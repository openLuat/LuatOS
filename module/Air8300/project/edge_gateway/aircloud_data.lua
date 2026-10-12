--[[
@module  aircloud_data
@summary AirCloud平台数据上报与命令处理模块
@version 1.1
@date    2026.09.20
@usage
本文件为AirCloud数据处理模块，负责定时通过 excloud.send 上报设备数据到 AirCloud 平台，
并处理平台下发的自定义控制命令（继电器开/关/读取等）。

数据来源（事件订阅，零重复采集）：
  - 定位经纬度 → 订阅 airlbs_app 发布的 Airlbs_LOCATION_UPDATE
  - 温湿度     → 订阅 temp_sensor 发布的 TEMP_HUMIDITY_UPDATE
  - 继电器状态 → 订阅 relay_ctrl 发布的 RELAY_STATUS_UPDATE
  - 系统数据(CPU/VBAT/CSQ/ICCID) → 发送时实时读取（系统级API）

上报字段（参考 excloud.FIELD_MEANINGS）：
  - 4G信号强度 (782, INTEGER)
  - SIM ICCID (783, ASCII)
  - 温度 (256, FLOAT)
  - 湿度 (257, FLOAT)
  - CPU温度 (263, INTEGER)
  - VBAT电压 (799, INTEGER)
  - GNSS经度 (512, ASCII)
  - GNSS纬度 (513, ASCII)
  - 继电器状态（268，ASCII）

运维日志：启用 AirCloud 运维日志，关键业务事件（上电/连网/采集/命令/FOTA）记录日志。


本文件没有对外接口，直接在 main.lua 中 require "aircloud_data" 即可加载运行。
]]

local excloud = require "excloud"
local relay_ctrl = require "relay_ctrl"

-- 继电器状态 tag：自定义字段 268，承载继电器各路状态（逗号分隔字符串）。
-- 选用理由：268 属协议"传感采集类"区间（256~511）；excloud 库在该区间仅收录
--           256~265（温度/湿度/颗粒数/酸度/碱度/海拔/水位/CPU温度/电量计量/工作状态），
--           266 及以后库中未定义，268 为空闲编号，语义独立，平台可命名为"继电器状态"，
--           后续扩展 8/16 路也不受限（相比原方案复用 775 官方语义为"GPIO高低电平"更贴切）。
-- 协议依据：上行业务载荷合法区间为 256~2047，268 在区间内；
--           excloud.build_tlv 仅做非空校验并按 field % 0x1000 编码，无字段白名单（库 599~612 行），
--           因此可直接发送库中未定义的编号（无需、也无法修改内置库）。
-- 使用前提：需在 AirCloud 平台预先登记数据点（名称"继电器状态"、编号 268、类型"字符串"）。
-- 数据格式：ASCII 字符串，各通道状态以英文逗号分隔（从左到右依次为通道0、通道1……），
--           '1'=吸合、'0'=断开。例：4 路 "1,1,0,0"（通道0、通道1 吸合）；
--           8 路自动变长 "1,1,0,0,0,0,0,0"。字段个数即路数，无需额外定义"路数"字段。
local RELAY_STATUS_FIELD = 268

-- 将继电器状态数组编码为逗号分隔的 ASCII 字符串
-- @param state table 继电器状态数组（1-based，元素 0/1）
-- @return string 形如 "1,1,0,0" 的字符串，字段个数 = 当前路数
local function relay_state_to_string(state)
    local n = relay_ctrl.get_channel_count()   -- 路数唯一来源：换 8 路模块自动跟随，无需改本文件
    local buf = {}
    for i = 1, n do
        buf[i] = (state[i] == 1) and "1" or "0"
    end
    return table.concat(buf, ",")
end

