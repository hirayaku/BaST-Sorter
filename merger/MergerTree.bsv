import ClientServer::*;
import FIFO::*;
import FIFOF::*;
import GetPut::*;
import Vector::*;
import BuildVector::*;
import MergerTypes::*;
import SeqMerger::*;

// a vector of Put interfaces
typedef Vector#(k, Put#(itype)) Puts#(numeric type k, type itype);

// Generic merger tree, with k input ports (Fan-in = k) with a width of n1 & 1 output port with a width of n2
interface MergerTreeGeneric#(numeric type k, numeric type n1, numeric type n2, type itype);
   interface Puts#(k, Vector#(n1, Item#(itype))) in;
   interface Get#(Vector#(n2, Item#(itype))) out;
endinterface

// Funnel-like merger tree, with k input ports, 1 output port, each with a width of n regardless of k
typedef MergerTreeGeneric#(k, n, n, itype) MergerTreeFunnel#(numeric type k, numeric type n, type itype);
// Throughput balanced merger tree, with k input ports, 1 output port; n1 * k = n2 * 2
typedef MergerTreeGeneric#(k, n1, n2, itype) MergerTreeBalanced#(numeric type k, numeric type n1, numeric type n2, type itype);

// K-Merger
typeclass MergerTreeK#(numeric type k, numeric type n1,/* numeric type n2,*/ type itype);
   module mkMergerTreeUnfolded#(Bool ascending) (MergerTreeFunnel#(k, n1, itype));
   // module mkMergerTreeBalanced#(Bool ascending) (MergerTreeBalanced#(k, n1, n2, itype));
   module mkMergerTreeSMT#(Bool ascending) (MergerTreeFunnel#(k, n1, itype));
endtypeclass

// base case: 2-Merger
instance MergerTreeK#(2, n1, itype)
// instance MergerTreeK#(2, n1, n2, itype)
provisos(SeqMerger::SeqMergerN#(n1, itype),
         NumAlias#(n1, n));

   module mkMergerTreeUnfolded#(Bool ascending) (MergerTreeFunnel#(2, n, itype));
      SeqMerger#(n, itype) merger <- mkSeqMerger(ascending);

      interface Puts in = vec(merger.inA, merger.inB);
      interface Get out = merger.out;
   endmodule

endinstance

// derivative case
instance MergerTreeK#(k, n1, itype)
provisos(NumAlias#(n1, n),
         SeqMerger::SeqMergerN#(n, itype),
         NumAlias#(TDiv#(k, 2), k2),
         Mul#(k2, 2, k),
         MergerTreeK#(k2, n, itype));

   module mkMergerTreeUnfolded#(Bool ascending) (MergerTreeFunnel#(k, n, itype));
      MergerTreeFunnel#(k2, n, itype) mtA <- mkMergerTreeUnfolded(ascending);
      MergerTreeFunnel#(k2, n, itype) mtB <- mkMergerTreeUnfolded(ascending);
      MergerTreeFunnel#(2, n, itype)  mt  <- mkMergerTreeUnfolded(ascending);

      rule final_mergeA;
         let out <- mtA.out.get;
         mt.in[0].put(out);
      endrule
      rule final_mergeB;
         let out <- mtB.out.get;
         mt.in[1].put(out);
      endrule

      interface Puts in = append(mtA.in, mtB.in);
      interface Get out = mt.out;
   endmodule

endinstance


(* synthesize *)
module mkAscMergerTree(MergerTreeFunnel#(4, 4, UInt#(32)));
   MergerTreeFunnel#(4, 4, UInt#(32)) merger <- mkMergerTreeUnfolded(True);
   return merger;
endmodule

