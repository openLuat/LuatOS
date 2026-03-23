PROJECT = "lcd_h264"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

sys.taskInit(function()
    if lcd then lcd.init("st7735s") end
    sys.wait(100)
    -- 打印一下mp4文件的大小
    log.info("h264", "MP4文件大小", io.fileSize("/luadb/video.mp4"))
    h264.debug(true)
    -- 打开MP4文件, 逐帧解码后绘制到LCD
    local fdec, err = h264.open_mp4("/luadb/video.mp4")
    if not fdec then
        log.error("h264", "打开MP4失败", err)
        return
    end
    local frame_id = 0
    while true do
        -- log.info("h264", "正在解码...")
        local frame, err = h264.read_frame(fdec)
        if err == "eof" then break end
        if frame then 
            frame_id = frame_id + 1
            log.info("h264", "帧", frame_id, frame.width, frame.height)
            sys.wait(30) -- 模拟每帧30ms的播放间隔
        end
    end
    h264.close_file(fdec)
    log.info("h264", "播放完成")
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!

