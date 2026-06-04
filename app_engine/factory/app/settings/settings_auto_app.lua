--[[
@module  settings_autostart_app
@summary 后装APP开机自启管理模块
@version 1.0
@date    2026.06.03
@author  江访

功能：
1. fskv 持久化自启配置（开关、目标APP路径、密码）
2. 密码验证（用于关闭设置中的自启/重新设置自启）
3. 开机延时100ms启动选定的后装APP
4. 硬件 RETURN 键密码保护（有密码时拦截 NES_CTRL 并弹窗验证）
]]

-- ==================== 配置常量 ====================

local CONFIG_KEYS = {
    ENABLED  = "app_autostart_enabled",
    TARGET   = "app_autostart_target",
    PASSWORD = "app_autostart_password",
    LOCKED   = "app_autostart_locked",
}

-- ==================== 局部变量 ====================

local fskv_initialized = false
local autostart_locked = false
local autostart_target_path = ""

-- fskv 持久化锁定状态，exapp.lua 直接读 fskv，无需 _G 或 publish 耦合
local function set_locked(value)
    autostart_locked = value
    if fskv_initialized then
        fskv.set(CONFIG_KEYS.LOCKED, value and "1" or "0")
    end
end

-- ==================== fskv 读写 ====================

local function init_fskv()
    if fskv_initialized then return true end
    local result = fskv.init()
    if result then
        fskv_initialized = true
        if fskv.get(CONFIG_KEYS.ENABLED) == nil then fskv.set(CONFIG_KEYS.ENABLED, "0") end
        if fskv.get(CONFIG_KEYS.PASSWORD) == nil then fskv.set(CONFIG_KEYS.PASSWORD, "") end
        if fskv.get(CONFIG_KEYS.TARGET) == nil then fskv.set(CONFIG_KEYS.TARGET, "") end
        if fskv.get(CONFIG_KEYS.LOCKED) == nil then fskv.set(CONFIG_KEYS.LOCKED, "0") end
        return true
    end
    log.error("settings_autostart", "fskv初始化失败")
    return false
end

local function get_enabled()
    if not fskv_initialized then init_fskv() end
    return (fskv.get(CONFIG_KEYS.ENABLED) or "0") == "1"
end

local function set_enabled(value)
    if not fskv_initialized then init_fskv() end
    fskv.set(CONFIG_KEYS.ENABLED, value and "1" or "0")
end

local function get_target()
    if not fskv_initialized then init_fskv() end
    return fskv.get(CONFIG_KEYS.TARGET) or ""
end

local function set_target(path)
    if not fskv_initialized then init_fskv() end
    fskv.set(CONFIG_KEYS.TARGET, path or "")
end

local function get_password()
    if not fskv_initialized then init_fskv() end
    return fskv.get(CONFIG_KEYS.PASSWORD) or ""
end

local function set_password(pwd)
    if not fskv_initialized then init_fskv() end
    fskv.set(CONFIG_KEYS.PASSWORD, pwd or "")
end

local function has_password()
    local pwd = get_password()
    return pwd ~= nil and pwd ~= ""
end

local function verify_password(input)
    local stored = get_password()
    if stored == "" then return true end
    return input == stored
end

-- ==================== 开机自启 ====================

sys.subscribe("OPEN_IDLE_WIN", function()
    if not get_enabled() then return end
    local target = get_target()
    if target == "" then return end

    local installed = exapp.list_installed()
    local found = false
    for _, info in pairs(installed) do
        if info.path == target then found = true; break end
    end
    if not found then return end

    sys.timerStart(function()
        local ok, err = pcall(exapp.open, target)
        if ok then
            autostart_target_path = target
            if has_password() then
                set_locked(true)
                log.info("settings_autostart", "密码锁已激活")
            end
            log.info("settings_autostart", "自启APP路径", target)
        else
            log.error("settings_autostart", "启动失败", err)
        end
    end, 100)
end)

-- ==================== 退出自启APP密码弹窗 ====================

