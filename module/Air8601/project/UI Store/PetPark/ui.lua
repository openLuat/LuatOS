-- 固定8个精灵，按各自Y活动带由远到近创建。不同活动带不交叉，无需动态重排。
-- 共享已导出的左右PNG；移动不换源，只有跑姿/状态/朝向变化才set_src。
local C=require "config"
local scene=require "scene"
local hitmask=require "hitmask"
local M={}
local root
local read_elapsed
local sprites={}
local count_buttons={}
local count_label,quality_label,previous_count,previous_quality
local SCALE=C.PET_SCALE or 1
local function round(n) return math.floor(n+0.5) end
local GROUP_W,GROUP_H=round(96*SCALE),round(96*SCALE)
local ANCHOR_X,ANCHOR_Y=48*SCALE,76*SCALE
local IMAGE_X,IMAGE_W=round(8*SCALE),round(80*SCALE)
local PANEL_X,PANEL_Y,PANEL_W,PANEL_H=22,18,420,125
local function count_style(selected)
    return {bg_color=selected and 0x507D50 or 0xFFFDF3,bg_opa=255,
        text_color=selected and 0xFFFFFF or 0x385F43,border_color=0x8DAA80,
        border_width=1,radius=8,pad=0,pressed_bg_color=0x507D50,
        pressed_text_color=0xFFFFFF}
end
local function image_path(p)
    local pose=p.frame==0 and "idle" or "run"..p.frame
    local prefix=p.quality=="high" and p.frame>0 and "hq_" or ""
    return "/luadb/"..prefix..p.kind..p.variant.."_"..p.direction.."_"..pose..".png"
end

-- 以已提交到屏幕的姿态命中，透明像素穿透；由前景向后景寻找第一只。
function M.pick(x,y)
    if type(x)~="number" or type(y)~="number" or x~=x or y~=y
        or x<0 or y<0 or x>=C.WIDTH or y>=C.HEIGHT then return nil end
    if x>=PANEL_X and x<PANEL_X+PANEL_W and y>=PANEL_Y and y<PANEL_Y+PANEL_H then
        return nil -- 数量面板上的按下不会点到背后的动物
    end
    for i=scene.count(),1,-1 do
        local s=sprites[i]
        if s and not s.hidden then
            local scale=s.zoom/256
            local left=s.x+IMAGE_X+(IMAGE_W-64*scale)/2
            local top=s.y+s.image_y+(IMAGE_W-64*scale)/2
            local sx=math.floor((x-left)/scale)
            local sy=math.floor((y-top)/scale)
            if hitmask.hit(s.path,sx,sy) then return scene.pets()[i].id end
        end
    end
    return nil
end

function M.set_count(count)
    if not root then return false end
    if not scene.set_count(count,read_elapsed()) then return false end
    M.refresh()
    log.info("petpark","active count",scene.count(),"quality",scene.quality())
    return true
end

local function on_touch(state,x,y)
    if state~=airui.TP_DOWN then return end
    local id=M.pick(x,y)
    if id and scene.trigger_run(id,read_elapsed()) then
        M.refresh()
        log.info("petpark","tap run",id)
    end
end

function M.create(now_elapsed)
    if root then return false end
    read_elapsed=now_elapsed or require("animation").elapsed
    assert(type(read_elapsed)=="function","pet touch requires the animation clock")
    assert(type(airui.touch_subscribe)=="function" and airui.TP_DOWN~=nil,
        "firmware requires AirUI touch_subscribe/TP_DOWN")
    root=airui.container({parent=airui.screen,x=0,y=0,w=C.WIDTH,h=C.HEIGHT,
        color=0xCFE9AF,radius=0,border_width=0})
    airui.image({parent=root,x=0,y=0,w=1024,h=600,src="/luadb/park.jpg"})
    for i,p in ipairs(scene.pets()) do
        local group=airui.container({parent=root,x=round(p.x-ANCHOR_X),y=round(p.y-ANCHOR_Y),
            w=GROUP_W,h=GROUP_H,radius=0,border_width=0})
        local shadow=airui.container({parent=group,x=round(31*SCALE),y=round(74*SCALE),
            w=round(34*SCALE),h=round(5*SCALE),
            color=0x395E36,radius=round(3*SCALE),border_width=0})
        shadow:set_color(0x395E36,45)
        local base_y=SCALE*(8+67-round(40+22*p.zoom/256))
        local image=airui.image({parent=group,x=IMAGE_X,y=round(base_y),w=IMAGE_W,h=IMAGE_W,
            src=image_path(p),zoom=p.zoom*SCALE})
        sprites[i]={group=group,image=image,base_y=base_y,zoom=p.zoom*SCALE}
    end
    -- 控制面板最后创建，保持在动物上方；只在数量变化时改选中样式。
    local badge=airui.container({parent=root,x=PANEL_X,y=PANEL_Y,w=PANEL_W,h=PANEL_H,
        color=0xFFFDF3,radius=20,border_width=0})
    badge:set_color(0xFFFDF3,235)
    airui.label({parent=badge,x=16,y=9,w=246,h=36,text="猫狗公园",font_size=29,
        color=0x385F43,align=airui.TEXT_ALIGN_LEFT})
    quality_label=airui.label({parent=badge,x=17,y=49,w=380,h=22,text="",font_size=16,
        color=0x66826B,align=airui.TEXT_ALIGN_LEFT})
    count_label=airui.label({parent=badge,x=282,y=17,w=120,h=25,text="",font_size=17,
        color=0x507D50,align=airui.TEXT_ALIGN_RIGHT})
    airui.label({parent=badge,x=17,y=90,w=88,h=25,text="宠物数量",font_size=17,
        color=0x385F43,align=airui.TEXT_ALIGN_LEFT})
    for n=1,#C.PETS do
        local count=n
        count_buttons[n]=airui.button({parent=badge,x=112+(n-1)*36,y=86,w=32,h=30,
            text=tostring(n),font_size=18,style=count_style(false),
            on_click=function() M.set_count(count) end})
    end
    M.refresh()
    airui.touch_subscribe(on_touch) -- 只注册一次；按下立即触发，HOLD/UP不重复触发
    return true
end

function M.refresh()
    if not root then return end
    local active=scene.count()
    local quality=scene.quality()
    if quality~=previous_quality then
        quality_label:set_text(quality=="high" and "细腻动效 · 点点宠物就开跑" or
            "轻量动效 · 点点宠物就开跑")
        previous_quality=quality
    end
    if active~=previous_count then
        for n,button in ipairs(count_buttons) do button:set_style(count_style(n==active)) end
        count_label:set_text("当前 "..active.." 只")
        previous_count=active
    end
    for i,p in ipairs(scene.pets()) do
        local s=sprites[i]
        local hidden=i>active
        if s.hidden~=hidden then s.group:set_hidden(hidden);s.hidden=hidden end
        if not hidden then
            local x,y=round(p.x-ANCHOR_X),round(p.y-ANCHOR_Y)
            if x~=s.x or y~=s.y then s.group:set_pos(x,y);s.x,s.y=x,y end
            local image_y=round(s.base_y+p.bob*SCALE)
            if image_y~=s.image_y then s.image:set_pos(IMAGE_X,image_y);s.image_y=image_y end
            local path=image_path(p)
            if path~=s.path then s.image:set_src(path);s.path=path end
        end
    end
end
return M
