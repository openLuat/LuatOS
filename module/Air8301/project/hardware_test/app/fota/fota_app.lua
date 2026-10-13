--[[
@module  fota_app
@summary FOTA远程升级模块
@version 1.0
@date    2026.09.04
@author  江访
@usage
FOTA远程升级功能模块：
- libfota2集成（合宙IoT平台）
- 重启标记机制（升级前保存版本/重启后对比写入历史）
- 升级历史（/fota_history.json，最多30条）
- 定时检查 + 开机检查
- 配置热切换
]]

local fota_app = {}

-- 消息常量
local FOTA_CMD_GET_VERSION = "fota_cmd_get_version"
local FOTA_VERSION_RSP = "fota_version_rsp"
local FOTA_CMD_GET_IOT_CONFIG = "fota_cmd_get_iot_config"
local FOTA_IOT_CONFIG_RSP = "fota_iot_config_rsp"
local FOTA_CMD_SET_PRODUCT_KEY = "fota_cmd_set_product_key"
local FOTA_CMD_GET_SETTINGS = "fota_cmd_get_settings"
local FOTA_SETTINGS_RSP = "fota_settings_rsp"
local FOTA_CMD_CHECK = "fota_cmd_check"
local FOTA_CMD_SAVE_SETTINGS = "fota_cmd_save_settings"
local FOTA_STATUS_CHECKING = "fota_status_checking"
local FOTA_STATUS_DOWNLOADING = "fota_status_downloading"
local FOTA_STATUS_SUCCESS = "fota_status_success"
local FOTA_STATUS_NO_NEW_VERSION = "fota_status_no_new_version"
local FOTA_STATUS_FAIL = "fota_status_fail"
local FOTA_CMD_GET_HISTORY = "fota_cmd_get_history"
local FOTA_HISTORY_RSP = "fota_history_rsp"
local FOTA_CMD_CLEAR_HISTORY = "fota_cmd_clear_history"

-- 文件路径
local FOTA_HISTORY_FILE = "/fota_history.json"
local FOTA_REBOOT_FLAG_FILE = "/fota_reboot_flag.json"
local MAX_HISTORY_COUNT = 30

-- 版本信息
local version_info = {
    core_version = "",
    script_version = "",
    build_date = "",
    hw_version = "",
}

-- IoT配置
local product_key = ""
local device_imei = ""

-- 设备配置引用
local g_fota_config = nil

-- FOTA相关
local libfota2 = nil
local auto_timer_id = nil
local network_ready = false
local last_percent = -1

local function collect_version_info()
    local ver, ver_num = rtos.version(true)
    if ver and ver_num then
        version_info.core_version = string.format("%s_%s", ver, ver_num)
    elseif ver then
        version_info.core_version = ver
    else
        version_info.core_version = "未知"
    end

    version_info.script_version = _G.VERSION or "未知"

    local build_date = rtos.buildDate()
    version_info.build_date = build_date or "未知"

    if hmeta and hmeta.hwver then
        version_info.hw_version = hmeta.hwver() or "未知"
    else
        version_info.hw_version = "未知"
    end

    log.info("fota_app", "core:", version_info.core_version,
        "script:", version_info.script_version,
        "build:", version_info.build_date,
        "hw:", version_info.hw_version)
end

local function collect_iot_config()
    if mobile and mobile.imei then
        device_imei = mobile.imei() or "未知"
    else
        device_imei = "未知"
    end
    log.info("fota_app", "product_key:", product_key, "imei:", device_imei)
end

local function reboot_flag_save()
    local fw_ver, fw_num = rtos.version(true)
    local script_ver = _G.VERSION or "000.000.001"

    local flag = {
        is_fota_reboot = true,
        firmware_version_before = fw_ver or "未知",
        firmware_num_before = fw_num or "0",
        script_version_before = script_ver,
        reboot_time = os.date("%Y-%m-%d %H:%M:%S")
    }

    local f = io.open(FOTA_REBOOT_FLAG_FILE, "w")
    if f then
        f:write(json.encode(flag))
        f:close()
        log.info("fota_app", "reboot_flag saved")
    end
end

