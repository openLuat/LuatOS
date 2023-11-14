--[[
    @module  VL6180
    @summary VL6180激光测距传感器 
    @version 1.0
    @date    2023.11.14
    @author  Dozingfiretruck
    @usage

    接线说明：
    MCU                        VL6180
    3V3                        VIN
    GND                        GND
    I2CSCL                     SCL
    I2CSDA                     SDA
    GPIO                       GPIO1(SHDN/中断输出)
    GPIO                       GPIO0(CE)

    VL6180测量说明：
    1、只能单次测量，测量0-10cm的绝对距离
    3、测量有效范围在20-30cm

    --注意:因使用了sys.wait()所有api需要在协程中使用
    --注意:因使用了GPIO中断，所以在中断内打印数据

    -- 用法实例
    VL_6180=require"VL_6180"
    sys.taskInit(function()
        sys.wait(2000)
        log.info('初始化')
        VL_6180.vl6180_init()
        while true do
            sys.wait(200)
            --单次测量开始
            VL_6180.odd_measuring_short()
        end
    end)
]]

VL_6180={}

--配置GPIO为CE和INT
local CE=4    --gpio 4
local INT=21  --gpio 21
--i2c id
local i2c_id=0
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
        --若不使用中断则关闭该打印
        log.info('距离',vldata)
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
    系统功能配置：
]]
local function SetMode()
    --设置GPIO1为中断输出，极性低
    write_register(0x0011,0x10)
    
    --系统高低阈值
--   write_register(0x001A,0x0A)
--   write_register(0x0019,0xC8)

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

--初始化VL6180
function VL_6180.vl6180_init()

    --初始化INT和CE
    it_ce_init()
    --初始化i2c
    i2c_init()

    --开启vl6180
    gpio.set(CE, 0)
    sys.wait(10)
    gpio.set(CE, 1)
 
    --读设备号
    i2c.send(i2c_id,addr,string.char(0x00,0x00))
    local recv_data=i2c.recv(i2c_id,addr,1)
    log.info('设备号:',string.toHex(recv_data))

    --读设备身份日期
    recv_data=read_register(0x0006,1)
    log.info('身份日期',recv_data & 0xF,'月')

    --系统模式配置
    SetMode()

    log.info('开始测量')

end

--单次测距
function VL_6180.odd_measuring_short()
    --等待设备就绪
    recv_data=read_register(0x004D,1)
    if recv_data & 0x1 ~=0 then
        --log.info('设备准备就绪')

        --启动测量，连续测距
        --i2c.send(i2c_id,addr,string.char(0x00,0x18,0x03))
        --启动测量，单次测距
        i2c.send(i2c_id,addr,string.char(0x00,0x18,0x01))
        --log.info('0x0018位值',read_register(0x0018,1))

        --判断ALS低阈值事件
        recv_data=read_register(0x004F,1)
        if recv_data & 0x04 ~= 0 then
            --log.info('低阈值实践准备就绪')
            --读取距离数据，单位mm
            vldata = read_register(0x0062,1)
            --清除全部中断标志位
            i2c.send(i2c_id,addr,string.char(0x00,0x15,0x07))
            --若不使用中断则打开
            --return vldata
        else
            log.info('低阈值')
        end
    else
        log.info('设备忙')
    end
end

return VL_6180