PROJECT = "startupv13"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
sys = require("sys")
local airlcd = require "airlcd"
local airgps = require "airgps"
local airsta = require "airsta"
local airmusic = require "airmusic"
local airap = require "airap"
local airtts  = require "airtts"
local airlan = require "airlan"
local airwan = require "airwan"

local airaudio  = require "airaudio"
local aircamera = require "aircamera"
local airrus = require "russia"
local airstatus = require "statusbar"
local airtestwlan = require "test_wlan"
local airbuzzer = require "airbuzzer"
local multi_network = require "multi_network"
local taskName = "MAIN"

local sid = 0

-- 按键事件类型：
-- "switch": 短按开机键切换菜单；  
-- "enter"： 长按开机键进入功能菜单或者退出功能菜单

-- 当前功能界面
-- "main":      九宫格主界面
-----------页面1------------------
-- "gps":       gps定位
-- "wifiap":    wifiap，可实现4g转wifi 用作热点传出
-- "wifista":   链接wifi路由器
-- "camera":    摄像头预览
-- "call":      拨打电话
-- "bt":        蓝牙
-- "sms":       短信
-- "tts":       文字转语音
------------页面2------------------
-- "record":    录音
-- "music":     播放音乐
-- "tf":        驱动TF卡
-- "gsensor":   运动传感器
-- "pm":        电源管理
-- "lan":       以太网lan 通讯，通过air8000 给以太网设备上网
-- "wan":       以太网wan 通讯，通过以太网给air8000 上网
---------页面3------------------
-- "multi_network": 多网融合演示
-- "485":       485 通讯
-- "can":       can 通讯
-- "onewire":   onewire 通讯
-- "pwm":       输出PWM 波形
-- "uart":      串口输出
-- "232":       232

local cur_fun = "main"
-- local cur_sel = 0

-- local funlist = {
-- "gps", "wifiap","wifista","camera", "call","bt","sms","tts",
-- "record","music","tf","gsensor","pm","lan","wan",
-- "multi_network","485","can","onewire","pwm","uart","232"
-- }

_G.bkcolor = lcd.rgb565(99, 180, 245,false)

local function wdtInit()
-- 添加硬狗防止程序卡死
  if wdt then
    wdt.init(9000) -- 初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000) -- 3s喂一次狗
  end
end



local function update()
  if cur_fun == "russia" then
    airrus.updaterus()
  end

  if airstatus.data.bat_level == 0 then
    airstatus.get_bat_level()
  end
end



local lock_push = 1
local function main_local(x,y)
  if x > 0 and  x < 100 and y > 64  and  y < 192 then
    return 1
  elseif x > 100 and  x < 200 and y > 64  and  y < 192 then
    return 2
  elseif x > 200 and  x < 300 and y > 64  and  y < 192 then
    return 3
  elseif x > 0 and  x < 100 and y > 192  and  y < 320 then
    return 4
  elseif x > 100 and  x < 200 and y > 192  and  y < 320 then
    return 5
  elseif x > 200 and  x < 300 and y > 192  and  y < 320 then
    return 6
  elseif x > 0 and  x < 100 and y > 320  and  y < 448 then
    return 7
  elseif x > 100 and  x < 200 and y > 320  and  y < 448 then
    return 8
  elseif x > 200 and  x < 300 and y > 320  and  y < 448 then
    return 9
  end
end

local function handal_main(x,y)
  key =  main_local(x,y) 
  log.info("tp_handal key",key)
  if key == 1 then
    cur_fun  = "gps"
  elseif key == 2 then
    cur_fun = "ap"
  elseif key == 3 then
    cur_fun = "sta"
  elseif key == 4 then
    cur_fun  = "camera"
  elseif key == 5 then
  elseif key == 6 then
  elseif key == 7 then
  elseif key == 8 then    --  tts
    cur_fun  = "tts"
   elseif key == 9 then
    cur_fun = "main1"
  end
end

