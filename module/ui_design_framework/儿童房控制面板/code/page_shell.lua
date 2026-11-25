--[[
@module  page_shell
@summary 外壳：背景 / 顶栏（问候+名字+时钟+温湿度+主题）/ 底部四 Tab / 四页整页容器 / 主题重建
@version 2.0.0
@note 坐标与 docs/儿童房面板效果稿.html 逐项对齐：
        顶栏 0..76，内容区 88..520，底部 Tab 528..584。
      切页用「整页容器 set_pos(0,88) / (-1024,88)」（R13）：不 destroy、不 hide/open，切回不丢状态。
      只往负方向（左）推，正方向会在可滚动 screen 上出滚动条。
      主题切换要重建：AirUI 已建控件不会跟随令牌变色，只能销毁重画（点击时发生，约 30-60ms）；
      重建前先销毁改名弹层（键盘在顶层，不在 MAIN 下），再 bump_epoch 作废旧热区定时器。
]]
local T = require "ui_theme"
local C = T.c
local W = require "ui_widget"
local S = require "app_state"
local CAST = require "ui_cast"
local KB = require "ui_keyboard"

local M = {}

local SW, SH = 1024, 600
local CONTENT_Y, CONTENT_H = 88, 432
local TAB_Y = 528

-- 必须静态 require，而且**一行一个**：
--   1) 依赖裁剪只认字面量 require，用 require(名字表[i]) 会被判成未引用；
--   2) 扫描是按行抓 require "xxx" 的，四个写在同一行会被拼成一个模块名，
--      烧录时报「缺少 page_room", require "page_light", require "page_story", require "page_star.lua」。
local page_room = require "page_room"
local page_light = require "page_light"
local page_story = require "page_story"
local page_star = require "page_star"

local PAGES = { page_room, page_light, page_story, page_star }
local PAGE_NAMES = { "page_room", "page_light", "page_story", "page_star" }
local tab_names = { "我的房间", "灯光乐园", "故事时间", "星星奖励" }
local tab_icons = { "ic_star", "ic_lamp", "ic_note", "ic_flower" }

-- 键盘不可用时的兜底改名名单（点一下换下一个）
local PRESET_NAMES = { "小星星", "小月亮", "小太阳", "豆豆", "糖糖", "圆圆" }

local st = {
    cur = 1,
    objs = {},          -- 需要销毁重建的顶层容器
    pages = {},         -- { root, handle }
    tabs = {},          -- { {box, lbl, badge} }
    labels = {},        -- 顶栏文字与图片引用
}

M.state = st

-- ==================== 背景 ====================
local function build_bg(root)
    local bg = W.box(root, 0, 0, SW, SH, C.bg, 0)
    W.glass(bg, C.bg, 255)
    table.insert(st.objs, bg)

    local b1 = W.box(bg, 0, 0, SW, 300, C.band1, 0)
    W.glass(b1, C.band1, 255)
    local b2 = W.box(bg, 0, 300, SW, 300, C.band2, 0)
    W.glass(b2, C.band2, 255)

    -- 柔光斑：container 没有渐变，用大圆 + 低 alpha 近似（效果稿 .blob 的 12/13/10%）
    local blobs = {
        { 260, -190, -200, C.blob1, 31 },
        { 180, 630, -130, C.blob2, 33 },
        { 140, 830, 360, C.blob3, 26 },
    }
    for _, b in ipairs(blobs) do
        local d = b[1]
        local o = W.box(bg, b[2], b[3], d, d, b[4], math.floor(d / 2))
        W.glass(o, b[4], b[5])
    end
    return bg
end

