--[[
@module  websocket_receiver
@summary WebSocket client数据接收处理应用功能模块
@version 1.0
@date    2025.08.24
@author  陈媛媛
@usage
本文件为WebSocket client 数据接收应用功能模块，核心业务逻辑为：
处理接收到的数据，同时将数据发送给其他应用功能模块做进一步处理；

本文件的对外接口有2个：
1、websocket_receiver.proc(data, fin, opcode)：数据处理入口，在websocket_main.lua中调用；
2、sys.publish("RECV_DATA_FROM_SERVER", "recv from websocket server: ", data)：
   将接收到的数据通过消息"RECV_DATA_FROM_SERVER"发布出去；
   需要处理数据的应用功能模块订阅处理此消息即可，本demo项目中uart_app.lua中订阅处理了本消息；
]]

local websocket_receiver = {}

-- 接收数据缓冲区
local recv_data_buff = ""

--[[
处理接收到的数据

@api websocket_receiver.proc(data, fin, opcode)

@param1 data string
表示接收到的数据

@param2 fin number
表示是否为最后一个数据包，1表示是最后一个，0表示还有后续

@param3 opcode number
表示数据包类型，1-文本，2-二进制

@return1 result nil

@usage
websocket_receiver.proc(data, fin, opcode)
]]
function websocket_receiver.proc(data, fin, opcode)
    log.info("WebSocket接收处理", "收到数据", data, "是否结束", fin, "操作码", opcode)

    -- 接收到数据，通知网络环境检测看门狗功能模块进行喂狗
    sys.publish("FEED_NETWORK_WATCHDOG")

    -- 将数据拼接到缓冲区
    recv_data_buff = recv_data_buff .. data

    -- 如果收到完整消息(fin=1)并且缓冲区有数据，则处理
    if fin == 1 and #recv_data_buff > 0 then
        local processed_data = recv_data_buff
        recv_data_buff = "" -- 清空缓冲区

        -- 尝试解析JSON格式数据
        local json_data, result, errinfo = json.decode(processed_data)
        if result and type(json_data) == "table" then
            log.info("WebSocket接收处理", "收到JSON格式数据")
            -- 如果是JSON格式，提取有用信息
            if json_data.action == "echo" and json_data.msg then
                processed_data = json_data.msg
                log.info("WebSocket接收处理", "提取echo消息", processed_data)
            end
            -- 其他JSON格式数据处理逻辑可以在这里添加
        else
            log.info("WebSocket接收处理", "收到非JSON格式数据")
        end

        -- 将处理后的数据通过"RECV_DATA_FROM_SERVER"消息publish出去，给其他应用模块处理
        sys.publish("RECV_DATA_FROM_SERVER", "收到WebSocket服务器数据: ", processed_data)
    else
        log.info("WebSocket接收处理", "收到部分数据，等待后续数据包")
    end
end

return websocket_receiver