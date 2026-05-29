--[[
@module  audio_main_win
@summary 音频系统主窗口
]]

local win_id = nil
local main_container = nil
local destroyed = false

local SCREEN_W = 480
local SCREEN_H = 800

-- 颜色定义
local COLOR_BG = 0x1A1A2E
local COLOR_CARD_BG = 0x252542
local COLOR_TEXT_PRIMARY = 0xFFFFFF
local COLOR_TEXT_SECONDARY = 0x8B8B9E
local COLOR_ACCENT = 0xFF4757
local COLOR_VOLUME_BAR = 0x4A90E2
local COLOR_VOLUME_BG = 0x3A3A5C
local COLOR_SUCCESS = 0x10B981
local COLOR_ERROR = 0xF43F5E

-- 音频系统状态
local audio_state = false
local volume = 75
local sd_mounted = false

-- UI元素引用
local volume_label = nil
local volume_bar = nil
local system_status_label = nil
local sd_status_label = nil
local init_progress_bar = nil
local init_progress_label = nil
local system_switch = nil

-- 加载audio_core模块
local audio_core = nil

-- 加载窗口管理模块
local exwin = exwin
if not exwin then
    exwin = require "exwin"
end

-- 更新音量显示
local function update_volume_display()
    if volume_label then
        volume_label:set_text(volume .. "%")
    end
    if volume_bar then
        volume_bar:set_value(volume, true)
    end
end



-- 更新SD卡状态显示
local function update_sd_status()
    if sd_status_label then
        sd_status_label:set_text(sd_mounted and "SD 已挂载" or "SD 未挂载")
        sd_status_label:set_color(sd_mounted and COLOR_SUCCESS or COLOR_TEXT_SECONDARY)
    end
end

-- 更新初始化进度显示
local function update_init_progress(percent, message)
    if init_progress_bar then
        init_progress_bar:set_value(percent, true)
    end
    if init_progress_label then
        init_progress_label:set_text(message)
    end
end

-- 显示/隐藏初始化进度条
local function show_init_progress(show)
    if init_progress_bar then
        if show then
            init_progress_bar:set_value(0, false)
        else
            init_progress_bar:set_value(0, false)
        end
    end
    if init_progress_label then
        init_progress_label:set_text(show and "准备..." or " ")
    end
end

-- 异步初始化音频系统（带进度条）
local function init_audio_async()
    sys.taskInit(function()
        -- 加载audio_core模块
        if not audio_core then
            audio_core = require "audio_core"
        end

        -- 显示进度条
        show_init_progress(true)

        -- 使用带进度回调的初始化（audio_core内部会处理SD卡挂载）
        local ok = audio_core.init(function(percent, message)
            update_init_progress(percent, message)
            sys.wait(10)
        end)

        -- 隐藏进度条
        show_init_progress(false)

        if ok then
            audio_core.set_volume(volume)
            log.info("audio", "音频系统已开启")
            if system_status_label then
                system_status_label:set_text("ON")
                system_status_label:set_color(COLOR_SUCCESS)
            end
            -- 刷新SD卡状态
            local data = fatfs.getfree("/sd")
            if data then
                sd_mounted = true
            else
                sd_mounted = false
            end
        else
            audio_state = false
            -- 初始化失败，将开关状态重置
            if system_switch then
                system_switch:set_state(false)
            end
            if system_status_label then
                system_status_label:set_text("OFF")
                system_status_label:set_color(COLOR_ERROR)
            end
            log.error("audio", "音频系统初始化失败")
        end

        update_sd_status()
    end)
end

--[[
切换音频系统开关
]]
local function toggle_audio_system()
    audio_state = not audio_state
    -- 开启音频系统
    if audio_state then
        init_audio_async()
    else
        -- 关闭音频系统
        if audio_core then
            audio_core.deinit()
        end
        log.info("audio", "音频系统已关闭")
        if system_status_label then
            system_status_label:set_text("OFF")
            system_status_label:set_color(COLOR_ERROR)
        end
        -- 关闭时SD卡显示未挂载
        sd_mounted = false
        update_sd_status()
    end
end

