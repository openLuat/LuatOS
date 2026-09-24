--[[
@module libfota3
@summary 合宙整机成品FOTA升级库（8301出厂固件）
@version 1.0
@date    2026.09.22
@author  江访

@description
    提供完整的FOTA升级功能，支持 request() 启动自动检测定时器，
    以及 check_update()、config() 两个独立接口，方便上层模块灵活控制升级流程。
    定时器支持基于时间戳的真实间隔，跨重启延续检测进度。

@features
    - request() 启动接口：等待时间同步后启动自动检测定时器
    - check_update() 检测更新：手动触发升级检测，复用 running 互斥
    - config() 配置管理：动态修改参数并同步定时器状态
    - 进度反馈：支持下载进度回调，实时反馈升级状态
    - 安全校验：支持SHA256校验，确保升级包完整性

@usage
libfota3.request({
    project_key = "your_project_key",
    script_name = "fota3_temp",
    script_version = "001.999.000",
    auto = true,
    interval = 86400,
    on_status = function(status, msg, percent) end,
    on_confirm = function(action, info, callback) end,
})
]]

local libfota3 = {}

-- ==================== 常量 ====================

local FOTA_CHECK_URL  = "http://iot.openluat.com/api/site/turnkey_fota"
local FOTA_REPORT_URL = "http://iot.openluat.com/api/site/turnkey_fota_result"
local DEFAULT_TIMEOUT = 120000
local FOTA_STATE_FILE = "/fota_state.json"
local FOTA_TIMER_STATE_FILE = "/fota_timer_state.json"

-- ==================== 内部状态 ====================

local running = false
local opts = nil
local auto_timer_id = nil
local last_percent = -1
local last_check_result = nil
local confirm_result = nil
local time_synced = false

-- ==================== 工具函数 ====================

--[[
URL编码：将特殊字符转换为URL安全格式

@local
@function url_encode
@param s string 原始字符串
@return string 编码后字符串
]]
local function url_encode(s)
    if not s then return "" end
    s = tostring(s)
    s = s:gsub("%%", "%%25")
    s = s:gsub(" ", "%%20")
    s = s:gsub("#", "%%23")
    s = s:gsub("&", "%%26")
    s = s:gsub("=", "%%3D")
    s = s:gsub("%+", "%%2B")
    s = s:gsub("\r", "%%0D")
    s = s:gsub("\n", "%%0A")
    return s
end

--[[
获取设备标识（IMEI / MAC / UID）

@local
@function get_device_id
@return string 标识类型
@return string 标识值
]]
local function get_device_id()
    local model = hmeta.model()
    -- 4G模组走IMEI
    if model:find("^Air780E") or model:find("^Air8000") or model:find("^Air700") then
        local ok, imei = pcall(mobile.imei)
        if ok and imei and #tostring(imei) >= 10 then
            return "imei", tostring(imei)
        end
    -- WiFi/MCU模组走MAC地址
    elseif model:find("^Air8101") then
        local ok, mac = pcall(wlan.getMac)
        if ok and mac and #tostring(mac) >= 12 then
            return "mac", tostring(mac)
        end
    elseif model:find("^Air1601") or model:find("^Air1602") or model:find("^Air1780") then
        local ok, uid = pcall(mcu.unique_id)
        if ok and uid then
            return "uid", tostring(uid)
        end
    end
    return nil, nil
end

--[[
校验文件 SHA256

@local
@function verify_sha256
@param file_path string 文件路径
@param expected string 期望的 SHA256
@return boolean 是否通过
]]
local function verify_sha256(file_path, expected)
    if not expected or expected == "" then
        log.warn("libfota3", "no sha256 provided, skip verification")
        return true
    end
    expected = expected:lower()
    if not crypto or not crypto.md_file then
        log.warn("libfota3", "crypto.md_file not available, skip verification")
        return true
    end
    local ok, hash = pcall(crypto.md_file, "SHA256", file_path)
    if not ok or not hash then
        log.error("libfota3", "sha256 compute failed")
        return false
    end
    if hash:lower() ~= expected then
        log.error("libfota3", "sha256 mismatch")
        return false
    end
    log.info("libfota3", "sha256 verified")
    return true
end

-- ==================== 状态文件操作 ====================

-- 保存升级状态到文件
local function state_save(state)
    local ok, err = pcall(function()
        io.writeFile(FOTA_STATE_FILE, json.encode(state))
    end)
    if ok then
        log.info("libfota3", "state file saved", state.status)
    else
        log.error("libfota3", "save state file failed", err)
    end
end

