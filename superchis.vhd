library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity superchis is
    port (
        -- Global Clocks and Control
        CLK50MHz : in  std_logic;
        GP_NCS   : in  std_logic;  -- GBA Chip Select (Active Low)
        GP_NWR   : in  std_logic;  -- GBA Write Enable (Active Low)
        GP_NRD   : in  std_logic;  -- GBA Read Enable (Active Low)
        clk3     : in  std_logic;  -- Auxiliary Clock

        -- General Purpose IO (from GBA cart edge)
        GP       : inout std_logic_vector(15 downto 0);  -- GBA Data Bus
        GP_16    : in  std_logic;
        GP_17    : in  std_logic;
        GP_18    : in  std_logic;
        GP_19    : in  std_logic;
        GP_20    : in  std_logic;
        GP_21    : in  std_logic;
        GP_22    : in  std_logic;
        GP_23    : in  std_logic;

        -- DDR SDRAM Interface
        DDR_A    : out std_logic_vector(12 downto 0);  -- DDR Address Bus
        DDR_BA   : out std_logic_vector(1 downto 0);   -- DDR Bank Address
        DDR_CKE  : out std_logic;                       -- DDR Clock Enable
        DDR_NRAS : out std_logic;                       -- DDR Row Address Strobe (Active Low)
        DDR_NCAS : out std_logic;                       -- DDR Column Address Strobe (Active Low)
        DDR_NWE  : out std_logic;                       -- DDR Write Enable (Active Low)

        -- Flash Interface
        FLASH_A          : out std_logic_vector(15 downto 0);  -- Flash Address Bus
        FLASH_NCE        : out std_logic;                       -- Flash Chip Enable (Active Low)
        FLASH_SRAM_NWE   : out std_logic;                       -- Flash Write Enable (Active Low)
        FLASH_SRAM_NOE   : out std_logic;                       -- Flash Output Enable (Active Low)
        SRAM_A16         : out std_logic;                       -- SRAM High Address bit

        -- SD Card Interface
        N_SDOUT : out std_logic;                          -- SD Card Output Enable (Active Low)
        SD_CLK  : out std_logic;                          -- SD Card Clock
        SD_CMD  : inout std_logic;                        -- SD Card Command Line
        SD_DAT  : inout std_logic_vector(3 downto 0)      -- SD Card Data Lines
    );
end entity superchis;

