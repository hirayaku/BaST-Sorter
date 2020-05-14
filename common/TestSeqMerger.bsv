
import ClientServer::*;
import FIFO::*;
import FIFOF::*;
import GetPut::*;
import Vector::*;
import Randomizable::*;

import MergerTypes::*;
import BitonicNetwork::*;
import SeqMerger::*;

typedef 4 VecSz;
Bool ascending = True;

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
    Reg#(UInt#(32)) testCnt <- mkReg(0);
    Integer rounds = 100;

    rule ticktock;
        tick <= tick + 1;
    endrule

    rule finish;
        if (tick ==  fromInteger(rounds)) begin
            $finish;
        end
    endrule

    FIFOF#(SeqVec#(VecSz, UInt#(32))) fifoA <- mkFIFOF;
    FIFOF#(SeqVec#(VecSz, UInt#(32))) fifoB <- mkFIFOF;
    SeqMerger#(VecSz, UInt#(32)) merger <- mkSeqMerger(ascending);

    Reg#(UInt#(32)) a <- mkReg(1);
    Reg#(UInt#(32)) b <- mkReg(8);

    rule data_fifoA;
        Vector#(VecSz, UInt#(32)) inVec;

        UInt#(32) current = a;
        for (Integer i = 0; i < valueOf(VecSz); i = i + 1) begin
            // let u <- rand32();
            // let delta = u % 10 + 1;
            // current = current + unpack(delta);
            inVec[i] = current;
            current = current + 2;
        end

        a <= current;
        fifoA.enq(SeqVec{round: OddRound, vec: inVec});
        // $display("[%d] inputA: ", tick, fshow(inVec));
    endrule

    rule data_fifoB;
        Vector#(VecSz, UInt#(32)) inVec;

        UInt#(32) current = b;
        for (Integer i = 0; i < valueOf(VecSz); i = i + 1) begin
            // let u <- rand32();
            // let delta = u % 10 + 1;
            // current = current + unpack(delta);
            inVec[i] = current;
            current = current + 2;
        end

        b <= current;
        fifoB.enq(SeqVec{round: OddRound, vec: inVec});
        // $display("[%d] inputB: ", tick, fshow(inVec));
    endrule

    Reg#(Round) round <- mkReg(OddRound);

    rule feed_merger;
        if (!fifoA.notEmpty || !fifoB.notEmpty) begin
            merger.put(DataBeat{valid: False, data: ?}, ?, round);

        end else begin
            let seqVecA = fifoA.first;
            let seqVecB = fifoB.first;
            Vector#(2, SeqVec#(VecSz, UInt#(32))) data;
            data[0] = seqVecA; data[1] = seqVecB;

            DeqSel sel;
            if (cmpSeqVec(seqVecA, seqVecB, ascending)) begin
               // last(vecA.vec) < last(vecB.vec)
               sel = DeqA;
               fifoA.deq;
            end else begin
               sel = DeqB;
               fifoB.deq;
            end

            merger.put(DataBeat{valid: True, data: data}, sel, round);
        end
    endrule

    rule extract_merger;
        let out <- merger.get;
        if (out.valid) begin
            testCnt <= testCnt + 1;
            // $display("[%d] output: ", testCnt, fshow(out.data.vec));
        end
    endrule

endmodule

