
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "httpdemo"
VERSION = "1.0.0"

--[[
本demo需要http库, 大部分能联网的设备都具有这个库
http也是内置库, 无需require

1. 如需上传大文件,请使用 httpplus 库, 对应demo/httpplus
2. 
]]

-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用http库需要下列语句]]
_G.sysplus = require("sysplus")


-- Air780E的AT固件默认会为开机键防抖, 导致部分用户刷机很麻烦
if rtos.bsp() == "EC618" and pm and pm.PWK_MODE then
    pm.power(pm.PWK_MODE, false)
end


sys.taskInit(function()
    -----------------------------
    -- 统一联网函数, 可自行删减
    ----------------------------
    if wlan and wlan.connect then
        -- wifi 联网, ESP32系列均支持
        local ssid = "luatos1234"
        local password = "12341234"
        log.info("wifi", ssid, password)
        -- TODO 改成esptouch配网
        -- LED = gpio.setup(12, 0, gpio.PULLUP)
        wlan.init()
        wlan.setMode(wlan.STATION)
        wlan.connect(ssid, password, 1)
        local result, data = sys.waitUntil("IP_READY", 30000)
        log.info("wlan", "IP_READY", result, data)
        device_id = wlan.getMac()
    elseif mobile then
        -- Air780E/Air600E系列
        --mobile.simid(2)
        -- LED = gpio.setup(27, 0, gpio.PULLUP)
        device_id = mobile.imei()
        log.info("ipv6", mobile.ipv6(true))
        sys.waitUntil("IP_READY", 30000)
    elseif http then
        sys.waitUntil("IP_READY")
    else
        while 1 do
            sys.wait(1000)
            log.info("http", "当前固件未包含http库")
        end
    end
    log.info("已联网")
    sys.publish("net_ready")
end)

function demo_http_get()
    -- 最普通的Http GET请求
    local code, headers, body = http.request("GET", "https://www.air32.cn/").wait()
    log.info("http.get", code, headers, body)
    local code, headers, body = http.request("GET", "https://mirrors6.tuna.tsinghua.edu.cn/", nil, nil, {ipv6=true}).wait()
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

function demo_http_post_json()
    -- POST request 演示
    local req_headers = {}
    req_headers["Content-Type"] = "application/json"
    local body = json.encode({name="LuatOS"})
    local code, headers, body = http.request("POST","http://site0.cn/api/httptest/simple/date", 
            req_headers,
            body -- POST请求所需要的body, string, zbuff, file均可
    ).wait()
    log.info("http.post", code, headers, body)
end

function demo_http_post_form()
    -- POST request 演示
    local req_headers = {}
    req_headers["Content-Type"] = "application/x-www-form-urlencoded"
    local params = {
        ABC = "123",
        DEF = 345
    }
    local body = ""
    for k, v in pairs(params) do
        body = body .. tostring(k) .. "=" .. tostring(v):urlEncode() .. "&"
    end
    local code, headers, body = http.request("POST","http://echohttp.wendal.cn/post", 
            req_headers,
            body -- POST请求所需要的body, string, zbuff, file均可
    ).wait()
    log.info("http.post.form", code, headers, body)
end

-- local function http_download_callback(content_len,body_len,userdata)
--     print("http_download_callback",content_len,body_len,userdata)
-- end

-- local http_userdata = "123456789"

function demo_http_download()

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
    log.info("http.post", code, headers, body) -- 只返回code和headers

    -- local f = io.open("/data.bin", "rb")
    -- if f then
    --     local data = f:read("*a")
    --     log.info("fs", "data", data, data:toHex())
    -- end
    
    -- GET request, 开个task让它自行执行去吧, 不管执行结果了
    sys.taskInit(http.request("GET","http://site0.cn/api/httptest/simple/time").wait)
end

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

        -- 也可用postMultipartFormData(url, params) 上传文件
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
end


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
        -- 演示GET请求
        demo_http_get()
        -- 表单提交
        -- demo_http_post_form()
        -- POST一个json字符串
        -- demo_http_post_json()
        -- 上传文件, mulitform形式
        -- demo_http_post_file()
        -- 文件下载
        -- demo_http_download()
        -- gzip压缩的响应, 以和风天气为例
        -- demo_http_get_gzip()

        sys.wait(1000)
        -- 打印一下内存状态
        log.info("sys", rtos.meminfo("sys"))
        log.info("lua", rtos.meminfo("lua"))
        sys.wait(600000)
    end
end)

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


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
