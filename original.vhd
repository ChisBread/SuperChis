library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity top is
    port (
        -- Global Clocks and Control
        CLK50MHz : in  std_logic;
        GP_NCS   : in  std_logic;
        GP_NWR   : in  std_logic;
        GP_NRD   : in  std_logic;
        clk3     : in  std_logic;

        -- General Purpose IO (from GBA cart edge)
        GP       : inout std_logic_vector(15 downto 0);
        GP_16    : in  std_logic;
        GP_17    : in  std_logic;
        GP_18    : in  std_logic;
        GP_19    : in  std_logic;
        GP_20    : in  std_logic;
        GP_21    : in  std_logic;
        GP_22    : in  std_logic;
        GP_23    : in  std_logic;

        -- DDR SDRAM Interface
        DDR_A    : out std_logic_vector(12 downto 0);
        DDR_BA   : out std_logic_vector(1 downto 0);
        DDR_CKE  : out std_logic;
        DDR_NRAS : out std_logic;
        DDR_NCAS : out std_logic;
        DDR_NWE  : out std_logic;

        -- Flash/SRAM Interface
        FLASH_A          : out std_logic_vector(15 downto 0);
        FLASH_NCE        : out std_logic;
        FLASH_SRAM_NWE   : out std_logic;
        FLASH_SRAM_NOE   : out std_logic;
        SRAM_A16         : out std_logic;

        -- SD Card Interface
        N_SDOUT : out std_logic;
        SD_CLK  : out std_logic;
        SD_CMD  : inout std_logic;
        SD_DAT  : inout std_logic_vector(3 downto 0)
    );
end entity top;

