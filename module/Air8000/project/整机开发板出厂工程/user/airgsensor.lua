local airgsensor = {}
local intPin = gpio.WAKEUP2

dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")
httpplus = require("httpplus")
local run_state = false  -- 判断本UI DEMO 是否运行
local interrupt_state = false  --  true 开始读取运动传感器数据，false 停止读取


local da221Addr = 0x27
local soft_reset = {0x00, 0x24}         -- 软件复位地址
local chipid_addr = 0x01                -- 芯片ID地址
local rangeaddr = {0x0f, 0x00}          -- 设置加速度量程，默认2g
local int_set1_reg = {0x16, 0x87}       --设置x,y,z发生变化时，产生中断
local int_set2_reg = {0x17, 0x10}       --使能新数据中断，数据变化时，产生中断，本程序不设置
local int_map1_reg = {0x19, 0x04}       --运动的时候，产生中断
local int_map2_reg = {0x1a, 0x01}

local active_dur_addr = {0x27, 0x04}    -- 设置激活时间
local active_ths_addr = {0x28, 0x14}    -- 设置激活阈值
local odr_addr = {0x10, 0x08}           -- 设置采样率 100Hz
local mode_addr = {0x11, 0x00}          -- 设置正常模式
local int_latch_addr = {0x21, 0x02}     -- 设置中断锁存
 
local i2cId = 0
local x_lsb_reg = 0x02
local x_msb_reg = 0x03
local y_lsb_reg = 0x04
local y_msb_reg = 0x05
local z_lsb_reg = 0x06
local z_msb_reg = 0x07
local x,y,z=0,0,0

local is_da221_init = false
local logSwitch = true
local moduleName = "da221"


local function start_interrupt()
    interrupt_state = true
end

local function stop_interrupt()
    interrupt_state = false
end

----是否打印日志
local function logF(...)
    if logSwitch then
        log.info(moduleName, ...)
    end
end


-- ------取ACTIVE_THS (28H)寄存器的中断阈值
-- active_th 为写入寄存器的数值（此处为 1），K 为与量程相关的系数：

-- ±2g 量程：K = 3.91 mg（1 LSB 对应 3.91 mg）。
-- ±4g 量程：K = 7.81 mg。
-- ±8g 量程：K = 15.625 mg。



local function read_xyz() ---读取三轴数据
    i2c.send(i2cId, da221Addr, x_lsb_reg, 1)   --读取X轴低字节（LSB） -- 发送LSB寄存器地址
    local recv_x_lsb = i2c.recv(i2cId, da221Addr, 1) -- 接收1字节LSB数据
    i2c.send(i2cId, da221Addr, x_msb_reg, 1)   --读取X轴高字节（MSB） --读取X轴高字节（MSB）  
    local recv_x_mab = i2c.recv(i2cId, da221Addr, 1)   ---- 接收1字节MSB数据
    local x_data = (string.byte(recv_x_mab) << 8) | string.byte(recv_x_lsb)
    --↑ 组合16位数据: MSB左移8位 + LSB    原理：高字节占据高位，低字节占据低位

    i2c.send(i2cId, da221Addr, y_lsb_reg, 1)
    local recv_y_lsb = i2c.recv(i2cId, da221Addr, 1)
    i2c.send(i2cId, da221Addr, y_msb_reg, 1)
    local recv_y_mab = i2c.recv(i2cId, da221Addr, 1)
    local y_data = (string.byte(recv_y_mab) << 8) | string.byte(recv_y_lsb)

    i2c.send(i2cId, da221Addr, z_lsb_reg, 1)
    local recv_z_lsb = i2c.recv(i2cId, da221Addr, 1)
    i2c.send(i2cId, da221Addr, z_msb_reg, 1)
    local recv_z_mab = i2c.recv(i2cId, da221Addr, 1)
    local z_data = (string.byte(recv_z_mab) << 8) | string.byte(recv_z_lsb)

    local x_accel = x_data / 1024  -- 原始值除以1024得实际加速度（单位：g）
    local y_accel = y_data / 1024
    local z_accel = z_data / 1024
    --↑ 原理：1024 = 2¹⁰，表明传感器量程为±2g（满量程对应±1024）
    -- 例如：静止时Z轴≈1024 → 1g，水平放置时X/Y轴≈0

     return x_accel, y_accel, z_accel
end
local intstu=false

-- local function x1int()
--     x1,y1,z1 = read_xyz()
-- end
-- sysplus.taskInit(x1int)


