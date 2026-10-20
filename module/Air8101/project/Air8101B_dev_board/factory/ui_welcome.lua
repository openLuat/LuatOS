--[[
@module  ui_welcome
@summary 开机画面：纯白底 + 居中 LOGO + 产品名 + 版本号 + 底部启动指示点
@version 4.0
@date    2026.10.19
@usage
    sys.publish("OPEN_WELCOME_WIN")   -- 由 ui_main 触发

对齐 Air8301 工厂工程 boot_win.lua 的开机范式（v4.0）
1. 页面上只留四样东西：LOGO、产品名、版本号、底部三个循环点亮的指示点。
   去掉了旧版的 logo 上下浮动和 spinner：白底上浮动像"抖动"，
   而且 spinner 和文字提示同时动，反倒不知道哪个才是加载指示。
2. LOGO 按图片真实宽高等比摆放（只读 PNG 文件头，不解码像素）：
   以 IMG_MAX_W×IMG_MAX_H 为位图区上限等比缩放，原图更小时最多放大
   UPSCALE_MAX 倍 —— 旧版不管原图多大都塞进 160×160 的方槽，方形图被无脑
   放大（64×64 → 2.5 倍）看着糊，非方形图还会被拉伸变形。
3. 停留 HOLD_MS 后关页进桌面；本页不注册任何输入。

logo 图片
把 logo.png 放到本目录（随脚本烧进 /luadb/logo.png）即可，推荐 256×256 以上、
24 位非隔行的直通式 PNG；没有图片时自动回落到"浅蓝圆角块 + A"，不会开天窗。

说明
- 全屏根容器用真实分辨率（S.W/S.H），其余元素用设计坐标（ui_kit / T.px 自动换算），
  5 寸 800×480 与 7/9/10 寸 1024×600 上比例一致。
]]

local exwin = require "exwin"
local ui    = require "ui_kit"
local T     = require "ui_theme"

local C, F, S = T.COLOR, T.FONT, T.SCREEN
local DW, DH = S.DW, S.DH
local px = T.px

local HOLD_MS       = 1800   -- 停留时长：够看清 LOGO，和 Air8301 开机页一致
local DOT_PERIOD_MS = 320    -- 底部指示点循环点亮周期

-- logo 图片候选路径（放工程根目录 → 随脚本烧进 /luadb/logo.png）
-- 找不到图片就回落到代码绘制的标识，保证开机页永远有东西显示
local LOGO_CANDIDATES = { "/luadb/logo.png", "/logo.png" }
local IMG_MAX_W   = 320      -- LOGO 位图区宽（设计像素）
local IMG_MAX_H   = 176      -- LOGO 位图区高（设计像素）
local UPSCALE_MAX = 2.2      -- 原图过小时的最大放大倍数（再大就明显糊）
local SLOT_Y      = 56       -- LOGO 位图区顶部（设计像素）
local LOGO_FALLBACK = 132    -- 回落绘制标识的边长（设计像素）

local win_id
local root, logo_bottom, content
local hold_timer, dot_timer
local dots, dot_idx

--- 只读 PNG 文件头拿宽高（不解码像素）；返回 w, h, 诊断信息
local function img_size(path)
    local f = io.open(path, "rb")
    if not f then return nil, nil, "打不开文件" end

    local sig = f:read(8) or ""
    if #sig < 8 or sig:byte(1) ~= 0x89 or sig:byte(2) ~= 0x50 then
        f:close()
        return nil, nil, "非 PNG（请导出 24 位直通式 PNG）"
    end

    -- 签名已读掉，接着是 IHDR 块：length(4) + "IHDR"(4) + w(4) + h(4)
    --   + 位深(1) + 颜色类型(1) + 压缩(1) + 滤波(1) + 隔行(1) + CRC(4) = 25 字节
    local hdr = f:read(25)
    f:close()
    if not hdr or #hdr < 25 or hdr:sub(5, 8) ~= "IHDR" then
        return nil, nil, "PNG 头不完整"
    end

    local function be32(i)
        return hdr:byte(i) * 0x1000000 + hdr:byte(i + 1) * 0x10000
             + hdr:byte(i + 2) * 0x100 + hdr:byte(i + 3)
    end

    local w, h = be32(9), be32(13)
    if w <= 0 or h <= 0 then return nil, nil, "PNG 宽高非法" end
    return w, h, ("颜色类型%d 隔行%d"):format(hdr:byte(18) or -1, hdr:byte(21) or -1)
end

