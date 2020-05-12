
import ClientServer::*;
import FIFO::*;
import FIFOF::*;
import GetPut::*;
import Vector::*;

import BitonicNetwork::*;

// Pipelined Merger Unguarded
// Implemented recursively in typeclass `MergerN`
// Methods:
// request.put          =>      submit streams of n-sequences to be merged
// response.get         =>      get a sorted n-sequence, flagged by `valid`
typedef Server#(
    DataBeat#(3, Vector#(n, itype)),
    DataBeat#(n, itype)
) MergerInner#(numeric type n, type itype);

typedef Server#(
    DataBeat#(2, Vector#(n, itype)),
    DataBeat#(n, itype)
) Merger#(numeric type n, type itype);

module mkMergerInner#(Bool ascending) (MergerInner#(n, itype))
    provisos(Bits#(Vector::Vector#(n, itype), vWidth),
             Ord#(itype),
             Bits#(itype, eWidth),
             NumAlias#(TMul#(n, 2), nn),
             Add#(n, a__, nn),
             BitonicMergerN#(nn, itype),
             NumAlias#(TMul#(TLog#(nn), 2), fifoD));

    BitonicMerger#(nn, itype) mergerA <- mkBitonicMergerS(ascending);
    BitonicMerger#(nn, itype) mergerB <- mkBitonicMergerS(ascending);
    // FIFO depth should ensure stall is impossible
    // XXX: replace FIFO with shift registers if this is the bottleneck when n grows
    FIFO#(Vector#(n, itype))  pending <- mkSizedFIFO(valueOf(fifoD));
    FIFO#(Bool)               validQ  <- mkSizedFIFO(valueOf(fifoD));

    rule mergeA2B;
        let valid <- toGet(validQ).get;

        let outA <- mergerA.response.get;
        let bottomVec12 = drop(outA.data);
        let vec3 <- toGet(pending).get;
        let inVec = append(vec3, bottomVec12);

        mergerB.request.put(DataBeat {
            valid: valid,
            data: inVec
        });
    endrule

    interface Put request;
        // request.put should be called **every cycle** by outer modules
        method Action put(DataBeat#(3, Vector#(n, itype)) in);
            let valid = in.valid;
            let vec1 = in.data[0];
            let vec2 = in.data[1];
            let vec3 = in.data[2];
            let vec12 = append(vec1, vec2);

            validQ.enq(valid);
            pending.enq(vec3);

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
                data: outVec
            };
        endmethod
    endinterface

endmodule

module mkMerger#(Bool ascending) (Merger#(n, itype))
    provisos(Bits#(Vector::Vector#(n, itype), vWidth),
             Bits#(itype, eWidth),
             Eq#(itype),
             Ord#(itype),
             Literal#(itype),
             NumAlias#(TMul#(n, 2), nn),
             BitonicMergerN#(nn, itype),
             NumAlias#(TMul#(TLog#(nn), 2), fifoD));

    MergerInner#(n, itype) merger_i <- mkMergerInner;

    Reg#(Vector#(n, itype)) lastVec <- mkReg(replicate(0));

    interface Put request;
        method Action put(DataBeat#(2, Vector#(n, itype)) in);
            let vecA = in.data[0];
            let vecB = in.data[1];

            let inData = DataBeat {
                valid: in.valid,
                data: append(append(vecA, vecB), lastVec)
            };

            merger_i.request.put(inData);

            if (in.valid) begin
                // update lastVec only when the input is valid
                if (last(vecA) < last(vecB)) begin
                    lastVec <= vecA;
                end else begin
                    lastVec <= vecB;
                end
            end
        endmethod
    endinterface

    interface Get response = merger_i.response.get;

endmodule

