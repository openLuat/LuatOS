local taskName = "call"
local calling = {}

function calling.publishMsg(param1, param2, param3, param4)
    sysplus.sendMsg(taskName, param1, param2, param3, param4)
end

--[[ 
    CC_STATE
        PLAY_DONE           音频播放结束
        CC_READY            通话功能准备OK
        CC_DONE             无论何种原因的通话结束
        INCOMINGCALL        来电
        CONNECTED           通话建立
        CALL_KEY            按键1
        POWER_KEY           按键2
]]

audio.on(0, function(id, event)
    -- 使用play来播放文件时只有播放完成回调
    local succ, stop, file_cnt = audio.getError(0)
    if not succ then
        if stop then
            log.info("用户停止播放")
        else
            log.info("第", file_cnt, "个文件解码失败")
        end
    end
    sysplus.sendMsg(taskName, "CC_STATE", "PLAY_DONE")
end)
sys.subscribe("CC_IND", function(state)
    log.info("cc state", state)
    if state == "READY" then
        sys.publish("CC_READY")
        sysplus.sendMsg(taskName, "CC_STATE", state)
    elseif state == "INCOMINGCALL" then
        log.info("cc.lastNum", cc.lastNum())
        sysplus.sendMsg(taskName, "CC_STATE", state)
    elseif state == "HANGUP_CALL_DONE" or state == "MAKE_CALL_FAILED" or state == "DISCONNECTED" then
        sysplus.sendMsg(taskName, "CC_STATE", "CC_DONE")
        audio.pm(0, audio.STANDBY)
        -- audio.pm(0,audio.SHUTDOWN)	--低功耗可以选择SHUTDOWN或者POWEROFF，如果codec无法断电用SHUTDOWN
    elseif state == "CONNECTED" then
        sysplus.sendMsg(taskName, "CC_STATE", "CONNECTED")
    end
end)

local list = {{
    name = "测试1",
    num = "xxxxxxxxxx"
}, {
    name = "测试2",
    num = "xxxxxxxxxx"
}}
local function findVaildNum(list, num)
    for index, v in ipairs(list) do
        if num == v.num then
            return index
        end
    end
    return false
end


