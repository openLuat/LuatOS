--[[
@module exair153x_wdt
@summary Air153C/Air153D 外置硬件看门狗扩展库
@version 1.0
@date    2026.08.03
@author  马梦阳
@usage
硬件接线要求：
  GPIOx → NPN 三极管 → WTDOG
  GPIO 高电平 → NPN 导通 → WTDOG 低电平（空闲态）
  GPIO 低电平 → NPN 截止 → WTDOG 高电平（喂狗有效）

本文件的对外接口有 4 个：
1、exair153x_wdt.init(cfg)        - 初始化看门狗并启动自动喂狗任务
2、exair153x_wdt.feed()           - 手动执行单次喂狗
3、exair153x_wdt.trigger_reset()  - 触发强制硬件复位（3 次快速脉冲）
4、exair153x_wdt.version()        - 获取库版本信息

使用示例：
-- Air153C 基础用法（全默认）
-- WDT 与 RST 悬空，AGPIO24 → NPN → WTDOG
local exair153x_wdt = require("exair153x_wdt")
exair153x_wdt.init({ wdt_pin = 24 })

-- 手动喂狗（事件驱动，非 GPIO 直接操作）
exair153x_wdt.feed()

-- 触发强制硬件复位（3 次快速脉冲）
exair153x_wdt.trigger_reset()

-- 版本更新说明
-- 版本号：202609091030
-- 1、更新时间：2026-09-09 10:30
-- 2、更新内容
--    1）PIN_IDLE_LEVEL 由 1 改为 0（空闲电平从高电平改为低电平）
--    2）对应注释调整：GPIO 空闲电平/切回电平由"高电平"改为"低电平"
--    3）gpio.setup 增加 gpio.PULLUP 参数
--    4）_inner_feed 函数逻辑调整：增加脉冲前后 50ms 延迟和中间电平切换
--
-- 版本号：202608260000
-- 1、更新时间：2026-08-26 00:00
-- 2、更新内容
--    将 auto_feed_period_s 的最小限制从 150 秒改为 0（不能为负数）
--
-- 版本号：202608030000
-- 1、更新时间：2026-08-03 00:00
-- 2、更新内容
--    初始版本发布，提供 init(cfg)、feed()、trigger_reset()、version() 四个外部 API
--    支持 Air153C/Air153D 双芯片，Air153D 超时档位由硬件 STRAP 引脚配置，软件层不参与
]]

-- ==========================================================
-- 库参数（固定电平，与 NPN 三极管反相特性匹配）
-- ==========================================================

-- GPIO 空闲电平：低电平（NPN 截止，WTDOG 高电平）
local PIN_IDLE_LEVEL    = 0
-- 喂狗脉冲电平：低电平（NPN 截止，WTDOG 高电平，喂狗有效）
local PIN_ACTIVE_LEVEL  = 0

-- ==========================================================
-- 默认配置
-- ==========================================================

local PULSE_MS                  = 250   -- 喂狗脉冲固定宽度（ms），库内常量，用户不可配置
local DEFAULT_AUTO_FEED_PERIOD  = 180   -- 自动喂狗默认周期（s）
local MIN_AUTO_FEED_PERIOD      = 0     -- 自动喂狗最小周期（s）
local FEED_COOLDOWN_MS          = 1000  -- 手动喂狗防误触发最小间隔（ms）

-- 事件名：用于手动喂狗 / trigger_reset 唤醒主循环并重置计时
local EVENT_FEED_RESET = "EXAIR_WDT_FEED_RESET"

-- ==========================================================
-- 内部状态变量
-- ==========================================================

-- 用户配置参数（init 后不可变）
local cfg_wdt_pin           = nil   -- 喂狗 GPIO 引脚号
local cfg_auto_feed_period  = DEFAULT_AUTO_FEED_PERIOD  -- 自动喂狗周期（s）

-- 运行时状态
local initialized       = false -- 是否已初始化
local last_feed_ms      = nil   -- 上次喂狗的毫秒时间戳（用于防误触发判断）
local need_force_reset  = false -- 强制复位标志位（由 trigger_reset() 设置，主循环检查后执行）

-- ==========================================================
-- 内部工具函数（先定义后调用）
-- ==========================================================

