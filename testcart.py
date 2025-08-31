
import struct
import serial
import random
import time
import math

import serial.tools.list_ports

# 设备配置
deviceSize = 32*1024**2  # 32MB

# SuperChis配置常量
MAGIC_ADDRESS = 0x01FFFFFE  # 魔术解锁地址 (GBA字节地址0x09FFFFFE)
MAGIC_VALUE = 0xA55A        # 魔术解锁值

# 配置位定义
CONFIG_MAP_DDR = 0x01       # Bit 0: 内存映射控制 (0=Flash, 1=DDR)
CONFIG_SD_ENABLE = 0x02     # Bit 1: SD卡接口使能
CONFIG_WRITE_ENABLE = 0x04  # Bit 2: 写使能控制

def writeRom(addr_word, dat):
    """
    向ROM地址写入数据
    
    Args:
        addr_word: 字地址 (16位字)
        dat: 要写入的数据 (可以是int或bytes)
    """
    if isinstance(dat, int):
        dat = struct.pack("<H", dat)

    cmd = []
    cmd.extend(struct.pack("<H", 2 + 1 + 4 + len(dat) + 2))
    cmd.append(0xf5)
    cmd.extend(struct.pack("<I", addr_word))
    cmd.extend(dat)
    cmd.extend([0, 0])

    ser.write(cmd)
    ack = ser.read(1)
    return ack

def readRom(addr_word, length_byte):
    """
    从ROM地址读取数据
    
    Args:
        addr_word: 字地址 (16位字)
        length_byte: 要读取的字节数
        
    Returns:
        读取到的数据 (bytes)
    """
    cmd = []
    cmd.extend(struct.pack("<H", 2 + 1 + 4 + 2 + 2))
    cmd.append(0xf6)
    cmd.extend(struct.pack("<I", addr_word << 1))  # 转换为字节地址
    cmd.extend(struct.pack("<H", length_byte))
    cmd.extend([0, 0])

    ser.write(cmd)
    respon = ser.read(length_byte + 2)
    return respon[2:]  # 跳过前2字节状态

def writeRam(addr, dat):
    """
    向RAM地址写入数据
    
    Args:
        addr: 字节地址
        dat: 要写入的数据
    """
    if isinstance(dat, int):
        dat = struct.pack("B", dat)

    cmd = []
    cmd.extend(struct.pack("<H", 2 + 1 + 4 + len(dat) + 2))
    cmd.append(0xf7)
    cmd.extend(struct.pack("<I", addr))
    cmd.extend(dat)
    cmd.extend([0, 0])

    ser.write(cmd)
    ack = ser.read(1)
    return ack

def readRam(addr, length_byte):
    """
    从RAM地址读取数据
    
    Args:
        addr: 字节地址
        length_byte: 要读取的字节数
        
    Returns:
        读取到的数据 (bytes)
    """
    cmd = []
    cmd.extend(struct.pack("<H", 2 + 1 + 4 + 2 + 2))
    cmd.append(0xf8)
    cmd.extend(struct.pack("<I", addr))
    cmd.extend(struct.pack("<H", length_byte))
    cmd.extend([0, 0])

    ser.write(cmd)
    respon = ser.read(length_byte + 2)
    return respon[2:]  # 跳过前2字节状态

def set_sc_mode(sdram, sd_enable, write_enable):
    """
    执行SuperChis解锁序列
    
    解锁序列：
    1. 向魔术地址 0x00FFFFFF 写入两次 0xA55A
    2. 向魔术地址 0x00FFFFFF 写入两次配置值 (sdram | (sd_enable << 1) | (write_enable << 2))
    """
    
    magic_addr_word = MAGIC_ADDRESS >> 1  # 转换为字地址
    config1 = sdram | (sd_enable << 1) | (write_enable << 2)
    writeRom(magic_addr_word, MAGIC_VALUE)
    writeRom(magic_addr_word, MAGIC_VALUE)
    writeRom(magic_addr_word, config1)
    writeRom(magic_addr_word, config1)
    return True

