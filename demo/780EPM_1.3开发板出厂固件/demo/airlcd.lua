
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
  local function lcd_pin()
    local rtos_bsp = rtos.bsp()
    if string.find(rtos_bsp, "780EPM") then
        return lcd.HWID_0, 36, 0xff, 0xff, 25 -- 注意:EC718P有硬件lcd驱动接口, 无需使用spi,当然spi驱动也支持
    else
        log.info("main", "没找到合适的cat.1芯片", rtos_bsp)
        return
    end
  end

  local spi_id, pin_reset, pin_dc, pin_cs, bl = lcd_pin()
  if spi_id ~= lcd.HWID_0 then
    spi_lcd = spi.deviceSetup(spi_id, pin_cs, 0, 0, 8, 20 * 1000 * 1000, spi.MSB, 1, 0)
    port = "device"
  else
    port = spi_id
  end

  lcd.init("st7796", {
    port = port,
    pin_dc = pin_dc,
    pin_pwr = bl,
    pin_rst = pin_reset,
    direction = 0,
    -- direction0 = 0x00,
    w = 320,
    h = 480,
    xoffset = 0,
    yoffset = 0,
    sleepcmd = 0x10,
    wakecmd = 0x11,
  })

  lcd.setupBuff(nil, true) -- 使用sys内存, 只需要选一种
  lcd.autoFlush(false)
end

return airLCD
