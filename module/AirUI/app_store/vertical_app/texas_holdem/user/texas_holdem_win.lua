--[[
@module  texas_holdem_win
@summary 德州扑克（人机对战，AirUI）
@version 1.0
]]

-- exapp 沙箱里包装后的 exwin 挂在 _ENV（my_env）上；rawget(_G,"exwin") 会落到全局表，
-- 误用裸 require("exwin") 时关闭窗口不会走沙箱计数，无法 exapp.close，再次打开会报 app already running。
local exwin = exwin
if not exwin then
    exwin = require "exwin"
end

local function ensure_airui()
    if not airui or not airui.init then
        return false
    end
    if type(exapp) == "table" then
        return true
    end
    local bsp = (rtos and rtos.bsp and rtos.bsp()) or ""
    bsp = tostring(bsp)
    if bsp:upper():find("PC", 1, true) then
        return airui.init(480, 800, airui.COLOR_FORMAT_ARGB8888)
    end
    local w, h = 480, 800
    if lcd and lcd.getSize then
        w, h = lcd.getSize()
    end
    return airui.init(w, h)
end

local win_id = nil
local main_container = nil
local game_area = nil

local status_label = nil
local pot_label = nil
local human_chips_label = nil
local ai_chips_label = nil
local phase_label = nil

-- 牌面：{ img = airui.image, lbl = airui.label }，有 PNG 时显示图，否则用 lbl 文本
local community_slots = {}
local human_hole_slots = {}
local ai_hole_slots = {}

local btn_fold = nil
local btn_call = nil
local btn_raise = nil

local HUMAN = 1
local AI = 2

local human_chips = 2000
local ai_chips = 2000
local pot = 0
local SB, BB = 10, 20

local deck = {}
local human_hole = {}
local ai_hole = {}
local board = { nil, nil, nil, nil, nil }

local human_folded = false
local ai_folded = false
local street = "preflop"

local human_in_round = 0
local ai_in_round = 0
local round_high = 0
local human_to_act = true

local human_is_sb = true

local function init_random_seed()
    math.randomseed((os.time and os.time()) or 12345)
    for _ = 1, 5 do
        math.random()
    end
end

local function new_deck()
    local d = {}
    for s = 0, 3 do
        for r = 2, 14 do
            table.insert(d, { r = r, s = s })
        end
    end
    return d
end

local function shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
end

local function card_text(c)
    if not c then
        return ""
    end
    local rank
    if c.r == 14 then
        rank = "A"
    elseif c.r == 13 then
        rank = "K"
    elseif c.r == 12 then
        rank = "Q"
    elseif c.r == 11 then
        rank = "J"
    elseif c.r == 10 then
        rank = "10"
    else
        rank = tostring(c.r)
    end
    local suit = ({ "♣", "♦", "♥", "♠" })[c.s + 1]
    return rank .. suit
end

local function card_color(c)
    if not c then
        return 0xFFFFFF
    end
    if c.s == 1 or c.s == 2 then
        return 0xFF5555
    end
    return 0xEEEEEE
end

-- 纸牌 PNG：Luatools/真机常用 /luadb/cards/xxx；LuatOS PC 扫描工程目录时非 lua 文件只以「文件名」进 luadb，路径为 /luadb/xxx
local CARD_W, CARD_H = 56, 78

local suit_keys = { "c", "d", "h", "s" }

local function card_rank_key(r)
    if r == 14 then
        return "a"
    elseif r == 13 then
        return "k"
    elseif r == 12 then
        return "q"
    elseif r == 11 then
        return "j"
    elseif r == 10 then
        return "10"
    else
        return tostring(r)
    end
end

local function card_face_basename(c)
    if not c then
        return nil
    end
    return card_rank_key(c.r) .. suit_keys[c.s + 1] .. ".png"
end

local function card_rank_long_key(r)
    if r == 14 then
        return "A"
    elseif r == 13 then
        return "K"
    elseif r == 12 then
        return "Q"
    elseif r == 11 then
        return "J"
    else
        return tostring(r)
    end