def diagnoseSuperChis():
    """诊断SuperChis配置状态"""
    print("\n--- SuperChis诊断 ---")
    
    try:
        # 测试Flash模式和SDRAM模式的差异
        print("1. 测试Flash/SDRAM模式切换...")
        
        test_addr = 0x00000100
        test_value = 0x1357
        
        # Flash模式测试
        set_sc_mode(sdram=0, sd_enable=0, write_enable=1)
        time.sleep(0.01)
        
        addr_word = test_addr >> 1
        writeRom(addr_word, test_value)
        flash_data = readRom(addr_word, 2)
        flash_value = struct.unpack("<H", flash_data)[0]
        
        # SDRAM模式测试  
        set_sc_mode(sdram=1, sd_enable=0, write_enable=1)
        time.sleep(0.01)
        
        writeRom(addr_word, test_value)
        sdram_data = readRom(addr_word, 2)
        sdram_value = struct.unpack("<H", sdram_data)[0]
        
        print(f"Flash模式写入: 0x{test_value:04X}, 读取: 0x{flash_value:04X}")
        print(f"SDRAM模式写入: 0x{test_value:04X}, 读取: 0x{sdram_value:04X}")
        
        if flash_value != sdram_value:
            print("✓ Flash/SDRAM模式切换正常")
        else:
            print("✗ Flash/SDRAM模式切换可能有问题")
            
        # 测试写使能
        print("\n2. 测试写使能功能...")
        
        # 写使能关闭
        set_sc_mode(sdram=1, sd_enable=0, write_enable=0)
        time.sleep(0.01)
        
        original_data = readRom(addr_word, 2)
        original_value = struct.unpack("<H", original_data)[0]
        
        writeRom(addr_word, 0x9999)  # 尝试写入
        after_write = readRom(addr_word, 2)
        after_value = struct.unpack("<H", after_write)[0]
        
        if original_value == after_value:
            print("✓ 写使能=0时写入被正确阻止")
        else:
            print("✗ 写使能=0时写入未被阻止")
            
        # 写使能开启
        set_sc_mode(sdram=1, sd_enable=0, write_enable=1)
        time.sleep(0.01)
        
        writeRom(addr_word, 0x6666)
        enabled_data = readRom(addr_word, 2) 
        enabled_value = struct.unpack("<H", enabled_data)[0]
        
        if enabled_value == 0x6666:
            print("✓ 写使能=1时写入正常")
        else:
            print(f"✗ 写使能=1时写入失败: 期望 0x6666, 实际 0x{enabled_value:04X}")
            
        # 测试魔术地址
        print("\n3. 测试魔术地址访问...")
        magic_addr_word = MAGIC_ADDRESS >> 1
        
        # 向魔术地址写入普通数据
        writeRom(magic_addr_word, 0x1122)
        magic_data = readRom(magic_addr_word, 2)
        magic_value = struct.unpack("<H", magic_data)[0]
        
        print(f"魔术地址 0x{MAGIC_ADDRESS:08X} 读取: 0x{magic_value:04X}")
        
        return True
        
    except Exception as e:
        print(f"诊断过程异常: {e}")
        return False

def testBasicReadWrite(test_addr = 0x00000000):
    """基础读写测试"""
    print("\n--- 基础读写测试 ---")
    # GBA ROM区域起始
    test_data = [0x1234, 0x5678, 0xABCD, 0xEF00]
    
    print(f"测试地址: 0x{test_addr:08X}")
    print(f"测试数据: {[hex(x) for x in test_data]}")
    
    try:
        # 写入测试数据
        addr_word = test_addr >> 1
        for i, data in enumerate(test_data):
            writeRom(addr_word + i, data)
        
        # 读取并校验
        errors = 0
        for i, expected in enumerate(test_data):
            actual_bytes = readRom(addr_word + i, 2)
            actual = struct.unpack("<H", actual_bytes)[0]
            
            if actual != expected:
                print(f"✗ 地址 0x{test_addr + i*2:08X}: 期望 0x{expected:04X}, 实际 0x{actual:04X}")
                errors += 1
            else:
                print(f"✓ 地址 0x{test_addr + i*2:08X}: 0x{actual:04X}")
        
        if errors == 0:
            print("✓ 基础读写测试通过!")
            return True
        else:
            print(f"✗ 基础读写测试失败! {errors} 个错误")
            return False
            
    except Exception as e:
        print(f"✗ 基础读写测试异常: {e}")
        return False

