--[[
 * ============================================================
 *  Air153C 看门狗芯片 - LuatOS lib 库
 *  基于：Air153C看门狗芯片设计手册V1.4
 *  支持模式：1=正常喂狗 / 0=停止喂狗(等待超时复位) / 2=强制复位
 * ============================================================
 *
 * 【重要 - 电平极性说明】
 *  如果你的硬件是：GPIO → NPN三极管 → R207上拉到 VBAT → Air153C WTDOG
 *    NPN 是反相驱动：
 *    GPIO低 → Q截止 → WTDOG被R207上拉为高电平(空闲)   → idle_level   = gpio.LOW
 *    GPIO高 → Q导通 → WTDOG被拉到地为低电平(喂狗有效) → active_level = gpio.HIGH
 *
 * 如果你去掉三极管，GPIO 直接连接 WTDOG（电平一致）：
 *    GPIO高 → WTDOG高电平(空闲)   → idle_level   = gpio.HIGH
 *    GPIO低 → WTDOG低电平(喂狗有效) → active_level = gpio.LOW
 *
 * 错误配置会导致：一直不喂狗反复复位 / 一直喂狗从不复位
 * ============================================================
 *
 * 使用示例:
 *   local air153c_wdt = require("air153c_watchdog")
 *   air153c_wdt.init_start({
 *       feed_pin           = 24,       -- GPIO 喂狗引脚
 *       idle_level         = gpio.LOW, -- GPIO 空闲电平（看上面说明）
 *       active_level       = gpio.HIGH,-- GPIO 喂狗有效电平（看上面说明）
 *       sys_voltage        = "3.8",   -- 系统电压，影响超时: "3.3"/"3.8"/"4.3"
 *       t_low              = 250,     -- 喂狗低脉冲宽度(ms) >200ms
 *       t_feed_gap         = 300,     -- 强制复位脉冲间隔(ms) <1000ms
 *       force_feed_count   = 2,       -- 强制复位喂狗次数
 *       wdt_boot_delay     = 15000,   -- 开机保护延时(ms)，避免影响下载
 *       default_mode       = 1,       -- 默认开机模式: 1=正常, 0=停止, 2=强制复位
 *   })
 * ============================================================
--]]

local M = {}

-- ==========================================================
-- 内部状态变量
-- ==========================================================
local config = {
    feed_pin           = 24,       -- GPIO 喂狗引脚
    idle_level         = gpio.LOW, -- GPIO 空闲电平
    active_level       = gpio.HIGH,-- GPIO 喂狗有效电平
    sys_voltage        = "3.8",   -- 系统电压
    t_low              = 250,     -- 喂狗低脉冲宽度 (ms)
    t_restout          = 550,     -- 复位输出等待 (ms)
    t_feed_gap         = 300,     -- 强制复位脉冲间隔 (ms)
    force_feed_count   = 2,       -- 强制复位喂狗次数
    wdt_boot_delay     = 15000,   -- 开机保护延时 (ms)
    default_mode       = 1,       -- 默认开机模式: 1=正常, 0=停止, 2=强制复位
}

local wdt_state = {
    mode             = "NORMAL",  -- 内部模式名称
    feed_count       = 0,
    last_feed_tick64 = nil,
    last_feed_ms     = nil,
    stop_elapsed_ms  = 0,
    monitor_ticks    = 0,
    boot_delay_done  = false,    -- 开机保护是否已完成
}

local wdt_pin_level = 0  -- 当前 GPIO 输出电平

-- 超时时间和安全喂狗间隔（根据电压计算）
local T_TIMEOUT = 0
local T_FEED = 0

-- FSKV 相关（可选）
local fskv_ok = false
local KV_KEY = {
    LAST_BOOT_TIME = "boot:last_time",
    LAST_NET_TIME  = "boot:last_net_time",
    LAST_REASON    = "boot:last_reason",
    BOOT_COUNT     = "boot:count",
}

-- 开机追踪状态
local boot_state = {
    net_ready_ticks = nil,
    ntp_synced      = false,
    net_ready       = false,
    net_ready_time  = nil,
    boot_time       = nil,
    reason_code     = nil,
    reason_str      = nil,
    last_boot_time  = nil,
    last_net_time   = nil,
    last_reason_str = nil,
    boot_count      = 0,
}

