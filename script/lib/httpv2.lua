--- 模块功能：HTTP客户端, 本代码从LuaTask 2.3.0适配到LuatOS
-- @module httpv2
-- @author 稀饭放姜
-- @author wendal
-- @license MIT
-- @copyright OpenLuat.com
-- @release 2017.10.23

local httpv2 = {}

local Content_type = {'application/x-www-form-urlencoded', 'application/json', 'application/octet-stream'}

function update_resp(resp, data)
    if not resp.code then
        -- 第一波数据,看看是不是header
        -- 需要预防一下, 头部都没发完整的情况
        local s = resp.tmpdata or ""
        s = s .. data
        if #s < 3 then
            resp.tmpdata = s
            return true -- 继续等数据
        end
        if not string.find(s, '\r\n\r\n', 1, true) then
            -- header超过8kb了,还没结束,肯定有妖,拒绝
            if #s > 8192 then
                log.info("httpv2", "Header bigger than 8192")
                resp.tmpdata = nil
                resp.code = 499
                resp.msg = "Header bigger than 8192"
                return false
            else
                resp.tmpdata = s
                return true -- 继续等数据
            end
        end
        resp.tmpdata = nil -- 可以释放了
        -- 接下来,是解析code和header的过程了
        local _, idx, response_code = s:find("%s(%d+)%s.-\r\n")
        local _, offset = s:find('\r\n\r\n')
        local response_header = {}
        for k, v in string.gmatch(s:sub(idx + 1, offset), "(.-):%s*(.-)\r\n") do response_header[k] = v end
        local len = response_header["Content-Range"] and tonumber(response_header["Content-Range"]:match("/(%d+)")) or tonumber(response_header["Content-Length"]) or 2147483648
        s = s:sub((offset or 0) + 1, -1)
        
        resp.code = response_code
        resp.headers = response_header
        resp.body = s
        --resp.ok = resp.code == 200 or resp.code == 206
        return true
    end
    resp.body = resp.body .. data -- 如果数据太长, 应该提前报警!!
    return true
end

-- 处理表的url编码
function urlencodeTab(params)
    local msg = {}
    for k, v in pairs(params) do
        table.insert(msg, string.urlEncode(k) .. '=' .. string.urlEncode(v))
        table.insert(msg, '&')
    end
    table.remove(msg)
    return table.concat(msg)