local function show_exit_password_popup()
    local density = _G.density_scale or 1.0
    local screen_w, screen_h = lcd.getSize()
    local win_w = math.floor(screen_w * 0.80)
    local header_h = math.floor(44 * density)
    local mg = math.floor(16 * density)
    local input_h = math.floor(46 * density)
    local btn_h = math.floor(44 * density)
    local label_h = math.floor(22 * density)
    local gap = math.floor(12 * density)
    local content_h = mg + label_h + gap + input_h + gap + btn_h + mg
    local win_h = header_h + content_h

    local popup_container = nil
    local popup_win = nil
    local popup_kb = nil
    local popup_win_id = nil

    local function cleanup()
        -- 销毁顺序：先内后外，先子后父
        if popup_kb then pcall(popup_kb.destroy, popup_kb); popup_kb = nil end
        if popup_win then pcall(popup_win.destroy, popup_win); popup_win = nil end
        if popup_container then pcall(popup_container.destroy, popup_container); popup_container = nil end
        if popup_win_id then exwin.close(popup_win_id); popup_win_id = nil end
    end

    local function on_confirm(pwd)
        local pwd_str = pwd or ""
        cleanup()
        sys.publish("AUTOSTART_EXIT_SUBMIT_PASSWORD", pwd_str)
    end

    local function on_create()
        popup_container = _G.airui.container({
            x = 0, y = 0, w = screen_w, h = screen_h,
            color = 0x000000, color_opacity = 128,
            parent = _G.airui.screen,
        })

        popup_kb = _G.airui.keyboard({
            x = 0, y = -math.floor(20 * density),
            w = screen_w, h = math.floor(240 * density),
            mode = "text", auto_hide = true, preview = true,
            on_commit = function(self) self:hide() end,
        })

        popup_win = _G.airui.win({
            parent = popup_container, title = "退出自启APP",
            w = win_w, h = win_h, close_btn = false, auto_center = true,
            style = { bg_color = 0xFFFFFF, header_bg_color = 0x007AFF, content_bg_color = 0xFFFFFF,
                title_text_color = 0xFFFFFF, radius = 12, title_align = _G.airui.TEXT_ALIGN_CENTER,
                header_height = header_h, content_pad = 0 },
        })

        local y_off = mg
        _G.airui.label({
            parent = popup_win, x = mg, y = y_off, w = win_w - 2 * mg, h = label_h,
            text = "请输入密码以退出自启APP", font_size = math.floor(16 * density),
            color = 0x757575, align = _G.airui.TEXT_ALIGN_CENTER,
        })
        y_off = y_off + label_h + gap

        local pwd_input = _G.airui.textarea({
            parent = popup_win, x = mg, y = y_off, w = win_w - 2 * mg, h = input_h,
            text = "", placeholder = "请输入密码", max_len = 16,
            font_size = math.floor(18 * density), keyboard = popup_kb,
        })
        y_off = y_off + input_h + gap

        local btn_w = math.floor((win_w - 2 * mg - gap) / 2)
        _G.airui.button({
            parent = popup_win, x = mg, y = y_off, w = btn_w, h = btn_h,
            text = "取消", font_size = math.floor(18 * density),
            style = { bg_color = 0xE0E0E0, pressed_bg_color = 0xE0E0E0, text_color = 0x333333, radius = 8,
                border_width = 1, border_color = 0xE0E0E0 },
            on_click = function() cleanup() end,
        })
        _G.airui.button({
            parent = popup_win, x = mg + btn_w + gap, y = y_off, w = btn_w, h = btn_h,
            text = "确定", font_size = math.floor(18 * density),
            style = { bg_color = 0x007AFF, pressed_bg_color = 0x0056B3, text_color = 0xFFFFFF, radius = 8, border_width = 0 },
            on_click = function()
                on_confirm(pwd_input:get_text())
            end,
        })
    end

    popup_win_id = exwin.open({
        on_create = on_create,
        on_destroy = function() end,
    })
end

sys.subscribe("AUTOSTART_REQUEST_EXIT_PASSWORD", function()
    if not autostart_locked then return end
    show_exit_password_popup()
end)

-- ==================== 硬件 RETURN 键拦截 ====================

sys.subscribe("NES_CTRL", function(key)
    if key == "RETURN" and autostart_locked then
        log.info("settings_autostart", "RETURN 被密码锁拦截")
        sys.publish("AUTOSTART_REQUEST_EXIT_PASSWORD")
    end
end)

