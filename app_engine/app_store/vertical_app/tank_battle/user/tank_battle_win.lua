--[[
@module  tank_battle_win
@summary 双人联网坦克大战游戏窗口模块
@version 1.0.3
@date    2026.05.20
@author  王世豪
@description
    游戏业务层模块，负责：
    - 游戏逻辑、UI渲染、用户交互
    - 游戏状态管理（连接状态、准备状态等）
    - 积分数据存储和管理
    - 设备信息管理
    
    网络通信通过 expvp.lua 模块完成
]]

-- 游戏版本号
local GAME_VERSION = "1.0.3"

-- 引入网络模块（exPvP：联网对战游戏通用框架）
local expvp = require("expvp")

-- ==================== 常量配置 ====================

local W, H = 480, 800  -- 竖屏分辨率

-- 参考横屏版本：游戏区域 576x432 (16x12, CELL=36)
-- 竖屏保持相同的地图尺寸 16x12，但缩小 CELL 以适应宽度
-- 左右留边距，游戏区域宽度设为 448 (16*28)，左右各留 16px 边距
local CELL = 28       -- 单元格大小
local COLS = 16       -- 地图列数（与横屏一致）
local ROWS = 12       -- 地图行数（与横屏一致）

-- 游戏区域偏移与尺寸（竖屏：游戏区域在上方，按钮在下方）
local HUD_H = 160              -- HUD高度（4行玩家信息，字体增大后需要更多空间）
local GAME_AREA_W = COLS * CELL  -- 448 (16*28)
local GAME_AREA_H = ROWS * CELL  -- 336 (12*28)
-- 游戏区域Y坐标：状态栏下方
local GAME_AREA_Y = HUD_H      -- 从状态栏下方开始 (160)
local GAME_AREA_X = (W - GAME_AREA_W) / 2  -- 游戏区域水平居中 (16)
local BUTTON_AREA_Y = GAME_AREA_Y + GAME_AREA_H  -- 按钮区域起始Y坐标 (496)
local BUTTON_AREA_H = H - BUTTON_AREA_Y  -- 按钮区域高度 (304)

local MAX_LIVES = 3
local RESPAWN_INVINCIBLE_MS = 1000  -- 重生倒计时+无敌时间 1秒
local SHOOT_COOLDOWN_MS = 500  -- 开火冷却 500ms，手感更流畅
local TANK_SIZE = 22  -- 坦克大小（比砖块小，留出空隙可以钻入砖缝）
local TANK_HALF = TANK_SIZE / 2
-- 碰撞体积比视觉体积稍小，允许坦克更贴近墙壁
local TANK_COLLISION_SIZE = 18
local TANK_COLLISION_HALF = TANK_COLLISION_SIZE / 2
local BULLET_SIZE = 6
local BULLET_SPEED = 6
local TANK_SPEED = 2.6
local BORDER_THICK = 4   -- 游戏区域边框厚度（需要在buildGameUI之前定义）

-- 玩家编号 → 颜色映射（用于UI标签等）
local PLAYER_COLORS = {
    [1] = 0x4ecb71,  -- 绿色
    [2] = 0x4da6ff,  -- 蓝色
}

-- 游戏状态
local STATE = {
    MENU = 'menu',
    ROOM_WAITING = 'room_waiting',  -- 等待房间中
    DEVICE_LIST = 'device_list',
    WAITING = 'waiting',
    CONNECTING = 'connecting',
    PLAYING = 'playing',
    GAME_OVER = 'game_over'
}

-- ==================== 模块内部状态 ====================

local win_id = nil
local main_container = nil
local game_timer_id = nil
local pos_sync_timer = nil  -- 位置同步定时器（250ms）

local gameState = STATE.MENU
local networkMode = false
local networkRole = nil
local networkPlayerNumber = 1

-- 游戏状态管理
local game_state = {
    online_devices = {},
    peer_connected = false,
    peer_ready = false,
    peer_device_id = nil,
    peer_device_model = nil,
    is_server = false,
    score_p1 = 0,
    score_p2 = 0
}

-- 设备信息
local my_device_id = nil
local my_device_model = "未知"

-- ==================== 房间系统状态 ====================
local room_players = {}             -- 房间玩家列表（含自己）
local my_player_number = 1          -- 自己在房间中的玩家编号
local my_ready = false              -- 自己是否已准备
local is_host_player = false        -- 是否为房主
local current_room_id = nil         -- 当前房间ID
local room_has_enough = false       -- 是否满足开始条件（>=2人）

-- 房间UI元素
local room_waiting_container = nil
local room_player_list = {}         -- 玩家列表UI元素

-- 匹配UI
local matchingContainer = nil
local matchingTimer = nil
local matchingCountdownLabel = nil
local matchingCountdownValue = 30
local room_ready_btn = nil          -- 准备按钮
local room_start_btn = nil          -- 开始游戏按钮（房主专用）
local room_leave_btn = nil          -- 离开房间按钮
local room_status_label = nil       -- 状态提示标签

-- 前向声明：按钮回调函数定义在菜单之后，需在闭包创建前声明
local onCreateRoom
local showJoinDialog
local onJoinRoom
local startQuickMatch
local showMatchingUI
local hideMatchingUI
local showRoomWaitingUI
local hideRoomWaitingUI
local updateRoomUI
local buildRoomWaitingUI
local showMainMenu
local sendOpponentLeft

-- 游戏对象
local tanks = {}
local bullets = {}
local walls = {}
local powerUps = {}

-- 输入状态
local input_p1 = { up = false, down = false, left = false, right = false, shoot = false }
local input_p2 = { up = false, down = false, left = false, right = false, shoot = false }
-- 屏幕按钮输入状态（玩家1，避免被键盘状态覆盖）
local btn_input = { up = false, down = false, left = false, right = false, shoot = false }
-- 按钮按下状态跟踪（防止 on_pressed/on_released 异常重复触发）
local btn_pressed_state = { up = false, down = false, left = false, right = false, shoot = false }

-- ==================== 实体按键配置 ====================
-- GPIO按键映射（与饥荒游戏保持一致）
local GPIO_KEY_MAP = {
    { pin = 44, action = "up"    },    -- 上
    { pin = 48, action = "down"  },    -- 下
    { pin = 41, action = "left"  },    -- 左
    { pin = 40, action = "right" },    -- 右
    { pin = 0,  action = "shoot" },    -- A键 - 开火
}
local DEBOUNCE_MS = 20              -- 消抖时间
local gpio_keys_setup = false       -- 按键是否已初始化
-- 方向按钮矩形（在 showGameUI 中初始化），用于 touch 订阅判定长按持续移动
local dir_btn_rects = nil
-- 全局触摸订阅引用（用于 win_on_destroy 时取消）
local touch_subscribed = false
-- 玩家1当前朝向（用于"转向后再次点击才移动"逻辑）
local p1_facing = 'up'  -- 'up' / 'down' / 'left' / 'right'
-- 键盘状态
local keyStates = {}

-- UI元素
local ui = {
    score_p1 = nil,
    score_p2 = nil,
    lives_p1 = nil,
    lives_p2 = nil,
    mode_indicator = nil,
    game_canvas = nil,
    menu_container = nil,
    network_panel = nil,
    overlay_message = nil,
    ko_overlay = nil,
    ko_label = nil,
    winner_label = nil,
    ko_restart_btn = nil,
    ko_back_btn = nil,
    -- 积分系统UI
    total_score_label = nil,
    peer_model_label = nil
}

-- 游戏元素容器
local game_elements_container = nil

-- ==================== 积分系统UI ====================
local scoreLabel = nil
local peerModelLabel = nil
local leaderboardWinId = nil
local leaderboardMainContainer = nil
local leaderboardItems = {}
local leaderboardPage = 1
local leaderboardTotalPages = 1
local leaderboardData = {}
local leaderboardLoadingLabel = nil

-- ==================== 工具函数 ====================

local toastContainer = nil

