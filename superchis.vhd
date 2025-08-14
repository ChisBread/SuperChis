library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity superchis is
    port (
        -- Global Clocks and Control / 全局时钟与控制信号
        CLK50MHz : in  std_logic;  -- 50MHz main clock input / 50MHz 主时钟输入
        GP_NCS   : in  std_logic;  -- GBA Cartridge Chip Select (Active Low) / GBA卡带片选 (低电平有效)
        GP_NWR   : in  std_logic;  -- GBA Write Enable (Active Low) / GBA写使能 (低电平有效)
        GP_NRD   : in  std_logic;  -- GBA Read Enable (Active Low) / GBA读使能 (低电平有效)
        clk3     : in  std_logic;  -- Auxiliary Clock (Original design dependency) / 辅助时钟 (源于原始设计)

        -- General Purpose IO (from GBA cart edge) / GBA卡带接口通用IO
        GP       : inout std_logic_vector(15 downto 0);  -- GBA Data Bus (Address/Data multiplexed) / GBA数据总线 (地址/数据复用)
        GP_16    : in  std_logic;                       -- GBA Address Bus A16 / GBA地址总线 A16
        GP_17    : in  std_logic;                       -- GBA Address Bus A17 / GBA地址总线 A17
        GP_18    : in  std_logic;                       -- GBA Address Bus A18 / GBA地址总线 A18
        GP_19    : in  std_logic;                       -- GBA Address Bus A19 / GBA地址总线 A19
        GP_20    : in  std_logic;                       -- GBA Address Bus A20 / GBA地址总线 A20
        GP_21    : in  std_logic;                       -- GBA Address Bus A21 / GBA地址总线 A21
        GP_22    : in  std_logic;                       -- GBA Address Bus A22 / GBA地址总线 A22
        GP_23    : in  std_logic;                       -- GBA Address Bus A23 / GBA地址总线 A23

        -- DDR SDRAM Interface / DDR SDRAM 接口
        DDR_A    : out std_logic_vector(12 downto 0);  -- DDR Address Bus / DDR 地址总线
        DDR_BA   : out std_logic_vector(1 downto 0);   -- DDR Bank Address / DDR 存储体地址
        DDR_CKE  : out std_logic;                       -- DDR Clock Enable / DDR 时钟使能
        DDR_NRAS : out std_logic;                       -- DDR Row Address Strobe (Active Low) / DDR 行地址选通 (低电平有效)
        DDR_NCAS : out std_logic;                       -- DDR Column Address Strobe (Active Low) / DDR 列地址选通 (低电平有效)
        DDR_NWE  : out std_logic;                       -- DDR Write Enable (Active Low) / DDR 写使能 (低电平有效)

        -- Flash Interface / 闪存接口
        FLASH_A          : out std_logic_vector(15 downto 0);  -- Flash Address Bus / 闪存地址总线
        FLASH_NCE        : out std_logic;                       -- Flash Chip Enable (Active Low) / 闪存片选 (低电平有效)
        FLASH_SRAM_NWE   : out std_logic;                       -- Flash/SRAM Write Enable (Active Low) / 闪存/SRAM 写使能 (低电平有效)
        FLASH_SRAM_NOE   : out std_logic;                       -- Flash/SRAM Output Enable (Active Low) / 闪存/SRAM 输出使能 (低电平有效)
        SRAM_A16         : out std_logic;                       -- SRAM High Address bit (for banking) / SRAM 高位地址 (用于Bank切换)

        -- SD Card Interface / SD卡接口
        N_SDOUT : out std_logic;                          -- SD Card I/O Output Enable (Active Low) / SD卡IO输出使能 (低电平有效)
        SD_CLK  : out std_logic;                          -- SD Card Clock / SD卡时钟
        SD_CMD  : inout std_logic;                        -- SD Card Command Line / SD卡命令线
        SD_DAT  : inout std_logic_vector(3 downto 0)      -- SD Card Data Lines / SD卡数据线
    );
end entity superchis;

