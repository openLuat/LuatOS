
PROJECT = "modbus_rtu"
VERSION = "1.0.0"

sys = require("sys")

sys.taskInit(function()
    uart.on(1, "recv", function(id, len)
        local data = uart.read(1, len)
        local _,addr,Instructions,reg,value,crc = pack.unpack(data,"<bbbHH")
        log.info("温度：", value.."℃" )
    end)

    local function modbus_send(uart_id,slaveaddr,Instructions,reg,value)
        local data = (string.format("%02x",slaveaddr)..string.format("%02x",Instructions)..string.format("%04x",reg)..string.format("%04x",value)):fromHex()
        local modbus_crc_data= pack.pack('<h', crypto.crc16("MODBUS",data))
        local data_tx = data..modbus_crc_data
        uart.write(uart_id,data_tx)
    end

    while 1 do
        modbus_send(1,0x01,0x03,0x01,0x01)
        sys.wait(2000)
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
