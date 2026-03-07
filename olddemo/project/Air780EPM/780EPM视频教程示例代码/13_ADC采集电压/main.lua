-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "ADC"
VERSION = "1.0.0"

-- sys库是标配
sys = require("sys")
--=============================================================
local function MY_ADC()
-- 读取CPU温度, 单位为0.001摄氏度, 是内部温度, 非环境温度
    while 1 do
    sys.wait(1000)
    adc.open(adc.CH_CPU)
    local temp = adc.get(adc.CH_CPU)
    log.info("CPU温度=",temp/1000)
    --adc.close(adc.CH_CPU)
-- adc.CH_CPU,CPU内部温度的通道id,内部通道，直接获取，不占用ADC 0-3，不外接任何电路
-- 读取VBAT供电电压, 单位为mV
--=============================================================
    sys.wait(1000)
    adc.open(adc.CH_VBAT)
    local vbat = adc.get(adc.CH_VBAT)
    log.info("VBAT供电电压",vbat/1000)
    --adc.close(adc.CH_VBAT)
-- adc.CH_VBAT,VBAT供电电压的通道id,内部通道，直接获取，不占用ADC 0-3，不外接任何电路
-- adc.CH_CPU 和 adc_CH_VBAT 在做读取动作之前，不需要像 ADC 0-3通道一样先打开adc.setRange(range)函数
--=============================================================
    sys.wait(1000)
--修改IO电平，都可以通过LuatOS软件设置为1.8V/2.8V/3.0V/3.3V
    pm.ioVol(pm.IOVOL_ALL_GPIO, 3300) 
-- 设置ADC引脚的测量范围0-3.6V，这种方式被测电压不可经过外部电阻分压后再挂在ADC上；
    adc.setRange(adc.ADC_RANGE_MAX)
-- 打开adc通道0,并读取
    adc.open(0) 
    local ADC0=adc.get(0)
    log.info("adc0=", ADC0,"mV") -- 返回电压值；
--=============================================================
    end
end
--=============================================================
sys.taskInit(MY_ADC)
--=============================================================
-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
