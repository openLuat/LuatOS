--[[
@module  drv_lowpower
@summary 低功耗模式pm.power(pm.WORK_MODE, 1)驱动配置功能模块
@version 1.0
@date    2026.02.09
@author  马梦阳
@usage
本文件为低功耗模式pm.power(pm.WORK_MODE, 1)驱动配置功能模块，提供了低功耗模式的配置模板，包括以下几点：
1、在进入低功耗模式前，根据自己的实际项目需求，配置进入低功耗模式后的中断唤醒方式；详情参考set_lowpower_interrupt_wakeup()实现
2、在进入低功耗模式前，根据自己的实际项目需求，配置一些必要的功能项；可以在满足项目功能需求的背景下，让功耗降到最低；详情参考set_lowpower_func_item()实现
3、配置最低功耗模式为低功耗模式；pm.power(pm.WORK_MODE, 1)


Air8000A/Air8000U/Air8000N/Air8000AB/Air8000W模组内部包含有WiFi芯片，GPIO23作为WiFi芯片的使能引脚，
默认状态下，GPIO23为高电平输出，在低功耗模式下,WiFi芯片部分的功耗表现为42uA左右，PSM+模式下，WiFi芯片部分的功耗表现为16uA左右，客户应根据实际项目需求进行配置
在低功耗模式示例代码中，并未对GPIO23进行配置，默认WiFi芯片是开启状态，以此演示低功耗模式下的实际功耗表现

Air8000A/Air8000U/Air8000N/Air8000AB/Air8000D/Air8000DB模组内部包含有GNSS和GSensor，GPIO24作为GNSS备电电源开关和GSensor电源开关
默认状态下，GPIO24为高电平，在低功耗模式和PSM+模式下，GNSS备电开启和Gsensor开启后，二者的功耗总和表现为783uA左右，客户应根据实际需求进行配置
在低功耗模式示例代码中，并未对GPIO24进行配置，默认状态下为高电平，以此演示低功耗模式下的实际功耗表现


2026.01.22：目前在低功耗模式时，4G内核固件存在缺陷，在低功耗模式下，会有一个1秒1次的电流波动，最终导致实际功耗较高，属于已知问题，正在解决中...

特别说明：
1、V2024 及之前的固件版本，4G芯片进入低功耗模式1后，WiFi芯片功耗表现较高，需要使用V2024以后的固件版本才能使得WiFi芯片达到42uA左右的功耗表现


本文件的对外接口只有1个：
1、sys.subscribe("DRV_SET_LOWPOWER", set_drv_lowpower)：订阅"DRV_SET_LOWPOWER"消息；
   其他应用模块如果需要配置低功耗模式，直接sys.publish("DRV_SET_LOWPOWER")这个消息即可；
]]

-- 获取当前使用的模组型号
local module = hmeta.model()

log.info("drv_lowpower", "当前使用的模组是：", module)


-- Air8000A/Air8000U/Air8000N/Air8000AB/Air8000D/Air8000DB模组WAKEUP2引脚内部用作GSensor中断信号，
-- 用户需要手动配置成中断方式才能实现GSensor的中断唤醒功能，除此之外不可作为其他功能使用
-- Air8000W/Air8000T模组WAKEUP2引脚并未被模组内部用作GSensor中断信号，可以作为普通中断功能
-- 
-- Air8000A/Air8000U/Air8000N/Air8000AB/Air8000W模组WAKEUP5引脚内部用于4G芯片与WiFi通信使用，外部不可再用
-- Air8000D/Air8000DB/Air8000T模组WAKEUP5引脚未被模组内部用作4G芯片与WiFi通信使用，可以作为普通中断功能
-- 
-- 在低功耗模式下，唤醒后会执行此处的中断处理函数
local function lowpower_wakeup_func(level, id)
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
    log.info("lowpower_wakeup_func", tag[id], level)
end


-- UART1的数据接收中断处理函数，UART1接收到数据时，会执行此函数
-- 此处仅仅简单的演示UART1唤醒后，读取UART1接收到的数据功能，更详细的用法参考单独的uart demo
-- 
-- 当配置波特率在9600及以下时，可正常接收每一包数据
-- 
-- 当配置波特率在9600以上时，模组在休眠状态下接收数据时会有丢失
-- 如何才能正确处理串口接收业务，建议采用以下操作流程：
-- 1、串口对端先发送1个字节的数据，例如发送“1”，此时会使模组唤醒，并触发UART1的数据接收中断回调（例如uart1_wakeup_read），回调函数中len为-1
-- 2、模组对“len == -1”进行判断，当len为-1时，切换到常规模式，开始准备接收数据，并向对端返回“lowpower wakeup\r\n”，用于告知对端模组已唤醒
-- 3、对端收到“lowpower wakeup\r\n”后，即可确认模组已唤醒，此时可以开始发送数据
-- 4、模组切换到常规模式后，通过while循环读取UART1接收到的数据，直到读取不到数据或者读取到的数据长度为0（回调中也做有拼接数据的处理，防止一包数据被拆分成多个小包）
-- 5、当业务处理完成后，可以通过调用 sys.publish("DRV_SET_LOWPOWER") 使其再次进入低功耗模式
-- 
-- 串口接收数据缓冲区
local read_buf = ""

