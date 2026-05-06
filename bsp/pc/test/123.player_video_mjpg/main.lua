
PROJECT = "player_video_mjpg"
VERSION = "1.0.0"

sys.taskInit(function()
    if lcd then lcd.init("gc9306x") end
    -- 打开MJPG视频文件, 逐帧解码后绘制到LCD, 这个文件很大, 没放在仓库里, 需要自己准备一个160x120分辨率的MJPG视频文件, 命名为video_160x120.mjpg, 放在运行目录下
    -- ffmpeg命令行是 ffmpeg -i input.mp4 -c:v mjpeg -q:v 5 -vf "scale=160:120" video_160x120.mjpg
    local player = videoplayer.open("video_160x120.mjpg")
    if not player then
        log.error("videoplayer", "打开视频失败")
        return
    end
    -- 开启调试信息
    -- videoplayer.debug(true)
    -- 获取视频信息
    local info = videoplayer.info(player)
    log.info("videoplayer", "分辨率", info.width, info.height)
    videoplayer.set_decode_mode(player, videoplayer.DECODE_SW)
    -- 逐帧解码并显示
    while true do
        log.info("videoplayer", "解码下一帧...")
        local ok, err = videoplayer.draw_frame(player, 0, 0)
        log.info("videoplayer", "draw_frame result", ok, err)
        lcd.flush()
        if err == "eof" then break end
        sys.wait(40) -- 约25fps
    end
    videoplayer.close(player)
    log.info("videoplayer", "播放完成")
    os.exit()
end)

sys.run()

