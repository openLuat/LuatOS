
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "tlink"
VERSION = "1.0.0"

--[[
本示例用于演示定时把温度数据传输到tlink平台, 由tlink平台进行处理, 并在网页端和手机端进行展示

本示例需要使用中国移动或者中国联通NB专有卡, 普通2G/3G/4G卡无法保证正常

-- 设备端接线

1. Air302开发板一块
2. DS18B20传感器一个
    - 需要带上拉电阻4.7k
    - 数据端接入模块/开发板的GPIO17
    - VCC接入VDDIO或其他3.3V供电脚
    - GND接入模块的GND

--- tlink网页端的配置

1. 首先, 请到 http://tlink.io 注册账号, 普通账号即可, 无需企业版
2. 然后, 登录后台, 在左侧菜单, 选择 "设备管理", 然后点击 "添加设备"
3. 新增设备时
    - 3.1 设备名称自选(例如模块的IMEI值)
    - 3.2 链接协议 选"UDP"
    - 3.3 掉线延时 选"300秒"
    - 3.4 传感器, 点"追加",会新增一行
        - 3.4.1 传感器名称, 填"温度传感器"
        - 3.4.2 类型, 选 "数值型"
        - 3.4.3 小数位, 选 "1(小数位)"
        - 3.4.4 单位, 填"摄氏度"
        - 3.4.5 地图, 随便选一个地址就行
    - 3.5 滚动屏幕到底部, 点击"创建设备", 完成基本创建
4. 返回设备列表后, 点击新设备的"设置连接"
    - 4.1 重点, 设备信息展示栏的 "序列号", 点击最后一个图标(修改)
        - 4.1.1 填入值 0 和 模块的IMEI值, 共16位
        - 4.1.2 例如模块的IMEI为 867814046436255, 则填入 0867814046436255
    - 4.2 点击 "数据头标签" "[H:数据]", 填入 一个字符  "#" 即井号
    - 4.3 点击 "数据标签" "D?"
    - 4.4 点击 "结束符标签" "[回车换行]"
    - 4.5 点击 "保存协议", 则 "当前协议" 会显示为 "[H:]  [D?]  [TE:0D0A]"
5. 返回设备列表, 至此, 网页端的配置就完成了

参考文档: 
    - 创建设备 https://www.tlink.io/help.htm?menu=2
    - UDP 协议 https://www.tlink.io/help.htm?menu=2&page=46
    - 安卓APP  https://www.tlink.io/help.htm?menu=2&page=116

注意事项:
    - 本demo是适合单传上传数据的场景,不适合有数据下发的场景
    - 由UDP的特性决定, 不能100%保证数据能上报成功
]]

local sys = require "sys"

-----------------------------------------------------------------------------------
--PM异常唤醒检测  休眠时间最低120S
--- pm_wakeup_time_check() 读取上次设置hib时间，并且与本次时间作比较，异常唤醒将直接睡眠
-- @return 无
function pm_wakeup_time_check ()
    log.info("pm", pm.lastReson())
    if pm.lastReson() == 1 then
        local tdata = lpmem.read(512, 6) -- 0x5A 0xA5, 然后一个32bit的taskInit
        local _, mark, tsleep = pack.unpack(tdata, ">HI")
        if mark == 0x5AA5 then
            local tnow = os.time()
            log.info("pm", "sleep time", tsleep, tnow)
			--下面的120S根据休眠时间设置，最大可以设置休眠时间-12S。
            if tnow - tsleep < (120 - 12) then
                pm.request(pm.HIB) -- 建议休眠
                return -- 是提前唤醒, 继续睡吧
            end
        end
    end
    return true
end

--- PM进入休眠
-- @param sec 进入hib深睡眠时间，单位：秒
-- @返回值： 无
-- @ pm_enter_hib_mode(sec)
function pm_enter_hib_mode(sec)
    --设置休眠唤醒时间，并开启休眠
    lpmem.write(512, pack.pack(">HI", 0x5AA5, os.time())) -- 把当前时间写入lpmem
    pm.dtimerStart(0, sec*1000)
    pm.request(pm.HIB) -- 建议休眠
    --log.info("pm check",pm.check())
    --sys.wait(300*1000)
