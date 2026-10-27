-- 图层：果饮插画JPG -> 共享原生液位 -> 透明PET空瓶PNG -> 原生文字和按钮。
-- 不画独立杯子。液位由固定的2px色带组成，保留PET瓶与背景的每像素透明度。
-- 只更新显隐/位置/颜色，不逐帧创建控件、不调用未公开的mask/resize接口。
local C = require "config"
local B = require "beverage"
local M = {}
local root, status, reset_button, fill_group, surface, glow
local cards, bands = {}, {}
local previous_phase, previous_drink, previous_size
local shown_rows = 0
local COL_X, COL_Y, COL_STEP = 24, 124, 248
local BOTTLE_X, BOTTLE_Y, BOTTLE_W, BOTTLE_H = 12, 50, 208, 336
-- 与bottle_empty.png内的直筒储液腔对齐；满量止于肩部下沿。
local LIQ_X, LIQ_Y, LIQ_W, LIQ_H = 50, 182, 132, 144
local ROW_H, ROWS = 2, 72
local ink, muted, mint, paper = 0x355C4A, 0x66816E, 0x4F9476, 0xFFFDF5

local function box(parent,x,y,w,h,color,radius)
    return airui.container({parent=parent,x=x,y=y,w=w,h=h,color=color,
        radius=radius or 0,border_width=0})
end
local function text(parent,x,y,w,h,value,size,color,align)
    return airui.label({parent=parent,x=x,y=y,w=w,h=h,text=value,
        font_size=size,color=color,align=align or airui.TEXT_ALIGN_LEFT})
end
local function button_style(accent,selected)
    return {bg_color=selected and accent or paper,bg_opa=selected and 255 or 235,
        text_color=selected and paper or ink,border_color=accent,border_width=1,
        radius=18,pad=0,pressed_bg_color=accent,pressed_text_color=paper}
end

local function build_liquid()
    fill_group=box(root,COL_X+LIQ_X,COL_Y+LIQ_Y,LIQ_W,LIQ_H)
    for n=1,ROWS do
        local y=(n-1)*ROW_H
        bands[n]=box(fill_group,0,y,LIQ_W,ROW_H,0xFFFFFF)
        bands[n]:set_hidden(true)
    end
    surface=box(fill_group,4,0,LIQ_W-8,2,0xFFF4CF,1)
    surface:set_color(0xFFF4CF,160)
    surface:set_hidden(true)
    fill_group:set_hidden(true)
end

local function set_level(level)
    local rows=math.max(0,math.min(ROWS,math.ceil(level*ROWS/3000)))
    if rows~=shown_rows then
        for n=math.min(shown_rows,rows)+1,math.max(shown_rows,rows) do
            bands[ROWS-n+1]:set_hidden(n>rows)
        end
        shown_rows=rows
    end
    fill_group:set_hidden(rows==0)
    surface:set_hidden(rows==0)
    if rows>0 then surface:set_pos(4,LIQ_H-rows*ROW_H) end
end

local function build_card(id)
    local d=C.DRINKS[id]
    local card=box(root,COL_X+(id-1)*COL_STEP,COL_Y,232,444)
    text(card,12,0,208,34,d.name,28,d.color,airui.TEXT_ALIGN_CENTER)
    text(card,12,36,208,18,d.english,13,d.color,airui.TEXT_ALIGN_CENTER)
    airui.image({parent=card,src="/luadb/bottle_empty.png",x=BOTTLE_X,y=BOTTLE_Y,
        w=BOTTLE_W,h=BOTTLE_H})
    -- 份量刻度也在瓶内；液位上沿逐步越过2/3和1/3位置。
    for _,yy in ipairs({LIQ_Y+48,LIQ_Y+96}) do
        box(card,LIQ_X+4,yy,15,1,ink):set_color(ink,90)
        box(card,LIQ_X+LIQ_W-19,yy,15,1,ink):set_color(ink,90)
    end
    local buttons={}
    for n,spec in ipairs(C.SIZES) do
        local size_id=n
        buttons[n]=airui.button({parent=card,x=69,y=177+(n-1)*50,w=94,h=38,
            text=spec.name,font_size=19,style=button_style(d.color,false),
            on_click=function() if B.select(id,size_id) then M.refresh() end end})
    end
    local volume=text(card,48,320,136,25,"请选择份量",16,ink,airui.TEXT_ALIGN_CENTER)
    local note_group=box(card,4,402,224,24)
    text(note_group,0,0,224,24,d.note,16,muted,airui.TEXT_ALIGN_CENTER)
    local start_group=box(card,18,398,196,44)
    local start=airui.button({parent=start_group,x=0,y=0,w=196,h=44,
        text="开始灌注",font_size=20,style=button_style(d.color,true),
        on_click=function()
            local s=B.snapshot()
            if s.drink==id and B.start() then M.refresh() end
        end})
    start_group:set_hidden(true)
    return {buttons=buttons,volume=volume,note_group=note_group,start_group=start_group,start=start}
