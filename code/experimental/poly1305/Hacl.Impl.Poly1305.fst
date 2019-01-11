module Hacl.Impl.Poly1305

module ST = FStar.HyperStack.ST
open FStar.HyperStack
open FStar.HyperStack.All
open FStar.Mul

open Lib.IntTypes
open Lib.Buffer
open Lib.ByteBuffer

open Hacl.Impl.Poly1305.Fields
module S = Hacl.Spec.Poly1305.Vec
module BSeq = Lib.ByteSequence
module LSeq = Lib.Sequence
module F32xN = Hacl.Impl.Poly1305.Field32xN

#reset-options "--z3rlimit 50"

inline_for_extraction
val poly1305_encode_block:
    #s:field_spec
  -> f:felem s
  -> b:lbuffer uint8 16ul
  -> Stack unit
    (requires fun h -> live h b /\ live h f)
    (ensures  fun h0 _ h1 ->
      modifies (loc f) h0 h1 /\
      felem_fits h1 f (1, 1, 1, 1, 1) /\
      feval h1 f == LSeq.map (S.pfadd (pow2 128))
        (LSeq.create (width s) (BSeq.nat_from_bytes_le (as_seq h0 b))))
let poly1305_encode_block #s f b =
  load_felem_le f b;
  set_bit128 f

inline_for_extraction
val poly1305_encode_blocks:
    #s:field_spec
  -> f:felem s
  -> b:lbuffer uint8 (blocklen s)
  -> Stack unit
    (requires fun h -> live h b /\ live h f)
    (ensures  fun h0 _ h1 -> modifies (loc f) h0 h1)
let poly1305_encode_blocks #s f b = admit();
  load_felems_le f b;
  set_bit128 f

inline_for_extraction
val poly1305_encode_last:
    #s:field_spec
  -> f:felem s
  -> len:size_t{v len < 16}
  -> b:lbuffer uint8 len
  -> Stack unit
    (requires fun h -> live h b /\ live h f /\ disjoint b f)
    (ensures  fun h0 _ h1 ->
      modifies (loc f) h0 h1 /\
      felem_fits h1 f (1, 1, 1, 1, 1) /\
      (Math.Lemmas.pow2_le_compat 128 (8 * v len);
      feval h1 f == LSeq.map (S.pfadd (pow2 (8 * v len)))
        (LSeq.create (width s) (BSeq.nat_from_bytes_le (as_seq h0 b)))))
