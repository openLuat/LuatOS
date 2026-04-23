PROJECT = "dac_audio_test"
VERSION = "2.0.1"
local function dac_cb(id, event, param)
    log.info("dac_cb", id, event, param)
end

local file_buff

function air160x_test()
    gpio.setup(12, 0)	--开发版PA要低电平开启
    dac.on(dac_cb)		--注册回调函数
    dac.open(0, 16000, 16, 0)
    local len = io.fileSize("/luadb/test_16k.raw")	--音频文件必须是有符号16bit，单声道，无压缩音频数据，不能有任何形式的文件头，文件尾
    file_buff = zbuff.create(len)
    local f = io.open("/luadb/test_16k.raw")
    if f then
        f:fill(file_buff)
    end
    file_buff:seek(len,zbuff.SEEK_CUR)
    dac.prepare(0, file_buff)	--有符号数据转成DAC需要的无符号数据
    dac.write(0, file_buff, true)	--循环播放
end
air160x_test()
sys.run()
