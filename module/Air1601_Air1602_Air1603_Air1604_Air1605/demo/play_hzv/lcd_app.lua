--[[
@module  lcd_app
@summary LCD 显示驱动应用功能模块（display 库 + AirUI，参数来自 hzv_hw）
@version 1.0
@date    2026.10.26
@author  拓毅恒
@usage
本文件为 HZV 播放 demo 的显示初始化应用功能模块，核心业务逻辑为：
1、先把背光压灭（PWM 占空比 0 / GPIO 输出低），再调 display.init("custom", ...) 初始化 RGB 屏；
2、屏初始化完立刻 display.fill 把整屏刷黑，避免开背光时看到显存残留（花屏）；
3、调用 airui.init(w, h) 初始化 AirUI，并加载固件内置的中文字库（hzfont）；
4、界面/视频首帧准备好后，由 main.lua 调 lcd_app.backlight_on() 点亮背光。

为什么顺序必须是"先灭背光 → 初始化 → 刷黑 → 建界面 → 最后亮屏"：
RGB 屏上电后显存里是随机内容，背光一旦提前点亮，屏上看到的就是花屏/白屏；
所以初始化全程背光保持熄灭，等 display.fill 刷黑、界面与首帧都画好之后再点灯。

对外接口：
1、lcd_app.init()：初始化屏幕、AirUI 与中文字库（背光保持熄灭），成功返回 true
2、lcd_app.backlight_on()：点亮背光，幂等，可重复调用
3、lcd_app.get_size()：查询当前屏幕分辨率，返回 width, height

本文件不包含业务逻辑，由 main.lua 的启动任务按顺序调用。
]]

-- 加载硬件环境配置模块，屏幕参数全部从参数表读取，本文件不出现具体板型判断
local hzv_hw = require "hzv_hw"

local M = {}

-- 生效的屏幕分辨率，init 成功后由参数表或 display.getSize() 写入
local lcd_width, lcd_height = 0, 0

-- 背光是否已经点亮，避免重复操作
local backlight_on = false

--[[
打开背光；

@api lcd_app.backlight(config)
@summary 按板型参数打开背光，支持 PWM 调光、GPIO 直拉、随屏供电脚一并点亮三种方式
@param table config hzv_hw 参数表中的 lcd 子表
@return nil
]]
--[[
上电先让背光保持熄灭；

@api lcd_app.backlight_prepare(config)
@summary 屏初始化前把背光压到最暗（PWM 占空比 0 / GPIO 输出低），
          避免开电瞬间就把还没初始化的显存内容（花屏/雪花）亮给用户看；
          等界面和视频首帧准备好后再调 backlight_on() 点亮
@param table config hzv_hw 参数表中的 lcd 子表
@return nil
]]
local function backlight_prepare(config)
    local bl = config.backlight
    if bl and bl.pwm_ch then
        -- PWM 先按 0 占空比启动：输出有效但全黑，后面调 duty 就是调亮度
        pwm.setup(bl.pwm_ch, bl.pwm_freq or 1000, 0)
        pwm.start(bl.pwm_ch)
        log.info("lcd_app", "背光预置为熄灭(PWM)", "通道" .. bl.pwm_ch, "占空比0")
    elseif bl and bl.gpio_bl then
        gpio.setup(bl.gpio_bl, 0)
        log.info("lcd_app", "背光预置为熄灭(GPIO)", "GPIO" .. bl.gpio_bl)
    elseif config.pin_bl then
        -- 只给一个背光脚的板型（出厂固件写作 pin_bl，如 Air1601 V1.1 的 GPIO2）
        gpio.setup(config.pin_bl, 0)
        log.info("lcd_app", "背光预置为熄灭(GPIO)", "GPIO" .. config.pin_bl)
    end
end

--[[
点亮背光（幂等，可以多次调用）；

@api lcd_app.backlight_on()
@summary 界面/视频首帧准备好之后调用；对于"背光与屏供电同脚"的板型，
          display.init 已经点亮，这里只打印日志
@return nil
]]
function M.backlight_on()
    if backlight_on then
        return
    end

    local lcd_cfg = hzv_hw.get().lcd
    local bl = lcd_cfg.backlight
    if bl and bl.pwm_ch then
        local ch   = bl.pwm_ch
        local freq = bl.pwm_freq or 1000
        local duty = bl.level or 100
        pwm.setup(ch, freq, duty)
        pwm.start(ch)
        log.info("lcd_app", "背光点亮(PWM)", "通道" .. ch, "占空比" .. duty)
    elseif bl and bl.gpio_bl then
        gpio.setup(bl.gpio_bl, 1)
        gpio.set(bl.gpio_bl, 1)
        log.info("lcd_app", "背光点亮(GPIO)", "GPIO" .. bl.gpio_bl)
    elseif lcd_cfg.pin_bl then
        gpio.setup(lcd_cfg.pin_bl, 1)
        gpio.set(lcd_cfg.pin_bl, 1)
        log.info("lcd_app", "背光点亮(GPIO)", "GPIO" .. lcd_cfg.pin_bl)
    elseif lcd_cfg.pin_pwr then
        -- 背光与屏供电同脚，display.init 内部已经点亮
        log.info("lcd_app", "背光随 LCD 供电脚已点亮", "GPIO" .. lcd_cfg.pin_pwr)
    else
        log.info("lcd_app", "该板无需软件控制背光")
    end

    backlight_on = true
