--[[
@module  face_app
@summary 人脸识别业务层（AirCAMERA_1034 人脸模组，UART2 115200 8N1）
@version 1.0
@date    2026.10.21
@author  江访
@usage
本模块封装人脸录入 / 验证的完整链路，与 UI 通过消息解耦：

  订阅: FACE_REGISTER_REQ   → {name?, admin?, timeout?}   人脸录入
        FACE_VERIFY_REQ     → {timeout?, reset?}          人脸验证（reset=true 时先复位模组）
        FACE_CLEAR_REQ      → 清空模组内全部已录入用户
        FACE_STATUS_REQ     → 查询模组状态（未就绪时顺带重新初始化）
  发布: FACE_STATUS_UPDATE  → {state, ready, text, message?}
        FACE_STATE_UPDATE   → {state, message}            引导语（偏头/遮挡…）
        FACE_REGISTER_RESULT → {success, user_id?, name?, error?}
        FACE_VERIFY_RESULT   → {success, user_id?, name?, admin?, unlock_status?, error?}
        FACE_CLEAR_RESULT    → {success, error?}

硬件（Air8601）：
  - 人脸模组走 UART2，115200/8N1，无复位脚（face_rst = nil）
  - GPIO73 UVC_EN 已在 config.power_on 中拉高，这里只需等供电稳定
  - 只走 UART 通信，不初始化 USB 摄像头（不做 UVC 预览，规避停流/复位链路）
]]

local exfacecam = require "exfacecam"

local TAG = "face_app"
local FACE_UART = 2          -- 人脸模组串口（Air8601：UART2）
local MAX_INIT_RETRY = 3     -- 初始化最大尝试次数
local INIT_RETRY_DELAY = 2000
local BOOT_WAIT = 2000       -- 上电后等待模组稳定的时间（与 face_demo 一致）
local RESET_WAIT = 1000      -- 录入前复位模组后的等待时间
local ENROLL_TIMEOUT = 15    -- 录入超时（秒）
local VERIFY_TIMEOUT = 15    -- 验证超时（秒）

-- ==================== 模组状态 ====================
local ST = { UNINIT = 0, INITING = 1, READY = 2, BUSY = 3, ERROR = 4 }

local STATE_LABEL = {
    [ST.UNINIT]  = "未初始化",
    [ST.INITING] = "正在初始化...",
    [ST.READY]   = "就绪",
    [ST.BUSY]    = "人脸处理中...",
    [ST.ERROR]   = "初始化失败",
}

local face_state = ST.UNINIT
local face_ready = false
local init_running = false
local last_state_ms = 0      -- 上次向 UI 发布引导语的时间戳（限流用）

local function publish_status(extra)
    local data = {
        state = face_state,
        ready = face_ready,
        text = STATE_LABEL[face_state] or "未知状态",
    }
    if extra then
        for k, v in pairs(extra) do data[k] = v end
    end
    sys.publish("FACE_STATUS_UPDATE", data)
end

-- ==================== 错误码文案 ====================
local ERR_TEXT = {
    [exfacecam.MR_REJECTED]             = "操作被拒绝",
    [exfacecam.MR_ABORTED]              = "操作被中止",
    [exfacecam.MR_FAILED4_CAMERA]       = "摄像头未就绪",
    [exfacecam.MR_FAILED4_UNKNOWNREASON] = "模组返回未知错误",
    [exfacecam.MR_FAILED4_INVALIDPARAM] = "参数无效",
    [exfacecam.MR_FAILED4_NOMEMORY]     = "模组存储空间不足",
    [exfacecam.MR_FAILED4_UNKNOWNUSER]  = "用户不存在",
    [exfacecam.MR_FAILED4_MAXUSER]      = "用户数量已达上限",
    [exfacecam.MR_FAILED4_FACEENROLLED] = "该人脸已录入",
    [exfacecam.MR_FAILED4_LIVENESSCHECK] = "活体检测未通过",
    [exfacecam.MR_FAILED4_TIMEOUT]      = "操作超时",
    [exfacecam.MR_FAILED4_AUTHORIZATION] = "授权失败",
}

