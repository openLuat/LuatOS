--[[
@module dhcam
@summary 大华摄像头功能模块，为exremotecam主模块提供大华摄像头的具体实现
@version 1.0
@date    2025.12.29
@author  拓毅恒
@usage
   注意：
        1. dhcam.lua是大华摄像头的功能模块，需配合exremotecam主模块使用
        2. 使用前请确保网络连接正常，能够访问到目标摄像头

    使用时，需要按照以下顺序加载模块：
        require "dhcam" -- 首先加载具体型号的摄像头功能模块（如大华）
        require "exremotecam" -- 然后加载exremotecam主模块
]]

local dhcam = {}

-- 全局变量定义
local camera_id, camera_buff

-- 大华参数
local DH_TextAlign = 0 -- 文本对齐方式，0左对齐，3右对齐 默认左对齐
local DH_channel = 0 -- 通道号

-- 大华OSD默认配置参数
local dh_osd_param = {
    host = "192.168.1.108",
    url = "/cgi-bin/configManager.cgi?",
    get_widgest = "action=getConfig&name=VideoWidget",
    set_widgest = "action=setConfig&VideoWidget[0].FontColorType=Adapt&VideoWidget[0].CustomTitle[1].PreviewBlend=true&VideoWidget[0].CustomTitle[1].EncodeBlend=true&VideoWidget[0].CustomTitle[1].TextAlign="..DH_TextAlign.."&VideoWidget[0].CustomTitle[1].Text=",
    text = "NULL",
    position = "&VideoWidget[0].CustomTitle[1].Rect[0]=83&VideoWidget[0].CustomTitle[1].Rect[1]=169&VideoWidget[0].CustomTitle[1].Rect[2]=2666&VideoWidget[0].CustomTitle[1].Rect[3]=607"
}

-- 大华抓图默认配置参数
local DAHUA_MD5Param = {
    username = "admin",
    password = "Air123456",
    realm = "Login to 7720fd71f7dd8d36eaabc67104aa4f38",--值要获取
    nonce = "dcd98b7102dd2f0e8b11d0f600bfb0c093",  -- 示例nonce值
    method = "GET:",  -- HTTP方法
    qop = "auth",
    nc = "00000001",
    cnonce = "KeA8e2Cy",
    response = "NULL",
    url = "/cgi-bin/snapshot.cgi?",
    timerul = "/cgi-bin/global.cgi?"
}

