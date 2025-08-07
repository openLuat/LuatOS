--[[
@module pcf8563t
@summary pcf8563t时钟模块
@version 1.0
@date    2023.11.02
@author  wendal
@usage
-- 数据手册 https://www.nxp.com.cn/docs/zh/data-sheet/PCF8563.pdf
local pcf8563t = require "pcf8563t"

local i2cid = 1
i2c.setup(i2cid, i2c.FAST)
pcf8563t.setup(i2cid) -- 选一个i2c, 也可以是软件i2c对象

-- 设置时间
local time = {year=2023,mon=11,day=2,wday=5,hour=13,min=14,sec=15}
pcf8563t.write(time)

-- 读取时间
local time = pcf8563t.read()
log.info("time",time.year,time.mon,time.day, time.hour,time.min,time.sec, "week=".. time.wday)

-- 设置闹钟, 并自动清除中断标志,开启alarm功能
alarm = {day=2,hour=13,min=14,sec=15}
pcf8563t.alarm(alarm)
local alarm_int = 1 -- 选一个GPIO,接时钟模块的INT脚
gpio.setup(1, function()
    log.info("alarm!!!")
    pcf8563t.control(nil, nil, 0, nil)
end, gpio.PULLUP)

-- 主动清除中断标志
pcf8563t.control(nil, nil, 0, nil)
-- 关闭alarm
pcf8563t.control(0, nil, 0, nil)
]]
local pcf8563t = {}

local i2cid = 1             --i2cid
local i2cslaveaddr =   0X51 --slave address
local baseyear = 2000

local REG_SEC = 0X02 
local REG_ALARM = 0x09

local function bcd_to_hex(data)
    return bit.rshift(data,4)*10+bit.band(data,0x0f)
 
end

