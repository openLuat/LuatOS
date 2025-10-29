--[[
@module  Led_test
@summary Led_test测试功能模块
@version 1.0
@date    2025.10.15
@author  马亚丹
@usage
本demo演示的功能为:使用Air780EPM，1.3开发板，GPIO27,即LTE(板子上的NET）指示灯模拟网络灯的亮灭显示。

工作状态说明，优先级顺序(1-5表示从高到低），高优先级状态会直接覆盖低优先级状态
1. "FLYMODE"     飞行模式
2. "SIMERR"      未检测到SIM卡或者SIM卡锁pin码等SIM卡异常
3. "SCK"         socket已连接上后台
4. "GPRS"        已附着GPRS数据网络
5. "IDLE"        未注册GPRS网络
"NULL":功能关闭状态

各种工作状态下配置的点亮、熄灭时长(单位毫秒)，默认值:
NULL = { 0, 0xFFFF }, --常灭
FLYMODE = { 0, 0xFFFF }, --常灭
SIMERR = { 300, 5700 }, --亮300毫秒,灭5700毫秒
IDLE = { 300, 3700 }, --亮300毫秒,灭3700毫秒
GPRS = { 300, 700 },  --亮300毫秒,灭700毫秒
SCK = { 100, 100 },   --亮100毫秒,灭100毫秒



核心逻辑:

1.自定义LED灯不同状态的闪烁时间
2.初始化LED,打开LED网络灯功能；
3.LED灯状态模拟，通过sys.publish("工作状态", 状态)：手动模拟状态触发，控制 LED灯的亮灭状态
4.关闭常规LED灯功能（避免冲突）,演示呼吸灯效果


]]
-- 网络状态指示灯演示示例
-- 注意:需在支持gpio和sys库的环境中运行(如嵌入式Lua开发板）

-- 引入必要模块
local netLed = require("netLed")


-- 初始化网络指示灯引脚(GPIO27，根据硬件调整）
-- 初始低电平(灭）
local ledPin = gpio.setup(27, 0, gpio.PULLUP)

--netLed.setup(true, 27)

-- 自定义LED灯不同状态的闪烁时间(增强区分度）
-- SIM错误:300ms亮/1700ms灭(2秒周期）
netLed.setBlinkTime("SIMERR", 300, 1700) 
-- 未注册:500ms亮/2500ms灭(3秒周期）
netLed.setBlinkTime("IDLE", 500, 2500) 
-- GPRS附着:200ms亮/200ms灭(400ms周期，中速闪）  
netLed.setBlinkTime("GPRS", 200, 200)
-- Socket连接:100ms亮/50ms灭(150ms周期，快速闪）    
netLed.setBlinkTime("SCK", 100, 50)      

-- 主任务:初始化指示灯并模拟网络状态变化
local function ledtest() 
  while true do
    -- 开启网络灯功能，网络灯用GPIO27，关闭LTE灯(LTE引脚设为空不处理）
    netLed.setup(true, 27)
    

    -- 状态1:初始状态(未注册网络，IDLE）
    log.info("LED状态", "未注册网络(IDLE):500ms亮/2500ms灭")
    -- 关闭飞行模式
    sys.publish("FLYMODE", false) 
    -- SIM正常
    sys.publish("SIM_IND", "RDY") 
    -- 未附着GPRS(触发IDLE状态）
    sys.publish("IP_LOSE") 
    -- 无Socket连接
    sys.publish("SOCKET_ACTIVE", false) 
    -- 维持12秒(4个3秒周期）
    sys.wait(12000)          
    

    -- 状态2:SIM卡错误(SIMERR）
    log.info("LED状态", "SIM卡错误(SIMERR):300ms亮/1700ms灭")
    -- SIM异常(触发SIMERR状态）
    sys.publish("SIM_IND", "ERROR")
    -- 维持8秒(4个2秒周期）
    sys.wait(8000)                  

    -- 状态3:已附着GPRS(GPRS）
    log.info("LED状态", "已附着GPRS:200ms亮/200ms灭(中速闪）")
    -- 恢复SIM正常，覆盖"ERROR"
    sys.publish("SIM_IND", "RDY")                -- 
    -- 发布IP_READY事件，明确触发GPRS状态(参数格式正确）
    sys.publish("IP_READY", "192.168.1.1", true)
    -- 确保无Socket连接(避免干扰）
    sys.publish("SOCKET_ACTIVE", false)
    -- 维持8秒(20个400ms周期）
    sys.wait(8000)                               


    -- 状态4:Socket已连接(SCK）
    log.info("LED状态", "Socket连接(SCK):100ms亮/50ms灭(快速闪）")
    -- 有Socket连接(触发SCK状态）
    sys.publish("SOCKET_ACTIVE", true)
    -- 维持6秒(40个150ms周期）
    sys.wait(6000)                     



    -- 状态5:飞行模式(FLYMODE，默认常灭）
    log.info("LED状态", "飞行模式(FLYMODE):常灭")
    -- 开启飞行模式(触发FLYMODE状态）
    sys.publish("FLYMODE", true) 
    -- 维持5秒
    sys.wait(5000)               

    -- 状态6:呼吸灯模式(独占引脚）
    log.info("LED状态", "呼吸灯模式:平滑渐变亮灭")
    -- 关闭常规LED功能(释放引脚,避免冲突）
    netLed.setup(false, 27) 
    local n = 0
    --呼吸灯循环10次
    while n < 10 do
      -- 传入Led灯引脚
      netLed.setupBreateLed(ledPin)
      -- 呼吸灯循环间隔
      sys.wait(20)
      n = n + 1
    end
  end
end
sys.taskInit(ledtest)
