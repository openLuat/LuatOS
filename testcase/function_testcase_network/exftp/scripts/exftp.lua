--[[
@module  exftp
@summary FTP客户端库
@version 1.0
@date    2025.12.18
@author  刘斌
@tag    LUAT_USE_NETWORK
]]

local exftp = {}
local TAG = "exftp"

-- FTP响应码常量
local FTP_CODE = {
    SERVICE_READY = 220,        -- 服务就绪
    USER_OK = 331,              -- 用户名正确，需要密码
    LOGIN_OK = 230,              -- 登录成功
    ENTER_PASSIVE = 227,         -- 进入被动模式
    FILE_ACTION_OK = 250,        -- 文件操作成功
    PATHNAME_CREATED = 257,      -- 路径名已创建
    DATA_CONN_OPEN = 150,        -- 数据连接已打开
    DATA_CONN_ALREADY_OPEN = 125, -- 数据连接已打开，传输开始
    TRANSFER_COMPLETE = 226,     -- 传输完成
    CLOSING_DATA = 226,         -- 关闭数据连接
}

-- 状态常量
local STATE = {
    DISCONNECTED = 0,   -- 未连接
    CONNECTED = 1,      -- 已连接但未认证
    AUTHENTICATED = 2,  -- 已认证
    TRANSFERRING = 3,   -- 正在传输
}

-- 创建FTP客户端实例
-- @param adapter 网络适配器，nil表示使用默认
-- @param host FTP服务器地址
-- @param port FTP服务器端口，默认21
-- @return ftp客户端实例
function exftp.create(adapter, host, port)
    if not host then
        log.error(TAG, "host不能为空")
        return nil
    end

    port = port or 21

    local self = {
        adapter = adapter,
        host = host,
        port = port,
        state = STATE.DISCONNECTED,
        cmd_netc = nil,      -- 命令通道socket
        data_netc = nil,     -- 数据通道socket
        cmd_rx_buff = nil,   -- 命令通道接收缓冲区
        data_rx_buff = nil,  -- 数据通道接收缓冲区
        topic = nil,         -- 事件通知topic
        username = nil,
        password = nil,
        last_response = nil, -- 最后一次响应
        last_code = nil,     -- 最后一次响应码
        debug_on = false,    -- 调试开关
        data_closed = false, -- 数据通道是否已关闭
    }

    -- 创建命令通道socket
    self.cmd_rx_buff = zbuff.create(1024)

    local function cmd_socket_cb(netc, event)
        if not self.cmd_netc then
            return
        end

        if event == socket.ON_LINE then
            -- TCP连接建立（参考httpplus，直接publish topic）
            sys.publish(self.topic)
        elseif event == socket.TX_OK then
            -- 数据发送完成
            sys.publish(self.topic)
        elseif event == socket.EVENT then
            -- 收到数据
            local ok = socket.rx(netc, self.cmd_rx_buff)
            if ok and self.cmd_rx_buff:used() > 0 then
                sys.publish(self.topic)
            end
        elseif event == socket.CLOSED then
            sys.publish(self.topic)
        end
    end

    -- 创建命令通道socket，如果指定适配器无效，尝试使用默认适配器
    self.cmd_netc = socket.create(self.adapter, cmd_socket_cb)
    if not self.cmd_netc then
        log.error(TAG, "创建命令通道socket失败")
        return nil
    end

    -- 使用socket对象作为topic（参考httpplus）
    self.topic = tostring(self.cmd_netc)

    socket.config(self.cmd_netc)

    -- 连接命令通道
    if not socket.connect(self.cmd_netc, self.host, self.port) then
        log.error(TAG, "连接FTP服务器失败")
        socket.release(self.cmd_netc)
        return nil
    end

    -- 设置元表
    setmetatable(self, {__index = exftp})

    -- 等待连接建立（参考httpplus）
    local ret = sys.waitUntil(self.topic, 5000)
    if ret == false then
        log.error(TAG, "等待连接建立超时")
        socket.close(self.cmd_netc)
        socket.release(self.cmd_netc)
        return nil
    end

    -- 等待服务器发送服务就绪响应，FTP服务器在连接建立后会立即发送220响应
    ret = sys.waitUntil(self.topic, 5000)
    if ret == false then
        log.error(TAG, "等待服务就绪响应超时")
        socket.close(self.cmd_netc)
        socket.release(self.cmd_netc)
        return nil
    end

    -- 检查是否有数据
    if not self.cmd_rx_buff or self.cmd_rx_buff:used() == 0 then
        log.error(TAG, "未收到服务就绪响应数据")
        socket.close(self.cmd_netc)
        socket.release(self.cmd_netc)
        return nil
    end

    -- 解析初始响应
    local code, msg = self:_parse_response()
    if not code or code ~= FTP_CODE.SERVICE_READY then
        log.error(TAG, "FTP服务未就绪", code, msg)
        socket.close(self.cmd_netc)
        socket.release(self.cmd_netc)
        return nil
    end

    self.state = STATE.CONNECTED

    return self
