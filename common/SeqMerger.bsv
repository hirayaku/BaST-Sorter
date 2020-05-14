
import ClientServer::*;
import FIFO::*;
import FIFOF::*;
import GetPut::*;
import Vector::*;

import MergerTypes::*;
import BitonicNetwork::*;

typedef Server#(
   DataBeat#(Vector, 3, Vector#(n, itype)),
   DataBeat#(Vector, n, itype)
) MergerInner#(numeric type n, type itype);

interface SeqMerger#(numeric type n, type itype);
   method Action put(DataBeat#(Vector, 2, SeqVec#(n, itype)) in, DeqSel sel, Round round);
   method ActionValue#(DataBeat#(SeqVec, n, itype)) get;
endinterface

// Pipelined Merger Unguarded
// Implemented recursively in typeclass `MergerN`
// Methods:
// request.put          =>      submit streams of n-sequences to be merged
// response.get         =>      get a sorted n-sequence, flagged by `valid`
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
      // request.put should be called **every cycle** by outer modules
      method Action put(DataBeat#(Vector, 3, Vector#(n, itype)) in);
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
      method ActionValue#(DataBeat#(Vector, n, itype)) get;
         let outB <- mergerB.response.get;
         Vector#(n, itype) outVec = take(outB.data);
         return DataBeat {
             valid: outB.valid,
             data: {outVec}
         };
      endmethod
   endinterface

endmodule

module mkSeqMerger#(Bool ascending) (SeqMerger#(n, itype))
   provisos(Bits#(itype, width),
            Eq#(itype),
            Ord#(itype),
            FShow#(Vector::Vector#(n, itype)),
            NumAlias#(TMul#(n, 2), nn),
            Add#(n, a__, nn),
            Add#(1, b__, n),
            BitonicMergerN#(nn, Item#(itype)),
            NumAlias#(TMul#(TLog#(nn), 4), fifoD));

   // defaultItem value depending on `ascending`
   Item#(itype) defaultItem = ascending ? Item{tag: MinKey, data: ?} : Item{tag: MaxKey, data: ?};
   Item#(itype) reverseItem = ascending ? Item{tag: MaxKey, data: ?} : Item{tag: MinKey, data: ?};

   Reg#(SeqVec#(n, itype)) seqVecA <- mkReg(SeqVec{round: InitRound, vec: ?});
   Reg#(SeqVec#(n, itype)) seqVecB <- mkReg(SeqVec{round: InitRound, vec: ?});

   Reg#(Bool)   valid  <- mkReg(False);
   FIFO#(Round) roundQ <- mkSizedFIFO(valueOf(fifoD));

   Reg#(DataBeat#(Vector, 3, Vector#(n, Item#(itype)))) mergerIn <- mkReg(DataBeat{valid: False, data: ?});
   MergerInner#(n, Item#(itype)) merger_i <- mkMergerInner(ascending);

   rule merge;
       merger_i.request.put(mergerIn);
   endrule

   // request.put should be called **every cycle** by outer modules
   method Action put(DataBeat#(Vector, 2, SeqVec#(n, itype)) in, DeqSel sel, Round round);
      // update internal states
      if (in.valid) begin
         case (sel)
         DeqA:
            seqVecA <= in.data[0];
         DeqB:
            seqVecB <= in.data[1];
         endcase
         roundQ.enq(round);
      end
      valid <= in.valid;

      let vecA = map(toNormalItem, seqVecA.vec);
      let vecB = map(toNormalItem, seqVecB.vec);
      let vecN = map(toNormalItem, in.data[pack(sel)].vec);
      if (seqVecA.round != round) begin
         // seq A has finished first
         vecA = replicate(defaultItem);
      end
      if (seqVecB.round != round) begin
         // seq B has finished first
         vecB = replicate(defaultItem);
      end
      // if (in.data[sel].round != round) begin
      //    // the remaining seq has finished
      //    vecN = replicate(reverseItem);
      // end

      Vector#(3, Vector#(n, Item#(itype))) inVec;
      inVec[0] = vecA; inVec[1] = vecB; inVec[2] = vecN;
      mergerIn <= DataBeat{
         valid: valid,
         data: inVec
      };

      /* if (valid) begin */
      /*    $display("To Merger: "); */
      /*    $display("  ", fshow(vecA)); */
      /*    $display("  ", fshow(vecB)); */
      /*    $display("  ", fshow(vecN)); */
      /* end */
   endmethod

   method ActionValue#(DataBeat#(SeqVec, n, itype)) get;
      let out <- merger_i.response.get;
      let round <- toGet(roundQ).get;
      if (out.valid) begin
         $display("From Merger: ");
         Vector#(n, Item#(itype)) outVec = take(out.data);
         $display("  ", fshow(outVec));
      end
      return DataBeat {
         valid: out.valid,
         data: SeqVec {
            round: round,
            vec: take(map(fromItem, out.data))
         }
      };
   endmethod

endmodule

