--[[
@module  httpplus
@summary httpplus应用功能模块 
@version 1.0
@date    2025.08.06
@author  朱天华
@usage
本文件为httpplus应用功能模块，核心业务逻辑为：基于不同的应用场景，演示httpplus扩展库的使用方式；
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


本文件没有对外接口，直接在main.lua中require "httpplus_app"就可以加载运行；
]]


--[[
此处先详细解释下httpplus.request接口的使用方法

接口定义：
    httpplus.request(opts)

使用方法：
    local code, response = httpplus.request(opts)
    只能在task中使用
    发送http请求到服务器，等待服务器的http应答，此处会阻塞当前task，等待整个过程成功结束或者出现错误异常结束或者超时结束

参数定义：
    opts，table类型，表示HTTP请求参数，包含以下内容
    {
        url        -- string类型，必须包含此参数，表示HTTP请求URL地址，支持HTTP、HTTPS，支持域名、IP地址，支持自定义端口，标准的HTTP URL格式都支持
        method     -- stirng或者nil类型，可选包含此参数，表示HTTP请求方法，支持"GET"、"POST"、"HEAD"等所有HTTP请求方法，如果没有传入此参数或者传入了nil类型，则使用默认值，默认值分为以下两种情况：
                   -- 如果没有设置files，forms，body，bodyfile参数，则默认为"GET"
                   -- 如果至少设置了files，forms，body，bodyfile中的一种参数，则默认为"POST"
        headers    -- table或者nil类型，可选包含此参数，表示自定义的一个或者多个HTTP请求头，例如 {["self_defined_key1"] = "self_defined_value1", ["self_defined_key2"] = "self_defined_value2"}
        timeout    -- number或者nil类型，单位秒，可选包含此参数，表示从发送请求到读取到服务器响应整个过程的超时时间，如果传入0，表示永久等待；如果没有传入此参数或者传入nil，则使用默认值30秒
        files      -- table或者nil类型，可选包含此参数，表示POST上传的一个或者多个文件列表，键值对的形式，若存在本参数，会自动强制以multipart/form-data形式上传；例如
                   -- {
                   --     ["uploadFile"] = "/luadb/logo.jpg",
                   --     ["logo1.jpg"] = "/luadb/logo.jpg",
                   -- }

        forms      -- table或者nil类型，可选包含此参数，表示POST上传的一个或者多个表单参数列表，键值对的形式
                   -- 若存在本参数并且不存在files参数，会自动强制以application/x-www-form-urlencoded形式上传
                   -- 若存在本参数并且存在files参数，会自动强制以multipart/form-data形式上传，也就是说支持同时上传文件和表单参数
                   -- 例如：
                   -- {
                   --     ["username"] = "LuatOS",
                   --     ["password"] = "123456",
                   -- } 
        body       -- string，zbuff，table或者nil类型，可选包含此参数，表示自定义的body内容, 不能与files或者forms同时存在
        bodyfile   -- string或者nil类型，可选包含此参数，表示要上传的一个文件的路径，会自动读取文件中的内容进行上传
                   -- 不能与files或者forms同时存在
                   -- 可以与body同时存在，与body同时存在时, 优先级高于body参数，也就是说，bodyfile对应的文件路径中的内容在body参数对应的内容之前
        debug      -- bool或者nil类型，可选包含此参数，表示调试开关，true表示打开debug调试信息日志，false表示关闭debug调试信息日志，如果没有传入此参数或者传入了nil类型，则使用默认值false
        try_ipv6   -- bool或者nil类型，可选包含此参数，表示是否优先尝试ipv6地址，true表示优先尝试使用ipv6，false表示不尝试使用ipv6，如果没有传入此参数或者传入了nil类型，则使用默认值false
        adapter    -- number或者nil类型，可选包含此参数，表示使用的网卡ID，例如4G网卡，SPI外挂以太网卡，WIFI网卡等；如果没有传入此参数，内核固件会自动选择当前时间点其他功能模块设置的默认网卡
                   -- 除非你HTTP请求时，一定要使用某一种网卡，才设置此参数；如果没什么特别要求，不要使用此参数，使用系统中设置的默认网卡即可
                   -- 这个参数和本demo中的netdrv_device.lua关系比较大，netdrv_device会设置默认网卡，此处http不要设置adapter参数，直接使用netdrv_device设置的默认网卡就行
    }

返回值定义：
    httpplus.request(opts)有两个返回值code，response
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
    response有以下两种含义
        1、当code的返回值大于等于100时，response为table类型，包含以下两项内容
           {
               headers = {},    -- table类型，一个或者多个应答头，键值对的形式，可以使用json.encode(response.headers)在日志中打印
               body = ,         -- zbuff类型，应答体数据；通过zbuff的query函数，可以转化为string类型：response.body:query()；也可以通过uart.tx等支持zbuff的函数直接使用，例如uart.tx(1, response.body)
           }
        2、当code的返回值小于0时，response为nil
]]