end

function M.create()
    if root then return end
    root=box(airui.screen,0,0,C.WIDTH,C.HEIGHT,0xFFF8E8)
    -- JPG原始尺寸1024x608，在1024x600组件中原比例居中裁切，无JPG缩放。
    airui.image({parent=root,src="/luadb/bg_bar.jpg",x=0,y=0,w=1024,h=600})
    box(root,0,0,1024,122,paper):set_color(paper,25)
    text(root,28,18,710,23,"FRESH & HAPPY  /  每一口都开心",15,mint)
    text(root,26,49,750,49,"快乐果饮站",38,ink)
    text(root,29,102,740,24,"选个口味，装满今天的小快乐",18,muted)
    box(root,830,23,166,34,0xE3F1D9,17):set_color(0xE3F1D9,230)
    text(root,835,30,156,24,"果味满满 · 快乐加倍",16,mint,airui.TEXT_ALIGN_CENTER)
    reset_button=airui.button({parent=root,x=854,y=77,w=142,h=34,
        text="清空选择",font_size=16,style=button_style(mint,false),
        on_click=function() if B.reset() then M.refresh() end end})
    require("mascot").create(root)
    glow=box(root,COL_X+8,COL_Y+65,216,330,0xFFFFFF,32)
    glow:set_hidden(true)
    build_liquid()
    for id=1,#C.DRINKS do cards[id]=build_card(id) end
    box(root,16,572,992,25,paper,10):set_color(paper,220)
    status=text(root,28,576,966,21,"01 选择瓶身份量    02 开始灌注    03 完成后重新选择",16,muted)
    M.refresh()
end

function M.refresh()
    if not root then return end
    local s=B.snapshot()
    local changed=s.phase~=previous_phase or s.drink~=previous_drink or s.size~=previous_size
    if changed then
        for id,card in ipairs(cards) do
            local selected=s.drink==id
            local d=C.DRINKS[id]
            card.start_group:set_hidden(not selected)
            card.note_group:set_hidden(selected)
            for n,button in ipairs(card.buttons) do
                button:set_style(button_style(d.color,selected and s.size==n))
                -- 状态机拒绝忙碌时的操作，保持透明按钮视觉。
            end
            if not selected then
                card.volume:set_text("请选择份量")
                card.start:set_text("开始灌注")
            else
                card.start:set_text(s.phase=="pouring" and "正在灌注..." or
                    (s.phase=="done" and "灌注完成" or "开始灌注"))
            end
        end
        glow:set_hidden(not s.drink)
        if s.drink then
            local d=C.DRINKS[s.drink]
            glow:set_pos(COL_X+(s.drink-1)*COL_STEP+8,COL_Y+65)
            glow:set_color(d.color,10)
            fill_group:set_pos(COL_X+(s.drink-1)*COL_STEP+LIQ_X,COL_Y+LIQ_Y)
            if s.drink~=previous_drink then
                for _,band in ipairs(bands) do band:set_color(d.liquid,235) end
            end
        end
        -- reset同样由状态机处理忙碌保护。
        if s.phase=="idle" then
            status:set_text("01 选择瓶身份量    02 开始灌注    03 完成后重新选择")
        elseif s.phase=="ready" then
            status:set_text("已选："..C.DRINKS[s.drink].name.." · "..C.SIZES[s.size].name..
                "（"..C.SIZES[s.size].fraction.."），点击瓶子下方开始灌注")
        elseif s.phase=="pouring" then
            status:set_text("正在灌注 "..C.DRINKS[s.drink].name.."，瓶内液位下降中，请稍候...")
        else
            status:set_text("灌注完成，瓶内已空；即将回到首页，请重新选择")
        end
    end
    set_level(s.level)
    if s.drink then
        local caption=C.SIZES[s.size].name.." · "..C.SIZES[s.size].fraction
        if s.phase~="ready" then caption=string.format("剩余 %d%%",math.ceil(s.level/30)) end
        cards[s.drink].volume:set_text(caption)
    end
    previous_phase,previous_drink,previous_size=s.phase,s.drink,s.size
end
return M
