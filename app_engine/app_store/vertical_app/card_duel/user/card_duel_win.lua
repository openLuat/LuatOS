--[[
@module  card_duel_win
@summary 卡牌对决 320×480
@version 1.0.1
@date    2026.05.03
@author  江访
]]

local game = {}

-- ============ 数据 ============
local CARD = {
    {id="strike", name="打击", cost=1, dmg=6,  blk=0 },
    {id="defend", name="防御", cost=1, dmg=0,  blk=5 },
    {id="bash",   name="痛击", cost=2, dmg=8,  blk=0 },
    {id="block",  name="固守", cost=2, dmg=0,  blk=10},
    {id="slash",  name="挥砍", cost=1, dmg=4,  blk=4 },
    {id="heavy",  name="重击", cost=3, dmg=15, blk=0 },
}
local _card_idx = {}
for i, c in ipairs(CARD) do _card_idx[c.id] = c end

local DECK = {"strike","strike","strike","strike","strike","defend","defend","defend","defend","bash"}
local MAX_HAND = 5

local ENEMY = {
    {name="绿皮史莱姆", hp=20, atk=5,  ptn={"atk"}},
    {name="硬壳甲虫",   hp=24, atk=6,  ptn={"atk","atk","block"}},
    {name="暗影仆从",   hp=28, atk=7,  ptn={"atk","atk","block"}},
    {name="荆棘魔藤",   hp=32, atk=8,  ptn={"atk","block","atk"}},
    {name="烈焰精灵",   hp=36, atk=10, ptn={"atk","block","block"}},
    {name="冰霜术士",   hp=40, atk=11, ptn={"atk","atk","block"}},
    {name="钢铁武士",   hp=46, atk=13, ptn={"atk","block","atk"}},
    {name="暗黑祭司",   hp=52, atk=14, ptn={"block","atk","atk"}},
    {name="双头蟒蛇",   hp=58, atk=16, ptn={"atk","atk","atk"}},
    {name="熔岩巨兽",   hp=66, atk=18, ptn={"atk","block","atk"}},
    {name="深渊领主",   hp=110,atk=22, ptn={"atk","block","atk"}},
}

-- ============ 布局常量 ============
local W, H = 320, 480
local L = {
    batt_y=0,  batt_h=150,
    hand_y=154, hand_h=206,
    act_y=366,  act_h=52,
    st_y=422,   st_h=28,
    card_w=56,  card_h=100, card_gap=4, card_sel=-8,
    hp_h=14,    hp_w=300,
    f_big=20,   f_main=16,  f_sm=14,  f_tiny=14,
    pad=8,  r=3,
}

-- ============ 颜色 ============
local CL = {
    bg=0x111827, cb=0x1f2937, ca=0x4a2020, cs=0x1f3d2f, cd=0x131b28,
    hp=0xe04040, hpb=0x2a1a1a, bl=0x4090e0, eg=0xe0c050,
    ia=0xe05050, ib=0x5090e0, tw=0xd8dce6, td=0x6b7280, tg=0xe0c050,
    b1=0x2563eb, b2=0x1a7f3a, be=0x5a4a30, br=0x4a3058,
    o=0x0f1724, pc=0x1a2332, hl=0x60a0e0, sl=0x5a5a40,
}

-- ============ 工具 ============
local function shuffle(t)
    for i = #t, 2, -1 do local j = math.random(i); t[i],t[j]=t[j],t[i] end
end
local function st(l, t) if l and l.set_text then l:set_text(t or "") end end
local function sv(c, v) if c and c.set_hidden then c:set_hidden(not v) end end
local function sc(l, cl) if l and l.set_color then l:set_color(cl) end end

