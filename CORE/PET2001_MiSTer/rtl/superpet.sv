/*
 * SuperPET expansion board.
 * Written by Olaf Seibert <rhialto@falu.nl> in 2025
 * for use with the MegaPET.
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

/*
 * The SuperPET board is plugged into the socket of the 6502 CPU.
 * Therefore it has (mostly) the same signals.
 * Here we define the ones that are used in the MegaPET.
 *
 * If the SuperPET is not enabled (pref_have_superpet is 0), it just passes on
 * signals to/from the T65 6502 cpu.
 */
module superpet
(
    input    [1:0]  mode,        // "00" => 6502, "01" => 65C02, "10" => 65C816
  //input           bcd_en = 1,  // '0' => 2A03/2A07, '1' => others

    input           res_n,
    input           enable,
    input           clk,
    input           rdy,
    input           abort_n = 1,
    input           irq_n = 1,
    input           nmi_n = 1,
    input           so_n = 1,
    output          r_w_n,
  //output          sync,	// there is no 6809 equivalent
  //output          ef,		// there is no 6809 equivalent
  //output          mf,		// there is no 6809 equivalent
  //output          xf,		// there is no 6809 equivalent
  //output          ml_n,	// there is no 6809 equivalent
  //output          vp_n,	// there is no 6809 equivalent
  //output          vda,	// there is no 6809 equivalent
  //output          vpa,	// there is no 6809 equivalent
    output   [23:0] a,
    input     [7:0] din,
    output    [7:0] dout,
    // 6502 registers (MSB) PC, SP, P, Y, X, A (LSB)
  //output   [63:0] regs,
  //output T_t65_dbg debug,
  //output          nmi_ack
  //
    // Extra signals for management
    input           pref_have_superpet,
    input           pref_enable_6809
);

wire [23:0] a_from_cpu;

assign a = { a_from_cpu[23:17], 1'b0, a_from_cpu[15:0] };

T65 cpu6502
(
    .mode(mode),
    .res_n(res_n),
    .enable(enable),
    .clk(clk),
    .rdy(rdy),
    .abort_n(abort_n),
    .irq_n(irq_n),
    .nmi_n(nmi_n),
    .so_n(so_n),
    .r_w_n(r_w_n),
    .a(a_from_cpu),
    .din(din),
    .dout(dout)
);

endmodule // superpet