local function showToast(message, duration)
    duration = duration or 2000
    
    -- 清除之前的toast
    if toastContainer then
        toastContainer:destroy()
        toastContainer = nil
    end
    
    -- 创建新toast
    toastContainer = airui.container({
        parent = main_container,
        x = W / 2 - 150,
        y = H / 2 - 30,
        w = 300,
        h = 60,
        color = 0x1a1a2e,
        radius = 10
    })
    
    airui.label({
        parent = toastContainer,
        x = 0,
        y = 15,
        w = 300,
        h = 30,
        text = message,
        color = 0xffffff,
        font_size = 16,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 自动消失
    sys.timerStart(function()
        if toastContainer then
            toastContainer:destroy()
            toastContainer = nil
        end
    end, duration)
end

local function clamp(value, min, max)
    if value < min then return min end
    if value > max then return max end
    return value
end

local function rectsOverlap(a, b)
    return not (a.x + a.w <= b.x or a.x >= b.x + b.w or a.y + a.h <= b.y or a.y >= b.y + b.h)
end

local function getTimestamp()
    if mcu and mcu.ticks2 then
        local ms_h, ms_l = mcu.ticks2(1)
        return ms_h * 1000000 + ms_l
    end
    return os.time() * 1000
end

-- 获取设备ID
local function get_device_id()
    return expvp.get_device_id()
end

-- 获取设备型号
local function get_device_model()
    if not my_device_model or my_device_model == "未知" then
        my_device_model = expvp.get_device_model()
    end
    return my_device_model
end

-- 获取昵称
local function get_nickname()
    local info = expvp.get_account_info()
    if info and info.nickname and #info.nickname > 0 then
        return info.nickname
    end
    return expvp.get_device_id():sub(-6)
end

-- ==================== 积分系统功能 ====================

-- 更新积分显示（积分已合并到玩家信息中，此函数保留供后续扩展）
local function updateScoreDisplay()
    -- 积分显示已移除，无需更新
end

-- 上传积分并显示结果
local function uploadGameScore()
    expvp.upload_score(function(ok, totalScore)
        if ok then
            log.info("tank_battle", "积分上传成功，总积分:", totalScore)
        else
            log.warn("tank_battle", "积分上传失败")
        end
    end)
end

-- ==================== 地图定义 ====================

local MAP_TEMPLATE = {
    {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    {0, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 0},
    {0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0},
    {0, 1, 1, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 0},
    {0, 1, 0, 0, 0, 1, 0, 0, 0, 2, 2, 0, 0, 0, 0, 0},
    {0, 0, 1, 1, 0, 0, 0, 1, 0, 2, 2, 0, 1, 0, 0, 0},
    {0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0},
    {0, 1, 1, 0, 0, 1, 0, 0, 2, 2, 0, 0, 0, 0, 1, 0},
    {0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 0, 0, 0, 0, 1, 0},
    {0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0},
    {0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0},
    {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
}

-- ==================== 构建地图 ====================

local function buildMap()
    walls = {}
    for row = 0, ROWS - 1 do
        for col = 0, COLS - 1 do
            local cellType = MAP_TEMPLATE[row + 1][col + 1]
            if cellType == 1 or cellType == 2 then
                table.insert(walls, {
                    x = col * CELL,
                    y = row * CELL,
                    w = CELL,
                    h = CELL,
                    type = cellType == 2 and 'steel' or 'brick',
                    destroyed = false,
                    health = cellType == 2 and 999 or 2
                })
            end
        end
    end
end

-- 获取随机可用的重生位置（避开墙壁和已有坦克）
local function getRandomSpawnPos()
    -- 收集所有可通行的格子（MAP_TEMPLATE 中值为 0）
    local walkable = {}
    for row = 0, ROWS - 1 do
        for col = 0, COLS - 1 do
            if MAP_TEMPLATE[row + 1][col + 1] == 0 then
                table.insert(walkable, { col = col, row = row })
            end
        end
    end
    if #walkable == 0 then return nil end

    -- 最多尝试 20 次找到一个不与现有坦克重叠的位置
    for attempt = 1, 20 do
        local cell = walkable[math.random(1, #walkable)]
        local sx = cell.col * CELL + CELL / 2  -- 格子中心
        local sy = cell.row * CELL + CELL / 2
        local spawnBounds = { x = sx - TANK_HALF, y = sy - TANK_HALF, w = TANK_SIZE, h = TANK_SIZE }

        -- 检查是否与其他存活的坦克重叠
        local overlap = false
        for _, t in ipairs(tanks) do
            if t.alive then
                local tb = t:getBounds()
                if rectsOverlap(spawnBounds, tb) then
                    overlap = true
                    break
                end
            end
        end
        if not overlap then
            return { x = sx, y = sy }
        end
    end
    -- 实在找不到，返回地图中心
    return { x = GAME_AREA_W / 2, y = GAME_AREA_H / 2 }
end

-- ==================== 坦克类 ====================

local Tank = {}
Tank.__index = Tank

-- 强制移动一段距离（距离单位：像素，如 CELL 或 CELL/2）
function Tank:moveOneStep(direction, distance)
    if self.moveRemaining > 0 then
        -- 已在移动中，忽略新请求（可保留调试，但用 log.info 替代）
        -- log.info("tank_battle", string.format("moveOneStep ignored, moveRemaining=%.2f", self.moveRemaining))
        return false
    end
    local dirVec = { x = 0, y = 0 }
    if direction == 'up' then
        dirVec.y = -1
    elseif direction == 'down' then
        dirVec.y = 1
    elseif direction == 'left' then
        dirVec.x = -1
    elseif direction == 'right' then
        dirVec.x = 1
    else
        return false
    end
    -- 安全记录（可选）
    -- log.info("tank_battle", string.format("moveOneStep dir=%s dist=%d", direction, distance))
    self.moveRemaining = distance
    self.moveDir = dirVec
    return true
end

function Tank.new(x, y, color, playerNum, name)
    local self = setmetatable({}, Tank)
    self.x = x
    self.y = y
    self.color = color
    self.playerNum = playerNum
    self.name = name
    self.dir = { x = 0, y = -1 }
    self.speed = TANK_SPEED
    self.lives = MAX_LIVES
    self.alive = true
    self.invincibleUntil = 0
    self.shootCooldownUntil = 0
    self.respawnTimer = 0
    self.flashTimer = 0
    self.powerUpType = nil
    self.powerUpUntil = 0
    self.moveRemaining = 0       -- 剩余移动距离（像素）
    self.moveDir = nil           -- 强制移动方向 {x, y}
    return self
end

function Tank:getBounds()
    return {
        x = self.x - TANK_HALF,
        y = self.y - TANK_HALF,
        w = TANK_SIZE,
        h = TANK_SIZE
    }
end

function Tank:hit()
    if not self.alive then return false end
    if getTimestamp() < self.invincibleUntil then return false end
    -- 每次被击中掉1条命，立即死亡并开始重生倒计时
    self.lives = self.lives - 1
    self.alive = false
    self.respawnTimer = RESPAWN_INVINCIBLE_MS
    return true
end

function Tank:respawn(x, y)
    self.x = x
    self.y = y
    self.dir = { x = 0, y = -1 }
    self.alive = true
    self.invincibleUntil = getTimestamp() + RESPAWN_INVINCIBLE_MS
    self.shootCooldownUntil = 0
    self.powerUpType = nil
    self.powerUpUntil = 0
    self.flashTimer = 0  -- 重置闪烁计时器
end

-- ==================== AI系统 ====================

-- AI状态（每个AI坦克独立，仅P2）
local aiStates = {
    [2] = { actionTimer = 0, currentAction = 'idle', moveRemaining = 0, moveDir = nil }
}

-- 获取最近的可攻击目标
local function findNearestTarget(aiTank)
    local nearestTank = nil
    local minDist = math.huge

    for _, tank in ipairs(tanks) do
        -- 只攻击存活的敌方坦克（不是自己，且不是队友）
        if tank.alive and tank.playerNum ~= aiTank.playerNum then
            local dx = tank.x - aiTank.x
            local dy = tank.y - aiTank.y
            local dist = math.sqrt(dx * dx + dy * dy)

            if dist < minDist then
                minDist = dist
                nearestTank = tank
            end
        end
    end

    return nearestTank, minDist
end

-- 更新单个AI坦克
local function updateSingleAI(aiTank, dt, inputState)
    local aiNum = aiTank.playerNum
    local state = aiStates[aiNum]
    if not state then return end

    -- 处理"移动一格"的剩余距离
    if state.moveRemaining > 0 and state.moveDir then
        state.moveRemaining = state.moveRemaining - TANK_SPEED
        if state.moveRemaining <= 0 then
            -- 走完一格，停止
            state.moveRemaining = 0
            state.moveDir = nil
            inputState.up = false
            inputState.down = false
            inputState.left = false
            inputState.right = false
        else
            -- 继续朝该方向移动
            inputState.up = (state.moveDir == 'up')
            inputState.down = (state.moveDir == 'down')
            inputState.left = (state.moveDir == 'left')
            inputState.right = (state.moveDir == 'right')
        end
        return  -- 移动中不做新决策
    end

    -- 查找最近目标
    local target, dist = findNearestTarget(aiTank)

    if not target then
        -- 没有目标，随机移动
        inputState.up = false
        inputState.down = false
        inputState.left = false
        inputState.right = false
        inputState.shoot = false
        return
    end

    local dx = target.x - aiTank.x
    local dy = target.y - aiTank.y

    -- 决策间隔
    state.actionTimer = state.actionTimer - dt
    if state.actionTimer > 0 then
        return
    end
    state.actionTimer = 0.3 + math.random() * 0.4  -- 0.3-0.7秒决策一次

    -- AI逻辑：根据距离决定行动
    local action
    if dist < 120 then
        -- 距离很近：尝试瞄准射击
        action = 'aim'
    elseif dist > 350 then
        -- 距离远：靠近目标
        action = 'chase'
    else
        -- 中等距离：随机决定是瞄准还是移动
        action = math.random() < 0.5 and 'aim' or 'move'
    end

    -- 清空输入
    inputState.up = false
    inputState.down = false
    inputState.left = false
    inputState.right = false
    inputState.shoot = false

    if action == 'aim' then
        -- 瞄准目标：选定方向后走一格 + 射击
        local angle = math.atan2(dy, dx)
        local deg = angle * 180 / math.pi
        local dir
        if deg > -45 and deg <= 45 then
            dir = 'right'
        elseif deg > 45 and deg <= 135 then
            dir = 'down'
        elseif deg > 135 or deg <= -135 then
            dir = 'left'
        else
            dir = 'up'
        end
        state.moveDir = dir
        state.moveRemaining = CELL

        -- 射击（检查坦克实际冷却状态，固定1.2秒间隔）
        local now = getTimestamp()
        if now >= aiTank.shootCooldownUntil then
            inputState.shoot = true
            aiTank.shootCooldownUntil = now + 1200  -- 固定1.2秒间隔（毫秒）
        end

    elseif action == 'chase' then
        -- 追踪目标：朝目标方向走一格
        local dir
        if math.abs(dx) > math.abs(dy) then
            dir = dx > 0 and 'right' or 'left'
        else
            dir = dy > 0 and 'down' or 'up'
        end
        state.moveDir = dir
        state.moveRemaining = CELL

    elseif action == 'move' then
        -- 随机移动一格
        local dirs = { 'up', 'down', 'left', 'right' }
        state.moveDir = dirs[math.random(1, 4)]
        state.moveRemaining = CELL
    end
end

-- 更新AI（P2在单机模式下是纯AI，不需要玩家输入）
local function updateAI(dt)
    if tanks[2] and tanks[2].alive then
        updateSingleAI(tanks[2], dt, input_p2)
    end
end

function Tank:update(dt, inputState)
    if not self.alive then
        if self.respawnTimer > 0 then
            self.respawnTimer = self.respawnTimer - dt * 1000
            if self.respawnTimer <= 0 then
                local sp = getRandomSpawnPos()
                if sp then
                    self:respawn(sp.x, sp.y)
                end
            end
        end
        return
    end

    -- ========== 强制移动（优先级高于输入） ==========
    if self.moveRemaining > 0 and self.moveDir then
        local moveX = self.moveDir.x
        local moveY = self.moveDir.y
        local step = self.speed * dt * 60
        if step > self.moveRemaining then step = self.moveRemaining end
        local newX = self.x + moveX * step
        local newY = self.y + moveY * step

        -- 碰撞检测（使用较小的碰撞体积，允许坦克更贴近墙壁）
        local bounds = { x = newX - TANK_COLLISION_HALF, y = newY - TANK_COLLISION_HALF, w = TANK_COLLISION_SIZE, h = TANK_COLLISION_SIZE }
        local blockedX = false
        local blockedY = false
        for _, wall in ipairs(walls) do
            if not wall.destroyed and rectsOverlap(bounds, wall) then
                blockedX = true
                blockedY = true
                -- 调试log（可选）
                -- log.info("tank_battle", string.format("碰撞检测: 碰到墙体 (%d,%d)", wall.x, wall.y))
                break
            end
        end
        for _, otherTank in ipairs(tanks) do
            if otherTank.playerNum ~= self.playerNum and otherTank.alive then
                -- 无敌状态可穿透其它坦克（避免重生点重叠卡死）
                local selfInvincible = getTimestamp() < self.invincibleUntil
                local otherInvincible = getTimestamp() < otherTank.invincibleUntil
                if not selfInvincible and not otherInvincible then
                    local ob = otherTank:getBounds()
                    if rectsOverlap(bounds, ob) then
                        blockedX = true
                        blockedY = true
                        break
                    end
                end
            end
        end
        if newX - TANK_COLLISION_HALF < 0 or newX + TANK_COLLISION_HALF > GAME_AREA_W then
            blockedX = true
            -- 调试log（可选）
            -- log.info("tank_battle", "碰撞检测: 碰到左/右边界")
        end
        if newY - TANK_COLLISION_HALF < 0 or newY + TANK_COLLISION_HALF > GAME_AREA_H then
            blockedY = true
            -- 调试log（可选）
            -- log.info("tank_battle", "碰撞检测: 碰到上/下边界")
        end

        if not blockedX then self.x = newX end
        if not blockedY then self.y = newY end

        self.moveRemaining = self.moveRemaining - step
        if self.moveRemaining <= 0 then
            -- 调试log（可选）
            -- log.info("tank_battle", string.format("强制移动完成: player=%d, 最终位置=(%.2f,%.2f)", self.playerNum, self.x, self.y))
            self.moveRemaining = 0
            self.moveDir = nil
        end

        -- 强制移动时更新坦克朝向
        self.dir = { x = moveX, y = moveY }
        return   -- 本次 update 不再处理输入移动
    end

    local moveX = 0
    local moveY = 0
    if inputState.up then moveY = -1 end
    if inputState.down then moveY = 1 end
    if inputState.left then moveX = -1 end
    if inputState.right then moveX = 1 end

    local mag = math.sqrt(moveX * moveX + moveY * moveY)
    if mag > 0 then
        moveX = moveX / mag
        moveY = moveY / mag
        self.dir = { x = moveX, y = moveY }
    end

    local spd = (self.powerUpType == 'speed' and getTimestamp() < self.powerUpUntil) and
        self.speed * 1.7 or self.speed
    local newX = self.x + moveX * spd * dt * 60
    local newY = self.y + moveY * spd * dt * 60

    local bounds = { x = newX - TANK_COLLISION_HALF, y = newY - TANK_COLLISION_HALF, w = TANK_COLLISION_SIZE, h = TANK_COLLISION_SIZE }
    local blockedX = false
    local blockedY = false

    for _, wall in ipairs(walls) do
        if not wall.destroyed and rectsOverlap(bounds, wall) then
            blockedX = true
            blockedY = true
            break
        end
    end

    for _, otherTank in ipairs(tanks) do
        if otherTank.playerNum ~= self.playerNum and otherTank.alive then
            -- 无敌状态可穿透其它坦克（避免重生点重叠卡死）
            local selfInvincible = getTimestamp() < self.invincibleUntil
            local otherInvincible = getTimestamp() < otherTank.invincibleUntil
            if not selfInvincible and not otherInvincible then
                local ob = otherTank:getBounds()
                if rectsOverlap(bounds, ob) then
                    blockedX = true
                    blockedY = true
                    break
                end
            end
        end
    end

    if newX - TANK_COLLISION_HALF < 0 or newX + TANK_COLLISION_HALF > GAME_AREA_W then blockedX = true end
    if newY - TANK_COLLISION_HALF < 0 or newY + TANK_COLLISION_HALF > GAME_AREA_H then blockedY = true end

    if not blockedX then self.x = newX end
    if not blockedY then self.y = newY end

    self.x = clamp(self.x, TANK_HALF, GAME_AREA_W - TANK_HALF)
    self.y = clamp(self.y, TANK_HALF, GAME_AREA_H - TANK_HALF)

    if inputState.shoot and getTimestamp() >= self.shootCooldownUntil then
        self:shoot()
    end

    -- 无敌闪烁计时器（0.1秒切换一次显隐）
    if getTimestamp() < self.invincibleUntil then
        self.flashTimer = self.flashTimer + dt * 1000
        if self.flashTimer >= 100 then
            self.flashTimer = self.flashTimer - 100
        end
    else
        self.flashTimer = 0
    end
end

function Tank:shoot()
    -- 双重检查：防止任何路径跳过冷却时间
    if getTimestamp() < self.shootCooldownUntil then
        log.warn('tank_battle', string.format('tank%d shoot: 冷却中，强制阻止', self.playerNum))
        return
    end
    
    local bx = self.x + self.dir.x * (TANK_HALF + 6)
    local by = self.y + self.dir.y * (TANK_HALF + 6)
    table.insert(bullets, {
        x = bx,
        y = by,
        vx = self.dir.x * BULLET_SPEED,
        vy = self.dir.y * BULLET_SPEED,
        owner = self.playerNum,
        color = self.color,
        size = BULLET_SIZE
    })
    self.shootCooldownUntil = getTimestamp() + SHOOT_COOLDOWN_MS
end

-- ==================== 粒子效果 ====================

local function spawnParticles(x, y, color, count)
    -- 粒子特效已移除，直接返回
    return
end

-- ==================== 游戏初始化 ====================

local function initGame()
    buildMap()
    bullets = {}
    particles = {}
    powerUps = {}
    game_state.score_p1 = 0
    game_state.score_p2 = 0

    -- 重置网络模块的积分
    expvp.reset_score()

    -- 复位玩家按钮输入状态
    lastDirClickTime = 0  -- 重置方向点击节流
    btn_input.up = false
    btn_input.down = false
    btn_input.left = false
    btn_input.right = false
    btn_input.shoot = false

    -- 2个玩家初始位置（左右两侧）
    tanks = {
        Tank.new(2.5 * CELL, 2.5 * CELL, 0x4ecb71, 1, "玩家1"),
        Tank.new(13.5 * CELL, 9.5 * CELL, 0x4da6ff, 2, "玩家2"),
    }
end

-- ==================== 游戏主循环 ====================

local lastUpdateTime = getTimestamp()

-- 处理按钮输入（每帧调用，让按下的方向按钮持续生效）
local function processButtonInput()
    if networkMode then
        -- 联机点按模式：移动由 moveOneStep 驱动，不依赖 input 表
        -- 只处理开火（btn_input.shoot 由 on_click 或 GPIO 回调设置）
        -- 重要：必须把方向字段全部清零，防止上一局单机模式残留的状态影响联机模式
        input_p1.up = false
        input_p1.down = false
        input_p1.left = false
        input_p1.right = false
        input_p1.shoot = false
        input_p2.up = false
        input_p2.down = false
        input_p2.left = false
        input_p2.right = false
        input_p2.shoot = false

        local localInput
        if current_room_id then
            localInput = my_player_number
        else
            localInput = networkPlayerNumber
        end
        local input_table = (localInput == 1) and input_p1 or input_p2
        if btn_input.shoot then
            input_table.shoot = true
            btn_input.shoot = false
        end
    else
        -- 单机模式：P1 用按钮 + GPIO，P2 是纯 AI
        input_p1.up = btn_input.up or false
        input_p1.down = btn_input.down or false
        input_p1.left = btn_input.left or false
        input_p1.right = btn_input.right or false
        if btn_input.shoot then
            input_p1.shoot = true
            btn_input.shoot = false
        else
            input_p1.shoot = false
        end
        
        -- P2 完全由 AI 控制，清空 input_p2 让 AI 自由设置
        -- （AI 会在 updateSingleAI 中直接设置 input_p2 的字段）
    end
end

local function gameLoop()
    local now = getTimestamp()
    local dt = (now - lastUpdateTime) / 1000
    lastUpdateTime = now

    -- 即使不在PLAYING状态也要更新时间，防止切换后dt过大
    if gameState ~= STATE.PLAYING then
        -- 只在MENU状态时重置lastUpdateTime，防止切换后dt过大
        if gameState == STATE.MENU then
            lastUpdateTime = now
        end
        return
    end

    dt = math.min(dt, 0.05)

    -- 处理按钮输入（每帧）
    processButtonInput()

    -- 单机对战模式下，玩家2使用AI
    if not networkMode and gameState == STATE.PLAYING then
        updateAI(dt)
    end

    for _, tank in ipairs(tanks) do
        -- 所有坦克统一用输入模拟移动
        -- 网络模式下，对手的输入由 sendInputMessage 同步到对方，对方用 input_p1/input_p2 驱动
        local input
        if tank.playerNum == 1 then
            input = input_p1
        else
            input = input_p2
        end
        tank:update(dt, input)
    end

    local i = #bullets
    while i >= 1 do
        local bullet = bullets[i]
        bullet.x = bullet.x + bullet.vx
        bullet.y = bullet.y + bullet.vy

        local destroyed = false

        if bullet.x < 0 or bullet.x > GAME_AREA_W or bullet.y < 0 or bullet.y > GAME_AREA_H then
            table.remove(bullets, i)
            destroyed = true
        end

        if not destroyed then
            for _, wall in ipairs(walls) do
                if not wall.destroyed then
                    local bulletBounds = {
                        x = bullet.x - bullet.size / 2,
                        y = bullet.y - bullet.size / 2,
                        w = bullet.size,
                        h = bullet.size
                    }
                    if rectsOverlap(bulletBounds, wall) then
                        if wall.type == 'brick' then
                            wall.health = wall.health - 1
                            if wall.health <= 0 then
                                wall.destroyed = true
                                spawnParticles(wall.x + CELL / 2, wall.y + CELL / 2, 0x8b4513, 10)
                            end
                        end
                        table.remove(bullets, i)
                        destroyed = true
                        break
                    end
                end
            end
        end

        if not destroyed then
            for _, tank in ipairs(tanks) do
                if tank.alive and tank.playerNum ~= bullet.owner then
                    local bulletBounds = {
                        x = bullet.x - bullet.size / 2,
                        y = bullet.y - bullet.size / 2,
                        w = bullet.size,
                        h = bullet.size
                    }
                    if rectsOverlap(bulletBounds, tank:getBounds()) then
                        if tank:hit() then
                            spawnParticles(tank.x, tank.y, tank.color, 20)
                            -- 为对应的玩家增加积分（击中+2分）
                            local owner = bullet.owner
                            if owner == 1 then
                                game_state.score_p1 = game_state.score_p1 + 2
                            elseif owner == 2 then
                                game_state.score_p2 = game_state.score_p2 + 2
                            end
                            -- 本地玩家击中敌方才累加积分（用于上传）
                            if owner == my_player_number then
                                expvp.add_score(2)
                            end
                        end
                        -- 被击中的玩家扣分（被击中-1分）
                        local targetPlayerNum = tank.playerNum
                        if targetPlayerNum == 1 then
                            game_state.score_p1 = game_state.score_p1 - 1
                        elseif targetPlayerNum == 2 then
                            game_state.score_p2 = game_state.score_p2 - 1
                        end
                        -- 本地玩家被击中扣分（用于上传）
                        if targetPlayerNum == my_player_number then
                            expvp.add_score(-1)
                        end
                        table.remove(bullets, i)
                        destroyed = true
                        break
                    end
                end
            end
        end

        i = i - 1
    end

    -- 检查游戏结束：只剩一个玩家存活（lives <= 0 即出局）
    if gameState == STATE.PLAYING then
        local alive = {}
        for i = 1, 2 do
            if tanks[i] and tanks[i].lives > 0 then
                table.insert(alive, i)
            end
        end

        if #alive <= 1 then
            gameState = STATE.GAME_OVER
            
            -- KO奖励：获胜方+5分
            local winnerNum = alive[1]
            if winnerNum then
                if winnerNum == 1 then
                    game_state.score_p1 = game_state.score_p1 + 5
                elseif winnerNum == 2 then
                    game_state.score_p2 = game_state.score_p2 + 5
                end
                -- 本地玩家获胜才累加KO奖励积分（用于上传）
                if winnerNum == my_player_number then
                    expvp.add_score(5)
                end
            end
            -- 上传本局积分
            uploadGameScore()
            -- 显示 K.O. 弹窗
            local winnerName = winnerNum and ("玩家" .. winnerNum .. " (P" .. winnerNum .. ")") or "未知"
            showKOOverlay(winnerName)
        end
    end

    updateUI()
    renderGame()
end

-- ==================== UI更新 ====================

function updateUI()
    -- 判断当前玩家编号
    local myPlayerNum
    if networkMode then
        if current_room_id then
            myPlayerNum = my_player_number  -- 房间模式
        else
            myPlayerNum = networkPlayerNumber  -- 匹配模式
        end
    else
        myPlayerNum = 1  -- 单机模式
    end

    -- 2个玩家的前缀标签
    local player_prefixes = {}
    for i = 1, 2 do
        if i == myPlayerNum then
            player_prefixes[i] = "[你]P" .. i
        else
            player_prefixes[i] = "P" .. i
        end
    end

    -- 更新2个玩家的HUD信息
    local player_ui_map = {
        [1] = {label = ui.score_p1, score = game_state.score_p1, base_color = 0x4ecb71},
        [2] = {label = ui.score_p2, score = game_state.score_p2, base_color = 0x4da6ff},
    }
    for i = 1, 2 do
        local item = player_ui_map[i]
        if item.label and tanks[i] then
            local lives = math.max(0, tanks[i].lives)
            local score = item.score
            -- 分数为负数时显示红色，正数或0时显示玩家基础颜色
            local score_color = (score < 0) and 0xff4444 or item.base_color
            item.label:set_text(player_prefixes[i] .. " 生命:" .. tostring(lives) .. " 分数:" .. tostring(score))
            item.label:set_color(score_color)
        end
    end
    -- 更新本局积分显示
    updateScoreDisplay()
end

-- 显示 K.O. 弹窗（参考火柴人格斗设计）
function showKOOverlay(winnerName)
    if ui.winner_label then
        ui.winner_label:set_text(winnerName .. "  获胜!")
    end
    if ui.ko_overlay and ui.ko_overlay.set_hidden then
        ui.ko_overlay:set_hidden(false)
    end
    log.info('tank_battle', 'K.O.! Winner: ' .. winnerName)
end

-- ==================== 游戏渲染 ====================

-- UI对象池（参考原版做法：预创建UI元素，每帧只更新位置）
local ui_pool = {
    walls = {},          -- 墙体UI元素 [index] = ref
    tanks = {},          -- 坦克根容器 [playerNum] = ref
    tank_barrels = {},   -- 炮管 [playerNum] = ref
    tank_muzzles = {},   -- 炮口 [playerNum] = ref
    -- 履带：[playerNum] = {v=ref, h=ref} v=竖直(左右侧), h=水平(上下侧)
    tank_track_l = {},
    tank_track_r = {},
    bullets = {},        -- 子弹UI元素 [index] = ref
    initialized = false
}

local MAX_BULLETS = 20
local MAX_PARTICLES = 100

-- 颜色定义
local COLOR_BRICK = 0x8b4513    -- 砖墙：棕色
local COLOR_STEEL = 0x808080    -- 钢铁墙：灰色
local COLOR_BULLET = 0xffdf70   -- 子弹：黄色
-- 颜色暗化辅助函数（用于3D立体感）
local function dimColor(c, factor)
    local r = ((c >> 16) & 0xFF) * factor
    local g = ((c >> 8) & 0xFF) * factor
    local b = (c & 0xFF) * factor
    return (math.floor(r) << 16) | (math.floor(g) << 8) | math.floor(b)
end

-- 初始化UI对象池（只创建一次）
local function initUIPool()
    if ui_pool.initialized or not game_elements_container then return end

    -- 创建墙体UI（根据当前walls数组）
    for i, wall in ipairs(walls) do
        if wall.type == 'steel' then
            -- 钢铁墙：使用田字格样式（类似原版坦克大战）
            local wallRoot = airui.container({
                parent = game_elements_container,
                x = wall.x,
                y = wall.y,
                w = wall.w - 1,
                h = wall.h - 1,
                color = 0x606060  -- 深色背景
            })
            
            -- 左上格子
            airui.container({
                parent = wallRoot,
                x = 1,
                y = 1,
                w = math.floor((wall.w - 3) / 2),
                h = math.floor((wall.h - 3) / 2),
                color = COLOR_STEEL,
                radius = 1
            })
            
            -- 右上格子
            airui.container({
                parent = wallRoot,
                x = math.floor((wall.w - 1) / 2) + 1,
                y = 1,
                w = math.floor((wall.w - 3) / 2),
                h = math.floor((wall.h - 3) / 2),
                color = COLOR_STEEL,
                radius = 1
            })
            
            -- 左下格子
            airui.container({
                parent = wallRoot,
                x = 1,
                y = math.floor((wall.h - 1) / 2) + 1,
                w = math.floor((wall.w - 3) / 2),
                h = math.floor((wall.h - 3) / 2),
                color = COLOR_STEEL,
                radius = 1
            })
            
            -- 右下格子
            airui.container({
                parent = wallRoot,
                x = math.floor((wall.w - 1) / 2) + 1,
                y = math.floor((wall.h - 1) / 2) + 1,
                w = math.floor((wall.w - 3) / 2),
                h = math.floor((wall.h - 3) / 2),
                color = COLOR_STEEL,
                radius = 1
            })
            
            ui_pool.walls[i] = wallRoot
        else
            -- 砖墙：2x2格砖墙样式，带砂浆缝
            local wallRoot = airui.container({
                parent = game_elements_container,
                x = wall.x,
                y = wall.y,
                w = wall.w - 1,
                h = wall.h - 1,
                color = 0x6b3410  -- 砂浆底色（深棕色）
            })

            local brickW = math.floor((wall.w - 4) / 2)
            local brickH = math.floor((wall.h - 4) / 2)

            -- 第一行：两块砖并排
            airui.container({
                parent = wallRoot,
                x = 1,
                y = 1,
                w = brickW,
                h = brickH,
                color = COLOR_BRICK,
                radius = 1
            })
            airui.container({
                parent = wallRoot,
                x = brickW + 3,
                y = 1,
                w = brickW,
                h = brickH,
                color = COLOR_BRICK,
                radius = 1
            })

            -- 第二行：两块砖并排
            airui.container({
                parent = wallRoot,
                x = 1,
                y = brickH + 3,
                w = brickW,
                h = brickH,
                color = COLOR_BRICK,
                radius = 1
            })
            airui.container({
                parent = wallRoot,
                x = brickW + 3,
                y = brickH + 3,
                w = brickW,
                h = brickH,
                color = COLOR_BRICK,
                radius = 1
            })

            ui_pool.walls[i] = wallRoot
        end
    end

    -- 创建坦克UI（经典Battle City风格，多部件拼装）
    for _, tank in ipairs(tanks) do
        -- 颜色配置
        local tankColor
        local trackColor = 0x3a3a3a  -- 履带深色
        local turretColor
        if tank.playerNum == 1 then
            tankColor = 0x3da85c      -- 绿色车身
            turretColor = 0x4ecb71    -- 绿色炮塔（亮一点）
        else
            tankColor = 0x3a8cd6      -- 蓝色车身（P2）
            turretColor = 0x4da6ff    -- 蓝色炮塔（亮一点）
        end

        -- 坦克根容器（不放底色，避免旋转时露出）
        local tankRoot = airui.container({
            parent = game_elements_container,
            x = tank.x - TANK_HALF,
            y = tank.y - TANK_HALF,
            w = TANK_SIZE,
            h = TANK_SIZE
        })

        -- 左履带-竖直（朝上下时使用，在左右两侧）
        local trackL_v = airui.container({
            parent = tankRoot,
            x = 1,
            y = 1,
            w = 5,
            h = TANK_SIZE - 2,
            color = trackColor,
            radius = 1
        })
        for ri = 1, 4 do
            local ry = 2 + (ri - 1) * 6
            airui.container({
                parent = trackL_v,
                x = 0, y = ry,
                w = 5, h = 2,
                color = 0x555555
            })
        end

        -- 左履带-水平（朝左右时使用，在上下两侧），初始隐藏
        local trackL_h = airui.container({
            parent = tankRoot,
            x = 1,
            y = 1,
            w = TANK_SIZE - 2,
            h = 5,
            color = trackColor,
            radius = 1
        })
        if trackL_h.set_hidden then trackL_h:set_hidden(true) end
        for ri = 1, 4 do
            local rx = 2 + (ri - 1) * 6
            airui.container({
                parent = trackL_h,
                x = rx, y = 0,
                w = 2, h = 5,
                color = 0x555555
            })
        end

        -- 右履带-竖直（朝上下时使用，在左右两侧）
        local trackR_v = airui.container({
            parent = tankRoot,
            x = TANK_SIZE - 6,
            y = 1,
            w = 5,
            h = TANK_SIZE - 2,
            color = trackColor,
            radius = 1
        })
        for ri = 1, 4 do
            local ry = 2 + (ri - 1) * 6
            airui.container({
                parent = trackR_v,
                x = 0, y = ry,
                w = 5, h = 2,
                color = 0x555555
            })
        end

        -- 右履带-水平（朝左右时使用，在上下两侧），初始隐藏
        local trackR_h = airui.container({
            parent = tankRoot,
            x = 1,
            y = TANK_SIZE - 6,
            w = TANK_SIZE - 2,
            h = 5,
            color = trackColor,
            radius = 1
        })
        if trackR_h.set_hidden then trackR_h:set_hidden(true) end
        for ri = 1, 4 do
            local rx = 2 + (ri - 1) * 6
            airui.container({
                parent = trackR_h,
                x = rx, y = 0,
                w = 2, h = 5,
                color = 0x555555
            })
        end

        -- 车身（主色）
        airui.container({
            parent = tankRoot,
            x = 6, y = 2,
            w = TANK_SIZE - 12,
            h = TANK_SIZE - 4,
            color = tankColor,
            radius = 1
        })

        -- 车身暗色下边缘（增加立体感）
        airui.container({
            parent = tankRoot,
            x = 6,
            y = TANK_SIZE - 5,
            w = TANK_SIZE - 12,
            h = 3,
            color = dimColor(tankColor, 0.8)
        })

        -- 炮塔底座（稍暗，圆形）
        airui.container({
            parent = tankRoot,
            x = 8, y = 8,
            w = TANK_SIZE - 16,
            h = TANK_SIZE - 16,
            color = tankColor,
            radius = (TANK_SIZE - 16) / 2
        })

        -- 炮塔上层（亮色，圆形）
        airui.container({
            parent = tankRoot,
            x = 10, y = 10,
            w = TANK_SIZE - 20,
            h = TANK_SIZE - 20,
            color = turretColor,
            radius = (TANK_SIZE - 20) / 2
        })

        -- 炮管底座（宽，居中）
        airui.container({
            parent = tankRoot,
            x = math.floor(TANK_SIZE / 2) - 3,
            y = 8,
            w = 6, h = 6,
            color = tankColor,
            radius = 1
        })

        -- 炮管（方向可变，初始朝上）
        local barrel = airui.container({
            parent = tankRoot,
            x = 9, y = 0,
            w = 4, h = 6,
            color = turretColor,
            radius = 1
        })

        -- 炮口（方向可变，初始朝上）
        local muzzle = airui.container({
            parent = tankRoot,
            x = 8, y = 0,
            w = 6, h = 2,
            color = 0x222222,
            radius = 0
        })

        ui_pool.tanks[tank.playerNum] = tankRoot
        ui_pool.tank_barrels[tank.playerNum] = barrel
        ui_pool.tank_muzzles[tank.playerNum] = muzzle
        ui_pool.tank_track_l[tank.playerNum] = {v = trackL_v, h = trackL_h}
        ui_pool.tank_track_r[tank.playerNum] = {v = trackR_v, h = trackR_h}
    end

    -- 预创建子弹UI池
    for i = 1, MAX_BULLETS do
        ui_pool.bullets[i] = airui.container({
            parent = game_elements_container,
            x = -100,
            y = -100,
            w = 8,
            h = 8,
            color = COLOR_BULLET,
            radius = 4
        })
        if ui_pool.bullets[i].set_hidden then
            ui_pool.bullets[i]:set_hidden(true)
        end
    end

    ui_pool.initialized = true
    log.info('tank_battle', 'UI pool initialized: ' .. #ui_pool.walls .. ' walls')
end

-- 销毁UI对象池（逐个销毁每个UI元素）
local function destroyUIPool()
    -- 销毁墙体
    for _, ref in ipairs(ui_pool.walls) do
        if ref and ref.destroy then
            ref:destroy()
        end
    end
    -- 销毁坦克
    for _, ref in pairs(ui_pool.tanks) do
        if ref and ref.destroy then
            ref:destroy()
        end
    end
    -- 销毁子弹
    for _, ref in ipairs(ui_pool.bullets) do
        if ref and ref.destroy then
            ref:destroy()
        end
    end
    ui_pool.walls = {}
    ui_pool.tanks = {}
    ui_pool.tank_barrels = {}
    ui_pool.tank_muzzles = {}
    ui_pool.tank_track_l = {}
    ui_pool.tank_track_r = {}
    ui_pool.bullets = {}
    ui_pool.initialized = false
end

function renderGame()
    if not game_elements_container then
        return
    end

    if gameState ~= STATE.PLAYING then
        return
    end
    
    -- 首次渲染时初始化UI池
    if not ui_pool.initialized then
        initUIPool()
    end
    
    -- 更新墙体显隐
    for i, wall in ipairs(walls) do
        local ref = ui_pool.walls[i]
        if ref and ref.set_hidden then
            ref:set_hidden(wall.destroyed)
        end
    end
    
    -- 更新坦克位置和朝向（多部件拼装，按方向动态定位炮管炮口）
    for _, tank in ipairs(tanks) do
        local ref = ui_pool.tanks[tank.playerNum]
        if ref then
            if ref.set_pos then
                ref:set_pos(tank.x - TANK_HALF, tank.y - TANK_HALF)
            end

            -- 根据坦克方向调整炮管和炮口位置（airui.container不支持旋转，改用动态定位）
            local barrelRef = ui_pool.tank_barrels[tank.playerNum]
            local muzzleRef = ui_pool.tank_muzzles[tank.playerNum]
            if tank.dir.x == 0 and tank.dir.y == -1 then
                -- 朝上
                if barrelRef and barrelRef.set_pos then
                    barrelRef:set_pos(9, 0)
                    if barrelRef.set_size then barrelRef:set_size(4, 6) end
                end
                if muzzleRef and muzzleRef.set_pos then
                    muzzleRef:set_pos(8, 0)
                    if muzzleRef.set_size then muzzleRef:set_size(6, 2) end
                end
            elseif tank.dir.x == 0 and tank.dir.y == 1 then
                -- 朝下
                if barrelRef and barrelRef.set_pos then
                    barrelRef:set_pos(9, 16)
                    if barrelRef.set_size then barrelRef:set_size(4, 6) end
                end
                if muzzleRef and muzzleRef.set_pos then
                    muzzleRef:set_pos(8, 20)
                    if muzzleRef.set_size then muzzleRef:set_size(6, 2) end
                end
            elseif tank.dir.x == -1 and tank.dir.y == 0 then
                -- 朝左
                if barrelRef and barrelRef.set_pos then
                    barrelRef:set_pos(0, 9)
                    if barrelRef.set_size then barrelRef:set_size(6, 4) end
                end
                if muzzleRef and muzzleRef.set_pos then
                    muzzleRef:set_pos(0, 8)
                    if muzzleRef.set_size then muzzleRef:set_size(2, 6) end
                end
            elseif tank.dir.x == 1 and tank.dir.y == 0 then
                -- 朝右
                if barrelRef and barrelRef.set_pos then
                    barrelRef:set_pos(16, 9)
                    if barrelRef.set_size then barrelRef:set_size(6, 4) end
                end
                if muzzleRef and muzzleRef.set_pos then
                    muzzleRef:set_pos(20, 8)
                    if muzzleRef.set_size then muzzleRef:set_size(2, 6) end
                end
            end

            -- 根据朝向切换履带显示（朝上下用竖直履带，朝左右用水平履带）
            local trackLV = ui_pool.tank_track_l[tank.playerNum]
            local trackRV = ui_pool.tank_track_r[tank.playerNum]
            if trackLV and trackRV then
                local useV = (tank.dir.x == 0)  -- 朝上或朝下时为true
                if trackLV.v and trackLV.v.set_hidden then trackLV.v:set_hidden(not useV) end
                if trackLV.h and trackLV.h.set_hidden then trackLV.h:set_hidden(useV) end
                if trackRV.v and trackRV.v.set_hidden then trackRV.v:set_hidden(not useV) end
                if trackRV.h and trackRV.h.set_hidden then trackRV.h:set_hidden(useV) end
            end

            if ref.set_hidden then
                -- 无敌状态下闪烁（每100ms切换一次，前50ms显示后50ms隐藏）
                local isInvincible = tank.alive and getTimestamp() < tank.invincibleUntil
                local blinkHidden = isInvincible and (tank.flashTimer or 0) >= 50
                ref:set_hidden(not tank.alive or blinkHidden)
            end
        end
    end
    
    -- 更新子弹位置
    for i = 1, MAX_BULLETS do
        local ref = ui_pool.bullets[i]
        if ref then
            local bullet = bullets[i]
            if bullet then
                if ref.set_pos then
                    ref:set_pos(bullet.x - bullet.size / 2, bullet.y - bullet.size / 2)
                end
                if ref.set_hidden then
                    ref:set_hidden(false)
                end
            else
                if ref.set_hidden then
                    ref:set_hidden(true)
                end
            end
        end
    end
end

-- ==================== 帮助弹窗 ====================

local help_dialog_container = nil

local function showHelpDialog()
    if help_dialog_container then
        help_dialog_container:destroy()
        help_dialog_container = nil
    end

    -- 全屏弹窗容器（参考竖屏错误版本）
    help_dialog_container = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = W,
        h = H,
        color = 0xFFFFFF,  -- 白色背景
    })

    -- 标题
    airui.label({
        parent = help_dialog_container,
        x = 0,
        y = 40,
        w = W,
        h = 48,
        text = "游戏帮助",
        font_size = 32,
        color = 0x333333,
        align = airui.TEXT_ALIGN_CENTER,
    })

    local line_y = 120
    local line_h = 44

    -- 游戏规则标题（绿色）
    airui.label({
        parent = help_dialog_container,
        x = 30,
        y = line_y,
        w = W - 60,
        h = line_h,
        text = "【游戏规则】",
        font_size = 24,
        color = 0x228844,
        align = airui.TEXT_ALIGN_LEFT,
    })
    line_y = line_y + line_h

    -- 游戏规则内容（每行简短，避免换行）
    local game_rules = {
        "● 每局 2 名玩家，先耗尽生命值者判负",
        "● 初始生命值：3 条命",
        "● 每次被击中扣 1 点受击计数",
        "● 累计 3 次受击掉 1 条命",
        "● 生命值归零后仍可继续战斗",
        "● 再被击中 3 次则游戏结束",
        "● 重生后有 5 秒无敌时间",
    }
    for _, line in ipairs(game_rules) do
        airui.label({
            parent = help_dialog_container,
            x = 30,
            y = line_y,
            w = W - 60,
            h = line_h,
            text = line,
            font_size = 22,
            color = 0x333333,
            align = airui.TEXT_ALIGN_LEFT,
        })
        line_y = line_y + line_h
    end

    line_y = line_y + 20  -- 空行

    -- 积分规则标题（红色）
    airui.label({
        parent = help_dialog_container,
        x = 30,
        y = line_y,
        w = W - 60,
        h = line_h,
        text = "【积分规则】",
        font_size = 24,
        color = 0xCC4444,
        align = airui.TEXT_ALIGN_LEFT,
    })
    line_y = line_y + line_h

    -- 积分规则内容
    local score_rules = {
        "● 击中敌方坦克：+2 分",
        "● 被敌方坦克击中：-1 分",
        "● KO对方获胜：额外 +5 分",
    }
    for _, line in ipairs(score_rules) do
        airui.label({
            parent = help_dialog_container,
            x = 30,
            y = line_y,
            w = W - 60,
            h = line_h,
            text = line,
            font_size = 22,
            color = 0x333333,
            align = airui.TEXT_ALIGN_LEFT,
        })
        line_y = line_y + line_h
    end

    -- 关闭按钮（居中底部）
    airui.button({
        parent = help_dialog_container,
        x = (W - 140) / 2,
        y = H - 100,
        w = 140,
        h = 52,
        text = "关闭",
        font_size = 22,
        style = { bg_color = 0x884444, text_color = 0xFFFFFF, border_width = 0, radius = 10 },
        on_click = function()
            if help_dialog_container then
                help_dialog_container:destroy()
                help_dialog_container = nil
            end
        end,
    })
end

-- ==================== 房间等待UI ====================

-- 更新房间UI（玩家列表、按钮状态）
updateRoomUI = function()
    if not room_waiting_container then return end
    
    -- 获取房间信息
    local room_info = expvp.get_room_info()
    is_host_player = room_info.is_host
    current_room_id = room_info.room_id
    local players = room_info.players or {}
    local player_count = expvp.get_player_count()
    room_has_enough = player_count >= 2
    -- 同步自己的准备状态（确保与网络模块一致）
    my_ready = room_info.my_ready
    
    -- 更新状态标签
    if room_status_label then
        local room_code = room_info.room_code or (current_room_id and current_room_id:sub(-6) or "---")
        -- 去掉 room_ 前缀
        room_code = room_code:gsub("^room_", "")
        local status_text = "房间码: " .. room_code .. "  在线: " .. player_count .. "/2"
        room_status_label:set_text(status_text)
    end
    
    -- 更新玩家列表（2个位置）
    local player_names = {"P1", "P2"}
    -- 构建玩家映射表: player_number -> {device_id, nickname, ready}
    local player_slots = {}
    -- 房主（自己）是P1
    player_slots[1] = {
        device_id = my_device_id,
        nickname = get_nickname() .. " [你]",
        ready = expvp.get_room_info().my_ready,
    }
    -- 其他玩家按顺序填入P2
    local slot = 2
    for device_id, pinfo in pairs(players) do
        if device_id ~= my_device_id and slot <= 2 then
            local pname = (pinfo.nickname or device_id:sub(-6))
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
            item.bg:set_color((i % 2 == 0) and 0x1e293b or 0x16213e)
            if item.label then
                item.label:set_text(player_names[i] .. " " .. ps.nickname)
            end
            if item.ready_label then
                item.ready_label:set_text(ready_text)
                item.ready_label:set_color(color)
            end
            if item.bg.set_hidden then item.bg:set_hidden(false) end
        else
            -- 空位
            if item.bg.set_hidden then item.bg:set_hidden(false) end
            item.bg:set_color(0x0a0a1a)
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
    if room_ready_btn and room_ready_btn.set_text then
        room_ready_btn:set_text(my_ready and "取消准备" or "准备")
    end
    
    -- 更新开始按钮状态（仅房主可见）
    if room_start_btn then
        if is_host_player then
            if room_start_btn.set_hidden then room_start_btn:set_hidden(false) end
            -- 按钮点击时内部会检查条件
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
        color = 0x0d1117,
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
    
    -- 房间状态
    room_status_label = airui.label({
        parent = room_waiting_container,
        x = 0, y = 90, w = W, h = 24,
        text = "房间ID: ---  在线: 1/4",
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
    local slot_height = 50  -- 增加高度以适应更大的字体
    for i = 1, 2 do
        local y = slot_start_y + (i - 1) * (slot_height + 8)  -- 增加间隙
        local bg = airui.container({
            parent = room_waiting_container,
            x = cx - 180, y = y, w = 360, h = slot_height,
            color = 0x16213e,
            radius = 6,
        })
        local label = airui.label({
            parent = room_waiting_container,
            x = cx - 170, y = y + 12, w = 200, h = 26,  -- 调整位置和高度
            text = "P" .. i .. " 等待加入...",
            font_size = 20,  -- 适当减小字体以确保显示完整
            color = 0xffffff,
            align = airui.TEXT_ALIGN_LEFT,
        })
        local ready_label = airui.label({
            parent = room_waiting_container,
            x = cx + 40, y = y + 12, w = 130, h = 26,  -- 调整位置和高度
            text = "---",
            font_size = 20,  -- 适当减小字体
            color = 0x888888,
            align = airui.TEXT_ALIGN_RIGHT,
        })
        room_player_list[i] = {bg = bg, label = label, ready_label = ready_label}
    end
    
    -- 三个按钮垂直排列：准备 | 开始游戏（房主） | 离开房间
    local btn_start_y = slot_start_y + 2 * (slot_height + 8) + 30
    local btn_w = 200  -- 更宽
    local btn_h = 55   -- 更高
    local btn_gap = 15 -- 垂直间隙
    local btn_x = cx - btn_w / 2  -- 居中
    
    room_ready_btn = airui.button({
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
            log.info('tank_battle', '房主开始游戏')
            expvp.start_game()
        end,
    })
    
    -- 离开房间按钮
    room_leave_btn = airui.button({
        parent = room_waiting_container,
        x = btn_x, y = btn_start_y + (btn_h + btn_gap) * 2, w = btn_w, h = btn_h,
        text = "离开房间",
        font_size = 20,
        style = { bg_color = 0x884444, text_color = 0xFFFFFF, border_width = 0, radius = 10 },
        on_click = function()
            log.info('tank_battle', '离开房间')
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
    if menu_container then
        menu_container:hide()
    end
    if matchingContainer then
        matchingContainer:destroy()
        matchingContainer = nil
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

-- ==================== 创建/加入房间 ====================

-- 创建房间
onCreateRoom = function()
    log.info('tank_battle', '创建房间')
    my_ready = false
    is_host_player = true
    networkMode = true
    gameState = STATE.ROOM_WAITING
    
    -- 创建房间
    expvp.create_room(function(success, room_id)
        if success then
            current_room_id = room_id
            log.info('tank_battle', '房间创建成功:', room_id)
            buildRoomWaitingUI()
            showRoomWaitingUI()
            showToast("房间已创建，等待其他玩家加入...")
        else
            showToast("创建房间失败")
            showMainMenu()
        end
    end)
end

-- 加入房间弹窗（输入房间ID）
local join_dialog_container = nil
local join_input_label = nil
local join_input_text = ""

showJoinDialog = function()
    if join_dialog_container then
        join_dialog_container:destroy()
        join_dialog_container = nil
    end
    
    join_input_text = ""
    
    -- 全屏弹窗，覆盖背后的坦克大战标题
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
    log.info('tank_battle', '加入房间:', room_id)
    my_ready = false
    is_host_player = false
    networkMode = true
    gameState = STATE.ROOM_WAITING
    
    expvp.join_room(room_id, function(success)
        if success then
            current_room_id = room_id
            log.info('tank_battle', '加入房间成功:', room_id)
            buildRoomWaitingUI()
            showRoomWaitingUI()
            showToast("已加入房间，请点击准备")
        else
            showToast("加入房间失败")
            showMainMenu()
        end
    end)
end
-- ==================== 位置同步相关函数 ====================

-- 位置同步定时器
local game_ui_container = nil

showMainMenu = function()
    if menu_container then
        menu_container:open()
    end
    if game_ui_container then
        game_ui_container:hide()
    end
    -- 清理房间状态
    hideRoomWaitingUI()
    room_players = {}
    my_player_number = 1
    my_ready = false
    is_host_player = false
    room_has_enough = false
    gameState = STATE.MENU
end

-- ==================== 发送移动/开火消息（联机点按模式） ====================

-- 联机模式：点按一次，向对方发送"移动一格"指令
local function sendMoveMessage(direction)
    if not networkMode then return end
    local msg = {
        type = "move",
        player_num = my_player_number,
        direction = direction,  -- 'up'/'down'/'left'/'right'
        from_device = my_device_id,
    }
    log.info('tank_battle', string.format('发送move: my_player_number=%s, dir=%s', tostring(my_player_number), direction))
    if current_room_id then
        expvp.broadcast_to_room(msg)
    elseif game_state.peer_device_id then
        expvp.send_to_device(game_state.peer_device_id, msg)
    end
end

-- 联机模式：点按开火，向对方发送"开火"指令
local function sendShootMessage()
    if not networkMode then return end
    
    -- 检查冷却时间：本地坦克必须在可射击状态才能发送
    local tank = tanks[my_player_number]
    if not tank or not tank.alive then return end
    if getTimestamp() < tank.shootCooldownUntil then 
        log.info('tank_battle', 'sendShootMessage: 冷却中，忽略')
        return 
    end
    
    local msg = {
        type = "shoot",
        player_num = my_player_number,
        from_device = my_device_id,
    }
    log.info('tank_battle', string.format('发送shoot: my_player_number=%s', tostring(my_player_number)))
    if current_room_id then
        expvp.broadcast_to_room(msg)
    elseif game_state.peer_device_id then
        expvp.send_to_device(game_state.peer_device_id, msg)
    end
end

-- 联机模式：定时广播自己的绝对位置，修正对手画面中的位置漂移
-- 使用格子坐标（grid_x, grid_y）而非像素坐标，确保横竖屏同步一致
local function sendPosSync()
    if not networkMode then return end
    local tank = tanks[my_player_number]
    if not tank or not tank.alive then return end
    local msg = {
        type = "sync_pos",
        player_num = my_player_number,
        grid_x = tank.x / CELL,  -- 发送格子坐标（如 2.5 表示第2.5格）
        grid_y = tank.y / CELL,
        direction = nil,
        from_device = my_device_id,
    }
    -- 计算方向向量转方向名
    if tank.dir.x == 0 and tank.dir.y == -1 then
        msg.direction = "up"
    elseif tank.dir.x == 0 and tank.dir.y == 1 then
        msg.direction = "down"
    elseif tank.dir.x == -1 and tank.dir.y == 0 then
        msg.direction = "left"
    elseif tank.dir.x == 1 and tank.dir.y == 0 then
        msg.direction = "right"
    end
    if current_room_id then
        expvp.broadcast_to_room(msg)
    elseif game_state.peer_device_id then
        expvp.send_to_device(game_state.peer_device_id, msg)
    end
end

-- 发送退出通知给对方（参考火柴人）
sendOpponentLeft = function()
    if not networkMode then return end
    if current_room_id then
        -- 房间模式：广播到房间
        expvp.broadcast_to_room({
            type = "opponent_left",
            from_device = my_device_id,
        })
    elseif game_state.peer_device_id then
        -- 匹配模式：点对点发送
        expvp.send_to_device(game_state.peer_device_id, {
            type = "opponent_left",
            from_device = my_device_id,
        })
    end
    log.info('tank_battle', '已发送退出通知给对方')
    -- 游戏中途退出也上传积分
    uploadGameScore()
end

local function showGameUI()
    log.info('tank_battle', 'showGameUI called')
    if menu_container then
        menu_container:hide()
    end
    if game_ui_container then
        game_ui_container:open()
        log.info('tank_battle', 'game_ui_container:open() called')
    end
    -- game_elements_container 是 game_ui_container 的子元素，自动随父显隐
end

local function buildMainMenu()
    -- 主菜单容器（全屏）
    menu_container = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = W,
        h = H,
        color = 0x0a0f1e
    })
    
    -- 背景图（使用坦克背景）- 使用 /luadb/ 前缀，res目录内容被挂载到luadb
    log.info('tank_battle', '加载背景图: /luadb/tank_background.jpg')
    airui.image({
        parent = menu_container,
        x = 0,
        y = 0,
        w = W,
        h = H,
        src = "/luadb/tank_background.jpg",
        fit = "cover"
    })

    -- 标题 - "坦克大战"（下移居中）
    airui.label({
        parent = menu_container,
        x = 0,
        y = 120,  -- 从80下移到120
        w = W,
        h = 70,
        text = "坦 克 大 战",
        font_size = 52,  -- 字体稍大
        color = 0xf0c040,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 按钮布局参数（增大按钮和字体，整体下移）
    local btn_w = 260      -- 按钮宽度
    local btn_h = 52       -- 按钮高度
    local btn_x = (W - btn_w) / 2  -- 水平居中
    local btn_gap = 10     -- 按钮间距
    local start_y = 210    -- 第一个按钮Y坐标（整体下移）

    -- 单机对战按钮
    airui.button({
        parent = menu_container,
        x = btn_x,
        y = start_y,
        w = btn_w,
        h = btn_h,
        text = "单机对战",
        font_size = 26,
        style = { bg_color = 0x2a3f5f, text_color = 0xFFFFFF, border_width = 0, radius = 10 },
        on_click = function()
            networkMode = false
            showGameUI()
            startGame()
        end,
    })

    -- 快速匹配按钮
    airui.button({
        parent = menu_container,
        x = btn_x,
        y = start_y + btn_h + btn_gap,
        w = btn_w,
        h = btn_h,
        text = "快速匹配",
        font_size = 26,
        style = { bg_color = 0x2a3f5f, text_color = 0xFFFFFF, border_width = 0, radius = 10 },
        on_click = function()
            startQuickMatch()
        end,
    })

    -- 创建房间按钮（与快速匹配、加入房间一起上下排列）
    airui.button({
        parent = menu_container,
        x = btn_x,
        y = start_y + (btn_h + btn_gap) * 2,
        w = btn_w,
        h = btn_h,
        text = "创建房间",
        font_size = 26,
        style = { bg_color = 0x2a3f5f, text_color = 0xFFFFFF, border_width = 0, radius = 10 },
        on_click = function()
            onCreateRoom()
        end,
    })

    -- 加入房间按钮（与创建房间、快速匹配一起上下排列）
    airui.button({
        parent = menu_container,
        x = btn_x,
        y = start_y + (btn_h + btn_gap) * 3,
        w = btn_w,
        h = btn_h,
        text = "加入房间",
        font_size = 26,
        style = { bg_color = 0x2a3f5f, text_color = 0xFFFFFF, border_width = 0, radius = 10 },
        on_click = function()
            showJoinDialog()
        end,
    })

    -- 排行榜按钮
    airui.button({
        parent = menu_container,
        x = btn_x,
        y = start_y + (btn_h + btn_gap) * 4,
        w = btn_w,
        h = btn_h,
        text = "排行榜",
        font_size = 26,
        style = { bg_color = 0x2a3f5f, text_color = 0xFFFFFF, border_width = 0, radius = 10 },
        on_click = function()
            openLeaderboardWin()
        end,
    })

    -- 帮助按钮
    airui.button({
        parent = menu_container,
        x = btn_x,
        y = start_y + (btn_h + btn_gap) * 5,
        w = btn_w,
        h = btn_h,
        text = "帮助",
        font_size = 26,
        style = { bg_color = 0x2a3f5f, text_color = 0xFFFFFF, border_width = 0, radius = 10 },
        on_click = function()
            showHelpDialog()
        end,
    })

    -- 退出按钮
    airui.button({
        parent = menu_container,
        x = btn_x,
        y = start_y + (btn_h + btn_gap) * 6,
        w = btn_w,
        h = btn_h,
        text = "退出",
        font_size = 28,
        style = { bg_color = 0x884444, text_color = 0xFFFFFF, border_width = 0, radius = 10 },
        on_click = function()
            log.info('tank_battle', '退出按钮点击, win_id=' .. tostring(win_id))
            -- 游戏中退出时通知对方
            if gameState == STATE.PLAYING or gameState == STATE.GAME_OVER then
                sendOpponentLeft()
            end
            if win_id then
                log.info('tank_battle', '正在关闭窗口...')
                exwin.close(win_id)
            else
                log.info('tank_battle', 'win_id为nil，无法关闭')
            end
        end,
    })
    
    -- 版本信息
    local version_label = airui.label({
        parent = menu_container,
        x = W - 80,
        y = H - 25,
        w = 60,
        h = 18,
        text = "v" .. GAME_VERSION,
        color = 0x666666,
        font_size = 18,
        align = 2
    })
end

-- ==================== 构建游戏UI ====================

local function buildGameUI()
    game_ui_container = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = W,
        h = H,
        color = 0x2d2d2d  -- Switch风格深灰色背景
    })
    game_ui_container:hide()

    -- ============ 顶部 HUD（两行布局）============
    local hud = airui.container({
        parent = game_ui_container,
        x = 0,
        y = 0,
        w = W,
        h = HUD_H,
        -- color = 0x1a1a2e  -- 与战斗区域背景一致
    })

    -- 第一行：标题（左上角）和退出按钮（右上角）
    -- 标题
    ui.title_label = airui.label({
        parent = hud,
        x = 8,
        y = 8,
        w = 120,
        h = 26,
        text = "坦克大战",
        color = 0xFFFFFF,
        font_size = 20,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 退出按钮（增大一倍，与边缘留出距离）
    local backBtn = airui.button({
        parent = hud,
        x = W - 100,
        y = 12,
        w = 80,
        h = 50,
        text = "退出",
        font_size = 22,
        style = {
            bg_color = 0xe60012,
            text_color = 0xFFFFFF,
            border_width = 0,
            radius = 6,
            pressed_bg_color = 0x990000  -- 按下时变深红色
        },
        on_click = function()
            -- 游戏中退出时通知对方
            if gameState == STATE.PLAYING or gameState == STATE.GAME_OVER then
                sendOpponentLeft()
            end
            showMainMenu()
        end
    })

    -- 第二行到第三行：P1、P2 信息（各占一行）
    -- 玩家1信息（绿色 - 玩家自己）
    ui.score_p1 = airui.label({
        parent = hud,
        x = 8,
        y = 42,
        w = 240,
        h = 24,
        text = "[你]P1 生命:3 分数:0",
        color = 0x4ecb71,
        font_size = 18,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 玩家2信息（蓝色 - 机器）
    ui.score_p2 = airui.label({
        parent = hud,
        x = 8,
        y = 70,
        w = 240,
        h = 24,
        text = "[机器]P2 生命:3 分数:0",
        color = 0x4da6ff,
        font_size = 18,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 只创建2个玩家（参考横屏版）

    -- 兼容旧引用
    ui.lives_p1 = ui.score_p1
    ui.lives_p2 = ui.score_p2
    
    -- 本局积分标签（保留引用但不再显示在HUD上，用于兼容旧代码）
    scoreLabel = ui.score_p1

    -- ============ 游戏区域（被灰色砖块边框包围）============
    local BORDER_COLOR = 0x808080
    -- 上边框
    airui.container({
        parent = game_ui_container,
        x = GAME_AREA_X - BORDER_THICK,
        y = GAME_AREA_Y - BORDER_THICK,
        w = GAME_AREA_W + BORDER_THICK * 2,
        h = BORDER_THICK,
        color = BORDER_COLOR
    })
    -- 下边框
    airui.container({
        parent = game_ui_container,
        x = GAME_AREA_X - BORDER_THICK,
        y = GAME_AREA_Y + GAME_AREA_H,
        w = GAME_AREA_W + BORDER_THICK * 2,
        h = BORDER_THICK,
        color = BORDER_COLOR
    })
    -- 左边框
    airui.container({
        parent = game_ui_container,
        x = GAME_AREA_X - BORDER_THICK,
        y = GAME_AREA_Y,
        w = BORDER_THICK,
        h = GAME_AREA_H,
        color = BORDER_COLOR
    })
    -- 右边框
    airui.container({
        parent = game_ui_container,
        x = GAME_AREA_X + GAME_AREA_W,
        y = GAME_AREA_Y,
        w = BORDER_THICK,
        h = GAME_AREA_H,
        color = BORDER_COLOR
    })

    -- 游戏元素容器（仅游戏区域大小，元素坐标系相对此容器）
    game_elements_container = airui.container({
        parent = game_ui_container,
        x = GAME_AREA_X,
        y = GAME_AREA_Y,
        w = GAME_AREA_W,
        h = GAME_AREA_H
        -- 不设置背景色，避免遮挡按钮
    })
    -- 禁用容器的滚动条（防止子元素超出时出现滚动条）
    if game_elements_container.set_scrollbar_mode then
        game_elements_container:set_scrollbar_mode(0)  -- 0 = LV_SCROLLBAR_MODE_OFF
    end
    if game_elements_container.clear_flag then
        -- 清除可滚动标志（LV_OBJ_FLAG_SCROLLABLE = 1 << 4 = 16）
        game_elements_container:clear_flag(16)
    end

    -- ============ 下方方向键（游戏区域外）============
    -- 竖屏布局：方向键靠左下，开火放右边
    -- 按钮区域：Y=496~800, 高度304px
    local btn_size = 55  -- 方向按钮尺寸
    local gap = 8        -- 按钮间隙
    -- 方向键靠左下放置
    local left_offset = 30
    -- 方向键中心点计算（左下区域）
    local cx = math.floor(left_offset + btn_size + gap + btn_size / 2)  -- 约105，取整
    -- 将按钮下移，确保不被 game_elements_container 遮挡
    -- game_elements_container 底部在 Y = GAME_AREA_Y + GAME_AREA_H = 160 + 336 = 496
    -- 上按钮的顶部 = cy - btn_size - gap - btn_size/2 = cy - 90
    -- 要让上按钮完全在 496 以下，需要 cy > 496 + 90 = 586
    local cy = 640  -- 固定值，确保所有按钮都在游戏区域下方

    -- 各方向按钮矩形（供 touch 订阅判定长按）
    -- 上按钮
    local up_x = math.floor(cx - btn_size / 2)
    local up_y = math.floor(cy - btn_size - gap - btn_size / 2)
    -- 下按钮
    local down_x = math.floor(cx - btn_size / 2)
    local down_y = math.floor(cy + btn_size / 2 + gap)
    -- 左按钮
    local left_x = math.floor(cx - btn_size - gap - btn_size / 2)
    local left_y = math.floor(cy - btn_size / 2)
    -- 右按钮
    local right_x = math.floor(cx + btn_size / 2 + gap)
    local right_y = math.floor(cy - btn_size / 2)

    -- 开火按钮放在右侧，与方向键同一高度
    local fire_size = 75  -- 开火按钮
    -- 靠右放置
    local fire_x = math.floor(W - 40 - fire_size / 2)  -- 约402，转换为整数
    local fire_y = cy  -- 与方向按钮垂直居中对齐
    log.info('tank_battle', string.format('fire_x=%s, fire_y=%s, fire_size=%s, W=%s, cy=%s', tostring(fire_x), tostring(fire_y), tostring(fire_size), tostring(W), tostring(cy)))

    -- 注意：dir_btn_rects 坐标需要与 touch_subscribe 返回的坐标系统一致。
    -- touch_subscribe 返回的坐标是相对于屏幕的（0,0）-（W,H）
    -- 按钮的 parent 是 game_ui_container，其位置是 (0, 0) 相对于 main_container
    -- 而 main_container 的 parent 是 airui.screen，位置也是 (0, 0)
    -- 因此按钮在屏幕上的绝对坐标就是其在 game_ui_container 中的坐标
    -- 不需要添加 GAME_AREA_X 偏移
    dir_btn_rects = {
        up    = { x = up_x, y = up_y, w = btn_size, h = btn_size, dir = 'up'    },
        down  = { x = down_x, y = down_y,  w = btn_size, h = btn_size, dir = 'down'  },
        left  = { x = left_x, y = left_y,  w = btn_size, h = btn_size, dir = 'left'  },
        right = { x = right_x, y = right_y, w = btn_size, h = btn_size, dir = 'right' },
    }

    -- 调试log：打印方向按钮矩形区域坐标和触摸坐标
    log.info("tank_battle", "方向按钮矩形区域(竖屏左下布局):")
    log.info("tank_battle", "dir_btn_rects=" .. tostring(dir_btn_rects))
    for dir, rect in pairs(dir_btn_rects) do
        log.info("tank_battle", string.format('  %s: x=%d~%d, y=%d~%d', dir, rect.x, rect.x+rect.w, rect.y, rect.y+rect.h))
    end
    log.info("tank_battle", string.format('开火按钮位置: x=%.1f, y=%.1f, size=%d', fire_x, fire_y, fire_size))
    log.info('tank_battle', '准备创建按钮...')

    -- on_click 兜底：在某些环境下 touch 订阅不可用时，至少能"瞬间转向"
    local function set_facing(dir)
        if not tanks[1] then return end
        p1_facing = dir
        if dir == 'up' then tanks[1].dir = { x = 0, y = -1 }
        elseif dir == 'down' then tanks[1].dir = { x = 0, y = 1 }
        elseif dir == 'left' then tanks[1].dir = { x = -1, y = 0 }
        elseif dir == 'right' then tanks[1].dir = { x = 1, y = 0 } end
    end

    -- 上
    log.info('tank_battle', '创建上按钮: x=' .. tostring(up_x) .. ', y=' .. tostring(up_y))
    local btn_up = airui.button({
        parent = game_ui_container,
        x = up_x, y = up_y, w = btn_size, h = btn_size,
        text = "↑",
        font_size = 28,
        style = {
            bg_color = 0x444444,
            text_color = 0xFFFFFF,
            border_width = 0,
            radius = 8,
            pressed_bg_color = 0x666666  -- 按下时变亮
        },
        on_click = function()
            if networkMode then
                -- 联机模式：点按一次移动一格（本地 + 通知对方）
                sendMoveMessage('up')
                -- 本地立即执行移动
                local myTank = tanks[my_player_number]
                if myTank and myTank.alive then
                    myTank:moveOneStep('up', CELL)
                end
            end
            -- 单机模式：不使用 on_click，由 on_pressed/on_released 处理
        end,
        -- 单机模式：按住移动，松开停止
        on_pressed = function()
            -- 防止重复触发
            if btn_pressed_state.up then return end
            btn_pressed_state.up = true
            btn_input.up = true
            -- log.info("tank_battle", "[BUTTON] 上按钮按下")
        end,
        on_released = function()
            -- 防止重复触发
            if not btn_pressed_state.up then return end
            btn_pressed_state.up = false
            btn_input.up = false
            -- log.info("tank_battle", "[BUTTON] 上按钮释放")
        end,
    })
    log.info('tank_battle', '上按钮创建结果: ' .. tostring(btn_up))

    -- 下
    log.info('tank_battle', '创建下按钮: x=' .. tostring(down_x) .. ', y=' .. tostring(down_y))
    local btn_down = airui.button({
        parent = game_ui_container,
        x = down_x, y = down_y, w = btn_size, h = btn_size,
        text = "↓",
        font_size = 28,
        style = {
            bg_color = 0x444444,
            text_color = 0xFFFFFF,
            border_width = 0,
            radius = 8,
            pressed_bg_color = 0x666666
        },
        on_click = function()
            if networkMode then
                sendMoveMessage('down')
                local myTank = tanks[my_player_number]
                if myTank and myTank.alive then
                    myTank:moveOneStep('down', CELL)
                end
            end
            -- 单机模式：不使用 on_click，由 on_pressed/on_released 处理
        end,
        -- 单机模式：按住移动，松开停止
        on_pressed = function()
            -- 防止重复触发
            if btn_pressed_state.down then return end
            btn_pressed_state.down = true
            btn_input.down = true
            -- log.info("tank_battle", "[BUTTON] 下按钮按下")
        end,
        on_released = function()
            -- 防止重复触发
            if not btn_pressed_state.down then return end
            btn_pressed_state.down = false
            btn_input.down = false
            -- log.info("tank_battle", "[BUTTON] 下按钮释放")
        end,
    })
    log.info('tank_battle', '下按钮创建结果: ' .. tostring(btn_down))

    -- 左
    log.info('tank_battle', '创建左按钮: x=' .. tostring(left_x) .. ', y=' .. tostring(left_y))
    local btn_left = airui.button({
        parent = game_ui_container,
        x = left_x, y = left_y, w = btn_size, h = btn_size,
        text = "←",
        font_size = 28,
        style = {
            bg_color = 0x444444,
            text_color = 0xFFFFFF,
            border_width = 0,
            radius = 8,
            pressed_bg_color = 0x666666
        },
        on_click = function()
            if networkMode then
                sendMoveMessage('left')
                local myTank = tanks[my_player_number]
                if myTank and myTank.alive then
                    myTank:moveOneStep('left', CELL)
                end
            end
            -- 单机模式：不使用 on_click，由 on_pressed/on_released 处理
        end,
        -- 单机模式：按住移动，松开停止
        on_pressed = function()
            -- 防止重复触发
            if btn_pressed_state.left then return end
            btn_pressed_state.left = true
            -- log.info("tank_battle", "[BUTTON] 左按钮按下!")
            btn_input.left = true
        end,
        on_released = function()
            -- 防止重复触发
            if not btn_pressed_state.left then return end
            btn_pressed_state.left = false
            -- log.info("tank_battle", "[BUTTON] 左按钮释放")
            btn_input.left = false
        end,
    })
    log.info('tank_battle', '左按钮创建结果: ' .. tostring(btn_left))

    -- 右
    log.info('tank_battle', '创建右按钮: x=' .. tostring(right_x) .. ', y=' .. tostring(right_y))
    local btn_right = airui.button({
        parent = game_ui_container,
        x = right_x, y = right_y, w = btn_size, h = btn_size,
        text = "→",
        font_size = 28,
        style = {
            bg_color = 0x444444,
            text_color = 0xFFFFFF,
            border_width = 0,
            radius = 8,
            pressed_bg_color = 0x666666
        },
        on_click = function()
            if networkMode then
                sendMoveMessage('right')
                local myTank = tanks[my_player_number]
                if myTank and myTank.alive then
                    myTank:moveOneStep('right', CELL)
                end
            end
            -- 单机模式：不使用 on_click，由 on_pressed/on_released 处理
        end,
        -- 单机模式：按住移动，松开停止
        on_pressed = function()
            -- 防止重复触发
            if btn_pressed_state.right then return end
            btn_pressed_state.right = true
            -- log.info("tank_battle", "[BUTTON] 右按钮按下!")
            btn_input.right = true
        end,
        on_released = function()
            -- 防止重复触发
            if not btn_pressed_state.right then return end
            btn_pressed_state.right = false
            -- log.info("tank_battle", "[BUTTON] 右按钮释放")
            btn_input.right = false
        end,
    })
    log.info('tank_battle', '右按钮创建结果: ' .. tostring(btn_right))

    -- ============ 下方开火按钮（游戏区域外）============
    -- 圆形红色按钮，与横屏版本保持一致
    local btnFire = airui.button({
        parent = game_ui_container,
        x = fire_x - fire_size / 2,
        y = fire_y - fire_size / 2,
        w = fire_size,
        h = fire_size,
        text = "开火",
        font_size = 20,
        style = {
            bg_color = 0xc23b22,
            text_color = 0xFFFFFF,
            border_width = 0,
            radius = fire_size / 2,
            pressed_bg_color = 0xff0000  -- 按下时变亮红色
        },
        on_click = function()
            btn_input.shoot = true
            -- 开火后重置，确保每次点击只发射一发
            sys.timerStart(function()
                btn_input.shoot = false
            end, 50)
            -- log.info("tank_battle", "[touch] 开火按钮点击")
            -- 联机模式也发送开火消息（点按即发射一发）
            if networkMode then
                sendShootMessage()
            end
        end
    })

    -- ============ K.O. 游戏结束弹窗（参考火柴人格斗设计）============
    -- 半透明背景遮罩
    ui.ko_overlay = airui.container({
        parent = game_ui_container,
        x = GAME_AREA_X,
        y = GAME_AREA_Y,
        w = GAME_AREA_W,
        h = GAME_AREA_H,
        color = 0x000000
    })
    ui.ko_overlay:hide()  -- 默认隐藏，避免挡住按钮

    -- K.O.! 大字
    ui.ko_label = airui.label({
        parent = ui.ko_overlay,
        x = 0,
        y = GAME_AREA_H / 2 - 80,
        w = GAME_AREA_W,
        h = 70,
        text = "K.O.!",
        font_size = 56,
        color = 0xff3333,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 获胜者标签
    ui.winner_label = airui.label({
        parent = ui.ko_overlay,
        x = 0,
        y = GAME_AREA_H / 2 - 10,
        w = GAME_AREA_W,
        h = 40,
        text = "",
        font_size = 24,
        color = 0xffd966,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 重新开始按钮
    ui.ko_restart_btn = airui.button({
        parent = ui.ko_overlay,
        x = GAME_AREA_W / 2 - 100,
        y = GAME_AREA_H / 2 + 50,
        w = 90,
        h = 40,
        text = "重新开始",
        font_size = 14,
        style = { bg_color = 0x4ecb71, text_color = 0xFFFFFF, border_width = 0, radius = 6 },
        on_click = function()
            -- 隐藏KO弹窗，重新开始游戏
            if ui.ko_overlay.set_hidden then
                ui.ko_overlay:set_hidden(true)
            end
            startGame()
        end
    })

    -- 返回主菜单按钮
    ui.ko_back_btn = airui.button({
        parent = ui.ko_overlay,
        x = GAME_AREA_W / 2 + 10,
        y = GAME_AREA_H / 2 + 50,
        w = 90,
        h = 40,
        text = "返回菜单",
        font_size = 14,
        style = { bg_color = 0xc23b22, text_color = 0xFFFFFF, border_width = 0, radius = 6 },
        on_click = function()
            if ui.ko_overlay.set_hidden then
                ui.ko_overlay:set_hidden(true)
            end
            showMainMenu()
        end
    })

    -- 初始隐藏
    if ui.ko_overlay.set_hidden then
        ui.ko_overlay:set_hidden(true)
    end

    log.info('tank_battle', 'buildGameUI completed')

    -- 预创建UI对象池（一次性在窗口初始化时创建，永久保留不销毁）
    -- 避免游戏开始时大量创建AirUI容器阻塞主线程导致按钮无响应
    buildMap()
    local temp_tanks = {
        Tank.new(2.5 * CELL, 2.5 * CELL, 0x4ecb71, 1, "玩家1"),
        Tank.new(13.5 * CELL, 9.5 * CELL, 0x4da6ff, 2, "玩家2"),
    }
    tanks = temp_tanks
    initUIPool()
    -- 清理临时数据但不销毁池（池保留，后面renderGame只更新位置不重建）
    walls = {}
    tanks = {}
end

-- ==================== 构建所有UI ====================

local function buildUI()
    log.info('tank_battle', 'buildUI started')
    buildMainMenu()
    buildGameUI()
    log.info('tank_battle', 'buildUI completed')
end

-- ==================== 开始游戏 ====================

function startGame()
    log.info('tank_battle', 'startGame called')
    -- 隐藏 KO 弹窗
    if ui.ko_overlay and ui.ko_overlay.set_hidden then
        ui.ko_overlay:set_hidden(true)
    end
    initGame()
    gameState = STATE.PLAYING

    -- 启动位置同步定时器（250ms 广播一次绝对位置，修正漂移）
    if networkMode and not pos_sync_timer then
        pos_sync_timer = sys.timerLoopStart(function()
            sendPosSync()
        end, 250)
    end

    log.info('tank_battle', 'game started, state = PLAYING')
end

-- ==================== 网络消息处理 ====================

local function onNetworkMessage(data)
    if not data or not data.type then return end

    if data.type == 'presence' then
        local deviceId = data.device_id
        if deviceId and deviceId ~= my_device_id then
            game_state.online_devices[deviceId] = {
                device_id = deviceId,
                device_model = data.device_model or "未知",
                nickname = data.nickname or deviceId:sub(-6),
                last_seen = getTimestamp()
            }
        end
    elseif data.type == 'move' then
        -- 联机点按模式：收到对方的"移动一格"指令
        if not networkMode then return end
        if data.from_device == my_device_id then return end

        -- 双方设备上都有 P1 和 P2 两个坦克
        -- P1 发送 player_num=1，接收方更新本地的 tanks[1]（P1坦克）
        -- P2 发送 player_num=2，接收方更新本地的 tanks[2]（P2坦克）
        local targetPlayerNum = data.player_num
        log.info('tank_battle', string.format('收到move: from=%s, player_num=%s, target=%s, dir=%s',
            data.from_device, tostring(data.player_num), tostring(targetPlayerNum), data.direction))

        if targetPlayerNum then
            local tank = tanks[targetPlayerNum]
            if tank and tank.alive then
                log.info('tank_battle', string.format('执行move: tank%d at (%.1f,%.1f) -> %s', targetPlayerNum, tank.x, tank.y, data.direction))
                tank:moveOneStep(data.direction, CELL)
            else
                log.warn('tank_battle', 'move: tank ' .. tostring(targetPlayerNum) .. ' not found or dead')
            end
        else
            log.warn('tank_battle', 'move: targetPlayerNum is nil, data.player_num=' .. tostring(data.player_num))
        end
    elseif data.type == 'sync_pos' then
        -- 联机模式：收到对方的绝对位置校正
        if not networkMode then return end
        if data.from_device == my_device_id then return end
        local targetPlayerNum = data.player_num
        if not targetPlayerNum then return end
        local tank = tanks[targetPlayerNum]
        if not tank or not tank.alive then return end
        -- 使用格子坐标转换为本地像素坐标，确保横竖屏同步一致
        if data.grid_x and data.grid_y then
            tank.x = data.grid_x * CELL
            tank.y = data.grid_y * CELL
        elseif data.x and data.y then
            -- 兼容旧版本：直接接收像素坐标（不推荐）
            tank.x = data.x
            tank.y = data.y
        end
        -- log.info('tank_battle', string.format('sync_pos: tank%d 校正到 (%.1f, %.1f)', targetPlayerNum, tank.x, tank.y))
        -- 同步方向
        local dirMap = { up = {x=0,y=-1}, down = {x=0,y=1}, left = {x=-1,y=0}, right = {x=1,y=0} }
        if data.direction and dirMap[data.direction] then
            tank.dir = dirMap[data.direction]
        end
    elseif data.type == 'shoot' then
        -- 联机点按模式：收到对方的"开火"指令
        if not networkMode then return end
        if data.from_device == my_device_id then return end

        -- 双方设备上都有 P1 和 P2 两个坦克，直接用 player_num 定位
        local targetPlayerNum = data.player_num
        log.info('tank_battle', string.format('收到shoot: from=%s, player_num=%s, target=%s',
            data.from_device, tostring(data.player_num), tostring(targetPlayerNum)))

        if targetPlayerNum then
            local tank = tanks[targetPlayerNum]
            if tank and tank.alive then
                -- 检查冷却时间：防止网络延迟导致的重复射击
                if getTimestamp() >= tank.shootCooldownUntil then
                    tank:shoot()
                    -- 重置对应玩家的输入状态，防止连续射击
                    if targetPlayerNum == 1 then
                        input_p1.shoot = false
                    else
                        input_p2.shoot = false
                    end
                else
                    log.info('tank_battle', string.format('收到shoot: tank%d 冷却中，忽略', targetPlayerNum))
                end
            else
                log.warn('tank_battle', 'shoot: tank ' .. tostring(targetPlayerNum) .. ' not found or dead')
            end
        else
            log.warn('tank_battle', 'shoot: targetPlayerNum is nil')
        end
    elseif data.type == 'leave' or data.type == 'opponent_left' then
        -- 对手退出游戏
        log.info('tank_battle', '对手退出游戏:', data.from_device or data.device_id)
        game_state.peer_connected = false
        if gameState == STATE.PLAYING or gameState == STATE.GAME_OVER then
            showToast("对方已退出游戏")
            sys.timerStart(function()
                showMainMenu()
            end, 1500)
        end
    elseif data.type == 'invite' then
    elseif data.type == 'accept_invite' then
    elseif data.type == 'game_start' then
    end
end

-- ==================== 快速匹配 ====================

local matchingContainer = nil
local matchingTimer = nil

showMatchingUI = function()
    -- 隐藏主菜单
    if ui.menu_container then
        ui.menu_container:hide()
    end
    
    -- 显示匹配中界面
    matchingContainer = airui.container({
        parent = main_container,
        x = 0, y = 0, w = W, h = H,
        color = 0x0d1117
    })
    
    -- 标题
    airui.label({
        parent = matchingContainer,
        x = 0, y = 140, w = W, h = 50,
        text = "正在寻找对手...",
        color = 0xf0c040,
        font_size = 28,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 提示文字
    airui.label({
        parent = matchingContainer,
        x = 0, y = 200, w = W, h = 24,
        text = "系统正在为您匹配实力相当的玩家",
        color = 0x888888,
        font_size = 22,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 倒计时文字
    matchingCountdownValue = 30
    matchingCountdownLabel = airui.label({
        parent = matchingContainer,
        x = 0, y = 240, w = W, h = 30,
        text = "匹配超时: 30 秒",
        color = 0xaaaaaa,
        font_size = 22,
        align = airui.TEXT_ALIGN_CENTER
    })
    -- 倒计时更新
    if matchingTimer then
        sys.timerStop(matchingTimer)
    end
    matchingTimer = sys.timerLoopStart(function()
        matchingCountdownValue = matchingCountdownValue - 1
        if matchingCountdownLabel then
            matchingCountdownLabel:set_text("匹配超时: " .. matchingCountdownValue .. " 秒")
        end
    end, 1000)
    
    -- 取消按钮（居中显示）
    airui.button({
        parent = matchingContainer,
        x = (W - 200) / 2, y = 320, w = 200, h = 50,
        text = "取消匹配",
        font_size = 26,
        style = { bg_color = 0x884444, text_color = 0xFFFFFF, radius = 10 },
        on_click = function()
            -- 如果已匹配到对手，发送退出通知
            if game_state.peer_connected and game_state.peer_device_id then
                sendOpponentLeft()
            end
            expvp.stop_match()
            hideMatchingUI()
            showMainMenu()
        end
    })
end

hideMatchingUI = function()
    if matchingContainer then
        matchingContainer:destroy()
        matchingContainer = nil
    end
    if matchingTimer then
        sys.timerStop(matchingTimer)
        matchingTimer = nil
    end
end

startQuickMatch = function()
    log.info('tank_battle', '开始快速匹配')
    
    networkMode = true
    gameState = STATE.WAITING
    
    showMatchingUI()
    
    -- 开始匹配
    expvp.start_match(function(success, result)
        if not success then
            hideMatchingUI()
            if result == "timeout" then
                showToast("匹配超时，暂无在线玩家")
            elseif result == "already matching" then
                showToast("正在匹配中...")
            end
            showMainMenu()
        end
        -- 匹配成功通过 on_match_found 回调处理
    end)
end

local function onMatchFound(peer_id, peer_info)
    local nickname = peer_info.nickname or peer_id:sub(-6)
    log.info('tank_battle', '匹配成功！对手:', nickname)
    
    hideMatchingUI()
    
    -- 设置对手信息
    game_state.peer_device_id = peer_id
    game_state.peer_device_model = peer_info.model or "未知"
    game_state.peer_connected = true
    
    -- 设置游戏状态
    expvp.set_game_playing(true, peer_id)
    
    -- 确定玩家编号（设备ID小的为玩家1）
    -- 注意：device_id 可能是字符串（如MAC地址），需要安全比较
    local my_id_num = tonumber(my_device_id)
    local peer_id_num = tonumber(peer_id)
    local imSmaller = false
    if my_id_num and peer_id_num then
        -- 双方都是数字，按数字比较
        imSmaller = (my_id_num < peer_id_num)
    else
        -- 有一方不是数字，按字符串比较（结果互补，保证一方P1一方P2）
        imSmaller = (my_device_id < peer_id)
    end
    networkPlayerNumber = imSmaller and 1 or 2
    my_player_number = networkPlayerNumber  -- 匹配模式同步设置 my_player_number
    game_state.is_server = (networkPlayerNumber == 1)
    log.info('tank_battle', string.format('匹配结果: my_device_id=%s, peer_id=%s, my_player_number=%s',
        tostring(my_device_id), tostring(peer_id), tostring(my_player_number)))
    
    -- 显示对手信息弹窗（2秒后自动开始）
    local match_dialog = airui.container({
        parent = main_container,
        x = W/2 - 200, y = H/2 - 80, w = 400, h = 160,
        color = 0x1a1a2e, radius = 16,
    })
    airui.label({
        parent = match_dialog,
        x = 0, y = 25, w = 400, h = 30,
        text = "匹配成功！",
        font_size = 22,
        color = 0xf0c040,
        align = airui.TEXT_ALIGN_CENTER,
    })
    airui.label({
        parent = match_dialog,
        x = 0, y = 60, w = 400, h = 30,
        text = "您的对手是：",
        font_size = 16,
        color = 0xaaaaaa,
        align = airui.TEXT_ALIGN_CENTER,
    })
    airui.label({
        parent = match_dialog,
        x = 0, y = 85, w = 400, h = 30,
        text = nickname,
        font_size = 20,
        color = 0xf0c040,
        align = airui.TEXT_ALIGN_CENTER,
    })
    -- 2秒后自动进入游戏
    sys.timerStart(function()
        if match_dialog then
            match_dialog:destroy()
            match_dialog = nil
        end
        showGameUI()
        startGame()
        if ui.mode_indicator then
            ui.mode_indicator:set_text("联网对战 - " .. nickname)
        end
    end, 2000)
end

-- ==================== 发送在线广播 ====================

local function sendPresence()
    expvp.send_presence({
        type = "presence",
        device_id = my_device_id,
        device_model = get_device_model(),
        nickname = get_nickname(),
        timestamp = getTimestamp()
    })
end

-- ==================== 键盘事件处理 ====================

local function onKeyEvent(key, state)
    keyStates[key] = state

    -- R键返回主菜单
    if key == 'r' and state then
        if gameState == STATE.GAME_OVER then
            -- 隐藏KO弹窗
            if ui.ko_overlay and ui.ko_overlay.set_hidden then
                ui.ko_overlay:set_hidden(true)
            end
            -- 返回主菜单
            showMainMenu()
            return
        end
    end

    if networkMode then
        -- 联机模式：实体按键触发移动/开火消息
        -- 只有按下时触发（state=true），松开时不处理
        if state then
            -- 方向键：发送移动消息
            if key == 'up' or key == 'down' or key == 'left' or key == 'right' then
                local direction = key  -- 'up', 'down', 'left', 'right'
                sendMoveMessage(direction)
                -- 本地立即执行移动（与屏幕按钮的 on_click 相同）
                local myTank = tanks[my_player_number]
                if myTank and myTank.alive then
                    myTank:moveOneStep(direction, CELL)
                end
            -- 开火键（GPIO action="shoot"）
            elseif key == 'shoot' then
                -- 设置 btn_input.shoot，由 processButtonInput 处理
                btn_input.shoot = true
                sendShootMessage()
            end
        end
    end
    -- 单机模式：不需要在这里处理，processButtonInput 会自动合并 keyStates 和 btn_input
end

-- ==================== 窗口生命周期 ====================

local function win_on_create()
    log.info('tank_battle', 'win_on_create called')
    
    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = W,
        h = H,
        color = 0x0d1117
    })
    
    expvp.init({
        game_name = "tank_battle",
        score_cls = 1,
        room_max_players = 2,
        callbacks = {
            on_message = onNetworkMessage,
            on_match_found = onMatchFound,
            on_peer_join = function(peer_id, peer_info)
                log.info('tank_battle', '玩家加入房间:', peer_info and peer_info.nickname or peer_id)
                updateRoomUI()
            end,
            on_peer_leave = function(peer_id)
                log.info('tank_battle', '玩家离开房间:', peer_id)
                -- 游戏进行中或房间等待中，提示对方已退出
                if gameState == STATE.PLAYING or gameState == STATE.GAME_OVER then
                    showToast("对方已退出游戏")
                    sys.timerStart(function()
                        showMainMenu()
                    end, 1500)
                elseif gameState == STATE.ROOM_WAITING then
                    showToast("对方已离开房间")
                    updateRoomUI()
                else
                    updateRoomUI()
                end
            end,
            on_peer_ready = function(peer_id, ready)
                log.info('tank_battle', '玩家准备状态:', peer_id, ready)
                updateRoomUI()
            end,
            on_game_started = function(data)
                log.info('tank_battle', '收到游戏开始通知')
                -- 解析玩家编号分配
                local assignments = data.player_assignments or {}
                my_player_number = assignments[my_device_id] or 1
                networkMode = true
                is_host_player = expvp.is_host()
                -- 设置对手信息（用于兼容旧版点对点通信）
                for device_id, pnum in pairs(assignments) do
                    if device_id ~= my_device_id then
                        game_state.peer_device_id = device_id
                        break
                    end
                end
                expvp.set_game_playing(true, game_state.peer_device_id)
                
                -- 关闭房间等待UI，开始游戏
                hideRoomWaitingUI()
                showGameUI()
                startGame()
                
                -- 更新模式指示器
                if ui.mode_indicator then
                    ui.mode_indicator:set_text("联网对战 (2人房间)")
                end
            end,
            on_join_rejected = function(reason)
                showToast("加入被拒绝: " .. (reason or "未知原因"))
                showMainMenu()
            end,
            on_disconnect = function()
                if networkMode and (gameState == STATE.PLAYING or gameState == STATE.GAME_OVER) then
                    showToast("对方已退出游戏")
                    networkMode = false
                    is_host_player = false
                    game_state.peer_connected = false
                    hideRoomWaitingUI()
                    sys.timerStart(function()
                        showMainMenu()
                    end, 1500)
                elseif networkMode and gameState == STATE.ROOM_WAITING then
                    showToast("网络连接断开")
                    networkMode = false
                    is_host_player = false
                    game_state.peer_connected = false
                    hideRoomWaitingUI()
                    showMainMenu()
                elseif networkMode and gameState == STATE.WAITING then
                    -- 匹配中对方断开
                    showToast("对方已取消匹配")
                    networkMode = false
                    game_state.peer_connected = false
                    game_state.peer_device_id = nil
                    hideMatchingUI()
                    showMainMenu()
                end
            end
        }
    })
    
    -- 在expvp.init之后获取设备信息（init内部会初始化state）
    my_device_id = get_device_id()
    my_device_model = get_device_model()
    
    expvp.start()

    sys.timerStart(sendPresence, 5000)

    -- 使用 sys.taskInit + sys.wait 方式运行游戏循环，避免阻塞 I2C 触摸驱动
    -- 相比 timerLoopStart，这种方式会在 wait 时让出 CPU 时间片
    sys.taskInit(function()
        while true do
            gameLoop()
            sys.wait(100)  -- 100ms 间隔，约10FPS
        end
    end)

    buildUI()

    -- 初始化实体按键
    setup_gpio_keys()

    log.info('tank_battle', 'window created successfully')
end

-- ==================== 实体按键处理 ====================

-- 判断是否使用实体按键（Air1602使用，Air8000W不使用）
local function should_use_gpio_keys()
    local model = get_device_model()
    log.info("tank_battle", "检测设备型号: " .. model)
    if model and model:find("Air1602") then
        log.info("tank_battle", "检测到Air1602设备，启用实体按键")
        return true
    end
    log.info("tank_battle", "非Air1602设备，不使用实体按键")
    return false
end

--- 注册所有实体按键 GPIO 中断（带消抖）
function setup_gpio_keys()
    if gpio_keys_setup then return end
    
    -- 根据设备型号判断是否使用实体按键
    if not should_use_gpio_keys() then
        log.info("tank_battle", "当前设备不使用实体按键: " .. tostring(get_device_model()))
        return
    end

    for _, item in ipairs(GPIO_KEY_MAP) do
        local action = item.action
        local pin = item.pin
        gpio.debounce(pin, DEBOUNCE_MS, 1)
        gpio.setup(pin, function(val)
            if val == 0 then
                -- 按键按下
                if action == "up" then
                    btn_input.up = true
                    -- 联网模式：发送移动消息并本地执行
                    if networkMode then
                        sendMoveMessage('up')
                        local myTank = tanks[my_player_number]
                        if myTank and myTank.alive then
                            myTank:moveOneStep('up', CELL)
                        end
                    end
                elseif action == "down" then
                    btn_input.down = true
                    if networkMode then
                        sendMoveMessage('down')
                        local myTank = tanks[my_player_number]
                        if myTank and myTank.alive then
                            myTank:moveOneStep('down', CELL)
                        end
                    end
                elseif action == "left" then
                    btn_input.left = true
                    if networkMode then
                        sendMoveMessage('left')
                        local myTank = tanks[my_player_number]
                        if myTank and myTank.alive then
                            myTank:moveOneStep('left', CELL)
                        end
                    end
                elseif action == "right" then
                    btn_input.right = true
                    if networkMode then
                        sendMoveMessage('right')
                        local myTank = tanks[my_player_number]
                        if myTank and myTank.alive then
                            myTank:moveOneStep('right', CELL)
                        end
                    end
                elseif action == "shoot" then
                    btn_input.shoot = true
                    if networkMode then
                        sendShootMessage()
                    end
                end
                log.info("tank_battle", "[GPIO] 按键按下: " .. action)
            else
                -- 按键释放
                if action == "up" then
                    btn_input.up = false
                elseif action == "down" then
                    btn_input.down = false
                elseif action == "left" then
                    btn_input.left = false
                elseif action == "right" then
                    btn_input.right = false
                elseif action == "shoot" then
                    btn_input.shoot = false
                end
                log.info("tank_battle", "[GPIO] 按键释放: " .. action)
            end
        end, gpio.PULLUP, gpio.BOTH)
    end
    gpio_keys_setup = true
    log.info("tank_battle", "GPIO keys setup completed")
end

--- 释放所有实体按键 GPIO 中断
local function teardown_gpio_keys()
    if not gpio_keys_setup then return end
    for _, item in ipairs(GPIO_KEY_MAP) do
        gpio.debounce(item.pin, 0)
        gpio.close(item.pin)
    end
    gpio_keys_setup = false
    log.info("tank_battle", "GPIO keys teardown completed")
end

local function win_on_destroy()
    log.info('tank_battle', 'win_on_destroy called')
    -- 释放实体按键
    teardown_gpio_keys()
    -- 停止游戏循环任务（使用 taskInit 方式，不需要 timerStop）
    -- 通过设置 gameState 为非 PLAYING 状态来停止游戏循环
    gameState = STATE.MENU
    game_timer_id = nil  -- 保留变量兼容性
    -- 停止位置同步定时器
    if pos_sync_timer then
        sys.timerStop(pos_sync_timer)
        pos_sync_timer = nil
    end
    -- 如果在房间中，先离开房间
    if current_room_id then
        expvp.leave_room()
        current_room_id = nil
    end
    expvp.stop()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    win_id = nil
end

-- ==================== 订阅窗口消息 ====================

local function open_handler()
    if win_id then return end
    win_id = exwin.open({
        on_create = win_on_create,
        on_destroy = win_on_destroy,
    })
end

sys.subscribe("OPEN_TANK_BATTLE_WIN", open_handler)

sys.subscribe("CLOSE_TANK_BATTLE_WIN", function()
    if win_id then
        exwin.close(win_id)
        win_id = nil
        main_container = nil
    end
end)

-- ==================== 键盘事件订阅 ====================

sys.subscribe("KEY_EVENT", function(key, state)
    onKeyEvent(key, state == 1)
end)

-- ==================== 排行榜功能 ====================

-- 前向声明
local loadLeaderboardData

-- 关闭排行榜窗口
local function closeLeaderboardWin()
    if leaderboardWinId then
        exwin.close(leaderboardWinId)
        leaderboardWinId = nil
        leaderboardMainContainer = nil
        leaderboardItems = {}
    end
end

-- 重建排行榜UI（卡片式列表，参考火柴人）
local function rebuildLeaderboardUI()
    if not leaderboardMainContainer then return end

    -- 清空旧项目
    for _, item in ipairs(leaderboardItems) do
        if item then item:destroy() end
    end
    leaderboardItems = {}

    -- 竖屏适配：列表宽度适配480px屏幕
    local cardW = 440
    local cardX = (W - cardW) / 2  -- 居中
    local cardH = 46  -- 减小高度避免与分页控件重叠
    local gap = 6     -- 减小间隙
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
        parent = header, x = 360, y = 6, w = 70, h = 18,
        text = "积分", font_size = 22, color = 0x007AFF,
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

    -- 前三名背景色和文字色
    local medalBgColors = {
        [1] = 0xFFD700,  -- 金黄色
        [2] = 0xC0C0C0,  -- 银色
        [3] = 0xCD7F32   -- 铜黄色
    }

    for i = startIdx, endIdx do
        local record = leaderboardData[i]
        local nickname = (record.s1 and #record.s1 > 0) and record.s1 or "匿名"
        local score = record.i1 or 0
        local displayName = #nickname > 16 and nickname:sub(1, 16) .. ".." or nickname

        local isTop3 = (i <= 3)
        local bgColor = isTop3 and medalBgColors[i] or 0xF5F5F5  -- 前三名奖牌色，其余灰色背景
        local textColor = 0x333333  -- 所有名次都用黑色字体

        -- 卡片容器（前三名带背景色）
        local card = airui.container({
            parent = leaderboardMainContainer,
            x = cardX, y = yPos, w = cardW, h = cardH,
            color = bgColor,
            radius = 6
        })
        table.insert(leaderboardItems, card)

        -- 排名（左对齐）
        local rankLabel = airui.label({
            parent = card, x = 15, y = 7, w = 50, h = 20,
            text = tostring(i), font_size = 16,
            color = textColor
        })
        table.insert(leaderboardItems, rankLabel)

        -- 昵称
        local nameLabel = airui.label({
            parent = card, x = 80, y = 7, w = 260, h = 20,
            text = displayName, font_size = 16,
            color = textColor
        })
        table.insert(leaderboardItems, nameLabel)

        -- 积分（右对齐，紧贴右边）
        local scoreLabel = airui.label({
            parent = card, x = 360, y = 7, w = 70, h = 20,
            text = tostring(score), font_size = 16,
            color = textColor,
            align = airui.TEXT_ALIGN_RIGHT
        })
        table.insert(leaderboardItems, scoreLabel)

        yPos = yPos + cardH + gap
    end

    -- 如果当前页包含第30名，显示提示（最多显示30名）
    if endIdx == 30 then
        yPos = yPos + 5
        local tipLabel = airui.label({
            parent = leaderboardMainContainer,
            x = cardX, y = yPos, w = cardW, h = 22,
            text = "仅显示前30名积分数据",
            font_size = 22,
            color = 0x888888,
            align = airui.TEXT_ALIGN_CENTER
        })
        table.insert(leaderboardItems, tipLabel)
    end

    -- 分页控件区域（11条数据占满后，位置在列表下方）
    -- 计算：80(起始) + 28(表头) + 11*(42+4) = 80 + 28 + 506 = 614
    local pageControlY = 690

    -- 上一页按钮
    local prevBtn = airui.button({
        parent = leaderboardMainContainer,
        x = 50, y = pageControlY, w = 100, h = 44,
        text = "上一页",
        font_size = 18,
        text_color = 0xFFFFFF,
        bg_color = leaderboardPage > 1 and 0x228844 or 0x888888,
        radius = 6,
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
        text_color = 0xFFFFFF,
        bg_color = leaderboardPage < leaderboardTotalPages and 0x228844 or 0x888888,
        radius = 6,
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
        -- 计算总数：最多显示30名
        local total = math.min(tonumber(data.total) or #data.records, 30)
        leaderboardTotalPages = math.max(1, math.ceil(total / 11))
        rebuildLeaderboardUI()
    end
end

-- 加载排行榜数据
function loadLeaderboardData()
    if leaderboardLoadingLabel then
        leaderboardLoadingLabel:set_text("加载中...")
    end
    
    -- 使用 exapp.list_record 直接查询（支持分页，每页11条）
    if exapp then
        local pageSize = 11
        local offset = (leaderboardPage - 1) * pageSize
        exapp.list_record({cls = 1, sort = "i1 desc", size = pageSize, offset = offset}, onLeaderboardQueryCallback)
    else
        -- 降级使用 expvp 模块
        expvp.query_leaderboard(leaderboardPage, function(success, data)
            if not success or not data then
                if leaderboardLoadingLabel then
                    leaderboardLoadingLabel:set_text("加载失败")
                end
                return
            end
            onLeaderboardQueryCallback(success, data)
        end, 11)
    end
end

-- 打开排行榜窗口
function openLeaderboardWin()
    if leaderboardWinId then return end
    
    leaderboardData = {}
    leaderboardPage = 1
    leaderboardTotalPages = 1
    
    leaderboardWinId = exwin.open({
        on_create = function()
            leaderboardMainContainer = airui.container({
                parent = airui.screen,
                x = 0, y = 0, w = W, h = H,
                color = 0xFFFFFF  -- 白色背景，占满全屏
            })
            
            -- 标题左侧奖杯图标
            airui.image({
                parent = leaderboardMainContainer,
                src = "/luadb/ranking_list.png",
                x = W / 2 - 120,
                y = 20,
                w = 36,
                h = 36
            })
            
            -- 标题文字
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
            
            -- 底部按钮行：刷新 | 删除我的积分 | 返回（竖屏适配，紧贴底部，增加间隙）
            local btn_y = H - 60
            local btn_gap = 20  -- 按钮之间的间隙
            -- 刷新按钮（左）
            airui.button({
                parent = leaderboardMainContainer,
                x = W / 2 - 200, y = btn_y, w = 110, h = 44,
                text = "刷新",
                font_size = 18,
                text_color = 0xFFFFFF,
                bg_color = 0x228844,
                radius = 8,
                on_click = function()
                    leaderboardPage = 1
                    loadLeaderboardData()
                end
            })
            
            -- 删除我的积分按钮（中）
            airui.button({
                parent = leaderboardMainContainer,
                x = W / 2 - 60, y = btn_y, w = 140, h = 44,
                text = "删除我的积分",
                font_size = 16,
                text_color = 0xFFFFFF,
                bg_color = 0x888888,
                radius = 8,
                on_click = function()
                    -- 弹出确认弹窗，防止误触
                    local confirmContainer
                    confirmContainer = airui.container({
                        parent = leaderboardMainContainer,
                        x = W / 2 - 180, y = 250, w = 360, h = 160,
                        color = 0xFFFFFF,
                        radius = 12,
                        shadow = true
                    })
                    airui.label({
                        parent = confirmContainer, x = 0, y = 25, w = 360, h = 32,
                        text = "确认删除我的积分？",
                        font_size = 22, color = 0xCC0000,
                        align = airui.TEXT_ALIGN_CENTER
                    })
                    airui.label({
                        parent = confirmContainer, x = 0, y = 55, w = 360, h = 24,
                        text = "删除后无法恢复",
                        font_size = 16, color = 0x888888,
                        align = airui.TEXT_ALIGN_CENTER
                    })
                    -- 取消按钮（左）
                    airui.button({
                        parent = confirmContainer,
                        x = 70, y = 100, w = 100, h = 44,
                        text = "取消",
                        font_size = 18, text_color = 0xFFFFFF, bg_color = 0x666666, radius = 6,
                        on_click = function()
                            confirmContainer:destroy()
                        end
                    })
                    -- 确认按钮（右）
                    airui.button({
                        parent = confirmContainer,
                        x = 190, y = 100, w = 100, h = 44,
                        text = "确认删除",
                        font_size = 18, text_color = 0xFFFFFF, bg_color = 0xCC0000, radius = 6,
                        on_click = function()
                            confirmContainer:destroy()
                            local ok, info = pcall(exapp.iot_get_account_info)
                            if ok and info and not info.is_guest then
                                local account = info.account or ""
                                local deleted = 0
                                for _, record in ipairs(leaderboardData) do
                                    local match = false
                                    if record.uni_key then
                                        match = (record.uni_key == account) or (record.uni_key:find(account, 1, true) == 1)
                                    end
                                    if match and record.id then
                                        exapp.delete_record({cls = 1, id = record.id})
                                        deleted = deleted + 1
                                    end
                                end
                                -- 删除后刷新排行榜
                                sys.timerStart(function()
                                    loadLeaderboardData()
                                end, 300)
                            end
                        end
                    })
                end
            })
            
            -- 返回按钮（右）
            airui.button({
                parent = leaderboardMainContainer,
                x = W / 2 + 90, y = btn_y, w = 110, h = 44,
                text = "返回",
                font_size = 18,
                text_color = 0xFFFFFF,
                bg_color = 0xCC0000,
                radius = 8,
                on_click = closeLeaderboardWin
            })
        end,
        on_destroy = function()
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

-- ==================== 模块导出 ====================

return {
    open = open_handler,
    close = win_on_destroy
}
