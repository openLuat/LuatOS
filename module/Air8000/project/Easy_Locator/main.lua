--[[
@file main.lua
@summary 主程序入口：项目配置、模块加载、系统启动
@version 1.0
@author  Auto
@usage
本项目：放学接我智能学生卡
主程序流程：
1. 定义项目信息（PROJECT、VERSION、PRODUCT_KEY等）
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

-- ==================== 开机初始化 ====================

--[[
开机防抖
防止误触发开机键
]]
pm.power(pm.PWK_MODE, true)

-- ==================== 加载功能模块[启动系统] ====================

--[[
加载bootup模块
bootup.lua负责：
1. 加载所有功能模块到全局环境
2. 配置轨迹补偿参数
3. 初始化GNSS低功耗模块（可选）
4. 初始化服务器管理
]]
require "bootup"

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句：启动系统主循环
sys.run()
