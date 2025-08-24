--[[
@module exvib
@summary exvib 三轴加速度传感器扩展库
@version 1.0
@date    2025.08.10
@author  李源龙
@usage
-- 用法实例
注意:

1. exvib.lua可适用于合宙内部集成了G-Sensor加速度传感器DA221的模组型号，
目前仅有Air8000系列模组内置了DA221，Air7000推出时也会内置该型号G-Sensor；

2. DA221在Air8000内部通过I2C1与之通信，并通过WAKEUP2接收运动监测中断，
如您使用合宙其它型号模组外接DA221时，比如Air780EGH，建议与Air8000保持一致也选用I2C1和WAKEUP2
(该管脚即为Air780EGH的PIN79:USIM_DET)，这样便可以无缝使用本扩展库，DA221的供应商为苏州明皜
如需采购DA221或者其他更高端的加速度传感器可以联系他们；

3. DA221作为加速度传感器，LuatOS仅支持运动检测这一功能，主要用于震动检测，运动检测，跌倒检测，
搭配GNSS实现震动然后定位的功能，其余功能请自行研究，合宙提供了三种应用场景，如果需要适配自己的场景需求，
请参考手册参数自行修改代码，调试适合自己场景的传感器值，合宙不提供DA221任何其它功能的任何形式的技术支持；

关于exvib库的三种模式主要用于以下场景：
1，微小震动检测，用于检测轻微震动的场景，例如用手敲击桌面；加速度量程2g；
2，运动检测，用于电动车或汽车行驶时的检测和人行走和跑步时的检测；加速度量程4g；
3，跌倒检测，用于人或物体瞬间跌倒时的检测；加速度量程8g；

exvib=require("exvib")

local intPin=gpio.WAKEUP2   --中断检测脚，内部固定wakeup2
local tid   --获取定时打开的定时器id
local num=0 --计数器 
local ticktable={0,0,0,0,0} --存放5次中断的tick值，用于做有效震动对比
local eff=false --有效震动标志位，用于判断是否触发定位


--有效震动模式
--tick计数器，每秒+1用于存放5次中断的tick值，用于做有效震动对比
-- local function tick()
--     num=num+1
-- end
-- --每秒运行一次计时
-- sys.timerLoopStart(tick,1000)

-- --有效震动判断
-- local function ind()
--     log.info("int", gpio.get(intPin))
--     if gpio.get(intPin) == 1 then
--         --接收数据如果大于5就删掉第一个
--         if #ticktable>=5 then
--             log.info("table.remove",table.remove(ticktable,1))
--         end
--         --存入新的tick值
--         table.insert(ticktable,num)
--         log.info("tick",num,(ticktable[5]-ticktable[1]<10),ticktable[5]>0)
--         log.info("tick2",ticktable[1],ticktable[2],ticktable[3],ticktable[4],ticktable[5])
--         --表长度为5且，第5次中断时间间隔减去第一次间隔小于10s，且第5次值为有效值
--         if #ticktable>=5 and (ticktable[5]-ticktable[1]<10 and ticktable[1]>0) then
--             log.info("vib", "xxx")
--             --是否要去触发有效震动逻辑
--             if eff==false then
--                 sys.publish("EFFECTIVE_VIBRATION")
--             end
--         end
--     end
-- end

-- --设置30s分钟之后再判断是否有效震动函数
-- local function num_cb()
--     eff=false
-- end

-- local function eff_vib()
--     --触发之后eff设置为true，30分钟之后再触发有效震动
--     eff=true
--     --30分钟之后再触发有效震动
--     sys.timerStart(num_cb,180000)
-- end

-- sys.subscribe("EFFECTIVE_VIBRATION",eff_vib)



--持续震动模式

--持续震动模式中断函数
local function ind()
    log.info("int", gpio.get(intPin))
    --上升沿为触发震动中断
    if gpio.get(intPin) == 1 then
        local x,y,z =  exvib.read_xyz()      --读取x，y，z轴的数据
        log.info("x", x..'g', "y", y..'g', "z", z..'g')
    end
end


local function vib_fnc()
    -- 1，微小震动检测，用于检测轻微震动的场景，例如用手敲击桌面；加速度量程2g；
    -- 2，运动检测，用于电动车或汽车行驶时的检测和人行走和跑步时的检测；加速度量程4g；
    -- 3，跌倒检测，用于人或物体瞬间跌倒时的检测；加速度量程8g；
    --打开震动检测功能
    exvib.open(1)
    --设置gpio防抖100ms
    gpio.debounce(intPin, 100)
    --设置gpio中断触发方式wakeup2唤醒脚默认为双边沿触发
    gpio.setup(intPin, ind)

end

sys.taskInit(vib_fnc)

]]
local exvib={}

