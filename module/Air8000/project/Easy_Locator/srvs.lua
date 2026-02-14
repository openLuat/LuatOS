--[[
@module  srvs
@summary 服务器统一管理模块：屏蔽单服务器与多服务器差异，提供统一接口
@version 1.0
@author  Auto
@usage
本模块实现以下功能：
1. 多服务器管理：统一管理多个服务器实例
2. 数据发送：向所有服务器发送数据
3. 连接状态：查询服务器连接状态
4. 差异屏蔽：屏蔽单一服务器与多服务器的实现差异
]]

local srvs = {}

-- ==================== 全局变量 ====================

-- 日志开关
local logSwitch = true
local moduleName = "srvs"
local logPrefix = "[SRVS]"

-- 本地日志输出函数
local function logF(...)
    if logSwitch then
        log.info(moduleName, logPrefix, ...)
    end
end

-- 服务器实例列表
-- 存储：{ srv1, srv2, ... }
-- 每个srv应该实现以下接口：
--   - srv.dataSend(data): 发送数据
--   - srv.isConnected(): 检查连接状态
local ns = {}

-- ==================== 核心函数 ====================

--[[
向所有已注册的服务器发送数据
遍历服务器列表，依次调用每个服务器的dataSend方法

@api srvs.dataSend(data)
@any data 要发送的数据（zbuff或string）
@usage
-- 发送位置数据到所有服务器
local data = common.monitorRecord()
srvs.dataSend(data)

-- 发送自定义数据
srvs.dataSend(zbuff.create(200))
]]
function srvs.dataSend(data)
    -- 打印数据内容（用于调试）
    logF("========== 开始发送数据到服务器 ==========")
    if data then
        local dataType = type(data)
        if dataType == "zbuff" then
            local len = data:query() or 0
            logF("数据类型: zbuff, 长度:", len, "字节")

            -- 尝试解析JT808报文
            if len >= 16 then
                local dataStr = data:toStr(0, len) or ""
                printUploadDataFromSrvs(dataStr)
            end
        elseif dataType == "string" then
            logF("数据类型: string, 长度:", #data, "字节")

            -- 尝试解析JT808报文
            if #data >= 16 then
                printUploadDataFromSrvs(data)
            end
        else
            logF("数据类型:", dataType)
        end
    else
        logF("数据为空，将自动调用common.monitorRecord()获取数据")
    end
    logF("==========================================")

    -- 遍历所有服务器
    for i = 1, #ns do
        local srv = ns[i]
        -- 检查服务器是否实现了dataSend方法
        if srv.dataSend then
            -- 使用pcall保护，避免单个服务器出错影响其他服务器
            local res, info = pcall(srv.dataSend, data)
            if not res then
                log.info("dataSend error info", info)
            end
        end
    end

    logF("数据发送完成，服务器数量:", #ns)
end

-- 打印上传数据的关键信息（从srvs模块内部调用）
local function printUploadDataFromSrvs(dataStr)
    if not dataStr or #dataStr < 16 then
        return
    end

    -- 尝试提取位置信息（从JT808报文中解析）
    -- JT808报文格式: 7E + 消息ID(2) + 消息体属性(2) + 终端手机号(6) + 消息流水号(2) + 消息体 + 校验码 + 7E
    -- 消息ID(2字节) = 0x0200 表示位置信息上报

    -- 查找起始标识7E
    local startPos = dataStr:find("\126") -- 7E的ASCII码
    if not startPos then
        return
    end

    -- 提取消息ID（在起始标识后2字节）
    if #dataStr < startPos + 5 then
        return
    end

    local msgIdHex = string.format("%02X%02X", dataStr:byte(startPos + 1), dataStr:byte(startPos + 2))
    logF("消息ID:", msgIdHex)

    -- 如果是位置信息上报(0x0200)，解析经纬度
    if msgIdHex == "0200" then
        -- 基础定位信息位置：起始标识(1) + 消息ID(2) + 属性(2) + 手机号(6) + 流水号(2) + 状态(1) = 14字节
        -- 状态字节后: 纬度(4) + 经度(4) + 高度(2) + 速度(2) + 方向(2) + 时间(6) = 20字节
        -- 需要访问到 startPos + 26 (course)，所以需要至少 startPos + 27 字节长度
        if #dataStr >= startPos + 27 then
            local statusByte = dataStr:byte(startPos + 14)
            local latHex = string.format("%02X%02X%02X%02X",
                dataStr:byte(startPos + 15),
                dataStr:byte(startPos + 16),
                dataStr:byte(startPos + 17),
                dataStr:byte(startPos + 18))
            local lngHex = string.format("%02X%02X%02X%02X",
                dataStr:byte(startPos + 19),
                dataStr:byte(startPos + 20),
                dataStr:byte(startPos + 21),
                dataStr:byte(startPos + 22))
            local speedHex = string.format("%02X%02X",
                dataStr:byte(startPos + 23),
                dataStr:byte(startPos + 24))
            local courseHex = string.format("%02X%02X",
                dataStr:byte(startPos + 25),
                dataStr:byte(startPos + 26))

            -- 转换为十进制
            local lat = tonumber(latHex, 16) or 0
            local lng = tonumber(lngHex, 16) or 0
            local speed = tonumber(speedHex, 16) or 0
            local course = tonumber(courseHex, 16) or 0

            -- 经纬度显示（JT808格式是度*1000000，需要转换）
            local latDeg = lat / 1000000
            local lngDeg = lng / 1000000
            local latType = lat < 0 and "S" or "N"
            local lngType = lng < 0 and "W" or "E"

            logF("位置信息:")
            logF("  经度:", lngDeg, "度", lngType, " (原始值:", lng, ")")
            logF("  纬度:", latDeg, "度", latType, " (原始值:", lat, ")")
            logF("  速度:", speed, "km/h")
            logF("  航向:", course, "度")
            logF("  状态:", string.format("%02X", statusByte))
        end
    end

    logF("发送时间:", os.date("%Y-%m-%d %H:%M:%S"))
end

--[[
添加服务器实例到管理列表

@api srvs.add(task)
@table task 服务器实例，必须实现dataSend()方法
@usage
-- 添加测试服务器
local auxServer = require "auxServer"
srvs.add(auxServer)

-- 添加其他服务器
local otherServer = require "otherServer"
srvs.add(otherServer)
]]
function srvs.add(task)
    table.insert(ns, task)
end

--[[
查询任意一个服务器的连接状态
如果任意一个服务器已连接，则返回true

@api srvs.isConnected()
@return boolean true=至少有一个服务器已连接，false=所有服务器未连接
@usage
if srvs.isConnected() then
    log.info("服务器已连接")
else
    log.info("服务器未连接")
end
]]
function srvs.isConnected()
    -- 遍历所有服务器
    for i = 1, #ns do
        local srv = ns[i]
        -- 检查服务器是否实现了isConnected方法
        if srv.isConnected then
            -- 如果任意一个服务器已连接，返回true
            return srv.isConnected()
        end
    end
    -- 所有服务器未连接，返回false
end

return srvs
