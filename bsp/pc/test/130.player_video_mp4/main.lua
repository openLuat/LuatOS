PROJECT = "player_video_mp4"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 演示: 通过 videoplayer 库播放 MP4 视频文件
local MP4_FILE = "1763942672.mp4"

sys.taskInit(function()
    sys.wait(100)

    videoplayer.debug(true)

    log.info("vp", "MP4文件大小", io.fileSize(MP4_FILE))

    local player = videoplayer.open(MP4_FILE)
    if not player then
        log.error("vp", "打开MP4失败")
        return
    end

    local frame_id = 0
    local max_frames = 999
    while frame_id < max_frames do
        local frame, err = videoplayer.read_frame(player)
        if err == "eof" then
            log.info("vp", "播放完成, 共", frame_id, "帧")
            break
        end
        if frame then
            frame_id = frame_id + 1
            if frame_id == 1 then
                log.info("vp", "分辨率", frame.width, frame.height,
                         "数据长度", #frame.data)
            elseif frame_id % 30 == 0 then
                log.info("vp", "已解码", frame_id, "帧")
            end
        else
            log.warn("vp", "帧解码失败", err)
        end
        sys.wait(1) -- 尽快解码，验证功能
    end

    videoplayer.close(player)
    log.info("vp", "播放完成")
    os.exit(0)
end)

sys.run()
