--[[
@module  ui_idle
@summary 桌面：状态栏（时间 / 日期 / 网络）+ 应用宫格（分页）
@version 3.0
@date    2026.10.16
@usage
    sys.publish("OPEN_IDLE_WIN")

说明
1. 应用清单集中在 APPS 表里，加应用只需加一行 + 实现对应页面；
   `todo = true` 表示"还没实现"，点了给提示，方便先把入口摆出来；
2. 每页最多 PER_PAGE 个图标（4 列 × 2 行 = 8 个，5 寸 800×480 也能完整放下）；
   应用不超过一页时**不显示**底部分页条，超过一页才出现「上一页 / 下一页」，翻页只重建宫格区，状态栏不闪；
3. 状态栏时间/网络变化走 STATUS_UPDATED 事件，秒级刷新；
4. 布局全部用**设计坐标**（基准 800×480，ui_theme.SCREEN.DW），1000 级屏靠 ui_kit 自动放大。
]]

local exwin  = require "exwin"
local ui     = require "ui_kit"
local T      = require "ui_theme"
local status = require "app_status"

local C, F, S, G = T.COLOR, T.FONT, T.SCREEN, T.GAP
local DW = S.DW
local airui = airui

local COLS     = 4
local MAX_ROWS = 2           -- 一页 4 列 × 2 行 = 8 个：5 寸 800×480 上也放得下，不做 3 行
local PER_PAGE = COLS * MAX_ROWS
local TOP_H    = 76          -- 状态栏高度（设计值）
local GRID_Y   = TOP_H + 16
local CELL_H   = 124

-- ===== 应用清单：加应用只改这里 =====
-- 图标：/luadb/app_*.png（48×48，随脚本烧入）；没有图片时自动回落彩色圆角块 + 名称首字。
local APPS = {
    { name = "网络优先级", event = "OPEN_NET_WIN",   color = C.ICON_BLUE,   icon_path = "/luadb/app_network.png" },
    { name = "WiFi",     event = "OPEN_WIFI_WIN",    color = C.ICON_CYAN,   icon_path = "/luadb/app_wifi.png" },
    { name = "温湿度",   event = "OPEN_485_WIN",     color = C.ICON_SLATE,  icon_path = "/luadb/app_rs485.png" },
    { name = "空气质量", event = "OPEN_AIR_WIN",     color = C.ICON_GREEN,  icon_path = "/luadb/app_air.png" },

    -- 「设备信息」已下线（2026-10-19）：版本/型号在开机日志里就能看到，页面价值不大
    { name = "音频播放", event = "OPEN_AUDIO_WIN",   color = C.ICON_RED,    icon_path = "/luadb/app_audio.png" },
    { name = "摄像头",   event = "OPEN_CAM_WIN",     color = C.ICON_TEAL,   icon_path = "/luadb/app_camera.png" },
}

local win_id
local page
local time_label, date_label, net_label
local content_box
local refresh_status

-- 状态栏差量刷新：记住上次显示的文本，没变就不 set_text（避免无谓重排/重绘）
local last_time, last_date, last_net

local OPEN_GUARD_MS = 120
local open_blocked = false

--- 桌面下面是否已经有页面（有则视为"上次点击已生效"）
local function page_opened()
    if not win_id then return false end
    local kids = exwin.children_of(win_id)
    return kids and #kids > 0
end

local function open_app(item)
    if open_blocked then return end

    -- 占位项：只提示，提示条同样做去重（否则同一次触摸会连弹 2~3 次）
    if item.todo then
        open_blocked = true
        sys.timerStart(function() open_blocked = false end, OPEN_GUARD_MS)
        if page then page.toast("「" .. item.name .. "」将在后续版本提供") end
        return
    end

    if page_opened() then return end
    open_blocked = true
    sys.timerStart(function() open_blocked = false end, OPEN_GUARD_MS)
    -- 先让本次触摸事件走完，再创建页面：页面控件多，在回调栈里直接建会卡住输入
    sys.timerStart(function() sys.publish(item.event) end, 10)
end

-- 重绘宫格（翻页只动这块，状态栏不闪）
-- 当前 7 个应用一页放得下，不画底部「上一页 / 下一页」条；超过 PER_PAGE 再加回来
local function render_content()
    if content_box then
        pcall(function() content_box:destroy() end)
        content_box = nil
    end

    -- 留 4 设计像素余量：body 下方还有 px(2) 的兜底内边距，
    -- 宫格容器如果正好顶到 S.DH，AirUI 1.2.x 会在右侧画出一条滚动条。
    local box_h = S.DH - GRID_Y - 4
    content_box = ui.box({
        parent = page.body, x = 0, y = GRID_Y, w = DW, h = box_h, color = C.CARD,
    })

    -- 整页白底：状态栏 → 宫格区之间不再有浅灰过渡带（那条灰在白条和白卡之间很像阴影）
    ui.app_grid({
        parent = content_box, x = 0, y = 0, w = DW,
        items = APPS, page = 1, per_page = PER_PAGE, cols = COLS,
        cell_h = CELL_H,
        bg = C.CARD, cell_bg = C.CARD, cell_border = C.BORDER,
        on_open = open_app,
    })

end

-- ===== 状态栏（白底 + 底部细分隔线，清爽风）=====

local function build_status_bar()
    local bar = ui.box({ parent = page.body, x = 0, y = 0, w = DW, h = TOP_H, color = C.CARD })
    -- 分隔线四周留 1~2px：压在容器边缘时 LVGL 会画滚动条（px 取整更明显）
    ui.divider({ parent = bar, x = 1, y = TOP_H - 3, w = DW - 2 })

    time_label = ui.label({
        parent = bar, x = G.M, y = 14, w = 200, h = 52,
        text = "00:00", size = F.HUGE, color = C.TEXT,
    })
    date_label = ui.label({
        parent = bar, x = G.M + 210, y = 34, w = 300, h = 26,
        text = "1970-01-01", size = F.SMALL, color = C.TEXT_WEAK,
    })
    net_label = ui.label({
        parent = bar, x = DW - G.M - 300, y = 34, w = 300, h = 26,
        text = "未联网", size = F.SMALL, color = C.TEXT_SUB,
        align = airui.TEXT_ALIGN_RIGHT,
    })
end

refresh_status = function()
    if not (time_label and date_label and net_label) then return end

    local t = status.time_str()
    if t ~= last_time then time_label:set_text(t) last_time = t end

    local d = status.date_str() .. " " .. status.weekday_str()
    if d ~= last_date then date_label:set_text(d) last_date = d end

    local n = status.net_summary()
    if n ~= last_net then net_label:set_text(n) last_net = n end
end

-- ===== 生命周期 =====

local function on_create()
    page = ui.page({ bg = C.CARD })   -- 桌面：整页白底，无标题栏，顶部自绘状态栏
    build_status_bar()
    render_content()
    refresh_status()
    sys.subscribe("STATUS_UPDATED", refresh_status)
end

local function on_destroy()
    sys.unsubscribe("STATUS_UPDATED", refresh_status)
    if page then
        page.destroy()
        page = nil
    end
    time_label, date_label, net_label, content_box = nil, nil, nil, nil
    last_time, last_date, last_net = nil, nil, nil
    win_id = nil
end

sys.subscribe("OPEN_IDLE_WIN", function()
    win_id = exwin.open({
        on_create     = on_create,
        on_destroy    = on_destroy,
        on_get_focus  = refresh_status,
        on_lose_focus = function() end,
    })
end)
