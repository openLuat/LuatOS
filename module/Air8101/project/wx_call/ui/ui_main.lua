--[[
@module  ui_main
@summary 界面总装：顶栏 + 主页 + 语音页 + 视频页 + 提示浮层
@version 1.2.0
@date    2026.10.21
@usage
  ui_main.build()   -- 必须在 lcd_drv.init() 之后调用
]]

local T       = require "ui_theme"
local status  = require "ui_status"
local idle    = require "ui_idle"
local uicall  = require "ui_call"

local M = {}

local pages = {}
local built = false

local toast, toast_label, toast_seq = nil, nil, 0

--- 页面切换（容器叠放 + set_hidden）
-- @param name "idle" / "voice" / "video"
function M.show(name)
    if not pages[name] then return end
    for k, v in pairs(pages) do
        v:set_hidden(k ~= name)
    end
end

local function show_toast(msg)
    if not toast then return end
    toast_seq = toast_seq + 1
    local seq = toast_seq
    toast_label:set_text(msg)
    toast:set_hidden(false)
    sys.taskInit(function()
        sys.wait(2500)
        if toast_seq == seq then toast:set_hidden(true) end
    end)
end

local function build_toast(root)
    local W, H = UI_W or 1024, UI_H or 600
    toast = airui.container({
        parent = root, x = (W - 460) // 2, y = H - 150,
        w = 460, h = 58, color = 0x2A1A0A, radius = 29,
    })
    pcall(function() toast:set_border_color(T.ORANGE, 1) end)
    toast_label = airui.label({
        parent = toast, text = "", x = 0, y = 0, w = 460, h = 58,
        font = "hzfont", font_size = 17, color = T.ORANGE_LT, align = airui.TEXT_ALIGN_CENTER,
    })
    toast:set_hidden(true)
end

--- 构建界面
function M.build()
    if built then return end
    built = true

    local W, H = UI_W or 1024, UI_H or 600

    local root = airui.container({ x = 0, y = 0, w = W, h = H, color = T.BG })

    -- 顶部状态栏（始终显示）
    status.create(root)

    -- 主页
    pages.idle = airui.container({ parent = root, x = 0, y = 88, w = W, h = H - 88, color = T.BG })
    idle.create(pages.idle)

    -- 两个通话页
    local cp = uicall.create(root)
    pages.voice = cp.voice
    pages.video = cp.video

    -- 提示浮层（最后创建，盖在所有页面之上）
    build_toast(root)

    M.show("idle")
    uicall.set_state("idle", "voice", "")
    uicall.set_media(false, true, true)

    -- 通话状态分发
    sys.subscribe("CALL_STATE", function(state, mode, peer)
        if state == "idle" then
            uicall.set_state("idle", mode, peer)
            M.show("idle")
        else
            M.show(mode == "video" and "video" or "voice")
            uicall.set_state(state, mode, peer)
        end
    end)

    sys.subscribe("CALL_TICK", function(sec)
        uicall.set_timer(sec)
    end)

    sys.subscribe("CALL_MEDIA", function(muted, speaker, camera)
        uicall.set_media(muted, speaker, camera)
    end)

    sys.subscribe("UI_TOAST", show_toast)

    sys.subscribe("CALL_SERVICE_READY", function(backend)
        if backend == "tc" then
            log.info("ui_main", "微信通话后端已就绪")
        else
            log.info("ui_main", "本地演示模式（无 tc_iot 或未配置凭证）")
        end
    end)

    log.info("ui_main", "ui ready", W, H)
    sys.publish("UI_READY")
end

return M
