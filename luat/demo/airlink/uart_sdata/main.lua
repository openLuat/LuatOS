
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "airlink_uart"
VERSION = "1.0.1"

sys.taskInit(function()
    log.info("airlink", "Starting airlink with UART task")
    -- 首先, 初始化uart1, 115200波特率 8N1
    uart.setup(1, 115200)
    -- 初始化airlink
    airlink.init()
    -- 启动airlink uart任务
    airlink.start(2)

    while 1 do
        -- 发送给对端设备
        local data = rtos.bsp() .. " " .. os.date() .. " " .. (mobile and mobile.imei() or "")
        log.info("发送数据给对端设备", data, "当前airlink状态", airlink.ready())
        airlink.sdata(data)
        -- airlink.test(1000) -- 要测试高速连续发送的情况
        sys.wait(1000)
    end
end)

sys.subscribe("AIRLINK_SDATA", function(data)
    log.info("收到AIRLINK_SDATA!!", data)
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