local function err_text(code)
    if code == nil then return "操作失败" end
    if type(code) ~= "number" then return tostring(code) end
    return ERR_TEXT[code] or ("操作失败（错误码 " .. tostring(code) .. "）")
end

-- ==================== 人脸状态引导语 ====================
-- state: 0=正常 1=无人脸 2=偏上 3=偏下 4=偏左 5=偏右 6=太远 7=太近
--        8=眉毛遮挡 9=眼睛遮挡 10=面部遮挡 11=角度异常
local STATE_TEXT = {
    [0]  = "请正对摄像头",
    [1]  = "未检测到人脸",
    [2]  = "请抬头",
    [3]  = "请低头",
    [4]  = "请向右转",
    [5]  = "请向左转",
    [6]  = "请靠近一些",
    [7]  = "请远离一些",
    [8]  = "眉毛被遮挡",
    [9]  = "眼睛被遮挡",
    [10] = "面部被遮挡",
    [11] = "角度异常",
}

-- 调试日志用的状态名（与 face_demo.lua 保持一致）
local STATE_NAME = {
    [0]  = "正常",
    [1]  = "无人脸",
    [2]  = "偏上",
    [3]  = "偏下",
    [4]  = "偏左",
    [5]  = "偏右",
    [6]  = "太远",
    [7]  = "太近",
    [8]  = "眉毛遮挡",
    [9]  = "眼睛遮挡",
    [10] = "面部遮挡",
    [11] = "角度异常",
}

local last_log_ms = 0         -- 上次打印人脸状态日志的时间戳（限流用）
local last_logged_state = -1  -- 上次打印的人脸状态（状态变化立即打印）

--[[模组 on_state 约 15fps 回调
调试日志：状态变化立即打印，同状态最多 1s 一次
界面发布：限流 500ms 一次，避免刷屏拖慢 UI]]
local function face_state_cb(state, left, top, right, bottom, yaw, pitch, roll)
    local now = mcu.ticks()

    if state ~= last_logged_state or (now - last_log_ms) >= 1000 then
        last_logged_state = state
        last_log_ms = now
        log.info(TAG, string.format(
            "人脸状态[%s] 框(%d,%d,%d,%d) yaw=%d pitch=%d roll=%d",
            STATE_NAME[state] or ("未知" .. tostring(state)),
            tonumber(left) or -1, tonumber(top) or -1,
            tonumber(right) or -1, tonumber(bottom) or -1,
            tonumber(yaw) or 0, tonumber(pitch) or 0, tonumber(roll) or 0))
    end

    if now - last_state_ms < 500 then return end
    last_state_ms = now
    sys.publish("FACE_STATE_UPDATE", {
        state = state,
        message = STATE_TEXT[state] or "请正对摄像头",
    })
end

-- ==================== 初始化 ====================
--[[打开人脸模组

exfacecam.open 末尾有一句 `if param.id == camera.USB then`：
整机若没有编入 camera 库，全局 camera 为 nil，这里会抛异常，
而那时 UART 已经 setup 完成、模组其实已在线。为了让返回值可信，
调用前补一个占位 camera —— param.id 为 nil，永远不等，不会触发摄像头初始化。]]
local function open_face_module()
    local cam_missing = (_G.camera == nil)
    if cam_missing then _G.camera = { USB = -1 } end
    local t0 = mcu.ticks()
    local ok, open_ok = pcall(exfacecam.open, {
        face_uart = FACE_UART,   -- 人脸模组串口（115200/8N1）
        face_rst = nil,          -- Air8601 无复位脚
    })
    if cam_missing then _G.camera = nil end
    log.info(TAG, string.format("exfacecam.open 返回: pcall_ok=%s open_ok=%s 耗时=%dms",
        tostring(ok), tostring(open_ok), math.floor(mcu.ticks() - t0)))
    return ok, open_ok
end

