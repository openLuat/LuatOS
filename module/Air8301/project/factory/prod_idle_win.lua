--[[
@module  prod_idle_win
@summary 产测首页·测试面板（8301出厂固件·产测模式）
@version 3.3
@date    2026.10.08
@author  江访
@version_note 产测专属：消息名前缀 OPEN_PROD_XXX_WIN，避免与业务页面冲突

@usage
界面范式（状态条 + 磁贴网格，无底部区）：
  顶部状态条 —— 左上角品牌名「合宙工业网关Air8301」+ 时间 + 指示灯
  中部 4×3  —— 12 个测试项磁贴（图标 + 名称 + 右上状态点）
  （v3.1 起删除底部「测试进度条 + 已查看 N/12」操作条，内容区随之下延，磁贴随之增高）

测试状态语义（本页为「已查看」标记，非自动化判定）：
  未测   —— 灰点，尚未打开该测试页
  已查看 —— 绿点，本次开机已打开过该测试页
点击磁贴发布 OPEN_PROD_XXX_WIN 进入对应测试页；返回本页时状态点自动刷新。

@note
  1) 产测框架未提供统一的自动判定结果消息（无 PROD_PASS/FAIL 事件），
     故此处以「是否已进入该测试页」作为标记依据，不伪造「通过/失败」结论；
  2) 本页只承载 Air8301 实际支持的功能，不引入大屏机型才有的应用。
]]

local theme = require "ui_theme"
require "theme"   -- 设置全局 T（提供按键音兜底 T.with_beep）

local win_id = nil
local main_container
local status                       -- 状态条句柄

-- 测试项（图标取自 /luadb/hw_*.png）
local items = {
    { name = "网络状态", icon = "/luadb/hw_network.png",  win = "OPEN_PROD_NETWORK_WIN" },
    { name = "WiFi",     icon = "/luadb/hw_wifi.png",     win = "OPEN_PROD_WIFI_WIN" },
    { name = "RS485",    icon = "/luadb/hw_rs485.png",    win = "OPEN_PROD_RS485_WIN" },
    { name = "RS232",    icon = "/luadb/hw_rs232.png",    win = "OPEN_PROD_RS232_WIN" },
    { name = "DI输入",   icon = "/luadb/hw_di.png",       win = "OPEN_PROD_DI_WIN" },
    { name = "RELOAD",   icon = "/luadb/hw_reload.png",   win = "OPEN_PROD_RELOAD_WIN" },
    { name = "DO输出",   icon = "/luadb/hw_do.png",       win = "OPEN_PROD_DO_WIN" },
    { name = "蜂鸣器",   icon = "/luadb/hw_buzzer.png",   win = "OPEN_PROD_BUZZER_WIN" },
    { name = "状态灯",   icon = "/luadb/hw_led.png",      win = "OPEN_PROD_LED_WIN" },
    { name = "看门狗",   icon = "/luadb/hw_watchdog.png", win = "OPEN_PROD_WATCHDOG_WIN" },
    { name = "Flash存储", icon = "/luadb/hw_flash.png",   win = "OPEN_PROD_FLASH_WIN" },
    { name = "系统信息", icon = "/luadb/hw_sysinfo.png",  win = "OPEN_PROD_SYSINFO_WIN" },
}

-- 已查看标记（本次开机内累计，键为 win 消息名）
local visited = {}
-- 磁贴句柄（第 i 项 -> { name_label, sub_label, dot }）
local tile_handles = {}

-- 磁贴网格几何（内容区 464×230：4 列 112×4 + 5×3；3 行 73×3 + 5×2）
local COLS, ROWS = 4, 3
local GAP = 5

-- ==================== 磁贴状态刷新 ====================

--[[
刷新磁贴「已查看」标记（页面已无底部进度条，只更新状态点与文字色）

@local
@function refresh_tiles
]]
local function refresh_tiles()
    for i = 1, #items do
        local h = tile_handles[i]
        local done = visited[items[i].win] == true
        if h then
            -- 状态一律用右上状态点表达，不再放状态文字
            if h[1] then h[1]:set_color(done and theme.C.t1 or theme.C.t2) end
            if h[2] then h[2]:set_color(done and theme.SEM.success or theme.C.t3, 255) end
        end
    end
end

--[[
标记某项已查看

@local
@function mark_visited
@param msg string 测试页消息名
]]
local function mark_visited(msg)
    visited[msg] = true
end

-- ==================== 磁贴点击回调（命名函数，禁止匿名函数） ====================

