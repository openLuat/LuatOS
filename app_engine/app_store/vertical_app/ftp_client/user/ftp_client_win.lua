--[[
@module  ftp_client_win
@summary FTP客户端页面模块
@version 1.0
@date    2026.04.01
@author  系统生成
]]

local win_id = nil
local main_container, content
local server_input, port_input, user_input, pass_input
local connect_btn
local file_list
local current_path = "/"
local ftp_client = nil
local file_items = {} -- 存储文件列表项的引用
local file_section
local exftp = nil -- 存储exftp库引用
local icon_info_label = nil -- 存储图标说明标签

local function create_ui()
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=480, h=800, color=0xF8F9FA })

    local header = airui.container({ parent = main_container, x=0, y=0, w=480, h=60, color=0x3F51B5 })
    local back_btn = airui.container({ parent = header, x = 390, y = 15, w = 80, h = 40, color = 0x2195F6, radius = 5,
        on_click = function() if win_id then exwin.close(win_id) end end
    })
    airui.label({ parent = back_btn, x = 10, y = 10, w = 60, h = 24, text = "返回", font_size = 20, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })

    airui.label({ parent = header, x = 10, y = 12, w = 460, h = 40, align = airui.TEXT_ALIGN_CENTER, text="FTP客户端", font_size=32, color=0xffffff })

    content = airui.container({ parent = main_container, x=0, y=60, w=480, h=740, color=0xF3F4F6 })

    -- 连接配置区域
    local connect_section = airui.container({ parent = content, x=0, y=0, w=480, h=200, color=0xFFFFFF })
    
    airui.label({ parent = connect_section, x=30, y=20, w=100, h=40, text="服务器:", font_size=24, color=0x000000 })
    server_input = airui.textarea({ parent = connect_section, x=130, y=20, w=300, h=40, placeholder = "ftp.example.com", font_size=20 })
    server_input:set_text("121.43.224.154") -- 默认服务器IP

    airui.label({ parent = connect_section, x=30, y=80, w=100, h=40, text="端口:", font_size=24, color=0x000000 })
    port_input = airui.textarea({ parent = connect_section, x=130, y=80, w=300, h=40, placeholder = "21", font_size=20 })
    port_input:set_text("21") -- 默认服务器端口号

    airui.label({ parent = connect_section, x=30, y=140, w=100, h=40, text="账号:", font_size=24, color=0x000000 })
    user_input = airui.textarea({ parent = connect_section, x=130, y=140, w=150, h=40, placeholder = "username", font_size=20 })
    user_input:set_text("ftp_user") -- 默认服务器登陆用户名

    airui.label({ parent = connect_section, x=300, y=140, w=60, h=40, text="密码:", font_size=24, color=0x000000 })
    pass_input = airui.textarea({ parent = connect_section, x=360, y=140, w=120, h=40, placeholder = "password", font_size=20 })
    pass_input:set_text("3QujbiMG") -- 默认服务器登陆密码

    -- 文件列表区域
    file_section = airui.container({ parent = content, x=0, y=290, w=480, h=450, color=0xFFFFFF })
    
    airui.label({ parent = file_section, x=10, y=10, w=460, h=30, text="文件列表", font_size=24, color=0x000000 })
    
    -- 路径显示
    airui.label({ parent = file_section, x=10, y=50, w=460, h=30, text="当前路径: " .. current_path, font_size=18, color=0x666666 })
    
    -- 格式化文件大小
    local function format_file_size(bytes)
        -- 确保bytes是数字类型
        bytes = tonumber(bytes) or 0
        if bytes < 1024 then
            return bytes .. "B"
        elseif bytes < 1024 * 1024 then
            return math.ceil(bytes / 1024) .. "KB"
        else
            return string.format("%.1fM", bytes / (1024 * 1024))
        end
    end
    
    -- 刷新文件列表
    local function refresh_file_list()
        -- 在协程中执行文件列表刷新操作
        sys.taskInit(function()
            -- 清空现有文件列表
            for _, item in ipairs(file_items) do
                if item then
                    item:destroy()
                end
            end
            file_items = {} -- 清空引用表
            
            -- 检查是否已连接
            if not ftp_client then
                local msg_label = airui.label({ parent = file_section, x=10, y=90, w=460, h=30, text="请先连接FTP服务器", font_size=18, color=0xFF0000 })
                table.insert(file_items, msg_label)
                return
            end
            
            -- 显示加载提示
            local loading_label = airui.label({ parent = file_section, x=10, y=90, w=460, h=30, text="正在加载客户端文件...", font_size=18, color=0x00796B })
            
            -- 等待1秒，让用户看到加载提示
            sys.wait(1000)
            
            -- 清空加载提示
            loading_label:destroy()
            
            -- 清空现有文件列表
            for _, item in ipairs(file_items) do
                if item then
                    item:destroy()
                end
            end
            file_items = {} -- 重新清空引用表
            
            -- 发送LIST命令获取文件列表
            if not exftp or type(exftp) ~= "table" then
                log.error("ftp", "exftp库未加载")
                return
            end
            
            -- 建立数据通道
            if not ftp_client:_connect_data_channel() then
                log.error("ftp", "建立数据通道失败")
                return
            end
            
            -- 发送LIST命令
            local code, msg = ftp_client:_send_cmd("LIST", 10000)
            if not code then
                ftp_client:_close_data_channel()
                log.error("ftp", "发送LIST命令失败")
                return
            end
            
            -- 读取文件列表数据
            local files = {}
            local start_time = os.time()
            
            log.info("ftp", "开始读取文件列表数据")
            
            -- 等待数据通道关闭，最多等待60秒
            while not ftp_client.data_closed do
                if ftp_client.data_rx_buff and ftp_client.data_rx_buff:used() > 0 then
                    local data = ftp_client.data_rx_buff:query()
                    -- 手动分割字符串
                    local i = 1
                    while i <= #data do
                        local j = string.find(data, "\r\n", i)
                        if not j then
                            j = string.find(data, "\n", i)
                            if not j then
                                break
                            end
                        end
                        local line = string.sub(data, i, j-1)
                        if line and line ~= "" then
                            table.insert(files, line)
                        end
                        i = j + 1
                    end
                    ftp_client.data_rx_buff:del()
                end
                
                -- 等待数据或事件
                local ret = sys.waitUntil(ftp_client.data_topic, 2000)
                if ret == false then
                    break
                end
                
                -- 检查超时
                if os.time() - start_time > 60 then
                    log.info("ftp", "读取文件列表超时(60秒)")
                    break
                end
            end
            
            log.info("ftp", "文件列表读取完成，共", #files, "条记录")
            
            -- 关闭数据通道
            ftp_client:_close_data_channel()
            
            -- 等待传输完成响应
            ftp_client:_wait_transfer_complete()
            
            -- 解析文件列表
            local parsed_files = {}
            
            -- 添加上级目录
            table.insert(parsed_files, { name = "..", type = "dir" })
            
            -- 解析LIST响应
            log.info("ftp", "开始解析文件列表，共", #files, "条记录")
            for i, line in ipairs(files) do
                log.info("ftp", "解析第", i, "条记录:", line)
                -- 尝试解析不同格式的LIST响应
                local is_dir, name, size
                
                -- 尝试解析标准UNIX LIST格式
                -- 格式示例: -rw-r--r-- 1 user group 1675 Apr  8 12:34 filename.txt
                local perm, links, user, group, size_str, month, day, time_or_year, rest = string.match(line, "^(.+)%s+(%d+)%s+(%S+)%s+(%S+)%s+(%d+)%s+(%S+)%s+(%S+)%s+(%S+)%s*(.*)$")
                
                if perm then
                    is_dir = string.sub(perm, 1, 1) == "d"
                    size = tonumber(size_str) or 0
                    -- 文件名可能包含空格，所以需要处理rest部分
                    name = rest and rest ~= "" and rest or time_or_year
                    log.info("ftp", "标准格式解析结果: name=", name, "is_dir=", is_dir, "size=", size)
                else
                    -- 简化的解析方式，直接提取文件名
                    -- 尝试从行尾提取文件名（适用于大多数LIST格式）
                    local last_space = string.find(string.reverse(line), " ")
                    if last_space then
                        name = string.sub(line, #line - last_space + 2)
                        is_dir = string.sub(line, 1, 1) == "d"
                        -- 尝试提取大小
                        -- 尝试多种方式解析文件大小
                        local size_str = string.match(line, "%s+(%d+)%s+")
                        size = size_str and tonumber(size_str) or nil
                        -- 如果第一种方式失败，尝试另一种格式
                        if not size then
                            size_str = string.match(line, "%s+(%d+)$")
                            size = size_str and tonumber(size_str) or nil
                        end
                        log.info("ftp", "简化格式解析结果: name=", name, "is_dir=", is_dir, "size=", size)
                    end
                end
                
                if name then
                    table.insert(parsed_files, {
                        name = name,
                        type = is_dir and "dir" or "file",
                        size = size
                    })
                    log.info("ftp", "添加到解析列表:", name)
                else
                    log.info("ftp", "解析失败，跳过这条记录")
                end
            end
            log.info("ftp", "文件列表解析完成，共", #parsed_files, "条记录")
            
            -- 打印根目录内容到日志
            log.info("ftp", "根目录内容:")
            for i, file in ipairs(parsed_files) do
                if file.type == "dir" then
                    log.info("ftp", "[目录] " .. file.name)
                else
                    log.info("ftp", "[文件] " .. file.name .. " (" .. (file.size or "未知") .. "B)")
                end
            end
            
            -- 显示文件列表
            local y_offset = 90
            
            -- 销毁之前的图标说明标签
            if icon_info_label then
                icon_info_label:destroy()
                icon_info_label = nil
            end
            
            -- 连接成功后显示图标说明
            if ftp_client then
                icon_info_label = airui.label({ parent = file_section, x=10, y=80, w=460, h=20, text="[D] 为文件夹, [F] 为文件", font_size=14, color=0x999999 })
                y_offset = 110
            end
            
            log.info("ftp", "开始显示文件列表，共", #parsed_files, "条记录")
            for i, file in ipairs(parsed_files) do
                log.info("ftp", "显示第", i, "条记录:", file.name, "类型:", file.type, "大小:", file.size)
                local file_item = airui.container({ parent = file_section, x=10, y=y_offset, w=460, h=40, color=0xF5F5F5, radius=5 })
                log.info("ftp", "创建文件项容器:", file_item)
                
                -- 使用文本图标
                local icon_text = file.type == "dir" and "[D]" or "[F]"
                local icon_label = airui.label({ parent = file_item, x=10, y=10, w=40, h=20, text=icon_text, font_size=16, color=0x00796B, align=airui.TEXT_ALIGN_CENTER })
                log.info("ftp", "创建图标标签:", icon_label)
                local name_label = airui.label({ parent = file_item, x=50, y=10, w=300, h=20, text=file.name, font_size=18, color=0x000000 })
                log.info("ftp", "创建名称标签:", name_label)
                
                if file.type == "file" then
                    -- 使用file.size或默认值0
                    local size = tonumber(file.size) or 0
                    local size_label = airui.label({ parent = file_item, x=360, y=10, w=90, h=20, text=format_file_size(size), font_size=16, color=0x666666, align=airui.TEXT_ALIGN_RIGHT })
                    log.info("ftp", "创建大小标签:", size_label, "文件大小:", size)
                end
                
                file_item:set_on_click(function()
                    if file.type == "dir" then
                        log.info("ftp", "进入目录", file.name)
                        -- 在协程中执行目录导航操作
                        sys.taskInit(function()
                            if file.name == ".." then
                                -- 返回上一级
                                if ftp_client:cdup() then
                                    local ok, path = ftp_client:pwd()
                                    if ok then
                                        current_path = path
                                        log.info("ftp", "当前目录", current_path)
                                        refresh_file_list()
                                    end
                                end
                            else
                                -- 进入子目录
                                if ftp_client:chdir(file.name) then
                                    local ok, path = ftp_client:pwd()
                                    if ok then
                                        current_path = path
                                        log.info("ftp", "当前目录", current_path)
                                        refresh_file_list()
                                    end
                                end
                            end
                        end)
                    elseif file.type == "file" then
                        log.info("ftp", "打开文件", file.name)
                        -- 下载并显示文件内容
                        sys.taskInit(function()
                            -- 显示加载提示
                            local load_label = airui.label({ parent = file_section, x=10, y=90, w=460, h=30, text="正在下载文件...", font_size=18, color=0x00796B })
                            
                            -- 尝试获取远程文件大小
                            local code, msg = ftp_client:_send_cmd("SIZE " .. file.name, 5000)
                            local file_size = 0
                            if code == 213 then
                                file_size = tonumber(msg:match("%d+")) or 0
                                log.info("ftp", "文件大小:", file_size, "字节")
                            end
                            
                            -- 检查文件系统剩余空间
                            local free_space = 0
                            local ok, stat = pcall(function()
                                return io.stat("/")
                            end)
                            if ok and stat and stat.bsize and stat.bavail then
                                free_space = stat.bsize * stat.bavail
                                log.info("ftp", "剩余空间:", free_space, "字节")
                            else
                                -- 尝试其他方式获取剩余空间
                                local ok2, info = pcall(function()
                                    return vfs.fsinfo("/")
                                end)
                                if ok2 and info and info.free then
                                    free_space = info.free
                                    log.info("ftp", "剩余空间:", free_space, "字节")
                                end
                            end
                            
                            -- 检查空间是否足够
                            if file_size > 0 and free_space > 0 and file_size > free_space then
                                -- 空间不足，显示提示
                                local alert_win = airui.container({ parent = airui.screen, x=100, y=200, w=280, h=150, color=0xFFFFFF, radius=10, shadow=5 })
                                airui.label({ parent = alert_win, x=10, y=30, w=260, h=40, text="空间不足，无法下载文件", font_size=16, color=0xFF0000, align=airui.TEXT_ALIGN_CENTER })
                                airui.label({ parent = alert_win, x=10, y=70, w=260, h=30, text="文件大小: " .. format_file_size(file_size) .. "\n剩余空间: " .. format_file_size(free_space), font_size=14, color=0x666666, align=airui.TEXT_ALIGN_CENTER })
                                airui.button({ parent = alert_win, x=100, y=110, w=80, h=30, text="确定", font_size=16, on_click=function()
                                    alert_win:destroy()
                                end })
                                load_label:destroy()
                                return
                            end
                            
                            -- 尝试使用retr命令下载文件到内存
                            log.info("ftp", "下载文件", file.name)
                            local data = ftp_client:retr(file.name)
                            local success = data ~= nil
                            
                            -- 销毁加载提示
                            load_label:destroy()
                            
                            if success and data then
                                log.info("ftp", "文件下载成功，大小:", #data)
                                
                                -- 显示文件内容
                                local content_win = airui.container({ parent = airui.screen, x=50, y=50, w=380, h=600, color=0xFFFFFF, radius=10, shadow=5 })
                                airui.label({ parent = content_win, x=10, y=10, w=360, h=30, text="文件内容: " .. file.name .. " (" .. format_file_size(#data) .. ")", font_size=18, color=0x000000 })
                                
                                -- 创建文本区域显示文件内容
                                local text_area = airui.textarea({ parent = content_win, x=10, y=50, w=360, h=500, text=data, font_size=14, color=0x000000, readonly=true })
                                
                                -- 关闭按钮
                                airui.button({ parent = content_win, x=150, y=560, w=80, h=40, text="关闭", font_size=16, on_click=function()
                                    content_win:destroy()
                                end })
                            else
                                log.error("ftp", "文件下载失败")
                                -- 显示错误提示
                                local error_label = airui.label({ parent = file_section, x=10, y=90, w=460, h=30, text="文件下载失败", font_size=18, color=0xFF0000 })
                                sys.wait(2000)
                                error_label:destroy()
                            end
                        end)
                    end
                end)
                
                -- 将文件项添加到引用表中
                table.insert(file_items, file_item)
                log.info("ftp", "添加文件项到引用表:", file.name, "当前引用表大小:", #file_items)
                
                y_offset = y_offset + 50
            end
            log.info("ftp", "文件列表显示完成，共添加", #file_items, "项到引用表")
        end) -- 结束sys.taskInit
    end
    
    -- 连接按钮
    connect_btn = airui.button({
        parent = content, x=180, y=220, w=120, h=50,
        text = "连接",
        font_size = 20,
        on_click = function()
            if ftp_client then
                -- 断开连接
                log.info("ftp", "断开连接")
                if ftp_client then
                    ftp_client:close()
                    ftp_client = nil
                end
                -- 销毁图标说明标签
                if icon_info_label then
                    icon_info_label:destroy()
                    icon_info_label = nil
                end
                -- 重置状态
                connect_btn:set_text("连接")
                -- 隐藏操作按钮容器
                if buttons_container then buttons_container:set_visible(false) end
                -- 刷新文件列表
                refresh_file_list()
            else
                -- 连接服务器
                local server = server_input:get_text()
                local port = port_input:get_text()
                local user = user_input:get_text()
                local pass = pass_input:get_text()
                log.info("ftp", "连接", server, port, user, pass)
                
                -- 在协程中执行FTP连接操作
                sys.taskInit(function()
                    -- 连接FTP服务器
                    if not exftp then
                        exftp = require "exftp"
                        if not exftp or type(exftp) ~= "table" then
                            log.error("ftp", "加载exftp库失败")
                            return
                        end
                    end
                    
                    -- 创建FTP客户端
                    ftp_client = exftp.create(nil, server, tonumber(port))
                    if not ftp_client then
                        log.error("ftp", "创建FTP客户端失败")
                        return
                    end
                    
                    -- 登录
                    if not ftp_client:auth(user, pass) then
                        log.error("ftp", "登录失败")
                        ftp_client:close()
                        ftp_client = nil
                        return
                    end
                    
                    log.info("ftp", "连接成功")
                    
                    -- 更新按钮文本
                    connect_btn:set_text("断开")
                    -- 显示操作按钮容器
                    if buttons_container then buttons_container:set_visible(true) end
                    
                    -- 获取当前目录
                    local ok, path = ftp_client:pwd()
                    if ok then
                        current_path = path
                        log.info("ftp", "当前目录", current_path)
                    end
                    
                    -- 确保在根目录
                    ftp_client:chdir("/")
                    local ok, path = ftp_client:pwd()
                    if ok then
                        current_path = path
                        log.info("ftp", "切换到根目录", current_path)
                    end
                    
                    -- 刷新文件列表
                    refresh_file_list()
                end)
            end
        end
    })
    
    -- 初始刷新文件列表
    refresh_file_list()

    -- 底部操作按钮
    local bottom_section = airui.container({ parent = content, x=0, y=700, w=480, h=40, color=0xFFFFFF })
    
    -- 创建操作按钮容器
    local buttons_container = airui.container({ parent = bottom_section, x=0, y=0, w=480, h=40, color=0xFFFFFF, visible=false })
    
    -- 上传按钮
    upload_button = airui.button({
        parent = buttons_container, x=100, y=0, w=140, h=40,
        text = "上传",
        font_size = 16,
        visible = false,
        on_click = function()
            log.info("ftp", "上传文件")
            
            -- 检查是否已连接
            if not ftp_client then
                local error_label = airui.label({ parent = file_section, x=10, y=90, w=460, h=30, text="请先连接FTP服务器", font_size=18, color=0xFF0000 })
                -- 使用协程来执行等待和销毁操作
                sys.taskInit(function()
                    sys.wait(2000)
                    error_label:destroy()
                end)
                return
            end
            
            -- 扫描根目录下的所有路径
            log.info("ftp", "开始扫描根目录下的所有路径")
            local accessible_paths = {}
            
            -- 尝试常见路径并记录结果
            local test_paths = {"/", "/luadb", "/luadb/", "./", "/app", "/app_store", "/data", "/tmp"}
            local path_status = {}
            
            for _, path in ipairs(test_paths) do
                local ok, entries = pcall(function()
                    return io.lsdir(path)
                end)
                local status = "unavailable"
                local color = 0xFF0000 -- 红色
                local message = "无法访问"
                
                if ok and type(entries) == "table" and #entries > 0 then
                    -- 尝试读取目录内容，确保真正可访问
                    local has_content = false
                    for _, entry in ipairs(entries) do
                        if entry.name and entry.name ~= "." and entry.name ~= ".." then
                            has_content = true
                            break
                        end
                    end
                    if has_content or #entries > 2 then -- 至少有一个非.和..的条目，或者有更多条目
                        status = "accessible"
                        color = 0x00FF00 -- 绿色
                        message = "可访问 (" .. #entries .. "个条目)"
                        table.insert(accessible_paths, path)
                    else
                        status = "empty"
                        color = 0xFFFF00 -- 黄色
                        message = "可访问但无内容"
                    end
                end
                
                table.insert(path_status, { path = path, status = status, color = color, message = message })
                log.info("ftp", path, "状态:", status, "消息:", message)
            end
            
            log.info("ftp", "扫描完成，找到", #accessible_paths, "个可访问路径")
            
            -- 显示文件系统浏览窗口
            local browse_win = airui.container({ parent = airui.screen, x=50, y=50, w=380, h=800, color=0xFFFFFF, radius=10, shadow=5 })
            airui.label({ parent = browse_win, x=10, y=10, w=320, h=30, text="选择要上传的文件", font_size=18, color=0x000000 })
            
            -- 右上角叉号按钮
            airui.button({ parent = browse_win, x=340, y=5, w=30, h=30, text="×", font_size=20, color=0xFF0000, on_click=function()
                browse_win:destroy()
            end })
            
            -- 当前浏览路径
            local current_fs_path = "./" -- 默认使用当前目录
            
            -- 路径显示
            local path_label = airui.label({ parent = browse_win, x=10, y=50, w=360, h=20, text="当前路径: " .. current_fs_path, font_size=14, color=0x666666 })
            
            -- 路径状态显示
            local y_offset = 70
            airui.label({ parent = browse_win, x=10, y=y_offset, w=360, h=20, text="路径状态:", font_size=14, color=0x000000 })
            y_offset = y_offset + 25
            
            -- 确保至少显示一些路径状态
            if #path_status == 0 then
                -- 添加默认路径状态
                table.insert(path_status, { path = "/", status = "unavailable", color = 0xFF0000, message = "无法访问" })
                table.insert(path_status, { path = "/luadb", status = "unavailable", color = 0xFF0000, message = "无法访问" })
                table.insert(path_status, { path = "./", status = "unavailable", color = 0xFF0000, message = "无法访问" })
            end
            
            for i, item in ipairs(path_status) do
                airui.label({ 
                    parent = browse_win, 
                    x=20, 
                    y=y_offset, 
                    w=150, 
                    h=20, 
                    text=item.path, 
                    font_size=14, 
                    color=item.color 
                })
                airui.label({ 
                    parent = browse_win, 
                    x=170, 
                    y=y_offset, 
                    w=200, 
                    h=20, 
                    text=item.message, 
                    font_size=12, 
                    color=0x666666, 
                    align=airui.TEXT_ALIGN_RIGHT 
                })
                
                -- 如果路径可访问，添加选择按钮
                if item.status == "accessible" then
                    airui.button({ 
                        parent = browse_win, 
                        x=20, 
                        y=y_offset + 20, 
                        w=340, 
                        h=25, 
                        text="选择此路径", 
                        font_size=12, 
                        color=0x00796B, 
                        on_click=function()
                            current_fs_path = item.path
                            path_label:set_text("当前路径: " .. current_fs_path)
                            log.info("ftp", "用户选择路径:", current_fs_path)
                            refresh_fs_list()
                        end 
                    })
                    y_offset = y_offset + 45
                else
                    y_offset = y_offset + 30
                end
            end
            
            -- 提示信息
            airui.label({ 
                parent = browse_win, 
                x=10, 
                y=y_offset, 
                w=360, 
                h=20, 
                text="绿色: 可访问 | 黄色: 空目录 | 红色: 无法访问", 
                font_size=12, 
                color=0x666666 
            })
            y_offset = y_offset + 25
            
            -- 手动输入路径功能
            airui.label({ parent = browse_win, x=10, y=y_offset, w=360, h=20, text="手动输入路径:", font_size=14, color=0x000000 })
            y_offset = y_offset + 25
            
            local path_input = airui.textarea({ 
                parent = browse_win, 
                x=20, 
                y=y_offset, 
                w=280, 
                h=30, 
                text="./", 
                font_size=14, 
                color=0x000000 
            })
            
            airui.button({ 
                parent = browse_win, 
                x=310, 
                y=y_offset, 
                w=50, 
                h=30, 
                text="确定", 
                font_size=12, 
                color=0x00796B, 
                on_click=function()
                    local input_path = path_input:get_text()
                    if input_path and input_path ~= "" then
                        current_fs_path = input_path
                        path_label:set_text("当前路径: " .. current_fs_path)
                        log.info("ftp", "用户手动输入路径:", current_fs_path)
                        refresh_fs_list()
                    end
                end 
            })
            y_offset = y_offset + 40
            
            -- 文件列表区域
            local fs_list_section = airui.container({ parent = browse_win, x=10, y=y_offset, w=360, h=600 - y_offset - 10, color=0xF5F5F5 })
            
            -- 刷新文件系统列表
            local function refresh_fs_list()
                -- 清空现有列表
                -- 由于get_children方法可能不存在，直接创建新的容器替换
                local old_fs_list_section = fs_list_section
                fs_list_section = airui.container({ parent = browse_win, x=10, y=y_offset, w=360, h=800 - y_offset - 10, color=0xF5F5F5 })
                if old_fs_list_section then
                    old_fs_list_section:destroy()
                end
                
                -- 读取当前目录内容
                local files = {}  
                log.info("ftp", "浏览文件系统，当前路径:", current_fs_path)
                local ok, entries = pcall(function()
                    return io.lsdir(current_fs_path)
                end)
                
                if ok and type(entries) == "table" and #entries > 0 then
                    log.info("ftp", "成功打开目录:", current_fs_path, "包含", #entries, "个条目")
                    local file_count = 0
                    local dir_count = 0
                    
                    -- 添加上级目录
                    local parent_item = airui.container({ parent = fs_list_section, x=0, y=10, w=360, h=40, color=0xFFFFFF, radius=5 })
                    airui.label({ parent = parent_item, x=10, y=10, w=340, h=20, text="[D] ..", font_size=16, color=0x00796B })
                    parent_item:set_on_click(function()
                        if current_fs_path ~= "/luadb/" and current_fs_path ~= "./" then
                            -- 返回上级目录
                            current_fs_path = current_fs_path:match("^(.*)/[^/]*$") or "/luadb/"
                            if current_fs_path == "" then
                                current_fs_path = "/luadb/"
                            end
                            path_label:set_text("当前路径: " .. current_fs_path)
                            refresh_fs_list()
                        end
                    end)
                    
                    local y = 60
                    for _, entry in ipairs(entries) do
                        if entry.name and entry.name ~= "." and entry.name ~= ".." then
                            local full_path = current_fs_path
                            if full_path ~= "./" and full_path ~= "/" then
                                full_path = full_path .. "/"
                            end
                            full_path = full_path .. entry.name
                            
                            local is_dir = entry.type == "directory"
                            local file_size = entry.size or 0
                            
                            if is_dir then
                                dir_count = dir_count + 1
                                log.info("ftp", "[目录]", entry.name, "路径:", full_path)
                            else
                                file_count = file_count + 1
                                log.info("ftp", "[文件]", entry.name, "大小:", file_size, "字节", "路径:", full_path)
                            end
                            
                            local file_item = airui.container({ parent = fs_list_section, x=0, y=y, w=360, h=40, color=0xFFFFFF, radius=5 })
                            local icon_text = is_dir and "[D]" or "[F]"
                            airui.label({ parent = file_item, x=10, y=10, w=340, h=20, text=icon_text .. " " .. entry.name, font_size=16, color=is_dir and 0x00796B or 0x000000 })
                            
                            file_item:set_on_click(function()
                                if is_dir then
                                    -- 进入子目录
                                    current_fs_path = full_path
                                    path_label:set_text("当前路径: " .. current_fs_path)
                                    refresh_fs_list()
                                else
                                    -- 选择文件上传
                                    log.info("ftp", "上传文件", full_path, "到FTP服务器")
                                    
                                    -- 显示上传进度
                                    local upload_label = airui.label({ parent = file_section, x=10, y=90, w=460, h=30, text="正在上传文件...", font_size=18, color=0x00796B })
                                    
                                    -- 在协程中执行上传操作
                                    sys.taskInit(function()
                                        -- 检查文件是否存在
                                        local fd = io.open(full_path, "rb")
                                        if not fd then
                                            log.error("ftp", "无法打开文件:", full_path, "权限错误")
                                            upload_label:destroy()
                                            local error_label = airui.label({ parent = file_section, x=10, y=90, w=460, h=30, text="无法打开文件，权限不足", font_size=18, color=0xFF0000 })
                                            sys.wait(2000)
                                            error_label:destroy()
                                            browse_win:destroy()
                                            return
                                        end
                                        fd:close()
                                        
                                        -- 检查文件大小
                                        local file_size = 0
                                        local ok, stat = pcall(function()
                                            return io.stat(full_path)
                                        end)
                                        if ok and stat and stat.size then
                                            file_size = stat.size
                                            log.info("ftp", "文件大小:", file_size, "字节")
                                        else
                                            log.error("ftp", "无法获取文件大小")
                                            upload_label:destroy()
                                            local error_label = airui.label({ parent = file_section, x=10, y=90, w=460, h=30, text="无法获取文件信息", font_size=18, color=0xFF0000 })
                                            sys.wait(2000)
                                            error_label:destroy()
                                            browse_win:destroy()
                                            return
                                        end
                                        
                                        log.info("ftp", "开始上传文件")
                                        -- 上传文件
                                        local success = ftp_client:upload(full_path, entry.name)
                                        
                                        -- 销毁上传提示
                                        upload_label:destroy()
                                        
                                        if success then
                                            log.info("ftp", "文件上传成功")
                                            local success_label = airui.label({ parent = file_section, x=10, y=90, w=460, h=30, text="文件上传成功", font_size=18, color=0x00796B })
                                            sys.wait(2000)
                                            success_label:destroy()
                                            -- 刷新FTP文件列表
                                            refresh_file_list()
                                        else
                                            log.error("ftp", "文件上传失败")
                                            local error_label = airui.label({ parent = file_section, x=10, y=90, w=460, h=30, text="文件上传失败", font_size=18, color=0xFF0000 })
                                            sys.wait(2000)
                                            error_label:destroy()
                                        end
                                    end)
                                    
                                    -- 关闭浏览窗口
                                    browse_win:destroy()
                                end
                            end)
                            
                            y = y + 45
                        end
                    end
                    log.info("ftp", "目录统计:", "文件数:", file_count, "目录数:", dir_count)
                else
                    log.error("ftp", "无法打开目录:", current_fs_path)
                    -- 显示错误提示
                    airui.label({ parent = fs_list_section, x=10, y=20, w=340, h=30, text="无法访问此目录", font_size=16, color=0xFF0000 })
                    airui.label({ parent = fs_list_section, x=10, y=60, w=340, h=20, text="请尝试其他路径或手动输入路径", font_size=14, color=0x666666 })
                end
            end
            
            -- 初始刷新文件系统列表
            refresh_fs_list()
            
            -- 关闭按钮
            airui.button({ parent = browse_win, x=150, y=750, w=80, h=40, text="关闭", font_size=16, on_click=function()
                browse_win:destroy()
            end })
        end
    })
    
    -- 刷新按钮
    refresh_button = airui.button({
        parent = buttons_container, x=300, y=0, w=120, h=40,
        text = "刷新",
        font_size = 16,
        visible = false,
        on_click = function()
            log.info("ftp", "刷新列表")
            refresh_file_list()
        end
    })
end

local function on_create()
    -- 启用系统键盘
    airui.keyboard_enable_system(true)
    create_ui()
end

local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    win_id = nil
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end
sys.subscribe("OPEN_FTP_CLIENT_WIN", open_handler)