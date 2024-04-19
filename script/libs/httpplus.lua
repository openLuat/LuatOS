--[[
@module httpplus
@summary http库的补充
@version 1.0
@date    2023.11.23
@author  wendal
@demo   httpplus
@tag    LUAT_USE_NETWORK
@usage
-- 本库支持的功能有:
--   1. 大文件上传的问题,不限大小
--   2. 任意长度的header设置
--   3. 任意长度的body设置
--   4. 鉴权URL自动识别
--   5. body使用zbuff返回,可直接传输给uart等库

-- 与http库的差异
--   1. 不支持文件下载
--   2. 不支持fota
]]


local httpplus = {}
local TAG = "httpplus"

local function http_opts_parse(opts)
    if not opts then
        log.error(TAG, "opts不能为nil")
        return -100, "opts不能为nil"
    end
    if not opts.url or #opts.url < 5 then
        log.error(TAG, "URL不存在或者太短了", url)
        return -100, "URL不存在或者太短了"
    end
    if not opts.headers then
        opts.headers = {}
    end

    if opts.debug or httpplus.debug then
        if not opts.log then
            opts.log = log.debug
        end
    else
        opts.log = function() 
            -- log.info(TAG, "无日志")
        end
    end

    -- 解析url
    -- 先判断协议是否加密
    local is_ssl = false
    local tmp = ""
    if opts.url:startsWith("https://") then
        is_ssl = true
        tmp = opts.url:sub(9)
    elseif opts.url:startsWith("http://") then
        tmp = opts.url:sub(8)
    else
        tmp = opts.url
    end
    -- log.info("http分解阶段1", is_ssl, tmp)
    -- 然后判断host段
    local uri = ""
    local host = ""
    local port = 0
    if tmp:find("/") then
        uri = tmp:sub((tmp:find("/"))) -- 注意find会返回多个值
        tmp = tmp:sub(1, tmp:find("/") - 1)
    else
        uri = "/"
    end
    -- log.info("http分解阶段2", is_ssl, tmp, uri)
    if tmp == nil or #tmp == 0 then
        log.error(TAG, "非法的URL", url)
        return -101, "非法的URL"
    end
    -- 有无鉴权信息
    if tmp:find("@") then
        local auth = tmp:sub(1, tmp:find("@") - 1)
        if not opts.headers["Authorization"] then
            opts.headers["Authorization"] = "Basic " .. auth:toBase64()
        end
        -- log.info("http鉴权信息", auth, opts.headers["Authorization"])
        tmp = tmp:sub(tmp:find("@") + 1)
    end
    -- 解析端口
    if tmp:find(":") then
        host = tmp:sub(1, tmp:find(":") - 1)
        port = tmp:sub(tmp:find(":") + 1)
        port = tonumber(port)
    else
        host = tmp
    end
    if not port or port < 1 then
        if is_ssl then
            port = 443
        else
            port = 80
        end
    end
    -- 收尾工作
    if not opts.headers["Host"] then
        opts.headers["Host"] = string.format("%s:%d", host, port)
    end
    -- Connection 必须关闭
    opts.headers["Connection"] = "Close"

    -- 复位一些变量,免得判断出错
    opts.is_closed = nil
    opts.body_len = 0

    -- multipart需要boundary
    local boundary = "------------------------16ef6e68ef" .. tostring(os.time())
    opts.boundary = boundary
    opts.mp = {}

    if opts.files then
        -- 强制设置为true
        opts.multipart = true
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
        for kk, vv in pairs(opts.files) do
            local ct = contentType[vv:match("%.(%w+)$")] or "application/octet-stream"
            local fname = vv:match("[^%/]+%w$")
            local tmp = string.format("--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\nContent-Type: %s\r\n\r\n", boundary, kk, fname, ct)
            -- log.info("文件传输头", tmp)
            table.insert(opts.mp, {vv, tmp, "file"})
            opts.body_len = opts.body_len + #tmp + io.fileSize(vv) + 2
            -- log.info("当前body长度", opts.body_len, "文件长度", io.fileSize(vv), fname, ct)
        end
    end

    -- 表单数据
    if opts.forms then
        if opts.multipart then
            for kk, vv in pairs(opts.forms) do
                local tmp = string.format("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n", boundary, kk)
                table.insert(opts.mp, {vv, tmp, "form"})
                opts.body_len = opts.body_len + #tmp + #vv + 2
                -- log.info("当前body长度", opts.body_len, "数据长度", #vv)
            end
        else
            if not opts.headers["Content-Type"] then
                opts.headers["Content-Type"] = "application/x-www-form-urlencoded;charset=UTF-8"
            end
            local buff = zbuff.create(120)
            for kk, vv in pairs(opts.forms) do
                buff:copy(nil, kk)
                buff:copy(nil, "=")
                buff:copy(nil, string.urlEncode(tostring(vv)))
                buff:copy(nil, "&")
            end
            if buff:used() > 0 then
                buff:del(-1, 1)
                opts.body = buff
                opts.body_len = buff:used()
                opts.log(TAG, "普通表单", opts.body)
            end
        end
    end

    -- 如果multipart模式
    if opts.multipart then
        -- 如果没主动设置body, 那么补个结尾
        if not opts.body then
            opts.body_len = opts.body_len + #boundary + 2 + 2 + 2
        end
        -- Content-Type没设置? 那就设置一下
        if not opts.headers["Content-Type"] then
            opts.headers["Content-Type"] = "multipart/form-data; boundary="..boundary
        end
    end

    -- 直接设置bodyfile
    if opts.bodyfile then
        local fd = io.open(opts.bodyfile, "rb")
        if not fd then
            log.error("httpplus", "bodyfile失败,文件不存在", opts.bodyfile)
            return -104, "bodyfile失败,文件不存在"
        end
        fd:close()
        opts.body_len = io.fileSize(opts.bodyfile)
    end

    -- 有设置body, 而且没设置长度
    if opts.body and (not opts.body_len or opts.body_len == 0) then
        -- body是zbuff的情况
        if type(opts.body) == "userdata" then
            opts.body_len = opts.body:used()
        -- body是json的情况
        elseif type(opts.body) == "table" then
            opts.body = json.encode(opts.body, "7f")
            if opts.body then
                opts.body_len = #opts.body
                if not opts.headers["Content-Type"] then
                    opts.headers["Content-Type"] = "application/json;charset=UTF-8"
                    opts.log(TAG, "JSON", opts.body)
                end
            end
        -- 其他情况就只能当文本了
        else
            opts.body = tostring(opts.body)
            opts.body_len = #opts.body
        end
    end
    -- 一定要设置Content-Length,而且强制覆盖客户自定义的值
    -- opts.body_len = opts.body_len or 0
    opts.headers["Content-Length"] = tostring(opts.body_len or 0)

    -- 如果没设置method, 自动补齐
    if not opts.method or #opts.method == 0 then
        if opts.body_len > 0 then
            opts.method = "POST"
        else
            opts.method = "GET"
        end
    else
        -- 确保一定是大写字母
        opts.method = opts.method:upper()
    end

    if opts.debug then
        opts.log(TAG, is_ssl, host, port, uri, json.encode(opts.headers))
    end
    

    -- 把剩余的属性设置好
    opts.host = host
    opts.port = port
    opts.uri  = uri
    opts.is_ssl = is_ssl

    if not opts.timeout or opts.timeout == 0 then
        opts.timeout = 30
    end

    return -- 成功完成,不需要返回值
end



local function zbuff_find(buff, str)
    -- log.info("zbuff查找", buff:used(), #str)
    if buff:used() < #str then
        return
    end
    local maxoff = buff:used()
    maxoff = maxoff - #str
    local tmp = zbuff.create(#str)
    tmp:write(str)
    -- log.info("tmp数据", tmp:query():toHex())
    for i = 0, maxoff, 1 do
        local flag = true
        for j = 0, #str - 1, 1 do
            -- log.info("对比", i, j, string.char(buff[i+j]):toHex(), string.char(tmp[j]):toHex(), buff[i+j] ~= tmp[j])
            if buff[i+j] ~= tmp[j] then
                flag = false
                break
            end
        end
        if flag then
            return i
        end
    end
end

local function resp_parse(opts)
    -- log.info("这里--------")
    local header_offset = zbuff_find(opts.rx_buff, "\r\n\r\n")
    -- log.info("头部偏移量", header_offset)
    if not header_offset then
        log.warn(TAG, "没有检测到http响应头部,非法响应")
        opts.resp_code = -198
        return
    end
    local state_line_offset = zbuff_find(opts.rx_buff, "\r\n")
    local state_line = opts.rx_buff:query(0, state_line_offset)
    local tmp = state_line:split(" ")
    if not tmp or #tmp < 2 then
        log.warn(TAG, "非法的响应行", state_line)
        opts.resp_code = -197
        return
    end
    local code = tonumber(tmp[2])
    if not code then
        log.warn(TAG, "非法的响应码", tmp[2])
        opts.resp_code = -196
        return
    end
    opts.resp_code = code
    opts.resp = {
        headers = {}
    }
    opts.log(TAG, "state code", code)
    -- TODO 解析header和body

    opts.rx_buff:del(0, state_line_offset + 2)
    -- opts.log(TAG, "剩余的响应体", opts.rx_buff:query())

    -- 解析headers
    while 1 do
        local offset = zbuff_find(opts.rx_buff, "\r\n")
        if not offset then
            log.warn(TAG, "不合法的剩余headers", opts.rx_buff:query())
            break
        end
        if offset == 0 then
            -- header的最后一个空行
            opts.rx_buff:del(0, 2)
            break
        end
        local line = opts.rx_buff:query(0, offset)
        opts.rx_buff:del(0, offset + 2)
        local tmp2 = line:split(":")
        opts.log(TAG, tmp2[1]:trim(), tmp2[2]:trim())
        opts.resp.headers[tmp2[1]:trim()] = tmp2[2]:trim()
    end

    -- if opts.resp_code < 299 then
        -- 解析body
        -- 有Content-Length就好办
        if opts.resp.headers["Content-Length"] then
            opts.log(TAG, "有长度, 标准的咯")
            opts.resp.body = opts.rx_buff
        elseif opts.resp.headers["Transfer-Encoding"] == "chunked" then
            -- log.info(TAG, "数据是chunked编码", opts.rx_buff[0], opts.rx_buff[1])
            -- log.info(TAG, "数据是chunked编码", opts.rx_buff:query(0, 4):toHex())
            local coffset = 0
            local crun = true
            while crun and coffset < opts.rx_buff:used() do
                -- 从当前offset读取长度, 长度总不会超过8字节吧?
                local flag = true
                -- local coffset = zbuff_find(opts.rx_buff, "\r\n")
                -- if not coffset then
                    
                -- end
                for i = 1, 8, 1 do
                    if opts.rx_buff[coffset+i] == 0x0D and opts.rx_buff[coffset+i+1] == 0x0A then
                        local ctmp = opts.rx_buff:query(coffset, i)
                        -- opts.log(TAG, "chunked分片长度", ctmp, ctmp:toHex())
                        local clen = tonumber(ctmp, 16)
                        -- opts.log(TAG, "chunked分片长度2", clen)
                        if clen == 0 then
                            -- 末尾了
                            opts.rx_buff:resize(coffset)
                            crun = false
                        else
                            -- 先删除chunked块
                            opts.rx_buff:del(coffset, i+2)
                            coffset = coffset + clen
                        end
                        flag = false
                        break
                    end
                end
                -- 肯定能搜到chunked
                if flag then
                    log.error("非法的chunked块")
                    break
                end
            end
            opts.resp.body = opts.rx_buff
        end
    -- end

    -- 清空rx_buff
    opts.rx_buff = nil

    -- 完结散花
end

-- socket 回调函数
local function http_socket_cb(opts, event)
    opts.log(TAG, "tcp.event", event)
    if event == socket.ON_LINE then
        -- TCP链接已建立, 那就可以上行了
        -- opts.state = "ON_LINE"
        sys.publish(opts.topic)
    elseif event == socket.TX_OK then
        -- 数据传输完成, 如果是文件上传就需要这个消息
        -- opts.state = "TX_OK"
        sys.publish(opts.topic)
    elseif event == socket.EVENT then
        -- 收到数据或者链接断开了, 这里总需要读取一次才知道
        local succ, data_len = socket.rx(opts.netc, opts.rx_buff)
        if succ and data_len > 0 then
            opts.log(TAG, "收到数据", data_len, "总长", #opts.rx_buff)
            -- opts.log(TAG, "数据", opts.rx_buff:query())
        else
            if not opts.is_closed then
                opts.log(TAG, "服务器已经断开了连接或接收出错")
                opts.is_closed = true
                sys.publish(opts.topic)
            end
        end
    elseif event == socket.CLOSED then
        log.info(TAG, "连接已关闭")
        opts.is_closed = true
        sys.publish(opts.topic)
    end
end

local function http_exec(opts)
    local netc = socket.create(opts.adapter, function(sc, event)
        if opts.netc then
            return http_socket_cb(opts, event)
        end
    end)
    if not netc then
        log.error(TAG, "创建socket失败了!!")
        return -102
    end
    opts.netc = netc
    opts.rx_buff = zbuff.create(1024)
    opts.topic = tostring(netc)
    socket.config(netc, nil,nil, opts.is_ssl)
    if opts.debug or httpplus.debug then
        socket.debug(netc)
    end
    if not socket.connect(netc, opts.host, opts.port, opts.try_ipv6) then
        log.warn(TAG, "调用socket.connect返回错误了")
        return -103, "调用socket.connect返回错误了"
    end
    local ret = sys.waitUntil(opts.topic, 5000)
    if ret == false then
        log.warn(TAG, "建立连接超时了!!!")
        return -104, "建立连接超时了!!!"
    end
    
    -- 首先是头部
    local line = string.format("%s %s HTTP/1.1\r\n", opts.method:upper(), opts.uri)
    -- opts.log(TAG, line)
    socket.tx(netc, line)
    for k, v in pairs(opts.headers) do
        line = string.format("%s: %s\r\n", k, v)
        socket.tx(netc, line)
    end
    line = "\r\n"
    socket.tx(netc, line)

    -- 然后是body
    local rbody = ""
    local write_counter = 0
    if opts.mp and #opts.mp > 0 then
        opts.log(TAG, "执行mulitpart上传模式")
        for k, v in pairs(opts.mp) do
            socket.tx(netc, v[2])
            write_counter = write_counter + #v[2]
            if v[3] == "file" then
                -- log.info("写入文件数据头", v[2])
                local fd = io.open(v[1], "rb")
                -- log.info("写入文件数据", v[1])
                if fd then
                    while not opts.is_closed do
                       local fdata = fd:read(1400)
                        if not fdata or #fdata == 0 then
                            break
                        end
                        -- log.info("写入文件数据", "长度", #fdata)
                        socket.tx(netc, fdata)
                        write_counter = write_counter + #fdata
                        -- 注意, 这里要等待TX_OK事件
                        sys.waitUntil(opts.topic, 3000)
                    end
                    fd:close()
                end
            else
                socket.tx(netc, v[1])
                write_counter = write_counter + #v[1]
            end
            socket.tx(netc, "\r\n")
            write_counter = write_counter + 2
        end
        -- rbody = rbody .. "--" .. opts.boundary .. "--\r\n"
        socket.tx(netc, "--")
        socket.tx(netc, opts.boundary)
        socket.tx(netc, "--\r\n")
        write_counter = write_counter + #opts.boundary + 2 + 2 + 2
    elseif opts.bodyfile then
        local fd = io.open(opts.bodyfile, "rb")
        -- log.info("写入文件数据", v[1])
        if fd then
            while not opts.is_closed do
                local fdata = fd:read(1400)
                if not fdata or #fdata == 0 then
                    break
                end
                -- log.info("写入文件数据", "长度", #fdata)
                socket.tx(netc, fdata)
                write_counter = write_counter + #fdata
                -- 注意, 这里要等待TX_OK事件
                sys.waitUntil(opts.topic, 300)
            end
            fd:close()
        end
    elseif opts.body then
        if type(opts.body) == "string" and #opts.body > 0 then
            socket.tx(netc, opts.body)
            write_counter = write_counter + #opts.body
        elseif type(opts.body) == "userdata" then
            write_counter = write_counter + opts.body:used()
            if opts.body:used() < 4*1024 then
                socket.tx(netc, opts.body)
            else
                local offset = 0
                local tmpbuff = opts.body
                local tsize = tmpbuff:used()
                while offset < tsize do
                    opts.log(TAG, "body(zbuff)分段写入", offset, tsize)
                    if tsize - offset > 4096 then
                        socket.tx(netc, tmpbuff:toStr(offset, 4096))
                        offset = offset + 4096
                        sys.waitUntil(opts.topic, 300)
                    else
                        socket.tx(netc, tmpbuff:toStr(offset, tsize - offset))
                        break
                    end
                end
            end
        end
    end
    -- log.info("写入长度", "期望", opts.body_len, "实际", write_counter)
    -- log.info("hex", rbody)

    -- 处理响应信息
    while not opts.is_closed and opts.timeout > 0 do
        log.info(TAG, "等待服务器完成响应")
        sys.waitUntil(opts.topic, 1000)
        opts.timeout = opts.timeout - 1
    end
    log.info(TAG, "服务器已完成响应,开始解析响应")
    resp_parse(opts)
    -- log.info("执行完成", "返回结果")
end

--[[
执行HTTP请求
@api httpplus.request(opts)
@table 请求参数,是一个table,最起码得有url属性
@return int 响应码,服务器返回的状态码>=100, 若本地检测到错误,会返回<0的值
@return 服务器正常响应时返回结果, 否则是错误信息或者nil
@usage
-- 请求参数介绍
local opts = {
    url    = "https://httpbin.air32.cn/abc", -- 必选, 目标URL
    method = "POST", -- 可选,默认GET, 如果有body,files,forms参数,会设置成POST
    headers = {}, -- 可选,自定义的额外header
    files = {},   -- 可选,文件上传,若存在本参数,会强制以multipart/form-data形式上传
    forms = {},   -- 可选,表单参数,若存在本参数,如果不存在files,按application/x-www-form-urlencoded上传
    body  = "abc=123",-- 可选,自定义body参数, 字符串/zbuff/table均可, 但不能与files和forms同时存在
    debug = false,    -- 可选,打开调试日志,默认false
    try_ipv6 = false, -- 可选,是否优先尝试ipv6地址,默认是false
    adapter = nil,    -- 可选,网络适配器编号, 默认是自动选
    timeout = 30,     -- 可选,读取服务器响应的超时时间,单位秒,默认30
    bodyfile = "xxx"  -- 可选,直接把文件内容作为body上传, 优先级高于body参数
}

local code, resp = httpplus.request({url="https://httpbin.air32.cn/get"})
log.info("http", code)
-- 返回值resp的说明
-- 情况1, code >= 100 时, resp会是个table, 包含2个元素
if code >= 100 then
    -- headers, 是个table
    log.info("http", "headers", json.encode(resp.headers))
    -- body, 是个zbuff
    -- 通过query函数可以转为lua的string
    log.info("http", "headers", resp.body:query())
    -- 也可以通过uart.tx等支持zbuff的函数转发出去
    -- uart.tx(1, resp.body)
end
]]
function httpplus.request(opts)
    -- 参数解析
    local ret = http_opts_parse(opts)
    if ret then
        return ret
    end

    -- 执行请求
    local ret, msg = pcall(http_exec, opts)
    if opts.netc then
        -- 清理连接
        if not opts.is_closed then
            socket.close(opts.netc)
        end
        socket.release(opts.netc)
        opts.netc = nil
    end
    -- 处理响应或错误
    if not ret then
        log.error(TAG, msg)
        return -199, msg
    end
    return opts.resp_code, opts.resp
end

return httpplus
