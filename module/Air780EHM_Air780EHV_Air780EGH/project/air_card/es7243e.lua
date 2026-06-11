--  维护录音开始时间和结束时间
-- 双buff，写入文件，算下3200编码完的大小。留出余量吗，做次数切换buff ，并写入sd卡
-- es7243e器件地址
local es7243e_address = 0x10
local i2cid = 1
-- es7243e初始化寄存器配置
local es7243e_reg = {
    {0x01, 0x3A}, {0x00, 0x80}, {0xF9, 0x00}, {0x04, 0x02}, {0x04, 0x01},
    {0xF9, 0x01}, {0x00, 0x1E}, {0x01, 0x00}, -- radio 256
    {0x03, 0x20}, {0x04, 0x01}, {0x0D, 0}, {0x05, 0x00}, {0x06, 4 - 1},
    {0x07, 0x00}, {0x08, 0xFF}, {0x02, (0x00 << 7) + 0}, {0x09, 0xCA},
    {0x0A, 0x85}, {0x0B, 0xC0 + 0x00 + (0x03 << 2)}, {0x0E, 191}, {0x10, 0x38},
    {0x11, 0x16}, {0x14, 0x0C}, {0x15, 0x0C}, {0x17, 0x02}, {0x18, 0x26},
    {0x0F, 0x80}, {0x19, 0x77}, {0x1F, 0x08 + (0 << 5) - 0x00}, {0x1A, 0xF4},
    {0x1B, 0x66}, {0x1C, 0x44}, {0x1E, 0x00}, {0x20, 0x10 + 14},
    {0x21, 0x10 + 14}, {0x00, 0x80 + (0 << 6)}, {0x01, 0x3A}, {0x16, 0x3F},
    {0x16, 0x00}, {0x0B, 0x00 + (0x03 << 2)}, {0x00, (0x80) + (1 << 6)}
}

-- i2s数据接收buffer
local rx_buff = zbuff.create(3200)

-- amr数据存放buffer，尽可能地给大一些
local amr_buff1 = zbuff.create(32000)
-- amr数据存放buffer，尽可能地给大一些
local amr_buff2 = zbuff.create(32000)
local cur_amr_buff = true

local file_name
local write_file_path
local file_path

local cb_counter = 0
-- 创建一个amr的encoder
local encoder = codec.create(codec.AMR, false, 7)


-- 首次开机标志位
local first_boot = true
-- 录音ticks
local record_ticks
-- local start_time
-- local end_time

-- i2s数据接收回调,定时存下文件
local function record_cb(id, buff)
    if buff then
        -- log.info("I2S", id, rx_buff:used(),"接收了,但是录音模式", gpio_util.get_recording_mode())
        if gpio_util.get_recording_mode() then
            cb_counter = cb_counter + 1
            if cb_counter > 100 then
                cur_amr_buff = not cur_amr_buff
                cb_counter = 0
                sys.publish("write_file")
            end
            -- log.info("I2S", id, "接收了", rx_buff:used())

            if cur_amr_buff then
                codec.encode(encoder, rx_buff, amr_buff1) -- 对录音数据进行amr编码，成功的话这个接口会返回true
                -- log.info("encode", "amr_buff1接收了", amr_buff1:used(),
                --          "cb_counter ", cb_counter)
            else
                codec.encode(encoder, rx_buff, amr_buff2) -- 对录音数据进行amr编码，成功的话这个接口会返回true
                -- log.info("encode", "amr_buff2接收了", amr_buff2:used(),
                --          "cb_counter ", cb_counter)
            end
        end
    end
end

sys.subscribe("write_file", function()
    log.info("write_file", cur_amr_buff, "file_path", file_path)
    if file_path then
        local f = io.open(file_path, "a")
        if f then
            if not cur_amr_buff then
                log.info("amr_buff1写入了", amr_buff1:used())
                if amr_buff1:used() > 100 then
                    f:write(amr_buff1:toStr(0, amr_buff1:used()))
                    f:close()
                    -- amr_buff1:clear(0)
                    amr_buff1:seek(0, zbuff.SEEK_SET)
                end
            else
                log.info("amr_buff2写入了", amr_buff2:used())
                if amr_buff2:used() > 100 then
                    f:write(amr_buff2:toStr(0, amr_buff2:used()))
                    f:close()
                    -- amr_buff2:clear(0)
                    amr_buff2:seek(0, zbuff.SEEK_SET)
                end
            end
        else
            log.error("打开文件失败", file_path)
            config.record_error = true
            config.record_status = config.record_status_mode.record_error
        end
    end
end)

local function i2c_i2s_init()
    i2c.setup(i2cid, i2c.FAST)
    i2s.setup(0, 1, 8000, 16, 1, i2s.MODE_I2S)
    i2s.on(0, record_cb) -- 开启i2c
    i2s.recv(0, rx_buff, 3200)
    gpio.setup(32, 1)
end

local record_state = false
local open_record_time
local function record_task()
    -- sys.waitUntil("start_record", config.UPLOAD_CONFIG.limitDuration * 1000)
    uart.setup(1, 115200) -- 开启串口1
    while true do
        sys.waitUntil("start_record", 1000)
        log.info("record_state", record_state)
        if gpio_util.get_recording_mode() then
            if first_boot then
                first_boot = false
                local sec_h, sec_l = mcu.ticks2(2)
                record_ticks = sec_l
            end
            local record_time =os.date("%Y%m%d%H%M%S")
            file_name = os.date("%Y%m%d_%H%M%S") .. ".amr"
            RecordingManager.addRecording(file_name)
            file_path = "/sd/" .. file_name
            local f = io.open(file_path, "w")
            if f then
                log.info("打开文件", file_path)
                f:write("#!AMR\n")
                f:close()
            end
            if not record_state then
                log.info("es7243e 录音开始")
                i2c_i2s_init()
                for i, v in pairs(es7243e_reg) do
                    i2c.send(i2cid, es7243e_address, v, 1)
                end
                record_state = true
                open_record_time = record_time
            end
            RecordingManager.setopen_record_time(file_name,open_record_time)
            log.info("es7243e 持续录音中")
            sys.waitUntil("stop_record",
                          config.UPLOAD_CONFIG.limitDuration * 1000)
            -- 上传录音
            cur_amr_buff = not cur_amr_buff
            cb_counter = 0
            sys.publish("write_file")
            -- sys.wait(100) -- 等待1s
            log.info("一片录音结束",file_name,RecordingManager.setEndTime(file_name, os.time()))
        else
            if record_state then
                -- sys.wait(1000)
                -- 结束录音
                record_state = false
                i2c.send(i2cid, es7243e_address, {0x00, (0x80) + (0 << 6)}, 1) -- 停止录音
                i2s.stop(0) -- 停止接收
                log.info("es7243e 录音结束")
                gpio.close(32)
            end
        end
    end
end

--20秒后更新首次开机的录音开始时间
local function rerecord_time_update()
    sys.waitUntil("stop_record", 20000)
    if record_ticks then
        local sec_h, sec_l = mcu.ticks2(2)
        log.info("首次开机录音开始时间", record_ticks, sec_l)
        local diff_tick = sec_l - record_ticks
        log.info("dtick64", diff_tick)
        local ts =  os.time() - diff_tick
        rerecord_time = os.date("%Y%m%d%H%M%S",ts)
        open_record_time = rerecord_time
        RecordingManager.set_firstopen_record_time(file_name, rerecord_time,ts)
        log.info("rerecord_time", rerecord_time, "now_time", os.date("%Y%m%d%H%M%S", os.time()))
    end
end
sys.taskInit(rerecord_time_update)

sys.taskInit(record_task)
