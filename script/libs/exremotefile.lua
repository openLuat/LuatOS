--[[
@module exremotefile
@summary exremotefile 远程文件管理系统扩展库，提供AP热点创建、SD卡挂载、SERVER文件管理服务器等功能，支持文件浏览、上传、下载和删除操作。
@version 1.0
@date    2025.09.10
@author  拓毅恒
@usage
注：在使用exremotefile 扩展库时，需要将同一目录下的explorer.html文件烧录进模组中，否则无法启动server服务器来创建文件管理系统!!!

注：如果使用Air8000开发板测试，必须自定义配置is_8000_development_board = true
因为Air8000开发板上TF和以太网是同一个SPI，使用开发板时必须要将以太网拉高
如果使用其他硬件，需要根据硬件原理图来决定是否需要此操作

本文件的对外接口有2个：
1、exremotefile.open(ap_opts, sdcard_opts, server_opts)：启动远程文件管理系统，可配置AP参数、SD卡参数和服务器参数
-- 启动后连接AP热点，直接使用luatools日志中默认的地址"http://192.168.4.1:80/explorer.html"来访问文件管理服务器。
-- 如果使用自定义配置，则需要根据配置中的server_addr和server_port参数来访问文件管理服务器。

2、exremotefile.close()：关闭远程文件管理系统，停止AP热点、卸载SD卡和关闭HTTP服务器
]]

-- 导入必要的模块
dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")

local exremotefile = {}
local is_initialized = false
local user_server_opts = {}
local user_sdcard_opts = {}
local ETH3V3_EN = 140 -- Air8000开发板以太网供电
local SPI_ETH_CS = 12 -- Air8000开发板以太网片选

-- AP默认配置
local default_ap_opts = {
    ap_ssid = "LuatOS_FileHub",
    ap_pwd = "12345678"
}

-- SPI默认配置
local default_sdcard_opts = {
    spi_id = 1,
    spi_cs = 20,
    is_8000_development_board = false,
    is_sdio = false
}

-- server默认配置
local default_server_opts = {
    user_name = "admin",
    user_pwd = "123456",
    server_addr = "192.168.4.1",
    server_port = 80
}

-- 保存模块引用，用于后续关闭操作
local modules = {
    ap = nil,
    http_server = nil
}

-- 创建AP热点
local function create_ap(ap_opts, server_opts)
    log.info("WIFI", "创建AP热点: " .. ap_opts.ap_ssid)
    log.info("WIFI", "AP密码: " .. ap_opts.ap_pwd)
    
    -- 初始化WiFi
    wlan.init()
    sys.wait(100)
    
    -- 创建AP
    wlan.createAP(ap_opts.ap_ssid, ap_opts.ap_pwd)
    
    -- 配置IP
    netdrv.ipv4(socket.LWIP_AP, server_opts.server_addr, "255.255.255.0", "0.0.0.0")
    
    -- 等待网络准备就绪
    while netdrv.ready(socket.LWIP_AP) ~= true do
        sys.wait(100)
    end
    
    -- 设置DNS代理
    dnsproxy.setup(socket.LWIP_AP, socket.LWIP_GP)
    
    -- 创建DHCP服务器
    dhcpsrv.create({adapter=socket.LWIP_AP})
    
    -- 发布AP创建完成事件
    sys.publish("AP_CREATE_OK")
    
    log.info("WIFI", "AP热点创建成功")
end

-- 初始化SD卡
local function init_sdcard(sdcard_opts)
    log.info("SDCARD", "开始初始化SD卡")
    
    -- 双重验证，确认使用的是Air8000开发板
    if sdcard_opts.is_8000_development_board == true then
        if sdcard_opts.spi_cs == 20 then
            if sdcard_opts.spi_id == 1 then
                -- 注：Air8000开发板上TF和以太网是同一个SPI，使用开发板时必须要将以太网拉高
                -- 如果使用其他硬件，需要根据硬件原理图来决定是否需要此操作
                -- 配置以太网供电引脚，设置为输出模式，并启用上拉电阻
                gpio.setup(ETH3V3_EN, 1, gpio.PULLUP)
                -- 配置以太网片选引脚，设置为输出模式，并启用上拉电阻
                gpio.setup(SPI_ETH_CS, 1, gpio.PULLUP)
                log.info("sdcard_init", "使用的是开发板，开始将以太网拉高")
            end
        end
    end
    
    local mount_result = nil

    if not sdcard_opts.is_sdio then
        -- 配置SPI，设置spi_id，波特率为400000，用于SD卡初始化
        local result = spi.setup(sdcard_opts.spi_id, nil, 0, 0, 8, 400 * 1000)
        log.info("sdcard_init", "open spi", result)
        -- 配置SD卡片选引脚，设置为输出模式，并启用上拉电阻
        gpio.setup(sdcard_opts.spi_cs, 1, gpio.PULLUP)
        -- 挂载SD卡到文件系统，指定挂载点为"/sd"
        mount_result = fatfs.mount(fatfs.SPI, "/sd", sdcard_opts.spi_id, sdcard_opts.spi_cs, 24 * 1000 * 1000)
    else
        mount_result = fatfs.mount(fatfs.SDIO, "/sd", sdcard_opts.spi_id, sdcard_opts.spi_cs, 24 * 1000 * 1000)
    end
    log.info("SDCARD", "挂载SD卡结果:", mount_result)
    
    -- 获取SD卡的可用空间信息
    local data, err = fatfs.getfree("/sd")
    if data then
        log.info("SDCARD", "SD卡可用空间信息:", json.encode(data))
    else
        log.info("SDCARD", "获取SD卡空间失败:", err)
    end
    
    return mount_result
