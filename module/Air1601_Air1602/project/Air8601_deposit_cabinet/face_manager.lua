--[[
@module  face_manager
@summary 人脸识别管理模块（AirCAMERA_1034 + exfacecam）
@version 1.0
@date    2026.08.14
@author  王城钧
@usage
本模块封装人脸识别摄像头（AirCAMERA_1034）的核心操作：
- 初始化 exfacecam（UART2 人脸模组 115200/8N1，仅UART通信，不初始化USB摄像头）
- 人脸注册（录入人脸）
- 人脸验证（刷脸识别）
- 用户管理（列表/删除）
- 人脸 ↔ 柜号绑定存储（fskv 持久化）

通过消息机制与界面解耦：
  订阅：FACE_REGISTER_REQ / FACE_VERIFY_REQ / FACE_LIST_REQ / FACE_DELETE_REQ
  发布：FACE_INIT_RESULT / FACE_REGISTER_RESULT / FACE_VERIFY_RESULT /
        FACE_LIST_RESULT / FACE_DELETE_RESULT / FACE_STATE_UPDATE
]]

local face_manager = {}

local exfacecam = require "exfacecam"
local config = require "config"

-- 人脸模块状态定义
local FACE_STATUS = {
    UNINIT = 0,   -- 未初始化
    INITING = 1,  -- 初始化中
    READY = 2,    -- 就绪
    BUSY = 3,     -- 忙（注册/验证中）
    ERROR = 4     -- 错误
}

-- 全局状态
local face_state = FACE_STATUS.UNINIT
local face_ready = false
local init_retry_count = 0      -- 初始化重试计数
local MAX_INIT_RETRY = 3        -- 最大重试次数
local init_watchdog = nil       -- 初始化看门狗定时器（防止 camera.init 卡住导致窗口无限等待）

-- 人脸绑定键前缀（与 config.face.bind_prefix 一致）
local bind_prefix = config.get("face.bind_prefix", "face_bind_")

--[[
人脸 ↔ 柜号绑定存储（fskv 持久化）
key: face_bind_{user_id} → value: box_num
]]

-- 保存人脸绑定
function face_manager.save_face_bind(user_id, box_num)
    if not user_id or not box_num then
        log.error("face_manager", "保存人脸绑定失败：参数不完整", user_id, box_num)
        return false
    end
    local key = bind_prefix .. tostring(user_id)
    fskv.set(key, tostring(box_num))
    log.info("face_manager", "保存人脸绑定: user_id=" .. tostring(user_id) .. " → 柜子" .. tostring(box_num))
    return true
end

-- 根据人脸用户ID获取绑定柜号
function face_manager.get_box_by_user_id(user_id)
    if not user_id then
        return nil
    end
    local key = bind_prefix .. tostring(user_id)
    local stored = fskv.get(key)
    -- 类型保护：fskv 值可能是 number/string/table/boolean，仅接受可转为数字的
    if type(stored) == "number" then
        return stored
    elseif type(stored) == "string" then
        return tonumber(stored)
    end
    return nil
end

-- 删除人脸绑定
function face_manager.delete_face_bind(user_id)
    if not user_id then
        return false
    end
    local key = bind_prefix .. tostring(user_id)
    fskv.del(key)
    log.info("face_manager", "删除人脸绑定: user_id=" .. tostring(user_id))
    return true
end

-- 获取人脸模块状态
function face_manager.get_status()
    return {
        state = face_state,
        ready = face_ready
    }
end

