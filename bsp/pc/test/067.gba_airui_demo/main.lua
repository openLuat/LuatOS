--[[
    @title: GBA + AirUI 嵌入式集成演示
    @description: 使用AirUI创建完整界面，GBA嵌入指定区域
    @author: LuatOS
    @date: 2026-03-24
    
    界面布局:
    ┌─────────────────────────────────────────┐
    │ [← Exit]        LuatOS GBA             │  ← 标题栏 (50px)
    ├─────────────────────────────────────────┤
    │                                         │
    │    ┌───────────────────────────┐        │  ← GBA画面区域
    │    │                           │        │     x=160, y=70
    │    │      GBA SCREEN           │        │     w=480, h=320
    │    │      480 x 320            │        │
    │    │                           │        │
    │    └───────────────────────────┘        │
    │                                         │
    ├─────────────────────────────────────────┤
    │  [◀][▼][▶]              (A) 红  (B) 蓝 │  ← 控制区 (100px)
    │   [▲]                    [START][SELECT]│
    └─────────────────────────────────────────┘
    
    总尺寸: 800 x 600
    GBA原始: 240x160, 2倍缩放: 480x320
]]

local sys = require("sys")

-- 检查模块
if not gba then
    log.error("GBA", "gba模块未加载！")
    return
end

if not airui then
    log.error("AirUI", "airui模块未加载！")
    return
end

-- 游戏列表
local GAMES = {
    {name = "宝可梦-绿宝石", path = "/luadb/pokemon_emerald.gba"},
    {name = "塞尔达传说-缩小帽",    path = "/luadb/The Legend of Zelda.gba"},
    {name = "火焰纹章-封印之剑",    path = "/luadb/Fire EmblemBlazing Sword.gba"},
    {name = "游戏测试",      path = "/luadb/game.gba"},
}

-- 状态
local STATE = {
    selected_game = 4,
    scale = 2,
    audio = true,
    running = false,
    ui = {},
}

-- 颜色定义
local COLORS = {
    title_bg = 0x2C3E50,
    title_text = 0xFFFFFF,
    bg = 0x1A1A2E,
    screen_border = 0x1A252F,
    btn_up = 0x34495E,
    btn_a = 0xE74C3C,
    btn_b = 0x3498DB,
    btn_func = 0x95A5A6,
}

-- SDL Keycode 常量（用于键盘映射）
local SDLK = {
    UP = 1073741906,      -- 方向键上
    DOWN = 1073741905,    -- 方向键下
    LEFT = 1073741904,    -- 方向键左
    RIGHT = 1073741903,   -- 方向键右
    W = 119,              -- W键
    A = 97,               -- A键
    S = 115,              -- S键
    D = 100,              -- D键
    J = 106,              -- J键 (B)
    K = 107,              -- K键 (A)
    SPACE = 32,           -- 空格键 (START)
    RETURN = 13,          -- 回车键 (START)
    ESCAPE = 27,          -- ESC键 (返回菜单)
    BACKSPACE = 8,        -- 退格键 (SELECT)
}

-- 键盘到GBA按键的映射
local KEY_MAP = {
    -- 方向键
    [SDLK.UP] = "up",
    [SDLK.DOWN] = "down",
    [SDLK.LEFT] = "left",
    [SDLK.RIGHT] = "right",
    -- WASD
    [SDLK.W] = "up",
    [SDLK.S] = "down",
    [SDLK.A] = "left",
    [SDLK.D] = "right",
    -- A/B键
    [SDLK.J] = "b",
    [SDLK.K] = "a",
    -- START/SELECT
    [SDLK.SPACE] = "start",
    [SDLK.RETURN] = "start",
    [SDLK.BACKSPACE] = "select",
}

-- 键盘事件处理函数
local function on_keypad_event(key, pressed, timestamp)
    -- 检查ESC键，用于返回菜单
    if key == SDLK.ESCAPE and pressed then
        log.info("Keyboard", "ESC pressed, returning to menu")
        stop_game()
        return
    end
    
    -- 映射到GBA按键
    local gba_key = KEY_MAP[key]
    if gba_key then
        gba.key(gba_key, pressed)
        -- log.debug("Keyboard", string.format("Key %s -> GBA %s (%s)", key, gba_key, pressed and "press" or "release"))
    end
