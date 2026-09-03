--[[
@module tools
@summary 工具模块
@version 2.2
@date    2026.09.03
@author  孟伟
@usage
工具模块，当前职责为 LED 状态机（2026.09.03 规则重写）：
- 亮/灭（任一满足即亮，全不满足即灭）：开机前 60s / GNSS 关→开切换后 10s / 充电中
- 常亮/闪烁（三个条件全部成立才常亮，任一不满足即 500ms 亮/500ms 灭闪烁）：
  ① 跟服务器通信正常（云链路处于连接状态，create.is_connected）
  ② 收到过服务器回复（600s 内收到过对设备上行的应答：鉴权回复17/上报回应18）
  ③ 收到的回复是成功响应（应答值为 ok/success 前缀）
- 颜色：充电中→黄灯；不充电→绿灯
- 充电器在位状态由 battery 模块轮询 YHM2712A 充电 IC 后经 CHARGING_START/STOP 事件驱动

004.000.030 清理：删除旧 LED 兼容接口（greenLed_* 等）、电源状态管理（get_vbus_state/
update_power_state 等）、业务状态（device_mode/position_active_report）、调试接口
get_all_state、计步编码 encode_step —— 均随 unactive_mode 删除与 GNSS 三态上报重构后无调用者。

004.000.034 重写：删除手动开灯接口（led_set_manual/led_server_rx，remote.open_light 命令
因调用处有存在性保护而不受影响，仅不再控制灯）；常亮判定由"600s 内收到过下行"改为
"通信正常 + 600s 内收到过成功回复"两条件；颜色由"充满绿"改为"不充电即绿"。
]]

local tools = {}

local config = require("config")

-- LED引脚定义（8202G：GPIO26 绿灯、GPIO27 黄灯）
local LED_PINS = {
    green  = config.HARDWARE_PINS.GREEN_LED    -- 26 绿灯
    ,yellow = config.HARDWARE_PINS.YELLOW_LED  -- 27 黄灯
}

-- LED 状态机参数
local LED_BOOT_ON_SEC    = 60     -- 开机前 60 秒亮（告知用户设备存活）
local LED_GNSS_ON_SEC    = 10     -- GNSS 关→开切换后亮 10 秒
local LED_REPLY_OK_SEC   = 600    -- 600 秒内收到过服务器回复 → 满足"收到过回复"条件，否则闪烁
local LED_BLINK_MS       = 500    -- 闪烁半周期：500ms 亮 / 500ms 灭

-- AirCloud 协议中对设备"上行报文"的应答字段编号（lib/excloud.lua FIELD_MEANINGS）
-- 鉴权回复(17)/上报回应(18)；其余下行（远程指令等）不属于"服务器回复"
local FIELD_AUTH_RESPONSE   = 17
local FIELD_REPORT_RESPONSE = 18

-- LED是否已初始化（惰性初始化兜底）
local led_inited = false

-- LED 状态机
local led = {
    boot_time = nil,        -- init_led 时刻（os.time），开机亮灯窗口基准
    gnss_on_until = 0,      -- GNSS 关→开切换亮灯截止时间戳
    last_reply_time = 0,    -- 最近一次收到服务器回复（17/18）的时间戳
    last_reply_ok = false,  -- 最近一次服务器回复是否为成功响应（ok/success）
    blink_phase = false,    -- 闪烁相位
    timer = nil,            -- 500ms 刷新定时器
}

-- 应答 value 是否为"成功"（AirCloud 协议：成功值为 ok/success 前缀，忽略大小写/空白）
-- 与 lib/excloud.lua 的 is_success_reply 同语义（lib 不可引用细节，此处独立实现）
local function is_success_reply(v)
    if v == nil then
        return false
    end
    local s = tostring(v):lower():gsub("%s", "")
    return s:match("^ok") ~= nil or s:match("^success") ~= nil
end

-- 电源状态（充电器在位状态由 battery 模块轮询 YHM2712A 充电IC 后，经 CHARGING_START/STOP 事件更新）
local device_state = {
    vbus_state = 0,    -- 1=充电器在位（含充满未拔），0=不在位
}

-- 云连接状态查询（惰性加载 create 模块，require 有缓存、每 500ms 轮询开销可忽略）
local function cloud_connected()
    local ok, create = pcall(require, "create")
    if ok and create and create.is_connected then
        return create.is_connected() and true or false
    end
    return false
end

