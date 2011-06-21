(*
    Copyright © 2011 MLstate

    This file is part of OPA.

    OPA is free software: you can redistribute it and/or modify it under the
    terms of the GNU Affero General Public License, version 3, as published by
    the Free Software Foundation.

    OPA is distributed in the hope that it will be useful, but WITHOUT ANY
    WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
    FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for
    more details.

    You should have received a copy of the GNU Affero General Public License
    along with OPA. If not, see <http://www.gnu.org/licenses/>.
*)
(*
    @author Jérémie Lumbroso
    @author François-Régis Sinot
**)


exception Id_overflow

(**
   Name creation, with namespaces.

   Use this generator if you wish to turn various occurrences of, say, ["x"] and ["y"] into
   ["x0"], ["x1"], ["x2"], ["y0"], ["y1"], ...

   Generate a new unique name.

   Usage: [let fresh ... = let f = fresh_named_factory ?init_size transf in f ...].

   [transf] is any transformer from triple (name, description, index), typically a custom printer

   {b Note} Names produced are guaranteed unique only with respect to each other,
   and only if your [transf] is consistent with the way you generate new items.
   In other words, the first name you will obtain by calling [fresh "x" "foo"] is
   always e.g. ["x_0___AS_foo"].
*)
type stamp = int
type name = string
type descr = string
type t_fresh = stamp * int * name * descr

let compare ((l1,_,_,_):t_fresh) (r1,_,_,_) =
  compare l1 r1 (* the stamp is unique *)
let equal ((l1,_,_,_):t_fresh) (r1,_,_,_) =
  l1 = r1
let hash ((i,_,_,_):t_fresh) = Hashtbl.hash i

let default_print (_,index,name,descr) =
  Printf.sprintf "%s_%d_%s" name index descr

let inner_fresh_named_factory ?(init_size=32) transf =
  let counter = ref (1 : stamp) in
  let new_stamp () =
    let stamp = !counter in
    if stamp < max_int && 0 - stamp > min_int then
      begin
        incr counter;
        stamp
      end
    else
      raise Id_overflow
  in
  let table = Hashtbl.create init_size in
  let rev_table = Hashtbl.create init_size in
  let next = fun ?(name="") ?(descr="") () ->
    let key = (name, descr) in
    let index =
      try
        Hashtbl.find table key
      with
        Not_found -> (-1)
    in
    let index = if index < max_int then index + 1 else raise Id_overflow in
    Hashtbl.replace table key index;
    transf (new_stamp (), index, name, descr) in

  (* for the specification, see the comment about [compare] in [FRESH] *)
  let prev ?(name="") ?(descr="") () =
    let key = (name, descr) in
    let index =
      try
        Hashtbl.find rev_table key
      with
        Not_found -> 0 (* don't start at 1 or else you can create collisions
                        * with the names generated by next *)
    in
    let index = if index > min_int then index - 1 else raise Id_overflow in
    Hashtbl.replace rev_table key index;
    transf (0 - new_stamp (), index, name, descr) in

  next, prev

let fresh_named_factory ?(init_size=32) transf =
  let (next, _) = inner_fresh_named_factory ~init_size transf in
  next

let default_fresh_named_factory () =
  fresh_named_factory default_print

module type FRESH =
sig
  type t
  val next : ?name:string -> ?descr:string -> unit -> t
  val prev : ?name:string -> ?descr:string -> unit -> t

  val compare : t -> t -> int
  (**
     values with the same name and descr are guaranteed to be
     generated in increasing order by [next] and decreasing order by [prev]
     ie calling [next ~name ~descr] will give you the greatest value with the
     given name and descr (until you call [next] again) and [prev] will give you
     the lowest value (until the you [prev] again)
  *)

  val equal  : t -> t -> bool
  val to_string : t -> string
  val to_int : t -> int
  val hash : t -> int

  (**
     export just the name, e.g. for manual printing
     This is used for errors messages, we try to print types with
     the name of type variables as there where in the source code.
  *)
  val name : t -> string

  (**
     This is like a next, but with the property that the name and the description
     of the fresh is taken from the given fresh.
     This is used in order not to loose the original names of TypeVariables.
  *)
  val refresh : t -> t
end

module type BRAND =
sig
  val printer : t_fresh -> string
end

module DefaultBrand : BRAND =
struct
  let printer (_, id, _, _) =
    let rec aux count =
      let count =  count / 26
      and charc = 97 + count mod 26 in
      let char = String.make 1 (Char.chr charc) in
      if count = 0 then char
      else aux (count - 1) ^ char
    in
      "'" ^ aux id
end

module FreshGen (Brand : BRAND) : FRESH =
struct
  type t = t_fresh

  let name (_, _, name, _) = name
  let next, prev = inner_fresh_named_factory (fun t -> t) (* hidden be signature *)

  let refresh (_, _, name, descr) = next ~name ~descr ()

  let hash = hash
  let compare = compare
  let equal = equal
  let to_string = Brand.printer
  let to_int (stamp, _index, _name, _descr) = stamp
end

(**
   Some simpler fresh generators without names.
*)

let fresh_factory (transf : int -> 'a) : (unit -> 'a) =
  let index = ref (-1) in
  fun () ->
    if !index < max_int then incr index else raise Id_overflow;
    transf !index

(** Example *)
(** let get_stringint_fresh = fresh_factory (fun t -> Printf.sprintf "_%010d" t);; *)

module Int =
struct
  (* global int counter -- better use local, specialized versions rather than this *)
  let get = fresh_factory (fun t -> t);;
end
