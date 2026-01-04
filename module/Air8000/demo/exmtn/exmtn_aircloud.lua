--[[
@module  exmtn_aircloud
@summary exmtn_aircloud测试功能模块
@version 1.0
@date    2025.12.10
@author  马亚丹
@usage
本demo演示的功能为：使用Air8000核心板 演示exmtn扩展库结合excloud扩展库 实现运维日志上传到云平台的功能。

核心逻辑：
1.联网判断，初始化exmtn

2.输出日志并写入日志到运维日志文件

2.开启excloud服务,并启动心跳保活机制

3.运维日志管理：当服务器下发 "运维日志上传请求" 时， excloud会自动扫描日志文件并上传到云端

]]



-- 引入 exmtn 模块
local exmtn = require "exmtn"
--引入 excloud模块
local excloud = require "excloud"

--定义日志内容
temp_log = "\n"
for i = 1, 5 do
    temp_log = temp_log .. "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789\n"
end

--获取exmtn配置状态
local function exmtn_config()
    -- 设置为1个区块  
    local config = exmtn.get_config()
    log.info("获取配置状态", config)
    if config then
        log.info("当前 exmtn 的配置状态",
            "enabled:", config.enabled,
            "cur_index:", config.cur_index,
            "block_size:", config.block_size,
            "blocks_per_file:", config.blocks_per_file,
            "file_limit:", config.file_limit,
            "write_way:", config.write_way)
    end
end

-- 输出日志并写入日志到运维日志文件
-- 使用 excloud 封装的接口记录日志， 这实际上会调用 exmtn.log，并添加自动上传的逻辑支持
-- 当服务器下发 "运维日志上传请求" (信令25) 时， excloud 会自动扫描 exmtn 生成的文件并上传到云端
local function mtnlog_task()
    local test_count = 0

    while true do
        test_count = test_count + 1

        --使用 exmtn 扩展库的接口记录日志
        exmtn.log("info", "test mtn info_log", test_count)
        exmtn.log("warn", "test mtn warn_log", test_count)
        exmtn.log("error", "test mtn error_log", test_count)
        exmtn.log("info", temp_log, test_count)
        --使用 excloud 封装的接口记录日志
        excloud.mtn_log("info", temp_log, test_count)
        --每2秒写入一次
        sys.wait(2000)
    end
end

sys.taskInit(mtnlog_task)


-- 回调函数
function on_excloud_event(event, data)
    if event == "mtn_log_upload_start" then
        log.info("运维日志上传开始", "文件数量:", data.file_count)
    elseif event == "mtn_log_upload_progress" then
        log.info("运维日志上传进度",
            "当前文件:", data.current_file,
            "总数:", data.total_files,
            "文件名:", data.file_name,
            "状态:", data.status)
    elseif event == "mtn_log_upload_complete" then
        log.info("运维日志上传完成",
            "成功:", data.success_count,
            "失败:", data.failed_count,
            "总计:", data.total_files)
    end
end

-- 注册回调
excloud.on(on_excloud_event)

--主函数
local function mtn_cloud()
    -- 如果当前时间点设置的默认网卡还没有连接成功，一直在这里循环等待
    while not socket.adapter(socket.dft()) do
        log.warn("excloud_task_func", "wait IP_READY", socket.dft())
        -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态;
        -- 注意：此处的1000毫秒超时不要修改的更长；
        -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
        -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
        -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end

    -- 配置excloud参数，excloud.setup 会自动调用 exmtn.init
    local ok, err_msg = excloud.setup({
        use_getip = true,                               -- 使用getip服务
        device_type = 1,                                -- 4G设备
        auth_key = "Cr8AYD0C2rKqE2vwJ9hWfMMDmQpJuARk",  -- 鉴权密钥
        transport = "tcp",                              -- 使用TCP传输
        auto_reconnect = true,                          -- 自动重连
        reconnect_interval = 10,                        -- 重连间隔(秒)
        max_reconnect = 5,                              -- 最大重连次数
        mtn_log_enabled = true,                         -- 启用运维日志
        mtn_log_blocks = 1,                             -- 日志文件块数
        mtn_log_write_way = excloud.MTN_LOG_CACHE_WRITE -- 缓存写入方式
    })

    if not ok then
        log.info("初始化失败: " .. err_msg)
        return
    else
        log.info("excloud初始化成功")
        --初始化成功后获取exmtn配置状态
        exmtn_config()
    end


    -- 开启excloud服务
    local ok, err_msg = excloud.open()
    if not ok then
        log.info("开启excloud服务失败: " .. err_msg)
        return
    else
        log.info("excloud服务已开启")
        -- 启动自动心跳，默认5分钟一次的心跳
        excloud.start_heartbeat()
        log.info("自动心跳已启动")
    end
end

sys.taskInit(mtn_cloud)
