--[[
@file main.lua
@summary 主程序入口：项目配置、模块加载、系统启动
@version 1.0
@author  Auto
@usage
本项目：放学接我智能学生卡
主程序流程：
1. 定义项目信息（PROJECT、VERSION、PRODUCT_KEY等）
2. 加载系统库（sys、sysplus）
3. 开机防抖处理
4. 关闭GPS电源（启动时关闭，后续按需打开）
5. 加载bootup模块（加载所有功能模块）
6. 启动系统主循环（sys.run()）
]]

-- ==================== 项目信息 ====================

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "StudentCard"         -- 项目名称
VERSION = "1.2.0"               -- 软件版本
PRODUCT_KEY = "123"             -- 产品密钥

-- 产品信息：放学接我
PRODUCT_VER = "0003"            -- 产品版本号

log.info("main", PROJECT, VERSION, PRODUCT_VER)

-- ==================== 加载系统库 ====================

-- 引入必要的库文件（Lua编写）
-- 内部库（C编写）不需要require
_G.sys = require "sys"          -- 系统库（事件驱动框架）
_G.sysplus = require "sysplus"  -- 系统扩展库

-- ==================== 开机初始化 ====================

--[[
开机防抖
防止误触发开机键
]]
pm.power(pm.PWK_MODE, true)

--[[
关闭GPS电源
启动时关闭GPS，降低功耗
后续按需打开GNSS（在common.lua中控制）

注意：这里关闭的是GPS芯片的电源，不是GNSS库
]]
local result = pm.power(pm.GPS, false)
log.info("main", "gps power off", result)

-- ==================== 加载功能模块 ====================

--[[
加载bootup模块
bootup.lua负责：
1. 加载所有功能模块到全局环境
2. 配置轨迹补偿参数
3. 初始化GNSS低功耗模块（可选）
4. 初始化服务器管理
]]
require "bootup"

-- ==================== 启动系统 ====================

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句：启动系统主循环
sys.run()
