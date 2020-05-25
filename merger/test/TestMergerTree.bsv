
import ClientServer::*;
import FIFO::*;
import FIFOF::*;
import GetPut::*;
import Vector::*;
import Randomizable::*;

import MergerTypes::*;
import MergerTree::*;

typedef `VecSz VecSz;
typedef `K     K;
Bool ascending = True;

import "BDPI" function ActionValue#(Bit#(32)) create_round(Bit#(32) sort_type);
import "BDPI" function Action delete_round(Bit#(32) rid);
import "BDPI" function ActionValue#(Bit#(32)) add_seq(Bit#(32) rid, Bit#(32) seq_type, Bit#(32) n, Bit#(32) lower, Bit#(32) upper);
import "BDPI" function ActionValue#(Bit#(32)) move_seq(Bit#(32) rid_src, Bit#(32) rid_dst);
import "BDPI" function Bool check_invec(Bit#(32) rid, Bit#(32) sid);
import "BDPI" function ActionValue#(Bit#(32)) get_invec(Bit#(32) rid, Bit#(32) sid);
import "BDPI" function Bool check_outvec(Bit#(32) rid);
import "BDPI" function ActionValue#(Bit#(32)) get_outvec(Bit#(32) rid);

module mkMergerTreeTest(Empty);
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

   FIFO#(Bit#(32)) rid_top_fifo <- mkSizedFIFO(8);
   Vector#(K, FIFO#(Bit#(32))) rid_fifo <- replicateM(mkSizedFIFO(8));
   Vector#(K, FIFO#(Bit#(32))) sid_fifo <- replicateM(mkSizedFIFO(8));
   Vector#(K, FIFO#(Bool)) term_fifo <- replicateM(mkSizedFIFO(8));

   rule init (tick == 0);
      inited <= True;
   endrule

   Integer maxRound = 64;
   Reg#(UInt#(32)) round <- mkReg(0);
   Reg#(UInt#(32)) testCnt <- mkReg(0);
   MergerTreeFunnel#(K, VecSz, UInt#(32)) mt <- mkMergerTreeUnfolded(ascending);

   rule gen_data (inited);
      round <= round + 1;

      if (round < fromInteger(maxRound)) begin
         let rid <- create_round(0);
         rid_top_fifo.enq(rid);

         for (Integer i = 0; i < valueOf(K); i = i + 1) begin
            rid_fifo[i].enq(rid);
            let x <- rand32();
            let sid <- add_seq(rid, 0, fromInteger(valueOf(VecSz)) * (x%16 + 16), pack(1024 * round), pack(1024 * round + 1024));
            sid_fifo[i].enq(sid);
            term_fifo[i].enq(False);
         end
      end
      
      if (round == fromInteger(maxRound)) begin
         for (Integer i = 0; i < valueOf(K); i = i + 1) begin
            term_fifo[i].enq(True);
         end
      end
   endrule

   for (Integer i = 0; i < valueOf(K); i = i + 1) begin
      // enq rule for each input ports

      rule enq_fifo (inited);
         let terminate = term_fifo[i].first;

         if (!terminate) begin
            Vector#(VecSz, UInt#(32)) inVec = ?;
            Vector#(VecSz, Item#(UInt#(32))) in;

            let rid = rid_fifo[i].first;
            let sid = sid_fifo[i].first;

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
               rid_fifo[i].deq;
               sid_fifo[i].deq;
               term_fifo[i].deq;
            end

            mt.in[i].put(in);
            $display("[@%9d] put[%2d]: ", tick, i, fshow(in));

         end else begin
            mt.in[i].put(replicate(maxItem));
            term_fifo[i].deq;
         end
      endrule

   end

   Reg#(Bool) valid_seq <- mkReg(False);
   rule extract_merger (inited);
      let out <- mt.out.get;

      $display("[@%9d] output No.%4d: ", tick, testCnt, fshow(out));
      if (out[0] != maxItem) begin
         testCnt <= testCnt + 1;

         // compare BSV with C++ results
         Vector#(VecSz, UInt#(32)) outVec = ?;
         let rid = rid_top_fifo.first;
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
         delete_round(rid_top_fifo.first);
         rid_top_fifo.deq;
      end
   endrule

endmodule

