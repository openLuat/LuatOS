# 可行性评估：PC 模拟器编译为 Emscripten (WebAssembly)

## 目标

评估将 `bsp/pc` PC 模拟器编译为 Emscripten/WASM 目标的可行性、主要障碍、推荐路径及工作量估算。

---

## 现有架构摘要

PC 模拟器的核心依赖：

| 层级 | 实现 | 文件 |
|------|------|------|
| 事件循环 | `uv_loop_t` + `uv_run()` spin-loop | `port/rtos/luat_msgbus_pc.c` |
| RTOS 任务 | `uv_thread_create`（→ pthreads） | `port/rtos/luat_rtos_task_pc.c` |
| 同步原语 | `uv_mutex_t`, `uv_cond_t`, `uv_sleep()` | 多处 |
| 定时器 | `uv_timer_t` | `port/rtos/luat_rtos_timer_pc.c` |
| 网络 I/O | `uv_tcp_t`, `uv_udp_t`, `uv_getaddrinfo_t` | `port/network/luat_network_adapter_libuv.c` |
| lwIP 线程 | `uv_thread_create` via `sys_thread_new` | `port/network/sys_arch_uv.c` |
| GUI | SDL2 + LVGL 9 (via libuv timer) | `xmake.lua`, `ui/` |
| 加密 | mbedtls3, gmssl (xmake 包) | |
| 文件系统 | Host 文件系统直接访问 | `port/luat_fs_mini.c` |

---

## 兼容性分析

### 🟢 基本兼容（改动极少）

- **Lua 5.3 VM** (`lua/`)：纯 C，无系统调用依赖，Emscripten 完全支持。
- **纯 C 第三方库**：mbedtls3、lfs、fatfs、cjson、miniz、libwebp、fastlz、OPUS、coremark 等，均为纯 C，可直接编译。
- **大多数 LuatOS 模块** (`luat/modules/`)：纯逻辑层，不依赖原生 I/O。
- **xmake 构建系统**：支持 Emscripten 平台（`xmake f -p wasm`）。
- **SDL2 (GUI 部分)**：Emscripten 内置 SDL2 支持（`-s USE_SDL=2`），LVGL 渲染可适配。

### 🟡 需要适配（中等工作量）

- **SDL2 主循环**：必须用 `emscripten_set_main_loop()` 替换当前的 `uv_run()` spin-loop。
- **文件系统**：替换 Host FS 为 Emscripten 的 MEMFS（内存）或 IDBFS（IndexedDB 持久化）。
- **gmssl 包**：xmake 的 `add_requires("gmssl")` 需要 WASM 版本构建或从源码编译。
- **win32 特定代码** (`win32/`)：通过宏 `LUAT_USE_WINDOWS` 条件编译排除，无需移植。

### 🔴 阻塞性障碍（根本性问题）

#### 1. libuv 多线程模型（最关键障碍）

**问题**：PC 模拟器将每个 RTOS 任务映射为 `uv_thread_create`（→ `pthread_create`）原生线程。`luat_rtos_task_sleep` 调用 `uv_sleep(ms)`，事件等待也使用阻塞式 spin-loop + `uv_sleep(1)`。

**Emscripten 限制**：
- 默认不支持 pthreads，浏览器 JS 是单线程模型。
- 启用 `-pthread` 需要 SharedArrayBuffer（需浏览器设置 COOP/COEP 安全头）和 `Atomics.wait`。
- `uv_sleep()` 的阻塞语义与浏览器事件循环根本冲突。

#### 2. libuv 网络层（次关键障碍）

**问题**：`uv_tcp_t`、`uv_udp_t`、`uv_getaddrinfo_t` 直接使用 POSIX 原始套接字（TCP/UDP）。

**Emscripten 限制**：
- 浏览器沙箱完全禁止原始 TCP/UDP 套接字访问。
- 只能通过 WebSocket 或 Fetch API 访问网络。

#### 3. lwIP 线程（关联障碍）

**问题**：lwIP 在 `sys_thread_new()` 中调用 `uv_thread_create` 创建 tcpip 线程，并在 `sys_arch_mbox_fetch` 等处使用 `uv_cond_wait` 阻塞等待。

---

## 推荐方案：WebSocket 代理 + Asyncify

### 方案概述

**新建服务端代理程序，通过 WebSocket 与 WASM 侧交互，替代 libuv 网络实现**。

结合 Emscripten 的 **Asyncify** 机制解决多线程阻塞问题，可以在**不引入 pthreads / SharedArrayBuffer** 的前提下让整个系统运行。

---

### 核心技术组合

#### 1. Asyncify（解决多线程阻塞问题）

Emscripten 的 `-s ASYNCIFY` 选项对 WASM 字节码进行插桩，允许 C 函数调用 `emscripten_sleep()` 来"暂停"执行，将控制权交还 JS 事件循环，之后恢复执行。

