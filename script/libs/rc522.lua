--[[
@module rc522
@summary rc522 非接触式读写卡驱动
@version 1.0
@date    2022.06.14
@author  Dozingfiretruck
@usage
--注意:因使用了sys.wait()所有api需要在协程中使用
-- 用法实例
local rc522 = require "rc522"
sys.taskInit(function()
    spi_rc522 = spi.setup(0,nil,0,0,8,10*1000*1000,spi.MSB,1,1)
    rc522.init(0,pin.PB04,pin.PB01)
    wdata = {0x01,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00}
    while 1 do
        rc522.write_datablock(8,wdata)
        for i=0,63 do
            local a,b = rc522.read_datablock(i)
            if a then
                print("read",i,b:toHex())
            end
        end
        sys.wait(500)
    end
end)
]]


local rc522 = {}

local sys = require "sys"

local rc522_spi,rc522_rst,rc522_irq,rc522_cs

---器件所用地址
local rc522_idle              =       0x00   --取消当前命令
local rc522_authent           =       0x0E   --验证密钥
local rc522_receive           =       0x08   --接收数据
local rc522_transmit          =       0x04   --发送数据
local rc522_transceive        =       0x0C   --发送并接收数据
local rc522_resetphase        =       0x0F   --复位
local rc522_calccrc           =       0x03   --CRC计算

--Mifare_One卡片命令字
rc522.reqidl                 =       0x26   --寻天线区内未进入休眠状态
rc522.reqall                 =       0x52   --寻天线区内全部卡
local rc522_anticoll1        =       0x93   --防冲撞
local rc522_anticoll2        =       0x95   --防冲撞
local rc522_authent1a        =       0x60   --验证A密钥
local rc522_authent1b        =       0x61   --验证B密钥
local rc522_read             =       0x30   --读块
local rc522_write            =       0xA0   --写块
local rc522_decrement        =       0xC0   --扣款
local rc522_increment        =       0xC1   --充值
local rc522_restore          =       0xC2   --调块数据到缓冲区
local rc522_transfer         =       0xB0   --保存缓冲区中数据
local rc522_halt             =       0x50   --休眠

