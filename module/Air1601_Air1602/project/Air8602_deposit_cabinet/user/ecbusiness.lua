--[[
@module  ecbusiness
@summary 寄存柜业务逻辑模块
@version 2.0
@date    2026.10.16
@author  王城钧
@usage
本模块实现智能寄存柜系统的存取件业务逻辑，包括存件、取件、验证取件码等功能。
处理用户操作与服务器接口、串口控制之间的协调。
]]


-- 先声明 ecbusiness 变量
local ecbusiness = {}

-- 导入必要的模块
local server_api = require "server_api"
local uart_controller = require "uart_controller"

-- 存取件状态定义
local BUSINESS_STATUS = {
    IDLE = 0,               -- 空闲
    DEPOSITING = 1,         -- 存件中
    VERIFYING = 2,          -- 验证中
    PICKING = 3,            -- 取件中
    ERROR = 4               -- 错误
}

-- 全局状态
local business_state = BUSINESS_STATUS.IDLE

-- 小程序码图片缓存
local qr_code_image_data = nil

--[[
获取可用箱子列表
@return: 箱子状态数组或nil
]]
local function get_available_boxes()
    log.info("ecbusiness", "获取可用箱子列表")
    
    local success, result = server_api.get_locker_status()
    
    if not success then
        log.error("ecbusiness", "获取柜子状态失败")
        return nil
    end
    
    return result
end

--[[
存件流程
@param user_info: 用户信息
@return: 操作结果
]]
function ecbusiness.deposit(user_info)
    log.info("ecbusiness", "开始存件流程")
    
    if business_state ~= BUSINESS_STATUS.IDLE then
        log.error("ecbusiness", "业务状态繁忙")
        return false, "业务状态繁忙"
    end
    
    business_state = BUSINESS_STATUS.DEPOSITING
    
    -- 获取可用箱子
    local available_boxes = get_available_boxes()
    if not available_boxes then
        business_state = BUSINESS_STATUS.ERROR
        return false, "获取可用箱子失败"
    end
    
    -- 选择一个可用的箱子
    local selected_box = nil
    for i, box in ipairs(available_boxes) do
        if box.available then
            selected_box = box
            break
        end
    end
    
    if not selected_box then
        business_state = BUSINESS_STATUS.IDLE
        return false, "无可用箱子"
    end
    
    -- 发送人脸存件请求到服务器（POST /face_store）
    -- user_info 需包含 face_id（人脸ID）与 face_name（人脸名称）
    local face_id = (user_info and user_info.face_id) or ""
    local face_name = (user_info and user_info.face_name) or ""
    local success, result = server_api.face_store(selected_box.box_num, face_id, face_name)
    
    if not success then
        business_state = BUSINESS_STATUS.ERROR
        return false, result or "存件请求失败"
    end
    
    -- 服务器返回的箱子编号与取件码（成功时 value 含 box/pickup_code/save_code/record_id）
    local box_num = selected_box.box_num
    local pickup_code = result.pickup_code
    local save_code = result.save_code
    local record_id = result.record_id
    
    -- 发送打开箱子的命令
    log.info("ecbusiness", "发送打开箱子" .. box_num .. "的命令")
    sys.publish("OPEN_BOX", box_num)
    
    -- 等待开柜结果
    local open_result = sys.waitUntil("BOX_OPEN_RESULT", 5000)
    
    if not open_result then
        business_state = BUSINESS_STATUS.ERROR
        return false, "开柜超时"
    end
    
    if not open_result.success then
        business_state = BUSINESS_STATUS.ERROR
        return false, "开柜失败: " .. (open_result.error or "未知错误")
    end
    
    -- 存件成功
    business_state = BUSINESS_STATUS.IDLE
    log.info("ecbusiness", "存件成功，箱子: " .. box_num .. ", 取件码: " .. tostring(pickup_code) .. ", 存件码: " .. tostring(save_code))
    
    return true, {
        box_num = box_num,
        pickup_code = pickup_code,
        save_code = save_code,
        record_id = record_id,
        user_info = user_info
    }
end

--[[
验证取件码
@param box_num: 箱子编号
@param pickup_code: 取件码
@return: 验证结果
]]
function ecbusiness.verify_pickup_code(box_num, pickup_code)
    log.info("ecbusiness", "验证取件码，箱子: " .. box_num)
    
    business_state = BUSINESS_STATUS.VERIFYING
    
    local success, result = server_api.verify_pickup_code(box_num, pickup_code)
    
    if not success then
        business_state = BUSINESS_STATUS.IDLE
        return false, result or "验证失败"
    end
    
    business_state = BUSINESS_STATUS.PICKING
    
    return true, "验证成功"