-- 架构主体
architecture behavioral of top is

    -- Internal Macrocell signals (CPLD内部宏单元信号)
    signal mc_A0, mc_A1, mc_A2, mc_A4, mc_A5, mc_A6, mc_A8, mc_A14, mc_A15 : std_logic;
    signal mc_B0, mc_B1, mc_B2, mc_B3, mc_B4, mc_B5, mc_B6, mc_B8, mc_B9, mc_B10, mc_B13, mc_B14, mc_B15 : std_logic;
    signal mc_C0, mc_C1, mc_C6, mc_C8, mc_C9, mc_C10, mc_C13, mc_C14, mc_C15 : std_logic;
    signal mc_D0, mc_D1, mc_D2, mc_D9, mc_D10 : std_logic;
    signal mc_E0, mc_E2, mc_E3, mc_E6, mc_E7, mc_E8, mc_E9, mc_E10, mc_E11, mc_E12, mc_E13, mc_E14, mc_E15 : std_logic;
    signal mc_F0, mc_F1, mc_F2, mc_F3, mc_F4, mc_F5, mc_F6, mc_F7, mc_F8, mc_F9, mc_F10, mc_F11, mc_F12, mc_F13, mc_F14, mc_F15 : std_logic;
    signal mc_G1, mc_G2, mc_G4, mc_G6, mc_G10, mc_G12, mc_G14 : std_logic;
    signal mc_H0, mc_H1, mc_H2, mc_H3, mc_H4, mc_H5, mc_H6, mc_H7, mc_H8, mc_H9, mc_H10, mc_H11, mc_H13, mc_H14, mc_H15 : std_logic;

    --
    -- ============================================================================
    -- MACROCELL SIGNAL ALIASES AND FUNCTIONALITY DESCRIPTION
    -- ============================================================================
    --
    -- | GLB | Signal | Alias                    | Function Description
    -- |-----|--------|--------------------------|--------------------------------------------------
    -- | A   | mc_A0  | ddr_addr_bit2           | DDR SDRAM Address bit 2 (T FF)
    -- | A   | mc_A1  | ddr_addr_bit7           | DDR SDRAM Address bit 7 (T FF)  
    -- | A   | mc_A2  | ddr_addr_bit5           | DDR SDRAM Address bit 5 (D FF)
    -- | A   | mc_A4  | ddr_addr_bit1           | DDR SDRAM Address bit 1 (T FF)
    -- | A   | mc_A5  | ddr_state_ctrl          | DDR State Machine Control (D FF)
    -- | A   | mc_A6  | ddr_addr_bit6           | DDR SDRAM Address bit 6 (T FF)
    -- | A   | mc_A8  | ddr_addr_bit0           | DDR SDRAM Address bit 0 (T FF)
    -- | A   | mc_A14 | ddr_addr_bit10          | DDR SDRAM Address bit 10 (T FF)
    -- | A   | mc_A15 | ddr_addr_bit8           | DDR SDRAM Address bit 8 (T FF)
    -- |-----|--------|--------------------------|--------------------------------------------------
    -- | B   | mc_B0  | ddr_bank1               | DDR Bank Address bit 1 (D FF)
    -- | B   | mc_B1  | ddr_addr_bit9           | DDR SDRAM Address bit 9 (D FF)
    -- | B   | mc_B2  | ddr_bank0               | DDR Bank Address bit 0 (D FF) 
    -- | B   | mc_B3  | ddr_addr_bit11          | DDR SDRAM Address bit 11 (D FF)
    -- | B   | mc_B4  | ddr_cke                 | DDR Clock Enable signal (D FF)
    -- | B   | mc_B5  | ddr_cmd_active          | DDR Command Active state (D FF with XOR)
    -- | B   | mc_B6  | ddr_timing_ctrl         | DDR Timing Control state (D FF)
    -- | B   | mc_B8  | unlock_sequence         | Magic Unlock Sequence Detector (Combo)
    -- | B   | mc_B9  | ddr_cmd_state           | DDR Command State Machine (D FF)
    -- | B   | mc_B10 | ddr_write_ctrl          | DDR Write Control (D FF, inverted)
    -- | B   | mc_B13 | ddr_row_active          | DDR Row Active Signal (D FF)
    -- | B   | mc_B14 | ddr_col_active          | DDR Column Active Signal (D FF)
    -- | B   | mc_B15 | mode_selector           | Configuration Mode Selector (D FF)
    -- |-----|--------|--------------------------|--------------------------------------------------
    -- | C   | mc_C0  | flash_addr_bit12        | Flash/SRAM Address bit 12 -> DDR_A(12) (D FF)
    -- | C   | mc_C1  | flash_addr_bit1_ctrl    | Flash Address bit 1 Control (Combo)
    -- | C   | mc_C6  | flash_addr_bit14_ctrl   | Flash Address bit 14 Control (Combo)
    -- | C   | mc_C8  | flash_addr_bit6_ctrl    | Flash Address bit 6 Control (Combo)
    -- | C   | mc_C9  | flash_addr_mode         | Flash Address Mode Control (D FF)
    -- | C   | mc_C10 | flash_banking_ctrl      | Flash Banking Control (D FF)
    -- | C   | mc_C13 | magic_unlock_ctrl       | Magic Address Unlock Control (D FF)
    -- | C   | mc_C14 | flash_addr_always_high  | Flash Address Always High (Tied to '1')
    -- | C   | mc_C15 | flash_addr_bit3_ctrl    | Flash Address bit 3 Control (Combo)
    -- |-----|--------|--------------------------|--------------------------------------------------
    -- | D   | mc_D0  | flash_addr_bit15_ctrl   | Flash Address bit 15 Control (Combo)
    -- | D   | mc_D1  | flash_addr_bit7_ctrl    | Flash Address bit 7 Control (Combo)
    -- | D   | mc_D2  | flash_addr_bit11_ctrl   | Flash Address bit 11 Control (Combo)
    -- | D   | mc_D9  | flash_banking_mode      | Flash Banking Mode Control (D FF)
    -- | D   | mc_D10 | flash_addr_low_always   | Flash Address Always Low (Tied to '0')
    -- |-----|--------|--------------------------|--------------------------------------------------
    -- | E   | mc_E0  | sd_dat2_state           | SD Card DAT2 State Logic (D FF)
    -- | E   | mc_E2  | sd_dat3_state           | SD Card DAT3 State Logic (D FF)
    -- | E   | mc_E3  | write_enable_sync       | Write Enable Synchronizer (D FF)
    -- | E   | mc_E6  | flash_chip_enable       | Flash Chip Enable Control (Combo)
    -- | E   | mc_E7  | flash_addr_bit9_gated   | Flash Address bit 9 Gated (Combo)
    -- | E   | mc_E8  | gp_bus_data0            | GP Bus Data bit 0 Multiplexer (Combo)
    -- | E   | mc_E9  | flash_write_enable      | Flash Write Enable (Direct GP_NWR)
    -- | E   | mc_E10 | gp_bus_data1            | GP Bus Data bit 1 Multiplexer (Combo)
    -- | E   | mc_E11 | flash_read_enable       | Flash Read Enable (Direct GP_NRD)
    -- | E   | mc_E12 | gp_bus_data2            | GP Bus Data bit 2 Multiplexer (Combo)
    -- | E   | mc_E13 | sd_cmd_state            | SD Card CMD State Logic (D FF)
    -- | E   | mc_E14 | gp_bus_data3            | GP Bus Data bit 3 Multiplexer (Combo)
    -- | E   | mc_E15 | sd_dat11_state          | SD Card DAT Toggle State (T FF)
    -- |-----|--------|--------------------------|--------------------------------------------------
    -- | F   | mc_F0  | sd_dat2_toggle          | SD Card DAT2 Toggle Logic (T FF)
    -- | F   | mc_F1  | sd_dat3_toggle          | SD Card DAT3 Toggle Logic (T FF)
    -- | F   | mc_F2  | gp_bus_mux4             | GP Bus bit 4 Data Multiplexer (Combo)
    -- | F   | mc_F3  | gp_bus_mux5             | GP Bus bit 5 Data Multiplexer (Combo)
    -- | F   | mc_F4  | gp_bus_mux6             | GP Bus bit 6 Data Multiplexer (Combo)
    -- | F   | mc_F5  | sd_dat1_state           | SD Card DAT1 State Logic (D FF)
    -- | F   | mc_F6  | gp_bus_mux7             | GP Bus bit 7 Data Multiplexer (Combo)
    -- | F   | mc_F7  | sd_cmd_toggle           | SD Card CMD Toggle Logic (T FF)
    -- | F   | mc_F8  | gp_bus_mux8             | GP Bus bit 8 Data Multiplexer (Combo)
    -- | F   | mc_F9  | sd_dat1_toggle          | SD Card DAT1 Toggle Logic (T FF)
    -- | F   | mc_F10 | gp_bus_mux9             | GP Bus bit 9 Data Multiplexer (Combo)
    -- | F   | mc_F11 | sd_dat0_toggle          | SD Card DAT0 Toggle Logic (T FF)
    -- | F   | mc_F12 | gp_bus_mux10            | GP Bus bit 10 Data Multiplexer (Combo)
    -- | F   | mc_F13 | gp_bus_mux11            | GP Bus bit 11 Data Multiplexer (Combo)
    -- | F   | mc_F14 | sd_dat0_toggle_f14      | SD Card DAT0 Toggle F14 Logic (T FF)
    -- | F   | mc_F15 | sd_dat1_toggle_f15      | SD Card DAT1 Toggle F15 Logic (T FF)
    -- |-----|--------|--------------------------|--------------------------------------------------
    -- | G   | mc_G1  | unlock_pattern1         | Unlock Pattern 1 Detector (D FF)
    -- | G   | mc_G2  | unlock_pattern2         | Unlock Pattern 2 Detector (D FF)
    -- | G   | mc_G4  | gp_bus_mux12            | GP Bus bit 12 Data Multiplexer (Combo)
    -- | G   | mc_G6  | gp_bus_mux15            | GP Bus bit 15 Data Multiplexer (Combo)
    -- | G   | mc_G10 | gp_bus_mux14            | GP Bus bit 14 Data Multiplexer (Combo)
    -- | G   | mc_G12 | gp_bus_mux13            | GP Bus bit 13 Data Multiplexer (Combo)
    -- | G   | mc_G14 | bank_select_ctrl        | Bank Select Control Register (D FF)
    -- |-----|--------|--------------------------|--------------------------------------------------
    -- | H   | mc_H0  | read_enable_sync        | Read Enable Synchronizer (D FF)
    -- | H   | mc_H1  | sd_clock_gen            | SD Card Clock Generator (Combo)
    -- | H   | mc_H2  | flash_addr_bit4         | Flash/DDR Address bit 4 Control (D FF)
    -- | H   | mc_H3  | sd_dat0_out             | SD Card DAT0 Output Logic (D FF)
    -- | H   | mc_H4  | flash_addr_bit3         | Flash/DDR Address bit 3 Control (T FF)
    -- | H   | mc_H5  | timing_sync1            | Timing Synchronization Stage 1 (D FF)
    -- | H   | mc_H6  | sd_dat3_out             | SD Card DAT3 Output (= mc_H9)
    -- | H   | mc_H7  | sd_dat2_out             | SD Card DAT2 Output Logic (D FF)
    -- | H   | mc_H8  | sd_cmd_out              | SD Card CMD Output (= mc_H9)
    -- | H   | mc_H9  | sd_dat_cmd_common       | SD Card DAT/CMD Common Logic (D FF)
    -- | H   | mc_H10 | timing_sync2            | Timing Synchronization Stage 2 (D FF)
    -- | H   | mc_H11 | iaddr_clock_gen         | Internal Address Counter Clock (Combo)
    -- | H   | mc_H13 | sd_dat1_out             | SD Card DAT1 Output Logic (D FF)
    -- | H   | mc_H14 | timing_sync3            | Timing Synchronization Stage 3 (D FF)
    -- | H   | mc_H15 | timing_sync4            | Timing Synchronization Stage 4 (D FF)
    -- ============================================================================
    --
    -- GLB Functionality Summary:
    -- - GLB A: DDR SDRAM Address Generation and State Control
    -- - GLB B: DDR SDRAM Command and Control Signal Generation  
    -- - GLB C: Flash/SRAM Address Control and Magic Unlock Logic
    -- - GLB D: Flash/SRAM Address Bus Generation
    -- - GLB E: SD Card Control and GP Bus Data Multiplexing
    -- - GLB F: SD Card Data Toggle Logic and GP Bus Output Control
    -- - GLB G: Internal Counter Control and Pattern Detection
    -- - GLB H: SD Card Interface and Clock/Timing Generation
    --

    -- Internal counter and register signals (内部计数器和寄存器信号) - Refactored to vectors
    signal ddrcnt      : unsigned(3 downto 0); -- DDR地址计数器
    signal icntr       : unsigned(8 downto 0); -- 内部状态机计数器
    signal iaddr       : unsigned(15 downto 0); -- 内部地址总线寄存器
    signal SDENABLE    : std_logic; -- SD卡功能使能
    signal MAP_REG     : std_logic; -- 模式映射寄存器 (DDR/SRAM)
    signal MAGICADDR   : std_logic; -- 特殊地址匹配标志
    signal LOAD_IREG   : std_logic; -- 内部寄存器加载信号
    signal N_DDR_SEL   : std_logic; -- DDR SDRAM 片选信号 (低有效)
    signal WRITEENABLE : std_logic; -- 写使能
    signal addr_load   : std_logic; -- 地址加载信号

