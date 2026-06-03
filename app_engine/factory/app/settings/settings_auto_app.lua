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
}

-- ==================== 局部变量 ====================

local fskv_initialized = false
local autostart_locked = false    -- 密码锁状态（拦截硬件 RETURN）
local autostart_target_path = ""

-- ==================== fskv 读写 ====================

local function init_fskv()
    if fskv_initialized then return true end
    local result = fskv.init()
    if result then
        fskv_initialized = true
        if fskv.get(CONFIG_KEYS.ENABLED) == nil then fskv.set(CONFIG_KEYS.ENABLED, "0") end
        if fskv.get(CONFIG_KEYS.PASSWORD) == nil then fskv.set(CONFIG_KEYS.PASSWORD, "") end
        if fskv.get(CONFIG_KEYS.TARGET) == nil then fskv.set(CONFIG_KEYS.TARGET, "") end
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
                autostart_locked = true
            end
        else
            log.error("settings_autostart", "启动失败", err)
        end
    end, 100)
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
        sys.publish("AUTOSTART_EXIT_PASSWORD_RESULT", true)
        log.info("settings_autostart", "密码验证通过，解除锁定")
        autostart_locked = false
        autostart_target_path = ""
        exwin.return_idle()
    else
        sys.publish("AUTOSTART_EXIT_PASSWORD_RESULT", false)
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
    if not value then autostart_locked = false; autostart_target_path = "" end
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
            autostart_locked = false; autostart_target_path = ""
        end
    end
end)

init_fskv()
