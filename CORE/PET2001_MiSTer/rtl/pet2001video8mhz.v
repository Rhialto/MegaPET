`timescale 1ns / 1ps

module pet2001video8mhz
(
(* dont_touch="true",mark_debug="true" *)
        output         pix,
(* dont_touch="true",mark_debug="true" *)
        output reg     HSync,
(* dont_touch="true",mark_debug="true" *)
        output reg     VSync,
(* dont_touch="true",mark_debug="true" *)
        output reg     HBlank,
(* dont_touch="true",mark_debug="true" *)
        output reg     VBlank,

(* dont_touch="true",mark_debug="true" *)
        output [10:0]  video_addr,      // Video RAM intf
(* dont_touch="true",mark_debug="true" *)
        input  [7:0]   video_data,

//(* dont_touch="true",mark_debug="true" *)
        output [10:0]  charaddr,        // char rom intf
(* dont_touch="true",mark_debug="true" *)
        input  [7:0]   chardata,
(* dont_touch="true",mark_debug="true" *)
        output reg     video_on,        // control sigs
(* dont_touch="true",mark_debug="true" *)
        input          video_blank,
        input          video_gfx,
(* dont_touch="true",mark_debug="true" *)
        input          reset,
(* dont_touch="true",mark_debug="true" *)
        input          clk,
(* dont_touch="true",mark_debug="true" *)
        input          ce_8mp,
(* dont_touch="true",mark_debug="true" *)
        input          ce_8mn,
(* dont_touch="true",mark_debug="true" *)
        input          ce_1m
);

/*
 * Based on PET-1254901.jpg
 * https://forum.vcfed.org/index.php?threads/commodore-static-pet-early-dynamic-pet-video-timings.1242511/
 * 
 * 1 usec = 1 character = 1 6502 clock cycle
 * 
 * <-------- 64 usec 1 full scan line ---------------------------->
 * 
 * +-----------+------+---------------------------------------+----+
 * |               Vertical flyback = 20 lines = 1.28 ms           |
 * |                                                               |
 * +           +------+---------------------------------------+----+
 * |           |   Raster scan on CRT face                         |
 * |           |   20 lines top border                         Z   |
 * +           +      +---------------------------------------+    +
 * |           |      |X  Text lines, Line 0                  |    |
 * |horizontal |      |                                       |    |
 * |flyback    |      |                                       |    |
 * |  12 usec  | 6.7  |   40 usec                             |5.3 |
 * |           | usec |                                       |usec|
 * |           |      |                                       |    |
 * |           |      |                                       |    |
 * |           |      |                                       |    |
 * |           |      |                                       |    |
 * |           |      |                                       |    |
 * |           |      |                                       |    |
 * |           |      |                                       |    |
 * |           |      |                                       |    |
 * |           |      |                                       |    |
 * |           |      |                                       |    |
 * |           |      |                                       |    |
 * |           |      |                                       |    |
 * |           |      |                                       |    |
 * |           |      |                                       |    |
 * |           |      |                                       |    |
 * |           |      |                                       |    |
 * |           |      |                                       |    |
 * |           |      |                                       |    |
 * |           |      |                                       |    |
 * |           |      |Line 24                  scan line 199 |Y   |
 * +           +      +---------------------------------------+    +
 * |           |                                                   |
 * |           |   20 lines bottom border                          |
 * +-----------+------+---------------------------------------+----+
 *
 * Scan line counting starts at "X": line 0 column 0.
 * So the in this counting, the line *ends* with the horizontal flyback.
 *
 * The VIDEO ON signal (used to generate 60 Hz IRQs and to avoid changing
 * the screen while the video circuitry reads it) turns off at Y and on at Z,
 * 3 * 20 lines later (the bottom of each: scan lines 199 and 259, pixel 320).
 * Because there is a delay of 1 cycle after a character is fetched from the
 * matrix (to run it through the character ROM), and 1 cycle to shift out all the
 * pixels, Y is 2 cycles after the last character has been fetched, not just 1.
 *
 *
 * For ease of counting we round 6.7 -> 7 and 5.3 -> 5.
 * or for more centered output   6.7 -> 6     5.3 -> 6.
 *
 */

(* dont_touch="true",mark_debug="true" *)
reg  [8:0] hc;
(* dont_touch="true",mark_debug="true" *)
reg  [8:0] vc;
(* dont_touch="true",mark_debug="true" *)
reg synchronize;

//assign video_on   = (vc < 200);
assign video_addr = {vc[8:3], 5'b00000}+{vc[8:3], 3'b000}+hc[8:3];          // 40 * line + charpos
assign charaddr   = {video_gfx, video_data[6:0], vc[2:0]};

always @(posedge clk) begin
    if (reset == 1) begin
        synchronize <= 1;
    end else if (reset == 0 && synchronize == 1 && ce_1m == 1) begin
        synchronize <= 0;
        hc <= 0;
        vc <= 0;
    end else begin
        if (ce_8mp) begin
        // Here video_addr (matrix address, in CRTC terms) may change, which goes
        // out an determines the value read from the character matrix.
            hc <= hc + 1'd1;
            if (hc == 64*8 -1) begin // 511
                hc <= 0;
                vc <= vc + 1'd1;
                if (vc == 259)
                    vc <= 0;
            end
        end

        if (ce_8mn) begin
            if (hc == 0) begin
                                            // 200 bottom of text, start of bottom border
                     if (vc == 220) begin   // bottom of screen, start of vertical blank
                    VBlank <= 1;
                end else if (vc == 226) begin   // start vsync
                    VSync <= 1;
                end else if (vc == 234) begin   // end vsync
                    VSync <= 0;
                end else if (vc == 240) begin   // top of screen, top border
                    VBlank <= 0;
                end                             // 260 top of text, end of top border
            end else if (hc == 319 + 8) begin   // start right border + all pixels shifted out
                if (vc == 199) begin
                    video_on <= 0;
                end else if (vc == 259) begin
                    video_on <= 1;
                end
            end else if (hc == 360) begin // start horizontal flyback
                HBlank <= 1;
            end else if (hc == 384) begin // start horizontal sync
                HSync <= 1;
            end else if (hc == 432) begin // end horizontal sync
                HSync <= 0;
            end else if (hc == 456) begin // start left border
                HBlank <= 0;
            end  // else if (hc == 511) begin // end line
                 // end
        end
    end
end

reg [7:0] vdata;
reg       inv;
assign    pix = (vdata[7] ^ inv) & ~video_blank;

always @(posedge clk) begin
    // Work on the other clock edge, so that we work with the updated Matrix
    // Address, and the updated Matrix value, and the updated character rom
    // pixels.
    if (ce_8mn) begin
        if (!hc[2:0]) begin
            {inv, vdata} <= ((hc < 320) && (vc < 200)) ? {video_data[7], chardata}
                                                       : 9'd0;
        end else begin
            vdata <= {vdata[6:0], 1'b0};
        end
    end
end

endmodule // pet2001video8mhz