def testWriteProtection(test_addr = 0x00002000):
    """测试写保护功能"""
    print("\n--- 写保护功能测试 ---")
    test_value1 = 0x1234
    test_value2 = 0x5678
    
    try:
        addr_word = test_addr >> 1
        
        # 1. 首先确保写使能开启时可以正常写入
        print("1. 验证写使能状态下正常写入...")
        set_sc_mode(sdram=1, sd_enable=0, write_enable=1)
        time.sleep(0.01)
        
        writeRom(addr_word, test_value1)
        time.sleep(0.001)
        
        actual_bytes = readRom(addr_word, 2)
        actual = struct.unpack("<H", actual_bytes)[0]
        
        if actual != test_value1:
            print(f"✗ 写使能状态下写入失败: 期望 0x{test_value1:04X}, 实际 0x{actual:04X}")
            return False
        
        print(f"✓ 写使能状态下写入成功: 0x{actual:04X}")
        
        # 2. 关闭写使能，测试写保护
        print("2. 测试写保护功能...")
        set_sc_mode(sdram=1, sd_enable=0, write_enable=0)
        time.sleep(0.01)
        
        # 记录写保护前的原始数据
        original_bytes = readRom(addr_word, 2)
        original_value = struct.unpack("<H", original_bytes)[0]
        print(f"   写保护前原始数据: 0x{original_value:04X}")
        
        # 尝试写入新数据
        print(f"   尝试写入新数据: 0x{test_value2:04X}")
        writeRom(addr_word, test_value2)
        time.sleep(0.001)
        
        # 读取数据，检查是否被写入
        protected_bytes = readRom(addr_word, 2)
        protected_value = struct.unpack("<H", protected_bytes)[0]
        
        if protected_value == original_value:
            print(f"✓ 写保护生效: 数据保持为 0x{protected_value:04X}")
        elif protected_value == test_value2:
            print(f"✗ 写保护失效: 数据被写入为 0x{protected_value:04X}")
            return False
        else:
            print(f"✗ 意外情况: 原始 0x{original_value:04X}, 写入 0x{test_value2:04X}, 读取 0x{protected_value:04X}")
            return False
        
        # 3. 重新开启写使能，验证写入恢复正常
        print("3. 验证重新开启写使能后写入恢复...")
        set_sc_mode(sdram=1, sd_enable=0, write_enable=1)
        time.sleep(0.01)
        
        writeRom(addr_word, test_value2)
        time.sleep(0.001)
        
        final_bytes = readRom(addr_word, 2)
        final_value = struct.unpack("<H", final_bytes)[0]
        
        if final_value == test_value2:
            print(f"✓ 写使能恢复正常: 0x{final_value:04X}")
        else:
            print(f"✗ 写使能恢复失败: 期望 0x{test_value2:04X}, 实际 0x{final_value:04X}")
            return False
        
        # 4. 测试多个地址的写保护
        print("4. 测试多个地址的写保护...")
        test_addresses = [0x00003000, 0x00004000, 0x00005000]
        
        set_sc_mode(sdram=1, sd_enable=0, write_enable=0)
        time.sleep(0.01)
        
        protection_errors = 0
        for addr in test_addresses:
            addr_word = addr >> 1
            
            # 读取原始数据
            orig_bytes = readRom(addr_word, 2)
            orig_val = struct.unpack("<H", orig_bytes)[0]
            
            # 尝试写入
            new_val = 0x9999
            writeRom(addr_word, new_val)
            time.sleep(0.001)
            
            # 检查是否被保护
            check_bytes = readRom(addr_word, 2)
            check_val = struct.unpack("<H", check_bytes)[0]
            
            if check_val == orig_val:
                print(f"   ✓ 地址 0x{addr:08X} 写保护正常")
            else:
                print(f"   ✗ 地址 0x{addr:08X} 写保护失效")
                protection_errors += 1
        
        if protection_errors == 0:
            print("✓ 多地址写保护测试通过")
        else:
            print(f"✗ {protection_errors} 个地址写保护失效")
            return False
        
        print("✓ 写保护功能测试全部通过!")
        return True
        
    except Exception as e:
        print(f"✗ 写保护测试异常: {e}")
        return False