end

-- 解析FTP响应
-- @return code 响应码，nil表示解析失败
-- @return msg
function exftp:_parse_response()
    if not self.cmd_rx_buff or self.cmd_rx_buff:used() == 0 then
        return nil
    end

    local response = self.cmd_rx_buff:query()
    if not response or #response < 3 then
        return nil
    end

    -- FTP响应格式: "220 Service ready\r\n" 或 "150 Opening data connection\r\n"
    local lines = {}
    for line in response:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end

    if #lines == 0 then
        return nil
    end

    -- 从后往前查找，找到第一个FTP响应码行
    local last_line = nil
    for i = #lines, 1, -1 do
        local line = lines[i]
        if #line >= 3 then
            local code_str = line:sub(1, 3)
            if tonumber(code_str) then
                last_line = line
                break
            end
        end
    end

    if not last_line then
        return nil
    end

    local code_str = last_line:sub(1, 3)
    local code = tonumber(code_str)
    if not code then
        return nil
    end

    -- 提取消息部分
    local msg = last_line:match("^%d+%s+(.+)")
    if not msg then
        msg = ""
    end

    self.last_code = code
    self.last_response = response

    -- 清空缓冲区（已处理完）
    self.cmd_rx_buff:del()

    return code, msg
end

-- 发送FTP命令并等待响应
-- @param cmd FTP命令
-- @param timeout 超时时间（毫秒），默认5000
-- @return code 响应码，nil表示失败
function exftp:_send_cmd(cmd, timeout)
    timeout = timeout or 5000

    -- 发送命令（FTP命令必须以\r\n结尾）
    local tx_ok = socket.tx(self.cmd_netc, cmd .. "\r\n")
    if tx_ok == false then
        log.error(TAG, "发送命令失败", cmd)
        return nil
    end

    -- 等待数据发送完成（TX_OK事件）
    local ret = sys.waitUntil(self.topic, timeout)
    if ret == false then
        log.error(TAG, "等待命令发送完成超时", cmd)
        return nil
    end

    -- 等待服务器响应（EVENT事件，收到数据）
    ret = sys.waitUntil(self.topic, timeout)
    if ret == false then
        log.error(TAG, "等待响应超时", cmd)
        return nil
    end

    -- 检查是否有响应数据
    if not self.cmd_rx_buff or self.cmd_rx_buff:used() == 0 then
        log.error(TAG, "未收到响应数据", cmd)
        return nil
    end

    -- 解析响应
    return self:_parse_response()
end

-- 进入被动模式（PASV）
-- @return ip 数据通道IP地址
-- @return port 数据通道端口
function exftp:_enter_pasv()
    local code, msg = self:_send_cmd("PASV", 5000)
    if not code or code ~= FTP_CODE.ENTER_PASSIVE then
        log.error(TAG, "PASV命令失败", "code:", code, "msg:", msg, "完整响应:", self.last_response)
        return nil, nil
    end

    -- 解析PASV响应: "227 Entering Passive Mode (192,168,1,100,123,45)"
    local pasv_info = msg:match("%(([^)]+)%)")
    if not pasv_info then
        log.error(TAG, "PASV响应格式错误", msg)
        return nil, nil
    end

    local parts = {}
    for part in pasv_info:gmatch("([^,]+)") do
        table.insert(parts, tonumber(part:match("%d+")))
    end

    if #parts ~= 6 then
        log.error(TAG, "PASV响应解析失败", pasv_info)
        return nil, nil
    end

    local ip = string.format("%d.%d.%d.%d", parts[1], parts[2], parts[3], parts[4])
    local port = parts[5] * 256 + parts[6]

    -- -- 检查IP地址是否可路由
    -- if ip:match("^172%.") or
    --     ip:match("^192%.") or
    --     ip:match("^10%.") or
    --     ip == "127.0.0.1" or
    --     ip:match("^169%.254%.") or
    --     ip:match("^0%.") then
    --     -- 使用服务器地址代替
    --     if self.debug_on then
    --         log.debug(TAG, "PASV返回不可路由地址，使用服务器地址", ip, self.host)
    --     end
    --     ip = self.host
    -- end

    if self.debug_on then
        log.debug(TAG, "PASV成功", ip, port)
    end

    return ip, port
