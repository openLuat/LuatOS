--[[
@module  exmtn
@summary 运维日志扩展库，负责日志的持久化存储
@version 1.0
@date    2024.11
@usage
exmtn.init(1, 0)  -- 初始化，1个块，缓存写入
exmtn.log("info", "tag", "message", 123)  -- 输出运维日志
]]

local exmtn = {}

-- 常量定义
local LOG_MTN_CACHE_SIZE = 4096
local LOG_MTN_FILE_COUNT = 4
local LOG_MTN_CONFIG_FILE = "/exmtn.trc"
local LOG_MTN_DEFAULT_BLOCKS_DIVISOR = 40
local LOG_MTN_ADD_WRITE_THRESHOLD = 256
local LOG_MTN_CONFIG_VERSION = 1

-- 写入方式常量
exmtn.CACHE_WRITE = 0
exmtn.ADD_WRITE = 1

-- 内部状态
local ctx = {
    inited = false,
    enabled = false,
    cur_index = 1,           -- 1-4
    block_size = 4096,       -- 默认块大小
    blocks_per_file = 1,     -- 每文件块数
    file_limit = 4096,       -- 每文件大小限制
    write_way = 0,           -- 0=缓存写入, 1=直接追加
    cache = "",              -- 缓存缓冲区
    cache_used = 0,          -- 缓存已使用字节数
}

-- 重置缓存
local function reset_cache()
    ctx.cache = ""
    ctx.cache_used = 0
end

-- 获取当前文件路径
local function get_file_path(index)
    return string.format("/hzmtn%d.trc", index or ctx.cur_index)
end

-- 获取当前文件大小
local function get_current_file_size()
    local path = get_file_path()
    local file = io.open(path, "rb")
    if not file then
        return 0
    end
    local size = file:seek("end")
    file:close()
    -- file:seek("end") 返回文件大小，如果失败返回 nil
    if size and size > 0 then
        return size
    end
    return 0
end

-- 检查文件是否存在
local function file_exists(path)
    local file = io.open(path, "rb")
    if file then
        file:close()
        return true
    end
    return false
end

-- 检查所有日志文件是否存在
local function files_exist()
    for i = 1, LOG_MTN_FILE_COUNT do
        local path = get_file_path(i)
        if file_exists(path) then
            return true
        end
    end
    return false
end

-- 删除所有日志文件
local function remove_files()
    for i = 1, LOG_MTN_FILE_COUNT do
        local path = get_file_path(i)
        os.remove(path)
    end
end

-- 创建空文件
local function create_files()
    for i = 1, LOG_MTN_FILE_COUNT do
        local path = get_file_path(i)
        local file = io.open(path, "wb")
        if file then
            file:close()
        end
    end
end

-- 读取配置文件
local function load_config()
    local file = io.open(LOG_MTN_CONFIG_FILE, "rb")
    if not file then
        return nil  -- 文件不存在，返回 nil
    end
    
    local content = file:read("*a")
    file:close()
    
    if not content or #content == 0 then
        return nil  -- 文件为空
    end
    
    -- 解析配置：格式为 "VERSION=1\nINDEX=2\nBLOCKS=10\nWRITE_WAY=0\n"
    local config = {}
    for line in content:gmatch("[^\r\n]+") do
        -- 移除首尾空白字符
        line = line:match("^%s*(.-)%s*$") or line
        local key, value = line:match("([^=]+)=(.+)")
        if key and value then
            -- 移除 key 和 value 的首尾空白字符
            key = key:match("^%s*(.-)%s*$") or key
            value = value:match("^%s*(.-)%s*$") or value
            local num_value = tonumber(value)
            if num_value then
                config[key] = num_value
            else
                config[key] = value
            end
        end
    end
    
    -- 验证版本号
    if config.VERSION ~= LOG_MTN_CONFIG_VERSION then
        return nil  -- 版本不匹配
    end
    
    return config
end

