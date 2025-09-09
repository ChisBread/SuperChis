#!/usr/bin/env python3
"""
SDRAM仿真器 - 基于equipment.txt的简化但准确实现
SDRAM Simulator - Simplified but accurate implementation based on equipment.txt

这个版本专注于核心的SDRAM控制逻辑，确保正确性和可读性
"""

class SDRAMSimulator:
    """SDRAM仿真器类"""
    
    def __init__(self):
        """初始化SDRAM仿真器"""
        # SDRAM输出引脚
        self.A = [0] * 13      # 地址线 A[0:12]  
        self.BA = [0, 0]       # Bank地址 BA[0:1]
        self.nRAS = 1          # 行地址选通 (低有效)
        self.nCAS = 1          # 列地址选通 (低有效)  
        self.nWE = 1           # 写使能 (低有效)
        self.CKE = 1           # 时钟使能
        
        # 内部状态寄存器
        self.sdram_refresh_mode = 0
        self.sdram_cmd_active = 0
        self.sdram_precharge_mode = 0  
        self.sdram_access_enable = 0
        self.refresh_counter = [0] * 9  # 9位计数器
        self.SDRAM_CTRL = [0, 0, 0, 0]  # CTRL[0:3]
        
        # GBA总线同步信号
        self.gba_bus_wr_sync = 1
        self.gba_bus_rd_sync = 1
        self.n_ddr_sel = 1
        
        # 配置寄存器
        self.config_sd_enable = 0
        self.config_map_reg = 0
        self.config_write_enable = 0
        
        # 输入信号
        self.CLK50Mhz = 0
        self.GP_AD = [0] * 24
        self.GP_NWR = 1
        self.GP_NRD = 1
        self.GP_nCS = 1
        self.internal_address = [0] * 16
        
        # 上一时钟状态
        self.prev_clk = 0
    
    def set_clock(self, clk):
        """设置时钟信号"""
        self.CLK50Mhz = int(clk)
        self.prev_clk = int(clk)
    
    def set_gba_signals(self, nwr=None, nrd=None, ncs=None):
        """设置GBA总线信号"""
        if nwr is not None: self.GP_NWR = int(nwr)
        if nrd is not None: self.GP_NRD = int(nrd)  
        if ncs is not None: self.GP_nCS = int(ncs)
    
    def set_address_data(self, ad_array):
        """设置GP.AD信号数组"""
        for i, val in enumerate(ad_array[:24]):
            self.GP_AD[i] = int(val)
    
    def set_internal_address(self, addr_array):
        """设置内部地址信号"""
        for i, val in enumerate(addr_array[:16]):
            self.internal_address[i] = int(val)
    
    def get_pins(self):
        """获取所有SDRAM引脚状态"""
        return {
            'A': self.A.copy(),
            'BA': self.BA.copy(), 
            'nRAS': self.nRAS,
            'nCAS': self.nCAS,
            'nWE': self.nWE,
            'CKE': self.CKE
        }
    
    def get_internal_state(self):
        """获取内部状态"""
        return {
            'refresh_mode': self.sdram_refresh_mode,
            'cmd_active': self.sdram_cmd_active,
            'precharge_mode': self.sdram_precharge_mode,
            'access_enable': self.sdram_access_enable,
            'refresh_counter': self.refresh_counter.copy(),
            'ctrl': self.SDRAM_CTRL.copy()
        }
    
    def _update_refresh_counter(self):
        """更新9位刷新计数器"""
        # 简单的二进制计数器
        carry = 1
        for i in range(9):
            sum_val = self.refresh_counter[i] + carry
            self.refresh_counter[i] = sum_val & 1
            carry = sum_val >> 1
            if carry == 0:
                break
        
        # 异步复位条件: CKE & nWE & !nRAS & !nCAS
        if self.CKE and self.nWE and not self.nRAS and not self.nCAS:
            self.refresh_counter[7] = 0
            self.refresh_counter[8] = 0
    
    def _update_gba_sync(self):
        """更新GBA总线同步信号 (在CLK50Mhz正沿)"""
        self.gba_bus_wr_sync = self.GP_NWR or not self.config_write_enable
        self.gba_bus_rd_sync = self.GP_NRD
        
        # n_ddr_sel逻辑 - 基于equipment.txt line 367
        # n_ddr_sel.D = (GP.nCS | config_sd_enable | !config_map_reg)
        self.n_ddr_sel = self.GP_nCS or self.config_sd_enable or not self.config_map_reg
    
    def _update_main_control_logic(self):
        """更新主要控制逻辑 (在!CLK50Mhz正沿，即CLK50Mhz负沿)"""
        # 当前状态
        ref_mode = self.sdram_refresh_mode
        cmd_active = self.sdram_cmd_active
        pre_mode = self.sdram_precharge_mode
        acc_enable = self.sdram_access_enable
        rc = self.refresh_counter
        ctrl = self.SDRAM_CTRL
        
        # 更新 sdram_refresh_mode
        new_ref_mode = (
            (cmd_active and not pre_mode and acc_enable and not rc[8]) or
            (cmd_active and not pre_mode and acc_enable and not rc[7]) or
            (not ctrl[1] and not ref_mode and not ctrl[0] and not ctrl[2] and not ctrl[3] and
             cmd_active and pre_mode and rc[8] and rc[7]) or
            (pre_mode and acc_enable and self.n_ddr_sel) or
            (not ref_mode and cmd_active and pre_mode and acc_enable) or
            (ref_mode and not pre_mode) or
            (ref_mode and not cmd_active) or
            (ref_mode and self.n_ddr_sel)
        )
        
        # 更新 sdram_cmd_active (带XOR)
        cmd_base = (
            (not ref_mode and not acc_enable and rc[8] and rc[7]) or
            (ref_mode and not cmd_active and not pre_mode and acc_enable and 
             self.gba_bus_wr_sync and self.gba_bus_rd_sync) or
            (not ref_mode and not cmd_active and pre_mode and acc_enable and 
             not self.n_ddr_sel and not self.gba_bus_rd_sync) or
            (not ref_mode and not cmd_active and pre_mode and acc_enable and
             not self.gba_bus_wr_sync and not self.n_ddr_sel) or
            (not ref_mode and cmd_active and not acc_enable) or
            (not ref_mode and cmd_active and not pre_mode and rc[8] and rc[7]) or
            (cmd_active and not pre_mode and not acc_enable) or
            (cmd_active and not acc_enable and not self.n_ddr_sel) or
            (cmd_active and not acc_enable and rc[8] and rc[7])
        )
        new_cmd_active = cmd_base ^ (ref_mode and pre_mode)
        
        # 更新 sdram_precharge_mode - 基于equipment.txt line 142-149
        # sdram_precharge_mode.D = !sdram_cmd_active & !sdram_precharge_mode & gba_bus_wr_sync & gba_bus_rd_sync
        #         | !sdram_refresh_mode & !sdram_precharge_mode & refresh_counter[8] & refresh_counter[7]
        #         | sdram_refresh_mode & sdram_precharge_mode & !sdram_access_enable & n_ddr_sel
        #         | !sdram_refresh_mode & !sdram_cmd_active & sdram_access_enable & gba_bus_wr_sync & !n_ddr_sel & gba_bus_rd_sync
        #         | sdram_refresh_mode & sdram_cmd_active & sdram_access_enable
        #         | !sdram_refresh_mode & !sdram_cmd_active & !sdram_precharge_mode
        #         | sdram_refresh_mode & !sdram_cmd_active & !sdram_access_enable
        #         | !sdram_refresh_mode & !sdram_access_enable & !refresh_counter[8]
        #         | !sdram_refresh_mode & !sdram_access_enable & !refresh_counter[7]
        
        new_pre_mode = (
            (not cmd_active and not pre_mode and self.gba_bus_wr_sync and self.gba_bus_rd_sync) or
            (not ref_mode and not pre_mode and rc[8] and rc[7]) or
            (ref_mode and pre_mode and not acc_enable and self.n_ddr_sel) or
            (not ref_mode and not cmd_active and acc_enable and self.gba_bus_wr_sync and not self.n_ddr_sel and self.gba_bus_rd_sync) or
            (ref_mode and cmd_active and acc_enable) or
            (not ref_mode and not cmd_active and not pre_mode) or
            (ref_mode and not cmd_active and not acc_enable) or
            (not ref_mode and not acc_enable and not rc[8]) or
            (not ref_mode and not acc_enable and not rc[7])
        )
        
        # 更新 sdram_access_enable - 基于equipment.txt line 155-161
        # 正确的AND逻辑实现
        # sdram_access_enable.D = (!sdram_refresh_mode | sdram_cmd_active | sdram_precharge_mode | !gba_bus_wr_sync | !gba_bus_rd_sync)
        #         & (!sdram_precharge_mode | sdram_access_enable | !n_ddr_sel | refresh_counter[8])
        #         & (!sdram_precharge_mode | sdram_access_enable | !n_ddr_sel | refresh_counter[7])
        #         & (sdram_refresh_mode | sdram_cmd_active | !sdram_precharge_mode | !n_ddr_sel)
        #         & (!sdram_refresh_mode | !sdram_cmd_active | !sdram_access_enable)
        #         & (sdram_refresh_mode | sdram_access_enable)
        #         & (sdram_cmd_active | sdram_access_enable)
        
        term1 = (not ref_mode or cmd_active or pre_mode or not self.gba_bus_wr_sync or not self.gba_bus_rd_sync)
        term2 = (not pre_mode or acc_enable or not self.n_ddr_sel or rc[8])
        term3 = (not pre_mode or acc_enable or not self.n_ddr_sel or rc[7])
        term4 = (ref_mode or cmd_active or not pre_mode or not self.n_ddr_sel)
        term5 = (not ref_mode or not cmd_active or not acc_enable)
        term6 = (ref_mode or acc_enable)
        term7 = (cmd_active or acc_enable)
        
        new_acc_enable = term1 and term2 and term3 and term4 and term5 and term6 and term7
        
        # 更新SDRAM_CTRL计数器
        # CTRL0: D触发器带XOR
        ctrl_condition = not ref_mode and cmd_active and not pre_mode and not acc_enable
        new_ctrl0 = ctrl_condition ^ ctrl[0]
        
        # CTRL1: T触发器
        new_ctrl1 = ctrl[1]
        if ctrl_condition and ctrl[0]:
            new_ctrl1 = 1 - ctrl[1]
        
        # CTRL2: T触发器
        new_ctrl2 = ctrl[2]
        if ctrl_condition and ctrl[1] and ctrl[0]:
            new_ctrl2 = 1 - ctrl[2]
        
        # CTRL3: T触发器  
        new_ctrl3 = ctrl[3]
        if ctrl_condition and ctrl[2] and ctrl[1] and ctrl[0]:
            new_ctrl3 = 1 - ctrl[3]
        
        # 应用更新
        self.sdram_refresh_mode = int(new_ref_mode)
        self.sdram_cmd_active = int(new_cmd_active)
        self.sdram_precharge_mode = int(new_pre_mode)
        self.sdram_access_enable = int(new_acc_enable)
        self.SDRAM_CTRL = [int(new_ctrl0), int(new_ctrl1), int(new_ctrl2), int(new_ctrl3)]
    
    def _update_address_pins(self):
        """更新地址引脚 (在!CLK50Mhz正沿)"""
        # 简化的地址映射逻辑
        ref_mode = self.sdram_refresh_mode
        cmd_active = self.sdram_cmd_active
        pre_mode = self.sdram_precharge_mode
        acc_enable = self.sdram_access_enable
        
        # 对于每个地址线，根据模式选择输出
        for i in range(13):
            if i == 10:
                # A[10]是特殊的触发器，单独处理
                self._update_a10_toggle()
            else:
                # 其他地址线的常规逻辑
                if ref_mode:
                    # 刷新模式下保持当前值或使用特定模式
                    if not pre_mode and not acc_enable:
                        # 保持当前值
                        pass
                    else:
                        # 根据刷新模式的具体逻辑
                        self.A[i] = 0
                elif not cmd_active and pre_mode and acc_enable:
                    # 预充电模式 - 使用列地址
                    if i < len(self.internal_address):
                        self.A[i] = self.internal_address[i]
                elif not cmd_active and not pre_mode and acc_enable:
                    # 正常访问模式 - 使用行地址
                    row_addr_map = [9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21]
                    if i < len(row_addr_map) and row_addr_map[i] < len(self.internal_address):
                        self.A[i] = self.internal_address[row_addr_map[i]]
        
        # Bank地址
        if not ref_mode and not cmd_active and acc_enable:
            self.BA[0] = self.GP_AD[22] if len(self.GP_AD) > 22 else 0
            self.BA[1] = self.GP_AD[23] if len(self.GP_AD) > 23 else 0
    
    def _update_a10_toggle(self):
        """更新A[10]触发器，基于equipment.txt的确切逻辑"""
        # 从equipment.txt获取的A[10]触发逻辑：
        # $SDRAM.A[10].T = (!GP.AD[19] & !sdram_refresh_mode & !sdram_cmd_active & !sdram_precharge_mode & sdram_access_enable
        #         | sdram_refresh_mode & !$SDRAM.A[10] & !sdram_cmd_active & !sdram_precharge_mode & !sdram_access_enable
        #         | sdram_refresh_mode & $SDRAM.A[10] & sdram_cmd_active & !sdram_precharge_mode & !sdram_access_enable
        #     ) ^ (!sdram_refresh_mode & !$SDRAM.A[10] & !sdram_cmd_active & sdram_access_enable)
        
        gp_ad19 = self.GP_AD[19] if len(self.GP_AD) > 19 else 0
        ref_mode = self.sdram_refresh_mode
        cmd_active = self.sdram_cmd_active  
        pre_mode = self.sdram_precharge_mode
        acc_enable = self.sdram_access_enable
        current_a10 = self.A[10]
        
        # 计算主表达式的三个条件
        cond1 = (not gp_ad19 and not ref_mode and not cmd_active and not pre_mode and acc_enable)
        cond2 = (ref_mode and not current_a10 and not cmd_active and not pre_mode and not acc_enable)
        cond3 = (ref_mode and current_a10 and cmd_active and not pre_mode and not acc_enable)
        
        # 计算XOR项
        xor_term = (not ref_mode and not current_a10 and not cmd_active and acc_enable)
        
        # 最终切换信号 = (cond1 | cond2 | cond3) XOR xor_term
        toggle = (cond1 or cond2 or cond3) != xor_term
        
        # 如果需要切换，则翻转A[10]
        if toggle:
            self.A[10] = 1 - self.A[10]
    
    def _update_control_pins(self):
        """更新控制引脚 (在!CLK50Mhz正沿)"""
        ref_mode = self.sdram_refresh_mode
        cmd_active = self.sdram_cmd_active
        pre_mode = self.sdram_precharge_mode
        acc_enable = self.sdram_access_enable
        rc = self.refresh_counter
        
        # nRAS信号
        self.nRAS = int(
            (cmd_active and not pre_mode and acc_enable) or
            (ref_mode and not pre_mode and acc_enable) or
            (not ref_mode and not cmd_active and pre_mode) or
            (pre_mode and not acc_enable)
        )
        
        # nCAS信号
        self.nCAS = int(
            (ref_mode and cmd_active and acc_enable and self.n_ddr_sel and not rc[8]) or
            (ref_mode and cmd_active and acc_enable and self.n_ddr_sel and not rc[7]) or
            (not cmd_active and not acc_enable) or
            (not ref_mode and not cmd_active and self.gba_bus_wr_sync and self.gba_bus_rd_sync) or
            (pre_mode and not acc_enable) or
            (not pre_mode and acc_enable)
        )
        
        # nWE信号
        cond1 = ref_mode or cmd_active or not pre_mode or not acc_enable or self.gba_bus_wr_sync
        cond2 = not ref_mode or pre_mode or acc_enable
        self.nWE = int(cond1 and cond2)
        
        # CKE信号
        cond1 = not ref_mode or not cmd_active or not pre_mode or not self.n_ddr_sel or rc[8]
        cond2 = not ref_mode or not cmd_active or not pre_mode or not self.n_ddr_sel or rc[7]
        self.CKE = int(cond1 and cond2)
    
    def clock_edge(self):
        self.CLK50Mhz = 1 - self.CLK50Mhz
        self._clock_edge()
    
    def clock_rising_edge(self):
        self._update_gba_sync()
    
    def clock_falling_edge(self):
        self._update_refresh_counter()
        self._update_main_control_logic()
        self._update_address_pins()
        self._update_control_pins()

    def _clock_edge(self):
        """处理时钟边沿"""
        # CLK50Mhz正沿 (上升沿)
        if self.CLK50Mhz and not self.prev_clk:
            self._update_gba_sync()
        
        # !CLK50Mhz正沿 (CLK50Mhz下降沿)  
        elif not self.CLK50Mhz and self.prev_clk:
            self._update_refresh_counter()
            self._update_main_control_logic()
            self._update_address_pins()
            self._update_control_pins()
        
        self.prev_clk = self.CLK50Mhz
    
    def reset(self):
        """复位仿真器"""
        self.A = [0] * 13
        self.BA = [0, 0]
        self.nRAS = 1
        self.nCAS = 1  
        self.nWE = 1
        self.CKE = 1
        
        self.sdram_refresh_mode = 0
        self.sdram_cmd_active = 0
        self.sdram_precharge_mode = 0
        self.sdram_access_enable = 0
        self.refresh_counter = [0] * 9
        self.SDRAM_CTRL = [0, 0, 0, 0]
        
        self.gba_bus_wr_sync = 1
        self.gba_bus_rd_sync = 1
        self.n_ddr_sel = 1
        
        self.prev_clk = 0
    
    def print_status(self):
        """打印当前状态"""
        print("=== SDRAM Simulator Status ===")
        print(f"Address: {self.A}")
        print(f"Bank: {self.BA}")  
        print(f"Control: nRAS={self.nRAS}, nCAS={self.nCAS}, nWE={self.nWE}, CKE={self.CKE}")
        print(f"State: REF={self.sdram_refresh_mode}, CMD={self.sdram_cmd_active}, PRE={self.sdram_precharge_mode}, ACC={self.sdram_access_enable}")
        print(f"Counter: {self.refresh_counter}")
        print(f"CTRL: {self.SDRAM_CTRL}")


