--[[
@module  mjpg_player
@summary MJPG视频播放器
@version 1.0.0
@date    2026.05.25
@author  拓毅恒
@usage
本模块使用AirUI框架实现MJPG视频播放功能：
1. 从 /luadb/fly_man_80.mjpg 加载视频
2. 使用 airui.video 组件播放视频
3. 支持循环播放

使用方法：
1. 将视频文件烧录到固件中
2. 在 main.lua 中 require "mjpg_player"
3. 上电后自动开始播放

注意事项：
1. 视频文件路径：/luadb/fly_man_80.mjpg
2. 适配 Air1601/1602 的 RGB 屏幕 1024x600
]]

-- ====================== 配置区域 ======================

-- 视频文件路径
local VIDEO_PATH = "/luadb/fly_man_80.mjpg"

-- 视频播放帧率
local VIDEO_FPS = 15

-- ====================== 视频播放函数 ======================

-- 使用AirUI播放视频
local function play_video_with_airui()
    log.info("播放器", "准备播放视频...")

    -- 检查视频文件是否存在
    if not io.exists(VIDEO_PATH) then
        log.error("播放器", "视频文件不存在:", VIDEO_PATH)
        return false
    end
    
    -- 检查视频文件大小
    local file_size = io.fileSize(VIDEO_PATH)
    log.info("播放器", "视频文件大小:", file_size, "字节")
    if file_size < 1000 then
        log.error("播放器", "视频文件太小，可能损坏:", file_size)
        return false
    end

    -- 获取LCD尺寸
    local lcd_width, lcd_height = lcd.getSize()
    log.info("播放器", "LCD尺寸:", lcd_width, "x", lcd_height)

    -- 获取视频实际分辨率
    log.info("播放器", "正在打开视频文件...")
    local temp_player, err = videoplayer.open(VIDEO_PATH)
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
        src = VIDEO_PATH,
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
