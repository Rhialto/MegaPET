---------------------------------------------------------------------------------------------------------
-- MiSTer2MEGA65 Framework
--
-- Custom keyboard controller for your core
--
-- Runs in the clock domain of the core.
--
-- This is how MiSTer2MEGA65 provides access to the MEGA65 keyboard:
--
-- MiSTer2MEGA65 provides a very simple and generic interface to the MEGA65 keyboard:
-- kb_key_num_i is running through the key numbers 0 to 79 with a frequency of 1 kHz, i.e. the whole
-- keyboard is scanned 1000 times per second. kb_key_pressed_n_i is already debounced and signals
-- low active, if a certain key is being pressed right now.
--
-- This PET keyboard offers a very symbolic mapping. A Mega-65 keyboard has all characters
-- on the keys that a PET has, but unfortunately most are in the wrong place. The numeric
-- keypad is also missing.
--
-- So we try to map all symbols on the keyboard to equivalent PET key presses.
-- Exception: there is no separate OFF/RVS key, which is used to delay scrolling.
-- The CTRL key is used in its place.
-- Another exception: the cursor up and left keys generate down and right, plus shift.
-- Some keys need to be shifted on the Mega-65 while being not shifted on the PET,
-- such as the shifted digits. This is handled by forcing the shift key to be un-pressed
-- while the '!' key (etc) are pressed. The PET may see unneeded shift key presses and
-- releases, though.
-- TODO: how to handle the graphics symbols we cannot get because of this.
-- for now I have a temporary version where the Mega key alwasy acts as a shift key for the PET:
-- 1 -> 1, shift+1 -> !, mega+1 -> petshift+1, mega+shift+1 -> petshift+! .
--
-- MiSTer2MEGA65 done by sy2002 and MJoergen in 2022 and licensed under GPL v3
---------------------------------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Keyboard matrix.
---
-- Row selectors range from 0..9. Detected columns from 0..7.
-- The ROM starts with row 0, col 0, and calls that scancode 80.
-- It checks increasing column numbers next (while decrementing the scan code),
-- then increases the row number. The last key detected (lowest scan code) wins.
-- The -1 brings the vector indices in the range 0..79.

entity matrix is
    port (
       key_n_i       : in std_logic_vector(79 downto 0); -- key switches by scan code (0...79)
       row_n_i       : in std_logic_vector(9 downto 0);  -- row selector (active low)
       col_n_o       : out std_logic_vector(7 downto 0)  -- column output (active low)
    );
end matrix;

architecture beh of matrix is
begin
    matrix: for c in 0 to 7 generate
        col_n_o(c) <=                                   -- c=  0,  1,  2,       7
            (row_n_i(0) or key_n_i(9*8 + (8-c) -1)) and --    80, 79, 78, ..., 73
            (row_n_i(1) or key_n_i(8*8 + (8-c) -1)) and --    72, 71, ...
            (row_n_i(2) or key_n_i(7*8 + (8-c) -1)) and --    64, ...
            (row_n_i(3) or key_n_i(6*8 + (8-c) -1)) and --    56
            (row_n_i(4) or key_n_i(5*8 + (8-c) -1)) and --    48
            (row_n_i(5) or key_n_i(4*8 + (8-c) -1)) and --    40
            (row_n_i(6) or key_n_i(3*8 + (8-c) -1)) and --    32
            (row_n_i(7) or key_n_i(2*8 + (8-c) -1)) and --    24
            (row_n_i(8) or key_n_i(1*8 + (8-c) -1)) and --    16
            (row_n_i(9) or key_n_i(0*8 + (8-c) -1));    --     8,  7,  6, ..., 1
    end generate;