-- 创建返回按钮
local function create_back_button(parent)
    local back_btn = airui.container({
        parent = parent,
        x = SCREEN_W - 80,
        y = 20,
        w = 60,
        h = 36,
        color = COLOR_ACCENT,
        radius = 8,
        on_click = function()
            log.info("audio", "返回按钮点击")
            if win_id then
                exwin.close(win_id)
            end
        end
    })
    
    airui.label({
        parent = back_btn,
        x = 0,
        y = 8,
        w = 60,
        h = 20,
        text = "返回",
        font_size = 14,
        color = COLOR_TEXT_PRIMARY,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    return back_btn
end

-- 创建音频系统开关卡片
local function create_system_card(parent)
    local card = airui.container({
        parent = parent,
        x = 20,
        y = 80,
        w = SCREEN_W - 40,
        h = 70,
        color = COLOR_CARD_BG,
        radius = 12,
    })
    
    if not card then
        return nil
    end
    
    -- 开关按钮
    system_switch = airui.switch({
        parent = card,
        x = 20,
        y = 20,
        w = 50,
        h = 30,
        checked = audio_state,
        on_color = COLOR_VOLUME_BAR,
        off_color = COLOR_VOLUME_BG,
        on_change = function(self, checked)
            toggle_audio_system()
        end
    })
    
    -- 标题
    airui.label({
        parent = card,
        x = 85,
        y = 12,
        w = 120,
        h = 24,
        text = "音频系统",
        color = COLOR_TEXT_PRIMARY,
        font_size = 16,
        align = "left",
    })
    
    -- 状态文字
    system_status_label = airui.label({
        parent = card,
        x = 85,
        y = 38,
        w = 60,
        h = 20,
        text = audio_state and "ON" or "OFF",
        color = audio_state and COLOR_SUCCESS or COLOR_ERROR,
        font_size = 14,
        align = "left",
    })
    
    -- 初始化进度条（默认隐藏）
    init_progress_bar = airui.bar({
        parent = card,
        x = 120,
        y = 38,
        w = 140,
        h = 12,
        value = 0,
    })
    
    -- 初始化进度标签
    init_progress_label = airui.label({
        parent = card,
        x = 265,
        y = 35,
        w = 80,
        h = 16,
        text = " ",
        font_size = 11,
        color = COLOR_VOLUME_BAR,
    })
    
    -- SD卡状态
    sd_status_label = airui.label({
        parent = card,
        x = SCREEN_W - 140,
        y = 25,
        w = 100,
        h = 20,
        text = sd_mounted and "SD 已挂载" or "SD 未挂载",
        color = sd_mounted and COLOR_SUCCESS or COLOR_TEXT_SECONDARY,
        font_size = 14,
        align = "right",
    })
    
    return card
end

-- 创建音量控制卡片
local function create_volume_card(parent)
    local card = airui.container({
        parent = parent,
        x = 20,
        y = 180,
        w = SCREEN_W - 40,
        h = 120,
        color = COLOR_CARD_BG,
        radius = 12,
    })
    
    if not card then
        return nil
    end
    
    -- 标题
    airui.label({
        parent = card,
        x = 20,
        y = 15,
        w = 80,
        h = 24,
        text = "主音量",
        color = COLOR_TEXT_PRIMARY,
        font_size = 16,
        align = "left",
    })
    
    -- 音量百分比
    volume_label = airui.label({
        parent = card,
        x = SCREEN_W - 100,
        y = 15,
        w = 60,
        h = 24,
        text = volume .. "%",
        color = COLOR_VOLUME_BAR,
        font_size = 16,
        align = "right",
    })
    
    -- 减号按钮
    local minus_btn = airui.button({
        parent = card,
        x = 20,
        y = 55,
        w = 44,
        h = 44,
        text = "-",
        color = COLOR_VOLUME_BAR,
        text_color = COLOR_TEXT_PRIMARY,
        radius = 8,
        font_size = 24,
    })
    
    if minus_btn then
        minus_btn:set_on_click(function()
            volume = math.max(0, volume - 5)
            log.info("audio", "音量减小:", volume)
            update_volume_display()
            if audio_core and audio_state then
                audio_core.set_volume(volume)
            end
        end)
    end
    
    -- 音量滑块（使用airui.bar）
    volume_bar = airui.bar({
        parent = card,
        x = 74,
        y = 65,
        w = SCREEN_W - 40 - 148,
        h = 24,
        value = volume,
        indicator_color = COLOR_VOLUME_BAR,
    })
    
    -- 音量滑块可点击区域
    local function set_volume_from_position(pos)
        volume = pos * 5
        if volume < 0 then volume = 0 end
        if volume > 100 then volume = 100 end
        update_volume_display()
        if audio_core and audio_state then
            audio_core.set_volume(volume)
        end
    end
    
    -- 创建20个分段点击区域（5%一分段）
    local bar_width = SCREEN_W - 40 - 148
    local segment_width = math.floor(bar_width / 20)
    for i = 0, 19 do
        local segment = airui.container({
            parent = card,
            x = 74 + i * segment_width,
            y = 55,
            w = segment_width,
            h = 44,
            opacity = 0,
        })
        segment:set_on_click(function()
            set_volume_from_position(i + 1)
        end)
    end
    
    -- 加号按钮
    local plus_btn = airui.button({
        parent = card,
        x = SCREEN_W - 40 - 64,
        y = 55,
        w = 44,
        h = 44,
        text = "+",
        color = COLOR_VOLUME_BAR,
        text_color = COLOR_TEXT_PRIMARY,
        radius = 8,
        font_size = 24,
    })
    
    if plus_btn then
        plus_btn:set_on_click(function()
            volume = math.min(100, volume + 5)
            log.info("audio", "音量增大:", volume)
            update_volume_display()
            if audio_core and audio_state then
                audio_core.set_volume(volume)
            end
        end)
    end
    
    return card
end

-- 创建功能按钮卡片
local function create_function_card(parent, y, icon_path, title, subtitle, callback)
    local card = airui.container({
        parent = parent,
        x = 20,
        y = y,
        w = SCREEN_W - 40,
        h = 90,
        color = COLOR_CARD_BG,
        radius = 12,
    })
    
    if not card then
        return nil
    end
    
    -- 图标
    airui.image({
        parent = card,
        x = 20,
        y = 15,
        w = 60,
        h = 60,
        src = icon_path,
    })
    
    -- 标题
    airui.label({
        parent = card,
        x = 95,
        y = 18,
        w = 200,
        h = 28,
        text = title,
        color = COLOR_TEXT_PRIMARY,
        font_size = 20,
        align = "left",
    })
    
    -- 副标题
    airui.label({
        parent = card,
        x = 95,
        y = 50,
        w = 250,
        h = 22,
        text = subtitle,
        color = COLOR_TEXT_SECONDARY,
        font_size = 14,
        align = "left",
    })
    
    -- 点击区域
    card:set_on_click(function()
        log.info("audio", title .. " 点击")
        if callback then
            callback()
        end
    end)
    
    return card
end

-- 创建UI
local function create_ui()
    if destroyed then
        return
    end
    
    -- 创建主容器
    main_container = airui.container({
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = COLOR_BG,
    })
    
    if not main_container then
        log.error("audio", "创建主容器失败")
        return
    end
    
    -- 创建返回按钮
    create_back_button(main_container)
    
    -- 创建音频系统开关卡片
    create_system_card(main_container)
    
    -- 创建音量控制卡片
    create_volume_card(main_container)
    
    -- 创建播放音频卡片
    create_function_card(
        main_container,
        330,
        "/luadb/play_audio.png",
        "播放音频",
        "播放MP3/AMR/PCM文件",
        function()
            if audio_state then
                sys.publish("OPEN_AUDIO_PLAY_WIN")
                log.info("audio", "打开播放音频界面")
            else
                log.warn("audio_main", "请先开启音频系统")
                -- 在UI上显示提示
                local tip_label = airui.label({
                    parent = main_container,
                    x = 100,
                    y = 400,
                    w = 280,
                    h = 40,
                    text = "请先开启音频系统",
                    color = COLOR_ERROR,
                    font_size = 16,
                    align = "center",
                })
                -- 2秒后自动消失
                sys.taskInit(function()
                    sys.wait(2000)
                    if tip_label then
                        tip_label:destroy()
                    end
                end)
            end
        end
    )
    
    -- 底部版本信息
    airui.label({
        parent = main_container,
        x = 165,
        y = SCREEN_H - 40,
        w = 200,
        h = 30,
        text = "AUDIO SYSTEM v1.0",
        color = COLOR_TEXT_SECONDARY,
        font_size = 14,
        align = "center",
    })
    
    log.info("audio", "UI创建完成")
end

-- 窗口创建回调
local function on_create()
    destroyed = false
    create_ui()
end

-- 窗口销毁回调
local function on_destroy()
    destroyed = true
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    win_id = nil
    volume_label = nil
    volume_bar = nil
    system_status_label = nil
    sd_status_label = nil
    init_progress_bar = nil
    init_progress_label = nil
    system_switch = nil
    -- 关闭音频系统
    if audio_state and audio_core then
        audio_core.deinit()
        audio_state = false
    end
end

-- 窗口获得焦点回调
local function on_get_focus()
    log.info("audio", "窗口获得焦点")
    -- 刷新SD卡状态
    if audio_state then
        local data = fatfs.getfree("/sd")
        if data then
            sd_mounted = true
        else
            sd_mounted = false
        end
        update_sd_status()
    end
end

-- 窗口失去焦点回调
local function on_lose_focus()
    log.info("audio", "窗口失去焦点")
end

-- 打开窗口
local function open_handler()
    if win_id then
        log.warn("audio", "窗口已存在")
        return
    end
    
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy
    })
    
    log.info("audio", "窗口ID", win_id)
end

-- 订阅打开窗口事件
sys.subscribe("OPEN_AUDIO_WIN", open_handler)

-- 外部调用打开窗口
function audio_open()
    open_handler()
end

-- 外部调用关闭窗口
function audio_close()
    if win_id then
        exwin.close(win_id)
    end
end

log.info("audio_main_win", "模块加载完成")
