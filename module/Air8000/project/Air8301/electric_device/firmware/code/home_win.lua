--[[
@module  home_win
@summary 主界面窗口模块（电压/状态显示 + 开关机/电压调节控制）
@version 1.0
@date    2026.08.23
@author  嵌入式软件设计开发代理
@usage
本模块为主界面（home_win），显示高压板实时电压、工作状态、设定电压与云端连接状态，
提供开关机按钮与电压调节按钮（每次 ±100V）实现本地控制。
布局：标题栏以下区域沿竖直中线左右分半，左半显示现有内容，右半显示 logo 图片。

订阅消息：
- "OPEN_HOME_WIN"         -- 打开主界面窗口
- "UI_UPDATE_STATUS"      -- 状态刷新 {voltage, work_status, set_voltage, cloud_connected, power, status_synced}
- "FOTA_STATUS"           -- FOTA 升级状态（fota_app 发布）：仅记录日志（主界面不再显示 FOTA 提示）
- "NET_STATUS"            -- 网络总状态 {wifi_connected, wifi_ssid, wifi_rssi, g4_connected, current_adapter}（netdrv_wifi 发布，更新标题栏图标）
- "NET_4G_SIGNAL_STATUS"  -- 4G 信号等级 {csq_level}（netdrv_4g 发布，-1=无SIM卡/无信号，1-5=信号等级）

发布消息：
- "UI_TOGGLE_POWER"       -- 本地开关机 {power}
- "UI_SET_VOLTAGE"        -- 本地电压调节 {voltage}
- "OPEN_SETTINGS_WIN"     -- 打开设置界面（WiFi设置 / 服务器设置）
]]

local win_id = nil
local main_container

-- UI 组件引用（用于刷新显示）
local voltage_label = nil        -- 实际电压值标签
local work_status_label = nil    -- 工作状态标签
local cloud_label = nil          -- 云端状态标签
local set_voltage_label = nil    -- 设定电压标签
local power_btn = nil            -- 开关机按钮
local right_panel = nil          -- 右侧 logo 显示区域
local wifi_status_img = nil      -- 标题栏 WiFi 状态图标（airui.image）
local g4_status_img = nil        -- 标题栏 4G 状态图标（airui.image）

-- 设定电压初始值：从 fskv 读取持久化值（每次开机恢复上次设定），无记录或超范围时用默认 3500
local init_set_voltage = 3500
local saved_set_voltage = fskv.get("set_voltage")
if saved_set_voltage ~= nil and saved_set_voltage >= 0 and saved_set_voltage <= 6000 then
    init_set_voltage = saved_set_voltage
end

-- 本地状态缓存（与 business_app 的 UI_UPDATE_STATUS 同步）
local state = {
    voltage = 0,             -- 实际输出电压（V）
    work_status = 0,         -- 工作状态（1=开机中，0=关机中）
    set_voltage = init_set_voltage,  -- 设定电压（V），开机从 fskv 恢复
    cloud_connected = false, -- 云端连接状态
    power = 0,               -- 开关机状态（1=开机，0=关机）
    status_synced = false,   -- 是否已收到高压板状态同步帧（开机初始未同步）
    wifi_connected = false,  -- WiFi 连接状态（标题栏图标）
    wifi_rssi = nil,         -- WiFi 信号强度（dBm，标题栏图标等级）
    g4_connected = false,    -- 4G 连接状态（标题栏图标）
    csq_level = -1,          -- 4G 信号等级（-1=无SIM卡/无信号，1-5=信号等级，标题栏 4G 图标）
}

-- 电压调节步进（V）
local VOLTAGE_STEP = 100
-- 电压调节范围（协议 5.3.1：0-6000）
local VOLTAGE_MIN = 0
local VOLTAGE_MAX = 6000

--[[
WiFi RSSI(dBm) 转信号等级（1-4，用于选择 wifixinhao1-4 图标）

@local
@function rssi_to_level
@param rssi number 信号强度（dBm，可为 nil）
@return number 信号等级 1-4
]]
local function rssi_to_level(rssi)
    if not rssi then
        return 4  -- 无 rssi 数据时默认满格（已连接场景）
    end
    -- 官方映射（参考 Air1601 factory status_provider_app）：rssi > -60 → 4 ... rssi <= -80 → 1
    if rssi > -60 then return 4 end
    if rssi > -70 then return 3 end
    if rssi > -80 then return 2 end
    return 1
end

