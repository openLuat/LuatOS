-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "ble"
VERSION = "1.0.1"

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")

-- 配置参数
local CONFIG = {
    DEVICE_NAME = "LuatOS",
    ADV_INTERVAL = 120,
    RECONNECT_DELAY = 1000,
    GATT = {
        service_uuid = "FA00",
        characteristics = {
            { uuid = "EA01", props = ble.NOTIFY|ble.READ|ble.WRITE },
            { uuid = "EA02", props = ble.WRITE },
            { uuid = "EA03", props = ble.READ },
            { uuid = "EA04", props = ble.READ|ble.WRITE }
        }
    },
    ADV_DATA = {
        {ble.FLAGS, string.char(0x06)},
        {ble.COMPLETE_LOCAL_NAME, "LuatOS_Air8000"},
        {ble.SERVICE_DATA, string.fromHex("FE01")},
        {ble.MANUFACTURER_SPECIFIC_DATA, string.fromHex("05F0")}
    }
}

-- characteristic handle
local characteristic1, characteristic2, characteristic3, characteristic4
local bluetooth_device, ble_device

-- 特征值读取响应映射表（使用特征值UUID作为键）
local read_responses_uuid = {
    [CONFIG.GATT.characteristics[1].uuid] = string.fromHex("0101"), -- EA01
    [CONFIG.GATT.characteristics[3].uuid] = string.fromHex("0303"), -- EA03
    [CONFIG.GATT.characteristics[4].uuid] = string.fromHex("0404")  -- EA04
}

-- 特征值写入处理函数映射表（使用特征值UUID作为键）
local write_handlers_uuid = {
    [CONFIG.GATT.characteristics[1].uuid] = function(data)
        log.info("ble", "EA01写入数据:", data:toHex())
        -- 处理EA01的写入逻辑
    end,
    
    [CONFIG.GATT.characteristics[2].uuid] = function(data)
        log.info("ble", "EA02写入数据:", data:toHex())
        -- 处理EA02的写入逻辑
    end,
    
    [CONFIG.GATT.characteristics[4].uuid] = function(data)
        log.info("ble", "EA04写入数据:", data:toHex())
        -- 处理EA04的写入逻辑
    end
}

-- 查找特征值UUID对应的句柄
local function find_uuid_by_handle(handle)
    for i, char in ipairs(CONFIG.GATT.characteristics) do
        if characteristic1 and handle == characteristic1 and i == 1 then
            return char.uuid
        elseif characteristic2 and handle == characteristic2 and i == 2 then
            return char.uuid
        elseif characteristic3 and handle == characteristic3 and i == 3 then
            return char.uuid
        elseif characteristic4 and handle == characteristic4 and i == 4 then
            return char.uuid
        end
    end
    return nil
end

local function ble_callback(ble_device, ble_event, ble_param)
    if ble_event == ble.EVENT_CONN then
        if ble_param.status == 0 then
            log.info("ble", "连接成功:", ble_param.conn_idx)
        else
            log.error("ble", "连接失败:", ble_param.status)
        end
        
    elseif ble_event == ble.EVENT_DISCONN then
        log.info("ble", "断开连接:", ble_param.conn_idx, "原因:", ble_param.reason)
        -- 延迟后重新开始广播
        sys.timerStart(function() 
            if ble_device then 
                local ok, err = pcall(function() ble_device:adv_start() end)
                if not ok then
                    log.error("ble", "重启广播失败:", err)
                else
                    log.info("ble", "已重启广播")
                end
            end
        end, CONFIG.RECONNECT_DELAY)
        
    elseif ble_event == ble.EVENT_WRITE then
        log.info("ble", "WRITE", 
                 "连接:", ble_param.conn_idx,
                 "服务:", ble_param.service_id,
                 "句柄:", ble_param.handle,
                 "数据:", ble_param.data:toHex())
        
        -- 通过句柄查找对应的UUID
        local uuid = find_uuid_by_handle(ble_param.handle)
        if uuid then
            -- 查找对应的特征值处理函数
            local handler = write_handlers_uuid[uuid]
            if handler then
                handler(ble_param.data)
            else
                log.warn("ble", "未找到UUID对应的写入处理函数:", uuid)
            end
        else
            log.warn("ble", "未找到句柄对应的UUID:", ble_param.handle)
        end
        
    elseif ble_event == ble.EVENT_READ then
        log.info("ble", "READ", 
                 "连接:", ble_param.conn_idx,
                 "服务:", ble_param.service_id,
                 "句柄:", ble_param.handle)
        
        -- 通过句柄查找对应的UUID
        local uuid = find_uuid_by_handle(ble_param.handle)
        if uuid then
            -- 根据UUID获取响应数据
            local response = read_responses_uuid[uuid] or string.fromHex("FFFF")
            local ok, err = pcall(function() ble_device:read_response(ble_param, response) end)
            if not ok then
                log.error("ble", "读取响应失败:", err)
            end
        else
            log.warn("ble", "未找到句柄对应的UUID:", ble_param.handle)
            local ok, err = pcall(function() ble_device:read_response(ble_param, string.fromHex("FFFF")) end)
            if not ok then
                log.error("ble", "读取响应失败:", err)
            end
        end
        
    elseif ble_event == ble.EVENT_MTU_CHANGE then
        log.info("ble", "MTU更改:", ble_param.mtu)
        
    elseif ble_event == ble.EVENT_NOTIFY then
        log.info("ble", "通知状态:", ble_param.status, "句柄:", ble_param.handle)
    end
