--[[
@module  ui_widget
@summary 安全原语层：内容区登记 + 越界收敛 + 热区 / 文本 / 图形 / 等宽数字
@note
  1) container 底层是 LVGL9 对象，默认可滚动且滚动条关不掉。子控件只要探出父内容区
     1px 就会画一条滚动条，所以这里不是"建议"收敛，而是**每个原语都强制收敛**：
     容器建好即登记 cw/ch = 外框 − 2×border_width，后续子控件按父登记值裁剪。
     业务层写错坐标只会被收缩 + 一条 log，不会在真机上炸出滚动条。
  2) 显隐一律不用 hide()/open()（open 恢复不回来，控件会永久藏死）。本项目的做法是
     整页销毁重建：切页时先 destroy 当前页根容器，再按新路由重建，没有残留、也没有
     跨页命中冲突。
  3) airui.label 没有 font_weight（F4），层级只能靠字号 + 色阶，这里不传这个参数。
  4) airui.shape 的 items 走 lua_tointeger，浮点会被静默转成 0（图元凭空消失），
     所以坐标一律 floor。
]]
local T = require "ui_theme"
local C = T.c
local M = {}

local CSIZE = setmetatable({}, { __mode = "k" })   -- 父对象 -> { cw, ch }
local WARNED = {}                                  -- tag -> true（越界日志只打一次）

local function warn_once(tag, right, bottom, cw, ch)
    if WARNED[tag] then return end
    WARNED[tag] = true
    -- 真机日志出现这条，说明有控件靠收敛兜住了，应回头改坐标而不是留着
    log.warn("uiw", string.format("越界已收敛 %s right=%d/%d bottom=%d/%d",
        tostring(tag), right, cw, bottom, ch))
end

local function csize(parent)
    local s = parent and CSIZE[parent]
    if s then return s.cw, s.ch end
    return T.W, T.H
end

-- ==================== 内容区收敛（A4） ====================
-- 返回裁剪后的 x, y, w, h。x/y 越界拉回 0，右侧/底部越界则收缩尺寸。
function M.fit(parent, x, y, w, h, tag)
    local cw, ch = csize(parent)
    x, y, w, h = x or 0, y or 0, w or 1, h or 1
    if x < 0 then x = 0 end
    if y < 0 then y = 0 end
    local right, bottom = x + w, y + h
    if right > cw then
        warn_once(tag, right, bottom, cw, ch)
        w = cw - x
    end
    if bottom > ch then
        warn_once(tag, right, bottom, cw, ch)
        h = ch - y
    end
    if w < 1 then w = 1 end
    if h < 1 then h = 1 end
    return x, y, w, h
end

-- 登记容器内容区。带描边的容器，子控件可用宽高每侧少一个 border_width。
local function reg(obj, w, h, bw)
    if not obj then return nil end          -- 创建失败时不能让 CSIZE[nil] 抛错
    bw = bw or 0
    CSIZE[obj] = { cw = w - 2 * bw, ch = h - 2 * bw }
    return obj
end

-- ==================== 颜色 ====================
-- 个别固件 set_color 不认第二个参数，失败后退回单参数版本（丢透明度但至少不断言崩溃）
function M.glass(obj, color, opa)
    if not obj then return end
    if not pcall(function() obj:set_color(color, opa) end) then
        pcall(function() obj:set_color(color) end)
    end
end

-- ==================== 基础容器 ====================
-- cfg: x y w h color radius border_w border_color opa tag
function M.box(parent, cfg)
    local bw = cfg.border_w or 0
    local x, y, w, h = M.fit(parent, cfg.x, cfg.y, cfg.w, cfg.h, cfg.tag or "box")
    local obj = airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = cfg.color,
        radius = cfg.radius or 0,
        border_width = bw,
        -- G2：不描边就不传 border_color，否则 opa 归零后框线仍然可见（幽灵框）
        border_color = (bw > 0) and (cfg.border_color or C.line) or nil,
        -- 第一道防线：即使几何算错也不画滚动条、不整屏滑动（老固件忽略该键）
        scrollable = false,
    })
    if cfg.opa then M.glass(obj, cfg.color, cfg.opa) end
    return reg(obj, w, h, bw)
