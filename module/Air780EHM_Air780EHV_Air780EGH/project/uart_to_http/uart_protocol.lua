--[[
@module  uart_protocol
@summary 串口协议格式定义库
@version 1.0
@date    2025.03.31
@author  拓毅恒
@usage

注意：
- 本文件定义串口通信协议格式规范
- uart_to_http.lua和uart_sender.lua都依赖此协议定义
- 协议支持校验和验证，可通过配置启用或禁用

协议帧格式：
+--------+--------+--------+--------+--------+--------+--------+--------+
|  帧头1 |  帧头2 | 长度低 | 长度高 |  数据  | 校验和 | 帧尾1  | 帧尾2  |
+--------+--------+--------+--------+--------+--------+--------+--------+
|  0xAA  |  0x55  |  lenL  |  lenH  | N字节  |  1字节 |  0x55  |  0xAA  |
+--------+--------+--------+--------+--------+--------+--------+--------+

协议特性：
- 帧头：0xAA 0x55 (2字节)
- 数据长度：2字节小端模式
- 校验和：数据内容的累加和（可选）
- 帧尾：0x55 0xAA (2字节)
- 最大数据长度：1024字节
]]

-- 协议帧常量定义
local protocol = {
    -- 帧头 (2字节)
    frame_head = {0xAA, 0x55},
    
    -- 帧尾 (2字节)
    frame_tail = {0x55, 0xAA},
    
    -- 长度字段
    len_field = {
        size = 2,           -- 长度字段字节数
        endian = "little",  -- 小端模式: little, 大端模式: big
    },
    
    -- 校验方式
    checksum = {
        enable = true,      -- 是否启用校验
        method = "sum",     -- 校验方法: sum(累加和), xor(异或), crc8, crc16
        size = 1,           -- 校验字段字节数
        range = "data",     -- 校验范围: data(仅数据), all(帧头到数据)
    },
    
    -- 帧结构信息
    frame_struct = {
        head_size = 2,      -- 帧头字节数
        len_size = 2,       -- 长度字段字节数
        checksum_size = 1,  -- 校验和字节数
        tail_size = 2,      -- 帧尾字节数
        min_frame_size = 7, -- 最小帧长度 = 帧头2 + 长度2 + 数据0 + 校验1 + 帧尾2
    },
    
    -- 数据限制
    limits = {
        max_data_len = 1024,    -- 最大单帧数据长度
        rx_buff_size = 2048,    -- 接收缓冲区大小
    }
}

-- 协议工具函数
local protocol_utils = {
    -- 计算校验和
    calc_checksum = function(data, len)
        local sum = 0
        for i = 0, len - 1 do
            sum = sum + data[i]
        end
        return sum & 0xFF
    end,
    
    -- 组装帧
    pack_frame = function(data)
        local len = #data
        
        -- 计算校验和
        local checksum = 0
        for i = 1, len do
            checksum = checksum + string.byte(data, i)
        end
        checksum = checksum & 0xFF
        
        -- 组装帧
        local frame = string.char(
            protocol.frame_head[1],
            protocol.frame_head[2],
            len & 0xFF,
            (len >> 8) & 0xFF
        ) .. data .. string.char(
            checksum,
            protocol.frame_tail[1],
            protocol.frame_tail[2]
        )
        
        return frame
    end,
    
    -- 解析长度字段 (小端模式)
    parse_length = function(byte_low, byte_high)
        return byte_low + (byte_high << 8)
    end
}

-- 返回协议定义和工具函数
return {
    protocol = protocol,
    protocol_utils = protocol_utils
}