-- ==========================================================
-- 内部工具函数
-- ==========================================================

-- 延迟函数：只能在 sys.taskInit 创建的 task 中调用
local function delay_ms(ms)
    sys.wait(ms)
end

-- 根据电压动态计算超时时间
local function get_timeout_by_voltage(voltage)
    local timeout_map = {
        ["3.3"] = 283000,    -- 283s @ 3.3V
        ["3.8"] = 240000,    -- 240s @ 3.8V
        ["4.3"] = 209000,    -- 209s @ 4.3V
    }
    return timeout_map[voltage] or 240000
end

-- 获取当前毫秒数
local function get_tick_ms()
    if mcu.ticks and mcu.hz then
        return math.floor((mcu.ticks() * 1000) / mcu.hz())
    end
    return nil
end

-- 开机保护等待
-- 只在第一次执行操作前等待，保护下载窗口
-- 仅强制复位需要等待，正常喂狗启动后已经过了保护期
local function wait_wdt_boot_delay(task_name)
    -- 如果已经过了保护期，不需要再等
    local elapsed_ms = 0
    if mcu.ticks and mcu.hz then
        elapsed_ms = math.floor((mcu.ticks() * 1000) / mcu.hz())
    end

    local remaining_ms = config.wdt_boot_delay - elapsed_ms
    if remaining_ms > 0 then
        log.info("WDT_BOOT_DELAY", task_name, "开机保护剩余", math.floor(remaining_ms / 1000), "秒，暂不执行看门狗操作")
        sys.wait(remaining_ms)
    end

    if remaining_ms > 0 then
        log.info("WDT_BOOT_DELAY", task_name, "开机保护结束，开始执行看门狗操作")
    end
end

-- 格式化时间间隔
local function fmt_interval(seconds)
    if not seconds or seconds < 0 then return "N/A" end
    local sec = math.floor(seconds)
    local d = math.floor(sec / 86400)
    local h = math.floor((sec % 86400) / 3600)
    local m = math.floor((sec % 3600) / 60)
    local s = sec % 60
    if d > 0 then
        return string.format("%dd %dh %dm %ds", d, h, m, s)
    end
    return string.format("%dh %dm %ds", h, m, s)
end

-- 模式编号转名称
local function mode_num_to_name(num)
    if num == 1 then
        return "NORMAL"
    elseif num == 0 then
        return "STOPPED"
    elseif num == 2 then
        return "FORCED_RESET"
    else
        return "NORMAL"
    end
end

-- ==========================================================
-- GPIO 初始化
-- ==========================================================

local function init_gpio()
    wdt_pin_level = config.idle_level
    gpio.setup(config.feed_pin, wdt_pin_level)
    log.info("WDT_INIT", string.format("喂狗引脚 GPIO%d 初始化为空闲态 %d", config.feed_pin, wdt_pin_level))
end

local function set_feed_pin(level)
    gpio.set(config.feed_pin, level)
    wdt_pin_level = level
end

-- ==========================================================
-- 核心喂狗函数
-- ==========================================================

local function feed_dog()
    -- 只在第一次喂狗前等待开机保护
    if not wdt_state.boot_delay_done then
        wait_wdt_boot_delay("WDT_FEED")
        wdt_state.boot_delay_done = true
    end

    -- 模式标签
    local mode_label =
        (wdt_state.mode == "NORMAL") and "常规喂狗" or
        (wdt_state.mode == "STOPPED") and "停止喂狗(初始)" or
        (wdt_state.mode == "FORCED_RESET") and "强制复位" or
        wdt_state.mode

    log.info("WDT_FEED", "当前", mode_label, string.format("模式, 开始喂狗: GPIO%d高 %d ms -> 恢复GPIO%d低(WTDOG高)", config.feed_pin, config.t_low, config.feed_pin))
    set_feed_pin(config.active_level)
    delay_ms(config.t_low)
    set_feed_pin(config.idle_level)

    wdt_state.feed_count = wdt_state.feed_count + 1
    wdt_state.last_feed_ms = get_tick_ms()
    wdt_state.monitor_ticks = 0  -- 喂狗成功，重置监控计数器

    if mcu.tick64 then
        local tick_str = select(1, mcu.tick64())
        if tick_str and #tick_str == 8 then
            wdt_state.last_feed_tick64 = tick_str
        end
    end

    log.info("WDT_FEED", "第", wdt_state.feed_count, "次喂狗完成")
