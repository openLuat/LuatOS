--[[
@module  file_manager_app
@summary 文件管理业务逻辑层，封装 io API 提供目录遍历、文件操作
@version 1.0
@date    2026.06.02
@author  江访
]]

-- 挂载点标签映射
local MOUNT_LABELS = {
    ["/"]              = "内置文件系统",
    ["/sd/"]           = "外挂TF卡",
    ["/little_flash/"] = "外挂Flash",
}

-- 所有已知挂载点
local MOUNT_POINTS = { "/", "/sd/", "/little_flash/" }

--[[
获取所有存在 /app_store 目录的挂载设备列表
如果挂载点存在但 /app_store 不存在则不显示
@return table 设备列表 { {mount_point, label}, ... }
]]
local function get_mount_points()
    local result = {}
    for _, mp in ipairs(MOUNT_POINTS) do
        -- 先检查挂载点是否存在
        if not io.dexist(mp) then
            log.info("file_manager", "mount point not found", mp)
            goto continue
        end
        -- 检查 /app_store 目录，不存在则创建
        local app_store_path = mp .. "app_store"
        if not io.dexist(app_store_path) then
            log.info("file_manager", "creating app_store", app_store_path)
            io.mkdir(app_store_path)
        end
        if io.dexist(app_store_path) then
            table.insert(result, {
                mount_point = mp,
                label = MOUNT_LABELS[mp] or mp,
            })
            log.info("file_manager", "found device", mp, MOUNT_LABELS[mp] or mp)
        else
            log.info("file_manager", "app_store create failed on", mp)
        end
        ::continue::
    end
    return result
end

--[[
列出指定目录下的文件和文件夹
@string dir_path 完整目录路径
@return boolean 是否成功
@return table 子项列表 { {name, size, type}, ... }，type=0文件 type=1目录
]]
local function list_directory(dir_path)
    local max_count = 200
    local offset = 0
    local ret, data = io.lsdir(dir_path, max_count, offset)
    if ret then
        return true, data or {}
    else
        log.warn("file_manager", "lsdir fail", dir_path, ret, data)
        return false, {}
    end
end

--[[
创建文件夹
@string dir_path 完整的文件夹路径
@return boolean 是否成功
]]
local function create_directory(dir_path)
    if io.dexist(dir_path) then
        log.warn("file_manager", "mkdir fail, already exists", dir_path)
        return false
    end
    local ret = io.mkdir(dir_path)
    if ret then
        log.info("file_manager", "mkdir ok", dir_path)
        return true
    else
        log.warn("file_manager", "mkdir fail", dir_path)
        return false
    end
end

--[[
创建空文件
@string file_path 完整文件路径
@return boolean 是否成功
]]
local function create_file(file_path)
    if io.exists(file_path) then
        log.warn("file_manager", "create file fail, already exists", file_path)
        return false
    end
    local fd = io.open(file_path, "w")
    if fd then
        fd:close()
        log.info("file_manager", "create file ok", file_path)
        return true
    else
        log.warn("file_manager", "create file fail", file_path)
        return false
    end
end

--[[
复制文件或空文件夹（读取并写入新路径）
@string src_path 源路径
@string dst_path 目标路径
@boolean is_directory 是否为目录
@return boolean 是否成功
]]
local function copy_path(src_path, dst_path, is_directory)
    if is_directory then
        -- 创建目标目录
        if not io.dexist(dst_path) then
            local ok = io.mkdir(dst_path)
            if not ok then
                log.warn("file_manager", "copy mkdir fail", dst_path)
                return false
            end
        end
        -- 遍历源目录，递归复制
        local ret, items = list_directory(src_path)
        if ret then
            for _, item in ipairs(items) do
                local sub_src = src_path .. "/" .. item.name
                local sub_dst = dst_path .. "/" .. item.name
                local sub_ok = copy_path(sub_src, sub_dst, item.type == 1)
                if not sub_ok then return false end
            end
        end
        return true
    else
        -- 复制文件
        local fdr = io.open(src_path, "rb")
        if not fdr then
            log.warn("file_manager", "copy open src fail", src_path)
            return false
        end
        local data = fdr:read("*a")
        fdr:close()
        local fdw = io.open(dst_path, "wb")
        if not fdw then
            log.warn("file_manager", "copy open dst fail", dst_path)
            return false
        end
        fdw:write(data or "")
        fdw:close()
        log.info("file_manager", "copy ok", src_path, "->", dst_path)
        return true
    end
end

-- 剪贴板
local clipboard = {
    items = {},      -- { {path, is_dir, name}, ... }
    mode = nil,      -- "copy" | "cut"
}

local function clipboard_set(items, mode)
    clipboard.items = items
    clipboard.mode = mode
    log.info("file_manager", "clipboard set", mode, #items)
end

local function clipboard_get()
    return clipboard.items, clipboard.mode
end

local function clipboard_clear()
    clipboard.items = {}
    clipboard.mode = nil
end

--[[
删除文件或文件夹（递归删除非空目录）
@string path 完整路径
@boolean is_directory 是否为目录
@return boolean 是否成功
]]
local function delete_path(path, is_directory)
    if is_directory then
        -- 递归清空目录内容后再删除
        local ret, items = list_directory(path)
        if ret then
            for _, item in ipairs(items) do
                local sub_path = path .. "/" .. item.name
                local sub_ok = delete_path(sub_path, item.type == 1)
                if not sub_ok then
                    log.warn("file_manager", "delete sub fail", sub_path)
                    return false
                end
            end
        end
        local rmdir_ok = io.rmdir(path)
        if rmdir_ok then
            log.info("file_manager", "rmdir ok", path)
            return true
        else
            log.warn("file_manager", "rmdir fail", path)
            return false
        end
    else
        local ret, err = os.remove(path)
        if ret then
            log.info("file_manager", "remove ok", path)
            return true
        else
            log.warn("file_manager", "remove fail", path, err)
            return false
        end
    end
end

-- 导出接口
return {
    MOUNT_LABELS = MOUNT_LABELS,
    get_mount_points = get_mount_points,
    list_directory = list_directory,
    create_directory = create_directory,
    create_file = create_file,
    delete_path = delete_path,
    copy_path = copy_path,
    clipboard_set = clipboard_set,
    clipboard_get = clipboard_get,
    clipboard_clear = clipboard_clear,
}
