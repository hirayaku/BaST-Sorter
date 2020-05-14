import ClientServer::*;
import Vector::*;
import DefaultValue::*;

// vector data with `valid` signal
typedef struct {
    Bool valid;
    vtype#(n, itype) data;
} DataBeat#(type vtype, numeric type n, type itype) deriving(Bits);

// Tag to identify special keys
typedef enum { MinKey, Normal, MaxKey } KeyTag deriving(Bits, Eq);

instance Ord#(KeyTag);
function Ordering compare (KeyTag t1, KeyTag t2);
   return compare(pack(t1), pack(t2));
endfunction
endinstance

typedef struct {
   KeyTag tag;
   itype  data;
} Item#(type itype) deriving(Bits, Eq);

function Item#(itype) toMinItem(itype data);
   return Item {
      tag: MinKey,
      data: data
   };
endfunction

function Item#(itype) toMaxItem(itype data);
   return Item {
      tag: MaxKey,
      data: data
   };
endfunction

function Item#(itype) toNormalItem(itype data);
   return Item {
      tag: Normal,
      data: data
   };
endfunction

function itype fromItem(Item#(itype) item);
    return item.data;
endfunction

instance Ord#(Item#(itype)) provisos(Ord#(itype));
function Bool \> (Item#(itype) i1, Item#(itype) i2);
   return (i1.tag > i2.tag) || ((i1.tag == i2.tag) && (i1.data > i2.data));
endfunction
endinstance

instance FShow#(Item#(itype)) provisos(FShow#(itype));
function Fmt fshow(Item#(itype) i);
   if (i.tag == MinKey) begin
      return $format("       Min");
   end else if (i.tag == MaxKey) begin
      return $format("       Max");
   end else begin
      return $format(fshow(i.data));
   end
endfunction
endinstance

/*
typedef struct {
   UInt#(8) round;     // current merging round
   UInt#(32) iter;     // current merging iteration within a certain round
} SeqIdx deriving(Bits, Eq);

instance Ord#(SeqIdx);
function Ordering compare (SeqIdx idx1, SeqIdx idx2);
   return compare(pack(idx1), pack(idx2));
   // return (idx1.round > idx2.round) || ((idx1.round == idx2.round) && (idx1.iter > idx2.iter));
endfunction
endinstance
*/

typedef enum { InitRound, OddRound, EvenRound } Round deriving(Bits, Eq);

typedef struct {
   Round round;
   Vector#(n, itype) vec;
} SeqVec#(numeric type n, type itype) deriving(Bits);

function Bool cmpSeqVec(SeqVec#(n, itype) sv1, SeqVec#(n, itype) sv2, Bool ascending)
   provisos(Add#(1, a__, n),
            Ord#(itype));
   if (ascending) begin
      return last(sv1.vec) < last(sv2.vec);
   end else begin
      return last(sv1.vec) >= last(sv2.vec);
   end
endfunction

typedef enum { DeqA, DeqB } DeqSel deriving(Bits, Eq);