-- ==================== 顶栏 ====================
local function build_topbar(root)
    local bar = W.box(root, 0, 0, SW, 76, -1, 0)

    -- 头像：点一下换下一个角色
    local av = W.card(bar, { x = 16, y = 14, w = 48, h = 48, radius = 16, shadow_opa = 40 })
    st.labels.avatar = W.sticker(av.inner, { name = CAST.img(false), x = 2, y = 2, w = 44, h = 44 })
    W.press(bar, { x = 16, y = 14, w = 48, h = 48, radius = 16,
        target = av.root, tx = 16, ty = 14, flash = C.pri, flash_opa = 40,
        on_click = function() M.next_cast(1) end })

    -- 问候 + 名字（名字可点开键盘改）
    st.labels.greet = W.text_mid(bar, { text = "", x = 74, y = 14, w = 58, h = 30,
        size = T.f.body, color = C.ink })
    st.labels.name = W.text_mid(bar, { text = "", x = 132, y = 14, w = 150, h = 30,
        size = T.f.body, color = C.ink })
    st.labels.date = W.text_mid(bar, { text = "", x = 74, y = 44, w = 230, h = 22,
        size = T.f.sub, color = C.ink2 })
    W.press(bar, { x = 130, y = 12, w = 158, h = 34, radius = 10,
        on_click = function() M.rename() end })

    -- 时钟卡（两侧各一枚装饰贴纸）
    local ck = W.card(bar, { x = 300, y = 12, w = 240, h = 64, radius = 20 })
    W.deco(ck.inner, { name = CAST.sticker(2), x = 8, y = 20, w = 24, h = 24 })
    st.labels.clock = W.text_mid(ck.inner, { text = "--:--", x = 0, y = 2, w = 240, h = 42,
        size = T.f.h1, color = C.ink, align = airui.TEXT_ALIGN_CENTER })
    st.labels.hint = W.text_mid(ck.inner, { text = "", x = 0, y = 44, w = 240, h = 20,
        size = T.f.sub, color = C.ink3, align = airui.TEXT_ALIGN_CENTER })
    W.deco(ck.inner, { name = CAST.sticker(5), x = 208, y = 20, w = 24, h = 24 })

    -- 室内外温湿度胶囊
    local function pill(x, icon, val, tag)
        local p = W.card(bar, { x = x, y = 22, w = 150, h = 44, radius = 22, shadow_opa = 40 })
        W.sticker(p.inner, { name = icon, x = 10, y = 8, w = 28, h = 28 })
        local v = W.text_mid(p.inner, { text = val, x = 44, y = 8, w = 52, h = 28,
            size = T.f.body, color = C.ink })
        local t = W.text_mid(p.inner, { text = tag, x = 96, y = 10, w = 46, h = 24,
            size = T.f.sub, color = C.ink2 })
        return v, t
    end
    st.labels.out = pill(560, "ic_sun", "18°", "室外")
    st.labels.inn = pill(716, "ic_drop", "23°", "室内")

    -- 主题按钮：点一下循环 5 套主题（原地重建）
    local tb = W.card(bar, { x = 874, y = 22, w = 118, h = 44, radius = 22,
        color = C.pri, shadow_opa = 50 })
    st.labels.theme = W.text_mid(tb.inner, { text = "", x = 0, y = 0, w = 118, h = 44,
        size = T.f.sub, color = C.white, align = airui.TEXT_ALIGN_CENTER })
    W.press(bar, { x = 874, y = 22, w = 118, h = 44, radius = 22, target = tb.root,
        tx = 874, ty = 22, flash = 0xFFFFFF, flash_opa = 60,
        on_click = function() M.next_theme() end })
    return bar
end

-- ==================== 底部 Tab ====================
local function refresh_tabs()
    for i, t in ipairs(st.tabs) do
        local on = (i == st.cur)
        W.glass(t.box, on and C.pri or C.card, 255)
        -- 选中态底色是主色，彩色贴图压在上面会发闷，垫一个半透明白圆做「徽标底」
        if t.badge then W.glass(t.badge, C.white, on and 210 or 0) end
        pcall(function() t.lbl:set_color(on and C.white or C.ink2) end)
    end
end

local function build_tabs(root)
    local bar = W.box(root, 0, TAB_Y, SW, 56, -1, 0)
    local x = 16
    for i = 1, 4 do
        local card = W.card(bar, { x = x, y = 0, w = 238, h = 56, radius = 20, shadow_opa = 40 })
        local badge = W.box(card.inner, 58, 12, 32, 32, C.white, 16)
        W.glass(badge, C.white, 0)
        W.sticker(card.inner, { name = tab_icons[i], x = 61, y = 15, w = 26, h = 26 })
        local lbl = W.text_mid(card.inner, { text = tab_names[i], x = 97, y = 0, w = 96, h = 56,
            size = T.f.body, color = C.ink2, align = airui.TEXT_ALIGN_LEFT })
        st.tabs[i] = { box = card.inner, lbl = lbl, badge = badge }
        W.press(bar, { x = x, y = 0, w = 238, h = 56, radius = 20,
            flash = C.pri, flash_opa = 40,
            on_click = function() M.switch(i) end })
        x = x + 246
    end
    return bar
