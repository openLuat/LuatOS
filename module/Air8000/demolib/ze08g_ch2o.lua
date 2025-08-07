--[[
@module ze08g_ch2o
@summary ZE08G-CH2O 电化学甲醛模组
@version 1.0
@date    2023.03.09
@author  BaiShiyu
@usage
--注意:因使用了sys.wait()所有api需要在协程中使用
-- 用法实例
sys = require("sys")
local ch2o = require "ze08g_ch2o"
local uartid = 1 -- 根据实际设备选取不同的uartid

sys.taskInit(function ()
    local result = ch2o.init(uartid)
    if not result then return end

    while true do
        sys.wait(1000)
        log.info("气体浓度值 PPB：", ch2o.getPPB())
        log.info("百万分比浓度 PPM：", ch2o.getPPM())
    end
end)
]]


local ze08g_ch2o = {}

local uartid    -- 根据实际设备选取不同的uartid
local rbuff
local ppb = 0

--[[
ze08g_ch2o初始化
@api ze08g_ch2o.init(uart_id)
@number uart_id uartid
@return bool   成功返回true
@usage
ze08g_ch2o.init(1)
]]
function ze08g_ch2o.init(uart_id)
    uartid = uart_id
    --初始化
    local result = uart.setup(
        uartid,--串口id
        9600,--波特率
        8,--数据位
        1--停止位
    )

    if result ~= 0 then
        log.info("ze08g_ch2o init_fail")
        return false
    end

    -- 收取数据会触发回调, 这里的"receive" 是固定值
    uart.on(uartid, "receive", function(id, len)
        local s = ""
        s = uart.read(id, len)
        if #s == 0 then return end
    
        local hexStr, hexLen = s:toHex()
        log.info("CH2O", "receive", hexStr, hexLen)
        
        if string.sub(hexStr,1,2) == "FF" and hexLen == 18 then
            rbuff = s
        end
    end)

    log.info("ze08g_ch2o init_ok")
    return true
end


--[[
获取ze08g_ch2o PPB数据
@api ze08g_ch2o.getPPB()
@return number 气体浓度值
@usage
local ppb = ze08g_ch2o.getPPB()
log.info("气体浓度值 PPB：", ppb))
]]
function ze08g_ch2o.getPPB()
    if not rbuff then return 0 end
    ppb = rbuff:byte(5)*255 + rbuff:byte(6)
    return ppb
end

--[[
获取ze08g_ch2o PPM数据
@api ze08g_ch2o.getPPM()
@return number 百万分比浓度
@usage
local ppm = ze08g_ch2o.getPPM()
log.info("百万分比浓度 PPM：", ppm))
]]
function ze08g_ch2o.getPPM()
    return ppb / 1000
end

return ze08g_ch2o

