
--[[
@module  stick_fighter_online_win
@summary 联机火柴人格斗游戏横屏版窗口模块
@version 1.0.1
@date    2026.05.18
@author  王世豪
]]

-- 游戏版本号（与@version保持一致）
local GAME_VERSION = "1.0.1"

local win_id = nil
local main_container = nil
local device_list_win_id = nil

local STATE = {
    MENU = 'menu',
    DEVICE_LIST = 'device_list',
    WAITING = 'waiting',
    CONNECTING = 'connecting',
    COUNTDOWN = 'countdown',
    FIGHTING = 'fighting',
    KO = 'ko'
}

-- 800x480 横屏分辨率
local W, H = 800, 480
local GROUND_Y = 340

local gameState = STATE.MENU
local countdownTimer = 0
local countdownValue = 3
local koTimer = 0
local koWinner = nil
local shakeAmount = 0
local shakeDecay = 0.85
-- 获取毫秒级时间戳
local function getTimestamp()
    if mcu and mcu.ticks2 then
        local ms_h, ms_l = mcu.ticks2(1)
        return ms_h * 1000000 + ms_l
    end
    return 0
end

local isConnecting = false -- 标记是否是因为连接而关闭窗口
local is_resetting = false
local inviteDialogContainer = nil  -- 邀请弹窗容器
local inviteRequestDeviceId = nil  -- 邀请者的设备ID
local inviteWaitingContainer = nil  -- 等待对方回复的容器
local inviteTargetDeviceId = nil    -- 邀请的目标设备ID
local lastSentPosX = 0 -- 上一次发送的位置x，用于去重

-- 积分系统
local myScore = 0
local SCORE_CLS = 2
local scoreLabel = nil
local peerModelLabel = nil
local pendingUpload = nil  -- 待上传的积分 {account, nickname, score}
local justDeletedMyScore = false  -- 删除积分后的标记，下次上传强制覆盖（不走累加）

-- 先定义获取设备ID的函数和设备ID变量
local my_device_id = nil

local function get_device_id()
    local device_id = "DEV_UNKNOWN"
    if mobile and mobile.imei then
        device_id = mobile.imei()
    elseif wlan and wlan.getMac then
        device_id = wlan.getMac()
    else
        device_id = "DEV_" .. tostring(os.time())
    end
    return device_id
end

-- 初始化设备ID
my_device_id = get_device_id()
log.info('device_id', my_device_id)

