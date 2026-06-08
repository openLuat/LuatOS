# PC 模拟器网络层竞态崩溃 — 根因分析

## 崩溃现象

- 经过 22-88 次 HTTPS 连接后，`luatos-lua.exe` 崩溃
- 崩溃点在 `network_default_socket_callback()` / `network_default_statemachine()`
- `--dep_strip=0` + 请求间延迟可以规避

## 根因：事件队列中的悬空 network_ctrl_t 指针

**类型**：Use-After-Free（释放后使用）

**受影响文件**：
- `components/network/adapter/luat_network_adapter.c` — 核心网络层状态机
- `bsp/pc/port/network/luat_network_adapter_posix.c` — PC POSIX 适配器

## 详细分析

### 1. 两套独立的事件队列

PC 模拟器有两套事件队列：

| 队列 | 投递方式 | 消费者 |
|------|----------|--------|
| **msgbus 队列** | `luat_msgbus_put()` (POSIX I/O 线程 → 主线程) | Lua `sys.run()` 主循环 |
| **task 事件队列** | `platform_send_event()` / `luat_send_event_to_task()` | 网络任务的事件循环 |

### 2. 致命的指针快照

当 POSIX 适配器的 I/O 线程投递网络事件时（`luat_network_adapter_posix.c:176`）：

```c
static void cb_to_nw_task(uint32_t event_id, size_t param1, ...)
{
    posix_nw_event_t *e = luat_heap_malloc(sizeof(posix_nw_event_t));
    ...
    pthread_mutex_lock(&g_socket_mutex);
    if (event_id > EV_NW_DNS_RESULT) {
        int sid = (int)(uint32_t)param1;
        if (sid >= 0 && sid < MAX_SOCK_NUM) {
            e->event.Param3 = (size_t)sockets[sid].param;  // ← 快照 network_ctrl_t *
            e->param.tag    = sockets[sid].tag;            // ← 快照 socket tag
        }
    }
    pthread_mutex_unlock(&g_socket_mutex);
    ...
    luat_msgbus_put(&msg, 0);  // 异步投递到 Lua 主线程
}
```

关键问题：`e->event.Param3` 是 `network_ctrl_t *` 指针的快照副本，但 `network_ctrl_t` 的生命周期由上层网络层管理，与 POSIX socket 槽位完全独立。

### 3. 竞态窗口（Race Window）

```
时刻  I/O 线程 (pthread)                  Lua 主线程 (sys.run())
────  ──────────────────────────────────  ─────────────────────────────
T1    服务端发送最后一个数据块
T2    recv() 返回 N 字节
T3    cb_to_nw_task(EV_RX_NEW, ...)  →  [事件 A]: Param3 = ctrl_X
      │ 入队 msgbus
T4    再次 recv() → 返回 0 (EOF)
T5    cb_to_nw_task(EV_REMOTE_CLOSE, ...)  →  [事件 B]: Param3 = ctrl_X
      │ 入队 msgbus
T6    io_running = 0 (槽位可复用)        sys.run() 取到 [事件 A]
      │                                    └─ network_default_statemachine(ctrl_X)
      │                                       └─ NW_LOCK(ctrl_X->mutex)   ← 仍有效
      │                                       └─ 发送 task 事件
      │                                    sys.run() 取到 [事件 B]
      │                                    └─ network_default_statemachine(ctrl_X)
      │                                       └─ ctrl_X->need_close = 1
      │                                       └─ 发送 task 事件
      │                                    task 处理事件 B → network_close()
      │                                    └─ network_force_close_socket()
      │                                    └─ network_release_ctrl(ctrl_X)
      │                                       └─ ctrl_X->mutex = NULL  ← 释放!
      │                                       └─ ctrl_busy[i] = 0
T7    新数据到达? (如果服务端再发数据)
      cb_to_nw_task(EV_RX_NEW, ...)  →  [事件 C]: Param3 = ctrl_X ← 悬空!
      │ 如果 I/O 线程已停止，此步骤不发生

        ─ 或者 ─

T7                                     sys.run() 取到 [事件 C] (若存在)
      │                                    └─ ctrl = (network_ctrl_t *)event->Param3
      │                                       ctrl 指向已释放的内存!
      │                                       └─ NW_LOCK(ctrl->mutex)
      │                                          mutex 是 NULL → CRASH!
```

