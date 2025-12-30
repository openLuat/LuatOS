--[[
@module exremotecam
@summary exremotecam 远程摄像头OSD控制扩展库，提供摄像头OSD文字显示设置和拍照功能。
@version 1.0
@date    2025.12.29
@author  拓毅恒
@usage
注：在使用exremotecam 扩展库时，需要确保网络连接正常，能够访问到目标摄像头。

本文件的对外接口有2个：
1、exremotecam.OSDsetup(Brand, Host, channel, text, X, Y)：设置摄像头OSD文字显示
-- 参数说明：
--   Brand: 摄像头品牌，当前仅支持"Dhua"(大华)
--   Host: 摄像头/NVR的IP地址
--   channel: 摄像头通道号
--   text: OSD文本内容，需用竖线分隔，格式如"1111|2222|3333|4444"
--   X: 显示位置的X坐标
--   Y: 显示位置的Y坐标

2、exremotecam.getphoto(Brand, Host, channel)：控制摄像头拍照
-- 参数说明：
--   Brand: 摄像头品牌，当前仅支持"Dhua"(大华)
--   Host: 摄像头/NVR的IP地址
--   channel: 摄像头通道号
-- 返回：若SD卡可用，则图片保存为/sd/1.jpeg
]]

--------------------------------各品牌摄像头HTTP参数配置--------------------------------
-- 大华参数
local DH_TextAlign = 0 -- 文本对齐方式，0左对齐，3右对齐 默认左对齐
local DH_channel = 0 -- 通道号
-- 大华OSD默认配置参数
local dh_osd_param = {
    Host = "192.168.1.108",
    url = "/cgi-bin/configManager.cgi?",
    GetWidgest = "action=getConfig&name=VideoWidget",
    SetWidgest = "action=setConfig&VideoWidget[0].FontColorType=Adapt&VideoWidget[0].CustomTitle[1].PreviewBlend=true&VideoWidget[0].CustomTitle[1].EncodeBlend=true&VideoWidget[0].CustomTitle[1].TextAlign="..DH_TextAlign.."&VideoWidget[0].CustomTitle[1].Text=",
    Text = "NULL",
    Postion = "&VideoWidget[0].CustomTitle[1].Rect[0]=83&VideoWidget[0].CustomTitle[1].Rect[1]=169&VideoWidget[0].CustomTitle[1].Rect[2]=2666&VideoWidget[0].CustomTitle[1].Rect[3]=607"
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
--------------------------------各品牌摄像头HTTP参数配置完毕--------------------------------

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
@usage:
    -- 示例1: 完整数组返回
    -- 输入: "OSD行1|OSD行2|OSD行3"
    -- 代码: local result = split_string_by_pipe("OSD行1|OSD行2|OSD行3")
    -- 输出: {"OSD行1", "OSD行2", "OSD行3"}
    
    -- 示例2: 返回元素数量
    -- 输入: "OSD行1|OSD行2|OSD行3"
    -- 代码: local count = split_string_by_pipe("OSD行1|OSD行2|OSD行3", "count")
    -- 输出: 3
    
    -- 示例3: 返回指定索引元素
    -- 输入: "OSD行1|OSD行2|OSD行3"
    -- 代码: local second_item = split_string_by_pipe("OSD行1|OSD行2|OSD行3", 2)
    -- 输出: "OSD行2"
    
    -- 示例4: 在OSDsetup中的实际应用
    -- 代码: OSDsetup("Dhua", "192.168.1.108", 0, "温度|湿度|天气|风向", 0, 2000)
    -- 内部处理: split_string_by_pipe("温度|湿度|天气|风向") 得到 {"温度", "湿度", "天气", "风向"}
    -- 最终效果: 在大华摄像头OSD上显示这四行文字
]]
local function split_string_by_pipe(input_str, return_type)
    -- 处理默认参数（如果未指定 return_type，默认返回完整数组）
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
@usage
local osd_elements = ElementJudg("行1|行2|行3|行4", 3)
-- 输出: "超出显示的范围,只能显示3行"
-- 返回: {"行1", "行2", "行3", "行4"}

