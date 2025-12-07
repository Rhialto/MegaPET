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

    input           pref_use_6809,
    input    [4:0]  cnt31
);

wire [23:0] a_from_6502;
wire [15:0] a_from_6809;
wire [15:0] a_from_cpu = pref_use_6809 ? a_from_6809 : a_from_6502[15:0];

wire [7:0]  dout_from_6809;
wire [7:0]  dout_from_6502;
assign dout = pref_use_6809 ? dout_from_6809 : dout_from_6502;

wire        r_w_n_from_6502;
wire        r_w_n_from_6809;
wire        r_w_n_from_cpu =  pref_use_6809 ? r_w_n_from_6809 : r_w_n_from_6502;

wire        r_w_n_to_mainboard;         // possibly modified by R/O switch for ext ram
assign      r_w_n = r_w_n_to_mainboard;

wire [7:0] din_from_mainboard = din;    // to give it a better name
reg  [7:0] din_to_cpu;

T65 cpu6502
(
    .mode(mode),
    .res_n(res_n && !pref_use_6809),
    .enable(enable),
    .clk(clk),
    .rdy(rdy),
    .abort_n(abort_n),
    .irq_n(irq_n),
    .nmi_n(nmi_n),
    .so_n(so_n),
    .r_w_n(r_w_n_from_6502),
    .a(a_from_6502),
    .din(din_to_cpu),
    .dout(dout_from_6502)
);

wire spet_extram_sel;   // 9xxx or os9flat
wire spet_iosel;        // EFxx
wire spet_EFFx;         // EFFx
wire dongle_sel;        // EFE0  EF xxx0 xxxx
wire acia_sel;          // EFF0: EF 1111 00xx
//re acia2_sel;         // EFF4: EF 1111 01xx
wire system_latch_sel;  // EFF8: EF 1111 10xx
wire bank_sw_sel;       // EFFC: EF 1111 110x
wire ramrom_sel;        // EFFE: EF 1111 111x
wire os9flat;           // flat memory mapping in effect for OS/9

