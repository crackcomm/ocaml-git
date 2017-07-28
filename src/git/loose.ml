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

module type S =
sig
  module Path : Path.S
  module FileSystem : Fs.S

  include Value.S

  module Value : Value.S with type Hash.t = Hash.t
                          and module Digest = Digest
                          and module Inflate = Inflate
                          and module Deflate = Deflate

  type error = [ FileSystem.File.error
               | FileSystem.Dir.error
               | D.error
               | E.error ]

  val pp_error : error Fmt.t

  val exists  :
    root:Path.t ->
    Hash.t -> bool Lwt.t

  val read    :
    root:Path.t ->
    window:Inflate.window ->
    ztmp:Cstruct.t ->
    dtmp:Cstruct.t ->
    raw:Cstruct.t ->
    Hash.t -> (t, error) result Lwt.t

  val inflate :
    root:Path.t ->
    window:Inflate.window ->
    ztmp:Cstruct.t ->
    dtmp:Cstruct.t ->
    raw:Cstruct.t ->
    Hash.t -> ([ `Commit | `Blob | `Tree | `Tag ] * Cstruct.t, error) result Lwt.t

  val inflate_wa :
    root:Path.t ->
    window:Inflate.window ->
    ztmp:Cstruct.t ->
    dtmp:Cstruct.t ->
    raw:Cstruct.t ->
    result:Cstruct.t ->
    Hash.t -> ([ `Commit | `Blob | `Tree | `Tag ] * Cstruct.t, error) result Lwt.t

  val list    :
    root:Path.t ->
    Hash.t list Lwt.t

  val size    :
    root:Path.t ->
    window:Inflate.window ->
    ztmp:Cstruct.t ->
    dtmp:Cstruct.t ->
    raw:Cstruct.t ->
    Hash.t -> (int64, error) result Lwt.t

  val write :
    root:Path.t ->
    ?capacity:int ->
    ?level:int ->
    ztmp:Cstruct.t ->
    raw:Cstruct.t ->
    t -> (Hash.t * int, error) result Lwt.t
end

