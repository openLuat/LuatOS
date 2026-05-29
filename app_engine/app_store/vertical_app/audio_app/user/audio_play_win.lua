--[[
@module  audio_play_win
@summary 音频播放窗口
@version 1.0.0
@date    2026.05.27
@usage
音频播放页面，提供：
1、文件列表显示
2、存储位置切换（内存/SD卡）
3、播放控制（播放/停止）
4、播放状态显示

订阅"OPEN_AUDIO_PLAY_WIN"事件打开窗口
]]

local audio_play_win = {}

-- 窗口ID
local win_id = nil

-- UI控件
local ui_controls = {}

-- 加载audio_core模块
local audio_core = nil

local SCREEN_W = 480
local SCREEN_H = 800

-- 颜色定义
local COLOR_BG = 0x1A1A2E
local COLOR_CARD_BG = 0x252542
local COLOR_TEXT_PRIMARY = 0xFFFFFF
local COLOR_TEXT_SECONDARY = 0x8B8B9E
local COLOR_ACCENT = 0x4A90E2
local COLOR_SUCCESS = 0x10B981
local COLOR_ERROR = 0xF43F5E
local COLOR_BUTTON_GREEN = 0x22C55E
local COLOR_BUTTON_RED = 0xEF4444
local COLOR_ITEM_SELECTED = 0x4A90E2
local COLOR_ITEM_NORMAL = 0x2D3748

-- 播放状态
local is_playing = false
local current_file = nil
local selected_index = 1
local storage_location = "memory" -- "内存" 或 "sd"

-- 音频文件列表
local file_list = {}

-- 文件列表项控件
local file_items = {}

