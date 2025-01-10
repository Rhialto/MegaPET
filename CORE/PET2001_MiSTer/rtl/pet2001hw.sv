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

        output           pix,
        output           HSync,
        output           VSync,
        output           HBlank,
        output           VBlank,
        input            pref_eoi_blanks,       // use as generic for 2001-specifics
        input            pref_have_crtc,

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

        input            clk_speed,
        input            clk_stop,
        input            diag_l,
        input            clk,
        input            ce_8mp,        // 8 HMz positive edge
        input            ce_8mn,        // 8 HMz negative edge
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

wire [10:0]     charaddr;
wire [7:0]      chardata;

dualport_2clk_ram #(
        .addr_width(11),        // 2 KB, but we can use a double size (SuperPET) ROM later
        .data_width(8),
        .rom_preload(1),
        .rom_file_hex(1),
        // Relative to PET_MEGA65/CORE/CORE-R6.runs/synth_1 (or sth.)
        .rom_file("../../PET2001_MiSTer/roms/PET3032-chars.hex"),
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
// Video RAM.
// The video hardware shares access to VRAM half the time.
//////////////////////////////////////
// On the 2001, video RAM is mirrored all the way up to $8FFF.
// Later models only mirror up to $87FF.

wire [7:0]      vram_data;
wire [10:0]     video_addr;     /* 2 KB */

