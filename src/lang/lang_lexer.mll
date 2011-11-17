(*****************************************************************************

  Liquidsoap, a programmable audio stream generator.
  Copyright 2003-2011 Savonet team

  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details, fully stated in the COPYING
  file at the root of the liquidsoap distribution.

  You should have received a copy of the GNU General Public License
  along with this program; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

 *****************************************************************************)
{
  open Lang_parser
  open Lexing

  let incrline ?(n=1) lexbuf =
    lexbuf.lex_curr_p <- {
      lexbuf.lex_curr_p with
          pos_bol = lexbuf.lex_curr_p.pos_cnum ;
          pos_lnum = n + lexbuf.lex_curr_p.pos_lnum }

  let parse_time t =
    let g sub n =
      let s = Pcre.get_substring sub n in
        if s="" then None else
          Some (int_of_string (String.sub s 0 (String.length s - 1)))
    in
      try
        let pat = "^((?:\\d+w)?)((?:\\d+h)?)((?:\\d+m)?)((?:\\d+s)?)$" in
        let sub = Pcre.exec ~pat t in
        let g = g sub in
          List.map g [1;2;3;4]
      with Not_found ->
        let pat = "^((?:\\d+w)?)(\\d+h)(\\d+)$" in
        let sub = Pcre.exec ~pat t in
        let g = g sub in
          [g 1;g 2;Some (int_of_string (Pcre.get_substring sub 3));None]

  (** Process multiline string syntax à la Caml (backslash-newline).
    * This is done almost in-place, mutating the initial string. *)
  let process_string s =
    let copy,cut =
      let pos = ref 0 in
        (fun i ->
           if !pos<>i then s.[!pos] <- s.[i] ;
           incr pos),
        (fun () -> String.sub s 0 !pos)
    in
    let len = String.length s in
    let rec search i test =
      if i >= len then raise Not_found ;
      if test s.[i] then i else
        search (i+1) test
    in
    let rec parse i =
      if i = len-1 then copy i else
      if i = len-2 then begin copy i ; copy (i+1) end else
        parse
          (if s.[i] = '\\' && s.[i+1] = '\n' then
             let i = search (i+2) (fun c -> c <> ' ') in
               if s.[i] = '\\' && i+1<len && s.[i+1] = ' ' then i+1 else i
           else begin
             copy i ; i+1
           end)
    in
      (try parse 0 with _ -> ()) ;
      cut ()

  let process_string s = process_string (String.copy s)
}

let digit = ['0'-'9']
let decimal_literal =
  ['0'-'9'] ['0'-'9' '_']*
let hex_literal =
  '0' ['x' 'X'] ['0'-'9' 'A'-'F' 'a'-'f']['0'-'9' 'A'-'F' 'a'-'f' '_']*
let oct_literal =
  '0' ['o' 'O'] ['0'-'7'] ['0'-'7' '_']*
let bin_literal =
  '0' ['b' 'B'] ['0'-'1'] ['0'-'1' '_']*
let int_literal =
  decimal_literal | hex_literal | oct_literal | bin_literal

let utf8_letter = ['A'-'Z' 'a'-'z' '_' '\192'-'\214' '\216'-'\246' '\248'-'\255' ]

let var = utf8_letter (utf8_letter|digit|'\'')*
let record_field = utf8_letter (utf8_letter|digit|'\''|'.')*

let time =
    ( (digit+ 'w')? (digit+ 'h') (digit+))
  | ( (digit+ 'w') (digit+ 'h')? (digit+ 'm')? (digit+ 's')?)
  | ( (digit+ 'w')? (digit+ 'h') (digit+ 'm')? (digit+ 's')?)
  | ( (digit+ 'w')? (digit+ 'h')? (digit+ 'm') (digit+ 's')?)
  | ( (digit+ 'w')? (digit+ 'h')? (digit+ 'm')? (digit+ 's'))

