-- 必须定义的全局变量（LuatOS框架要求）
PROJECT = "socket_demo"
VERSION = "1.0.0"

-- 定义全局网络控制块
local ctrl = nil
local maintaskname = "MAIN_TASK"

-- 网络初始化函数
local function network_init()
    ctrl = socket.create(nil, maintaskname)
    if not ctrl then
        log.error("socket", "create failed")
        return false
    end

    -- 等待网络就绪（轮询检测）
    while not socket.linkup(ctrl) do
        log.info("network", "waiting connection...")
        sys.wait(2000)
    end
    return true
end

local function send_data(data)
    local succ, sent = socket.tx(ctrl, data)
    if succ and sent == #data then
        log.info("socket", "sent", data)
        return true
    else
        log.error("socket.send", "failed", sent)
        return false
    end
end

-- 主任务函数
local function main_task()
    if not network_init() then return end

    -- 连接服务器（同步方式）
    local succ, connected = socket.connect(ctrl, "netlab.luatos.com", 40123)
    if not succ then
        log.error("socket.connect", "failed")
        socket.close(ctrl)
        return
    end

    -- 连接状态检测
    if not connected then
        log.warn("socket", "waiting connection...")
        repeat
            sys.wait(1000)
            local _, state = socket.status(ctrl)
        until state == socket.ON_LINE
    end

    -- 主循环
    while true do
        if send_data("PING") then
            -- 接收数据（使用socket.rx）
            local buff = zbuff.create(2048)
            local succ, len = socket.rx(ctrl, buff, 5000)
            if succ and len > 0 then
                log.info("socket.rx", "received", buff:query(0, len):toStr())
            else
                log.error("socket", "receive timeout")
                break
            end
        else
            break
        end
        sys.wait(3000)
    end

    socket.close(ctrl)
    log.info("APP", "connection closed")
end

-- 启动任务
sysplus.taskInitEx(main_task, maintaskname)

-- 必须放在文件末尾
sys.run()
