/*
 * Commodore 4040/8250 IEEE drive implementation
 *
 * Copyright (C) 2024, Erik Scheffers (https://github.com/eriks5)
 *
 * This file is part of CBM-II_MiSTer.
 *
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by
 * the Free Software Foundation, version 2.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

module ieeedrv_step (
	input            clk_sys,
	input            reset,

	input            drv_type,

	input            img_mounted,
	input            selected,
	input            changing,

	input            busy,
	input            mtr,
	input            sync,
	input      [1:0] stp,
	input            we,
	input            hd,

	output reg       save_track,
	output     [6:0] track
);

// For 4040 "6530-34 RIOT DOS 2" part #901466-04 
// and 8520 "6530-47 RIOT DOS 2.7 Micropolis" part #901885-04
// (some other RIOT versions for other drive types use different step motor control signals)

wire [8:0] MAX_HTRACK = 9'(drv_type ? 42*2 : 76*4);
wire [8:0] DIR_HTRACK = 9'(drv_type ? 17*2 : 38*4);

reg  [8:0] htrack;

assign track = drv_type ? htrack[7:1] :  htrack[8:2];

always @(posedge clk_sys) begin
	reg        track_modified;
	reg  [1:0] move, stp_old;
	reg        hd_old, sync_old;
	reg  [5:0] cnt;

	hd_old <= hd;
	sync_old <= sync;

	stp_old <= stp;
	move <= stp - stp_old;

	if (img_mounted) track_modified <= 0;

	if (reset || !track_modified || we || !selected)
		cnt <= {1'b0, drv_type, 4'b0};
	else if (~&cnt && !sync_old && sync)
		cnt <= cnt + 1'b1;

	if (reset) begin
		htrack <= DIR_HTRACK;
		track_modified <= 0;
	end
   else begin
		if (selected && we) 
			track_modified <= 1;

		if (move[0]) begin
			if (!move[1] && htrack < MAX_HTRACK) htrack <= htrack + 1'b1;
			if ( move[1] && htrack > 0         ) htrack <= htrack - 1'b1;
		end

		if (track_modified && (move[0] || changing || !mtr || &cnt || hd != hd_old)) begin
			save_track <= ~save_track;
			track_modified <= 0;
		end
	end
end

endmodule
