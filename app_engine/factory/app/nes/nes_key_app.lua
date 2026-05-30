--[[
@module  nes_key_app
@summary NES游戏按键模块 — 8方向计算 + 动作键连发 + 控制键快响应
@version 1.0
@date    2026.05.30
@author  江访

由 app_main 根据 project_config.features.nes 条件加载。
订阅 OPEN_WELCOME_WIN 事件（LCD初始化后触发），延迟注册GPIO中断。

按键类型（根据 key 名称自动分类）：
  - 方向键: NES_KEY_UP / NES_KEY_DOWN / NES_KEY_LEFT / NES_KEY_RIGHT
    → 发布 NES_KEY(key, pressed) 单键事件 + 计算组合方向发布 NES_DIR(direction) 事件
    → 支持8方向组合（同时按两个相邻方向键=对角线方向）
  - 动作键: NES_KEY_A / NES_KEY_B
    → 按下立即发布 NES_KEY(key, 1)，松开发布 NES_KEY(key, 0)
    → 按住不放：自动连发，60ms间隔交替按/松
  - 控制键: NES_KEY_RETURN / NES_KEY_START / NES_KEY_SELECT
    → 仅按下沿发布 NES_CTRL(key)，30ms软件防抖

发布事件：
  NES_KEY(key, pressed)    — key="UP"/"DOWN"/"LEFT"/"RIGHT"/"A"/"B", pressed=1按下/0释放
  NES_DIR(direction)       — 0=NONE, 1=UP, 2=UP_RIGHT, 3=RIGHT, 4=DOWN_RIGHT,
                                    5=DOWN, 6=DOWN_LEFT, 7=LEFT, 8=UP_LEFT
  NES_CTRL(key)            — key="RETURN"/"START"/"SELECT"，仅按下沿发布（带防抖）
]]

-- ==================== 配置常量 ====================

local HW_DEBOUNCE_MS = 20          -- GPIO硬件消抖(ms)
local CTRL_DEBOUNCE_MS = 30        -- 控制键软件防抖窗口(ms)，够快且防抖动

-- ticks 转毫秒：mcu.hz() 动态获取 tick 频率，兼容 Air1601/1602（20ms/tick）和 PC（1ms/tick）
local function ticks_to_ms(diff_ticks)
    local hz = mcu.hz() or 1
    if hz <= 0 then hz = 1 end
    return diff_ticks * 1000 / hz
end

-- ==================== 方向状态 ====================

-- 方向bitmask: bit0=UP, bit1=DOWN, bit2=LEFT, bit3=RIGHT
local dir_bits = 0
local prev_dir_code = 0

-- bitmask → 方向编码（顺时针）
local DIR_BITMASK_TO_CODE = {
    [0]  = 0,   -- NONE
    [1]  = 1,   -- UP         (0b0001)
    [2]  = 5,   -- DOWN       (0b0010)
    [4]  = 7,   -- LEFT       (0b0100)
    [8]  = 3,   -- RIGHT      (0b1000)
    [5]  = 8,   -- UP+LEFT    (0b0101)
    [9]  = 2,   -- UP+RIGHT   (0b1001)
    [6]  = 6,   -- DOWN+LEFT  (0b0110)
    [10] = 4,   -- DOWN+RIGHT (0b1010)
    [3]  = 0,   -- UP+DOWN    → 抵消为NONE
    [12] = 0,   -- LEFT+RIGHT → 抵消为NONE
}

-- 方向键短名 → bit位
local DIR_NAME_TO_BIT = {
    UP    = 1,   -- bit0
    DOWN  = 2,   -- bit1
    LEFT  = 4,   -- bit2
    RIGHT = 8,   -- bit3
}

-- ==================== 控制键状态 ====================

local ctrl_last_press = {}    -- key短名 → 上次按下时间戳(tick)

-- ==================== 工具函数 ====================

--- 从 NES_KEY_XXX 全名提取短名（如 "NES_KEY_UP" → "UP"）
local function short_name(key_name)
    return key_name:match("NES_KEY_(.+)$") or key_name
end

--- 按键类型分类
local function classify_key(key_name)
    if key_name:find("NES_KEY_UP") or key_name:find("NES_KEY_DOWN") or
       key_name:find("NES_KEY_LEFT") or key_name:find("NES_KEY_RIGHT") then
        return "direction"
    end
    if key_name:find("NES_KEY_A") or key_name:find("NES_KEY_B") then
        return "action"
    end
    if key_name:find("NES_KEY_RETURN") or key_name:find("NES_KEY_START") or
       key_name:find("NES_KEY_SELECT") then
        return "control"
    end
    return "unknown"
end

