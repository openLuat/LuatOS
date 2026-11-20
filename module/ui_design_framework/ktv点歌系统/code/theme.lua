--[[
@module theme
@summary AIR KTV 点歌系统 · 控件层 / 双主题配色 / 自绘图标
         依据 https://docs.openluat.com/osapi/core/airui （AirUI V1.2.x）
         设计稿 docs/index.html 1024×600，深/浅 × 蓝/紫/青

约定（六个项目复盘 + 官方文档）：
1. label 文本在框内顶部对齐 → txt() 下移 y、h 收紧到 size*1.28。
2. 只有 container 有 set_hidden；要整体隐藏就挂容器。
3. 坐标/半径/线宽取整；小数会让固件丢弃整批图元。
4. 不用 arc/ellipse（本批固件不渲染），弧线多段 line 拼。
5. 单 shape 图元 ≤32，超出吞后半段。
6. 无渐变能力：封面取渐变首色实底 + 高光块近似。
7. 字号 ≥16；中文宽按码点算（中文 1 / ASCII 0.55）。
8. 点击回调里销毁/重建走 defer（sys.timerStart 30ms）。
9. 可点区域最后压一层 hit，避免子 label/shape 拦触摸。
10. 禁用 sys.timerLoopStart，一律 taskInit + sys.wait。
11. 刷新 task 每帧 pcall，异常只记日志不退出。
12. 本地 luac 为整数固件版：不写浮点字面量，用 n/100 表达。
]]

local sys = require "sys"
local mock = require "mock"

local theme = {}
theme.W, theme.H = 1024, 600

local AL, AC, AR = airui.TEXT_ALIGN_LEFT, airui.TEXT_ALIGN_CENTER, airui.TEXT_ALIGN_RIGHT
theme.AL, theme.AC, theme.AR = AL, AC, AR

--------------------------------------------------------------------
-- 配色：CSS 变量 1:1 转 0xRRGGBB
--------------------------------------------------------------------
theme.PALETTES = {
    dark = {
        bg=0x10131D, nav=0x171C29, topbar=0x141827, mini=0x161B29,
        input=0x121624, card=0x20283A, card2=0x252E42, track=0x2C3550,
        tag=0x28324A, tag_text=0xCBD3E2, func=0x2A3450, text=0xFFFFFF,
        sub=0xA7B0C0, placeholder=0x5C6678, op_hover=0x33405C, del=0xFF7B8A,
        rank1=0xFFD35C, rank2=0xC9D4E8, rank3=0xE7A46B, toast_bg=0x141A2A,
        sw_off=0xC6D0E0, white=0xFFFFFF, black=0x0D1424,
        orange=0xFFB33D, orange2=0xF57C24, knob=0xFFB733,
        line_mix=0xFFFFFF, line_a=7/100,
        kb_bg=0x20283A, kb_key=0x252E42, kb_text=0xFFFFFF,
        kb_func=0x33405C, kb_border=0x2C3550, kb_cand=0x19D5D0,
    },
    light = {
        bg=0xF2F4F9, nav=0xE8ECF5, topbar=0xFFFFFF, mini=0xFFFFFF,
        input=0xF4F6FB, card=0xFFFFFF, card2=0xF0F3FA, track=0xDDE3EF,
        tag=0xE9EDF6, tag_text=0x3A4560, func=0xE1E7F2, text=0x1A2233,
        sub=0x5A6680, placeholder=0x9AA5BA, op_hover=0xDCE3F0, del=0xE0455C,
        rank1=0xD9A400, rank2=0x8492AC, rank3=0xB8753A, toast_bg=0xFFFFFF,
        sw_off=0xC7D0E0, white=0xFFFFFF, black=0x0D1424,
        orange=0xFFB33D, orange2=0xF57C24, knob=0xFFB733,
        line_mix=0x14203C, line_a=10/100,
        kb_bg=0xE9E9E9, kb_key=0xFFFFFF, kb_text=0x222222,
        kb_func=0xD0D0D0, kb_border=0xD0D0D0, kb_cand=0x0E9E99,
    },
}

