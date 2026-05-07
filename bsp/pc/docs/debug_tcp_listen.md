# TCP Listen/Accept 功能调试记录

**日期**: 2025-07  
**范围**: PC模拟器 libuv 网络适配器  
**文件**: `bsp/pc/port/network/luat_network_adapter_libuv.c`, `components/network/adapter/luat_lib_socket.c`  
**提交**: `6fee4daff`

---

## 1. 功能概述

为 PC 模拟器的 libuv 网络适配器实现 TCP Server 端口监听功能。原有的 `libuv_socket_listen` 和 `libuv_socket_accept` 为空桩函数（返回 -1），需参考 `net_lwip2.c` 的实现补全。

### 最终实现方案：一对一模式（`no_accept=1`）

- 监听用独立的 `listen_tcp`（堆分配），客户端连接直接 accept 到 socket 的内嵌 `tcp` 句柄
- 不分配新 socket，复用监听 socket 转为在线状态
- 简化了多客户端管理的复杂度，适合 PC 模拟器场景

---

## 2. 关键Bug与修复

### Bug 1: libuv 句柄不可 memcpy（严重）

**现象**: 初始方案尝试将 `accept_tcp` 通过 `memcpy` 复制到 socket 的内嵌 tcp 字段。

**根因**: libuv 的 `uv_tcp_t` 等句柄内部包含链表指针（`handle_queue`），`memcpy` 会破坏 libuv 事件循环的句柄跟踪链表，导致崩溃或悬挂。

**修复**: 改为一对一模式——`on_new_connection` 直接将客户端 accept 到 socket 的内嵌 tcp（该 tcp 已由 `libuv_create_socket` 初始化但未连接，满足 `uv_accept` 的前置条件）。

**教训**:
> ⚠️ **永远不要 memcpy libuv 句柄**。它们包含内部链表指针，必须原地使用。

### Bug 2: CLOSE_OK 事件导致崩溃（ACCESS_VIOLATION）

**现象**: 测试通过后，`socket.close(netc)` 触发 ACCESS_VIOLATION READ at `0x00000013`。

**调试过程**:
1. 在 `close_socket`、`libuv_socket_close` 添加 DBG_ERR 打印 → 全部正常打印，崩溃发生在 return 之后
2. 在 `network_force_close_socket` 逐步添加打印 → 包括 "done" 都打印了
3. 怀疑是异步回调问题 → 发现 `close_socket` 对 LISTENING 状态发送了 `EV_NW_SOCKET_CLOSE_OK`
4. 追踪事件链：`EV_NW_SOCKET_CLOSE_OK` → `cb_to_nw_task` → `uv_async_send` → 回调在 libuv 线程触发 → `network_default_statemachine` → `luat_lib_socket_callback` → 访问 `l_ctrl->task_name`
5. `l_ctrl->task_name` 是**未初始化的野指针**（`lua_newuserdata` 不会清零内存）

**根因链**:
```
close_socket(LISTENING)
  → cb_to_nw_task(EV_NW_SOCKET_CLOSE_OK)
    → uv_async_send (libuv线程执行回调)
      → network_default_socket_callback
        → network_default_statemachine
          → luat_lib_socket_callback
            → lua_pushstring(L, l_ctrl->task_name)  // task_name = 0x00000013 (野指针!)
              → ACCESS_VIOLATION
```

**修复**:
1. **移除 CLOSE_OK 事件**: LISTENING 状态关闭时不发送 `EV_NW_SOCKET_CLOSE_OK`（框架层不需要该事件来完成关闭流程）
2. **初始化 l_ctrl**: 在 `l_socket_create` 中添加 `memset(l_ctrl, 0, sizeof(luat_socket_ctrl_t))`，确保 `cb_ref`、`task_name` 等字段被清零

### Bug 3: cb_to_nw_task 的 param 为 NULL

**现象**: 部分回调路径中 `adapter` 指针为 NULL。