local i2cId = 0

local da221Addr = 0x27
local soft_reset = {0x00, 0x24}         -- 软件复位地址
local chipid_addr = 0x01                -- 芯片ID地址
local rangeaddr = {0x0f, 0x00}          -- 设置加速度量程，默认2g
-- local rangeaddr = {0x0f, 0x01}          -- 设置加速度量程，默认4g
-- local rangeaddr = {0x0f, 0x10}          -- 设置加速度量程，默认8g
local int_set1_reg = {0x16, 0x87}       --设置x,y,z发生变化时，产生中断
local int_set2_reg = {0x17, 0x10}       --使能新数据中断，数据变化时，产生中断，本程序不设置
local int_map1_reg = {0x19, 0x04}       --运动的时候，产生中断
local int_map2_reg = {0x1a, 0x01}

local active_dur_addr = {0x27, 0x01}    -- 设置激活时间，默认0x01
local active_ths_addr = {0x28, 0x33}    -- 设置激活阈值，灵敏度最高
-- local active_ths_addr = {0x28, 0x80}    -- 设置激活阈值，灵敏度适中
-- local active_ths_addr = {0x28, 0xFE}    -- 设置激活阈值，灵敏度最低
local odr_addr = {0x10, 0x08}           -- 设置采样率 100Hz
local mode_addr = {0x11, 0x00}          -- 设置正常模式
local int_latch_addr = {0x21, 0x02}     -- 设置中断锁存

local x_lsb_reg = 0x02 -- X轴LSB寄存器地址
local x_msb_reg = 0x03 -- X轴MSB寄存器地址
local y_lsb_reg = 0x04 -- Y轴LSB寄存器地址
local y_msb_reg = 0x05 -- Y轴MSB寄存器地址
local z_lsb_reg = 0x06 -- Z轴LSB寄存器地址
local z_msb_reg = 0x07 -- Z轴MSB寄存器地址

local active_state = 0x0b -- 激活状态寄存器地址
local active_state_data

--[[
    获取da221的xyz轴数据
@api exvib.read_xyz()
@return number x轴数据，number y轴数据，number z轴数据
@usage
    local x,y,z =  exvib.read_xyz()      --读取x，y，z轴的数据
        log.info("x", x..'g', "y", y..'g', "z", z..'g')
]]
function exvib.read_xyz()
    -- da221是LSB在前，MSB在后，每个寄存器都是1字节数据，每次读取都是6个寄存器数据一起获取
    -- 因此直接从X轴LSB寄存器(0x02)开始连续读取6字节数据(X/Y/Z各2字节)，避免出现数据撕裂问题
    i2c.send(i2cId, da221Addr, x_lsb_reg, 1)
    local recv_data = i2c.recv(i2cId, da221Addr, 6)

    -- LSB数据格式为: D[3] D[2] D[1] D[0] unused unused unused unused
    -- MSB数据格式为: D[11] D[10] D[9] D[8] D[7] D[6] D[5] D[4]
    -- 数据位为12位，需要将MSB数据左移4位，LSB数据右移4位，最后进行或运算
    -- 解析X轴数据 (LSB在前，MSB在后)
    local x_data = (string.byte(recv_data, 2) << 4) | (string.byte(recv_data, 1) >> 4)

    -- 解析Y轴数据 (LSB在前，MSB在后)
    local y_data = (string.byte(recv_data, 4) << 4) | (string.byte(recv_data, 3) >> 4)

    -- 解析Z轴数据 (LSB在前，MSB在后)
    local z_data = (string.byte(recv_data, 6) << 4) | (string.byte(recv_data, 5) >> 4)

    -- 转换为12位有符号整数
    -- 判断X轴数据是否大于2047，若大于则表示数据为负数
    -- 因为12位有符号整数的范围是 -2048 到 2047，原始数据为无符号形式，大于2047的部分需要转换为负数
    -- 通过减去4096 (2^12) 将无符号数转换为对应的有符号负数
    if x_data > 2047 then x_data = x_data - 4096 end
    -- 判断Y轴数据是否大于2047，若大于则进行同样的有符号转换
    if y_data > 2047 then y_data = y_data - 4096 end
    -- 判断Z轴数据是否大于2047，若大于则进行同样的有符号转换
    if z_data > 2047 then z_data = z_data - 4096 end

    -- 转换为加速度值（单位：g）
    local x_accel = x_data / 1024
    local y_accel = y_data / 1024
    local z_accel = z_data / 1024

    -- 输出加速度值（单位：g）
    return x_accel, y_accel, z_accel
