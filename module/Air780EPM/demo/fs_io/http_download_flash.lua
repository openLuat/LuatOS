--[[
@module http_download_flash
@summary HTTP下载文件到内置Flash模块
@version 1.0.0
@date    2025.09.23
@author  王棚嶙
@usage
本文件演示的功能为通过HTTP下载文件到内置Flash中：
1. 网络就绪检测
2. 创建HTTP下载任务并等待完成
3. 记录下载结果
4. 获取并记录文件大小(使用io.fileSize)
本文件没有对外接口，直接在main.lua中require "http_download_flash"即可
]]

local function http_download_flash_task()
    -- 阶段1: 网络就绪检测
    while not socket.adapter(socket.dft()) do
        log.warn("HTTP下载", "等待网络连接", socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end

    log.info("HTTP下载", "网络已就绪", socket.dft())

    -- 阶段2: 执行下载任务
    log.info("HTTP下载", "开始下载任务")

    -- 创建下载目录
    local download_dir = "/downloads"
    if not io.dexist(download_dir) then
        io.mkdir(download_dir)
    end

    -- 核心下载操作开始
    local code, headers, body_size = http.request("GET",
                                    "https://gitee.com/openLuat/LuatOS/raw/master/module/Air780EHM_Air780EHV_Air780EGH/demo/audio/sample-6s.mp3",
                                    nil, nil, {dst = download_dir .. "/sample-6s.mp3"}).wait()

    -- 阶段3: 记录下载结果
    log.info("HTTP下载", "下载完成", 
        code == 200 and "success" or "error", 
        code, 
        json.encode(headers or {}), 
        body_size) 
        
    if code == 200 then
        -- 获取实际文件大小 (使用io.fileSize接口)
        local actual_size = io.fileSize(download_dir .. "/sample-6s.mp3")
        if not actual_size then
            -- 备用方案
            actual_size = io.fileSize(download_dir .. "/sample-6s.mp3")
        end
        
        log.info("HTTP下载", "文件大小验证", "预期:", body_size, "实际:", actual_size)
        
        if actual_size ~= body_size then
            log.error("HTTP下载", "文件大小不一致", "预期:", body_size, "实际:", actual_size)
        end
        
        -- 展示下载后的文件系统状态
        local success, total_blocks, used_blocks, block_size, fs_type =  io.fsstat("/")
        if success then
            log.info("HTTP下载", "下载后文件系统信息:", 
                     "总空间=" .. total_blocks .. "块", 
                     "已用=" .. used_blocks .. "块", 
                     "块大小=" .. block_size.."字节",
                     "类型=" .. fs_type)
        end
    end

end

-- 创建下载任务
sys.taskInit(http_download_flash_task)