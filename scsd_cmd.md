# SCSD烧录卡 SD卡CMD通信协议详解

## 概述

本文档详细说明SCSD烧录卡的SD卡CMD指令收发方法、硬件接口和通信流程。基于对superfw固件代码的分析，提供完整的技术实现细节。

## 地址映射

### GBA内存映射 vs 卡带物理地址

由于GBA将卡带映射到`0x08000000`开始的地址空间，存在以下地址对应关系：

| 功能 | GBA地址 | 卡带物理地址 | 说明 |
|------|---------|--------------|------|
| 模式切换寄存器 | 0x09FFFFFE | 0x01FFFFFE | 魔术解锁地址 |
| CMD接口 | 0x09800000 | 0x01800000 | SD卡命令收发接口 |
| ROM镜像基址 | 0x08000000 | 0x00000000 | 卡带起始地址 |

**重要提示：** 
- Python脚本中使用卡带物理地址（需要减去0x08000000偏移量）
- GBA程序中使用GBA映射地址

## 硬件接口定义

### 核心寄存器

```c
// CMD接口寄存器（16位访问）
#define SC_RDWR_COMMAND     0x09800000  // GBA地址
#define SC_RDWR_COMMAND_PHY 0x01800000  // 卡带物理地址

// 模式切换寄存器（16位访问）
#define REG_SC_MODE_REG_ADDR     0x09FFFFFE  // GBA地址  
#define REG_SC_MODE_REG_ADDR_PHY 0x01FFFFFE  // 卡带物理地址
```

### CMD接口位定义

```
SC_RDWR_COMMAND 寄存器（16位）：
┌─────────────────┬───────────┬─────────────────┐
│   Bit 15-8      │   Bit 7   │   Bit 6-1  │ Bit 0 │
│   (保留/未使用)  │ CMD输出位  │  (保留)    │CMD输入位│
└─────────────────┴───────────┴─────────────┴───────┘

Bit 0 (CMD_IN):  从SD卡接收数据（输入）
Bit 7 (CMD_OUT): 向SD卡发送数据（输出）
其他位：保留，功能未定义
```

## 模式切换序列

在进行任何SD卡通信前，必须先切换到SD卡接口模式：

```c
void write_supercard_mode(uint16_t modebits) {
    volatile uint16_t *mode_reg = (volatile uint16_t*)0x09FFFFFE;
    
    // 魔术解锁序列
    *mode_reg = 0xA55A;  // 写入魔术值
    *mode_reg = 0xA55A;  // 重复写入魔术值
    *mode_reg = modebits; // 写入配置值
    *mode_reg = modebits; // 重复写入配置值
}

void set_supercard_mode(unsigned mapped_area, bool write_access, bool sdcard_interface) {
    // 配置位定义：
    // Bit 0: 内存映射控制 (0=Flash固件, 1=SDRAM)
    // Bit 1: SD卡接口使能 (0=关闭, 1=开启)  
    // Bit 2: 写使能控制 (0=只读, 1=可写)
    
    uint16_t value = mapped_area | 
                     (sdcard_interface ? 0x02 : 0x00) | 
                     (write_access ? 0x04 : 0x00);
    write_supercard_mode(value);
}
```

**使用示例：**
```c
// 开启SD卡接口，SDRAM映射，允许写入
set_supercard_mode(1, true, true);
```

## CMD指令发送流程

### 1. 指令包构造

SD卡CMD指令采用6字节固定格式：

```c
uint8_t cmd_buffer[6] = {
    0x40 | cmd_index,    // [0] 起始位(0) + 传输位(1) + 命令索引(6位)
    (arg >> 24) & 0xFF,  // [1] 参数字节3（最高位）
    (arg >> 16) & 0xFF,  // [2] 参数字节2  
    (arg >> 8) & 0xFF,   // [3] 参数字节1
    arg & 0xFF,          // [4] 参数字节0（最低位）
    crc7(cmd_buffer, 5)  // [5] CRC7校验 + 结束位(1)
};
```

### 2. 等待CMD线空闲

发送前必须等待CMD线进入空闲状态：

```c
bool wait_cmd_idle(uint32_t timeout) {
    volatile uint16_t *cmd_reg = (volatile uint16_t*)0x09800000;
    
    while (timeout--) {
        uint16_t status = *cmd_reg;
        if (status & 0x0001) {  // 检查Bit 0
            return true;        // Bit 0 = 1 表示CMD线空闲
        }
    }
    return false;  // 超时
}
```

### 3. 逐位发送数据

```c
void send_cmd_byte(uint8_t data) {
    volatile uint16_t *cmd_reg = (volatile uint16_t*)0x09800000;
    
    // 从最高位(Bit 7)开始发送，到最低位(Bit 0)
    for (int bit = 7; bit >= 0; bit--) {
        uint16_t bit_value = (data >> bit) & 0x01;
        
        // 将要发送的位放在Bit 7位置，通过16位写入
        // 实际硬件只使用Bit 7进行输出
        *cmd_reg = bit_value << 7;
    }
}

void send_cmd_buffer(const uint8_t *buffer, size_t length) {
    for (size_t i = 0; i < length; i++) {
        send_cmd_byte(buffer[i]);
    }
}
```

## CMD响应接收流程

### 1. 等待响应开始

```c
bool wait_response_start(uint32_t timeout) {
    volatile uint16_t *cmd_reg = (volatile uint16_t*)0x09800000;
    
    while (timeout--) {
        uint16_t status = *cmd_reg;
        if ((status & 0x0001) == 0) {  // 检查Bit 0
            return true;               // Bit 0 = 0 表示响应开始
        }
    }
    return false;  // 超时
}
```

