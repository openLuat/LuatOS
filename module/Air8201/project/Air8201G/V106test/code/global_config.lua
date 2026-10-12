--[[
@module  global_config
@summary 全局配置与运行统计（基于 FSKV 持久化）
@version 1.0
@date    2026.05.28
@description
    在 FSKV 区持久化记录设备运行统计信息，主要字段：
      1. boot_time     - 首次联网时间（os.time，秒；冷启动时等 IP_READY+基站对时后写入）
      2. reset_count   - 硬件 reset 或软件重启次数（通过 pm.lastReson() 判断）
      3. report_count  - 数据包总上传次数（心跳/业务上报合计）
      4. tcp_fail_count - TCP 连接失败次数
      5. disconnect_count - 断网次数

    上电开机判定：pm.lastReson() 返回 (0,0,0) 即认定为冷启动上电，会清空 FSKV 并重新初始化。
    其他重启原因（看门狗、软件 reboot、深度睡眠唤醒等）保留历史统计，对应 reset_count + 1。

    依据：
      - fskv API：https://docs.openluat.com/air8201/luatos/app/common/fskv/
      - fskv demo：https://gitee.com/openLuat/LuatOS/tree/master/module/Air8000/demo/fskv/fskv_test.lua
      - pm.lastReson demo：https://gitee.com/openLuat/LuatOS/tree/master/module/Air780EPM/demo/wdt/internal_wdt.lua

@usage
    -- 必须在 main.lua 启动早期调用一次 init（同步阻塞，无需 task）
    local global_config = require "global_config"
    global_config.init()

    -- 业务代码递增计数（每发一个业务/心跳包调用一次）
    global_config.inc_report_count()

    -- TCP 连接失败时递增
    global_config.inc_tcp_fail_count()

    -- 断网时递增
    global_config.inc_disconnect_count()

    -- 读取统计快照（返回 table）
    local stat = global_config.get_stats()
    -- stat.boot_time / stat.reset_count / stat.report_count / stat.tcp_fail_count / stat.disconnect_count
]] local global_config = {}

-- ========== FSKV Key 常量（统一管理，避免散落字符串） ==========
local KEY_BOOT_TIME = "gcfg_boot_time" -- 首次联网时间戳（秒，冷启动后联网+对时才写）
local KEY_RESET_COUNT = "gcfg_reset_count" -- 硬件 reset / 软件重启次数
local KEY_REPORT_COUNT = "gcfg_report_count" -- 数据包总上传次数（心跳 + 业务）
local KEY_TCP_FAIL_COUNT = "gcfg_tcp_fail_count" -- TCP 连接失败次数（建连不成功）
local KEY_TCP_DROP_COUNT = "gcfg_tcp_drop_count" -- TCP 断联次数（已连接被断开）
local KEY_DISCONNECT_COUNT = "gcfg_disconnect_count" -- 断网次数

-- ========== 内部状态 ==========
-- 标记 init 是否成功（不重复初始化）
local initialized = false

-- 标记本次启动是否为"冷启动"（pm.lastReson() = 0,0,0）
-- 仅冷启动时才会在首次联网后写 boot_time；其他重启原因保留 FSKV 中的旧值不动
local is_cold_boot_flag = false

-- 标记 boot_time 是否已通过"首次联网"事件写入过（防重复）
local boot_time_recorded = false

-- 等待 IP_READY 后多少毫秒再读 os.time()（给基站对时留缓冲）
-- 合宙官方文档：移动/电信卡通常会自动下发基站时间，无需 SNTP
-- 但下发到 RTC 生效需要短暂时间，保险起见等 3 秒
local CELL_TIME_SYNC_WAIT_MS = 3000

-- ========== 内部辅助函数 ==========

-- 安全读取整数：fskv.get 返回 nil 时回退默认值
-- 这是 fskv 的官方约定：键不存在/获取失败 → 返回 nil
local function get_int(key, default_val)
    local v = fskv.get(key)
    if type(v) == "number" then
        return v
    end
    return default_val
