--[[
@module  mypower
@summary 电源管理模块（电池监测 + USB充电检测 + 低功耗 + PWRKEY关机）
@version 2.0
@date    2026-05-27
@description
    v2.0 核心功能：
      1. 电池电压检测：ADC0 分压电路，5次采样去最大去最小求平均，补偿 140mV
         （参考花生宠物 battery.lua 2026.04.22）
      2. 电量计算：3.4V=0%（关机阈值），4.2V=100%（满电），线性映射
      3. 低电关机：电压 <= 3.4V 自动调用 pm.shutdown() 保护电池
      4. USB 充电检测：WAKEUP1(VBUS) 引脚双边沿中断，level=1 表示已插入
      5. 充满时间估算：基于剩余电量 + 经验充电速率
      6. 低功耗常驻：init 后立即进入 pm.power(pm.WORK_MODE, 1)
      7. PWRKEY 长按 7 秒 -> pm.shutdown() 软关机
]]

local mypower = {}

-- ========== 硬编码常量 ==========
local BATTERY_FULL_MV            = 4150    -- 满电电压(mV) = 4.15V → 100%
local BATTERY_PERCENT_EMPTY_MV   = 3300    -- 电量0%电压(mV) = 3.3V → 0%（显示用）
local BATTERY_EMPTY_MV           = 3400    -- 关机保护电压(mV) = 3.4V（低于此值自动关机保护电池）
local BATTERY_DIVIDER_HIGH       = 1000    -- 分压电阻高边(kΩ)：BAT->1MΩ->ADC0->300kΩ->GND
local BATTERY_DIVIDER_LOW        = 300     -- 分压电阻低边(kΩ)
local BATTERY_ADC_OFFSET_MV      = 140     -- ADC 测量补偿值(mV)，与花生宠物一致
local BATTERY_ADC_CHANNEL        = 0       -- 用户指定 ADC0
local BATTERY_SAMPLE_COUNT       = 5       -- 单次采样次数
local BATTERY_SAMPLE_INTERVAL_MS = 10      -- 采样间隔
local BATTERY_MONITOR_INTERVAL   = 60000   -- 电池监控周期(毫秒)
local LOW_BATTERY_THRESHOLD      = 10      -- 低电量警告阈值(%)
local CRITICAL_BATTERY_THRESHOLD = 5       -- 严重低电警告阈值(%)

-- USB 充电检测：WAKEUP1(VBUS) 引脚
-- 参考 Air8201 BTB 设计文档：https://docs.openluat.com/air8201/luatos/hardware/design/btb/
-- "vbus(WAKEUP1) ... 可作为唤醒脚（WAKEUP1）,可对电池进行充电"
local VBUS_DETECT_PIN            = gpio.WAKEUP1
local VBUS_DEBOUNCE_MS           = 200     -- VBUS 防抖时长

-- 充电速率（用于估算充满所需时间）：单位 %/min，经验值
-- 假设 1000mAh 电池 + 500mA 充电电流 -> 2 小时充满 -> 约 0.83 %/min
local CHARGE_RATE_PERCENT_PER_MIN = 0.83

-- PWRKEY 长按关机
local PWRKEY_DEBOUNCE_MS         = 200     -- PWRKEY 防抖时长
local PWRKEY_SHUTDOWN_HOLD_MS    = 7000    -- 长按 7 秒触发关机

-- 低电压关机保护开关
local LOW_VOLTAGE_SHUTDOWN_ENABLED = true

-- ========== 红灯（LED）配置 ==========
local RED_LED_PIN        = 16      -- 红灯控制引脚 GPIO16
local RED_LED_ON_LEVEL   = 1       -- 点亮电平（高电平点亮；若硬件为低电平点亮则改为 0）
local RED_LED_BLINK_ON_MS  = 200   -- 单次闪烁点亮时长(ms)
local RED_LED_BLINK_OFF_MS = 200   -- 单次闪烁熄灭时长(ms)
local RED_LED_DEFAULT_TIMES = 3    -- 默认闪烁次数
local red_led_inited     = false   -- GPIO16 是否已初始化为输出模式

-- ========== 模块状态 ==========
local battery_state = {
    voltage_mv = 0,
    level = 100,
    charging = false,
    last_check_time = 0,
}

local is_lowpower_mode = false
-- 旧版 long_press_timer 已废弃，PWRKEY 长按检测改为轮询累计法（见下方 pwrkey 段）

