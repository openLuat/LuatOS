--[[
@module  update
@summary FOTA 升级管理模块（支持 libfota2 / libfota3 双模式）
@version 3.0
@date    2026.07.30
@usage
默认 libfota3（只能合宙人员根据客户提供的IMEI升级，客户无法自行操作），可通过 main.lua 中 FOTA_MODE 变量切换。
客户如需 libfota2（IoT平台自行管理），修改 main.lua 中 FOTA_MODE = 2 后自行烧录源码。
服务器下发指令支持远程切换。

FOTA_MODE 含义：
  3 = libfota3（默认，只能合宙人员根据客户提供的IMEI升级，客户无法自行操作）
  2 = libfota2（IoT平台FOTA，客户自行管理）

服务器下发命令：
  {"command":"update","data":{"params":{}}}          -- 触发升级检查
  {"command":"fota_mode","data":{"params":{"mode":2}}} -- 切换FOTA模式
]]

local update = {}

-- FOTA 模式：3=libfota3(默认,只能合宙人员根据客户IMEI升级), 2=libfota2(IoT平台,客户自行管理)
-- 从 _G 读取，main.lua 中设置 FOTA_MODE = 3
local FOTA_MODE = _G.FOTA_MODE or 3

-- ==================== libfota2 相关 ====================

local libfota2 = require("libfota2")
local fota_running = false

-- libfota2 回调
local function fota2_cb(ret)
    log.info("fota", "libfota2 升级结果:", ret)
    fota_running = false
    sys.publish("FOTA_CHECK_DONE")
    if ret == 0 then
        log.info("fota", "升级包下载成功，重启设备")
        pm.reboot()
    elseif ret == 1 then
        log.warn("fota", "连接失败，请检查网络或服务器配置")
    elseif ret == 2 then
        log.warn("fota", "URL错误")
    elseif ret == 3 then
        log.warn("fota", "服务器断开")
    elseif ret == 4 then
        log.info("fota", "下载失败，可能已是最新版本或升级包缺失")
    elseif ret == 5 then
        log.warn("fota", "版本号格式错误，需使用 xxx.yyy.zzz 格式")
    end
end

-- ==================== libfota3 实例引用 ====================

local libfota3 = require("libfota3")

-- ==================== 公共 API ====================

-- 初始化：启动 FOTA（开机即执行，与工作模式无关）
-- request() 会配置 opts(含project_key) 并启动定时器；
-- 首次运行(last_ts=0)且时间同步成功时，内部 setup_timer 会立即触发一次检测，之后每 interval 秒一次
function update.init()
    -- 无条件打印当前版本号（无论是否升级、何种模式）
    log.info("update", "===== 当前固件版本:", _G.PROJECT, _G.VERSION, "=====")

    if FOTA_MODE == 3 then
        -- ===== libfota3：开机立即检测一次，之后每8小时自动检测一次 =====
        -- config() 配置 project_key 等参数并启动 8h 定时；
        -- check_update() 强制立即检测一次（不依赖内部时间戳文件）
        local project_key = _G.PRODUCT_KEY
        if not project_key or project_key == "" then
            log.warn("update", "PRODUCT_KEY 未配置，跳过 libfota3")
            return
        end
        libfota3.config({
            project_key = project_key,
            script_name = _G.PROJECT or "Air8201",
            script_version = _G.VERSION or "004.000.000",
            auto = true,
            interval = 28800,  -- 8小时
            on_status = function(status, msg, percent)
                log.info("fota", status, msg, percent)
            end,
            on_confirm = function(action, info, callback)
                callback(true)
            end,
        })
        libfota3.check_update()
    else
        -- ===== libfota2：立即检查一次 + 启动定时器 =====
        update.check_update()
        update.start_periodic_check()
    end
end

-- 手动触发升级检查（服务器下发 update 命令时调用）
function update.check_update()
    if FOTA_MODE == 3 then
        log.info("update", "libfota3 手动触发升级检查")
        libfota3.check_update()
    else
        local project_key = _G.PRODUCT_KEY
        if not project_key or project_key == "" then
            log.warn("update", "PRODUCT_KEY 未配置，跳过升级检查")
            return
        end
        if fota_running then
            log.info("update", "升级正在进行中，跳过")
            return
        end
        log.info("update", "libfota2 手动触发升级检查")
        fota_running = true
        libfota2.request(fota2_cb, {})
    end
end

-- 切换 FOTA 模式
-- @param number mode 2=libfota2, 3=libfota3
function update.set_fota_mode(mode)
    if mode ~= 2 and mode ~= 3 then
        log.warn("update", "无效的FOTA模式:", mode, "，仅支持 2=libfota2, 3=libfota3")
        return
    end
    local old_mode = FOTA_MODE
    FOTA_MODE = mode
    log.info("update", "FOTA模式切换为:", mode == 3 and "libfota3(整机成品FOTA)" or "libfota2(IoT平台)")

    -- 停止旧模式的定时器
    if old_mode == 2 then
        update.stop_periodic_check()
    end
    -- 如果旧模式是 libfota3，停止其定时器
    if old_mode == 3 then
        libfota3.config({auto = false})
    end

    -- 启动新模式的定时器
    if mode == 2 then
        update.start_periodic_check()
    elseif mode == 3 then
        local project_key = _G.PRODUCT_KEY
        if project_key and project_key ~= "" then
            libfota3.request({
                project_key = project_key,
                script_name = _G.PROJECT or "Air8201",
                script_version = _G.VERSION or "004.000.000",
                auto = true,
                interval = 28800,
                on_status = function(status, msg, percent)
                    log.info("fota", status, msg, percent)
                end,
                on_confirm = function(action, info, callback)
                    callback(true)
                end,
            })
        end
    end
end

-- ==================== 定时器管理（libfota2 用） ====================

local periodic_timer_id = nil

function update.start_periodic_check()
    if FOTA_MODE == 3 then
        return
    end
    if periodic_timer_id then
        return
    end
    log.info("update", "启动 libfota2 定时升级检查（每8小时）")
    periodic_timer_id = sys.timerLoopStart(update.check_update, 8 * 3600000)
end

function update.stop_periodic_check()
    if periodic_timer_id then
        sys.timerStop(periodic_timer_id)
        periodic_timer_id = nil
        log.info("update", "已停止 libfota2 定时升级检查")
    end
end

return update