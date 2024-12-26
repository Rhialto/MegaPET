`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////
//
// Initial Engineer (2001 Model):          Thomas Skibo
// Brought to 3032 and 4032 (non CRTC):    Ruben Aparicio
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
(* dont_touch="true",mark_debug="true" *)
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
(* dont_touch="true",mark_debug="true" *)
        input            ce_8mp,        // 8 HMz positive edge
(* dont_touch="true",mark_debug="true" *)
        input            ce_8mn,        // 8 HMz negative edge
(* dont_touch="true",mark_debug="true" *)
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

(* dont_touch="true",mark_debug="true" *)
wire [10:0]     charaddr;
(* dont_touch="true",mark_debug="true" *)
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
(* dont_touch="true",mark_debug="true" *)
wire [7:0]      ram_data;
(* dont_touch="true",mark_debug="true" *)
wire [7:0]      vram_data;
(* dont_touch="true",mark_debug="true" *)
wire [7:0]      video_data;
(* dont_touch="true",mark_debug="true" *)
wire [10:0]     video_addr;     /* 2 KB */

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

(* dont_touch="true",mark_debug="true" *)
reg     vram_cpu_video;         // 1=cpu, 0=video
(* dont_touch="true",mark_debug="true" *)
wire    vram_sel = (addr[15:11] == 5'b1000_0) ||
                   (pref_eoi_blanks && addr[15:12] == 4'b1000);
(* dont_touch="true",mark_debug="true" *)
wire    vram_we = we && vram_sel; // && vram_cpu_video;

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

dualport_2clk_ram #(.addr_width(10)) pet2001vram
(
        .clock_a(clk),
(* dont_touch="true",mark_debug="true" *)
        .address_a(addr[9:0]),
        //.address_a(vram_sel && vram_cpu_video ? addr[9:0]
        //                                      : video_addr[9:0]),
        //.address_a(vram_sel ? addr[9:0]      // snow?
        //                    : video_addr[9:0]),
        .data_a(data_in),
        .wren_a(vram_we),
        .q_a(vram_data)

        // Not accessible to QNICE for now.
       ,.clock_b(clk),
        .address_b(video_addr[9:0]),
        .q_b(video_data)
);

//////////////////////////////////////
// Video hardware.
//////////////////////////////////////
wire    video_on;    // signal indicating VGA is scanning visible
                     // rows.  Used to generate tick interrupts.
wire    video_blank; // blank screen during scrolling
wire    video_gfx;   // display graphic characters vs. lower-case

pet2001video8mhz vid
(
        .pix(pix),
        .HSync(HSync),
        .VSync(VSync),
        .HBlank(HBlank),
        .VBlank(VBlank),

        .video_addr(video_addr),
        .video_data(video_data),
        //.video_data(vram_data),

        .charaddr(charaddr),
        .chardata(chardata),
        .video_on(video_on),
        .video_blank(video_blank & pref_eoi_blanks), // video_blank when eoi_blanks else 0
        .video_gfx(video_gfx),
        .reset(reset),
        .clk(clk),
        .ce_1m(ce_1m),
        .ce_8mp(ce_8mp),
        .ce_8mn(ce_8mn)
);
 
////////////////////////////////////////////////////////
// I/O hardware
////////////////////////////////////////////////////////
wire [7:0]      io_read_data;
wire            io_sel = addr[15:8] == 8'hE8;

pet2001io io
(
        //.*,     // TODO: remove!
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
        .video_on(video_on),

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
        .clk(clk),
        .reset(reset)
);

/////////////////////////////////////
// Read data mux (to CPU)
/////////////////////////////////////
always @(*)
begin
    if (io_sel) begin
        data_out = io_read_data;
    end else begin
        casex(addr[15:12])
                5'b1111: data_out = rom_data;     // F000-FFFF
                5'b1110: data_out = rom_data;     // E000-EFFF except E8xx
                5'b110x: data_out = rom_data;     // C000-DFFF
                5'b1011: data_out = rom_data;     // B000-BFFF BASIC
                5'b1010: data_out = rom_data;     // A000-AFFF OPT ROM 2
                5'b1001: data_out = rom_data;     // 9000-9FFF OPT ROM 1
                5'b1000: data_out = vram_data;    // 8000-8FFF VIDEO RAM (mirrored several times)
                5'b0xxx: data_out = ram_data;     // 0000-7FFF 32KB RAM
                default: data_out = addr[15:8];
        endcase;
    end;
end;

endmodule // pet2001hw
