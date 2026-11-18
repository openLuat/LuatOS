--[[
@module theme
@summary 车载电脑 HMI - 主题配色 / 页面工厂 / 顶栏 / 底栏 / 通用控件
        （BYD DiLink 风格，与 preview.html 一致，1024×600）
]]

local sys   = require "sys"
local exwin = require "exwin"

require "mock"   -- 全局 MOCK：页面共用数据（theme 顶栏/底栏也要读）

local theme = {}

--------------------------------------------------------------------
-- 图片资源探测
-- 本工程原来坚持「一切用 shape 画、不用 PNG」，但空调页座椅、车辆页整车
-- 用矩形拼出来确实太糙（用户反馈「太丑」），这两块改成贴图，图片放在
-- code/img/ 下随 luadb 一起下载。
-- 下载方式不同，落盘路径可能是 /luadb/img/ 也可能是 /luadb/，逐个探测；
-- 都找不到就返回 nil，由页面回退到原来的 shape 绘制——
-- lv_image 拿到不存在的路径会直接报错甚至花屏，不能盲传。
--------------------------------------------------------------------
theme.IMGDIR = "/luadb/img/"
theme._imgcache = {}
function theme.img(name)
    local hit = theme._imgcache[name]
    if hit ~= nil then return hit ~= false and hit or nil end
    local dirs = { "/luadb/img/", "/luadb/", "/img/" }
    for i = 1, #dirs do
        local p = dirs[i] .. name
        local ok = false
        pcall(function() ok = io.exists(p) end)
        if ok then
            theme._imgcache[name] = p
            return p
        end
    end
    theme._imgcache[name] = false
    return nil
end

--------------------------------------------------------------------
-- label 高度兜底
-- LVGL 的 label 从顶部开始绘制、超出对象高度的部分会被裁掉，
-- 而中文字（hzfont）实际行高约为字号的 1.35 倍：页面里大量 label
-- 写 h=20 配 font_size=16，字形下缘会被切掉一截（表现为「字显示不全」）。
-- 这里统一在创建前把 h 抬到 ≥ 1.35×字号；字形起点不变，只是多给裁剪空间。
--------------------------------------------------------------------
pcall(function()
    local _label = airui.label
    airui.label = function(o)
        if type(o) == "table" then
            local fs = math.floor(tonumber(o.font_size) or 16)
            local need = math.floor(fs * 1.35 + 0.5)
            local h = tonumber(o.h)
            if not h or h < need then o.h = need end
        end
        return _label(o)
    end
end)

--------------------------------------------------------------------
-- 屏幕分辨率（自适应）
--------------------------------------------------------------------
theme.W, theme.H = 1024, 600
pcall(function()
    -- display 为全局核心库，不可 require
    local w, h = display.getSize()
    if w and w > 0 then theme.W = w end
    if h and h > 0 then theme.H = h end
end)

--------------------------------------------------------------------
-- 主题配色：深色（默认）/ 浅色，取值与 preview.html 的 CSS 变量一致
-- C 是"当前生效"的调色板：toggle_theme 就地覆写字段值（不换表身份），
-- 页面里的 local C = theme.C 拿到的是同一张表，重建后自动跟随
-- 页面禁止硬编码 0xRRGGBB，一律使用语义色
--------------------------------------------------------------------
theme.cur = "dark"
theme.PALETTES = {
    dark = {
        bg     = 0x04070E,  -- 整屏背景（--bg）
        page   = 0x04080F,  -- 页面渐变底色近似（#050B16→#03060C）
        card   = 0x122238,  -- 卡片底色（--card 渐变的实色近似）
        card2  = 0x0C1A2C,  -- 二档卡片（--card2）
        deep   = 0x0E1C30,  -- 更深一档（tctl / 胶囊 / 浮层）
        float  = 0x14263E,  -- 浮层（sheet / 下拉）
        line   = 0x16253A,  -- 边框（--line @20% 预混合）
        line2  = 0x0D1624,  -- 弱分隔线（--line2 @10% 预混合）
        text   = 0xE9F2FF,  -- 主文字（--text）
        title  = 0xDCE9FB,  -- 卡片标题（.ctitle）
        name   = 0xCFE0F6,  -- 名称类文字（.wcity/.mapdest b）
        sub    = 0x94AAC8,  -- 次要文字（--sub）
        dim    = 0x5F7694,  -- 弱文字（--dim）
        icon   = 0xBFD6F2,  -- 图标默认色
        bright = 0xEAF4FF,  -- 图标亮色
        blue   = 0x2E7DFF,  -- --blue
        blue2  = 0x5AA7FF,  -- --blue2
        cyan   = 0x35D6E8,  -- --cyan
        green  = 0x34D399,  -- --green
        pink   = 0xF43F6E,  -- --pink
        purple = 0x8B7BFF,  -- --purple
        yellow = 0xF5C542,  -- --yellow
        orange = 0xFFA14A,  -- --orange
        knob   = 0xFFFFFF,  -- 进度条旋钮
        cloud  = 0xBBD2EC,  -- 天气图标云朵（首页天气卡）
        rain   = 0x8FBBEA,  -- 雨丝
        lum    = 0,         -- 0=深色主题
    },
    light = {
        bg     = 0xF2F6FC,
        page   = 0xEDF2FA,
        card   = 0xFFFFFF,
        card2  = 0xF7FAFF,
        deep   = 0xE7EFFA,
        float  = 0xFFFFFF,
        line   = 0xB8CBE6,
        line2  = 0xD8E2F2,
        text   = 0x16324F,
        title  = 0x16324F,
        name   = 0x16324F,
        sub    = 0x57708F,
        dim    = 0x8296B0,
        icon   = 0x2E5A8A,
        bright = 0x16324F,
        blue   = 0x1F5FBF,
        blue2  = 0x1F5FBF,
        cyan   = 0x1893B8,
        green  = 0x1F8F63,
        pink   = 0xD43B66,
        purple = 0x6A5BE0,
        yellow = 0xC79520,
        orange = 0xE07E22,
        knob   = 0xFFFFFF,
        cloud  = 0x9DB4D4,
        rain   = 0x5E88C0,
        lum    = 255,       -- 255=浅色主题
    },
}
theme.C = {}
for k, v in pairs(theme.PALETTES.dark) do theme.C[k] = v end

--------------------------------------------------------------------
-- 颜色预混合（滑动卡顿优化）：
-- "半透明色叠底色"离线算成不透明色，运行时避开 LVGL 逐像素 alpha 混合
--------------------------------------------------------------------
function theme.blend(fg, bg, alpha)
    if alpha > 1 then alpha = alpha / 255 end
    if alpha > 1 then alpha = 1 end
    if alpha < 0 then alpha = 0 end
    local r = math.floor((fg >> 16 & 0xFF) * alpha + (bg >> 16 & 0xFF) * (1 - alpha) + 0.5)
    local g = math.floor((fg >> 8 & 0xFF) * alpha + (bg >> 8 & 0xFF) * (1 - alpha) + 0.5)
    local b = math.floor((fg & 0xFF) * alpha + (bg & 0xFF) * (1 - alpha) + 0.5)
    return (r << 16) | (g << 8) | b
end

local function derive_colors()
    local C = theme.C
    if C.lum == 0 then
        -- 深色：卡片顶缘高亮线 / 选中态蓝底 / 弱蓝描边
        C.hi        = theme.blend(0x8CC8FF, C.card, 0.28)
        C.sel       = theme.blend(C.blue, C.card, 0.30)
        C.sel_str   = theme.blend(C.blue, C.card, 0.42)
        C.track     = theme.blend(0x78A0D2, C.card, 0.20)
        C.glow      = theme.blend(C.blue2, C.bg, 0.30)
        C.shadow    = 0x000000
        C.skin      = 0xC99A6E   -- 头像肤色（深色下的暖色）
    else
        C.hi        = 0xFFFFFF
        C.sel       = theme.blend(C.blue, C.card, 0.14)
        C.sel_str   = theme.blend(C.blue, C.card, 0.22)
        C.track     = 0xD5E0F0
        C.glow      = theme.blend(C.blue2, C.bg, 0.30)
        C.shadow    = theme.blend(0x1E3C64, C.bg, 0.18)
        C.skin      = 0xD9A177
    end
end
derive_colors()

-- 深浅主题切换（就地覆写 C；返回 "dark"/"light"）
function theme.toggle_theme()
    theme.cur = (theme.cur == "dark") and "light" or "dark"
    for k, v in pairs(theme.PALETTES[theme.cur]) do theme.C[k] = v end
    derive_colors()
    -- 缓存里的页面是按旧配色画的，留着会「切回浅色却还是深色底」，
    -- 直接丢掉，下次进入时按新主题重建
    if theme.clear_cache then pcall(theme.clear_cache) end
    log.info("theme", "switch to " .. theme.cur)
    return theme.cur
end

theme.TOP_H = 46                 -- 顶栏高度（与 .topbar 一致）
theme.DOCK_H = 58               -- 底栏高度（与 .dockbar 一致）
theme.PAD = 16                  -- 页面左右边距

