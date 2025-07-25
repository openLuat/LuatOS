
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "httpdemo"
VERSION = "1.0.0"

--[[
本demo需要http库, 大部分能联网的设备都具有这个库
http也是内置库, 无需require

如需上传大文件,请使用 httpplus 库, 对应demo/httpplus
]]


-- 网络任务
sys.taskInit(function()
    local result,data
    -----------------------------
    -- 统一联网函数, 可自行删减
    ----------------------------
    -- 设置wifi网络名称(ssid)和密码(password)
    local ssid = "ChinaNet-7jU2"
    local password = "xnceqvkr"

    if wlan and wlan.connect then
        -- wifi 联网, ssid表示wifi网络名称，password为网络密码
        --输出wifi的用户名称、密码及硬件库名称
        log.info("wifi", ssid, password, rtos.bsp() )
        -- LED = gpio.setup(12, 0, gpio.PULLUP)
        -- 网络初始化
        wlan.init()
        -- 运行模式为 工作站/客户端
        wlan.setMode(wlan.STATION)
    end

    ----- time 为修复网络时间过长而修订为 while主体，增加网络状态判断        
    while true do
    ----- /time 为修复网络时间过长而修订为 while主体，增加网络状态判断        
        if wlan and wlan.connect then
            -- 连接网络
            wlan.connect(ssid, password, 1)
            -- 在网络连接成功时，会发布一个系统消息 IP_READY，而
            -- sys.waitUntil 订阅此消息，能在设置的时间内收到此消息
            -- 即表示网络连接成功。
            result, data = sys.waitUntil("IP_READY", 30000)
            log.info("wlan", "IP_READY", result, data)
            -- 取得网络Mac
            device_id = wlan.getMac()
        else
            while 1 do
                sys.wait(1000)
                log.info("http", "当前固件未包含http库")
            end
        end
        if result == true then
            log.info("已联网")
            sys.publish("net_ready")
        end
    ----- time 为修复网络时间过长而修订为 while主体，增加网络状态判断        
        while wlan and wlan.ready() do
            sys.wait(1000)
        end
    ----- /time 为修复网络时间过长而修订为 while主体，增加网络状态判断        
    end
end)

