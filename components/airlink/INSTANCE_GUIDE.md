# AirLink 实例模式使用说明

适用版本：LuatOS `fix/airlink-air8000s-instance` 分支，基于 `feat/airlink-dual-arq3`，包含提交 `7dda7d0d2`、`4657bee58`。

更新时间：2026-11-17。

## 1. 功能概述

实例模式允许主控同时连接两个 AirLink 从机，各自独立收发、维护状态及绑定网卡。

已验证的组合：

| 组合 | 连接方式 |
|---|---|
| 6205＋780EPM | 双 UART |
| 6205＋780EPM | 共享 SPI 总线、独立 CS |
| 6208＋780EPM | UART＋SPI |
| AIR8605 板载 6205 | UART3 单实例 |

本文约定：

- 实例 `0`：Wi-Fi，6205/6208。
- 实例 `1`：蜂窝，780。
- Wi-Fi 网卡：`socket.LWIP_STA`。
- 蜂窝转发网卡：`socket.LWIP_GP_GW`。

**实例 ID、UART/SPI 编号、网卡编号是三种不同的编号。** 实例 `0` 并不表示 UART0。本文的实例分配是示例约定，实际功能路由根据配置的驱动能力选择实例。

## 2. 开启方式与兼容性

### 2.1 编译配置

主控固件需要启用：

```c
#define LUAT_USE_AIRLINK_INSTANCE 1
```

并包含 AirLink、对应传输方式和网络组件。

**Air8000 默认自动启动板内 Air8000S。** 在已有的
`LUAT_USE_AIRLINK_AUTO_MASTER` 配置上开启 `LUAT_USE_AIRLINK_INSTANCE` 后，
固件在执行 `main.lua` 前自动创建实例 `0`，绑定STA/AP网卡，最多等待链路就绪500 ms。
脚本仍可直接使用 `wlan.init()` / `wlan.connect()`，只需为外接从机配置实例 `1`。
不带Wi-Fi的子型号不会自动创建实例；创建失败会记录错误，不回退到legacy。
未开启实例宏的固件继续使用原legacy自动启动流程。

如需由脚本自行分配全部实例，可额外开启**可选的手动启动宏**：

```c
#define LUAT_USE_AIRLINK_MANUAL_SETUP 1
```

该宏优先于自动启动配置，禁止Lua执行前自动创建板内实例。
手动启动固件必须由脚本配置链路，不能依赖旧脚本隐式启动 Wi-Fi。
该宏必须与 `LUAT_USE_AIRLINK_INSTANCE` 同时定义。

当前 CCM SDK 已在以下文件开启（路径相对于 CCM SDK 仓库根目录）：

```text
csdk/project/luatos/include/luat_conf_bsp.h
```

Lua 检查：

```lua
assert(type(airlink.setup) == "function", "固件不支持AirLink实例模式")
```

### 2.2 运行方式

- 未开启实例宏的Air8000，以及未使用自动实例启动或 `setup` 的其他平台，保留legacy路径。
- Air8000自动实例固件保留Wi-Fi使用习惯，但板内链路已是实例 `0`，不要重复 `setup(0, ...)`。
- 新脚本直接调用 `airlink.setup(id, conf)`，进入实例模式。
- 实例模式不需要预先调用 `airlink.init()`、`airlink.config()`、`airlink.start()`。
- 同一次启动中，两套初始化方式不能混用。

**Air8000同时开启实例和自动启动宏时，板内链路自动切换为实例模式。**
其他手动配置平台仍由 `airlink.setup()` 进入实例模式。

旧模式下，无参数 `ready()`、`statistics()`、`sver()` 保留原有路径。但此前传给无参数接口、被忽略的多余参数，现在可能被解释为实例 ID，例如 `airlink.ready(0)`。

实例模式下，查询接口应明确传入实例 ID。无参数 `statistics()` 仍是旧全局统计入口，不代表两个实例的统计总和。

## 3. 创建实例

```lua
local ok, rc = airlink.setup(id, conf)
```

返回：

- `ok`：是否创建成功。
- `rc`：`0` 表示成功，负数表示错误。

创建成功表示实例任务已启动；对端握手和网络就绪需要另外等待。建议在 `sys.taskInit` 创建的任务中调用。

### 3.1 配置参数

