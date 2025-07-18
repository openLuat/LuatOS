
pm.ioVol(pm.IOVOL_ALL_GPIO, 3300) -- 所有GPIO高电平输出3.3V(方便使用VDD_EXT给18B20供电)
gpio.setup(2, 1) --GPIO2控制780EPM开发板V1.3版本camera电源打开和关闭
gpio.setup(31, 1) -- GPIO31控制780EPM开发板V1.4版本camera电源打开和关闭

local onewire_pin = 54 --18B20接的pin 54脚


pins.setup(onewire_pin, "ONEWIRE") -- PAD54脚既是GPIO3也是cam_mclk 

--读取当前pin脚上的18B20温度
local function read_ds18b20(id)
log.info("读取温度",id)
    local tbuff = zbuff.create(10)
    local succ, crc8c, range, t
    local rbuff = zbuff.create(9)
    tbuff:write(0x55)
    tbuff:copy(nil, id)
    tbuff:write(0xb8)
  
    tbuff[tbuff:used() - 1] = 0x44
    succ = onewire.tx(0, tbuff, false, true, true)
    if not succ then
        return
    end

    succ = onewire.reset(0, true)
    if not succ then
        return
    end
    if onewire.bit(0) > 0 then
        log.info("温度转换完成")
    end
    tbuff[tbuff:used() - 1] = 0xbe
    succ = onewire.tx(0, tbuff, false, true, true)
    if not succ then
        return
    end
    succ, rx_data = onewire.rx(0, 9, nil, rbuff, false, false, false)
    crc8c = crypto.crc8(rbuff:toStr(0, 8), 0x31, 0, true)
    if crc8c == rbuff[8] then
        range = (rbuff[4] >> 5) & 0x03
        -- rbuff[0] = 0xF8
        -- rbuff[1] = 0xFF
        t = rbuff:query(0, 2, false, true)
        t = t * (5000 >> range)
        t = t / 10000
        log.info("当前温度", t,"原始值为",mcu.x32(rbuff[8]))
    else
        log.info("RAM DATA CRC校验不对", mcu.x32(crc8c), mcu.x32(rbuff[8]))
        return
    end

end

--初始化当前pin脚上的18B20，并读取18B20的唯一识别ID
local function test_ds18b20()
    local succ, rx_data
    local id = zbuff.create(8)
    local crc8c
    onewire.init(0) -- 初始化单总线
    onewire.timing(0, false, 0, 500, 500, 15, 240, 70, 1, 15, 10, 2)
    id:set() -- 清空id
    succ, rx_data = onewire.rx(0, 8, 0x33, id, false, true, true)
    if succ then
        if id[0] == 0x28 then
            crc8c = crypto.crc8(id:query(0, 7), 0x31, 0, true)
            if crc8c == id[7] then
                log.info("探测到DS18B20", "18B20对应唯一ID为", id:query(0, 7):toHex())
                read_ds18b20(id)
                -- log.info("DS18B20离线，重新探测")
            else
                log.info("ROM ID CRC校验不对", mcu.x32(crc8c), mcu.x32(id[7]))
            end
        else
            log.info("ROM ID不正确", mcu.x32(id[0]))
        end
    else
        log.info("没有检测到DS18B20")
    end
end

local switchover_pin = gpio.PWR_KEY --选择powerkey作为切换18B20读数的信号脚

gpio.debounce(switchover_pin, 100) --设置防抖


--设置powerkey按下和抬起的功能(18B20温度的取值再54pin和56pin之间切换)
--如果客户需要其他pin(22/54/56/78)则改动switchover_pin为用户需要的即可
--注意，由于powerkey不能做单边沿触发，所以一次按下和抬起的动作，会触发两次切换pin
--看效果的话，可以先一直按住powerkey几秒，再松开
gpio.setup(switchover_pin, function()
    log.info("Touch_pin", switchover_pin, "被触发")
    log.info("当前单总线pad", onewire_pin)
    if onewire_pin == 54 then
        log.info("给PAD" .. onewire_pin .. "配置到GPIO3上去", pins.setup(onewire_pin, "GPIO3"))
        log.info("给GPIO3设置为高电平输出模式",gpio.setup(3,1))--一定要执行gpio.setup，至于是哪种模式，用户根据自身需求
        onewire_pin = 56
    else
        log.info("给PAD" .. onewire_pin .. "配置到GPIO7上去", pins.setup(onewire_pin, "GPIO7"))
        log.info("给GPIO7设置为高电平输出模式",gpio.setup(7,1))

        onewire_pin = 54
    end
    log.info("设置后单总线pad", onewire_pin)

    onewire.deinit(0) -- 切换的时候一定要先关闭单总线，在读取的时候重新初始化

    log.info("给" .. onewire_pin .. "配置到onewire上去", pins.setup(onewire_pin, "ONEWIRE"))
    sys.publish("powerkey被按下")
end, gpio.PULLUP, gpio.RISING)

sys.taskInit(function()
    while 1 do
        -- sys.waitUntil("powerkey被按下")
        log.info("1S后读取"..onewire_pin.."脚上的18B20")
        sys.wait(1000)
        log.info("开始读取18B20")
        test_ds18b20()
    end
end)




