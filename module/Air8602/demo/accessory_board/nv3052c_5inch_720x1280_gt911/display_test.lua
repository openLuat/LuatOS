--[[
@module  display_test
@summary Air8602 5寸 NV3052C 显示+GT911 触摸测试模块
@version 1.0
@date    2026.10.09
@author  江访
@usage
本文件为 5寸 NV3052C 显示 + GT911 触摸测试模块，核心测试流程为：
1、power_on()     —— 供电与 I2C1 引脚复用配置，本板 LCD_DISP = GPIO15，用户按原理图自行拉高
2、exd.setup()    —— 显示初始化，扩展库仅做显示IC初始化（复位 + 寄存器初始化 + RGB 时序 + 帧缓冲）
3、touch_init()   —— GT911 触摸初始化，i2c.setup + tp.init("gt911") + airui 绑定，用户自行初始化
4、draw_ui()      —— 界面绘制，深色背景 + 型号标题 + 提示文字
5、backlight_on() —— 背光点亮，PWM3，界面就绪后用户自行点亮
6、on_touch()     —— 触摸回调，按下处画绿色点并打印坐标

重要：供电、背光、触摸初始化均由本 demo 自行控制，显示IC初始化扩展库只负责显示 IC 初始化，
不操作供电引脚 pin_pwr、不操作背光引脚 pin_bl、不负责触摸初始化，显示初始化完成也不会自动开背光。

NV3052C 需要寄存器初始化序列：扩展库做复位 + 库内自带寄存器序列初始化 + RGB 时序配置（use_builtin_ic 默认 false，用库内自带序列）。
板级复位脚 pin_rst 必传，本板 LCD_DISP = GPIO15 兼 LCD 复位脚。

测试现象：深色背景 + 型号标题，触摸屏幕出现绿色点并打印坐标。
]]

-- 加载 NV3052C 显示IC初始化扩展库
local exd = require "exd_nv3052c_rgb"

-- 本板屏幕参数（NV3052C 5寸 720x1280）
local SCREEN_W = 720
local SCREEN_H = 1280

-- 触摸点记录
local dots = {}

-- 供电与 I2C1 引脚复用配置
-- LCD 供电/显示使能引脚由用户按底板原理图控制，扩展库不操作 pin_pwr
-- 本板 LCD_DISP = GPIO15（兼 LCD 复位脚，显示初始化内部会做复位时序）
local function power_on()
    -- I2C1 引脚复用（GT911 触摸总线）
    pins.setup(33, "I2C1_CLK")
    pins.setup(32, "I2C1_SDA")
    -- LCD_DISP = GPIO15（兼 LCD 复位脚，显示初始化内部会做复位时序）
    gpio.setup(15, 1)   -- 输出高电平，使能 LCD 显示
    sys.wait(100)       -- 等供电稳定
end

-- 背光点亮
-- 背光引脚由用户控制，扩展库不操作 pin_bl，显示初始化完成不会自动开背光
-- 本板背光 = PWM3 调光
local function backlight_on()
    local ok = pwm.setup(3, 1000, 100)  -- 通道 3，1kHz，100% 亮度
    if ok then
        pwm.start(3)
        log.info("display_test", "背光已点亮")
    else
        log.error("display_test", "背光初始化失败，请确认 PWM 通道与原理图一致")
    end
end

-- GT911 触摸初始化
-- 触摸初始化由用户完成，与显示IC初始化扩展库无关
-- 本板 GT911 挂 I2C1
local function touch_init()
    -- I2C 总线初始化（tp.init 只做触摸芯片初始化，I2C 控制器须先配置）
    i2c.setup(1, i2c.SLOW)  -- I2C1，低速模式（触摸对速度不敏感，低速最稳定）
    local tp_device = tp.init("gt911", {
        port = 1,            -- I2C 端口 1
        pin_rst = 72,        -- TP_RESET
        pin_int = 51,        -- TP_INT（接唤醒引脚的板子传 gpio.WAKEUP0）
        int_type = tp.FALLING,
        w = SCREEN_W,
        h = SCREEN_H,
    })
    if tp_device then
        airui.device_bind_touch(tp_device)
    else
        log.error("display_test", "触摸初始化失败")
    end
end

-- 触摸回调：按下处画绿色点并打印坐标
local function on_touch(state, x, y, track_id, timestamp)
    if state == airui.TP_DOWN then
        log.info("display_test", "触摸按下", x, y)
        local dot = airui.shape({
            x = x - 6, y = y - 6, w = 12, h = 12,
            items = {
                { type = "rect", x = 0, y = 0, w = 12, h = 12,
                  fill = true, fill_color = 0x00FF00, color = 0x00FF00 },
            },
        })
        table.insert(dots, dot)
    end
end

-- 界面绘制：深色全屏背景 + 型号标题 + 测试提示
local function draw_ui()
    -- 深色全屏背景
    airui.shape({
        x = 0, y = 0, w = SCREEN_W, h = SCREEN_H,
        items = {
            { type = "rect", x = 0, y = 0, w = SCREEN_W, h = SCREEN_H,
              fill = true, fill_color = 0x101828, color = 0x101828 },
        },
    })
    -- 型号标题
    airui.label({
        x = 0, y = math.floor(SCREEN_H / 2) - 60, w = SCREEN_W, h = 36,
        text = "Air8602 5寸 NV3052C 显示+触摸测试",
        font_size = 28, color = 0xFFFFFF, align = airui.TEXT_ALIGN_CENTER,
    })
    -- 测试提示
    airui.label({
        x = 0, y = math.floor(SCREEN_H / 2), w = SCREEN_W, h = 28,
        text = "触摸屏幕画点测试",
        font_size = 20, color = 0xAAAAAA, align = airui.TEXT_ALIGN_CENTER,
    })
end

-- 测试主任务（运行在协程中）：供电 → 显示初始化 → 界面绘制 → 触摸初始化 → 背光点亮
local function display_test_task_func()
    -- 1、供电与引脚配置（自行控制）
    power_on()

    -- 2、显示初始化（扩展库，仅显示IC初始化）
    --    NV3052C 不设板级默认参数，pin_rst 必传
    --    本板 LCD_DISP = GPIO15 兼 LCD 复位脚，屏幕参数（5寸 720x1280/时序）全默认
    local ok, info = exd.setup({ pin_rst = 15 })
    if not ok then
        log.error("display_test", "显示初始化失败", info)
        return
    end
    log.info("display_test", "显示初始化完成", info.backend, info.w, info.h)

    -- 3、UI 初始化与界面绘制
    airui.init(info.w, info.h)
    airui.set_rotation(0)
    airui.font_load({ type = "hzfont", size = 24, cache_size = 1024, antialias = 1 })
    draw_ui()

    -- 4、触摸初始化（自行控制）
    touch_init()
    airui.touch_subscribe(on_touch)

    -- 5、背光点亮（自行控制，界面就绪后点亮避免花屏）
    backlight_on()
    log.info("display_test", "测试就绪，请触摸屏幕")
end

sys.taskInit(display_test_task_func)