-- 加载升级状态文件
local function state_load()
    if not io.exists(FOTA_STATE_FILE) then return nil end
    local ok, data = pcall(function()
        return json.decode(io.readFile(FOTA_STATE_FILE))
    end)
    if ok and type(data) == "table" then return data end
    return nil
end

-- 清理升级状态文件
local function state_clear()
    if io.exists(FOTA_STATE_FILE) then
        os.remove(FOTA_STATE_FILE)
        log.info("libfota3", "state file removed")
    end
end

-- ==================== 定时器状态文件操作 ====================

-- 保存上次检测时间戳
local function timer_state_save(ts)
    local ok, err = pcall(function()
        io.writeFile(FOTA_TIMER_STATE_FILE, json.encode({last_check_ts = ts}))
    end)
    if ok then
        log.info("libfota3", "timer state saved, ts", ts)
    else
        log.error("libfota3", "save timer state failed", err)
    end
end

-- 加载上次检测时间戳，文件不存在时返回 0
local function timer_state_load()
    if not io.exists(FOTA_TIMER_STATE_FILE) then return 0 end
    local ok, data = pcall(function()
        return json.decode(io.readFile(FOTA_TIMER_STATE_FILE))
    end)
    if ok and type(data) == "table" and data.last_check_ts then
        return data.last_check_ts
    end
    return 0
end

-- ==================== 等待网络与时间同步 ====================

-- 等待网络连接（最多 60 秒）
local function wait_network()
    log.info("libfota3", "wait network, timeout 60s")
    for i = 1, 60 do
        if socket.adapter(socket.dft()) then
            log.info("libfota3", "network ready")
            return true
        end
        if opts and opts.on_status then
            opts.on_status("network_fail", "网络连接失败")
        end
        sys.wait(1000)
    end
    return false
end

-- 等待 NTP 时间同步完成
local function wait_time_sync()
    if not wait_network() then
        log.warn("libfota3", "网络未就绪，跳过时间同步")
        return false
    end
    socket.sntp()
    if sys.waitUntil("NTP_UPDATE", 30000) then
        log.info("libfota3", "时间同步完成", os.date("%Y-%m-%d %H:%M:%S"))
        return true
    end
    log.warn("libfota3", "时间同步超时")
    return false
end

-- ==================== HTTP 检查 ====================

--[[
HTTP 检查：向 FOTA 服务器查询是否有新版本

@local
@function http_check
@return table 服务器响应数据 / nil
@return string 错误信息
]]
local function http_check()
    local project_key = opts and opts.project_key or nil
    if not project_key then
        return nil, "缺少project_key"
    end

    local id_type, id_val = get_device_id()
    if not id_val then
        return nil, "无法获取设备标识(IMEI/MAC)"
    end

    local v, core_id = rtos.version(true)
    local core_version = v and v:gsub("^V", "") or "0"
    core_id = core_id or "0"

    local model = ""
    if hmeta and hmeta.model then
        model = hmeta.model() or ""
    end

    local script_name = opts and opts.script_name or _G.PROJECT or ""
    local script_version = opts and opts.script_version or _G.VERSION or "0.0.0"

    local url = FOTA_CHECK_URL
        .. "?" .. id_type .. "=" .. url_encode(id_val)
        .. "&project_key=" .. url_encode(project_key)
        .. "&model=" .. url_encode(model)
        .. "&core_id=" .. url_encode(tostring(core_id))
        .. "&core_version=" .. url_encode(core_version)
        .. "&script_name=" .. url_encode(script_name)
        .. "&script_version=" .. url_encode(script_version)

    log.info("libfota3", "check", "id", id_type, id_val, "model", model,
        "core_id", core_id, "core_version", core_version, "script", script_version)

    local code, headers, body = http.request("GET", url, nil, nil, {timeout = DEFAULT_TIMEOUT}).wait()
    if code ~= 200 then
        log.error("libfota3", "check http error", code)
        return nil, "服务器响应错误(" .. tostring(code) .. ")"
    end
    if not body or body == "" then
        return nil, "服务器返回空"
    end

    local ok, result = pcall(json.decode, body)
    if not ok or type(result) ~= "table" then
        log.error("libfota3", "check json parse failed", body)
        return nil, "服务器返回格式错误"
    end

    if result.code and result.code ~= 0 then
        log.info("libfota3", "no update, code", result.code, "msg", result.msg)
        return result, result.msg or "无新版本"
    end

    log.info("libfota3", "new version found", "script", result.script_version, "size", result.size)
    return result
end

-- ==================== HTTP 下载并刷写 ====================

