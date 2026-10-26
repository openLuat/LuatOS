--[[
@module  settings_gnss_app
@summary GNSS 定位业务层（设置页入口 · UART3 + Air510W + exgnss 扩展库）
@version 1.0
@date    2026.10.26
@author  江访
@usage
本模块是 GNSS 定位页的业务层：开/关定位、每秒把当前解算结果整理成一帧发给 UI。
页面只负责排版，不直接调 exgnss。

消息协议:
订阅: GNSS_OPEN_REQ              → 打开定位（exgnss.setup + open DEFAULT）
订阅: GNSS_CLOSE_REQ             → 关闭定位（退出页面时释放 UART3）
发布: GNSS_OPEN_RESULT(ok, err, info)  info = { name, uart_id, baud, mode, hz }
发布: GNSS_STATUS(state)         → OPEN / FIXED / LOSE / CLOSE（已去重，状态没变不重复发）
发布: GNSS_DATA(t)               → 定位快照，字段见 build_snapshot()

硬件来自 config.peripherals 里 type="gnss" 的条目（默认 UART3 / 115200）；
驱动是 script/libs/exgnss.lua 扩展库 + 内核 libgnss，工程内不再包一层。

=== UART3 与 4G 互斥 ===

本板 UART3 同时接 4G 模组与 GNSS 模组，由硬件切换，软件不做仲裁。
若 4G 那一路在位、network 里的 4g_airlink_uart 已按 2Mbps 打开 UART3，
exgnss 内部 uart.setup 会失败 → 本模块把失败原样报给页面，不会崩：

    [exgnss] open 3 / uart3 is already opened

=== 「一个页面 = 一个 exgnss 应用」 ===

exgnss 用「模式 + tag」标识一个应用，本模块固定 tag="settings"。重复 open 不会堆栈：
addItem 内部先 delItem 再复用空槽。关闭时只关自己那一个应用 —— 若工程里还有别的
模块开着 GNSS，exgnss 不会真正 uart.close / 断电（引用计数语义）。
]]

local exgnss = require "exgnss"

-- 本模块占用的 exgnss 「应用」标识
local TAG = "settings"

-- 未配置 peripherals 时的兜底参数（开发板 V1.1：UART3 / 115200，模块 VBAT 直供）
-- agps_enable 关：4G 与 GNSS 共用 UART3，4G 不在位时 lbsLoc2 加载会崩（见 config 注释）
-- debug 关：打开会打印每条 NMEA 原始报文，排障时临时改 true
local FALLBACK_PARAMS = {
    id = "gnss_1", name = "GNSS", uart_id = 3, baud = 115200,
    gnssmode = 1, agps_enable = false, hz = 1, debug = false,
}

local params = nil       -- 缓存的 config 条目
local running = false    -- 本页是否已打开定位
local poll_timer = nil   -- 快照刷新定时器 id
local last_state = "CLOSE"
local got_data = false   -- 本轮是否收到过任何 NMEA 帧，用于「串口没通」的诊断

-- ==================== 配置 ====================

--[[取本机型声明的 gnss 配置条目（取第一条）]]
local function find_params()
    local list = _G.project_config and _G.project_config.peripherals
    if type(list) ~= "table" then return nil end
    for _, p in ipairs(list) do
        if p and p.type == "gnss" then return p end
    end
    return nil
end

local function get_params()
    if params then return params end
    params = find_params() or FALLBACK_PARAMS
    return params
end

--[[端口描述，给 UI 显示]]
local function port_info()
    local p = get_params()
    return {
        name    = p.name or "GNSS",
        uart_id = p.uart_id or 3,
        baud    = p.baud or 115200,
        mode    = (p.gnssmode == 2) and "单北斗" or "卫星全定位",
        hz      = p.hz or 1,
    }
end

--[[把 config 条目翻译成 exgnss.setup 的参数表，字段与 demo/gnss_test 一致：
gnssmode / agps_enable / debug / uart / uartbaud / hz]]

--[[打开前先把 UART 抢回来。

UART3 可能还被 network 里的 4g_airlink_uart 按 2Mbps 占着。这种状态下 exgnss 内部
uart.setup 会被 C 层直接跳过（日志 "luat_uart_setup: uart3 is opened!"）：波特率不重配、
RX 回调也不会换成 libgnss，表现就是「按钮显示已开启、状态搜星中、但一帧 NMEA 都收不到」，
必须先点一次「停止定位」（exgnss.close 里有 uart.close）再开才正常。

这里主动 close 一次，让后面的 uart.setup 真正生效，不必让用户手动开关一轮。
本板 GNSS 与 4G 共用 UART3、打开定位就意味着要切到 GNSS 那一路，断 4G 属预期。]]
local function release_uart()
    local uid = get_params().uart_id or 3
    pcall(uart.close, uid)
end

local function apply_setup()
    local p = get_params()
    release_uart()
    exgnss.setup({
        gnssmode    = p.gnssmode or 1,
        agps_enable = (p.agps_enable == true),
        debug       = (p.debug == true),
        uart        = p.uart_id or 3,
        uartbaud    = p.baud or 115200,
        hz          = p.hz or 1,
    })
end

-- ==================== 数据快照 ====================

-- tonumber 的 nil 安全版：拿不到就是 nil，不冒充 0
local function num(v)
    return tonumber(v)
end