local function handal_main1(x,y)
  key =  main_local(x,y) 
  log.info("tp_handal key",key)
  if key == 1 then
  elseif key == 2 then
   
  elseif key == 3 then
  elseif key == 4 then
  elseif key == 5 then
  elseif key == 6 then
    cur_fun = "lan"
  elseif key == 7 then
    cur_fun = "main"
  elseif key == 8 then
    cur_fun = "wan"
  elseif key == 9 then
    cur_fun = "main2"
  end
end

local function handal_main2(x,y)
  key =  main_local(x,y) 
  log.info("tp_handal key",key)
  if key == 1 then
    cur_fun  = "multi_network"
  elseif key == 2 then
  elseif key == 3 then
  elseif key == 4 then
  elseif key == 5 then
  elseif key == 6 then
  elseif key == 7 then
    cur_fun = "main1"
  elseif key == 8 then
  elseif key == 9 then
    cur_fun = "main"
  end
end

local function  tp_handal(tp_device,tp_data)
  -- log.info("tp_handal",tp_data[1].x,tp_data[1].y,tp_data[1].event)
  if tp_data[1].event == 1 then
    lock_push = 0
  end
  if tp_data[1].event == 2  and   lock_push == 0 then
    if cur_fun == "main" then
      handal_main(tp_data[1].x,tp_data[1].y)
    elseif cur_fun == "main1" then
      handal_main1(tp_data[1].x,tp_data[1].y)
    elseif cur_fun == "main2" then
      handal_main2(tp_data[1].x,tp_data[1].y)
    elseif cur_fun == "tts" then
      airtts.tp_handal(tp_data[1].x,tp_data[1].y,tp_data[1].event)
    elseif cur_fun == "camera" then
      aircamera.tp_handal(tp_data[1].x,tp_data[1].y,tp_data[1].event)
    elseif cur_fun == "gps" then
      airgps.tp_handal(tp_data[1].x,tp_data[1].y,tp_data[1].event)
    elseif cur_fun == "ap" then
      airap.tp_handal(tp_data[1].x,tp_data[1].y,tp_data[1].event)
    elseif cur_fun == "sta" then
      airsta.tp_handal(tp_data[1].x,tp_data[1].y,tp_data[1].event)
    elseif cur_fun == "multi_network" then
      multi_network.tp_handal(tp_data[1].x,tp_data[1].y,tp_data[1].event)
    elseif cur_fun == "wan" then
      airwan.tp_handal(tp_data[1].x,tp_data[1].y,tp_data[1].event)
    elseif cur_fun == "lan" then
      airlan.tp_handal(tp_data[1].x,tp_data[1].y,tp_data[1].event)
    end
    lock_push = 1
  end
end


-- 画状态栏
local function draw_statusbar()
  lcd.showImage(0, 0, "/luadb/signal" .. airstatus.data.sig_stren .. ".jpg")
  lcd.showImage(64, 0, "/luadb/power" .. airstatus.data.bat_level .. ".jpg")
  lcd.showImage(128, 0, "/luadb/temp.jpg")
  lcd.showImage(192, 0, "/luadb/humidity.jpg")
  lcd.showImage(0, 448, "/luadb/Lbottom.jpg")

  if airstatus.data.weather.result then
      lcd.setFont(lcd.font_opposansm32_chinese)
      lcd.drawStr(172, 30, tostring(airstatus.data.weather.temp))
      lcd.drawStr(236, 30, tostring(airstatus.data.weather.humidity))
      lcd.showImage(256, 0, airstatus.data.weather.text)
  else
      lcd.showImage(256, 0, "/luadb/default.jpg")
  end
end


--画九宫格界面
local function draw_main()
  local i = 0
  local j = 0 
  local x,y
  local fname
  local sel = 0
  
  for i = 1,3 do
    for j = 1,3 do
      x = 64 + (i-1)*128 + 24
      y = (j-1)*106 + 13
      sel = j+(i-1)*3
      fname = "/luadb/" .. "A" .. sel .. ".jpg"
      -- log.info("fname：", fname, x,y,sel,cur_sel)
      lcd.showImage(y,x,fname)
    end
  end      