end

local function card_face_long_basename(c)
    if not c then
        return nil
    end
    local suit_long = ({ "Clubs", "Diamonds", "Hearts", "Spades" })[c.s + 1]
    return "card" .. suit_long .. card_rank_long_key(c.r) .. ".png"
end

local function paths_card_face(c)
    local b1 = card_face_basename(c)
    local b2 = card_face_long_basename(c)
    if not b1 then
        return {}
    end
    -- 资源统一放在 app_dir/res/ 下，对应脚本里的 /luadb/xxx
    return {
        "/luadb/" .. b1,
        "/luadb/" .. b2,
    }
end

local function paths_card_back()
    return {
        "/luadb/back.png",
    }
end

local function paths_card_empty()
    return {
        "/luadb/card_empty.png",
    }
end

local function file_exists(path)
    if not path or path == "" then
        return false
    end
    if io and io.exists then
        return io.exists(path)
    end
    return false
end

local function first_existing_path(paths)
    for _, p in ipairs(paths) do
        if file_exists(p) then
            return p
        end
    end
    return nil
end

local card_path_cache = {}
local function resolve_card_path(cache_key, paths)
    if card_path_cache[cache_key] ~= nil then
        return card_path_cache[cache_key]
    end
    local p = first_existing_path(paths)
    card_path_cache[cache_key] = p or false
    return p
end

local function safe_img_src(img, paths)
    if not img then
        return false
    end
    local path = resolve_card_path(table.concat(paths, "|"), paths)
    if not path then
        return false
    end
    local ok = pcall(function()
        img:set_src(path)
    end)
    return ok
end

-- 卡牌图片只显示中间区域，通常是因为 LVGL Image 会按对象的 w/h 做裁剪，
-- 但图片原始尺寸与 w/h 不一致。这里从 PNG 头部读取宽高，计算一个“塞进卡槽”的缩放 zoom。
local CARD_ZOOM = 256
local function read_png_wh(path)
    if not path or not path:lower():match("%.png$") then
        return nil, nil
    end
    if not io or not io.open then
        return nil, nil
    end
    local fd = io.open(path, "rb")
    if not fd then
        return nil, nil
    end
    local data = fd:read(24)
    fd:close()
    if not data or #data < 24 then
        return nil, nil
    end
    -- PNG: IHDR 后 8 字节里存 width/height（big-endian）
    local b1 = string.byte(data, 17) -- width msb
    local b2 = string.byte(data, 18)
    local b3 = string.byte(data, 19)
    local b4 = string.byte(data, 20) -- width lsb
    local w = b1 * 16777216 + b2 * 65536 + b3 * 256 + b4

    b1 = string.byte(data, 21) -- height msb
    b2 = string.byte(data, 22)
    b3 = string.byte(data, 23)
    b4 = string.byte(data, 24) -- height lsb
    local h = b1 * 16777216 + b2 * 65536 + b3 * 256 + b4
    if w <= 0 or h <= 0 then
        return nil, nil
    end
    return w, h
end

local function compute_card_zoom()
    -- 兜底：你给的牌面统一尺寸（避免读取 PNG 失败时 zoom 退回 256）
    local fallback_w, fallback_h = 140, 190
    local fallback_zoom = math.floor(math.min(CARD_W / fallback_w, CARD_H / fallback_h) * 256)
    if fallback_zoom < 64 then fallback_zoom = 64 end
    if fallback_zoom > 512 then fallback_zoom = 512 end

    local probe_paths = {
        "/luadb/2c.png",
        "/luadb/back.png",
        "/luadb/10h.png",
    }
    local p = first_existing_path(probe_paths)
    if not p then
        return fallback_zoom
    end
    local w, h = read_png_wh(p)
    if not w or not h then
        return fallback_zoom
    end
    local zoom = math.floor(math.min(CARD_W / w, CARD_H / h) * 256)
    if zoom < 64 then zoom = 64 end
    if zoom > 512 then zoom = 512 end
    return zoom
