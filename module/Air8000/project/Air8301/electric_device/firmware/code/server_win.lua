--[[
@module  server_win
@summary 服务器设置窗口模块（默认AirCloud / 自定义TCP服务器单选配置）
@version 1.0
@date    2026.08.26
@author  嵌入式软件设计开发代理
@usage
本模块为服务器设置界面（server_win），提供服务器模式单选与自定义服务器配置：
1、单选：默认AirCloud服务器（使用 getip 动态获取服务器地址）/ 自定义TCP服务器（手动配置地址和端口）；
2、选择"自定义TCP服务器"时显示服务器地址与端口输入框，可配置并保存；
3、配置项（模式、地址、端口）存储到 fskv，掉电生效；
4、业务对接（excloud 扩展库接口：如何根据模式选择 getip 或自定义地址）暂未实现，后续版本接入。

fskv 键：
- "server_mode"   -- 服务器模式：1=默认AirCloud，2=自定义TCP（默认 1）
- "server_addr"   -- 自定义服务器地址（IP 或域名，默认空字符串）
- "server_port"   -- 自定义服务器端口（默认空字符串，1-65535）

订阅消息：
- "OPEN_SERVER_WIN"      -- 打开服务器设置窗口

发布消息：
- "OPEN_SETTINGS_WIN"    -- 返回设置窗口
]]

local win_id = nil
local main_container = nil

-- UI 组件引用
local btn_default = nil        -- 单选按钮：默认AirCloud服务器
local btn_custom = nil         -- 单选按钮：自定义TCP服务器
local custom_panel = nil       -- 自定义配置区容器（仅 mode=2 显示）
local addr_ta = nil            -- 服务器地址输入框
local port_ta = nil            -- 端口输入框
local kb = nil                 -- 虚拟键盘（地址/端口共用）

-- 当前服务器模式（1=默认AirCloud，2=自定义TCP；fskv 持久化，默认 1）
local server_mode = 1

-- 进入窗口时的配置快照（返回时判断配置是否真正改变）
local init_mode = 1
local init_addr = ""
local init_port = ""

-- fskv 键名
local KV_MODE = "server_mode"
local KV_ADDR = "server_addr"
local KV_PORT = "server_port"

-- 单选按钮视觉区分（浅色主题）：选中绿色背景+亮绿边框（白字） / 未选中浅灰背景+浅灰边框（深灰字）
local RADIO_ON_BG = 0x4CAF50          -- 选中：亮绿色背景
local RADIO_ON_BORDER = 0x388E3C      -- 选中：深绿边框
local RADIO_OFF_BG = 0xEDEFF2         -- 未选中：浅灰背景（浅色主题）
local RADIO_OFF_BORDER = 0xC0C4CC     -- 未选中：浅灰边框

-- 前向声明（解决 local 函数相互引用的解析顺序）
local create_custom_panel
local destroy_custom_panel
local refresh_radio

--[[
读取服务器配置（fskv，掉电生效）

@local
@function load_config
@return nil
]]
local function load_config()
    local mode = fskv.get(KV_MODE)
    server_mode = (mode == 2) and 2 or 1
    -- 记录进入窗口时的配置快照（返回时判断是否真正改变）
    init_mode = server_mode
    init_addr = fskv.get(KV_ADDR) or ""
    init_port = fskv.get(KV_PORT) or ""
end

--[[
服务器配置已更改提示：弹出对话框，3 秒后重启生效
（服务器配置在 aircloud_app 启动时读取，需重启后按新配置连接）

@local
@function prompt_restart
@return nil
]]
local function prompt_restart()
    airui.msgbox({
        title = "提示",
        text = "服务器配置已更改，3秒后即将重启生效",
        buttons = {"确定"},
        on_action = function(self, label)
            if label == "确定" then
                self:hide()
            end
        end
    })
    -- 3 秒后软件重启（使新配置生效）
    sys.timerStart(rtos.reboot, 3000)
end

--[[
保存按钮回调：校验并保存自定义服务器地址与端口（fskv）

@local
@function on_save_click
@return nil
]]
local function on_save_click()
    if not addr_ta or not port_ta then
        return
    end
    local addr = addr_ta:get_text() or ""
    local port = port_ta:get_text() or ""
    -- 去除首尾空格
    addr = string.gsub(addr, "^%s*(.-)%s*$", "%1")
    port = string.gsub(port, "^%s*(.-)%s*$", "%1")
    -- 校验：地址非空
    if addr == "" then
        airui.msgbox({
            title = "提示",
            text = "服务器地址不能为空",
            buttons = {"确定"},
            on_action = function(self, label)
                if label == "确定" then
                    self:hide()
                end
            end
        })
        return
    end
    -- 校验：端口为 1-65535 的数字
    local port_num = tonumber(port)
    if not port_num or port_num < 1 or port_num > 65535 then
        airui.msgbox({
            title = "提示",
            text = "端口必须为 1-65535 的数字",
            buttons = {"确定"},
            on_action = function(self, label)
                if label == "确定" then
                    self:hide()
                end
            end
        })
        return
    end
    -- 判断配置是否真正改变（与 fskv 旧值比较）
    local old_addr = fskv.get(KV_ADDR) or ""
    local old_port = fskv.get(KV_PORT) or ""
    if addr == old_addr and port == old_port then
        airui.msgbox({
            title = "提示",
            text = "配置未改变，无需重启",
            buttons = {"确定"},
            on_action = function(self, label)
                if label == "确定" then
                    self:hide()
                end
            end
        })
        return
    end
    -- 保存 fskv（掉电生效）
    fskv.set(KV_ADDR, addr)
    fskv.set(KV_PORT, port)
    log.info("server_win", "已保存自定义服务器: " .. addr .. ":" .. port)
    -- 配置已真正改变：提示重启生效
    prompt_restart()