end

-- 安全写入：失败仅打日志（不抛错，避免影响业务）
local function safe_set(key, value)
    local ok = fskv.set(key, value)
    if not ok then
        log.error("GCFG", "fskv.set 失败 key=" .. tostring(key) .. " value=" .. tostring(value))
    end
    return ok
end

-- 判断是否为"冷启动上电"
-- 依据：pm.lastReson() 返回 (r1, r2, r3)，全部为 0 视为冷启动
-- 来源：用户指定 "000 为上电开机"
local function is_cold_boot(r1, r2, r3)
    local n1 = tonumber(r1) or 0
    local n2 = tonumber(r2) or 0
    local n3 = tonumber(r3) or 0
    return n1 == 0 and n2 == 0 and n3 == 0
end

-- ========== 公开接口 ==========

--[[
@api global_config.init()
@summary 初始化 FSKV 区并按重启原因决定是否重建数据
@return boolean 是否初始化成功
@description
    流程：
      1. fskv.init() 初始化数据库
      2. 调用 pm.lastReson() 获取本次开机原因（所有合宙模组都支持，无需 pcall）
      3. 若为冷启动（0,0,0）→ fskv.clear() 清空 + 写初始值（boot_time=0 占位，等联网后异步补写）
      4. 否则视为软重启/看门狗复位等 → 保留历史数据，reset_count + 1
      5. 若冷启动 → 启动异步 task 等待 IP_READY + 基站对时 → 写入真实 boot_time
    幂等：多次调用安全（initialized 标志位保护）
]]
function global_config.init()
    if initialized then
        log.warn("GCFG", "已初始化，跳过重复调用")
        return true
    end

    -- 1. 初始化 fskv（必须最先调用）
    local r = fskv.init()
    log.info("GCFG", "fskv.init 结果=" .. tostring(r))
    if not r then
        log.error("GCFG", "FSKV 初始化失败，统计功能不可用")
        return false
    end

    -- 2. 读取本次开机原因（合宙官方所有模组均支持 pm.lastReson()，无需 pcall）
    local r1, r2, r3 = pm.lastReson()
    log.info("GCFG", "pm.lastReson() ->", "r1=" .. tostring(r1), "r2=" .. tostring(r2), "r3=" .. tostring(r3))

    -- 3. 打印 FSKV 当前状态（已用字节、总字节、KV 条目数）
    local used, total, kv_count = fskv.status()
    log.info("GCFG", "FSKV 状态: used=" .. tostring(used) .. "B", "total=" .. tostring(total) .. "B",
        "kv_count=" .. tostring(kv_count))

    -- 4. 判定冷启动 vs 软重启，决定行为
    if is_cold_boot(r1, r2, r3) then
        -- ===== 冷启动（上电开机）：清空 FSKV 并重新初始化 =====
        log.info("GCFG", "===> 冷启动 (0,0,0)，清空 FSKV 并重建初始数据")

        local cleared = fskv.clear()
        log.info("GCFG", "fskv.clear 结果=" .. tostring(cleared))

        -- ⚠️ 注意：boot_time 不再在此处立即写入！
        -- 改为等首次 IP_READY + 基站对时完成后再写真实 UTC 时间
        -- 此时仅写入占位 0，由 wait_first_network_task() 异步补写
        safe_set(KEY_BOOT_TIME, 0)
        safe_set(KEY_RESET_COUNT, 0) -- 冷启动 reset_count 也归零
        safe_set(KEY_REPORT_COUNT, 0)
        safe_set(KEY_TCP_FAIL_COUNT, 0)
        safe_set(KEY_TCP_DROP_COUNT, 0)
        safe_set(KEY_DISCONNECT_COUNT, 0)

        -- 标记本次为冷启动，启动联网监听 task
        is_cold_boot_flag = true
        boot_time_recorded = false

        log.info("GCFG", "冷启动初始化完成，boot_time 待联网后异步写入，其他计数器归零")
    else
        -- ===== 非冷启动（看门狗 / 软 reboot / 唤醒等）：保留历史，reset_count + 1 =====
        log.info("GCFG", "===> 非冷启动 (" .. tostring(r1) .. "," .. tostring(r2) .. "," .. tostring(r3) ..
            ")，保留历史统计，reset_count + 1")

        -- ⚠️ 注意：非冷启动严禁修改 boot_time，必须保留 FSKV 中的原值
        -- 如果旧固件升级上来导致 KEY_BOOT_TIME 缺失，仅补占位 0（不写当前时间）
        if get_int(KEY_BOOT_TIME, nil) == nil then
            log.warn("GCFG", "boot_time 缺失，补占位 0（非冷启动不写真实时间）")
            safe_set(KEY_BOOT_TIME, 0)
        end

        local old_reset = get_int(KEY_RESET_COUNT, 0)
        safe_set(KEY_RESET_COUNT, old_reset + 1)
        log.info("GCFG", "reset_count: " .. old_reset .. " -> " .. (old_reset + 1))

        -- 其他计数器（report_count / tcp_fail / disconnect）保持原值，不动
        -- 若缺失则补 0
        if get_int(KEY_REPORT_COUNT, nil) == nil then
            safe_set(KEY_REPORT_COUNT, 0)
        end
        if get_int(KEY_TCP_FAIL_COUNT, nil) == nil then
            safe_set(KEY_TCP_FAIL_COUNT, 0)
        end
        if get_int(KEY_TCP_DROP_COUNT, nil) == nil then
            safe_set(KEY_TCP_DROP_COUNT, 0)
        end
        if get_int(KEY_DISCONNECT_COUNT, nil) == nil then
            safe_set(KEY_DISCONNECT_COUNT, 0)
        end

        -- 标记本次为非冷启动，IP_READY 监听 task 将不会写 boot_time
        is_cold_boot_flag = false
        boot_time_recorded = true -- 视为"已记录"（实际是不允许修改），跳过 task 写入
    end

    initialized = true

    -- 5. 仅冷启动：启动异步 task 等待首次联网 + 基站对时，然后写入真实 boot_time
    -- 依据：合宙官方 https://docs.openluat.com/air8201/luatos/app/socket/tcp/ chunk_id=42
    --       "模组上电以后固件内部联网成功以后会自动发布 sys.publish(\"IP_READY\")"
    -- 依据：合宙官方 NTP 文档 https://docs.openluat.com/atmozu/product/command/ntp/
    --       "对于 Air780EP/移动/电信卡, 通常会下发基站时间, 同步时间并不是必要的"
    if is_cold_boot_flag and not boot_time_recorded then
        sys.taskInit(function()
            log.info("GCFG", "[BOOT_TIME] 等待 IP_READY 以获取首次联网+基站对时时间...")
            while not socket.adapter(socket.dft()) do
                log.warn("excloud_task_func", "wait IP_READY", socket.dft())
                -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
                -- 或者等待1秒超时退出阻塞等待状态;
                -- 注意：此处的1000毫秒超时不要修改的更长；
                -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
                -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
                -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
                sys.waitUntil("IP_READY", 5000)
            end
            log.info("GCFG", "[BOOT_TIME] 已联网 (IP_READY)，等待基站对时 " .. CELL_TIME_SYNC_WAIT_MS ..
                "ms 让 RTC 同步...")
            sys.wait(CELL_TIME_SYNC_WAIT_MS)

            -- 二次确认状态（防止 task 启动期间被其他流程改写）
            if boot_time_recorded then
                log.info("GCFG", "[BOOT_TIME] 已被其他流程记录，跳过")
                return
            end

            local network_time = os.time()
            safe_set(KEY_BOOT_TIME, network_time)
            boot_time_recorded = true
            log.info("GCFG",
                "[BOOT_TIME] 首次联网时间已写入 FSKV: " .. network_time .. " (" ..
                    os.date("%Y-%m-%d %H:%M:%S", network_time) .. ")")
        end)
    end

    log.info("GCFG", "global_config 初始化完成 (cold_boot=" .. tostring(is_cold_boot_flag) .. ")")
    return true
