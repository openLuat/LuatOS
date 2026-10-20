--[[
@module  rs485
@summary RS485 / UART3 对外通信口（Air8203 工业场景专属）
@version 0.1（框架骨架）
@date    2026.09.28

=== Air8203 的三档接法（子型号第 1/2/3 位） ===
  变体 1（iso485）：隔离式 RS485 —— 板载 CA-IS2092A 隔离收发器
  【图】原理图第 9 页：U491 = CA-IS2092A（16 脚隔离器），3.3V 由 U490 = LP5907MFX-3.3 提供；
        隔离电源外围 L900 2.0uH / CY1 39PF / B491 B492 600ohm 共模电感；
        总线保护 R493/R495 330R、R496 110（终端）、TVS485、F900/F901 保险丝

  变体 2（rs485） ：非隔离 RS485 —— 板载 SIT3485E
  【图】原理图第 2 页：U245 = SIT3485E（8 脚），RE#(2)/DE(3) 并接后由 **GPIO1** 驱动；
        R427/R429 10K 上拉、R428 120 终端、TVS17/TVS18、F203/F204 保险丝；
        图注「对外客户端 IO 支持 3.3V 版本和 5V 版本」

  变体 3（uart）  ：UART3 直出 —— 对外端子就是 3.3V TTL 串口
  （【官网】端子复用关系：485_B/UART_TX 同一端子；485_A/UART_RX 同一端子）

=== 方向控制（本次移植的关键新增点） ===
RS485 是半双工，必须控制收发方向：
  · 非隔离版：【图】RE#/DE 并接 → 单个 GPIO（GPIO1）即可同时控制收发
      - DE=1 且 /RE=1 → 发送允许、接收禁止
      - DE=0 且 /RE=0 → 发送禁止、接收允许
      - 若板上 RE#/DE 已短接（原理图显示并接），则一根线搞定
  · 隔离版：【待核】CA-IS2092A 的 DE/RE 引脚接法

=== 【待核】清单（P0） ===
  a) 485 数据脚落在主控哪个 UART？（非隔离版走 UART_TXD/RXD；UART3 版本另算）
     候选：UART1(PIN17/18, GPIO18/19)、UART2(PIN28/29, GPIO12/13)
     ⚠️ 原理图第 1 页显示 EHV 的 PIN57/58 为 NC，而对外网络名却出现 UART3_TXD/RXD
        → 需图形核对，可能通过 pins 库复用其它管脚
  b) 波特率（工业现场通常 9600/115200，【待核】）
  c) dir_active_high：发送时 DIR 置高还是置低（取决于 RE#/DE 的并接极性与三极管是否反相）
  d) 端子极性：485_A / 485_B 的对应关系（对外 10PIN 连接器 J100）

=== ★★ 当前状态：整体未启用（2026-09-28 现场要求） ===
【已确认 2026-09-28】**先不启动任何 485 的东西** —— 待明确现场接的 485 设备
（协议、波特率、主从角色、寄存器表）之后再开发。

因此本模块当前的行为被收敛为**只打一条日志**：
  · config.RS485_CONFIG.ENABLE = false
  · rs485.init() 只输出提示日志，**不建串口、不注册方向脚、不起接收任务**
  · rs485.send() 因 state.inited 恒为 false 而直接失败（不会误发数据）
  · 云平台命令 rs485_send 仍保留（modules/remote.lua），但会明确回执"功能暂未启用"

⚠️ 下方两处仍需在开发前确认（保留原样，不要凭猜测填）：
  a) 485 数据脚落在主控哪个 UART？波特率多少？（config.RS485_CONFIG.UART / BAUD 仍为 nil）
  b) 方向脚极性 DIR_ACTIVE_HIGH 未标定

=== 设计要点（开发时遵守） ===
  1. 方向切换必须与 tx 严格同步：uart.tx 是异步的，**不能**发完立刻翻转方向，
     否则会截断尾部字节。正确做法是等发送完成回调/或按波特率估算字节时长 + 余量。
     —— 这是 RS485 代码最常见的坑，务必在实现时显式处理。
  2. 隔离版与 UART 版共用同一份收发逻辑，只差"是否操作方向脚"。
  3. 默认只做**透传**；Modbus 从站为可选增强（工业场景常见需求）。
]]

local rs485 = {}

local config = require("config")
local CFG = config.RS485_CONFIG or {}

local state = {
    inited   = false,
    dir_pin  = nil,
    uart_id  = nil,
    tx_cnt   = 0,
    rx_cnt   = 0,
    rx_buf   = nil,
}

