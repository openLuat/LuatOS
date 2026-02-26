local expm = require "expm"


local function set_pm_lowpower()    

    -- 配置最低功耗模式为低功耗模式,根据自己的项目需求决定是否需要进入飞行模式
    -- 如果不需要进入飞行模式，使用expm.set(expm.LOWPOWER)
    -- 如果需要进入飞行模式，使用expm.set(expm.LOWPOWER, {[expm.FLYMODE] = expm.OPEN})
    -- 在vbat供电3.8v，低功耗待机状态下，进入飞行模式，可以减少1mA到1.2mA的功耗（和天线性能以及网络环境有关系，以自己的实际硬件+实际网络环境测试数据为准）
    -- 注意：一旦进入飞行模式，意味着无法使用4G网络
    -- 使用合宙核心板测试的低功耗模式功耗数据，在vbat供电3.8v状态下
    -- 飞行模式+低功耗：46uA左右
    -- 低功耗：1mA到1.2mA左右（和天线性能以及网络环境有关系，以自己的实际硬件+实际网络环境测试数据为准）
    expm.set(expm.LOWPOWER)
    -- expm.set(expm.LOWPOWER, {[expm.FLYMODE] = expm.OPEN})

end

sys.subscribe("PM_SET_LOWPOWER", set_pm_lowpower)

-- 如果项目启动之后，最低功耗模式一直配置为expm.LOWPOWER模式，则可以直接打开下面这一行代码，相当于开机初始化时，就配置最低功耗模式为expm.LOWPOWER
--
-- 如果项目不需要初始化配置，或者在项目运行过程中，在不同的功耗模式之间手动切换，
-- 则可以根据需求，注释掉下面的一行代码，根据自己的业务逻辑，在合适的位置sys.publish("PM_SET_LOWPOWER")即可
sys.publish("PM_SET_LOWPOWER")