end

--[[
销毁自定义配置区（含输入框与虚拟键盘）

@local
@function destroy_custom_panel
@return nil
]]
destroy_custom_panel = function()
    -- 虚拟键盘 parent 为 airui.screen（不在 custom_panel 内），需单独销毁
    if kb then
        kb:destroy()
        kb = nil
    end
    if addr_ta then
        addr_ta:destroy()
        addr_ta = nil
    end
    if port_ta then
        port_ta:destroy()
        port_ta = nil
    end
    if custom_panel then
        custom_panel:destroy()
        custom_panel = nil
    end
end

--[[
创建自定义配置区（服务器地址 + 端口 + 保存按钮，仅 mode=2 时显示）

@local
@function create_custom_panel
@return nil
]]
create_custom_panel = function()
    -- 重建前先销毁旧的（切换单选时）
    destroy_custom_panel()
    -- 自定义配置区容器（parent=main_container，绝对 y=112 起；地址/端口两列并排，输入框保持在虚拟键盘上方；白色背景贴合浅色主题）
    custom_panel = airui.container({
        parent = main_container,
        x = 0,
        y = 112,
        w = 480,
        h = 160,
        color = 0xFFFFFF
    })
    -- 虚拟键盘（底部弹出，h=110 覆盖 y=162~272；地址/端口输入框均位于键盘上方可见）
    kb = airui.keyboard({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = 480,
        h = 110,
        mode = "text",
        auto_hide = true,
        on_commit = function(self)
            if self then
                self:hide()
            end
        end
    })
    -- 服务器地址（label 与输入框留 2px 间距；深灰文字）
    airui.label({
        parent = custom_panel,
        x = 20,
        y = 0,
        w = 300,
        h = 16,
        text = "服务器地址",
        font_size = 13,
        color = 0x666666
    })
    addr_ta = airui.textarea({
        parent = custom_panel,
        x = 20,
        y = 18,
        w = 290,
        h = 30,
        placeholder = "请输入 IP 或域名",
        text = fskv.get(KV_ADDR) or "",
        max_len = 64,
        align = airui.TEXT_ALIGN_LEFT,
        style = {radius = 4, bg_color = 0xF0F0F0, text_color = 0x333333, font_size = 14},
        keyboard = kb
    })
    -- 端口（与地址同排右侧，绝对位置 130~160，位于虚拟键盘上方可见；深灰文字）
    airui.label({
        parent = custom_panel,
        x = 330,
        y = 0,
        w = 130,
        h = 16,
        text = "端口",
        font_size = 13,
        color = 0x666666
    })
    port_ta = airui.textarea({
        parent = custom_panel,
        x = 330,
        y = 18,
        w = 130,
        h = 30,
        placeholder = "1-65535",
        text = fskv.get(KV_PORT) or "",
        max_len = 5,
        align = airui.TEXT_ALIGN_LEFT,
        style = {radius = 4, bg_color = 0xF0F0F0, text_color = 0x333333, font_size = 14},
        keyboard = kb
    })
    -- 保存按钮（键盘收起后可见；蓝色主操作按钮）
    airui.button({
        parent = custom_panel,
        x = 20,
        y = 62,
        w = 440,
        h = 36,
        text = "保存配置",
        style = {
            bg_color = 0x2196F3,
            text_color = 0xFFFFFF,
            radius = 8,
        },
        on_click = on_save_click
    })
    -- 提示
    airui.label({
        parent = custom_panel,
        x = 20,
        y = 108,
        w = 440,
        h = 16,
        text = "配置保存到本地，重启后生效",
        font_size = 12,
        color = 0x8C8C8C,
        align = airui.TEXT_ALIGN_CENTER
    })
end

