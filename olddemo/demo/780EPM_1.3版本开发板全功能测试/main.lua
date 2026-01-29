PROJECT = "780EPM_development_board"
VERSION = "1.0.3"

sys = require("sys")
log.style(1)


 pm.ioVol(pm.IOVOL_ALL_GPIO, 3000)--所有IO电平开到3V，适配camera
--  mcu.hardfault(0)    --死机后停机，一般用于调试状态
--用到哪个就开哪个，如果lcd和camera同时用到，只用开camera就好

--  require"lcd7796"--只测试LCD

--  require"camera780epm"--LCD和camera一起测试，默认为GC032A 30W像素，也可以改成bf30a2 8w像素，打开对应注释即可

-- require"modbus780epm"--开发板485接口测试，接的uart1

-- require"pwm780epm"--开发板蜂鸣器(pwm驱动)测试

-- require "loopback"--开发板uart2和uart3回环测试，测试时需要短接uart2和uart3

-- require"adc780epm"--开发板adc通道测试

-- require "gpio780epm"--开发板gpio全测试


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