### 4. 为什么 `network_release_ctrl` 后 ctrl 变"僵尸"

`network_release_ctrl()` (luat_network_adapter.c:1425) 释放了 ctrl 的关键资源：

```c
void network_release_ctrl(network_ctrl_t *ctrl)
{
    network_deinit_tls(ctrl);           // 释放 TLS 上下文
    platform_release_timer(ctrl->timer); // 释放定时器
    ctrl->timer = NULL;
    luat_heap_free(ctrl->cache_data);    // 释放缓存
    ctrl->cache_data = NULL;
    luat_heap_free(ctrl->dns_ip);       // 释放 DNS 结果
    ctrl->dns_ip = NULL;
    luat_heap_free(ctrl->domain_name);  // 释放域名
    ctrl->domain_name = NULL;
    adapter->ctrl_busy[i] = 0;          // 标记为可用
    platform_release_mutex(ctrl->mutex); // 释放互斥锁
    ctrl->mutex = NULL;                  // ← 设为 NULL!
}
```

**但 `ctrl->tag` 没有被清零。**当悬空事件到达 `network_default_socket_callback` 时：

```c
network_ctrl_t *ctrl = (network_ctrl_t *)event->Param3;  // 悬空指针

// 第 1113 行: 如果 ctrl 非 NULL (释放后内存可能不为 NULL)
if (event->ID != 0 && event->ID != EV_NW_DNS_RESULT && ctrl) {
    luat_netdrv_fire_socket_event_netctrl(event->ID, ctrl, 0);  // 访问已释放的 ctrl
}

// 第 1121 行: ctrl->tag 可能碰巧匹配 (未被清零)
if (ctrl && ((event->ID == EV_NW_DNS_RESULT) || (ctrl->tag == cb_param->tag)))
{
    network_default_statemachine(ctrl, event, adapter);  // ← 崩溃点
    // 状态机第一行: NW_LOCK(ctrl->mutex)
    //              = platform_lock_mutex(NULL) → CRASH
```

### 5. 代码中的已知问题证据

`luat_network_adapter.c:1148-1150` 已有注释确认：

```c
DBG_ERR("cb ctrl invaild %x %08X", ctrl, event->ID);
// 下面这行的打印在部分平台会有问题
// 原因是ctrl可能已经被释放, 再次访问会导致coredump
//DBG_HexPrintf(&ctrl->tag, 8);
```

中文大意："原因是 ctrl 可能已经被释放，再次访问会导致 coredump"

### 6. 为什么 `--dep_strip=0` 能"修复"

`--dep_strip=0` **不是真正的修复，只是改变了时序：**

| 参数 | 行为 | 影响 |
|------|------|------|
| `--dep_strip=1` (默认) | 只打包 require() 链中的文件 | Lua VM 初始化更快，HTTP 请求密集，事件堆积更多 |
| `--dep_strip=0` | 打包所有文件 | 更多模块初始化 → 更慢的执行 → 请求间隔更长 → 事件堆积更少 |

更多的 Lua 模块意味着：
- 更大的堆内存占用 → 不同的内存布局
- 更多模块初始化开销 → 请求间延迟增加
- GC 触发更频繁 → 异步事件处理速度变化

这些时序变化恰好使竞态窗口出现的概率降到极低水平（但并非零）。

### 7. 复现条件

| 条件 | 说明 |
|------|------|
| 快速连续发起 HTTP(S) 请求 | 大量 TCP 连接短时间建立/关闭 |
| 网络延迟低 | 数据快速到达，RX_NEW 事件快速投递 |
| `--dep_strip=1` | Lua VM 负载轻，处理速度快 |
| MAX_SOCK_NUM=32 | 槽位有限，增加了重用概率 |

### 8. 两个关键的次级问题

**A. `posix_socket_force_close` 不清除 `conn->param`**

`luat_network_adapter_posix.c:569` 的 `close_socket_internal(socket_id, 1)` 设置 `conn->tag = 0` 但**不清除 `conn->param`**。如果 socket 槽位被新的连接重用，`sockets[sid].param` 可能仍然指向旧的 `network_ctrl_t`，而新的 `cb_to_nw_task` 调用会使用这个过时的指针。

**B. `posix_socket_close` 返回 1 的语义问题**

`luat_network_adapter_posix.c:894`：

