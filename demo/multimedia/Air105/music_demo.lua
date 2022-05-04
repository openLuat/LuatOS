--用2*2行列键盘实现切换歌曲，选择上一首，选择下一首，暂停/恢复
--用软件行列键盘，底层已经做好防抖了，如果用单独按键，自行处理
--当前选择上/下一首不会立刻生效，按切换歌曲才会生效，如果需要立刻生效，就取消相应注释即可
--[[
接线要求:

SPI 使用常规4线解法
Air105开发板         TF模块
PC9                  CS
PB12(SPI0_CLK)       CLK
PB14(SPI0_MISO)      MOSI
PB15(SPI0_MISO)      MISO
5V                   VCC
GND                  GND
]]
-- music文件夾，可以換成你自己的目录，不用加/sd/，demo里固定用TF卡目录，如果要本地目录，自行修改
local musicDir = "/music/"
local taskName = "task_audio"

local playList = {}
local curPlay = 0
local prePlay = 0
local nextPlay = 1
local tFiles = 0
local isPause = false
local MSG_MD = "moreData"   -- 播放缓存有空余
local MSG_PD = "playDone"   -- 播放完成所有数据
local MSG_NEW = "audioNew"  -- 播放新的歌曲

audio.on(0, function(id, event)
    if event == audio.MORE_DATA then
        sysplus.sendMsg(taskName, MSG_MD)
    else
        sysplus.sendMsg(taskName, MSG_PD)
    end
end)

local function moveNext()
    prePlay = curPlay
    curPlay = curPlay + 1
    if curPlay >= tFiles then
        curPlay = 0
    end
    nextPlay = curPlay + 1
    if nextPlay >= tFiles then
        nextPlay = 0
    end
    log.info("选择下一首")
    log.info("上一首", prePlay, playList[prePlay])
    log.info("选择", curPlay, playList[curPlay])
    log.info("下一首", nextPlay, playList[nextPlay])
end

local function movePre()
    nextPlay = curPlay
    curPlay = prePlay
    if prePlay > 0 then
        prePlay = prePlay - 1
    else
        prePlay = tFiles - 1
    end
    log.info("选择上一首")
    log.info("上一首", prePlay, playList[prePlay])
    log.info("选择", curPlay, playList[curPlay])
    log.info("下一首", nextPlay, playList[nextPlay])
end

local function task_cb(msg)
    log.info(msg[1], msg[2], msg[3], msg[4])
end

-- 用软件行列键盘，底层已经做好防抖了，如果用单独按键，自行处理
sys.subscribe("SOFT_KB_INC", function(port, data, state)
    -- log.info(data, state)
    -- 按下起效
    if state > 0 then
        if data == 0 then
            -- 开始播放或者立刻结束当前歌曲并播放下一首
            sysplus.sendMsg(taskName, MSG_NEW)
        elseif data == 1 then
            movePre()
            -- 如果需要立刻就切换歌曲就取消注释
            -- sysplus.sendMsg(taskName, MSG_NEW)
        elseif data == 16 then
            moveNext()
            -- 如果需要立刻就切换歌曲就取消注释
            -- sysplus.sendMsg(taskName, MSG_NEW)
        elseif data == 17 then
            isPause = not isPause
            audio.pause(0, isPause)
            log.info("暂停状态", isPause)
        end
    end
end)