architecture behavioral of superchis is

    -- ========================================================================
    -- Type Definitions
    -- ========================================================================
    
    -- DDR SDRAM State Machine
    type ddr_state_t is (
        DDR_IDLE,
        DDR_PRECHARGE,
        DDR_ACTIVATE,
        DDR_READ,
        DDR_WRITE,
        DDR_REFRESH
    );
    
    -- Access Mode Types
    type access_mode_t is (
        MODE_FLASH,
        MODE_DDR,
        MODE_SD
    );

    -- ========================================================================
    -- Internal Signals
    -- ========================================================================
    
    -- Configuration Registers
    signal config_map_reg     : std_logic := '0';          -- 0=Flash, 1=DDR
    signal config_sd_enable   : std_logic := '0';          -- SD Card Enable
    signal config_write_enable: std_logic := '0';          -- Write Enable
    signal config_bank_select : std_logic_vector(2 downto 0) := "000";  -- Bank Selection
    
    -- Magic Unlock Sequence
    signal magic_address      : std_logic := '0';          -- Magic Address Detection
    signal magic_value_match  : std_logic := '0';          -- Magic Value (0xA55A) Detection
    signal config_load_enable : std_logic := '0';          -- Configuration Load Enable
    signal magic_write_count  : unsigned(1 downto 0) := "00"; -- Count magic value writes
    
    -- Address Management
    signal internal_address   : unsigned(15 downto 0) := (others => '0');  -- Internal Address Counter
    signal flash_address      : std_logic_vector(15 downto 0);  -- Flash Address Bus
    signal ddr_address        : std_logic_vector(12 downto 0);   -- DDR Address Bus
    signal ddr_bank_address   : std_logic_vector(1 downto 0);    -- DDR Bank Address
    
    -- DDR Control Signals
    signal ddr_state          : ddr_state_t := DDR_IDLE;
    signal ddr_counter        : unsigned(3 downto 0) := (others => '0');
    signal ddr_refresh_counter: unsigned(8 downto 0) := (others => '0');
    signal ddr_cke_reg        : std_logic := '0';
    signal ddr_ras_reg        : std_logic := '1';
    signal ddr_cas_reg        : std_logic := '1';
    signal ddr_we_reg         : std_logic := '1';
    
    -- Access Control
    signal current_mode       : access_mode_t := MODE_FLASH;
    signal sd_output_enable   : std_logic := '1';
    
    -- Bus Control
    signal gp_output_enable   : std_logic := '0';
    signal gp_output_data     : std_logic_vector(15 downto 0) := (others => '0');
    
    -- Timing Control
    signal address_load       : std_logic := '0';
    signal address_load_sync  : std_logic := '0';  -- Synchronized version (equivalent to mc_H10)
    signal address_load_sync2 : std_logic := '0';  -- Second stage sync (equivalent to mc_H5)
    signal write_sync         : std_logic;
    signal read_sync          : std_logic;
    signal write_enable_sync  : std_logic;  -- Additional sync for write enable
    signal timing_sync3       : std_logic := '0';  -- Equivalent to mc_H14
    signal timing_sync4       : std_logic := '0';  -- Equivalent to mc_H15
    
    -- SD Card Signals
    signal sd_clock           : std_logic := '0';
    signal sd_cmd_out         : std_logic := '1';
    signal sd_data_out        : std_logic_vector(3 downto 0) := (others => '1');
    signal sd_cmd_oe          : std_logic := '0';
    signal sd_data_oe         : std_logic_vector(3 downto 0) := (others => '0');
    
    -- SD Card State Signals (equivalent to original macrocells)
    signal sd_dat_state       : std_logic_vector(3 downto 0) := (others => '0');  -- mc_H3,F5,E0,E2
    signal sd_cmd_state       : std_logic := '0';  -- mc_E13
    signal sd_dat_toggle      : std_logic_vector(3 downto 0) := (others => '0');  -- mc_F0,F1,F14,F15
    signal sd_cmd_toggle      : std_logic := '0';  -- mc_F7
    signal sd_common_logic    : std_logic := '0';  -- mc_H9

