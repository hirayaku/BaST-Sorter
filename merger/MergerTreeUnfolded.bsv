import ClientServer::*;
import FIFO::*;
import FIFOF::*;
import GetPut::*;
import Vector::*;
import MergerTypes::*;
import SeqMerger::*;
import MergerTreeTypes::*;

interface MergerTreeUnfolded#(numeric type m, numeric type n, type itype);
   interface Puts#(m, n, Item#(itype)) in;
   interface Get#(Vector#(n, Item#(itype))) out;
endinterface

module mkMergerTreeUnfolded#(Bool ascending) (MergerTreeUnfolded#(m, n, itype));

   SeqMerger#(n, itype) merger <- mkSeqMerger(ascending);

endmodule

module mkAscMergerTree(MergerTreeUnfolded#(8, 4, UInt#(32)));
   MergerTreeUnfolded#(8, 4, UInt#(32)) merger <- mkMergerTreeUnfolded(True);
   return merger;
endmodule
