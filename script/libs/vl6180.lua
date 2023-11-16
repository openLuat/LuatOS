--[[
@module  vl6180
@summary VL6180激光测距传感器 
@version 1.0
@date    2023.11.14
@author  dingshuaifei
@usage

--MCU                        vl6180
--3V3                        VIN
--GND                        GND
--I2CSCL                     SCL
--I2CSDA                     SDA
--GPIO                       GPIO1(SHDN/中断输出)
--GPIO                       GPIO0(CE)

vl6180测量说明：
1、只能单次测量，测量0-10cm的绝对距离
2、测量有效范围在20-30cm

--注意:因使用了sys.wait()所有api需要在协程中使用
-- 用法实例
vl6180=require"vl6180"
local CE=4
local INT=21
local I2C_ID=0
sys.taskInit(function()
    sys.wait(2000)
    log.info('初始化')
    vl6180.init(CE,INT,I2C_ID)
    while true do
        sys.wait(200)
        --单次测量开始
        log.info('距离:',vl6180.get())
    end
end)
]]

vl6180={}

--配置GPIO为CE和INT
local CE   --gpio
local INT  --gpio
--i2c id
local i2c_id
--设备地址
local addr=0x29
--测量距离数据
local vldata 

--设置中断和CE
local function it_ce_init()
    --设置CE引脚上拉输出,默认1
    gpio.setup(CE, 0, gpio.PULLUP)
    --设置INT引脚中断，测量完成后会进入回调
    gpio.setup(INT, function(val) 
        sys.publish("VL6180_INC")
    end, gpio.PULLUP)
end

--配置i2c
local function i2c_init()
    --i2c 1 快速模式
    i2c.setup(i2c_id,i2c.FAST)
end

--[[
    写设备寄存器值：
    写入寄存器会判断写入的值是否写入成功，若不成功则会打印出相应的寄存器地址，以及当前寄存器的值。
    注意：有的寄存器位写入值后，会被硬件清除，不代表写失败，具体参考相应寄存器
    @regaddr 寄存器地址
    @val 写入的值
]]
local function write_register(regaddr,val)
    local stu=i2c.send(i2c_id,addr,string.char(regaddr>>8,regaddr&0xff,val))
    i2c.send(i2c_id,addr,string.char(regaddr>>8,regaddr&0xff))
    local reg=i2c.recv(i2c_id,addr,1)
    if string.byte(reg) ~= val then
        log.info('写入失败地址',string.toHex(string.char(regaddr)),'读值',string.toHex(reg),'写发送状态',stu)
    end
end
--[[
    读设备寄存器的值：
    @regaddr 寄存器地址
    @bit 读多少位
]]
local function read_register(regaddr,bit)
    local regval
    i2c.send(i2c_id,addr,string.char(regaddr>>8,regaddr&0xff))
    regval=i2c.recv(i2c_id,addr,bit)
    return string.byte(regval)
end

--[[
    系统功能配置
]]
local function SetMode()
    --设置GPIO1为中断输出，极性低
    write_register(0x0011,0x10)

    --复位平均采样周期
    write_register(0x010A,0x30)
    --模拟增益设置1.0
    write_register(0x003F,0x46)
    --系统范围VHV重复率
    write_register(0x0031,0xFF)

    --积分周期100ms
    write_register(0x0041,0x63)
    --对测距传感器进行单次温度校准
    --write_register(0x002E,0x00)
    write_register(0x002E,0x01)

    --测量周期，10ms
    write_register(0x001B,0x09)
    write_register(0x003E,0x31)
    --系统中断配置GPIO
    write_register(0x0014,0x24)
end

--[[
vl6180初始化
@api vl6180.init(ce,int,id)
@number  ce gpio编号[控制] 
@number  int gpio编号[中断]
@number  id i2c总线id 
@return  bool 成功返回true失败返回false
@usage
vl6180.Init(4,21,0)
]]
function vl6180.init(ce,int,i2cid)

    --判断id是否存在
    if i2c.exist(i2cid)~=true then 
        log.info('i2c不存在')
        return false
    end
    --赋值
    CE       =ce
    INT      =int
    i2c_id   =i2cid

    --初始化INT和CE
    it_ce_init()
    --初始化i2c
    i2c_init()

    --开启vl6180
    gpio.set(CE, 0)
    sys.wait(10)
    gpio.set(CE, 1)
 
    --读设备号
    local send_s=i2c.send(i2c_id,addr,string.char(0x00,0x00))
    if send_s ~=true then 
        log.info('设备不存在')
        return false
    end
    local recv_data=i2c.recv(i2c_id,addr,1)
    log.info('设备号:',string.toHex(recv_data))

    --系统模式配置
    SetMode()
    return true

end

--[[
vl6180获取测量距离值 单位:mm
@api vl6180.get()
@return number 成功返回vl6180数据，失败返回0
@usage
local data=vl6180.get()
log.info("measuring val:",data)
]]
function vl6180.get()
    --等待设备就绪
    local recv_data=read_register(0x004D,1)
    if recv_data & 0x1 ~=0 then
        --启动测量，单次测距
        i2c.send(i2c_id,addr,string.char(0x00,0x18,0x01))
        --判断ALS低阈值事件
        recv_data=read_register(0x004F,1)
        if recv_data & 0x04 ~= 0 then
            --读取距离数据，单位mm
            vldata = read_register(0x0062,1)
            --清除全部中断标志位
            i2c.send(i2c_id,addr,string.char(0x00,0x15,0x07))
            if sys.waitUntil("VL6180_INC")  then
                return vldata
            else
                return 0
            end
        else
            log.info('低阈值事件等待就绪')
        end
    else
        log.info('设备忙')
        return 0
    end
end

return vl6180