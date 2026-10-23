--[[
@module  weather_set_win
@summary 城市设置页（内置城市列表选择，即时生效）（8301出厂固件）
@version 1.0
@date    2026.10.10
@author  江访

@usage
入口：业务模式主页（idle_win）天气卡的城市名 → OPEN_WEATHER_SET_WIN。

页面内容（480×272，内容区 464×210）：
  1、提示行：当前城市
  2、城市列表（每页 6 行，行内：城市名 + 经纬度），点击即选中并保存
     - 当前选中的城市以品牌浅蓝底 + 品牌蓝文字高亮
  3、底部翻页条：上一页 / 页码 / 下一页

数据来源：
  weather_app.get_cities()   内置城市表（{名称, 纬度, 经度} 数组）
  weather_app.get_city()     当前城市名
  WEATHER_UPDATE(state)      天气数据更新（城市变更后的实时刷新）

交互：
  点击城市行 → 发布 WEATHER_CITY_SET(name)
             → weather_app 保存到 fskv 并立即刷新天气
             → 本页订阅 WEATHER_UPDATE 同步「当前城市」提示行与高亮行

@note 城市表只有一份（在 weather_app 内置），本页通过外部接口读取，避免重复定义。
@note airui.container 无滚动能力，故以「分页」替代滑动条（与 wifi_win 扫描结果同范式）。
]]

local theme = require "ui_theme"
local weather = require "weather_app"

local win_id = nil
local main_container
local layout                  -- theme.page 返回的内容区几何
local list_box                -- 城市列表容器
local row_handles = {}        -- 城市行句柄（固定 PAGE_SIZE 行：{row, title, right}，渲染时更新）
local city_label              -- 提示行的当前城市数值标签
local page_label              -- 翻页条的页码标签

local render                  -- 列表渲染（前置声明，供交互回调引用）
local select_city             -- 选中城市（前置声明，供行回调引用）

local cities = {}             -- 内置城市表（{名称, 纬度, 经度}）
local cur_city = ""           -- 当前选中城市名
local cur_page = 1            -- 当前页码（从 1 起）

-- ==================== 布局常量 ====================
-- 内容区 464×210 = 提示行 30 + 4 + 列表 6×24 + 4 + 翻页条 28
local HINT_H  = 30
local ROW_H   = 24
local GAP     = 4
local PAGE_SIZE = 6
local BTN_W   = 100
local BTN_H   = 28
local LH      = 19            -- 16px 字号的行盒高（字号 + 3）

local list_y, list_h          -- 列表区几何（render 复用）

-- ==================== 数据加工 ====================

--[[总页数

@local
@function total_pages
@return number 总页数（至少 1）
]]
local function total_pages()
    local n = #cities
    if n == 0 then return 1 end
    return math.floor((n + PAGE_SIZE - 1) / PAGE_SIZE)
end

--[[应用一行城市数据（文字 + 选中态配色）

@local
@function apply_row
@param h table 行句柄 {row, title, right}
@param c table|nil 城市数据 {名称, 纬度, 经度}；nil 表示该行留空
]]
local function apply_row(h, c)
    -- 城市记录为位置数组 {名称, 纬度, 经度}（weather_app 内置表定义）
    local name, lat, lng
    if c then name, lat, lng = c[1], c[2], c[3] end
    local selected = name and (name == cur_city)
    h.title:set_text(name or "")
    h.right:set_text(name and string.format("%.2f,%.2f", lat, lng) or "")
    h.title:set_color(selected and theme.C.brand or theme.C.t1)
    h.right:set_color(selected and theme.C.brand_deep or theme.C.t3)
    -- 容器换色无稳定 ABI，做存在性判断 + pcall 保护，失败不影响文字刷新
    if h.row.set_color then
        pcall(function() h.row:set_color(selected and theme.C.brand_soft or theme.C.panel, 255) end)
    end
    if h.row.set_border_color then
        pcall(function() h.row:set_border_color(selected and theme.C.brand or theme.C.stroke_soft, 1) end)
    end
end

--[[生成城市行点击回调（工厂函数：按值捕获行索引，避免循环变量捕获问题）
说明：城市行固定创建（每页 PAGE_SIZE 行），回调按「行索引 + 当前页」解析目标城市，
      渲染时只更新行内容、不重建行，避免在触摸回调中销毁触发对象。

@local
@function make_row_handler
@param index number 行索引（1~PAGE_SIZE）
@return function 点击回调
]]
local function make_row_handler(index)
    return function()
        if not exwin.is_active(win_id) then return end
        local c = cities[(cur_page - 1) * PAGE_SIZE + index]
        if c then select_city(c[1]) end
    end
end

-- ==================== 渲染 ====================

--[[按当前页与选中态刷新城市列表（只更新行内容，不重建行）与提示行 / 页码

@local
@function render
]]
function render()
    if not main_container then return end

    local pages = total_pages()
    if cur_page > pages then cur_page = pages end
    if cur_page < 1 then cur_page = 1 end

    for i = 1, PAGE_SIZE do
        local h = row_handles[i]
        if h then
            apply_row(h, cities[(cur_page - 1) * PAGE_SIZE + i])
        end
    end

    if city_label then
        city_label:set_text((cur_city ~= "") and cur_city or "--")
    end
    if page_label then
        page_label:set_text(tostring(cur_page) .. " / " .. tostring(pages))
    end
