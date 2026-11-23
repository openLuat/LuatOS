--[[
@module  page_wash
@summary 净界洗车 · 自助洗车机主界面（1024x600 / 晨曦白·夜青双主题）
@version 1.0.0
@note 与 docs/方案A_水光玻璃.html 一一对应：
      顶栏（品牌 / 状态芯片 / 时钟 / 主题 / 帮助）
      + 三栏（洗车方案 / 洗车房实时 / 结算）
      + 三阶段（选方案 → 洗车中 → 完成评价）
      + 扫码支付弹层 + 外观主题菜单。
      纪律：子控件不探出父容器内容区（AirUI 滚动条关不掉）；
           显隐一律靠「销毁重建」，不用 hide/open（真机 open 恢复不回来）；
           任何会销毁控件的操作都延后一帧执行，避免销毁正在命中的对象。
]]
local T = require "ui_theme"
local W = require "ui_widget"
local S = require "app_state"
local C, G = T.c, T.glass
local M = {}

-- 构建标记：每次改完代码改这里，日志里能确认模拟器加载的是哪一版
local BUILD_TAG = "20261118-1510"

local SW, SH = T.screen.w, T.screen.h
local BASE, PAGE, ROOT, PANELS
local PANELS_SELECT                              -- 选方案阶段容器（render_steps 运行时要用）
local gen = 0                                    -- 重建代数：旧定时器回调自动失效
local t_clock, t_wash, t_pay
local pay_left = 180
local paying = false                             -- 支付按钮处理中：防重复点击
local toast_box

-- 顶栏句柄
local lbl_clock, lbl_date, lbl_dev, lbl_bay, lbl_cam_tag
-- 左栏句柄
local pkg_cards, addon_chips, steps_box, lbl_pkg_dur, lbl_step_cnt
local steps_sig                                  -- 工序列表签名：内容不变就不重建
local refresh_sig                                -- 右栏结算签名：金额没变就不刷新
local clock_cache                                -- 时钟字符串缓存：同值不重绘
-- 右栏句柄
local bill_vals, lbl_total, lbl_coupon_state, coupon_box, coupon_in, lbl_pay
-- 洗车中 / 完成 / 弹层
local wash_ui, done_ui, pay_ui, menu_ui

-- 前置声明（闭包互相引用）
local refresh_select, refresh_stars, build_panels, set_stage, reset_to_select, render_steps
local fill_done
local start_wash, paint_wash, stop_wash, start_ticker
local open_pay, close_pay, open_menu, close_menu

-- ==================== 布局常量（对应 HTML 1024x600） ====================
local TOP   = { x = 18, y = 16, w = 988, h = 64 }
-- PANELS 从 y=80 起（顶栏 16..80 不能被全屏容器盖住，否则顶栏按钮点不到），
-- 所以三栏卡片坐标改成相对 PANELS 的 12 = 92 - 80
local PANEL_Y = 80
local MAIN_Y, MAIN_H = 12, 492
local COL   = { L = { x = 18, w = 430 }, M = { x = 460, w = 322 }, R = { x = 794, w = 212 } }
local IN_L, IN_M, IN_R = 402, 292, 184          -- 三栏内容宽

-- ==================== 通用 ====================
-- hzfont 缺 ¥(U+00A5) / ✓(U+2713) / —(U+2014) 字形，统一改用 ￥、symbol、汉字
local function money(v) return "￥" .. v end

-- 图片根目录：Luatools 下载 / --llt 模拟器都把资源**摊平**放进 /luadb，
-- 即 /luadb/pkg-water.jpg，没有 img/ 这一层，所以 /luadb/ 是第一顺位（且不去探测 /luadb/img/，
-- 否则每次启动都会打一条 "fopen /luadb/img/pkg-water.jpg not found"）。
-- 其余候选只在非 Luatools 场景（直接跑 exe、工程目录带 img）兜底。
local IMG_BASE

local function find_demo_img()
    if not (io and io.lsdir) then return nil end
    -- io.lsdir 一次最多返回 len 条，/demo 下有上百个工程，必须分页扫
    local off, page = 0, 50
    for _ = 1, 8 do
        local ok, list = io.lsdir("/demo", page, off)
        if not ok or type(list) ~= "table" or #list == 0 then return nil end
        for _, v in ipairs(list) do
            local name = (type(v) == "table") and v.name or nil
            if name then
                local base = "/demo/" .. name .. "/img/"
                local ok2, e = pcall(io.exists, base .. "pkg-water.jpg")
                if ok2 and e then return base end
            end
        end
        if #list < page then return nil end
        off = off + #list
    end
    return nil
end

local function img_base()
    if IMG_BASE ~= nil then return IMG_BASE or nil end
    for _, b in ipairs({ "/luadb/", "/img/", "img/" }) do
        local ok, e = pcall(io.exists, b .. "pkg-water.jpg")
        if ok and e then
            IMG_BASE = b
            log.info("page_wash", "图片目录", b)
            return b
        end
    end
    local d = find_demo_img()
    if d then
        IMG_BASE = d
        log.info("page_wash", "图片目录", d)
        return d
    end
    IMG_BASE = false
    log.warn("page_wash", "未找到图片目录，改用图标占位")
    return nil
end

-- 浮层提示：始终画在 ROOT 的最后一层（最上面），2.6s 后自动销毁。
-- 注意：切阶段会重建 PANELS，新面板会盖住旧提示，所以 rebuild 后要重画一次。
local toast_msg, toast_box, toast_mark, toast_idx
local menu_mark, pay_mark, steps_mark              -- 临时界面的登记起点
local steps_idx                                    -- 工序行在登记表里的索引（销毁时精确作废）

local function draw_toast()
    if toast_box then
        pcall(function() toast_box:destroy() end)
        toast_box = nil
        W.reg_kill(toast_idx)                    -- 只作废这条提示自己的登记项
    end
    if not ROOT or not toast_msg then return end
    toast_mark = W.reg_mark()
    -- HTML #toast：底部居中、浅底 + 主色描边、文字用正文色
    local box = W.box(ROOT, 252, 534, 520, 42, C.card, 12, 246, C.edge, 1)
    W.text_mid(box, { text = toast_msg, x = 12, y = 0, w = 496, h = 42, size = T.f.sub,
        color = C.text, align = airui.TEXT_ALIGN_CENTER })
    toast_box = box
    toast_idx = W.reg_group(toast_mark)
end

local function toast(msg)
    toast_msg = msg
    draw_toast()
    -- 用文案本身判定，避免重建（gen 变化）导致定时器失效、提示永不消失
    sys.timerStart(function()
        if toast_msg == msg then
            toast_msg = nil
            if toast_box then
                pcall(function() toast_box:destroy() end)
                toast_box = nil
                W.reg_kill(toast_idx)
            end
        end
    end, 2600)
end

-- 描边按钮（HTML .ghost：透明底 + 1px hair3 描边，不是填充块）
local function ghost_btn(parent, cfg)
    local r = cfg.radius or 12
    W.stroke(parent, cfg.x, cfg.y, cfg.w, cfg.h, r, G.hair_color, G.hair3_opa)
    local lbl = W.text_mid(parent, { text = cfg.text or "", x = cfg.x, y = cfg.y,
        w = cfg.w, h = cfg.h, size = cfg.size or T.f.sub,
        color = cfg.tcolor or C.text_sub, align = airui.TEXT_ALIGN_CENTER })
    W.press_layer(parent, { x = cfg.x, y = cfg.y, w = cfg.w, h = cfg.h,
        radius = r, on_click = cfg.on_click })
    return { lbl = lbl }
end

-- 实心按钮（HTML .cta：主色渐变 + 顶部内高光 + 投影）
local function pill(parent, cfg)
    local r = cfg.radius or T.r.chip
    local box = W.box(parent, cfg.x, cfg.y, cfg.w, cfg.h,
        cfg.color or C.pri, r, cfg.opa or 255)
    if cfg.glow ~= false then
        -- 顶部 1px 高光（HTML inset 0 1px 0 rgba(255,255,255,.42)）
        local hl = W.box(parent, cfg.x + 2, cfg.y + 1, cfg.w - 4, 1, 0xFFFFFF, 0, 0)
        W.glass(hl, 0xFFFFFF, 96)
    end
    local label = W.text_mid(parent, { text = cfg.text or "", x = cfg.x, y = cfg.y,
        w = cfg.w, h = cfg.h, size = cfg.size or T.f.body,
        color = cfg.tcolor or C.on_pri, weight = cfg.weight,
        align = airui.TEXT_ALIGN_CENTER })
    local hit = W.press_layer(parent, { x = cfg.x, y = cfg.y, w = cfg.w, h = cfg.h,
        radius = r, on_click = cfg.on_click })
    return { box = box, lbl = label, hit = hit }
end

-- ==================== 背景 ====================
local BG, BG_BANDS = nil, {}                     -- 背景容器 + 色带对象（主题热切换时只改色不重建）
local BG_T = {}                                  -- 各色带的插值位置

local function bg_mix(a, b, t)
    local function ch(v, sh) return math.floor(v / sh) % 256 end
    local ar, ag, ab = ch(a, 65536), ch(a, 256), a % 256
    local br, bg2, bb = ch(b, 65536), ch(b, 256), b % 256
    return math.floor(ar + (br - ar) * t + 0.5) * 65536
         + math.floor(ag + (bg2 - ag) * t + 0.5) * 256
         + math.floor(ab + (bb - ab) * t + 0.5)
end

local function bg_color_at(t)
    local stops = { { 0.0, G.bg_top }, { 0.44, G.bg_mid or G.bg_top }, { 1.0, G.bg_bot } }
    for k = 2, #stops do
        if t <= stops[k][1] or k == #stops then
            local p0, c0 = stops[k - 1][1], stops[k - 1][2]
            local p1, c1 = stops[k][1], stops[k][2]
            local u = (p1 > p0) and ((t - p0) / (p1 - p0)) or 0
            return bg_mix(c0, c1, math.max(0, math.min(1, u)))
        end
    end
    return G.bg_top
end

local BG_PHOTO = nil                             -- 背景图对象（有图时用它，没图用色带）
local bg_mark, bg_idx                            -- 色带在颜色登记表里的区间（重建时精确作废）

