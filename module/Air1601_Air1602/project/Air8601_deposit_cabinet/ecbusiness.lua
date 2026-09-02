--[[
@module  ecbusiness
@summary 寄存柜业务逻辑模块
@version 1.0
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
local config = require "config"

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
服务器为唯一事实源，返回 value.boxes = [{box,type,status}]
status: 0=空闲 1=占用
@return: 箱子状态数组或nil
]]
-- 获取本地已占用柜号集合
--    从未上报服务器 → 服务器始终认为全部空闲 → 若不排除本地占用，刷脸存件会每次都选同一个柜子(柜1)。
-- 本地占用数据源：
--   1. aircloud.pickup_code_map（取件码 → 柜号，取件码存件后建立，取件/解绑时删除）
--   2. face_manager 的人脸绑定（fskv face_bind_{uid} → 柜号）
local function get_local_occupied_boxes()
    local occupied = {}
    local function mark(box_num)
        -- 类型保护：fskv 值可能是 number/string/table/boolean，仅处理可转为数字的
        local n = nil
        if type(box_num) == "number" then
            n = box_num
        elseif type(box_num) == "string" then
            n = tonumber(box_num)
        end
        if n then
            occupied[n] = true
        end
    end
    -- 取件码映射
    local aircloud = require "aircloud"
    for _, box_num in pairs(aircloud.pickup_code_map or {}) do
        mark(box_num)
    end
    -- 人脸绑定（fskv face_bind_*）
    local bind_prefix = "face_bind_"
    local iter = fskv.iter()
    local key = fskv.next(iter)
    while key do
        if string.sub(key, 1, #bind_prefix) == bind_prefix then
            mark(fskv.get(key))
        end
        key = fskv.next(iter)
    end
    return occupied
end

--[[
执行柜子初始化（同步版）
开机任务与"设备未初始化"(code 12) 自愈逻辑共用：
向服务器上报 7 路控制板柜子配置，成功后记录 fskv 标志。
@return: 是否成功, 错误信息
]]
local function do_locker_init()
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
        return true
    end

    log.error("ecbusiness", "柜子初始化失败: " .. tostring(result or "未知错误"))
    return false, result
end

local function get_available_boxes()
    log.info("ecbusiness", "获取可用箱子列表")

    local success, result, biz_code = server_api.get_locker_status()

    -- 自愈：服务器返回"设备未初始化"(code 12) 时（如服务器清库/换环境导致设备记录丢失），
    -- 自动重新调 /init 上报柜子配置后重试一次，无需人工删除 fskv 标志或重启设备。
    if not success and biz_code == 12 then
        log.warn("ecbusiness", "服务器提示设备未初始化，自动重新初始化")
        local init_ok, init_err = do_locker_init()
        if init_ok then
            log.info("ecbusiness", "自动重新初始化成功，重试获取柜子状态")
            success, result, biz_code = server_api.get_locker_status()
        else
            log.error("ecbusiness", "自动重新初始化失败: " .. tostring(init_err or "未知错误"))
        end
    end

    if not success then
        log.error("ecbusiness", "获取柜子状态失败")
        return nil, biz_code
    end

    -- 排除本地已占用柜子（刷脸存件未上报服务器的占用）
    local local_occupied = get_local_occupied_boxes()
    if next(local_occupied) then
        log.info("ecbusiness", "本地已占用柜子: " .. json.encode(local_occupied))
    end

    -- 统一转换为 {box_num, type, available} 数组
    local boxes = {}
    if result and result.boxes then
        for _, b in ipairs(result.boxes) do
            table.insert(boxes, {
                box_num = b.box,
                type = b.type or 0,
                available = (b.status == 0) and not local_occupied[b.box]
            })
        end
    end
    return boxes, biz_code
end

-- 轮询选柜：fskv 记录上次分配柜号
local LAST_ALLOCATED_BOX_KEY = "last_allocated_box"

--[[
按柜号升序在指定范围内找一个可用柜
@param available_boxes: get_available_boxes 返回的箱子数组
@param from_box: 起始柜号（含）
@param to_box: 结束柜号（含）
@return: 可用箱子或 nil
]]
local function find_available_in_range(available_boxes, from_box, to_box)
    if not available_boxes then
        return nil
    end
    -- 先按柜号升序排列，保证轮询按柜号顺序推进
    local sorted = {}
    for _, b in ipairs(available_boxes) do
        table.insert(sorted, b)
    end
    table.sort(sorted, function(a, b) return a.box_num < b.box_num end)
    for _, box in ipairs(sorted) do
        if box.available and box.box_num >= from_box and box.box_num <= to_box then
            return box
        end
    end
    return nil
end

--[[
安全的 tonumber：Lua 5.3 中 tonumber(nil) 会直接抛错（bad argument #1 to 'tonumber' (value expected)），
本函数对 number/string 正常转换，对 nil/table/boolean 返回默认值，避免崩溃。
@param v: 待转换值
@param default: 转换失败时的默认值
@return: 数字或默认值
]]
local function safe_tonumber(v, default)
    if type(v) == "number" then
        return v
    elseif type(v) == "string" then
        local n = tonumber(v)
        if n then
            return n
        end
    end
    return default
end

--[[
轮询均衡选柜（默认 1-5 轮询，可配置）
规则：
1. 记录上次分配柜号（fskv: last_allocated_box），下次从下一个柜号开始找；
2. 只在轮询范围（默认 1-5，config.locker.allocation 可配）内轮询，到末尾后回绕到起点；
3. 轮询范围内全部占用时，若允许回退（fallback_outside=true），
   则回退到范围外柜子（如 6-7），避免明明有空柜却提示"无可用箱子"。
@param available_boxes: get_available_boxes 返回的箱子数组
@return: 选中箱子或 nil
]]
local function select_box_round_robin(available_boxes)
    local cfg = config.locker.allocation or {}
    local start_box = safe_tonumber(cfg.round_robin_start, 1)
    local end_box = safe_tonumber(cfg.round_robin_end, config.locker.total_boxes)
    local fallback = cfg.fallback_outside ~= false

    -- 上次分配柜号，未分配过则从 start_box 开始
    -- 类型保护：fskv 值可能是 number/string/table/boolean，仅接受可转为数字的值
    local stored_last = fskv.get(LAST_ALLOCATED_BOX_KEY)
    local last_box = start_box - 1
    if type(stored_last) == "number" then
        last_box = stored_last
    elseif type(stored_last) == "string" then
        local n = tonumber(stored_last)
        if n then
            last_box = n
        end
    end

    -- 候选起点：上次柜号的下一个；超出范围回绕到起点
    local candidate = last_box + 1
    if candidate > end_box then
        candidate = start_box
    end

    -- 第一段：candidate .. end_box
    local selected = find_available_in_range(available_boxes, candidate, end_box)
    -- 第二段（回绕）：start_box .. candidate-1
    if not selected and candidate > start_box then
        selected = find_available_in_range(available_boxes, start_box, candidate - 1)
    end
    -- 回退：轮询范围内全部占用，尝试范围外柜子（6-7）
    if not selected and fallback and end_box < config.locker.total_boxes then
        selected = find_available_in_range(available_boxes, end_box + 1, config.locker.total_boxes)
    end

    if selected then
        fskv.set(LAST_ALLOCATED_BOX_KEY, selected.box_num)
        log.info("ecbusiness", "轮询选柜: 上次=" .. tostring(last_box) .. ", 本次=" .. selected.box_num)
    end
    return selected
end

--[[
统一选柜入口（deposit 与 face_deposit 共用）
按配置的分配策略选择柜子：round_robin=轮询均衡 / first_available=顺序取最小
@param available_boxes: get_available_boxes 返回的箱子数组
@return: 选中箱子或 nil
]]
local function select_available_box(available_boxes)
    local cfg = config.locker.allocation or {}
    if cfg.strategy == "round_robin" then
        return select_box_round_robin(available_boxes)
    end
    -- 默认策略：顺序取第一个可用（原逻辑）
    for _, box in ipairs(available_boxes) do
        if box.available then
            return box
        end
    end
    return nil
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
    local available_boxes, biz_code = get_available_boxes()
    if not available_boxes then
        business_state = BUSINESS_STATUS.IDLE
        if biz_code == 12 then
            return false, "设备未初始化，自动初始化失败，请检查网络后重试"
        end
        return false, "获取可用箱子失败"
    end
    
    -- 选择一个可用的箱子（轮询均衡选柜）
    local selected_box = select_available_box(available_boxes)

    if not selected_box then
        business_state = BUSINESS_STATUS.IDLE
        return false, "无可用箱子"
    end
    
    -- 发送存件请求到服务器
    local success, result = server_api.deposit_item(selected_box.box_num, user_info)
    
    if not success then
        business_state = BUSINESS_STATUS.IDLE
        return false, result or "存件请求失败"
    end
    
    -- 箱子编号和取件码
    local box_num = selected_box.box_num
    local pickup_code = result.pickup_code
    
    -- 发送打开箱子的命令
    log.info("ecbusiness", "发送打开箱子" .. box_num .. "的命令")
    sys.publish("OPEN_BOX", box_num)
    
    -- 等待开柜结果
    local open_ok, open_result = sys.waitUntil("BOX_OPEN_RESULT", 5000)
    
    if not open_ok or not open_result then
        business_state = BUSINESS_STATUS.IDLE
        return false, "开柜超时"
    end
    
    if not open_result.success then
        business_state = BUSINESS_STATUS.IDLE
        return false, "开柜失败: " .. (open_result.error or "未知错误")
    end
    
    -- 存件成功
    business_state = BUSINESS_STATUS.IDLE
    log.info("ecbusiness", "存件成功，箱子: " .. box_num .. ", 取件码: " .. pickup_code)
    
    return true, {
        box_num = box_num,
        pickup_code = pickup_code,
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
    local open_ok, open_result = sys.waitUntil("BOX_OPEN_RESULT", 5000)
    
    if not open_ok or not open_result then
        business_state = BUSINESS_STATUS.IDLE
        return false, "开柜超时"
    end
    
    if not open_result.success then
        business_state = BUSINESS_STATUS.IDLE
        return false, "开柜失败: " .. (open_result.error or "未知错误")
    end
    
    -- 发送取件完成请求到服务器
    local success, result = server_api.pickup_item(box_num, pickup_code)
    
    if not success then
        business_state = BUSINESS_STATUS.IDLE
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
柜子初始化任务（等待网络就绪后执行，开机一次性）
复用 do_locker_init 完成 /init 上报，成功后额外获取小程序码图片
]]
local function locker_init_task()
    log.info("ecbusiness", "等待网络就绪后执行柜子初始化")
    if not wait_network_ready() then
        log.error("ecbusiness", "等待网络超时，柜子初始化失败")
        return
    end
    log.info("ecbusiness", "网络已就绪，开始柜子初始化")

    local ok = do_locker_init()

    if ok then
        -- 初始化成功后立即获取小程序码图片
        log.info("ecbusiness", "开始获取小程序码图片")
        local err
        qr_code_image_data, err = server_api.generate_wechat_qr_code()
        if qr_code_image_data then
            log.info("ecbusiness", "小程序码图片获取成功")
        else
            log.error("ecbusiness", "小程序码图片获取失败: " .. (err or "未知错误"))
        end
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

