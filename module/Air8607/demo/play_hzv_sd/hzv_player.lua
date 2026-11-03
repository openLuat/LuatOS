--[[
@module  hzv_player
@summary HZV 音视频播放引擎应用功能模块（airui.video 播放控制 + 功放 + 播放统计）
@version 1.1
@date    2026.10.30
@author  江访
@usage
本文件为 Air8607 播放 SD 卡 HZV 素材 demo 的播放引擎应用功能模块，核心业务逻辑为：
1、按 HZV 素材的真实分辨率在屏幕内居中创建 airui.video 组件；
2、组件参数固定为 format="hzv"、backend="videoplayer"、decode_mode="hw"、loop=false、auto_play=false；
3、先设置软件音量、再拉高功放 PA、最后调用 video:play 开始播放；
4、建一个"返回列表"按钮放在画面右上角，点按钮或点画面都发出 HZV_BACK_REQ 消息回到选择页；
5、on_complete 回调置位播放结束标记，轮播任务按模式换下一条素材或者发消息回列表；
6、统计任务定时读取 video:get_stats，打印帧率、总帧数、音视频偏差、丢帧数、音频欠载次数；
7、播放前后补回触摸 I2C 总线配置，避免播放音视频之后触摸不响应。

HZV 的音画同步由底层引擎完成，Lua 侧不需要设置 interval，也不需要定时调用 step/skip。

本文件的对外接口有5个：
1、hzv_player.set_playlist(files)：保存素材列表，播放从这张表里取
2、hzv_player.play_one(index)：播放列表里的第 index 条，播完发消息回选择页
3、hzv_player.play_all：从第一条开始顺序轮播整张表，轮完发消息回选择页
4、hzv_player.stop：停止播放并销毁视频组件、关闭功放
5、hzv_player.stats：返回 video:get_stats 的结果，没有播放时返回 nil
]]

local lcd_app = require "lcd_app"
local tp_app  = require "tp_app"

local M = {}

-- Air8607 功放使能脚 = GPIO73（AUDIOPA_EN），HT6873 高电平使能
local PIN_PA       = 73
local PA_ON_LEVEL  = 1

-- 软件音量，100 表示原始音量，取值范围 0~1000
local SPEAKER_VOLUME = 70

-- 播放统计的打印间隔，单位 ms
local T_STATS = 2000

-- 轮播任务的检查间隔，单位 ms
local T_ROTATE = 500

-- "返回列表"按钮的尺寸与边距
local BACK_BTN_W = 200
local BACK_BTN_H = 56
local BACK_BTN_PAD = 24

-- "返回列表"按钮的底色
local COL_BACK_BTN = 0xC0392B

-- 当前视频组件
local video = nil

-- "返回列表"按钮，起播时创建、返回时销毁
local back_btn = nil

-- 当前播放的素材路径与素材名
local cur_path = nil
local cur_name = nil

-- 播放列表、当前下标与播放模式，模式 one 表示只播一条，all 表示顺序轮播整张表
local playlist   = nil
local play_index = 1
local play_mode  = "one"

-- on_complete 置位的播放结束标记，由轮播任务消费
local play_done = false

-- 轮播与统计任务的运行标志，stop 之后两个任务一起退出
local running = false

--[[
打开或关闭功放 PA；

@summary 按 PA_ON_LEVEL 换算实际输出电平，打开时输出有效电平，关闭时输出相反电平

@param boolean on true 打开功放，false 关闭功放
@return nil
]]
local function pa_set(on)
    local level = on and PA_ON_LEVEL or (1 - PA_ON_LEVEL)
    gpio.setup(PIN_PA, level)
    log.info("hzv_player", on and "功放打开" or "功放关闭", "GPIO" .. PIN_PA, "电平", level)
end

--[[
设置喇叭软件音量；

@summary 调用 audio_v2.soft_volume，固件没有这个接口时只打印告警，不影响播放

@return boolean 设置成功返回 true，失败返回 false
]]
local function set_volume()
    if not rawget(_G, "audio_v2") or not audio_v2.soft_volume then
        log.warn("hzv_player", "固件不支持 audio_v2.soft_volume，音量维持固件默认值")
        return false
    end

    local ok = audio_v2.soft_volume(SPEAKER_VOLUME)
    if ok then
        log.info("hzv_player", "软件音量设置", SPEAKER_VOLUME, "100 为原始音量")
    else
        log.warn("hzv_player", "软件音量设置失败", SPEAKER_VOLUME)
    end
    return ok
