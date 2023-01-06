(*
 * SPDX-FileCopyrightText: 2022 Tarides <contact@tarides.com>
 *
 * SPDX-License-Identifier: ISC
 *)

open Eio
open Bigarray

let make_memory_map () = Array2.create char c_layout 1024 4096
let large_test_record i = ("KEY_" ^ string_of_int i, String.make 256 'x')

module Basic = struct
  let test_single_record =
    Alcotest.test_case "insert an retrieve a single record" `Quick (fun () ->
        let memory_map = make_memory_map () in

        let db = Omdb.init memory_map in

        let key = "MY_KEY" in
        let value = "MY_VALUE" in

        Omdb.update db key (Fun.const @@ Some value);

        Alcotest.(
          check (option string) "Can retrieve inserted value" (Some value)
          @@ Omdb.find db key))

  let test_multiple_leaves =
    Alcotest.test_case "insert more records than what fits in a leaf" `Quick
      (fun () ->
        let memory_map = make_memory_map () in

        let db = Omdb.init memory_map in

        Seq.init 10 large_test_record
        |> Seq.iter (fun (key, value) ->
               Omdb.update db key (Fun.const @@ Some value));

        Seq.init 10 large_test_record
        |> Seq.iter (fun (key, value) ->
               Alcotest.(
                 check (option string) "Can retrieve inserted value"
                   (Some value)
                 @@ Omdb.find db key)))

  let test_multiple_nodes =
    Alcotest.test_case "insert more records than fits in two leaves" `Quick
      (fun () ->
        let memory_map = make_memory_map () in

        let db = Omdb.init memory_map in

        (* TODO figure out heuristics to compute how many records of
           what size need to be inserted *)
        Seq.init 20 large_test_record
        |> Seq.iter (fun (key, value) ->
               Omdb.update db key (Fun.const @@ Some value));

        Seq.init 20 large_test_record
        |> Seq.iter (fun (key, value) ->
               Alcotest.(
                 check (option string) "Can retrieve inserted value"
                   (Some value)
                 @@ Omdb.find db key)))

  let test_cases =
    [ test_single_record; test_multiple_leaves; test_multiple_nodes ]
end

module Property_based = struct
  module Map = Map.Make (String)

  let gen_key = QCheck2.Gen.(small_nat |> map string_of_int)

  (* let gen_value = QCheck2.Gen.string_printable *)
  let gen_value = QCheck2.Gen.(small_nat |> map string_of_int)

  (* type event = Omdb.key * Omdb.value *)

  let gen_events =
    let open QCheck2.Gen in
    pair gen_key gen_value |> map (fun (k, v) -> (k, v)) |> list

  let test_insert_recrods =
    QCheck2.Test.make ~count:10 ~name:"Insert records" gen_events (fun events ->
        (* Init a databaes *)
        let db = Omdb.init (Array2.create char c_layout 1024 4096) in

        (* Insert values into map and database *)
        let map =
          List.fold_left
            (fun map event ->
              match event with
              | key, value ->
                  let () =
                    Omdb.update db key (Fun.const @@ Option.some value)
                  in
                  Map.update key (Fun.const @@ Option.some value) map)
            Map.empty events
        in

        (* Check that all values in map are in the database as well. *)
        (* Map.to_seq map *)
        (* |> Seq.for_all *)
        (*      (fun key value -> *)
        (*        match Omdb.find db key with *)
        (*        | Some value_db -> *)
        (*            Alcotest.( *)
        (*              check string "value in DB matches expectation" value *)
        (*                value_db); *)
        (*            true *)
        (*        | None -> false) *)
        (*      map; *)
        map |> Map.to_seq
        |> Seq.for_all (fun (key, value) ->
               match Omdb.find db key with
               | Some value_db -> value = value_db
               | None ->
                   traceln "FAILURE: key-value (%s - %s) not found in DB" key
                     value;

                   traceln "FAILURE: events: %a"
                     Fmt.(
                       list ~sep:semi @@ parens @@ pair ~sep:comma string string)
                     events;

                   false))

  let test_cases = [ QCheck_alcotest.to_alcotest test_insert_recrods ]
end

let () =
  Alcotest.run "Omdb"
    [
      ("Basic", Basic.test_cases); ("Property-based", Property_based.test_cases);
    ]
