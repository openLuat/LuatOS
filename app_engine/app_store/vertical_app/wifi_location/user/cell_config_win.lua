--[[
@module  cell_config_win
@summary 基站定位配置页面
@version 1.0
@date    2026.04.01
@author  您的名字
@usage
本模块为基站定位配置页面，用于设置项目的key_id和key。
订阅"OPEN_CELL_CONFIG_WIN"事件打开窗口。
]]
local cell_config_win = {}
local win_id = nil
local main_container, content
local key_id_input, key_input

-- 配置状态
local config = {
    key_id = "",
    key = ""
}

-- 配置文件名
local CONFIG_FILE = "/cell_config.json"

function cell_config_win.get_config()
    return config
end

--[[
加载配置

@local
@function load_config
@return nil
@usage
-- 内部调用，从文件加载配置
]]
local function load_config()
    local file, err = io.open(CONFIG_FILE, "r")
    if file then
        local content = file:read("*a")
        file:close()
        
        local loaded_config = json.decode(content)
        if loaded_config then
            -- 合并加载的配置到默认配置
            for k, v in pairs(loaded_config) do
                config[k] = v
            end
            log.info("CELL_CONFIG", "配置加载成功")
        else
            log.warn("CELL_CONFIG", "配置文件解析失败")
        end
    else
        log.warn("CELL_CONFIG", "配置文件不存在，使用默认配置")
    end
end

--[[
保存配置

@local
@function save_config
@return nil
@usage
-- 内部调用，保存配置到文件
]]
local function save_config()
    local content = json.encode(config)
    local file, err = io.open(CONFIG_FILE, "w")
    if file then
        file:write(content)
        file:close()
        log.info("CELL_CONFIG", "配置保存成功")
    else
        log.error("CELL_CONFIG", "配置保存失败: " .. err)
    end
end

--[[
创建窗口UI

@local
@function create_ui
@return nil
@usage
-- 内部调用，创建配置页面的UI
]]
local function create_ui()
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=480, h=800, color=0x0f172a })
    
    -- 顶部返回栏
    local header = airui.container({ parent = main_container, x=0, y=0, w=480, h=60, color=0x1e293b })
    
    -- 返回按钮
    local back_btn = airui.container({ parent = header, x = 10, y = 10, w = 100, h = 40, color=0x38bdf8, radius = 5,
        on_click = function()
            if win_id then
                exwin.close(win_id)
            end
        end
    })
    airui.label({ parent = back_btn, x=20, y=15, w=60, h=20, text="返回", font_size=16, color=0xfefefe, align = airui.TEXT_ALIGN_CENTER })
    
    -- 标题
    airui.label({ parent = header, x=120, y=10, w=240, h=40, text="基站定位配置", font_size=24, color=0x38bdf8, align = airui.TEXT_ALIGN_CENTER })
    
    content = airui.container({ parent = main_container, x=0, y=60, w=480, h=740, color=0x1e293b })
    
    -- 加载配置
    load_config()
    
    -- 配置内容区域
    local config_content = airui.container({ parent = content, x=0, y=0, w=480, h=740, color=0x1e293b })
    
    -- 装饰性线条
    airui.container({ parent = config_content, x=10, y=10, w=460, h=1, color=0x38bdf8, radius = 0.5 })
    
    -- 项目配置区域
    local project_section = airui.container({ parent = config_content, x=10, y=10, w=460, h=300, color=0x0f172a, radius = 8 })
    airui.label({ parent = project_section, x=10, y=5, w=100, h=20, text="项目配置", font_size=12, color=0x94a3b8, align = airui.TEXT_ALIGN_LEFT })
    
    -- 创建文本虚拟键盘
    local text_keyboard = airui.keyboard({
        x = 0,
        y = -10,
        w = 480,
        h = 200,
        mode = "text",
        auto_hide = true,
        preview = true
    })
    
    -- 项目key_id
    airui.label({ parent = project_section, x=20, y=35, w=100, h=40, text="项目key_id:", font_size=14, color=0x94a3b8, align = airui.TEXT_ALIGN_LEFT })
    key_id_input = airui.textarea({
        parent = project_section,
        x=130,
        y=35,
        w=310,
        h=40,
        text=config.key_id,
        font_size=14,
        color=0xe2e8f0,
        background_color=0x1e293b,
        border_color=0x475569,
        radius=4,
        align=airui.TEXT_ALIGN_LEFT,
        keyboard = text_keyboard
    })
    
    -- 项目key
    airui.label({ parent = project_section, x=20, y=95, w=100, h=40, text="项目key:", font_size=14, color=0x94a3b8, align = airui.TEXT_ALIGN_LEFT })
    key_input = airui.textarea({
        parent = project_section,
        x=130,
        y=95,
        w=310,
        h=40,
        text=config.key,
        font_size=14,
        color=0xe2e8f0,
        background_color=0x1e293b,
        border_color=0x475569,
        radius=4,
        align=airui.TEXT_ALIGN_LEFT,
        keyboard = text_keyboard
    })
    
    -- 底部按钮
    local bottom_buttons = airui.container({ parent = config_content, x=10, y=650, w=460, h=60, color=0x0f172a, radius = 8 })
    
    -- 重置按钮
    local reset_btn = airui.container({ parent = bottom_buttons, x=10, y=10, w=215, h=40, color=0x64748b, radius = 5,
        on_click = function()
            -- 重置配置
            config = {
                key_id = "",
                key = ""
            }
            
            -- 重置UI
            if key_id_input then key_id_input:set_text("") end
            if key_input then key_input:set_text("") end
        end
    })
    airui.label({ parent = reset_btn, x=0, y=10, w=215, h=20, text="重置", font_size=14, color=0xfefefe, align = airui.TEXT_ALIGN_CENTER })
    
    -- 保存按钮
    local save_btn = airui.container({ parent = bottom_buttons, x=235, y=10, w=215, h=40, color=0x38bdf8, radius = 5,
        on_click = function()
            -- 保存配置
            if key_id_input then
                config.key_id = key_id_input:get_text() or ""
            end
            if key_input then
                config.key = key_input:get_text() or ""
            end
            -- 保存配置到文件
            save_config()
            -- 关闭配置页面
            if win_id then
                exwin.close(win_id)
            end
        end
    })
    airui.label({ parent = save_btn, x=0, y=10, w=215, h=20, text="保存", font_size=14, color=0xfefefe, align = airui.TEXT_ALIGN_CENTER })
end

--[[
窗口创建回调

@local
@function on_create
@return nil
@usage
-- 窗口打开时调用，创建UI
]]
local function on_create()
    create_ui()
end

--[[
窗口销毁回调

@local
@function on_destroy
@return nil
@usage
-- 窗口关闭时调用，销毁容器
]]
local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    win_id = nil
end

-- 窗口获得焦点回调
local function on_get_focus()
    -- 获得焦点时的处理
end

-- 窗口失去焦点回调
local function on_lose_focus()
    -- 失去焦点时的处理
end

-- 订阅打开配置页面的消息
local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

sys.subscribe("OPEN_CELL_CONFIG_WIN", open_handler)

load_config() -- 加载配置

return cell_config_win