end

--[[
取件流程
@param box_num: 箱子编号
@param pickup_code: 取件码
@return: 操作结果
]]
function ecbusiness.pickup(box_num, pickup_code)
    log.info("ecbusiness", "开始取件流程，箱子: " .. box_num)
    
    -- 验证取件码
    local success, result = ecbusiness.verify_pickup_code(box_num, pickup_code)
    
    if not success then
        return false, result
    end
    
    -- 发送打开箱子的命令
    log.info("ecbusiness", "发送打开箱子" .. box_num .. "的命令")
    sys.publish("OPEN_BOX", box_num)
    
    -- 等待开柜结果
    local open_result = sys.waitUntil("BOX_OPEN_RESULT", 5000)
    
    if not open_result then
        business_state = BUSINESS_STATUS.ERROR
        return false, "开柜超时"
    end
    
    if not open_result.success then
        business_state = BUSINESS_STATUS.ERROR
        return false, "开柜失败: " .. (open_result.error or "未知错误")
    end
    
    -- 发送取件完成请求到服务器
    local success, result = server_api.pickup_item(box_num, pickup_code)
    
    if not success then
        business_state = BUSINESS_STATUS.ERROR
        return false, result or "取件请求失败"
    end
    
    -- 取件成功
    business_state = BUSINESS_STATUS.IDLE
    log.info("ecbusiness", "取件成功，箱子: " .. box_num)
    
    return true, "取件成功"
end

--[[
获取系统状态
@return: 系统状态
]]
function ecbusiness.get_system_status()
    return {
        business_state = business_state,
        available_boxes = get_available_boxes()
    }
end

--[[
等待网络就绪
@param max_tries: 最大等待次数（每次约1秒），默认120次
@return: 是否就绪
]]
local function wait_network_ready(max_tries)
    max_tries = max_tries or 120
    local tries = 0
    while not socket.adapter(socket.dft()) do
        tries = tries + 1
        if tries > max_tries then
            return false
        end
        log.warn("ecbusiness", "等待网络连接", socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end
    return true
end

--[[
柜子初始化任务（等待网络就绪后执行）
]]
local function locker_init_task()
    log.info("ecbusiness", "等待网络就绪后执行柜子初始化")
    if not wait_network_ready() then
        log.error("ecbusiness", "等待网络超时，柜子初始化失败")
        return
    end
    log.info("ecbusiness", "网络已就绪，开始柜子初始化")

    -- 发送柜子初始化请求（根据实际7路控制板配置）
    local box_info = {}
    for i = 1, 7 do
        -- 根据实际箱子类型配置，这里暂时默认全部为小箱子（类型0）
        -- 实际应用中可以根据控制板类型或配置文件来设置不同类型的箱子
        table.insert(box_info, {box = i, type = 0})
    end

    local success, result = server_api.init_locker(box_info)

    if success then
        log.info("ecbusiness", "柜子初始化成功")
        fskv.set("locker_initialized", "true") -- 记录初始化成功标志

        -- 初始化成功后立即获取小程序码图片
        log.info("ecbusiness", "开始获取小程序码图片")
        local err
        qr_code_image_data, err = server_api.generate_wechat_qr_code()
        if qr_code_image_data then
            log.info("ecbusiness", "小程序码图片获取成功")
        else
            log.error("ecbusiness", "小程序码图片获取失败: " .. (err or "未知错误"))
        end
    else
        log.error("ecbusiness", "柜子初始化失败: " .. (result or "未知错误"))
    end
end

--[[
初始化业务模块
]]
local function init()
    log.info("ecbusiness", "业务模块初始化")
    
    -- 初始化状态
    business_state = BUSINESS_STATUS.IDLE
    
    -- 检查是否已经成功初始化过
    local has_initialized = fskv.get("locker_initialized")
    if not has_initialized or has_initialized ~= "true" then
        log.info("ecbusiness", "第一次开机，等待网络就绪后执行柜子初始化")
        sys.taskInit(locker_init_task)
    else
        log.info("ecbusiness", "柜子已经成功初始化过")
    end
    
    log.info("ecbusiness", "业务模块初始化完成")
end

-- 自动初始化
init()

-- 获取小程序码图片
function ecbusiness.get_qr_code_image()
    return qr_code_image_data
end

-- 对外接口
return ecbusiness
