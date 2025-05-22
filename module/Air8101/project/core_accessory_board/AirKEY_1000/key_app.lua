--[[
本功能模块演示的内容为：
使用Air8101核心板的GPIO中断检测AirKEY_1000配件板上8个独立按键的按下或者弹起状态
AirKEY_1000是合宙设计生产的一款8路独立按键的配件板
]]


--加载AirKEY_1000驱动文件
local air_key = require "AirKEY_1000"

--AirKEY_1000上8个按键对应的Air8101的GPIO ID
local KEY1_GPIO_ID = 49
local KEY2_GPIO_ID = 23
local KEY3_GPIO_ID = 21
local KEY4_GPIO_ID = 19
local KEY5_GPIO_ID = 51
local KEY6_GPIO_ID = 41
local KEY7_GPIO_ID = 26
local KEY8_GPIO_ID = 24


--按键1的中断处理函数
--int_level：number类型，表示触发中断后，某一时刻引脚的电平，1为高电平，0为低电平，并不一定是触发中断时的电平
--gpio_id：number类型，air_key.setup函数配置按键1时，对应的Air8101上的GPIO ID
--在中断处理函数中，不要直接执行耗时较长的动作，例如写fskv，写文件，延时等
--可以publish消息给其他协程或者给订阅消息的处理函数去执行耗时动作
local function key1_int_cbfunc(int_level, gpio_id)
    log.info("key1_int_cbfunc pressup", gpio_id, int_level)

    --如果需要执行耗时较长的动作，不要在这里直接执行
    --而是使用以下代码，publish一个消息出去，给其他协程或者给订阅消息的处理函数去执行耗时动作
    sys.publish("KEY1_PRESSUP_IND")
end

--按键2的中断处理函数
--int_level：number类型，表示触发中断后，某一时刻引脚的电平，1为高电平，0为低电平，并不一定是触发中断时的电平
--gpio_id：number类型，air_key.setup函数配置按键2时，对应的Air8101上的GPIO ID
--在中断处理函数中，不要直接执行耗时较长的动作，例如写fskv，写文件，延时等
--可以publish消息给其他协程或者给订阅消息的处理函数去执行耗时动作
local function key2_int_cbfunc(int_level, gpio_id)
    log.info("key2_int_cbfunc pressup", gpio_id, int_level)

    --如果需要执行耗时较长的动作，不要在这里直接执行
    --而是使用以下代码，publish一个消息出去，给其他协程或者给订阅消息的处理函数去执行耗时动作
    sys.publish("KEY2_PRESSUP_IND")
end

--按键3的中断处理函数
--int_level：number类型，表示触发中断后，某一时刻引脚的电平，1为高电平，0为低电平，并不一定是触发中断时的电平
--gpio_id：number类型，air_key.setup函数配置按键3时，对应的Air8101上的GPIO ID
--在中断处理函数中，不要直接执行耗时较长的动作，例如写fskv，写文件，延时等
--可以publish消息给其他协程或者给订阅消息的处理函数去执行耗时动作
local function key3_int_cbfunc(int_level, gpio_id)
    log.info("key3_int_cbfunc pressup", gpio_id, int_level)

    --如果需要执行耗时较长的动作，不要在这里直接执行
    --而是使用以下代码，publish一个消息出去，给其他协程或者给订阅消息的处理函数去执行耗时动作
    sys.publish("KEY3_PRESSUP_IND")
end

--按键4的中断处理函数
--int_level：number类型，表示触发中断后，某一时刻引脚的电平，1为高电平，0为低电平，并不一定是触发中断时的电平
--gpio_id：number类型，air_key.setup函数配置按键4时，对应的Air8101上的GPIO ID
--在中断处理函数中，不要直接执行耗时较长的动作，例如写fskv，写文件，延时等
--可以publish消息给其他协程或者给订阅消息的处理函数去执行耗时动作
local function key4_int_cbfunc(int_level, gpio_id)
    log.info("key4_int_cbfunc pressup", gpio_id, int_level)

    --如果需要执行耗时较长的动作，不要在这里直接执行
    --而是使用以下代码，publish一个消息出去，给其他协程或者给订阅消息的处理函数去执行耗时动作
    sys.publish("KEY4_PRESSUP_IND")