-- 获取系统启动以来的毫秒数
-- @return number|nil 毫秒数，获取失败返回 nil
local function get_tick_ms()
    if mcu.ticks and mcu.hz then
        return math.floor((mcu.ticks() * 1000) / mcu.hz())
    end
    return nil
end

-- ==========================================================
-- GPIO 操作函数（先定义后调用）
-- ==========================================================

-- 初始化 GPIO 引脚，输出空闲电平
local function init_gpio()
    gpio.setup(cfg_wdt_pin, PIN_IDLE_LEVEL, gpio.PULLUP)
    log.info("exair153x_wdt", string.format("GPIO%d 初始化为空闲态 %d", cfg_wdt_pin, PIN_IDLE_LEVEL))
end

-- 设置 GPIO 输出电平
-- @param level number 目标电平（0 或 1）
local function set_pin_level(level)
    gpio.set(cfg_wdt_pin, level)
end

-- ==========================================================
-- 核心喂狗函数（先定义后调用）
-- ==========================================================

-- 底层喂狗函数，输出单次喂狗脉冲
-- 自动喂狗与手动喂狗全部复用此函数
local function _inner_feed()
    set_pin_level((PIN_ACTIVE_LEVEL == 0) and 1 or 0)
    sys.wait(50)
    -- GPIO 输出低电平（喂狗有效）
    set_pin_level(PIN_ACTIVE_LEVEL)
    sys.wait(PULSE_MS)
    set_pin_level((PIN_ACTIVE_LEVEL == 0) and 1 or 0)
    sys.wait(50)
    -- GPIO 切回低电平（空闲态）
    set_pin_level(PIN_IDLE_LEVEL)

    -- 记录本次喂狗时间戳，用于 feed() 的防误触发判断
    last_feed_ms = get_tick_ms()
end

-- 强制复位函数，连续输出 3 次快速脉冲触发芯片硬件复位
-- 芯片判定条件：T_test < 1s 内连续收到 3 个喂狗信号
local function _force_reset()
    log.warn("exair153x_wdt", "开始 3 次快速脉冲，触发芯片强制硬件复位")

    set_pin_level((PIN_ACTIVE_LEVEL == 0) and 1 or 0)
    sys.wait(100)
    -- 连续 3 次喂狗脉冲（250ms 宽度），相邻间隔 100ms
    -- 第1次到第3次脉冲开始跨度 700ms，远小于芯片 1s 判定限制
    for i = 1, 3 do
        set_pin_level(PIN_ACTIVE_LEVEL)
        sys.wait(PULSE_MS)
        set_pin_level((PIN_ACTIVE_LEVEL == 0) and 1 or 0)
        -- 最后一次脉冲后不需要间隔
        if i < 3 then
            sys.wait(100)
        end
    end

    -- 芯片检测到 3 次快速脉冲后，PWR_OFF 输出 500ms 高电平
    -- 通过 NPN 三极管拉低主控 RESET，实现整机硬件复位
    log.warn("exair153x_wdt", "3 次脉冲已发送，等待芯片触发硬件复位")
end

-- 参数全量校验
-- @param cfg table 用户传入的配置表
-- @return boolean 校验是否通过
local function validate_params(cfg)
    -- 校验 wdt_pin（必选）
    if cfg.wdt_pin == nil or type(cfg.wdt_pin) ~= "number" then
        log.error("exair153x_wdt", "wdt_pin 无效，必须传入有效的 GPIO 引脚号")
        return false
    end

    -- 校验 auto_feed_period_s（可选，不能为负数）
    if cfg.auto_feed_period_s ~= nil then
        if type(cfg.auto_feed_period_s) ~= "number" or cfg.auto_feed_period_s < MIN_AUTO_FEED_PERIOD then
            log.error("exair153x_wdt", "auto_feed_period_s 不能为负数")
            return false
        end
    end

    return true
end

-- ==========================================================
-- 自动喂狗主循环任务
-- ==========================================================