assign spet_extram_sel  = pref_have_superpet && (a_from_cpu[15:12] == 4'h9   ||  os9flat);
assign spet_iosel       = pref_have_superpet && (a_from_cpu[15: 8] == 8'hEF) && !os9flat;
assign spet_EFFx        = spet_iosel         && (a_from_cpu[ 7: 4] == 4'hF);

assign dongle_sel       = spet_iosel && a_from_cpu[4]   == 1'b0;
assign acia_sel         = spet_EFFx  && a_from_cpu[3:2] == 2'b00;
assign system_latch_sel = spet_EFFx  && a_from_cpu[3:2] == 2'b10;
assign bank_sw_sel      = spet_EFFx  && a_from_cpu[3:1] == 3'b110;
assign ramrom_sel       = spet_EFFx  && a_from_cpu[3:1] == 3'b111;

/*
 * Bank Switch latch.
 */
reg  [7:0] bank_sw;

wire [3:0] bank    = bank_sw[3:0];
wire       syncdis = bank_sw[5];        // also named firq-disable
wire       os9sel  = bank_sw[6];        // OS/9 flat memory mapping
wire       ctrlwp  = bank_sw[7];        // 1 allows the System Latch to be written.
wire       sync_happened;               // resets OS/9 flat memory mapping

always @(posedge clk) begin
    if (!res_n || sync_happened) begin
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
wire [7:0] data_from_acia = 8'h00;

/*
 * ACIA 6850 (not implemented; supposedly EFF4-EFF5)
 */

/*
 * 6702 dongle.
 *
 *                7654 3210
 * Selected at EF xxx0 xxxx, but internally has CS that effectively
 *                111  00xx
 * make it EFE0...3.
 */

wire [7:0] data_from_6702;

mos6702 dongle
(
    .clk(clk),
    .ce(enable),
    .reset(!res_n),

    .data_in(dout),
    .data_out(data_from_6702),
    .write(!r_w_n_from_cpu),
    .cs({a_from_cpu[2], a_from_cpu[3], !dongle_sel,                     // 6:4 must be all 0
         a_from_cpu[5], a_from_cpu[6], a_from_cpu[7], a_from_cpu[7]})   // 3:0 must be all 1
);

/*
 * Expansion memory 9xxx (actually implemented on the main board)
 */
assign a = os9flat         ? { 8'b00000001, a_from_cpu[15      :0] } :
           spet_extram_sel ? { 8'b00000001, bank, a_from_cpu[11:0] }
                           : { 8'b00000000, a_from_cpu[15      :0] };
assign r_w_n_to_mainboard = spet_extram_sel ? r_w_n_from_cpu || !spet_ram_wp
                                            : r_w_n_from_cpu;

///////////////////////////
// The other cpu: 6809
///////////////////////////

/*
 * Use cnt31 to generate E and Q. They must go like this:
 *
 *    +    +----+
 * E  |    |    |
 *    +----+    +....
 *
 *      +----+
 * Q    |    |
 *    --+    +---...
 *
 * It changes its state to the next one on the falling edge of E.
 *
 * Basic idea:
 * E = cnt31[4];
 * Q = cnt31[4] ^ cnt31[3];
 *
 * but we need to shift the falling edge of E a bit later so it corresponds to
 * the falling edge of "enable" aka "ce_1m". Remember that ce_1m is set in
 * reaction to cnt31==0, so it is 1 while cnt31 is 1.
 *
 * We don't care so much about the exact edges of Q.
 */
reg E;
always @(posedge clk) begin
    if (!pref_use_6809) begin
        E <= 1;
    end else begin
        E <= cnt31[4] || (cnt31 == 0);
    end
end

wire Q = pref_use_6809 && (cnt31[4] ^ cnt31[3]);

// Latch the Data towards the 6809 on the rising edge of "enable" since
// the 6502 uses the data at that point.
// The 6809 uses the bus inputs continuously (most of its logic is
// combinatorial). So we make sure that D remains constant from one rising
// edge of "enable" to the next.

    (* dont_touch = "false", mark_debug = "false" *)
reg [7:0] din_to_6809;

// Transparent latch for din_to_6809:
// when enable goes/is high, latch the value until the next time it goes high.
/* Latches are apparently bad...
always @(enable or din_to_cpu or pref_use_6809) begin
    if (enable && pref_use_6809) begin
        din_to_6809 = din_to_cpu;
    end
end
*/
// so instead we use a flipflop and accept the 1-clock delay by
// sampling one clock earlier.
always @(posedge clk) begin
    if (cnt31 == 0 && pref_use_6809) begin
        din_to_6809 <= din_to_cpu;
    end
end

wire bs, ba;                    // for SuperOS9 MMU
assign sync_happened = ba && !bs && !syncdis;
wire nfirq = !sync_happened;    // for SuperOS9 MMU
assign os9flat = pref_use_6809 && os9sel && !ba;

mc6809e cpu6809e
(
    .D(din_to_6809),            // input   [7:0] D,
    .DOut(dout_from_6809),      // output  [7:0] DOut,
    .ADDR(a_from_6809),         // output  [15:0] ADDR,
    .RnW(r_w_n_from_6809),      // output  RnW,
    .E(E),                      // input   E,
    .Q(Q),                      // input   Q,
    .BS(bs),                    // output  BS,
    .BA(ba),                    // output  BA,
    .nIRQ(irq_n || !pref_use_6809),// input   nIRQ,
    .nFIRQ(nfirq),              // input   nFIRQ,
    .nNMI(nmi_n || !pref_use_6809),// input   nNMI,
    .AVMA(),                    // output  AVMA,
    .BUSY(),                    // output  BUSY,
    .LIC(),                     // output  LIC,
    .nHALT(1'b1),               // input   nHALT,
    .nRESET(res_n)              // input   nRESET
);

// 6809-specific ROMs. 3 x 8 KB.


wire io_gap     = (a_from_6809[15:11] == 5'b1110_1);    // E800 - EFFF

wire rom_ab_sel = pref_use_6809 && (a_from_6809[15:13] == 3'b101)            && !os9flat;
wire rom_cd_sel = pref_use_6809 && (a_from_6809[15:13] == 3'b110)            && !os9flat;
wire rom_ef_sel = pref_use_6809 && (a_from_6809[15:13] == 3'b111) && !io_gap && !os9flat;

wire [7:0] rom_ab_data;
wire [7:0] rom_cd_data;
wire [7:0] rom_ef_data;

dualport_2clk_ram #(
        .addr_width(13),
        .data_width(8),
        .rom_preload(1),
        .rom_file_hex(1),
        // Relative to PET_MEGA65/CORE/CORE-R6.runs/synth_1 (or sth.)
        .rom_file("../../PET2001_MiSTer/roms/waterloo-a000-bfff.970018-12.hex")
        //.falling_b(1)
) waterloo_ab (
        // A: Access from CPU
        .address_a(a_from_6809[12:0]),
        .data_a(),
        .q_a(rom_ab_data),
        .wren_a(0),
        .clock_a(clk)

        // B: Access from QNICE on falling edge
        //.address_b(dma_addr[14:0]),
        //.data_b(dma_din),
        //.q_b(dma_rom_dout),
        //.wren_b(dma_we & ),
        //.clock_b(dma_clk)
);

dualport_2clk_ram #(
        .addr_width(13),
        .data_width(8),
        .rom_preload(1),
        .rom_file_hex(1),
        // Relative to PET_MEGA65/CORE/CORE-R6.runs/synth_1 (or sth.)
        .rom_file("../../PET2001_MiSTer/roms/waterloo-c000-dfff.970019-12.hex")
        //.falling_b(1)
) waterloo_cd (
        // A: Access from CPU
        .address_a(a_from_6809[12:0]),
        .data_a(),
        .q_a(rom_cd_data),
        .wren_a(0),
        .clock_a(clk)

        // B: Access from QNICE on falling edge
        //.address_b(dma_addr[14:0]),
        //.data_b(dma_din),
        //.q_b(dma_rom_dout),
        //.wren_b(dma_we & ),
        //.clock_b(dma_clk)
);

dualport_2clk_ram #(
        .addr_width(13),
        .data_width(8),
        .rom_preload(1),
        .rom_file_hex(1),
        // Relative to PET_MEGA65/CORE/CORE-R6.runs/synth_1 (or sth.)
        .rom_file("../../PET2001_MiSTer/roms/waterloo-e000-ffff.970020-12.hex")
        //.falling_b(1)
) waterloo_ef (
        // A: Access from CPU
        .address_a(a_from_6809[12:0]),
        .data_a(),
        .q_a(rom_ef_data),
        .wren_a(0),
        .clock_a(clk)

        // B: Access from QNICE on falling edge
        //.address_b(dma_addr[14:0]),
        //.data_b(dma_din),
        //.q_b(dma_rom_dout),
        //.wren_b(dma_we & ),
        //.clock_b(dma_clk)
);

///////////////////////////
// Read data mux (to CPU)
///////////////////////////

always @(*)
begin
    casex({rom_ab_sel, rom_cd_sel, rom_ef_sel, spet_extram_sel, spet_iosel, dongle_sel, acia_sel})
        7'b1_x_x_x_x_x_x:  din_to_cpu = rom_ab_data;            // Axxx, Bxxx
        7'bx_1_x_x_x_x_x:  din_to_cpu = rom_cd_data;            // Cxxx, Dxxx
        7'bx_x_1_x_x_x_x:  din_to_cpu = rom_ef_data;            // Exxx, Fxxx, but not E800-EFFF
        7'bx_x_x_1_x_x_x:  din_to_cpu = din_from_mainboard;     // 9xxx
        7'bx_x_x_x_1_0_0:  din_to_cpu = a_from_cpu[15:8];       // EFxx  approximation of "empty bus"
        7'bx_x_x_x_x_1_x:  din_to_cpu = data_from_6702;         // EFE0
        7'bx_x_x_x_x_x_1:  din_to_cpu = data_from_acia;         // EFF0
        default:           din_to_cpu = din_from_mainboard;
//         ^ ^ ^ ^ ^ ^ ^
//         | | | | | | +--- acia_sel
//         | | | | | +----- dongle_sel
//         | | | | +------- spet_iosel EFxx
//         / | | +--------- spet_extram_sel
//       ab cd ef
    endcase;
end;


endmodule // superpet