end

--[[
读取一次视频分辨率；

@summary 用 videoplayer 打开素材读视频信息后立即关闭，只做尺寸探测

@param string path HZV 素材路径
@return table 成功返回 {w=, h=}，失败返回 nil
]]
local function probe_read_size(path)
    local player = videoplayer.open(path)
    if not player then
        return nil
    end

    local info = videoplayer.info(player)
    videoplayer.close(player)
    if info and info.width and info.height then
        return { w = info.width, h = info.height }
    end
    return nil
end

--[[
探测 HZV 素材的真实分辨率；

@summary 固件没有 videoplayer 库或探测失败时返回 nil，由调用方按屏幕尺寸兜底

@param string path HZV 素材路径
@return number 视频宽度，探测失败返回 nil
@return number 视频高度，探测失败返回 nil
]]
local function probe_size(path)
    if not rawget(_G, "videoplayer") or not videoplayer.open then
        return nil
    end

    local ok, size = pcall(probe_read_size, path)
    if ok and size then
        log.info("hzv_player", "探测到视频分辨率", size.w .. "x" .. size.h)
        return size.w, size.h
    end
    log.warn("hzv_player", "视频分辨率探测失败，按屏幕尺寸创建组件")
    return nil
end

--[[
销毁视频组件本体；

@summary 组件对象失效时用 pcall 兜住，不把任务带崩

@param table v airui.video 组件对象
@return nil
]]
local function destroy_video(v)
    v:destroy()
end

--[[
销毁视频组件本体；

@summary 组件对象失效时用 pcall 兜住，不把任务带崩

@param table b airui.button 组件对象
@return nil
]]
local function destroy_button(b)
    b:destroy()
end

--[[
"返回列表"按钮的点击回调；

@summary 发出回到素材选择页的消息，由 main.lua 收消息做页面切换

@param userdata sender 被点中的按钮

@return nil
]]
local function on_back_click(sender)
    log.info("hzv_player", "点返回按钮，回到素材选择页")
    sys.publish("HZV_BACK_REQ")
end

--[[
视频画面的点击回调；

@summary 点画面等同于点"返回列表"按钮

@param userdata sender 被点中的视频组件

@return nil
]]
local function on_video_click(sender)
    log.info("hzv_player", "点视频画面，回到素材选择页")
    sys.publish("HZV_BACK_REQ")
end

--[[
建立"返回列表"按钮；

@summary 按屏幕宽高算出右上角坐标后创建，覆盖在视频画面之上

@return nil
]]
local function build_back_btn()
    local screen_w, screen_h = lcd_app.get_size()
    back_btn = airui.button({
        x         = screen_w - BACK_BTN_W - BACK_BTN_PAD,
        y         = BACK_BTN_PAD,
        w         = BACK_BTN_W,
        h         = BACK_BTN_H,
        text      = "返回列表",
        font_size = 22,
        style     = {
            bg_color   = COL_BACK_BTN,
            text_color = 0xFFFFFF,
            radius     = 10,
        },
        on_click  = on_back_click,
    })
    if not back_btn then
        log.warn("hzv_player", "返回按钮创建失败，只能点视频画面返回")
    end
end

--[[
销毁"返回列表"按钮；

@return nil
]]
local function destroy_back_btn()
    if not back_btn then
        return
    end
    pcall(destroy_button, back_btn)
    back_btn = nil
end

--[[
销毁当前视频组件与返回按钮；

@summary 释放解码通道占用的内存并关闭功放，换素材或返回列表时调用

@return nil
]]
local function destroy_player()
    destroy_back_btn()

    if not video then
        return
    end

    pcall(destroy_video, video)
    video = nil
    cur_path = nil
    cur_name = nil
    pa_set(false)

    -- 音视频通路会重配 I2C1，收尾后补回触摸总线配置
    tp_app.recover()
end

--[[
播放结束回调；

@summary 组件读到文件尾且 loop=false 时由 AirUI 调用，只置位结束标记，
          换素材的动作交给轮播任务做

@return nil
]]
local function on_play_complete()
    play_done = true
end