--MF522寄存器定义
-- PAGE 0
local rc522_rfu00            =       0x00 --保留为将来之用    
local rc522_com_mand         =       0x01 --启动和停止命令的执行      
local rc522_com_ie           =       0x02 --中断请求传递的使能和禁能控制位      
local rc522_divl_en          =       0x03 --中断请求传递的使能和禁能控制位      
local rc522_com_irq          =       0x04 --包含中断请求标志      
local rc522_div_irq          =       0x05 --包含中断请求标志  
local rc522_error            =       0x06 --错误标志，指示执行的上个命令的错误状态      
local rc522_status1          =       0x07 --包含通信的状态标志      
local rc522_status2          =       0x08 --包含接收器和发送器的状态标志      
local rc522_fifo_data        =       0x09 --64 字节 FIFO 缓冲区的输入和输出  
local rc522_fifo_level       =       0x0A --指示 FIFO 中存储的字节数  
local rc522_water_level      =       0x0B --定义 FIFO 下溢和上溢报警的 FIFO 深度  
local rc522_control          =       0x0C --不同的控制寄存器  
local rc522_bit_framing      =       0x0D --面向位的帧的调节  
local rc522_coll             =       0x0E --RF 接口上检测到的第一个位冲突的位的位置  
local rc522_rfu0f            =       0x0F --保留为将来之用  
-- PAGE 1     
local RFU10                  =       0x10 --保留为将来之用
local rc522_mode             =       0x11 --定义发送和接收的常用模式
local rc522_tx_mode          =       0x12 --定义发送过程的数据传输速率
local rc522_rx_mode          =       0x13 --定义接收过程中的数据传输速率
local rc522_tx_control       =       0x14 --控制天线驱动器管脚 TX1 和 TX2 的逻辑特性
local rc522_tx_ayto          =       0x15 --控制天线驱动器的设置
local rc522_tx_sel           =       0x16 --选择天线驱动器的内部源
local rc522_rx_sel           =       0x17 --选择内部的接收器设置
local rc522_rx_threshold     =       0x18 --选择位译码器的阈值
local rc522_demod            =       0x19 --定义解调器的设置
local rc522_rfu1a            =       0x1A --保留为将来之用
local rc522_rfu1b            =       0x1B --保留为将来之用
local rc522_mifare           =       0x1C --控制 ISO 14443/MIFARE 模式中 106kbit/s 的通信
local rc522_rfu1d            =       0x1D --保留为将来之用
local rc522_rfu1e            =       0x1E --保留为将来之用
local rc522_serial_speed     =       0x1F --选择串行 UART 接口的速率
-- PAGE 2    
local rc522_rfu20            =       0x20 --保留为将来之用  
local rc522_crcresult_m      =       0x21 --显示 CRC 计算的实际 MSB 值
local rc522_crcresult_l      =       0x22 --显示 CRC 计算的实际 LSB 值
local rc522_rfu23            =       0x23 --保留为将来之用
local rc522_mod_width        =       0x24 --控制 ModWidth 的设置
local rc522_rfu25            =       0x25 --保留为将来之用
local rc522_rfcfg            =       0x26 --配置接收器增益
local rc522_gsn              =       0x27 --选择天线驱动器管脚 TX1 和 TX2 的调制电导
local rc522_cwgscfg          =       0x28 --选择天线驱动器管脚 TX1 和 TX2 的调制电导
local rc522_modgscfg         =       0x29 --选择天线驱动器管脚 TX1 和 TX2 的调制电导
local rc522_tmode            =       0x2A --定义内部定时器的设置
local rc522_tprescaler       =       0x2B --定义内部定时器的设置
local rc522_tpreload_h       =       0x2C --描述 16 位长的定时器重装值
local rc522_tpreload_l       =       0x2D --描述 16 位长的定时器重装值
local rc522_tcounter_value_h =       0x2E --描述 16 位长的定时器重装值
local rc522_tcounter_value_l =       0x2F --描述 16 位长的定时器重装值
-- PAGE 3      
local rc522_rfu30            =       0x30 --保留为将来之用
local rc522_testsel1         =       0x31 --常用测试信号的配置
local rc522_testsel2         =       0x32 --常用测试信号的配置和 PRBS 控制
local rc522_testpin_en       =       0x33 --D1-D7 输出驱动器的使能管脚（注：仅用于串行接口）
local rc522_testpin_value    =       0x34 --定义 D1-D7 用作 I/O 总线时的值
local rc522_testbus          =       0x35 --显示内部测试总线的状态
local rc522_autotest         =       0x36 --控制数字自测试
local rc522_version          =       0x37 --显示版本
local rc522_analogtest       =       0x38 --控制管脚 AUX1 和 AUX2
local rc522_testadc1         =       0x39 --定义 TestDAC1 的测试值  
local rc522_testadc2         =       0x3A --定义 TestDAC2 的测试值   
local rc522_testadc          =       0x3B --显示 ADC I 和 Q 通道的实际值   
local rc522_rfu3c            =       0x3C --保留用于产品测试   
local rc522_rfu3d            =       0x3D --保留用于产品测试   
local rc522_rfu3e            =       0x3E --保留用于产品测试   
local rc522_rfu3f		     =       0x3F --保留用于产品测试

local Key_A = string.char(0xff,0xff,0xff,0xff,0xff,0xff)
local Key_B = string.char(0xff,0xff,0xff,0xff,0xff,0xff)

--[[
写rc522寄存器
@api rc522.set_bit_mask(address, value)
@number address 地址
@number value    值
@usage
write_rawrc(rc522_bit_framing,0x07)
]]
local function write_rawrc(address, value)
    rc522_cs(0)
    local data = string.char((address<<1)&0x7E) .. string.char(value)
    spi.send(rc522_spi, data)
    -- rc522_spi:send(data)
    rc522_cs(1)
end

--[[
读rc522寄存器
@api rc522.read_rawrc(address)
@number address 地址
@return number 寄存器值
@usage
local n = read_rawrc(rc522_com_irq) 
]]
local function read_rawrc(address)
    rc522_cs(0)
    local data = string.char(((address<<1)&0x7E)|0x80)
    spi.send(rc522_spi, data)
    local val = spi.recv(rc522_spi,1)
    -- rc522_spi:send(data)
    -- local val = rc522_spi:recv(1)
    rc522_cs(1)
    return string.byte(val)
end

--[[
对rc522寄存器置位
@api rc522.set_bit_mask(address, mask)
@number address 地址
@number mask    置位值
@usage
rc522.set_bit_mask (rc522_fifo_level, 0x80)	
]]
function rc522.set_bit_mask(address, mask)
    local current = read_rawrc(address)
    write_rawrc(address, bit.bor(current, mask))
end