end

local function set_card_slot(slot, c, mode)
    if not slot or not slot.img or not slot.lbl then
        return
    end
    mode = mode or "face"
    local img, lbl = slot.img, slot.lbl
    if mode == "empty" then
        if safe_img_src(img, paths_card_empty()) then
            img:set_opacity(255)
            lbl:set_text("")
        else
            img:set_opacity(0)
            lbl:set_text("--")
            lbl:set_color(0x888888)
        end
        return
    end
    if mode == "back" then
        if safe_img_src(img, paths_card_back()) then
            img:set_opacity(255)
            lbl:set_text("")
        else
            img:set_opacity(0)
            lbl:set_text("?")
            lbl:set_color(0x888888)
        end
        return
    end
    if c then
        if safe_img_src(img, paths_card_face(c)) then
            img:set_opacity(255)
            lbl:set_text("")
        else
            img:set_opacity(0)
            lbl:set_text(card_text(c))
            lbl:set_color(card_color(c))
        end
    end
end

local function cmp_eval(a, b)
    for i = 1, 6 do
        if a[i] ~= b[i] then
            return a[i] > b[i]
        end
    end
    return false
end

local function eval5(cards)
    local r = {}
    for i = 1, 5 do
        r[i] = cards[i].r
    end
    table.sort(r, function(x, y)
        return x > y
    end)

    local flush = true
    local s0 = cards[1].s
    for i = 2, 5 do
        if cards[i].s ~= s0 then
            flush = false
            break
        end
    end

    local uniq = {}
    local seen = {}
    for _, v in ipairs(r) do
        if not seen[v] then
            seen[v] = true
            table.insert(uniq, v)
        end
    end
    table.sort(uniq, function(a, b)
        return a > b
    end)

    local str_hi = nil
    if #uniq == 5 then
        if uniq[1] - uniq[5] == 4 then
            str_hi = uniq[1]
        end
        if uniq[1] == 14 and uniq[2] == 5 and uniq[3] == 4 and uniq[4] == 3 and uniq[5] == 2 then
            str_hi = 5
        end
    end

    if flush and str_hi then
        return { 9, str_hi, 0, 0, 0, 0 }
    end

    local counts = {}
    for _, v in ipairs(r) do
        counts[v] = (counts[v] or 0) + 1
    end

    local four, trip, pair_ranks = nil, nil, {}
    for k, v in pairs(counts) do
        if v == 4 then
            four = k
        elseif v == 3 then
            trip = k
        elseif v == 2 then
            table.insert(pair_ranks, k)
        end
    end

    if four then
        local kicker = 0
        for i = 1, 5 do
            if r[i] ~= four then
                kicker = r[i]
                break
            end
        end
        return { 8, four, kicker, 0, 0, 0 }
    end

    if trip and #pair_ranks >= 1 then
        table.sort(pair_ranks, function(a, b)
            return a > b
        end)
        return { 7, trip, pair_ranks[1], 0, 0, 0 }
    end

    if flush then
        return { 6, r[1], r[2], r[3], r[4], r[5] }
    end

    if str_hi then
        return { 5, str_hi, 0, 0, 0, 0 }
    end

    if trip then
        local kick = {}
        for i = 1, 5 do
            if r[i] ~= trip then
                table.insert(kick, r[i])
            end
        end
        table.sort(kick, function(a, b)
            return a > b
        end)
        return { 4, trip, kick[1] or 0, kick[2] or 0, 0, 0 }
    end

    if #pair_ranks >= 2 then
        table.sort(pair_ranks, function(a, b)
            return a > b
        end)
        local kicker = 0
        for i = 1, 5 do
            local skip = false
            for _, p in ipairs(pair_ranks) do
                if r[i] == p then
                    skip = true
                    break
                end
            end
            if not skip then
                kicker = r[i]
                break
            end
        end
        return { 3, pair_ranks[1], pair_ranks[2], kicker, 0, 0 }
    end

    if #pair_ranks == 1 then
        local p = pair_ranks[1]
        local kick = {}
        for i = 1, 5 do
            if r[i] ~= p then
                table.insert(kick, r[i])
            end
        end
        table.sort(kick, function(a, b)
            return a > b
        end)
        return { 2, p, kick[1] or 0, kick[2] or 0, kick[3] or 0, 0 }
    end

    return { 1, r[1], r[2], r[3], r[4], r[5] }
