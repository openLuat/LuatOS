--[[
@module theme
@summary 音频频谱 · 音乐律动 HMI —— 配色 / 通用控件 / 页面工厂 / 绘图工具
         设计稿 audio_spectrum_ui/preview.html（1024×800）
         实机 Air8603 10寸 1024×600，按 600 高重新排布

         === 沿用前几个工程的踩坑结论（务必遵守）===
         1. label 的 text 在控件框内是【顶部对齐】→ theme.txt 统一把 y 下移、h 收紧到
            size*1.28，调用方仍按"视觉块"给坐标。
         2. 只有 container 有 set_hidden；label / shape / button 【没有】。
            要整体隐藏就把它们塞进一个容器再隐藏容器。
         3. 所有坐标 / 半径 / 线宽一律取整。固件解析小数坐标会失败并丢弃【整批】图元。
         4. 不用 arc / ellipse 图元（本批固件不渲染），弧线一律多段折线 ARC() 拼。
         5. 单个 shape 的图元按 32 个一批分开建，超上限会吞掉后半段。
         6. 动态图元用 set_items 整表重建（复用同一张表不会触发重绘）；
            shape 容器范围要盖住整块图形，超出的图元会被裁剪。
         7. 深色界面没有渐变能力：用"纯色 + 多层低透明度圆"近似光晕。
         8. 字号下限 16（正文 16~18，数值 20~30，标题 18~22）。
         9. 点击回调里销毁/重建控件子树有 use-after-free 风险（错误还会被 pcall 吞掉，
            表现为"点了没反应"）→ 一律 sys.timerStart(fn, 30) 延迟到事件外执行。
        10. 子 label / shape 会拦触摸，出现"要点两下"→ 可点区域最后压一层 theme.hit。
        11. 部分固件 exwin 没有 bind_root → 必须 if exwin.bind_root then pcall(...) 保护。
        12. 切页必须"先 close 旧窗，再 open 新窗"，反过来会白屏。
        13. 【刷新循环禁用 sys.timerLoopStart】它是固定周期投递事件，与回调耗时
            无关；主任务每轮只消费一条事件，帧一重就积压，几分钟后事件池耗尽，
            触发 assert "task event too much" 断言死机（复位原因 6）。
            一律用 sys.taskInit + sys.wait：跑完本帧才开始计时，永不积压。
        14. 深浅主题：theme.C 是"当前生效"的调色板，toggle_theme() 就地覆写字段
            （不换表身份），所以页面里的 local C = theme.C 自动跟随；
            但已创建控件的颜色不会变，切完必须 theme.rerender_page() 重建整页，
            且必须在 LVGL 事件回调之外调用（页面里套 sys.timerStart(fn, 30)）。
]]

local sys   = require "sys"
local exwin = require "exwin"

local theme = {}

theme.W, theme.H = 1024, 600
pcall(function()
    local w, h = display.getSize()
    if w and h and w > 0 then theme.W = w end
    if h and h > 0 then theme.H = h end
end)

--------------------------------------------------------------------
-- 双主题：深色（默认，html 深海军蓝 + 紫青）/ 浅色
--
-- C 是"当前生效"的调色板。toggle_theme() 就地把字段值覆写进 theme.C，
-- 不换表身份 —— 页面里 `local C = theme.C` 拿的是同一张表，切完再
-- rerender 重建一次 UI 即可，不需要重新 require。
--
-- 额外语义色（页面里别硬编码）：
--   sel   选中/高亮的谱线色   strong 强调文字   knob 进度旋钮
--   ghost1/ghost2 波形背景辅助线   lum  色谱亮度（深浅主题对配色需求不同）
--------------------------------------------------------------------
theme.cur = "dark"
theme.PALETTES = {
    dark = {
        bg      = 0x050B12,
        bg2     = 0x081320,
        card    = 0x16283C,
        card2   = 0x0D1B2A,
        deep    = 0x0A1826,
        line    = 0x1E3A55,
        track   = 0x16304A,
        text    = 0xE6F3FF,
        sub     = 0x6F93B4,
        dim     = 0x4E6D8A,
        violet  = 0x8B5CF6,
        purple  = 0xA78BFA,
        blue    = 0x3B82F6,
        cyan    = 0x22D3EE,
        cyan2   = 0x67E8F9,
        white   = 0xFFFFFF,
        black   = 0x000000,
        red     = 0xE5533D,
        sel     = 0xF0FBFF,
        strong  = 0xFFFFFF,
        knob    = 0xFFFFFF,
        icon    = 0xBCE4FF,   -- 上一首/下一首图标
        ghost1  = 0x5B7FA6,
        ghost2  = 0x6E63C8,
        lum     = 63,
    },
    light = {
        bg      = 0xEDF1F8,
        bg2     = 0xFFFFFF,
        card    = 0xFFFFFF,
        card2   = 0xE7EEF8,
        deep    = 0xDCE5F2,
        line    = 0xC7D4E6,
        track   = 0xD3DFEE,
        text    = 0x0F2036,
        sub     = 0x566C84,
        dim     = 0x8496AA,
        violet  = 0x6D28D9,
        purple  = 0x7C3AED,
        blue    = 0x2563EB,
        cyan    = 0x0E9BB5,
        cyan2   = 0x0B7C93,
        white   = 0xFFFFFF,
        black   = 0x000000,
        red     = 0xD93A2B,
        sel     = 0x14304D,   -- 浅底上用深墨色高亮，白线会看不见
        strong  = 0x0F2036,
        knob    = 0x16283C,
        icon    = 0x1C6FB0,   -- 浅底上要压深，原来是 0xBCE4FF 在白色按钮上几乎看不见
        ghost1  = 0x8FA5BE,
        ghost2  = 0x9C8CD8,
        lum     = 52,
    },
}
theme.C = {}
for k, v in pairs(theme.PALETTES.dark) do theme.C[k] = v end
local C = theme.C

