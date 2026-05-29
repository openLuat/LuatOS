--[[
@module  nes_key_app
@summary NES游戏按键模块 v4.0 — 全部 airui 常量直发，零换算
@version 4.0
@date    2026.05.28

按键类型（根据 key 名称自动分类）：
  - 方向键: UP/DOWN/LEFT/RIGHT → 8方向计算 → NES_KEY(airui常量, 0/1)
  - 动作键: A/B → 200ms combo窗口 → NES_KEY(airui常量, 0/1)
  - 瞬发键: START/SELECT → 按下即发 press+80ms后auto release → NES_KEY(airui常量, 0/1)
  - 返回键: RETURN → 200ms防抖 → NES_CTRL("RETURN")

发布事件：
  NES_KEY(key_code, pressed)  — key_code=airui.NES_KEY_* 常量(number), pressed=0/1(number)
  NES_CTRL(key)                — key="RETURN"，仅返回键
  NES_COMBO(combo)             — combo="AB"
]]

-- ==================== 配置常量 ====================

local HW_DEBOUNCE_MS = 20
local CTRL_DEBOUNCE_MS = 200
local COMBO_WINDOW_MS = 200

-- ==================== 方向状态 ====================

local dir_up    = false
local dir_down  = false
local dir_left  = false
local dir_right = false
local dir_keys_sent = {}

--- 辅助：取 airui 常量并确保返回 number（严格类型检查）
local function airui_key(name)
    local v = airui["NES_KEY_" .. name]
    if v == nil then return nil end
    if type(v) == "number" then return v end
    if type(v) == "string" then
        local n = tonumber(v)
        if n then return n end
    end
    return nil  -- 无法识别，跳过
end

--- 发布 NES_KEY
local function pub_key(key_code, pressed)
    log.info("nes_key_app", "PUB NES_KEY", key_code, pressed)
    sys.publish("NES_KEY", key_code, pressed)
end

local function publish_direction_keys()
    local u, d, l, r = dir_up, dir_down, dir_left, dir_right
    local target = {}

    if u and r and not d and not l then
        target.UP = true; target.RIGHT = true
    elseif u and l and not d and not r then
        target.UP = true; target.LEFT = true
    elseif d and r and not u and not l then
        target.DOWN = true; target.RIGHT = true
    elseif d and l and not u and not r then
        target.DOWN = true; target.LEFT = true
    elseif u and not d and not l and not r then
        target.UP = true
    elseif d and not u and not l and not r then
        target.DOWN = true
    elseif l and not r and not u and not d then
        target.LEFT = true
    elseif r and not l and not u and not d then
        target.RIGHT = true
    end

    for k, _ in pairs(dir_keys_sent) do
        if not target[k] then
            local kc = airui_key(k)
            if kc then pub_key( kc, 0) end
        end
    end
    for k, _ in pairs(target) do
        if not dir_keys_sent[k] then
            local kc = airui_key(k)
            if kc then pub_key( kc, 1) end
        end
    end
    dir_keys_sent = target
end

-- ==================== 动作键(A/B)状态 ====================

local a_pressed = false
local b_pressed = false
local combo_active = false
local pending_action = nil
local pending_timer = nil

-- ==================== 控制键(仅RETURN)状态 ====================

local return_last = 0

local function now_ms()
    local ok, t = pcall(mcu.ticks)
    if ok and type(t) == "number" then return math.floor(math.abs(t)) end
    ok, t = pcall(rtos.tick)
    if ok and type(t) == "number" then return math.floor(math.abs(t)) end
    local ok2, clk = pcall(os.clock)
    if ok2 and type(clk) == "number" then return math.floor(math.abs(clk) * 1000) end
    return 0
end

-- ==================== 工具函数 ====================

local function short_name(key_name)
    return key_name:match("NES_KEY_(.+)$") or key_name
end

local function classify_key(key_name)
    if key_name:find("NES_KEY_UP") or key_name:find("NES_KEY_DOWN") or
       key_name:find("NES_KEY_LEFT") or key_name:find("NES_KEY_RIGHT") then
        return "direction"
    end
    if key_name:find("NES_KEY_A") or key_name:find("NES_KEY_B") then
        return "action"
    end
    if key_name:find("NES_KEY_START") or key_name:find("NES_KEY_SELECT") then
        return "momentary"
    end
    if key_name:find("NES_KEY_RETURN") then
        return "return_key"
    end
    return "unknown"