local low_battery_threshold = LOW_BATTERY_THRESHOLD
local critical_battery_threshold = CRITICAL_BATTERY_THRESHOLD

-- ========== 电池电压采样 ==========
-- 读取电池电压（5次采样，去最大最小，取剩下平均）
-- 参考花生宠物 battery.lua 2026.04.22
-- @return number|nil 电池电压(mV)，失败返回 nil
local function read_battery_voltage()
    local samples = {}

    for i = 1, BATTERY_SAMPLE_COUNT do
        adc.setRange(adc.ADC_RANGE_MIN)
        adc.open(BATTERY_ADC_CHANNEL)
        local raw_mv = adc.get(BATTERY_ADC_CHANNEL)
        adc.close(BATTERY_ADC_CHANNEL)

        if raw_mv then
            -- 反向分压计算：vbat = raw * (Rhigh + Rlow) / Rlow + 补偿
            local vbat = raw_mv * (BATTERY_DIVIDER_HIGH + BATTERY_DIVIDER_LOW) / BATTERY_DIVIDER_LOW
                         + BATTERY_ADC_OFFSET_MV
            table.insert(samples, vbat)
        end

        sys.wait(BATTERY_SAMPLE_INTERVAL_MS)
    end

    if #samples < 3 then
        log.error("POWER", "ADC 采样失败，有效数据不足（仅 " .. #samples .. " 次）")
        return nil
    end

    local max_val, min_val, sum = samples[1], samples[1], 0
    for i = 1, #samples do
        if samples[i] > max_val then max_val = samples[i] end
        if samples[i] < min_val then min_val = samples[i] end
        sum = sum + samples[i]
    end

    local avg_voltage = (sum - max_val - min_val) / (#samples - 2)
    return math.floor(avg_voltage + 0.5)
end

-- 计算电池电量百分比（线性映射）
-- 用户指定：3.4V=0%（关机阈值），4.2V=100%
local function calculate_level(voltage_mv)
    -- 电量百分比量程：3.3V(3300mV)=0% ~ 4.15V(4150mV)=100%
    if voltage_mv >= BATTERY_FULL_MV then return 100 end
    if voltage_mv <= BATTERY_PERCENT_EMPTY_MV then return 0 end
    return math.floor((voltage_mv - BATTERY_PERCENT_EMPTY_MV) / (BATTERY_FULL_MV - BATTERY_PERCENT_EMPTY_MV) * 100)
end

-- 估算充满电所需时间（仅充电中有效）
-- @return number|nil 剩余分钟数，未充电返回 nil
local function estimate_remaining_charge_minutes()
    if not battery_state.charging then return nil end
    local remain_percent = 100 - battery_state.level
    if remain_percent <= 0 then return 0 end
    return math.floor(remain_percent / CHARGE_RATE_PERCENT_PER_MIN + 0.5)
end

-- ========== USB 充电检测 ==========
local function vbus_callback()
    local level = gpio.get(VBUS_DETECT_PIN)
    log.info("POWER", "VBUS event, level=" .. tostring(level))

    if level == 1 then
        battery_state.charging = true
        log.info("POWER", "===> USB 插入，进入充电模式")
        sys.publish("CHARGING_START")
    else
        battery_state.charging = false
        log.info("POWER", "===> USB 拔出，停止充电")
        sys.publish("CHARGING_STOP")
    end
end

local function setup_vbus_listener()
    gpio.debounce(VBUS_DETECT_PIN, VBUS_DEBOUNCE_MS)
    gpio.setup(VBUS_DETECT_PIN, vbus_callback, gpio.PULLDOWN, gpio.BOTH)

    -- 初始化时读取当前 VBUS 电平
    local current = gpio.get(VBUS_DETECT_PIN)
    if current then
        battery_state.charging = (current == 1)
        log.info("POWER", "VBUS 监听已启用 (WAKEUP1), 初始充电状态:", battery_state.charging)
    end
end

-- ========== 红灯闪烁 ==========
-- 初始化红灯 GPIO16 为输出模式（幂等，仅首次真正配置）
local function red_led_init()
    if red_led_inited then return end
    gpio.setup(RED_LED_PIN, RED_LED_ON_LEVEL == 1 and 0 or 1)  -- 输出模式，初始为熄灭电平
    red_led_inited = true
    log.info("POWER", "红灯 GPIO" .. RED_LED_PIN .. " 已初始化为输出模式")
end

-- 红灯闪烁指定次数（同步阻塞，须在 task 中调用）
-- @param times number 闪烁次数，默认 RED_LED_DEFAULT_TIMES(3)
function mypower.blink_red_led(times)
    times = tonumber(times) or RED_LED_DEFAULT_TIMES
    if times <= 0 then times = RED_LED_DEFAULT_TIMES end

    red_led_init()

    local off_level = (RED_LED_ON_LEVEL == 1) and 0 or 1
    log.info("POWER", "红灯闪烁 " .. times .. " 次")

    for i = 1, times do
        gpio.set(RED_LED_PIN, RED_LED_ON_LEVEL)   -- 点亮
        sys.wait(RED_LED_BLINK_ON_MS)
        gpio.set(RED_LED_PIN, off_level)          -- 熄灭
        sys.wait(RED_LED_BLINK_OFF_MS)
    end

    -- 结束后确保熄灭
    gpio.set(RED_LED_PIN, off_level)
end

-- ========== 软关机 ==========
-- 软关机（调用合宙官方 pm.shutdown 接口）
-- 仅 Air780E/Air700E/Air780EP 等移芯 CAT1 平台系列支持
-- 关机后需再次按 PWRKEY 才能开机
function mypower.shutdown(reason)
    reason = reason or "manual"
    log.warn("POWER", "===> 即将关机, reason=" .. tostring(reason))
    -- 关机前红灯闪烁 3 次，提示即将关机（同步阻塞，闪完再关机）
    mypower.blink_red_led(RED_LED_DEFAULT_TIMES)
    pm.shutdown()
end

-- ========== PWRKEY 长按 7 秒关机监听（轮询累计法 v2）==========
-- 实现机制（解决旧版边沿中断"快短按弹起边沿丢失"问题）：
--   1) PWRKEY 配置为 PULLUP + 下降沿中断，仅作为"开始监测"的触发器
--   2) 收到下降沿中断 → 通过 sys.publish 启动监测任务（避免重入）
--   3) 监测任务每秒主动 gpio.get(gpio.PWR_KEY) 一次
--      ├─ level=0（按下中）→ 累计计数 +1
--      ├─ level=1（已弹起）→ 任意时刻读到高电平立即退出，发布短按事件
--      └─ 累计达到 PWRKEY_SHUTDOWN_HOLD_SEC（7）秒 → 调用 mypower.shutdown
--   4) 任务结束后等待下一次下降沿中断
-- 优势：
--   - 不依赖弹起的上升沿中断，极快短按（弹起边沿被防抖吃掉）也能正确识别
--   - 轮询粒度 1 秒，CPU 占用极低
--   - 任务任意时刻退出，无定时器悬空问题
local PWRKEY_POLL_TASK_NAME    = "PWRKEY_POLL_TASK"
local PWRKEY_POLL_INTERVAL_MS  = 1000   -- 轮询周期：每秒一次
local PWRKEY_SHUTDOWN_HOLD_SEC = math.floor(PWRKEY_SHUTDOWN_HOLD_MS / 1000)  -- 累计需达到的秒数