let poly1305_encode_last #s f len b =
  push_frame();
  let tmp = create 16ul (u8 0) in
  copy (sub tmp 0ul len) (sub b 0ul len);
  let h0 = ST.get () in
  assume (BSeq.nat_from_bytes_le (as_seq h0 b) == BSeq.nat_from_bytes_le (as_seq h0 tmp));
  load_felem_le f tmp;
  let h1 = ST.get () in
  assert (feval h1 f == LSeq.create (width s) (BSeq.nat_from_bytes_le (as_seq h0 tmp)));
  LSeq.eq_intro (LSeq.create (width s) (BSeq.nat_from_bytes_le (as_seq h0 tmp)))
    (LSeq.create (width s) (BSeq.nat_from_bytes_le (as_seq h0 b)));
  assert (BSeq.nat_from_bytes_le (as_seq h0 b) < pow2 (v len * 8));
  Math.Lemmas.pow2_le_compat 128 (v len * 8);
  assume (F32xN.felem_less #(width s) h1 f (pow2 (v len * 8)));
  set_bit f (len *! 8ul);
  let h2 = ST.get () in
  assert (feval h2 f == LSeq.map (S.pfadd (pow2 (v len * 8))) (feval h1 f));
  pop_frame()

inline_for_extraction
val poly1305_encode_r:
    #s:field_spec
  -> p:precomp_r s
  -> b:lbuffer uint8 16ul
  -> Stack unit
    (requires fun h -> live h b /\ live h p)
    (ensures  fun h0 _ h1 ->
      modifies (loc p) h0 h1 /\
      load_precompute_r_post h1 p /\
      feval h1 (gsub p 0ul 5ul) == S.encode_r (as_seq h0 b))
let poly1305_encode_r #s p b =
  let lo = uint_from_bytes_le (sub b 0ul 8ul) in
  let hi = uint_from_bytes_le (sub b 8ul 8ul) in
  let mask0 = u64 0x0ffffffc0fffffff in
  let mask1 = u64 0x0ffffffc0ffffffc in
  let lo = lo &. mask0 in
  let hi = hi &. mask1 in
  let h0 = ST.get () in
  load_precompute_r p lo hi;
  let h1 = ST.get () in
  assert (feval h1 (gsub p 0ul 5ul) == LSeq.create (width s) (uint_v hi * pow2 64 + uint_v lo));
  assume (S.encode_r (as_seq h0 b) == S.to_elem (width s) (uint_v hi * pow2 64 + uint_v lo));
  LSeq.eq_intro (feval h1 (gsub p 0ul 5ul)) (S.encode_r (as_seq h0 b))

inline_for_extraction
type poly1305_ctx (s:field_spec) = lbuffer (limb s) (nlimb s +. precomplen s)

(*
inline_for_extraction
val get_acc: #s:field_spec -> ctx:poly1305_ctx s -> Stack (felem s)
                   (requires (fun h -> live h ctx))
		   (ensures (fun h0 r h1 -> h0 == h1 /\ live h1 r))
*)
inline_for_extraction
let get_acc #s (ctx:poly1305_ctx s) = sub ctx (size 0) (nlimb s)


(*
inline_for_extraction
val get_precomp_r: #s:field_spec -> ctx:poly1305_ctx s -> Stack (precomp_r s)
                   (requires (fun h -> live h ctx))
		   (ensures (fun h0 r h1 -> h0 == h1 /\ live h1 r))
*)
inline_for_extraction
let get_precomp_r #s (ctx:poly1305_ctx s) = sub ctx (nlimb s) (precomplen s)

inline_for_extraction
val poly1305_init_:
    #s:field_spec
  -> ctx:poly1305_ctx s
  -> key:lbuffer uint8 32ul
  -> Stack unit
    (requires fun h ->
      live h ctx /\ live h key /\ disjoint ctx key)
    (ensures  fun h0 _ h1 ->
      modifies (loc ctx) h0 h1 /\
     (let (acc_s, r_s) = S.poly1305_init (as_seq h0 key) in
      let acc = gsub ctx 0ul (nlimb s) in
      let p = gsub ctx (nlimb s) (precomplen s) in
      load_precompute_r_post h1 p /\
      feval h1 (gsub p 0ul 5ul) == r_s /\ feval h1 acc == acc_s))
let poly1305_init_ #s ctx key =
  let kr = sub key 0ul 16ul in
  let acc = get_acc ctx in
  let precomp_r = get_precomp_r ctx in
  let h0 = ST.get () in
  set_zero acc;
  let h1 = ST.get () in
  LSeq.eq_intro (feval h1 acc) (fst (S.poly1305_init (as_seq h0 key)));
  poly1305_encode_r precomp_r kr

(* WRAPPER TO PREVENT INLINING *)
[@CInline]
let poly1305_init_32 (ctx:poly1305_ctx M32) (k:lbuffer uint8 32ul) = poly1305_init_ #M32 ctx k
[@CInline]
let poly1305_init_128 (ctx:poly1305_ctx M128) (k:lbuffer uint8 32ul) = poly1305_init_ #M128 ctx k
inline_for_extraction
let poly1305_init_256 (ctx:poly1305_ctx M256) (k:lbuffer uint8 32ul) = poly1305_init_ #M256 ctx k

inline_for_extraction noextract
val poly1305_init:
    #s:field_spec
  -> ctx:poly1305_ctx s
  -> key:lbuffer uint8 32ul
  -> Stack unit
    (requires fun h ->
      live h ctx /\ live h key /\ disjoint ctx key)
    (ensures  fun h0 _ h1 ->
      modifies (loc ctx) h0 h1 /\
     (let (acc_s, r_s) = S.poly1305_init (as_seq h0 key) in
      let acc = gsub ctx 0ul (nlimb s) in
      let p = gsub ctx (nlimb s) (precomplen s) in
      load_precompute_r_post h1 p /\
      feval h1 (gsub p 0ul 5ul) == r_s /\ feval h1 acc == acc_s))
let poly1305_init #s ctx key =
  match s with
  | M32  -> poly1305_init_32 ctx key
  | M128 -> poly1305_init_128 ctx key
  | M256 -> poly1305_init_256 ctx key
(* WRAPPER to Prevent Inlining *)


inline_for_extraction
val poly1305_nblocks:
    #s:field_spec
  -> ctx:poly1305_ctx s
  -> len:size_t{v len % v (blocklen s) == 0}
  -> text:lbuffer uint8 len
  -> Stack unit
    (requires fun h -> live h ctx /\ live h text)
    (ensures  fun h0 _ h1 -> modifies (loc ctx) h0 h1)
let poly1305_nblocks #s ctx len text =
  push_frame();
  let acc = get_acc ctx in
  let pre = get_precomp_r ctx in
  let e = create (nlimb s) (limb_zero s) in
  let sz_block = blocklen s in
  let blocks = len /. sz_block in
  let h0 = ST.get() in
  admit();
  loop_nospec #h0 blocks ctx
  (fun i ->
    let b = sub text (i *. sz_block) sz_block in
    poly1305_encode_blocks e b;
    fmul_rn acc acc pre;
    fadd acc acc e
  );
  fmul_rn_normalize acc pre;
  pop_frame()

inline_for_extraction
val poly1305_update_:
    #s:field_spec
  -> ctx:poly1305_ctx s
  -> len:size_t
  -> text:lbuffer uint8 len
  -> Stack unit
    (requires fun h -> live h ctx /\ live h text)
    (ensures  fun h0 _ h1 -> modifies (loc ctx) h0 h1)
let poly1305_update_ #s ctx len text =
  push_frame();
  let acc = get_acc ctx in
  let pre = get_precomp_r ctx in
  let sz_block = blocklen s in
  let len0 = if sz_block >. size 16 then (len /. sz_block) *. sz_block else size 0 in
  if (sz_block >. size 16) then (
    let t0 = sub text (size 0) len0 in
    poly1305_nblocks ctx len0 t0
  );
  let len = len -. len0 in
  let text = sub text len0 len in
  let e = create (nlimb s) (limb_zero s) in
  let blocks = len /. size 16 in
  let h0 = ST.get() in
  admit();
  loop_nospec #h0 blocks ctx
  (fun i ->
    let b = sub text (i *. size 16) (size 16) in
    poly1305_encode_block e b;
    fadd_mul_r acc e pre
  );
  let rem = len %. size 16 in
  if (rem >. size 0) then (
    let b = sub text (blocks *. size 16) rem in
    poly1305_encode_last e rem b;
    fadd_mul_r acc e pre);
  pop_frame()

(* WRAPPER TO PREVENT INLINING *)
[@CInline]
let poly1305_update_32 (ctx:poly1305_ctx M32) (len:size_t) (text:lbuffer uint8 len) = poly1305_update_ #M32 ctx len text
[@CInline]
let poly1305_update_128 (ctx:poly1305_ctx M128) (len:size_t) (text:lbuffer uint8 len) = poly1305_update_ #M128 ctx len text
inline_for_extraction
let poly1305_update_256 (ctx:poly1305_ctx M256) (len:size_t) (text:lbuffer uint8 len) = poly1305_update_ #M256 ctx len text

inline_for_extraction noextract
val poly1305_update:
    #s:field_spec
  -> ctx:poly1305_ctx s
  -> len:size_t
  -> text:lbuffer uint8 len
  -> Stack unit
    (requires fun h -> live h ctx /\ live h text)
    (ensures  fun h0 _ h1 -> modifies (loc ctx) h0 h1)
let poly1305_update #s ctx len text =
  match s with
  | M32 -> poly1305_update_32 ctx len text
  | M128 -> poly1305_update_128 ctx len text
  | M256 -> poly1305_update_256 ctx len text
(* WRAPPER to Prevent Inlining *)


inline_for_extraction
val poly1305_finish_:
    #s:field_spec
  -> key:lbuffer uint8 32ul
  -> ctx:poly1305_ctx s
  -> tag:lbuffer uint8 16ul
  -> Stack unit
    (requires fun h -> live h ctx /\ live h tag /\ live h key)
    (ensures  fun h0 _ h1 -> modifies (loc tag) h0 h1)
let poly1305_finish_ #s key ctx tag = admit();
  push_frame ();
  let acc = get_acc ctx in
  reduce_felem acc;

  let ks = sub key (size 16) (size 16) in
  let sk = create (nlimb s) (limb_zero s) in
  load_felem_le sk ks;

  //use u128 addition
  fadd acc acc sk;
  store_felem_le tag acc;
  pop_frame ()

(* WRAPPER TO PREVENT INLINING *)
[@CInline]
let poly1305_finish_32 (key:lbuffer uint8 32ul) (ctx:poly1305_ctx M32) (tag:lbuffer uint8 16ul) = poly1305_finish_ #M32 key ctx tag
[@CInline]
let poly1305_finish_128 (key:lbuffer uint8 32ul) (ctx:poly1305_ctx M128) (tag:lbuffer uint8 16ul) = poly1305_finish_ #M128 key ctx tag
[@CInline]
let poly1305_finish_256 (key:lbuffer uint8 32ul) (ctx:poly1305_ctx M256) (tag:lbuffer uint8 16ul) = poly1305_finish_ #M256 key ctx tag

inline_for_extraction noextract
val poly1305_finish:
    #s:field_spec
  -> key:lbuffer uint8 32ul
  -> ctx:poly1305_ctx s
  -> tag:lbuffer uint8 16ul
  -> Stack unit
    (requires fun h -> live h ctx /\ live h tag /\ live h key)
    (ensures  fun h0 _ h1 -> modifies (loc tag) h0 h1)
let poly1305_finish #s key ctx tag =
   match s with
   | M32 -> poly1305_finish_32 key ctx tag
   | M128 -> poly1305_finish_128 key ctx tag
   | M256 -> poly1305_finish_256 key ctx tag
(* WRAPPER to Prevent Inlining *)



inline_for_extraction
val poly1305_mac:
    #s:field_spec
  -> tag:lbuffer uint8 16ul
  -> len:size_t
  -> text:lbuffer uint8 len
  -> key:lbuffer uint8 32ul
  -> Stack unit
    (requires fun h -> live h text /\ live h tag /\ live h key)
    (ensures  fun h0 _ h1 -> modifies (loc tag) h0 h1)
let poly1305_mac #s tag len text key =
  push_frame ();
  let ctx = create (nlimb s +. precomplen s) (limb_zero s) in
  poly1305_init ctx key;
  poly1305_update ctx len text;
  poly1305_finish key ctx tag;
  pop_frame ()