| 参数 | 说明 | 默认值 |
|---|---|---|
| `drv` | 从机驱动名称，必填 | 无 |
| `mode` | UART 或 SPI 主机模式 | `airlink.MODE_UART` |
| `uart_id` | 主控 UART 编号 | `1` |
| `baudrate` | UART 波特率 | `2000000` |
| `spi_id` | 主控 SPI 编号 | `0` |
| `cs` | 主控连接该从机的片选 GPIO | `255`，SPI 使用时必须配置 |
| `rdy` | 主控连接该从机 RDY 的 GPIO | `255`，未配置 |
| `speed` | SPI 时钟频率，Hz | `20000000` |
| `sta_adapter` | Wi-Fi STA 对应的主控网卡 | Wi-Fi 驱动默认 STA，蜂窝驱动默认 `-1` |
| `ap_adapter` | Wi-Fi AP 对应的主控网卡 | Wi-Fi 驱动默认 AP，蜂窝驱动默认 `-1` |
| `cellular_adapter` | 蜂窝转发对应的主控网卡 | 蜂窝驱动默认 GP_GW，Wi-Fi 驱动默认 `-1` |

网卡参数可用 `-1` 表示不映射。通常保留驱动默认值即可。

`drv` 支持：

```text
air6205
air6208
air8000s
air780epm
air780er2
```

驱动名称被接受，不代表对应板型、固件和接线已经完成验收；当前 780 双路验收使用的是 Air780EPM。

`air8000s` 使用 Air8000 板内 SPI 默认配置：`mode=airlink.MODE_SPI_MASTER`、
`spi_id=0`、`cs=8`、`rdy=22`、`speed=31000000`，SPI Mode 3、8位、MSB、
1600字节全双工帧。默认值来自现有Air8000驱动，不代表新的多路硬件验收结果。
可显式覆盖SPI参数；该驱动不接受UART或HSPI模式，返回 `-3`。
其能力为Wi-Fi和BLE，网卡默认映射STA/AP。

### 3.2 双 UART

```lua
local ok, rc = airlink.setup(0, {
    drv = "air6205",
    mode = airlink.MODE_UART,
    uart_id = 1,
    baudrate = 2000000
})
assert(ok, "Wi-Fi setup失败: " .. tostring(rc))

ok, rc = airlink.setup(1, {
    drv = "air780epm",
    mode = airlink.MODE_UART,
    uart_id = 2,
    baudrate = 2000000
})
assert(ok, "蜂窝 setup失败: " .. tostring(rc))
```

UART 使用 8N1，两端波特率一致，TX/RX 交叉连接并共地。`setup` 会配置主控 UART，无需再对同一端口调用 `uart.setup()`。

### 3.3 共享 SPI

下面为已测试的主控引脚配置：

```lua
-- 先保证两个从机都处于未选中状态
gpio.setup(12, 1, gpio.PULLUP)
gpio.setup(8, 1, gpio.PULLUP)

assert(airlink.setup(0, {
    drv = "air6205",
    mode = airlink.MODE_SPI_MASTER,
    spi_id = 1,
    cs = 12,
    rdy = 41,
    speed = 1000000
}))

assert(airlink.setup(1, {
    drv = "air780epm",
    mode = airlink.MODE_SPI_MASTER,
    spi_id = 1,
    cs = 8,
    rdy = 42,
    speed = 1000000
}))
```

两路共用 SCLK/MOSI/MISO，各用独立 CS、RDY，并共地。实例内部通过总线锁协调传输。

这里的 `cs`、`rdy` 都是**主控 GPIO 编号**。780 从机自己的引脚需要在从机侧另行配置。已验证的 EPM 从机配置为 SPI0、CS8、RDY22。

当前验收速度为 **1 MHz**；虽然接口默认 20 MHz，使用时建议明确填写已验证的频率。共享总线上的 780EPM 需使用包含硬件 CS 修复的固件。

该修复对 EC718M 的 SPI0/CS8、SPI1/CS12 原生片选组合采用硬件 CS 和固定 1600 字节 DMA 完成通知；其他片选组合保留旧路径。

### 3.4 UART＋SPI

组合上述两种配置即可，例如：

```lua
assert(airlink.setup(0, {
    drv = "air6208",
    mode = airlink.MODE_UART,
    uart_id = 2,
    baudrate = 2000000
}))

assert(airlink.setup(1, {
    drv = "air780epm",
    mode = airlink.MODE_SPI_MASTER,
    spi_id = 1,
    cs = 8,
    rdy = 42,
    speed = 1000000
}))
```