end

-- ==================== 页面 ====================
local ctx = {}                       -- 传给各页的上下文（避免页面反向 require page_shell 造成循环）

--- 建一页的内容（懒加载：切主题时只重建当前页，其余等切过去再建）
local function build_page(i)
    local p = st.pages[i]
    if not p or not p.pending then return end
    local ok, handle = pcall(PAGES[i].create, p.root, ctx)
    if not ok then
        log.error("page_shell", "页面创建失败", PAGE_NAMES[i], tostring(handle))
        handle = { refresh = function() end }
    end
    p.handle = handle
    p.pending = false
end

local function build_pages(root)
    ctx.on_cast_change = function(dir, idx)
        if dir then CAST.next(dir) end
        if idx then CAST.select(idx) end
        log.info("page_shell", "切角色", CAST.idx(), CAST.name(), CAST.room_name())
        M.refresh_pages()
        M.refresh_top()
    end

    st.pages = {}
    for i = 1, 4 do
        local pr = W.box(root, i == st.cur and 0 or -SW, CONTENT_Y, SW, CONTENT_H, -1, 0)
        table.insert(st.objs, pr)
        st.pages[i] = { root = pr, handle = nil, pending = true }
    end
    -- 只建当前页：4 页全建要 ~1s（真机每页 40+ 控件），切主题时只付 1/4
    build_page(st.cur)
end

-- ==================== 顶栏数据 ====================
function M.refresh_top()
    local clk = S.clock()
    if st.labels.clock then pcall(function() st.labels.clock:set_text(clk.hhmm) end) end
    if st.labels.hint then pcall(function() st.labels.hint:set_text(clk.hint) end) end
    if st.labels.greet then pcall(function() st.labels.greet:set_text(clk.greet) end) end
    if st.labels.date then pcall(function() st.labels.date:set_text(clk.date) end) end
    if st.labels.name then pcall(function() st.labels.name:set_text(S.kid_name()) end) end
    if st.labels.out then pcall(function() st.labels.out:set_text(S.env.temp_out .. "°") end) end
    if st.labels.inn then pcall(function() st.labels.inn:set_text(S.env.temp_in .. "°") end) end
    if st.labels.theme then
        pcall(function()
            st.labels.theme:set_text(string.format("%s %d/%d", T.name, T.idx, T.count))
        end)
    end
    W.set_image(st.labels.avatar, CAST.img(false))
end

