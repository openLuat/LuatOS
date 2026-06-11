--[[
@module  coin_clash_win
@summary 双人接金币碰撞对决游戏窗口模块
@version 1.0.1
@date    2026.06.11
@author  王世豪
@description
    游戏业务层模块，负责：
    - 游戏逻辑、UI渲染、用户交互
    - 游戏状态管理（菜单、房间等待、游戏中、游戏结束）
    - 积分数据存储和管理
    - 设备信息管理
    
    网络通信通过 expvp.lua 模块完成
]]

-- 游戏版本号
local GAME_VERSION = "1.0.1"

-- 引入网络模块（exPvP：联网对战游戏通用框架）
local expvp = require("expvp")

-- ==================== 常量配置 ====================

local W, H = 320, 480  -- 竖屏分辨率（与 HTML 版一致）

-- 玩家尺寸（与 HTML 版一致）
local PLAYER_W = 60
local PLAYER_H = 16
local PLAYER_Y = H - 50 - PLAYER_H - 12  -- 位于底部控制栏上方

-- 金币参数
local COIN_RADIUS = 7
local MAX_COINS = 12
local GRAVITY = 0.255
local GENERATE_FRAMES = 14  -- 约每14帧生成一枚金币（10FPS下约1.4秒/枚）
local WIN_SCORE = 20        -- 先到20分获胜

-- 碰撞冷却（10FPS帧数，约0.8秒）
local COLLISION_COOLDOWN = 8

-- 游戏状态
local STATE = {
    MENU = 'menu',
    ROOM_WAITING = 'room_waiting',
    PLAYING = 'playing',
    PAUSED = 'paused',
    GAME_OVER = 'game_over'
}

-- ==================== 模块内部状态 ====================

local win_id = nil
local main_container = nil
local game_loop_task_running = false
local game_loop_generation = 0

local gameState = STATE.MENU
local networkMode = false
local networkRole = nil

-- 游戏状态管理
local game_state = {
    online_devices = {},
    peer_connected = false,
    peer_ready = false,
    peer_device_id = nil,
    peer_device_model = nil,
    is_host = false,
}

-- 玩家数据（与 HTML 版对应）
local player1 = {
    x = 40,
    y = PLAYER_Y,
    w = PLAYER_W,
    h = PLAYER_H,
    score = 0,
    color = 0x3b82f6,       -- 蓝色
    lightColor = 0x7abfff,
    collisionCooldown = 0,
    device_id = nil,
}
local player2 = {
    x = W - PLAYER_W - 40,
    y = PLAYER_Y,
    w = PLAYER_W,
    h = PLAYER_H,
    score = 0,
    color = 0xef4444,       -- 红色
    lightColor = 0xff8a7a,
    collisionCooldown = 0,
    device_id = nil,
}

-- 金币数组
local coins = {}

-- 碰撞特效
local collisionEffect = { active = false, x = 0, y = 0, timer = 0 }

-- 帧计数器
local frameCounter = 0

-- 游戏运行标志
local gameRunning = true
local score_uploaded = false

-- 触摸拖拽状态（参考 airplane_battle/breakout）
local touch_state = {
    dragging_p1 = false,
    dragging_p2 = false,
    track_id_p1 = nil,
    track_id_p2 = nil,
    offset_p1_x = 0,
    offset_p2_x = 0,
}
-- UI 元素
local ui = {
    menu_container = nil,
    game_container = nil,
    score1_label = nil,
    score2_label = nil,
    score1_name_label = nil,
    score2_name_label = nil,
    status_label = nil,
    pause_btn = nil,
    reset_btn = nil,
    playfield = nil,
    dynamic_layer = nil,
    coin_labels = {},
    player1_obj = nil,
    player2_obj = nil,
    collision_label = nil,
    game_over_overlay = nil,
    winner_label = nil,
    join_dialog_container = nil,
    join_input_label = nil,
    join_tip_label = nil,
    -- 房间UI
    room_container = nil,
    room_status_label = nil,
    room_player_list = {},
    room_ready_btn = nil,
    room_start_btn = nil,
    room_leave_btn = nil,
}

local startLocalGame, showMainMenu, showGameUI, onCreateRoom, showRoomWaitingUI, updateRoomUI, getRoomPlayerCount, renderGameObjects, updateScoreUI, startGameLoop, resetDragState

-- 房间状态
local room_players = {}
local my_player_number = 1
local my_ready = false
local is_host_player = false
local current_room_id = nil
local my_device_id = nil
local player_names = { [1] = "蓝方", [2] = "红方" }
local last_sent_x = nil
local state_sync_counter = 0
local join_input_text = ""
local room_update_timer = nil
local room_ui_active = false
local return_menu_pending = false
local safeReturnMainMenu
local uploadGameScore
local togglePause

local function clearRoomUIRefs()
    ui.room_container = nil
    ui.room_status_label = nil
    ui.room_player_list = {}
    ui.room_ready_btn = nil
    ui.room_start_btn = nil
    ui.room_leave_btn = nil
    room_ui_active = false
end

local function clearGameObjectRefs()
    ui.dynamic_layer = nil
    ui.coin_labels = {}
    ui.player1_obj = nil
    ui.player2_obj = nil
    ui.collision_label = nil
end

-- ==================== 工具函数 ====================

local function clamp(value, min, max)
    if value < min then return min end
    if value > max then return max end
    return value
end

local function normalizeTouchXY(x, y)
    local raw_x, raw_y = x, y
    if y and y > H then
        x = x * W / 720
        y = y * H / 1280
    elseif x and x > W then
        x = x * W / 720
    end
    return x, y, raw_x, raw_y
end

local function getDeviceId()
    local info = expvp.get_player_info()
    return info and info.device_id or "unknown"
end

local function getNickname()
    local info = expvp.get_player_info()
    return info and info.nickname or "玩家"
end

local function shortName(name, max_len)
    name = name or "玩家"
    max_len = max_len or 8
    if #name > max_len then
        return name:sub(1, max_len) .. ".."
    end
    return name
end

local function getPlayerByNumber(num)
    return num == 2 and player2 or player1
end

local function getMyPlayer()
    return getPlayerByNumber(my_player_number)
end

local function sendNetworkMessage(action, data)
    if not networkMode then return end
    my_device_id = my_device_id or getDeviceId()
    local msg = { action = action, from = my_device_id }
    if data then
        for k, v in pairs(data) do
            msg[k] = v
        end
    end
    expvp.broadcast_to_room(msg)
end

local function collectRoomPlayerNames(assignments)
    player_names = { [1] = "蓝方", [2] = "红方" }
    local room_info = expvp.get_room_info()
    local players = room_info and room_info.players or {}
    for device_id, pnum in pairs(assignments or {}) do
        local info = players[device_id]
        local fallback = device_id == (my_device_id or getDeviceId()) and getNickname() or device_id:sub(-6)
        player_names[pnum] = shortName((info and info.nickname) or fallback, 10)
    end
end

local function setVisible(obj, visible)
    if not obj then return end
    if visible then
        if obj.open then
            obj:open()
        elseif obj.show then
            obj:show()
        end
    else
        if obj.hide then obj:hide() end
    end
end

local function safeSetText(obj, text)
    if not obj then return end
    pcall(function()
        obj:set_text(text or "")
    end)
end

safeReturnMainMenu = function(notify_peer)
    if return_menu_pending then return end
    return_menu_pending = true

    if uploadGameScore and (gameState == STATE.PLAYING or gameState == STATE.PAUSED or gameState == STATE.GAME_OVER) then
        uploadGameScore()
    end
    if notify_peer ~= false and networkMode and current_room_id then
        sendNetworkMessage("leave", {})
        if expvp.leave_room then expvp.leave_room() end
    end

    current_room_id = nil
    networkMode = false
    is_host_player = false
    my_ready = false
    gameRunning = false
    room_ui_active = false
    resetDragState()
    game_loop_generation = game_loop_generation + 1
    game_loop_task_running = false
    if room_update_timer then
        sys.timerStop(room_update_timer)
        room_update_timer = nil
    end
    sys.timerStart(function()
        return_menu_pending = false
        showMainMenu()
    end, 50)
end

togglePause = function()
    if gameState == STATE.PLAYING then
        gameState = STATE.PAUSED
        gameRunning = false
        if ui.pause_btn then ui.pause_btn:set_text("继续") end
        if ui.status_label then
            ui.status_label:set_text("暂停中")
        end
    elseif gameState == STATE.PAUSED then
        gameState = STATE.PLAYING
        gameRunning = true
        if ui.pause_btn then ui.pause_btn:set_text("暂停") end
        updateScoreUI()
        startGameLoop()
    end