local pwrkey_polling = false  -- 防止重入：监测任务运行期间忽略新的中断

-- PWRKEY 下降沿中断回调（仅做"开始监测"的触发器，不做业务）
local function pwrkey_handler()
    local level = gpio.get(gpio.PWR_KEY)
    log.info("POWER", "PWRKEY 中断触发, level=" .. tostring(level))

    -- 只处理按下事件（level=0），且当前没有正在轮询
    if level == 0 and (not pwrkey_polling) then
        pwrkey_polling = true
        sys.publish(PWRKEY_POLL_TASK_NAME)
    end
end

-- PWRKEY 轮询监测任务：每秒采样电平，累计达 7 秒拉低就关机
local function start_pwrkey_poll_task()
    sys.taskInit(function()
        while true do
            -- 等待中断触发"开始监测"信号
            sys.waitUntil(PWRKEY_POLL_TASK_NAME)
            log.info("POWER", "PWRKEY 进入轮询监测，每秒采样一次")

            local low_count = 0
            while true do
                sys.wait(PWRKEY_POLL_INTERVAL_MS)
                local lv = gpio.get(gpio.PWR_KEY)

                if lv == 0 then
                    -- 仍按下：累计 +1
                    low_count = low_count + 1
                    log.info("POWER", "PWRKEY 持续按下 " .. low_count
                                      .. "/" .. PWRKEY_SHUTDOWN_HOLD_SEC .. " 秒")

                    if low_count >= PWRKEY_SHUTDOWN_HOLD_SEC then
                        log.warn("POWER", "PWRKEY 累计长按 " .. PWRKEY_SHUTDOWN_HOLD_SEC
                                          .. " 秒 → 触发关机")
                        pwrkey_polling = false
                        mypower.shutdown("PWRKEY hold " .. PWRKEY_SHUTDOWN_HOLD_SEC .. "s")
                        break
                    end
                else
                    -- 已弹起：未满 7 秒，视为短按
                    log.info("POWER", "PWRKEY 已弹起（累计按下 " .. low_count
                                      .. " 秒，未满 " .. PWRKEY_SHUTDOWN_HOLD_SEC .. " 秒）→ 短按")
                    -- 短按红灯闪烁 3 次（测试红灯），独立 task 不阻塞轮询循环
                    sys.taskInit(function()
                        mypower.blink_red_led(RED_LED_DEFAULT_TIMES)
                    end)
                    sys.publish("PWRKEY_SHORT_PRESS")
                    -- 兼容旧逻辑：main.lua 中是 waitUntil("PWRKEY_WAKEUP")
                    sys.publish("PWRKEY_WAKEUP")
                    pwrkey_polling = false
                    break
                end
            end
        end
    end)
