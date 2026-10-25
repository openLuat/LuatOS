--[[
@module  main
@summary Air8607 电子相册（1024x600 横屏 + GT911 触摸 + SPI1 TF 卡）
@version 1.0
@date    2026.10.22
@board   Air8607（Air1603）+ 10寸 RGB 1024x600 + GT911 + TF 卡

@boot
1、power_on()      —— 背光 PWM3 占空比 0、LCD 供电、SD_EN 上电、PA 关断、I2C1 配置
2、exd.setup()     —— 显示初始化（复位 + RGB 时序 + 帧缓冲）
3、airui 初始化    —— init + 旋转 + 中文字库
4、app.start()     —— 建首页（先出画面，SD 卡在后台挂载）
5、touch_init()    —— GT911 + airui 绑定
6、touch_subscribe —— 全局手势（查看器里的左右滑动 / 轻触呼出控制条）
7、backlight_on()  —— 界面就绪后再点亮背光，防花屏

@note
照片解码**不走** LVGL 图片缓存（那是 1024x600 报
"hzjpeg alloc fail ... 需要1843200的连续内存" 的根因），
而是走 airui.video 的单帧 MJPG 通道，固定的两块 1024x600 RGB565
帧缓冲，零拷贝解码，destroy 即释放。详见 photo_view.lua 文件头。
]]
PROJECT = "air8607_album"
VERSION = "1.0.0"

local conf = require "conf"
local exd = require "exd_air8607_rgb"
local app = require "app"
local ui_home = require "ui_home"
local ui_lock = require "ui_lock"
local settings = require "settings"

local SW, SH = conf.W, conf.H

-- 调试开关：打开后打印 LVGL FPS / 触摸坐标 / 内存
local TP_DEBUG = false
local MEM_DEBUG = false

-- ==================== 上电时序 ====================
local function power_on()
    -- 背光 PWM3 上电占空比 0（UI 就绪后再点亮）
    pwm.setup(3, 1000, 0)
    pwm.start(3)

    -- LCD 供电使能（低有效，先关闭）与 DISP
    gpio.setup(17, 0)
    gpio.setup(15, 1)

    -- SD 卡供电（SD_EN 高有效）与功放关断（本工程不出声）
    gpio.setup(74, 1)
    gpio.setup(73, 0)

    -- GT911 触摸 I2C1：必须走轮询模式（第三参 true），速率用默认值。
    -- 中断模式下 TP 中断里突发读 I2C 会和嵌套中断互相干扰，表现为只在触摸时
    -- 报 I2C 错误 / 丢点 / 完全没反应。与 factory_new/drv/tp/tp_gt911.lua 一致。
    i2c.setup(1, 0, true)

    sys.wait(120)   -- 等供电稳定
end

local function backlight_on()
    -- 应用上次保存的亮度（设置页里可调；默认 100%）
    local b = settings.apply_brightness(settings.get_brightness())
    if b then
        log.info("main", "背光已点亮", b .. "%")
    else
        log.error("main", "背光初始化失败，请确认 PWM 通道")
    end
end

-- ==================== 触摸 ====================
local function touch_init()
    -- GT911 上电余量不足时 tp.init 会软失败（只返回 nil），必须重试一次，
    -- 否则静默变成“触摸完全失灵”。与 factory_new/ui/boot_ui.lua 一致。
    for attempt = 1, 2 do
        local dev = tp.init("gt911", {
            port = 1,             -- I2C1
            pin_rst = 14,         -- TP_RST（Air8607 = GPIO14）
            pin_int = 51,         -- TP_INT
            int_type = tp.FALLING,
            w = SW,
            h = SH,
        })
        if dev then
            airui.device_bind_touch(dev)
            log.info("main", "GT911 触摸初始化完成")
            return true
        end
        log.warn("main", "GT911 初始化未成功，200ms 后重试", attempt)
        sys.wait(200)
    end
    log.error("main", "触摸初始化失败")
    return false
end

-- ==================== 主流程 ====================
sys.taskInit(function()
    power_on()

    local ok, info = exd.setup({ pin_rst = 15 })
    if not ok then
        log.error("main", "显示初始化失败", info)
        return
    end
    log.info("main", "显示初始化完成", info.backend, info.w, info.h)
    -- display 是底层驱动（面板时序 + 帧缓冲），airui 只是它的上层 UI：
    -- airui 的平台驱动内部就是 luat_display_get_by_id(0) 拿 display 的 fb。
    -- 跑在 lcd 后端说明固件太老，Air1603 请用 V1028（该版本才带 display 核心库）。
    if info.backend ~= "display" then
        log.warn("main", "固件缺少 display 核心库（当前走旧 lcd 后端），建议升级 Air1603 V1028")
    end

    if not airui.init(SW, SH) then
        log.error("main", "airui.init 失败")
        return
    end
    airui.set_rotation(0)
    airui.font_load({
        type = "hzfont",
        size = conf.font.size,
        cache_size = conf.font.cache_size,
        antialias = conf.font.antialias,
    })
    if MEM_DEBUG or TP_DEBUG then airui.debug(true) end

    -- 先建首页：SD 卡挂载放到后台，开机更快出画面
    app.start()

    -- 触摸必须在动画/手势之前绑定
    touch_init()

    if airui.touch_subscribe then
        airui.touch_subscribe(function(state, x, y, id, ts)
            if TP_DEBUG then
                log.info("TP", state, x, y, id, ts)
            end
            app.on_touch(state, x, y, id, ts)
        end)
    else
        log.warn("main", "固件没有 airui.touch_subscribe，查看器手势不可用")
    end

    backlight_on()
    log.info("main", "电子相册已就绪")
end)

-- 时间/日期每分钟刷新一次（首页和锁屏页共用）
sys.timerLoopStart(function()
    ui_home.tick()
    ui_lock.tick()
end, 60000)

-- 内存观察（排查 OOM 时把 MEM_DEBUG 改成 true）
if MEM_DEBUG then
    sys.timerLoopStart(function()
        local ok, total, used, max = pcall(rtos.meminfo, "psram")
        if ok then
            log.info("mem.psram", used, "/", total, "max", max)
        end
        log.info("mem.lua", rtos.meminfo("lua"))
        log.info("mem.sys", rtos.meminfo("sys"))
    end, 10000)
end

sys.run()
