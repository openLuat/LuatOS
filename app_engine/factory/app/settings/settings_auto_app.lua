--[[
@module  settings_autostart_app
@summary 后装APP开机自启管理模块
@version 1.0
@date    2026.06.03
@author  江访

功能：
1. fskv 持久化自启配置（开关、目标APP路径、密码）
2. 密码验证（用于退出自启/关闭设置中的自启/重新设置自启）
3. 开机延时3秒自动启动选定的后装APP
4. 拦截 NES_CTRL RETURN 按键，密码保护退出自启APP
]]

-- ==================== 配置常量 ====================

local CONFIG_KEYS = {
    ENABLED  = "app_autostart_enabled",
    TARGET   = "app_autostart_target",
    PASSWORD = "app_autostart_password",
}

-- ==================== 局部变量 ====================

local fskv_initialized = false
local autostart_active = false    -- 自启APP是否正在运行
local autostart_target_path = ""  -- 当前运行的自启APP路径

-- ==================== fskv 读写 ====================

local function init_fskv()
    if fskv_initialized then return true end
    local result = fskv.init()
    if result then
        fskv_initialized = true
        log.info("settings_autostart", "fskv初始化成功")
        if fskv.get(CONFIG_KEYS.ENABLED) == nil then
            fskv.set(CONFIG_KEYS.ENABLED, "0")
        end
        if fskv.get(CONFIG_KEYS.PASSWORD) == nil then
            fskv.set(CONFIG_KEYS.PASSWORD, "")
        end
        if fskv.get(CONFIG_KEYS.TARGET) == nil then
            fskv.set(CONFIG_KEYS.TARGET, "")
        end
        return true
    else
        log.error("settings_autostart", "fskv初始化失败")
        return false
    end
end

local function get_enabled()
    if not fskv_initialized then init_fskv() end
    return (fskv.get(CONFIG_KEYS.ENABLED) or "0") == "1"
end

local function set_enabled(value)
    if not fskv_initialized then init_fskv() end
    fskv.set(CONFIG_KEYS.ENABLED, value and "1" or "0")
    log.info("settings_autostart", "自启开关", value and "开" or "关")
end

local function get_target()
    if not fskv_initialized then init_fskv() end
    return fskv.get(CONFIG_KEYS.TARGET) or ""
end

local function set_target(path)
    if not fskv_initialized then init_fskv() end
    fskv.set(CONFIG_KEYS.TARGET, path or "")
    log.info("settings_autostart", "自启目标", path)
end

local function get_password()
    if not fskv_initialized then init_fskv() end
    return fskv.get(CONFIG_KEYS.PASSWORD) or ""
end

local function set_password(pwd)
    if not fskv_initialized then init_fskv() end
    fskv.set(CONFIG_KEYS.PASSWORD, pwd or "")
    log.info("settings_autostart", "密码已更新")
end

local function has_password()
    local pwd = get_password()
    return pwd ~= nil and pwd ~= ""
end

-- ==================== 密码验证 ====================

local function verify_password(input)
    local stored = get_password()
    if stored == "" then return true end
    return input == stored
end

-- ==================== APP 自启执行 ====================

local function execute_autostart()
    if not get_enabled() then
        log.info("settings_autostart", "自启已关闭，跳过")
        return
    end

    local target = get_target()
    if target == "" then
        log.info("settings_autostart", "未设置自启目标")
        return
    end

    -- 验证目标APP是否仍然已安装
    local installed = exapp.list_installed()
    local found = false
    for _, info in pairs(installed) do
        if info.path == target then
            found = true
            break
        end
    end

    if not found then
        log.warn("settings_autostart", "自启目标已卸载", target)
        return
    end

    log.info("settings_autostart", "启动自启APP", target)
    local ok, err = pcall(exapp.open, target)
    if ok then
        autostart_active = true
        autostart_target_path = target
        -- 有密码则拦截 RETURN 按键，不让 APP 直接收到 NES_CTRL
        _G.autostart_return_capture = has_password()
    else
        log.error("settings_autostart", "自启APP启动失败", err)
    end
end

-- ==================== 退出自启APP（密码保护） ====================

local function request_exit_autostart()
    if not autostart_active then return end

    if not has_password() then
        -- 无密码，允许 APP 自行处理退出（恢复 NES_CTRL RETURN 正常发布）
        log.info("settings_autostart", "无密码，允许正常退出")
        _G.autostart_return_capture = false
        autostart_active = false
        autostart_target_path = ""
        -- 直接发布 NES_CTRL RETURN 让 APP 退出
        sys.publish("NES_CTRL", "RETURN")
    else
        -- 有密码，发布事件让UI弹出密码验证
        log.info("settings_autostart", "需要密码验证退出自启APP")
        sys.publish("AUTOSTART_REQUEST_EXIT_PASSWORD")
    end
end

-- 密码验证结果回调（由 UI 模块发布）
local function on_exit_password_verified(success)
    if success then
        log.info("settings_autostart", "密码验证通过，退出自启APP")
        _G.autostart_return_capture = false
        autostart_active = false
        autostart_target_path = ""
        sys.publish("NES_CTRL", "RETURN")  -- 发送RETURN让APP自行退出
    else
        log.info("settings_autostart", "密码验证失败，不退出")
    end