-- 保存配置文件
local function save_config(index, blocks, write_way)
    local content = string.format("VERSION=%d\nINDEX=%d\nBLOCKS=%d\nWRITE_WAY=%d\n", 
        LOG_MTN_CONFIG_VERSION, index, blocks, write_way)
    
    local file = io.open(LOG_MTN_CONFIG_FILE, "wb")
    if not file then
        log.warn("exmtn", "无法打开配置文件: " .. LOG_MTN_CONFIG_FILE)
        return false
    end
    
    local ok = file:write(content)
    file:close()
    
    if not ok then
        log.warn("exmtn", "写入配置文件失败: " .. LOG_MTN_CONFIG_FILE)
        return false
    end
    
    return true
end

-- 更新索引（同时保存完整配置）
local function update_index(index)
    return save_config(index, ctx.blocks_per_file, ctx.write_way)
end

-- 格式化时间戳
-- 返回格式: [2025-11-05 15:06:49.947][00000027.994]
local function format_timestamp()
    -- 获取系统运行时间（毫秒）
    local ticks_ms = 0
    if mcu and mcu.ticks then
        local ticks = mcu.ticks()
        if ticks then
            ticks_ms = ticks
        end
    end
    
    -- 获取当前日期时间
    local date_time_str = ""
    local ms = 0
    
    if os and os.date then
        -- 获取当前日期时间字符串: 2025-11-05 15:06:49
        local dt = os.date("%Y-%m-%d %H:%M:%S")
        if dt then
            -- 计算毫秒：使用系统运行时间的毫秒部分
            -- 如果 RTC 已设置，时间会更准确
            ms = ticks_ms % 1000
            date_time_str = string.format("%s.%03d", dt, ms)
        end
    end
    
    -- 如果无法获取日期时间，使用默认格式
    if date_time_str == "" then
        date_time_str = "1970-01-01 00:00:00.000"
    end
    
    -- 计算系统运行时间（秒.毫秒）
    local uptime_sec = math.floor(ticks_ms / 1000)
    local uptime_ms = ticks_ms % 1000
    
    -- 格式化运行时间部分: 00000027.994（固定宽度，9位整数+3位小数）
    local uptime_str = string.format("%09d.%03d", uptime_sec, uptime_ms)
    
    -- 返回完整时间戳
    return string.format("[%s][%s]", date_time_str, uptime_str)
end

-- 格式化调试信息
local function format_debug_info(level, include_level)
    local info = debug.getinfo(2, "Sl")
    if not info or not info.source then
        return nil
    end
    
    local src = info.source
    -- 跳过第一个字符（@ 或 =）
    if src:sub(1, 1) == "@" or src:sub(1, 1) == "=" then
        src = src:sub(2)
    end
    
    local line = info.currentline or 0
    if line > 64 * 1024 then
        line = 0
    end
    
    if include_level and level then
        return string.format("%s/%s:%d", level, src, line)
    else
        return string.format("%s:%d", src, line)
    end
end

-- 格式化消息（与 log.info/warn/error 格式一致，但添加时间戳前缀）
local function format_message(level, tag, ...)
    local argc = select("#", ...)
    
    -- 获取 log.style 配置
    local log_style = 0
    if log and log.style then
        log_style = log.style() or 0
    end
    
    -- 根据级别确定日志标识
    local level_char = "I"  -- 默认 info
    if level == "warn" then
        level_char = "W"
    elseif level == "error" then
        level_char = "E"
    end
    
    local msg = ""
    local dbg_info_with_level = format_debug_info(level_char, true)
    local dbg_info_only = format_debug_info(nil, false)
    
    if log_style == 0 then
        -- LOG_STYLE_NORMAL: "I/user.tag arg1 arg2 ...\n"
        msg = string.format("%s/user.%s", level_char, tag)
        for i = 1, argc do
            local arg = select(i, ...)
            msg = msg .. " " .. tostring(arg)
        end
    elseif log_style == 1 then
        -- LOG_STYLE_DEBUG_INFO: "I/file.lua:123 tag arg1 arg2 ...\n"
        if dbg_info_with_level then
            msg = dbg_info_with_level
        else
            msg = level_char
        end
        msg = msg .. " " .. tag
        for i = 1, argc do
            local arg = select(i, ...)
            msg = msg .. " " .. tostring(arg)
        end
    else
        -- LOG_STYLE_FULL: "I/user.tag file.lua:123 arg1 arg2 ...\n"
        msg = string.format("%s/user.%s", level_char, tag)
        if dbg_info_only then
            msg = msg .. " " .. dbg_info_only
        end
        for i = 1, argc do
            local arg = select(i, ...)
            msg = msg .. " " .. tostring(arg)
        end
    end
    
    msg = msg .. "\n"
    
    -- 添加时间戳前缀
    local timestamp = format_timestamp()
    return timestamp .. " " .. msg