local httpplus = require "httpplus"


-- 普通的http get请求功能演示
-- 请求的body数据保存到内存变量中，在内存够用的情况下，长度不限
-- timeout可以设置超时时间
local function httpplus_app_get()
    local body
    -- https get请求https://www.air32.cn/网页内容
    -- 如果请求成功，请求的数据保存到response.body中
    local code, response = httpplus.request({url="https://www.air32.cn/"})
    log.info("httpplus_app_get1", code==200 and "success" or "error", code)
    if code==200 then
        log.info("httpplus_app_get1 headers", json.encode(response.headers or {}))
        body = response.body:query()
        log.info("httpplus_app_get1 body", body and (body:len()>512 and body:len() or body) or "nil")
    end


    -- http get请求http://httpbin.air32.cn/get网页内容，超时时间为3秒
    -- 请求超时时间为3秒，用户自己写代码时，不要照抄3秒，根据自己业务逻辑的需要设置合适的超时时间
    -- 如果请求成功，请求的数据保存到body中
    code, response = httpplus.request({url="http://httpbin.air32.cn/get", timeout=3})
    log.info("httpplus_app_get2", code==200 and "success" or "error", code)
    if code==200 then
        log.info("httpplus_app_get2 headers", json.encode(response.headers or {}))
        body = response.body:query()
        log.info("httpplus_app_get2 body", body and (body:len()>512 and body:len() or body) or "nil")
    end
end


-- http get下载压缩数据的功能演示
local function httpplus_app_get_gzip()
    local body
    -- https get请求https://devapi.qweather.com/v7/weather/now?location=101010100&key=0e8c72015e2b4a1dbff1688ad54053de网页内容，超时时间为3秒
    -- 如果请求成功，请求的数据保存到response.body中
    local code, response = httpplus.request({url="https://devapi.qweather.com/v7/weather/now?location=101010100&key=0e8c72015e2b4a1dbff1688ad54053de"})
    log.info("httpplus_app_get_gzip", code==200 and "success" or "error", code)
    if code==200 then
        log.info("httpplus_app_get_gzip headers", json.encode(response.headers or {}))
        body = response.body:query()
        log.info("httpplus_app_get_gzip body", body and (body:len()>512 and body:len() or body) or "nil")
    end

    -- 如果请求成功
    if code == 200 then
        -- 从body的第11个字节开始解压缩
        local uncompress_data = miniz.uncompress(body:sub(11,-1), 0)
        if not uncompress_data then
            log.error("httpplus_app_get_gzip uncompress error")
            return
        end

        local json_data = json.decode(uncompress_data)
        if not json_data then
            log.error("httpplus_app_get_gzip json.decode error")
            return
        end

        log.info("httpplus_app_get_gzip json_data", json_data)
        log.info("httpplus_app_get_gzip", "和风天气", json_data.code)
        if json_data.now then
            log.info("httpplus_app_get_gzip", "和风天气", "天气", json_data.now.text)
            log.info("httpplus_app_get_gzip", "和风天气", "温度", json_data.now.temp)
        end
    end