sysplus.taskInitEx(function()
    local multimedia_id = 0
    local i2c_id = 0
    local i2s_id = 0
    local i2s_mode = 0
    local i2s_sample_rate = 16000
    local i2s_bits_per_sample = 16
    local i2s_channel_format = i2s.MONO_R
    local i2s_communication_format = i2s.MODE_LSB
    local i2s_channel_bits = 16
    local pa_pin = 16
    local pa_on_level = 1
    local pa_delay = 100
    local power_pin = 8
    local power_on_level = 1
    local power_delay = 3
    local power_time_delay = 100
    local voice_vol = 50
    local mic_vol = 65
    local find_es8311 = false
    i2c.setup(i2c_id, i2c.FAST)
	pm.power(pm.LDO_CTL, false)  --开发板上ES8311由LDO_CTL控制上下电
    sys.wait(10)
    pm.power(pm.LDO_CTL, true)  --开发板上ES8311由LDO_CTL控制上下电
	sys.wait(1000)
    if i2c.send(i2c_id, 0x18, 0xfd) == true then
        log.info("音频小板或内置ES8311", "codec on i2c0")
        find_es8311 = true
    end

    if not find_es8311 then
        while true do
            log.info("not find es8311")
            sys.wait(1000)
        end
    end

    i2s.setup(i2s_id, i2s_mode, i2s_sample_rate, i2s_bits_per_sample, i2s_channel_format, i2s_communication_format, i2s_channel_bits)

    audio.config(multimedia_id, pa_pin, pa_on_level, power_delay, pa_delay, power_pin, power_on_level, power_time_delay)
    audio.setBus(multimedia_id, audio.BUS_I2S, {
        chip = "es8311",
        i2cid = i2c_id,
        i2sid = i2s_id,
        voltage = audio.VOLTAGE_1800
    }) -- 通道0的硬件输出通道设置为I2S

    audio.vol(multimedia_id, voice_vol)
    audio.micVol(multimedia_id, mic_vol)
    audio.debug(true)
    cc.init(multimedia_id)
    audio.pm(0, audio.STANDBY)
    sys.waitUntil("CC_READY")

    local mode, index, ret, callList = "IDLE", 0, nil, {}
    local ttsDone = true
    local isSelect = false
    while true do
        if mode == "IDLE" then
            index = 1
            ret = sysplus.waitMsg(taskName, nil, nil)
            log.info("IDLE", ret[1], ret[2])
            if ret[2] == "INCOMINGCALL" then -- 来电
                local num = cc.lastNum() -- 获取来电号码
                index = findVaildNum(callList, num) -- 如果号码有效，则进入准备通话状态，无效则挂断
                -- if index then
                    mode = "PREPARE"
                --     local result = audio.tts(0, callList[index].name .. "电话")
                --     log.info("tts result", result)
                -- else
                --     mode = "DISCONNECTING"
                -- end
            elseif ret[2] == "CALL_KEY" then -- 主动拨号
                callList = fskv.get("phoneList")
                if not callList or #callList <= 0 then -- 联系人列表为空，则回到IDLE状态
                    audio.tts(0, "未设置联系人列表")
                    mode = "IDLE"
                else -- 联系人列表不为空，则进入等待呼叫状态
                    mode = "WAIT_CALLING"
                end
            elseif ret[2] == "PLAY_DONE" then
                ttsDone = true
            end
        elseif mode == "WAIT_CALLING" then -- 等待呼叫
            ret = sysplus.waitMsg(taskName, nil, 4000)
            if not ret then -- 等待超时，拨打当前选中的联系人，默认为第一个
                if not isSelect then
                    isSelect = true
                    audio.tts(0, "正在拨打" .. string.fromHex(callList[index].name) .. "的电话")
                end
                -- cc.dial(0, callList[index].num)
                -- mode = "CALLING"
            elseif ret[2] == "CALL_KEY" then -- 按下拨号键，则选择下一个联系人
                if ttsDone then
                    index = index + 1
                    if index > #callList then
                        index = 1
                    end
                    ttsDone = false
                    audio.playStop(0)
                    local result = audio.tts(0, "即将呼叫" .. string.fromHex(callList[index].name))
                    log.info("即将呼叫", callList[index].name, callList[index].num)
                end
            elseif ret[2] == "POWER_KEY" then -- 按下开机键，则挂断
                audio.playStop(0)
                mode = "DISCONNECTING"
            elseif ret[2] == "PLAY_DONE" then
                ttsDone = true
                if isSelect then
                    isSelect = false
                    mode = "CALLING"
                    cc.dial(0, callList[index].num)
                end
            elseif ret[2] == "CC_DONE" then -- 通话结束，回到IDLE
                audio.playStop(0)
                mode = "IDLE"
            end
        elseif mode == "CALLING" then -- 拨号中
            ret = sysplus.waitMsg(taskName, nil, nil)
            if ret[2] == "CC_DONE" or ret[2] == "POWER_KEY" then -- 通话结束或开机键按下，走到挂断流程
                mode = "DISCONNECTING"
            elseif ret[2] == "CONNECTED" then -- 收到通话建立消息，则进入通话中状态
                mode = "CONNECTING"
            end
        elseif mode == "PREPARE" then -- 准备通话
            ret = sysplus.waitMsg(taskName, nil, nil)
            log.info("PREPARE", ret[1], ret[2])
            if ret[2] == "CALL_KEY" then -- 按下拨号键，接听，则进入通话中状态
                audio.playStop(0)
                cc.accept(0)
                mode = "CONNECTING"
            elseif ret[2] == "POWER_KEY" then -- 按下开机键，走到挂断流程
                audio.playStop(0)
                mode = "DISCONNECTING"
            elseif ret[2] == "PLAY_DONE" then -- 播放完毕，循环播放
                ttsDone = true
                local result = audio.tts(0, string.fromHex(callList[index].name .. "电话"))
                log.info("tts result", result)
            elseif ret[2] == "CC_DONE" then -- 通话结束，回到IDLE
                audio.playStop(0)
                mode = "IDLE"
            end
        elseif mode == "CONNECTING" then -- 通话中
            ret = sysplus.waitMsg(taskName, nil, nil)
            log.info("CONNECTING", ret[1], ret[2])
            if ret[2] == "POWER_KEY" then -- 按下开机键，走到挂断流程
                mode = "DISCONNECTING"
            elseif ret[2] == "CC_DONE" then -- 通话结束，回到IDLE
                mode = "IDLE"
            end
        elseif mode == "DISCONNECTING" then -- 挂断流程
            cc.hangUp(0) -- 挂断电话
            ret = sysplus.waitMsg(taskName, nil, 10000)
            log.info("DISCONNECTING", ret[1], ret[2])
            if not ret or ret[2] == "CC_DONE" then -- 通话结束或者超时没有等到挂断结束的消息，回到IDLE
                mode = "IDLE"
            elseif ret[2] == "PLAY_DONE" then
                ttsDone = true
            end
        end
    end
end, taskName)

-- 按键1, 红色SOS按钮
gpio.setup(0, function()
    log.info("callme", "拨号键触发, 拨打电话")
    sysplus.sendMsg(taskName, "CC_STATE", "CALL_KEY")
end, gpio.PULLDOWN, gpio.RISING)
gpio.debounce(0, 1000)

return calling
