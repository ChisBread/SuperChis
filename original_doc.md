# GBA SuperCard CPLD 设计文档

## 概述

该 VHDL 设计实现了一个基于 CPLD (LC4128x_TQFP128) 的 GBA (Game Boy Advance) SuperCard 控制器，通过 GBA 接口信号和 50MHz 时钟控制多种存储设备：DDR SDRAM、Flash 存储器、SRAM 和 SD 卡。

## 设计架构

该设计采用模块化架构，将 CPLD 的 8 个 GLB (Global Logic Block) 分配不同的功能：

- **GLB A (0)**: DDR SDRAM 地址生成和状态控制
- **GLB B (1)**: DDR SDRAM 命令和控制信号生成  
- **GLB C (2)**: Flash/SRAM 地址控制和特殊解锁逻辑
- **GLB D (3)**: Flash/SRAM 地址总线生成
- **GLB E (4)**: SD 卡控制和 GP 总线数据多路复用
- **GLB F (5)**: SD 卡数据切换逻辑和 GP 总线输出控制
- **GLB G (6)**: 内部计数器控制和模式检测
- **GLB H (7)**: SD 卡接口和时钟/时序生成

## 输入信号定义

### GBA 接口信号
- `GP_NCS`: 片选信号（低有效）- 主要时钟源
- `GP_NWR`: 写使能信号（低有效）
- `GP_NRD`: 读使能信号（低有效）
- `GP[15:0]`: 双向数据/地址总线
- `GP_16` ~ `GP_23`: 扩展控制信号

### 系统时钟
- `CLK50MHz`: 50MHz 系统时钟 - 用于高速同步操作
- `clk3`: 3MHz 时钟 - 用于特定时序控制

## 存储设备控制机制

### 1. DDR SDRAM 控制

DDR SDRAM 通过复杂的状态机进行控制，主要涉及以下信号：

#### 地址生成 (GLB A)
- 使用内部状态寄存器 `mc_A0` ~ `mc_A15` 生成 DDR 地址线
- 地址位映射：
  - `DDR_A[2:0]` ← `mc_A0`, `mc_A8`, `mc_A4`
  - `DDR_A[7:3]` ← `mc_A1`, `mc_H2`, `mc_H4`, `mc_A2`, `mc_A6`
  - `DDR_A[12:8]` ← `mc_C0`, `mc_B3`, `mc_B1`, `mc_A15`, `mc_A14`

#### 控制信号生成 (GLB B)
- `DDR_CKE` (时钟使能): 由 `mc_B4` 控制，当 DDR 被选择且计数器达到特定状态时激活
- `DDR_NRAS` (行地址选通): 由 `mc_B13` 控制行激活状态
- `DDR_NCAS` (列地址选通): 由 `mc_B14` 控制列激活状态  
- `DDR_NWE` (写使能): 由 `mc_B10` 控制写操作
- `DDR_BA[1:0]` (Bank 地址): 由 `mc_B0`, `mc_B2` 控制

#### DDR 选择逻辑
```vhdl
N_DDR_SEL <= (GP_NCS or not MAP_REG) or (SDENABLE and GP_23)
```
- 当 `MAP_REG=1`、`SDENABLE=0` 且 `GP_NCS=0` 时选择 DDR
- 由 CLK50MHz 同步更新

#### SDRAM 自刷新机制详解

SDRAM 需要定期刷新以保持数据完整性，本设计通过精密的状态机实现自刷新与 GBA 访问的协调：

##### 1. 刷新状态机核心逻辑

**主要状态控制信号**：
- `mc_A5` (ddr_state_ctrl): DDR 状态机主控制
- `mc_B5` (ddr_cmd_active): DDR 命令激活状态  
- `mc_B6` (ddr_timing_ctrl): DDR 时序控制状态
- `mc_B9` (ddr_cmd_state): DDR 命令状态机
- `icntr[8:0]`: 9位内部计数器，用于刷新时序控制

##### 2. 自刷新触发条件

自刷新在以下条件下启动：
```vhdl
-- mc_A5 状态转换逻辑
mc_A5 <= (mc_B5 and not mc_B6 and mc_B9 and not icntr(8))
    or (mc_B5 and not mc_B6 and mc_B9 and not icntr(7))
    or (not ddrcnt(1) and not mc_A5 and not ddrcnt(0) and not ddrcnt(2) 
        and not ddrcnt(3) and mc_B5 and mc_B6 and icntr(8) and icntr(7))
```

**触发条件分析**：
1. **计数器条件**: 当 `icntr[8:7] = "11"` 时，表示刷新间隔计数器已满
2. **DDR计数器状态**: `ddrcnt[3:0] = "0000"` 确保当前没有正在进行的 DDR 操作
3. **状态机协调**: `mc_B5=1, mc_B6=1` 表示进入刷新准备状态

##### 3. 刷新时序控制

**时钟域同步**：
- **GP_NCS 域**: 主状态机更新，响应 GBA 访问请求
- **CLK50MHz 域**: 高精度时序控制，确保刷新时序符合 SDRAM 规范