end

local function setup_pwrkey_listener()
    -- 参考 Air8000 drv_lowpower.lua：
    --   PWR_KEY 内部已拉高至 VBAT，必须 PULLUP，不能 PULLDOWN
    --   按下产生下降沿，弹起产生上升沿
    --   防抖必须在 gpio.setup 之前调用
    -- 本版本只关心"按下"瞬间触发轮询，弹起判定交给轮询任务，
    -- 所以中断边沿可以简化为 gpio.FALLING（只关心下降沿）
    gpio.debounce(gpio.PWR_KEY, PWRKEY_DEBOUNCE_MS)
    gpio.setup(gpio.PWR_KEY, pwrkey_handler, gpio.PULLUP, gpio.FALLING)
    -- 启动后台轮询任务（一直存活，等待中断信号）
    start_pwrkey_poll_task()
    log.info("POWER", "PWRKEY 监听已启用: PULLUP + FALLING + 每秒轮询, debounce "
                      .. PWRKEY_DEBOUNCE_MS .. "ms, 累计 "
                      .. PWRKEY_SHUTDOWN_HOLD_SEC .. "s 拉低=关机")
end

-- ========== 电池监控 ==========
-- 检测电池电压并更新状态
local function check_battery()
    local voltage = read_battery_voltage()
    if not voltage then return end

    battery_state.voltage_mv = voltage
    battery_state.level = calculate_level(voltage)
    battery_state.last_check_time = os.time()

    log.info("POWER", "电池电压:", voltage .. "mV", "电量:", battery_state.level .. "%",
                      "充电:", battery_state.charging)

    -- 低电压自动关机保护（仅在未充电状态下触发，避免充电过程中误判）
    if LOW_VOLTAGE_SHUTDOWN_ENABLED and (not battery_state.charging) and voltage <= BATTERY_EMPTY_MV then
        log.warn("POWER", "===> 电池电压 " .. voltage .. "mV <= " .. BATTERY_EMPTY_MV
                          .. "mV，触发低电关机保护")
        mypower.shutdown("low_voltage_" .. voltage .. "mV")
        return
    end

    -- 低电量警告
    if battery_state.level <= critical_battery_threshold then
        log.warn("POWER", "严重低电:", battery_state.level .. "%")
        sys.publish("CRITICAL_BATTERY", battery_state.level)
    elseif battery_state.level <= low_battery_threshold then
        log.warn("POWER", "低电警告:", battery_state.level .. "%")
        sys.publish("LOW_BATTERY", battery_state.level)
    end

    -- 充电中打印估算时间
    if battery_state.charging then
        local mins = estimate_remaining_charge_minutes()
        if mins then
            log.info("POWER", "充电中, 预计 " .. mins .. " 分钟充满")
        end
    end
end

