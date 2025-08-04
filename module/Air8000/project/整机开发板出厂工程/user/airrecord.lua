local airrecord = {}
local airaudio  = require "airaudio"
local run_state = false

-- 录音状态
local RECORD_STATE = {
    IDLE = 0,        -- 空闲状态
    RECORDING = 1,   -- 录音中
    PLAYING = 2,     -- 播放中
    RECORDED = 3,    -- 已录制完成
    STOPPING = 4     -- 正在停止录音
}

local record_state = RECORD_STATE.IDLE
local recordPath = "/ram/record"
local last_record_time = 0
local last_play_time = 0
local stop_requested = false
local play_requested = false
local replay_requested = false
local record_success = false
local play_success = false

-- 开始录音
local function start_recording()
    log.info("airrecord", "开始录音")
    
    -- 删除之前的录音文件
    if io.exists(recordPath) then
        os.remove(recordPath)
    end
    
    -- 开始录音 - 0表示无限时长录制
    record_state = RECORD_STATE.RECORDING
    record_success = audio.record(0, audio.AMR, 0, 7, recordPath)
    last_record_time = os.time()
    
    return record_success
end

-- 停止录音
local function stop_recording()
    log.info("airrecord", "停止录音")
    record_state = RECORD_STATE.STOPPING
    return audio.recordStop(0)
end

-- 播放录音
local function play_recording()
    log.info("airrecord", "播放录音")
    record_state = RECORD_STATE.PLAYING
    play_success = audio.play(0, recordPath)
    last_play_time = os.time()
    return play_success
end

-- 重置录音状态
local function reset_recording()
    if record_state == RECORD_STATE.PLAYING then
        audio.playStop(0)
    elseif record_state == RECORD_STATE.RECORDING then
        audio.recordStop(0)
    end
    
    -- 删除录音文件
    if io.exists(recordPath) then
        os.remove(recordPath)
    end
    
    record_state = RECORD_STATE.IDLE
    record_success = false
    play_success = false
end

function airrecord.run()
    log.info("airrecord.run")
    lcd.setFont(lcd.font_opposansm12_chinese)
    run_state = true
    
    -- 初始化音频
    airaudio.init()
    
    -- 进入时自动开始录音
    if record_state == RECORD_STATE.IDLE then
        start_recording()
    end

    while run_state do
        sys.wait(100)
        
        -- 检查录音状态
        if record_state == RECORD_STATE.STOPPING then
            -- 检查录音文件是否存在
            if io.exists(recordPath) and io.fileSize(recordPath) > 0 then
                record_state = RECORD_STATE.RECORDED
            elseif os.time() - last_record_time > 2 then
                -- 超过2秒没有文件，认为录音失败
                record_state = RECORD_STATE.RECORDED
            end
        end
        
        -- 检查播放状态
        if record_state == RECORD_STATE.PLAYING then
            -- 检查播放是否完成
            if not play_success then
                -- 播放失败，回到完成状态
                record_state = RECORD_STATE.RECORDED
            elseif os.time() - last_play_time > 5 then
                -- 超过5秒，认为播放完成
                record_state = RECORD_STATE.RECORDED
            end
        end
        
        -- 处理用户请求
        if stop_requested then
            stop_recording()
            stop_requested = false
        elseif play_requested then
            play_recording()
            play_requested = false
        elseif replay_requested then
            reset_recording()
            start_recording()
            replay_requested = false
        end
        
        -- 更新UI
        lcd.clear(0xffff)
        lcd.showImage(0,0,"/luadb/return.jpg")  -- 返回按钮始终显示
        
        if record_state == RECORD_STATE.RECORDING then
            -- 录音中：显示停止按钮
            lcd.showImage(128,264,"/luadb/stop1.jpg")
            lcd.drawStr(112, 100, "录音中...", 0x0000, lcd.CENTER)
        elseif record_state == RECORD_STATE.RECORDED then
            -- 已录制：显示播放和重录按钮
            lcd.showImage(47,264,"/luadb/play.jpg")
            lcd.showImage(208,264,"/luadb/replay.jpg")
            lcd.drawStr(112, 100, "录音完成", 0x0000, lcd.CENTER)
            
            -- 显示文件信息
            if io.exists(recordPath) then
                local size = io.fileSize(recordPath)
                lcd.drawStr(112, 130, "大小: "..size.."字节", 0x0000, lcd.CENTER)
            end
        elseif record_state == RECORD_STATE.PLAYING then
            -- 播放中：显示播放状态
            lcd.drawStr(112, 100, "播放中...", 0x0000, lcd.CENTER)
        elseif record_state == RECORD_STATE.STOPPING then
            -- 停止中：显示提示信息
            lcd.drawStr(112, 100, "正在停止录音...", 0x0000, lcd.CENTER)
        end
        
        lcd.flush()
    end
    
    -- 退出时清理资源
    reset_recording()
    return true
end

function airrecord.tp_handal(x, y, event)
    -- 返回按钮
    if x > 0 and x < 137 and y > 0 and y < 64 then
        run_state = false
        return
    end
    
    -- 根据当前状态处理触摸事件
    if record_state == RECORD_STATE.RECORDING then
        -- 停止按钮
        if x > 128 and x < 192 and y > 264 and y < 358 then
            stop_requested = true
        end
    elseif record_state == RECORD_STATE.RECORDED then
        -- 播放按钮
        if x > 47 and x < 111 and y > 264 and y < 328 then
            play_requested = true
        -- 重录按钮
        elseif x > 208 and x < 272 and y > 264 and y < 328 then
            replay_requested = true
        end
    end
end

return airrecord