--[[
下载升级包并写入 fota 分区

@local
@function http_download
@param url string 下载地址
@param sha256 string SHA256 校验值
@param progress_cb function 进度回调
@return boolean 是否成功
@return string 错误信息
]]
local function http_download(url, sha256, progress_cb)
    -- 选择临时文件路径：优先使用 PSRAM
    local temp_path = "/ram/fota_update.bin"
    local psram_total, psram_used = rtos.meminfo("psram")
    local psram_free = psram_total and psram_used and (psram_total - psram_used) or 0
    if psram_free < 512 * 1024 then
        temp_path = "/fota_update.bin"
        log.info("libfota3", "psram low, use internal fs for temp file")
    end

    if io.exists(temp_path) then os.remove(temp_path) end

    log.info("libfota3", "download", url, "->", temp_path)

    local function download_progress_callback_func(total, received)
        if progress_cb and total and total > 0 then
            progress_cb(received, total)
        end
    end

    local code, headers = http.request("GET", url, nil, nil, {
        dst = temp_path,
        timeout = 600000,
        callback = download_progress_callback_func
    }).wait()

    if code ~= 200 then
        os.remove(temp_path)
        log.error("libfota3", "download http error", code)
        return false, "下载失败(" .. tostring(code) .. ")"
    end

    local file_size = io.fileSize(temp_path) or 0
    if file_size == 0 then
        os.remove(temp_path)
        return false, "下载文件为空"
    end
    log.info("libfota3", "download complete", file_size, "bytes")

    if not verify_sha256(temp_path, sha256) then
        os.remove(temp_path)
        return false, "SHA256校验失败"
    end

    if not fota then
        os.remove(temp_path)
        return false, "fota模块不可用"
    end

    if not fota.init() then
        os.remove(temp_path)
        return false, "fota初始化失败"
    end

    local bsp = rtos.bsp():lower()
    if not bsp:find("air8101") then
        local wait_start = os.clock()
        while not fota.wait() do
            if os.clock() - wait_start > 30 then
                fota.finish(false)
                os.remove(temp_path)
                return false, "fota等待超时"
            end
            sys.wait(100)
        end
    end

    local result, _, cache = fota.file(temp_path)
    if not result then
        fota.finish(false)
        os.remove(temp_path)
        return false, "fota写入失败"
    end

    while true do
        local succ, done = fota.isDone()
        if not succ then
            fota.finish(false)
            os.remove(temp_path)
            return false, "fota过程出错"
        end
        if done then
            fota.finish(true)
            break
        end
        if cache and cache > 65536 then
            sys.wait(500)
        else
            sys.wait(200)
        end
    end

    if io.exists(temp_path) then os.remove(temp_path) end
    log.info("libfota3", "download and flash complete")
    return true
end

-- ==================== 上报结果 ====================

--[[
将升级结果上报给 FOTA 服务器（异步任务 + 重试）

@local
@function report_result
@param fota_sn string 升级事务ID
@param result_code number 结果码（1=成功，2=失败）
]]
local function report_result(fota_sn, result_code)
    if not wait_network() then return end

    if not fota_sn or fota_sn == "" then
        log.warn("libfota3", "no fota_sn, skip report")
        return
    end

    local url = FOTA_REPORT_URL
        .. "?fota_sn=" .. url_encode(fota_sn)
        .. "&result_code=" .. url_encode(tostring(tonumber(result_code) or 0))

    log.info("libfota3", "report result", "fota_sn", fota_sn, "code", result_code)

    local body = json.encode({
        fota_sn = fota_sn,
        result_code = tonumber(result_code) or 0
    })

    local function report_task()
        for attempt = 1, 2 do
            local code, headers, rsp_body = http.request("POST", url,
                {["Content-Type"] = "application/json"},
                body,
                {timeout = 30000}
            ).wait()

            if code == 200 and rsp_body then
                local ok, rsp = pcall(json.decode, rsp_body)
                if ok and rsp and rsp.code == 0 then
                    log.info("libfota3", "report success")
                    return
                end
            end

            log.warn("libfota3", "report http error", code, "attempt", attempt)
            if attempt == 1 then sys.wait(2000) end
        end
        log.error("libfota3", "report failed after retries")
    end

    sys.taskInit(report_task)
end

-- ==================== 开机处理（版本比对 + 上报） ====================

