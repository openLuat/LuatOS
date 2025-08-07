--[[
@module  http_app
@summary http应用功能模块 
@version 1.0
@date    2025.08.01
@author  朱天华
@usage
本文件为http应用功能模块，核心业务逻辑为：基于不同的应用场景，演示http核心库的使用方式；
http核心库和httpplus扩展库的区别如下：
|   区别项                          |   http核心库                                                               |  httpplus扩展库               |
| --------------------------------- | ------------------------------------------------------------------------- | ---------------------------- |
|    文件上传                        |    文件最大64KB                                                           |    只要内存够用，文件大小不限   |
|    文件下载                        |    支持，只要文件系统空间够用，文件大小不限                                  |    不支持                     |
|    http header的key: value的限制   |    所有header的value总长度不能超过4KB，单个header的value长度不能超过1KB      |    只要内存够用，header长度不限 |
|    鉴权URL自动识别                 |    不支持                                                                 |    支持                        |
|    接收到的body数据存储支持zbuff      |    不支持                                                               |    支持，可以直接传输给uart等库 |
|    接收到的body数据存储到内存中     |    最大支持32KB                                                            |    只要内存够用，大小不限       |
|    chunk编码                       |    支持                                                                   |    不支持                       |


本文件没有对外接口，直接在main.lua中require "http_app"就可以加载运行；
]]


--[[
此处先详细解释下http.request接口的使用方法

接口定义：
    http.request(method, url, headers, body, opts, server_ca_cert, client_cert, client_key, client_password)

使用方法：
    local code, headers, body = http.request(method, url, headers, body, opts, server_ca_cert, client_cert, client_key, client_password).wait()
    只能在task中使用
    发送http请求到服务器，等待服务器的http应答，此处会阻塞当前task，等待整个过程成功结束或者出现错误异常结束或者超时结束

参数定义：
    method，stirng类型，必须包含此参数，表示HTTP请求方法，支持"GET"、"POST"、"HEAD"等所有HTTP请求方法
    url，string类型，必须包含此参数，表示HTTP请求URL地址，支持HTTP、HTTPS，支持域名、IP地址，支持自定义端口，标准的HTTP URL格式都支持
    headers，table或者nil类型，可选包含此参数，表示HTTP请求头，例如 {["Content-Type"] = "application/x-www-form-urlencoded", ["self_defined_key"] = "self_defined_value"} 
    body，string或者zbuff或者nil类型，可选包含此参数，表示HTTP请求体，如果请求体是一个文件中的内容，要把文件内容读出来，赋值给body使用
    opts，table或者nil类型，可选包含此参数，表示HTTP请求的一些额外配置，包含以下内容
    {
        timeout    -- -- number或者nil类型，单位毫秒，可选包含此参数，表示从发送请求到读取到服务器响应整个过程的超时时间，如果传入0，表示永久等待；如果没有传入此参数或者传入nil，则使用默认值10分钟
        dst        -- 下载路径，string类型，当HTTP请求的数据需要保存到文件中时，此处填写完整的文件路径
        adapter    -- 使用的网卡ID，number类型，例如4G网卡，SPI外挂以太网卡，WIFI网卡等；如果没有传入此参数，内核固件会自动选择当前时间点其他功能模块设置的默认网卡
                    -- 除非你HTTP请求时，一定要使用某一种网卡，才设置此参数；如果没什么特别要求，不要使用此参数，使用系统中设置的默认网卡即可
                    -- 这个参数和本demo中的netdrv_device.lua关系比较大，netdrv_device会设置默认网卡，此处http不要设置adapter参数，直接使用netdrv_device设置的默认网卡就行
        debug      -- 调试开关，bool类型，true表示打开debug调试信息日志，false表示关闭debug调试信息日志，默认为关闭状态
        ipv6       -- 是否为ipv6，bool类型，true表示使用ipv6，false表示不使用ipv6，默认为false
        userdata   -- 下载回调函数使用的用户自定义回调参数，做为callback回调函数的第三个参数使用
        callback   -- 下载回调函数，function类型，当下载数据时，无论是保存到内存中，还是保存到文件系统中，如果设置了callback，内核固件中每收到一包body数据，都会自动执行一次callback回调函数
                    -- 回调函数的调用形式为callback(content_len, body_len, userdata)
                    --     content_len：number类型，数据总长度
                    --     body_len：number类型，已经下载的数据长度
                    --     userdata：下载回调函数使用的用户自定义回调参数
    }
    server_ca_cert，string类型，服务器ca证书数据，可选包含此参数，当客户端需要验证服务器证书时，需要此参数，如果证书数据在一个文件中，要把文件内容读出来，赋值给server_ca_cert
    client_cert，string类型，客户端证书数据，可选包含此参数，当服务器需要验证客户端证书时，需要此参数，如果证书数据在一个文件中，要把文件内容读出来，赋值给client_cert
    client_key, string类型，客户端加密后的私钥数据，可选包含此参数，当服务器需要验证客户端证书时，需要此参数，如果加密后的私钥数据在一个文件中，要把文件内容读出来，赋值给client_key
    client_password，string类型，客户端私钥口令数据，可选包含此参数，当服务器需要验证客户端证书时，需要此参数，如果私钥口令数据在一个文件中，要把文件内容读出来，赋值给client_password

返回值定义：

    http.request().wait()有三个返回值code，headers，body
    code表示执行结果，number类型，有以下两种含义：
        1、code大于等于100时，表示服务器返回的HTTP状态码，例如200表示成功，详细说明可以通过搜索引擎搜索“HTTP状态码”自行了解
        2、code小于0时，表示内核固件中检测到通信异常，有如下几种:
            -1 HTTP_ERROR_STATE 错误的状态, 一般是底层异常,请报issue
            -2 HTTP_ERROR_HEADER 错误的响应头部, 通常是服务器问题
            -3 HTTP_ERROR_BODY 错误的响应体,通常是服务器问题
            -4 HTTP_ERROR_CONNECT 连接服务器失败, 未联网,地址错误,域名错误
            -5 HTTP_ERROR_CLOSE 提前断开了连接, 网络或服务器问题
            -6 HTTP_ERROR_RX 接收数据报错, 网络问题
            -7 HTTP_ERROR_DOWNLOAD 下载文件过程报错, 网络问题或下载路径问题
            -8 HTTP_ERROR_TIMEOUT 超时, 包括连接超时,读取数据超时
            -9 HTTP_ERROR_FOTA fota功能报错,通常是更新包不合法  
    headers有以下两种含义：
        1、当code的返回值大于等于100时，headers表示服务器返回的应答头，table类型
        2、当code的返回值小于0时，headers为nil        
    body有以下三种含义
        1、当code的返回值大于等于100时，如果请求的body数据不需要保存到文件中，而是直接保存到内存中，则body表示请求到的数据内容，string类型
        2、当code的返回值大于等于100时，如果请求的body数据需要保存到文件中，则body表示保存请求数据后的文件的大小，number类型
        3、当code的返回值小于0时，body为nil
]]


