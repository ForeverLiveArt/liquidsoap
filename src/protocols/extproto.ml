(*****************************************************************************

  Liquidsoap, a programmable audio stream generator.
  Copyright 2003-2013 Savonet team

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

open Source
open Dtools

let dlog = Log.make ["protocols";"external"]

exception Missing of string

let mktmp src =
  let file_ext =
    Printf.sprintf ".%s"
    (try
      Utils.get_ext src
     with
       | _ -> "osb")
  in
  Filename.temp_file "liq" file_ext

let resolve proto program command s ~log maxtime =
  let s = proto ^ ":" ^ s in
  (* We create a fresh stdin for the process,
   * and another one, unused by the child, on which we'll wait for EOF
   * as a mean to detect termination. *)
  let (iR,iW) = Unix.pipe () in
  let (xR,xW) = Unix.pipe () in
  let local = mktmp s in
  try
    let pid =
      Unix.create_process program (command program s local)
        iR xW Unix.stderr
    in
    dlog#f 4 "Executing %s %S %S" program s local;
    let timeout () = max 0. (maxtime -. Unix.gettimeofday ()) in
      Unix.close iR ;
      let prog_stdout = ref "" in
      let rec task () = 
        let timeout = timeout () in
        { Duppy.Task.
          priority = Tutils.Non_blocking;
          events   = [`Read xR; `Delay timeout];
          handler  = fun l ->
          if List.mem (`Delay timeout) l then
           begin
            Unix.kill pid 9;
            []
           end
          else
           begin
            let s = String.create 1024 in
            let ret = Unix.read xR s 0 1024 in
            if ret > 0 then
             begin
               prog_stdout := !prog_stdout ^ (String.sub s 0 ret);
               [task ()]
             end
            else
              []
           end }
      in
      Duppy.Task.add Tutils.scheduler (task ());
      let (p,code) = Unix.waitpid [] pid in
        assert (p <> 0) ;
        dlog#f 4 "Download process finished (%s)"
          (match code with
          | Unix.WSIGNALED _ -> "killed"
          | Unix.WEXITED 0 -> "ok"
          | _ -> "error") ;
        Unix.close iW ;
        Unix.close xW ;
        if code = Unix.WEXITED 0 then
          [Request.indicator ~temporary:true !prog_stdout]
        else begin
          log "Download failed: timeout, invalid URI ?" ;
          ( try Unix.unlink !prog_stdout with _ -> () ) ;
          []
        end
  with Missing progname ->
    dlog#f 2 "Could not find download program %s" progname;
    []

let conf =
  Dtools.Conf.void ~p:(Configure.conf#plug "extproto") "External protocol resolvers"
    ~comments:["Settings for the external protocol resolver"]

let conf_server_name =
  Dtools.Conf.bool ~p:(conf#plug "use_server_name") "Use server-provided name"
    ~d:false ~comments:["Use server-provided name."]

let extproto = [
  Configure.get_program,
  [ "http";"https";"ftp" ],
  (fun prog src dst ->
    begin try
      ignore(Utils.which "wget")
    with Not_found -> raise (Missing "wget") end;
    if conf_server_name#get then 
      [|prog;src;dst;"true"|]
    else
      [|prog;src;dst|])
]

let () =
  (* Enabling of protocols rely on the presence of the programs.
   * The detection must be done at startup, so that --list-plugins shows the
   * enabled protocols. But we delay logging for Init.at_start time, so that
   * logs shows enabled/disabled protocols. *)
  List.iter
    (fun (prog,protos,command) ->
       try
         let prog = Utils.which prog in
           dlog#f 3 "Found %S." prog ;
           List.iter
             (fun proto ->
                Request.protocols#register
                  ~sdoc:(Printf.sprintf "Fetch files using %S." prog)
                  proto
                  { Request.resolve = resolve proto prog command ;
                    Request.static = false })
             protos
       with
         | Not_found ->
             dlog#f 3 "Didn't find %S." prog
    )
    extproto
