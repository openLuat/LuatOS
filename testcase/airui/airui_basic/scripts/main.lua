PROJECT = "airui_test"
VERSION = "1.0.0"
local sys = require("sys")

-- AirUI 依赖 display 库：必须先 display.init 填充 display_conf/fb_info，
-- 否则 airui.init 会报 "luatos disp: display_conf is NULL"。
-- 注意：当前 draw_buf 像素数据按物理布局紧排，旋转由驱动层 flush 时完成。
sys.taskInit(function()
    log.info("airui", "start init")

    -- 初始化显示：st7701s 480x854 RGB 接口（与 display_basic 用例一致）
    local ret, err = display.init("st7701s", {
        w = 480,
        h = 854,
        interface = "rgb",
        pclk_polarity = 1, -- 时钟极性，1为高电平，0为低电平
        pin_scl = 23,      -- SPI 时钟引脚（初始化通信）
        pin_sdi = 2,       -- SPI 数据引脚
        pin_cs = 22,       -- SPI 片选引脚
        pin_rst = 15,      -- 复位引脚
    })
    log.info("airui", "display.init ret", ret, err)
    if not ret then
        log.error("airui", "display.init failed")
        return
    end

    -- 背光：PWM 通道3, 1kHz, 占空比100%
    local ok = pwm.open(3, 1000, 100)
    log.info("airui", "pwm backlight", ok)

    -- 初始化 AirUI，分辨率与物理屏一致（暂不旋转，先验证 AirUI 渲染链路）
    local airui_ret = airui.init(480, 854, airui.COLOR_FORMAT_RGB565)
    log.info("airui", "airui.init", airui_ret)
    if not airui_ret then
        log.error("airui", "airui.init failed")
        return
    end

    -- ===== GT911 触摸初始化（参考 eng_1602_5i_v5：I2C端口1, RST=3, INT=51, 下降沿）=====
    -- GPIO 复位序列
    gpio.setup(3, 0)
    gpio.close(3)

    -- 硬件 I2C 端口 1
    i2c.setup(1)

    -- 触摸回调（仅用于日志调试；AirUI 会通过 tp.init 配置轮询坐标）
    local function tp_callback(tp_device, tp_data)
        if tp_data and tp_data[1] then
            log.info("airui_touch", "x", tp_data[1].x, "y", tp_data[1].y, "event", tp_data[1].event)
        end
    end

    local tp_dev = tp.init("gt911", {
        port = 1,
        pin_rst = 3,
        pin_int = 51,
        int_type = tp.FALLING,
        w = 480,  -- GT911 X/Y Output Max，与物理屏一致
        h = 854,
    }, tp_callback)
    if not tp_dev then
        log.error("airui", "tp.init failed")
        return
    end
    airui.device_bind_touch(tp_dev)
    log.info("airui", "touch gt911 bound")

    -- 背景容器铺满全屏
    local bg = airui.container({
        parent = airui.screen,
        x = 0, y = 0, w = 480, h = 854,
        color = 0x2B2B2B,
    })

    -- 静态标题
    local title = airui.label({
        parent = airui.screen,
        x = 20, y = 20, w = 440, h = 40,
        text = "AirUI Test 480x854",
    })

    -- 动态计数标签
    local tick_label = airui.label({
        parent = airui.screen,
        x = 20, y = 70, w = 440, h = 40,
        text = "tick: 0",
    })

    -- 按钮
    local btn = airui.button({
        parent = airui.screen,
        x = 20, y = 120, w = 440, h = 50,
        text = "Button",
        on_click = function()
            log.info("airui", "button clicked")
        end,
    })

    -- 进度条
    local progress = airui.bar({
        parent = airui.screen,
        x = 20, y = 190, w = 440, h = 30,
        value = 0,
    })

    -- 复选框
    local cb = airui.checkbox({
        parent = airui.screen,
        x = 20, y = 240, w = 200, h = 40,
        text = "Check",
        checked = true,
        on_change = function(self)
            log.info("airui", "checkbox ->", self:get_checked())
        end,
    })

    -- 旋转：每次 +90°，循环 0/90/180/270（屏幕按钮 + 外部按键共用）
    local cur_rotation = 0
    local rot_btn = nil
    local function do_rotate()
        cur_rotation = (cur_rotation + 90) % 360
        airui.set_rotation(cur_rotation)
        if rot_btn then
            rot_btn:set_text("Rotate: " .. cur_rotation)
        end
        log.info("airui", "rotate ->", cur_rotation)
    end
    rot_btn = airui.button({
        parent = airui.screen,
        x = 20, y = 300, w = 440, h = 50,
        text = "Rotate: 0",
        on_click = do_rotate,
    })

    -- 外部按键(pin44，eng_1602_5i_v5 的 NES"上"键，低有效)控制旋转方向。
    -- 采用"中断置标志 + 主循环消费"，避免在 GPIO 中断上下文直接调用 LVGL/airui API。
    -- 中断回调置标志，由主循环消费，避免在中断上下文操作 LVGL/airui
    local rotate_pending = false
    local rotate_cooldown = 0
    gpio.setup(44, function()
        rotate_pending = true
    end, gpio.PULLUP, gpio.INT_FALLING)

    log.info("airui", "airui_test_ready")

    local tick = 0
    local dir = 1
    local value = 0
    while true do
        -- 消费外部按键旋转请求（低有效按键，按下即 INT_FALLING 一次）
        if rotate_pending then
            local now = mcu.ticks()
            rotate_pending = false
            if (now - rotate_cooldown) >= 250 then -- 250ms 冷却，防抖动重复触发
                rotate_cooldown = now
                sys.wait(30)
                do_rotate()
            end
        end

        tick = tick + 1

        -- 更新动态内容：计数 + 进度条往返摆动
        tick_label:set_text("tick: " .. tick)
        value = value + dir
        if value >= 100 then
            dir = -1
        elseif value <= 0 then
            dir = 1
        end
        progress:set_value(value, true)

        -- 刷新一帧（含性能计时）
        local t0_str, us_period = mcu.tick64()
        airui.full_refresh()
        local t1_str, period1 = mcu.tick64()
        local _ok, diff_tick = mcu.dtick64(t1_str, t0_str, 0)
        local mul = us_period
        if (not mul or mul <= 0) and period1 and period1 > 0 then
            mul = period1
        end
        if _ok and diff_tick and mul and mul > 0 then
            local us = diff_tick * mul
            log.info("airui", "airui_perf", "tick", tick, "us", us, "ms", us / 1000)
        end

        sys.wait(200)
    end
end)

sys.run()
