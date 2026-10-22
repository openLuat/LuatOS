--[[
@module  ui_idle
@summary 主页（1024x600）：设备状态卡 + 语音通话 / 视频通话两个入口
@version 1.2.0
@date    2026.10.21
]]

local T    = require "ui_theme"
local cfg  = require "hw_config"
local net  = require "net_mgr"
local cam  = require "usb_cam"
local wx   = require "wx_call"
local call = require "call_mgr"

local M = {}

local dot_net, lbl_net
local dot_cam, lbl_cam
local dot_wx, lbl_wx

-- 脏检查缓存：状态没变不重绘
local last_net, last_cam, last_wx

local function box(parent, x, y, w, h, color, radius)
    return airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = color, radius = radius or 0,
    })
end

local function text(parent, str, x, y, w, h, size, color, align)
    return airui.label({
        parent = parent, text = str, x = x, y = y, w = w, h = h,
        font = "hzfont", font_size = size, color = color,
        align = align or airui.TEXT_ALIGN_LEFT,
    })
end

local function state_row(card, y, key)
    text(card, key, 22, y, 84, 24, 16, T.TEXT_DIM)
    local dot = box(card, 124, y + 8, 10, 10, T.LINE, 5)
    local val = text(card, "--", 144, y - 2, 124, 26, 18, T.TEXT)
    return dot, val
end

local CAM_STATE = {
    online      = { T.GREEN, "在线" },
    warming     = { T.YELLOW, "预热中" },
    offline     = { T.RED, "未连接" },
    disabled    = { T.YELLOW, "已关闭" },
    unsupported = { T.YELLOW, "不支持" },
}

local WX_STATE = {
    offline    = { T.TEXT_DIM, "未就绪" },
    idle       = { T.GREEN, "空闲" },
    connecting = { T.YELLOW, "连接中" },
    ringing    = { T.ORANGE, "来电" },
    talking    = { T.ORANGE, "通话中" },
}

local function apply_cam(state)
    if state == last_cam then return end
    last_cam = state
    local m = CAM_STATE[state] or { T.TEXT_DIM, "检测中" }
    if dot_cam then dot_cam:set_color(m[1]) end
    if lbl_cam then lbl_cam:set_text(m[2]) end
end

local function apply_wx(state)
    if state == last_wx then return end
    last_wx = state
    local m = WX_STATE[state] or { T.TEXT_DIM, wx.name(state) }
    if dot_wx then dot_wx:set_color(m[1]) end
    if lbl_wx then lbl_wx:set_text(m[2]) end
end

local function apply_net(n)
    local ready = n and n.ready
    local txt = ready and (n.ip or "已连接") or "未连接"
    if txt == last_net then return end
    last_net = txt
    if dot_net then dot_net:set_color(ready and T.GREEN or T.RED) end
    if lbl_net then lbl_net:set_text(txt) end
end

-- 大按钮：整块可点，图标 + 主标题 + 英文副标题 + 胶囊提示
local function action_card(page, x, icon, title, sub, mode)
    local c = box(page, x, 26, 311, 410, T.CARD, 26)
    pcall(function() c:set_border_color(T.ORANGE_PALE, 2) end)

    local circle = airui.container({
        parent = c, x = 80, y = 54, w = 150, h = 150,
        color = T.ORANGE, radius = 75,
    })
    airui.label({
        parent = circle, text = "", symbol = icon, x = 0, y = 0, w = 150, h = 150,
        font = "hzfont", font_size = 64, color = T.DARK_TEXT, align = airui.TEXT_ALIGN_CENTER,
    })

    text(c, title, 0, 238, 311, 44, 34, T.TEXT, airui.TEXT_ALIGN_CENTER)
    text(c, sub, 0, 292, 311, 22, 14, T.ORANGE_LT, airui.TEXT_ALIGN_CENTER)

    local pill = box(c, 90, 336, 130, 38, T.ORANGE_PALE, 19)
    text(pill, "点击发起", 0, 0, 130, 38, 15, T.ORANGE_LT, airui.TEXT_ALIGN_CENTER)

    local function tap()
        call.dial(mode)
    end

    -- 整块容器点击 + 图标区点击，双重保证触摸响应
    pcall(function() c:set_on_click(tap) end)
    pcall(function() circle:set_on_click(tap) end)

    return c
end

--- 创建主页
-- @param page 页面容器
function M.create(page)
    -- ================= 左侧设备状态 =================
    local info = box(page, 30, 26, 290, 410, T.CARD, 22)
    text(info, "设备状态", 22, 18, 200, 28, 20, T.ORANGE)

    local _, v_door = state_row(info, 66, "门禁")
    v_door:set_text("已布防")

    dot_net, lbl_net = state_row(info, 114, "网络")
    dot_cam, lbl_cam = state_row(info, 162, "摄像头")
    dot_wx, lbl_wx = state_row(info, 210, "微信")

    box(info, 22, 262, 246, 1, T.LINE)

    text(info, "设备编号", 22, 276, 160, 20, 13, T.TEXT_DIM)
    text(info, "DOOR-8101-01", 22, 298, 246, 26, 17, T.TEXT)

    text(info, "固件版本", 22, 334, 160, 20, 13, T.TEXT_DIM)
    text(info, cfg.version, 22, 356, 246, 26, 17, T.TEXT_SUB)

    -- ================= 两个通话入口 =================
    action_card(page, 346, airui.SYMBOL_CALL, "语音通话", "VOICE CALL", "voice")
    action_card(page, 683, airui.SYMBOL_VIDEO, "视频通话", "VIDEO CALL", "video")

    -- ================= 底部提示条 =================
    local foot = box(page, 30, 448, 964, 58, T.CARD, 16)
    box(foot, 22, 24, 10, 10, T.GREEN, 5)
    text(foot, "系统就绪 · 点击上方按钮发起语音 / 视频通话", 42, 17, 600, 24, 16, T.TEXT_SUB)
    text(foot, "AI 门禁 · " .. (PROJECT or "SmartDoor") .. "  " .. cfg.version,
        680, 17, 264, 24, 13, T.TEXT_DIM, airui.TEXT_ALIGN_RIGHT)

    -- ================= 状态刷新 =================
    sys.subscribe("NET_STATUS", apply_net)

    sys.subscribe("USB_CAM", apply_cam)
    sys.subscribe("WX_CALL_STATE", apply_wx)

    -- 初始值
    apply_cam(cam.state)
    apply_wx(wx.state)
    apply_net({ ready = net.ready, ip = net.ip })
end

return M