-- ==================== 上报字段有效性过滤（v1.9 新增） ====================
-- 背景（实测踩坑点）：excloud.build_tlv 只要遇到一个"无法编码"的字段就直接判定失败
--   （库 604~609 行：value_encoded 为 nil 或 "" 即 return false），
--   而 excloud.send 遍历 tlv_list 时任一字段构建失败就整包返回 false
--   （库 2166~2170 行："excloud.send data is failed"），
--   结果是该轮全部数据（含温湿度等正常字段）一起被丢弃。
-- 触发条件：
--   1) ASCII / UNICODE / BINARY 类型字段值为 nil 或空字符串
--      —— 典型：GNSS 尚未定位时经纬度为空串、SIM 未就绪时 ICCID 为空串；
--         （注意 excloud 对解码/编码失败的返回值是空串 "" 而非 nil，两种都要判）
--   2) INTEGER / FLOAT 类型字段值不是 number（如 nil 或字符串）。
-- 对策：组包后统一过滤无效字段，保证有效数据照常上报；被跳过字段打印日志便于排查。
-- @param list table 待发送的 TLV 数组
-- @param tag  string 日志标签（区分调用点，如"周期上报"/"命令应答"）
-- @return table 过滤后的 TLV 数组（可能为空表，调用方需判空）
local function filter_valid_tlvs(list, tag)
    local out = {}
    local DT = excloud.DATA_TYPES
    for _, item in ipairs(list) do
        local t, v = item.data_type, item.value
        local reason
        if t == nil or v == nil then
            reason = "值为空(nil)"
        elseif t == DT.ASCII or t == DT.UNICODE or t == DT.BINARY then
            if type(v) ~= "string" or #v == 0 then
                reason = "字符串为空"
            end
        elseif t == DT.INTEGER or t == DT.FLOAT then
            if type(v) ~= "number" then
                reason = "非数字(" .. type(v) .. ")"
            end
        end
        if reason then
            log.warn("aircloud_data", tag, "跳过无效字段 field:", item.field_meaning,
                "type:", t, "原因:", reason, "值:", tostring(v))
        else
            out[#out + 1] = item
        end
    end
    return out
end

-- 经纬度缓存
local lat, lng = nil, nil
sys.subscribe("Airlbs_LOCATION_UPDATE", function(new_lat, new_lng)
    lat = new_lat
    lng = new_lng
end)

-- 温湿度缓存
local rtu_temp, rtu_hum = nil, nil
sys.subscribe("TEMP_HUMIDITY_UPDATE", function(temp, humi)
    rtu_temp = temp
    rtu_hum = humi
end)

-- 继电器状态缓存（1-based：元素1 对应通道0 ……），按实际路数动态构造
local relay_state = {}
for i = 1, relay_ctrl.get_channel_count() do relay_state[i] = 0 end
sys.subscribe("RELAY_STATUS_UPDATE", function(new_state)
    if type(new_state) == "table" then
        relay_state = new_state
    end
end)

-- 运维日志辅助函数：写入运维日志（通过 excloud.mtn_log）
-- @param tag string 日志标签
-- @param ... any 日志内容
local function mtn_log(tag, ...)
    local ok, err = pcall(excloud.mtn_log, tag, ...)
    if not ok then
        log.warn("aircloud_data", "运维日志写入失败", err)
    end
end

-- 喂狗辅助：在空中网络业务成功收发时喂网络看门狗
local function feed_watchdog()
    sys.publish("FEED_NETWORK_WATCHDOG")
end

-- ==================== 心跳保活（v2.0 新增） ====================
-- 背景（实测踩坑点）：AirCloud 协议连接流程第 8 步为"启动心跳机制，定期发送心跳"，
--   平台以此维持设备在线状态、并允许向设备下发消息/命令。excloud 库不会自动启动心跳：
--   库 1722~1724 行仅在"心跳此前运行过"（heartbeat_was_running 为真）时才在重连后自动恢复，
--   若应用从未调用过 excloud.start_heartbeat()，则设备永远没有心跳——
--   表现为平台侧设备显示"不在线"，且无法下发消息（本次问题的主因）。
-- 另：v1.8 关闭 auto_reconnect 后，库内 socket 层自动重连（库 2094~2095 行）同时失效，
--   故更依赖应用层心跳 + TCP keepalive 维持长连接活性，避免被运营商 NAT 静默回收。
local HEARTBEAT_INTERVAL_SEC = 120   -- 心跳间隔（秒）；库默认 300，此处缩短以提升在线判定与保活时效

-- 启动/重启云端心跳。
-- 幂等：库内 start_heartbeat() 会先 stop 再重新 start（库 2318~2319 行），
--       因此认证成功回调中每次调用都是安全的（开机认证、重建后重新认证都会走到）。
local function ensure_heartbeat()
    if type(excloud.start_heartbeat) ~= "function" then
        log.warn("aircloud_data", "当前 excloud 库不支持 start_heartbeat, 跳过心跳启动")
        return
    end
    -- 心跳数据必须非空：库 heartbeat() 直接调用 excloud.send(data)（库 2314 行），
    -- 空表会导致心跳包无法构建，故至少携带一个合法字段（时间戳，INTEGER）。
    local hb_data = {
        { field_meaning = excloud.FIELD_MEANINGS.TIMESTAMP, data_type = excloud.DATA_TYPES.INTEGER, value = os.time() },
    }
    local ok, err = pcall(excloud.start_heartbeat, HEARTBEAT_INTERVAL_SEC, hb_data)
    if ok then
        log.info("aircloud_data", "云端心跳已启动, 间隔", HEARTBEAT_INTERVAL_SEC, "秒")
        mtn_log("aircloud", "云端心跳已启动, 间隔 " .. HEARTBEAT_INTERVAL_SEC .. " 秒")
    else
        log.error("aircloud_data", "云端心跳启动失败", err)
    end
end

-- ==================== 事件名与链路状态 ====================
-- 云端下行命令事件名。
-- 用途：excloud.on 的消息回调运行在 socket 回调上下文（非协程），
--       不能在其中直接调用会阻塞等待的接口，因此回调只解析命令并发布本事件，
--       由独立协程任务接收后执行并回传应答。
local AIRCLOUD_CMD_EVENT = "AIRCLOUD_CONTROL_CMD"

-- 云端链路重建请求事件（仅由 request_reconnect 发布，保证单一入口）
local AIRCLOUD_RECONNECT_EVENT = "AIRCLOUD_RECONNECT"

-- 云端认证成功事件（由 auth_result 回调发布，各处等待统一使用 sys.waitUntil）
local AIRCLOUD_AUTH_OK_EVENT = "AIRCLOUD_AUTH_OK"

-- 立即上报事件（链路重建并认证完成后触发一次，便于快速验证恢复情况）
local REPEAT_REPORT_EVENT = "AIRCLOUD_REPORT_NOW"

-- 云端认证是否已成功。周期上报任务以此为准，避免首包在网络/认证未就绪时白丢。
local auth_ok = false

-- 最近一次"成功通信"的时间戳（连接成功/认证成功/收到消息/上报成功都会刷新）。
-- 通信健康监控以此判断链路是否假死。
local last_ok_time = os.time()

-- 重建状态机（单一责任人模型的核心状态）
local reconnecting = false        -- 互斥标志：连接管理器是否正执行 close → open → 等认证 全过程
local reconnect_pending = false   -- 是否有待处理的重建请求（请求去重）
local reconnect_fail = 0          -- 连续重建失败次数（用于指数退避）
local last_reconnect_time = 0     -- 上次重建开始时间（os.time，与 last_ok_time 同源）

-- 重建最小间隔（秒）：窗口内的非强制重建请求一律忽略，抑制抖动触发的重复建连。
-- 注：必须使用 os.time()（墙上时间），os.clock() 是进程 CPU 时间，不可用于计时判断。
local RECONNECT_COOLDOWN = 5

-- 重建失败指数退避序列（秒），封顶 60 秒，避免异常场景下高频重建
local BACKOFF_TABLE = { 5, 10, 20, 40, 60 }

-- 重建类运维日志节流间隔（秒）：频繁重建时避免反复写 flash / 消耗平台额度
local MTN_LOG_MIN_INTERVAL = 60
local last_reconnect_mtn_log = 0

-- 依据当前连续失败次数，计算下一次重试的退避时长
-- @return number 退避秒数
local function backoff_delay()
    local idx = reconnect_fail + 1
    if idx > #BACKOFF_TABLE then
        idx = #BACKOFF_TABLE
    end
    return BACKOFF_TABLE[idx]
end

-- 请求重建云端连接（统一的"重建入口"，可被网卡监听、上报失败、断链事件、健康监控等多处调用）
-- 说明：本函数只做"投递"，绝不直接操作连接；真正的 close() + open() 只由连接管理器执行。
-- @param reason string 触发原因（写入日志与运维日志，便于追溯）
-- @param force  boolean 为 true 时无视冷却窗口（仅健康监控等兜底路径使用）
local function request_reconnect(reason, force)
    -- 已有请求在排队，或连接管理器正在重建：直接忽略，避免并发建连互踩
    if reconnect_pending or reconnecting then
        log.info("aircloud_data", "重建进行中, 忽略重建请求:", reason)
        return
    end
    local st = excloud.status() or {}
    if not st.is_open then
        -- 服务尚未开启（开机阶段），无需重建，交给正常启动流程处理
        return
    end
    -- 冷却窗口校验（使用 os.time() 墙上时间，与 last_ok_time 同源）
    if not force and (os.time() - last_reconnect_time) < RECONNECT_COOLDOWN then
        log.info("aircloud_data", "重建冷却中, 忽略重建请求:", reason)
        return
    end
    reconnect_pending = true
    last_reconnect_time = os.time()
    log.warn("aircloud_data", "请求重建云端连接:", reason)
    -- 运维日志节流：重建可能高频反复，60 秒内最多写一条，避免反复写 flash
    if os.time() - last_reconnect_mtn_log >= MTN_LOG_MIN_INTERVAL then
        last_reconnect_mtn_log = os.time()
        mtn_log("aircloud", "重建云端连接:" .. tostring(reason))
    end
    sys.publish(AIRCLOUD_RECONNECT_EVENT)
end

-- excloud 事件回调
excloud.on(function(event, data)
    -- 降噪：事件回调触发频繁（心跳/收发/连接结果），降为 debug 级别，避免日志刷屏
    log.debug("aircloud_data", "事件", event, json.encode(data))

    if event == "connect_result" then
        if data.success then
            log.info("aircloud_data", "连接成功")
            mtn_log("aircloud", "aircloud 连接成功")
            last_ok_time = os.time()
            feed_watchdog()
        else
            log.warn("aircloud_data", "连接失败: " .. (data.error or "未知错误"))
        end
    elseif event == "auth_result" then
        if data.success then
            log.info("aircloud_data", "认证成功")
            mtn_log("aircloud", "aircloud 认证成功")
            auth_ok = true          -- 允许周期上报任务开始发送
            last_ok_time = os.time()
            feed_watchdog()
            -- 【v2.0 关键修复】启动/重启云端心跳：平台依靠心跳维持设备"在线"状态，
            -- 没有心跳时平台会判定设备离线，从而无法下发消息/命令。
            -- 开机首次认证与重建后重新认证都会走到这里，保证心跳始终在运行。
            ensure_heartbeat()
            -- 事件驱动：唤醒连接管理器（等重建认证）与上报任务（等发送时机），替代各处轮询等待
            sys.publish(AIRCLOUD_AUTH_OK_EVENT)
        else
            log.warn("aircloud_data", "认证失败: " .. (data.message or "?"))
        end
    elseif event == "disconnect" then
        -- 补齐断链即时响应：关闭库自带重连（auto_reconnect = false）后，
        -- 断链必须由应用层感知并请求重建，否则链路将一直处于断开状态。
        log.warn("aircloud_data", "链路已断开")
        auth_ok = false
        request_reconnect("链路断开事件")
    elseif event == "message" then
        log.info("aircloud_data", "收到消息, seq:", data.header and data.header.sequence_num)
        last_ok_time = os.time()
        feed_watchdog()
        for _, tlv in ipairs(data.tlvs or {}) do
            -- 兼容平台两种下行方式：
            --   CONTROL_COMMAND(19) 平台"控制命令"
            --   IRTU_DOWN(21)       平台"透传消息"/iRTU 透传控制指令
            if tlv.field == excloud.FIELD_MEANINGS.CONTROL_COMMAND
                or tlv.field == excloud.FIELD_MEANINGS.IRTU_DOWN then
                local ok, cmd = pcall(json.decode, tostring(tlv.value))
                if not ok or type(cmd) ~= "table" or not cmd.type then
                    log.warn("aircloud_data", "无效命令:", tostring(tlv.value))
                else
                    log.info("aircloud_data", "收到命令:", cmd.type)
                    mtn_log("aircloud", "收到命令:" .. cmd.type)
                    -- 不在回调中执行命令：本回调运行在 socket 回调上下文（非协程），
                    -- 而继电器命令会走 comm_core → exmodbus → sys.waitUntil 阻塞等待串口响应，
                    -- 在非协程中 yield 会触发 "attempt to yield from outside a coroutine"，
                    -- 进而 Lua VM 退出并重启。此处只投递事件，由协程任务执行。
                    sys.publish(AIRCLOUD_CMD_EVENT, cmd)
                end
            end
        end
    elseif event == "send_result" then
        -- 【v2.1 关键修复】发送结果回调：这是"链路已死"最可靠的信号。
        -- 实测日志：心跳构建成功后抛
        --   {"sequence_num":4,"success":false,"error_msg":"TCP connection not available"}
        -- 该错误由库 2206 行（TCP 分支 is_connected / connection 判定失败）产生，
        -- 说明底层 socket 已不可用；若应用层不处理本回调，就无人重建链路，
        -- 表现为平台侧设备一直"不在线"、无法下发消息（本次问题主因）。
        if data.success then
            -- 心跳/上报/应答只要有任意一条发送成功，即视为通信正常
            last_ok_time = os.time()
            feed_watchdog()
        else
            local emsg = tostring(data.error_msg or "")
            log.warn("aircloud_data", "发送失败", emsg, "seq:", data.sequence_num)
            -- 仅对"链路不可用"类错误触发重建；字段构建失败等业务类错误不重建
            -- （业务类失败由上报任务自身的 30 秒快速重试处理，避免无谓重建）
            if string.find(emsg, "not available", 1, true)
                or string.find(emsg, "not connected", 1, true) then
                auth_ok = false
                request_reconnect("发送失败(链路不可用): " .. emsg, true)
            end
        end
    end
end)

-- 等待默认网卡稳定：连续 stable_s 秒 socket.dft() 保持不变，即视为稳定。
-- 目的：开机时 4G 往往先就绪，随后 exnetif 会按优先级切到以太网/WiFi；
--       若在切换之前建立 TCP 连接，切网会关闭该 socket，导致云端连接进入假死状态。
-- @param max_wait_s number 最长等待秒数（防止网络反复抖动时死等）
-- @param stable_s   number 需要连续稳定的秒数
-- @return number 稳定时的默认网卡编号
local function wait_default_adapter_stable(max_wait_s, stable_s)
    local last = socket.dft()
    local stable, waited = 0, 0
    while stable < stable_s and waited < max_wait_s do
        sys.wait(1000)
        waited = waited + 1
        local cur = socket.dft()
        if cur == last then
            stable = stable + 1
        else
            log.info("aircloud_data", "默认网卡变化", last, "->", cur, "稳定计时重新开始")
            last = cur
            stable = 0
        end
    end
    return last
end

-- ==================== 云端链路连接管理器（唯一的重建责任人） ====================
-- 背景：excloud 建立的 socket 绑定在当时的默认网卡上。开机时 4G 往往先就绪，
--       随后 exnetif 会按优先级切到以太网/WiFi，切换动作会关闭旧 socket；
--       而 excloud 在这种被动关闭路径下不会自动重连（不回调、不重建），
--       导致链路假死——表现为后续 excloud.send 一直返回
--       "TCP connection not available"，且日志再无任何 [excloud] 收发记录。
-- 职责：接收所有来源的重建请求 → 等默认网卡稳定 → close() + open() → 等认证事件 → 成功则触发验证上报。
-- 关键：全程持有 reconnecting 互斥标志，保证同一时刻只有一个重建流程在跑（杜绝并发 open 互踩）。
-- 说明：excloud.close() 会复位 is_open/is_connected（库内 2128~2129 行），故 close() + open() 是可靠的重建方式。
sys.taskInit(function()
    while true do
        sys.waitUntil(AIRCLOUD_RECONNECT_EVENT)
        reconnect_pending = false
        reconnecting = true                                  -- 进入互斥区
        -- 等默认网卡稳定，避免刚重建又被切网断开；同时把 IP_READY 自愈事件挡在建连之前
        local adapter = wait_default_adapter_stable(30, 5)
        log.info("aircloud_data", "开始重建云端连接, 默认网卡 =", adapter)
        auth_ok = false                                      -- 重建后需重新认证，先清认证标志
        pcall(excloud.close)
        sys.wait(500)
        local ok, err = excloud.open()
        local authenticated = false
        if ok then
            log.info("aircloud_data", "云端连接已重建, 等待重新认证")
            -- 事件驱动等待认证（open() 异步：先建 TCP、再发鉴权、最后回调 auth_result），
            -- 取代原先的 while + sys.wait(1000) 轮询，避免被其它流程打断后白等。
            -- 【v2.2】先判快照：sys.waitUntil 的消息不留存（publish 时若无人正在等待即丢弃），
            -- 若 auth_result 恰好在进入等待之前完成，这里会白等 20 秒 → 误判重建失败 →
            -- 退避重试再建一次 → 多产生一条鉴权。
            if auth_ok or sys.waitUntil(AIRCLOUD_AUTH_OK_EVENT, 20000) then
                authenticated = true
            end
        else
            log.error("aircloud_data", "云端连接重建失败", err)
        end
        reconnecting = false                                 -- 退出互斥区（先释放，再决定是否重试）

        if authenticated then
            reconnect_fail = 0
            last_ok_time = os.time()
            log.info("aircloud_data", "重建后重新认证成功, 触发一次上报验证")
            sys.publish(REPEAT_REPORT_EVENT)
        else
            -- 指数退避后自动重试一次（直接重新投递，不受冷却窗口限制）
            local delay = backoff_delay()
            reconnect_fail = reconnect_fail + 1
            log.warn("aircloud_data", "重建未成功, 退避", delay, "秒后重试")
            sys.wait(delay * 1000)
            reconnect_pending = true
            last_reconnect_time = os.time()
            sys.publish(AIRCLOUD_RECONNECT_EVENT)
        end
    end
end)

-- 默认网卡变化监听：默认网卡切换（经滞回确认）后请求重建云端连接。
-- 滞回设计：连续 2 次采样（约 4 秒）不同才认定真切换，避免切换过程中的横跳反复触发；
--           切换后静默 30 秒，等 exnetif 稳定并让重建流程独占执行。
sys.taskInit(function()
    local last = socket.dft()
    local same_cnt = 0
    while true do
        sys.wait(2000)
        local cur = socket.dft()
        if cur == last then
            same_cnt = 0
        else
            same_cnt = same_cnt + 1
            if same_cnt >= 2 then
                log.info("aircloud_data", "默认网卡切换", last, "->", cur)
                request_reconnect("默认网卡切换 " .. tostring(last) .. "->" .. tostring(cur))
                last, same_cnt = cur, 0
                sys.wait(30000)          -- 切换后静默 30 秒，等 exnetif 稳定
                last = socket.dft()      -- 以静默期后的实际网卡为新基准
            end
        end
    end
end)

-- 周期上报任务（每 3 分钟）
sys.taskInit(function()
    -- 等待网络就绪（最长 60 秒），避免在网络未就绪时启动 excloud 服务
    sys.waitUntil("IP_READY", 60000)
    -- 等默认网卡稳定后再建连，从源头避免"建连后被切网"导致连接假死
    local adapter = wait_default_adapter_stable(30, 5)
    log.info("aircloud_data", "默认网卡已稳定, adapter =", adapter)
    sys.wait(500)

    -- 初始化 AirCloud 连接（启用运维日志：4块，追加写入方式）
    local ok, err = excloud.setup({
        transport = "tcp",               -- 传输协议（device_type 已由库自动判断，无需配置）
        auto_reconnect = false,          -- 关键：关闭库自带重连，避免与连接管理器形成双责任人（重复建连 → 重复鉴权）
        -- 【v2.0】TCP 层 keepalive：关闭 auto_reconnect 后，库内 socket 层自动重连
        -- （库 2094~2095 行 autoreconn）同时失效，长连接被运营商 NAT 静默回收将无人感知；
        -- 开启 TCP keepalive 由协议栈主动探测死链，配合 disconnect 事件 + 健康监控快速重建。
        keep_idle = 60,                  -- 空闲 60 秒后开始保活探测
        keep_interval = 20,              -- 探测间隔 20 秒
        keep_cnt = 3,                    -- 连续 3 次无响应即判定链路断开
        mtn_log_enabled = true,          -- 启用运维日志
        mtn_log_blocks = 4,              -- 运维日志每个文件块数
        mtn_log_write_way = excloud.MTN_LOG_ADD_WRITE, -- 追加写入方式
    })
    if not ok then
        log.error("aircloud_data", "excloud.setup 失败", err)
    else
        log.info("aircloud_data", "excloud.setup 初始化成功")
        mtn_log("aircloud", "excloud.setup 初始化成功")
    end

    -- 开启 excloud 服务（必须调用！否则 excloud.send 全部返回"excloud服务未开启"）
    local ok_open, err_open = excloud.open()
    if not ok_open then
        log.error("aircloud_data", "excloud.open 失败", err_open)
    else
        log.info("aircloud_data", "excloud.open 服务已开启")
        mtn_log("aircloud", "excloud 服务已开启")
    end

    -- 等待云端认证成功后再开始周期上报（最多 60 秒）
    -- 目的：避免网络/认证尚未就绪时发出必然失败的"开机首包"
    if not auth_ok then
        sys.waitUntil(AIRCLOUD_AUTH_OK_EVENT, 60000)
    end
    if not auth_ok then
        log.warn("aircloud_data", "等待云端认证超时, 仍启动上报任务")
    end

    local retry_soon = false   -- 本轮上报失败标记：置位后仅等 30 秒即快速重试

    while true do
        repeat
        -- 发送前确认云端链路与认证均已就绪：
        -- 重建/切网/断链后 auth_ok 会被清 false，此时发送必然返回"未连接到服务器"。
        -- 这里等待认证事件（最长 20 秒），仍未就绪则跳过本轮上报，
        -- 避免"发送失败 → 触发重建 → 又发送失败"的快速循环。
        local st = excloud.status() or {}
        local link_ok = st.is_open and st.is_connected and (st.is_authenticated ~= false) and auth_ok
        if not link_ok then
            log.info("aircloud_data", "云端链路未就绪, 等待认证事件")
            sys.waitUntil(AIRCLOUD_AUTH_OK_EVENT, 20000)
        end
        if not auth_ok then
            log.warn("aircloud_data", "云端认证未就绪, 跳过本轮上报")
            break
        end

        -- 实时读取系统级数据
        local rssi = mobile.csq() or 0
        local iccid = mobile.iccid() or ""

        -- CPU 温度 / VBAT 电压
        local cpu_temp = 0
        local vbat = 0
        pcall(function()
            adc.open(adc.CH_CPU); cpu_temp = (adc.get(adc.CH_CPU) or 0) / 1000; adc.close(adc.CH_CPU)
            adc.open(adc.CH_VBAT); vbat = (adc.get(adc.CH_VBAT) or 0) / 1000; adc.close(adc.CH_VBAT)
        end)

        local _lat = lat or ""
        local _lng = lng or ""
        -- 温湿度：直接取缓存值（尚未采集到时为 nil，由 filter_valid_tlvs 剔除该字段），
        -- 不再用 or 0 兜底 —— 否则传感器异常时会向平台上报 0℃/0%RH，触发误告警
        local _rtu_temp = rtu_temp
        local _rtu_hum = rtu_hum

        -- 组 TLV 数组
        local tlv_list = {
            { field_meaning = excloud.FIELD_MEANINGS.SIGNAL_STRENGTH_4G, data_type = excloud.DATA_TYPES.INTEGER, value = rssi },
            { field_meaning = excloud.FIELD_MEANINGS.SIM_ICCID,           data_type = excloud.DATA_TYPES.ASCII,   value = iccid },
            { field_meaning = excloud.FIELD_MEANINGS.TEMPERATURE,         data_type = excloud.DATA_TYPES.FLOAT,   value = _rtu_temp },
            { field_meaning = excloud.FIELD_MEANINGS.HUMIDITY,            data_type = excloud.DATA_TYPES.FLOAT,   value = _rtu_hum },
            { field_meaning = excloud.FIELD_MEANINGS.ENV_TEMPERATURE,     data_type = excloud.DATA_TYPES.INTEGER, value = cpu_temp },
            { field_meaning = excloud.FIELD_MEANINGS.VOLTAGE,             data_type = excloud.DATA_TYPES.INTEGER, value = vbat },
            { field_meaning = excloud.FIELD_MEANINGS.GNSS_LONGITUDE,      data_type = excloud.DATA_TYPES.ASCII,   value = _lng },
            { field_meaning = excloud.FIELD_MEANINGS.GNSS_LATITUDE,       data_type = excloud.DATA_TYPES.ASCII,   value = _lat },
            -- 继电器状态（自定义字段 268，ASCII 字符串，逗号分隔：'1'=吸合、'0'=断开）
            -- 例：4 路 "1,1,0,0"；8 路自动变长 "1,1,0,0,0,0,0,0"（字段个数即路数）
            { field_meaning = RELAY_STATUS_FIELD,                          data_type = excloud.DATA_TYPES.ASCII,   value = relay_state_to_string(relay_state) },
        }

        -- 【v1.9 关键修复】发送前过滤掉无法编码的字段。
        -- 原因：excloud.send 只要有一个字段构建失败就整包返回 false，
        --       会使该轮全部数据（含温湿度）一起丢失——表现为平台长时间收不到数据、
        --       或"只零星上报过一两次"。典型触发：GNSS 未定位时经纬度为空串。
        local tlv_valid = filter_valid_tlvs(tlv_list, "周期上报")
        if #tlv_valid == 0 then
            log.warn("aircloud_data", "本轮无可上报的有效字段, 跳过")
            break
        end

        local send_ok, err_msg = excloud.send(tlv_valid, false)
        if send_ok then
            log.info("aircloud_data", "上报成功, 有效字段数", #tlv_valid, "/", #tlv_list)
            last_ok_time = os.time()
            feed_watchdog()
        else
            log.warn("aircloud_data", "上报失败", err_msg)
            -- 失败后 30 秒快速重试一次（不重建链路），避免一次失败就延后 3 分钟
            retry_soon = true
            -- 仅在链路确实不可用时才请求重建（链路正常时的偶发失败不重建，避免无谓的重复建连/重复鉴权）
            local st2 = excloud.status() or {}
            if not (st2.is_open and st2.is_connected and st2.is_authenticated) then
                request_reconnect("上报失败:" .. tostring(err_msg))
            end
        end

        until true

        -- 每 3 分钟上报一次（降低平台测试版每日上行消息额度消耗）；
        -- 若收到立即上报请求（如链路重建并认证完成）则提前上报，便于快速验证恢复情况；
        -- 若本轮上报失败，则 30 秒后快速重试一次，避免数据被延后整整一个上报周期。
        local wait_ms = 180000
        if retry_soon then
            wait_ms = 30000
            retry_soon = false
        end
        sys.waitUntil(REPEAT_REPORT_EVENT, wait_ms)
    end
end)

-- ==================== 云端命令执行任务 ====================
-- 背景：excloud.on 的消息回调运行在 socket 回调上下文（非协程），
--       在其中执行继电器命令会走 comm_core → exmodbus → sys.waitUntil 阻塞等待，
--       因不能在非协程中 yield，会报 "attempt to yield from outside a coroutine"，
--       进而 Lua VM 退出并重启（实测踩坑点）。
-- 对策：消息回调只解析命令并发布 AIRCLOUD_CMD_EVENT；
--       本任务在协程上下文中接收事件，执行命令并回传应答。
sys.taskInit(function()
    while true do
        local _, cmd = sys.waitUntil(AIRCLOUD_CMD_EVENT)
        if type(cmd) == "table" and cmd.type then
            -- 构建应答
            local resp = { cmd = cmd.type }
            if cmd.type == "read_all" then
                adc.open(adc.CH_CPU); resp.cpu_temp = (adc.get(adc.CH_CPU) or 0) / 1000; adc.close(adc.CH_CPU)
                adc.open(adc.CH_VBAT); resp.vbat = (adc.get(adc.CH_VBAT) or 0) / 1000; adc.close(adc.CH_VBAT)
                resp.temperature = rtu_temp or 0; resp.humidity = rtu_hum or 0
                resp.latitude = lat or ""; resp.longitude = lng or ""
                resp.csq = mobile.csq() or 0; resp.imei = mobile.imei() or ""; resp.iccid = mobile.iccid() or ""
                resp.relay = relay_state
                resp.timestamp = os.time()
            elseif cmd.type == "relay_open" then
                local ch = cmd.channel or 0
                local ok_exec = relay_ctrl.open(ch)
                resp.relay = relay_ctrl.get_state()
                resp.result = ok_exec and "success" or "fail"
                resp.channel = ch
            elseif cmd.type == "relay_close" then
                local ch = cmd.channel or 0
                local ok_exec = relay_ctrl.close(ch)
                resp.relay = relay_ctrl.get_state()
                resp.result = ok_exec and "success" or "fail"
                resp.channel = ch
            elseif cmd.type == "relay_toggle" then
                local ch = cmd.channel or 0
                local ok_exec = relay_ctrl.toggle(ch)
                resp.relay = relay_ctrl.get_state()
                resp.result = ok_exec and "success" or "fail"
                resp.channel = ch
            elseif cmd.type == "relay_all_open" then
                local ok_exec = relay_ctrl.all_open()
                resp.relay = relay_ctrl.get_state()
                resp.result = ok_exec and "success" or "fail"
            elseif cmd.type == "relay_all_close" then
                local ok_exec = relay_ctrl.all_close()
                resp.relay = relay_ctrl.get_state()
                resp.result = ok_exec and "success" or "fail"
            elseif cmd.type == "relay_read" then
                local st = relay_ctrl.read_status()
                resp.relay = st or relay_ctrl.get_state()
                resp.result = st and "success" or "fail"
            elseif cmd.type == "read_temp" then
                resp.temperature = rtu_temp or 0
            elseif cmd.type == "read_humi" then
                resp.humidity = rtu_hum or 0
            elseif cmd.type == "read_vbat" then
                adc.open(adc.CH_VBAT); resp.vbat = (adc.get(adc.CH_VBAT) or 0) / 1000; adc.close(adc.CH_VBAT)
            elseif cmd.type == "read_cpu" then
                adc.open(adc.CH_CPU); resp.cpu_temp = (adc.get(adc.CH_CPU) or 0) / 1000; adc.close(adc.CH_CPU)
            elseif cmd.type == "read_csq" then
                resp.csq = mobile.csq() or 0
            elseif cmd.type == "read_iccid" then
                resp.iccid = mobile.iccid() or ""
            elseif cmd.type == "read_time" then
                resp.timestamp = os.time()
            else
                resp = { error = "未知命令", cmd = cmd.type or "" }
            end

            -- 应答回传（CONTROL_RESPONSE, ASCII）
            -- 同样走字段有效性过滤：避免空值字段导致整包应答发送失败
            log.info("aircloud_data", "命令执行完成, 应答:", json.encode(resp))
            local resp_tlv = filter_valid_tlvs({
                { field_meaning = excloud.FIELD_MEANINGS.CONTROL_RESPONSE, data_type = excloud.DATA_TYPES.ASCII, value = json.encode(resp) },
            }, "命令应答")
            if #resp_tlv > 0 then
                excloud.send(resp_tlv, false)
            else
                log.warn("aircloud_data", "命令应答无有效字段, 未发送")
            end
            feed_watchdog()
        end
    end
end)

-- ==================== 通信健康监控（纯看门狗，只投递重建请求） ====================
-- 背景：excloud 在 socket.CLOSED（如建连后默认网卡切换导致底层 socket 被关闭）时，
--       只清理连接对象，既不把 is_connected 置 false，也不安排重连，
--       于是 excloud.status() 一直"看起来正常"，但实际已无 socket，永远不会自愈。
-- 对策：记录最近一次成功通信时间；超过 IDLE_TIMEOUT 仍无任何成功通信，
--       即判定链路假死，投递"强制重建"请求（force 绕过冷却窗口）。
-- 注：本任务不再自行 close()/open()，全部交由连接管理器执行，
--     避免与重建流程并发操作连接（这是 v1.7 重复鉴权的主因之一）。
local IDLE_TIMEOUT = 4 * 60   -- 秒。周期上报间隔为 180 秒，超时即判定为假死
local CHECK_PERIOD = 60       -- 秒。健康检查周期

sys.taskInit(function()
    sys.wait(60000)   -- 开机先给 1 分钟建连与认证时间，避免误判
    while true do
        local st = excloud.status() or {}
        local idle = os.time() - last_ok_time
        if st.is_open and idle >= IDLE_TIMEOUT then
            log.warn("aircloud_data", "云端通信已", idle, "秒无成功记录, 判定链路假死")
            mtn_log("aircloud", "云端通信假死, 强制重连")
            last_ok_time = os.time()   -- 重置计时，避免同一故障被反复触发
            request_reconnect("健康监控: " .. idle .. " 秒无成功通信", true)
        end
        sys.wait(CHECK_PERIOD * 1000)
    end
end)

-- ==================== 云端链路活性巡检（v2.1 新增，秒级发现假死） ====================
-- 背景（实测踩坑点）：底层 socket 被动失效时（典型：建连后默认网卡被 exnetif 切换、
--   长连接被运营商 NAT 静默回收），excloud 走 socket.CLOSED 分支只 cleanup_connection()
--   （库 1752~1753 行）——既不回调 disconnect，也不安排重连，状态位还可能仍显示"已连接"。
--   此时库心跳持续失败并抛 "TCP connection not available"（库 2206 行），
--   表现为平台侧设备"不在线"、无法下发消息，且长时间不自愈。
-- 与既有机制的分工：
--   ① send_result 回调（见上方 excloud.on）—— 心跳/上报失败时立即触发重建（最快路径）；
--   ② 本巡检任务 —— 兜住"状态位直接异常"与"状态位假活且恰好无发送失败"两种情况；
--   ③ 通信健康监控（上方 IDLE_TIMEOUT 4 分钟）—— 最外层兜底。
-- 巡检策略（只投递请求，绝不自行 close()/open()，保持单一重建责任人模型）：
--   - 状态位异常（is_connected 为假 / is_authenticated 为假）→ 立即强制重建；
--   - 状态位正常但"无成功通信"超过 150 秒（正常链路上 120 秒一次的心跳必然刷新
--     last_ok_time，故不会走到此分支）→ 主动 heartbeat() 探测一次，失败即强制重建。
--   正常链路上巡检不产生任何额外上行报文，不增加平台消息额度消耗。
local PROBE_IDLE_SEC = 150       -- 无成功通信超过该秒数则主动探测一次
local PATROL_PERIOD_MS = 30000   -- 巡检周期（毫秒）

sys.taskInit(function()
    local last_probe_time = 0
    sys.wait(90000)   -- 开机先给建连、认证与首次心跳留出时间，避免误判
    while true do
        local st = excloud.status() or {}
        if st.is_open and (not st.is_connected or st.is_authenticated == false) then
            log.warn("aircloud_data", "链路巡检: 状态异常 is_connected =", st.is_connected,
                "is_authenticated =", st.is_authenticated)
            auth_ok = false
            request_reconnect("链路巡检: 状态位异常", true)
        elseif st.is_open and (os.time() - last_ok_time) > PROBE_IDLE_SEC
            and (os.time() - last_probe_time) > PROBE_IDLE_SEC then
            -- 状态位看起来正常，但长时间没有任何成功通信 → 主动探测，识别"假活"链路
            local idle = os.time() - last_ok_time
            last_probe_time = os.time()
            log.warn("aircloud_data", "链路巡检:", idle, "秒无成功通信, 主动探测心跳")
            local probe_ok = excloud.heartbeat()
            if not probe_ok then
                auth_ok = false
                request_reconnect("链路巡检: 心跳探测失败", true)
            end
        end
        sys.wait(PATROL_PERIOD_MS)
    end
end)