end

-- 刷新缓存到文件
local function flush_cache()
    if ctx.cache_used == 0 then
        return true
    end
    
    local path = get_file_path()
    local file = io.open(path, "ab")
    if not file then
        log.warn("exmtn", "无法打开文件: " .. path)
        return false
    end
    
    -- file:write 返回 true/false 或 nil，不返回字节数
    local ok = file:write(ctx.cache)
    file:close()
    
    if not ok then
        log.warn("exmtn", "写入文件失败: " .. path)
        return false
    end
    
    reset_cache()
    return true
end

-- 直接写入文件（ADD_WRITE 模式）
local function direct_write(data)
    local path = get_file_path()
    local file = io.open(path, "ab")
    if not file then
        log.warn("exmtn", "无法打开文件: " .. path)
        return false
    end
    
    -- file:write 返回 true/false 或 nil，不返回字节数
    local ok = file:write(data)
    file:close()
    
    if not ok then
        log.warn("exmtn", "写入文件失败: " .. path)
        return false
    end
    
    return true
end

-- 将数据追加到缓存或直接写入
local function buffer_append(data)
    if not data or #data == 0 then
        return true
    end
    
    local len = #data
    
    -- ADD_WRITE 模式：直接写入文件
    if ctx.write_way == exmtn.ADD_WRITE then
        -- 小数据先缓存，累积到阈值再写入
        if len < LOG_MTN_ADD_WRITE_THRESHOLD then
            if ctx.cache_used + len > LOG_MTN_CACHE_SIZE then
                if not flush_cache() then
                    return false
                end
            end
            ctx.cache = ctx.cache .. data
            ctx.cache_used = ctx.cache_used + len
            -- 如果累积到阈值，立即写入
            if ctx.cache_used >= LOG_MTN_ADD_WRITE_THRESHOLD then
                return flush_cache()
            end
            return true
        end
        -- 大数据直接写入
        return direct_write(data)
    end
    
    -- CACHE_WRITE 模式：原有逻辑
    if len > LOG_MTN_CACHE_SIZE then
        -- 先刷新缓存
        if not flush_cache() then
            return false
        end
        -- 大数据直接写入
        return direct_write(data)
    end
    
    -- 检查缓存是否足够
    if ctx.cache_used + len > LOG_MTN_CACHE_SIZE then
        if not flush_cache() then
            return false
        end
    end
    
    ctx.cache = ctx.cache .. data
    ctx.cache_used = ctx.cache_used + len
    return true
end