--------------------------------------------------------------------
-- 页面注册与切换（踩坑：exwin 必须"先 close 旧栈顶，再 open 新窗"，
-- 先开后关会把旧窗留在栈底，close 时焦点错乱导致白屏）
--------------------------------------------------------------------
local registry = {}
local current_win = nil
local current_mod = nil

function theme.register(name, mod)
    registry[name] = mod
end

--------------------------------------------------------------------
-- 页面缓存（切页提速的核心）
-- 原来每切一次页都是「destroy 旧页 root + 重建新页 root」，一页几百个
-- LVGL 对象，Air8603 上重建要 300ms 起步，点下去先黑/白一下才出来。
-- container 有 set_hidden / hide / open（label/shape 没有），隐藏的页面
-- 不参与渲染也不占 CPU，所以改成：离开时 set_hidden(true) 留在内存，
-- 回来时 set_hidden(false) + open() 直接从内存里亮出来，≈ 0 开销。
-- 只留最近 theme.CACHE_MAX 页，超出的按最久未用销毁；12 页全攒着会吃满内存。
--------------------------------------------------------------------
theme.CACHE_MAX = 3
local cache_lru = {}          -- 已缓存页名，尾部 = 最近使用

local function lru_touch(name)
    for i = 1, #cache_lru do
        if cache_lru[i] == name then table.remove(cache_lru, i) break end
    end
    cache_lru[#cache_lru + 1] = name
end

local function lru_evict(keep)
    while #cache_lru > theme.CACHE_MAX do
        local old = table.remove(cache_lru, 1)
        local mod = registry[old]
        if mod and mod.evict and old ~= keep and old ~= theme._cur_page then
            pcall(mod.evict, mod)
            log.info("ui", "cache evict " .. old)
        end
    end
end

-- 主题切换后缓存页还是旧配色 → 全部丢掉，下次进入按新主题重建
function theme.clear_cache()
    local list = cache_lru
    cache_lru = {}
    for i = 1, #list do
        local mod = registry[list[i]]
        if mod and mod.evict and list[i] ~= theme._cur_page then
            pcall(mod.evict, mod)
        end
    end
end

local function switch_page(name)
    local mod = registry[name]
    if not mod then return end
    if current_win then
        local w = current_win
        current_win = nil
        log.info("ui", "exwin.close " .. tostring(w))
        pcall(exwin.close, w)
    end
    log.info("ui", "exwin.open page " .. name)
    current_mod = mod
    current_win = mod.open()
    lru_touch(name)
    lru_evict(name)
    log.info("ui", "exwin.open done, win=" .. tostring(current_win))
end
sys.subscribe("SWITCH_PAGE", switch_page)

-- 当前页整页重建（主题切换用；调用方必须已在 LVGL 事件回调之外）
function theme.rerender_current()
    if current_mod and current_mod.rerender then
        pcall(current_mod.rerender, current_mod)
    end
end

--------------------------------------------------------------------
-- 页面栈：任何页面走 theme.go_defer("xxx") 进来都会记下「从哪来」，
-- 页内返回键统一调 theme.back_defer()，回到上一页而不是硬编码回首页
-- （用户反馈：音乐/导航/语音页点退出直接跳回主界面，应该回上一页）。
--------------------------------------------------------------------
theme._cur_page = nil
theme._stack = {}

function theme.go(name, no_push)
    if not name then return end
    local from = theme._cur_page
    if not no_push and from and from ~= name then
        theme._stack[#theme._stack + 1] = from
        if #theme._stack > 8 then table.remove(theme._stack, 1) end
    end
    sys.publish("SWITCH_PAGE", name)
end

-- 只隔一帧（12ms ≈ 一次刷屏周期），把调用挪出 LVGL 事件回调即可，
-- 原来 30ms 纯粹是白等；鼠标/手指抬起的观感差别明显
local go_timer, back_timer = nil, nil
function theme.go_defer(name)
    if go_timer then sys.timerStop(go_timer) end
    go_timer = sys.timerStart(function()
        go_timer = nil
        theme.go(name)
    end, 12)
end

-- 返回上一页；栈空时回 default（默认首页）
function theme.back(default)
    local t = table.remove(theme._stack)
    theme.go(t or default or "home", true)
end

function theme.back_defer(default)
    if back_timer then sys.timerStop(back_timer) end
    back_timer = sys.timerStart(function()
        back_timer = nil
        theme.back(default)
    end, 12)
end

--------------------------------------------------------------------
-- 页面工厂
-- build_fn(root, M)  返回 1.5s 刷新回调（可选）
-- M.rerender 整页重建（主题切换用，必须在 LVGL 事件回调之外调用）
--------------------------------------------------------------------
function theme.make_page(name, build_fn)
    local M = { name = name }
    local root, timer_id
    local built = false      -- root 是否已建好（决定走缓存复用还是重建）
    local update_fn = nil    -- 1s 刷新回调，复用页面时要重新挂上
    -- 页内动画定时器（路线流动、呼吸点之类的高频刷新）。
    -- 这些 timer 必须跟着页面隐藏/重建一起停，否则页面切走后还在跑；
    -- 同时把定义存下来，缓存复用页面时原样重启。
    local anim_defs = {}
    local anim_ids = {}

    local function stop_anims()
        for _, id in ipairs(anim_ids) do pcall(sys.timerStop, id) end
        anim_ids = {}
    end

    local function start_anims()
        for _, d in ipairs(anim_defs) do
            local id = sys.timerLoopStart(function() pcall(d.fn) end, d.ms)
            anim_ids[#anim_ids + 1] = id
        end
    end

    local function stop_refresh()
        if timer_id then sys.timerStop(timer_id) timer_id = nil end
    end

    -- 先刷一次再挂定时器：从缓存里亮出来的页面要立刻显示最新数据，
    -- 否则会先看到离开那一瞬间的旧值（1s 后才更新）
    local function start_refresh()
        if update_fn and not timer_id then
            pcall(update_fn)
            -- 1s 刷新：原来 1500ms 时进度秒数会「2 秒一跳」（1.5s 累加后取整），
            -- 播放进度、歌词滚动都跟着抖，所以统一改成 1s
            timer_id = sys.timerLoopStart(update_fn, 1000)
        end
    end

    local function create_ui()
        -- 命中缓存：不重建，直接把旧 root 亮出来（切页提速主要靠这条）
        if built and root then
            pcall(root.set_hidden, root, false)
            pcall(root.open, root)     -- 提到最前，否则被后建的页面盖住
            theme._cur_root = root
            theme._cur_page = name
            start_refresh()
            start_anims()
            if exwin.bind_root then pcall(exwin.bind_root, root) end
            log.info("ui", "page " .. name .. " resume")
            return
        end
        log.info("ui", "create page " .. name)
        root = airui.container({
            parent = airui.screen,
            x = 0, y = 0, w = theme.W, h = theme.H,
            color = theme.C.bg,
        })
        theme._cur_root = root
        theme._cur_page = name
        anim_defs = {}
        -- 构建失败不再拖垮整页：已画出的部分保留，错误进日志
        local ok, update = pcall(build_fn, root, M)
        if not ok then
            log.error("ui", "page " .. name .. " build error: " .. tostring(update))
            update = nil
        end
        update_fn = update
        built = true
        start_refresh()
        -- 踩坑：部分固件版本的 exwin 没有 bind_root 方法，直接调用 = nil call 重启
        if exwin.bind_root then
            pcall(exwin.bind_root, root)
        end
        log.info("ui", "page " .. name .. " ready")
    end

    -- 页内动画定时器：让 build_fn 里也能开高频 loop，页面隐藏/销毁时自动收掉
    function M.loop(fn, ms)
        local d = { fn = fn, ms = ms or 120 }
        anim_defs[#anim_defs + 1] = d
        local id = sys.timerLoopStart(function()
            -- 单帧出错不能把 loop 打死，也不能把异常抛回 sys 定时器
            pcall(d.fn)
        end, d.ms)
        anim_ids[#anim_ids + 1] = id
        return id
    end

    -- 彻底销毁（LRU 淘汰 / 主题切换用）
    function M.evict()
        stop_refresh()
        stop_anims()
        if root then pcall(root.destroy, root) root = nil end
        built = false
        update_fn = nil
        anim_defs = {}
    end

    -- 整页重建（主题切换用）：销毁旧 root → 重跑 create_ui
    function M.rerender()
        M.evict()
        create_ui()
    end

    function M.open()
        return exwin.open({
            on_create  = create_ui,
            on_destroy = function()
                stop_refresh()
                stop_anims()
                if not root then return end
                if built then
                    -- 留在内存里，只是藏起来；再进来时 set_hidden(false) 秒开
                    pcall(root.set_hidden, root, true)
                    lru_touch(name)
                    lru_evict(name)
                    log.info("ui", "page " .. name .. " cached")
                else
                    pcall(root.destroy, root)
                    root = nil
                end
            end,
        })
    end

    theme.register(name, M)
    return M
end

--------------------------------------------------------------------
-- 通用点击包装：LVGL 回调内不做重建/销毁，统一延迟 12ms + 防抖
-- （12ms 足够跳出 lv_timer_handler 的回调栈；原来 30ms 每次点击都白等）
--------------------------------------------------------------------
local function _mkdeb()
    local t = nil
    return function(fn)
        if t then sys.timerStop(t) end
        t = sys.timerStart(function() t = nil fn() end, 12)
    end
end
theme.debounce = _mkdeb

--------------------------------------------------------------------
-- 图元安全绘制（踩坑：shape 图元过多整批丢弃 → 按 30 个一批建多个 shape；
-- 圆心/半径必须取整；实心圆 width>=1）
--------------------------------------------------------------------
function theme.shapes(parent, x, y, w, h, items)
    local n = #items
    local i = 1
    while i <= n do
        local j = math.min(i + 29, n)
        local part = {}
        for k = i, j do part[#part + 1] = items[k] end
        airui.shape({ parent = parent, x = x, y = y, w = w, h = h, items = part })
        i = j + 1
    end
end

local function _ci(items, cx, cy, r, col, opa, ishape)
    ishape = ishape or items
    ishape[#ishape + 1] = { type = "circle",
        cx = math.floor(cx + 0.5), cy = math.floor(cy + 0.5),
        r = math.floor(r + 0.5), color = col, width = 1,
        fill = true, fill_color = col, fill_opacity = opa or 255 }
end

local function _ln(items, x1, y1, x2, y2, col, w)
    items[#items + 1] = { type = "line",
        x1 = math.floor(x1), y1 = math.floor(y1),
        x2 = math.floor(x2), y2 = math.floor(y2), color = col, width = w or 2 }
end

local function _rc(items, x, y, w, h, col, rad)
    items[#items + 1] = { type = "rect",
        x = math.floor(x), y = math.floor(y),
        w = math.floor(w), h = math.floor(h),
        color = col, width = 1, radius = rad or 0,
        fill = true, fill_color = col, fill_opacity = 255 }
end

-- 空心矩形（描边不填充）
local function _rco(items, x, y, w, h, col, rad, lw)
    items[#items + 1] = { type = "rect",
        x = math.floor(x), y = math.floor(y),
        w = math.floor(w), h = math.floor(h),
        color = col, width = lw or 2, radius = rad or 0, fill = false }
end

-- 空心圆（描边不填充）
local function _cco(items, cx, cy, r, col, lw)
    items[#items + 1] = { type = "circle",
        cx = math.floor(cx + 0.5), cy = math.floor(cy + 0.5),
        r = math.floor(r + 0.5), color = col, width = lw or 2, fill = false }
end

theme._ci, theme._ln, theme._rc, theme._rco, theme._cco = _ci, _ln, _rc, _rco, _cco

--------------------------------------------------------------------
-- 线性图标（shape 绘制，替代 HTML 的 SVG path）
-- kind / size / col 为主色；col2 为第二色（可选）
--------------------------------------------------------------------
function theme.icon(parent, x, y, s, kind, col, col2)
    col2 = col2 or col
    local c, ln, rc = {}, nil, nil
    ln = function(x1, y1, x2, y2, cc, w) _ln(c, x1, y1, x2, y2, cc or col, w or 2) end
    rc = function(rx, ry, rw, rh, cc, rad) _rc(c, rx, ry, rw, rh, cc or col, rad or 0) end
    local function ci(cx, cy, r, cc, opa) _ci(c, cx, cy, r, cc or col, opa) end
    local h = s / 2

    if kind == "home" then
        -- 实心房子：屋顶用「按行堆三角」画，墙体用圆角矩形，门用 col2 挖出来。
        -- 原来屋顶是两条斜线 + 一根竖线 + 小方块，16px 下互相穿插糊成一团
        -- （用户反馈「主页的图标也好丑」）。
        local roofh = math.max(5, math.floor(s * 0.40))
        local wallw = math.max(8, math.floor(s * 0.64))
        local wallx = math.floor((s - wallw) / 2)
        for row = 0, roofh - 1 do
            local t = (row + 0.6) / roofh
            local ww = math.max(2, math.floor(s * t))
            rc(math.floor((s - ww) / 2), 1 + row, ww, 1, nil, 0)
        end
        local wy = roofh
        rc(wallx, wy, wallw, s - wy - 1, nil, 1)
        local dh = math.max(4, math.floor(s * 0.30))
        rc(math.floor(s / 2) - 2, s - dh - 1, 4, dh, col2, 1)
    elseif kind == "nav" then
        -- 导航箭头：照 APP 列表里的实心向上三角（原来四条细斜线在 22px 下
        -- 互相穿插，糊成一团「四不像」，用户反馈要求改成干净的三角块）。
        -- 按行堆 1px 矩形，任何尺寸都是边缘平整的实心三角。
        local tw  = math.max(6, math.floor(s * 0.72))
        local thh = math.max(6, math.floor(s * 0.66))
        local x0  = math.floor((s - tw) / 2)
        local y0  = math.floor((s - thh) / 2)
        for row = 0, thh - 1 do
            local t  = (row + 0.5) / thh
            local ww = math.max(1, math.floor(tw * t))
            rc(x0 + math.floor((tw - ww) / 2), y0 + row, ww, 1, nil, 0)
        end
    elseif kind == "clock" then
        ci(h, h, 0.34 * s)
        ln(h, 0.28 * s, h, h, nil, 2)
        ln(h, h, 0.68 * s, 0.68 * s, nil, 2)
    elseif kind == "music" then
        ln(0.38 * s, 0.25 * s, 0.38 * s, 0.75 * s)
        ln(0.38 * s, 0.25 * s, 0.83 * s, 0.17 * s)
        ln(0.83 * s, 0.17 * s, 0.83 * s, 0.65 * s)
        ci(0.27 * s, 0.75 * s, 0.11 * s)
        ci(0.72 * s, 0.66 * s, 0.11 * s)
    elseif kind == "car" then
        ln(0.12 * s, 0.68 * s, 0.2 * s, 0.42 * s)
        ln(0.2 * s, 0.42 * s, 0.82 * s, 0.42 * s)
        ln(0.82 * s, 0.42 * s, 0.88 * s, 0.68 * s)
        ln(0.12 * s, 0.68 * s, 0.88 * s, 0.68 * s)
        ci(0.28 * s, 0.72 * s, 0.09 * s)
        ci(0.72 * s, 0.72 * s, 0.09 * s)
    elseif kind == "seat" then
        ln(0.3 * s, 0.18 * s, 0.3 * s, 0.58 * s)
        ln(0.3 * s, 0.58 * s, 0.72 * s, 0.72 * s)
        ln(0.72 * s, 0.72 * s, 0.72 * s, 0.85 * s)
    elseif kind == "volume" then
        rc(0.14 * s, 0.38 * s, 0.16 * s, 0.24 * s)
        ln(0.34 * s, 0.3 * s, 0.34 * s, 0.7 * s, nil, 2)
        ln(0.34 * s, 0.3 * s, 0.52 * s, 0.2 * s, nil, 2)
        ln(0.34 * s, 0.7 * s, 0.52 * s, 0.8 * s, nil, 2)
        ln(0.66 * s, 0.34 * s, 0.66 * s, 0.66 * s, col2, 2)
        ln(0.66 * s, 0.34 * s, 0.78 * s, 0.26 * s, col2, 2)
        ln(0.66 * s, 0.66 * s, 0.78 * s, 0.74 * s, col2, 2)
    elseif kind == "grid" then
        rc(0.15 * s, 0.15 * s, 0.28 * s, 0.28 * s, nil, 1)
        rc(0.57 * s, 0.15 * s, 0.28 * s, 0.28 * s, nil, 1)
        rc(0.15 * s, 0.57 * s, 0.28 * s, 0.28 * s, nil, 1)
        rc(0.57 * s, 0.57 * s, 0.28 * s, 0.28 * s, nil, 1)
    elseif kind == "wifi" then
        ci(h, h - 0.02 * s, 0.06 * s)
        ln(0.24 * s, 0.4 * s, 0.4 * s, 0.56 * s, nil, 2)
        ln(0.76 * s, 0.4 * s, 0.6 * s, 0.56 * s, nil, 2)
        ln(0.12 * s, 0.26 * s, 0.34 * s, 0.48 * s, nil, 2)
        ln(0.88 * s, 0.26 * s, 0.66 * s, 0.48 * s, nil, 2)
    elseif kind == "signal" then
        -- 4G 信号：4 根递增的圆角竖条，底边对齐。
        -- 原来是 0.14/0.38/0.62/0.86 的比例坐标、条宽只有 2px，16~18px 下
        -- 相邻两根几乎贴着，渲染完就是一团灰块（用户要求「画好看一点」）。
        -- 改用整数像素：宽 3、间隙 1、高度 5/8/11/14，最后一根用 col2 表示弱信号。
        local gap2 = math.max(1, math.floor(s * 0.08))
        local bw2  = math.max(2, math.floor((s - 3 * gap2) / 4))
        local ox2  = math.floor((s - (4 * bw2 + 3 * gap2)) / 2)   -- 水平居中
        local base = s - 1
        for i = 1, 4 do
            local bh2 = math.max(3, math.floor(s * (0.30 + 0.16 * (i - 1))))
            rc(ox2 + (i - 1) * (bw2 + gap2), base - bh2, bw2, bh2,
                i == 4 and col2 or nil, 1)
        end
    elseif kind == "battery" then
        -- 电池：圆角外框 + 正极凸点 + 绿色电量块（约 70%）。
        -- 原来描边只有 1.5px、电量块 0.44*s 宽，16px 下框线糊在一起、
        -- 电量块几乎看不见 → 外框固定 2px、电量块按内腔宽度 72% 算。
        local fw = s - 2
        local fh = math.max(8, math.floor(s * 0.62))
        local fy = math.floor((s - fh) / 2)
        _rco(c, 0, fy, fw, fh, col, 2, 2)
        rc(fw + 1, fy + math.floor(fh / 2) - 2, 2, 4)
        rc(2, fy + 2, math.floor((fw - 4) * 0.72), math.max(2, fh - 4), col2 or col, 1)
    elseif kind == "play" then
        ln(0.28 * s, 0.18 * s, 0.82 * s, h, nil, 3)
        ln(0.28 * s, 0.82 * s, 0.82 * s, h, nil, 3)
        ln(0.28 * s, 0.18 * s, 0.28 * s, 0.82 * s, nil, 3)
    elseif kind == "pause" then
        rc(0.3 * s, 0.2 * s, 0.12 * s, 0.6 * s)
        rc(0.58 * s, 0.2 * s, 0.12 * s, 0.6 * s)
    elseif kind == "prev" or kind == "next" then
        -- 上一首/下一首：竖条 + 实心三角（♯ 形）。
        -- 原来用两条细斜线画三角，18~20px 下糊成 "K"，用户反馈「好丑」。
        -- 这里按行用 1px 矩形堆出实心三角，任何尺寸都是干净的块面。
        local dir   = (kind == "prev") and -1 or 1
        local tw    = math.max(6, math.floor(s * 0.50))   -- 三角宽
        local th    = math.max(8, math.floor(s * 0.74))   -- 三角高
        local barw  = math.max(2, math.floor(s * 0.12))   -- 竖条宽
        -- 竖条和三角之间原来只有 1px 缝，18~20px 下尖角跟竖条粘成一块，
        -- 上一首（尖朝左）看起来比下一首糊 → 缝改成 2px 以上
        local gap   = math.max(2, math.floor(s * 0.11))
        local total = barw + gap + tw
        local x0    = math.floor((s - total) / 2)
        local gy    = math.floor(h - th / 2)              -- 三角顶边
        local tri_x, bar_x
        if dir < 0 then                    -- 上一首：竖条在左，三角朝左
            bar_x, tri_x = x0, x0 + barw + gap
        else                               -- 下一首：竖条在右，三角朝右
            tri_x, bar_x = x0, x0 + tw + gap
        end
        for row = 0, th - 1 do
            local t  = (row + 0.5) / th    -- 0..1
            local ww = tw * (1 - math.abs(t * 2 - 1))   -- 中间最宽，上下收尖
            if ww < 1 then ww = 1 end
            local xx = (dir < 0) and (tri_x + tw - ww) or tri_x
            rc(xx, gy + row, ww, 1, nil, 0)
        end
        rc(bar_x, gy, barw, th, nil, 1)
    elseif kind == "left" or kind == "right" then
        -- 返回 / 左右箭头：照参考图做「横杆 + 尖头」的完整 ← 键。
        -- 原来只有一个 <（两条边、没有横杆），22px 看过去像一团缺角的碎块
        -- （用户反馈「它是一个 <- 键，你现在这个图案是四不像」）。
        -- 尖头仍按行堆 1px 矩形保证边缘干净，横杆单独一条实心矩形。
        local dir = (kind == "left") and -1 or 1
        local aw  = math.max(9, math.floor(s * 0.78))    -- 箭头总横向跨度
        local ah  = math.max(9, math.floor(s * 0.56))    -- 尖头高度
        local th  = math.max(2, math.floor(s * 0.19))    -- 笔画厚度
        local span = math.max(3, math.floor(aw * 0.42))  -- 尖头横向跨度
        local ay  = math.floor((s - ah) / 2)
        local bx  = math.floor((s - aw) / 2)
        -- 尖头：dir<0 尖端在左、端点在右；dir>0 镜像
        for row = 0, ah - 1 do
            local k  = math.abs((row + 0.5) / ah * 2 - 1)   -- 端点 1 → 中线 0
            local xx = (dir < 0) and (bx + math.floor(k * span))
                                 or  (bx + aw - th - math.floor(k * span))
            rc(xx, ay + row, th, 1, nil, 0)
        end
        -- 横杆：从尖端内侧拉到另一端，位于垂直中线
        local rx = (dir < 0) and (bx + th) or bx
        rc(rx, ay + math.floor((ah - th) / 2), aw - th, th, nil, 0)
    elseif kind == "up" then
        ln(0.2 * s, 0.62 * s, h, 0.38 * s, nil, 3)
        ln(h, 0.38 * s, 0.8 * s, 0.62 * s, nil, 3)
    elseif kind == "down" then
        ln(0.2 * s, 0.38 * s, h, 0.62 * s, nil, 3)
        ln(h, 0.62 * s, 0.8 * s, 0.38 * s, nil, 3)
    elseif kind == "plus" then
        ln(h, 0.22 * s, h, 0.78 * s, nil, 2)
        ln(0.22 * s, h, 0.78 * s, h, nil, 2)
    elseif kind == "minus" then
        ln(0.22 * s, h, 0.78 * s, h, nil, 2)
    elseif kind == "fan" then
        ci(h, h, 0.08 * s)
        local a
        for i = 0, 2 do
            a = math.rad(i * 120 - 90)
            ln(h, h, h + 0.3 * s * math.cos(a), h + 0.3 * s * math.sin(a), nil, 3)
        end
    elseif kind == "spark" then
        -- 六芒星（参考 APP 列表里空调的「米」字图标）：
        -- 三条过圆心的直径线，间隔 60°，任何尺寸都不会糊
        local r = 0.42 * s
        local a
        for i = 0, 2 do
            a = math.rad(90 + i * 60)
            ln(h - r * math.cos(a), h - r * math.sin(a),
               h + r * math.cos(a), h + r * math.sin(a), nil, 2)
        end
    elseif kind == "turn-left" then
        -- 照 preview.html 的 path M18 9H9V4L3 10l6 6v-5h9z：
        -- 横杆 + 竖杆 + 朝上的实心三角。原来只有两条细斜线在极小尺寸下
        -- 糊成一团（用户反馈「这图标好丑」），这里加粗到 3 并把三角闭合。
        local function fl(v) return math.floor(v + 0.5) end
        ln(fl(0.38 * s), fl(0.38 * s), fl(0.80 * s), fl(0.38 * s), nil, 3)   -- 右侧横杆
        ln(fl(0.38 * s), fl(0.38 * s), fl(0.38 * s), fl(0.80 * s), nil, 3)   -- 竖杆
        ln(fl(0.12 * s), fl(0.44 * s), fl(0.38 * s), fl(0.16 * s), nil, 3)   -- 三角左翼
        ln(fl(0.64 * s), fl(0.44 * s), fl(0.38 * s), fl(0.16 * s), nil, 3)   -- 三角右翼
        ln(fl(0.12 * s), fl(0.44 * s), fl(0.64 * s), fl(0.44 * s), nil, 3)   -- 三角底边
    elseif kind == "power" then
        ci(h, h + 0.04 * s, 0.3 * s)
        ln(h, 0.14 * s, h, 0.42 * s, nil, 2)
    elseif kind == "bolt" then
        ln(0.6 * s, 0.12 * s, 0.36 * s, 0.55 * s, nil, 2)
        ln(0.36 * s, 0.55 * s, 0.58 * s, 0.55 * s, nil, 2)
        ln(0.58 * s, 0.55 * s, 0.4 * s, 0.88 * s, nil, 2)
    elseif kind == "phone" then
        _rco(c, 0.28 * s, 0.1 * s, 0.44 * s, 0.8 * s, col, 3, 2)
        ln(0.42 * s, 0.8 * s, 0.58 * s, 0.8 * s, col2, 2)
    elseif kind == "mic" then
        _rco(c, 0.4 * s, 0.14 * s, 0.2 * s, 0.42 * s, col, 2, 2)
        ln(0.3 * s, 0.44 * s, 0.3 * s, 0.52 * s, nil, 2)
        ln(0.7 * s, 0.44 * s, 0.7 * s, 0.52 * s, nil, 2)
        ln(0.3 * s, 0.52 * s, 0.7 * s, 0.52 * s, nil, 2)
        ln(h, 0.52 * s, h, 0.72 * s, nil, 2)
        ln(0.38 * s, 0.72 * s, 0.62 * s, 0.72 * s, nil, 2)
    elseif kind == "seatheat" then
        ln(0.3 * s, 0.18 * s, 0.3 * s, 0.58 * s)
        ln(0.3 * s, 0.58 * s, 0.72 * s, 0.72 * s)
        ln(0.72 * s, 0.72 * s, 0.72 * s, 0.85 * s)
        rc(0.62 * s, 0.2 * s, 0.24 * s, 0.24 * s, nil, 2)
    elseif kind == "heater" then
        ln(0.24 * s, 0.14 * s, 0.24 * s, 0.86 * s, nil, 3)
        ln(0.76 * s, 0.14 * s, 0.76 * s, 0.86 * s, nil, 3)
        ln(0.24 * s, h, 0.76 * s, h, nil, 3)
    elseif kind == "sync" then
        ln(0.12 * s, 0.3 * s, 0.88 * s, 0.3 * s, nil, 2)
        ln(0.12 * s, 0.7 * s, 0.88 * s, 0.7 * s, nil, 2)
        _cco(c, 0.3 * s, 0.3 * s, 0.1 * s, col, 2)
        _cco(c, 0.7 * s, 0.7 * s, 0.1 * s, col, 2)
    elseif kind == "heart" then
        ln(0.5 * s, 0.82 * s, 0.12 * s, 0.42 * s, nil, 2)
        ln(0.12 * s, 0.42 * s, 0.16 * s, 0.2 * s, nil, 2)
        ln(0.16 * s, 0.2 * s, 0.34 * s, 0.24 * s, nil, 2)
        ln(0.34 * s, 0.24 * s, h, 0.3 * s, nil, 2)
        ln(h, 0.3 * s, 0.66 * s, 0.24 * s, nil, 2)
        ln(0.66 * s, 0.24 * s, 0.84 * s, 0.2 * s, nil, 2)
        ln(0.84 * s, 0.2 * s, 0.88 * s, 0.42 * s, nil, 2)
        ln(0.88 * s, 0.42 * s, h, 0.82 * s, nil, 2)
    elseif kind == "disc" then
        _cco(c, h, h, 0.34 * s, col, 2)
        _ci(c, h, h, 0.08 * s, col, 255)
    elseif kind == "mv" then
        _rco(c, 0.12 * s, 0.24 * s, 0.76 * s, 0.52 * s, col, 3, 2)
        ln(0.42 * s, 0.4 * s, 0.42 * s, 0.6 * s, nil, 2)
        ln(0.42 * s, 0.4 * s, 0.62 * s, h, nil, 2)
        ln(0.42 * s, 0.6 * s, 0.62 * s, h, nil, 2)
    elseif kind == "search" then
        _cco(c, 0.42 * s, 0.42 * s, 0.26 * s, col, 2)
        ln(0.62 * s, 0.62 * s, 0.86 * s, 0.86 * s, nil, 2)
    elseif kind == "more" then
        ln(0.14 * s, h, 0.86 * s, h, nil, 2)
        ln(0.14 * s, 0.26 * s, 0.86 * s, 0.26 * s, nil, 2)
        ln(0.14 * s, 0.74 * s, 0.86 * s, 0.74 * s, nil, 2)
    elseif kind == "robot" then
        _cco(c, h, 0.42 * s, 0.27 * s, col, 2)
        _ci(c, 0.4 * s, 0.38 * s, 0.045 * s, col, 255)
        _ci(c, 0.6 * s, 0.38 * s, 0.045 * s, col, 255)
        ln(0.38 * s, 0.54 * s, 0.44 * s, 0.58 * s, nil, 2)
        ln(0.44 * s, 0.58 * s, 0.56 * s, 0.58 * s, nil, 2)
        ln(0.56 * s, 0.58 * s, 0.62 * s, 0.54 * s, nil, 2)
    elseif kind == "camera" then
        _rco(c, 0.1 * s, 0.3 * s, 0.8 * s, 0.5 * s, col, 4, 2)
        _cco(c, h, 0.55 * s, 0.13 * s, col, 2)
        ln(0.34 * s, 0.3 * s, 0.4 * s, 0.22 * s, nil, 2)
        ln(0.4 * s, 0.22 * s, 0.6 * s, 0.22 * s, nil, 2)
        ln(0.6 * s, 0.22 * s, 0.66 * s, 0.3 * s, nil, 2)
    elseif kind == "sun" then
        ci(h, 0.42 * s, 0.18 * s)
        local a
        for i = 0, 7 do
            a = math.rad(i * 45)
            ln(h + 0.26 * s * math.cos(a), 0.42 * s + 0.26 * s * math.sin(a),
               h + 0.36 * s * math.cos(a), 0.42 * s + 0.36 * s * math.sin(a), nil, 2)
        end
    elseif kind == "photo" then
        _rco(c, 0.12 * s, 0.2 * s, 0.76 * s, 0.6 * s, col, 3, 2)
        _ci(c, 0.34 * s, 0.4 * s, 0.07 * s, col, 255)
        ln(0.16 * s, 0.72 * s, 0.44 * s, 0.5 * s, nil, 2)
        ln(0.44 * s, 0.5 * s, 0.6 * s, 0.64 * s, nil, 2)
        ln(0.6 * s, 0.64 * s, 0.72 * s, 0.56 * s, nil, 2)
        ln(0.72 * s, 0.56 * s, 0.86 * s, 0.7 * s, nil, 2)
    elseif kind == "folder" then
        ln(0.12 * s, 0.3 * s, 0.4 * s, 0.3 * s, nil, 2)
        ln(0.4 * s, 0.3 * s, 0.48 * s, 0.38 * s, nil, 2)
        ln(0.48 * s, 0.38 * s, 0.88 * s, 0.38 * s, nil, 2)
        ln(0.88 * s, 0.38 * s, 0.88 * s, 0.76 * s, nil, 2)
        ln(0.88 * s, 0.76 * s, 0.12 * s, 0.76 * s, nil, 2)
        ln(0.12 * s, 0.76 * s, 0.12 * s, 0.3 * s, nil, 2)
    elseif kind == "gamepad" then
        _rco(c, 0.1 * s, 0.32 * s, 0.8 * s, 0.38 * s, col, 6, 2)
        ln(0.2 * s, 0.51 * s, 0.32 * s, 0.51 * s, nil, 2)
        ln(0.26 * s, 0.45 * s, 0.26 * s, 0.57 * s, nil, 2)
        _ci(c, 0.68 * s, 0.47 * s, 0.035 * s, col, 255)
        _ci(c, 0.78 * s, 0.55 * s, 0.035 * s, col, 255)
    elseif kind == "screen" then
        _rco(c, 0.12 * s, 0.2 * s, 0.76 * s, 0.5 * s, col, 3, 2)
        ln(0.4 * s, 0.8 * s, 0.6 * s, 0.8 * s, nil, 2)
        ln(h, 0.7 * s, h, 0.8 * s, nil, 2)
    elseif kind == "shield" then
        ln(h, 0.12 * s, 0.82 * s, 0.3 * s, nil, 2)
        ln(0.82 * s, 0.3 * s, 0.82 * s, 0.58 * s, nil, 2)
        ln(0.82 * s, 0.58 * s, h, 0.88 * s, nil, 2)
        ln(h, 0.88 * s, 0.18 * s, 0.58 * s, nil, 2)
        ln(0.18 * s, 0.58 * s, 0.18 * s, 0.3 * s, nil, 2)
        ln(0.18 * s, 0.3 * s, h, 0.12 * s, nil, 2)
    elseif kind == "book" then
        ln(h, 0.16 * s, h, 0.84 * s, nil, 2)
        ln(h, 0.16 * s, 0.82 * s, 0.22 * s, nil, 2)
        ln(0.82 * s, 0.22 * s, 0.82 * s, 0.78 * s, nil, 2)
        ln(0.82 * s, 0.78 * s, h, 0.84 * s, nil, 2)
        ln(h, 0.16 * s, 0.18 * s, 0.22 * s, nil, 2)
        ln(0.18 * s, 0.22 * s, 0.18 * s, 0.78 * s, nil, 2)
        ln(0.18 * s, 0.78 * s, h, 0.84 * s, nil, 2)
    elseif kind == "download" then
        ln(h, 0.14 * s, h, 0.6 * s, nil, 2)
        ln(0.32 * s, 0.4 * s, h, 0.6 * s, nil, 2)
        ln(h, 0.6 * s, 0.68 * s, 0.4 * s, nil, 2)
        ln(0.16 * s, 0.78 * s, 0.84 * s, 0.78 * s, nil, 2)
    elseif kind == "expand" then
        ln(0.14 * s, 0.38 * s, 0.14 * s, 0.14 * s, nil, 2)
        ln(0.14 * s, 0.14 * s, 0.38 * s, 0.14 * s, nil, 2)
        ln(0.62 * s, 0.14 * s, 0.86 * s, 0.14 * s, nil, 2)
        ln(0.86 * s, 0.14 * s, 0.86 * s, 0.38 * s, nil, 2)
        ln(0.86 * s, 0.62 * s, 0.86 * s, 0.86 * s, nil, 2)
        ln(0.86 * s, 0.86 * s, 0.62 * s, 0.86 * s, nil, 2)
        ln(0.38 * s, 0.86 * s, 0.14 * s, 0.86 * s, nil, 2)
        ln(0.14 * s, 0.86 * s, 0.14 * s, 0.62 * s, nil, 2)
    elseif kind == "user" then
        ci(h, 0.32 * s, 0.18 * s)
        ln(0.18 * s, 0.82 * s, 0.82 * s, 0.82 * s, nil, 2)
        ln(0.18 * s, 0.82 * s, h, 0.56 * s, nil, 2)
        ln(h, 0.56 * s, 0.82 * s, 0.82 * s, nil, 2)
    end
    if #c > 0 then
        theme.shapes(parent, x, y, s, s, c)
    end
end

--------------------------------------------------------------------
-- 轻提示 toast（对齐 HTML 的 toast）：挂在当前页面 root 上，1.6s 自动隐藏
-- 必须在 LVGL 事件回调之外调用（配合 theme.debounce 使用）
--------------------------------------------------------------------
local toast_state, toast_timer
function theme.toast(text)
    local root = theme._cur_root
    if not root then return end
    if not toast_state or toast_state.root ~= root then
        -- 不要描边：边框会在提示条下方留一条亮线（看起来像「字幕下面的杠」）
        local bg = airui.container({ parent = root,
            x = math.floor(theme.W / 2) - 170, y = theme.H - 116, w = 340, h = 40,
            color = theme.C.deep, radius = 20 })
        -- 文字必须是底板的子对象：
        --   1) label 没有 hide/open 方法（只有 container 有），调 lbl:hide() 会抛
        --      "attempt to call a nil value (method 'hide')"，被 theme.click 的 pcall
        --      吞掉后表现为「点了没反应」；
        --   2) container:open() 会 move_foreground，同级 label 会被底板盖住。
        -- 挂成子对象后，底板的显示/隐藏/置顶都自动带上文字。
        local lbl = airui.label({ parent = bg, x = 0, y = 9, w = 340, h = 22,
            text = "", color = theme.C.text, font_size = 16,
            align = airui.TEXT_ALIGN_CENTER })
        bg:hide()
        toast_state = { root = root, bg = bg, lbl = lbl }
    end
    pcall(function()
        toast_state.lbl:set_text(text)
        toast_state.bg:open()
    end)
    if toast_timer then sys.timerStop(toast_timer) end
    toast_timer = sys.timerStart(function()
        toast_timer = nil
        pcall(function() toast_state.bg:hide() end)
    end, 1600)
end

--------------------------------------------------------------------
-- 局部提示气泡（如调温度时的「主驾 26°C」）
-- 位置固定在页面底部正中（dock 上方，和 theme.toast 同一条水平线）。
-- 不要描边：边框会在气泡下缘留一条亮线，看着就是「提示词下面一根横杠」
-- （用户反馈过，toast 里也踩过同一个坑）。
-- 每个 id 复用同一个控件：连点几十次也不会越堆越多。
-- label 必须是气泡容器的子对象（container:open() 会 move_foreground，
-- 同级 label 会被底板盖住，理由同 theme.toast）
--------------------------------------------------------------------
local tip_state = {}
function theme.tip(id, text, w)
    local root = theme._cur_root
    if not root then return end
    local C = theme.C
    w = w or 176
    local st = tip_state[id]
    if not st or st.root ~= root then
        local bg = airui.container({ parent = root,
            x = math.floor((theme.W - w) / 2), y = theme.H - 116, w = w, h = 40,
            color = C.deep, radius = 20 })
        local lbl = airui.label({ parent = bg, x = 0, y = 9, w = w, h = 22,
            text = "", color = C.bright, font_size = 16,
            align = airui.TEXT_ALIGN_CENTER })
        bg:hide()
        st = { root = root, bg = bg, lbl = lbl }
        tip_state[id] = st
    end
    pcall(function()
        st.lbl:set_text(text)
        st.bg:open()
    end)
    if st.timer then sys.timerStop(st.timer) end
    st.timer = sys.timerStart(function()
        st.timer = nil
        pcall(function() st.bg:hide() end)
    end, 1400)
end

--------------------------------------------------------------------
-- 顶栏（46px）：[返回键] 头像 + 用户名 + 居中 LOGO + 状态图标 + 时间 + 宫格按钮
-- back_name 非空时左侧显示返回键（对应 HTML 的 gridbtn 返回箭头）
-- 头像点击 = 深/浅主题切换（视觉与 HTML 一致，功能入口藏在这里）
--------------------------------------------------------------------
-- label 非空时用 label 代替用户名（如「智能语音」页左上角标题）
function theme.topbar(root, back_name, with_avatar, no_status, home_btn, label)
    local C = theme.C
    local db = theme.debounce()
    local ax = 16
    if back_name then
        -- 30×30 圆底 + 18 号粗箭头（箭头居中：x=15+(30-18)/2=21, y=8+(30-18)/2=14）
        airui.shape({ parent = root, x = 15, y = 8, w = 30, h = 30, items = {
            { type = "circle", cx = 15, cy = 15, r = 14, color = C.line, width = 1,
              fill = true, fill_color = C.deep, fill_opacity = 255 } } })
        theme.icon(root, 21, 14, 18, "left", C.bright)
        -- back_name == "back" 时走页面栈返回上一页，其余按指定页跳转
        theme.click(root, 15, 8, 30, 30, function()
            if back_name == "back" then theme.back_defer() else theme.go_defer(back_name) end
        end, 15)
        ax = 54
    end
    if with_avatar ~= false then
        -- 头像：肤色圆 + 亮色描边
        airui.shape({ parent = root, x = ax + 4, y = 10, w = 26, h = 26, items = {
            { type = "circle", cx = 13, cy = 13, r = 12, color = C.hi, width = 2,
              fill = true, fill_color = C.skin, fill_opacity = 255 } } })
        theme.click(root, ax, 6, 34, 34, function()
            theme.toggle_theme()
            theme.rerender_current()
        end, 17)
        airui.label({ parent = root, x = ax + 36, y = 13, w = 150, h = 22,
            text = label or MOCK.user.name, color = C.title, font_size = 16 })
    else
        airui.label({ parent = root, x = ax, y = 13, w = 150, h = 22,
            text = label or MOCK.user.name, color = C.title, font_size = 16 })
    end

    -- 居中 LOGO（hzfont 无斜体，用亮色 + 大字近似）
    airui.label({ parent = root, x = (theme.W - 220) / 2, y = 11, w = 220, h = 24,
        text = "BYD DiLink", color = C.title, font_size = 19,
        align = airui.TEXT_ALIGN_CENTER })

    -- 右侧：4G 信号 / 电量 / 时间 / 圆钮（间距算好，互不重叠）
    -- wifi 图标在 16px 下由几段直线弧拼成，看着像个「对勾」，用户要求去掉；
    -- 信号与电量放大到 18px，并按整数像素重画（见 theme.icon）
    if not no_status then
        local iy = 14
        theme.icon(root, theme.W - 186, iy, 18, "signal", C.icon, C.dim)
        theme.icon(root, theme.W - 160, iy, 18, "battery", C.icon, C.green)
        airui.label({ parent = root, x = theme.W - 136, y = 13, w = 84, h = 22,
            text = MOCK.time_str, color = C.sub, font_size = 16,
            align = airui.TEXT_ALIGN_RIGHT })
    end

    -- 右上角圆钮：默认「回主页」；首页显式传 "apps" 才是「全部应用」
    local is_apps = (home_btn == "apps")
    airui.shape({ parent = root, x = theme.W - 44, y = 9, w = 28, h = 28, items = {
        { type = "circle", cx = 14, cy = 14, r = 13, color = C.line, width = 1,
          fill = true, fill_color = is_apps and C.deep or C.card, fill_opacity = 255 } } })
    if is_apps then
        theme.icon(root, theme.W - 37, 16, 14, "grid", C.icon)
    else
        -- 门洞用圆底同色「挖」出来，避免深色门在亮底上糊成一块
        theme.icon(root, theme.W - 38, 15, 16, "home", C.icon, C.card)
    end
    theme.click(root, theme.W - 44, 9, 28, 28, function()
        theme.go_defer(is_apps and "apps" or "home")
    end, 14)

    -- 底部亮线
    airui.container({ parent = root, x = 16, y = theme.TOP_H - 1,
        w = theme.W - theme.PAD * 2, h = 1, color = C.line })
end

--------------------------------------------------------------------
-- 统一点击层：透明容器 + 30ms 延迟执行 + 长按兜底
-- 触摸屏手指按下后只要有轻微位移（>10px）或触发滚动，LVGL 就把这次操作
-- 判成 moved/scrolled，CLICKED 事件会被丢弃，表现为「怎么点都没反应」。
-- 所以所有可点区域统一走这个函数，并额外绑长按（阈值 300ms）做兜底。
--------------------------------------------------------------------
function theme.click(parent, x, y, w, h, fn, radius)
    local fired = false
    local function run()
        local ok, err = pcall(fn)
        if not ok then print("[ui.click] " .. tostring(err)) end
    end
    -- 两条绑定路径（创建参数 on_click / 方法 set_on_click）可能都生效，
    -- 用 fired 保证一次触摸只执行一次回调
    local function later()
        if fired then return end
        fired = true
        sys.timerStart(function()
            fired = false
            run()
        end, 12)
    end
    -- on_click 走创建参数：部分固件的 container:set_on_click 失败时仍能点
    local b = airui.container({ parent = parent,
        x = math.floor(x), y = math.floor(y),
        w = math.floor(w), h = math.floor(h),
        color = theme.C.bg, color_opacity = 1, radius = radius or 0,
        on_click = later, on_long_press = later })
    pcall(function() b:set_on_click(later) end)
    pcall(function() b:set_on_long_press(later) end)
    return b
end

--------------------------------------------------------------------
-- 底栏 dock（58px）：首页/音乐/车辆 | 双区温度+风量 | 座椅/音量
--------------------------------------------------------------------
function theme.dockbar(root)
    local C = theme.C
    local db = theme.debounce()
    local dh = theme.DOCK_H
    local y = theme.H - dh - 12
    local yc = y + math.floor(dh / 2)          -- 58 高的底栏中线（y+29）
    airui.container({ parent = root, x = 16, y = y, w = theme.W - 32, h = dh,
        color = C.card2, radius = 14, border_color = C.line, border_width = 1 })

    local icons = { "home", "music", "car" }
    local pages = { "home", "music", "car" }
    for i = 1, 3 do
        local ix = 30 + (i - 1) * 44
        -- 原来图标顶边固定 y+12（中心 y+21），比右侧 38 高的温度框（中心 y+29）
        -- 高 8px，三个图标整体浮在上面（用户反馈「图标没有对齐」）→ 统一按中线摆
        -- 当前页再垫一个选中方底（对照参考图：选中项有浅色圆角块）
        if theme._cur_page == pages[i] then
            airui.container({ parent = root, x = ix - 6, y = yc - 15, w = 30, h = 30,
                color = C.sel, radius = 9 })
        end
        -- 房子的门洞用 dock 底色挖出来（深色门在深底上会糊成一块）
        theme.icon(root, ix, yc - 9, 18, icons[i], C.icon,
            icons[i] == "home" and C.card2 or C.icon)
        local p = pages[i]
        theme.click(root, ix - 8, yc - 17, 34, 34, function()
            -- 按下先补一层选中底色（对照参考图的浅色方块），再把图标盖回去，
            -- 否则跳页那一刻看不出「点中了哪个」
            if theme._cur_page ~= p then
                airui.container({ parent = root, x = ix - 6, y = yc - 15, w = 30, h = 30,
                    color = C.sel, radius = 9 })
                theme.icon(root, ix, yc - 9, 18, icons[i], C.icon,
                    icons[i] == "home" and C.card2 or C.icon)
            end
            theme.go_defer(p)
        end, 9)
    end

    -- 分隔线
    airui.container({ parent = root, x = 30 + 3 * 44 + 4, y = yc - 13, w = 1, h = 26, color = C.line })

    -- 双区温度控件 tctl（左 23°C / 右 19°C）+ 中间风量图标
    local function tctl(x, key)
        airui.container({ parent = root, x = x, y = yc - 19, w = 116, h = 38,
            color = C.deep, radius = 10, border_color = C.line2, border_width = 1 })
        theme.icon(root, x + 8, yc - 10, 20, "left", C.icon)
        local lbl = airui.label({ parent = root, x = x + 29, y = yc - 13, w = 58, h = 26,
            text = MOCK.ac.t[key] .. "°C", color = C.text, font_size = 18,
            align = airui.TEXT_ALIGN_CENTER })
        theme.icon(root, x + 88, yc - 10, 20, "right", C.icon)
        -- MOCK.ac_step 只改数据，label 建好之后不会自己变 —— 原来点箭头
        -- 数字纹丝不动（用户反馈「温度调节不了」），这里手动刷一次文本
        local function bump(d)
            MOCK.ac_step(key, d)
            pcall(function() lbl:set_text(MOCK.ac.t[key] .. "°C") end)
            -- 点箭头只改数字，用户不知道到底有没有点中 → 页面底部正中弹
            -- 「主驾 26°C / 副驾 21°C」提示
            theme.tip("ac_" .. key,
                (key == "l" and "主驾 " or "副驾 ") .. MOCK.ac.t[key] .. "°C")
        end
        theme.click(root, x, yc - 19, 28, 38, function() bump(-1) end, 8)
        theme.click(root, x + 88, yc - 19, 28, 38, function() bump(1) end, 8)
    end
    tctl(30 + 3 * 44 + 16, "l")
    theme.icon(root, 30 + 3 * 44 + 16 + 128, yc - 13, 26, "fan", C.blue2)
    tctl(30 + 3 * 44 + 16 + 128 + 34, "r")

    -- 右端的座椅 / 音量两个键用户要求去掉（底栏只留导航、温度、风量）
end

--------------------------------------------------------------------
-- 卡片（圆角 14 + 顶缘高亮线，对应 .card）
--------------------------------------------------------------------
function theme.card(parent, r, opts)
    local C = theme.C
    opts = opts or {}
    airui.container({
        parent = parent,
        x = r.x, y = r.y, w = r.w, h = r.h,
        color = opts.color or C.card,
        radius = opts.radius or 14,
        border_color = opts.border or C.line,
        border_width = 1,
    })
    if opts.hi ~= false then
        airui.container({ parent = parent, x = r.x + 10, y = r.y,
            w = r.w - 20, h = 1, color = C.hi, color_opacity = 120 })
    end
end

--------------------------------------------------------------------
-- 卡片头：标题 + 右侧小字（对应 .card-head）
--------------------------------------------------------------------
function theme.card_head(parent, r, title, right_txt, right_col)
    local C = theme.C
    -- h 必须 ≥ 字号的 1.35 倍：16 号中文字实际行高约 21~22，h=20 会把下缘裁掉
    airui.label({ parent = parent, x = r.x + 12, y = r.y + 11, w = r.w - 24, h = 22,
        text = title, color = C.title, font_size = 16 })
    if right_txt then
        airui.label({ parent = parent, x = r.x + 12, y = r.y + 11, w = r.w - 24, h = 22,
            text = right_txt, color = right_col or C.sub, font_size = 16,
            align = airui.TEXT_ALIGN_RIGHT })
    end
end

--------------------------------------------------------------------
-- 通用圆角按钮（容器 + 居中文本，样式完全受主题控制，
-- 不用 airui.button：其选中色硬编码 0x1A73E8，换肤不跟随）
--------------------------------------------------------------------
function theme.pill(parent, r, text, opts)
    local C = theme.C
    opts = opts or {}
    airui.container({
        parent = parent,
        x = r.x, y = r.y, w = r.w, h = r.h,
        color = opts.bg or C.sel,
        radius = opts.radius or math.floor(r.h / 2),
        border_color = opts.border or C.line,
        border_width = opts.bw or 1,
    })
    -- 文字框按 1.35 倍字号给高，否则中文字下缘会被裁
    local fh = math.floor((opts.font or 16) * 1.35)
    airui.label({ parent = parent, x = r.x, y = r.y + math.floor((r.h - fh) / 2),
        w = r.w, h = fh, text = text,
        color = opts.color or C.text, font_size = opts.font or 16,
        align = airui.TEXT_ALIGN_CENTER })
end

--------------------------------------------------------------------
-- 进度条（.progress：轨道 + 填充 + 圆形旋钮）
-- 返回 obj:set(pct 0~1) —— 用 shape:set_items 就地更新，避免整块重建
--------------------------------------------------------------------
function theme.progress(parent, r)
    local C = theme.C
    local kr  = r.knob or 4                 -- 旋钮半径（音乐页用 7 更醒目）
    local pad = math.max(4, kr + 1)         -- 画布上下留白，保证旋钮不出画布
    airui.container({ parent = parent, x = r.x, y = r.y, w = r.w, h = r.h,
        color = C.track, radius = math.floor(r.h / 2) })
    local shp = airui.shape({ parent = parent,
        x = r.x, y = r.y - pad, w = r.w, h = r.h + pad * 2, items = {} })
    local function set(pct)
        -- 数值兜底：调用方可能把控件句柄/字符串传进来（曾出现
        -- "attempt to perform arithmetic on a airui.slider" 直接重启），
        -- 这里统一转成数字再夹紧，坏值按 0 处理
        pct = tonumber(pct) or 0
        if pct > 1 then pct = 1 end
        if pct < 0 then pct = 0 end
        local fw = math.max(0, math.floor((r.w - 4) * pct))
        -- set_items 是对已有 shape 的二次重建，个别固件上会失败并抛错；
        -- 这里兜住，避免把调用方（整页构建 / 刷新回调）后面的代码一起带走
        pcall(function() shp:set_items({
            { type = "rect", x = 0, y = pad, w = fw, h = r.h,
              color = C.blue2, width = 1, radius = math.floor(r.h / 2),
              fill = true, fill_color = C.blue2, fill_opacity = 255 },
            -- 旋钮右缘不能越过画布（pct=1 时 fw+pad 会顶到边界）
            { type = "circle",
              cx = math.min(math.floor(fw + pad), r.w - pad - 1),
              cy = math.floor(pad + r.h / 2),
              r = kr, color = C.knob, width = 1,
              fill = true, fill_color = C.knob, fill_opacity = 255 },
        }) end)
    end
    -- 支持配置文件里直接给初始进度（r.pct），否则从 0 开始
    set(r.pct or 0)
    return { set = set }
end

--------------------------------------------------------------------
-- 折线 / 柱状图表（移植自「天气预报」工程 theme.chart）
-- 用 airui.chart 原生图元：自带 y 轴、网格、折线渐变填充，
-- 比之前手绘 theme._ln 的细线更像原型里的面积图
--   cfg.type   "line" | "bar"
--   cfg.color  折线/柱色     cfg.ylab=false 关闭 y 轴刻度
--   cfg.cats   底部要留时间轴位置
--------------------------------------------------------------------
function theme.chart(parent, a, cfg)
    cfg = cfg or {}
    local C = theme.C
    local y, h = a.y, a.h
    if cfg.cats then h = h - 22 end
    local px, pw = a.x + 40, a.w - 44          -- 绘图区（左侧留给 y 轴刻度）
    local ymax = cfg.y_max or 100
    local ymin = cfg.y_min or 0

    if cfg.ylab ~= false then
        for i = 0, 4 do
            local v = ymin + (ymax - ymin) * i / 4
            airui.label({ parent = parent,
                x = a.x, y = y + h - 18 - math.floor((h - 18) * i / 4),
                w = 36, h = 18, text = tostring(math.floor(v + 0.5)),
                color = C.dim, font_size = 16, align = airui.TEXT_ALIGN_RIGHT })
        end
    end

    return airui.chart({
        parent       = parent,
        x = px, y = y, w = pw, h = h,
        type         = cfg.type or "line",
        y_min        = ymin,
        y_max        = ymax,
        point_count  = cfg.points or 12,
        update_mode  = "shift",
        line_color   = cfg.color or C.blue2,
        line_width   = (cfg.type == "bar") and 2 or 3,
        point_radius = (cfg.type == "bar") and 0 or 3,
        -- 渐变填充参数只认 fill={enable,opa_start,opa_end}，fill_fade 不生效
        fill         = (cfg.type == "line" and cfg.fill ~= false) and
            { enable = true, color = cfg.color or C.blue2,
              opa_start = 140, opa_end = 0 } or nil,
        legend       = false,
        bg_color     = C.card,
        bg_opa       = 0,
        grid_color   = C.line,
        grid_opa     = 255,
        hdiv         = cfg.hdiv or 2,
        vdiv         = cfg.vdiv or 4,
        bar_radius   = 3,
    })
end

function theme.set_chart(ch, vals)
    pcall(ch.set_point_count, ch, #vals)
    local t = {}
    for k, v in ipairs(vals) do t[k] = math.floor(v + 0.5) end
    ch:set_values(1, t)
end

--------------------------------------------------------------------
-- 天气图标（云 + 雨丝）：纯 shape 绘制
-- 踩坑规避：不用 PNG；实心圆 width>=1；圆心/半径取整
--------------------------------------------------------------------
function theme.cloud_rain(parent, x, y, w, h, opts)
    local C = theme.C
    opts = opts or {}
    local cloud = opts.cloud or C.cloud
    local rainc = opts.rain or C.rain
    local items = {}
    local function ci(cx, cy, r, col, opa) _ci(items, cx, cy, r, col, opa) end
    -- 云朵（三圆 + 底部圆角矩形连体，近似 HTML 的云形）
    ci(w * 0.28, h * 0.55, h * 0.20, cloud, 250)
    ci(w * 0.52, h * 0.44, h * 0.26, cloud, 255)
    ci(w * 0.72, h * 0.58, h * 0.19, cloud, 250)
    _rc(items, w * 0.22, h * 0.50, w * 0.56, h * 0.28, cloud, math.floor(h * 0.12))
    -- 雨丝（3 条，错相位下落动画由 theme.anim_drops 驱动）
    local drops = {}
    _ln(drops, w * 0.32, h * 0.86, w * 0.28, h * 1.02, rainc, 2)
    _ln(drops, w * 0.52, h * 0.86, w * 0.48, h * 1.04, rainc, 2)
    _ln(drops, w * 0.72, h * 0.86, w * 0.68, h * 1.02, rainc, 2)
    theme.shapes(parent, x, y, w, h, items)
    local shp = airui.shape({ parent = parent, x = x, y = y,
        w = w, h = h + 8, items = drops })
    theme._rain_reg(shp, drops)
end

--------------------------------------------------------------------
-- 雨丝动画（沿用天气预报工程的 shape 轮换方案）：
-- 全局 200ms 定时器用 set_items 轮换相位；重建后已销毁 shape 自动剔除
--------------------------------------------------------------------
theme._drops = {}
theme._drops_timer = nil

function theme._rain_reg(shp, base, mode, flash_col)
    theme._drops[#theme._drops + 1] = { shp = shp, base = base, ph = 0,
        mode = mode or "rain", flash_col = flash_col }
    if not theme._drops_timer then
        theme._drops_timer = sys.timerLoopStart(theme.anim_drops, 200)
    end
end

function theme.anim_drops()
    for i = #theme._drops, 1, -1 do
        local e = theme._drops[i]
        local ok = pcall(function()
            if e.shp:is_destroyed() then error("gone") end
            e.ph = (e.ph + 1) % 6
            local items = {}
            for k, it in ipairs(e.base) do
                local dy = ((e.ph + k * 2) % 6) * 1.4
                items[#items + 1] = { type = "line",
                    x1 = math.floor(it.x1), y1 = math.floor(it.y1 + dy),
                    x2 = math.floor(it.x2), y2 = math.floor(it.y2 + dy),
                    color = it.color, width = it.width }
            end
            e.shp:set_items(items)
        end)
        if not ok then table.remove(theme._drops, i) end
    end
end

--------------------------------------------------------------------
-- 珠链圆环（沿圆周密集小圆拼接成实心环；shape 图元按 30 个/批 分开建）
-- segs = { {f=占比, color=..}, ... } 从 12 点方向顺时针排布；
-- start_deg 可指定起始角（默认 -90 即 12 点）
--------------------------------------------------------------------
function theme.arc_ring(parent, cx, cy, r, segs, start_deg, bead_r)
    cx, cy, r = math.floor(cx), math.floor(cy), math.floor(r)
    local total = 0
    for _, s in ipairs(segs) do total = total + s.f end
    local br = bead_r or 4
    local sd = (start_deg or -90)

    local ox, oy = r + 8, r + 8
    local sx, sy = cx - r - 8, cy - r - 8
    local items = { { type = "circle", cx = ox, cy = oy, r = r,
        color = theme.C.line, width = 1, fill = false, opacity = 120 } }

    -- 用 shape 的 arc 图元画（LVGL 的 lv_draw_arc）：一圈就是一根带子，
    -- 线宽 = 2*bead_r，外径取 r + bead_r，环带正好落在 r±bead_r。
    -- 原来是把圆周切成 90 多个 4~5px 的小圆珠串起来，软件渲染下每颗珠子
    -- 边缘都是锯齿、圆心取整还有台阶，用户反馈「圆弧不够圆滑」。
    -- 段与段之间不加圆头（rounded），接缝才是严丝合缝的一条连续弧。
    local a0 = sd
    for _, s in ipairs(segs) do
        local span = 360 * (s.f / total)
        if span > 0.3 then
            items[#items + 1] = { type = "arc", cx = ox, cy = oy,
                r = r + br, start_angle = math.floor(a0 + 0.5),
                end_angle = math.floor(a0 + span + 0.5),
                color = s.color, width = br * 2, opacity = 255 }
        end
        a0 = a0 + span
    end
    local sp
    local ok = pcall(function()
        sp = airui.shape({ parent = parent, x = sx, y = sy,
            w = 2 * r + 16, h = 2 * r + 16, items = items })
    end)
    if ok and sp ~= nil then return end

    -- 退路：老固件不认识 arc 图元时 airui.shape 返回 nil，改用旧的小圆珠
    -- 拼接（珠子多点、重叠 40%），保证环至少能画出来
    local N = math.floor(2 * math.pi * r / (br * 0.6) + 0.5)
    if N < 32 then N = 32 elseif N > 160 then N = 160 end
    items = { { type = "circle", cx = ox, cy = oy, r = r,
        color = theme.C.line, width = 1, fill = false, opacity = 120 } }
    for k = 0, N - 1 do
        local frac = (k + 0.5) / N
        local col = segs[#segs].color
        local acc = 0
        for _, s in ipairs(segs) do
            acc = acc + s.f / total
            if frac <= acc then col = s.color break end
        end
        local a = math.rad(sd + 360 * frac)
        items[#items + 1] = { type = "circle",
            cx = math.floor(ox + r * math.cos(a) + 0.5),
            cy = math.floor(oy + r * math.sin(a) + 0.5),
            r = br, color = col, width = 1,
            fill = true, fill_color = col, fill_opacity = 255 }
        if #items >= 30 then
            airui.shape({ parent = parent, x = sx, y = sy,
                w = 2 * r + 16, h = 2 * r + 16, items = items })
            items = {}
        end
    end
    if #items > 0 then
        airui.shape({ parent = parent, x = sx, y = sy,
            w = 2 * r + 16, h = 2 * r + 16, items = items })
    end
end

return theme