注意事项:
1. 函数会打印所有解析到的元素及其索引
2. 当元素数量超过最大行数时，会记录警告日志
3. 无论是否超出限制，都会返回完整的元素数组
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
@usage: 
    local encoded = urlencode("Hello World!")
    -- 输出: "Hello+World%21"
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
@usage: 
    local ha1 = CameraHA1("admin", "realm", "123456")
    -- 输出: md5("admin:realm:123456")的小写哈希值
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
@usage: 
    local code, headers, body = http.request("GET", "http://192.168.1.100/cgi-bin/test", initial_headers).wait()
    if code == 401 then
        local success, updated_headers = handle_digest_auth("192.168.1.100", "/cgi-bin/test", "param=value", headers, "ha2_value")
        if success then
            -- 使用更新后的头部发送第二次请求
        end
    end
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
设置大华(Dahua)摄像头的OSD(屏幕显示)模块
@api DH_set_osd_module(Host,Data,TextAlign,channel,x,y)
@string Host 摄像头的IP地址
@string Data 要显示的OSD文本内容
@number TextAlign OSD文本对齐方式，默认为全局的DH_TextAlign
@number channel 摄像头通道号，默认为全局的DH_channel
@number x OSD显示的X坐标，默认为0
@number y OSD显示的Y坐标，默认为0
@return nil 无返回值，函数通过日志输出执行结果
@usage: 
    DH_set_osd_module("192.168.1.100", "温度: 25℃", 0, 1, 100, 200)
    -- 功能: 在IP为192.168.1.100的摄像头通道1上，坐标(100,200)处显示"温度: 25℃"
]]
local function DH_set_osd_module(Host,Data,TextAlign,channel,x,y)
    -- 设置默认参数值
    DH_TextAlign = TextAlign or DH_TextAlign  -- 对齐方式 如果没填用默认值左对齐
    channel = channel or DH_channel           -- 通道号 如果没填用默认值0
    x = x or 0  -- x坐标 如果没填用默认值为0
    y = y or 0  -- y坐标 如果没填用默认值为0
    
    -- 构建OSD位置参数字符串
    dh_osd_param.Postion = "&VideoWidget["..channel.."].CustomTitle[1].Rect[0]="..x.."&VideoWidget["..channel.."].CustomTitle[1].Rect[1]="..y.."&VideoWidget["..channel.."].CustomTitle[1].Rect[2]=0".."&VideoWidget["..channel.."].CustomTitle[1].Rect[3]=0"
    -- 构建OSD设置参数字符串
    dh_osd_param.SetWidgest = "action=setConfig&VideoWidget["..channel.."].FontColorType=Adapt&VideoWidget["..channel.."].CustomTitle[1].PreviewBlend=true&VideoWidget["..channel.."].CustomTitle[1].EncodeBlend=true&VideoWidget["..channel.."].CustomTitle[1].TextAlign="..DH_TextAlign.."&VideoWidget["..channel.."].CustomTitle[1].Text="
    
    -- 对OSD文本内容进行URL编码，确保特殊字符正确传输
    local OsdData = urlencode(Data)
    -- 拼接完整的OSD设置参数
    local OSDTEXT = dh_osd_param.SetWidgest ..OsdData
    ---log.info("打印放置位置",dh_osd_param.Postion)
    
    -- 计算HA2值，用于Digest认证
    -- HA2 = MD5(方法:URL路径:请求参数)
    local HA2 = string.lower(crypto.md5(DAHUA_MD5Param.method..dh_osd_param.url..OSDTEXT..dh_osd_param.Postion))
    -- 构建HTTP请求头部
    local Camera_header = {["Accept-Encoding"]="identity",["Host"]=""..Host}
    
    -- 发送第一次HTTP请求，获取鉴权信息
    local full_params = OSDTEXT..dh_osd_param.Postion
    local full_url = "http://"..Host..dh_osd_param.url..full_params
    local code, headers, body = http.request("GET", full_url, Camera_header).wait()
    log.info("DHosd", "第一次请求http，code：", code, headers)  -- 打印返回的状态码和头部信息
    
    -- 处理HTTP请求返回结果
    if code == 401 then -- 401表示需要身份认证
        -- 使用Digest认证函数处理认证
        local success, updated_headers = handle_digest_auth(Host, dh_osd_param.url, full_params, headers, HA2)
        if success then
            -- 发送第二次HTTP请求，这次带有完整的认证信息
            local code, headers, body = http.request("GET", full_url, updated_headers).wait()
            log.info("DHosd", "第二次请求http，code：", code)
        else
            log.info("DHosd", "Digest认证失败")
            return
        end
    elseif code == -4 then
        -- 处理重组错误（参数错误）
        log.info("DHosd", "重组错误，请检查参数是否正确")
        return  -- 退出函数，节省资源
    else
        -- 处理其他HTTP错误
        log.info("DHosd", "HTTP请求错误，code：", code)
        return  -- 退出函数，节省资源
    end
end

--[[
设置摄像头OSD(屏幕显示)文字功能
@api OSDsetup(Brand,Host,channel,text,X,Y)
@string Brand 摄像头品牌，当前仅支持: "Dhua" - 大华
@string Host 摄像头/NVR的IP地址
@number channel 摄像头通道号（主要用于NVR）
@string text OSD文本内容，需用竖线分隔，格式如"1111|2222|3333|4444"，大华最多显示13行
@number X 显示位置的X坐标
@number Y 显示位置的Y坐标
@return 无 无返回值
@usage
-- 大华摄像头OSD测试
OSDsetup("Dhua", "192.168.0.163", 0, "行1|行2|行3", 0, 2000)

-- 多通道NVR示例
OSDsetup("Dhua", "192.168.0.200", 1, "温度: 25℃|湿度: 60%", 100, 50)
]]
local function OSDsetup(Brand,Host,channel,text,X,Y)
    -- 判断摄像头品牌
    if Brand == "Dhua" then
        log.info("osdsetup","检测到大华摄像头，开始初始化")
        -- 解析并验证OSD文本内容，大华摄像头最多支持13行
        ElementJudg(text,13)
        -- 调用大华摄像头OSD设置函数
        -- 参数：IP地址、OSD文本数组、对齐方式、通道号、X坐标、Y坐标
        DH_set_osd_module(Host,text,0,channel,X,Y)
        
        -- 以下品牌型号暂不支持，代码已注释
        -- elseif Brand == "Hikvision" then
        --     log.info("osdsetup","检测到海康摄像头，开始初始化")
        --     local all_items = ElementJudg(Text,4)
        --     HKOSDBdoyGetFun(Host,channel,all_items[1],all_items[2],all_items[3],all_items[4],X,Y)
        -- elseif Brand == "Uniview" then
        --     log.info("osdsetup","检测到宇视摄像头，开始初始化")
        --     local all_items = ElementJudg(Text,6)
        --     EZ_OSDSETFun(Host,channel,all_items[1],all_items[2],all_items[3],all_items[4],all_items[5],all_items[6],X,Y)
        -- elseif Brand == "TianDiWeiye" then
        --     log.info("osdsetup","检测到天地伟业摄像头，开始初始化")
        --     local all_items = ElementJudg(Text,6)
        --     -- TDOSDModify(Host,t)
    else
        -- 处理不支持的品牌
        log.info("osdsetup","型号填写错误或暂不支持！！！")
    end