-- 写入日志到文件
local function write_to_file(msg)
    if not ctx.enabled then
        return true  -- 未启用时返回成功，不写入
    end
    
    local len = #msg
    
    -- CACHE_WRITE 模式
    if ctx.write_way == exmtn.CACHE_WRITE then
        -- 检查文件大小 + 缓存大小 + 当前数据是否会超过限制
        -- 如果会超过，先刷新缓存
        if ctx.cache_used > 0 then
            local file_sz = get_current_file_size()
            if file_sz + ctx.cache_used + len > ctx.file_limit then
                -- 先刷新缓存
                if not flush_cache() then
                    return false
                end
                -- 重新获取文件大小
                file_sz = get_current_file_size()
                -- 检查文件是否已满
                if file_sz >= ctx.file_limit then
                    -- 文件已满，切换到下一个文件
                    ctx.cur_index = (ctx.cur_index % LOG_MTN_FILE_COUNT) + 1
                    local path = get_file_path()
                    local file = io.open(path, "wb")
                    if file then
                        file:close()
                    end
                    if not update_index(ctx.cur_index) then
                        log.warn("exmtn", "更新索引失败")
                        return false
                    end
                    reset_cache()
                end
            end
        else
            -- 缓存为空，检查文件大小
            local file_sz = get_current_file_size()
            if file_sz + len > ctx.file_limit then
                -- 文件已满，切换到下一个文件
                ctx.cur_index = (ctx.cur_index % LOG_MTN_FILE_COUNT) + 1
                local path = get_file_path()
                local file = io.open(path, "wb")
                if file then
                    file:close()
                end
                if not update_index(ctx.cur_index) then
                    log.warn("exmtn", "更新索引失败")
                    return false
                end
                reset_cache()
            end
        end
        
        -- 如果加入这条数据后缓存会满，先刷新缓存
        if ctx.cache_used + len > LOG_MTN_CACHE_SIZE then
            if not flush_cache() then
                return false
            end
            
            -- 刷新后再次检查文件大小
            local file_sz = get_current_file_size()
            if file_sz >= ctx.file_limit then
                -- 文件已满，切换到下一个文件
                ctx.cur_index = (ctx.cur_index % LOG_MTN_FILE_COUNT) + 1
                local path = get_file_path()
                local file = io.open(path, "wb")
                if file then
                    file:close()
                end
                if not update_index(ctx.cur_index) then
                    log.warn("exmtn", "更新索引失败")
                    return false
                end
                reset_cache()
            end
        end
        
        -- 加入缓存
        return buffer_append(msg)
    else
        -- ADD_WRITE 模式：先刷新缓存，确保文件大小准确
        if ctx.cache_used > 0 then
            if not flush_cache() then
                return false
            end
        end
        
        -- 获取当前文件大小
        local file_sz = get_current_file_size()
        
        -- 检查当前文件是否已写满
        if file_sz >= ctx.file_limit then
            -- 文件已满，切换到下一个文件
            ctx.cur_index = (ctx.cur_index % LOG_MTN_FILE_COUNT) + 1
            local path = get_file_path()
            local file = io.open(path, "wb")
            if file then
                file:close()
            end
            if not update_index(ctx.cur_index) then
                log.warn("exmtn", "更新索引失败")
                return false
            end
            reset_cache()
        end
        
        -- 检查当前数据是否能放入当前文件
        if file_sz + len > ctx.file_limit then
            -- 当前数据放不下，切换到下一个文件
            ctx.cur_index = (ctx.cur_index % LOG_MTN_FILE_COUNT) + 1
            local path = get_file_path()
            local file = io.open(path, "wb")
            if file then
                file:close()
            end
            if not update_index(ctx.cur_index) then
                log.warn("exmtn", "更新索引失败")
                return false
            end
            reset_cache()
        end
        
        -- 加入缓存或直接写入（buffer_append 会根据大小决定）
        return buffer_append(msg)
    end
end

