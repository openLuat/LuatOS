--[[
@module kvstore
@summary 键值存储模块
@version 1.0
@date    2026.03.10
@author  孟伟
@usage
键值存储模块，用于存储设备配置和状态信息，使用fskv实现
]]

local kvstore = {}

-- 初始化存储，初始化fskv键值存储系统
function kvstore.init()
    log.info("kvstore", "初始化键值存储")

    -- 初始化fskv
    local result = fskv.init()
    if result then
        log.info("kvstore", "fskv初始化成功")
    else
        log.error("kvstore", "fskv初始化失败:", result)
    end

    -- 第一次上电时写入初始值
    local is_first_boot = not fskv.get("initialized")
    if is_first_boot then
        log.info("kvstore", "第一次上电，写入初始值")
        fskv.set("bind_status", "false")          -- 绑定状态: false=未绑定, true=已绑定
        fskv.set("step_status", "0")               -- 计步状态: 0=关闭, 1=开启
        fskv.set("location_mode", "smart")        -- 定位模式: smart=智能, periodic=定时, realtime=实时
        fskv.set("low_power_mode", "false")      -- 低电量模式: false=正常, true=低电量
        fskv.set("work_mode", "-1")              -- 工作模式: -1=未激活, 0=常规模式，1=智能模式，2=寻狗模式（默认未激活）
        fskv.set("vbat", "")                 -- 电池电压(mV)
        fskv.set("smart_interval", "300")        -- 智能模式上报间隔(秒)
        fskv.set("no_motion_count", "0")         -- 无运动连续上报次数
        fskv.set("user_id", "")                  -- 绑定的用户ID
        fskv.set("device_id", "")                -- 设备唯一标识
        fskv.set("bluetooth_mac", "")            -- 蓝牙MAC地址
        fskv.set("bind_token", "")               -- 绑定会话凭证
        fskv.set("bind_time", "0")                -- 绑定时间戳
        fskv.set("session_id", "")                -- 当前会话ID
        fskv.set("last_report_time", "0")        -- 上次定位上报时间戳
        fskv.set("device_mode", "")               -- 设备型号
        fskv.set("is_home", "false")             -- 常驻地状态: false=非长驻地, true=常驻地
        fskv.set("audio_volume", "80")           -- 音频音量(0-100)，默认80
        fskv.set("report_interval", "")          -- 自定义上报间隔(秒)，空=自动
        fskv.set("initialized", "true")           -- 初始化标记
        log.info("kvstore", "初始值写入完成")
    end

    log.info("kvstore", "初始化完成")
end

-- 保存数据，将键值对保存到fskv存储中
-- @param string key 键名
-- @param any value 值
-- @return boolean 保存成功返回true，失败返回false
function kvstore.save(key, value)
    local result = fskv.set(key, value)
    if result then
        log.debug("kvstore", "数据保存成功:", key)
        return true
    end
    log.error("kvstore", "数据保存失败:", key, result)
    return false
end

-- 获取工作模式，返回当前工作模式
-- @return number 工作模式，未激活返回-1
function kvstore.get_work_mode()
    local value = fskv.get("work_mode")
    return value and tonumber(value) or -1
end

-- 设置工作模式，保存工作模式到存储
-- @param number mode 工作模式
function kvstore.set_work_mode(mode)
    kvstore.save("work_mode", tostring(mode))
    log.info("kvstore", "设置工作模式:", mode)
end

-- 获取计步状态，返回计步功能是否开启
-- @return string 计步状态，"0"关闭，"1"开启
function kvstore.get_step_status()
    local value = fskv.get("step_status")
    return value or "0"
end

-- 设置计步状态，保存计步功能状态
-- @param string status 计步状态
function kvstore.set_step_status(status)
    kvstore.save("step_status", status)
    log.info("kvstore", "设置计步状态:", status)
end

-- 获取电池电压，返回保存的电池电压
-- @return number 电池电压（mV）
function kvstore.get_vbat()
    local value = fskv.get("vbat")
    return value and tonumber(value) or 4200