-- 获取显示昵称（优先用IOT昵称，没有就用设备ID后6位）
local function get_nickname()
    if exapp then
        local ok, info = pcall(exapp.iot_get_account_info)
        if ok and info and info.nickname and #info.nickname > 0 then
            return info.nickname
        end
    end
    -- 确保 my_device_id 不为 nil
    if not my_device_id or #my_device_id == 0 then
        my_device_id = "DEV_" .. tostring(os.time())
    end
    return my_device_id:sub(#my_device_id - 5)
end

-- 排行榜
local leaderboardWinId = nil
local leaderboardMainContainer = nil
local leaderboardItems = {}
local leaderboardPage = 1
local leaderboardTotalPages = 1
local leaderboardData = {}
local leaderboardLoadingLabel = nil
local close_leaderboard_win 
local close_device_list_win 
local check_both_ready 
local send_start_game 

-- IOT 登录状态
local loginMenuStatus = nil
local update_login_menu_status 

local MQTT_SERVER = "lbsmqtt.airm2m.com"
local MQTT_PORT = 1884
local MQTT_QOS = 0
local TASK_NAME = "stick_fighter_mqtt"

-- 获取本机设备型号
local my_device_model = "未知"
if hmeta and hmeta.model then
    local model = hmeta.model()
    if model then
        my_device_model = model
    end
end
log.info('device_model', my_device_model)

local TOPIC_PRESENCE = "stick_fighter/presence"
local TOPIC_DATA = "stick_fighter/data/"

local game_state_mqtt = {
    online_devices = {},
    peer_connected = false,
    peer_ready = false,
    i_am_ready = false,
    peer_device_id = nil,
    peer_device_model = nil,  -- 对方的设备型号
    mqtt_client = nil,
    mqtt_ready = false,
    is_running = false,
    is_server = false
}

local player1 = nil
local player2 = nil

-- UI 缓存变量，避免每帧重复更新
local ui_cache = {
    hp1_value = -1,
    hp2_value = -1,
    hp1_text = '',
    hp2_text = '',
    score_text = '',
    peer_text = '',
    score_color = nil
}

-- 发送用户输入消息
local function send_input_message(input_type, duration, customX, customY)
    -- 调试日志：检查连接状态
    if not game_state_mqtt then
        log.info('send_input', 'ERROR: game_state_mqtt is nil')
        return
    end
    if not game_state_mqtt.peer_connected then
        log.info('send_input', 'ERROR: peer_connected is false')
        return
    end
    if not game_state_mqtt.mqtt_client then
        log.info('send_input', 'ERROR: mqtt_client is nil')
        return
    end
    
    -- 关键修复：如果正在跳跃中，不发送第二次跳跃消息（避免两段跳）
    if input_type == 'jump' and player1.isJumping then
        log.info('send_input', '跳过发送', '正在跳跃中，不重复发送')
        return
    end
    
    log.info('send_input', '准备发送', '动作:', input_type)
    
    local currentX = customX or player1.x
    local currentY = customY or player1.y
    
    -- 如果是校准消息，且位置变化 < 3 像素，就不发送（减少消息量）
    if (input_type == 'left_pos' or input_type == 'right_pos' or input_type == 'left_end' or input_type == 'right_end') then
        local delta = math.abs(currentX - lastSentPosX)
        if delta < 3 then
            log.info('send_input', '位置变化太小，跳过发送', input_type, '变化:', string.format("%.1fpx", delta))
            return
        end
    end
    
    -- 记录这次发送的位置
    lastSentPosX = currentX
    
    local data = {
        type = "input",
        input = input_type,
        duration = duration,
        x = currentX,  -- 发送时的实时位置（用于校准）
        y = currentY,
        state = player1.state,
        from_device = my_device_id
    }
    
    local ok, json_str = pcall(json.encode, data)
    if ok then
        local topic = TOPIC_DATA .. game_state_mqtt.peer_device_id
        game_state_mqtt.mqtt_client:publish(topic, json_str, MQTT_QOS)
        log.info('send_input', 
            player1.name, 
            '动作:', input_type, 
            '位置:', string.format("%.1f", data.x))
    end
end

local particles = {}
local damageLabels = {}
local hp1Bar = nil
local hp2Bar = nil
local hp1Text = nil
local hp2Text = nil
local hp1Label = nil
local hp2Label = nil
local vsText = nil
local countdownLabel = nil
local koLabel = nil
local winnerLabel = nil
local menuContainer = nil
local statusLabel = nil
local myIdLabel = nil

local countdownContainer = nil
local koContainer = nil
local winnerContainer = nil
local restartContainer = nil

local device_list_main_container = nil
local device_list_popup_items = {}
local device_list_page = 1              -- 当前页码
local DEVICE_PAGE_SIZE = 10             -- 每页显示设备数
local DEVICE_MAX_PAGES = 10             -- 最大页数

local function set_container_visible(container, visible)
    if container then
        if visible then
            container:open()
        else
            container:hide()
        end
    end
end

local function set_label_visible(label, visible)
    if label then
        if visible then
            label:open()
        else
            label:hide()
        end
    end
end

local StickFighter = {}
StickFighter.__index = StickFighter

function StickFighter.new(x, y, facingRight, color, name, colorHex, root)
    local self = setmetatable({}, StickFighter)
    self.x = x
    self.y = y
    self.facingRight = facingRight
    self.color = color
    self.colorHex = colorHex
    self.name = name
    self.root = root

    -- 所有尺寸使用固定值
    self.headRadius = 10
    self.neckLen = 4
    self.bodyLen = 26
    self.upperLegLen = 16
    self.lowerLegLen = 14
    self.upperArmLen = 14
    self.lowerArmLen = 12

    self.state = 'idle'
    self.stateTimer = 0
    self.stateDuration = 999
    self.animPhase = 0

    self.hp = 100
    self.maxHp = 100
    self.moveSpeed = 100
    self.attackCooldown = 0
    self.hitStun = 0
    self.invincible = 0

    self.punchDamage = 8
    self.punchRange = 28
    self.punchActiveStart = 0.25
    self.punchActiveEnd = 0.55
    self.punchDuration = 0.35
    self.punchCooldown = 0.45

    self.kickDamage = 12
    self.kickRange = 35
    self.kickActiveStart = 0.3
    self.kickActiveEnd = 0.6
    self.kickDuration = 0.48
    self.kickCooldown = 0.65

    self.blockReduceRatio = 0.75

    self.jumpVelocity = 0
    self.jumpGravity = 900
    self.jumpInitialVelocity = -350
    self.isJumping = false
    self.groundY = y

    self.inputLeft = false
    self.inputRight = false
    self.inputJump = false
    self.inputPunch = false
    self.inputKick = false
    self.inputBlock = false

    self.prevPunch = false
    self.prevKick = false
    self.prevJump = false

    self.currentAttackHit = false
    self.currentAttackId = 0

    self.flashTimer = 0
    self.bodyOffsetX = 0
    self.bodyOffsetY = 0
    
    -- 平滑过渡用的目标状态（仅用于远程玩家）
    self.targetX = nil
    self.targetY = nil
    self.targetState = nil
    self.targetStateTimer = nil

    self.bodyContainer = airui.container({
        parent = root,
        x = 0,
        y = 0,
        w = W,
        h = 380
    })
    self.bodyContainer:hide()

    -- 火柴人身体各个部分使用固定尺寸
    local headW, headH = self.headRadius * 2, self.headRadius * 2
    local headX, headY = x - self.headRadius, y - self.lowerLegLen - self.upperLegLen - self.bodyLen - self.neckLen - self.headRadius * 2
    self.head = airui.container({
        parent = self.bodyContainer,
        x = headX,
        y = headY,
        w = headW,
        h = headH,
        color = colorHex,
        radius = self.headRadius
    })

    local torsoW, torsoH = 8, self.bodyLen
    local torsoX, torsoY = x - 4, y - self.lowerLegLen - self.upperLegLen - self.bodyLen
    self.torso = airui.container({
        parent = self.bodyContainer,
        x = torsoX,
        y = torsoY,
        w = torsoW,
        h = torsoH,
        color = colorHex,
        radius = 2
    })

    local legW = 5
    local legX1, legY1 = x - 6, y - self.lowerLegLen - self.upperLegLen
    self.leftLeg = airui.container({
        parent = self.bodyContainer,
        x = legX1,
        y = legY1,
        w = legW,
        h = self.upperLegLen,
        color = colorHex,
        radius = 2
    })

    local legX2 = x + 1
    self.rightLeg = airui.container({
        parent = self.bodyContainer,
        x = legX2,
        y = legY1,
        w = legW,
        h = self.upperLegLen,
        color = colorHex,
        radius = 2
    })

    local armW = 5
    local armX1, armY1 = x - 12, y - self.lowerLegLen - self.upperLegLen - self.bodyLen + 5
    self.leftArm = airui.container({
        parent = self.bodyContainer,
        x = armX1,
        y = armY1,
        w = armW,
        h = self.upperArmLen,
        color = colorHex,
        radius = 2
    })

    local armX2 = x + 7
    self.rightArm = airui.container({
        parent = self.bodyContainer,
        x = armX2,
        y = armY1,
        w = armW,
        h = self.upperArmLen,
        color = colorHex,
        radius = 2
    })

    return self
end

function StickFighter:getHipY() return self.y - self.lowerLegLen - self.upperLegLen end
function StickFighter:getHeadCenterY() 
    return self.y - self.lowerLegLen - self.upperLegLen - self.bodyLen - self.neckLen - self.headRadius 
end
function StickFighter:getShoulderY() 
    return self.y - self.lowerLegLen - self.upperLegLen - self.bodyLen 
end

function StickFighter:getBodyRect()
    local hTop = self:getHeadCenterY() - self.headRadius + self.bodyOffsetY
    local hBot = self.y + self.bodyOffsetY
    local hWidth = 28
    return {
        left = self.x + self.bodyOffsetX - hWidth / 2,
        right = self.x + self.bodyOffsetX + hWidth / 2,
        top = hTop,
        bottom = hBot,
        width = hWidth,
        height = hBot - hTop
    }
end

function StickFighter:getAttackRect()
    if self.state == 'punch' and self:isAttackActive() then
        local shoulderY = self:getShoulderY() + self.bodyOffsetY
        local dir = self.facingRight and 1 or -1
        local startX = self.x + self.bodyOffsetX + dir * 15
        local endX = self.x + self.bodyOffsetX + dir * self.punchRange
        return {
            left = math.min(startX, endX) - 10,
            right = math.max(startX, endX) + 10,
            top = shoulderY - 25,
            bottom = shoulderY + 15,
            active = true,
            type = 'punch'
        }
    end
    if self.state == 'kick' and self:isAttackActive() then
        local hipY = self:getHipY() + self.bodyOffsetY
        local dir = self.facingRight and 1 or -1
        local startX = self.x + self.bodyOffsetX + dir * 15
        local endX = self.x + self.bodyOffsetX + dir * self.kickRange
        return {
            left = math.min(startX, endX) - 12,
            right = math.max(startX, endX) + 12,
            top = hipY - 25,
            bottom = hipY + 20,
            active = true,
            type = 'kick'
        }
    end
    return { left = 0, right = 0, top = 0, bottom = 0, active = false, type = nil }
end

function StickFighter:isAttackActive()
    if self.state == 'punch' then
        local prog = self.stateTimer / self.punchDuration
        return prog >= self.punchActiveStart and prog <= self.punchActiveEnd
    end
    if self.state == 'kick' then
        local prog = self.stateTimer / self.kickDuration
        return prog >= self.kickActiveStart and prog <= self.kickActiveEnd
    end
    return false
end

function StickFighter:isBlocking()
    return self.state == 'block' and self.hitStun <= 0
end

function StickFighter:canAct()
    return self.hitStun <= 0 and self.state ~= 'knockdown' and self.hp > 0
end

function StickFighter:update(dt)
    -- 所有远程玩家（无论服务器还是客户端的player2），都跳过本地输入判断
    -- 只做跳跃物理计算、动画和平滑插值，避免walk状态立即变回idle
    if self == player2 then
        -- 更新动画相关的计时器
        if self.attackCooldown > 0 then self.attackCooldown = self.attackCooldown - dt end
        if self.hitStun > 0 then self.hitStun = self.hitStun - dt end
        if self.invincible > 0 then self.invincible = self.invincible - dt end
        if self.flashTimer > 0 then self.flashTimer = self.flashTimer - dt end
        if self.stateTimer < self.stateDuration then
            self.stateTimer = self.stateTimer + dt
            if self.stateTimer >= self.stateDuration then
                self:onStateComplete()
            end
        end
        self.animPhase = self.animPhase + dt * 5
        
        -- bodyOffset 衰减（和本地玩家保持一致）
        if self.bodyOffsetX ~= 0 then self.bodyOffsetX = self.bodyOffsetX * 0.85 end
        if self.bodyOffsetY ~= 0 then self.bodyOffsetY = self.bodyOffsetY * 0.85 end
        if math.abs(self.bodyOffsetX) < 0.3 then self.bodyOffsetX = 0 end
        if math.abs(self.bodyOffsetY) < 0.3 then self.bodyOffsetY = 0 end
        
        -- 客户端player2也要进行跳跃物理计算！
        if self.isJumping then
            self.y = self.y + self.jumpVelocity * dt
            self.jumpVelocity = self.jumpVelocity + self.jumpGravity * dt
            
            if self.y >= self.groundY then
                self.y = self.groundY
                self.isJumping = false
                self.jumpVelocity = 0
                if self.state == 'jump' then
                    self:setState('idle')
                end
            end
        end
        
        -- 平滑插值
        if self.targetX ~= nil then
            local dx = self.targetX - self.x
            if math.abs(dx) > 0.5 then
                self.x = self.x + dx * 0.3
            else
                self.x = self.targetX
                self.targetX = nil
            end
        end
        if self.targetY ~= nil then
            local dy = self.targetY - self.y
            if math.abs(dy) > 0.5 then
                self.y = self.y + dy * 0.3
            else
                self.y = self.targetY
                self.targetY = nil
            end
        end
        
        local minX = 20
        local maxX = W - 20
        self.x = math.max(minX, math.min(maxX, self.x))
        return
    end

    -- if self.name == '自己' then
    --     log.info('StickFighter.update', 'name:', self.name, 'state:', self.state, 
    --              'inputPunch:', self.inputPunch, 'inputKick:', self.inputKick, 
    --              'attackCooldown:', self.attackCooldown, 'isJumping:', self.isJumping)
    -- end
    
    if self.attackCooldown > 0 then self.attackCooldown = self.attackCooldown - dt end
    if self.hitStun > 0 then self.hitStun = self.hitStun - dt end
    if self.invincible > 0 then self.invincible = self.invincible - dt end
    if self.flashTimer > 0 then self.flashTimer = self.flashTimer - dt end
    if self.bodyOffsetX ~= 0 then self.bodyOffsetX = self.bodyOffsetX * 0.85 end
    if self.bodyOffsetY ~= 0 then self.bodyOffsetY = self.bodyOffsetY * 0.85 end
    if math.abs(self.bodyOffsetX) < 0.3 then self.bodyOffsetX = 0 end
    if math.abs(self.bodyOffsetY) < 0.3 then self.bodyOffsetY = 0 end

    if self.isJumping then
        self.y = self.y + self.jumpVelocity * dt
        self.jumpVelocity = self.jumpVelocity + self.jumpGravity * dt
        if self.y >= self.groundY then
            self.y = self.groundY
            self.isJumping = false
            self.jumpVelocity = 0
            if self.state == 'jump' then
                self:setState('idle')
            end
        end
    end

    if self.state == 'hit' and self.hitStun <= 0 then
        self:setState('idle')
    end
    if self.state == 'knockdown' and self.stateTimer > 1.5 then
        self:setState('idle')
    end

    if self.stateTimer < self.stateDuration then
        self.stateTimer = self.stateTimer + dt
        if self.stateTimer >= self.stateDuration then
            self:onStateComplete()
        end
    end

    self.animPhase = self.animPhase + dt * 5

    if self:canAct() then
        if self.inputBlock and self.state ~= 'block' and self.state ~= 'punch' and self.state ~= 'kick' and not self.isJumping then
            log.info('StickFighter.update', self.name, 'entering block state')
            self:setState('block')
        end
        if not self.inputBlock and self.state == 'block' then
            self:setState('idle')
        end

        if self.state ~= 'punch' and self.state ~= 'kick' and self.state ~= 'hit' and self.state ~= 'knockdown' then
            -- 先保存旧值，再检查条件
            local oldPunch = self.prevPunch
            local oldKick = self.prevKick
            local oldJump = self.prevJump
            
            if self.inputPunch and not oldPunch and self.attackCooldown <= 0 and not self.isJumping then
                log.info('StickFighter.update', self.name, 'starting punch')
                self:startPunch()
                self.inputPunch = false  -- 触发后立即设置为 false，准备下一次点击
            end
            if self.inputKick and not oldKick and self.attackCooldown <= 0 and not self.isJumping then
                log.info('StickFighter.update', self.name, 'starting kick')
                self:startKick()
                self.inputKick = false  -- 触发后立即设置为 false，准备下一次点击
            end
            if self.inputJump and not oldJump and not self.isJumping and self.state ~= 'punch' and self.state ~= 'kick' then
                log.info('StickFighter.update', self.name, 'starting jump')
                self:startJump()
                self.inputJump = false  -- 触发后立即设置为 false，准备下一次点击
            end
        end

        if self.state == 'idle' or self.state == 'walk' or self.state == 'block' then
            local moveDir = 0
            if self.inputLeft then moveDir = -1 end
            if self.inputRight then moveDir = moveDir + 1 end
            moveDir = math.max(-1, math.min(1, moveDir))

            local speed = self.state == 'block' and self.moveSpeed * 0.5 or self.moveSpeed
            if moveDir ~= 0 then
                self.x = self.x + moveDir * speed * dt
                if self.state == 'idle' then self:setState('walk') end
            elseif self.state == 'walk' then
                self:setState('idle')
            end
        end
    end

    -- 平滑插值：如果有目标位置，慢慢移过去
    if self.targetX ~= nil then
        local dx = self.targetX - self.x
        if math.abs(dx) > 0.5 then
            -- 每帧移动 30% 的距离（可以调整）
            self.x = self.x + dx * 0.3
        else
            -- 距离很近了，直接对齐
            self.x = self.targetX
            self.targetX = nil
        end
    end
    if self.targetY ~= nil then
        local dy = self.targetY - self.y
        if math.abs(dy) > 0.5 then
            self.y = self.y + dy * 0.3
        else
            self.y = self.targetY
            self.targetY = nil
        end
    end

    -- 优化边界计算，让玩家更靠近屏幕边缘
    local minX = 20
    local maxX = W - 20
    self.x = math.max(minX, math.min(maxX, self.x))

    -- 关键修复！！！最后再更新 prev 值！！！
    self.prevPunch = self.inputPunch
    self.prevKick = self.inputKick
    self.prevJump = self.inputJump
end

function StickFighter:setState(newState)
    local oldState = self.state
    if self.state == newState then return end
    self.state = newState
    self.stateTimer = 0
    self.currentAttackHit = false
    -- 移除旧的状态消息发送，改用输入同步系统
    -- 动作消息已在按钮点击时通过 send_input_message 发送

    if newState == 'idle' then
        self.stateDuration = 999
    elseif newState == 'walk' then
        self.stateDuration = 999
    elseif newState == 'block' then
        self.stateDuration = 999
    elseif newState == 'punch' then
        self.stateDuration = self.punchDuration
        self.attackCooldown = self.punchCooldown
        self.currentAttackId = self.currentAttackId + 1
    elseif newState == 'kick' then
        self.stateDuration = self.kickDuration
        self.attackCooldown = self.kickCooldown
        self.currentAttackId = self.currentAttackId + 1
    elseif newState == 'hit' then
        self.stateDuration = 0.45
        self.hitStun = 0.45
    elseif newState == 'knockdown' then
        self.stateDuration = 2.0
        self.hitStun = 2.0
        self.isJumping = false
        self.y = self.groundY
    elseif newState == 'jump' then
        self.stateDuration = 999
    end
end

function StickFighter:onStateComplete()
    if self.state == 'punch' or self.state == 'kick' then
        self:setState('idle')
    end
    if self.state == 'hit' then
        if self.hp <= 0 then
            self:setState('knockdown')
        else
            self:setState('idle')
        end
    end
end

function StickFighter:startPunch()
    log.info('StickFighter.startPunch', 'name:', self.name)
    self:setState('punch')
end

function StickFighter:startKick()
    log.info('StickFighter.startKick', 'name:', self.name)
    self:setState('kick')
end

function StickFighter:startJump()
    log.info('StickFighter.startJump', 'name:', self.name)
    self.isJumping = true
    self.jumpVelocity = self.jumpInitialVelocity
    self:setState('jump')
end

local function sync_hp_to_client()
    if not game_state_mqtt.is_server then return end
    if not game_state_mqtt.peer_connected or not game_state_mqtt.mqtt_client then return end
    local data = {
        type = 'hp_sync',
        hp1 = player1.hp,
        hp2 = player2.hp,
    }
    local ok, json_str = pcall(json.encode, data)
    if ok then
        game_state_mqtt.mqtt_client:publish(TOPIC_DATA .. game_state_mqtt.peer_device_id, json_str, MQTT_QOS)
        log.info('sync_hp_to_client', 'hp1:', player1.hp, 'hp2:', player2.hp)
    end
end

function StickFighter:takeDamage(damage, attackerX)
    if self.invincible > 0 then return 0 end
    if self.hp <= 0 then return 0 end

    local actualDamage = damage
    local isDefending = self:isBlocking()

    if isDefending then
        -- 防御成功：减少75%伤害，只受25%伤害
        actualDamage = math.floor(damage * 0.25)
        self.flashTimer = 0.15
    else
        self.flashTimer = 0.2
    end

    self.hp = math.max(0, self.hp - actualDamage)
    self.invincible = 0.4

    -- 只有血量归零才进入击倒状态，去掉受击击退和僵直
    if self.hp <= 0 then
        self:setState('knockdown')
    end

    if game_state_mqtt.is_server then
        sync_hp_to_client()   -- 发送双方最新血量
    end

    return actualDamage
end

function StickFighter:draw(otherX)
    local ox = self.bodyOffsetX
    local oy = self.bodyOffsetY
    local x = self.x + ox
    local y = self.y + oy
    local dir = self.facingRight and 1 or -1

    if self.state == 'idle' or self.state == 'walk' or self.state == 'block' then
        if otherX > self.x and not self.facingRight then self.facingRight = true end
        if otherX < self.x and self.facingRight then self.facingRight = false end
    end
    local fd = self.facingRight and 1 or -1

    local bodyColor = self.colorHex
    if self.flashTimer > 0 then
        bodyColor = '#ffffff'
    end
    if self.invincible > 0 and math.floor(self.invincible * 20) % 2 == 0 then
        bodyColor = '#66ffffff'
    end

    local hipY = y - self.lowerLegLen - self.upperLegLen
    local shoulderY = hipY - self.bodyLen
    local neckY = shoulderY - self.neckLen
    local headCY = neckY - self.headRadius

    local state = self.state
    local st = self.stateTimer
    local punchArmExtend = 0
    local kickLegExtend = 0

    if state == 'punch' then
        local prog = math.min(1, st / self.punchDuration)
        if prog < self.punchActiveStart then
            punchArmExtend = prog / self.punchActiveStart
        elseif prog < self.punchActiveEnd then
            punchArmExtend = 1
        else
            punchArmExtend = 1 - (prog - self.punchActiveEnd) / (1 - self.punchActiveEnd)
        end
        punchArmExtend = math.max(0, math.min(1, punchArmExtend))
    end
    if state == 'kick' then
        local prog = math.min(1, st / self.kickDuration)
        if prog < self.kickActiveStart then
            kickLegExtend = prog / self.kickActiveStart
        elseif prog < self.kickActiveEnd then
            kickLegExtend = 1
        else
            kickLegExtend = 1 - (prog - self.kickActiveEnd) / (1 - self.kickActiveEnd)
        end
        kickLegExtend = math.max(0, math.min(1, kickLegExtend))
    end

    -- 取消 idle 状态下的呼吸晃动，减少不必要的同步
    local breathe = 0
    shoulderY = shoulderY + breathe
    neckY = neckY + breathe
    headCY = headCY + breathe
    hipY = hipY + breathe * 0.5

    local walkCycle = (state == 'walk') and math.sin(self.animPhase * 2.5) * 8 or 0
    local walkBob = (state == 'walk') and math.abs(math.cos(self.animPhase * 2.5)) * 5 or 0
    hipY = hipY - walkBob
    shoulderY = shoulderY - walkBob
    neckY = neckY - walkBob
    headCY = headCY - walkBob

    if state == 'hit' then
        local hitProg = st / 0.45
        local leanBack = math.sin(hitProg * math.pi) * 15
        shoulderY = shoulderY - leanBack * 0.6
        neckY = neckY - leanBack * 0.7
        headCY = headCY - leanBack * 0.8
    end

    if state == 'knockdown' then
        local kdProg = math.min(1, st / 0.6)
        local lieDown = kdProg * 0.9
        shoulderY = hipY - self.bodyLen * (1 - lieDown)
        neckY = shoulderY
        headCY = shoulderY - self.headRadius * (1 - lieDown * 0.5)
    end

    -- 缓存位置，避免重复设置
    local headX = math.floor(x - self.headRadius)
    local headY = math.floor(headCY)
    if headX ~= self._cache_headX or headY ~= self._cache_headY then
        self._cache_headX = headX
        self._cache_headY = headY
        self.head:set_pos(headX, headY)
    end

    local torsoX = math.floor(x - 4)
    local torsoY = math.floor(shoulderY)
    if torsoX ~= self._cache_torsoX or torsoY ~= self._cache_torsoY then
        self._cache_torsoX = torsoX
        self._cache_torsoY = torsoY
        self.torso:set_pos(torsoX, torsoY)
    end

    local legTopY = hipY
    local legMidY = hipY + self.upperLegLen

    local frontLegX = x + fd * 4
    local backLegX = x - fd * 4
    local walkOffsetFront = walkCycle
    local walkOffsetBack = -walkCycle

    local flKneeX = frontLegX
    local flKneeY = legMidY

    if kickLegExtend > 0.01 then
        local ext = kickLegExtend
        flKneeX = frontLegX + fd * 25 * ext
        flKneeY = legMidY - 20 * ext
    end

    local leftLegX = math.floor(backLegX - 2)
    local leftLegY = math.floor(legMidY)
    if leftLegX ~= self._cache_leftLegX or leftLegY ~= self._cache_leftLegY then
        self._cache_leftLegX = leftLegX
        self._cache_leftLegY = leftLegY
        self.leftLeg:set_pos(leftLegX, leftLegY)
    end

    local rightLegX = math.floor(flKneeX - 2)
    local rightLegY = math.floor(flKneeY)
    if rightLegX ~= self._cache_rightLegX or rightLegY ~= self._cache_rightLegY then
        self._cache_rightLegX = rightLegX
        self._cache_rightLegY = rightLegY
        self.rightLeg:set_pos(rightLegX, rightLegY)
    end

    local frontShoulderX = x + fd * 4
    local backShoulderX = x - fd * 4

    local bElbowY = shoulderY + 18
    local bHandY = bElbowY + 16
    if state == 'walk' then
        bElbowY = bElbowY - walkOffsetBack * 0.4
        bHandY = bHandY - walkOffsetBack * 0.5
    end

    local fElbowY = shoulderY + 18
    local fHandY = fElbowY + 16

    if self:isBlocking() then
        fElbowY = shoulderY - 5
        fHandY = shoulderY + 5
    end
    if punchArmExtend > 0.01 then
        local ext = punchArmExtend
        fElbowY = shoulderY - 15 * ext
        fHandY = shoulderY - 8 * ext
    end
    if state == 'walk' then
        fElbowY = fElbowY - walkOffsetFront * 0.4
        fHandY = fHandY - walkOffsetFront * 0.5
    end
    if state == 'knockdown' then
        fElbowY = shoulderY + 20
        fHandY = fElbowY + 10
    end

    local leftArmX = math.floor(backShoulderX - 2 - fd * 8)
    local leftArmY = math.floor(bElbowY)
    if leftArmX ~= self._cache_leftArmX or leftArmY ~= self._cache_leftArmY then
        self._cache_leftArmX = leftArmX
        self._cache_leftArmY = leftArmY
        self.leftArm:set_pos(leftArmX, leftArmY)
    end

    local rightArmX = math.floor(frontShoulderX + fd * 8 - 2)
    local rightArmY = math.floor(fElbowY)
    if rightArmX ~= self._cache_rightArmX or rightArmY ~= self._cache_rightArmY then
        self._cache_rightArmX = rightArmX
        self._cache_rightArmY = rightArmY
        self.rightArm:set_pos(rightArmX, rightArmY)
    end
end

function StickFighter:reset(x, y)
    self.x = x
    self.y = y
    self.groundY = y
    self.hp = self.maxHp
    self.state = 'idle'
    self.stateTimer = 0
    self.attackCooldown = 0
    self.hitStun = 0
    self.invincible = 0
    self.isJumping = false
    self.jumpVelocity = 0
    self.flashTimer = 0
    self.bodyOffsetX = 0
    self.bodyOffsetY = 0
    self.currentAttackHit = false
    self.facingRight = (x < W / 2)
    self.inputLeft = false
    self.inputRight = false
    self.inputJump = false
    self.inputPunch = false
    self.inputKick = false
    self.inputBlock = false
    self.prevPunch = false
    self.prevKick = false
    self.prevJump = false
end

function StickFighter:setColor(newColorHex)
    self.colorHex = newColorHex
    if self.head then self.head:set_color(newColorHex) end
    if self.torso then self.torso:set_color(newColorHex) end
    if self.leftLeg then self.leftLeg:set_color(newColorHex) end
    if self.rightLeg then self.rightLeg:set_color(newColorHex) end
    if self.leftArm then self.leftArm:set_color(newColorHex) end
    if self.rightArm then self.rightArm:set_color(newColorHex) end
end

function StickFighter:show()
    if self.bodyContainer then self.bodyContainer:open() end
end

function StickFighter:hide()
    if self.bodyContainer then self.bodyContainer:hide() end
end

function StickFighter:destroy()
    if self.bodyContainer then
        self.bodyContainer:destroy()
        self.bodyContainer = nil
    end
end

local function spawnHitParticles(x, y, count)
    count = count or 8
    for i = 1, count do
        local angle = math.random() * math.pi * 2
        local speed = 2 + math.random() * 6
        table.insert(particles, {
            x = x, y = y,
            vx = math.cos(angle) * speed,
            vy = math.sin(angle) * speed - 2,
            life = 0.3 + math.random() * 0.5,
            size = 1.5 + math.random() * 3
        })
    end
end

local function triggerKO(winner, loser)
    gameState = STATE.KO
    koTimer = 0
    koWinner = winner
    loser:setState('knockdown')
    spawnHitParticles(loser.x, loser:getHeadCenterY(), 20)
    shakeAmount = 12

    if koContainer then koContainer:open() end
    if winnerContainer then
        winnerLabel:set_text(winner.name .. ' 获胜!')
        winnerContainer:open()
    end
    if restartContainer then restartContainer:open() end
    -- 如果是服务器，广播KO消息给客户端
    if game_state_mqtt.is_server and game_state_mqtt.peer_connected and game_state_mqtt.mqtt_client then
        local ko_data = {
            type = 'ko',
            winner_name = winner.name,
            winner_is_server = true
        }
        local ok, json_str = pcall(json.encode, ko_data)
        if ok then
            game_state_mqtt.mqtt_client:publish(TOPIC_DATA .. game_state_mqtt.peer_device_id, json_str, MQTT_QOS)
            log.info('triggerKO', '广播KO消息')
        end
    end
    -- KO时立即上传积分
    upload_score()
end

----------------------------------------------------------------------
-- 积分上传（先查询服务器当前总积分，累加后再上传）
----------------------------------------------------------------------
function upload_score()
    log.info("score", "【上传积分】开始，当前myScore:", myScore, "gameState:", gameState)
    
    if myScore == 0 then
        log.info("score", "【上传积分】积分为0，无需上传")
        return
    end
    if not exapp then
        log.warn("score", "【上传积分】exapp 不可用")
        return
    end

    local ok, info = pcall(exapp.iot_get_account_info)
    if not ok or not info or info.is_guest then
        log.warn("score", "【上传积分】未登录或访客模式，不上传")
        return
    end

    pendingUpload = {
        account = info.account or "unknown",
        nickname = info.nickname or "unknown",
        score = myScore  -- 可能为负数
    }
    log.info("score", "【上传积分】查询自己的积分 account:", pendingUpload.account, "本场:", pendingUpload.score)
    -- 先查询服务器当前总积分（使用filter精确过滤uni_key），DB_RESULT 回调中累加后上传
    exapp.list_record({
        cls = SCORE_CLS,
        size = 1,
        filter = {
            aks = {"uni_key"},
            acs = {"eq"},
            avs = {pendingUpload.account},
        },
    })
end

----------------------------------------------------------------------
-- 排行榜（卡片式列表）
----------------------------------------------------------------------
local function rebuild_leaderboard_ui()
    if not leaderboardMainContainer then return end

    for _, item in ipairs(leaderboardItems) do
        if item then item:destroy() end
    end
    leaderboardItems = {}

    local cardW = 400
    local cardX = W / 2 - 200
    local cardH = 30
    local gap = 3
    local yPos = 50

    -- 表头卡片
    local header = airui.container({
        parent = leaderboardMainContainer,
        x = cardX, y = yPos, w = cardW, h = 24,
        color = 0xE8F0FE,
        radius = 4
    })
    table.insert(leaderboardItems, header)

    airui.label({
        parent = header, x = 12, y = 4, w = 50, h = 16,
        text = "排名", font_size = 13, color = 0x007AFF
    })
    airui.label({
        parent = header, x = 80, y = 4, w = 200, h = 16,
        text = "昵称", font_size = 13, color = 0x007AFF
    })
    airui.label({
        parent = header, x = 320, y = 4, w = 70, h = 16,
        text = "积分", font_size = 13, color = 0x007AFF,
        align = airui.TEXT_ALIGN_RIGHT
    })

    yPos = yPos + 24 + gap + 2

    if #leaderboardData == 0 then
        local empty = airui.container({
            parent = leaderboardMainContainer,
            x = cardX, y = yPos, w = cardW, h = 50,
            color = 0xFFFFFF,
            radius = 6
        })
        table.insert(leaderboardItems, empty)
        airui.label({
            parent = empty, x = 0, y = 15, w = cardW, h = 20,
            text = "暂无数据", font_size = 16, color = 0x888888,
            align = airui.TEXT_ALIGN_CENTER
        })
        return
    end

    -- 计算当前页的起始和结束索引（每页11个）
    local startIdx = (leaderboardPage - 1) * 11 + 1
    local endIdx = math.min(startIdx + 10, #leaderboardData)

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
            parent = card, x = 12, y = 6, w = 50, h = 18,
            text = tostring(i), font_size = 14,
            color = textColor
        })
        table.insert(leaderboardItems, rankLabel)

        -- 昵称
        local nameLabel = airui.label({
            parent = card, x = 80, y = 6, w = 200, h = 18,
            text = displayName, font_size = 14,
            color = textColor
        })
        table.insert(leaderboardItems, nameLabel)

        -- 积分（右对齐，紧贴右边）
        local scoreLabel = airui.label({
            parent = card, x = 320, y = 6, w = 70, h = 18,
            text = tostring(score), font_size = 14,
            color = textColor,
            align = airui.TEXT_ALIGN_RIGHT
        })
        table.insert(leaderboardItems, scoreLabel)

        yPos = yPos + cardH + gap
    end

    -- 如果当前页包含第30名且是最后一条，显示提示
    if endIdx == 30 and endIdx <= #leaderboardData then
        yPos = yPos + 5
        local tipLabel = airui.label({
            parent = leaderboardMainContainer,
            x = cardX, y = yPos, w = cardW, h = 22,
            text = "—— 仅展示前30名，更多高手等你来挑战！——",
            font_size = 13,
            color = 0x888888,
            align = airui.TEXT_ALIGN_CENTER
        })
        table.insert(leaderboardItems, tipLabel)
    end

    -- 分页控件区域（固定在列表下方，避免与底部按钮重叠）
    local pageControlY = 400

    -- 上一页按钮
    local prevBtn = airui.button({
        parent = leaderboardMainContainer,
        x = W / 2 - 150, y = pageControlY, w = 80, h = 32,
        text = "上一页",
        font_size = 13,
        text_color = 0xFFFFFF,
        bg_color = leaderboardPage > 1 and 0x228844 or 0x888888,
        radius = 4,
        on_click = function()
            if leaderboardPage > 1 then
                leaderboardPage = leaderboardPage - 1
                rebuild_leaderboard_ui()
            end
        end
    })
    table.insert(leaderboardItems, prevBtn)

    -- 页码显示 <页数/总页数>
    local pageLabel = airui.label({
        parent = leaderboardMainContainer,
        x = W / 2 - 60, y = pageControlY + 6, w = 120, h = 20,
        text = string.format("<%d/%d>", leaderboardPage, leaderboardTotalPages),
        font_size = 15,
        color = 0x333333,
        align = airui.TEXT_ALIGN_CENTER
    })
    table.insert(leaderboardItems, pageLabel)

    -- 下一页按钮
    local nextBtn = airui.button({
        parent = leaderboardMainContainer,
        x = W / 2 + 70, y = pageControlY, w = 80, h = 32,
        text = "下一页",
        font_size = 13,
        text_color = 0xFFFFFF,
        bg_color = leaderboardPage < leaderboardTotalPages and 0x228844 or 0x888888,
        radius = 4,
        on_click = function()
            if leaderboardPage < leaderboardTotalPages then
                leaderboardPage = leaderboardPage + 1
                rebuild_leaderboard_ui()
            end
        end
    })
    table.insert(leaderboardItems, nextBtn)
