--[[
@module  backup_app
@summary 备份管理模块
@version 1.0
@date    2026.09.04
@author  江访
@usage
MD5校验、自动每日备份(可配置保留份数)、手动备份/恢复。
恢复标记文件(restore_pending.json)下次开机生效。
]]

local backup_app = {}

local TASK_NAME = "backup_app"
local BACKUP_DIR = "/backup"

local _device_config = nil
local _auto_backup_timer = nil

local function init_backup_dir()
    if not io.dexist(BACKUP_DIR) then
        local ok = io.mkdir(BACKUP_DIR)
        if ok then
            log.info(TASK_NAME, "mkdir success", BACKUP_DIR)
        else
            log.error(TASK_NAME, "mkdir failed", BACKUP_DIR)
        end
    end
end

local function get_backup_dir_info()
    init_backup_dir()
    local ok, total_blocks, used_blocks, block_size = io.fsstat(BACKUP_DIR)
    if not ok then return 0, 0 end
    return used_blocks * block_size, total_blocks * block_size
end

local function parse_time_from_filename(filename)
    local year = filename:sub(8, 11)
    local month = filename:sub(12, 13)
    local day = filename:sub(14, 15)
    local hour = filename:sub(17, 18)
    local min = filename:sub(19, 20)
    local sec = filename:sub(21, 22)
    if year and month and day and hour and min and sec then
        return string.format("%s-%s-%s %s:%s:%s", year, month, day, hour, min, sec)
    end
    return "--"
end

local function list_backup_files()
    init_backup_dir()
    local ret, data = io.lsdir(BACKUP_DIR, 100, 0)
    if not ret then return {} end
    local result = {}
    for _, item in ipairs(data) do
        table.insert(result, {
            name = item.name,
            size = item.size,
            time = parse_time_from_filename(item.name)
        })
    end
    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end

local function delete_backup_file(filename)
    local full_path = BACKUP_DIR .. "/" .. filename
    local ok = os.remove(full_path)
    if ok then
        log.info(TASK_NAME, "delete success", filename)
    else
        log.error(TASK_NAME, "delete failed", filename)
    end
    return ok
end

local function cleanup_old_backups(retain_count)
    local files = list_backup_files()
    if #files <= retain_count then return end
    local to_delete = #files - retain_count
    for i = 1, to_delete do
        if files[i] and files[i].name then
            delete_backup_file(files[i].name)
        end
    end
end

local function create_backup()
    init_backup_dir()

    local config_path = "/device_config.json"
    local f = io.open(config_path, "r")
    if not f then
        log.error(TASK_NAME, "device_config not found")
        return false
    end

    local config_content = f:read("*a")
    f:close()

    local ok, config = pcall(json.decode, config_content)
    if not ok then
        log.error(TASK_NAME, "config decode failed")
        return false
    end

    local checksum = crypto.md5(config_content)
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local filename = BACKUP_DIR .. "/backup_" .. timestamp .. ".json"

    -- 检查文件是否存在
    local full_path = filename
    local suffix = 0
    while io.exists(full_path) do
        suffix = suffix + 1
        full_path = string.format("%s/backup_%s_%d.json", BACKUP_DIR, timestamp, suffix)
    end
    filename = full_path

    local backup_data = {
        time = os.date("%Y-%m-%d %H:%M:%S"),
        config = config,
        raw_json = config_content,
        checksum = checksum
    }

    local fd = io.open(filename, "w")
    if fd then
        fd:write(json.encode(backup_data))
        fd:close()
        log.info(TASK_NAME, "backup created", filename, "checksum=" .. checksum)

        local retain_count = (config.backup and config.backup.auto_backup and config.backup.auto_backup.retain_count) or 3
        cleanup_old_backups(retain_count)

        local backup_cfg = _device_config and _device_config.backup or {}
        local auto_backup = backup_cfg.auto_backup or {enabled = true, period = 1, retain_count = 3}
        sys.publish("CONFIG_UPDATE_TRIGGER", "backup", {
            auto_backup = auto_backup,
            last_backup_time = os.date("%Y-%m-%d %H:%M:%S")
        })

        return true
    end
    log.error(TASK_NAME, "backup failed")
    return false
end

local function restore_backup(filename)
    local full_path = BACKUP_DIR .. "/" .. filename
    local fd = io.open(full_path, "r")
    if not fd then
        return false, "文件不存在"
    end

    local content = fd:read("*a")
    fd:close()

    local ok, backup_data = pcall(json.decode, content)
    if not ok or not backup_data then
        return false, "JSON解析失败"
    end

    if backup_data.checksum and backup_data.raw_json then
        local calc_checksum = crypto.md5(backup_data.raw_json)
        if calc_checksum ~= backup_data.checksum then
            return false, "校验失败"
        end
    end

    sys.publish("BACKUP_RESTORE", backup_data.config)
    return true, ""
end

local function start_auto_backup_timer()
    if _auto_backup_timer then
        sys.timerStop(_auto_backup_timer)
        _auto_backup_timer = nil
    end

    local backup_cfg = _device_config and _device_config.backup
    if not backup_cfg or not backup_cfg.auto_backup or not backup_cfg.auto_backup.enabled then
        log.info(TASK_NAME, "auto backup disabled")
        return
    end

    local period_days = backup_cfg.auto_backup.period or 1
    local interval_ms = period_days * 24 * 60 * 60 * 1000

    _auto_backup_timer = sys.timerLoopStart(function()
        if create_backup() then
            sys.publish("BACKUP_LIST_QUERY")
        end
    end, interval_ms)

    log.info(TASK_NAME, "auto backup timer started", "period=" .. period_days .. "d")
end

local function subscribe_events()
    sys.subscribe("BACKUP_STORAGE_QUERY", function()
        local used, total = get_backup_dir_info()
        sys.publish("BACKUP_STORAGE_UPDATE", used, total)
    end)

    sys.subscribe("BACKUP_LIST_QUERY", function()
        local files = list_backup_files()
        sys.publish("BACKUP_LIST_UPDATE", files)
    end)

    sys.subscribe("BACKUP_FILE_DELETE", function(filename)
        delete_backup_file(filename)
        sys.publish("BACKUP_LIST_QUERY")
    end)

    sys.subscribe("BACKUP_CREATE_NOW", function()
        if create_backup() then
            sys.publish("BACKUP_LIST_QUERY")
        end
    end)

    sys.subscribe("BACKUP_RESTORE_NOW", function(filename)
        local ok, err = restore_backup(filename)
        sys.publish("BACKUP_RESTORE_RESULT", ok, err or "")
    end)

    sys.subscribe("BACKUP_CONFIG_QUERY", function()
        local backup_cfg = _device_config and _device_config.backup
        sys.publish("BACKUP_CONFIG_UPDATE", backup_cfg)
    end)

    sys.subscribe("BACKUP_CONFIG_SET", function(new_cfg)
        if _device_config then
            _device_config.backup = new_cfg
            start_auto_backup_timer()
            sys.publish("CONFIG_UPDATE_TRIGGER", "backup", new_cfg)
            sys.publish("BACKUP_CONFIG_UPDATE", new_cfg)
        end
    end)
end

function backup_app.init(config)
    _device_config = config
    init_backup_dir()
    start_auto_backup_timer()
    subscribe_events()
    log.info(TASK_NAME, "init done")
end

return backup_app
