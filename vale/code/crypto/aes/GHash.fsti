module GHash

open Opaque_s
open Words_s
open Types_s
open Arch.Types
open GHash_s
open GF128_s
open GCTR_s
open GCM_helpers
open Workarounds
open Collections.Seqs_s
open Collections.Seqs
open FStar.Seq

#reset-options "--use_two_phase_tc true"
let rec ghash_incremental_def (h_LE:quad32) (y_prev:quad32) (x:seq quad32) : Tot quad32 (decreases %[length x]) =
  if length x = 0 then y_prev else
  let y_i_minus_1 = ghash_incremental_def h_LE y_prev (all_but_last x) in
  let x_i = last x in
  let xor_LE = quad32_xor y_i_minus_1 x_i in
  gf128_mul_LE xor_LE h_LE

let ghash_incremental = make_opaque ghash_incremental_def

// avoids need for extra fuel
val lemma_ghash_incremental_def_0 (h_LE:quad32) (y_prev:quad32) (x:seq quad32) : Lemma
  (requires length x == 0)
  (ensures ghash_incremental_def h_LE y_prev x == y_prev)
  [SMTPat (ghash_incremental_def h_LE y_prev x)]

val ghash_incremental_to_ghash (h:quad32) (x:seq quad32) : Lemma
  (requires length x > 0)
  (ensures ghash_incremental h (Mkfour 0 0 0 0) x == ghash_LE h x)
  (decreases %[length x])

val lemma_hash_append (h:quad32) (y_prev:quad32) (a b:ghash_plain_LE) : Lemma
  (ensures
    ghash_incremental h y_prev (append a b) ==
    (let y_a = ghash_incremental h y_prev a in ghash_incremental h y_a b))
  (decreases %[length b])

let ghash_incremental0 (h:quad32) (y_prev:quad32) (x:seq quad32) : quad32 =
  if length x > 0 then ghash_incremental h y_prev x else y_prev

val lemma_hash_append2 (h y_init y_mid y_final:quad32) (s1:seq quad32) (q:quad32) : Lemma
  (requires y_mid = ghash_incremental0 h y_init s1 /\
            y_final = ghash_incremental h y_mid (create 1 q))
  (ensures  y_final == ghash_incremental h y_init (s1 @| (create 1 q)))

val lemma_hash_append3 (h y_init y_mid1 y_mid2 y_final:quad32) (s1 s2 s3:seq quad32) : Lemma
  (requires y_init = Mkfour 0 0 0 0 /\
            y_mid1 = ghash_incremental0 h y_init s1 /\
            y_mid2 = ghash_incremental0 h y_mid1 s2 /\
            length s3 > 0 /\
            y_final = ghash_incremental h y_mid2 s3)
  (ensures y_final == ghash_LE h (append s1 (append s2 s3)))

#reset-options "--z3rlimit 30"
open FStar.Mul
val lemma_ghash_incremental_bytes_extra_helper (h y_init y_mid y_final:quad32) (input:seq quad32) (final final_padded:quad32) (num_bytes:nat) : Lemma
  (requires (1 <= num_bytes /\
             num_bytes < 16 * length input /\
             16 * (length input - 1) < num_bytes /\
             num_bytes % 16 <> 0 /\ //4096 * num_bytes < pow2_32 /\
             (let num_blocks = num_bytes / 16 in
              let full_blocks = slice_work_around input num_blocks in
              y_mid = ghash_incremental0 h y_init full_blocks /\
              final == index input num_blocks /\
              (let padded_bytes = pad_to_128_bits (slice_work_around (le_quad32_to_bytes final) (num_bytes % 16)) in
               length padded_bytes == 16 /\
               final_padded == le_bytes_to_quad32 padded_bytes /\
               y_final = ghash_incremental h y_mid (create 1 final_padded)))))
  (ensures (let input_bytes = slice_work_around (le_seq_quad32_to_bytes input) num_bytes in
            let padded_bytes = pad_to_128_bits input_bytes in
            let input_quads = le_bytes_to_seq_quad32 padded_bytes in
            length padded_bytes == 16 * length input_quads /\
            y_final == ghash_incremental h y_init input_quads))

val lemma_ghash_registers (h y_init y0 y1 y2 y3 y4 r0 r1 r2 r3:quad32) (input:seq quad32) (bound:nat) : Lemma
  (requires length input >= bound + 4 /\
            r0 == index input (bound + 0) /\
            r1 == index input (bound + 1) /\
            r2 == index input (bound + 2) /\
            r3 == index input (bound + 3) /\
            y0 == ghash_incremental0 h y_init (slice input 0 bound) /\
            y1 == ghash_incremental h y0 (create 1 r0) /\
            y2 == ghash_incremental h y1 (create 1 r1) /\
            y3 == ghash_incremental h y2 (create 1 r2) /\
            y4 == ghash_incremental h y3 (create 1 r3))
  (ensures y4 == ghash_incremental h y_init (slice input 0 (bound + 4)))

(*
val lemma_slice_extension (s:seq quad32) (bound:int) (q:quad32) : Lemma
  (requires 0 <= bound /\ bound + 1 <= length s /\ 
            index_work_around_quad32 (slice_work_around s (bound + 1)) bound == q)
  (ensures equal (slice_work_around s (bound + 1))
                 (append (slice_work_around s bound) (create 1 q)))
*)   