end beh;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity keyboard is
   port (
      clk_main_i           : in std_logic;               -- core clock

      -- Interface to the MEGA65 keyboard
      key_num_i            : in integer range 0 to 79;   -- cycles through all MEGA65 keys
      key_pressed_n_i      : in std_logic;               -- low active: debounced feedback: is kb_key_num_i pressed right now?

      -- Interface to the PET's PIA.
        --E810    PORT A  7   Diagnostic sense (pin 5 on the user port)
        --                6   IEEE EOI in
        --                5   Cassette sense #2
        --                4   Cassette sense #1
        --                3-0 Keyboard row select (through 4->10 decoder)
        --E811    CA2         output to blank the screen (old PETs only)
        --                    IEEE EOI out
        --        CA1         cassette #1 read line
        --E812    PORT B  7-0 Contents of keyboard row
        --                    Usually all or all but one bits set.
        --E813    CB2         output to cassette #1 motor: 0=on, 1=off
        --        CB1         screen retrace detection in
        --
        --
        --         Control
        --
        -- 7    CA1 active transition flag. 1= 0->1, 0= 1->0
        -- 6    CA2 active transition flag. 1= 0->1, 0= 1->0
        -- 5    CA2 direction           1 = out        | 0 = in
        --                    ------------+------------+---------------------
        -- 4    CA2 control   Handshake=0 | Manual=1   | Active: High=1 Low=0
        -- 3    CA2 control   On Read=0   | CA2 High=1 | IRQ on=1, IRQ off=0
        --                    Pulse  =1   | CA2 Low=0  |
        --
        -- 2    Port A control: DDRA = 0, IORA = 1
        -- 1    CA1 control: Active High = 1, Low = 0
        -- 0    CA1 control: IRQ on=1, off = 0
      row_select_i         : in  std_logic_vector(3 downto 0);
      column_selected_o    : out std_logic_vector(7 downto 0);

      business_layout_i    : in  std_logic;    -- 0=normal/graphic layout, 1=business layout

      diag_sense_o         : out  std_logic;
      nmi_o                : out  std_logic;

      -- MEGA65 joysticks and paddles/mouse/potentiometers
      joy_1_up_n_i         : in  std_logic;
      joy_1_down_n_i       : in  std_logic;
      joy_1_left_n_i       : in  std_logic;
      joy_1_right_n_i      : in  std_logic;
      joy_1_fire_n_i       : in  std_logic
   );
end keyboard;

architecture beh of keyboard is

-- MEGA65 key codes that kb_key_num_i is using while
-- kb_key_pressed_n_i is signalling (low active) which key is pressed
constant m65_ins_del       : integer := 0;
constant m65_return        : integer := 1;
constant m65_horz_crsr     : integer := 2;   -- means cursor right in C64 terminology
constant m65_f7            : integer := 3;
constant m65_f1            : integer := 4;
constant m65_f3            : integer := 5;
constant m65_f5            : integer := 6;
constant m65_vert_crsr     : integer := 7;   -- means cursor down in C64 terminology
constant m65_3             : integer := 8;
constant m65_w             : integer := 9;
constant m65_a             : integer := 10;
constant m65_4             : integer := 11;
constant m65_z             : integer := 12;
constant m65_s             : integer := 13;
constant m65_e             : integer := 14;
constant m65_left_shift    : integer := 15;
constant m65_5             : integer := 16;
constant m65_r             : integer := 17;
constant m65_d             : integer := 18;
constant m65_6             : integer := 19;
constant m65_c             : integer := 20;
constant m65_f             : integer := 21;
constant m65_t             : integer := 22;
constant m65_x             : integer := 23;
constant m65_7             : integer := 24;
constant m65_y             : integer := 25;
constant m65_g             : integer := 26;
constant m65_8             : integer := 27;
constant m65_b             : integer := 28;
constant m65_h             : integer := 29;
constant m65_u             : integer := 30;
constant m65_v             : integer := 31;
constant m65_9             : integer := 32;
constant m65_i             : integer := 33;
constant m65_j             : integer := 34;
constant m65_0             : integer := 35;
constant m65_m             : integer := 36;
constant m65_k             : integer := 37;
constant m65_o             : integer := 38;
constant m65_n             : integer := 39;
constant m65_plus          : integer := 40;
constant m65_p             : integer := 41;
constant m65_l             : integer := 42;
constant m65_minus         : integer := 43;
constant m65_dot           : integer := 44;
constant m65_colon         : integer := 45;
constant m65_at            : integer := 46;
constant m65_comma         : integer := 47;
constant m65_gbp           : integer := 48;
constant m65_asterisk      : integer := 49;
constant m65_semicolon     : integer := 50;
constant m65_clr_home      : integer := 51;
constant m65_right_shift   : integer := 52;
constant m65_equal         : integer := 53;
constant m65_arrow_up      : integer := 54;  -- symbol, not cursor
constant m65_slash         : integer := 55;
constant m65_1             : integer := 56;
constant m65_arrow_left    : integer := 57;  -- symbol, not cursor
constant m65_ctrl          : integer := 58;
constant m65_2             : integer := 59;
constant m65_space         : integer := 60;
constant m65_mega          : integer := 61;
constant m65_q             : integer := 62;
constant m65_run_stop      : integer := 63;
constant m65_no_scrl       : integer := 64;
constant m65_tab           : integer := 65;
constant m65_alt           : integer := 66;
constant m65_help          : integer := 67;
constant m65_f9            : integer := 68;
constant m65_f11           : integer := 69;
constant m65_f13           : integer := 70;
constant m65_esc           : integer := 71;
constant m65_capslock      : integer := 72;
constant m65_up_crsr       : integer := 73;  -- cursor up
constant m65_left_crsr     : integer := 74;  -- cursor left
constant m65_restore       : integer := 75;

constant pet_none          : integer := 80;  -- no key pressed