-- 深浅切换（就地覆写 C，返回 "dark"/"light"）；调用方切完必须 rerender
function theme.toggle_theme()
    theme.cur = (theme.cur == "dark") and "light" or "dark"
    for k, v in pairs(theme.PALETTES[theme.cur]) do theme.C[k] = v end
    log.info("theme", "switch to " .. theme.cur)
    return theme.cur
end

function theme.set_theme(name)
    if theme.PALETTES[name] and theme.cur ~= name then
        theme.cur = name
        for k, v in pairs(theme.PALETTES[name]) do theme.C[k] = v end
    end
    return theme.cur
end

theme.TOP_H = 52

--------------------------------------------------------------------
-- 基础控件
--------------------------------------------------------------------
function theme.box(parent, x, y, w, h, color, radius)
    return airui.container({ parent = parent, x = x, y = y, w = w, h = h,
        color = color or C.card, radius = radius or 0 })
end

-- 半透明底（color_opacity 0~255）
function theme.box_a(parent, x, y, w, h, color, opa, radius)
    return airui.container({ parent = parent, x = x, y = y, w = w, h = h,
        color = color, color_opacity = opa or 160, radius = radius or 0 })
end

function theme.box_b(parent, x, y, w, h, color, radius, bcol, bw)
    return airui.container({ parent = parent, x = x, y = y, w = w, h = h,
        color = color or C.card, radius = radius or 0,
        border_color = bcol or C.line, border_width = bw or 1 })
end

function theme.circle(parent, x, y, d, color, opa)
    local o = airui.container({ parent = parent, x = x, y = y, w = d, h = d,
        color = color, radius = math.floor(d / 2) })
    if opa then pcall(o.set_color, o, color, opa) end
    return o
end

-- 文本：调用方给"视觉块"，这里换成单行 label 并垂直居中（踩坑 1）
function theme.txt(parent, x, y, w, h, text, color, size, align)
    size = size or 16
    local lh = math.floor(size * 1.28 + 0.5)
    local ny = y
    if h and h > lh then ny = y + math.floor((h - lh) / 2) end
    return airui.label({ parent = parent, x = x, y = ny, w = w, h = lh,
        text = text or "", color = color or C.text,
        font_size = size, align = align })
end

-- 透明热区（踩坑 10：压在图标/文字上接收触摸）
function theme.hit(parent, x, y, w, h, on_click)
    local o = airui.container({ parent = parent, x = x, y = y, w = w, h = h,
        color = C.bg, radius = 0 })
    pcall(o.set_color, o, C.bg, 0)
    if on_click then pcall(o.set_on_click, o, on_click) end
    return o
end

-- 胶囊/圆角按钮：底色容器 + 文字 label + 透明热区
-- 返回 { bg = 容器, lb = 文字 }，用 theme.pill_on / pill_off 切换选中态
function theme.pill(parent, x, y, w, h, text, size, radius, on_click)
    local bg = airui.container({ parent = parent, x = x, y = y, w = w, h = h,
        color = C.card, color_opacity = 150,
        radius = radius or math.floor(h / 2),
        border_color = C.line, border_width = 1 })
    local lb = theme.txt(parent, x, y, w, h, text, C.sub, size or 16,
        airui.TEXT_ALIGN_CENTER)
    theme.hit(parent, x, y, w, h, on_click)
    return { bg = bg, lb = lb, w = w, h = h }