end

-- 强制复位
local function force_reset()
    -- 如果开机保护还没完成，先等待
    if not wdt_state.boot_delay_done then
        wait_wdt_boot_delay("WDT_FORCE_RST")
        wdt_state.boot_delay_done = true
    end
    log.warn("WDT_FORCE_RST", string.format("========== 开始%d次喂狗强制复位测试 ==========", config.force_feed_count))
    wdt_state.mode = "FORCED_RESET"

    for i = 1, config.force_feed_count do
        log.info("WDT_FORCE_RST", string.format("第 %d 次喂狗: GPIO%d高 %d ms -> 恢复GPIO%d低(WTDOG高)", i, config.feed_pin, config.t_low, config.feed_pin))
        set_feed_pin(config.active_level)
        delay_ms(config.t_low)
        set_feed_pin(config.idle_level)

        if i < config.force_feed_count then
            log.info("WDT_FORCE_RST", string.format("第 %d 次脉冲完成, 间隔 %d ms 后发送下一次脉冲", i, config.t_feed_gap))
            delay_ms(config.t_feed_gap)
        end
    end

    wdt_state.feed_count = wdt_state.feed_count + config.force_feed_count
    log.info("WDT_FORCE_RST", string.format("%d次喂狗完成, 累计喂狗次数:%d, 当前GPIO%d保持低电平(WTDOG空闲高)", config.force_feed_count, wdt_state.feed_count, config.feed_pin))

    sys.wait(config.t_restout + 500)
    log.warn("WDT_FORCE_RST", string.format("========== %d次喂狗强制复位测试结束 ==========", config.force_feed_count))
end

-- ==========================================================
-- 任务：喂狗主循环
-- ==========================================================

local function watchdog_feeding_task()
    log.info("WDT_TASK", "看门狗喂狗任务启动, 间隔:", math.floor(T_FEED/1000) .. "s")

    while true do
        if wdt_state.mode == "NORMAL" then
            feed_dog()
            -- 使用 waitUntil 可被 set_mode 的 publish 立即唤醒, 避免卡在长 sleep 中错过模式切换
            sys.waitUntil("WDT_MODE_CHANGE", T_FEED)

        elseif wdt_state.mode == "STOPPED" then
            -- 如果从未喂过狗，先执行一次喂狗脉冲
            -- 看门狗芯片需要收到第一个下降沿才开始超时计时
            if wdt_state.feed_count == 0 then
                log.info("WDT_STOPPED", "初始模式为STOPPED，先执行一次喂狗以启动芯片计时...")
                feed_dog()
                wdt_state.stop_elapsed_ms = 0  -- 刚喂完，计时从0开始
                log.info("WDT_STOPPED", "初始喂狗完成，进入停止等待(超时", math.floor(T_TIMEOUT/1000) .. "s)")
                sys.waitUntil("WDT_MODE_CHANGE", 30000)  -- 等待30s或被模式切换唤醒
                goto continue
            end
            -- 累计已过时间：每30s循环一次，直接累加
            wdt_state.stop_elapsed_ms = wdt_state.stop_elapsed_ms + 30000
            -- 电平描述
            local pin_level = (wdt_pin_level == config.idle_level) and string.format("GPIO%d_LOW(WTDOG空闲高)", config.feed_pin) or string.format("GPIO%d_HIGH(WTDOG喂狗低)", config.feed_pin)
            local elapsed_ms = wdt_state.stop_elapsed_ms
            local remaining = T_TIMEOUT - elapsed_ms
            local remain_str = remaining > 0 and fmt_interval(math.floor(remaining / 1000)) or "即将复位!"
            log.info("WDT_STOPPED", "喂狗已停止 | 距上次喂狗:", fmt_interval(math.floor(elapsed_ms / 1000)),
                     "| 超时阈值:", math.floor(T_TIMEOUT/1000) .. "s",
                     "| 预计复位剩余:", remain_str,
                     "| 引脚电平:", pin_level)
            sys.waitUntil("WDT_MODE_CHANGE", 30000)  -- STOPPED模式每30s汇报一次, 可被模式切换唤醒

        elseif wdt_state.mode == "FORCED_RESET" then
            force_reset()
            log.info("WDT_EXIT", "强制复位已执行，恢复NORMAL模式等待下次指令")
            -- 恢复NORMAL模式，继续循环等待下一次模式切换
            wdt_state.mode = "NORMAL"
        end
        ::continue::
    end
