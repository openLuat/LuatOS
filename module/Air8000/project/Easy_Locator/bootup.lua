--[[
@module  bootup
@summary 系统启动模块：加载所有功能模块，初始化配置
@version 1.0
@author  Auto
@usage
本模块实现以下功能：
1. 加载所有功能模块到全局环境
2. 配置轨迹补偿参数
3. 初始化GNSS低功耗模块（可选）
4. 初始化服务器管理
]]

-- wlan.init() -- WiFi初始化（本项目未使用）

-- ==================== 加载功能模块 ====================


-- 配置文件模块
require "cfg"

-- 网络状态管理模块
_G.netWork = require "netWork"

-- 网络通信模块
_G.libnet = require "libnet"

-- 设备管理模块（功耗管理、运动检测）
_G.manage = require "manage"

-- 轨迹补偿模块
_G.trackCompensate = require "trackCompensate"

-- 电池管理模块
_G.charge = require "charge"

-- GNSS模块（使用exgnss库）
_G.exgnss = require "exgnss"

-- 公共模块（定位、数据上报）
_G.common = require "common"

-- API工具库
_G.api = require "api"

-- JT808协议模块
_G.jt808 = require "jt808"

-- 服务器统一管理模块
_G.srvs = require "srvs"

-- ==================== 初始化服务器 ====================

-- 测试服务器（auxServer）添加到服务器列表
local auxTask = require "auxServer"
srvs.add(auxTask)


-- ==================== 垃圾回收 ====================

collectgarbage("collect")
collectgarbage("collect")

-- ==================== 配置轨迹补偿参数 ====================

--[[
轨迹补偿模块配置
用于减少GNSS静态漂移，提高定位精度
]]

-- 默认配置
local trackConfig = {
    -- 距离阈值（米），超过此距离认为漂移，进行补偿
    distanceThreshold = 50,

    -- 速度突变阈值（km/h），超过此值认为异常，进行平滑
    speedChangeThreshold = 5,

    -- 航向跳变阈值（度），超过此值进行平滑
    courseChangeThreshold = 30,

    -- 是否启用拐点补偿
    enableCornerCompensate = true,

    -- 最小转弯半径（米），小于此值认为是急转弯
    minTurnRadius = 10,
}

-- 从配置文件读取用户自定义参数（如果存在）
if _G.TRACK_COMPENSATE_CONFIG then
    for k, v in pairs(_G.TRACK_COMPENSATE_CONFIG) do
        trackConfig[k] = v
    end
end

-- 应用配置
trackCompensate.setConfig(trackConfig)
log.info("bootup", "轨迹补偿模块已加载并配置", json.encode(trackConfig))

-- ==================== GNSS低功耗模块（可选） ====================

--[[
GNSS低功耗模式
通过全局变量 _G.GNSS_LOWPOWER_ENABLE 控制
启用后，GNSS将按指定周期定位，降低功耗
]]

if _G.GNSS_LOWPOWER_ENABLE then
    log.info("bootup", "加载GNSS低功耗模块")
    _G.gnssLowPower = require "gnssLowPower"
    sys.taskInit(function()
        sys.wait(5000)  -- 等待系统初始化
        gnssLowPower.init()
        gnssLowPower.open(_G.GNSS_LOWPOWER_INTERVAL)  -- 使用配置的定位周期
    end)
else
    log.info("bootup", "GNSS低功耗模式未启用")
end

-- ==================== 加载调试模块 ====================

require "mdebug"