--[[
初始化运维日志
@api exmtn.init(blocks, write_way)
@int blocks 每个文件的块数，0表示禁用，正整数表示块数量
@int write_way 写入方式，可选参数。exmtn.CACHE_WRITE(0)表示缓存写入，exmtn.ADD_WRITE(1)表示直接追加写入，默认为exmtn.CACHE_WRITE
@return boolean 成功返回true，失败返回false
@usage
exmtn.init(1, exmtn.CACHE_WRITE)  -- 初始化，1个块，缓存写入
]]
function exmtn.init(blocks, write_way)
    -- 参数校验
    if blocks == nil then
        blocks = 0
    end
    blocks = math.floor(blocks)
    if blocks < 0 then
        log.warn("exmtn", "无效的块数")
        return false
    end
    
    write_way = write_way or exmtn.CACHE_WRITE
    if write_way ~= exmtn.CACHE_WRITE and write_way ~= exmtn.ADD_WRITE then
        write_way = exmtn.CACHE_WRITE
    end
    
    -- 如果禁用
    if blocks == 0 then
        reset_cache()
        remove_files()
        ctx.enabled = false
        ctx.cur_index = 1
        -- 删除配置文件
        os.remove(LOG_MTN_CONFIG_FILE)
        ctx.inited = true
        return true
    end
    
    -- 读取文件系统信息
    if not ctx.inited then
        ctx.block_size = 4096
        ctx.blocks_per_file = 1
        
        -- 尝试获取文件系统信息（需要 fs 模块支持）
        -- fs.fsstat 返回: success, total_blocks, used_blocks, block_size, fs_type
        if fs and fs.fsstat then
            local success, total_blocks, used_blocks, block_size, fs_type = fs.fsstat("/")
            if success and block_size and block_size > 0 then
                ctx.block_size = block_size
                if total_blocks and total_blocks > 0 then
                    local def_blocks = math.floor(total_blocks / LOG_MTN_DEFAULT_BLOCKS_DIVISOR)
                    if def_blocks > 0 then
                        ctx.blocks_per_file = def_blocks
                    end
                end
            end
        end
    end
    
    -- 读取配置文件（仅在首次初始化时读取）
    if not ctx.inited then
        local config = load_config()
        if config then
            -- 读取索引
            if config.INDEX and config.INDEX >= 1 and config.INDEX <= LOG_MTN_FILE_COUNT then
                ctx.cur_index = config.INDEX
            end
            
            -- 读取块数配置
            if config.BLOCKS and config.BLOCKS > 0 then
                ctx.blocks_per_file = config.BLOCKS
            end
            
            -- 读取写入方式配置
            if config.WRITE_WAY == 0 or config.WRITE_WAY == 1 then
                ctx.write_way = config.WRITE_WAY
            end

            log.info("exmtn", "读取索引", ctx.cur_index)
            log.info("exmtn", "读取块数配置", ctx.blocks_per_file)
            log.info("exmtn", "读取写入方式配置", ctx.write_way)
        end
    end
    
    -- 检查配置是否变化
    -- 如果已初始化，比较当前配置和新配置；如果未初始化，不需要判断（首次初始化总是"变化"的）
    local config_changed = false
    if ctx.inited then
        -- 已初始化：比较当前配置和新传入的配置
        config_changed = (ctx.blocks_per_file ~= blocks) or (ctx.write_way ~= write_way)
    end
    -- 未初始化：config_changed 保持为 false，因为首次初始化不算"变化"

    log.info("exmtn", "配置变化", config_changed)
    -- 更新配置
    ctx.blocks_per_file = blocks
    ctx.write_way = write_way
    ctx.file_limit = ctx.block_size * ctx.blocks_per_file
    if ctx.file_limit == 0 then
        ctx.file_limit = LOG_MTN_CACHE_SIZE
    end
    
    -- 处理文件的三种情况
    if config_changed then
        -- 情况1：配置变化，清空文件
        log.info("exmtn", "配置变化，清空文件")
        reset_cache()
        remove_files()
        create_files()
        ctx.cur_index = 1
    elseif files_exist() then
        -- 情况2：配置没有变化，文件存在，根据配置文件中保存的文件指针继续写
        log.info("exmtn", "配置未变化，文件存在，继续写入")
        -- ctx.cur_index 已经从配置文件读取（如果是首次初始化）或保持当前值（如果已初始化），不需要重置
    else
        -- 情况3：配置没有变化，文件不存在，创建文件
        log.info("exmtn", "配置未变化，文件不存在，创建文件")
        create_files()
        -- ctx.cur_index 已经从配置文件读取（如果是首次初始化）或保持当前值（如果已初始化），不需要重置
    end
    
    -- 保存配置到文件
    if not save_config(ctx.cur_index, blocks, write_way) then
        log.warn("exmtn", "保存配置失败")
        return false
    end
    
    ctx.enabled = true
    ctx.inited = true
    
    -- 打印初始化信息
    if blocks > 0 then
        local total_size = ctx.file_limit * LOG_MTN_FILE_COUNT
        local file_size_mb = ctx.file_limit / (1024 * 1024)
        local total_size_mb = total_size / (1024 * 1024)
        local file_size_kb = ctx.file_limit / 1024
        local total_size_kb = total_size / 1024
        
        if ctx.file_limit >= 1024 * 1024 then
            log.info("exmtn", string.format("初始化成功: 每个文件 %.2f MB (%d 块 × %d 字节), 总空间 %.2f MB (%d 个文件)", 
                file_size_mb, ctx.blocks_per_file, ctx.block_size, total_size_mb, LOG_MTN_FILE_COUNT))
        elseif ctx.file_limit >= 1024 then
            log.info("exmtn", string.format("初始化成功: 每个文件 %.2f KB (%d 块 × %d 字节), 总空间 %.2f KB (%d 个文件)", 
                file_size_kb, ctx.blocks_per_file, ctx.block_size, total_size_kb, LOG_MTN_FILE_COUNT))
        else
            log.info("exmtn", string.format("初始化成功: 每个文件 %d 字节 (%d 块 × %d 字节), 总空间 %d 字节 (%d 个文件)", 
                ctx.file_limit, ctx.blocks_per_file, ctx.block_size, total_size, LOG_MTN_FILE_COUNT))
        end
    end
    
    return true
