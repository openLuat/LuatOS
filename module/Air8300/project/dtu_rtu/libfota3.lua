--[[
@module libfota3
@summary 合宙整机成品FOTA升级库
@version 2.0
@date    2026.06.18
@author  江访

@description
    提供完整的FOTA升级功能，支持 request() 启动自动检测定时器，
    以及 check_update()、config() 两个独立接口，
    方便上层模块灵活控制升级流程。
    定时器支持基于时间戳的真实间隔，跨重启延续检测进度。

@features
    - request() 启动接口：等待时间同步后启动自动检测定时器
    - check_update() 检测更新：手动触发升级检测，复用 running 互斥
    - config() 配置管理：动态修改参数并同步定时器状态
    - 进度反馈：支持下载进度回调，实时反馈升级状态
    - 安全校验：支持SHA256校验，确保升级包完整性

@usage
-- 启动自动检测定时器（时间同步 + 定时检测 + 下载 + 重启）
libfota3.request({
    project_key = "your_project_key",    -- 项目密钥，用于FOTA服务认证
    script_name = "fota3_temp",          -- 脚本名称
    script_version = "001.999.000",      -- 脚本版本
    auto = true,                         -- 启用自动定时检测
    interval = 86400,                    -- 自动检测间隔（秒），默认24小时
    on_status = function(status, msg, percent)
        log.info("fota_temp", status, msg, percent)
    end,
    on_confirm = function(action, info, callback)
        if action == "download" then
            -- true 表示用户确认下载
            callback(true)
        elseif action == "reboot" then
            -- true 表示用户确认重启升级
            callback(true)
        end
    end,
})

-- 手动触发检测更新
libfota3.check_update()

-- 动态修改配置
libfota3.config({auto = false})
libfota3.config({auto = true, interval = 3600})
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

-- URL编码：将特殊字符转换为URL安全格式，用于构建HTTP请求参数
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

-- 获取设备标识，用于FOTA服务器识别设备
-- 返回值：设备标识类型（"imei"/"mac"）和标识值，获取失败返回 nil
local function get_device_id()
    -- 优先使用 mobile.imei：蜂窝网络设备（如4G模组）的标准标识
    if mobile and mobile.imei then
        -- 使用 pcall 包装：防止 API 不可用或调用失败导致程序崩溃
        local ok, imei = pcall(mobile.imei)
        -- 验证 IMEI 长度：确保获取到的标识有效（IMEI 标准长度为15位）
        if ok and imei and #tostring(imei) >= 10 then
            return "imei", tostring(imei)
        end
    end

    -- 备选方案：使用 wlan.getMac（WiFi设备的MAC地址）
    -- WiFi设备没有IMEI，使用MAC地址作为唯一标识
    if wlan and wlan.getMac then
        -- 使用 pcall 包装：防止 API 不可用或调用失败导致程序崩溃
        local ok, mac = pcall(wlan.getMac)
        -- 验证 MAC 地址长度：确保获取到的标识有效（MAC地址标准长度为12位十六进制）
        if ok and mac and #tostring(mac) >= 12 then
            return "mac", tostring(mac)
        end
    end

    -- 按照文档上的方案，没说让用户自己定义设备ID，暂不启用
    -- if _G.IMEI and #tostring(_G.IMEI) >= 10 then
    --     return "imei", tostring(_G.IMEI)
    -- end

    -- 按照文档上的方案，只有说填IMEI或者MAC，没有说填unique_id，暂不启用
    -- if mcu and mcu.unique_id then
    --     local ok, uid = pcall(mcu.unique_id)
    --     if ok and uid then
    --         return "uid", tostring(uid)
    --     end
    -- end

    -- 所有方案都失败，返回 nil
    return nil, nil
end

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
    hash = hash:lower()
    if hash ~= expected then
        log.error("libfota3", "sha256 mismatch")
        return false
    end
    log.info("libfota3", "sha256 verified")
    return true
end

-- ==================== 状态文件操作 ====================

-- 将升级状态信息持久化到文件
local function state_save(state)
    -- 使用 pcall 包装，防止文件写入失败导致程序崩溃
    local ok, err = pcall(function()
        -- JSON 编码并写入：将 Lua 表转换为 JSON 格式并写入文件
        io.writeFile(FOTA_STATE_FILE, json.encode(state))
    end)

    -- 记录操作结果，便于调试和问题追踪
    if ok then
        -- 成功：记录当前状态，便于追踪升级流程
        log.info("libfota3", "state file saved", state.status)
    else
        -- 失败：记录错误信息，便于排查问题
        log.error("libfota3", "save state file failed", err)
    end
end

-- 加载 FOTA 状态文件：用于记录升级过程中的状态信息
local function state_load()
    -- 文件不存在时直接返回 nil，避免后续不必要的文件操作
    if not io.exists(FOTA_STATE_FILE) then return nil end

    -- 使用 pcall 包装，防止文件读取失败或 JSON 解码异常导致程序崩溃
    local ok, data = pcall(function()
        return json.decode(io.readFile(FOTA_STATE_FILE))
    end)

    -- 确保解码后的数据是 table 类型，符合预期的状态数据格式
    if ok and type(data) == "table" then return data end

    -- 异常情况统一返回 nil
    return nil
end

-- 升级流程完成后清理状态文件，避免重复处理
-- 使用场景：开机处理完成后、升级失败后等
local function state_clear()
    -- 检查文件是否存在：避免删除不存在的文件导致错误
    if io.exists(FOTA_STATE_FILE) then
        -- 清理升级记录，确保下次开机时状态干净
        os.remove(FOTA_STATE_FILE)
        -- 记录日志
        log.info("libfota3", "state file removed")
    end
end

-- ==================== 定时器状态文件操作 ====================

-- 保存上次检测时间戳到文件
-- @param ts number: 时间戳（秒）
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
-- @return number: 上次检测时间戳（秒）
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

-- ==================== 等待网络 ====================

-- 等待网络连接：确保设备已连接到网络
local function wait_network()
    log.info("libfota3", "wait network, timeout 60s")

    -- 循环检查网络状态：最多等待 60 秒
    for i = 1, 60 do
        -- 检查网络适配器：判断网络是否可用
        if socket.adapter(socket.dft()) then
            log.info("libfota3", "network ready")
            return true
        end
        -- 等待超时：记录警告日志，通知调用方，返回 false
        if opts and opts.on_status then
            opts.on_status("network_fail", "网络连接失败")
        end
        -- 每秒检查一次
        sys.wait(1000)
    end

    return false
end

-- ==================== 等待时间同步 ====================

-- 等待 NTP 时间同步完成
-- 流程：等待网络就绪 → 触发 NTP 同步 → 等待同步结果
-- @return boolean: 同步成功返回 true，超时返回 false
local function wait_time_sync()
    -- 等待网络就绪
    if not wait_network() then
        log.warn("libfota3", "网络未就绪，跳过时间同步")
        return false
    end

    -- 主动触发 NTP 时间同步
    socket.sntp()

    -- 等待 NTP_UPDATE 事件，30秒超时
    local ok = sys.waitUntil("NTP_UPDATE", 30000)
    if ok then
        log.info("libfota3", "时间同步完成", os.date("%Y-%m-%d %H:%M:%S"))
        return true
    else
        log.warn("libfota3", "时间同步超时")
        return false
    end
end

-- ==================== HTTP 检查 ====================

-- HTTP 检查：向FOTA服务器查询是否有新版本
-- 设计思路：收集设备信息，构建请求参数，发送查询请求，解析响应结果
-- 返回值：成功返回服务器响应数据，失败返回 nil 和错误信息
local function http_check()
    -- 验证 project_key：项目密钥是FOTA服务认证的必要参数
    local project_key = opts and opts.project_key or nil
    if not project_key then
        return nil, "缺少project_key"
    end

    -- 获取设备标识：用于服务器识别设备
    local id_type, id_val = get_device_id()
    if not id_val then
        return nil, "无法获取设备标识(IMEI/MAC)"
    end

    -- 获取当前核心版本信息：用于服务器判断是否需要升级核心固件
    local v, core_id = rtos.version(true)
    local core_version = v and v:gsub("^V", "") or "0"
    core_id = core_id or "0"

    -- 获取设备型号：用于服务器匹配对应的升级包
    local model = ""
    if hmeta and hmeta.model then
        model = hmeta.model() or ""
    end

    -- 获取脚本信息：用于服务器判断是否需要升级脚本
    local script_name = opts and opts.script_name or _G.PROJECT or ""
    local script_version = opts and opts.script_version or _G.VERSION or "0.0.0"
    local timeout = DEFAULT_TIMEOUT

    -- 构建请求URL：包含所有必要参数，用于服务器判断是否有新版本
    local url = FOTA_CHECK_URL
        .. "?" .. id_type .. "=" .. url_encode(id_val)
        .. "&project_key=" .. url_encode(project_key)
        .. "&model=" .. url_encode(model)
        .. "&core_id=" .. url_encode(tostring(core_id))
        .. "&core_version=" .. url_encode(core_version)
        .. "&script_name=" .. url_encode(script_name)
        .. "&script_version=" .. url_encode(script_version)

    -- 记录查询信息：便于调试和问题追踪
    log.info("libfota3", "check", "id", id_type, id_val, "model", model, "core_id", core_id, "core_version", core_version, "script", script_version)

    -- 发送HTTP请求：向FOTA服务器查询新版本
    local code, headers, body = http.request("GET", url, nil, nil, {timeout = timeout}).wait()
    if code ~= 200 then
        log.error("libfota3", "check http error", code)
        return nil, "服务器响应错误(" .. tostring(code) .. ")"
    end

    -- 验证响应体：确保服务器返回了有效数据
    if not body or body == "" then
        return nil, "服务器返回空"
    end

    -- 解析JSON响应：使用 pcall 防止解析失败导致程序崩溃
    local ok, result = pcall(json.decode, body)
    if not ok or type(result) ~= "table" then
        log.error("libfota3", "check json parse failed", body)
        return nil, "服务器返回格式错误"
    end

    -- 判断是否有新版本：result.code 为 0 表示有新版本
    if result.code and result.code ~= 0 then
        log.info("libfota3", "no update, code", result.code, "msg", result.msg)
        return result, result.msg or "无新版本"
    end

    -- 发现新版本：记录版本信息
    log.info("libfota3", "new version found", "script", result.script_version, "size", result.size)
    return result
end

-- ==================== HTTP 下载并刷写 ====================

-- 下载升级包并写入 fota 分区
-- 流程说明：下载 -> SHA256校验 -> fota初始化 -> 等待就绪 -> 刷写 -> 等待完成
-- 返回值：成功返回 true，失败返回 false 和错误信息
local function http_download(url, sha256, progress_cb)
    -- 选择临时文件路径：优先使用 PSRAM（读写速度快），空间不足时使用内部 Flash
    local temp_path = "/ram/fota_update.bin"
    local psram_total, psram_used = rtos.meminfo("psram")
    local psram_free = psram_total and psram_used and (psram_total - psram_used) or 0
    if psram_free < 512 * 1024 then
        temp_path = "/fota_update.bin"
        log.info("libfota3", "psram low, use internal fs for temp file")
    end

    -- 清理旧文件：避免残留文件影响下载
    if io.exists(temp_path) then os.remove(temp_path) end

    log.info("libfota3", "download", url, "->", temp_path)

    -- 定义下载进度回调：通知用户下载进度
    local function download_progress_callback_func(total, received)
        if progress_cb and total and total > 0 then
            progress_cb(received, total)
        end
    end

    -- 发送 HTTP 请求：下载升级包到临时文件
    -- 超时时间 600 秒（10 分钟）：大文件下载需要较长时间
    local code, headers = http.request("GET", url, nil, nil, {
        dst = temp_path,
        timeout = 600000,
        callback = download_progress_callback_func
    }).wait()

    -- 验证 HTTP 状态码：200 表示成功
    if code ~= 200 then
        os.remove(temp_path)
        log.error("libfota3", "download http error", code)
        return false, "下载失败(" .. tostring(code) .. ")"
    end

    -- 验证文件大小：确保下载到了有效数据
    local file_size = io.fileSize(temp_path) or 0
    if file_size == 0 then
        os.remove(temp_path)
        return false, "下载文件为空"
    end
    log.info("libfota3", "download complete", file_size, "bytes")

    -- SHA256 校验：确保下载文件完整且未被篡改
    if not verify_sha256(temp_path, sha256) then
        os.remove(temp_path)
        return false, "SHA256校验失败"
    end

    -- 检查 fota 模块：确保可用
    if not fota then
        os.remove(temp_path)
        return false, "fota模块不可用"
    end

    -- 初始化 fota 模块：准备刷写
    if not fota.init() then
        os.remove(temp_path)
        return false, "fota初始化失败"
    end

    -- 获取设备 BSP：用于判断是否需要等待 fota 就绪
    local bsp = rtos.bsp():lower()
    -- Air8101 平台 fota.wait() 永远不就绪，跳过等待直接写文件
    if not bsp:find("air8101") then
        -- 等待 fota 就绪：最多等待 30 秒
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

    -- 刷写升级包：将临时文件写入 fota 分区
    local result, _, cache = fota.file(temp_path)
    if not result then
        fota.finish(false)
        os.remove(temp_path)
        return false, "fota写入失败"
    end

    -- 等待刷写完成：轮询检查刷写状态
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
        -- 根据缓存大小调整等待时间
        if cache and cache > 65536 then
            sys.wait(500)
        else
            sys.wait(200)
        end
    end

    -- 清理临时文件：释放存储空间
    if io.exists(temp_path) then os.remove(temp_path) end
    log.info("libfota3", "download and flash complete")
    return true
end

-- ==================== 上报结果 ====================

-- 将升级结果发送给FOTA服务器
-- 采用异步任务+重试机制，确保上报成功且不阻塞主线程
local function report_result(fota_sn, result_code)

    -- 等待网络可用：确保网络连接正常，避免上报失败
    if not wait_network() then return end

    -- 确保有有效的升级事务ID
    if not fota_sn or fota_sn == "" then
        log.warn("libfota3", "no fota_sn, skip report")
        return
    end

    -- 构建请求URL：包含 fota_sn 和 result_code 参数
    local url = FOTA_REPORT_URL
        .. "?fota_sn=" .. url_encode(fota_sn)
        .. "&result_code=" .. url_encode(tostring(tonumber(result_code) or 0))

    -- 记录上报信息：便于调试和问题追踪
    log.info("libfota3", "report result", "fota_sn", fota_sn, "code", result_code)

    -- 构建请求体：JSON格式的升级结果数据
    local body = json.encode({
        fota_sn = fota_sn,
        result_code = tonumber(result_code) or 0
    })

    -- 执行上报操作，失败时自动重试
    local function report_task()
        -- 最多重试2次
        for attempt = 1, 2 do
            local code, headers, rsp_body = http.request("POST", url,
                {["Content-Type"] = "application/json"},
                body,
                {timeout = 30000}  -- 30秒超时
            ).wait()

            -- 检查HTTP状态码和业务状态码
            -- HTTP 200 且响应体中 code 为 0 表示成功
            if code == 200 and rsp_body then
                local ok, rsp = pcall(json.decode, rsp_body)
                if ok and rsp and rsp.code == 0 then
                    log.info("libfota3", "report success")
                    return
                end
            end

            -- 记录失败信息：便于调试和问题追踪
            log.warn("libfota3", "report http error", code, "attempt", attempt)

            -- 第一次失败后等待2秒再重试
            if attempt == 1 then sys.wait(2000) end
        end

        -- 最终失败处理：所有重试都失败后记录错误日志
        log.error("libfota3", "report failed after retries")
    end

    -- 启动异步上报任务：在系统任务中执行，不阻塞当前函数
    sys.taskInit(report_task)
end

-- ==================== 开机处理（版本比对 + 上报） ====================

-- 检查上次升级结果并上报服务器
-- 设备重启后，通过版本比对判断升级是否成功，并将结果上报给FOTA服务器
local function handle_boot()
    -- 加载状态文件：检查是否存在未完成的升级记录
    -- 状态文件在检测到新版本时创建，记录升级前后的版本信息
    local state = state_load()
    if not state then
        log.info("libfota3", "no state file, skip boot report")
        return
    end

    -- 通知用户：正在处理上次升级结果
    if opts and opts.on_status then
        opts.on_status("boot_report", "正在检测上次升级结果")
    end

    -- 获取当前版本信息：包括核心版本、核心ID、脚本版本
    -- 需要与升级前后的版本进行比对，判断升级是否成功
    local cur_version, cur_version_id = rtos.version(true)
    local cur_core_version = cur_version and cur_version:gsub("^V", "") or "0"
    local cur_core_id = cur_version_id or "0"
    local cur_script_version = opts and opts.script_version or _G.VERSION or "0.0.0"

    -- 从状态文件获取升级前的版本信息，用于判断核心固件是否发生变化
    local old_core_id = state.old_core_id or "?"
    local old_core_version = state.old_core_version or "?"
    local old_script_version = state.old_script_version or "?"

    -- 从状态文件获取升级后的版本信息，用于记录FOTA服务器期望的升级结果
    local new_core_id = state.new_core_id or "?"
    local new_core_version = state.new_core_version or "?"
    local new_script_version = state.new_script_version or "?"

    -- 记录版本比对信息：便于调试和问题排查
    log.info("libfota3", "=== 升级版本比对 ===")
    log.info("libfota3", string.format("core_id:     old=%s  new=%s  cur=%s", old_core_id, new_core_id, cur_core_id))
    log.info("libfota3", string.format("core_version:old=%s  new=%s  cur=%s", old_core_version, new_core_version, cur_core_version))
    log.info("libfota3", string.format("script_ver:  old=%s  new=%s  cur=%s", old_script_version, new_script_version, cur_script_version))

    -- 判断升级是否成功：比较当前版本与升级前的版本
    -- 核心固件或脚本任一发生变化，则认为升级成功
    local core_changed = (tonumber(cur_core_version) == tonumber(new_core_version)) and (cur_core_id == new_core_id)
    local script_changed = (cur_script_version == new_script_version)
    local result_code = 3  -- 默认值：未知状态

    -- 根据版本变化确定升级结果
    -- result_code 含义：1=成功，2及2以上=失败
    if core_changed and script_changed then
        result_code = 1
        log.info("libfota3", "upgrade success", "core_changed", core_changed, "script_changed", script_changed)
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

    -- 将结果发送给FOTA服务器，需要存在有效的fota_sn（升级事务ID）
    if state.fota_sn and state.fota_sn ~= "" then
        log.info("libfota3", "上报上次升级结果", "fota_sn", state.fota_sn, "code", result_code)
        -- 上报升级结果：包含升级事务ID和结果码
        report_result(state.fota_sn, result_code)
    end

    -- 无论成功失败，都清理状态文件
    state_clear()
end

-- ==================== 用户确认等待 ====================

-- 等待用户确认
local function wait_confirm(action, info)
    -- 无确认回调时默认允许
    if not opts or not opts.on_confirm then
        return true
    end

    -- 重置确认结果，确保每次等待都是全新的状态
    confirm_result = nil

    -- 调用确认回调：通知用户需要确认的操作
    -- callback 函数由用户实现，用于设置确认结果
    opts.on_confirm(action, info, function(ok)
        confirm_result = ok
    end)

    -- 等待用户确认，通过轮询等待用户做出决定
    while confirm_result == nil do
        sys.wait(100)  -- 每100ms检查一次，平衡响应速度和资源消耗
    end

    -- 返回用户决定：true 表示确认，false 表示取消
    return confirm_result
end

-- ==================== 下载流程 ====================

-- 下载升级包并刷写，完成后重启设备
-- 流程说明：网络等待 -> 检查更新结果 -> 下载 -> 刷写 -> 确认重启 -> 重启
local function do_download_flow()
    -- 等待网络可用：确保网络连接正常，避免下载失败
    if not wait_network() then
        running = false
        return
    end

    -- 检查是否有检测结果：确保已经检测过更新
    if not last_check_result then
        if opts and opts and opts.on_status then
            opts.on_status("check_fail", "请先检测更新")
        end
        return
    end

    -- 获取检测结果：包含下载URL和SHA256校验值
    local result = last_check_result
    last_percent = -1  -- 重置下载进度，用于进度回调

    -- 通知用户：开始下载升级包
    if opts and opts and opts.on_status then
        opts.on_status("download_start", "开始下载升级包...")
    end

    -- 调用 HTTP 下载：下载升级包并刷写，回调中通知用户下载进度（只在百分比变化时通知）
    local ok, err = http_download(result.url, result.sha256, function(received, total)
        if total and total > 0 then
            local percent = math.floor(received * 100 / total)
            if percent ~= last_percent then
                last_percent = percent
                local msg = string.format("正在下载: %d%% (%d/%d KB)", percent, received // 1024, total // 1024)
                if opts and opts and opts.on_status then
                    opts.on_status("downloading", msg, percent)
                end
            end
        end
    end)

    -- 处理下载失败：更新状态文件，通知用户
    if not ok then
        local state = state_load()
        if state then
            state.status = "download_fail"
            state_save(state)
        end
        log.error("libfota3", "下载失败:", err)
        if opts and opts and opts.on_status then
            opts.on_status("download_fail", err or "下载失败")
        end
        return
    end

    -- 下载成功：更新状态文件，通知用户
    local state = state_load()
    if state then
        state.status = "download_done"
        state_save(state)
    end

    if opts and opts and opts.on_status then
        opts.on_status("download_done", "升级包已就绪，重启即可升级")
    end

    -- 确认重启：让用户决定是否立即重启升级
    local ok2 = wait_confirm("reboot")
    if not ok2 then
        -- 用户取消：返回，不重启设备
        log.info("libfota3", "用户取消重启升级")
        return
    end

    -- 重启设备：应用升级
    if opts and opts and opts.on_status then
        opts.on_status("rebooting", "正在重启...")
    end
    sys.timerStart(rtos.reboot, 500)
end

-- ==================== 检测流程 ====================

-- 检测更新流程：向FOTA服务器查询新版本，发现新版本后启动下载流程
local function do_check_flow()
    -- 等待网络可用：确保网络连接正常，避免检测失败
    if not wait_network() then
        running = false
        return
    end

    -- 初始化检查结果存储：用于后续流程使用
    if not last_check_result then
        last_check_result = {}
    end

    -- 通知用户：正在检测更新
    if opts and opts.on_status then
        opts.on_status("checking", "正在检测更新...")
    end

    -- 调用 HTTP 检查：向服务器查询新版本
    local result, err = http_check()
    if not result then
        -- 检测失败：通知用户并返回
        if opts and opts.on_status then
            opts.on_status("check_fail", err or "检测失败")
        end
        return
    end

    -- 判断是否有新版本：result.code 不为 0 表示无新版本
    if result.code and result.code ~= 0 then
        if opts and opts.on_status then
            opts.on_status("no_new_version", result.msg or "当前已是最新版本")
        end
        return
    end

    -- 有新版本：保存检查结果，用于后续下载流程
    last_check_result = result

    -- 记录当前版本信息：用于开机时比对升级是否成功
    local cur_ver, cur_ver_id = rtos.version(true)
    local state = {
        fota_sn = result.fota_sn or "",  -- 升级事务ID，用于上报结果
        status = "has_update",           -- 状态：有新版本
        old_core_id = cur_ver_id or "0", -- 升级前核心ID
        old_core_version = cur_ver and cur_ver:gsub("^V", "") or "0", -- 升级前核心版本
        old_script_version = opts and opts.script_version or opts and _G.VERSION or "0.0.0", -- 升级前脚本版本
        new_core_id = result.core_id or "?",           -- 升级后核心ID
        new_core_version = result.core_version or "?", -- 升级后核心版本
        new_script_version = result.script_version or "0.0.0" -- 升级后脚本版本
    }

    -- 通知用户：发现新版本
    local msg = string.format("发现新版本 %s (%s)",
        result.script_version or "?",
        result.size and (math.floor(result.size / 1024) .. "KB") or "未知大小")
    if opts and opts.on_status then
        opts.on_status("new_version", msg)
    end

    -- 确认下载：让用户决定是否下载升级包
    local info = {
        version = result.script_version,
        size = result.size,
        fota_sn = result.fota_sn,
    }
    local ok = wait_confirm("download", info)
    if not ok then
        -- 用户取消：返回，不启动下载流程
        log.info("libfota3", "用户取消下载")
        return
    end

    -- 更新状态文件
    state_save(state)

    -- 启动下载流程：下载升级包并刷写
    do_download_flow()
end

-- ==================== 定时器管理 ====================

-- 定时器回调函数：定时触发检测更新流程
local function on_timer()
    -- 在系统任务中执行检测：避免阻塞定时器回调
    sys.taskInit(function()
        -- 获取当前配置
        local interval = 86400
        if opts and opts.interval then
            interval = opts.interval
        end

        -- 执行检测更新流程
        do_check_flow()

        -- 检测完成后更新时间戳到文件
        if time_synced then
            timer_state_save(os.time())
        end

        -- 启动下次单次定时器（固定间隔）
        auto_timer_id = sys.timerStart(on_timer, interval * 1000)
        log.info("libfota3", "下次检测间隔", interval, "秒")
    end)
end

-- 根据用户配置启动或停止定时检测
local function setup_timer()
    -- 清理现有定时器：避免重复定时器导致资源泄漏
    if auto_timer_id then
        sys.timerStop(auto_timer_id)
        auto_timer_id = nil
    end

    local auto, interval = true, 86400

    -- 从配置参数中获取自动检测开关和间隔时间
    if opts and opts.auto ~= nil then
        auto = opts.auto
    end
    if opts and opts.interval then
        interval = opts.interval
    end

    -- 未启用自动检测，不启动定时器
    if not auto or not interval or interval <= 0 then
        log.info("libfota3", "未启用自动检测，不启动定时器")
        return
    end

    if time_synced then
        -- 时间已同步：使用时间戳计算剩余等待时间
        local last_ts = timer_state_load()
        local now = os.time()
        local wait_sec = (last_ts + interval) - now

        if wait_sec <= 0 then
            -- 已过期或首次运行，立即触发检测
            log.info("libfota3", "检测已过期或首次运行，立即触发")
            on_timer()
        else
            -- 启动单次定时器
            auto_timer_id = sys.timerStart(on_timer, wait_sec * 1000)
            log.info("libfota3", "定时器已启动，等待", wait_sec, "秒后检测",
                     "预计时间", os.date("%Y-%m-%d %H:%M:%S", now + wait_sec))
        end
    else
        -- 时间未同步：不启动定时器
        log.warn("libfota3", "时间未同步，定时器未启动")
    end
end

-- ==================== 公共 API ====================

--[[
@api libfota3.request(opts)
@summary 启动FOTA升级流程
@description 
    等待时间同步完成后启动自动检测定时器。
    根据时间同步结果选择定时策略：
    - 时间同步成功：基于时间戳计算剩余等待时间，跨重启延续进度
    - 时间同步超时：不启动定时器
    支持多次调用，可动态修改配置参数。如需立即检测，可单独使用
    check_update()。
@param opts table 必填，配置参数表，包含以下字段：
    - project_key string 必填，项目密钥，用于FOTA服务认证
    - script_name string 选填，脚本名称，默认使用 _G.PROJECT
    - script_version string 选填，脚本版本，默认使用 _G.VERSION
    - auto boolean 选填，是否自动定时检测，默认 true
    - interval number 选填，自动检测间隔（秒），默认 86400（24小时）
    - on_status function 选填，状态回调函数，参数为 (status, msg, percent)
        status string 状态码，取值：
        - "network_fail"：网络连接失败
        - "boot_report"：正在检测上次升级结果
        - "checking"：正在检测更新
        - "check_fail"：检测失败
        - "no_new_version"：当前已是最新版本
        - "new_version"：发现新版本
        - "download_start"：开始下载升级包
        - "downloading"：正在下载（包含进度）
        - "download_fail"：下载失败
        - "download_done"：升级包已就绪
        - "rebooting"：正在重启
        - "upgrade_success"：升级成功
        - "upgrade_fail"：升级失败/无变化
        msg string 状态描述信息，用于日志记录或用户提示，参考状态码说明
        percent number 下载进度百分比（0-100），仅在 status="downloading" 时有效，其他状态为 nil
    - on_confirm function 选填，确认回调函数，用于有屏幕设备让用户确认操作
        参数为 (action, info, callback)
        action 取值：
        - "download"：确认下载，info 包含 version, size, fota_sn
        - "reboot"：确认重启，info 为 nil
        callback(boolean)：调用 callback(true) 确认，callback(false) 取消
@return 无返回值
@usage 
libfota3.request({
    project_key = "your_project_key",    -- 项目密钥，用于FOTA服务认证
    script_name = "fota3_temp",          -- 脚本名称
    script_version = "001.999.000",      -- 脚本版本
    auto = true,                         -- 启用自动定时检测
    interval = 86400,                    -- 自动检测间隔（秒），默认24小时
    on_status = function(status, msg, percent)
        log.info("fota_temp", status, msg, percent)
    end,
    on_confirm = function(action, info, callback)
        if action == "download" then
            -- true 表示用户确认下载
            callback(true)
        elseif action == "reboot" then
            -- true 表示用户确认重启升级
            callback(true)
        end
    end,
})
]]
function libfota3.request(new_opts)
    -- 防止重复启动
    if running then
        log.info("libfota3", "FOTA 流程已在运行中，跳过本次执行")
        return
    end

    -- 更新配置
    if new_opts then
        opts = new_opts
    end

    -- 设置运行标志：防止重复触发
    running = true

    -- 在系统任务中执行：避免阻塞主线程
    -- 任务顺序设计：
    -- 1. wait_time_sync()：等待时间同步完成
    -- 2. setup_timer()：根据时间同步结果启动定时器
    --    - 时间同步成功且已过期：立即触发 on_timer() → do_check_flow()
    --    - 时间同步成功未过期：启动单次定时器等待
    --    - 时间同步超时：不启动定时器
    -- 3. running = false：流程完成，重置运行标志
    sys.taskInit(function()
        -- 等待时间同步完成
        time_synced = wait_time_sync()
        -- 根据同步结果启动定时器
        setup_timer()
        -- 流程完成，释放运行标志
        running = false
    end)
end

--[[
@api libfota3.check_update()
@summary 检测更新
@description 仅执行 do_check_flow()，含网络检测 → 下载 → 刷写 → 重启。
    复用 running 标志，与 request() 互斥。
@usage
    libfota3.check_update()
]]
function libfota3.check_update()
    if running then
        log.info("libfota3", "FOTA 流程已在运行中，跳过本次执行")
        return
    end
    -- 标记运行中，与其他调用互斥
    running = true
    sys.taskInit(function()
        do_check_flow()
        -- 检测完成后更新时间戳，重置定时器
        if time_synced then
            timer_state_save(os.time())
        end
        setup_timer()
        -- 流程结束，释放运行标志
        running = false
    end)
end

--[[
@api libfota3.config(new_opts)
@summary 动态修改 FOTA 配置，参数格式与 request() 一致
@description 更新配置后自动处理定时器启停。支持传入部分参数，未传的保持原值。
@param table new_opts 配置参数表，支持字段：
    - auto boolean 选填，是否自动定时检测
    - interval number 选填，自动检测间隔（秒）
@usage
    libfota3.config({auto = true, interval = 86400})
    libfota3.config({auto = false})
]]
function libfota3.config(new_opts)
    opts = opts or {}
    if not new_opts then return end

    -- 记录变更前的值，用于判断是否需要重启定时器
    local old_auto = opts.auto
    local old_interval = opts.interval

    -- 合并新配置到 opts
    for k, v in pairs(new_opts) do
        opts[k] = v
    end

    -- auto 或 interval 有变化时才执行定时器刷新
    if opts.auto ~= old_auto or opts.interval ~= old_interval then
        -- 重置时间戳，从新的 interval 重新开始计时
        -- 1. auto 从 false 变为 true
        -- 2. interval 变化
        if time_synced then
            timer_state_save(os.time())
        end
        setup_timer()
    end
end

-- 模块加载时自动执行开机上报
-- 此时 opts 为 nil，handle_boot 会使用默认值，不影响主流程
sys.taskInit(handle_boot)

return libfota3
