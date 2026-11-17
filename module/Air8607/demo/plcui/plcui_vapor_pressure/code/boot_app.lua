--[[
@module  boot_app
@summary 启动编排：Air8607 上电、显示与触摸初始化、plcui 加载、刷新与工艺节拍启动
@version 1.0.0
@date    2026.11.16
@author  蒋骞
@usage
本文件为 plcui_vapor_pressure 的启动编排模块，顺序固定：
1、板级上电与显示（exd_air8607_rgb）、触摸（tp_app，GT911）；
2、plcui.init(1024x600)，宽高必须与显示设备一致；
3、plcui.load("/luadb/main.xml", {handlers = ui_app.handlers})；
4、ui_app.init 绑定界面，tp_app.bind 绑定触摸；
5、启动 500ms 界面刷新与 200ms 工艺节拍。

PC 模拟器上跳过板级上电与显示 / 触摸初始化，直接用 SDL 窗口，
plcui 的 Lua 接口在 PC 与真机上完全一致。

本文件的对外接口有 1 个：boot_app.main_task_func（文件末尾自启动）。
]]

local boot_app = {}

local ui_app = require "ui_app"
local vp_app = require "vp_app"

-- 屏幕分辨率与背光通道
local SCREEN_W, SCREEN_H = 1024, 600
local IS_PC = rtos.bsp() == "PC"
local BL = { pwm_ch = 3, freq = 1000, duty = 82 }

-- plcui 初始化与 XML 路径的兼容候选
local XML_CANDIDATES = { "/luadb/main.xml", "/res/main.xml", "/main.xml" }

-- 板级上电：背光 PWM、LCD 供电、DISP、功放、I2C
local function power_on()
    pwm.setup(BL.pwm_ch, BL.freq, 0)
    pwm.start(BL.pwm_ch)
    gpio.setup(17, 0)   -- LCD 供电（低有效）
    gpio.setup(15, 1)   -- DISP
    gpio.setup(73, 0)   -- 功放关断
    i2c.setup(1, i2c.FAST)
    sys.wait(120)
end

-- 显示初始化：demo 已验证的 RGB 扩展库，display 后端失败自动降级 lcd
local function display_init()
    if IS_PC then
        return true
    end
    local exd = require "exd_air8607_rgb"
    local ok, info = exd.setup({ pin_rst = 15 })
    if not ok then
        log.error("boot", "显示初始化失败", info)
        return false
    end
    log.info("boot", "显示就绪", type(info) == "string" and info or "display")
    return true
end

local function backlight_on()
    if IS_PC then
        return
    end
    pwm.setup(BL.pwm_ch, BL.freq, BL.duty)
    pwm.start(BL.pwm_ch)
    log.info("boot", "背光已点亮", BL.duty .. "%")
end

-- 触摸初始化（i2c1 + GT911），必须在 plcui.init 之前
local function touch_init()
    if IS_PC then
        return true
    end
    local tp_app = require "tp_app"
    return tp_app.init()
end

-- plcui.device_bind_touch 必须在 plcui.init 之后
local function touch_bind()
    if IS_PC then
        return
    end
    local tp_app = require "tp_app"
    if not tp_app.bind() then
        log.error("boot", "触摸绑定 plcui 失败，按钮点不动")
    end
end

-- 新版 plcui.init(options)，旧固件是 plcui.init(width, height)
local function init_with_options()
    return plcui.init({ width = SCREEN_W, height = SCREEN_H })
end

local function init_with_size()
    return plcui.init(SCREEN_W, SCREEN_H)
end

local function plcui_init()
    local errs = {}
    local attempts = {
        { "init({width,height})", init_with_options },
        { "init(w,h)", init_with_size },
    }
    for _, a in ipairs(attempts) do
        local ok, ret, err = pcall(a[2])
        if ok and ret then
            return true, a[1]
        end
        local why = (not ok) and tostring(ret)
            or (type(err) == "table" and (err.message or err.code) or tostring(err))
        errs[#errs + 1] = a[1] .. " -> " .. tostring(why)
    end
    return false, table.concat(errs, " | ")
end

-- 加载 XML：handlers 必须放在 options 表里，写错等于整个交互层没接线
local function load_xml()
    for _, path in ipairs(XML_CANDIDATES) do
        if io.exists(path) then
            local ok, doc, err = pcall(plcui.load, path, { handlers = ui_app.handlers })
            if ok and doc then
                log.info("boot", "界面已加载", path)
                return doc
            end
            local reason = err and (err.message or err.code) or tostring(doc)
            log.error("boot", "加载失败", path, reason)
            return nil
        end
    end
    log.error("boot", "找不到 main.xml，请检查 /luadb/main.xml、/res/main.xml 或 /main.xml")
    return nil
end

--[[
主任务：板级初始化 -> plcui 初始化 -> 加载界面 -> 启动刷新与工艺节拍

@api boot_app.main_task_func()
]]
function boot_app.main_task_func()
    if not IS_PC then
        power_on()
        if not display_init() then
            return
        end
        if not touch_init() then
            log.error("boot", "触摸初始化失败，请检查 GT911 排线")
            return
        end
    end

    local ok, why = plcui_init()
    if not ok then
        log.error("boot", "plcui.init 失败", why, "请确认固件已开启 LUAT_USE_PLCUI")
        return
    end
    local ver = plcui.version and plcui.version() or "?"
    log.info("boot", "plcui 就绪", tostring(ver))

    local doc = load_xml()
    if not doc then
        return
    end

    ui_app.init(doc)
    sys.timerLoopStart(ui_app.refresh_cbfunc, 500)
    vp_app.start()
    touch_bind()
    backlight_on()

    log.info("boot", "蒸气压测定仪 HMI 已就绪")
end

sys.taskInit(boot_app.main_task_func)

return boot_app