-- 在现有 BG 容器内重建内容：首次构建与主题热切换共用。
-- 只重建 BG 的子控件，BG 本身位置不变，z 序不受影响。
local function bg_apply()
    if not BG then return end
    if BG_PHOTO then pcall(function() BG_PHOTO:destroy() end); BG_PHOTO = nil end
    for _, b in ipairs(BG_BANDS) do pcall(function() b:destroy() end) end
    W.reg_kill(bg_idx)                           -- 旧色带的登记项作废，否则改色时会访问已销毁对象
    BG_BANDS, BG_T = {}, {}
    pcall(function() BG:set_color(G.bg_top, 255) end)
    -- 首选：HTML 渲染出来的整幅背景（含渐变 + 光晕），像素一致
    local base = img_base()
    if base then
        local path = base .. "bg_" .. T.mode .. ".jpg"
        local ok, e = pcall(io.exists, path)
        if ok and e then
            BG_PHOTO = W.photo(BG, { x = 0, y = 0, w = SW, h = SH, src = path, fit = "stretch" })
            if BG_PHOTO then return end
        end
    end
    -- 兜底：色带近似（三段 0% / 44% / 100%）
    local N = 12
    bg_mark = W.reg_mark()
    for i = 0, N - 1 do
        local t = (N > 1) and (i / (N - 1)) or 0
        local y0 = math.floor(i * SH / N)
        local y1 = math.floor((i + 1) * SH / N)
        -- 每档向下多 1px 盖住取整缝隙，最后一档正好到屏幕底
        BG_BANDS[i + 1] = W.box(BG, 0, y0, SW, y1 - y0 + 1, bg_color_at(t), 0, 255)
        BG_T[i + 1] = t
    end
    bg_idx = W.reg_group(bg_mark)
end

local function build_background()
    BG = W.box(ROOT, 0, 0, SW, SH, G.bg_top, 0, 255, nil, nil, nil, "bg_top")
    bg_apply()
end

-- 主题热切换：换背景图 / 重算色带（不销毁 BG 本身，避免盖住面板）
local function repaint_background() bg_apply() end

-- ==================== 顶栏 ====================
-- 状态芯片：HTML 里「设备就绪」带圆点，「洗车房 A · 空闲」不带（只有文字）
local function status_chip(parent, x, w, name, with_dot)
    -- 胶囊统一用不透明实色（G.chip_bg），保证与附加服务芯片底色完全一致
    local box = W.box(parent, x, 15, w, 34, G.chip_bg or 0xFFFFFF, 17, 255,
        nil, nil, nil, "chip_bg")
    W.stroke(parent, x, 15, w, 34, 17, G.chip_edge or G.hair_color,
        G.chip_edge_opa or G.hair3_opa, "chip_edge_opa")
    local dot, lbl
    if with_dot then
        -- HTML .chip i：默认 --accent，.busy 时 --accent2
        dot = W.box(parent, x + 13, 28, 7, 7, C.pri, 4, 255)
        lbl = W.text_mid(parent, { text = name, x = x + 27, y = 15, w = w - 32, h = 34,
            size = T.f.sub, color = C.text_sub })
    else
        lbl = W.text_mid(parent, { text = name, x = x + 13, y = 15, w = w - 26, h = 34,
            size = T.f.sub, color = C.text_sub })
    end
    local h = { dot = dot, lbl = lbl, box = box }
    -- 圆点三态：nil = 就绪(accent) / "busy" = 运行中(accent2) / "off" = 提醒(warn)
    function h.set(txt, kind)
        if dot then
            local col = C.pri
            if kind == "busy" then col = C.accent2 or C.pri
            elseif kind == "off" then col = C.warn or C.pri end
            W.glass(dot, col, 255)
        end
        pcall(function() lbl:set_text(txt) end)
    end
    return h
end

local function build_topbar()
    local g = W.glass_card({ parent = ROOT, x = TOP.x, y = TOP.y, w = TOP.w, h = TOP.h })
    local p = g.card
    -- 品牌：38 水滴标记 + 名称 18/600 + 门店 16/dim
    W.box(p, 18, 13, 38, 38, C.pri, 12, 255)
    -- 品牌图标：水滴。HTML 是 24×24 viewBox 的泪滴路径：
    --   顶点 (12,3.2)、底圆 心(12,12.4) r=5.6
    -- 这里换算到 38×38 标记内（20×20 绘制区，居中），底圆 + 切线三角逐行填充。
    local drop = {}
    local cx, apex_y, tri_y = 19, 11, 16
    -- 半径必须是整数：binding 里按 int 解析，浮点会被截断成 0（图标消失）
    drop[#drop + 1] = { type = "circle", cx = cx, cy = 20, r = 5,
        color = C.on_pri, width = 1, fill = true, fill_color = C.on_pri }
    for y = apex_y, tri_y do
        local t = (y - apex_y) / (tri_y - apex_y)
        local half = math.max(1, math.floor(4.6 * t + 0.5))
        drop[#drop + 1] = { type = "line", x1 = cx - half, y1 = y, x2 = cx + half, y2 = y,
            color = C.on_pri, width = 1 }
    end
    W.shape(p, { x = 18, y = 13, w = 38, h = 38, items = drop })
    W.text(p, { text = "净界洗车", x = 68, y = 8, w = 160, h = 24, size = T.f.body,
        color = C.text, weight = 700 })
    -- 门店名需要约 126px（「万象城店 B2-A」），芯片相应右移让位
    W.text(p, { text = "万象城店 B2-A", x = 68, y = 33, w = 126, h = 20, size = T.f.sub,
        color = C.text_dim })
    -- 状态芯片（HTML：品牌后 margin-left 6 / gap 8，高 34 / 圆角 17 / padding 0 13）
    lbl_dev = status_chip(p, 200, 108, "设备就绪", true)
    -- 宽度按最长文案「洗车房 A · 洗车中」（约 144px）+ padding 26
    lbl_bay = status_chip(p, 316, 172, "洗车房 A · 空闲", false)
    -- 循环水：与其它胶囊同底色/描边（区间 496..612，与洗车房芯片 gap 8）
    local wtr = W.box(p, 496, 15, 116, 34, G.chip_bg or 0xFFFFFF, 17, 255,
        nil, nil, nil, "chip_bg")
    W.stroke(p, 496, 15, 116, 34, 17, G.chip_edge or G.hair_color,
        G.chip_edge_opa or G.hair3_opa, "chip_edge_opa")
    W.text_mid(wtr, { text = "循环水 85%", x = 0, y = 0, w = 116, h = 34, size = T.f.sub,
        color = C.text_sub, align = airui.TEXT_ALIGN_CENTER })
    -- 右侧：会员 / 时钟（两行）/ 主题图标按钮 / 帮助
    local ava = W.box(p, 672, 19, 26, 26, C.pri, 13, 255)
    W.text_mid(ava, { text = "屿", x = 0, y = 0, w = 26, h = 26, size = T.f.sub,
        color = C.on_pri, align = airui.TEXT_ALIGN_CENTER })
    W.text_mid(p, { text = "陈屿", x = 704, y = 16, w = 42, h = 32, size = T.f.sub, color = C.text_sub })
    -- 宽度必须容得下 HH:MM:SS（8 字），88 只够 HH:MM，真机上秒数会被裁掉
    lbl_clock = W.text(p, { text = "", x = 726, y = 13, w = 116, h = 26, size = 22,
        color = C.text, align = airui.TEXT_ALIGN_RIGHT })
    -- 日期文案是「11月18日 周三」，需要更宽（88 会把「周三」裁掉）
    lbl_date = W.text(p, { text = "", x = 702, y = 38, w = 140, h = 20, size = T.f.sub,
        color = C.text_dim, align = airui.TEXT_ALIGN_RIGHT })
    -- 主题：38x38 图标按钮。HTML .iconbtn 是「透明底 + 1px --hair3 描边」，
    -- 描边用 shape 画（container border 在圆角处会变直角，且不随主题换透明度）
    local tb = airui.container({ parent = p, x = 852, y = 13, w = 38, h = 38,
        color = -1, border_width = 0, radius = 12, scrollable = false })
    W.stroke(p, 852, 13, 38, 38, 12, G.hair_color, G.hair3_opa, "hair3_opa")
    -- 图标：半黑半白的对比度圆（对应 HTML 的 .iconbtn svg：圆环 + 右半实心）
    W.shape(tb, { x = 0, y = 0, w = 38, h = 38, items = {
        -- HTML: 19px 图标里 circle r=8.2 stroke 1.6 → 直径≈14.2、描边≈1.3
        -- 先画右半实心（arc 的 r 为外半径，r=4+width 7 覆盖 0..7.5），再用细环压边
        { type = "arc", cx = 19, cy = 19, r = 4, start_angle = 270, end_angle = 90,
          color = C.text_sub, width = 7 },
        { type = "circle", cx = 19, cy = 19, r = 7, color = C.text_sub, width = 1 },
    } })
    -- 帮助：36 高幽灵按钮（HTML .ghost：透明底 + 1px --hair3 描边）
    local hb = airui.container({ parent = p, x = 904, y = 14, w = 66, h = 36,
        color = -1, border_width = 0, radius = 18, scrollable = false })
    W.stroke(p, 904, 14, 66, 36, 18, G.hair_color, G.hair3_opa, "hair3_opa")
    W.text_mid(hb, { text = "帮助", x = 0, y = 0, w = 66, h = 36, size = T.f.sub,
        color = C.text_sub, align = airui.TEXT_ALIGN_CENTER })
    -- 热区必须压在文字/图标之上：LVGL 事件不冒泡，label 会吃掉点击
    W.press_layer(p, { x = 852, y = 13, w = 38, h = 38, radius = 12,
        on_click = function() open_menu() end })
    W.press_layer(p, { x = 904, y = 14, w = 66, h = 36, radius = 18,
        on_click = function() toast("客服 400-800-1234 · 24 小时营业") end })
end

