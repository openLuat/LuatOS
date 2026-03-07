
--[[
@module  cam_control
@summary 网络摄像头控制模块
@version 1.0
@date    2026.03.06
@author  拓毅恒
@usage
控制网络摄像头的OSD显示、拍照和上传功能
功能：在网络连接成功后，控制网络摄像头设置OSD文字显示内容和位置，进行拍照操作，并根据SD卡状态智能选择保存路径，最后将照片上传到测试服务器。

特性：
- 支持大华摄像头OSD文字显示
- 智能路径选择：SD卡挂载时保存到/sd/，未挂载时保存到/luadb/
- 自动照片上传到air32.cn测试服务器

本文件没有对外接口，直接在main.lua中require "cam_control"就可以加载运行。
]]

-- 导入exremotecam模块
local dhcam = require "dhcam"
local exremotecam = require "exremotecam"
-- 引入httpplus扩展库模块用于照片上传
local httpplus = require "httpplus"

-- 保存图片名称
local photo_save_addr = "get_photo.jpeg"

-- 照片上传功能函数
local function upload_photo_task()
    while true do
        -- 等待拍照完成事件，并获取保存路径
        local _, save_path = sys.waitUntil("PHOTO_CAPTURE_DONE")
        
        -- 读取照片文件
        local photo_data = io.readFile(save_path)
        if photo_data then
            log.info("照片读取成功", "文件大小:", #photo_data, "字节", "路径:", save_path)
            
            -- 通过网卡状态判断网络是否连接成功
            while not socket.adapter(socket.dft()) do
                log.warn("upload_photo_task", "等待网络连接...")
                sys.waitUntil("IP_READY", 30000)
            end
            
            -- 将拍摄到的照片数据上传到服务器air32.cn
            -- 如果上传成功，电脑上浏览器打开https://www.air32.cn/upload/data/jpg/，打开对应的测试日期目录，点击具体的测试时间照片，可以查看摄像头拍照上传的照片
            local code = httpplus.request({
                url = "http://upload.air32.cn/api/upload/jpg",
                method = "POST",
                body = photo_data
            })
            
            -- 打印http传输状态
            log.info("照片上传结果", "HTTP状态码:", code)
            
            -- 根据状态码判断上传结果
            if code == 200 then
                log.info("照片上传成功", "可在 https://www.air32.cn/upload/data/jpg/ 查看")
            else
                log.warn("照片上传失败", "状态码:", code)
            end
        else
            log.error("照片读取失败", "文件不存在或读取错误", "路径:", save_path)
        end
    end
end

-- 拍照任务
local function camera_start()
    sys.waitUntil("NET_CONNECT_OK")
    log.info("开始运行OSD操作")
    
    -- 配置大华摄像头OSD，分六行依次显示 1111 2222 3333 4444 5555 6666
    exremotecam.osd({brand = "dhcam", host = "192.168.1.108", channel = 0, text = "1111|2222|3333|4444|5555|6666", x = 0, y = 2000})
    
    -- 等待OSD配置完成再进行拍照
    sys.wait(1000) 
    log.info("开始运行抓图操作")
    
    -- 判断SD卡状态，选择保存路径
            local save_path
            if io.exists("/sd") then
                save_path = "/sd/" .. photo_save_addr
                log.info("SD卡已挂载", "照片将保存到:", save_path)
            else
                save_path = "/luadb/" .. photo_save_addr
                log.info("SD卡未挂载", "照片将保存到:", save_path)
            end
    
    -- 执行拍照操作
    local result = exremotecam.get_photo({brand = "dhcam", host = "192.168.1.108", channel = 1, save_path = save_path})
    
    if result == 1 then
        log.info("拍照成功", "照片已保存到:", save_path)
        -- 发布拍照完成事件，触发上传任务
        sys.publish("PHOTO_CAPTURE_DONE", save_path)
    else
        log.warn("拍照失败", "返回码:", result)
    end
end

sys.taskInit(camera_start)
-- 启动照片上传任务
sys.taskInit(upload_photo_task)