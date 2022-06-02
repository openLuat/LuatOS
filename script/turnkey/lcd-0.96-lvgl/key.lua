local key = {}

local cb = nil--按键回调函数

--设置回调
function key.setCb(f)
    cb = f
end

--消抖处理
local dt = 200--过滤时间：20ms
local isLock = nil--按键锁

--按键回调
function key.cb(k,p)
    log.info("key",k,p,isLock,cb)
    if not cb or not p or isLock then return end
    cb(k)
    isLock = true
    sys.timerStart(function() isLock = false end,dt)
end

--几个按键 左L 右R 上U 下D 确定O
gpio.setup(device.keyL, function(p) key.cb("L",p==0) end, gpio.PULLUP)
gpio.setup(device.keyR, function(p) key.cb("R",p==0) end, gpio.PULLUP)
gpio.setup(device.keyU, function(p) key.cb("U",p==0) end, gpio.PULLUP)
gpio.setup(device.keyD, function(p) key.cb("D",p==0) end, gpio.PULLUP)
gpio.setup(device.keyO, function(p) key.cb("O",p==0) end, gpio.PULLUP)


return key
