--[[
@module xmodem
@summary xmodem 协议
@version 1.0
@date    2025.10.17
@author  Dozingfiretruck
@usage
--加载xmodem模块
xmodem=require ("xmodem")

--设置默认filepath为脚本区的send.bin文件
local filepath="/luadb/send.bin"

local taskName = "xmodem_run"


local uart_id = 1    --串口号

local baudrate = 115200  --波特率

local file_path=filepath --文件路径

local send_type=true  --true表示单次发送128字节，false表示单次发送1024字节

local inform_data="wait C"    --发送前提示信息，告知对方要发送C字符来接收文件

-- 处理未识别的消息
local function xmodem_run_cb(msg)
	log.info("xmodem_run_cb", msg[1], msg[2], msg[3], msg[4])
end

--http获取文件函数
local  function http_recived_cb()
    while not socket.adapter(socket.dft()) do
        log.warn("httpplus_app_task_func", "wait IP_READY", socket.dft())
        -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态;
        -- 注意：此处的1000毫秒超时不要修改的更长；
        -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
        -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
        -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end
    local path = "/send.bin"
    -- 以下链接仅用于测试，禁止用于生产环境
    local code, headers, body_size = http.request("GET", "http://airtest.openluat.com:2900/download/send.bin", nil, nil, {dst=path}).wait()
    log.info("http", code==200 and "success" or "error", code)
    if code==200 then
       log.info("HTTP receive ok",body_size)
       file = io.open(path, "rb")
        if file then
            content = file:read("*a")
            log.info("文件读取", "路径:" .. path, "内容:" .. content)
            file:close()
        else
            log.error("文件操作", "无法打开文件读取内容", "路径:" .. path)
        end
        file_path=path
    end
    
end

--  定义一个xmodem_run函数，用于用xmodem发送文件
local function xmodem_run() 
    --如果需要http下载文件，然后发送下载的文件，可以打开下面的http_recived_cb()函数
    -- http_recived_cb()
    
    --启动xmodem发送
    local result=xmodem.send(uart_id,baudrate,file_path,send_type,inform_data)
    --等待时间12秒，等待接收方发送C字符启动发送，发送结束后接收端发送ACK:0x06表示接收完成，文件全部传输完成之后模块发送EOT​：0x04表示传输结束，接收端返回0x06表示确认结束
    log.info("Xmodem", "start")

    log.info("Xmodem", "send result", result)
    --判断是否传输成功，传输是否成功，都需要关闭xmodem
    if result then
        log.info("Xmodem", "send success")
        xmodem.close(uart_id)
    else
        log.info("Xmodem", "send failed")
        xmodem.close(uart_id)
    end

end

--创建并且启动一个task
--运行这个task的主函数xmodem_run
sys.taskInit(xmodem_run, taskName,xmodem_run_cb)


]]
local xmodem = {}

local sys = require "sys"

local HEAD
local DATA_SIZE 

local SOH           =   0x01    -- Modem数据头 128
local STX           =   0x02    -- Modem数据头 1K
local EOT           =   0x04    -- 发送结束
local ACK           =   0x06    -- 应答
local NAK           =   0x15    -- 非应答
local CAN           =   0x18    -- 取消发送
local CTRLZ         =   0x1A    -- 填充
local CRC_CHR       =   0x43    -- C: ASCII字符C
local CRC_SIZE      =   2
local FRAME_ID_SIZE =   2
local DATA_SIZE_SOH =   128
local DATA_SIZE_STX =   1024


local function uart_cb(id, len)
    local data = uart.read(id, 1024)
    if #data == 0 then
        return
    end
    log.info("xmodem", "uart读取到数据:", data:toHex())
    data = data:byte(1)
    sys.publish("xmodem", data)
end


--[[
xmodem 发送文件
@api xmodem.send(uart_id,baudrate,type,inform_data)
@number uart_id uart端口号
@number uart_br uart波特率
@string file_path 文件路径
@bool type 1k/128 默认1k
@return bool 发送结果
@usage
xmodem.send(1, 115200, "/luadb/send.bin",true)
]]

function xmodem.send(uart_id,baudrate,file_path,type,inform_data)
        local ret, flen, cnt, crc
        if type then
            HEAD = SOH
            DATA_SIZE = DATA_SIZE_SOH
        else
            HEAD = STX
            DATA_SIZE = DATA_SIZE_STX
        end
        local XMODEM_SIZE = 1+FRAME_ID_SIZE+DATA_SIZE+CRC_SIZE
        local packsn = 0
        local xmodem_buff = zbuff.create(XMODEM_SIZE)
        local data_buff = zbuff.create(DATA_SIZE)
        local fd = io.open(file_path, "rb")
        if fd then
            uart.setup(uart_id,baudrate)
            uart.on(uart_id, "receive", uart_cb)
            if inform_data and  inform_data~="" then
                uart.write(uart_id,inform_data)
            end
            local result, data = sys.waitUntil("xmodem", 12000)
            if result and (data == CRC_CHR or data == NAK) then
                cnt = 1
                while true do
                    data_buff:set(0, CTRLZ)
                    ret, flen = fd:fill(data_buff,0,DATA_SIZE)
                    log.info("xmodem", "发送第", cnt, "包")
                    if flen > 0 then
                        data_buff:seek(0)
                        crc = crypto.crc16("XMODEM",data_buff)
                        packsn = (packsn+1) & 0xff
                        xmodem_buff[0] = 0x02
                        xmodem_buff[1] = packsn
                        xmodem_buff[2] = 0xff-xmodem_buff[1]
                        data_buff:seek(DATA_SIZE)
                        xmodem_buff:copy(3, data_buff)
                        xmodem_buff[1027] = crc>>8
                        xmodem_buff[1028] = crc&0xff
                        xmodem_buff:seek(XMODEM_SIZE)
                        -- log.info(xmodem_buff:used())
                        :: RESEND ::
                        uart.tx(uart_id, xmodem_buff)
                        result, data = sys.waitUntil("xmodem", 10000)
                        if result and data == ACK then
                            cnt = cnt + 1
                        elseif result and data == NAK then
                            goto RESEND
                        else
                            uart.write(uart_id, string.char(EOT))
                            log.info("xmodem", "发送失败")
                            return false
                        end
                        if flen ~= DATA_SIZE then
                            log.info("xmodem", "文件到头了")
                            break
                        end
                    else
                        log.info("xmodem", "文件到头了")
                        break
                    end
                end
                uart.write(uart_id, string.char(EOT))
                fd:close()
                return true
            else
                log.info("xmodem", "不支持的起始数据包",data)
                return false
            end
        else
            log.info("xmodem", "待传输的文件不存在")
            return false
        end
end

--[[
关闭xmodem
@api xmodem.close(uart_id)
@number uart_id uart端口号
@usage
-- 执行xmodem传输后, 无论是否传输成功, 都建议关闭xmodem上下文, 也会关闭uart
xmodem.close(2)
]]
function xmodem.close(uart_id)
    uart.on(uart_id, "receive")
    uart.close(uart_id)
end

return xmodem