theme.ACCENTS = {
    blue   = {dark={blue=0x2F5FE6,purple=0x6B4FE0,cyan=0x19D5D0},
              light={blue=0x2F62E6,purple=0x6649E8,cyan=0x0E9E99}},
    -- 梦幻紫：blue 槽也用深紫，使 C.ac（主色）真正呈紫色而非蓝紫
    purple = {dark={blue=0xA24BEF,purple=0x8B3FD6,cyan=0xC77DFF},
              light={blue=0x8B2FD6,purple=0x7420C0,cyan=0xA855F7}},
    cyan   = {dark={blue=0x00CDBE,purple=0x477BFF,cyan=0x2FE8D8},
              light={blue=0x0E9E99,purple=0x2F62E6,cyan=0x0BA8A3}},
}

theme.C = {}
theme.mode, theme.key = "dark", "blue"

function theme.mix(fg, bg, a)
    local r1,g1,b1 = math.floor(fg/65536)%256, math.floor(fg/256)%256, fg%256
    local r2,g2,b2 = math.floor(bg/65536)%256, math.floor(bg/256)%256, bg%256
    local r = math.max(0, math.min(255, math.floor(r1*a + r2*(1-a) + 50/100)))
    local g = math.max(0, math.min(255, math.floor(g1*a + g2*(1-a) + 50/100)))
    local b = math.max(0, math.min(255, math.floor(b1*a + b2*(1-a) + 50/100)))
    return r*65536 + g*256 + b
end

function theme.apply(mode, key)
    theme.mode = (mode == "light") and "light" or "dark"
    theme.key = theme.ACCENTS[key] and key or "blue"
    local src = theme.PALETTES[theme.mode]
    for k,v in pairs(src) do theme.C[k] = v end
    for k,v in pairs(theme.ACCENTS[theme.key][theme.mode]) do theme.C[k] = v end
    local C = theme.C
    C.line = theme.mix(C.line_mix, C.bg, C.line_a)
    C.line2 = theme.mix(C.line_mix, C.bg, C.line_a*2)
    C.ac = C.blue
    C.acw = theme.mix(C.blue, C.bg, 22/100)
    C.acline = theme.mix(C.blue, C.bg, 42/100)
    C.glow = theme.mix(C.blue, C.purple, 50/100)
    return theme.mode
end
theme.apply("dark", "blue")

local C = theme.C

function theme.defer(fn, ms)
    if not fn then return end
    sys.timerStart(function()
        local ok,err = pcall(fn)
        if not ok then pcall(log.error,"theme","defer: "..tostring(err)) end
    end, ms or 30)
end

function theme.nilcall(o, m, ...)
    if not o or not o[m] then return nil end
    return pcall(o[m], o, ...)
end

function theme.text_w(s, unit)
    s, unit = tostring(s or ""), unit or 1
    local n = 0
    for _,c in utf8.codes(s) do n = n + ((c > 0x2E80) and 1 or 55/100) end
    return math.floor(n*unit + 50/100)
end

function theme.fmt_time(s)
    s = math.max(0, math.floor(tonumber(s) or 0))
    return string.format("%02d:%02d", math.floor(s/60), s%60)
end

-- UTF-8 安全取首字符：按字节 sub(1,1) 会把汉字截成半个字，显示成空白
-- "凤凰传奇" -> "凤"，"BEYOND" -> "B"
function theme.first_char(s)
    s = tostring(s or "")
    if s == "" then return "" end
    local ok, i = pcall(utf8.offset, s, 2)
    if ok and i and i > 2 then return s:sub(1, i-1) end
    if ok and i and i == 2 then return s:sub(1,1) end
    return s
end

--------------------------------------------------------------------
-- 颜色注册表：切主题原位换色，不重建控件
--------------------------------------------------------------------
local entries = {}
local function keyof(col)
    if col == nil then return nil end
    -- 深色主题 text/white 同为 0xFFFFFF：优先匹配 text，避免文字被固定成白色
    if col == 0xFFFFFF and C.text == 0xFFFFFF then return "text" end
    for k,v in pairs(C) do if v == col then return k end end
    return nil
