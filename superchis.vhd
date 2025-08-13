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
    
    -- DDR SDRAM State Machine / DDR SDRAM 状态机
    type ddr_state_t is (
        DDR_IDLE,       -- Idle state / 空闲状态
        DDR_PRECHARGE,  -- Precharge command / 预充电
        DDR_ACTIVATE,   -- Activate command (open a row) / 行激活
        DDR_READ,       -- Read command / 读命令
        DDR_WRITE,      -- Write command / 写命令
        DDR_REFRESH     -- Refresh command / 刷新命令
    );
    
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
    signal ddr_state          : ddr_state_t := DDR_IDLE;    -- Current state of the DDR state machine / DDR状态机的当前状态
    signal ddr_counter        : unsigned(3 downto 0) := (others => '0'); -- Counter for timing within DDR states / 用于DDR状态内部时序的计数器
    signal ddr_refresh_counter: unsigned(8 downto 0) := (others => '0'); -- Counter to trigger auto-refresh / 用于触发自动刷新的计数器
    signal ddr_cke_reg        : std_logic := '0';           -- DDR CKE signal register / DDR CKE信号寄存器
    signal ddr_ras_reg        : std_logic := '1';           -- DDR nRAS signal register / DDR nRAS信号寄存器
    signal ddr_cas_reg        : std_logic := '1';           -- DDR nCAS signal register / DDR nCAS信号寄存器
    signal ddr_we_reg         : std_logic := '1';           -- DDR nWE signal register / DDR nWE信号寄存器
    
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
    signal read_sync          : std_logic;                  -- Synchronized GP_NRD / 同步后的GP_NRD
    signal write_enable_sync  : std_logic;                  -- Synchronized write enable logic (original: mc_E3) / 同步后的写使能逻辑
    signal gba_bus_idle_sync_d1       : std_logic := '0';           -- Timing sync stage (original: mc_H14) / 时序同步级
    signal gba_bus_idle_sync       : std_logic := '0';           -- Timing sync stage (original: mc_H15) / 时序同步级
    signal addr_clock         : std_logic := '0';          -- Composite clock for address counter (original: mc_H11) / 地址计数器的组合时钟 (原始: mc_H11)  
    
    -- SD Card Signals / SD卡信号
    signal sd_cmd_out         : std_logic := '1';           -- Data to be driven on the SD_CMD line / 驱动到SD_CMD线上的数据
    signal sd_data_out        : std_logic_vector(3 downto 0) := (others => '1'); -- Data to be driven on the SD_DAT lines(original: mc_H3, H13, H7, H6) / 驱动到SD_DAT线上的数据
    signal sd_cmd_oe          : std_logic := '0';           -- Output enable for the SD_CMD line / SD_CMD线的输出使能
    signal sd_data_oe         : std_logic_vector(3 downto 0) := (others => '0'); -- Output enable for the SD_DAT lines / SD_DAT线的输出使能
    
    -- SD Card State Signals (Reconstruction of original macrocells) / SD卡状态信号 (对原始宏单元的重构)
    signal sd_dat_state       : std_logic_vector(3 downto 0) := (others => '0');  -- State for DAT lines (original: mc_H3,F5,E0,E2) / DAT线的状态
    signal sd_cmd_state       : std_logic := '0';           -- State for CMD line (original: mc_E13) / CMD线的状态
    signal sd_dat_toggle      : std_logic_vector(3 downto 0) := (others => '0');  -- D-FFs for DAT lines (original: mc_F0,F1,F14,F15) / DAT线的D触发器
    signal sd_cmd_toggle      : std_logic := '0';           -- D-FF for CMD line (original: mc_F7) / CMD线的D触发器
    signal sd_common_logic    : std_logic := '0';           -- Shared logic for some SD outputs (mc_H9) / 用于部分SD输出的共享逻辑

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
        
        if config_sd_enable = '1' then
            -- SD Card interface is enabled and takes priority.
            -- SD卡接口已使能，并拥有最高优先级。
            current_mode <= MODE_SD;
        elsif config_map_reg = '1' then
            -- SDRAM mode is selected.
            -- 选择SDRAM模式。
            current_mode <= MODE_DDR;
        else
            -- Default mode is Flash/SRAM access.
            -- 默认为Flash/SRAM访问模式。
            current_mode <= MODE_FLASH;
        end if;
    end process;

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
            flash_address(1)  <= config_bank_select(3) or internal_address(1); -- FLASH-A1 = mc_C1 = mc_B15 | iaddr-a1
            flash_address(3)  <= config_bank_select(3) or internal_address(5) or config_bank_select(4); -- FLASH-A3 = mc_C15 = mc_B15 | iaddr-a5 | mc_C9
            flash_address(6)  <= config_bank_select(4) or internal_address(8); -- FLASH-A6 = mc_C8 = mc_C9 | iaddr-a8
            flash_address(7)  <= internal_address(4)  or config_bank_select(0); -- FLASH-A7 = mc_D1 = iaddr-a4 | mc_C10
            flash_address(11) <= internal_address(11) or config_bank_select(2); -- FLASH-A11 = mc_D2 = iaddr-a11 | mc_D9
            flash_address(14) <= internal_address(14) or config_bank_select(1); -- FLASH-A14 = mc_C6 = iaddr-a14 | mc_G14
            flash_address(15) <= config_bank_select(0) or internal_address(15) or config_bank_select(2) or config_bank_select(1); -- FLASH-A15 = mc_D0 = mc_C10 | iaddr-a15 | mc_D9 | mc_G14

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
    -- Simple state machine for basic DDR commands
    -- NOTE: Refresh logic clocked by GP_NCS (faithful to original design)
    -- 用于基本DDR命令的简单状态机
    -- 注意: 刷新逻辑由GP_NCS驱动（忠实于原始设计）
    -- ========================================================================
    
    -- DDR State Machine, clocked by GP_NCS rising edge
    -- DDR状态机，由GP_NCS上升沿驱动
    process(GP_NCS)
    begin
        if rising_edge(GP_NCS) then
            case ddr_state is
                when DDR_IDLE =>
                    ddr_counter <= (others => '0');
                    -- Start DDR operation if bus idle and in DDR mode
                    -- 如果总线空闲且处于DDR模式则开始DDR操作
                    if current_mode = MODE_DDR and 
                       write_enable_sync = '1' and read_sync = '1' then
                        ddr_state <= DDR_ACTIVATE;
                    -- Trigger refresh if counter overflows / 计数器溢出时触发刷新
                    elsif ddr_refresh_counter(8) = '1' then
                        ddr_state <= DDR_REFRESH;
                    end if;
                    
                when DDR_ACTIVATE =>
                    ddr_counter <= ddr_counter + 1;
                    if ddr_counter = "0010" then  -- Wait for tRCD (RAS to CAS delay) / 等待tRCD延迟
                        if GP_NWR = '0' and config_write_enable = '1' then
                            ddr_state <= DDR_WRITE;
                        elsif GP_NRD = '0' then
                            ddr_state <= DDR_READ;
                        else
                            ddr_state <= DDR_IDLE;  -- No R/W, return to idle / 无读写，返回空闲
                        end if;
                    end if;
                    
                when DDR_READ =>
                    ddr_counter <= ddr_counter + 1;
                    if ddr_counter = "0100" then  -- Wait for read latency (CL) / 等待读延迟
                        ddr_state <= DDR_PRECHARGE;
                    end if;
                    
                when DDR_WRITE =>
                    ddr_counter <= ddr_counter + 1;
                    if ddr_counter = "0010" then  -- Wait for write recovery (tWR) / 等待写恢复时间
                        ddr_state <= DDR_PRECHARGE;
                    end if;
                    
                when DDR_PRECHARGE =>
                    ddr_counter <= ddr_counter + 1;
                    if ddr_counter = "0011" then  -- Wait for precharge time (tRP) / 等待预充电时间
                        ddr_state <= DDR_IDLE;
                    end if;
                    
                when DDR_REFRESH =>
                    ddr_counter <= ddr_counter + 1;
                    if ddr_counter = "0111" then  -- Wait for refresh cycle time (tRFC) / 等待刷新周期时间
                        ddr_state <= DDR_IDLE;
                        ddr_refresh_counter <= (others => '0');
                    end if;
            end case;
            
            -- Increment refresh counter when not in a refresh cycle.
            -- 在非刷新周期内，递增刷新计数器。
            if ddr_state /= DDR_REFRESH then
                ddr_refresh_counter <= ddr_refresh_counter + 1;
            end if;
        end if;
    end process;

    -- DDR Command Generation / DDR命令生成
    -- Generates DDR control signals (CKE, nRAS, nCAS, nWE) based on the current state.
    -- 基于当前状态生成DDR控制信号。
    process(ddr_state, current_mode, write_enable_sync)
    begin
        ddr_cke_reg <= '0';
        ddr_ras_reg <= '1';
        ddr_cas_reg <= '1';
        ddr_we_reg  <= '1';
        
        if current_mode = MODE_DDR then
            ddr_cke_reg <= '1'; -- Keep CKE high when DDR mode is active / DDR模式激活时保持CKE为高
            
            case ddr_state is
                when DDR_ACTIVATE =>
                    ddr_ras_reg <= '0';  -- Assert nRAS for ACTIVATE command / 发送激活命令
                    
                when DDR_READ =>
                    ddr_cas_reg <= '0';  -- Assert nCAS for READ command / 发送读命令
                    
                when DDR_WRITE =>
                    ddr_cas_reg <= '0';  -- Assert nCAS for WRITE command / 发送写命令
                    ddr_we_reg  <= '0';  -- Assert nWE for WRITE command
                    
                when DDR_PRECHARGE =>
                    ddr_ras_reg <= '0';  -- Assert nRAS for PRECHARGE command / 发送预充电命令
                    ddr_we_reg  <= '0';  -- Assert nWE for PRECHARGE command
                    
                when DDR_REFRESH =>
                    ddr_ras_reg <= '0';  -- Assert nRAS for REFRESH command / 发送刷新命令
                    ddr_cas_reg <= '0';  -- Assert nCAS for REFRESH command
                    
                when others =>
                    null;
            end case;
        end if;
    end process;
    
    -- DDR Address Multiplexing / DDR地址复用
    -- This is a faithful reconstruction of the original CPLD's complex address multiplexing scheme.
    -- Each DDR address bit has state-dependent logic based on the DDR controller FSM states.
    -- 这是对原始CPLD复杂地址复用方案的忠实重构。
    -- 每个DDR地址位都有基于DDR控制器状态机的状态相关逻辑。
    
    -- DDR Address multiplexing based on original CPLD macrocell logic
    -- These signals match the original Boolean equations from the CPLD fitter report
    -- 基于原始CPLD宏单元逻辑的DDR地址复用
    -- 这些信号与CPLD布线报告中的原始布尔方程匹配
    process(ddr_state, internal_address, GP_16, GP_17, GP_18, GP_19, GP_20, GP_21, GP_22, GP_23)
        -- Local signal to identify DDR address phases for cleaner code
        -- 用于识别DDR地址阶段的本地信号，使代码更清晰
        variable is_row_phase    : boolean;
        variable is_column_phase : boolean;
    begin
        -- Decode DDR state to address phases (equivalent to original CPLD macrocell states)
        -- 将DDR状态解码为地址阶段（等效于原始CPLD宏单元状态）
        -- Original: mc_A5='0', mc_B5='0', mc_B6='0', mc_B9='1' for row phase
        -- Original: mc_A5='0', mc_B5='0', mc_B6='1', mc_B9='1' for column phase
        is_row_phase    := (ddr_state = DDR_ACTIVATE);
        is_column_phase := (ddr_state = DDR_READ or ddr_state = DDR_WRITE or ddr_state = DDR_PRECHARGE);
        
        -- Default values
        ddr_address      <= (others => '0');
        ddr_bank_address <= GP_23 & GP_22;  -- Bank address is stable during both phases

        -- DDR Address mapping based on CPLD macrocell logic
        -- DDR地址映射基于CPLD宏单元逻辑
        if is_row_phase then
            -- Row Address Phase / 行地址阶段
            ddr_address(0)  <= internal_address(9);   -- DDR-A0 = mc_A8
            ddr_address(1)  <= not internal_address(10); -- DDR-A1 = mc_A4
            ddr_address(2)  <= internal_address(11);  -- DDR-A2 = mc_A0
            ddr_address(3)  <= internal_address(12);  -- DDR-A3 = mc_H4
            ddr_address(4)  <= internal_address(13);  -- DDR-A4 = mc_H2
            ddr_address(5)  <= internal_address(14);  -- DDR-A5 = mc_A2
            ddr_address(6)  <= internal_address(15);  -- DDR-A6 = mc_A6
            ddr_address(7)  <= GP_16;                 -- DDR-A7 = mc_A1
            ddr_address(8)  <= not GP_17;             -- DDR-A8 = mc_A15
            ddr_address(9)  <= GP_18;                 -- DDR-A9 = mc_B1
            ddr_address(10) <= not GP_19;             -- DDR-A10 = mc_A14
            ddr_address(11) <= GP_20;                 -- DDR-A11 = mc_B3
            ddr_address(12) <= GP_21;                 -- DDR-A12 = mc_C0
            
        elsif is_column_phase then
            -- Column Address Phase / 列地址阶段
            ddr_address(0)  <= internal_address(0);   -- DDR-A0
            ddr_address(1)  <= not internal_address(1);  -- DDR-A1
            ddr_address(2)  <= internal_address(2);   -- DDR-A2
            ddr_address(3)  <= internal_address(3);   -- DDR-A3
            ddr_address(4)  <= internal_address(4);   -- DDR-A4
            ddr_address(5)  <= internal_address(5);   -- DDR-A5
            ddr_address(6)  <= internal_address(6);   -- DDR-A6
            ddr_address(7)  <= internal_address(7);   -- DDR-A7
            ddr_address(8)  <= not internal_address(8);  -- DDR-A8
            ddr_address(9)  <= '0';                   -- DDR-A9 (always 0 in column phase)
            ddr_address(10) <= GP_19;                 -- DDR-A10 (special case for precharge)
            ddr_address(11) <= '0';                   -- DDR-A11 (always 0 in column phase)
            ddr_address(12) <= '0';                   -- DDR-A12 (always 0 in column phase)
        end if;
    end process;
    
    DDR_A    <= ddr_address;
    DDR_BA   <= ddr_bank_address;
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
    
    -- GP Bus Data Multiplexing (matching original CPLD boolean equations)
    -- GP总线数据复用 (匹配原始CPLD布尔方程)
    -- GP_22 selects mode: 0=debug/toggle states, 1=data transmission
    -- GP_22选择模式：0=调试/触发器状态，1=数据传输
    process(GP_22, sd_cmd_toggle, SD_CMD, sd_dat_toggle, sd_cmd_state, sd_dat_state, 
            clk3, SD_DAT, sd_common_logic)
        -- Local aliases for better readability / 本地别名，提高可读性
        alias debug_mode    : std_logic is not GP_22;  -- GP_22=0: Debug/Toggle mode
        alias data_mode     : std_logic is GP_22;      -- GP_22=1: Data transmission mode
    begin
        -- GP总线数据复用：基于GP_22地址位选择调试模式或数据传输模式
        -- GP bus data mux: GP_22 selects debug mode or data transmission mode
        
        if debug_mode = '1' then
            -- Debug Mode (GP_22=0): Read internal toggle states and control signals
            -- 调试模式：读取内部触发器状态和控制信号
            gp_output_data(0)  <= sd_cmd_toggle;        -- CMD toggle state
            gp_output_data(1)  <= sd_dat_toggle(1);     -- DAT1 toggle state  
            gp_output_data(2)  <= sd_dat_toggle(0);     -- DAT0 toggle state
            gp_output_data(3)  <= sd_dat_toggle(3);     -- DAT3 toggle state
            gp_output_data(4)  <= sd_cmd_state;         -- CMD line state
            gp_output_data(5)  <= sd_dat_state(2);      -- DAT2 line state
            gp_output_data(6)  <= sd_dat_state(0);      -- DAT0 line state
            gp_output_data(7)  <= sd_dat_state(3);      -- DAT3 line state
            gp_output_data(8)  <= SD_DAT(0);            -- Raw SD-DAT0 input (key bit!)
            gp_output_data(9)  <= SD_DAT(1);            -- Raw SD-DAT1 input
            gp_output_data(10) <= SD_DAT(2);            -- Raw SD-DAT2 input
            gp_output_data(11) <= SD_DAT(3);            -- Raw SD-DAT3 input
            gp_output_data(12) <= sd_dat_toggle(2);     -- Additional toggle state
            gp_output_data(13) <= sd_dat_toggle(3);     -- Additional toggle state
            gp_output_data(14) <= sd_dat_toggle(2);     -- Duplicate for compatibility
            gp_output_data(15) <= sd_dat_toggle(1);     -- Duplicate for compatibility
        else
            -- Data Transmission Mode (GP_22=1): Read actual SD line states and combined signals
            -- 数据传输模式：读取实际SD线路状态和组合信号
            gp_output_data(0)  <= SD_CMD;               -- Direct SD-CMD line state
            gp_output_data(1)  <= sd_cmd_state;         -- Processed CMD state
            gp_output_data(2)  <= sd_dat_state(2);      -- Processed DAT2 state
            gp_output_data(3)  <= '0';                  -- Fixed low in data mode
            gp_output_data(4)  <= sd_dat_state(1);      -- Processed DAT1 state
            gp_output_data(5)  <= sd_dat_state(3);      -- Processed DAT3 state
            gp_output_data(6)  <= sd_data_out(1);       -- SD-DAT1 output driver
            gp_output_data(7)  <= sd_data_out(2);       -- SD-DAT2 output driver
            gp_output_data(8)  <= clk3;                 -- Clock signal (key bit!)
            gp_output_data(9)  <= '0';                  -- Fixed low in data mode
            gp_output_data(10) <= '1';                  -- Fixed high in data mode
            gp_output_data(11) <= '1';                  -- Fixed high in data mode
            gp_output_data(12) <= '1';                  -- Fixed high in data mode
            gp_output_data(13) <= '1';                  -- Fixed high in data mode
            gp_output_data(14) <= '1';                  -- Fixed high in data mode
            gp_output_data(15) <= '1';                  -- Fixed high in data mode
        end if;
    end process;
    
    -- GP bus tri-state control. Drive the bus when enabled, otherwise high-impedance.
    -- GP总线三态控制。使能时驱动总线，否则为高阻态。
    GP <= gp_output_data when gp_output_enable = '1' else (others => 'Z');

    -- ========================================================================
    -- SD Card Interface (Low-Level Bit-Banging Logic) / SD卡接口 (底层位操作逻辑)
    -- Complex reconstruction of original CPLD's SD communication logic using
    -- state latches and toggle flip-flops. Verified against CPLD fitter report.
    -- 对原始CPLD的SD通信逻辑的复杂重构，使用状态锁存器和触发器。
    -- 
    -- Architecture / 架构:
    -- - STATE layer: Stores current SD line output values / 存储当前SD线路输出值
    -- - TOGGLE layer: Controls when to flip STATE values / 控制何时翻转STATE值
    -- - GP_22 selects read mode: 0=debug/toggle states, 1=SD line states
    -- - GP_19/20: Global control bits, GP(8-12): Individual reset bits
    -- ========================================================================

    -- SD Card State Machine, clocked by GP_NCS rising edge.
    -- Direct implementation of CPLD fitter report boolean equations.
    -- State dependencies: cmd->dat2->dat0->dat1->dat3
    -- SD卡状态机，由GP_NCS上升沿驱动。CPLD适配报告布尔方程的直接实现。
    process(GP_NCS)
        -- Local signals for cleaner logic / 本地信号，使逻辑更清晰
        variable gba_enable_condition    : std_logic;  -- GBA主动使能条件
        variable gba_override_condition  : std_logic;  -- GBA强制复位条件
        variable any_dat_inactive        : std_logic;  -- 任意DAT线非活动
        variable some_dat_inactive       : std_logic;  -- 部分DAT线非活动
    begin
        if rising_edge(GP_NCS) then
            -- Common condition calculations / 公共条件计算
            gba_enable_condition   := not GP_19;  -- GP_19=0 enables SD operations
            gba_override_condition := GP_20;      -- GP_20=1 forces override mode
            
            -- State dependency calculations / 状态依赖计算
            any_dat_inactive  := not sd_dat_state(0) or not sd_dat_state(1) or 
                                not sd_dat_state(2) or not sd_dat_state(3);
            some_dat_inactive := not sd_dat_state(1) or not sd_dat_state(3);
            
            -- SD Command State (mc_E13) - First in dependency chain
            -- SD命令状态 - 依赖链的第一个
            -- Logic: Enable when GBA activates and any DAT line is inactive
            sd_cmd_state <= (gba_enable_condition and any_dat_inactive) or
                           (gba_override_condition and not sd_cmd_toggle);

            -- SD DAT2 State (mc_F5) - Depends on cmd_state  
            -- SD DAT2状态 - 依赖于cmd_state
            -- Logic: Enable when GBA activates, CMD is active, and some DAT lines inactive
            sd_dat_state(2) <= (gba_enable_condition and sd_cmd_state and some_dat_inactive) or
                              (gba_override_condition and not sd_dat_toggle(1));

            -- SD DAT0 State (mc_E0) - Depends on dat_state(2)
            -- SD DAT0状态 - 依赖于dat_state(2)
            -- Logic: Enable when GBA activates, DAT2 is active, and some DAT lines inactive
            sd_dat_state(0) <= (gba_enable_condition and sd_dat_state(2) and some_dat_inactive) or
                              (gba_override_condition and not sd_dat_toggle(0));

            -- SD DAT1 State (mc_E2) - Depends on dat_state(0)
            -- SD DAT1状态 - 依赖于dat_state(0)  
            -- Logic: Enable when GBA activates, DAT0 is active, and DAT3 is inactive
            sd_dat_state(1) <= (gba_enable_condition and sd_dat_state(0) and not sd_dat_state(3)) or
                              (gba_override_condition and not sd_dat_toggle(3));

            -- SD DAT3 State (mc_H3) - Last in chain, depends on dat_state(1)
            -- SD DAT3状态 - 链的最后一个，依赖于dat_state(1)
            -- Logic: Enable when GBA activates and DAT1 is active
            sd_dat_state(3) <= (gba_enable_condition and sd_dat_state(1)) or
                              (gba_override_condition and not sd_cmd_toggle);
            
            -- SD Common Logic (mc_H9) - Shared logic for output generation
            -- SD公共逻辑 - 用于输出生成的共享逻辑
            -- Logic: Same as DAT3 state but with different override condition
            sd_common_logic <= (gba_enable_condition and sd_dat_state(1)) or
                              (gba_override_condition and not sd_dat_state(2));
        end if;
    end process;
    
    -- SD Card Toggle Flip-Flop Logic.
    -- T-FlipFlops with T = (condition_set) XOR (reset_condition) structure.
    -- SD卡触发器逻辑。T触发器采用 T = (设置条件) XOR (复位条件) 结构。
    process(GP_NCS)
        -- Toggle condition calculation function / 触发器条件计算函数
        -- Encapsulates common T-FF logic pattern for all SD toggles
        -- 封装所有SD触发器的通用T-FF逻辑模式
        function calc_toggle_condition(
            current_toggle : std_logic;
            feedback_line  : std_logic;
            gp_reset_bit   : std_logic
        ) return std_logic is
            variable t_set_condition   : std_logic;
            variable t_reset_condition : std_logic;
            variable timing_active     : std_logic;
        begin
            -- Common timing condition for feedback / 反馈的公共时序条件
            timing_active := not address_load_sync2 and not gba_bus_idle_sync_d1 and gba_bus_idle_sync;
            
            -- T Set Condition: GBA control OR SD line feedback OR SD line inversion
            -- T设置条件：GBA控制 或 SD线反馈 或 SD线反转
            t_set_condition := 
                -- GBA active control / GBA主动控制
                (not GP_19 and not current_toggle and address_load_sync2) or
                -- SD line high feedback / SD线高电平反馈
                (not GP_22 and feedback_line and not current_toggle and timing_active) or
                -- SD line low inversion / SD线低电平反转
                (not GP_22 and not feedback_line and current_toggle and timing_active);
            
            -- T Reset Condition: GBA forced reset via specific GP bit
            -- T复位条件：通过特定GP位进行GBA强制复位
            t_reset_condition := not gp_reset_bit and not GP_19 and address_load_sync2 and not address_load_sync;
            
            -- Final T-FF input: XOR ensures set and reset don't conflict
            -- 最终T-FF输入：XOR确保设置和复位不冲突
            return t_set_condition xor t_reset_condition;
        end function;
        
    begin
        if rising_edge(GP_NCS) then
            -- SD DAT Toggle Flip-Flops / SD DAT触发器
            -- Each DAT line has its own toggle FF with specific feedback
            -- 每条DAT线都有自己的触发器，具有特定的反馈连接
            
            -- Controls SD-DAT0 write via SD-DAT2 feedback / 通过SD-DAT2反馈控制SD-DAT0写操作
            sd_dat_toggle(0) <= calc_toggle_condition(sd_dat_toggle(0), SD_DAT(2), GP(8));

            -- Controls SD-DAT3 write via SD-DAT3 feedback / 通过SD-DAT3反馈控制SD-DAT3写操作 
            sd_dat_toggle(1) <= calc_toggle_condition(sd_dat_toggle(1), SD_DAT(3), GP(10));

            -- Controls SD-DAT0 alternate mode via SD-DAT0 feedback / 通过SD-DAT0反馈控制SD-DAT0替代模式
            sd_dat_toggle(2) <= calc_toggle_condition(sd_dat_toggle(2), SD_DAT(0), GP(11));

            -- Controls SD-DAT1 write via SD-DAT1 feedback / 通过SD-DAT1反馈控制SD-DAT1写操作
            sd_dat_toggle(3) <= calc_toggle_condition(sd_dat_toggle(3), SD_DAT(1), GP(9));
            
            -- SD CMD Toggle Flip-Flop / SD CMD触发器
            -- Controls SD-CMD line, uses sd_dat_toggle(2) as feedback
            -- 控制SD-CMD线，使用sd_dat_toggle(2)作为反馈
            sd_cmd_toggle <= calc_toggle_condition(sd_cmd_toggle, sd_dat_toggle(2), GP(12));
        end if;
    end process;
    
    -- ========================================================================
    -- SD Interface Outputs / SD接口输出
    -- ========================================================================
    -- Final output stage: TOGGLE→STATE→Combinational logic→Physical SD lines
    -- 最终输出阶段：TOGGLE触发器→STATE状态机→组合逻辑→物理SD线路
    
    -- SD Clock Generation / SD时钟生成
    -- Provides clock when GBA bus is idle / 在GBA总线空闲时提供时钟
    SD_CLK <= (GP_NWR and GP_NRD) or sd_output_enable;
    
    -- SD Command Line Output / SD命令线输出
    -- Directly driven by command state / 直接由命令状态驱动
    sd_cmd_out <= sd_cmd_state;
    
    -- SD Data Lines Output / SD数据线输出
    -- GP_22-dependent routing for different operation modes
    -- GP_22相关路由，用于不同的操作模式
    process(GP_22, sd_dat_state, sd_common_logic)
    begin
        if GP_22 = '0' then
            -- Data Mode: Use specific state combinations / 数据模式：使用特定状态组合
            sd_data_out(0) <= sd_dat_state(1);  -- DAT0 from DAT1 state
            sd_data_out(1) <= sd_dat_state(0);  -- DAT1 from DAT0 state
            sd_data_out(2) <= sd_dat_state(3);  -- DAT2 from DAT3 state
            sd_data_out(3) <= sd_common_logic;  -- DAT3 from common logic
        else
            -- Command Mode: Alternative state routing / 命令模式：替代状态路由
            sd_data_out(0) <= sd_dat_state(2);  -- DAT0 from DAT2 state  
            sd_data_out(1) <= sd_dat_state(3);  -- DAT1 from DAT3 state
            sd_data_out(2) <= sd_dat_state(0);  -- DAT2 from DAT0 state
            sd_data_out(3) <= sd_common_logic;  -- DAT3 unchanged
        end if;
    end process;
    
    -- SD Output Enable Control / SD输出使能控制
    -- Controls when CPLD drives SD lines vs high-impedance for reading
    -- 控制何时CPLD驱动SD线路，何时处于高阻态进行读取
    
    -- CMD Line: Writing AND Command mode AND SD enabled
    -- CMD线：写操作 且 命令模式 且 SD使能
    sd_cmd_oe <= not GP_NWR and GP_22 and not sd_output_enable;
    
    -- DAT Lines: Writing AND Data mode AND SD enabled  
    -- DAT线：写操作 且 数据模式 且 SD使能
    sd_data_oe <= (others => (not GP_NWR and not GP_22 and not sd_output_enable));
    
    -- ========================================================================
    -- SD Physical Layer Connections / SD物理层连接
    -- ========================================================================
    -- Tri-state control for bidirectional SD lines
    -- SD线路的三态控制实现全双工通信
    
    -- SD Command Line Tri-state / SD命令线三态控制
    SD_CMD <= sd_cmd_out when sd_cmd_oe = '1' else 'Z';
    
    -- SD Data Lines Tri-state / SD数据线三态控制
    gen_sd_dat: for i in 0 to 3 generate
        SD_DAT(i) <= sd_data_out(i) when sd_data_oe(i) = '1' else 'Z';
    end generate;

end behavioral;