end

--[[
初始化 LCD 显示驱动和 AirUI；

@api lcd_app.init()
@summary 按 HARDWARE_ENV 参数初始化屏幕与 AirUI，失败时打印错误并返回 false
@return boolean 初始化成功返回 true，失败返回 false

@usage
if not lcd_app.init() then
    log.error("main", "屏幕初始化失败")
    return
end
]]
function M.init()
    local cfg = hzv_hw.get()
    local lcd_cfg = cfg.lcd

    -- 屏幕参数先按参数表落盘，display.getSize() 能取到真实值时再用真实值覆盖
    lcd_width, lcd_height = lcd_cfg.w, lcd_cfg.h

    -- 第一步：屏初始化前先把背光压灭。
    -- 背光提前亮会照出显存里的上电随机内容（花屏/白屏），所以整个初始化过程都保持熄灭，
    -- 等刷黑、建好界面、首帧画完，再由 main.lua 调 backlight_on() 点灯。
    backlight_prepare(lcd_cfg)

    -- PC 模拟器上 AirUI 走 SDL2 窗口，跳过 display.init，避免出现两个窗口
    if rtos.bsp() == "PC" then
        log.info("lcd_app", "PC 模拟器跳过 display.init")
    else
        if not display or not display.init then
            log.error("lcd_app", "固件不支持 display 库，请烧录带 LUAT_USE_DISPLAY 的固件")
            return false
        end

        -- 统一用 display 库初始化 RGB 屏，id 必须显式给 0，AirUI 取的是默认屏
        local ok, err = display.init("custom", {
            id        = 0,
            interface = "rgb",
            w         = lcd_cfg.w,
            h         = lcd_cfg.h,
            -- RGB 时序
            hbp       = lcd_cfg.hbp,
            hspw      = lcd_cfg.hspw,
            hfp       = lcd_cfg.hfp,
            vbp       = lcd_cfg.vbp,
            vspw      = lcd_cfg.vspw,
            vfp       = lcd_cfg.vfp,
            pclk_hz   = lcd_cfg.pclk_hz,
            -- 引脚：pin_pwr 由 display.init 拉高使能屏供电，pin_rst 由 display.init 做复位时序
            pin_rst   = lcd_cfg.pin_rst,
            pin_pwr   = lcd_cfg.pin_pwr,
        })
        if not ok then
            log.error("lcd_app", "display.init 失败", err)
            return false
        end
        log.info("lcd_app", "display.init 成功")

        -- display 内部可能按屏实际能力调整分辨率，这里以真实值为准
        if display.getSize then
            local dw, dh = display.getSize()
            if dw and dw > 0 and dh and dh > 0 then
                lcd_width, lcd_height = dw, dh
            end
        end

        -- 第二步：屏初始化完立刻把整屏刷黑。
        -- RGB 屏的帧缓冲由显示控制器持续扫描输出，display.fill 写进去马上生效，
        -- 这样即使背光被提前点亮，看到的也是纯黑而不是花屏（出厂固件同样先铺底再亮屏）。
        if display.fill then
            display.fill(0, 0, lcd_width, lcd_height, 0x0000)
            log.info("lcd_app", "屏幕已刷黑", lcd_width .. "x" .. lcd_height)
        end
    end

    -- 初始化 AirUI，HZV 播放依赖 airui.video 组件
    if not airui or not airui.init then
        log.error("lcd_app", "固件不支持 AirUI，请烧录带 LUAT_USE_AIRUI 的固件")
        return false
    end
    if not airui.init(lcd_width, lcd_height) then
        log.error("lcd_app", "airui.init 失败")
        return false
    end
    log.info("lcd_app", "airui.init 成功", lcd_width .. "x" .. lcd_height)

    -- ########## 加载中文字库（关键，漏了中文全部显示成方块） ##########
    -- 固件编译时已内置中文矢量字库（hzfont），这里不传 path 就用内置字库，加载后全局生效；
    -- Air1601/Air1602 固件说明里"中文矢量字库 √"，8607 出厂固件也是在 airui.init 之后
    -- 立即 airui.font_load，所以它的按钮中文正常。不加载则所有中文渲染成"豆腐块"。
    if airui.font_load then
        local ok, err = pcall(airui.font_load, {
            type       = "hzfont",   -- 目前仅 hzfont 支持矢量缩放
            size       = 16,         -- 组件不指定 font_size 时用这个字号
            cache_size = 1024,       -- 字形缓存数量，界面文字不多，1024 足够
            antialias  = 1,          -- 抗锯齿等级 1~3，1 最快
        })
        if ok then
            log.info("lcd_app", "中文字库加载成功(hzfont)")
        else
            log.error("lcd_app", "中文字库加载失败，界面中文会显示成方块", err)
        end
    else
        log.warn("lcd_app", "固件不支持 airui.font_load，界面中文可能显示成方块")
    end

    return true
end

--[[
查询当前屏幕分辨率；

@api lcd_app.get_size()
@summary 返回初始化后的屏幕宽高，用于视频组件居中计算
@return number 屏幕宽度
@return number 屏幕高度
]]
function M.get_size()
    return lcd_width, lcd_height
end

return M