end


-- http post提交表单数据功能演示
local function httpplus_app_post_form()
    -- http post提交表单数据
    -- http://httpbin.air32.cn/post为回环测试服务器，服务器收到post提交的表单数据后，还会下发同样的表单数据给设备
    -- 如果请求成功，服务器应答的数据会保存到response.body中
    local code, response = httpplus.request(
    {
        url = "http://httpbin.air32.cn/post",
        forms = {username="LuatOS", password="123456"}
    })
    log.info("httpplus_app_post_form", code==200 and "success" or "error", code)
    if code==200 then
        log.info("httpplus_app_post_form headers", json.encode(response.headers or {}))
        local body = response.body:query()
        log.info("httpplus_app_post_form body", body and (body:len()>512 and body:len() or body) or "nil")
    end
end


-- http post提交json数据功能演示
local function httpplus_app_post_json()
    local params = {
        username = "LuatOS",
        password = "123456"
    }

    -- http post提交json数据
    -- http://httpbin.air32.cn/post为回环测试服务器，服务器收到post提交的json数据后，还会下发同样的json数据给设备
    -- ["Content-Type"] = "application/json" 表示post提交的body数据格式为json格式的数据
    -- 如果请求成功，服务器应答的数据会保存到response.body中
    local code, response = httpplus.request(
    {
        method = "POST",
        url = "http://httpbin.air32.cn/post",
        headers = {["Content-Type"] = "application/json"},
        body = json.encode(params)
    })
    log.info("httpplus_app_post_json", code==200 and "success" or "error", code)
    if code==200 then
        log.info("httpplus_app_post_json headers", json.encode(response.headers or {}))
        local body = response.body:query()
        log.info("httpplus_app_post_json body", body and (body:len()>512 and body:len() or body) or "nil")
    end
end


-- http post提交纯文本数据功能演示
local function httpplus_app_post_text()
    -- http post提交纯文本数据
    -- http://httpbin.air32.cn/post为回环测试服务器，服务器收到post提交的纯文本数据后，还会下发同样的纯文本数据给设备
    -- ["Content-Type"] = "text/plain" 表示post提交的body数据格式为纯文本格式的数据
    -- 如果请求成功，服务器应答的数据会保存到response.body中
    local code, response = httpplus.request(
    {
        method = "POST",
        url = "http://httpbin.air32.cn/post",
        headers = {["Content-Type"] = "text/plain"},
        body = "This is a raw text message from LuatOS device"
    })
    log.info("httpplus_app_post_text", code==200 and "success" or "error", code)
    if code==200 then
        log.info("httpplus_app_post_text headers", json.encode(response.headers or {}))
        local body = response.body:query()
        log.info("httpplus_app_post_text body", body and (body:len()>512 and body:len() or body) or "nil")
    end
end


-- http post提交xml数据功能演示
local function httpplus_app_post_xml()
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
    -- 如果请求成功，服务器应答的数据会保存到response.body中
    local code, response = httpplus.request(
    {
        method = "POST",
        url = "http://httpbin.air32.cn/post",
        headers = {["Content-Type"] = "text/xml"},
        body = body
    })
    log.info("httpplus_app_post_xml", code==200 and "success" or "error", code)
    if code==200 then
        log.info("httpplus_app_post_xml headers", json.encode(response.headers or {}))
        body = response.body:query()
        log.info("httpplus_app_post_xml body", body and (body:len()>512 and body:len() or body) or "nil")
    end
end


