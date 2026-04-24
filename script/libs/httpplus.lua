--[[
@module httpplus
@summary http库的补充
@version 1.0
@date    2023.11.23
@author  wendal
@demo    httpplus
@tag    LUAT_USE_NETWORK
@usage
-- 本库支持的功能有:
--   1. 大文件上传的问题,不限大小
--   2. 任意长度的header设置
--   3. 任意长度的body设置
--   4. 鉴权URL自动识别
--   5. body使用zbuff返回,可直接传输给uart等库
--   6. 下载回调函数, 可以处理大文件下载,不限大小
--   7. 文件下载和fota升级



-- 支持  http 1.0 和 http 1.1, 不支持http2.0
-- 支持 GET/POST/PUT/DELETE/HEAD 等常用方法,也支持自定义method
-- 支持 HTTP 和 HTTPS 协议
-- 支持 IPv4 和 IPv6
-- 支持 HTTP 鉴权
-- 支持 multipart/form-data 上传文件和表单
-- 支持 application/x-www-form-urlencoded 上传表单
-- 支持 application/json 上传json数据
-- 支持 自定义 body 上传任意数据
-- 支持 自定义 headers
-- 支持 大文件上传,不限大小
-- 支持 zbuff 作为 body 上传和响应返回
-- 支持 bodyfile 直接把文件内容作为body上传
-- 支持 上传时使用自定义缓冲区, 2025.9.25 新增
-- 支持 通过回调函数处理单包/chunk块数据， 2026.1.9 新增
-- 支持 下载大文件,不限大小,需要搭配回调函数， 2026.1.9 新增
-- 支持 文件下载到本地
-- 支持 fota升级
]]


local httpplus = {}
local TAG = "httpplus"

