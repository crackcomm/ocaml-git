(*
 * Copyright (c) 2013-2017 Thomas Gazagnaire <thomas@gazagnaire.org>
 * and Romain Calascibetta <romain.calascibetta@gmail.com>
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
open Carton

(** The Git Reference module. *)
type t

val of_string : string -> (t, [> `Msg of string ]) result

val v : string -> t

val add_seg : t -> string -> t

val append : t -> t -> t

val segs : t -> string list

val pp : t Fmt.t

val head : t

val master : t

val ( / ) : t -> string -> t

val ( // ) : t -> t -> t

val to_string : t -> string

val equal : t -> t -> bool

val compare : t -> t -> int

module Map : Map.S with type key = t

module Set : Set.S with type elt = t

type 'uid contents = Uid of 'uid | Ref of t

val equal_contents :
  equal:('uid -> 'uid -> bool) -> 'uid contents -> 'uid contents -> bool

val compare_contents :
  compare:('uid -> 'uid -> int) -> 'uid contents -> 'uid contents -> int

val pp_contents : pp:'uid Fmt.t -> 'uid contents Fmt.t

val uid : 'uid -> 'uid contents

val ref : t -> 'uid contents







end

end
