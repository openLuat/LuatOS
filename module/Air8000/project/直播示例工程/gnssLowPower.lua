--[[
@module  gnssLowPower
@summary GNSS低功耗定位模块，仅上传数据到测试服务器
@version 3.0
@date    2025.02.02
@usage
本模块封装了低功耗GNSS定位功能，定时开启GNSS定位一次，
获取经纬度后仅通过测试服务器(auxServer)上传，不上传到其他服务器。
集成完整的AGPS逻辑，包括星历下载、基站定位辅助等。
使用exgnss接口实现。
]]

-- 模块导出表
local gnssLowPower = {}

-- 模块名称和日志开关
local moduleName = "gnssLowPower"
local logSwitch = true

-- 引入exgnss扩展库
local exgnss = require "exgnss"

-- 本地日志输出函数
local function logF(...)
    if logSwitch then
        log.info(moduleName, ...)
    end
end

-- GNSS低功耗配置参数
local gnssOpts = {
    gnssmode = 1,           -- 1为卫星全定位(GPS+北斗)，2为单北斗
    agps_enable = true,      -- 启用AGPS辅助定位，加速首次定位
    debug = true,           -- 是否输出调试信息
    auto_open = false,      -- 不自动打开GNSS，由本模块控制开关
    hz = 1,                -- 定位频率1Hz，每秒定位一次
}

-- exgnss应用标签，用于引用计数管理
-- 使用独立标签避免与common模块的GNSS应用冲突
local gnssAppTag = "gnssLowPower"