end

local function on_leaderboard_query_callback(success, data)
    -- log.info("leaderboard", "【回调】查询结果", "success:", success, "has_data:", data ~= nil)
    if success and data and data.records then
        -- log.info("leaderboard", "【回调】共" .. (data.total or #data.records) .. "条记录")
        if leaderboardLoadingLabel then
            leaderboardLoadingLabel:destroy()
            leaderboardLoadingLabel = nil
        end
        leaderboardData = data.records
        table.sort(leaderboardData, function(a, b)
            return (tonumber(a.i1) or 0) > (tonumber(b.i1) or 0)
        end)
        local total = data.total or #data.records
        leaderboardTotalPages = math.max(1, math.ceil(total / 11))
        rebuild_leaderboard_ui()
    end
end

local function on_leaderboard_db_result(endpoint, success, data)
    -- log.info("leaderboard", "DB_RESULT", "endpoint:", endpoint, "success:", success, "data:", json.encode(data or {}))
    if endpoint ~= "list" then return end

    -- 如果有待上传的积分，查询结果回来累加后上传
    if pendingUpload then
        local up = pendingUpload
        log.info("score", "【积分回调】检测到待上传积分", "account:", up.account, "score:", up.score, "justDeleted:", justDeletedMyScore)
        log.info("score", "【积分回调】data:", json.encode(data or {}))
        pendingUpload = nil  -- 先清除，防止异常
        myScore = 0  -- 积分已提交上传，重置本地积分
        if not exapp or not exapp.add_record then
            log.warn("score", "【积分回调】exapp.add_record 不可用，跳过上传")
            return
        end
        -- 如果刚刚删除了积分，强制按本场积分上传（防止读到旧缓存导致积分"复活"）
        if justDeletedMyScore then
            justDeletedMyScore = false  -- 用过即清
            local upload_val = math.max(0, up.score)  -- 防止负数（i1 是 uint）
            log.info("score", "【积分回调】刚删除过积分，强制覆盖上传:", upload_val, "(本场:", up.score, ")")
            if upload_val > 0 then
                pcall(exapp.add_record, {
                    cls = SCORE_CLS,
                    uni_key = up.account,
                    i1 = upload_val,
                    s1 = up.nickname,
                })
            else
                log.info("score", "【积分回调】删除后本场积分<=0，跳过上传")
            end
            return
        end
        if success and data and data.records and #data.records > 0 then
            local rec = data.records[1]
            -- 校验返回的uni_key是否匹配，避免服务器查询返回错误数据
            if rec.uni_key ~= up.account then
                log.warn("score", "【积分回调】返回的uni_key不匹配！返回:", rec.uni_key, "期望:", up.account, "→ 视为无历史记录")
                local upload_val = math.max(0, up.score)
                if upload_val > 0 then
                    log.info("score", "【积分回调】无匹配历史，首次上传积分:", upload_val)
                    pcall(exapp.add_record, {
                        cls = SCORE_CLS,
                        uni_key = up.account,
                        i1 = upload_val,
                        s1 = up.nickname,
                    })
                else
                    log.info("score", "【积分回调】无匹配历史且本场积分<=0，跳过上传")
                end
                return
            end
            local current_total = tonumber(rec.i1) or 0
            local new_total = math.max(0, current_total + up.score)  -- 累加后保证不为负
            log.info("score", "【积分回调】累加上传 原:", current_total, "本场变化:", up.score, "总:", new_total, "match_uni:", rec.uni_key, "expect_uni:", up.account)
            pcall(exapp.add_record, {
                cls = SCORE_CLS,
                uni_key = up.account,
                i1 = new_total,
                s1 = up.nickname,
            })
        elseif success and data and data.records then
            -- 无历史记录，本场为正才上传，负数不上传（避免负数变成0产生奇怪的记录）
            local upload_val = math.max(0, up.score)
            if upload_val > 0 then
                log.info("score", "【积分回调】无历史记录，首次上传积分:", upload_val)
                pcall(exapp.add_record, {
                    cls = SCORE_CLS,
                    uni_key = up.account,
                    i1 = upload_val,
                    s1 = up.nickname,
                })
            else
                log.info("score", "【积分回调】无历史记录且本场积分<=0，跳过上传")
            end
        else
            local upload_val = math.max(0, up.score)
            log.warn("score", "【积分回调】查询总积分失败，按本场积分上传:", upload_val)
            if upload_val > 0 then
                pcall(exapp.add_record, {
                    cls = SCORE_CLS,
                    uni_key = up.account,
                    i1 = upload_val,
                    s1 = up.nickname,
                })
            end
        end
        return
    end

    -- 排行榜查询（通过全局事件，非回调方式）
    if not success or not data or not data.records then
        -- log.warn("leaderboard", "【全局事件】查询失败")
        return
    end
    -- log.info("leaderboard", "【全局事件】处理排行榜数据，共", #data.records, "条记录")
    if leaderboardLoadingLabel then
        leaderboardLoadingLabel:destroy()
        leaderboardLoadingLabel = nil
    end
    leaderboardData = data.records
    table.sort(leaderboardData, function(a, b)
        return (tonumber(a.i1) or 0) > (tonumber(b.i1) or 0)
    end)
    local total = data.total or #data.records
    leaderboardTotalPages = math.max(1, math.ceil(total / 11))
    rebuild_leaderboard_ui()
end

local function open_leaderboard_win()
    if leaderboardWinId then
        exwin.close(leaderboardWinId)
        return
    end

    leaderboardData = {}
    leaderboardPage = 1
    leaderboardTotalPages = 1

    leaderboardWinId = exwin.open({
        on_create = function()
            leaderboardMainContainer = airui.container({
                parent = airui.screen,
                x = 0, y = 0, w = W, h = H,
                color = 0xFFFFFF
            })

            -- 标题左侧奖杯图标
            airui.image({
                parent = leaderboardMainContainer,
                src = "/luadb/ranking_list.png",
                x = W / 2 - 140,
                y = 8,
                w = 28,
                h = 28
            })

            -- 标题
            airui.label({
                parent = leaderboardMainContainer,
                x = 0, y = 10, w = W, h = 40,
                text = "火柴人积分排行榜",
                font_size = 24,
                color = 0x333333,
                align = airui.TEXT_ALIGN_CENTER
            })

            leaderboardLoadingLabel = airui.label({
                parent = leaderboardMainContainer,
                x = 0, y = 170, w = W, h = 35,
                text = "数据同步中，请稍等...",
                font_size = 16,
                color = 0x888888,
                align = airui.TEXT_ALIGN_CENTER
            })

            -- 打开时自动刷新一次（带回调）
            -- log.info("leaderboard", "【打开窗口】开始查询排行榜")
            exapp.list_record({cls = SCORE_CLS, sort = "i1 desc", size = 30}, on_leaderboard_query_callback)

            -- 底部按钮行：刷新 | 删除 | 关闭
            -- 刷新按钮（左）
            airui.button({
                parent = leaderboardMainContainer,
                x = W / 2 - 190, y = 435, w = 100, h = 36,
                text = "刷新",
                font_size = 15,
                text_color = 0xFFFFFF,
                bg_color = 0x228844,
                radius = 6,
                on_click = function()
                    -- log.info("leaderboard", "【刷新按钮】开始查询排行榜")
                    exapp.list_record({cls = SCORE_CLS, sort = "i1 desc", size = 30}, on_leaderboard_query_callback)
                end
            })

            -- TEMP TODO: 删除测试按钮（临时，正式版删除）
            airui.button({
                parent = leaderboardMainContainer,
                x = W / 2 - 65, y = 435, w = 130, h = 36,
                text = "删除我的积分",
                font_size = 13,
                text_color = 0xFFFFFF,
                bg_color = 0x888888,
                radius = 6,
                on_click = function()
                    -- 弹出确认弹窗，防止误触
                    local confirmContainer
                    confirmContainer = airui.container({
                        parent = leaderboardMainContainer,
                        x = W / 2 - 160, y = 170, w = 320, h = 140,
                        color = 0xFFFFFF,
                        radius = 12,
                        shadow = true
                    })
                    airui.label({
                        parent = confirmContainer, x = 0, y = 20, w = 320, h = 28,
                        text = "确认删除我的积分？",
                        font_size = 18, color = 0xCC0000,
                        align = airui.TEXT_ALIGN_CENTER
                    })
                    airui.label({
                        parent = confirmContainer, x = 0, y = 45, w = 260, h = 20,
                        text = "删除后无法恢复",
                        font_size = 12, color = 0x888888,
                        align = airui.TEXT_ALIGN_CENTER
                    })
                    -- 取消按钮
                    airui.button({
                        parent = confirmContainer,
                        x = 30, y = 80, w = 80, h = 32,
                        text = "取消",
                        font_size = 13, text_color = 0xFFFFFF, bg_color = 0x666666, radius = 5,
                        on_click = function()
                            -- log.info("score", "【删除积分】用户取消删除")
                            confirmContainer:destroy()
                        end
                    })
                    -- 确认按钮
                    airui.button({
                        parent = confirmContainer,
                        x = 150, y = 80, w = 80, h = 32,
                        text = "确认删除",
                        font_size = 13, text_color = 0xFFFFFF, bg_color = 0xCC0000, radius = 5,
                        on_click = function()
                            confirmContainer:destroy()
                            local ok, info = pcall(exapp.iot_get_account_info)
                            if ok and info and not info.is_guest then
                                local account = info.account or ""
                                -- log.info("score", "【删除积分】开始查找用户记录，account:", account)
                                local deleted = 0
                                for _, record in ipairs(leaderboardData) do
                                    local match = false
                                    if record.uni_key then
                                        match = (record.uni_key == account) or (record.uni_key:find(account, 1, true) == 1)
                                    end
                                    if match and record.id then
                                        -- log.info("score", "【删除积分】匹配到记录，id:", record.id, "uni_key:", record.uni_key)
                                        exapp.delete_record({cls = SCORE_CLS, id = record.id})
                                        deleted = deleted + 1
                                    end
                                end
                                if deleted > 0 then
                                    justDeletedMyScore = true  -- 标记已删除，下次上传强制覆盖（防服务器读缓存）
                                    log.info("score", "【删除积分】已设置justDeletedMyScore=true，下次上传将覆盖")
                                end
                                -- log.info("score", "【删除积分】完成，共删除", deleted, "条记录")
                                -- log.info("score", "【删除积分】300ms后刷新排行榜")
                                sys.timerStart(function()
                                    -- log.info("leaderboard", "【删除后刷新】开始查询排行榜")
                                    exapp.list_record({cls = SCORE_CLS, sort = "i1 desc", size = 30}, on_leaderboard_query_callback)
                                end, 300)
                            end
                        end
                    })
                end
            })
            -- TEMP END

            -- 关闭按钮（右）
            airui.button({
                parent = leaderboardMainContainer,
                x = W / 2 + 90, y = 435, w = 100, h = 36,
                text = "关闭",
                font_size = 15,
                text_color = 0xFFFFFF,
                bg_color = 0xCC0000,
                radius = 6,
                on_click = function()
                    close_leaderboard_win()
                end
            })

            -- 查询积分前 30 名（按 i1 降序，带回调）
            -- log.info("leaderboard", "【on_create】开始查询排行榜")
            exapp.list_record({cls = SCORE_CLS, sort = "i1 desc", size = 30}, on_leaderboard_query_callback)
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

local function close_leaderboard_win_impl()
    if leaderboardWinId then
        exwin.close(leaderboardWinId)
    end
end
close_leaderboard_win = close_leaderboard_win_impl

----------------------------------------------------------------------
-- 信息弹窗（积分规则、扣血规则、游戏版本）
----------------------------------------------------------------------
local infoWinId = nil
local infoMainContainer = nil

local function close_info_win_impl()
    if infoWinId then
        exwin.close(infoWinId)
    end
end

local function open_info_win()
    if infoWinId then
        exwin.close(infoWinId)
        return
    end

    infoWinId = exwin.open({
        on_create = function()
            infoMainContainer = airui.container({
                parent = airui.screen,
                x = 0, y = 0, w = W, h = H,
                color = 0xFFFFFF
            })

            -- 标题
            airui.label({
                parent = infoMainContainer,
                x = 0, y = 12, w = W, h = 36,
                text = "游戏信息",
                font_size = 20,
                color = 0x333333,
                align = airui.TEXT_ALIGN_CENTER
            })

            -- 版本号
            airui.label({
                parent = infoMainContainer,
                x = 0, y = 45, w = W, h = 20,
                text = "版本: " .. GAME_VERSION,
                font_size = 16,
                color = 0x888888,
                align = airui.TEXT_ALIGN_CENTER
            })

            -- 积分规则标题
            airui.label({
                parent = infoMainContainer,
                x = 15, y = 75, w = W - 30, h = 22,
                text = "【积分规则】",
                font_size = 16,
                color = 0x228844,
                align = airui.TEXT_ALIGN_LEFT
            })

            -- 积分规则内容
            airui.label({
                parent = infoMainContainer,
                x = 15, y = 98, w = W - 30, h = 18,
                text = "1、加分：拳击 +2，脚踢 +3",
                font_size = 14,
                color = 0x333333,
                align = airui.TEXT_ALIGN_LEFT
            })

            airui.label({
                parent = infoMainContainer,
                x = 15, y = 118, w = W - 30, h = 18,
                text = "2、扣分：被打/被踢 -1（最低0分）",
                font_size = 14,
                color = 0x333333,
                align = airui.TEXT_ALIGN_LEFT
            })

            -- 扣血规则标题
            airui.label({
                parent = infoMainContainer,
                x = 15, y = 150, w = W - 30, h = 22,
                text = "【扣血规则】",
                font_size = 16,
                color = 0xCC4444,
                align = airui.TEXT_ALIGN_LEFT
            })

            -- 扣血规则内容
            airui.label({
                parent = infoMainContainer,
                x = 15, y = 173, w = W - 30, h = 18,
                text = "1、拳击 -8 血量",
                font_size = 14,
                color = 0x333333,
                align = airui.TEXT_ALIGN_LEFT
            })

            airui.label({
                parent = infoMainContainer,
                x = 15, y = 193, w = W - 30, h = 18,
                text = "2、脚踢 -12 血量",
                font_size = 14,
                color = 0x333333,
                align = airui.TEXT_ALIGN_LEFT
            })

            airui.label({
                parent = infoMainContainer,
                x = 15, y = 213, w = W - 30, h = 18,
                text = "3、防御减伤 75%，持续 1.5 秒",
                font_size = 14,
                color = 0x333333,
                align = airui.TEXT_ALIGN_LEFT
            })

            -- 提示
            airui.label({
                parent = infoMainContainer,
                x = 15, y = 245, w = W - 30, h = 18,
                text = "注：防御过程积分照样扣 1 分",
                font_size = 14,
                color = 0xFF8800,
                align = airui.TEXT_ALIGN_LEFT
            })

            airui.label({
                parent = infoMainContainer,
                x = 15, y = 263, w = W - 30, h = 18,
                text = "（防御保护血量，不保护积分）",
                font_size = 14,
                color = 0x888888,
                align = airui.TEXT_ALIGN_LEFT
            })

            -- 关闭按钮（左上角）
            airui.button({
                parent = infoMainContainer,
                x = 20, y = 15, w = 60, h = 30,
                text = "关闭",
                font_size = 13,
                text_color = 0xFFFFFF,
                bg_color = 0xCC0000,
                radius = 5,
                on_click = function()
                    close_info_win_impl()
                end
            })
        end,
        on_destroy = function()
            if infoMainContainer then
                infoMainContainer:destroy()
                infoMainContainer = nil
            end
            infoWinId = nil
        end
    })
end

----------------------------------------------------------------------
-- IOT 登录状态显示（登录由首页应用商店完成，本应用只读取状态）
----------------------------------------------------------------------
local function update_login_menu_status_impl()
    if not loginMenuStatus then return end
    if not exapp then
        loginMenuStatus:set_text("IOT: 不可用")
        return
    end
    local ok, info = pcall(exapp.iot_get_account_info)
    if ok and info and not info.is_guest then
        local display = (info.nickname and #info.nickname > 0) and info.nickname or info.account or "已登录"
        if #display > 10 then display = display:sub(1, 10) .. ".." end
        loginMenuStatus:set_text("IOT: " .. display)
    else
        loginMenuStatus:set_text("IOT: 未登录")
    end
end
update_login_menu_status = update_login_menu_status_impl

local function checkAttackHit(attacker, defender)
    -- 只在攻击者正在攻击时才输出日志
    -- local should_log = (attacker.state == 'punch' or attacker.state == 'kick') and attacker:isAttackActive()
    -- if should_log then
    --     log.info('CHK', attacker.name, 'state:', attacker.state, 'active:', attacker:isAttackActive(), 'hit:', attacker.currentAttackHit)
    -- end
    
    if attacker.currentAttackHit then return end
    if not attacker:isAttackActive() then return end
    if defender.invincible > 0 then return end
    if defender.hp <= 0 then return end

    local atkRect = attacker:getAttackRect()
    local defRect = defender:getBodyRect()

    if not atkRect.active then return end

    local overlapX = math.max(0, math.min(atkRect.right, defRect.right) - math.max(atkRect.left, defRect.left))
    local overlapY = math.max(0, math.min(atkRect.bottom, defRect.bottom) - math.max(atkRect.top, defRect.top))

    if overlapX > 8 and overlapY > 5 then
        attacker.currentAttackHit = true

        -- 计分规则：
        -- 打一拳：攻击者 +2分，被攻击者 -1分
        -- 踢一脚：攻击者 +3分，被攻击者 -1分
        local attackScore = atkRect.type == 'kick' and 3 or 2
        local defendScore = 1

        -- 本地玩家命中对手
        if attacker == player1 then
            myScore = myScore + attackScore
            log.info("score", atkRect.type == 'kick' and "踢中!" or "命中!", "积分+", attackScore, "当前积分:", myScore)
        end
        -- 本地玩家被对手命中（允许负数，上传时会扣减历史积分）
        if defender == player1 then
            myScore = myScore - defendScore
            log.info("score", atkRect.type == 'kick' and "被踢中!" or "被命中!", "积分-", defendScore, "当前积分:", myScore)
        end

        -- 只在服务端执行扣血和特效
        if game_state_mqtt.is_server then
            local damage = atkRect.type == 'kick' and attacker.kickDamage or attacker.punchDamage
            local actualDmg = defender:takeDamage(damage, attacker.x)

            local hitX = (attacker.x + defender.x) / 2
            local hitY = (defender:getShoulderY() + defender.y) / 2
            spawnHitParticles(hitX, hitY, atkRect.type == 'kick' and 12 or 8)
            shakeAmount = math.max(shakeAmount, atkRect.type == 'kick' and 7 or 4)

            if defender.hp <= 0 and gameState == STATE.FIGHTING then
                triggerKO(attacker, defender)
            end
        end
    end
end

local function enforceDistance(p1, p2, minDist)
    minDist = minDist or 48
    -- 计算距离时考虑对方的偏移！
    local p1_actual_x = p1.x + p1.bodyOffsetX
    local p2_actual_x = p2.x + p2.bodyOffsetX
    local dx = p2_actual_x - p1_actual_x
    local dist = math.abs(dx)
    if dist < minDist and dist > 0.01 then
        local overlap = minDist - dist
        local sign = dx > 0 and 1 or -1
        -- 关键修复：双向限制，本地玩家和远程玩家都不能穿过对方
        p1.x = p1.x - sign * overlap * 0.5
        p2.x = p2.x + sign * overlap * 0.5
    end
    local minX = 20
    local maxX = W - 20
    p1.x = math.max(minX, math.min(maxX, p1.x))
    p2.x = math.max(minX, math.min(maxX, p2.x))
end

-- 执行实际的发送操作
local function do_send_my_state()
    if not game_state_mqtt.peer_connected or not game_state_mqtt.mqtt_client then return end
    local now = getTimestamp()
    
    local data = {
        type = 'state',
        x = player1.x,
        y = player1.y,
        hp = game_state_mqtt.is_server and player1.hp or nil,
        state = player1.state,
        stateTimer = player1.stateTimer,
        facingRight = player1.facingRight,
        bodyOffsetX = player1.bodyOffsetX,
        bodyOffsetY = player1.bodyOffsetY,
        inputBlock = player1.inputBlock,
        sendTime = now,  -- 发送时间戳
    }
    -- 过滤 nil 字段
    local filtered = {}
    for k, v in pairs(data) do
        if v ~= nil then filtered[k] = v end
    end
    local ok, json_str = pcall(json.encode, filtered)
    if ok then
        game_state_mqtt.mqtt_client:publish(TOPIC_DATA .. game_state_mqtt.peer_device_id, json_str, MQTT_QOS)
        log.info('send_my_state', '已发送!', 'state:', data.state)
    end
    lastSendTime = now
    needsSend = false
    pendingSendTimer = nil
end

function send_my_state(force)
    -- log.info('send_my_state', '被调用!', 'force:', force, 'state:', player1.state)
    if not game_state_mqtt.peer_connected or not game_state_mqtt.mqtt_client then return end
    
    local now = getTimestamp()
    needsSend = true
    
    -- 检查是否可以立即发送
    if force or now - lastSendTime >= sendInterval then
        -- 取消之前的延迟发送
        if pendingSendTimer then
            sys.timerStop(pendingSendTimer)
            pendingSendTimer = nil
        end
        do_send_my_state()
    else
        -- 需要延迟发送，计算剩余时间
        local remaining = sendInterval - (now - lastSendTime)
        if not pendingSendTimer then
            -- 只设置一个新的延迟发送计时器
            pendingSendTimer = sys.timerStart(function()
                do_send_my_state()
            end, remaining)
        end
    end
end

-- 发送本方设备型号
local function send_device_info()
    if not game_state_mqtt.peer_connected or not game_state_mqtt.mqtt_client then return end
    local data = {
        type = 'device_info',
        model = my_device_model
    }
    local ok, json_str = pcall(json.encode, data)
    if ok then
        game_state_mqtt.mqtt_client:publish(TOPIC_DATA .. game_state_mqtt.peer_device_id, json_str, MQTT_QOS)
        log.info('send_device_info', '发送本方机型:', my_device_model)
    end
end

local function send_ready()
    if not game_state_mqtt.peer_connected or not game_state_mqtt.mqtt_client then return end
    local data = { type = 'ready', device_id = my_device_id }
    local ok, json_str = pcall(json.encode, data)
    if ok then
        game_state_mqtt.mqtt_client:publish(TOPIC_DATA .. game_state_mqtt.peer_device_id, json_str, MQTT_QOS)
        log.info('send_ready', '已发送准备信号，给:', game_state_mqtt.peer_device_id)
    end
end

local function send_opponent_left()
    if not game_state_mqtt.peer_connected or not game_state_mqtt.mqtt_client then return end
    local data = { type = 'opponent_left' }
    local ok, json_str = pcall(json.encode, data)
    if ok then
        game_state_mqtt.mqtt_client:publish(TOPIC_DATA .. game_state_mqtt.peer_device_id, json_str, MQTT_QOS)
        log.info('send_opponent_left', '已发送对手离开信号')
    end
    -- 游戏中途退出也上传积分
    upload_score()
end

local function show_toast(msg)
    if not main_container then return end
    local toast = airui.container({
        parent = main_container,
        x = W / 2 - 150, y = 100, w = 300, h = 45,
        color = 0xCC3333,
        radius = 8
    })
    airui.label({
        parent = toast, x = 0, y = 12, w = 300, h = 22,
        text = msg, font_size = 15, color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })
    sys.timerStart(function()
        if toast then toast:destroy() end
    end, 1200)
end

local function close_invite_waiting()
    if inviteWaitingContainer then
        inviteWaitingContainer:hide()
    end
    inviteTargetDeviceId = nil
end

local function show_invite_waiting()
    if not main_container then return end
    if inviteWaitingContainer then
        inviteWaitingContainer:open()
    end
end

local function update_score_display()
    if scoreLabel and peerModelLabel then
        local role = nil
        local pid = game_state_mqtt.peer_device_id
        if pid then
            role = (my_device_id < pid) and '红方' or '蓝方'
        end
        -- 第一行：角色 + 对方机型（只在连接建立后显示）
        local peerText = ''
        if role then
            peerText = '您是' .. role
            if game_state_mqtt.peer_device_model then
                peerText = peerText .. ' | 对方机型：' .. game_state_mqtt.peer_device_model
            end
        end
        -- 带缓存更新
        if peerText ~= ui_cache.peer_text then
            ui_cache.peer_text = peerText
            peerModelLabel:set_text(peerText)
        end

        -- 第二行：本场积分（带缓存）
        local score_text = '本场积分: ' .. myScore
        if score_text ~= ui_cache.score_text then
            ui_cache.score_text = score_text
            scoreLabel:set_text(score_text)
        end
        -- 颜色缓存
        if scoreLabel.set_color then
            local score_color = myScore >= 0 and 0xffcc00 or 0xff4444
            if score_color ~= ui_cache.score_color then
                ui_cache.score_color = score_color
                scoreLabel:set_color(score_color)
            end
        end
    end
end

local function start_game_connect(peer_device_id)
    if not peer_device_id then return end
    close_invite_waiting()
    if leaderboardWinId then
        exwin.close(leaderboardWinId)
        leaderboardWinId = nil
    end
    if infoWinId then
        exwin.close(infoWinId)
        infoWinId = nil
    end
    game_state_mqtt.peer_device_id = peer_device_id
    game_state_mqtt.peer_connected = true
    game_state_mqtt.is_server = my_device_id < peer_device_id
    game_state_mqtt.i_am_ready = false
    game_state_mqtt.peer_ready = false
    gameState = STATE.WAITING

    -- 更新显示（显示您是红方/蓝方和对方机型）
    update_score_display()

    if game_state_mqtt.is_server then
        player1:reset(80, GROUND_Y)
        player2:reset(240, GROUND_Y)
        player1.facingRight = true
        player2.facingRight = false
        player1.name = '红方'
        player2.name = '蓝方'
        player1:setColor(0xff4455)
        player2:setColor(0x4499ff)
        if hp1Bar then hp1Bar:set_indicator_color(0xff4455) end
        if hp2Bar then hp2Bar:set_indicator_color(0x4499ff) end
        if hp1Label then hp1Label:set_text('红方') end
        if hp2Label then hp2Label:set_text('蓝方') end
    else
        player1:reset(240, GROUND_Y)
        player2:reset(80, GROUND_Y)
        player1.facingRight = false
        player2.facingRight = true
        player1.name = '蓝方'
        player2.name = '红方'
        player1:setColor(0x4499ff)
        player2:setColor(0xff4455)
        if hp1Bar then hp1Bar:set_indicator_color(0xff4455) end
        if hp2Bar then hp2Bar:set_indicator_color(0x4499ff) end
        if hp1Label then hp1Label:set_text('红方') end
        if hp2Label then hp2Label:set_text('蓝方') end
    end

    player1:show()
    player2:show()
    if statusLabel then
        local myRole = game_state_mqtt.is_server and '红方' or '蓝方'
        statusLabel:set_text('您是' .. myRole .. '！ 等待对手准备...')
    end

    isConnecting = true
    close_device_list_win()
    sys.timerStart(function()
        game_state_mqtt.i_am_ready = true
        send_ready()
        send_start_game()
        check_both_ready()
    end, 200)
end

local function close_invite_dialog()
    if inviteDialogContainer then
        inviteDialogContainer:destroy()
        inviteDialogContainer = nil
    end
end

local function show_invite_dialog(nickname, sender_device_id)
    if not main_container then return end
    close_invite_dialog()
    inviteRequestDeviceId = sender_device_id

    inviteDialogContainer = airui.container({
        parent = main_container,
        x = W / 2 - 150, y = 140, w = 300, h = 110,
        color = 0xFFFFFF,
        radius = 10,
        shadow = true
    })
    airui.label({
        parent = inviteDialogContainer, x = 0, y = 18, w = 300, h = 26,
        text = nickname .. ' 邀请你对战',
        font_size = 17, color = 0x333333,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.button({
        parent = inviteDialogContainer,
        x = 40, y = 60, w = 100, h = 36,
        text = '同意',
        font_size = 15, text_color = 0xFFFFFF, bg_color = 0x009933, radius = 6,
        on_click = function()
            close_invite_dialog()
            if game_state_mqtt.mqtt_client and sender_device_id then
                local data = { type = 'connect_accept', device_id = my_device_id, nickname = get_nickname(), model = my_device_model }
                local ok, json_str = pcall(json.encode, data)
                if ok then
                    game_state_mqtt.mqtt_client:publish(TOPIC_DATA .. sender_device_id, json_str, MQTT_QOS)
                end
            end
            start_game_connect(sender_device_id)
        end
    })
    airui.button({
        parent = inviteDialogContainer,
        x = 160, y = 60, w = 100, h = 36,
        text = '拒绝',
        font_size = 15, text_color = 0xFFFFFF, bg_color = 0xCC0000, radius = 6,
        on_click = function()
            close_invite_dialog()
            if game_state_mqtt.mqtt_client and sender_device_id then
                local data = { type = 'connect_reject', device_id = my_device_id }
                local ok, json_str = pcall(json.encode, data)
                if ok then
                    game_state_mqtt.mqtt_client:publish(TOPIC_DATA .. sender_device_id, json_str, MQTT_QOS)
                end
            end
        end
    })
end

local function reset_to_menu()
    if is_resetting then return end
    is_resetting = true

    local ok = pcall(function()
        close_invite_waiting()
        close_invite_dialog()

        game_state_mqtt.peer_connected = false
        game_state_mqtt.peer_ready = false
        game_state_mqtt.i_am_ready = false
        game_state_mqtt.peer_device_id = nil
        game_state_mqtt.peer_device_model = nil
        game_state_mqtt.is_server = nil

        if player1 then player1:reset(80, GROUND_Y) player1:hide() end
        if player2 then player2:reset(240, GROUND_Y) player2:hide() end
        particles = {}
        shakeAmount = 0
        koWinner = nil
        koTimer = 0
        myScore = 0
        update_score_display()
        if hp1Bar then hp1Bar:set_value(100, true) end
        if hp2Bar then hp2Bar:set_value(100, true) end
        if hp1Text then hp1Text:set_text('100/100') end
        if hp2Text then hp2Text:set_text('100/100') end

        set_container_visible(koContainer, false)
        set_container_visible(winnerContainer, false)
        set_container_visible(restartContainer, false)
        set_container_visible(countdownContainer, false)
        set_container_visible(menuContainer, true)

        if statusLabel then
            statusLabel:set_text('查找对手开始对战')
        end

        gameState = STATE.MENU
    end)

    is_resetting = false
    if not ok then
        log.error("reset_to_menu", "执行异常")
    end
end

local function startCountdown()
    if gameState ~= STATE.WAITING and gameState ~= STATE.KO and gameState ~= STATE.MENU then return end
    gameState = STATE.COUNTDOWN
    countdownValue = 3
    countdownTimer = 0

    if game_state_mqtt.is_server then
        player1:reset(100, GROUND_Y)
        player2:reset(220, GROUND_Y)
        player1.facingRight = true
        player2.facingRight = false
        player1.name = '红方'
        player2.name = '蓝方'
        player1:setColor(0xff4455)
        player2:setColor(0x4499ff)
        if hp1Bar then hp1Bar:set_indicator_color(0xff4455) end
        if hp2Bar then hp2Bar:set_indicator_color(0x4499ff) end
        if hp1Label then hp1Label:set_text('红方') end
        if hp2Label then hp2Label:set_text('蓝方') end
    else
        player1:reset(220, GROUND_Y)
        player2:reset(100, GROUND_Y)
        player1.facingRight = false
        player2.facingRight = true
        player1.name = '蓝方'
        player2.name = '红方'
        player1:setColor(0x4499ff)
        player2:setColor(0xff4455)
        -- 客户端血条位置和颜色保持不变：左红方，右蓝方
        if hp1Bar then hp1Bar:set_indicator_color(0xff4455) end
        if hp2Bar then hp2Bar:set_indicator_color(0x4499ff) end
        if hp1Label then hp1Label:set_text('红方') end
        if hp2Label then hp2Label:set_text('蓝方') end
    end

    player1.invincible = 0
    player2.invincible = 0

    player1:show()
    player2:show()

    set_container_visible(countdownContainer, true)
    set_container_visible(menuContainer, false)
    
    -- 清空等待提示
    if statusLabel then
        statusLabel:set_text('')
    end
end

check_both_ready = function()
    if game_state_mqtt.i_am_ready and game_state_mqtt.peer_ready then
        log.info('check_both_ready', '双方都已准备，开始倒计时')
        startCountdown()
    end
end

send_start_game = function()
    if not game_state_mqtt.peer_connected or not game_state_mqtt.mqtt_client then return end
    local data = { type = 'start_game', device_id = my_device_id }
    local ok, json_str = pcall(json.encode, data)
    if ok then
        game_state_mqtt.mqtt_client:publish(TOPIC_DATA .. game_state_mqtt.peer_device_id, json_str, MQTT_QOS)
    end
end

local function send_restart()
    if not game_state_mqtt.peer_connected or not game_state_mqtt.mqtt_client then return end
    local data = { type = 'restart' }
    local ok, json_str = pcall(json.encode, data)
    if ok then
        game_state_mqtt.mqtt_client:publish(TOPIC_DATA .. game_state_mqtt.peer_device_id, json_str, MQTT_QOS)
        log.info('send_restart', '已发送重新开始信号')
    end
end

local function resetGame(fromRemote)
    if is_resetting then return end
    is_resetting = true

    -- 如果是从本地发起，通知对手重新开始
    if not fromRemote then
        send_restart()
    end

    -- 重置准备状态，方便重新开始
    game_state_mqtt.i_am_ready = false
    game_state_mqtt.peer_ready = false
    
    particles = {}
    shakeAmount = 0
    koWinner = nil
    koTimer = 0

    set_container_visible(koContainer, false)
    set_container_visible(winnerContainer, false)
    set_container_visible(restartContainer, false)

    -- KO 后重新开始，发送 ready 信号等待对方
    gameState = STATE.WAITING
    if statusLabel then
        statusLabel:set_text('等待对手准备...')
    end
    game_state_mqtt.i_am_ready = true
    send_ready()
    check_both_ready()
    
    is_resetting = false
end

local accumulatedDt = 0
local fixedDt = 1 / 60  -- 60 FPS，流畅度优先
local gameTimerId = nil
local GAME_LOOP_INTERVAL = 16  -- 约60 FPS

local function update(dt)
    if shakeAmount > 0.05 then
        shakeAmount = shakeAmount * shakeDecay
    else
        shakeAmount = 0
    end

    for i = #particles, 1, -1 do
        particles[i].life = particles[i].life - dt
        if particles[i].life <= 0 then
            table.remove(particles, i)
        end
    end

    -- 等待和倒计时状态下，禁止一切操作
    if gameState == STATE.WAITING or gameState == STATE.COUNTDOWN then
        -- 等待状态显示提示
        if gameState == STATE.WAITING and statusLabel then
            if game_state_mqtt.peer_ready then
                statusLabel:set_text('对手已准备！')
            else
                statusLabel:set_text('等待对手准备...')
            end
        end
        -- 禁止一切输入（移动+攻击）
        player1.inputLeft = false
        player1.inputRight = false
        player1.inputJump = false
        player1.inputPunch = false
        player1.inputKick = false
        player1.inputBlock = false
        if gameState == STATE.COUNTDOWN then
            countdownTimer = countdownTimer + dt
            if countdownTimer >= 1.0 then
                countdownTimer = countdownTimer - 1.0
                countdownValue = countdownValue - 1
                if countdownValue <= 0 then
                    gameState = STATE.FIGHTING
                    countdownValue = 0
                    set_container_visible(countdownContainer, false)
                end
            end
            if countdownLabel then
                countdownLabel:set_text(countdownValue > 0 and tostring(countdownValue) or 'FIGHT!')
            end
        end
        return
    end

    if gameState == STATE.KO then
        koTimer = koTimer + dt
        return
    end

    if gameState ~= STATE.FIGHTING then return end

    -- 1. 先检测攻击（使用本帧开始时的状态）
    checkAttackHit(player1, player2)
    checkAttackHit(player2, player1)

    -- 2. 更新玩家状态（移动、攻击计时等）
    player1:update(dt)
    player2:update(dt)  

    enforceDistance(player1, player2, 30)

    -- 任何非攻击状态下都自动更新朝向，确保攻击方向正确
    if player1.x < player2.x then
        if player1.state ~= 'punch' and player1.state ~= 'kick' and player1.state ~= 'hit' and player1.state ~= 'knockdown' then
            player1.facingRight = true
        end
        if player2.state ~= 'punch' and player2.state ~= 'kick' and player2.state ~= 'hit' and player2.state ~= 'knockdown' then
            player2.facingRight = false
        end
    else
        if player1.state ~= 'punch' and player1.state ~= 'kick' and player1.state ~= 'hit' and player1.state ~= 'knockdown' then
            player1.facingRight = false
        end
        if player2.state ~= 'punch' and player2.state ~= 'kick' and player2.state ~= 'hit' and player2.state ~= 'knockdown' then
            player2.facingRight = true
        end
    end


end

local function updateUI()
    -- 左血条永远显示红方血量（带缓存）
    if hp1Bar then
        local hp1_value = game_state_mqtt.is_server and player1.hp or player2.hp
        if hp1_value ~= ui_cache.hp1_value then
            ui_cache.hp1_value = hp1_value
            hp1Bar:set_value(hp1_value, false)
        end
    end
    -- 右血条永远显示蓝方血量（带缓存）
    if hp2Bar then
        local hp2_value = game_state_mqtt.is_server and player2.hp or player1.hp
        if hp2_value ~= ui_cache.hp2_value then
            ui_cache.hp2_value = hp2_value
            hp2Bar:set_value(hp2_value, false)
        end
    end
    -- 左HP文字显示红方（带缓存）
    if hp1Text then
        local hp1_text = 'HP: ' .. (game_state_mqtt.is_server and player1.hp or player2.hp) .. ' / 100'
        if hp1_text ~= ui_cache.hp1_text then
            ui_cache.hp1_text = hp1_text
            hp1Text:set_text(hp1_text)
        end
    end
    -- 右HP文字显示蓝方（带缓存）
    if hp2Text then
        local hp2_text = 'HP: ' .. (game_state_mqtt.is_server and player2.hp or player1.hp) .. ' / 100'
        if hp2_text ~= ui_cache.hp2_text then
            ui_cache.hp2_text = hp2_text
            hp2Text:set_text(hp2_text)
        end
    end

    -- 只在连接建立后更新积分显示（避免每帧不必要的调用）
    if scoreLabel and game_state_mqtt.peer_connected then
        update_score_display()
    end

    player1:draw(player2.x)
    player2:draw(player1.x)
end

local function gameLoop()
    -- 简化：直接用固定时间步长，每帧只更新一次
    update(fixedDt)
    updateUI()
end


local function send_presence()
    if not game_state_mqtt.mqtt_ready then return end
    local data = {
        type = 'presence',
        device_id = my_device_id,
        is_server = game_state_mqtt.is_server,
        is_connected = game_state_mqtt.peer_connected,
        nickname = get_nickname()
    }
    local ok, json_str = pcall(json.encode, data)
    if ok and game_state_mqtt.mqtt_client then
        game_state_mqtt.mqtt_client:publish(TOPIC_PRESENCE, json_str, MQTT_QOS)
    end
end

close_device_list_win = function()
    log.info('close_device_list_win', 'device_list_win_id:', device_list_win_id)
    if device_list_win_id then
        log.info('close_device_list_win', 'closing window, isConnecting:', isConnecting)
        exwin.close(device_list_win_id)
        log.info('close_device_list_win', 'exwin.close调用完毕')
    else
        log.info('close_device_list_win', 'no window to close')
    end
end

local function update_device_list_ui()
    if not device_list_main_container then return end

    -- 先清理30秒没收到心跳的离线设备，以及对战中已连接的设备
    local now = os.time()
    for device_id, device_info in pairs(game_state_mqtt.online_devices) do
        if (device_info.last_seen and now - device_info.last_seen > 30) or device_info.is_connected then
            game_state_mqtt.online_devices[device_id] = nil
        end
    end

    for _, item in ipairs(device_list_popup_items) do
        if item then item:destroy() end
    end
    device_list_popup_items = {}

    -- 收集排除自己的设备列表
    local devices = {}
    for device_id, _ in pairs(game_state_mqtt.online_devices) do
        if device_id ~= my_device_id then
            table.insert(devices, device_id)
        end
    end

    local count = #devices
    local yPos = 45

    -- 在线设备计数
    local countLabel = airui.label({
        parent = device_list_main_container,
        text = '在线设备: ' .. count,
        x = 0, y = yPos, w = W, h = 24,
        font_size = 14,
        color = 0x0066cc,
        align = airui.TEXT_ALIGN_CENTER
    })
    table.insert(device_list_popup_items, countLabel)

    yPos = yPos + 30

    if count == 0 then
        local label = airui.label({
            parent = device_list_main_container,
            text = '暂无在线设备',
            x = 0, y = yPos + 10, w = W, h = 40,
            font_size = 20,
            color = 0x888888,
            align = airui.TEXT_ALIGN_CENTER
        })
        table.insert(device_list_popup_items, label)
        return
    end

    -- 分页计算
    local totalPages = math.min(math.ceil(count / DEVICE_PAGE_SIZE), DEVICE_MAX_PAGES)
    if device_list_page > totalPages then device_list_page = totalPages end
    if device_list_page < 1 then device_list_page = 1 end

    local startIdx = (device_list_page - 1) * DEVICE_PAGE_SIZE + 1
    local endIdx = math.min(startIdx + DEVICE_PAGE_SIZE - 1, count)

    -- 当前页设备列表
    for i = startIdx, endIdx do
        local device_id = devices[i]

        local device_info = game_state_mqtt.online_devices[device_id] or {}
        local display_name = device_info.nickname or device_id:sub(1, 12)
        local nameLabel = airui.label({
            parent = device_list_main_container,
            text = display_name,
            x = W / 2 - 200, y = yPos, w = 300, h = 32,
            font_size = 15,
            color = 0x333333,
            align = airui.TEXT_ALIGN_LEFT
        })
        table.insert(device_list_popup_items, nameLabel)

        local btn = airui.button({
            parent = device_list_main_container,
            text = '邀请',
            x = W / 2 + 120, y = yPos + 2, w = 80, h = 28,
            font_size = 14,
            text_color = 0xffffff,
            bg_color = 0x009933,
            radius = 4,
            on_click = function()
                log.info('发送对战邀请，设备ID:', device_id)
                if game_state_mqtt.peer_connected then
                    show_toast('已在对战中')
                    return
                end
                if game_state_mqtt.mqtt_client then
                    local data = { type = 'connect_request', device_id = my_device_id, nickname = get_nickname(), model = my_device_model }
                    local ok, json_str = pcall(json.encode, data)
                    if ok then
                        game_state_mqtt.mqtt_client:publish(TOPIC_DATA .. device_id, json_str, MQTT_QOS)
                    end
                end
                inviteTargetDeviceId = device_id
                isConnecting = true
                close_device_list_win()
                show_invite_waiting()
            end
        })
        table.insert(device_list_popup_items, btn)

        yPos = yPos + 35
    end

    -- 分页控件
    if totalPages > 1 then
        yPos = yPos + 8

        airui.button({
            parent = device_list_main_container,
            x = W / 2 - 150, y = yPos, w = 80, h = 30,
            text = '上一页',
            font_size = 13,
            text_color = (device_list_page > 1) and 0xFFFFFF or 0x888888,
            bg_color = (device_list_page > 1) and 0x666666 or 0xCCCCCC,
            radius = 4,
            on_click = function()
                if device_list_page > 1 then
                    device_list_page = device_list_page - 1
                    update_device_list_ui()
                end
            end
        })

        airui.label({
            parent = device_list_main_container,
            text = device_list_page .. '/' .. totalPages,
            x = W / 2 - 50, y = yPos + 5, w = 100, h = 20,
            font_size = 14,
            color = 0x333333,
            align = airui.TEXT_ALIGN_CENTER
        })

        airui.button({
            parent = device_list_main_container,
            x = W / 2 + 70, y = yPos, w = 80, h = 30,
            text = '下一页',
            font_size = 13,
            text_color = (device_list_page < totalPages) and 0xFFFFFF or 0x888888,
            bg_color = (device_list_page < totalPages) and 0x666666 or 0xCCCCCC,
            radius = 4,
            on_click = function()
                if device_list_page < totalPages then
                    device_list_page = device_list_page + 1
                    update_device_list_ui()
                end
            end
        })
    end
end

local function handle_message(topic, payload)
    -- log.info('handle_message', '收到消息', 'topic:', topic, 'payload:', payload)
    if not game_state_mqtt.is_running then return end
    local success, data = pcall(json.decode, payload)
    if not success or not data then 
        log.info('handle_message', 'ERROR: 解析json失败')
        return 
    end

    if data.type == 'connect_request' and data.device_id then
        if game_state_mqtt.peer_connected then
            if game_state_mqtt.mqtt_client then
                local resp = { type = 'connect_reject', device_id = my_device_id, reason = 'in_battle' }
                local ok, json_str = pcall(json.encode, resp)
                if ok then
                    game_state_mqtt.mqtt_client:publish(TOPIC_DATA .. data.device_id, json_str, MQTT_QOS)
                end
            end
            return
        end
        -- 关闭排行榜、帮助弹窗和设备列表窗口，让邀请弹窗显示在最前面
        close_device_list_win()
        if leaderboardWinId then
            exwin.close(leaderboardWinId)
            leaderboardWinId = nil
        end
        if infoWinId then
            exwin.close(infoWinId)
            infoWinId = nil
        end
        local nickname = data.nickname or data.device_id:sub(#data.device_id - 5)
        -- 保存对方机型（被邀请方收到邀请时就知道对方机型了）
        if data.model then
            game_state_mqtt.peer_device_model = data.model
        end
        show_invite_dialog(nickname, data.device_id)
        return
    elseif data.type == 'connect_accept' and data.device_id then
        -- 如果邀请已取消，忽略对方的同意
        if not inviteTargetDeviceId then
            log.info('邀请已取消，忽略对方的同意')
            return
        end
        close_invite_waiting()
        local nickname = data.nickname or data.device_id:sub(#data.device_id - 5)
        -- 保存对方机型，在 start_game_connect 中会显示
        if data.model then
            game_state_mqtt.peer_device_model = data.model
        end
        show_toast(nickname .. ' 已接受邀请')
        close_device_list_win()
        start_game_connect(data.device_id)
        return
    elseif data.type == 'connect_reject' and data.device_id then
        close_invite_waiting()
        if data.reason == 'in_battle' then
            show_toast('对方正在对战中')
        else
            show_toast('对方拒绝了邀请')
        end
        isConnecting = false
        return
    elseif data.type == 'connect_cancel' and data.device_id then
        -- 对方取消了邀请，关闭邀请弹窗
        close_invite_dialog()
        -- 清除机型信息（被邀请方收到邀请时保存了机型）
        game_state_mqtt.peer_device_model = nil
        update_score_display()
        show_toast('对方取消了邀请')
        return
    end
    
    if data.type == 'presence' and data.device_id ~= my_device_id then
        if game_state_mqtt.peer_connected and data.device_id == game_state_mqtt.peer_device_id then
            return
        end
        if data.is_connected then
            if game_state_mqtt.online_devices[data.device_id] then
                game_state_mqtt.online_devices[data.device_id] = nil
                if device_list_main_container then
                    update_device_list_ui()
                end
            end
            return
        end
        local is_new_device = (game_state_mqtt.online_devices[data.device_id] == nil)
        game_state_mqtt.online_devices[data.device_id] = { last_seen = os.time(), nickname = data.nickname, is_connected = data.is_connected or false }
        if is_new_device and device_list_main_container then
            update_device_list_ui()
        end
    elseif data.type == 'ready' and data.device_id then
        -- 收到 ready 消息，如果还没连接，自动建立连接
        if not game_state_mqtt.peer_connected then
            log.info('handle_message', 
                '收到ready自动连接', 
                '对方设备ID:', data.device_id:sub(1, 10),
                '我的设备ID:', my_device_id:sub(1, 10),
                '我是服务器:', my_device_id < data.device_id)
            -- 关闭排行榜和帮助弹窗（如果开着）
            if leaderboardWinId then
                exwin.close(leaderboardWinId)
                leaderboardWinId = nil
            end
            if infoWinId then
                exwin.close(infoWinId)
                infoWinId = nil
            end
            game_state_mqtt.peer_device_id = data.device_id
            game_state_mqtt.peer_connected = true
            game_state_mqtt.is_server = my_device_id < data.device_id
            gameState = STATE.WAITING
            
            -- 初始化玩家位置和颜色
            if game_state_mqtt.is_server then
                player1:reset(80, GROUND_Y)
                player2:reset(240, GROUND_Y)
                player1.facingRight = true
                player2.facingRight = false
                player1.name = '红方'
                player2.name = '蓝方'
                player1:setColor(0xff4455)
                player2:setColor(0x4499ff)
                if hp1Bar then hp1Bar:set_indicator_color(0xff4455) end
                if hp2Bar then hp2Bar:set_indicator_color(0x4499ff) end
                if hp1Label then hp1Label:set_text('红方') end
                if hp2Label then hp2Label:set_text('蓝方') end
                log.info('角色分配', '我是服务器：player1=红方, player2=蓝方')
            else
                player1:reset(240, GROUND_Y)
                player2:reset(80, GROUND_Y)
                player1.facingRight = false
                player2.facingRight = true
                player1.name = '蓝方'
                player2.name = '红方'
                player1:setColor(0x4499ff)
                player2:setColor(0xff4455)
                -- 客户端血条位置和颜色保持不变：左红方，右蓝方
                if hp1Bar then hp1Bar:set_indicator_color(0xff4455) end
                if hp2Bar then hp2Bar:set_indicator_color(0x4499ff) end
                log.info('角色分配', '我是客户端：player1=蓝方, player2=红方')
                if hp1Label then hp1Label:set_text('红方') end
                if hp2Label then hp2Label:set_text('蓝方') end
            end
            
            player1:show()
            player2:show()
            
            -- 关闭设备列表窗口
            close_device_list_win()
        end
        
        if game_state_mqtt.peer_connected then
            log.info('handle_message', '收到对手准备信号')
            game_state_mqtt.peer_ready = true
            if statusLabel then
                statusLabel:set_text('对手已准备！')
            end
            -- 收到 ready 后，回发一个自己的 ready，确保双方都能同步
            if not game_state_mqtt.i_am_ready then
                game_state_mqtt.i_am_ready = true
                send_ready()
            end
            check_both_ready()
        end
    elseif data.type == 'device_info' and data.model then
        -- 收到对方的设备型号，更新本地记录
        game_state_mqtt.peer_device_model = data.model
        log.info('handle_message', '收到对方机型:', game_state_mqtt.peer_device_model)
        update_score_display()   -- 立即刷新显示
    elseif data.type == 'start_game' and game_state_mqtt.peer_connected then
        -- 兼容旧版本，直接开始倒计时
        game_state_mqtt.peer_ready = true
        -- 收到 start_game 也回发 ready，确保双方同步
        if not game_state_mqtt.i_am_ready then
            game_state_mqtt.i_am_ready = true
            send_ready()
        end
        check_both_ready()
    elseif data.type == 'input' and game_state_mqtt.peer_connected then
        -- 收到对方的输入消息，本地执行相应动作
        -- log.info('收到输入', 
            -- '发送方设备:', (data.from_device or 'unknown'):sub(1, 10),
            -- '动作:', data.input, 
            -- '持续时间:', data.duration, 'ms', 
            -- '位置:', string.format("%.1f,%.1f", data.x or 0, data.y or 0),
            -- '本地玩家名:', player1.name, 
            -- '对方玩家名:', player2.name)
        
        -- 强制校准位置，确保动作从正确位置开始
        if data.x then player2.x = data.x end
        if data.y then player2.y = data.y end
        
        -- 重置 prev 状态，确保下一次 update 能触发动作
        player2.prevJump = false
        player2.prevPunch = false
        player2.prevKick = false
        
        -- 根据输入类型执行动作
        if data.input == 'jump' then
            -- 1. 先强制校准到起跳位置
            if data.x then player2.x = data.x end
            if data.y then player2.y = data.y end
            
            -- 2. 强制重置跳跃状态（不管之前什么状态，都重新开始）
            player2.isJumping = false
            player2.jumpVelocity = 0
            
            -- 3. 直接开始跳跃（设置速度+状态，和对方完全一致）
            player2.jumpVelocity = -350
            player2.isJumping = true
            player2:setState('jump')
            
            -- 4. 重置input，防止update里重复触发
            player2.inputJump = false
            
            log.info('跳跃同步', '强制同步成功', 
                '起跳位置:', string.format("x=%.1f, y=%.1f", player2.x, player2.y),
                '初速度:', player2.jumpVelocity,
                'isJumping:', player2.isJumping)
            -- 不需要timer重置，整个动作由本地update自然完成
            
        elseif data.input == 'punch' then
            -- 直接触发出拳
            if player2.attackCooldown <= 0 and not player2.isJumping and player2:canAct() then
                player2.inputPunch = true
                player2:startPunch()  -- 直接调用
                log.info('出拳同步', '触发成功')
            end
            sys.timerStart(function() player2.inputPunch = false end, data.duration)
            
        elseif data.input == 'kick' then
            -- 直接触发出脚
            if player2.attackCooldown <= 0 and not player2.isJumping and player2:canAct() then
                player2.inputKick = true
                player2:startKick()  -- 直接调用
                log.info('出脚同步', '触发成功')
            end
            sys.timerStart(function() player2.inputKick = false end, data.duration)
            
        elseif data.input == 'block' then
            -- 直接触发防御（关键修复：player2的update跳过了本地输入判断，所以这里要手动设置状态）
            player2.inputBlock = true
            if player2.state ~= 'block' and player2.state ~= 'punch' and player2.state ~= 'kick' and not player2.isJumping then
                player2:setState('block')
            end
            log.info('防御同步', '触发成功')
            sys.timerStart(function() 
                player2.inputBlock = false
                if player2.state == 'block' then
                    player2:setState('idle')
                end
            end, data.duration)
            
        elseif data.input == 'left' then
            -- 完美左移同步：平滑移动到目标位置
            -- 1. 设置目标位置（最终位置）
            if data.x then player2.targetX = data.x end
            if data.y then player2.targetY = data.y end
            
            -- 2. 设置朝向
            player2.facingRight = false
            
            -- 3. 播放walk动画（视觉效果）
            if player2.state == 'idle' then
                player2:setState('walk')
            end
            
            -- 4. 200ms后停止动画（和移动时间一致）
            sys.timerStart(function() 
                if player2.state == 'walk' then
                    player2:setState('idle')
                end
                -- 确保最后对齐到目标位置
                if player2.targetX ~= nil then
                    player2.x = player2.targetX
                    player2.targetX = nil
                end
                if player2.targetY ~= nil then
                    player2.y = player2.targetY
                    player2.targetY = nil
                end
            end, data.duration or 200)
            
            log.info('左移同步', '平滑移动开始', 
                '目标位置:', string.format("%.1f", data.x or 0))
            
        elseif data.input == 'right' then
            -- 完美右移同步：平滑移动到目标位置
            -- 1. 设置目标位置（最终位置）
            if data.x then player2.targetX = data.x end
            if data.y then player2.targetY = data.y end
            
            -- 2. 设置朝向
            player2.facingRight = true
            
            -- 3. 播放walk动画（视觉效果）
            if player2.state == 'idle' then
                player2:setState('walk')
            end
            
            -- 4. 200ms后停止动画（和移动时间一致）
            sys.timerStart(function() 
                if player2.state == 'walk' then
                    player2:setState('idle')
                end
                -- 确保最后对齐到目标位置
                if player2.targetX ~= nil then
                    player2.x = player2.targetX
                    player2.targetX = nil
                end
                if player2.targetY ~= nil then
                    player2.y = player2.targetY
                    player2.targetY = nil
                end
            end, data.duration or 200)
            
            log.info('右移同步', '平滑移动开始', 
                '目标位置:', string.format("%.1f", data.x or 0))
            
        elseif data.input == 'left_pos' or data.input == 'left_end' or data.input == 'right_pos' or data.input == 'right_end' then
            -- 兼容旧校准消息：只更新位置，不重置input（做备用校准）
            if data.input:find('left') then
                player2.facingRight = false
            else
                player2.facingRight = true
            end
            if data.x then player2.x = data.x end
            if data.y then player2.y = data.y end
            log.info('移动校准', data.input, '校准位置:', string.format("%.1f", player2.x))
        end
        
    elseif data.type == 'state' and game_state_mqtt.peer_connected then
        -- 兼容旧版本：状态消息
        log.info('收到状态', '状态:', data.state, 'isJumping:', player2.isJumping)
        
        -- 关键修复：跳跃中时不要用状态消息覆盖y坐标，否则会打断跳跃物理计算！
        player2.x = data.x or player2.x
        if not player2.isJumping then
            player2.y = data.y or player2.y
        end
        
        -- 更新状态（关键优化：walk状态下不立即切换回idle，让甩臂动画播放完！）
        local newState = data.state or player2.state
        if newState == 'idle' and player2.state == 'walk' then
            -- 正在走路，延迟一小段时间再变回idle，让甩臂动画播放完
            sys.timerStart(function()
                if player2.state == 'walk' then
                    player2:setState('idle')
                end
            end, 150)
        elseif newState ~= player2.state then
            player2:setState(newState)
        end
        
        player2.stateTimer = data.stateTimer or player2.stateTimer
        player2.facingRight = (data.facingRight ~= nil) and data.facingRight or player2.facingRight
        player2.bodyOffsetX = data.bodyOffsetX or player2.bodyOffsetX
        player2.bodyOffsetY = data.bodyOffsetY or player2.bodyOffsetY
        player2.inputBlock = data.inputBlock or false
        
        if game_state_mqtt.is_server then
            -- 服务器：不覆盖血量
        else
            -- 客户端：接受血量
            if data.hp then
                player2.hp = data.hp
            end
            -- 清除对手本地输入
            player2.inputLeft = false
            player2.inputRight = false
            player2.inputJump = false
            player2.inputPunch = false
            player2.inputKick = false
        end
        
    elseif data.type == 'ready' and game_state_mqtt.peer_connected then
        log.info('handle_message', '收到对手准备信号')
        game_state_mqtt.peer_ready = true
        if statusLabel then
            statusLabel:set_text('对手已准备！')
        end
        -- 收到 ready 后，回发一个自己的 ready，确保双方都能同步
        if not game_state_mqtt.i_am_ready then
            game_state_mqtt.i_am_ready = true
            send_ready()
        end
        check_both_ready()
    elseif data.type == 'restart' and game_state_mqtt.peer_connected then
        log.info('handle_message', '收到对手重新开始信号')
        if gameState == STATE.KO or gameState == STATE.WAITING then
            resetGame(true)
        end
    elseif data.type == 'opponent_left' and game_state_mqtt.peer_connected then
        log.info('handle_message', '对手退出游戏')
        game_state_mqtt.peer_connected = false
        if gameState ~= STATE.MENU then
            upload_score()
            show_toast('对方已退出游戏')
            sys.timerStart(reset_to_menu, 1500)
        end
    elseif data.type == 'start_game' and game_state_mqtt.peer_connected then
        -- 兼容旧版本，直接开始倒计时
        game_state_mqtt.peer_ready = true
        -- 收到 start_game 也回发 ready，确保双方同步
        if not game_state_mqtt.i_am_ready then
            game_state_mqtt.i_am_ready = true
            send_ready()
        end
        check_both_ready()
    elseif data.type == 'ko' and game_state_mqtt.peer_connected then
        -- 客户端收到KO消息
        if gameState == STATE.FIGHTING then
            gameState = STATE.KO
            koTimer = 0
            
            -- 根据winner_name判断谁获胜
            if data.winner_name == player1.name then
                koWinner = player1
                player2:setState('knockdown')
                spawnHitParticles(player2.x, player2:getHeadCenterY(), 20)
            else
                koWinner = player2
                player1:setState('knockdown')
                spawnHitParticles(player1.x, player1:getHeadCenterY(), 20)
            end
            
            -- 显示KO界面
            if koContainer then koContainer:open() end
            if winnerContainer then
                winnerLabel:set_text(data.winner_name .. ' 获胜!')
                winnerContainer:open()
            end
            if restartContainer then restartContainer:open() end
            
            shakeAmount = 12
            
            -- 客户端KO时也上传积分
            upload_score()
            
            log.info('handle_message', '收到KO消息，获胜者:', data.winner_name)
        end
    elseif data.type == 'hp_sync' then
        if not game_state_mqtt.is_server then
            -- 客户端：服务端 hp1=红方，hp2=蓝方
            -- 客户端 player1=蓝方(自己)，player2=红方(对手)
            player1.hp = data.hp2   -- 自己的血量 = 服务端蓝方血量
            player2.hp = data.hp1   -- 对手的血量 = 服务端红方血量
        end
    elseif data.type == 'ack' then
        -- 收到 ack 消息，计算往返延迟
        local now = getTimestamp()
        if data.originalSendTime then
            local roundTrip = now - data.originalSendTime
            local oneWay = roundTrip / 2
            log.info('往返延迟', 
                '原始发送:', string.format("%.0fms", data.originalSendTime),
                -- '对方回发:', string.format("%.0fms", data.ackSendTime),
                -- '收到时间:', string.format("%.0fms", now),
                '总耗时:', string.format("%.0fms", roundTrip),
                '单程延迟≈:', string.format("%.0fms", oneWay))
        end
    end
end

local function mqtt_client_event_cbfunc(mqtt_client, event, data, payload, metas)
    if not game_state_mqtt.is_running then return end

    -- log.info("mqtt_client_event_cbfunc", event, data)
    
    if event == 'conack' then
        sys.sendMsg(TASK_NAME, 'MQTT_EVENT', 'CONNECT', true)
        mqtt_client:subscribe(TOPIC_PRESENCE, MQTT_QOS)
        mqtt_client:subscribe(TOPIC_DATA .. my_device_id, MQTT_QOS)
    elseif event == 'suback' then
        sys.sendMsg(TASK_NAME, 'MQTT_EVENT', 'SUBSCRIBE', true)
        game_state_mqtt.mqtt_ready = true
        if statusLabel then
            statusLabel:set_text('MQTT已连接！')
        end
        sys.taskInit(function()
            sys.wait(1000)
            if game_state_mqtt.is_running and game_state_mqtt.mqtt_ready then
                send_presence()
            end
        end)
        sys.taskInit(function()
            while game_state_mqtt.is_running do
                sys.wait(10000)
                if game_state_mqtt.is_running and game_state_mqtt.mqtt_ready and not game_state_mqtt.peer_connected then
                    send_presence()
                end
            end
        end)
    elseif event == 'recv' then
        -- log.info('mqtt_client_event_cbfunc', '收到消息:', data, payload)
        -- 处理消息
        handle_message(data, payload)
    elseif event == 'disconnect' then
        if gameState ~= STATE.MENU then
            sys.timerStart(function()
                show_toast('连接已断开')
                reset_to_menu()
            end, 100)
        end
        sys.sendMsg(TASK_NAME, 'MQTT_EVENT', 'DISCONNECTED', false)
    elseif event == 'error' then
        if gameState ~= STATE.MENU then
            sys.timerStart(function()
                show_toast('连接异常')
                reset_to_menu()
            end, 100)
        end
        sys.sendMsg(TASK_NAME, 'MQTT_EVENT', 'ERROR')
    end
end

local function mqtt_client_main_task_func()
    while game_state_mqtt.is_running do
        -- 等待网络就绪
        while game_state_mqtt.is_running and not socket.adapter(socket.dft()) do
            if statusLabel then
                statusLabel:set_text('等待网络...')
            end
            sys.waitUntil('IP_READY', 1000)
        end
        if not game_state_mqtt.is_running then break end
        
        if statusLabel then
            statusLabel:set_text('连接MQTT...')
        end
        sys.cleanMsg(TASK_NAME)
        
        local mqtt_client = mqtt.create(nil, MQTT_SERVER, MQTT_PORT)
        if mqtt_client then
            local success = true
            
            if not mqtt_client:auth(TASK_NAME .. my_device_id, '', '', true) then
                success = false
            end
            
            if success then
                mqtt_client:on(mqtt_client_event_cbfunc)
                mqtt_client:keepalive(60)
                
                if mqtt_client:connect() then
                    game_state_mqtt.mqtt_client = mqtt_client
                    
                    -- 主消息循环
                    while game_state_mqtt.is_running do
                        local msg = sys.waitMsg(TASK_NAME, 'MQTT_EVENT')
                        if not msg then
                            break
                        end
                        if msg[2] == 'CONNECT' then
                            if not msg[3] then
                                break
                            end
                        elseif msg[2] == 'SUBSCRIBE' then
                            if not msg[3] then
                                mqtt_client:disconnect()
                                sys.wait(1000)
                                break
                            end
                        elseif msg[2] == 'DISCONNECTED' then
                            break
                        elseif msg[2] == 'ERROR' then
                            break
                        end
                    end
                else
                    success = false
                end
            end
            
            -- 关闭连接
            game_state_mqtt.mqtt_ready = false
            mqtt_client:close()
            game_state_mqtt.mqtt_client = nil
        end
        
        if game_state_mqtt.is_running then
            sys.wait(3000)
        end
    end
end

local function open_device_list_win()
    log.info('open_device_list_win', 'device_list_win_id:', device_list_win_id)
    if device_list_win_id then 
        log.info('open_device_list_win', 'window already exists')
        return 
    end
    
    device_list_win_id = exwin.open({
        on_create = function()
            log.info('open_device_list_win', 'on_create called')
            device_list_main_container = airui.container({
                parent = airui.screen,
                x = 0,
                y = 0,
                w = W,
                h = H,
                color = 0xffffff
            })
            airui.label({
                parent = device_list_main_container,
                x = 0,
                y = 12,
                w = W,
                h = 36,
                text = '选择对手',
                font_size = 22,
                color = 0x333333,
                align = airui.TEXT_ALIGN_CENTER
            })
            log.info('open_device_list_win', 'refresh button pos: W/2-180, 435, size: 160, 40')
            airui.button({
                parent = device_list_main_container,
                x = W / 2 - 180,
                y = 435,
                w = 160,
                h = 40,
                text = '刷新',
                font_size = 16,
                text_color = 0xffffff,
                bg_color = 0x9932cc,
                radius = 6,
                on_click = function()
                    log.info('刷新按钮被点击')
                    send_presence()
                    update_device_list_ui()
                end
            })
            log.info('open_device_list_win', 'close button pos: W/2+20, 435, size: 160, 40')
            airui.button({
                parent = device_list_main_container,
                x = W / 2 + 20,
                y = 435,
                w = 160,
                h = 40,
                text = '关闭',
                font_size = 16,
                text_color = 0xffffff,
                bg_color = 0xcc0000,
                radius = 6,
                on_click = function()
                    log.info('关闭按钮被点击')
                    close_device_list_win()
                end
            })
            update_device_list_ui()
        end,
        on_destroy = function()
            log.info('open_device_list_win', 'on_destroy called, isConnecting:', isConnecting)
            -- 先清理UI元素
            for _, item in ipairs(device_list_popup_items) do
                if item then
                    item:destroy()
                end
            end
            device_list_popup_items = {}
            if device_list_main_container then
                log.info('open_device_list_win', 'destroying device_list_main_container')
                device_list_main_container:destroy()
                device_list_main_container = nil
            else
                log.info('open_device_list_win', 'device_list_main_container already nil')
            end
            -- 最后再清空窗口ID
            device_list_win_id = nil
            log.info('open_device_list_win', 'device_list_win_id set to nil')
            
            -- 根据游戏状态决定是否恢复菜单
            if gameState == STATE.WAITING or gameState == STATE.FIGHTING or gameState == STATE.KO then
                log.info('open_device_list_win', 'in battle, don\'t restore menu')
            else
                log.info('open_device_list_win', 'restore menu')
                gameState = STATE.MENU
                set_container_visible(menuContainer, true)
            end
            isConnecting = false
        end
    })
    log.info('open_device_list_win', 'window opened, id:', device_list_win_id)
end

local function create_ui()
    
    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = W,
        h = H,
        color = 0x0a0a14
    })

    local bgContainer = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = W,
        h = GROUND_Y,
        color = 0x1a2a4a
    })

    local groundContainer = airui.container({
        parent = main_container,
        x = 0,
        y = GROUND_Y,
        w = W,
        h = H - GROUND_Y,
        color = 0x3d4050
    })

    hp1Bar = airui.bar({
        parent = main_container,
        x = 50,
        y = 22,
        w = 280,
        h = 18,
        min = 0,
        max = 100,
        value = 100,
        radius = 3,
        bg_color = 0x1a1a2e,
        indicator_color = 0xff4455
    })
    hp1Text = airui.label({
        parent = main_container,
        x = 50,
        y = 44,
        w = 100,
        h = 16,
        text = '100/100',
        font_size = 11,
        color = 0xdddddd
    })
    hp1Label = airui.label({
        parent = main_container,
        x = 50,
        y = 5,
        w = 80,
        h = 18,
        text = '红方',
        font_size = 13,
        color = 0xffffff
    })

    hp2Bar = airui.bar({
        parent = main_container,
        x = W - 330,
        y = 22,
        w = 280,
        h = 18,
        min = 0,
        max = 100,
        value = 100,
        radius = 3,
        bg_color = 0x1a1a2e,
        indicator_color = 0x4499ff
    })
    hp2Text = airui.label({
        parent = main_container,
        x = W - 150,
        y = 44,
        w = 100,
        h = 16,
        text = '100/100',
        font_size = 11,
        color = 0xdddddd,
        align = airui.TEXT_ALIGN_RIGHT
    })
    hp2Label = airui.label({
        parent = main_container,
        x = W - 130,
        y = 5,
        w = 80,
        h = 18,
        text = '蓝方',
        font_size = 13,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_RIGHT
    })

    vsText = airui.label({
        parent = main_container,
        x = 0,
        y = 12,
        w = W,
        h = 24,
        text = 'VS',
        font_size = 18,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })

    peerModelLabel = airui.label({
        parent = main_container,
        x = 0,
        y = 58,
        w = W,
        h = 18,
        text = '您是蓝方',
        font_size = 14,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })

    scoreLabel = airui.label({
        parent = main_container,
        x = 0,
        y = 78,
        w = W,
        h = 18,
        text = '本场积分: 0',
        font_size = 14,
        color = 0xffcc00,
        align = airui.TEXT_ALIGN_CENTER
    })

    countdownContainer = airui.container({
        parent = main_container,
        x = 0,
        y = 160,
        w = W,
        h = 100,
        opacity = 0
    })
    countdownLabel = airui.label({
        parent = countdownContainer,
        x = 0,
        y = 0,
        w = W,
        h = 100,
        text = '3',
        font_size = 72,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })
    set_container_visible(countdownContainer, false)

    koContainer = airui.container({
        parent = main_container,
        x = 0,
        y = 120,
        w = W,
        h = 70,
        opacity = 0,
        touchable = false
    })
    koLabel = airui.label({
        parent = koContainer,
        x = 0,
        y = 0,
        w = W,
        h = 70,
        text = 'K.O.!',
        font_size = 52,
        color = 0xff3333,
        align = airui.TEXT_ALIGN_CENTER
    })
    set_container_visible(koContainer, false)

    winnerContainer = airui.container({
        parent = main_container,
        x = 0,
        y = 195,
        w = W,
        h = 45,
        opacity = 0,
        touchable = false
    })
    winnerLabel = airui.label({
        parent = winnerContainer,
        x = 0,
        y = 0,
        w = W,
        h = 45,
        text = '',
        font_size = 22,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })
    set_container_visible(winnerContainer, false)

    restartContainer = airui.container({
        parent = main_container,
        x = 0,
        y = 245,
        w = W,
        h = 50,
        opacity = 0,
        touchable = false
    })
    -- KO 界面上的重启提示文字，改为一个可点击的按钮
    airui.button({
        parent = restartContainer,
        x = W / 2 - 120,
        y = 5,
        w = 240,
        h = 40,
        text = '点击重新开始',
        font_size = 16,
        text_color = 0xcccccc,
        bg_color = 0x333333,
        radius = 8,
        on_click = function()
            if koTimer > 1.5 then
                resetGame()
            end
        end
    })

    set_container_visible(restartContainer, false)

    player1 = StickFighter.new(200, GROUND_Y, true, 0xff4455, '红方', 0xff4455, main_container)
    player2 = StickFighter.new(600, GROUND_Y, false, 0x4499ff, '蓝方', 0x4499ff, main_container)

    -- 按钮放在独立容器里，确保在最上层不被遮挡
    local buttonLayer = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = W,
        h = H,
    })

    -- 菜单容器放在最后创建，确保在最上层
    menuContainer = airui.container({
        parent = main_container,
        x = 0,
        y = 110,
        w = W,
        h = 300
    })
    airui.label({
        parent = menuContainer,
        x = 0,
        y = 10,
        w = W,
        h = 50,
        text = '火柴人格斗',
        font_size = 28,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = menuContainer,
        x = 0,
        y = 65,
        w = W,
        h = 30,
        text = '联机版',
        font_size = 18,
        color = 0xff8844,
        align = airui.TEXT_ALIGN_CENTER
    })
    statusLabel = airui.label({
        parent = menuContainer,
        text = '正在连接MQTT...',
        x = 0,
        y = 100,
        w = W,
        h = 25,
        font_size = 12,
        color = 0xcccccc,
        align = airui.TEXT_ALIGN_CENTER
    })
    loginMenuStatus = airui.label({
        parent = menuContainer,
        text = "IOT: 检查中...",
        x = 0,
        y = 125,
        w = W,
        h = 20,
        font_size = 10,
        color = 0x888888,
        align = airui.TEXT_ALIGN_CENTER
    })
    myIdLabel = airui.label({
        parent = menuContainer,
        text = 'ID: ' .. my_device_id,
        x = 0,
        y = 145,
        w = W,
        h = 20,
        font_size = 10,
        color = 0x888888,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.button({
        parent = menuContainer,
        x = W / 2 - 270,
        y = 180,
        w = 130,
        h = 45,
        text = '查找对手',
        font_size = 14,
        text_color = 0xffffff,
        bg_color = 0x228844,
        radius = 5,
        on_click = function()
            set_container_visible(menuContainer, false)
            open_device_list_win()
        end
    })

    airui.button({
        parent = menuContainer,
        x = W / 2 - 130,
        y = 180,
        w = 130,
        h = 45,
        text = '积分排行榜',
        font_size = 14,
        text_color = 0xffffff,
        bg_color = 0xff8800,
        radius = 5,
        on_click = function()
            open_leaderboard_win()
        end
    })

    airui.button({
        parent = menuContainer,
        x = W / 2 + 10,
        y = 180,
        w = 130,
        h = 45,
        text = '帮助',
        font_size = 14,
        text_color = 0xffffff,
        bg_color = 0x3366cc,
        radius = 5,
        on_click = function()
            open_info_win()
        end
    })

    -- 创建退出按钮，在帮助按钮右边（菜单状态）
    airui.button({
        parent = menuContainer,
        x = W / 2 + 150,
        y = 180,
        w = 100,
        h = 45,
        text = '退出',
        font_size = 14,
        text_color = 0xffffff,
        bg_color = 0x884444,
        radius = 5,
        on_click = function()
            log.info('退出按钮被点击')
            if gameState ~= STATE.MENU then
                send_opponent_left()
                reset_to_menu()
            else
                if win_id then
                    exwin.close(win_id)
                end
            end
        end
    })

    -- 创建退出按钮，在右按钮和拳按钮中间（战斗状态）
    airui.button({
        parent = main_container,
        x = 320,
        y = 410,
        w = 80,
        h = 40,
        text = '退出',
        font_size = 14,
        text_color = 0xffffff,
        bg_color = 0x884444,
        radius = 5,
        on_click = function()
            log.info('退出按钮被点击')
            if gameState ~= STATE.MENU then
                send_opponent_left()
                reset_to_menu()
            else
                if win_id then
                    exwin.close(win_id)
                end
            end
        end
    })

    inviteWaitingContainer = airui.container({
        parent = main_container,
        x = W / 2 - 150, y = 140, w = 300, h = 90,
        color = 0xFFFFFF,
        radius = 12,
        shadow = true
    })
    airui.label({
        parent = inviteWaitingContainer, x = 0, y = 15, w = 300, h = 28,
        text = '已发送对战邀请',
        font_size = 18, color = 0x333333,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.button({
        parent = inviteWaitingContainer,
        x = 90, y = 50, w = 120, h = 32,
        text = '取消邀请',
        font_size = 15, text_color = 0xFFFFFF, bg_color = 0xCC0000, radius = 6,
        on_click = function()
            if game_state_mqtt.mqtt_client and inviteTargetDeviceId then
                local data = { type = 'connect_cancel', device_id = my_device_id }
                local ok, json_str = pcall(json.encode, data)
                if ok then
                    game_state_mqtt.mqtt_client:publish(TOPIC_DATA .. inviteTargetDeviceId, json_str, MQTT_QOS)
                end
            end
            close_invite_waiting()
            isConnecting = false
            is_resetting = false
            reset_to_menu()
            if menuContainer then menuContainer:open() end
        end
    })
    set_container_visible(inviteWaitingContainer, false)

    local buttonConfigs = {
        { x = 80, y = 445, r = 26, label = '左', action = 'left' },
        { x = 170, y = 445, r = 26, label = '右', action = 'right' },
        { x = 125, y = 385, r = 24, label = '跳', action = 'jump' },
        { x = 550, y = 435, r = 24, label = '拳', action = 'punch' },
        { x = 640, y = 435, r = 24, label = '脚', action = 'kick' },
        { x = 730, y = 435, r = 24, label = '防', action = 'block' },
    }

    for _, btn in ipairs(buttonConfigs) do
        local isAction = btn.action == 'punch' or btn.action == 'kick' or btn.action == 'block'
        local isSpecial = btn.action == 'jump'
        local bgColor = 0x667788
        if isAction then bgColor = 0xd04040 end
        if isSpecial then bgColor = 0x3366aa end

        airui.button({
            parent = buttonLayer,
            x = btn.x - btn.r,
            y = btn.y - btn.r,
            w = btn.r * 2,
            h = btn.r * 2,
            text = btn.label,
            font_size = isAction and 16 or 13,
            text_color = 0xffffff,
            bg_color = bgColor,
            radius = btn.r,
            on_click = function()
                log.info('button_click', btn.action)
                if btn.action == 'jump' then
                    player1.inputJump = true
                    sys.timerStart(function() player1.inputJump = false end, 150)
                    send_input_message('jump', 150)
                elseif btn.action == 'punch' then
                    player1.inputPunch = true
                    sys.timerStart(function() player1.inputPunch = false end, 200)
                    send_input_message('punch', 200)
                elseif btn.action == 'kick' then
                    player1.inputKick = true
                    sys.timerStart(function() player1.inputKick = false end, 250)
                    send_input_message('kick', 250)
                elseif btn.action == 'block' then
                    -- 点击防御：胳膊竖起来，持续1.5秒后自动放下
                    player1.inputBlock = true
                    sys.timerStart(function() player1.inputBlock = false end, 1500)
                    send_input_message('block', 1500)
                elseif btn.action == 'left' then
                    player1.inputLeft = true
                    sys.timerStart(function() player1.inputLeft = false end, 200)
                    local minX = 20
                    local maxX = W - 20
                    local predictedX = math.max(minX, math.min(maxX, player1.x - 20))
                    send_input_message('left', 200, predictedX, player1.y)
                elseif btn.action == 'right' then
                    player1.inputRight = true
                    sys.timerStart(function() player1.inputRight = false end, 200)
                    local minX = 20
                    local maxX = W - 20
                    local predictedX = math.max(minX, math.min(maxX, player1.x + 20))
                    send_input_message('right', 200, predictedX, player1.y)
                end
            end
        })
    end

    gameState = STATE.MENU
    accumulatedDt = 0

    gameTimerId = sys.timerLoopStart(gameLoop, GAME_LOOP_INTERVAL)

    ---- 每分钟自动上传一次积分
    -- scoreUploadTimer = sys.timerLoopStart(upload_score, 60000)

    update_login_menu_status()

    game_state_mqtt.is_running = true
    sys.taskInitEx(mqtt_client_main_task_func, TASK_NAME)
end

local function on_open()
    create_ui()
end

local function on_close()
    send_opponent_left()
    game_state_mqtt.is_running = false
    if gameTimerId then
        sys.timerStop(gameTimerId)
        gameTimerId = nil
    end
    upload_score()
    if leaderboardWinId then
        exwin.close(leaderboardWinId)
        leaderboardWinId = nil
    end
    if loginWinId then
        exwin.close(loginWinId)
        loginWinId = nil
    end
    if player1 then player1:destroy() end
    if player2 then player2:destroy() end
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    if device_list_win_id then
        exwin.close(device_list_win_id)
        device_list_win_id = nil
    end
end

local function open_handler()
    win_id = exwin.open({
        on_create = on_open,
        on_destroy = on_close,
    })
end

sys.subscribe("OPEN_STICK_FIGHTER_ONLINE_WIN", open_handler)
sys.subscribe("DB_RESULT", on_leaderboard_db_result)

return {
    open = open_handler,
    close = on_close
}
