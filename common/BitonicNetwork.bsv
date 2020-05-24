
/* import Pipe::*; */
import ClientServer::*;
import FIFO::*;
import FIFOF::*;
import GetPut::*;
import Vector::*;
import MergerTypes::*;

// Compare-and-Swap circuit
function Tuple2#(itype, itype) cas(Tuple2#(itype, itype) inTup, Bool ascending)
    provisos(Ord#(itype));

    let {a, b} = inTup;
    return (pack(a>b)^pack(!ascending))==1? tuple2(b,a): tuple2(a,b);

endfunction

// Half cleaner (combinational logic)
// Arguments:
// inVec        =>      input bitonic sequences (first sequence ascending)
// ascending    =>      indicating cas circuit direction
function Vector#(n, itype) halfClean(Vector#(n, itype) inVec, Bool ascending)
    provisos(Mul#(TDiv#(n, 2), 2, n), Ord#(itype));

    Vector#(TDiv#(n, 2), itype) top = take(inVec);
    Vector#(TDiv#(n, 2), itype) bottom = drop(inVec);

    function Tuple2#(itype, itype) casF(Tuple2#(itype, itype) in) = cas(in, ascending);
    let outTuples = map(casF, zip(top, bottom));
    let {outTop, outBottom} = unzip(outTuples);

    return append(outTop, outBottom);

endfunction


// Pipelined Butterfly Merger Network Unguarded
// It only merges two sorted sequences coming in the same cycle
// Implemented recursively in typeclass `BitonicMergerN`
// Methods:
// request.put          =>      submit a bitonic sequence (DataBeat) to be merged
// response.get         =>      get a merged sequence (DataBeat), flagged by `valid`
typedef Server#(
    DataBeat#(n, itype),
    DataBeat#(n, itype)
) BitonicMerger#(numeric type n, type itype);

// interface BitonicMerger#(numeric type n, type itype);
//    (* always_ready *)
//    interface Put#(DataBeat#(n, itype)) request;
//    (* always_ready *)
//    interface Get#(DataBeat#(n, itype)) response;
// endinterface

typeclass BitonicMergerN#(numeric type n, type itype);
    module mkBitonicMerger#(Bool ascending) (BitonicMerger#(n, itype));
    // A variant of original bitonic merger: input are two sorted subsequences in the same direction
    // (the second sequence is reversed)
    module mkBitonicMergerS#(Bool ascending) (BitonicMerger#(n, itype));
endtypeclass

// Base instances
instance BitonicMergerN#(2, itype)
    provisos(Bits#(Vector::Vector#(2, itype), bitWidth),
             Ord#(itype));

    module mkBitonicMerger#(Bool ascending) (BitonicMerger#(2, itype));

        Reg#(Bool) stageValid <- mkReg(False);
        Reg#(Vector#(2, itype)) stage <- mkRegU;

        interface Put request;
            // this method should be called **every cycle** by outer modules
            method Action put(DataBeat#(2, itype) in);
                stage <= halfClean(in.data, ascending);
                stageValid <= in.valid;
            endmethod
        endinterface

        interface Get response;
            method ActionValue#(DataBeat#(2, itype)) get;
                return DataBeat {
                    valid: stageValid,
                    data: stage
                };
            endmethod
        endinterface

    endmodule

    module mkBitonicMergerS#(Bool ascending) (BitonicMerger#(2, itype));
        BitonicMerger#(2, itype) merger <- mkBitonicMerger(ascending);
        interface Put request = merger.request;
        interface Get response = merger.response;
    endmodule

endinstance

// Derivative instances
instance BitonicMergerN#(n, itype)
    provisos(Bits#(Vector::Vector#(n, itype), bitWidth),
             Ord#(itype),
             NumAlias#(TDiv#(n, 2), n2),
             Mul#(n2, 2, n),
             BitonicMergerN#(n2, itype));

    module mkBitonicMerger#(Bool ascending) (BitonicMerger#(n, itype));
        Reg#(Bool) stageValid <- mkReg(False);
        Reg#(Vector#(n, itype)) stage <- mkRegU;

        Vector#(2, BitonicMerger#(n2, itype)) childMergers <- replicateM(mkBitonicMerger(ascending));

        (* fire_when_enabled, no_implicit_conditions *)
        rule doStageTop;
            childMergers[0].request.put(DataBeat {
                valid: stageValid,
                data: take(stage)
            });
        endrule

        (* fire_when_enabled, no_implicit_conditions *)
        rule doStageBottom;
            childMergers[1].request.put(DataBeat {
                valid: stageValid,
                data: drop(stage)
            });
        endrule

        interface Put request;
            // this method should be called **every cycle** by outer modules
            method Action put(DataBeat#(n, itype) in);
                stage <= halfClean(in.data, ascending);
                stageValid <= in.valid;
            endmethod
        endinterface

        interface Get response;
            method ActionValue#(DataBeat#(n, itype)) get;
                let top <- childMergers[0].response.get;
                let bottom <- childMergers[1].response.get;
                return DataBeat {
                    valid: top.valid,
                    data: append(top.data, bottom.data)
                };
            endmethod
        endinterface

    endmodule

    module mkBitonicMergerS#(Bool ascending) (BitonicMerger#(n, itype));
        Reg#(Bool) stageValid <- mkReg(False);
        Reg#(Vector#(n, itype)) stage <- mkRegU;

        Vector#(2, BitonicMerger#(n2, itype)) childMergers <- replicateM(mkBitonicMerger(ascending));

        (* fire_when_enabled, no_implicit_conditions *)
        rule doStageTop;
            childMergers[0].request.put(DataBeat {
                valid: stageValid,
                data: take(stage)
            });
        endrule

        (* fire_when_enabled, no_implicit_conditions *)
        rule doStageBottom;
            childMergers[1].request.put(DataBeat {
                valid: stageValid,
                data: drop(stage)
            });
        endrule

        interface Put request;
            // this method should be called **every cycle** by outer modules
            method Action put(DataBeat#(n, itype) in);
                Vector#(n2, itype) top = take(in.data);
                Vector#(n2, itype) bottom = reverse(drop(in.data));
                stage <= halfClean(append(top, bottom), ascending);
                stageValid <= in.valid;
            endmethod
        endinterface

        interface Get response;
            method ActionValue#(DataBeat#(n, itype)) get;
                let top <- childMergers[0].response.get;
                let bottom <- childMergers[1].response.get;
                return DataBeat {
                    valid: top.valid,
                    data: append(top.data, bottom.data)
                };
            endmethod
        endinterface
    endmodule
endinstance



// Pipelined Bitonic Sorter Unguarded
// Implemented recursively in typeclass `BitonicSorterN`
// Methods:
// request.put          =>      submit a sequence to be sorted
// response.get         =>      get a sorted sequence, flagged by `valid`

typedef Server#(
    DataBeat#(n, itype),
    DataBeat#(n, itype)
) BitonicSorter#(numeric type n, type itype);

typeclass BitonicSorterN#(numeric type n, type itype);
    module mkBitonicSorter#(Bool ascending) (BitonicSorter#(n, itype));
endtypeclass

// Base instances
instance BitonicSorterN#(2, itype)
    provisos(Bits#(Vector::Vector#(2, itype), bitWidth),
             Ord#(itype));

    module mkBitonicSorter#(Bool ascending) (BitonicSorter#(2, itype));

        BitonicMerger#(2, itype) merger <- mkBitonicMergerS(ascending);

        // request.put should be called **every cycle** by outer modules
        interface Put request = merger.request;
        interface Get response = merger.response;

    endmodule

endinstance

// Derivative instances
instance BitonicSorterN#(n, itype)
    provisos(Bits#(Vector::Vector#(n, itype), bitWidth),
             Ord#(itype),
             BitonicMergerN#(n, itype),
             NumAlias#(TDiv#(n, 2), n2),
             Mul#(n2, 2, n),
             BitonicSorterN#(n2, itype),
             Add#(n2, a__, n));

    module mkBitonicSorter#(Bool ascending) (BitonicSorter#(n, itype));

        // two sub-sorters + one merger
        Vector#(2, BitonicSorter#(n2, itype)) childSorters <- replicateM(mkBitonicSorter(ascending));
        BitonicMerger#(n, itype) merger <- mkBitonicMergerS(ascending);

        (* fire_when_enabled, no_implicit_conditions *)
        rule doMerge;
            let top <- childSorters[0].response.get;
            let bottom <- childSorters[1].response.get;
            merger.request.put(DataBeat {
                valid: top.valid,
                data: append(top.data, bottom.data)
            });
        endrule

        interface Put request;
            // request.put should be called **every cycle** by outer modules
            method Action put(DataBeat#(n, itype) in);
                Vector#(n2, itype) top = take(in.data);
                Vector#(n2, itype) bottom = drop(in.data);
                childSorters[0].request.put(DataBeat{
                    valid: in.valid,
                    data: top
                });
                childSorters[1].request.put(DataBeat{
                    valid: in.valid,
                    data: bottom
                });
            endmethod
        endinterface

        interface Get response = merger.response;
    endmodule

endinstance

// Utility function for simulation
// isSorted: check if a vector is sorted
function Bool isSorted(Vector#(n, itype) in, Bool ascending)
   provisos(Ord#(itype));

   Bool unSorted = False;
   for (Integer i = 1; i < valueOf(n); i = i + 1) begin
      if ( ascending ) begin
         unSorted = in[i-1] > in[i] || unSorted;
      end
      else begin
         unSorted = in[i-1] < in[i] || unSorted;
      end
   end
   return !unSorted;

endfunction