architecture behavioral of superchis is

    -- ========================================================================
    -- Type Definitions / 类型定义
    -- ========================================================================
    
    -- Access Mode Types / 访问模式类型
    type access_mode_t is (
        MODE_FLASH,     -- Accessing Flash/SRAM / 访问闪存或SRAM
        MODE_DDR,       -- Accessing DDR SDRAM / 访问DDR SDRAM
        MODE_SD         -- Accessing SD Card I/O / 访问SD卡IO
    );

    -- ========================================================================
    -- Internal Signals / 内部信号
    -- ========================================================================
    
    -- Configuration Registers / 配置寄存器
    -- These registers are set via the magic unlock sequence. / 这些寄存器通过“魔术解锁序列”设置。
    signal config_map_reg     : std_logic := '0';          -- Memory map control: 0=Flash, 1=DDR / 内存映射控制
    signal config_sd_enable   : std_logic := '0';          -- SD Card I/O interface enable / SD卡IO接口使能
    signal config_write_enable: std_logic := '0';          -- General write enable (used for SRAM A16, etc.) / 通用写使能 (用于SRAM A16等)
    signal config_bank_select : std_logic_vector(4 downto 0) := "00000";  -- Flash memory bank selection bits / Flash闪存的Bank选择位 (mc_C10, mc_G14, mc_D9, mc_B15, mc_C9)
    
    -- Magic Unlock Sequence / 魔术解锁序列
    -- Logic to detect the specific address/data sequence to unlock configuration. / 用于检测特定地址/数据序列以解锁配置功能的逻辑。
    signal magic_address      : std_logic := '0';          -- Detects access to the magic address (0x09FFFFFE) / 检测是否访问魔术地址
    signal magic_value_match  : std_logic := '0';          -- Detects the magic value (0xA55A) on the data bus / 检测总线上是否出现魔术值
    signal config_load_enable : std_logic := '0';          -- Enable signal for loading configuration / 配置加载使能信号
    signal magic_write_count  : unsigned(1 downto 0) := "00"; -- Counts the magic value writes (requires 2) / 对魔术值写入次数进行计数 (需要2次)
    
    -- Address Management / 地址管理
    signal internal_address   : unsigned(15 downto 0) := (others => '0');  -- Internal 16-bit address counter / 内部16位地址计数器
    signal flash_address      : std_logic_vector(15 downto 0);  -- Address bus going to the Flash chip / 连接到Flash芯片的地址总线
    signal ddr_address        : std_logic_vector(12 downto 0);   -- Address bus going to the DDR SDRAM / 连接到DDR SDRAM的地址总线
    signal ddr_bank_address   : std_logic_vector(1 downto 0);    -- Bank address for DDR SDRAM / DDR SDRAM的Bank地址
    
    -- DDR Control Signals / DDR控制信号
    
    -- DDR State Machine Type / DDR状态机类型
    type ddr_state_t is (
        DDR_IDLE,           -- 空闲状态，等待命令
        DDR_PRECHARGE,      -- 预充电状态
        DDR_ROW_ACTIVE,     -- 行激活状态
        DDR_COLUMN_ACCESS,  -- 列访问状态
        DDR_BURST_ACTIVE,   -- 突发传输状态
        DDR_REFRESH,        -- 自动刷新状态
        DDR_TIMING_WAIT     -- 时序等待状态
    );
    
    signal ddr_current_state  : ddr_state_t := DDR_IDLE;    -- 当前DDR状态
    signal ddr_next_state     : ddr_state_t := DDR_IDLE;    -- 下一个DDR状态
    
    -- DDR controller signals
    -- DDR控制器信号
    signal n_ddr_sel          : std_logic; -- DDR chip select (active low)
    signal ddr_nras_reg       : std_logic := '1'; -- DDR nRAS register
    signal ddr_ncas_reg       : std_logic := '1'; -- DDR nCAS register
    signal ddr_nwe_reg        : std_logic := '1'; -- DDR nWE register
    signal ddr_cke_reg        : std_logic := '0'; -- DDR CKE register
    signal ddrcnt             : unsigned(3 downto 0) := (others => '0'); -- Internal DDR timing counter
    signal icntr              : unsigned(8 downto 0) := (others => '0'); -- Internal refresh/timing counter
    
    -- Access Control / 访问控制
    signal current_mode       : access_mode_t := MODE_FLASH; -- Current top-level access mode / 当前顶层访问模式
    signal sd_output_enable   : std_logic := '1';           -- Master output enable for the SD card I/O block / SD卡IO模块的主输出使能
    
    -- Bus Control / 总线控制
    signal gp_output_enable   : std_logic := '0';           -- Output enable for the GP data bus / GP数据总线的输出使能
    signal gp_output_data     : std_logic_vector(15 downto 0) := (others => '0'); -- Data to be driven onto the GP bus / 将要驱动到GP总线上的数据
    
    -- Timing Control (Synchronizers) / 时序控制 (同步器)
    -- These signals are synchronized versions of GBA bus signals, used to avoid metastability. / GBA总线信号的同步版本，用于避免亚稳态。
    signal address_load       : std_logic := '0';           -- Latched signal indicating address phase / 标志地址阶段的锁存信号
    signal address_load_sync  : std_logic := '0';           -- First stage sync (original: mc_H10) / 第一级同步
    signal address_load_sync2 : std_logic := '0';           -- Second stage sync (original: mc_H5) / 第二级同步
    signal read_sync          : std_logic;                  -- Synchronized GP_NRD (original: mc_H0)
    signal write_enable_sync  : std_logic;                  -- Synchronized write enable logic (original: mc_E3)
    signal gba_bus_idle_sync_d1       : std_logic := '0';           -- Timing sync stage (original: mc_H14) / 时序同步级
    signal gba_bus_idle_sync       : std_logic := '0';           -- Timing sync stage (original: mc_H15) / 时序同步级
    signal addr_clock         : std_logic := '0';          -- Composite clock for address counter (original: mc_H11) / 地址计数器的组合时钟 (原始: mc_H11)  
    
    -- SD Card Signals / SD卡信号
    signal sd_cmd_out         : std_logic := '1';           -- Data to be driven on the SD_CMD line / 驱动到SD_CMD线上的数据
    signal sd_data_out        : std_logic_vector(3 downto 0) := (others => '1'); -- Data to be driven on the SD_DAT lines(original: mc_H3, H13, H7, H6) / 驱动到SD_DAT线上的数据
    signal sd_cmd_oe          : std_logic := '0';           -- Output enable for the SD_CMD line / SD_CMD线的输出使能
    signal sd_data_oe         : std_logic_vector(3 downto 0) := (others => '0'); -- Output enable for the SD_DAT lines / SD_DAT线的输出使能
    
    -- SD Card State Signals (Reconstructed from original macrocells) / SD卡状态信号 (对原始宏单元的重构)
    -- Note: The naming convention is descriptive, with original macrocell names in comments for cross-reference.
    -- 注意：命名约定是描述性的，并在注释中保留了原始宏单元名称，以便于交叉引用。
    
    -- State Latches (D-FFs) / 状态锁存器 (D型触发器)
    signal sd_cmd_state  : std_logic := '0'; -- Holds the current state for the CMD line output. (Original: mc_E13)
    signal sd_dat1_state : std_logic := '0'; -- Holds the state for DAT1 line logic. (Original: mc_F5)
    signal sd_dat2_state : std_logic := '0'; -- Holds the state for DAT2 line logic. (Original: mc_E0)
    signal sd_dat3_state : std_logic := '0'; -- Holds the state for DAT3 line logic. (Original: mc_E2)
    
    -- Toggle Flip-Flops (T-FFs) for State Control / 用于状态控制的T型触发器
    signal sd_cmd_toggle  : std_logic := '0'; -- T-FF for CMD state transition. (Original: mc_F7)
    signal sd_dat1_toggle : std_logic := '0'; -- T-FF for DAT1 state transition. (Original: mc_F9)
    signal sd_dat2_toggle : std_logic := '0'; -- T-FF for DAT2 state transition. (Original: mc_F11)
    signal sd_dat3_toggle : std_logic := '0'; -- T-FF for DAT3 state transition. (Original: mc_E15)

    -- Toggle Flip-Flops (T-FFs) for Feedback Path / 用于反馈路径的T型触发器
    signal sd_dat0_feedback_toggle : std_logic := '0'; -- T-FF for feedback from SD_DAT(0). (Original: mc_F14)
    signal sd_dat1_feedback_toggle : std_logic := '0'; -- T-FF for feedback from SD_DAT(1). (Original: mc_F15)
    signal sd_dat2_feedback_toggle : std_logic := '0'; -- T-FF for feedback from SD_DAT(2). (Original: mc_F0)
    signal sd_dat3_feedback_toggle : std_logic := '0'; -- T-FF for feedback from SD_DAT(3). (Original: mc_F1)

    -- SD Card Output Data Buffers / SD卡输出数据缓冲
    signal sd_cmd_out_data      : std_logic; -- Data for SD_CMD output. (Original: mc_H8)
    signal sd_dat0_out_data     : std_logic; -- Data for SD_DAT(0) output. (Original: mc_H3)
    signal sd_dat1_out_data     : std_logic; -- Data for SD_DAT(1) output. (Original: mc_H13)
    signal sd_dat2_out_data     : std_logic; -- Data for SD_DAT(2) output. (Original: mc_H7)
    signal sd_dat3_out_data     : std_logic; -- Data for SD_DAT(3) output. (Original: mc_H6)
    signal sd_common_out_logic  : std_logic; -- Shared logic for CMD and DAT3 outputs. (Original: mc_H9)
    
    -- Internal SD control signals / SD内部控制信号
    signal sd_mode_active : std_logic; -- High when SD card I/O is selected and active.
    signal sd_write_active: std_logic; -- High during a GBA write cycle to the SD interface.