end

--初始化da221
local function da221_init()
    gpio.setup(24, 1, gpio.PULLUP)  -- gsensor 开关
    --关闭i2c
    i2c.close(i2cId)
    --重新打开i2c,i2c速度设置为低速
    i2c.setup(i2cId, i2c.SLOW)

    sys.wait(50)
    i2c.send(i2cId, da221Addr, soft_reset, 1)   --复位da221
    sys.wait(50)
    i2c.send(i2cId, da221Addr, chipid_addr, 1)  --读取芯片id
    local chipid = i2c.recv(i2cId, da221Addr, 1)    --接收返回的芯片id
    log.info("i2c", "chipid",chipid:toHex())
    if string.byte(chipid) == 0x13 then
        log.info("exvib init success")
    else
        log.info("exvib init fail")
    end
    -- 设置寄存器
    i2c.send(i2cId, da221Addr, rangeaddr, 1)    --设置加速度量程，默认2g
    sys.wait(5)
    i2c.send(i2cId, da221Addr, int_set1_reg, 1) --设置x,y,z发生变化时，产生中断
    sys.wait(5)
    i2c.send(i2cId, da221Addr, int_map1_reg, 1)--运动的时候，产生中断
    sys.wait(5)
    i2c.send(i2cId, da221Addr, active_dur_addr, 1)-- 设置激活时间，默认0x00
    sys.wait(5)
    i2c.send(i2cId, da221Addr, active_ths_addr, 1)-- 设置激活阈值
    sys.wait(5)
    i2c.send(i2cId, da221Addr, mode_addr, 1)-- 设置模式
    sys.wait(5)
    i2c.send(i2cId, da221Addr, odr_addr, 1)-- 设置采样率
    sys.wait(5)
    i2c.send(i2cId, da221Addr, int_latch_addr, 1)-- 设置中断锁存 中断一旦触发将保持，直到手动清除
    sys.wait(5)
end

--[[
    打开da221
@api exvib.open(mode)
@number da221模式设置，1，微小震动检测，用于检测轻微震动的场景，例如用手敲击桌面；加速度量程2g；
                        2，运动检测，用于电动车或汽车行驶时的检测和人行走和跑步时的检测；加速度量程4g；
                        3，跌倒检测，用于人或物体瞬间跌倒时的检测；加速度量程8g；
@return nil
@usage
    exvib.open(1)
]]
function exvib.open(mode)
    if mode==1 or tonumber(mode)==1 then
        --轻微检测
        log.info("轻微检测")
        rangeaddr = {0x0f, 0x00}          -- 设置加速度量程，默认2g
        active_ths_addr = {0x28, 0x33}    -- 设置激活阈值
        odr_addr = {0x10, 0x04}           -- 设置采样率 15.63Hz
        active_dur_addr = {0x27, 0x01}    -- 设置激活时间
    elseif mode==2 or tonumber(mode)==2 then
        --常规检测
        rangeaddr = {0x0f, 0x01}          -- 设置加速度量程，默认4g
        active_ths_addr = {0x28, 0x26}    -- 设置激活阈值
        odr_addr = {0x10, 0x08}           -- 设置采样率 250Hz
        active_dur_addr = {0x27, 0x14}    -- 设置激活时间
    elseif mode==3 or tonumber(mode)==3 then
        --高动态检测
        rangeaddr = {0x0f, 0x10}          -- 设置加速度量程，默认8g
        active_ths_addr = {0x28, 0x80}    -- 设置激活阈值
        odr_addr = {0x10, 0x0F}           -- 设置采样率 1000Hz
        active_dur_addr = {0x27, 0x04}    -- 设置激活时间
    end
    sys.taskInit(da221_init)
end

--[[
    关闭da221
@api exvib.close()
@return nil
@usage
    exvib.close()
]]
function exvib.close()
    gpio.close(24)  -- gsensor供电关闭
    log.info("exvib close..")
end


return exvib