end

local function best_of_7(all7)
    local best = nil
    for i = 1, 6 do
        for j = i + 1, 7 do
            local five = {}
            for k = 1, 7 do
                if k ~= i and k ~= j then
                    table.insert(five, all7[k])
                end
            end
            local e = eval5(five)
            if not best or cmp_eval(e, best) then
                best = e
            end
        end
    end
    return best
end

local function hand_rank_name(e)
    local t = e[1]
    if t == 9 then
        return "同花顺"
    elseif t == 8 then
        return "四条"
    elseif t == 7 then
        return "葫芦"
    elseif t == 6 then
        return "同花"
    elseif t == 5 then
        return "顺子"
    elseif t == 4 then
        return "三条"
    elseif t == 3 then
        return "两对"
    elseif t == 2 then
        return "一对"
    else
        return "高牌"
    end
end

local function best_two_hole_vs_board(h1, h2, brd)
    local cards = { h1, h2 }
    for i = 1, 5 do
        if brd[i] then
            table.insert(cards, brd[i])
        end
    end
    local n = #cards
    if n == 5 then
        return eval5(cards)
    end
    if n == 6 then
        local best = nil
        for i = 1, 6 do
            local five = {}
            for j = 1, 6 do
                if j ~= i then
                    table.insert(five, cards[j])
                end
            end
            local e = eval5(five)
            if not best or cmp_eval(e, best) then
                best = e
            end
        end
        return best
    end
    if n == 7 then
        return best_of_7(cards)
    end
    if n == 2 then
        if h1.r == h2.r then
            return { 2, h1.r, 0, 0, 0, 0 }
        end
        return { 1, math.max(h1.r, h2.r), math.min(h1.r, h2.r), 0, 0, 0 }
    end
    return { 1, 2, 0, 0, 0, 0 }
end

local function strength_for_ai()
    local eh = best_two_hole_vs_board(human_hole[1], human_hole[2], board)
    local ea = best_two_hole_vs_board(ai_hole[1], ai_hole[2], board)
    if cmp_eval(ea, eh) then
        return 0.75
    elseif cmp_eval(eh, ea) then
        return 0.35
    else
        return 0.5
    end
end

local function can_start_hand()
    return human_chips > BB and ai_chips > BB
end

local function reset_round_bets()
    human_in_round = 0
    ai_in_round = 0
    round_high = 0
end

local function post_blinds()
    reset_round_bets()
    local sb_amt, bb_amt
    if human_is_sb then
        sb_amt = math.min(SB, human_chips)
        bb_amt = math.min(BB, ai_chips)
        human_chips = human_chips - sb_amt
        ai_chips = ai_chips - bb_amt
        human_in_round = sb_amt
        ai_in_round = bb_amt
    else
        sb_amt = math.min(SB, ai_chips)
        bb_amt = math.min(BB, human_chips)
        ai_chips = ai_chips - sb_amt
        human_chips = human_chips - bb_amt
        ai_in_round = sb_amt
        human_in_round = bb_amt
    end
    pot = pot + sb_amt + bb_amt
    round_high = math.max(human_in_round, ai_in_round)
end

local function human_call_cost()
    return math.max(0, round_high - human_in_round)
end

local function ai_call_cost()
    return math.max(0, round_high - ai_in_round)
end

local function refresh_chips_ui()
    if human_chips_label then
        human_chips_label:set_text("你: " .. tostring(human_chips))
    end
    if ai_chips_label then
        ai_chips_label:set_text("电脑: " .. tostring(ai_chips))
    end
    if pot_label then
        pot_label:set_text("底池: " .. tostring(pot))
    end