-- http下载数据回调函数
-- content_len：number类型，数据总长度
-- body_len：number类型，已经下载的数据长度
-- userdata：下载回调函数使用的用户自定义回调参数
-- 每收到一包body数据，就会调用一次http_cbfunc回调函数
local function http_cbfunc(content_len, body_len, userdata)
    log.info("http_cbfunc", content_len, body_len, userdata)
end


-- 普通的http get请求功能演示
-- 请求的body数据保存到内存变量中，在内存够用的情况下，最大支持32KB的数据存储到内存中
-- timeout可以设置超时时间
-- callback可以设置回调函数，可用于实时检测body数据的下载进度
local function http_app_get()
    -- https get请求https://www.air32.cn/网页内容
    -- 如果请求成功，请求的数据保存到body中
    local code, headers, body = http.request("GET", "https://www.air32.cn/").wait()
    log.info("http_app_get1", 
        code==200 and "success" or "error", 
        code, 
        json.encode(headers or {}), 
        body and (body:len()>512 and body:len() or body) or "nil")

    -- https get请求https://www.luatos.com/网页内容
    -- 请求超时时间为3秒，用户自己写代码时，不要照抄10秒，根据自己业务逻辑的需要设置合适的超时时间
    -- 回调函数为http_cbfunc，回调函数使用的第三个回调参数为"http_app_get2"
    -- 如果请求成功，请求的数据保存到body中
    code, headers, body = http.request("GET", "https://www.luatos.com/", nil, nil, {timeout=10000, userdata="http_app_get2", callback=http_cbfunc}).wait()
    log.info("http_app_get2", 
        code==200 and "success" or "error", 
        code, 
        json.encode(headers or {}), 
        body and (body:len()>512 and body:len() or body) or "nil")

    -- http get请求http://httpbin.air32.cn/get网页内容，超时时间为3秒
    -- 请求超时时间为3秒，用户自己写代码时，不要照抄3秒，根据自己业务逻辑的需要设置合适的超时时间
    -- 回调函数为http_cbfunc，回调函数使用的第三个回调参数为"http_app_get3"
    -- 如果请求成功，请求的数据保存到body中
    code, headers, body = http.request("GET", "http://httpbin.air32.cn/get", nil, nil, {timeout=3000, userdata="http_app_get3", callback=http_cbfunc}).wait()
    log.info("http_app_get3", 
        code==200 and "success" or "error", 
        code, 
        json.encode(headers or {}), 
        body and (body:len()>512 and body:len() or body) or "nil")
