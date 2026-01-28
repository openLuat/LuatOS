local setting_page = {}

local config = require("irtu_config")

local setting_container, detail_area, status_label
local need_refresh = true

local function safe_to_str(value)
    if value == nil then
        return "未配置"
    end
    if type(value) == "boolean" then
        return value and "是" or "否"
    end
    if type(value) == "table" then
        return json.encode(value)
    end
    return tostring(value)
end

local function format_table_entries(label, tbl)
    local lines = {}
    if type(tbl) == "table" then
        for idx, val in ipairs(tbl) do
            lines[#lines + 1] = string.format("%s[%d]: %s", label, idx, safe_to_str(val))
        end
    else
        lines[#lines + 1] = string.format("%s: %s", label, safe_to_str(tbl))
    end
    return lines
end

local function build_config_text()
    -- 获取配置
    log.info("setting_page", "build config text")
    local sheet = config.get()
    log.info("setting_page", "get config", sheet)
    if type(sheet) ~= "table" then
        log.warn("setting_page", "config table not ready")
        return "配置尚未准备好，请稍后再试"
    end
    local lines = {}
    local function add(name, value)
        lines[#lines + 1] = string.format("%-14s %s", name .. ":", safe_to_str(value))
    end
    -- 添加配置项
    -- add("ProductKey", sheet.project_key or PRODUCT_KEY)
    add("Host", sheet.host)
    add("Port", sheet.port)
    add("Passon", sheet.passon)
    -- add("Reg", sheet.reg)
    -- add("ParamVer", sheet.param_ver)
    -- add("Flow", sheet.flow)
    -- add("FOTA", sheet.fota)
    -- add("Log", sheet.log)
    -- add("IPv6", sheet.isipv6)
    -- add("WebProtect", sheet.webProtect)
    -- add("Rndis", sheet.isRndis)
    -- add("Rndis2", sheet.isRndis2)
    -- add("PwrMod", sheet.pwrmod)
    -- add("Password", sheet.password)
    -- log.info("setting_page", "add config items")
    if sheet.apn then
        for idx, value in ipairs(sheet.apn) do
            lines[#lines + 1] = string.format("APN[%d]: %s", idx, safe_to_str(value))
        end
    end
    if sheet.pins then
        for idx, value in ipairs(sheet.pins) do
            lines[#lines + 1] = string.format("PIN[%d]: %s", idx, safe_to_str(value))
        end
    end
    if sheet.uconf then
        for idx, entry in ipairs(sheet.uconf) do
            lines[#lines + 1] = string.format("UART[%d]: %s", idx, safe_to_str(entry))
        end
    end
    -- if sheet.conf then
    --     for idx, entry in ipairs(sheet.conf) do
    --         lines[#lines + 1] = string.format("CONF[%d]: %s", idx, safe_to_str(entry))
    --     end
    -- end
    -- if sheet.protectContent then
    --     lines[#lines + 1] = string.format("Protect count: %d", #sheet.protectContent)
    -- end
    -- if sheet.upprot then
    --     lines[#lines + 1] = string.format("UP协议数: %d", #sheet.upprot)
    -- end
    -- if sheet.dwprot then
    --     lines[#lines + 1] = string.format("DW协议数: %d", #sheet.dwprot)
    -- end
    -- if sheet.cmds then
    --     for idx, cmd in ipairs(sheet.cmds) do
    --         lines[#lines + 1] = string.format("CMD[%d]: %s", idx, safe_to_str(cmd))
    --     end
    -- end
    -- if sheet.gps then
    --     lines[#lines + 1] = "GPS配置: " .. safe_to_str(sheet.gps)
    -- end
    log.info("setting_page", "build config text done")
    return table.concat(lines, "\n")
end

local function refresh_config()
    log.info("setting_page", "refresh config")
    -- 更新状态标签
    if status_label then
        status_label:set_text("配置更新时间：" .. os.date("%H:%M:%S"))
    end
    log.info("setting_page", "update status label")
    -- 更新详情区域
    if detail_area then
        text = build_config_text()
        log.info("setting_page", "update detail area", text)
        detail_area:set_text(text)
    end
    need_refresh = false
    log.info("setting_page", "refresh config done")
end

function setting_page.create_page()
    log.info("setting_page", "create page")

    config.onUpdate(function()
        need_refresh = true
    end)

    setting_container = airui.container({
        x = 0, y = 0, w = 320, h = 480,
        color = 0xffffff,
    })

    airui.label({
        parent = setting_container,
        text = "iRTU 参数配置",
        x = 20, y = 10, w = 280, h = 32,
        font_size = 24,
    })

    status_label = airui.label({
        parent = setting_container,
        text = "读取配置中...",
        x = 20, y = 50, w = 280, h = 24,
    })

    detail_area = airui.textarea({
        parent = setting_container,
        x = 20, y = 90, w = 280, h = 320,
        read_only = true,
        auto_line_feed = true,
        text = "配置内容将显示在这里",
    })

    airui.button({
        parent = setting_container,
        text = "刷新",
        x = 60, y = 420, w = 80, h = 40,
        on_click = refresh_config,
    })

    airui.button({
        parent = setting_container,
        text = "返回",
        x = 180, y = 420, w = 80, h = 40,
        on_click = function()
            setting_container:hide()
        end,
    })

    setting_container:hide()
    return setting_container
end

function setting_page.show_page()
    log.info("setting_page", "show page")
    if not setting_container then
        log.info("setting_page", "create page")
        setting_page.create_page()
    end
    -- 刷新配置
    if need_refresh then
        log.info("setting_page", "config changed, refreshing")
        refresh_config()
    else
        log.info("setting_page", "config unchanged, skip refresh")
    end
    -- 打开页面
    log.info("setting_page", "open page")
    setting_container:open()
end

return setting_page