end

-- ==================== 游戏逻辑（移植自 coin_clash.html） ====================

-- 初始化/重置游戏
local function initGame()
    player1.score = 0
    player2.score = 0
    score_uploaded = false
    player1.collisionCooldown = 0
    player2.collisionCooldown = 0
    player1.x = 40
    player2.x = W - PLAYER_W - 40
    
    coins = {}
    -- 初始生成 3~5 枚金币，降低同时渲染对象数量
    local startCoins = math.random(3, 5)
    for i = 1, startCoins do
        coins[i] = {
            x = math.random(COIN_RADIUS, W - COIN_RADIUS),
            y = -COIN_RADIUS - math.random(0, 22),
            vy = math.random() * 2.7 + 1.8,
            radius = COIN_RADIUS,
        }
    end
    
    frameCounter = 0
    collisionEffect.active = false
    gameRunning = true
    touch_state.dragging_p1 = false
    touch_state.dragging_p2 = false
    touch_state.track_id_p1 = nil
    touch_state.track_id_p2 = nil
    touch_state.offset_p1_x = 0
    touch_state.offset_p2_x = 0
    
    log.info("coin_clash", "game init, coins:", #coins)
end

-- 重置单枚金币
local function resetCoin(coin)
    coin.x = math.random(COIN_RADIUS, W - COIN_RADIUS)
    coin.y = -COIN_RADIUS - math.random(0, 18)
    coin.vy = math.random() * 2.7 + 1.8
end

-- 添加新金币
local function addNewCoin()
    if #coins >= MAX_COINS then return end
    table.insert(coins, {
        x = math.random(COIN_RADIUS, W - COIN_RADIUS),
        y = -COIN_RADIUS - math.random(0, 22),
        vy = math.random() * 2.7 + 1.8,
        radius = COIN_RADIUS,
    })
end

-- 矩形圆形碰撞检测
local function rectCircleCollide(rx, ry, rw, rh, cx, cy, radius)
    local closestX = clamp(cx, rx, rx + rw)
    local closestY = clamp(cy, ry, ry + rh)
    local dx = cx - closestX
    local dy = cy - closestY
    return (dx * dx + dy * dy) < (radius * radius)
end

-- 处理金币碰撞（接金币）
local function handleCoinCollisions()
    for i = #coins, 1, -1 do
        local coin = coins[i]
        if rectCircleCollide(player1.x, player1.y, player1.w, player1.h, coin.x, coin.y, coin.radius) then
            player1.score = player1.score + 1
            resetCoin(coin)
        elseif rectCircleCollide(player2.x, player2.y, player2.w, player2.h, coin.x, coin.y, coin.radius) then
            player2.score = player2.score + 1
            resetCoin(coin)
        end
    end
end

-- 更新金币位置
local function updateCoins()
    for _, coin in ipairs(coins) do
        coin.vy = coin.vy + GRAVITY
        coin.y = coin.y + coin.vy
        if coin.y - coin.radius >= H - 50 or coin.y + coin.radius < -40 then
            resetCoin(coin)
        end
        coin.x = clamp(coin.x, coin.radius, W - coin.radius)
    end
end

-- 尝试生成新金币
local function tryGenerateCoin()
    if not gameRunning then return end
    frameCounter = frameCounter + 1
    if frameCounter >= GENERATE_FRAMES and #coins < MAX_COINS then
        addNewCoin()
        frameCounter = 0
    end
    if frameCounter >= GENERATE_FRAMES * 2 then
        frameCounter = 0
    end
end

-- 处理玩家碰撞（互相扣分 + 推开）
local function handlePlayerCollision()
    if player1.collisionCooldown > 0 then
        player1.collisionCooldown = player1.collisionCooldown - 1
    end
    if player2.collisionCooldown > 0 then
        player2.collisionCooldown = player2.collisionCooldown - 1
    end
    
    -- AABB 碰撞检测
    local overlap = not (
        player1.x + player1.w <= player2.x or
        player2.x + player2.w <= player1.x or
        player1.y + player1.h <= player2.y or
        player2.y + player2.h <= player1.y
    )
    
    if overlap then
        if player1.collisionCooldown == 0 and player2.collisionCooldown == 0 then
            player1.score = math.max(0, player1.score - 1)
            player2.score = math.max(0, player2.score - 1)
            
            player1.collisionCooldown = COLLISION_COOLDOWN
            player2.collisionCooldown = COLLISION_COOLDOWN
            
            collisionEffect.active = true
            collisionEffect.timer = 4
            collisionEffect.x = (player1.x + player2.x + player1.w) / 2
            collisionEffect.y = PLAYER_Y - 18
            
            log.info("coin_clash", "collision! P1:", player1.score, "P2:", player2.score)
        end
        
        -- 推开逻辑
        local dx = (player1.x + player1.w / 2) - (player2.x + player2.w / 2)
        local pushForce = 6
        if dx > 0 then
            player1.x = clamp(player1.x + pushForce, 0, W - player1.w)
            player2.x = clamp(player2.x - pushForce, 0, W - player2.w)
        elseif dx < 0 then
            player1.x = clamp(player1.x - pushForce, 0, W - player1.w)
            player2.x = clamp(player2.x + pushForce, 0, W - player2.w)
        else
            player1.x = clamp(player1.x - 5, 0, W - player1.w)
            player2.x = clamp(player2.x + 5, 0, W - player2.w)
        end
    end
    
    player1.x = clamp(player1.x, 0, W - player1.w)
    player2.x = clamp(player2.x, 0, W - player2.w)
end

resetDragState = function()
    touch_state.dragging_p1 = false
    touch_state.dragging_p2 = false
    touch_state.track_id_p1 = nil
    touch_state.track_id_p2 = nil
    touch_state.offset_p1_x = 0
    touch_state.offset_p2_x = 0
end

local function movePlayerTo(player, x, offset_x)
    if gameState ~= STATE.PLAYING then return end
    player.x = clamp(x - offset_x, 0, W - player.w)
    local obj = player == player1 and ui.player1_obj or ui.player2_obj
    if obj then
        obj:set_pos(math.floor(player.x), math.floor(player.y - 82))
    else
        renderGameObjects()
    end
end

local function sendMyPosition(force)
    if not networkMode then return end
    local my_player = getMyPlayer()
    local x = math.floor(my_player.x)
    if force or last_sent_x == nil or math.abs(x - last_sent_x) >= 2 then
        last_sent_x = x
        sendNetworkMessage("move", { player = my_player_number, x = x })
    end
end

-- 胜利判定
local function checkWinCondition()
    if player1.score >= WIN_SCORE or player2.score >= WIN_SCORE then
        gameRunning = false
        return true
    end
    return false
end

-- 获取状态提示文字
local function getStatusText()
    if player1.score >= WIN_SCORE then
        return "蓝方" .. WIN_SCORE .. "分胜利!"
    elseif player2.score >= WIN_SCORE then
        return "红方" .. WIN_SCORE .. "分胜利!"
    elseif player1.score > player2.score then
        return "蓝方领先! 碰撞扣分!"
    elseif player2.score > player1.score then
        return "红方领先! 撞击对手减分"
    else
        return "均势, 躲避碰撞同时接币"
    end
end

-- ==================== UI 更新 ====================

local function getScoreName(side)
    if side == 1 then
        return networkMode and ("蓝方 " .. shortName(player_names[1] or "蓝方", 8)) or "蓝方"
    end
    return networkMode and ("红方 " .. shortName(player_names[2] or "红方", 8)) or "红方"
end

-- 更新分数显示和状态文字
updateScoreUI = function()
    if ui.score1_name_label then
        ui.score1_name_label:set_text(getScoreName(1))
    end
    if ui.score2_name_label then
        ui.score2_name_label:set_text(getScoreName(2))
    end
    if ui.score1_label then
        ui.score1_label:set_text(tostring(player1.score))
    end
    if ui.score2_label then
        ui.score2_label:set_text(tostring(player2.score))
    end
    if ui.status_label then
        ui.status_label:set_text(getStatusText())
    end
end

local function ensureGameObjectLayer()
    if not ui.playfield then return false end
    if not ui.dynamic_layer then
        ui.dynamic_layer = airui.container({
            parent = ui.playfield,
            x = 0, y = 0,
            w = W, h = H - 132,
            color = 0x1e2b2c,
        })
        ui.coin_labels = {}
        for i = 1, MAX_COINS do
            ui.coin_labels[i] = airui.label({
                parent = ui.dynamic_layer,
                x = -30, y = -30,
                w = 16, h = 16,
                text = "$",
                color = 0xfacc15,
                font_size = 16,
                align = airui.TEXT_ALIGN_CENTER,
            })
            setVisible(ui.coin_labels[i], false)
        end
        ui.player1_obj = airui.container({
            parent = ui.dynamic_layer,
            x = player1.x, y = player1.y - 82,
            w = player1.w, h = player1.h,
            color = player1.color,
            radius = 6,
        })
        ui.player2_obj = airui.container({
            parent = ui.dynamic_layer,
            x = player2.x, y = player2.y - 82,
            w = player2.w, h = player2.h,
            color = player2.color,
            radius = 6,
        })
        ui.collision_label = airui.label({
            parent = ui.dynamic_layer,
            x = -80, y = -40,
            w = 60, h = 22,
            text = "碰撞 -1",
            color = 0xffd966,
            font_size = 12,
            align = airui.TEXT_ALIGN_CENTER,
        })
        setVisible(ui.collision_label, false)
    end
    return true
end

renderGameObjects = function()
    if not ensureGameObjectLayer() then return end

    for i = 1, MAX_COINS do
        local label = ui.coin_labels[i]
        local coin = coins[i]
        if label and coin then
            label:set_pos(math.floor(coin.x - 8), math.floor(coin.y - 90))
            setVisible(label, true)
        elseif label then
            setVisible(label, false)
        end
    end

    if ui.player1_obj then
        ui.player1_obj:set_pos(math.floor(player1.x), math.floor(player1.y - 82))
    end
    if ui.player2_obj then
        ui.player2_obj:set_pos(math.floor(player2.x), math.floor(player2.y - 82))
    end

    if ui.collision_label then
        if collisionEffect.active then
            ui.collision_label:set_pos(math.floor(collisionEffect.x - 30), math.floor(collisionEffect.y - 82))
            setVisible(ui.collision_label, true)
        else
            setVisible(ui.collision_label, false)
        end
    end
end

local function makeStateSnapshot()
    local coin_list = {}
    for i, coin in ipairs(coins) do
        coin_list[i] = { x = coin.x, y = coin.y, vy = coin.vy, radius = coin.radius }
    end
    return {
        p1x = player1.x,
        p2x = player2.x,
        p1score = player1.score,
        p2score = player2.score,
        coins = coin_list,
        effect = {
            active = collisionEffect.active,
            x = collisionEffect.x,
            y = collisionEffect.y,
            timer = collisionEffect.timer,
        },
    }
end

local function applyStateSnapshot(data)
    if not data then return end
    player1.x = data.p1x or player1.x
    player2.x = data.p2x or player2.x
    player1.score = data.p1score or player1.score
    player2.score = data.p2score or player2.score
    if data.coins then
        coins = {}
        for i, coin in ipairs(data.coins) do
            coins[i] = {
                x = coin.x,
                y = coin.y,
                vy = coin.vy or 0,
                radius = coin.radius or COIN_RADIUS,
            }
        end
    end
    if data.effect then
        collisionEffect.active = data.effect.active or false
        collisionEffect.x = data.effect.x or 0
        collisionEffect.y = data.effect.y or 0
        collisionEffect.timer = data.effect.timer or 0
    end
    updateScoreUI()
    renderGameObjects()
end

local function broadcastStateSnapshot(force)
    if not networkMode or not is_host_player then return end
    state_sync_counter = state_sync_counter + 1
    if force or state_sync_counter >= 3 then
        state_sync_counter = 0
        sendNetworkMessage("state", makeStateSnapshot())
    end
end

-- ==================== 游戏主循环 ====================

local function gameLoop()
    if gameState ~= STATE.PLAYING and gameState ~= STATE.PAUSED then
        return
    end
    
    if gameRunning and gameState == STATE.PLAYING then
        if (not networkMode) or is_host_player then
            handlePlayerCollision()
            updateCoins()
            handleCoinCollisions()
            tryGenerateCoin()
            
            if checkWinCondition() then
                if networkMode then
                    sendNetworkMessage("game_over", makeStateSnapshot())
                end
                showGameOver()
                return
            end
            
            updateScoreUI()
            renderGameObjects()
            broadcastStateSnapshot(false)
        else
            updateScoreUI()
            renderGameObjects()
        end
    end
end

startGameLoop = function()
    if game_loop_task_running then
        return
    end
    game_loop_generation = game_loop_generation + 1
    local generation = game_loop_generation
    game_loop_task_running = true
    sys.taskInit(function()
        while game_loop_task_running and generation == game_loop_generation do
            if gameState == STATE.PLAYING or gameState == STATE.PAUSED then
                gameLoop()
            end
            sys.wait(100)
        end
    end)
end

local function stopGameLoop()
    game_loop_generation = game_loop_generation + 1
    game_loop_task_running = false
end

uploadGameScore = function()
    if score_uploaded then return end
    score_uploaded = true

    local scoreEarned
    if networkMode then
        local myPlayer = getMyPlayer()
        scoreEarned = myPlayer and myPlayer.score or 0
    else
        scoreEarned = math.max(player1.score, player2.score)
    end
    scoreEarned = math.max(0, tonumber(scoreEarned) or 0)
    if scoreEarned == 0 then return end

    expvp.add_local_score(scoreEarned)
    expvp.upload_local_score(function(success, total)
        if success then
            log.info("coin_clash", "积分上传成功", "本局", scoreEarned, "累计", total or 0)
        else
            log.warn("coin_clash", "积分上传失败", "本局", scoreEarned)
        end
    end)
end

-- ==================== 游戏结束界面 ====================

function showGameOver()
    gameState = STATE.GAME_OVER
    stopGameLoop()
    uploadGameScore()
    
    if not ui.game_container then return end
    
    -- 创建半透明覆盖层
    ui.game_over_overlay = airui.container({
        parent = ui.game_container,
        x = 0, y = 0,
        w = W, h = H,
        color = 0x000000,
        alpha = 180,
    })
    
    -- 获胜提示
    local winnerText
    local winnerColor
    if player1.score >= WIN_SCORE then
        winnerText = "蓝方胜利！"
        winnerColor = 0x7abfff
    else
        winnerText = "红方胜利！"
        winnerColor = 0xff8a7a
    end
    
    ui.winner_label = airui.label({
        parent = ui.game_over_overlay,
        x = 0, y = H / 2 - 60,
        w = W, h = 40,
        text = winnerText,
        color = winnerColor,
        font_size = 18,
        align = airui.TEXT_ALIGN_CENTER,
    })
    
    -- 分数显示
    local scoreText = "蓝方 " .. player1.score .. " : " .. player2.score .. " 红方"
    airui.label({
        parent = ui.game_over_overlay,
        x = 0, y = H / 2 - 20,
        w = W, h = 30,
        text = scoreText,
        color = 0xffd966,
        font_size = 14,
        align = airui.TEXT_ALIGN_CENTER,
    })
    
    -- 重开按钮
    ui.restart_btn = airui.button({
        parent = ui.game_over_overlay,
        x = (W - 100) / 2, y = H / 2 + 20,
        w = 100, h = 36,
        text = "重开",
        font_size = 14,
        style = {
            bg_color = 0xfacc15,
            text_color = 0x1f2e1c,
            border_width = 0,
            radius = 18,
            pressed_bg_color = 0xb97f10,
        },
        on_click = function()
            hideGameOver()
            startLocalGame()
        end,
    })
    
    -- 返回菜单按钮
    ui.back_menu_btn = airui.button({
        parent = ui.game_over_overlay,
        x = (W - 100) / 2, y = H / 2 + 66,
        w = 100, h = 36,
        text = "返回菜单",
        font_size = 14,
        style = {
            bg_color = 0x2a3f5f,
            text_color = 0xffffff,
            border_width = 0,
            radius = 18,
        },
        on_click = function()
            hideGameOver()
            safeReturnMainMenu()
        end,
    })
    
    log.info("coin_clash", "game over, P1:", player1.score, "P2:", player2.score)
end

function hideGameOver()
    if ui.game_over_overlay then
        ui.game_over_overlay:destroy()
        ui.game_over_overlay = nil
    end
    ui.winner_label = nil
    ui.restart_btn = nil
    ui.back_menu_btn = nil
end

-- ==================== 开始本地游戏 ====================

startLocalGame = function()
    log.info("coin_clash", "start local game")
    gameState = STATE.PLAYING
    networkMode = false
    
    initGame()
    showGameUI()
    updateScoreUI()
    renderGameObjects()
    startGameLoop()
end

-- ==================== UI 构建：主菜单 ====================

local function buildMainMenu()
    if ui.menu_container then
        pcall(function() ui.menu_container:destroy() end)
        ui.menu_container = nil
    end
    
    ui.menu_container = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = W, h = H,
        color = 0x071916,
    })
    
    -- 顶部深色背景区
    airui.container({
        parent = ui.menu_container,
        x = 0, y = 0,
        w = W, h = H,
        color = 0x0a2f2a,
    })
    
    -- 标题卡片
    airui.container({
        parent = ui.menu_container,
        x = 18, y = 42,
        w = W - 36, h = 104,
        color = 0x102b2a,
        radius = 16,
    })
    
    airui.label({
        parent = ui.menu_container,
        x = 0, y = 58,
        w = W, h = 42,
        text = "接金币对决",
        font_size = 30,
        color = 0xfacc15,
        align = airui.TEXT_ALIGN_CENTER,
    })
    
    airui.label({
        parent = ui.menu_container,
        x = 0, y = 104,
        w = W, h = 22,
        text = "碰撞扣分 $ 接币抢分",
        font_size = 14,
        color = 0xb9f2df,
        align = airui.TEXT_ALIGN_CENTER,
    })
    
    -- 底部装饰金币线
    -- for i = 1, 7 do
        -- airui.label({
            -- parent = ui.menu_container,
            -- x = 36 + (i - 1) * 38, y = 418,
            -- w = 20, h = 20,
            -- text = "$",
            -- font_size = 16,
            -- color = 0xfacc15,
            -- align = airui.TEXT_ALIGN_CENTER,
        -- })
    -- end
    
    local btn_w = 210
    local btn_h = 34
    local btn_x = (W - btn_w) / 2
    local btn_gap = 8
    local start_y = 174
    
    local function addMenuButton(index, text, bg_color, text_color, on_click)
        airui.button({
            parent = ui.menu_container,
            x = btn_x,
            y = start_y + (btn_h + btn_gap) * index,
            w = btn_w,
            h = btn_h,
            text = text,
            font_size = 16,
            style = {
                bg_color = bg_color,
                text_color = text_color or 0xffffff,
                border_width = 0,
                radius = 17,
                pressed_bg_color = 0x0f3a35,
            },
            on_click = on_click,
        })
    end
    
    addMenuButton(0, "单机对战", 0xfacc15, 0x1f2e1c, function()
        startLocalGame()
    end)
    
    addMenuButton(1, "创建房间", 0x25635a, 0xffffff, function()
        onCreateRoom()
    end)
    
    addMenuButton(2, "加入房间", 0x25635a, 0xffffff, function()
        showJoinDialog()
    end)
    
    addMenuButton(3, "积分排行榜", 0x2a3f5f, 0xffffff, function()
        openLeaderboard()
    end)
    
    addMenuButton(4, "帮助", 0x2a3f5f, 0xffffff, function()
        showHelpDialog()
    end)
    
    addMenuButton(5, "退出", 0x884444, 0xffffff, function()
        if win_id then
            exwin.close(win_id)
        end
    end)
    
    airui.label({
        parent = ui.menu_container,
        x = 0, y = H - 26,
        w = W - 12, h = 18,
        text = "v" .. GAME_VERSION,
        color = 0x7c8f8b,
        font_size = 12,
        align = airui.TEXT_ALIGN_RIGHT,
    })