end


-- http get下载压缩数据的功能演示
local function http_app_get_gzip()
    -- https get请求https://devapi.qweather.com/v7/weather/now?location=101010100&key=0e8c72015e2b4a1dbff1688ad54053de网页内容，超时时间为3秒
    -- 如果请求成功，请求的数据保存到body中
    local code, headers, body = http.request("GET", "https://devapi.qweather.com/v7/weather/now?location=101010100&key=0e8c72015e2b4a1dbff1688ad54053de").wait()
    log.info("http_app_get_gzip", 
        code==200 and "success" or "error", 
        code, 
        json.encode(headers or {}), 
        body and (body:len()>512 and body:len() or body) or "nil")

    -- 如果请求成功
    if code == 200 then
        -- 从body的第11个字节开始解压缩
        local uncompress_data = miniz.uncompress(body:sub(11,-1), 0)
        if not uncompress_data then
            log.error("http_app_get_gzip uncompress error")
            return
        end

        local json_data = json.decode(uncompress_data)
        if not json_data then
            log.error("http_app_get_gzip json.decode error")
            return
        end

        log.info("http_app_get_gzip json_data", json_data)
        log.info("http_app_get_gzip", "和风天气", json_data.code)
        if json_data.now then
            log.info("http_app_get_gzip", "和风天气", "天气", json_data.now.text)
            log.info("http_app_get_gzip", "和风天气", "温度", json_data.now.temp)
        end
    end
end