end

-- 纯色圆角块（无内容区语义，仅装饰）。坐标按父内容区收敛。
function M.fill(parent, cfg)
    return M.box(parent, cfg)
end

-- ==================== 文本 ====================
-- hzfont 行高 = 字号 + 3（源码 g_airui_hzfont_extra_leading = 3）。
-- 所有字号由 main.lua 按 T.f.sizes 一次载齐，label 一定落在 hzfont 上，
-- 所以行高按 size+3 算；若某档漏载会回退到主题点阵字库（中文变方框），下面 warn_font 会先报出来。
local FSZ = {}
for _, s in ipairs(T.f.sizes) do FSZ[s] = true end

local font_warned = {}
local function warn_font(sz)
    if FSZ[sz] or font_warned[sz] then return end
    font_warned[sz] = true
    log.warn("uiw", "字号未预载，中文会渲染成方框，请加入 ui_theme.M.f.sizes", sz)
end

local function text_h(sz, declared)
    local need = sz + 3
    local h = declared or need
    return (h > need) and h or need
end

-- cfg: x y w h size color text align tag
function M.text(parent, cfg)
    local sz = cfg.size or T.f.body
    warn_font(sz)
    local x, y, w, h = M.fit(parent, cfg.x, cfg.y, cfg.w or 160, text_h(sz, cfg.h), cfg.tag or "text")
    return airui.label({
        parent = parent, text = cfg.text or "", x = x, y = y, w = w, h = h,
        font_size = sz, color = cfg.color or C.ink,
        align = cfg.align or airui.TEXT_ALIGN_LEFT,
    })
end

-- 垂直居中文字：label 文字在控件内是顶部对齐，所以让 label 高 = 真实行高，
-- 再按目标盒高中点定位。用 hzfont 行高（size+3），视觉中心才与盒中心重合。
function M.text_mid(parent, cfg)
    local sz = cfg.size or T.f.body
    warn_font(sz)
    local th = sz + 3
    local boxh = cfg.h or th
    local y = (cfg.y or 0) + math.floor((boxh - th) / 2)
    local x, yy, w, h = M.fit(parent, cfg.x, y, cfg.w or 160, th, cfg.tag or "tmid")
    return airui.label({
        parent = parent, text = cfg.text or "", x = x, y = yy, w = w, h = h,
        font_size = sz, color = cfg.color or C.ink,
        align = cfg.align or airui.TEXT_ALIGN_CENTER,
    })
end

-- ==================== 热区 ====================
-- 不用 airui.button：默认 2px 描边清不干净、hide 后 open 恢复不回来、
-- set_disabled 约定不稳。透明 container + Lua 闭包开关是唯一可靠的组合。
-- cfg: x y w h radius target tx ty on_click tag
function M.press(parent, cfg)
    local x, y, w, h = M.fit(parent, cfg.x, cfg.y, cfg.w, cfg.h, cfg.tag or "press")
    local enabled = true
    local hit = airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = 0xFFFFFF, color_opacity = 0,
        radius = cfg.radius or T.r.chip, border_width = 0,
        scrollable = false,
        on_click = function()
            if not enabled then return end
            M.glass(hit, 0xFFFFFF, 42)                    -- 即时按下反馈
            if cfg.target then pcall(function() cfg.target:set_pos(cfg.tx, cfg.ty + 2) end) end
            sys.timerStart(function()
                M.glass(hit, 0xFFFFFF, 0)
                if cfg.target then pcall(function() cfg.target:set_pos(cfg.tx, cfg.ty) end) end
            end, 90)
            if cfg.on_click then cfg.on_click() end
        end,
    })
    M.glass(hit, 0xFFFFFF, 0)                            -- 兜底：固件不认 color_opacity 时再压一次
    local hd = { obj = hit }
    function hd.set_disabled(v) enabled = not v end
    function hd.set_visible(v) enabled = v and true or false end
    return hd
end

