local cfg = require "air8801_config"
local bridge = require "factory_hzadb"
local buffer = ""
local channel
local reboot_pending

local function reply(command)
    if command == "PING" then return "PONG" end
    -- PANEL? 同时回报整机型号、触摸、串口电平与面板来源（project=出厂配置 / fskv=调试口临时覆盖）
    if command == "PANEL?" then
        return string.format("PANEL=%s,%s,PROJECT=%s,SERIAL=%s,SOURCE=%s",
            cfg.panel, cfg.touch_mode, cfg.project or "--",
            cfg.serial.mode or "--", cfg.panel_source or "--")
    end
    -- PANEL,RESET# 清掉调试口的面板覆盖，回到 PROJECT 出厂配置（出厂前必做）
    if command == "PANEL,RESET" then
        if reboot_pending or require("air8801_factory").busy() then return "PANEL=FAIL,BUSY" end
        local ok, reason = cfg.clear_panel()
        if not ok then return "PANEL=FAIL," .. reason end
        reboot_pending = true
        sys.timerStart(rtos.reboot, 500)
        return "PANEL=RESET,REBOOT"
    end
    if command == "TP_CAL?" then return exwin and ("TP_CAL=" .. require("air8801_touch_cal").status) or "TP_CAL=NOT_READY" end
    if command == "TP_CAL" then
        local tp = require("air8801_touch")
        if not tp.enabled() then return "TP_CAL=FAIL,NO_TOUCH" end
        if not exwin or not tp.ready() then return "TP_CAL=FAIL,NOT_READY" end
        local ok, reason = require("air8801_touch_cal").open()
        return ok and "TP_CAL=RUNNING" or ("TP_CAL=FAIL," .. tostring(reason))
    end
    -- PANEL,<profile>,<touch>#：profile 只收 [0-9a-z]（如 1024x600），touch 收 resistive/capacitive/none
    local panel, touch = command:match("^PANEL,([0-9a-z]+),([a-z]+)$")
    if panel then
        if reboot_pending or require("air8801_factory").busy() then return "PANEL=FAIL,BUSY" end
        local ok, reason = cfg.save_panel(panel, touch)
        if not ok then return "PANEL=FAIL," .. reason end
        reboot_pending = true
        sys.timerStart(rtos.reboot, 500)
        return "PANEL=SAVED,REBOOT"
    end
    return "ERROR=UNKNOWN_COMMAND"
end

if not _G.is_pc then
    channel = bridge.attach(function(data)
        buffer = buffer .. data
        while true do
            local stop = buffer:find("#", 1, true)
            if not stop then break end
            local command = buffer:sub(1, stop - 1):match("^%s*(.-)%s*$")
            buffer = buffer:sub(stop + 1)
            if #command <= 64 then
                sys.taskInit(function()
                    local ok, result = pcall(reply, command)
                    if not ok then log.error("air8801_debug", result) end
                    channel.write((ok and result or "ERROR=HANDLER") .. "#")
                end)
            end
        end
        if #buffer > 64 then buffer = "" end
    end)
end