--[[
人脸存件流程（刷脸注册 → 分配柜子 → 开柜 → 绑定）
@param user_id: 人脸用户ID（人脸模块注册返回）
@param user_name: 用户名称（可选）
@return: 操作结果
]]
function ecbusiness.face_deposit(user_id, user_name)
    log.info("ecbusiness", "开始人脸存件流程，user_id: " .. tostring(user_id))

    if business_state ~= BUSINESS_STATUS.IDLE then
        log.error("ecbusiness", "业务状态繁忙")
        return false, "业务状态繁忙"
    end

    business_state = BUSINESS_STATUS.DEPOSITING

    -- 获取可用箱子
    local available_boxes, biz_code = get_available_boxes()
    if not available_boxes then
        business_state = BUSINESS_STATUS.IDLE
        if biz_code == 12 then
            return false, "设备未初始化，自动初始化失败，请检查网络后重试"
        end
        return false, "获取可用箱子失败"
    end

    -- 选择一个可用的箱子（轮询均衡选柜）
    local selected_box = select_available_box(available_boxes)

    if not selected_box then
        business_state = BUSINESS_STATUS.IDLE
        return false, "无可用箱子"
    end

    -- 发送刷脸存件请求到服务器（优先走 /face_store，服务器生成取件码+存件码）
    local box_num = selected_box.box_num
    local pickup_code = nil
    local save_code = nil

    local fname = user_name or ("face_" .. tostring(user_id))
    local success, result, is_network_error = server_api.face_store(box_num, user_id, fname)

    if success and result then
        pickup_code = result.pickup_code
        save_code = result.save_code
        log.info("ecbusiness", "服务器刷脸存件登记成功，box=" .. box_num
                 .. ", pickup_code=" .. tostring(pickup_code)
                 .. ", save_code=" .. tostring(save_code)
                 .. ", record_id=" .. tostring(result.record_id))
    elseif is_network_error then
        -- ⚠️ 仅网络错误（断网/超时/服务器不可用）时降级本地：
        -- 本地生成备用取件码继续开柜（人脸本身是取件凭证，取件码只是备用）。
        pickup_code = tostring(100000 + math.random(0, 899999))
        log.warn("ecbusiness", "服务器刷脸存件登记网络错误(" .. tostring(result or "未知")
                 .. ")，使用本地取件码: " .. pickup_code)
    else
        -- 服务器明确拒绝（如 code 55 "该柜子已占用"）：终止流程并提示用户，
        -- 避免本地继续开柜造成本地与服务器状态不一致。
        business_state = BUSINESS_STATUS.IDLE
        log.error("ecbusiness", "服务器拒绝刷脸存件: " .. tostring(result or "未知错误"))
        return false, result or "服务器拒绝存件"
    end

    -- 保存人脸绑定（人脸user_id ↔ 柜号 ↔ 取件码）
    local face_manager = require "face_manager"
    face_manager.save_face_bind(user_id, box_num)
    if pickup_code then
        local aircloud = require "aircloud"
        aircloud.pickup_code_map[pickup_code] = box_num
        log.info("ecbusiness", "人脸存件取件码: " .. pickup_code .. " → 柜子" .. box_num)
    end

    -- 发送打开箱子的命令
    log.info("ecbusiness", "发送打开箱子" .. box_num .. "的命令")
    sys.publish("OPEN_BOX", box_num)

    -- 等待开柜结果
    local open_ok, open_result = sys.waitUntil("BOX_OPEN_RESULT", 5000)

    if not open_ok or not open_result then
        business_state = BUSINESS_STATUS.IDLE
        return false, "开柜超时"
    end

    if not open_result.success then
        business_state = BUSINESS_STATUS.IDLE
        return false, "开柜失败: " .. (open_result.error or "未知错误")
    end

    -- 存件成功
    business_state = BUSINESS_STATUS.IDLE
    log.info("ecbusiness", "人脸存件成功，箱子: " .. box_num .. ", 取件码: " .. tostring(pickup_code))

    return true, {
        box_num = box_num,
        pickup_code = pickup_code,
        save_code = save_code,
        user_id = user_id
    }