-- ==================== 图形 ====================
-- airui.shape：line / circle / ellipse / rect 多图元（弧线用多段 line 折线近似）。
-- 老固件可能没有 shape 组件，此时返回 nil，调用方应能接受"没有装饰图"。
local function int_items(items)
    if type(items) ~= "table" then return items end
    for _, it in ipairs(items) do
        for k, v in pairs(it) do
            if type(v) == "number" and k ~= "opacity" and k ~= "width"
                and k ~= "radius" and k ~= "r" and k ~= "dash_width" and k ~= "dash_gap" then
                it[k] = math.floor(v)
            end
        end
    end
    return items
end

function M.shape(parent, cfg)
    local x, y, w, h = M.fit(parent, cfg.x, cfg.y, cfg.w, cfg.h, cfg.tag or "shape")
    local ok, obj = pcall(function()
        return airui.shape({ parent = parent, x = x, y = y, w = w, h = h,
            items = int_items(cfg.items or {}) })
    end)
    if ok and obj then return obj end
    return nil
end

-- ==================== 等宽数字 ====================
-- 真机 hzfont 的 advance width 等于字形位图宽度，"1111" 比 "8888" 窄一截，
-- 整串交给一个 label 会在改值时左右跳动（模拟器等宽字体永远复现不出来）。
-- 这里一格一个数字：'9' 是数字格（宽 size×0.66），其它字符是分隔格（宽 size×0.3），
-- 分隔格只建一次，改值只按位左对齐 set_text，位数变化不挪动其它数字。
--
-- cfg: x y size template color align tag
--   template 只写数字位与分隔符，例："99:99"、"9999"、"99.99"
--   set 用法：h.num_set(handle, "08:30") / h.num_set(handle, "2841")
function M.num(parent, cfg)
    local size = cfg.size or T.f.h3
    warn_font(size)
    local tpl = cfg.template or "9999"
    local dw = math.floor(size * 0.66)
    local sw = math.floor(size * 0.3)
    local th = size + 3

    local total, cells = 0, {}
    for i = 1, #tpl do
        local ch = tpl:sub(i, i)
        local cw = (ch == "9") and dw or sw
        cells[i] = { x = total, w = cw, digit = (ch == "9") }
        total = total + cw
    end

    local x, y, w, h = M.fit(parent, cfg.x, cfg.y, total, th, cfg.tag or "num")
    -- 外层透明容器：把整块数字当成一个整体定位，内部各格相对它排
    local root = airui.container({ parent = parent, x = x, y = y, w = w, h = h,
        color = -1, border_width = 0, scrollable = false })
    reg(root, w, h, 0)

    local align = cfg.align or airui.TEXT_ALIGN_CENTER
    local lbls = {}
    for i = 1, #cells do
        local c = cells[i]
        local bound = math.min(c.w, w - c.x)
        if bound > 0 then
            lbls[i] = airui.label({
                parent = root, text = c.digit and "0" or tpl:sub(i, i),
                x = c.x, y = 0, w = bound, h = th,
                font_size = size, color = cfg.color or C.ink, align = align,
            })
        end
    end

    local hd = { root = root, cells = cells, lbls = lbls, size = size }
    -- 填充规则：只从串里取数字字符，分隔符（: . -）由模板固定不动；
    -- 数字右对齐，高位不足补空格——这样 "4.00" 在 "999.99" 里会落在 4.00 的位置，
    -- 而 "12.00" 变宽时小数点不会移位。
    function hd.set(str)
        str = tostring(str or "")
        local nums = {}
        for k = 1, #str do
            local c = str:sub(k, k)
            if c >= "0" and c <= "9" then nums[#nums + 1] = c end
        end
        local dcount = 0
        for i = 1, #cells do
            if cells[i].digit then dcount = dcount + 1 end
        end
        local start = dcount - #nums + 1
        if start < 1 then start = 1 end
        local di = 0
        for i = 1, #cells do
            if cells[i].digit then
                di = di + 1
                local ni = di - (start - 1)
                local v = (ni >= 1 and ni <= #nums) and nums[ni] or " "
                local lb = lbls[i]
                if lb then pcall(function() lb:set_text(v) end) end
            end
        end
    end
    function hd.set_color(color)
        for i = 1, #lbls do
            if lbls[i] then pcall(function() lbls[i]:set_color(color) end) end
        end
    end
    return hd
end

function M.num_set(handle, str)
    if handle and handle.set then handle.set(str) end
end

return M