reg     vram_cpu_video;         // 1=cpu, 0=video
wire    vram_sel = (addr[15:11] == 5'b1000_0) ||
                   (pref_eoi_blanks && addr[15:12] == 4'b1000);
wire    vram_we = we && vram_sel && vram_cpu_video;
reg     load_sr; // Load the video shift register. Name from schematic 8032087.

// Select who owns the bus.
// Video owns it from ce_8mp to ce_8mn.
// We only need it once (later twice) for video fetch during an 1 MHz
// cycle so this switches too often...
always @(posedge clk)
begin
    if (ce_1m || ce_8mn) begin
        vram_cpu_video <= 1;
    end else if (ce_8mp) begin
        vram_cpu_video <= 0;
    end;
end;

// Decide when to load the video shift register.
// Do this in the first 8 MHz clock after the cpu 1 MHz clock.
always @(posedge clk)
begin
    if (ce_1m) begin
        load_sr <= 1;
    end else if (ce_8mn) begin
        load_sr <= 0;
    end;
end;

// The address bus for VRAM is multiplexed.
// On the 2001, the CPU always has priority, so the address is from the cpu if
// vram_sel is true.
// For later models, also vram_cpu_video must be true.
// pref_eoi_blanks is the indicator that the first or the second behaviour is
// wanted.

dualport_2clk_ram #(.addr_width(10)) pet2001vram
(
        .clock_a(clk),
        .address_a(vram_sel && (vram_cpu_video ||
	                        pref_eoi_blanks) ? addr[9:0]
                                                 : video_addr[9:0]),
        .data_a(data_in),
        .wren_a(vram_we),
        .q_a(vram_data)

        // Not accessible to QNICE for now.
);

//////////////////////////////////////
// Video hardware.
//////////////////////////////////////

wire    video_on;    // Signal indicating video is scanning visible
                     // rows.  Used to generate tick interrupts.
wire    video_blank; // Blank screen during scrolling.
wire    video_gfx;   // Display graphic characters vs. lower-case.

// Signals from the CRTC.
wire        crtc_hblank;  /* horizontal blanking */
wire        crtc_vblank;  /* vertical blanking */
wire        crtc_hsync;   /* horizontal sync */
wire        crtc_vsync;   /* vertical sync */
wire        crtc_de;      /* display enable */
wire [13:0] crtc_ma;      /* matrix address (screen memory) */
wire  [4:0] crtc_ra;      /* row address */
wire        crtc_irq_vsync; /* vertical sync used for retrace_irq_n */

// Similar signals from the discrete video circuits.
wire        discrete_hblank;  /* horizontal blanking */
wire        discrete_vblank;  /* vertical blanking */
wire        discrete_hsync;   /* horizontal sync */
wire        discrete_vsync;   /* vertical sync */
wire        discrete_de;      /* display enable */
wire [13:0] discrete_ma;      /* matrix address (screen memory) */
wire  [4:0] discrete_ra;      /* row address */

pet2001video8mhz vid
(
        .video_on(video_on),

        .vid_hblank(discrete_hblank),
        .vid_vblank(discrete_vblank),
        .vid_hsync(discrete_hsync),
        .vid_vsync(discrete_vsync),
        .vid_de(discrete_de),
        .vid_cursor(),
        .vid_ma(discrete_ma),
        .vid_ra(discrete_ra),

        .reset(reset || pref_have_crtc),
        .clk(clk),
        .ce_1m(ce_1m)
);

// Choose either old/discrete video or CRTC.
// We ignore the cursor since it isn't connected.

wire        chosen_hblank;  /* horizontal blanking */
wire        chosen_vblank;  /* vertical blanking */
wire        chosen_hsync;   /* horizontal sync */
wire        chosen_vsync;   /* vertical sync */
wire        chosen_de;      /* display enable */
wire [13:0] chosen_ma;      /* matrix address (screen memory) */
wire  [4:0] chosen_ra;      /* row address */

assign chosen_hblank = pref_have_crtc ? crtc_hblank
                                      : discrete_hblank;
assign chosen_vblank = pref_have_crtc ? crtc_vblank
                                      : discrete_vblank;
assign chosen_hsync  = pref_have_crtc ? crtc_hsync
                                      : discrete_hsync;
assign chosen_vsync  = pref_have_crtc ? crtc_vsync
                                      : discrete_vsync;
assign chosen_de     = pref_have_crtc ? crtc_de
                                      : discrete_de;
assign chosen_ma     = pref_have_crtc ? crtc_ma
                                      : discrete_ma;
assign chosen_ra     = pref_have_crtc ? crtc_ra
                                      : discrete_ra;
 
wire retrace_irq_n = pref_have_crtc ? ~crtc_irq_vsync : video_on;

assign HBlank = chosen_hblank;
assign VBlank = chosen_vblank;
assign HSync  = chosen_hsync;
assign VSync  = chosen_vsync;

assign video_addr = chosen_ma[10:0]; // => vram_data
// TODO: add chosen_ma[13] as chr_option, and chosen_ma[12] as invert.
assign charaddr   = {video_gfx, vram_data[6:0], chosen_ra[2:0]}; // => chardata

reg [7:0] vdata;
reg       inv;
assign    pix = (vdata[7] ^ inv) & ~(video_blank & pref_eoi_blanks);

wire no_row;    // name from schematic 8032087
assign no_row = chosen_ra[3] || chosen_ra[4];

/*
 * ce_8mn must be at least 3 clk cycles after ce_8mp.
 * At the falling edge of ce_8mp (so 1 clk after it rises), video_addr will change.
 * (charaddr manages to change at the same time)
 * 1 clk later, video_data will be available.
 * 1 clk later, chardata will be available.
 * Total: 3 clks from rising edge of ce_8mp.
 */
always @(posedge clk) begin
    // Work on the other clock edge, so that we work with the updated Matrix
    // Address, and the updated Matrix value, and the updated character rom
    // pixels. On real hardware this would take 2 CPU clocks: 1 to fetch the
    // matrix value, 1 for lookup in the character ROM.
    if (ce_8mn) begin
        if (load_sr) begin
            {inv, vdata} <= (chosen_de && ~no_row) ? {vram_data[7], chardata}
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
        .retrace_irq_n(retrace_irq_n),

        .crtc_hblank(crtc_hblank),
        .crtc_vblank(crtc_vblank),
        .crtc_hsync(crtc_hsync),
        .crtc_vsync(crtc_vsync),
        .crtc_de(crtc_de),
        .crtc_cursor(),
        .crtc_ma(crtc_ma),
        .crtc_ra(crtc_ra),

        .crtc_irq_vsync(crtc_irq_vsync),
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
        .ce_8m(ce_8mp),
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