end

-----------------------------------------------------------------------------------------

-- 读取ds18b20的数据
function get_data()
    local data = nil
    for i=1,10 do -- 读取时存在失败的可能性,所以需要尝试多次
        local temp, result = sensor.ds18b20(17)
        if result and temp ~= 250 then
            -- 数据格式对应 [H:]  [D?]  [TE:0D0A]
            data = string.format( "0%s#%d\r\n", nbiot.imei(), math.floor(temp))
            log.info("data", data)
            log.info("data.hex", data:toHex())
            break
        end
        sys.wait(2000)
    end
    return data
end

-- 主任务
function main_task()
    -- 等待联网
    while not socket.isReady() do sys.wait(1000) end
    -- 建立netclient对象
    local netc = socket.udp()
    netc:host("47.106.61.135") -- 这里对应的 udp.tlink.io 的IP地址
    netc:port(9896)            -- UDP协议的端口号
    -- 配置好回调
    netc:on("connect", function(id, re)
        log.info("netc", "connect", id, re)
        sys.taskInit(function()
            local data = get_data()
            if data then
                log.info("netc", "send reg package", data)
                netc:send(data, 2)
            end
            sys.publish("NETC_OK")
        end)
    end)
    netc:on("recv", function(id, data)
        -- 注意, 唤醒操作, 调用netc:rebind后, 如果基站有缓存的数据, 这里就会被触发
        log.info("netc", "recv", id, data)
        --netc:send(data)
    end)
    -- 检查开机原因
    local flag = false
    log.info("pm", "lastReson", pm.lastReson())
    -- 非普通上电/复位上电,那就是唤醒上电咯
    if pm.lastReson() ~= 0 then
        -- 读取低功耗内存的 0x5A 0xA5 ? ? ? ?
        local data = lpmem.read(0, 6)
        -- 打印内容,方便调试
        log.info("lpmem", data:toHex())
        -- 使用pack库解析之
        local _, t1,t2,sockid = pack.unpack(data, ">bbI")
        -- 头两个字符是我们自定义的0x5A 0xA5,不是的话,就肯定是脏数据了
        if t1 == 0x5A and t2 == 0xA5 then
            netc:rebind(sockid) -- 重建tcp上下文
            local data = get_data()
            if data then
                netc:send(data, 2) -- 发送心跳
            end
            flag = true
        else
            -- 脏数据就不管了
            log.info("lpmem", "bad custom lpmem data, skip")
        end
    end
    -- 如果不唤醒流程, 或者数据是脏的,就新建连接
    if not flag then
        -- 启动tcp连接线程
        if netc:start() == 0 then
            sys.waitUntil("NETC_OK", 15000)
            if netc:closed() == 0 then
                -- 启动成功, 那就把sockid放入低功耗内存,在唤醒时重建上下文.
                lpmem.write(0, pack.pack(">bbI", 0x5A, 0xA5, netc:sockid()))
            else
                -- 启动,那就重启吧 or 重试2次?
                log.warn("Start netc FAIL!!!")
                sys.wait(15000)
                rtos.reboot()
            end
        else
            -- socket线程都启动失败?什么情况啊
            log.warn("Start netc FAIL!!!")
            sys.wait(5000)
            rtos.reboot()
        end
    end
    -- 要求进入休眠状态,省电. 
    -- 如修改休眠时长, 务必做到 "同比例"修改pm_wakeup_time_check里面的检测时长
    pm_enter_hib_mode(120)
end

-- 先判断休眠是否够了, 然后再执行主任务
sys.taskInit(function()
    if pm_wakeup_time_check() then
        main_task()
    else
        log.info("pm", "too early, back to hib")
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
