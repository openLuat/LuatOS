--[[
本功能模块演示的内容为：
使用Air8101开发板来演示errdump日志上报功能
使用手动读取异常日志并通过串口传出
]]



local function test_user_log()
    -- 下面演示手动获取异常日志信息,手动读取到异常日志可以上报到自己服务器，或者输出到串口。下面演示通过串口输出系统异常日志和用户记录日志数据，
    errDump.config(true, 0,nil,nil,"112.125.89.8",46463) --配置为手动读取，如果配置为自动上报将无法手动读取系统异常日志
    -- --初始化串口，用于输出读取到的错误日志
    local uartid = 1      -- 根据实际设备选取不同的uartid
    uart.setup(
        uartid,           --串口id
        115200,           --波特率
        8,                --数据位
        1                 --停止位
    )
    local buff = zbuff.create(4096)
    local new_flag = errDump.dump(buff, errDump.TYPE_SYS) -- 开机手动读取一次异常日志
    if buff:used() > 0 then
        log.info("errBuff",buff:toStr(0, buff:used())) -- 打印出异常日志
        uart.write(uartid, buff:toStr(0, buff:used()))
        --这里读取到的系统异常日志通过串口输出
    end
    new_flag = errDump.dump(buff, errDump.TYPE_SYS)
    if not new_flag then
        log.info("没有新数据了，删除系统错误日志")
        errDump.dump(nil, errDump.TYPE_SYS, true)
    end
    while true do
        sys.wait(15000)
        errDump.record("测试一下用户的记录功能") --写入用户的日志，注意最大只有4KB，超过部分新的覆盖旧的
        local new_flag = errDump.dump(buff, errDump.TYPE_USR)
        if new_flag then
            log.info("errBuff", buff:toStr(0, buff:used()))
            uart.write(uartid, buff:toStr(0, buff:used()))
            --这里读取到的用户写入日志通过串口输出
        end
        new_flag = errDump.dump(buff, errDump.TYPE_USR)
        if not new_flag then
            log.info("没有新数据了，删除用户错误日志")
            errDump.dump(nil, errDump.TYPE_USR, true)
        end
    end
end

local function test_error_log() --故意写错用来触发系统异常日志记录
	sys.wait(60000)
	lllllllllog.info("测试一下用户的记录功能") --默认写错代码死机
end



sys.taskInit(test_user_log) -- 启动errdemp测试任务
sys.taskInit(test_error_log)--启动错误函数任务