-- http get下载数据保存到文件中的功能演示
-- 请求的body数据保存到文件中，在文件系统够用的情况下，文件大小不限
-- timeout可以设置超时时间
-- callback可以设置回调函数，可用于实时检测文件下载进度
local function http_app_get_file()

    -- 创建/http_download目录，用来存放通过http下载的文件
    -- 重复创建目录会返回失败
    -- 在创建目录之前可以使用api判断下目录是否存在
    -- 不过只有最新版本的内核固件才支持判断目录是否存在的api
    -- 在编写本demo时还没有这个api
    -- 如果Luatools烧录软件时，没有勾选 清除FS分区，此处日志有可能输出error
    -- 如果输出error，不用理会，不会影响后续逻辑的执行
    -- 等后续的新版本内核固件支持 判断目录是否存在 的api之后，再加上api判断
    local download_dir = "/http_download/"
    local result, reason = io.mkdir(download_dir)
    if not result then
        log.error("http_app_get_file io.mkdir error", reason)
    end

    
    local file_path = download_dir.."get_file1.html"
    -- https get请求https://www.air32.cn/网页内容
    -- 如果请求成功，请求的数据保存到文件file_path中
    local code, headers, body_size = http.request("GET", "https://www.air32.cn/", nil, nil, {dst=file_path}).wait()
    log.info("http_app_get_file1", 
        code==200 and "success" or "error", 
        code, 
        json.encode(headers or {}), 
        body_size)

    -- 如果下载成功
    if code==200 then
        -- 读取文件大小
        local size = io.fileSize(file_path)
        log.info("http_app_get_file1", "io.fileSize="..size)

        if size~=body_size then
            log.error("io.fileSize doesn't equal with body_size, error", size, body_size)
        end

        --文件使用完之后，如果以后不再用到，根据需要可以自行删除
        os.remove(file_path)
    end
 



    file_path = download_dir.."get_file2.html"
    -- https get请求https://www.luatos.com/网页内容
    -- 请求超时时间为3秒，用户自己写代码时，不要照抄10秒，根据自己业务逻辑的需要设置合适的超时时间
    -- 回调函数为http_cbfunc，回调函数使用的第三个回调参数为"http_app_get_file2"
    -- 如果请求成功，请求的数据保存到文件file_path中
    code, headers, body_size = http.request("GET", "https://www.luatos.com/", nil, nil, {dst=file_path, timeout=10000, userdata="http_app_get_file2", callback=http_cbfunc}).wait()
    log.info("http_app_get_file2", 
        code==200 and "success" or "error", 
        code, 
        json.encode(headers or {}), 
        body_size)

    -- 如果下载成功
    if code==200 then
        -- 读取文件大小
        local size = io.fileSize(file_path)
        log.info("http_app_get_file2", "io.fileSize="..size)

        if size~=body_size then
            log.error("io.fileSize doesn't equal with body_size, error", size, body_size)
        end

        --文件使用完之后，如果以后不再用到，根据需要可以自行删除
        os.remove(file_path)
    end




    file_path = download_dir.."get_file3.html"
    -- http get请求http://httpbin.air32.cn/get网页内容，超时时间为3秒
    -- 请求超时时间为3秒，用户自己写代码时，不要照抄3秒，根据自己业务逻辑的需要设置合适的超时时间
    -- 回调函数为http_cbfunc，回调函数使用的第三个回调参数为"http_app_get_file3"
    -- 如果请求成功，请求的数据保存到文件file_path中
    code, headers, body_size = http.request("GET", "http://httpbin.air32.cn/get", nil, nil, {dst=file_path, timeout=3000, userdata="http_app_get_file3", callback=http_cbfunc}).wait()
    log.info("http_app_get_file3", 
        code==200 and "success" or "error", 
        code, 
        json.encode(headers or {}), 
        body_size)

    -- 如果下载成功
    if code==200 then
        -- 读取文件大小
        local size = io.fileSize(file_path)
        log.info("http_app_get_file3", "io.fileSize="..size)

        if size~=body_size then
            log.error("io.fileSize doesn't equal with body_size, error", size, body_size)
        end

        --文件使用完之后，如果以后不再用到，根据需要可以自行删除
        os.remove(file_path)
    end
end


-- http post提交表单数据功能演示
local function http_app_post_form()
    local params = {
        username = "LuatOS",
        password = "123456"
    }
    local body = ""
    -- 拼接成url编码的键值对的形式
    for k, v in pairs(params) do
        body = body .. k .. "=" .. tostring(v):urlEncode() .. "&"
    end
    -- 删除最后一位的&字符，最终为string类型的username=LuatOS&password=123456
    body = body:sub(1,-2)

    -- http post提交表单数据
    -- http://httpbin.air32.cn/post为回环测试服务器，服务器收到post提交的表单数据后，还会下发同样的表单数据给设备
    -- ["Content-Type"] = "application/x-www-form-urlencoded" 表示post提交的body数据格式为url编码的键值对形式的表单数据
    -- 如果请求成功，服务器应答的数据会保存到resp_body中
    local code, headers, resp_body = http.request("POST", "http://httpbin.air32.cn/post", {["Content-Type"] = "application/x-www-form-urlencoded"}, body).wait()
    log.info("http_app_post_form", 
        code==200 and "success" or "error", 
        code, 
        json.encode(headers or {}), 
        resp_body and (resp_body:len()>512 and resp_body:len() or resp_body) or "nil")
end


-- http post提交json数据功能演示
local function http_app_post_json()
    local params = {
        username = "LuatOS",
        password = "123456"
    }
    local body = json.encode(params)

    -- http post提交json数据
    -- http://httpbin.air32.cn/post为回环测试服务器，服务器收到post提交的json数据后，还会下发同样的json数据给设备
    -- ["Content-Type"] = "application/json" 表示post提交的body数据格式为json格式的数据
    -- 如果请求成功，服务器应答的数据会保存到resp_body中
    local code, headers, resp_body = http.request("POST", "http://httpbin.air32.cn/post", {["Content-Type"] = "application/json"}, body).wait()
    log.info("http_app_post_json", 
        code==200 and "success" or "error", 
        code, 
        json.encode(headers or {}), 
        resp_body and (resp_body:len()>512 and resp_body:len() or resp_body) or "nil")