module Make
    (Digest : Ihash.IDIGEST with type t = Bytes.t
                            and type buffer = Cstruct.t)
    (Path : Path.S)
    (FileSystem : Fs.S with type path = Path.t
                        and type File.error = [ `System of string ]
                        and type File.raw = Cstruct.t)
    (Inflate : Common.INFLATE)
    (Deflate : Common.DEFLATE)
  : S with type Hash.t = Digest.t
       and module Digest = Digest
       and module Path = Path
       and module FileSystem = FileSystem
       and module Inflate = Inflate
       and module Deflate = Deflate
= struct
  module Path = Path
  module FileSystem = FileSystem

  module Value = Value.Make(Digest)(Inflate)(Deflate)

  include Value

  type error =
    [ FileSystem.File.error
    | FileSystem.Dir.error
    | D.error
    | E.error ]

  let pp_error ppf = function
    | #D.error as err -> D.pp_error ppf err
    | #E.error as err -> E.pp_error ppf err
    | #FileSystem.File.error as err -> FileSystem.File.pp_error ppf err

  let hash_get : Hash.t -> int -> int = fun h i -> Char.code @@ Bytes.get h i

  let explode hash =
    Fmt.strf "%02x" (hash_get hash 0),
    let buf = Buffer.create ((Digest.length - 1) * 2) in
    let ppf = Fmt.with_buffer buf in

    for i = 1 to Digest.length - 1
    do Fmt.pf ppf "%02x%!" (hash_get hash i) done;

    Buffer.contents buf

  let exists ~root hash =
    let open Lwt.Infix in

    let first, rest = explode hash in

    FileSystem.File.exists Path.(root / "objects" / first / rest)
    >>= function Ok v -> Lwt.return true
               | Error (`System err) -> Lwt.return false

  (* XXX(dinosaure): it's come from [digestif] library. *)
  let of_hex hex =
    let code x = match x with
      | '0' .. '9' -> Char.code x - 48
      | 'A' .. 'F' -> Char.code x - 55
      | 'a' .. 'z' -> Char.code x - 87
      | _ -> raise (Invalid_argument "of_hex")
    in

    let wsp = function ' ' | '\t' | '\r' | '\n' -> true | _ -> false in
    let fold_s f a s = let r = ref a in Bytes.iter (fun x -> r := f !r x) s; !r in

    fold_s
      (fun (res, i, acc) -> function
         | chr when wsp chr -> (res, i, acc)
         | chr ->
           match acc, code chr with
           | None, x -> (res, i, Some (x lsl 4))
           | Some y, x -> Bytes.set res i (Char.unsafe_chr (x lor y)); (res, succ i, None))
      (Bytes.create Digest.length, 0, None)
      hex
    |> function (_, _, Some _)  -> raise (Invalid_argument "of_hex")
              | (res, i, _) ->
                if i = Digest.length
                then res
                else (for i = i to Digest.length - 1 do Bytes.set res i '\000' done; res)

  (* XXX(dinosaure): make this function more resilient: if [of_hex] fails), avoid the path. *)
  let list ~root =
    let open Lwt.Infix in

    FileSystem.Dir.contents
      ~dotfiles:false
      ~rel:true
      Path.(root / "objects")
    >>= function
    | Error (`System sys_err) ->
      Lwt.return []
    | Ok firsts ->
      Lwt_list.fold_left_s
        (fun acc first ->
           FileSystem.Dir.contents ~dotfiles:false ~rel:true (Path.(append (root / "objects") first))
           >>= function
           | Ok paths ->
             Lwt_list.fold_left_s
               (fun acc path ->
                  try
                    (of_hex Path.(Bytes.unsafe_of_string ((to_string first) ^ (to_string path))))
                    |> fun v -> Lwt.return (v :: acc)
                  with _ -> Lwt.return acc)
               acc
               paths
           | Error (`System err) -> Lwt.return acc)
        [] firsts

  type 't decoder =
    (module Common.DECODER with type t = 't
                            and type raw = Cstruct.t
                            and type init = Inflate.window * Cstruct.t * Cstruct.t
                            and type error = [ `Decoder of string
                                             | `Inflate of Inflate.error ])

  let gen (type t) ~root ~window ~ztmp ~dtmp ~raw (decoder : t decoder) hash : (t, error) result Lwt.t =
    let module D = (val decoder) in

    let first, rest = explode hash in
    let decoder     = D.default (window, ztmp, dtmp) in

    let open Lwt.Infix in

    FileSystem.File.open_r ~mode:0o400 ~lock:(Lwt.return ()) Path.(root / "objects" / first / rest)
    >>= function Error (#FileSystem.File.error as err) -> Lwt.return (Error err)
               | Ok read ->

    let rec loop decoder = match D.eval decoder with
      | `Await decoder ->
        FileSystem.File.read raw read >>=
        (function
          | Error (#FileSystem.File.error as err) -> Lwt.return (Error err)
          | Ok n -> match D.refill (Cstruct.sub raw 0 n) decoder with
            | Ok decoder -> loop decoder
            | Error (#D.error as err) -> Lwt.return (Error err))
      | `End (rest, value) -> Lwt.return (Ok value)
      | `Error (res, (#D.error as err)) -> Lwt.return (Error err)
    in

    loop decoder

  let read ~root ~window ~ztmp ~dtmp ~raw hash =
    gen ~root ~window ~ztmp ~dtmp ~raw (module D) hash

  module HeaderAndBody =
  struct
    type t = [ `Commit | `Blob | `Tag | `Tree ] * Cstruct.t

    let kind =
      let open Angstrom in

      (string "blob" *> return `Blob
      <|> string "commit" *> return `Commit
      <|> string "tag" *> return `Tag
      <|> string "tree" *> return `Tree)
    (* XXX(dinosaure): come from [Value] but not exposed in the interface. *)

    let int64 =
      let open Angstrom in
      take_while (function '0' .. '9' -> true | _ -> false) >>| Int64.of_string

    let to_end cs =
      let open Angstrom in
      let pos = ref 0 in

      fix @@ fun m ->
      available >>= function
      | 0 ->
        peek_char
        >>= (function
            | Some _ -> m
            | None ->
              return (Cstruct.sub cs 0 !pos))
      | n -> take n >>= fun chunk ->
        (* XXX(dinosaure): this code [blit] only what is possible to copy to
           [cs]. It can be happen than we don't store all of the git object in
           [cs] but in specific context (when we want to decode a source of a
           delta-ification), this is what we want, store only what is needed and
           limit the memory consumption.

           This code is close to the [~result] argument of [decoder] and, in
           fact, if we don't want to store the git object in a specific user
           defined buffer, we ensure to allocate what is needed to store all of
           the git object. *)
        let n' = min n (Cstruct.len cs - !pos) in
        Cstruct.blit_from_string chunk 0 cs !pos n';
        pos := !pos + n;

        if n = 0 then return cs else m

    let decoder ~result =
      let open Angstrom in
      kind <* take 1
      >>= fun kind -> int64 <* advance 1
      >>= fun length -> (match result with
      | Some result -> to_end result
      | None -> to_end (Cstruct.create (Int64.to_int length)))
      >>| fun cs -> kind, cs
  end

  module I = Helper.MakeInflater(Inflate)(struct include HeaderAndBody let decoder = decoder ~result:None end)

  let inflate ~root ~window ~ztmp ~dtmp ~raw hash =
    gen ~root ~window ~ztmp ~dtmp ~raw (module I) hash

  let inflate_wa ~root ~window ~ztmp ~dtmp ~raw ~result hash =
    let module P = Helper.MakeInflater(Inflate)(struct include HeaderAndBody let decoder = decoder ~result:(Some result) end) in
    gen ~root ~window ~ztmp ~dtmp ~raw (module I) hash

  module HeaderOnly =
  struct
    type t = [ `Commit | `Blob | `Tag | `Tree ] * int64

    let kind = HeaderAndBody.kind
    let int64 = HeaderAndBody.int64
    let decoder =
      let open Angstrom in
      kind <* take 1
      >>= fun kind -> int64 <* advance 1
      >>| fun length -> kind, length
  end

  module S = Helper.MakeInflater(Inflate)(HeaderOnly)

  let size ~root ~window ~ztmp ~dtmp ~raw hash =
    let first, rest = explode hash in
    let decoder     = S.default (window, ztmp, dtmp) in

    let open Lwt.Infix in

    FileSystem.File.open_r ~mode:0o400 ~lock:(Lwt.return ()) Path.(root / "objects" / first / rest)
    >>= function Error (#FileSystem.File.error as err) -> Lwt.return (Error err)
               | Ok read ->

    let rec loop decoder = match S.eval decoder with
      | `Await decoder ->
        FileSystem.File.read raw read >>=
        (function
          | Error (#FileSystem.File.error as err) -> Lwt.return (Error err)
          | Ok n -> match S.refill (Cstruct.sub raw 0 n) decoder with
            | Ok decoder -> loop decoder
            | Error (#S.error as err) -> Lwt.return (Error err))
      | `End (rest, (kind, size)) -> Lwt.return (Ok size)
      (* XXX(dinosaure): [gen] checks if we consume all of the input. But
        for this compute, we don't need to compute all. It's
        redundant. *)
      | `Error (res, (#S.error as err)) -> Lwt.return (Error err)
    in

    loop decoder

  let write ~root ?(capacity = 0x100) ?(level = 4) ~ztmp ~raw value =
    let hash        = digest value in
    let first, rest = explode hash in
    let encoder     = E.default (capacity, value, level, ztmp) in

    let open Lwt.Infix in

    FileSystem.File.open_w ~mode:644 ~lock:(Lwt.return ()) Path.(root / "objects" / first / rest)
    >>= function Error (#FileSystem.File.error as err) -> Lwt.return (Error err)
               | Ok write ->

    (* XXX(dinosaure): replace this code by [Helper.safe_encoder_to_file]. *)
    let rec loop encoder = match E.eval raw encoder with
      | `Flush encoder ->
        (if E.used encoder > 0
         then FileSystem.File.write raw ~len:(E.used encoder) write
         else Lwt.return (Ok 0)) >>=
        (function
          | Error (#FileSystem.File.error as err) -> Lwt.return (Error err)
          | Ok n ->
            if n = E.used encoder
            then loop (E.flush 0 (Cstruct.len raw) encoder)
            else begin
              let rest = E.used encoder - n in
              Cstruct.blit raw n raw 0 rest;
              loop (E.flush rest (Cstruct.len raw - rest) encoder)
            end)
      | `End (encoder, w) ->
        if E.used encoder > 0
        then begin
          FileSystem.File.write raw ~len:(E.used encoder) write >>=
          (function
            | Error (#FileSystem.File.error as err) -> Lwt.return (Error err)
            | Ok n ->
              if n = E.used encoder
              then loop (E.flush 0 (Cstruct.len raw) encoder)
              else begin
                let rest = E.used encoder - n in
                Cstruct.blit raw n raw 0 rest;
                loop (E.flush rest (Cstruct.len raw - rest) encoder)
              end)
        end else
          FileSystem.File.close write
          >|= (function Ok ()-> Ok w | Error (#FileSystem.File.error as err) -> Error err)
      | `Error (#E.error as err) -> Lwt.return (Error err)
    in

    loop encoder >|= function Ok w -> Ok (hash, w) | Error err -> Error err
end