--[[
初始化人脸模块（exfacecam.open）
- GPIO73 UVC 使能已在 hardware.power_on 中处理
- USB摄像头 + UART2 人脸模组（115200/8N1）
]]
local function face_init_task()
    log.info("face_manager", "人脸模块初始化任务开始")
    if face_ready then
        sys.publish("FACE_INIT_RESULT", {success = true})
        return
    end

    -- 启动初始化看门狗：8 秒内未完成则判定失败（防止 camera.init 卡死导致 UI 无限等待）
    if init_watchdog then
        sys.timerStop(init_watchdog)
        init_watchdog = nil
    end
    init_watchdog = sys.timerStart(function()
        init_watchdog = nil
        if not face_ready then
            face_state = FACE_STATUS.ERROR
            log.error("face_manager", "人脸模块初始化超时（8秒），请检查摄像头连接")
            sys.publish("FACE_INIT_RESULT", {success = false, error = "人脸模块初始化超时，请检查摄像头连接"})
        end
    end, 8000)

    -- 等待摄像头供电稳定（与官方 face_demo.lua 一致，给 AirCAMERA_1034 充分上电时间）
    sys.wait(1000)
    log.info("face_manager", "供电稳定等待完成，开始调用 exfacecam.open")

    log.info("face_manager", "调用 exfacecam.open: face_uart=" .. tostring(config.get("face.uartid", 2)) .. "（仅UART通信，不初始化USB摄像头）")

    local ok, open_ok = pcall(function()
        -- 原因：camera.init() 后 USB 摄像头处于就绪态，register/verify 时人脸模组启动工作，
        --       摄像头开始输出 UVC 视频流，叠加 LCD/4G/触摸/485 后系统资源超载
        --       → 设备崩溃重启（日志：register/verify 后 175ms trace lost → bootloader）。
        -- AirCAMERA_1034 人脸识别算法在模组内部（UART 通信），UVC 摄像头仅用于屏幕预览（可选），
        -- 禁用后不影响刷脸注册/验证功能。
        return exfacecam.open({
            face_uart = config.get("face.uartid", 2),               -- 人脸模组串口 uart2（115200/8N1）
            face_rst = nil,                                         -- 无复位引脚
        })
    end)
    log.info("face_manager", "exfacecam.open 返回: pcall_ok=" .. tostring(ok) .. ", open_ok=" .. tostring(open_ok))

    if not ok then
        -- pcall 异常：可能是资源竞争，延迟后重试
        if init_watchdog then sys.timerStop(init_watchdog) init_watchdog = nil end
        init_retry_count = init_retry_count + 1
        if init_retry_count < MAX_INIT_RETRY then
            face_state = FACE_STATUS.INITING
            log.warn("face_manager", "人脸模块初始化异常，第 " .. init_retry_count .. " 次重试:", open_ok)
            sys.timerStart(function()
                sys.taskInit(face_init_task)
            end, 2000)
            return
        end
        if init_watchdog then sys.timerStop(init_watchdog) init_watchdog = nil end
        face_state = FACE_STATUS.ERROR
        log.error("face_manager", "人脸模块初始化异常（已重试 " .. MAX_INIT_RETRY .. " 次）", open_ok)
        sys.publish("FACE_INIT_RESULT", {success = false, error = tostring(open_ok)})
        return
    end

    if not open_ok then
        -- open 失败：可能摄像头/USB 未就绪，延迟后重试
        if init_watchdog then sys.timerStop(init_watchdog) init_watchdog = nil end
        init_retry_count = init_retry_count + 1
        if init_retry_count < MAX_INIT_RETRY then
            face_state = FACE_STATUS.INITING
            log.warn("face_manager", "人脸模块打开失败，第 " .. init_retry_count .. " 次重试")
            sys.timerStart(function()
                sys.taskInit(face_init_task)
            end, 2000)
            return
        end
        if init_watchdog then sys.timerStop(init_watchdog) init_watchdog = nil end
        face_state = FACE_STATUS.ERROR
        log.error("face_manager", "人脸模块打开失败（已重试 " .. MAX_INIT_RETRY .. " 次）")
        sys.publish("FACE_INIT_RESULT", {success = false, error = "人脸模块打开失败"})
        return
    end

    init_retry_count = 0
    if init_watchdog then
        sys.timerStop(init_watchdog)
        init_watchdog = nil
    end
    face_state = FACE_STATUS.READY
    face_ready = true
    log.info("face_manager", "人脸模块初始化成功")
    sys.publish("FACE_INIT_RESULT", {success = true})
end

-- 人脸状态回调（用于界面提示）
-- state: 0=正常, 1=无人脸, 2=偏上, 3=偏下, 4=偏左, 5=偏右,
--        6=太远, 7=太近, 8=眉毛遮挡, 9=眼睛遮挡, 10=面部遮挡, 11=角度异常
local last_state_time = 0  -- 上次发布人脸状态的时间戳(ms)，用于限流
local function face_state_cb(state)
    -- 限流：每 500ms 最多发布一次，避免 on_state 高频回调（约15fps）导致 UI 频繁刷新、系统负载过高
    local now = mcu.ticks()
    if now - last_state_time < 500 then
        return
    end
    last_state_time = now

    local state_text = {
        [0] = "请正对摄像头",
        [1] = "未检测到人脸",
        [2] = "请抬头",
        [3] = "请低头",
        [4] = "请向右转",
        [5] = "请向左转",
        [6] = "请靠近一些",
        [7] = "请远离一些",
        [8] = "眉毛被遮挡",
        [9] = "眼睛被遮挡",
        [10] = "面部被遮挡",
        [11] = "角度异常",
    }
    local msg = state_text[state] or "请正对摄像头"
    sys.publish("FACE_STATE_UPDATE", {state = state, message = msg})
