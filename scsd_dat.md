# SCSD烧录卡 DAT数据接口详解

## 概述

本文档详细说明SCSD烧录卡的DAT数据接口工作机制，包括4位并行数据传输、16位移位寄存器原理、数据读写时序以及状态检测机制。基于对superfw固件代码的深入分析。

## 硬件架构

### 1. GBA总线与SD卡接口关系

```
GBA CPU (ARM7TDMI) - 16位数据总线
     ↓
SCSD烧录卡 - 16位移位寄存器
     ↓
SD卡 - 4位DAT接口 (DAT3, DAT2, DAT1, DAT0)
```

**关键设计原理**：
- GBA使用16位卡带总线，32位访问 = 2次连续16位访问
- SD卡使用4位并行DAT接口进行数据传输
- SCSD卡内部维护16位移位寄存器，累积4次4位数据形成完整16位

### 2. 地址映射

| 功能寄存器 | GBA地址 | 卡带物理地址 | Python字地址 | 说明 |
|------------|---------|--------------|---------------|------|
| 数据读取寄存器 | 0x09100000 | 0x01100000 | 0x880000 | DAT数据读取 |
| 数据写入寄存器 | 0x09000000 | 0x01000000 | 0x800000 | DAT数据写入 |
| 状态检查寄存器 | 0x09100000 | 0x01100000 | 0x880000 | DAT0状态检测 |
| 快速读取寄存器(镜像) | 0x0B100000 | 0x03100000 | 0x1880000 | 高速读取模式 |
| 快速写入寄存器(镜像) | 0x0B000000 | 0x03000000 | 0x1800000 | 高速写入模式 |
| SuperCard Lite寄存器 | 0x09200000 | 0x01200000 | 0x900000 | 32位直接访问 |

### 3. 状态位定义

```c
#define SD_DATA0    0x0100    // Bit 8，DAT0线状态检测位

// 状态位含义：
// Bit 8 = 1: DAT0空闲（数据传输完成或SD卡不忙）
// Bit 8 = 0: DAT0忙碌（数据传输中或SD卡内部处理中）
```

## 16位移位寄存器工作原理

### 1. 读取时序机制

SCSD卡内部维护一个16位移位寄存器，工作流程如下：

```
时钟周期    GBA访问    SD卡DAT[3:0]    移位寄存器状态    寄存器内容
   1      16位读取#1      4位数据      [----][----][----][4bit]   垃圾数据
   2      16位读取#2      4位数据      [----][----][4bit][4bit]   部分数据  
   3      16位读取#3      4位数据      [----][4bit][4bit][4bit]   垃圾数据
   4      16位读取#4      4位数据      [4bit][4bit][4bit][4bit]   完整数据★
```

**关键发现**：
- 只有第2次和第4次访问包含有效数据
- 完整的16位数据在第4次访问时出现在寄存器高16位
- 这解释了为什么代码中偶数寄存器(r2,r6,r8,r10)被标记为"垃圾"

### 2. 代码验证

#### 标准读取模式（批量访问）
```assembly
// 8次连续16位读取 = 4次完整的16位数据获取
ldmia r5, {r2, r3, r6, r7, r8, r9, r10, r11}

// 数据分布：
// r2,  r6,  r8,  r10 ← 垃圾数据（第1、3次访问）
// r3,  r7,  r9,  r11 ← 有效数据（第2、4次访问）

// 提取有效数据的高16位
bic  r7, r12                    // 清除r7低16位
bic r11, r12                    // 清除r11低16位  
orr  r7,  r7, r3, lsr #16      // r7高16位 | r3高16位
orr r11, r11, r9, lsr #16      // r11高16位 | r9高16位
```

#### 简化读取模式（逐字节）
```assembly
// 2次16位读取 = 1次完整的8位数据获取
ldmia r5, {r2, r3}
lsr r2, r2, #24                 // 提取r2最高8位
lsr r3, r3, #24                 // 提取r3最高8位
strb r2, [buffer], #1
strb r3, [buffer], #1
```

### 3. 写入时序机制

```
时钟周期    GBA访问       锁存器        SD卡DAT[3:0]输出
   1      16位写入#1    锁存8位数据        低4位
   2      16位写入#2        -            高4位
```

**写入代码**：
```assembly
ldrb r2, [buffer], #1           // 加载8位数据
str r2, [SC_WRITE_REGISTER_8]   // 32位写入 = 2次16位操作
```

32位写入自动完成：第1拍锁存数据并发送低4位，第2拍发送高4位。

## 数据传输协议

### 1. 读取操作流程

