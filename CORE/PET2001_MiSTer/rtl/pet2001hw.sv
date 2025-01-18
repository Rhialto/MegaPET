`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////
//
// Initial Engineer (2001 Model):          Thomas Skibo
// Brought to 3032 and 4032 (non CRTC):    Ruben Aparicio
// Added disk drive, cycle exact video, CRTC, etc: Olaf "Rhialto" Seibert
//
// Create Date:      Sep 23, 2011
//
// Module Name:      pet2001hw
//
// Description:      Encapsulate all Pet hardware except cpu.
//
//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
//
// Copyright (C) 2011, Thomas Skibo.  All rights reserved.
// Copyright (C) 2019, Ruben Aparicio.  All rights reserved.
// Copyright (C) 2025, Olaf 'Rhialto' Seibert.  All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
// * Redistributions of source code must retain the above copyright
//   notice, this list of conditions and the following disclaimer.
// * Redistributions in binary form must reproduce the above copyright
//   notice, this list of conditions and the following disclaimer in the
//   documentation and/or other materials provided with the distribution.
// * The names of contributors may not be used to endorse or promote products
//   derived from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL Thomas Skibo OR CONTRIBUTORS BE LIABLE FOR
// ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
// LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
// OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
// SUCH DAMAGE.
//
//////////////////////////////////////////////////////////////////////////////

module pet2001hw
(
        input [15:0]     addr, // CPU Interface
        input [7:0]      data_in,
        output reg [7:0] data_out,
        input            we,
        output           irq,

        output           ce_pixel_o,
        output           pix_o,
        output           HSync_o,
        output           VSync_o,
        output           HBlank_o,
        output           VBlank_o,
        input            pref_eoi_blanks,       // use as generic for 2001-specifics
        input            pref_have_crtc,
        input            pref_have_80_cols,

        output [3:0]     keyrow, // Keyboard
        input  [7:0]     keyin,

        output           cass_motor_n, // Cassette
        output           cass_write,
        input            cass_sense_n,
        input            cass_read,
        output           audio, // CB2 audio

        // IEEE-488
        input      [7:0] ieee488_data_i,
        output     [7:0] ieee488_data_o,
        input            ieee488_atn_i,
        output           ieee488_atn_o,
        output           ieee488_ifc_o,
        input            ieee488_srq_i,
        input            ieee488_dav_i,
        output           ieee488_dav_o,
        input            ieee488_eoi_i,
        output           ieee488_eoi_o,
        input            ieee488_nrfd_i,
        output           ieee488_nrfd_o,
        input            ieee488_ndac_i,
        output           ieee488_ndac_o,

        // QNICE clock domain via dma_clk
        input            dma_clk,
        input  [14:0]    dma_addr,
        input   [7:0]    dma_din,
        output  [7:0]    dma_dout,
        input            dma_we,
        input            dma_char_ce,   // select character rom instead of basic/edit/kernal

        input            clk_speed,     // unused
        input            clk_stop,      // unused
        input            diag_l,
        input            clk,
        input [4:0]      cnt31_i,
        input            ce_1m,
        input            reset
);

/////////////////////////////////////////////////////////////
// Pet ROMS excluding character ROM.
/////////////////////////////////////////////////////////////
wire [7:0]      rom_data;

wire rom_wr = dma_we & ~dma_char_ce;
wire chars_wr = dma_we & dma_char_ce;

wire [7:0]      dma_rom_dout;
wire [7:0]      dma_char_dout;

assign dma_dout = dma_char_ce ? dma_char_dout : dma_rom_dout;

// System ROMs

// dpram #(.addr_width(15), .mem_init_file("./roms/PET2001-BASIC4.mif")) pet2001rom
dualport_2clk_ram #(
        .addr_width(15),
        .data_width(8),
        .rom_preload(1),
        .rom_file_hex(1),
        // Relative to PET_MEGA65/CORE/CORE-R6.runs/synth_1 (or sth.)
        .rom_file("../../PET2001_MiSTer/roms/PET2001-BASIC4.hex"),
        .falling_b(1)
) pet2001rom (
        // A: Access from CPU
        .address_a(addr[14:0]),
        .data_a(),
        .q_a(rom_data),
        .wren_a(0),
        .clock_a(clk),

        // B: Access from QNICE on falling edge
        .address_b(dma_addr[14:0]),
        .data_b(dma_din),
        .q_b(dma_rom_dout),
        .wren_b(rom_wr),
        .clock_b(dma_clk & ~dma_char_ce)
);

/////////////////////////////////////////////////////////////
// Character ROM
/////////////////////////////////////////////////////////////

wire [11:0]     charaddr;
wire [7:0]      chardata;

dualport_2clk_ram #(
        .addr_width(12),        // 4 KB: double size (SuperPET) ROM
        .data_width(8),
        .rom_preload(1),
        .rom_file_hex(1),
        // Relative to PET_MEGA65/CORE/CORE-R6.runs/synth_1 (or sth.)
        .rom_file("../../PET2001_MiSTer/roms/characters.901640-01.hex"), // was PET3032-chars.hex
    .falling_b(1)
) pet2001chars (
        // A: Access from video system
        .address_a(charaddr),
        .q_a(chardata),
        .clock_a(clk),

        // B: Access from QNICE on falling edge
        .address_b(dma_addr[10:0]),
        .data_b(dma_din),
        .q_b(dma_char_dout),
        .wren_b(chars_wr),
        .clock_b(dma_clk & dma_char_ce)
);

//////////////////////////////////////////////////////////////
// Pet RAM.
//////////////////////////////////////////////////////////////
wire [7:0]      ram_data;

wire    ram_we  = we && ~addr[15];

//32KB RAM
dualport_2clk_ram #(.addr_width(15)) pet2001ram
(
        .clock_a(clk),
        .q_a(ram_data),
        .data_a(data_in),
        .address_a(addr[14:0]),
        .wren_a(ram_we)

        // Not accessible to QNICE for now.
);

//////////////////////////////////////
// Video timing.
// One CPU clock (1 character) is divided into 32 subclocks.
// Derive the pixel clock from this, and loading the shift register.
//////////////////////////////////////
reg     vram_cpu_video;         // 1=cpu, 0=video
reg     load_sr; // Load the video shift register. Name from schematic 8032087.
reg     ce_pixel;
reg     ce_8m;

/*
 * Select who owns the bus. Video needs to fetch from the screen matrix,
 * then look up in the character ROM.
 * Also time the pixels and load the shift register at the same time as
 * a pixel.
 *
 * For the CPU, ce_1m is set when cnt31_i == 0. It expects to read data the
 * next time ce_1m == 1, so in between we can play with the bus.
 * Data written by the CPU are on its bus the whole time between the times
 * when ce_1m == 1. Playing with the vram's bus will make it write the same
 * thing twice.
 */
always @(posedge clk)
begin
    ce_pixel <= pref_have_80_cols ? (cnt31_i[0] == 1)     // every 2 clocks
                                  : (cnt31_i[1:0] == 1);  // every 4 clocks
    ce_8m <= (cnt31_i[1:0] == 1);  // every 4 clocks

    if (cnt31_i == 3) begin
        vram_cpu_video <= 0;    // video; could be <= !chosen_de?
    end else if (cnt31_i == 5) begin
        vram_cpu_video <= 1;    // cpu again.
        load_sr <= 1;   // ce_pixel must be true at the same time; <= !chosen_de ?
    end else if (cnt31_i == 6) begin
        load_sr <= 0;
    end else if (pref_have_80_cols) begin
        if (cnt31_i == 16+3) begin
            vram_cpu_video <= 0;    // video; could be <= !chosen_de?
        end else if (cnt31_i == 16+5) begin
            vram_cpu_video <= 1;    // cpu again.
            load_sr <= 1;   // ce_pixel must be true at the same time; <= !chosen_de ?
        end else if (cnt31_i == 16+6) begin
            load_sr <= 0;
        end
    end;
end;

assign ce_pixel_o = ce_pixel;

//////////////////////////////////////
// Video RAM.
// The video hardware shares access to VRAM some of the time.
//////////////////////////////////////
// On the 2001, video RAM is mirrored all the way up to $8FFF.
// Later models only mirror up to $87FF.

wire [7:0]      vram_data;
wire [9:0]      video_addr;     /* 1 KB */

wire    vram_sel = (addr[15:11] == 5'b1000_0) ||
                   (pref_eoi_blanks && addr[15:12] == 4'b1000);
wire    vram_we = we && vram_sel && vram_cpu_video;

// The address bus for VRAM (2 KB) is multiplexed.
// On the 2001, the CPU always has priority, so the address is from the cpu if
// vram_sel is true.
// For later models, also vram_cpu_video must be true.
// pref_eoi_blanks is the indicator that the first behaviour is wanted.

wire [10:0] vram_addr_cpu;
wire [10:0] vram_addr_vid;
wire [10:0] vram_addr;

assign vram_addr_cpu = pref_have_80_cols ? addr[10:0]
                                         : { 1'b0, addr[9:0] };
assign vram_addr_vid = pref_have_80_cols ? { video_addr[9:0], cnt31_i[4] }
                                         : { 1'b0, video_addr[9:0] };
assign vram_addr = vram_sel && (vram_cpu_video ||
                                pref_eoi_blanks) ? vram_addr_cpu
                                                 : vram_addr_vid;

dualport_2clk_ram #(.addr_width(11)) pet2001vram
(
        .clock_a(clk),
        .address_a(vram_addr),
        .data_a(data_in),
        .wren_a(vram_we),
        .q_a(vram_data)

        // Not accessible to QNICE for now.
);

//////////////////////////////////////
// Video hardware.
//////////////////////////////////////
//
// Signals from the CRTC.
wire        crtc_de;      /* display enable */
wire [13:0] crtc_ma;      /* matrix address (screen memory) */
wire  [4:0] crtc_ra;      /* row address */
wire        crtc_irq_vsync; /* vertical sync used for retrace_irq_n */

wire        video_blank; // Blank screen during scrolling.
wire        video_gfx;   // Display graphic characters vs. lower-case.

wire chr_option = crtc_ma[13];	// use high half of character ROM
wire invert = !crtc_ma[12];	// invert the screen

assign video_addr = crtc_ma[9:0]; // => vram_data
assign charaddr   = {chr_option, video_gfx, vram_data[6:0], crtc_ra[2:0]}; // => chardata

reg [7:0] vdata;	// pixel shift register
reg       inv;		// bit 7 from video ram: invert pixels
assign    pix_o = invert ^ ((vdata[7] ^ inv) & ~(video_blank & pref_eoi_blanks));

wire no_row;    // name from schematic 8032087
assign no_row = crtc_ra[3] || crtc_ra[4];

/*
 * ce_pixel must be at least 2 clk cycles after vram_cpu_video.
 * 1 clk later, vram_data will be available.
 * 1 clk later, chardata will be available.
 * Total: 2 clks from rising edge of vram_cpu_video, if video_addr was already
 * set up.
 */
always @(posedge clk) begin
    // Work on the other clock edge, so that we work with the updated Matrix
    // Address, and the updated Matrix value, and the updated character rom
    // pixels. On real hardware this would take 2 CPU clocks: 1 to fetch the
    // matrix value, 1 for lookup in the character ROM.
    if (ce_pixel) begin
        if (load_sr) begin
            {inv, vdata} <= (crtc_de && ~no_row) ? {vram_data[7], chardata}
                                                 : 9'd0;
        end else begin
            vdata <= {vdata[6:0], 1'b0};
        end
    end
end

////////////////////////////////////////////////////////
// I/O hardware
////////////////////////////////////////////////////////
wire [7:0]      io_read_data;
// This allows for "small I/O area" only. No I/O extensions in E900-EFFF.
wire            io_sel = addr[15:8] == 8'hE8;

pet2001io io
(
        .data_out(io_read_data),
        .data_in(data_in),
        .addr(addr[7:0]),               // E8xx only!
        .cs(io_sel),
        .we(we),
        .irq(irq),

        .keyrow(keyrow),
        .keyin(keyin),

        .video_blank(video_blank),
        .video_gfx(video_gfx),
        .retrace_irq_n_i(crtc_irq_vsync),

        .crtc_hblank(HBlank_o),
        .crtc_vblank(VBlank_o),
        .crtc_hsync(HSync_o),
        .crtc_vsync(VSync_o),
        .crtc_de(crtc_de),
        .crtc_cursor(),
        .crtc_ma(crtc_ma),
        .crtc_ra(crtc_ra),

        .crtc_irq_vsync_n_o(crtc_irq_vsync),
        .pref_have_crtc(pref_have_crtc),

        .cass_motor_n(cass_motor_n),
        .cass_write(cass_write),
        .cass_sense_n(cass_sense_n),
        .cass_read(cass_read),
        .audio(audio),

        .diag_l(diag_l),

        // IEEE-488
        .ieee488_data_i(ieee488_data_i),
        .ieee488_data_o(ieee488_data_o),
        .ieee488_atn_o( ieee488_atn_o),
        .ieee488_ifc_o( ieee488_ifc_o),
        .ieee488_srq_i( ieee488_srq_i),
        .ieee488_dav_i( ieee488_dav_i),
        .ieee488_dav_o( ieee488_dav_o),
        .ieee488_eoi_i( ieee488_eoi_i),
        .ieee488_eoi_o( ieee488_eoi_o),
        .ieee488_nrfd_i(ieee488_nrfd_i),
        .ieee488_nrfd_o(ieee488_nrfd_o),
        .ieee488_ndac_i(ieee488_ndac_i),
        .ieee488_ndac_o(ieee488_ndac_o),

        .ce(ce_1m),
        .ce_8m(ce_8m),    // keep this at 8 MHz
        .clk(clk),
        .reset(reset)
);

/////////////////////////////////////
// Read data mux (to CPU)
/////////////////////////////////////
always @(*)
begin
    casex({addr[15:12], io_sel, vram_sel})
            6'b1111_x_x: data_out = rom_data;     // F000-FFFF KERNAL
            6'bxxxx_1_x: data_out = io_read_data; // E800-E8FF I/O
            6'b1110_0_x: data_out = rom_data;     // E000-EFFF except E8xx: EDITOR
            6'b110x_x_x: data_out = rom_data;     // C000-DFFF BASIC
            6'b1011_x_x: data_out = rom_data;     // B000-BFFF BASIC 4
            6'b1010_x_x: data_out = rom_data;     // A000-AFFF OPT ROM 2
            6'b1001_x_x: data_out = rom_data;     // 9000-9FFF OPT ROM 1
            6'b1000_x_1: data_out = vram_data;    // 8000-8FFF VIDEO RAM (mirrored several times)
            6'b0xxx_x_x: data_out = ram_data;     // 0000-7FFF 32KB RAM
            default: data_out = addr[15:8];
    endcase;
end;

endmodule // pet2001hw
