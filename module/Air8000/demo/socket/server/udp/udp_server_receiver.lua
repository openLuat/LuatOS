--[[
@module  udp_server_receiver
@summary udp server socket数据接收应用功能模块 
@version 1.0
@date    2025.09.16
@author  王世豪
@usage
本文件为udp server socket数据接收应用功能模块，核心业务逻辑为：
从内核读取接收到的数据，然后将数据发送给其他应用功能模块做进一步处理；

本文件的对外接口有2个：
1、udp_server_receiver.proc(socket_server)：数据接收应用逻辑处理入口，在udp_server_main.lua中调用；
2、sys.publish("RECV_DATA_FROM_CLIENT", data, remote_ip, remote_port)：
    将接收到的数据通过消息"RECV_DATA_FROM_CLIENT"发布出去；
    需要处理数据的应用功能模块订阅处理此消息即可；
]]

local udp_server_receiver = {}

-- 客户端信息
local client_info = {}
-- 标记是否已经通知过客户端信息更新
local client_info_notified = false

-- 获取客户端信息
function udp_server_receiver.get_client_info()
    return client_info
end

-- 重置客户端信息
function udp_server_receiver.reset_client_info()
    client_info.ip = nil
    client_info.port = nil
    -- 重置通知标记，以便下次收到客户端信息时可以重新通知
    client_info_notified = false
end

-- 初始化客户端信息
udp_server_receiver.reset_client_info()

--[[
检查udp server是否收到数据，如果收到数据，读取并且处理完所有数据

@api udp_server_receiver.proc(data, remote_ip, remote_port)

@param1 data string
表示接收到的数据；

@param2 remote_ip string
表示发送数据的client的IP地址；

@param3 remote_port number
表示发送数据的client的端口号；

@return1 result bool
表示处理结果，成功为true，失败为false

@usage
udp_server_receiver.proc(data, remote_ip, remote_port)
]]
function udp_server_receiver.proc(data, remote_ip, remote_port)
    log.info("udp_server_receiver.proc", "收到数据", data, "来自", remote_ip, remote_port)
    
    -- -- 更新客户端信息
    -- local info_changed = (client_info.ip ~= remote_ip or client_info.port ~= remote_port)
    client_info.ip = remote_ip
    client_info.port = remote_port
    -- -- 在客户端信息发生变化时发布通知
    -- if info_changed and not client_info_notified then
    --     -- 发布消息通知其他模块客户端信息已更新
    --     sys.publish("UDP_CLIENT_INFO_UPDATED")
    --     client_info_notified = true
    -- end

    log.info("client_info", client_info.ip, client_info.port)

    -- 将接收到的数据通过消息发布出去
    sys.publish("RECV_DATA_FROM_CLIENT", data, remote_ip, remote_port)
    
    return true
end

return udp_server_receiver