begin

    -- ========================================================================
    -- Address Decoding and Mode Selection
    -- ========================================================================
    
    process(internal_address, config_map_reg, config_sd_enable, GP_16, GP_17, GP_18, GP_19, GP_20, GP_21, GP_22, GP_23)
    begin
        -- Default to Flash mode
        current_mode <= MODE_FLASH;
        
        if config_sd_enable = '1' then
            -- SD Card interface is mapped into ROM address space
            current_mode <= MODE_SD;
        elsif config_map_reg = '1' then
            -- SDRAM mode (instead of internal Flash)
            current_mode <= MODE_DDR;
        else
            -- Flash/SRAM mode (default)
            -- SRAM is accessed through the same interface as Flash
            -- Address decoding determines which physical device is selected
            current_mode <= MODE_FLASH;
        end if;
    end process;

    -- ========================================================================
    -- Magic Address Detection and Configuration
    -- ========================================================================
    
    -- Magic address detection: 0x09FFFFFE->0x01FFFFFE(8bit)->0x00FFFFFF(16bit) (SuperCard mode register)
    magic_address <= '1' when (internal_address = x"FFFF" and
                               GP_16 = '1' and GP_17 = '1' and GP_18 = '1' and GP_19 = '1' and
                               GP_20 = '1' and GP_21 = '1' and GP_22 = '1' and GP_23 = '1') else '0';
    
    -- Magic value detection: 0xA55A
    magic_value_match <= '1' when (GP(15 downto 0) = x"A55A") else '0';
    
    -- Magic sequence state machine to match driver behavior (2x magic, 2x config)
    process(GP_NWR)
    begin
        if rising_edge(GP_NWR) then
            if magic_address = '1' then
                case magic_write_count is
                    when "00" => -- Expect first magic value
                        if magic_value_match = '1' then
                            magic_write_count <= "01";
                        end if;
                    when "01" => -- Expect second magic value
                        if magic_value_match = '1' then
                            magic_write_count <= "10";
                        else
                            magic_write_count <= "00"; -- Reset on wrong value
                        end if;
                    when "10" => -- Expect first config value
                        -- Load config registers on the first config write
                        config_sd_enable    <= GP(1);
                        config_map_reg      <= GP(0);
                        config_write_enable <= GP(2);
                        -- Load flash banking bits, faithfully matching original.vhd logic
                        config_bank_select(0) <= GP(4) and not GP(8) and GP(12); -- mc_C10
                        config_bank_select(1) <= GP(7) and not GP(10) and GP(11);-- mc_G14
                        config_bank_select(2) <= GP(7) and GP(9) and not GP(15); -- mc_D9
                        magic_write_count   <= "11";
                    when "11" => -- Expect second config value, then reset
                        magic_write_count <= "00";
                    when others =>
                        magic_write_count <= "00";
                end case;
            else
                -- If write is not to magic address, reset the sequence
                magic_write_count <= "00";
            end if;
        end if;
    end process;

    -- ========================================================================
    -- Internal Address Counter
    -- ========================================================================
    
    -- Address load control (equivalent to original addr_load logic)
    -- Original: addr_load <= (GP_NWR and GP_NRD and addr_load) or GP_NCS;
    -- This is a latch that holds '1' when GP_NCS is high, and maintains state when both GP_NWR and GP_NRD are high
    address_load <= (GP_NWR and GP_NRD and address_load) or GP_NCS;
    
    -- Internal address counter with load capability
    process(GP_NCS, GP_NWR, GP_NRD)
        variable addr_clock : std_logic;
    begin
        -- Generate address counter clock (equivalent to mc_H11 in original)
        addr_clock := (not GP_NCS and GP_NWR and GP_NRD) or 
                     (GP_NCS and not GP_NRD) or 
                     (GP_NCS and not GP_NWR);
        
        if rising_edge(addr_clock) then
            if address_load = '1' then
                internal_address <= unsigned(GP);
            else
                internal_address <= internal_address + 1;
            end if;
        end if;
    end process;

    -- ========================================================================
    -- Flash Address Generation
    -- ========================================================================
    
    process(internal_address, config_bank_select, current_mode, config_write_enable)
    begin
        -- Default to a direct mapping of the internal address
        flash_address <= std_logic_vector(internal_address);
        
        -- Bank selection for extended addressing, faithfully matching original.vhd
        if current_mode = MODE_FLASH then
            -- The original design uses OR logic to apply banking bits to the address.
            -- This is a direct reconstruction of the logic found in GLB C and D.
            flash_address(15) <= internal_address(15) or config_bank_select(2) or config_bank_select(1) or config_bank_select(0); -- mc_D0
            flash_address(14) <= internal_address(14) or config_bank_select(1); -- mc_C6
            flash_address(11) <= internal_address(11) or config_bank_select(2); -- mc_D2
            flash_address(7)  <= internal_address(7)  or config_bank_select(0); -- mc_D1 (original was iaddr(4), typo in original)
            
            -- Flash address bit 9 gating (equivalent to mc_E7 in original)
            -- Only allow A9 to be set when write is enabled
            flash_address(9) <= internal_address(9) and config_write_enable;
        end if;
    end process;
    
    FLASH_A <= flash_address;
    
    -- SRAM A16 uses config_write_enable (equivalent to original WRITEENABLE)
    SRAM_A16 <= config_write_enable;

    -- ========================================================================
    -- DDR SDRAM Controller
    -- ========================================================================
    
    -- DDR State Machine
    process(GP_NCS)
    begin
        if rising_edge(GP_NCS) then
            case ddr_state is
                when DDR_IDLE =>
                    ddr_counter <= (others => '0');
                    -- DDR operation requires mc_E3 and mc_H0 to be high
                    -- mc_E3 = GP_NWR or not WRITEENABLE (high when not writing or write disabled)
                    -- mc_H0 = GP_NRD (high when not reading)
                    -- So DDR starts when not actively reading/writing
                    if current_mode = MODE_DDR and 
                       write_enable_sync = '1' and read_sync = '1' then
                        ddr_state <= DDR_ACTIVATE;
                    elsif ddr_refresh_counter(8) = '1' then
                        ddr_state <= DDR_REFRESH;
                    end if;
                    
                when DDR_ACTIVATE =>
                    ddr_counter <= ddr_counter + 1;
                    if ddr_counter = "0010" then  -- tRCD timing
                        -- Write if GP_NWR is low and write is enabled
                        if GP_NWR = '0' and config_write_enable = '1' then
                            ddr_state <= DDR_WRITE;
                        elsif GP_NRD = '0' then
                            ddr_state <= DDR_READ;
                        else
                            ddr_state <= DDR_IDLE;  -- No read/write, go to idle
                        end if;
                    end if;
                    
                when DDR_READ =>
                    ddr_counter <= ddr_counter + 1;
                    if ddr_counter = "0100" then  -- Read latency
                        ddr_state <= DDR_PRECHARGE;
                    end if;
                    
                when DDR_WRITE =>
                    ddr_counter <= ddr_counter + 1;
                    if ddr_counter = "0010" then  -- Write timing
                        ddr_state <= DDR_PRECHARGE;
                    end if;
                    
                when DDR_PRECHARGE =>
                    ddr_counter <= ddr_counter + 1;
                    if ddr_counter = "0011" then  -- tRP timing
                        ddr_state <= DDR_IDLE;
                    end if;
                    
                when DDR_REFRESH =>
                    ddr_counter <= ddr_counter + 1;
                    if ddr_counter = "0111" then  -- Refresh timing
                        ddr_state <= DDR_IDLE;
                        ddr_refresh_counter <= (others => '0');
                    end if;
            end case;
            
            -- Refresh counter
            if ddr_state /= DDR_REFRESH then
                ddr_refresh_counter <= ddr_refresh_counter + 1;
            end if;
        end if;
    end process;
    
    -- DDR Command Generation
    process(ddr_state, current_mode, write_enable_sync)
    begin
        ddr_cke_reg <= '0';
        ddr_ras_reg <= '1';
        ddr_cas_reg <= '1';
        ddr_we_reg  <= '1';
        
        if current_mode = MODE_DDR then
            ddr_cke_reg <= '1';
            
            case ddr_state is
                when DDR_ACTIVATE =>
                    ddr_ras_reg <= '0';  -- RAS active
                    
                when DDR_READ =>
                    ddr_cas_reg <= '0';  -- CAS active for read
                    
                when DDR_WRITE =>
                    -- The decision to write is made when entering this state.
                    -- The previous condition on write_enable_sync was incorrect as the
                    -- signal is '0' during a write, preventing the command from issuing.
                    ddr_cas_reg <= '0';  -- CAS active
                    ddr_we_reg  <= '0';  -- WE active for write
                    
                when DDR_PRECHARGE =>
                    ddr_ras_reg <= '0';  -- RAS active
                    ddr_we_reg  <= '0';  -- WE active for precharge
                    
                when DDR_REFRESH =>
                    ddr_ras_reg <= '0';  -- RAS active
                    ddr_cas_reg <= '0';  -- CAS active for refresh
                    
                when others =>
                    null;
            end case;
        end if;
    end process;
    
    -- DDR Address Multiplexing
    process(ddr_state, internal_address, GP_16, GP_17, GP_18, GP_19, GP_20, GP_21, GP_22, GP_23)
    begin
        -- This logic is a faithful reconstruction of the original hardware's
        -- unusual address multiplexing scheme. It combines the GBA's upper address
        -- bus (GP_16 to GP_21) with the lower address bus (via internal_address)
        -- to form the SDRAM row and column addresses.
        
        -- Default assignments for safety in unused states
        ddr_address      <= (others => '0');
        ddr_bank_address <= "00";

        case ddr_state is
            when DDR_ACTIVATE | DDR_PRECHARGE | DDR_REFRESH =>
                -- Row Address Composition, based on original.vhd analysis
                ddr_address(12) <= GP_21;
                ddr_address(11) <= GP_20;
                ddr_address(10) <= GP_19;
                ddr_address(9)  <= GP_18;
                ddr_address(8)  <= GP_17;
                ddr_address(7)  <= GP_16;
                ddr_address(6)  <= internal_address(15);
                ddr_address(5)  <= internal_address(14);
                ddr_address(4)  <= internal_address(13);
                ddr_address(3)  <= internal_address(12);
                ddr_address(2)  <= internal_address(11);
                ddr_address(1)  <= internal_address(10);
                ddr_address(0)  <= internal_address(9);
                
                ddr_bank_address <= GP_23 & GP_22;
                
            when DDR_READ | DDR_WRITE =>
                -- Column Address Composition, based on original.vhd analysis
                -- The original leaves some address bits unchanged; we make this explicit.
                -- High bits are zeroed as they are not part of the column address.
                ddr_address(12 downto 11) <= "00";
                ddr_address(10) <= GP_19; -- Note: Unusual dependency on a high-order GBA address bit.
                ddr_address(9)  <= '0';
                ddr_address(8)  <= internal_address(8);
                ddr_address(7)  <= '0';
                ddr_address(6)  <= internal_address(6);
                ddr_address(5)  <= internal_address(5);
                ddr_address(4)  <= internal_address(4);
                ddr_address(3)  <= internal_address(3);
                ddr_address(2)  <= internal_address(2);
                ddr_address(1)  <= internal_address(1);
                ddr_address(0)  <= internal_address(0);
                
                ddr_bank_address <= GP_23 & GP_22; -- Bank address is stable during operation
                
            when others =>
                -- In DDR_IDLE, address lines are don't care, but driving '0' is safe.
                null;
        end case;
    end process;
    
    DDR_A    <= ddr_address;
    DDR_BA   <= ddr_bank_address;
    DDR_CKE  <= ddr_cke_reg;
    DDR_NRAS <= ddr_ras_reg;
    DDR_NCAS <= ddr_cas_reg;
    DDR_NWE  <= ddr_we_reg;

    -- ========================================================================
    -- Chip Enable Generation
    -- ========================================================================

    -- This logic is a faithful reconstruction of the original hardware's
    -- chip enable logic from original.vhd macrocells mc_E6 and the direct
    -- equation for N_SDOUT. These signals are active-low.

    -- FLASH_NCE is enabled when:
    --  - GP_NCS is active (low)
    --  - Not in DDR mode (config_map_reg is low)
    --  - SD card is not enabled OR GP_23 is low
    --  - clk3 is low (unusual dependency, but faithful to original)
    FLASH_NCE <= (GP_NCS or clk3 or config_map_reg) or (config_sd_enable and GP_23);

    -- N_SDOUT is enabled when:
    --  - GP_NCS is active (low)
    --  - SD card is enabled (config_sd_enable is high)
    --  - GP_23 is high
    --  - Not at the magic address
    sd_output_enable <= GP_NCS or not GP_23 or not config_sd_enable or magic_address;
    
    N_SDOUT <= sd_output_enable;
    -- ========================================================================
    -- Read/Write Enable Synchronization
    -- ========================================================================
    
    process(CLK50MHz)
    begin
        if rising_edge(CLK50MHz) then
            write_sync <= GP_NWR;
            read_sync  <= GP_NRD;
            
            -- Address load synchronization chain (equivalent to mc_H10 -> mc_H5 in original)
            address_load_sync <= address_load;
            address_load_sync2 <= address_load_sync;
            
            -- Timing synchronization stages (equivalent to mc_H14, mc_H15 in original)
            timing_sync4 <= GP_NWR and GP_NRD;
            timing_sync3 <= timing_sync4;
            
            -- Write enable synchronization (equivalent to mc_E3 in original)
            -- This creates a synchronized write enable signal that affects DDR operation
            -- mc_E3 <= GP_NWR or not WRITEENABLE in original code
            write_enable_sync <= GP_NWR or not config_write_enable;
        end if;
    end process;
    
    -- Use synchronized write enable for Flash/SRAM 
    -- The logic here should match the original's behavior
    FLASH_SRAM_NWE <= GP_NWR;
    FLASH_SRAM_NOE <= GP_NRD;

    -- ========================================================================
    -- GP Bus Output Control (Complete Implementation)
    -- ========================================================================
    
    gp_output_enable <= '1' when (GP_NRD = '0' and sd_output_enable = '0') else '0';
    
    -- GP Bus Data Multiplexing (equivalent to original mc_E8, mc_E10, etc.)
    process(GP_22, sd_cmd_toggle, SD_CMD, sd_dat_toggle, sd_cmd_state, sd_dat_state, 
            clk3, SD_DAT, sd_common_logic)
    begin
        -- Lower nibble: SD card data/toggle signals vs actual SD interface
        for i in 0 to 3 loop
            if GP_22 = '0' then
                case i is
                    when 0 => gp_output_data(i) <= sd_cmd_toggle;     -- GP(0)
                    when 1 => gp_output_data(i) <= sd_dat_toggle(1);  -- GP(1)
                    when 2 => gp_output_data(i) <= sd_dat_toggle(0);  -- GP(2)
                    when 3 => gp_output_data(i) <= sd_dat_toggle(3);  -- GP(3)
                end case;
            else
                case i is
                    when 0 => gp_output_data(i) <= SD_CMD;
                    when 1 => gp_output_data(i) <= sd_cmd_state;
                    when 2 => gp_output_data(i) <= sd_dat_state(1);
                    when 3 => gp_output_data(i) <= sd_dat_state(2);
                end case;
            end if;
        end loop;
        
        -- Middle nibble: more SD state vs toggle signals
        -- This logic is a faithful reconstruction of the original's multiplexing
        -- for the middle nibble of the GP bus.
        if GP_22 = '0' then
            -- When GP_22 is low, output various toggle/state signals
            gp_output_data(4) <= sd_dat_toggle(2);  -- Corresponds to mc_F14 in original
            gp_output_data(5) <= sd_common_logic;   -- Corresponds to mc_H9 in original
            gp_output_data(6) <= sd_cmd_state;      -- Corresponds to mc_E13 in original
            gp_output_data(7) <= sd_dat_state(0);   -- Corresponds to mc_H3 in original
        else
            -- When GP_22 is high, output a different mix of state signals
            gp_output_data(4) <= sd_dat_state(3);   -- Corresponds to mc_E2 in original
            gp_output_data(5) <= sd_dat_state(0);   -- Corresponds to mc_H3 in original
            gp_output_data(6) <= sd_common_logic;   -- Corresponds to mc_H9 in original
            gp_output_data(7) <= sd_dat_state(3);   -- Corresponds to mc_E2 in original
        end if;
        
        -- Upper byte: mix of SD DAT lines, constants, and toggle signals
        gp_output_data(8)  <= SD_DAT(0) when GP_22 = '0' else clk3;
        gp_output_data(9)  <= SD_DAT(1) when GP_22 = '0' else '0';
        gp_output_data(10) <= '1' when GP_22 = '0' else SD_DAT(2);
        gp_output_data(11) <= '1' when GP_22 = '0' else SD_DAT(3);
        
        -- Top nibble: constants vs toggle signals
        gp_output_data(12) <= '1' when GP_22 = '0' else sd_dat_toggle(2);
        gp_output_data(13) <= '1' when GP_22 = '0' else sd_dat_toggle(3);
        gp_output_data(14) <= '1' when GP_22 = '0' else sd_dat_toggle(0);
        gp_output_data(15) <= '1' when GP_22 = '0' else sd_dat_toggle(1);
    end process;
    
    -- GP bus tri-state control
    GP <= gp_output_data when gp_output_enable = '1' else (others => 'Z');

    -- ========================================================================
    -- SD Card Interface (Complete Implementation)
    -- ========================================================================
    
    -- Helper function for SD state logic (reduces repetition)
    function sd_state_logic(gp22, gp_data, gp19, addr_sync2, addr_sync, timing3, timing4 : std_logic;
                           current_state, toggle_state : std_logic) return std_logic is
    begin
        return ((not gp22 or current_state or addr_sync2 or timing3 or not timing4) and
                (gp22 or toggle_state or addr_sync2 or timing3 or not timing4) and
                (gp_data or gp19 or not addr_sync2 or addr_sync) and
                (not gp19 or current_state or not addr_sync2) and
                (current_state or addr_sync2 or timing4) and
                (current_state or addr_sync2 or not timing3));
    end function;
    
    -- SD Card State Machine (equivalent to original GLB E/F logic)
    process(GP_NCS)
    begin
        if rising_edge(GP_NCS) then
            -- Update all SD DAT states using the helper function
            sd_dat_state(2) <= sd_state_logic(GP_22, GP(2), GP_19, address_load_sync2, address_load_sync,
                                             timing_sync3, timing_sync4, sd_dat_state(1), sd_dat_toggle(0));
            sd_dat_state(3) <= sd_state_logic(GP_22, GP(3), GP_19, address_load_sync2, address_load_sync,
                                             timing_sync3, timing_sync4, sd_dat_state(2), sd_dat_toggle(3));
            sd_dat_state(1) <= sd_state_logic(GP_22, GP(1), GP_19, address_load_sync2, address_load_sync,
                                             timing_sync3, timing_sync4, sd_cmd_state, sd_dat_toggle(1));
            sd_dat_state(0) <= sd_state_logic(GP_22, GP(4), GP_19, address_load_sync2, address_load_sync,
                                             timing_sync3, timing_sync4, sd_dat_state(3), sd_cmd_state);
            
            -- SD CMD State (special case with SD_CMD input)
            sd_cmd_state <= (sd_cmd_state or address_load_sync2 or not timing_sync3) and
                           (GP_22 or sd_cmd_toggle or address_load_sync2 or timing_sync3 or not timing_sync4) and
                           (GP(0) or GP_19 or not address_load_sync2 or address_load_sync) and
                           (not GP_22 or SD_CMD or address_load_sync2 or timing_sync3 or not timing_sync4) and
                           (not GP_19 or sd_cmd_state or not address_load_sync2) and
                           (sd_cmd_state or address_load_sync2 or timing_sync4);
            
            -- SD Common Logic (for shared outputs)
            sd_common_logic <= (GP_22 or sd_dat_state(3) or address_load_sync2 or timing_sync3 or not timing_sync4) and
                              (not GP_22 or address_load_sync2 or sd_dat_state(2) or timing_sync3 or not timing_sync4) and
                              (GP(7) or GP_19 or not address_load_sync2 or address_load_sync) and
                              (not GP_19 or not address_load_sync2 or sd_common_logic) and
                              (address_load_sync2 or sd_common_logic or timing_sync4) and
                              (address_load_sync2 or sd_common_logic or not timing_sync3);
        end if;
    end process;
    
    -- SD Card Toggle Logic (simplified with generate loop)
    process(GP_NCS)
        constant GP_BITS : std_logic_vector(3 downto 0) := GP(10) & GP(11) & GP(8) & GP(9);
        constant SD_BITS : std_logic_vector(3 downto 0) := SD_DAT(2) & SD_DAT(3) & SD_DAT(0) & SD_DAT(1);
        variable term1, term2 : std_logic;
    begin
        if rising_edge(GP_NCS) then
            -- Generate toggle logic for all 4 DAT lines
            for i in 0 to 3 loop
                -- This logic implements a T-FlipFlop based on the original design's equations.
                -- T = term1 XOR term2
                -- Q(n+1) = T XOR Q(n)
                term1 := (not GP_19 and not GP_BITS(i) and address_load_sync2 and not address_load_sync);
                term2 := ((not GP_19 and not sd_dat_toggle(i) and address_load_sync2) or
                       (not GP_22 and SD_BITS(i) and not sd_dat_toggle(i) and not address_load_sync2 and not timing_sync3 and timing_sync4) or
                       (not GP_22 and not SD_BITS(i) and sd_dat_toggle(i) and not address_load_sync2 and not timing_sync3 and timing_sync4));
                sd_dat_toggle(i) <= (term1 xor term2) xor sd_dat_toggle(i);
            end loop;
            
            -- CMD Toggle (special case)
            term1 := (not GP_19 and not GP(12) and address_load_sync2 and not address_load_sync);
            term2 := ((not GP_19 and not sd_cmd_toggle and address_load_sync2) or
                   (not GP_22 and not sd_cmd_toggle and sd_dat_toggle(2) and not address_load_sync2 and not timing_sync3 and timing_sync4) or
                   (not GP_22 and sd_cmd_toggle and not sd_dat_toggle(2) and not address_load_sync2 and not timing_sync3 and timing_sync4));
            sd_cmd_toggle <= (term1 xor term2) xor sd_cmd_toggle;
        end if;
    end process;
    
    -- SD Interface Outputs (simplified)
    SD_CLK <= (GP_NWR and GP_NRD) or sd_output_enable;
    sd_cmd_out <= sd_common_logic;
    sd_data_out <= sd_dat_state(0) & sd_dat_state(1) & sd_dat_state(2) & sd_common_logic;
    
    -- Output enable logic
    sd_cmd_oe <= not GP_NWR and GP_22 and not sd_output_enable;
    sd_data_oe <= (others => (not GP_NWR and not GP_22 and not sd_output_enable));
    
    -- Tri-state control
    SD_CMD <= sd_cmd_out when sd_cmd_oe = '1' else 'Z';
    gen_sd_dat: for i in 0 to 3 generate
        SD_DAT(i) <= sd_data_out(i) when sd_data_oe(i) = '1' else 'Z';
    end generate;

end behavioral;
