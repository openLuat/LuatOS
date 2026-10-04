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
local init_watchdog = nil       -- 初始化看门狗定时器

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

-- 人脸模块是否正在忙（注册/验证中）
-- 用途：FOTA 等后台任务做空闲门禁（业务空闲才允许下载/重启）
function face_manager.is_busy()
    return face_state == FACE_STATUS.BUSY
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

    -- 启动初始化看门狗：8 秒内未完成则判定失败
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

    -- 等待摄像头供电稳定 1000ms
    sys.wait(1000)
    log.info("face_manager", "供电稳定等待完成，开始调用 exfacecam.open")

    log.info("face_manager", "调用 exfacecam.open: face_uart=" .. tostring(config.get("face.uartid", 2)) .. "（仅UART通信，不初始化USB摄像头）")

    local ok, open_ok = pcall(function()
        -- 仅使用 UART 与人脸模组通信，不初始化 USB 摄像头（UVC 预览由 face_preview 管理）
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
    -- 限流：每 500ms 最多发布一次（模组 on_state 约 15fps 回调）
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

-- 清理模组上的残留人脸模板（注册前调用）
-- 做法：拉取模组模板列表，只删除 fskv 中已无 face_bind_* 绑定的 user_id
--       （即已取件/已解绑的残留模板），保留仍在寄存用户的模板。
-- 不使用 exfacecam.clear()：该接口会删除全部模板，包含其他在用用户的。
-- @return boolean true=清理流程完成（可继续注册）；false=列表获取失败（可能有残留模板）
local function cleanup_unbound_templates()
    -- ★ 注意返回值个数：exfacecam.list() 返回 (ok, count, ids) 三个值，
    --   用 pcall 包后是 4 个返回值（pok, list_ok, count, ids）。
    --   少接一个会让我这里的 ids 变成 count（number）→ #ids 抛
    --   "attempt to get length of a number value" → Lua VM exit → 设备重启。
    local pok, list_ok, count, ids = pcall(function()
        return exfacecam.list()
    end)
    if not pok or not list_ok then
        log.warn("face_manager", "注册前获取人脸模板列表失败，跳过旧模板清理")
        return false
    end

    count = tonumber(count) or 0
    if type(ids) ~= "table" then
        log.warn("face_manager", "注册前获取人脸模板列表返回异常(ids 类型 " .. type(ids) .. ")，跳过旧模板清理")
        return false
    end

    local removed, kept, failed = 0, 0, 0
    for i = 1, #ids do
        local uid = ids[i]
        if face_manager.get_box_by_user_id(uid) then
            -- 该 user_id 仍有柜号绑定（用户在寄存中）→ 保留模板
            kept = kept + 1
        else
            local dok, dres = pcall(function()
                return exfacecam.delete(uid)
            end)
            if dok and dres then
                removed = removed + 1
            else
                failed = failed + 1
                log.warn("face_manager", "删除已解绑旧模板失败 user_id=" .. tostring(uid))
            end
        end
    end
    log.info("face_manager", "注册前旧模板清理完成：模组共 " .. tostring(count)
             .. " 个，保留在寄存 " .. kept .. " 个，删除已解绑 " .. removed
             .. " 个，删除失败 " .. failed .. " 个")
    return true
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

    -- ★ 互斥：exfacecam 内部是单例状态（reply_map / note_cb 共享），
    --   并发执行 register/verify 会互相抢回包，表现为一方莫名超时或结果串到别的流程。
    --   因此忙时直接拒绝并回失败结果，界面提示稍后重试即可（只置 BUSY 而不阻止并发没有意义）。
    if face_state == FACE_STATUS.BUSY then
        log.warn("face_manager", "人脸模块正忙，拒绝本次注册请求")
        sys.publish("FACE_REGISTER_RESULT", {success = false, error = "人脸模块正忙，请稍后重试"})
        return
    end

    face_state = FACE_STATUS.BUSY
    log.info("face_manager", "开始人脸注册，name=" .. tostring(params.name) .. "，将阻塞等待模组录入结果")

    -- verify 可能匹配到旧模板（无绑定柜号），导致取件时"识别到旧人脸/绑定柜子=nil"无法开柜
    -- 注意：这里只删"已解绑"的旧模板，不清空全部模板（多人共用寄存柜）；
    --   模组刚复位时可能未就绪，故重试数次。
    local cleanup_ok = false
    for i = 1, 3 do
        cleanup_ok = cleanup_unbound_templates()
        if cleanup_ok then
            break
        end
        log.warn("face_manager", "注册前旧模板清理第 " .. i .. " 次失败，1秒后重试")
        sys.wait(1000)
    end
    if not cleanup_ok then
        log.warn("face_manager", "注册前旧模板清理最终失败，继续注册（可能仍匹配到旧人脸）")
    end

    -- 人脸状态回传（"请正对摄像头/请抬头"等界面引导，界面订阅 FACE_STATE_UPDATE）
    -- 传入 on_state 回调，把模组状态通过 FACE_STATE_UPDATE 发布给界面
    -- face_state_cb 内部有 500ms 限流
    --   config.face.state_callback = false 可一键关闭状态回传
    local state_cb = config.get("face.state_callback", true) and face_state_cb or nil

    local ok, reg_ok, reg_data = pcall(function()
        -- 与 LCD/4G/485 等业务叠加后导致系统崩溃重启（face_demo 单跑不崩，因为其回调仅 log）。
        return exfacecam.register({
            name = params.name or "user",
            admin = params.admin or false,
            timeout = params.timeout or config.get("face.register_timeout", 15),
            on_state = state_cb,
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

    -- 互斥：同注册，避免并发抢占模组回包
    if face_state == FACE_STATUS.BUSY then
        log.warn("face_manager", "人脸模块正忙，拒绝本次验证请求")
        sys.publish("FACE_VERIFY_RESULT", {success = false, error = "人脸模块正忙，请稍后重试"})
        return
    end

    face_state = FACE_STATUS.BUSY
    log.info("face_manager", "开始人脸验证，将阻塞等待模组识别结果")

    local ok, ver_ok, ver_data = pcall(function()
        return exfacecam.verify({
            timeout = params.timeout or config.get("face.verify_timeout", 15),
            -- 同注册：回传人脸状态供界面提示（可用 config.face.state_callback 关闭）
            on_state = config.get("face.state_callback", true) and face_state_cb or nil,
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

-- 任务安全启动（兜底未捕获异常）
-- 注意：Lua 里任何未捕获异常都会让 LuatOS 打印 "Lua VM exit!! reboot in 15000ms" 并整机重启，
--   寄存柜是无人值守设备，不能因一次类型错误重启。
--   这里统一包一层 pcall：异常时复位 face_state 并对外发布失败结果，界面不会一直卡在"处理中"。
-- @param result_topic 失败时要发布的主题（nil 表示只记日志）
-- @param fn 任务函数
local function start_task_safe(result_topic, fn, arg1)
    sys.taskInit(function()
        local ok, err = pcall(fn, arg1)
        if not ok then
            log.error("face_manager", "任务" .. tostring(result_topic) .. "异常:", tostring(err))
            face_state = FACE_STATUS.READY   -- 复位状态
            if result_topic then
                sys.publish(result_topic, {success = false, error = "内部异常: " .. tostring(err)})
            end
        end
    end)
end

-- 消息订阅
sys.subscribe("FACE_REGISTER_REQ", function(data)
    start_task_safe("FACE_REGISTER_RESULT", face_register_task, data)
end)
sys.subscribe("FACE_VERIFY_REQ", function(data)
    start_task_safe("FACE_VERIFY_RESULT", face_verify_task, data)
end)
sys.subscribe("FACE_LIST_REQ", function()
    start_task_safe("FACE_LIST_RESULT", face_list_task)
end)
sys.subscribe("FACE_DELETE_REQ", function(data)
    start_task_safe("FACE_DELETE_RESULT", face_delete_task, data)
end)

-- 模块初始化（由 main.lua 在硬件初始化完成后显式调用）
-- 须在 hardware.init 完成后调用（camera.init 与 display.init 并发会竞争内存/系统资源，
-- 可能导致 LCD 初始化失败、屏幕不亮）
function face_manager.init()
    log.info("face_manager", "人脸识别模块初始化")
    sys.taskInit(face_init_task)
end

-- 复位人脸模组（在摄像头预览停止后调用，让模组传感器从 UVC 模式回到人脸采集模式；
-- register 录入依赖该状态，verify 不受影响）
-- @param skip_wait boolean 可选：true=不等待复位完成（串行降级重试等场景由调用方自行控制时序）
function face_manager.reset_module(skip_wait)
    log.info("face_manager", "复位人脸模组" .. (skip_wait and "（跳过等待）" or ""))
    local ok, err = pcall(function()
        local exfacecam = require "exfacecam"
        return exfacecam.reset()
    end)
    if not ok then
        log.warn("face_manager", "人脸模组复位异常:", err)
    end
    if skip_wait then
        return
    end
    -- 等待模组复位完成
    sys.wait(500)
end

-- 对外接口
return face_manager