end

-- 建立数据通道连接
-- @return true成功，false失败
function exftp:_connect_data_channel()
    -- 如果已有数据通道，先关闭
    if self.data_netc then
        socket.close(self.data_netc)
        socket.release(self.data_netc)
        self.data_netc = nil
    end

    -- 进入被动模式
    local data_ip, data_port = self:_enter_pasv()
    if not data_ip or not data_port then
        return false
    end

    -- 创建数据通道socket
    self.data_rx_buff = zbuff.create(2048)
    self.data_closed = false  -- 重置关闭标志

    local function data_socket_cb(netc, event)
        if not self.data_netc then
            return
        end

        -- 使用数据通道自己的topic（参考httpplus）
        local data_topic = self.data_topic or tostring(self.data_netc)

        if event == socket.ON_LINE then
            -- TCP连接建立（参考httpplus，直接publish topic）
            sys.publish(data_topic)
        elseif event == socket.TX_OK then
            -- 数据发送完成
            sys.publish(data_topic)
        elseif event == socket.EVENT then
            -- 收到数据
            local ok = socket.rx(netc, self.data_rx_buff)
            if not ok or (self.data_rx_buff and self.data_rx_buff:used() == 0) then
                -- 连接关闭或没有数据
                if not self.data_closed then
                    self.data_closed = true
                    if self.debug_on then
                        log.debug(TAG, "数据通道关闭")
                    end
                end
            end
            sys.publish(data_topic)
        elseif event == socket.CLOSED then
            if not self.data_closed then
                self.data_closed = true
                if self.debug_on then
                    log.debug(TAG, "数据通道关闭")
                end
            end
            sys.publish(data_topic)
        end
    end

    -- 创建数据通道socket，如果指定适配器无效，尝试使用默认适配器
    self.data_netc = socket.create(self.adapter, data_socket_cb)
    if not self.data_netc and self.adapter ~= nil then
        -- 如果指定适配器失败，尝试使用默认适配器（兼容PC模拟器）
        log.warn(TAG, "数据通道使用指定适配器失败，尝试使用默认适配器", self.adapter)
        self.data_netc = socket.create(nil, data_socket_cb)
    end
    if not self.data_netc then
        log.error(TAG, "创建数据通道socket失败")
        return false
    end

    -- 使用数据通道socket对象作为topic（参考httpplus）
    self.data_topic = tostring(self.data_netc)

    socket.config(self.data_netc)

    -- 连接数据通道
    if not socket.connect(self.data_netc, data_ip, data_port) then
        log.error(TAG, "连接数据通道失败", data_ip, data_port)
        socket.release(self.data_netc)
        self.data_netc = nil
        return false
    end

    -- 等待连接建立（参考httpplus）
    local ret = sys.waitUntil(self.data_topic, 5000)
    if ret == false then
        log.error(TAG, "数据通道连接超时")
        socket.close(self.data_netc)
        socket.release(self.data_netc)
        self.data_netc = nil
        return false
    end

    if self.debug_on then
        log.debug(TAG, "数据通道连接成功")
    end

    return true
end

-- 关闭数据通道
function exftp:_close_data_channel()
    self.data_closed = true  -- 标记为已关闭
    if self.data_netc then
        socket.close(self.data_netc)
        socket.release(self.data_netc)
        self.data_netc = nil
    end
    if self.data_rx_buff then
        self.data_rx_buff = nil
    end
end

-- 清理传输错误（关闭数据通道、关闭文件、恢复状态）
-- @param fd 文件句柄，可为nil
function exftp:_cleanup_transfer_error(fd)
    self:_close_data_channel()
    if fd then
        fd:close()
    end
    self.state = STATE.AUTHENTICATED
end

-- 检查传输命令响应码是否有效
-- @param code 响应码
-- @return true有效，false无效
function exftp:_is_valid_transfer_response(code)
    return code == FTP_CODE.DATA_CONN_OPEN or
           code == FTP_CODE.DATA_CONN_ALREADY_OPEN or
           code == FTP_CODE.FILE_ACTION_OK
end

