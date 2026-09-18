PROJECT = "hzv_airui"
VERSION = "1.0.0"

sys.taskInit(function()
    local ret = airui.init(480, 320, airui.COLOR_FORMAT_ARGB8888)
    if not ret then
        log.error("hzv", "airui.init failed")
        os.exit(1)
    end

    local video = airui.video({
        x = 0,
        y = 0,
        w = 480,
        h = 320,
        src = "/luadb/mbappe-3s.hzv",
        backend = "videoplayer",
        decode_mode = "sw",
        loop = false,
        auto_play = true,
    })
    if not video then
        log.error("hzv", "airui.video open failed")
        os.exit(1)
    end

    -- PC 的 WASAPI 设备首次打开可能耗时约 0.5~1 秒；开始计数后视频应跟随
    -- DMA sample counter，而不是从创建控件时提前跑。
    sys.wait(2500)
    local mid = video:get_stats()
    log.info("hzv", "paced frames", mid.total_frames, "audio_pts", mid.audio_pts_ms,
        "av_delta", mid.av_delta_ms, "clock", mid.clock_mode, "playing", mid.playing)
    local timing_ok = mid.total_frames >= 8 and mid.total_frames <= 22 and
        mid.clock_mode == "sample-counter" and mid.playing

    sys.wait(2500)
    local stats = video:get_stats()
    log.info("hzv", "frames", stats.total_frames, "fps", stats.fps,
        "playing", stats.playing)
    -- AirUI 创建控件时会先解 1 帧作为静态预览；开始播放后统计剩余
    -- 29 帧。到 EOF 后 playing=false，因此合计正好验证了样本的 30 帧。
    local ok = timing_ok and (stats.total_frames + stats.dropped_frames) == 29 and not stats.playing
    video:destroy()
    if ok then
        log.info("hzv", "PASS: audio sample clock + 29 scheduled frames", "dropped", stats.dropped_frames)
        os.exit(0)
    end
    log.error("hzv", "FAIL: expected 1 preview + 29 playback frames and EOF")
    os.exit(1)
end)

sys.run()
