--[[
@module  ble_ibeacon
@summary Air8000演示ibeacon功能模块
@version 1.0
@date    2025.07.01
@author  wangshihao
@usage
本文件为Air8000核心板演示ibeacon功能的代码示例，核心业务逻辑为：
1. 初始化蓝牙底层框架
2. 创建BLE对象实例
3. 配置ibeacon广播数据包
    - 包含厂商特定数据格式,ibeacon类型标识符
    - 设置UUID、Major、Minor等关键参数
4. 启动BLE广播功能
]]

function ble_callback()
    -- 无事可做
end

function ble_ibeacon()
    local ret = 0
    sys.wait(500)
    log.info("开始初始化蓝牙核心")
    bluetooth_device = bluetooth.init()
    sys.wait(100)
    log.info("初始化BLE功能")
    ble_device = bluetooth_device:ble(ble_callback)
    sys.wait(100)

    sys.wait(100)
    log.info("开始设置广播内容")

    local adv_data = string.char(0x4C, 0x00, -- Manufacturer ID（2字节）
                                0x02, 0x15, -- ibeacon数据类型（2字节）
                                0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, -- UUID（16字节）
                                0x00, 0x01, -- Major（2字节）
                                0x00, 0x02, -- Minor（2字节）
                                0xC0) -- Signal Power（1字节）

    ble_device:adv_create({
        addr_mode = ble.PUBLIC, -- 广播地址模式, 可选值: ble.PUBLIC, ble.RANDOM, ble.RPA, ble.NRPA
        channel_map = ble.CHNLS_ALL, -- 广播的通道, 可选值: ble.CHNLS_37, ble.CHNLS_38, ble.CHNLS_39, ble.CHNLS_ALL
        intv_min = 120, -- 广播间隔最小值, 单位为0.625ms, 最小值为20, 最大值为10240
        intv_max = 120, -- 广播间隔最大值, 单位为0.625ms, 最小值为20, 最大值为10240
        adv_data = { -- 支持表格形式, 也支持字符串形式(255字节以内)
            {ble.FLAGS, string.char(0x06)}, 
            {ble.MANUFACTURER_SPECIFIC_DATA, adv_data} 
        }
    })

    sys.wait(100)
    log.info("开始广播")
    ble_device:adv_start()
end

sys.taskInit(ble_ibeacon)