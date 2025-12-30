--[[
@module  fota_uart
@summary 串口FOTA升级功能模块
@version 1.0
@date    2025.10.24
@author  孟伟
@usage
-- 串口FOTA升级功能
-- 提供通过串口分段接收升级包数据进行固件升级的功能

用法:
1. 先把脚本和固件烧录到模块里, 并确认开机正常
2. 在电脑端操作：进入命令行程序，执行 `python main.py` 进行升级，需要保证升级文件名字为 `fota_uart.bin`，并且和 `main.py` 在同一目录下
    注意：运行`python main.py`需要确保电脑安装了Python环境。
3. 观察luatools的输出和main.py的输出
4. 模块接收正确的升级数据后,会提示1秒后重启
5. 本demo自带的脚本升级包,仅加了一条打印和修改版本号

串口通讯过程说明
串口升级采用简单的文本协议进行握手和数据传输控制：
协议流程：
1. 上位机发送：#FOTA\n
2. 设备回复：#FOTA RDY\n
3. 上位机发送：256字节数据包
4. 设备回复：#FOTA NEXT\n（请求下一包）
5. 重复步骤3-4直到所有数据发送完成
6. 设备回复：#FOTA OK\n（升级成功）
7. 设备自动重启

注意:
- 本demo默认是走main uart串口进行升级
- 升级过程中如果发生错误，串口会自动关闭，设备会重新初始化进入升级模式
- 升级成功设备会自动重启

本文件没有对外接口，直接在main.lua中require "fota_uart"就可以加载运行；
]]

-- 定义所需要的UART编号
uart_id = 1    -- UART1, 通常也是MAIN_UART

-- 全局变量
local uart_zbuff = nil
local uart_fota_state = 0
local uart_rx_counter = 0
local uart_fota_writed = 0

-- 初始化串口 - 开机时自动执行
local function init_uart_fota()
    log.info("FOTA_UART", "开机自动启动串口升级模式")
    -- 初始化串口和缓冲区
    uart_zbuff = zbuff.create(1024)
    uart.setup(uart_id, 115200)
    uart.on(uart_id, "receive", uart_cbfun)
    uart_fota_state = 0
    uart_rx_counter = 0
    uart_fota_writed = 0
    -- 发布事件，唤醒升级任务
    sys.publish("UART_UPGRADE_START")
end

-- 清理资源的函数
local function cleanup_resources()
    if uart_zbuff then
        uart_zbuff:del()
        uart_zbuff = nil
    end
    uart.close(uart_id)  -- 关闭串口
    uart_fota_state = 0
    log.info("FOTA_UART", "资源已清理，串口已关闭")
end

-- 串口接收回调函数
function uart_cbfun(id, len)
    if not uart_zbuff then
        return
    end

    -- 防御缓冲区超标的情况
    if uart_zbuff:used() > 8192 then
        log.warn("fota", "uart_zbuff待处理的数据太多了,强制清空")
        uart_zbuff:del()
    end

    while true do
        local len = uart.rx(id, uart_zbuff)
        if len <= 0 then
            break
        end
        uart_rx_counter = uart_rx_counter + len
        log.info("uart", "收到数据", len, "累计", uart_rx_counter)
        -- 首次收到数据即发布事件，唤醒升级任务
        if uart_fota_state == 0 then
            sys.publish("UART_FOTA")
            log.info("UART_FOTA", "首次收到数据，发布升级信号")
        end
    end
end

-- 串口升级任务
local function uartUpgradeTask()
    local fota_state = 0 -- 0还没开始, 1进行中

    -- 开机时自动启动升级模式
    init_uart_fota()

    while true do
        -- 等待升级启动信号
        sys.waitUntil("UART_UPGRADE_START")
        log.info("FOTA_UART", "升级任务已启动，等待数据...")

        while true do
            -- 等待升级数据到来
            sys.waitUntil("UART_FOTA")
            log.info("UART_FOTA", "等待数据...")

            local used = uart_zbuff and uart_zbuff:used() or 0
            if used > 0 then
                if fota_state == 0 then
                    -- 等待FOTA的状态
                    if used > 5 then
                        local data = uart_zbuff:query()
                        uart_zbuff:del()
                        -- 如果接受到 #FOTA\n 代表数据要来了
                        if data:startsWith("#FOTA") and data:endsWith("\n") then
                            fota_state = 1
                            log.info("fota", "检测到fota起始标记,进入FOTA状态", data)
                            if fota.init() then
                                -- 固件数据发送端应该在收到#FOTA RDY\n之后才开始发送数据
                                uart.write(uart_id, "#FOTA RDY\n")
                            else
                                log.error("FOTA_UART", "FOTA初始化失败")
                                cleanup_resources()
                                break
                            end
                        end
                    end
                else
                    -- 已进入升级状态：把收到的数据喂给fota.run
                    uart_fota_writed = uart_fota_writed + used
                    log.info("准备写入fota包", used, "累计写入", uart_fota_writed)
                    local result, isDone, cache = fota.run(uart_zbuff)
                    log.debug("fota.run", result, isDone, cache)
                    uart_zbuff:del() -- 清空缓冲区

                    if not result then
                        -- 写入失败，退出升级状态并通知上位机
                        log.error("fota", "出错了", result, isDone, cache)
                        uart.write(uart_id, "#FOTA ERR\n")
                        -- 调用fota.finish(false)结束升级流程，参数false表示升级流程失败。
                        fota.finish(false)
                        cleanup_resources()
                        fota_state = 0
                        break
                    elseif isDone then
                        -- 全部数据写入完成，等待底层校验结束
                        local success = false
                        for i = 1, 30 do  -- 最多等待3秒
                            sys.wait(100)
                            local succ, fotaDone = fota.isDone()
                            if not succ then
                                log.error("fota", "校验过程出错")
                                uart.write(uart_id, "#FOTA ERR\n")
                                fota.finish(false)
                                cleanup_resources()
                                fota_state = 0
                                break
                            end
                            if fotaDone then
                                uart_fota_state = 1
                                -- 升级文件成功写入flash中的fota分区，准备重启设备；
                                log.info("fota", "已完成,1s后重启")
                                -- 调用fota.finish(true)结束升级流程，参数true表示正确走完流程。
                                fota.finish(true)
                                -- 反馈给上位机
                                uart.write(uart_id, "#FOTA OK\n")
                                sys.wait(1000)
                                success = true
                                rtos.reboot()
                                break
                            end
                        end
                        if not success then
                            log.error("fota", "校验超时")
                            uart.write(uart_id, "#FOTA ERR\n")
                            fota.finish(false)
                            cleanup_resources()
                            fota_state = 0
                        end
                        break
                    else
                        -- 单包写入成功，通知上位机继续下发
                        log.info("fota", "单包写入完成", used, "等待下一个包")
                        uart.write(uart_id, "#FOTA NEXT\n")
                    end
                end
            end
        end

        -- 重置状态，等待下次升级
        fota_state = 0
        uart_fota_state = 0
        uart_rx_counter = 0
        uart_fota_writed = 0

        -- 升级流程结束后，重新初始化串口等待下次升级
        sys.wait(1000)
        init_uart_fota()
    end
end

-- 启动串口升级任务
sys.taskInit(uartUpgradeTask)