--[[
读取一次播放统计；

@summary get_stats 是 AirUI V1.2.6 之后新增的接口，老固件没有，用 pcall 兼容

@param table v airui.video 组件对象
@return table 统计表
]]
local function read_stats(v)
    return v:get_stats()
end

--[[
打印一次播放统计；

@summary 帧率、总帧数、音视频偏差、丢帧数、音频欠载次数一起打进日志

@return nil
]]
local function print_stats()
    local stats = M.stats()
    if not stats then
        return
    end

    log.info("hzv_player", "播放统计",
        "fps=" .. tostring(stats.fps),
        "总帧数=" .. tostring(stats.total_frames),
        "音视频偏差(ms)=" .. tostring(stats.av_delta_ms),
        "丢帧=" .. tostring(stats.dropped_frames),
        "音频欠载=" .. tostring(stats.audio_underruns),
        "解码模式=" .. tostring(stats.decode_mode))
end

--[[
打开并播放一个 HZV 素材；

@summary 销毁旧组件后按素材分辨率居中创建新组件，先设音量和功放再 play

@param string path HZV 素材路径
@param string name 素材文件名，打进日志用
@return boolean 打开成功返回 true，失败返回 false
]]
local function open_player(path, name)
    if not io.exists(path) then
        log.error("hzv_player", "素材不存在", path)
        return false
    end
    log.info("hzv_player", "素材大小", path,
        math.floor((io.fileSize(path) or 0) / 1024) .. "KB")

    -- 换素材时先销毁旧组件，避免多个解码通道同时占用内存
    destroy_player()

    local screen_w, screen_h = lcd_app.get_size()
    local vw, vh = probe_size(path)

    -- airui.video 不支持缩放，素材比屏幕大时按屏幕裁上限
    vw = math.min(vw or screen_w, screen_w)
    vh = math.min(vh or screen_h, screen_h)

    -- 在屏幕内居中
    local vx = math.floor((screen_w - vw) / 2)
    local vy = math.floor((screen_h - vh) / 2)

    -- 不传 parent 时组件挂在当前屏上，全屏播放不需要指定父对象
    video = airui.video({
        x           = vx,
        y           = vy,
        w           = vw,
        h           = vh,
        src         = path,
        format      = "hzv",         -- HZV 容器，音画同步由底层引擎完成
        backend     = "videoplayer", -- 走 videoplayer 后端（HZV reader + JPEG 解码 + Audio V2）
        decode_mode = "hw",          -- 硬解优先，拿不到硬解时底层回退软解
        loop        = false,         -- 播到文件尾触发 on_complete，由轮播任务决定下一步
        auto_play   = false,         -- 由本模块控制播放时机，先设音量、开功放再 play
        on_complete = on_play_complete,
        on_click    = on_video_click,
    })

    if not video then
        log.error("hzv_player", "创建视频组件失败", path,
            "请确认固件已开启 LUAT_USE_AIRUI / VIDEOPLAYER / HZV / JPEG_DECODE_HW / AUDIO_V2")
        return false
    end

    cur_path = path
    cur_name = name
    log.info("hzv_player", "视频组件创建成功", path,
        "位置", vx, vy, "尺寸", vw .. "x" .. vh)

    set_volume()
    -- 先打开功放再播放，避免第一帧音频被 PA 建立时间吞掉
    pa_set(true)
    video:play()
    log.info("hzv_player", "video:play", path)

    -- 播放之后补回触摸总线配置，保证画面右上角的返回按钮点得动
    tp_app.recover()

    -- 返回按钮建在视频之后，保证盖在画面最上层
    build_back_btn()
    return true
end