end

--[[
大华摄像头拍照功能，获取指定通道的快照图片
@api DHPicture(Host,channel)
@string Host 摄像头/NVR的IP地址
@number channel 摄像头通道号
@return 无 无返回值，若SD卡可用则图片保存为/sd/1.jpeg
@usage
-- 获取大华摄像头通道0的快照图片
DHPicture("192.168.1.108", 0)

-- 获取大华NVR通道1的快照图片
DHPicture("192.168.0.200", 1)
]]
local function DHPicture(Host,channel)
    log.info("DHPicture","开始执行")
    
    -- 构建拍照请求参数：通道号和图片类型(0表示快照)
    local resultStr = "channel="..channel.."&type=0"
    
    -- 计算HA2值：对HTTP方法、URL路径和请求参数进行MD5加密
    local HA2 = string.lower(crypto.md5(DAHUA_MD5Param.method..DAHUA_MD5Param.url..resultStr))
    
    -- 准备基础HTTP请求头部
    local Camera_header = {["Accept-Encoding"]="identity",["Host"]=""..Host}
    
    -- 发送第一次HTTP请求，主要目的是获取Digest认证信息
    local full_url = "http://"..Host..DAHUA_MD5Param.url..resultStr
    local code, headers, body = http.request("GET", full_url, Camera_header).wait()
    log.info("DHPicture","第一次请求http，code：",code,headers)
    
    -- 获取到鉴权信息
    if  code ==401 then
        -- 使用统一的Digest认证函数处理认证
        local success, updated_headers = handle_digest_auth(Host, DAHUA_MD5Param.url, resultStr, headers, HA2)
        if success then
            Camera_header = updated_headers
            log.info("DHPicture","鉴权信息重组完成")
        else
            log.info("DHPicture", "Digest认证失败")
            return
        end
    end
    
    -- 检查SD卡状态
    local can_save_to_sd = false
    local data, err = fatfs.getfree("/sd")
    if data then
        can_save_to_sd = true
        log.info("DHPicture", "SD卡可用空间信息:", json.encode(data))
    else
        log.info("DHPicture", "无法获取SD卡空间信息:", err)
    end
    
    -- 根据SD卡状态发送请求
    local code, headers, body
    if can_save_to_sd then
        -- 发送第二次请求（带有完整的认证信息），获取图片并保存到/sd/1.jpeg
        code, headers, body = http.request("GET", full_url, Camera_header, nil, {dst = "/sd/1.jpeg"}).wait()
    else
        -- 发送第二次请求（带有完整的认证信息），不保存图片
        code, headers, body = http.request("GET", full_url, Camera_header).wait()
        log.info("DHPicture", "没有检测到SD卡，无法保存图片到SD卡中，请确认SD卡状态后重试")
    end
    
    log.info("DHPicture","第二次请求http，code：", code, body)
    if code == 200 then
        log.info("DHPicture","拍照完成")
    end
end

--[[
多品牌摄像头拍照通用接口，根据品牌调用对应厂商的拍照功能
@api getphoto(Brand,Host,channel)
@string Brand 摄像头品牌，当前仅支持: "Dhua" - 大华
@string Host 摄像头/NVR的IP地址
@number channel 摄像头通道号
@return 无 无返回值，若SD卡可用则图片保存为/sd/1.jpeg
@usage
-- 获取大华摄像头通道0的快照图片
getphoto("Dhua", "192.168.1.108", 1)

-- 获取大华NVR通道1的快照图片
getphoto("Dhua", "192.168.0.200", 1)
]]
local function getphoto(Brand,Host,channel)
    -- 判断摄像头品牌
    if Brand == "Dhua" then
        log.info("getphoto","检测到大华摄像头，开始初始化")
        DHPicture(Host,channel)
    else
        -- 处理不支持的品牌
        log.info("getphoto","型号填写错误或暂不支持！！！")
        return
    end
end

return {
    OSDsetup = OSDsetup,
    getphoto = getphoto
}