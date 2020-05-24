
import ClientServer::*;
import FIFO::*;
import FIFOF::*;
import GetPut::*;
import Vector::*;
import Randomizable::*;

import MergerTypes::*;
import BitonicNetwork::*;
import SeqMerger::*;

typedef `VecSz VecSz;
Bool ascending = True;

import "BDPI" function ActionValue#(Bit#(32)) create_round(Bit#(32) sort_type);
import "BDPI" function Action delete_round(Bit#(32) rid);
import "BDPI" function ActionValue#(Bit#(32)) add_seq(Bit#(32) rid, Bit#(32) seq_type, Bit#(32) n, Bit#(32) lower, Bit#(32) upper);
import "BDPI" function ActionValue#(Bit#(32)) move_seq(Bit#(32) rid_src, Bit#(32) rid_dst);
import "BDPI" function Bool check_invec(Bit#(32) rid, Bit#(32) sid);
import "BDPI" function ActionValue#(Bit#(32)) get_invec(Bit#(32) rid, Bit#(32) sid);
import "BDPI" function Bool check_outvec(Bit#(32) rid);
import "BDPI" function ActionValue#(Bit#(32)) get_outvec(Bit#(32) rid);

module mkMergerInnerTest(Empty);
    Reg#(UInt#(32)) tick <- mkReg(0);
    Reg#(UInt#(32)) testCnt <- mkReg(0);
    Integer rounds = 16;

    rule ticktock;
        tick <= tick + 1;
    endrule

    rule finish;
        if (tick ==  fromInteger(rounds)) begin
            $finish;
        end
    endrule

    MergerInner#(VecSz, UInt#(32)) merger <- mkMergerInner(ascending);

    rule data1;
        Vector#(VecSz, UInt#(32)) vecA = ?, vecB = ?, vecN = ?;
        Bool valid = False;
        if (tick == 0) begin
           vecA[0] = 1; vecA[1] = 3; vecA[2] = 32'hffffffff; vecA[3] = 32'hffffffff;
           vecB[0] = 2; vecB[1] = 4; vecB[2] = 32'haaaaaaaa; vecB[3] = 32'hffffffff;
           vecN[0] = 5; vecN[1] = 7; vecN[2] = 32'haaaaaaaa; vecN[3] = 32'hffffffff;
           valid = True;
        end
        if (tick == 1) begin
            vecA[0] = 5; vecA[1] = 7;
            vecB[0] = 2; vecB[1] = 4;
            vecN[0] = 6; vecN[1] = 8;
            valid = True;
        end
        if (tick == 3) begin
            vecA[0] = 5; vecA[1] = 7;
            vecB[0] = 6; vecB[1] = 8;
            vecN[0] = 9; vecN[1] = 11;
            valid = True;
        end

        Vector#(3, Vector#(VecSz, UInt#(32))) inVecs;
        inVecs[0] = vecA; inVecs[1] = vecB; inVecs[2] = vecN;
        merger.request.put(DataBeat{
            valid: valid,
            data: inVecs
        });

        if (valid) begin
            $display("Put ", fshow(inVecs));
        end
    endrule

    rule polldata;
        let out <- merger.response.get;
        if (out.valid) begin
            $display("Got ", fshow(out.data));
        end
    endrule
endmodule

module mkMergerTest(Empty);
   Reg#(UInt#(32)) tick <- mkReg(0);
   Reg#(Bool) inited <- mkReg(False);

   rule ticktock;
       tick <= tick + 1;
   endrule

   /*
   Integer maxTick = 64;
   rule finish;
       if (tick ==  fromInteger(maxTick)) begin
           $finish;
       end
   endrule
   */

   FIFO#(Bit#(32)) rid_fifo <- mkSizedFIFO(8);
   FIFO#(Bit#(32)) rid_fifoA <- mkSizedFIFO(8);
   FIFO#(Bit#(32)) rid_fifoB <- mkSizedFIFO(8);
   FIFO#(Bit#(32)) sid_fifoA <- mkSizedFIFO(8);
   FIFO#(Bit#(32)) sid_fifoB <- mkSizedFIFO(8);
   FIFO#(Bool)     end_fifoA <- mkFIFO;
   FIFO#(Bool)     end_fifoB <- mkFIFO;

   rule init (tick == 0);
      inited <= True;
   endrule

   Integer maxRound = 2;
   Reg#(UInt#(32)) round <- mkReg(0);
   Reg#(UInt#(32)) testCnt <- mkReg(0);
   SeqMerger#(VecSz, UInt#(32)) merger <- mkSeqMerger(ascending);

   rule gen_data (inited);
      round <= round + 1;

      if (round < fromInteger(maxRound)) begin
         let rid <- create_round(0);
         rid_fifo.enq(rid);
         rid_fifoA.enq(rid);
         rid_fifoB.enq(rid);

         let randA <- rand32();
         let sidA <- add_seq(rid, 0, fromInteger(valueOf(VecSz)) * (randA%16 + 16), pack(1024 * round), pack(1024 * round + 1024));
         // let sidA <- add_seq(rid, 0, fromInteger(valueOf(VecSz)) * 32, pack(1024 * round), pack(1024 * round + 1024));
         // let sidA <- add_seq(rid, 0, fromInteger(valueOf(VecSz)) * 32, 0, 1024);
         sid_fifoA.enq(sidA);
         end_fifoA.enq(False);

         let randB <- rand32();
         let sidB <- add_seq(rid, 0, fromInteger(valueOf(VecSz)) * (randB%16 + 16), pack(1024 * round), pack(1024 * round + 1024));
         // let sidB <- add_seq(rid, 0, fromInteger(valueOf(VecSz)) * 32, pack(1024 * round), pack(1024 * round + 1024));
         // let sidB <- add_seq(rid, 0, fromInteger(valueOf(VecSz)) * 32, 0, 1024);
         sid_fifoB.enq(sidB);
         end_fifoB.enq(False);

      end
      
      if (round == fromInteger(maxRound)) begin
         end_fifoA.enq(True);
         end_fifoB.enq(True);
      end
   endrule

   rule enq_fifoA (inited);
      let terminate = end_fifoA.first;

      if (!terminate) begin
         Vector#(VecSz, UInt#(32)) inVec = ?;
         Vector#(VecSz, Item#(UInt#(32))) in;

         let rid = rid_fifoA.first;
         let sid = sid_fifoA.first;

         Bool checkNotEnd = check_invec(rid, sid);
         for (Integer i = 0; i < valueOf(VecSz); i = i + 1) begin
            if (check_invec(rid, sid)) begin
               let v <- get_invec(rid, sid);
               inVec[i] = unpack(v);
            end
         end

         if (checkNotEnd) begin
            in = map(toNormalItem, inVec);
         end else begin
            in = map(toMaxItem, inVec);
            rid_fifoA.deq;
            sid_fifoA.deq;
            end_fifoA.deq;
         end

         merger.putA(in);
         // $display("[@%9d] putA: ", tick, fshow(in));

      end else begin
         merger.putA(replicate(maxItem));
         end_fifoA.deq;
      end
   endrule

   rule data_fifoB (inited);
      let terminate = end_fifoB.first;

      if (!terminate) begin
         Vector#(VecSz, UInt#(32)) inVec = ?;
         Vector#(VecSz, Item#(UInt#(32))) in;

         let rid = rid_fifoB.first;
         let sid = sid_fifoB.first;

         Bool checkNotEnd = check_invec(rid, sid);
         for (Integer i = 0; i < valueOf(VecSz); i = i + 1) begin
            if (check_invec(rid, sid)) begin
               let v <- get_invec(rid, sid);
               inVec[i] = unpack(v);
            end
         end

         if (checkNotEnd) begin
            in = map(toNormalItem, inVec);
         end else begin
            in = map(toMaxItem, inVec);
            rid_fifoB.deq;
            sid_fifoB.deq;
            end_fifoB.deq;
         end

         merger.putB(in);
         // $display("[@%9d] putB: ", tick, fshow(in));

      end else begin
         merger.putB(replicate(maxItem));
         end_fifoB.deq;
      end

   endrule

   Reg#(Bool) valid_seq <- mkReg(False);
   rule extract_merger (inited);
      let out <- merger.get;

      $display("[@%9d] output No.%4d: ", tick, testCnt, fshow(out));
      if (out[0] != maxItem) begin
         testCnt <= testCnt + 1;

         // compare BSV with C++ results
         Vector#(VecSz, UInt#(32)) outVec = ?;
         let rid = rid_fifo.first;
         for (Integer i = 0; i < valueOf(VecSz); i = i + 1) begin
            if (check_outvec(rid)) begin
               let v <- get_outvec(rid);
               outVec[i] = unpack(v);
            end
            if (out[i] != toNormalItem(outVec[i])) begin
               $display("Sorted outputs mismatch!");
               $display("For Item No.%0d , expect: %d, got ", i, outVec[i], fshow(out[i]));
               $finish;
            end
         end
      end

      if (!valid_seq && out[0] != maxItem) begin
         // a new sequence appears
         valid_seq <= True;
      end
      if (valid_seq && out[0] == maxItem) begin
         // the current sequence ends 
         valid_seq <= False;
         delete_round(rid_fifo.first);
         rid_fifo.deq;
      end
   endrule

endmodule