--[[打印模组固件版本与已录入用户列表（排障用，与 face_demo.lua 的 do_list_users 一致）]]
local function log_module_info()
    -- get_version() 返回 (ok, version)，pcall 包住后是 3 个返回值
    local vok, v_ok, v_ver = pcall(function() return exfacecam.get_version() end)
    if vok and v_ok then
        log.info(TAG, "模组版本: " .. tostring(v_ver))
    else
        log.warn(TAG, string.format("读取模组版本失败: pcall_ok=%s ver_ok=%s",
            tostring(vok), tostring(v_ok)))
    end

    -- list() 返回 (ok, count, ids)，pcall 包住后是 4 个返回值，必须接满
    local pok, list_ok, count, ids = pcall(function() return exfacecam.list() end)
    log.info(TAG, string.format("用户列表: pcall_ok=%s list_ok=%s count=%s",
        tostring(pok), tostring(list_ok), tostring(count)))
    if not (pok and list_ok) then return end
    if type(ids) ~= "table" then return end

    for _, uid in ipairs(ids) do
        local qok, q_ok, q_data = pcall(function() return exfacecam.query(uid) end)
        if qok and q_ok and type(q_data) == "table" then
            log.info(TAG, string.format("用户 id=%s name=%s admin=%s",
                tostring(uid), tostring(q_data.name), tostring(q_data.admin)))
        else
            log.warn(TAG, string.format("查询用户 %s 失败: pcall_ok=%s q_ok=%s data=%s",
                tostring(uid), tostring(qok), tostring(q_ok), tostring(q_data)))
        end
    end
end

local function init_task()
    if init_running then return end
    init_running = true

    face_state = ST.INITING
    face_ready = false
    publish_status()

    log.info(TAG, string.format("开始初始化人脸模组: face_uart=%d face_rst=nil camera全局=%s",
        FACE_UART, tostring(_G.camera)))

    -- 等供电稳定（config.power_on 里 GPIO73 UVC_EN 拉高后 200ms，这里再留足余量）
    sys.wait(1000)
    sys.wait(BOOT_WAIT)

    for i = 1, MAX_INIT_RETRY do
        local ok, open_ok = open_face_module()
        if ok and open_ok then
            face_state = ST.READY
            face_ready = true
            init_running = false
            log.info(TAG, "人脸模组初始化成功（UART" .. FACE_UART .. "）")
            publish_status()
            log_module_info()
            return
        end

        log.warn(TAG, "人脸模组初始化失败（第 " .. i .. "/" .. MAX_INIT_RETRY .. " 次）",
            tostring(open_ok))
        if i < MAX_INIT_RETRY then
            face_state = ST.INITING
            publish_status({
                message = "人脸模组未响应，正在重试（" .. (i + 1) .. "/" .. MAX_INIT_RETRY .. "）",
            })
            sys.wait(INIT_RETRY_DELAY)
        end
    end

    face_state = ST.ERROR
    face_ready = false
    init_running = false
    log.error(TAG, "人脸模组初始化失败，已重试 " .. MAX_INIT_RETRY .. " 次")
    publish_status({ message = "人脸模组连接失败，请检查 UART2 接线与模组供电" })
end

-- ==================== 人脸录入 / 验证 ====================
--[[自动生成姓名：用户N（N = 模组内已有模板数 + 1）

★ exfacecam.list() 返回 3 个值 (ok, count, ids)，pcall 包住后是 4 个
  (pok, list_ok, count, ids)；这里必须接满 4 个，否则 ids 会落到 count
  的位置上，后续按表使用时会抛 "attempt to get length of a number value"。]]
local function next_user_name()
    local pok, list_ok, count = pcall(function() return exfacecam.list() end)
    if pok and list_ok then
        return "用户" .. tostring((tonumber(count) or 0) + 1)
    end
    return "用户"
end

--[[释放忙碌态：只有模组仍在线才能回到 READY]]
local function leave_busy()
    face_state = face_ready and ST.READY or ST.ERROR
    publish_status()
end

