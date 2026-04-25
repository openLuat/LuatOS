# AGENTS.md — components/airlink

AirLink 是 Air8000/Air8101+Air780E 双芯片场景下的跨设备通信框架，通过 SPI/UART 传输结构化命令。

---

## 目录结构

```
components/airlink/
├── include/                       # 公共头文件
│   ├── luat_airlink.h             # 主头文件（包含所有子头文件）
│   ├── luat_airlink_rpc.h         # nanopb typed RPC API
│   ├── luat_airlink_transport.h   # transport/slot 注册 API
│   └── ...
├── src/
│   ├── luat_airlink.c             # 核心初始化、命令调度
│   ├── luat_airlink_rpc.c         # nanopb RPC 框架（call/notify/dispatch）
│   ├── luat_airlink_cmds.c        # 命令表注册
│   ├── driver/                    # 客户端驱动（GPIO/UART/WLAN/PM）
│   │   ├── luat_airlink_drv_gpio.c
│   │   ├── luat_airlink_drv_uart.c
│   │   ├── luat_airlink_drv_wlan.c
│   │   └── luat_airlink_drv_pm.c
│   ├── exec/                      # 服务端 RPC handler（在目标设备上运行）
│   │   ├── luat_airlink_cmd_exec_basic.c     # 基础命令（sdata、log 等）
│   │   ├── luat_airlink_cmd_exec_rpc.c       # RPC 命令分发入口
│   │   ├── luat_airlink_cmd_exec_rpc_gpio.c  # GPIO typed handler
│   │   ├── luat_airlink_cmd_exec_rpc_uart.c  # UART typed handler
│   │   ├── luat_airlink_cmd_exec_rpc_wlan.c  # WLAN typed handler
│   │   ├── luat_airlink_cmd_exec_rpc_pm.c    # PM typed handler
│   │   ├── luat_airlink_cmd_exec_rpc_sdata.c # SDATA notify handler
│   │   └── luat_airlink_rpc_nb_table.c       # 静态 handler 指针表
│   └── task/
│       ├── luat_airlink_loopback_task.c      # PC 模拟器 loopback 任务
│       └── luat_airlink_spi_slave_task.c     # SPI 从机任务（硬件专用）
└── binding/
    └── luat_lib_airlink.c         # Lua 绑定
```

---

## 构建说明

### 在 PC 模拟器上构建（Windows）

**务必使用 bat 脚本，不要直接运行 `xmake -y`**（全量编译耗时 10+ 分钟，输出被截断导致无法看到错误）：

```powershell
# 增量编译（推荐，约 10-30 秒）
cd bsp\pc
cmd /c build_windows_32bit_msvc.bat

# 强制全量重编
cmd /c build_windows_32bit_msvc.bat full
```

成功输出末行：`[pc-build] Build completed successfully`  
失败时只显示错误行，完整日志在 `bsp/pc/build/logs/` 下。

### 哪些文件在 PC 上编译

在 `bsp/pc/xmake.lua` 中，以下文件被 `remove_files` 排除（硬件专用）：
- `src/driver/*.c` — 硬件驱动
- `src/exec/luat_airlink_cmd_exec_gpio/uart/wlan/bluetooth.c` — 非 RPC 版 exec handler
- `src/task/luat_airlink_spi_slave_task.c`

以下文件**正常参与 PC 编译**：
- `src/exec/luat_airlink_cmd_exec_rpc_*.c` — nanopb typed RPC handlers
- `src/exec/luat_airlink_rpc_nb_table.c` — 静态 handler 表
- `src/luat_airlink_rpc.c` — RPC 框架

### 运行测试

```powershell
cd bsp\pc
build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\airlink\airlink_nanopb_basic\scripts\
```

---

## nanopb RPC 架构

### 线格式（cmd 0x30）

```
[pkgid   : 8 bytes]  -- 0 = NOTIFY（无需响应）
[rpc_id  : 2 bytes]  -- 功能号，按模块分段
[msg_type: 1 byte ]  -- 0=REQUEST, 1=NOTIFY
[payload : N bytes]  -- nanopb 编码
```

### RPC ID 分配

| 范围 | 模块 | 宏 |
|------|------|----|
| `0x0100` | GPIO | `LUAT_USE_AIRLINK_RPC_GPIO` |
| `0x0200` | UART | `LUAT_USE_AIRLINK_RPC_UART` |
| `0x0300` | WLAN | `LUAT_USE_AIRLINK_RPC_WLAN` |
| `0x0400` | PM   | `LUAT_USE_AIRLINK_RPC_PM`   |
| `0x0500` | SDATA notify | `LUAT_USE_AIRLINK_RPC_SDATA` |

