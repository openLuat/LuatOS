--[[
@module  lora2_main
@summary lora2功能测试主模块
@version 1.0
@date    2025.11.24
@author  王世豪
@usage
本功能模块演示的内容为：
1. lora2设备初始化与配置
2. SPI接口初始化
3. 发送和接收参数配置
4. 事件回调处理
5. 发送和接收任务管理

本文件没有对外接口,直接在main.lua中require "lora2_main"就可以加载运行；
]]

-- 加载依赖模块
local lora2_sender = require "lora2_sender"
local lora2_receiver = require "lora2_receiver"

local TASK_NAME = "lora2_task"

local spi_id = 0 -- SPI接口ID
local pin_cs = 8 -- 片选引脚
local pin_reset = 1 -- 复位控制引脚
local pin_busy = 16 -- 忙状态指示引脚
local pin_dio1 = 17 -- DIO1引脚


local RECEIVE_TIMEOUT = 3000  -- 接收超时时间3秒

--[[
event值有：
    tx_done     -- 发送完成：数据已成功发送
    rx_done     -- 接收完成：成功接收到数据
    rx_timeout  -- 接收超时：在指定时间内未收到数据
    rx_error    -- 接收错误：接收过程中发生错误
__]]
function callback(lora_device, event, data, size)
    if event == "tx_done" then
        sys.sendMsg(TASK_NAME, "LORA_EVENT", "tx_done")
    elseif event == "rx_done" then
        sys.sendMsg(TASK_NAME, "LORA_EVENT", "rx_done", data, size)
    elseif event == "rx_timeout" then
        sys.sendMsg(TASK_NAME, "LORA_EVENT", "rx_timeout")
    elseif event == "rx_error" then
        sys.sendMsg(TASK_NAME, "LORA_EVENT", "rx_error")
    else
        log.warn("未知事件类型:", event)
    end
end

local function lora2_init()
    -- 初始化SPI
    spi_lora = spi_lora or spi.deviceSetup(spi_id,pin_cs,0,0,8,10*1000*1000,spi.MSB,1,0)
    if not spi_lora then
        log.error("spi_lora init failed")
        return false
    end

    -- 初始化LORA2设备
    -- 当前支持型号：llcc68, sx1268
    lora_device = lora_device or lora2.init("llcc68",{res = pin_reset,busy = pin_busy,dio1 = pin_dio1},spi_lora)
    if not lora_device then
        log.error("lora_device init failed")
        return false
    end
    log.info("lora_device",lora_device)

    -- 设置频道频率为433MHz
    lora_device:set_channel(433000000) 

    -- 配置 lora 设备的发送参数
    lora_device:set_txconfig({
        mode=1, 
        power=22,
        fdev=0,
        bandwidth=0,
        datarate=9,
        coderate=4,
        preambleLen=8,
        fixLen=false,
        crcOn=true,
        freqHopOn=0,
        hopPeriod=0,
        iqInverted=false
    })

    -- 配置 lora 设备的接收参数
    lora_device:set_rxconfig({
        mode=1,
        bandwidth=0,
        datarate=9,
        coderate=4,
        bandwidthAfc=0,
        preambleLen=8,
        symbTimeout=0,
        fixLen=false,
        payloadLen=0,
        crcOn=true,
        freqHopOn=0,
        hopPeriod=0,
        iqInverted=false,
        rxContinuous=false
    })

    return true
end

local function lora2_main_task_func()
    local result,msg

    while true do
        result = lora2_init()
        if not result then
            log.info("lora2_init error")
            goto EXCEPTION_PROC
        end

        -- 注册回调
        lora_device:on(callback)

        -- 默认初始化后启动接收
        lora_device:recv(RECEIVE_TIMEOUT)

        --- 发送设备就绪事件，将lora_device传递给sender模块
        sys.sendMsg(lora2_sender.TASK_NAME, "LORA_EVENT", "DEVICE_READY", lora_device) 

        while true do
            msg = sys.waitMsg(TASK_NAME, "LORA_EVENT")

            if msg[2]== "tx_done" then
                log.info("lora2_main", "发送完成")
                -- 通知sender模块发送完成
                sys.sendMsg(lora2_sender.TASK_NAME, "LORA_EVENT", "TX_DONE")
                -- 发送完成后启动接收
                lora_device:recv(RECEIVE_TIMEOUT)

            elseif msg[2]== "rx_done" then
                log.info("lora2_main", "接收完成", "数据长度:", msg[4])
                -- 交由receiver模块处理数据
                lora2_receiver.proc(msg[3], msg[4], lora_device)
                -- 处理完成后启动接收
                lora_device:recv(RECEIVE_TIMEOUT)

            elseif msg[2]== "rx_timeout" then
                log.info("lora2_main", "接收超时")
                -- 接收超时后继续接收
                lora_device:recv(RECEIVE_TIMEOUT)

                -- 接收过程中发生错误
            elseif msg[2]== "rx_error" then
                log.info("lora2_main", "接收错误")
                -- 接收错误后继续接收
                lora_device:recv(RECEIVE_TIMEOUT)
            end
        end
        
        -- 出现异常
        ::EXCEPTION_PROC::

        -- 清空此task绑定的消息队列中的未处理的消息
        sys.cleanMsg(TASK_NAME)

        sys.wait(5000)
    end
end

sys.taskInitEx(lora2_main_task_func, TASK_NAME)