end

-- 工具函数
local function file_exists(path)
    local f = io.open(path, "rb")
    if f then f:close() return true end
    return false
end

--[[
    创建游戏选择菜单
]]
local function create_game_menu()
    local cont = airui.container({
        x = 0, y = 0, w = 800, h = 600,
        style = { bg_color = COLORS.bg, bg_opa = 255 }
    })
    STATE.ui.menu_cont = cont

    airui.label({
        parent = cont,
        text = "LuatOS GBA模拟器",
        x = 0, y = 30, w = 800, h = 50,
        style = { text_color = COLORS.title_text, text_align = "center" }
    })

    local y = 120
    for i, game in ipairs(GAMES) do
        local exists = file_exists(game.path)
        local btn = airui.button({
            parent = cont,
            text = string.format("%s %d. %s", exists and "√" or "×", i, game.name),
            x = 150, y = y, w = 500, h = 60,
            style = {
                bg_color = exists and COLORS.title_bg or 0x555555,
                text_color = COLORS.title_text,
                radius = 8,
            },
            on_click = function()
                if exists then
                    STATE.selected_game = i
                    start_game(game)
                else
                    log.warn("Menu", "游戏文件不存在")
                end
            end
        })
        y = y + 80
    end

    airui.button({
        parent = cont,
        text = "❌ 退出",
        x = 300, y = 520, w = 200, h = 50,
        style = { bg_color = COLORS.btn_a, text_color = COLORS.title_text, radius = 25 },
        on_click = function() 
            log.info("Menu", "退出程序")
            -- 直接结束，不使用sys.exit
            return 
        end
    })
end