-- ============ 卡牌系统 ============
local function deck_init()
    local g = game
    g.draw = {}; for _,v in ipairs(DECK) do g.draw[#g.draw+1]=v end
    g.hand = {}; g.discard = {}; g.exhaust = {}
    shuffle(g.draw)
end

local function draw_cards(n)
    local g = game
    for _ = 1, n do
        if #g.hand >= MAX_HAND then break end
        if #g.draw == 0 then
            for _,v in ipairs(g.discard) do g.draw[#g.draw+1]=v end
            g.discard = {}; shuffle(g.draw)
            if #g.draw == 0 then break end
        end
        g.hand[#g.hand+1] = g.draw[#g.draw]; g.draw[#g.draw] = nil
    end
end

local function discard_hand()
    local g = game
    for _,v in ipairs(g.hand) do g.discard[#g.discard+1]=v end
    g.hand = {}; g.selected = {}
end

local function card_eff(cid)
    local c = _card_idx[cid]; if not c then return nil end
    local up = game.upgrades[cid]
    local bd, bb = 0, 0
    if up then bd, bb = up.d or 0, up.b or 0 end
    local d, bl = c.dmg+bd, c.blk+bb
    local desc = ""
    if d>0 and bl>0 then desc = "伤"..d.." 防"..bl elseif d>0 then desc = "造成"..d.."点伤害" elseif bl>0 then desc = "获得"..bl.."点格挡" end
    return {name=c.name, cost=c.cost, dmg=d, blk=bl, desc=desc}
end

sel_toggle = function(idx)
    local g = game
    local cid = g.hand[idx]; if not cid then return end
    local c = _card_idx[cid]; if not c then return end
    if g.selected[idx] then g.selected[idx] = nil
    else
        local cost = 0
        for i in pairs(g.selected) do
            local ci = _card_idx[g.hand[i]]; if ci then cost=cost+ci.cost end
        end
        if cost + c.cost <= g.player_energy then g.selected[idx] = true end
    end
    ui_refresh()
end

local function sel_any()
    for _ in pairs(game.selected) do return true end
    return false
end

sel_play = function()
    if not sel_any() then return end
    local g = game; local idxs = {}
    for i in pairs(g.selected) do idxs[#idxs+1]=i end
    table.sort(idxs, function(a,b) return a>b end)
    for _,idx in ipairs(idxs) do
        local ef = card_eff(g.hand[idx])
        if ef then
            g.player_energy = g.player_energy - ef.cost
            if ef.blk > 0 then g.player_block = g.player_block + ef.blk end
            if ef.dmg > 0 then
                local dmg = ef.dmg
                if g.enemy_block > 0 then
                    if dmg <= g.enemy_block then g.enemy_block=g.enemy_block-dmg; dmg=0
                    else dmg=dmg-g.enemy_block; g.enemy_block=0 end
                end
                g.enemy_hp = g.enemy_hp - dmg
                if g.enemy_hp<0 then g.enemy_hp=0 end
            end
            g.discard[#g.discard+1] = g.hand[idx]; table.remove(g.hand, idx)
        end
    end
    g.selected = {}; ui_refresh()
    if g.enemy_hp <= 0 then state_set("win") end
end

-- ============ 战斗系统 ============
local function enemy_calc(floor)
    if floor > 11 then floor = 11 end
    local e = ENEMY[floor]; local f = floor - 1
    return e.name, math.floor(e.hp*(1+f*0.08)), math.floor(e.atk*(1+f*0.06)), e.ptn
end

local function enemy_init()
    local name, hp, atk, ptn = enemy_calc(game.floor)
    game.enemy_name, game.enemy_max_hp, game.enemy_hp = name, hp, hp
    game.enemy_block = 0; game.enemy_atk = atk
    game.enemy_intent = ""; game.enemy_ival = 0; game.enemy_pidx = 0
    game.enemy_ptn = ptn
    local ui = game.ui; if ui.eimg then ui.eimg:set_src("/luadb/enemy"..game.floor..".png") end
end

local function combat_init()
    deck_init()
    game.player_energy = game.player_max_energy; game.player_block = 0
    enemy_init(); draw_cards(MAX_HAND); game.selected = {}
end

local function combat_check()
    if game.enemy_hp <= 0 then return "win" end
    if game.player_hp <= 0 then return "lose" end
end

-- ============ 敌人AI ============
local function enemy_intent()
    local g = game
    local ptn = g.enemy_ptn; if not ptn or #ptn == 0 then g.enemy_intent="atk"; g.enemy_ival=g.enemy_atk; return end
    g.enemy_pidx = g.enemy_pidx + 1; if g.enemy_pidx > #ptn then g.enemy_pidx = 1 end
    local it = ptn[g.enemy_pidx]; g.enemy_intent = it
    if it == "atk" then g.enemy_ival = g.enemy_atk
    elseif it == "block" then g.enemy_ival = math.floor(g.enemy_atk * 0.7)
    else g.enemy_ival = 0 end
end


local function enemy_turn()
    local g = game
    if g.state ~= "enemy_turn" then return end
    if g.enemy_hp <= 0 then state_set("win"); return end
    if g.enemy_intent == "atk" then
        local dmg = g.enemy_ival
        if g.player_block > 0 then
            if dmg <= g.player_block then g.player_block=g.player_block-dmg; dmg=0
            else dmg=dmg-g.player_block; g.player_block=0 end
        end
        g.player_hp = g.player_hp - dmg; if g.player_hp<0 then g.player_hp=0 end
    elseif g.enemy_intent == "block" then
        g.enemy_block = g.enemy_block + g.enemy_ival
    end
    ui_refresh()
    sys.timerStart(function() enemy_cb() end, 600)
end

-- ============ 状态机 ============
player_end = function()
    if game.state ~= "player_turn" then return end
    if game.enemy_hp <= 0 then state_set("win"); return end
    state_set("enemy_turn")
end

on_start = function()
    if game.state ~= "start" then return end
    game.floor = 1; game.player_hp = game.player_max_hp; game.player_block = 0
    game.gold = 0; game.upgrades = {}
    combat_init(); enemy_intent(); state_set("player_turn")
end

on_restart = function()
    local g = game
    g.floor = 1; g.player_hp = g.player_max_hp; g.player_block = 0
    g.gold = 0; g.upgrades = {}
    g.player_energy = g.player_max_energy
    g.draw = {}; g.hand = {}; g.discard = {}; g.exhaust = {}; g.selected = {}
    deck_init(); enemy_init(); draw_cards(MAX_HAND); enemy_intent(); state_set("player_turn")
end

on_close = function() if win_id then exwin.close(win_id) end end
on_menu = function() state_set("start") end

on_next = function()
    local g = game
    if g.floor >= g.max_floor then state_set("victory"); return end
    if sf(g.floor+1) then state_set("shop"); return end
    sl()
end
sf = function(f) return f==5 or f==10 or f==11 end

sl = function()
    local g = game
    if g.floor >= g.max_floor then state_set("victory"); return end
    g.floor = g.floor + 1; g.player_block = 0
    g.player_energy = g.player_max_energy
    g.draw = {}; g.hand = {}; g.discard = {}; g.exhaust = {}; g.selected = {}
    deck_init(); enemy_init(); draw_cards(MAX_HAND); enemy_intent(); state_set("player_turn")
end

enemy_cb = function()
    local r = combat_check()
    if r=="win" then state_set("win") elseif r=="lose" then state_set("lose")
    else state_set("player_turn_start") end
end

function state_set(st)
    local g = game; g.state = st
    if st == "player_turn_start" then
        g.player_energy = g.player_max_energy; g.player_block = 0; g.selected = {}
        discard_hand(); draw_cards(MAX_HAND); enemy_intent(); state_set("player_turn"); return
    end
    if st == "enemy_turn" then enemy_turn(); return end
    if     st == "start"   then page_show("start")
    elseif st == "player_turn" then page_show(nil)
    elseif st == "win"     then page_show("win")
    elseif st == "lose"    then page_show("lose")
    elseif st == "victory" then page_show("victory")
    elseif st == "shop"    then shop_refresh(); page_show("shop") end
    ui_refresh()
end

-- ============ 商店 ============
shop_refresh = function()
    local ui = game.ui; if not ui.shop_gold then return end
    local up = game.upgrades
    local al = math.floor((up["strike"] and up["strike"].d or 0)/2)
    local dl = math.floor((up["defend"] and up["defend"].b or 0)/2)
    st(ui.shop_gold, "金币 "..game.gold)
    st(ui.shop_hp, "HP "..game.player_hp.."/"..game.player_max_hp)
    st(ui.shop_atk, "攻击Lv"..al.." (15金)")
    st(ui.shop_def, "防御Lv"..dl.." (15金)")
    st(ui.shop_heal, "回复15HP (10金)")
end

shop_buy_atk = function()
    if game.gold < 15 then return end; game.gold = game.gold - 15
    for id, c in pairs(_card_idx) do
        if c.dmg > 0 then
            local u = game.upgrades[id]; if not u then u = {}; game.upgrades[id] = u end
            u.d = (u.d or 0) + 2
        end
    end
    shop_refresh()
end

shop_buy_def = function()
    if game.gold < 15 then return end; game.gold = game.gold - 15
    for id, c in pairs(_card_idx) do
        if c.blk > 0 then
            local u = game.upgrades[id]; if not u then u = {}; game.upgrades[id] = u end
            u.b = (u.b or 0) + 2
        end
    end
    shop_refresh()
end

shop_buy_heal = function()
    if game.gold < 10 then return end
    if game.player_hp >= game.player_max_hp then return end
    game.gold = game.gold - 10
    game.player_hp = math.min(game.player_hp + 15, game.player_max_hp)
    shop_refresh()
end

-- ============ UI 构建 ============
local function floor(v) return type(v)=="number" and math.floor(v) or v end
local function mk_cont(p, x, y, w, h, c, r)
    return airui.container({parent=p, x=floor(x), y=floor(y), w=floor(w), h=floor(h), color=c or CL.bg, radius=r and floor(r)})
end
local function mk_lbl(p, x, y, w, h, t, fs, c, a)
    return airui.label({parent=p, x=floor(x), y=floor(y), w=floor(w), h=floor(h), text=t or "", font_size=floor(fs or L.f_main), color=c or CL.tw, align=a or airui.TEXT_ALIGN_CENTER})
end
local function mk_btn(p, x, y, w, h, t, fs, tc, bc, oc)
    return airui.button({parent=p, x=floor(x), y=floor(y), w=floor(w), h=floor(h), text=t, font_size=floor(fs or L.f_main), style={text_color=tc or CL.tw, bg_color=bc or CL.b1, radius=floor(L.r), border_width=0}, on_click=oc})
end

-- 卡牌点击
local function s1() sel_toggle(1) end
local function s2() sel_toggle(2) end
local function s3() sel_toggle(3) end
local function s4() sel_toggle(4) end
local function s5() sel_toggle(5) end
local Q = {s1,s2,s3,s4,s5}

local function page_start()
    local ui = game.ui; local T = mk_cont
    ui.start = T(main_container,0,0,W,H,CL.pc)
    local bw = math.floor(W*0.78); local bx = math.floor((W-bw)/2)
    local by = math.floor(H*0.12); local bh = math.floor(H*0.36)
    T(ui.start,bx,by,bw,bh,CL.pc,L.r)
    mk_lbl(ui.start,bx,by+bh*.10,bw,L.f_big*1.5,"卡牌对决",L.f_big,CL.hl)
    mk_lbl(ui.start,bx,by+bh*.32,bw,L.f_main*1.2,"收集卡牌 构筑牌组",L.f_main,CL.tw)
    mk_lbl(ui.start,bx,by+bh*.55,bw,L.f_sm*3,"策略战斗 逐步推进\n击败深渊领主",L.f_sm,CL.td)
    local btn_w = math.floor(bw*.6); local btn_h = math.floor(L.act_h*.7)
    local btn_y1 = by+bh+math.floor(H*.04)
    mk_btn(ui.start,math.floor((W-btn_w)/2),btn_y1,btn_w,btn_h,"开始游戏",L.f_big,CL.tw,CL.b2,on_start)
    local btn_y2 = btn_y1+btn_h+math.floor(H*.02)
    mk_btn(ui.start,math.floor((W-btn_w)/2),btn_y2,btn_w,btn_h,"结束游戏",L.f_big,CL.tw,CL.br,on_close)
end

local function page_combat()
    local ui = game.ui; local fw = W - L.pad*2

    -- 战斗根容器，统一管理所有战斗子元素的显隐，避免AirUI真实固件渲染树重建丢失parent
    ui.combat_root = mk_cont(main_container, 0, 0, W, H, CL.bg)

    -- 战场 (敌人上/玩家下)
    ui.batt = mk_cont(ui.combat_root,0,L.batt_y,W,L.batt_h,CL.bg)
    ui.batt:set_border_color(0x1e3040,1)

    -- 敌人 (上半)
    ui.eimg = airui.image({parent=ui.batt, src="/luadb/enemy1.png", x=L.pad, y=4, w=24, h=24, opacity=255})
    ui.ename = mk_lbl(ui.batt, L.pad+28, 6, fw-30, 18, "", L.f_sm, CL.tw, airui.TEXT_ALIGN_LEFT)
    ui.ehp = airui.bar({parent=ui.batt, x=L.pad, y=30, w=fw, h=L.hp_h, value=100, bg_color=CL.hpb, indicator_color=CL.hp, radius=3})
    ui.ehpl = mk_lbl(ui.batt, L.pad, 28, fw, 16, "", L.f_sm, CL.tw)
    ui.eblk = mk_lbl(ui.batt, L.pad, 48, math.floor(fw*.5), 18, "", L.f_sm, CL.bl, airui.TEXT_ALIGN_LEFT)
    ui.eint = mk_lbl(ui.batt, math.floor(W*.5), 48, math.floor(fw*.5)-L.pad, 18, "", L.f_sm, CL.ia, airui.TEXT_ALIGN_LEFT)
    mk_cont(ui.batt, L.pad, 70, fw, 1, 0x1e3040)

    -- 玩家 (下半)
    ui.pimg = airui.image({parent=ui.batt, src="/luadb/player.png", x=L.pad, y=76, w=24, h=24, opacity=255})
    ui.pname = mk_lbl(ui.batt, L.pad+28, 78, fw-30, 18, "勇者", L.f_sm, CL.tg, airui.TEXT_ALIGN_LEFT)
    ui.php = airui.bar({parent=ui.batt, x=L.pad, y=102, w=fw, h=L.hp_h, value=100, bg_color=CL.hpb, indicator_color=CL.hp, radius=3})
    ui.phpl = mk_lbl(ui.batt, L.pad, 100, fw, 16, "", L.f_sm, CL.tw)
    ui.pen = mk_lbl(ui.batt, L.pad, 120, math.floor(fw*.5), 18, "", L.f_sm, CL.eg, airui.TEXT_ALIGN_LEFT)
    ui.pblk = mk_lbl(ui.batt, math.floor(W*.5), 120, math.floor(fw*.5)-L.pad, 18, "", L.f_sm, CL.bl, airui.TEXT_ALIGN_LEFT)

    -- 手牌 (无desc行, 4标签)
    ui.hand = mk_cont(ui.combat_root, 0, L.hand_y, W, L.hand_h, CL.bg)
    ui.cards = {}
    local tw = MAX_HAND*L.card_w + (MAX_HAND-1)*L.card_gap
    local sx = math.floor((W-tw)/2)
    local yb = math.floor((L.hand_h-L.card_h)/2)
    local lw, lx = L.card_w-8, 4
    for i = 1, MAX_HAND do
        local cx = sx + (i-1)*(L.card_w+L.card_gap)
        local slt = airui.container({parent=ui.hand, x=cx, y=yb, w=L.card_w, h=L.card_h, color=CL.cb, radius=3})
        local n  = mk_lbl(slt, lx, 4,  lw, 18, "", L.f_sm, CL.tw)
        local co = mk_lbl(slt, lx, 26, lw, 20, "", L.f_big, CL.eg)
        local dm = mk_lbl(slt, lx, 52, lw, 18, "", L.f_sm, CL.hp)
        local bk = mk_lbl(slt, lx, 74, lw, 18, "", L.f_sm, CL.bl)
        n:set_on_click(Q[i]); co:set_on_click(Q[i]); dm:set_on_click(Q[i]); bk:set_on_click(Q[i])
        ui.cards[i] = {c=slt,bx=cx,by=yb,n=n,co=co,dm=dm,bk=bk}
        sv(slt, false)
    end

    -- 动作栏 (含详情文字)
    ui.act = mk_cont(ui.combat_root, 0, L.act_y, W, L.act_h, CL.bg)
    ui.dlbl = mk_lbl(ui.act, L.pad, 2, W-L.pad*2, 16, "点击手牌选中", L.f_sm, CL.td)
    local bw2 = math.floor(W*.42); local bh2 = 26
    local bg2 = math.floor((W-bw2*2)/3)
    ui.bplay = mk_btn(ui.act, bg2, 20, bw2, bh2, "打出", L.f_main, CL.tw, CL.b1, sel_play)
    ui.bend = mk_btn(ui.act, bg2*2+bw2, 20, bw2, bh2, "结束回合", L.f_main, CL.tw, CL.be, player_end)

    -- 状态栏
    ui.st = mk_cont(ui.combat_root, 0, L.st_y, W, L.st_h, CL.bg)
    ui.fl = mk_lbl(ui.st, L.pad, 2, math.floor(W*.3), L.st_h-4, "", L.f_sm, CL.tg, airui.TEXT_ALIGN_LEFT)
    ui.pl = mk_lbl(ui.st, math.floor(W*.32), 2, math.floor(W*.34), L.st_h-4, "", L.f_sm, CL.td)
    local rw2 = math.floor(W*.15); local rh2 = math.floor(L.st_h*.7)
    local ry2 = math.floor((L.st_h-rh2)/2)
    mk_btn(ui.st, math.floor(W*.68), ry2, rw2, rh2, "重来", L.f_sm, CL.tw, CL.br, on_restart)
    mk_btn(ui.st, math.floor(W*.85), ry2, rw2, rh2, "关闭", L.f_sm, CL.td, 0x444444, on_close)
end

local function page_win()
    local ui = game.ui; local T = mk_cont
    ui.win = T(main_container,0,0,W,H,CL.o); sv(ui.win, false)
    local bw = math.floor(W*.78); local bx = math.floor((W-bw)/2)
    local bh = math.floor(H*.42); local by = math.floor(H*.15)
    T(ui.win,bx,by,bw,bh,CL.pc,L.r)
    airui.image({parent=ui.win, src="/luadb/win.png", x=math.floor((W-24)/2), y=math.floor(by+bh*.06), w=24, h=24, opacity=255})
    mk_lbl(ui.win,bx,by+bh*.22,bw,L.f_big*1.5,"战斗胜利!",L.f_big,CL.hl)
    ui.wgold = mk_lbl(ui.win,bx,by+bh*.42,bw,L.f_main*1.2,"",L.f_main,CL.tg)
    ui.wnext = mk_lbl(ui.win,bx,by+bh*.60,bw,L.f_sm*1.2,"",L.f_sm,CL.tw)
    local bw2 = math.floor(bw*.55); local bh2 = math.floor(L.act_h*.65)
    mk_btn(ui.win,math.floor((W-bw2)/2),by+bh+H*.03,bw2,bh2,"下一层",L.f_big,CL.tw,CL.b2,on_next)
    mk_lbl(ui.win,0,by+bh+H*.03+bh2+H*.03,W,L.f_sm,"HP不会自动回复",L.f_sm,CL.td)
end

local function page_lose()
    local ui = game.ui; local T = mk_cont
    ui.lose = T(main_container,0,0,W,H,CL.o); sv(ui.lose, false)
    local bw = math.floor(W*.78); local bx = math.floor((W-bw)/2)
    local bh = math.floor(H*.42); local by = math.floor(H*.15)
    T(ui.lose,bx,by,bw,bh,CL.pc,L.r)
    airui.image({parent=ui.lose, src="/luadb/lose.png", x=math.floor((W-24)/2), y=math.floor(by+bh*.06), w=24, h=24, opacity=255})
    mk_lbl(ui.lose,bx,by+bh*.22,bw,L.f_big*1.5,"战斗失败",L.f_big,CL.hp)
    ui.lfl = mk_lbl(ui.lose,bx,by+bh*.42,bw,L.f_main*1.2,"",L.f_main,CL.tw)
    ui.lgl = mk_lbl(ui.lose,bx,by+bh*.58,bw,L.f_main*1.2,"",L.f_main,CL.tg)
    ui.lhi = mk_lbl(ui.lose,bx,by+bh*.72,bw,L.f_sm*1.2,"",L.f_sm,CL.td)
    local bw2 = math.floor(bw*.55); local bh2 = math.floor(L.act_h*.65)
    mk_btn(ui.lose,math.floor((W-bw2)/2),by+bh+H*.03,bw2,bh2,"重新开始",L.f_big,CL.tw,CL.br,on_restart)
    local mby = by+bh+H*.03+bh2+H*.02
    local mbw = math.floor(bw*.4)
    mk_btn(ui.lose,math.floor((W-mbw)/2),mby,mbw,bh2,"返回主菜单",L.f_main,CL.tw,CL.b1,on_menu)
end

local function page_victory()
    local ui = game.ui; local T = mk_cont
    ui.vic = T(main_container,0,0,W,H,CL.o); sv(ui.vic, false)
    local bw = math.floor(W*.8); local bx = math.floor((W-bw)/2)
    local bh = math.floor(H*.48); local by = math.floor(H*.12)
    T(ui.vic,bx,by,bw,bh,CL.pc,L.r)
    airui.image({parent=ui.vic, src="/luadb/victory.png", x=math.floor((W-24)/2), y=math.floor(by+bh*.05), w=24, h=24, opacity=255})
    mk_lbl(ui.vic,bx,by+bh*.20,bw,L.f_big*1.5,"完全通关!",L.f_big,CL.eg)
    mk_lbl(ui.vic,bx,by+bh*.36,bw,L.f_main*1.3,"击败了深渊领主",L.f_main,CL.tw)
    ui.vhp = mk_lbl(ui.vic,bx,by+bh*.50,bw,L.f_main*1.2,"",L.f_main,CL.hp)
    ui.vgl = mk_lbl(ui.vic,bx,by+bh*.64,bw,L.f_main*1.2,"",L.f_main,CL.tg)
    mk_lbl(ui.vic,bx,by+bh*.78,bw,L.f_sm*1.2,"恭喜你征服了深渊!",L.f_sm,CL.td)
    local bw2 = math.floor(bw*.5); local bh2 = math.floor(L.act_h*.65)
    mk_btn(ui.vic,math.floor((W-bw2)/2),by+bh+H*.04,bw2,bh2,"再玩一次",L.f_big,CL.tw,CL.b2,on_restart)
end

local function page_shop()
    local ui = game.ui; local T = mk_cont
    ui.shop = T(main_container,0,0,W,H,CL.o); sv(ui.shop, false)
    local bw = math.floor(W*.84); local bx = math.floor((W-bw)/2)
    local bh = math.floor(H*.6); local by = math.floor(H*.06)
    T(ui.shop,bx,by,bw,bh,CL.pc,L.r)
    mk_lbl(ui.shop,bx,by+bh*.03,bw,L.f_big*1.3,"商店",L.f_big,CL.eg)
    ui.shop_gold = mk_lbl(ui.shop,bx,by+bh*.11,bw,L.f_main,"",L.f_main,CL.tg)
    ui.shop_hp = mk_lbl(ui.shop,bx,by+bh*.18,bw,L.f_sm,"",L.f_sm,CL.hp)
    local iw = math.floor(bw*.85); local ix = math.floor((W-iw)/2)
    local ih = math.floor(bh*.12); local ig = math.floor(bh*.04)
    local lw = iw-80; local lh = L.f_sm*2; local lo = math.floor((ih-lh)/2)
    local fs = L.f_tiny
    local y1 = by + math.floor(bh*.26)
    local box1 = T(ui.shop,ix,y1,iw,ih,0x3a3a20,L.r)
    ui.shop_atk = mk_lbl(box1,6,lo,lw,lh,"",fs,CL.tw,airui.TEXT_ALIGN_LEFT)
    airui.button({parent=box1, x=iw-72, y=math.floor(ih*.15), w=64, h=math.floor(ih*.7), text="购买", font_size=fs, style={bg_color=CL.b1, text_color=CL.tw, radius=3, border_width=0}, on_click=shop_buy_atk})
    local y2 = y1+ih+ig
    local box2 = T(ui.shop,ix,y2,iw,ih,0x203a20,L.r)
    ui.shop_def = mk_lbl(box2,6,lo,lw,lh,"",fs,CL.tw,airui.TEXT_ALIGN_LEFT)
    airui.button({parent=box2, x=iw-72, y=math.floor(ih*.15), w=64, h=math.floor(ih*.7), text="购买", font_size=fs, style={bg_color=CL.b1, text_color=CL.tw, radius=3, border_width=0}, on_click=shop_buy_def})
    local y3 = y2+ih+ig
    local box3 = T(ui.shop,ix,y3,iw,ih,0x203a3a,L.r)
    ui.shop_heal = mk_lbl(box3,6,lo,lw,lh,"",fs,CL.tw,airui.TEXT_ALIGN_LEFT)
    airui.button({parent=box3, x=iw-72, y=math.floor(ih*.15), w=64, h=math.floor(ih*.7), text="购买", font_size=fs, style={bg_color=CL.b2, text_color=CL.tw, radius=3, border_width=0}, on_click=shop_buy_heal})
    local ly = y3+ih+math.floor(ig*1.5)
    local lw2 = math.floor(bw*.5)
    mk_btn(ui.shop,math.floor((W-lw2)/2),ly,lw2,math.floor(L.act_h*.65),"离开商店",L.f_main,CL.tw,CL.b2,sl)
end

function page_show(name)
    local ui = game.ui
    sv(ui.combat_root, name==nil)
    sv(ui.start, name=="start"); sv(ui.win, name=="win")
    sv(ui.lose, name=="lose"); sv(ui.vic, name=="victory"); sv(ui.shop, name=="shop")
    if name=="win" then game.gold = game.gold + game.floor*10 end
end

function ui_build()
    game.ui = {}
    page_start(); page_combat(); page_win(); page_lose(); page_victory(); page_shop()
    page_show("start")
end

-- ============ UI刷新 ============
local function ui_card(i, cid, sel, playable)
    local s = game.ui.cards[i]; if not s then return end
    if not cid then sv(s.c, false); return end
    local ef = card_eff(cid); if not ef then sv(s.c, false); return end
    sv(s.c, true)
    if not playable and not sel then
        sc(s.n,CL.td); sc(s.co,CL.td); sc(s.dm,CL.td); sc(s.bk,CL.td)
    else
        sc(s.n,CL.tw); sc(s.co,CL.eg); sc(s.dm,CL.hp); sc(s.bk,CL.bl)
    end
    if sel then s.c:set_color(CL.sl); s.c:set_border_color(CL.eg, 2)
    else
        local cc = CL.cb
        if ef.dmg>0 and ef.blk==0 then cc=CL.ca elseif ef.blk>0 and ef.dmg==0 then cc=CL.cs elseif ef.dmg>0 then cc=0x4a305a end
        s.c:set_color(cc); s.c:set_border_color(0, 0)
    end
    st(s.n, ef.name); st(s.co, ef.cost.."E")
    st(s.dm, ef.dmg>0 and "伤"..ef.dmg or "")
    st(s.bk, ef.blk>0 and "防"..ef.blk or "")
end

local function ui_pos()
    local n = #game.hand; if n==0 then return end
    local tw = n*L.card_w + (n-1)*L.card_gap
    local sx = math.floor((W-tw)/2)
    for i=1,n do
        local s = game.ui.cards[i]
        if s then
            local x = sx+(i-1)*(L.card_w+L.card_gap)
            local y = s.by + (game.selected[i] and L.card_sel or 0)
            s.c:set_pos(x, y)
        end
    end
end

local function ui_hand()
    ui_pos()
    for i=1,MAX_HAND do
        local cid = game.hand[i]
        local sel = game.selected[i]
        local ok = true
        if cid and not sel then
            local c = _card_idx[cid]
            if c then
                local cost = 0
                for j in pairs(game.selected) do
                    local cj = _card_idx[game.hand[j]]; if cj then cost=cost+cj.cost end
                end
                ok = (cost + c.cost) <= game.player_energy
            end
        end
        ui_card(i, cid, sel, ok)
    end
end

local function ui_enemy()
    local ui = game.ui; if not ui.ename then return end
    st(ui.ename, game.enemy_name); st(ui.ehpl, "HP "..game.enemy_hp.."/"..game.enemy_max_hp)
    if ui.ehp then ui.ehp:set_value(math.floor(game.enemy_hp/game.enemy_max_hp*100), false) end
    st(ui.eblk, game.enemy_block>0 and "格挡"..game.enemy_block or "")
    local txt=""; if game.enemy_intent=="atk" then txt="下回合 攻击"..game.enemy_ival; ui.eint:set_color(CL.ia)
    elseif game.enemy_intent=="block" then txt="下回合 防御"..game.enemy_ival; ui.eint:set_color(CL.ib) end
    st(ui.eint, txt)
end

local function ui_player()
    local ui = game.ui; if not ui.phpl then return end
    st(ui.phpl, "HP "..game.player_hp.."/"..game.player_max_hp)
    if ui.php then ui.php:set_value(math.floor(game.player_hp/game.player_max_hp*100), false) end
    st(ui.pen, "能量 "..game.player_energy.."/"..game.player_max_energy)
    st(ui.pblk, game.player_block>0 and "格挡"..game.player_block or "")
end

local function ui_act()
    local ui = game.ui; if not ui.bplay then return end
    if game.state == "player_turn" then
        sv(ui.bplay, sel_any()); sv(ui.bend, true)
    elseif game.state == "enemy_turn" then
        sv(ui.bplay, false); sv(ui.bend, false)
    else
        sv(ui.bplay, false); sv(ui.bend, false)
    end
end

function ui_refresh()
    if game.state == "start" or game.state == "shop" then return end
    ui_enemy(); ui_player(); ui_hand()
    local ui = game.ui
    if ui.dlbl then
        local s = {}; for i in pairs(game.selected) do s[#s+1]=i end
        if #s>0 then
            local cs = 0; for _,i in ipairs(s) do local c=_card_idx[game.hand[i]]; if c then cs=cs+c.cost end end
            st(ui.dlbl, "已选"..#s.."张 费用"..cs)
        else st(ui.dlbl, "点击手牌选中并打出") end
    end
    ui_act()
    st(ui.fl, "楼层"..game.floor.."/"..game.max_floor)
    st(ui.pl, "牌库"..#game.draw.." 弃"..#game.discard)
    if game.state=="win" and ui.wnext then
        local nf = game.floor+1
        st(ui.wnext, nf>game.max_floor and "最终Boss已击败!" or "下一层: "..enemy_calc(nf))
        st(ui.wgold, "获得金币 +"..(game.floor*10))
    end
    if game.state=="lose" and ui.lfl then
        st(ui.lfl, "到达楼层: "..game.floor); st(ui.lgl, "金币: "..game.gold)
        st(ui.lhi, "你倒在了"..(game.enemy_name or "").."面前")
    end
    if game.state=="victory" and ui.vhp then
        st(ui.vhp, "剩余HP: "..game.player_hp.."/"..game.player_max_hp)
        st(ui.vgl, "金币: "..game.gold)
    end
end

-- ============ 主循环 & 生命周期 ============
local function tick()
    if game.state ~= "player_turn" and game.state ~= "enemy_turn" then return end
end

function on_create()
    math.randomseed(os.time())
    main_container = airui.container({parent=airui.screen, x=0, y=0, w=W, h=H, color=CL.bg})
    game = {
        state="start",player_hp=80,player_max_hp=80,player_block=0,
        player_energy=3,player_max_energy=3,floor=1,max_floor=11,gold=0,
        draw={},hand={},discard={},exhaust={},selected={},upgrades={},
        enemy_hp=0,enemy_max_hp=0,enemy_block=0,
        enemy_intent="",enemy_ival=0,enemy_name="",enemy_atk=0,enemy_pidx=0,enemy_ptn={},
        ui={},
    }
    ui_build()
    game_timer_id = sys.timerLoopStart(tick, 50)
end

function on_destroy()
    if game_timer_id then sys.timerStop(game_timer_id); game_timer_id=nil end
    if main_container then main_container:destroy(); main_container=nil end
    win_id=nil
end
function on_get_focus() end
function on_lose_focus() end

-- ============ 入口 ============
local function open()
    win_id = exwin.open({on_create=on_create, on_destroy=on_destroy, on_get_focus=on_get_focus, on_lose_focus=on_lose_focus})
end
sys.subscribe("OPEN_CARD_DUEL_WIN", open)