-- 等待传输完成响应（226）
-- @return true收到传输完成响应，false未收到
function exftp:_wait_transfer_complete()
    local has_226 = false
    if self.cmd_rx_buff and self.cmd_rx_buff:used() > 0 then
        local code, msg = self:_parse_response()
        if code and code == FTP_CODE.TRANSFER_COMPLETE then
            has_226 = true
            if self.debug_on then
                log.debug(TAG, "传输完成", msg)
            end
        end
    end

    -- 如果没有226响应，等待接收
    if not has_226 then
        local ret = sys.waitUntil(self.topic, 10000)
        if ret == false then
            log.warn(TAG, "等待传输完成响应超时")
        else
            -- 检查是否有226响应
            if self.cmd_rx_buff and self.cmd_rx_buff:used() > 0 then
                local code, msg = self:_parse_response()
                if code and code == FTP_CODE.TRANSFER_COMPLETE then
                    has_226 = true
                    if self.debug_on then
                        log.debug(TAG, "传输完成", msg)
                    end
                end
            end
        end
    end

    return has_226
end

-- 认证
-- @param username 用户名
-- @param password 密码
-- @return true成功，false失败
function exftp:auth(username, password)
    if self.state ~= STATE.CONNECTED then
        log.error(TAG, "状态错误，无法认证", self.state)
        return false
    end

    self.username = username
    self.password = password

    -- 发送USER命令
    local code, msg = self:_send_cmd("USER " .. username, 5000)
    if not code then
        return false
    end

    if code ~= FTP_CODE.USER_OK and code ~= FTP_CODE.LOGIN_OK then
        log.error(TAG, "USER命令失败", code, msg)
        return false
    end

    -- 如果已经是LOGIN_OK，说明不需要密码
    if code == FTP_CODE.LOGIN_OK then
        self.state = STATE.AUTHENTICATED
        return true
    end

    -- 发送PASS命令
    code, msg = self:_send_cmd("PASS " .. password, 5000)
    if not code or code ~= FTP_CODE.LOGIN_OK then
        log.error(TAG, "PASS命令失败", code, msg)
        return false
    end

    self.state = STATE.AUTHENTICATED

    return true
end

-- 上传文件
-- @param local_path 本地文件路径
-- @param remote_path 远程文件路径
-- @param opts 选项，{timeout=超时时间(毫秒), buffer_size=缓冲区大小(字节)}
-- @return true成功，false失败
function exftp:upload(local_path, remote_path, opts)
    opts = opts or {}
    local timeout = opts.timeout or 5 * 60 * 1000  -- 默认5分钟
    local buffer_size = opts.buffer_size  -- 用户指定的缓冲区大小

    if self.state ~= STATE.AUTHENTICATED then
        return false
    end

    -- 检查本地文件
    local fd = io.open(local_path, "rb")
    if not fd then
        return false
    end

    local file_size = io.fileSize(local_path)
    if not file_size or file_size == 0 then
        fd:close()
        return false
    end

    if self.debug_on then
        log.debug(TAG, "开始上传文件", local_path, "大小:", file_size, "字节")
    end

    -- 建立数据通道
    if not self:_connect_data_channel() then
        fd:close()
        return false
    end

    self.state = STATE.TRANSFERRING

    -- 发送STOR命令
    local code, msg = self:_send_cmd("STOR " .. remote_path, 10000)
    if not code then
        self:_cleanup_transfer_error(fd)
        return false
    end

    if not self:_is_valid_transfer_response(code) then
        self:_cleanup_transfer_error(fd)
        return false
    end

    -- 创建上传缓冲区（参考httpplus）
    if not buffer_size then
        buffer_size = 1024 * 128
    end
    local fbuf = zbuff.create(buffer_size, 0, zbuff.HEAP_PSRAM)

    if not fbuf then
        fbuf = zbuff.create(1024 * 64, 0, zbuff.HEAP_PSRAM)  -- 默认64KB，增大缓冲区
    end

    if not fbuf then
        fbuf = zbuff.create(1024 * 24, 0, zbuff.HEAP_PSRAM)  -- 降级到24KB
    end

    if not fbuf then
        fbuf = zbuff.create(1024 * 8, 0, zbuff.HEAP_PSRAM)   -- 降级到8KB
    end

    if not fbuf then
        self:_cleanup_transfer_error(fd)
        return false
    end

    if self.debug_on then
        log.debug(TAG, "上传缓冲区大小", fbuf:len())
    end

    -- 分块上传（并行操作）
    local total_sent = 0
    local start_time = os.time()
    local is_closed = false
    local upload_completed = false

    -- 预读第一个数据块
    fbuf:seek(0)
    local ok, current_flen = fd:fill(fbuf)
    if not ok or current_flen <= 0 then
        upload_completed = true
    else
        fbuf:seek(current_flen)
    end

    while not is_closed and not upload_completed do

        -- 发送当前缓冲区的数据
        if current_flen > 0 then
            local tx_ok = socket.tx(self.data_netc, fbuf)
            if tx_ok == false then
                log.error(TAG, "发送数据失败")
                is_closed = true
                break
            end
            total_sent = total_sent + current_flen

            -- 显示进度
            if self.debug_on and total_sent % (1024 * 1024) == 0 then
                log.debug(TAG, "已上传", total_sent, "/", file_size)
            end
        end

        -- 并行优化：发送的同时预读下一个数据块
        fbuf:seek(0)
        local ok, next_flen = fd:fill(fbuf)
        if not ok or next_flen <= 0 then
            next_flen = 0  -- 没有更多数据
            if current_flen == 0 then
                upload_completed = true
                break
            end
        else
            fbuf:seek(next_flen)
        end

        -- 等待当前发送完成
        local ret = sys.waitUntil(self.data_topic, 300)
        if ret == false then
            log.warn(TAG, "等待TX_OK超时，继续发送")
        end

        -- 切换到下一个数据块
        current_flen = next_flen

        -- 检查超时
        if os.time() - start_time > timeout / 1000 then
            log.error(TAG, "上传超时")
            is_closed = true
            break
        end
    end

    fd:close()

    -- 关闭数据通道（关闭后服务器会通过命令通道发送226响应）
    self:_close_data_channel()

    -- 等待传输完成响应
    local transfer_success = self:_wait_transfer_complete()

    self.state = STATE.AUTHENTICATED

    -- 判断上传是否成功
    local success = (not is_closed and total_sent == file_size) or transfer_success

    if success then
        if self.debug_on then
            log.debug(TAG, "上传成功", total_sent, "/", file_size)
        end
        return true
    else
        log.error(TAG, "上传失败", "is_closed:", is_closed, "total_sent:", total_sent, "file_size:", file_size, "transfer_success:", transfer_success)
        return false
    end