end

-- ==================== 显示/隐藏 UI ====================

showMainMenu = function()
    log.info("coin_clash", "showMainMenu")
    gameState = STATE.MENU
    networkMode = false
    is_host_player = false
    current_room_id = nil
    my_ready = false
    stopGameLoop()
    
    if ui.game_container then
        pcall(function() ui.game_container:destroy() end)
        ui.game_container = nil
        clearGameObjectRefs()
    end
    if room_update_timer then
        sys.timerStop(room_update_timer)
        room_update_timer = nil
    end
    if ui.room_container then
        room_ui_active = false
        pcall(function() ui.room_container:destroy() end)
        clearRoomUIRefs()
    end
    buildMainMenu()
end

showGameUI = function()
    log.info("coin_clash", "showGameUI")
    if ui.menu_container then
        pcall(function() ui.menu_container:destroy() end)
        ui.menu_container = nil
    end
    if room_update_timer then
        sys.timerStop(room_update_timer)
        room_update_timer = nil
    end
    if ui.room_container then
        room_ui_active = false
        pcall(function() ui.room_container:destroy() end)
    end
    clearRoomUIRefs()
    if ui.game_container then
        pcall(function() ui.game_container:destroy() end)
        ui.game_container = nil
        clearGameObjectRefs()
    end
    buildGameUI()