-- ==================== 改名 ====================
function M.rename()
    local opened = KB.open({
        parent = st.main,
        value = S.kid_name(),
        on_done = function(v)
            log.info("page_shell", "改名", S.kid_name(), "->", tostring(v))
            S.set_kid_name(v)
            M.refresh_top()
        end,
    })
    if opened then return end

    -- 键盘不可用（固件没编 IME）：退化为点名字循环预设名，功能不丢
    local cur = S.kid_name()
    local idx = 0
    for i, v in ipairs(PRESET_NAMES) do
        if v == cur then idx = i end
    end
    S.set_kid_name(PRESET_NAMES[idx % #PRESET_NAMES + 1])
    M.refresh_top()
    log.warn("page_shell", "键盘不可用，名字改为预设循环", S.kid_name())
end

-- ==================== 对外接口 ====================

--- 毫秒时钟（PC/真机都有 mcu.ticks；取不到就返回 nil，仅影响计时日志）
local function now_ms()
    local ok, v = pcall(function() return mcu.ticks() end)
    if ok and type(v) == "number" then return v end
    return nil
end

function M.create()
    local t0 = now_ms()
    st.objs = {}
    st.pages = {}
    st.tabs = {}
    st.labels = {}

    -- airui.screen 只允许挂一个直系子容器：屏幕本身是自动排布（flex）容器，
    -- 直接往 screen 上挂多个同级控件会被排布/压缩（实测只剩顶栏，页面与 Tab 全部消失）。
    -- 所以先建一张关掉滚动的整屏画布 MAIN，后面所有层都挂在 MAIN 上。
    local main = W.box(airui.screen, 0, 0, SW, SH, -1, 0, false)
    table.insert(st.objs, main)
    st.main = main

    table.insert(st.objs, build_bg(main))
    local t1 = now_ms()
    table.insert(st.objs, build_topbar(main))
    local t2 = now_ms()
    build_pages(main)                  -- 每页根容器单独登记，切主题时逐个销毁
    local t3 = now_ms()
    table.insert(st.objs, build_tabs(main))
    refresh_tabs()
    M.refresh_top()
    local t4 = now_ms()
    log.info("page_shell", "界面已创建", "主题=" .. T.name, "角色=" .. CAST.name())
    if t0 and t1 and t2 and t3 and t4 then
        log.info("page_shell", "重建分段(ms)", "bg", t1 - t0, "top", t2 - t1,
            "page", t3 - t2, "tab", t4 - t3, "合计", t4 - t0)
    end
    -- 开机也把其余三页补齐（1.2s 后再动手，别抢首帧和背光）；切主题走 next_theme 里的 120ms
    M.fill_later(1200)
end

--- 后台把还处于 pending 的页建出来：一次一页，单链 timerStart（不是 timerLoopStart），建完即停。
--- 好处：切主题当场只付 1/4 的时间，之后点 Tab 不卡；重复调度也安全（build_page 自己看 pending）。
function M.fill_later(delay)
    local function step()
        for i = 1, 4 do
            local p = st.pages[i]
            if p and p.pending then
                build_page(i)
                sys.timerStart(step, 120)
                return
            end
        end
    end
    sys.timerStart(step, delay or 120)
end

--- 切页：只推位置，不销毁（R13）
function M.switch(i)
    if not st.pages[i] or i == st.cur then return end
    -- 懒页：第一次切过去才建内容（页面此刻还在屏幕外，建完再推上来，看不到中间态）
    build_page(i)
    local old = st.pages[st.cur]
    if old then pcall(function() old.root:set_pos(-SW, CONTENT_Y) end) end
    local new = st.pages[i]
    pcall(function() new.root:set_pos(0, CONTENT_Y) end)
    st.cur = i
    refresh_tabs()
    M.refresh_current()
    log.info("page_shell", "切页", i, tab_names[i])
end

--- 只刷当前页（隐藏页不刷，避免一次点击同步刷新四页）
function M.refresh_current()
    local p = st.pages[st.cur]
    if p and p.handle and p.handle.refresh then
        local ok, err = pcall(p.handle.refresh)
        if not ok then log.error("page_shell", "页面刷新失败", PAGE_NAMES[st.cur], tostring(err)) end
    end
end

--- 刷全部页（角色切换会同时影响页1 大角色、页2 预览圆、页3 封面）
--- 懒页还没建内容，跳过它（切过去时 create 会按最新状态画）
function M.refresh_pages()
    for i, p in ipairs(st.pages) do
        if p.handle and not p.pending and p.handle.refresh then
            local ok, err = pcall(p.handle.refresh)
            if not ok then
                log.error("page_shell", "页面刷新失败", PAGE_NAMES[i], tostring(err))
            end
        end
    end
end

--- 切主题：销毁所有顶层容器后按新令牌重建（保留当前页）
function M.next_theme()
    local keep = st.cur
    T.next()
    log.info("page_shell", "切换主题", T.idx, T.name)
    W.defer(function()
        local t0 = now_ms()
        KB.destroy()            -- 键盘在顶层，不是 MAIN 的子控件，必须单独销毁
        W.clear_twinkle()
        W.bump_epoch()          -- 作废旧热区的回弹定时器，再销毁控件
        for _, o in ipairs(st.objs) do
            pcall(function() o:destroy() end)
        end
        st.objs = {}
        M.create()
        M.switch_force(keep)
        local t1 = now_ms()
        if t0 and t1 then
            log.info("page_shell", "主题重建耗时", t1 - t0, "ms")
        end
        -- 其余三页后台补齐：当场只付 1/4 的时间，之后点 Tab 不会卡
        M.fill_later(120)
    end, 30)
end

--- 强制切到某页（重建后位置是默认第 1 页，需要复位）
function M.switch_force(i)
    i = math.max(1, math.min(4, i or 1))
    build_page(i)
    for k, p in ipairs(st.pages) do
        pcall(function() p.root:set_pos(k == i and 0 or -SW, CONTENT_Y) end)
    end
    st.cur = i
    refresh_tabs()
    M.refresh_current()
end

--- 主循环心跳：500ms 一跳，只改文字/颜色/透明度
function M.tick(dt_ms)
    M.refresh_top()
    local playing = S.story_tick(dt_ms)
    if playing and st.cur == 3 then M.refresh_current() end
    W.tick_twinkle()
end

return M