--[[
扫描音频文件
]]
local function scan_audio_files()
    -- 清空文件列表
    file_list = {}
    
    -- 音频文件扩展名
    local audio_extensions = {".mp3", ".amr", ".pcm", ".wav"}
    
    -- 根据存储位置确定扫描路径
    local scan_path, path_name
    if storage_location == "memory" then
        scan_path = "/luadb/"
        path_name = "内存目录"
    else
        scan_path = "/sd/"
        path_name = "SD卡目录"
    end
    
    -- 扫描目标目录
    log.info("audio_play", "扫描", path_name, ":", scan_path)
    local ret, data = io.lsdir(scan_path, 50, 0)
    
    if ret and data then
        log.info("audio_play", path_name, "扫描成功，找到", #data, "个文件")
        for _, entry in ipairs(data) do
            local name = entry.name
            if name and entry.type == 0 then
                log.info("audio_play", "扫描到文件:", name)
                local lower_name = name:lower()
                for _, ext in ipairs(audio_extensions) do
                    if lower_name:match(ext .. "$") then
                        local file_path = scan_path .. name
                        table.insert(file_list, {
                            name = name,
                            path = file_path
                        })
                        log.info("audio_play", "添加音频文件:", name, "路径:", file_path)
                        break
                    end
                end
            end
        end
    else
        log.warn("audio_play", path_name, "扫描失败或为空")
    end
    
    -- 如果没有找到文件，添加提示
    if #file_list == 0 then
        file_list = {{ name = "暂无音频文件", path = "" }}
    end
    
    log.info("audio_play", "扫描完成，共找到", #file_list, "个音频文件")
    return file_list
end

--[[
更新文件列表显示
]]
local function update_file_list()
    for i, item in ipairs(file_items) do
        if i == selected_index then
            item.container:set_color(COLOR_ITEM_SELECTED)
            item.name_label:set_color(0xFFFFFF)
        else
            item.container:set_color(COLOR_ITEM_NORMAL)
            item.name_label:set_color(COLOR_TEXT_PRIMARY)
        end
    end
    
    -- 更新当前文件显示
    if ui_controls.current_file_label and file_list[selected_index] then
        ui_controls.current_file_label:set_text(file_list[selected_index].name)
    end
end

--[[
更新播放状态显示
]]
local function update_play_status()
    if ui_controls.status_label then
        if is_playing then
            ui_controls.status_label:set_text("正在播放...")
            ui_controls.status_label:set_color(COLOR_SUCCESS)
        else
            ui_controls.status_label:set_text("已停止")
            ui_controls.status_label:set_color(COLOR_TEXT_SECONDARY)
        end
    end
    
    -- 更新按钮状态
    if ui_controls.play_btn then
        ui_controls.play_btn:set_color(is_playing and 0x16A34A or COLOR_BUTTON_GREEN)
    end
end

--[[
创建文件列表项
]]
local function create_file_item(parent, y, index, file_info)
    local item = {}
    
    -- 容器
    item.container = airui.container({
        parent = parent,
        x = 20,
        y = y,
        w = 440,
        h = 50,
        color = (index == selected_index) and COLOR_ITEM_SELECTED or COLOR_ITEM_NORMAL,
        radius = 8,
    })
    
    -- 文件名
    item.name_label = airui.label({
        parent = item.container,
        x = 15,
        y = 15,
        w = 400,
        h = 20,
        text = file_info.name,
        font_size = 16,
        color = (index == selected_index) and 0xFFFFFF or COLOR_TEXT_PRIMARY,
        align = "left",
    })
    
    -- 点击事件
    item.container:set_on_click(function()
        selected_index = index
        update_file_list()
        log.info("audio_play", "选中文件:", file_info.name)
    end)
    
    return item
end

--[[
切换存储位置
]]
local function toggle_storage()
    -- 先切换存储位置
    if storage_location == "memory" then
        storage_location = "sd"
        if ui_controls.storage_label then
            ui_controls.storage_label:set_text("SD卡")
        end
        log.info("audio_play", "切换到SD卡存储")
    else
        storage_location = "memory"
        if ui_controls.storage_label then
            ui_controls.storage_label:set_text("内存")
        end
        log.info("audio_play", "切换到内存存储")
    end
    
    -- 重新扫描文件并更新列表
    file_list = scan_audio_files()
    selected_index = 1
    
    -- 刷新文件列表显示
    -- 先销毁旧的列表项
    for _, item in ipairs(file_items) do
        if item.container then
            item.container:destroy()
        end
    end
    file_items = {}
    
    -- 重新创建文件列表项
    if ui_controls.list_container then
        for i, file_info in ipairs(file_list) do
            local item_y = 10 + (i - 1) * 60
            file_items[i] = create_file_item(ui_controls.list_container, item_y, i, file_info)
        end
    else
        log.error("audio_play", "列表容器不存在")
    end
    
    update_file_list()
end

--[[
播放选中文件
]]
local function play_selected()
    if not file_list[selected_index] then
        return
    end
    
    local file = file_list[selected_index]
    
    -- 检查是否是提示项
    if file.path == "" then
        log.warn("audio_play", "没有可播放的文件")
        return
    end
    
    current_file = file
    
    log.info("audio_play", "开始播放:", file.name, "路径:", file.path)
    
    -- 加载audio_core模块
    if not audio_core then
        audio_core = require "audio_core"
    end
    
    -- 调用audio_core播放文件
    local ok = audio_core.play_file(file.path, function()
        -- 播放完成回调
        log.info("audio_play", "播放完成:", file.name)
        is_playing = false
        update_play_status()
    end)
    
    if ok then
        is_playing = true
        log.info("audio_play", "播放启动成功")
    else
        is_playing = false
        log.error("audio_play", "播放启动失败")
    end
    
    update_play_status()
end

--[[
停止播放
]]
local function stop_playback()
    log.info("audio_play", "停止播放")
    
    -- 调用audio_core停止播放
    if audio_core then
        audio_core.stop_play()
    end
    
    is_playing = false
    current_file = nil
    
    update_play_status()
end

--[[
返回按钮点击
]]
function audio_play_win.go_back()
    log.info("audio_play", "返回主界面")
    stop_playback()
    if win_id then
        exwin.close(win_id)
        win_id = nil
    end
end

--[[
创建界面
]]
function audio_play_win.on_create()
    log.info("audio_play", "创建音频播放界面")
    
    -- 创建主容器
    ui_controls.main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = COLOR_BG,
    })
    
    -- ==================== 顶部标题栏 ====================
    local header = airui.container({
        parent = ui_controls.main_container,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = 60,
        color = COLOR_CARD_BG,
    })
    
    -- 标题
    airui.label({
        parent = header,
        x = 20,
        y = 18,
        w = 200,
        h = 24,
        text = "音频播放",
        font_size = 20,
        color = COLOR_TEXT_PRIMARY,
        align = "left",
    })
    
    -- 返回按钮
    local close_btn = airui.button({
        parent = header,
        x = 400,
        y = 10,
        w = 60,
        h = 30,
        text = "返回",
        font_size = 14,
        text_color = 0xFFFFFF,
        bg_color = 0xF44336,
        bg_color_pressed = 0xD32F2F,
        border_color = 0xFFFFFF,
        border_width = 1,
        radius = 4,
        on_click = function()
            audio_play_win.go_back()
        end
    })
    
    -- ==================== 存储位置选择 ====================
    airui.label({
        parent = ui_controls.main_container,
        x = 20,
        y = 80,
        w = 100,
        h = 20,
        text = "存储位置:",
        font_size = 16,
        color = COLOR_TEXT_SECONDARY,
        align = "left",
    })
    
    local storage_btn = airui.container({
        parent = ui_controls.main_container,
        x = 120,
        y = 75,
        w = 80,
        h = 32,
        color = COLOR_ACCENT,
        radius = 6,
    })
    ui_controls.storage_label = airui.label({
        parent = storage_btn,
        x = 0,
        y = 7,
        w = 80,
        h = 18,
        text = "内存",
        font_size = 14,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER,
    })
    storage_btn:set_on_click(function()
        toggle_storage()
    end)
    
    -- ==================== 文件列表区域 ====================
    -- 先扫描音频文件
    scan_audio_files()
    
    ui_controls.list_container = airui.container({
        parent = ui_controls.main_container,
        x = 0,
        y = 120,
        w = SCREEN_W,
        h = 280,
        color = COLOR_BG,
    })
    local list_container = ui_controls.list_container
    
    -- 创建文件列表项
    file_items = {}
    for i, file_info in ipairs(file_list) do
        local item_y = 10 + (i - 1) * 60
        file_items[i] = create_file_item(list_container, item_y, i, file_info)
    end
    
    -- ==================== 底部控制区 ====================
    local control_panel = airui.container({
        parent = ui_controls.main_container,
        x = 0,
        y = 600,
        w = SCREEN_W,
        h = 200,
        color = COLOR_BG,
    })
    
    -- 当前文件标签
    airui.label({
        parent = control_panel,
        x = 20,
        y = 20,
        w = 100,
        h = 20,
        text = "当前文件:",
        font_size = 14,
        color = COLOR_TEXT_SECONDARY,
        align = "left",
    })
    
    ui_controls.current_file_label = airui.label({
        parent = control_panel,
        x = 110,
        y = 20,
        w = 350,
        h = 20,
        text = file_list[selected_index] and file_list[selected_index].name or "",
        font_size = 14,
        color = COLOR_TEXT_PRIMARY,
        align = "left",
    })
    
    -- 播放按钮
    ui_controls.play_btn = airui.container({
        parent = control_panel,
        x = 40,
        y = 60,
        w = 180,
        h = 50,
        color = COLOR_BUTTON_GREEN,
        radius = 8,
    })
    airui.label({
        parent = ui_controls.play_btn,
        x = 0,
        y = 15,
        w = 180,
        h = 20,
        text = "播放",
        font_size = 18,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER,
    })
    ui_controls.play_btn:set_on_click(function()
        play_selected()
    end)
    
    -- 停止按钮
    ui_controls.stop_btn = airui.container({
        parent = control_panel,
        x = 260,
        y = 60,
        w = 180,
        h = 50,
        color = COLOR_BUTTON_RED,
        radius = 8,
    })
    airui.label({
        parent = ui_controls.stop_btn,
        x = 0,
        y = 15,
        w = 180,
        h = 20,
        text = "停止",
        font_size = 18,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER,
    })
    ui_controls.stop_btn:set_on_click(function()
        stop_playback()
    end)
    
    -- 播放状态
    ui_controls.status_label = airui.label({
        parent = control_panel,
        x = 230,
        y = 130,
        w = SCREEN_W,
        h = 20,
        text = "已停止",
        font_size = 16,
        color = COLOR_TEXT_SECONDARY,
        align = "center",
    })
