--[[
@module  drv_psm
@summary PSM+模式pm.power(pm.WORK_MODE, 3)驱动配置功能模块
@version 1.0
@date    2026.02.12
@author  马梦阳
@usage
本文件为PSM+模式pm.power(pm.WORK_MODE, 3)驱动配置功能模块，提供了PSM+模式的配置模板，包括以下几点：
1、在进入PSM+模式前，根据自己的实际项目需求，配置进入PSM+模式后的中断唤醒方式；详情参考set_psm_interrupt_wakeup()实现
2、在进入PSM+模式前，根据自己的实际项目需求，配置一些必要的功能项；可以在满足项目功能需求的背景下，让功耗降到最低；详情参考set_psm_func_item()实现
3、配置最低功耗模式为PSM+模式；pm.power(pm.WORK_MODE, 3)


Air780EGP/EGG模组内部包含有GNSS和Gsensor，Air780EGH模组内部只包含有GNSS，不包含Gsensor；
GPIO23作为GNSS备电电源开关和Gsensor电源开关，默认状态下为高电平；
在低功耗模式和PSM+模式下，GNSS备电开启和Gsensor开启后，二者的功耗总和表现为200uA左右，客户应根据实际需求进行配置；
在PSM+模式示例代码中，默认配置GPIO23为输入下拉的方式来演示PSM+模式的功耗表现；


本文件的对外接口只有1个：
1、sys.subscribe("DRV_SET_PSM", set_drv_psm)：订阅"DRV_SET_PSM"消息；
   其他应用模块如果需要配置PSM+模式，直接sys.publish("DRV_SET_PSM")这个消息即可；
]]


-- 获取当前使用的模组型号
local module = hmeta.model()

log.info("drv_psm", "当前使用的模组是：", module)


-- Air780EGG/EGP模组WAKEUP2引脚内部用作GSensor中断信号，用户需要手动配置成中断方式才能实现GSensor的中断唤醒功能，除此之外不可作为其他功能使用
-- Air780EPM/EHM/EHU/EHN/EHV/EGH模组WAKEUP2引脚并未被模组内部用作GSensor中断信号，可以作为普通中断功能
-- 
-- Air780EHV模组WAKEUP3引脚内部用作GPIO20功能，用于控制Audio Codec芯片ES8311的供电使能开关，除此之外不可作为其他功能
-- Air780EPM/EHM/EHU/EHN/EGH/EGP/EGG模组WAKEUP3引脚并未被模组内部占用，可以作为普通中断功能
-- 
-- Air780EGH/EGP/EGG模组WAKEUP4引脚内部用作GPIO21功能，用于控制GNSS定位芯片的供电使能开关，除此之外不可作为其他功能
-- Air780EPM/EHM/EHU/EHN/EHV模组WAKEUP4引脚并未被模组内部占用，可以作为普通中断功能
-- 
-- Air780EPM/EHM模组没有引出此引脚，所以无法配置CHG_DET（WAKEUP6）功能
-- Air780EHU/EHN/EHV/EGH/EGP/EGG模组支持CHG_DET（WAKEUP6）功能，可以作为普通中断功能
-- 
-- 在PSM+模式下，唤醒后会直接重启软件系统，并不会执行此处的中断处理函数
local function psm_wakeup_func(level, id)
    local tag =
    {
        [gpio.PWR_KEY] = "PWR_KEY",
        [gpio.CHG_DET] = "CHG_DET",
        [gpio.WAKEUP0] = "WAKEUP0",
        [gpio.WAKEUP1] = "WAKEUP1",
        [gpio.WAKEUP2] = "WAKEUP2",
        [gpio.WAKEUP3] = "WAKEUP3",
        [gpio.WAKEUP4] = "WAKEUP4",
        [gpio.WAKEUP5] = "WAKEUP5",
    }

    -- 注意：此处的level电平并不表示触发中断的边沿电平
    -- 而是在触发中断后，某个时间点的电平状态
    -- 可能和触发中断的边沿电平状态一致，也可能不一致
    log.info("psm_wakeup_func", tag[id], level)
end


