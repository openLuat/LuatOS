PROJECT = "startupv13"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
sys = require("sys")

local airlcd = require "airlcd"
local aircam = require "camera8000_simple"
local airrus = require "russia"
local airstatus = require "statusbar"
local airtestwlan = require "test_wlan"
local airbuzzer = require "airbuzzer"

local key = ""      

local powertick = 0
local boottick = 0
local SWITCH_LONG_TIME = 500
local ROT_LONG_TIME = 300
local QUIT_LONG_TIME = 3000

local sid = 0

-- 按键事件类型：
-- "switch": 短按开机键切换菜单；  
-- "enter"： 长按开机键进入功能菜单或者退出功能菜单

-- 当前功能界面
-- "main":      九宫格主界面
-- "picshow":   图片显示
-- "camshow":   摄像头预览
-- "russia":    俄罗斯方块
-- "LAN":       以太网 LAN
-- "WAN":       以太网 WAN
-- "selftest":  硬件自检
-- "modbusTCP": modbus-TCP
-- "modbusRTU": modbus-RTU
-- "CAN":       CAN 测试
local cur_fun = "main"
local cur_sel = 0

local funlist = {
"picshow", "camshow","russia",
"LAN", "WAN","selftest",
"modbusTCP","modbusRTU","CAN"
}

local bkcolor = lcd.rgb565(99, 180, 245,false)

local function wdtInit()
-- 添加硬狗防止程序卡死
  if wdt then
    wdt.init(9000) -- 初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000) -- 3s喂一次狗
  end
end

local function StartCam()
  airlcd.lcd_init("AirLCD_43_01")
  sys.taskInit(aircam.start_cam)
  aircam.isquit = false
end

local function QuitCam()
  aircam.isquit  = true
  sys.wait(300)
  airlcd.lcd_init("AirLCD_43_01")
end

local function keypressed()
  if key == "" then
    return
  end
  
  log.info("keypressed : ", key, cur_fun)

  if cur_fun == "russia" then
      if key == "quit" then
          cur_fun = "main"
      else
          airrus.keypressed(key)
      end
      return
  end

  if key == "switch" then
    if cur_fun == "main" then
      cur_sel = cur_sel + 1
      if cur_sel > 9 then
        cur_sel = 1
      end
      log.info("select num:", cur_sel)
    end
    key = ""
  elseif key == "enter" or key == "quit" then
    if cur_fun == "main" then
      cur_fun = funlist[cur_sel]
      if cur_fun == "camshow" then
        StartCam()
      elseif cur_fun == "russia" then
        airrus.initrus()
      elseif cur_fun == "LAN" then
        
      elseif cur_fun == "WAN" then
        sys.taskInit(airtestwlan.test_wan)
      elseif cur_fun == "selftest" then

      elseif cur_fun == "modbusTCP" then

      elseif cur_fun == "modbusRTU" then

      elseif cur_fun == "CAN" then
      end
    else
      cur_fun = "main"
      if not aircam.isquit then
        QuitCam()
      end
    end
    key = ""
  end
end

local function PowerInterrupt()
    local s1 = 0
    local s2 = 0
    local v = gpio.get(gpio.PWR_KEY)
    log.info("pwrkey：", v, powertick)
    if v == 0 then
      powertick = mcu.ticks()
      airbuzzer.start_buzzer()
    elseif  v == 1 then
      s1 = mcu.ticks()
      airbuzzer.stop_buzzer()
      local s2 = s1 - powertick
      if s2 < SWITCH_LONG_TIME then
          key = "switch"
          if cur_fun == "russia" then
            key = "left"
          end
      elseif s2 < QUIT_LONG_TIME then
          key = "enter"
          if cur_fun == "russia" then
            key = "fast"
          end
      else
          key = "quit"
      end
      powertick = s1
      --if cur_fun == "russia" then
      --  airrus.keypressed(key)
      --end
      log.info("power key：", v, powertick,s2,key)
    end
