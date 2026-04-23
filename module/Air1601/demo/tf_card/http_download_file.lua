--[[
@module http_download_file
@summary http下载文件模块
@version 1.0.0
@date    2025.08.25
@author  王棚嶙
@usage
本文件演示的功能为通过http下载文件进入TF卡中：
1. 网络就绪检测
2. 创建HTTP下载任务并等待完成
3. 记录下载结果
4. 获取并记录文件大小
本文件没有对外接口，直接在main.lua中require "http_download_file"即可
]] 

local function http_download_file_task()

    while not socket.adapter(socket.dft()) do
        log.warn("HTTP下载", "等待网络连接", socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end

    log.info("HTTP下载", "网络已就绪", socket.dft())

    spi_id, pin_cs = 1, 8
    spi.setup(spi_id, nil, 0, 0,8,400000)
    gpio.setup(pin_cs, 1)

    local mount_ok = fatfs.mount(fatfs.SPI, "/sd", spi_id, pin_cs, 24000000)
    if not mount_ok then
        log.error("HTTP下载", "文件系统挂载失败")
        fatfs.unmount("/sd")
        spi.close(spi_id)
        return
    end

    log.info("HTTP下载", "开始下载任务")

    local code, headers, body_size = http.request("GET",
                                    "http://airtest.openluat.com:2900/download/1.mp3",
                                    nil, nil, {dst = "/sd/1.mp3"}).wait()
    log.info("HTTP下载", "下载完成", 
        code==200 and "success" or "error", 
        code, 
        json.encode(headers or {}), 
        body_size) 
        
    if code == 200 then
        local actual_size = io.fileSize("/sd/1.mp3")
        log.info("HTTP下载", "文件大小验证", "预期:", body_size, "实际:", actual_size)
        
        if actual_size~= body_size then
            log.error("HTTP下载", "文件大小不一致", "预期:", body_size, "实际:", actual_size)
        end
    end

    fatfs.unmount("/sd")
    spi.close(spi_id)
    log.info("HTTP下载", "资源清理完成")
end

sys.taskInit(http_download_file_task)