end

-- ==================== UI 构建：游戏界面 ====================

function buildGameUI()
    if ui.game_container then
        pcall(function() ui.game_container:destroy() end)
        clearGameObjectRefs()
    end
    
    ui.game_container = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = W, h = H,
        color = 0x1e2a2a,
    })
    
    -- ======== 顶部分数面板 ========
    local score_panel = airui.container({
        parent = ui.game_container,
        x = 0, y = 0,
        w = W, h = 60,
        color = 0x111a1a,
    })
    
    -- P1 分数卡片
    local p1_card = airui.container({
        parent = score_panel,
        x = 4, y = 6,
        w = 130, h = 48,
        color = 0x0f2c3b,
        radius = 8,
    })
    ui.score1_name_label = airui.label({
        parent = p1_card,
        x = 0, y = 4,
        w = 130, h = 18,
        text = getScoreName(1),
        color = 0x7abfff,
        font_size = 10,
        align = airui.TEXT_ALIGN_CENTER,
    })
    ui.score1_label = airui.label({
        parent = p1_card,
        x = 0, y = 22,
        w = 130, h = 24,
        text = "0",
        color = 0xffffff,
        font_size = 20,
        align = airui.TEXT_ALIGN_CENTER,
    })
    
    -- VS 徽章
    airui.label({
        parent = score_panel,
        x = (W - 40) / 2, y = 14,
        w = 40, h = 30,
        text = "VS",
        color = 0xfacc15,
        font_size = 14,
        align = airui.TEXT_ALIGN_CENTER,
    })
    
    -- P2 分数卡片
    local p2_card = airui.container({
        parent = score_panel,
        x = W - 134, y = 6,
        w = 130, h = 48,
        color = 0x3b1e2a,
        radius = 8,
    })
    ui.score2_name_label = airui.label({
        parent = p2_card,
        x = 0, y = 4,
        w = 130, h = 18,
        text = getScoreName(2),
        color = 0xff9e8f,
        font_size = 10,
        align = airui.TEXT_ALIGN_CENTER,
    })
    ui.score2_label = airui.label({
        parent = p2_card,
        x = 0, y = 22,
        w = 130, h = 24,
        text = "0",
        color = 0xffffff,
        font_size = 20,
        align = airui.TEXT_ALIGN_CENTER,
    })
    
    -- ======== 状态提示 ========
    ui.status_label = airui.label({
        parent = ui.game_container,
        x = 0, y = 62,
        w = W, h = 20,
        text = "✨ 碰撞扣分 + 接金币 ✨",
        color = 0xffde9c,
        font_size = 10,
        align = airui.TEXT_ALIGN_CENTER,
    })
    
    -- ======== 游戏区域 ========
    local game_area_h = H - 82 - 50
    ui.playfield = airui.container({
        parent = ui.game_container,
        x = 0, y = 82,
        w = W, h = game_area_h,
        color = 0x1e2b2c,
    })
    
    -- 底部装饰线
    airui.container({
        parent = ui.playfield,
        x = 0, y = game_area_h - 18,
        w = W, h = 18,
        color = 0xe9b56e,
        alpha = 32,
    })
    
    -- ======== 底部控制栏 ========
    local ctrl_bar = airui.container({
        parent = ui.game_container,
        x = 0, y = H - 50,
        w = W, h = 50,
        color = 0x111a1a,
    })
    
    -- 返回按钮
    ui.reset_btn = airui.button({
        parent = ctrl_bar,
        x = (W - 60) / 2 - 35, y = 8,
        w = 60, h = 32,
        text = "返回",
        font_size = 12,
        style = {
            bg_color = 0xfacc15,
            text_color = 0x1f2e1c,
            border_width = 0,
            radius = 16,
            pressed_bg_color = 0xb97f10,
        },
        on_click = function()
            safeReturnMainMenu()
        end,
    })
    
    -- 暂停按钮
    ui.pause_btn = airui.button({
        parent = ctrl_bar,
        x = (W - 60) / 2 + 35, y = 8,
        w = 60, h = 32,
        text = "暂停",
        font_size = 12,
        style = {
            bg_color = 0xfacc15,
            text_color = 0x1f2e1c,
            border_width = 0,
            radius = 16,
            pressed_bg_color = 0xb97f10,
        },
        on_click = function()
            if gameState == STATE.PLAYING then
                gameState = STATE.PAUSED
                gameRunning = false
                ui.pause_btn:set_text("继续")
                if ui.status_label then
                    ui.status_label:set_text("暂停中")
                end
            elseif gameState == STATE.PAUSED then
                gameState = STATE.PLAYING
                gameRunning = true
                ui.pause_btn:set_text("暂停")
                updateScoreUI()
                startGameLoop()
            end
        end,
    })