end

local function set_status(text)
    if status_label then
        status_label:set_text(text)
    end
end

local function set_phase(text)
    if phase_label then
        phase_label:set_text(text)
    end
end

local function update_community_ui()
    for i = 1, 5 do
        local slot = community_slots[i]
        if slot then
            local c = board[i]
            if c then
                set_card_slot(slot, c, "face")
            else
                set_card_slot(slot, nil, "empty")
            end
        end
    end
end

local function update_hole_ui()
    if human_hole_slots[1] then
        set_card_slot(human_hole_slots[1], human_hole[1], "face")
        set_card_slot(human_hole_slots[2], human_hole[2], "face")
    end
    if ai_hole_slots[1] then
        if street == "showdown" or human_folded then
            set_card_slot(ai_hole_slots[1], ai_hole[1], "face")
            set_card_slot(ai_hole_slots[2], ai_hole[2], "face")
        else
            set_card_slot(ai_hole_slots[1], nil, "back")
            set_card_slot(ai_hole_slots[2], nil, "back")
        end
    end
end

local function end_betting_round()
    human_in_round = 0
    ai_in_round = 0
    round_high = 0
end

local function showdown_or_ai()
    if human_folded then
        set_status("你弃牌，电脑赢")
        ai_chips = ai_chips + pot
        pot = 0
        street = "end"
        refresh_chips_ui()
        return
    end
    if ai_folded then
        set_status("电脑弃牌，你赢")
        human_chips = human_chips + pot
        pot = 0
        street = "end"
        refresh_chips_ui()
        return
    end

    local allh = { human_hole[1], human_hole[2], board[1], board[2], board[3], board[4], board[5] }
    local alla = { ai_hole[1], ai_hole[2], board[1], board[2], board[3], board[4], board[5] }
    local eh = best_of_7(allh)
    local ea = best_of_7(alla)
    street = "showdown"
    update_hole_ui()
    if cmp_eval(eh, ea) then
        set_status("你赢: " .. hand_rank_name(eh))
        human_chips = human_chips + pot
    elseif cmp_eval(ea, eh) then
        set_status("电脑赢: " .. hand_rank_name(ea))
        ai_chips = ai_chips + pot
    else
        set_status("平局: " .. hand_rank_name(eh))
        human_chips = human_chips + math.floor(pot / 2)
        ai_chips = ai_chips + pot - math.floor(pot / 2)
    end
    pot = 0
    street = "end"
    refresh_chips_ui()
end

local function deal_flop()
    table.remove(deck, 1)
    board[1], board[2], board[3] = deck[1], deck[2], deck[3]
    table.remove(deck, 1)
    table.remove(deck, 1)
    table.remove(deck, 1)
    street = "flop"
    reset_round_bets()
    set_phase("翻牌圈")
end

local function deal_turn()
    table.remove(deck, 1)
    board[4] = deck[1]
    table.remove(deck, 1)
    street = "turn"
    reset_round_bets()
    set_phase("转牌圈")
end

local function deal_river()
    table.remove(deck, 1)
    board[5] = deck[1]
    table.remove(deck, 1)
    street = "river"
    reset_round_bets()
    set_phase("河牌圈")
end

local function advance_after_both_matched()
    end_betting_round()
    if street == "preflop" then
        deal_flop()
    elseif street == "flop" then
        deal_turn()
    elseif street == "turn" then
        deal_river()
    elseif street == "river" then
        showdown_or_ai()
    end
    update_community_ui()
    human_to_act = true
end