--[[
    创建游戏界面（GBA嵌入AirUI容器）
]]
local function create_game_ui()
    if STATE.ui.menu_cont then
        STATE.ui.menu_cont:destroy()  -- 使用destroy而不是delete
        STATE.ui.menu_cont = nil
    end

    -- 主容器
    local main = airui.container({
        x = 0, y = 0, w = 800, h = 600,
        style = { bg_color = COLORS.bg, bg_opa = 255 }
    })
    STATE.ui.main = main

    -- ========== 标题栏 ==========
    local title_bar = airui.container({
        parent = main, x = 0, y = 0, w = 800, h = 50,
        style = { bg_color = COLORS.title_bg, bg_opa = 255 }
    })

    airui.button({
        parent = title_bar, text = "← Exit",
        x = 10, y = 5, w = 80, h = 40,
        style = { bg_color = COLORS.btn_a, text_color = COLORS.title_text, radius = 20 },
        on_click = function() stop_game() end
    })

    airui.label({
        parent = title_bar, text = "LuatOS GBA",
        x = 0, y = 0, w = 800, h = 50,
        style = { text_color = COLORS.title_text, text_align = "center" }
    })

    -- ========== GBA画面区域（带边框）==========
    local screen_border = airui.container({
        parent = main, x = 158, y = 68, w = 484, h = 324,
        style = {
            bg_color = COLORS.screen_border,
            bg_opa = 255,
            radius = 4,
        }
    })
    STATE.ui.screen_border = screen_border

    -- 这是GBA画面的实际容器，将传给gba.airui_init_ex()
    local screen_area = airui.container({
        parent = screen_border, x = 2, y = 2, w = 480, h = 320,
        style = { bg_color = 0x000000, bg_opa = 255 }
    })
    STATE.ui.screen_area = screen_area

    -- ========== 控制区 ==========
    local ctrl_y = 420

    -- 方向键（左）
    local dpad_x, dpad_y = 120, ctrl_y
    
    -- 上
    airui.button({
        -- parent = main, text = "▲",
        parent = main, text = "↑",
        x = dpad_x + 50, y = dpad_y, w = 50, h = 50,
        style = { bg_color = COLORS.btn_up, text_color = COLORS.title_text, radius = 8 },
        on_click = function() gba.key("up", true) sys.taskInit(function() sys.wait(100) gba.key("up", false) end) end
    })

    -- 左
    airui.button({
        -- parent = main, text = "◀",
        parent = main, text = "←",
        x = dpad_x, y = dpad_y + 50, w = 50, h = 50,
        style = { bg_color = COLORS.btn_up, text_color = COLORS.title_text, radius = 8 },
        on_click = function() gba.key("left", true) sys.taskInit(function() sys.wait(100) gba.key("left", false) end) end
    })

    -- 下
    airui.button({
        -- parent = main, text = "▼",
        parent = main, text = "↓",
        x = dpad_x + 50, y = dpad_y + 100, w = 50, h = 50,
        style = { bg_color = COLORS.btn_up, text_color = COLORS.title_text, radius = 8 },
        on_click = function() gba.key("down", true) sys.taskInit(function() sys.wait(100) gba.key("down", false) end) end
    })

    -- 右
    airui.button({
        -- parent = main, text = "▶",
        parent = main, text = "→",
        x = dpad_x + 100, y = dpad_y + 50, w = 50, h = 50,
        style = { bg_color = COLORS.btn_up, text_color = COLORS.title_text, radius = 8 },
        on_click = function() gba.key("right", true) sys.taskInit(function() sys.wait(100) gba.key("right", false) end) end
    })

    -- AB键（右）
    local ab_x = 550
    
    -- B键（蓝色，左）
    airui.button({
        parent = main, text = "B",
        x = ab_x, y = dpad_y + 50, w = 60, h = 60,
        style = { bg_color = COLORS.btn_b, text_color = COLORS.title_text, radius = 30 },
        on_click = function() gba.key("b", true) sys.taskInit(function() sys.wait(100) gba.key("b", false) end) end
    })

    -- A键（红色，右）
    airui.button({
        parent = main, text = "A",
        x = ab_x + 80, y = dpad_y + 20, w = 70, h = 70,
        style = { bg_color = COLORS.btn_a, text_color = COLORS.title_text, radius = 35 },
        on_click = function() gba.key("a", true) sys.taskInit(function() sys.wait(100) gba.key("a", false) end) end
    })

    -- START/SELECT（中下方）
    local func_x = 330
    
    airui.button({
        parent = main, text = "START",
        x = func_x, y = ctrl_y + 80, w = 90, h = 40,
        style = { bg_color = COLORS.btn_func, text_color = COLORS.title_text, radius = 20 },
        on_click = function() gba.key("start", true) sys.taskInit(function() sys.wait(100) gba.key("start", false) end) end
    })

    airui.button({
        parent = main, text = "SELECT",
        x = func_x + 100, y = ctrl_y + 80, w = 90, h = 40,
        style = { bg_color = COLORS.btn_func, text_color = COLORS.title_text, radius = 20 },
        on_click = function() gba.key("select", true) sys.taskInit(function() sys.wait(100) gba.key("select", false) end) end
    })
end

