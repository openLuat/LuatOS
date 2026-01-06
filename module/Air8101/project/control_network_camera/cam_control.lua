
--[[
@module  cam_control
@summary 网络摄像头控制模块
@version 1.0
@date    2025.12.30
@author  拓毅恒
@usage
控制网络摄像头的OSD显示和拍照功能
功能：在网络连接成功后，控制网络摄像头设置OSD文字显示内容和位置，并进行拍照操作，照片保存在SD卡中。

本文件没有对外接口，直接在main.lua中require "cam_control"就可以加载运行。
]]

-- 导入exremotecam模块
local dhcam = require "dhcam"
local exremotecam = require "exremotecam"

local function camera_start()
    sys.waitUntil("WIFI_CONNECT_OK")
    log.info("开始运行OSD操作")
    -- 配置大华摄像头OSD，分六行依次显示 1111 2222 3333 4444 5555 6666
    exremotecam.osd({brand = "Dhua", host = "192.168.1.108", channel = 0, text = "1111|2222|3333|4444|5555|6666", x = 0, y = 2000})
    -- 等待OSD配置完成再进行拍照
    sys.wait(1000) 
    log.info("开始运行抓图操作")
    exremotecam.get_photo({brand = "Dhua", host = "192.168.1.108", channel = 1})
end

sys.taskInit(camera_start)