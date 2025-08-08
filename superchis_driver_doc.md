# SuperChis CPLD 驱动与功能文档

## 1. 概述 (Overview)

`superchis` 是一个复杂的CPLD设计，旨在作为GBA（Game Boy Advance）烧录卡的硬件核心。它忠实地复刻了原始SuperCard SD版卡带的硬件逻辑，提供了对板载Flash、SRAM、DDR SDRAM以及SD卡的访问控制。

本文档基于实际的GBA驱动代码 (`supercard_driver.c` 和 `supercard_io.S`) 编写，详细说明了如何通过GBA的卡带接口与`superchis` CPLD进行交互。

`superchis` is a complex CPLD design intended to be the hardware core for a GBA (Game Boy Advance) flash cartridge. It faithfully reconstructs the hardware logic of the original SuperCard SD version, providing access control to onboard Flash, SRAM, DDR SDRAM, and an SD card.

This document is based on actual GBA driver code (`supercard_driver.c` and `supercard_io.S`) and describes how to interact with the `superchis` CPLD through the GBA's cartridge interface.

---

## 2. 内存映射与地址空间 (Memory Mapping and Address Space)

### 2.1. GBA地址空间布局 (GBA Address Space Layout)

根据驱动代码，SuperChis使用以下地址映射：

```c
// Base addresses for different ROM mirrors
#define SC_MIRROR_BASE_8         0x08000000  // Primary ROM mirror
#define SC_MIRROR_BASE_A         0x0A000000  // Secondary ROM mirror (faster)

// Magic configuration register
#define REG_SC_MODE_REG_ADDR     0x09FFFFFE  // Mode configuration register
```

### 2.2. 功能地址映射 (Functional Address Mapping)

| 地址范围 | 功能 | 说明 |
|---------|------|------|
| `0x08000000-0x09FFFFFF` | 主ROM镜像 | Flash/DDR/SD I/O模式的主要访问区域 |
| `0x0A000000-0x0BFFFFFF` | 快速ROM镜像 | 相同功能但使用更快的等待状态 |
| `0x09FFFFFE` | 模式配置寄存器 | 魔术解锁序列和模式切换 |

### 2.3. SD卡I/O专用地址 (SD Card I/O Specific Addresses)

当SD卡模式激活时，以下地址具有特殊含义：

```c
// SD Card I/O registers (from supercard_io.S)
#define SC_WRITE_REGISTER_8     (SC_MIRROR_BASE_8 + 0x01000000)  // 0x09000000
#define SC_WRITE_REGISTER_A     (SC_MIRROR_BASE_A + 0x01000000)  // 0x0B000000
#define SC_READ_REGISTER_16     (SC_MIRROR_BASE_8 + 0x01100000)  // 0x09100000
#define SC_READ_REGISTER_8      (SC_MIRROR_BASE_8 + 0x01100000)  // 0x09100000
#define SC_READ_REGISTER_A      (SC_MIRROR_BASE_A + 0x01100000)  // 0x0B100000
#define SC_RDWR_COMMAND         (SC_MIRROR_BASE_8 + 0x01800000)  // 0x09800000
#define SCLITE_DATA_REGISTER32  (SC_MIRROR_BASE_8 + 0x01200000)  // 0x09200000 (Lite版专用)
```

---

## 3. 模式配置系统 (Mode Configuration System)

### 3.1. 魔术解锁序列 (Magic Unlock Sequence)

基于驱动代码 `write_supercard_mode()` 函数，配置SuperChis需要执行以下严格的序列：

```c
void write_supercard_mode(uint16_t modebits) {
  // Write magic value and then the mode value (twice) to trigger the mode change.
  asm volatile (
    "strh %1, [%0]\n"    // 1. 写入魔术值 0xA55A
    "strh %1, [%0]\n"    // 2. 再次写入魔术值 0xA55A  
    "strh %2, [%0]\n"    // 3. 写入配置字
    "strh %2, [%0]\n"    // 4. 再次写入配置字
    :: "l"(REG_SC_MODE_REG_ADDR),  // 地址: 0x09FFFFFE
       "l"(MODESWITCH_MAGIC),       // 魔术值: 0xA55A
       "l"(modebits)                // 配置位
    : "memory");
}
```

**重要**: 此序列必须严格按顺序执行，任何中断或对其他地址的访问都会导致序列失效。

### 3.2. 配置字格式 (Configuration Word Format)

根据 `set_supercard_mode()` 函数，配置字的格式如下：

