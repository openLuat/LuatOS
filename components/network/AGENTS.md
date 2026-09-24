# LuatOS Network Stack

**Scope**: `components/network/` - Network protocols and communication stacks.

## OVERVIEW

Network subsystem providing TCP/UDP, HTTP, MQTT, WebSocket, CoAP, and low-level networking (LwIP) support.

## STRUCTURE

```
network/
├── adapter/          # Network adapter abstraction
├── adapter_lwip2/    # LwIP 2.x integration
├── libhttp/          # HTTP client implementation
├── libemqtt/         # MQTT client
├── websocket/        # WebSocket client/server
├── lwip22/           # LwIP 2.2 source
├── libhttp/          # HTTP protocol
├── libsntp/          # SNTP time sync
├── netdrv/           # Network drivers
├── errdump/          # Error dumping
├── l2tp/             # L2TPv2 client (RFC 2661, netdrv submodule)
├── ipsec/            # IKEv2/IPsec client (netdrv submodule)
├── openvpn/          # OpenVPN client (netdrv submodule)
├── wireguard/        # VPN support
└── httpsrv/          # HTTP server
```

## WHERE TO LOOK

| Protocol | Location | Key File |
|----------|----------|----------|
| HTTP client | `libhttp/` | `libhttp.c` |
| MQTT | `libemqtt/` | `libemqtt.c` |
| WebSocket | `websocket/` | `websocket.c` |
| TCP/UDP (raw) | `adapter/` | `luat_network_adapter.c` |
| Socket Lua API | `adapter/` | `luat_lib_socket.c` |
| SNTP | `libsntp/` | `libsntp.c` |
| HTTP server | `httpsrv/` | `httpsrv.c` |
| L2TP | `l2tp/` | `src/l2tp_client.c` (control plane) + `src/l2tp_ppp.c` |
| IPsec | `ipsec/` | `src/ipsec_ike.c` (IKEv2 state machine) |
| OpenVPN | `openvpn/` | `src/ovpn_client.c` + `src/ovpn_tls.c` |

## THREE-LAYER ARCHITECTURE

```
┌─────────────────────────────────┐
│ Lua API (luat_lib_socket.c)     │  socket.create/listen/accept/rx/tx
├─────────────────────────────────┤
│ Framework (luat_network_adapter │  network_ctrl_t state machine
│           .c / .h)             │  States: OFF_LINE → CONNECTING → ONLINE / LISTEN
├─────────────────────────────────┤
│ Adapter (per-platform)          │  lwip2: net_lwip2.c
│                                 │  PC:    luat_network_adapter_posix.c
└─────────────────────────────────┘
```

### State Machine (network_ctrl_t)
```
NW_STATE_LINK_OFF(0) → NW_STATE_OFF_LINE(1) → NW_STATE_CONNECTING(3)
  → NW_STATE_ONLINE(5)      (client connected)
  → NW_STATE_LISTEN(6)      (server listening)
  → NW_STATE_DISCONNECTING(7)
```

### Key Events
| Event | Meaning |
|-------|---------|
| `EV_NW_SOCKET_LISTEN` | Listen started successfully |
| `EV_NW_SOCKET_CONNECT_OK` | Client connected (or accepted) |
| `EV_NW_SOCKET_CLOSE_OK` | Socket closed (⚠️ not sent for LISTEN close) |
| `EV_NW_SOCKET_RX_NEW` | Data received |
| `EV_NW_SOCKET_TX_OK` | Data sent |

### TCP Server (Listen/Accept) Notes
- Framework supports two modes: `no_accept=0` (allocates new socket per client) and `no_accept=1` (reuses listener socket)
- PC simulator uses `no_accept=1` (one-to-one mode)
- When closing a LISTENING socket, do NOT send `EV_NW_SOCKET_CLOSE_OK` — it triggers callbacks that may access uninitialized Lua state
- `l_socket_create` must `memset(l_ctrl, 0, ...)` — `lua_newuserdata` does not zero memory

### UDP Receive Contract
- Public `socket.rx(ctrl, buff, limit)` semantics for UDP are: return at most `limit` bytes from the current datagram, then discard the unread tail of that datagram.
- TCP is different: unread bytes stay queued and can be read by the next `socket.rx(...)`.
- TLS/DTLS internal reads are the only receive path that should preserve unread UDP tail data across partial reads, and they must do it explicitly with `NETWORK_RX_FLAG_PRESERVE_UDP_REMAIN`.
- When modifying adapter `socket_receive()` implementations, do not globally preserve UDP unread remainder for normal reads. `bsp/pc/port/network/luat_network_adapter_posix.c` and `components/network/adapter_lwip2/net_lwip2.c` are the current reference shape for the flag-gated behavior.
- `components/network/lwip_with_sdk/net_lwip.c` and `components/ethernet/w5500/w5500.c` still keep the older behavior today; align them separately if you need repo-wide consistency.

### Debug Macros
- `DBG()` — prints only when `ctrl->is_debug` is true (per-socket)
- `DBG_ERR()` — always prints regardless of debug flag
- Both require `__NW_DEBUG_ENABLE__` defined (line ~162 of `luat_network_adapter.c`)

## CONVENTIONS

**Network Adapter API:**
- Use `network_adapter` for unified network interface
- Callback-based async operations
- Buffer management via `luat_zbuff`

**Protocol Clients:**
- Initialize with `*_init()` function
- Connect with host/port parameters
- Event callbacks: on_connect, on_receive, on_close

**libhttp 跨线程通知（luatos 模式）:**
- `luat_http_client.c` → `luat_lib_http.c` 的通知必须走自包含的 `luat_http_msg_t`（`libhttp/luat_http.h`），消息内禁止携带 `luat_http_ctrl_t`（指针也不行）——多核平台上 luatos 与 lwip 不同核，共享控制块会竞争 free
- `http_ctrl` 的访问与释放只在网络事件派发线程（lwip 板卡=lwip 任务；PC 上即 VM 线程，事件经 msgbus 派发）串行进行；释放/超时命令必须投递到**派发线程自己的队列**（`http_post_cmd`：lwip 板卡走 `network_tcpip_callback`，其余走 msgbus——**else 分支仅在网络事件经 msgbus 派发到 VM 线程的构建上成立**，新增非 msgbus 派发的适配器时必须重新评估），禁止嵌套在回调链里就地执行、也禁止投到别的线程（曾因投到 lwip 任务与 VM 派发并发而段错误）；跨线程寻址一律用 `idg`（`luat_http_idg_claim` 原子认领防重复释放；teardown 把已认领的 ctrl 指针作为所有权移交传给派发线程执行，属受控例外），luatos 模式的定时器回调同样以 idg 寻址
- 消息及其 headers/body 的所有权随投递移交：消费端（VM 线程）用完调用 `luat_http_msg_free`；通知投递失败由生产端释放（终态交付失败另有 `luat_http_fail_notify` 轻量兜底防 Lua 侧挂起）；teardown/超时命令投递失败则放弃（罕见队列满会泄漏 ctrl/netc 槽位，以泄漏换正确性——不得就地执行补救）

## FEATURE FLAGS

```c
#define LUAT_USE_NETWORK  // Enable network stack
#define LUAT_USE_SNTP     // Enable SNTP
#define LUAT_USE_MQTT     // Enable MQTT
#define LUAT_USE_WEBSOCKET // Enable WebSocket
```

## ANTI-PATTERNS

- ❌ Do NOT call LwIP directly - use adapter layer
- ❌ Do NOT block in network callbacks
- ❌ Do NOT assume network is always available