end

local function draw_main1()
  local i = 0
  local j = 0 
  local x,y
  local fname
  local sel = 0
  
  for i = 1,3 do
    for j = 1,3 do
      x = 64 + (i-1)*128 + 24
      y = (j-1)*106 + 13
      sel = j+(i-1)*3
      fname = "/luadb/" .. "B" .. sel .. ".jpg"
      -- log.info("fname：", fname, x,y,sel,cur_sel)
      lcd.showImage(y,x,fname)
    end
  end      
end

local function draw_main2()
  local i = 0
  local j = 0 
  local x,y
  local fname
  local sel = 0
  
  for i = 1,3 do
    for j = 1,3 do
      x = 64 + (i-1)*128 + 24
      y = (j-1)*106 + 13
      sel = j+(i-1)*3
      fname = "/luadb/" .. "C" .. sel .. ".jpg"
      -- log.info("fname：", fname, x,y,sel,cur_sel)
      lcd.showImage(y,x,fname)
    end
  end      
end

local function draw_pic()
  lcd.showImage(0,64,"/luadb/P1.jpg")
end

local function draw_tts()
  if  airtts.run()   then
    cur_fun = "main"
  end
end

local function draw_camera()

  if  aircamera.run()   then
    cur_fun = "main"
  end
end


local function draw_gps()
  aircamera.close()
  if  airgps.run()   then
    cur_fun = "main"
  end
end

local function draw_ap()
  if  airap.run()   then
    cur_fun = "main"
  end
end

local function draw_sta()
  if  airsta.run()   then
    cur_fun = "main"
  end
end

local function draw_wan()
  if  airwan.run()   then
    cur_fun = "main"
  end
end

local function draw_lan()
  if  airlan.run()   then
    cur_fun = "main"
  end
end

local function draw_multi_network()
  if  multi_network.run()   then
    cur_fun = "main"
  end
end

local function draw()
  if cur_fun == "camshow" then
    return
  end

  lcd.clear(_G.bkcolor)    
  
  draw_statusbar()
  
  if cur_fun == "main" then
    draw_main()
  elseif cur_fun == "main1" then
    draw_main1()
  elseif cur_fun == "main2" then
    draw_main2()
  elseif cur_fun == "tts" then
    draw_tts()
  elseif cur_fun  == "camera" then
    draw_camera()
  elseif cur_fun == "gps" then
    draw_gps()
  elseif cur_fun == "ap" then
    draw_ap()
  elseif cur_fun == "sta" then
    draw_sta()
  elseif cur_fun == "wan" then
    draw_wan()
  elseif cur_fun == "lan" then
    draw_lan()
  elseif cur_fun == "multi_network" then
    draw_multi_network()    
  end
  
  lcd.showImage(0,448,"/luadb/Lbottom.jpg")
  lcd.flush()
end

local function update_airstatus()
  airstatus.get_sig_strength()
  airstatus.get_weather()
end

wdtInit()


function ip_ready_handle(ip, adapter)
  log.info("ip_ready_handle",ip, adapter)
  if adapter == socket.LWIP_GP then
    sysplus.taskInitEx(update_airstatus, "update_airstatus")
  end
end

local function UITask()
    sys.wait(1000)
    log.info("合宙 8000 startup v1")
    -- aircamera.init()
    airlcd.lcd_init("AirLCD_1001")
    sys.subscribe("TP",tp_handal)
    while 1 do
      update()
      draw()
      if ((sid % 10) == 0) then
        log.info("sid: ", sid, cur_fun)
      end

      sid = sid + 1
      sys.wait(10)
    end

end
sys.subscribe("IP_READY", ip_ready_handle)
sysplus.taskInitEx(UITask, taskName)

-- 当前是给camera 表的变量赋值让camera 退出。 未来可以让 UI task 发消息给camera 任务，让camera 任务关闭摄像头，释放LCD

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