local function audio_task()
    softkb.init(0, {pin.PD12, pin.PD13}, {pin.PE1, pin.PE2})
    local tagLen = 0
    local frameLen = 1152 * 4
    local spiId = 2
    local nowPlay
    local result = spi.setup(
        spiId,--串口id
        255, -- 不使用默认CS脚
        0,--CPHA
        0,--CPOL
        8,--数据宽度
        400*1000  -- 初始化时使用较低的频率
    )
    local isMP3 = false
    local TF_CS = pin.PB3
    gpio.setup(TF_CS, 1)
    -- fatfs.debug(1) -- 若挂载失败,可以尝试打开调试信息,查找原因
    fatfs.mount("SD", spiId, TF_CS, 24000000)
    -- fatfs.mount("SD", 0, TF_CS, 24000000)
    local data, err = fatfs.getfree("SD")
    local buff = zbuff.create(1024)
    local in_buff = zbuff.create(frameLen * 3 + 512)
    local isRun = false
    local result, AudioFormat, NumChannels, SampleRate, ByteRate, BlockAlign, BitsPerSample, is_signed

    if data then
        log.info("fatfs", "getfree", json.encode(data))
        local dir_nums, dir_info = fatfs.lsdir(musicDir)
        for k,v in pairs(dir_info) do
            if k:find(".mp3") or k:find(".MP3") or k:find(".wav") or k:find(".WAV") then
                log.info("找到",k)
                playList[tFiles] = k
                tFiles = tFiles + 1
            end
        end
        log.info("总共", tFiles)
        prePlay = tFiles - 1
        log.info("等待切换歌曲")
        sysplus.waitMsg(taskName, MSG_NEW)
        while true do
            isRun = false
            isMP3 = false
            nowPlay = curPlay
            log.info("开始播放")
            log.info("上一首", prePlay, playList[prePlay])
            log.info("当前", curPlay, playList[curPlay])
            log.info("下一首", nextPlay, playList[nextPlay])
            f = io.open("/sd".. musicDir .. playList[curPlay], "rb")
            if f then
                if playList[curPlay]:find(".mp3") or playList[curPlay]:find(".MP3") then
                    -- 解析MP3的必要信息
                    isMP3 = true
                    in_buff:del()
                    data = f:read(10)
                    if data:sub(1, 3) == 'ID3' then
                        in_buff:copy(nil, data)
                        tagLen = ((in_buff:query(6, 1, true) & 0x7f) << 21) + ((in_buff:query(7, 1, true) & 0x7f) << 14) + ((in_buff:query(8, 1, true) & 0x7f) << 7) + (in_buff:query(9, 1, true) & 0x7f)
                        log.info("jump head",  tagLen)
                        f:seek(SEEK_SET, tagLen)
                    end
                    in_buff:del()
                    data = f:read(frameLen)
                    codecr = codec.create(codec.MP3)
                    result, AudioFormat, NumChannels, SampleRate, BitsPerSample, is_signed = codec.get_audio_info(codecr, data)
                    if result then
                        log.info("mp3 info", NumChannels, SampleRate, BitsPerSample)
                        buff:resize(65536)
                        in_buff:copy(nil, data)
                        result = codec.get_audio_data(codecr, in_buff, buff)
                        log.debug("start", audio.start(0, AudioFormat, NumChannels, SampleRate, BitsPerSample, is_signed))
                        audio.write(0, buff)
                        data = f:read(frameLen)
                        in_buff:copy(nil, data) 
                        result = codec.get_audio_data(codecr, in_buff, buff)
                        audio.write(0, buff)
                        data = f:read(frameLen)
                        isRun = true        
                    else
                        log.debug("mp3解码失败!")
                    end
                else
                    isMP3 = false
                    data = nil
                    buff:del()
                    -- 解析WAV的必要信息
                    buff:copy(0, f:read(12))
                    if buff:query(0, 4) == 'RIFF' and buff:query(8, 4) == 'WAVE' then             
                        local total = buff:query(4, 4, false)
                        buff:copy(0, f:read(8))
                        if buff:query(0, 4) == 'fmt ' then      
                            buff:copy(0, f:read(16))
                            buff:seek(0, zbuff.SEEK_SET)
                            result, AudioFormat, NumChannels, SampleRate, ByteRate, BlockAlign, BitsPerSample = buff:unpack("<HHIIHH")
                            log.debug("find fmt info", AudioFormat, NumChannels, SampleRate, ByteRate, BlockAlign, BitsPerSample)
                            buff:copy(0, f:read(8))
                            if buff:query(0, 4) ~= 'data' then
                                buff:copy(0, buff:query(4, 4, false))
                                buff:copy(0, f:read(8))
                            end
                            log.debug("start", audio.start(0, AudioFormat, NumChannels, SampleRate, BitsPerSample))
                            SampleRate = (SampleRate * BlockAlign // 8) & ~(3)
                            log.info("size", SampleRate)
                            data = f:read(SampleRate)
                            audio.write(0, data)
                            data = f:read(SampleRate)
                            audio.write(0, data)
                            data = f:read(SampleRate)
                            isRun = true
                        end
                    else
                        log.debug("不正确的RIFF头", buff:query(0, 4), buff:query(8, 4))
                    end

                end
                if isRun then
                    while true do
                        local msg = sysplus.waitMsg(taskName, nil, 2000)
                        if type(msg) == 'table' then
                            if msg[1] == MSG_MD and isRun then
                                if isMP3 then
                                    if in_buff:used() >= frameLen * 2 then
                                        isRun = codec.get_audio_data(codecr, in_buff, buff)
                                        audio.write(0, buff)
                                    else
                                        data = f:read(frameLen)
                                        in_buff:copy(nil, data) 
                                        if #data ~= frameLen then
                                            isRun = codec.get_audio_data(codecr, in_buff, buff, false)
                                            log.info("解码结束")
                                            isRun = false
                                        else
                                            isRun = codec.get_audio_data(codecr, in_buff, buff)
                                        end
                                        audio.write(0, buff)
                                    end
                                else
                                    audio.write(0, data)
                                    data = f:read(SampleRate)
                                    if not data or #data == 0 then
                                        log.info("没有数据了")
                                        isRun = false
                                    end
                                end
                            elseif msg[1] == MSG_PD then
                                log.info("播放结束")
                                break
                            elseif msg[1] == MSG_NEW then
                                log.info("切换歌曲")
                                break
                            end
                        else
                            if not isPause then
                                log.error(type(msg), msg)
                            end
                        end
                    end
                end
                if isMP3 then
                    codec.release(codecr)
                end
                audio.stop(0)
                f:close()
            end
            -- 如果有底层的播放消息，也释放掉
            sysplus.waitMsg(taskName, MSG_MD, 10)
            sysplus.waitMsg(taskName, MSG_PD, 10)
            isPause = false
            log.info(rtos.meminfo("sys"))
            log.info(rtos.meminfo("lua"))
            if nowPlay == curPlay then
                prePlay = curPlay
                curPlay = curPlay + 1
                if curPlay >= tFiles then
                    curPlay = 0
                end
                nextPlay = curPlay + 1
                if nextPlay >= tFiles then
                    nextPlay = 0
                end
            end
        end
    else
        log.info("fatfs", "err", err)
    end
    sysplus.taskDel(taskName)
end

sysplus.taskInitEx(audio_task, taskName, task_cb)