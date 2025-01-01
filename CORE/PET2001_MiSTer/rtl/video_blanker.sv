//============================================================================
//
//  Inspired by
//  CBM-II Video sync
//  Copyright (C) 2024 Erik Scheffers
//  Adjusted for PET by Olaf 'Rhialto' Seibert 2024/2025.
//
//============================================================================

module video_blanker
(
   input        clk,
   input        ce,         // use at least the pixel frequency here
   input        reset,

   input        hsync_i,
   input        vsync_i,
   input        de_i,

   output reg   hsync_o,
   output reg   vsync_o,
   output reg   hblank_o,
   output reg   vblank_o
);

/*
 * At least one PET editor rom uses a total resolution of 400 x 400
 * (including sync time).
 * Normally the used area is 40*8 = 320 horizontal and 25*8 = 200 or 25*10
 * = 250 vertical.
 * Let's allow some borders around that.
 */
localparam VISIBLE_H = 320 + 32;    // 352
localparam VISIBLE_V = 250 + 46;    // 296

// TODO: take off at least 2 msbits off all horizontal counters
reg[11:0] dot_count;
reg[11:0] hres;

reg[8:0]  line_count;
reg[8:0]  vres_buf[2];
wire[8:0] vres = vres_buf[0] > vres_buf[1] ? vres_buf[0] : vres_buf[1];

reg[11:0] de_left;
reg[11:0] de_right;
reg[8:0] de_top;
reg[8:0] de_bottom;
reg[8:0] de_line;

reg[11:0] blank_left;
reg[11:0] blank_right;
reg[8:0] blank_top;
reg[8:0] blank_bottom;

always @(posedge clk) begin
    reg hsync_r0;
    reg vsync_r0;
    reg de_r0;
    reg new_de_top;
    reg newfield;
    reg[11:0] tmp_blank_top;
    reg[11:0] tmp_blank_bottom;
    reg[11:0] tmp_blank_left;
    reg[11:0] tmp_blank_right;

    if (reset) begin
        line_count <= 0;
        dot_count <= 0;
        blank_top <= 0;
        blank_bottom <= 0;
        blank_left <= 0;
        blank_right <= 0;
    end
    else if (ce) begin
        vsync_r0 <= vsync_i;
        if (!vsync_r0 && vsync_i) begin
            newfield = 1;
            new_de_top = 1;
        end

        hsync_r0 <= hsync_i;
        if (!hsync_r0 && hsync_i) begin
            dot_count <= 0;
            hres <= dot_count;

            if (newfield) begin
                newfield = 0;

                de_bottom <= de_line + 1;

                line_count <= 0;
                vres_buf[0] <= vres_buf[1];
                vres_buf[1] <= line_count + 1;

                /*
		 * Calculate where we want the blanking signals.
                 * used = de_right - de_left;
                 * available = VISIBLE_H - used;
                 *           = VISIBLE_H - de_right + de_left;
                 * blank_left = de_left - available / 2;
                 *            = de_left - (VISIBLE_H - de_right + de_left) / 2;
                 *            = de_left - VISIBLE_H/2 + de_right/2 - de_left/2;
                 *            = de_left/2 + de_right/2 - VISIBLE_H/2;
                 * blank_right = de_right + available / 2;
                 *             = de_right + (VISIBLE_H - de_right + de_left) / 2;
                 *             = de_right + VISIBLE_H/2 - de_right/2 + de_left/2;
                 *             = de_left/2 + de_right/2 + VISIBLE_H/2;
		 * We start counting horizontally at the start of HSYNC.
		 * Compared to this, the normal image is pretty far to the
		 * right and our calculation of the right-side blanking edge
		 * "overflows" to the left. Typical values are blank_left=$036
		 * right=$196=$007 (with hres=$18f). blank_top=$036
		 * bottom=$15e with vres=$18f.
		 */
		/*
		 * TODO: for programs that switch the 8032 to 40 columns, the
		 * below wont work properly. It would have a very long hsync?
		 */
                tmp_blank_left  = de_left[11:1] + de_right[11:1] - VISIBLE_H/2;
		if (tmp_blank_left > hres) begin
		    blank_left <= tmp_blank_left + hres;
		end else begin
		    blank_left <= tmp_blank_left;
		end;
                tmp_blank_right = de_left[11:1] + de_right[11:1] + VISIBLE_H/2;
		if (tmp_blank_right > hres) begin
		    blank_right <= tmp_blank_right - hres;
		end else begin
		    blank_right <= tmp_blank_right;
		end;

		if (vres >= VISIBLE_V) begin
		    tmp_blank_top    = de_top[8:1] + de_bottom[8:1] - VISIBLE_V/2;
		    if (tmp_blank_top > vres) begin
			blank_top <= tmp_blank_top + vres;
		    end else begin
			blank_top <= tmp_blank_top;
		    end;
		    tmp_blank_bottom = de_top[8:1] + de_bottom[8:1] + VISIBLE_V/2;
		    if (tmp_blank_bottom > vres) begin
			blank_bottom <= tmp_blank_bottom - vres;
		    end else begin
			blank_bottom <= tmp_blank_bottom;
		    end;
		end else begin
		    // The CRTC produces fewer lines than we want to display.
		    // Compromise with the border we put around it.
		    tmp_blank_top = de_top - 20;
		    if (tmp_blank_top > vres) begin // underflow
			blank_top <= de_top[8:1];
		    end else begin
			blank_top <= tmp_blank_top;
		    end
		    tmp_blank_bottom = de_bottom + 20;
		    if (tmp_blank_bottom >= vres - 2) begin
			blank_bottom <= vres - 2;
		    end else begin
			blank_bottom <= tmp_blank_bottom;
		    end
	        end
            end
            else if (line_count < 511) begin
                line_count <= line_count + 9'd1;
            end
        end
        else if (dot_count < 4095) begin
            dot_count <= dot_count + 12'd1;
        end

        de_r0 <= de_i;
        if (!de_r0 && de_i) begin   // display enable turns on
            de_left <= dot_count;
            if (new_de_top) begin
                new_de_top = 0;
                de_top <= line_count;
            end
        end
        else if (de_r0 && !de_i) begin  // display enable turns off
            de_right <= dot_count;
            de_line <= line_count;
        end
    end
end

always @(posedge clk) begin
    if (ce) begin
        if (1==1 /*hres < 416 && vres < 416*/) begin

            if (dot_count == blank_right) begin
                hblank_o <= 1;
                hsync_o <= 1;
            end
            else if (dot_count == blank_left)  begin
                hblank_o <= 0;
                hsync_o <= 0;

		if (line_count == blank_bottom) begin
		    vblank_o <= 1;
		    vsync_o <= 1;
		end
		else if (line_count == blank_top) begin
		    vblank_o <= 0;
		    vsync_o <= 0;
		end;
            end
        end
        else if (hres >= 128 && vres >= 128) begin
            // Non-standard video mode
            hblank_o <= hsync_i;
            hsync_o <= hsync_i;

            if (vsync_i) begin
                vblank_o <= 1;
                if (hsync_o && !hsync_i) vsync_o <= 1;
            end
            else if (vsync_o) begin
                if (hsync_o && !hsync_i) vsync_o <= 0;
            end
            else if (vblank_o) begin
                if (!hsync_o && hsync_i) vblank_o <= 0;
            end
        end
        else begin
            // Illegal video mode
            hsync_o <= 0;
            vsync_o <= 0;
            hblank_o <= 1;
            vblank_o <= 1;
        end
    end
end

endmodule
