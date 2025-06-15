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
	input        clk_sys,
	input        reset,
	input        ce,

	input        drv_type,

	input        mounted,
	input        selected,
	input        changing,

	input        mtr,
	input        sync,
	input  [1:0] stp,
	input        we,
	input        rw,
	input        hd,

	output reg   save_track,
	output [7:0] track,
	output       track_changing
);

// For 4040 "6530-34 RIOT DOS 2" part #901466-04 
// and 8520 "6530-47 RIOT DOS 2.7 Micropolis" part #901885-04
// (some other RIOT versions for other drive types use different step motor control signals)

localparam SIDE0_START = 1;
localparam SIDE1_START = 78;

wire [8:0] MAX_HTRACK = 9'(drv_type ? 42*2 : 76*4);
wire [8:0] DIR_HTRACK = 9'(drv_type ? 17*2 : 38*4);
reg  [8:0] htrack;

assign track = drv_type ? 8'(htrack[7:1] + SIDE0_START)
								: 8'(htrack[8:2] + (hd ? SIDE1_START : SIDE0_START));

wire [20:0] CHANGE_DELAY = 21'(drv_type ? 'h40000: 'h20000);  // `ce` clock pulses between stepper pulses
reg  [20:0] change_cnt;

wire  [5:0] SYNC_PULSES = 6'(drv_type ? (
										(track < 18) ? 5'd20 :
										(track < 25) ? 5'd18 :
										(track < 31) ? 5'd17 :
															5'd16
									) : (
										(track <  40) ? 5'd28 :
										(track <  54) ? 5'd26 :
										(track <  65) ? 5'd24 :
										(track <  78) ? 5'd22 :
										(track < 117) ? 5'd28 :
										(track < 131) ? 5'd26 :
										(track < 142) ? 5'd24 :
															 5'd22
									)) << 1;

assign track_changing = |change_cnt;

always @(posedge clk_sys) begin
	reg       track_modified;
	reg [1:0] move, stp_old;
	reg       hd_old, sync_old, rw_old;
	reg [5:0] sync_cnt;

	hd_old   <= hd;
	rw_old   <= rw;
	sync_old <= sync;

	stp_old  <= stp;
	move     <= stp - stp_old;

	if (change_cnt && ce)
		change_cnt <= change_cnt - 1'b1;

	if (reset || mounted || !track_modified || track_changing || !mtr)
		sync_cnt <= SYNC_PULSES;
	else if (sync_cnt && !sync_old && sync)
		sync_cnt <= sync_cnt - 1'b1;

	if (reset || mounted) begin
		htrack <= DIR_HTRACK;
		track_modified <= 0;
		change_cnt <= 0;
	end
	else begin
		if (move[0]) begin
			if (!move[1] && htrack < MAX_HTRACK) begin
				htrack     <= htrack + 1'b1;
				change_cnt <= CHANGE_DELAY;
			end
			if (move[1] && htrack > 0) begin
				htrack     <= htrack - 1'b1;
				change_cnt <= CHANGE_DELAY;
			end
		end

		if (selected) begin
			if (we)
				track_modified <= 1;

			if (hd != hd_old) begin
				change_cnt <= CHANGE_DELAY;
			end

			if (track_modified && (changing || move[0] || !mtr || hd != hd_old || !sync_cnt)) begin
				save_track <= ~save_track;
				track_modified <= 0;
			end

			if (rw_old && !rw)
				change_cnt <= 0;
		end
	end
end

endmodule
