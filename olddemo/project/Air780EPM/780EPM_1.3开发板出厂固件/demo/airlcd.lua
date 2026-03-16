
local airLCD = {}

function airLCD.lcd_init(sn)

  if sn ~= "AirLCD_0001" then
    return
  end

  pm.ioVol(pm.IOVOL_ALL_GPIO, 3000)--所有IO电平开到3V，电平匹配
  gpio.setup(29, 1) -- GPIO29 打开给lcd电源供电

  local rtos_bsp = rtos.bsp()
  -- local chip_type = hmeta.chip()
  -- 根据不同的BSP返回不同的值
  -- 根据不同的BSP返回不同的值
  -- spi_id,pin_reset,pin_dc,pin_cs,bl
  function lcd_pin()
      return lcd.HWID_0, 36, 0xff, 0xff, 160 -- 注意:EC718P有硬件lcd驱动接口, 无需使用spi,当然spi驱动也支持
      -- return 0,1,10,8,22
  end

  local spi_id, pin_reset, pin_dc, pin_cs, bl = lcd_pin()
  if spi_id ~= lcd.HWID_0 then
    spi_lcd = spi.deviceSetup(spi_id, pin_cs, 0, 0, 8, 20 * 1000 * 1000, spi.MSB, 1, 0)
    port = "device"
  else
    port = spi_id
  end



  lcd.init("st7796",{port = port,pin_dc = pin_dc, pin_pwr = bl, pin_rst = pin_reset,direction = 0,w = 320,h = 480,xoffset = 0,yoffset = 0},spi_lcd)
	


  lcd.setupBuff(nil, true) -- 使用sys内存, 只需要选一种
  lcd.autoFlush(false)
  log.info("tp", "tp init")
  local function tp_callBack(tp_device,tp_data)
      sys.publish("TP",tp_device,tp_data)
      log.info("TP",tp_data[1].x,tp_data[1].y,tp_data[1].event)
  end

  -- local softI2C = i2c.createSoft(20, 21, 2) -- SCL, SDA
  -- local softI2C = i2c.createSoft(28, 26, 1) -- SCL, SDA
  -- tp_device = tp.init("jd9261t_inited",{port=softI2C, pin_rst = 27,pin_int = gpio.CHG_DET,w = width,h = height,int_type=gpio.FALLING, refresh_rate = 60},tp_callBack)

  -- tp_device = tp.init("jd9261t_inited",{port=0, pin_rst = 20,pin_int = gpio.WAKEUP0,w = width,h = height,int_type=gpio.FALLING, refresh_rate = 60},tp_callBack)
  local i2c_id = 0
  i2c.setup(i2c_id, i2c.SLOW)
  tp_device = tp.init("gt911",{port=i2c_id, pin_rst = 20,pin_int = gpio.WAKEUP0,},tp_callBack)

  -- gpio.setup(gpio.WAKEUP0, function ()
  --     log.info("tp", "tp interrupt")
  -- end, gpio.PULLUP, gpio.FALLING)
  if tp_device then
      print(tp_device)
      sys.taskInit(function()
          while 1 do 
              local result, tp_device, tp_data = sys.waitUntil("TP")
              if result then
                  lcd.drawPoint(tp_data[1].x, tp_data[1].y, 0xF800)
                  lcd.flush()
              end
          end
      end)
  end

end

return airLCD
