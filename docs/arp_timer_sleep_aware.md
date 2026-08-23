# ARP 1000ms 定时器低功耗化改造 / netdrv.arpSleep API

> 适用：基于 `net_lwip2` adapter + `netdrv` 框架的 BSP（Air8000A/U/N/AB/W/D/DB/T 等），目标是消除 `pm.power(pm.WORK_MODE, 1)` 进入 Slp1 后由 ARP 1000ms 定时器（`etharp_tmr`）带来的周期性唤醒功耗。

---

## 1. 背景与问题

### 1.1 现象

Air8000A 系列模组进入低功耗模式后，预期功耗 ~40-70uA，但实测有持续 1Hz 的电流脉冲。串口/EPAT 日志可观察到：

```
03:0048:07:06464  D/net arp_pm: TICK etharp_tmr
03:0148:07:05760  D/net arp_pm: TICK etharp_tmr
03:0248:07:05440  D/net arp_pm: TICK etharp_tmr
... 每秒一次, 无限持续 ...
```

### 1.2 根因

`net_lwip2.c` 为每个 netif 维护了一个 1000ms 周期的 ARP timer（`prvlwip.arp_timer`），作用是周期性扫描 ARP 表 + 重传 ARP 请求。当编译选项是 `LUAT_NETDRV_ARP_TIMER_ALWAYS_ON` 时它永久 1Hz 跑；当编译为 on-demand 时它本应在「不需要 ARP」时停止，但：

- WIFI/CH390/AP 任一 netif 处于 `link_up` 且 `gw_mac` 尚未解析时，定时器都会启动；
- 进入低功耗前没有任何代码主动告诉 net_lwip2「我要睡了，把定时器停掉」。

### 1.3 多次尝试的失败路径

| 方案 | 结果 |
|---|---|
| 在 `luat_lib_pm.c` 的 `l_pm_power_ctrl` 加 hook：`id==LUAT_PM_POWER_WORK_MODE && onoff!=0` 时调用 `net_lwip2_arp_timer_sleep_prepare()` | 失败。Air8000 的 `pm.power(WORK_MODE,1)` 编译宏走 `LUAT_USE_DRV_PM` 分支，最初 hook 放在 `#else` 内，从未生效。 |
| 把 hook 移到 `#ifdef LUAT_USE_DRV_PM` **外** | 失败。Air8000 实际把 `pm.power(WORK_MODE,1)` 重定向到 `pm.request(Slp1)` 路径（日志只看到 `I/pm request mode=Slp1`，看不到我们注册的 `arp_pm: pm.power(...)` 行），完全绕过 `l_pm_power_ctrl`。 |
| 同时在 `l_pm_request` 加 hook | 部分固件构建仍未触发。该路径在 SoC 内部由 drv_pm 框架管理，钩子位置和编译条件因平台而异，不可靠。 |
| 用 `netdrv.ctrl(LWIP_ETH, CTRL_UPDOWN, 0)` 让 `LINK_DOWN` 事件触发 `apply_stop` | 在 ETH 场景下有效，但 STA/AP 场景下 WIFI 芯片会被直接掉电，netif 不一定经过标准 LINK_DOWN 事件。 |

### 1.4 最终选择

**抛弃所有 pm 钩子，改用一个显式的 Lua API：`netdrv.arpSleep()` / `netdrv.arpResume()`。** 由低功耗脚本在 `pm.power(WORK_MODE,1)` 之前主动调用，直接把 `EV_LWIP_ARP_TIMER_SLEEP` 事件 post 给 lwip task。完全与 pm 框架解耦。

---

## 2. 系统架构

```
┌──────────────────────────────────────────────────────────┐
│  Lua: drv_lowpower.lua                                   │
│    1. dhcpsrv.stop(_G.eth_dhcpsrv)   关闭 dhcpsrv 协程    │
│    2. netdrv.ctrl(LWIP_ETH, CTRL_UPDOWN, 0)  关 CH390    │
│    3. netdrv.arpSleep()             关闭 ARP timer       │
│    4. pm.power(pm.WORK_MODE, 1)     进入 Slp1            │
└──────────────────────────────────────────────────────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────────────┐
│  C: l_netdrv_arp_sleep (luat_lib_netdrv.c)               │
│    net_lwip2_arp_timer_sleep_prepare()                   │
└──────────────────────────────────────────────────────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────────────┐
│  C: net_lwip2.c                                          │
│    platform_send_event(EV_LWIP_ARP_TIMER_SLEEP)          │
│    └─> lwip task 收到事件                                 │
│        └─> apply_stop()                                   │
│            └─> luat_stop_rtos_timer(arp_timer)            │
│            └─> arp_timer_in_sleep = 1                     │
└──────────────────────────────────────────────────────────┘
```