end

-- 设置电池电压，保存电池电压到存储
-- @param number vbat 电池电压（mV）
function kvstore.set_vbat(vbat)
    kvstore.save("vbat", tostring(vbat))
    log.debug("kvstore", "设置电池电压:", vbat)
end

-- 获取设备模式，返回设备模式字符串
-- @return string 设备模式
function kvstore.get_device_mode()
    local value = fskv.get("device_mode")
    return value or ""
end

-- 设置设备模式，保存设备模式到存储
-- @param string mode 设备模式
function kvstore.set_device_mode(mode)
    kvstore.save("device_mode", mode)
    log.info("kvstore", "设置设备模式:", mode)
end

-- 获取上次上报时间，返回时间戳
-- @return number 上次上报时间戳
function kvstore.get_last_report_time()
    local value = fskv.get("last_report_time")
    return value and tonumber(value) or 0
end

-- 设置上次上报时间，保存时间戳到存储
-- @param number time 时间戳
function kvstore.set_last_report_time(time)
    kvstore.save("last_report_time", tostring(time))
    log.debug("kvstore", "设置上次上报时间:", time)
end

-- 获取智能模式上报间隔，返回间隔秒数
-- @return number 上报间隔（秒）
function kvstore.get_smart_interval()
    local value = fskv.get("smart_interval")
    return value and tonumber(value) or 0
end

-- 设置智能模式上报间隔，保存间隔时间
-- @param number interval 上报间隔（秒）
function kvstore.set_smart_interval(interval)
    kvstore.save("smart_interval", tostring(interval))
    log.debug("kvstore", "设置智能模式上报间隔:", interval)
end

-- 获取无运动次数，返回连续无运动的上报次数
-- @return number 无运动次数
function kvstore.get_no_motion_count()
    local value = fskv.get("no_motion_count")
    return value and tonumber(value) or 0
end

-- 设置无运动次数，保存无运动计数
-- @param number count 无运动次数
function kvstore.set_no_motion_count(count)
    kvstore.save("no_motion_count", tostring(count))
    log.debug("kvstore", "设置无运动次数:", count)
end

-- 获取低电量模式状态，返回是否处于低电量模式
-- @return boolean 低电量模式状态
function kvstore.get_low_power_mode()
    local value = fskv.get("low_power_mode")
    return value and value == "true"
end

-- 设置低电量模式状态，保存低电量模式状态
-- @param boolean state 低电量模式状态
function kvstore.set_low_power_mode(state)
    kvstore.save("low_power_mode", state and "true" or "false")
    log.info("kvstore", "设置低电量模式状态:", state)
end

-- 获取绑定状态，返回设备是否已绑定
-- @return boolean 绑定状态
function kvstore.get_bind_status()
    local value = fskv.get("bind_status")
    return value and value == "true"
end

-- 设置绑定状态，保存绑定状态到存储
-- @param boolean status 绑定状态
function kvstore.set_bind_status(status)
    kvstore.save("bind_status", status and "true" or "false")
    log.info("kvstore", "设置绑定状态:", status)
end

-- 获取用户ID，返回绑定的用户标识
-- @return string 用户ID
function kvstore.get_user_id()
    local value = fskv.get("user_id")
    return value or ""
end

-- 设置用户ID，保存用户标识到存储
-- @param string user_id 用户ID
function kvstore.set_user_id(user_id)
    kvstore.save("user_id", user_id)
    log.info("kvstore", "设置用户ID:", user_id)
end

-- 获取设备ID，返回设备唯一标识
-- @return string 设备ID
function kvstore.get_device_id()
    local value = fskv.get("device_id")
    return value or ""
end

-- 设置设备ID，保存设备标识到存储
-- @param string device_id 设备ID
function kvstore.set_device_id(device_id)
    kvstore.save("device_id", device_id)
    log.info("kvstore", "设置设备ID:", device_id)
end

-- 获取蓝牙MAC地址，返回蓝牙物理地址
-- @return string 蓝牙MAC地址
function kvstore.get_bluetooth_mac()
    local value = fskv.get("bluetooth_mac")
    return value or ""