-- ==================== 左栏：方案 / 附加服务 ====================
local function pkg_image(p)
    local b = img_base()
    if not b then return nil end
    if p.id == 1 then return b .. "pkg-water.jpg" end
    if p.id == 3 then return b .. "pkg-polish.jpg" end
    return b .. "pkg-foam.jpg"
end

local function thumb(parent, x, y, w, h, src)
    W.box(parent, x, y, w, h, C.deep, T.r.thumb, 255)
    if not W.photo(parent, { x = x, y = y, w = w, h = h, src = src, fit = "cover" }) then
        W.icon(parent, { symbol = airui.SYMBOL_IMAGE, x = x + math.floor((w - 20) / 2),
            y = y + math.floor((h - 20) / 2), size = 20, w = 20, h = 20, color = C.text_dim })
    end
end

local function build_pkg_card(parent, i, y)
    local p = S.pkgs[i]
    -- 描边用「外框 + 内填」两层：LVGL 的 border 在圆角处会画成直角
    -- HTML .pkg：100 高 / 圆角 16 / 1px hair2 描边（选中时描边转主色）
    local box = W.box(parent, 13, y, IN_L, 100, C.pkg_off, 16, 255, nil, nil, nil, "pkg_off")
    local frame = W.stroke(parent, 13, y, IN_L, 100, 16, G.hair_color, G.hair2_opa, "hair2_opa")
    thumb(box, 9, 10, 90, 78, pkg_image(p))
    W.text(box, { text = p.name, x = 111, y = 5, w = 120, h = 26, size = T.f.body,
        color = C.text, weight = 700 })
    -- 推荐徽标（HTML .rec：主色底 + on-accent 字）
    if p.rec then
        local rec = W.box(box, 187, 7, 48, 22, C.pri, 6, 255)
        W.text_mid(rec, { text = p.rec, x = 0, y = 0, w = 48, h = 22, size = T.f.sub,
            color = C.on_pri, weight = 600, align = airui.TEXT_ALIGN_CENTER })
    end
    W.text(box, { text = p.desc, x = 112, y = 32, w = 186, h = 22, size = T.f.sub, color = C.text_sub })
    W.text(box, { text = S.fmt_dur(p.dur) .. " · " .. #p.steps .. " 道", x = 112, y = 56, w = 186, h = 22,
        size = T.f.sub, color = C.text_dim })
    local price = W.text(box, { text = money(p.price), x = 296, y = 6, w = 96, h = 34,
        size = T.f.price, color = C.text, weight = 700, align = airui.TEXT_ALIGN_RIGHT })
    W.text(box, { text = money(p.list), x = 296, y = 44, w = 96, h = 20,
        size = T.f.sub, color = C.text_dim, align = airui.TEXT_ALIGN_RIGHT })
    -- 划线价：label 不支持 text-decoration，用 1px 细线压在文字中间
    W.box(box, 344, 53, 44, 1, C.text_dim, 0, 210)
    -- 选中态：底色提亮 + 通栏竖条 + 缩略图角标（描边不吃透明度，所以不用动态边框）
    local bar = W.box(box, 0, 20, 4, 60, C.pri, 2, 0)
    -- 角标底边 74+22=96 ≤ 98（卡片内高），避免贴边被裁
    local badge = W.box(box, 88, 74, 22, 22, C.pri, 11, 0)
    local chk = W.icon(badge, { symbol = "", x = 2, y = 1, size = 16, w = 18, h = 20, color = C.on_pri })
    local h = { box = box, frame = frame, bar = bar, badge = badge, chk = chk, price = price, id = i }
    function h.render(on)
        if frame then frame.set(on and C.pri or G.hair_color, on and 255 or G.hair2_opa) end
        W.glass(box, on and C.pkg_on or C.pkg_off, 255)
        W.glass(bar, C.pri, on and 255 or 0)
        W.glass(badge, C.pri, on and 255 or 0)
        pcall(function() chk:set_text(on and airui.SYMBOL_OK or "") end)
        pcall(function() price:set_color(on and C.pri or C.text) end)
    end
    W.press_layer(box, { x = 0, y = 0, w = IN_L, h = 100, radius = 16,
        on_click = function()
            if S.cur == i then return end
            S.cur = i
            for _, c in ipairs(pkg_cards) do c.render(c.id == i) end
            render_steps()
            refresh_select()
        end })
    h.render(S.cur == i)
    return h
end

-- 附加服务：HTML .addon（44 高 / 圆角 12 / 1px hair2 描边 / 名称 sub + 价格 dim 两段色）
local function build_addon_chip(parent, i, x)
    local a = S.addons[i]
    local CW = 128
    local box = W.box(parent, x, 418, CW, 44, G.chip_bg or 0xFFFFFF, 12, 255,
        nil, nil, nil, "chip_bg")
    local frame = W.stroke(parent, x, 418, CW, 44, 12, G.chip_edge or G.hair_color,
        G.chip_edge_opa or G.hair3_opa, "chip_edge_opa")
    -- 名称与价格按字符数估算宽度，整体居中（HTML 是 inline 居中）
    local nl = (utf8 and utf8.len and utf8.len(a.name)) or #a.name
    local price = " +" .. a.price
    local est = nl * 16 + 6 + #tostring(a.price) * 9 + 8
    local sx = x + math.floor((CW - est) / 2)
    local nlbl = W.text_mid(parent, { text = a.name, x = sx, y = 419, w = nl * 16 + 4, h = 42,
        size = T.f.sub, color = C.text_sub })
    local plbl = W.text_mid(parent, { text = price, x = sx + nl * 16 + 2, y = 419, w = 48, h = 42,
        size = T.f.sub, color = C.text_dim })
    -- 选中时的 ✓（HTML .addon.on::before）
    local chk = W.icon(parent, { symbol = "", x = sx - 17, y = 430, size = 16, w = 16, h = 20,
        color = C.on_pri })

    local h = { box = box, lbl = nlbl }
    function h.set_active(on)
        if frame then
            frame.set(on and C.pri or (G.chip_edge or G.hair_color),
                on and 255 or (G.chip_edge_opa or G.hair3_opa))
        end
        W.glass(box, on and C.pri or (G.chip_bg or 0xFFFFFF), 255)
        pcall(function()
            nlbl:set_color(on and C.on_pri or C.text_sub)
            plbl:set_color(on and C.on_pri or C.text_dim)
            chk:set_text(on and airui.SYMBOL_OK or "")
        end)
    end
    W.press_layer(parent, { x = x, y = 418, w = CW, h = 44, radius = 12,
        on_click = function()
            S.toggle_addon(a.id)
            h.set_active(S.addon_on(a.id))
            refresh_select()
        end })
    h.set_active(S.addon_on(a.id))
    return h
end

local function build_left_select()
    local g = W.glass_card({ parent = PANELS, x = COL.L.x, y = MAIN_Y, w = COL.L.w, h = MAIN_H })
    local p = g.card
    W.text(p, { text = "01 洗车方案", x = 13, y = 12, w = 200, h = 22, size = T.f.sub,
        color = C.text_sub, weight = 600 })
    W.text(p, { text = "共 3 种", x = 300, y = 12, w = 115, h = 22, size = T.f.sub,
        color = C.text_dim, align = airui.TEXT_ALIGN_RIGHT })
    pkg_cards = {}
    for i = 1, #S.pkgs do
        pkg_cards[i] = build_pkg_card(p, i, 44 + (i - 1) * 110)
    end
    W.box(p, 13, 375, IN_L, 1, C.divider, 0, 90)
    W.text(p, { text = "02 附加服务", x = 13, y = 386, w = 200, h = 22, size = T.f.sub,
        color = C.text_sub, weight = 600 })
    W.text(p, { text = "可多选", x = 300, y = 386, w = 115, h = 22, size = T.f.sub,
        color = C.text_dim, align = airui.TEXT_ALIGN_RIGHT })
    addon_chips = {}
    for i = 1, #S.addons do
        addon_chips[i] = build_addon_chip(p, i, 13 + (i - 1) * 137)
    end
end

-- ==================== 中栏：实时画面 + 工序预览 ====================
render_steps = function()
    local parent = PANELS_SELECT or PANELS
    if not parent then return end
    local p = S.pkg()
    -- 工序内容没变就不重建（切换套餐时 4/6/7 道会变，只在这种情况下重建，省 24 个控件的增删）
    local sig = #p.steps
    for _, st in ipairs(p.steps) do sig = sig .. "|" .. st.n .. st.t end
    if steps_box and steps_sig == sig then return end
    steps_sig = sig
    if steps_box then
        pcall(function() steps_box:destroy() end)
        steps_box = nil
        W.reg_kill(steps_idx)                    -- 只作废工序行自己的登记项（不能截断）
    end
    steps_mark = W.reg_mark()
    steps_box = W.box(parent, COL.M.x + 14, MAIN_Y + 314, IN_M, 142, 0x000000, 0, 0)
    local n = #p.steps
    local rowh = math.floor(142 / n)
    for i, st in ipairs(p.steps) do
        local y = (i - 1) * rowh
        W.text_mid(steps_box, { text = string.format("%02d", i), x = 0, y = y, w = 24, h = rowh,
            size = T.f.sub, color = C.text_dim })
        W.box(steps_box, 26, y + math.floor(rowh / 2) - 3, 6, 6, C.edge, 3, 190)
        W.text_mid(steps_box, { text = st.n, x = 38, y = y, w = 130, h = rowh,
            size = T.f.sub, color = C.text })
        W.text_mid(steps_box, { text = S.fmt_dur(st.t), x = 168, y = y, w = 124, h = rowh,
            size = T.f.sub, color = C.text_dim, align = airui.TEXT_ALIGN_RIGHT })
    end
    if lbl_step_cnt then pcall(function() lbl_step_cnt:set_text(n .. " 道") end) end
    steps_idx = W.reg_group(steps_mark)          -- 记下这批工序行的登记索引
end