-- 在进入PSM+模式前，根据自己的实际项目需求，配置PSM+模式下的中断唤醒方式
-- 
-- PSM+模式下，Air780EPM/EHM支持以下几种类型的中断唤醒方式：
-- 1、深度休眠定时器(dtimer)
-- 2、PWR_KEY引脚中断
-- 3、WAKEUP0、WAKEUP2、WAKEUP3、WAKEUP4、WAKEUP5引脚中断
-- 4、VBUS(内部分压到WAKEUP1)引脚中断
-- 5、UART1_RXD引脚中断(可以将UART1配置为支持的任意波特率)
-- 
-- Air780EHM/EHU/EHN支持以下几种类型的中断唤醒方式：
-- 1、深度休眠定时器(dtimer)
-- 2、PWR_KEY引脚中断
-- 3、CHG_DET(WAKEUP6)引脚中断
-- 4、WAKEUP0、WAKEUP2、WAKEUP3、WAKEUP4、WAKEUP5引脚中断
-- 5、VBUS(内部分压到WAKEUP1)引脚中断
-- 6、UART1_RXD引脚中断(可以将UART1配置为支持的任意波特率)
-- 
-- Air780EHV支持以下几种类型的中断唤醒方式：
-- 1、深度休眠定时器(dtimer)
-- 2、PWR_KEY引脚中断
-- 3、CHG_DET(WAKEUP6)引脚中断
-- 4、WAKEUP0、WAKEUP2、WAKEUP4、WAKEUP5引脚中断
-- 5、VBUS(内部分压到WAKEUP1)引脚中断
-- 6、UART1_RXD引脚中断(可以将UART1配置为支持的任意波特率)
-- 
-- Air780EGH支持以下几种类型的中断唤醒方式：
-- 1、深度休眠定时器(dtimer)
-- 2、PWR_KEY引脚中断
-- 3、CHG_DET(WAKEUP6)引脚中断
-- 4、WAKEUP0、WAKEUP2、WAKEUP3、WAKEUP5引脚中断
-- 5、VBUS(内部分压到WAKEUP1)引脚中断
-- 6、UART1_RXD引脚中断(可以将UART1配置为支持的任意波特率)
-- 
-- Air780EGP/EGG支持以下几种类型的中断唤醒方式：
-- 1、深度休眠定时器(dtimer)
-- 2、PWR_KEY引脚中断
-- 3、CHG_DET(WAKEUP6)引脚中断
-- 4、WAKEUP0、WAKEUP3、WAKEUP4、WAKEUP5引脚中断
-- 5、VBUS(内部分压到WAKEUP1)引脚中断
-- 6、UART1_RXD引脚中断(可以将UART1配置为支持的任意波特率)
-- 
-- 特别注意：从PSM+模式唤醒后，软件系统会直接重启，重启过程中AGPIO的电平状态不会发生改变！！！！！！
-- 特别注意：当使用杜邦线短接/断开测试时，因为抖动因素，所以实际情况肯定会存在高低电平频繁跳变的情况！！！！！！
--          所以测试表现和实际的短接/断开动作并不完全相符，这种测试方法仅仅简单验证一下功能即可！！！！！！
--          最终自己设计的硬件产品并不会出现此问题
-- 特别注意：当配置引脚唤醒功能时，基于使用的硬件，配置之后，可能会增加系统功耗；本函数中基于Air780EXX系列每个模组的核心板给出了每项配置对功耗的影响数据
--          当使用自己的硬件测试时，以自己的硬件实测数据为准；Air780EXX系列每个模组的核心板的实测数据可以用来参考
local function set_psm_interrupt_wakeup()
    -- 配置深度休眠定时器唤醒
    -- 定时器时长有讲究，此处的时长不要小于80秒
    -- 因为如果满足进入PSM+模式的条件，内核固件最长需要75秒肯定可以进入PSM+模式
    -- 如果此处设置的时间过短，在某些情况下，有可能还没有真正进入PSM+模式，就出现了深度休眠定时器超时
    -- 此情况下的唤醒重启，pm.lastReson()的返回值为1,4,0,0，仅关注第一个返回值1即可
    -- pm.dtimerStart(0, 60*60*1000)    -- Air780EXX系列每个模组的核心板测试，没有增加功耗


    -- 配置PWR_KEY引脚下降沿、上升沿、双边沿中断唤醒（根据硬件设计原理以及项目需求，配置防抖之后，从中断唤醒方式中六选一）
    -- 防抖配置：200ms时长防抖，冷却模式（根据项目需求可以修改）
    -- 此处的代码基于合宙Air780EXX系列每个模组的核心板测试：
    --     由于PWR_KEY引脚内部已经拉高至VBAT电压，因此只能配置为gpio.PULLUP，不能配置为gpio.PULLDOWN
    --     当配置为gpio.PULLUP时，按下开机键产生下降沿，弹起开机键产生上升沿
    -- 在实际的项目中，可以根据自己的硬件设计原理以及项目需求，对此处的代码做适当修改
    -- 此情况下的唤醒重启，pm.lastReson()的返回值为5,4,0,256，仅关注第一个返回值5即可
    -- 
    -- 特别注意：gpio.debounce接口设置的防抖功能，在不同功耗模式下表现不同：
    --          1、在常规模式0下，防抖功能有效，可以参考API详细说明，配置自己需要的防抖模式，实现“有效避免误触发”的效果
    --          2、在低功耗模式1下，休眠之后，防抖功能无效，根据自己配置的中断触发类型，只要满足条件就会立即触发中断，自动唤醒，并且执行中断处理函数
    --          3、在PSM+模式3下，休眠之后，防抖功能无效，根据自己配置的中断触发类型，只要满足条件就会立即触发中断，自动唤醒，并且重启软件
    -- gpio.debounce(gpio.PWR_KEY, 200)
    -- gpio.setup(gpio.PWR_KEY, psm_wakeup_func, gpio.PULLUP, gpio.FALLING)    -- Air780EXX系列每个模组的核心板测试，没有增加功耗
    -- gpio.setup(gpio.PWR_KEY, psm_wakeup_func, gpio.PULLUP, gpio.RISING)     -- Air780EXX系列每个模组的核心板测试，没有增加功耗
    -- gpio.setup(gpio.PWR_KEY, psm_wakeup_func, gpio.PULLUP, gpio.BOTH)       -- Air780EXX系列每个模组的核心板测试，没有增加功耗


    -- 在Air780EXX系列模组中，Air780EHN/EHU/EHV/EGH/EGG/EGP模组包含有CHG_DET(WAKEUP6)引脚，可以将此引脚配置为中断唤醒引脚
    -- Air780EPM/EHM模组没有引出此引脚，所以无法配置CHG_DET(WAKEUP6)引脚的中断唤醒功能
    -- 配置CHG_DET(WAKEUP6)引脚下降沿、上升沿、双边沿中断唤醒（根据硬件设计原理以及项目需求，配置防抖之后，从中断唤醒方式中三选一）
    -- 防抖配置，目前是1000ms防抖（因为在核心板上使用杜邦线插拔测试，电平状态跳变频繁，所以防抖时间设置的较长，实际项目中根据自己的硬件设计和项目需求修改），冷却模式（根据项目需求可以修改）
    -- 此处的代码基于合宙Air780EXX系列支持CHG_DET(WAKEUP6)引脚的模组核心板测试：
    --     由于CHG_DET(WAKEUP6)引脚内部已经拉高至VDD_1.8V，因此只能配置为gpio.PULLUP，不能配置为gpio.PULLDOWN
    --     当配置为gpio.PULLUP时，将CHG_DET(WAKEUP6)引脚（对应的丝印为75/CHG_DET）和GND短接产生下降沿，和GND断开产生上升沿
    -- 在实际的项目中，可以根据自己的硬件设计原理以及项目需求，对此处的代码做适当修改
    -- 此情况下的唤醒重启，pm.lastReson()的返回值为6,4,0,512，仅关注第一个返回值6即可
    -- 
    -- 特别注意：gpio.debounce接口设置的防抖功能，在不同功耗模式下表现不同：
    --          1、在常规模式0下，防抖功能有效，可以参考API详细说明，配置自己需要的防抖模式，实现“有效避免误触发”的效果
    --          2、在低功耗模式1下，休眠之后，防抖功能无效，根据自己配置的中断触发类型，只要满足条件就会立即触发中断，自动唤醒，并且执行中断处理函数
    --          3、在PSM+模式3下，休眠之后，防抖功能无效，根据自己配置的中断触发类型，只要满足条件就会立即触发中断，自动唤醒，并且重启软件
    -- gpio.debounce(gpio.CHG_DET, 1000)
    -- gpio.setup(gpio.CHG_DET, psm_wakeup_func, gpio.PULLUP, gpio.FALLING)    -- Air780EXX系列支持CHG_DET(WAKEUP6)引脚的模组核心板测试，没有增加功耗
    -- gpio.setup(gpio.CHG_DET, psm_wakeup_func, gpio.PULLUP, gpio.RISING)     -- Air780EXX系列支持CHG_DET(WAKEUP6)引脚的模组核心板测试，没有增加功耗
    -- gpio.setup(gpio.CHG_DET, psm_wakeup_func, gpio.PULLUP, gpio.BOTH)       -- Air780EXX系列支持CHG_DET(WAKEUP6)引脚的模组核心板测试，没有增加功耗


    -- 配置WAKEUP0引脚下降沿、上升沿、双边沿中断唤醒（根据硬件设计原理以及项目需求，配置防抖之后，从中断唤醒方式中六选一）
    -- 防抖配置，目前是1000ms防抖（因为在核心板上使用杜邦线插拔测试，电平状态跳变频繁，所以防抖时间设置的较长，实际项目中根据自己的硬件设计和项目需求修改），冷却模式（根据项目需求可以修改）
    -- 此处的代码基于合宙Air780EXX系列每个模组的核心板测试：
    --     当配置为gpio.PULLUP时，将WAKEUP0引脚（对应的丝印为101/WAKEUP0）和GND短接产生下降沿，和GND断开产生上升沿
    --     当配置为gpio.PULLDOWN时，将WAKEUP0引脚（对应的丝印为101/WAKEUP0）和3V3引脚短接产生上升沿，和3V3引脚断开产生下降沿
    -- 在客户实际的项目中，可以根据自己的硬件设计原理以及项目需求，对此处的代码做适当修改
    -- 此情况下的唤醒重启，pm.lastReson()的返回值为2,4,0,1，仅关注第一个返回值2表示此时为WAKEUP唤醒
    -- 通过第四个返回值可以判断WAKEUP的序号，其中返回值表示2的幂，序号表示2的幂次
    -- 例如：WAKEUP0表示幂次为0，第四个返回值为2^0=1
    -- 
    -- 特别注意：gpio.debounce接口设置的防抖功能，在不同功耗模式下表现不同：
    --          1、在常规模式0下，防抖功能有效，可以参考API详细说明，配置自己需要的防抖模式，实现“有效避免误触发”的效果
    --          2、在低功耗模式1下，休眠之后，防抖功能无效，根据自己配置的中断触发类型，只要满足条件就会立即触发中断，自动唤醒，并且执行中断处理函数
    --          3、在PSM+模式3下，休眠之后，防抖功能无效，根据自己配置的中断触发类型，只要满足条件就会立即触发中断，自动唤醒，并且重启软件
    -- gpio.debounce(gpio.WAKEUP0, 1000)
    -- gpio.setup(gpio.WAKEUP0, psm_wakeup_func, gpio.PULLUP, gpio.FALLING)    -- Air780EXX系列每个模组的核心板测试，没有增加功耗
    -- gpio.setup(gpio.WAKEUP0, psm_wakeup_func, gpio.PULLUP, gpio.RISING)     -- Air780EXX系列每个模组的核心板测试，没有增加功耗
    -- gpio.setup(gpio.WAKEUP0, psm_wakeup_func, gpio.PULLUP, gpio.BOTH)       -- Air780EXX系列每个模组的核心板测试，没有增加功耗
    -- gpio.setup(gpio.WAKEUP0, psm_wakeup_func, gpio.PULLDOWN, gpio.FALLING)  -- Air780EXX系列每个模组的核心板测试，没有增加功耗
    -- gpio.setup(gpio.WAKEUP0, psm_wakeup_func, gpio.PULLDOWN, gpio.RISING)   -- Air780EXX系列每个模组的核心板测试，没有增加功耗
    -- gpio.setup(gpio.WAKEUP0, psm_wakeup_func, gpio.PULLDOWN, gpio.BOTH)     -- Air780EXX系列每个模组的核心板测试，没有增加功耗


    -- 配置VBUS(WAKEUP1)引脚下降沿、上升沿、双边沿中断唤醒（根据硬件设计原理以及项目需求，配置防抖之后，从中断唤醒方式中六选一）
    -- 防抖配置：200ms时长防抖，冷却模式（根据项目需求可以修改）
    -- 此处的代码基于合宙Air780EXX系列每个模组的核心板测试，将提供5V供电输入的USB线插入type-c座子，会产生上升沿，拔出会产生下降沿
    -- 在客户实际的项目中，可以根据自己的硬件设计原理以及项目需求，对此处的代码做适当修改
    -- 此情况下的唤醒重启，pm.lastReson()的返回值为2,4,0,2，仅关注第一个返回值2表示此时为WAKEUP唤醒
    -- 通过第四个返回值可以判断WAKEUP的序号，其中返回值表示2的幂，序号表示2的幂次
    -- 例如：WAKEUP1表示幂次为1，第四个返回值为2^1=2
    -- 
    -- 特别注意：gpio.debounce接口设置的防抖功能，在不同功耗模式下表现不同：
    --          1、在常规模式0下，防抖功能有效，可以参考API详细说明，配置自己需要的防抖模式，实现“有效避免误触发”的效果
    --          2、在低功耗模式1下，休眠之后，防抖功能无效，根据自己配置的中断触发类型，只要满足条件就会立即触发中断，自动唤醒，并且执行中断处理函数
    --          3、在PSM+模式3下，休眠之后，防抖功能无效，根据自己配置的中断触发类型，只要满足条件就会立即触发中断，自动唤醒，并且重启软件
    -- gpio.debounce(gpio.WAKEUP1, 200)
    -- gpio.setup(gpio.WAKEUP1, psm_wakeup_func, gpio.PULLUP, gpio.FALLING)    -- Air780EXX系列每个模组的核心板测试，增加17uA功耗
    -- gpio.setup(gpio.WAKEUP1, psm_wakeup_func, gpio.PULLUP, gpio.RISING)     -- Air780EXX系列每个模组的核心板测试，增加17uA功耗
    -- gpio.setup(gpio.WAKEUP1, psm_wakeup_func, gpio.PULLUP, gpio.BOTH)       -- Air780EXX系列每个模组的核心板测试，增加17uA功耗
    -- gpio.setup(gpio.WAKEUP1, psm_wakeup_func, gpio.PULLDOWN, gpio.FALLING)  -- Air780EXX系列每个模组的核心板测试，没有增加功耗
    -- gpio.setup(gpio.WAKEUP1, psm_wakeup_func, gpio.PULLDOWN, gpio.RISING)   -- Air780EXX系列每个模组的核心板测试，没有增加功耗
    -- gpio.setup(gpio.WAKEUP1, psm_wakeup_func, gpio.PULLDOWN, gpio.BOTH)     -- Air780EXX系列每个模组的核心板测试，没有增加功耗


    -- 在Air780EXX系列模组中，Air780EGP/EGG模组WAKEUP2引脚内部用作GSensor中断信号，
    -- 如果需要在低功耗模式下使用GSensor的中断唤醒功能，则需要根据下方说明打开对应的代码
    -- 
    -- Air780EPM/EHM/EHN/EHU/EHV/EGH模组WAKEUP2引脚并未被模组内部用作GSensor中断信号，可以作为普通中断功能使用，配置方式见下一个配置项
    -- 
    -- 配置WAKEUP2引脚下降沿、上升沿、双边沿中断唤醒（根据硬件设计原理以及项目需求，配置防抖之后，从中断唤醒方式中三选一）
    -- 防抖配置：200ms时长防抖，冷却模式（根据项目需求可以修改）
    -- 此处的代码基于合宙Air780EXX系列内部包含GSensor的每个模组的核心板测试，WAKEUP2引脚已被模组内部用作GSensor中断信号，外部不可再用，否则会干扰GSensor的正常工作
    -- 在实际测试时，需要先引用exvib模块，再通过exvib.open(1)打开Air780EXX系列内部包含的三轴加速度传感器DA221，最后配置WAKEUP2引脚的中断唤醒功能
    -- 由于GSensor的电源开关通过Air780EXX系列内部包含GSensor的模组的GPIO23控制，因此切记不要在其他地方对GPIO23进行二次配置，否则会干扰GSensor的正常工作
    -- 在客户实际的项目中，可以根据自己的硬件设计原理以及项目需求，对此处的代码做适当修改
    -- 此情况下的唤醒重启，pm.lastReson()的返回值为2,4,0,4，仅关注第一个返回值2表示此时为WAKEUP唤醒
    -- 通过第四个返回值可以判断WAKEUP的序号，其中返回值表示2的幂，序号表示2的幂次
    -- 例如：WAKEUP2表示幂次为2，第四个返回值为2^2=4
    -- 
    -- 特别注意：gpio.debounce接口设置的防抖功能，在不同功耗模式下表现不同：
    --          1、在常规模式0下，防抖功能有效，可以参考API详细说明，配置自己需要的防抖模式，实现“有效避免误触发”的效果
    --          2、在低功耗模式1下，休眠之后，防抖功能无效，根据自己配置的中断触发类型，只要满足条件就会立即触发中断，自动唤醒，并且执行中断处理函数
    --          3、在PSM+模式3下，休眠之后，防抖功能无效，根据自己配置的中断触发类型，只要满足条件就会立即触发中断，自动唤醒，并且重启软件
    -- if module == "Air780EGP" or module == "Air780EGG" then
    --     -- 关于引用exvib模块，功耗数据变化的说明：
    --     exvib = require("exvib")    -- 引用exvib模块
    --     exvib.open(1)               -- 打开Air780EXX系列内部的三轴加速度传感器DA221
    -- 
    --     -- 在测试下面的配置代码时，同时也需要把上面两行代码打开
    --     gpio.debounce(gpio.WAKEUP2, 200)
    --     -- gpio.setup(gpio.WAKEUP2, psm_wakeup_func, nil, gpio.FALLING)  -- Air780EXX系列内部包含GSensor的每个模组的核心板测试，没有增加功耗
    --     -- gpio.setup(gpio.WAKEUP2, psm_wakeup_func, nil, gpio.RISING)   -- Air780EXX系列内部包含GSensor的每个模组的核心板测试，没有增加功耗
    --     -- gpio.setup(gpio.WAKEUP2, psm_wakeup_func, nil, gpio.BOTH)     -- Air780EXX系列内部包含GSensor的每个模组的核心板测试，没有增加功耗
    -- end
    -- 
    -- 
    -- 在Air780EXX系列模组中，除了Air780EGP/EGG模组WAKEUP2引脚内部用作GSensor中断信号外
    -- Air780EPM/EHM/EHN/EHU/EHV/EGH模组WAKEUP2引脚并未被模组内部用作GSensor中断信号，外部可以作为WAKEUP使用
    -- 如果需要在PSM+模式下使用WAKEUP2引脚的中断唤醒功能，则需要根据下方说明打开对应的代码
    -- 
    -- 配置WAKEUP2引脚下降沿、上升沿、双边沿中断唤醒（根据硬件设计原理以及项目需求，配置防抖之后，从中断唤醒方式中六选一）
    -- 防抖配置，目前是1000ms防抖（因为在核心板上使用杜邦线插拔测试，电平状态跳变频繁，所以防抖时间设置的较长，实际项目中根据自己的硬件设计和项目需求修改），冷却模式（根据项目需求可以修改）
    -- 此处的代码基于合宙Air780EXX系列每个模组内部不包含GSensor的核心板测试：
    --     当配置为gpio.PULLUP时，将WAKEUP2引脚（对应的丝印为79/SIMDET）和GND短接产生下降沿，和GND断开产生上升沿
    --     当配置为gpio.PULLDOWN时，将WAKEUP2引脚（对应的丝印为79/SIMDET）和3V3引脚短接产生上升沿，和3V3引脚断开产生下降沿
    -- 在客户实际的项目中，可以根据自己的硬件设计原理以及项目需求，对此处的代码做适当修改
    -- 此情况下的唤醒重启，pm.lastReson()的返回值为2,4,0,4，仅关注第一个返回值2表示此时为WAKEUP唤醒
    -- 通过第四个返回值可以判断WAKEUP的序号，其中返回值表示2的幂，序号表示2的幂次
    -- 例如：WAKEUP2表示幂次为2，第四个返回值为2^2=4
    -- 
    -- 特别注意：gpio.debounce接口设置的防抖功能，在不同功耗模式下表现不同：
    --          1、在常规模式0下，防抖功能有效，可以参考API详细说明，配置自己需要的防抖模式，实现“有效避免误触发”的效果
    --          2、在低功耗模式1下，休眠之后，防抖功能无效，根据自己配置的中断触发类型，只要满足条件就会立即触发中断，自动唤醒，并且执行中断处理函数
    --          3、在PSM+模式3下，休眠之后，防抖功能无效，根据自己配置的中断触发类型，只要满足条件就会立即触发中断，自动唤醒，并且重启软件
    -- if module == "Air780EPM" or module == "Air780EHM" or module == "Air780EHN" or module == "Air780EHU" or module == "Air780EHV" or module == "Air780EGH" then
    --     gpio.debounce(gpio.WAKEUP2, 1000)
    --     -- gpio.setup(gpio.WAKEUP2, psm_wakeup_func, gpio.PULLUP, gpio.FALLING)    -- Air780EXX系列内部不包含GSensor的每个模组的核心板测试，没有增加功耗
    --     -- gpio.setup(gpio.WAKEUP2, psm_wakeup_func, gpio.PULLUP, gpio.RISING)     -- Air780EXX系列内部不包含GSensor的每个模组的核心板测试，没有增加功耗
    --     -- gpio.setup(gpio.WAKEUP2, psm_wakeup_func, gpio.PULLUP, gpio.BOTH)       -- Air780EXX系列内部不包含GSensor的每个模组的核心板测试，没有增加功耗
    --     -- gpio.setup(gpio.WAKEUP2, psm_wakeup_func, gpio.PULLDOWN, gpio.FALLING)  -- Air780EXX系列内部不包含GSensor的每个模组的核心板测试，没有增加功耗
    --     -- gpio.setup(gpio.WAKEUP2, psm_wakeup_func, gpio.PULLDOWN, gpio.RISING)   -- Air780EXX系列内部不包含GSensor的每个模组的核心板测试，没有增加功耗
    --     -- gpio.setup(gpio.WAKEUP2, psm_wakeup_func, gpio.PULLDOWN, gpio.BOTH)     -- Air780EXX系列内部不包含GSensor的每个模组的核心板测试，没有增加功耗
    -- end


    -- 在Air780EXX系列模组中，Air780EHV模组内部将GPIO20引脚强制用作GPIO20功能，用于控制Audio Codec芯片ES8311的供电使能开关
    -- 除Air780EHV模组外，Air780EPM/EHM/EHN/EHU/EGH/EGG/EGP模组可以将GPIO20引脚配置为WAKEUP3引脚，用于中断唤醒功能
    -- 配置WAKEUP3引脚下降沿、上升沿、双边沿中断唤醒（根据硬件设计原理以及项目需求，配置防抖之后，从中断唤醒方式中六选一）
    -- 防抖配置，目前是1000ms防抖（因为在核心板上使用杜邦线插拔测试，电平状态跳变频繁，所以防抖时间设置的较长，实际项目中根据自己的硬件设计和项目需求修改），冷却模式（根据项目需求可以修改）
    -- 此处的代码基于合宙Air780EXX系列支持将GPIO20引脚配置为WAKEUP3引脚的模组的核心板测试：
    --     当配置为gpio.PULLUP时，将WAKEUP3引脚（对应的丝印为102/GPIO20）和GND短接产生下降沿，和GND断开产生上升沿
    --     当配置为gpio.PULLDOWN时，将WAKEUP3引脚（对应的丝印为102/GPIO20）和3V3引脚短接产生上升沿，和3V3引脚断开产生下降沿
    -- 在客户实际的项目中，可以根据自己的硬件设计原理以及项目需求，对此处的代码做适当修改
    -- 此情况下的唤醒重启，pm.lastReson()的返回值为2,4,0,8，仅关注第一个返回值2表示此时为WAKEUP唤醒
    -- 通过第四个返回值可以判断WAKEUP的序号，其中返回值表示2的幂，序号表示2的幂次
    -- 例如：WAKEUP3表示幂次为3，第四个返回值为2^3=8
    -- 
    -- 特别注意：gpio.debounce接口设置的防抖功能，在不同功耗模式下表现不同：
    --          1、在常规模式0下，防抖功能有效，可以参考API详细说明，配置自己需要的防抖模式，实现“有效避免误触发”的效果
    --          2、在低功耗模式1下，休眠之后，防抖功能无效，根据自己配置的中断触发类型，只要满足条件就会立即触发中断，自动唤醒，并且执行中断处理函数
    --          3、在PSM+模式3下，休眠之后，防抖功能无效，根据自己配置的中断触发类型，只要满足条件就会立即触发中断，自动唤醒，并且重启软件
    -- gpio.debounce(gpio.WAKEUP3, 1000)
    -- gpio.setup(gpio.WAKEUP3, psm_wakeup_func, gpio.PULLUP, gpio.FALLING)    -- Air780EXX系列支持将GPIO20引脚配置为WAKEUP3引脚的模组的核心板测试，没有增加功耗
    -- gpio.setup(gpio.WAKEUP3, psm_wakeup_func, gpio.PULLUP, gpio.RISING)     -- Air780EXX系列支持将GPIO20引脚配置为WAKEUP3引脚的模组的核心板测试，没有增加功耗
    -- gpio.setup(gpio.WAKEUP3, psm_wakeup_func, gpio.PULLUP, gpio.BOTH)       -- Air780EXX系列支持将GPIO20引脚配置为WAKEUP3引脚的模组的核心板测试，没有增加功耗
    -- gpio.setup(gpio.WAKEUP3, psm_wakeup_func, gpio.PULLDOWN, gpio.FALLING)  -- Air780EXX系列支持将GPIO20引脚配置为WAKEUP3引脚的模组的核心板测试，没有增加功耗
    -- gpio.setup(gpio.WAKEUP3, psm_wakeup_func, gpio.PULLDOWN, gpio.RISING)   -- Air780EXX系列支持将GPIO20引脚配置为WAKEUP3引脚的模组的核心板测试，没有增加功耗
    -- gpio.setup(gpio.WAKEUP3, psm_wakeup_func, gpio.PULLDOWN, gpio.BOTH)     -- Air780EXX系列支持将GPIO20引脚配置为WAKEUP3引脚的模组的核心板测试，没有增加功耗


    -- 在Air780EXX系列模组中，Air780EGH/EGP/EGG模组内部将GPIO21引脚强制用作GPIO21功能，用于控制GNSS定位芯片的供电使能开关
    -- 除Air780EGH/EGP/EGG模组外，Air780EPM/EHM/EHN/EHU/EHV模组可以将GPIO21引脚配置为WAKEUP4引脚，用于中断唤醒功能
    -- 配置WAKEUP4引脚下降沿、上升沿、双边沿中断唤醒（根据硬件设计原理以及项目需求，配置防抖之后，从中断唤醒方式中六选一）
    -- 防抖配置，目前是1000ms防抖（因为在核心板上使用杜邦线插拔测试，电平状态跳变频繁，所以防抖时间设置的较长，实际项目中根据自己的硬件设计和项目需求修改），冷却模式（根据项目需求可以修改）
    -- 此处的代码基于合宙Air780EXX系列支持将GPIO21引脚配置为WAKEUP4引脚的模组的核心板测试：
    --     当配置为gpio.PULLUP时，将WAKEUP4引脚（对应的丝印为107/GPIO21）和GND短接产生下降沿，和GND断开产生上升沿
    --     当配置为gpio.PULLDOWN时，将WAKEUP4引脚（对应的丝印为107/GPIO21）和3V3引脚短接产生上升沿，和3V3引脚断开产生下降沿
    -- 在客户实际的项目中，可以根据自己的硬件设计原理以及项目需求，对此处的代码做适当修改
    -- 此情况下的唤醒重启，pm.lastReson()的返回值为2,4,0,16，仅关注第一个返回值2表示此时为WAKEUP唤醒
    -- 通过第四个返回值可以判断WAKEUP的序号，其中返回值表示2的幂，序号表示2的幂次
    -- 例如：WAKEUP4表示幂次为4，第四个返回值为2^4=16
    -- 
    -- 特别注意：gpio.debounce接口设置的防抖功能，在不同功耗模式下表现不同：
    --          1、在常规模式0下，防抖功能有效，可以参考API详细说明，配置自己需要的防抖模式，实现“有效避免误触发”的效果
    --          2、在低功耗模式1下，休眠之后，防抖功能无效，根据自己配置的中断触发类型，只要满足条件就会立即触发中断，自动唤醒，并且执行中断处理函数
    --          3、在PSM+模式3下，休眠之后，防抖功能无效，根据自己配置的中断触发类型，只要满足条件就会立即触发中断，自动唤醒，并且重启软件
    -- if module == "Air780EPM" or module == "Air780EHM" or module == "Air780EHN" or module == "Air780EHU" or module == "Air780EHV" then
    --     gpio.debounce(gpio.WAKEUP4, 1000)
    --     -- gpio.setup(gpio.WAKEUP4, psm_wakeup_func, gpio.PULLUP, gpio.FALLING)    -- Air780EXX系列支持将GPIO21引脚配置为WAKEUP4引脚的模组的核心板测试，没有增加功耗
    --     -- gpio.setup(gpio.WAKEUP4, psm_wakeup_func, gpio.PULLUP, gpio.RISING)     -- Air780EXX系列支持将GPIO21引脚配置为WAKEUP4引脚的模组的核心板测试，没有增加功耗
    --     -- gpio.setup(gpio.WAKEUP4, psm_wakeup_func, gpio.PULLUP, gpio.BOTH)       -- Air780EXX系列支持将GPIO21引脚配置为WAKEUP4引脚的模组的核心板测试，没有增加功耗
    --     -- gpio.setup(gpio.WAKEUP4, psm_wakeup_func, gpio.PULLDOWN, gpio.FALLING)  -- Air780EXX系列支持将GPIO21引脚配置为WAKEUP4引脚的模组的核心板测试，没有增加功耗
    --     -- gpio.setup(gpio.WAKEUP4, psm_wakeup_func, gpio.PULLDOWN, gpio.RISING)   -- Air780EXX系列支持将GPIO21引脚配置为WAKEUP4引脚的模组的核心板测试，没有增加功耗
    --     -- gpio.setup(gpio.WAKEUP4, psm_wakeup_func, gpio.PULLDOWN, gpio.BOTH)     -- Air780EXX系列支持将GPIO21引脚配置为WAKEUP4引脚的模组的核心板测试，没有增加功耗
    -- end


    -- 配置WAKEUP5引脚下降沿、上升沿、双边沿中断唤醒（根据硬件设计原理以及项目需求，配置防抖之后，从中断唤醒方式中六选一）
    -- 防抖配置，目前是1000ms防抖（因为在核心板上使用杜邦线插拔测试，电平状态跳变频繁，所以防抖时间设置的较长，实际项目中根据自己的硬件设计和项目需求修改），冷却模式（根据项目需求可以修改）
    -- 此处的代码基于合宙Air780EXX系列每个模组的核心板测试：
    --     当配置为gpio.PULLUP时，将WAKEUP5引脚（对应的丝印为19/GPIO22）和GND短接产生下降沿，和GND断开产生上升沿
    --     当配置为gpio.PULLDOWN时，将WAKEUP5引脚（对应的丝印为19/GPIO22）和3V3引脚短接产生上升沿，和3V3引脚断开产生下降沿
    -- 在客户实际的项目中，可以根据自己的硬件设计原理以及项目需求，对此处的代码做适当修改
    -- 此情况下的唤醒重启，pm.lastReson()的返回值为2,4,0,32，仅关注第一个返回值2表示此时为WAKEUP唤醒
    -- 通过第四个返回值可以判断WAKEUP的序号，其中返回值表示2的幂，序号表示2的幂次
    -- 例如：WAKEUP5表示幂次为5，第四个返回值为2^5=32
    -- 
    -- 特别注意：gpio.debounce接口设置的防抖功能，在不同功耗模式下表现不同：
    --          1、在常规模式0下，防抖功能有效，可以参考API详细说明，配置自己需要的防抖模式，实现“有效避免误触发”的效果
    --          2、在低功耗模式1下，休眠之后，防抖功能无效，根据自己配置的中断触发类型，只要满足条件就会立即触发中断，自动唤醒，并且执行中断处理函数
    --          3、在PSM+模式3下，休眠之后，防抖功能无效，根据自己配置的中断触发类型，只要满足条件就会立即触发中断，自动唤醒，并且重启软件
    -- gpio.debounce(gpio.WAKEUP5, 1000)
    -- gpio.setup(gpio.WAKEUP5, psm_wakeup_func, gpio.PULLUP, gpio.FALLING)    -- Air780EXX系列每个模组的核心板测试，没有增加功耗
    -- gpio.setup(gpio.WAKEUP5, psm_wakeup_func, gpio.PULLUP, gpio.RISING)     -- Air780EXX系列每个模组的核心板测试，没有增加功耗
    -- gpio.setup(gpio.WAKEUP5, psm_wakeup_func, gpio.PULLUP, gpio.BOTH)       -- Air780EXX系列每个模组的核心板测试，没有增加功耗
    -- gpio.setup(gpio.WAKEUP5, psm_wakeup_func, gpio.PULLDOWN, gpio.FALLING)  -- Air780EXX系列每个模组的核心板测试，没有增加功耗
    -- gpio.setup(gpio.WAKEUP5, psm_wakeup_func, gpio.PULLDOWN, gpio.RISING)   -- Air780EXX系列每个模组的核心板测试，没有增加功耗
    -- gpio.setup(gpio.WAKEUP5, psm_wakeup_func, gpio.PULLDOWN, gpio.BOTH)     -- Air780EXX系列每个模组的核心板测试，没有增加功耗


    -- 配置UART1_RXD接收到数据唤醒（模组配置为任意支持的波特率都可以，对端串口配置任意的波特率也可以，二者波特率不必一致）
    -- 此处仅仅简单的演示UART1唤醒功能的配置，更详细的用法参考单独的uart demo
    -- 初始化UART1，波特率9600，数据位8，停止位1
    -- 基于合宙Air780EXX系列每个模组的核心板测试，将UART1引脚（对应的丝印为17/U1RXD、18/U1TXD、GND）通过USB转TTL串口线和电脑相连，电脑串口工具配置任意波特率，数据位8，停止位1，串口工具发送任何数据都可以唤醒模组
    -- 此情况下的唤醒重启，pm.lastReson()的返回值为3,4,0,64，仅关注第一个返回值3即可
    -- uart.setup(1, 9600, 8, 1)    -- Air780EXX系列每个模组的核心板测试，没有增加功耗
