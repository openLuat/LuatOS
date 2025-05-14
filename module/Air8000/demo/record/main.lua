-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "record"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")
_G.sysplus = require("sysplus")


gpio.setup(24, 1, gpio.PULLUP)          -- i2c工作的电压域

local taskName = "task_audio"

local MSG_MD = "moreData"   -- 播放缓存有空余
local MSG_PD = "playDone"   -- 播放完成所有数据

-- amr数据存放buffer，尽可能地给大一些
amr_buff = zbuff.create(20 * 1024)
--创建一个amr的encoder
encoder = nil
pcm_buff0 = zbuff.create(16000)
pcm_buff1 = zbuff.create(16000)
audio.on(0, function(id, event, point)
    --使用play来播放文件时只有播放完成回调
    if event == audio.RECORD_DATA then -- 录音数据
		if point == 0 then
			log.info("buff", point, pcm_buff0:used())
			codec.encode(encoder, pcm_buff0, amr_buff)
		else
			log.info("buff", point, pcm_buff1:used())
			codec.encode(encoder, pcm_buff1, amr_buff)
		end
        
    elseif event == audio.RECORD_DONE then -- 录音完成
        sys.publish("AUDIO_RECORD_DONE")
    else
        local succ,stop,file_cnt = audio.getError(0)
        if not succ then
            if stop then
                log.info("用户停止播放")
            else
                log.info("第", file_cnt, "个文件解码失败")
            end
        end
        -- log.info("播放完成一个音频")
        sysplus.sendMsg(taskName, MSG_PD)
    end
end)

---- MultipartForm上传文件
-- url string 请求URL地址
-- filename string 上传服务器的文件名
-- filePath string 待上传文件的路径
local function postMultipartFormData(url, filename, filePath)
    local boundary = "----WebKitFormBoundary"..os.time()
    local req_headers = {
        ["Content-Type"] = "multipart/form-data; boundary=" .. boundary,
    }
    local body = {}
    table.insert(body, "--"..boundary.."\r\nContent-Disposition: form-data; name=\"file\"; filename=\"".. filename .."\"\r\n\r\n")
    table.insert(body, io.readFile(filePath))
    table.insert(body, "\r\n")
    table.insert(body, "--"..boundary.."--\r\n")
    body = table.concat(body)
    log.info("headers: ", "\r\n" .. json.encode(req_headers), type(body))
    log.info("body: " .. body:len() .. "\r\n" .. body)
    local code, headers, body = http.request("POST",url,
            req_headers,
            body
    ).wait()   
    log.info("http.post", code, headers, body)
end

function audio_setup()
		local i2c_id = 0            -- i2c_id 0

		local pa_pin = 16           -- 喇叭pa功放脚
		local power_pin = 8         -- es8311电源脚

		local i2s_id = 0            -- i2s_id 0
		local i2s_mode = 0          -- i2s模式 0 主机 1 从机
		local i2s_sample_rate = 16000   -- 采样率
		local i2s_bits_per_sample = 16  -- 数据位数
		local i2s_channel_format = i2s.MONO_R   -- 声道, 0 左声道, 1 右声道, 2 立体声
		local i2s_communication_format = i2s.MODE_LSB   -- 格式, 可选MODE_I2S, MODE_LSB, MODE_MSB
		local i2s_channel_bits = 16     -- 声道的BCLK数量

		local multimedia_id = 0         -- 音频通道 0
		local pa_on_level = 1           -- PA打开电平 1 高电平 0 低电平
		local power_delay = 3           -- 在DAC启动前插入的冗余时间，单位100ms
		local pa_delay = 100            -- 在DAC启动后，延迟多长时间打开PA，单位1ms
		local power_on_level = 1        -- 电源控制IO的电平，默认拉高
		local power_time_delay = 100    -- 音频播放完毕时，PA与DAC关闭的时间间隔，单位1ms

		local voice_vol = 70        -- 喇叭音量
		local mic_vol = 80          -- 麦克风音量
		pm.power(pm.LDO_CTL, false)  --开发板上ES8311由LDO_CTL控制上下电
		sys.wait(100)
		pm.power(pm.LDO_CTL, true)  --开发板上ES8311由LDO_CTL控制上下电
		gpio.setup(8, 1)
	
		i2c.setup(i2c_id,i2c.FAST)      --设置i2c
		i2s.setup(i2s_id, i2s_mode, i2s_sample_rate, i2s_bits_per_sample, i2s_channel_format, i2s_communication_format,i2s_channel_bits)    --设置i2s
	
		audio.config(multimedia_id, pa_pin, pa_on_level, power_delay, pa_delay, power_pin, power_on_level, power_time_delay)
		audio.setBus(multimedia_id, audio.BUS_I2S,{chip = "es8311",i2cid = i2c_id , i2sid = i2s_id, voltage = audio.VOLTAGE_1800})	--通道0的硬件输出通道设置为I2S
	
		audio.vol(multimedia_id, voice_vol)
		audio.micVol(multimedia_id, mic_vol)
		sys.publish("AUDIO_READY")