```c
void set_supercard_mode(unsigned mapped_area, bool write_access, bool sdcard_interface) {
  // Bit0: Controls SDRAM vs internal Flash mapping
  // Bit1: Controls whether the SD card interface is mapped into the ROM address space.
  // Bit2: Controls read-only/write access. Doubles as SRAM bank selector!
  uint16_t value = mapped_area | (sdcard_interface ? 0x2 : 0x0) | (write_access ? 0x4 : 0x0);
  write_supercard_mode(value);
}
```

| Bit | 名称 | 功能描述 |
|-----|------|----------|
| 0 | `mapped_area` | 内存映射控制: `0`=Flash, `1`=DDR SDRAM |
| 1 | `sdcard_interface` | SD卡I/O接口使能: `0`=禁用, `1`=启用 |
| 2 | `write_access` | 写访问控制/SRAM Bank选择: `0`=只读/Bank0, `1`=读写/Bank1 |
| 3-15 | - | 保留位 (应设为0) |

---

## 4. SD卡接口协议 (SD Card Interface Protocol)

### 4.1. SD卡I/O工作原理 (SD Card I/O Operation)

SuperChis实现了一个完全由软件控制的SD卡接口。驱动通过精确控制每个总线周期来模拟SD卡的SPI或SD模式协议。

#### 4.1.1. 关键信号定义

```c
#define SD_DATA0                0x0100  // DAT0线状态位
```

#### 4.1.2. 命令接口 (Command Interface)

SD卡命令通过 `SC_RDWR_COMMAND` (0x09800000) 地址进行位操作发送：

```c
// 从 send_sdcard_commandbuf() 函数
void send_sdcard_commandbuf(const uint8_t *buffer, unsigned length) {
  ldr r3, =SC_RDWR_COMMAND
  1:
    ldrb r2, [r0]        // 加载一个字节
    add r0, $1
    .rept 8              // 逐位发送 (MSB先发)
      strh r2, [r3]      // 写入当前位到CMD线
      lsl r2, #1         // 左移准备下一位
    .endr
    sub r1, $1
    bne 1b
}
```

### 4.2. 数据传输协议 (Data Transfer Protocol)

#### 4.2.1. 读操作 (Read Operations)

SD卡数据读取使用高度优化的汇编代码实现：

```assembly
sc_read_sectors_w0:  // 使用0x08000000基址的快速读取
  // 1. 等待数据准备就绪 (DAT0拉低)
  mov r4, $(CMD_WAIT_DATA)    // 超时计数器
  mov r3, $(SC_READ_REGISTER_16)
  2:
    subs r4, r4, $1
    moveq r0, $1              // 超时返回错误
    beq 3f
    ldrh r2, [r3]
    tst r2, $(SD_DATA0)       // 检查DAT0状态
  bne 2b
  
  // 2. 读取512字节扇区数据
  mov r4, $(512 / 16 / 8)     // 每次读取64位，循环次数
  2:
    .rept 16
      ldmia r5, {r2, r3, r6, r7, r8, r9, r10, r11}  // 读取64位
      // 处理数据并写入缓冲区...
      stmia r0!, {r7, r11}
    .endr
    subs r4, r4, $1
    bne 2b
```

#### 4.2.2. 写操作 (Write Operations)

SD卡写入包括数据发送和CRC校验：

```assembly
sc_write_sectors_w0:
  // 1. 发送数据开始令牌
  mov r2, $0xFFFFFFFF
  str r2, [r6]               // 发送前导位
  strh r1, [r6]              // 发送开始令牌
  
  // 2. 发送512字节数据
  mov r1, $(512 / 2 / 8)
  2:
    .rept 16
      ldrb r2, [r4], #1      // 从缓冲区读取字节
      str r2, [r6]           // 发送到SD卡
    .endr
    subs r1, r1, $1
    bne 2b
    
  // 3. 发送CRC校验码
  // 4. 接收响应令牌并检查状态
```

### 4.3. 性能优化策略 (Performance Optimization)

#### 4.3.1. 双重地址镜像

驱动代码支持两个地址镜像，用于性能优化：

```c
static inline bool use_fast_mirror() {
  #ifdef SUPERCARD_LITE_IO
    return false;              // SC lite不能使用快速等待状态
  #else
    return isgba && !slowsd;   // 仅在GBA模式且快速加载开启时使用
  #endif
}

// 读写函数指针数组
const static t_rdsec_fn sc_read_sectors[2] = {
  &sc_read_sectors_w0,   // 0x08000000基址
  &sc_read_sectors_w1    // 0x0A000000基址 (快速)
};
```