end

-- 会话管理
local authenticated_sessions = {}

-- 获取文件信息
local function get_file_info(path)
    log.info("FILE_INFO", "获取文件信息: " .. path)

    -- 获取文件名
    local filename = path:match("([^/]+)$") or ""

    -- 获取大小
    local direct_size = io.fileSize(path)
    if direct_size and direct_size > 0 then
        log.info("FILE_INFO", "获取文件大小成功: " .. direct_size .. " 字节")
        return {
            name = filename,
            size = direct_size,
            isDirectory = false,
            path = path
        }
    end

    -- 检查文件是否存在，避免对文件进行错误的目录判断
    if not io.exists(path) then
        log.info("FILE_INFO", "文件不存在: " .. path)
        return {
            name = filename,
            size = 0,
            isDirectory = false,
            path = path
        }
    end

    -- 尝试判断是否为目录
    local ret, data = io.lsdir(path, 1, 0)
    if ret and data and type(data) == "table" and #data > 0 then
        log.info("FILE_INFO", "路径是一个目录: " .. path)
        return {
            name = filename,
            size = 0,
            isDirectory = true,
            path = path
        }
    end

    -- 检查文件是否存在
    if not io.exists(path) then
        log.info("FILE_INFO", "文件不存在: " .. path)
        return {
            name = filename,
            size = 0,
            isDirectory = false,
            path = path
        }
    end

    -- 尝试打开文件获取大小
    local file = io.open(path, "rb")
    if file then
        -- 尝试获取文件大小
        local file_size = io.fileSize(path)

        -- 如果返回0或nil，尝试通过读取文件内容获取大小
        if not file_size or file_size == 0 then
            log.info("FILE_INFO", "获取文件大小，尝试读取文件内容")
            local content = file:read("*a")
            file_size = #content
            log.info("FILE_INFO", "使用文件内容长度获取大小: " .. file_size .. " 字节")
        else
            log.info("FILE_INFO", "获取文件大小成功: " .. file_size .. " 字节")
        end

        file:close()
        log.info("FILE_INFO", "成功获取文件信息: " .. filename .. ", 大小: " .. file_size .. " 字节")
        return {
            name = filename,
            size = file_size,
            isDirectory = false,
            path = path
        }
    end
end

