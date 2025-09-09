#!/usr/bin/env python3
"""验证修正后的SDRAM模拟器功能"""

from sdram_simulator import SDRAMSimulator


def decode_sdram_command(nRAS, nCAS, nWE):
    """解码SDRAM命令"""
    if nRAS and nCAS and nWE:
        return "NOP", "🔄"
    elif not nRAS and not nCAS and nWE:
        return "REFRESH", "📖"
    elif not nRAS and nCAS and nWE:
        return "ROW_ACT", "🏦"
    elif nRAS and not nCAS and nWE:
        return "READ", "📚"
    elif nRAS and not nCAS and not nWE:
        return "WRITE", "✏️"
    elif not nRAS and nCAS and not nWE:
        return "PRECHARGE", "💤"
    elif not nRAS and not nCAS and not nWE:
        return "BURST_TERM", "⏹️"
    else:
        return "UNKNOWN", "❓"


def run_sequence(simulator, name, signal_sequence, verbose = True):
    """运行信号序列并统计命令"""
    print(f"\n📖 {name}:")
    cmd_count = {}
    cycle_count = 0
    
    for step_name, ncs, nrd, nwr, edges in signal_sequence:
        if verbose:
            print(f"📌 {step_name} (nCS={ncs}, NRD={nrd}, NWR={nwr}) - {edges}边沿数")

        # 设置信号
        simulator.GP_nCS = ncs
        simulator.GP_NRD = nrd
        simulator.GP_NWR = nwr
        
        # 运行指定周期数
        for i in range(edges):
            simulator.clock_edge()
            if simulator.CLK50Mhz:
                continue
            cycle_count += 1
            cmd, emoji = decode_sdram_command(simulator.nRAS, simulator.nCAS, simulator.nWE)
            is_auto_precharge = cmd == "READ" and simulator.GP_AD[10] == 1
            if verbose:
                print(f"  周期 {cycle_count}: REF{simulator.sdram_refresh_mode}CMD{simulator.sdram_cmd_active}PRE{simulator.sdram_precharge_mode}ACC{simulator.sdram_access_enable} -> {cmd} {emoji} {'(自动PRECHARGE)' if is_auto_precharge else ''}")
            
            # 统计命令
            cmd_count[cmd] = cmd_count.get(cmd, 0) + 1

    return cmd_count, cycle_count


def make_read_sequence(times):
    return [
        ("拉低CS", False, True, True, 4)
    ] + [("拉低NRD", False, False, True, 6), ("拉高NRD", False, True, True, 4)] * times \
    + [("拉高CS", True, True, True, 6)]


def make_write_sequence(times):
    return [
        ("拉低CS", False, True, True, 4)
    ] + [("拉低NWR", False, True, False, 6), ("拉高NWR", False, True, True, 4)] * times \
    + [("拉高CS", True, True, True, 6)]


def make_idle_sequence(times):
    return [("拉高CS", True, True, True, 2)] * times


def test_read_write_commands(times):
    """测试读写命令生成"""
    print("=== READ/WRITE命令测试 ===")
    # READ操作序列
    read_sequence = make_read_sequence(times)
    # WRITE操作序列
    write_sequence = make_write_sequence(times)
    # IDLE序列
    idle_sequence = make_idle_sequence(times)
    simulator = SDRAMSimulator()
    simulator.reset()
    simulator.config_map_reg = 1  # 启用SDRAM映射
    simulator.config_write_enable = 1
    simulator.set_clock(0)
    # 设置地址
    simulator.GP_AD = [0] * 24 # 地址为0
    simulator.GP_AD[1] = 1     # 设置一些地址位用于测试
    simulator.GP_AD[2] = 1     # 地址 = 0x006
    
    print("🔧 初始化13068周期...")
    # 初始设置：所有信号无效
    simulator.GP_nCS = True    # 芯片未选择
    simulator.GP_NRD = True    # 读禁止
    simulator.GP_NWR = True    # 写禁止
    
    # 运行13068个周期进行初始化
    init_cmd_count = {}
    for i in range(13068):
        simulator.clock_edge()
        cmd, emoji = decode_sdram_command(simulator.nRAS, simulator.nCAS, simulator.nWE)
        init_cmd_count[cmd] = init_cmd_count.get(cmd, 0) + 1

    print("✅ 初始化完成")
    print(f"初始状态: REF={simulator.sdram_refresh_mode} CMD={simulator.sdram_cmd_active} PRE={simulator.sdram_precharge_mode} ACC={simulator.sdram_access_enable}")
    for cmd, count in init_cmd_count.items():
        print(f"  {cmd}命令数量: {count}")

    # 执行READ操作
    read_cmd_counts, cycles = run_sequence(simulator, "READ操作序列", read_sequence)
    total_cycles = cycles
    
    # 执行READ到WRITE转换
    write_cmd_counts, cycles = run_sequence(simulator, "WRITE操作序列", write_sequence)
    total_cycles += cycles

    print(f"\n📊 总结:")
    print(f"  总共运行周期: {total_cycles}")
    for key, value in write_cmd_counts.items():
        read_cmd_counts[key] = read_cmd_counts.get(key, 0) + value
    for key, value in read_cmd_counts.items():
        print(f"  {key}命令数量: {value}")
    
    # 验证结果
    if read_cmd_counts.get("READ", 0) > 0:
        print("  ✅ READ命令生成成功")
    else:
        print("  ❌ READ命令生成失败")

    if read_cmd_counts.get("WRITE", 0) > 0:
        print("  ✅ WRITE命令生成成功")
    else:
        print("  ❌ WRITE命令生成失败")
    # 执行IDLE操作
    cmd_counts, cycles = run_sequence(simulator, "IDLE操作序列", idle_sequence, False)
    for cmd, count in cmd_counts.items():
        print(f"  {cmd}命令数量: {count}")

if __name__ == "__main__":
    test_read_write_commands(8)