--[[
刷新界面显示（根据本地状态缓存更新所有 UI 组件）

@local
@function refresh_ui
@return nil
]]
local function refresh_ui()
    -- 窗口未创建或已销毁时直接返回（避免访问已销毁的 airui 组件）
    if not main_container then
        return
    end
    if voltage_label then
        voltage_label:set_text("实际输出电压: " .. state.voltage .. " V")
    end
    if work_status_label then
        local ws_text
        if not state.status_synced then
            -- 每次开机尚未收到状态同步帧时显示"未同步"
            ws_text = "工作状态: 未同步"
        elseif state.work_status == 1 then
            ws_text = "工作状态: 运行中"
        else
            ws_text = "工作状态: 已关机"
        end
        work_status_label:set_text(ws_text)
    end
    if set_voltage_label then
        set_voltage_label:set_text("设定电压: " .. state.set_voltage .. " V")
    end
    if cloud_label then
        local cloud_text = state.cloud_connected and "云端: 已连接" or "云端: 未连接"
        cloud_label:set_text(cloud_text)
    end
    if power_btn then
        -- 按钮显示当前可执行的操作（关机时显示"开机"，开机时显示"关机"）
        local btn_text = (state.power == 1) and "关 机" or "开 机"
        power_btn:set_text(btn_text)
    end
    -- 标题栏网络状态图标：WiFi 已连接按信号等级显示 wifixinhao1-4，未连接显示 wifixinhao0
    if wifi_status_img then
        local wifi_icon = "/luadb/wifixinhao0.png"
        if state.wifi_connected then
            wifi_icon = "/luadb/wifixinhao" .. rssi_to_level(state.wifi_rssi) .. ".png"
        end
        wifi_status_img:set_src(wifi_icon)
    end
    -- 标题栏网络状态图标（参考官方 Air8000A idle_win.lua）：
    -- csq_level 1-5 → 4Gxinhao1-5.png（按信号等级）；-1（无卡/无信号）→ 4Gxinhao6.png（默认无信号）
    if g4_status_img then
        local g4_icon = "/luadb/4Gxinhao6.png"  -- 默认无信号/无卡
        if state.csq_level > 0 and state.csq_level <= 5 then
            g4_icon = "/luadb/4Gxinhao" .. state.csq_level .. ".png"
        end
        g4_status_img:set_src(g4_icon)
    end
end

--[[
设置入口按钮点击回调：打开设置界面（WiFi设置 / 服务器设置）

@local
@function on_settings_btn_click
@return nil
]]
local function on_settings_btn_click()
    if win_id then
        exwin.close(win_id)
    end
    sys.publish("OPEN_SETTINGS_WIN")
end

--[[
开关机按钮点击回调：切换开关机状态并发布本地控制消息

@local
@function on_power_btn_click
@return nil
]]
local function on_power_btn_click()
    local new_power = 0
    if state.power == 0 then
        new_power = 1
    else
        new_power = 0
    end
    state.power = new_power
    -- 发布本地开关机消息（business_app 订阅）
    sys.publish("UI_TOGGLE_POWER", new_power)
    log.info("home_win", "本地开关机操作: " .. new_power)
end

--[[
电压 "-" 按钮点击回调：设定电压减 100V

@local
@function on_voltage_minus_click
@return nil
]]
local function on_voltage_minus_click()
    local new_voltage = state.set_voltage - VOLTAGE_STEP
    if new_voltage < VOLTAGE_MIN then
        new_voltage = VOLTAGE_MIN
    end
    -- 写回本地状态，支持连续调节（此前缺失导致每次从初始值计算）
    state.set_voltage = new_voltage
    -- 发布本地电压调节消息（business_app 订阅）
    sys.publish("UI_SET_VOLTAGE", new_voltage)
    log.info("home_win", "本地电压调节: " .. new_voltage)
end

--[[
电压 "+" 按钮点击回调：设定电压加 100V

@local
@function on_voltage_plus_click
@return nil
]]
local function on_voltage_plus_click()
    local new_voltage = state.set_voltage + VOLTAGE_STEP
    if new_voltage > VOLTAGE_MAX then
        new_voltage = VOLTAGE_MAX
    end
    -- 写回本地状态，支持连续调节（此前缺失导致每次从初始值计算）
    state.set_voltage = new_voltage
    -- 发布本地电压调节消息（business_app 订阅）
    sys.publish("UI_SET_VOLTAGE", new_voltage)
    log.info("home_win", "本地电压调节: " .. new_voltage)
end