end

function theme.pill_on(p)
    pcall(p.bg.set_color, p.bg, C.cyan, 255)
    pcall(p.lb.set_color, p.lb, 0x08131F)
end

function theme.pill_off(p)
    pcall(p.bg.set_color, p.bg, C.card, 150)
    pcall(p.lb.set_color, p.lb, C.sub)
end

--------------------------------------------------------------------
-- 颜色工具：html 的 hsl 转 0xRRGGBB
--------------------------------------------------------------------
function theme.hue_col(h, s, l)
    h = (h % 360) / 360
    s = s / 100
    l = l / 100
    local c = (1 - math.abs(2 * l - 1)) * s
    local x = c * (1 - math.abs((h * 6) % 2 - 1))
    local m = l - c / 2
    local seg = math.floor(h * 6)
    local r, g, b
    if seg == 0 then r, g, b = c, x, 0
    elseif seg == 1 then r, g, b = x, c, 0
    elseif seg == 2 then r, g, b = 0, c, x
    elseif seg == 3 then r, g, b = 0, x, c
    elseif seg == 4 then r, g, b = x, 0, c
    else r, g, b = c, 0, x end
    r = math.floor((r + m) * 255 + 0.5)
    g = math.floor((g + m) * 255 + 0.5)
    b = math.floor((b + m) * 255 + 0.5)
    return r * 65536 + g * 256 + b
end

--------------------------------------------------------------------
-- 时间格式
--------------------------------------------------------------------
function theme.fmt_time(s)
    s = math.max(0, math.floor(s or 0))
    return string.format("%02d:%02d", math.floor(s / 60), s % 60)
end

--------------------------------------------------------------------
-- 页面工厂（单页 exwin）
-- build_fn(root) 返回 update, interval(ms)，按 interval 起刷新定时器
--------------------------------------------------------------------
local registry, current_win = {}, nil

function theme.register(idx, mod) registry[idx] = mod end

sys.subscribe("SWITCH_PAGE", function(idx)
    local mod = registry[idx]
    if not mod then return end
    if current_win then
        local w = current_win
        current_win = nil
        pcall(exwin.close, w)          -- 踩坑 12：先关旧窗
    end
    theme.page_idx = idx
    current_win = mod.open()
end)

function theme.open_page(idx) sys.publish("SWITCH_PAGE", idx) end

-- 主题切换用：重建当前页（必须在 LVGL 事件回调之外调用，页面里套 sys.timerStart(fn, 30)）
function theme.rerender_page(idx)
    local mod = registry[idx or theme.page_idx]
    if mod and mod.rerender then pcall(mod.rerender) end
end

function theme.make_page(idx, title, build_fn)
    local M = { idx = idx, title = title }
    local root, gen = nil, 0

    --[[
    刷新循环为什么不用 sys.timerLoopStart（实机踩坑 13，务必照抄）：

      定时器是【固定周期投递事件】，跟上一帧画没画完无关；而 luatos 主任务
      每轮只消费一条事件。刷新回调一旦比周期慢（这个页面每帧要标脏一大片
      shape 再让 LVGL 重绘），事件就开始积压：
        先刷 "no free static event"，几分钟后动态事件池耗尽，
        直接 assert "task event too much" → 断言死机（复位原因 6）。
      实测：40ms 一帧跑约 133 秒必死，把周期调大只会推迟死亡时间。

      改用 taskInit + sys.wait：本帧跑完才开始计时，永远不积压。
    ]]
    local function stop_loop()
        gen = gen + 1                  -- 让旧协程下一轮自动退出
    end

    local function create_ui()
        root = airui.container({ parent = airui.screen, x = 0, y = 0,
            w = theme.W, h = theme.H, color = C.bg })
        local update, interval = build_fn(root)
        if update then
            pcall(update)
            interval = interval or 100
            gen = gen + 1
            local my_gen = gen
            sys.taskInit(function()
                while gen == my_gen do
                    local ok, err = pcall(update)
                    if not ok then
                        pcall(log.error, "theme", "update error: " .. tostring(err))
                    end
                    sys.wait(interval)
                end
            end)
        end
        if exwin.bind_root then pcall(exwin.bind_root, root) end   -- 踩坑 11
    end

    function M.rerender()
        stop_loop()
        if root then pcall(root.destroy, root) root = nil end
        create_ui()
    end

    function M.open()
        return exwin.open({
            on_create  = create_ui,
            on_destroy = function()
                stop_loop()
                if root then root:destroy() root = nil end
            end,
        })
    end

    theme.register(idx, M)
    return M
end

return theme
