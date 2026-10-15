--[[
@module  ble_link
@summary BLE 链路（MS1631C）—— 看门狗 / 唤醒源 / 海外 APN 配置口
@version 0.1（框架骨架）
@date    2026.09.28

=== Air8203 为什么有独立的 BLE 芯片 ===
【官网-8203 产品页】原文：「Air8202 使用 Air153C 做看门狗，Air8203 使用 BLE 芯片来做，
一方面可以 BLE 芯片可以做看门狗，一方面也可以在 Air8203 出海外地区时配置 APN 使用」

→ MS1631C 在 8203 上承担三件事：
   ① **硬件看门狗**：主控不按时喂 → 拉高 → 反相 → 拉低主控 RESET_N   ← 见 wdt.lua（P0）
   ② **BLE 通信**   ：与手机保持连接，断连或收到数据时反向唤醒主控
   ③ **APN 配置口** ：海外版本（U/N 系列）通过它配置 APN

=== 硬件事实（【图】原理图第 6 页） ===
  · U461 = MS1631C-3D10A
  · 晶振 X460 = 26MHz（2016 封装，9pF）
  · 天线：J460（IPEX 一代，外接）**或** J461（陶瓷贴片 1608）二选一
  · 引脚：1 PA01/TXD/SCL/SWDIO  3 PA00/RXD/SDA/SWCLK  8 RSTN/PA19  10 PA14  9 PA17
  · 图注三条（原文）：
      ① 「当主控发 AT 指令给 MS1631C 得不到响应时，通过拉低此管脚可复位 BLE 芯片」
         → 即 RESET_BLE 是"逃生通道"，AT 通道死了还能硬复位它
      ② 「当主控进入低功耗模式时，Air5101 与手机或其它蓝牙设备保持连接」
         （注：图注此处写 Air5101，疑为笔误，应为 MS1631C 或 Air510W 系列命名混用 —— 【待核】）
      ③ 「当蓝牙连接断开或收到数据时，可通过此管脚唤醒主控以恢复主控的处理数据功能」
         → BLE_WAKEUP0 是 BLE → 主控 的唤醒线

=== 【待核】清单（P0/P1） ===
  a) 【P0】AT 串口落在主控哪个 UART + 波特率（与喂狗机制强相关，见 wdt.lua）
  b) 【P1】RESET_BLE 对应主控 GPIO 号
  c) 【P1】BLE_WAKEUP0 对应主控哪个 WAKEUP 脚（候选：WAKEUP0/PIN101，或 GPIO20）
  d) 【P1】MS1631C 的 AT 指令集（合宙是否提供该芯片的扩展库？当前检索未找到 LuatOS 官方库）
     → 若官方无库，本模块需自行封装 AT 通道；建议先向合宙确认是否已有扩展库/示例
  e) 【P2】BLE 透传模式与服务端协议（是否需要把 BLE 收到的数据转发到 AirCloud）

=== 实现策略（分两步走） ===
  第 1 步（本框架）：只做 UART 建链 + AT 探测，确认芯片在线与波特率
  第 2 步（待 a~d 确认后）：接入喂狗（wdt.lua）、唤醒回调、APN 配置
]]

local ble_link = {}

local config = require("config")
local CFG = config.BOARD and config.BOARD.ble or {}

local state = {
    inited  = false,
    uart_id = nil,
    online  = false,
    rx_buf  = nil,
}

--[[
初始化 BLE 链路。
★ 时序：必须在 wdt.init() 之后、sim_slot.init() 之前调用（见 main.lua）——
  因为喂狗通道很可能就是这条 UART（【待核】），二者共用必须由 BLE 先建链。
]]
function ble_link.init()
    if state.inited then return true end

    log.info("ble_link", "初始化 BLE 链路: chip=" .. tostring(CFG.chip)
        .. " uart=" .. tostring(CFG.uart)
        .. " baud=" .. tostring(CFG.baud)
        .. " reset=" .. tostring(CFG.reset_pin)
        .. " wakeup=" .. tostring(CFG.wakeup_pin))

    if not CFG.uart or not CFG.baud then
        log.warn("ble_link", "★ BLE 串口参数未确认（uart/baud 为 nil），本模块暂不建立串口。",
            "待确认：① AT 串口所在 UART ② 波特率 ③ RESET_BLE 引脚 ④ BLE_WAKEUP0 引脚 ⑤ AT 指令集",
            "—— 依据：【图】第 6 页 U461 = MS1631C-3D10A（26MHz 晶振，IPEX/陶瓷天线二选一）")
        return false
    end

    state.uart_id = CFG.uart
    uart.setup(state.uart_id, CFG.baud)

    -- RESET_BLE：逃生复位线（AT 无响应时拉低复位）
    if CFG.reset_pin then
        gpio.setup(CFG.reset_pin, 1)   -- 常态拉高（不复位）
        log.info("ble_link", "RESET_BLE = GPIO" .. CFG.reset_pin .. "（常态高，拉低即复位 BLE 芯片）")
    end

    -- BLE_WAKEUP0：BLE → 主控 唤醒线（主控休眠时靠它被唤醒）
    if CFG.wakeup_pin then
        log.info("ble_link", "BLE_WAKEUP0 = GPIO" .. CFG.wakeup_pin .. "（BLE 断连/收数据时唤醒主控）")
        -- TODO【待实现】注册唤醒中断（形态取决于该脚是否为 WAKEUP 类）
    end

    state.inited = true
    log.info("ble_link", "BLE 链路初始化完成")
    return true
end

--[[
发送 AT 指令（带等待与超时）。

@param string cmd      指令内容（不含 CRLF）
@param number timeout  等待响应的毫秒数
@return boolean, string|nil
]]
function ble_link.at(cmd, timeout)
    if not state.inited then return false, "BLE 未初始化" end
    uart.tx(state.uart_id, cmd .. "\r\n")
    local ok, resp = sys.waitUntil("BLE_AT_RESP", timeout or 1000)
    if ok then return true, resp end
    return false, nil
end

--[[
硬复位 BLE 芯片（AT 通道无响应时的逃生通道）。
【图】图注：「当主控发 AT 指令给 MS1631C 得不到响应时，通过拉低此管脚可复位 BLE 芯片」
]]
function ble_link.reset()
    if not CFG.reset_pin then return false, "RESET_BLE 引脚未确认" end
    log.warn("ble_link", "BLE 无响应 → 硬复位（拉低 GPIO" .. CFG.reset_pin .. "）")
    gpio.set(CFG.reset_pin, 0)
    sys.wait(100)
    gpio.set(CFG.reset_pin, 1)
    state.online = false
    return true
end

function ble_link.is_online()
    return state.online
end

function ble_link.get_status()
    return {
        inited  = state.inited,
        online  = state.online,
        chip    = CFG.chip,
        uart    = state.uart_id,
    }
end

return ble_link