local function on_network_click()  mark_visited("OPEN_PROD_NETWORK_WIN");  sys.publish("OPEN_PROD_NETWORK_WIN")  end
local function on_wifi_click()     mark_visited("OPEN_PROD_WIFI_WIN");     sys.publish("OPEN_PROD_WIFI_WIN")     end
local function on_rs485_click()    mark_visited("OPEN_PROD_RS485_WIN");    sys.publish("OPEN_PROD_RS485_WIN")    end
local function on_rs232_click()    mark_visited("OPEN_PROD_RS232_WIN");    sys.publish("OPEN_PROD_RS232_WIN")    end
local function on_di_click()       mark_visited("OPEN_PROD_DI_WIN");       sys.publish("OPEN_PROD_DI_WIN")       end
local function on_reload_click()   mark_visited("OPEN_PROD_RELOAD_WIN");   sys.publish("OPEN_PROD_RELOAD_WIN")   end
local function on_do_click()       mark_visited("OPEN_PROD_DO_WIN");       sys.publish("OPEN_PROD_DO_WIN")       end
local function on_buzzer_click()   mark_visited("OPEN_PROD_BUZZER_WIN");   sys.publish("OPEN_PROD_BUZZER_WIN")   end
local function on_led_click()      mark_visited("OPEN_PROD_LED_WIN");      sys.publish("OPEN_PROD_LED_WIN")      end
local function on_watchdog_click() mark_visited("OPEN_PROD_WATCHDOG_WIN"); sys.publish("OPEN_PROD_WATCHDOG_WIN") end
local function on_flash_click()    mark_visited("OPEN_PROD_FLASH_WIN");    sys.publish("OPEN_PROD_FLASH_WIN")    end
local function on_sysinfo_click()  mark_visited("OPEN_PROD_SYSINFO_WIN");  sys.publish("OPEN_PROD_SYSINFO_WIN")  end

local click_funcs = {
    on_network_click, on_wifi_click,
    on_rs485_click, on_rs232_click, on_di_click,
    on_reload_click, on_do_click, on_buzzer_click,
    on_led_click, on_watchdog_click, on_flash_click,
    on_sysinfo_click,
}

-- ==================== UI 构建 ====================

--[[
创建产测首页 UI

@local
@function create_ui
]]
local function create_ui()
    -- nav = "none"：既不画 Dock 也不生成底部操作条（v3.1 起已删除测试进度条）
    local ctx = theme.shell({
        title = theme.BRAND,        -- 左上角品牌名（与业务模式一致）
        nav = "none",
        time = os.date("%H:%M"),
    })
    main_container = ctx.base
    status = ctx.status

    -- 中部 4×3 测试项磁贴
    local cw = math.floor((ctx.w - GAP * (COLS - 1)) / COLS)
    local ch = math.floor((ctx.h - GAP * (ROWS - 1)) / ROWS)
    for i, item in ipairs(items) do
        local col = (i - 1) % COLS
        local row = math.floor((i - 1) / COLS)
        local x = ctx.x + col * (cw + GAP)
        local y = ctx.y + row * (ch + GAP)
        local _, name_label, _, dot = theme.tile(ctx.base, {
            x = x, y = y, w = cw, h = ch,
            icon = item.icon, icon_size = 24, icon_y = 5,
            text = item.name, dot = theme.C.t3,
            on_click = T.with_beep(click_funcs[i]),
        })
        tile_handles[i] = { name_label, dot }
    end

    refresh_tiles()
end

-- ==================== 窗口生命周期 ====================

--[[
窗口创建回调

@local
@function on_create
]]
local function on_create()
    log.info("prod_idle_win", "[UI-MARK] 产测首页 v3.3 已加载（品牌标题 + 磁贴网格）")
    create_ui()
end

--[[
窗口销毁回调：释放页面全部组件

@local
@function on_destroy
]]
local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    status = nil
    tile_handles = {}
    win_id = nil
end

--[[
窗口获得焦点回调：返回本页时刷新时间与磁贴标记

@local
@function on_get_focus
]]
local function on_get_focus()
    if status and status.time then
        status.time:set_text(os.date("%H:%M"))
    end
    refresh_tiles()
end

--[[
窗口失去焦点回调

@local
@function on_lose_focus
]]
local function on_lose_focus() end

--[[
OPEN_PROD_IDLE_WIN 消息处理器

@local
@function open_handler
]]
local function open_handler()
    -- 单实例保护：避免同页多实例并存时互相覆盖 win_id（会使点击准入判定失效）
    if win_id and exwin.is_active(win_id) then return end
    if win_id then
        exwin.close(win_id)
        win_id = nil
    end
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

sys.subscribe("OPEN_PROD_IDLE_WIN", open_handler)