end


--按键5、6、7、8的中断处理函数
--int_level：number类型，表示触发中断后，某一时刻引脚的电平，1为高电平，0为低电平，并不一定是触发中断时的电平
--gpio_id：number类型，air_key.setup函数配置按键5、6、7、8时，对应的Air8101上的GPIO ID
--在中断处理函数中，不要直接执行耗时较长的动作，例如写fskv，写文件，延时等
--可以publish消息给其他协程或者给订阅消息的处理函数去执行耗时动作
local function key5678_int_cbfunc(int_level, gpio_id)
    log.info("key5678_int_cbfunc", gpio_id, int_level)

    --如果需要执行耗时较长的动作，不要在这里直接执行
    --而是使用以下代码，publish一个消息出去，给其他协程或者给订阅消息的处理函数去执行耗时动作
    if gpio_id==KEY5_GPIO_ID then
        log.info("key5 pressdown")
        sys.publish("KEY5_PRESSDOWN_IND")
    elseif gpio_id==KEY6_GPIO_ID then
        log.info("key6 pressdown")
        sys.publish("KEY6_PRESSDOWN_IND")
    elseif gpio_id==KEY7_GPIO_ID then
        log.info("key7 pressdown")
        sys.publish("KEY7_PRESSDOWN_IND")
    elseif gpio_id==KEY8_GPIO_ID then
        log.info("key8 pressdown")
        sys.publish("KEY8_PRESSDOWN_IND")
    end    
end



--本demo中，Air8101核心板和AirKEY_1000配件板的接线方式如下
--Air8101核心板             AirKEY_1000配件板
--     40/R1-----------------K1
--     39/R3-----------------K2
--     38/R5-----------------K3
--     37/R7-----------------K4
--     36/G1-----------------K5
--     35/G3-----------------K6
--     34/G5-----------------K7
--     33/G7-----------------K8
--       gnd-----------------G



--AirKEY_1000上的1、2、3、4，四个按键的引脚
--分别和Air8101的KEY1_GPIO_ID、KEY2_GPIO_ID、KEY3_GPIO_ID、KEY4_GPIO_ID四个引脚相连
--GPIO配置为上升沿触发中断，可以实时检测到按键弹起的动作
--按键弹起时，会执行对应的中断处理函数key1_int_cbfunc、key2_int_cbfunc、key3_int_cbfunc、key4_int_cbfunc
--在中断处理函数中，不要直接执行耗时较长的动作，例如写fskv，写文件，延时等
--可以publish消息给其他协程或者给订阅消息的处理函数去执行耗时动作
air_key.setup(1, KEY1_GPIO_ID, gpio.RISING, key1_int_cbfunc)
air_key.setup(2, KEY2_GPIO_ID, gpio.RISING, key2_int_cbfunc)
air_key.setup(3, KEY3_GPIO_ID, gpio.RISING, key3_int_cbfunc)
air_key.setup(4, KEY4_GPIO_ID, gpio.RISING, key4_int_cbfunc)

--AirKEY_1000上的5、6、7、8，四个按键的引脚
--分别和Air8101的KEY5_GPIO_ID、KEY6_GPIO_ID、KEY7_GPIO_ID、KEY8_GPIO_ID四个引脚相连
--GPIO配置为下降沿触发中断，可以实时检测到按键按下的动作
--按键按下时，会执行对应的中断处理函数key5678_int_cbfunc
--这四个按键共用了同一个中断处理函数，可以通过函数传入的GPIO ID来区分是哪一个按键被按下
--在中断处理函数中，不要直接执行耗时较长的动作，例如写fskv，写文件，延时等
--可以publish消息给其他协程或者给订阅消息的处理函数去执行耗时动作
air_key.setup(5, KEY5_GPIO_ID, gpio.FALLING, key5678_int_cbfunc)
air_key.setup(6, KEY6_GPIO_ID, gpio.FALLING, key5678_int_cbfunc)
air_key.setup(7, KEY7_GPIO_ID, gpio.FALLING, key5678_int_cbfunc)
air_key.setup(8, KEY8_GPIO_ID, gpio.FALLING, key5678_int_cbfunc)

