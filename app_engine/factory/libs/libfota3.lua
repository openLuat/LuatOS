--[[
@module libfota3
@summary 合宙整机成品FOTA升级（两步协议：检查→下载→上报）
@version 1.0
@date    2026.05.27
@author  江访
@usage
-- 检查更新
local libfota3 = require("libfota3")
local result, err = libfota3.check()
if result and result.code == 0 then
    log.info("有新版本", result.script_version, result.size)
    -- 下载升级
    local ok, err2 = libfota3.download(result.url, result.sha256, function(r, t)
        log.info("进度", r, t)
    end)
    if ok then
        -- 重启前上报成功
        libfota3.report_result(result.fota_sn, 0)
        rtos.reboot()
    end
else
    log.info("无更新或出错", err)
end
]]

local libfota3 = {}

local FOTA_CHECK_URL  = "http://iot.openluat.com/api/site/turnkey_fota"
local FOTA_REPORT_URL = "http://iot.openluat.com/api/site/turnkey_fota_result"
local DEFAULT_TIMEOUT = 120000

----------------------------------------------------------------------
-- 内部工具函数
----------------------------------------------------------------------

-- 获取设备标识（优先IMEI，其次MAC，最后MCU唯一ID）
local function get_device_id()
    if mobile and mobile.imei then
        local ok, imei = pcall(mobile.imei)
        if ok and imei and #tostring(imei) >= 10 then
            return "imei", tostring(imei)
        end
    end
    if wlan and wlan.getMac then
        local ok, mac = pcall(wlan.getMac)
        if ok and mac and #tostring(mac) >= 12 then
            return "mac", tostring(mac)
        end
    end
    if _G.IMEI and #tostring(_G.IMEI) >= 10 then
        return "imei", tostring(_G.IMEI)
    end
    -- 兜底：MCU唯一ID（WiFi-only模组如Air1601等无IMEI/MAC时使用）
    if mcu and mcu.unique_id then
        local ok, uid = pcall(mcu.unique_id)
        if ok and uid then
            return "uid", tostring(uid)
        end
    end
    return nil, nil
end

-- SHA256校验（从文件读取并计算）
local function verify_sha256(file_path, expected)
    if not expected or expected == "" then
        log.warn("libfota3", "no sha256 provided, skip verification")
        return true
    end
    expected = expected:lower()
    -- 使用crypto库计算SHA256
    if not crypto or not crypto.sha256 then
        log.warn("libfota3", "crypto.sha256 not available, skip verification")
        return true
    end
    local ok, hash = pcall(crypto.sha256, file_path, "file")
    if not ok or not hash then
        log.error("libfota3", "sha256 compute failed", ok, hash)
        return false
    end
    hash = hash:lower()
    if hash ~= expected then
        log.error("libfota3", "sha256 mismatch", "expected", expected, "got", hash)
        return false
    end
    log.info("libfota3", "sha256 verified")
    return true
end

----------------------------------------------------------------------
-- 公共API
----------------------------------------------------------------------

--[[
检查是否有新版本可用

@api libfota3.check(opts)
@table opts 可选参数（所有字段均可选，有默认值）
  project_key:  项目密钥，默认 _G.PROJECT_KEY
  imei:         设备IMEI（4G模块），自动检测
  mac:          设备MAC（WiFi模块），自动检测
  core_name:    固件名，默认从 rtos.firmware() 提取
  core_id:      固件编号，默认 rtos.version(true) 第二返回值
  core_version: 固件版本号，默认 rtos.version()
  script_name:  脚本名，默认 _G.PROJECT
  script_version: 脚本版本号，默认 _G.VERSION
  timeout:      超时毫秒，默认 120000
@return table|nil 成功返回 {code, core_version, script_version, size, sha256, fota_sn, url, msg}
@return string|nil 失败原因
]]
function libfota3.check(opts)
    opts = opts or {}
    local project_key = opts.project_key or _G.PROJECT_KEY or _G.PRODUCT_KEY
    if not project_key then
        return nil, "缺少project_key"
    end

    -- 设备标识
    local id_type, id_val
    if opts.imei then
        id_type, id_val = "imei", opts.imei
    elseif opts.mac then
        id_type, id_val = "mac", opts.mac
    else
        id_type, id_val = get_device_id()
    end
    if not id_val then
        return nil, "无法获取设备标识(IMEI/MAC)"
    end

    -- 固件信息
    local core_version = opts.core_version
    if not core_version then
        local v = rtos.version()
        core_version = v and v:gsub("^V", "") or "0"
    end
    local core_id = opts.core_id or select(2, rtos.version(true)) or "0"
    local core_name = opts.core_name
    if not core_name then
        local fw = rtos.firmware()
        core_name = fw and fw:gsub("_V%d+", "") or "LuatOS-SoC_" .. rtos.bsp()
    end
    local script_name = opts.script_name or _G.PROJECT or ""
    local script_version = opts.script_version or _G.VERSION or "0.0.0"
    local timeout = opts.timeout or DEFAULT_TIMEOUT

    -- 构建URL
    local url = FOTA_CHECK_URL
        .. "?" .. id_type .. "=" .. id_val
        .. "&project_key=" .. project_key
        .. "&core_name=" .. core_name
        .. "&core_id=" .. tostring(core_id)
        .. "&core_version=" .. core_version
        .. "&script_name=" .. script_name
        .. "&script_version=" .. script_version

    log.info("libfota3", "check", "id", id_type, id_val, "core", core_name, core_id, core_version, "script", script_version)

    local code, headers, body = http.request("GET", url, nil, nil, {timeout = timeout}).wait()
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