-- LED 状态机核心：每 500ms 由定时器调用，各事件也触发立即刷新
-- 规则（用户确认，2026.09.03）：
--   亮：开机60s内 / GNSS关→开切换后10s内 / 充电中（任一满足即亮，全不满足即灭）
--   常亮/闪烁：① 通信正常(云连接) ② 600s内收到过服务器回复(17/18) ③ 回复是成功响应(ok/success)
--              三条全部成立→常亮；任一不满足→500ms亮/500ms灭
--   颜色：充电中→黄；不充电→绿
-- 充电判定：本硬件无 VBUS 检测脚（GPIO 直读已失效），充电器在位状态由
--   battery 模块轮询 YHM2712A 充电IC（exs_yhm2712a.status）得出，
--   经 CHARGING_START/CHARGING_STOP 事件更新 device_state.vbus_state
local function led_refresh()
    if not led_inited then return end
    local now = os.time()

    -- 1) 亮/灭判定（充电状态来自 battery 轮询缓存，开机即插着充电器时首次轮询后即点亮）
    local charging = (device_state.vbus_state == 1)
    local lit = charging
        or (led.boot_time and (now - led.boot_time) < LED_BOOT_ON_SEC)  -- 开机60s
        or (now < led.gnss_on_until)                                    -- GNSS切换10s

    -- 2) 常亮/闪烁判定（三个条件全部成立才常亮）
    local connected = cloud_connected()                                             -- ① 通信正常
    local replied = led.last_reply_time > 0
        and (now - led.last_reply_time) <= LED_REPLY_OK_SEC                         -- ② 收到过回复
    local steady = connected and replied and led.last_reply_ok                      -- ③ 回复成功

    local on
    if not lit then
        on = false
    elseif steady then
        on = true
    else
        led.blink_phase = not led.blink_phase
        on = led.blink_phase
    end

    -- 3) 颜色判定：充电中→黄，不充电→绿
    local color = charging and "yellow" or "green"

    -- 4) 输出到引脚（任一时刻最多亮一盏）
    gpio.set(LED_PINS.green,  (on and color == "green")  and 1 or 0)
    gpio.set(LED_PINS.yellow, (on and color == "yellow") and 1 or 0)
end

-- 初始化LED：设置为输出模式并关闭所有LED，记录开机时间并启动状态机定时器
function tools.init_led()
    log.info("[tools]", "初始化LED状态机")
    for _, pin in pairs(LED_PINS) do
        if pin then
            gpio.setup(pin, 0)
            gpio.set(pin, 0)
        end
    end
    led_inited = true
    led.boot_time = os.time()
    led.blink_phase = false
    if not led.timer then
        led.timer = sys.timerLoopStart(led_refresh, LED_BLINK_MS)
    end
    led_refresh()
end

-- ============================================
-- LED 状态机对外接口
-- ============================================

-- GNSS 关→开切换：亮灯 10 秒（由 active_mode 主循环在切换瞬间调用）
function tools.led_gnss_switched_on()
    led.gnss_on_until = os.time() + LED_GNSS_ON_SEC
    led_refresh()
    log.info("[tools]", "GNSS开启，LED亮10秒")
end

-- 订阅服务器回复：REMOTE_COMMAND 覆盖一切下行，其中 AirCloud 通道解析出的
-- 鉴权回复(17)/上报回应(18)（raw 为 TLV 表，field 为 17/18）才是对设备"上行报文"的应答；
-- 远程指令（raw 为 JSON 字符串）不属于"服务器回复"，不参与常亮判定。
-- 只有成功回复刷新时间戳；失败回复立即置 last_reply_ok=false（下一拍进入闪烁）
sys.subscribe("REMOTE_COMMAND", function(msg)
    local raw = msg and msg.raw
    if type(raw) ~= "table" or (raw.field ~= FIELD_AUTH_RESPONSE and raw.field ~= FIELD_REPORT_RESPONSE) then
        return
    end
    led.last_reply_time = os.time()
    led.last_reply_ok = is_success_reply(raw.value)
    log.info("[tools]", "收到服务器回复", led.last_reply_ok and "成功" or "失败", "value", tostring(raw.value))
    led_refresh()
end)

-- 订阅充电状态变化事件（由 battery 模块轮询 YHM2712A 充电IC 后发布）：更新内部缓存并立即刷新 LED
-- （充电器在位状态由 battery 后台任务默认 30s 轮询一次，插拔检测延迟上限即为此值）
sys.subscribe("CHARGING_START", function()
    device_state.vbus_state = 1
    led_refresh()
end)
sys.subscribe("CHARGING_STOP", function()
    device_state.vbus_state = 0
    led_refresh()
end)

return tools
