--[[
@module exairlinkwdt
@summary 基于 AirLink 的远程看门狗管理库
@version 1.0
@date    2026.07.14
@author  马梦阳

@description
    提供设备间的看门狗喂狗和复位控制功能，
    通过 AirLink 通道实现远程看门狗管理。
    支持定时喂狗、超时复位和运行时参数动态更新。

@features
    - 通过 AirLink 通道发送喂狗/复位命令
    - 管理 TO_RESET 管脚输出，实现硬件复位
    - 支持定时喂狗和超时复位机制
    - 支持运行时参数动态更新

【重要 - 电平极性说明】
如果你的硬件是：GPIO → NPN三极管 → 上拉电阻到 VBAT → WTDOG
  NPN 是反相驱动：
  GPIO低 → 三极管截止 → WTDOG被上拉电阻拉为高电平(空闲)   → reset_idle_level = 0
  GPIO高 → 三极管导通 → WTDOG被拉到地为低电平(复位有效) → reset_idle_level = 1

如果你去掉三极管，GPIO 直接连接 WTDOG（电平一致）：
  GPIO高 → WTDOG高电平(空闲)   → reset_idle_level = 1
  GPIO低 → WTDOG低电平(复位有效) → reset_idle_level = 0

错误配置会导致：一直复位 / 一直不复位

@usage
local exairlinkwdt = require("exairlinkwdt")

-- 初始化看门狗，TO_RESET 使用 GPIO27
local success = exairlinkwdt.open({ reset_pin = 27 })

-- 正常喂狗
exairlinkwdt.feed(0)

-- 强制复位
exairlinkwdt.feed(1)

-- 更新本端参数（target 为 0 或者 nil）
exairlinkwdt.update({ timeout = 300 })

-- 更新对端参数（target 为 1）
exairlinkwdt.update({ timeout = 600, target = 1 })

-- 关闭看门狗
exairlinkwdt.close()

-- 获取库版本信息
exairlinkwdt.version()


-- 版本更新说明
-- 版本号：202607161200
-- 1、更新时间：2026-07-16 12:00
-- 2、更新内容
--    新增 exairlinkwdt.open() 接口，初始化看门狗并启动喂狗定时器
--    新增 exairlinkwdt.feed() 接口，支持正常喂狗和强制复位功能
--    新增 exairlinkwdt.close() 接口，关闭看门狗并发送关闭命令到对端
--    新增 exairlinkwdt.update() 接口，支持更新本端或对端的喂狗周期和超时时长
--    新增 exairlinkwdt.version() 接口，获取库版本信息
--    新增喂狗定时器功能，按周期自动发送喂狗命令
--    新增等待喂狗超时定时器功能，监控对端设备喂狗状态
--    新增懒加载机制，收到喂狗命令时自动配置 GPIO
--    新增参数校验机制，确保参数有效性和合法性
-- 
-- 版本号：202607190000
-- 1、更新时间：2026-07-19 00:00
-- 2、更新内容
--    新增电平极性说明，说明 NPN 三极管的电平极性关系
--    修改默认空闲电平为低电平（reset_idle_level = 0）
]]

-- 命令常量定义
local CMD_FEED = "WDT:FEED"      -- 喂狗命令
local CMD_RESET = "WDT:RESET"    -- 强制复位命令
local CMD_OPEN = "WDT:OPEN"      -- 开启看门狗命令
local CMD_CLOSE = "WDT:CLOSE"    -- 关闭看门狗命令
local CMD_UPDATE_PREFIX = "WDT:UPDATE:"  -- 参数更新命令前缀

-- 默认参数配置
local DEFAULT_FEED_INTERVAL = 150 * 1000  -- 默认喂狗周期：150秒（转换为毫秒）
local DEFAULT_TIMEOUT = 240 * 1000        -- 默认超时时长：240秒（转换为毫秒）

-- 内部状态变量
local is_initialized = false      -- 初始化状态标志
local reset_pin = nil             -- TO_RESET 管脚号
local reset_idle_level = 0        -- TO_RESET 管脚常态电平（默认低电平）
local feed_interval = DEFAULT_FEED_INTERVAL  -- 当前喂狗周期
local timeout = DEFAULT_TIMEOUT              -- 当前超时时长
local feed_timer_id = nil         -- 喂狗定时器ID
local timeout_timer_id = nil      -- 等待喂狗超时定时器ID
local gpio_set_func = nil         -- GPIO 设置函数引用

-- 模块导出表
local exairlinkwdt = {}