--[[
对rc522寄存器清位
@api rc522.clear_bit_mask(address, mask)
@number address 地址
@number mask    清位值
@usage
rc522.clear_bit_mask(rc522_com_irq, 0x80 )
]]
function rc522.clear_bit_mask(address, mask)
    local current = read_rawrc(address)
    write_rawrc(address, bit.band(current, bit.bnot(mask)))
end

--[[ 
命令通讯
@api rc522.command(command,data)
@number command 
@number data 
@return status data len 结果,返回数据,收到的位长度
@usage
rc522.version()
]]
function rc522.command(command,data)
    local out_data = {}
    local len = 0
    local status = false
    local Irq_en  = 0x00
    local waitfor = 0x00
    local last_bits,n,l
    if command==rc522_authent then
        Irq_en   = 0x12;		
        waitfor = 0x10;		
    elseif command==rc522_transceive then 
        Irq_en   = 0x77;		
        waitfor = 0x30;		
    end
    write_rawrc(0x02, bit.bor(Irq_en, 0x80))
    rc522.clear_bit_mask(rc522_com_irq, 0x80 )
    write_rawrc (rc522_com_mand, rc522_idle)	 
    rc522.set_bit_mask (rc522_fifo_level, 0x80)	
    for i=1,#data do
        write_rawrc(rc522_fifo_data, data[i])
    end
    write_rawrc(rc522_com_mand,command )	
    if ( command == rc522_transceive )then
        rc522.set_bit_mask(rc522_bit_framing,0x80)
    end
    l = 12;
    while true do
        sys.wait(1)
        n = read_rawrc(rc522_com_irq) 
        l = l - 1
        if  not ((l ~= 0) and (bit.band(n, 0x01) == 0) and (bit.band(n, waitfor) == 0)) then
            break
        end
    end
    rc522.clear_bit_mask(rc522_bit_framing, 0x80 )
    if (l ~= 0)then 
        if bit.band(read_rawrc(rc522_error), 0x1B) == 0x00 then
            status = true
            if bit.band(n,Irq_en,0x01)~=0then			
                status = false
            end   
            if (command == rc522_transceive )then
                n = read_rawrc(rc522_fifo_level)
                last_bits = bit.band(read_rawrc(rc522_control),0x07)	
                if last_bits ~= 0 then
                    len = (n - 1) * 8 + last_bits  
                else
                    len = n * 8  
                end
                if n == 0 then	
                    n = 1  
                end  
                for i=1, n do
                    out_data [ i ] = read_rawrc(rc522_fifo_data)
                end 
            end
        end   
    else
        status = false
    end
    rc522.set_bit_mask (rc522_control,0x80 )
    write_rawrc(rc522_com_mand,rc522_idle )
    return status,out_data,len 
end

--[[ 
防冲撞
@api rc522.anticoll(id)
@string id 卡片序列号，4字节
@return status uid 结果,uid
@usage
local status,uid = rc522.anticoll(array_id)
]]
function rc522.anticoll(id)
    local check = 0
    local uid
    rc522.clear_bit_mask(rc522_status2,0x08)
    write_rawrc( rc522_bit_framing, 0x00);
    rc522.clear_bit_mask (rc522_coll, 0x80);			  
    local status, back_data = rc522.command(rc522_transceive,{0x93,0x20})
    if status == true then		            
        for i=1,4 do
            check = bit.bxor(check,back_data[i])
        end
        if check ~= back_data[5] then
            status = false;
        end   			
        uid = string.char(table.unpack(back_data,1,4))	
    end
    rc522.clear_bit_mask( rc522_coll, 0x80 )
    return status,uid;		
end

--[[ 
crc计算
@api calculate_crc(data)
@table data 数据
@return table crc值
@usage
local crc = calculate_crc(buff)
]]
local function calculate_crc(data)
    local ret_data = {}
    rc522.clear_bit_mask(rc522_div_irq, 0x04)
    write_rawrc(rc522_com_mand, rc522_idle) 
    rc522.set_bit_mask (rc522_fifo_level,0x80 ) 
    for i=1,#data do
        write_rawrc(rc522_fifo_data, data[i])
    end
    write_rawrc(rc522_com_mand, rc522_calccrc) 
    local i = 0xFF
    while true do
        local n = read_rawrc(0x05)
        i = i - 1
        if not ((i ~= 0) and not (n&0x04)) then
            break
        end
    end
    ret_data[1] = read_rawrc(0x22)
    ret_data[2] = read_rawrc(0x21)
    return ret_data
end