-- 发送方向：置为"发送"
local function dir_tx()
    if not state.dir_pin then return end
    local lv = CFG.DIR_ACTIVE_HIGH and 1 or 0
    gpio.set(state.dir_pin, lv)
end

-- 接收方向：置为"接收"
local function dir_rx()
    if not state.dir_pin then return end
    local lv = CFG.DIR_ACTIVE_HIGH and 0 or 1
    gpio.set(state.dir_pin, lv)
end

--[[
初始化 RS485 口。
@return boolean
]]
function rs485.init()
    if state.inited then return true end

    -- ★ 8203 当前状态：485 整体不启用（仅日志提示，不产生任何副作用）
    if CFG.ENABLE == false then
        log.info("rs485", "★ RS485 暂未启用（config.RS485_CONFIG.ENABLE=false）：",
            "先不启动任何 485 功能，待明确现场接的 485 设备（协议/波特率/主从角色）后再开发。",
            "本模块未建串口、未注册方向脚、未起接收任务；",
            "待确认项仍在：UART=", tostring(CFG.UART), " BAUD=", tostring(CFG.BAUD),
            " DIR_PIN=", tostring(CFG.DIR_PIN), "（方向极性亦未标定）")
        return false
    end

    log.info("rs485", "初始化: variant=" .. tostring(CFG.VARIANT)
        .. " uart=" .. tostring(CFG.UART)
        .. " baud=" .. tostring(CFG.BAUD)
        .. " dir_pin=" .. tostring(CFG.DIR_PIN))

    -- 【待核】以下三项确认前不建立串口，避免占用错误 UART 打乱其它外设
    if not CFG.UART or not CFG.BAUD then
        log.warn("rs485", "★ RS485 参数未确认（uart/baud 为 nil），本模块暂不建立串口。",
            "待确认：① 485 数据脚所在 UART ② 波特率 ③ 方向脚极性 ④ 端子 A/B 对应",
            "—— 依据：【图】第 2 页（非隔离 SIT3485E，方向=GPIO1）/ 第 9 页（隔离 CA-IS2092A）")
        return false
    end

    state.uart_id = CFG.UART
    uart.setup(state.uart_id, CFG.BAUD)

    -- 方向脚（变体 3 为 UART 直出，无方向控制）
    if CFG.VARIANT ~= "uart" and CFG.DIR_MANUAL and CFG.DIR_PIN then
        state.dir_pin = CFG.DIR_PIN
        gpio.debounce(state.dir_pin, 0)
        gpio.setup(state.dir_pin, 0)   -- 初始=接收
        dir_rx()
    end

    state.inited = true
    log.info("rs485", "RS485 初始化完成")

    -- 接收任务（常驻）
    sys.taskInit(function()
        local buf = zbuff.create(1024)
        while true do
            if uart.rx(state.uart_id, buf) > 0 then
                local data = buf:toStr(0, buf:used())
                buf:del()
                state.rx_cnt = state.rx_cnt + 1
                -- TODO【待实现】按业务分发：
                --   · 透传模式 → sys.publish("RS485_DATA", data)
                --   · Modbus 从站 → 交给 modbus 解析
                sys.publish("RS485_DATA", data)
            else
                sys.wait(50)
            end
        end
    end)

    return true
end

--[[
发送数据（自动控制方向）。

★ 关键：dir_tx → tx → 等发送完成 → dir_rx。
  不可在 uart.tx 之后立即 dir_rx，否则尾部字节会被截断。
  等待时长 = 字节数 × (10bit/baud) × 1000 ms + 余量，或使用官方发送完成回调。

@param string data
@return boolean
]]
function rs485.send(data)
    if not state.inited or not data or #data == 0 then return false end

    dir_tx()
    uart.tx(state.uart_id, data)

    -- 估算发送耗时并等待（10 bit/byte：1 起始 + 8 数据 + 1 停止）
    local baud = CFG.BAUD or 9600
    local wait_ms = math.ceil(#data * 10 * 1000 / baud) + 5
    sys.wait(wait_ms)

    dir_rx()
    state.tx_cnt = state.tx_cnt + 1
    return true
end

--[[
注册接收回调（业务层用；也可直接订阅 "RS485_DATA" 事件）
]]
function rs485.on_data(cb)
    sys.subscribe("RS485_DATA", cb)
end

function rs485.get_status()
    return {
        inited  = state.inited,
        variant = CFG.VARIANT,
        dir_pin = state.dir_pin,
        uart    = state.uart_id,
        tx_cnt  = state.tx_cnt,
        rx_cnt  = state.rx_cnt,
    }
end

return rs485