end

-- ==========================================================
-- 任务：监控喂狗间隔
-- ==========================================================

local function watchdog_monitor_task()
    log.info("WDT_MONITOR", "看门狗监控任务启动, 超时阈值:", math.floor(T_TIMEOUT/1000) .. "s")

    while true do
        if wdt_state.mode ~= "NORMAL" then
            sys.wait(5000)
            goto continue
        end

        -- 用计数器检测喂狗间隔，feed_dog() 会将此计数器归零
        wdt_state.monitor_ticks = (wdt_state.monitor_ticks or 0) + 10
        if wdt_state.monitor_ticks > T_TIMEOUT * 0.9 / 1000 then
            log.warn("WDT_WARN", "喂狗间隔过长:", wdt_state.monitor_ticks, "s, 即将超时!")
        end

        ::continue::
        sys.wait(10000)
    end
end

-- ==========================================================
-- 公共接口：初始化
-- ==========================================================

--[[
 * 初始化看门狗配置
 * @param cfg 配置表，包含所有可配置参数
 * @return 无
--]]
function M.init(cfg)
    -- 合并用户配置
    if cfg.feed_pin ~= nil then
        config.feed_pin = cfg.feed_pin
    end
    if cfg.idle_level ~= nil then
        config.idle_level = cfg.idle_level
    end
    if cfg.active_level ~= nil then
        config.active_level = cfg.active_level
    end
    if cfg.sys_voltage ~= nil then
        config.sys_voltage = cfg.sys_voltage
    end
    if cfg.t_low ~= nil then
        config.t_low = cfg.t_low
    end
    if cfg.t_restout ~= nil then
        config.t_restout = cfg.t_restout
    end
    if cfg.t_feed_gap ~= nil then
        config.t_feed_gap = cfg.t_feed_gap
    end
    if cfg.force_feed_count ~= nil then
        config.force_feed_count = cfg.force_feed_count
    end
    if cfg.wdt_boot_delay ~= nil then
        config.wdt_boot_delay = cfg.wdt_boot_delay
    end
    if cfg.default_mode ~= nil then
        config.default_mode = cfg.default_mode
    end

    -- 转换模式编号为名称
    wdt_state.mode = mode_num_to_name(config.default_mode)

    -- 根据电压计算超时时间
    T_TIMEOUT = get_timeout_by_voltage(config.sys_voltage)
    -- 安全喂狗间隔 = 超时 * 0.6 (留40%余量)
    T_FEED = math.floor(T_TIMEOUT * 0.6)

    -- 初始化 GPIO
    init_gpio()

    -- FSKV 初始化（可选）
    if fskv and fskv.init then
        fskv_ok = fskv.init()
        log.info("FSKV_INIT", fskv_ok and "初始化成功" or "初始化失败")
        if fskv_ok then
            -- 读取历史开机记录
            local last_time = fskv.get(KV_KEY.LAST_BOOT_TIME)
            if last_time then
                boot_state.last_boot_time = tonumber(last_time)
            end
            local last_net = fskv.get(KV_KEY.LAST_NET_TIME)
            if last_net then
                boot_state.last_net_time = tonumber(last_net)
            end
            boot_state.last_reason_str = fskv.get(KV_KEY.LAST_REASON)
            local count = fskv.get(KV_KEY.BOOT_COUNT)
            boot_state.boot_count = count and tonumber(count) or 0
        end
    else
        log.warn("FSKV_INIT", "FSKV库不可用，开机历史记录功能禁用")
    end

    -- 打印配置信息
    log.info("AIR153C_WDT", "初始化完成:")
    log.info("AIR153C_WDT", string.format("  feed_pin: %d", config.feed_pin))
    log.info("AIR153C_WDT", string.format("  idle_level: %d, active_level: %d", config.idle_level, config.active_level))
    log.info("AIR153C_WDT", string.format("  sys_voltage: %s, timeout: %ds", config.sys_voltage, math.floor(T_TIMEOUT/1000)))
    log.info("AIR153C_WDT", string.format("  t_low: %dms, feed_interval: %ds", config.t_low, math.floor(T_FEED/1000)))
    log.info("AIR153C_WDT", string.format("  default_mode: %d(%s)", config.default_mode, wdt_state.mode))
