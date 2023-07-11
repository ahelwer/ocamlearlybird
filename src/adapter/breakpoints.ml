open Ground
open Debug_protocol_ex
open Debugger
open Util

type my_bp = {
  dbp : Debugger.source_breakpoint;
  is_line_bp : bool;
  dbp_version : int ref;
}

let run ~init_args ~launch_args ~dbg rpc =
  ignore init_args;
  ignore launch_args;
  ignore dbg;
  Lwt.pause ();%lwt
  let alloc_handle = Unique_id.make_alloc 1 in
  let source_bp_tbl = Hashtbl.create 0 in
  Debug_rpc.set_command_handler rpc
    (module Set_breakpoints_command)
    (fun arg ->
      let source = arg.source.path |> Option.get in
      let prev_breakpoints =
        Hashtbl.find_opt source_bp_tbl source |> Option.value ~default:[]
      in
      prev_breakpoints
      |> List.iter (fun bp -> Debugger.remove_breakpoint dbg bp.dbp);
      Hashtbl.remove source_bp_tbl source;
      let make_breakpoint dbp is_line_bp =
        if dbp.bp_active then
          let pos =
            if is_line_bp then dbp.bp_loc.pos else dbp.bp_resolved_loc.pos
          in
          Breakpoint.make ~id:(Some dbp.bp_id) ~verified:true
            ~source:
              (Some (Source.make ~path:(Some dbp.bp_resolved_loc.source) ()))
            ~line:(Some (fst pos |> line_to_client ~init_args))
            ~column:(Some (snd pos |> column_to_client ~init_args))
            ()
        else Breakpoint.make ~id:(Some dbp.bp_id) ~verified:false ()
      in
      let breakpoints =
        arg.breakpoints |> Option.value ~default:[] |> List.to_seq
        |> Seq.map (fun (bp : Source_breakpoint.t) ->
               let id = alloc_handle () in
               let dbp_version = ref 0 in
               let is_line_bp = bp.column |> Option.is_none in
               let on_change dbp =
                 if !dbp_version <> dbp.bp_version then (
                   dbp_version := dbp.bp_version;
                   if dbp.bp_active then
                     Debug_rpc.send_event rpc
                       (module Breakpoint_event)
                       (Breakpoint_event.Payload.make ~reason:Changed
                          ~breakpoint:(make_breakpoint dbp is_line_bp))
                   else
                     Debug_rpc.send_event rpc
                       (module Breakpoint_event)
                       (Breakpoint_event.Payload.make ~reason:Changed
                          ~breakpoint:
                            (Breakpoint.make ~id:(Some id) ~verified:false ())))
                 else Lwt.return ()
               in
               let dbp =
                 Debugger.set_breakpoint dbg ~id ~source
                   ~line:(bp.line |> line_from_client ~init_args)
                   ?column:
                     (bp.column |> Option.map (column_from_client ~init_args))
                   ~on_change ()
               in
               dbp_version := dbp.bp_version;
               { dbp; is_line_bp; dbp_version })
        |> Seq.tap (fun bp ->
               let bps =
                 Hashtbl.find_opt source_bp_tbl source
                 |> Option.value ~default:[]
               in
               Hashtbl.replace source_bp_tbl source (bp :: bps))
        |> Seq.map (fun { dbp; is_line_bp; _ } ->
               make_breakpoint dbp is_line_bp)
        |> List.of_seq
      in
      Lwt.return Set_breakpoints_command.Result.(make ~breakpoints ()));
  Debug_rpc.set_command_handler rpc
    (module Breakpoint_locations_command)
    (fun arg ->
      let breakpoints =
        Debugger.breakpoint_locations dbg
          (arg.source.path |> Option.get)
          ~line:(arg.line |> line_from_client ~init_args)
          ?column:(arg.column |> Option.map (column_from_client ~init_args))
          ?end_line:(arg.end_line |> Option.map (line_from_client ~init_args))
          ?end_column:
            (arg.end_column |> Option.map (column_from_client ~init_args))
          ()
      in
      let breakpoints =
        breakpoints
        |> List.map (fun loc ->
               Breakpoint_location.make
                 ~line:(fst loc.pos |> line_to_client ~init_args)
                 ~column:(Some (snd loc.pos |> column_to_client ~init_args))
                 ())
      in
      Lwt.return Breakpoint_locations_command.Result.(make ~breakpoints ()));
  Lwt.join []