--[[复位模组并等待其重新应答

模组若被 UVC 预览留在"摄像头模式"，register 会因传感器切不回人脸模式而一直超时
（返回 13 = MR_FAILED4_TIMEOUT），复位可以让传感器回到人脸模式。
这里做完复位再用 list() 探测模组是否已恢复应答，成功返回 true。]]
local function reset_and_wait()
    local t0 = mcu.ticks()
    local rok, r_ok = pcall(function() return exfacecam.reset() end)
    log.info(TAG, string.format("复位人脸模组: pcall_ok=%s reset_ok=%s 耗时=%dms",
        tostring(rok), tostring(r_ok), math.floor(mcu.ticks() - t0)))
    sys.wait(RESET_WAIT)

    for i = 1, 3 do
        local pok, list_ok, count = pcall(function() return exfacecam.list() end)
        log.info(TAG, string.format("复位后探测(%d/3): pcall_ok=%s list_ok=%s count=%s",
            i, tostring(pok), tostring(list_ok), tostring(count)))
        if pok and list_ok then return true end
        sys.wait(1000)
    end
    log.warn(TAG, "复位后模组仍未应答")
    return false
end

local function do_register(params)
    params = params or {}

    if not face_ready then
        sys.publish("FACE_REGISTER_RESULT", { success = false, error = "人脸模组未就绪，请稍后重试" })
        return
    end
    --[[互斥：exfacecam 内部是单例状态（reply_map / note_cb 共享），
    并发 register/verify 会互相抢回包，表现为莫名超时或结果串台。]]
    if face_state == ST.BUSY then
        sys.publish("FACE_REGISTER_RESULT", { success = false, error = "人脸模块正忙，请稍后重试" })
        return
    end

    face_state = ST.BUSY
    publish_status()

    local name = params.name
    if name == nil or name == "" then name = next_user_name() end

    local timeout = params.timeout or ENROLL_TIMEOUT
    log.info(TAG, string.format("开始人脸录入，name=%s admin=%s timeout=%ds",
        tostring(name), tostring(params.admin or false), timeout))

    local t0 = mcu.ticks()
    local ok, reg_ok, reg_data = pcall(function()
        return exfacecam.register({
            name = name,
            admin = params.admin or false,
            timeout = timeout,
            on_state = face_state_cb,
        })
    end)
    log.info(TAG, string.format("exfacecam.register 返回: pcall_ok=%s reg_ok=%s reg_data=%s 耗时=%dms",
        tostring(ok), tostring(reg_ok), tostring(reg_data), math.floor(mcu.ticks() - t0)))

    leave_busy()

    if not ok then
        log.error(TAG, "人脸录入异常", tostring(reg_ok))
        sys.publish("FACE_REGISTER_RESULT", { success = false, error = "人脸录入异常：" .. tostring(reg_ok) })
        return
    end

    if reg_ok then
        local user_id = tonumber(reg_data)
        log.info(TAG, "人脸录入成功，user_id=" .. tostring(user_id))
        sys.publish("FACE_REGISTER_RESULT", { success = true, user_id = user_id, name = name })
    else
        log.warn(TAG, "人脸录入失败，code=" .. tostring(reg_data))
        sys.publish("FACE_REGISTER_RESULT", { success = false, error = err_text(reg_data) })
    end
end