def verifySDRAM():
    """验证SDRAM写入功能 - 详细诊断"""
    print("\n--- SDRAM写入验证测试 ---")
    
    # 测试多个地址和数据模式
    test_cases = [
        (0x00001000, 0xDEAD),
        (0x00001002, 0xBEEF), 
        (0x00001004, 0x1234),
        (0x00001006, 0x5678),
        (0x00001008, 0xABCD),
        (0x0000100A, 0xEF00),
        (0x0000100C, 0x0000),
        (0x0000100E, 0xFFFF),
        (0x00F0100E, 0xDEAD),
        (0x00F0100C, 0xBEEF), 
        (0x00F0100A, 0x1234),
        (0x00F01008, 0x5678),
        (0x00F01006, 0xABCD),
        (0x00F01004, 0xEF00),
        (0x00F01002, 0x0000),
        (0x00F01000, 0xFFFF),
        (0x01001000, 0xDEAD),
        (0x01001002, 0xBEEF), 
        (0x01001004, 0x1234),
        (0x01001006, 0x5678),
        (0x01001008, 0xABCD),
        (0x0100100A, 0xEF00),
        (0x0100100C, 0x0000),
        (0x0100100E, 0xFFFF),
        (0x00450496, 0x1234),
        (0x002EEC96, 0x74AF),
        (0x00A9170A, 0xEF00),
        (0x00F6A70A, 0xAFE7)
    ]
    # # 随机地址，随机数据
    random.seed(42)
    same = set([x[0] for x in test_cases])
    for _ in range(200):
        addr = random.randint(0, 0x01FFFFFF)
        addr = addr - (addr % 2)
        val = random.randint(0, 0xFFFF)
        if addr not in same:
            same.add(addr)
            test_cases.append((addr, val))

    print("测试多个地址和数据模式...")
    errors = 0
    
    for test_addr, test_value in test_cases:
        try:
            addr_word = test_addr >> 1
            
            # 写入测试数据
            writeRom(addr_word, test_value)
                
        except Exception as e:
            print(f"✗ 地址 0x{test_addr:08X} 测试异常: {e}")
            errors += 1
    
    set_sc_mode(sdram=0, sd_enable=0, write_enable=0)
    time.sleep(0.6)
    set_sc_mode(sdram=1, sd_enable=0, write_enable=1)
    for test_addr, test_value in test_cases[::-1]:
        try:
            # 读取并验证
            addr_word = test_addr >> 1
            actual_bytes = readRom(addr_word, 2)
            actual = struct.unpack("<H", actual_bytes)[0]
            
            if actual == test_value:
                print(f"✓ 地址 0x{test_addr:08X}: 写入 0x{test_value:04X}, 读取 0x{actual:04X}")
            else:
                print(f"✗ 地址 0x{test_addr:08X}: 写入 0x{test_value:04X}, 读取 0x{actual:04X}")
                # 分析差异
                xor_diff = test_value ^ actual
                print(f"    XOR差异: 0x{xor_diff:04X} (二进制: {xor_diff:016b})")
                errors += 1
        except Exception as e:
            print(f"✗ 地址 0x{test_addr:08X} 测试异常: {e}")
            errors += 1

    # 测试地址线
    print("\n测试地址线...")
    addr_line_errors = 0
    base_addr = 0x00000000

    for bit in range(16):  # 测试低16位地址线
        test_addr = base_addr + (1 << bit)
        test_value = 0x1000 + bit  # 每个地址使用不同的值
        
        try:
            addr_word = test_addr >> 1
            writeRom(addr_word, test_value)
            time.sleep(0.001)
            
            actual_bytes = readRom(addr_word, 2)
            actual = struct.unpack("<H", actual_bytes)[0]
            
            if actual == test_value:
                print(f"✓ A{bit}: 地址 0x{test_addr:08X} = 0x{actual:04X}")
            else:
                print(f"✗ A{bit}: 地址 0x{test_addr:08X}, 期望 0x{test_value:04X}, 实际 0x{actual:04X}")
                addr_line_errors += 1
                
        except Exception as e:
            print(f"✗ A{bit} 测试异常: {e}")
            addr_line_errors += 1
    
    # 测试数据线
    print("\n测试数据线...")
    data_line_errors = 0
    test_addr = 0x00002000
    
    for bit in range(16):  # 测试16位数据线
        test_value = 1 << bit
        
        try:
            addr_word = test_addr >> 1
            writeRom(addr_word, test_value)
            time.sleep(0.001)
            
            actual_bytes = readRom(addr_word, 2)
            actual = struct.unpack("<H", actual_bytes)[0]
            
            if actual == test_value:
                print(f"✓ D{bit}: 0x{test_value:04X} = 0x{actual:04X}")
            else:
                print(f"✗ D{bit}: 期望 0x{test_value:04X}, 实际 0x{actual:04X}")
                data_line_errors += 1
                
        except Exception as e:
            print(f"✗ D{bit} 测试异常: {e}")
            data_line_errors += 1
    
    # 总结
    total_errors = errors + addr_line_errors + data_line_errors
    print(f"\n=== 验证结果 ===")
    print(f"基础测试错误: {errors}/8")
    print(f"地址线错误: {addr_line_errors}/16") 
    print(f"数据线错误: {data_line_errors}/16")
    print(f"总错误数: {total_errors}/40")
    
    if total_errors == 0:
        print("✓ SDRAM验证通过!")
        return True
    else:
        print("✗ SDRAM验证失败!")
        return False