-- http post提交原始二进制数据功能演示
local function httpplus_app_post_binary()
    local body = io.readFile("/luadb/logo.jpg")

    -- http post提交原始二进制数据
    -- http://upload.air32.cn/api/upload/jpg为jpg图片上传测试服务器
    -- 此处将logo.jpg的原始二进制数据做为body上传到服务器
    -- 上传成功后，电脑上浏览器打开https://www.air32.cn/upload/data/jpg/，打开对应的测试日期目录，点击具体的测试时间照片，可以查看上传的照片
    -- ["Content-Type"] = "application/octet-stream" 表示post提交的body数据格式为原始二进制格式的数据
    -- 如果请求成功，服务器应答的数据会保存到response.body中
    local code, response = httpplus.request(
    {
        method = "POST",
        url = "http://upload.air32.cn/api/upload/jpg",
        headers = {["Content-Type"] = "application/octet-stream"},
        body = body
    })
    log.info("httpplus_app_post_binary", code==200 and "success" or "error", code)
    if code==200 then
        log.info("httpplus_app_post_binary headers", json.encode(response.headers or {}))
        body = response.body:query()
        log.info("httpplus_app_post_binary body", body and (body:len()>512 and body:len() or body) or "nil")
    end
end


-- http post文件上传功能演示
local function httpplus_app_post_file()
    -- hhtplus.request接口支持单文件上传、多文件上传、单文本上传、多文本上传、单/多文本+单/多文件上传
    -- http://airtest.openluat.com:2900/uploadFileToStatic 仅支持单文件上传，并且上传的文件name必须使用"uploadFile"
    -- 所以此处仅演示了单文件上传功能，并且"uploadFile"不能改成其他名字，否则会出现上传失败的应答
    -- 如果你自己的http服务支持更多类型的文本/文件混合上传，可以打开注释自行验证
    local code, response = httpplus.request(
    {
        url = "http://airtest.openluat.com:2900/uploadFileToStatic",
        files =
        {
            ["uploadFile"] = "/luadb/logo.jpg",
            -- ["logo1.jpg"] = "/luadb/logo.jpg",
        },
        -- forms =
        -- {
        --     ["username"] = "LuatOS",
        --     ["password"] = "123456",
        -- },
    })
    log.info("httpplus_app_post_file", code==200 and "success" or "error", code)
    if code==200 then
        log.info("httpplus_app_post_file headers", json.encode(response.headers or {}))
        local body = response.body:query()
        log.info("httpplus_app_post_file body", body and (body:len()>512 and body:len() or body) or "nil")
    end
end



-- http app task 的任务处理函数
local function httpplus_app_task_func() 
    while true do
        -- 如果当前时间点设置的默认网卡还没有连接成功，一直在这里循环等待
        while not socket.adapter(socket.dft()) do
            log.warn("httpplus_app_task_func", "wait IP_READY", socket.dft())
            -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
            -- 或者等待1秒超时退出阻塞等待状态;
            -- 注意：此处的1000毫秒超时不要修改的更长；
            -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
            -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
            -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
            sys.waitUntil("IP_READY", 1000)
        end

        -- 检测到了IP_READY消息
        log.info("httpplus_app_task_func", "recv IP_READY", socket.dft())

        -- 普通的http get请求功能演示
        httpplus_app_get()
        -- http get下载压缩数据的功能演示
        httpplus_app_get_gzip()
        -- http post提交表单数据功能演示
        httpplus_app_post_form()
        -- -- http post提交json数据功能演示
        httpplus_app_post_json()
        -- http post提交纯文本数据功能演示
        httpplus_app_post_text()
        -- http post提交xml数据功能演示
        httpplus_app_post_xml()
        -- http post提交原始二进制数据功能演示
        httpplus_app_post_binary()
        -- http post文件上传功能演示
        httpplus_app_post_file()

        -- 60秒之后，循环测试
        sys.wait(60000)
    end
end

--创建并且启动一个task
--运行这个task的处理函数httpplus_app_task_func
sys.taskInit(httpplus_app_task_func)