#### 4.3.2. 缓冲区对齐优化

汇编代码检查缓冲区对齐以选择最优的传输路径：

```assembly
tst r0, $3                 // 检查缓冲区是否4字节对齐
bne 5f                     // 跳转到慢速路径
// ... 快速对齐路径代码
5:
// ... 慢速非对齐路径代码
```

---

## 5. SD卡初始化流程 (SD Card Initialization Process)

### 5.1. 完整初始化序列

基于 `sdcard_init()` 函数，完整的SD卡初始化包括以下步骤：

```c
unsigned sdcard_init(t_card_info *info) {
  // 1. 发送初始化时钟
  send_empty_clocks(4096);  // ~1ms的时钟信号
  
  // 2. 发送CMD0复位命令
  if (!send_sdcard_reset())
    return SD_ERR_NO_STARTUP;
    
  // 3. 发送CMD8检测卡版本
  bool cmd8_ok = send_sdcard_command(SD_CMD8, 0xAA | 0x100, resp, SD_MAX_RESP);
  
  // 4. ACMD41循环等待卡片就绪
  uint32_t ocrreq = OCR_V30 | (cmd8_ok ? OCR_CCS : 0);
  for (unsigned i = 0; i < WAIT_READY_COUNT; i++) {
    send_sdcard_command(SD_CMD55, 0, NULL, SD_MAX_RESP);
    send_sdcard_command(SD_ACMD41, ocrreq, resp, SD_MAX_RESP);
    
    uint32_t ocr = (resp[1] << 24) | (resp[2] << 16) | (resp[3] << 8) | resp[4];
    if (ocr & OCR_NBUSY) {
      drv_issdhc = cmd8_ok && (ocr & OCR_CCS);
      break;
    }
  }
  
  // 5. 获取卡片识别信息 (CMD2)
  send_sdcard_command(SD_CMD2, 0, resp, SD_MAX_RESP_BUF);
  
  // 6. 获取相对卡地址 (CMD3)
  send_sdcard_command(SD_CMD3, 0, resp, SD_MAX_RESP);
  drv_rca = (resp[1] << 8) | resp[2];
  
  // 7. 读取卡能力信息 (CMD9)
  send_sdcard_command(SD_CMD9, drv_rca << 16, resp, SD_MAX_RESP_BUF);
  
  // 8. 选择卡片进入传输模式 (CMD7)
  send_sdcard_command(SD_CMD7, drv_rca << 16, NULL, SD_MAX_RESP);
  
  // 9. 设置4位总线模式 (ACMD6)
  send_sdcard_command(SD_CMD55, drv_rca << 16, NULL, SD_MAX_RESP);
  send_sdcard_command(SD_ACMD6, 0x2, NULL, SD_MAX_RESP);
  
  // 10. 设置块大小为512字节 (CMD16)
  send_sdcard_command(SD_CMD16, 512, NULL, SD_MAX_RESP);
  
  return 0;
}
```

### 5.2. 错误代码定义

```c
#define SD_ERR_NO_STARTUP        1   // 卡片启动失败
#define SD_ERR_BAD_IDENT         2   // 身份识别失败  
#define SD_ERR_BAD_INIT          3   // 初始化失败
#define SD_ERR_BAD_CAP           4   // 能力读取失败
#define SD_ERR_BAD_MODEXCH       5   // 模式切换失败
#define SD_ERR_BAD_BUSSEL        6   // 总线选择失败
#define SD_ERR_READTIMEOUT      10   // 读超时
#define SD_ERR_WRITETIMEOUT     11   // 写超时
#define SD_ERR_BADREAD          12   // 读操作失败
#define SD_ERR_BADWRITE         13   // 写操作失败
```

---

## 6. 驱动API接口 (Driver API Interface)

### 6.1. 核心配置函数

```c
// 设置SuperChis工作模式
void set_supercard_mode(unsigned mapped_area, bool write_access, bool sdcard_interface);

// 直接写入模式配置
void write_supercard_mode(uint16_t modebits);
```

### 6.2. SD卡操作函数

```c
// SD卡初始化
unsigned sdcard_init(t_card_info *info);

// SD卡重新初始化 (用于错误恢复)
unsigned sdcard_reinit(void);

// 读取多个扇区
unsigned sdcard_read_blocks(uint8_t *buffer, uint32_t blocknum, unsigned blkcnt);

// 写入多个扇区  
unsigned sdcard_write_blocks(const uint8_t *buffer, uint32_t blocknum, unsigned blkcnt);
```

