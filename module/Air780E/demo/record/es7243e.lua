-- es7243e器件地址
local es7243e_address = 0x10

-- es7243e初始化寄存器配置
local es7243e_reg = {
    {0x01, 0x3A},
	{0x00, 0x80},
	{0xF9, 0x00},
	{0x04, 0x02},
	{0x04, 0x01},
	{0xF9, 0x01},
	{0x00, 0x1E},
	{0x01, 0x00},
	--radio 256
	{0x03, 0x20},
	{0x04, 0x01},
	{0x0D, 0},
	{0x05, 0x00},
	{0x06, 4 - 1},
	{0x07, 0x00},
	{0x08, 0xFF},
	
	{0x02, (0x00 << 7) + 0},
	{0x09, 0xCA},
	{0x0A, 0x85},
	{0x0B, 0xC0 + 0x00 + (0x03 << 2)},
	{0x0E, 191},
	{0x10, 0x38},
	{0x11, 0x16},
	{0x14, 0x0C},
	{0x15, 0x0C},
	{0x17, 0x02},
	{0x18, 0x26},
	{0x0F, 0x80},
	{0x19, 0x77},
	{0x1F, 0x08 + (0 << 5) - 0x00},
	{0x1A, 0xF4},
	{0x1B, 0x66},
	{0x1C, 0x44},
	{0x1E, 0x00},
	{0x20, 0x10 + 14},
	{0x21, 0x10 + 14},
	{0x00, 0x80 + (0 << 6)},
	{0x01, 0x3A},
	{0x16, 0x3F},
	{0x16, 0x00},
	{0x0B, 0x00 + (0x03 << 2)},
	{0x00, (0x80) + (1 << 6)},
}

-- i2s数据接收buffer
local rx_buff = zbuff.create(3200)

-- amr数据存放buffer，尽可能地给大一些
local amr_buff = zbuff.create(10240)

--创建一个amr的encoder
local encoder = codec.create(codec.AMR, false)

-- i2s数据接收回调
local function record_cb(id, buff)
    if buff then
        log.info("I2S", id, "接收了", rx_buff:used())
        codec.encode(encoder, rx_buff, amr_buff)                -- 对录音数据进行amr编码，成功的话这个接口会返回true
    end
end



local function record_task()
    sys.wait(5000)
    uart.setup(1, 115200)                                       -- 开启串口1
    log.info("i2c initial",i2c.setup(0, i2c.FAST))              -- 开启i2c
    i2s.setup(0, 0, 8000, 16, 1, i2s.MODE_I2S)                  -- 开启i2s
    i2s.on(0, record_cb)                                        -- 注册i2s接收回调
    i2s.recv(0, rx_buff, 3200)
    sys.wait(300)
    for i, v in pairs(es7243e_reg) do                           -- 初始化es7243e
        i2c.send(0,es7243e_address,v,1)
    end
    sys.wait(5000)
    i2c.send(0, es7243e_address,{0x00, (0x80) + (0 << 6)},1)    -- 停止录音
    i2s.stop(0)                                                 -- 停止接收

    log.info("录音5秒结束")
    uart.write(1, "#!AMR\n")                                    -- 向串口发送amr文件标识数据
    sys.wait(5)                                                 -- 等待5ms确保发送成功
    uart.write(1, amr_buff:query())                             -- 向串口发送编码后的amr数据
end
pm.power(pm.DAC_EN, true)                                       -- 打开es7243e芯片供电
sys.taskInit(record_task)