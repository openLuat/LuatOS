--[[
@module tm1637
@summary tm1637 数码管
@version 1.0
@date    2022.04.06
@author  Dozingfiretruck
@usage
--注意:因使用了sys.wait()所有api需要在协程中使用
-- 用法实例
local tm1637 = require "tm1637"
sys.taskInit(function()
    count = 0
    tm1637.init(1,4)
    tm1637.singleShow(0,2)
    tm1637.singleShow(1,1,true)
    tm1637.singleShow(2,3)
    tm1637.singleShow(3,6)
    while 1 do
        sys.wait(1000)
        if count > 7 then
            count = 0
        end
        log.info("调整亮度", count)
        tm1637.setLight(count)
        count = count + 1
    end
end)
]]
local tm1637 = {}

local sys = require "sys"

local TM1637_SCL
local TM1637_SDA

local function i2c_init(scl,sda)
    TM1637_SCL = gpio.setup(scl, 0, gpio.PULLUP)
    TM1637_SDA = gpio.setup(sda, 0, gpio.PULLUP)
end

local function i2c_strat()
    TM1637_SDA(1)
    TM1637_SCL(1)
    TM1637_SDA(0)
    TM1637_SCL(0)
    -- sys.wait(10)
end
local function i2c_send(data)
    for i = 0, 7, 1 do
        TM1637_SCL(0)
        local mbit = bit.isset(data, i) and 1 or 0
        TM1637_SDA(mbit)
        TM1637_SCL(1)
    end
    TM1637_SCL(0)
    TM1637_SDA(1)
    TM1637_SCL(1)
    -- mack = TM1637_SDA()
    -- if mack == 0 then TM1637_SDA(0) end
    TM1637_SDA(0)
    TM1637_SCL(0)

end
local function i2c_stop()
    TM1637_SCL(0)
    TM1637_SDA(0)
    TM1637_SCL(1)
    TM1637_SDA(1)
end

local function i2c_recv(num)
    local revData = i2c.recv(i2cid, i2cslaveaddr, num)
    return revData
end

--[[ 
      0
     ---
  5 |   | 1   *
     -6-      7 (on 2nd segment)
  4 |   | 2   *
     ---
      3
76543210
 ]]

            --[[   0   1    2    3    4    5    6    7    8    9    A    b    C    d    E    F    G     H    I   J    K     L    M    n    O    P    q    r    S    t    U    v    W    X    y   Z          -   * ]]
local hextable = {0x3f,0x06,0x5b,0x4f,0x66,0x6d,0x7d,0x07,0x7f,0x6f,0x77,0x7c,0x39,0x5e,0x79,0x71,0x3d,0x76,0x06,0x1e,0x76,0x38,0x55,0x54,0x3f,0x73,0x67,0x50,0x6d,0x78,0x3e,0x1c,0x2a,0x76,0x6e,0x5b,0x00,0x40,0x63};


--[[
TM1637显示清空
@api tm1637.clear()
@usage
tm1637.clear()
]]
function tm1637.clear()
    i2c_strat()
    i2c_send(0x40) -- 自加模式
    i2c_stop()
    i2c_strat()
    i2c_send(0xc0)
    for i = 1, 4 do i2c_send(0x00) end
    i2c_stop()
end

--[[
TM1637显示
@api tm1637.singleShow(com,date,comma)
@number com com端口号
@number date 显示数字,0-9即显示0-9,10会显示a以此类推
@bool   comma 是否带逗号或冒号
@usage
tm1637.singleShow(0,2)
tm1637.singleShow(1,1,true)
tm1637.singleShow(2,3)
tm1637.singleShow(3,6)
]]
function tm1637.singleShow(com,date,comma)
    if com then
        i2c_strat()
        i2c_send(0x44) -- 地址模式
        i2c_stop()
        i2c_strat()
        i2c_send(0xc0+com)
        if comma then
            i2c_send(bit.bor(hextable[date+1],0x80))
        else
            i2c_send(hextable[date+1])
        end
        i2c_stop()
    end
end

--[[
TM1637设置亮度
@api tm1637.setLight(light)
@number light 亮度,0-7
@usage
tm1637.setLight(3)
]]
function tm1637.setLight(light)
    i2c_strat()
    i2c_send(bit.bor(light,0x88))
    i2c_stop()
end

--[[
TM1637初始化
@api tm1637.init(scl,sda)
@number scl i2c_scl
@number sda i2c_sda
@return bool   成功返回true
@usage
tm1637.init(1,4)
]]
function tm1637.init(scl,sda)
    i2c_init(scl,sda)
    sys.wait(200)
    tm1637.clear()
    i2c_strat()
    i2c_send(0x8f)
    i2c_stop()
    return true
end

return tm1637