begin

    -- GLB 0 (A) - DDR地址生成逻辑
    process(GP_NCS)
    begin
        if rising_edge(GP_NCS) then
            -- mc_A0: T FF
            mc_A0 <= ((mc_A0 and mc_A5 and not mc_B6 and not mc_B9)
                or (not mc_A5 and not mc_B5 and not mc_B6 and mc_B9 and iaddr(11))
                or (not mc_A5 and not mc_B5 and mc_B6 and mc_B9 and iaddr(2))
                ) xor (mc_A0 and not mc_A5 and not mc_B5 and mc_B9) xor mc_A0;
            -- mc_A1: T FF
            mc_A1 <= ((mc_A1 and mc_A5 and not mc_B6 and not mc_B9)
                or (GP_16 and not mc_A5 and not mc_B5 and not mc_B6 and mc_B9)
                or (not mc_A5 and not mc_B5 and mc_B6 and mc_B9 and iaddr(7))
                ) xor (mc_A1 and not mc_A5 and not mc_B5 and mc_B9) xor mc_A1;
            -- mc_A2: D FF
            mc_A2 <= (mc_A2 and mc_A5 and mc_B6)
                or (not mc_A5 and not mc_B5 and not mc_B6 and mc_B9 and iaddr(14))
                or (not mc_A5 and not mc_B5 and mc_B6 and mc_B9 and iaddr(5))
                or (mc_A5 and mc_B5 and not mc_B6 and not mc_B9)
                or (mc_A2 and not mc_A5 and not mc_B9)
                or (mc_A2 and mc_B5)
                or (mc_A2 and mc_A5 and mc_B9);
            -- ddrcnt: 4-bit counter
            if (not mc_A5 and mc_B5 and not mc_B6 and not mc_B9) = '1' then
                ddrcnt <= ddrcnt + 1;
            end if;
            -- mc_A4: T FF
            mc_A4 <= ((mc_A4 and mc_A5 and not mc_B6 and not mc_B9)
                or (not mc_A5 and not mc_B5 and not mc_B6 and mc_B9 and not iaddr(10))
                or (not mc_A5 and not mc_B5 and mc_B6 and mc_B9 and not iaddr(1))
                ) xor (not mc_A4 and not mc_A5 and not mc_B5 and mc_B9) xor mc_A4;
            -- mc_A5: D FF
            mc_A5 <= (mc_B5 and not mc_B6 and mc_B9 and not icntr(8))
                or (mc_B5 and not mc_B6 and mc_B9 and not icntr(7))
                or (not ddrcnt(1) and not mc_A5 and not ddrcnt(0) and not ddrcnt(2) and not ddrcnt(3) and mc_B5 and mc_B6 and icntr(8) and icntr(7))
                or (mc_B6 and mc_B9 and N_DDR_SEL)
                or (not mc_A5 and mc_B5 and mc_B6 and mc_B9)
                or (mc_A5 and not mc_B6)
                or (mc_A5 and not mc_B5)
                or (mc_A5 and N_DDR_SEL);
            -- mc_A6: T FF
            mc_A6 <= ((mc_A5 and mc_A6 and not mc_B6 and not mc_B9)
                or (not mc_A5 and not mc_B5 and not mc_B6 and mc_B9 and iaddr(15))
                or (not mc_A5 and not mc_B5 and mc_B6 and mc_B9 and iaddr(6))
                ) xor (not mc_A5 and mc_A6 and not mc_B5 and mc_B9) xor mc_A6;
            -- mc_A8: T FF
            mc_A8 <= ((mc_A5 and mc_A8 and not mc_B6 and not mc_B9)
                or (not mc_A5 and not mc_B5 and not mc_B6 and mc_B9 and iaddr(9))
                or (not mc_A5 and not mc_B5 and mc_B6 and mc_B9 and iaddr(0))
                ) xor (not mc_A5 and mc_A8 and not mc_B5 and mc_B9) xor mc_A8;
            -- icntr(6..0): 7-bit synchronous counter
            icntr(6 downto 0) <= icntr(6 downto 0) + 1;
            -- icntr 7,8 have async reset, handled in another process
            
            -- mc_A14: T FF
            mc_A14 <= ((not GP(19) and not mc_A5 and not mc_B5 and not mc_B6 and mc_B9)
                or (mc_A5 and not mc_A14 and not mc_B5 and not mc_B6 and not mc_B9)
                or (mc_A5 and mc_A14 and mc_B5 and not mc_B6 and not mc_B9)
                ) xor (not mc_A5 and not mc_A14 and not mc_B5 and mc_B9) xor mc_A14;
            -- mc_A15: T FF
            mc_A15 <= ((mc_A5 and mc_A15 and not mc_B6 and not mc_B9)
                or (not mc_A5 and not mc_B5 and mc_B6 and mc_B9 and not iaddr(8))
                or (not GP_17 and not mc_A5 and not mc_B5 and not mc_B6 and mc_B9)
                ) xor (not mc_A5 and not mc_A15 and not mc_B5 and mc_B9) xor mc_A15;
        end if;
    end process;
    DDR_A(2) <= mc_A0;
    DDR_A(5) <= mc_A2;
    DDR_A(1) <= mc_A4;
    DDR_A(6) <= mc_A6;
    DDR_A(0) <= mc_A8;
    DDR_A(7) <= mc_A1;
    DDR_A(10) <= mc_A14;
    DDR_A(8) <= mc_A15;

    -- GLB 1 (B) - DDR控制信号生成逻辑
    process(GP_NCS)
    begin
        if rising_edge(GP_NCS) then
            -- mc_B0: D FF
            mc_B0 <= (mc_B0 and mc_B5 and mc_B9)
                or (mc_B0 and mc_B6 and not mc_B9)
                or (GP_23 and not mc_A5 and not mc_B5 and mc_B9)
                or (not mc_A5 and mc_B0 and not mc_B9)
                or (mc_A5 and mc_B0 and mc_B9);
            -- mc_B1: D FF
            mc_B1 <= (mc_B1 and mc_B5 and mc_B9)
                or (mc_B1 and mc_B6 and not mc_B9)
                or (GP_18 and not mc_A5 and not mc_B5 and not mc_B6 and mc_B9)
                or (not mc_A5 and mc_B1 and not mc_B9)
                or (mc_A5 and mc_B1 and mc_B9);
            -- mc_B2: D FF
            mc_B2 <= (mc_B2 and mc_B5 and mc_B9)
                or (mc_B2 and mc_B6 and not mc_B9)
                or (GP_22 and not mc_A5 and not mc_B5 and mc_B9)
                or (not mc_A5 and mc_B2 and not mc_B9)
                or (mc_A5 and mc_B2 and mc_B9);
            -- mc_B3: D FF
            mc_B3 <= (mc_B3 and mc_B5 and mc_B9)
                or (mc_B3 and mc_B6 and not mc_B9)
                or (GP_20 and not mc_A5 and not mc_B5 and not mc_B6 and mc_B9)
                or (not mc_A5 and mc_B3 and not mc_B9)
                or (mc_A5 and mc_B3 and mc_B9);
            -- mc_B4: D FF, simplified from (A|B)&(A|C) to A|(B&C)
            mc_B4 <= not((not mc_A5 or not mc_B5 or not mc_B6 or not N_DDR_SEL) or (icntr(8) and icntr(7)));
            -- mc_B5: D FF (with XOR)
            mc_B5 <= ((not mc_A5 and not mc_B9 and icntr(8) and icntr(7))
                or (mc_A5 and not mc_B5 and not mc_B6 and mc_B9 and mc_E3 and mc_H0)
                or (not mc_A5 and not mc_B5 and mc_B6 and mc_B9 and not N_DDR_SEL and not mc_H0)
                or (not mc_A5 and not mc_B5 and mc_B6 and mc_B9 and not mc_E3 and not N_DDR_SEL)
                or (not mc_A5 and mc_B5 and not mc_B9)
                or (not mc_A5 and mc_B5 and not mc_B6 and icntr(8) and icntr(7))
                or (mc_B5 and not mc_B6 and not mc_B9)
                or (mc_B5 and not mc_B9 and not N_DDR_SEL)
                or (mc_B5 and not mc_B9 and icntr(8) and icntr(7))
                ) xor (mc_A5 and mc_B6);
            -- mc_B6: D FF
            mc_B6 <= (not mc_B5 and not mc_B6 and mc_E3 and mc_H0)
                or (not mc_A5 and not mc_B6 and icntr(8) and icntr(7))
                or (mc_A5 and mc_B6 and not mc_B9 and N_DDR_SEL)
                or (not mc_A5 and not mc_B5 and mc_B9 and mc_E3 and not N_DDR_SEL and mc_H0)
                or (mc_A5 and mc_B5 and mc_B9)
                or (not mc_A5 and not mc_B9 and not icntr(8))
                or (not mc_A5 and not mc_B5 and not mc_B6)
                or (mc_A5 and not mc_B5 and not mc_B9)
                or (not mc_A5 and not mc_B9 and not icntr(7));
            -- mc_B9: D FF
            mc_B9 <= not ((not mc_A5 or mc_B5 or mc_B6 or not mc_E3 or not mc_H0)
                and (not mc_B6 or mc_B9 or not N_DDR_SEL or icntr(8))
                and (not mc_B6 or mc_B9 or not N_DDR_SEL or icntr(7))
                and (mc_A5 or mc_B5 or not mc_B6 or not N_DDR_SEL)
                and (not mc_A5 or not mc_B5 or not mc_B9)
                and (mc_A5 or mc_B9)
                and (mc_B5 or mc_B9));
            -- mc_B10: D FF
            mc_B10 <= not ((mc_A5 or mc_B5 or not mc_B6 or not mc_B9 or mc_E3)
                and (not mc_A5 or mc_B6 or mc_B9));
            -- mc_B13: D FF
            mc_B13 <= (mc_B5 and not mc_B6 and mc_B9)
                or (mc_A5 and not mc_B6 and mc_B9)
                or (not mc_A5 and not mc_B5 and mc_B6)
                or (mc_B6 and not mc_B9);
            -- mc_B14: D FF
            mc_B14 <= (mc_A5 and mc_B5 and mc_B9 and N_DDR_SEL and not icntr(8))
                or (mc_A5 and mc_B5 and mc_B9 and N_DDR_SEL and not icntr(7))
                or (not mc_B5 and not mc_B9)
                or (not mc_A5 and not mc_B5 and mc_E3 and mc_H0)
                or (mc_B6 and not mc_B9)
                or (not mc_B6 and mc_B9);
        end if;
    end process;
    DDR_BA(1) <= mc_B0;
    DDR_BA(0) <= mc_B2;
    DDR_CKE <= mc_B4;
    DDR_NRAS <= mc_B13;
    DDR_NCAS <= mc_B14;
    DDR_NWE <= mc_B10;
    DDR_A(9) <= mc_B1;
    DDR_A(11) <= mc_B3;

    -- 组合逻辑，用于检测所有地址和控制信号是否处于特定状态 (可能用于模式解锁)
    mc_B8 <= GP_16 and GP_17 and GP(0) and GP(1) and GP(2) and GP(3) and GP(5) and GP(10) and GP(11) and GP_18 and GP_22 and GP_21 and GP_20 and GP(19) and GP(15) and GP(13) and GP(12) and GP_23;

    -- 寄存器加载过程，在GP_NWR上升沿触发
    process(GP_NWR)
    begin
        if rising_edge(GP_NWR) then
            if LOAD_IREG = '1' then
                SDENABLE <= GP(1);
                MAP_REG <= GP(0);
                mc_B15 <= GP(6) and not GP(13) and GP(12);
            end if;
        end if;
    end process;

    -- GLB 2 (C) - Flash/SRAM地址和控制逻辑
    process(GP_NCS)
    begin
        if rising_edge(GP_NCS) then
            -- mc_C0: D FF
            mc_C0 <= (mc_B5 and mc_B9 and mc_C0)
                or (mc_B6 and not mc_B9 and mc_C0)
                or (GP_21 and not mc_A5 and not mc_B5 and not mc_B6 and mc_B9)
                or (not mc_A5 and not mc_B9 and mc_C0)
                or (mc_A5 and mc_B9 and mc_C0);
        end if;
    end process;
    DDR_A(12) <= mc_C0;

    mc_C1 <= mc_B15 or iaddr(1);
    FLASH_A(1) <= mc_C1;
    FLASH_A(5) <= iaddr(2);
    FLASH_A(2) <= iaddr(6);
    FLASH_A(4) <= iaddr(0);
    mc_C6 <= iaddr(14) or mc_G14;
    FLASH_A(14) <= mc_C6;
    mc_C8 <= mc_C9 or iaddr(8);
    FLASH_A(6) <= mc_C8;
    mc_C15 <= mc_B15 or iaddr(5) or mc_C9;
    FLASH_A(3) <= mc_C15;
    mc_C14 <= '1'; -- Tied high (硬编码为高电平)

    process(GP_NWR)
    begin
        if rising_edge(GP_NWR) then
            if LOAD_IREG = '1' then
                mc_C9 <= GP(4) and not GP(5) and GP(14);
                mc_C10 <= GP(4) and not GP(8) and GP(12);
            end if;
        end if;
    end process;

    -- 特殊功能控制寄存器，由CLK50MHz同步
    process(CLK50MHz)
    begin
        if rising_edge(CLK50MHz) then
            MAGICADDR <= GP(4) and GP(6) and GP(7) and GP(8) and GP(9) and GP(14) and mc_B8;
            LOAD_IREG <= GP(4) and GP(6) and GP(7) and GP(8) and GP(9) and GP(14) and mc_B8 and mc_G1;
            mc_C13 <= GP(4) and GP(6) and GP(7) and GP(8) and GP(9) and GP(14) and mc_B8 and mc_G2;
        end if;
    end process;

    -- GLB 3 (D) - Flash/SRAM地址总线逻辑
    mc_D0 <= mc_C10 or iaddr(15) or mc_D9 or mc_G14;
    FLASH_A(15) <= mc_D0;
    mc_D1 <= iaddr(4) or mc_C10;
    FLASH_A(7) <= mc_D1;
    mc_D2 <= iaddr(11) or mc_D9;
    FLASH_A(11) <= mc_D2;
    FLASH_A(8) <= iaddr(3);
    FLASH_A(13) <= iaddr(13);
    FLASH_A(12) <= iaddr(12);
    FLASH_A(0) <= iaddr(7);
    FLASH_A(10) <= iaddr(10);
    mc_D10 <= '0'; -- Tied low (硬编码为低电平)

    process(GP_NWR)
    begin
        if rising_edge(GP_NWR) then
            if LOAD_IREG = '1' then
                mc_D9 <= GP(7) and GP(9) and not GP(15);
            end if;
        end if;
    end process;

    -- GLB C & D Shared Clock Logic for iaddr counter (C和D逻辑块共享的内部地址计数器)
    -- 这个计数器在mc_H11的上升沿计数，用于生成Flash/SRAM的地址
    process(mc_H11)
    begin
        if rising_edge(mc_H11) then
            if addr_load = '1' then
                iaddr <= unsigned(GP);
            else
                iaddr <= iaddr + 1;
            end if;
        end if;
    end process;

    -- GLB 4 (E) - SD卡和Flash/SRAM控制逻辑
    process(GP_NCS)
    begin
        if rising_edge(GP_NCS) then
            -- mc_E0: D FF
            mc_E0 <= (not GP_22 or mc_F5 or mc_H5 or mc_H14 or not mc_H15)
                and (GP_22 or mc_F11 or mc_H5 or mc_H14 or not mc_H15)
                and (GP(2) or GP(19) or not mc_H5 or mc_H10)
                and (not GP(19) or mc_E0 or not mc_H5)
                and (mc_E0 or mc_H5 or mc_H15)
                and (mc_E0 or mc_H5 or not mc_H14);
            -- mc_E2: D FF
            mc_E2 <= (not GP_22 or mc_E0 or mc_H5 or mc_H14 or not mc_H15)
                and (GP_22 or mc_E15 or mc_H5 or mc_H14 or not mc_H15)
                and (GP(3) or GP(19) or not mc_H5 or mc_H10)
                and (not GP(19) or mc_E2 or not mc_H5)
                and (mc_E2 or mc_H5 or mc_H15)
                and (mc_E2 or mc_H5 or not mc_H14);
            -- mc_E13: D FF
            mc_E13 <= (mc_E13 or mc_H5 or not mc_H14)
                and (GP_22 or mc_F7 or mc_H5 or mc_H14 or not mc_H15)
                and (GP(0) or GP(19) or not mc_H5 or mc_H10)
                and (not GP_22 or SD_CMD or mc_H5 or mc_H14 or not mc_H15)
                and (not GP(19) or mc_E13 or not mc_H5)
                and (mc_E13 or mc_H5 or mc_H15);
            -- mc_E15: T FF
            mc_E15 <= ((not GP(19) and not mc_E15 and mc_H5)
                or (not GP_22 and not mc_E15 and mc_F1 and not mc_H5 and not mc_H14 and mc_H15)
                or (not GP_22 and mc_E15 and not mc_F1 and not mc_H5 and not mc_H14 and mc_H15)
                ) xor (not GP(19) and not GP(15) and mc_H5 and not mc_H10) xor mc_E15;
        end if;
    end process;
    FLASH_A(9) <= mc_E7;
    N_SDOUT <= GP_NCS or not GP_23 or not SDENABLE or MAGICADDR; -- SD卡输出使能（低有效）
    FLASH_NCE <= mc_E6; -- Flash芯片使能（低有效）
    -- Simplified from (A|B)&(A|C) to A|(B&C)
    mc_E6 <= (GP_NCS or clk3 or MAP_REG) or (SDENABLE and GP_23);
    FLASH_SRAM_NWE <= mc_E9; -- Flash/SRAM 写使能（低有效）
    mc_E9 <= GP_NWR;
    FLASH_SRAM_NOE <= mc_E11; -- Flash/SRAM 读使能（低有效）
    mc_E11 <= GP_NRD;
    mc_E7 <= iaddr(9) and WRITEENABLE;
    mc_E8 <= (not GP_22 and mc_F7) or (GP_22 and SD_CMD);
    mc_E10 <= (not GP_22 and mc_F9) or (GP_22 and mc_E13);
    mc_E12 <= (not GP_22 and mc_F11) or (GP_22 and mc_F5);
    mc_E14 <= (not GP_22 and mc_E15) or (GP_22 and mc_E0);

    process(CLK50MHz)
    begin
        if rising_edge(CLK50MHz) then
            mc_E3 <= GP_NWR or not WRITEENABLE;
            -- DDR选择信号生成, simplified from (A|B)&(A|C) to A|(B&C)
            N_DDR_SEL <= (GP_NCS or not MAP_REG) or (SDENABLE and GP_23);
        end if;
    end process;

    -- GLB 5 (F) - SD卡数据逻辑和GP总线输出逻辑
    process(GP_NCS)
    begin
        if rising_edge(GP_NCS) then
            -- mc_F0: T FF
            mc_F0 <= ((not GP(19) and not mc_F0 and mc_H5)
                or (not GP_22 and SD_DAT(2) and not mc_F0 and not mc_H5 and not mc_H14 and mc_H15)
                or (not GP_22 and not SD_DAT(2) and mc_F0 and not mc_H5 and not mc_H14 and mc_H15)
                ) xor (not GP(10) and not GP(19) and mc_H5 and not mc_H10) xor mc_F0;
            -- mc_F1: T FF
            mc_F1 <= ((not GP(19) and not mc_F1 and mc_H5)
                or (not GP_22 and SD_DAT(3) and not mc_F1 and not mc_H5 and not mc_H14 and mc_H15)
                or (not GP_22 and not SD_DAT(3) and mc_F1 and not mc_H5 and not mc_H14 and mc_H15)
                ) xor (not GP(11) and not GP(19) and mc_H5 and not mc_H10) xor mc_F1;
            -- mc_F5: D FF
            mc_F5 <= (not GP_22 or mc_E13 or mc_H5 or mc_H14 or not mc_H15)
                and (GP_22 or mc_F9 or mc_H5 or mc_H14 or not mc_H15)
                and (GP(1) or GP(19) or not mc_H5 or mc_H10)
                and (not GP(19) or mc_F5 or not mc_H5)
                and (mc_F5 or mc_H5 or mc_H15)
                and (mc_F5 or mc_H5 or not mc_H14);
            -- mc_F7: T FF
            mc_F7 <= ((not GP(19) and not mc_F7 and mc_H5)
                or (not GP_22 and not mc_F7 and mc_F14 and not mc_H5 and not mc_H14 and mc_H15)
                or (not GP_22 and mc_F7 and not mc_F14 and not mc_H5 and not mc_H14 and mc_H15)
                ) xor (not GP(19) and not GP(12) and mc_H5 and not mc_H10) xor mc_F7;
            -- mc_F9: T FF
            mc_F9 <= ((not GP(19) and not mc_F9 and mc_H5)
                or (not GP_22 and not mc_F9 and mc_F15 and not mc_H5 and not mc_H14 and mc_H15)
                or (not GP_22 and mc_F9 and not mc_F15 and not mc_H5 and not mc_H14 and mc_H15)
                ) xor (not GP(19) and not GP(13) and mc_H5 and not mc_H10) xor mc_F9;
            -- mc_F11: T FF
            mc_F11 <= ((not GP(19) and not mc_F11 and mc_H5)
                or (not GP_22 and mc_F0 and not mc_F11 and not mc_H5 and not mc_H14 and mc_H15)
                or (not GP_22 and not mc_F0 and mc_F11 and not mc_H5 and not mc_H14 and mc_H15)
                ) xor (not GP(19) and not GP(14) and mc_H5 and not mc_H10) xor mc_F11;
            -- mc_F14: T FF
            mc_F14 <= ((not GP(19) and not mc_F14 and mc_H5)
                or (not GP_22 and SD_DAT(0) and not mc_F14 and not mc_H5 and not mc_H14 and mc_H15)
                or (not GP_22 and not SD_DAT(0) and mc_F14 and not mc_H5 and not mc_H14 and mc_H15)
                ) xor (not GP(8) and not GP(19) and mc_H5 and not mc_H10) xor mc_F14;
            -- mc_F15: T FF
            mc_F15 <= ((not GP(19) and not mc_F15 and mc_H5)
                or (not GP_22 and SD_DAT(1) and not mc_F15 and not mc_H5 and not mc_H14 and mc_H15)
                or (not GP_22 and not SD_DAT(1) and mc_F15 and not mc_H5 and not mc_H14 and mc_H15)
                ) xor (not GP(9) and not GP(19) and mc_H5 and not mc_H10) xor mc_F15;
        end if;
    end process;
    mc_F2 <= (not GP_22 and mc_E13) or (GP_22 and mc_E2);
    mc_F3 <= (GP_22 and mc_H3) or (not GP_22 and mc_F5);
    mc_F4 <= (GP_22 and mc_H13) or (not GP_22 and mc_E0);
    mc_F6 <= (GP_22 and mc_H7) or (not GP_22 and mc_E2);
    mc_F8 <= (clk3 and GP_22) or (not GP_22 and SD_DAT(0));
    mc_F10 <= not GP_22 and SD_DAT(1);
    mc_F12 <= GP_22 or SD_DAT(2);
    mc_F13 <= GP_22 or SD_DAT(3);

    -- GLB 4/5 Shared OE for GP(0-15) (GP总线输出使能控制)
    -- 当GP_NRD和N_SDOUT都为低时，GP总线作为输出
    GP(0) <= mc_E8 when (not GP_NRD and not N_SDOUT) = '1' else 'Z';
    GP(1) <= mc_E10 when (not GP_NRD and not N_SDOUT) = '1' else 'Z';
    GP(2) <= mc_E12 when (not GP_NRD and not N_SDOUT) = '1' else 'Z';
    GP(3) <= mc_E14 when (not GP_NRD and not N_SDOUT) = '1' else 'Z';
    GP(4) <= mc_F2 when (not GP_NRD and not N_SDOUT) = '1' else 'Z';
    GP(5) <= mc_F3 when (not GP_NRD and not N_SDOUT) = '1' else 'Z';
    GP(6) <= mc_F4 when (not GP_NRD and not N_SDOUT) = '1' else 'Z';
    GP(7) <= mc_F6 when (not GP_NRD and not N_SDOUT) = '1' else 'Z';
    GP(8) <= mc_F8 when (not GP_NRD and not N_SDOUT) = '1' else 'Z';
    GP(9) <= mc_F10 when (not GP_NRD and not N_SDOUT) = '1' else 'Z';
    GP(10) <= mc_F12 when (not GP_NRD and not N_SDOUT) = '1' else 'Z';
    GP(11) <= mc_F13 when (not GP_NRD and not N_SDOUT) = '1' else 'Z';
    GP(12) <= mc_G4 when (not GP_NRD and not N_SDOUT) = '1' else 'Z';
    GP(13) <= mc_G12 when (not GP_NRD and not N_SDOUT) = '1' else 'Z';
    GP(14) <= mc_G10 when (not GP_NRD and not N_SDOUT) = '1' else 'Z';
    GP(15) <= mc_G6 when (not GP_NRD and not N_SDOUT) = '1' else 'Z';

    -- GLB 6 (G) - 内部计数器和控制逻辑
    -- Note: icntr(0-6) are handled in the GLB A process. This process is now empty.
    -- process(GP_NCS)
    -- begin
    --     if rising_edge(GP_NCS) then
    --     end if;
    -- end process;

    -- 内部计数器7和8，带异步复位逻辑
    process(GP_NCS, mc_B4, mc_B10, mc_B13, mc_B14)
    variable reset_icntr : std_logic;
    begin
        reset_icntr := mc_B4 and mc_B10 and not mc_B13 and not mc_B14;
        if reset_icntr = '1' then
            icntr(7) <= '0';
            icntr(8) <= '0';
        elsif rising_edge(GP_NCS) then
            -- icntr7: T FF with Async Reset
            icntr(7) <= (icntr(0) and icntr(1) and icntr(2) and icntr(3) and icntr(4) and icntr(5) and icntr(6)) xor icntr(7);
            -- icntr8: T FF with Async Reset
            icntr(8) <= (icntr(0) and icntr(1) and icntr(2) and icntr(3) and icntr(4) and icntr(5) and icntr(6) and icntr(7)) xor icntr(8);
        end if;
    end process;

    process(GP_NWR)
    begin
        if rising_edge(GP_NWR) then
            mc_G1 <= not GP(0) and GP(1) and not GP(2) and GP(3) and GP(4) and not GP(5) and GP(6) and not GP(7) and GP(8) and not GP(9) and GP(10) and not GP(11) and mc_C13;
            mc_G2 <= not GP(0) and GP(1) and not GP(2) and GP(3) and GP(4) and not GP(5) and GP(6) and not GP(7) and GP(8) and not GP(9) and GP(10) and not GP(11) and MAGICADDR;
            if LOAD_IREG = '1' then
                WRITEENABLE <= GP(2);
                mc_G14 <= GP(7) and not GP(10) and GP(11);
            end if;
        end if;
    end process;
    SRAM_A16 <= WRITEENABLE;

    mc_G4 <= GP_22 or mc_F14;
    mc_G6 <= GP_22 or mc_F1;
    mc_G10 <= GP_22 or mc_F0;
    mc_G12 <= GP_22 or mc_F15;

    -- GLB 7 (H) - SD卡接口和时钟生成逻辑
    process(GP_NCS)
    begin
        if rising_edge(GP_NCS) then
            -- mc_H2: D FF
            mc_H2 <= (mc_A5 and mc_B6 and mc_H2)
                or (not mc_A5 and not mc_B5 and not mc_B6 and mc_B9 and iaddr(13))
                or (not mc_A5 and not mc_B5 and mc_B6 and mc_B9 and iaddr(4))
                or (mc_A5 and mc_B5 and not mc_B6 and not mc_B9)
                or (not mc_A5 and not mc_B9 and mc_H2)
                or (mc_B5 and mc_H2)
                or (mc_A5 and mc_B9 and mc_H2);
            -- mc_H3: D FF
            mc_H3 <= (not GP_22 or mc_E2 or mc_H5 or mc_H14 or not mc_H15)
                and (GP_22 or mc_E13 or mc_H5 or mc_H14 or not mc_H15)
                and (GP(4) or GP(19) or not mc_H5 or mc_H10)
                and (not GP(19) or mc_H3 or not mc_H5)
                and (mc_H3 or mc_H5 or mc_H15)
                and (mc_H3 or mc_H5 or not mc_H14);
            -- mc_H4: T FF
            mc_H4 <= ((mc_A5 and not mc_B6 and not mc_B9 and mc_H4)
                or (not mc_A5 and not mc_B5 and mc_B6 and mc_B9 and iaddr(3))
                or (not mc_A5 and not mc_B5 and not mc_B6 and mc_B9 and iaddr(12))
                ) xor (not mc_A5 and not mc_B5 and mc_B9 and mc_H4) xor mc_H4;
            -- mc_H7: D FF
            mc_H7 <= (GP_22 or mc_E0 or mc_H5 or mc_H14 or not mc_H15)
                and (not GP_22 or mc_H5 or mc_H13 or mc_H14 or not mc_H15)
                and (GP(6) or GP(19) or not mc_H5 or mc_H10)
                and (not GP(19) or not mc_H5 or mc_H7)
                and (mc_H5 or mc_H7 or mc_H15)
                and (mc_H5 or mc_H7 or not mc_H14);
            -- mc_H9: D FF
            mc_H9 <= (GP_22 or mc_E2 or mc_H5 or mc_H14 or not mc_H15)
                and (not GP_22 or mc_H5 or mc_H7 or mc_H14 or not mc_H15)
                and (GP(7) or GP(19) or not mc_H5 or mc_H10)
                and (not GP(19) or not mc_H5 or mc_H9)
                and (mc_H5 or mc_H9 or mc_H15)
                and (mc_H5 or mc_H9 or not mc_H14);
            -- mc_H13: D FF
            mc_H13 <= (GP_22 or mc_F5 or mc_H5 or mc_H14 or not mc_H15)
                and (not GP_22 or mc_H3 or mc_H5 or mc_H14 or not mc_H15)
                and (GP(5) or GP(19) or not mc_H5 or mc_H10)
                and (not GP(19) or not mc_H5 or mc_H13)
                and (mc_H5 or mc_H13 or mc_H15)
                and (mc_H5 or mc_H13 or not mc_H14);
        end if;
    end process;
    DDR_A(4) <= mc_H2;
    DDR_A(3) <= mc_H4;

    -- 高速时钟域逻辑
    process(CLK50MHz)
    begin
        if rising_edge(CLK50MHz) then
            mc_H0 <= GP_NRD;
            mc_H5 <= mc_H10;
            mc_H10 <= addr_load;
            mc_H14 <= mc_H15;
            mc_H15 <= GP_NWR and GP_NRD;
        end if;
    end process;

    mc_H1 <= (GP_NWR and GP_NRD) or N_SDOUT;
    SD_CLK <= mc_H1; -- SD卡时钟
    mc_H6 <= mc_H9;
    mc_H8 <= mc_H9;
    mc_H11 <= (not GP_NCS and GP_NWR and GP_NRD) or (GP_NCS and not GP_NRD) or (GP_NCS and not GP_NWR); -- 内部地址计数器时钟生成
    addr_load <= (GP_NWR and GP_NRD and addr_load) or GP_NCS; -- 地址加载控制

    -- SD Card Interface OE and Data (SD卡接口输出使能和数据)
    SD_CMD <= mc_H8 when (not GP_NWR and GP_22 and not N_SDOUT) = '1' else 'Z';
    SD_DAT(0) <= mc_H3 when (not GP_NWR and not GP_22 and not N_SDOUT) = '1' else 'Z';
    SD_DAT(1) <= mc_H13 when (not GP_NWR and not GP_22 and not N_SDOUT) = '1' else 'Z';
    SD_DAT(2) <= mc_H7 when (not GP_NWR and not GP_22 and not N_SDOUT) = '1' else 'Z';
    SD_DAT(3) <= mc_H6 when (not GP_NWR and not GP_22 and not N_SDOUT) = '1' else 'Z';

end behavioral;