### 3.5 Air8000 内置 Air8000S＋外接从机

主控保留Air8000原有自动启动配置，开启实例宏，**无需开启手动启动宏**：

```lua
sys.taskInit(function()
    -- 板内Air8000S已经自动创建为实例0，无需再次setup。
    assert(airlink.status(0), "板内Air8000S自动创建失败")

    -- 示例：外接780，UART编号必须按实际接线填写。
    local ok, rc = airlink.setup(1, {
        drv = "air780epm",
        mode = airlink.MODE_UART,
        uart_id = 1,
        baudrate = 2000000
    })
    assert(ok, "外接从机setup失败: " .. tostring(rc))
    -- 后续按第4节等待链路，再执行wlan.init/wlan.connect。
end)
```

仅使用板内Wi-Fi时，不需要任何 `airlink.setup()` 调用。
若开启 `LUAT_USE_AIRLINK_MANUAL_SETUP`，则先在任务中执行
`assert(airlink.setup(0, {drv = "air8000s"}))`，再配置外接实例。

Air8000自身的蜂窝网卡仍是 `socket.LWIP_GP`，外接780使用
`socket.LWIP_GP_GW`，两者不能混淆。
板内GPIO23上电时序和3.3V IO配置仍由Air8000 BSP启动代码负责；
组件不会把其他主控的GPIO23当作通用电源脚。

驱动收到Wi-Fi设备信息后，将GPIO24配置为输出并拉高，以维持Air8000充电IC。
这两条初始化命令明确发往该实例，即使Air8000S配置在实例1，也不会误发到实例0。
它是**从机GPIO24**，不是主控GPIO24。`ready(id)` 在初始化命令完成发送后才为真；
这不等于对端应用执行确认。链路超时后收到新帧会重新进行初始化。

此处覆盖实例创建、SPI收发、功能路由和启动初始化。旧 `airlink.power`、
`irqmode`、`wakeup_irqmode` 等单实例省电/中断接口不属于多路配置接口，
不要与本节流程混用；多路休眠和快速断电重启仍需单独适配、验收。

## 4. 等待链路就绪

在 `sys.taskInit` 创建的任务中等待：

```lua
local function wait_link(id, timeout_ms)
    for _ = 1, math.ceil(timeout_ms / 100) do
        local s = airlink.status(id)
        if s and s.ready and s.version > 0 then
            return s
        end
        sys.wait(100)
    end
    error("AirLink握手超时: " .. id)
end

local wifi = wait_link(0, 15000)
local cell = wait_link(1, 15000)

assert(wifi.peer_type == 1, "实例0不是Wi-Fi设备")
assert(cell.peer_type == 2, "实例1不是蜂窝设备")
```

需要区分三个状态：

| 状态 | 含义 |
|---|---|
| `setup` 成功 | 实例创建及任务启动成功 |
| `airlink.ready(id)` | AirLink 通信链路就绪 |
| `netdrv.ready(adapter)` | 对应主控网卡就绪 |

**AirLink ready 不等于已经可以访问互联网。** 实际联网能力应通过指定网卡的请求验证。

## 5. 双网络联网完整示例

### 5.1 主控脚本

下面示例使用双 UART。前提是：

- 6205 已运行对应 AirLink 从机固件。
- 780 已运行 AirLink 从机，并配置蜂窝 NAPT、DNS 代理。
- 780 转发网卡地址为 `192.168.111.2/24`。
- 根据实际板卡完成必要的供电、复位和外部看门狗初始化。

