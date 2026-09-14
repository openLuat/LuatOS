--[[
@module kvstore
@summary 键值存储模块
@version 1.2
@date    2026.09.06
@author  孟伟
@usage
键值存储模块，用于存储设备配置和状态信息，使用fskv实现。

004.000.030 清理：删除绑定/计步/蓝牙/设备模式/上报间隔等死接口（云绑定流程已废弃、
上报节奏改由 GNSS 三态固定策略驱动），仅保留存活键：
- work_mode        工作模式（app 启动分发 / remote.change_mode 切换）
- low_power_mode   低电量状态（active_mode 低电量检测写入，lowpower_app 读取）
- audio_volume     音频音量（remote.set_volume 写入，预留）
- gnss_schedule    GNSS 开启时间窗（001.000.002 新增，remote.gnss_schedule 写入，active_mode 评估）
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
        fskv.set("low_power_mode", "false")      -- 低电量模式: false=正常, true=低电量
        fskv.set("work_mode", "2")              -- 工作模式: 0=常规模式，1=智能模式，2=GPS定位/寻宠模式（默认寻宠模式）
        fskv.set("audio_volume", "80")           -- 音频音量(0-100)，默认80
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
-- @return number 工作模式
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

-- 获取音频音量
-- @return number 音量值(0-100)，默认80
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

-- 获取 GNSS 开启时间窗配置（001.000.002 新增）
-- 存储格式：JSON 字符串 {"enable":1,"start":"08:30","end":"18:00"}
-- @return table|nil 配置表 {enable=0/1, start="HH:mm", end="HH:mm"}；未配置或损坏返回 nil
function kvstore.get_gnss_schedule()
    local raw = fskv.get("gnss_schedule")
    if not raw or raw == "" then
        return nil
    end
    local ok, cfg = pcall(json.decode, raw)
    if not ok or type(cfg) ~= "table" then
        log.warn("kvstore", "GNSS时间窗配置损坏，忽略:", raw)
        return nil
    end
    return cfg
end

-- 设置 GNSS 开启时间窗配置（001.000.002 新增）
-- @param table cfg {enable=1, start="HH:mm", end="HH:mm"}；传 nil 或 enable≠1 表示清除配置
-- @return boolean 保存成功返回 true
function kvstore.set_gnss_schedule(cfg)
    if type(cfg) ~= "table" or not cfg.enable or tonumber(cfg.enable) ~= 1 then
        fskv.set("gnss_schedule", "")
        log.info("kvstore", "清除GNSS时间窗配置")
        return true
    end
    local ok, raw = pcall(json.encode, cfg)
    if not ok or type(raw) ~= "string" then
        log.error("kvstore", "GNSS时间窗配置编码失败")
        return false
    end
    kvstore.save("gnss_schedule", raw)
    log.info("kvstore", "设置GNSS时间窗:", raw)
    return true
end

return kvstore
