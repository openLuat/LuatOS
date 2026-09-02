--[[
@module  server_api
@summary 服务器接口模块
@version 1.0
@date    2026.10.16
@author  王城钧
@usage
本模块实现智能寄存柜系统与服务器之间的API通信
支持存件、取件、柜子状态同步等功能
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

-- 获取设备唯一标识（优先使用配置的自定义设备号，未配置时自动使用 MCU 唯一 ID）
local function get_device_id()
    -- 优先使用 config.device.device_id（仅当服务器要求特定格式设备号时填写）
    local device_id = config.get("device.device_id")
    if device_id and device_id ~= "" then
        return device_id
    end
    -- 使用 MCU 唯一 ID（软件不可更改，Air1601 系列返回 6 字节，转 hex 后如 "3A2F9C1B8E4D"）
    local uid = mcu.unique_id()
    if uid and uid:toHex() and uid:toHex() ~= "" then
        return uid:toHex()
    end
    -- 回退使用 STA MAC 地址（如 "C8C2C6906511"）
    if wlan and wlan.getMac then
        local mac = wlan.getMac(0, true)
        if mac and mac ~= "" then
            return mac
        end
    end
    -- 4G设备回退使用IMEI
    local imei = mobile.imei()
    if imei then
        return imei
    end
    return "unknown"
end

-- HTTP请求函数（带重试：4G airlink 链路瞬断时自动重试）
-- 参数：url(接口路径), params(请求体), method(默认POST)
-- 返回：成功 result(table)，失败 nil, err
local function http_request(url, params, method)
    local method = method or "POST"

    -- 构建完整URL
    local full_url
    if SERVER_CONFIG.port == 443 then
        full_url = string.format("https://%s%s%s", SERVER_CONFIG.host, SERVER_CONFIG.api_path, url)
    else
        full_url = string.format("https://%s:%d%s%s", SERVER_CONFIG.host, SERVER_CONFIG.port, SERVER_CONFIG.api_path, url)
    end

    -- 网络未就绪时直接返回，避免底层 airlink 失败导致死机
    if not socket.adapter(socket.dft()) then
        log.warn("server_api", "网络未就绪，无法发送请求")
        return nil, "网络未就绪"
    end

    -- 请求数据
    local request_data = json.encode(params)

    --    导致 code=-8。这里最多重试2次，间隔1秒，显著提升成功率。
    local last_code, last_body
    for attempt = 1, 3 do
        -- 重试前重新确认网络就绪（断网时快速失败，避免白白等待）
        if not socket.adapter(socket.dft()) then
            log.warn("server_api", "网络未就绪，无法发送请求")
            return nil, "网络未就绪"
        end

        log.info("server_api", method .. " 请求: " .. full_url)
        log.debug("server_api", "请求数据: " .. request_data)

        -- 发送HTTP请求，调用wait()方法获取响应
        --    避免刷脸存件等流程卡在"正在处理"界面无法返回
        local code, headers, body = http.request(method, full_url, {
            ["Content-Type"] = "application/json"
        }, request_data, {timeout = 5000}).wait()

        log.debug("server_api", "HTTP响应原始返回值:")
        log.debug("server_api", "code: " .. tostring(code))
        log.debug("server_api", "headers 对象类型: " .. type(headers))
        log.debug("server_api", "body 对象类型: " .. type(body))

        if code >= 0 then
            -- 网络层成功（可能仍是 HTTP 错误状态码，需继续解析）
            log.info("server_api", "响应状态码: " .. tostring(code))
            if body then
                log.info("server_api", "响应内容: " .. tostring(body))
            else
                log.info("server_api", "响应内容为空")
            end
            if code ~= 200 then
                log.error("server_api", "HTTP状态码错误: " .. tostring(code))
                return nil, "HTTP状态码错误: " .. tostring(code)
            end
            local result = json.decode(body)
            if not result then
                log.error("server_api", "响应解析失败，响应内容: " .. tostring(body))
                return nil, "响应解析失败"
            end
            return result
        end

        -- 网络层失败（code<0），记录并重试
        last_code, last_body = code, body
        log.error("server_api", "HTTP请求失败(第" .. attempt .. "次): 错误码 " .. tostring(code))
        if attempt < 3 then
            sys.wait(1000)  -- 等待1秒后重试
        end
    end

    return nil, "HTTP请求失败: 错误码 " .. tostring(last_code)
end

-- 从服务端响应中提取错误信息（服务端业务错误码 != 0 时，err 为 nil，需从 result 提取）
local function get_api_err(result, err)
    if err then return err end
    if result then
        if type(result.value) == "string" and result.value ~= "" then
            return result.value
        end
        if result.code then
            return "服务器错误码: " .. tostring(result.code)
        end
    end
    return "未知错误"
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

-- 解析 JPEG 文件宽高（从 SOF0/SOF1/SOF2 标记读取）
-- 参数：file_content(string 文件内容)
-- 返回：w, h（无法解析时返回 nil）
local function get_jpeg_size(file_content)
    if not file_content or #file_content < 10 then return nil end
    local i = 3 -- 跳过 FF D8
    while i + 8 <= #file_content do
        if file_content:byte(i) == 0xFF then
            local marker = file_content:byte(i + 1)
            -- SOF0(0xC0) SOF1(0xC1) SOF2(0xC2)
            if marker == 0xC0 or marker == 0xC1 or marker == 0xC2 then
                local h = file_content:byte(i + 5) * 256 + file_content:byte(i + 6)
                local w = file_content:byte(i + 7) * 256 + file_content:byte(i + 8)
                return w, h
            end
            local len = file_content:byte(i + 2) * 256 + file_content:byte(i + 3)
            if len < 2 then return nil end
            i = i + 2 + len
        else
            i = i + 1
        end
    end
    return nil
end

-- 生成微信小程序码
local function do_generate_wechat_qr_code()
    -- 网络未就绪时直接返回，避免底层 airlink 失败导致死机
    if not socket.adapter(socket.dft()) then
        log.warn("server_api", "网络未就绪，无法生成小程序码")
        return nil, "网络未就绪"
    end

    local params = {
        project = "smart_locker",
        scene = get_device_id(),
        page = "pages/index/index",
        -- 注意：微信 getwxacodeunlimit 接口 width 合法范围是 280~1280，
        --       传小于 280 的值会被服务器 clamp 到 280（280 不是 16 的倍数，airui 无法解码）。
        --       288 = 18*16，既是 16 的倍数又满足微信最小 280 的限制。
        width = 288
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
    -- 注意：文件名带版本号，避免旧代码下载的 280x280 文件被"文件存在"逻辑复用
    local qr_file_path = "/qr_code_v288.jpeg"
    
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
    -- 注意：headers 键名可能大小写不一致，这里做兼容匹配
    if type(headers) == "table" then
        local content_type = headers["Content-Type"] or headers["content-type"] or headers["CONTENT-TYPE"]
        -- 若上面都没匹配到，遍历查找（兼容其他大小写形式）
        if not content_type then
            for k, v in pairs(headers) do
                if type(k) == "string" and string.lower(k) == "content-type" then
                    content_type = v
                    break
                end
            end
        end
        if content_type and string.find(string.lower(content_type), "image") then
            log.info("server_api", "小程序码生成成功，图片大小: " .. tostring(body_length) .. "字节")
            -- 检查文件是否成功创建
            if io.exists(qr_file_path) then
                log.debug("server_api", "图片文件成功保存到: " .. qr_file_path)
                -- 验证文件是否是有效的图片格式（JPEG 或 PNG）
                local file_content = io.readFile(qr_file_path)
                if file_content and #file_content > 2 then
                    local is_jpeg = file_content:sub(1, 2) == "\255\216"
                    local is_png = file_content:sub(1, 4) == "\137PNG"
                    if is_jpeg or is_png then
                        -- 校验 JPEG 宽高必须是 16 的倍数（airui 解码硬性要求，否则硬件解码跳过、软件解码失败）
                        if is_jpeg then
                            local w, h = get_jpeg_size(file_content)
                            if w and h and (w % 16 ~= 0 or h % 16 ~= 0) then
                                log.error("server_api", "小程序码图片尺寸非16倍数: " .. w .. "x" .. h .. "，删除文件避免显示坏图")
                                os.remove(qr_file_path)
                                return nil, "图片尺寸非16倍数: " .. w .. "x" .. h
                            end
                            -- 校验 JPEG 文件完整性：必须以 FFD9 结束（防止下载截断的坏文件被复用导致解码失败）
                            if file_content:sub(-2) ~= "\255\217" then
                                log.error("server_api", "小程序码图片文件不完整（缺少JPEG结束标记），删除文件")
                                os.remove(qr_file_path)
                                return nil, "图片文件不完整（下载被截断）"
                            end
                        elseif is_png then
                            -- 校验 PNG 文件完整性：必须以 IEND 数据块结束
                            if file_content:sub(-8) ~= "\0\0\0\0IEND\174\66\96\130" then
                                log.error("server_api", "小程序码图片文件不完整（缺少PNG结束标记），删除文件")
                                os.remove(qr_file_path)
                                return nil, "图片文件不完整（下载被截断）"
                            end
                        end
                        log.debug("server_api", "成功读取图片文件内容，大小: " .. string.len(file_content) .. "字节，是有效的图片格式")
                        return file_content, nil -- 返回图片二进制数据
                    end
                end
                log.error("server_api", "下载的图片文件格式无效，不是有效的JPEG/PNG图片")
                if file_content then
                    log.debug("server_api", "文件前4字节: " .. file_content:sub(1, 4):toHex())
                end
                return nil, "下载的图片格式无效"
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

-- 生成微信小程序码（带防重入保护：main 预下载与存件窗口下载并发时只执行一次）
function server_api.generate_wechat_qr_code()
    if _G.qr_downloading then
        log.warn("server_api", "小程序码正在下载中，跳过重复请求")
        return nil, "正在下载中"
    end
    _G.qr_downloading = true
    local ok, data, err = pcall(do_generate_wechat_qr_code)
    _G.qr_downloading = false
    if ok then
        return data, err
    end
    log.error("server_api", "生成小程序码异常: " .. tostring(data))
    return nil, "生成小程序码异常"
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
    
    local err_msg = get_api_err(result, err)
    log.error("server_api", "获取取件码失败: " .. err_msg)
    return false, err_msg
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
    
    local err_msg = get_api_err(result, err)
    log.error("server_api", "取件码验证失败: " .. err_msg)
    return false, err_msg
end

-- 存件登记（服务器生成取件码）
--   设备端【不应】主动分配格子。此处保留给当前"设备本地选柜"过渡流程使用：
--   设备本地选好柜后调用本接口，服务器登记并返回取件码。
--   参数格式：{deviceid, box}
function server_api.deposit_item(box_num, user_info)
    local params = {
        deviceid = get_device_id(),
        box = box_num
    }

    local result, err = http_request("/store", params)

    if result and result.code == 0 then
        log.info("server_api", "存件登记成功")
        return true, result.value
    end

    local err_msg = get_api_err(result, err)
    log.error("server_api", "存件登记失败: " .. err_msg)
    return false, err_msg
end

-- 刷脸存件登记（服务器生成取件码 + 存件码）
-- 请求：POST /face_store  {deviceid, box, face_id, face_name}
-- 成功：{code:0, value:{box, pickup_code, save_code, record_id}}
-- 失败：{code:55 "该柜子已占用" / 56 "设备不存在" / 57 "柜号不合法" / 58 "服务器内部错误"}
-- 返回：成功 true, result.value, false
--       业务错误（服务器明确拒绝） false, err_msg, false
--       网络错误（断网/超时/解析失败） false, err_msg, true
function server_api.face_store(box_num, face_id, face_name)
    local params = {
        deviceid = get_device_id(),
        box = box_num,
        face_id = tostring(face_id or ""),
        face_name = tostring(face_name or ""),
    }

    local result, err = http_request("/face_store", params)

    if result and result.code == 0 then
        log.info("server_api", "刷脸存件登记成功", "box", box_num,
                 "pickup_code", result.value and result.value.pickup_code,
                 "save_code", result.value and result.value.save_code)
        return true, result.value, false
    end

    local err_msg = get_api_err(result, err)
    if result then
        -- 服务器明确返回业务错误（如 code 55 该柜子已占用），需终止流程提示用户
        log.error("server_api", "刷脸存件登记被服务器拒绝: " .. err_msg)
        return false, err_msg, false
    end
    -- 网络层错误（断网/超时/响应解析失败），可降级本地处理
    log.error("server_api", "刷脸存件登记网络错误: " .. err_msg)
    return false, err_msg, true
end

-- 取件完成上报（设备本地取件后调用，服务器释放格子）
-- 参数格式：{deviceid, box, pickup_code}
function server_api.pickup_item(box_num, code)
    local params = {
        deviceid = get_device_id(),
        box = box_num,
        pickup_code = code
    }

    local result, err = http_request("/carry", params)

    if result and result.code == 0 then
        log.info("server_api", "取件完成上报成功")
        return true, result.value
    end

    local err_msg = get_api_err(result, err)
    log.error("server_api", "取件完成上报失败: " .. err_msg)
    return false, err_msg
end

-- 刷脸取件完成上报（设备刷脸取件后调用，服务器释放格子）
-- 请求：POST /carry  {deviceid, box, face_id}
function server_api.face_pickup_item(box_num, face_id)
    local params = {
        deviceid = get_device_id(),
        box = box_num,
        face_id = tostring(face_id or "")
    }

    local result, err = http_request("/carry", params)

    if result and result.code == 0 then
        log.info("server_api", "刷脸取件完成上报成功")
        return true, result.value
    end

    local err_msg = get_api_err(result, err)
    log.warn("server_api", "刷脸取件完成上报失败: " .. err_msg)
    return false, err_msg
end

-- 获取柜子状态（箱子状态 API，设备/小程序共用）
-- 服务器为唯一事实源：
--   - 设备轮询此接口获取：①当前各格子占用情况 ②待执行的存件命令(store_commands)
--   - 小程序进入页面时也调此接口，展示可用的格子
-- 请求：POST /status  {deviceid}
-- 响应：{code:0, value:{boxes:[{box,type,status}], store_commands:[{box,pickup_code}]}}
--   status: 0=空闲 1=占用
function server_api.get_locker_status()
    local result, err = http_request("/status", {deviceid = get_device_id()}, "POST")

    if result and result.code == 0 then
        log.info("server_api", "获取柜子状态成功")
        return true, result.value, 0
    end

    local err_msg = get_api_err(result, err)
    log.error("server_api", "获取柜子状态失败: " .. err_msg)
    -- 第三个返回值：服务器业务错误码（如 12=设备未初始化），网络错误时为 nil
    -- 供业务层判断是否需要自动重新初始化自愈
    return false, err_msg, result and result.code
end

-- 定时同步箱子数据（设备上报实际占用格子，服务器对账）
-- 用于网络异常时累积的取件/状态信息同步
-- 请求：POST /sync  {deviceid, boxes:[格子编号数组]}
-- status_data 兼容两种入参：
--   {box=1, status=0} 的数组，或纯格子编号数组 [1,2,3]
function server_api.sync_status(status_data)
    local boxes = {}
    if type(status_data) == "table" then
        for _, v in ipairs(status_data) do
            if type(v) == "table" then
                table.insert(boxes, v.box or v.box_num)
            else
                table.insert(boxes, v)
            end
        end
    end

    local params = {
        deviceid = get_device_id(),
        boxes = boxes
    }

    local result, err = http_request("/sync", params)

    if result and result.code == 0 then
        log.info("server_api", "箱子数据同步成功")
        return true, result.value
    end

    local err_msg = get_api_err(result, err)
    log.error("server_api", "箱子数据同步失败: " .. err_msg)
    return false, err_msg
end

-- 存件命令确认（设备执行开柜后向服务器确认"命令已执行"）
-- 请求：POST /store_ack  {deviceid, data:[{box, pickup_code}, ...]}
function server_api.store_ack(executed_boxes)
    local params = {
        deviceid = get_device_id(),
        data = executed_boxes or {}
    }

    local result, err = http_request("/store_ack", params)

    if result and result.code == 0 then
        log.info("server_api", "存件命令确认成功")
        return true, result.value
    end

    local err_msg = get_api_err(result, err)
    log.error("server_api", "存件命令确认失败: " .. err_msg)
    return false, err_msg
end

-- 模块初始化
local function init()
    log.info("server_api", "服务器接口模块初始化")
end

-- 自动初始化
init()

-- 对外接口
return server_api