```lua
PROJECT = "airlink_dual_example"
VERSION = "001.000.000"

sys = require "sys"

local WIFI = socket.LWIP_STA
local CELL = socket.LWIP_GP_GW
local wifi_ip_ready = false

sys.subscribe("IP_READY", function(ip, adapter)
    if adapter == WIFI and ip and ip ~= "0.0.0.0" then
        wifi_ip_ready = true
    end
    log.info("IP_READY", adapter, ip)
end)

sys.subscribe("IP_LOSE", function(adapter)
    if adapter == WIFI then
        wifi_ip_ready = false
    end
end)

local function wait_for(check, timeout_ms, message)
    for _ = 1, math.ceil(timeout_ms / 100) do
        if check() then return end
        sys.wait(100)
    end
    error(message)
end

local function setup_link(id, conf)
    local ok, rc = airlink.setup(id, conf)
    assert(ok, "setup失败: " .. id .. ", rc=" .. tostring(rc))
end

local function request(adapter, name)
    local payload = "hello from " .. name
    local code, _, body = http.request(
        "POST",
        "http://httpbin.luatos.com/post",
        {["Content-Type"] = "text/plain"},
        payload,
        {adapter = adapter, timeout = 20000}
    ).wait()

    local obj = code == 200 and type(body) == "string"
        and json.decode(body)
    local passed = type(obj) == "table" and obj.data == payload
    log.info(name, "HTTP", code, "回显一致", passed)
end

sys.taskInit(function()
    assert(type(airlink.setup) == "function", "固件缺少实例接口")

    setup_link(0, {
        drv = "air6205",
        mode = airlink.MODE_UART,
        uart_id = 1,
        baudrate = 2000000
    })

    setup_link(1, {
        drv = "air780epm",
        mode = airlink.MODE_UART,
        uart_id = 2,
        baudrate = 2000000
    })

    for id = 0, 1 do
        wait_for(function()
            local s = airlink.status(id)
            return s and s.ready and s.version > 0
        end, 15000, "链路握手超时: " .. id)
        log.info("link", id, json.encode(airlink.status(id)))
    end

    assert(airlink.status(0).peer_type == 1, "Wi-Fi对端类型错误")
    assert(airlink.status(1).peer_type == 2, "蜂窝对端类型错误")

    -- 主控到780的转发网段
    netdrv.ipv4(CELL, "192.168.111.1",
        "255.255.255.0", "192.168.111.2")
    socket.setDNS(CELL, 1, "192.168.111.2")

    -- Wi-Fi连接
    wlan.init()
    wifi_ip_ready = false
    wlan.connect("你的SSID", "你的密码", 1)

    wait_for(function()
        return wifi_ip_ready and netdrv.ready(WIFI)
    end, 90000, "Wi-Fi获取IP超时")

    wait_for(function()
        return netdrv.ready(CELL)
    end, 90000, "蜂窝转发网卡未就绪")

    -- 两个任务分别指定网卡，独立发起请求
    sys.taskInit(function() request(WIFI, "wifi") end)
    sys.taskInit(function() request(CELL, "cellular") end)
end)

sys.run()
```

业务请求通过 `adapter` 选择出口。实例模式本身不自动提供网络故障切换或负载均衡。

### 5.2 780 UART 从机侧参考

780 仍可使用旧单实例接口，与主控实例模式通信：

```lua
PROJECT = "airlink_cell_peer"
VERSION = "001.000.000"

sys = require "sys"
local dnsproxy = require "dnsproxy"

sys.taskInit(function()
    assert(uart.setup(1, 2000000, 8, 1) == 0)

    airlink.init()
    airlink.config(airlink.CONF_UART_ID, 1)
    sys.wait(100)
    airlink.start(airlink.MODE_UART)

    netdrv.setup(socket.LWIP_GP_GW, netdrv.WHALE)
    netdrv.ipv4(socket.LWIP_GP_GW,
        "192.168.111.2", "255.255.255.0", "192.168.111.1")

    while not socket.adapter(socket.LWIP_GP) do
        sys.wait(1000)
    end

    netdrv.napt(socket.LWIP_GP)
    dnsproxy.setup(socket.LWIP_GP_GW, socket.LWIP_GP)
end)

sys.run()
```

这段依赖支持对应接口的蜂窝固件，以及 `dnsproxy` 模块。已验证的 EPM 构建使用 DATA3 固件类型；不同 780 型号应使用其对应固件。

## 6. 状态、统计与链路探测

### 6.1 状态查询

```lua
local s = airlink.status(0)
log.info("status", json.encode(s))
```

未配置的实例返回 `nil`。主要字段：

| 字段 | 含义 |
|---|---|
| `id` | 实例 ID |
| `ready` | 链路是否就绪 |
| `peer_type` | `1` 为 Wi-Fi，`2` 为蜂窝；尚未取得信息时可能为 `0` |
| `version` | 对端上报版本 |
| `arq` | ARQ 协商状态；本轮 UART 测试就绪值为 `1` |
| `rpc` | 对端是否声明 RPC 能力 |
| `fragment` | 对端是否声明分片能力 |
| `sta_state` | 对端 Wi-Fi STA 状态 |
| `cat_state` | 对端蜂窝状态 |
| `sta_adapter` | 主控映射的 STA 网卡 |
| `cellular_adapter` | 主控映射的蜂窝转发网卡 |

