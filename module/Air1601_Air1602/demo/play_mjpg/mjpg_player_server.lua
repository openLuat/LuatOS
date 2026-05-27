--[[
@module  mjpg_player_server
@summary MJPG视频播放器 - 服务器下载播放模式
@version 1.0.0
@date    2026.05.25
@author  拓毅恒
@usage
本模块实现从HTTP服务器下载MJPG视频并播放的功能：
1. 从服务器下载视频到 /ram/server_video.mjpg
2. 使用 airui.video 组件播放视频
3. 支持循环播放

使用方法：
1. 需要插入SIM卡并连接网络
2. 在 main.lua 中 require "mjpg_player_server"
3. 上电后自动下载并播放

注意事项：
1. 服务器视频URL：https://appstoreoss.luatos.com/iot-apps/res/100197/video_160x160.mjpg
2. 视频保存路径：/ram/server_video.mjpg
3. 适配 Air1601/1602 的 RGB 屏幕 1024x600
]]

-- ====================== 配置区域 ======================

-- 服务器视频URL
local SERVER_VIDEO_URL = "https://appstoreoss.luatos.com/iot-apps/res/100197/video_160x160.mjpg"

-- 下载后保存路径
local DOWNLOADED_VIDEO_PATH = "/ram/server_video.mjpg"

-- 视频播放帧率
local VIDEO_FPS = 15

-- ====================== 视频下载函数 ======================

-- 从服务器下载视频
local function download_video()
    log.info("播放器", "从服务器下载视频:", SERVER_VIDEO_URL)

    -- 等待网络就绪
    log.info("播放器", "等待网络连接...")
    while not socket.adapter(socket.dft()) do
        sys.waitUntil("IP_READY", 1000)
    end
    log.info("播放器", "网络已就绪")

    -- 清理旧文件
    if io.exists(DOWNLOADED_VIDEO_PATH) then
        os.remove(DOWNLOADED_VIDEO_PATH)
        log.info("播放器", "删除旧视频文件")
    end

    -- 下载视频文件
    log.info("播放器", "开始下载...")
    local code, headers, body_size = http.request("GET", SERVER_VIDEO_URL, nil, nil,
        {dst = DOWNLOADED_VIDEO_PATH, timeout = 60000}).wait()

    if code ~= 200 then
        log.error("播放器", "下载失败, code:", code)
        return false
    end

    log.info("播放器", "下载完成, 大小:", body_size, "字节")

    -- 检查文件
    local actual_size = io.fileSize(DOWNLOADED_VIDEO_PATH)
    if actual_size ~= body_size then
        log.error("播放器", "文件大小不一致, 预期:", body_size, "实际:", actual_size)
        return false
    end

    return true
end

-- ====================== 视频播放函数 ======================

-- 使用AirUI播放视频
local function play_video_with_airui()
    log.info("播放器", "准备播放视频...")

    -- 下载视频
    if not download_video() then
        log.error("播放器", "下载视频失败")
        return false
    end

    -- 获取LCD尺寸
    local lcd_width, lcd_height = lcd.getSize()
    log.info("播放器", "LCD尺寸:", lcd_width, "x", lcd_height)

    -- 获取视频实际分辨率
    log.info("播放器", "正在打开视频文件...")
    local temp_player, err = videoplayer.open(DOWNLOADED_VIDEO_PATH)
    local video_width, video_height = 160, 160
    if temp_player then
        log.info("播放器", "视频文件打开成功")
        local info = videoplayer.info(temp_player)
        if info then
            video_width = info.width
            video_height = info.height
            log.info("播放器", "视频实际分辨率:", video_width, "x", video_height)
        else
            log.warn("播放器", "无法获取视频信息，使用默认尺寸 160x160")
        end
        videoplayer.close(temp_player)
    else
        log.error("播放器", "无法打开视频文件:", err)
        log.warn("播放器", "使用默认尺寸 160x160")
    end

    -- 计算居中显示位置
    local x = math.floor((lcd_width - video_width) / 2)
    local y = math.floor((lcd_height - video_height) / 2)
    if x < 0 then x = 0 end
    if y < 0 then y = 0 end

    log.info("播放器", "视频显示位置:", x, y)

    -- 创建全屏黑色背景容器
    local screen_container = airui.container({
        x = 0,
        y = 0,
        w = lcd_width,
        h = lcd_height,
        color = 0x000000,
    })

    if not screen_container then
        log.error("播放器", "创建屏幕容器失败")
        return false
    end

    -- 创建视频容器
    local video_container = airui.container({
        parent = screen_container,
        x = x,
        y = y,
        w = video_width,
        h = video_height,
        color = 0x000000,
    })

    if not video_container then
        log.error("播放器", "创建视频容器失败")
        return false
    end

    -- 创建 airui.video 组件
    local interval = math.floor(1000 / VIDEO_FPS)
    local video_component = airui.video({
        parent = video_container,
        x = 0,
        y = 0,
        src = DOWNLOADED_VIDEO_PATH,
        format = "mjpg",
        interval = interval,
        loop = true
    })

    if not video_component then
        log.error("播放器", "创建视频组件失败")
        return false
    end

    log.info("播放器", "视频组件创建成功")

    -- 开始播放
    video_component:play()
    log.info("播放器", "视频开始播放")

    -- 保持任务运行
    while true do
        sys.wait(1000)
    end
end

-- ====================== 播放器主任务 ======================

-- 播放器初始化任务
local function player_task()
    log.info("播放器", "初始化LCD和AirUI...")
    if not lcd_drv.init() then
        log.error("播放器", "LCD初始化失败")
        return
    end

    -- 开始播放视频
    play_video_with_airui()
end

-- 启动播放器任务
sys.taskInit(player_task)