end
local function getter(col)
    -- 传字符串时按语义 key 取色：theme.txt(..., "text", ...) 会随主题变化
    if type(col) == "string" then
        return function() return C[col] end
    end
    if col == nil then return function() return col end end
    local k = keyof(col)
    if k then return function() return C[k] end end
    return function() return col end
end
function theme.register(o, get, opa, border)
    if o then entries[#entries+1] = {o=o, get=get, opa=opa, border=border} end
end
function theme.clear_registry() entries = {} end
function theme.recolor()
    for i=1,#entries do
        local e = entries[i]
        local col = e.get()
        if e.border then theme.nilcall(e.o,"set_border_color",col)
        elseif e.opa then theme.nilcall(e.o,"set_color",col,e.opa)
        else theme.nilcall(e.o,"set_color",col) end
    end
end

--------------------------------------------------------------------
-- 基础控件
--------------------------------------------------------------------
function theme.box(parent,x,y,w,h,color,radius)
    local col = color or C.card
    local o = airui.container({parent=parent,x=math.floor(x),y=math.floor(y),
        w=math.floor(w),h=math.floor(h),color=col,radius=math.floor(radius or 0)})
    theme.register(o, getter(col))
    return o
end

function theme.box_a(parent,x,y,w,h,color,radius,opa)
    local col = color or C.card
    local o = airui.container({parent=parent,x=math.floor(x),y=math.floor(y),
        w=math.floor(w),h=math.floor(h),color=col,color_opacity=opa or 255,
        radius=math.floor(radius or 0)})
    theme.register(o, getter(col), opa or 255)
    return o
end

function theme.box_b(parent,x,y,w,h,color,radius,bcol,bw)
    local col,bc = color or C.card, bcol or C.line
    local o = airui.container({parent=parent,x=math.floor(x),y=math.floor(y),
        w=math.floor(w),h=math.floor(h),color=col,radius=math.floor(radius or 0),
        border_color=bc,border_width=bw or 1})
    theme.register(o, getter(col))
    theme.register(o, getter(bc), nil, true)
    return o
end

function theme.circle(parent,x,y,d,color)
    local col = color or C.ac
    d = math.floor(d)
    local o = airui.container({parent=parent,x=math.floor(x),y=math.floor(y),
        w=d,h=d,color=col,radius=math.floor(d/2)})
    theme.register(o, getter(col))
    return o
end

-- label 顶部对齐修正
function theme.txt(parent,x,y,w,h,text,color,size,align)
    size = size or 16
    local lh = math.floor(size*128/100 + 50/100)
    local ny = math.floor(y)
    if h and h > lh then ny = ny + math.floor((h-lh)/2) end
    local col = color or C.text
    local o = airui.label({parent=parent,x=math.floor(x),y=ny,
        w=math.floor(w),h=lh,text=text or "",color=col,
        font_size=size,align=align or AL})
    theme.register(o, getter(col))
    return o
end

-- 内置 symbol（小图标，字号 ≤24）
function theme.symbol(parent,x,y,w,h,sym,color,size)
    local col = color or C.sub
    local o = airui.label({parent=parent,x=math.floor(x),y=math.floor(y),
        w=math.floor(w),h=math.floor(h),symbol=sym,
        font_size=math.min(size or 20,24),color=col,align=AC})
    theme.register(o, getter(col))
    return o
end

-- quiet=true 时不做按下白闪（侧栏这类自带激活态的地方用，免得按下冒出透明白框）
function theme.hit(parent,x,y,w,h,fn,quiet)
    local o = airui.container({parent=parent,x=math.floor(x),y=math.floor(y),
        w=math.floor(w),h=math.floor(h),color=C.white,radius=0})
    theme.nilcall(o,"set_color",C.white,0)
    if fn then
        theme.nilcall(o,"set_on_click",function(self)
            if not quiet then
                -- 按下反馈：亮一下再向外慢慢淡去（分 5 步降透明度）
                theme.nilcall(o,"set_color",C.white,72)
                local step = 0
                local function fade()
                    step = step + 1
                    local opa = math.max(0, 72 - step*15)
                    theme.nilcall(o,"set_color",C.white,opa)
                    if opa > 0 then sys.timerStart(fade, 36) end
                end
                sys.timerStart(fade, 36)
            end
            local ok,err = pcall(fn, self)
            if not ok then pcall(log.error,"theme","hit: "..tostring(err)) end
        end)
    end
    return o
end

function theme.shape(parent,x,y,w,h)
    return airui.shape({parent=parent,x=math.floor(x),y=math.floor(y),
        w=math.floor(w),h=math.floor(h),items={}})
end

local drawn = {}
function theme.put(sh, items)
    if not sh then return end
    local has = items and #items > 0
    if not has and drawn[sh] == false then return end
    drawn[sh] = has or nil
    theme.nilcall(sh,"set_items",items or {})
end
function theme.reset_draw() drawn = {} end

--------------------------------------------------------------------
-- 图元 helper
--------------------------------------------------------------------
local function ln(x1,y1,x2,y2,col,w)
    return {type="line",x1=math.floor(x1),y1=math.floor(y1),
        x2=math.floor(x2),y2=math.floor(y2),color=col,width=w or 1,
        round_start=true,round_end=true}
end
local function rc(x,y,w,h,col,r)
    return {type="rect",x=math.floor(x),y=math.floor(y),
        w=math.floor(w),h=math.floor(h),radius=math.floor(r or 0),
        color=col,width=1,fill=true,fill_color=col,fill_opacity=255}
end
local function cl(cx,cy,r,col,fill)
    return {type="circle",cx=math.floor(cx),cy=math.floor(cy),r=math.floor(r),
        color=col,width=1,fill=(fill~=false),fill_color=col,
        fill_opacity=(fill==false) and 0 or 255}
end
local function ARC(it,cx,cy,r,a0,a1,col,w)
    local n = math.max(3, math.floor(math.abs(a1-a0)/15 + 50/100))
    local px,py
    for i=0,n do
        local a = math.rad(a0 + (a1-a0)*i/n)
        local x,y = math.floor(cx+r*math.cos(a)), math.floor(cy+r*math.sin(a))
        if i>0 then it[#it+1] = ln(px,py,x,y,col,w) end
        px,py = x,y
    end
end
theme.ln, theme.rc, theme.cl = ln, rc, cl

--------------------------------------------------------------------
-- 34 个自绘图标：24×24 归一化，l=线 r=矩形 c=圆 a=弧
--------------------------------------------------------------------
local G = {
    note={l={{9,18,9,5},{9,5,20,3},{20,3,20,16}},c={{6,18,3,1},{17,16,3,1}}},
    home={l={{3,11,12,4},{12,4,21,11},{5,10,5,20},{5,20,19,20},{19,20,19,10},{9,20,9,14},{15,14,15,20},{9,14,15,14}}},
    cat={r={{3,3,7,7,1},{14,3,7,7,1},{3,14,7,7,1},{14,14,7,7,1}}},
    artist={c={{12,8,4,1}},l={{4,21,4,19},{4,19,8,15},{8,15,16,15},{16,15,20,19},{20,19,20,21}}},
    search={c={{11,11,7,0}},l={{16,16,20,20}}},
    list={l={{8,6,20,6},{8,12,20,12},{8,18,20,18}},c={{4,6,1,1},{4,12,1,1},{4,18,1,1}}},
    rank={l={{4,20,4,10},{4,10,9,10},{9,10,9,20},{10,20,10,4},{10,4,15,4},{15,4,15,20},{16,20,16,13},{16,13,21,13},{21,13,21,20},{2,20,22,20}}},
    playlist={l={{4,6,18,6},{4,12,18,12},{4,18,13,18},{20,18,20,9},{20,9,23,8}},c={{18,18,2,0}}},
    playing={c={{12,12,9,0}},l={{10,8,17,12},{17,12,10,16},{10,16,10,8}}},
    set={c={{12,12,3,0}},l={{12,2,12,5},{12,19,12,22},{2,12,5,12},{19,12,22,12},{5,5,7,7},{17,17,19,19},{19,5,17,7},{7,17,5,19}}},
    play={l={{8,5,8,19},{8,19,19,12},{19,12,8,5}}},
    pause={r={{7,5,4,14,0},{13,5,4,14,0}}},
    prev={l={{7,5,7,19},{20,5,9,12},{9,12,20,19},{20,19,20,5}}},
    next={l={{17,5,17,19},{4,5,15,12},{15,12,4,19},{4,19,4,5}}},
    plus={l={{12,5,12,19},{5,12,19,12}}},
    trash={l={{4,7,20,7},{9,7,9,4},{15,4,15,7},{6,7,7,20},{17,20,18,7},{7,20,17,20},{9,4,15,4}}},
    pin={l={{12,17,12,22},{8,3,16,3},{16,3,15,9},{15,9,18,12},{18,12,18,14},{6,14,18,14},{6,14,9,9},{9,9,8,3}}},
    vol={l={{4,9,4,15},{4,15,8,15},{8,15,13,19},{13,19,13,5},{13,5,8,9},{8,9,4,9}},a={{17,12,4,-55,55}}},
    clock={c={{12,12,9,0}},l={{12,7,12,12},{12,12,15,14}}},
    fire={l={{12,2,17,7},{17,7,17,12},{17,12,15,17},{15,17,9,17},{9,17,7,12},{7,12,7,7},{7,7,12,2},{10,13,10,10},{10,10,13,13},{13,13,14,15},{14,15,10,15}}},
    star={l={{12,3,15,9},{15,9,22,10},{22,10,17,15},{17,15,18,22},{18,22,12,18},{12,18,6,22},{6,22,7,15},{7,15,2,10},{2,10,9,9},{9,9,12,3}}},
    back={l={{15,5,8,12},{8,12,15,19}}},
    check={l={{5,12,9,16},{9,16,19,6}}},
    -- 月牙：外弧（圆心偏左，扫左侧）+ 内弧（圆心偏右下，反向扫内缘），两弧在两圆交点收尾成尖角
    moon={a={{11,12,9,45,292},{16,11,8,-102,79}}},
    sun={c={{12,12,4,0}},l={{12,2,12,5},{12,19,12,22},{2,12,5,12},{19,12,22,12},{5,5,7,7},{17,17,19,19},{19,5,17,7},{7,17,5,19}}},
    info={c={{12,12,9,0},{12,7,1,1}},l={{12,11,12,17}}},
    -- 重唱：细圆环（缺口在正上偏左）+ 缺口处朝上的箭头（对齐设计稿那个回转箭头）
    replay={a={{12,13,8,-50,195}},l={{7,10,7,5},{4,8,7,5},{10,8,7,5}}},
    mic={r={{9,3,6,11,3}},a={{12,11,7,0,180}},l={{12,18,12,21},{8,21,16,21}}},
    mute={l={{4,9,4,15},{4,15,8,15},{8,15,13,19},{13,19,13,5},{13,5,8,9},{8,9,4,9},{17,9,22,15},{22,9,17,15}}},
    eq={l={{6,20,6,10},{12,20,12,4},{18,20,18,13}},c={{6,8,2,1},{12,16,2,1},{18,11,2,1}}},
    control={l={{4,7,20,7},{4,17,20,17}},c={{9,7,3,1},{15,17,3,1}}},
    atmos={l={{9,18,15,18},{10,21,14,21},{9,14,15,14},{10,7,12,3},{12,3,14,7}},a={{12,12,6,190,350}}},
    snow={l={{12,2,12,22},{4,6,20,18},{20,6,4,18},{9,4,12,7},{12,7,15,4},{9,20,12,17},{12,17,15,20}}},
    wind={l={{3,8,14,8},{14,8,16,6},{16,6,14,4},{3,12,17,12},{17,12,19,14},{3,16,11,16},{11,16,13,18}}},
    drop={l={{12,3,17,12},{17,12,17,15},{17,15,12,20},{12,20,7,15},{7,15,7,12},{7,12,12,3}}},
}

function theme.ic_items(name,w,h,col,lw)
    local d = G[name]
    local it = {}
    if not d then return it end
    local scale = math.min(w/24, h/24)
    local ox,oy = (w-24*scale)/2, (h-24*scale)/2
    local function X(v) return math.floor(ox+v*scale) end
    local function Y(v) return math.floor(oy+v*scale) end
    local function S(v) return math.max(1, math.floor((v or 1)*scale + 50/100)) end
    if d.l then
        for i=1,#d.l do local s=d.l[i]; it[#it+1]=ln(X(s[1]),Y(s[2]),X(s[3]),Y(s[4]),col,S(lw)) end
    end
    if d.r then
        for i=1,#d.r do local s=d.r[i]
            it[#it+1]=rc(X(s[1]),Y(s[2]),math.floor(s[3]*scale),math.floor(s[4]*scale),col,math.floor((s[5] or 0)*scale))
        end
    end
    if d.c then
        for i=1,#d.c do local s=d.c[i]; it[#it+1]=cl(X(s[1]),Y(s[2]),math.floor(s[3]*scale),col,s[4]~=0) end
    end
    if d.a then
        for i=1,#d.a do local s=d.a[i]; ARC(it,X(s[1]),Y(s[2]),math.floor(s[3]*scale),s[4],s[5],col,S(lw)) end
    end
    return it
end

function theme.icon(parent,x,y,w,h,name,color,lw)
    local sh = theme.shape(parent,x,y,w,h)
    theme.put(sh, theme.ic_items(name,w,h,color or C.sub,lw or 2))
    return sh
end
function theme.icon_set(sh,w,h,name,color,lw)
    theme.put(sh, theme.ic_items(name,w,h,color or C.sub,lw or 2))
end

-- 歌曲封面图元：彩色底 + 高光块 + 背景同心圆 + 右下角音符
-- 单 shape 图元数约 8 个，低于固件 32 上限
-- skip_base=true 时不画底色矩形（底色由封面底 container 负责），只留装饰
function theme.cover_items(size, idx, radius, base, skip_base)
    size = math.floor(size)
    local g = mock.gradient(idx or 0)
    local b = base or g[1]
    local hi = base and theme.mix(0xFFFFFF, b, 18/100) or g[2]
    local r = radius or math.floor(size*18/100)
    local items = {}
    if not skip_base then items[#items+1] = rc(0,0,size,size,b,r) end
    items[#items+1] = rc(2,2,math.floor(size*55/100),math.floor(size*26/100),hi,r)
    -- 居中的淡色同心圆（设计稿里环正好套住首字）
    local light = theme.mix(0xFFFFFF, b, 26/100)
    local cx, cy = math.floor(size/2), math.floor(size/2)
    items[#items+1] = cl(cx, cy, math.floor(size*46/100), light, false)
    items[#items+1] = cl(cx, cy, math.floor(size*29/100), light, false)
    -- 右下角音符
    local nw = math.max(10, math.floor(size*34/100))
    local nx = size - nw - math.floor(size*7/100)
    local ny = size - nw - math.floor(size*4/100)
    local note = theme.ic_items("note", nw, nw, theme.mix(0xFFFFFF, b, 55/100), 1)
    for i=1,#note do
        local it = note[i]
        if it.type == "line" then
            it.x1,it.y1,it.x2,it.y2 = it.x1+nx,it.y1+ny,it.x2+nx,it.y2+ny
        elseif it.type == "rect" then
            it.x,it.y = it.x+nx,it.y+ny
        elseif it.type == "circle" then
            it.cx,it.cy = it.cx+nx,it.cy+ny
        end
        items[#items+1] = it
    end
    return items
end

local function cover_font(size)
    return math.min(52, math.max(18, math.floor(size*42/100 + 50/100)))
end

-- 封面（一次性静态绘制，返回首字 label 便于后续换字）
function theme.cover(parent,x,y,size,idx,label,radius)
    local o = theme.songcover(parent,x,y,size,idx,radius)
    if label and o.mk then pcall(o.mk.set_text, o.mk, tostring(label)) end
    return o.mk
end

-- 可换歌的封面对象：{cv=, sh=, mk=, size=, radius=, idx=, base=}
-- 底色用 container（换歌只 set_color，不动 z 序），装饰用 shape，首字 label 最后建 → 永远在最上层
function theme.songcover(parent,x,y,size,idx,radius,base)
    size = math.floor(size)
    local g = mock.gradient(idx or 0)
    local col = base or g[1]
    local r = radius or math.floor(size*18/100)
    local cv = theme.box(parent,x,y,size,size,col,r)
    local sh = theme.shape(parent,x,y,size,size)
    -- 装饰图元在首字 label 之前画好，保证字压在最上层
    theme.put(sh, theme.cover_items(size,idx or 0,r,base,true))
    local fs = cover_font(size)
    local lh = math.floor(fs*128/100 + 50/100)
    local mk = theme.txt(parent,x,y+math.floor((size-lh)/2),size,lh,"",0xFFFFFF,fs,AC)
    return {cv=cv,sh=sh,mk=mk,size=size,radius=r,idx=idx or 0,base=base,color=col}
end

function theme.songcover_set(o, idx, name)
    if not o then return end
    if idx then o.idx = idx end
    local g = mock.gradient(o.idx or 0)
    local col = o.base or g[1]
    -- 每次都设色：recolor 可能按注册色复位，这里重新贴回当前歌曲的颜色
    if o.cv then theme.nilcall(o.cv,"set_color",col,255) end
    if o.sh then theme.put(o.sh, theme.cover_items(o.size,o.idx,o.radius,o.base,true)) end
    if name and o.mk then
        pcall(o.mk.set_text, o.mk, theme.first_char(name))
    end
end

--------------------------------------------------------------------
-- 开关 / 滑杆 / 胶囊 / 进度条
--------------------------------------------------------------------
function theme.switch(parent,x,y,on,w)
    w = w or 44
    local track = theme.box(parent,x,y,w,24,on and C.ac or C.sw_off,12)
    local dot = theme.circle(parent,x+(on and (w-21) or 3),y+3,18,C.white)
    return {track=track,dot=dot,x=x,y=y,w=w,on=not not on}
end
function theme.sw_set(sw,on,color)
    sw.on = not not on
    theme.nilcall(sw.track,"set_color",on and (color or C.ac) or C.sw_off,255)
    theme.nilcall(sw.dot,"set_pos",sw.x+(on and (sw.w-21) or 3),sw.y+3)
end

-- 透明 slider 只收手指；轨道/填充/旋钮自绘
function theme.slider(parent,x,y,w,track_h,val,on_change)
    local h = math.max(32, track_h+22)   -- 加大透明触控区，pad=0 保证整块可点
    local oy = y + math.floor((track_h-h)/2)
    local ok,sl = pcall(airui.slider,{
        parent=parent,x=math.floor(x),y=math.floor(oy),
        w=math.floor(w),h=math.floor(h),min=0,max=100,
        value=math.floor(val or 0),
        style={bg_opa=0,indicator_opa=0,knob_opa=0,border_width=0,
            radius=math.floor(h/2),pad=0},
        on_change=on_change,
    })
    if not ok or not sl then return nil end
    return sl
end

function theme.pill(parent,x,y,w,h,text,size,fn,pri)
    local bc,bd = pri and C.acw or C.card, pri and C.ac or C.line
    theme.box_b(parent,x,y,w,h,bc,math.floor(h/2),bd,1)
    local lb = theme.txt(parent,x,y,w,h,text,pri and C.white or C.sub,size or 16,AC)
    theme.hit(parent,x,y,w,h,fn)
    return lb
end

function theme.bar(parent,x,y,w,h,pct,col,r)
    theme.box(parent,x,y,w,h,C.track,math.floor(h/2))
    local sh = theme.shape(parent,x,y,w,h)
    theme.put(sh, pct>0 and {rc(0,0,math.floor(w*pct/100),h,col or C.blue,r or math.floor(h/2))} or {})
    return sh
end

return theme