#### 1.1 等待数据传输开始
```c
bool wait_data_start(uint32_t timeout) {
    volatile uint16_t *status_reg = (volatile uint16_t*)0x09100000;
    
    while (timeout--) {
        uint16_t status = *status_reg;
        if ((status & SD_DATA0) == 0) {  // Bit 8 = 0
            return true;  // 数据传输开始
        }
    }
    return false;  // 超时
}
```

#### 1.2 批量数据读取（512字节扇区）
```c
void read_sector_fast(uint8_t *buffer) {
    volatile uint32_t *data_reg = (volatile uint32_t*)0x09100000;
    uint32_t *buf32 = (uint32_t*)buffer;
    
    // 读取512字节 = 128次32位读取 = 256次16位读取
    for (int i = 0; i < 32; i++) {  // 32组，每组16次32位读取
        uint32_t data[8];
        
        // 16次32位读取 = 32次16位读取 = 16个完整数据
        for (int j = 0; j < 8; j += 2) {
            data[j]   = *data_reg;      // 垃圾数据
            data[j+1] = *data_reg;      // 有效数据
        }
        
        // 提取并合并有效数据
        for (int j = 1; j < 8; j += 2) {
            uint32_t high_data = data[j] & 0xFFFF0000;     // 高16位
            uint32_t low_data = data[j-1] >> 16;           // 前一个的高16位
            *buf32++ = high_data | low_data;
        }
    }
    
    // 读取CRC校验码（16字节）
    for (int i = 0; i < 4; i++) {
        *data_reg;  // 丢弃CRC数据
        *data_reg;
    }
}
```

#### 1.3 逐字节读取（未对齐缓冲区）
```c
void read_sector_slow(uint8_t *buffer) {
    volatile uint32_t *data_reg = (volatile uint32_t*)0x09100000;
    
    // 读取512字节，每2次16位访问得到2字节
    for (int i = 0; i < 256; i++) {
        uint32_t data1 = *data_reg;  // 第1次32位读取
        uint32_t data2 = *data_reg;  // 第2次32位读取
        
        buffer[i*2]     = (data1 >> 24) & 0xFF;  // 第1字节
        buffer[i*2 + 1] = (data2 >> 24) & 0xFF;  // 第2字节
    }
    
    // 丢弃CRC
    for (int i = 0; i < 4; i++) {
        *data_reg;
        *data_reg;
    }
}
```

### 2. 写入操作流程

#### 2.1 发送起始令牌
```c
void send_write_token() {
    volatile uint32_t *write_reg = (volatile uint32_t*)0x09000000;
    
    // 发送预同步序列
    *write_reg = 0xFFFFFFFF;  // 发送全1
    *write_reg = 0xFFFFFFFF;  // 重复
    *write_reg = 0xFFFFFFFF;  // 重复
    
    // 发送起始令牌
    *(volatile uint16_t*)write_reg = 0xFFFF;  // 前导
    *(volatile uint16_t*)write_reg = 0x00FE;  // 起始令牌 0xFE
}
```

#### 2.2 发送数据块（512字节）
```c
void write_sector_data(const uint8_t *buffer) {
    volatile uint32_t *write_reg = (volatile uint32_t*)0x09000000;
    
    // 逐字节发送512字节数据
    for (int i = 0; i < 512; i++) {
        *write_reg = buffer[i];  // 32位写入，自动处理8位→4位+4位
    }
}
```

#### 2.3 发送CRC并接收状态
```c
uint8_t write_sector_finish(uint16_t crc) {
    volatile uint32_t *write_reg = (volatile uint32_t*)0x09000000;
    
    // 发送16位CRC
    *write_reg = (crc >> 8) & 0xFF;   // CRC高字节
    *write_reg = crc & 0xFF;          // CRC低字节
    
    // 接收3位状态响应 + 1位dummy
    uint8_t status = 0;
    for (int i = 0; i < 4; i++) {
        uint16_t bit = *(volatile uint16_t*)write_reg;
        status = (status << 1) | ((bit & SD_DATA0) ? 1 : 0);
    }
    
    return status & 0x07;  // 返回3位状态码
}
```

### 2.4 等待写入完成
```c
bool wait_write_complete(uint32_t timeout) {
    volatile uint16_t *write_reg = (volatile uint16_t*)0x09000000;
    
    // 等待DAT0线变高，表示SD卡写入完成
    while (timeout--) {
        if (*write_reg & SD_DATA0) {  // Bit 8 = 1
            return true;  // 写入完成
        }
    }
    return false;  // 超时
}
```

## 状态检测机制

### 1. DAT0线状态监控

DAT0线在不同阶段有不同含义：