其他查询：

```lua
local ready = airlink.ready(0)
local version = airlink.sver(0)
```

UART 在双方支持时协商 ARQ3；旧对端可继续使用 legacy。当前 SPI 使用 legacy，`arq=0` 属于正常情况。不能将 SPI 联网测试描述为 ARQ3 验证。

### 6.2 统计查询

```lua
local s = airlink.statistics(0)
log.info("statistics", json.encode(s))
```

未配置的实例返回 `nil`。包括：

- `tx_pkg`、`rx_pkg`：链路包统计。
- `tx_ip`、`rx_ip`：IP 包统计。
- `tx_bytes`、`rx_bytes`：字节统计。
- `arq`：ARQ 状态。
- `retx`：ARQ 重传次数。
- `giveup`：ARQ 放弃次数。
- `duplicate`：重复帧去重次数。

各统计分组包含 `total/ok/err/drop`。这些是对应代码路径的计数，`drop=0` 不能单独证明物理链路完全无丢帧。

### 6.3 AirLink ping

```lua
sys.subscribe("AIRLINK_PING_RESULT", function(reqid, ok, value, echo)
    log.info("ping", reqid, ok, value, echo)
end)

local reqid = airlink.ping("hello", 3000, 0)
```

第三个参数为实例 ID。这是对 AirLink 对端的回显探测，不是互联网 ICMP ping。多路同时探测时，用返回的 `reqid` 区分结果。

成功时，事件中的 `value` 为往返耗时毫秒数，`echo` 为回显数据；失败时 `value` 为 `"timeout"` 或错误码，`echo` 为 `nil`。

## 7. 关闭实例

```lua
local ok, rc = airlink.close(0)
assert(ok, "close失败: " .. tostring(rc))
```

关闭实例 `0` 后，实例 `1` 可以继续通信。

关闭是异步处理：工作任务会清理队列并释放传输缓冲。若检查收发是否停止，应留出收尾时间：

```lua
airlink.close(0)
sys.wait(1500)
log.info("link0 ready", airlink.ready(0))
```

上述等待时间用于示例观察，不是同步完成通知。

当前实现保留已关闭实例的槽位和网卡归属：

- 不能对同一 ID 再次 `setup`。
- 不能通过关闭全部实例切回旧初始化流程。
- 重新配置需要重启。

## 8. 创建错误码

| `rc` | 含义 |
|---|---|
| `0` | 成功 |
| `-1` | 实例 ID、驱动或配置无效 |
| `-2` | 实例槽位已经配置，包括已关闭的实例 |
| `-3` | 传输模式不支持 |
| `-4` | 参数或网卡映射不合法 |
| `-5` | UART、SPI 片选或网卡归属冲突 |
| `-6` | 内存、硬件、网络初始化或任务创建失败 |
| `-7` | 旧 AirLink 流程已经初始化或启动 |

Lua 参数类型错误、未知驱动名及部分参数越界会直接抛出参数错误，不一定返回上述错误码。

`-6` 若发生在网卡已部分创建之后，当前实现可能保留槽位，需重启后再配置。

## 9. 使用边界

- 最多两个实例，ID 为 `0`、`1`。
- 推荐当前已验证的“一条 Wi-Fi＋一条蜂窝”组合。
- 两个 UART 实例必须使用不同 UART。
- 共享 SPI 必须使用不同 CS，并正确连接从机 RDY。
- `wlan`、BLE、蜂窝操作按功能选择实例；同类设备的多实例选择不属于本轮验收范围。
- HSPI 已有代码适配，但本轮没有完成 HSPI 实机验收。
- AIR8605 板载 6205 使用主控 UART3；同时连接 780 需要另一条独立连接，不能仅通过创建两个实例共用同一 UART。
- 板级供电、复位及外部看门狗仍需由具体板子的初始化代码处理。已测试 AIR8605 使用 GPIO64 复位、GPIO57 喂外部看门狗，UART 测试时将 SPI2 的 CS4/CS47 拉高。
