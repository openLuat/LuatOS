--[[
@module  main
@summary 电车充电站实时状态大屏（Air8607 + 10寸 1024x600 RGB + GT911 + 内置DAC/HT6873）
@version 1.0.0
@date    2026.10.23

=== 功能 ===
1. 10 个充电桩实时状态：空闲 / 充电中 / 充电完成，5 列 x 2 行卡片；
   每张卡一节电池，充电中按 soc 连续推进电量格（暗槽 + 亮段）。
2. 充电完成（充满或预充金额用完）后：
   - 卡片切荧光绿 + 呼吸高亮，并开始「停留计时」；
   - 立即语音播报「XX号充电桩充电完成，请及时驶离，超时将产生费用」；
   - 若开启定时播报，每 N 分钟重复提醒，直到车辆驶离（计时归零）。
3. 底部左侧：定时播报开关（勾选框）+ 分钟调节（-/+ 与 5/10/15/30 快捷档）。
4. 底部右侧：手动输入播报内容（软键盘 + 常用短语），可随时停止。
5. 点击任意卡片演示状态流转：空闲 → 充电中 → 已完成 → 驶离。

=== 启动顺序（顺序有依赖，勿随意调整）===
1) power_on        供电/背光 PWM 归零/I2C 引脚
2) exd.setup       RGB 时序 + 帧缓冲
3) airui.init      分辨率 + 中文字库 + 旋转
4) voice.init      音频通路（无硬件时自动降级为日志播报）
5) manager.init    业务状态先就绪，UI build 才能按真实状态渲染
6) ui.build        搭界面
7) touch_init      触摸绑定（必须在界面搭好之后）
8) backlight_on    首帧之后点亮背光，防花屏
9) 两个定时器：500ms 业务/计时刷新 + 400ms 完成态呼吸高亮
]]
PROJECT = "ev_charge_monitor"
VERSION = "1.0.0"

local cfg = require "ev_config"
local mgr = require "ev_manager"
local voice = require "ev_voice"
local ui = require "ev_ui"
local exd = require "exd_air8607_rgb"

local SCREEN_W, SCREEN_H = cfg.HW.screen.w, cfg.HW.screen.h

-- 开机演示数据：3 台充电中、1 台已完成（已完成的不重复播报）
local DEMO_INIT = {
    { status = "idle" },
    { status = "charging", soc = 42 },
    { status = "charging", soc = 66 },
    { status = "idle" },
    { status = "done" },
    { status = "charging", soc = 28 },
    { status = "idle" },
    { status = "idle" },
    { status = "idle" },
    { status = "idle" },
}

-- 供电、背光 PWM3 上电占空比 0 与 I2C 引脚配置
local function power_on()
    pwm.setup(cfg.HW.screen.pwm_ch, cfg.HW.screen.pwm_freq, 0)
    pwm.start(cfg.HW.screen.pwm_ch)
    gpio.setup(cfg.HW.screen.pin_pwr, 0)     -- LCD 供电使能（低有效，先关闭）
    gpio.setup(cfg.HW.screen.pin_rst, 1)     -- LCD 显示使能/复位脚拉高
    i2c.setup(cfg.HW.screen.i2c_id, i2c.FAST)
    sys.wait(100)                            -- 等供电稳定
end

-- 背光点亮（PWM3 调光）
local function backlight_on()
    if pwm.setup(cfg.HW.screen.pwm_ch, cfg.HW.screen.pwm_freq, 100) then
        pwm.start(cfg.HW.screen.pwm_ch)
        log.info("main", "背光已点亮")
    else
        log.error("main", "背光初始化失败，请确认 PWM 通道与原理图一致")
    end
end

-- GT911 触摸初始化 + airui 绑定
-- 注意：w/h 必须给，缺了会让 input 适配器以 EINVAL 静默拒绝
local function touch_init()
    local dev = tp.init(cfg.HW.tp.model, {
        port = cfg.HW.tp.port,
        pin_rst = cfg.HW.tp.pin_rst,
        pin_int = cfg.HW.tp.pin_int,
        int_type = tp.FALLING,
        w = SCREEN_W,
        h = SCREEN_H,
    })
    if dev then
        airui.device_bind_touch(dev)
        log.info("main", "GT911 触摸初始化完成")
        return true
    end
    log.error("main", "触摸初始化失败")
    return false
end

sys.taskInit(function()
    local is_pc = (rtos.bsp() == "PC")

    -- 1、供电与引脚
    if not is_pc then power_on() end

    -- 2、显示初始化
    local ok, info = exd.setup({ pin_rst = cfg.HW.screen.pin_rst })
    if not ok then
        log.error("main", "显示初始化失败", info)
        return
    end
    log.info("main", "显示初始化完成", info.backend, info.w, info.h)

    -- 3、AirUI 初始化
    airui.init(SCREEN_W, SCREEN_H)
    airui.set_rotation(0)
    airui.font_load({ type = "hzfont", size = 16, cache_size = 2048, antialias = 1 })

    -- 4、音频通路（失败只降级，不阻断 UI）
    voice.init(cfg.HW.audio)
    voice.on_state(ui.on_voice_state)

    -- 5、业务状态先就绪
    mgr.auto_demo = true
    mgr.init(DEMO_INIT)

    -- 6、搭界面（内部注册 mgr.on_change 并做一次全量刷新）
    ui.build()

    -- 7、触摸
    if not is_pc then touch_init() end

    -- 8、背光
    if not is_pc then backlight_on() end
    log.info("main", "充电站状态大屏已就绪，桩位数", cfg.PILE_COUNT)

    -- 9、主刷新：500ms 推进业务与计时显示
    local last = mgr.now_s()
    sys.timerLoopStart(function()
        local now = mgr.now_s()
        local dt = now - last
        if dt < 0 or dt > 5 then dt = 0.5 end   -- 首次进入 / 时钟异常时保守取值
        last = now
        local ok2, err = pcall(mgr.tick, dt)
        if not ok2 then log.error("main", "业务 tick 异常", err) end
        local ok3, err3 = pcall(ui.refresh)
        if not ok3 then log.error("main", "UI 刷新异常", err3) end
    end, 500)

    -- 完成态呼吸高亮单独节拍，与业务刷新解耦
    sys.timerLoopStart(function()
        pcall(ui.refresh_breath)
    end, 400)
end)

sys.run()
