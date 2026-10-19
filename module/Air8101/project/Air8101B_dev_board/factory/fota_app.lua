--[[
@module  fota_app
@summary FOTA 后台自动升级（libfota3）：无界面版
@version 1.0
@date    2026.10.19
@usage
    local fota = require "fota_app"
    fota.start()        -- 用户模式联网任务里调用一次（幂等）
    fota.status()       -- { stage, msg, progress } 最近一次状态
    fota.check()        -- 手动触发一次检测（调试口 / 产测指令可用）

配置来源：config_*.lua 的 fota 段，fskv 可覆盖单项
    fota.project_key   合宙 IOT 平台 Turnkey 页面获取；留空则只打日志、不联网
    fota.script_name   留空用 _G.PROJECT
    fota.auto          默认 true（每天自动检测一次）
    fota.interval      自动检测间隔秒，默认 86400
    fskv: fota_key / fota_auto("1"/"0") / fota_interval

说明
1. 不传 on_confirm → libfota3 内部默认放行：发现新版本直接下载、刷写、重启，
   所以本机不带屏也能升级；要改成"必须人工确认"时再补 on_confirm。
2. libfota3.request() 内部自己等网络 + 对时（NTP），调用方不必先等 IP；
   用 Auto 定时器，跨重启也按时间戳续上，不会反复下载。
3. 升级结果（upgrade_success / upgrade_fail）由库在下次开机时上报平台，
   日志里看 "fota" 前缀即可。
]]

local libfota3 = require "libfota3"   -- 必须字面量 require，烧录合并器才会打包

local M = {}

local started = false
local st = { stage = "idle", msg = "就绪", progress = 0 }

local function board_cfg()
    return (_G.project_config or {}).fota or {}
end

--- fskv 读取（未初始化/无此键时不抛异常）
local function kv_get(k)
    local ok, v = pcall(fskv.get, k)
    return ok and v or nil
end

-- ===== 配置 =====

function M.key()
    local v = kv_get("fota_key")
    if type(v) == "string" and v ~= "" then return v end
    return tostring(board_cfg().project_key or "")
end

function M.script_name()
    local v = board_cfg().script_name
    if type(v) == "string" and v ~= "" then return v end
    return _G.PROJECT or "unknown"
end

function M.interval()
    local v = tonumber(kv_get("fota_interval") or "")
    return v or tonumber(board_cfg().interval) or 86400
end

function M.auto()
    local v = kv_get("fota_auto")
    if v == "1" then return true end
    if v == "0" then return false end
    return board_cfg().auto ~= false      -- 出厂默认自动检测
end

-- ===== libfota3 回调 =====

local function on_status(status, msg, percent)
    st.stage, st.msg = tostring(status or ""), tostring(msg or "")
    st.progress = tonumber(percent) or st.progress
    log.info("fota", st.stage, st.msg, percent and (percent .. "%") or "")
    sys.publish("FOTA_STATUS", st.stage, st.msg, st.progress)
end

-- ===== 启动 / 查询 =====

function M.start()
    if started then return true end

    local key = M.key()
    if key == "" then
        st.stage, st.msg = "idle", "未配置项目密钥"
        log.warn("fota_app", "未配置 config.fota.project_key，本机不参与远程升级")
        return false
    end

    started = true

    -- Air8101 的 FOTA 设备标识取 WiFi MAC：只用 4G / 以太网时先 init 驱动
    -- （只初始化，不连接，不影响 exnetif 的网卡调度）
    local ok, mac = pcall(wlan.getMac)
    if not ok or not mac or #tostring(mac) < 12 then
        pcall(wlan.init)
    end

    libfota3.request({
        project_key    = key,
        script_name    = M.script_name(),
        script_version = _G.VERSION or "0.0.0",
        auto           = M.auto(),
        interval       = M.interval(),
        on_status      = on_status,
    })

    log.info("fota_app", "libfota3 已启动", M.script_name(), _G.VERSION,
        "auto:", M.auto(), "interval(s):", M.interval())
    return true
end

--- 手动检测一次（有界面/调试口时用；自动检测已开着就不需要调）
function M.check()
    if M.key() == "" then return false, "未配置项目密钥" end

    if not started then
        M.start()
        -- request 后库要先等网络 + 对时，这段 running=true，太早调会被忽略
        sys.taskInit(function()
            sys.wait(3000)
            libfota3.check_update()
        end)
        return true
    end

    libfota3.check_update()
    return true
end

function M.status()
    return st
end

return M