-- GET 请求
function demo_http_get()
    -- 最普通的Http GET请求
    local code, headers, body = http.request("GET", "https://www.air32.cn/").wait()
    log.info("http.get", code, headers, body)

    sys.wait(100)

    local code, headers, body = http.request("GET", "https://www.luatos.com/").wait()
    log.info("http.get", code, headers, body)

    -- 按需打印
    -- code 响应值, 若大于等于 100 为服务器响应, 小于的均为错误代码
    -- headers是个table, 一般作为调试数据存在
    -- body是字符串. 注意lua的字符串是带长度的byte[]/char*, 是可以包含不可见字符的
    -- log.info("http", code, json.encode(headers or {}), #body > 512 and #body or body)
end

-- 数据类型 application/json 演示
function demo_http_post_json()
    -- POST request 演示

    local req_headers = {}

    req_headers={
        ["Authorization"] = "Basic NkZhbXFsRmZTVmQ4OHNHejpLemt0SW8yUTNXcFhmbXRJTEtqME1mc3dsbHF0cTV0aldQM1BPUFU2d1M2M0E5VVlYOHJ1SFZCSVRaejlBak5w",
        ["Content-Type"] = "application/json",
        ["Connection"] = "keep-alive"
    }
    
    local body = json.encode( 
        {
            --query_date 是日期，如果操作时返回日期错误，则可以调整参数再试。
            --iccids 可以登录该网站，查询卡片信息得到，具体的数据，本数据亦可使用该网站上该用户下的其它卡片号码。
            ["query_date"] = "20241212",            
            ["iccids"] = "89860403102080512138"
        }
    )

    local code, headers, body = http.request("POST","http://api.taoyuan-tech.com/api/open/iotcard/usagelog", 
            req_headers,
            body -- POST请求所需要的body, string, zbuff, file均可
    ).wait()
    log.info("http.post", code, headers, body)
end

-- 数据类型 x-www-form-urlencoded 演示
function demo_http_post_form()
    -- POST request 演示
    local req_headers = {}
    req_headers["Content-Type"] = "application/x-www-form-urlencoded"
    local params = {
        ABC = "123",
        DEF = "345"
    }
    local body = ""
    for k, v in pairs(params) do
        body = body .. tostring(k) .. "=" .. tostring(v):urlEncode() .. "&"
    end
    local code, headers, body = http.request("POST","http://httpbin.air32.cn/post", 
            req_headers,
            body -- POST请求所需要的body, string, zbuff, file均可
    ).wait()
    log.info("http.post.form", code, headers, body)
end

-- GET方法的文件下载
function demo_http_download()

    --http.request("GET","http://zuoye.free.fr/files/flag.png",nil,nil,nil,nil,cbFnc)
    --关于http文件下载的演示，由于服务器比较难找，因而使用了http://zuoye.free.fr网站，如果下面的文件
    --演示失败，请试着打开上面的链接，查看文件是否存在，或者更换文件测试。如果该网站不存在了，那还请大
    --家谅解一二。或者大家也可以使用自己知道的网站资源来对http的下载功能进行测试。

    --有关post方法的文件下载，原demo倒是有，但测试一直不成功，可能是网站原因
    
    local code, headers, body = http.request("GET","http://zuoye.free.fr/files/flag.png",
            {}, -- 请求所添加的 headers, 可以是nil
            "", 
            nil
    ).wait()
    log.info("http.get", code, headers, string.toHex(body)) -- 只返回code和headers
end

-- POST方法的文件下载
function demo_http_download_post()

    -- POST and download, task内的同步操作
    local opts = {}                 -- 额外的配置项
    opts["dst"] = "/data.bin"       -- 下载路径,可选
    opts["timeout"] = 30000         -- 超时时长,单位ms,可选
    -- opts["adapter"] = socket.ETH0  -- 使用哪个网卡,可选
    -- opts["callback"] = http_download_callback
    -- opts["userdata"] = http_userdata

    for k, v in pairs(opts) do
        print("opts",k,v)
    end
    
    local code, headers, body = http.request("POST","http://site0.cn/api/httptest/simple/date",
            {}, -- 请求所添加的 headers, 可以是nil
            "", 
            opts
    ).wait()
    log.info("http.post", "code ="..code.." headers = ",headers, " body= "..body) -- 只返回code和headers

    --大家也可以依具体发问对文件进行操作处理
    local f = io.open("/data.bin", "rb")
    if f then
        local data = f:read("*a")
        log.info("fs", "data", data, data:toHex())
    end
    
    -- GET request, 开个task让它自行执行去吧, 不管执行结果了
    sys.taskInit(http.request("GET","http://site0.cn/api/httptest/simple/time").wait)
end

-- 普通方式的文件上传
---- MultipartForm上传文件
-- url string 请求URL地址
-- req_headers table 请求头
-- params table 需要传输的数据参数
function postMultipartFormData(url, params)
    local boundary = "----WebKitFormBoundary"..os.time()
    local req_headers = {
        ["Content-Type"] = "multipart/form-data; boundary="..boundary,
    }
    local body = {}

    --log.info("postMultipart_params=",url.."----"..params.."------")
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
                json = "application/json"       -- JSON
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
    local code, headers, body = http.request("POST",url,
            req_headers,
            body
    ).wait()   
    log.info("http.post", code, headers, body)
end

-- 虚拟内存的文件上传
function demo_http_post_file()
        -- -- POST multipart/form-data模式 上传文件---手动拼接
        local boundary = "----WebKitFormBoundary"..os.time()
        local req_headers = {
            ["Content-Type"] = "multipart/form-data; boundary="..boundary,
        }
        local body = "--"..boundary.."\r\n"..
                     "Content-Disposition: form-data; name=\"uploadFile\"; filename=\"luatos_uploadFile_TEST01.txt\""..
                     "\r\nContent-Type: text/plain\r\n\r\n"..
                     "1111http_测试一二三四654zacc\r\n"..
                     "--"..boundary

        log.info("headers: ", "\r\n"..json.encode(req_headers))
        log.info("body: ", "\r\n"..body)
        local code, headers, body = http.request("POST","http://airtest.openluat.com:2900/uploadFileToStatic",
                req_headers,
                body -- POST请求所需要的body, string, zbuff, file均可
        ).wait()
        log.info("http.post", code, headers, body)
end

-- 解压缩的演示
local function demo_http_get_gzip()
    -- 这里用 和风天气 的API做演示
    -- 这个API的响应, 总会gzip压缩过, 需要配合miniz库进行解压
    local code, headers, body = http.request("GET", "https://devapi.qweather.com/v7/weather/now?location=101010100&key=0e8c72015e2b4a1dbff1688ad54053de").wait()
    log.info("http.gzip", code)
    if code == 200 then
        local re = miniz.uncompress(body:sub(11), 0)
        log.info("和风天气", re)
        if re then
            local jdata = json.decode(re)
            log.info("jdata", jdata)
            if jdata then
                log.info("和风天气", jdata.code)
                if jdata.now then
                    log.info("和风天气", "天气", jdata.now.text)
                    log.info("和风天气", "温度", jdata.now.temp)
                end
            end
        end
    end
end

sys.taskInit(function()
    sys.wait(100)
    -- 打印一下支持的加密套件, 通常来说, 固件已包含常见的99%的加密套件
    -- if crypto.cipher_suites then
    --     log.info("cipher", "suites", json.encode(crypto.cipher_suites()))
    -- end

    -------------------------------------
    -------- HTTP 演示代码 --------------
    -------------------------------------
    sys.waitUntil("net_ready") -- 等联网

    while 1 do
        -- 大家可以在下面的演示函数中，选择需要进行操作的功能，去掉注释符，
        -- 保存后下载到开发板进行测试演示

        -- 演示GET请求
        -- demo_http_get()
        -- 表单提交
        -- demo_http_post_form()
        -- POST一个json字符串
        --  demo_http_post_json()
        -- 上传文件, mulitform形式
        -- demo_http_post_file()
        --[[

         postMultipartFormData(
            "http://airtest.openluat.com:2900/uploadFileToStatic",
            {
                -- texts = 
                -- {
                --     ["imei"] = "862991234567890",
                --     ["time"] = "20180802180345"
                -- },
                
                files =
                {
                    ["uploadFile"] = "/luadb/luatos_uploadFile.txt",
                }
            }
        )

        ]]
        -- POST方法文件下载
        -- demo_http_download_post()
        -- GET方法文件下载
        --demo_http_download()
        -- gzip压缩的响应, 以和风天气为例
        demo_http_get_gzip()

        sys.wait(1000)
        -- 打印一下内存状态
        log.info("sys", rtos.meminfo("sys"))
        log.info("lua", rtos.meminfo("lua"))
        --sys.wait(600000)
        sys.wait(10000)
    ----- time 为修复网络时间过长而修订为 while主体，增加网络状态判断        
    while wlan and wlan.ready() == false do
            log.info("http demo","wifi_disconnected")
            sys.waitUntil("net_ready",10000) -- 等联网  
        end
    end
    ----- /time 为修复网络时间过长而修订为 while主体，增加网络状态判断        
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
