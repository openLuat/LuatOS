--[[
@module  turn_card_win
@summary 炉石like卡牌对战游戏窗口模块
@version 1.0.1
@date    2026.06.04
@author  LuatOS
@description
    游戏业务层模块，负责：
    - 游戏逻辑、UI渲染、用户交互
    - 游戏状态管理（回合、手牌、战场等）
    - 本地AI对战和联网对战
    
    网络通信通过 expvp.lua 模块完成
]]

-- 游戏版本号
local GAME_VERSION = "1.0.1"

-- 引入网络模块（exPvP：联网对战游戏通用框架）
local expvp = require("expvp")

-- ==================== 常量配置 ====================

local W, H = 480, 800  -- 竖屏分辨率

-- 游戏区域配置
local HERO_AREA_H = 120      -- 英雄区域高度
local BOARD_AREA_H = 140     -- 战场区域高度
local HAND_AREA_H = 160      -- 手牌区域高度
local BUTTON_AREA_H = 80     -- 按钮区域高度
local MIDDLE_LOG_H = 40      -- 中间日志区域高度

-- 卡牌尺寸
local CARD_W = 70
local CARD_H = 100
local MINION_W = 60
local MINION_H = 80
local HERO_SIZE = 80

-- 游戏状态
local STATE = {
    MENU = 'menu',
    ROOM_WAITING = 'room_waiting',
    DEVICE_LIST = 'device_list',
    WAITING = 'waiting',
    CONNECTING = 'connecting',
    PLAYING = 'playing',
    GAME_OVER = 'game_over'
}

-- ==================== 卡牌库 ====================

local SPELL_LIB = {
    { id = 0, name = "炎术士", cost = 1, atk = 1, hp = 2, type = "minion", desc = "1费随从" },
    { id = 1, name = "寒冰箭", cost = 2, atk = 0, hp = 0, type = "spell", damage = 3, desc = "造成3点伤害" },
    { id = 2, name = "蓝龙崽", cost = 3, atk = 2, hp = 4, type = "minion", desc = "龙族新星" },
    { id = 3, name = "奥术智慧", cost = 2, atk = 0, hp = 0, type = "spell", draw = 2, desc = "抽2张牌" },
    { id = 4, name = "闪电箭", cost = 1, atk = 0, hp = 0, type = "spell", damage = 2, desc = "造成2点伤害" },
    { id = 5, name = "暗影魔", cost = 2, atk = 2, hp = 2, type = "minion", desc = "虚空造物" },
    { id = 6, name = "地狱火", cost = 4, atk = 4, hp = 4, type = "minion", desc = "毁灭之力" },
    { id = 7, name = "法力护盾", cost = 2, atk = 0, hp = 0, type = "spell", armor = 5, desc = "获得5点护甲" }
}

-- ==================== 模块内部状态 ====================

local win_id = nil
local main_container = nil

local gameState = STATE.MENU
local networkMode = false
local networkRole = nil
local mySide = nil  -- 联机时标记自己是 "player" 还是 "ai" 侧

-- 积分系统
local consecutive_wins = 0  -- 联机连胜场数

-- 联机数据发送/接收
local function sendNetworkAction(actionType, actionData)
    if not networkMode then return end
    local msg = { action = actionType, from = my_device_id }
    if actionData then
        for k, v in pairs(actionData) do msg[k] = v end
    end
    expvp.broadcast_to_room(msg)
end

-- 前置声明：以下变量/函数在后面定义，但 handleNetworkGameData 先定义且引用它们
local checkGameOver
local game
local addLog
local calcScore
local handleScore
local startTurn
local ui
local is_host_player
local current_room_id

local function handleNetworkGameData(data)
    if not networkMode or not data then return end
    log.info('turn_card', '网络数据:', json.encode(data))
    
    -- 处理对方离开消息（type字段而非action字段）
    if data.type == "leave" or data.type == "opponent_left" then
        if gameState == STATE.PLAYING or gameState == STATE.GAME_OVER then
            stopTurnTimer()
            if expvp.leave_room then
                expvp.leave_room()
            end
            current_room_id = nil
            networkMode = false
            is_host_player = false
            consecutive_wins = 0
            if ui.game_container then
                ui.game_container:destroy()
                ui.game_container = nil
                ui.log_labels = nil
                ui.hand_cards = {}
                ui.board_minions = { player = {}, ai = {} }
            end
            if ui.game_over_container then
                ui.game_over_container:destroy()
                ui.game_over_container = nil
            end
            showToast("对方已退出游戏")
            hideRoomWaitingUI()
            showMainMenu()
        else
            updateRoomUI()
        end
        return
    end
    
    local action = data.action
    
    if action == "play_card" then
        -- 对手出了一张牌，使用消息中携带的真实卡牌数据（而非本地的占位手牌）
        local oppSide = mySide == "player" and "ai" or "player"
        local card = data.card
        local cardIdx = data.handIdx
        if card then
            game[oppSide].mana = game[oppSide].mana - card.cost
            -- 从对手手牌中移除（优先按索引，失败则按名字匹配，最后移除任意未知牌）
            local removed = false
            if cardIdx and game[oppSide].hand[cardIdx] then
                table.remove(game[oppSide].hand, cardIdx)
                removed = true
            else
                for i, hc in ipairs(game[oppSide].hand) do
                    if hc.name == card.name then
                        table.remove(game[oppSide].hand, i)
                        removed = true
                        break
                    end
                end
            end
            if not removed and #game[oppSide].hand > 0 then
                table.remove(game[oppSide].hand)
            end
            table.insert(game[oppSide].graveyard, card)
            if card.type == "minion" then
                local newMinion = {
                    id = card.id, name = card.name, cost = card.cost,
                    atk = card.atk, hp = card.hp, maxHp = card.hp, canAttack = true
                }
                table.insert(game[oppSide].board, newMinion)
                addLog("对方召唤了 " .. card.name)
            else
                addLog("对方施放了 " .. card.name)
            end
        end
        
    elseif action == "damage_spell" then
        -- 对手使用伤害法术
        local oppSide = mySide == "player" and "ai" or "player"
        local enemySide = mySide  -- 法术目标是"我"这一侧
        local targetType = data.targetType  -- "hero" or "minion"
        local targetIdx = data.targetIdx
        local cardDef = data.cardDef
        if targetType == "hero" then
            game[enemySide].hero.hp = math.max(0, game[enemySide].hero.hp - cardDef.damage)
            addLog("对方用 " .. (cardDef.name or "法术") .. " 对英雄造成 " .. cardDef.damage .. " 伤害")
        elseif targetType == "minion" and targetIdx then
            local board = game[enemySide].board
            if board[targetIdx] then
                board[targetIdx].hp = math.max(0, board[targetIdx].hp - cardDef.damage)
                addLog("对方用 " .. (cardDef.name or "法术") .. " 对 " .. board[targetIdx].name .. " 造成 " .. cardDef.damage .. " 伤害")
                if board[targetIdx].hp <= 0 then
                    table.insert(game[enemySide].graveyard, table.remove(board, targetIdx))
                    addLog("随从被消灭")
                end
            end
        end
        
    elseif action == "armor_spell" then
        local oppSide = mySide == "player" and "ai" or "player"
        game[oppSide].hero.armor = game[oppSide].hero.armor + (data.armor or 0)
        addLog("对方获得了 " .. (data.armor or 0) .. " 点护甲")
        
    elseif action == "draw_spell" then
        -- 对手抽牌，在本侧同步执行
        -- 实际抽牌是本地化的，不需要同步
        
    elseif action == "hero_power" then
        local oppSide = mySide == "player" and "ai" or "player"
        game[oppSide].mana = game[oppSide].mana - 2
        local enemySide = mySide
        local targetType = data.targetType
        local targetIdx = data.targetIdx
        if targetType == "hero" then
            game[enemySide].hero.hp = math.max(0, game[enemySide].hero.hp - 1)
            addLog("对方英雄技能对英雄造成1点伤害")
        elseif targetType == "minion" and targetIdx then
            local board = game[enemySide].board
            if board[targetIdx] then
                board[targetIdx].hp = math.max(0, board[targetIdx].hp - 1)
                if board[targetIdx].hp <= 0 then
                    table.insert(game[enemySide].graveyard, table.remove(board, targetIdx))
                end
                addLog("对方英雄技能对随从造成1点伤害")
            end
        end
        
    elseif action == "attack" then
        local oppSide = mySide == "player" and "ai" or "player"
        local enemySide = mySide
        local attIdx = data.attackerIdx
        local targetType = data.targetType
        local targetIdx = data.targetIdx
        local attacker = game[oppSide].board[attIdx]
        if not attacker then return end
        if targetType == "hero" then
            local dmg = attacker.atk
            game[enemySide].hero.hp = math.max(0, game[enemySide].hero.hp - dmg)
            attacker.canAttack = false
            addLog("对方 " .. attacker.name .. " 攻击英雄造成 " .. dmg .. " 伤害")
        elseif targetType == "minion" and targetIdx then
            local defender = game[enemySide].board[targetIdx]
            if not defender then return end
            defender.hp = math.max(0, defender.hp - attacker.atk)
            attacker.hp = math.max(0, attacker.hp - defender.atk)
            if defender.hp <= 0 then
                table.insert(game[enemySide].graveyard, table.remove(game[enemySide].board, targetIdx))
            end
            if attacker.hp <= 0 then
                table.insert(game[oppSide].graveyard, table.remove(game[oppSide].board, attIdx))
            else
                attacker.canAttack = false
            end
            addLog("对方 " .. attacker.name .. " 与 " .. defender.name .. " 交战")
        end
        
    elseif action == "end_turn" then
        addLog("对方结束了回合")
        if networkMode and mySide then
            startTurn(mySide)
        end
        
    elseif action == "rematch" then
        -- 再来一局：关闭游戏结束弹窗，重新构建游戏UI
        if ui.game_over_container then
            ui.game_over_container:destroy()
            ui.game_over_container = nil
        end
        gameState = STATE.PLAYING
        buildGameUI()
        
    elseif action == "sync_state" then
        -- 完整状态同步（用于初始/重连）
        if data.turn then game.turn = data.turn end
        if data.oppSide then
            local s = data.oppSide  -- "player" or "ai"，对手侧数据
            if game[s] then
                game[s].mana = data.mana or game[s].mana
                game[s].maxMana = data.maxMana or game[s].maxMana
                game[s].hero.hp = data.heroHp or game[s].hero.hp
                game[s].hero.armor = data.heroArmor or game[s].hero.armor
                game[s].hand = {}  -- 手牌内容隐藏，只保留数量
                for _ = 1, (data.handCount or 0) do
                    table.insert(game[s].hand, { name = "?", cost = 0, type = "unknown" })
                end
                game[s].board = {}
                if data.board then
                    for _, bm in ipairs(data.board) do
                        table.insert(game[s].board, {
                            id = bm.id, name = bm.name, cost = bm.cost,
                            atk = bm.atk, hp = bm.hp, maxHp = bm.maxHp, canAttack = bm.canAttack
                        })
                    end
                end
            end
        end
    end
    
    checkGameOver()
    updateUI()
end

-- 游戏核心数据
game = {
    turn = "player",
    player = {
        hero = { name = "大法师", hp = 30, maxHp = 30, armor = 0 },
        mana = 1, maxMana = 1,
        deck = {}, hand = {}, board = {}, graveyard = {}
    },
    ai = {
        hero = { name = "暗影祭司", hp = 30, maxHp = 30, armor = 0 },
        mana = 1, maxMana = 1,
        deck = {}, hand = {}, board = {}, graveyard = {}
    },
    waitingForTarget = false,
    pendingAction = nil,
    logMessage = "奥术对决开始！玩家先手",
    gameOver = false,
    winner = nil,
    heroPowerUsed = false,
    selectedCardIdx = nil,
    selectedMinionIdx = nil
}

-- 回合倒计时变量
local TURN_TIMEOUT = 20
local turn_timer_id = nil
local turn_remaining = TURN_TIMEOUT
-- 前向声明（实际实现在文件后面）
local stopTurnTimer, startTurnTimer, resetTurnTimer, onTurnTimeout
local showGameOver, showMainMenu

-- UI元素
ui = {
    menu_container = nil,
    game_container = nil,
    room_container = nil,
    log_labels = nil,
    end_turn_btn = nil,

    hero_power_btn = nil,
    player_hero_hp = nil,
    ai_hero_hp = nil,
    player_timer = nil,
    ai_timer = nil,
    player_mana = nil,
    ai_mana = nil,
    hand_cards = {},
    board_minions = { player = {}, ai = {} },
    game_over_container = nil,
    -- 积分标签
    ai_score_label = nil,
    player_score_label = nil,
}

-- ==================== 工具函数 ====================