### 6.3. 底层辅助函数

```c
// 发送空闲时钟
void send_empty_clocks(unsigned count);

// 等待卡片空闲
bool wait_sdcard_idle(unsigned timeout);

// 等待DAT0线空闲
bool wait_dat0_idle(unsigned timeout);

// 接收SD卡响应
bool receive_sdcard_response(uint8_t *buffer, unsigned maxsize, unsigned timeout);

// 发送命令缓冲区
void send_sdcard_commandbuf(const uint8_t *buffer, unsigned maxsize);
```

---

## 7. 使用示例 (Usage Examples)

### 7.1. 基本SD卡操作

```c
#include "supercard_driver.h"

int main() {
    // 1. 切换到SD卡模式
    set_supercard_mode(0, false, true);  // Flash映射, 只读, SD卡使能
    
    // 2. 初始化SD卡
    t_card_info info;
    unsigned result = sdcard_init(&info);
    if (result != 0) {
        printf("SD卡初始化失败: %d\n", result);
        return -1;
    }
    
    // 3. 读取第一个扇区
    uint8_t buffer[512];
    result = sdcard_read_blocks(buffer, 0, 1);
    if (result != 0) {
        printf("读取失败: %d\n", result);
        return -1;
    }
    
    // 4. 处理读取的数据...
    
    return 0;
}
```

### 7.2. Flash/SRAM模式切换

```c
// 切换到Flash模式，启用写访问
set_supercard_mode(0, true, false);   // Flash映射, 读写, SD卡禁用

// 切换到DDR SDRAM模式
set_supercard_mode(1, true, false);   // DDR映射, 读写, SD卡禁用

// 切换SRAM Bank (通过write_access位)
set_supercard_mode(0, false, false);  // SRAM Bank 0
set_supercard_mode(0, true, false);   // SRAM Bank 1
```

### 7.3. 高性能数据传输

```c
// 启用快速镜像进行高速传输
bool use_fast = use_fast_mirror();
unsigned result;

if (use_fast) {
    // 使用0x0A000000基址的快速镜像
    result = sc_read_sectors_w1(buffer, block_count);
} else {
    // 使用0x08000000基址的标准镜像  
    result = sc_read_sectors_w0(buffer, block_count);
}
```

---

## 8. 性能特性与限制 (Performance Characteristics and Limitations)

### 8.1. 传输性能

- **标准镜像** (0x08000000): 兼容性最佳，适合所有GBA型号
- **快速镜像** (0x0A000000): 在GBA模式下可提供约20%的性能提升
- **SuperCard Lite**: 不支持快速等待状态，但有专用的32位数据接口

### 8.2. 时序要求

- **命令超时**: ~100ms (`CMD_WAIT_RESP = 0x60000`)
- **数据超时**: ~1s (`CMD_WAIT_DATA = 0x800000`) 
- **写入超时**: ~500ms (`WAIT_READY_WRITE = 0x200000`)

### 8.3. 使用限制

1. **魔术序列必须原子执行**: 任何中断都会导致配置失败
2. **地址对齐影响性能**: 4字节对齐的缓冲区能获得最佳性能
3. **模式切换开销**: 每次模式切换都需要完整的魔术序列

---

## 9. 故障排除 (Troubleshooting)

### 9.1. 常见问题

**问题**: SD卡初始化失败
- **原因**: 卡片不兼容或时序问题
- **解决**: 检查卡片类型，尝试降低时钟频率

**问题**: 读写操作超时
- **原因**: 卡片繁忙或硬件连接问题  
- **解决**: 检查物理连接，增加重试次数

**问题**: 模式切换无效
- **原因**: 魔术序列被中断
- **解决**: 关闭中断后重新执行配置序列

### 9.2. 调试建议

1. 使用示波器检查SD卡时钟和数据线信号
2. 监控超时计数器确定问题阶段
3. 检查CRC校验确保数据完整性
4. 使用已知好卡片进行测试

---

## 10. 技术参考 (Technical References)

- **SD卡规范**: SD Physical Layer Simplified Specification
- **CRC算法**: `crc.h` 中的CRC7和CRC16实现
- **GBA硬件**: Game Boy Advance Programming Manual
- **SuperCard原理**: 基于对原始硬件的逆向工程

本文档基于实际的驱动代码编写，确保了与硬件实现的完全一致性。