end


-- Air780EGG/EGP模组内部包含有Gsensor，Air780EGH/EGP/EGG模组内部包含有GNSS
-- Air780EHV模组内部包含有Audio Codec芯片ES8311，Air780EHU/EHN/EHV/EGH/EGP/EGG模组支持CHG_DET（WAKEUP6）功能
-- Air780EPM/EHM模组没有引出CHG_DET（WAKEUP6）引脚，无法配置CHG_DET（WAKEUP6）功能
-- set_psm_func_item()中会自动对模组型号进行判断，避免对不包含GNSS/Gsensor/Audio Codec芯片或者CHG_DET（WAKEUP6）功能的模组进行误配置
-- 在进入PSM+模式前，根据自己的实际项目需求，配置一些必要的功能项，可以在满足项目功能需求的背景下，让功耗降到最低
local function set_psm_func_item()
    -- 第一类功能配置项：飞行模式
    -- 通过配置飞行模式可以有效关闭4G芯片的4G网络能力
    -- 
    -- 这个功能的特性是：
    -- 1、在常规模式下，飞行模式默认是关闭的，可以根据项目需要显式的开启飞行模式，从而关闭4G网络能力
    -- 2、在低功耗模式下，飞行模式默认也是关闭的，需要根据项目需要显式的开启飞行模式，从而关闭4G网络能力，关闭后可以有效降低功耗
    -- 3、在PSM+模式下，飞行模式默认是开启的，不能显式的关闭飞行模式
    -- 从2025年3月份发布的内核固件开始：
    -- 1、在pm.power(pm.WORK_MODE, 3)中会自动执行mobile.flymode(0, true)进入飞行模式
    -- 2、从PSM+模式唤醒重启后，重启后飞行模式的状态和重启前用户是否显式执行mobile.flymode控制的飞行模式的状态一致；
    -- 3、其余原因的重启或者开机，重启或者开机后，自动退出飞行模式；
    -- 根据自己的项目需求决定：进入PSM+模式前，是否需要显式的进入飞行模式；如果需要，则打开下面这行代码
    -- 是否打开下面这行代码，最终不会影响PSM+模式的功耗，仅仅影响从PSM+模式唤醒重启后的默认飞行模式状态
    -- 如果打开了下面这行代码，进入PSM+模式后，被唤醒会自动重启软件，重启后，默认仍然处于飞行模式状态
    -- 轻易不要打开这行代码，因为这行代码和具体项目的业务逻辑关联性会比较强，在这里加上这行代码仅仅是为了解释：显式进行飞行模式后，下次重启后的默认飞行状态
    -- mobile.flymode(0, true)


    -- 第二类功能配置项：USB功能
    -- 通过USB功能可以实现抓日志和业务数据通信等
    -- 
    -- 这个功能的特性是：
    -- 1、在常规模式下，USB功能是默认开启的，通过USB虚拟串口进行抓日志和业务数据通信等
    -- 2、在低功耗模式和PSM+模式下，此时USB功能默认是关闭的，无法使用USB虚拟串口进行抓日志和业务数据通信等
    -- 根据自己的项目需求决定：进入PSM+模式前，是否需要关闭USB功能
    -- 从2025年3月份发布的内核固件开始：
    -- 1、在pm.power(pm.WORK_MODE, 1)和pm.power(pm.WORK_MODE, 3)中会自动执行pm.power(pm.USB, false)关闭USB功能
    -- 2、在pm.power(pm.WORK_MODE, 0)会自动执行pm.power(pm.USB, true)打开USB功能
    -- 所以，如果你使用的内核固件如果是2025年3月份之后发布的，则不再需要显示的关闭USB功能，在PSM+模式中会自动关闭USB功能
    -- 此处代码默认没有显式的关闭USB功能，是因为在后续的pm.power(pm.WORK_MODE, 1)中会自动关闭USB功能
    -- 如果由于某种原因，你必须使用2025年3月份之前的内核固件，则根据需求可以打开下面的一行代码
    -- 在vbat供电3.8v的状态下，关闭USB功能，可以减少140uA到200uA左右的功耗
    -- pm.power(pm.USB, false)


    -- 第三类功能配置项：GNSS备电电源开关及Gsensor电源开关
    -- 这一类功能配置项仅对Air780EGH/EGG/EGP模组有效（Air780EGH内部包含GNSS，Air780EGG/EGP内部包含GNSS和Gsensor）
    -- Air780EPM/EHM/EHN/EHU/EHV模组内部不包含GNSS和Gsensor，无法使用该功能
    -- Air780EGH/EGG/EGP模组通过GPIO23作为GNSS的备电电源开关和Gsensor的电源开关，默认为高电平输出
    -- 
    -- 这个功能引脚输出的电平状态，对GNSS和Gsensor功能的影响是：
    -- GNSS：在低功耗模式或者PSM+模式下，
    --      如果GPIO23输出高电平，可以保证GNSS的定位数据不被丢失，
    --                           并且在关闭GNSS后两个小时内，在室外空旷环境下，再次打开GNSS时，可以热启动3s左右快速获取到定位数据；
    --                           但是如果超过两个小时之后，再次打开GNSS，就是冷启动状态，35s左右才能获取到定位数据；
    --      如果GPIO23输出低电平，此时GNSS的备电电源开关是关闭的，下次打开GNSS时，就是冷启动状态，35s左右才能获取到定位数据；
    --      客户可以根据项目需求来配置GPIO23的电平状态
    -- Gsensor：在低功耗模式或者PSM+模式下，
    --          如果GPIO23输出高电平，Gsensor的电源开关处于打开状态，那么可以通过Gsensor的中断唤醒脚（WAKEUP2）来实现震动中断唤醒功能；
    --          如果GPIO23输出低电平，Gsensor的电源开关处于关闭状态，那么无法使用Gsensor的任何功能；
    -- 
    -- 所以，在实际的项目设计中，如果需要工作在低功耗模式或者PSM+模式下，
    -- 可能你会打开GNSS的备电电源开关和GSensor的电源开关，用于保存GNSS的定位数据和快速获取定位数据或者实现GSensor的震动中断唤醒功能
    -- 根据自己的项目需求决定：进入PSM+模式前，是否需要关闭GNSS的备电电源开关和GSensor的电源开关
    -- 此处默认使用的是配置为输入下拉的方式来关闭，默认代码已经打开，可以减少200uA左右的功耗
    if module == "Air780EGH" or module == "Air780EGG" or module == "Air780EGP" then
        gpio.setup(23, nil, gpio.PULLDOWN)
    end


    -- 第四类功能配置项：通用AGPIO（GPIO24、GPIO25、GPIO26、GPIO27、GPIO28）
    -- 这五个功能引脚在Air780EXX系列模组内部并没有被占用，所以用户在项目开发中可以根据自己的项目需求来使用任何一个引脚
    -- 
    -- 这些功能引脚的特性是：
    -- 1、在常规功耗模式下，可以做为普通的GPIO输出、输入、中断使用
    -- 2、在低功耗模式和PSM+模式下，可以保持固定的高电平或者低电平输出
    -- 3、如果在模组内部和模组外部都没有接其他元器件，无论软件上如何配置AGPIO，对功耗都没有影响
    -- 4、如果在模组内部或者模组外部接了其他元器件，当软件配置的AGPIO输出低，让元器件彻底不工作，则对功耗都没有影响
    -- 5、如果在模组内部或者模组外部接了其他元器件，当软件配置的AGPIO输出高，让元器件彻底不工作，并且AGPIO在硬件上也没有接下拉电阻，则对功耗都没有影响
    -- 6、如果在模组内部或者模组外部接了其他元器件，当软件配置的AGPIO输出高，让元器件彻底不工作，但是AGPIO在硬件上接了下拉电阻，对功耗有影响
    --    例如接了100K的下拉电阻，当AGPIO输出的高电平是3.3V、下拉电阻是100K时，其电流影响的理论值大概是3.3V/100K=33uA，具体数据以实际硬件环境的测量为准
    -- 7、如果在模组内部或者模组外部接了其他元器件，当软件配置的AGPIO输出电平可以让元器件正常工作，则对功耗有影响，影响大小取决于元器件本身的耗电，具体数据以实际硬件环境的测量为准
    -- 所以，在实际的项目设计中，如果需要工作在低功耗模式或者PSM+模式下
    -- 可能你会使用这些AGPIO来固定输出高电平，做为Vref，给其他外围硬件电路做上拉使用（例如模组的UART RX可以上拉到Vref，SIM卡插入检测的USIM_DET可以上拉到Vref）；也可能会有其他用途
    -- 根据自己的项目需求决定：进入PSM+模式前，来关闭AGPIO（GPIO24、GPIO25、GPIO26、GPIO27、GPIO28）控制的电路单元的功耗
    -- 一旦关闭，如果你项目中使用了这些功能引脚，意味着这些功能引脚有关的功能将无法正常工作，例如无法为外围电路提供上拉
    -- 此处默认使用的是配置为输入下拉的方式来关闭，默认代码已经注释掉了，如果默认不配置的状态可以满足需求（实际测试一下功耗），就可以不用代码控制，默认什么动作都不处理即可
    -- 如果打开这里的默认配置代码可以满足需求（实际测试一下功耗），就可以直接打开使用
    -- 如果无法满足需求，需要根据自己的电路设计，来决定如何关闭（什么都不处理，输出低电平，输出高电平，close，输入下拉，输入上拉，六种方式中的一种）；
    -- 具体使用何种方式，需要结合自己的硬件来实际测试，选取功耗最低的一种即可
    -- 可以在此处关闭，也可以在具体的外围电路软件功能模块代码文件中关闭
    -- gpio.setup(24, nil, gpio.PULLDOWN)
    -- gpio.setup(25, nil, gpio.PULLDOWN)
    -- gpio.setup(26, nil, gpio.PULLDOWN)
    -- gpio.setup(27, nil, gpio.PULLDOWN)
    -- gpio.setup(28, nil, gpio.PULLDOWN)


    -- 第五类功能配置项：通用WAKEUP（WAKEUP0）
    -- 这一个功能引脚在Air780EXX系列每个模组内部并没有被占用，所以用户在项目开发中可以根据自己的项目需求来使用这个引脚
    -- 
    -- 这些功能引脚的特性是：
    -- 1、在常规功耗模式下，可以做为中断使用，每个引脚可以配置独立的中断处理函数，用来区分是哪一个WAKEUP引脚产生的中断
    -- 2、在低功耗模式下，也可以作为中断使用，每个引脚可以配置独立的中断处理函数，用来区分是哪一个WAKEUP引脚产生的中断
    -- 3、在PSM+模式下，也可以作为中断使用，虽然每个引脚可以配置独立的中断处理函数，但是仅仅做为唤醒功能使用，一旦唤醒，软件系统会直接重启，并不会执行中断处理函数，无法区分是哪一个WAKEUP引脚唤醒
    -- 所以，在实际的项目设计中，如果需要工作在低功耗模式或者PSM+模式下，可能你会使用这些WAKEUP引脚的中断唤醒功能
    -- 根据自己的项目需求，决定是否需要关闭通用WAKEUP（WAKEUP0）功能，如果关闭，对功耗的影响可以降到最低
    -- 一旦关闭，如果你项目中使用了这些功能引脚，意味着这些功能引脚有关的功能将无法正常工作，例如无法中断唤醒
    -- 此处默认使用的是配置为输入下拉的方式来关闭，默认代码已经注释掉了，如果默认不配置的状态可以满足需求（实际测试一下功耗），就可以不用代码控制，默认什么动作都不处理即可
    -- 如果打开这里的默认配置代码可以满足需求（实际测试一下功耗），就可以直接打开使用
    -- 如果无法满足需求，需要根据自己的电路设计，来决定如何关闭（什么都不处理，输入下拉，输入上拉，close，四种方式中的一种）；具体使用何种方式，需要结合自己的硬件来实际测试，选取功耗最低的一种即可
    -- 可以在此处关闭，也可以在具体的外围电路软件功能模块代码文件中关闭
    -- gpio.setup(gpio.WAKEUP0, nil, gpio.PULLDOWN)


    -- 第六类功能配置项：VBUS（WAKEUP1）
    -- 这个是VBUS功能引脚，在Air780EXX系列每个模组内部经分压后接WAKEUP1，固定只能用作USB插入检测使用
    -- 
    -- 这个功能引脚的特性是：
    -- 1、在常规功耗模式下，可以做为中断使用，可以配置中断处理函数处理业务逻辑
    -- 2、在低功耗模式下，也可以作为中断使用，可以配置中断处理函数处理业务逻辑
    -- 3、在PSM+模式下，也可以作为中断使用，虽然可以配置中断处理函数，但是仅仅做为唤醒功能使用，一旦唤醒，软件系统会直接重启，并不会执行中断处理函数
    -- 所以，在实际的项目设计中，如果需要工作在低功耗模式或者PSM+模式下，可能你会使用这个引脚的中断唤醒功能
    -- 根据自己的项目需求决定是否需要关闭VBUS（WAKEUP1）功能，如果关闭，对功耗的影响可以降到最低
    -- 一旦关闭，如果你项目中使用了这个功能引脚，意味着这个功能引脚有关的功能将无法正常工作，例如无法检测USB插入、无法中断唤醒
    -- 此处默认使用的是配置为输入下拉的方式来关闭，默认代码已经注释掉了，如果默认不配置的状态可以满足需求（实际测试一下功耗），就可以不用代码控制，默认什么动作都不处理即可
    -- 如果打开这里的默认配置代码可以满足需求（实际测试一下功耗），就可以直接打开使用
    -- 如果无法满足需求，需要根据自己的电路设计，来决定如何关闭（什么都不处理，输入下拉，输入上拉，close，四种方式中的一种）；具体使用何种方式，需要结合自己的硬件来实际测试，选取功耗最低的一种即可
    -- 可以在此处关闭，也可以在具体的外围电路软件功能模块代码文件中关闭
    -- gpio.setup(gpio.WAKEUP1, nil, gpio.PULLDOWN)



    -- 第七类功能配置项：AGPIOWU（GPIO20/WAKEUP3、GPIO21/WAKEUP4、GPIO22/WAKEUP5）
    -- 在Air780EXX系列模组中，Air780EHV模组内部将GPIO20/WAKEUP3引脚作为GPIO20功能，用于控制Audio Codec芯片ES8311的供电使能开关
    -- 除Air780EHV模组外，Air780EPM/EHM/EHU/EHN/EGH/EGP/EGG模组可以将GPIO20/WAKEUP3引脚作为WAKEUP3功能使用
    -- 
    -- 在Air780EXX系列模组中，Air780EGH/EGP/EGG模组内部将GPIO21/WAKEUP4引脚作为GPIO21功能，用于控制GNSS定位芯片的供电使能开关
    -- 除Air780EGH/EGP/EGG模组外，Air780EPM/EHM/EHU/EHN/EHV模组可以将GPIO21/WAKEUP4引脚作为WAKEUP4功能使用
    -- 
    -- 只有GPIO22/WAKEUP5引脚在Air780EXX系列模组中没有被占用
    -- 
    -- 所以用户在项目开发中可以根据自己的项目需求以及选择的模组型号来合理使用任何一个引脚
    -- 
    -- 这些功能引脚的特性是：
    -- 1、软件上既可以配置做为AGPIO使用，也可以配置做为WAKEUP使用
    -- 2、做AGPIO使用时，功能特性以及如何配置可以将功耗降到最低，参考上文中“第三类功能配置项：通用AGPIO”的说明
    -- 3、做WAKEUP使用时，功能特性以及如何配置可以将功耗降到最低，参考上文中“第四类功能配置项：通用WAKEUP”的说明
    -- if module == "Air780EPM" or module == "Air780EHM" or module == "Air780EHU" or module == "Air780EHN" or module == "Air780EGH" or module == "Air780EGP" or module == "Air780EGG" then
    --     gpio.setup(gpio.WAKEUP3, nil, gpio.PULLDOWN)
    -- end
    -- 
    -- if module == "Air780EPM" or module == "Air780EHM" or module == "Air780EHU" or module == "Air780EHN" or module == "Air780EHV" then
    --     gpio.setup(gpio.WAKEUP4, nil, gpio.PULLDOWN)
    -- end
    -- 
    -- gpio.setup(gpio.WAKEUP5, nil, gpio.PULLDOWN)


    -- 第八类功能配置项：PWR_KEY
    -- 这个是PWRKEY开机键功能引脚，这个功能引脚的特性是：
    -- 1、如果PWRKEY接地，模组上电即开机；如果PWRKEY不接地，模组上电后，此引脚检测到下降沿就可以开机
    -- 2、开机运行之后：
    --    (1) 在常规功耗模式下，可以做为中断使用，可以配置中断处理函数处理业务逻辑
    --    (2) 在低功耗模式下，也可以作为中断使用，可以配置中断处理函数处理业务逻辑
    --    (3) 在PSM+模式下，也可以作为中断使用，虽然可以配置中断处理函数，但是仅仅做为唤醒功能使用，一旦唤醒，软件系统会直接重启，并不会执行中断处理函数
    -- 所以，在实际的项目设计中，如果需要工作在低功耗模式或者PSM+模式下，可能你会使用这个引脚的中断唤醒功能
    -- 需要提醒的是，PWR_KEY引脚如果硬件设计为接地自动开机，通常会增加系统功耗；以Air780EXX系列每个模组的核心板为例，如果一直按下开机键，则会增加系统功耗15uA左右
    -- 根据自己的项目需求决定：进入PSM+模式前，是否需要关闭PWR_KEY功能
    -- 一旦关闭，如果你项目中使用了这个功能引脚，意味着这个功能引脚有关的功能将无法正常工作，例如无法中断唤醒
    -- gpio.setup(gpio.PWR_KEY, nil, gpio.PULLDOWN)


    -- 第九类功能配置项：CHG_DET（WAKEUP6）
    -- 在Air780EXX系列模组中，Air780EHU/EHN/EHV/EGH/EGG/EGP模组支持CHG_DET（WAKEUP6）功能
    -- Air780EPM/EHM模组没有引出此引脚，所以无法配置CHG_DET（WAKEUP6）功能
    -- 
    -- 原始功能为充电器插入检测，目前只做跟PWR_KEY一样的功能使用
    -- PWR_KEY引脚与CHG_DET（WAKEUP6）引脚在硬件上的部分区别在于：
    -- 1、PWR_KEY引脚内部上拉至VBAT，CHG_DET（WAKEUP6）引脚内部上拉至一个不对外开放的LDO_1.8V
    -- 2、PWR_KEY引脚可以直接接地或者通过串联电阻接地，而CHG_DET（WAKEUP6）引脚只能直接接地，不能通过串联电阻接地
    -- CHG_DET（WAKEUP6）引脚的特性是：
    -- 1、上电开机前，CHG_DET（WAKEUP6）引脚检测到下降沿（接地）就可以执行开机
    -- 2、开机运行之后：
    --    (1) 在常规功耗模式下，可以做为中断使用，可以配置中断处理函数处理业务逻辑
    --    (2) 在低功耗模式下，也可以作为中断使用，可以配置中断处理函数处理业务逻辑
    --    (3) 在PSM+模式下，也可以作为中断使用，虽然可以配置中断处理函数，但是仅仅做为唤醒功能使用，一旦唤醒，软件系统会直接重启，并不会执行中断处理函数
    -- 所以，在实际的项目设计中，如果需要工作在低功耗模式或者PSM+模式下，可能你会使用这个引脚的中断唤醒功能
    -- 根据自己的项目需求决定：进入PSM+模式前，是否需要关闭CHG_DET（WAKEUP6）功能
    -- 一旦关闭，如果你项目中使用了这个功能引脚，意味着这个功能引脚有关的功能将无法正常工作，例如无法中断唤醒
    -- if module == "Air780EHU" or module == "Air780EHN" or module == "Air780EHV" or module == "Air780EGH" or module == "Air780EGP" or module == "Air780EGG" then
    --     gpio.setup(gpio.CHG_DET, nil, gpio.PULLDOWN)
    -- end
