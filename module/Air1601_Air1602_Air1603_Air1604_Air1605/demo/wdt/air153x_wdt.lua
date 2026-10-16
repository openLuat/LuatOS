-- air153x_wdt.lua
--[[
@summary Air153C/Air153D外部看门狗演示模块
@version 1.0
@date    2026.08.21
@author  陈媛媛
@usage
硬件介绍：
Air153C/Air153D是合宙推出的SOT23-6封装看门狗芯片，用于保障系统稳定性。
- Air153C：超时时间固定约240秒（3.3V供电时实测283秒）
- Air153D：通过STRAP引脚可配置超时时间（10分钟/60分钟/12小时/24小时）

核心信号：
- WTDOG（PIN3）：喂狗输入，常态低电平，高脉冲喂狗（>200ms）
- PWR_OFF（PIN4）：复位输出，喂狗异常时输出高电平触发主控复位

复位触发条件：
1. 超时复位：超过T_timeout未收到喂狗信号，PWR_OFF输出500ms高电平
2. 强制复位：1秒内连续收到3个喂狗信号，PWR_OFF立即输出500ms高电平

本示例演示三种使用场景：
1、auto_feed模式：配置看门狗，内部自动喂狗，系统持续运行
2、force_reset模式：配置看门狗，10秒后手动触发强制复位（3次快速脉冲）
3、no_feed模式：不配置看门狗，等待超时后自动复位模组

通过修改 DEMO_MODE 变量来选择演示模式

注意：
- force_reset模式下，设备会在10秒后触发硬件复位
- no_feed模式下，设备会在看门狗超时后自动复位（Air153C约240秒，Air153D取决于STRAP配置）
]]

local exair153x_wdt = require("exair153x_wdt")

-- 演示模式选择： "auto_feed"、 "force_reset" 或 "no_feed"
local DEMO_MODE = "auto_feed"  -- 修改这个变量来切换演示模式

local wdt_pin = 24  -- 看门狗喂狗引脚

-- 模式1：配置看门狗，内部自动喂狗
local function auto_feed_mode()
    log.info("wdt_demo", "模式1：自动喂狗模式启动")
    
    -- 初始化看门狗，启动自动喂狗任务
    -- 默认180秒自动喂狗一次
    exair153x_wdt.init({ wdt_pin = wdt_pin })
    
    log.info("wdt_demo", "看门狗已初始化，自动喂狗任务已启动")
    log.info("wdt_demo", "系统将自动维持看门狗，设备持续运行")
    
    -- 模拟业务逻辑运行
    local count = 0
    while true do
        count = count + 1
        log.info("wdt_demo", "业务逻辑运行中... 第" .. count .. "次循环")
        
        -- 可选：手动喂狗（有防误触发机制）
        -- exair153x_wdt.feed()
        
        sys.wait(30000)  -- 每30秒打印一次状态
    end
end

-- 模式2：10秒后手动执行强制复位
local function force_reset_mode()
    log.info("wdt_demo", "模式2：强制复位模式启动")
    
    -- 初始化看门狗
    exair153x_wdt.init({ wdt_pin = wdt_pin })
    
    log.info("wdt_demo", "看门狗已初始化")
    log.info("wdt_demo", "等待10秒后触发强制复位...")
    
    -- 等待10秒
    sys.wait(10000)
    
    -- 触发强制复位（3次快速脉冲触发芯片硬件复位）
    log.info("wdt_demo", "触发强制复位！")
    exair153x_wdt.trigger_reset()
    
    -- 芯片检测到3次快速脉冲后会触发硬件复位
    -- 以下代码不会执行（设备将复位）
    sys.wait(5000)
    log.info("wdt_demo", "如果看到这条日志，说明复位未成功")
end

-- 模式3：不配置看门狗，等待超时后自动复位
local function no_feed_mode()
    log.info("wdt_demo", "模式3：无喂狗模式启动")
    log.info("wdt_demo", "不初始化看门狗，等待看门狗超时自动复位")
    log.info("wdt_demo", "超时时间取决于Air153C/Air153D芯片的硬件配置")
    
    -- 不调用exair153x_wdt.init()，不喂狗
    -- 看门狗芯片会在超时后触发复位
    
    local count = 0
    while true do
        count = count + 1
        log.info("wdt_demo", "运行中... 第" .. count .. "次循环（无喂狗）")
        sys.wait(10000)  -- 每10秒打印一次
    end
end

-- 根据选择的模式执行对应函数
sys.taskInit(function()
    log.info("wdt_demo", "Air153C/Air153D外部看门狗演示 v" .. exair153x_wdt.version())
    log.info("wdt_demo", "当前模式: " .. DEMO_MODE)
    
    if DEMO_MODE == "auto_feed" then
        auto_feed_mode()
    elseif DEMO_MODE == "force_reset" then
        force_reset_mode()
    elseif DEMO_MODE == "no_feed" then
        no_feed_mode()
    else
        log.error("wdt_demo", "未知模式: " .. DEMO_MODE .. "，请选择 auto_feed、force_reset 或 no_feed")
    end
end)