end

--[[
销毁界面
]]
function audio_play_win.on_destroy()
    log.info("audio_play", "销毁音频播放界面")
    
    -- 停止播放
    if is_playing then
        stop_playback()
    end
    
    -- 销毁文件列表项控件
    for _, item in ipairs(file_items) do
        if item.container then
            item.container:destroy()
        end
    end
    file_items = {}
    
    -- 销毁主容器
    if ui_controls.main_container then
        ui_controls.main_container:destroy()
    end
    
    -- 清理控件引用
    ui_controls = {}
    win_id = nil
    
    -- 重置状态
    is_playing = false
    current_file = nil
    selected_index = 1
    file_list = {}
end

--[[
失去焦点
]]
function audio_play_win.on_lose_focus()
    log.info("audio_play", "失去焦点")
end

--[[
获得焦点
]]
function audio_play_win.on_get_focus()
    log.info("audio_play", "获得焦点")
end

--[[
打开窗口处理函数
]]
local function open_handler()
    win_id = exwin.open({
        on_create = audio_play_win.on_create,
        on_destroy = audio_play_win.on_destroy,
        on_lose_focus = audio_play_win.on_lose_focus,
        on_get_focus = audio_play_win.on_get_focus,
    })
end

-- 订阅打开窗口事件
sys.subscribe("OPEN_AUDIO_PLAY_WIN", open_handler)

-- 设为全局变量
_G.audio_play_win = audio_play_win

return audio_play_win