--[[ 
验证卡片密码
@api authstate(mode, addr,key,uid )
@number mode 模式
@number addr 地址
@string key 密码
@string uid uid
@return bool 结果
@usage
status = authstate(rc522_authent1b, addr,Key_B,uid )
]]
local function authstate( mode, addr,key,uid )
    local buff = {}
    buff[1] = mode
    buff[2] = addr
    for i=1,6 do
        buff[i+2]=key:byte(i)
    end
    for i=1,4 do
        buff[i+8]=uid:byte(i)
    end
    local status, back_data = rc522.command(rc522_authent,buff)
    if status == true and (read_rawrc(rc522_status2)& 0x08) ~= 0 then
        return true
    end
    return false	
end

--[[ 
写数据到M1卡一块
@api rc522.write(addr, data)
@number addr 块地址(0-63)M1卡总共有16个扇区(每个扇区有：3个数据块+1个控制块),共64个块
@table data 数据
@return bool 结果
@usage
rc522.write(addr, data)
]]
function rc522.write(addr, data)
    local buff = {}
    buff[1] = rc522_write;
    buff[2] = addr;
    local crc = calculate_crc(buff)
    buff[3] = crc[1]
    buff[4] = crc[2]
    local status, back_data, back_bits = rc522.command(rc522_transceive,buff)
    if status == true and back_bits == 4 and (back_data[1]& 0x0F)==0x0A then
        local buf_w = {}
        for i=0, 16 do
            table.insert(buf_w, data[i])
        end
        local crc = calculate_crc(buf_w)
        table.insert(buf_w, crc[1])
        table.insert(buf_w, crc[2])
        status, back_data, back_bits = rc522.command(rc522_transceive,buf_w)
        if status == true and back_bits == 4 and (back_data[1]& 0x0F)==0x0A then
            return status;
        end
    end
    return status;		
end

--[[ 
写数据到M1卡一块
@api rc522.read(addr)
@number addr 块地址(0-63)M1卡总共有16个扇区(每个扇区有：3个数据块+1个控制块),共64个块
@return bool,string 结果，数据
@usage
rc522.read(addr, data)
]]
local function read(addr)
    local buff = {}
    buff[1] = rc522_read;
    buff[2] = addr;
    local crc = calculate_crc(buff)
    buff[3] = crc[1]
    buff[4] = crc[2]
    local status, back_data, back_bits = rc522.command(rc522_transceive,buff)
    if status == true and back_bits == 0x90 then
        local data = string.char(table.unpack(back_data,1,16))
        return status,data
    end
    return false
end

--[[ 
rc522 硬件版本
@api rc522.version()
@return number 硬件版本
@usage
rc522.version()
]]
function rc522.version()
    return read_rawrc(rc522_version)
end

--[[ 
rc522 命令卡片进入休眠状态
@api rc522.halt()
@return bool 结果
@usage
rc522.halt()
]]
function rc522.halt()
    local buff = {}
    buff[1] = rc522_halt;
    buff[2] = 0;
    local crc = calculate_crc(buff)
    buff[3] = crc[1]
    buff[4] = crc[2]
    local status = rc522.command(rc522_transceive,buff)
    return status
end

--[[ 
rc522 复位
@api rc522.reset()
@usage
rc522.reset()
]]
function rc522.reset()
    rc522_rst(1)
    rc522_rst(0)
    rc522_rst(1)
    write_rawrc(rc522_com_mand, 0x0f)
    write_rawrc(rc522_mode, 0x3D)        
    write_rawrc(rc522_tpreload_l, 30)       
    write_rawrc(rc522_tpreload_h, 0)			
    write_rawrc(rc522_tmode, 0x8D)			
    write_rawrc(rc522_tprescaler, 0x3E)	
    write_rawrc(rc522_tx_ayto, 0x40)		
end

--[[ 
开启天线 
@api rc522.antenna_on()
@usage
rc522.antenna_on()
]]
function rc522.antenna_on()
    local uc = read_rawrc( rc522_tx_control )
    if (( uc & 0x03 )==0 ) then
        rc522.set_bit_mask(rc522_tx_control, 0x03)
    end
end

--[[ 
关闭天线 
@api rc522.antenna_on()
@usage
rc522.antenna_on()
]]
function rc522.antenna_off()
    rc522.clear_bit_mask( rc522_tx_control, 0x03 )
end

--[[ 
设置rc522工作方式为ISO14443_A
@api rc522_config_isotype()
@usage
rc522_config_isotype()
]]
local function rc522_config_isotype()
    rc522.clear_bit_mask(rc522_status2, 0x08)
    write_rawrc(rc522_mode, 0x3D)
    write_rawrc(rc522_rx_sel, 0x86)
    write_rawrc(rc522_rfcfg, 0x7F)
    write_rawrc(rc522_tpreload_l, 30)
    write_rawrc(rc522_tpreload_h, 0)
    write_rawrc(rc522_tmode, 0x8D)
    write_rawrc(rc522_tprescaler, 0x3E)
    rc522.antenna_on()
