--[[
@module  tcp_multi_receiver
@summary tcp server socket数据接收应用功能模块(一对多)
@version 1.0
@date    2026.08.02
@author  王世豪
@usage
本文件为tcp server 数据接收应用功能模块(一对多版本)，核心业务逻辑为：
从指定的client socket读取内核缓冲区的数据，然后将数据发布给其他应用功能模块做进一步处理；
每个client拥有独立的接收缓冲区，互不影响。

本文件的对外接口有3个：
1、tcp_multi_receiver.proc(client)：数据接收应用逻辑处理入口，在tcp_multi_main.lua的client事件回调中调用；
2、tcp_multi_receiver.cleanup(client)：清理指定client的接收缓冲区，在client关闭时调用；
3、sys.publish("RECV_DATA_FROM_CLIENT", data, client)：
    将接收到的数据通过消息"RECV_DATA_FROM_CLIENT"发布出去；
    第二个参数data为接收到的数据；
    第三个参数client为数据来源的client句柄，业务模块可以基于它做单播回复；
    需要处理数据的应用功能模块订阅处理此消息即可，本demo项目中uart_app.lua中订阅处理了本消息；
]]

local tcp_multi_receiver = {}

-- 每个client各自独立的socket数据接收缓冲区
-- key为tostring(client)，value为zbuff
local recv_buffs = {}

--[[
检查指定的client socket是否收到数据，如果收到数据，读取并且处理完所有数据
@api tcp_multi_receiver.proc(client)

@param1 client userdata or lightuserdata
表示由socket.accept接口派生的client socket对象；
必须传入，不允许为空或者nil；

@return1 result bool
表示处理结果，成功为true，失败为false（表示该client连接异常）

@usage
-- 示例：处理指定client接收数据
tcp_multi_receiver.proc(client)
]]
function tcp_multi_receiver.proc(client)
    -- 以tostring(client)为key，获取该client专用的接收缓冲区
    -- userdata与lightuserdata的tostring结果一致，均指向同一底层socket对象
    local key = tostring(client)
    if recv_buffs[key]==nil then
        recv_buffs[key] = zbuff.create(1024)
        -- 当recv_buff不再使用时，不需要主动调用recv_buff:free()去释放
        -- 因为Lua的垃圾处理器会自动释放recv_buff所申请的内存空间
        -- 如果等不及垃圾处理器自动处理，在确定以后不会再使用recv_buff时，则可以主动调用recv_buff:free()释放内存空间
    end
    local recv_buff = recv_buffs[key]

    -- 循环从内核的缓冲区读取接收到的数据
    -- 如果读取失败，返回false，退出循环
    -- 如果读取成功，处理数据，并且继续循环读取
    -- 如果读取成功，并且读出来的数据为空，表示已经没有数据可读，返回true，退出循环
    while true do
        -- 从内核的缓冲区中读取数据到recv_buff中
        local succ, param = socket.rx(client, recv_buff)

        -- 读取数据失败
        -- 有两种情况：
        -- 1、recv_buff扩容失败
        -- 2、socket server和client之间的连接断开
        if not succ then
            log.info("tcp_multi_receiver.proc", "socket.rx error", param)
            return false
        end

        -- 如果读取到了数据, used()就必然大于0, 进行处理
        if recv_buff:used() > 0 then
            log.info("tcp_multi_receiver.proc", "recv data len", recv_buff:used())

            -- 读取socket数据接收缓冲区中的数据，赋值给data
            local data = recv_buff:query()

            log.info("tcp_multi_receiver.proc", "recv data", data)

            -- 将数据以及来源client通过"RECV_DATA_FROM_CLIENT"消息publish出去，给其他应用模块处理
            -- 业务模块可以通过第二个参数client，对数据来源的client做单播回复
            sys.publish("RECV_DATA_FROM_CLIENT", data, client)

            -- 清空socket数据接收缓冲区中的数据
            recv_buff:del()
        else
            -- 读取成功，但是读出来的数据为空，表示已经没有数据可读，可以退出循环了
            break
        end
    end

    return true
end

--[[
清理指定client的接收缓冲区
@api tcp_multi_receiver.cleanup(client)

@param1 client userdata or lightuserdata
表示由socket.accept接口派生的client socket对象；
必须传入，不允许为空或者nil；

@usage
-- 示例：client关闭时清理其缓冲区
tcp_multi_receiver.cleanup(client)
]]
function tcp_multi_receiver.cleanup(client)
    recv_buffs[tostring(client)] = nil
end

return tcp_multi_receiver