--[[
按竖线(|)分割字符串，支持多种返回格式
@api split_string_by_pipe(input_str,return_type)
@string input_str 要分割的字符串，格式如"1111|2222|3333"
@string/number return_type 返回类型，可选值：
        "all" - 返回完整拆分数组（默认值）
        "count" - 返回元素数量
        整数 - 返回指定索引的元素（索引从1开始）
@return 根据return_type参数不同，返回不同结果：
    - "all": table - 包含所有分割元素的数组
    - "count": number - 分割后的元素数量
    - 整数索引: string - 指定索引的元素，索引越界时返回错误信息
    - 无效参数: string - 错误提示信息
]]
local function split_string_by_pipe(input_str, return_type)
    -- 处理默认参数
    return_type = return_type or "all"
    -- 存储拆分后的结果
    local split_result = {}

    -- 核心拆分逻辑：遍历字符串，按 | 分割
    for item in string.gmatch(input_str, "[^|]+") do
        table.insert(split_result, item)  -- 将匹配到的元素加入数组
    end

    -- 根据 return_type 处理返回结果
    if return_type == "all" then
        -- 返回完整拆分数组
        return split_result
    elseif return_type == "count" then
        -- 返回元素数量（#split_result 是 Lua 获取数组长度的方式）
        return #split_result
    elseif type(return_type) == "number" then
        -- 返回指定索引的元素（Lua 数组索引从 1 开始）
        if return_type >= 1 and return_type <= #split_result then
            return split_result[return_type]
        else
            -- 处理索引越界
            return string.format("索引 %d 越界，当前只有 %d 个元素（索引 1 到 %d）", 
                                return_type, #split_result, #split_result)
        end
    else
        -- 处理无效的 return_type 参数
        return "return_type 无效！可选值：'all'、'count' 或整数索引"
    end
end

--[[
解析并验证OSD显示元素，确保不超出最大显示行数
@api ElementJudg(Data, number)
@string Data 竖线分隔的OSD文本内容，格式如"1111|2222|3333"
@number number 最大允许显示的行数
@return table 分割后的所有OSD元素数组
]]
local function ElementJudg(Data,number)
    -- 使用split_string_by_pipe函数按竖线分割OSD数据
    local all_items = split_string_by_pipe(Data)
    
    -- 遍历并打印所有解析到的OSD元素及其索引
    for i, item in ipairs(all_items) do
        log.info("元素解析", "索引", i, "值", item)
    end
    -- 获取OSD元素的总数
    local NUM = split_string_by_pipe(Data,"count")
    
    -- 检查元素数量是否超过最大允许行数
    if NUM > number then
        -- 记录警告日志，提示超出显示范围
        log.info("超出显示的范围,只能显示"..number.."行")
    end
    
    -- 返回完整的OSD元素数组（无论是否超出限制）
    return all_items
end

--[[
URL编码函数，用于将字符串转换为符合URL标准的编码格式
@api urlencode(str)
@string str 需要进行URL编码的字符串
@return string 编码后的URL安全字符串，如果输入为nil则返回空字符串
]]
local function urlencode(str)
    -- 检查输入参数是否存在
    if (str) then
        -- 将换行符转换为CRLF格式，符合HTTP标准
        str = string.gsub(str, "\n", "\r\n")
        -- 对非字母数字和空格的字符进行%XX编码
        str = string.gsub(str, "([^%w ])", function(c) return string.format("%%%02X", string.byte(c)) end)
        -- 将空格转换为+号，符合URL编码规范
        str = string.gsub(str, " ", "+")
    end
    -- 返回编码后的字符串或空字符串（如果输入为nil）
    return str or ""
end

--[[
计算Digest认证中的HA1值，用于网络摄像头的身份验证
@api CameraHA1(username,realm,password)
@string username 用户名
@string realm 认证域，由服务器在401响应中提供
@string password 用户密码
@return string 计算得到的HA1值（小写的MD5哈希值）
]]
local function CameraHA1(username,realm,password)
    -- 计算HA1值：MD5(用户名:认证域:密码)，并转换为小写
    -- Digest认证标准要求使用小写的哈希值
    local ha1 = string.lower(crypto.md5(username..":"..realm..":"..password))
    -- 返回计算得到的HA1值
    return ha1
end

--[[
处理Digest认证，仅在收到401响应时调用
@api handle_digest_auth(Host,url,params,headers,HA2)
@string Host 摄像头的IP地址
@string url 请求的URL路径
@string params 请求参数
@table headers 第一次HTTP请求返回的头部信息
@string HA2 预先计算好的HA2值
@return boolean, table 认证是否成功, 更新后的请求头部
]]
local function handle_digest_auth(Host, url, params, headers, HA2)
    -- 将headers转换为JSON格式以便解析
    local str = json.encode(headers)
    local Authenticate = json.decode(str)
    -- 获取WWW-Authenticate头信息
    local www = Authenticate["WWW-Authenticate"]
    
    if not www then
        log.info("DigestAuth", "没有找到WWW-Authenticate头信息")
        return false, nil
    end
    
    log.info("DigestAuth", "获取的鉴权信息:", www)
    
    -- 从鉴权信息中提取所需参数
    DAHUA_MD5Param.realm = string.match(www,"realm=\"(.-)\"")  -- 提取认证域
    DAHUA_MD5Param.nonce = string.match(www,"nonce=\"(.-)\"")  -- 提取随机数
    
    if not DAHUA_MD5Param.realm or not DAHUA_MD5Param.nonce then
        log.info("DigestAuth", "无法提取realm或nonce参数")
        return false, nil
    end
    
    -- 计算HA1值（用户名、认证域、密码的MD5哈希）
    local HA1 = CameraHA1(DAHUA_MD5Param.username, DAHUA_MD5Param.realm, DAHUA_MD5Param.password)
    
    -- 计算完整的response值（Digest认证的核心）
    -- response = MD5(HA1:nonce:nc:cnonce:qop:HA2)
    DAHUA_MD5Param.response = string.lower(crypto.md5(HA1..":"..DAHUA_MD5Param.nonce..":"..DAHUA_MD5Param.nc..":"..DAHUA_MD5Param.cnonce..":"..DAHUA_MD5Param.qop..":"..HA2))
    
    -- 构建完整的Authorization头部
    local authorization_header = "Digest username=\"" .. DAHUA_MD5Param.username .. "\", realm=\"" .. DAHUA_MD5Param.realm .. "\", nonce=\"" .. DAHUA_MD5Param.nonce .. "\", uri=\"" .. url..params.. "\", qop=" .. DAHUA_MD5Param.qop .. ", nc=" .. DAHUA_MD5Param.nc .. ", cnonce=\"" .. DAHUA_MD5Param.cnonce .. "\", response=\"" .. DAHUA_MD5Param.response.."\""
    
    -- 更新请求头部，添加认证信息
    local updated_headers = {['Host']=''..Host, ["Authorization"] = ''..authorization_header, ['Connection']='keep-alive'}
    log.info("DigestAuth", "鉴权信息重组完成")
    
    return true, updated_headers
end

--[[
设置大华(Dhua)摄像头的OSD(屏幕显示)模块
@api dhcam.set_osd(dahua_param)
@table dahua_param 大华摄像头OSD配置参数
@string dahua_param.host 摄像头的IP地址
@string dahua_param.data 要显示的OSD文本内容
@number dahua_param.text_align OSD文本对齐方式，默认为全局的DH_TextAlign
@number dahua_param.channel 摄像头通道号，默认为全局的DH_channel
@number dahua_param.x OSD显示的X坐标，默认为0
@number dahua_param.y OSD显示的Y坐标，默认为0
@return boolean 返回值
 false：OSD设置失败
 true：OSD设置成功
]]
function dhcam.set_osd(dahua_param)
    -- 参数类型检查
    if type(dahua_param) ~= "table" then
        log.error("dhcam.set_osd", "参数必须是table类型")
        return false
    end
    
    -- 设置默认参数值
    local host = dahua_param.host or dh_osd_param.host
    local data = dahua_param.data or ""
    local text_align = dahua_param.text_align or DH_TextAlign  -- 对齐方式 如果没填用默认值左对齐
    local channel = dahua_param.channel or DH_channel           -- 通道号 如果没填用默认值0
    local x = dahua_param.x or 0  -- x坐标 如果没填用默认值为0
    local y = dahua_param.y or 0  -- y坐标 如果没填用默认值为0
    
    -- 构建OSD位置参数字符串
    dh_osd_param.position = "&VideoWidget["..channel.."].CustomTitle[1].Rect[0]="..x.."&VideoWidget["..channel.."].CustomTitle[1].Rect[1]="..y.."&VideoWidget["..channel.."].CustomTitle[1].Rect[2]=0".."&VideoWidget["..channel.."].CustomTitle[1].Rect[3]=0"
    -- 构建OSD设置参数字符串
    dh_osd_param.set_widgest = "action=setConfig&VideoWidget["..channel.."].FontColorType=Adapt&VideoWidget["..channel.."].CustomTitle[1].PreviewBlend=true&VideoWidget["..channel.."].CustomTitle[1].EncodeBlend=true&VideoWidget["..channel.."].CustomTitle[1].TextAlign="..text_align.."&VideoWidget["..channel.."].CustomTitle[1].Text="
    
    -- 对OSD文本内容进行URL编码，确保特殊字符正确传输
    local osd_data = urlencode(data)
    -- 拼接完整的OSD设置参数
    local osd_text = dh_osd_param.set_widgest .. osd_data
    ---log.info("打印放置位置", dh_osd_param.position)
    
    -- 计算HA2值，用于Digest认证
    -- HA2 = MD5(方法:URL路径:请求参数)
    local HA2 = string.lower(crypto.md5(DAHUA_MD5Param.method..dh_osd_param.url..osd_text..dh_osd_param.position))
    -- 构建HTTP请求头部
    local camera_header = {["Accept-Encoding"]="identity",["Host"]=""..host}
    
    -- 发送第一次HTTP请求，获取鉴权信息
    local full_params = osd_text..dh_osd_param.position
    local full_url = "http://"..host..dh_osd_param.url..full_params
    local code, headers, body = http.request("GET", full_url, camera_header).wait()
    log.info("dh_osd", "第一次请求http，code：", code, headers)  -- 打印返回的状态码和头部信息
    
    -- 处理HTTP请求返回结果
    if code == 401 then -- 401表示需要身份认证
        -- 使用Digest认证函数处理认证
        local success, updated_headers = handle_digest_auth(host, dh_osd_param.url, full_params, headers, HA2)
        if success then
            -- 发送第二次HTTP请求，这次带有完整的认证信息
            local code, headers, body = http.request("GET", full_url, updated_headers).wait()
            log.info("dh_osd", "第二次请求http，code：", code)
            if code == 200 then
                log.info("dh_osd", "OSD设置成功")
                return true
            else
                log.info("dh_osd", "OSD设置失败，HTTP状态码：", code)
                return false
            end
        else
            log.info("dh_osd", "Digest认证失败")
            return false
        end
    elseif code == -4 then
        -- 处理重组错误（参数错误）
        log.info("dh_osd", "重组错误，请检查参数是否正确")
        return false  -- 退出函数，节省资源
    else
        -- 处理其他HTTP错误
        log.info("dh_osd", "HTTP请求错误，code：", code)
        return false  -- 退出函数，节省资源
    end
end

--[[
大华摄像头拍照功能，获取指定通道的快照图片
@api dhcam.take_picture(dahua_param)
@table dahua_param 大华摄像头拍照配置参数
@string dahua_param.host 摄像头/NVR的IP地址
@number dahua_param.channel 摄像头通道号
@return number 返回值
 0：拍照失败
 1：拍照成功，并且照片保存到/sd/1.jpeg
 2：拍照成功，但是照片没有保存本地
]]
function dhcam.take_picture(dahua_param)
    -- 参数类型检查
    if type(dahua_param) ~= "table" then
        log.error("dhcam.take_picture", "参数必须是table类型")
        return 0
    end
    
    -- 设置默认参数值
    local host = dahua_param.host or "192.168.1.108"
    local channel = dahua_param.channel or 0
    
    -- 构建拍照请求参数
    local photo_params = "channel=" .. channel
    
    -- 计算HA2值，用于Digest认证
    local HA2 = string.lower(crypto.md5(DAHUA_MD5Param.method..DAHUA_MD5Param.url..photo_params))
    
    -- 构建HTTP请求头部
    local camera_header = {["Accept-Encoding"]="identity",["Host"]=""..host}
    
    -- 发送第一次HTTP请求，获取鉴权信息
    local full_url = "http://"..host..DAHUA_MD5Param.url..photo_params
    local code, headers, body = http.request("GET", full_url, camera_header).wait()
    log.info("dh_picture", "第一次请求http，code：", code)
    
    -- 处理HTTP请求返回结果
    if code == 401 then -- 401表示需要身份认证
        -- 使用Digest认证函数处理认证
        local success, updated_headers = handle_digest_auth(host, DAHUA_MD5Param.url, photo_params, headers, HA2)
        if success then
            -- 发送第二次HTTP请求，这次带有完整的认证信息
            local code, headers, body = http.request("GET", full_url, updated_headers).wait()
            log.info("dh_picture", "第二次请求http，code：", code)
            if code == 200 then
                -- 检查SD卡是否可用
                local sd_test_file = io.open("/sd/test.txt", "w")
                if sd_test_file then
                    sd_test_file:close()
                    os.remove("/sd/test.txt")
                    log.info("dh_picture", "SD卡可用，开始保存照片")
                    
                    -- 保存照片到SD卡
                    local photo_file = io.open("/sd/1.jpeg", "wb")
                    if photo_file then
                        photo_file:write(body)
                        photo_file:close()
                        log.info("dh_picture", "照片保存到/sd/1.jpeg成功")
                        return 1
                    else
                        log.info("dh_picture", "照片保存失败")
                        return 2
                    end
                else
                    log.info("dh_picture", "SD卡不可用，照片未保存本地")
                    return 2
                end
            else
                log.info("dh_picture", "拍照失败，HTTP状态码：", code)
                return 0
            end
        else
            log.info("dh_picture", "Digest认证失败")
            return 0
        end
    elseif code == 200 then
        -- 无需认证，直接处理照片
        local sd_test_file = io.open("/sd/test.txt", "w")
        if sd_test_file then
            sd_test_file:close()
            os.remove("/sd/test.txt")
            log.info("dh_picture", "SD卡可用，开始保存照片")
            
            -- 保存照片到SD卡
            local photo_file = io.open("/sd/1.jpeg", "wb")
            if photo_file then
                photo_file:write(body)
                photo_file:close()
                log.info("dh_picture", "照片保存到/sd/1.jpeg成功")
                return 1
            else
                log.info("dh_picture", "照片保存失败")
                return 2
            end
        else
            log.info("dh_picture", "SD卡不可用，照片未保存本地")
            return 2
        end
    else
        log.info("dh_picture", "拍照失败，HTTP状态码：", code)
        return 0
    end
end

-- 注册大华摄像头模块
_G.dhcam = dhcam
return dhcam