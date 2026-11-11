--[[
@module  boot_app
@summary 启动编排（屏幕 -> 触摸 -> PLCUI -> 界面 -> 数据 -> 背光）
@version 1.1
@date    2026.11.11
@usage
本文件为 FactoryHMI 的启动编排模块：
1、真机：lcd_app.init 完成 Air8607 板级上电时序与 1024x600 RGB 屏初始化，背光保持熄灭；
2、真机：tp_app.init 初始化 GT911 触摸，失败不中止（界面还能显示，只是点不动）；
3、plcui.init 接管 LVGL 显示与输入，目标刷新率 60Hz；
4、真机：tp_app.bind 把触摸绑到 PLCUI，绑定之后 on-click 才会触发；
5、ui_app.start 加载 main.xml、注册界面事件、启动刷新调度；
6、data_sim.start 启动工艺数据模拟器，900ms 推进一次；
7、真机：等首帧画好再点亮背光，避免开机花屏。

注意：plcui 由 main.lua 统一 require 后提升为全局，本模块只做判空防御。

对外接口：
1、boot_app.main_task_func
]]

local boot_app = {}

local lcd_app = require "lcd_app"
local tp_app = require "tp_app"
local data_sim = require "data_sim"
local ui_app = require "ui_app"

local LCD_WIDTH = 1024
local LCD_HEIGHT = 600

local IS_PC = (rtos.bsp() == "PC")

--[[
启动编排主任务；
]]
function boot_app.main_task_func()
    if not IS_PC then
        if not lcd_app.init() then
            log.error("boot_app", "屏幕初始化失败，启动中止")
            return
        end
        if not tp_app.init() then
            log.error("boot_app", "触摸初始化失败，界面按钮点不动")
        end
    end

    -- plcui 未加载时直接中止，否则下面 index 会打挂整个 Lua VM
    if not plcui or not plcui.init then
        log.error("boot_app", "plcui 库不可用，启动中止，请烧录带 LUAT_USE_PLCUI 的固件")
        return
    end

    if not plcui.init({width = LCD_WIDTH, height = LCD_HEIGHT}) then
        log.error("boot_app", "plcui.init 失败，启动中止")
        return
    end
    local plcui_ver = (plcui.version and plcui.version()) or "?"
    log.info("boot_app", "plcui.init 成功", LCD_WIDTH .. "x" .. LCD_HEIGHT, plcui_ver)

    if not IS_PC then
        tp_app.bind()
    end

    if not ui_app.start() then
        log.error("boot_app", "界面加载失败，启动中止")
        return
    end

    data_sim.start()

    if IS_PC then
        ui_app.pc_snapshot_start()
    else
        sys.wait(200)
        lcd_app.backlight_on()
    end

    log.info("boot_app", "FactoryHMI 启动完成")
end

sys.taskInit(boot_app.main_task_func)

return boot_app
