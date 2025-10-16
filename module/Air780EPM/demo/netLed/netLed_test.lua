--[[
@module  netLed_test
@summary netLed_test测试功能模块
@version 1.0
@date    2025.10.15
@author  马亚丹
@usage
本demo演示的功能为：使用Air780EPM，1.3开发板，GPIO27,即LTE（板子上的NET）指示灯演示网络灯的亮灭显示。
工作状态说明：
"NULL"：      功能关闭状态
"FLYMODE"     飞行模式
"SIMERR"      未检测到SIM卡或者SIM卡锁pin码等SIM卡异常
"IDLE"        未注册GPRS网络
"GPRS"        已附着GPRS数据网络
"SCK"         socket已连接上后台

各种工作状态下配置的点亮、熄灭时长(单位毫秒)，默认值：
FLYMODE = {0,0xFFFF},  --常灭
SIMERR = {300,5700},  --亮300毫秒,灭5700毫秒
IDLE = {300,3700},  --亮300毫秒,灭3700毫秒
GPRS = {300,700},  --亮300毫秒,灭700毫秒
SCK = {100,100},  --亮100毫秒,灭100毫秒



核心逻辑：
1.演示lte指示灯，初始化lte,点亮指示灯
2.演示led指示灯，初始化led,点亮指示灯
3.初始化led,演示飞行模式，卡状态错误模式下led指示灯亮灭情况,以及呼吸灯演示

]]
local netLed = require("netLed")

---------步骤1：演示lte指示灯----------
local function netLte_test()
    --等待5s,网络稳定后点亮
    sys.wait(5000)
    log.info("初始化lte灯")
    --GPIO27是Air780EPM ,1.3版本开发板的NET灯控制脚,此处演示用不到ledpin，写个不存在的GPIO
    netLed.setup(true, 0, 27)
    local lteCtrl = gpio.setup(27, 1, gpio.PULLUP)
    log.info("lte网络状态灯点亮")
    netLed.setState()
    netLed.taskLte(lteCtrl)
end
sys.taskInit(netLte_test)

---------步骤2：演示led指示灯----------
local function netLed_test1()
    --挂起20秒再运行，等前面的运行完
    sys.wait(20000)
    log.info("初始化led灯")
    -- 初始化Led灯 ，打开网络灯功能，GPIO27是Air780EPM ,1.3版本开发板的NET灯控制脚，这里把NET灯做普通led灯模拟使用，设定后按初始的IDLE工作状态的默认配置运行
    netLed.setup(true, 27)
    local LedCtrl = gpio.setup(27, 1, gpio.PULLUP)
    log.info("led网络状态灯点亮")
    netLed.setState()
    netLed.taskLed(LedCtrl)
end
sys.taskInit(netLed_test1)


---------步骤3：演示飞行模式，卡状态错误模式下led指示灯亮灭情况以及呼吸灯演示----------
--自定义“飞行模式”的LED闪烁时长：亮1000ms，灭500ms
netLed.setBlinkTime("FLYMODE")

--自定义“SIM卡错误”的LED闪烁时长：亮200ms，灭300ms
--如果开机时没有插卡，会触发这个模式，
--如果开机时卡状态正常会正常运行步骤2的程序
netLed.setBlinkTime("SIMERR", 100, 200)


--创建网络灯控制任务
local function netLed_test()
    --先挂起一段时间，等前面的演示完
    sys.wait(40000)
    log.info("初始化led灯")
    netLed.setup(true, 27)
    log.info("获取当前工作状态")
    --到这里网络已经稳定，工作状态变为GPRS
    netLed.setState()

    log.info("触发飞行")
    -- 发布飞行模式事件，工作状态切换为FLYMODE状态
    sys.publish("FLYMODE", true)
    --更新LED灯的工作状态
    netLed.setState()

    sys.wait(20000)
    log.info("关闭飞行模式")
    -- 关闭飞行模式
    sys.publish("FLYMODE", false)
    --更新LED灯的工作状态
    netLed.setState()

    --等待1秒确保关闭飞行模式后切换为“呼吸灯”模式
    sys.wait(1000)
    log.info("呼吸灯演示")
    local breatheLed = gpio.setup(27, 1, gpio.PULLUP)    
    local n = 0
    while n < 10 do
        -- 呼吸灯效果（渐亮→保持→渐暗→保持循环），演示循环10次，可按需设定
        netLed.setupBreateLed(breatheLed)
        n = n + 1
        if n == 10 then
            log.info("呼吸灯演示结束")
        end
    end
    --呼吸灯演示结束，按当前工作状态，即GPRS工作状态的默认配置闪亮
    --更新LED灯的工作状态
    netLed.setState()
end
sys.taskInit(netLed_test)