---

## 3. 改动清单

### 3.1 C 层

| 文件 | 改动 | 必须重编 |
|---|---|---|
| `components/network/adapter_lwip2/net_lwip2.h` | 声明 `net_lwip2_arp_timer_sleep_prepare/wakeup_resume` 等公共 API | ✅ |
| `components/network/adapter_lwip2/net_lwip2.c` | 实现 sleep/resume API + EV_LWIP_ARP_TIMER_SLEEP/RESUME 事件处理；修复 `LINK_STATE` 钩子用 `netif_is_link_up()`（不是 `netif_is_up()`）；`any_adapter_need_arp` 同步加上 link_up 检查 | ✅ |
| `components/network/netdrv/src/luat_netdrv_lwip_etharp.c` | `gw_mac_valid` 通知（STABLE 时置 1, free 时置 0） | ✅ |
| `components/network/netdrv/src/luat_netdrv_ch390h_task.c` | 所有 CH390 处于 `CH390H_STATUS_STOPPED` 时 task 进入 `LUAT_WAIT_FOREVER` 等待，不再 1Hz 心跳；新增 `luat_ch390h_task_wakeup()` | ✅ |
| `components/network/netdrv/src/luat_netdrv_ch390h.c` | `CTRL_UPDOWN=1` 时调用 `luat_ch390h_task_wakeup()` 把 task 从 FOREVER 等待唤醒 | ✅ |
| `components/network/netdrv/binding/luat_lib_netdrv.c` | 新增 Lua API `netdrv.arpSleep()` / `netdrv.arpResume()` | ✅ |

### 3.2 Lua 层

| 文件 | 改动 | 必须重编 |
|---|---|---|
| `script/libs/dhcpsrv.lua` | 新增 `dhcpsrv.stop(srv)` API；`dhcp_task` 加 `srv.stop` 退出条件 | ❌ 刷脚本即可 |
| `module/Air8000/demo/network_routing/wifi_out_ethernet_in_wifi_in/netif_app.lua` | `dhcpsrv.create` 返回值存到 `_G.eth_dhcpsrv` / `_G.ap_dhcpsrv`，供 drv_lowpower 引用 | ❌ |
| `module/Air8000/demo/network_routing/wifi_out_ethernet_in_wifi_in/drv_lowpower.lua` | 休眠前: stop dhcpsrv + CTRL_UPDOWN=0 + `netdrv.arpSleep()`；UART1 唤醒回调: `netdrv.arpResume()` + CTRL_UPDOWN=1 + 重新 create dhcpsrv | ❌ |

---

## 4. 新增 Lua API

### 4.1 `netdrv.arpSleep()`

```lua
-- 进入 pm.power(pm.WORK_MODE, 1) 之前调用
netdrv.arpSleep()
pm.power(pm.WORK_MODE, 1)
```

- **作用**：直接 post `EV_LWIP_ARP_TIMER_SLEEP` 事件给 lwip task，task 收到后立即 stop ARP 1000ms 定时器，并把当前 running 状态保存到 `arp_timer_sleep_saved` 字段以便恢复时判断。
- **返回**：boolean。`true` 表示事件已投递（编译启用了 `LUAT_USE_NETDRV_LWIP_ARP` 且未开 `LUAT_NETDRV_ARP_TIMER_ALWAYS_ON`）；`false` 表示当前固件 ARP timer 是 always-on 模式或未启用，无效。
- **线程安全**：可在任意 task / 协程中调用。

### 4.2 `netdrv.arpResume()`

```lua
-- 唤醒回调里调用
netdrv.arpResume()
```

- **作用**：post `EV_LWIP_ARP_TIMER_RESUME` 事件给 lwip task。task 收到后清 `arp_timer_in_sleep` 标志位，然后检查 `arp_timer_sleep_saved` 或 `any_adapter_need_arp()`，若仍有 adapter 需要 ARP（admin_up + link_up + gw_mac 未解析），重新启动定时器；否则保持停止。
- **返回**：boolean，同上。

---

## 5. 关键 C 实现要点

### 5.1 `LINK_STATE` 事件钩子修复