end

--[[
@api global_config.inc_report_count()
@summary 数据包总上传次数 +1（业务包 + 心跳包合计）
@return number 递增后的最新值
]]
function global_config.inc_report_count()
    if not initialized then
        log.warn("GCFG", "未初始化，inc_report_count 被忽略")
        return 0
    end
    local cur = get_int(KEY_REPORT_COUNT, 0) + 1
    safe_set(KEY_REPORT_COUNT, cur)
    return cur
end

--[[
@api global_config.inc_tcp_fail_count()
@summary TCP 连接失败次数 +1
@return number 递增后的最新值
]]
function global_config.inc_tcp_fail_count()
    if not initialized then
        log.warn("GCFG", "未初始化，inc_tcp_fail_count 被忽略")
        return 0
    end
    local cur = get_int(KEY_TCP_FAIL_COUNT, 0) + 1
    safe_set(KEY_TCP_FAIL_COUNT, cur)
    log.info("GCFG", "TCP 连接失败次数 -> " .. cur)
    return cur
end

--[[
@api global_config.inc_tcp_drop_count()
@summary TCP 断联次数 +1（已连接的 TCP 链路被断开）
@return number 递增后的最新值
]]
function global_config.inc_tcp_drop_count()
    if not initialized then
        log.warn("GCFG", "未初始化，inc_tcp_drop_count 被忽略")
        return 0
    end
    local cur = get_int(KEY_TCP_DROP_COUNT, 0) + 1
    safe_set(KEY_TCP_DROP_COUNT, cur)
    log.info("GCFG", "TCP 断联次数 -> " .. cur)
    return cur