--[[
检查上次升级结果并上报服务器

@local
@function handle_boot
]]
local function handle_boot()
    local state = state_load()
    if not state then
        log.info("libfota3", "no state file, skip boot report")
        return
    end

    if opts and opts.on_status then
        opts.on_status("boot_report", "正在检测上次升级结果")
    end

    local cur_version, cur_version_id = rtos.version(true)
    local cur_core_version = cur_version and cur_version:gsub("^V", "") or "0"
    local cur_core_id = cur_version_id or "0"
    local cur_script_version = opts and opts.script_version or _G.VERSION or "0.0.0"

    local old_core_id = state.old_core_id or "?"
    local old_core_version = state.old_core_version or "?"
    local old_script_version = state.old_script_version or "?"
    local new_core_id = state.new_core_id or "?"
    local new_core_version = state.new_core_version or "?"
    local new_script_version = state.new_script_version or "?"

    log.info("libfota3", "=== 升级版本比对 ===")
    log.info("libfota3", string.format("core_id:     old=%s  new=%s  cur=%s", old_core_id, new_core_id, cur_core_id))
    log.info("libfota3", string.format("core_version:old=%s  new=%s  cur=%s", old_core_version, new_core_version, cur_core_version))
    log.info("libfota3", string.format("script_ver:  old=%s  new=%s  cur=%s", old_script_version, new_script_version, cur_script_version))

    local core_changed = (tonumber(cur_core_version) == tonumber(new_core_version)) and (cur_core_id == new_core_id)
    local script_changed = (cur_script_version == new_script_version)
    local result_code = 3

    if core_changed and script_changed then
        result_code = 1
        log.info("libfota3", "upgrade success")
        if opts and opts.on_status then
            opts.on_status("upgrade_success", "升级成功", result_code)
        end
    else
        result_code = 2
        log.info("libfota3", "upgrade failed, no version change")
        if opts and opts.on_status then
            opts.on_status("upgrade_fail", "升级失败/无变化", result_code)
        end
    end

    if state.fota_sn and state.fota_sn ~= "" then
        log.info("libfota3", "上报上次升级结果", "fota_sn", state.fota_sn, "code", result_code)
        report_result(state.fota_sn, result_code)
    end

    state_clear()
end

-- ==================== 用户确认等待 ====================

--[[
等待用户确认

@local
@function wait_confirm
@param action string 动作
@param info table 信息
@return boolean 是否确认
]]
local function wait_confirm(action, info)
    if not opts or not opts.on_confirm then
        return true
    end
    confirm_result = nil
    opts.on_confirm(action, info, function(ok)
        confirm_result = ok
    end)
    while confirm_result == nil do
        sys.wait(100)
    end
    return confirm_result
end

-- ==================== 下载流程 ====================

