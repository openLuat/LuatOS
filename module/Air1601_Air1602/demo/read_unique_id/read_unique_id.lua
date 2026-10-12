--[[
@module  read_unique_id
@summary 读取Air1601的唯一ID
@version 1.0
@date    2026.07.02
@usage
本demo演示的功能为：
    读取Air1601的MCU唯一ID
    使用toHex()方法转换为十六进制字符串
    通过日志输出显示
]]

function read_unique_id()
    -- 读取唯一ID
    local unique_id = mcu.unique_id()
    
    if unique_id and #unique_id > 0 then
        -- 转换为十六进制字符串并输出
        log.info("unique_id", "Air1601 Unique ID (hex):", unique_id:toHex())
        log.info("unique_id", "ID length:", #unique_id, "bytes")
    else
        log.warn("unique_id", "Failed to get unique ID")
    end
end

sys.taskInit(read_unique_id)