local function build_mid_select()
    local g = W.glass_card({ parent = PANELS, x = COL.M.x, y = MAIN_Y, w = COL.M.w, h = MAIN_H })
    local p = g.card
    W.text(p, { text = "洗车房 A 实时", x = 14, y = 12, w = 170, h = 22, size = T.f.sub,
        color = C.text_sub, weight = 600 })
    -- .live i：6px 圆点，与 16 号文字垂直居中（对齐后中心 y≈112）
    W.box(p, 238, 16, 6, 6, C.danger, 3, 255)
    W.text(p, { text = "LIVE", x = 250, y = 12, w = 44, h = 22, size = T.f.sub, color = C.danger })
    W.box(p, 14, 42, IN_M, 138, C.deep, T.r.panel, 255)
    local cam_src = img_base()
    if not W.photo(p, { x = 14, y = 42, w = IN_M, h = 138,
        src = cam_src and (cam_src .. "pkg-foam.jpg") or nil, fit = "cover" }) then
        W.icon(p, { symbol = airui.SYMBOL_VIDEO, x = 146, y = 100, size = 26, w = 28, h = 28, color = C.text_dim })
    end
    -- 画面底部压暗 + 左下两枚小标签（HTML .camtint / .camtag）
    W.box(p, 14, 130, IN_M, 50, 0x000000, 0, 62)
    local t1 = W.box(p, 24, 148, 64, 24, 0x0A0F0F, 7, 170)
    W.text_mid(t1, { text = "1080P", x = 0, y = 0, w = 64, h = 24, size = T.f.sub,
        color = 0xEAF5F2, align = airui.TEXT_ALIGN_CENTER })
    local t2 = W.box(p, 94, 148, 80, 24, 0x0A0F0F, 7, 170)
    lbl_cam_tag = W.text_mid(t2, { text = "待洗车", x = 0, y = 0, w = 80, h = 24, size = T.f.sub,
        color = 0xEAF5F2, align = airui.TEXT_ALIGN_CENTER })
    -- .carplate：bg --surface（白 .065 / .56）+ 1px hair2 描边、圆角 13
    local plate = W.box(p, 14, 192, IN_M, 72, 0xFFFFFF, 13, G.surface_opa,
        nil, nil, "surface_opa", "__white")
    W.stroke(p, 14, 192, IN_M, 72, 13, G.hair_color, G.hair2_opa, "hair2_opa")
    W.text(plate, { text = S.plate, x = 12, y = 10, w = 180, h = 28, size = 20, color = C.text, weight = 700 })
    W.text(plate, { text = S.car, x = 12, y = 40, w = 190, h = 22, size = T.f.sub, color = C.text_dim })
    lbl_pkg_dur = W.text(plate, { text = S.fmt_dur(S.pkg().dur), x = 186, y = 8, w = 94, h = 28,
        size = 20, color = C.pri, weight = 700, align = airui.TEXT_ALIGN_RIGHT })
    W.text(plate, { text = "预计用时", x = 176, y = 40, w = 104, h = 22, size = T.f.sub,
        color = C.text_dim, align = airui.TEXT_ALIGN_RIGHT })
    W.box(p, 14, 276, IN_M, 1, C.divider, 0, 90)
    W.text(p, { text = "03 工序流程", x = 14, y = 286, w = 180, h = 22, size = T.f.sub,
        color = C.text_sub, weight = 600 })
    lbl_step_cnt = W.text(p, { text = "", x = 200, y = 286, w = 106, h = 22, size = T.f.sub,
        color = C.text_dim, align = airui.TEXT_ALIGN_RIGHT })
    render_steps()
end

-- ==================== 右栏：会员 / 结算 ====================
local function build_right_select()
    local g = W.glass_card({ parent = PANELS, x = COL.R.x, y = MAIN_Y, w = COL.R.w, h = MAIN_H })
    local p = g.card
    -- 会员卡：HTML 有 a22 描边 + 渐隐底，这里用「外框 + 内填」两层
    W.box(p, 13, 13, IN_R, 110, C.pri, T.r.panel, 72)
    local vip = W.box(p, 14, 14, IN_R - 2, 108, C.vip_bg, T.r.panel - 1, 255)
    W.text(vip, { text = "会员余额", x = 14, y = 10, w = 100, h = 22, size = T.f.sub, color = C.text_sub })
    -- .lvl：padding 1px 8px，靠 vip 内容右边界（内容宽 154，右边界 168）
    local lvl = W.box(vip, 120, 10, 48, 22, C.pri, 6, 255)
    W.text_mid(lvl, { text = "黑金", x = 0, y = 0, w = 48, h = 22, size = T.f.sub,
        color = C.on_pri, align = airui.TEXT_ALIGN_CENTER })
    W.text(vip, { text = "￥126.00", x = 14, y = 34, w = 160, h = 38, size = 30,
        color = C.text, weight = 700 })
    W.text(vip, { text = "积分 2,480", x = 14, y = 78, w = 160, h = 22, size = T.f.sub, color = C.text_sub })
    -- 优惠券：HTML 是虚线边框 + surface3 底（用「外框 + 内填」近似细边）
    coupon_box = W.box(p, 13, 133, IN_R, 42, C.edge, T.r.chip, 110)
    coupon_in = W.box(p, 14, 134, IN_R - 2, 40, C.coupon_bg, T.r.chip - 1, 255)
    W.text_mid(coupon_in, { text = "满 50 减 8", x = 12, y = 0, w = 110, h = 40, size = T.f.sub, color = C.text_sub })
    lbl_coupon_state = W.text_mid(coupon_in, { text = "", x = 96, y = 0, w = 74, h = 40,
        size = T.f.sub, color = C.text_dim, align = airui.TEXT_ALIGN_RIGHT })
    W.box(p, 13, 187, IN_R, 1, C.divider, 0, 90)
    local names = { "套餐", "附加", "优惠券" }
    bill_vals = {}
    for i = 1, 3 do
        local y = 198 + (i - 1) * 30
        W.text_mid(p, { text = names[i], x = 13, y = y, w = 90, h = 22, size = T.f.sub, color = C.text_dim })
        bill_vals[i] = W.text_mid(p, { text = "", x = 100, y = y, w = 87, h = 22, size = T.f.sub,
            color = C.text_sub, align = airui.TEXT_ALIGN_RIGHT })
    end
    W.text_mid(p, { text = "合计", x = 13, y = 300, w = 60, h = 24, size = T.f.sub, color = C.text_dim })
    lbl_total = W.text(p, { text = "", x = 68, y = 292, w = 119, h = 42, size = T.f.display,
        color = C.text, weight = 700, align = airui.TEXT_ALIGN_RIGHT })
    local btn = pill(p, { x = 13, y = 348, w = IN_R, h = 54, text = "确认支付", size = T.f.body,
        weight = 600, on_click = function() open_pay() end })
    lbl_pay = btn.lbl
    W.text(p, { text = "微信 / 支付宝 / 余额", x = 13, y = 414, w = IN_R, h = 22,
        size = T.f.sub, color = C.text_dim, align = airui.TEXT_ALIGN_CENTER })
end

-- ==================== 选中态刷新 ====================
refresh_select = function()
    local c = S.calc()
    -- 结果没变就整段跳过：避免无谓的 set_text / set_color 触发局部重绘（真机上每次都要重画）
    local sig = table.concat({ S.cur, tostring(c.base), tostring(c.add), tostring(c.disc),
        tostring(c.total) }, "|")
    if refresh_sig == sig and bill_vals then return end
    refresh_sig = sig
    if bill_vals then
        pcall(function()
            bill_vals[1]:set_text(money(c.base))
            -- HTML 空值用破折号；hzfont 没有 U+2014，用半角减号代替（不会出现方块）
            bill_vals[2]:set_text(c.add > 0 and ("+" .. money(c.add)) or "-")
            bill_vals[3]:set_text(c.disc > 0 and ("-" .. money(c.disc)) or "-")
            bill_vals[3]:set_color(c.disc > 0 and C.pri or C.text_sub)
        end)
    end
    if lbl_total then pcall(function() lbl_total:set_text(money(c.total)) end) end
    if lbl_pay then pcall(function() lbl_pay:set_text("确认支付 " .. money(c.total)) end) end
    if lbl_coupon_state then
        pcall(function() lbl_coupon_state:set_text(c.disc > 0 and "已抵扣" or "不可用") end)
        pcall(function() lbl_coupon_state:set_color(c.disc > 0 and C.pri or C.text_dim) end)
        -- 优惠券：可用时描边与文字转主色，底略微上色
        if coupon_box then
            W.glass(coupon_box, c.disc > 0 and C.pri or C.edge, 255)
        end
        if coupon_in then
            W.glass(coupon_in, c.disc > 0 and C.vip_bg or C.coupon_bg, 255)
        end
    end
    if lbl_pkg_dur then pcall(function() lbl_pkg_dur:set_text(S.fmt_dur(S.pkg().dur)) end) end
    for i, a in ipairs(S.addons) do
        if addon_chips and addon_chips[i] then addon_chips[i].set_active(S.addon_on(a.id)) end
    end
end

-- ==================== 洗车中 ====================
local function build_left_wash()
    local g = W.glass_card({ parent = PANELS, x = COL.L.x, y = MAIN_Y, w = COL.L.w, h = MAIN_H })
    local p = g.card
    W.text(p, { text = "洗车进度", x = 13, y = 12, w = 200, h = 22, size = T.f.sub,
        color = C.text_sub, weight = 600 })
    W.text(p, { text = "全程 " .. S.fmt_dur(S.pkg().dur), x = 300, y = 12, w = 115, h = 22,
        size = T.f.sub, color = C.text_dim, align = airui.TEXT_ALIGN_RIGHT })
    local steps = S.pkg().steps
    local n = #steps
    local area = 396
    local bh = math.min(56, math.floor((area - (n - 1) * 8) / n))
    wash_ui.rows = {}
    for i, st in ipairs(steps) do
        local y = 44 + (i - 1) * (bh + 8)
        local box = W.box(p, 13, y, IN_L, bh, C.card, T.r.panel, G.tile_opa,
            nil, nil, "tile_opa", "card")
        W.stroke(p, 13, y, IN_L, bh, T.r.panel, G.hair_color, G.hair2_opa or 27, "hair2_opa")
        local idx = W.text_mid(box, { text = string.format("%02d", i), x = 10, y = 6, w = 22, h = 22,
            size = T.f.sub, color = C.text_dim })
        local nm = W.text_mid(box, { text = st.n, x = 36, y = 6, w = 240, h = 22,
            size = T.f.sub, color = C.text_sub })
        local du = W.text_mid(box, { text = S.fmt_dur(st.t), x = 286, y = 6, w = 104, h = 22,
            size = T.f.sub, color = C.text_dim, align = airui.TEXT_ALIGN_RIGHT })
        local bar = W.bar(box, { x = 10, y = bh - 15, w = IN_L - 20, h = 5, value = 0,
            bg_color = C.edge })
        wash_ui.rows[i] = { box = box, idx = idx, nm = nm, du = du, bar = bar }
    end
    -- 底部提示（HTML #washNote）
    W.text(p, { text = "正在洗车，请在休息区等候", x = 13, y = 446, w = IN_L, h = 20,
        size = T.f.sub, color = C.text_dim, align = airui.TEXT_ALIGN_CENTER })
