#!/usr/bin/env python3
"""验证修正后的SDRAM模拟器功能"""

from sdram_simulator import SDRAMSimulator

def decode_sdram_command(nRAS, nCAS, nWE):
    """解码SDRAM命令"""
    if nRAS and nCAS and nWE:
        return "NOP", "🔄"
    elif not nRAS and not nCAS and nWE:
        return "REFRESH/ACT", "📖"
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
def test_read_write_commands():
    """测试读写命令生成"""
    print("=== READ/WRITE命令测试 ===")
    
    simulator = SDRAMSimulator()
    simulator.reset()
    simulator.config_map_reg = 1  # 启用SDRAM映射
    simulator.config_write_enable = 1
    simulator.set_clock(0)
    # 设置地址
    simulator.GP_AD = [0] * 24 # 地址为0
    simulator.GP_AD[1] = 1     # 设置一些地址位用于测试
    simulator.GP_AD[2] = 1     # 地址 = 0x006
    
    print("🔧 初始化40000周期...")
    # 初始设置：所有信号无效
    simulator.GP_nCS = True    # 芯片未选择
    simulator.GP_NRD = True    # 读禁止
    simulator.GP_NWR = True    # 写禁止
    
    # 运行40000个周期进行初始化
    for i in range(40000):
        simulator.clock_edge()
    
    print("✅ 初始化完成")
    print(f"初始状态: REF={simulator.sdram_refresh_mode} CMD={simulator.sdram_cmd_active} PRE={simulator.sdram_precharge_mode} ACC={simulator.sdram_access_enable}")
    
    
    def run_sequence(name, signal_sequence):
        """运行信号序列并统计命令"""
        print(f"\n📖 {name}:")
        read_commands = 0
        write_commands = 0
        cycle_count = 0
        
        for step_name, ncs, nrd, nwr, edges in signal_sequence:
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
                print(f"  周期 {cycle_count}: REF{simulator.sdram_refresh_mode}CMD{simulator.sdram_cmd_active}PRE{simulator.sdram_precharge_mode}ACC{simulator.sdram_access_enable} -> {cmd} {emoji} {'(自动PRECHARGE)' if is_auto_precharge else ''}")
                
                # 统计命令
                if cmd == "READ":
                    read_commands += 1
                elif cmd == "WRITE":
                    write_commands += 1
                elif cmd == "PRECHARGE":
                    print(f"   🎯 发现PRECHARGE命令！")
                elif cmd == "ROW_ACT":
                    print(f"   🏦 ROW_ACTIVATE") if edges <= 2 else None
        
        return read_commands, write_commands, cycle_count
    
    # 定义READ操作序列
    read_sequence = [
        ("拉高CS", True, True, True, 1),     
        ("拉低CS", False, True, True, 3),     # 片选激活
        ("拉低NRD", False, False, True, 12),   # 读使能激活
        ("拉高NRD", False, True, True, 4),    # 读使能释放
        ("拉低NRD", False, False, True, 12),   # 读使能激活
        ("拉高NRD", False, True, True, 4),    # 读使能释放
        ("拉低NRD", False, False, True, 12),   # 读使能激活
        ("拉高NRD但保持CS低", False, True, True, 4),  # 延长等待时间
        ("拉高CS", True, True, True, 4),
    ]
    
    # 定义READ到WRITE的正确时序
    read_to_write_sequence = [
        ("拉高CS", True, True, True, 2),     
        ("拉低CS", False, True, True, 2),     # 重新拉低CS
        ("拉低NWR", False, True, False, 12),   # 写使能激活
        ("拉高NWR", False, True, True, 4),    # 写使能释放
        ("拉低NWR", False, True, False, 12),   # 写使能激活
        ("拉高NWR", False, True, True, 4),    # 写使能释放
        ("拉低NWR", False, True, False, 12),   # 写使能激活
        ("拉高NWR但保持CS低", False, True, True, 4),  # 延长等待时间
        ("拉高CS", True, True, True, 4),
    ]
    
    # 执行READ操作
    r_cmds, w_cmds, cycles = run_sequence("READ操作序列", read_sequence)
    total_read = r_cmds
    total_write = w_cmds
    total_cycles = cycles
    
    # 执行READ到WRITE转换
    r_cmds, w_cmds, cycles = run_sequence("READ到WRITE转换序列", read_to_write_sequence)
    total_read += r_cmds
    total_write += w_cmds
    total_cycles += cycles
    
    print(f"\n📊 总结:")
    print(f"  READ命令数量: {total_read}")
    print(f"  WRITE命令数量: {total_write}")
    print(f"  总共运行周期: {total_cycles}")
    
    # 验证结果
    if total_read > 0:
        print("  ✅ READ命令生成成功")
    else:
        print("  ❌ READ命令生成失败")
        
    if total_write > 0:
        print("  ✅ WRITE命令生成成功")
    else:
        print("  ❌ WRITE命令生成失败")

def test_state_transitions():
    """测试状态转换"""
    print("\n=== 状态转换测试 ===")
    
    simulator = SDRAMSimulator()
    simulator.reset()
    simulator.config_map_reg = 1
    simulator.config_write_enable = 1
    
    # 快速初始化
    for _ in range(40000):
        simulator.clock_edge()
    
    print("跟踪关键状态转换:")
    states_seen = set()
    
    # 定义测试序列：更细致的控制
    test_sequence = [
        ("空闲", True, True, True, 2),
        ("激活CS", False, True, True, 2), 
        ("开始读", False, False, True, 3),
        ("结束读", False, True, True, 2),
        ("释放CS", True, True, True, 3),  # 正确的时序：先释放CS
        ("重新激活CS", False, True, True, 2),
        ("开始写", False, True, False, 3),
        ("结束写", False, True, True, 2),
        ("最终释放", True, True, True, 2),
    ]
    
    for step_name, ncs, nrd, nwr, cycles in test_sequence:
        print(f"\n🔄 {step_name} (nCS={ncs}, NRD={nrd}, NWR={nwr}):")
        
        simulator.GP_nCS = ncs
        simulator.GP_NRD = nrd
        simulator.GP_NWR = nwr
        
        for i in range(cycles):
            old_state = (simulator.sdram_refresh_mode, simulator.sdram_cmd_active, 
                        simulator.sdram_precharge_mode, simulator.sdram_access_enable)
            
            simulator.clock_edge()
            
            new_state = (simulator.sdram_refresh_mode, simulator.sdram_cmd_active, 
                        simulator.sdram_precharge_mode, simulator.sdram_access_enable)
            
            states_seen.add(new_state)
            
            if old_state != new_state:
                print(f"  周期 {i+1}: {old_state} -> {new_state}")
            
            # 检查重要状态
            if new_state == (0, 0, 1, 1):
                cmd_type = "READ" if (simulator.nRAS == 1 and simulator.nCAS == 0 and simulator.nWE == 1) else "WRITE" if (simulator.nRAS == 1 and simulator.nCAS == 0 and simulator.nWE == 0) else "其他"
                print(f"    🎯 到达目标状态! 命令类型: {cmd_type}")
    
    print(f"\n📈 观察到的状态数量: {len(states_seen)}")
    print("所有状态:", sorted(states_seen))

if __name__ == "__main__":
    test_read_write_commands()
    # test_state_transitions()