--[[
创建 UI：主界面布局（480x272）

@local
@function create_ui
@return nil
]]
local function create_ui()
    -- 主容器（全屏白色背景，浅色主题）
    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = 480,
        h = 272,
        color = 0xFFFFFF
    })

    -- 标题栏（浅蓝色，浅色主题）
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 480,
        h = 45,
        color = 0x64B5F6
    })
    -- 最左侧：设置入口按钮（WiFi设置 / 服务器设置，白底深蓝字）
    airui.button({
        parent = title_bar,
        x = 10,
        y = 8,
        w = 50,
        h = 30,
        text = "设置",
        font_size = 14,
        style = {
            bg_color = 0xFFFFFF,
            text_color = 0x1565C0,
            radius = 6,
        },
        on_click = on_settings_btn_click
    })
    -- 中间：机构名称标题（居中显示，深蓝文字）
    airui.label({
        parent = title_bar,
        x = 60,
        y = 10,
        w = 360,
        h = 25,
        text = "中国电力研究院",
        font_size = 20,
        color = 0x0D47A1,
        align = airui.TEXT_ALIGN_CENTER
    })
    -- 最右侧：WiFi 状态图标（wifixinhao0=未连接，wifixinhao1-4=信号等级，32x32 PNG）
    wifi_status_img = airui.image({
        parent = title_bar,
        x = 410,
        y = 7,
        w = 32,
        h = 32,
        src = "/luadb/wifixinhao0.png"
    })
    -- 最右侧：4G 状态图标（4Gxinhao1=未连接弱信号，4Gxinhao6=已连接强信号，32x32 PNG）
    g4_status_img = airui.image({
        parent = title_bar,
        x = 446,
        y = 7,
        w = 32,
        h = 32,
        src = "/luadb/4Gxinhao1.png"
    })

    -- 左半区域（x=0~240）：实际输出电压（标签与数值合并为一行显示，字体/颜色/行高与工作状态、云端、设定电压保持一致，浅色主题下深灰文字）
    voltage_label = airui.label({
        parent = main_container,
        x = 20,
        y = 55,
        w = 200,
        h = 20,
        text = "实际输出电压: 0 V",
        font_size = 14,
        color = 0x333333
    })

    -- 左半区域：工作状态 / 云端状态 / 设定电压（垂直排列，与"实际输出电压"行间距统一为 8px，保持四行等距美观）
    work_status_label = airui.label({
        parent = main_container,
        x = 20,
        y = 83,
        w = 200,
        h = 20,
        text = "工作状态: 未同步",
        font_size = 14,
        color = 0x333333
    })
    cloud_label = airui.label({
        parent = main_container,
        x = 20,
        y = 111,
        w = 200,
        h = 20,
        text = "云端: 未连接",
        font_size = 14,
        color = 0x333333
    })
    set_voltage_label = airui.label({
        parent = main_container,
        x = 20,
        y = 139,
        w = 200,
        h = 20,
        text = "设定电压: 3500 V",
        font_size = 14,
        color = 0x333333
    })

    -- 左半区域：控制区开关机按钮（上移压缩，与下方电压调节按钮保持间距，避免重叠；蓝色主操作按钮）
    power_btn = airui.button({
        parent = main_container,
        x = 20,
        y = 172,
        w = 200,
        h = 40,
        text = "开 机",
        style = {
            bg_color = 0x2196F3,
            text_color = 0xFFFFFF,
            radius = 8,
        },
        on_click = on_power_btn_click
    })

    -- 左半区域：控制区电压调节按钮（-100 / +100，480x272 下上移并压缩高度；浅蓝底深蓝字）
    airui.button({
        parent = main_container,
        x = 20,
        y = 220,
        w = 90,
        h = 36,
        text = "-",
        font_size = 28,
        style = {
            bg_color = 0xE3F2FD,
            text_color = 0x1565C0,
            radius = 6,
        },
        on_click = on_voltage_minus_click
    })
    airui.button({
        parent = main_container,
        x = 130,
        y = 220,
        w = 90,
        h = 36,
        text = "+",
        font_size = 28,
        style = {
            bg_color = 0xE3F2FD,
            text_color = 0x1565C0,
            radius = 6,
        },
        on_click = on_voltage_plus_click
    })
    airui.label({
        parent = main_container,
        x = 20,
        y = 258,
        w = 200,
        h = 14,
        text = "电压调节 (每次 " .. VOLTAGE_STEP .. "V)",
        font_size = 12,
        color = 0x8C8C8C,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 右半区域（x=240~480）：显示 logo 图片（200×200，480x272 下随面板压缩后垂直居中；白色背景贴合浅色主题）
    right_panel = airui.container({
        parent = main_container,
        x = 240,
        y = 45,
        w = 240,
        h = 227,
        color = 0xFFFFFF
    })
    airui.image({
        parent = right_panel,
        x = 20,
        y = 14,
        w = 200,
        h = 200,
        src = "/luadb/logo.png",
        fit = "contain"   -- 等比缩放完整显示，避免图片尺寸超出显示框被裁剪
    })
end

--[[
状态刷新消息处理（business_app 发布 UI_UPDATE_STATUS）

@local
@function on_ui_update_status
@param voltage number 实际输出电压（V）
@param work_status number 工作状态（1=开机中，0=关机中）
@param set_voltage number 设定电压（V）
@param cloud_connected boolean 云端连接状态
@param power number 开关机状态（1=开机，0=关机）
@param status_synced boolean 是否已收到状态同步帧（true=已同步，false=未同步）
@return nil
]]
local function on_ui_update_status(voltage, work_status, set_voltage, cloud_connected, power, status_synced)
    state.voltage = voltage or 0
    state.work_status = work_status or 0
    state.set_voltage = set_voltage or 3500
    state.cloud_connected = cloud_connected or false
    if power ~= nil then
        state.power = power
    end
    if status_synced ~= nil then
        state.status_synced = status_synced
    end
    refresh_ui()
end

--[[
FOTA 状态消息处理（fota_app 发布 FOTA_STATUS，仅记录日志；主界面不再显示 FOTA 提示）

@local
@function on_fota_status
@param status string FOTA 状态
@param msg string 消息
@param percent number 下载进度（可选）
@return nil
]]
local function on_fota_status(status, msg, percent)
    log.info("home_win", "FOTA 状态:", tostring(status), tostring(msg), percent and (percent .. "%") or "")
end

--[[
网络总状态消息处理（netdrv_wifi 发布 NET_STATUS，更新标题栏 WiFi/4G 状态图标）

@local
@function on_net_status
@param wifi_connected boolean WiFi 连接状态
@param wifi_ssid string 当前 WiFi SSID
@param wifi_rssi number 信号强度
@param g4_connected boolean 4G 连接状态
@param adapter number 当前默认网卡
@return nil
]]
local function on_net_status(wifi_connected, wifi_ssid, wifi_rssi, g4_connected, adapter)
    state.wifi_connected = wifi_connected or false
    state.wifi_rssi = wifi_rssi
    state.g4_connected = g4_connected or false
    refresh_ui()
end

--[[
4G 信号等级消息处理（netdrv_4g 发布 NET_4G_SIGNAL_STATUS，更新标题栏 4G 信号图标）

@local
@function on_g4_signal_status
@param csq_level number 4G 信号等级（-1=无SIM卡/无信号，1-5=信号等级）
@return nil
]]
local function on_g4_signal_status(csq_level)
    state.csq_level = csq_level or -1
    refresh_ui()
end

--[[
窗口创建回调

@local
@function on_create
@return nil
]]
local function on_create()
    log.info("home_win", "打开主界面窗口")
    create_ui()
    refresh_ui()
end

--[[
窗口销毁回调

@local
@function on_destroy
@return nil
]]
local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    -- 子组件变量全部置 nil，防止窗口关闭后消息回调访问已销毁的 airui 对象
    voltage_label = nil
    work_status_label = nil
    cloud_label = nil
    set_voltage_label = nil
    power_btn = nil
    right_panel = nil
    wifi_status_img = nil
    g4_status_img = nil
    win_id = nil
end

-- 可选：获得焦点/失去焦点时不做特殊处理
local function on_get_focus() end

local function on_lose_focus() end

--[[
订阅打开主界面的消息

@local
@function open_home_handler
@return nil
]]
local function open_home_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end
sys.subscribe("OPEN_HOME_WIN", open_home_handler)

-- 订阅状态刷新与 FOTA 状态消息
sys.subscribe("UI_UPDATE_STATUS", on_ui_update_status)
sys.subscribe("FOTA_STATUS", on_fota_status)

-- 订阅网络总状态消息（netdrv_wifi 发布，更新标题栏 WiFi/4G 状态图标）
sys.subscribe("NET_STATUS", on_net_status)

-- 订阅 4G 信号等级消息（netdrv_4g 发布，更新标题栏 4G 信号图标）
sys.subscribe("NET_4G_SIGNAL_STATUS", on_g4_signal_status)