end

--[[
rc522 寻卡
@api rc522.request(req_code)
@number req_code rc522.reqidl 寻天线区内未进入休眠状态 rc522.reqall 寻天线区内全部卡
@return bool tagtype 结果，卡类型 
@usage
status,array_id = rc522.request(rc522.reqall)
]]
function rc522.request(req_code)
    rc522.clear_bit_mask(rc522_status2,0x08)
    write_rawrc(rc522_bit_framing,0x07)
    rc522.set_bit_mask(rc522_tx_control,0x03)
    local tagtype
    local status, back_data, back_bits = rc522.command(rc522_transceive,{req_code})
    if status == true and back_bits == 0x10 then
        tagtype = string.char(table.unpack(back_data,1,2))
        return status, tagtype
    end
    return false
end

--[[
选定卡片
@api rc522.select(id)
@number id 卡片序列号，4字节
@return bool 结果 
@usage
status = rc522.select(id)
]]
function rc522.select(id)
    local buff = {}
    buff[1]=rc522_anticoll1
    buff[2]=0x70
    buff[7]=0
    for i=1,4 do
        buff[i+2]=id:byte(i)
        buff[7]= bit.bxor(buff[7],id:byte(i))
    end
    local crc = calculate_crc(buff)
    buff[8]=crc[1]
    buff[9]=crc[2]
    rc522.clear_bit_mask( rc522_status2, 0x08 )
    local status, back_data, back_bits = rc522.command(rc522_transceive,buff)
    if status == true and back_bits == 0x18 then
        return true
    end
    return false	
end

--[[
按照rc522操作流程写入16字节数据到块
@api rc522.write_datablock(addr,data)
@number addr 任意块地址.M1卡总共有16个扇区(每个扇区有：3个数据块+1个控制块),共64个块
@table data 指向要写入的数据,必须为16个字符
@return bool 结果 
@usage
rc522.write_datablock(addr,data)
]]
function rc522.write_datablock(addr,data)
    if #data ~= 6 then
        return false
    end
    local status,array_id = rc522.request(rc522.reqall)
    if  status ~= true then
        status,array_id = rc522.request(rc522.reqall)
    end
    if status == true then
        local status,uid = rc522.anticoll(array_id)
        if status == true then
            rc522.select(uid)
            status = authstate( rc522_authent1b, addr,Key_B,uid )
            if status == true then
                status = rc522.write(addr,data)
                rc522.halt()
                return status
            end
        end
    end
    return false
end

--[[
按照rc522操作流程读取块
@api rc522.read_datablock(addr)
@number addr 任意块地址.M1卡总共有16个扇区(每个扇区有：3个数据块+1个控制块),共64个块
@return bool string 结果 数据
@usage
    for i=0,63 do
        local a,b = rc522.read_datablock(i)
        if a then
            print("read",i,b:toHex())
        end
    end
]]
function rc522.read_datablock(addr)
    local status,array_id = rc522.request(rc522.reqall)
    if  status ~= true then
        status,array_id = rc522.request(rc522.reqall)
    end
    if status == true then
        local status,uid = rc522.anticoll(array_id)
        if status == true then
            rc522.select(uid)
            status = authstate( rc522_authent1b, addr,Key_B,uid )
            if status == true then
                local status,data = read(addr)
                if status == true then
                    return true, data
                end
                rc522.halt()
            end
        end
    end
    return false
end

--[[
rc522 初始化
@api rc522.init(spi_id, cs, rst)
@number spi_id spi端口号
@number cs      cs引脚
@number rst     rst引脚
@return bool 初始化结果
@usage
spi_rc522 = spi.setup(0,nil,0,0,8,10*1000*1000,spi.MSB,1,1)
rc522.init(0,pin.PB04,pin.PB01)
]]
function rc522.init(spi_id,cs,rst)
    rc522_spi = spi_id
    rc522_cs = gpio.setup(cs, 0, gpio.PULLUP) 
    rc522_cs(1)
    rc522_rst = gpio.setup(rst, 0, gpio.PULLUP) 
    rc522_rst(1)
    rc522.reset()
    rc522_config_isotype()
    log.debug("rc522.version",rc522.version())
    return true
end

function rc522.test()

end

return rc522



