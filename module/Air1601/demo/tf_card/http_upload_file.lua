--[[
@module http_upload_file
@summary TF卡大文件httpplus上传模块
@version 1.0.0
@date 2025.08.25
@author 王棚嶙
@usage
本文件演示通过httpplus库将TF卡中的大文件上传到HTTP服务器：
1. 网络就绪检测
2. TF卡文件系统挂载
3. 大文件上传功能
4. 上传结果记录
本文件没有对外接口，直接在main.lua中require "http_upload_file"即可
]]
local httpplus = require "httpplus"

local function http_upload_task()
    while not socket.adapter(socket.dft()) do
        log.warn("HTTP上传", "等待网络连接", socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end

    log.info("HTTP上传", "网络已就绪", socket.dft())

    spi_id, pin_cs = 1, 8
    spi.setup(spi_id, nil, 0, 0,8,400000)
    gpio.setup(pin_cs, 1)
    
    local mount_ok = fatfs.mount(fatfs.SPI, "/sd", spi_id, pin_cs, 24000000)
    if not mount_ok then
        log.error("HTTP上传", "文件系统挂载失败")
        fatfs.unmount("/sd/1.mp3")
        spi.close(spi_id)
        return
    end

    local upload_file_path ="/sd/1.mp3" 
    if not io.exists(upload_file_path) then
        log.error("HTTP上传", "要上传的文件不存在", upload_file_path)
        fatfs.unmount("/sd")
        spi.close(spi_id)
        return
    end

    local file_size = io.fileSize(upload_file_path)
    log.info("HTTP上传", "准备上传文件", upload_file_path, "大小:", file_size, "字节")

    log.info("HTTP上传", "开始上传任务")
    
    local code, response = httpplus.request({
        url = "http://airtest.openluat.com:2900/uploadFileToStatic",
        files = {
            ["uploadFile"] = upload_file_path, 
        },
    })

    log.info("HTTP上传", "上传完成", 
        code == 200 and "success" or "error", 
        code)
    
    if code == 200 then
        log.info("HTTP上传", "服务器响应头", json.encode(response.headers or {}))
        local body = response.body and response.body:query()
        log.info("HTTP上传", "服务器响应体长度", body and body:len() or 0)
        
        if body then
            log.info("HTTP上传", "服务器响应内容", body:len() > 512 and "内容过长，不显示" or body)
        end
    else
        log.error("HTTP上传", "上传失败", code)
    end

    fatfs.unmount("/sd")
    spi.close(spi_id)
    log.info("HTTP上传", "资源清理完成")
end

sys.taskInit(http_upload_task)