-- 自动喂狗主循环，由 init() 内部通过 sys.taskInit 启动
-- 按 auto_feed_period_s 周期自动喂狗，feed() / trigger_reset() 可通过
-- sys.publish(EVENT_FEED_RESET) 唤醒并重置计时起点
local function auto_feed_task()
    -- 首次喂狗
    log.info("exair153x_wdt", "首次喂狗")
    _inner_feed()

    -- 主循环：周期喂狗，可被 EVENT_FEED_RESET 事件唤醒
    while true do
        sys.waitUntil(EVENT_FEED_RESET, cfg_auto_feed_period * 1000)

        -- 优先检查是否需要执行强制复位
        -- trigger_reset() 设置标志位后，由主循环统一执行复位操作
        if need_force_reset then
            need_force_reset = false
            _force_reset()
            goto continue
        end

        -- 执行喂狗（无论是超时唤醒还是被 feed()/trigger_reset() 唤醒）
        _inner_feed()
        log.debug("exair153x_wdt", "喂狗完成")

        ::continue::
    end
end

-- ==========================================================
-- 公开 API
-- ==========================================================

local M = {}

--[[
初始化看门狗，配置全局参数，执行首次上电喂狗，并启动自动喂狗任务
@param cfg table 配置表，必须包含 wdt_pin，其余可选
@return boolean 初始化是否成功
@usage
exair153x_wdt.init({ wdt_pin = 24 })
exair153x_wdt.init({ wdt_pin = 24, auto_feed_period_s = 180 })
]]
function M.init(cfg)
    -- 参数类型检查
    if cfg == nil or type(cfg) ~= "table" then
        log.error("exair153x_wdt", "init 参数必须为 table 类型")
        return false
    end

    -- 重复初始化拦截
    if initialized then
        log.warn("exair153x_wdt", "已初始化，禁止重复调用")
        return false
    end

    -- 全量参数校验
    if not validate_params(cfg) then
        return false
    end

    -- 写入配置参数
    cfg_wdt_pin         = cfg.wdt_pin
    cfg_auto_feed_period = cfg.auto_feed_period_s or DEFAULT_AUTO_FEED_PERIOD

    -- 初始化 GPIO
    init_gpio()

    -- 标记初始化完成
    initialized = true

    -- 启动自动喂狗主循环任务
    sys.taskInit(auto_feed_task)

    log.info("exair153x_wdt", string.format("初始化成功: GPIO%d, 脉冲=%dms, 周期=%ds",
        cfg_wdt_pin, PULSE_MS, cfg_auto_feed_period))

    return true
end

--[[
手动执行单次喂狗操作
仅唤醒主循环，由主循环统一执行喂狗
内有防误触发机制，距上次喂狗不足 1 秒时拒绝执行
@return boolean 喂狗请求是否成功
@usage
local success = exair153x_wdt.feed()
]]
function M.feed()
    -- 未初始化拦截
    if not initialized then
        log.warn("exair153x_wdt", "未初始化，无法喂狗")
        return false
    end

    -- 防误触发：距上次喂狗不足 1 秒不执行，避免 1s 内出现 3 次脉冲误触发强制复位
    local now_ms = get_tick_ms()
    if last_feed_ms and now_ms then
        local delta = now_ms - last_feed_ms
        if delta < FEED_COOLDOWN_MS then
            log.warn("exair153x_wdt", string.format("距上次喂狗仅 %dms，跳过手动喂狗（防误触发强制复位）", delta))
            return false
        end
    end

    -- 唤醒主循环执行喂狗
    sys.publish(EVENT_FEED_RESET)

    return true
end

--[[
手动触发看门狗复位操作，设置标志位后由主循环统一执行复位
@return boolean 调用是否成功
@usage
local success = exair153x_wdt.trigger_reset()
]]
function M.trigger_reset()
    -- 未初始化拦截
    if not initialized then
        log.warn("exair153x_wdt", "未初始化，无法触发复位")
        return false
    end

    -- 设置强制复位标志位，由主循环检查后执行
    need_force_reset = true

    -- 唤醒主循环
    sys.publish(EVENT_FEED_RESET)

    return true
end

--[[
获取库版本信息，无需初始化即可调用
@return string 年月日时分，例如： "202606300102"
@usage
exair153x_wdt.version()
]]
function M.version()
    return "202609091030"
end

log.debug("exair153x_wdt", "version -> " .. M.version())

return M