begin

    -- ========================================================================
    -- Address Decoding and Mode Selection / 地址译码与模式选择
    -- Determines the current operating mode based on configuration registers.
    -- 基于配置寄存器的值，决定当前的芯片工作模式。
    -- ========================================================================
    
    process(internal_address, config_map_reg, config_sd_enable, GP_16, GP_17, GP_18, GP_19, GP_20, GP_21, GP_22, GP_23)
    begin
        -- Default to Flash mode / 默认为Flash模式
        current_mode <= MODE_FLASH;
        
        if config_sd_enable = '1' and GP_23 = '1' then
            current_mode <= MODE_SD;
        elsif config_map_reg = '1' then
            current_mode <= MODE_DDR;
        else
            current_mode <= MODE_FLASH;
        end if;
    end process;

    -- DDR Chip Select Logic (from original mc_E4)
    -- DDR片选逻辑
    n_ddr_sel <= GP_NCS or not config_map_reg or (config_sd_enable and GP_23);

    -- ========================================================================
    -- Magic Address Detection and Configuration / 魔术地址检测与配置
    -- Implements the unlock sequence required by the GBA driver.
    -- A specific 4-write sequence to address 0x09FFFFFE configures the chip.
    -- 实现GBA驱动所需的解锁序列。通过向地址0x09FFFFFE执行特定的4次写操作来配置芯片。
    -- ========================================================================
    
    -- Magic address detection: 0x00FFFFFF(0x09FFFFFE in GBA) (A23-A16=0xFF, A15-A0=0xFFFF)
    -- GBA address is byte-addressed, VHDL uses 16-bit words. So 0xFFFE -> 0xFFFF.
    -- 魔术地址检测: 0x00FFFFFF (字节地址) -> 内部地址 A23-A16=FFh, A15-A0=FFFFh -> 内部16位字地址 FFFFh
    magic_address <= '1' when (internal_address = x"FFFF" and
                               GP_16 = '1' and GP_17 = '1' and GP_18 = '1' and GP_19 = '1' and
                               GP_20 = '1' and GP_21 = '1' and GP_22 = '1' and GP_23 = '1') else '0';
    
    -- Magic value detection: 0xA55A on the data bus.
    -- Original pattern (mc_G2): !GP(0) & GP(1) & !GP(2) & GP(3) & GP(4) & !GP(5) & GP(6) & !GP(7) & 
    --                   GP(8) & !GP(9) & GP(10) & !GP(11) = 0101 0101 1010 = 0xA55A (low 12 bits)
    -- 魔术值检测: 数据总线上的0xA55A。
    magic_value_match <= '1' when (GP(15 downto 0) = x"A55A") else '0';
    
    -- Magic sequence state machine: requires two writes of 0xA55A, followed by two config writes.
    -- 魔术序列状态机: 需要两次写入0xA55A，随后是两次配置写入。
    process(GP_NWR)
    begin
        if falling_edge(GP_NWR) then
            if magic_address = '1' then
                case magic_write_count is
                    when "00" => -- Expect first magic value / 等待第一个魔术值
                        if magic_value_match = '1' then
                            magic_write_count <= "01";
                        end if;
                    when "01" => -- Expect second magic value / 等待第二个魔术值
                        if magic_value_match = '1' then
                            magic_write_count <= "10";
                        else
                            magic_write_count <= "00"; -- Reset on wrong value / 值错误则复位
                        end if;
                    when "10" => -- Expect first config value, load it. / 等待第一个配置值并加载
                        config_sd_enable    <= GP(1);
                        config_map_reg      <= GP(0);
                        config_write_enable <= GP(2);
                        -- Faithfully reconstruct the original's complex flash banking logic.
                        -- 忠实地重构原始设计中复杂的Flash Bank逻辑。
                        config_bank_select(0) <= GP(4) and not GP(8) and GP(12);   -- mc_C10
                        config_bank_select(1) <= GP(7) and not GP(10) and GP(11);  -- mc_G14
                        config_bank_select(2) <= GP(7) and GP(9) and not GP(15);   -- mc_D9
                        config_bank_select(3) <= GP(6) and not GP(13) and GP(12);  -- mc_B15
                        config_bank_select(4) <= GP(4) and not GP(5) and GP(14);   -- mc_C9
                        magic_write_count   <= "11";
                    when "11" => -- Expect second config value, then reset sequence. / 等待第二个配置值，然后复位序列
                        magic_write_count <= "00";
                    when others =>
                        magic_write_count <= "00";
                end case;
            else
                -- If write is not to magic address, reset the sequence.
                -- 如果写操作未指向魔术地址，则复位序列。
                magic_write_count <= "00";
            end if;
        end if;
    end process;

    -- ========================================================================
    -- Internal Address Counter / 内部地址计数器
    -- Latches the address from the GP bus or auto-increments for sequential access.
    -- 从GP总线锁存地址，或在连续访问时自动递增。
    -- ========================================================================
    
    -- Address load control latch. (Original: addr_load <= (GP_NWR and GP_NRD and addr_load) or GP_NCS;)
    -- This latch holds '1' when GP_NCS is high (inactive), allowing the address to be loaded.
    -- 地址加载控制锁存器。当GP_NCS为高（非活动）时，该锁存器保持'1'，允许加载新地址。
    address_load <= (GP_NWR and GP_NRD and address_load) or GP_NCS;
    
    -- Generate address counter clock (equivalent to mc_H11 in original CPLD report)
    -- mc_H11 = !GP_NCS & GP_NWR & GP_NRD | GP_NCS & !GP_NRD | GP_NCS & !GP_NWR
    -- This creates clock edges for both address loading and auto-increment
    -- 为地址计数器生成时钟 (等效于原始CPLD报告的mc_H11)
    -- 这为地址加载和自动递增都创建时钟边沿
    addr_clock <= (not GP_NCS and GP_NWR and GP_NRD) or 
                  (GP_NCS and not GP_NRD) or 
                  (GP_NCS and not GP_NWR);
    
    -- Internal address counter process.
    -- The clock is a composite signal derived from GBA control signals, as in the original design.
    -- 内部地址计数器进程。其时钟是GBA控制信号的组合，与原始设计一致。
    process(addr_clock)
    begin
        if rising_edge(addr_clock) then
            if address_load = '1' then
                -- Load address from GBA data bus
                -- 从GBA数据总线加载地址
                internal_address <= unsigned(GP);
            else
                -- Auto-increment for next sequential address
                -- 自动递增以访问下一个地址
                internal_address <= internal_address + 1;
            end if;
        end if;
    end process;

    -- ========================================================================
    -- Flash Address Generation / Flash地址生成
    -- Implements complex banking logic from original CPLD
    -- 实现源自原始CPLD的复杂Bank切换逻辑
    -- ========================================================================
    
    process(internal_address, config_bank_select, current_mode, config_write_enable)
    begin
        if current_mode = MODE_FLASH then
            -- Direct implementation based on CPLD report address scrambling and banking
            -- 基于CPLD报告的地址重映射与Bank选择的直接实现

            -- Direct Scrambling / 直接重映射
            flash_address(0)  <= internal_address(7);  -- FLASH-A0 = iaddr-a7
            flash_address(2)  <= internal_address(6);  -- FLASH-A2 = iaddr-a6
            flash_address(4)  <= internal_address(0);  -- FLASH-A4 = iaddr-a0
            flash_address(5)  <= internal_address(2);  -- FLASH-A5 = iaddr-a2
            flash_address(8)  <= internal_address(3);  -- FLASH-A8 = iaddr-a3
            flash_address(10) <= internal_address(10); -- FLASH-A10 = iaddr-a10
            flash_address(12) <= internal_address(12); -- FLASH-A12 = iaddr-a12
            flash_address(13) <= internal_address(13); -- FLASH-A13 = iaddr-a13

            -- Scrambling combined with Banking Logic (OR logic from report)
            -- 与Bank逻辑结合的重映射部分（来自报告的“或”逻辑）
            flash_address(1)  <= internal_address(1) or config_bank_select(3); -- FLASH-A1 = mc_C1 = mc_B15 | iaddr-a1
            flash_address(3)  <= internal_address(5) or config_bank_select(3) or config_bank_select(4); -- FLASH-A3 = mc_C15 = mc_B15 | iaddr-a5 | mc_C9
            flash_address(6)  <= internal_address(8) or config_bank_select(4) ; -- FLASH-A6 = mc_C8 = mc_C9 | iaddr-a8
            flash_address(7)  <= internal_address(4)  or config_bank_select(0); -- FLASH-A7 = mc_D1 = iaddr-a4 | mc_C10
            flash_address(11) <= internal_address(11) or config_bank_select(2); -- FLASH-A11 = mc_D2 = iaddr-a11 | mc_D9
            flash_address(14) <= internal_address(14) or config_bank_select(1); -- FLASH-A14 = mc_C6 = iaddr-a14 | mc_G14
            flash_address(15) <= internal_address(15) or config_bank_select(0) or config_bank_select(1) or config_bank_select(2); -- FLASH-A15 = mc_D0 = mc_C10 | iaddr-a15 | mc_D9 | mc_G14

            -- Gated Logic (AND logic from report)
            -- 门控逻辑部分（来自报告的“与”逻辑）
            flash_address(9)  <= internal_address(9) and config_write_enable; -- FLASH-A9 = mc_E7 = iaddr-a9 & WRITEENABLE

        else
            -- In non-Flash modes, pass the address through directly.
            -- 在非Flash模式下，直接透传地址。
            flash_address <= std_logic_vector(internal_address);
        end if;
    end process;
    
    FLASH_A <= flash_address;
    
    -- SRAM A16 is controlled by write enable config bit for banking
    -- SRAM A16由写使能配置位控制，用于Bank切换
    SRAM_A16 <= config_write_enable;

    -- ========================================================================
    -- DDR SDRAM Controller / DDR SDRAM 控制器
    -- This is a readable state machine implementation that is functionally equivalent
    -- to the original CPLD's DDR controller boolean equations.
    -- 这是一个可读的状态机实现，在功能上等效于原始CPLD的DDR控制器布尔方程。
    -- ========================================================================

    -- Internal counter with asynchronous reset, based on original CPLD report (GLB G)
    -- 基于原始CPLD报告的带异步复位的内部计数器 (GLB G)
    process(GP_NCS, ddr_cke_reg, ddr_nwe_reg, ddr_nras_reg, ddr_ncas_reg)
        variable reset_icntr : std_logic;
    begin
        -- Async reset condition for high bits of icntr
        reset_icntr := ddr_cke_reg and ddr_nwe_reg and not ddr_nras_reg and not ddr_ncas_reg;
        if reset_icntr = '1' then
            icntr(8 downto 7) <= "00";
        elsif rising_edge(GP_NCS) then
            -- Low bits are a synchronous counter
            icntr(6 downto 0) <= icntr(6 downto 0) + 1;
            -- High bits are toggle flip-flops based on lower bits carry-out
            if (icntr(6 downto 0) = "1111111") then
                icntr(7) <= not icntr(7);
            end if;
            if (icntr(7 downto 0) = "11111111") then
                icntr(8) <= not icntr(8);
            end if;
        end if;
    end process;

    -- DDR State Machine Transition Logic / DDR状态机转移逻辑
    -- This process determines the next state based on current conditions
    -- 此进程根据当前条件确定下一个状态
    ddr_state_transition: process(ddr_current_state, n_ddr_sel, write_enable_sync, read_sync, 
                                  icntr, ddrcnt, GP_NCS)
    begin
        case ddr_current_state is
            when DDR_IDLE =>
                -- 检查是否需要自动刷新
                if icntr(8) = '1' and icntr(7) = '1' then
                    ddr_next_state <= DDR_REFRESH;
                -- 检查是否有访问请求
                elsif n_ddr_sel = '0' and (write_enable_sync = '0' or read_sync = '0') then
                    ddr_next_state <= DDR_ROW_ACTIVE;
                else
                    ddr_next_state <= DDR_IDLE;
                end if;

            when DDR_ROW_ACTIVE =>
                -- 行激活后进入列访问
                ddr_next_state <= DDR_COLUMN_ACCESS;

            when DDR_COLUMN_ACCESS =>
                -- 列访问后进入突发传输或预充电
                if n_ddr_sel = '1' then
                    ddr_next_state <= DDR_PRECHARGE;
                else
                    ddr_next_state <= DDR_BURST_ACTIVE;
                end if;

            when DDR_BURST_ACTIVE =>
                -- 突发传输期间检查是否需要预充电
                if n_ddr_sel = '1' or (icntr(8) = '1' and icntr(7) = '1') then
                    ddr_next_state <= DDR_PRECHARGE;
                else
                    ddr_next_state <= DDR_BURST_ACTIVE;
                end if;

            when DDR_PRECHARGE =>
                -- 预充电完成后根据条件决定下一步
                if icntr(8) = '1' and icntr(7) = '1' then
                    ddr_next_state <= DDR_REFRESH;
                elsif ddrcnt = "1000" then  -- 预充电时间完成
                    ddr_next_state <= DDR_IDLE;
                else
                    ddr_next_state <= DDR_TIMING_WAIT;
                end if;

            when DDR_REFRESH =>
                -- 刷新完成后返回空闲
                ddr_next_state <= DDR_TIMING_WAIT;

            when DDR_TIMING_WAIT =>
                -- 等待时序要求满足
                if ddrcnt = "0000" then
                    ddr_next_state <= DDR_IDLE;
                else
                    ddr_next_state <= DDR_TIMING_WAIT;
                end if;

            when others =>
                ddr_next_state <= DDR_IDLE;
        end case;
    end process;

    -- DDR State Machine Sequential Logic / DDR状态机时序逻辑
    ddr_state_register: process(GP_NCS)
    begin
        if rising_edge(GP_NCS) then
            ddr_current_state <= ddr_next_state;
            
            -- DDR timing counter management / DDR时序计数器管理
            case ddr_current_state is
                when DDR_PRECHARGE | DDR_TIMING_WAIT =>
                    if ddrcnt /= "0000" then
                        ddrcnt <= ddrcnt - 1;
                    end if;
                when DDR_ROW_ACTIVE =>
                    ddrcnt <= "1000";  -- 设置预充电等待时间
                when others =>
                    ddrcnt <= (others => '0');
            end case;
        end if;
    end process;

    -- DDR Control Signal Generation / DDR控制信号生成
    -- Generate control signals based on current state
    -- 根据当前状态生成控制信号
    ddr_control_signals: process(ddr_current_state, n_ddr_sel, write_enable_sync, icntr)
    begin
        -- Default values / 默认值
        ddr_nras_reg <= '1';
        ddr_ncas_reg <= '1';
        ddr_nwe_reg  <= '1';
        ddr_cke_reg  <= '0';

        case ddr_current_state is
            when DDR_IDLE =>
                ddr_cke_reg <= '1';
                
            when DDR_ROW_ACTIVE =>
                ddr_nras_reg <= '0';  -- 激活行
                ddr_cke_reg  <= '1';
                
            when DDR_COLUMN_ACCESS =>
                ddr_ncas_reg <= '0';  -- 激活列
                ddr_cke_reg  <= '1';
                if write_enable_sync = '0' then
                    ddr_nwe_reg <= '0';  -- 写操作
                end if;
                
            when DDR_BURST_ACTIVE =>
                ddr_cke_reg <= '1';
                if write_enable_sync = '0' then
                    ddr_nwe_reg <= '0';
                end if;
                
            when DDR_PRECHARGE =>
                ddr_nras_reg <= '0';  -- 预充电命令
                ddr_ncas_reg <= '0';
                ddr_cke_reg  <= '1';
                
            when DDR_REFRESH =>
                ddr_nras_reg <= '0';  -- 自动刷新
                ddr_ncas_reg <= '0';
                ddr_cke_reg  <= '1';
                
            when DDR_TIMING_WAIT =>
                ddr_cke_reg <= '1';
                
            when others =>
                null;  -- 保持默认值
        end case;
    end process;

    -- ========================================================================
    -- DDR Address and Control Line Assignment / DDR地址与控制线分配
    -- ========================================================================
    
    -- Assign control signals from reconstructed macrocells
    DDR_NRAS <= ddr_nras_reg;
    DDR_NCAS <= ddr_ncas_reg;
    DDR_NWE  <= ddr_nwe_reg;
    DDR_CKE  <= ddr_cke_reg;
    
    -- DDR Address and Bank multiplexing based on state machine
    -- 基于状态机的DDR地址和Bank复用
    process(GP_NCS)
    begin
        if rising_edge(GP_NCS) then
            -- Bank Address (stable across phases)
            -- Bank地址（在各阶段保持稳定）
            if ddr_current_state = DDR_ROW_ACTIVE or ddr_current_state = DDR_COLUMN_ACCESS then
                ddr_bank_address(1) <= GP_23; -- Bank select bit 1
                ddr_bank_address(0) <= GP_22; -- Bank select bit 0
            end if;

            -- Row/Column Address Multiplexing based on state machine
            -- 基于状态机的行/列地址复用
            case ddr_current_state is
                when DDR_ROW_ACTIVE =>
                    -- Row Address Phase / 行地址阶段
                    ddr_address(0)  <= internal_address(9);
                    ddr_address(1)  <= not internal_address(10);
                    ddr_address(2)  <= internal_address(11);
                    ddr_address(3)  <= internal_address(12);
                    ddr_address(4)  <= internal_address(13);
                    ddr_address(5)  <= internal_address(14);
                    ddr_address(6)  <= internal_address(15);
                    ddr_address(7)  <= GP_16;
                    ddr_address(8)  <= not GP_17;
                    ddr_address(9)  <= GP_18;
                    ddr_address(10) <= not GP_19;
                    ddr_address(11) <= GP_20;
                    ddr_address(12) <= GP_21;
                    
                when DDR_COLUMN_ACCESS =>
                    -- Column Address Phase / 列地址阶段
                    ddr_address(0)  <= internal_address(0);
                    ddr_address(1)  <= not internal_address(1);
                    ddr_address(2)  <= internal_address(2);
                    ddr_address(3)  <= internal_address(3);
                    ddr_address(4)  <= internal_address(4);
                    ddr_address(5)  <= internal_address(5);
                    ddr_address(6)  <= internal_address(6);
                    ddr_address(7)  <= internal_address(7);
                    ddr_address(8)  <= not internal_address(8);
                    ddr_address(9)  <= '0'; -- Tied low
                    ddr_address(10) <= not GP_19; -- Special case for precharge all
                    ddr_address(11) <= '0'; -- Tied low
                    ddr_address(12) <= '0'; -- Tied low
                    
                when others =>
                    -- Maintain previous address during other states
                    -- 在其他状态期间保持之前的地址
                    null;
            end case;
        end if;
    end process;
    
    DDR_A  <= ddr_address;
    DDR_BA <= ddr_bank_address;

    -- ========================================================================
    -- Chip Enable Generation / 片选信号生成
    -- ========================================================================

    -- This logic is a faithful reconstruction of the original hardware's
    -- chip enable logic from original.vhd macrocells. These signals are active-low.
    -- 此逻辑忠实地重构了原始硬件(original.vhd)宏单元的片选逻辑。这些信号都是低电平有效。

    -- FLASH_NCE is enabled when: GP_NCS is active, not in DDR mode, and not in SD mode (or GP_23 is low).
    -- The clk3 dependency is unusual but faithful to the original.
    -- FLASH_NCE在以下情况使能: GP_NCS有效, 非DDR模式, 且非SD模式(或GP_23为低)。
    -- 对clk3的依赖不寻常，但忠于原始设计。
    FLASH_NCE <= GP_NCS or clk3 or config_map_reg or (config_sd_enable and GP_23);

    -- N_SDOUT (SD I/O block enable) is enabled when: GP_NCS is active, SD mode is enabled, and GP_23 is high.
    -- It is disabled at the magic address to prevent conflicts.
    -- N_SDOUT (SD I/O模块使能)在以下情况使能: GP_NCS有效, SD模式使能, 且GP_23为高。
    -- 在魔术地址处该信号被禁用以防止冲突。
    sd_output_enable <= GP_NCS or not GP_23 or not config_sd_enable or magic_address;
    
    N_SDOUT <= sd_output_enable;
    -- ========================================================================
    -- Read/Write Enable Synchronization / 读写信号同步
    -- Synchronizes GBA bus signals to the internal 50MHz clock to prevent metastability.
    -- 将GBA总线信号同步到内部50MHz时钟，以防止亚稳态问题。
    -- ========================================================================
    
    process(CLK50MHz)
    begin
        if rising_edge(CLK50MHz) then
            read_sync  <= GP_NRD;
            
            -- Address load synchronization chain (original: mc_H10 -> mc_H5)
            -- 地址加载同步链
            address_load_sync <= address_load;
            address_load_sync2 <= address_load_sync;
            
            -- Timing synchronization stages (original: mc_H14, mc_H15)
            -- 时序同步级
            gba_bus_idle_sync <= GP_NWR and GP_NRD;
            gba_bus_idle_sync_d1 <= gba_bus_idle_sync;
            
            -- Synchronized write enable logic (original: mc_E3)
            -- 同步写使能逻辑
            write_enable_sync <= GP_NWR or not config_write_enable;
        end if;
    end process;
    
    -- Pass through GBA R/W signals to Flash/SRAM directly.
    -- 将GBA的读写信号直接透传给Flash/SRAM。
    FLASH_SRAM_NWE <= GP_NWR;
    FLASH_SRAM_NOE <= GP_NRD;

    -- ========================================================================
    -- GP Bus Output Control / GP总线输出控制
    -- Controls when the CPLD drives data onto the GBA's GP data bus.
    -- 控制CPLD何时将数据驱动到GBA的GP数据总线上。
    -- ========================================================================
    
    -- The GP bus is driven only during a GBA read cycle (GP_NRD='0') and when the SD I/O block is active.
    -- GP总线仅在GBA读周期(GP_NRD='0')且SD I/O模块激活时才由本芯片驱动。
    gp_output_enable <= '1' when (GP_NRD = '0' and sd_output_enable = '0') else '0';
    
    -- GP Bus Data Multiplexing (Reconstructed from original.vhd CPLD equations)
    -- This process multiplexes various internal SD card states onto the GP data bus during SD read operations.
    -- The behavior is controlled by GP_22:
    --  - GP_22 = '0' (Debug Mode): Exposes internal toggle and state flip-flops for debugging.
    --  - GP_22 = '1' (Data Mode):  Exposes actual SD line data and processed states.
    gp_bus_mux: process(GP_22, SD_CMD, SD_DAT, clk3, sd_cmd_state, sd_dat1_state, sd_dat2_state, sd_dat3_state, 
                        sd_cmd_toggle, sd_dat1_toggle, sd_dat2_toggle, sd_dat3_toggle, 
                        sd_dat0_feedback_toggle, sd_dat1_feedback_toggle, sd_dat2_feedback_toggle, sd_dat3_feedback_toggle,
                        sd_dat0_out_data, sd_dat1_out_data, sd_dat2_out_data)
    begin
        -- This logic is a direct, readable translation of the macrocell equations feeding the GP bus drivers.
        -- Each line corresponds to a specific GP data bit's source logic from original.vhd.
        if GP_22 = '0' then -- Debug Mode: Output internal FF states
            gp_output_data(0)  <= sd_cmd_toggle;             -- mc_F7
            gp_output_data(1)  <= sd_dat1_toggle;            -- mc_F9
            gp_output_data(2)  <= sd_dat2_toggle;            -- mc_F11
            gp_output_data(3)  <= sd_dat3_toggle;            -- mc_E15
            gp_output_data(4)  <= sd_cmd_state;              -- mc_E13
            gp_output_data(5)  <= sd_dat1_state;             -- mc_F5
            gp_output_data(6)  <= sd_dat2_state;             -- mc_E0
            gp_output_data(7)  <= sd_dat3_state;             -- mc_E2
            gp_output_data(8)  <= SD_DAT(0);                 -- Raw SD_DAT(0) input
            gp_output_data(9)  <= SD_DAT(1);                 -- Raw SD_DAT(1) input
            gp_output_data(10) <= SD_DAT(2);                 -- Raw SD_DAT(2) input
            gp_output_data(11) <= SD_DAT(3);                 -- Raw SD_DAT(3) input
            gp_output_data(12) <= sd_dat0_feedback_toggle;   -- mc_F14
            gp_output_data(13) <= sd_dat1_feedback_toggle;   -- mc_F15
            gp_output_data(14) <= sd_dat2_feedback_toggle;   -- mc_F0
            gp_output_data(15) <= sd_dat3_feedback_toggle;   -- mc_F1
        else -- Data Transmission Mode
            gp_output_data(0)  <= SD_CMD;                    -- Raw SD_CMD input
            gp_output_data(1)  <= sd_cmd_state;              -- mc_E13
            gp_output_data(2)  <= sd_dat1_state;             -- mc_F5
            gp_output_data(3)  <= sd_dat2_state;             -- mc_E0
            gp_output_data(4)  <= sd_dat3_state;             -- mc_E2
            gp_output_data(5)  <= sd_dat0_out_data;          -- mc_H3
            gp_output_data(6)  <= sd_dat1_out_data;          -- mc_H13
            gp_output_data(7)  <= sd_dat2_out_data;          -- mc_H7
            gp_output_data(8)  <= clk3;                      -- Raw clk3 input
            gp_output_data(9)  <= '0';                       -- Tied to GND
            gp_output_data(10) <= '1';                       -- Tied to VCC
            gp_output_data(11) <= '1';                       -- Tied to VCC
            gp_output_data(12) <= '1';                       -- Tied to VCC
            gp_output_data(13) <= '1';                       -- Tied to VCC
            gp_output_data(14) <= '1';                       -- Tied to VCC
            gp_output_data(15) <= '1';                       -- Tied to VCC
        end if;
    end process;
    
    -- GP bus tri-state control. Drive the bus when enabled, otherwise high-impedance.
    -- GP总线三态控制。使能时驱动总线，否则为高阻态。
    GP <= gp_output_data when gp_output_enable = '1' else (others => 'Z');

    -- ========================================================================
    -- SD Card Interface (Reconstructed from original.vhd)
    -- ========================================================================
    -- This section faithfully reconstructs the complex bit-banging logic for SD card
    -- communication found in the original CPLD design. It relies on a series of
    -- state latches (D-FFs) and toggle flip-flops (T-FFs) clocked by GP_NCS.
    -- The logic is controlled by GBA-side signals like GP_19, GP_22, and
    -- specific data bits on the GP bus (GP(0)-GP(15)) for control and resets.
    --
    -- Key Timing Signals:
    --   - address_load_sync2:   Latched address phase signal (from mc_H5).
    --   - gba_bus_idle_sync:    Indicates GBA bus is idle (NRD=1, NWR=1) (from mc_H15).
    --   - gba_bus_idle_sync_d1: Delayed version of the above (from mc_H14).
    -- ========================================================================

    -- Process for SD Card State Latches (D-FFs), clocked by GP_NCS.
    -- This implements the core state machine that determines SD line output values.
    sd_state_logic: process(GP_NCS)
    begin
        if rising_edge(GP_NCS) then
            -- CMD State (Original: mc_E13)
            sd_cmd_state <= (sd_cmd_state or address_load_sync2 or not gba_bus_idle_sync_d1)
                and (GP_22 or sd_cmd_toggle or address_load_sync2 or gba_bus_idle_sync_d1 or not gba_bus_idle_sync)
                and (GP(0) or GP_19 or not address_load_sync2 or address_load_sync)
                and (not GP_22 or SD_CMD or address_load_sync2 or gba_bus_idle_sync_d1 or not gba_bus_idle_sync)
                and (not GP_19 or sd_cmd_state or not address_load_sync2)
                and (sd_cmd_state or address_load_sync2 or gba_bus_idle_sync);

            -- DAT1 State (Original: mc_F5)
            sd_dat1_state <= (not GP_22 or sd_cmd_state or address_load_sync2 or gba_bus_idle_sync_d1 or not gba_bus_idle_sync)
                and (GP_22 or sd_dat1_toggle or address_load_sync2 or gba_bus_idle_sync_d1 or not gba_bus_idle_sync)
                and (GP(1) or GP_19 or not address_load_sync2 or address_load_sync)
                and (not GP_19 or sd_dat1_state or not address_load_sync2)
                and (sd_dat1_state or address_load_sync2 or gba_bus_idle_sync)
                and (sd_dat1_state or address_load_sync2 or not gba_bus_idle_sync_d1);

            -- DAT2 State (Original: mc_E0)
            sd_dat2_state <= (not GP_22 or sd_dat1_state or address_load_sync2 or gba_bus_idle_sync_d1 or not gba_bus_idle_sync)
                and (GP_22 or sd_dat2_toggle or address_load_sync2 or gba_bus_idle_sync_d1 or not gba_bus_idle_sync)
                and (GP(2) or GP_19 or not address_load_sync2 or address_load_sync)
                and (not GP_19 or sd_dat2_state or not address_load_sync2)
                and (sd_dat2_state or address_load_sync2 or gba_bus_idle_sync)
                and (sd_dat2_state or address_load_sync2 or not gba_bus_idle_sync_d1);

            -- DAT3 State (Original: mc_E2)
            sd_dat3_state <= (not GP_22 or sd_dat2_state or address_load_sync2 or gba_bus_idle_sync_d1 or not gba_bus_idle_sync)
                and (GP_22 or sd_dat3_toggle or address_load_sync2 or gba_bus_idle_sync_d1 or not gba_bus_idle_sync)
                and (GP(3) or GP_19 or not address_load_sync2 or address_load_sync)
                and (not GP_19 or sd_dat3_state or not address_load_sync2)
                and (sd_dat3_state or address_load_sync2 or gba_bus_idle_sync)
                and (sd_dat3_state or address_load_sync2 or not gba_bus_idle_sync_d1);
        end if;
    end process;

    -- Process for SD Card Toggle Flip-Flops (T-FFs), clocked by GP_NCS.
    -- This implements the complex state transition logic, which often depends on feedback
    -- from the SD lines themselves, allowing for bit-banging communication protocols.
    sd_toggle_logic: process(GP_NCS)
        -- Local variables to hold the calculated toggle condition for each flip-flop.
        -- This replaces the 'should_toggle' function to resolve signal access errors.
        variable toggle_cond : std_logic;
        variable set_cond    : std_logic;
        variable reset_cond  : std_logic;
        variable timing_active : std_logic;
    begin
        if rising_edge(GP_NCS) then
            -- This timing window is active during the transition from active R/W to idle bus state.
            timing_active := not address_load_sync2 and not gba_bus_idle_sync_d1 and gba_bus_idle_sync;

            -- ==================================================================
            -- Logic for: sd_cmd_toggle (mc_F7)
            -- ==================================================================
            set_cond := (not GP_19 and not sd_cmd_toggle and address_load_sync2) or
                        (not GP_22 and sd_dat0_feedback_toggle and not sd_cmd_toggle and timing_active) or
                        (not GP_22 and not sd_dat0_feedback_toggle and sd_cmd_toggle and timing_active);
            reset_cond := not GP(12) and not GP_19 and address_load_sync2 and not address_load_sync;
            toggle_cond := set_cond xor reset_cond;
            sd_cmd_toggle <= sd_cmd_toggle xor toggle_cond;

            -- ==================================================================
            -- Logic for: sd_dat1_toggle (mc_F9)
            -- ==================================================================
            set_cond := (not GP_19 and not sd_dat1_toggle and address_load_sync2) or
                        (not GP_22 and sd_dat1_feedback_toggle and not sd_dat1_toggle and timing_active) or
                        (not GP_22 and not sd_dat1_feedback_toggle and sd_dat1_toggle and timing_active);
            reset_cond := not GP(13) and not GP_19 and address_load_sync2 and not address_load_sync;
            toggle_cond := set_cond xor reset_cond;
            sd_dat1_toggle <= sd_dat1_toggle xor toggle_cond;

            -- ==================================================================
            -- Logic for: sd_dat2_toggle (mc_F11)
            -- ==================================================================
            set_cond := (not GP_19 and not sd_dat2_toggle and address_load_sync2) or
                        (not GP_22 and sd_dat2_feedback_toggle and not sd_dat2_toggle and timing_active) or
                        (not GP_22 and not sd_dat2_feedback_toggle and sd_dat2_toggle and timing_active);
            reset_cond := not GP(14) and not GP_19 and address_load_sync2 and not address_load_sync;
            toggle_cond := set_cond xor reset_cond;
            sd_dat2_toggle <= sd_dat2_toggle xor toggle_cond;

            -- ==================================================================
            -- Logic for: sd_dat3_toggle (mc_E15)
            -- ==================================================================
            set_cond := (not GP_19 and not sd_dat3_toggle and address_load_sync2) or
                        (not GP_22 and sd_dat3_feedback_toggle and not sd_dat3_toggle and timing_active) or
                        (not GP_22 and not sd_dat3_feedback_toggle and sd_dat3_toggle and timing_active);
            reset_cond := not GP(15) and not GP_19 and address_load_sync2 and not address_load_sync;
            toggle_cond := set_cond xor reset_cond;
            sd_dat3_toggle <= sd_dat3_toggle xor toggle_cond;

            -- ==================================================================
            -- Logic for: sd_dat0_feedback_toggle (mc_F14)
            -- ==================================================================
            set_cond := (not GP_19 and not sd_dat0_feedback_toggle and address_load_sync2) or
                        (not GP_22 and SD_DAT(0) and not sd_dat0_feedback_toggle and timing_active) or
                        (not GP_22 and not SD_DAT(0) and sd_dat0_feedback_toggle and timing_active);
            reset_cond := not GP(8) and not GP_19 and address_load_sync2 and not address_load_sync;
            toggle_cond := set_cond xor reset_cond;
            sd_dat0_feedback_toggle <= sd_dat0_feedback_toggle xor toggle_cond;

            -- ==================================================================
            -- Logic for: sd_dat1_feedback_toggle (mc_F15)
            -- ==================================================================
            set_cond := (not GP_19 and not sd_dat1_feedback_toggle and address_load_sync2) or
                        (not GP_22 and SD_DAT(1) and not sd_dat1_feedback_toggle and timing_active) or
                        (not GP_22 and not SD_DAT(1) and sd_dat1_feedback_toggle and timing_active);
            reset_cond := not GP(9) and not GP_19 and address_load_sync2 and not address_load_sync;
            toggle_cond := set_cond xor reset_cond;
            sd_dat1_feedback_toggle <= sd_dat1_feedback_toggle xor toggle_cond;

            -- ==================================================================
            -- Logic for: sd_dat2_feedback_toggle (mc_F0)
            -- ==================================================================
            set_cond := (not GP_19 and not sd_dat2_feedback_toggle and address_load_sync2) or
                        (not GP_22 and SD_DAT(2) and not sd_dat2_feedback_toggle and timing_active) or
                        (not GP_22 and not SD_DAT(2) and sd_dat2_feedback_toggle and timing_active);
            reset_cond := not GP(10) and not GP_19 and address_load_sync2 and not address_load_sync;
            toggle_cond := set_cond xor reset_cond;
            sd_dat2_feedback_toggle <= sd_dat2_feedback_toggle xor toggle_cond;

            -- ==================================================================
            -- Logic for: sd_dat3_feedback_toggle (mc_F1)
            -- ==================================================================
            set_cond := (not GP_19 and not sd_dat3_feedback_toggle and address_load_sync2) or
                        (not GP_22 and SD_DAT(3) and not sd_dat3_feedback_toggle and timing_active) or
                        (not GP_22 and not SD_DAT(3) and sd_dat3_feedback_toggle and timing_active);
            reset_cond := not GP(11) and not GP_19 and address_load_sync2 and not address_load_sync;
            toggle_cond := set_cond xor reset_cond;
            sd_dat3_feedback_toggle <= sd_dat3_feedback_toggle xor toggle_cond;
        end if;
    end process;

    -- ========================================================================
    -- SD Interface Physical Layer / SD接口物理层
    -- ========================================================================
    
    -- SD Clock Generation (Original: mc_H1)
    SD_CLK <= (GP_NWR and GP_NRD) or sd_output_enable;
    
    -- Process for SD Card Output Data Buffers (D-FFs), clocked by GP_NCS.
    -- This generates the final data values to be driven onto the SD lines.
    sd_output_data_logic: process(GP_NCS)
    begin
        if rising_edge(GP_NCS) then
            -- SD_DAT(0) Output Data (Original: mc_H3)
            sd_dat0_out_data <= (not GP_22 or sd_dat3_state or address_load_sync2 or gba_bus_idle_sync_d1 or not gba_bus_idle_sync)
                and (GP_22 or sd_cmd_state or address_load_sync2 or gba_bus_idle_sync_d1 or not gba_bus_idle_sync)
                and (GP(4) or GP_19 or not address_load_sync2 or address_load_sync)
                and (not GP_19 or sd_dat0_out_data or not address_load_sync2)
                and (sd_dat0_out_data or address_load_sync2 or gba_bus_idle_sync)
                and (sd_dat0_out_data or address_load_sync2 or not gba_bus_idle_sync_d1);

            -- SD_DAT(1) Output Data (Original: mc_H13)
            sd_dat1_out_data <= (GP_22 or sd_dat1_state or address_load_sync2 or gba_bus_idle_sync_d1 or not gba_bus_idle_sync)
                and (not GP_22 or sd_dat0_out_data or address_load_sync2 or gba_bus_idle_sync_d1 or not gba_bus_idle_sync)
                and (GP(5) or GP_19 or not address_load_sync2 or address_load_sync)
                and (not GP_19 or not address_load_sync2 or sd_dat1_out_data)
                and (address_load_sync2 or sd_dat1_out_data or gba_bus_idle_sync)
                and (address_load_sync2 or sd_dat1_out_data or not gba_bus_idle_sync_d1);

            -- SD_DAT(2) Output Data (Original: mc_H7)
            sd_dat2_out_data <= (GP_22 or sd_dat2_state or address_load_sync2 or gba_bus_idle_sync_d1 or not gba_bus_idle_sync)
                and (not GP_22 or address_load_sync2 or sd_dat1_out_data or gba_bus_idle_sync_d1 or not gba_bus_idle_sync)
                and (GP(6) or GP_19 or not address_load_sync2 or address_load_sync)
                and (not GP_19 or not address_load_sync2 or sd_dat2_out_data)
                and (address_load_sync2 or sd_dat2_out_data or gba_bus_idle_sync)
                and (address_load_sync2 or sd_dat2_out_data or not gba_bus_idle_sync_d1);

            -- Common Logic for CMD and DAT3 (Original: mc_H9)
            sd_common_out_logic <= (GP_22 or sd_dat3_state or address_load_sync2 or gba_bus_idle_sync_d1 or not gba_bus_idle_sync)
                and (not GP_22 or address_load_sync2 or sd_dat2_out_data or gba_bus_idle_sync_d1 or not gba_bus_idle_sync)
                and (GP(7) or GP_19 or not address_load_sync2 or address_load_sync)
                and (not GP_19 or not address_load_sync2 or sd_common_out_logic)
                and (address_load_sync2 or sd_common_out_logic or gba_bus_idle_sync)
                and (address_load_sync2 or sd_common_out_logic or not gba_bus_idle_sync_d1);
        end if;
    end process;
    
    -- In the original design, H6 and H8 are directly fed by H9.
    sd_dat3_out_data <= sd_common_out_logic; -- Original: mc_H6 <= mc_H9
    sd_cmd_out_data  <= sd_common_out_logic; -- Original: mc_H8 <= mc_H9

    -- SD Output Enable Control
    sd_mode_active  <= not sd_output_enable;
    sd_write_active <= not GP_NWR and sd_mode_active;

    -- CMD Line OE: Active during a write in Command mode (GP_22=1).
    sd_cmd_oe <= sd_write_active and GP_22;
    
    -- DAT Lines OE: Active during a write in Data mode (GP_22=0).
    sd_data_oe <= (others => (sd_write_active and not GP_22));
    
    -- Tri-state Buffers for Physical SD Lines
    SD_CMD    <= sd_cmd_out_data  when sd_cmd_oe = '1' else 'Z';
    SD_DAT(0) <= sd_dat0_out_data when sd_data_oe(0) = '1' else 'Z';
    SD_DAT(1) <= sd_dat1_out_data when sd_data_oe(1) = '1' else 'Z';
    SD_DAT(2) <= sd_dat2_out_data when sd_data_oe(2) = '1' else 'Z';
    SD_DAT(3) <= sd_dat3_out_data when sd_data_oe(3) = '1' else 'Z';

end behavioral;