end

-- ==================== 联网对战功能 ====================

-- 创建房间
onCreateRoom = function()
    log.info("coin_clash", "create room")
    my_ready = false
    gameState = STATE.ROOM_WAITING
    networkMode = true
    is_host_player = true
    
    local room_id = expvp.create_room()
    current_room_id = room_id
    
    showRoomWaitingUI(room_id)
end

local function showRoomTip(text, color)
    if ui.join_tip_label then
        safeSetText(ui.join_tip_label, text or "")
        if color and ui.join_tip_label.set_color then
            pcall(function()
                ui.join_tip_label:set_color(color)
            end)
        end
    elseif room_ui_active and ui.room_container and ui.room_status_label then
        safeSetText(ui.room_status_label, text or "")
    end
end

local function onJoinRoom(room_id)
    if not room_id or #room_id ~= 6 then
        showRoomTip("请输入6位房间号", 0xff8888)
        return
    end
    log.info("coin_clash", "join room", room_id)
    my_ready = false
    is_host_player = false
    gameState = STATE.ROOM_WAITING
    networkMode = true
    my_device_id = my_device_id or getDeviceId()
    expvp.join_room(room_id)
    current_room_id = room_id
    showRoomWaitingUI(room_id)
    sys.timerStart(function()
        if room_ui_active then updateRoomUI() end
    end, 300)
    sys.timerStart(function()
        if room_ui_active then updateRoomUI() end
    end, 1200)
end

getRoomPlayerCount = function(room_info)
    local count = 0
    for _ in pairs((room_info and room_info.players) or {}) do
        count = count + 1
    end
    return count
end

-- 显示加入房间对话框
function showJoinDialog()
    log.info("coin_clash", "show join dialog")
    if ui.join_dialog_container then
        ui.join_dialog_container:destroy()
        ui.join_dialog_container = nil
    end
    join_input_text = ""

    ui.join_dialog_container = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = W, h = H,
        color = 0x0a0f1e,
    })

    airui.label({
        parent = ui.join_dialog_container,
        x = 0, y = 46,
        w = W, h = 34,
        text = "加入房间",
        color = 0xfacc15,
        font_size = 22,
        align = airui.TEXT_ALIGN_CENTER,
    })

    ui.join_tip_label = airui.label({
        parent = ui.join_dialog_container,
        x = 0, y = 86,
        w = W, h = 24,
        text = "请输入房主分享的6位房间号",
        color = 0xb9f2df,
        font_size = 12,
        align = airui.TEXT_ALIGN_CENTER,
    })

    ui.join_input_label = airui.label({
        parent = ui.join_dialog_container,
        x = 40, y = 126,
        w = W - 80, h = 46,
        text = "------",
        color = 0xffffff,
        font_size = 24,
        align = airui.TEXT_ALIGN_CENTER,
    })

    local function refreshInput()
        local text = join_input_text
        while #text < 6 do text = text .. "-" end
        if ui.join_input_label then
            ui.join_input_label:set_text(text)
        end
    end

    local key_w, key_h, gap = 64, 42, 10
    local start_x = (W - key_w * 3 - gap * 2) / 2
    local start_y = 200
    for i = 1, 9 do
        local n = tostring(i)
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        airui.button({
            parent = ui.join_dialog_container,
            x = start_x + col * (key_w + gap), y = start_y + row * (key_h + gap),
            w = key_w, h = key_h,
            text = n,
            font_size = 18,
            style = { bg_color = 0x25635a, text_color = 0xffffff, border_width = 0, radius = 8 },
            on_click = function()
                if #join_input_text < 6 then
                    join_input_text = join_input_text .. n
                    refreshInput()
                end
            end,
        })
    end

    local row4_y = start_y + 3 * (key_h + gap)
    airui.button({
        parent = ui.join_dialog_container,
        x = start_x, y = row4_y,
        w = key_w, h = key_h,
        text = "0",
        font_size = 18,
        style = { bg_color = 0x25635a, text_color = 0xffffff, border_width = 0, radius = 8 },
        on_click = function()
            if #join_input_text < 6 then
                join_input_text = join_input_text .. "0"
                refreshInput()
            end
        end,
    })
    airui.button({
        parent = ui.join_dialog_container,
        x = start_x + key_w + gap, y = row4_y,
        w = key_w * 2 + gap, h = key_h,
        text = "删除",
        font_size = 16,
        style = { bg_color = 0x884444, text_color = 0xffffff, border_width = 0, radius = 8 },
        on_click = function()
            if #join_input_text > 0 then
                join_input_text = join_input_text:sub(1, -2)
                refreshInput()
            end
        end,
    })

    airui.button({
        parent = ui.join_dialog_container,
        x = 50, y = H - 50,
        w = 100, h = 36,
        text = "加入",
        font_size = 16,
        style = { bg_color = 0xfacc15, text_color = 0x1f2e1c, border_width = 0, radius = 18 },
        on_click = function()
            local room_id = join_input_text
            if ui.join_dialog_container then
                ui.join_dialog_container:destroy()
                ui.join_dialog_container = nil
                ui.join_input_label = nil
                ui.join_tip_label = nil
            end
            onJoinRoom(room_id)
        end,
    })
    airui.button({
        parent = ui.join_dialog_container,
        x = W - 150, y = H - 50,
        w = 100, h = 36,
        text = "取消",
        font_size = 16,
        style = { bg_color = 0x2a3f5f, text_color = 0xffffff, border_width = 0, radius = 18 },
        on_click = function()
            if ui.join_dialog_container then
                ui.join_dialog_container:destroy()
                ui.join_dialog_container = nil
                ui.join_input_label = nil
                ui.join_tip_label = nil
            end
        end,
    })
end