**计数器复位机制**：
```vhdl
process(GP_NCS, mc_B4, mc_B10, mc_B13, mc_B14)
variable reset_icntr : std_logic;
begin
    reset_icntr := mc_B4 and mc_B10 and not mc_B13 and not mc_B14;
    if reset_icntr = '1' then
        icntr(7) <= '0';
        icntr(8) <= '0';
    elsif rising_edge(GP_NCS) then
        -- 计数器递增逻辑
    end if;
end process;
```

**复位条件解析**：
- `mc_B4=1` (DDR_CKE 激活)
- `mc_B10=1` (写使能信号)  
- `mc_B13=0` (行地址选通无效)
- `mc_B14=0` (列地址选通无效)

这个组合表示 SDRAM 处于空闲状态，可以安全重置刷新计数器。

##### 4. GBA 访问与刷新的时序协调

**优先级机制**：
1. **GBA 访问优先**: 当 `GP_NCS=0` 时，立即暂停刷新操作
2. **刷新窗口检测**: 利用 GBA 总线空闲间隙执行刷新
3. **状态保持**: 刷新被中断时保持当前状态，等待下次机会

**同步策略**：
```vhdl
-- DDR 命令状态机
mc_B9 <= not ((not mc_A5 or mc_B5 or mc_B6 or not mc_E3 or not mc_H0)
    and (not mc_B6 or mc_B9 or not N_DDR_SEL or icntr(8))
    and (not mc_B6 or mc_B9 or not N_DDR_SEL or icntr(7))
    and (mc_A5 or mc_B5 or not mc_B6 or not N_DDR_SEL)
    and (not mc_A5 or not mc_B5 or not mc_B9)
    and (mc_A5 or mc_B9)
    and (mc_B5 or mc_B9));
```

**关键同步点**：
- `mc_E3` (write_enable_sync): 写使能同步器
- `mc_H0` (read_enable_sync): 读使能同步器  
- `N_DDR_SEL`: DDR 选择信号

##### 5. 刷新命令序列

**标准刷新序列**：
1. **预充电阶段**: `DDR_NRAS=0, DDR_NCAS=1, DDR_NWE=0`
2. **自刷新进入**: `DDR_NRAS=0, DDR_NCAS=0, DDR_NWE=1, DDR_CKE=0`
3. **刷新保持**: 保持 CKE=0 一定时间
4. **刷新退出**: `DDR_CKE=1`，恢复正常操作

**控制信号生成**：
```vhdl
DDR_CKE <= mc_B4;   -- 时钟使能控制
DDR_NRAS <= mc_B13; -- 行地址选通
DDR_NCAS <= mc_B14; -- 列地址选通  
DDR_NWE <= mc_B10;  -- 写使能
```

##### 6. 时序参数保证

**刷新间隔**: 通过 9位计数器 `icntr[8:0]` 实现，计数周期 = 512 × GP_NCS周期
**最小刷新时间**: 由状态机确保满足 SDRAM 规范要求的 tRFC 参数
**恢复时间**: 刷新完成后等待 tXSR 时间才允许正常访问

这种设计确保了 SDRAM 在保持数据完整性的同时，最小化对 GBA 访问性能的影响。

### 2. Flash/SRAM 控制

Flash 和 SRAM 共享地址总线和控制逻辑：

#### 地址生成 (GLB C & D)
Flash 地址通过内部地址寄存器 `iaddr[15:0]` 和多个控制位生成：
- 基础地址映射：`FLASH_A[15:0]` 主要来自 `iaddr` 寄存器
- 特殊地址位控制：
  - `FLASH_A[1]` = `mc_B15` OR `iaddr[1]`（支持模式切换）
  - `FLASH_A[3]` = `mc_B15` OR `iaddr[5]` OR `mc_C9`（支持地址映射模式）
  - `FLASH_A[14]` = `iaddr[14]` OR `mc_G14`（支持扩展地址）

#### 控制信号
- `FLASH_NCE` (片选): 由逻辑 `(GP_NCS OR clk3 OR MAP_REG) OR (SDENABLE AND GP_23)` 控制
- `FLASH_SRAM_NWE` (写使能): 直接连接到 `GP_NWR`
- `FLASH_SRAM_NOE` (读使能): 直接连接到 `GP_NRD`
- `SRAM_A16` (扩展地址): 连接到 `WRITEENABLE` 寄存器

#### 内部地址计数器
```vhdl
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
```

#### mc_H11 时钟生成逻辑详解
```vhdl
mc_H11 <= (not GP_NCS and GP_NWR and GP_NRD) or (GP_NCS and not GP_NRD) or (GP_NCS and not GP_NWR);
```

`mc_H11` 作为内部地址计数器的时钟信号，其生成逻辑包含三个条件的逻辑或：

1. **`(not GP_NCS and GP_NWR and GP_NRD)`** - 芯片选中且空闲状态
   - GP_NCS=0（芯片被选中）
   - GP_NWR=1 且 GP_NRD=1（既不读也不写，总线空闲）
   - 此时提供稳定的时钟，用于地址计数器的自动递增