```c
static int posix_socket_close(int socket_id, uint64_t tag, void *user_data)
{
    ...
    close_socket_internal(socket_id, 0);  // 设置 io_stop=1
    return 1;  // 强制上层也调用 force_close
}
```

返回 1 告诉上层 "还需要调用 force_close"。这导致 `network_socket_close` + `network_socket_force_close` 的双重调用路径，增加了 `close_socket_internal` 被多次调用的可能性。

## 修复建议

### 方案 A：在 `network_release_ctrl` 中清除 tag（最小改动）

在 `network_release_ctrl` 结束前添加：

```c
ctrl->tag = 0;  // 使悬空事件在 tag 检查时被拒绝
```

**优点**：一行改动
**缺点**：不解决 POSIX 层 `conn->param` 悬空问题；如果 ctrl 槽位被重用且新 ctrl 的 tag 恰等于旧的 cb_param->tag，仍有误路由风险

### 方案 B：在 `network_default_socket_callback` 中添加 mutex 安全检查

在访问 `ctrl->tag` 前检查 `ctrl->mutex` 是否有效：

```c
// 在 line 1121 之前添加
if (!ctrl->mutex) return 0;  // ctrl 已释放，丢弃事件
```

**优点**：防御所有已释放 ctrl 的访问
**缺点**：依赖 ctrl->mutex 的 NULL 语义（需要确保其他路径也设置 mutex=NULL）

### 方案 C：在 POSIX 适配器中，不在事件中传递裸指针（根本修复）

修改 `cb_to_nw_task`，使用 socket_id 而非 `network_ctrl_t *`：

```c
// 不再快照 sockets[sid].param
// 改为: 在 posix_nw_event_handler 中用 socket_id 重新查找
e->event.Param3 = (size_t)(uintptr_t)sid;  // 传 socket_id 而非指针
```

然后在 `posix_nw_event_handler` 中：

```c
// 根据 socket_id 和 tag 查找对应的 ctrl
for (i = 0; i < adapter->max_socket_num; i++) {
    if (adapter->ctrl_busy[i] && 
        adapter->ctrl_table[i].tag == e->param.tag) {
        ctrl = &adapter->ctrl_table[i];
        break;
    }
}
```

**优点**：根本解决
**缺点**：改动较大，影响所有平台，需要测试

### 方案 D：在 `close_socket_internal` 中同步清理 conn->param（防御措施）

```c
if (force) {
    conn->state = SC_CLOSED;
    conn->tag = 0;
    conn->param = NULL;  // 添加此行
}
```

**优点**：防止槽位重用时读到旧指针
**缺点**：不能解决已入队事件中的悬空指针

### 推荐组合方案

- **立即修复**：方案 A (ctrl->tag = 0) + 方案 D (conn->param = NULL) — 低风险，覆盖大部分场景
- **长期方案**：方案 C (用 socket_id 替代裸指针) — 需要完整回归测试

## 相关文件索引

| 文件 | 行号 | 角色 |
|------|------|------|
| `components/network/adapter/luat_network_adapter.c` | 1103-1187 | `network_default_socket_callback` — 事件分发入口 |
| `components/network/adapter/luat_network_adapter.c` | 1045-1100 | `network_default_statemachine` — 状态机，崩溃点 |
| `components/network/adapter/luat_network_adapter.c` | 1425-1469 | `network_release_ctrl` — 释放 ctrl，产生"僵尸" |
| `components/network/adapter/luat_network_adapter.c` | 1148 | 已知问题的注释 |
| `bsp/pc/port/network/luat_network_adapter_posix.c` | 176-213 | `cb_to_nw_task` — 投递事件，快照悬空指针 |
| `bsp/pc/port/network/luat_network_adapter_posix.c` | 569-627 | `close_socket_internal` — 不清理 conn->param |
| `bsp/pc/port/network/luat_network_adapter_posix.c` | 639-724 | `posix_create_socket` — 设置 conn->param = ctrl |
| `bsp/pc/port/network/luat_network_adapter_posix.c` | 893-904 | `posix_socket_close` — 返回 1 触发双重关闭 |
| `bsp/pc/port/rtos/luat_rtos_task_pc.c` | 41-43 | `luat_send_event_to_task` — 异步投递 task 事件 |
| `bsp/pc/port/rtos/luat_msgbus_pc.c` | 22-38 | `luat_msgbus_put` — 异步投递 msgbus 事件 |