-- 显示房间等待界面
showRoomWaitingUI = function(room_id)
    room_ui_active = false
    if room_update_timer then
        sys.timerStop(room_update_timer)
        room_update_timer = nil
    end
    if ui.menu_container then
        pcall(function() ui.menu_container:destroy() end)
        ui.menu_container = nil
    end
    if ui.room_container then
        pcall(function() ui.room_container:destroy() end)
        clearRoomUIRefs()
    end

    ui.room_container = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = W, h = H,
        color = 0x0a0f1e,
    })
    room_ui_active = true

    airui.label({
        parent = ui.room_container,
        x = 0, y = 40,
        w = W, h = 30,
        text = "房间号: " .. (room_id or "----"),
        color = 0xffd966,
        font_size = 16,
        align = airui.TEXT_ALIGN_CENTER,
    })

    ui.room_status_label = airui.label({
        parent = ui.room_container,
        x = 0, y = 80,
        w = W, h = 24,
        text = "等待玩家加入...",
        color = 0xb9f2df,
        font_size = 13,
        align = airui.TEXT_ALIGN_CENTER,
    })

    for i = 1, 2 do
        local y = 125 + (i - 1) * 38
        local bg = airui.container({
            parent = ui.room_container,
            x = 20, y = y,
            w = W - 40, h = 32,
            color = 0x16213e,
            radius = 6,
        })
        local label = airui.label({
            parent = ui.room_container,
            x = 30, y = y + 7,
            w = W - 140, h = 18,
            text = "玩家" .. i .. ": 等待加入...",
            color = 0xffffff,
            font_size = 13,
            align = airui.TEXT_ALIGN_LEFT,
        })
        local ready_label = airui.label({
            parent = ui.room_container,
            x = W - 105, y = y + 7,
            w = 75, h = 18,
            text = "---",
            color = 0x666666,
            font_size = 13,
            align = airui.TEXT_ALIGN_RIGHT,
        })
        ui.room_player_list[i] = { bg = bg, label = label, ready_label = ready_label }
    end

    local room_btn_w = 190
    local room_btn_h = 38
    local room_btn_x = (W - room_btn_w) / 2
    local room_btn_y = 218
    local room_btn_gap = 12

    ui.room_ready_btn = airui.button({
        parent = ui.room_container,
        x = room_btn_x, y = room_btn_y,
        w = room_btn_w, h = room_btn_h,
        text = "准备",
        font_size = 16,
        style = { bg_color = 0x2a5f3f, text_color = 0xffffff, border_width = 0, radius = 19 },
        on_click = function()
            if not room_ui_active then return end
            my_ready = not my_ready
            expvp.set_ready(my_ready)
            updateRoomUI()
        end,
    })

    ui.room_start_btn = airui.button({
        parent = ui.room_container,
        x = room_btn_x, y = room_btn_y + room_btn_h + room_btn_gap,
        w = room_btn_w, h = room_btn_h,
        text = "开始游戏",
        font_size = 16,
        style = { bg_color = 0x3f5f2a, text_color = 0xffffff, border_width = 0, radius = 19 },
        on_click = function()
            if not room_ui_active or not is_host_player then return end
            local room_info = expvp.get_room_info()
            if getRoomPlayerCount(room_info) < 2 then
                showRoomTip("需要2名玩家才能开始", 0xff8888)
                return
            end
            if not expvp.is_all_ready() then
                showRoomTip("等待双方准备", 0xffd966)
                return
            end
            expvp.start_game()
        end,
    })

    ui.room_leave_btn = airui.button({
        parent = ui.room_container,
        x = room_btn_x, y = room_btn_y + (room_btn_h + room_btn_gap) * 2,
        w = room_btn_w, h = room_btn_h,
        text = "离开房间",
        font_size = 16,
        style = { bg_color = 0x884444, text_color = 0xffffff, border_width = 0, radius = 19 },
        on_click = function()
            safeReturnMainMenu()
        end,
    })

    if ui.room_status_label then
        safeSetText(ui.room_status_label, "房间号: " .. (room_id or "----") .. "  等待玩家加入...")
    end
    if ui.room_start_btn then
        setVisible(ui.room_start_btn, is_host_player)
    end
    updateRoomUI()
    if room_update_timer then
        sys.timerStop(room_update_timer)
    end
    room_update_timer = sys.timerLoopStart(updateRoomUI, 1000)
end

-- 隐藏房间等待界面
local function hideRoomWaitingUI()
    room_ui_active = false
    if room_update_timer then
        sys.timerStop(room_update_timer)
        room_update_timer = nil
    end
    if ui.room_container then
        pcall(function() ui.room_container:destroy() end)
    end
    clearRoomUIRefs()
end

-- 更新房间UI（玩家列表、准备状态）
updateRoomUI = function()
    if not room_ui_active or gameState ~= STATE.ROOM_WAITING or not ui.room_container then return end
    local room_info = expvp.get_room_info()
    if not room_info or not ui.room_player_list then return end
    is_host_player = room_info.is_host
    my_ready = room_info.my_ready
    current_room_id = room_info.room_id or current_room_id
    
    local player_slots = {}
    local slot = 1
    local my_id = my_device_id or getDeviceId()
    local players = room_info.players or {}
    if players[my_id] then
        local player = players[my_id]
        player_slots[slot] = {
            nickname = (player.nickname or getNickname()) .. " [你]" .. (player.is_host and " (房主)" or ""),
            ready = my_ready,
        }
        slot = slot + 1
    elseif current_room_id then
        player_slots[slot] = {
            nickname = getNickname() .. " [你]" .. (is_host_player and " (房主)" or ""),
            ready = my_ready,
        }
        slot = slot + 1
    end
    for did, player in pairs(players) do
        if did ~= my_id and slot <= 2 then
            player_slots[slot] = {
                nickname = (player.nickname or did:sub(-6)) .. (player.is_host and " (房主)" or ""),
                ready = player.ready or false,
            }
            slot = slot + 1
        end
    end
    for i = 1, 2 do
        local item = ui.room_player_list[i]
        if item then
            local ps = player_slots[i]
            if ps then
                if item.bg and item.bg.set_color then item.bg:set_color((i % 2 == 0) and 0x1e293b or 0x16213e) end
                if item.label then safeSetText(item.label, "玩家" .. i .. ": " .. ps.nickname) end
                if item.ready_label then
                    safeSetText(item.ready_label, ps.ready and "已准备" or "等待中")
                    if item.ready_label.set_color then item.ready_label:set_color(ps.ready and 0x4ecb71 or 0xffd966) end
                end
            else
                if item.bg and item.bg.set_color then item.bg:set_color(0x0a0a1a) end
                if item.label then safeSetText(item.label, "玩家" .. i .. ": 等待加入...") end
                if item.ready_label then
                    safeSetText(item.ready_label, "---")
                    if item.ready_label.set_color then item.ready_label:set_color(0x666666) end
                end
            end
        end
    end
    
    local player_count = getRoomPlayerCount(room_info)
    if ui.room_status_label then
        safeSetText(ui.room_status_label, "房间号: " .. (current_room_id or "----") .. "  在线: " .. player_count .. "/2")
    end
    if ui.room_ready_btn then
        safeSetText(ui.room_ready_btn, my_ready and "取消准备" or "准备")
    end
    if ui.room_start_btn then
        setVisible(ui.room_start_btn, is_host_player)
    end
end

-- 开始联网游戏
local function startNetworkGame(player_assignments)
    log.info("coin_clash", "start network game")
    gameState = STATE.PLAYING
    networkMode = true
    my_device_id = my_device_id or getDeviceId()
    
    -- 根据分配确定自己是 P1 还是 P2：P1=蓝方，P2=红方
    my_player_number = player_assignments and player_assignments[my_device_id] or 1
    collectRoomPlayerNames(player_assignments)
    
    initGame()
    showGameUI()
    updateScoreUI()
    renderGameObjects()
    startGameLoop()

    if is_host_player then
        sys.timerStart(function()
            broadcastStateSnapshot(true)
        end, 200)
    end
end

local function handleNetworkMessage(data)
    if not networkMode or not data then return end
    if data.from and data.from == (my_device_id or getDeviceId()) then return end

    if data.action == "move" then
        local p = getPlayerByNumber(data.player)
        if p and data.x then
            p.x = clamp(data.x, 0, W - p.w)
            if is_host_player then
                broadcastStateSnapshot(true)
            end
        end
    elseif data.action == "state" then
        if not is_host_player then
            applyStateSnapshot(data)
        end
    elseif data.action == "game_over" then
        if not is_host_player then
            applyStateSnapshot(data)
            showGameOver()
        end
    elseif data.action == "leave" then
        safeReturnMainMenu(false)
    end
end

-- ==================== expvp 事件回调 ====================

local function onExpvpEvent(event, payload)
    if event ~= "message" and event ~= "game_data" then
        log.info("coin_clash", "expvp event:", event)
    end
    
    if event == "connect" then
        log.info("coin_clash", "MQTT connected")
        
    elseif event == "disconnect" then
        log.info("coin_clash", "MQTT disconnected")
        if gameState == STATE.ROOM_WAITING or gameState == STATE.PLAYING then
            safeReturnMainMenu(false)
        end
        
    elseif event == "peer_join" then
        log.info("coin_clash", "peer joined:", payload and payload.nickname or "")
        if room_ui_active then updateRoomUI() end
        
    elseif event == "peer_leave" then
        log.info("coin_clash", "peer left")
        safeReturnMainMenu(false)
        
    elseif event == "peer_ready" then
        log.info("coin_clash", "peer ready:", payload and payload.ready)
        if room_ui_active then updateRoomUI() end
        
    elseif event == "join_rejected" then
        log.warn("coin_clash", "join rejected:", payload and payload.reason or "")
        safeReturnMainMenu(false)
        
    elseif event == "game_start" then
        log.info("coin_clash", "game start")
        hideRoomWaitingUI()
        local data = payload or {}
        startNetworkGame(data.player_assignments)
        
    elseif event == "game_data" then
        local data = payload and payload.data or nil
        handleNetworkMessage(data)
        
    elseif event == "message" then
        handleNetworkMessage(payload)
        
    elseif event == "presence" then
        log.info("coin_clash", "presence:", payload and payload.nickname or "")
    end
