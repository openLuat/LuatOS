--[[
@module  boot_app
@summary 启动编排：上电时序、显示与触摸初始化、界面加载、周期任务
@version 1.0.0
@date    2026.11.16
@author  江访
@usage
本文件只管「按什么顺序把东西点起来」，业务在 data_app、界面在 ui_app：
1、boot_app.main_task_func  上电时序 → display 初始化 → PLCUI 载入 → 触摸绑定 → 点背光 → 起定时器；
2、boot_app.refresh_tick_cbfunc  每秒推进一步工艺量并刷当前页；
3、boot_app.flow_tick_cbfunc     200ms 换一帧管路流动条纹。
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

--[[ 上电时序：先关背光再给屏供电，避免上电花屏
     两个已知的"假错误"，都不影响功能：
     1、pwm.setup 会打 E/pwm setup ch 3 —— LuatOS 的 luat_lib_pwm.c 在
        LUAT_CONF_PWM_MAXID 未定义时无条件打这行（通道 <=5 就是成功的），属遗留噪声；
     2、gpio.setup(17, 0) 会打 W/gpio ... pin 17 disable use —— 这版固件的 pinmux
        已把 GPIO17 关掉（LCD 供电由硬件常使能），返回 0 是正常的，不必重试。 ]]
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

--[[ 显示初始化：10 寸 1024x600 RGB，失败直接返回 false ]]
local function display_init()
    if IS_PC then return true end
    local exd = require "exd_air8607_rgb"
    local ok, info = exd.setup({ pin_rst = 15 })
    if not ok then
        log.error("boot", "显示初始化失败", info)
        return false
    end
    log.info("boot", "显示就绪", info or "")
    if display and display.getSize then
        local w, h = display.getSize()
        if w ~= SCREEN_W or h ~= SCREEN_H then
            log.warn("boot", "显示尺寸与设计稿不一致", w .. "x" .. h, "设计稿 1024x600")
        end
    end
    return true
end

--[[ 触摸：GT911 挂在 I2C1，初始化失败不影响先出画面 ]]
local function touch_init()
    if IS_PC then return true end
    local tp_app = require "tp_app"
    return tp_app.init()
end

--[[ 触摸绑定必须在 plcui.init 之后，否则按钮不响应 ]]
local function touch_bind()
    if IS_PC then return end
    local tp_app = require "tp_app"
    if not tp_app.bind() then
        log.error("boot", "触摸绑定 PLCUI 失败，界面将不可点")
    end
end

--[[ 界面就绪后再点背光，避免用户看到半张界面；亮度取数据层当前值 ]]
local function backlight_on()
    if IS_PC then return end
    local duty = data_app.bright_level() or BL.duty
    pwm.setup(BL.pwm_ch, BL.freq, duty)
    pwm.start(BL.pwm_ch)
    log.info("boot", "背光点亮", duty .. "%")
end

--[[ 每秒任务：推进工艺量 + 刷界面 ]]
function boot_app.refresh_tick_cbfunc()
    data_app.step()
    ui_app.refresh()
end

--[[ 200ms 任务：管路流动条纹 ]]
function boot_app.flow_tick_cbfunc()
    ui_app.tick_flow()
end

--[[ 启动主任务 ]]
function boot_app.main_task_func()
    log.info("boot", "启动", PROJECT or "plcui_injection_line", VERSION or "1.0.0")

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

    sys.timerLoopStart(boot_app.refresh_tick_cbfunc, 1000)
    sys.timerLoopStart(boot_app.flow_tick_cbfunc, 200)

    log.info("boot", "界面已就绪，四页可切换")
end

sys.taskInit(boot_app.main_task_func)

return boot_app
