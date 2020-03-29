# Luat API列表

当前手工维护, 待项目完善后, 使用工具自动生成

## 核心API

场景: 每隔5分钟唤醒一次/按键唤醒, 读取gpio状态, 写uart数据, 联网发送数据到服务器, 再次进入低功耗模式

功能所需:
* sys     -- 支撑整个流程
* timer   --  支撑定时唤醒和流程控制
* 流程控制 --  等待联网
* pm      --  进入低功耗
* gpio    --  读取gpio状态/按键唤醒
* uart    --  写串口数据
* socket  --  联网读写数据
* lwm2m   --  电信卡联网读写数据
* device  --  设备信息,联网数据中包含设备识别号(imei)

--------------------------------------------------------------
### API列表

```lua
-- 底层相关
sys.run(mode)                    -- rtos核心机制启动,总是main.lua最后一句
sys.restart(reson)               -- 重启
sys.reson()                      -- 系统的原因(按键开机/定时器唤醒/中断唤醒...)

-- 功耗管理
pm.mode(pm.IDLE)                 -- 进入指定功耗模式

-- 定时器
timer.start(timer_type, timeout, callback, arg1, ...) -- 启动一个定时器
timer.stop(id)                  -- 停止一个定时器

-- 流程控制相关
task.wait(timeout)              -- 当前协程让出调度权
task.waitUtil(topic, timeout)   -- 等待topic发布,或超时
task.publish(topic, arg1, ...)  -- 发布topic消息
task.subscribe(topic, func)     -- 订阅topic消息
task.start(func, arg1, ...)     -- 启动一个协程

-- 低功耗相关
lpmem.write(pos, data)          -- 写数据到不掉电内存
lpmen.read(pos, len)            -- 从不掉电内读数据

-- GPIO相关
pmu.ldo(zone, mode)             -- 设置电压域
gpio.setup(pin, mode, pullup, func) -- 设置GPIO脚的功能
gpio.set(pin, value)            -- 设置输出电平
gpio.get(pin)            -- 获取输入电平
gpio.odr(pin)                   -- 获取输出电平

-- UART相关
uart.setup(id, bandrate, bit, nor, stop_bit) -- 配置uart
uart.write(id, data)             -- 发送数据到UART
uart.read(id, maxLen)           -- 读取数据
uart.close(id)                  -- 关闭uart
uart.on(event, callback)        -- uart的事件回调
uart.tnow(id, pin,nor)          -- 485控制管脚 

-- socket相关
socket.ready()                  -- 判断是否已经附着到网络
socket.new(mode, cert)          -- 新建一个socket, mode可以是tcp/udp等
socket:select(msg_id)           -- 等待消息
socket:connect(host, port, timeout) -- 建立连接
socket:send(data, callback)     -- 发送数据
socket:recv(timeout, callback)  -- 接收数据
socket:read(maxLen)             -- 从缓冲区读取数据
socket:write(data)              -- 将数据写入缓冲区
socket:close()                  -- 关闭连接
socket:on(event, callback)      -- 各种回调

-- lwm2m 相关
lwm2m.xxx                       -- 与socket类似

-- coap相关
coap.xxx                        -- 与socket类似

-- 系统信息
device.imei()                   -- 设备IMEI
device.sn(val)                  -- 设备SN, 填入参数就设置sn, 不填就返回sn
device.version()                -- 设备版本号
device.muid()                   -- 设备识别号

-- SIM卡相关
sim.iccid()                     -- SIM的ICCID
sim.imsi()                      -- 设备IMSI

-- 网络状态相关
modem.cellInfo()                -- 基站信息
modem.csq()                     -- 信号强度
modem.stat()                    -- 网络状态
```

--------------------------------------------------------------
### 设想的lua代码
```lua
-- 定时发送GPIO1的状态到服务器

local TG = 1
gpio.setup(TG, gpio.INPUT, gpio.PULLUP)
uart.setup(1)

task.taskInit(function()
    task.waitUtil("IP_READY", 60000) -- 等待联网,最多60秒
    -- 读取设备信息
    local imei = device.imei()
    local iccid = sim.iccid()
    local stat = gpio.get(TG)
    local str = imei .. "," .. iccid .. "," .. stat
    -- 写入uart
    uart.write(1, str .. "\r")
    -- 发送到服务器
    local u = socket.create("udp", "udplab.openluat.com", 123456)
    -- u:connect(30000)
    u:send(imei .. "," .. iccid .. "," .. stat)
    u:close()
    -- 启动定时器, 5分钟后唤醒
    timer.start(timer.hw, 5*60*1000)
    -- 进入低功耗模式
    pm.mode(pm.PM2)
end)

sys.run() -- TODO 反正都写这句,那就干脆去掉?
```

### 设想LUA代码2
```lua
-- 以下demo代码基于如下场景：
--1. GPIO1为RETIO（深睡眠仍然可以唤醒的io），高电平工作在SLEEP1模式，低电平工作在IDLE模式
--2. 串口1透传udp://udplab.openluat.com:8888

pm.mode(pm.IDLE) -- 功耗管理工作在idle模式

-- gpio1 功耗模式管理
gpio.setup(1, gpio.INPUT, gpio.PULLUP, function(value)
    pm.mode(value == 1 and pm.PM1 or pm.IDLE)
end)

uart.setup(1, ...)

uart.on(1, 'recv', function(len)
    sys.publish('SEND_REQ', uart.read(1, len))
end)

task.init(function()
    while true do
        if not socket.ready() then
            task.wait('IP_READY')
        end

        local c = socket.new('udp')

        if c:connect('udplab.openluat.com', 8888) then
            local loop = true
            while loop do
                local r, d = c:recv('SEND_REQ')
                if r == 'data' then
                    uart.write(1, d)
                elseif r == 'msg' then
                    for _, v in ipairs(d) do
                        if not c:send(v) then
                            loop = false
                            log.warn('demo', 'socket send error', socket.errorno())
                            break
                        end
                    end
                elseif r == 'error' then
                    loop = false
                    log.warn('demo', 'socket recv error', socket.errorno())
                end
            end
        else
            log.warn('demo', 'socket conn error', socket.errorno())
        end
        c:close()
    end
end)
```