-- 定义系统文件的规则（系统文件不显示）
local function is_system_file(filename)
    -- 系统文件扩展名列表
    local system_extensions = {".luac", ".html", ".md"}
    -- 特殊系统文件名
    local special_system_files = {".airm2m_all_crc#.bin"}

    -- 检查文件名是否匹配特殊系统文件名
    for _, sys_file in ipairs(special_system_files) do
        if filename == sys_file then
            return true
        end
    end

    -- 检查文件扩展名是否为系统文件扩展名
    for _, ext in ipairs(system_extensions) do
        if filename:sub(-#ext) == ext then
            return true
        end
    end

    return false
end

-- 扫描目录
local function scan_with_lsdir(path, files)
    log.info("LIST_DIR", "开始扫描目录")
    -- 确保路径格式正确，处理多层目录和编码问题
    local scan_path = path
    log.info("LIST_DIR", "原始路径: " .. scan_path)

    -- 规范化路径，处理URL编码残留问题
    scan_path = scan_path:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
    log.info("LIST_DIR", "解码后路径: " .. scan_path)

    -- 移除多余的斜杠
    scan_path = scan_path:gsub("//+", "/")
    log.info("LIST_DIR", "去重斜杠后路径: " .. scan_path)

    -- 规范化路径，移除可能的尾部斜杠
    scan_path = scan_path:gsub("/*$", "")
    log.info("LIST_DIR", "移除尾部斜杠后路径: " .. scan_path)

    -- 确保路径以/开头
    if not scan_path:match("^/") then
        scan_path = "/" .. scan_path
    end
    log.info("LIST_DIR", "确保以/开头后路径: " .. scan_path)

    -- 确保路径以/结尾
    scan_path = scan_path .. (scan_path == "" and "" or "/")

    log.info("LIST_DIR", "开始扫描路径: " .. scan_path)

    -- 扫描目录，最多列出50个文件，从第0个开始
    local ret, data = io.lsdir(scan_path, 50, 0)

    if ret then
        log.info("LIST_DIR", "成功获取目录内容，文件数量: " .. #data)
        log.info("LIST_DIR", "目录内容: " .. json.encode(data))

        -- 遍历目录内容
        for i = 1, #data do
            local entry = data[i]
            local is_dir = (entry.type ~= 0)
            local entry_type = is_dir and "目录" or "文件"
            log.info("LIST_DIR", "找到条目: " .. entry.name .. ", 类型: " .. entry_type)

            local full_path = scan_path .. entry.name

            -- 处理目录和文件的不同逻辑
            if is_dir then
                -- 对于目录，直接构造信息
                local dir_info = {
                    name = entry.name,
                    size = 0,
                    isDirectory = true,
                    path = full_path
                }
                -- 过滤sd卡系统文件夹目录
                if entry.name ~= "System Volume Information" then
                    table.insert(files, dir_info)
                    log.info("LIST_DIR", "添加目录: " .. entry.name .. ", 路径: " .. full_path)
                end
            else
                -- 检查是否为用户文件
                local is_user_file = not is_system_file(entry.name)

                -- 只有用户文件才会被添加到列表中
                if is_user_file then
                    -- 对于文件，调用get_file_info获取详细信息
                    local file_info = get_file_info(full_path)
                    if file_info and file_info.size ~= nil then
                        file_info.isDirectory = false
                        table.insert(files, file_info)
                        log.info("LIST_DIR", "添加文件: " .. entry.name .. ", 大小: " .. file_info.size ..
                            " 字节, 路径: " .. file_info.path)
                    else
                        -- 如果get_file_info失败，使用默认值
                        local default_info = {
                            name = entry.name,
                            size = entry.size or 0,
                            isDirectory = false,
                            path = full_path
                        }
                        table.insert(files, default_info)
                        log.info("LIST_DIR", "添加文件(默认信息): " .. entry.name .. ", 大小: " ..
                            (entry.size or 0) .. " 字节")
                    end
                end
            end
        end
        return true
    else
        log.info("LIST_DIR", "扫描失败: " .. (data or "未知错误"))
    end
    return false
end

-- 列出目录
local function list_directory(path)
    -- 初始化文件列表
    local files = {}

    log.info("LIST_DIR", "开始处理目录请求: " .. path)

    -- 扫描方法表
    local scan_success = scan_with_lsdir(path, files)

    -- 记录扫描结果
    if scan_success then
        log.info("LIST_DIR", "扫描方法成功")
    else
        log.info("LIST_DIR", "扫描方法失败")
    end

    log.info("LIST_DIR", "目录扫描完成，总共找到文件数量: " .. #files)
    return files
end

-- 会话验证
local function validate_session(headers)
    -- 获取Cookie中的session_id
    local cookies = headers['Cookie'] or ''
    local session_id = nil
    if cookies then
        session_id = cookies:match('session_id=([^;]+)')
    end

    -- 检查会话ID是否已认证
    if session_id and authenticated_sessions[session_id] then
        return true
    else
        return false
    end
end

-- 生成会话ID
local function generate_session_id()
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    local id = ""
    for i = 1, 32 do
        local rand = math.random(1, #chars)
        id = id .. chars:sub(rand, rand)
    end
    return id
end

-- 检查字符串是否以指定前缀开头
local function string_starts_with(str, prefix)
    return string.sub(str, 1, string.len(prefix)) == prefix
end

-- server请求处理
local function handle_http_request(fd, method, uri, headers, body)
    log.info("HTTP", method, uri)

    -- 登录
    if uri == "/login" and method == "POST" then
        local data = json.decode(body or "{}")
        log.info("LOGIN", "收到登录请求，用户名: " .. (data and data.username or "空"))
        if data and data.username == user_server_opts.user_name and data.password == user_server_opts.user_pwd then
            local session_id = generate_session_id()
            authenticated_sessions[session_id] = os.time()

            -- 计算已认证会话数量
            local session_count = 0
            for _ in pairs(authenticated_sessions) do
                session_count = session_count + 1
            end

            log.info("LOGIN", "登录成功！用户名: " .. data.username)
            log.info("LOGIN", "生成SessionID: " .. session_id)
            log.info("LOGIN", "当前已认证会话数量: " .. session_count)

            -- 设置Cookie
            return 200, {
                ["Content-Type"] = "application/json",
                ["Set-Cookie"] = "session_id=" .. session_id .. "; Path=/; Max-Age=3600"
            }, json.encode({
                success = true,
                session_id = session_id
            })
        else
            return 200, {
                ["Content-Type"] = "application/json"
            }, json.encode({
                success = false,
                message = "用户名或密码错误"
            })
        end
    end

    -- 登出
    if uri == "/logout" and method == "POST" then
        local cookie = headers["Cookie"] or ""
        for session_id in cookie:gmatch("session_id=([^;]+)") do
            authenticated_sessions[session_id] = nil
        end
        return 200, {
            ["Set-Cookie"] = "session_id=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT"
        }, ""
    end

    -- 检查认证
    if uri == "/check-auth" then
        return 200, {
            ["Content-Type"] = "application/json"
        }, json.encode({
            authenticated = validate_session(headers)
        })
    end

    -- 扫描文件接口
    if string_starts_with(uri, "/scan-files") then
        log.info("SCAN", "收到文件扫描请求")

        -- 检查传统认证方式
        local is_authenticated = validate_session(headers)

        -- 如果传统认证失败，尝试从URL参数中获取用户名和密码
        if not is_authenticated then
            local url_username = uri:match("username=([^&]+)")
            local url_password = uri:match("password=([^&]+)")
            if url_username and url_password then
                url_username = url_username:gsub("%%(%x%x)", function(hex)
                    return string.char(tonumber(hex, 16))
                end)
                url_password = url_password:gsub("%%(%x%x)", function(hex)
                    return string.char(tonumber(hex, 16))
                end)
                if url_username == user_server_opts.user_name and url_password == user_server_opts.user_pwd then
                    log.info("AUTH", "扫描请求通过URL参数认证成功")
                    is_authenticated = true
                else
                    log.info("AUTH", "扫描请求URL参数认证失败: 用户名或密码错误")
                end
            else
                log.info("AUTH", "扫描请求URL中没有找到用户名和密码参数")
            end
        end

        -- 如果认证仍然失败，返回未授权访问
        if not is_authenticated then
            log.info("HTTP", "未授权访问文件扫描功能")
            return 401, {
                ["Content-Type"] = "application/json"
            }, json.encode({
                success = false,
                message = "未授权访问"
            })
        end

        -- 执行文件扫描
        log.info("SCAN", "开始扫描内部文件系统和TF卡...")

        -- 定义要扫描的挂载点，包括SD卡挂载点
        local mount_points = {"/", "/luadb/", "/sd/"}
        local found_files = {}

        -- 对每个挂载点执行扫描
        for _, mount_point in ipairs(mount_points) do
            log.info("SCAN", "开始扫描挂载点: " .. mount_point)

            -- 如果路径不以/结尾，添加/确保路径格式正确
            local scan_path = mount_point
            if not scan_path:match("/$") then
                scan_path = scan_path .. (scan_path == "" and "" or "/")
            end

            -- 扫描目录
            log.info("SCAN", "开始扫描路径: " .. scan_path)
            -- 尝试列出目录内容，最多列出50个文件
            local ret, data = io.lsdir(scan_path, 50, 0)

            if ret then
                log.info("SCAN", "成功获取目录内容，文件数量: " .. #data)
                log.info("SCAN", "目录内容: " .. json.encode(data))

                -- 遍历目录内容
                for i = 1, #data do
                    local entry = data[i]
                    local full_path = scan_path .. entry.name

                    -- 如果是文件（type == 0），添加到文件列表
                    if entry.type == 0 then
                        local info = get_file_info(full_path)
                        if info then
                            table.insert(found_files, {
                                name = entry.name,
                                size = info.size,
                                path = full_path
                            })
                            log.info("SCAN", "找到文件: " .. entry.name .. ", 大小: " .. info.size ..
                                " 字节, 路径: " .. full_path)
                        else
                            -- 如果get_file_info失败，使用io.lsdir返回的大小
                            table.insert(found_files, {
                                name = entry.name,
                                size = entry.size or 0,
                                path = full_path
                            })
                            log.info("SCAN", "找到文件: " .. entry.name .. ", 大小: " .. (entry.size or 0) ..
                                " 字节, 路径: " .. full_path)
                        end
                    else
                        -- 如果是目录，记录但不添加到文件列表
                        log.info("SCAN", "找到目录: " .. entry.name .. ", 路径: " .. full_path)
                    end
                end
            else
                log.info("SCAN", "扫描失败: " .. (data or "未知错误"))
            end

            local list_files = list_directory(mount_point)
            if list_files then
                for _, file in ipairs(list_files) do
                    -- 只记录非目录文件
                    if not file.isDirectory then
                        -- 确保文件路径正确
                        local file_path = file.path or (mount_point .. (mount_point == "/" and "" or "/") .. file.name)

                        -- 检查文件是否已添加
                        local is_exists = false
                        for _, f in ipairs(found_files) do
                            if f.name == file.name and f.path == file_path then
                                is_exists = true
                                break
                            end
                        end
                        if not is_exists then
                            table.insert(found_files, {
                                name = file.name,
                                size = file.size,
                                path = file_path
                            })
                            log.info("SCAN",
                                "从list_directory添加文件: " .. file.name .. ", 大小: " .. file.size ..
                                    " 字节, 路径: " .. file_path)
                        end
                    end
                end
            end

            log.info("SCAN", "挂载点扫描完成: " .. mount_point .. ", 找到文件: " .. #found_files .. " 个")
        end

        -- 扫描完成后，打印详细的文件列表
        log.info("SCAN", "文件扫描完成，总共找到文件数量: " .. #found_files)
        for i, file in ipairs(found_files) do
            log.info("SCAN", "文件[" .. i .. "]: " .. file.name .. ", 大小: " .. file.size .. " 字节, 路径: " ..
                file.path)
        end

        -- 返回扫描结果
        return 200, {
            ["Content-Type"] = "application/json"
        }, json.encode({
            success = true,
            foundFiles = #found_files,
            files = found_files,
            message = "文件扫描完成"
        })
    end

    -- 文件列表
    if string_starts_with(uri, "/list") then

        -- 检查传统认证方式
        local is_authenticated = validate_session(headers)

        -- 如果传统认证失败，尝试从URL参数中获取用户名和密码
        if not is_authenticated then
            local url_username = uri:match("username=([^&]+)")
            local url_password = uri:match("password=([^&]+)")
            if url_username and url_password then
                url_username = url_username:gsub("%%(%x%x)", function(hex)
                    return string.char(tonumber(hex, 16))
                end)
                url_password = url_password:gsub("%%(%x%x)", function(hex)
                    return string.char(tonumber(hex, 16))
                end)
                if url_username == user_server_opts.user_name and url_password == user_server_opts.user_pwd then
                    log.info("AUTH", "通过URL参数认证成功")
                    is_authenticated = true
                else
                    log.info("AUTH", "URL参数认证失败: 用户名或密码错误")
                end
            else
                log.info("AUTH", "URL中没有找到用户名和密码参数")
            end
        end

        -- 如果认证仍然失败，返回未授权访问
        if not is_authenticated then
            log.info("HTTP", "未授权访问文件列表")
            return 401, {
                ["Content-Type"] = "text/plain"
            }, "未授权访问"
        end
        local path = uri:match("path=([^&]+)") or "/luadb"
        log.info("HTTP", "请求的文件列表路径: " .. path)
        path = path:gsub("%%(%x%x)", function(hex)
            return string.char(tonumber(hex, 16))
        end)
        log.info("HTTP", "解码后的文件列表路径: " .. path)

        -- 调用list_directory函数扫描目录
        log.info("HTTP", "开始扫描目录")
        local files = list_directory(path)

        -- 记录传给页面的文件数据
        log.info("HTTP", "准备返回文件列表，数量: " .. #files)
        for i, file in ipairs(files) do
            log.info("HTTP", "文件[" .. i .. "]: " .. file.name .. ", 大小: " .. file.size)
        end

        return 200, {
            ["Content-Type"] = "application/json"
        }, json.encode({
            success = true,
            files = files
        })
    end

    -- 文件下载
    if string_starts_with(uri, "/download") then
        log.info("DOWNLOAD", "收到下载请求: " .. uri)

        -- 检查传统认证方式
        local is_authenticated = validate_session(headers)

        -- 如果传统认证失败，尝试从URL参数中获取用户名和密码
        if not is_authenticated then
            local url_username = uri:match("username=([^&]+)")
            local url_password = uri:match("password=([^&]+)")
            if url_username and url_password then
                url_username = url_username:gsub("%%(%x%x)", function(hex)
                    return string.char(tonumber(hex, 16))
                end)
                url_password = url_password:gsub("%%(%x%x)", function(hex)
                    return string.char(tonumber(hex, 16))
                end)
                if url_username == user_server_opts.user_name and url_password == user_server_opts.user_pwd then
                    log.info("AUTH", "下载请求通过URL参数认证成功")
                    is_authenticated = true
                else
                    log.info("AUTH", "下载请求URL参数认证失败: 用户名或密码错误")
                end
            else
                log.info("AUTH", "下载请求URL中没有找到用户名和密码参数")
            end
        end

        -- 如果认证仍然失败，返回未授权访问
        if not is_authenticated then
            log.info("HTTP", "未授权访问文件下载")
            return 401, {
                ["Content-Type"] = "text/plain"
            }, "未授权访问"
        end

        -- 获取请求的文件路径
        local path = uri:match("path=([^&]+)") or ""
        path = path:gsub("%%(%x%x)", function(hex)
            return string.char(tonumber(hex, 16))
        end)

        -- 检查文件是否存在
        if not io.exists(path) then
            log.info("DOWNLOAD", "文件不存在: " .. path)
            return 404, {
                ["Content-Type"] = "text/plain"
            }, "文件不存在"
        end

        -- 尝试打开文件以确认可访问性并获取文件信息
        local file = io.open(path, "rb")
        if not file then
            log.info("DOWNLOAD", "文件无法打开: " .. path)
            return 404, {
                ["Content-Type"] = "text/plain"
            }, "文件无法打开"
        end

        -- 获取文件名
        local filename = path:match("([^/]+)$")

        -- 获取文件大小
        local file_size = io.fileSize(path)

        -- 关闭文件
        file:close()

        log.info("DOWNLOAD", "确认文件信息: " .. filename .. ", 大小: " .. file_size .. " 字节")

        -- 使用httpsrv下载，直接重定向URL
        -- 如需要下载文件系统中123.mp3，直接重定向到URL:http://192.168.4.1/123.mp3
        -- 如果路径以/sd/开头，则保留完整的sd路径
        local redirect_url = "/" .. filename
        if string_starts_with(path, "/sd/") then
            -- 保留完整的sd路径，以便直接访问sd卡文件及其子目录
            redirect_url = path
        end

        log.info("DOWNLOAD", "开始下载文件：" .. redirect_url)

        -- 返回HTTP 302重定向响应
        return 302, {
            ["Location"] = redirect_url,
            ["Content-Type"] = "text/html"
        }, [[
            <html>
            <head><title>重定向下载</title></head>
            <body>
                <p>正在重定向到文件下载...</p>
            </body>
            </html>
        ]]
    end

    -- 文件删除
    if string_starts_with(uri, "/delete") and method == "POST" then
        -- 检查传统认证方式
        local is_authenticated = validate_session(headers)

        -- 如果传统认证失败，尝试从URL参数中获取用户名和密码
        if not is_authenticated then
            local url_username = uri:match("username=([^&]+)")
            local url_password = uri:match("password=([^&]+)")
            if url_username and url_password then
                url_username = url_username:gsub("%%(%x%x)", function(hex)
                    return string.char(tonumber(hex, 16))
                end)
                url_password = url_password:gsub("%%(%x%x)", function(hex)
                    return string.char(tonumber(hex, 16))
                end)
                if url_username == user_server_opts.user_name and url_password == user_server_opts.user_pwd then
                    log.info("AUTH", "通过URL参数认证成功")
                    is_authenticated = true
                else
                    log.info("AUTH", "URL参数认证失败: 用户名或密码错误")
                end
            else
                log.info("AUTH", "URL中没有找到用户名和密码参数")
            end
        end

        -- 如果认证仍然失败，返回未授权访问
        if not is_authenticated then
            log.info("HTTP", "未授权访问文件删除")
            return 401, {
                ["Content-Type"] = "application/json"
            }, json.encode({
                success = false,
                message = "未授权访问"
            })
        end
        local path = uri:match("path=([^&]+)") or ""
        path = path:gsub("%%(%x%x)", function(hex)
            return string.char(tonumber(hex, 16))
        end)
        if not io.exists(path) then
            return 200, {
                ["Content-Type"] = "application/json"
            }, json.encode({
                success = false,
                message = "文件不存在"
            })
        end
        -- 尝试删除文件
        local ok, err = os.remove(path)
        if ok then
            return 200, {
                ["Content-Type"] = "application/json"
            }, json.encode({
                success = true,
                message = "文件删除成功"
            })
        else
            return 200, {
                ["Content-Type"] = "application/json"
            }, json.encode({
                success = false,
                message = "删除失败: " .. (err or "未知错误")
            })
        end
    end

    -- 首页
    if uri == "/" then
        local html_file = io.open("/index.html", "r")
        if html_file then
            local content = html_file:read("*a")
            html_file:close()
            return 200, {
                ["Content-Type"] = "text/html"
            }, content
        end
    end

    -- 直接文件路径访问
    -- 检查是否是API路径，如果不是，则尝试作为文件路径访问
    local is_api_path = string_starts_with(uri, "/login") or string_starts_with(uri, "/logout") or
                            string_starts_with(uri, "/check-auth") or string_starts_with(uri, "/scan-files") or
                            string_starts_with(uri, "/list") or string_starts_with(uri, "/download") or
                            string_starts_with(uri, "/delete") or uri == "/"

    if not is_api_path then
        log.info("DIRECT_ACCESS", "尝试直接访问文件: " .. uri)

        -- 确定实际文件路径
        local file_path = uri

        -- 如果路径不是以/sd/开头，则默认在/luadb/目录下查找
        if not string_starts_with(file_path, "/sd/") then
            -- 移除开头的斜杠
            if file_path:sub(1, 1) == "/" then
                file_path = file_path:sub(2)
            end
            -- 添加/luadb/前缀
            file_path = "/luadb/" .. file_path
        end

        log.info("DIRECT_ACCESS", "解析后的实际文件路径: " .. file_path)

        -- 检查文件是否存在
        if not io.exists(file_path) then
            log.info("DIRECT_ACCESS", "文件不存在: " .. file_path)
            return 404, {
                ["Content-Type"] = "text/plain"
            }, "文件不存在"
        end

        -- 尝试打开文件
        local file = io.open(file_path, "rb")
        if not file then
            log.info("DIRECT_ACCESS", "文件无法打开: " .. file_path)
            return 404, {
                ["Content-Type"] = "text/plain"
            }, "文件无法打开"
        end

        -- 获取文件名
        local filename = file_path:match("([^/]+)$")

        -- 读取文件内容
        local content = file:read("*a")

        -- 关闭文件
        file:close()

        log.info("DIRECT_ACCESS", "文件读取完成: " .. filename .. ", 大小: " .. #content .. " 字节")

        -- 设置HTTP头部
        local response_headers = {
            ["Content-Type"] = "application/octet-stream",
            ["Content-Disposition"] = "attachment; filename=\"" .. filename .. "\""
        }

        return 200, response_headers, content
    end

    return 404, {
        ["Content-Type"] = "text/plain"
    }, "页面未找到"
end

-- server服务器启动任务
local function http_server_start_task(server_opts, ap_opts)
    -- 等待AP初始化完成
    sys.waitUntil("AP_CREATE_OK")
    
    -- 确认SD卡是否挂载成功
    local retry_count = 0
    local max_retries = 3
    
    while retry_count < max_retries do
        local free_space, err = fatfs.getfree("/sd")
        if free_space then
            log.info("HTTP", "SD卡挂载成功，可用空间: " .. json.encode(free_space))
            break
        else
            retry_count = retry_count + 1
            log.warn("HTTP", "SD卡挂载检查失败 (" .. retry_count .. "): " .. (err or "未知错误"))
            if retry_count < max_retries then
                sys.wait(1000)
            else
                log.error("HTTP", "SD卡挂载失败，将继续启动但可能无法访问SD卡内容")
            end
        end
    end
    
    -- 启动HTTP服务器
    httpsrv.start(server_opts.server_port, handle_http_request, socket.LWIP_AP)
    
    log.info("HTTP", "文件服务器已启动")
    log.info("HTTP", "请连接WiFi: " .. ap_opts.ap_ssid .. "，密码: " .. ap_opts.ap_pwd)
    log.info("HTTP", "然后访问: http://" .. server_opts.server_addr.. ":" .. server_opts.server_port .. "/explorer.html")
end


--[[
启动文件管理系统，包括创建AP热点、挂载TF/SD卡和启动SERVER文件管理服务器功能
@api exremotefile.open(ap_opts, sdcard_opts, server_opts)
@table ap_opts 可选，AP配置选项表
@table sdcard_opts 可选，TF/SD卡挂载配置选项表
@table server_opts 可选，服务器配置选项表
@return 无 无返回值
@usage
-- 一、使用默认参数创建server服务器
-- 启动后连接默认AP热点，直接访问日志中默认的地址"http://192.168.4.1:80/explorer.html"来访问文件管理服务器。
exremotefile.open()


-- 二、自定义参数启动
-- 启动后连接自定义AP热点，访问日志中自定义的地址"http://"server_addr":"server_port"/explorer.html"来访问文件管理服务器。
exremotefile.open({
    ap_ssid = "LuatOS_FileHub", -- WiFi名称
    ap_pwd = "12345678"         -- WiFi密码
}, 
{
    spi_id = 1,                 -- SPI编号
    spi_cs = 12，               -- CS片选引脚
    is_8000_development_board = false, -- 是否使用8000开发板
    is_sdio = false             -- 是否使用sdio挂载
}, 
{
    server_addr = "192.168.4.1",    -- 服务器地址
    server_port = 80,           -- 服务器端口
    user_name = "admin",        -- 用户名
    user_pwd = "123456"          -- 密码
})
]]
function exremotefile.open(ap_opts, sdcard_opts, server_opts)
    if is_initialized then
        log.warn("exremotefile", "文件管理系统已经在运行中")
        return
    end
    
    log.info("exremotefile", "启动文件管理系统")
    
    -- 合并配置
    if ap_opts then
        log.info("check_config", "开始检查AP参数")
        if not ap_opts.ap_ssid then 
            ap_opts.ap_ssid = default_ap_opts.ap_ssid
            log.info("check_config", "AP没有设置ssid，用默认配置",ap_opts.ap_ssid)
        end
        if not ap_opts.ap_pwd then
            ap_opts.ap_pwd = default_ap_opts.ap_pwd
            log.info("check_config", "AP没有设置pwd，用默认配置",ap_opts.ap_pwd)
        end
        log.info("check_config", "AP参数配置完毕")
    else
        ap_opts = default_ap_opts
        log.info("check_config", "没有AP参数，用默认配置")
    end

    if sdcard_opts then
        log.info("check_config", "开始检查TF/SD挂载参数")
        if not sdcard_opts.spi_id  then
            sdcard_opts.spi_id = default_sdcard_opts.spi_id
            log.info("check_config", "TF/SD挂载没有设置spi号，用默认配置",sdcard_opts.spi_id)
        end
        if not sdcard_opts.spi_cs  then
            sdcard_opts.spi_cs = default_sdcard_opts.spi_cs
            log.info("check_config", "TF/SD挂载没有设置cs片选脚，用默认配置",sdcard_opts.spi_cs)
        end
        log.info("check_config", "TF/SD挂载参数配置完毕")
    else
        sdcard_opts = default_sdcard_opts
        log.info("check_config", "没有TF/SD挂载参数，用默认配置")
    end
    
    if server_opts then
        log.info("check_config", "开始检查SERVER参数")
        if not server_opts.server_addr then
            server_opts.server_addr = default_server_opts.server_addr
            log.info("check_config", "SERVER没有设置addr，用默认配置",server_opts.server_addr)
        end
        if not server_opts.server_port then
            server_opts.server_port = default_server_opts.server_port
            log.info("check_config", "SERVER没有设置port，用默认配置",server_opts.server_port)
        end
        if not server_opts.user_name then
            server_opts.user_name = default_server_opts.user_name
            log.info("check_config", "SERVER没有设置user_name，用默认配置",server_opts.user_name)
        end
        if not server_opts.user_pwd then
            server_opts.user_pwd = default_server_opts.user_pwd
            log.info("check_config", "SERVER没有设置user_pwd，用默认配置",server_opts.user_pwd)
        end
        log.info("check_config", "SERVER参数配置完毕")
    else
        server_opts = default_server_opts
        log.info("check_config", "没有SERVER参数，用默认配置")
    end
    
    user_sdcard_opts = sdcard_opts
    user_server_opts = server_opts
    -- 创建AP热点
    create_ap(ap_opts, server_opts)
    
    -- 初始化SD卡
    local mount_result = init_sdcard(sdcard_opts)
    if not mount_result then
        log.error("exremotefile", "SD卡初始化失败")
    end
    
    -- 启动HTTP服务器
    sys.taskInit(http_server_start_task, server_opts, ap_opts)
    
    is_initialized = true
    log.info("exremotefile", "文件管理系统启动完成")
end

--[[
关闭文件管理系统，包括停止HTTP文件服务器、取消TF/SD卡挂载和停止AP热点
@api exremotefile.close()
@return 无 无返回值
@usage
-- 关闭文件管理系统
-- exremotefile.close()
]]
function exremotefile.close()
    if not is_initialized then
        log.warn("exremotefile", "文件管理系统尚未启动")
        return
    end
    
    log.info("exremotefile", "关闭文件管理系统")
    
    -- 停止HTTP服务器
    httpsrv.stop(user_server_opts.server_port, nil, socket.LWIP_AP)
    -- 取消挂载SD卡
    fatfs.unmount("/sd")
    -- 停止AP热点
    wlan.stopAP()

    -- 关闭所用SPI
    spi.close(user_sdcard_opts.spi_id)
    
    -- 关闭所用IO
    if user_sdcard_opts.is_8000_development_board == true then
        gpio.close(ETH3V3_EN)
        gpio.close(SPI_ETH_CS)
    end
    gpio.close(user_sdcard_opts.spi_cs)
    
    is_initialized = false
    log.info("exremotefile", "文件管理系统已关闭")
end

return exremotefile