--- 计算并发布组合方向（仅当方向状态变化时）
local function publish_direction()
    local new_code = DIR_BITMASK_TO_CODE[dir_bits]
    if new_code == nil then new_code = 0 end
    if new_code ~= prev_dir_code then
        prev_dir_code = new_code
        log.info("nes_key", "DIR publish NES_DIR", new_code)
        sys.publish("NES_DIR", new_code)
    end
end

-- ==================== GPIO 回调工厂 ====================

--- 方向键回调：更新 bitmask，发布 NES_KEY + 计算 NES_DIR
local function create_direction_callback(sname)
    local bit = DIR_NAME_TO_BIT[sname]
    return function(val)
        local pressed = (val == 0)
        log.info("nes_key", "DIR GPIO", sname, pressed and "DOWN" or "UP", "bits before", dir_bits)
        if pressed then
            dir_bits = dir_bits | bit
        else
            dir_bits = dir_bits & ~bit
        end
        -- 单键事件（后装APP可选择性忽略，用NES_DIR替代）
        sys.publish("NES_KEY", sname, pressed and 1 or 0)
        -- 更新组合方向
        publish_direction()
        log.info("nes_key", "DIR publish NES_KEY", sname, pressed and 1 or 0, "dir_bits", dir_bits)
    end
end

--- 动作键回调：按下发1，松开发0，NES模拟器自行处理按住状态
local function create_action_callback(sname)
    return function(val)
        local pressed = (val == 0)
        log.info("nes_key", "ACT GPIO", sname, pressed and "DOWN" or "UP")
        sys.publish("NES_KEY", sname, pressed and 1 or 0)
    end
end

--- 控制键回调：仅按下沿 + 软件防抖（使用 ticks_to_ms 兼容不同 tick 频率）
local function create_control_callback(sname)
    return function(val)
        local pressed = (val == 0)
        if not pressed then return end  -- 控制键仅响应按下沿

        local now = mcu.ticks()
        local last = ctrl_last_press[sname] or 0
        if ticks_to_ms(now - last) >= CTRL_DEBOUNCE_MS then
            ctrl_last_press[sname] = now
            log.info("nes_key", "CTRL publish NES_CTRL", sname)
            sys.publish("NES_CTRL", sname)
        end
    end
end

-- ==================== 配置传递（兼容旧接口） ====================

sys.subscribe("NES_APP_BIND", function()
    local cfg = _G.NES_KEY_CONFIG
    if not cfg or type(cfg) ~= "table" or #cfg == 0 then
        local pc = _G.project_config
        if pc and pc.nes_keys and type(pc.nes_keys) == "table" then
            cfg = pc.nes_keys
        end
    end
    if cfg and type(cfg) == "table" and #cfg > 0 then
        log.info("nes_key_app", "send NES_KEY_CFG", #cfg, "keys")
        sys.publish("NES_KEY_CFG", cfg)
    end
end)

-- ==================== 主初始化（延迟到LCD就绪后） ====================

--- 注册所有 NES 按键 GPIO，可多次调用（幂等）
local function register_all_keys()
    local cfg = _G.project_config
    if not cfg or not cfg.nes_keys or type(cfg.nes_keys) ~= "table" then
        log.info("nes_key_app", "no nes_keys in config, skip")
        return
    end

    local count = 0
    for _, entry in ipairs(cfg.nes_keys) do
        local pin = entry.pin
        local key_name = entry.key
        local key_type = classify_key(key_name)
        local sname = short_name(key_name)

        if key_type == "unknown" then
            log.warn("nes_key_app", "unknown key type:", key_name, "-> GPIO", pin)
        end

        -- 硬件消抖
        gpio.debounce(pin, HW_DEBOUNCE_MS, 1)

        -- 根据类型创建对应的回调
        local callback
        if key_type == "direction" then
            callback = create_direction_callback(sname)
        elseif key_type == "action" then
            callback = create_action_callback(sname)
        elseif key_type == "control" then
            callback = create_control_callback(sname)
        else
            -- unknown类型：降级为简单双边沿发布
            callback = function(val)
                sys.publish("NES_KEY", sname, val == 0 and 1 or 0)
            end
        end

        gpio.setup(pin, callback, gpio.PULLUP, gpio.BOTH)

        count = count + 1
        log.info("nes_key_app", key_name, "(", key_type, ")", "-> GPIO", pin)
    end
    log.info("nes_key_app", "registered", count, "NES keys")
end

sys.subscribe("OPEN_WELCOME_WIN", function()
    register_all_keys()
end)

-- NES 游戏启动后 airui.nes 初始化可能覆盖 GPIO，收到通知后补注册
sys.subscribe("NES_GAME_STARTED", function()
    log.info("nes_key_app", "NES game started, re-register keys after 200ms")
    sys.timerStart(function()
        register_all_keys()
    end, 200)
end)