local function reboot_flag_load()
    local f = io.open(FOTA_REBOOT_FLAG_FILE, "r")
    if f then
        local content = f:read("*a")
        f:close()
        if content and content ~= "" then
            local ok, data = pcall(json.decode, content)
            if ok and data then return data end
        end
    end
    return nil
end

local function reboot_flag_clear()
    local f = io.open(FOTA_REBOOT_FLAG_FILE, "w")
    if f then
        f:write("")
        f:close()
        log.info("fota_app", "reboot_flag cleared")
    end
end

local function history_load()
    local f = io.open(FOTA_HISTORY_FILE, "r")
    if f then
        local content = f:read("*a")
        f:close()
        if content and content ~= "" then
            local ok, data = pcall(json.decode, content)
            if ok and type(data) == "table" then return data end
        end
    end
    return {}
end

local function history_save(history)
    local f = io.open(FOTA_HISTORY_FILE, "w")
    if f then
        f:write(json.encode(history))
        f:close()
        return true
    end
    return false
end

local function history_add(record)
    local history = history_load()
    table.insert(history, 1, record)
    while #history > MAX_HISTORY_COUNT do
        table.remove(history)
    end
    return history_save(history)
end

local function reboot_flag_check()
    local flag = reboot_flag_load()
    if not flag or not flag.is_fota_reboot then
        if flag then reboot_flag_clear() end
        return
    end

    log.info("fota_app", "checking FOTA reboot result")

    local fw_ver, fw_num = rtos.version(true)
    local script_ver = _G.VERSION or "000.000.001"

    local status = "fail"
    local description = "升级失败"

    if fw_ver ~= flag.firmware_version_before or fw_num ~= flag.firmware_num_before then
        status = "success"
        description = "固件升级成功"
    elseif script_ver ~= flag.script_version_before then
        status = "success"
        description = "脚本升级成功"
    else
        description = "版本号未变化，升级失败"
    end

    history_add({
        time = flag.reboot_time,
        firmware_version_before = flag.firmware_version_before,
        script_version_before = flag.script_version_before,
        firmware_version_after = fw_ver,
        script_version_after = script_ver,
        status = status,
        description = description
    })

    reboot_flag_clear()
end

local function wait_network()
    if network_ready then return true end
    local retry_count = 30
    while not socket.adapter(socket.dft()) do
        sys.waitUntil("IP_READY", 1000)
        retry_count = retry_count - 1
        if retry_count <= 0 then
            log.error("fota_app", "wait_network: timeout")
            return false
        end
    end
    network_ready = true
    return true
end

local function fota_result_cb(ret)
    log.info("fota_app", "fota_result_cb", ret)
    last_percent = -1
    if ret == 0 then
        reboot_flag_save()
        sys.publish(FOTA_STATUS_SUCCESS, "升级包下载成功，即将重启")
        sys.timerStart(rtos.reboot, 2000)
    elseif ret == 4 then
        sys.publish(FOTA_STATUS_NO_NEW_VERSION, "当前已是最新版本")
    else
        local msg = "操作失败"
        if ret == 1 then msg = "连接失败"
        elseif ret == 2 then msg = "URL错误"
        elseif ret == 3 then msg = "服务器断开"
        elseif ret == 5 then msg = "版本号格式错误"
        else msg = "未知错误(" .. tostring(ret) .. ")" end
        sys.publish(FOTA_STATUS_FAIL, msg, ret)
    end
end