2. **`(GP_NCS and not GP_NRD)`** - 芯片未选中但有读操作
   - GP_NCS=1（芯片未被选中） 
   - GP_NRD=0（读操作有效）
   - 在读操作的边沿触发地址更新

3. **`(GP_NCS and not GP_NWR)`** - 芯片未选中但有写操作  
   - GP_NCS=1（芯片未被选中）
   - GP_NWR=0（写操作有效）
   - 在写操作的边沿触发地址更新

**设计意图**：
- 当芯片被选中时，在总线空闲期间提供连续时钟用于地址自动递增
- 当芯片未被选中时，利用读写操作的边沿作为地址更新的触发信号
- 这种设计确保了地址计数器能够在适当的时机更新，支持连续访问和突发传输模式

- 在 `mc_H11` 上升沿时更新，支持从 GP 总线加载或自动递增

### 3. SD 卡控制

SD 卡接口通过专用的状态机和切换逻辑实现：

#### 时钟生成
```vhdl
mc_H1 <= (GP_NWR and GP_NRD) or N_SDOUT;
SD_CLK <= mc_H1;
```
- SD 卡时钟由 GBA 读写信号和 SD 输出使能控制

#### 数据线控制 (GLB F)
每个 SD 数据线都有对应的状态寄存器和切换逻辑：
- `SD_DAT[0]` ← `mc_H3`（带输出使能控制）
- `SD_DAT[1]` ← `mc_H13` 
- `SD_DAT[2]` ← `mc_H7`
- `SD_DAT[3]` ← `mc_H6`
- `SD_CMD` ← `mc_H8`

#### 输出使能逻辑
```vhdl
SD_CMD <= mc_H8 when (not GP_NWR and GP_22 and not N_SDOUT) = '1' else 'Z';
```
- 当写操作、GP_22 有效且 SD 输出使能时才驱动信号线

### 4. GP 总线多路复用

GP 总线在不同模式下承担不同功能：

#### 输出模式
当 `(not GP_NRD and not N_SDOUT) = '1'` 时，GP 总线输出 SD 卡数据：
```vhdl
GP(0) <= mc_E8 when (not GP_NRD and not N_SDOUT) = '1' else 'Z';
GP(1) <= mc_E10 when (not GP_NRD and not N_SDOUT) = '1' else 'Z';
-- ... 其他位类似
```

#### 数据选择逻辑
每个 GP 位都有对应的多路选择器，根据 `GP_22` 信号选择 SD 卡数据或其他功能：
```vhdl
mc_E8 <= (not GP_22 and mc_F7) or (GP_22 and SD_CMD);
```

## 特殊功能和模式控制

### 1. 模式寄存器
系统通过特殊的寄存器控制不同工作模式：
- `MAP_REG`: 选择 DDR 或 SRAM 模式
- `SDENABLE`: SD 卡功能使能
- `WRITEENABLE`: 写操作使能和 SRAM 扩展地址

### 2. Magic 地址解锁
设计包含特殊的解锁序列检测：
```vhdl
MAGICADDR <= GP(4) and GP(6) and GP(7) and GP(8) and GP(9) and GP(14) and mc_B8;
```
当检测到特定的地址模式时，允许访问配置寄存器。

### 3. 模式切换序列
```vhdl
mc_G1 <= not GP(0) and GP(1) and not GP(2) and GP(3) and GP(4) and not GP(5) 
         and GP(6) and not GP(7) and GP(8) and not GP(9) and GP(10) and not GP(11) and mc_C13;
```
通过特定的数据模式实现功能模式切换。

## 时钟域和同步机制

### 1. 主要时钟域
- **GP_NCS 域**: 主要的状态机更新，包括 DDR 控制、地址生成
- **CLK50MHz 域**: 高速同步操作，特殊信号生成
- **GP_NWR 域**: 寄存器加载和配置更新
- **mc_H11 域**: 内部地址计数器更新

### 2. 异步复位逻辑
部分计数器具有异步复位功能：
```vhdl
reset_icntr := mc_B4 and mc_B10 and not mc_B13 and not mc_B14;
```
当特定的 DDR 控制信号组合出现时，重置内部计数器。

## 总结

这个 CPLD 设计实现了一个功能完整的多存储设备控制器，能够：

1. **智能存储选择**: 根据模式寄存器和控制信号自动选择 DDR、Flash/SRAM 或 SD 卡
2. **复杂地址映射**: 支持多种地址映射模式和扩展地址功能
3. **多协议支持**: 同时支持并行存储器（DDR/Flash/SRAM）和串行存储器（SD卡）协议
4. **动态配置**: 通过特殊序列可以动态配置工作模式
5. **高性能操作**: 利用 50MHz 时钟实现高速数据传输

该设计充分利用了 CPLD 的并行处理能力，通过精心设计的状态机和多路复用逻辑，在有限的资源下实现了复杂的多存储设备控制功能。