end

-- 创建GATT表
local function create_gatt_table()
    local att_db = {
        string.fromHex(CONFIG.GATT.service_uuid), -- 主服务UUID
        
        -- 特征值定义
        { -- 特征值1
            string.fromHex(CONFIG.GATT.characteristics[1].uuid),
            CONFIG.GATT.characteristics[1].props
        },
        
        { -- 特征值2
            string.fromHex(CONFIG.GATT.characteristics[2].uuid),
            CONFIG.GATT.characteristics[2].props
        },
        
        { -- 特征值3
            string.fromHex(CONFIG.GATT.characteristics[3].uuid),
            CONFIG.GATT.characteristics[3].props
        },
        
        { -- 特征值4
            string.fromHex(CONFIG.GATT.characteristics[4].uuid),
            CONFIG.GATT.characteristics[4].props
        }
    }
    
    return att_db
end

-- 初始化蓝牙
local function init_bluetooth()
    log.info("开始初始化蓝牙核心")
    local ok, result = pcall(function() return bluetooth.init() end)
    if not ok then
        log.fatal("蓝牙初始化失败:", result)
        return nil
    end
    
    bluetooth_device = result
    log.info("蓝牙核心初始化成功")
    sys.wait(100)
    log.info("初始化BLE功能")
    ok, result = pcall(function() return bluetooth_device:ble(ble_callback) end)
    if not ok then
        log.fatal("BLE初始化失败:", result)
        return nil
    end
    
    ble_device = result
    log.info("BLE功能初始化成功")
    return true
end

-- 配置GATT服务
local function setup_gatt()
    log.info("开始创建GATT服务")
    local att_db = create_gatt_table()
    
    local ok, result1, result2, result3, result4 = pcall(function() 
        return ble_device:gatt_create(att_db) 
    end)
    
    if not ok then
        log.fatal("GATT创建失败:", result1)
        return false
    end
    
    characteristic1, characteristic2, characteristic3, characteristic4 = 
        result1, result2, result3, result4
    
    log.info("GATT创建成功", 
             "特征值1:", characteristic1,
             "特征值2:", characteristic2,
             "特征值3:", characteristic3,
             "特征值4:", characteristic4)
    
    return true
end

-- 配置广播
local function setup_advertising()
    log.info("开始设置广播内容")
    local ok, err = pcall(function()
        ble_device:adv_create({
            addr_mode = ble.PUBLIC,
            channel_map = ble.CHNLS_ALL,
            intv_min = CONFIG.ADV_INTERVAL,
            intv_max = CONFIG.ADV_INTERVAL,
            adv_data = CONFIG.ADV_DATA
        })
    end)
    
    if not ok then
        log.fatal("广播配置失败:", err)
        return false
    end
    
    log.info("广播内容设置成功")
    return true
end

-- 启动广播
local function start_advertising()
    log.info("开始广播")
    local ok, err = pcall(function() ble_device:adv_start() end)
    if not ok then
        log.fatal("广播启动失败:", err)
        return false
    end
    
    log.info("广播已启动")
    return true
end

sys.taskInit(function()
    log.info("main", "项目启动:", PROJECT, "版本:", VERSION)
    sys.wait(500)
    if not init_bluetooth() then
        log.fatal("蓝牙初始化失败，程序退出")
        return
    end
    
    if not setup_gatt() then
        log.fatal("GATT服务设置失败，程序退出")
        return
    end
    sys.wait(100)
    if not setup_advertising() then
        log.fatal("广播设置失败，程序退出")
        return
    end
    sys.wait(100)
    if not start_advertising() then
        log.fatal("广播启动失败，程序退出")
        return
    end
    
    log.info("蓝牙设备已就绪，等待连接...")
    
    -- 主循环
    while true do
        sys.wait(5000)  -- 每5秒执行一次
        -- 可以添加周期性任务
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!    