end

-- ==========================================================
-- 公共接口：启动看门狗任务
-- ==========================================================

--[[
 * 启动看门狗任务
 * 必须在 init() 之后调用
--]]
function M.start()
    -- 启动喂狗任务
    sys.taskInit(watchdog_feeding_task)
    -- 启动监控任务
    sys.taskInit(watchdog_monitor_task)
    log.info("AIR153C_WDT", "所有任务已启动")
end

--[[
 * 一次性完成初始化并启动 (便捷接口)
 * @param cfg 配置表，同 init()
 * 用法: air153c_wdt.init_start(cfg)
--]]
function M.init_start(cfg)
    M.init(cfg)
    M.start()
    return M
end

-- ==========================================================
-- 公共接口：手动单次喂狗（不影响正常循环喂狗）
-- ==========================================================

--[[
 * 手动执行一次单次喂狗
 * 可以在自定义逻辑中调用，比如某些事件后额外喂狗
 * @return true=执行成功, false=执行失败(当前模式不对)
--]]
function M.single_feed()
    return M.feed_now()
end

-- ==========================================================
-- 公共接口：切换模式
-- ==========================================================

--[[
 * 切换看门狗模式
 * @param mode_num 模式编号: 1=正常喂狗, 0=停止喂狗, 2=强制复位
--]]
function M.set_mode(mode_num)
    local mode_name = mode_num_to_name(mode_num)
    wdt_state.mode = mode_name
    if mode_num == 0 then
        wdt_state.stop_elapsed_ms = 0  -- 重置停止计时器
        log.info("AIR153C_WDT", "模式切换: STOPPED(停止喂狗，等待超时复位)")
        sys.publish("WDT_STATUS", "STOPPED", wdt_state.feed_count)
    elseif mode_num == 1 then
        wdt_state.stop_elapsed_ms = 0
        log.info("AIR153C_WDT", "模式切换: NORMAL(正常自动定时喂狗)")
        sys.publish("WDT_STATUS", "NORMAL", wdt_state.feed_count)
    elseif mode_num == 2 then
        log.info("AIR153C_WDT", "模式切换: FORCED_RESET(执行强制复位)")
        sys.publish("WDT_STATUS", "FORCED_RESET", wdt_state.feed_count)
        -- 强制复位在下次任务循环中执行
    end
    -- 立即唤醒 watchdog_feeding_task 中的 waitUntil, 避免卡在长 sleep 里错过模式切换
    sys.publish("WDT_MODE_CHANGE", mode_num)
end

-- ==========================================================
-- 公共接口：手动执行一次喂狗
-- ==========================================================

--[[
 * 手动执行一次喂狗
 * 仅在 NORMAL 模式下有效
--]]
function M.feed_now()
    if wdt_state.mode ~= "NORMAL" then
        log.warn("AIR153C_WDT", "当前模式不允许手动喂狗: " .. wdt_state.mode)
        return false
    end

    -- 防误触发：距上次喂狗不足1秒不执行，避免误触发双脉冲强制复位
    local elapsed_ms = get_tick_ms()
    if wdt_state.last_feed_ms and elapsed_ms then
        local delta = elapsed_ms - wdt_state.last_feed_ms
        if delta and delta < 1000 then
            log.warn("AIR153C_WDT", string.format("距上次喂狗仅 %dms，跳过本次手动喂狗(防误触发强制复位)", delta))
            return false
        end
    end

    sys.taskInit(function()
        feed_dog()
    end)
    return true
end

-- ==========================================================
-- 公共接口：查询当前状态
-- ==========================================================

--[[
 * 查询当前看门狗状态
 * @return 状态表
--]]
function M.get_status()
    return {
        mode = wdt_state.mode,
        mode_num = config.default_mode,
        feed_count = wdt_state.feed_count,
        monitor_ticks = wdt_state.monitor_ticks,
        stop_elapsed_ms = wdt_state.stop_elapsed_ms,
        last_feed_ms = wdt_state.last_feed_ms,
        timeout_ms = T_TIMEOUT,
        feed_interval_ms = T_FEED,
    }
end

-- ==========================================================
-- 返回模块
-- ==========================================================

return M
