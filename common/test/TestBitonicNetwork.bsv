
import Assert::*;
import ClientServer::*;
import FIFO::*;
import FIFOF::*;
import GetPut::*;
import Vector::*;
import Randomizable::*;

import BitonicNetwork::*;

typedef `VecSz VecSz;
Bool ascending = True;

module mkHalfCleanTest(Empty);
    Reg#(UInt#(32)) testCnt <- mkReg(0);
    Integer rounds = 1;

    /* Randomize#(UInt#(32)) rand_gen <- mkGenericRandomizer; */

    rule tick;
        testCnt <= testCnt + 1;
        if (testCnt == fromInteger(rounds)) begin
            $finish;
        end
    endrule

    /* rule init if (testCnt == 0); */
    /*     rand_gen.cntrl.init(); */
    /* endrule */

    rule doTest;
        Vector#(VecSz, UInt#(32)) inVec;

        /* let v <- rand_gen.next() % 5; */
        let v <- rand32();
        v = v % 5;
        inVec[0] = unpack(v);
        for (Integer i = 1; i < valueOf(TDiv#(VecSz, 2)); i = i + 1) begin
            let u <- rand32();
            u = u % 10;
            inVec[i] = inVec[i-1] + unpack(u);
        end

        v <- rand32();
        v = v % 5;
        inVec[valueof(VecSz) - 1] = unpack(v);
        for (Integer i = valueOf(VecSz) - 2; i >= valueOf(TDiv#(VecSz, 2)); i = i - 1) begin
            let u <- rand32();
            u = u % 10;
            inVec[i] = inVec[i+1] + unpack(u);
        end

        let outVec = halfClean(inVec, ascending);

        $display("Seq[%d] input : ", testCnt, fshow(inVec));
        $display("Seq[%d] output: ", testCnt, fshow(outVec));

    endrule
endmodule

module mkBitonicMergerTest(Empty);
    Reg#(UInt#(32)) tick <- mkReg(0);
    Reg#(UInt#(32)) testCnt <- mkReg(0);
    Integer rounds = 10;

    rule ticktock;
        tick <= tick + 1;
    endrule

    rule finish;
        if (testCnt ==  fromInteger(rounds)) begin
            $finish;
        end
    endrule

    FIFOF#(Vector#(VecSz, UInt#(32)))   inFIFO  <- mkFIFOF;
    FIFO#(Vector#(VecSz, UInt#(32)))    in2FIFO <- mkSizedFIFO(16);
    /* FIFO#(Vector#(VecSz, UInt#(32)))    in2FIFO <- mkFIFO; */
    BitonicMerger#(VecSz, UInt#(32))    merger  <- mkBitonicMergerS(ascending);

    rule gen_data;
        Vector#(VecSz, UInt#(32)) inVec;

        /* let v <- rand_gen.next() % 5; */
        let v <- rand32();
        v = v % 7;
        inVec[0] = unpack(v);
        for (Integer i = 1; i < valueOf(TDiv#(VecSz, 2)); i = i + 1) begin
            let u <- rand32();
            u = u % 13;
            inVec[i] = inVec[i-1] + unpack(u);
        end

        v <- rand32();
        v = v % 7;
        inVec[valueOf(TDiv#(VecSz, 2))] = unpack(v);
        for (Integer i = valueOf(TDiv#(VecSz, 2)) + 1; i < valueOf(VecSz); i = i + 1) begin
            let u <- rand32();
            u = u % 13;
            inVec[i] = inVec[i-1] + unpack(u);
        end

        inFIFO.enq(inVec);
    endrule

    rule doMerge;
        DataBeat#(Vector, VecSz, UInt#(32)) databeat = ?;

        if (inFIFO.notEmpty) begin
            let inVec <- toGet(inFIFO).get;
            in2FIFO.enq(inVec);
            databeat = DataBeat {
                valid: True,
                data: inVec
            };
        end else begin
            databeat = DataBeat {
                valid: False,
                data: ?
            };
        end

        /* $display("[@%d] Push to merger: ", tick, fshow(databeat.valid), fshow(databeat.data)); */
        merger.request.put(databeat);
    endrule

    rule check_result;
        let out <- merger.response.get;
        if (out.valid) begin
            testCnt <= testCnt + 1;
            let inVec <- toGet(in2FIFO).get;
            $display("Seq[%d] input:  ", testCnt, fshow(inVec));
            $display("Seq[%d] output: ", testCnt, fshow(out.data));
            if (!isSorted(out.data, ascending)) begin
                $display("Failed\n");
                $finish;
            end
        end else begin
            $display("Invalid data beat");
        end
        $display("");
    endrule

endmodule

module mkBitonicSorterTest(Empty);
    Reg#(UInt#(32)) tick <- mkReg(0);
    Reg#(UInt#(32)) testCnt <- mkReg(0);
    Integer rounds = 10;

    rule ticktock;
        tick <= tick + 1;
    endrule

    rule finish;
        if (testCnt ==  fromInteger(rounds)) begin
            $finish;
        end
    endrule

    FIFOF#(Vector#(VecSz, UInt#(32)))   inFIFO  <- mkFIFOF;
    FIFO#(Vector#(VecSz, UInt#(32)))    in2FIFO <- mkSizedFIFO(16);
    /* FIFO#(Vector#(VecSz, UInt#(32)))    in2FIFO <- mkFIFO; */
    BitonicSorter#(VecSz, UInt#(32))    sorter  <- mkBitonicSorter(ascending);

    rule gen_data;
        Vector#(VecSz, UInt#(32)) inVec;

        /* let v <- rand_gen.next() % 5; */
        for (Integer i = 0; i < valueOf(VecSz); i = i + 1) begin
            let u <- rand32();
            u = u % 63; 
            inVec[i] = unpack(u);
        end

        inFIFO.enq(inVec);
    endrule

    rule doMerge;
        DataBeat#(Vector, VecSz, UInt#(32)) databeat = ?;

        if (inFIFO.notEmpty) begin
            let inVec <- toGet(inFIFO).get;
            in2FIFO.enq(inVec);
            databeat = DataBeat {
                valid: True,
                data: inVec
            };
        end else begin
            databeat = DataBeat {
                valid: False,
                data: ?
            };
        end

        /* $display("[@%d] Push to sorter: ", tick, fshow(databeat.valid), fshow(databeat.data)); */
        sorter.request.put(databeat);
    endrule

    rule check_result;
        let out <- sorter.response.get;
        if (out.valid) begin
            testCnt <= testCnt + 1;
            let inVec <- toGet(in2FIFO).get;
            $display("Seq[%d] input:  ", testCnt, fshow(inVec));
            $display("Seq[%d] output: ", testCnt, fshow(out.data));
            if (!isSorted(out.data, ascending)) begin
                $display("Failed\n");
                $finish;
            end
        end else begin
            $display("Invalid data beat");
        end
        $display("");
    endrule

endmodule

