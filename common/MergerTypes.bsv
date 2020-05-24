import Vector::*;

// vector data with `valid` signal
typedef struct {
    Bool valid;
    Vector#(n, itype) data;
} DataBeat#(numeric type n, type itype) deriving(Bits);

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
} Item#(type itype) deriving(Bits);

Item#(itype) minItem = Item { tag: MinKey, data: ?};
Item#(itype) maxItem = Item { tag: MaxKey, data: ?};

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

instance Eq#(Item#(itype)) provisos(Eq#(itype));
function Bool \== (Item#(itype) x1, Item#(itype) x2);
   return ((x1.tag == MinKey) && (x2.tag == MinKey)) ||
          ((x1.tag == MaxKey) && (x2.tag == MaxKey)) ||
          ((x1.tag == Normal) && (x2.tag == Normal) && x1.data == x2.data);
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