--[[
刷新单选按钮视觉状态（浅色主题：选中绿色背景+亮绿边框+白字；未选中浅灰背景+浅灰边框+深灰字）

@local
@function refresh_radio
@return nil
]]
refresh_radio = function()
    if btn_default then
        local on = (server_mode == 1)
        btn_default:set_style({
            bg_color = on and RADIO_ON_BG or RADIO_OFF_BG,
            border_color = on and RADIO_ON_BORDER or RADIO_OFF_BORDER,
            border_width = 2,
            text_color = on and 0xFFFFFF or 0x333333,
        })
    end
    if btn_custom then
        local on = (server_mode == 2)
        btn_custom:set_style({
            bg_color = on and RADIO_ON_BG or RADIO_OFF_BG,
            border_color = on and RADIO_ON_BORDER or RADIO_OFF_BORDER,
            border_width = 2,
            text_color = on and 0xFFFFFF or 0x333333,
        })
    end
end

--[[
单选"默认AirCloud服务器"点击回调：切换模式并保存（fskv）

@local
@function on_default_click
@return nil
]]
local function on_default_click()
    if server_mode == 1 then
        return
    end
    server_mode = 1
    fskv.set(KV_MODE, 1)
    log.info("server_win", "切换服务器模式: 默认AirCloud")
    refresh_radio()
    destroy_custom_panel()
end

--[[
单选"自定义TCP服务器"点击回调：切换模式并保存（fskv）

@local
@function on_custom_click
@return nil
]]
local function on_custom_click()
    if server_mode == 2 then
        return
    end
    server_mode = 2
    fskv.set(KV_MODE, 2)
    log.info("server_win", "切换服务器模式: 自定义TCP")
    refresh_radio()
    create_custom_panel()
end

--[[
返回按钮回调：关闭窗口并返回设置窗口

@local
@function on_back
@return nil
]]
local function on_back()
    -- 判断配置是否真正改变（与进入窗口时的快照比较）
    local cur_mode = fskv.get(KV_MODE) or 1
    local cur_addr = fskv.get(KV_ADDR) or ""
    local cur_port = fskv.get(KV_PORT) or ""
    local changed = (cur_mode ~= init_mode) or (cur_addr ~= init_addr) or (cur_port ~= init_port)
    if not changed then
        -- 配置未改变：正常返回设置窗口
        if win_id then
            exwin.close(win_id)
            win_id = nil
        end
        sys.publish("OPEN_SETTINGS_WIN")
        return
    end
    -- 配置已真正改变：不关闭/不切换窗口，直接弹重启提示
    -- （msgbox 显示在当前服务器设置窗口之上，不会被其他窗口覆盖），3 秒后重启生效
    prompt_restart()
end

--[[
创建 UI：服务器设置界面布局（480x272）

@local
@function create_ui
@return nil
]]
local function create_ui()
    -- 读取 fskv 配置
    load_config()
    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = 480,
        h = 272,
        color = 0xFFFFFF -- 白色背景（浅色主题）
    })
    -- 标题栏（浅蓝色）
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 480,
        h = 45,
        color = 0x64B5F6
    })
    airui.button({
        parent = title_bar,
        x = 10,
        y = 8,
        w = 50,
        h = 30,
        text = "←",
        font_size = 18,
        style = {
            bg_color = 0xFFFFFF,
            text_color = 0x1565C0,
            radius = 6,
        },
        on_click = on_back
    })
    airui.label({
        parent = title_bar,
        x = 60,
        y = 10,
        w = 360,
        h = 25,
        text = "服务器设置",
        font_size = 20,
        color = 0x0D47A1,
        align = airui.TEXT_ALIGN_CENTER
    })
    -- 单选区（按钮模拟单选：浅色主题下选中绿色背景+亮绿边框+白字，未选中浅灰背景+浅灰边框+深灰字）
    btn_default = airui.button({
        parent = main_container,
        x = 20,
        y = 50,
        w = 440,
        h = 28,
        text = "默认AirCloud服务器",
        font_size = 14,
        style = {
            bg_color = RADIO_OFF_BG,
            border_color = RADIO_OFF_BORDER,
            border_width = 2,
            radius = 6,
            text_color = 0x333333,
        },
        on_click = on_default_click
    })
    btn_custom = airui.button({
        parent = main_container,
        x = 20,
        y = 82,
        w = 440,
        h = 28,
        text = "自定义TCP服务器",
        font_size = 14,
        style = {
            bg_color = RADIO_OFF_BG,
            border_color = RADIO_OFF_BORDER,
            border_width = 2,
            radius = 6,
            text_color = 0x333333,
        },
        on_click = on_custom_click
    })
    refresh_radio()
    -- 自定义配置区（仅 mode=2 显示）
    if server_mode == 2 then
        create_custom_panel()
    end
end

--[[
窗口创建回调

@local
@function on_create
@return nil
]]
local function on_create()
    log.info("server_win", "打开服务器设置窗口")
    create_ui()
end

--[[
窗口销毁回调

@local
@function on_destroy
@return nil
]]
local function on_destroy()
    destroy_custom_panel()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    btn_default = nil
    btn_custom = nil
    win_id = nil
end

--[[
打开服务器设置窗口

@local
@function open_server_win
@return nil
]]
local function open_server_win()
    if win_id then
        exwin.close(win_id)
        win_id = nil
    end
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
    })
end
sys.subscribe("OPEN_SERVER_WIN", open_server_win)
