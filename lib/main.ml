(*
 * Copyright (c) 2013 Thomas Gazagnaire <thomas@gazagnaire.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

open Cmdliner

let global_option_section = "COMMON OPTIONS"
let help_sections = [
  `S global_option_section;
  `P "These options are common to all commands.";
]

(* Helpers *)
let mk_flag ?section flags doc =
  let doc = Arg.info ?docs:section ~doc flags in
  Arg.(value & flag & doc)

let mk_opt ?section flags value doc conv default =
  let doc = Arg.info ?docs:section ~docv:value ~doc flags in
  Arg.(value & opt conv default & doc)

let term_info title ~doc ~man =
  let man = man @ help_sections in
  Term.info ~sdocs:global_option_section ~doc ~man title

let arg_list name doc conv =
  let doc = Arg.info ~docv:name ~doc [] in
  Arg.(value & pos_all conv [] & doc)

let no_install = mk_flag ["no-install"] "Do not auto-install OPAM packages."
let xen = mk_flag ["xen"] "Generate a Xen microkernel. Do not use in conjunction with --unix-*."
let unix = mk_flag ["unix"] "Use unix-direct backend. Do not use in conjunction with --xen."
let socket = mk_flag ["socket"] "Use networking socket backend. Do not use in conjunction with --xen."
(* Select the operating mode from command line flags *)
let mode unix xen socket =
  match xen,unix,socket with
  |true,true,_ -> failwith "Cannot specify --unix and --xen together."
  |true,_,true -> failwith "Cannot specify --xen and --socket together."
  |true,false,false -> `xen
  |false,_,true -> `unix `socket
  |false,_,false -> `unix `direct

let switch = mk_opt ["switch"]
    "SWITCH" "Use $(docv) as the current compiler switch."
    Arg.(some string) None

let file =
  let doc = Arg.info ~docv:"FILE"
    ~doc:"Configuration file for Mirari.  If not specified, the current directory will be scanned.  If one file ending with the $(i,conf) extension is found, that will be used.  No files, or multiple configuration files, will result in an error unless one is explicitly specified on the command line." [] in
  Arg.(value & pos 0 (some string) None & doc)

(* CONFIGURE *)
let configure_doc = "Configure a Mirage application."
let configure =
  let doc = configure_doc in
  let man = [
    `S "DESCRIPTION";
    `P "The $(b,configure) command initializes a fresh Mirage application."
  ] in
  let configure unix xen socket compiler no_install file =
    if unix && xen then `Help (`Pager, Some "configure")
    else
      `Ok (Mirari.configure ~mode:(mode unix xen socket) ~no_install file) in
  Term.(ret (pure configure $ unix $ xen $ socket $ switch $ no_install $ file)), term_info "configure" ~doc ~man

(* BUILD *)
let build_doc = "Build a Mirage application."
let build =
  let doc = build_doc in
  let man = [
    `S "DESCRIPTION";
    `P "Build an already configured application."
  ] in
  let build unix xen socket compiler file =
    if unix && xen then `Help (`Pager, Some "build")
    else
      `Ok (Mirari.build ~mode:(mode unix xen socket) file) in
  Term.(ret (pure build $ unix $ xen $ socket $ switch $ file)), term_info "build" ~doc ~man

(* RUN *)
let run_doc = "Run a Mirage application."
let run =
  let doc = run_doc in
  let man = [
    `S "DESCRIPTION";
    `P "Run a Mirage application on the selected backend."] in
  let run unix xen socket compiler file =
    if unix && xen then `Help (`Pager, Some "run")
    else
      `Ok (Mirari.run ~mode:(mode unix xen socket) file) in
  Term.(ret (pure run $ unix $ xen $ socket $ switch $ file)), term_info "run" ~doc ~man

(* CLEAN *)
let clean_doc = "Clean auto-generated files."
let clean =
  let doc = clean_doc in
  let man = [
    `S "DESCRIPTION";
    `P "Clean auto-generated files generated by mirari (and obuild). This is useful to implement the clean target on Makefiles."
  ] in
  Term.(pure Mirari.clean $ pure ()), term_info "clean" ~doc ~man

(* HELP *)
let help =
  let doc = "Display help about Mirari and Mirari commands." in
  let man = [
    `S "DESCRIPTION";
    `P "Prints help about Mirari commands.";
    `P "Use `$(mname) help topics' to get the full list of help topics.";
  ] in
  let topic =
    let doc = Arg.info [] ~docv:"TOPIC" ~doc:"The topic to get help on." in
    Arg.(value & pos 0 (some string) None & doc )
  in
  let help man_format cmds topic = match topic with
    | None       -> `Help (`Pager, None)
    | Some topic ->
      let topics = "topics" :: cmds in
      let conv, _ = Arg.enum (List.rev_map (fun s -> (s, s)) topics) in
      match conv topic with
      | `Error e -> `Error (false, e)
      | `Ok t when t = "topics" -> List.iter print_endline cmds; `Ok ()
      | `Ok t -> `Help (man_format, Some t) in

  Term.(ret (pure help $Term.man_format $Term.choice_names $topic)),
  Term.info "help" ~doc ~man

let default =
  let doc = "Mirage application builder" in
  let man = [
    `S "DESCRIPTION";
    `P "Mirari is a Mirage application builder. It glues together a set of libaries and configuration (e.g. network and storage) into a standalone microkernel or UNIX binary.";
    `P "Use either $(b,mirari <command> --help) or $(b,mirari help <command>) \
        for more information on a specific command.";
  ] @  help_sections
  in
  let usage () =
    Printf.printf
      "usage: mirari [--version]\n\
      \              [--help]\n\
      \              <command> [<args>]\n\
      \n\
      The most commonly used opam commands are:\n\
      \    configure   %s\n\
      \    build       %s\n\
      \n\
      See 'opam help <command>' for more information on a specific command.\n%!"
      configure_doc build_doc in
  Term.(pure usage $ pure ()),
  Term.info "mirari"
    ~version:(Path_generated.project_version)
    ~sdocs:global_option_section
    ~doc
    ~man

let commands = [
  configure;
  build;
  run;
  clean;
]

let () =
  (* Do not die on Ctrl+C: necessary when mirari has to cleanup things
     (like killing running kernels) before terminating. *)
  Sys.catch_break true;
  match Term.eval_choice default commands with
  | `Error _ -> exit 1
  | _ -> ()
