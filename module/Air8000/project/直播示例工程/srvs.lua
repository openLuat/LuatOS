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