end

-- ==================== 监听 APP 安装/卸载变化 ====================

local function on_installed_updated()
    if autostart_active and autostart_target_path ~= "" then
        local installed = exapp.list_installed()
        local found = false
        for _, info in pairs(installed) do
            if info.path == autostart_target_path then
                found = true
                break
            end
        end
        if not found then
            log.info("settings_autostart", "自启APP已被卸载，标记为非活跃")
            autostart_active = false
            autostart_target_path = ""
            _G.autostart_return_capture = false
        end
    end
end

-- ==================== 事件处理 ====================

-- 获取自启配置（供 UI 查询）
sys.subscribe("AUTOSTART_SETTINGS_GET", function()
    local enabled = get_enabled()
    local target = get_target()
    local pwd_set = has_password()

    local target_name = ""
    if target ~= "" then
        local installed = exapp.list_installed()
        for _, info in pairs(installed) do
            if info.path == target then
                target_name = info.cn_name or ""
                break
            end
        end
    end

    sys.publish("AUTOSTART_SETTINGS_VALUE", {
        enabled = enabled,
        target = target,
        target_name = target_name,
        has_password = pwd_set,
    })
    log.info("settings_autostart", "上报自启配置", enabled, target_name, pwd_set)
end)

-- 设置开关（关闭时需要密码验证，开启不需要）
sys.subscribe("AUTOSTART_SET_ENABLED", function(value, password)
    if value == false and has_password() then
        if not verify_password(password) then
            sys.publish("AUTOSTART_PASSWORD_RESULT", false, "密码错误")
            return
        end
    end
    set_enabled(value)
    sys.publish("AUTOSTART_PASSWORD_RESULT", true, "")
    sys.publish("AUTOSTART_CONFIG_CHANGED")
end)

-- 设置/修改自启目标APP（需要密码验证）
sys.subscribe("AUTOSTART_SET_TARGET", function(target_path, password)
    if has_password() then
        if not verify_password(password) then
            sys.publish("AUTOSTART_PASSWORD_RESULT", false, "密码错误")
            return
        end
    end
    set_target(target_path)
    sys.publish("AUTOSTART_PASSWORD_RESULT", true, "")
    sys.publish("AUTOSTART_CONFIG_CHANGED")
    log.info("settings_autostart", "自启目标已更新", target_path)
end)

-- 设置/修改密码
sys.subscribe("AUTOSTART_SET_PASSWORD", function(old_password, new_password)
    if has_password() then
        if not verify_password(old_password) then
            sys.publish("AUTOSTART_PASSWORD_RESULT", false, "原密码错误")
            return
        end
    end
    set_password(new_password or "")
    sys.publish("AUTOSTART_PASSWORD_RESULT", true, "")
    sys.publish("AUTOSTART_CONFIG_CHANGED")
end)

-- 通用密码验证
sys.subscribe("AUTOSTART_VERIFY_PASSWORD", function(password)
    local ok = verify_password(password)
    sys.publish("AUTOSTART_PASSWORD_RESULT", ok, ok and "" or "密码错误")
end)

-- 退出自启APP时的密码提交
sys.subscribe("AUTOSTART_EXIT_SUBMIT_PASSWORD", function(password)
    local ok = verify_password(password)
    sys.publish("AUTOSTART_EXIT_PASSWORD_RESULT", ok)
end)

-- 获取已安装APP列表（供UI选择APP用）
sys.subscribe("AUTOSTART_GET_INSTALLED_APPS", function()
    local apps = {}
    local installed = exapp.list_installed()
    for _, info in pairs(installed) do
        table.insert(apps, {
            name = info.cn_name or "",
            path = info.path or "",
            icon = info.icon_path or "",
        })
    end
    -- 按安装时间排序（后安装的在前）
    table.sort(apps, function(a, b)
        return (a.name or "") < (b.name or "")
    end)
    sys.publish("AUTOSTART_INSTALLED_APPS_VALUE", apps)
end)

-- 拦截 NES_CTRL RETURN 按键 → 退出自启APP
-- 注意：nes_key_app 发现有密码保护时不会发 NES_CTRL("RETURN")，
-- 而是发 AUTOSTART_RETURN_PRESSED，在此处理
sys.subscribe("AUTOSTART_RETURN_PRESSED", function()
    log.info("settings_autostart", "检测到RETURN按键，请求退出自启APP")
    request_exit_autostart()
end)

-- 同时保留 NES_CTRL 订阅以防未拦截到的情况
sys.subscribe("NES_CTRL", function(key)
    if key == "RETURN" and autostart_active then
        log.info("settings_autostart", "NES_CTRL RETURN (fallback)")
        request_exit_autostart()
    end
end)

-- 监听安装变化
sys.subscribe("APP_STORE_INSTALLED_UPDATED", on_installed_updated)

-- 订阅退出密码验证结果
sys.subscribe("AUTOSTART_EXIT_PASSWORD_RESULT", on_exit_password_verified)

-- ==================== 开机自启延时执行 ====================

-- 等待 idle_win 创建完成后再延时 1 秒执行自启，确保 exwin 窗口栈已初始化
sys.subscribe("OPEN_IDLE_WIN", function()
    sys.timerStart(function()
        execute_autostart()
    end, 100)
end)

init_fskv()
