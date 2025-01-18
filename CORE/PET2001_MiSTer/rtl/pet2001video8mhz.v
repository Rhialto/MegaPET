/////////////////////////////////////////////////////
//
// Created by Olaf "Rhialto" Seibert, January 2025.
//
// Module name: pet2001video8mhz
//
// Description:
//
//      This is the discrete video output circuitry of a PET 2001 or 30xx.
//      It is synchronized to the CPU: it takes 1 cpu cycle to output
//      1 character.
//
// License: GPL version 3
//

module pet2001video8mhz
(
        // new CRTC-compatible outputs, interface with video/crtc multiplexer
        output reg     vid_hblank,
        output reg     vid_vblank,
        output reg     vid_hsync,
        output reg     vid_vsync,
        output         vid_de,
        output [13:0]  vid_ma,
        output  [4:0]  vid_ra,

        output reg     video_on,        // control sigs

        input          video_blank,
        input          video_gfx,
        input          reset,
        input          clk,
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
 * So in this way of counting, the line *ends* with the left border.
 *
 * The VIDEO ON signal (used to generate 60 Hz IRQs and to avoid changing
 * the screen while the video circuitry reads it) turns off at Y and on at Z,
 * 3 * 20 lines later (the bottom of each: scan lines 199 and 259, pixel 320).
 * Because there is a delay of 1 cycle after a character is fetched from the
 * matrix (to run it through the character ROM), and 1 cycle to shift out all the
 * pixels, Y is 2 cycles after the last character has been fetched, not just 1.
 *
 * For ease of counting we round 6.7 -> 7 and 5.3 -> 5.
 * or for more centered output   6.7 -> 6     5.3 -> 6.
 */

reg  [5:0] hc;          /* horizontal counter, 0-63 */
reg  [8:0] vc;          /* vertical counter, 0-259 */
reg synchronize;

assign vid_ma = {vc[8:3], 5'b00000}+{vc[8:3], 3'b000}+hc;          // 40 * line + charpos
assign vid_ra = {2'b00, vc[2:0]};
assign vid_de = (hc < 40) && (vc < 200);

always @(posedge clk) begin
    if (reset == 1) begin
        synchronize <= 1;
    end else if (reset == 0 && synchronize == 1 && ce_1m == 1) begin
        synchronize <= 0;
        hc <= 0;
        vc <= 0;
    end else begin
        if (ce_1m) begin
            hc <= hc + 1'd1;

            if (hc == 40 -1 + 1+1) begin   // start right border + chardata fetch delay + all pixels shifted out
                if (vc == 199) begin
                    video_on <= 0;
                end else if (vc == 259) begin
                    video_on <= 1;
                end
            end else if (hc == 46 -1) begin // start horizontal blank
                vid_hblank <= 1;
            end else if (hc == 50 -1) begin // start horizontal sync
                vid_hsync <= 1;
            end else if (hc == 54 -1) begin // end horizontal sync
                vid_hsync <= 0;
            end else if (hc == 58 -1) begin // start left border
                vid_hblank <= 0;
                                                  // 200 bottom of text, start of bottom border
                if          (vc == 220-1) begin   // bottom of screen, start of vertical blank
                    vid_vblank <= 1;
                end else
                if          (vc == 226-1) begin   // start vsync
                    vid_vsync <= 1;
                end else if (vc == 234-1) begin   // end vsync
                    vid_vsync <= 0;
                end else if (vc == 240-1) begin   // top of screen, top border
                    vid_vblank <= 0;
                end                               // 260 top of text, end of top border
            end else if (hc == 64 -1) begin // 63 end line
                hc <= 0;
                vc <= vc + 1'd1;
                if (vc == 259)
                    vc <= 0;
            end
        end
    end
end


endmodule // pet2001video8mhz
