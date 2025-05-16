audio.on(0, function(id, event)
    --使用play来播放文件时只有播放完成回调
    local succ,stop,file_cnt = audio.getError(0)
    if not succ then
        if stop then
            log.info("用户停止播放")
        else
            log.info("第", file_cnt, "个文件解码失败")
        end
    end
    -- log.info("播放完成一个音频")
    sys.publish("AUDIO_PLAY_DONE")
end)

local i2c_id = 1
local i2s_id = 0

local samplerate = 16000	--支持内部amr编码的soc才能用


-- es8311器件地址
local es8311_address = 0x18
local record_cnt = 0
-- es8311初始化寄存器配置
local es8311_reg = {
	{0x45,0x00},
	{0x01,0x30},
	{0x02,0x10},
	{0x02,0x00},
	{0x03,0x10},
	{0x16,0x24},
	{0x04,0x20},
	{0x05,0x00},
	{0x06,3},
	{0x07,0x00},
	{0x08,0xFF},
	{0x09,0x0C},
	{0x0A,0x0C},
	{0x0B,0x00},
	{0x0C,0x00},
	{0x10,0x03},
	{0x11,0x7F},
	{0x00,0x80},
	{0x0D,0x01},
	{0x01,0x3F},
	{0x14,0x1a},
	{0x12,0x28},
	{0x13,0x00},
	{0x0E,0x02},
	{0x0F,0x44},
	{0x15,0x00},
	{0x1B,0x0A},
	{0x1C,0x6A},
	{0x37,0x48},
	{0x44,(0 <<7)},
	{0x17,210},
	{0x32,200},
}

-- i2s数据接收buffer
local rx_buff = zbuff.create(3200)

-- amr数据存放buffer，尽可能地给大一些
local amr_buff = zbuff.create(20 * 1024)
--创建一个amr的encoder
local encoder

-- 录音文件路径
local recordPath = "/record.amr"

-- i2s数据接收回调
local function record_cb(id, buff)
    if buff then
        log.info("I2S", id, "接收了", rx_buff:used())
        log.info("编码结果", codec.encode(encoder, rx_buff, amr_buff))		-- 对录音数据进行amr编码，成功的话这个接口会返回true, 默认编码等级为MR475
		record_cnt = record_cnt + 1
		if samplerate > 8000 then
			if record_cnt >= 50 then	--超过5秒后停止
				log.info("I2S", "stop") 
				i2s.stop(i2s_id)	
			end
		else
			if record_cnt >= 25 then	--超过5秒后停止
				log.info("I2S", "stop") 
				i2s.stop(i2s_id)	
			end
		end

    end
end

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


local function record_task()
	os.remove(recordPath)
	audio.config(0, 25, 1, 6, 200)						
	pm.power(pm.LDO_CTL, true)							-- 打开es8311芯片供电
	--自适应开发板，自己做的板子不需要2个I2C都用
	i2c.setup(0, i2c.FAST)
	i2c.setup(1, i2c.FAST)
	if i2c.send(0, 0x18, 0xfd) == true then
		log.info("音频小板", "codec on i2c0")
	end
	if i2c.send(1, 0x18, 0xfd) == true then
		log.info("云喇叭开发板", "codec on i2c1")
		power_pin = nil
		i2c_id = 1
	end

    for i, v in pairs(es8311_reg) do					-- 初始化es8311
        i2c.send(i2c_id, es8311_address, v, 1)
    end
	if samplerate > 8000 then
		encoder = codec.create(codec.AMR_WB, false, 7)
		if encoder == nil then
		log.info("不支持16K编码，改成8K采样")
			samplerate = 8000
			encoder = codec.create(codec.AMR, false, 7)
		end
	else
		encoder = codec.create(codec.AMR, false, 7)
	end
	
	i2s.setup(i2s_id, 1, samplerate, 16, 1, i2s.MODE_LSB)			-- 开启i2s
    i2s.on(i2s_id, record_cb) 								-- 注册i2s接收回调

    i2s.recv(i2s_id, rx_buff, 3200)
	i2c.send(i2c_id, es8311_address, {0x00, 0xc0}, 1)
    sys.wait(6000)
    i2c.send(i2c_id, es8311_address, {0x00, 0x80}, 1)			-- ES8311停止录音
    log.info("录音5秒结束")
	codec.release(encoder)
	codec = nil
	if samplerate > 8000 then
		io.writeFile(recordPath, "#!AMR-WB\n")					-- 向文件写入amr文件标识数据
	else
		io.writeFile(recordPath, "#!AMR\n")					-- 向文件写入amr文件标识数据
	end
	io.writeFile(recordPath, amr_buff:query(), "a+b")	-- 向文件写入编码后的amr数据
	i2s.setup(i2s_id, 0, 0, 0, 0, i2s.MODE_LSB)
   
	local result = audio.play(0, {recordPath})			-- 请求音频播放
	log.info("音频播放结果", result)
	if result then
		sys.waitUntil("AUDIO_PLAY_DONE")				-- 等待音频播放完毕
	else
														-- 音频播放出错	
	end

	-- 下面的演示是将音频文件发送到服务器上，如有需要，可以将下面代码注释打开，这里的url是合宙的文件上传测试服务器，上传的文件到http://tools.openluat.com/tools/device-upload-test查看
	--[[ 
		local timeTable = os.date("*t", os.time())
		local nowTime = string.format("%4d%02d%02d_%02d%02d%02d", timeTable.year, timeTable.month, timeTable.day, timeTable.hour, timeTable.min, timeTable.sec)
		local filename = mobile.imei() .. "_" .. nowTime .. ".amr"
		postMultipartFormData("http://tools.openluat.com/api/site/device_upload_file", filename, recordPath)
 	]]
	uart.setup(1, 115200)								-- 开启串口1
    uart.write(1, io.readFile(recordPath))				-- 向串口发送录音文件
end

sys.taskInit(record_task)