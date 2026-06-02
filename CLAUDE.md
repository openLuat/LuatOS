# NDK 组件开发指南

## 概述

NDK (Native Development Kit) 是 LuatOS 中的 **RISC-V RV32IMA 模拟器组件**，允许在沙盒化的 RV32 环境中运行 MiniRV32IMA 二进制镜像，提供 GPIO、UART、CRYPTO 等主机侧外设的访问能力。

## 目录结构

```
components/ndk/
├── include/
│   ├── luat_ndk.h          # 核心数据结构与API声明
│   ├── luat_ndk_abi.h      # Host/Guest ABI定义（CSR寄存器、命令码、宏）
│   ├── luat_ndk_host.h     # Host侧外设操作接口
│   ├── luat_ndk_builtin.h  # Guest侧内联函数（供RISC-V客户端代码使用）
│   └── mini-rv32ima.h      # MiniRV32IMA CPU核心实现
├── src/
│   ├── luat_ndk.c           # 核心模拟器（生命周期、浮点运算、线程管理）
│   ├── luat_ndk_host.c      # CSR读写处理、日志输出
│   ├── luat_ndk_host_gpio.c # GPIO外设CSR处理
│   ├── luat_ndk_host_uart.c # UART外设CSR处理
│   ├── luat_ndk_host_crypto.c # CRYPTO外设CSR处理（MD5/CRC32）
│   └── luat_ndk_host_event.c  # Event ring buffer管理
├── binding/
│   └── luat_lib_ndk.c      # Lua绑定（ndk.rv32i/exec/info等）
└── guest/                   # RISC-V客户端示例代码和固件
```

## 架构设计

### ABI 通信机制

Guest 通过 RISC-V `csrrw` 指令与 Host 交互，CSR 地址定义在 `luat_ndk_abi.h`：

- **元数据类**: `0x13C-0x13F` (magic/version/features/lasterror)
- **时间类**: `0x141-0x143` (time_lo/time_hi/delay_us)
- **事件类**: `0x144-0x145` (event_enable/event_pending)
- **GPIO v2**: `0x210-0x214` (config/write_v2/read_v2/irq_state/irq_clear)
- **UART v1**: `0x220-0x224` (config/tx/rx_state/rx_read/rx_clear)
- **CRYPTO v1**: `0x230-0x231` (md5/crc32)

### 浮点运算处理

`luat_ndk.c` 实现了完整的 RV32IMF 浮点支持，特点：

- 使用 `fenv_t` 管理主机浮点环境，跨平台支持 GCC/MSVC
- 所有浮点计算使用 `volatile` 中间变量防止编译器优化干扰
- NaN/Inf/sNaN 正确规范化
- RISC-V RM (rounding mode) 到主机 FE_* 的映射

### 线程模型

- **同步模式**: `ndk.exec()` 在调用线程执行
- **异步模式**: `ndk.thread()` 创建 RTOS 任务执行
- 线程安全通过 `ndk_lock/ndk_unlock` + critical section 实现

## 开发要点

### 代码质量规范

1. **地址计算**: 使用 `uint64_t` 中转避免 `uint32_t` 减法溢出
2. **线程计数器**: 必须使用原子操作（`InterlockedIncrement` for MSVC，`__sync_add_and_fetch` for GCC）
3. **宏定义**: `&`/`|` 混用时必须加完整括号
4. **资源清理**: 抽取 `ndk_free_fields()` 辅助函数避免重复

### 测试方法

```powershell
# 编译32位版本（UTEST模式）
cd bsp/pc
$env:LUAT_USE_UTEST = "y"
powershell -File build_with_summary.ps1 -Arch x86 -Vm64 0 -Mode summary

# 运行utest
powershell -File pc_utest_coverage.ps1 -Suite ndk_basic -SkipBuild

# 运行特定测试套件
powershell -File pc_utest_coverage.ps1 -Suite "ndk_hostabi_basic" -SkipBuild
```

### 常见问题

**Q: 如何添加新的外设CSR?**
1. 在 `luat_ndk_abi.h` 定义 CSR 地址和命令码
2. 在 `luat_ndk_host.c` 的 `luat_ndk_host_othercsr_write/read` 中添加处理分支
3. 在 Guest 侧使用 `luat_ndk_builtin.h` 中的内联函数访问

**Q: 如何调试 Guest 程序?**
1. Guest 通过 `NDK_CSR_PRINT_STR/NUM/PTR` 输出日志
2. Host 侧 `luat_ndk_host_othercsr_write` 捕获并打印

**Q: 如何验证ABI兼容性?**
- 运行 `ndk_hostabi_basic` 测试套件
- 检查 `testcase/unit_testcase_tools/ndk_hostabi_basic/scripts/` 中的测试用例

## 相关文档

- [GPIO v2 设计文档](../docs/superpowers/specs/2026-05-20-gpio-v2-design.md)
- [UART v1 设计文档](../docs/superpowers/specs/2026-05-20-uart-v1-design.md)