end

local function BootInterrupt()
    local v = gpio.get(0)
    log.info("gpio0：", v, boottick)
    if v == 1 then
      boottick = mcu.ticks()
    elseif  v == 0 then
      s1 = mcu.ticks()
      local s2 = s1 - boottick
      if s2 < ROT_LONG_TIME then
        key = "right"
      else
        key = "up"
      end
      boottick = s1
      --if cur_fun == "russia" then
      --  airrus.keypressed(key)
      --end
      log.info("gpio0 key：", v, boottick,s2,key)
    end
end

local function KeyInit()
    if not gpio.PWR_KEY then
      log.info("bsp not support powerkey")
      return
    end
  
    gpio.setup(gpio.PWR_KEY, PowerInterrupt, gpio.PULLUP, gpio.BOTH)
    gpio.setup(0, BootInterrupt, gpio.PULLDOWN, gpio.BOTH)
end

local function update()
  if cur_fun == "russia" then
    airrus.updaterus()
  end

  if not airstatus.data.weather.result and ((sid % 50) == 0)  then
    airstatus.get_sig_strength()
    airstatus.get_weather()
  end
  if airstatus.data.bat_level == 0 then
    airstatus.get_bat_level()
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

local function draw_wan()
  lcd.showImage(0, 65, "/luadb/function5.jpg")
end

local function draw_lan()
  lcd.showImage(0, 65, "/luadb/function4.jpg")
end

local function draw_selftest()
  lcd.showImage(0, 65, "/luadb/choose1.jpg")
  lcd.showImage(0, 194, "/luadb/choose2.jpg")
  lcd.showImage(0, 322, "/luadb/choose3.jpg")
end

local function draw_modbusRTU()
  lcd.showImage(0, 65, "/luadb/final_function.jpg")
end

local function draw_modbusTCP()
  lcd.showImage(0, 65, "/luadb/final_function.jpg")
end

local function draw_CAN()
  lcd.showImage(0, 65, "/luadb/final_function.jpg")
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
      if sel == cur_sel then
        fname = "/luadb/" .. "D" .. sel .. ".jpg"
      else
        fname = "/luadb/" .. "L" .. sel .. ".jpg"
      end
      -- log.info("fname：", fname, x,y,sel,cur_sel)
      lcd.showImage(y,x,fname)
    end
  end      
end

local function draw_pic()
  lcd.showImage(0,64,"/luadb/P1.jpg")
end

local function draw()
  if cur_fun == "camshow" then
    return
  end

  lcd.clear(bkcolor)    
  
  draw_statusbar()
  
  if cur_fun == "main" then
    draw_main()
  elseif cur_fun == "picshow" then
    draw_pic()
  elseif cur_fun == "russia" then
    airrus.drawrus()
  elseif cur_fun == "LAN" then
    draw_lan()
  elseif cur_fun == "WAN" then
    draw_wan()
  elseif cur_fun == "selftest" then
    draw_selftest()
  elseif cur_fun == "modbusTCP" then
    draw_modbusTCP()
  elseif cur_fun == "modbusRTU" then
    draw_modbusRTU()
  elseif cur_fun == "CAN" then
    draw_CAN()
end
  
  lcd.showImage(0,448,"/luadb/Lbottom.jpg")
  lcd.flush()
end

wdtInit()

local function UITask()
    airlcd.lcd_init("AirLCD_1001")

    KeyInit()
    log.info("合宙 8000 startup v13:" .. sid)

    while 1 do
        keypressed()
        
        update()

        draw()

        if ((sid % 10) == 0) then
          log.info("sid: ", sid, cur_fun)
        end

        sid = sid + 1
        sys.wait(10)
    end

end

sys.taskInit(UITask)
-- 当前是给camera 表的变量赋值让camera 退出。 未来可以让 UI task 发消息给camera 任务，让camera 任务关闭摄像头，释放LCD

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
