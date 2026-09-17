PROJECT = "hzmp4_airui"
VERSION = "1.0.0"

sys.taskInit(function()
    local ret = airui.init(480, 320, airui.COLOR_FORMAT_ARGB8888)
    if not ret then
        log.error("hzmp4", "airui.init failed")
        os.exit(1)
    end

    local video = airui.video({
        x = 0,
        y = 0,
        w = 480,
        h = 320,
        src = "/luadb/mbappe-3s.hzmp4",
        backend = "videoplayer",
        decode_mode = "sw",
        loop = false,
        auto_play = true,
    })
    if not video then
        log.error("hzmp4", "airui.video open failed")
        os.exit(1)
    end

    sys.wait(1500)
    local mid = video:get_stats()
    log.info("hzmp4", "paced frames", mid.total_frames, "playing", mid.playing)
    local timing_ok = mid.total_frames >= 10 and mid.total_frames <= 18 and mid.playing

    sys.wait(2300)
    local stats = video:get_stats()
    log.info("hzmp4", "frames", stats.total_frames, "fps", stats.fps,
        "playing", stats.playing)
    -- AirUI 创建控件时会先解 1 帧作为静态预览；开始播放后统计剩余
    -- 29 帧。到 EOF 后 playing=false，因此合计正好验证了样本的 30 帧。
    local ok = timing_ok and stats.total_frames == 29 and not stats.playing
    video:destroy()
    if ok then
        log.info("hzmp4", "PASS: decoded 1 preview + 29 playback frames")
        os.exit(0)
    end
    log.error("hzmp4", "FAIL: expected 1 preview + 29 playback frames and EOF")
    os.exit(1)
end)

sys.run()
