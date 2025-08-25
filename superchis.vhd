library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity superchis is
    port (
        -- Global Clocks and Control / 全局时钟与控制信号
        CLK50MHz : in  std_logic;  -- 50MHz main clock input / 50MHz 主时钟输入
        GP_NCS   : in  std_logic;  -- GBA Cartridge Chip Select (Active Low) / GBA卡带片选 (低电平有效)
        GP_NCS2_EXT  : in  std_logic;
        GP_NCS2  : out  std_logic;
        GP_NWR   : in  std_logic;  -- GBA Write Enable (Active Low) / GBA写使能 (低电平有效)
        GP_NRD   : in  std_logic;  -- GBA Read Enable (Active Low) / GBA读使能 (低电平有效)
        -- clk3     : in  std_logic;  -- Auxiliary Clock (Original design dependency) / 辅助时钟 (源于原始设计)

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
        FLASH_HIGH       : out std_logic_vector(4 downto 0);   -- Flash High Bank Select (5 bits for 32 banks) / 闪存Bank选择 (5位用于32个Bank)
        FLASH_NCE        : out std_logic;                       -- Flash Chip Enable (Active Low) / 闪存片选 (低电平有效)
        FLASH_SRAM_NWE   : out std_logic;                       -- Flash/SRAM Write Enable (Active Low) / 闪存/SRAM 写使能 (低电平有效)
        FLASH_SRAM_NOE   : out std_logic;                       -- Flash/SRAM Output Enable (Active Low) / 闪存/SRAM 输出使能 (低电平有效)
        SRAM_A16         : out std_logic;                       -- SRAM High Address bit (for banking) / SRAM 高位地址 (用于Bank切换)

        -- SD Card Interface / SD卡接口
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
    -- Constants / 常量定义
    -- ========================================================================
    
    ------ W9825G6KH-6I Timing Parameters / W9825G6KH-6I 时序参数
    --- CLK Cycle Time (tCK): 20ns(50MHz) 6ns(166.67MHz)
    --- Ref/Active to Ref/Active Command Period (tRC): 60ns
    --- Active to precharge Command Period (tRAS): 42ns
    --- Active to Read/Write Command Delay Time (tRCD): 18ns
    --- Read/Write(a) to Read/Write(b) Command Period (tCCD): 1tCK
    --- Precharge to Active Command Period (tRP): 18ns
    --- Active(a) to Active(b) Command Period (tRRD): 2tCK
    --- Write Recovery Time (tWR): 2tCK
    -- 时序参数常量 (基于50MHz时钟，20ns周期)
    -- 注意：这些是实际需要等待的周期数
    constant tRC_CYCLES  : unsigned(3 downto 0) := to_unsigned(3, 4);  -- 60ns / 20ns = 3
    constant tRAS_CYCLES : unsigned(3 downto 0) := to_unsigned(3, 4);  -- 42ns / 20ns = 2.1, 向上取整到3
    constant tRCD_CYCLES : unsigned(3 downto 0) := to_unsigned(1, 4);  -- 18ns / 20ns = 0.9, 向上取整到1
    constant tRP_CYCLES  : unsigned(3 downto 0) := to_unsigned(1, 4);  -- 18ns / 20ns = 0.9, 向上取整到1
    constant tRRD_CYCLES : unsigned(3 downto 0) := to_unsigned(2, 4);  -- 2 * tCK = 2周期
    constant tWR_CYCLES  : unsigned(3 downto 0) := to_unsigned(2, 4);  -- 2 * tCK = 2周期
    constant REFRESH_INTERVAL : unsigned(11 downto 0) := to_unsigned(390, 12); -- 7.8125us / 20ns ≈ 390 cycles

    -- ========================================================================
    -- Internal Signals / 内部信号
    -- ========================================================================
    
    -- Configuration Registers / 配置寄存器
    -- These registers are set via the magic unlock sequence. / 这些寄存器通过“魔术解锁序列”设置。
    signal config_map_reg     : std_logic := '0';          -- Memory map control: 0=Flash, 1=DDR / 内存映射控制
    signal config_sd_enable   : std_logic := '0';          -- SD Card I/O interface enable / SD卡IO接口使能
    signal config_write_enable: std_logic := '0';          -- General write enable (used for SRAM A16, etc.) / 通用写使能 (用于SRAM A16等)
    signal config_bank_select : std_logic_vector(4 downto 0) := "00000";  -- Flash memory bank selection bits / Flash闪存的Bank选择位 (mc_C10, mc_G14, mc_D9, mc_B15, mc_C9)
    signal flash_high_tmp     : unsigned(4 downto 0) := (others => '0'); -- 5位高位Bank选择寄存器
    
    -- Magic Unlock Sequence / 魔术解锁序列
    -- Logic to detect the specific address/data sequence to unlock configuration. / 用于检测特定地址/数据序列以解锁配置功能的逻辑。
    signal magic_address      : std_logic := '0';          -- Detects access to the magic address (0x09FFFFFE) / 检测是否访问魔术地址
    signal magic_value_match  : std_logic := '0';          -- Detects the magic value (0xA55A) on the data bus / 检测总线上是否出现魔术值
    signal magic_write_count  : unsigned(1 downto 0) := "00"; -- Counts the magic value writes (requires 2) / 对魔术值写入次数进行计数 (需要2次)
    
    -- Address Management / 地址管理
    signal internal_address   : unsigned(15 downto 0) := (others => '0');  -- Internal 16-bit address counter / 内部16位地址计数器
    signal flash_address      : std_logic_vector(15 downto 0);  -- Address bus going to the Flash chip / 连接到Flash芯片的地址总线
    
    -- 50MHz Clock Driven DDR Control Signals / 50MHz时钟驱动的DDR控制信号
    signal refresh_counter : unsigned(11 downto 0) := (others => '0'); -- 刷新计数器
    -- DDR Control Signals / DDR控制信号
    signal ddr_need_refresh : std_logic := '0';
    
    -- DDR Address and Control Registers / DDR地址和控制寄存器
    signal ddr_addr_reg : std_logic_vector(12 downto 0) := (others => '0');
    signal ddr_ba_reg   : std_logic_vector(1 downto 0) := (others => '0');
    signal ddr_cke_reg  : std_logic := '1';
    signal ddr_ras_reg  : std_logic := '1';
    signal ddr_cas_reg  : std_logic := '1';
    signal ddr_we_reg   : std_logic := '1';
    
    -- DDR chip select signal
    signal n_ddr_sel : std_logic := '1';  -- DDR not selected (active low)
    
    
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
    signal gba_bus_idle_sync_d1       : std_logic := '1';           -- Timing sync stage (original: mc_H14) / 时序同步级
    signal gba_bus_idle_sync       : std_logic := '1';           -- Timing sync stage (original: mc_H15) / 时序同步级
    signal addr_clock         : std_logic := '0';          -- Composite clock for address counter (original: mc_H11) / 地址计数器的组合时钟 (原始: mc_H11)  
    
    -- SD Interface - Simplified GPIO Mapping Signals / SD接口 - 简化GPIO映射信号
    signal sd_clk_out         : std_logic := '0';           -- SD clock output register / SD时钟输出寄存器
    signal sd_cmd_out     : std_logic := '1';           -- SD CMD output register / SD CMD输出寄存器
    signal sd_dat_out     : std_logic_vector(3 downto 0) := (others => '1'); -- SD DAT output register / SD DAT输出寄存器
    signal sd_cmd_oe      : std_logic := '0';           -- SD CMD output enable register / SD CMD输出使能寄存器
    signal sd_dat_oe      : std_logic_vector(3 downto 0) := (others => '0'); -- SD DAT output enable register / SD DAT输出使能寄存器
    signal sd_mode_active     : std_logic;                   -- SD mode active flag / SD模式激活标志
    signal sd_write_active    : std_logic;                   -- SD write operation active / SD写操作激活
    signal sd_read_active     : std_logic;                   -- SD read operation active / SD读操作激活

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
    
    -- DDR selection signal (active low) / DDR选择信号 (低电平有效)
    n_ddr_sel <= not config_map_reg;

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
                        config_map_reg      <= GP(0);
                        config_sd_enable    <= GP(1);
                        config_write_enable <= GP(2);
                        config_bank_select(4 downto 0) <= GP(7 downto 3); -- Load bank select bits from GP(3) to GP(7)
                        -- -- Faithfully reconstruct the original's complex flash banking logic.
                        -- -- 忠实地重构原始设计中复杂的Flash Bank逻辑。
                        -- config_bank_select(0) <= GP(4) and not GP(8) and GP(12);   -- mc_C10
                        -- config_bank_select(1) <= GP(7) and not GP(10) and GP(11);  -- mc_G14
                        -- config_bank_select(2) <= GP(7) and GP(9) and not GP(15);   -- mc_D9
                        -- config_bank_select(3) <= GP(6) and not GP(13) and GP(12);  -- mc_B15
                        -- config_bank_select(4) <= GP(4) and not GP(5) and GP(14);   -- mc_C9
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
    GP_NCS2 <= GP_NCS2_EXT; -- 直接连接外部NCS2信号
    -- SRAM A16 is controlled by write enable config bit for banking
    -- SRAM A16由写使能配置位控制，用于Bank切换
    SRAM_A16 <= config_write_enable;
    -- 高位Bank
    -- 通过配置使得高位Bank可以进行0~31的偏移，即 FLASH_HIGH = unsigned(NOR_A25,NOR_A24,GP_23~GP_21) + BANK_OFFSET
    process(internal_address, config_bank_select, GP_21, GP_22, GP_23)
    begin
        -- 直接映射高位Bank选择
        flash_high_tmp(0) <= GP_21;
        flash_high_tmp(1) <= GP_22;
        flash_high_tmp(2) <= GP_23;
        flash_high_tmp(3) <= '0'; -- Reserved, not used in this design
        flash_high_tmp(4) <= '0'; -- Reserved, not used in this design
        FLASH_HIGH <= std_logic_vector(flash_high_tmp + unsigned(config_bank_select));
    end process;
    flash_address <= std_logic_vector(internal_address);
    FLASH_A <= flash_address;
    -- ---- 以下是旧版SuperCard的逻辑
    -- process(internal_address, config_bank_select, current_mode, config_write_enable)
    -- begin
    --     if current_mode = MODE_FLASH then
    --         -- Direct implementation based on CPLD report address scrambling and banking
    --         -- 基于CPLD报告的地址重映射与Bank选择的直接实现

    --         -- Direct Scrambling / 直接重映射
    --         flash_address(0)  <= internal_address(7);  -- FLASH-A0 = iaddr-a7
    --         flash_address(2)  <= internal_address(6);  -- FLASH-A2 = iaddr-a6
    --         flash_address(4)  <= internal_address(0);  -- FLASH-A4 = iaddr-a0
    --         flash_address(5)  <= internal_address(2);  -- FLASH-A5 = iaddr-a2
    --         flash_address(8)  <= internal_address(3);  -- FLASH-A8 = iaddr-a3
    --         flash_address(10) <= internal_address(10); -- FLASH-A10 = iaddr-a10
    --         flash_address(12) <= internal_address(12); -- FLASH-A12 = iaddr-a12
    --         flash_address(13) <= internal_address(13); -- FLASH-A13 = iaddr-a13

    --         -- Scrambling combined with Banking Logic (OR logic from report)
    --         -- 与Bank逻辑结合的重映射部分（来自报告的“或”逻辑）
    --         flash_address(1)  <= internal_address(1); -- or config_bank_select(3); -- FLASH-A1 = mc_C1 = mc_B15 | iaddr-a1
    --         flash_address(3)  <= internal_address(5); -- or config_bank_select(3) or config_bank_select(4); -- FLASH-A3 = mc_C15 = mc_B15 | iaddr-a5 | mc_C9
    --         flash_address(6)  <= internal_address(8); -- or config_bank_select(4) ; -- FLASH-A6 = mc_C8 = mc_C9 | iaddr-a8
    --         flash_address(7)  <= internal_address(4); --  or config_bank_select(0); -- FLASH-A7 = mc_D1 = iaddr-a4 | mc_C10
    --         flash_address(11) <= internal_address(11); -- or config_bank_select(2); -- FLASH-A11 = mc_D2 = iaddr-a11 | mc_D9
    --         flash_address(14) <= internal_address(14); -- or config_bank_select(1); -- FLASH-A14 = mc_C6 = iaddr-a14 | mc_G14
    --         flash_address(15) <= internal_address(15); -- or config_bank_select(0) or config_bank_select(1) or config_bank_select(2); -- FLASH-A15 = mc_D0 = mc_C10 | iaddr-a15 | mc_D9 | mc_G14
    --         -- Gated Logic (AND logic from report)
    --         -- 门控逻辑部分（来自报告的“与”逻辑）
    --         flash_address(9)  <= internal_address(9); -- and config_write_enable; -- FLASH-A9 = mc_E7 = iaddr-a9 & WRITEENABLE
    --     else
    --         -- In non-Flash modes, pass the address through directly.
    --         -- 在非Flash模式下，直接透传地址。
    --         flash_address <= std_logic_vector(internal_address);
    --     end if;
    -- end process;
    

    -- ========================================================================
    -- DDR SDRAM Controller - 完全基于原始CPLD方程重构
    -- DDR SDRAM Controller - Complete reconstruction based on original CPLD equations
    -- 完全按照 original_report.html 中的方程重构
    -- Fully reconstructed according to equations in original_report.html
    -- ========================================================================

    -- DDR Chip Select Logic (from original mc_E4)
    -- DDR片选逻辑 (来自原始 mc_E4)
    n_ddr_sel <= GP_NCS or not config_map_reg or (config_sd_enable and GP_23);
    
    -- ========================================================================
    -- New DDR SDRAM Controller - GBA Synchronized Design
    -- 新的DDR SDRAM控制器 - 与GBA同步的设计
    -- ========================================================================
    
    -- DDR刷新计数器 (运行在50MHz时钟域)
    ddr_refresh_counter: process(CLK50MHz)
    begin
        if rising_edge(CLK50MHz) then
            refresh_counter <= refresh_counter + 1;
            if refresh_counter >= REFRESH_INTERVAL then
                refresh_counter <= (others => '0');
                ddr_need_refresh <= '1';
            end if;
            
            -- 清除刷新请求, 一次刷新持续tRC_CYCLES
            if ddr_need_refresh = '1' and refresh_counter >= tRC_CYCLES then
                ddr_need_refresh <= '0';
            end if;
        end if;
    end process;
    
    -- ========================================================================
    -- DDR SDRAM Controller - 时钟同步的寄存器输出设计
    -- DDR SDRAM Controller - Clock-synchronized register output design
    -- 使用50MHz时钟同步所有DDR输出，避免组合逻辑的不稳定性
    -- Use 50MHz clock to synchronize all DDR outputs, avoiding combinational logic instability
    -- ========================================================================

    -- DDR控制器主进程 - 50MHz时钟同步
    -- DDR Controller Main Process - 50MHz clock synchronized
    ddr_controller: process(CLK50MHz)
    begin
        if rising_edge(CLK50MHz) then
            -- read_sync  <= GP_NRD;
            
            -- Address load synchronization chain (original: mc_H10 -> mc_H5)
            -- 地址加载同步链
            address_load_sync2 <= address_load_sync;
            address_load_sync <= address_load;
            
            -- Timing synchronization stages (original: mc_H14, mc_H15)
            -- 时序同步级
            gba_bus_idle_sync_d1 <= gba_bus_idle_sync;
            gba_bus_idle_sync <= GP_NWR and GP_NRD;
            
            if config_map_reg = '1' then  -- DDR模式
                ddr_cke_reg <= '1';  -- 时钟始终使能
                -- 刷新优先级最高
                if ddr_need_refresh = '1' and GP_NCS = '1' then
                    -- AUTO REFRESH命令 (只在总线空闲时执行)
                    ddr_ras_reg <= '0';  -- RAS低电平
                    ddr_cas_reg <= '0';  -- CAS低电平
                    ddr_we_reg  <= '1';  -- WE高电平
                    ddr_addr_reg <= (others => '0');
                    ddr_ba_reg <= (others => '0');
                elsif GP_NCS = '0' then  -- GBA访问期间
                    if gba_bus_idle_sync  = '0' then
                        -- READ命令
                        ddr_ras_reg <= '1';  -- RAS高电平
                        ddr_cas_reg <= '0';  -- CAS低电平
                        ddr_we_reg  <= GP_NWR;  -- WE高电平
                        if gba_bus_idle_sync_d1 = '1' then
                            -- 列地址
                            ddr_addr_reg(12) <= '0';
                            ddr_addr_reg(11) <= '0';
                            ddr_addr_reg(10) <= '0';  -- A10=0表示非auto-precharge
                            ddr_addr_reg(9)  <= '0';
                            ddr_addr_reg(8)  <= internal_address(8);
                            ddr_addr_reg(7)  <= internal_address(7);
                            ddr_addr_reg(6)  <= internal_address(6);
                            ddr_addr_reg(5)  <= internal_address(5);
                            ddr_addr_reg(4)  <= internal_address(4);
                            ddr_addr_reg(3)  <= internal_address(3);
                            ddr_addr_reg(2)  <= internal_address(2);
                            ddr_addr_reg(1)  <= internal_address(1);
                            ddr_addr_reg(0)  <= internal_address(0);
                        end if;
                    else
                        -- ACTIVE命令 (地址阶段)
                        ddr_ras_reg <= '0';  -- RAS低电平
                        ddr_cas_reg <= '1';  -- CAS高电平
                        ddr_we_reg  <= '1';  -- WE高电平
                        -- 行地址
                        ddr_addr_reg(12) <= GP_21;
                        ddr_addr_reg(11) <= GP_20;
                        ddr_addr_reg(10) <= GP_19;
                        ddr_addr_reg(9)  <= GP_18;
                        ddr_addr_reg(8)  <= GP_17;
                        ddr_addr_reg(7)  <= GP_16;
                        ddr_addr_reg(6)  <= internal_address(15);
                        ddr_addr_reg(5)  <= internal_address(14);
                        ddr_addr_reg(4)  <= internal_address(13);
                        ddr_addr_reg(3)  <= internal_address(12);
                        ddr_addr_reg(2)  <= internal_address(11);
                        ddr_addr_reg(1)  <= internal_address(10);
                        ddr_addr_reg(0)  <= internal_address(9);
                    end if;
                    -- Bank地址使用最高位
                    ddr_ba_reg(1) <= GP_23;
                    ddr_ba_reg(0) <= GP_22;
                else
                    -- 空闲状态，NOP命令
                    ddr_ras_reg <= '1';
                    ddr_cas_reg <= '1';
                    ddr_we_reg  <= '1';
                    ddr_addr_reg <= (others => '0');
                    ddr_ba_reg <= (others => '0');
                end if;
            else
                -- 非DDR模式时保持DDR初始化状态和刷新
                -- Keep DDR in initialized state and refreshed during non-DDR modes
                ddr_cke_reg  <= '1';  -- 保持时钟使能，维持DDR初始化状态
                
                -- 在非DDR模式下仍然执行刷新操作
                if ddr_need_refresh = '1' then
                    -- AUTO REFRESH命令
                    ddr_ras_reg <= '0';  -- RAS低电平
                    ddr_cas_reg <= '0';  -- CAS低电平
                    ddr_we_reg  <= '1';  -- WE高电平
                    ddr_addr_reg <= (others => '0');
                    ddr_ba_reg <= (others => '0');
                else
                    -- 空闲状态，NOP命令
                    ddr_ras_reg <= '1';
                    ddr_cas_reg <= '1';
                    ddr_we_reg  <= '1';
                    ddr_addr_reg <= (others => '0');
                    ddr_ba_reg <= (others => '0');
                end if;
            end if;
        end if;
    end process;
    
    -- 将寄存器输出连接到DDR接口
    -- Connect register outputs to DDR interface
    DDR_A    <= ddr_addr_reg;
    DDR_BA   <= ddr_ba_reg;
    DDR_CKE  <= ddr_cke_reg;
    DDR_NRAS <= ddr_ras_reg;
    DDR_NCAS <= ddr_cas_reg;
    DDR_NWE  <= ddr_we_reg;

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
    FLASH_NCE <= GP_NCS or config_map_reg or (config_sd_enable and GP_23); -- or clk3

    -- SD I/O mode detection
    -- SD I/O模式检测
    
    sd_output_enable <= GP_NCS or not GP_23 or not config_sd_enable or magic_address;
    
    -- Pass through GBA R/W signals to Flash/SRAM directly.
    -- 将GBA的读写信号直接透传给Flash/SRAM。
    FLASH_SRAM_NWE <= GP_NWR;
    FLASH_SRAM_NOE <= GP_NRD;

    -- ========================================================================
    -- GP Bus Output Control / GP总线输出控制
    -- Controls when the CPLD drives data onto the GBA's GP data bus.
    -- 控制CPLD何时将数据驱动到GBA的GP数据总线上。
    -- ========================================================================
    
    -- The GP bus is driven during GBA read cycles in SD mode
    -- GP总线在SD模式的GBA读周期时由本芯片驱动
    gp_output_enable <= '1' when (GP_NRD = '0' and (current_mode = MODE_SD)) else '0';

    -- GP bus tri-state control. Drive the bus when enabled, otherwise high-impedance.
    -- GP总线三态控制。使能时驱动总线，否则为高阻态。
    GP <= gp_output_data when gp_output_enable = '1' else (others => 'Z');

    -- ========================================================================
    -- SD Card Interface - Simplified GPIO Mapping
    -- SD卡接口 - 简化的GPIO映射
    -- 直接将GBA地址/数据位映射到SD卡引脚，简化复杂的状态机逻辑
    -- Direct mapping of GBA address/data bits to SD card pins, simplifying complex state machine logic
    -- ========================================================================
    
    -- SD模式激活检测
    -- SD mode activation detection
    sd_mode_active <= '1' when (config_sd_enable = '1' and GP_23 = '1' and GP_NCS = '0') else '0';
    sd_write_active <= sd_mode_active and (not GP_NWR);
    sd_read_active <= sd_mode_active and (not GP_NRD);
    
    -- SD时钟生成 - 简单的组合逻辑
    -- SD Clock Generation - Simple combinational logic
    SD_CLK <= sd_clk_out when sd_mode_active = '1' else 'Z';
    
    -- SD写操作 - 将GP数据位映射到SD引脚
    -- SD Write Operation - Map GP data bits to SD pins
    sd_write_process: process(CLK50MHz)
    begin
        if rising_edge(CLK50MHz) then
            if sd_write_active = '1' then
                -- 根据地址低位选择控制模式
                case internal_address(2 downto 0) is
                    when "000" => -- 地址偏移0: 控制SD_CLK
                        sd_clk_out <= GP(0);
                        
                    when "001" => -- 地址偏移1: 控制SD_CMD
                        sd_cmd_out <= GP(0);
                        sd_cmd_oe <= GP(4);  -- 使用GP(4)控制CMD输出使能
                        
                    when "010" => -- 地址偏移2: 控制SD_DAT
                        sd_dat_out <= GP(3 downto 0);
                        sd_dat_oe <= GP(7 downto 4);  -- 使用GP(7:4)控制DAT输出使能
                        
                    when "011" => -- 地址偏移3: 组合控制
                        sd_cmd_out <= GP(0);
                        sd_dat_out <= GP(4 downto 1);
                        sd_cmd_oe <= GP(8);
                        sd_dat_oe <= GP(12 downto 9);
                        
                    when others => -- 其他地址: 保持当前状态
                        null;
                end case;
            end if;
        end if;
    end process;
    
    -- SD读操作 - 将SD引脚状态映射到GP总线
    -- SD Read Operation - Map SD pin states to GP bus
    sd_read_process: process(sd_read_active, internal_address, SD_CMD, SD_DAT, sd_cmd_out, sd_dat_out, sd_cmd_oe, sd_dat_oe)
    begin
        if sd_read_active = '1' then
            case internal_address(2 downto 0) is
                when "000" => -- 地址偏移0: 读取SD引脚输入状态
                    gp_output_data(0) <= SD_CMD;
                    gp_output_data(4 downto 1) <= SD_DAT;
                    gp_output_data(15 downto 5) <= (others => '0');
                    
                when "001" => -- 地址偏移1: 读取SD引脚输出状态
                    gp_output_data(0) <= sd_cmd_out;
                    gp_output_data(4 downto 1) <= sd_dat_out;
                    gp_output_data(8) <= sd_cmd_oe;
                    gp_output_data(12 downto 9) <= sd_dat_oe;
                    gp_output_data(15 downto 13) <= (others => '0');
                    gp_output_data(7 downto 5) <= (others => '0');
                    
                when "010" => -- 地址偏移2: 混合状态 (输入+输出)
                    gp_output_data(0) <= SD_CMD;
                    gp_output_data(1) <= sd_cmd_out;
                    gp_output_data(2) <= sd_cmd_oe;
                    gp_output_data(6 downto 3) <= SD_DAT;
                    gp_output_data(10 downto 7) <= sd_dat_out;
                    gp_output_data(14 downto 11) <= sd_dat_oe;
                    gp_output_data(15) <= '0';
                    
                when others => -- 其他地址: 返回状态信息
                    gp_output_data(0) <= sd_mode_active;
                    gp_output_data(1) <= sd_write_active;
                    gp_output_data(2) <= sd_read_active;
                    gp_output_data(15 downto 3) <= (others => '0');
            end case;
        else
            gp_output_data <= (others => '0');
        end if;
    end process;
    
    -- SD引脚三态控制
    -- SD Pin Tri-state Control
    SD_CMD <= sd_cmd_out when sd_cmd_oe = '1' else 'Z';
    SD_DAT(0) <= sd_dat_out(0) when sd_dat_oe(0) = '1' else 'Z';
    SD_DAT(1) <= sd_dat_out(1) when sd_dat_oe(1) = '1' else 'Z';
    SD_DAT(2) <= sd_dat_out(2) when sd_dat_oe(2) = '1' else 'Z';
    SD_DAT(3) <= sd_dat_out(3) when sd_dat_oe(3) = '1' else 'Z';

end behavioral;
