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

    -- SDRAM State Machine Types / SDRAM状态机类型
    type sdram_state_t is (
        SDRAM_POWER_UP,      -- 上电状态：等待200us初始化延迟
        SDRAM_PRECHARGE_ALL, -- 预充电所有Bank
        SDRAM_AUTO_REFRESH,  -- 执行8次自动刷新
        SDRAM_MODE_REG_SET,  -- 设置模式寄存器
        SDRAM_IDLE          -- 空闲状态：等待访问请求
    );

    -- SD Access Type / SD访问类型
    type sd_access_type_t is (
        SD_ACCESS_NONE, -- No SD access / 无SD访问
        SD_ACCESS_CMD,  -- Accessing command register / 访问命令寄存器
        SD_ACCESS_READ,  -- Accessing data register / 访问数据寄存器
        SD_ACCESS_WRITE  -- Accessing data register / 访问数据寄存器
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
    constant tRC_CYCLES  : unsigned(3 downto 0) := to_unsigned(2, 4);  -- 60ns / 20ns = 3
    constant tRAS_CYCLES : unsigned(3 downto 0) := to_unsigned(2, 4);  -- 42ns / 20ns = 2.1, 向上取整到3
    constant tRCD_CYCLES : unsigned(3 downto 0) := to_unsigned(0, 4);  -- 18ns / 20ns = 0.9, 向上取整到1
    constant tRP_CYCLES  : unsigned(3 downto 0) := to_unsigned(0, 4);  -- 18ns / 20ns = 0.9, 向上取整到1
    constant tRRD_CYCLES : unsigned(3 downto 0) := to_unsigned(1, 4);  -- 2 * tCK = 2周期
    constant tWR_CYCLES  : unsigned(3 downto 0) := to_unsigned(1, 4);  -- 2 * tCK = 2周期
    constant REFRESH_INTERVAL : unsigned(8 downto 0) := to_unsigned(384, 9); -- 7.8125us / 20ns ≈ 384 cycles

    -- ========================================================================
    -- Internal Signals / 内部信号
    -- ========================================================================
    
    -- Configuration Registers / 配置寄存器
    -- These registers are set via the magic unlock sequence. / 这些寄存器通过“魔术解锁序列”设置。
    signal config_map_reg     : std_logic := '0';          -- Memory map control: 0=Flash, 1=DDR / 内存映射控制
    signal config_sd_enable   : std_logic := '0';          -- SD Card I/O interface enable / SD卡IO接口使能
    signal config_write_enable: std_logic := '0';          -- General write enable (used for SRAM A16, etc.) / 通用写使能 (用于SRAM A16等)
    signal config_sram_bank   : std_logic := '0';          -- SRAM Bank selection / SRAM Bank选择
    signal config_bank_select : std_logic_vector(4 downto 0) := "00000";  -- Flash memory bank selection bits / Flash闪存的Bank选择位 (mc_C10, mc_G14, mc_D9, mc_B15, mc_C9)
    signal flash_high_tmp     : unsigned(4 downto 0) := (others => '0'); -- 5位高位Bank选择寄存器
    
    -- Magic Unlock Sequence / 魔术解锁序列
    -- Logic to detect the specific address/data sequence to unlock configuration. / 用于检测特定地址/数据序列以解锁配置功能的逻辑。
    signal magic_address      : std_logic := '0';          -- Detects access to the magic address (0x09FFFFFE) / 检测是否访问魔术地址
    signal bootleg_sram_bank_address      : std_logic := '0';    -- Detects access to the bootleg bank switch address (0x09000000) / 检测是否访问bank切换地址

    signal magic_value_match  : std_logic := '0';          -- Detects the magic value (0xA55A) on the data bus / 检测总线上是否出现魔术值
    signal magic_write_count  : unsigned(1 downto 0) := "00"; -- Counts the magic value writes (requires 2) / 对魔术值写入次数进行计数 (需要2次)
    
    -- Address Management / 地址管理
    signal internal_address   : unsigned(15 downto 0) := (others => '0');  -- Internal 16-bit address counter / 内部16位地址计数器
    signal flash_address      : std_logic_vector(15 downto 0);  -- Address bus going to the Flash chip / 连接到Flash芯片的地址总线
    
    -- 50MHz Clock Driven DDR Control Signals / 50MHz时钟驱动的DDR控制信号
    
    -- SDRAM Timing Control Signals / SDRAM时序控制信号
    signal refresh_counter    : unsigned(8 downto 0) := (others => '0'); -- 刷新计数器
    signal refresh_needed     : std_logic := '0';                        -- 刷新挂起标志
    signal ddr_cycle_counter      : unsigned(3 downto 0) := (others => '0');

    -- DDR Address and Control Registers / DDR地址和控制寄存器
    signal ddr_addr_reg : std_logic_vector(12 downto 0) := (others => '0');
    signal ddr_ba_reg   : std_logic_vector(1 downto 0) := (others => '0');
    signal ddr_cke_reg  : std_logic := '0';
    signal ddr_ras_reg  : std_logic := '1';
    signal ddr_cas_reg  : std_logic := '1';
    signal ddr_we_reg   : std_logic := '1';
    
    -- SDRAM State Machine and Initialization / SDRAM状态机与初始化
    signal sdram_state : sdram_state_t := SDRAM_POWER_UP;
    
    -- DDR chip select signal
    signal n_ddr_sel : std_logic := '1';  -- DDR not selected (active low)
    
    -- Bus Control / 总线控制
    signal sd_io_buffer     : std_logic_vector(15 downto 0) := (others => '0'); -- Data to be driven onto the GP bus / 将要驱动到GP总线上的数据
    
    -- Timing Control (Synchronizers) / 时序控制 (同步器)
    -- These signals are synchronized versions of GBA bus signals, used to avoid metastability. / GBA总线信号的同步版本，用于避免亚稳态。
    signal address_load       : std_logic := '0';           -- Latched signal indicating address phase / 标志地址阶段的锁存信号
    signal address_load_sync  : std_logic := '0';           -- First stage sync (original: mc_H10) / 第一级同步
    signal address_load_sync2 : std_logic := '0';           -- Second stage sync (original: mc_H5) / 第二级同步
    signal gba_bus_idle_sync_d1       : std_logic := '1';           -- Timing sync stage (original: mc_H14) / 时序同步级
    signal gba_bus_idle_sync       : std_logic := '1';           -- Timing sync stage (original: mc_H15) / 时序同步级
    signal gba_bus_wr_sync       : std_logic := '1';           -- Timing sync stage (original: mc_H15) / 时序同步级
    signal gba_bus_rd_sync       : std_logic := '1';           -- Timing sync stage (original: mc_H15) / 时序同步级
    signal addr_clock         : std_logic := '0';          -- Composite clock for address counter (original: mc_H11) / 地址计数器的组合时钟 (原始: mc_H11)  
    
    -- SD Interface - Clean forward implementation based on reverse analysis
    -- SD接口 - 基于逆向分析的正向清洁实现
    -- 分离的移位寄存器：SD.reg1用于输出，SD.reg2用于输入
    signal sd_output_shift_reg : std_logic_vector(3 downto 0) := (others => '1'); -- 输出移位寄存器 (原SD.reg1)
    signal sd_cmd_output       : std_logic := '1';                                 -- CMD输出缓冲
    signal sd_dat_output       : std_logic_vector(3 downto 0) := "1111";          -- DAT输出缓冲
    signal n_sd_mode_active    : std_logic;                                        -- SD模式激活标志
    
    -- Timing and control signals / 时序与控制信号
    signal sd_access_type      : sd_access_type_t;                                 -- SD访问类型
    
    -- Buffer for GBA data output / GBA数据输出缓冲
    signal sd_read_buffer      : std_logic_vector(15 downto 0) := (others => '0');

begin

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
    
    bootleg_sram_bank_address <= '1' when (internal_address = x"0000"and
                               GP_16 = '0' and GP_17 = '0' and GP_18 = '0' and GP_19 = '0' and
                               GP_20 = '0' and GP_21 = '0' and GP_22 = '0' and GP_23 = '1') else '0';
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
                    when "10" => -- Expect first config value. / 等待第一个配置值
                        magic_write_count   <= "11";
                    when "11" => -- Expect second config value, load it, then reset sequence. / 等待第二个配置值，加载然后复位序列
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
                        magic_write_count <= "00";
                    when others =>
                        magic_write_count <= "00";
                end case;
            elsif bootleg_sram_bank_address = '1' then
                if config_write_enable = '0' then
                    config_sram_bank <= GP(0);
                end if;
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
    -- 如果写使能未激活，则使用Bank选择信号
    SRAM_A16 <= config_write_enable or config_sram_bank;
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

    sdram_syncer: process(CLK50MHz)
    begin
        if rising_edge(CLK50MHz) then
            -- 同步GBA信号
            address_load_sync2 <= address_load_sync;
            address_load_sync <= address_load;
            gba_bus_idle_sync_d1 <= gba_bus_idle_sync;
            gba_bus_idle_sync <= GP_NWR and GP_NRD;
            gba_bus_wr_sync <= GP_NWR or not config_write_enable;
            gba_bus_rd_sync <= GP_NRD;
            -- DDR Chip Select Logic (from original mc_E4)
            -- DDR片选逻辑 (来自原始 mc_E4)
            n_ddr_sel <= GP_NCS or not config_map_reg or (config_sd_enable and GP_23);
        end if;
    end process;

    -- SDRAM Controller Process / SDRAM控制器进程
    sdram_controller: process(CLK50MHz)
    begin
        if falling_edge(CLK50MHz) then
            case sdram_state is
                -- =============================================================
                -- 初始化序列 / Initialization Sequence
                -- =============================================================
                when SDRAM_POWER_UP =>
                    -- 上电延迟200us，但可以近似成GBA CPU启动
                    ddr_cke_reg <= '0';  -- CKE低电平
                    ddr_ras_reg <= '1';  -- NOP命令
                    ddr_cas_reg <= '1';
                    ddr_we_reg  <= '1';
                    ddr_addr_reg <= (others => '0');
                    ddr_ba_reg <= (others => '0');

                    if gba_bus_idle_sync = '0' then -- 第一次读写发生
                        sdram_state <= SDRAM_PRECHARGE_ALL;
                    end if;
                    
                when SDRAM_PRECHARGE_ALL =>
                    -- 预充电所有Bank
                    ddr_cke_reg <= '1';  -- 使能时钟
                    ddr_ras_reg <= '0';  -- PRECHARGE命令
                    ddr_cas_reg <= '1';
                    ddr_we_reg  <= '0';
                    ddr_addr_reg <= (others => '0');
                    ddr_addr_reg(10) <= '1';  -- A10=1表示预充电所有Bank
                    ddr_ba_reg <= (others => '0');

                    if gba_bus_idle_sync = '1' then -- 第一次读写结束
                        sdram_state <= SDRAM_AUTO_REFRESH;
                    end if;
                    
                when SDRAM_AUTO_REFRESH =>
                    -- 执行自动刷新直到解锁
                    ddr_ras_reg <= '0';  -- AUTO REFRESH命令
                    ddr_cas_reg <= '0';
                    ddr_we_reg  <= '1';
                    ddr_addr_reg <= (others => '0');
                    ddr_ba_reg <= (others => '0');

                    if magic_value_match = '1' and magic_address = '1' then
                        sdram_state <= SDRAM_MODE_REG_SET;
                    end if;
                    
                when SDRAM_MODE_REG_SET =>
                    -- 设置模式寄存器
                    ddr_ras_reg <= '0';  -- MODE REGISTER SET命令
                    ddr_cas_reg <= '0';
                    ddr_we_reg  <= '0';
                    -- 模式寄存器设置：CAS延迟=2, 突发长度=1, 顺序模式
                    ddr_addr_reg <= "0000000100000";  -- CAS=2, BL=1
                    ddr_ba_reg <= (others => '0');
                    sdram_state <= SDRAM_IDLE;
                    
                -- =============================================================
                -- 正常操作状态 / Normal Operation States
                -- =============================================================
                when SDRAM_IDLE =>
                    -- 检查GBA访问请求
                    -- 刷新计数器
                    refresh_counter <= refresh_counter + 1;
                    if refresh_counter >= REFRESH_INTERVAL then
                        refresh_counter <= (others => '0');
                        refresh_needed <= '1';
                    end if;
                    -- 检查是否需要刷新
                    if refresh_needed = '1' and n_ddr_sel = '1' then
                        -- 刷新：RAS=0, CAS=0, WE=1
                        ddr_ras_reg <= '0';
                        ddr_cas_reg <= '0';
                        ddr_we_reg  <= '1';
                        ddr_addr_reg <= (others => '0');
                        ddr_ba_reg <= (others => '0');
                        refresh_needed <= '0';
                    elsif n_ddr_sel = '0' then
                        ddr_cycle_counter <= ddr_cycle_counter + 1;
                        if gba_bus_idle_sync_d1 = '1' and gba_bus_idle_sync = '0' then
                            -- cycle 0
                            ddr_ras_reg <= '0';
                            ddr_cas_reg <= '1';
                            ddr_we_reg  <= '1';
                            ddr_addr_reg <= GP_21 & GP_20 & GP_19 & GP_18 & GP_17 & GP_16 & 
                                        std_logic_vector(internal_address(15 downto 9));
                            ddr_ba_reg <= GP_23 & GP_22;
                            ddr_cycle_counter <= (others => '0');
                        elsif gba_bus_idle_sync_d1 = '0' and gba_bus_idle_sync = '0' then
                            -- cycle 1~3
                            -- 同一行，直接读写
                            ddr_ras_reg <= '1';
                            ddr_cas_reg <= '0';
                            ddr_we_reg  <= gba_bus_wr_sync;  -- 写保护：当config_write_enable=0时强制WE=1(禁写)
                            -- 列地址
                            ddr_addr_reg(12 downto 9) <= (others => '0');
                            ddr_addr_reg(8 downto 0) <= std_logic_vector(internal_address(8 downto 0));
                            ddr_ba_reg <= GP_23 & GP_22;
                            if ddr_cycle_counter > x"3" then
                                -- 预充电：RAS=0, CAS=1, WE=0
                                ddr_ras_reg <= '0';
                                ddr_cas_reg <= '1';
                                ddr_we_reg  <= '0';
                                ddr_addr_reg <= (others => '0');
                                ddr_addr_reg(10) <= '1';  -- A10=1预充电所有Bank
                                ddr_ba_reg <= (others => '0');
                            end if;
                        elsif gba_bus_idle_sync_d1 = '0' and gba_bus_idle_sync = '1' then
                            -- 预充电：RAS=0, CAS=1, WE=0
                            ddr_ras_reg <= '0';
                            ddr_cas_reg <= '1';
                            ddr_we_reg  <= '0';
                            ddr_addr_reg <= (others => '0');
                            ddr_addr_reg(10) <= '1';  -- A10=1预充电所有Bank
                            ddr_ba_reg <= (others => '0');
                        else
                            -- 空闲状态，NOP命令
                            ddr_ras_reg <= '1';
                            ddr_cas_reg <= '1';
                            ddr_we_reg  <= '1';
                            ddr_addr_reg <= (others => '0');
                            ddr_ba_reg <= (others => '0');
                        end if;
                    else
                        -- 空闲状态，NOP命令
                        ddr_ras_reg <= '1';
                        ddr_cas_reg <= '1';
                        ddr_we_reg  <= '1';
                        ddr_addr_reg <= (others => '0');
                        ddr_ba_reg <= (others => '0');
                    end if;
                when others =>
                    sdram_state <= SDRAM_POWER_UP;
                    
            end case;
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

    -- FLASH_NCE is enabled when: GP_NCS is active, not in DDR mode, and not in SD mode (or GP_23 is low).
    -- FLASH_NCE在以下情况使能: GP_NCS有效, 非DDR模式, 且非SD模式(或GP_23为低)。
    FLASH_NCE <= GP_NCS or config_map_reg or (config_sd_enable and GP_23);
    
    -- Pass through GBA R/W signals to Flash/SRAM directly.
    -- 将GBA的读写信号直接透传给Flash/SRAM。
    FLASH_SRAM_NWE <= GP_NWR;
    FLASH_SRAM_NOE <= GP_NRD;

    -- ========================================================================
    -- SD Card Controller - Forward Implementation / SD卡控制器 - 正向实现
    -- Based on reverse analysis of original CPLD logic
    -- 基于原始CPLD逻辑的逆向分析
    -- ========================================================================

    n_sd_mode_active <= '0' when (config_sd_enable = '1' and GP_23 = '1' and GP_NCS = '0' and magic_address = '0') else '1';
    GP <= sd_read_buffer when (n_sd_mode_active = '0' and GP_NRD = '0') else (others => 'Z');
    SD_CLK <= (GP_NWR and GP_NRD) or n_sd_mode_active;
    -- Address decoding for SD interface / SD接口地址解码
    -- 0x01800000 -> GP_22=1, GP_20=0, GP_19=0 -> CMD interface
    -- 0x01100000 -> GP_22=0, GP_20=0, GP_19=1 -> DAT read interface  
    -- 0x01000000 -> GP_22=0, GP_20=0, GP_19=0 -> DAT write interface
    sd_access_type <= SD_ACCESS_CMD   when (GP_22 = '1') else
                      SD_ACCESS_READ  when (GP_22 = '0' and GP_19 = '1') else
                      SD_ACCESS_WRITE when (GP_22 = '0' and GP_19 = '0') else
                      SD_ACCESS_NONE;
    sd_controller: process(CLK50MHz)
    begin
        if falling_edge(CLK50MHz) then
            -- Only process when SD mode is active / 仅在SD模式活动时处理
            if n_sd_mode_active = '0' then
                -- Once address_load falling edge, two consecutive rising edges of gba_bus_idle_sync will occur for SD_ACCESS_WRITE
                -- 一次连续传输只会发送一次address_load下降，也就是说uint32_t写入，会是一次address_load下降，两次gba_bus_idle_sync上升
                if address_load_sync2 = '1' then
                    if address_load_sync = '0' then
                        case sd_access_type is
                            when SD_ACCESS_CMD =>
                                sd_cmd_output <= GP(7);
                            when SD_ACCESS_WRITE =>
                                sd_dat_output <= GP(7 downto 4);        -- 高4位直接输出
                                sd_output_shift_reg <= GP(3 downto 0);  -- 锁存低4位
                            when others =>
                                null;
                        end case;
                    end if;
                elsif gba_bus_idle_sync_d1 = '0' and gba_bus_idle_sync = '0' then
                    case sd_access_type is
                        when SD_ACCESS_CMD =>
                            sd_read_buffer(0) <= SD_CMD;
                        when SD_ACCESS_READ =>
                            sd_read_buffer(11 downto 8) <= SD_DAT;
                        when SD_ACCESS_WRITE =>
                            if gba_bus_rd_sync = '0' then
                                sd_read_buffer(11 downto 8) <= SD_DAT;
                            end if;
                        when others =>
                            null;
                    end case;
                elsif gba_bus_idle_sync_d1 = '0' and gba_bus_idle_sync = '1' then
                    case sd_access_type is
                        when SD_ACCESS_READ =>
                            sd_read_buffer <= sd_read_buffer(11 downto 0) & sd_read_buffer(15 downto 12);
                        when SD_ACCESS_WRITE =>
                            sd_dat_output <= sd_output_shift_reg;
                        when others =>
                            null;
                    end case;
                end if;
            else
                sd_cmd_output <= '1';                        -- CMD idle high (SD spec)
                sd_dat_output <= "1111";                     -- DAT idle high (SD spec)
            end if;
        end if;
    end process;

    -- SD Pin Tri-state Control / SD引脚三态控制
    -- Enhanced tri-state logic with improved timing and control
    -- 增强的三态逻辑，改进时序和控制
    
    -- CMD: Drive during CMD write operations with proper timing
    -- CMD：在CMD写操作期间驱动，具有适当的时序
    SD_CMD <= sd_cmd_output when (n_sd_mode_active = '0' and 
                                  sd_access_type = SD_ACCESS_CMD and 
                                  GP_NWR = '0') else 'Z';
    
    -- DAT: Drive during DAT write operations with enhanced control
    -- DAT：在DAT写操作期间驱动，具有增强的控制
    SD_DAT <= sd_dat_output when (n_sd_mode_active = '0' and 
                                  sd_access_type = SD_ACCESS_WRITE and 
                                  GP_NWR = '0') else (others => 'Z');

end behavioral;