end

--[[
人脸取件流程（刷脸验证 → 查绑定柜号 → 开柜 → 解绑）
@param user_id: 人脸用户ID（人脸模块验证返回）
@return: 操作结果
]]
function ecbusiness.face_pickup(user_id)
    log.info("ecbusiness", "开始人脸取件流程，user_id: " .. tostring(user_id))

    if business_state ~= BUSINESS_STATUS.IDLE then
        log.error("ecbusiness", "业务状态繁忙")
        return false, "业务状态繁忙"
    end

    business_state = BUSINESS_STATUS.PICKING

    -- 通过人脸绑定获取柜号
    local face_manager = require "face_manager"
    local box_num = face_manager.get_box_by_user_id(user_id)

    if not box_num then
        business_state = BUSINESS_STATUS.IDLE
        return false, "未找到该用户绑定的柜子"
    end

    -- 发送打开箱子的命令
    log.info("ecbusiness", "发送打开箱子" .. box_num .. "的命令")
    sys.publish("OPEN_BOX", box_num)

    -- 等待开柜结果
    local open_ok, open_result = sys.waitUntil("BOX_OPEN_RESULT", 5000)

    if not open_ok or not open_result then
        business_state = BUSINESS_STATUS.IDLE
        return false, "开柜超时"
    end

    if not open_result.success then
        business_state = BUSINESS_STATUS.IDLE
        return false, "开柜失败: " .. (open_result.error or "未知错误")
    end

    -- 取件成功后删除绑定
    face_manager.delete_face_bind(user_id)

    -- 同步删除该柜号的备用取件码（否则本地占用集合仍视为占用）
    local aircloud = require "aircloud"
    aircloud.delete_pickup_code_by_box(box_num)

    -- 通知服务器释放格子（刷脸取件方式 /carry，失败不阻塞业务，靠下次对账兜底）
    pcall(function()
        local server_api = require "server_api"
        server_api.face_pickup_item(box_num, user_id)
    end)

    -- 取件成功
    business_state = BUSINESS_STATUS.IDLE
    log.info("ecbusiness", "人脸取件成功，箱子: " .. box_num)

    return true, {
        box_num = box_num,
        user_id = user_id
    }
end

-- 获取小程序码图片
function ecbusiness.get_qr_code_image()
    return qr_code_image_data
end

-- 重置业务状态为空闲（界面退出/异常时调用，防止后台任务残留导致下次"业务状态繁忙"）
function ecbusiness.reset_business_state()
    business_state = BUSINESS_STATUS.IDLE
end

-- 是否正在业务操作中（存/取/刷脸存/刷脸取）
function ecbusiness.is_busy()
    return business_state ~= BUSINESS_STATUS.IDLE
end

-- 对外接口
return ecbusiness
