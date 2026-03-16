local DS18B20 = {}
new_temp=-100--中间过渡数据
gongshui_temp=-1000--供水温度/进水温度
huishui_temp=-1000--回水温度/出水温度
mark=0--采集成功标志
TEMP_mark=0--温度采集成功标志
--=============================================================
--匹配温度ID，并发送温度转换命令并做温度转换
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
            new_temp=KeepDecimalPlace(t, 2)--处理数据四舍五入
            mark=1--采集成功
            log.info("处理后的温度=",new_temp)
        else
            log.info("RAM DATA CRC校验不对",  mcu.x32(crc8c), mcu.x32(rbuff[8]))
            new_temp=-100--数据校验错误
            mark=0--采集失败
            return
        end
        sys.wait(50)
    end
end
--=============================================================
--读温度ID及判断数据
local function test_ds18b20()
    local succ,rx_data
    local id = zbuff.create(8)

    local crc8c
    --onewire.init(0)
    --onewire.timing(0, false, 0, 500, 500, 15, 240, 70, 1, 15, 10, 2)
    --for i=1,5 do
    while true do
        onewire.init(0)
        onewire.timing(0, false, 0, 500, 500, 15, 240, 70, 1, 15, 10, 2)
        id:set() --清空id
        succ,rx_data = onewire.rx(0, 8, 0x33, id, false, true, true)
        if succ then
            if id[0] == 0x28 then
                crc8c = crypto.crc8(id:query(0,7), 0x31, 0, true)
                if crc8c == id[7] then
                    log.info("探测到DS18B20", id:query(0, 7):toHex())
                    read_ds18b20(id)
                    log.info("DS18B20离线,重新探测")
                    new_temp=-200--异常处理
                    mark=2--识别出，但是采集失败
                else
                    log.info("ROM ID CRC校验不对",  mcu.x32(crc8c), mcu.x32(id[7]))
                    new_temp=-300--异常处理
                    mark=3--识别出，CRC校验不对
                end
            else
                log.info("ROM ID不正确", mcu.x32(id[0]))
                new_temp=-400--异常处理
                mark=4--识别出，D不正确不对
            end
        end
        log.info("没有检测到DS18B20, 5秒后重试")
        new_temp=-500--异常处理
        mark=5--识别出，D不正确不对
        sys.wait(100)
    end
end
--=============================================================
local function select_ds18b20()
      local water_in_pin=11
      local water_out_pin=9
      local water_in=gpio.setup(water_in_pin, 0)--初始化状态
      local water_out=gpio.setup(water_out_pin, 0)--初始化状态
      while true do
            
            water_in(1)
            water_out(0)
            mark=0--重置一下标志位
            onewire.deinit(0) -- 切换的时候一定要先关闭单总线，在读取的时候重新初始化
            sys.wait(1000)
            TEMP_mark=0--初始化一下 
            log.info("进水标志位mark=",mark)
            if mark==1 then
                gongshui_temp=new_temp
                log.info("采集供水/进水成功，温度=",gongshui_temp)
            else
                gongshui_temp=-1000
                log.info("采集供水/进水失败，温度=",gongshui_temp)
            end
            water_in(0)
            water_out(1)
            mark=0--重置一下标志位
            onewire.deinit(0) -- 切换的时候一定要先关闭单总线，在读取的时候重新初始化
            sys.wait(1000)
            log.info("回水标志位mark=",mark)
            log.info("采集供水/进水成功，电源状态切换")
            if mark==1 then
                huishui_temp=new_temp
                log.info("采集回水/出水成功，温度=",huishui_temp)
            else
                huishui_temp=-1000
                log.info("采集回水/出水失败，温度=",huishui_temp)
            end 
            TEMP_mark=1--温度采集成功          
      end
end
--=============================================================
if onewire then
    sys.taskInit(test_ds18b20)
else
    log.info("no onewire")
end
sys.taskInit(select_ds18b20)
--=============================================================