local function concat_timeout_func()
    if read_buf:len() > 0 then
        -- uart.write(1, "len: " .. #read_buf .. " data: " .. read_buf .. "\r\n")
        read_buf = ""
    end
end

-- UART1的数据接收中断回调函数，UART1接收到数据时，会执行此函数
local function uart1_wakeup_read(_, len)
    if len == -1 then
        -- 切换到常规模式
        pm.power(pm.WORK_MODE, 0)
        -- 发送确认唤醒的消息
        uart.write(1, "lowpower wakeup\r\n")
    end

    local s
    while true do
        -- 非阻塞读取UART1接收到的数据，最长读取1024字节
        s = uart.read(1, 1024)

        -- 如果从串口没有读到数据
        if not s or s:len() == 0 then
            -- 启动50毫秒的定时器，如果50毫秒内没收到新的数据，则处理当前收到的所有数据
            -- 这样处理是为了防止将一大包数据拆分成多个小包来处理
            -- 例如pc端串口工具下发1100字节的数据，可能会产生将近20次的中断进入到read函数，才能读取完整
            -- 此处的50毫秒可以根据自己项目的需求做适当修改，在满足整包拼接完整的前提下，时间越短，处理越及时
            sys.timerStart(concat_timeout_func, 50)
            break
        end

        log.info("lowpower uart1_read len", s:len())
        -- log.info("lowpower uart1_wakeup_read", s, s:toHex())

        -- 拼接收到的数据到缓冲区
        read_buf = read_buf .. s
    end
end


-- 在进入低功耗模式前，根据自己的实际项目需求，配置低功耗模式下的中断唤醒方式
-- 
-- 低功耗模式下，Air8000A/Air8000U/Air8000N/Air8000AB/Air8000W支持以下几种类型的中断唤醒方式：
-- 1、PWR_KEY引脚中断
-- 2、CHG_DET(WAKEUP6)引脚中断
-- 3、WAKEUP0、WAKEUP2、WAKEUP3、WAKEUP4引脚中断
-- 4、VBUS(内部分压到WAKEUP1)引脚中断
-- 5、UART1_RXD引脚中断(需要将UART1配置为9600波特率)
-- 
-- Air8000D/Air8000DB/Air8000T支持以下几种类型的中断唤醒方式：
-- 1、PWR_KEY引脚中断
-- 2、CHG_DET(WAKEUP6)引脚中断
-- 3、WAKEUP0、WAKEUP2、WAKEUP3、WAKEUP4、WAKEUP5引脚中断
-- 4、VBUS(内部分压到WAKEUP1)引脚中断
-- 5、UART1_RXD引脚中断(需要将UART1配置为9600波特率)
-- 
-- 特别注意：当使用杜邦线短接/断开测试时，因为抖动因素，所以实际情况肯定会存在高低电平频繁跳变的情况！！！！！！
--          所以测试表现和实际的短接/断开动作并不完全相符，这种测试方法仅仅简单验证一下功能即可！！！！！！
--          最终自己设计的硬件产品并不会出现此问题
-- 特别注意：当配置引脚唤醒功能时，基于使用的硬件，配置之后，可能会增加系统功耗；本函数中基于Air8000系列每个模组的核心板给出了每项配置对功耗的影响数据
--          当使用自己的硬件测试时，以自己的硬件实测数据为准；Air8000系列每个模组的核心板的实测数据可以用来参考
local function set_lowpower_interrupt_wakeup()
    -- 下列三行代码为Air8000系列每个模组的通用AGPIO引脚
    -- 在接下来的中断唤醒功能测试中，有部分引脚可能需要短接3V3电平进行测试中断触发
    -- 由于Air8000系列每个模组的核心板都没有提供3V3电平输出引脚
    -- 因此需要使用其他引脚模拟3V3电平输出，之所以选择GPIO26、GPIO27、GPIO28引脚
    -- 是因为这三个引脚为通用AGPIO引脚，在低功耗模式下可以保持电平不变化
    -- 默认情况下，下列三行代码均未打开，如果需要用到3V3电平输出，则需要手动打开其中一个即可
    -- 
    -- 注意：当VBAT供电电压为3.8V时，GPIO26、GPIO27、GPIO28引脚高电平输出3.3V左右；
    --      当VBAT供电电压为3.3V时，GPIO26、GPIO27、GPIO28引脚高电平输出3.0V左右；
    -- gpio.setup(26, 1)    -- Air8000系列每个模组的核心板测试，没有增加功耗
    -- gpio.setup(27, 1)    -- Air8000系列每个模组的核心板测试，没有增加功耗
    -- gpio.setup(28, 1)    -- Air8000系列每个模组的核心板测试，没有增加功耗


    -- 配置PWR_KEY引脚下降沿、上升沿、双边沿中断唤醒（根据硬件设计原理以及项目需求，配置防抖之后，从中断唤醒方式中三选一）
    -- 防抖配置：200ms时长防抖，冷却模式（根据项目需求可以修改）
    -- 此处的代码基于合宙Air8000系列每个模组的核心板测试：
    --     由于PWR_KEY引脚内部已经拉高至VBAT电压，因此只能配置为gpio.PULLUP，不能配置为gpio.PULLDOWN
    --     当配置为gpio.PULLUP时，按下开机键产生下降沿，弹起开机键产生上升沿
    -- 在实际的项目中，可以根据自己的硬件设计原理以及项目需求，对此处的代码做适当修改
    -- 
    -- 特别注意：gpio.debounce接口设置的防抖功能，在不同功耗模式下表现不同：
    --          1、在常规模式0下，防抖功能有效，可以参考API详细说明，配置自己需要的防抖模式，实现“有效避免误触发”的效果
    --          2、在低功耗模式1下，休眠之后，防抖功能无效，根据自己配置的中断触发类型，只要满足条件就会立即触发中断，自动唤醒，并且执行中断处理函数
    --          3、在PSM+模式3下，休眠之后，防抖功能无效，根据自己配置的中断触发类型，只要满足条件就会立即触发中断，自动唤醒，并且重启软件
    -- gpio.debounce(gpio.PWR_KEY, 200)
    -- gpio.setup(gpio.PWR_KEY, lowpower_wakeup_func, gpio.PULLUP, gpio.FALLING)    -- Air8000系列每个模组的核心板测试，没有增加功耗
    -- gpio.setup(gpio.PWR_KEY, lowpower_wakeup_func, gpio.PULLUP, gpio.RISING)     -- Air8000系列每个模组的核心板测试，没有增加功耗
    -- gpio.setup(gpio.PWR_KEY, lowpower_wakeup_func, gpio.PULLUP, gpio.BOTH)       -- Air8000系列每个模组的核心板测试，没有增加功耗


    -- 配置CHG_DET(WAKEUP6)引脚下降沿、上升沿、双边沿中断唤醒（根据硬件设计原理以及项目需求，配置防抖之后，从中断唤醒方式中三选一）
    -- 防抖配置，目前是1000ms防抖（因为在核心板上使用杜邦线插拔测试，电平状态跳变频繁，所以防抖时间设置的较长，实际项目中根据自己的硬件设计和项目需求修改），冷却模式（根据项目需求可以修改）
    -- 此处的代码基于合宙Air8000系列每个模组的核心板测试：
    --     由于CHG_DET(WAKEUP6)引脚内部已经拉高至VDD_1.8V，因此只能配置为gpio.PULLUP，不能配置为gpio.PULLDOWN
    --     当配置为gpio.PULLUP时，将CHG_DET(WAKEUP6)引脚（对应的丝印为43/CHG_DET）和GND短接产生下降沿，和GND断开产生上升沿
    -- 在实际的项目中，可以根据自己的硬件设计原理以及项目需求，对此处的代码做适当修改
    -- 
    -- 特别注意：gpio.debounce接口设置的防抖功能，在不同功耗模式下表现不同：
    --          1、在常规模式0下，防抖功能有效，可以参考API详细说明，配置自己需要的防抖模式，实现“有效避免误触发”的效果
    --          2、在低功耗模式1下，休眠之后，防抖功能无效，根据自己配置的中断触发类型，只要满足条件就会立即触发中断，自动唤醒，并且执行中断处理函数
    --          3、在PSM+模式3下，休眠之后，防抖功能无效，根据自己配置的中断触发类型，只要满足条件就会立即触发中断，自动唤醒，并且重启软件
    -- gpio.debounce(gpio.CHG_DET, 1000)
    -- gpio.setup(gpio.CHG_DET, lowpower_wakeup_func, gpio.PULLUP, gpio.FALLING)    -- Air8000系列每个模组的核心板测试，没有增加功耗
    -- gpio.setup(gpio.CHG_DET, lowpower_wakeup_func, gpio.PULLUP, gpio.RISING)     -- Air8000系列每个模组的核心板测试，没有增加功耗
    -- gpio.setup(gpio.CHG_DET, lowpower_wakeup_func, gpio.PULLUP, gpio.BOTH)       -- Air8000系列每个模组的核心板测试，没有增加功耗


    -- 配置WAKEUP0引脚下降沿、上升沿、双边沿中断唤醒（根据硬件设计原理以及项目需求，配置防抖之后，从中断唤醒方式中六选一）
    -- 防抖配置，目前是1000ms防抖（因为在核心板上使用杜邦线插拔测试，电平状态跳变频繁，所以防抖时间设置的较长，实际项目中根据自己的硬件设计和项目需求修改），冷却模式（根据项目需求可以修改）
    -- 此处的代码基于合宙Air8000系列每个模组的核心板测试：
    --     当配置为gpio.PULLUP时，将WAKEUP0引脚（对应的丝印为44/WAKEUP0）和GND短接产生下降沿，和GND断开产生上升沿
    --     当配置为gpio.PULLDOWN时，将WAKEUP0引脚（对应的丝印为44/WAKEUP0）和3V3电平短接产生上升沿，和3V3电平断开产生下降沿
    -- 由于核心板上没有3V3引脚，所以我们需要使用其他引脚来模拟3V3电平，目前我们已经在set_lowpower_interrupt_wakeup()函数前几行中编写了对应的配置代码
    -- 客户只需要根据自己的实际项目需求，在需要用到3V3电平输出的时候手动打开配置代码即可
    -- 在客户实际的项目中，可以根据自己的硬件设计原理以及项目需求，对此处的代码做适当修改
    -- 
    -- 特别注意：gpio.debounce接口设置的防抖功能，在不同功耗模式下表现不同：
    --          1、在常规模式0下，防抖功能有效，可以参考API详细说明，配置自己需要的防抖模式，实现“有效避免误触发”的效果
    --          2、在低功耗模式1下，休眠之后，防抖功能无效，根据自己配置的中断触发类型，只要满足条件就会立即触发中断，自动唤醒，并且执行中断处理函数
    --          3、在PSM+模式3下，休眠之后，防抖功能无效，根据自己配置的中断触发类型，只要满足条件就会立即触发中断，自动唤醒，并且重启软件
    -- gpio.debounce(gpio.WAKEUP0, 1000)
    -- gpio.setup(gpio.WAKEUP0, lowpower_wakeup_func, gpio.PULLUP, gpio.FALLING)    -- Air8000系列每个模组的核心板测试，没有增加功耗
    -- gpio.setup(gpio.WAKEUP0, lowpower_wakeup_func, gpio.PULLUP, gpio.RISING)     -- Air8000系列每个模组的核心板测试，没有增加功耗
    -- gpio.setup(gpio.WAKEUP0, lowpower_wakeup_func, gpio.PULLUP, gpio.BOTH)       -- Air8000系列每个模组的核心板测试，没有增加功耗
    -- gpio.setup(gpio.WAKEUP0, lowpower_wakeup_func, gpio.PULLDOWN, gpio.FALLING)  -- Air8000系列每个模组的核心板测试，没有增加功耗
    -- gpio.setup(gpio.WAKEUP0, lowpower_wakeup_func, gpio.PULLDOWN, gpio.RISING)   -- Air8000系列每个模组的核心板测试，没有增加功耗
    -- gpio.setup(gpio.WAKEUP0, lowpower_wakeup_func, gpio.PULLDOWN, gpio.BOTH)     -- Air8000系列每个模组的核心板测试，没有增加功耗


    -- 配置VBUS(WAKEUP1)引脚下降沿、上升沿、双边沿中断唤醒（根据硬件设计原理以及项目需求，配置防抖之后，从中断唤醒方式中六选一）
    -- 防抖配置：200ms时长防抖，冷却模式（根据项目需求可以修改）
    -- 此处的代码基于合宙Air8000系列每个模组的核心板测试，将提供5V供电输入的USB线插入type-c座子，会产生上升沿，拔出会产生下降沿
    -- 在客户实际的项目中，可以根据自己的硬件设计原理以及项目需求，对此处的代码做适当修改
    -- 
    -- 特别注意：gpio.debounce接口设置的防抖功能，在不同功耗模式下表现不同：
    --          1、在常规模式0下，防抖功能有效，可以参考API详细说明，配置自己需要的防抖模式，实现“有效避免误触发”的效果
    --          2、在低功耗模式1下，休眠之后，防抖功能无效，根据自己配置的中断触发类型，只要满足条件就会立即触发中断，自动唤醒，并且执行中断处理函数
    --          3、在PSM+模式3下，休眠之后，防抖功能无效，根据自己配置的中断触发类型，只要满足条件就会立即触发中断，自动唤醒，并且重启软件
    -- gpio.debounce(gpio.WAKEUP1, 200)
    -- gpio.setup(gpio.WAKEUP1, lowpower_wakeup_func, gpio.PULLUP, gpio.FALLING)    -- Air8000系列每个模组的核心板测试，增加19uA功耗
    -- gpio.setup(gpio.WAKEUP1, lowpower_wakeup_func, gpio.PULLUP, gpio.RISING)     -- Air8000系列每个模组的核心板测试，增加19uA功耗
    -- gpio.setup(gpio.WAKEUP1, lowpower_wakeup_func, gpio.PULLUP, gpio.BOTH)       -- Air8000系列每个模组的核心板测试，增加19uA功耗
    -- gpio.setup(gpio.WAKEUP1, lowpower_wakeup_func, gpio.PULLDOWN, gpio.FALLING)  -- Air8000系列每个模组的核心板测试，没有增加功耗
    -- gpio.setup(gpio.WAKEUP1, lowpower_wakeup_func, gpio.PULLDOWN, gpio.RISING)   -- Air8000系列每个模组的核心板测试，没有增加功耗
    -- gpio.setup(gpio.WAKEUP1, lowpower_wakeup_func, gpio.PULLDOWN, gpio.BOTH)     -- Air8000系列每个模组的核心板测试，没有增加功耗


    -- 在Air8000系列模组中，Air8000A/Air8000U/Air8000N/Air8000AB/Air8000D/Air8000DB模组WAKEUP2引脚内部用作GSensor中断信号，
    -- 如果需要在低功耗模式下使用GSensor的中断唤醒功能，则需要根据下方说明打开对应的代码
    -- 
    -- Air8000W/Air8000T模组WAKEUP2引脚并未被模组内部用作GSensor中断信号，可以作为普通中断功能使用，配置方式见下一个配置项
    -- 
    -- 配置WAKEUP2引脚下降沿、上升沿、双边沿中断唤醒（根据硬件设计原理以及项目需求，配置防抖之后，从中断唤醒方式中三选一）
    -- 防抖配置：200ms时长防抖，冷却模式（根据项目需求可以修改）
    -- 此处的代码基于合宙Air8000系列内部包含GSensor的每个模组的核心板测试，WAKEUP2引脚已被模组内部用作GSensor中断信号，外部不可再用，否则会干扰GSensor的正常工作
    -- 在实际测试时，需要先引用exvib模块，再通过exvib.open(1)打开Air8000系列内部包含的三轴加速度传感器DA221，最后配置WAKEUP2引脚的中断唤醒功能
    -- 由于GSensor的电源开关通过Air8000系列内部包含Gsensor的模组的GPIO24控制，因此切记不要在其他地方对GPIO24进行二次配置，否则会干扰GSensor的正常工作
    -- 在客户实际的项目中，可以根据自己的硬件设计原理以及项目需求，对此处的代码做适当修改
    -- 
    -- 特别注意：gpio.debounce接口设置的防抖功能，在不同功耗模式下表现不同：
    --          1、在常规模式0下，防抖功能有效，可以参考API详细说明，配置自己需要的防抖模式，实现“有效避免误触发”的效果
    --          2、在低功耗模式1下，休眠之后，防抖功能无效，根据自己配置的中断触发类型，只要满足条件就会立即触发中断，自动唤醒，并且执行中断处理函数
    --          3、在PSM+模式3下，休眠之后，防抖功能无效，根据自己配置的中断触发类型，只要满足条件就会立即触发中断，自动唤醒，并且重启软件
    -- if module == "Air8000A" or module == "Air8000U" or module == "Air8000N" or module == "Air8000AB" or module == "Air8000D" or module == "Air8000DB" then
    --     -- 关于引用exvib模块，功耗数据变化的说明：
    --     exvib = require("exvib")    -- 引用exvib模块，如果其他地方没有将GPIO24拉低，此时功耗数据会增加783uA
    --     exvib.open(1)               -- 打开Air8000A内部的三轴加速度传感器DA221，库内自动将GPIO24拉高，此时功耗数据会增加783uA
    -- 
    --     -- 在测试下面的配置代码时，同时也需要把上面两行代码打开
    --     gpio.debounce(gpio.WAKEUP2, 200)
    --     -- gpio.setup(gpio.WAKEUP2, lowpower_wakeup_func, nil, gpio.FALLING)  -- Air8000系列内部包含GSensor的每个模组的核心板测试，增加783uA功耗
    --     -- gpio.setup(gpio.WAKEUP2, lowpower_wakeup_func, nil, gpio.RISING)   -- Air8000系列内部包含GSensor的每个模组的核心板测试，增加783uA功耗
    --     -- gpio.setup(gpio.WAKEUP2, lowpower_wakeup_func, nil, gpio.BOTH)     -- Air8000系列内部包含GSensor的每个模组的核心板测试，增加783uA功耗
    -- end
    -- 
    -- 
    -- 在Air8000系列模组中，除了Air8000A/Air8000U/Air8000N/Air8000AB/Air8000D/Air8000DB模组WAKEUP2引脚内部用作GSensor中断信号外
    -- Air8000W/Air8000T模组WAKEUP2引脚并未被模组内部用作GSensor中断信号，外部可以作为WAKEUP使用
    -- 如果需要在低功耗模式下使用WAKEUP2引脚的中断唤醒功能，则需要根据下方说明打开对应的代码
    -- 
    -- 配置WAKEUP2引脚下降沿、上升沿、双边沿中断唤醒（根据硬件设计原理以及项目需求，配置防抖之后，从中断唤醒方式中六选一）
    -- 防抖配置，目前是1000ms防抖（因为在核心板上使用杜邦线插拔测试，电平状态跳变频繁，所以防抖时间设置的较长，实际项目中根据自己的硬件设计和项目需求修改），冷却模式（根据项目需求可以修改）
    -- 此处的代码基于合宙Air8000系列每个模组内部不包含GSensor的核心板测试：
    --     当配置为gpio.PULLUP时，将WAKEUP2引脚（对应的丝印为78/WAKEUP2）和GND短接产生下降沿，和GND断开产生上升沿
    --     当配置为gpio.PULLDOWN时，将WAKEUP2引脚（对应的丝印为78/WAKEUP2）和3V3电平短接产生上升沿，和3V3电平断开产生下降沿
    -- 由于核心板上没有3V3引脚，所以我们需要使用其他引脚来模拟3V3电平，目前我们已经在set_lowpower_interrupt_wakeup()函数前几行中编写了对应的配置代码
    -- 客户只需要根据自己的实际项目需求，在需要用到3V3电平输出的时候手动打开配置代码即可
    -- 在客户实际的项目中，可以根据自己的硬件设计原理以及项目需求，对此处的代码做适当修改
    -- 
    -- 特别注意：gpio.debounce接口设置的防抖功能，在不同功耗模式下表现不同：
    --          1、在常规模式0下，防抖功能有效，可以参考API详细说明，配置自己需要的防抖模式，实现“有效避免误触发”的效果
    --          2、在低功耗模式1下，休眠之后，防抖功能无效，根据自己配置的中断触发类型，只要满足条件就会立即触发中断，自动唤醒，并且执行中断处理函数
    --          3、在PSM+模式3下，休眠之后，防抖功能无效，根据自己配置的中断触发类型，只要满足条件就会立即触发中断，自动唤醒，并且重启软件
    -- if module == "Air8000W" or module == "Air8000T" then
    --     gpio.debounce(gpio.WAKEUP2, 1000)
    --     -- gpio.setup(gpio.WAKEUP2, lowpower_wakeup_func, gpio.PULLUP, gpio.FALLING)    -- Air8000系列每个模组的核心板测试，没有增加功耗
    --     -- gpio.setup(gpio.WAKEUP2, lowpower_wakeup_func, gpio.PULLUP, gpio.RISING)     -- Air8000系列每个模组的核心板测试，没有增加功耗
    --     -- gpio.setup(gpio.WAKEUP2, lowpower_wakeup_func, gpio.PULLUP, gpio.BOTH)       -- Air8000系列每个模组的核心板测试，没有增加功耗
    --     -- gpio.setup(gpio.WAKEUP2, lowpower_wakeup_func, gpio.PULLDOWN, gpio.FALLING)  -- Air8000系列每个模组的核心板测试，没有增加功耗
    --     -- gpio.setup(gpio.WAKEUP2, lowpower_wakeup_func, gpio.PULLDOWN, gpio.RISING)   -- Air8000系列每个模组的核心板测试，没有增加功耗
    --     -- gpio.setup(gpio.WAKEUP2, lowpower_wakeup_func, gpio.PULLDOWN, gpio.BOTH)     -- Air8000系列每个模组的核心板测试，没有增加功耗
    -- end


    -- 配置WAKEUP3引脚下降沿、上升沿、双边沿中断唤醒（根据硬件设计原理以及项目需求，配置防抖之后，从中断唤醒方式中六选一）
    -- 防抖配置，目前是1000ms防抖（因为在核心板上使用杜邦线插拔测试，电平状态跳变频繁，所以防抖时间设置的较长，实际项目中根据自己的硬件设计和项目需求修改），冷却模式（根据项目需求可以修改）
    -- 此处的代码基于合宙Air8000系列每个模组的核心板测试，WAKEUP3引脚在核心板上与LED4相连接，用于控制LED4的亮灭：
    --     当配置为gpio.PULLUP时，将WAKEUP3引脚（对应的丝印为23/GPIO20）和GND短接产生下降沿，和GND断开产生上升沿
    --     当配置为gpio.PULLDOWN时，将WAKEUP3引脚（对应的丝印为23/GPIO20）和3V3电平短接产生上升沿，和3V3电平断开产生下降沿
    -- 由于核心板上没有3V3引脚，所以我们需要使用其他引脚来模拟3V3电平，目前我们已经在set_lowpower_interrupt_wakeup()函数前几行中编写了对应的配置代码
    -- 客户只需要根据自己的实际项目需求，在需要用到3V3电平输出的时候手动打开配置代码即可
    -- 在客户实际的项目中，可以根据自己的硬件设计原理以及项目需求，对此处的代码做适当修改
    -- 
    -- 注意：在实际测试中，如果测试结果不太理想，可以通过断开WAKEUP3引脚与LED4的连接，来排除LED4对WAKEUP3引脚中断唤醒功能的影响
    -- 
    -- 特别注意：gpio.debounce接口设置的防抖功能，在不同功耗模式下表现不同：
    --          1、在常规模式0下，防抖功能有效，可以参考API详细说明，配置自己需要的防抖模式，实现“有效避免误触发”的效果
    --          2、在低功耗模式1下，休眠之后，防抖功能无效，根据自己配置的中断触发类型，只要满足条件就会立即触发中断，自动唤醒，并且执行中断处理函数
    --          3、在PSM+模式3下，休眠之后，防抖功能无效，根据自己配置的中断触发类型，只要满足条件就会立即触发中断，自动唤醒，并且重启软件
    -- gpio.debounce(gpio.WAKEUP3, 1000)
    -- gpio.setup(gpio.WAKEUP3, lowpower_wakeup_func, gpio.PULLUP, gpio.FALLING)    -- Air8000系列每个模组的核心板测试，没有增加功耗
    -- gpio.setup(gpio.WAKEUP3, lowpower_wakeup_func, gpio.PULLUP, gpio.RISING)     -- Air8000系列每个模组的核心板测试，没有增加功耗
    -- gpio.setup(gpio.WAKEUP3, lowpower_wakeup_func, gpio.PULLUP, gpio.BOTH)       -- Air8000系列每个模组的核心板测试，没有增加功耗
    -- gpio.setup(gpio.WAKEUP3, lowpower_wakeup_func, gpio.PULLDOWN, gpio.FALLING)  -- Air8000系列每个模组的核心板测试，没有增加功耗
    -- gpio.setup(gpio.WAKEUP3, lowpower_wakeup_func, gpio.PULLDOWN, gpio.RISING)   -- Air8000系列每个模组的核心板测试，没有增加功耗
    -- gpio.setup(gpio.WAKEUP3, lowpower_wakeup_func, gpio.PULLDOWN, gpio.BOTH)     -- Air8000系列每个模组的核心板测试，没有增加功耗


    -- 配置WAKEUP4引脚下降沿、上升沿、双边沿中断唤醒（根据硬件设计原理以及项目需求，配置防抖之后，从中断唤醒方式中六选一）
    -- 防抖配置，目前是1000ms防抖（因为在核心板上使用杜邦线插拔测试，电平状态跳变频繁，所以防抖时间设置的较长，实际项目中根据自己的硬件设计和项目需求修改），冷却模式（根据项目需求可以修改）
    -- 此处的代码基于合宙Air8000A核心板测试，WAKEUP4引脚在核心板上与LED5相连接，用于控制LED5的亮灭：
    --     当配置为gpio.PULLUP时，将WAKEUP4引脚（对应的丝印为24/GPIO21）和GND短接产生下降沿，和GND断开产生上升沿
    --     当配置为gpio.PULLDOWN时，将WAKEUP4引脚（对应的丝印为24/GPIO21）和3V3电平短接产生上升沿，和3V3电平断开产生下降沿
    -- 由于核心板上没有3V3引脚，所以我们需要使用其他引脚来模拟3V3电平，目前我们已经在set_lowpower_interrupt_wakeup()函数前几行中编写了对应的配置代码
    -- 客户只需要根据自己的实际项目需求，在需要用到3V3电平输出的时候手动打开配置代码即可
    -- 在客户实际的项目中，可以根据自己的硬件设计原理以及项目需求，对此处的代码做适当修改
    -- 
    -- 注意：在实际测试中，如果测试结果不太理想，可以通过断开WAKEUP4引脚与LED5的连接，来排除LED5对WAKEUP4引脚中断唤醒功能的影响
    -- 
    -- 特别注意：gpio.debounce接口设置的防抖功能，在不同功耗模式下表现不同：
    --          1、在常规模式0下，防抖功能有效，可以参考API详细说明，配置自己需要的防抖模式，实现“有效避免误触发”的效果
    --          2、在低功耗模式1下，休眠之后，防抖功能无效，根据自己配置的中断触发类型，只要满足条件就会立即触发中断，自动唤醒，并且执行中断处理函数
    --          3、在PSM+模式3下，休眠之后，防抖功能无效，根据自己配置的中断触发类型，只要满足条件就会立即触发中断，自动唤醒，并且重启软件
    -- gpio.debounce(gpio.WAKEUP4, 1000)
    -- gpio.setup(gpio.WAKEUP4, lowpower_wakeup_func, gpio.PULLUP, gpio.FALLING)    -- Air8000系列每个模组的核心板测试，增加14uA功耗
    -- gpio.setup(gpio.WAKEUP4, lowpower_wakeup_func, gpio.PULLUP, gpio.RISING)     -- Air8000系列每个模组的核心板测试，增加14uA功耗
    -- gpio.setup(gpio.WAKEUP4, lowpower_wakeup_func, gpio.PULLUP, gpio.BOTH)       -- Air8000系列每个模组的核心板测试，增加14uA功耗
    -- gpio.setup(gpio.WAKEUP4, lowpower_wakeup_func, gpio.PULLDOWN, gpio.FALLING)  -- Air8000系列每个模组的核心板测试，没有增加功耗
    -- gpio.setup(gpio.WAKEUP4, lowpower_wakeup_func, gpio.PULLDOWN, gpio.RISING)   -- Air8000系列每个模组的核心板测试，没有增加功耗
    -- gpio.setup(gpio.WAKEUP4, lowpower_wakeup_func, gpio.PULLDOWN, gpio.BOTH)     -- Air8000系列每个模组的核心板测试，没有增加功耗


    -- 在Air8000系列模组中，Air8000A/Air8000U/Air8000N/Air8000AB/Air8000W模组内部包含有WiFi芯片
    -- WAKEUP5引脚已被Air8000系列内部包含WiFi芯片的每个模组内部用作主控与WiFi芯片通信使用，作为airlink_rdy脚，用于判断从机设备是否就绪
    -- 外部不可再用，否则会干扰WiFi的正常工作，在客户实际的项目中，应避免操作WAKEUP5引脚
    -- 
    -- 
    -- 在Air8000系列模组中，除了Air8000A/Air8000U/Air8000N/Air8000AB/Air8000W模组内部包含有WiFi芯片外
    -- Air8000D/Air8000DB/Air8000T模组内部不包含WiFi芯片，对应模组的WAKEUP5引脚可以作为WAKEUP引脚使用
    -- 如果需要在低功耗模式下使用WAKEUP5的中断唤醒功能，则需要根据下方说明打开对应的代码
    -- 配置WAKEUP5引脚下降沿、上升沿、双边沿中断唤醒（根据硬件设计原理以及项目需求，配置防抖之后，从中断唤醒方式中六选一）
    -- 防抖配置，目前是1000ms防抖（因为在核心板上使用杜邦线插拔测试，电平状态跳变频繁，所以防抖时间设置的较长，实际项目中根据自己的硬件设计和项目需求修改），冷却模式（根据项目需求可以修改）
    -- 此处的代码基于合宙Air8000系列每个模组内部不包含WiFi芯片的核心板测试：
    --     当配置为gpio.PULLUP时，将WAKEUP5引脚（对应的丝印为88/WAKEUP5）和GND短接产生下降沿，和GND断开产生上升沿
    --     当配置为gpio.PULLDOWN时，将WAKEUP5引脚（对应的丝印为88/WAKEUP5）和3V3电平短接产生上升沿，和3V3电平断开产生下降沿
    -- 由于核心板上没有3V3引脚，所以我们需要使用其他引脚来模拟3V3电平，目前我们已经在set_lowpower_interrupt_wakeup()函数前几行中编写了对应的配置代码
    -- 客户只需要根据自己的实际项目需求，在需要用到3V3电平输出的时候手动打开配置代码即可
    -- 在客户实际的项目中，可以根据自己的硬件设计原理以及项目需求，对此处的代码做适当修改
    -- 
    -- 特别注意：gpio.debounce接口设置的防抖功能，在不同功耗模式下表现不同：
    --          1、在常规模式0下，防抖功能有效，可以参考API详细说明，配置自己需要的防抖模式，实现“有效避免误触发”的效果
    --          2、在低功耗模式1下，休眠之后，防抖功能无效，根据自己配置的中断触发类型，只要满足条件就会立即触发中断，自动唤醒，并且执行中断处理函数
    --          3、在PSM+模式3下，休眠之后，防抖功能无效，根据自己配置的中断触发类型，只要满足条件就会立即触发中断，自动唤醒，并且重启软件
    -- if module == "Air8000D" or module == "Air8000DB" or module == "Air8000T" then
    --     gpio.debounce(gpio.WAKEUP5, 1000)
    --     -- gpio.setup(gpio.WAKEUP5, lowpower_wakeup_func, gpio.PULLUP, gpio.FALLING)    -- Air8000系列每个模组内部不包含WiFi芯片的核心板测试，没有增加功耗
    --     -- gpio.setup(gpio.WAKEUP5, lowpower_wakeup_func, gpio.PULLUP, gpio.RISING)     -- Air8000系列每个模组内部不包含WiFi芯片的核心板测试，没有增加功耗
    --     -- gpio.setup(gpio.WAKEUP5, lowpower_wakeup_func, gpio.PULLUP, gpio.BOTH)       -- Air8000系列每个模组内部不包含WiFi芯片的核心板测试，没有增加功耗
    --     -- gpio.setup(gpio.WAKEUP5, lowpower_wakeup_func, gpio.PULLDOWN, gpio.FALLING)  -- Air8000系列每个模组内部不包含WiFi芯片的核心板测试，没有增加功耗
    --     -- gpio.setup(gpio.WAKEUP5, lowpower_wakeup_func, gpio.PULLDOWN, gpio.RISING)   -- Air8000系列每个模组内部不包含WiFi芯片的核心板测试，没有增加功耗
    --     -- gpio.setup(gpio.WAKEUP5, lowpower_wakeup_func, gpio.PULLDOWN, gpio.BOTH)     -- Air8000系列每个模组内部不包含WiFi芯片的核心板测试，没有增加功耗
    -- end


    -- 配置9600波特率的UART1_RXD接收到数据唤醒（必须配置为9600波特率，这样可以保证唤醒的同时，还能接收到完整的数据）
    -- 此处仅仅简单的演示UART1唤醒功能的配置，更详细的用法参考单独的uart demo
    -- 初始化UART1，波特率9600，数据位8，停止位1
    -- 基于合宙Air8000系列每个核心板测试，将UART1引脚（对应的丝印为17/U1RXD、16/U1TXD、GND）通过USB转TTL串口线和电脑相连，电脑串口工具配置9600波特率，数据位8，停止位1，串口工具发送任何数据都可以唤醒模组
    -- uart.setup(1, 9600, 8, 1)
    -- 注册UART1的数据接收中断处理函数，UART1接收到数据时，会执行uart1_wakeup_read函数
    -- uart.on(1, "receive", uart1_wakeup_read)
end



-- Air8000A/Air8000U/Air8000N/Air8000AB/Air8000D/Air8000DB模组内部包含有GNSS和GSensor
-- Air8000A/Air8000U/Air8000N/Air8000AB/Air8000W模组内部包含有WiFi芯片
-- Air8000T模组内部既不包含GNSS和GSensor，又不包含WiFi芯片
-- set_lowpower_func_item()中会自动对模组型号进行判断，避免对不包含WiFi芯片或者GNSS和GSensor进行误配置
-- 在进入低功耗模式前，根据自己的实际项目需求，配置一些必要的功能项，可以在满足项目功能需求的背景下，让功耗降到最低
local function set_lowpower_func_item()
    -- 第一类功能配置项：飞行模式
    -- 通过配置飞行模式可以有效关闭4G芯片的4G网络能力
    -- 
    -- 这个功能的特性是：
    -- 1、在常规模式下，飞行模式默认是关闭的，可以根据项目需要显式的开启飞行模式，从而关闭4G网络能力
    -- 2、在低功耗模式下，飞行模式默认也是关闭的，需要根据项目需要显式的开启飞行模式，从而关闭4G网络能力，关闭后可以有效降低功耗
    -- 3、在PSM+模式下，飞行模式默认是开启的，不能显式的关闭飞行模式
    -- 根据自己的项目需求决定：进入低功耗模式前，是否需要进入飞行模式
    -- 一旦进入飞行模式，意味着无法使用4G网络，无法和自己的业务服务器保持连接和收发数据
    -- 此处代码默认没有进入飞行模式；如果需要进入飞行模式，打开下面的一行代码
    -- 在vbat供电3.8v的状态下，进入飞行模式，可以减少1mA到1.5mA的功耗（和天线性能以及网络环境有关系，以自己的实际硬件+实际网络环境测试数据为准）
    -- 在关闭其他功能的情况下，飞行模式+低功耗状态，待机电流在40多uA到70多uA左右
    -- mobile.flymode(0, true)



    -- 第二类功能配置项：USB功能
    -- 通过USB功能可以实现抓日志和业务数据通信等
    -- 
    -- 这个功能的特性是：
    -- 1、在常规模式下，USB功能是默认开启的，通过USB虚拟串口进行抓日志和业务数据通信等
    -- 2、在低功耗模式和PSM+模式下，此时USB功能默认是关闭的，无法使用USB虚拟串口进行抓日志和业务数据通信等
    -- 根据自己的项目需求决定：进入低功耗模式前，是否需要关闭USB供电电源
    -- 从2025年3月份发布的内核固件开始：
    -- 1、在pm.power(pm.WORK_MODE, 1)和pm.power(pm.WORK_MODE, 3)中会自动执行pm.power(pm.USB, false)关闭USB功能
    -- 2、在pm.power(pm.WORK_MODE, 0)会自动执行pm.power(pm.USB, true)打开USB功能
    -- 所以，如果你使用的内核固件如果是2025年3月份之后发布的，则不再需要显式的关闭USB功能，在低功耗模式中会自动关闭USB功能
    -- 此处代码默认没有显式的关闭USB功能，是因为在后续的pm.power(pm.WORK_MODE, 1)中会自动关闭USB功能
    -- 如果由于某种原因，你必须使用2025年3月份之前的内核固件，则根据需求可以打开下面的一行代码
    -- 在vbat供电3.8v的状态下，关闭USB功能，可以减少140uA到200uA左右的功耗
    -- pm.power(pm.USB, false)



    -- 第三类功能配置项：WiFi功能
    -- 这一类功能配置项仅对Air8000A/Air8000U/Air8000N/Air8000AB/Air8000W模组有效，Air8000D/Air8000DB/Air8000T模组内部不包含WiFi芯片，无法使用WiFi功能
    -- Air8000A/Air8000U/Air8000N/Air8000AB/Air8000W模组内部包含有WiFi芯片，通过WiFi芯片可以实现如下功能：
    -- 1、WiFi STA/AP功能
    -- 2、WiFi芯片端的GPIO引脚可以配置为输入、输出、中断唤醒，用于与外部设备进行通信
    -- 3、WiFi芯片端的UART引脚可以配置为任意支持的波特率，用于与外部设备进行通信
    -- 
    -- 这三类功能的特性是：
    -- WiFi：在进入低功耗模式休眠之前如果配置了WiFi STA/AP功能，那么在进入休眠后可以保持之前的WiFi STA/AP功能，但是由于4G芯片与WiFi芯片之间的
    --       SPI通信会被断开，因此4G芯片端无法对WiFi芯片进行任何操作，所以在实际项目中无任何意义
    --       在进入PSM+模式休眠之后，WiFi芯片端的WiFi网络会被完全关闭（这里指的是WiFi STA/AP功能，而不是WiFi芯片被关闭）
    -- UART：在进入低功耗模式或者PSM+模式休眠之后，不会保持之前的UART配置参数，UART收发功能无法使用
    -- GPIO：在进入低功耗模式或者PSM+模式休眠之前如果配置了输入、输出、中断唤醒功能，那么在进入休眠后可以保持之前的配置参数，但是4G芯片与WiFi芯片之间的
    --       SPI通信会被断开，因此输入功能在实际项目中无任何意义，中断唤醒功能可以认为是不支持，只有输出功能可以正常使用，不过在配置输出功能时需要配置软件上/下拉，
    --       否则在进入休眠后无法保持之前的配置参数
    -- 
    -- 从2025年7月份发布的内核固件开始：
    -- 1、在pm.power(pm.WORK_MODE, 1)和pm.power(pm.WORK_MODE, 3)中会自动将WiFi芯片配置为对应的休眠模式
    -- 2、在pm.power(pm.WORK_MODE, 0)会将WiFi芯片自动重启，配置参数会被重置为默认值
    --
    -- 根据自己的项目需求决定：进入低功耗模式前，WiFi芯片是否需要内核固件自动配置为对应的休眠模式还是手动直接关闭WiFi芯片；
    -- 如果只是让内核固件自动配置为对应的休眠模式，那么仅仅是关闭4G芯片与WiFi芯片之间的SPI通信，4G芯片无法再继续操作WiFi芯片了
    -- 不过在进入休眠模式前对WiFi芯片的配置不会受到任何影响
    -- 如果是直接手动关闭WiFi芯片，那么WiFi芯片端的任何功能都将无法使用，如果需要手动关闭，则打开下面这行代码
    -- pm.power(pm.WIFI, 0)是从2025年12月份发布的内核固件开始新增的配置方法
    -- 如果由于某种原因，你必须使用2025年12月份之前的内核固件，则需要通过gpio.setup(23, nil, gpio.PULLDOWN)关闭WiFi芯片
    --
    -- 关闭WiFi芯片后可以减少42uA左右的功耗
    --
    -- 总之：如果在进入低功耗模式1之后，还要使用ID为100以上的GPIO输出保持功能，则将此处下面的几行代码注释掉，不要彻底关闭WiFi芯片，但是会增加42uA左右的功耗
    --       如果在进入低功耗模式1之后，不需要使用ID为100以上的GPIO、UART11、UART12、WiFi数传功能，则打开下面几行代码，彻底关闭WiFi芯片，会减少42uA左右的功耗
    -- if module == "Air8000A" or module == "Air8000U" or module == "Air8000N" or module == "Air8000AB" or module == "Air8000W" then
    --     if pm.WIFI then
    --         pm.power(pm.WIFI, 0)
    --     else
    --         gpio.setup(23, nil, gpio.PULLDOWN)
    --     end
    -- end



    -- 第四类功能配置项：GNSS备电电源开关及GSensor电源开关
    -- 这一类功能配置项仅对Air8000A/Air8000U/Air8000N/Air8000AB/Air8000D/Air8000DB模组有效，Air8000W/Air8000T模组内部不包含GNSS和GSensor，无法使用该功能
    -- Air8000A/Air8000U/Air8000N/Air8000AB/Air8000D/Air8000DB模组内部包含有GNSS和GSensor
    -- 通过GPIO24作为GNSS的备电电源开关和GSensor的电源开关，默认为高电平输出
    -- 
    -- 这个功能引脚输出的电平状态，对GNSS和Gsensor功能的影响是：
    -- GNSS：在低功耗模式或者PSM+模式下，
    --       如果GPIO24输出高电平，可以保证GNSS的定位数据不被丢失，
    --                            并且在关闭GNSS后两个小时内，在室外空旷环境下，再次打开GNSS时，可以热启动3s左右快速获取到定位数据；
    --                            但是如果超过两个小时之后，再次打开GNSS，就是冷启动状态，35s左右才能获取到定位数据；
    --       如果GPIO24输出低电平，此时GNSS的备电电源开关是关闭的，下次打开GNSS时，就是冷启动状态，35s左右才能获取到定位数据；
    --       客户可以根据项目需求来配置GPIO24的电平状态
    -- GSensor：在低功耗模式或者PSM+模式下，
    --          如果GPIO24输出高电平，GSensor的电源开关处于打开状态，那么可以通过GSensor的中断唤醒脚（WAKEUP2）来实现震动中断唤醒功能；
    --          如果GPIO24输出低电平，GSensor的电源开关处于关闭状态，那么无法使用GSensor的任何功能；
    --
    -- 所以，在实际的项目设计中，如果需要工作在低功耗模式或者PSM+模式下，
    -- 可能你会打开GNSS的备电电源开关和GSensor的电源开关，用于保存GNSS的定位数据和快速获取定位数据或者实现GSensor的震动中断唤醒功能
    -- 根据自己的项目需求决定：进入低功耗模式前，是否需要关闭GNSS的备电电源开关和GSensor的电源开关
    -- 此处默认使用的是配置为输入下拉的方式来关闭，默认代码没有打开，这行代码打开后可以减少783uA左右的功耗
    -- if module == "Air8000A" or module == "Air8000U" or module == "Air8000N" or module == "Air8000AB" or module == "Air8000D" or module == "Air8000DB" then
    --     gpio.setup(24, nil, gpio.PULLDOWN)
    -- end



    -- 第五类功能配置项：通用AGPIO（GPIO26、GPIO27、GPIO28）
    -- 这三个功能引脚在Air8000系列每个模组内部并没有被占用，所以用户在项目开发中可以根据自己的项目需求来使用任何一个引脚
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
    -- 根据自己的项目需求决定：进入低功耗模式前，来关闭AGPIO（GPIO26、GPIO27、GPIO28）控制的电路单元的功耗
    -- 一旦关闭，如果你项目中使用了这些功能引脚，意味着这些功能引脚有关的功能将无法正常工作，例如无法为外围电路提供上拉
    -- 此处默认使用的是配置为输入下拉的方式来关闭，默认代码已经注释掉了，如果默认不配置的状态可以满足需求（实际测试一下功耗），就可以不用代码控制，默认什么动作都不处理即可
    -- 如果打开这里的默认配置代码可以满足需求（实际测试一下功耗），就可以直接打开使用
    -- 如果无法满足需求，需要根据自己的电路设计，来决定如何关闭（什么都不处理，输出低电平，输出高电平，close，输入下拉，输入上拉，六种方式中的一种）；
    -- 具体使用何种方式，需要结合自己的硬件来实际测试，选取功耗最低的一种即可
    -- 可以在此处关闭，也可以在具体的外围电路软件功能模块代码文件中关闭
    -- gpio.setup(26, nil, gpio.PULLDOWN)
    -- gpio.setup(27, nil, gpio.PULLDOWN)
    -- gpio.setup(28, nil, gpio.PULLDOWN)



    -- 第六类功能配置项：通用WAKEUP（WAKEUP0）
    -- 这一个功能引脚在Air8000系列每个模组内部并没有被占用，所以用户在项目开发中可以根据自己的项目需求来使用这个引脚
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



    -- 第七类功能配置项：VBUS（WAKEUP1）
    -- 这个是VBUS功能引脚，在Air8000系列每个模组内部经分压后接WAKEUP1，固定只能用作USB插入检测使用
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



    -- 第八类功能配置项：AGPIOWU（GPIO20/WAKEUP3、GPIO21/WAKEUP4、GPIO22/WAKEUP5）
    -- 在Air8000系列模组中，Air8000A/Air8000U/Air8000N/Air8000AB/Air8000W模组内部包含有WiFi芯片
    -- WAKEUP5引脚已被Air8000系列内部包含WiFi芯片的每个模组内部用作主控与WiFi芯片通信使用，作为airlink_rdy脚，用于判断从机设备是否就绪
    -- 只剩下WAKEUP3、WAKEUP4这两个引脚没有被占用，所以用户可以根据自己的项目需求来使用这两个引脚
    -- 
    -- 除了上面所说的型号之外，Air8000D/Air8000DB/Air8000T模组内部不包含WiFi芯片，对应模组的WAKEUP5引脚可以作为WAKEUP引脚使用
    -- 这三个功能引脚在Air8000D/Air8000DB/Air8000T模组内部并没有被占用，所以用户在项目开发中可以根据自己的项目需求来使用任何一个引脚
    -- 
    -- 这些功能引脚的特性是：
    -- 1、软件上既可以配置做为AGPIO使用，也可以配置做为WAKEUP使用
    -- 2、做AGPIO使用时，功能特性以及如何配置可以将功耗降到最低，参考上文中“第三类功能配置项：通用AGPIO”的说明
    -- 3、做WAKEUP使用时，功能特性以及如何配置可以将功耗降到最低，参考上文中“第四类功能配置项：通用WAKEUP”的说明
    -- if module == "Air8000A" or module == "Air8000U" or module == "Air8000N" or module == "Air8000AB" or module == "Air8000W" then
    --     -- gpio.setup(gpio.WAKEUP3, nil, gpio.PULLDOWN)
    --     -- gpio.setup(gpio.WAKEUP4, nil, gpio.PULLDOWN)
    -- elseif module == "Air8000D" or module == "Air8000DB" or module == "Air8000T" then
    --     -- gpio.setup(gpio.WAKEUP3, nil, gpio.PULLDOWN)
    --     -- gpio.setup(gpio.WAKEUP4, nil, gpio.PULLDOWN)
    --     -- gpio.setup(gpio.WAKEUP5, nil, gpio.PULLDOWN)
    -- end



    -- 第九类功能配置项：PWR_KEY
    -- 这个是PWRKEY开机键功能引脚，这个功能引脚的特性是：
    -- 1、如果PWRKEY接地，模组上电即开机；如果PWRKEY不接地，模组上电后，此引脚检测到下降沿就可以开机
    -- 2、开机运行之后：
    --    (1) 在常规功耗模式下，可以做为中断使用，可以配置中断处理函数处理业务逻辑
    --    (2) 在低功耗模式下，也可以作为中断使用，可以配置中断处理函数处理业务逻辑
    --    (3) 在PSM+模式下，也可以作为中断使用，虽然可以配置中断处理函数，但是仅仅做为唤醒功能使用，一旦唤醒，软件系统会直接重启，并不会执行中断处理函数
    -- 所以，在实际的项目设计中，如果需要工作在低功耗模式或者PSM+模式下，可能你会使用这个引脚的中断唤醒功能
    -- 需要提醒的是，PWR_KEY引脚如果硬件设计为接地自动开机，通常会增加系统功耗；以Air8000系列每个模组的核心板为例，如果一直按下开机键，则会增加系统功耗15uA左右
    -- 根据自己的项目需求决定：进入低功耗模式前，是否需要关闭PWR_KEY功能
    -- 一旦关闭，如果你项目中使用了这个功能引脚，意味着这个功能引脚有关的功能将无法正常工作，例如无法中断唤醒
    -- gpio.setup(gpio.PWR_KEY, nil, gpio.PULLDOWN)


    -- 第十类功能配置项：CHG_DET（WAKEUP6）
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
    -- 根据自己的项目需求决定：进入低功耗模式前，是否需要关闭CHG_DET（WAKEUP6）功能
    -- 一旦关闭，如果你项目中使用了这个功能引脚，意味着这个功能引脚有关的功能将无法正常工作，例如无法中断唤醒
    -- gpio.setup(gpio.CHG_DET, nil, gpio.PULLDOWN)
end


local function lowpower_task()
    log.info("lowpower_task enter")

    -- 在进入低功耗模式前，根据自己的实际项目需求，配置进入低功耗模式后的中断唤醒方式
    -- 一定要仔细阅读这个函数的代码注释说明，根据自己的项目需求来决定是否需要配置每一项功能
    -- 注意：如果在此处配置了某些引脚，就不要在接下来的set_lowpower_func_item()函数中关闭对应的引脚功能，否则会导致配置失效
    -- 例如，如果在此函数中配置了WAKEUP0引脚中断唤醒，则在set_lowpower_func_item()中就不要关闭WAKEUP0引脚功能
    set_lowpower_interrupt_wakeup()


    -- 在进入低功耗模式前，根据自己的实际项目需求，配置一些必要的功能项
    -- 可以在满足项目功能需求的背景下，让功耗降到最低
    -- 一定要仔细阅读这个函数的代码注释说明，根据自己的项目需求来决定是否需要配置每一项功能
    set_lowpower_func_item()


    -- 延时10秒钟，是为了使用USB抓取日志
    -- 仅仅开发调试过程中需要，量产前不需要
    -- sys.wait(10000)


    -- 配置最低功耗模式为低功耗模式
    -- 执行下面这行代码后，只是配置了允许系统进入低功耗模式
    -- 并不是说，一定会立即进低功耗模式，最终进入低功耗模式的时间点，取决于内核固件中的任务和Lua脚本中task都处于阻塞状态
    -- 也就是说，执行这一行代码时：
    -- (1) 如果内核固件中的任务和Lua脚本中task都处于阻塞状态，理论上就会立即成功进入低功耗模式
    -- (2) 否则，不会立即成功进入低功耗模式，而是等待所有运行中的任务处于阻塞状态；
    --     假设5秒钟之后，满足了条件，则5秒钟之后会成功进入低功耗模式；
    -- 
    -- 在配置最低功耗模式为低功耗模式之后，无论是否成功进入低功耗模式：
    -- 用户编写的任何脚本代码的主动业务逻辑都会正常运行，代码运行过程中就会自动唤醒，代码阻塞后又会自动进入低功耗状态
    --
    -- 使用合宙核心板测试的低功耗模式功耗数据，在vbat供电3.8v状态下
    -- 飞行模式+低功耗+配置set_lowpower_func_item()中的所有功能项：66uA左右（40uA到70uA左右都属于正常值）
    -- 低功耗+set_lowpower_func_item()中的所有功能项(飞行模式除外)：1mA到1.5mA左右（和天线性能以及网络环境有关系，以自己的实际硬件+实际网络环境测试数据为准）
    pm.power(pm.WORK_MODE, 1)

    -- 在低功耗模式下，默认会关闭USB功能，这样会降低140uA到200uA左右的功耗
    -- 所以默认无法使用USB端口抓日志，可以使用DBG_UART(即UART0)端口+EPAT工具+USB转TTL高速线+6000000波特率来抓日志
    -- 也可以在开发调试过程中，打开下面这行代码，重新打开USB功能，使用USB端口+Luatools抓日志，代价就是无法测量准确的功耗
    -- 等到调试OK之后，项目软件量产前再关掉这行代码，完整测试一遍项目的所有功能，保证最终量产状态下的项目稳定性
    -- pm.power(pm.USB, true)
end


local function set_drv_lowpower()
    sys.taskInit(lowpower_task)
end


-- 根据项目的业务逻辑，在合适的位置sys.publish("DRV_SET_LOWPOWER")就可以配置最低功耗模式为低功耗模式
sys.subscribe("DRV_SET_LOWPOWER", set_drv_lowpower)

-- 如果项目启动之后，最低功耗模式需要一直配置为低功耗模式，则可以直接打开下面这一行代码，相当于开机初始化时，就配置最低功耗模式为低功耗模式
--
-- 如果项目不需要初始化为低功耗模式，或者在项目运行过程中，在不同的功耗模式之间手动切换，
-- 则可以根据需求，注释掉下面的一行代码，根据自己的业务逻辑，在合适的位置sys.publish("DRV_SET_LOWPOWER")即可配置为最低功耗模式为低功耗模式
-- sys.publish("DRV_SET_LOWPOWER")