local function try_ai_response()
    if human_to_act then
        return
    end
    if ai_folded or human_folded then
        return
    end
    if street == "end" then
        return
    end

    local cost = ai_call_cost()
    local strength = strength_for_ai()
    local roll = math.random()

    if cost == 0 then
        if roll < 0.18 + strength * 0.12 then
            local bet = BB
            if bet > ai_chips then
                bet = ai_chips
            end
            if bet <= 0 then
                set_status("电脑过牌")
                if human_in_round == ai_in_round then
                    advance_after_both_matched()
                else
                    human_to_act = true
                end
                return
            end
            ai_chips = ai_chips - bet
            ai_in_round = ai_in_round + bet
            pot = pot + bet
            round_high = math.max(round_high, ai_in_round)
            set_status("电脑下注 " .. tostring(bet))
            refresh_chips_ui()
            human_to_act = true
            return
        end
        set_status("电脑过牌")
        if human_in_round == ai_in_round then
            advance_after_both_matched()
        else
            human_to_act = true
        end
        return
    end

    if cost > ai_chips then
        ai_folded = true
        set_status("电脑弃牌（筹码不足）")
        showdown_or_ai()
        return
    end

    local fold_thresh = 0.5 - strength * 0.35
    if roll < fold_thresh and cost >= BB then
        ai_folded = true
        set_status("电脑弃牌")
        showdown_or_ai()
        return
    end

    ai_chips = ai_chips - cost
    ai_in_round = ai_in_round + cost
    pot = pot + cost
    set_status("电脑跟注 " .. tostring(cost))
    refresh_chips_ui()

    if human_in_round == ai_in_round then
        advance_after_both_matched()
    else
        human_to_act = true
    end
end

local function on_human_fold()
    if not human_to_act or street == "end" or street == "showdown" then
        return
    end
    human_folded = true
    human_to_act = false
    set_status("你弃牌")
    showdown_or_ai()
end

local function on_human_call()
    if not human_to_act or street == "end" or street == "showdown" then
        return
    end
    local cost = human_call_cost()
    if cost > human_chips then
        set_status("筹码不足")
        return
    end
    human_chips = human_chips - cost
    human_in_round = human_in_round + cost
    pot = pot + cost
    refresh_chips_ui()
    set_status(cost == 0 and "过牌" or ("跟注 " .. tostring(cost)))

    if cost > 0 then
        if human_in_round == ai_in_round then
            advance_after_both_matched()
            return
        end
        human_to_act = false
        try_ai_response()
        return
    end

    human_to_act = false
    try_ai_response()
end

local function on_human_raise()
    if not human_to_act or street == "end" or street == "showdown" then
        return
    end
    local cost = human_call_cost()
    local total = cost + BB
    if total > human_chips then
        set_status("筹码不足")
        return
    end
    human_chips = human_chips - total
    human_in_round = human_in_round + total
    pot = pot + total
    round_high = human_in_round
    refresh_chips_ui()
    set_status("加注 " .. tostring(total))
    human_to_act = false
    try_ai_response()
end

local function new_hand()
    if not can_start_hand() then
        set_status("一方筹码不足，请重置")
        return
    end
    init_random_seed()
    human_folded = false
    ai_folded = false
    board = { nil, nil, nil, nil, nil }
    street = "preflop"
    pot = 0
    deck = new_deck()
    shuffle(deck)
    human_hole = { deck[1], deck[2] }
    ai_hole = { deck[3], deck[4] }
    for _ = 1, 4 do
        table.remove(deck, 1)
    end
    post_blinds()
    set_phase("翻牌前")
    set_status(human_is_sb and "你是小盲，先行动" or "你是大盲，电脑先行动")
    update_community_ui()
    update_hole_ui()
    refresh_chips_ui()
    human_to_act = human_is_sb
    human_is_sb = not human_is_sb
    if human_to_act then
        return
    end
    sys.timerStart(function()
        try_ai_response()
    end, 60)
end

local function on_reset()
    human_chips = 2000
    ai_chips = 2000
    ai_folded = false
    human_folded = false
    human_is_sb = true
    new_hand()
end

local function on_exit()
    if win_id then
        exwin.close(win_id)
    end
end