end

--[[
人脸注册任务（阻塞调用，需独立 task）
register 返回: ok, user_id（成功时 user_id 为数字；失败时返回错误码）
]]
local function face_register_task(params)
    params = params or {}

    if not face_ready then
        sys.publish("FACE_REGISTER_RESULT", {success = false, error = "人脸模块未初始化"})
        return
    end

    face_state = FACE_STATUS.BUSY
    log.info("face_manager", "开始人脸注册，name=" .. tostring(params.name) .. "，将阻塞等待模组录入结果")

    -- verify 可能匹配到旧模板（无绑定柜号），导致取件时"识别到旧人脸/绑定柜子=nil"无法开柜。
    -- 复位(MID_RESET)后模组需重新上线，DELALL 可能因模组未就绪而超时，故重试数次。
    local clear_ok = false
    for i = 1, 3 do
        local clr_ok, clr_result = pcall(function()
            return exfacecam.clear()
        end)
        if clr_ok and clr_result then
            clear_ok = true
            log.info("face_manager", "注册前已清空旧人脸模板（第" .. i .. "次成功）")
            break
        end
        log.warn("face_manager", "注册前清空旧人脸模板第 " .. i .. " 次失败，1秒后重试", clr_result)
        sys.wait(1000)
    end
    if not clear_ok then
        log.warn("face_manager", "注册前清空旧人脸模板最终失败，继续注册（可能仍匹配旧人脸）")
    end

    local ok, reg_ok, reg_data = pcall(function()
        -- 与 LCD/4G/485 等业务叠加后导致系统崩溃重启（face_demo 单跑不崩，因为其回调仅 log）。
        return exfacecam.register({
            name = params.name or "user",
            admin = params.admin or false,
            timeout = params.timeout or config.get("face.register_timeout", 15),
        })
    end)
    log.info("face_manager", "exfacecam.register 返回: pcall_ok=" .. tostring(ok)
             .. ", reg_ok=" .. tostring(reg_ok) .. ", reg_data=" .. tostring(reg_data))

    if not ok then
        face_state = FACE_STATUS.READY
        log.error("face_manager", "人脸注册异常", reg_data)
        sys.publish("FACE_REGISTER_RESULT", {success = false, error = tostring(reg_data)})
        return
    end

    face_state = FACE_STATUS.READY

    if reg_ok then
        -- 注册成功，reg_data 为 user_id（数字）
        log.info("face_manager", "人脸注册成功，user_id=" .. tostring(reg_data))
        sys.publish("FACE_REGISTER_RESULT", {
            success = true,
            user_id = reg_data,
            name = params.name or "user",
        })
    else
        -- 注册失败，reg_data 为错误码
        local err_msg = "注册失败，错误码: " .. tostring(reg_data)
        log.warn("face_manager", err_msg)
        sys.publish("FACE_REGISTER_RESULT", {success = false, error = err_msg})
    end
end

--[[
人脸验证任务（阻塞调用，需独立 task）
verify 返回: ok, {user_id, name, admin, unlock_status}
]]
local function face_verify_task(params)
    params = params or {}

    if not face_ready then
        sys.publish("FACE_VERIFY_RESULT", {success = false, error = "人脸模块未初始化"})
        return
    end

    face_state = FACE_STATUS.BUSY
    log.info("face_manager", "开始人脸验证，将阻塞等待模组识别结果")

    local ok, ver_ok, ver_data = pcall(function()
        return exfacecam.verify({
            timeout = params.timeout or config.get("face.verify_timeout", 15),
        })
    end)
    log.info("face_manager", "exfacecam.verify 返回: pcall_ok=" .. tostring(ok)
             .. ", ver_ok=" .. tostring(ver_ok) .. ", ver_data=" .. tostring(ver_data))

    if not ok then
        face_state = FACE_STATUS.READY
        log.error("face_manager", "人脸验证异常", ver_data)
        sys.publish("FACE_VERIFY_RESULT", {success = false, error = tostring(ver_data)})
        return
    end

    face_state = FACE_STATUS.READY

    if ver_ok and ver_data and ver_data.user_id then
        -- 验证成功，ver_data 为 {user_id, name, admin, unlock_status}
        local user_id = ver_data.user_id
        local box_num = face_manager.get_box_by_user_id(user_id)
        log.info("face_manager", "人脸验证成功，user_id=" .. tostring(user_id)
                 .. ", name=" .. tostring(ver_data.name)
                 .. ", 绑定柜子=" .. tostring(box_num))
        sys.publish("FACE_VERIFY_RESULT", {
            success = true,
            user_id = user_id,
            name = ver_data.name,
            admin = ver_data.admin,
            unlock_status = ver_data.unlock_status,
            box_num = box_num,
        })
    else
        -- 验证失败，ver_data 为错误码
        local err_msg = "验证失败，错误码: " .. tostring(ver_data)
        log.warn("face_manager", err_msg)
        sys.publish("FACE_VERIFY_RESULT", {success = false, error = err_msg})
    end
