module Math.Poly2.Words

let lemma_add128 a b =
  let Mkfour a0 a1 a2 a3 = to_quad32 a in
  let Mkfour b0 b1 b2 b3 = to_quad32 b in
  let pxor m n = of_nat32 m +. of_nat32 n in
  calc (==) {
    to_quad32 (a +. b);
    == {
      lemma_quad32_to_nat32s a;
      lemma_quad32_to_nat32s b;
      lemma_bitwise_all ();
      lemma_equal (a +. b) (poly128_of_poly32s (pxor a0 b0) (pxor a1 b1) (pxor a2 b2) (pxor a3 b3))
    }
    to_quad32 (poly128_of_poly32s (pxor a0 b0) (pxor a1 b1) (pxor a2 b2) (pxor a3 b3));
    == {of_nat32_xor a0 b0; of_nat32_xor a1 b1; of_nat32_xor a2 b2; of_nat32_xor a3 b3}
    to_quad32 (poly128_of_nat32s (ixor a0 b0) (ixor a1 b1) (ixor a2 b2) (ixor a3 b3));
    == {lemma_quad32_of_nat32s (ixor a0 b0) (ixor a1 b1) (ixor a2 b2) (ixor a3 b3)}
    Mkfour (ixor a0 b0) (ixor a1 b1) (ixor a2 b2) (ixor a3 b3);
    == {Opaque_s.reveal_opaque quad32_xor_def}
    quad32_xor (to_quad32 a) (to_quad32 b);
  }

let lemma_quad32_double_shift a =
  let q = to_quad32 a in
  let Mkfour q0 q1 q2 q3 = to_quad32 a in
  calc (==) {
    Mkfour #nat32 0 0 q0 q1;
    == {lemma_quad32_of_nat32s 0 0 q0 q1}
    to_quad32 (poly128_of_nat32s 0 0 q0 q1);
    == {
      lemma_bitwise_all ();
      lemma_quad32_to_nat32s a;
      lemma_equal (shift (mask a 64) 64) (poly128_of_nat32s 0 0 q0 q1)
    }
    to_quad32 (shift (mask a 64) 64);
    == {lemma_mask_is_mod a 64; lemma_shift_is_mul (a %. monomial 64) 64}
    to_quad32 ((a %. monomial 64) *. monomial 64);
  };
  calc (==) {
    Mkfour #nat32 q2 q3 0 0;
    == {lemma_quad32_of_nat32s q2 q3 0 0}
    to_quad32 (poly128_of_nat32s q2 q3 0 0);
    == {
      lemma_bitwise_all ();
      lemma_quad32_to_nat32s a;
      lemma_equal (shift a (-64)) (poly128_of_nat32s q2 q3 0 0)
    }
    to_quad32 (shift a (-64));
    == {lemma_shift_is_div a 64}
    to_quad32 (a /. monomial 64);
  };
  ()

let lemma_quad32_double_swap a =
  let s = swap a 64 in
  let Mkfour a0 a1 a2 a3 = to_quad32 a in
  calc (==) {
    to_quad32 s;
    == {
      lemma_bitwise_all ();
      lemma_quad32_to_nat32s a;
      lemma_equal s (poly128_of_nat32s a2 a3 a0 a1)
    }
    to_quad32 (poly128_of_nat32s a2 a3 a0 a1);
    == {lemma_quad32_of_nat32s a2 a3 a0 a1}
    Mkfour a2 a3 a0 a1;
  }