end

--[[
输出运维日志并写入文件
@api exmtn.log(level, tag, ...)
@string level 日志级别，必须是 "info", "warn", 或 "error"
@string tag 日志标识，必须是字符串
@... 需打印的参数
@return boolean 成功返回true，失败返回false
@usage
exmtn.log("info", "message", 123)
exmtn.log("warn", "message", 456)
exmtn.log("error", "message", 789)
]]
function exmtn.log(level, tag, ...)
    if not level or type(level) ~= "string" then
        log.warn("exmtn", "level 必须是字符串")
        return false
    end
    
    if not tag or type(tag) ~= "string" then
        log.warn("exmtn", "tag 必须是字符串")
        return false
    end
    
    -- 根据级别调用对应的底层函数（会被日志级别过滤）
    if level == "info" then
        log.info(tag, ...)
    elseif level == "warn" then
        log.warn(tag, ...)
    elseif level == "error" then
        log.error(tag, ...)
    else
        log.warn("exmtn", "level 必须是 'info', 'warn' 或 'error'")
        return false
    end
    
    -- 格式化消息（用于文件写入）
    local msg = format_message(level, tag, ...)
    if not msg then
        log.warn("exmtn", "格式化消息失败")
        return false
    end
    
    -- 写入文件（不受日志级别影响）
    return write_to_file(msg)
end

--[[
获取当前配置
@api exmtn.get_config()
@return table|nil 配置信息，失败返回nil
@usage
local config = exmtn.get_config()
if config then
    log.info("exmtn", "blocks:", config.blocks, "write_way:", config.write_way)
end
]]
function exmtn.get_config()
    if not ctx.inited then
        return nil
    end
    return {
        enabled = ctx.enabled,
        cur_index = ctx.cur_index,
        block_size = ctx.block_size,
        blocks_per_file = ctx.blocks_per_file,
        file_limit = ctx.file_limit,
        write_way = ctx.write_way,
    }
end

--[[
清除所有运维日志文件
@api exmtn.clear()
@return boolean 成功返回true，失败返回false
@usage
local ok = exmtn.clear()
if ok then
    log.info("exmtn", "日志文件已清除")
end
]]
function exmtn.clear()
    -- 如果已初始化，先刷新缓存（确保数据不丢失）
    if ctx.inited and ctx.cache_used > 0 then
        if not flush_cache() then
            return false
        end
    end
    
    -- 删除所有日志文件
    remove_files()
    
    -- 重新创建空文件
    create_files()
    
    -- 重置索引为1
    ctx.cur_index = 1
    
    -- 更新配置文件
    if not save_config(1, ctx.blocks_per_file, ctx.write_way) then
        return false
    end
    
    log.info("exmtn", "运维日志文件已清除")
    return true
end

return exmtn