--[[
    启动游戏（使用airui_init_ex嵌入）
]]
function start_game(game)
    if not file_exists(game.path) then
        log.error("Game", "ROM不存在: " .. game.path)
        return
    end

    -- 先创建AirUI界面
    create_game_ui()

    log.info("Game", "启动游戏: " .. game.name)

    -- 检查是否支持airui_init_ex
    if not gba.airui_init_ex then
        log.error("GBA", "当前固件不支持gba.airui_init_ex()")
        log.warn("GBA", "请使用普通AirUI模式（gba.init({mode=\"airui\"})）")
        return_to_menu()
        return
    end

    -- 使用airui_init_ex初始化，传入AirUI容器
    log.info("Game", "使用AirUI嵌入模式初始化...")
    local ret, err = gba.airui_init_ex({
        parent = STATE.ui.screen_area,  -- 将GBA嵌入到这个容器中
        x = 0, y = 0,
        width = 480, height = 320,
        scale = STATE.scale,
        audio = STATE.audio,
        show_controls = false,  -- 我们用AirUI创建自己的控制按钮
    })

    if not ret then
        log.error("Game", "初始化失败: " .. tostring(err))
        return_to_menu()
        return
    end

    -- 加载ROM
    ret, err = gba.load(game.path)
    if not ret then
        log.error("Game", "加载ROM失败: " .. tostring(err))
        gba.deinit()
        return_to_menu()
        return
    end

    log.info("Game", "ROM加载成功！")

    -- 获取游戏信息
    local info = gba.get_info()
    if info then
        log.info("Game", "游戏: " .. tostring(info.title))
    end

    -- 订阅键盘事件
    if airui.keypad_subscribe then
        airui.keypad_subscribe(on_keypad_event)
        log.info("Game", "键盘控制已启用")
        log.info("Game", "按键映射: 方向键/WASD=移动, J=B, K=A, Space/Enter=START, Backspace=SELECT, ESC=退出")
    else
        log.warn("Game", "当前固件不支持键盘订阅，只能使用触屏按钮")
    end

    STATE.running = true

    -- 游戏循环（使用step而不是run，避免阻塞AirUI）
    sys.taskInit(function()
        log.info("Game", "游戏运行中...")
        local frame_count = 0          -- 帧计数（定期重置防止溢出）
        local total_frames = 0         -- 总帧数（用于最终统计）
        local start_time = mcu.ticks()
        local target_fps = 60
        local frame_time = 1000 / target_fps  -- 每帧16.67ms
        local next_frame = start_time + frame_time
        
        while STATE.running do
            -- 执行一帧
            gba.step()
            frame_count = frame_count + 1
            total_frames = total_frames + 1
            
            -- 定期重置帧计数器（防止数值溢出，每10万帧重置一次）
            if frame_count >= 100000 then
                frame_count = 0
            end
            
            -- 计算下一帧时间
            local now = mcu.ticks()
            next_frame = next_frame + frame_time
            
            -- 等待到下一帧时间（留出时间给AirUI渲染）
            local wait = next_frame - now
            if wait > 1 then
                wait = wait - 1
                sys.wait(math.floor(wait))
            end
            
            -- 每3秒输出一次帧率信息
            if frame_count % 180 == 0 then
                local elapsed = mcu.ticks() - start_time
                local fps = total_frames / (elapsed / 1000)
                -- log.info("Game", string.format("帧率: %.1f FPS, 总帧数: %d", fps, total_frames))
            end
        end
        log.info("Game", "游戏结束，总帧数: " .. total_frames)
        stop_game()
    end)
end

--[[
    停止游戏
]]
function stop_game()
    if not STATE.running then return end
    
    log.info("Game", "停止游戏...")
    STATE.running = false
    
    -- 取消键盘订阅
    if airui.keypad_unsubscribe then
        airui.keypad_unsubscribe()
    end
    
    -- 保存存档
    local game = GAMES[STATE.selected_game]
    if game then
        local save_path = game.path:gsub("%.gba$", ".sav")
        gba.save_sram(save_path)
        log.info("Game", "存档已保存")
    end

    gba.deinit()
    return_to_menu()
end

--[[
    返回菜单
]]
function return_to_menu()
    if STATE.ui.main then
        STATE.ui.main:destroy()  -- 使用destroy而不是delete
        STATE.ui.main = nil
    end
    create_game_menu()
end

--[[
    主程序
]]
sys.taskInit(function()
    sys.wait(100)
    
    log.info("GBA", "====================================")
    log.info("GBA", "  GBA + AirUI 嵌入式集成演示")
    log.info("GBA", "====================================")

    -- 初始化AirUI
    log.info("AirUI", "初始化AirUI...")
    local ret = airui.init(800, 600, airui.COLOR_FORMAT_ARGB8888)
    if not ret then
        log.error("AirUI", "初始化失败")
        return
    end

    -- 检查API
    if gba.airui_init_ex then
        log.info("GBA", "✓ 支持gba.airui_init_ex() - 嵌入模式可用")
    else
        log.warn("GBA", "✗ 不支持gba.airui_init_ex() - 将使用标准模式")
        log.warn("GBA", "请先编译修改后的固件")
    end

    create_game_menu()
end)

sys.run()
