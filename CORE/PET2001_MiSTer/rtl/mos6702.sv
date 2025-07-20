/*
 * SuperPET dongle, the 6702.
 *
 * Written by Olaf Seibert <rhialto@falu.nl> in 2025
 * for use with the MegaPET.
 *
 * With thanks to the same people who made the implementation in VICE possible,
 * and
 * http://forum.6502.org/viewtopic.php?f=4&t=6674
 * https://www.forum64.de/index.php?thread/116391-mos6702-superpet-mmf9000-dongle-dissected/
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 * * Redistributions of source code must retain the above copyright
 *   notice, this list of conditions and the following disclaimer.
 * * Redistributions in binary form must reproduce the above copyright
 *   notice, this list of conditions and the following disclaimer in the
 *   documentation and/or other materials provided with the distribution.
 * * The names of contributors may not be used to endorse or promote products
 *   derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL Thomas Skibo OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

module shifter #(
    parameter L=8,                      // length
    parameter P=0                       // polarity of output
)(
    input           reset,
    input           clk,
    input           ce,

    input           data_in,
    output          data_out
);

reg [L-1:0] register;

assign data_out = register[0] ^ P;

always @(posedge clk) begin
    if (reset) begin
        register <= 0;
    end else if (ce) begin
        if (L == 1) begin
            register <= { data_in ^ data_out };
        end else begin
            register <= { data_in ^ data_out, register[L-1:1] };
        end
    end
end

endmodule // shifter

module mos6702
(
    input            clk,
    input            ce,
    input            reset,

    input      [7:0] data_in,
    output reg [7:0] data_out,
    input            write,		// 1 = write
    input      [6:0] cs                 // 7 chip selects
);

reg        doshift;
reg        prev_d0;
reg  [7:0] inputs;
wire [7:0] outputs;
wire       selected = (cs == 7'b0001111);  // EF xxx0 xxxx -> EFE0..3
assign     data_out = selected ? outputs : 8'hFF;

shifter #(2, 1) shifter7(reset, clk, doshift, inputs[7], outputs[7]);
shifter #(5, 1) shifter6(reset, clk, doshift, inputs[6], outputs[6]);
shifter #(3, 0) shifter5(reset, clk, doshift, inputs[5], outputs[5]);
shifter #(1, 1) shifter4(reset, clk, doshift, inputs[4], outputs[4]);
shifter #(8, 0) shifter3(reset, clk, doshift, inputs[3], outputs[3]);
shifter #(7, 1) shifter2(reset, clk, doshift, inputs[2], outputs[2]);
shifter #(3, 1) shifter1(reset, clk, doshift, inputs[1], outputs[1]);
shifter #(6, 0) shifter0(reset, clk, doshift, inputs[0], outputs[0]);

always @(posedge clk) begin
    if (reset) begin
        doshift <= 0;
        prev_d0 <= 1;                           // require an even value first
    end else begin
        doshift <= 0;

        if (ce) begin
            if (selected) begin
                if (write) begin
                    prev_d0 <= data_in[0];

                    if (data_in[0] && !prev_d0) begin   // rising edge triggers shift
                        doshift <= 1;
                        inputs <= data_in;      // buffer inputs, just in case
                    end
                end
            end
        end
    end
end

endmodule // mos6702