end

-- ==================== 触摸拖动处理 ====================

local function setupTouchControl()
    airui.touch_subscribe(function(state, x, y, track_id)
        if gameState ~= STATE.PLAYING or not (state and x and y) then
            return
        end

        x, y = normalizeTouchXY(x, y)
        local state_num = tonumber(state)
        local is_down = state_num == 1
        local is_hold = state_num == 2
        local is_up = state_num == 3
        if not (is_down or is_hold or is_up) then
            is_down = (airui.TP_DOWN and state == airui.TP_DOWN) or (tp and tp.EVENT_DOWN and state == tp.EVENT_DOWN)
            is_hold = (airui.TP_HOLD and state == airui.TP_HOLD) or (tp and tp.EVENT_MOVE and state == tp.EVENT_MOVE)
            is_up = (airui.TP_UP and state == airui.TP_UP) or (tp and tp.EVENT_UP and state == tp.EVENT_UP)
        end
        local game_area_start_y = 82
        local game_area_end_y = H - 50
        local controllable = networkMode and getMyPlayer() or nil

        if is_down then
            if y >= game_area_start_y and y <= game_area_end_y then
                local target = controllable
                if not target then
                    local p1_center = player1.x + player1.w / 2
                    local p2_center = player2.x + player2.w / 2
                    target = math.abs(x - p1_center) <= math.abs(x - p2_center) and player1 or player2
                end
                if target == player1 then
                    touch_state.dragging_p1 = true
                    touch_state.dragging_p2 = false
                    touch_state.track_id_p1 = track_id
                    touch_state.offset_p1_x = player1.w / 2
                    movePlayerTo(player1, x, touch_state.offset_p1_x)
                    sendMyPosition(true)
                elseif target == player2 then
                    touch_state.dragging_p2 = true
                    touch_state.dragging_p1 = false
                    touch_state.track_id_p2 = track_id
                    touch_state.offset_p2_x = player2.w / 2
                    movePlayerTo(player2, x, touch_state.offset_p2_x)
                    sendMyPosition(true)
                end
            end
        elseif is_hold then
            if touch_state.dragging_p1 then
                movePlayerTo(player1, x, touch_state.offset_p1_x)
                sendMyPosition(false)
            elseif touch_state.dragging_p2 then
                movePlayerTo(player2, x, touch_state.offset_p2_x)
                sendMyPosition(false)
            end
        elseif is_up then
            if touch_state.dragging_p1 or touch_state.dragging_p2 then
                sendMyPosition(true)
                resetDragState()
            end
        elseif touch_state.dragging_p1 then
            movePlayerTo(player1, x, touch_state.offset_p1_x)
            sendMyPosition(false)
        elseif touch_state.dragging_p2 then
            movePlayerTo(player2, x, touch_state.offset_p2_x)
            sendMyPosition(false)
        end
    end)
end

-- ==================== 帮助对话框 ====================

function showHelpDialog()
    local help_container = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = W, h = H,
        color = 0xffffff,
    })
    
    airui.label({
        parent = help_container,
        x = 0, y = 24,
        w = W, h = 32,
        text = "游戏帮助",
        color = 0x1f2937,
        font_size = 22,
        align = airui.TEXT_ALIGN_CENTER,
    })
    
    local help_text = "【游戏规则】\n" ..
                    "1. 拖动蓝方/红方角色左右移动。\n" ..
                    "2. 接到金币 +1 分。\n" ..
                    "3. 两名玩家碰撞时双方各 -1 分。\n" ..
                    "4. 先到 " .. WIN_SCORE .. " 分获胜。\n" ..
                    "5. 单机模式可同屏控制双方；联机模式每人只控制自己的角色。\n\n" ..
                    "【积分规则】\n" ..
                    "1. 联机对战结束后，上传自己本局获得的分数。\n" ..
                    "2. 排行榜按累计积分从高到低展示。\n" ..
                    "3. 接金币越多、减少碰撞扣分，排名越靠前。"
    
    airui.label({
        parent = help_container,
        x = 18, y = 74,
        w = W - 36, h = H - 140,
        text = help_text,
        color = 0x374151,
        font_size = 13,
        align = airui.TEXT_ALIGN_LEFT,
    })
    
    airui.button({
        parent = help_container,
        x = (W - 120) / 2, y = H - 56,
        w = 120, h = 38,
        text = "返回",
        font_size = 15,
        style = { bg_color = 0x2563eb, text_color = 0xffffff, border_width = 0, radius = 19 },
        on_click = function()
            help_container:destroy()
        end,
    })
end

-- ==================== 排行榜 ====================

local leaderboardItems = {}
local leaderboardPage = 1
local leaderboardTotalPages = 1
local leaderboardData = {}
local leaderboardLoadingLabel = nil
local loadLeaderboardData

local function clearLeaderboardItems()
    for _, item in ipairs(leaderboardItems) do
        if item then pcall(function() item:destroy() end) end
    end
    leaderboardItems = {}
end

local function closeLeaderboard()
    clearLeaderboardItems()
    leaderboardLoadingLabel = nil
    leaderboardData = {}
    leaderboardPage = 1
    leaderboardTotalPages = 1
    if ui.leaderboard_container then
        pcall(function() ui.leaderboard_container:destroy() end)
        ui.leaderboard_container = nil
    end
end

local function showLeaderboardMessage(text)
    if leaderboardLoadingLabel then
        safeSetText(leaderboardLoadingLabel, text)
    end
end