local function http_opts_parse(opts)
    if not opts then
        log.error(TAG, "opts不能为nil")
        return -100, "opts不能为nil"
    end
    if not opts.url or #opts.url < 5 then
        log.error(TAG, "URL不存在或者太短了", opts.url)
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
        log.error(TAG, "非法的URL", opts.url)
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
        if (is_ssl and port == 443) or ((not is_ssl) and port == 80) then
            opts.headers["Host"] = host
        else
            opts.headers["Host"] = string.format("%s:%d", host, port)
        end
    end
    -- Connection 必须关闭
    opts.headers["Connection"] = "Close"

    -- 复位一些变量,免得判断出错
    opts.is_closed = nil
    opts.body_len = 0

    -- multipart需要boundary
    local boundary = "----WebKitFormBoundary"..os.time()
    opts.boundary = boundary
    -- MIME Multipart Media Encapsulation, Type: multipart/form-data, Boundary: "------------------------16ef6e68ef1766793020"
    opts.mp = {}

    if opts.files then
        -- 强制设置为true
        opts.multipart = true
    end

    -- 表单数据
    if opts.forms then
        if opts.multipart then
            for kk, vv in pairs(opts.forms) do
                local tmp = string.format("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n", boundary, kk)
                table.insert(opts.mp, {tostring(vv), tmp, "form"})
                opts.body_len = opts.body_len + #tmp + #tostring(vv) + 2
                -- log.info("当前body长度", opts.body_len, "数据长度", #vv)
            end
        else
            if not opts.headers["Content-Type"] then
                opts.headers["Content-Type"] = "application/x-www-form-urlencoded;charset=UTF-8"
            end
            local buff = zbuff.create(256)
            for kk, vv in pairs(opts.forms) do
                buff:copy(nil, string.urlEncode(tostring(kk)))
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

    if opts.files then
        -- 强制设置为true
        opts.multipart = true
        local contentType = {
            txt = "text/plain",             -- 文本
            jpg = "image/jpeg",             -- JPG 格式图片
            jpeg = "image/jpeg",            -- JPEG 格式图片
            png = "image/png",              -- PNG 格式图片   
            gif = "image/gif",              -- GIF 格式图片
            html = "text/html",             -- HTML
            json = "application/json",      -- JSON
            mp4 = "video/mp4",              -- MP4 格式视频
            mp3 = "audio/mp3",              -- MP3 格式音频
            webm = "video/webm",            -- WebM 格式视频
        }
        for kk, vv in pairs(opts.files) do
            local ct = contentType[vv:match("%.(%w+)$")] or "application/octet-stream"
            local fname = vv:match("([^/\\]+)$") or vv
            local tmp = string.format("--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\nContent-Type: %s\r\n\r\n", boundary, kk, fname, ct)
            -- log.info("文件传输头", tmp)
            table.insert(opts.mp, {vv, tmp, "file"})
            opts.body_len = opts.body_len + #tmp + io.fileSize(vv) + 2
            -- log.info("当前body长度", opts.body_len, "文件长度", io.fileSize(vv), fname, ct)
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

    -- 如果是大文件下载模式, 那么强制要求提供 callback
    if opts.is_big_file then
        if not opts.callback then
            log.error(TAG, "is_big_file 模式必须提供 callback")
            return -105, "is_big_file 模式必须提供 callback"
        end
        -- 强制不缓存 body
        opts.no_cache_body = true
    else
        opts.no_cache_body = false
    end

    -- 处理文件下载和fota
    if opts.fota then
        if not fota then
            log.error(TAG, "fota模式但fota模块不可用")
            return -107, "fota模块不可用"
        end
        opts.no_cache_body = true
    elseif opts.dst then
        opts.no_cache_body = true
        if not opts.write_fd then
            local write_fd = io.open(opts.dst, "wb")
            if not write_fd then
                log.error(TAG, "无法打开文件用于写入", opts.dst)
                return -106, "无法打开文件用于写入"
            end
            opts.write_fd = write_fd
        end
    end

    if opts.fota or opts.dst then
        local user_callback = opts.callback
        opts.callback = function(total_len, recv_len, recv_data, userdata)
            if opts.write_fd then
                opts.write_fd:write(recv_data)
            elseif opts.fota then
                local result, isDone, cache = fota.run(recv_data)
                if not result then
                    log.error(TAG, "fota.run写入失败")
                    opts.fota_error = true
                end
                opts.fota_isDone = isDone
                opts.fota_cache = cache
            end
            if user_callback then
                user_callback(total_len, recv_len, recv_data, userdata)
            end
        end
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

local function resp_parse(opts, data_len)
    -- 初始化resp
    if not opts.resp then
        -- 初始化headers
        opts.resp = {headers = {}}
        -- 如果需要返回body, 那么先初始化body
        if not opts.no_cache_body then
            opts.resp.body = zbuff.create(1024)
        end
    end

    -- 从rx_buff中提取新数据给rx_data，rx_data用于后续解析
    local used_len = opts.rx_buff:used()
    local start_pos = used_len - data_len
    -- log.info(TAG, "缓冲区状态", "used:", used_len, "data_len:", data_len, "start_pos:", start_pos)

    local rx_data = opts.rx_buff:query(start_pos, data_len)
    -- log.info(TAG, "当前rx_data", "长度:", #rx_data, "数据:", rx_data:toHex())

    -- 初始化头部解析状态变量
    if opts.header_parsed == nil then
        opts.header_parsed = false
    end

    -- 如果头部还未解析, 那么先解析头部
    if not opts.header_parsed then

        if not opts.header_buff then
            opts.header_buff = zbuff.create(1024)
        end
        -- 先把rx_data复制到header_buff，用于后续解析头部
        opts.header_buff:copy(nil, rx_data)

        opts.log(TAG, "尝试解析http响应头部")
        -- 查找头部结束的偏移量
        local header_offset = zbuff_find(opts.header_buff, "\r\n\r\n")
        -- log.info("头部偏移量", header_offset)
        -- 如果未找到头部结束符, 那么判断是否超时, 如果超时, 则返回错误码
        if opts.is_timeout and not header_offset then
            log.warn(TAG, "HTTP请求超时且未检测到完整响应头部")
            opts.resp_code = -198
            return
        end
        -- 解析状态行，格式通常为"HTTP/1.1 200 OK\r\n"
        local state_line_offset = zbuff_find(opts.header_buff, "\r\n")
        if not state_line_offset then
            -- 还没收到完整的状态行
            return
        end
        local state_line = opts.header_buff:query(0, state_line_offset)
        local tmp = state_line:split(" ") -- 将状态行内容按空格分割成数组
        -- 状态行至少包含协议版本、响应码
        if not tmp or #tmp < 2 then
            log.warn(TAG, "非法的响应行", state_line)
            opts.resp_code = -197
            return
        end
        -- 解析出响应码
        local code = tonumber(tmp[2])
        if not code then
            log.warn(TAG, "非法的响应码", tmp[2])
            opts.resp_code = -196
            return
        end
        opts.resp_code = code
        opts.log(TAG, "state code", code)

        -- 如果是fota模式且状态码成功，初始化fota
        if opts.fota and (code == 200 or code == 206) then
            opts.fota_ready = true
        end

        -- 删除状态行
        opts.header_buff:del(0, state_line_offset + 2)
        opts.log(TAG, "剩余的响应体", opts.header_buff:query())

        -- 解析headers（仅按首个冒号拆分，保留值中的冒号）
        while true do
            -- 查找下一个header行的结束偏移量
            local offset = zbuff_find(opts.header_buff, "\r\n")
            if not offset then
                -- 还没收到完整的头部
                return
            end
            if offset == 0 then
                -- header的最后一个空行
                opts.header_buff:del(0, 2)
                break
            end
            -- 解析header行
            local line = opts.header_buff:query(0, offset)
            opts.header_buff:del(0, offset + 2)
            local name, value = line:match("^([^:]+):%s*(.*)$")
            -- 解析出头部字段名和值
            if name and value then
                name = name:trim() -- 移除字段名首尾空格、制表符、换行符等
                value = value:trim() -- 移除字段值首尾空格、制表符、换行符等
                opts.log(TAG, name, value)
                opts.resp.headers[name] = value
            else
                opts.log(TAG, "忽略非法header行", line)
            end
        end

        -- 解析完成后，若header_buff中还有数据，那么将其作为新的rx_data
        if opts.header_buff:used() > 0 then
            opts.log(TAG, "剩余的响应体2", opts.header_buff:query())
            rx_data = opts.header_buff:query()
            opts.header_buff:clear() -- 清空，不再需要
        else -- 若没有剩余数据，那么rx_data为空字符串
            rx_data = ""
        end

        opts.header_parsed = true
        opts.header_buff = nil -- 释放内存
        opts.log(TAG, "HTTP头部解析完成")
    else
        opts.log(TAG, "HTTP头部已解析，跳过解析步骤")
    end

    -- 如果状态码不是200/206，就不处理body了
    if not (opts.resp_code == 200 or opts.resp_code == 206) then
        return
    end

    -- 解析body
    -- 有Content-Length就好办
    if opts.resp.headers["Content-Length"] then
        opts.log(TAG, "有Content-Length", opts.resp.headers["Content-Length"])
        -- 解析出声明的body长度
        local declared = tonumber(opts.resp.headers["Content-Length"]) or 0
        local new_data = rx_data
        if opts.callback then
            opts.accumulated_body_len = (opts.accumulated_body_len or 0) + #new_data
            -- log.info(TAG, "累计已接收 body 总长度", opts.accumulated_body_len, "声明长度", declared)
            if opts.userdata then
                opts.callback(declared, #new_data, new_data, opts.userdata)
            else
                opts.callback(declared, #new_data, new_data)
            end
        end
        -- 仅当需要缓存时才追加
        if not opts.no_cache_body then
            opts.resp.body:copy(nil, rx_data)
            if opts.resp.body:used() >= declared then
                opts.resp.body:resize(declared)
            end
        end
    elseif opts.resp.headers["Transfer-Encoding"] == "chunked" or opts.resp.headers["transfer-encoding"] == "chunked" then
        -- 解析 chunked 编码：长度行（可含分号扩展）+ 数据 + CRLF，末块长度为0
        local function zbuff_find_from(buff, str, start_off)
            local used = buff:used()
            if used - start_off < #str then return end
            local maxoff = used - #str
            local tmp2 = zbuff.create(#str)
            tmp2:write(str)
            for i = start_off, maxoff, 1 do
                local ok = true
                for j = 0, #str - 1, 1 do
                    if buff[i+j] ~= tmp2[j] then ok = false; break end
                end
                if ok then return i end
            end
        end

        if not opts.chunk_buff then
            opts.chunk_buff = zbuff.create(1024)
        end
        -- 追加当前数据到chunk_buff
        opts.chunk_buff:copy(nil, rx_data)

        local chunk_pos = 0
        -- 循环解析chunk_buff中的chunk
        while true do
            chunk_pos = 0
            -- 查找chunk长度行的结束偏移量
            local line_end = zbuff_find_from(opts.chunk_buff, "\r\n", chunk_pos)
            if not line_end then
                opts.log(TAG, "尚未接收到完整的chunk长度行，等待后续数据")
                break
            end
            -- 解析chunk长度行
            local len_line = opts.chunk_buff:query(chunk_pos, line_end)
            local semi = len_line:find(";")
            local hex = semi and len_line:sub(1, semi - 1) or len_line
            local clen = tonumber(hex, 16)
            -- log.info(TAG, "当前chunk长度", clen)
            if not clen then
                opts.log(TAG, "非法的chunk长度值", #len_line, "内容:", len_line)
                break
            end
            chunk_pos = line_end + 2
            if clen == 0 then
                -- 末块：忽略后续 trailers
                opts.log(TAG, "末块：忽略后续 trailers")
                opts.chunk_buff = nil  -- 释放 buffer
                break
            end
            if chunk_pos + clen + 2 > opts.chunk_buff:used() then
                opts.log(TAG, "尚未接收到完整的chunk数据", "需要:", clen, "实际可用:", opts.chunk_buff:used() - chunk_pos - 2)
                break
            end
            -- 解析出单个chunk数据块中的数据
            local chunk_data = opts.chunk_buff:query(chunk_pos, clen)

            if opts.callback then
                -- 累计已接收 chunk 总长度
                opts.accumulated_cbody_len = (opts.accumulated_cbody_len or 0) + clen
                -- log.info(TAG, "累计已接收 cbody 总长度", opts.accumulated_cbody_len)
                if opts.userdata then
                    opts.callback(0, clen, chunk_data, opts.userdata)
                else
                    opts.callback(0, clen, chunk_data)
                end
            end

            -- 仅当需要缓存时才追加
            if not opts.no_cache_body and opts.resp.body then
                opts.resp.body:copy(nil, chunk_data)
            end
            -- 删除已处理的chunk数据
            opts.chunk_buff:del(0, chunk_pos + clen + 2)
        end
    end
end

-- socket 回调函数
local function http_socket_cb(opts, event)
    opts.log(TAG, "tcp.event", string.format("%08X", event))
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
        -- log.info(TAG, "socket.EVENT", "succ", succ, "data_len", data_len)
        -- log.info(TAG, "当前rx_buff长度", opts.rx_buff:used())
        if succ and data_len > 0 then
            -- 解析响应数据
            resp_parse(opts, data_len)
            -- 重置接收缓冲区指针
            opts.rx_buff:seek(0)
        elseif not succ then
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
    local fail_check = true
    local netc = socket.create(opts.adapter, function(sc, event)
        if opts.netc then
            return http_socket_cb(opts, event)
        end
    end)
    if not netc then
        log.error(TAG, "创建socket失败了!!!")
        return -102
    end
    opts.netc = netc
    opts.rx_buff = zbuff.create(1024)
    opts.topic = tostring(netc)
    socket.config(netc, nil, nil, opts.is_ssl, nil, nil, nil,
        opts.server_cert, opts.client_cert, opts.client_key, opts.client_password)
    if opts.debug_socket then
        socket.debug(netc, true)
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

    if opts.fota then
        opts.log(TAG, "fota模式，初始化fota")
        fota.init()
        local wait_count = 0
        while not fota.wait() do
            sys.wait(100)
            wait_count = wait_count + 1
            if wait_count > 100 then
                log.error(TAG, "fota.wait超时")
                return -108, "fota.wait超时"
            end
        end
        opts.log(TAG, "fota底层准备就绪")
    end

    opts.is_timeout = false
    local timer_id = sys.timerStart(function()
        log.warn(TAG, "HTTP请求超时了!!!")
        opts.is_timeout = true
    end, opts.timeout * 1000)
    
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
    local fbuf = nil
    if (opts.mp and #opts.mp > 0) or opts.bodyfile or (opts.body and type(opts.body) == "userdata" and opts.body:used() > 4*1024) then
        if opts.upload_file_buff then
            fbuf = opts.upload_file_buff
        else
            if hmeta and hmeta.chip and hmeta.chip() == "EC718HM" then
                fbuf = zbuff.create(1024 * 128, 0, zbuff.HEAP_PSRAM) -- 718hm可以128k的,放手去用
            elseif hmeta and hmeta.chip and hmeta.chip() == "EC718PM" then
                fbuf = zbuff.create(1024 * 64, 0, zbuff.HEAP_PSRAM) -- Air8101/7258可以128k的,放手去用
            elseif hmeta and hmeta.chip and hmeta.chip() == "BK7258" then
                fbuf = zbuff.create(1024 * 128, 0, zbuff.HEAP_PSRAM) -- Air8101/7258可以128k的,放手去用
            else
                fbuf = zbuff.create(1024 * 24, 0, zbuff.HEAP_PSRAM) -- 其他模组就是小的用吧
            end
        end
        if fbuf == nil then
            fbuf = zbuff.create(1024 * 8, 0, zbuff.HEAP_PSRAM) -- 创建一个小的,作为防御
            if fbuf == nil then
                fbuf = zbuff.create(1500, 0, zbuff.HEAP_PSRAM) -- 创建一个最小的,最后防御
            end
        end
        opts.log(TAG, "上传使用缓冲区", fbuf:len())
    end
    
    if opts.mp and #opts.mp > 0 then
        opts.log(TAG, "执行multipart上传模式")
        for k, v in ipairs(opts.mp) do
            fail_check = socket.tx(netc, v[2])
            write_counter = write_counter + #v[2]
            if v[3] == "file" then
                -- log.info("写入文件数据头", v[2])
                local fd = io.open(v[1], "rb")
                -- log.info("写入文件数据", v[1])
                if fd then
                    local total = 0
                    while not opts.is_closed do
                        fbuf:seek(0)
                        local ok, flen = fd:fill(fbuf)
                        if not ok or flen <= 0 then
                            break
                        end
                        fbuf:seek(flen)
                        opts.log(TAG, "写入文件数据", "长度", flen, "总计", total)
                        if socket.tx(netc, fbuf) == false then
                            log.warn(TAG, "socket.tx返回错误了, 传送失败!!!")
                            fail_check = false
                            break
                        end
                        write_counter = write_counter + flen
                        -- 注意, 这里要等待TX_OK事件
                        sys.waitUntil(opts.topic, 1000)
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
        if opts.body_len and opts.body_len > 0 and write_counter ~= opts.body_len then
            opts.log(TAG, "multipart长度不一致", "期望", opts.body_len, "实际", write_counter)
        end
    elseif opts.bodyfile then
        local fd = io.open(opts.bodyfile, "rb")
        -- log.info("写入文件数据", v[1])
        if fd then
            local total = 0
            while not opts.is_closed do
                fbuf:seek(0)
                local ok, flen = fd:fill(fbuf)
                if not ok or flen <= 0 then
                    break
                end
                fbuf:seek(flen)
                total = total + flen
                opts.log(TAG, "写入文件数据", "长度", flen, "总计", total)
                if socket.tx(netc, fbuf) == false then
                    log.warn(TAG, "socket.tx返回错误了, 传送失败!!!")
                    fail_check = false
                    break
                end
                write_counter = write_counter + flen
                -- 注意, 这里要等待TX_OK事件
                sys.waitUntil(opts.topic, 1000)
            end
            fd:close()
        end
    elseif opts.body then
        if type(opts.body) == "string" and #opts.body > 0 then
            socket.tx(netc, opts.body)
            write_counter = write_counter + #opts.body
        elseif type(opts.body) == "userdata" then
            opts.log(TAG, "使用zbuff上传数据", opts.body:used())
            write_counter = write_counter + opts.body:used()
            if opts.body:used() <= 4*1024 then
                fail_check = socket.tx(netc, opts.body)
            else
                local offset = 0
                local tmpbuff = opts.body
                local tsize = tmpbuff:used()
                while offset < tsize do
                    -- TODO 应该使用fbuf来做缓冲区，而不是toStr
                    opts.log(TAG, "body(zbuff)分段写入", offset, tsize)
                    fbuf:seek(0)
                    if tsize - offset > fbuf:len() then
                        fbuf:copy(0, tmpbuff, offset, fbuf:len())
                        fbuf:seek(fbuf:len())
                        if socket.tx(netc, fbuf) == false then
                            log.warn(TAG, "socket.tx返回错误了, 传送失败!!!")
                            fail_check = false
                            break
                        end
                        offset = offset + fbuf:len()
                        sys.waitUntil(opts.topic, 1000)
                    else
                        fbuf:copy(0, tmpbuff, offset, tsize - offset)
                        fbuf:seek(tsize - offset)
                        fail_check = socket.tx(netc, fbuf)
                        break
                    end
                end
            end
        end
    end
    -- log.info("写入长度", "期望", opts.body_len, "实际", write_counter)
    -- log.info("hex", rbody)
    if not fail_check then
        log.warn(TAG, "发送数据失败, 终止请求")
        opts.resp_code = -199
        return
    end

    -- 处理响应信息
    while not opts.is_closed and not opts.is_timeout do
        sys.waitUntil(opts.topic, 100)
    end
    if timer_id and not opts.is_timeout then
        sys.timerStop(timer_id)
        timer_id = nil
    end
    if opts.is_timeout then
        log.warn(TAG, "HTTP请求超时")
        opts.resp_code = -1
    end
    log.info(TAG, "服务器已完成响应")

    -- 清空rx_buff
    opts.rx_buff = nil
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
    files = {},   -- 可选,键值对的形式,文件上传,若存在本参数,会强制以multipart/form-data形式上传
    forms = {},   -- 可选,键值对的形式,表单参数,若存在本参数,如果不存在files,按application/x-www-form-urlencoded上传
    body  = "abc=123",-- 可选,自定义body参数, 字符串/zbuff/table均可, 但不能与files和forms同时存在
    debug = false,    -- 可选,打开调试日志,默认false
    try_ipv6 = false, -- 可选,是否优先尝试ipv6地址,默认是false
    adapter = nil,    -- 可选,网络适配器编号, 默认是自动选
    timeout = 30,     -- 可选,读取服务器响应的超时时间,单位秒,默认30
    bodyfile = "xxx", -- 可选,直接把文件内容作为body上传, 优先级高于body参数
    upload_file_buff = zbuff.create(1024*64), -- 可选,上传时使用的缓冲区,默认会根据型号创建一个buff
    server_cert = nil, -- 可选,HTTPS服务器证书内容,PEM格式字符串
    client_cert = nil, -- 可选,HTTPS客户端证书内容,PEM格式字符串
    client_key  = nil, -- 可选,HTTPS客户端私钥内容,PEM格式字符串
    client_password = nil, -- 可选,HTTPS客户端私钥密码,字符串
    callback = nil, -- 可选,回调函数,用于接收数据,支持Content-Length和chunked两种模式，包含以下参数
                        -- total_len: number类型，Content-Length模式时表示响应体的总长度，chunked模式时表示0
                        -- recv_len: number类型，Content-Length模式时表示当前接收的字节数，chunked模式时表示单个chunk数据块长度
                        -- recv_data: string类型，Content-Length模式时表示当前接收的数据内容，chunked模式时表示单个chunk数据块内容（不包含chunk长度和\r\n）
                        -- userdata: string类型，表示用户传入的自定义回调参数（在请求时指定）
    userdata = nil, -- 可选,用户自定义参数,会原封不动的传入回调函数中
    is_big_file = false, -- 可选,是否为大文件下载模式,默认false，开启后，返回值中的resp.body参数会被设置为nil
                        -- 同时强制要求设置callback参数, 用于接收数据
    dst = nil, -- 可选,文件下载路径，设置后会自动将响应内容写入该文件
    fota = false, -- 可选,是否为fota升级模式，设置为true会使用fota系统功能进行升级
                  -- fota模式下resp会额外返回: fota_success(boolean)是否成功, fota_msg(string)结果描述
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
-- 情况2, code < 0 时, resp会是个错误信息字符串

-- 对upload_file_buff参数的说明
--   1. 如果上传的文件比较大,建议传入这个参数,避免每次都创建和销毁缓冲区
--   2. 如果不传入这个参数,本库会根据不同的模组型号创建一个合适的缓冲区
--   3. 多个同时执行的httpplus请求,不可以共用同一个缓冲区

-- 文件下载示例
local code, resp = httpplus.request({
    url = "http://example.com/file.bin",
    dst = "/sdcard/file.bin",
    callback = function(total, recv, data)
        log.info("下载进度", recv, "/", total)
    end
})

-- fota升级示例
local code, resp = httpplus.request({
    url = "http://example.com/fota.bin",
    fota = true,
    callback = function(total, recv, data)
        log.info("fota进度", recv, "/", total)
    end
})
-- fota升级结果判断
if code == 200 and resp.fota_success then
    log.info("fota升级成功，3秒后重启")
    sys.wait(3000)
    rtos.reboot()
else
    log.error("fota升级失败", resp.fota_msg)
end
]]
function httpplus.request(opts)
    -- 参数解析
    local ret = http_opts_parse(opts)
    if ret then
        return ret
    end

    -- 执行请求
    local ok, err = pcall(http_exec, opts)
    
    -- 清理资源
    if opts.write_fd then
        opts.write_fd:close()
        opts.write_fd = nil
    end

    if opts.fota and ok and (opts.resp_code == 200 or opts.resp_code == 206) then
        if opts.fota_error then
            log.error(TAG, "fota.run写入失败，升级取消")
            fota.finish(false)
            if opts.resp then
                opts.resp.fota_success = false
                opts.resp.fota_msg = "fota.run写入失败"
            end
        else
            local succ, fotaDone = fota.isDone()
            if succ and fotaDone then
                log.info(TAG, "fota升级包接收完成")
                fota.finish(true)
                if opts.resp then
                    opts.resp.fota_success = true
                    opts.resp.fota_msg = "升级成功，请重启设备"
                end
            else
                log.error(TAG, "fota升级失败", succ, fotaDone)
                fota.finish(false)
                if opts.resp then
                    opts.resp.fota_success = false
                    opts.resp.fota_msg = "fota.isDone检查失败"
                end
            end
        end
    end
    
    if opts.netc then
        -- 清理连接
        if not opts.is_closed then
            socket.close(opts.netc)
        end
        socket.release(opts.netc)
        opts.netc = nil
    end
    
    -- 处理响应或错误
    if not ok then
        log.error(TAG, err)
        return -199, err
    end

    -- 如果是 is_big_file 模式，resp.body 应为 nil 或空
    if opts.no_cache_body then
        -- 可选：显式设置 body 为 nil，避免误解
        if opts.resp then
            opts.resp.body = nil
        end
    end
    
    return opts.resp_code, opts.resp
end

return httpplus