end

--[[
@api global_config.inc_disconnect_count()
@summary 断网次数 +1
@return number 递增后的最新值
]]
function global_config.inc_disconnect_count()
    if not initialized then
        log.warn("GCFG", "未初始化，inc_disconnect_count 被忽略")
        return 0
    end
    local cur = get_int(KEY_DISCONNECT_COUNT, 0) + 1
    safe_set(KEY_DISCONNECT_COUNT, cur)
    log.info("GCFG", "断网次数 -> " .. cur)
    return cur
end

--[[
@api global_config.get_stats()
@summary 获取当前所有统计字段快照
@return table  含 5 个字段：boot_time / reset_count / report_count / tcp_fail_count / disconnect_count
]]
function global_config.get_stats()
    return {
        boot_time = get_int(KEY_BOOT_TIME, 0),
        reset_count = get_int(KEY_RESET_COUNT, 0),
        report_count = get_int(KEY_REPORT_COUNT, 0),
        tcp_fail_count = get_int(KEY_TCP_FAIL_COUNT, 0),
        tcp_drop_count = get_int(KEY_TCP_DROP_COUNT, 0),
        disconnect_count = get_int(KEY_DISCONNECT_COUNT, 0)
    }
end

--[[
@api global_config.dump_stats()
@summary 打印当前所有统计字段（调试用）
]]
function global_config.dump_stats()
    local s = global_config.get_stats()
    log.info("GCFG", "===== 当前统计快照 =====", "boot_time=" .. s.boot_time, "reset_count=" .. s.reset_count,
        "report_count=" .. s.report_count, "tcp_fail_count=" .. s.tcp_fail_count, "tcp_drop_count=" .. s.tcp_drop_count,
        "disconnect_count=" .. s.disconnect_count)
end

--[[
@api global_config.is_initialized()
@summary 查询是否已初始化（供外部 require 后判断）
@return boolean
]]
function global_config.is_initialized()
    return initialized
end

return global_config
