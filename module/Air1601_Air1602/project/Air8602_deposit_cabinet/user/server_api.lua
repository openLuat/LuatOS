--[[
@module  server_api
@summary 服务器接口模块
@version 2.0
@date    2026.10.16
@author  王城钧
@usage
本模块实现智能寄存柜系统与服务器之间的API通信
支持存件(face_store)、取件、柜子状态同步、小程序码生成等功能
]]


-- 先声明 server_api 变量
local server_api = {}

-- 加载配置模块
local config = require "config"

-- 服务器配置
local SERVER_CONFIG = {
    host = config.get("server.host"),
    port = config.get("server.port"),
    api_path = config.get("server.api_path")
}

-- 获取设备唯一标识（按可用硬件源自动适配）
local function get_device_id()
    -- 4G设备优先使用IMEI
    local imei = mobile.imei()
    if imei then
        return imei
    end
    -- WiFi设备使用MAC地址
    local mac = wlan.getMac(nil, true)
    if mac then
        return mac
    end
    -- 最后使用MCU唯一ID
    local uid = mcu.unique_id()
    if uid then
        return uid:toHex()
    end
    return "unknown"
end

-- HTTP请求函数
local function http_request(url, params, method)
    local method = method or "POST"

    -- 网络未就绪时直接返回，避免底层 airlink 失败导致死机
    if not socket.adapter(socket.dft()) then
        log.warn("server_api", "网络未就绪，无法发送请求")
        return nil, "网络未就绪"
    end

    -- 构建完整URL
    -- 根据协议和端口构建URL
    local full_url
    if SERVER_CONFIG.port == 443 then
        full_url = string.format("https://%s%s%s", SERVER_CONFIG.host, SERVER_CONFIG.api_path, url)
    else
        full_url = string.format("https://%s:%d%s%s", SERVER_CONFIG.host, SERVER_CONFIG.port, SERVER_CONFIG.api_path, url)
    end
    
    log.info("server_api", method .. " 请求: " .. full_url)
    
    -- 构建请求数据
    local request_data = json.encode(params)
    
    log.info("server_api", "请求数据: " .. request_data)
    
    -- 详细打印请求参数
    log.debug("server_api", "HTTP请求详情:")
    log.debug("server_api", "方法: " .. method)
    log.debug("server_api", "URL: " .. full_url)
    log.debug("server_api", "请求头: " .. json.encode({["Content-Type"] = "application/json"}))
    log.debug("server_api", "请求体: " .. request_data)
    
    -- 发送HTTP请求，调用wait()方法获取响应
    local code, headers, body = http.request(method, full_url, {
        ["Content-Type"] = "application/json"
    }, request_data).wait()
    
    -- 详细打印响应结果
    log.debug("server_api", "HTTP响应原始返回值:")
    log.debug("server_api", "code: " .. tostring(code))
    log.debug("server_api", "headers 对象类型: " .. type(headers))
    log.debug("server_api", "body 对象类型: " .. type(body))
    
    if code < 0 then
        log.error("server_api", "HTTP请求失败: 错误码 " .. tostring(code))
        return nil, "HTTP请求失败: 错误码 " .. tostring(code)
    end
    
    -- 打印响应状态和内容
    log.info("server_api", "响应状态码: " .. tostring(code))
    if body then
        log.info("server_api", "响应内容: " .. tostring(body))
    else
        log.info("server_api", "响应内容为空")
    end
    
    -- 检查响应状态码
    if code ~= 200 then
        log.error("server_api", "HTTP状态码错误: " .. tostring(code))
        return nil, "HTTP状态码错误: " .. tostring(code)
    end
    
    -- 解析响应
    local result = json.decode(body)
    
    if not result then
        log.error("server_api", "响应解析失败，响应内容: " .. tostring(body))
        return nil, "响应解析失败"
    end
    
    return result
end

-- 初始化柜子（发送箱子数据到服务器）
function server_api.init_locker(box_info)
    local params = {
        deviceid = get_device_id(),
        data = box_info
    }
    
    log.info("server_api", "柜子初始化请求参数: " .. json.encode(params))
    
    local result, err = http_request("/init", params)
    
    if result then
        log.info("server_api", "柜子初始化响应: " .. json.encode(result))
        
        if result.code == 0 then
            log.info("server_api", "柜子初始化成功")
            return true, result
        else
            log.error("server_api", "柜子初始化失败: 服务器返回错误码 " .. (result.code or "未知"))
            return false, result
        end
    else
        log.error("server_api", "柜子初始化失败: " .. (err or "未知错误"))
        return false, err
    end
end