--[[整理一帧当前定位数据。exgnss 取不到数据时返回 nil，字段缺失即 nil，
绝对不填假值 —— 页面据此显示「--」，避免把 0 当成真实坐标。]]
local function build_snapshot()
    local t = { state = last_state }

    local ok_fix, fix = pcall(exgnss.is_fix)
    if ok_fix then t.fix = fix and true or false end

    local ok_rmc, rmc = pcall(exgnss.rmc, 2)
    if ok_rmc and type(rmc) == "table" then
        got_data = true
        t.valid  = rmc.valid and true or false
        t.lat    = num(rmc.lat)
        t.lng    = num(rmc.lng)
        t.speed  = num(rmc.speed)    -- 节
        t.course = num(rmc.course)   -- 度，正北顺时针
        if num(rmc.year) and num(rmc.month) and num(rmc.day) then
            t.utc = string.format("%04d-%02d-%02d %02d:%02d:%02d",
                math.floor(num(rmc.year)), math.floor(num(rmc.month)), math.floor(num(rmc.day)),
                math.floor(num(rmc.hour) or 0), math.floor(num(rmc.min) or 0),
                math.floor(num(rmc.sec) or 0))
        end
    end

    local ok_gga, gga = pcall(exgnss.gga, 2)
    if ok_gga and type(gga) == "table" then
        t.sats    = num(gga.satellites_tracked)  -- 参与定位的卫星数
        t.alt     = num(gga.altitude)            -- 海拔，米
        t.hdop    = num(gga.hdop)                -- 水平精度因子，越小越好
        t.quality = num(gga.fix_quality)          -- 0 无效 / 1 单点 / 2 差分
    end

    return t
end

local function publish_snapshot()
    local ok, t = pcall(build_snapshot)
    if not ok then
        log.warn("settings_gnss", "读取定位数据失败", tostring(t))
        return
    end
    if t then sys.publish("GNSS_DATA", t) end
end

-- ==================== 状态 ====================

--[[转发定位状态给 UI；exgnss 的 GNSS_STATE 与本地关闭都会打到这里，去重后再发。
force = true 用于页面刚打开时补发当前状态（此时 UI 是新建的，不知道历史状态）]]
local function push_state(state, force)
    if type(state) ~= "string" then return end
    if not force and state == last_state then return end
    last_state = state
    sys.publish("GNSS_STATUS", state)
end

sys.subscribe("GNSS_STATE", function(event)
    push_state(event)
    -- 状态一变立刻补一帧，UI 不用等下一个 1 秒周期
    if running then publish_snapshot() end
end)

-- ==================== 定时刷新 ====================

local function stop_poll()
    if poll_timer then
        sys.timerStop(poll_timer)
        poll_timer = nil
    end
end

local function start_poll()
    stop_poll()
    -- 1 秒一次：hz=1 时每秒一条 RMC/GGA，刷新再快也只是重复读同一帧
    poll_timer = sys.timerLoopStart(publish_snapshot, 1000)
end

-- ==================== 打开 / 关闭 ====================

--[[打开定位放进 sys.taskInit 里跑：
exgnss 打开时会连发几条 $CFGMSG 配置语句（内部用 sys.timerStart 延时），
且 AGPS 分支会 sys.waitUntil 等 NTP；放在非协程的订阅回调里容易出问题。]]
sys.subscribe("GNSS_OPEN_REQ", function()
    sys.taskInit(function()
        if running then
            sys.publish("GNSS_OPEN_RESULT", true, nil, port_info())
            return
        end

        -- UART3 口复用校验：当前通道不是「GNSS」时禁止抢这条串口。
        -- 否则通道选 4G / WiFi 的板子进本页会把正在联网的模组直接踢下线。
        local ch = require "settings_channel_app"
        local ch_mode = ch.get()
        if ch_mode ~= "gnss" then
            sys.publish("GNSS_OPEN_RESULT", false,
                "当前 UART3 通道为 " .. ch.label(ch_mode) .. "，请先在「设置 → UART3口复用」切到 GNSS", port_info())
            return
        end

        apply_setup()
        got_data = false

        -- pcall 只抓异常；exgnss.open 自己也可能返回 false（打开失败），两种都要判
        local called, ret = pcall(exgnss.open, exgnss.DEFAULT, { tag = TAG })
        if not called then
            log.error("settings_gnss", "打开定位异常", tostring(ret))
            sys.publish("GNSS_OPEN_RESULT", false, tostring(ret), port_info())
            return
        end
        if ret == false then
            log.error("settings_gnss", "打开定位失败", "exgnss.open 返回 false")
            sys.publish("GNSS_OPEN_RESULT", false, "打开失败：串口可能已被占用", port_info())
            return
        end

        running = true
        start_poll()
        log.info("settings_gnss", "定位已打开", "UART" .. tostring(port_info().uart_id))
        sys.publish("GNSS_OPEN_RESULT", true, nil, port_info())
        -- 页面是新建的，不知道历史状态（可能上一轮已经定位成功），补发一次当前值
        push_state(last_state, true)
        publish_snapshot()

        --[[串口没通时 exgnss 不会报错，只是永远没有 NMEA —— 6 秒仍无任何帧就提示一次。
        UART3 被 4G 占用（2Mbps）是最典型的场景。]]
        sys.timerStart(function()
            if not running or got_data then return end
            log.warn("settings_gnss", "打开后 6 秒未收到 NMEA 数据")
            sys.publish("GNSS_NOTE", "6 秒内未收到 NMEA，请确认 UART3 未被 4G 占用、模块已上电")
        end, 6000)
    end)
end)

sys.subscribe("GNSS_CLOSE_REQ", function()
    stop_poll()
    got_data = false
    if running then
        running = false
        pcall(exgnss.close, exgnss.DEFAULT, { tag = TAG })
        log.info("settings_gnss", "定位已关闭")
    end
    -- 主动关闭时 exgnss 可能还有别的应用开着而不发 CLOSE 事件，这里自行兜一次
    push_state("CLOSE")
end)
