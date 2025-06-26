-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "ble"
VERSION = "1.0.0"
--[[
Air8000的BLE支持4种模式，分别是主机模式(central)，从机模式(peripheral)，广播者模式(ibeacon)，以及观察者模式(scan)。
1.主机模式(central)：
主机模式是能够搜索别人并主动建立连接的一方，从扫描状态转化而来的。其可以和一个或多个从设备进行连接通信，它会定期的扫描周围的广播状态设备发送的广播信息，可以对周围设备进行搜索并选择所需要连接的从设备进行配对连接，建立通信链路成功后，主从双方就可以发送接收数据。
2.从机模式(peripheral)：
从机模式是从广播者模式转化而来的，未被连接的从机首先进入广播状态，等待被主机搜索，当主机扫描到从设备建立连接后，就可以和主机设备进行数据的收发，其不能主动的建立连接，只能等别人来连接自己。和广播模式有区别的地方在于，从机模式的设备是可以被连接的，定期的和主机进行连接和数据传输，在数据传输过程中作从机。
3.广播者模式(ibeacon)
处于广播模式的设备，会周期性的广播beacon信息, 但不会被扫描到, 也不会连接其他设备。
4.观察者模式(scan)
观察者模式，该模式下模块为非连接，相对广播者模式的一对多发送广播，观察者可以一对多接收数据。在该模式中，设备可以仅监听和读取空中的广播数据。和主机唯一的区别是不能发起连接，只能持续扫描从机。
蓝牙中的重要概念
1. GATT（通用属性配置文件）
  - 定义 BLE 设备如何组织和传输数据，以 “服务（Service）” 和 “特征（Characteristic）” 为单位。
  - 示例：心率监测设备的 GATT 服务包含 “心率特征”，手机通过读取该特征获取心率数据。
2. 服务和特征
- 服务是特征的容器，通过逻辑分组简化复杂功能的管理；
- 特征是数据交互的最小单元，通过属性定义实现灵活的读写与推送机制；
- 两者结合构成 GATT 协议的核心框架，支撑蓝牙设备间的标准化数据交互（如智能穿戴、医疗设备、物联网传感器）。
3. 特征的关键属性（Properties）
特征通过 “属性” 定义数据的操作方式，常见属性包括：
  1. 可读（Read）：允许客户端读取特征值（如读取电池电量）。
  2. 可写（Write）：允许客户端写入特征值（如设置设备参数）。
  3. 通知（Notification）：服务端主动发送特征值更新（如心率变化时推送给手机）。
  4. 指示（Indication）：比通知更可靠的推送（需客户端确认接收）。
4. UUID
  UUID 是蓝牙 GATT 协议的 “数字身份证”，通过标准化的唯一标识机制，实现了跨厂商设备的功能互认（标准 UUID）与厂商个性化功能的扩展（自定义 UUID）
  Air8000 的所有操作，都通过UUID来索引和管理
]]

log.info("main", "project name is ", PROJECT, "version is ", VERSION)

-- 通过boot按键方便刷Air8000S
function PWR8000S(val) gpio.set(23, val) end

gpio.debounce(0, 1000)
gpio.setup(0, function()
    sys.taskInit(function()
        log.info("复位Air8000S")
        PWR8000S(0)
        sys.wait(20)
        PWR8000S(1)
    end)
end, gpio.PULLDOWN)

local att_db =   { -- Service
    string.fromHex("FA00"), -- 服务 UUID
    -- Characteristic
    { -- Characteristic 1
        string.fromHex("EA01"), -- 特征 UUID Value
        ble.NOTIFY | ble.READ | ble.WRITE -- 属性
    }, { -- Characteristic 2
        string.fromHex("EA02"), ble.WRITE
    }, { -- Characteristic 3
        string.fromHex("EA03"), ble.READ
    }, { -- Characteristic 4
        string.fromHex("EA04"), ble.IND | ble.READ
    }
}

ble_stat = false

local function ble_callback(dev, evt, param)
    if evt == ble.EVENT_CONN then
        log.info("ble", "connect 成功", param, param and param.addr and param.addr:toHex() or "unknow")
        ble_stat = true
    elseif evt == ble.EVENT_DISCONN then
        log.info("ble", "disconnect")
        ble_stat = false
        -- 1秒后重新开始广播
        sys.timerStart(function() dev:adv_start() end, 1000)
    elseif evt == ble.EVENT_WRITE then
        -- 收到写请求
        log.info("ble", "接收到写请求", param.uuid_service:toHex(), param.data:toHex())
    end
end

local bt_scan = false -- 是否扫描蓝牙

sys.taskInit(function()
    local ret = 0
    sys.wait(500)
    log.info("开始初始化蓝牙核心")
    bluetooth_device = bluetooth.init()
    sys.wait(100)
    log.info("初始化BLE功能")
    ble_device = bluetooth_device:ble(ble_callback)
    if ble_device == nil then
        log.error("当前固件不支持完整的BLE")
        return
    end
    sys.wait(100)

    log.info('开始创建GATT')
    ret = ble_device:gatt_create(att_db)
    log.info("创建的GATT", ret)

    sys.wait(100)
    log.info("开始设置广播内容")
    ble_device:adv_create({
        addr_mode = ble.PUBLIC,
        channel_map = ble.CHNLS_ALL,
        intv_min = 120,
        intv_max = 120,
        adv_data = {
            {ble.FLAGS, string.char(0x06)},
            {ble.COMPLETE_LOCAL_NAME, "LuatOS123"},
            {ble.SERVICE_DATA, string.fromHex("FE01")},
            {ble.MANUFACTURER_SPECIFIC_DATA, string.fromHex("05F0")}
        }
    })

    sys.wait(100)
    log.info("开始广播")
    ble_device:adv_start()

    while 1 do
        sys.wait(3000)
        if ble_stat then
            local wt = {
                uuid_service = string.fromHex("FA00"),
                uuid_characteristic = string.fromHex("EA01"), 
            }
            local result = ble_device:write_notify(wt, "123456" .. os.date())
            log.info("ble", "发送数据", result)
        else
            -- log.info("等待连接成功之后发送数据")
        end
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