-- 生成微信小程序码
function server_api.generate_wechat_qr_code()
    -- 网络未就绪时直接返回，避免底层 airlink 失败导致死机
    if not socket.adapter(socket.dft()) then
        log.warn("server_api", "网络未就绪，无法生成小程序码")
        return nil, "网络未就绪"
    end

    local params = {
        project = "smart_locker",
        scene = get_device_id(),
        page = "pages/index/index",
        width = 432  -- 图片尺寸必须为16的倍数，且符合微信小程序码接口合法范围(280~1280)；432=27*16
    }
    
    log.info("server_api", "生成小程序码请求参数: " .. json.encode(params))
    
    -- 构建完整URL
    local full_url
    if SERVER_CONFIG.port == 443 then
        full_url = string.format("https://%s/iot/t3rd/wx_gen_app_code", SERVER_CONFIG.host)
    else
        full_url = string.format("https://%s:%d/iot/t3rd/wx_gen_app_code", SERVER_CONFIG.host, SERVER_CONFIG.port)
    end
    
    -- 图片保存路径（使用文件系统区）
    local qr_file_path = "/qr_code.jpeg"
    
    -- 发送HTTP请求，使用opts.dst参数直接将响应保存到文件中
    local code, headers, body_length = http.request("POST", full_url, {
        ["Content-Type"] = "application/json"
    }, json.encode(params), {
        dst = qr_file_path, -- 直接保存到文件
        timeout = 30000 -- 30秒超时
    }).wait()
    
    if code < 0 then
        log.error("server_api", "生成小程序码失败: 错误码 " .. tostring(code))
        return nil, "生成小程序码失败: 错误码 " .. tostring(code)
    end
    
    -- 检查响应是否是图片数据（图片响应通常会有Content-Type: image/...）
    if type(headers) == "table" then
        local content_type = headers["Content-Type"]
        if content_type and string.find(content_type, "image") then
            log.info("server_api", "小程序码生成成功，图片大小: " .. tostring(body_length) .. "字节")
            -- 检查文件是否成功创建
            if io.exists(qr_file_path) then
                log.debug("server_api", "图片文件成功保存到: " .. qr_file_path)
                -- 验证文件是否是有效的JPEG格式
                local file_content = io.readFile(qr_file_path)
                if file_content and #file_content > 2 and file_content:sub(1, 2) == "\255\216" then
                    log.debug("server_api", "成功读取图片文件内容，大小: " .. string.len(file_content) .. "字节，是有效的JPEG格式")
                    return file_content, nil -- 返回图片二进制数据
                else
                    log.error("server_api", "下载的图片文件格式无效，不是有效的JPEG图片")
                    log.debug("server_api", "文件前2字节: " .. (file_content and file_content:sub(1, 2):toHex() or "nil"))
                    return nil, "下载的图片格式无效"
                end
            else
                log.error("server_api", "图片文件未成功创建")
                return nil, "图片文件未成功创建"
            end
        else
            -- 可能是错误响应
            log.error("server_api", "生成小程序码失败: 服务器返回非图片响应")
            -- 尝试解析响应内容
            if body_length then
                local file_content = io.readFile(qr_file_path)
                if file_content then
                    log.debug("server_api", "响应内容: " .. file_content)
                    local result, parse_err = json.decode(file_content)
                    if result then
                        log.error("server_api", "生成小程序码失败: " .. (result.msg or "未知错误"))
                        return nil, result
                    end
                end
            end
            return nil, "服务器返回非图片响应"
        end
    else
        log.error("server_api", "HTTP请求失败，headers类型错误: " .. type(headers))
        return nil, "HTTP请求失败"
    end
end

-- 获取取件码
function server_api.get_pickup_code(box_num)
    local params = {
        box_num = box_num
    }
    
    local result, err = http_request("/get_pickup_code", params)
    
    if result and result.code == 0 then
        log.info("server_api", "获取取件码成功")
        return true, result.value
    end
    
    log.error("server_api", "获取取件码失败: " .. (err or "未知错误"))
    return false, err
end

-- 验证取件码
function server_api.verify_pickup_code(box_num, code)
    local params = {
        box_num = box_num,
        code = code
    }
    
    local result, err = http_request("/verify_pickup_code", params)
    
    if result and result.code == 0 then
        log.info("server_api", "取件码验证成功")
        return true, result.value
    end
    
    log.error("server_api", "取件码验证失败: " .. (err or "未知错误"))
    return false, err
end

-- 人脸存件操作（POST /face_store）
-- 请求参数: {deviceid, box, face_id, face_name}
-- 成功响应: {code:0, value:{box, pickup_code, save_code, record_id}}
-- 失败响应: {code:55, value:"该柜子已占用"}（value 为字符串错误信息）
function server_api.face_store(box_num, face_id, face_name)
    local params = {
        deviceid = get_device_id(),
        box = box_num,
        face_id = face_id,
        face_name = face_name
    }
    
    local result, err = http_request("/face_store", params)
    
    if result and result.code == 0 then
        log.info("server_api", "人脸存件操作成功")
        return true, result.value
    end
    
    -- 失败时服务器返回的 value 可能是字符串错误信息（如"该柜子已占用"）
    local fail_msg = err or "存件请求失败"
    if result and result.value and type(result.value) == "string" then
        fail_msg = result.value
        log.error("server_api", "人脸存件失败: 服务器返回错误码 " .. tostring(result.code) .. ", " .. fail_msg)
    else
        log.error("server_api", "人脸存件失败: " .. fail_msg)
    end
    return false, fail_msg
end

-- 取件操作
function server_api.pickup_item(box_num, code)
    local params = {
        box_num = box_num,
        code = code
    }
    
    local result, err = http_request("/pickup", params)
    
    if result and result.code == 0 then
        log.info("server_api", "取件操作成功")
        return true, result.value
    end
    
    log.error("server_api", "取件操作失败: " .. (err or "未知错误"))
    return false, err
end

-- 获取柜子状态
function server_api.get_locker_status()
    local result, err = http_request("/status", {}, "GET")
    
    if result and result.code == 0 then
        log.info("server_api", "获取柜子状态成功")
        return true, result.value
    end
    
    log.error("server_api", "获取柜子状态失败: " .. (err or "未知错误"))
    return false, err
end

-- 同步柜子状态
function server_api.sync_status(status_data)
    local params = {
        status_data = status_data
    }
    
    local result, err = http_request("/sync_status", params)
    
    if result and result.code == 0 then
        log.info("server_api", "柜子状态同步成功")
        return true, result.value
    end
    
    log.error("server_api", "柜子状态同步失败: " .. (err or "未知错误"))
    return false, err
end

-- 模块初始化
local function init()
    log.info("server_api", "服务器接口模块初始化")
end

-- 自动初始化
init()

-- 对外接口
return server_api
