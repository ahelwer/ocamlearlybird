(**
 * Copyright (C) 2021 Yuxiang Wen
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *)

type pc = int * int

module Sp : sig
  type t
  val null : t
  val mone : t
  val base : t -> int -> t
  val compare : t -> t -> int

  val read : Lwt_io.input_channel -> t Lwt.t
  val write : Lwt_io.output_channel -> t -> unit Lwt.t
end

val main_frag : int

type 'a source_location = {
  source : string;
  pos : int * int;
  end_ : 'a;
}

type source_position = unit source_location

type source_range = (int * int) source_location
