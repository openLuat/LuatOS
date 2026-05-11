-- Naming: local fn=2-5ch, local var=2-4ch, log tag="wcw"
--[[
@module  wifi_connect_win
@summary WiFi连接窗口（UI层，事件驱动）- 自适应分辨率
@version 1.1
@date    2026.04.16
@author  江访
]]

local SCREEN_W, SCREEN_H = 480, 800
local MARGIN = 15
local TITLE_H = math.floor(60 * _G.density_scale)
local BUTTON_H = 50
local SPACING = 10

local COLOR_PRIMARY        = 0x007AFF
local COLOR_PRIMARY_DARK   = 0x0056B3
local COLOR_BG             = 0xF5F5F5
local COLOR_CARD           = 0xFFFFFF
local COLOR_TEXT           = 0x333333
local COLOR_TEXT_SECONDARY = 0x757575
local COLOR_DIVIDER        = 0xE0E0E0
local COLOR_WHITE          = 0xFFFFFF

local function uscr()
    local rot = airui.get_rotation()
    local pw, ph = lcd.getSize()
    if rot == 0 or rot == 180 then
        SCREEN_W, SCREEN_H = pw, ph
    else
        SCREEN_W, SCREEN_H = ph, pw
    end
    MARGIN = math.floor(SCREEN_W * 0.03)
    TITLE_H = math.floor(60 * _G.density_scale)
    BUTTON_H = math.floor(SCREEN_H * 0.0625)
    SPACING = math.floor(SCREEN_W * 0.02)
end

local wid = nil
local cmc = nil
local ccw = nil
local cwk = nil
local cpt = nil
local pti = nil
local pii = nil
local cac = nil
local cfs = false

local ccfg = {
    wifi_enabled = false,
    ssid = "",
    password = "",
    need_ping = true,
    local_network_mode = false,
    ping_ip = "",
    ping_time = "10000",
    auto_socket_switch = true
}

local function ccrs(d)
    ccfg = d.config
    log.info("wcw", "配置加载完成:", json.encode(ccfg))

    if cfs and cpt and ccw then
        if ccfg.ssid == ccw.ssid then
            cpt:set_text(ccfg.password or "")
            cac.need_ping = ccfg.need_ping ~= nil and ccfg.need_ping or true
            cac.local_network_mode = ccfg.local_network_mode ~= nil and ccfg.local_network_mode or false
            cac.ping_ip = ccfg.ping_ip or ""
            cac.ping_time = ccfg.ping_time or "10000"
            cac.auto_socket_switch = ccfg.auto_socket_switch ~= nil and ccfg.auto_socket_switch or true
        end
    end
end