--[[
下载升级包并刷写，完成后重启设备

@local
@function do_download_flow
]]
local function do_download_flow()
    if not wait_network() then
        running = false
        return
    end

    if not last_check_result then
        if opts and opts.on_status then
            opts.on_status("check_fail", "请先检测更新")
        end
        return
    end

    local result = last_check_result
    last_percent = -1

    if opts and opts.on_status then
        opts.on_status("download_start", "开始下载升级包...")
    end

    local function download_progress_cb(received, total)
        if total and total > 0 then
            local percent = math.floor(received * 100 / total)
            if percent ~= last_percent then
                last_percent = percent
                local msg = string.format("正在下载: %d%% (%d/%d KB)", percent, received // 1024, total // 1024)
                if opts and opts.on_status then
                    opts.on_status("downloading", msg, percent)
                end
            end
        end
    end

    local ok, err = http_download(result.url, result.sha256, download_progress_cb)

    if not ok then
        local state = state_load()
        if state then
            state.status = "download_fail"
            state_save(state)
        end
        log.error("libfota3", "下载失败:", err)
        if opts and opts.on_status then
            opts.on_status("download_fail", err or "下载失败")
        end
        return
    end

    local state = state_load()
    if state then
        state.status = "download_done"
        state_save(state)
    end

    if opts and opts.on_status then
        opts.on_status("download_done", "升级包已就绪，重启即可升级")
    end

    local ok2 = wait_confirm("reboot")
    if not ok2 then
        log.info("libfota3", "用户取消重启升级")
        return
    end

    if opts and opts.on_status then
        opts.on_status("rebooting", "正在重启...")
    end
    sys.timerStart(rtos.reboot, 500)
end

-- ==================== 检测流程 ====================

--[[
检测更新流程：查询新版本，发现新版本后启动下载流程

@local
@function do_check_flow
]]
local function do_check_flow()
    if not wait_network() then
        running = false
        return
    end

    if not last_check_result then
        last_check_result = {}
    end

    if opts and opts.on_status then
        opts.on_status("checking", "正在检测更新...")
    end

    local result, err = http_check()
    if not result then
        if opts and opts.on_status then
            opts.on_status("check_fail", err or "检测失败")
        end
        return
    end

    if result.code and result.code ~= 0 then
        if opts and opts.on_status then
            opts.on_status("no_new_version", result.msg or "当前已是最新版本")
        end
        return
    end

    last_check_result = result

    local cur_ver, cur_ver_id = rtos.version(true)
    local state = {
        fota_sn = result.fota_sn or "",
        status = "has_update",
        old_core_id = cur_ver_id or "0",
        old_core_version = cur_ver and cur_ver:gsub("^V", "") or "0",
        old_script_version = opts and opts.script_version or _G.VERSION or "0.0.0",
        new_core_id = result.core_id or "?",
        new_core_version = result.core_version or "?",
        new_script_version = result.script_version or "0.0.0"
    }

    local msg = string.format("发现新版本 %s (%s)",
        result.script_version or "?",
        result.size and (math.floor(result.size / 1024) .. "KB") or "未知大小")
    if opts and opts.on_status then
        opts.on_status("new_version", msg)
    end

    local info = {
        version = result.script_version,
        size = result.size,
        fota_sn = result.fota_sn,
    }
    local ok = wait_confirm("download", info)
    if not ok then
        log.info("libfota3", "用户取消下载")
        return
    end

    state_save(state)
    do_download_flow()
end

-- ==================== 定时器管理 ====================

--[[
定时器回调：定时触发检测更新流程

@local
@function on_timer
]]
local function on_timer()
    sys.taskInit(function()
        local interval = 86400
        if opts and opts.interval then
            interval = opts.interval
        end

        do_check_flow()

        if time_synced then
            timer_state_save(os.time())
        end

        auto_timer_id = sys.timerStart(on_timer, interval * 1000)
        log.info("libfota3", "下次检测间隔", interval, "秒")
    end)
end

--[[
根据用户配置启动或停止定时检测

@local
@function setup_timer
]]
local function setup_timer()
    if auto_timer_id then
        sys.timerStop(auto_timer_id)
        auto_timer_id = nil
    end

    local auto, interval = true, 86400
    if opts and opts.auto ~= nil then
        auto = opts.auto
    end
    if opts and opts.interval then
        interval = opts.interval
    end

    if not auto or not interval or interval <= 0 then
        log.info("libfota3", "未启用自动检测，不启动定时器")
        return
    end

    if time_synced then
        local last_ts = timer_state_load()
        local now = os.time()
        local wait_sec = (last_ts + interval) - now

        if wait_sec <= 0 then
            log.info("libfota3", "检测已过期或首次运行，立即触发")
            on_timer()
        else
            auto_timer_id = sys.timerStart(on_timer, wait_sec * 1000)
            log.info("libfota3", "定时器已启动，等待", wait_sec, "秒后检测",
                     "预计时间", os.date("%Y-%m-%d %H:%M:%S", now + wait_sec))
        end
    else
        log.warn("libfota3", "时间未同步，定时器未启动")
    end
end

-- ==================== 公共 API ====================

--[[
@api libfota3.request(opts)
@summary 启动FOTA升级流程
@param opts table 配置参数表（project_key/script_name/script_version/auto/interval/on_status/on_confirm）
]]
function libfota3.request(new_opts)
    if running then
        log.info("libfota3", "FOTA 流程已在运行中，跳过本次执行")
        return
    end
    if new_opts then
        opts = new_opts
    end
    running = true
    sys.taskInit(function()
        time_synced = wait_time_sync()
        setup_timer()
        running = false
    end)
end

--[[
@api libfota3.check_update()
@summary 手动检测更新（复用 running 标志与 request() 互斥）
]]
function libfota3.check_update()
    if running then
        log.info("libfota3", "FOTA 流程已在运行中，跳过本次执行")
        return
    end
    running = true
    sys.taskInit(function()
        do_check_flow()
        if time_synced then
            timer_state_save(os.time())
        end
        setup_timer()
        running = false
    end)
end

--[[
@api libfota3.config(new_opts)
@summary 动态修改 FOTA 配置
@param table new_opts 配置参数表（auto/interval）
]]
function libfota3.config(new_opts)
    opts = opts or {}
    if not new_opts then return end

    local old_auto = opts.auto
    local old_interval = opts.interval

    for k, v in pairs(new_opts) do
        opts[k] = v
    end

    if opts.auto ~= old_auto or opts.interval ~= old_interval then
        if time_synced then
            timer_state_save(os.time())
        end
        setup_timer()
    end
end

-- 模块加载时自动执行开机上报
sys.taskInit(handle_boot)

return libfota3