-- ========== 进入低功耗常驻模式 ==========
-- 低功耗模式下：4G 保持在线（长连接）、CPU 降频、定时器/中断可唤醒、AGPIO 保电平
function mypower.enter_lowpower()

    -- 进入低功耗常驻前红灯闪烁 3 次，提示开机完成即将进入 MODE1
    mypower.blink_red_led(RED_LED_DEFAULT_TIMES)

    log.info("POWER", "进入低功耗常驻模式: pm.power(pm.WORK_MODE, 1)")
    pm.power(pm.WORK_MODE, 1)
    -- pm.power(pm.USB, 1)
    is_lowpower_mode = true
    log.info("POWER", "已进入低功耗常驻模式")
end

-- ========== 初始化 ==========
function mypower.init()
    log.info("POWER", "初始化电源管理 v2.0 ...")
    log.info("POWER", "电池: ADC" .. BATTERY_ADC_CHANNEL,
                      "满电=" .. BATTERY_FULL_MV .. "mV",
                      "关机=" .. BATTERY_EMPTY_MV .. "mV")
    log.info("POWER", "VBUS 引脚: WAKEUP1 (Air8201 BTB)")
    log.info("POWER", "低电量阈值:", low_battery_threshold .. "%")
    log.info("POWER", "严重低电阈值:", critical_battery_threshold .. "%")

    -- ① 启用 USB 充电检测
    setup_vbus_listener()

    -- ② 启用 PWRKEY 长按 7 秒关机监听（必须在进入低功耗模式之前注册中断）
    setup_pwrkey_listener()

    -- ③ 立即检测一次电池（用 taskInit 包一层，避免阻塞 init）
    sys.taskInit(function()
        sys.wait(50)
        check_battery()
    end)

    -- ④ 立即进入低功耗常驻模式
    mypower.enter_lowpower()

    -- ⑤ 电池监控循环
    sys.taskInit(function()
        while true do
            sys.wait(BATTERY_MONITOR_INTERVAL)
            check_battery()
        end
    end)

    log.info("POWER", "初始化完成（低功耗常驻 + 电池监控）")
end

-- ========== 对外接口 ==========
-- 获取电池数据（完整状态）
function mypower.get_data()
    return {
        voltage_mv = battery_state.voltage_mv,
        voltage = battery_state.voltage_mv / 1000,   -- 兼容旧接口：返回 V
        level = battery_state.level,
        charging = battery_state.charging,
        last_check_time = battery_state.last_check_time,
        remaining_charge_minutes = estimate_remaining_charge_minutes(),
    }
end

-- 获取电池电量(%)
function mypower.get_battery_level()
    return battery_state.level
end

-- 获取电池电压（V，保留两位小数；兼容旧接口）
function mypower.get_battery_voltage()
    return tonumber(string.format("%.2f", battery_state.voltage_mv / 1000))
end

-- 获取电池电压（mV）
function mypower.get_battery_voltage_mv()
    return battery_state.voltage_mv
end

-- 充电状态
function mypower.is_charging()
    return battery_state.charging
end

-- 是否处于低功耗常驻模式
function mypower.is_lowpower_mode()
    return is_lowpower_mode
end

-- 强制立即检测一次电池
function mypower.force_check()
    check_battery()
    return mypower.get_data()
end

-- 设置低电量阈值（仅运行期生效）
function mypower.set_low_battery_threshold(threshold)
    log.info("POWER", "设置低电量阈值:", threshold .. "%")
    low_battery_threshold = threshold
end

-- 设置临界电量阈值（仅运行期生效）
function mypower.set_critical_battery_threshold(threshold)
    log.info("POWER", "设置严重低电阈值:", threshold .. "%")
    critical_battery_threshold = threshold
end

function mypower.get_low_battery_threshold()
    return low_battery_threshold
end

function mypower.get_critical_battery_threshold()
    return critical_battery_threshold
end

-- 获取整体电源状态（兼容旧接口）
function mypower.get_status()
    return {
        battery_level = battery_state.level,
        battery_voltage_mv = battery_state.voltage_mv,
        is_charging = battery_state.charging,
        is_lowpower_mode = is_lowpower_mode,
        low_battery_threshold = low_battery_threshold,
        critical_battery_threshold = critical_battery_threshold,
        remaining_charge_minutes = estimate_remaining_charge_minutes(),
    }
end

-- 估算充满电剩余时间（分钟，仅充电中有效；兼容旧接口）
function mypower.get_remaining_charging_time()
    return estimate_remaining_charge_minutes()
end

return mypower
