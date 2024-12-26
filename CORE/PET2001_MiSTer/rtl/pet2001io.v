`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
//
// Engineer:	Thomas Skibo 
// 
// Create Date:	Sep 24, 2011
//
// Module Name: pet2001io
//
// Description:
//	I/O devices for Pet emulator.  Includes two PIAs and a VIA and a
//	module that converts a PS2 keyboard into a PET keyboard.
//
//	I/O is mapped into region 0xE800-0xE8FF.
//
//		0xE810-0xE813		PIA1
//		0xE820-0xE823		PIA2
//		0xE840-0xE84F		VIA
//		0xE880-0xE84F		CRTC
//
//      Signals for the IEEE-488 port come out.
//
/////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
//
// Copyright (C) 2011, Thomas Skibo.  All rights reserved.
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

module pet2001io
(
	output reg [7:0] data_out, 	// CPU interface
	input  [7:0] data_in,
	input  [7:0] addr,
	input        cs,
	input        we,

	output       irq,

	output [3:0] keyrow, 		// Keyboard
	input  [7:0] keyin,

	output       video_blank, 	// Video controls
	output       video_gfx,
	input        video_on,

        input        pref_have_crtc,     // do we want the CRTC?

	output       cass_motor_n, 	// Cassette #1 interface
	output       cass_write,
	input        cass_sense_n,
	input        cass_read,
	output       audio, 		// CB2 audio

	input        diag_l, 	// diag jumper input

        // IEEE-488
        input  [7:0] ieee488_data_i,
        output [7:0] ieee488_data_o,
        input        ieee488_atn_i,
        output       ieee488_atn_o,
        output       ieee488_ifc_o,
        input        ieee488_srq_i,
        input        ieee488_dav_i,
        output       ieee488_dav_o,
        input        ieee488_eoi_i,
        output       ieee488_eoi_o,
        input        ieee488_nrfd_i,
        output       ieee488_nrfd_o,
        input        ieee488_ndac_i,
        output       ieee488_ndac_o,

	input        ce,
	input        clk,
	input        reset
);

//delay ce for io for stability.
reg strobe_io;
always @(negedge clk) strobe_io <= ce;

assign ieee488_ifc_o = ~reset;      // IEEE bus is active-low.

wire pia1_sel = cs & addr[4];       // E810
wire pia2_sel = cs & addr[5];       // E820
wire via_sel  = cs & addr[6];       // E840
wire crtc_sel = (cs & addr[7]) && pref_have_crtc;       // E880

/////////////////////////// 6520 PIA1 ////////////////////////////////////
//
// Has some IEEE-488 port connections, but most of them are on PIA2.
//
wire [7:0] pia1_data_out;
wire       pia1_irq;
wire [7:0] pia1_porta_out;
wire [7:0] pia1_porta_in = {diag_l, ieee488_eoi_i & ieee488_eoi_o, 1'b1, cass_sense_n, 4'b1111};
wire       pia1_ca1_in = !cass_read;
wire       pia1_ca2_out;

pia6520 pia1
(
	.data_out(pia1_data_out),
	.data_in(data_in),
	.addr(addr[1:0]),
	.strobe(strobe_io & pia1_sel),
	.we(we),

	.irq(pia1_irq),
	.porta_out(pia1_porta_out),
	.porta_in(pia1_porta_in),
	.portb_out(),
	.portb_in(keyin),

	.ca1_in(pia1_ca1_in),
	.ca2_out(pia1_ca2_out),
	.ca2_in(1'b0),

	.cb1_in(video_on),
	.cb2_out(cass_motor_n),
	.cb2_in(1'b0),

	.clk(clk),
	.reset(reset)
);
 
assign video_blank = !pia1_ca2_out;
assign ieee488_eoi_o = pia1_ca2_out;
assign keyrow = pia1_porta_out[3:0];

 
////////////////////////// 6520 PIA2 ////////////////////////////////////
//
// Mostly IEEE-488 port connections.
// For now we ignore the bus drivers/transceivers (MC3446) since our
// IEEE-488 bus module essentially does the same thing. They are
// hard-wired to output anyway.
//
wire [7:0] pia2_data_out;
wire       pia2_irq;

pia6520 pia2
(
        .data_out(pia2_data_out),
        .data_in(data_in),
        .addr(addr[1:0]),
        .strobe(strobe_io & pia2_sel),
        .we(we),

        .irq(pia2_irq),
        .porta_out(),                   // tranceiver would ignore output to DI lines.
        .porta_in(ieee488_data_i),      // real input from bus transceiver; tranceiver would "& ieee488_data_o".
        .portb_out(ieee488_data_o),     // real output to bus tranceiver
        .portb_in(ieee488_data_i),

        .ca1_in(ieee488_atn_i),
        .ca2_out(ieee488_ndac_o),
        .ca2_in(1'b1),                  // loopback via bus driver

        .cb1_in(ieee488_srq_i),
        .cb2_out(ieee488_dav_o),
        .cb2_in(1'b1),                  // loopback via bus driver

        .clk(clk),
        .reset(reset)
);


/////////////////////////// 6522 VIA ////////////////////////////////////
//
wire [7:0] via_data_out;
wire       via_irq;
wire [7:0] via_portb_out;
wire [7:0] via_portb_in = {ieee488_dav_i, ieee488_nrfd_i, video_on, 4'b0_000, ieee488_ndac_i}; // msb first

via6522 via
(
	.data_out(via_data_out),
	.data_in(data_in),
	.addr(addr[3:0]),
	.strobe(strobe_io & via_sel),
	.we(we),

	.irq(via_irq),
	.porta_out(),
	.porta_in(8'h00),
	.portb_out(via_portb_out),
	.portb_in(via_portb_in),

	.ca1_in(1'b0),
	.ca2_out(video_gfx),
	.ca2_in(1'b0),

	.cb1_out(),
	.cb1_in(1'b0),
	.cb2_out(audio),
	.cb2_in(1'b0),

	.ce(ce),

	.clk(clk),
	.reset(reset)
);

assign ieee488_nrfd_o = via_portb_out[1];
assign ieee488_atn_o = via_portb_out[2];
assign cass_write = via_portb_out[3];

/////////////////////////// 6845 CRTC ///////////////////////////////////
//
wire [7:0] crtc_data_out;

mc6845 crtc
(
        .CLOCK(clk),
        .CLKEN(ce),
        .nRESET(~reset),

        // Bus interface
        .ENABLE(strobe_io & crtc_sel),
        .R_nW(~we),
        .RS(addr[0]),
        .DI(data_in),
        .DO(crtc_data_out),

        // Display interface
        .VSYNC(),
        .HSYNC(),
        .DE(),
        .CURSOR(),
        .LPSTB(),

        // Memory interface
        .MA(),
        .RA()
);

/////////////// Read data mux /////////////////////////
// register I/O stuff, therefore RDY must be delayed a cycle!
//
always @(posedge clk) begin
	data_out <= 8'hFF
                    & (pia1_sel ? pia1_data_out : 8'hFF)
                    & (pia2_sel ? pia2_data_out : 8'hFF)
                    & (via_sel  ? via_data_out  : 8'hFF)
                    & (crtc_sel ? crtc_data_out : 8'hFF);
end
 
assign irq = pia1_irq || pia2_irq || via_irq;

endmodule // pet2001io
