
--[[
@module  stick_fighter_online_win
@summary 双人联机火柴人格斗游戏窗口模块
@version 1.0.3
@date    2026.05.09
@author  王世豪
]]

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

local W, H = 320, 480
local GROUND_Y = 340

local gameState = STATE.MENU
local countdownTimer = 0
local countdownValue = 3
local koTimer = 0
local koWinner = nil
local shakeAmount = 0
local shakeDecay = 0.85
local lastSendTime = 0
local sendInterval = 50 -- ms, 发送间隔
local isConnecting = false -- 标记是否是因为连接而关闭窗口
local is_resetting = false

local MQTT_SERVER = "lbsmqtt.airm2m.com"
local MQTT_PORT = 1884
local MQTT_QOS = 0
local TASK_NAME = "stick_fighter_mqtt"

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

my_device_id = get_device_id()

local TOPIC_PRESENCE = "stick_fighter/presence"
local TOPIC_DATA = "stick_fighter/data/"

local game_state_mqtt = {
    online_devices = {},
    peer_connected = false,
    peer_ready = false,
    i_am_ready = false,
    peer_device_id = nil,
    mqtt_client = nil,
    mqtt_ready = false,
    is_running = false,
    is_server = false
}

local player1 = nil
local player2 = nil

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
    self.punchRange = 45
    self.punchActiveStart = 0.25
    self.punchActiveEnd = 0.55
    self.punchDuration = 0.35
    self.punchCooldown = 0.45

    self.kickDamage = 14
    self.kickRange = 55
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

    -- 容器使用固定尺寸
    self.bodyContainer = airui.container({
        parent = root,
        x = 0,
        y = 0,
        w = 320,
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
        local startX = self.x + self.bodyOffsetX + dir * 10
        local endX = self.x + self.bodyOffsetX + dir * self.kickRange
        return {
            left = math.min(startX, endX) - 15,
            right = math.max(startX, endX) + 15,
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
    -- 简化日志，避免打印太快
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
            -- 关键修复！！！先保存旧值，再检查条件！！！
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

    -- 正确的边界计算！
    local minX = 35
    local maxX = W - 35
    self.x = math.max(minX, math.min(maxX, self.x))

    -- 关键修复！！！最后再更新 prev 值！！！
    self.prevPunch = self.inputPunch
    self.prevKick = self.inputKick
    self.prevJump = self.inputJump
end

function StickFighter:setState(newState)
    if self.state == newState then return end
    self.state = newState
    self.stateTimer = 0
    self.currentAttackHit = false

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

    local breathe = (state == 'idle') and math.sin(self.animPhase * 0.8) * 2 or 0
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

    self.head:set_pos(math.floor(x - self.headRadius), math.floor(headCY))
    self.torso:set_pos(math.floor(x - 4), math.floor(shoulderY))

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

    self.leftLeg:set_pos(math.floor(backLegX - 2), math.floor(legMidY))
    self.rightLeg:set_pos(math.floor(flKneeX - 2), math.floor(flKneeY))

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

    self.leftArm:set_pos(math.floor(backShoulderX - 2 - fd * 8), math.floor(bElbowY))
    self.rightArm:set_pos(math.floor(frontShoulderX + fd * 8 - 2), math.floor(fElbowY))
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
            winner_is_server = true   -- 可选，让客户端知道谁赢了
        }
        local ok, json_str = pcall(json.encode, ko_data)
        if ok then
            game_state_mqtt.mqtt_client:publish(TOPIC_DATA .. game_state_mqtt.peer_device_id, json_str, MQTT_QOS)
            log.info('triggerKO', '广播KO消息')
        end
    end
end

local function checkAttackHit(attacker, defender)
    -- 只在攻击者正在攻击时才输出日志
    local should_log = (attacker.state == 'punch' or attacker.state == 'kick') and attacker:isAttackActive()
    
    if should_log then
        log.info('CHK', attacker.name, 'state:', attacker.state, 'active:', attacker:isAttackActive(), 'hit:', attacker.currentAttackHit)
    end
    
    if attacker.currentAttackHit then return end
    if not attacker:isAttackActive() then return end
    if defender.invincible > 0 then return end
    if defender.hp <= 0 then return end

    -- 客户端不执行扣血，只播放特效（可选）
    if not game_state_mqtt.is_server then
        -- 仍可检测并发送命中消息（此处略）
        return
    end

    local atkRect = attacker:getAttackRect()
    local defRect = defender:getBodyRect()

    if not atkRect.active then return end

    local overlapX = math.max(0, math.min(atkRect.right, defRect.right) - math.max(atkRect.left, defRect.left))
    local overlapY = math.max(0, math.min(atkRect.bottom, defRect.bottom) - math.max(atkRect.top, defRect.top))

    if should_log then
        log.info('CHK', 'atk:', atkRect.left, '-', atkRect.right, 'def:', defRect.left, '-', defRect.right, 'ovlp:', overlapX, overlapY)
    end

    if overlapX > 8 and overlapY > 5 then
        log.info('CHK', 'HIT!', attacker.name, '->', defender.name, 'damage:', (atkRect.type == 'kick' and attacker.kickDamage or attacker.punchDamage))
        attacker.currentAttackHit = true
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
        -- 只调整本地玩家(p1)的位置，不要调整远程玩家(p2)的位置！
        p1.x = p1.x - sign * overlap
    end
    -- 边界也使用正确的计算方式！
    local minX = 35
    local maxX = W - 35
    p1.x = math.max(minX, math.min(maxX, p1.x))
    -- 不要修改 p2 的位置！
end

-- local function send_my_state()
--     if not game_state_mqtt.peer_connected or not game_state_mqtt.mqtt_client then return end
--     local now = mcu and mcu.ticks and mcu.ticks() or 0
--     if now - lastSendTime < sendInterval then return end
--     lastSendTime = now
    
--     local data = {
--         type = 'state',
--         x = player1.x,
--         y = player1.y,
--         -- hp = player1.hp,
--         hp = game_state_mqtt.is_server and player1.hp or nil,
--         state = player1.state,
--         stateTimer = player1.stateTimer,
--         facingRight = player1.facingRight,
--         bodyOffsetX = player1.bodyOffsetX,
--         bodyOffsetY = player1.bodyOffsetY
--     }
--     -- 编码时过滤 nil
--     local filtered = {}
--     for k, v in pairs(data) do if v ~= nil then filtered[k] = v end end

--     local ok, json_str = pcall(json.encode, filtered)
--     if ok then
--         game_state_mqtt.mqtt_client:publish(TOPIC_DATA .. game_state_mqtt.peer_device_id, json_str, MQTT_QOS)
--     end
-- end

local function send_my_state(force)
    if not game_state_mqtt.peer_connected or not game_state_mqtt.mqtt_client then return end
    local now = mcu and mcu.ticks and mcu.ticks() or 0
    if not force and now - lastSendTime < sendInterval then return end
    lastSendTime = now

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
    }
    -- 过滤 nil 字段
    local filtered = {}
    for k, v in pairs(data) do
        if v ~= nil then filtered[k] = v end
    end
    local ok, json_str = pcall(json.encode, filtered)
    if ok then
        game_state_mqtt.mqtt_client:publish(TOPIC_DATA .. game_state_mqtt.peer_device_id, json_str, MQTT_QOS)
        -- 调试日志
        -- if data.hp then
            -- log.info('send_my_state', '发送血量:', data.hp)
        -- end
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

local function check_both_ready()
    if game_state_mqtt.i_am_ready and game_state_mqtt.peer_ready then
        log.info('check_both_ready', '双方都已准备，开始倒计时')
        startCountdown()
    end
end

local function send_start_game()
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

local function setPlayerInput(player, action, value)
    local p = player == 1 and player1 or player2
    if action == 'left' then
        p.inputLeft = value
    elseif action == 'right' then
        p.inputRight = value
    elseif action == 'jump' then
        p.inputJump = value
    elseif action == 'punch' then
        p.inputPunch = value
    elseif action == 'kick' then
        p.inputKick = value
    elseif action == 'block' then
        p.inputBlock = value
    end
end

local accumulatedDt = 0
local fixedDt = 1 / 60
local gameTimerId = nil

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

    -- 等待和倒计时状态下，只允许移动，不允许攻击
    if gameState == STATE.WAITING or gameState == STATE.COUNTDOWN then
        -- 等待状态显示提示
        if gameState == STATE.WAITING and statusLabel then
            if game_state_mqtt.peer_ready then
                statusLabel:set_text('对手已准备！')
            else
                statusLabel:set_text('等待对手准备...')
            end
        end
        player1:update(dt)
        -- 禁止攻击输入
        player1.inputPunch = false
        player1.inputKick = false
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
    -- player1:update(dt)
    -- player2:update(dt)
    
    -- 更新玩家状态
    player1:update(dt)
    if game_state_mqtt.is_server then
        player2:update(dt)   -- 服务器需要更新对手的物理
    end

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

    -- checkAttackHit(player1, player2)
    -- checkAttackHit(player2, player1)
end

local function updateUI()
    if hp1Bar then
        -- 左血条永远显示红方血量
        if game_state_mqtt.is_server then
            hp1Bar:set_value(player1.hp, false)
        else
            hp1Bar:set_value(player2.hp, false)
        end
    end
    if hp2Bar then
        -- 右血条永远显示蓝方血量
        if game_state_mqtt.is_server then
            hp2Bar:set_value(player2.hp, false)
        else
            hp2Bar:set_value(player1.hp, false)
        end
    end
    if hp1Text then
        -- 左HP文字显示红方，确保maxHp总是100
        if game_state_mqtt.is_server then
            hp1Text:set_text('HP: ' .. player1.hp .. ' / 100')
        else
            hp1Text:set_text('HP: ' .. player2.hp .. ' / 100')
        end
    end
    if hp2Text then
        -- 右HP文字显示蓝方，确保maxHp总是100
        if game_state_mqtt.is_server then
            hp2Text:set_text('HP: ' .. player2.hp .. ' / 100')
        else
            hp2Text:set_text('HP: ' .. player1.hp .. ' / 100')
        end
    end

    player1:draw(player2.x)
    player2:draw(player1.x)
end

local function gameLoop()
    local rawDt = 1 / 60
    accumulatedDt = accumulatedDt + rawDt
    local updates = 0
    while accumulatedDt >= fixedDt and updates < 5 do
        update(fixedDt)
        accumulatedDt = accumulatedDt - fixedDt
        updates = updates + 1
    end
    if updates == 0 and accumulatedDt > 0 then
        update(accumulatedDt)
        accumulatedDt = 0
    end
    updateUI()
    if gameState == STATE.FIGHTING then
        send_my_state()
    end
end


local function send_presence()
    if not game_state_mqtt.mqtt_ready then return end
    local data = {
        type = 'presence',
        device_id = my_device_id,
        is_server = game_state_mqtt.is_server
    }
    local ok, json_str = pcall(json.encode, data)
    if ok and game_state_mqtt.mqtt_client then
        game_state_mqtt.mqtt_client:publish(TOPIC_PRESENCE, json_str, MQTT_QOS)
    end
end

local function close_device_list_win()
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
    for _, item in ipairs(device_list_popup_items) do
        if item then item:destroy() end
    end
    device_list_popup_items = {}
    local count = 0
    for _ in pairs(game_state_mqtt.online_devices) do
        count = count + 1
    end
    local countLabel = airui.label({
        parent = device_list_main_container,
        text = '在线设备: ' .. count,
        x = 10,
        y = 80,
        w = 300,
        h = 25,
        font_size = 14,
        color = 0x0066cc,
        align = airui.TEXT_ALIGN_CENTER
    })
    table.insert(device_list_popup_items, countLabel)
    if count == 0 then
        local label = airui.label({
            parent = device_list_main_container,
            text = '暂无在线设备',
            x = 10,
            y = 110,
            w = 300,
            h = 30,
            font_size = 16,
            color = 0x888888,
            align = airui.TEXT_ALIGN_CENTER
        })
        table.insert(device_list_popup_items, label)
    else
        local yPos = 110
        for device_id, _ in pairs(game_state_mqtt.online_devices) do
            if device_id ~= my_device_id then
                local idLabel = airui.label({
                    parent = device_list_main_container,
                    text = device_id:sub(1, 20),
                    x = 10,
                    y = yPos,
                    w = 190,
                    h = 35,
                    font_size = 12,
                    color = 0x333333,
                    align = airui.TEXT_ALIGN_LEFT
                })
                table.insert(device_list_popup_items, idLabel)
                local btn = airui.button({
                    parent = device_list_main_container,
                    text = '连接',
                    x = 200,
                    y = yPos,
                    w = 100,
                    h = 35,
                    font_size = 14,
                    text_color = 0xffffff,
                    bg_color = 0x009933,
                    on_click = function()
                        log.info('连接按钮被点击，设备ID:', device_id)
                        game_state_mqtt.peer_device_id = device_id
                        game_state_mqtt.peer_connected = true
                        game_state_mqtt.is_server = my_device_id < device_id
                        
                        -- 重置准备状态
                        game_state_mqtt.i_am_ready = false
                        game_state_mqtt.peer_ready = false
                        
                        -- 设置等待状态
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
                            if hp1Label then hp1Label:set_text('红方') end
                            if hp2Label then hp2Label:set_text('蓝方') end
                        end
                        
                        -- 立即显示两个玩家
                        player1:show()
                        player2:show()
                        
                        if statusLabel then
                            statusLabel:set_text('等待对手准备...')
                        end
                        
                        -- 标记是因为连接而关闭窗口
                        isConnecting = true
                        
                        -- 关闭设备列表窗口（让on_destroy自然清理）
                        log.info('准备关闭设备列表窗口, device_list_win_id:', device_list_win_id)
                        close_device_list_win()
                        log.info('close_device_list_win已返回')
                        
                        -- 用定时器延迟发送ready，让窗口关完再说
                        sys.timerStart(function()
                            -- 发送自己准备好的信号
                            game_state_mqtt.i_am_ready = true
                            send_ready()
                            
                            -- 也发送 start_game 消息
                            send_start_game()
                            
                            -- 检查双方是否都准备好了
                            check_both_ready()
                        end, 200)
                    end
                })
                table.insert(device_list_popup_items, btn)
                yPos = yPos + 40
            end
        end
    end
end

local function handle_message(topic, payload)
    if not game_state_mqtt.is_running then return end
    local success, data = pcall(json.decode, payload)
    if not success or not data then return end
    
    if data.type == 'presence' and data.device_id ~= my_device_id then
        if not game_state_mqtt.online_devices[data.device_id] then
            game_state_mqtt.online_devices[data.device_id] = {}
        end
        update_device_list_ui()
    elseif data.type == 'ready' and data.device_id then
        -- 收到 ready 消息，如果还没连接，自动建立连接
        if not game_state_mqtt.peer_connected then
            log.info('handle_message', '收到ready自动连接:', data.device_id)
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
    elseif data.type == 'start_game' and game_state_mqtt.peer_connected then
        -- 兼容旧版本，直接开始倒计时
        game_state_mqtt.peer_ready = true
        -- 收到 start_game 也回发 ready，确保双方同步
        if not game_state_mqtt.i_am_ready then
            game_state_mqtt.i_am_ready = true
            send_ready()
        end
        check_both_ready()
    elseif data.type == 'state' and game_state_mqtt.peer_connected then
        -- player2.x = data.x or player2.x
        -- player2.y = data.y or player2.y
        -- player2.hp = data.hp or player2.hp
        -- player2.state = data.state or player2.state
        -- player2.stateTimer = data.stateTimer or player2.stateTimer
        -- player2.facingRight = data.facingRight ~= nil and data.facingRight or player2.facingRight
        -- player2.bodyOffsetX = data.bodyOffsetX or player2.bodyOffsetX
        -- player2.bodyOffsetY = data.bodyOffsetY or player2.bodyOffsetY
        if game_state_mqtt.is_server then
            -- 服务器：更新对手的运动数据，不覆盖血量
            player2.x = data.x or player2.x
            player2.y = data.y or player2.y
            -- 状态变化时调用 setState 重置 currentAttackHit，否则第二次攻击无法命中
            local newState = data.state or player2.state
            if newState ~= player2.state then
                player2:setState(newState)
            end
            player2.stateTimer = data.stateTimer or player2.stateTimer
            player2.facingRight = (data.facingRight ~= nil) and data.facingRight or player2.facingRight
            player2.bodyOffsetX = data.bodyOffsetX or player2.bodyOffsetX
            player2.bodyOffsetY = data.bodyOffsetY or player2.bodyOffsetY
            -- 服务器端：同步防御状态
            player2.inputBlock = data.inputBlock or false
        else
            -- 客户端：完全接受服务器数据（包括血量）
            player2.x = data.x or player2.x
            player2.y = data.y or player2.y
            if data.hp then
                player2.hp = data.hp
                -- log.info('handle_message', '收到对手血量:', data.hp)
            end
            player2.state = data.state or player2.state
            player2.stateTimer = data.stateTimer or player2.stateTimer
            player2.facingRight = (data.facingRight ~= nil) and data.facingRight or player2.facingRight
            player2.bodyOffsetX = data.bodyOffsetX or player2.bodyOffsetX
            player2.bodyOffsetY = data.bodyOffsetY or player2.bodyOffsetY
            -- 同步对方的防御状态，不要强制设为false
            player2.inputBlock = data.inputBlock or false
            -- 清除对手的其他本地输入，避免干扰
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
            
            log.info('handle_message', '收到KO消息，获胜者:', data.winner_name)
        end
    elseif data.type == 'hp_sync' then
        if not game_state_mqtt.is_server then
            -- 客户端：服务端 hp1=红方，hp2=蓝方
            -- 客户端 player1=蓝方(自己)，player2=红方(对手)
            player1.hp = data.hp2   -- 自己的血量 = 服务端蓝方血量
            player2.hp = data.hp1   -- 对手的血量 = 服务端红方血量
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
        handle_message(data, payload)
    elseif event == 'disconnect' then
        sys.sendMsg(TASK_NAME, 'MQTT_EVENT', 'DISCONNECTED', false)
    elseif event == 'error' then
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
                y = 20,
                w = 320,
                h = 40,
                text = '选择对手',
                font_size = 18,
                color = 0x333333,
                align = airui.TEXT_ALIGN_CENTER
            })
            log.info('open_device_list_win', 'refresh button pos: 10, 440, size: 140, 35')
            airui.button({
                parent = device_list_main_container,
                x = 10,
                y = 440,
                w = 140,
                h = 35,
                text = '刷新',
                font_size = 14,
                text_color = 0xffffff,
                bg_color = 0x9932cc,
                on_click = function()
                    log.info('刷新按钮被点击')
                    send_presence()
                    update_device_list_ui()
                end
            })
            log.info('open_device_list_win', 'close button pos: 170, 440, size: 140, 35')
            airui.button({
                parent = device_list_main_container,
                x = 170,
                y = 440,
                w = 140,
                h = 35,
                text = '关闭',
                font_size = 14,
                text_color = 0xffffff,
                bg_color = 0xcc0000,
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
            
            -- 根据标志决定是否恢复菜单
            if isConnecting then
                log.info('open_device_list_win', 'close for connection, don\'t restore menu')
                isConnecting = false
            else
                log.info('open_device_list_win', 'manual close, restore menu')
                gameState = STATE.MENU
                set_container_visible(menuContainer, true)
            end
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
        x = 10,
        y = 22,
        w = 120,
        h = 14,
        min = 0,
        max = 100,
        value = 100,
        radius = 3,
        bg_color = 0x1a1a2e,
        indicator_color = 0xff4455
    })
    hp1Text = airui.label({
        parent = main_container,
        x = 10,
        y = 42,
        w = 80,
        h = 14,
        text = '100/100',
        font_size = 10,
        color = 0xdddddd
    })
    hp1Label = airui.label({
        parent = main_container,
        x = 10,
        y = 8,
        text = '红方',
        font_size = 11,
        color = 0xffffff
    })

    hp2Bar = airui.bar({
        parent = main_container,
        x = 190,
        y = 22,
        w = 120,
        h = 14,
        min = 0,
        max = 100,
        value = 100,
        radius = 3,
        bg_color = 0x1a1a2e,
        indicator_color = 0x4499ff
    })
    hp2Text = airui.label({
        parent = main_container,
        x = 240,
        y = 42,
        w = 80,
        h = 14,
        text = '100/100',
        font_size = 10,
        color = 0xdddddd,
        align = airui.TEXT_ALIGN_RIGHT
    })
    hp2Label = airui.label({
        parent = main_container,
        x = 190,
        y = 8,
        text = '蓝方',
        font_size = 11,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_RIGHT
    })

    vsText = airui.label({
        parent = main_container,
        x = 140,
        y = 12,
        w = 40,
        h = 18,
        text = 'VS',
        font_size = 12,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })

    countdownContainer = airui.container({
        parent = main_container,
        x = 0,
        y = 180,
        w = 320,
        h = 80,
        opacity = 0
    })
    countdownLabel = airui.label({
        parent = countdownContainer,
        x = 0,
        y = 0,
        w = 320,
        h = 80,
        text = '3',
        font_size = 60,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })
    set_container_visible(countdownContainer, false)

    koContainer = airui.container({
        parent = main_container,
        x = 0,
        y = 140,
        w = 320,
        h = 60,
        opacity = 0
    })
    koLabel = airui.label({
        parent = koContainer,
        x = 0,
        y = 0,
        w = 320,
        h = 60,
        text = 'K.O.!',
        font_size = 40,
        color = 0xff3333,
        align = airui.TEXT_ALIGN_CENTER
    })
    set_container_visible(koContainer, false)

    winnerContainer = airui.container({
        parent = main_container,
        x = 0,
        y = 205,
        w = 320,
        h = 35,
        opacity = 0
    })
    winnerLabel = airui.label({
        parent = winnerContainer,
        x = 0,
        y = 0,
        w = 320,
        h = 35,
        text = '',
        font_size = 16,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })
    set_container_visible(winnerContainer, false)

    restartContainer = airui.container({
        parent = main_container,
        x = 0,
        y = 245,
        w = 320,
        h = 40,
        opacity = 0
    })
    -- KO 界面上的重启提示文字，改为一个可点击的按钮
    airui.button({
        parent = restartContainer,
        x = 60,
        y = 5,
        w = 200,
        h = 35,
        text = '点击重新开始',
        font_size = 12,
        text_color = 0xcccccc,
        bg_color = 0x333333,
        radius = 5,
        on_click = function()
            if koTimer > 1.5 then
                resetGame()
            end
        end
    })

    set_container_visible(restartContainer, false)

    player1 = StickFighter.new(80, GROUND_Y, true, 0xff4455, '红方', 0xff4455, main_container)
    player2 = StickFighter.new(240, GROUND_Y, false, 0x4499ff, '蓝方', 0x4499ff, main_container)

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
        y = 100,
        w = 320,
        h = 280
    })
    airui.label({
        parent = menuContainer,
        x = 0,
        y = 10,
        w = 320,
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
        w = 320,
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
        w = 320,
        h = 25,
        font_size = 12,
        color = 0xcccccc,
        align = airui.TEXT_ALIGN_CENTER
    })
    myIdLabel = airui.label({
        parent = menuContainer,
        text = 'ID: ' .. my_device_id,
        x = 0,
        y = 125,
        w = 320,
        h = 20,
        font_size = 10,
        color = 0x888888,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.button({
        parent = menuContainer,
        x = 60,
        y = 155,
        w = 200,
        h = 45,
        text = '查找对手',
        font_size = 18,
        text_color = 0xffffff,
        bg_color = 0x228844,
        radius = 5,
        on_click = function()
            set_container_visible(menuContainer, false)
            open_device_list_win()
        end
    })

    -- 创建退出按钮，放在"防"按钮上方，在最顶层
    airui.button({
        parent = main_container,
        x = 255,
        y = 365,
        w = 50,
        h = 28,
        text = '退出',
        font_size = 14,
        text_color = 0xffffff,
        bg_color = 0x884444,
        radius = 5,
        on_click = function()
            log.info('退出按钮被点击')
            if win_id then
                exwin.close(win_id)
            end
        end
    })

    local buttonConfigs = {
        { x = 30, y = 445, r = 22, label = '左', action = 'left' },
        { x = 90, y = 445, r = 22, label = '右', action = 'right' },
        { x = 60, y = 390, r = 20, label = '跳', action = 'jump' },
        { x = 160, y = 420, r = 18, label = '拳', action = 'punch' },
        { x = 220, y = 420, r = 18, label = '脚', action = 'kick' },
        { x = 280, y = 420, r = 18, label = '防', action = 'block' },
    }

    for _, btn in ipairs(buttonConfigs) do
        local isAction = btn.action == 'punch' or btn.action == 'kick'
        local isSpecial = btn.action == 'block' or btn.action == 'jump'
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
                elseif btn.action == 'punch' then
                    player1.inputPunch = true
                    sys.timerStart(function() player1.inputPunch = false end, 200)
                elseif btn.action == 'kick' then
                    player1.inputKick = true
                    sys.timerStart(function() player1.inputKick = false end, 250)
                elseif btn.action == 'block' then
                    -- 点击防御：胳膊竖起来，持续1.5秒后自动放下
                    player1.inputBlock = true
                    sys.timerStart(function() player1.inputBlock = false end, 1500)
                elseif btn.action == 'left' then
                    player1.inputLeft = true
                    sys.timerStart(function() player1.inputLeft = false end, 200)
                elseif btn.action == 'right' then
                    player1.inputRight = true
                    sys.timerStart(function() player1.inputRight = false end, 200)
                end
            end
        })
    end

    gameState = STATE.MENU
    accumulatedDt = 0

    gameTimerId = sys.timerLoopStart(gameLoop, 16)

    game_state_mqtt.is_running = true
    sys.taskInitEx(mqtt_client_main_task_func, TASK_NAME)
end

local function on_open()
    create_ui()
end

local function on_close()
    game_state_mqtt.is_running = false
    if gameTimerId then
        sys.timerStop(gameTimerId)
        gameTimerId = nil
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

return {
    open = open_handler,
    close = on_close
}
