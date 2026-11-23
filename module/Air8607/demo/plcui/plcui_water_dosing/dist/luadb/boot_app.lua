--[[
@module  boot_app
@summary 启动编排：上电时序、显示与触摸初始化、界面加载、周期任务
@version 1.0.0
@date    2026.11.16
@author  江访
@usage
本文件只管「按什么顺序把东西点起来」，业务在 data_app、界面在 ui_app：
1、boot_app.main_task_func   上电时序 -> display 初始化 -> PLCUI 载入 -> 触摸绑定 -> 点背光 -> 起定时器；
2、boot_app.refresh_tick_cbfunc 每秒推进工艺量并刷当前页；
3、boot_app.flow_tick_cbfunc    200ms 换一帧管路流动条纹。
PC 模拟器与真机走同一份代码，只有 board 相关几段按 rtos.bsp() 跳过。
本文件的对外接口有 3 个。
]]

local boot_app = {}

local SCREEN_W, SCREEN_H = 1024, 600
local IS_PC = rtos.bsp() == "PC"

local data_app = require "data_app"
local ui_app = require "ui_app"

-- Air8607 整机：背光 PWM3，LCD 供电 GPIO17（低有效），DISP 复位 GPIO15
local BL = { pwm_ch = 3, freq = 1000, duty = 82 }

local function power_on()
    if IS_PC then return end
    pwm.setup(BL.pwm_ch, BL.freq, 0)
    pwm.start(BL.pwm_ch)
    local ok17 = gpio.setup(17, 0)
    if not ok17 then
        log.info("boot", "GPIO17 已由固件托管，跳过（LCD 供电常使能）")
    end
    gpio.setup(15, 1)
    i2c.setup(1, i2c.FAST)
    sys.wait(120)
end

local function display_init()
    if IS_PC then return true end
    local exd = require "exd_air8607_rgb"
    local ok, info = exd.setup({ pin_rst = 15 })
    if not ok then
        log.error("boot", "显示初始化失败", info)
        return false
    end
    log.info("boot", "显示就绪", info or "")
    return true
end

local function touch_init()
    if IS_PC then return true end
    local tp_app = require "tp_app"
    return tp_app.init()
end

local function touch_bind()
    if IS_PC then return end
    local tp_app = require "tp_app"
    if not tp_app.bind() then
        log.error("boot", "触摸绑定 PLCUI 失败，界面将不可点")
    end
end

local function backlight_on()
    if IS_PC then return end
    pwm.setup(BL.pwm_ch, BL.freq, BL.duty)
    pwm.start(BL.pwm_ch)
    log.info("boot", "背光点亮", BL.duty .. "%")
end

function boot_app.refresh_tick_cbfunc()
    data_app.step()
    ui_app.refresh()
end

function boot_app.flow_tick_cbfunc()
    ui_app.tick_flow()
end

function boot_app.main_task_func()
    log.info("boot", "启动", PROJECT or "plcui_water_dosing", VERSION or "1.0.0")

    power_on()

    if not display_init() then
        log.error("boot", "显示未就绪，流程终止")
        return
    end

    data_app.init()

    if not ui_app.load(ui_app.handlers) then
        log.error("boot", "界面加载失败，请检查 main.xml 与图片是否同目录")
        return
    end

    touch_init()
    touch_bind()
    backlight_on()

    -- 首帧刷一次，让界面脱离初值
    ui_app.refresh()

    sys.timerLoopStart(boot_app.refresh_tick_cbfunc, 1000)
    sys.timerLoopStart(boot_app.flow_tick_cbfunc, 200)

    log.info("boot", "界面已就绪，6 态可切换")
end

sys.taskInit(boot_app.main_task_func)

return boot_app