--- 创建 LOGO：图片优先（等比、不硬拉）→ 回落绘制；返回对象和底边（设计坐标）
local function create_logo(parent)
    local src
    for _, p in ipairs(LOGO_CANDIDATES) do
        if io.exists(p) then src = p break end
    end

    if src then
        local pw, ph, extra = img_size(src)
        local w, h
        if pw and ph then
            -- 等比缩放到位图区内；原图比位图区小则最多放大 UPSCALE_MAX 倍
            local scale = math.min(IMG_MAX_W / pw, IMG_MAX_H / ph, UPSCALE_MAX)
            w = math.max(1, math.floor(pw * scale + 0.5))
            h = math.max(1, math.floor(ph * scale + 0.5))
            log.info("ui_welcome", "LOGO", src, pw .. "×" .. ph, extra or "",
                "显示", w .. "×" .. h)
            if pw < 128 then
                log.warn("ui_welcome", "logo.png 只有", pw .. "×" .. ph,
                    "，放大后偏糊；换一张 ≥256×256 的 PNG 会更清晰")
            end
        else
            w, h = IMG_MAX_H, IMG_MAX_H     -- 解析失败：正方形兜底，仍交给 airui 解码
            log.warn("ui_welcome", "LOGO 尺寸解析失败:", extra or "未知",
                "→ 按", w .. "×" .. h, "显示")
        end

        local y = SLOT_Y + math.floor((IMG_MAX_H - h) / 2)
        local ok, obj = pcall(airui.image, {
            parent = parent, x = px((DW - w) / 2), y = px(y),
            w = px(w), h = px(h), src = src,
        })
        if ok and obj then
            return obj, y + h
        end
        log.warn("ui_welcome", "LOGO 图片创建失败，回落代码绘制:", src)
    end

    -- 回落：浅蓝圆角块 + 品牌首字母
    local size = LOGO_FALLBACK
    local y = SLOT_Y + math.floor((IMG_MAX_H - size) / 2)
    local box = ui.no_scroll(airui.container({
        parent = parent, x = px((DW - size) / 2), y = px(y),
        w = px(size), h = px(size),
        color = C.PRIMARY_SOFT, radius = px(size * 0.26),
    }))
    ui.label({
        parent = box, x = px(2), y = math.floor((px(size) - F.HUGE) / 2),
        w = px(size) - px(4), h = F.HUGE + px(4),
        text = "A", size = F.HUGE, color = C.PRIMARY, align = airui.TEXT_ALIGN_CENTER,
    })
    return box, y + size
end

-- ===== 页面 =====

local function stop_timers()
    if dot_timer  then sys.timerStop(dot_timer)  dot_timer  = nil end
    if hold_timer then sys.timerStop(hold_timer) hold_timer = nil end
end

--- 底部三个指示点：当前点亮品牌蓝，其余浅蓝（和 Air8301 开机页的跑马灯一致）
local function create_dots(parent)
    dots = {}
    local size, gap, y = 10, 22, 418
    local x0 = (DW - (3 * size + 2 * gap)) / 2
    for i = 1, 3 do
        dots[i] = ui.no_scroll(airui.container({
            parent = parent, x = px(x0 + (i - 1) * (size + gap)), y = px(y),
            w = px(size), h = px(size),
            color = C.PRIMARY_SOFT, radius = px(size / 2),
        }))
    end
end

local function tick_dots()
    dot_idx = (dot_idx or 0) % 3 + 1
    for i, d in ipairs(dots or {}) do
        pcall(d.set_color, d, i == dot_idx and C.PRIMARY or C.PRIMARY_SOFT)
    end
end

local function create_ui()
    -- 整屏白底：根容器铺满真实分辨率（屏幕比例和 800:480 不一致时不留黑边）
    root = ui.no_scroll(airui.container({
        parent = airui.screen, x = 0, y = 0, w = S.W, h = S.H, color = C.CARD,
    }))

    -- 内容区：设计基准 800×480 等比放大后居中，页面内部坐标仍是设计坐标（px() 换算）
    -- 高度比根容器少 px(2)：与根容器等高时 AirUI 1.2.x 会在右侧画出一条滚动条
    content = ui.no_scroll(airui.container({
        parent = root, x = S.OX, y = S.OY, w = S.CW, h = S.CH - px(2), color = C.CARD,
    }))

    -- LOGO：图片等比优先，缺图回落绘制；第二返回值是 LOGO 底边（设计坐标）
    local obj
    obj, logo_bottom = create_logo(content)

    -- 产品名：LOGO 下方 24px，字号 F.BIG（28）
    local title_y = logo_bottom + 24
    ui.label({
        parent = content, x = 0, y = title_y, w = DW, h = 40,
        text = "Air8101B开发板", size = F.BIG, color = C.TEXT,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 版本号：紧跟产品名一行，弱化颜色（等于 Air8301 开机页的"版本 xxx"）
    local ver = _G.VERSION
    local ver_text = (ver and ver ~= "") and ("版本 " .. tostring(ver)) or (_G.PROJECT or "")
    ui.label({
        parent = content, x = 0, y = title_y + 40, w = DW, h = 28,
        text = ver_text, size = F.SMALL, color = C.TEXT_WEAK,
        align = airui.TEXT_ALIGN_CENTER,
    })

    create_dots(content)
    dot_idx = 0
    tick_dots()
end

local function on_timeout()
    -- 先开桌面、再关自己：exwin 窗口栈全程非空，进桌面不闪白屏（同 Air8301 boot_win）
    sys.publish("OPEN_IDLE_WIN")
    if win_id then
        exwin.close(win_id)
    end
end

local function on_create()
    create_ui()
    hold_timer = sys.timerStart(on_timeout, HOLD_MS)
    dot_timer  = sys.timerLoopStart(tick_dots, DOT_PERIOD_MS)
end

local function on_destroy()
    stop_timers()
    if root then
        pcall(function() root:destroy() end)
        root = nil
    end
    dots, dot_idx = nil, nil
    logo_bottom, content = nil, nil
    win_id = nil
end

sys.subscribe("OPEN_WELCOME_WIN", function()
    win_id = exwin.open({
        on_create      = on_create,
        on_destroy     = on_destroy,
        on_get_focus   = function() end,
        on_lose_focus  = function() end,
    })
end)
