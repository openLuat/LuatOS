--重要声明！！！
--该代码仅供学习参考使用，未经量产验证；
--思路可以借鉴，但是不要直接用在项目开发上，一定要结合自己项目做！！！
--================================================================

local Radar_485 = {}--RS485空气开关控制
kong_Value_485=0--空高
liao_Value_485=0--料高
SNR_485=0--雷达信号强度
Radar_temp_485=-100
--=============================================================
local uartid =1       -- 根据实际设备选取不同的uartid，2代表uart2,串口3为LCD复用
--=============================================================
local RE_DE_PIN=24--收发控制引脚，780EPM的引脚引脚是20，GPIO24
local LDO_EN=1--RS485芯片供电控制引脚
gpio.setup(LDO_EN, 1)
--RS485专用的初始化
uart.setup(
 uartid, --串口ID
 115200,--波特率
 8,--数据位
 1,--停止位
 uart.NONE,--校验位
 uart.LSB,--高低位顺序
 1024,--数据缓存区大小 
 RE_DE_PIN,--收发切换引脚
 0, --电平状态
 8000--收发切换时间
)--收发的切换时间，极限为2000us
log.info("uart1", "485雷达串口初始化完成")
--=============================================================
--=============================================================
--读雷达命令
local Device_Address=0x01  --根据实际情况设置
--读雷达状态，功能码03
--1.同时读取空高/料高:01 03 00 00 00 04 44 09
local Read_Radar_Date=string.char(Device_Address,0x03,0x00,0x00,0x00,0x04,0x44,0x09)
--2.同时读取空高/料高/SNR/温度:01 03 00 00 00 08 44 0C--低功耗雷达
--local Read_4_Date=string.char(Device_Address,0x03,0x00,0x00,0x00,0x08,0x44,0x0C)--低功耗雷达
--2.同时读取空高/料高/SNR/温度:01 03 00 00 00 0A C5 CD--四线制485雷达
local Read_4_Date=string.char(Device_Address,0x03,0x00,0x00,0x00,0x0A,0xC5,0xCD)
--3.同时读取空高/料高/SNR/温度/湿度/俯仰角/横滚角:01 03 00 00 00 0E C4 0E
--=============================================================
--=============================================================
--crc16校验函数
function crc16(buf,len)
    local init = 0xFFFF;
    local poly = 0xA001;
    local ret = init;
    local byte=0;
    for j=1,len,1 do
        byte = string.byte(buf,j);
        ret=((ret ~ byte) & 0xFFFF);
        for i=1,8,1 do
            if((ret & 0x0001)>0) then
                ret = (ret >> 1);
                ret = ((ret ~ poly) & 0xFFFF);
            else
                ret= (ret >> 1);
            end;
        end
    end
    local hi = ((ret >> 8) & 0xFF);
    local lo = (ret & 0xFF);
    ret = ((lo << 8) | hi);
    return ret;