替换策略：
- `uv_sleep(ms)` → `emscripten_sleep(ms)`
- `luat_msgbus_get` 的 spin-loop 中加入 `emscripten_sleep(1)` 让出控制权
- 整体 RTOS 多任务架构**无需重写**（仍可模拟任务/事件队列）

优缺点：
- ✅ 不需要 pthreads / SharedArrayBuffer / COOP+COEP 限制
- ✅ 现有任务/定时器/事件逻辑几乎不变
- ⚠️ WASM 体积增加约 30~50%（插桩开销，模拟器场景可接受）

#### 2. WebSocket 网络代理（解决网络问题）

**网络适配层已高度抽象**（`network_adapter_info` 函数指针表，约 20 个接口）：

```c
// luat_network_adapter_libuv.c 中注册
static const network_adapter_info prv_libuv_adapter = {
    .create_soceket  = libuv_create_socket,
    .socket_connect  = libuv_socket_connect,
    .socket_send     = libuv_socket_send,
    .socket_receive  = libuv_socket_receive,
    .socket_close    = libuv_socket_close,
    .dns             = libuv_dns,
    // ... 共 ~20 个函数指针
};
network_register_adapter(NW_ADAPTER_INDEX_ETH0, &prv_libuv_adapter, NULL);
```

新建 `port/network/luat_network_adapter_ws.c`，实现同一套函数指针接口，通过 Emscripten WebSocket API 与代理服务器通信：

```
┌─────────────────────────────────┐     WebSocket      ┌──────────────────────┐
│  WASM (浏览器)                   │ ←─────────────────→ │  代理服务器           │
│                                 │                     │                      │
│  luat_network_adapter_ws.c      │   { op: "connect"   │  ws_proxy_server     │
│  ↓                              │     socket_id: 1    │  ↓                   │
│  emscripten WebSocket API       │     host: "...",    │  真实 TCP/UDP 套接字  │
│  (单连接，多路复用虚拟 socket)    │     port: 443 }     │  (OS 原生)           │
└─────────────────────────────────┘                     └──────────────────────┘
```

代理协议（轻量 JSON 或二进制帧）：

| 操作 | 方向 | 描述 |
|------|------|------|
| `connect` | WASM → 代理 | 建立 TCP 连接 |
| `connect_ok` / `connect_fail` | 代理 → WASM | 连接结果 |
| `send` | WASM → 代理 | 发送数据 |
| `data` | 代理 → WASM | 接收数据 |
| `close` | 双向 | 关闭连接 |
| `dns` | WASM → 代理 | DNS 解析请求 |
| `dns_result` | 代理 → WASM | DNS 解析结果 |
| `listen` / `accept` | WASM → 代理 | TCP Server 支持 |

---

### 整体架构图

```
浏览器
┌────────────────────────────────────────┐
│  WASM (emcc 编译)                       │
│  ┌────────────────────────────────┐    │
│  │ Lua VM + LuatOS Core + 业务脚本 │    │
│  └────────────────────────────────┘    │
│  ┌───────────────┐  ┌──────────────┐  │
│  │ RTOS 任务系统  │  │ SDL2 + LVGL  │  │
│  │ (Asyncify 驱动)│  │ (emsc SDL2)  │  │
│  └───────────────┘  └──────────────┘  │
│  ┌─────────────────────────────────┐  │
│  │ luat_network_adapter_ws.c       │  │
│  │ (Emscripten WebSocket API)      │  │
│  └──────────────┬──────────────────┘  │
└─────────────────┼──────────────────────┘
                  │ WebSocket (localhost:9000)
┌─────────────────┼──────────────────────┐
│  代理服务器 (本地进程)                   │
│  tools/ws_proxy/ (Go 单二进制)          │
│  ┌─────────────────────────────────┐  │
│  │ 虚拟 socket 映射表              │  │
│  │ socket_id → 真实 TCP/UDP fd     │  │
│  └─────────────────────────────────┘  │
│            ↓ 真实网络 I/O              │
│  互联网 / 内网服务                      │
└────────────────────────────────────────┘
```

---

## 实施计划（分阶段）

### 阶段 1：基础编译通过（约 2~3 周）

**目标**：纯 C 组件在 `emcc` 下编译无报错，Asyncify 接入。

新增文件：
- `bsp/wasm/xmake.lua` — Emscripten 平台构建配置
- `bsp/wasm/port/` — WASM 平台 port 层（libuv stub 等）

工作内容：
1. 新建 `bsp/wasm/` 目录，编写 `xmake f -p wasm` 构建脚本（参考 `bsp/pc/xmake.lua`）
2. 剔除不兼容代码：
   - `win32/` 目录完全排除（`LUAT_USE_WINDOWS` 宏已有条件编译保护）
   - 所有 `#include "uv.h"` 用 `#ifdef LUAT_USE_EMSCRIPTEN` 宏条件隔离
   - `luat_network_adapter_libuv.c` 在 WASM 构建中排除，以空 stub 替代