signal key_pressed_n : std_logic_vector(79 downto 0);

-- 4-to-10 decoder for keyboard row selection.
signal row_n : std_logic_vector(9 downto 0);
signal shift_n : std_logic;
signal mega_n : std_logic;
signal unshift_n: std_logic;
signal b_unshift_n: std_logic;

signal joy1_direction : std_logic_vector(9 downto 1);
-- Which PET N-keyboard switches are pressed
signal pet_n_n : std_logic_vector(79 downto 0);
-- Which PET B-keyboard switches are pressed
signal pet_b_n : std_logic_vector(79 downto 0);
-- Unified N/B, including joystick keys
signal pet_nb_n : std_logic_vector(79 downto 0);

--signal key_num_pressed : integer range 0 to 79;
signal pet_key_num_pressed : integer range 0 to 80;
signal fire_pet_key_num : integer range 0 to 80 := 56 -1; -- scan code for A on B keyboard (W on N keyboard)

signal counter : integer range 0 to 79; -- used in process pet_keyboard_state

type enum_config_state is (sIDLE, sWAITJS1, sWAITJS2, sWAITKEY);

signal config_state : enum_config_state := sIDLE;
signal prev_business_layout : std_logic;

attribute mark_debug : string;
attribute mark_debug of key_pressed_n           : signal is "true";
attribute mark_debug of pet_b_n                 : signal is "true";
attribute mark_debug of pet_nb_n                : signal is "true";
attribute mark_debug of config_state            : signal is "true";
attribute mark_debug of pet_key_num_pressed     : signal is "true";
attribute mark_debug of fire_pet_key_num        : signal is "true";
attribute mark_debug of joy_1_fire_n_i          : signal is "true";
attribute mark_debug of counter                 : signal is "true";

begin

    keyboard_state : process(clk_main_i)
    begin
        if rising_edge(clk_main_i) then
            key_pressed_n(key_num_i) <= key_pressed_n_i;
        end if;
    end process;

    pet_keyboard_state : process(clk_main_i, business_layout_i, pet_n_n, pet_b_n) is
        variable pressed_n : std_logic;
    begin
        if rising_edge(clk_main_i) then
            if counter = 0 then
                counter <= 79;
            else
                counter <= counter - 1;
            end if;

            -- Keep track of which (single) PET key is pressed.
            -- Select which keyboard to use.
            pressed_n := pet_b_n(counter) when business_layout_i else
                         pet_n_n(counter);

            if pressed_n = '0' then
                -- If this key is pressed, record it.
                pet_key_num_pressed <= counter;
            elsif counter = pet_key_num_pressed then
                -- This key is not pressed; if it was the recorded key, forget it.
                pet_key_num_pressed <= pet_none;
            end if;

            -- Press the "fire" key if the joystick's fire button is pressed.
            if (counter = fire_pet_key_num) and (joy_1_fire_n_i = '0') then
                pet_nb_n(counter) <= '0';
            else
                pet_nb_n(counter) <= pressed_n;
            end if;
        end if;
    end process;

    -- When you press the MEGA and the CTRL key simultaneously,
    -- assert the diagnostic sense line (for resetting into the monitor).
    -- Instructions in the monitor:
    -- Type a ; and return. Then cursor to the SP value and make it F8,
    -- then type return. Now you can X back to BASIC.
    -- Instructions from https://mikenaberezny.com/hardware/pet-cbm/its-new-cursor/
    -- https://mikenaberezny.com/wp-content/uploads/2012/07/new-cursor-installation-instructions.pdf
    diag_sense_o <= key_pressed_n(m65_mega) or key_pressed_n(m65_ctrl);

    -- Map MEGA + RESTORE to the NMI line (which is normally connected to a pull up)
    nmi_o <= key_pressed_n(m65_mega) or key_pressed_n(m65_restore);

    -- 4-to-10 decoder for keyboard row selection. Active low.
    decoder: for sel in 0 to 9 generate
        row_n(sel) <= '0' when to_integer(unsigned(row_select_i)) = sel else '1';
    end generate;

    -- Since we use "negative logic" we swap 'and' and 'or' too; De Morgan.
    shift_n <= key_pressed_n(m65_left_shift) and key_pressed_n(m65_right_shift);
    mega_n <= key_pressed_n(m65_mega);

    -- Decode joystick direction (also with negative logic)
    joy1_direction(7) <=     joy_1_up_n_i or  not joy_1_down_n_i or      joy_1_left_n_i or  not joy_1_right_n_i;
    joy1_direction(8) <=     joy_1_up_n_i or  not joy_1_down_n_i or  not joy_1_left_n_i or  not joy_1_right_n_i;
    joy1_direction(9) <=     joy_1_up_n_i or  not joy_1_down_n_i or  not joy_1_left_n_i or      joy_1_right_n_i;

    joy1_direction(4) <= not joy_1_up_n_i or  not joy_1_down_n_i or      joy_1_left_n_i or  not joy_1_right_n_i;