end
--=============================================================
--=============================================================
--采集雷达数据
local function get_radar_date()
    --=============================================================
    --注册串口事件回调
    uart.on(uartid, "receive", function(id, len)
        local s = ""
        repeat --repeadt类似C语言的do…while循环，repeat重复执行循环，直到until指定条件为真
            s = uart.read(id, len)
            --log.info("uart", "receive", id, #s, s)
            log.info("串口2", "receive", id, #s, s:toHex())
            --log.info("第三个数string.byte(s,3)=", string.byte(s,3))
            if #s > 0  then -- #s 是取字符串的长度，string.byte(s,3)==8判断师回复的那条命令
                -- 如果传输二进制/十六进制数据, 部分字符不可见, 不代表没收到
                -- 关于收发hex值,请查阅 https://doc.openluat.com/article/583
                log.info("第三个数string.byte(s,3)=", string.byte(s,3))
                local crc16=crc16(s,#s-2)
                local crc16_high=crc16 >> 8
                local crc16_low=crc16 & 0xFF
                log.info("CRC校验高位",crc16_high,"CRC校验低位",crc16_low)
                --打印其hex字符串形式
                --数据转换为数值string.byte，用于crc校验
                local receive_crc_high = string.byte(s,#s-1)
                local receive_crc_low = string.byte(s,#s)
                local receive_Switch_state = string.byte(s,#s-2)
                log.info("接收到的CRC校验高位", "接收到的CRC校验低位", receive_crc_high, receive_crc_low)
                log.info("uart", "receive", id, #s, s:toHex())
                --=============================================================
                --识别读取数据并将数据赋值给空高料高变量
                if crc16_high==receive_crc_high and crc16_low==receive_crc_low and string.byte(s,3)==20 then--物位计的判断
                --if crc16_high==receive_crc_high and crc16_low==receive_crc_low and string.byte(s,3)==16 then--判断10数据
                    --注意，string.byte(s,3)==16，收到字符串的第3个数据，判断时要转换为十进制数，第三个数为0x10，十进制数为16--低功耗雷达
                    --注意，string.byte(s,3)==16，收到字符串的第3个数据，判断时要转换为十进制数，第三个数为0x14，十进制数为20--四线制雷达
                    log.info("crc检验通过数据合法")
                    --先将字符串转为hex格式
                    local hexStr, len = string.toHex(s) -- 返回值"3132",2,后面的2是长度
                    --log.info("收到的16进制字符串=",hexStr,len)
                    --print(hexStr,len) -- 将输出 3132
                    --截取空高数据，并加上0x个前缀
                    --local kong_high="0x"..string.sub(hexStr,7,14)--将0x拼接到字符串上,string.sub(hexStr,7,14)是一个数字算一个(低功耗雷达)
                    local kong_high="0x"..string.sub(hexStr,11,18)--物位计
                    --截取料高数据，并加上0x个前缀
                    --local liao_high="0x"..string.sub(hexStr,15,22)--将0x拼接到字符串上(低功耗雷达)
                    local liao_high="0x"..string.sub(hexStr,19,26)--物位计
                    --信噪比
                    --local SNR_Date="0x"..string.sub(hexStr,23,30)--将0x拼接到字符串上(低功耗雷达)
                    local SNR_Date="0x"..string.sub(hexStr,27,34)--物位计
                    --雷达温度
                    --local temp_Date="0x"..string.sub(hexStr,31,38)--将0x拼接到字符串上(低功耗雷达)
                    local temp_Date="0x"..string.sub(hexStr,35,42)--物位计
                    log.info("空高16进制字符串=",kong_high)
                    log.info("料高16进制字符串=",liao_high)
                    log.info("信噪比16进制字符串=",SNR_Date)
                    log.info("雷达温度比16进制字符串=",temp_Date)
                    --将hex格式转化为浮点型数据
                    local kong_temp = string.pack("<L",kong_high)
                    kong_Value_485 = string.unpack("f",kong_temp)
                    log.info("空高kong_Value_485=",kong_Value_485)
                    local liao_temp = string.pack("<L",liao_high)
                    liao_Value_485= string.unpack("f",liao_temp)
                    log.info("料高liao_Value_485=",liao_Value_485)
                    local SNR_temp = string.pack("<L",SNR_Date)
                    SNR_485 = string.unpack("f",SNR_temp)
                    log.info("信噪比SNR_485=",SNR_485)
                    local xinhao_temp = string.pack("<L",temp_Date)
                    Radar_temp_485 = string.unpack("f",xinhao_temp)
                    log.info("雷达温度Radar_temp_485=",Radar_temp_485)                               
                    --uart.write(1, s)--正常采集不透传给串口1，也就是传给蓝牙
                    log.info("发布雷达完成消息", "receive", id, #s, s)
                    sys.publish("雷达完成")
                --=============================================================
                --如果不是采集命令，则透传给串口1
                elseif crc16_high==receive_crc_high and crc16_low==receive_crc_low then
                    log.info("串口2透传给串口1数据", "receive", id, #s, s)
                    -- log.info("uart", "receive", id, #s, s:toHex())
                    uart.write(1, s)--暂时不透传给串口1
                elseif crc16_high~=receive_crc_high or crc16_low~=receive_crc_low then
                    log.info("无数据或crc检验不通过")
                    kong_Value_485=-100--空高
                    liao_Value_485=-100--料高
                    uart.write(1, s)--暂时不透传给串口1
                    --两种情况，一种是采集失败，一种是采集回波曲线
                    end
            end
            if #s == len then
                --log.info("程序经过这里1")
                break
            end
        until s == ""
        --log.info("程序经过这里2")
    end)
    --=============================================================
    while true do
        --sys.waitUntil("读雷达")
        log.info("读485空高数值")
        sys.wait(2000)--2秒读一次高度
        -- uart.write(uartid,Read_Radar_Date)
        -- log.info("串口发送完成",Read_Radar_Date)
        uart.write(uartid,Read_4_Date)
        log.info("485雷达采集发送完成",Read_4_Date)
    end
end
--=============================================================
--=============================================================
-- 并非所有设备都支持sent事件
uart.on(uartid, "sent", function(id)
    log.info("uart", "sent", id)
end)
--=============================================================
--开启协程
sys.taskInit(get_radar_date)
--=============================================================
--测试串口时使用
--循环发数据
--sys.timerLoopStart(uart.write,5000,uartid,Read_Radar_Date)
--=============================================================

--=============================================================
--crc16校验函数用法
--local data = string.pack("BBBBBB", 0x01, 0x03, 0x00, 0x00, 0x00, 0x02);--需要校验CRC16的内容
--local datacrc = crc16(data,6);
--print( datacrc >> 8 )		--输出196 == 0xC4
--print( datacrc & 0xFF )		--输出11  == 0x0B
--=============================================================