end

-- 设置蓝牙MAC地址，保存蓝牙地址到存储
-- @param string mac 蓝牙MAC地址
function kvstore.set_bluetooth_mac(mac)
    kvstore.save("bluetooth_mac", mac)
    log.info("kvstore", "设置蓝牙MAC地址:", mac)
end

-- 获取绑定凭证，返回绑定会话的凭证
-- @return string 绑定凭证
function kvstore.get_bind_token()
    local value = fskv.get("bind_token")
    return value or ""
end

-- 设置绑定凭证，保存绑定凭证到存储
-- @param string token 绑定凭证
function kvstore.set_bind_token(token)
    kvstore.save("bind_token", token)
    log.info("kvstore", "设置绑定凭证")
end

-- 获取绑定时间，返回绑定完成的时间戳
-- @return number 绑定时间戳
function kvstore.get_bind_time()
    local value = fskv.get("bind_time")
    return value and tonumber(value) or 0
end

-- 设置绑定时间，保存绑定时间戳
-- @param number time 绑定时间戳
function kvstore.set_bind_time(time)
    kvstore.save("bind_time", tostring(time))
    log.info("kvstore", "设置绑定时间:", time)
end

-- 获取会话ID，返回当前绑定会话的标识
-- @return string 会话ID
function kvstore.get_session_id()
    local value = fskv.get("session_id")
    return value or ""
end

-- 设置会话ID，保存会话标识到存储
-- @param string session_id 会话ID
function kvstore.set_session_id(session_id)
    kvstore.save("session_id", session_id)
    log.info("kvstore", "设置会话ID:", session_id)
end

-- 获取定位模式，返回绑定的定位模式
-- @return string 定位模式
function kvstore.get_location_mode()
    local value = fskv.get("location_mode")
    return value or "smart"
end

-- 设置定位模式，保存定位模式到存储
-- @param string mode 定位模式
function kvstore.set_location_mode(mode)
    kvstore.save("location_mode", mode)
    log.info("kvstore", "设置定位模式:", mode)
end

-- 获取常驻地状态
-- @return boolean 是否在常驻地
function kvstore.get_is_home()
    local value = fskv.get("is_home")
    return value and value == "true"
end

-- 设置常驻地状态
-- @param boolean is_home 是否在常驻地
function kvstore.set_is_home(is_home)
    kvstore.save("is_home", is_home and "true" or "false")
    log.info("kvstore", "设置常驻地状态:", is_home)
end

-- 获取音频音量
-- @return number 音量值(0-100)，默认50
function kvstore.get_audio_volume()
    local value = fskv.get("audio_volume")
    return value and tonumber(value) or 80
end

-- 设置音频音量
-- @param number volume 音量值(1-100)
function kvstore.set_audio_volume(volume)
    fskv.set("audio_volume", tostring(volume))
    log.info("kvstore", "设置音频音量:", volume)
end

-- 获取自定义上报间隔（服务端下发 set_report_interval）
-- @return number 间隔秒数，未设置返回 nil
function kvstore.get_report_interval()
    local value = fskv.get("report_interval")
    return value and tonumber(value) or nil
end

-- 设置自定义上报间隔
-- @param number interval 间隔秒数
function kvstore.set_report_interval(interval)
    kvstore.save("report_interval", tostring(interval))
    log.info("kvstore", "设置自定义上报间隔:", interval)
end

-- 清除所有数据，清空存储中的所有配置项
function kvstore.clear()
    local keys = {
        "work_mode", "step_status", "vbat", "device_mode", "last_report_time",
        "smart_interval", "no_motion_count", "low_power_mode", "bind_status",
        "user_id", "device_id", "bluetooth_mac", "bind_token", "bind_time",
        "session_id", "location_mode", "report_interval"
    }

    for _, key in ipairs(keys) do
        fskv.set(key, nil)
    end

    log.info("kvstore", "清除所有数据")
end

return kvstore