end


local function psm_task()
    log.info("psm_task enter")

    -- 在进入PSM+模式前，根据自己的实际项目需求，配置进入PSM+模式后的唤醒方式
    -- 一定要仔细阅读这个函数的代码注释说明，根据自己的项目需求来决定是否需要配置每一项功能
    -- 注意：如果在此处配置了某些引脚，就不要在接下来的set_psm_func_item()函数中关闭对应的引脚功能，否则会导致配置失效
    -- 例如，如果在此函数中配置了WAKEUP0引脚中断唤醒，则在set_psm_func_item()中就不要关闭WAKEUP0引脚功能
    set_psm_interrupt_wakeup()


    -- 在进入PSM+模式前，根据自己的实际项目需求，配置一些必要的功能项
    -- 可以在满足项目功能需求的背景下，让功耗降到最低
    -- 一定要仔细阅读这个函数的代码注释说明，根据自己的项目需求来决定是否需要配置每一项功能
    set_psm_func_item()


    -- 延时10秒钟，是为了使用USB抓取日志
    -- 仅仅开发调试过程中需要，量产前不需要
    -- sys.wait(10000)


    -- 配置最低功耗模式为PSM+模式
    -- 执行下面这行代码后，只是配置了允许系统进入PSM+模式
    -- 并不是说，一定会立即进入PSM+模式，最终进入PSM+模式的时间点，取决于内核固件中的任务和Lua脚本中task都处于阻塞状态
    -- 也就是说，执行这一行代码时：
    -- (1) 如果内核固件中的任务和Lua脚本中task都处于阻塞状态，理论上就会立即成功进入PSM+模式
    -- (2) 否则，不会立即成功进入PSM+模式，而是等待所有运行中的任务处于阻塞状态；
    --     假设5秒钟之后，满足了条件，则5秒钟之后会成功进入PSM+模式；这种情况下，执行到这一行代码时仅仅是配置了一下，还会接着执行后续其他脚本代码，等5秒钟之后，内核固件就会自动控制成功进入PSM+模式
    -- 
    -- 一旦成功进入PSM+模式，则从进入的那一刻起，RAM掉电，后续不再执行任何脚本代码
    -- 使用合宙核心板测试的PSM+模式功耗数据，在vbat供电3.8v状态下，配置set_psm_func_item()中的所有功能项：3.3uA左右（3uA到10uA都属于正常值）
    pm.power(pm.WORK_MODE, 3)


    -- 下面几行代码实现的功能是：延时等待80秒，然后软件重启；
    --
    -- 为什么要写下面三行代码，分以下两种情况介绍：
    -- 1、当上面执行pm.power(pm.WORK_MODE, 3)时，如果立即成功进入到PSM+模式，则没有机会执行此处的三行代码
    -- 2、当上面执行pm.power(pm.WORK_MODE, 3)时，如果没有立即成功进入到PSM+模式，则会接着执行此处的三行代码
    --    在此处最多等待80秒，80秒内，如果成功进入了PSM+模式，则没有机会运行此处的rtos.reboot()软件重启代码
    --    如果超过了80秒，都没有成功进入PSM+模式，则此处会控制软件重启，
    --    重启后，根据本demo项目写的业务逻辑，会再次执行进入PSM+模式的逻辑
    --
    -- 此处为什么延时等待80秒，是因为从2025年3月份开始，对外发布的内核固件，在脚本中执行pm.power(pm.WORK_MODE, 3)时，
    -- 如果满足进入PSM+模式的条件，理论上会立即成功进入PSM+模式，
    -- 虽然如此，为了防止出现不可预知的错误，所以在内核固件中多加了一层保护机制，最长等待75秒钟一定会成功进入PSM+模式
    -- 所以在此处延时等待80秒，比75秒稍微长个5秒钟，为了让内核固件的这一层保护机制有时间运行，而不必执行此处的软件重启脚本代码
    -- 减少不必要的重启规避逻辑而带来的多余功耗
    --
    -- 这个是设置允许进入PSM+模式的标准操作，必须要与demo保持一致，加入这三行代码
    sys.wait(80000)
    log.info("psm_task", "进入PSM+失败，重启")
    rtos.reboot()
end


local function set_drv_psm()
    sys.taskInit(psm_task)
end


-- 根据项目的业务逻辑，在合适的位置sys.publish("DRV_SET_PSM")就可以配置最低功耗模式为PSM+模式
sys.subscribe("DRV_SET_PSM", set_drv_psm)