--[[
下载升级包并写入flash

@api libfota3.download(url, sha256, progress_cb)
@string url 下载地址（来自check返回的url字段）
@string sha256 预期的SHA256校验值（可选，为空则跳过校验）
@function progress_cb 进度回调 function(received_bytes, total_bytes) end（可选）
@return boolean 成功返回true
@return string|nil 失败原因
]]
function libfota3.download(url, sha256, progress_cb)
    if not url or url == "" then
        return false, "缺少下载地址"
    end

    -- 确定临时文件路径
    local temp_path = "/ram/fota_update.bin"
    -- PSAM空间不足时回退到内置文件系统
    local psram_total, psram_used = rtos.meminfo("psram")
    local psram_free = psram_total and psram_used and (psram_total - psram_used) or 0
    if psram_free < 512 * 1024 then  -- 不足512KB时回退
        temp_path = "/fota_update.bin"
        log.info("libfota3", "psram low, use internal fs for temp file")
    end
    -- 删除可能残留的旧文件
    if io.exists(temp_path) then os.remove(temp_path) end

    log.info("libfota3", "download", url, "->", temp_path)

    local code, headers = http.request("GET", url, nil, nil, {
        dst = temp_path,
        timeout = 600000,  -- 10分钟超时
        callback = function(total, received)
            if progress_cb and total and total > 0 then
                progress_cb(received, total)
            end
        end
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

    -- SHA256校验
    if not verify_sha256(temp_path, sha256) then
        os.remove(temp_path)
        return false, "SHA256校验失败"
    end

    -- 写入flash：初始化fota → 等待就绪 → fota.file → 等待完成
    if not fota then
        os.remove(temp_path)
        return false, "fota模块不可用"
    end
    if not fota.init() then
        os.remove(temp_path)
        return false, "fota初始化失败"
    end
    local wait_start = os.clock()
    while not fota.wait() do
        if os.clock() - wait_start > 30 then
            fota.finish(false)
            os.remove(temp_path)
            return false, "fota等待超时"
        end
        sys.wait(100)
    end

    local result, _, cache = fota.file(temp_path)
    if not result then
        fota.finish(false)
        os.remove(temp_path)
        return false, "fota写入失败"
    end
    -- 等待fota完成
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

    -- 删除临时文件
    if io.exists(temp_path) then os.remove(temp_path) end

    log.info("libfota3", "download and flash complete")
    return true
end

--[[
上报升级结果给服务器

@api libfota3.report_result(fota_sn, result_code)
@string fota_sn 升级序列号（check返回的fota_sn）
@number result_code 结果码：0=成功 1=校验失败 2=写入失败 3=其他错误
@return boolean 上报是否成功
]]
function libfota3.report_result(fota_sn, result_code)
    if not fota_sn or fota_sn == "" then
        log.warn("libfota3", "no fota_sn, skip report")
        return false
    end
    local url = FOTA_REPORT_URL
        .. "?fota_sn=" .. fota_sn
        .. "&result_code=" .. tostring(result_code or 0)

    log.info("libfota3", "report result", "fota_sn", fota_sn, "code", result_code)

    -- 最多重试1次
    for attempt = 1, 2 do
        local code, headers, body = http.request("POST", url, nil, nil, {timeout = 30000}).wait()
        if code == 200 then
            log.info("libfota3", "report success")
            return true
        end
        log.warn("libfota3", "report http error", code, "attempt", attempt)
        if attempt == 1 then sys.wait(2000) end
    end
    log.error("libfota3", "report failed after retries")
    return false
end

return libfota3