-- 密码提交验证（退出弹窗）
sys.subscribe("AUTOSTART_EXIT_SUBMIT_PASSWORD", function(password)
    if verify_password(password) then
        log.info("settings_autostart", "密码验证通过，解除锁定")
        set_locked(false)
        local target = autostart_target_path
        autostart_target_path = ""
        -- 锁已解除，让 APP 的 exapp.close 自然退出
        if target ~= "" then
            log.info("settings_autostart", "调用 exapp.close", target)
            local ok, err = pcall(exapp.close, target)
            if not ok then
                log.error("settings_autostart", "exapp.close 失败", err)
            end
        end
    end
end)

-- ==================== 设置页面事件 ====================

sys.subscribe("AUTOSTART_SETTINGS_GET", function()
    local target_name = ""
    local target = get_target()
    if target ~= "" then
        local installed = exapp.list_installed()
        for _, info in pairs(installed) do
            if info.path == target then target_name = info.cn_name or ""; break end
        end
    end
    sys.publish("AUTOSTART_SETTINGS_VALUE", {
        enabled = get_enabled(), target = target,
        target_name = target_name, has_password = has_password(),
    })
end)

sys.subscribe("AUTOSTART_SET_ENABLED", function(value, password)
    if value == false and has_password() then
        if not verify_password(password) then
            sys.publish("AUTOSTART_PASSWORD_RESULT", false, "密码错误")
            return
        end
    end
    set_enabled(value)
    if not value then set_locked(false); autostart_target_path = "" end
    sys.publish("AUTOSTART_PASSWORD_RESULT", true, "")
    sys.publish("AUTOSTART_CONFIG_CHANGED")
end)

sys.subscribe("AUTOSTART_SET_TARGET", function(target_path, password)
    if has_password() and not verify_password(password) then
        sys.publish("AUTOSTART_PASSWORD_RESULT", false, "密码错误")
        return
    end
    set_target(target_path)
    sys.publish("AUTOSTART_PASSWORD_RESULT", true, "")
    sys.publish("AUTOSTART_CONFIG_CHANGED")
end)

-- 组合命令：设置目标APP并自动启用自启开关（从 idle_win 长按菜单调用）
-- 密码校验由调用方在弹出密码验证后传入已验证的密码（空字符串表示无密码）
sys.subscribe("AUTOSTART_SET_TARGET_AND_ENABLE", function(target_path, password)
    if has_password() and not verify_password(password) then
        sys.publish("AUTOSTART_PASSWORD_RESULT", false, "密码错误")
        return
    end
    set_target(target_path)
    set_enabled(true)
    sys.publish("AUTOSTART_PASSWORD_RESULT", true, "")
    sys.publish("AUTOSTART_CONFIG_CHANGED")
end)

sys.subscribe("AUTOSTART_SET_PASSWORD", function(old_password, new_password)
    if has_password() and not verify_password(old_password) then
        sys.publish("AUTOSTART_PASSWORD_RESULT", false, "原密码错误")
        return
    end
    set_password(new_password or "")
    sys.publish("AUTOSTART_PASSWORD_RESULT", true, "")
    sys.publish("AUTOSTART_CONFIG_CHANGED")
end)

sys.subscribe("AUTOSTART_GET_INSTALLED_APPS", function()
    local apps = {}
    local installed = exapp.list_installed()
    for _, info in pairs(installed) do
        table.insert(apps, { name = info.cn_name or "", path = info.path or "", icon = info.icon_path or "" })
    end
    table.sort(apps, function(a, b) return (a.name or "") < (b.name or "") end)
    sys.publish("AUTOSTART_INSTALLED_APPS_VALUE", apps)
end)

-- 监听卸载
sys.subscribe("APP_STORE_INSTALLED_UPDATED", function()
    if autostart_locked and autostart_target_path ~= "" then
        local installed = exapp.list_installed()
        local found = false
        for _, info in pairs(installed) do
            if info.path == autostart_target_path then found = true; break end
        end
        if not found then
            set_locked(false); autostart_target_path = ""
        end
    end
end)

init_fskv()
