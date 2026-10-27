-- @module  board_hw
-- @summary 板级资源管理（Air780EPM 方案）
-- @version 001.000.000
-- @date    2026.10.27
-- @author  OpenLuat
-- @BSD License
--[[
职责：集中管理板载资源，业务模块（meter_app / aircloud_app）不再直接摆弄引脚。

资源表：
  RS485        串口2，硬件自动换向（无需方向脚）
  GPIO25       485 芯片可控电源，高电平供电          → 上电即拉高
  GPIO23       RS485 EN / 方向脚（收发器 DE+RE）      → 交 uart.setup 硬件自动换向，勿当 GPIO 拉高
  GPIO22       运放芯片可控电源，高电平启动模拟量检测 → 默认关，按需开
  GPIO27       NET LED，高电平亮                      → 默认闪烁，联网/采集正常转常亮
  GPIO30       Reload 按键，输入上拉，按下接 GND      → 短按/长按事件
  GPIO28       硬件看门狗（exair153x_wdt 扩展库）      → init{wdt_pin=28, auto_feed_period_s=150}
  GPIO24       可控电源输出                           → 默认关，按需开
  GPIO20/21    输入 1 / 输入 2（干接点/电平输入）
  ADC2         供电电压 = ADC电压 × 1033000 / 33000（最大 36V）
  ADC0         模拟量输入1 电压 = ADC电压 × 103300 / 3300（最大 36V）
  ADC1         模拟量输入2 电流 = ADC电压 / 51

注意：pm.ioVol(IOVOL_ALL_GPIO, 3300) 必须在所有 UART/GPIO 初始化之前调用，
      否则先初始化的引脚副输出电平会停在默认值。
]]

local M = {}

local exair153x_wdt = require "exair153x_wdt" -- Air153C/Air153D 外置硬件看门狗扩展库

-- ==================== 引脚表 ====================
local PIN = {
    RS485_PWR  = 25, -- 485 芯片可控电源，高=供电
    RS485_EN   = 23, -- RS485 EN / 方向脚（部分硬件版本需要）
    OPAMP_PWR  = 22, -- 运放芯片可控电源，高=启动模拟量检测
    NET_LED    = 27, -- 网络指示灯，高=亮
    RELOAD_KEY = 30, -- Reload 按键，输入上拉，按下接 GND
    WDT        = 28, -- 硬件看门狗（默认没贴）
    PWR_OUT    = 24, -- 可控电源输出
    IN1        = 20, -- 输入 1
    IN2        = 21, -- 输入 2
}
M.PIN = PIN

-- ==================== ADC 通道 ====================
local ADC = {
    SUPPLY = 2, -- 供电电压采集（分压比 1033000/33000）
    AIN1   = 0, -- 模拟量输入1（分压比 103300/3300）
    AIN2   = 1, -- 模拟量输入2（电流，ADC电压/51）
}
M.ADC = ADC

-- ==================== 可调参数 ====================
local CFG = {
    wtd_feed_s   = 150,    -- 喂狗周期 s（建议 150s）
    adc_period   = 10000,  -- ADC 采样周期 ms
    key_long_ms  = 3000,   -- Reload 长按判定 ms
    led_blink_ms = 500,    -- 闪烁半周期 ms
}
M.CFG = CFG

-- ==================== 状态 ====================
local inited   = false
local led_mode = "blink" -- "blink" | "on" | "off"
local hw_data  = { vbat = 0, ain1 = 0, ain2 = 0, in1 = 0, in2 = 0 }

local function pin_set(pin, level, pull)
    if not pin then return end
    if pull then gpio.setup(pin, level, pull) else gpio.setup(pin, level) end
end

-- ==================== 基础资源 ====================

-- 所有 GPIO 高电平输出 3.3V（必须在其它初始化之前）
function M.io_voltage()
    if pm and pm.ioVol and pm.IOVOL_ALL_GPIO then
        pm.ioVol(pm.IOVOL_ALL_GPIO, 3300)
        return true
    end
    log.warn("hw", "本固件不支持 pm.ioVol，GPIO 电平沿用默认值")
    return false
end

function M.rs485_power(on) pin_set(PIN.RS485_PWR, on and 1 or 0) end -- 485 芯片供电
-- RS485 EN（接 DE/RE）：归 UART2 的硬件自动换向控制，软件不要把它当普通 GPIO 拉高，
-- 否则 DE=1/RE=1 → 收发器长期处于发送态、接收器关闭，只能发不能收（表现为全部超时）。
-- 只有确实需要软件手动控方向时，才在 meter_app 的 CFG.dir_gpio 里填 23。
function M.rs485_en() end
function M.opamp_power(on) pin_set(PIN.OPAMP_PWR, on and 1 or 0) end -- 运放供电，开=可测模拟量
function M.power_out(on)   pin_set(PIN.PWR_OUT,   on and 1 or 0) end -- 可控电源输出

-- 网络灯：on=true 常亮 / false 灭 / nil 恢复闪烁
function M.net_led(on)
    if on == nil then
        led_mode = "blink"
    else
        led_mode = on and "on" or "off"
        pin_set(PIN.NET_LED, on and 1 or 0)
    end
end

-- 输入口（干接点/电平），返回 0/1
function M.input(n)
    local pin = (n == 2) and PIN.IN2 or PIN.IN1
    return gpio.get(pin) and 1 or 0
end