3. 验证纯 C 组件（Lua VM、mbedtls3、lfs、cjson 等）在 `emcc` 下编译无报错
4. 加入 Asyncify：在 `xmake.lua` 中添加 `-s ASYNCIFY=1`

---

### 阶段 2：事件循环适配（约 1~2 周）

**目标**：能跑通不需网络的基础 Lua 脚本（coremark、crypto 测试）。

新增文件：
- `bsp/wasm/port/rtos/luat_msgbus_wasm.c` — 替换 `luat_msgbus_pc.c`
- `bsp/wasm/port/rtos/luat_rtos_timer_wasm.c` — 替换 `luat_rtos_timer_pc.c`
- `bsp/wasm/src/main_wasm.c` — WASM 入口（替换 `main_mini.c`）

工作内容：
5. 重写 `luat_msgbus_wasm.c`：
   - 去掉 `uv_run()` 调用（libuv 主循环无法在 WASM 下运行）
   - spin-loop 中改为 `emscripten_sleep(1)` 让出控制权
6. 重写定时器驱动：用 `emscripten_set_main_loop` 回调定期 tick
7. 验证：coremark、crypto、fskv 等无网络测试脚本能正常运行

---

### 阶段 3：WebSocket 网络适配器（约 3~4 周）

**目标**：TCP/HTTP/MQTT 等上层协议通过 WebSocket 代理正常工作。

新增文件：
- `bsp/wasm/port/network/luat_network_adapter_ws.c` — WASM 网络适配器
- `tools/ws_proxy/main.go` — 代理服务器（Go 实现，单二进制，跨平台）

工作内容：
8. 新建代理服务器 `tools/ws_proxy/`（Go 实现）：
   - WebSocket 服务端（默认监听 `localhost:9000`）
   - 协议处理：connect / send / recv / close / dns
   - 维护虚拟 socket ID → 真实 OS fd 映射表
9. 新建 `luat_network_adapter_ws.c`：
   - 使用 `emscripten/websocket.h` API 建立到代理的单路 WebSocket
   - 实现 `network_adapter_info` 全部函数指针（对应 libuv 适配器的 ~20 个接口）
   - 收到代理数据后通过 `luat_msgbus_put` 将事件注入 Lua VM

---

### 阶段 4：GUI 适配（可选，约 1~2 周）

**目标**：SDL2 + LVGL 在浏览器中正常渲染。

修改文件：
- `bsp/wasm/xmake.lua` — 增加 `-s USE_SDL=2` 替换 `libsdl2` 包依赖

工作内容：
10. SDL2：Emscripten 内置 SDL2，`-s USE_SDL=2` 替换 xmake 的 `add_requires("libsdl2")`
11. LVGL 事件循环：将原 `lvgl_timer_cb`（libuv 定时）改为 `emscripten_set_main_loop` 驱动

---

## 技术风险

| 风险项 | 严重性 | 缓解措施 |
|--------|--------|----------|
| Asyncify 代码体积膨胀 | 低 | 对模拟器场景可接受；生产环境可改用 pthreads 方案 |
| Asyncify 与 Lua 协程的交互 | 中 | Lua 协程不跨 C 堆栈，Asyncify 影响有限；需专项测试 |
| 代理服务器安全性 | 低-中 | 本地运行（localhost），不暴露公网；有需求可加 token 认证 |
| libuv 完全去除的工作量 | 中 | 仅在 WASM 平台分支替换，PC 原有代码路径不受影响 |
| UDP 代理协议复杂度 | 中 | WebSocket 是 TCP 流，UDP 需帧化处理；可延后支持 |
| gmssl xmake 包 WASM 构建 | 低 | 可临时 stub 或从源码单独编译为 WASM，非核心阻塞项 |

---

## 可行性结论

**方案可行性：高。**

| 目标 | 可行性 |
|------|--------|
| Lua 脚本运行（本地计算） | ✅ 高，阶段 1~2 即可验证 |
| RTOS 多任务模拟 | ✅ 可行（Asyncify，无需 SharedArrayBuffer）|
| 网络功能（TCP/HTTP/MQTT）| ✅ 可行（WebSocket 代理，阶段 3）|
| GUI（SDL2 + LVGL）| ✅ 可行（Emscripten 内置 SDL2，阶段 4）|
| UDP 通信 | 🟡 可行但需额外协议设计 |
| 无外部依赖独立运行 | 🟡 需本地代理服务器（可打包为一键启动）|

**总工作量估算**：约 **8~12 周**（阶段 1~3 必要，阶段 4 可选）

---

## 待决策事项

1. **代理服务器部署形式**：纯本地工具（随模拟器启动）vs 云端公共代理？
2. **目标平台**：纯浏览器演示 vs Electron 打包（Electron 可去除 WebSocket 代理，直接用 Node.js 原生 socket）？
3. **是否需要 UDP 支持**？（影响代理协议复杂度）
4. **lwIP 处理**：在 WASM 版本中完全去除（用 WebSocket 代理替代所有网络），还是保留（增加复杂度）？
