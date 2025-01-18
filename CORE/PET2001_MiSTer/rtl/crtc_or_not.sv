/////////////////////////////////////////////////////
//
// Created by Olaf "Rhialto" Seibert, January 2025.
//
// Module name: crtc_or_not
//
// Description:
//
//      This chooses either the discrete video circuitry for a PET, or
//      uses a 6845 CRT controller chip.
//      The differences are made as small as possible.
//
// License: GPL version 3
//
module crtc_or_not
(
        input          reset,
        input          clk,
        input          ce_1m,
        input          ce_8m,

        input          pref_have_crtc,  // do we want the CRTC?

        // Bus interface for CRTC, if in use
        input          enable,
        input          r_nw,
        input          rs,
        input  [7:0]   data_in,
        output [7:0]   data_out,

        // CRTC-compatible outputs
        output          vid_hblank_o,
        output          vid_vblank_o,
        output          vid_hsync_o,
        output          vid_vsync_o,
        output          vid_de_o,
        output          vid_cursor_o,
        output [13:0]   vid_ma_o,
        output  [4:0]   vid_ra_o,

        output          retrace_irq_n_o        // control sigs
);

// Signals from the CRTC.
wire        crtc_hblank;  /* horizontal blanking */
wire        crtc_vblank;  /* vertical blanking */
wire        crtc_hsync;   /* horizontal sync */
wire        crtc_vsync;   /* vertical sync */
wire        crtc_de;      /* display enable */
wire [13:0] crtc_ma;      /* matrix address (screen memory) */
wire  [4:0] crtc_ra;      /* row address */
reg         crtc_irq_vsync; /* vertical sync used for retrace_irq_n */

// Similar signals from the discrete video circuits.
wire        discrete_hblank;  /* horizontal blanking */
wire        discrete_vblank;  /* vertical blanking */
wire        discrete_hsync;   /* horizontal sync */
wire        discrete_vsync;   /* vertical sync */
wire        discrete_de;      /* display enable */
wire [13:0] discrete_ma;      /* matrix address (screen memory) */
wire  [4:0] discrete_ra;      /* row address */
wire        video_on;         /* Signal indicating video is scanning visible
                               * rows.  Used to generate tick interrupts. */

/////////////////////////// DISCRETE VIDEO //////////////////////////////

pet2001video8mhz discrete
(
        .video_on(video_on),

        .vid_hblank(discrete_hblank),
        .vid_vblank(discrete_vblank),
        .vid_hsync(discrete_hsync),
        .vid_vsync(discrete_vsync),
        .vid_de(discrete_de),
        .vid_ma(discrete_ma),
        .vid_ra(discrete_ra),

        .reset(reset || pref_have_crtc),
        .clk(clk),
        .ce_1m(ce_1m)
);


/////////////////////////// 6845 CRTC ///////////////////////////////////

wire crtc_hsync_out;
wire crtc_vsync_out;
wire crtc_cursor;

mc6845 crtc
(
        .CLOCK(clk),
        .CLKEN(ce_1m /*&& pref_have_crtc*/),
        .CLKEN_CPU(ce_1m /*&& pref_have_crtc*/),
        .nRESET(!reset),

        // Bus interface
        .ENABLE(enable),
        .R_nW(r_nw),
        .RS(rs),
        .DI(data_in),
        .DO(data_out),

        // Display interface
        .VSYNC(crtc_vsync_out),
        .HSYNC(crtc_hsync_out),
        .DE(crtc_de),
        .CURSOR(crtc_cursor),
        .LPSTB(0),   // no light pen connected.

        .VGA(0),    // we don't want VGA

        // Memory interface
        .MA(crtc_ma),
        .RA(crtc_ra)
);

// Delay the CRTC vsync by 1 CPU clock for generating the retrace IRQ.
// This corresponds to the general 1 clock delay caused by looking up
// pixels in the character ROM.
always @(posedge clk) begin
    if (ce_1m) begin
        crtc_irq_vsync <= crtc_vsync_out;
    end
end

/*
 * The CRTC doesn't generate blanking signals (only Display Enable), and we
 * want to have some blanking signals that leave a border around the actual
 * display but not as much as the sync signals do. 
 */

video_blanker add_blanking
(
    .clk(clk),
    .ce(ce_8m),
    .reset(reset || !pref_have_crtc),

    // inputs
    .hsync_i(crtc_hsync_out),
    .vsync_i(crtc_vsync_out),
    .de_i(crtc_de),

    // outputs
    .hsync_o(crtc_hsync),
    .vsync_o(crtc_vsync),
    .hblank_o(crtc_hblank),
    .vblank_o(crtc_vblank)
);

///////////////////////////////////////////////////////////////////////////
//
// Choose either old/discrete video or CRTC.

assign vid_hblank_o = pref_have_crtc ? crtc_hblank
                                     : discrete_hblank;
assign vid_vblank_o = pref_have_crtc ? crtc_vblank
                                     : discrete_vblank;
assign vid_hsync_o  = pref_have_crtc ? crtc_hsync
                                     : discrete_hsync;
assign vid_vsync_o  = pref_have_crtc ? crtc_vsync
                                     : discrete_vsync;
assign vid_de_o     = pref_have_crtc ? crtc_de
                                     : discrete_de;
assign vid_ma_o     = pref_have_crtc ? crtc_ma
                                     : discrete_ma;
assign vid_ra_o     = pref_have_crtc ? crtc_ra
                                     : discrete_ra;
assign vid_cursor_o = pref_have_crtc ? crtc_cursor
                                     : 0;
assign retrace_irq_n_o = pref_have_crtc ? ~crtc_irq_vsync
                                        : video_on;

endmodule // crtc_or_not;