rule token = parse
  | [' ' '\t' '\r']    { token lexbuf }
  | '\n'               { incrline lexbuf ; PP_ENDL }
  | (('#' [^'\n'] * '\n') + as doc)
      { let doc = Pcre.split ~pat:"\n" doc in
          incrline ~n:(List.length doc) lexbuf ;
          PP_COMMENT doc }

  | "%ifdef"   { PP_IFDEF }
  | "%endif"   { PP_ENDIF }
  | "%include" [' ' '\t']* '"' ([^ '"' '>' '\n']* as file) '"'
               { PP_INCLUDE file }
  | "%include" [' ' '\t']* '<' ([^ '"' '>' '\n']* as file) '>'
               { PP_INCLUDE (Filename.concat Configure.libs_dir file) }

  | '#' [^'\n']* eof { EOF }
  | eof { EOF }

  | "def"    { PP_DEF }
  | "fun"    { FUN }
  | "="      { GETS }
  | "end"    { END }
  | "begin"  { BEGIN }
  | "if"     { IF }
  | "then"   { THEN }
  | "else"   { ELSE }
  | "elsif"  { ELSIF }
  | "->"     { YIELDS }
  | "with"   { WITH }

  | "%ogg"    { OGG }
  | "%vorbis" { VORBIS }
  | "%flac"   { FLAC }
  | "%vorbis.cbr" { VORBIS_CBR }
  | "%vorbis.abr" { VORBIS_ABR }
  | "%theora" { THEORA }
  | "%external" { EXTERNAL }
  | "%dirac"  { DIRAC  }
  | "%speex"  { SPEEX }
  | "%wav" { WAV }
  | "%mp3" { MP3 }
  | "%mp3.cbr" { MP3 }
  | "%mp3.abr" { MP3_ABR }
  | "%mp3.vbr" { MP3_VBR }
  | "%aac+" { AACPLUS }
  | "%aacplus" { AACPLUS }
  | "%aac" { VOAACENC }

  | '[' { LBRA }
  | ']' { RBRA }
  | '(' { LPAR }
  | ')' { RPAR }
  | '{' { LCUR }
  | '}' { RCUR }
  | ',' { COMMA }
  | ':' { COLON }
  | ';' { SEQ }
  | ";;" { SEQSEQ }
  | '.' { FIELD }
  | "?" { QMARK }
  | "~" { TILD }
  | "-" { MINUS }
  | "not" { NOT }
  | "and" | "or"                   { BIN0 (Lexing.lexeme lexbuf) }
  | "!="
  | "==" | "<" | "<=" | ">" | ">=" { BIN1 (Lexing.lexeme lexbuf) }
  | "+" | "%" | "^" | "+." | "-."  { BIN2 (Lexing.lexeme lexbuf) }
  | "/" | "*." | "/."              { BIN3 (Lexing.lexeme lexbuf) }
  | "mod"                          { BIN3 (Lexing.lexeme lexbuf) }
  | "*"                            { TIMES }

  | "ref" { REF }
  | "!"   { GET }
  | ":="  { SET }

  | "true"  { BOOL true }
  | "false" { BOOL false }
  | int_literal { INT (int_of_string (Lexing.lexeme lexbuf)) }
  | (digit* as ipart) '.' (digit* as fpart)
      { let fpart =
          if fpart = "" then 0. else
            (float_of_string fpart) /.
            (10. ** (float_of_int (String.length fpart)))
        in
        let ipart = if ipart = "" then 0. else float_of_string ipart in
          FLOAT (ipart +. fpart) }

  | time as t                  { TIME (parse_time t) }
  | (time as t1) [' ' '\t' '\r']* '-' [' ' '\t' '\r']* (time as t2)
                               { INTERVAL (parse_time t1, parse_time t2) }

  | var as v                   { VAR v }
  | record_field as rf         { let rf = Pcre.split ~pat:"\\." rf in RECORD_FIELD (List.hd rf, List.tl rf) }

  | '\'' (([^'\''] | '\\' '\'')* as s) '\''   {
            String.iter (fun c -> if c = '\n' then incrline lexbuf) s ;
            let s = process_string s in
            STRING (Pcre.substitute ~pat:"\\\\n" ~subst:(fun _ -> "\n")
                     (Pcre.substitute ~pat:"\\\\r" ~subst:(fun _ -> "\r")
                      (Pcre.substitute ~pat:"\\\\'" ~subst:(fun _ -> "'") s))) }
  | '"' (([^'"'] | '\\' '"')* as s) '"'   {
            String.iter (fun c -> if c = '\n' then incrline lexbuf) s ;
            let s = process_string s in
            STRING (Pcre.substitute ~pat:"\\\\n" ~subst:(fun _ -> "\n")
                      (Pcre.substitute ~pat:"\\\\r" ~subst:(fun _ -> "\r")
                      (Pcre.substitute ~pat:"\\\\\"" ~subst:(fun _ -> "\"") s))) }