local function do_verify(params)
    params = params or {}

    if not face_ready then
        sys.publish("FACE_VERIFY_RESULT", { success = false, error = "人脸模组未就绪，请稍后重试" })
        return
    end
    if face_state == ST.BUSY then
        sys.publish("FACE_VERIFY_RESULT", { success = false, error = "人脸模块正忙，请稍后重试" })
        return
    end

    face_state = ST.BUSY
    publish_status()

    -- 预览占用过 UVC 时传感器可能停在摄像头模式，按需复位回人脸模式
    if params.reset then reset_and_wait() end

    local timeout = params.timeout or VERIFY_TIMEOUT
    log.info(TAG, string.format("开始人脸验证，timeout=%ds", timeout))

    local t0 = mcu.ticks()
    local ok, ver_ok, ver_data = pcall(function()
        return exfacecam.verify({
            timeout = timeout,
            on_state = face_state_cb,
        })
    end)
    log.info(TAG, string.format("exfacecam.verify 返回: pcall_ok=%s ver_ok=%s ver_data=%s 耗时=%dms",
        tostring(ok), tostring(ver_ok), tostring(ver_data), math.floor(mcu.ticks() - t0)))

    leave_busy()

    if not ok then
        log.error(TAG, "人脸验证异常", tostring(ver_ok))
        sys.publish("FACE_VERIFY_RESULT", { success = false, error = "人脸验证异常：" .. tostring(ver_ok) })
        return
    end

    if not ver_ok then
        log.warn(TAG, "人脸验证失败，code=" .. tostring(ver_data))
        sys.publish("FACE_VERIFY_RESULT", { success = false, error = err_text(ver_data) })
        return
    end

    if type(ver_data) == "table" and ver_data.user_id then
        log.info(TAG, "人脸验证成功，user_id=" .. tostring(ver_data.user_id))
        sys.publish("FACE_VERIFY_RESULT", {
            success = true,
            user_id = ver_data.user_id,
            name = ver_data.name,
            admin = ver_data.admin,
            unlock_status = ver_data.unlock_status,
        })
    else
        sys.publish("FACE_VERIFY_RESULT", { success = false, error = "未识别到已录入的人脸" })
    end
end

--[[清空模组内全部已录入用户

模组自身不做录入查重，重复录入会持续占用模板位，因此提供整体清空作为兜底手段。]]
local function do_clear()
    if not face_ready then
        sys.publish("FACE_CLEAR_RESULT", { success = false, error = "人脸模组未就绪，请稍后重试" })
        return
    end
    if face_state == ST.BUSY then
        sys.publish("FACE_CLEAR_RESULT", { success = false, error = "人脸模块正忙，请稍后重试" })
        return
    end

    face_state = ST.BUSY
    publish_status()

    local ok, clear_ok = pcall(function() return exfacecam.clear() end)
    log.info(TAG, string.format("清空全部用户: pcall_ok=%s clear_ok=%s",
        tostring(ok), tostring(clear_ok)))

    leave_busy()

    if not ok then
        sys.publish("FACE_CLEAR_RESULT", { success = false, error = "清空异常：" .. tostring(clear_ok) })
    elseif clear_ok then
        sys.publish("FACE_CLEAR_RESULT", { success = true })
    else
        sys.publish("FACE_CLEAR_RESULT", { success = false, error = "清空失败，模组未返回成功" })
    end
end

--[[任务兜底：录/验内部是阻塞调用，异常不能让整机重启（Lua VM exit 会触发 reboot）]]
local function start_task_safe(fn, params, result_topic)
    sys.taskInit(function()
        local ok, err = pcall(fn, params)
        if not ok then
            log.error(TAG, "人脸任务异常", tostring(err))
            face_state = face_ready and ST.READY or ST.ERROR
            sys.publish(result_topic, { success = false, error = "人脸操作异常：" .. tostring(err) })
            publish_status()
        end
    end)
end

-- ==================== 消息订阅 ====================
sys.subscribe("FACE_REGISTER_REQ", function(params)
    start_task_safe(do_register, params, "FACE_REGISTER_RESULT")
end)

sys.subscribe("FACE_VERIFY_REQ", function(params)
    start_task_safe(do_verify, params, "FACE_VERIFY_RESULT")
end)

sys.subscribe("FACE_CLEAR_REQ", function(params)
    start_task_safe(do_clear, params, "FACE_CLEAR_RESULT")
end)

sys.subscribe("FACE_STATUS_REQ", function()
    publish_status()
    -- 未就绪且当前没有初始化在跑 → 重新走一遍初始化（模组热插拔/上电晚的场景）
    if not face_ready and not init_running then
        sys.taskInit(init_task)
    end
end)

-- 随 app_main 加载即开始初始化，等页面打开时通常已就绪
sys.taskInit(init_task)