**根因**: `luat_network_cb_param_t` 初始化时 `.param = NULL`，应为 `.param = ctrl.user_data`（适配器指针）。

**修复**: `cb_to_nw_task` 中设置 `.param = ctrl.user_data`。

### Bug 4: socket_state_str 越界

**现象**: 新增 `SC_LISTENING` 状态后，日志打印状态名时可能越界。

**修复**: `socket_state_str` 函数的边界检查更新为包含新状态值。

---

## 3. 线程模型要点

```
┌──────────────┐       ┌──────────────────┐
│  主线程       │       │  libuv 线程       │
│  Lua VM      │       │  uv_run() 事件循环 │
│  消息总线     │       │  I/O 回调处理      │
│  协程调度     │       │                   │
└──────┬───────┘       └────────┬──────────┘
       │                        │
       │  cb_to_nw_task()       │
       │  ─────────────────►    │
       │  (uv_async_send)      │
       │                        │
       │    回调直接调用          │
       │    network_default_    │
       │    socket_callback     │
       │                        │
```

- `cb_to_nw_task` 通过 `uv_async_send` 从主线程向 libuv 线程发送事件
- 回调在 **libuv 线程**执行，直接调用 `network_default_socket_callback`
- 注意：`network_default_statemachine` 会取 `NW_LOCK`，但 `network_force_close_socket` 并非所有操作都加锁，存在潜在竞态

---

## 4. Listen/Close 流程

### Listen 流程
```
socket.listen(netc)
  → network_listen()
    → network_base_connect(ctrl, NULL)
      → libuv_socket_listen(socket_id, tag, port, user_data)
        → malloc listen_tcp, uv_tcp_init, uv_tcp_bind, uv_listen
        → cb_to_nw_task(EV_NW_SOCKET_LISTEN)
          → 状态机: CONNECTING → LISTEN(6)
```

### Accept 流程（一对一模式）
```
客户端连接
  → on_new_connection(server, status)
    → uv_accept(server, &sockets[id].tcp)  // 直接accept到内嵌tcp
    → uv_read_start  // 开始接收数据
    → cb_to_nw_task(EV_NW_SOCKET_CONNECT_OK)
      → 状态机: LISTEN(6) → ONLINE(5)
```

### Close 流程（LISTENING 状态）
```
socket.close(netc)
  → close_socket(socket_id)
    → uv_close(listen_tcp)   // 异步关闭监听句柄, on_listen_close 释放内存
    → uv_close(&tcp)         // 关闭内嵌tcp (已init但未连接)
    → 设置 tag=0, state=SC_CLOSED
    → 不发送 CLOSE_OK 事件!   // 关键: 避免触发野指针访问
```

---

## 5. 调试方法论

1. **分层定位**: 先确定崩溃在哪一层（Lua API → 网络框架 → 适配器层）
2. **逐步打印**: 在疑似路径添加 `DBG_ERR` 打印，缩小范围
3. **异步思维**: 在多线程/异步系统中，崩溃点可能不在调用栈中，而在异步回调中
4. **追踪事件链**: 从事件发送到事件处理，完整追踪回调链
5. **检查初始化**: `lua_newuserdata` / `malloc` 不会清零内存，必须手动初始化
6. **清理调试代码**: 修复后务必移除所有临时打印

---

## 6. 测试验证

### 测试用例: `testcase/function_testcase_network/tcp_server/tcp_server_basic/`

| 测试 | 描述 | 方法 |
|------|------|------|
| `test_tcp_server_listen` | 验证 listen 状态 | 创建 socket → listen(12345) → 轮询等待状态变为 LISTEN(6) |
| `test_tcp_server_self_connect` | 验证数据收发 | Server listen → Client connect → PING/PONG 数据交换 |

### 运行命令
```powershell
cd bsp\pc
.\build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\function_testcase_network\tcp_server\tcp_server_basic\scripts\
```

### 外部测试工具
```bash
python tcp_server_client.py  # 发送 PING, 等待 PONG 响应
```