end

-- 下载文件
-- @param remote_path 远程文件路径
-- @param local_path 本地文件路径
-- @param opts 选项，{timeout=超时时间(毫秒)}
-- @return true成功，false失败
function exftp:download(remote_path, local_path, opts)
    opts = opts or {}
    local timeout = opts.timeout or 5 * 60 * 1000  -- 默认5分钟

    if self.state ~= STATE.AUTHENTICATED then
        return false
    end

    -- 先获取远程文件大小（使用SIZE命令）
    local code, msg = self:_send_cmd("SIZE " .. remote_path, 5000)
    if not code or code ~= 213 then
        log.error(TAG, "获取远程文件大小失败", code, msg)
        return false
    end

    -- SIZE命令成功，响应格式：213 <size>
    local remote_file_size = tonumber(msg:match("%d+"))
    if not remote_file_size then
        log.error(TAG, "解析远程文件大小失败", msg)
        return false
    end

    if self.debug_on then
        log.debug(TAG, "远程文件大小", remote_file_size, "字节")
    end

    -- 建立数据通道
    if not self:_connect_data_channel() then
        return false
    end

    self.state = STATE.TRANSFERRING

    -- 发送RETR命令
    local code, msg = self:_send_cmd("RETR " .. remote_path, 10000)
    if not code then
        self:_cleanup_transfer_error()
        return false
    end

    if code ~= FTP_CODE.DATA_CONN_OPEN and
       code ~= FTP_CODE.DATA_CONN_ALREADY_OPEN and
       code ~= FTP_CODE.FILE_ACTION_OK then
        self:_cleanup_transfer_error()
        return false
    end

    -- 创建本地文件
    local fd = io.open(local_path, "w+b")
    if not fd then
        self:_cleanup_transfer_error()
        return false
    end

    -- 接收数据并写入文件（流式写入，避免大文件占用内存）
    local total_received = 0
    local start_time = os.time()
    local is_closed = false
    local last_data_time = os.time()

    while not is_closed and not self.data_closed do
        -- 先尝试读取已有数据
        if self.data_rx_buff and self.data_rx_buff:used() > 0 then
            local data = self.data_rx_buff:query()
            fd:write(data)
            total_received = total_received + #data
            self.data_rx_buff:del()  -- 清空缓冲区
            last_data_time = os.time()

            if self.debug_on and total_received % (1024 * 100) == 0 then
                log.debug(TAG, "已下载", total_received, "/", remote_file_size)
            end
        end

        -- 检查是否已接收完所有数据
        if total_received >= remote_file_size then
            if self.debug_on then
                log.debug(TAG, "已接收完所有数据", total_received, "/", remote_file_size)
            end
            -- 延时100ms后主动断开数据通道
            sys.wait(100)
            self:_close_data_channel()
            break
        end

        -- 等待数据或事件（使用数据通道的topic）
        local ret = sys.waitUntil(self.data_topic, 1000)
        if ret == false then
            log.warn(TAG, "等待数据超时")
        else
            -- 收到事件（可能是数据到达或连接关闭）
            -- 检查缓冲区是否有数据
            if self.data_rx_buff and self.data_rx_buff:used() > 0 then
                last_data_time = os.time()
            end
        end

        -- 检查超时
        if os.time() - start_time > timeout / 1000 then
            log.error(TAG, "下载超时")
            is_closed = true
            break
        end
    end

    -- 最后再读取一次可能剩余的数据
    if self.data_rx_buff and self.data_rx_buff:used() > 0 then
        local data = self.data_rx_buff:query()
        fd:write(data)
        total_received = total_received + #data
        self.data_rx_buff:del()
    end

    fd:close()

    -- 如果数据通道还未关闭，关闭它（关闭后服务器会通过命令通道发送226响应）
    if not self.data_closed then
        self:_close_data_channel()
    end

    -- 等待传输完成响应（已通过文件大小判断完成，可能已经有226响应了）
    if self.cmd_rx_buff and self.cmd_rx_buff:used() > 0 then
        local saved_data = self.cmd_rx_buff:query()
        if saved_data and saved_data:find("226") then
            -- 已有226响应，直接解析
            self:_parse_response()
            if self.debug_on then
                log.debug(TAG, "已检测到226响应，无需等待")
            end
        else
            -- 没有226响应，等待接收
            self:_wait_transfer_complete()
        end
    else
        -- 缓冲区为空，等待接收
        self:_wait_transfer_complete()
    end

    self.state = STATE.AUTHENTICATED

    if self.debug_on then
        log.debug(TAG, "下载完成", total_received, remote_file_size and ("/" .. remote_file_size) or "")
    end

    return true
