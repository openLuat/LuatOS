-- es8218e器件地址
local es8218e_address = 0x10

-- es8218e初始化寄存器配置
local es8218e_reg = {
    {0x00, 0x00},
    {0x01, 0x2F + (0 << 7)},
    {0x02, 0x01},
    {0x03, 0x20},
    {0x04, 0x01},
    {0x05, 0x00},
    {0x06, 4 + (0 << 5)},
    {0x10, 0x18 + 0},
    {0x07, 0 + (3 << 2)},
    {0x09, 0x00},
    {0x0A, 0x22 + (0xCC * 0)},
    {0x0B, 0x02 - 0},
    {0x14, 0xA0},
    {0x0D, 0x30},
    {0x0E, 0x20},
    {0x23, 0x00},
    {0x24, 0x00},
    {0x18, 0x04},
    {0x19, 0x04},
    {0x0F, (0 << 5) + (1 << 4) + 7},
    {0x08, 0x00},
    {0x00, 0x80},
    {0x12, 0x1C},
    {0x11, 0},
    {0x01, (0x2f) + (1 << 7)},
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
    for i, v in pairs(es8218e_reg) do                           -- 初始化es8218e
        i2c.send(0,es8218e_address,v,1)
    end
    sys.wait(5000)
    i2c.send(0, es8218e_address,{0x01, (0x2f) + (1 << 7)},1)    -- 停止录音
    i2s.stop(0)                                                 -- 停止接收

    log.info("录音5秒结束")
    uart.write(1, "#!AMR\n")                                    -- 向串口发送amr文件标识数据
    sys.wait(5)                                                 -- 等待5ms确保发送成功
    uart.write(1, amr_buff:query())                             -- 向串口发送编码后的amr数据
end
pm.power(pm.DAC_EN, true)                                       -- 打开es8218e芯片供电
sys.taskInit(record_task)