end

-- ==================== GPIO 回调工厂 ====================

local function create_direction_callback(sname)
    return function(val)
        local pressed = (val == 0)
        if sname == "UP" then dir_up = pressed
        elseif sname == "DOWN" then dir_down = pressed
        elseif sname == "LEFT" then dir_left = pressed
        elseif sname == "RIGHT" then dir_right = pressed
        end
        publish_direction_keys()
    end
end

local function create_action_callback(sname)
    local is_a = (sname == "A")
    local akey = airui_key(sname)
    local okey = airui_key(is_a and "B" or "A")
    return function(val)
        local pressed = (val == 0)
        if is_a then a_pressed = pressed else b_pressed = pressed end

        if pressed then
            if combo_active then return end
            local other_pressed = is_a and b_pressed or a_pressed
            if other_pressed then
                if pending_timer and pending_action then
                    sys.timerStop(pending_timer)
                    pending_timer = nil
                    pending_action = nil
                    combo_active = true
                    sys.publish("NES_COMBO", "AB")
                    return
                end
            end
            pending_action = sname
            if pending_timer then sys.timerStop(pending_timer) end
            pending_timer = sys.timerStart(function()
                if not combo_active and pending_action == sname then
                    if akey then pub_key( akey, 1) end
                end
                pending_timer = nil
                pending_action = nil
            end, COMBO_WINDOW_MS)
        else
            if combo_active then
                combo_active = false
                if akey then pub_key( akey, 0) end
                local other_held = is_a and b_pressed or a_pressed
                if other_held and okey then
                    pub_key( okey, 1)
                end
            else
                if pending_action == sname and pending_timer then
                    sys.timerStop(pending_timer)
                    pending_timer = nil
                    pending_action = nil
                    if akey then pub_key( akey, 1) end
                end
                if akey then pub_key( akey, 0) end
            end
        end
    end
end

local function create_momentary_callback(sname)
    local akey = airui_key(sname)
    return function(val)
        if val ~= 0 then return end
        if akey then
            pub_key( akey, 1)
            sys.timerStart(function()
                pub_key( akey, 0)
            end, 80)
        end
    end
end

local function create_return_callback()
    return function(val)
        if val ~= 0 then return end
        local now = now_ms()
        if now - return_last >= CTRL_DEBOUNCE_MS then
            return_last = now
            sys.publish("NES_CTRL", "RETURN")
        end
    end
end

-- ==================== 主初始化 ====================

sys.subscribe("OPEN_WELCOME_WIN", function()
    local cfg = _G.project_config
    if not cfg or not cfg.nes_keys or type(cfg.nes_keys) ~= "table" then
        log.info("nes_key_app", "no nes_keys, skip")
        return
    end

    log.info("nes_key_app", "airui UP=" .. tostring(airui["NES_KEY_UP"])
        .. " A=" .. tostring(airui["NES_KEY_A"]) .. " START=" .. tostring(airui["NES_KEY_START"]))

    local count = 0
    for _, entry in ipairs(cfg.nes_keys) do
        local pin = entry.pin
        local key_name = entry.key
        local key_type = classify_key(key_name)
        local sname = short_name(key_name)

        gpio.debounce(pin, HW_DEBOUNCE_MS, 1)

        local callback
        if key_type == "direction" then
            callback = create_direction_callback(sname)
        elseif key_type == "action" then
            callback = create_action_callback(sname)
        elseif key_type == "momentary" then
            callback = create_momentary_callback(sname)
        elseif key_type == "return_key" then
            callback = create_return_callback()
        else
            local kc = airui_key(key_name)
            callback = function(val)
                if kc then sys.publish("NES_KEY", kc, val == 0 and 1 or 0) end
            end
        end

        gpio.setup(pin, callback, gpio.PULLUP, gpio.BOTH)
        count = count + 1
    end
    log.info("nes_key_app", "registered " .. tostring(count) .. " NES keys")
end)