# 测试和演示
def test_basic_operation():
    """测试基本操作"""
    print("=== 基本操作测试 ===")
    
    sdram = SDRAMSimulator()
    print("初始状态:")
    sdram.print_status()
    
    # 运行几个时钟周期
    print(f"\n运行10个时钟周期...")
    for i in range(10):
        sdram.set_clock(1)
        sdram.clock_edge()
        sdram.set_clock(0)
        sdram.clock_edge()
    
    print("10个周期后:")
    sdram.print_status()

def test_gba_read():
    """测试GBA读操作"""
    print("\n=== GBA读操作测试 ===")
    
    sdram = SDRAMSimulator()
    
    # 首先需要初始化配置寄存器来启用SDRAM
    print("步骤1: 初始化配置寄存器")
    
    # 设置配置：config_map_reg=1 来启用SDRAM
    sdram.config_map_reg = 1  # 手动设置，或者通过正确的配置序列
    sdram.config_write_enable = 1
    
    print(f"配置寄存器: map_reg={sdram.config_map_reg}, write_enable={sdram.config_write_enable}")
    
    # 重新计算n_ddr_sel
    sdram.set_gba_signals(nwr=1, nrd=1, ncs=0)
    sdram.set_clock(1)
    sdram.clock_edge()  # 这会更新n_ddr_sel
    
    print(f"n_ddr_sel = {sdram.n_ddr_sel}")
    
    print("\n步骤2: 设置读操作")
    # 设置读操作
    sdram.set_gba_signals(nwr=1, nrd=0, ncs=0)  # 读使能
    sdram.set_address_data([1, 0, 1, 0] + [0]*20)  # 设置地址
    sdram.set_internal_address([1]*16)  # 设置内部地址
    
    print("设置读操作后:")
    for i in range(10):  # 运行更多周期
        sdram.set_clock(1)
        sdram.clock_edge()
        sdram.set_clock(0)
        sdram.clock_edge()
        print(f"周期 {i+1}: nRAS={sdram.nRAS}, nCAS={sdram.nCAS}, nWE={sdram.nWE}, ACC={sdram.sdram_access_enable}")
        
        # 如果状态开始变化，显示更多信息
        if sdram.sdram_access_enable or sdram.sdram_cmd_active:
            print(f"        状态: REF={sdram.sdram_refresh_mode}, CMD={sdram.sdram_cmd_active}, PRE={sdram.sdram_precharge_mode}, ACC={sdram.sdram_access_enable}")
            break

def test_refresh_operation():
    """测试刷新操作"""
    print("\n=== 刷新操作测试 ===")
    
    sdram = SDRAMSimulator()
    
    # 空闲状态
    sdram.set_gba_signals(nwr=1, nrd=1, ncs=1)
    
    print("初始刷新计数器:", sdram.refresh_counter)
    
    # 运行足够的周期观察刷新计数器
    for i in range(50):
        sdram.set_clock(1)
        sdram.clock_edge()
        sdram.set_clock(0)
        sdram.clock_edge()
        
        if i % 10 == 9:
            print(f"周期 {i+1}: 刷新计数器 = {sdram.refresh_counter}")

if __name__ == "__main__":
    test_basic_operation()
    test_gba_read()
    test_refresh_operation()
