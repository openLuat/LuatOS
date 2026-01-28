--[[
@module  errdump_read
@summary errdump手动读取功能模块
@version 1.0
@date    2025.09.05
@author  孟伟
@usage
本功能模块演示的内容为：
手动读取异常日志,通过消息"ERRDUMP_DATA_SEND_UART"发布出去通知串口接收进行处理，
通过消息"SEND_DATA_REQ"发布出去通知tcp接收进行处理。
如果是系统异常日志，则会在重启后手动读取上报，用户写入的调试日志则需要手动读取上报。
注意：用户写入的调试日志只能手动读取上报，不能自动上报。
]]

--加载uart模块
require "uart_app"
--加载tcp主应用模块
require "tcp_client_main"

local function test_user_log()
    -- 下面演示手动获取异常日志信息,手动读取到异常日志可以上报到自己服务器
    errDump.config(true, 0)                                   --配置为手动读取，如果配置为自动上报将无法手动读取系统异常日志
    local err_buff = zbuff.create(4096)
    local new_flag = errDump.dump(err_buff, errDump.TYPE_SYS) -- 开机手动读取一次系统异常日志
    if err_buff:used() > 0 then
        -- log.info(err_buff:toStr(0, err_buff:used())) -- 打印出异常日志
        -- 将数据data通过"ERRDUMP_DATA_SEND_UART"消息publish给串口发送出去
        sys.publish("ERRDUMP_DATA_SEND_UART", err_buff:toStr(0, err_buff:used()))
        -- 将读取到的系统异常日志通过"SEND_DATA_REQ"消息publish给tcp发送出去
        sys.publish("SEND_DATA_REQ", err_buff:toStr(0, err_buff:used()))
    end
    --手动读取的话需要手动删除日志，否则下次读取会继续读取上次的日志
    --  errDump.dumpf返回值：true表示本次读取前并没有写入数据，false反之，在删除日志前，最好再读一下确保没有新的数据写入了
    new_flag = errDump.dump(err_buff, errDump.TYPE_SYS)
    if not new_flag then
        log.info("没有新数据了，删除系统错误日志")
        errDump.dump(nil, errDump.TYPE_SYS, true)
    end
    -- 开机读取完系统异常日志后循环读取用户调试日志
    while true do
        local new_flag = errDump.dump(err_buff, errDump.TYPE_USR)
        if new_flag then
            log.info("errBuff", err_buff:toStr(0, err_buff:used()))
            -- 将数据data通过"ERRDUMP_DATA_SEND_UART"消息publish给串口发送出去
            sys.publish("ERRDUMP_DATA_SEND_UART", err_buff:toStr(0, err_buff:used()))
            -- 将读取到的用户调试日志通过"SEND_DATA_REQ"消息publish给tcp发送出去
            sys.publish("SEND_DATA_REQ", err_buff:toStr(0, err_buff:used()))
        end
        new_flag = errDump.dump(err_buff, errDump.TYPE_USR)
        if not new_flag then
            log.info("没有新数据了，删除用户调试日志")
            errDump.dump(nil, errDump.TYPE_USR, true)
        end
        sys.wait(15000)
        errDump.record("测试一下用户的调试日志记录功能") --写入用户的调试日志，注意最大只有4KB，超过部分新的覆盖旧的
    end
end

local function test_error_log() --故意写错用来触发系统异常日志记录
    sys.wait(60000)
    --故意写错代码死机
    lllllllllog.info("此处使用一个不存在的库文件，导致出现异常")
end


sys.taskInit(test_user_log)  -- 启动errdemp测试任务
sys.taskInit(test_error_log) --启动错误函数任务
