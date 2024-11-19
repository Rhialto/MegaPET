----------------------------------------------------------------
--
-- An IEEE bus with a master (the PET) and one connected device.
--
----------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity ieee488_bus_1 is
    port (
        pet_data_i : in  std_logic_vector(7 downto 0); -- in from PET
        pet_data_o : out std_logic_vector(7 downto 0); -- out to PET
        pet_atn_i  : in  std_logic;             -- only set by controller
        pet_atn_o  : out std_logic;
        pet_ifc_i  : in  std_logic;             -- only set by controller
        pet_srq_o  : out std_logic;             -- only set by device, to PET
--      pet_ren_i  : out std_logic;             -- unused
        pet_dav_i  : in  std_logic;
        pet_dav_o  : out std_logic;
        pet_eoi_i  : in  std_logic;
        pet_eoi_o  : out std_logic;
        pet_nrfd_i : in  std_logic;
        pet_nrfd_o : out std_logic;
        pet_ndac_i : in  std_logic;
        pet_ndac_o : out std_logic;

        -- Multiple attached devices would multiply the block below.
        d01_data_i : in  std_logic_vector(7 downto 0) := (others => 'H');
        d01_data_o : out std_logic_vector(7 downto 0);
        d01_atn_i  : in  std_logic := 'H';
        d01_atn_o  : out std_logic;             -- only set by controller
        d01_ifc_o  : out std_logic;             -- only set by controller
        d01_srq_i  : in  std_logic := 'H';      -- only set by device
        d01_dav_i  : in  std_logic := 'H';
        d01_dav_o  : out std_logic;
        d01_eoi_i  : in  std_logic := 'H';
        d01_eoi_o  : out std_logic;
        d01_nrfd_i : in  std_logic := 'H';
        d01_nrfd_o : out std_logic;
        d01_ndac_i : in  std_logic := 'H';
        d01_ndac_o : out std_logic
         );
end entity ieee488_bus_1;

architecture simplistic of ieee488_bus_1 is

    attribute mark_debug : string;
    attribute mark_debug of pet_data_i : signal is "true";
    attribute mark_debug of pet_data_o : signal is "true";
    attribute mark_debug of pet_atn_i  : signal is "true";
    attribute mark_debug of pet_dav_i  : signal is "true";
    attribute mark_debug of pet_dav_o  : signal is "true";
    attribute mark_debug of pet_eoi_i  : signal is "true";
    attribute mark_debug of pet_eoi_o  : signal is "true";
    attribute mark_debug of pet_nrfd_i : signal is "true";
    attribute mark_debug of pet_nrfd_o : signal is "true";
    attribute mark_debug of pet_ndac_i : signal is "true";
    attribute mark_debug of pet_ndac_o : signal is "true";

    attribute mark_debug of d01_data_i : signal is "true";
    attribute mark_debug of d01_data_o : signal is "true";

    signal    data   : std_logic_vector(7 downto 0);
    signal    atn    : std_logic;               -- only set by controller
    signal    ifc    : std_logic;               -- only set by controller
    signal    srq    : std_logic;               -- only set by device
    signal    dav    : std_logic;
    signal    eoi    : std_logic;
    signal    nrfd   : std_logic;
    signal    ndac   : std_logic;

    attribute mark_debug of data       : signal is "true";
begin
    -- AND all the respective signals from all devices.
    data <= pet_data_i and d01_data_i;
    atn  <= pet_atn_i  and d01_atn_i;
    ifc  <= pet_ifc_i;
    srq  <= d01_srq_i;
    dav  <= pet_dav_i  and d01_dav_i;
    eoi  <= pet_eoi_i  and d01_eoi_i;
    nrfd <= pet_nrfd_i and d01_nrfd_i;
    ndac <= pet_ndac_i and d01_ndac_i;

    -- Provide the PET and each device with the result.
    pet_data_o <= data;
    pet_atn_o  <= atn;
    pet_srq_o  <= srq;
    pet_dav_o  <= dav;
    pet_eoi_o  <= eoi;
    pet_nrfd_o <= nrfd;
    pet_ndac_o <= ndac;

    d01_data_o <= data;
    d01_atn_o  <= atn;
    d01_ifc_o  <= ifc;
    d01_dav_o  <= dav;
    d01_eoi_o  <= eoi;
    d01_nrfd_o <= nrfd;
    d01_ndac_o <= ndac;

end architecture simplistic;