--[[
@function send_command
@summary 发送 AirLink 命令
@param string cmd 命令字符串
@return boolean 发送是否成功
]]
local function send_command(cmd)
    -- 发送命令
    local result = airlink.sdata(cmd)
    if not result then
        log.error("exairlinkwdt", "命令发送失败:", cmd)
        return false
    end
    
    log.info("exairlinkwdt", "命令发送成功:", cmd)
    return true
end

--[[
@function restore_idle_level
@summary 恢复常态电平
@description 复位脉冲结束后调用，恢复 TO_RESET 管脚到常态电平
]]
local function restore_idle_level()
    if gpio_set_func then
        gpio_set_func(reset_idle_level)
        log.info("exairlinkwdt", "TO_RESET 管脚恢复常态电平:", reset_idle_level)
    end
end

--[[
@function stop_feed_timer
@summary 停止喂狗定时器
]]
local function stop_feed_timer()
    if feed_timer_id then
        sys.timerStop(feed_timer_id)
        feed_timer_id = nil
        log.info("exairlinkwdt", "喂狗定时器已停止")
    end
end

--[[
@function stop_timeout_timer
@summary 停止等待喂狗超时定时器
]]
local function stop_timeout_timer()
    if timeout_timer_id then
        sys.timerStop(timeout_timer_id)
        timeout_timer_id = nil
        log.info("exairlinkwdt", "等待喂狗超时定时器已停止")
    end
end

--[[
@function send_reset_command
@summary 发送复位命令
@description 发送 WDT:RESET 命令给对端，对端收到后自行复位
@return boolean 发送是否成功
]]
local function send_reset_command()
    return send_command(CMD_RESET)
end

--[[
@function hardware_reset
@summary 硬件复位
@description 通过 TO_RESET 管脚输出复位电平，强制复位对端设备
@return boolean 复位是否成功
]]
local function hardware_reset()
    -- 触发本地 TO_RESET 管脚输出复位电平
    if gpio_set_func then
        -- 输出与常态相反的电平触发复位
        local reset_level = (reset_idle_level == 1) and 0 or 1
        gpio_set_func(reset_level)
        log.warn("exairlinkwdt", "TO_RESET 管脚输出复位电平:", reset_level)
        
        -- 延时后恢复常态电平（复位脉冲宽度）
        sys.timerStart(restore_idle_level, 100)  -- 100ms 复位脉冲
        return true
    end
    log.error("exairlinkwdt", "TO_RESET 管脚未初始化，无法触发复位")
    return false
end

--[[
@function timeout_timer_callback
@summary 等待喂狗超时定时器回调函数
@description 喂狗超时后通过 TO_RESET 管脚硬件复位对端设备
]]
local function timeout_timer_callback()
    log.warn("exairlinkwdt", "等待喂狗超时，触发硬件复位")
    hardware_reset()
end

--[[
@function start_timeout_timer
@summary 启动等待喂狗超时定时器
@description 超时后触发复位动作
]]
local function start_timeout_timer()
    -- 停止已有的等待喂狗超时定时器
    stop_timeout_timer()
    
    -- 创建单次等待喂狗超时定时器
    timeout_timer_id = sys.timerStart(timeout_timer_callback, timeout)
    
    if timeout_timer_id then
        log.info("exairlinkwdt", "等待喂狗超时定时器启动，超时时长:", timeout, "ms")
    else
        log.error("exairlinkwdt", "等待喂狗超时定时器启动失败")
    end
end

--[[
@function feed_action
@summary 喂狗动作
@description 发送喂狗命令给对端
@return boolean 喂狗是否成功
]]
local function feed_action()
    -- 发送喂狗命令
    local success = send_command(CMD_FEED)
    return success
end

--[[
@function feed_timer_callback
@summary 喂狗定时器回调函数
@description 定时执行喂狗动作
]]
local function feed_timer_callback()
    feed_action()
end

--[[
@function start_feed_timer
@summary 启动喂狗定时器
@description 按 feed_interval 周期自动发送喂狗命令
]]
local function start_feed_timer()
    -- 停止已有的喂狗定时器
    stop_feed_timer()
    
    -- 创建循环定时器
    feed_timer_id = sys.timerLoopStart(feed_timer_callback, feed_interval)
    
    if feed_timer_id then
        log.info("exairlinkwdt", "喂狗定时器启动，周期:", feed_interval, "ms")
    else
        log.error("exairlinkwdt", "喂狗定时器启动失败")
    end
end

