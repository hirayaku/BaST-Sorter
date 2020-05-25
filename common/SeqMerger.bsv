
import ClientServer::*;
import Cntrs::*;
import FIFO::*;
import FIFOF::*;
import GetPut::*;
import Vector::*;

import MergerTypes::*;
import BitonicNetwork::*;

// Inner implementation of pipelined merger, w/o guards
typedef Server#(
   DataBeat#(3, Vector#(n, itype)),
   DataBeat#(n, itype)
) MergerInner#(numeric type n, type itype);

// Pipelined Vectorized Merger w/o back pressure
module mkMergerInner#(Bool ascending) (MergerInner#(n, itype))
provisos(Bits#(Vector::Vector#(n, itype), vWidth),
         Ord#(itype),
         Bits#(itype, eWidth),
         NumAlias#(TMul#(n, 2), nn),
         Add#(n, a__, nn),
         FShow#(Vector::Vector#(nn, itype)),
         BitonicMergerN#(nn, itype),
         NumAlias#(TLog#(nn), pipeLevel),
         NumAlias#(TMul#(TLog#(nn), 2), fifoD));

   BitonicMerger#(nn, itype) mergerA <- mkBitonicMergerS(ascending);
   BitonicMerger#(nn, itype) mergerB <- mkBitonicMergerS(ascending);
   Reg#(Vector#(pipeLevel, Vector#(n, itype))) shiftReg <- mkRegU;

   rule mergerA2B;
      let outA <- mergerA.response.get;
      let bottom = drop(outA.data);
      let vec3 = shiftReg[valueOf(pipeLevel)-1];
      let inVec = append(vec3, bottom);

      mergerB.request.put(DataBeat {
          valid: outA.valid,
          data: inVec
      });

   endrule

   interface Put request;
      method Action put(DataBeat#(3, Vector#(n, itype)) in);
         let valid = in.valid;
         let vec1 = in.data[0];
         let vec2 = in.data[1];
         let vec3 = in.data[2];
         let vec12 = append(vec1, vec2);

         shiftReg <= shiftInAt0(shiftReg, vec3);
         mergerA.request.put(DataBeat {
             valid: valid,
             data: vec12
         });
      endmethod
   endinterface

   interface Get response;
      method ActionValue#(DataBeat#(n, itype)) get;
         let outB <- mergerB.response.get;
         Vector#(n, itype) outVec = take(outB.data);
         return DataBeat {
             valid: outB.valid,
             data: {outVec}
         };
      endmethod
   endinterface

endmodule


// pipelined merger w/ guards with an unguarded merger inside
interface SeqMerger#(numeric type n, type itype);
   interface Put#(Vector#(n, Item#(itype))) inA;
   interface Put#(Vector#(n, Item#(itype))) inB;
   interface Get#(Vector#(n, Item#(itype))) out;
   // method Action putA(Vector#(n, Item#(itype)) in);
   // method Action putB(Vector#(n, Item#(itype)) in);
   // method ActionValue#(Vector#(n, Item#(itype))) get;
endinterface

// define a typeclass for SeqMerger so that upper module could use its provisos conveniently
typeclass SeqMergerN#(numeric type n, type itype);
   module mkSeqMerger#(Bool ascending) (SeqMerger#(n, itype));
endtypeclass

instance SeqMergerN#(n, itype)
provisos(Bits#(itype, width),
         Eq#(itype),
         Ord#(itype),
         FShow#(Vector::Vector#(n, itype)),
         NumAlias#(TMul#(n, 2), nn),
         Add#(n, a__, nn),
         Add#(1, b__, n),
         BitonicMergerN#(nn, Item#(itype)),
         // input to output delay is 3 + 2*log2(nn)
         // output FIFO depth = max{ 4 + 2*log2(nn), 4*log2(nn) }
         NumAlias#(TMax#(TAdd#(TMul#(TLog#(nn), 2), 4), TMul#(TLog#(nn), 4)), fifoD));

   module mkSeqMerger#(Bool ascending) (SeqMerger#(n, itype));

      // two input FIFO
      FIFOF#(Vector#(n, Item#(itype))) fifoA <- mkFIFOF;
      FIFOF#(Vector#(n, Item#(itype))) fifoB <- mkFIFOF;

      // defaultItem value depending on `ascending`
      Item#(itype) defaultItem = ascending ? minItem : maxItem;
      Item#(itype) reverseItem = ascending ? maxItem : minItem;

      Reg#(Vector#(n, Item#(itype))) regA <- mkReg(replicate(defaultItem));
      Reg#(Vector#(n, Item#(itype))) regB <- mkReg(replicate(defaultItem));

      // merger pipeline
      Reg#(DataBeat#(3, Vector#(n, Item#(itype)))) mergerIn <- mkReg(DataBeat{valid: False, data: ?});
      MergerInner#(n, Item#(itype)) merger_i <- mkMergerInner(ascending);

      // output FIFO, with credit-based flow control for merger_i
      FIFO#(Vector#(n, Item#(itype)))  fifoOut <- mkSizedFIFO(valueOf(fifoD));
      UCount capacity <- mkUCount(0, valueOf(fifoD));

      // this rule should always fire
      rule doDeq;
         if (!fifoA.notEmpty || !fifoB.notEmpty || !capacity.isLessThan(valueOf(fifoD))) begin
            // either input FIFO is empty or there is not enough space for output FIFO
            mergerIn <= DataBeat {valid: False, data: ?};

         end else begin
            let vecNA = fifoA.first;
            let vecNB = fifoB.first;
            let selA = ascending? head(vecNB) > head(vecNA) : head(vecNA) > head(vecNB);
            // mark the end of both sequences
            let seqEnd = (head(vecNA) == reverseItem) && (head(vecNB) == reverseItem);

            if (seqEnd || selA) begin
               regA <= vecNA;
               fifoA.deq;
            end
            if (seqEnd || !selA) begin
               regB <= vecNB;
               fifoB.deq;
            end

            Vector#(3, Vector#(n, Item#(itype))) inVec;
            inVec[0] = regA; inVec[1] = regB; inVec[2] = (selA)? vecNA : vecNB;

            if (head(regA) == reverseItem) begin
               inVec[0] = replicate(defaultItem);
            end
            if (head(regB) == reverseItem) begin
               inVec[1] = replicate(defaultItem);
            end

            mergerIn <= DataBeat {valid: True, data: inVec};
            capacity.incr(1);
         end
      endrule

      (* fire_when_enabled, no_implicit_conditions *)
      rule toMerger;
          merger_i.request.put(mergerIn);
      endrule

      rule fromMerger;
         let out <- merger_i.response.get;
         if (out.valid) begin
            Vector#(n, Item#(itype)) outVec = out.data;
            if (head(outVec) == defaultItem) begin
               outVec = replicate(reverseItem);
            end
            fifoOut.enq(outVec);
            /*
            $display("From Merger: ");
            $display("  ", fshow(outVec));
            */
         end
      endrule

      interface Put inA = toPut(fifoA);
      interface Put inB = toPut(fifoB);
      interface Get out;
         method ActionValue#(Vector#(n, Item#(itype))) get;
            let out <- toGet(fifoOut).get;
            capacity.decr(1);
            return out;
         endmethod
      endinterface

   endmodule

endinstance