local function ccui()
    uscr()

    local cfg
    if cfs and ccw then
        cfg = {
            need_ping = ccw.need_ping ~= nil and ccw.need_ping or true,
            local_network_mode = ccw.local_network_mode ~= nil and ccw.local_network_mode or false,
            ping_ip = ccw.ping_ip or "",
            ping_time = ccw.ping_time or "10000",
            auto_socket_switch = ccw.auto_socket_switch ~= nil and ccw.auto_socket_switch or true
        }
    elseif cfs and ccfg then
        cfg = ccfg
    else
        cfg = {
            need_ping = true,
            local_network_mode = false,
            ping_ip = "",
            ping_time = "10000",
            auto_socket_switch = true
        }
    end

    cac = {
        need_ping = cfg.need_ping,
        local_network_mode = cfg.local_network_mode,
        ping_ip = cfg.ping_ip,
        ping_time = cfg.ping_time,
        auto_socket_switch = cfg.auto_socket_switch
    }

    cmc = airui.container({
        x = 0, y = 0,
        w = SCREEN_W, h = SCREEN_H,
        color = COLOR_BG,
    })

    -- 标题栏
    local tb = airui.container({
        parent = cmc,
        x = 0, y = 0,
        w = SCREEN_W, h = TITLE_H,
        color = COLOR_PRIMARY,
    })
    local bb = airui.container({
        parent = tb,
        x = math.floor(10 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = math.floor(50 * _G.density_scale), h = TITLE_H - math.floor(20 * _G.density_scale),
        color = COLOR_PRIMARY,
        on_click = function()
            exwin.close(wid)
        end
    })
    airui.label({
        parent = bb,
        x = 0, y = math.floor(5 * _G.density_scale),
        w = math.floor(50 * _G.density_scale), h = math.floor(30 * _G.density_scale),
        text = "<",
        font_size = math.floor(28 * _G.density_scale),
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = tb,
        text = ccw and ccw.ssid or "未知",
        x = 0, y = math.floor(15 * _G.density_scale),
        w = SCREEN_W, h = math.floor(30 * _G.density_scale),
        font_size = math.floor(24 * _G.density_scale),
        color = COLOR_CARD,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 键盘
    cwk = airui.keyboard({
        parent = cmc,
        x = 0, y = 0,
        w = SCREEN_W, h = math.floor(200 * _G.density_scale),
        mode = "text",
        auto_hide = true,
        preview = true,
        on_commit = function(self) self:hide() end,
    })

    -- 可滚动内容容器
    local con = airui.container({
        parent = cmc,
        x = 0, y = TITLE_H,
        w = SCREEN_W, h = SCREEN_H - TITLE_H - math.floor(80 * _G.density_scale),
        color = COLOR_BG,
        scroll = true
    })

    -- 密码区域
    airui.label({
        parent = con,
        text = "WiFi 密码",
        x = MARGIN + math.floor(5 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = math.floor(200 * _G.density_scale), h = math.floor(25 * _G.density_scale),
        font_size = math.floor(18 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT,
    })
    local pc = airui.container({
        parent = con,
        x = MARGIN, y = math.floor(40 * _G.density_scale),
        w = SCREEN_W - 2 * MARGIN, h = math.floor(80 * _G.density_scale),
        color = COLOR_CARD, radius = 8,
    })
    cpt = airui.textarea({
        parent = pc,
        x = math.floor(10 * _G.density_scale), y = math.floor(15 * _G.density_scale),
        w = SCREEN_W - 2 * MARGIN - math.floor(20 * _G.density_scale), h = math.floor(50 * _G.density_scale),
        text = ccw and ccw.password or "",
        placeholder = "请输入WiFi密码",
        max_len = 64,
        font_size = math.floor(22 * _G.density_scale),
        color = COLOR_TEXT,
        keyboard = cwk,
    })

    -- 高级配置
    airui.label({
        parent = con,
        text = "高级配置",
        x = MARGIN + math.floor(5 * _G.density_scale), y = math.floor(130 * _G.density_scale),
        w = math.floor(200 * _G.density_scale), h = math.floor(25 * _G.density_scale),
        font_size = math.floor(18 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT,
    })
    local ac = airui.container({
        parent = con,
        x = MARGIN, y = math.floor(160 * _G.density_scale),
        w = SCREEN_W - 2 * MARGIN, h = math.floor(330 * _G.density_scale),
        color = COLOR_CARD, radius = 8,
    })

    local yo = math.floor(15 * _G.density_scale)
    local rw = SCREEN_W - 2 * MARGIN - math.floor(20 * _G.density_scale)

    -- need_ping 开关行
    local npr = airui.container({
        parent = ac,
        x = math.floor(10 * _G.density_scale), y = yo,
        w = rw, h = math.floor(45 * _G.density_scale),
        color = COLOR_CARD, radius = 4,
    })
    airui.label({
        parent = npr,
        text = "网络连通检测",
        x = math.floor(10 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = math.floor(200 * _G.density_scale), h = math.floor(25 * _G.density_scale),
        font_size = math.floor(20 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT,
    })
    airui.switch({
        parent = npr,
        x = rw - math.floor(80 * _G.density_scale), y = math.floor(8 * _G.density_scale),
        w = math.floor(70 * _G.density_scale), h = math.floor(29 * _G.density_scale),
        checked = cac.need_ping,
        on_change = function(self)
            cac.need_ping = self:get_state()
        end
    })
    yo = yo + math.floor(55 * _G.density_scale)

    -- 局域网模式开关
    local lmr = airui.container({
        parent = ac,
        x = math.floor(10 * _G.density_scale), y = yo,
        w = rw, h = math.floor(45 * _G.density_scale),
        color = COLOR_CARD, radius = 4,
    })
    airui.label({
        parent = lmr,
        text = "局域网模式",
        x = math.floor(10 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = math.floor(200 * _G.density_scale), h = math.floor(25 * _G.density_scale),
        font_size = math.floor(20 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT,
    })
    airui.switch({
        parent = lmr,
        x = rw - math.floor(80 * _G.density_scale), y = math.floor(8 * _G.density_scale),
        w = math.floor(70 * _G.density_scale), h = math.floor(29 * _G.density_scale),
        checked = cac.local_network_mode,
        on_change = function(self)
            cac.local_network_mode = self:get_state()
        end
    })
    yo = yo + math.floor(55 * _G.density_scale)

    -- 检测间隔输入
    local ptr = airui.container({
        parent = ac,
        x = math.floor(10 * _G.density_scale), y = yo,
        w = rw, h = math.floor(45 * _G.density_scale),
        color = COLOR_CARD, radius = 4,
    })
    airui.label({
        parent = ptr,
        text = "检测间隔 (ms)",
        x = math.floor(10 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = math.floor(150 * _G.density_scale), h = math.floor(25 * _G.density_scale),
        font_size = math.floor(20 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT,
    })
    pti = airui.textarea({
        parent = ptr,
        x = rw - math.floor(120 * _G.density_scale), y = math.floor(8 * _G.density_scale),
        w = math.floor(110 * _G.density_scale), h = math.floor(29 * _G.density_scale),
        text = cac.ping_time,
        placeholder = "10000",
        max_len = 10,
        font_size = math.floor(18 * _G.density_scale),
        color = COLOR_TEXT,
        keyboard = cwk,
    })
    yo = yo + math.floor(55 * _G.density_scale)

    -- 检测IP输入
    local pir = airui.container({
        parent = ac,
        x = math.floor(10 * _G.density_scale), y = yo,
        w = rw, h = math.floor(45 * _G.density_scale),
        color = COLOR_CARD, radius = 4,
    })
    airui.label({
        parent = pir,
        text = "检测IP",
        x = math.floor(10 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = math.floor(100 * _G.density_scale), h = math.floor(25 * _G.density_scale),
        font_size = math.floor(20 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT,
    })
    pii = airui.textarea({
        parent = pir,
        x = rw - math.floor(170 * _G.density_scale), y = math.floor(8 * _G.density_scale),
        w = math.floor(160 * _G.density_scale), h = math.floor(29 * _G.density_scale),
        text = cac.ping_ip,
        placeholder = "可选",
        max_len = 32,
        font_size = math.floor(18 * _G.density_scale),
        color = COLOR_TEXT,
        keyboard = cwk,
    })
    yo = yo + math.floor(55 * _G.density_scale)

    -- 自动切换连接开关
    local asr = airui.container({
        parent = ac,
        x = math.floor(10 * _G.density_scale), y = yo,
        w = rw, h = math.floor(45 * _G.density_scale),
        color = COLOR_CARD, radius = 4,
    })
    airui.label({
        parent = asr,
        text = "自动切换连接",
        x = math.floor(10 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = math.floor(200 * _G.density_scale), h = math.floor(25 * _G.density_scale),
        font_size = math.floor(20 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT,
    })
    airui.switch({
        parent = asr,
        x = rw - math.floor(80 * _G.density_scale), y = math.floor(8 * _G.density_scale),
        w = math.floor(70 * _G.density_scale), h = math.floor(29 * _G.density_scale),
        checked = cac.auto_socket_switch,
        on_change = function(self)
            cac.auto_socket_switch = self:get_state()
        end
    })

    -- 底部按钮
    local bc = airui.container({
        parent = cmc,
        x = 0, y = SCREEN_H - math.floor(80 * _G.density_scale),
        w = SCREEN_W, h = math.floor(80 * _G.density_scale),
        color = COLOR_BG,
    })
    local bw = math.floor((SCREEN_W - 2 * MARGIN - SPACING) / 2)
    airui.button({
        parent = bc,
        x = MARGIN, y = math.floor(15 * _G.density_scale),
        w = bw, h = BUTTON_H,
        text = "取消",
        on_click = function()
            exwin.close(wid)
        end
    })
    airui.button({
        parent = bc,
        x = MARGIN + bw + SPACING, y = math.floor(15 * _G.density_scale),
        w = bw, h = BUTTON_H,
        text = "连接",
        style = {
            bg_color = COLOR_PRIMARY, bg_opa = 255,
            text_color = COLOR_WHITE,
            pressed_bg_color = COLOR_PRIMARY_DARK,
            pressed_text_color = COLOR_WHITE,
        },
        on_click = function()
            local pwd = cpt:get_text()
            if not pwd or pwd == "" then
                airui.msgbox({
                    text = "请输入WiFi密码",
                    buttons = { "确定" },
                    on_action = function(self) self:destroy() end
                })
                return
            end
            if #pwd < 8 then
                airui.msgbox({
                    text = "WiFi密码长度至少需要8位",
                    buttons = { "确定" },
                    on_action = function(self) self:destroy() end
                })
                return
            end

            cac.ping_time = pti:get_text()
            cac.ping_ip = pii:get_text()

            local ptn = tonumber(cac.ping_time)
            if not ptn or ptn <= 0 then
                airui.msgbox({
                    text = "检测间隔必须是正整数，请重新输入",
                    buttons = { "确定" },
                    on_action = function(self) self:destroy() end
                })
                return
            end

            sys.publish("WIFI_CONNECT_REQ", {
                ssid = ccw and ccw.ssid,
                password = pwd,
                advanced_config = cac
            })

            if cfs then
                sys.publish("CLOSE_WIFI_SAVED_LIST_WIN")
            end

            if wid then
                exwin.close(wid)
            end
        end
    })
end

local function ccoc(ssid)
    log.info("wcw", "WiFi连接成功:", ssid)
end

local function cdsc(rs, cd)
    log.info("wcw", "WiFi连接失败:", rs, cd)
end

local function ccre()
    sys.publish("WIFI_GET_CONFIG_REQ")
    ccui()
    sys.subscribe("WIFI_CONNECTED", ccoc)
    sys.subscribe("WIFI_DISCONNECTED", cdsc)
    sys.subscribe("WIFI_CONFIG_RSP", ccrs)
end

local function cdst()
    sys.unsubscribe("WIFI_CONNECTED", ccoc)
    sys.unsubscribe("WIFI_DISCONNECTED", cdsc)
    sys.unsubscribe("WIFI_CONFIG_RSP", ccrs)
    if cmc then
        cmc:destroy()
        cmc = nil
    end
    wid = nil
    ccw = nil
    cwk = nil
    cpt = nil
    pti = nil
    pii = nil
    cac = nil
    cfs = false
end

local function cgfc() end
local function clfc() end

local function open(wd, fs)
    if type(wd) == "table" then
        ccw = wd
    else
        ccw = {ssid = wd}
    end
    cfs = fs or false
    if not exwin.is_active(wid) then
        wid = exwin.open({
            on_create = ccre,
            on_destroy = cdst,
            on_get_focus = cgfc,
            on_lose_focus = clfc,
        })
    end
end

sys.subscribe("OPEN_WIFI_CONNECT_WIN", open)