end


-- http post提交纯文本数据功能演示
local function http_app_post_text()
    -- http post提交纯文本数据
    -- http://httpbin.air32.cn/post为回环测试服务器，服务器收到post提交的纯文本数据后，还会下发同样的纯文本数据给设备
    -- ["Content-Type"] = "text/plain" 表示post提交的body数据格式为纯文本格式的数据
    -- 如果请求成功，服务器应答的数据会保存到resp_body中
    local code, headers, resp_body = http.request("POST", "http://httpbin.air32.cn/post", {["Content-Type"] = "text/plain"}, "This is a raw text message from LuatOS device").wait()
    log.info("http_app_post_text", 
        code==200 and "success" or "error", 
        code, 
        json.encode(headers or {}), 
        resp_body and (resp_body:len()>512 and resp_body:len() or resp_body) or "nil")
end


-- http post提交xml数据功能演示
local function http_app_post_xml()
    -- [=[ 和 ]=] 之间是一个多行字符串
    local body = [=[
        <?xml version="1.0" encoding="UTF-8"?>
        <user>
            <name>LuatOS</name>
            <password>123456</password>
        </user>
    ]=]

    -- http post提交xml数据
    -- http://httpbin.air32.cn/post为回环测试服务器，服务器收到post提交的xml数据后，还会下发同样的xml数据给设备
    -- ["Content-Type"] = "text/xml" 表示post提交的body数据格式为xml格式的数据
    -- 如果请求成功，服务器应答的数据会保存到resp_body中
    local code, headers, resp_body = http.request("POST", "http://httpbin.air32.cn/post", {["Content-Type"] = "text/xml"}, body).wait()
    log.info("http_app_post_xml", 
        code==200 and "success" or "error", 
        code, 
        json.encode(headers or {}), 
        resp_body and (resp_body:len()>512 and resp_body:len() or resp_body) or "nil")
end


-- http post提交原始二进制数据功能演示
local function http_app_post_binary()
    local body = io.readFile("/luadb/logo.jpg")

    -- http post提交原始二进制数据
    -- http://upload.air32.cn/api/upload/jpg为jpg图片上传测试服务器
    -- 此处将logo.jpg的原始二进制数据做为body上传到服务器
    -- 上传成功后，电脑上浏览器打开https://www.air32.cn/upload/data/jpg/，打开对应的测试日期目录，点击具体的测试时间照片，可以查看上传的照片
    -- ["Content-Type"] = "application/octet-stream" 表示post提交的body数据格式为原始二进制格式的数据
    -- 如果请求成功，服务器应答的数据会保存到resp_body中
    local code, headers, resp_body = http.request("POST", "http://upload.air32.cn/api/upload/jpg", {["Content-Type"] = "application/octet-stream"}, body).wait()
    log.info("http_app_post_binary", 
        code==200 and "success" or "error", 
        code, 
        json.encode(headers or {}), 
        resp_body and (resp_body:len()>512 and resp_body:len() or resp_body) or "nil")
end