-- ==================== ADC ====================
-- adc.get() 返回引脚电压 mV；三个通道均为 36V 分压后 ≤3.3V，用量程 MAX
local function adc_read(ch)
    adc.setRange(adc.ADC_RANGE_MAX) -- 量程必须在 open 之前设置
    adc.open(ch)
    local mv = adc.get(ch) or 0
    adc.close(ch)
    return mv
end

function M.read_supply_mv()  -- 供电电压 mV（最大 36V）
    return adc_read(ADC.SUPPLY) * 1033000 / 33000
end

function M.read_ain1_mv()    -- 模拟量输入1 电压 mV
    return adc_read(ADC.AIN1) * 103300 / 3300
end

function M.read_ain2()       -- 模拟量输入2 电流 = ADC电压/51（单位按传感器标定）
    return adc_read(ADC.AIN2) / 51
end

-- 最新一次 ADC 采样（供上报使用，避免每次上报都开 ADC）
function M.get_hw_data() return hw_data end

-- ==================== 任务 ====================

local function led_task()
    local lvl = 0
    while true do
        if led_mode == "blink" then
            lvl = 1 - lvl
            pin_set(PIN.NET_LED, lvl)
        elseif led_mode == "on" then
            pin_set(PIN.NET_LED, 1)
        else
            pin_set(PIN.NET_LED, 0)
        end
        sys.wait(CFG.led_blink_ms)
    end
end

-- Reload 按键：短按发 RELOAD_KEY_SHORT，长按发 RELOAD_KEY_LONG（订阅方自行决定动作）
-- 边沿触发：必须先看到一次高电平（松开）才允许判定"按下"，
-- 否则开机时该脚若为低（未贴按键/上拉无效）会被误判成长按，形成重启死循环。
local function key_task()
    local armed      = false -- 是否见过松开态
    local pressed_ms = 0
    local long_sent  = false
    local last_lvl   = nil
    while true do
        local lvl = gpio.get(PIN.RELOAD_KEY)
        if lvl ~= last_lvl then
            log.info("hw", "Reload 键电平", lvl, armed and "(已武装)" or "(待松开)")
            last_lvl = lvl
        end
        if lvl == 1 then armed = true end

        if lvl == 0 and armed then -- 按下接 GND
            pressed_ms = pressed_ms + 50
            if not long_sent and pressed_ms >= CFG.key_long_ms then
                long_sent = true
                log.warn("hw", "Reload 长按", CFG.key_long_ms, "ms")
                sys.publish("RELOAD_KEY_LONG")
            end
        else
            if armed and pressed_ms >= 50 and pressed_ms < CFG.key_long_ms then
                log.info("hw", "Reload 短按", pressed_ms, "ms")
                sys.publish("RELOAD_KEY_SHORT")
            end
            pressed_ms, long_sent = 0, false
        end
        sys.wait(50)
    end
end

local function adc_task()
    while true do
        hw_data.vbat = M.read_supply_mv()
        hw_data.ain1 = M.read_ain1_mv()
        hw_data.ain2 = M.read_ain2()
        hw_data.in1  = M.input(1)
        hw_data.in2  = M.input(2)
        sys.publish("HW_DATA", hw_data)
        sys.wait(CFG.adc_period)
    end
end

-- 硬件看门狗：GPIO28，每 150s 喂一次（板子默认没贴芯片，引脚动作无副作用）
local function wtd_init()
    local ok = exair153x_wdt.init({
        wdt_pin            = PIN.WDT,       -- GPIO28 → NPN → WTDOG
        auto_feed_period_s = CFG.wtd_feed_s, -- 自动喂狗周期 s（库内部自带喂狗任务）
    })
    if not ok then log.warn("hw", "看门狗初始化失败，请检查 exair153x_wdt 参数") end
end

-- ==================== 初始化 ====================
function M.init()
    if inited then return end
    inited = true

    local io3v3 = M.io_voltage()          -- ① 先定电平，再碰任何外设
    pin_set(PIN.RS485_PWR, 1)             -- ② 485 芯片上电
    -- ③ RS485 EN(GPIO23→DE/RE) 不能 gpio.setup：
    --    该脚由 UART2 的硬件自动换向驱动，抢成 GPIO 输出高会把收发器钉在发送态
    pin_set(PIN.OPAMP_PWR, 0)             -- ④ 运放默认关（省电），用 opamp_power(true) 打开
    pin_set(PIN.PWR_OUT, 0)               -- ⑤ 可控电源输出默认关
    pin_set(PIN.NET_LED, 0)               -- ⑥ 网络灯先灭，由 led_task 接管闪烁
    pin_set(PIN.RELOAD_KEY, 0, gpio.PULLUP) -- ⑦ Reload 按键：输入 + 内部上拉，按下接 GND
    pin_set(PIN.IN1, 0, gpio.PULLUP)      -- ⑧ 输入口：输入 + 上拉，悬空读 1
    pin_set(PIN.IN2, 0, gpio.PULLUP)

    sys.taskInit(led_task)
    sys.taskInit(key_task)
    sys.taskInit(adc_task)
    -- TODO 先禁用，排查"开机约 2 秒反复重启"是否由喂狗波形/极性引起
    -- （exair153x_wdt 假设 GPIO→NPN→WTDOG；若板上 GPIO28 直连 WTDOG，电平是反的）
    -- wtd_init()

    log.info("hw", "板级初始化完成", "3.3V:", io3v3,
        "485电源:GPIO" .. PIN.RS485_PWR, "EN:GPIO" .. PIN.RS485_EN .. "(UART硬件自动换向)")
end

return M
