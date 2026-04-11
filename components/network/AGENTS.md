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
├── ulwip/            # Micro LwIP variant
├── libhttp/          # HTTP protocol
├── libsntp/          # SNTP time sync
├── netdrv/           # Network drivers
├── errdump/          # Error dumping
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

## THREE-LAYER ARCHITECTURE

```
┌─────────────────────────────────┐
│ Lua API (luat_lib_socket.c)     │  socket.create/listen/accept/rx/tx
├─────────────────────────────────┤
│ Framework (luat_network_adapter │  network_ctrl_t state machine
│           .c / .h)             │  States: OFF_LINE → CONNECTING → ONLINE / LISTEN
├─────────────────────────────────┤
│ Adapter (per-platform)          │  lwip2: net_lwip2.c
│                                 │  PC:    luat_network_adapter_libuv.c
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