local function hex_to_bcd(data)
    return bit.lshift(data//10,4)+data%10
end

--[[
初始化
@api pcf8563t.setup(id, by)
@int i2c设备的id, 或者软件i2c的对象,必须填
@int 年份基准,默认是2000, 可以不填
@return boolean 成功返回true, 否则返回false
]]
function pcf8563t.setup(id, by)
    i2cid = id
    local t = pcf8563t.read()
    if by then
        baseyear = by
    end
    return t and t.year ~= nil
end

--[[
读出时间
@api pcf8563t.read()
@return table 时间信息,如果读取失败会返回空的表
@usage
local time = pcf8563t.read()
if time and time.year then
    log.info("time", json.encode(time))
end
-- time 是个table, 有以下字段, 与os.date是兼容的
-- time.year 年份
-- time.mon  月份
-- time.day  月内的天数
-- time.hour 小时, 24进制
-- time.min  分钟
-- time.sec  秒
-- time.wday 周N, 周日为1, 周六为7
]]
function pcf8563t.read()
    -- read time
    local time_data = {}
    local data = i2c.readReg(i2cid, i2cslaveaddr, REG_SEC, 7)
    if not data or #data ~= 7 then
        return time_data
    end
    time_data.year = bcd_to_hex(data:byte(7)) + baseyear
    time_data.mon = bcd_to_hex(data:byte(6) & 0x9F)
    time_data.wday = bcd_to_hex(data:byte(5) & 0x07) + 1
    time_data.day = bcd_to_hex(data:byte(4) & 0x3F)
    time_data.hour = bcd_to_hex(data:byte(3) & 0x3F)
    time_data.min = bcd_to_hex(data:byte(2) & 0x7F)
    time_data.sec = bcd_to_hex(data:byte(1) & 0x7F)
	return time_data
end

--[[
设置时间
@api pcf8563t.write(time)
@table 时间信息,与pcf8563t.read的字段规则是一样的
@return nil 无返回值
@usage
local time = {year=2023,mon=11,day=2,wday=5,hour=13,min=14,sec=15}
pcf8563t.write(time)
]]
function pcf8563t.write(time)
    -- set time
    local data7 = hex_to_bcd(time.year - baseyear)
    local data6 = hex_to_bcd(time.mon)
    local data5 = hex_to_bcd(time.wday - 1)
    local data4 = hex_to_bcd(time.day)
    local data3 = hex_to_bcd(time.hour)
    local data2 = hex_to_bcd(time.min)
    local data1 = hex_to_bcd(time.sec)
    i2c.writeReg(i2cid, i2cslaveaddr, REG_SEC, string.char(data1,data2,data3,data4,data5,data6,data7))
end

--[[
设置闹钟
@api pcf8563t.alarm(time)
@table 时间信息
@return nil 无返回值
@usage
-- 设置闹钟, 并自动清除中断标志,开启alarm功能
-- 注意只能设置天(wday)/小时(hour)/分钟(min)/周天(wday), 无法设置年月
alarm = {day=2,hour=13,min=14}
pcf8563t.alarm(alarm)
local alarm_int = 1 -- 选一个GPIO,接时钟模块的INT脚
gpio.setup(1, function()
    log.info("alarm!!!")
    pcf8563t.control(nil, nil, 0, nil)
end, gpio.PULLUP)

-- 注意规则!!! 传入的值,需要全部匹配才会触发
-- 例如, 每当min=1时触发, 不判断hour/day/wday
alarm = {min=1}
-- 例如, 每当min=1且hour=0时触发, 不判断day/wday
alarm = {min=1, hour=0}
-- 全部day/hour/min都满足才触发
alarm = {day=2,hour=13,min=14}
-- 全部day/hour/min/wday都满足才触发
alarm = {day=2,hour=13,min=14,wday=2}
]]
function pcf8563t.alarm(time)
    -- set time
    local data5 = time.wday and hex_to_bcd(time.wday - 1) or  0x80
    local data4 = time.day and hex_to_bcd(time.day) or  0x80
    local data3 = time.hour and hex_to_bcd(time.hour) or  0x80
    local data2 = time.min and hex_to_bcd(time.min) or  0x80
    -- local data1 = time.sec and hex_to_bcd(time.sec) or 0
    i2c.writeReg(i2cid, i2cslaveaddr, REG_ALARM, string.char(data2,data3,data4,data5))
    local dataN = i2c.readReg(i2cid, i2cslaveaddr, REG_ALARM, 4)
    log.info("数据对比", string.char(data2,data3,data4,data5):toHex(), dataN:toHex())
    pcf8563t.control(1, nil, 0, nil)
end

--[[
设置闹钟
@api pcf8563t.control(AIE, TIE, AF, TF)
@int 闹钟开关, 0 关闭, 1 开始, nil保持原样
@int 定时器开关, 0 关闭, 1 开始, nil保持原样
@int 清除闹钟中断, 0 清除, nil保持原样
@int 清除定时器中断, 0 清除, nil保持原样
@return nil 无返回值
@usage
-- 主动清除中断标志
pcf8563t.control(nil, nil, 0, nil)
-- 关闭alarm
pcf8563t.control(0, nil, 0, nil)
]]
function pcf8563t.control(AIE, TIE, AF, TF)
    local data = i2c.readReg(i2cid, i2cslaveaddr, 0x01, 1)
    if data and #data == 1 then
        data = data:byte()
        if AIE then
            data = data | ((AIE & 0x01) << 1)
        end
        if TIE then
            data = data | (TIE & 0x01)
        end
        if AF then
            data = data | ((AF & 0x01) << 3)
        end
        if TF then
            data = data | ((TF & 0x01) << 2)
        end
        i2c.writeReg(i2cid, i2cslaveaddr, 0x01, string.char(data))
        local data2 = i2c.readReg(i2cid, i2cslaveaddr, 0x01, 1)
        log.info("数据对比", string.char(data):toHex(), data2:toHex())
    end 
end

return pcf8563t