### 静态 handler 表（`luat_airlink_rpc_nb_table.c`）

核心机制：每个 exec handler 文件导出一个 `const luat_airlink_rpc_nb_reg_t luat_airlink_rpc_XXX_reg` 全局量，`luat_airlink_rpc_nb_table.c` 按宏汇编成指针数组。`nb_dispatch` 优先无锁搜索静态表，再加锁搜索动态表（Lua 侧注册，最多 8 槽）。

**添加新 RPC 模块的步骤：**

1. 在 `components/nanopb/proto/` 创建 `.proto` 文件
2. 运行 nanopb 生成器，将 `.pb.h` 放 `include/`，`.pb.c` 放 `src/`
3. 创建 `src/exec/luat_airlink_cmd_exec_rpc_XXX.c`：
   - 第一行 `#include "luat_base.h"`（**必须在 `#ifdef` 之前**）
   - 外层 `#ifdef LUAT_USE_AIRLINK_RPC`，内层 `#ifdef LUAT_USE_AIRLINK_RPC_XXX`
   - 导出 `const luat_airlink_rpc_nb_reg_t luat_airlink_rpc_XXX_reg`
4. 在 `luat_airlink_rpc_nb_table.c` 增加 `extern` 声明和指针数组条目
5. 在 `bsp/pc/include/luat_conf_bsp.h` 增加 `#define LUAT_USE_AIRLINK_RPC_XXX 1`
6. 分配 RPC ID（在 proto 文件注释中记录）

---

## 常见陷阱

### `#include "luat_base.h"` 必须在 `#ifdef LUAT_USE_AIRLINK_RPC` 之前

`luat_conf_bsp.h`（定义所有 `LUAT_USE_*` 宏）通过 `luat_base.h` 引入。如果把 `#include "luat_base.h"` 放在 `#ifdef LUAT_USE_AIRLINK_RPC` 内部，预处理器还未看到宏定义就求值条件，导致整个文件被跳过，产生 `LNK2001` 无法解析的外部符号错误（极难排查，因为编译阶段无任何提示）。

**正确模式：**
```c
#include "luat_base.h"  // ← 必须在 #ifdef 外面

#ifdef LUAT_USE_AIRLINK_RPC
#include "luat_airlink_rpc.h"
// ... 其余代码
#endif
```

### nanopb 类型名前缀取决于 `.proto` 的 `package` 指令

- 无 `package`：`SdataNotify`（裸名）
- `package drv_sdata;`：`drv_sdata_SdataNotify`
- 生成后务必看 `.pb.h` 确认实际类型名，不要凭推测写代码

### nanopb 生成器把 `.pb.c` 输出到 `--output-dir` 指定目录

如果 `--output-dir` 设为 `include/`，则 `.pb.c` 也会生成在 `include/` 里。需要手动将 `.pb.c` 移到 `src/`，否则 xmake 不会编译它。

### UART write 必须循环分块

`luat_airlink_drv_uart_write()` 在 RPC 模式下必须循环调用 `nb_call` 直到所有数据发送完毕（每次最多 `UART_WRITE_RPC_MAX = 500` 字节），而不能依赖单次调用。否则大于 500 字节的数据会被截断。

### sdata 数据路径

- **客户端**：`luat_airlink_sdata_send()` → RPC 时走 `nb_notify`（按 1400B 分块），无 RPC 时走 raw cmd 0x20
- **服务端**：`luat_airlink_cmd_exec_rpc_sdata.c` 收到 notify → 解码 `SdataNotify` → 调用 `luat_airlink_cmd_exec_sdata_data()` → 发布 `AIRLINK_SDATA` 事件

---

## 关键文件速查

| 文件 | 作用 |
|------|------|
| `src/luat_airlink_rpc.c` | `nb_call` / `nb_notify` / `nb_dispatch` 核心实现 |
| `src/exec/luat_airlink_rpc_nb_table.c` | 静态 handler 指针表（按宏条件汇编） |
| `src/exec/luat_airlink_cmd_exec_basic.c` | `sdata_data`、`notify_log` 等基础 exec |
| `include/luat_airlink_rpc.h` | `luat_airlink_rpc_nb_reg_t` 结构定义 + API 声明 |
| `binding/luat_lib_airlink.c` | Lua API 绑定，含 `luat_airlink_sdata_send()` |
| `bsp/pc/include/luat_conf_bsp.h` | PC 功能宏开关（`LUAT_USE_AIRLINK_RPC_*`） |
| `testcase/airlink/airlink_nanopb_basic/` | nanopb RPC 端到端测试（5 个 loopback 用例） |
