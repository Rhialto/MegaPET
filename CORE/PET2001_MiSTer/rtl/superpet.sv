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
    output          r_w_n,      // 0 is write, 1 is read
  //output          sync,       // there is no 6809 equivalent
  //output          ef,         // there is no 6809 equivalent
  //output          mf,         // there is no 6809 equivalent
  //output          xf,         // there is no 6809 equivalent
  //output          ml_n,       // there is no 6809 equivalent
  //output          vp_n,       // there is no 6809 equivalent
  //output          vda,        // there is no 6809 equivalent
  //output          vpa,        // there is no 6809 equivalent
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

wire [7:0] din_from_mainboard = din;    // give it a better name
reg  [7:0] din_to_cpu;

wire        r_w_n_from_cpu;
wire        r_w_n_to_mainboard;
assign      r_w_n = r_w_n_to_mainboard;

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
    .r_w_n(r_w_n_from_cpu),
    .a(a_from_cpu),
    .din(din_to_cpu),
    .dout(dout)
);

wire spet_extram_sel;   // 9xxx
wire spet_iosel;        // EFxx
wire spet_EFFx;         // EFFx
wire dongle_sel;        // EFE0  EF xxx0 xxxx
wire acia_sel;          // EFF0: EF 1111 00xx
//re acia2_sel;         // EFF4: EF 1111 01xx
wire system_latch_sel;  // EFF8: EF 1111 10xx
wire bank_sw_sel;       // EFFC: EF 1111 110x
wire ramrom_sel;        // EFFE: EF 1111 111x

assign spet_extram_sel  = pref_have_superpet && a_from_cpu[15:12] == 4'h9;
assign spet_iosel       = pref_have_superpet && a_from_cpu[15: 8] == 8'hEF;
assign spet_EFFx        = spet_iosel         && a_from_cpu[ 7: 4] == 4'hF;

assign dongle_sel       = spet_iosel && a_from_cpu[4]   == 1'b0;
assign acia_sel         = spet_EFFx  && a_from_cpu[3:2] == 2'b00;
assign system_latch_sel = spet_EFFx  && a_from_cpu[3:2] == 2'b10;
assign bank_sw_sel      = spet_EFFx  && a_from_cpu[3:1] == 3'b110;
assign ramrom_sel       = spet_EFFx  && a_from_cpu[3:1] == 3'b111;

/*
 * Bank Switch latch.
 */
reg  [7:0] bank_sw;

wire [3:0] bank   = bank_sw[3:0];
wire       ctrlwp = bank_sw[7];         // 1 allows the System Latch to be written.

always @(posedge clk) begin
    if (!res_n) begin
        bank_sw <= 8'h00;
    end else if (enable) begin
        if (bank_sw_sel && !r_w_n_from_cpu) begin
            bank_sw <= dout;
        end
    end
end

/*
 * System Latch
 */
reg [7:0] system_latch;
wire      spet_cpu_switch = system_latch[0];    // 0 is 6809, 1 is 6502
wire      spet_ram_wp     = system_latch[1];    // 0 is write protect, 1 is write enable
wire      spet_diag       = system_latch[2];    // unused, needed only for cpu switch

always @(posedge clk) begin
    if (!res_n) begin
        system_latch <= 8'hFF;
    end else if (enable) begin
        if (ctrlwp && system_latch_sel && !r_w_n_from_cpu) begin
            system_latch <= dout;
        end
    end
end

/*
 * RAM/ROM Latch (not implemented)
 */

/*
 * ACIA 6551 (not implemented)
 */
wire [7:0] data_from_acia = 8'hFF;

/*
 * ACIA 6850 (not implemented; supposedly EFF4-EFF5)
 */

/*
 * 6702 dongle (not implemented yet)
 */
wire [7:0] data_from_6702 = 8'hFF;

/*
 * Expansion memory 9xxx
 */
assign a = spet_extram_sel ? { 8'b1, bank, a_from_cpu[11:0] }
                           : { 8'b0, a_from_cpu[15      :0] };
assign r_w_n_to_mainboard = spet_extram_sel ? r_w_n_from_cpu || !spet_ram_wp
                                            : r_w_n_from_cpu;

///////////////////////////
// Read data mux (to CPU)
///////////////////////////

always @(*)
begin
    casex({spet_extram_sel, spet_iosel, dongle_sel, acia_sel})
        4'b1_x_x_x:  din_to_cpu = din_from_mainboard;
        4'bx_1_0_0:  din_to_cpu = a_from_cpu[15:8];     // approximation of "empty bus"
        4'bx_x_1_x:  din_to_cpu = data_from_6702;
        4'bx_x_x_1:  din_to_cpu = data_from_acia;
        default:     din_to_cpu = din_from_mainboard;
    endcase;
end;


endmodule // superpet