--[[
轮播模式下换下一条素材；

@summary 一条打不开就跳到下一条，一轮内全部打不开时返回 false

@return boolean 换到可播的素材返回 true，整轮都打不开返回 false
]]
local function rotate_to_next()
    local tried = 0
    while tried < #playlist do
        play_index = play_index + 1
        if play_index > #playlist then
            play_index = 1
        end
        tried = tried + 1

        local item = playlist[play_index]
        log.info("hzv_player", "开始播放", play_index .. "/" .. #playlist, item.path)
        if open_player(item.path, item.name) then
            return true
        end
        log.warn("hzv_player", "素材打开失败，换下一条", item.path)
    end

    log.error("hzv_player", "一轮内全部素材都打不开，回到素材选择页")
    return false
end

--[[
轮播任务；

@summary 定时检查播放结束标记，单条模式发消息回列表，轮播模式换下一条或整轮结束回列表

@return nil
]]
local function rotate_task()
    while running do
        if play_done then
            play_done = false

            if play_mode == "all" and rotate_to_next() then
                -- 已经换到下一条，继续播
            else
                running = false
                sys.publish("HZV_BACK_REQ")
            end
        end
        sys.wait(T_ROTATE)
    end
    log.info("hzv_player", "轮播任务退出")
end

--[[
播放统计任务；

@summary 定时读取 video:get_stats 并打印，播放期间持续输出

@return nil
]]
local function stats_task()
    while running do
        sys.wait(T_STATS)
        if running then
            print_stats()
        end
    end
end

--[[
启动一次播放；

@summary 置好运行标志后播当前下标，起播成功才拉起轮播与统计任务

@return boolean 起播成功返回 true，失败返回 false
]]
local function start_playback()
    if not playlist or #playlist == 0 then
        log.error("hzv_player", "播放列表为空，无法播放")
        return false
    end
    if play_index < 1 or play_index > #playlist then
        play_index = 1
    end

    play_done = false
    running   = true

    local item = playlist[play_index]
    log.info("hzv_player", "开始播放", play_index .. "/" .. #playlist, item.path)
    if not open_player(item.path, item.name) then
        running = false
        return false
    end

    sys.taskInit(rotate_task)
    sys.taskInit(stats_task)
    return true
end

--[[
播放列表里的第 index 条素材；

@api hzv_player.play_one(index)

@summary 只播这一条，读到文件尾后发出 HZV_BACK_REQ 消息回到素材选择页

@param number index 素材序号，从 1 开始，由 file_list 的点选消息带过来

@return boolean 起播成功返回 true，序号越界或起播失败返回 false

@usage
hzv_player.play_one(2)
]]
function M.play_one(index)
    if not playlist or #playlist == 0 then
        log.error("hzv_player", "播放列表为空，无法播放")
        return false
    end
    if type(index) ~= "number" or index < 1 or index > #playlist then
        log.error("hzv_player", "素材序号越界", tostring(index))
        return false
    end

    play_mode  = "one"
    play_index = index
    return start_playback()
end

--[[
顺序播放整张素材表；

@api hzv_player.play_all()

@summary 从第一条开始按顺序播，整轮播完后发出 HZV_BACK_REQ 消息回到素材选择页

@return boolean 起播成功返回 true，起播失败返回 false

@usage
hzv_player.play_all()
]]
function M.play_all()
    if not playlist or #playlist == 0 then
        log.error("hzv_player", "播放列表为空，无法播放")
        return false
    end

    play_mode  = "all"
    play_index = 1
    return start_playback()
end

--[[
设置播放列表；

@api hzv_player.set_playlist(files)

@summary 保存素材列表，play_one 与 play_all 都按这张表取素材

@param table files 素材列表，每项为 {path=, name=, size=}，由 sd_app.list_hzv 提供

@return boolean 设置成功返回 true，列表为空返回 false

@usage
hzv_player.set_playlist(sd_app.list_hzv())
]]
function M.set_playlist(files)
    if type(files) ~= "table" or #files == 0 then
        log.error("hzv_player", "没有可播放的 HZV 素材")
        return false
    end
    playlist = files
    log.info("hzv_player", "播放列表已设置", "素材数量" .. #files)
    return true
end

--[[
停止播放；

@api hzv_player.stop()

@summary 停止轮播任务，销毁视频组件与返回按钮并关闭功放，可重复调用

@return nil

@usage
hzv_player.stop()
]]
function M.stop()
    running   = false
    play_done = false
    destroy_player()
    log.info("hzv_player", "播放已停止")
end

--[[
查询播放统计；

@api hzv_player.stats()

@summary 返回 video:get_stats 的结果，没有播放或固件过老时返回 nil

@return table 统计表或 nil

@usage
local stats = hzv_player.stats()
if stats then
    log.info("hzv_player", "fps", stats.fps)
end
]]
function M.stats()
    if not video then
        return nil
    end

    local ok, stats = pcall(read_stats, video)
    if ok then
        return stats
    end
    return nil
end

return M