local function create_ui()
    CARD_ZOOM = compute_card_zoom()
    log.info("texas_holdem_win", "CARD_ZOOM", CARD_ZOOM)

    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = 480,
        h = 800,
        color = 0x0F2E1A,
    })

    game_area = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 480,
        h = 800,
        color = 0x0F2E1A,
    })

    ai_chips_label = airui.label({
        parent = game_area,
        x = 10,
        y = 10,
        w = 460,
        h = 28,
        text = "电脑: 2000",
        font_size = 20,
        color = 0xC8E6C9,
        align = airui.TEXT_ALIGN_LEFT,
    })

    local ai_cards = airui.container({
        parent = game_area,
        x = 100,
        y = 38,
        w = 280,
        h = CARD_H + 12,
        color = 0x15351A,
    })
    for i = 1, 2 do
        local x = 16 + (i - 1) * (CARD_W + 12)
        local lbl = airui.label({
            parent = ai_cards,
            x = x,
            y = 6,
            w = CARD_W,
            h = CARD_H,
            text = "?",
            font_size = 16,
            color = 0x888888,
            align = airui.TEXT_ALIGN_CENTER,
        })
        local img = airui.image({
            parent = ai_cards,
            x = x,
            y = 6,
            w = CARD_W,
            h = CARD_H,
            zoom = CARD_ZOOM,
            opacity = 0,
        })
        ai_hole_slots[i] = { img = img, lbl = lbl }
    end

    phase_label = airui.label({
        parent = game_area,
        x = 10,
        y = 118,
        w = 460,
        h = 24,
        text = "翻牌前",
        font_size = 18,
        color = 0xA5D6A7,
        align = airui.TEXT_ALIGN_CENTER,
    })

    pot_label = airui.label({
        parent = game_area,
        x = 10,
        y = 146,
        w = 460,
        h = 28,
        text = "底池: 0",
        font_size = 22,
        color = 0xFFECB3,
        align = airui.TEXT_ALIGN_CENTER,
    })

    local comm = airui.container({
        parent = game_area,
        x = 20,
        y = 182,
        w = 440,
        h = CARD_H + 16,
        color = 0x1B4332,
    })
    local gap = 8
    for i = 1, 5 do
        local x = 12 + (i - 1) * (CARD_W + gap)
        local lbl = airui.label({
            parent = comm,
            x = x,
            y = 8,
            w = CARD_W,
            h = CARD_H,
            text = "--",
            font_size = 16,
            color = 0x888888,
            align = airui.TEXT_ALIGN_CENTER,
        })
        local img = airui.image({
            parent = comm,
            x = x,
            y = 8,
            w = CARD_W,
            h = CARD_H,
            zoom = CARD_ZOOM,
            opacity = 0,
        })
        community_slots[i] = { img = img, lbl = lbl }
    end

    status_label = airui.label({
        parent = game_area,
        x = 10,
        y = 282,
        w = 460,
        h = 56,
        text = "准备开始",
        font_size = 18,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_LEFT,
    })

    human_chips_label = airui.label({
        parent = game_area,
        x = 10,
        y = 334,
        w = 460,
        h = 28,
        text = "你: 2000",
        font_size = 20,
        color = 0xC8E6C9,
        align = airui.TEXT_ALIGN_LEFT,
    })

    local hc = airui.container({
        parent = game_area,
        x = 100,
        y = 362,
        w = 280,
        h = CARD_H + 12,
        color = 0x15351A,
    })
    for i = 1, 2 do
        local x = 16 + (i - 1) * (CARD_W + 12)
        local lbl = airui.label({
            parent = hc,
            x = x,
            y = 6,
            w = CARD_W,
            h = CARD_H,
            text = "",
            font_size = 16,
            color = 0xEEEEEE,
            align = airui.TEXT_ALIGN_CENTER,
        })
        local img = airui.image({
            parent = hc,
            x = x,
            y = 6,
            w = CARD_W,
            h = CARD_H,
            zoom = CARD_ZOOM,
            opacity = 0,
        })
        human_hole_slots[i] = { img = img, lbl = lbl }
    end

    local btn_row = airui.container({
        parent = game_area,
        x = 20,
        y = 452,
        w = 440,
        h = 56,
        color = 0x0F2E1A,
    })
    btn_fold = airui.button({
        parent = btn_row,
        x = 0,
        y = 0,
        w = 130,
        h = 50,
        text = "弃牌",
        font_size = 22,
        text_color = 0xFFCDD2,
        bg_color = 0x4E342E,
        on_click = on_human_fold,
    })
    btn_call = airui.button({
        parent = btn_row,
        x = 150,
        y = 0,
        w = 130,
        h = 50,
        text = "跟注/过牌",
        font_size = 22,
        text_color = 0xE8F5E9,
        bg_color = 0x2E7D32,
        on_click = on_human_call,
    })
    btn_raise = airui.button({
        parent = btn_row,
        x = 300,
        y = 0,
        w = 130,
        h = 50,
        text = "加注",
        font_size = 22,
        text_color = 0xFFF9C4,
        bg_color = 0x1B5E20,
        on_click = on_human_raise,
    })

    local bottom = airui.container({
        parent = game_area,
        x = 40,
        y = 512,
        w = 410,
        h = 124,
        color = 0x0F2E1A,
    })
    airui.label({
        parent = bottom,
        x = 0,
        y = 0,
        w = 400,
        h = 18,
        text = "盲注 " .. tostring(SB) .. "/" .. tostring(BB) .. "  加注 +" .. tostring(BB),
        font_size = 12,
        color = 0xA5D6A7,
        align = airui.TEXT_ALIGN_LEFT,
    })
    airui.label({
        parent = bottom,
        x = 0,
        y = 20,
        w = 400,
        h = 18,
        text = "跟注/过牌与当前注对齐",
        font_size = 12,
        color = 0xA5D6A7,
        align = airui.TEXT_ALIGN_LEFT,
    })

    airui.button({
        parent = bottom,
        x = 0,
        y = 62,
        w = 126,
        h = 32,
        text = "新一局",
        font_size = 15,
        text_color = 0xE8F5E9,
        bg_color = 0x33691E,
        on_click = function()
            if street == "end" or street == "showdown" then
                new_hand()
            else
                set_status("先结束本局再开新局")
            end
        end,
    })

    airui.button({
        parent = bottom,
        x = 137,
        y = 62,
        w = 126,
        h = 32,
        text = "重置筹码",
        font_size = 15,
        text_color = 0xE8F5E9,
        bg_color = 0x33691E,
        on_click = on_reset,
    })

    airui.button({
        parent = bottom,
        x = 274,
        y = 62,
        w = 126,
        h = 32,
        text = "退出",
        font_size = 15,
        text_color = 0xE8F5E9,
        bg_color = 0x1B5E20,
        on_click = on_exit,
    })

    if not file_exists("/luadb/2c.png") then
        log.info("texas_holdem_win", "未检测到牌面资源 /luadb/2c.png，使用文字牌面；见 cards/README.txt")
    end

    new_hand()
end

local function on_create()
    create_ui()
end

local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    win_id = nil
    game_area = nil
    status_label = nil
    pot_label = nil
    human_chips_label = nil
    ai_chips_label = nil
    phase_label = nil
    community_slots = {}
    human_hole_slots = {}
    ai_hole_slots = {}
    btn_fold = nil
    btn_call = nil
    btn_raise = nil
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    if win_id ~= nil then
        return
    end
    if not ensure_airui() then
        log.error("texas_holdem_win", "airui init failed")
        return
    end
    log.info("texas_holdem_win", "open_handler")
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

sys.subscribe("OPEN_TEXAS_HOLDEM_WIN", open_handler)

-- 给 main 用：模拟器里常出现 publish 早于事件循环或 subscribe 未收到，需同步调一次
function texas_holdem_open()
    open_handler()
end

-- 仅加载本文件、未跑 main 时，延迟补开（避免无界面）
sys.timerStart(function()
    if win_id == nil and main_container == nil then
        log.info("texas_holdem_win", "timer fallback open")
        open_handler()
    end
end, 100)
