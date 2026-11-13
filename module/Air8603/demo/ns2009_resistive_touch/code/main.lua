--[[
@module  main
@summary Air1603 / Air8603M1 + 7 寸 800x480 RGB 电阻屏（NS2009）显示 + 触摸整机测试
@version 1.0
@date    2026.11.11
@usage
界面用 AirUI 控件（container/label/button/shape）实现；触摸/标定/存档走核心库 tp。
硬件/接线见 config.lua 与上级目录的 测试硬件环境说明.md。

分层：
  config.lua     硬件 + AirUI 主题配置（唯一配置源）
  drv_screen.lua 真机 display.init 分配 FB + PWM 背光
  drv_touch.lua  触摸：tp（init/事件桥接/标定/fskv 存档）
  ui_test.lua    AirUI 界面（触摸区 + 数值面板 + 按钮 + 标定/确认/超时页）
  main.lua       装配 + 启动（本文件）

启动顺序：
  1. 底板上电时序 power_on
  2. 关背光（RGB 帧缓冲跨热复位不清屏，先关掉避免残留画面）
  3. 点屏：drv.init（真机 display.init 分配 FB；PC 跳过）
  4. AirUI：airui.init(w,h) → set_rotation → font_load
  5. 触摸：touch.init（tp.init ns2009）→ airui.device_bind_touch(dev)
  6. 建界面 ui.init（AirUI 控件 + airui.touch_subscribe 驱动准星/轨迹）
  7. airui.refresh → 开背光 → ui.start（主循环：接标定触发）
  8. 上电标定策略：fskv 恢复 or 强制四点标定（不限时，直到成功）
]]

PROJECT = "NS2009_RESISTIVE_TOUCH"
VERSION = "001.001.000"

log.info("main", PROJECT, VERSION)

_G.sys = require("sys")

-- 模块装配（依赖单向：main → 各模块）
local CFG   = require("config")
local drv   = require("drv_screen")
local touch = require("drv_touch")
local ui    = require("ui_test")

--[[底板上电时序（真机必须；PC 无 gpio 自动跳过）
    少了这步：LCDC 初始化"成功"但黑屏，同时 I2C 上 NS2009 地址无应答。]]
local function power_on()
    if not (gpio and gpio.setup and gpio.set) then
        log.info("main", "无 gpio 库（PC 模拟器），跳过上电时序")
        return
    end
    for _, step in ipairs(CFG.power_on or {}) do
        gpio.setup(step.pin, step.dir or 0)
        gpio.set(step.pin, step.level or 0)
        log.info("main", "供电轨", "GPIO" .. step.pin, "=" .. (step.level or 0))
        if step.delay and step.delay > 0 then
            sys.wait(step.delay)
        end
    end
end

--[[I2C1 引脚显式复用（CFG.touch.pins），避免 pin 默认功能不是 I2C1]]
local function apply_touch_pins()
    if not (pins and pins.setup) then
        log.info("main", "固件没有 pins 库，跳过 I2C1 引脚复用")
        return
    end
    for _, p in ipairs(CFG.touch.pins or {}) do
        local ok, ret = pcall(pins.setup, p[1], p[2])
        log.info("main", "pins.setup", "PIN" .. p[1], p[2], ok and ret or "failed")
    end
end

sys.taskInit(function()
    -- 1. 先给屏/触摸上电（真机必须，PC 自动跳过）
    power_on()

    drv.set_backlight_cfg(CFG.backlight)
    drv.backlight(0)

    -- 3. 点屏（真机 display.init 分配 FB；PC 跳过）
    if not drv.init(CFG.lcd) then
        log.error("main", "点屏失败，测试终止")
        return
    end

    -- 4. AirUI 引擎
    if not (airui and airui.init) then
        log.error("main", "固件未启用 airui 库，无法运行本 AirUI 版本（需用含 AirUI 的固件）")
        return
    end
    local w, h = drv.width(), drv.height()
    if not airui.init(w, h) then
        log.error("main", "airui.init 失败")
        return
    end
    airui.set_rotation(CFG.lcd.direction or 0)
    if airui.font_load then
        airui.font_load({
            type = "hzfont",
            size = CFG.ui.font_size or 16,
            cache_size = 1024,
            antialias = 1,
        })
    end
    if airui.version then
        log.info("main", "airui version", tostring(airui.version()))
    end

    -- 5. 触摸（核心库 tp）+ 绑定到 AirUI（复用 tp.init 的设备拿标定后坐标）
    local dev, err
    if tp then
        apply_touch_pins()
        dev, err = touch.init(CFG.touch)
        if not dev then
            log.error("main", "触摸初始化失败：" .. tostring(err) .. "；显示部分继续运行")
        end
    else
        log.error("main", "固件未启用 tp 库，触摸/标定不可用；显示部分继续运行")
    end
    if dev and airui.device_bind_touch then
        local bok = airui.device_bind_touch(dev)
        log.info("main", "airui.device_bind_touch", bok)
    end

    -- 6. 建 AirUI 界面
    ui.init(CFG, touch)
    if airui.refresh then pcall(airui.refresh) end

    -- 7. 开背光 + 起主循环（接标定触发）
    sys.wait(150)
    drv.backlight(CFG.backlight.level)
    ui.start()

    -- 8. 上电标定策略：无存档 → 强制四点标定（不限时，直到成功）
    --    （未标定状态下触摸坐标上下颠倒——芯片原点在左下、屏幕逻辑原点在左上，
    --     所以首次上电必须完成一次标定，界面方向才会正确）
    if dev and not drv.is_pc then
        if CFG.touch.save_cal then
            local restored, rerr = touch.restore_calibration()
            if restored then
                log.info("main", "标定已从 fskv 恢复，跳过四点标定")
            elseif CFG.touch.auto_cal then
                log.info("main", "无有效标定存档（" .. tostring(rerr) .. "），上电强制四点标定（不限时）")
                ui.run_calibration(true)   -- 首次标定：不限时，超时/失败自动重来
            end
        elseif CFG.touch.auto_cal then
            log.info("main", "上电四点标定（未启用存档，不限时）")
            ui.run_calibration(true)
        end
    end

    log.info("main", "测试界面已启动",
        "屏幕 " .. w .. "x" .. h, "后端 airui", "触摸 NS2009（tp 核心库）")
end)

sys.run()
