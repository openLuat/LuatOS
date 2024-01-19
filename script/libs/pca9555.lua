--[[

@module pca9555
@summary pca9555 IO扩展
@version 1.0
@date    2024/1/15
@author  小牛
@usage
    i2c.setup(0, i2c.FAST)
    pca9555.setup(0, 0x20, 0x0000)
    for i=0,7 do
        pca9555.pin(i,0)
    end
]]

local pca9555 = {}

local PCA9555_i2cid=0
local PCA9555_addr=0x20
local PCA9555_mode=0x0000 --IO全为输出
local PCA9555_IOstart=0xffff

-- pca9555 registers define
local PCA9555_REG_IN0 = 0x00                  --输入端口寄存器0 默认值由外部逻辑决定 只可读不可写
local PCA9555_REG_IN1 = 0x01                  --输入端口寄存器1 默认值由外部逻辑决定 只可读不可写
local PCA9555_REG_OUT0 = 0x02                 --输出端口寄存器0 默认值为1 可读可写
local PCA9555_REG_OUT1 = 0x03                 --输入端口寄存器1 默认值为1 可读可写
local PCA9555_REG_POL0 = 0x04                 --极性反转寄存器0 默认值为0 可读可写
local PCA9555_REG_POL1 = 0x05                 --极性反转寄存器1 默认值为0 可读可写
local PCA9555_REG0_CFG0 = 0x06                --配置端口寄存器0 默认为1 可读可写
local PCA9555_REG1_CFG1 = 0x07                --配置端口寄存器1 默认为1 可读可写

--[[
配置寄存器说明          1为输入模式     0为输出模式
Config registers
---------------------------------------------------------------------------------------
Config          prot 0 register
Bit                   7       6       5       4       3       2       1
Symbol              C0.7    C0.6    C0.5    C0.4    C0.3    C0.2    C0.0
Default               1       1       1       1       1       1       1
---------------------------------------------------------------------------------------
Config          prot 1 register
Bit                   7       6       5       4       3       2       1
Symbol              C1.7    C1.6    C1.5    C1.4    C1.3    C1.2    C1.0
Default               1       1       1       1       1       1       1
---------------------------------------------------------------------------------------
]]

--[[
pca9555初始化
@api pca955.setup(i2cid, addr,mode)
@number i2cid 所在的i2c总线
@number addr pca9555设备的i2c地址
@number mode 配置输入输出模式  --0xffff 高八位配置IO 17-10 低八位配置IO 7-0
@return 初始化失败，返回nil
@usage
    i2c.setup(0, i2c.FAST)
    pca9555.setup(0,0x20,0xffff)
]]
function pca9555.setup(i2cid,addr,mode)
    PCA9555_i2cid=i2cid
    PCA9555_addr=addr
    PCA9555_mode=mode
    readEncoder()
    local tmp=i2c.readReg(PCA9555_i2cid, PCA9555_addr, 0x02, 2)
    if tmp==nil then
        log.info("PCA9555初始化失败")
        return nil
    end
    if  PCA9555_mode~=nil  then
        i2c.writeReg(PCA9555_i2cid,PCA9555_addr,0x06,pack.pack("<H",PCA9555_mode))
        i2c.writeReg(PCA9555_i2cid,PCA9555_addr,0x02,pack.pack("<H",PCA9555_IOstart))
    else
        local recvData=i2c.readReg(PCA9555_i2cid, PCA9555_addr,0x00,2)
        _,recvData=pack.unpack(recvData,"<H")
        log.info("pca9555默认为完全输入模式",recvData)
    end
end

--[[
pca9555 pin控制
@api pca9555.pin(pin,val)
@number pin 引脚 0-7 10-17
@number val 高/低电平 1/0
@return number 如果val未填,则读取pin的输出电平
@usage
    for i=0,7 do
        pca9555.pin(i,0)
    end
]]
function pca9555.pin(pin,val)
    if pin==nil then
        log.info("请选择引脚")
    elseif pin then
        if val==nil then
            if pin>9 then
                pin=pin-2
            end
            local tmp=i2c.readReg(PCA9555_i2cid, PCA9555_addr,0x00,2)
            _,tmp=pack.unpack(tmp,"<H")
            val=(tmp&(1<<pin))>>pin
            return val
        elseif val==0 then
            if pin>9 then
                pin=pin-2
            end
            PCA9555_IOstart=PCA9555_IOstart&(~(1<<pin))
            i2c.writeReg(PCA9555_i2cid,PCA9555_addr,0x02,pack.pack("<H",PCA9555_IOstart))
        else
            if pin>9 then
                pin=pin-2
            end
            PCA9555_IOstart=PCA9555_IOstart|(1<<pin)
            i2c.writeReg(PCA9555_i2cid,PCA9555_addr,0x02,pack.pack("<H",PCA9555_IOstart))
        end
    end
end

return pca9555
