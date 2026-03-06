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
| SNTP | `libsntp/` | `libsntp.c` |
| HTTP server | `httpsrv/` | `httpsrv.c` |

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
