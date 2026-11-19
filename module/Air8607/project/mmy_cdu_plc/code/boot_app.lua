--[[
@module  boot_app
@summary 启动编排：上电时序、显示与触摸初始化、界面载入、每秒推进
@version 1.0.0
@date    2026.11.17
@usage
本文件只管「按什么顺序把东西点起来」，业务在 data_app、界面在 ui_app：
1、power_on      背光 PWM3 归零、LCD 供电与复位、I2C1；
2、display_init  exd_air8607_rgb 初始化 1024x600 RGB；
3、ui_app.load   plcui.init + 载入 main.xml + 进首页；
4、touch_init    触摸初始化并绑定 PLCUI；
5、backlight_on  最后点亮背光，防上电花屏；
6、每秒 tick     推进业务数据并刷当前页。
PC 模拟器与真机走同一份代码，只有板级几段按 rtos.bsp() 跳过。
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
    pcall(function()
        pwm.setup(BL.pwm_ch, BL.freq, 0)
        pwm.start(BL.pwm_ch)
    end)
    pcall(function()
        gpio.setup(17, 0)
        gpio.setup(15, 1)
    end)
    pcall(function() i2c.setup(1, i2c.FAST) end)
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
    log.info("boot", "显示就绪", info and info.backend or "")
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
    pcall(function()
        pwm.setup(BL.pwm_ch, BL.freq, BL.duty)
        pwm.start(BL.pwm_ch)
    end)
    log.info("boot", "背光点亮", BL.duty .. "%")
end

--[[ 放大 hzfont 字形缓存
PLCUI 自己在首帧时才初始化 hzfont，用的容量是 256 条；本工程五页共 9 档字号、
约 460 个「字符 × 字号」组合，256 条会反复淘汰重绘（日志里那句 cache size=256 已满）。
hzfont_init 在已初始化时会直接返回成功并跳过，所以在这里先按 1024 初始化，
PLCUI 后续那次调用就变成空操作，缓存容量按我们的来。
容量失败不影响启动：init 返回 0 → 状态仍是 UNINIT → PLCUI 会按 256 再初始化一次。]]
local function font_cache_tune()
    if not hzfont or not hzfont.init then
        log.info("boot", "无 hzfont 库，字形缓存保持默认")
        return
    end
    -- 依次尝试，真机内存不够时退一档，最终退到默认 256 也不影响启动
    for _, cap in ipairs({ 1024, 512 }) do
        local ok, ret = pcall(hzfont.init, nil, cap, false)
        if ok and ret then
            log.info("boot", "hzfont 字形缓存已设为", cap)
            return
        end
        log.warn("boot", "hzfont 缓存设置失败，降一档", cap)
    end
    log.warn("boot", "hzfont 缓存保持默认 256（容量不足时日志会提示已满）")
end

function boot_app.tick_cbfunc()
    data_app.step()
    ui_app.refresh()
end

function boot_app.main_task_func()
    log.info("boot", "启动", PROJECT or "mmy_cdu_plc", VERSION or "1.0.0")

    power_on()

    if not display_init() then
        log.error("boot", "显示未就绪，流程终止")
        return
    end

    data_app.init()

    font_cache_tune()

    if not ui_app.load(ui_app.handlers) then
        log.error("boot", "界面加载失败，请检查 main.xml 与 hit.png 是否在 res/ 下")
        return
    end

    touch_init()
    touch_bind()
    backlight_on()

    -- 首帧刷一次，让界面脱离 XML 初值
    ui_app.refresh()

    sys.timerLoopStart(boot_app.tick_cbfunc, 1000)

    log.info("boot", "界面已就绪，5 页可切换")
end

sys.taskInit(boot_app.main_task_func)

return boot_app