```c
// 文件: components/network/adapter_lwip2/net_lwip2.c
case EV_LWIP_NETIF_LINK_STATE:
{
    uint8_t idx = event.Param3;
#ifndef LUAT_NETDRV_ARP_TIMER_ALWAYS_ON
    // 注意: 这里是 link state 事件, 必须用 netif_is_link_up() 判断 link 层状态,
    // 不能用 netif_is_up() (它是 admin state). CH390 CTRL_UPDOWN=0 只调
    // netif_set_link_down, 不动 admin state, 误用 netif_is_up 会导致 link down
    // 被错判为 LINK_UP 而重新启动 ARP 定时器.
    if (prvlwip.lwip_netif[idx] != NULL
        && netif_is_up(prvlwip.lwip_netif[idx])
        && netif_is_link_up(prvlwip.lwip_netif[idx])) {
        // LINK_UP 分支
        prvlwip.gw_mac_valid[idx] = 0;
        net_lwip2_arp_timer_apply_start();
    } else {
        // LINK_DOWN 分支
        prvlwip.gw_mac_valid[idx] = 0;
        if (!net_lwip2_any_adapter_need_arp()) {
            net_lwip2_arp_timer_apply_stop();
        }
    }
#endif
    net_lwip2_check_network_ready(idx);
}
break;
```

### 5.2 `any_adapter_need_arp` 充要条件

```c
static int net_lwip2_any_adapter_need_arp(void)
{
    uint8_t i;
    for (i = 0; i < NW_ADAPTER_INDEX_LWIP_NETIF_QTY; i++) {
        if (prvlwip.lwip_netif[i] != NULL
            && netif_is_up(prvlwip.lwip_netif[i])
            && netif_is_link_up(prvlwip.lwip_netif[i])   // 必须 link_up
            && prvlwip.gw_mac_valid[i] == 0) {
            return 1;
        }
    }
    return 0;
}
```

### 5.3 CH390 task FOREVER 等待

```c
// 文件: components/network/netdrv/src/luat_netdrv_ch390h_task.c
static void ch390_task_main(void* args) {
    // ...
    while (1) {
        // ...
        int any_active = 0;
        for (size_t i = 0; i < MAX_CH390H_NUM; i++) {
            if (ch390h_drvs[i] != NULL
                && ch390h_drvs[i]->status != CH390H_STATUS_STOPPED) {
                any_active = 1;
                break;
            }
        }
        if (!any_active) {
            // 所有 CH390 都 STOPPED, 不再 1Hz 心跳, 直到收到消息(IRQ 或 CTRL_UPDOWN=1)
            ret = task_wait_msg(LUAT_WAIT_FOREVER);
        }
        else if (s_ch390h_mode == 0) {
            ret = task_wait_msg(5);    // PULL: 5ms
        }
        else {
            ret = task_wait_msg(1000); // IRQ: 1Hz 心跳
        }
    }
}

void luat_ch390h_task_wakeup(void) {
    if (qt == NULL) return;
    uint32_t len = 0;
    luat_rtos_queue_get_cnt(qt, &len);
    if (len > 4) return;
    pkg_evt_t evt = { .id = 2 };
    luat_rtos_queue_send(qt, &evt, sizeof(pkg_evt_t), 0);
}
```

### 5.4 `netdrv.arpSleep` Lua binding

```c
// 文件: components/network/netdrv/binding/luat_lib_netdrv.c
static int l_netdrv_arp_sleep(lua_State *L) {
#if defined(LUAT_USE_NETDRV_LWIP_ARP) && !defined(LUAT_NETDRV_ARP_TIMER_ALWAYS_ON)
    net_lwip2_arp_timer_sleep_prepare();
    lua_pushboolean(L, 1);
#else
    lua_pushboolean(L, 0);
#endif
    return 1;
}

// 注册:
{ "arpSleep",       ROREG_FUNC(l_netdrv_arp_sleep)},
{ "arpResume",      ROREG_FUNC(l_netdrv_arp_resume)},
```

---

## 6. 业务侧使用模板

### 6.1 应用脚本（暴露 dhcpsrv 句柄）

```lua
-- netif_app.lua
local function wifi_eth_setup()
    -- ...
    -- 用全局变量暴露给低功耗模块, 进入休眠前会调用 dhcpsrv.stop(eth_dhcpsrv)
    _G.eth_dhcpsrv = dhcpsrv.create({ adapter = socket.LWIP_ETH })
end

local function wifi_sta_ap_setup()
    -- ...
    _G.ap_dhcpsrv = dhcpsrv.create(dhcpsrv_opts)
end
```

