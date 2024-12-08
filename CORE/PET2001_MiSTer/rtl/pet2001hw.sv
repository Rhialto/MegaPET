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
        input            eoi_blanks,

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
        input            ce_7mp,
        input            ce_7mn,
        input            ce_1m,
        input            reset
);

/////////////////////////////////////////////////////////////
// Pet ROMS incuding character ROM.  Character data is read
// out second port.  This brings total ROM to 16K which is
// easy to arrange.
/////////////////////////////////////////////////////////////
wire [7:0]      rom_data;

wire [10:0]     charaddr;
wire [7:0]      chardata;

wire rom_wr = dma_we & ~dma_char_ce; // & dma_addr[15];
wire chars_wr = dma_we & dma_char_ce; // & dma_addr[15];

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

// Character ROM

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
// Pet RAM and video RAM.  Video RAM is dual ported.
//////////////////////////////////////////////////////////////
wire [7:0]      ram_data;
wire [7:0]      vram_data;
wire [7:0]      video_data;
wire [10:0] video_addr;

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

wire    vram_we = we && (addr[15:12] == 4'h8);

// was dpram
dualport_2clk_ram #(.addr_width(10)) pet2001vram
(
        .clock_a(clk),
        .address_a(addr[9:0]),
        .data_a(data_in),
        .wren_a(vram_we),
        .q_a(vram_data),

        .clock_b(clk),
        .address_b(video_addr),
        .q_b(video_data)
);

//////////////////////////////////////
// Video hardware.
//////////////////////////////////////
wire    video_on;    // signal indicating VGA is scanning visible
                     // rows.  Used to generate tick interrupts.
wire    video_blank; // blank screen during scrolling
wire    video_gfx;   // display graphic characters vs. lower-case

pet2001video vid
(
        .pix(pix),
        .HSync(HSync),
        .VSync(VSync),
        .HBlank(HBlank),
        .VBlank(VBlank),

        .video_addr(video_addr),
        .video_data(video_data),

        .charaddr(charaddr),
        .chardata(chardata),
        .video_on(video_on),
        .video_blank(video_blank & eoi_blanks), // video_blank when eoi_blanks else 0
        .video_gfx(video_gfx),
        .clk(clk),
        .ce_7mp(ce_7mp),
        .ce_7mn(ce_7mn)
);
 
////////////////////////////////////////////////////////
// I/O hardware
////////////////////////////////////////////////////////
wire [7:0]      io_read_data;
wire            io_sel = addr[15:8] == 8'hE8;

pet2001io io
(
        .*,
        .ce(ce_1m),
        .data_out(io_read_data),
        .data_in(data_in),
        .addr(addr[10:0]),
        .cs(io_sel),
        .video_sync(video_on),
        .video_blank(video_blank),

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
        .ieee488_ndac_o(ieee488_ndac_o)
);

/////////////////////////////////////
// Read data mux (to CPU)
/////////////////////////////////////
always @(*)
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

endmodule // pet2001hw