| 操作阶段 | DAT0=1含义 | DAT0=0含义 | 检测寄存器 |
|----------|------------|------------|------------|
| 读取等待 | 等待数据 | 数据开始传输 | SC_READ_REGISTER_16 |
| 读取过程 | 无数据/结束 | 有数据传输 | SC_READ_REGISTER_16 |
| 写入状态接收 | 状态位='1' | 状态位='0' | SC_WRITE_REGISTER_8 |
| 写入完成等待 | SD卡空闲 | SD卡忙碌 | SC_WRITE_REGISTER_8 |

### 2. 超时机制

```c
// 推荐超时值
#define CMD_WAIT_DATA    0x400000   // 约1秒，数据传输超时
#define WAIT_READY_WRITE 0x200000   // 约500ms，写入完成超时
```

### 3. 错误检测

#### 写入状态码含义
- `010` (0x2): 数据被接受，无错误
- `101` (0x5): 数据被拒绝，CRC错误  
- `110` (0x6): 数据被拒绝，写入错误

## SuperCard Lite优化模式

SuperCard Lite提供了简化的32位直接访问模式：

```c
// SuperCard Lite快速读取
void sclite_read_sector(uint8_t *buffer) {
    volatile uint32_t *data_reg = (volatile uint32_t*)0x09200000;
    uint32_t *buf32 = (uint32_t*)buffer;
    
    // 直接128次32位读取，无需处理移位寄存器
    for (int i = 0; i < 128; i++) {
        buf32[i] = *data_reg;
    }
    
    // 读取CRC（2次32位）
    *data_reg;
    *data_reg;
}
```

SuperCard Lite模式优势：
- 无移位寄存器延迟
- 无垃圾数据处理
- 直接32位对齐访问
- 更高的传输效率

## Python实现要点

### 1. 地址转换示例
```python
# 物理地址定义
SC_READ_REGISTER_PHY  = 0x01100000  # 读取寄存器
SC_WRITE_REGISTER_PHY = 0x01000000  # 写入寄存器

# 转换为16位字地址
READ_REG_WORD_ADDR  = SC_READ_REGISTER_PHY >> 1   # 0x880000
WRITE_REG_WORD_ADDR = SC_WRITE_REGISTER_PHY >> 1  # 0x800000
```

### 2. 移位寄存器模拟
```python
def read_dat_byte_pair():
    """读取2字节数据，模拟16位移位寄存器"""
    # 第1次32位读取（2次16位）- 部分数据
    data1_low  = readRom(READ_REG_WORD_ADDR, 2)     # 垃圾
    data1_high = readRom(READ_REG_WORD_ADDR, 2)     # 第1字节在高8位
    
    # 第2次32位读取（2次16位）- 完整数据  
    data2_low  = readRom(READ_REG_WORD_ADDR, 2)     # 垃圾
    data2_high = readRom(READ_REG_WORD_ADDR, 2)     # 第2字节在高8位
    
    byte1 = (struct.unpack(">H", data1_high)[0] >> 8) & 0xFF
    byte2 = (struct.unpack(">H", data2_high)[0] >> 8) & 0xFF
    
    return bytes([byte1, byte2])
```

### 3. 状态检测
```python
def wait_dat0_ready(timeout=0x400000):
    """等待DAT0线准备就绪"""
    for _ in range(timeout):
        status = readRom(READ_REG_WORD_ADDR, 2)
        status_word = struct.unpack("<H", status)[0]
        if (status_word & 0x0100) == 0:  # DAT0=0表示数据开始
            return True
    return False

def wait_dat0_idle(timeout=0x200000):  
    """等待DAT0线空闲"""
    for _ in range(timeout):
        status = readRom(WRITE_REG_WORD_ADDR, 2)
        status_word = struct.unpack("<H", status)[0]
        if status_word & 0x0100:  # DAT0=1表示空闲
            return True
    return False
```

## 时序图

### 读取时序
```
SD卡CMD → 读命令发送 → 等待响应 → 发送读取扇区命令
   ↓
DAT0检测 → 等待数据开始(DAT0=0) → 数据传输 → 传输完成(DAT0=1)
   ↓  
数据读取 → 16位移位寄存器累积 → 提取有效数据 → 完成
```

### 写入时序  
```
SD卡CMD → 写命令发送 → 等待响应 → 发送写入扇区命令
   ↓
数据发送 → 起始令牌 → 512字节数据 → CRC校验
   ↓
状态接收 → 3位状态码接收 → 写入状态判断
   ↓
完成等待 → 等待DAT0空闲 → 写入完成确认
```

此文档提供了SCSD烧录卡DAT接口的完整技术实现细节，可作为开发SD卡数据传输功能的权威参考。