### 2. 逐位接收数据

```c
uint8_t receive_cmd_byte(uint32_t timeout) {
    volatile uint16_t *cmd_reg = (volatile uint16_t*)0x09800000;
    uint8_t received_byte = 0;
    
    // 接收8位数据，从最高位到最低位
    for (int bit = 7; bit >= 0; bit--) {
        uint32_t bit_timeout = timeout;
        
        while (bit_timeout--) {
            uint16_t status = *cmd_reg;
            uint8_t input_bit = status & 0x0001;  // 提取Bit 0
            
            // 将接收到的位设置到正确位置
            if (input_bit) {
                received_byte |= (1 << bit);
            }
            break;  // 读取一次即可，实际实现需要适当的时序控制
        }
    }
    
    return received_byte;
}

bool receive_response(uint8_t *buffer, size_t length, uint32_t timeout) {
    if (!wait_response_start(timeout)) {
        return false;  // 等待响应开始失败
    }
    
    for (size_t i = 0; i < length; i++) {
        buffer[i] = receive_cmd_byte(timeout);
    }
    
    return true;
}
```

## 完整CMD交互示例

### 发送CMD0（复位命令）

```c
bool send_cmd0_reset() {
    const uint32_t CMD_WAIT_IDLE = 0x800000;
    
    // 1. 等待CMD线空闲
    if (!wait_cmd_idle(CMD_WAIT_IDLE)) {
        return false;
    }
    
    // 2. 构造CMD0指令包
    uint8_t cmd0_buffer[6] = {
        0x40 | 0,    // CMD0
        0x00, 0x00, 0x00, 0x00,  // 参数为0
        0x95         // CMD0的固定CRC
    };
    
    // 3. 发送指令
    send_cmd_buffer(cmd0_buffer, 6);
    
    // 4. CMD0无响应，发送额外时钟让卡片完成复位
    send_empty_clocks(4096);
    
    return true;
}
```

### 发送CMD8（接口条件检查）

```c
bool send_cmd8_check_interface(uint8_t *response) {
    const uint32_t CMD_WAIT_IDLE = 0x800000;
    const uint32_t CMD_WAIT_RESP = 0x60000;
    
    // 1. 等待CMD线空闲
    if (!wait_cmd_idle(CMD_WAIT_IDLE)) {
        return false;
    }
    
    // 2. 构造CMD8指令包（检查2.7-3.6V电压范围，测试模式0xAA）
    uint8_t cmd8_buffer[6] = {
        0x40 | 8,     // CMD8
        0x00, 0x00,   // 保留位
        0x01,         // 电压范围 2.7-3.6V  
        0xAA,         // 测试模式
        0x87          // CRC7校验
    };
    
    // 3. 发送指令
    send_cmd_buffer(cmd8_buffer, 6);
    
    // 4. 接收R7响应（6字节）
    if (!receive_response(response, 6, CMD_WAIT_RESP)) {
        return false;
    }
    
    // 5. 发送额外时钟
    send_empty_clocks(32);
    
    return true;
}
```

## 时序参数

```c
// 推荐超时值（基于4MHz时钟频率）
#define CMD_WAIT_IDLE    0x800000   // ~2秒，等待CMD线空闲
#define CMD_WAIT_RESP    0x60000    // ~100ms，等待命令响应
#define CMD_WAIT_DATA    0x800000   // ~2秒，等待数据传输
#define INIT_DELAY_CLOCKS   4096    // ~1ms，初始化延迟时钟数
#define CMD_SPACING_CLOCKS    32    // 命令间隔时钟数
```

## Python实现注意事项

在Python测试脚本中实现时需要注意：

1. **地址转换**：使用卡带物理地址（减去0x08000000）
2. **字节序**：注意little-endian格式
3. **时序控制**：通过适当的延迟模拟硬件时序
4. **错误处理**：实现完整的超时和错误检测机制

### Python地址定义示例

```python
# SCSD物理地址定义（用于Python脚本）
SC_RDWR_COMMAND_PHY = 0x01800000  # CMD接口
REG_SC_MODE_REG_PHY = 0x01FFFFFE  # 模式切换寄存器

# 转换为字地址（16位访问）
CMD_REG_WORD_ADDR = SC_RDWR_COMMAND_PHY >> 1
MODE_REG_WORD_ADDR = REG_SC_MODE_REG_PHY >> 1
```

## 常见SD卡命令列表

| 命令 | 索引 | 参数 | 响应 | 说明 |
|------|------|------|------|------|
| CMD0 | 0 | 0x00000000 | 无 | 软件复位 |
| CMD8 | 8 | 0x000001AA | R7 | 接口条件检查 |
| CMD55 | 55 | RCA << 16 | R1 | 应用命令前缀 |
| ACMD41 | 41 | OCR值 | R3 | SD卡初始化 |
| CMD2 | 2 | 0x00000000 | R2 | 获取CID寄存器 |
| CMD3 | 3 | 0x00000000 | R6 | 获取相对地址(RCA) |
| CMD9 | 9 | RCA << 16 | R2 | 获取CSD寄存器 |
| CMD7 | 7 | RCA << 16 | R1b | 选择/取消卡片 |
| CMD13 | 13 | RCA << 16 | R1 | 获取状态 |
| CMD16 | 16 | 块大小 | R1 | 设置块长度 |

此文档提供了完整的SCSD烧录卡SD卡通信技术细节，可作为开发SD卡测试工具的技术参考。