local function fota_progress_cb(total_len, received_len, userdata)
    if total_len > 0 then
        local percent = math.floor(received_len * 100 / total_len)
        if percent ~= last_percent then
            last_percent = percent
            local msg = string.format("下载中：%d%% (%d/%d KB)", percent, received_len // 1024, total_len // 1024)
            sys.publish(FOTA_STATUS_DOWNLOADING, msg, percent)
        end
    end
end

local function fota_task()
    if not wait_network() then
        sys.publish(FOTA_STATUS_FAIL, "网络未就绪", -1)
        return
    end

    if not libfota2 then
        libfota2 = require("libfota2")
    end

    sys.publish(FOTA_STATUS_CHECKING, "正在连接服务器...")

    local opts = {
        project_key = product_key,
        callback = fota_progress_cb,
        userdata = "fota_progress",
        timeout = 120000
    }
    libfota2.request(fota_result_cb, opts)
end

local function get_auto_settings()
    local auto = g_fota_config and g_fota_config.auto_check
    if auto == nil then auto = true end
    local interval = g_fota_config and g_fota_config.check_interval
    if interval == nil then interval = 3600 end
    local power_on_check = g_fota_config and g_fota_config.power_on_check
    if power_on_check == nil then power_on_check = false end
    return auto, interval, power_on_check
end

local function update_auto_timer(auto, interval)
    if auto_timer_id then
        sys.timerStop(auto_timer_id)
        auto_timer_id = nil
    end
    if auto and interval > 0 then
        auto_timer_id = sys.timerLoopStart(fota_task, interval * 1000)
        log.info("fota_app", "auto timer started", interval .. "s")
    end
end

local function save_auto_settings(auto, interval, power_on_check)
    if interval == nil or interval <= 0 then interval = 3600 end
    if g_fota_config then
        g_fota_config.auto_check = auto
        g_fota_config.check_interval = interval
        g_fota_config.power_on_check = power_on_check
        sys.publish("CONFIG_UPDATE_TRIGGER", "fota", g_fota_config)
    end
    update_auto_timer(auto, interval)
end

local function subscribe_events()
    sys.subscribe(FOTA_CMD_GET_VERSION, function()
        collect_version_info()
        sys.publish(FOTA_VERSION_RSP, {
            core_version = version_info.core_version,
            script_version = version_info.script_version,
            build_date = version_info.build_date,
            hw_version = version_info.hw_version,
        })
    end)

    sys.subscribe(FOTA_CMD_GET_IOT_CONFIG, function()
        collect_iot_config()
        sys.publish(FOTA_IOT_CONFIG_RSP, {
            product_key = product_key,
            device_imei = device_imei,
        })
    end)

    sys.subscribe(FOTA_CMD_SET_PRODUCT_KEY, function(data)
        if data and data.product_key then
            product_key = data.product_key
            if g_fota_config then
                g_fota_config.product_key = product_key
                sys.publish("CONFIG_UPDATE_TRIGGER", "fota", g_fota_config)
            end
        end
    end)

    sys.subscribe(FOTA_CMD_CHECK, function()
        sys.taskInit(fota_task)
    end)

    sys.subscribe(FOTA_CMD_SAVE_SETTINGS, function(data)
        if data then
            save_auto_settings(
                data.auto_check ~= nil and data.auto_check or false,
                data.check_interval or 3600,
                data.power_on_check ~= nil and data.power_on_check or false
            )
        end
    end)

    sys.subscribe(FOTA_CMD_GET_SETTINGS, function()
        local auto, interval, power_on_check = get_auto_settings()
        sys.publish(FOTA_SETTINGS_RSP, {
            auto_check = auto,
            check_interval = interval,
            power_on_check = power_on_check
        })
    end)

    sys.subscribe(FOTA_CMD_GET_HISTORY, function()
        sys.publish(FOTA_HISTORY_RSP, history_load())
    end)

    sys.subscribe(FOTA_CMD_CLEAR_HISTORY, function()
        history_save({})
    end)

    -- 配置热切换
    sys.subscribe("CONFIG_UPDATED", function(new_config)
        if new_config and new_config.fota then
            g_fota_config = new_config.fota
            if new_config.fota.product_key then
                product_key = new_config.fota.product_key
            end
            local auto, interval = get_auto_settings()
            update_auto_timer(auto, interval)
        end
    end)
end

--[[
@function init
@summary 初始化模块
@param config table fota配置（由app_main统一传入）
]]
function fota_app.init(config)
    log.info("fota_app", "initializing")
    collect_version_info()
    reboot_flag_check()

    g_fota_config = config or {}
    if g_fota_config.product_key then
        product_key = g_fota_config.product_key
    end

    subscribe_events()

    local auto, interval, power_on_check = get_auto_settings()
    update_auto_timer(auto, interval)
    if power_on_check then
        sys.taskInit(fota_task)
    end
end

return fota_app
