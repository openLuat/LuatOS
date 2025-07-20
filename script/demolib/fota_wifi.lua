--[[
-- @module fota_wifi
-- @summary 用于Air8000/8000A/8000W型号模组自动升级WIFI
-- @version 1.0.1
-- @date    2025.6.26
-- @author  tuoyiheng
-- @usage
--注：使用时在创建的一个task处理函数中直接调用fota_wifi.request()即可开始执行WiFi升级任务
--用法实例
local fota_wifi = require("fota_wifi")

local function wifi_fota_task_func()
    -- ...此处省略很多代码

    local result = fota_wifi.request()
    if result then
        log.info("fota_wifi", "升级任务执行成功")
    else
        log.info("fota_wifi", "升级任务执行失败")
    end

    -- ...此处省略很多代码
end

-- 判断网络是否正常
local function wait_ip_ready()
    local result, ip, adapter = sys.waitUntil("IP_READY", 30000)
    if result then
        log.info("fota_wifi", "开始执行升级任务")
        sys.taskInit(wifi_fota_task_func)
    else
        log.error("当前正在升级WIFI&蓝牙固件，请插入可以上网的SIM卡")
    end
end

-- 在设备启动时检查SIM卡状态
sys.taskInit(wait_ip_ready)
]]
local fota_wifi = {}
local is_request = false -- 标记是否正在执行request任务
local fota_result = false -- 记录fota任务的执行结果

-- 判断是否为空
local function is_nil(s)
    return s == nil or s == ""
end

-- 判断json是否合法
local function is_json(str)
    local success, result = pcall(json.decode, str)
    return success and type(result) == "table"
end

-- 解析服务器响应的json数据
local function parse_response(body)
    if not body or body == "" then
        log.error("fota_wifi", "返回的body为空")
        return nil
    end

    local success, json_body = pcall(json.decode, body)
    if success and type(json_body) == "table" then
        log.info("fota_wifi", "解析服务器响应成功")
        return json_body
    else
        log.error("fota_wifi", "解析服务器响应失败，body内容:", body)
        return nil
    end
end

-- 判断是否需要升级，返回true或false
local function need_fota(version, server_version)
    local version_num = tonumber(version)
    local server_version_num = tonumber(server_version)
    if version_num < server_version_num then
        return true
    end
    return false
end

-- 下载升级文件，支持断点续传
local function download_file(url)
    local file_path = "/ram/fotawifi.bin"
    local downloaded_size = 0

    -- 检查文件是否存在，获取已下载的大小
    if io.exists(file_path) then
        downloaded_size = io.fileSize(file_path)
        log.info("fota_wifi", "检测到未完成的下载，已下载大小:", downloaded_size)
    end

    -- 设置请求头，支持断点续传
    local headers = {}
    if downloaded_size > 0 then
        headers["Range"] = "bytes=" .. downloaded_size .. "-"
    end

    local code, headers, body = http.request("GET", url, headers, nil, nil).wait()
    if code == 200 or code == 206 then
        -- 开始写入文件
        local file_mode = downloaded_size > 0 and "a+" or "w+"
        local file = io.open(file_path, file_mode)
        if file then
            file:seek("end", downloaded_size)
            file:write(body)
            file:close()

            -- 判断文件是否下载完整
            local file_size = io.fileSize(file_path)
            local content_length = tonumber(headers["content-length"] or headers["Content-Length"])
            if file_size >= (content_length or file_size) then
                log.info("fota_wifi", "下载升级文件成功,文件路径:", file_path)
                return file_path
            else
                log.info("fota_wifi", "下载中...当前大小:", file_size, "目标大小:", content_length)
            end
        else
            log.error("fota_wifi", "无法创建文件")
            -- 删除不完整的文件
            os.remove(file_path)
        end
    else
        log.error("fota_wifi", "下载失败,状态码:", code)
        -- 删除不完整的文件
        if io.exists(file_path) then
            os.remove(file_path)
        end
    end
    return nil
end

-- 执行升级操作
local function fota_start(file_path)
    -- 检查文件是否存在
    if not io.exists(file_path) then
        log.error("fota_wifi", "升级文件不存在")
        return false
    end

    -- 检查文件大小是否超过256K (256 * 1024 Bytes)
    local file_size = io.fileSize(file_path)
    if file_size < 256 * 1024 then
        log.error("fota_wifi", "升级文件大小不足256K，文件大小:", file_size)
        return false
    end

    -- 执行airlink.sfota操作
    local result = airlink.sfota(file_path)
    if result then
        log.info("fota_wifi", "升级成功")
        -- 释放文件占用的空间
        -- 因为sfota是异步执行的，所以这里不能用os.remove()删除文件
        file_path = nil
        return true
    else
        log.error("fota_wifi", "升级失败")
        os.remove(file_path)
        return false
    end
end


--[[
Air8000系列模组自动升级wifi
@api fota_wifi.request()
@return bool 成功返回true
@usage
local result = fota_wifi.request()
if result then
    log.info("fota_wifi", "升级任务执行成功")
else
    log.info("fota_wifi", "升级任务执行失败")
end
]]
function fota_wifi.request()
    if is_request then
        log.warn("fota_wifi", "升级任务正在执行中，请勿重复调用")
        return false
    end

    is_request = true
    fota_result = false

    -- 构建请求URL
    local url = "http://wififota.openluat.com/air8000/update.json"
    local imei = is_nil(mobile.imei()) and "未知imei" or mobile.imei()
    local version = is_nil(airlink.sver()) and "未知版本" or airlink.sver()
    local muid = is_nil(mobile.muid()) and "未知muid" or mobile.muid()
    local hw = is_nil(hmeta.hwver()) and "未知硬件版本" or hmeta.hwver()
    local request_url = string.format("%s?imei=%s&version=%s&muid=%s&hw=%s", url, imei, version, muid, hw)

    log.info("fota_wifi", "正在请求升级信息, URL:", request_url)

    -- 发送HTTP请求获取服务器响应
    local code, headers, body = http.request("GET", request_url, {}, nil, {timeout = 30000}).wait()
    if code == 200 then
        log.info("fota_wifi", "获取服务器响应成功")
        -- 打印返回的body内容
        -- log.info("fota_wifi", "body:", body)
        -- 解析服务器响应的json数据
        local response = parse_response(body)
        if response then
            -- 获取服务器返回的版本号和下载链接
            local server_version = response.version
            local download_url = response.url

            -- 获取本地版本号
            local local_version = airlink.sver()

            -- 判断是否需要升级
            if need_fota(local_version, server_version) then
                log.info("fota_wifi", "需要升级, 本地版本:", local_version, "服务器版本:", server_version)
                -- 下载升级文件
                local file_path = download_file(download_url)
                if file_path then
                    -- 开始升级
                    fota_result = fota_start(file_path)
                end
            else
                log.info("fota_wifi", "当前已是最新WIFI固件")
                fota_result = true
            end
        else
            log.error("fota_wifi", "解析服务器响应失败")
        end
    else
        log.error("fota_wifi", "获取服务器响应失败,状态码:", code)
    end

    -- 释放请求标记
    is_request = false
    return fota_result
end

return fota_wifi