### 6.2 低功耗脚本（关闭顺序）

```lua
-- drv_lowpower.lua 在 pm.power(pm.WORK_MODE, 1) 之前

-- 1) 关 dhcpsrv 协程 (消除 1Hz sys.waitUntil 唤醒)
if dhcpsrv and dhcpsrv.stop and _G.eth_dhcpsrv then
    dhcpsrv.stop(_G.eth_dhcpsrv)
    _G.eth_dhcpsrv = nil
end
if dhcpsrv and dhcpsrv.stop and _G.ap_dhcpsrv then
    dhcpsrv.stop(_G.ap_dhcpsrv)
    _G.ap_dhcpsrv = nil
end

-- 2) 关 CH390 PHY + 让 ch390_task 进入 FOREVER 等待
if netdrv and netdrv.CTRL_UPDOWN and socket.adapter and socket.adapter(socket.LWIP_ETH) then
    pcall(netdrv.ctrl, socket.LWIP_ETH, netdrv.CTRL_UPDOWN, 0)
end

-- 3) 关 ARP 1000ms 定时器
if netdrv and netdrv.arpSleep then
    netdrv.arpSleep()
end

-- 4) 进入低功耗
pm.power(pm.WORK_MODE, 1)
```

### 6.3 唤醒回调（恢复顺序）

```lua
local function uart1_wakeup_read(_, len)
    if len == -1 then
        pm.power(pm.WORK_MODE, 0)

        -- 1) 恢复 ARP 定时器 (内部判断是否真的需要启动)
        if netdrv and netdrv.arpResume then
            netdrv.arpResume()
        end
        -- 2) 重启 CH390 PHY + task
        if netdrv and netdrv.CTRL_UPDOWN then
            pcall(netdrv.ctrl, socket.LWIP_ETH, netdrv.CTRL_UPDOWN, 1)
        end
        -- 3) 重建 dhcpsrv (stop 是一次性的)
        if dhcpsrv and dhcpsrv.create and not _G.eth_dhcpsrv then
            _G.eth_dhcpsrv = dhcpsrv.create({adapter = socket.LWIP_ETH})
        end

        uart.write(1, "lowpower wakeup\r\n")
    end
    -- ...
end
```

---

## 7. 验证标准

### 7.1 重编 BSP（不能只刷脚本）

```powershell
# 在 bsp/Air8000 目录下
xmake -y
# 烧入新的 .soc
```

判断标准：开机日志里必须看到这一行说明 C 改动已编入：

```
I/net arp_pm: INIT adapter=2 on-demand mode, timer created (stopped)
```

### 7.2 进入休眠期望日志

```
I/user.lowpower_task enter
I/user.drv_lowpower stop ap dhcpsrv
I/user.dhcpsrv dhcp_task exit, adapter 3
I/user.drv_lowpower ch390 skip CTRL_UPDOWN=0 (LWIP_ETH not present)
I/user.drv_lowpower netdrv.arpSleep() -> stop ARP 1000ms timer
I/net arp_pm: API sleep_prepare -> post EV_SLEEP
I/net arp_pm: EVENT SLEEP saved=1 running=1
I/net arp_pm: apply_stop running=1 -> stop
I/pm request mode=Slp1, prev=Slp1
（之后串口不再出现 D/net arp_pm: TICK etharp_tmr）
```

### 7.3 唤醒期望日志

```
I/pm wakeup
I/net arp_pm: API wakeup_resume -> post EV_RESUME
I/net arp_pm: EVENT RESUME saved=1 in_sleep=1
I/net arp_pm: apply_start running=0 in_sleep=0 -> start 1000ms
```

---

## 8. 排障 checklist