local function post_multipart_form_data(url, params)
    local boundary = "----WebKitFormBoundary"..os.time()
    local req_headers = {
        ["Content-Type"] = "multipart/form-data; boundary="..boundary,
    }
    local body = {}

    -- 解析拼接 body
    for k,v in pairs(params) do
        if k=="texts" then
            local bodyText = ""
            for kk,vv in pairs(v) do
                print(kk,vv)
                bodyText = bodyText.."--"..boundary.."\r\nContent-Disposition: form-data; name=\""..kk.."\"\r\n\r\n"..vv.."\r\n"
            end
            table.insert(body, bodyText)
        elseif k=="files" then
            local contentType =
            {
                txt = "text/plain",             -- 文本
                jpg = "image/jpeg",             -- JPG 格式图片
                jpeg = "image/jpeg",            -- JPEG 格式图片
                png = "image/png",              -- PNG 格式图片   
                gif = "image/gif",              -- GIF 格式图片
                html = "image/html",            -- HTML
                json = "application/json",      -- JSON
            }
            
            for kk,vv in pairs(v) do
                if type(vv) == "table" then
                    for i=1, #vv do
                        print(kk,vv[i])
                        table.insert(body, "--"..boundary.."\r\nContent-Disposition: form-data; name=\""..kk.."\"; filename=\""..vv[i]:match("[^%/]+%w$").."\"\r\nContent-Type: "..contentType[vv[i]:match("%.(%w+)$")].."\r\n\r\n")
                        table.insert(body, io.readFile(vv[i]))
                        table.insert(body, "\r\n")
                    end
                else
                    print(kk,vv)
                    table.insert(body, "--"..boundary.."\r\nContent-Disposition: form-data; name=\""..kk.."\"; filename=\""..vv:match("[^%/]+%w$").."\"\r\nContent-Type: "..contentType[vv:match("%.(%w+)$")].."\r\n\r\n")
                    table.insert(body, io.readFile(vv))
                    table.insert(body, "\r\n")
                end
            end
        end
    end 
    table.insert(body, "--"..boundary.."--\r\n")
    body = table.concat(body)
    log.info("headers: ", "\r\n" .. json.encode(req_headers), type(body))
    log.info("body: " .. body:len() .. "\r\n" .. body)

    local code, headers, resp_body = http.request("POST", url, req_headers, body).wait()  
    log.info("post_multipart_form_data", 
        code==200 and "success" or "error", 
        code, 
        json.encode(headers or {}), 
        resp_body and (resp_body:len()>512 and resp_body:len() or resp_body) or "nil")
    
end


-- http post文件上传功能演示
local function http_app_post_file()
    -- 此接口post_multipart_form_data支持单文件上传、多文件上传、单文本上传、多文本上传、单/多文本+单/多文件上传
    -- http://airtest.openluat.com:2900/uploadFileToStatic 仅支持单文件上传，并且上传的文件name必须使用"uploadFile"
    -- 所以此处仅演示了单文件上传功能，并且"uploadFile"不能改成其他名字，否则会出现上传失败的应答
    -- 如果你自己的http服务支持更多类型的文本/文件混合上传，可以打开注释自行验证
    post_multipart_form_data(
        "http://airtest.openluat.com:2900/uploadFileToStatic",
        {
            -- texts = 
            -- {
            --     ["username"] = "LuatOS",
            --     ["password"] = "123456"
            -- },
            
            files =
            {
                ["uploadFile"] = "/luadb/logo.jpg",
                -- ["logo1.jpg"] = "/luadb/logo.jpg",
            }
        }
    )
end



-- http app task 的任务处理函数
local function http_app_task_func() 
    while true do
        -- 如果当前时间点设置的默认网卡还没有连接成功，一直在这里循环等待
        while not socket.adapter(socket.dft()) do
            log.warn("http_app_task_func", "wait IP_READY", socket.dft())
            -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
            -- 或者等待1秒超时退出阻塞等待状态;
            -- 注意：此处的1000毫秒超时不要修改的更长；
            -- 因为当使用libnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
            -- 当libnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
            -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
            sys.waitUntil("IP_READY", 1000)
        end

        -- 检测到了IP_READY消息
        log.info("http_app_task_func", "recv IP_READY", socket.dft())

        -- 普通的http get请求功能演示
        http_app_get()
        -- http get下载压缩数据的功能演示
        http_app_get_gzip()
        -- http get下载数据保存到文件中的功能演示
        http_app_get_file()
        -- http post提交表单数据功能演示
        http_app_post_form()
        -- http post提交json数据功能演示
        http_app_post_json()
        -- http post提交纯文本数据功能演示
        http_app_post_text()
        -- http post提交xml数据功能演示
        http_app_post_xml()
        -- http post提交原始二进制数据功能演示
        http_app_post_binary()
        -- http post文件上传功能演示
        http_app_post_file()

        -- 60秒之后，循环测试
        sys.wait(60000)
    end
end

--创建并且启动一个task
--运行这个task的处理函数http_app_task_func
sys.taskInit(http_app_task_func)
