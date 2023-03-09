-- UART1支持600 1200 2400 4800 9600波特率下休眠仍然接收数据，并且不丢失数据
-- 其他波特率时，在休眠后通过UART1的RX唤醒，注意唤醒开始所有连续数据会丢失，所以要发2次，第一次发送字节后，会有提示，然后再发送数据
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "ZE08G-CH2O"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")

local uartid = 1 -- 根据实际设备选取不同的uartid

local rbuff
local ppb = 0
--初始化
local result = uart.setup(
    uartid,--串口id
    9600,--波特率
    8,--数据位
    1--停止位
)

-- 获取PPB值
-- 气体浓度值 (PPB)=( 气 体 浓 度 高 位 *256+ 气 体 浓 度 低 位 )
function GetPPB()
    if not rbuff then return nil end
    ppb = rbuff:byte(5)*255 + rbuff:byte(6)
    return ppb
end

-- 获取PPM值
--百万分比浓度（PPM）= PPB / 1000
function GetPPM()
    return ppb / 1000
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

sys.taskInit(function ()
    while true do
        sys.wait(1000)
        log.info("ppb:  ", GetPPB(), "ppm:    ", GetPPM(), string.format("USART_PM25:   %s mg/m3.", GetPPM() * 1.25))
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