| 现象 | 可能原因 | 排查方法 |
|---|---|---|
| 看不到 `netdrv.arpSleep()` 日志 | Lua 脚本未更新 | 重新 download script |
| 看到 Lua 日志但没 `API sleep_prepare` | C 改动没编入 | 必须重编 BSP，不能只刷脚本 |
| 看到 `apply_stop` 但 TICK 仍在 | 多个 lwip task 实例 / timer 二次注册 | 抓 `INIT` 日志确认初始化次数 |
| `not such netdrv 4` 警告 | CH390 没初始化 | 检查 `wifi_eth_setup()` 是否被调用 |
| `apply_start skip running=1 in_sleep=0` 之后又出现 TICK | LINK_UP/DOWN 误判 | 确认 net_lwip2.c 用的是 `netif_is_link_up()` 不是 `netif_is_up()` |
| 唤醒后 `arpResume` 后没自动启动 timer | `any_adapter_need_arp` 返回 false | 正常，等业务流量触发 SET_IP/LINK_UP 时会自启 |
| WIFI STA 仍 1Hz 唤醒 | LWIP_DHCP `dhcp_fine_tmr` 500ms / `dhcp_coarse_tmr` 60s | 改用静态 IP 或在 lwipopts.h 关 LWIP_DHCP |
| 仍有 10Hz 唤醒 | `LWIP_IGMP=1` (`igmp_tmr` 100ms) 或 `LWIP_IPV6_MLD=1` | 在 BSP lwipopts.h 设为 0 |

---

## 9. 其他功耗杀手提醒

`netdrv.arpSleep()` 只解决 ARP 1000ms 定时器。要达到最低功耗还需注意：

1. **LWIP_DHCP**：500ms / 60s 周期，必杀。静态 IP 或编译关闭。
2. **LWIP_IGMP / LWIP_IPV6_MLD**：100ms 周期，致命。`lwipopts.h` 设为 0。
3. **CH390 PULL 模式**：5ms 轮询。必须接 INT 脚走 IRQ 模式。
4. **AGPIO 高电平 + 外部下拉电阻**：每 100K 下拉 ~33uA。
5. **GNSS / GSensor 电源开关 (GPIO24)**：拉低省 88uA。
6. **WIFI 芯片 (GPIO23)**：`pm.power(pm.WIFI, 0)` 或 `gpio.setup(23, nil, gpio.PULLDOWN)` 省 42uA。
7. **dhcpsrv.lua 协程**：1Hz `sys.waitUntil`，用 `dhcpsrv.stop(srv)` 关掉。
8. **CH390 task 1Hz 心跳**：用 `netdrv.ctrl(LWIP_ETH, CTRL_UPDOWN, 0)` 让 task 进 FOREVER 等待。

---

## 10. 历史决策记录

| 日期 | 决策 | 原因 |
|---|---|---|
| 2026-06-23 | 在 `luat_lib_pm.c` 加 sleep hook | 最初方案，认为 `pm.power(WORK_MODE,1)` 会经过 `l_pm_power_ctrl` |
| 2026-06-23 | hook 移到 `#ifdef LUAT_USE_DRV_PM` 外 | 发现 Air8000 走 DRV_PM 分支，hook 被跳过 |
| 2026-06-24 | 修复 `EV_LWIP_NETIF_LINK_STATE` 用 `netif_is_link_up()` | 发现 `CTRL_UPDOWN=0` 时 link_down 被错判为 LINK_UP |
| 2026-06-24 | 抛弃 pm hook，改用 `netdrv.arpSleep()` Lua API | 发现 Air8000 `pm.power(WORK_MODE,1)` 实际走 `pm.request(Slp1)` 路径，绕过所有 pm 钩子 |

---

## 11. 相关文件索引

- 内核 ARP 定时器实现: [components/network/adapter_lwip2/net_lwip2.c](../components/network/adapter_lwip2/net_lwip2.c)
- ARP 定时器公共 API: [components/network/adapter_lwip2/net_lwip2.h](../components/network/adapter_lwip2/net_lwip2.h)
- gw_mac 通知: [components/network/netdrv/src/luat_netdrv_lwip_etharp.c](../components/network/netdrv/src/luat_netdrv_lwip_etharp.c)
- CH390 task: [components/network/netdrv/src/luat_netdrv_ch390h_task.c](../components/network/netdrv/src/luat_netdrv_ch390h_task.c)
- CH390 控制: [components/network/netdrv/src/luat_netdrv_ch390h.c](../components/network/netdrv/src/luat_netdrv_ch390h.c)
- netdrv Lua binding: [components/network/netdrv/binding/luat_lib_netdrv.c](../components/network/netdrv/binding/luat_lib_netdrv.c)
- dhcpsrv: [script/libs/dhcpsrv.lua](../script/libs/dhcpsrv.lua)
- 示例 demo: [module/Air8000/demo/network_routing/wifi_out_ethernet_in_wifi_in/](../module/Air8000/demo/network_routing/wifi_out_ethernet_in_wifi_in/)