end

local function build_mid_wash()
    local g = W.glass_card({ parent = PANELS, x = COL.M.x, y = MAIN_Y, w = COL.M.w, h = MAIN_H })
    local p = g.card
    W.text(p, { text = "进行中", x = 14, y = 12, w = 120, h = 22, size = T.f.sub,
        color = C.text_sub, weight = 600 })
    -- .live i：6px 圆点，与 16 号文字垂直居中（对齐后中心 y≈112）
    W.box(p, 238, 16, 6, 6, C.danger, 3, 255)
    W.text(p, { text = "LIVE", x = 250, y = 12, w = 44, h = 22, size = T.f.sub, color = C.danger })
    -- 圆环：HTML 是 200px / stroke 7 的 SVG 弧，这里用 shape 的 arc（带圆头）
    local ring_w = 2 * 88 + 7 + 6
    local rx = 14 + math.floor((IN_M - ring_w) / 2)
    wash_ui.ring = W.ring(p, { x = rx, y = 26, r = 88, width = 7 })
    wash_ui.lbl_time = W.text_mid(p, { text = S.fmt_mmss(S.pkg().dur), x = 14, y = 98, w = IN_M, h = 44,
        size = 40, color = C.text, weight = 700, align = airui.TEXT_ALIGN_CENTER })
    W.text(p, { text = "剩余时间", x = 14, y = 146, w = IN_M, h = 22, size = T.f.sub,
        color = C.text_dim, align = airui.TEXT_ALIGN_CENTER })
    wash_ui.lbl_step = W.text(p, { text = S.pkg().steps[1].n, x = 14, y = 172, w = IN_M, h = 26,
        size = T.f.body, color = C.pri, align = airui.TEXT_ALIGN_CENTER })
    -- .gauge 三张卡片：surface3 底 + 1px hair2 描边
    local names = { "水压", "水温", "用水" }
    wash_ui.metric = {}
    wash_ui.metric_unit = {}
    for i = 1, 3 do
        local x = 14 + (i - 1) * 96
        local box = W.box(p, x, 246, 90, 86, 0xFFFFFF, 12, G.surface3_opa or 82,
            nil, nil, "surface3_opa", "__white")
        W.stroke(p, x, 246, 90, 86, 12, G.hair_color, G.hair2_opa or 27, "hair2_opa")
        W.text(box, { text = names[i], x = 10, y = 8, w = 70, h = 20, size = T.f.sub, color = C.text_dim })
        wash_ui.metric[i] = W.text(box, { text = "", x = 10, y = 34, w = 52, h = 30,
            size = 22, color = C.text, weight = 700 })
        wash_ui.metric_unit[i] = W.text(box, { text = "", x = 56, y = 42, w = 30, h = 20,
            size = T.f.sub, color = C.text_sub })
    end
    -- .pane 的 justify-content:space-between → 这行固定在面板底部
    W.text_mid(p, { text = "预计完成", x = 14, y = 440, w = 90, h = 24, size = T.f.sub, color = C.text_dim })
    wash_ui.lbl_fin = W.text_mid(p, { text = "", x = 100, y = 440, w = 96, h = 24, size = T.f.sub, color = C.text })
    wash_ui.lbl_pct = W.text_mid(p, { text = "0%", x = 196, y = 440, w = 110, h = 24, size = T.f.sub,
        color = C.pri, align = airui.TEXT_ALIGN_RIGHT })
end

local function build_right_wash()
    local g = W.glass_card({ parent = PANELS, x = COL.R.x, y = MAIN_Y, w = COL.R.w, h = MAIN_H })
    local p = g.card
    W.text(p, { text = "实时参数", x = 13, y = 12, w = 120, h = 22, size = T.f.sub,
        color = C.text_sub, weight = 600 })
    W.text(p, { text = "房 A", x = 130, y = 12, w = 67, h = 22, size = T.f.sub,
        color = C.text_dim, align = airui.TEXT_ALIGN_RIGHT })
    local names = { "水压", "泡沫", "转速", "用水" }
    wash_ui.param = {}
    for i = 1, 4 do
        local y = 48 + (i - 1) * 56
        W.text(p, { text = names[i], x = 13, y = y, w = 90, h = 22, size = T.f.sub, color = C.text_sub })
        local v = W.text(p, { text = "", x = 96, y = y, w = 101, h = 22, size = T.f.sub,
            color = C.text, align = airui.TEXT_ALIGN_RIGHT })
        local bar = W.bar(p, { x = 13, y = y + 30, w = IN_R, h = 5, value = 0 })
        wash_ui.param[i] = { lbl = v, bar = bar }
    end
    -- HTML .note：surface3 底 + 1px hair2 描边 + 圆角 11
    local note = W.box(p, 13, 300, IN_R, 92, 0xFFFFFF, 11,
        G.surface3_opa or 82, nil, nil, "surface3_opa", "__white")
    W.stroke(p, 13, 300, IN_R, 92, 11, G.hair_color, G.hair2_opa, "hair2_opa")
    W.text(note, { text = "运行中，请勿靠近喷头与毛刷。异常可按下方按钮中止。",
        x = 12, y = 10, w = IN_R - 24, h = 72, size = T.f.sub, color = C.text_dim })
    -- .stop：1px danger 描边 + d08 底（不是实心块），同样贴面板底部
    W.box(p, 13, 428, IN_R, 46, C.danger, 12, 20)
    W.stroke(p, 13, 428, IN_R, 46, 12, C.danger, 90)
    W.text_mid(p, { text = "紧急停止", x = 13, y = 428, w = IN_R, h = 46, size = T.f.sub,
        color = C.danger, align = airui.TEXT_ALIGN_CENTER })
    W.press_layer(p, { x = 13, y = 428, w = IN_R, h = 46, radius = 12,
        on_click = function() stop_wash() end })
    wash_ui.stop = true
end

-- ==================== 完成 ====================
refresh_stars = function()
    if not done_ui or not done_ui.stars then return end
    for i, s in ipairs(done_ui.stars) do
        local on = i <= S.rating
        pcall(function() s.lbl:set_color(on and C.star_on or C.star_off) end)
    end
end