-- 打开GNSS低功耗模式
-- 定时开启GNSS定位，获取位置后上传到测试服务器
-- @param interval 定位间隔(秒)，默认60秒
-- 使用exgnss的TIMERORSUC模式：定位成功或超时后自动关闭GNSS
function gnssLowPower.open(interval)
    interval = interval or 60  -- 默认60秒定位一次

    logF("打开GNSS低功耗模式", "间隔", interval, "秒")

    -- 设置GNSS参数
    exgnss.setup(gnssOpts)

    -- 定义定位回调函数
    -- 当GNSS定位成功或超时时，exgnss会调用此回调
    local function lowpower_callback(tag)
        logF("低功耗定位回调", tag)

        -- 获取RMC数据(推荐航向定位信息)
        -- 参数3表示获取最近3秒内的数据
        local rmc = exgnss.rmc(3)
        logF("RMC数据", json.encode(rmc))

        -- 检查定位是否有效
        if not rmc or not rmc.lat or not rmc.lng then
            logF("定位数据无效，放弃上传")
            return
        end

        -- 保存最后位置到本地文件
        -- 文件路径：/hxxtloc，格式：JSON
        local locData = json.encode({lat = rmc.lat, lng = rmc.lng, time = os.time()})
        io.writeFile("/hxxtloc", locData)
        logF("保存位置到本地", locData)

        -- 准备构建JT808定位数据包
        local lat, lng = rmc.lat, rmc.lng
        local gga = exgnss.gga(2)     -- 获取GGA数据，包含高度信息
        local vtg = exgnss.vtg()      -- 获取VTG数据，包含速度和航向
        local speed = (vtg and vtg.speed_kph or 0)  -- 速度(km/h)
        local course = rmc.course or 0               -- 航向(度)
        local altitude = gga and gga.altitude or 0   -- 高度(米)

        -- 构建测试服务器定位数据包（JT808协议）
        -- 获取UTC时间
        local tTime = os.date("!*t", os.time())
        local status = 0  -- JT808状态位

        -- 设置定位状态位
        if rmc.valid then
            status = status + 0x02  -- bit1: 定位有效
        end

        -- 设置南纬位
        if lat < 0 then
            status = status + 0x04  -- bit2: 南纬
            lat = math.abs(lat)
        end

        -- 设置西经位
        if lng < 0 then
            status = status + 0x08  -- bit3: 西经
            lng = math.abs(lng)
        end

        -- 时间格式转换为BCD
        local timeStr = api.NumToBCDBin(tTime.year % 100, 1) ..
                       api.NumToBCDBin(tTime.month, 1) ..
                       api.NumToBCDBin(tTime.day, 1) ..
                       api.NumToBCDBin(tTime.hour, 1) ..
                       api.NumToBCDBin(tTime.min, 1) ..
                       api.NumToBCDBin(tTime.sec, 1)

        -- 构建定位基础信息(JT808 0x0200消息体)
        local baseInfo = jt808.makeLocatBaseInfoMsg(0, status, lat, lng,
            math.floor(altitude), math.floor(speed), math.floor(course), timeStr)

        -- 添加电池信息(0x04附件)
        -- 格式：附件ID(1字节) + 长度(1字节) + 充电状态(1字节) + 电量百分比(1字节)
        baseInfo = baseInfo .. api.NumToBigBin(0x04, 1) ..
                   api.NumToBigBin(2, 1) ..
                   api.NumToBigBin(charge.isCharge() and 0 or 1, 1) ..
                   api.NumToBigBin(charge.getBatteryPercent(), 1)

        -- 添加电压信息(0x2B附件)
        -- 格式：附件ID(1字节) + 长度(1字节) + 电压(2字节) + 保留(2字节)
        baseInfo = baseInfo .. api.NumToBigBin(0x2B, 1) ..
                   api.NumToBigBin(4, 1) ..
                   api.NumToBigBin(charge.getVbat(), 2) ..
                   api.NumToBigBin(0, 2)

        -- 添加信号强度(0x30附件)
        -- 格式：附件ID(1字节) + 长度(1字节) + CSQ信号值(1字节)
        baseInfo = baseInfo .. api.NumToBigBin(0x30, 1) ..
                   api.NumToBigBin(1, 1) ..
                   api.NumToBigBin(mobile.csq(), 1)

        -- 添加GNSS工作模式标识(0x64附件)
        -- 格式：附件ID(1字节) + 长度(1字节) + 模式(1字节)
        -- 模式值：1=CAPTURE, 2=STATIC_GNSS, 4=STATIC_LBS, 8=TRACKING
        baseInfo = baseInfo .. api.NumToBigBin(0x64, 1) ..
                   api.NumToBigBin(1, 1) ..
                   api.NumToBigBin(2, 1)  -- 2表示GNSS低功耗模式

        -- 创建zbuff缓冲区并复制数据
        local item = zbuff.create(200)
        item:copy(nil, baseInfo)

        -- 只发送到测试服务器(auxServer)
        if auxServer then
            local result, msg = auxServer.dataSend(item)
            logF("数据发送到测试服务器", result, msg)
        else
            logF("auxServer未加载，数据未发送")
            item:free()  -- 释放缓冲区
        end
    end

    -- 使用exgnss的TIMERORSUC模式
    -- 特性：定位成功或超时后自动关闭GNSS，节省功耗
    -- tag: 应用标签，用于引用计数
    -- val: 最大定位时长(秒)
    -- cb: 定位完成或超时后的回调函数
    exgnss.open(exgnss.TIMERORSUC, {tag = gnssAppTag, val = interval, cb = lowpower_callback})

    -- 启动自己的定时器来循环开启
    -- 虽然TIMERORSUC模式会自动关闭，但需要定时器循环重新打开
    sys.timerLoopStart(function()
        logF("定时开启GNSS定位")
        exgnss.open(exgnss.TIMERORSUC, {tag = gnssAppTag, val = interval, cb = lowpower_callback})
    end, interval * 1000)

    logF("GNSS低功耗模式已启动")
end

-- 关闭GNSS低功耗模式
-- 停止定时定位，释放GNSS资源
function gnssLowPower.close()
    logF("关闭GNSS低功耗模式")
    -- 关闭GNSS应用，exgnss会自动关闭定时器和GNSS硬件
    exgnss.close(exgnss.TIMERORSUC, {tag = gnssAppTag})
end

-- 初始化GNSS低功耗模块
-- 在使用open之前调用，进行必要的初始化工作
function gnssLowPower.init()
    logF("初始化GNSS低功耗模块")
    -- exgnss会自动管理串口、电源、AGPS等，这里不需要额外配置
end

return gnssLowPower