end

--[[
用户列表任务
list 返回: ok, count, ids（用户ID数组）
]]
local function face_list_task()
    if not face_ready then
        sys.publish("FACE_LIST_RESULT", {success = false, error = "人脸模块未初始化"})
        return
    end

    face_state = FACE_STATUS.BUSY
    log.info("face_manager", "获取人脸用户列表")

    local ok, list_ok, count, ids = pcall(function()
        return exfacecam.list()
    end)

    face_state = FACE_STATUS.READY

    if not ok then
        sys.publish("FACE_LIST_RESULT", {success = false, error = tostring(count)})
        return
    end

    if not list_ok then
        sys.publish("FACE_LIST_RESULT", {success = false, error = "查询失败，错误码: " .. tostring(count)})
        return
    end

    -- 补充查询每个用户的名称与绑定柜号
    local users = {}
    if ids then
        for i, uid in ipairs(ids) do
            local q_ok, q_info = pcall(function()
                return exfacecam.query(uid)
            end)
            local name = ""
            if q_ok and q_info then
                name = (type(q_info) == "table") and (q_info.name or "") or ""
            end
            table.insert(users, {
                user_id = uid,
                name = name,
                box_num = face_manager.get_box_by_user_id(uid),
            })
        end
    end

    sys.publish("FACE_LIST_RESULT", {success = true, users = users})
end

--[[
删除用户任务
]]
local function face_delete_task(params)
    params = params or {}

    if not face_ready then
        sys.publish("FACE_DELETE_RESULT", {success = false, error = "人脸模块未初始化"})
        return
    end

    local user_id = params.user_id
    if not user_id then
        sys.publish("FACE_DELETE_RESULT", {success = false, error = "缺少 user_id"})
        return
    end

    face_state = FACE_STATUS.BUSY
    log.info("face_manager", "删除人脸用户", user_id)

    local ok, del_ok = pcall(function()
        return exfacecam.delete(user_id)
    end)

    face_state = FACE_STATUS.READY

    if not ok then
        sys.publish("FACE_DELETE_RESULT", {success = false, error = tostring(del_ok)})
        return
    end

    if not del_ok then
        sys.publish("FACE_DELETE_RESULT", {success = false, error = "删除失败"})
        return
    end

    -- 同步删除绑定记录
    face_manager.delete_face_bind(user_id)

    log.info("face_manager", "删除人脸用户成功", user_id)
    sys.publish("FACE_DELETE_RESULT", {success = true, user_id = user_id})
end

-- 消息订阅
sys.subscribe("FACE_REGISTER_REQ", function(data)
    sys.taskInit(face_register_task, data)
end)
sys.subscribe("FACE_VERIFY_REQ", function(data)
    sys.taskInit(face_verify_task, data)
end)
sys.subscribe("FACE_LIST_REQ", function()
    sys.taskInit(face_list_task)
end)
sys.subscribe("FACE_DELETE_REQ", function(data)
    sys.taskInit(face_delete_task, data)
end)

-- 模块初始化（由 main.lua 在硬件初始化完成后显式调用）
-- 若 face_init_task 与 system_init 并发执行，exfacecam.open 内部的 camera.init
-- 会与 hardware.init 内部的 lcd.init 竞争内存/系统资源，导致 LCD 初始化失败、屏幕不亮。
function face_manager.init()
    log.info("face_manager", "人脸识别模块初始化")
    sys.taskInit(face_init_task)
end

-- 复位人脸模组（在摄像头预览停止后调用，让模组传感器从UVC模式回到人脸采集模式，
-- 否则 register(录入新脸) 会因传感器切不回去而超时，而 verify 不受影响）
function face_manager.reset_module()
    log.info("face_manager", "复位人脸模组")
    local ok, err = pcall(function()
        local exfacecam = require "exfacecam"
        return exfacecam.reset()
    end)
    if not ok then
        log.warn("face_manager", "人脸模组复位异常:", err)
    end
    -- 等待模组复位完成
    sys.wait(500)
end

-- 对外接口
return face_manager