local function showToast(message, duration)
    duration = duration or 2000
    local toast = airui.container({
        parent = main_container,
        x = W / 2 - 150,
        y = 280,
        w = 300,
        h = 60,
        color = 0x1a1a2e,
        radius = 10
    })
    
    airui.label({
        parent = toast,
        x = 0,
        y = 15,
        w = 300,
        h = 30,
        text = message,
        color = 0xffffff,
        font_size = 16,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    sys.timerStart(function()
        toast:destroy()
    end, duration)
end

-- 获取设备ID
local function get_device_id()
    local info = expvp.get_player_info()
    return info.device_id
end

-- 获取昵称
local function get_nickname()
    local info = expvp.get_player_info()
    return info.nickname
end

-- 获取对手昵称（联机模式）
local function get_opponent_nickname()
    if not networkMode then return "暗影祭司" end
    local room_info = expvp.get_room_info()
    if room_info and room_info.players then
        for device_id, p in pairs(room_info.players) do
            if device_id ~= my_device_id then
                return p.nickname or "对手"
            end
        end
    end
    return "对手"
end

-- 获取指定side对应的昵称（联机模式，双方看到的结果一致）
local function get_side_nickname(side)
    if not networkMode then
        return side == "player" and "大法师" or "暗影祭司"
    end
    if side == mySide then
        return get_nickname() or "玩家"
    else
        return get_opponent_nickname()
    end
end

local function shuffleArray(arr)
    local result = {}
    for i = 1, #arr do
        result[i] = arr[i]
    end
    for i = #result, 2, -1 do
        local j = math.random(i)
        result[i], result[j] = result[j], result[i]
    end
    return result
end

-- 日志历史数组（最多10条）
local logHistory = {}
local MAX_LOG_LINES = 10

addLog = function(msg)
    game.logMessage = msg
    -- 添加到历史记录顶部
    table.insert(logHistory, 1, msg)
    -- 超过5条时删除最旧的（最后一条）
    if #logHistory > MAX_LOG_LINES then
        table.remove(logHistory)
    end
    -- UI 已被销毁则跳过更新（防止访问已销毁的 airui 组件导致崩溃）
    if not ui.game_container then return end
    -- 更新显示
    if ui.log_labels then
        for i = 1, MAX_LOG_LINES do
            if ui.log_labels[i] then
                pcall(function() ui.log_labels[i]:set_text(logHistory[i] or "") end)
                pcall(function() ui.log_labels[i]:set_color(i == 1 and 0xf1c40f or 0x888888) end)
            end
        end
    end
end

-- ==================== 游戏逻辑 ====================

local function buildBaseDeck()
    local deck = {}
    -- 通用函数：完整复制卡牌所有字段
    local function cloneCard(cardDef)
        local card = {}
        for k, v in pairs(cardDef) do
            card[k] = v
        end
        return card
    end
    for i = 1, 2 do
        table.insert(deck, cloneCard(SPELL_LIB[1]))
    end
    table.insert(deck, cloneCard(SPELL_LIB[5]))
    table.insert(deck, cloneCard(SPELL_LIB[2]))
    table.insert(deck, cloneCard(SPELL_LIB[4]))
    table.insert(deck, cloneCard(SPELL_LIB[6]))
    table.insert(deck, cloneCard(SPELL_LIB[3]))
    table.insert(deck, cloneCard(SPELL_LIB[7]))
    return shuffleArray(deck)
end

local function drawCard(side)
    local target = game[side]
    if #target.deck == 0 then
        if #target.graveyard > 0 then
            target.deck = shuffleArray(target.graveyard)
            target.graveyard = {}
            local name1 = (side == 'player') and (networkMode and (get_nickname() or "玩家") or "大法师艾琳") or (networkMode and "对手" or "暗影祭司")
        addLog(name1 .. " 牌库重洗")
        else
            return
        end
    end
    
    if #target.deck > 0 then
        local card = table.remove(target.deck, 1)
        if #target.hand >= 6 then
            table.insert(target.graveyard, card)
            addLog("手牌已满，" .. card.name .. " 被弃置")
        else
            table.insert(target.hand, card)
            local name2 = (side == 'player') and (networkMode and (get_nickname() or "玩家") or "大法师艾琳") or (networkMode and "对手" or "暗影祭司")
            addLog(name2 .. "抽中：" .. card.name)
        end
    end
end

local function resetAttackMarks(side)
    for _, m in ipairs(game[side].board) do
        m.canAttack = true
    end
end

checkGameOver = function()
    if game.gameOver then return false end
    if game.player.hero.hp <= 0 then
        game.gameOver = true
        game.winner = "ai"
        gameState = STATE.GAME_OVER
        -- game.player是host侧 → host阵亡，guest获胜 → 双方显示一致
        local winnerName = get_side_nickname("ai")
        local loserName = get_side_nickname("player")
        addLog("胜利！" .. winnerName .. "净化了" .. loserName)
        -- 计算并处理积分（pcall 保护，确保弹窗始终显示）
        local scoreEarned, isWinner = 0, false
        local oldStreak = consecutive_wins  -- 保存旧连胜数，handleScore 会清零
        pcall(function()
            scoreEarned, isWinner = calcScore()
            handleScore(scoreEarned, isWinner)
        end)
        showGameOver(winnerName .. "获胜", scoreEarned, isWinner, oldStreak)
        stopTurnTimer()
        return true
    elseif game.ai.hero.hp <= 0 then
        game.gameOver = true
        game.winner = "player"
        gameState = STATE.GAME_OVER
        -- game.ai是guest侧 → guest阵亡，host获胜 → 双方显示一致
        local winnerName = get_side_nickname("player")
        local loserName = get_side_nickname("ai")
        addLog("胜利！" .. winnerName .. "净化了" .. loserName)
        -- 计算并处理积分（pcall 保护，确保弹窗始终显示）
        local scoreEarned, isWinner = 0, false
        local oldStreak = consecutive_wins  -- 保存旧连胜数，handleScore 会清零
        pcall(function()
            scoreEarned, isWinner = calcScore()
            handleScore(scoreEarned, isWinner)
        end)
        showGameOver(winnerName .. "获胜", scoreEarned, isWinner, oldStreak)
        stopTurnTimer()
        return true
    end
    return false
end

-- 计算本场可获得积分
calcScore = function()
    local isWinner = false
    if networkMode then
        isWinner = (game.winner == mySide)
    else
        isWinner = (game.winner == "player")
    end
    if not isWinner then
        return 0, false
    end
    if networkMode then
        local baseScore = 10
        local streakBonus = consecutive_wins * 2
        return baseScore + streakBonus, true
    else
        return 5, true  -- 单机模式固定5分
    end
end

-- 处理积分累加与上传
handleScore = function(scoreEarned, isWinner)
    if isWinner and scoreEarned > 0 then
        expvp.add_score(scoreEarned)
        if networkMode then
            consecutive_wins = consecutive_wins + 1
        end
    else
        if networkMode then
            consecutive_wins = 0  -- 联机失败重置连胜
        end
    end
    expvp.upload_score(function(success, total)
        if success then
            log.info('turn_card', '积分上传成功, 总分: ' .. (total or 0))
        end
    end)
end

startTurn = function(side)
    if game.gameOver then return end
    if not ui.game_container then return end
    local p = game[side]
    p.maxMana = math.min(10, p.maxMana + 1)
    p.mana = p.maxMana
    drawCard(side)
    resetAttackMarks(side)
    game.heroPowerUsed = false
    game.turn = side
    -- 联机模式下根据mySide显示"你的回合"或"对方回合"
    if networkMode and mySide then
        addLog((side == mySide and '你的' or '对方的') .. "回合开始")
    else
        addLog((side == 'player' and '玩家' or 'AI') .. " 回合开始")
    end
    -- 只有当前回合是本地玩家时才启动计时器
    if networkMode and mySide then
        if side == mySide then
            startTurnTimer()
        else
            stopTurnTimer()
            if ui.player_timer then
                ui.player_timer:set_text("")
            end
        end
    else
        -- 单机模式：只有玩家回合才启动计时器
        if side == "player" then
            startTurnTimer()
        else
            stopTurnTimer()
            if ui.player_timer then
                ui.player_timer:set_text("")
            end
        end
    end
    updateUI()
end

-- ==================== 游戏动作 ====================

local function executeHeroPower(side, targetType, targetIdx)
    local caster = game[side]
    local enemySide = side == "player" and "ai" or "player"
    
    if caster.mana < 2 then
        addLog("法力不足")
        return false
    end
    if game.heroPowerUsed then
        addLog("英雄技能已使用")
        return false
    end
    
    caster.mana = caster.mana - 2
    game.heroPowerUsed = true
    
    if targetType == "hero" then
        local enemyHero = game[enemySide].hero
        enemyHero.hp = math.max(0, enemyHero.hp - 1)
        addLog("火焰冲击对敌方英雄造成1点伤害")
    elseif targetType == "minion" then
        local board = game[enemySide].board
        if targetIdx > 0 and targetIdx <= #board then
            local minion = board[targetIdx]
            minion.hp = math.max(0, minion.hp - 1)
            addLog("火焰冲击对 " .. minion.name .. " 造成1点伤害")
            if minion.hp <= 0 then
                table.insert(game[enemySide].graveyard, minion)
                table.remove(board, targetIdx)
                addLog(minion.name .. " 被消灭")
            end
        end
    end
    
    checkGameOver()
    if side == 'player' then resetTurnTimer() end
    if networkMode and side == mySide then
        sendNetworkAction("hero_power", { targetType = targetType, targetIdx = targetIdx })
    end
    updateUI()
    return true
end

local function playCard(side, handIdx)
    if game.gameOver then return false end
    if game.turn ~= side then
        addLog("不是你的回合")
        return false
    end
    
    local playerObj = game[side]
    local card = playerObj.hand[handIdx]
    if not card then return false end
    
    if playerObj.mana < card.cost then
        addLog("法力不足")
        return false
    end
    
    if card.type == "minion" then
        if #playerObj.board >= 5 then
            addLog("战场已满")
            return false
        end
        playerObj.mana = playerObj.mana - card.cost
        local newMinion = {
            id = card.id, name = card.name, cost = card.cost, atk = card.atk, hp = card.hp, maxHp = card.hp, canAttack = true
        }
        table.insert(playerObj.board, newMinion)
        table.remove(playerObj.hand, handIdx)
        table.insert(playerObj.graveyard, card)
        local name3 = (side == 'player') and (networkMode and (get_nickname() or "玩家") or "大法师艾琳") or (networkMode and "对手" or "暗影祭司")
        addLog(name3 .. "使用：" .. card.name)
        if side == 'player' then resetTurnTimer() end
        if networkMode and side == mySide then
            sendNetworkAction("play_card", { handIdx = handIdx, card = { id = card.id, name = card.name, cost = card.cost, type = card.type, atk = card.atk, hp = card.hp } })
        end
        updateUI()
        return true
        
    elseif card.type == "spell" then
        if card.damage then
            game.waitingForTarget = true
            game.pendingAction = { type = "spell_damage", side = side, card = card, handIdx = handIdx }
            addLog("点击敌方头像或随从施放 " .. card.name)
            return true
        elseif card.armor then
            playerObj.mana = playerObj.mana - card.cost
            playerObj.hero.armor = playerObj.hero.armor + card.armor
            table.remove(playerObj.hand, handIdx)
            table.insert(playerObj.graveyard, card)
            addLog(card.name .. " 赋予 " .. card.armor .. " 点护甲")
            if side == 'player' then resetTurnTimer() end
            if networkMode and side == mySide then
                sendNetworkAction("armor_spell", { armor = card.armor })
            end
            updateUI()
            return true
        elseif card.draw then
            playerObj.mana = playerObj.mana - card.cost
            table.remove(playerObj.hand, handIdx)
            table.insert(playerObj.graveyard, card)
            addLog(card.name .. " 抽 " .. card.draw .. " 张牌")
            for i = 1, card.draw do
                drawCard(side)
            end
            if side == 'player' then resetTurnTimer() end
            if networkMode and side == mySide then
                sendNetworkAction("draw_spell", { draw = card.draw })
            end
            updateUI()
            return true
        end
    end
    return false
end

local function applyDamageSpell(side, card, targetType, targetIdx)
    log.info('turn_card', 'applyDamageSpell called, card=', json.encode(card))
    local caster = game[side]
    local enemySide = side == "player" and "ai" or "player"
    
    caster.mana = caster.mana - card.cost
    local handIdx = game.pendingAction.handIdx
    table.remove(caster.hand, handIdx)
    table.insert(caster.graveyard, card)
    
    if targetType == "hero" then
        local enemyHero = game[enemySide].hero
        enemyHero.hp = math.max(0, enemyHero.hp - card.damage)
        addLog(card.name .. " 对敌方英雄造成 " .. card.damage .. " 伤害")
    else
        local board = game[enemySide].board
        if targetIdx > 0 and targetIdx <= #board then
            local minion = board[targetIdx]
            minion.hp = math.max(0, minion.hp - card.damage)
            addLog(card.name .. " 对 " .. minion.name .. " 造成 " .. card.damage .. " 伤害")
            if minion.hp <= 0 then
                table.insert(game[enemySide].graveyard, minion)
                table.remove(board, targetIdx)
                addLog(minion.name .. " 被消灭")
            end
        end
    end
    
    game.waitingForTarget = false
    game.pendingAction = nil
    checkGameOver()
    if side == 'player' then resetTurnTimer() end
    if networkMode and side == mySide then
        sendNetworkAction("damage_spell", {
            cardDef = { name = card.name, damage = card.damage },
            targetType = targetType, targetIdx = targetIdx
        })
    end
    updateUI()
    return true
end

local function applyAttack(attackerSide, attackerIdx, targetType, targetIdx)
    local attacker = game[attackerSide].board[attackerIdx]
    if not attacker or not attacker.canAttack then return false end
    
    local enemySide = attackerSide == "player" and "ai" or "player"
    
    if targetType == "hero" then
        local enemyHero = game[enemySide].hero
        local dmg = attacker.atk
        enemyHero.hp = math.max(0, enemyHero.hp - dmg)
        addLog(attacker.name .. " 攻击英雄造成 " .. dmg .. " 伤害")
        attacker.canAttack = false
        checkGameOver()
    else
        local enemyBoard = game[enemySide].board
        if targetIdx < 1 or targetIdx > #enemyBoard then return false end
        local defender = enemyBoard[targetIdx]
        local attDmg = attacker.atk
        local defDmg = defender.atk
        defender.hp = math.max(0, defender.hp - attDmg)
        attacker.hp = math.max(0, attacker.hp - defDmg)
        addLog(attacker.name .. " 与 " .. defender.name .. " 交战")
        
        if defender.hp <= 0 then
            table.insert(game[enemySide].graveyard, defender)
            table.remove(enemyBoard, targetIdx)
            addLog(defender.name .. " 被消灭")
        end
        if attacker.hp <= 0 then
            table.insert(game[attackerSide].graveyard, attacker)
            for i, m in ipairs(game[attackerSide].board) do
                if m == attacker then
                    table.remove(game[attackerSide].board, i)
                    break
                end
            end
            addLog(attacker.name .. " 战死")
        else
            attacker.canAttack = false
        end
        checkGameOver()
    end
    
    game.waitingForTarget = false
    game.pendingAction = nil
    game.selectedMinionIdx = nil
    if attackerSide == 'player' then resetTurnTimer() end
    if networkMode and attackerSide == mySide then
        sendNetworkAction("attack", { attackerIdx = attackerIdx, targetType = targetType, targetIdx = targetIdx })
    end
    updateUI()
    return true
end

local function endTurn()
    if game.gameOver then return end
    -- 联机模式下检查是否是当前玩家的回合
    local isMyTurn = networkMode and mySide and (game.turn == mySide)
    local isPlayerTurn = not networkMode and (game.turn == "player")
    if not isMyTurn and not isPlayerTurn then
        if networkMode then
            addLog("现在是对方回合")
        else
            addLog("现在是AI回合")
        end
        return
    end
    stopTurnTimer()
    -- 清除倒计时UI显示
    if ui.player_timer then
        ui.player_timer:set_text("")
    end
    game.waitingForTarget = false
    game.pendingAction = nil
    game.selectedCardIdx = nil
    game.selectedMinionIdx = nil
    if networkMode then
        sendNetworkAction("end_turn", {})
        -- 切换到对方回合（防止玩家在等待期间误操作）
        game.turn = (mySide == "player") and "ai" or "player"
        addLog("等待对方操作...")
        updateUI()
        return
    end
    startTurn("ai")
    sys.timerStart(aiTurn, 800)
end

-- ==================== 倒计时函数 ====================

stopTurnTimer = function()
    if turn_timer_id then
        sys.timerStop(turn_timer_id)
        turn_timer_id = nil
    end
end

onTurnTimeout = function()
    turn_timer_id = nil
    -- 联机模式下检查是否是当前玩家的回合
    local mySideLocal = networkMode and mySide or "player"
    if game.turn == mySideLocal and not game.gameOver then
        addLog("时间到！自动结束回合")
        endTurn()
    end
end

startTurnTimer = function()
    stopTurnTimer()
    turn_remaining = TURN_TIMEOUT
    if ui.player_timer then
        ui.player_timer:set_text(tostring(turn_remaining))
        ui.player_timer:set_color(0xf1c40f)
    end
    turn_timer_id = sys.timerLoopStart(function()
        turn_remaining = turn_remaining - 1
        if ui.player_timer then
            ui.player_timer:set_text(tostring(turn_remaining))
            if turn_remaining <= 5 then
                ui.player_timer:set_color(0xe74c3c)
            end
        end
        if turn_remaining <= 0 then
            stopTurnTimer()
            onTurnTimeout()
        end
    end, 1000)
end

resetTurnTimer = function()
    local mySideLocal = networkMode and mySide or "player"
    if turn_timer_id and game.turn == mySideLocal then
        startTurnTimer()
    end
end

-- ==================== AI逻辑 ====================

function aiTurn()
    if game.gameOver or game.turn ~= "ai" then return end
    
    local ai = game.ai
    local opp = game.player
    
    -- 使用英雄技能
    if not game.heroPowerUsed and ai.mana >= 2 then
        local targetType = "hero"
        local targetIdx = 0
        if #opp.board > 0 and math.random() < 0.6 then
            targetType = "minion"
            local lowHealthIdx = 1
            local lowHealth = opp.board[1].hp
            for i, m in ipairs(opp.board) do
                if m.hp < lowHealth then
                    lowHealth = m.hp
                    lowHealthIdx = i
                end
            end
            targetIdx = lowHealthIdx
        end
        executeHeroPower("ai", targetType, targetIdx)
    end
    
    if game.gameOver then return end
    
    -- 出牌
    for i = #ai.hand, 1, -1 do
        local card = ai.hand[i]
        if card and card.cost and ai.mana >= card.cost then
            if card.type == "spell" and card.damage then
                local targetIdx = 0
                local targetType = "minion"
                local found = false
                for j, m in ipairs(opp.board) do
                    if m.hp <= card.damage then
                        targetIdx = j
                        found = true
                        break
                    end
                end
                if not found and #opp.board > 0 then
                    targetIdx = 1
                elseif #opp.board == 0 then
                    targetType = "hero"
                end
                
                ai.mana = ai.mana - card.cost
                local spellCard = table.remove(ai.hand, i)
                table.insert(ai.graveyard, spellCard)
                
                if targetType == "hero" then
                    opp.hero.hp = math.max(0, opp.hero.hp - card.damage)
                    addLog("AI 施放 " .. card.name .. " 对英雄造成 " .. card.damage .. " 伤害")
                else
                    local m = opp.board[targetIdx]
                    m.hp = math.max(0, m.hp - card.damage)
                    addLog("AI 施放 " .. card.name .. " 对 " .. m.name .. " 造成 " .. card.damage .. " 伤害")
                    if m.hp <= 0 then
                        table.insert(opp.graveyard, m)
                        table.remove(opp.board, targetIdx)
                        addLog(m.name .. " 被消灭")
                    end
                end
                checkGameOver()
                updateUI()
                
            elseif card.type == "minion" and #ai.board < 5 then
                ai.mana = ai.mana - card.cost
                local newMinion = {
                    id = card.id, name = card.name, atk = card.atk, hp = card.hp, maxHp = card.hp, canAttack = true
                }
                table.insert(ai.board, newMinion)
                table.remove(ai.hand, i)
                table.insert(ai.graveyard, card)
                addLog("AI 召唤 " .. card.name)
                updateUI()
            end
        end
    end
    
    if game.gameOver then return end
    
    -- 随从攻击
    for i, minion in ipairs(ai.board) do
        if minion.canAttack then
            local targetType = "hero"
            local targetIdx = 0
            
            if #opp.board > 0 then
                local bestTarget = 1
                local bestScore = -999
                for j, m in ipairs(opp.board) do
                    local score = m.atk * 2 - m.hp
                    if score > bestScore then
                        bestScore = score
                        bestTarget = j
                    end
                end
                targetType = "minion"
                targetIdx = bestTarget
            end
            
            if targetType == "hero" then
                local dmg = minion.atk
                opp.hero.hp = math.max(0, opp.hero.hp - dmg)
                addLog(minion.name .. " 攻击英雄造成 " .. dmg .. " 伤害")
                minion.canAttack = false
                checkGameOver()
            else
                local defender = opp.board[targetIdx]
                defender.hp = math.max(0, defender.hp - minion.atk)
                minion.hp = math.max(0, minion.hp - defender.atk)
                addLog(minion.name .. " 与 " .. defender.name .. " 交战")
                
                if defender.hp <= 0 then
                    table.insert(opp.graveyard, defender)
                    table.remove(opp.board, targetIdx)
                    addLog(defender.name .. " 被消灭")
                end
                if minion.hp <= 0 then
                    table.insert(ai.graveyard, minion)
                    table.remove(ai.board, i)
                    addLog(minion.name .. " 战死")
                else
                    minion.canAttack = false
                end
                checkGameOver()
            end
            updateUI()
        end
    end
    
    -- AI结束回合
    sys.timerStart(function()
        if not game.gameOver then
            startTurn("player")
        end
    end, 500)
end

-- ==================== UI构建 ====================

local function resetGame()
    game.turn = "player"
    game.player = {
        hero = { name = "大法师", hp = 30, maxHp = 30, armor = 0 },
        mana = 1, maxMana = 1,
        deck = buildBaseDeck(),
        hand = {},
        board = {},
        graveyard = {}
    }
    game.ai = {
        hero = { name = "暗影祭司", hp = 30, maxHp = 30, armor = 0 },
        mana = 1, maxMana = 1,
        deck = buildBaseDeck(),
        hand = {},
        board = {},
        graveyard = {}
    }
    game.waitingForTarget = false
    game.pendingAction = nil
    game.logMessage = "点击卡牌->头像/随从进行攻击 | 结束回合按钮"
    game.gameOver = false
    game.winner = nil
    game.heroPowerUsed = false
    game.selectedCardIdx = nil
    game.selectedMinionIdx = nil
    
    -- 清空日志历史
    logHistory = {}
    stopTurnTimer()
    
    -- 初始抽牌
    for i = 1, 3 do
        drawCard("player")
        drawCard("ai")
    end
    
    -- 添加初始提示
    addLog("点击卡牌->头像/随从进行攻击 | 结束回合按钮")

    updateUI()
    -- 不再这里直接启动计时器，由调用方根据情况决定
    -- 单机模式：buildGameUI 后会调用 startTurn(game.turn)
    -- 联机模式：根据 game_start 的 player_assignments 决定
end

-- ==================== 游戏UI ====================

function updateUI()
    if not ui.game_container then return end
    if game.gameOver then return end  -- 游戏结束时不更新UI，避免干扰结算弹窗
    
    -- 确定显示映射：底部始终是自己，顶部始终是对方
    local bottomSide = networkMode and mySide or "player"
    local topSide = (bottomSide == "player") and "ai" or "player"
    
    -- 更新底部玩家HP条和数值（钳制负数）
    if ui.player_hero_hp and bottomSide then
        local hp = math.max(0, game[bottomSide].hero.hp)
        ui.player_hero_hp:set_text(hp .. "/" .. game[bottomSide].hero.maxHp)
    end
    if ui.player_hp_bar and bottomSide then
        ui.player_hp_bar:set_value(math.max(0, game[bottomSide].hero.hp), false)
    end
    
    -- 更新顶部对方HP条和数值（钳制负数）
    if ui.ai_hero_hp and topSide then
        local hp = math.max(0, game[topSide].hero.hp)
        ui.ai_hero_hp:set_text(hp .. "/" .. game[topSide].hero.maxHp)
    end
    if ui.ai_hp_bar and topSide then
        ui.ai_hp_bar:set_value(math.max(0, game[topSide].hero.hp), false)
    end
    
    -- 更新底部玩家法力条和数值
    if ui.player_mana and bottomSide then
        local m = math.max(0, game[bottomSide].mana)
        ui.player_mana:set_text(m .. "/" .. game[bottomSide].maxMana)
    end
    if ui.player_mana_segments and bottomSide then
        local m = math.max(0, game[bottomSide].mana)
        for i = 1, 10 do
            ui.player_mana_segments[i]:set_hidden(i > m)
        end
    end
    
    -- 更新顶部对方法力条分段显示
    if ui.ai_mana and topSide then
        local m = math.max(0, game[topSide].mana)
        ui.ai_mana:set_text(m .. "/" .. game[topSide].maxMana)
    end
    if ui.ai_mana_segments and topSide then
        local m = math.max(0, game[topSide].mana)
        for i = 1, 10 do
            ui.ai_mana_segments[i]:set_hidden(i > m)
        end
    end
    
    -- 更新回合指示器
    if ui.turn_indicator then
        if networkMode and mySide then
            -- 联机模式：显示"你的回合"或"对方回合"
            if game.turn == mySide then
                ui.turn_indicator:set_text("你的回合")
                ui.turn_indicator:set_color(0xf1c40f)
            else
                ui.turn_indicator:set_text("对方回合")
                ui.turn_indicator:set_color(0xe74c3c)
            end
        else
            -- 单机模式：显示"玩家回合"或"AI回合"
            if game.turn == "player" then
                ui.turn_indicator:set_text("玩家回合")
                ui.turn_indicator:set_color(0xf1c40f)
            else
                ui.turn_indicator:set_text("AI回合")
                ui.turn_indicator:set_color(0xe74c3c)
            end
        end
    end
    
    -- 更新日志
    if ui.log_label then
        ui.log_label:set_text(game.logMessage)
    end
    
    -- 更新手牌显示（底部始终是自己）
    local myHand = bottomSide and game[bottomSide].hand or game.player.hand
    for i, cardUI in ipairs(ui.hand_cards) do
        if i <= #myHand then
            local card = myHand[i]
            cardUI.cost_label:set_text(tostring(card.cost))
            cardUI.name_label:set_text(card.name)
            if card.type == "minion" and card.atk ~= nil and card.hp ~= nil then
                -- 随从：显示攻击和生命，隐藏法术
                cardUI.spell_label:set_text("")
                cardUI.atk_container:set_hidden(false)
                cardUI.atk_label:set_text(tostring(card.atk))
                cardUI.hp_container:set_hidden(false)
                cardUI.hp_label:set_text(tostring(card.hp))
            else
                -- 法术：显示"法术"标识，隐藏攻击生命
                cardUI.spell_label:set_text("法术")
                cardUI.atk_container:set_hidden(true)
                cardUI.hp_container:set_hidden(true)
            end
            cardUI.container:set_hidden(false)
        else
            cardUI.container:set_hidden(true)
        end
    end
    
    -- 更新战场显示 - 静态槽位更新（不销毁重建，和手牌一样方式）
    -- 顶部战场（对方）
    local topBoard = topSide and game[topSide].board or game.ai.board
    for i, minionUI in ipairs(ui.board_minions.ai) do
        if i <= #topBoard then
            local m = topBoard[i]
            minionUI.cost_label:set_text(tostring(m.cost or ""))
            minionUI.name_label:set_text(m.name)
            minionUI.atk_label:set_text(tostring(m.atk))
            minionUI.hp_label:set_text(tostring(math.max(0, m.hp)))
            minionUI.container:set_hidden(false)
        else
            minionUI.container:set_hidden(true)
        end
    end
    
    -- 底部战场（自己）
    local bottomBoard = bottomSide and game[bottomSide].board or game.player.board
    for i, minionUI in ipairs(ui.board_minions.player) do
        if i <= #bottomBoard then
            local m = bottomBoard[i]
            minionUI.cost_label:set_text(tostring(m.cost or ""))
            minionUI.name_label:set_text(m.name)
            minionUI.atk_label:set_text(tostring(m.atk))
            minionUI.hp_label:set_text(tostring(math.max(0, m.hp)))
            minionUI.container:set_hidden(false)
        else
            minionUI.container:set_hidden(true)
        end
    end
end

local function buildGameUI()
    -- 先停止所有定时器，防止回调访问已销毁的组件
    stopTurnTimer()
    
    if ui.game_container then
        ui.game_container:destroy()
        ui.game_container = nil
        -- 同步清理容器内所有子组件引用，防止后续回调访问已销毁对象
        ui.log_labels = nil
        ui.hand_cards = {}
        ui.board_minions = { player = {}, ai = {} }
    end
    
    ui.game_container = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = W,
        h = H,
        color = 0x1a2a1a
    })
    
    -- 返回主菜单按钮（右上角）
    airui.button({
        parent = ui.game_container,
        x = W - 80,
        y = 10,
        w = 70,
        h = 36,
        text = "返回",
        font_size = 16,
        style = { bg_color = 0x5a4a4a, text_color = 0xffffff, border_width = 0, radius = 6 },
        on_click = function()
            -- 清理游戏状态
            stopTurnTimer()
            if game_timer_id then
                sys.timerStop(game_timer_id)
                game_timer_id = nil
            end
            -- 联机模式：退出房间通知对方
            if networkMode and expvp.leave_room then
                expvp.leave_room()
            end
            current_room_id = nil
            networkMode = false
            consecutive_wins = 0  -- 重置连胜
            -- 返回主菜单
            if ui.game_container then
                ui.game_container:destroy()
                ui.game_container = nil
                ui.log_labels = nil
                ui.hand_cards = {}
                ui.board_minions = { player = {}, ai = {} }
            end
            showMainMenu()
        end,
    })
    
    -- ========== AI区域（顶部左侧）==========
    -- AI头像（圆形边框）
    airui.container({
        parent = ui.game_container,
        x = 20,
        y = 50,
        w = 62,
        h = 62,
        color = 0x8B6914,
        radius = 31
    })
    airui.image({
        parent = ui.game_container,
        x = 21,
        y = 51,
        w = 60,
        h = 60,
        src = "/luadb/enemy_avatar.png"
    })
    
    -- 确保my_device_id已初始化
    my_device_id = my_device_id or get_device_id()

    -- AI名字（联机模式显示"对方"+对方昵称，单机模式显示"暗影祭司"）
    local ai_name = "暗影祭司"
    if networkMode then
        local room_info = expvp.get_room_info()
        if room_info and room_info.players then
            for device_id, p in pairs(room_info.players) do
                if device_id ~= my_device_id then
                    ai_name = (p.nickname or "对手") .. " (对方)"
                    break
                end
            end
        end
    end
    ui.ai_name_label = airui.label({
        parent = ui.game_container,
        x = 90,
        y = 50,
        w = 150,
        h = 24,
        text = ai_name,
        color = 0xffffff,
        font_size = 18
    })
    
    -- AI积分标签（对手本场积分）
    ui.ai_score_label = airui.label({
        parent = ui.game_container,
        x = 195,
        y = 53,
        w = 130,
        h = 20,
        text = "",
        color = 0xaaaaaa,
        font_size = 12,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- AI HP条（红色）
    ui.ai_hp_bar = airui.bar({
        parent = ui.game_container,
        x = 90,
        y = 78,
        w = 120,
        h = 14,
        min = 0,
        max = 30,
        value = 30,
        bg_color = 0x3a3a3a,
        indicator_color = 0xe74c3c,
        radius = 7
    })
    
    -- AI HP数值
    ui.ai_hero_hp = airui.label({
        parent = ui.game_container,
        x = 215,
        y = 76,
        w = 50,
        h = 18,
        text = "30/30",
        color = 0xffffff,
        font_size = 14
    })
    
    -- AI右侧倒计时（暂不需要，AI回合固定800ms延迟）
    ui.ai_timer = nil
    
    -- AI法力条容器（分段显示）
    ui.ai_mana_container = airui.container({
        parent = ui.game_container,
        x = 90,
        y = 96,
        w = 100,
        h = 10,
        color = 0x3a3a3a,
        radius = 5
    })
    
    -- AI法力条分段（最多10段，每段9像素宽，间隔1像素）
    ui.ai_mana_segments = {}
    for i = 1, 10 do
        local segment = airui.container({
            parent = ui.ai_mana_container,
            x = (i - 1) * 10,
            y = 0,
            w = 9,
            h = 10,
            color = 0x3498db,
            radius = 2
        })
        -- 初始显示1段（游戏开始时有1点法力）
        segment:set_hidden(i > 1)
        table.insert(ui.ai_mana_segments, segment)
    end
    
    -- AI法力数值
    ui.ai_mana = airui.label({
        parent = ui.game_container,
        x = 195,
        y = 94,
        w = 60,
        h = 14,
        text = "1/1",
        color = 0x3498db,
        font_size = 12
    })
    
    -- AI英雄点击区域（透明容器，用于法术目标选择）
    local ai_hero_click = airui.container({
        parent = ui.game_container,
        x = 20,
        y = 50,
        w = 245,
        h = 60
    })
    -- 透明按钮覆盖
    airui.button({
        parent = ai_hero_click,
        x = 0,
        y = 0,
        w = 245,
        h = 60,
        text = "",
        style = { bg_opa = 0, border_width = 0 },
        on_click = function()
            if game.waitingForTarget and game.pendingAction then
                if game.pendingAction.type == "spell_damage" then
                    applyDamageSpell(game.pendingAction.side, game.pendingAction.card, "hero", 0)
                elseif game.pendingAction.type == "hero_power" then
                    executeHeroPower(game.pendingAction.side, "hero", 0)
                elseif game.pendingAction.type == "attack" then
                    applyAttack(game.pendingAction.side, game.pendingAction.attackerIdx, "hero", 0)
                end
            end
        end
    })
    
    -- 回合指示器（右上角）
    ui.turn_indicator = airui.label({
        parent = ui.game_container,
        x = W - 150,
        y = 60,
        w = 130,
        h = 30,
        text = "玩家回合",
        color = 0xf1c40f,
        font_size = 20,
        align = airui.TEXT_ALIGN_RIGHT
    })
    
    -- AI战场区域（AI头像下方）- 静态创建5个随从槽位
    ui.board_minions.ai = {}
    local ai_board_y = 120
    for slot_i = 1, 5 do
        local m_x = 20 + (slot_i - 1) * 75
        local mc = airui.container({
            parent = ui.game_container,
            x = m_x, y = ai_board_y,
            w = MINION_W, h = MINION_H,
            color = 0xe8d5b7,
            radius = 8
        })
        airui.button({
            parent = mc, x = 0, y = 0, w = MINION_W, h = MINION_H,
            text = "",
            style = { bg_opa = 0, border_width = 0 },
            on_click = function()
                if game.waitingForTarget and game.pendingAction then
                    if game.pendingAction.type == "spell_damage" then
                        applyDamageSpell(game.pendingAction.side, game.pendingAction.card, "minion", slot_i)
                    elseif game.pendingAction.type == "hero_power" then
                        executeHeroPower(game.pendingAction.side, "minion", slot_i)
                    elseif game.pendingAction.type == "attack" then
                        applyAttack(game.pendingAction.side, game.pendingAction.attackerIdx, "minion", slot_i)
                    end
                end
            end
        })
        -- 费用数值（左上角）
        airui.container({ parent = mc, x = 2, y = 2, w = 14, h = 14, color = 0x3498db, radius = 7 })
        local cl = airui.label({ parent = mc, x = 2, y = 2, w = 14, h = 14, text = "", color = 0xffffff, font_size = 9, align = airui.TEXT_ALIGN_CENTER })
        local nl = airui.label({ parent = mc, x = 2, y = 25, w = MINION_W - 4, h = 18, text = "", color = 0x2c1810, font_size = 18, align = airui.TEXT_ALIGN_CENTER })
        airui.image({ parent = mc, x = 2, y = MINION_H - 18, w = 14, h = 14, src = "/luadb/attack_icon.png" })
        local al = airui.label({ parent = mc, x = 2, y = MINION_H - 18, w = 14, h = 14, text = "", color = 0xffffff, font_size = 9, align = airui.TEXT_ALIGN_CENTER })
        airui.image({ parent = mc, x = MINION_W - 16, y = MINION_H - 18, w = 14, h = 14, src = "/luadb/health_icon.png" })
        local hl = airui.label({ parent = mc, x = MINION_W - 16, y = MINION_H - 18, w = 14, h = 14, text = "", color = 0xffffff, font_size = 9, align = airui.TEXT_ALIGN_CENTER })
        mc:set_hidden(true)
        table.insert(ui.board_minions.ai, { container = mc, cost_label = cl, name_label = nl, atk_label = al, hp_label = hl })
    end

    -- ========== 公共出牌记录区域（中间）==========
    -- 实时记录日志区域（10行滚动显示）
    ui.log_labels = {}
    for i = 1, MAX_LOG_LINES do
        ui.log_labels[i] = airui.label({
            parent = ui.game_container,
            x = 20,
            y = 200 + (i - 1) * 20,
            w = W - 40,
            h = 18,
            text = i == 1 and "点击卡牌->头像/随从进行攻击 | 结束回合按钮" or "",
            color = i == 1 and 0xf1c40f or 0x888888,
            font_size = 18,
            align = airui.TEXT_ALIGN_CENTER
        })
    end
    
    -- ========== 玩家战场区域 ==========
    -- 玩家战场区域 - 静态创建5个随从槽位
    ui.board_minions.player = {}
    local player_board_y = 420
    for slot_i = 1, 5 do
        local m_x = 20 + (slot_i - 1) * 75
        local mc = airui.container({
            parent = ui.game_container,
            x = m_x, y = player_board_y,
            w = MINION_W, h = MINION_H,
            color = 0xe8d5b7,
            radius = 8
        })
        airui.button({
            parent = mc, x = 0, y = 0, w = MINION_W, h = MINION_H,
            text = "",
            style = { bg_opa = 0, border_width = 0 },
            on_click = function()
                -- 确定当前玩家侧：联机模式使用mySide，单机模式使用"player"
                local mySideLocal = networkMode and mySide or "player"
                local mySideData = networkMode and mySide and game[mySide] or game.player
                if game.turn == mySideLocal then
                    local minion = mySideData.board[slot_i]
                    if minion and minion.canAttack then
                        game.waitingForTarget = true
                        game.pendingAction = { type = "attack", side = mySideLocal, attackerIdx = slot_i, attacker = minion }
                        game.selectedMinionIdx = slot_i
                        addLog("选择攻击目标")
                        updateUI()
                    end
                end
            end
        })
        airui.container({ parent = mc, x = 2, y = 2, w = 14, h = 14, color = 0x3498db, radius = 7 })
        local cl = airui.label({ parent = mc, x = 2, y = 2, w = 14, h = 14, text = "", color = 0xffffff, font_size = 9, align = airui.TEXT_ALIGN_CENTER })
        local nl = airui.label({ parent = mc, x = 2, y = 25, w = MINION_W - 4, h = 18, text = "", color = 0x2c1810, font_size = 18, align = airui.TEXT_ALIGN_CENTER })
        airui.image({ parent = mc, x = 2, y = MINION_H - 18, w = 14, h = 14, src = "/luadb/attack_icon.png" })
        local al = airui.label({ parent = mc, x = 2, y = MINION_H - 18, w = 14, h = 14, text = "", color = 0xffffff, font_size = 9, align = airui.TEXT_ALIGN_CENTER })
        airui.image({ parent = mc, x = MINION_W - 16, y = MINION_H - 18, w = 14, h = 14, src = "/luadb/health_icon.png" })
        local hl = airui.label({ parent = mc, x = MINION_W - 16, y = MINION_H - 18, w = 14, h = 14, text = "", color = 0xffffff, font_size = 9, align = airui.TEXT_ALIGN_CENTER })
        mc:set_hidden(true)
        table.insert(ui.board_minions.player, { container = mc, cost_label = cl, name_label = nl, atk_label = al, hp_label = hl })
    end

    -- ========== 玩家区域（下方）==========
    -- 玩家头像
    airui.image({
        parent = ui.game_container,
        x = 20,
        y = 540,
        w = 60,
        h = 60,
        src = "/luadb/player_avatar.png"
    })
    
    -- 玩家名字（联机模式显示"你"+自己的昵称，单机模式显示"大法师艾琳"）
    local player_name = "大法师艾琳"
    if networkMode then
        player_name = (get_nickname() or "玩家") .. " (你)"
    end
    ui.player_name_label = airui.label({
        parent = ui.game_container,
        x = 90,
        y = 540,
        w = 150,
        h = 24,
        text = player_name,
        color = 0xffffff,
        font_size = 18
    })
    
    -- 玩家积分标签（本场积分）
    ui.player_score_label = airui.label({
        parent = ui.game_container,
        x = 195,
        y = 543,
        w = 130,
        h = 20,
        text = "",
        color = 0xaaaaaa,
        font_size = 12,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 玩家HP条（红色）
    ui.player_hp_bar = airui.bar({
        parent = ui.game_container,
        x = 90,
        y = 568,
        w = 120,
        h = 14,
        min = 0,
        max = 30,
        value = 30,
        bg_color = 0x3a3a3a,
        indicator_color = 0xe74c3c,
        radius = 7
    })
    
    -- 玩家HP数值
    ui.player_hero_hp = airui.label({
        parent = ui.game_container,
        x = 215,
        y = 566,
        w = 50,
        h = 18,
        text = "30/30",
        color = 0xffffff,
        font_size = 14
    })
    
    -- 玩家右侧倒计时
    ui.player_timer = airui.label({
        parent = ui.game_container,
        x = 270,
        y = 560,
        w = 50,
        h = 30,
        text = "",
        color = 0xf1c40f,
        font_size = 26,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 玩家法力条容器（分段显示）
    ui.player_mana_container = airui.container({
        parent = ui.game_container,
        x = 90,
        y = 586,
        w = 100,
        h = 10,
        color = 0x3a3a3a,
        radius = 5
    })
    
    -- 玩家法力条分段（最多10段，每段9像素宽，间隔1像素）
    ui.player_mana_segments = {}
    for i = 1, 10 do
        local segment = airui.container({
            parent = ui.player_mana_container,
            x = (i - 1) * 10,
            y = 0,
            w = 9,
            h = 10,
            color = 0x3498db,
            radius = 2
        })
        -- 初始显示1段（游戏开始时有1点法力）
        segment:set_hidden(i > 1)
        table.insert(ui.player_mana_segments, segment)
    end
    
    -- 玩家法力数值
    ui.player_mana = airui.label({
        parent = ui.game_container,
        x = 195,
        y = 584,
        w = 60,
        h = 14,
        text = "1/1",
        color = 0x3498db,
        font_size = 12
    })
    
    -- 英雄技能按钮（右下角）
    ui.hero_power_btn = airui.button({
        parent = ui.game_container,
        x = W - 100,
        y = 540,
        w = 80,
        h = 60,
        text = "英雄技能\n(2费)",
        font_size = 20,
        style = { bg_color = 0x5a3a1a, text_color = 0xffa500, border_width = 0, radius = 8 },
        on_click = function()
            -- 确定当前玩家侧：联机模式使用mySide，单机模式使用"player"
            local mySideLocal = networkMode and mySide or "player"
            local mySideData = networkMode and mySide and game[mySide] or game.player
            if game.turn == mySideLocal and not game.heroPowerUsed and mySideData.mana >= 2 then
                game.waitingForTarget = true
                game.pendingAction = { type = "hero_power", side = mySideLocal }
                addLog("火焰冲击 → 选择目标")
            end
        end
    })
    
    -- 手牌区域（玩家信息下方）
    ui.hand_cards = {}
    for i = 1, 6 do
        local card_x = 10 + (i - 1) * 78
        local card_y = 620
        
        -- 卡牌容器
        local card_container = airui.container({
            parent = ui.game_container,
            x = card_x,
            y = card_y,
            w = CARD_W,
            h = CARD_H,
            color = 0x4a3a2a,
            radius = 8
        })
        
        -- 卡牌背景图
        airui.image({
            parent = card_container,
            x = 0,
            y = 0,
            w = CARD_W,
            h = CARD_H,
            src = "/luadb/spell_card_bg.png"
        })
        
        -- 费用数值（左上角，圆形背景）
        airui.container({
            parent = card_container,
            x = 2,
            y = 2,
            w = 16,
            h = 16,
            color = 0x3498db,
            radius = 8
        })
        local cost_label = airui.label({
            parent = card_container,
            x = 2,
            y = 2,
            w = 16,
            h = 16,
            text = "",
            color = 0xffffff,
            font_size = 12,
            align = airui.TEXT_ALIGN_CENTER
        })
        
        -- 卡牌名称（中间）- 使用深色文字带阴影效果
        local name_label = airui.label({
            parent = card_container,
            x = 2,
            y = 35,
            w = CARD_W - 4,
            h = 30,
            text = "",
            color = 0x2c1810,
            font_size = 18,
            align = airui.TEXT_ALIGN_CENTER
        })
        
        -- 底部区域容器（完全透明，不设置背景色）
        local bottom_container = airui.container({
            parent = card_container,
            x = 0,
            y = CARD_H - 28,
            w = CARD_W,
            h = 26
        })
        
        -- 法术标识（底部居中，仅法术显示）
        local spell_label = airui.label({
            parent = bottom_container,
            x = 0,
            y = 3,
            w = CARD_W,
            h = 20,
            text = "",
            color = 0x9b59b6,
            font_size = 11,
            align = airui.TEXT_ALIGN_CENTER
        })
        
        -- 攻击区域（左下角，仅随从显示）
        local atk_container = airui.container({
            parent = bottom_container,
            x = 5,
            y = 3,
            w = 30,
            h = 20
        })
        local atk_icon = airui.image({
            parent = atk_container,
            x = 0,
            y = 2,
            w = 14,
            h = 14,
            src = "/luadb/attack_icon.png"
        })
        local atk_label = airui.label({
            parent = atk_container,
            x = 16,
            y = 0,
            w = 14,
            h = 20,
            text = "",
            color = 0xffffff,
            font_size = 11,
            align = airui.TEXT_ALIGN_LEFT
        })
        
        -- 生命区域（右下角，仅随从显示）
        local hp_container = airui.container({
            parent = bottom_container,
            x = CARD_W - 35,
            y = 3,
            w = 30,
            h = 20
        })
        local hp_icon = airui.image({
            parent = hp_container,
            x = 0,
            y = 2,
            w = 14,
            h = 14,
            src = "/luadb/health_icon.png"
        })
        local hp_label = airui.label({
            parent = hp_container,
            x = 16,
            y = 0,
            w = 14,
            h = 20,
            text = "",
            color = 0xffffff,
            font_size = 11,
            align = airui.TEXT_ALIGN_LEFT
        })
        
        -- 点击按钮（覆盖在容器上）
        local card_btn = airui.button({
            parent = card_container,
            x = 0,
            y = 0,
            w = CARD_W,
            h = CARD_H,
            text = "",
            style = { 
                bg_color = 0x000000, 
                text_color = 0xffffff, 
                border_width = 0, 
                radius = 8,
                bg_opa = 0
            },
            on_click = function()
                -- 确定当前玩家侧：联机模式使用mySide，单机模式使用"player"
                local mySideLocal = networkMode and mySide or "player"
                local mySideData = networkMode and mySide and game[mySide] or game.player
                if game.turn == mySideLocal and i <= #mySideData.hand then
                    local card = mySideData.hand[i]
                    if game.selectedCardIdx == i then
                        -- 第二次点击同一张牌：出牌
                        playCard(mySideLocal, i)
                        game.selectedCardIdx = nil
                    else
                        game.selectedCardIdx = i
                        addLog("选中: " .. card.name)
                        -- 法术牌：第一次点击就进入目标选择模式
                        if card.type == "spell" then
                            playCard(mySideLocal, i)
                            game.selectedCardIdx = nil
                        end
                        updateUI()
                    end
                end
            end
        })
        
        table.insert(ui.hand_cards, {
            container = card_container,
            btn = card_btn,
            cost_label = cost_label,
            name_label = name_label,
            spell_label = spell_label,
            atk_container = atk_container,
            atk_label = atk_label,
            hp_container = hp_container,
            hp_label = hp_label
        })
    end

    -- 底部按钮区域
    -- 结束回合按钮
    ui.end_turn_btn = airui.button({
        parent = ui.game_container,
        x = W - 120,
        y = H - 70,
        w = 100,
        h = 45,
        text = "结束回合",
        font_size = 20,
        style = { bg_color = 0x4a4a6a, text_color = 0xffffff, border_width = 0, radius = 8 },
        on_click = endTurn
    })
    
    -- AI英雄点击区域（作为攻击目标）
    airui.button({
        parent = ui.game_container,
        x = 20,
        y = 50,
        w = 60,
        h = 60,
        text = "",
        style = { bg_opa = 0, border_width = 0 },
        on_click = function()
            if game.waitingForTarget and game.pendingAction then
                if game.pendingAction.type == "spell_damage" then
                    applyDamageSpell(game.pendingAction.side, game.pendingAction.card, "hero", 0)
                elseif game.pendingAction.type == "hero_power" then
                    executeHeroPower(game.pendingAction.side, "hero", 0)
                elseif game.pendingAction.type == "attack" then
                    applyAttack(game.pendingAction.side, game.pendingAction.attackerIdx, "hero", 0)
                end
            end
        end
    })
    
    resetGame()
    -- 开始游戏回合，startTurn 会根据当前回合和模式决定是否启动计时器
    startTurn(game.turn)
end

-- ==================== 菜单UI ====================

showGameOver = function(winnerText, scoreEarned, isWinner, oldStreak)
    if ui.game_over_container then
        ui.game_over_container:destroy()
    end
    
    local popup_h = 250
    ui.game_over_container = airui.container({
        parent = main_container,
        x = W / 2 - 150,
        y = H / 2 - popup_h / 2,
        w = 300,
        h = popup_h,
        color = 0x1a1a2e,
        radius = 15
    })
    
    airui.label({
        parent = ui.game_over_container,
        x = 0,
        y = 20,
        w = 300,
        h = 40,
        text = "游戏结束",
        color = 0xffd700,
        font_size = 28,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    airui.label({
        parent = ui.game_over_container,
        x = 0,
        y = 65,
        w = 300,
        h = 35,
        text = winnerText,
        color = 0xffffff,
        font_size = 20,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 本局获胜者奖励
    airui.label({
        parent = ui.game_over_container,
        x = 0,
        y = 100,
        w = 300,
        h = 25,
        text = "本局获胜者：+10分",
        color = 0xffd700,
        font_size = 16,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 积分显示
    if isWinner then
        local scoreMsg = "获得积分: +" .. scoreEarned
        if networkMode and consecutive_wins > 0 then
            scoreMsg = scoreMsg .. " (连胜" .. consecutive_wins .. "场)"
        end
        airui.label({
            parent = ui.game_over_container,
            x = 0,
            y = 130,
            w = 300,
            h = 30,
            text = scoreMsg,
            color = 0x00ff88,
            font_size = 16,
            align = airui.TEXT_ALIGN_CENTER
        })
    elseif networkMode and (oldStreak or 0) > 0 then
        -- 失败且之前有连胜，才提示连胜中断
        airui.label({
            parent = ui.game_over_container,
            x = 0,
            y = 130,
            w = 300,
            h = 25,
            text = "连胜已中断 (此前" .. oldStreak .. "连胜)",
            color = 0xcc6666,
            font_size = 14,
            align = airui.TEXT_ALIGN_CENTER
        })
    end
    
    -- 再来一局按钮（左）
    airui.button({
        parent = ui.game_over_container,
        x = 45,
        y = popup_h - 55,
        w = 100,
        h = 40,
        text = "再来一局",
        style = { bg_color = 0x4a4a6a, text_color = 0xffffff, border_width = 0, radius = 8 },
        on_click = function()
            ui.game_over_container:destroy()
            ui.game_over_container = nil
            if networkMode then
                sendNetworkAction("rematch", {})
                gameState = STATE.PLAYING
                buildGameUI()
            else
                resetGame()
                startTurn(game.turn)
            end
        end
    })
    -- 返回菜单按钮（右）
    airui.button({
        parent = ui.game_over_container,
        x = 155,
        y = popup_h - 55,
        w = 100,
        h = 40,
        text = "返回菜单",
        style = { bg_color = 0x888888, text_color = 0xffffff, border_width = 0, radius = 8 },
        on_click = function()
            ui.game_over_container:destroy()
            ui.game_over_container = nil
            if networkMode then
                local expvp_mod = require("expvp")
                pcall(function() expvp_mod.leave_room() end)
            end
            if ui.game_container then
                ui.game_container:destroy()
                ui.game_container = nil
                ui.log_labels = nil
                ui.hand_cards = {}
            end
            networkMode = false
            current_room_id = nil
            stopTurnTimer()
            showMainMenu()
        end
    })
end

-- ==================== 房间系统状态 ====================
local room_players = {}
local my_ready = false
local room_has_enough = false
is_host_player = false
current_room_id = nil
local my_device_id = nil  -- 当前设备ID

-- 房间UI元素
local room_waiting_container = nil
local join_dialog_container = nil
local join_input_label = nil
local join_input_text = ""
local help_dialog_container = nil
local leaderboard_container = nil
local ready_btn = nil
local room_start_btn = nil

-- 前向声明
local setupExpvp
local onCreateRoom
local onJoinRoom
local showJoinDialog
local showHelpDialog
local showLeaderboard
local showRoomWaitingUI
local hideRoomWaitingUI
local updateRoomUI
local sendOpponentLeft

-- ==================== 帮助弹窗 ====================
local function showHelpDialog()
    if help_dialog_container then
        help_dialog_container:destroy()
        help_dialog_container = nil
    end

    help_dialog_container = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = W,
        h = H,
        color = 0x1a1a2e,
    })

    -- 标题
    airui.label({
        parent = help_dialog_container,
        x = 0,
        y = 40,
        w = W,
        h = 50,
        text = "游戏帮助",
        font_size = 32,
        color = 0xffd700,
        align = airui.TEXT_ALIGN_CENTER,
    })

    local line_y = 110
    local line_h = 36

    -- 游戏规则
    airui.label({
        parent = help_dialog_container,
        x = 30,
        y = line_y,
        w = W - 60,
        h = line_h,
        text = "【游戏规则】",
        font_size = 22,
        color = 0x4a9eff,
        align = airui.TEXT_ALIGN_LEFT,
    })

    line_y = line_y + line_h + 8

    local rules = {
        "1. 双方英雄初始30点生命值",
        "2. 每回合获得1点法力水晶(上限10)",
        "3. 手牌上限6张，超出会弃置",
        "4. 战场最多5个随从",
        "5. 先击败对方英雄获胜",
    }

    for _, rule in ipairs(rules) do
        airui.label({
            parent = help_dialog_container,
            x = 30,
            y = line_y,
            w = W - 60,
            h = 30,
            text = rule,
            font_size = 20,
            color = 0xcccccc,
            align = airui.TEXT_ALIGN_LEFT,
        })
        line_y = line_y + 30
    end

    line_y = line_y + 20

    -- 操作说明
    airui.label({
        parent = help_dialog_container,
        x = 30,
        y = line_y,
        w = W - 60,
        h = line_h,
        text = "【操作说明】",
        font_size = 22,
        color = 0x4a9eff,
        align = airui.TEXT_ALIGN_LEFT,
    })

    line_y = line_y + line_h + 8

    local operations = {
        "1. 点击手牌选中，再次点击打出",
        "2. 点击随从选择攻击目标",
        "3. 点击英雄技能选择目标施放",
        "4. 法术牌需要选择目标",
        "5. 点击结束回合让AI行动",
    }

    for _, op in ipairs(operations) do
        airui.label({
            parent = help_dialog_container,
            x = 30,
            y = line_y,
            w = W - 60,
            h = 30,
            text = op,
            font_size = 20,
            color = 0xcccccc,
            align = airui.TEXT_ALIGN_LEFT,
        })
        line_y = line_y + 30
    end

    line_y = line_y + 20

    -- 积分规则
    airui.label({
        parent = help_dialog_container,
        x = 30,
        y = line_y,
        w = W - 60,
        h = line_h,
        text = "【积分规则】",
        font_size = 22,
        color = 0x4a9eff,
        align = airui.TEXT_ALIGN_LEFT,
    })

    line_y = line_y + line_h + 8

    local scores = {
        "1. 联机获胜: +10分",
        "2. 单机获胜: +5分",
        "3. 联机连胜: 每场额外+2分",
        "4. 失败不扣分",
    }

    for _, s in ipairs(scores) do
        airui.label({
            parent = help_dialog_container,
            x = 30,
            y = line_y,
            w = W - 60,
            h = 30,
            text = s,
            font_size = 20,
            color = 0xcccccc,
            align = airui.TEXT_ALIGN_LEFT,
        })
        line_y = line_y + 30
    end

    -- 关闭按钮
    airui.button({
        parent = help_dialog_container,
        x = W / 2 - 60,
        y = H - 100,
        w = 120,
        h = 50,
        text = "关闭",
        font_size = 22,
        style = { bg_color = 0x4a4a6a, text_color = 0xffffff, radius = 10 },
        on_click = function()
            if help_dialog_container then
                help_dialog_container:destroy()
                help_dialog_container = nil
            end
        end,
    })
end

-- ==================== 排行榜（新实现） ====================

-- 前向声明
local loadLeaderboardData

-- 排行榜窗口ID和UI容器
local leaderboardWinId = nil
local leaderboardMainContainer = nil
local leaderboardItems = {}
local leaderboardPage = 1
local leaderboardTotalPages = 1
local leaderboardData = {}
local leaderboardLoadingLabel = nil

-- 关闭排行榜窗口
local function closeLeaderboardWin()
    if leaderboardWinId then
        exwin.close(leaderboardWinId)
        leaderboardWinId = nil
        leaderboardMainContainer = nil
        leaderboardItems = {}
    end
end

-- 重建排行榜UI（卡片式列表）
local function rebuildLeaderboardUI()
    if not leaderboardMainContainer then return end
    
    -- 清空旧项目
    for _, item in ipairs(leaderboardItems) do
        if item then item:destroy() end
    end
    leaderboardItems = {}
    
    -- 列表宽度适配
    local cardW = 440
    local cardX = (W - cardW) / 2
    local cardH = 46
    local gap = 6
    local yPos = 80
    
    -- 表头卡片
    local header = airui.container({
        parent = leaderboardMainContainer,
        x = cardX, y = yPos, w = cardW, h = 28,
        color = 0xE8F0FE,
        radius = 4
    })
    table.insert(leaderboardItems, header)
    
    airui.label({
        parent = header, x = 15, y = 6, w = 60, h = 18,
        text = "排名", font_size = 22, color = 0x007AFF
    })
    airui.label({
        parent = header, x = 80, y = 6, w = 240, h = 18,
        text = "昵称", font_size = 22, color = 0x007AFF
    })
    airui.label({
        parent = header; x = 360; y = 6; w = 70; h = 18;
        text = "积分"; font_size = 22; color = 0x007AFF;
        align = airui.TEXT_ALIGN_RIGHT
    })
    
    yPos = yPos + 28 + gap + 2
    
    if #leaderboardData == 0 then
        local empty = airui.container({
            parent = leaderboardMainContainer,
            x = cardX, y = yPos, w = cardW, h = 60,
            color = 0xFFFFFF,
            radius = 6
        })
        table.insert(leaderboardItems, empty)
        airui.label({
            parent = empty, x = 0, y = 20, w = cardW, h = 22,
            text = "暂无数据", font_size = 18, color = 0x888888,
            align = airui.TEXT_ALIGN_CENTER
        })
        return
    end
    
    -- 计算当前页的起始和结束索引（每页11个，最多显示30名）
    local startIdx = (leaderboardPage - 1) * 11 + 1
    local endIdx = math.min(startIdx + 10, #leaderboardData, 30)
    
    -- 前三名背景色
    local medalBgColors = {
        [1] = 0xFFD700,  -- 金
        [2] = 0xC0C0C0,  -- 银
        [3] = 0xCD7F32   -- 铜
    }
    
    for i = startIdx, endIdx do
        local record = leaderboardData[i]
        local nickname = (record.s1 and #record.s1 > 0) and record.s1 or "匿名"
        local score = record.i1 or 0
        local displayName = #nickname > 16 and nickname:sub(1, 16) .. ".." or nickname
        
        local isTop3 = (i <= 3)
        local bgColor = isTop3 and medalBgColors[i] or 0xF5F5F5
        local textColor = 0x333333
        
        -- 卡片容器
        local card = airui.container({
            parent = leaderboardMainContainer,
            x = cardX, y = yPos, w = cardW, h = cardH,
            color = bgColor,
            radius = 6
        })
        table.insert(leaderboardItems, card)
        
        -- 排名
        airui.label({
            parent = card, x = 15, y = 7, w = 50, h = 20,
            text = tostring(i), font_size = 16,
            color = textColor
        })
        
        -- 昵称
        airui.label({
            parent = card, x = 80, y = 7, w = 260, h = 20,
            text = displayName, font_size = 16,
            color = textColor
        })
        
        -- 积分
        airui.label({
            parent = card, x = 360, y = 7, w = 70, h = 20,
            text = tostring(score), font_size = 16,
            color = textColor,
            align = airui.TEXT_ALIGN_RIGHT
        })
        
        yPos = yPos + cardH + gap
    end
    
    -- 分页控件
    local pageControlY = 690
    
    -- 上一页按钮
    local prevBtn = airui.button({
        parent = leaderboardMainContainer,
        x = 50, y = pageControlY, w = 100, h = 44,
        text = "上一页",
        font_size = 18,
        style = { bg_color = leaderboardPage > 1 and 0x228844 or 0x888888, text_color = 0xFFFFFF, radius = 6 },
        on_click = function()
            if leaderboardPage > 1 then
                leaderboardPage = leaderboardPage - 1
                loadLeaderboardData()
            end
        end
    })
    table.insert(leaderboardItems, prevBtn)
    
    -- 页码显示
    local pageLabel = airui.label({
        parent = leaderboardMainContainer,
        x = 170, y = pageControlY + 8, w = 140, h = 28,
        text = string.format("<%d/%d>", leaderboardPage, leaderboardTotalPages),
        font_size = 22,
        color = 0x333333,
        align = airui.TEXT_ALIGN_CENTER
    })
    table.insert(leaderboardItems, pageLabel)
    
    -- 下一页按钮
    local nextBtn = airui.button({
        parent = leaderboardMainContainer,
        x = 330, y = pageControlY, w = 100, h = 44,
        text = "下一页",
        font_size = 18,
        style = { bg_color = leaderboardPage < leaderboardTotalPages and 0x228844 or 0x888888, text_color = 0xFFFFFF, radius = 6 },
        on_click = function()
            if leaderboardPage < leaderboardTotalPages then
                leaderboardPage = leaderboardPage + 1
                loadLeaderboardData()
            end
        end
    })
    table.insert(leaderboardItems, nextBtn)
end

-- 加载排行榜数据回调
local function onLeaderboardQueryCallback(success, data)
    if success and data and data.records then
        if leaderboardLoadingLabel then
            leaderboardLoadingLabel:destroy()
            leaderboardLoadingLabel = nil
        end
        leaderboardData = data.records
        
        table.sort(leaderboardData, function(a, b)
            return (tonumber(a.i1) or 0) > (tonumber(b.i1) or 0)
        end)
        
        local total = math.min(tonumber(data.total) or #data.records, 30)
        leaderboardTotalPages = math.max(1, math.ceil(total / 11))
        rebuildLeaderboardUI()
    end
end

-- 加载排行榜数据
loadLeaderboardData = function()
    if leaderboardLoadingLabel then
        leaderboardLoadingLabel:set_text("加载中...")
    end
    
    -- 使用 expvp.query_leaderboard 查询（默认前30名）
    expvp.query_leaderboard(function(success, data)
        if not success or not data then
            if leaderboardLoadingLabel then
                leaderboardLoadingLabel:set_text("加载失败")
            end
            return
        end
        onLeaderboardQueryCallback(success, data)
    end)
end

-- 打开排行榜窗口
local function openLeaderboardWin()
    log.info('turn_card', 'openLeaderboardWin 被调用, leaderboardWinId=' .. tostring(leaderboardWinId))
    if leaderboardWinId then
        log.info('turn_card', '排行榜窗口已存在，直接返回')
        return
    end
    
    leaderboardData = {}
    leaderboardPage = 1
    leaderboardTotalPages = 1
    
    leaderboardWinId = exwin.open({
        on_create = function()
            log.info('turn_card', '排行榜窗口 on_create 被调用')
            leaderboardMainContainer = airui.container({
                parent = airui.screen,
                x = 0, y = 0, w = W, h = H,
                color = 0xFFFFFF
            })
            
            -- 标题
            airui.label({
                parent = leaderboardMainContainer,
                x = 0, y = 20, w = W, h = 48,
                text = "积分排行榜",
                font_size = 32,
                color = 0x333333,
                align = airui.TEXT_ALIGN_CENTER
            })
            
            -- 加载提示
            leaderboardLoadingLabel = airui.label({
                parent = leaderboardMainContainer,
                x = 0, y = 200, w = W, h = 35,
                text = "数据同步中，请稍等...",
                font_size = 16,
                color = 0x888888,
                align = airui.TEXT_ALIGN_CENTER
            })
            
            -- 加载数据
            loadLeaderboardData()
            
            -- 刷新按钮
            airui.button({
                parent = leaderboardMainContainer,
                x = W / 2 - 200, y = H - 60, w = 110, h = 44,
                text = "刷新",
                font_size = 18,
                style = { bg_color = 0x228844, text_color = 0xFFFFFF, radius = 8 },
                on_click = function()
                    log.info('turn_card', '刷新按钮被点击')
                    leaderboardPage = 1
                    loadLeaderboardData()
                end
            })

            -- 删除我的积分按钮
            airui.button({
                parent = leaderboardMainContainer,
                x = W / 2 - 55, y = H - 60, w = 110, h = 44,
                text = "删除我的积分",
                font_size = 16,
                style = { bg_color = 0xcc4444, text_color = 0xFFFFFF, radius = 8 },
                on_click = function()
                    -- 确认对话框
                    local confirmContainer = airui.container({
                        parent = leaderboardMainContainer,
                        x = 0, y = 0, w = W, h = H,
                        color = 0x00000080
                    })

                    -- 对话框背景
                    airui.container({
                        parent = confirmContainer,
                        x = W / 2 - 150, y = H / 2 - 80, w = 300, h = 160,
                        color = 0xFFFFFF,
                        radius = 12
                    })

                    -- 提示文字
                    airui.label({
                        parent = confirmContainer,
                        x = W / 2 - 140, y = H / 2 - 60, w = 280, h = 60,
                        text = "确定要删除您的积分记录吗？\n此操作不可恢复",
                        font_size = 16,
                        color = 0x333333,
                        align = airui.TEXT_ALIGN_CENTER
                    })

                    -- 确定按钮
                    airui.button({
                        parent = confirmContainer,
                        x = W / 2 - 130, y = H / 2 + 10, w = 110, h = 44,
                        text = "确定删除",
                        font_size = 16,
                        style = { bg_color = 0xcc4444, text_color = 0xFFFFFF, radius = 8 },
                        on_click = function()
                            expvp.delete_score(function(success, count)
                                if success then
                                    showToast("积分已删除")
                                    leaderboardPage = 1
                                    loadLeaderboardData()
                                else
                                    showToast("删除失败，请检查登录状态")
                                end
                            end)
                            confirmContainer:destroy()
                        end
                    })

                    -- 取消按钮
                    airui.button({
                        parent = confirmContainer,
                        x = W / 2 + 20, y = H / 2 + 10, w = 110, h = 44,
                        text = "取消",
                        font_size = 16,
                        style = { bg_color = 0x888888, text_color = 0xFFFFFF, radius = 8 },
                        on_click = function()
                            confirmContainer:destroy()
                        end
                    })
                end
            })

            -- 返回按钮
            airui.button({
                parent = leaderboardMainContainer,
                x = W / 2 + 90, y = H - 60, w = 110, h = 44,
                text = "返回",
                font_size = 18,
                style = { bg_color = 0x888888, text_color = 0xFFFFFF, radius = 8 },
                on_click = function()
                    log.info('turn_card', '返回按钮被点击, leaderboardWinId=' .. tostring(leaderboardWinId))
                    if leaderboardWinId then
                        log.info('turn_card', '正在关闭排行榜窗口')
                        exwin.close(leaderboardWinId)
                        leaderboardWinId = nil
                        leaderboardMainContainer = nil
                        leaderboardItems = {}
                        log.info('turn_card', '排行榜窗口已关闭')
                    else
                        log.info('turn_card', 'leaderboardWinId 为 nil，无法关闭')
                    end
                end
            })
        end,
        on_destroy = function()
            log.info('turn_card', '排行榜窗口 on_destroy 被调用')
            -- 显式销毁容器，因为 parent 是 airui.screen 不是窗口本身
            for _, item in ipairs(leaderboardItems) do
                if item then item:destroy() end
            end
            leaderboardItems = {}
            if leaderboardLoadingLabel then
                leaderboardLoadingLabel:destroy()
                leaderboardLoadingLabel = nil
            end
            if leaderboardMainContainer then
                leaderboardMainContainer:destroy()
                leaderboardMainContainer = nil
            end
            leaderboardWinId = nil
            leaderboardData = {}
        end
    })
end

local function showLeaderboard()
    openLeaderboardWin()
end

-- ==================== 发送退出通知 ====================

-- 发送退出通知给对方
sendOpponentLeft = function()
    if not networkMode then return end
    if current_room_id then
        -- 房间模式：广播到房间
        expvp.broadcast_to_room({
            type = "opponent_left",
            from_device = my_device_id,
        })
    end
end

-- ==================== 创建/加入房间 ====================

-- 公共：初始化 expvp 并注册事件回调
setupExpvp = function()
    local ok, err = expvp.init({
        game_name = "turn_card",
        score_cls = 3,
        room_max_players = 2,
    })
    if not ok then
        log.error('turn_card', 'expvp init failed:', err)
        return
    end

    -- 获取设备信息
    my_device_id = get_device_id()
    
    -- 注册事件回调
    expvp.on(function(event, payload)
        if event == "message" then
            -- 通过 broadcast_to_room 发送的游戏数据会作为 message 事件到达
            -- 过滤掉自己发送的消息（broadcast 会发给房间内所有人包括自己）
            if payload.from ~= my_device_id then
                handleNetworkGameData(payload)
            end
        elseif event == "peer_join" then
            log.info('turn_card', '玩家加入房间:', payload.nickname or payload.device_id)
            updateRoomUI()
        elseif event == "peer_leave" then
            log.info('turn_card', '玩家离开房间:', payload.device_id)
            -- 游戏进行中或游戏结束，提示对方已退出
            if gameState == STATE.PLAYING or gameState == STATE.GAME_OVER then
                stopTurnTimer()
                -- 退出房间
                if expvp.leave_room then
                    expvp.leave_room()
                end
                current_room_id = nil
                networkMode = false
                is_host_player = false
                -- 清除游戏UI
                if ui.game_container then
                    ui.game_container:destroy()
                    ui.game_container = nil
                    ui.log_labels = nil
                    ui.hand_cards = {}
                    ui.board_minions = { player = {}, ai = {} }
                end
                showToast("对方已退出游戏")
                hideRoomWaitingUI()
                showMainMenu()
            elseif gameState == STATE.ROOM_WAITING then
                showToast("对方已离开房间")
                updateRoomUI()
            else
                updateRoomUI()
            end
        elseif event == "peer_ready" then
            log.info('turn_card', '玩家准备状态:', payload.device_id, payload.ready)
            updateRoomUI()
        elseif event == "game_start" then
            log.info('turn_card', '收到游戏开始通知')
            -- 解析玩家编号分配
            local assignments = payload.player_assignments or {}
            for devId, pNum in pairs(assignments) do
                if devId == my_device_id then
                    mySide = (pNum == 1) and "player" or "ai"
                end
            end
            networkMode = true
            local room_info = expvp.get_room_info()
            is_host_player = room_info.is_host
            -- 设置对手ID
            local peer_device_id = nil
            for device_id, pnum in pairs(assignments) do
                if device_id ~= my_device_id then
                    peer_device_id = device_id
                    break
                end
            end
            expvp.set_game_playing(true, peer_device_id)
            
            -- 关闭房间等待UI，开始游戏
            gameState = STATE.PLAYING
            hideRoomWaitingUI()
            buildGameUI()
        elseif event == "join_rejected" then
            showToast("加入被拒绝: " .. (payload.reason or "未知原因"))
            showMainMenu()
        elseif event == "disconnect" then
            if networkMode and (gameState == STATE.PLAYING or gameState == STATE.GAME_OVER) then
                stopTurnTimer()
                -- 退出房间
                if expvp.leave_room then
                    expvp.leave_room()
                end
                current_room_id = nil
                -- 清除游戏UI
                if ui.game_container then
                    ui.game_container:destroy()
                    ui.game_container = nil
                    ui.log_labels = nil
                    ui.hand_cards = {}
                    ui.board_minions = { player = {}, ai = {} }
                end
                showToast("对方已退出游戏")
                networkMode = false
                is_host_player = false
                hideRoomWaitingUI()
                showMainMenu()
            elseif networkMode and gameState == STATE.ROOM_WAITING then
                if expvp.leave_room then
                    expvp.leave_room()
                end
                current_room_id = nil
                showToast("网络连接断开")
                networkMode = false
                is_host_player = false
                hideRoomWaitingUI()
                showMainMenu()
            end
        end
    end)
    expvp.start()
end

-- 房间玩家列表UI元素
local room_player_list = {}

-- 更新房间UI（玩家列表、按钮状态）
updateRoomUI = function()
    if not room_waiting_container then return end
    
    -- 获取房间信息
    local room_info = expvp.get_room_info()
    is_host_player = room_info.is_host
    current_room_id = room_info.room_id
    local players = room_info.players or {}
    -- 计算玩家数量（players 表中已包含房主和自己，直接用 pairs 遍历）
    local player_count = 0
    for _ in pairs(players) do
        player_count = player_count + 1
    end
    -- 如果 players 表为空（理论上不会），至少为1（自己）
    if player_count == 0 then
        player_count = 1
    end
    room_has_enough = player_count >= 2
    -- 同步自己的准备状态（确保与网络模块一致）
    my_ready = room_info.my_ready
    
    -- 更新玩家列表（2个位置）
    local player_names = {"P1", "P2"}
    -- 构建玩家映射表: player_number -> {device_id, nickname, ready}
    local player_slots = {}
    -- 从 players 表中动态获取玩家信息
    -- 先放自己（房主或加入者）
    local slot = 1
    if players[my_device_id] then
        local pinfo = players[my_device_id]
        player_slots[slot] = {
            device_id = my_device_id,
            nickname = (pinfo.nickname or my_device_id:sub(-6)) .. " [你]",
            ready = room_info.my_ready,
        }
        slot = slot + 1
    else
        -- 兜底：如果 players 中没有自己，手动添加
        player_slots[slot] = {
            device_id = my_device_id,
            nickname = get_nickname() .. " [你]",
            ready = room_info.my_ready,
        }
        slot = slot + 1
    end
    -- 其他玩家按顺序填入
    for device_id, pinfo in pairs(players) do
        if device_id ~= my_device_id and slot <= 2 then
            local pname = (pinfo.nickname or "") .. ""
            -- 如果 nickname 为空，使用 device_id 后6位
            if pname == "" then
                pname = device_id:sub(-6)
            end
            player_slots[slot] = {
                device_id = device_id,
                nickname = pname,
                ready = pinfo.ready or false,
            }
            slot = slot + 1
        end
    end
    
    -- 更新每个槽位的UI
    for i = 1, 2 do
        local item = room_player_list[i]
        if not item then break end
        
        local ps = player_slots[i]
        if ps then
            -- 有玩家
            local ready_text = ps.ready and "已准备" or "等待中"
            local color = ps.ready and 0x4ecb71 or 0xffd966
            if item.bg then item.bg:set_color((i % 2 == 0) and 0x1e293b or 0x16213e) end
            if item.label then
                item.label:set_text(player_names[i] .. " " .. ps.nickname)
            end
            if item.ready_label then
                item.ready_label:set_text(ready_text)
                item.ready_label:set_color(color)
            end
            if item.bg and item.bg.set_hidden then item.bg:set_hidden(false) end
        else
            -- 空位
            if item.bg and item.bg.set_hidden then item.bg:set_hidden(false) end
            if item.bg then item.bg:set_color(0x0a0a1a) end
            if item.label then
                item.label:set_text(player_names[i] .. " 等待加入...")
            end
            if item.ready_label then
                item.ready_label:set_text("---")
                item.ready_label:set_color(0x666666)
            end
        end
    end
    
    -- 更新准备按钮文字
    if ready_btn and ready_btn.set_text then
        ready_btn:set_text(my_ready and "取消准备" or "准备")
    end
    
    -- 更新开始按钮状态（仅房主可见）
    if room_start_btn then
        if is_host_player then
            if room_start_btn.set_hidden then room_start_btn:set_hidden(false) end
        else
            if room_start_btn.set_hidden then room_start_btn:set_hidden(true) end
        end
    end
end

-- 构建房间等待UI
buildRoomWaitingUI = function()
    -- 如果已有旧容器，先销毁
    if room_waiting_container then
        room_waiting_container:destroy()
        room_waiting_container = nil
    end
    room_player_list = {}
    room_waiting_container = airui.container({
        parent = main_container,
        x = 0, y = 0, w = W, h = H,
        color = 0x1a1a2e,
    })
    room_waiting_container:hide()
    
    local cx = W / 2
    
    -- 标题
    airui.label({
        parent = room_waiting_container,
        x = 0, y = 40, w = W, h = 40,
        text = "等 待 房 间",
        font_size = 28,
        color = 0xf0c040,
        align = airui.TEXT_ALIGN_CENTER,
    })
    
    -- 房间号
    local room_code = current_room_id and current_room_id:gsub("^room_", "") or "---"
    airui.label({
        parent = room_waiting_container,
        x = 0, y = 90, w = W, h = 24,
        text = "房间码: " .. room_code .. "  在线: 1/2",
        font_size = 24,
        color = 0x888888,
        align = airui.TEXT_ALIGN_CENTER,
    })
    
    -- 玩家列表标题
    airui.label({
        parent = room_waiting_container,
        x = cx - 180, y = 125, w = 360, h = 22,
        text = "玩家列表",
        font_size = 26,
        color = 0xaaaaaa,
        align = airui.TEXT_ALIGN_CENTER,
    })
    
    -- 2个玩家槽位
    local slot_start_y = 155
    local slot_height = 50
    for i = 1, 2 do
        local y = slot_start_y + (i - 1) * (slot_height + 8)
        local bg = airui.container({
            parent = room_waiting_container,
            x = cx - 180, y = y, w = 360, h = slot_height,
            color = 0x16213e,
            radius = 6,
        })
        local label = airui.label({
            parent = room_waiting_container,
            x = cx - 170, y = y + 12, w = 200, h = 26,
            text = "P" .. i .. " 等待加入...",
            font_size = 20,
            color = 0xffffff,
            align = airui.TEXT_ALIGN_LEFT,
        })
        local ready_label = airui.label({
            parent = room_waiting_container,
            x = cx + 40, y = y + 12, w = 130, h = 26,
            text = "---",
            font_size = 20,
            color = 0x888888,
            align = airui.TEXT_ALIGN_RIGHT,
        })
        room_player_list[i] = {bg = bg, label = label, ready_label = ready_label}
    end
    
    -- 三个按钮垂直排列：准备 | 开始游戏（房主） | 离开房间
    local btn_start_y = slot_start_y + 2 * (slot_height + 8) + 30
    local btn_w = 200
    local btn_h = 55
    local btn_gap = 15
    local btn_x = cx - btn_w / 2
    
    -- 准备按钮
    ready_btn = airui.button({
        parent = room_waiting_container,
        x = btn_x, y = btn_start_y, w = btn_w, h = btn_h,
        text = "准备",
        font_size = 20,
        style = { bg_color = 0x3b82f6, text_color = 0xFFFFFF, border_width = 0, radius = 10 },
        on_click = function()
            my_ready = not my_ready
            expvp.set_ready(my_ready)
            updateRoomUI()
        end,
    })
    
    -- 开始游戏按钮（房主专用）
    room_start_btn = airui.button({
        parent = room_waiting_container,
        x = btn_x, y = btn_start_y + btn_h + btn_gap, w = btn_w, h = btn_h,
        text = "开始游戏",
        font_size = 20,
        style = { bg_color = 0x4ecb71, text_color = 0xFFFFFF, border_width = 0, radius = 10 },
        on_click = function()
            if not is_host_player then return end
            if not room_has_enough then
                showToast("需要至少2名玩家")
                return
            end
            local room_info = expvp.get_room_info()
            if not room_info.my_ready then
                showToast("请先准备")
                return
            end
            for _, p in pairs(room_info.players or {}) do
                if not p.ready then
                    showToast("等待所有玩家准备")
                    return
                end
            end
            log.info('turn_card', '房主开始游戏')
            expvp.start_game()
        end,
    })
    
    -- 离开房间按钮
    airui.button({
        parent = room_waiting_container,
        x = btn_x, y = btn_start_y + (btn_h + btn_gap) * 2, w = btn_w, h = btn_h,
        text = "离开房间",
        font_size = 20,
        style = { bg_color = 0x884444, text_color = 0xFFFFFF, border_width = 0, radius = 10 },
        on_click = function()
            log.info('turn_card', '离开房间')
            -- 通知其他玩家自己离开
            sendOpponentLeft()
            my_ready = false
            is_host_player = false
            networkMode = false
            current_room_id = nil
            expvp.leave_room()
            hideRoomWaitingUI()
            showMainMenu()
        end,
    })
    
    updateRoomUI()
end

showRoomWaitingUI = function()
    if room_waiting_container then
        room_waiting_container:open()
    end
    if ui.menu_container then
        ui.menu_container:hide()
    end
    if join_dialog_container then
        join_dialog_container:destroy()
        join_dialog_container = nil
    end
    gameState = STATE.ROOM_WAITING
    updateRoomUI()
end

hideRoomWaitingUI = function()
    if room_waiting_container then
        room_waiting_container:destroy()
        room_waiting_container = nil
    end
    room_player_list = {}
end

-- 加入房间弹窗（输入房间ID）
local join_input_label = nil

showJoinDialog = function()
    if join_dialog_container then
        join_dialog_container:destroy()
        join_dialog_container = nil
    end
    
    join_input_text = ""
    
    -- 全屏弹窗，覆盖背后的标题
    join_dialog_container = airui.container({
        parent = main_container,
        x = 0, y = 0, w = W, h = H,
        color = 0x1a1a2e,
    })
    
    -- 标题
    airui.label({
        parent = join_dialog_container,
        x = 0, y = 60, w = W, h = 56,
        text = "加入房间",
        font_size = 36,
        color = 0xf0c040,
        align = airui.TEXT_ALIGN_CENTER,
    })
    
    -- 提示
    airui.label({
        parent = join_dialog_container,
        x = 40, y = 140, w = W - 80, h = 32,
        text = "请输入房主分享的6位房间码",
        font_size = 20,
        color = 0xaaaaaa,
        align = airui.TEXT_ALIGN_CENTER,
    })
    
    -- 输入框显示
    join_input_label = airui.label({
        parent = join_dialog_container,
        x = 40, y = 200, w = W - 80, h = 56,
        text = "|",
        font_size = 32,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER,
    })
    
    -- 虚拟键盘行1: 1-9
    local kb_start_y = 300
    local kb_w = 80
    local kb_h = 60
    local kb_gap = 16
    local kb_start_x = (W - 3 * kb_w - 2 * kb_gap) / 2
    
    for i = 1, 9 do
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        local x = kb_start_x + col * (kb_w + kb_gap)
        local y = kb_start_y + row * (kb_h + kb_gap)
        airui.button({
            parent = join_dialog_container,
            x = x, y = y, w = kb_w, h = kb_h,
            text = tostring(i),
            font_size = 28,
            style = { bg_color = 0x444444, text_color = 0xFFFFFF, radius = 10 },
        on_click = function()
            if #join_input_text < 6 then
                join_input_text = join_input_text .. tostring(i)
                if join_input_label then
                    join_input_label:set_text(join_input_text .. "|")
                    end
                end
            end,
        })
    end
    
    -- 第4行: 0 和 删除
    local row4_y = kb_start_y + 3 * (kb_h + kb_gap)
    airui.button({
        parent = join_dialog_container,
        x = kb_start_x, y = row4_y, w = kb_w, h = kb_h,
        text = "0",
        font_size = 28,
        style = { bg_color = 0x444444, text_color = 0xFFFFFF, radius = 10 },
        on_click = function()
            if #join_input_text < 6 then
                join_input_text = join_input_text .. "0"
                if join_input_label then
                    join_input_label:set_text(join_input_text .. "|")
                end
            end
        end,
    })
    
    -- 删除按钮
    airui.button({
        parent = join_dialog_container,
        x = kb_start_x + (kb_w + kb_gap), y = row4_y,
        w = kb_w * 2 + kb_gap, h = kb_h,
        text = "删除",
        font_size = 24,
        style = { bg_color = 0x884444, text_color = 0xFFFFFF, radius = 10 },
        on_click = function()
            if #join_input_text > 0 then
                join_input_text = join_input_text:sub(1, -2)
                if join_input_label then
                    join_input_label:set_text(#join_input_text > 0 and (join_input_text .. "|") or "|")
                end
            end
        end,
    })
    
    -- 确认加入 + 取消 按钮并排（底部居中）
    local btn_confirm_w = 160
    local btn_cancel_w = 120
    local btn_action_y = H - 140
    airui.button({
        parent = join_dialog_container,
        x = W / 2 - btn_confirm_w - 15, y = btn_action_y,
        w = btn_confirm_w, h = 60,
        text = "确认加入",
        font_size = 24,
        style = { bg_color = 0x3b82f6, text_color = 0xFFFFFF, radius = 12 },
        on_click = function()
            if #join_input_text == 6 then
                local room_id = "room_" .. join_input_text
                if join_dialog_container then
                    join_dialog_container:destroy()
                    join_dialog_container = nil
                end
                onJoinRoom(room_id)
            else
                showToast("请输入6位房间码")
            end
        end,
    })
    airui.button({
        parent = join_dialog_container,
        x = W / 2 + 15, y = btn_action_y,
        w = btn_cancel_w, h = 60,
        text = "取消",
        font_size = 24,
        style = { bg_color = 0x884444, text_color = 0xFFFFFF, radius = 10 },
        on_click = function()
            if join_dialog_container then
                join_dialog_container:destroy()
                join_dialog_container = nil
            end
            join_input_text = ""
        end,
    })
end

-- 加入指定房间
onJoinRoom = function(room_id)
    log.info('turn_card', '加入房间:', room_id)
    my_ready = false
    is_host_player = false
    networkMode = true
    gameState = STATE.ROOM_WAITING
    
    expvp.join_room(room_id)
    current_room_id = room_id
    log.info('turn_card', '加入房间:', room_id)
    buildRoomWaitingUI()
    showRoomWaitingUI()
    showToast("已加入房间，请点击准备")
end

-- 创建房间
onCreateRoom = function()
    log.info('turn_card', '创建房间')
    my_ready = false
    is_host_player = true
    networkMode = true
    gameState = STATE.ROOM_WAITING
    
    -- 创建房间
    current_room_id = expvp.create_room()
    if current_room_id then
        log.info('turn_card', '房间创建成功:', current_room_id)
        buildRoomWaitingUI()
        showRoomWaitingUI()
        showToast("房间已创建，等待其他玩家加入...")
    else
        showToast("创建房间失败")
        showMainMenu()
    end
end

-- ==================== 主菜单（放在所有依赖函数之后）====================

showMainMenu = function()
    if ui.menu_container then
        ui.menu_container:destroy()
    end

    -- 清理房间状态
    if hideRoomWaitingUI then hideRoomWaitingUI() end
    room_players = {}
    my_ready = false
    room_has_enough = false
    networkMode = false
    is_host_player = false
    current_room_id = nil
    gameState = STATE.MENU

    ui.menu_container = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = W,
        h = H,
        color = 0x0a0f1a
    })

    -- 背景图
    airui.image({
        parent = ui.menu_container,
        x = 0,
        y = 0,
        w = W,
        h = H,
        src = "/luadb/turn_card_background.jpg",
        fit = "cover"
    })

    -- 游戏标题
    airui.label({
        parent = ui.menu_container,
        x = 0,
        y = 100,
        w = W,
        h = 60,
        text = "卡 牌 对 决",
        font_size = 52,
        color = 0xf0c040,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 副标题
    airui.label({
        parent = ui.menu_container,
        x = 0,
        y = 165,
        w = W,
        h = 35,
        text = "回合制策略",
        font_size = 30,
        color = 0xaaaacc,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 按钮布局参数
    local btn_w = 260
    local btn_h = 52
    local btn_x = (W - btn_w) / 2
    local btn_gap = 12
    local start_y = 280

    -- 单机对战按钮（深紫蓝色，与魔法主题协调）
    airui.button({
        parent = ui.menu_container,
        x = btn_x,
        y = start_y,
        w = btn_w,
        h = btn_h,
        text = "单机对战",
        font_size = 26,
        style = { bg_color = 0x5a4a8a, text_color = 0xffd700, border_width = 0, radius = 10 },
        on_click = function()
            networkMode = false
            ui.menu_container:hide()
            buildGameUI()
        end,
    })

    -- 创建房间按钮（深紫蓝色）
    airui.button({
        parent = ui.menu_container,
        x = btn_x,
        y = start_y + (btn_h + btn_gap) * 1,
        w = btn_w,
        h = btn_h,
        text = "创建房间",
        font_size = 26,
        style = { bg_color = 0x5a4a8a, text_color = 0xffd700, border_width = 0, radius = 10 },
        on_click = function()
            onCreateRoom()
        end,
    })

    -- 加入房间按钮（深紫蓝色）
    airui.button({
        parent = ui.menu_container,
        x = btn_x,
        y = start_y + (btn_h + btn_gap) * 2,
        w = btn_w,
        h = btn_h,
        text = "加入房间",
        font_size = 26,
        style = { bg_color = 0x5a4a8a, text_color = 0xffd700, border_width = 0, radius = 10 },
        on_click = function()
            showJoinDialog()
        end,
    })

    -- 排行榜按钮（深紫蓝色）
    airui.button({
        parent = ui.menu_container,
        x = btn_x,
        y = start_y + (btn_h + btn_gap) * 3,
        w = btn_w,
        h = btn_h,
        text = "积分排行榜",
        font_size = 26,
        style = { bg_color = 0x5a4a8a, text_color = 0xffd700, border_width = 0, radius = 10 },
        on_click = function()
            showLeaderboard()
        end,
    })

    -- 帮助按钮（深紫蓝色）
    airui.button({
        parent = ui.menu_container,
        x = btn_x,
        y = start_y + (btn_h + btn_gap) * 4,
        w = btn_w,
        h = btn_h,
        text = "帮助",
        font_size = 26,
        style = { bg_color = 0x5a4a8a, text_color = 0xffd700, border_width = 0, radius = 10 },
        on_click = function()
            showHelpDialog()
        end,
    })

    -- 退出按钮（暗红色，与主题形成对比）
    airui.button({
        parent = ui.menu_container,
        x = btn_x,
        y = start_y + (btn_h + btn_gap) * 5,
        w = btn_w,
        h = btn_h,
        text = "退出",
        font_size = 26,
        style = { bg_color = 0x8a3a3a, text_color = 0xffd700, border_width = 0, radius = 10 },
        on_click = function()
            if win_id then
                exwin.close(win_id)
            end
        end,
    })

    -- 版本信息
    airui.label({
        parent = ui.menu_container,
        x = W - 100,
        y = H - 25,
        w = 80,
        h = 18,
        text = "v" .. GAME_VERSION,
        color = 0x666666,
        font_size = 20,
        align = airui.TEXT_ALIGN_RIGHT
    })
end

-- ==================== 窗口生命周期 ====================

local function win_on_create()
    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = W,
        h = H,
        color = 0x0a0f1a
    })
    
    -- 初始化 expvp（只调用一次）
    setupExpvp()
    
    showMainMenu()
end

local function win_on_destroy()
    stopTurnTimer()
    -- 停止MQTT连接（防止重复启动导致多个MQTT任务冲突）
    if expvp then
        expvp.stop()
    end
    -- 清理资源
    if ui.game_container then
        ui.game_container:destroy()
        ui.game_container = nil
    end
    if ui.menu_container then
        ui.menu_container:destroy()
        ui.menu_container = nil
    end
    if ui.game_over_container then
        ui.game_over_container:destroy()
        ui.game_over_container = nil
    end
    main_container = nil
    win_id = nil
end

-- ==================== 消息订阅 ====================

local function open_handler()
    if win_id then return end
    win_id = exwin.open({
        on_create = win_on_create,
        on_destroy = win_on_destroy,
    })
end

sys.subscribe("OPEN_TURN_CARD_WIN", open_handler)

sys.subscribe("CLOSE_TURN_CARD_WIN", function()
    if win_id then
        exwin.close(win_id)
        win_id = nil
        main_container = nil
    end
end)
