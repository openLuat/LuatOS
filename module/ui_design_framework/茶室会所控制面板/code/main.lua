--[[
松风阁 · 茶室会所控制面板（1024×600）
启动顺序：fskv -> 硬件（LCD/AirUI/触摸/背光） -> 界面
]]

PROJECT = "tea_house_8607"
VERSION = "1.0.0"
log.info("main", PROJECT, VERSION)

-- sys 是固件内置全局库，不要写 local sys = require "sys"
sys.taskInit(function()
    sys.wait(50)

    if fskv then
        local ok = pcall(fskv.init)
        log.info("main", "fskv.init", ok)
    end

    local hw = require "hardware"
    if not hw.init() then
        log.error("main", "硬件初始化失败：请确认固件含 airui + exd_jd9165ba_rgb 所需能力")
        return
    end

    -- 界面构建兜底：任何异常都要打印，避免"黑屏无线索"
    local ui = require "ui"
    local ok, err = pcall(ui.start)
    if not ok then
        log.error("main", "界面构建失败", tostring(err))
        return
    end

    local S = require "app_state"
    log.info("main", "启动完成", S.theme, S.bright, "开", S.count_on(), "路")
end)

sys.run()
