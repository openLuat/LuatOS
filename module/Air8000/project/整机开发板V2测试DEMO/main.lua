-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "develment_boards_demo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)
_G.sys = require("sys")
_G.sysplus = require("sysplus")
--[[
本示例代码支持的功能项如下:
“AUDIO_PLAY":                       ---- 音频-播放音乐功能展示
“CAMERA”:                           ---- 摄像头功能展示
“CAN”:                              ---- CAN 测试
"ETHERNAT_WAN":                     ---- 以太网WAN功能测试
“KEY” :                             ---- 按键测试
"LCD":                              --- LCD 功能测试
"LED":                              --- LED 功能测试
"SIM":                              --- SIM 卡热插拔功能测试
"TF":                               --- TF 卡功能测试
]]

_G.NOW_PROJECT = "LCD"                --- 可以在此处选择需要测试的项目

if  NOW_PROJECT == "AUDIO_PLAY" then           
    require "test_audio_play"                    
elseif NOW_PROJECT == "CAMERA" then             
    require "test_camera"       
elseif NOW_PROJECT == "CAN" then               
    require "test_can"                    
elseif NOW_PROJECT == "ETHERNAT_WAN" then     
    require "test_ethernat_wan"                  
elseif NOW_PROJECT == "KEY" then              
    require "test_key"                        
elseif NOW_PROJECT ==  "LCD" then             
    require "test_lcd"                           
elseif NOW_PROJECT == "LED" then              
    require "test_led"  
elseif NOW_PROJECT == "SIM" then              
    require "test_sim_det"                              
elseif NOW_PROJECT == "TF" then               
    require "test_tf"                       
end


if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end
log.info("main", "develment boards demo")


sys.timerLoopStart(function()
    log.info("mem.lua", rtos.meminfo())
    log.info("mem.sys", rtos.meminfo("sys"))
 end, 3000)



-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