end

-- 配置好audio外设
sys.taskInit(audio_setup)

local function audio_task()
    sys.waitUntil("AUDIO_READY")
    sys.wait(5000)
    local result

    --下面为录音demo，根据适配情况选择性开启
    local recordPath = "/record.amr"
    
    -- -- 直接录音到文件
    -- err = audio.record(0, audio.AMR, 5, 7, recordPath)
    -- sys.waitUntil("AUDIO_RECORD_DONE")
    -- log.info("record","录音结束")
    -- result = audio.play(0, {recordPath})
    -- if result then
    --     --等待音频通道的回调消息，或者切换歌曲的消息
    --     while true do
    --         msg = sysplus.waitMsg(taskName, nil)
    --         if type(msg) == 'table' then
    --             if msg[1] == MSG_PD then
    --                 log.info("播放结束")
    --                 break
    --             end
    --         else
    --             log.error(type(msg), msg)
    --         end
    --     end
    -- else
    --     log.debug("解码失败!")
    --     sys.wait(1000)
    -- end

    -- -- 录音到内存自行编码
    
    encoder = codec.create(codec.AMR, false, 7)
    log.info("encoder",encoder)
    log.info("开始录音")
    err = audio.record(0, audio.AMR, 5, 7, nil,nil, pcm_buff0, pcm_buff1)
    sys.waitUntil("AUDIO_RECORD_DONE")
    log.info("record","录音结束")
    os.remove(recordPath)
    io.writeFile(recordPath, "#!AMR\n")
	io.writeFile(recordPath, amr_buff:query(), "a+b")

	result = audio.play(0, {recordPath})
    if result then
        --等待音频通道的回调消息，或者切换歌曲的消息
        while true do
            msg = sysplus.waitMsg(taskName, nil)
            if type(msg) == 'table' then
                if msg[1] == MSG_PD then
                    log.info("播放结束")
                    break
                end
            else
                log.error(type(msg), msg)
            end
        end
    else
        log.debug("解码失败!")
        sys.wait(1000)
    end

	-- 下面的演示是将音频文件发送到服务器上，如有需要，可以将下面代码注释打开，这里的url是合宙的文件上传测试服务器，上传的文件到http://tools.openluat.com/tools/device-upload-test查看
	--[[ 
		local timeTable = os.date("*t", os.time())
		local nowTime = string.format("%4d%02d%02d_%02d%02d%02d", timeTable.year, timeTable.month, timeTable.day, timeTable.hour, timeTable.min, timeTable.sec)
		local filename = mobile.imei() .. "_" .. nowTime .. ".amr"
		postMultipartFormData("http://tools.openluat.com/api/site/device_upload_file", filename, recordPath)
 	]]
    --该方法为从串口1，把录音数据传给串口1
    --  uart.setup(1, 115200)								-- 开启串口1
    --  uart.write(1, io.readFile(recordPath))				-- 向串口发送录音文件

end

sysplus.taskInitEx(audio_task, taskName)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!