local function build_left_done()
    local g = W.glass_card({ parent = PANELS, x = COL.L.x, y = MAIN_Y, w = COL.L.w, h = MAIN_H })
    local p = g.card
    W.text(p, { text = "洗车评价", x = 13, y = 12, w = 200, h = 22, size = T.f.sub,
        color = C.text_sub, weight = 600 })
    W.text(p, { text = "+20 积分", x = 300, y = 12, w = 115, h = 22, size = T.f.sub,
        color = C.text_dim, align = airui.TEXT_ALIGN_RIGHT })
    W.text(p, { text = "这次洗得怎么样？", x = 14, y = 102, w = IN_L, h = 30, size = 20,
        color = C.text, weight = 600 })
    -- 1-5 分：★ 字形（hzfont 已覆盖），选中 star-on 色
    done_ui.stars = {}
    for i = 1, 5 do
        local x = 14 + (i - 1) * 48
        local txt = W.text(p, { text = "★", x = x, y = 178, w = 38, h = 40, size = 32,
            color = C.text_dim, align = airui.TEXT_ALIGN_CENTER })
        done_ui.stars[i] = { lbl = txt }
        W.press_layer(p, { x = x, y = 178, w = 38, h = 40, radius = 8, on_click = function()
            S.rating = i
            refresh_stars()
        end })
    end
    done_ui.tags = {}
    -- .tag：自适应宽度胶囊（16 号字 ≈ 16px/字 + 左右 padding 12），间隔 8
    local tx = 14
    for i, t in ipairs(S.rating_tags) do
        -- 中文必须按字符数算（#t 是字节数，会放大 3 倍）
        local nch = (utf8 and utf8.len and utf8.len(t)) or (math.floor(#t / 3))
        local tw = nch * 16 + 26
        local box = W.box(p, tx, 264, tw, 32, 0xFFFFFF, 16, G.surface3_opa or 82,
            nil, nil, "surface3_opa", "__white")
        local st = W.stroke(p, tx, 264, tw, 32, 16, G.hair_color, G.hair2_opa or 27, "hair2_opa")
        local lbl = W.text_mid(box, { text = t, x = 0, y = 0, w = tw, h = 32, size = T.f.sub,
            color = C.text_sub, align = airui.TEXT_ALIGN_CENTER })
        local hh = { box = box, lbl = lbl }
        function hh.render(on)
            W.glass(box, on and C.pri or 0xFFFFFF, on and 40 or (G.surface3_opa or 82))
            if st then st.set(on and C.pri or G.hair_color, on and 120 or (G.hair2_opa or 27)) end
            pcall(function() lbl:set_color(on and C.pri or C.text_sub) end)
        end
        done_ui.tags[i] = hh
        W.press_layer(p, { x = tx, y = 264, w = tw, h = 32, radius = 16, on_click = function()
            S.tags[t] = (not S.tags[t]) or nil
            hh.render(S.tags[t])
        end })
        hh.render(S.tags[t])
        tx = tx + tw + 8
    end
    -- 提交评价：描边按钮，高 40（HTML .btnline）
    ghost_btn(p, { x = 14, y = 359, w = IN_L, h = 40, text = "提交评价", size = T.f.sub,
        tcolor = C.text, radius = 12,
        on_click = function()
            local list = {}
            for _, t in ipairs(S.rating_tags) do
                if S.tags[t] then list[#list + 1] = t end
            end
            local extra = (#list > 0) and (" · " .. table.concat(list, "、")) or ""
            toast("感谢评价 " .. S.rating .. " 星" .. extra .. "，20 积分已到账")
        end })
    W.text(p, { text = "评价仅需 3 秒，帮助我们做得更好", x = 14, y = 465, w = IN_L, h = 22,
        size = T.f.sub, color = C.text_dim, align = airui.TEXT_ALIGN_CENTER })
end

local function build_mid_done()
    local g = W.glass_card({ parent = PANELS, x = COL.M.x, y = MAIN_Y, w = COL.M.w, h = MAIN_H })
    local p = g.card
    -- 完成图标：主色 13% 圆 + 自绘对勾（symbol 字号放大不生效，改 shape 线）
    local cx = math.floor((IN_M - 104) / 2)
    W.box(p, cx, 48, 104, 104, C.pri, 52, 33)
    W.shape(p, { x = cx, y = 48, w = 104, h = 104, items = {
        { type = "line", x1 = 36, y1 = 52, x2 = 47, y2 = 64, color = C.pri, width = 6, round_end = true },
        { type = "line", x1 = 47, y1 = 64, x2 = 70, y2 = 38, color = C.pri, width = 6, round_end = true },
    } })
    W.text(p, { text = "洗车完成", x = 14, y = 156, w = IN_M, h = 34, size = 26,
        color = C.text, weight = 700, align = airui.TEXT_ALIGN_CENTER })
    W.text(p, { text = S.plate .. " · " .. S.pkg().name, x = 14, y = 194, w = IN_M, h = 22,
        size = T.f.sub, color = C.text_dim, align = airui.TEXT_ALIGN_CENTER })
    local names = { "用时", "用水", "耗电" }
    done_ui.stat = {}
    for i = 1, 3 do
        -- .stat：surface3 底 + 1px hair2 描边，高 65
        local x = 14 + (i - 1) * 92
        local box = W.box(p, x, 292, 86, 65, 0xFFFFFF, 12, G.surface3_opa or 82,
            nil, nil, "surface3_opa", "__white")
        W.stroke(p, x, 292, 86, 65, 12, G.hair_color, G.hair2_opa or 27, "hair2_opa")
        done_ui.stat[i] = W.text(box, { text = "", x = 0, y = 12, w = 86, h = 26,
            size = 22, color = C.text, weight = 700, align = airui.TEXT_ALIGN_CENTER })
        W.text(box, { text = names[i], x = 0, y = 40, w = 86, h = 20,
            size = T.f.sub, color = C.text_dim, align = airui.TEXT_ALIGN_CENTER })
    end
    W.text(p, { text = "车辆可驶离 · 闸机已抬起", x = 14, y = 465, w = IN_M, h = 22,
        size = T.f.sub, color = C.text_dim, align = airui.TEXT_ALIGN_CENTER })
end

local function build_right_done()
    local g = W.glass_card({ parent = PANELS, x = COL.R.x, y = MAIN_Y, w = COL.R.w, h = MAIN_H })
    local p = g.card
    W.text(p, { text = "本次小票", x = 13, y = 12, w = 100, h = 22, size = T.f.sub,
        color = C.text_sub, weight = 600 })
    W.text(p, { text = "电子发票", x = 110, y = 12, w = 87, h = 22, size = T.f.sub,
        color = C.text_dim, align = airui.TEXT_ALIGN_RIGHT })
    local names = { "订单", "套餐", "附加", "优惠", "支付", "时间" }
    done_ui.rc = {}
    -- 小票 6 行：行距 28，分隔线在 218（HTML 基准：divider≈310 绝对 / 面板顶 92）
    for i = 1, 6 do
        local y = 44 + (i - 1) * 28
        W.text_mid(p, { text = names[i], x = 13, y = y, w = 60, h = 26, size = T.f.sub, color = C.text_dim })
        done_ui.rc[i] = W.text_mid(p, { text = "", x = 64, y = y, w = 133, h = 26, size = T.f.sub,
            color = C.text_sub, align = airui.TEXT_ALIGN_RIGHT })
    end
    W.box(p, 13, 218, IN_R, 1, C.divider, 0, 90)
    W.text_mid(p, { text = "实付", x = 13, y = 260, w = 60, h = 28, size = T.f.sub, color = C.text_dim })
    done_ui.pay = W.text(p, { text = "", x = 58, y = 252, w = 139, h = 40, size = 30,
        color = C.text, weight = 700, align = airui.TEXT_ALIGN_RIGHT })
    pill(p, { x = 13, y = 376, w = IN_R, h = 38, text = "再来一次", size = T.f.sub, weight = 600,
        on_click = function()
            sys.timerStart(function() reset_to_select(); toast("已返回方案选择") end, 40)
        end })
    ghost_btn(p, { x = 13, y = 430, w = IN_R, h = 36, text = "返回首页", size = T.f.sub,
        tcolor = C.text_sub, radius = 12,
        on_click = function()
            sys.timerStart(function() reset_to_select(); toast("欢迎再次使用净界洗车") end, 40)
        end })
end

-- ==================== 面板总装（三个阶段常驻，切换只挪位置） ====================
local STAGE = {}                                 -- [阶段] = 该阶段的容器
local HANDLES = {}                               -- [阶段] = 该阶段的控件句柄

local function capture(st)
    -- 注意：steps_box 不进 HANDLES。它在 render_steps 里会被销毁重建，
    -- 若存进 HANDLES，切回选方案页时 restore 会把「已销毁的旧句柄」写回全局变量，
    -- 下一次重建就删不掉真正在用的那个，导致工序列表重复叠加。
    HANDLES[st] = {
        pkg_cards = pkg_cards, addon_chips = addon_chips,
        lbl_pkg_dur = lbl_pkg_dur, lbl_step_cnt = lbl_step_cnt,
        bill_vals = bill_vals, lbl_total = lbl_total,
        lbl_coupon_state = lbl_coupon_state, coupon_box = coupon_box,
        coupon_in = coupon_in, lbl_pay = lbl_pay,
        wash_ui = wash_ui, done_ui = done_ui,
    }
end

local function restore(st)
    local h = HANDLES[st]
    if not h then
        pkg_cards, addon_chips = nil, nil
        lbl_pkg_dur, lbl_step_cnt, bill_vals, lbl_total = nil, nil, nil, nil
        lbl_coupon_state, coupon_box, coupon_in, lbl_pay = nil, nil, nil, nil
        wash_ui, done_ui = nil, nil
        return
    end
    pkg_cards, addon_chips = h.pkg_cards, h.addon_chips
    lbl_pkg_dur, lbl_step_cnt = h.lbl_pkg_dur, h.lbl_step_cnt
    bill_vals, lbl_total = h.bill_vals, h.lbl_total
    lbl_coupon_state, coupon_box, coupon_in, lbl_pay =
        h.lbl_coupon_state, h.coupon_box, h.coupon_in, h.lbl_pay
    wash_ui, done_ui = h.wash_ui, h.done_ui
end

local function build_one(st)
    -- 非当前阶段先放到屏幕外（set_pos 挪走，不用 hide：真机上 hide/open 不可靠）
    local x = (st == S.stage) and 0 or -SW
    local c = W.box(ROOT, x, PANEL_Y, SW, SH - PANEL_Y, 0x000000, 0, 0)
    PANELS = c
    -- 只重置签名，不动 steps_box：它是选方案页的句柄，
    -- 在建 wash/done 时清掉会导致选方案页里那棵树“失联”，再次重建时叠出第二份。
    steps_sig, refresh_sig = nil, nil
    if st == "wash" then
        wash_ui = {}
        build_left_wash(); build_mid_wash(); build_right_wash()
    elseif st == "done" then
        done_ui = {}
        build_left_done(); build_mid_done(); build_right_done()
        fill_done()
    else
        pkg_cards, addon_chips = {}, {}
        build_left_select(); build_mid_select(); build_right_select()
        refresh_select()
    end
    capture(st)
    STAGE[st] = c
    if st == "select" then PANELS_SELECT = c end
end

build_panels = function()
    for _, c in pairs(STAGE) do pcall(function() c:destroy() end) end
    STAGE, HANDLES = {}, {}
    if PANELS then pcall(function() PANELS:destroy() end); PANELS = nil end
    steps_box, steps_sig = nil, nil              -- 旧工序列表已随容器销毁
    restore("select")                            -- 清空句柄，builder 会重新赋值
    build_one("select"); build_one("wash"); build_one("done")
    restore(S.stage)
end

fill_done = function()
    local p = S.pkg()
    local u = S.usage()
    local c = S.calc()
    local n = 0
    for _, a in ipairs(S.addons) do if S.picked[a.id] then n = n + 1 end end
    local o = S.make_order()
    pcall(function()
        -- HTML 的 fmt() 不带前导零：8:30 而不是 08:30
        done_ui.stat[1]:set_text((S.fmt_mmss(p.dur):gsub("^0", "")))
        done_ui.stat[2]:set_text(u.water .. "L")
        done_ui.stat[3]:set_text(u.kwh)
        done_ui.rc[1]:set_text(o.no)
        done_ui.rc[2]:set_text(p.name)
        done_ui.rc[3]:set_text(n > 0 and (n .. " 项 " .. money(c.add)) or "无")
        done_ui.rc[4]:set_text(c.disc > 0 and ("-" .. money(c.disc)) or "无")
        done_ui.rc[5]:set_text("微信支付")
        done_ui.rc[6]:set_text(os.date("%m-%d %H:%M", os.time()))
        done_ui.pay:set_text(money(c.total))
    end)
    refresh_stars()
    if lbl_dev then lbl_dev.set("设备就绪") end
    if lbl_bay then lbl_bay.set("洗车房 A · 空闲") end
end

-- ==================== 阶段切换 ====================
set_stage = function(st)
    S.stage = st
    gen = gen + 1
    -- 三个阶段都已常驻：这里只做「挪位置 + 绑定句柄」，没有任何控件重建
    for name, c in pairs(STAGE) do
        pcall(function() c:set_pos((name == st) and 0 or -SW, PANEL_Y) end)
    end
    restore(st)
    if st == "done" then fill_done() end
    draw_toast()
end

reset_to_select = function()
    if t_wash then pcall(function() sys.timerStop(t_wash) end); t_wash = nil end
    S.elapsed = 0
    S.rating = 5
    S.tags = {}
    set_stage("select")
    if lbl_dev then lbl_dev.set("设备就绪") end
    if lbl_bay then lbl_bay.set("洗车房 A · 空闲") end
end

-- ==================== 洗车推进 ====================
start_ticker = function()
    local my = gen
    if t_wash then pcall(function() sys.timerStop(t_wash) end) end
    t_wash = sys.timerLoopStart(function()
        if my ~= gen or S.stage ~= "wash" then return end
        S.elapsed = S.elapsed + S.SPEED
        local ok, err = pcall(paint_wash)
        if not ok then log.warn("wash", "paint", tostring(err)) end
        if S.elapsed >= S.total then
            S.elapsed = S.total
            if t_wash then pcall(function() sys.timerStop(t_wash) end); t_wash = nil end
            -- 不能在定时器回调里直接销毁/重建三栏，延后一帧执行
            sys.timerStart(function()
                if my ~= gen then return end
                set_stage("done")
                toast("洗车完成，欢迎再次光临")
            end, 40)
        end
    end, 1000)
end

start_wash = function()
    S.elapsed = 0
    S.total = S.pkg().dur
    set_stage("wash")
    if lbl_dev then lbl_dev.set("运行中", "busy") end
    if lbl_bay then lbl_bay.set("洗车房 A · 洗车中") end
    start_ticker()
    local ok, err = pcall(paint_wash)
    if not ok then log.warn("wash", "paint", tostring(err)) end
end

paint_wash = function()
    if not wash_ui then return end
    local p = S.pkg()
    local total = (S.total > 0) and S.total or 1
    local frac = S.elapsed / total
    local acc, cur, prog = 0, #p.steps, 0
    for i, st in ipairs(p.steps) do
        if S.elapsed < acc + st.t then
            cur = i
            prog = (S.elapsed - acc) / st.t
            break
        end
        acc = acc + st.t
    end
    if wash_ui.ring then wash_ui.ring.set(frac) end
    pcall(function()
        wash_ui.lbl_time:set_text(S.fmt_mmss(total - S.elapsed))
        wash_ui.lbl_step:set_text(p.steps[cur] and p.steps[cur].n or "收尾检查")
        wash_ui.lbl_pct:set_text(math.floor(frac * 100 + 0.5) .. "%")
        wash_ui.lbl_fin:set_text(os.date("%H:%M", os.time() + math.max(0, total - S.elapsed)))
    end)
    for i, row in ipairs(wash_ui.rows or {}) do
        local w = 0
        if i < cur then w = 100 elseif i == cur then w = prog * 100 end
        row.bar.set(w)                       -- 内部已做「值没变就不重绘」
        local now = (i == cur)
        if row.on ~= now then                -- 只有高亮态变化时才重设底/字色（每次都是一整行重绘）
            row.on = now
            row.bar.color(now and C.pri or (i < cur and W.mix(C.pri, C.card, 0.55) or C.pri))
            W.glass(row.box, now and C.pri or C.card, now and (G.a06_opa or 15) or G.tile_opa)
            pcall(function()
                row.nm:set_color(now and C.text or C.text_sub)
                row.du:set_color(now and C.pri or C.text_dim)
                row.idx:set_color(now and C.pri or C.text_dim)
            end)
        end
    end
    -- 指标：与 HTML 的 METRIC 表同源
    local METRIC = {
        { p = 4.6, f = 1.4, r = 2750 }, { p = 4.2, f = 3.2, r = 2400 },
        { p = 3.4, f = 3.0, r = 1800 }, { p = 4.4, f = 0.6, r = 2900 },
        { p = 3.0, f = 1.2, r = 1600 }, { p = 2.2, f = 0.0, r = 3200 },
    }
    -- 水压/泡沫/转速 只随“当前工序”变化：工序没换就不重设（省 3 label + 3 条），
    -- 用水是累计值，每秒都要更新。
    local water = frac * 42.6
    local changed = (wash_ui.last_cur ~= cur)
    wash_ui.last_cur = cur
    local m = METRIC[math.min(cur, #METRIC)]
    if changed then
        pcall(function()
            wash_ui.metric[1]:set_text(string.format("%.1f", m.p))
            wash_ui.metric_unit[1]:set_text("bar")
            wash_ui.metric[2]:set_text("32")
            wash_ui.metric_unit[2]:set_text("℃")
            wash_ui.param[1].lbl:set_text(string.format("%.1f bar", m.p))
            wash_ui.param[2].lbl:set_text(string.format("%.1f %%", m.f))
            wash_ui.param[3].lbl:set_text(tostring(m.r))
        end)
        wash_ui.param[1].bar.set(m.p / 6 * 100)
        wash_ui.param[2].bar.set(m.f / 5 * 100)
        wash_ui.param[3].bar.set(m.r / 3500 * 100)
    end
    pcall(function()
        wash_ui.metric[3]:set_text(string.format("%.1f", water))
        wash_ui.metric_unit[3]:set_text("L")
        wash_ui.param[4].lbl:set_text(string.format("%.1f L", water))
    end)
    wash_ui.param[4].bar.set(water / 50 * 100)
end

stop_wash = function()
    if S.stage ~= "wash" then return end
    local c = S.calc()
    local back = c.total * (1 - S.elapsed / ((S.total > 0) and S.total or 1))
    if t_wash then pcall(function() sys.timerStop(t_wash) end); t_wash = nil end
    sys.timerStart(function()
        reset_to_select()
        toast(string.format("洗车已中止，未完成部分 ￥%.2f 已退回", back))
    end, 40)
end

-- ==================== 支付弹层 ====================
open_pay = function()
    if pay_ui or S.stage ~= "select" then return end
    pay_mark = W.reg_mark()
    local c = S.calc()
    -- 蒙版：HTML 是 backdrop-filter:blur(18px) + rgba(4,8,11,.55)。
    -- LVGL 无模糊能力，这里用压暗蒙层（0x04080B @140 ≈ 55%）。
    local root = airui.container({ parent = ROOT, x = 0, y = 0, w = SW, h = SH,
        color = 0x04080B, color_opacity = 140, border_width = 0, scrollable = false })
    -- 透明点击层（不用 press_layer，避免整屏白闪）
    airui.container({ parent = root, x = 0, y = 0, w = SW, h = SH,
        color = -1, border_width = 0, scrollable = false,
        on_click = function()
            sys.timerStart(function() close_pay(); toast("已取消支付") end, 40)
        end })
    local card = airui.container({ parent = root, x = 316, y = 68, w = 392, h = 464,
        color = C.card, color_opacity = 244, radius = T.r.card, border_width = 0,
        scrollable = false, on_click = function() end })
    -- HTML .mcard 有 1px --hair 描边；container border 在圆角处会变直角，改用 shape
    W.stroke(root, 316, 68, 392, 464, T.r.card, G.hair_color, G.hair_opa)
    W.text(card, { text = "扫码支付", x = 0, y = 22, w = 392, h = 30, size = 20,
        color = C.text, weight = 700, align = airui.TEXT_ALIGN_CENTER })
    -- HTML .msub 只显示套餐名
    W.text(card, { text = S.pkg().name,
        x = 0, y = 54, w = 392, h = 22, size = T.f.sub, color = C.text_dim,
        align = airui.TEXT_ALIGN_CENTER })
    W.box(card, 101, 82, 190, 190, 0xFFFFFF, 14, 255)
    local ok = pcall(function()
        airui.qrcode({ parent = card, x = 112, y = 96, size = 168,
            data = "https://pay.jingjie.example/cw?amt=" .. c.total .. "&bay=A",
            dark_color = 0x15171A, light_color = 0xFFFFFF, quiet_zone = true })
    end)
    if not ok then
        W.icon(card, { symbol = airui.SYMBOL_IMAGE, x = 186, y = 166, size = 20, w = 20, h = 20,
            color = C.text_dim })
    end
    W.text(card, { text = money(c.total), x = 0, y = 280, w = 392, h = 44, size = 34,
        color = C.text, weight = 700, align = airui.TEXT_ALIGN_CENTER })
    -- 倒计时：数字主色加粗 + 静态说明（对应 HTML 的 .mcd b + 文本）
    local cd_num = W.text(card, { text = "03:00", x = 92, y = 328, w = 48, h = 22,
        size = T.f.sub, color = C.pri, weight = 600, align = airui.TEXT_ALIGN_RIGHT })
    W.text(card, { text = " 内完成支付，超时自动取消", x = 142, y = 328, w = 210, h = 22,
        size = T.f.sub, color = C.text_dim })
    ghost_btn(card, { x = 24, y = 362, w = 167, h = 50, text = "取消", size = T.f.sub,
        tcolor = C.text_sub, radius = 12,
        on_click = function()
            sys.timerStart(function() close_pay(); toast("已取消支付") end, 40)
        end })
    local okbtn
    okbtn = pill(card, { x = 201, y = 362, w = 167, h = 50, text = "我已完成支付", size = T.f.body,
        weight = 600, on_click = function()
            if paying then return end
            paying = true
            pcall(function() okbtn.lbl:set_text("支付处理中…") end)
            sys.timerStart(function()
                if not pay_ui then return end
                pcall(function() okbtn.lbl:set_text("支付成功") end)
                sys.timerStart(function()
                    if not pay_ui then return end
                    close_pay()
                    toast("支付成功，洗车房 A 已启动")
                    start_wash()
                end, 640)
            end, 620)
        end })
    W.text(card, { text = "· 微信支付 · 支付宝 · 会员余额", x = 0, y = 424, w = 392, h = 20,
        size = T.f.sub, color = C.text_dim, align = airui.TEXT_ALIGN_CENTER })
    pay_ui = { root = root, cd = cd_num, idx = W.reg_group(pay_mark) }
    pay_left = 180
    paying = false
    if t_pay then pcall(function() sys.timerStop(t_pay) end) end
    t_pay = sys.timerLoopStart(function()
        if not pay_ui then return end
        pay_left = pay_left - 1
        if pay_left <= 0 then
            sys.timerStart(function() close_pay(); toast("支付超时，订单已取消") end, 5)
            return
        end
        pcall(function() cd_num:set_text(S.fmt_mmss(pay_left)) end)
    end, 1000)
end

close_pay = function()
    if t_pay then pcall(function() sys.timerStop(t_pay) end); t_pay = nil end
    if pay_ui then
        pcall(function() pay_ui.root:destroy() end)
        W.reg_kill(pay_ui.idx)                   -- 只作废弹层自己的登记项
        pay_ui = nil
    end
end

-- ==================== 主题菜单 ====================
open_menu = function()
    if menu_ui then return end
    menu_mark = W.reg_mark()
    local root = W.box(ROOT, 0, 0, SW, SH, 0x000000, 0, 0)
    -- HTML 里没有全屏遮罩，只有一层透明点击区用于「点外部关闭」
    W.press_layer(root, { x = 0, y = 0, w = SW, h = SH, radius = 0,
        on_click = function() close_menu() end })
    -- HTML #themeMenu：宽 272 / 圆角 16 / padding 12；行 padding 9/10、圆角 11、行距 6
    local pw = 272
    local ROW_H, ROW_W = 58, pw - 24
    local card = airui.container({ parent = root, x = 640, y = 86, w = pw, h = 177,
        color = C.card, color_opacity = 252, radius = 16, border_width = 0,
        scrollable = false, on_click = function() end })
    W.glass(card, C.card, 252)
    -- HTML #themeMenu 同样有 1px --hair 描边
    W.stroke(root, 640, 86, pw, 177, 16, G.hair_color, G.hair_opa)
    -- .tmhead：eyebrow 16/600 + hint 16 dim，padding 2px 4px 10px
    W.text(card, { text = "外观主题", x = 16, y = 14, w = 160, h = 22, size = T.f.sub,
        color = C.text_sub, weight = 600 })
    W.text(card, { text = "2 套", x = 196, y = 14, w = 60, h = 22, size = T.f.sub,
        color = C.text_dim, align = airui.TEXT_ALIGN_RIGHT })
    local list = {
        { mode = "dawn",  name = "晨曦白", desc = "晨光暖白 · 淡霞",
          sw_l = 0xFFFDFB, sw_r = 0xAE6B52 },
        { mode = "night", name = "夜青",   desc = "深色水感 · 青碧冷光",
          sw_l = 0x0D1519, sw_r = 0x57C9B6 },
    }
    menu_ui = { root = root, card = card }
    for i, it in ipairs(list) do
        local on = (T.mode == it.mode)
        local y = 43 + (i - 1) * (ROW_H + 6)
        -- .tmopt：底色 surface3，选中 a13 + 描边 a45
        local row = W.box(card, 12, y, ROW_W, ROW_H, 0xFFFFFF, 11,
            on and (G.a13_opa or 33) or (G.surface3_opa or 82))
        local st = W.stroke(card, 12, y, ROW_W, ROW_H, 11, C.pri, on and (G.a45_opa or 115) or 0)
        -- .sw：22x22 / 圆角 7 / 左右各半（色值按 HTML 固定），外层圆角裁剪子级
        local sw = W.box(row, 10, 18, 22, 22, it.sw_l, 7, 255)
        W.box(sw, 11, 0, 11, 22, it.sw_r, 0, 255)
        W.stroke(row, 10, 18, 22, 22, 7, G.hair_color, G.hair3_opa or 54)
        -- .tml b / em
        W.text(row, { text = it.name, x = 42, y = 9, w = 160, h = 22, size = T.f.sub,
            color = on and C.pri or C.text, weight = 600 })
        W.text(row, { text = it.desc, x = 42, y = 30, w = 170, h = 20, size = T.f.sub,
            color = C.text_dim })
        -- .chk：20x20 主色对勾，仅选中显示
        if on then
            W.icon(row, { symbol = airui.SYMBOL_OK, x = 218, y = 19, size = 18,
                w = 20, h = 20, color = C.pri })
        end
        W.press_layer(row, { x = 0, y = 0, w = ROW_W, h = ROW_H, radius = 11,
            on_click = function()
                if T.mode == it.mode then
                    sys.timerStart(function() close_menu() end, 30)
                    return
                end
                -- 热切换：按颜色映射批量改色，不销毁任何控件；先收起菜单
                close_menu()
                sys.timerStart(function() M.set_theme(it.mode) end, 16)
            end })
    end
    menu_ui = { root = root, card = card, idx = W.reg_group(menu_mark) }
end

close_menu = function()
    if menu_ui then
        pcall(function() menu_ui.root:destroy() end)
        W.reg_kill(menu_ui.idx)                  -- 只作废菜单自己的登记项
        menu_ui = nil
    end
end

-- ==================== 时钟 ====================
local WK = { "周日", "周一", "周二", "周三", "周四", "周五", "周六" }
-- 始终显示设备系统时间（os.time），不做「是否已同步」的判断：
-- 没联网同步时 os.time() 是从开机起算的时间，也照原样显示，不再出现 --:-- / 时间待同步
local function update_clock()
    if not lbl_clock then return end
    local t = os.time()
    if not t then return end
    local d = os.date("*t", t)
    if not (d and d.hour) then return end
    local s1 = string.format("%02d:%02d:%02d", d.hour, d.min, d.sec)
    local s2 = string.format("%d月%d日 %s", d.month, d.day, WK[d.wday])
    if s1 == clock_cache then return end             -- 同值不重绘
    clock_cache = s1
    pcall(function()
        lbl_clock:set_text(s1)
        lbl_date:set_text(s2)
    end)
end

-- ==================== 销毁 / 构建 ====================
function M.destroy()
    gen = gen + 1
    if t_clock then pcall(function() sys.timerStop(t_clock) end); t_clock = nil end
    if t_wash  then pcall(function() sys.timerStop(t_wash) end);  t_wash  = nil end
    if t_pay   then pcall(function() sys.timerStop(t_pay) end);   t_pay   = nil end
    if PAGE then pcall(function() PAGE:destroy() end); PAGE = nil end
    BASE, ROOT, PANELS = nil, airui.screen, nil
    STAGE, HANDLES = {}, {}
    PANELS_SELECT = nil
    W.reg_reset()
    toast_box = nil
    lbl_clock, lbl_date, lbl_dev, lbl_bay = nil, nil, nil, nil
    pkg_cards, addon_chips, steps_box = nil, nil, nil
    lbl_pkg_dur, lbl_step_cnt, bill_vals, lbl_total = nil, nil, nil, nil
    lbl_coupon_state, coupon_box, coupon_in, lbl_pay = nil, nil, nil, nil
    wash_ui, done_ui, pay_ui, menu_ui = nil, nil, nil, nil
end

-- 主题热切换：不改结构、不重建控件，只按「旧色值 → 新色值」批量改色
function M.set_theme(mode)
    local t0 = 0
    pcall(function() t0 = mcu.ticks() end)
    local oldc, oldg = {}, {}
    for k, v in pairs(T.c) do oldc[k] = v end
    for k, v in pairs(T.glass) do oldg[k] = v end
    T.set_mode(mode)
    local map = {}
    for k, v in pairs(oldc) do
        local nv = T.c[k]
        if type(v) == "number" and type(nv) == "number" then map[v] = nv end
    end
    for k, v in pairs(oldg) do
        local nv = T.glass[k]
        if type(v) == "number" and type(nv) == "number" and map[v] == nil then map[v] = nv end
    end
    local n = W.retint(map)
    pcall(function() W.apply_hl(G.hl_opa) end)     -- 顶部高光条透明度随主题变
    pcall(function() W.apply_theme_hooks() end)    -- 渐隐投影等“计算色”重算
    repaint_background()
    -- 少量「运行时用 glass 设色」的地方（芯片圆点、选中卡、结算栏）重新走一遍
    if S.stage == "wash" then
        if lbl_dev then lbl_dev.set("运行中", "busy") end
        if lbl_bay then lbl_bay.set("洗车房 A · 洗车中") end
        if wash_ui then pcall(paint_wash) end
    else
        if lbl_dev then lbl_dev.set("设备就绪") end
        if lbl_bay then lbl_bay.set("洗车房 A · 空闲") end
        if S.stage == "done" then
            if done_ui then pcall(fill_done) end
        else
            for _, c in ipairs(pkg_cards or {}) do pcall(function() c.render(c.id == S.cur) end) end
            for i, a in ipairs(S.addons or {}) do
                if addon_chips and addon_chips[i] then
                    pcall(function() addon_chips[i].set_active(S.addon_on(a.id)) end)
                end
            end
            refresh_sig = nil
            pcall(refresh_select)
        end
    end
    draw_toast()
    log.info("page_wash", "主题热切换", mode, "改色对象", n, "耗时",
        (t0 > 0) and (mcu.ticks() - t0) or -1, "ms")
end

function M.create(root)
    local t0 = 0
    pcall(function() t0 = mcu.ticks() end)
    M.destroy()
    BASE = root or airui.screen
    PAGE = airui.container({ parent = BASE, x = 0, y = 0, w = SW, h = SH,
        color = 0x000000, color_opacity = 0, border_width = 0, scrollable = false })
    ROOT = PAGE
    S.stage = S.stage or "select"
    build_background()
    build_topbar()
    build_panels()
    set_stage(S.stage)
    if S.stage == "wash" then
        if lbl_dev then lbl_dev.set("运行中", "busy") end
        if lbl_bay then lbl_bay.set("洗车房 A · 洗车中") end
        start_ticker()
        paint_wash()
    end
    update_clock()
    t_clock = sys.timerLoopStart(update_clock, 1000)   -- 秒级刷新（原来 20s 一次，秒数不跳）
    log.info("page_wash", "自助洗车机界面已创建，主题", T.mode, "构建", BUILD_TAG,
        "重建耗时", (t0 > 0) and (mcu.ticks() - t0) or -1, "ms")
    draw_toast()          -- 整页重建后，未过期的提示重新贴到最上层
end

return M