--[[
@function reboot_task
@summary 延迟重启任务
@description 等待500ms后执行重启，确保日志输出完成
]]
local function reboot_task()
    sys.wait(500)
    pm.reboot()
end

--[[
@function parse_update_command
@summary 解析参数更新命令
@description 从 WDT:UPDATE: 命令中解析参数
@param string data 命令字符串
@return table 解析后的参数表
]]
local function parse_update_command(data)
    local params = {}
    -- 解析 "WDT:UPDATE:timeout=300,feed_interval=200" 格式
    local param_str = string.sub(data, #CMD_UPDATE_PREFIX + 1)
    -- 打印解析过程，便于调试
    -- log.info("exairlinkwdt", "解析更新命令，原始数据:", data, "参数字符串:", param_str)
    for key, value in string.gmatch(param_str, "([%w_]+)=(%d+)") do
        params[key] = tonumber(value)
        -- log.info("exairlinkwdt", "解析到参数:", key, "=", value)
    end
    -- 打印解析结果
    -- log.info("exairlinkwdt", "解析结果: timeout=", params.timeout, "feed_interval=", params.feed_interval)
    return params
end

--[[
@function send_update_command
@summary 发送参数更新命令给对端
@param table params 参数表（秒单位）
@return boolean 发送是否成功
]]
local function send_update_command(params)
    local parts = {}
    if params.timeout then
        table.insert(parts, "timeout=" .. params.timeout)
    end
    if params.feed_interval then
        table.insert(parts, "feed_interval=" .. params.feed_interval)
    end
    local cmd = CMD_UPDATE_PREFIX .. table.concat(parts, ",")
    return send_command(cmd)
end

--[[
@function airlink_sdata_handler
@summary AirLink SDATA 事件处理函数
@description 处理来自对端的看门狗命令
@param string data 接收到的数据
]]
local function airlink_sdata_handler(data)
    -- 检查数据有效性
    if not data or type(data) ~= "string" then
        return
    end
    
    -- 解析命令
    if data == CMD_FEED then
        -- 收到喂狗命令，重置等待喂狗超时定时器
        if is_initialized then
            log.info("exairlinkwdt", "收到喂狗命令，重置等待喂狗超时定时器")
            -- 如果还未配置GPIO，说明对端已开始喂狗，本端也应配置GPIO并启动等待喂狗超时定时器
            if gpio_set_func == nil and reset_pin then
                gpio_set_func = gpio.setup(reset_pin, reset_idle_level)
                if gpio_set_func then
                    log.info("exairlinkwdt", "发现还未配置 GPIO，配置 TO_RESET 管脚为输出模式，初始电平:", reset_idle_level)
                else
                    log.error("exairlinkwdt", "GPIO 初始化失败，管脚号:", reset_pin)
                end
            end
            -- 重启等待喂狗超时定时器（内部会先停止旧定时器再创建新的）
            start_timeout_timer()
        end
    elseif data == CMD_RESET then
        -- 收到对端发来的复位命令，本端主动复位
        if is_initialized then
            log.warn("exairlinkwdt", "收到复位命令，本端即将复位")
            sys.taskInit(reboot_task)
        end
    elseif data == CMD_OPEN then
        -- 收到对端发来的开启命令，配置本端 TO_RESET 管脚并启动等待喂狗超时定时器
        if not is_initialized then
            log.info("exairlinkwdt", "收到开启命令，等待本端调用 open() 初始化")
        elseif reset_pin and not gpio_set_func then
            -- 配置 TO_RESET 管脚为输出模式，初始输出常态电平
            gpio_set_func = gpio.setup(reset_pin, reset_idle_level)
            if gpio_set_func then
                log.info("exairlinkwdt", "TO_RESET 管脚配置成功，管脚:", reset_pin, "常态电平:", reset_idle_level)
                -- 启动等待喂狗超时定时器
                start_timeout_timer()
            else
                log.error("exairlinkwdt", "TO_RESET 管脚配置失败，管脚:", reset_pin)
            end
        end
    elseif data == CMD_CLOSE then
        -- 收到对端发来的关闭命令
        if is_initialized then
            log.info("exairlinkwdt", "收到关闭命令，关闭等待喂狗超时定时器")
            -- 关闭等待喂狗超时定时器
            stop_timeout_timer()
            -- 将 TO_RESET 管脚恢复为输入模式
            if reset_pin and gpio_set_func then
                gpio.setup(reset_pin, nil)  -- nil 表示输入模式
                gpio_set_func = nil
                log.info("exairlinkwdt", "TO_RESET 管脚已恢复为输入模式")
            end
            is_initialized = false
        end
    elseif string.sub(data, 1, #CMD_UPDATE_PREFIX) == CMD_UPDATE_PREFIX then
        -- 收到参数更新命令，解析并更新本端参数
        local update_params = parse_update_command(data)
        if update_params.timeout or update_params.feed_interval then
            -- 调用本端 update 函数更新参数（target=0）
            exairlinkwdt.update({
                timeout = update_params.timeout,
                feed_interval = update_params.feed_interval,
                target = 0
            })
        end
    end
end

--[[
@api exairlinkwdt.open(options)
@summary 初始化看门狗
@description 记录配置参数，发送开启命令到对端，启动喂狗定时器
@param table options 配置参数表
    - reset_pin number TO_RESET 管脚号（必选）
    - reset_idle_level number 常态电平（可选，默认为0低电平）
@return boolean 初始化是否成功
]]
function exairlinkwdt.open(options)
    -- 检查重复初始化
    if is_initialized then
        log.warn("exairlinkwdt", "看门狗已初始化，请勿重复调用")
        return false
    end
    
    -- 参数校验
    if not options or type(options) ~= "table" then
        log.error("exairlinkwdt", "参数必须是 table 类型")
        return false
    end
    
    -- 检查必选参数 reset_pin
    if not options.reset_pin or type(options.reset_pin) ~= "number" then
        log.error("exairlinkwdt", "reset_pin 参数无效，必须是数字类型")
        return false
    end
    
    -- 记录配置参数
    reset_pin = options.reset_pin
    reset_idle_level = options.reset_idle_level or 0  -- 默认低电平
    
    -- 验证电平参数
    if reset_idle_level ~= 0 and reset_idle_level ~= 1 then
        log.error("exairlinkwdt", "reset_idle_level 必须是 0 或 1")
        return false
    end
    
    -- 设置初始化状态
    is_initialized = true
    
    -- 发送开启看门狗命令到对端，对端收到后会配置 TO_RESET 管脚并启动等待喂狗超时定时器
    send_command(CMD_OPEN)
    
    -- 立即执行一次喂狗
    feed_action()
    
    -- 启动喂狗定时器
    start_feed_timer()
    
    log.info("exairlinkwdt", "看门狗初始化成功，管脚:", reset_pin, "常态电平:", reset_idle_level)
    return true
end

--[[
@api exairlinkwdt.feed(mode)
@summary 喂狗操作
@description 发送喂狗或强制复位命令到对端设备
@param number mode 喂狗模式
    - 0: 正常喂狗，发送 WDT:FEED 命令
    - 1: 强制复位，发送 WDT:RESET 命令，对端收到后自行复位
@return boolean 操作是否成功
]]
function exairlinkwdt.feed(mode)
    -- 检查初始化状态
    if not is_initialized then
        log.error("exairlinkwdt", "看门狗未初始化，请先调用 open()")
        return false
    end
    
    -- 参数校验
    if mode ~= 0 and mode ~= 1 then
        log.error("exairlinkwdt", "mode 参数必须是 0 或 1")
        return false
    end
    
    -- 根据模式执行相应动作
    if mode == 0 then
        -- 正常喂狗
        return feed_action()
    else
        -- 强制复位：发送复位命令给对端，对端收到后自行复位
        return send_reset_command()
    end
end

--[[
@api exairlinkwdt.close()
@summary 关闭看门狗
@description 关闭喂狗定时器，发送关闭命令到对端
@return boolean 关闭是否成功
]]
function exairlinkwdt.close()
    -- 检查初始化状态
    if not is_initialized then
        log.warn("exairlinkwdt", "看门狗未初始化，无需关闭")
        return false
    end
    
    -- 关闭喂狗定时器
    stop_feed_timer()
    
    -- 发送关闭命令到对端，对端收到后会关闭等待喂狗超时定时器并恢复 TO_RESET 管脚
    send_command(CMD_CLOSE)
    
    -- 清理状态
    is_initialized = false
    
    log.info("exairlinkwdt", "看门狗已关闭")
    return true
end

--[[
@api exairlinkwdt.update(params)
@summary 更新看门狗参数
@description 支持更新单个或多个参数，更新喂狗周期时立即重置定时器
@param table params 参数配置表
    - timeout number 超时时长（秒）
    - feed_interval number 喂狗周期（秒）
    - target number 更新目标：0=本端（默认），1=对端
@return boolean 更新是否成功
]]
function exairlinkwdt.update(params)
    -- 检查初始化状态
    if not is_initialized then
        log.error("exairlinkwdt", "看门狗未初始化，请先调用 open()")
        return false
    end
    
    -- 参数校验
    if not params or type(params) ~= "table" then
        log.error("exairlinkwdt", "参数必须是 table 类型")
        return false
    end
    
    -- 检查是否至少有一个有效参数
    local new_timeout = params.timeout
    local new_feed_interval = params.feed_interval
    
    if not new_timeout and not new_feed_interval then
        log.error("exairlinkwdt", "至少需要传入 timeout 或 feed_interval 中的一个参数")
        return false
    end
    
    -- 校验参数类型和范围
    if new_timeout then
        if type(new_timeout) ~= "number" or new_timeout <= 0 then
            log.error("exairlinkwdt", "timeout 必须是正整数（秒）")
            return false
        end
    end
    
    if new_feed_interval then
        if type(new_feed_interval) ~= "number" or new_feed_interval <= 0 then
            log.error("exairlinkwdt", "feed_interval 必须是正整数（秒）")
            return false
        end
    end
    
    -- 获取 target 参数，默认为 0（本端）
    local target = params.target or 0
    
    -- 校验 target 参数
    if target ~= 0 and target ~= 1 then
        log.error("exairlinkwdt", "target 参数必须是 0 或 1")
        return false
    end
    
    -- 如果是更新对端参数，发送更新命令
    if target == 1 then
        -- 构建参数表（保持秒单位）
        local update_params = {}
        if new_timeout then
            update_params.timeout = new_timeout
        end
        if new_feed_interval then
            update_params.feed_interval = new_feed_interval
        end
        -- 发送更新命令给对端
        return send_update_command(update_params)
    end
    
    -- 以下为更新本端参数的逻辑
    -- 转换为毫秒
    if new_timeout then
        new_timeout = new_timeout * 1000
    end
    if new_feed_interval then
        new_feed_interval = new_feed_interval * 1000
    end
    
    --[[
        参数关系校验规则：
        1. 只更新喂狗周期时，要求小于当前超时时间
        2. 只更新超时时间时，要求大于当前喂狗周期
        3. 两个都更新时，先更新喂狗周期，再更新超时时间
    ]]
    if new_timeout and new_feed_interval then
        -- 两个都更新时，先更新喂狗周期
        if new_feed_interval >= new_timeout then
            log.error("exairlinkwdt", "feed_interval 必须小于 timeout")
            return false
        end
        feed_interval = new_feed_interval
        timeout = new_timeout
    elseif new_timeout then
        -- 只更新超时时间，要求大于当前喂狗周期
        if new_timeout <= feed_interval then
            log.error("exairlinkwdt", "timeout 必须大于当前 feed_interval:", feed_interval, "ms")
            return false
        end
        timeout = new_timeout
    elseif new_feed_interval then
        -- 只更新喂狗周期，要求小于当前超时时间
        if new_feed_interval >= timeout then
            log.error("exairlinkwdt", "feed_interval 必须小于当前 timeout:", timeout, "ms")
            return false
        end
        feed_interval = new_feed_interval
    end
    
    -- 如果更新了喂狗周期且喂狗定时器正在运行，立即重置喂狗定时器
    if new_feed_interval and feed_timer_id then
        start_feed_timer()
    end
    
    --[[
        如果只更新了超时时间，不重启等待喂狗超时定时器
        等下次收到喂狗命令时自然重置，避免意外触发超时
    ]]
    
    -- 根据实际更新的参数输出日志
    if new_timeout and new_feed_interval then
        log.info("exairlinkwdt", "参数更新成功，喂狗周期:", feed_interval, "ms，超时时长:", timeout, "ms")
    elseif new_timeout then
        log.info("exairlinkwdt", "超时时长更新成功:", timeout, "ms")
    elseif new_feed_interval then
        log.info("exairlinkwdt", "喂狗周期更新成功:", feed_interval, "ms")
    end
    return true
end

--[[
获取库版本信息
@return string 年月日时分，例如： "202607161200"
@usage
exairlinkwdt.version()
]]
function exairlinkwdt.version()
    return "202607190000"
end

log.debug("exairlinkwdt", "version -> " .. exairlinkwdt.version())

-- 订阅 AirLink SDATA 事件
sys.subscribe("AIRLINK_SDATA", airlink_sdata_handler)

-- 返回模块
return exairlinkwdt