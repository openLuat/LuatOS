--[[
@module  cfg
@summary 配置管理模块：服务器配置、设备参数、GNSS低功耗设置
@version 1.0
@author  Auto
@usage
本模块实现以下功能：
1. 初始化配置：首次启动时设置默认服务器地址和端口
2. 参数持久化：使用fskv存储配置信息
3. GNSS低功耗模式配置：是否启用、定位间隔设置
4. 设备认证码、联系人列表等配置管理
]]

-- ==================== GNSS低功耗全局配置 ====================

-- GNSS低功耗模式开关
-- true=启用低功耗模式（按指定间隔周期定位）
-- false=关闭低功耗模式（持续定位）
_G.GNSS_LOWPOWER_ENABLE = false

-- GNSS低功耗模式定位间隔（秒）
-- 低功耗模式下，GNSS每隔指定秒数定位一次，其余时间休眠
_G.GNSS_LOWPOWER_INTERVAL = 60

-- ==================== 配置初始化函数 ====================

--[[
初始化配置
功能：
1. 初始化fskv存储
2. 检查是否首次启动（通过isInit标志）
3. 首次启动时写入默认配置：
   - 主服务器地址和端口
   - 备用服务器地址和端口
   - 设备认证码（默认空）
   - 联系人列表（默认空）
   - GNSS低功耗配置（默认关闭）

@usage cfg.init() -- 在启动时调用一次
]]
local function init()
    -- 初始化fskv存储
    fskv.init()

    -- 检查是否已初始化
    local isInit = fskv.get("isInit")
    log.info("cfg", isInit)

    -- 已初始化则跳过
    if isInit then
        return
    end

    -- ==================== 写入默认服务器配置 ====================

    -- 主服务器配置
    fskv.set("monitorIP1", "data.18gps.net")   -- 主服务器地址
    fskv.set("monitorPort1", 7018)             -- 主服务器端口

    -- 备用服务器配置
    fskv.set("monitorIP2", "124.71.128.165")   -- 备用服务器地址
    fskv.set("monitorPort2", 7808)             -- 备用服务器端口

    -- ==================== 写入设备认证配置 ====================

    fskv.set("authCode1", "")   -- 主服务器认证码（首次为空）
    fskv.set("authCode2", "")   -- 备用服务器认证码（首次为空）

    -- ==================== 写入其他配置 ====================

    fskv.set("isInit", true)    -- 标记已初始化
    fskv.set("phoneList", {})   -- 联系人列表（默认为空）

    -- ==================== 写入GNSS低功耗配置 ====================

    fskv.set("gnssLowPowerEnable", false)  -- 默认禁用GNSS低功耗模式
    fskv.set("gnssLowPowerInterval", 60)   -- 定位间隔60秒
end

-- 执行初始化
init()

-- ==================== 读取GNSS低功耗配置到全局变量 ====================

--[[
GNSS低功耗配置加载
从fskv读取GNSS低功耗配置并设置到全局变量
其他模块通过全局变量 _G.GNSS_LOWPOWER_ENABLE 和 _G.GNSS_LOWPOWER_INTERVAL 访问

说明：
- 全局变量可以在启动时通过 _G.GNSS_LOWPOWER_ENABLE = true 手动修改
- 修改后需要重新启动或手动加载gnssLowPower模块生效
]]

-- 读取GNSS低功耗模式开关
_G.GNSS_LOWPOWER_ENABLE = fskv.get("gnssLowPowerEnable") or false

-- 读取GNSS低功耗模式定位间隔
_G.GNSS_LOWPOWER_INTERVAL = fskv.get("gnssLowPowerInterval") or 60

-- 打印GNSS低功耗配置
log.info("cfg", "GNSS低功耗模式", _G.GNSS_LOWPOWER_ENABLE, "间隔", _G.GNSS_LOWPOWER_INTERVAL, "秒")