end
--- HTTP客户端
-- @string method,提交方式"GET" or "POST"
-- @string url,HTTP请求超链接
-- @number timeout,超时时间
-- @param params,table类型，请求发送的查询字符串，通常为键值对表
-- @param data,table类型，正文提交的body,通常为键值对、json或文件对象类似的表
-- @number ctype,Content-Type的类型(可选1,2,3),默认1:"urlencode",2:"json",3:"octet-stream"
-- @string basic,HTTP客户端的authorization basic验证的"username:password"
-- @param headers,table类型,HTTP headers部分
-- @param cert,table类型，此参数可选，默认值为： nil，ssl连接需要的证书配置，只有ssl参数为true时，才参数才有意义，cert格式如下：
-- {
--  caCert = "ca.crt", --CA证书文件(Base64编码 X.509格式)，如果存在此参数，则表示客户端会对服务器的证书进行校验；不存在则不校验
--  clientCert = "client.crt", --客户端证书文件(Base64编码 X.509格式)，服务器对客户端的证书进行校验时会用到此参数
--  clientKey = "client.key", --客户端私钥文件(Base64编码 X.509格式) clientPassword = "123456", --客户端证书文件密码[可选]
--  }
-- @return string,table,string,正常返回response_code, response_header, response_body
-- @return string,string,错误返回 response_code, error_message
-- @usage local c, h, b = httpv2.request(url, method, headers, body)
-- @usage local r, e  = httpv2.request("http://wrong.url/ ")
function httpv2.request(method, url, timeout, params, data, ctype, basic, headers, cert, fnc)
    local response_header, response_code, response_body = {}
    local _, idx, offset, ssl, auth, https, host, port, path
    if type(headers) == "string" then
        local tmp = {}
        for k, v in string.gmatch(headers, "(.-):%s*(.-)\r\n") do tmp[k] = v end
        headers = tmp
    elseif type(headers) ~= "table" then
        headers = {
            ['User-Agent'] = 'Mozilla/4.0',
            ['Accept'] = '*/*',
            ['Accept-Language'] = 'zh-CN,zh,cn',
            ['Content-Type'] = 'application/x-www-form-urlencoded',
            ['Connection'] = 'close',
        }
    end
    -- 处理url的协议头和鉴权
    _, offset, https = url:find("^(%a+)://")
    _, idx, auth = url:find("(.-:.-)@", (offset or 0) + 1)
    offset = idx or offset
    -- 对host:port整形
    if url:match("^[^/]+:(%d+)", (offset or 0) + 1) then
        _, offset, host, port = url:find("^([^/]+):(%d+)", (offset or 0) + 1)
    elseif url:find("(.-)/", (offset or 0) + 1) then
        _, offset, host = url:find("(.-)/", (offset or 0) + 1)
        offset = offset - 1
    else
        offset, host = #url, url:sub((offset or 0) + 1, -1)
    end
    if not host then return '105', 'ERR_NAME_NOT_RESOLVED' end
    if not headers.Host then headers["Host"] = host end
    port = port or (https == "https" and 443 or 80)
    path = url:sub(offset + 1, -1)
    path = path == "" and "/" or path
    -- 处理查询字符串
    if params then path = path .. '?' .. (type(params) == 'table' and urlencodeTab(params) or params) end
    -- 处理HTTP协议body部分的数据
    ctype = ctype or 2
    headers['Content-Type'] = Content_type[ctype]
    if ctype == 1 and type(data) == 'table' then
        data = urlencodeTab(data)
        headers['Content-Length'] = #data or 0
    elseif ctype == 2 and data ~= nil then
        data = type(data) == 'string' and data or (type(data) == 'table' and json.encode(data)) or ""
        headers['Content-Length'] = #data or 0
    elseif ctype == 3 and type(data) == 'string' then
        headers['Content-Length'] = io.fileSize(data) or 0
    elseif data and type(data) == "string" then
        headers['Content-Length'] = #data or 0
    end
    -- 处理HTTP Basic Authorization 验证
    if auth then
        headers['Authorization'] = 'Basic ' .. crypto.base64_encode(auth, #auth)
    elseif type(basic) == 'string' then
        headers['Authorization'] = 'Basic ' .. crypto.base64_encode(basic, #basic)
    end
    -- 处理headers部分
    local str = ""
    for k, v in pairs(headers) do str = str .. k .. ": " .. v .. "\r\n" end
    -- @LuatOS, 部分特性未支持,所以先过滤一下
    if ctype == 3 then return '499', 'CTYPE_NOT_SUPPRT' end
    log.info("httpv2", "all ready", "do tcp connect")
    -- 发送请求报文
    while not socket.isReady() do sys.wait(1000) end
    local c = socket.tcp(https == "https", cert)
    c:host(host)
    c:port(port)
    local connect_topic = "NETC_CONNECT_" .. tostring(c:id())
    local connect_re = false
    local resp = {}
    c:on("connect", function(id, re)
        connect_re = re
        sys.publish(connect_topic, re)
        if not re then
            c:clean()
            c:close()
        end
    end)
    c:on("recv", function(id, data)
        log.debug("httpv2", "recv", "first 30 bytes", string.sub(data, 1, 30))
        if not update_resp(resp, data) then
            log.info("httpv2", "close connect for bad resp")
            c:clean()
            c:close()
        end
    end)
    if not c:start() then
        c:clean()
        c:close()
        return "499", "SOCKET_CONN_START_ERROR"
    end
    sys.waitUntil(connect_topic, 15000)
    if not connect_re then
        c:clean()
        c:close()
        return "499", "SOCKET_CONN_CONNECT_ERROR"
    end
    if ctype ~= 3 then
        str = method .. ' ' .. path .. ' HTTP/1.0\r\n' .. str .. '\r\n' .. (data and data .. "\r\n" or "")
        log.info("send http request:", str)
        if not c:send(str) then
            c:clean()
            c:close()
            return '426', 'SOCKET_SEND_ERROR'
        end
    else
        str = method .. ' ' .. path .. ' HTTP/1.0\r\n' .. str .. '\r\n'
        log.info("send http request:", str)
        if not c:send(str) then
            c:clean()
            c:close()
            return '426', 'SOCKET_SEND_ERROR'
        end
        local file = io.open(data, 'r')
        if file then
            while true do
                local dat = file:read(8192)
                if dat == nil then
                    io.close(file)
                    break
                end
                if not c:send(dat) then
                    io.close(file)
                    c:close()
                    return '426', 'SOCKET_SEND_ERROR'
                end
            end
        end
        if not c:send('\r\n') then
            c:close()
            return '426', 'SOCKET_SEND_ERROR'
        end
    end

    -- 等待结束
    while c:closed() == 0 do
        sys.waitUntil("NETC_END_" .. c:id(), timeout)
    end
    c:clean()
    c:close()
    if resp.code then
        log.info("httpv2", "resp code", resp.code, "body len", #resp.body)
        return resp.code, resp.headers, resp.body
    end
    return 502, {}, ""
    ------------------------------------ 接收服务器返回消息部分 ------------------------------------
    --[[
    local msg, str = {}, ""
    local r, s = c:recv(timeout)
    if not r then
        c:close()
        return '503', 'SOCKET_RECV_TIMOUT'
    end
    -- 处理状态代码
    _, idx, response_code = s:find("%s(%d+)%s.-\r\n")
    _, offset = s:find('\r\n\r\n')
    if not idx or not offset then return '501', 'SERVER_NOT_RESPONSE' end
    log.info('httpv2.response code:', response_code)
    -- 处理headers代码
    for k, v in string.gmatch(s:sub(idx + 1, offset), "(.-):%s*(.-)\r\n") do response_header[k] = v end
    local len = response_header["Content-Range"] and tonumber(response_header["Content-Range"]:match("/(%d+)")) or tonumber(response_header["Content-Length"]) or 2147483648
    
    s = s:sub((offset or 0) + 1, -1)
    local cnt = #s
    if tonumber(response_code) == 200 or tonumber(response_code) == 206 then
        -- 处理body
        while true do
            if type(fnc) == "function" then
                fnc(s, len)
            else
                table.insert(msg, s)
            end
            if cnt >= len then break end
            r, s = c:recv(timeout)
            if not r then break end
            cnt = cnt + #s
        end
        s = table.concat(msg) or ""
    end
    c:close()
    local gzip = response_header["Content-Encoding"] == "gzip"
    return response_code, response_header, gzip and ((zlib.inflate(s)):read()) or s
    ]]
end

return httpv2