def testMemoryPattern(start_addr, length, pattern_name, pattern_func):
    """
    测试内存模式
    
    Args:
        start_addr: 起始地址
        length: 测试长度
        pattern_name: 模式名称
        pattern_func: 生成模式数据的函数
    """
    print(f"\n--- {pattern_name} 测试 ---")
    print(f"地址范围: 0x{start_addr:08X} - 0x{start_addr + length - 1:08X}")
    
    # 生成测试数据
    test_data = pattern_func(length)
    
    # 写入数据
    print("写入测试数据...")
    start_time = time.time()
    
    write_size = 4096
    for offset in range(0, length, write_size):
        chunk_size = min(write_size, length - offset)
        chunk_data = test_data[offset:offset + chunk_size]
        
        # 转换为16位字地址
        addr_word = (start_addr + offset) >> 1
        writeRom(addr_word, chunk_data)
        if offset % (length // 4) == 0:
            progress = (offset / length) * 100
            print(f"写入进度: {progress:.1f}%")
    
    write_time = time.time() - start_time
    print(f"写入完成，耗时: {write_time:.2f}秒")
    
    # 读取并校验数据
    print("读取并校验数据...")
    start_time = time.time()
    
    errors = 0
    read_size = 4096

    for offset in range(0, length, read_size):
        chunk_size = min(read_size, length - offset)
        expected_data = test_data[offset:offset + chunk_size]
        
        # 转换为16位字地址
        addr_word = (start_addr + offset) >> 1
        actual_data = readRom(addr_word, chunk_size)
        
        if actual_data != expected_data:
            errors += 1
            if errors <= 10:  # 只显示前10个错误
                print(f"地址 0x{start_addr + offset:08X} 校验失败:")
                print(f"  期望: {expected_data.hex()}")
                print(f"  实际: {actual_data.hex()}")
        
        if offset % (length // 4) == 0:
            progress = (offset / length) * 100
            print(f"校验进度: {progress:.1f}%")
    
    # 随机读1000次
    print("随机读取1000次进行校验...")
    random_errors = 0
    for _ in range(1000):
        # 生成一个随机的、偶数对齐的偏移量
        offset = random.randint(0, length - 2) & ~1 
        
        addr_word = (start_addr + offset) >> 1
        
        # 读取实际数据
        actual_data = readRom(addr_word, 2)
        
        # 获取期望数据
        expected_data_chunk = test_data[offset:offset+2]
        
        if actual_data != expected_data_chunk:
            random_errors += 1
            if random_errors <= 10: # 只显示前10个随机读错误
                print(f"  ✗ 随机地址 0x{start_addr + offset:08X} 校验失败:")
                print(f"    期望: {expected_data_chunk.hex()}")
                print(f"    实际: {actual_data.hex()}")

    if random_errors > 0:
        print(f"✗ 随机读取测试发现 {random_errors} 个错误")
    else:
        print("✓ 随机读取测试通过")
    
    read_time = time.time() - start_time
    print(f"校验完成，耗时: {read_time:.2f}秒")
    
    total_errors = errors + random_errors
    if total_errors == 0:
        print(f"✓ {pattern_name} 测试通过!")
    else:
        print(f"✗ {pattern_name} 测试失败! 发现 {total_errors} 个错误")
    
    return total_errors == 0
def generatePatternFile(length):
    data = bytearray()
    with open("test.gba", 'rb') as f:
        f.seek(0)
        data = f.read(length)
    return data

def generatePatternAA55(length):
    """生成0xAA55交替模式"""
    data = bytearray()
    for i in range(0, length, 2):
        data.extend([0xAA, 0x55])
    return data[:length]

def generatePattern5500(length):
    """生成0x5500交替模式"""
    data = bytearray()
    for i in range(0, length, 2):
        data.extend([0x55, 0x00])
    return data[:length]

def generatePatternRandom(length):
    """生成随机模式"""
    random.seed(12345)  # 固定种子以便重现
    return bytearray(random.randint(0, 255) for _ in range(length))

def generatePatternIncremental(length):
    """生成递增模式"""
    return bytearray(i & 0xFF for i in range(length))

def lcg32(s):
    """32位线性同余生成器"""
    return (s * 1664525 + 1013904223) & 0xFFFFFFFF

def sdram_stress_test(max_size_mb=4, progress_callback=None):
    """
    SDRAM压力测试 - 简化版本，每次写入2字节，不恢复数据
    
    Args:
        max_size_mb: 最大测试大小(MB)，默认4MB
        progress_callback: 进度回调函数
    
    Returns:
        测试结果: 成功返回True，失败返回负数表示失败位置
    """
    print(f"\n--- SDRAM压力测试 (测试范围: {max_size_mb}MB) ---")
    
    start_seed = 0xdeadbeef
    test_size_words = max_size_mb * 1024 * 1024 // 2  # 转换为16位字数量
    test_size_bytes = test_size_words * 2
    buffer_size = 512  # 512个16位字的缓冲区
    
    # 临时缓冲区用于存储期望的数据
    tmp = bytearray(buffer_size * 2)  # 1KB缓冲区
    
    rndgen = start_seed
    pos = 0
    
    print(f"开始压力测试，测试{test_size_words}个16位字...")
    print("测试模式: 写入随机数据，延迟验证，简化版本")
    
    start_time = time.time()
    
    try:
        for i in range(test_size_words):
            # 验证之前写入的数据 (延迟512个位置)
            if i >= buffer_size:
                prev_pos = (pos - 22541 * buffer_size) & (test_size_words - 1)
                prev_addr = prev_pos * 2  # 转换为字节地址
                
                # 读取SDRAM中的数据
                addr_word = prev_addr >> 1  # 转换为16位字地址
                actual_data = readRom(addr_word, 2)  # 读取2字节(16位)
                actual_value = struct.unpack("<H", actual_data)[0]
                
                # 从tmp中获取期望的值
                buf_idx = i & (buffer_size - 1)
                expected_bytes = tmp[buf_idx*2:(buf_idx+1)*2]
                expected_value = struct.unpack("<H", expected_bytes)[0]
                
                if actual_value != expected_value:
                    print(f"✗ 验证失败在位置 {prev_pos} (0x{prev_addr:08X})")
                    print(f"    期望: 0x{expected_value:04X}, 实际: 0x{actual_value:04X}")
                    print(f"    XOR差异: 0x{expected_value ^ actual_value:04X}")
                    return -i  # 返回负的失败位置
            
            # 生成随机值并存储到临时缓冲区
            current_addr = pos * 2  # 转换为字节地址
            addr_word = current_addr >> 1  # 转换为16位字地址
            
            # 生成16位随机值
            rnd_value = rndgen & 0xFFFF
            rnd_bytes = struct.pack("<H", rnd_value)
            
            # 存储期望值到缓冲区
            buf_idx = i & (buffer_size - 1)
            tmp[buf_idx*2:(buf_idx+1)*2] = rnd_bytes
            
            # 写入随机值到SDRAM
            writeRom(addr_word, rnd_value)
            
            # 更新生成器和位置
            pos = (pos + 22541) & (test_size_words - 1)
            rndgen = lcg32(rndgen)
            
            # 更新进度
            if (i + 1) % 0x1000 == 0: 
                progress = (i + 1) / test_size_words * 100
                elapsed = time.time() - start_time
                print(f"进度: {progress:.1f}% ({i+1}/{test_size_words}), 用时: {elapsed:.1f}秒")
                
                if progress_callback:
                    if progress_callback(i >> 16, test_size_words >> 16):
                        print("测试被用户中断")
                        break
        
        elapsed_time = time.time() - start_time
        print(f"✓ SDRAM压力测试完成! 用时: {elapsed_time:.1f}秒")
        print(f"   测试了 {test_size_words} 个16位字 ({test_size_bytes/1024/1024:.1f}MB)")
        print(f"   平均速度: {test_size_bytes/1024/1024/elapsed_time:.2f} MB/s")
        
        return True
        
    except Exception as e:
        print(f"✗ SDRAM压力测试异常: {e}")
        import traceback
        traceback.print_exc()
        return False

def runMemoryTests(start_addr = 0x00000000):
    """运行完整的内存测试"""
    print("\n=== SuperChis SDRAM 测试 ===")
    
    test_size = 1 * 1024 * 1024  # 测试1MB
    
    tests = [
        # ("文件测试", generatePatternFile),
        ("0xAA55 交替模式", generatePatternAA55),
        ("0x5500 交替模式", generatePattern5500),
        ("递增模式", generatePatternIncremental),
        # ("随机模式", generatePatternRandom)
    ]
    
    passed = 0
    total = len(tests)
    
    for pattern_name, pattern_func in tests:
        if testMemoryPattern(start_addr, test_size, pattern_name, pattern_func):
            passed += 1
    
    print(f"\n=== 测试结果 ===")
    print(f"通过: {passed}/{total}")
    
    if passed == total:
        print("✓ 所有测试通过！SDRAM工作正常。")
    else:
        print("✗ 部分测试失败，请检查SDRAM连接和配置。")
    
    return passed == total

def connectDevice():
    """连接烧卡器设备"""
    print("正在寻找烧卡器...")
    portName = None
    comports = serial.tools.list_ports.comports()
    
    for port in comports:
        if port.vid == 0x0483 and port.pid == 0x0721:
            portName = port.device
            break
    
    if portName is None:
        print("找不到烧卡器")
        return None
    
    print(f"找到烧卡器: {portName}")
    
    try:
        ser = serial.Serial()
        ser.port = portName
        ser.baudrate = 115200
        ser.timeout = 5
        ser.open()
        ser.dtr = True
        ser.dtr = False
        print("烧卡器连接成功")
        return ser
    except Exception as e:
        print(f"连接烧卡器失败: {e}")
        return None

# 主程序
if __name__ == "__main__":
    print("=== SuperChis 烧卡器测试程序 ===")
    print("功能:")
    print("1. 解锁SuperChis芯片")
    print("2. 配置SDRAM模式")
    print("3. 基础读写测试")
    print("4. 完整SDRAM测试")
    print("5. 数据完整性校验")
    print()
    
    # 连接设备
    ser = connectDevice()
    if ser is None:
        exit()
    
    try:
        # 执行解锁序列
        set_sc_mode(sdram=0, sd_enable=0, write_enable=0)
        header = readRom(0xA0>>1, 10)
        set_sc_mode(sdram=1, sd_enable=0, write_enable=1)
        headerSDRAM = readRom(0xA0>>1, 10)
        print(header, headerSDRAM)
        if header == headerSDRAM:
            print("配置未生效，可能烧卡器未正确连接或配置")
            exit(-1)
        else:
            print("SuperChis SDRAM解锁成功，配置已生效")
        print("\n等待配置生效...")
        time.sleep(0.1)
        
        # 验证解锁是否成功
        if not verifySDRAM():
            print("\n解锁验证失败，运行详细诊断...")
            diagnoseSuperChis()
            exit(-1)
        
        # 基础读写测试
        if not testBasicReadWrite(0x0000000) or not testBasicReadWrite(0x1000000):
            print("基础测试失败，跳过完整测试")
            exit(-1)
        
        # 测试写保护
        if not testWriteProtection(0x00002000) or not testWriteProtection(0x1002000):
            print("写保护测试失败")
            exit(-1)
            
        # SDRAM压力测试
        print("\n准备运行SDRAM压力测试...")
        choice = input("是否运行SDRAM压力测试? (推荐，验证数据完整性) [Y/n]: ").lower()
        
        if choice in ['y', 'yes']:
            # 运行SDRAM压力测试
            set_sc_mode(sdram=1, sd_enable=0, write_enable=1)
            time.sleep(0.1)
            
            stress_result = sdram_stress_test(max_size_mb=1)
            
            if stress_result == True:
                print("✓ SDRAM压力测试通过！数据完整性良好。")
            else:
                print(f"✗ SDRAM压力测试失败！问题位置: {stress_result}")
                
        # 询问是否运行完整测试
        print("\n基础测试通过!")
        choice = input("是否运行完整的内存测试? (可能需要几分钟) [y/N]: ").lower()
        
        if choice in ['y', 'yes']:
            # 运行完整内存测试
            set_sc_mode(sdram=1, sd_enable=0, write_enable=1)
            success = runMemoryTests()
            
            if success:
                print("\n🎉 所有测试通过！SuperChis工作正常。")
            else:
                print("\n❌ 完整测试失败，请检查硬件连接。")
        else:
            print("\n跳过完整测试。基础功能正常。")
        
    except KeyboardInterrupt:
        print("\n测试被用户中断")
    except Exception as e:
        print(f"\n测试过程中发生错误: {e}")
        import traceback
        traceback.print_exc()
    finally:
        # 关闭连接
        print("\n关闭烧卡器连接...")
        if 'ser' in locals() and ser.is_open:
            ser.close()
        print("测试完成")