--  joy1_direction(5) <= not joy_1_up_n_i or  not joy_1_down_n_i or  not joy_1_left_n_i or  not joy_1_right_n_i;
    joy1_direction(6) <= not joy_1_up_n_i or  not joy_1_down_n_i or  not joy_1_left_n_i or      joy_1_right_n_i;

    joy1_direction(1) <= not joy_1_up_n_i or      joy_1_down_n_i or      joy_1_left_n_i or  not joy_1_right_n_i;
    joy1_direction(2) <= not joy_1_up_n_i or      joy_1_down_n_i or  not joy_1_left_n_i or  not joy_1_right_n_i;
    joy1_direction(3) <= not joy_1_up_n_i or      joy_1_down_n_i or  not joy_1_left_n_i or      joy_1_right_n_i;


    matrix: entity work.matrix
        port map (
            key_n_i => pet_nb_n,    -- multiplexed either from N or B keyboard (pet_n_n or pet_b_n)
            row_n_i => row_n,
            col_n_o => column_selected_o
        );

    ---------------------------------------------------------------------
    --
    -- N keyboard decoding
    --
    -- Use MEGA to force-shift a key such as ! which is unshifted on this
    -- keyboard but shifted on the M65.
    ---------------------------------------------------------------------

    -- Mark the keys where we press SHIFT on the M65 keyboard, but which do not
    -- have shift on the PET keyboard.
    unshift_n <= shift_n or (key_pressed_n(m65_1) and           -- !
                             key_pressed_n(m65_2) and           -- "
                             key_pressed_n(m65_3) and           -- #
                             key_pressed_n(m65_4) and           -- $
                             key_pressed_n(m65_5) and           -- %
                             key_pressed_n(m65_6) and           -- &
                             key_pressed_n(m65_7) and           -- '
                             key_pressed_n(m65_8) and           -- (
                             key_pressed_n(m65_9) and           -- )
                             key_pressed_n(m65_comma) and       -- <
                             key_pressed_n(m65_dot) and         -- >
                             key_pressed_n(m65_slash) and       -- ?
                             key_pressed_n(m65_colon) and       -- [
                             key_pressed_n(m65_semicolon)       -- ]
                            );

    -- Set the individual key switches for every possible key (10 * 8).
    -- This is separate from the actual keyboard matrix (where these swiches connect
    -- rows to columns) because inlining them in the matrix expression is
    -- pretty unreadable. Now we could present the keys in scancode order
    -- if we whish. Also, in the future we may want to manipulate the
    -- switches before going into the matrix (for example for run-time changeable
    -- joystick control).

    -- column 0
    pet_n_n(9*8+8 -1) <= key_pressed_n(m65_1)          or shift_n; -- !
    pet_n_n(8*8+8 -1) <= key_pressed_n(m65_2)          or shift_n; -- "
    pet_n_n(7*8+8 -1) <= key_pressed_n(m65_q);                     -- q
    pet_n_n(6*8+8 -1) <= key_pressed_n(m65_w);                     -- w
    pet_n_n(5*8+8 -1) <= key_pressed_n(m65_a);                     -- a
    pet_n_n(4*8+8 -1) <= key_pressed_n(m65_s);                     -- s
    pet_n_n(3*8+8 -1) <= key_pressed_n(m65_z);                     -- z
    pet_n_n(2*8+8 -1) <= key_pressed_n(m65_x);                     -- x
    pet_n_n(1*8+8 -1) <= mega_n and                                -- mega is *always* shift
                          (key_pressed_n(m65_left_shift) or not unshift_n) and -- left shift unless !"<> etc
                           key_pressed_n(m65_up_crsr) and          --   or up
                           key_pressed_n(m65_left_crsr);           --   or left
    pet_n_n(0*8+8 -1) <= key_pressed_n(m65_ctrl);                  -- off/rvs

    -- column 1
    pet_n_n(9*8+7 -1) <= key_pressed_n(m65_3)          or shift_n; -- #
    pet_n_n(8*8+7 -1) <= key_pressed_n(m65_4)          or shift_n; -- $
    pet_n_n(7*8+7 -1) <= key_pressed_n(m65_e);                     -- e
    pet_n_n(6*8+7 -1) <= key_pressed_n(m65_r);                     -- r
    pet_n_n(5*8+7 -1) <= key_pressed_n(m65_d);                     -- d
    pet_n_n(4*8+7 -1) <= key_pressed_n(m65_f);                     -- f
    pet_n_n(3*8+7 -1) <= key_pressed_n(m65_c);                     -- c
    pet_n_n(2*8+7 -1) <= key_pressed_n(m65_v);                     -- v
    pet_n_n(1*8+7 -1) <= key_pressed_n(m65_at);                    -- @
    pet_n_n(0*8+7 -1) <= key_pressed_n(m65_colon)      or shift_n; -- [

    -- column 2
    pet_n_n(9*8+6 -1) <= key_pressed_n(m65_5)          or shift_n; -- %
    pet_n_n(8*8+6 -1) <= key_pressed_n(m65_7)          or shift_n; -- '
    pet_n_n(7*8+6 -1) <= key_pressed_n(m65_t);                     -- t
    pet_n_n(6*8+6 -1) <= key_pressed_n(m65_y);                     -- y
    pet_n_n(5*8+6 -1) <= key_pressed_n(m65_g);                     -- g
    pet_n_n(4*8+6 -1) <= key_pressed_n(m65_h);                     -- h
    pet_n_n(3*8+6 -1) <= key_pressed_n(m65_b);                     -- b
    pet_n_n(2*8+6 -1) <= key_pressed_n(m65_n);                     -- n
    pet_n_n(1*8+6 -1) <= key_pressed_n(m65_semicolon)  or shift_n; -- ]
    pet_n_n(0*8+6 -1) <= key_pressed_n(m65_space);                 -- space

    -- column 3
    pet_n_n(9*8+5 -1) <= key_pressed_n(m65_6)      or     shift_n; -- &
    pet_n_n(8*8+5 -1) <= key_pressed_n(m65_gbp);                   -- \ or pound
    pet_n_n(7*8+5 -1) <= key_pressed_n(m65_u);                     -- u
    pet_n_n(6*8+5 -1) <= key_pressed_n(m65_i);                     -- i
    pet_n_n(5*8+5 -1) <= key_pressed_n(m65_j);                     -- j
    pet_n_n(4*8+5 -1) <= key_pressed_n(m65_k);                     -- k
    pet_n_n(3*8+5 -1) <= key_pressed_n(m65_m);                     -- m
    pet_n_n(2*8+5 -1) <= key_pressed_n(m65_comma)  or not shift_n; -- ,
    pet_n_n(1*8+5 -1) <= '1';                                      -- n/c
    pet_n_n(0*8+5 -1) <= key_pressed_n(m65_comma)  or     shift_n; -- <

    -- column 4
    pet_n_n(9*8+4 -1) <= key_pressed_n(m65_8)          or     shift_n; -- (
    pet_n_n(8*8+4 -1) <= key_pressed_n(m65_9)          or     shift_n; -- )
    pet_n_n(7*8+4 -1) <= key_pressed_n(m65_o);                         -- o
    pet_n_n(6*8+4 -1) <= key_pressed_n(m65_p);                         -- p
    pet_n_n(5*8+4 -1) <= key_pressed_n(m65_l);                         -- l
    pet_n_n(4*8+4 -1) <= key_pressed_n(m65_colon)      or not shift_n; -- :
    pet_n_n(3*8+4 -1) <= key_pressed_n(m65_semicolon)  or not shift_n; -- ;
    pet_n_n(2*8+4 -1) <= key_pressed_n(m65_slash)      or     shift_n; -- ?
    pet_n_n(1*8+4 -1) <= key_pressed_n(m65_dot)        or     shift_n; -- >
    pet_n_n(0*8+4 -1) <= key_pressed_n(m65_run_stop);                  -- run/stop

    -- column 5
    pet_n_n(9*8+3 -1) <= key_pressed_n(m65_arrow_left);                   -- <-
    pet_n_n(8*8+3 -1) <= '1';                                             -- n/c
    pet_n_n(7*8+3 -1) <= key_pressed_n(m65_arrow_up);                     -- ^
    pet_n_n(6*8+3 -1) <= '1';                                             -- n/c
    pet_n_n(5*8+3 -1) <= '1';                                             -- n/c
    pet_n_n(4*8+3 -1) <= '1';                                             -- n/c
    pet_n_n(3*8+3 -1) <= key_pressed_n(m65_return);                       -- return
    pet_n_n(2*8+3 -1) <= '1';                                             -- n/c
    pet_n_n(1*8+3 -1) <= key_pressed_n(m65_right_shift) or not unshift_n; -- right shift, unless !"#$ etc
    pet_n_n(0*8+3 -1) <= '1';                                             -- n/c

    -- column 6
    pet_n_n(9*8+2 -1) <= key_pressed_n(m65_clr_home);                  -- clr/home
    pet_n_n(8*8+2 -1) <= key_pressed_n(m65_vert_crsr) and
                         key_pressed_n(m65_up_crsr);                   -- crsr down (or up)
    pet_n_n(7*8+2 -1) <= (key_pressed_n(m65_7)      or not shift_n)
                          and joy1_direction(7);                       -- 7
    pet_n_n(6*8+2 -1) <= (key_pressed_n(m65_8)      or not shift_n)
                          and joy1_direction(8);                       -- 8
    pet_n_n(5*8+2 -1) <= (key_pressed_n(m65_4)      or not shift_n)
                          and joy1_direction(4);                       -- 4
    pet_n_n(4*8+2 -1) <= key_pressed_n(m65_5)       or not shift_n;    -- 5
    pet_n_n(3*8+2 -1) <= (key_pressed_n(m65_1)      or not shift_n)
                          and joy1_direction(1);                       -- 1
    pet_n_n(2*8+2 -1) <= (key_pressed_n(m65_2)      or not shift_n)
                          and joy1_direction(2);                       -- 2
    pet_n_n(1*8+2 -1) <= key_pressed_n(m65_0);                         -- 0
    pet_n_n(0*8+2 -1) <= key_pressed_n(m65_dot)      or not shift_n;   -- .

    -- column 7
    pet_n_n(9*8+1 -1) <= key_pressed_n(m65_horz_crsr) and
                         key_pressed_n(m65_left_crsr);                 -- crsr => (or <=)
    pet_n_n(8*8+1 -1) <= key_pressed_n(m65_ins_del);                   -- inst/del
    pet_n_n(7*8+1 -1) <= (key_pressed_n(m65_9)        or not shift_n)
                          and joy1_direction(9);                       -- 9
    pet_n_n(6*8+1 -1) <= key_pressed_n(m65_slash)     or not shift_n;  -- /
    pet_n_n(5*8+1 -1) <= (key_pressed_n(m65_6)        or not shift_n)
                          and joy1_direction(6);                       -- 6
    pet_n_n(4*8+1 -1) <= key_pressed_n(m65_asterisk);                  -- *
    pet_n_n(3*8+1 -1) <= (key_pressed_n(m65_3)        or not shift_n)
                          and joy1_direction(3);                       -- 3
    pet_n_n(2*8+1 -1) <= key_pressed_n(m65_plus);                      -- +
    pet_n_n(1*8+1 -1) <= key_pressed_n(m65_minus);                     -- -
    pet_n_n(0*8+1 -1) <= key_pressed_n(m65_equal);                     -- =

    ---------------------------------------------------------------------
    --
    -- B keyboard decoding.
    --
    -- Use the MEGA + digits (or dot) for the numeric pad version.
    -- Use MEGA to shift the unshifted chars [ and ].
    -- Use ALT for the repeat key.
    -- * beside a charactre means that it has no shifted equivalent.
    --   for digits this means it's the numeric keypad version.
    -- the numbers in [brackets] appear to be unused PETSCII values.
    ---------------------------------------------------------------------
    b_unshift_n <= shift_n or (key_pressed_n(m65_colon) and       -- [
                               key_pressed_n(m65_semicolon)       -- ]
                            );

    -- The indexes below correspond to the keyboard scan codes from RAM location 151
    -- (except that later ROM versions don't expose the value and translate to PETSCII)
    -- column 0
    pet_b_n(9*8+8 -1) <= key_pressed_n(m65_2)   or not mega_n;      -- 2
    pet_b_n(8*8+8 -1) <= key_pressed_n(m65_1)   or not mega_n;      -- 1
    pet_b_n(7*8+8 -1) <= key_pressed_n(m65_esc);                    -- ESC*
    pet_b_n(6*8+8 -1) <= key_pressed_n(m65_a);                      -- a
    pet_b_n(5*8+8 -1) <= key_pressed_n(m65_tab);                    -- TAB
    pet_b_n(4*8+8 -1) <= key_pressed_n(m65_q);                      -- q
    pet_b_n(3*8+8 -1) <= ((key_pressed_n(m65_left_shift) or not b_unshift_n) and   -- left shift unless ...
                          (b_unshift_n or mega_n) and               --   or mega+[]
                          key_pressed_n(m65_asterisk) and           --   or *
                          key_pressed_n(m65_equal) and              --   or =
                          key_pressed_n(m65_plus) and               --   or +
                          key_pressed_n(m65_up_crsr) and            --   or up
                          key_pressed_n(m65_left_crsr));            --   or left
    pet_b_n(2*8+8 -1) <= key_pressed_n(m65_z);                      -- z
    pet_b_n(1*8+8 -1) <= key_pressed_n(m65_ctrl);                   -- off/rvs
    pet_b_n(0*8+8 -1) <= key_pressed_n(m65_arrow_left);             -- <- left arrow*

    -- column 1
    pet_b_n(9*8+7 -1) <= key_pressed_n(m65_5)    or not mega_n;     -- 5
    pet_b_n(8*8+7 -1) <= key_pressed_n(m65_4)    or not mega_n;     -- 4
    pet_b_n(7*8+7 -1) <= key_pressed_n(m65_s);                      -- s
    pet_b_n(6*8+7 -1) <= key_pressed_n(m65_d);                      -- d
    pet_b_n(5*8+7 -1) <= key_pressed_n(m65_w);                      -- w
    pet_b_n(4*8+7 -1) <= key_pressed_n(m65_e);                      -- e
    pet_b_n(3*8+7 -1) <= key_pressed_n(m65_c);                      -- c
    pet_b_n(2*8+7 -1) <= key_pressed_n(m65_v);                      -- v
    pet_b_n(1*8+7 -1) <= key_pressed_n(m65_x);                      -- x
    pet_b_n(0*8+7 -1) <= key_pressed_n(m65_3)    or not mega_n;     -- 3

    -- column 2
    pet_b_n(9*8+6 -1) <= key_pressed_n(m65_8)    or not mega_n;     -- 8
    pet_b_n(8*8+6 -1) <= key_pressed_n(m65_7)    or not mega_n;     -- 7
    pet_b_n(7*8+6 -1) <= key_pressed_n(m65_f);                      -- f
    pet_b_n(6*8+6 -1) <= key_pressed_n(m65_g);                      -- g
    pet_b_n(5*8+6 -1) <= key_pressed_n(m65_r);                      -- r
    pet_b_n(4*8+6 -1) <= key_pressed_n(m65_t);                      -- t
    pet_b_n(3*8+6 -1) <= key_pressed_n(m65_b);                      -- b
    pet_b_n(2*8+6 -1) <= key_pressed_n(m65_n);                      -- n
    pet_b_n(1*8+6 -1) <= key_pressed_n(m65_space);                  -- SPACE
    pet_b_n(0*8+6 -1) <= key_pressed_n(m65_6)    or not mega_n;     -- 6

    -- column 3
    pet_b_n(9*8+5 -1) <= (key_pressed_n(m65_minus) and
                          key_pressed_n(m65_equal));                -- - and =
    pet_b_n(8*8+5 -1) <= key_pressed_n(m65_0);                      -- 0* (top row)
    pet_b_n(7*8+5 -1) <= key_pressed_n(m65_h);                      -- h
    pet_b_n(6*8+5 -1) <= key_pressed_n(m65_j);                      -- j
    pet_b_n(5*8+5 -1) <= key_pressed_n(m65_y);                      -- y
    pet_b_n(4*8+5 -1) <= key_pressed_n(m65_u);                      -- u
    pet_b_n(3*8+5 -1) <= key_pressed_n(m65_dot)  or not mega_n;     -- . and <
    pet_b_n(2*8+5 -1) <= key_pressed_n(m65_comma);                  -- , and >
    pet_b_n(1*8+5 -1) <= key_pressed_n(m65_m);                      -- m
    pet_b_n(0*8+5 -1) <= key_pressed_n(m65_9)    or not mega_n;     -- 9

    -- column 4
    pet_b_n(9*8+4 -1) <= ((key_pressed_n(m65_8)  or     mega_n)
                           and joy1_direction(8));                  -- 8*
    pet_b_n(8*8+4 -1) <= ((key_pressed_n(m65_7)  or     mega_n)
                           and joy1_direction(7));                  -- 7*
    pet_b_n(7*8+4 -1) <= key_pressed_n(m65_semicolon) or shift_n;   -- ]*
    pet_b_n(6*8+4 -1) <= key_pressed_n(m65_return);                 -- RETURN
    pet_b_n(5*8+4 -1) <= key_pressed_n(m65_gbp);                    -- \*
    pet_b_n(4*8+4 -1) <= (key_pressed_n(m65_vert_crsr) and
                          key_pressed_n(m65_up_crsr));              -- crsr down (or up)
    pet_b_n(3*8+4 -1) <= key_pressed_n(m65_dot)  or     mega_n;     -- .*
    pet_b_n(2*8+4 -1) <= key_pressed_n(m65_0)    or     mega_n;     -- 0* (keypad)
    pet_b_n(1*8+4 -1) <= key_pressed_n(m65_clr_home);               -- HOME
    pet_b_n(0*8+4 -1) <= key_pressed_n(m65_run_stop);               -- STOP

    -- column 5
    pet_b_n(9*8+3 -1) <= (key_pressed_n(m65_horz_crsr) and
                          key_pressed_n(m65_left_crsr));            -- crsr => (or <=)
    pet_b_n(8*8+3 -1) <= key_pressed_n(m65_arrow_up);               -- ^*
    pet_b_n(7*8+3 -1) <= key_pressed_n(m65_k);                      -- k
    pet_b_n(6*8+3 -1) <= key_pressed_n(m65_l);                      -- l
    pet_b_n(5*8+3 -1) <= key_pressed_n(m65_i);                      -- i
    pet_b_n(4*8+3 -1) <= key_pressed_n(m65_o);                      -- o
    pet_b_n(3*8+3 -1) <= '1';                                       -- [25]
    pet_b_n(2*8+3 -1) <= '1';                                       -- [15]
    pet_b_n(1*8+3 -1) <= '1';                                       -- [21]
    pet_b_n(0*8+3 -1) <= ((key_pressed_n(m65_colon) or not shift_n) and
                          key_pressed_n(m65_asterisk));             -- : and *

    -- column 6
    pet_b_n(9*8+2 -1) <= '1';                                       -- [14]
    pet_b_n(8*8+2 -1) <= '1';                                       -- [6]
    pet_b_n(7*8+2 -1) <= ((key_pressed_n(m65_semicolon) or not shift_n) and
                           key_pressed_n(m65_plus));                -- ; and +
    pet_b_n(6*8+2 -1) <= key_pressed_n(m65_at);                     -- @
    pet_b_n(5*8+2 -1) <= key_pressed_n(m65_p);                      -- p
    pet_b_n(4*8+2 -1) <= (key_pressed_n(m65_colon) or     shift_n); -- [*
    pet_b_n(3*8+2 -1) <= key_pressed_n(m65_right_shift) or not b_unshift_n;  -- RIGHT SHIFT
    pet_b_n(2*8+2 -1) <= key_pressed_n(m65_alt);                    -- [16] REPEAT
    pet_b_n(1*8+2 -1) <= key_pressed_n(m65_slash);                  -- / and ?
    pet_b_n(0*8+2 -1) <= '1';                                       -- [4]

    -- column 7
    pet_b_n(9*8+1 -1) <= '1';                                       -- [5]
    pet_b_n(8*8+1 -1) <= ((key_pressed_n(m65_9)  or     mega_n)
                           and joy1_direction(9));                  -- 9*
    pet_b_n(7*8+1 -1) <= key_pressed_n(m65_5)    or     mega_n;     -- 5*
    pet_b_n(6*8+1 -1) <= ((key_pressed_n(m65_6)  or     mega_n)
                           and joy1_direction(6));                  -- 6*
    pet_b_n(5*8+1 -1) <= key_pressed_n(m65_ins_del);                -- INST/DEL
    pet_b_n(4*8+1 -1) <= ((key_pressed_n(m65_4)  or     mega_n)
                           and joy1_direction(4));                  -- 4*
    pet_b_n(3*8+1 -1) <= ((key_pressed_n(m65_3)  or     mega_n)
                           and joy1_direction(3));                  -- 3*
    pet_b_n(2*8+1 -1) <= ((key_pressed_n(m65_2)  or     mega_n)
                           and joy1_direction(2));                  -- 2*
    pet_b_n(1*8+1 -1) <= ((key_pressed_n(m65_1)  or     mega_n)
                           and joy1_direction(1));                  -- 1*
    pet_b_n(0*8+1 -1) <= '1';                                       -- [20]

    -- The state machine for the run-time joystick configuration.
    -- For now we only can configure which key is pressed by the fire button.
    config : process(clk_main_i) is
    begin
        if rising_edge(clk_main_i) then
            -- Detect keyboard layout change.
            -- When this happens, set the fire button to the A key again.
            prev_business_layout <= business_layout_i;

            if prev_business_layout /= business_layout_i then
                config_state <= sIDLE;

                if business_layout_i then
                    fire_pet_key_num <= 56 -1;
                else
                    fire_pet_key_num <= 48 -1;
                end if;
            end if;

            case config_state is
                when sIDLE =>
                    -- If F1 is pressed, proceed.
		    if (key_pressed_n(m65_f1) or not shift_n or not mega_n) = '0' then
                        config_state <= sWAITJS1;
                    end if;
                when sWAITJS1 =>
                    -- If F1 is released, proceed.
                    if key_pressed_n(m65_f1) = '1' then
                        config_state <= sWAITJS2;
                    end if;
                when sWAITJS2 =>
                    -- If fire is pressed, proceed.
                    if joy_1_fire_n_i = '0' then
                        config_state <= sWAITKEY;
                    end if;
                when sWAITKEY =>
                    -- If fire is released, go back and wait for it again.
                    if joy_1_fire_n_i = '1' then
                        config_state <= sWAITJS2;
                    -- If fire is still pressed and also some other key, proceed and finalize.
                    elsif joy_1_fire_n_i = '0' and (pet_key_num_pressed /= pet_none)
                    then
                        config_state <= sIDLE;
                        fire_pet_key_num <= pet_key_num_pressed;
                    end if;
            end case;
        end if;
    end process;
end beh;
