local board = require "air8801_board"
local cfg = require "air8801_config"
local touch = require "air8801_touch"

sys.taskInit(function()
    if not _G.__power_on_done then sys.waitUntil("POWER_ON_DONE", 2000) end
    if not _G.__power_on_done then return end
    if not (lcd_drv.hw_init() and lcd_drv.airui_init()) then
        log.error("boot_ui", "RGB 初始化失败", cfg.panel)
        return
    end
    local logo = airui.container({parent = airui.screen, x = 0, y = 0, w = screen_w, h = screen_h,
        color = 0, color_opacity = 255, scrollable = false})
    if io.exists("/luadb/logo.png") then
        airui.image({parent = logo, x = (screen_w - 128) // 2, y = (screen_h - 128) // 2,
            w = 128, h = 128, src = "/luadb/logo.png"})
    end
    require("settings_display_app").restore_brightness()
    sys.wait(100)
    if not board.set_backlight(cfg.hw.lcd.backlight.level) then log.error("boot_ui", "背光启动失败") end
    -- 裸屏（型号 LCD 段）没有触摸芯片，直接跳过初始化与标定
    if not _G.is_pc and touch.enabled() then
        for _ = 1, 2 do
            local ok, dev = pcall(tp_drv.init)
            if ok and dev then break end
            log.warn("boot_ui", "触摸初始化失败", cfg.touch_mode, dev)
            sys.wait(150)
        end
    end
    if screen_w <= 480 then _G.density_scale = 0.78 end
    lcd_drv.airui_core_init()
    exwin = require "exwin"
    require("app_main").core()
    require("ui_main").core()
    require("ui_theme").restore()
    sys.publish("OPEN_IDLE_WIN")
    logo:destroy()
    log.info("boot_ui", "K8801 DESKTOP_READY", cfg.model, cfg.panel, cfg.touch_mode, touch.ready())
    if touch.resistive() and touch.ready() and not touch.calibrated() then
        sys.wait(200)
        require("air8801_touch_cal").open()
    end
end)