end

--[[选中某城市：更新本地状态、发布设置并刷新列表

@local
@function select_city
@param name string 城市名
]]
function select_city(name)
    if name == cur_city then return end
    cur_city = name
    -- 发布城市设置：weather_app 保存到 fskv 并立即刷新天气
    sys.publish("WEATHER_CITY_SET", name)
    if city_label then city_label:set_text(name) end
    render()
end

-- ==================== 交互回调 ====================

--[[导航栏返回按钮点击

@local
@function on_back_click
]]
local function on_back_click()
    if not exwin.is_active(win_id) then return end
    exwin.close(win_id)
end

--[[上一页

@local
@function on_prev_click
]]
local function on_prev_click()
    if cur_page > 1 then
        cur_page = cur_page - 1
        render()
    end
end

--[[下一页

@local
@function on_next_click
]]
local function on_next_click()
    if cur_page < total_pages() then
        cur_page = cur_page + 1
        render()
    end
end

--[[天气数据更新：同步当前城市（本页操作 / 其它来源变更都会触发）

@local
@function on_weather_update
@param st table weather_app 发布的状态表
]]
local function on_weather_update(st)
    if type(st) ~= "table" then return end
    if type(st.city) == "string" and st.city ~= "" and st.city ~= cur_city then
        cur_city = st.city
        if exwin.is_active(win_id) then render() end
    end
end

-- ==================== UI 构建 ====================

--[[创建城市设置页 UI

@local
@function create_ui
]]
local function create_ui()
    local ctx = theme.page({ title = "城市设置", on_back = on_back_click })
    main_container = ctx.base
    layout = ctx

    -- 提示行：当前城市
    local y = ctx.y
    local _, val = theme.kv_row(ctx.base, {
        x = ctx.x, y = y, w = ctx.w, h = HINT_H,
        label = "当前城市", value = (cur_city ~= "") and cur_city or "--",
        value_color = theme.C.primary,
    })
    city_label = val
    y = y + HINT_H + GAP

    -- 列表区（固定创建 PAGE_SIZE 行，渲染时只更新内容）
    list_y = y
    list_h = PAGE_SIZE * ROW_H
    list_box = theme.box(ctx.base, { x = ctx.x, y = list_y, w = ctx.w, h = list_h })
    row_handles = {}
    for i = 1, PAGE_SIZE do
        local row, title, right = theme.row(list_box, {
            x = 0, y = (i - 1) * ROW_H, w = ctx.w, h = ROW_H,
            text = "", right = "",
            right_w = 120, right_px = theme.fs("small"),
            color = theme.C.panel, border = theme.C.stroke_soft,
            text_color = theme.C.t1, right_color = theme.C.t3,
            on_click = make_row_handler(i),
        })
        row_handles[i] = { row = row, title = title, right = right }
    end
    y = y + list_h + GAP

    -- 翻页条：上一页 / 页码 / 下一页
    theme.ghost(ctx.base, {
        x = ctx.x, y = y, w = BTN_W, h = BTN_H,
        text = "上一页", on_click = on_prev_click,
    })
    page_label = theme.label(ctx.base, {
        x = ctx.x + BTN_W + 6, y = y + math.floor((BTN_H - LH) / 2),
        w = ctx.w - 2 * BTN_W - 12, h = LH,
        text = "1 / 1", px_size = theme.fs("body"), color = theme.C.t2,
        align = airui.TEXT_ALIGN_CENTER,
    })
    theme.ghost(ctx.base, {
        x = ctx.x + ctx.w - BTN_W, y = y, w = BTN_W, h = BTN_H,
        text = "下一页", on_click = on_next_click,
    })

    render()
end

-- ==================== 窗口生命周期 ====================

--[[窗口创建回调

@local
@function on_create
]]
local function on_create()
    log.info("weather_set_win", "[UI-MARK] 城市设置页 v1.0 已加载")
    cities = weather.get_cities() or {}
    cur_city = weather.get_city() or ""
    cur_page = 1
    create_ui()
    sys.subscribe("WEATHER_UPDATE", on_weather_update)
end

--[[窗口销毁回调

@local
@function on_destroy
]]
local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    layout = nil
    list_box = nil
    row_handles = {}
    city_label = nil
    page_label = nil
    sys.unsubscribe("WEATHER_UPDATE", on_weather_update)
    win_id = nil
end

--[[窗口获得焦点回调：同步一次当前城市

@local
@function on_get_focus
]]
local function on_get_focus()
    cur_city = weather.get_city() or cur_city
    render()
end

--[[窗口失去焦点回调

@local
@function on_lose_focus
]]
local function on_lose_focus() end

--[[OPEN_WEATHER_SET_WIN 消息处理器（单实例保护）

@local
@function open_handler
]]
local function open_handler()
    if win_id and exwin.is_active(win_id) then return end
    if win_id then
        exwin.close(win_id)
        win_id = nil
    end
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

sys.subscribe("OPEN_WEATHER_SET_WIN", open_handler)
