--[[
本文件为tcp client socket数据接收应用功能模块，核心业务逻辑为：
从内核读取接收到的数据，然后将数据发送给其他应用功能模块做进一步处理；

本文件的对外接口有2个：
1、tcp_client_receiver.proc(socket_client)：数据接收应用逻辑处理入口，在tcp_client_main.lua中调用；
2、sys.publish("RECV_DATA_FROM_SERVER", "recv from tcp server: ", data)：
   将接收到的数据通过消息"RECV_DATA_FROM_SERVER"发布出去；
   需要处理数据的应用功能模块订阅处理此消息即可，本demo项目中uart_app.lua中订阅处理了本消息；
]]

local tcp_client_receiver = {}

-- socket数据接收缓冲区
local recv_buff = nil

-- 数据接收应用入口函数
function tcp_client_receiver.proc(socket_client)
    -- 如果socket数据接收缓冲区还没有申请过空间，则先申请内存空间
    if recv_buff==nil then
        recv_buff = zbuff.create(1024)
        -- 当recv_buff不再使用时，不需要主动调用recv_buff:free()去释放
        -- 因为Lua的垃圾处理器会自动释放recv_buff所申请的内存空间
        -- 如果等不及垃圾处理器自动处理，在确定以后不会再使用recv_buff时，则可以主动调用recv_buff:free()释放内存空间
    end

    -- 从内核的缓冲区中读取数据到recv_buff中
    -- 如果recv_buff的存储空间不足，会自动扩容
    local result = socket.rx(socket_client, recv_buff)

    -- 读取数据失败
    -- 有两种情况：
    -- 1、recv_buff扩容失败
    -- 2、socket client和server之间的连接断开
    if not result then
        log.error("tcp_client_receiver.proc", "socket.rx error")
        return false
    end

    -- 如果读取到了数据, used()就必然大于0, 进行处理
    if recv_buff:used() > 0 then
        log.info("tcp_client_receiver.proc", "recv data len", recv_buff:used())

        -- 读取socket数据接收缓冲区中的数据，赋值给data
        local data = recv_buff:query()

        -- 将数据data通过"RECV_DATA_FROM_SERVER"消息publish出去，给其他应用模块处理
        sys.publish("RECV_DATA_FROM_SERVER", "recv from tcp server: ", data)

        -- 清空socket数据接收缓冲区中的数据
        recv_buff:del()
    end

    return true
end

return tcp_client_receiver