local function rebuildLeaderboardUI()
    if not ui.leaderboard_container then return end
    clearLeaderboardItems()

    local cardW = W - 40
    local cardX = 20
    local cardH = 32
    local gap = 6
    local yPos = 62

    local header = airui.container({
        parent = ui.leaderboard_container,
        x = cardX, y = yPos,
        w = cardW, h = 26,
        color = 0xe8f0fe,
        radius = 4,
    })
    table.insert(leaderboardItems, header)
    airui.label({ parent = header, x = 10, y = 5, w = 48, h = 16, text = "排名", color = 0x007aff, font_size = 14, align = airui.TEXT_ALIGN_CENTER })
    airui.label({ parent = header, x = 68, y = 5, w = cardW - 160, h = 16, text = "昵称", color = 0x007aff, font_size = 14, align = airui.TEXT_ALIGN_LEFT })
    airui.label({ parent = header, x = cardW - 82, y = 5, w = 72, h = 16, text = "积分", color = 0x007aff, font_size = 14, align = airui.TEXT_ALIGN_RIGHT })

    yPos = yPos + 30

    if #leaderboardData == 0 then
        local empty = airui.container({
            parent = ui.leaderboard_container,
            x = cardX, y = yPos,
            w = cardW, h = 58,
            color = 0xffffff,
            radius = 6,
        })
        table.insert(leaderboardItems, empty)
        airui.label({
            parent = empty,
            x = 0, y = 18,
            w = cardW, h = 22,
            text = "暂无排行数据",
            color = 0x888888,
            font_size = 15,
            align = airui.TEXT_ALIGN_CENTER,
        })
        return
    end

    local pageSize = 9
    local startIdx = (leaderboardPage - 1) * pageSize + 1
    local endIdx = math.min(startIdx + pageSize - 1, #leaderboardData, 30)
    local medalBgColors = { [1] = 0xffd700, [2] = 0xc0c0c0, [3] = 0xcd7f32 }

    for i = startIdx, endIdx do
        local rec = leaderboardData[i]
        local nickname = (rec.s1 and #rec.s1 > 0) and rec.s1 or "匿名"
        local displayName = #nickname > 16 and nickname:sub(1, 16) .. ".." or nickname
        local score = tonumber(rec.i1) or 0
        local card = airui.container({
            parent = ui.leaderboard_container,
            x = cardX, y = yPos,
            w = cardW, h = cardH,
            color = medalBgColors[i] or 0xf5f5f5,
            radius = 6,
        })
        table.insert(leaderboardItems, card)
        airui.label({ parent = card, x = 10, y = 7, w = 48, h = 18, text = tostring(i), color = 0x333333, font_size = 14, align = airui.TEXT_ALIGN_CENTER })
        airui.label({ parent = card, x = 68, y = 7, w = cardW - 160, h = 18, text = displayName, color = 0x333333, font_size = 14, align = airui.TEXT_ALIGN_LEFT })
        airui.label({ parent = card, x = cardW - 82, y = 7, w = 72, h = 18, text = tostring(score), color = 0x333333, font_size = 14, align = airui.TEXT_ALIGN_RIGHT })
        yPos = yPos + cardH + gap
    end

    local pageControlY = H - 88
    local prevBtn = airui.button({
        parent = ui.leaderboard_container,
        x = 42, y = pageControlY,
        w = 72, h = 28,
        text = "上一页",
        font_size = 12,
        style = { bg_color = leaderboardPage > 1 and 0x228844 or 0x888888, text_color = 0xffffff, border_width = 0, radius = 7 },
        on_click = function()
            if leaderboardPage > 1 then
                leaderboardPage = leaderboardPage - 1
                rebuildLeaderboardUI()
            end
        end,
    })
    table.insert(leaderboardItems, prevBtn)

    local pageLabel = airui.label({
        parent = ui.leaderboard_container,
        x = (W - 100) / 2, y = pageControlY + 5,
        w = 100, h = 18,
        text = string.format("<%d/%d>", leaderboardPage, leaderboardTotalPages),
        color = 0x333333,
        font_size = 13,
        align = airui.TEXT_ALIGN_CENTER,
    })
    table.insert(leaderboardItems, pageLabel)

    local nextBtn = airui.button({
        parent = ui.leaderboard_container,
        x = W - 114, y = pageControlY,
        w = 72, h = 28,
        text = "下一页",
        font_size = 12,
        style = { bg_color = leaderboardPage < leaderboardTotalPages and 0x228844 or 0x888888, text_color = 0xffffff, border_width = 0, radius = 7 },
        on_click = function()
            if leaderboardPage < leaderboardTotalPages then
                leaderboardPage = leaderboardPage + 1
                rebuildLeaderboardUI()
            end
        end,
    })
    table.insert(leaderboardItems, nextBtn)
end

local function onLeaderboardQueryCallback(success, data)
    if not ui.leaderboard_container then return end
    if leaderboardLoadingLabel then
        pcall(function() leaderboardLoadingLabel:destroy() end)
        leaderboardLoadingLabel = nil
    end
    if not success or not data or not data.records then
        leaderboardData = {}
        leaderboardTotalPages = 1
        rebuildLeaderboardUI()
        return
    end
    leaderboardData = data.records
    table.sort(leaderboardData, function(a, b)
        return (tonumber(a.i1) or 0) > (tonumber(b.i1) or 0)
    end)
    local total = math.min(tonumber(data.total) or #leaderboardData, #leaderboardData, 30)
    leaderboardTotalPages = math.max(1, math.ceil(total / 9))
    rebuildLeaderboardUI()
end

loadLeaderboardData = function()
    if not ui.leaderboard_container then return end
    showLeaderboardMessage("数据同步中，请稍等...")
    expvp.query_leaderboard(function(success, data)
        onLeaderboardQueryCallback(success, data)
    end, 30)
end

local function showDeleteScoreConfirm()
    if not ui.leaderboard_container then return end
    local confirmContainer = airui.container({
        parent = ui.leaderboard_container,
        x = 0, y = 0,
        w = W, h = H,
        color = 0x00000080,
    })
    airui.container({
        parent = confirmContainer,
        x = W / 2 - 145, y = H / 2 - 80,
        w = 290, h = 160,
        color = 0xffffff,
        radius = 12,
    })
    airui.label({
        parent = confirmContainer,
        x = W / 2 - 130, y = H / 2 - 58,
        w = 260, h = 58,
        text = "确定要删除您的积分记录吗？\n此操作不可恢复",
        color = 0x333333,
        font_size = 15,
        align = airui.TEXT_ALIGN_CENTER,
    })
    airui.button({
        parent = confirmContainer,
        x = W / 2 - 124, y = H / 2 + 14,
        w = 108, h = 38,
        text = "确定删除",
        font_size = 14,
        style = { bg_color = 0xcc4444, text_color = 0xffffff, border_width = 0, radius = 8 },
        on_click = function()
            expvp.delete_score(function(success)
                if not ui.leaderboard_container then return end
                showLeaderboardMessage(success and "积分已删除" or "删除失败，请检查登录状态")
                leaderboardPage = 1
                loadLeaderboardData()
            end)
            confirmContainer:destroy()
        end,
    })
    airui.button({
        parent = confirmContainer,
        x = W / 2 + 16, y = H / 2 + 14,
        w = 108, h = 38,
        text = "取消",
        font_size = 14,
        style = { bg_color = 0x888888, text_color = 0xffffff, border_width = 0, radius = 8 },
        on_click = function()
            confirmContainer:destroy()
        end,
    })
end

function openLeaderboard()
    closeLeaderboard()
    ui.leaderboard_container = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = W, h = H,
        color = 0xffffff,
    })
    leaderboardData = {}
    leaderboardPage = 1
    leaderboardTotalPages = 1

    airui.label({
        parent = ui.leaderboard_container,
        x = 0, y = 20,
        w = W, h = 34,
        text = "积分排行榜",
        color = 0x333333,
        font_size = 22,
        align = airui.TEXT_ALIGN_CENTER,
    })
    leaderboardLoadingLabel = airui.label({
        parent = ui.leaderboard_container,
        x = 0, y = 200,
        w = W, h = 26,
        text = "数据同步中，请稍等...",
        color = 0x888888,
        font_size = 15,
        align = airui.TEXT_ALIGN_CENTER,
    })

    loadLeaderboardData()

    local bottomY = H - 50
    airui.button({
        parent = ui.leaderboard_container,
        x = 18, y = bottomY,
        w = 86, h = 36,
        text = "刷新",
        font_size = 14,
        style = { bg_color = 0x228844, text_color = 0xffffff, border_width = 0, radius = 8 },
        on_click = function()
            leaderboardPage = 1
            loadLeaderboardData()
        end,
    })
    airui.button({
        parent = ui.leaderboard_container,
        x = 117, y = bottomY,
        w = 86, h = 36,
        text = "删除",
        font_size = 14,
        style = { bg_color = 0xcc4444, text_color = 0xffffff, border_width = 0, radius = 8 },
        on_click = showDeleteScoreConfirm,
    })
    airui.button({
        parent = ui.leaderboard_container,
        x = 216, y = bottomY,
        w = 86, h = 36,
        text = "返回",
        font_size = 14,
        style = { bg_color = 0x888888, text_color = 0xffffff, border_width = 0, radius = 8 },
        on_click = closeLeaderboard,
    })
end

-- ==================== 初始化入口 ====================

local function init()
    log.info("coin_clash", "init start")
    
    -- 先显示主菜单，避免网络初始化异常阻断首屏渲染
    showMainMenu()
    
    -- 设置触摸拖动输入
    local touch_ok, touch_err = pcall(setupTouchControl)
    if not touch_ok then
        log.warn("coin_clash", "touch setup failed", touch_err)
    end
    
    -- 初始化 expvp 网络模块
    local net_ok, net_ret = pcall(function()
        return expvp.init({
            game_name = "coin_clash",
            score_cls = 2,
            room_max_players = 2,
        })
    end)
    if net_ok and net_ret then
        -- 注册 expvp 事件回调
        expvp.on(onExpvpEvent)
        
        -- 启动网络服务
        local start_ok, start_err = pcall(expvp.start)
        if not start_ok then
            log.warn("coin_clash", "expvp start failed", start_err)
        end
    else
        log.warn("coin_clash", "expvp init failed", net_ret)
    end
    
    log.info("coin_clash", "init done")
end

-- ==================== 窗口事件处理 ====================

local function win_on_create()
    main_container = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = W, h = H,
        color = 0x0a0f1e,
    })
    init()
end

local function win_on_destroy()
    log.info("coin_clash", "window closing")
    stopGameLoop()
    if room_update_timer then
        sys.timerStop(room_update_timer)
        room_update_timer = nil
    end
    room_ui_active = false
    resetDragState()
    if airui and airui.touch_unsubscribe then
        airui.touch_unsubscribe()
    end
    expvp.stop()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    -- 清理UI引用，避免已销毁对象被复用
    ui.menu_container = nil
    ui.game_container = nil
    clearGameObjectRefs()
    clearRoomUIRefs()
    win_id = nil
end

local function open_handler()
    if win_id then return end
    win_id = exwin.open({
        on_create = win_on_create,
        on_destroy = win_on_destroy,
    })
end

sys.subscribe("OPEN_COIN_CLASH_WIN", open_handler)

sys.subscribe("CLOSE_COIN_CLASH_WIN", function()
    if win_id then
        exwin.close(win_id)
        win_id = nil
        main_container = nil
    end
end)

return {
    init = init,
}