end

-- 切换工作目录
-- @param path 目标目录路径（绝对路径或相对路径）
-- @return true成功，false失败
function exftp:chdir(path)
    if self.state ~= STATE.AUTHENTICATED then
        return false
    end

    local code, msg = self:_send_cmd("CWD " .. path, 5000)
    if not code then
        return false
    end

    if code ~= FTP_CODE.FILE_ACTION_OK then
        return false
    end

    return true
end

-- 获取当前工作目录
-- @return true成功，false失败
-- @return path 当前目录路径
function exftp:pwd()
    if self.state ~= STATE.AUTHENTICATED then
        return false
    end

    local code, msg = self:_send_cmd("PWD", 5000)
    if not code then
        return false, nil
    end

    -- PWD响应格式: "257 "/path/to/dir" is current directory"
    if code == 257 then
        -- 提取路径（可能在引号中）
        local path = msg:match('"([^"]+)"') or msg:match("'([^']+)'") or msg:match("%s+([^%s]+)")
        if path then
            if self.debug_on then
                log.debug(TAG, "当前目录", path)
            end
            return true, path
        end
    end

    return false, nil
end

-- 返回上一级目录
-- @return true成功，false失败
function exftp:cdup()
    if self.state ~= STATE.AUTHENTICATED then
        return false
    end

    local code, msg = self:_send_cmd("CDUP", 5000)
    if not code then
        return false
    end

    if code ~= FTP_CODE.FILE_ACTION_OK then
        return false
    end

    return true
end

-- 设置调试开关
-- @param onoff true开启，false关闭
function exftp:debug(onoff)
    self.debug_on = onoff or false
    if self.cmd_netc then
        socket.debug(self.cmd_netc, onoff)
    end
    if self.data_netc then
        socket.debug(self.data_netc, onoff)
    end
end

-- 关闭连接
function exftp:close()
    self:_close_data_channel()

    if self.cmd_netc then
        socket.close(self.cmd_netc)
        socket.release(self.cmd_netc)
        self.cmd_netc = nil
    end

    if self.cmd_rx_buff then
        self.cmd_rx_buff = nil
    end

    self.state = STATE.DISCONNECTED

end

return exftp

