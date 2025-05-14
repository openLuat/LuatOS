PROJECT = "onewiredemo"
VERSION = "1.0.0"
sys = require("sys")
log.style(1)

--[[
接线说明:
   DS18B20    Air780EPM
1. GND    -> GND
2. VDD    -> 3.3V
3. DATA    -> GPIO2

注意:
1. 3.3v在老版本的开发板上没有引脚, 所以需要外接, 一定要确保共地
2. ONEWIRE功能支持在4个引脚使用, 但硬件通道只有一个, 默认是GPIO2
3. 如需切换到其他脚, 参考如下切换逻辑, 选其中一种

mcu.altfun(mcu.ONEWIRE, 0, 17, 4, 0) -- GPIO2, 也就是默认值
mcu.altfun(mcu.ONEWIRE, 0, 18, 4, 0) -- GPIO3
mcu.altfun(mcu.ONEWIRE, 0, 22, 4, 0) -- GPIO7
mcu.altfun(mcu.ONEWIRE, 0, 53, 4, 0) -- GPIO28
]]

local function read_ds18b20(id)
    local tbuff = zbuff.create(10)
    local succ,crc8c,range,t
    local rbuff = zbuff.create(9)
    --如果有多个DS18B20,需要带上ID
    tbuff:write(0x55)
    tbuff:copy(nil, id)
    tbuff:write(0xb8)
    --如果只有1个DS18B20,就用无ID方式
    --tbuff:write(0xcc,0xb8)
    while true do
        tbuff[tbuff:used() - 1] = 0x44
        succ = onewire.tx(0, tbuff, false, true, true)
        if not succ then
            return
        end
        while true do
            succ = onewire.reset(0, true)
            if not succ then
                return
            end
            if onewire.bit(0) > 0 then
                log.info("温度转换完成")
                break
            end
            sys.wait(10)
        end
        tbuff[tbuff:used() - 1] = 0xbe
        succ = onewire.tx(0, tbuff, false, true, true)
        if not succ then
            return
        end
        succ,rx_data = onewire.rx(0, 9, nil, rbuff, false, false, false)
        crc8c = crypto.crc8(rbuff:toStr(0,8), 0x31, 0, true)
        if crc8c == rbuff[8] then
            range = (rbuff[4] >> 5) & 0x03
            -- rbuff[0] = 0xF8
            -- rbuff[1] = 0xFF
            t = rbuff:query(0,2,false,true)
            t = t * (5000 >> range)
            t = t / 10000
            log.info(t)
        else
            log.info("RAM DATA CRC校验不对",  mcu.x32(crc8c), mcu.x32(rbuff[8]))
            return
        end
        sys.wait(500)
    end
end

local function test_ds18b20()
    local succ,rx_data
    local id = zbuff.create(8)

    local crc8c
    onewire.init(0)
    onewire.timing(0, false, 0, 500, 500, 15, 240, 70, 1, 15, 10, 2)
    while true do
        id:set() --清空id
        succ,rx_data = onewire.rx(0, 8, 0x33, id, false, true, true)
        if succ then
            if id[0] == 0x28 then
                crc8c = crypto.crc8(id:query(0,7), 0x31, 0, true)
                if crc8c == id[7] then
                    log.info("探测到DS18B20", id:query(0, 7):toHex())
                    read_ds18b20(id)
                    log.info("DS18B20离线，重新探测")
                else
                    log.info("ROM ID CRC校验不对",  mcu.x32(crc8c), mcu.x32(id[7]))
                end
            else
                log.info("ROM ID不正确", mcu.x32(id[0]))
            end
        end
        log.info("没有检测到DS18B20, 5秒后重试")
        sys.wait(5000)

    end
    

end

if onewire then
    sys.taskInit(test_ds18b20)
else
    log.info("no onewire")
end

sys.run()