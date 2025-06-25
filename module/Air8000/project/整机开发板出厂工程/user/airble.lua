local airble = {}

dnsproxy = require("dnsproxy")
dhcpsrv =  require("dhcpsrv")
httpplus = require("httpplus")
local run_state = false  -- 判断本UI DEMO 是否运行
local ble_state = "未初始"
local ble_flag = "false"

local Characteristic1 = "EA01"
local Characteristic1_read = ""
local Characteristic1_write = ""
local Characteristic2 = "EA02"
local Characteristic2_write = ""
local Characteristic3 = "EA03"
local Characteristic3_read = ""
local Characteristic4 = "EA04"
local Characteristic4_read = ""
local Characteristic4ind = ""


local att_db = nil




local function set_att_db()
    att_db = { -- Service
    string.fromHex("FA00"), -- Service UUID
    -- Characteristic
    { -- Characteristic 1
        string.fromHex(Characteristic1), -- Characteristic UUID Value
        ble.NOTIFY | ble.READ | ble.WRITE -- Properties
    }, { -- Characteristic 2
        string.fromHex(Characteristic2), ble.WRITE
    }, { -- Characteristic 3
        string.fromHex(Characteristic3), ble.READ
    }, { -- Characteristic 4
        string.fromHex(Characteristic4), ble.IND | ble.READ
    }
}
end

local function ble_callback(dev, evt, param)
    if evt == ble.EVENT_CONN then
        ble_state = "蓝牙链接成功"
        log.info("ble", ble_state, param, param and param.addr and param.addr:toHex() or "unknow")
        ble_flag = true
    elseif evt == ble.EVENT_DISCONN then
        ble_state = "蓝牙已断开"
        log.info("ble", ble_state)
        ble_flag = false
        -- 1秒后重新开始广播
        sys.timerStart(function() dev:adv_start() end, 1000)
    elseif evt == ble.EVENT_WRITE_REQ then
        -- 收到写请求
        ble_state = "接收到写请求"
        log.info("ble", "接收到写请求", param.uuid_service:toHex(), param.data:toHex(),param.uuid_characteristic:toHex())
        if param.uuid_characteristic:toHex() == Characteristic1 then
            Characteristic1_write = param.data:toHex()
        elseif param.uuid_characteristic:toHex() == Characteristic2 then
            Characteristic2_write = param.data:toHex()
        end

    end
end

local function write_read()
    local wr = {
        uuid_service = string.fromHex("FA00"),
        uuid_characteristic = string.fromHex("EA01"), 
    }
    ble_device:write_value(wr, "FA00EA01 HELLO" .. os.date())

    wr = {
        uuid_service = string.fromHex("FA00"),
        uuid_characteristic = string.fromHex("EA03"), 
    }   
    ble_device:write_value(wr, "FA00EA03 HELLO" .. os.date())
    
    wr = {
        uuid_service = string.fromHex("FA00"),
        uuid_characteristic = string.fromHex("EA04"), 
    }
    ble_device:write_value(wr, "FA00EA04 HELLO" .. os.date())
    
end

local function ble_peripheral_setup()
    local ret = 0
    set_att_db()
    sys.wait(500)
    
    ble_state = "开始初始化蓝牙核心"
    log.info(ble_state)
    bluetooth_device = bluetooth.init()
    sys.wait(100)
    ble_state = "初始化BLE功能"
    log.info(ble_state)
    ble_device = bluetooth_device:ble(ble_callback)
    if ble_device == nil then
        ble_state = "当前固件不支持完整的BLE"
        log.error(ble_state)
        return
    end
    sys.wait(100)
    ble_state = '开始创建GATT'
    log.info(ble_state)
    ret = ble_device:gatt_create(att_db)
    log.info("创建的GATT", ret)

    sys.wait(100)
    ble_state = "开始设置广播内容"
    log.info(ble_state)
    ble_device:adv_create({
        addr_mode = ble.PUBLIC,
        channel_map = ble.CHNLS_ALL,
        intv_min = 120,
        intv_max = 120,
        adv_data = {
            {ble.FLAGS, string.char(0x06)},
            {ble.COMPLETE_LOCAL_NAME, "LuatOS_Air8000"},
            {ble.SERVICE_DATA, string.fromHex("FE01")},
            {ble.MANUFACTURER_SPECIFIC_DATA, string.fromHex("05F0")}
        }
    })
    sys.wait(100)
    ble_state = "开始广播"
    log.info(ble_state)
    ble_device:adv_start()
    write_read()
end

local function start_notify_and_ind()
    if ble_flag then
        local wt = {
            uuid_service = string.fromHex("FA00"),
            uuid_characteristic = string.fromHex("EA01"), 
        }
        local result = ble_device:write_notify(wt, "123456" .. os.date())
        log.info("ble", "发送通知数据", result)

        local wi = {
            uuid_service = string.fromHex("FA00"),
            uuid_characteristic = string.fromHex("EA04"), 
        }
        local result = ble_device:write_indicate(wi, "please read" .. os.date())
        log.info("ble", "发送指示数据", result)
        ble_state = "通知指示数据已经发送完毕"
    end
end


function airble.run()       
    log.info("airble.run")
    lcd.setFont(lcd.font_opposansm12_chinese) -- 设置中文字体
    run_state = true
    sysplus.taskInitEx(ble_peripheral_setup,"airble")
    while true do
        sys.wait(10)
        lcd.clear(_G.bkcolor) 
        lcd.drawStr(0,80,"当前蓝牙状态:" .. ble_state )
        lcd.drawStr(0,100,"服务:FA00,特征:" .. Characteristic1  .. ",可读数据为：" ..  Characteristic1_read.. "被写入数据为:" .. Characteristic1_write)
        lcd.drawStr(0,120,"服务:FA00,特征:" .. Characteristic2   .. "被写入数据为:" .. Characteristic2_write)
        lcd.drawStr(0,140,"服务:FA00,特征:" .. Characteristic3   .. ",可读数据为：" .. Characteristic3_read)
        lcd.drawStr(0,160,"服务:FA00,特征:" .. Characteristic4   .. "可读数据为：" .. Characteristic4_read)



        lcd.showImage(130,350,"/luadb/start.jpg")   -- EA01 发送数据
        lcd.flush()
        
        if not  run_state  then    -- 等待结束，返回主界面
            return true
        end
    end
end



function airble.tp_handal(x,y,event)       
    log.info("airble.tp_handal",x,y)
    if x > 20 and  x < 100 and y > 360  and  y < 440 then
        run_state = false
    elseif x > 130 and  x < 239 and y > 350  and  y < 393 then
        sysplus.taskInitEx(start_notify_and_ind, "start_notify_and_ind")
    end
end

return airble