-- 中断模式
local function ind()
    if interrupt_state then         --如果点击开始按钮
        if gpio.get(intPin) == 1 then
        intstu=true             --触发中断就更改电平状态
            --中断情况       
        --log.info("超过阈值")     
        x,y,z = read_xyz()      --读取x，y，z轴的数据
       -- log.info("测试x", x, "y", y, "z", z)
        else
        intstu=false
        end       
    end
end    
gpio.setup(intPin, ind)


local function da221_init()
    log.info("da221 init...")
    --关闭i2c
    i2c.close(i2cId)            ------初始化i2c
    --重新打开i2c,i2c速度设置为低速
    i2c.setup(i2cId, i2c.SLOW)

    sys.wait(50)
    i2c.send(i2cId, da221Addr, soft_reset, 1)
    sys.wait(50)
    i2c.send(i2cId, da221Addr, chipid_addr, 1)
    local chipid = i2c.recv(i2cId, da221Addr, 1)
    log.info("i2c", "chipid",chipid:toHex())
    if string.byte(chipid) == 0x13 then
        log.info("da221 init success")
        is_da221_init = true    -- da221 初始化成功 
        --sys.publish("DA221_INIT_SUCCESS")
    else
        is_da221_init = false   -- da221 初始化失败
        --log.info("da221 init fail")
    end

-----初始化gsensor------
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

function da221_run()
    -- 轮询读取三轴速度
    log.info("interrupt_state123",is_da221_init,interrupt_state )
    da221_init()
    log.info("interrupt_state",is_da221_init,interrupt_state )
    while true do
        if is_da221_init then
            -- return  -- i2c 如果已经初始化 就直接退出这个函数，不往下执行
            -- 读取三轴速度
            x,y,z = read_xyz()      --读取x，y，z轴的数据
            log.info("x", x, "y", y, "z", z)
        end
        sys.wait(10000)
    end
end

--------------------------------以下是UI页面核心程序-------------------
function airgsensor.run()       
    log.info("airgsensor.run")
    lcd.setFont(lcd.font_opposansm12_chinese) -- 设置中文字体
    run_state = true
    sys.taskInit(da221_run)  --读取先，y，z值  
    while true do
        sys.wait(10)         
        lcd.clear(_G.bkcolor) --清除页面
        lcd.drawStr(10,80,"运动传感器测试" )
         ----- 传感器任务----
        lcd.drawStr(15,110, "X:")
        lcd.drawStr(15,130, "Y:")
        lcd.drawStr(15,150, "Z:")
        lcd.drawStr(15,170, "中断阈值:")
        lcd.drawStr(15,190, "中断情况:")  
        lcd.drawStr(28,110, x.."g")   ---显示X轴加速度数值
        lcd.drawStr(28,130, y.."g")
        lcd.drawStr(28,150, z.."g") 
       
        lcd.drawStr(70,170, "78.2mg") ----中断阈值的值 20*K=20*3.91   ,可根据实际情况换算修改       

        lcd.showImage(20,360,"/luadb/back.jpg")

        if interrupt_state then  --如果是开始状态下           
              
            if intstu  then     --如果触发了中断
                lcd.drawStr(70,190, "触发中断")
                lcd.drawStr(28,110, x.."g")
                lcd.drawStr(28,130, y.."g")
                lcd.drawStr(28,150, z.."g")             
            else 
                lcd.drawStr(70,190, "未触发")
                lcd.showImage(130,370,"/luadb/start.jpg")     --  关闭中断模式
            end            
            --lcd.showImage(130,370,"/luadb/stop.jpg")      --  开启中断模式
        else            
        lcd.showImage(130,370,"/luadb/start.jpg")    --  关闭中断模式            
        end

        lcd.showImage(0,448,"/luadb/Lbottom.jpg")
        lcd.flush()--刷新页面        
        if not  run_state  then    -- 等待结束，返回主界面
        x,y,z=0,0,0
        sysplus.taskInitEx(stop_interrupt, "stop_interrupt")
            return true
        end
    end
end



function airgsensor.tp_handal(x,y,event)       
    if x > 20 and  x < 100 and y > 360  and  y < 440 then   -- 返回主界面
        run_state = false
    elseif x > 130 and  x < 230 and y > 370  and  y < 417 then
        if not interrupt_state then
            sysplus.taskInitEx(start_interrupt, "start_interrupt")
        else
            --sysplus.taskInitEx(stop_interrupt, "stop_interrupt")
        end
    end
end




return airgsensor
