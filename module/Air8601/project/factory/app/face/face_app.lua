--[[
@module  face_app
@summary 人脸识别业务层（AirCAMERA_1034 人脸模组 UART2 + USB UVC 实时预览）
@version 2.0
@date    2026.10.23
@author  江访
@usage
本模块封装「实时预览 + 人脸录入 / 验证 / 清空」的完整链路，与 UI 通过消息解耦：

  订阅: FACE_PREVIEW_START_REQ → {x, y, w, h, fit?}  开启实时预览（x/y 为屏幕绝对坐标）
        FACE_PREVIEW_STOP_REQ  → {destroy?}          停止预览；destroy=true 时同时销毁组件
        FACE_REGISTER_REQ      → {name?, admin?, timeout?}   人脸录入
        FACE_VERIFY_REQ        → {timeout?}                  人脸验证
        FACE_CLEAR_REQ         → 清空模组内全部已录入用户
        FACE_STATUS_REQ        → 查询模组状态（未就绪时顺带重新初始化）
  发布: FACE_PREVIEW_STATE  → {state, text}           0=未预览 1=打开中 2=预览中
        FACE_STATUS_UPDATE  → {state, ready, text, message?}
        FACE_STATE_UPDATE   → {state, message}            引导语（偏头/遮挡…）
        FACE_REGISTER_RESULT → {success, user_id?, name?, error?}
        FACE_VERIFY_RESULT   → {success, user_id?, name?, admin?, unlock_status?, error?}
        FACE_CLEAR_RESULT    → {success, error?}

硬件（Air8601）：
  - 人脸模组走 UART2，115200/8N1，无复位脚（face_rst = nil）
  - 摄像头与人脸模组是同一颗模组（AirCAMERA_1034），UVC 预览与人脸识别互斥
  - GPIO73 = UVC_EN，断电 400ms / 上电 500ms 可硬复位模组

时序铁律（实机验证）：
  1. 停流顺序必须是 widget:stop() → 等 400ms → excamera.close() → 等 100~300ms，
     否则在途帧回调会访问已释放的缓冲（use-after-free）。
  2. 本次开机用过 UVC 预览后，模组停在摄像头模式，MID_RESET 软复位只回包不重启，
     register 必超时且传感器持续出流发热 —— 必须 GPIO73 断电硬复位，再重新探测 UART。
  3. excamera / exfacecam 都是单例，预览与人脸操作、人脸操作之间全部串行。
]]

local exfacecam = require "exfacecam"

local excamera = require "excamera"

local TAG = "face_app"
local FACE_UART = 2          -- 人脸模组串口（Air8601：UART2）
local MAX_INIT_RETRY = 3     -- 初始化最大尝试次数
local INIT_RETRY_DELAY = 1000
local BOOT_WAIT = 2000       -- 上电后等待模组稳定的时间（与 face_demo 一致）
local ENROLL_TIMEOUT = 15    -- 录入超时（秒）
local VERIFY_TIMEOUT = 15    -- 验证超时（秒）

-- ==================== 摄像头参数 ====================
local CAM_EN_GPIO = 73       -- UVC_EN，断电可硬复位整个摄像头模组
local SENSOR_W = 960
local SENSOR_H = 480
local CAM_FPS = 10
local CAM_ROTATION = 90      -- 模组竖装，画面顺时针旋转 90°
local CONNECT_WAIT = 800     -- 首次等待摄像头连接的时间
local RETRY_WAIT = 3000      -- 断电重枚举后再等待的时间

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
local face_opened = false    -- exfacecam 是否已打开 UART 会话
local face_opening = false   -- 正在打开（避免并发重复 open）
local last_state_ms = 0      -- 上次向 UI 发布引导语的时间戳（限流用）

-- ==================== 预览状态 ====================
local PV = { IDLE = 0, OPENING = 1, PREVIEWING = 2 }
local PV_TEXT = {
    [PV.IDLE]      = "预览未开启",
    [PV.OPENING]   = "正在打开摄像头...",
    [PV.PREVIEWING] = "预览中",
}

local pv_state = PV.IDLE
local pv_gen = 0             -- 代数，让旧的连接监控 / 旧回调立即失效
local pv_host = nil          -- 宿主机位容器（挂在 airui.screen 上）
local pv_widget = nil        -- airui.camera 组件
local pv_box = nil           -- 组件当前几何，用于判断能否复用
local stream_open = false    -- excamera 数据流是否已打开
local uvc_used = false       -- 本次开机是否用过 UVC 预览（用过则录入前必须硬复位）

-- ==================== 工具 ====================
--[[mcu.ticks() 不是毫秒：优先按 mcu.hz() 换算，取不到则退回原值]]
local function now_ms()
    if mcu and mcu.hz then
        local hz = mcu.hz()
        if hz and hz > 0 then
            return mcu.ticks() * 1000 // hz
        end
    end
    if mcu and mcu.ticks then return mcu.ticks() end
    return os.time() * 1000
end

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

local function publish_preview(text)
    sys.publish("FACE_PREVIEW_STATE", {
        state = pv_state,
        text = text or PV_TEXT[pv_state] or "",
    })
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
    local now = now_ms()

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

-- ==================== 摄像头硬复位 ====================
--[[GPIO73 断电重枚举

UVC 模式下模组停在摄像头模式，MID_RESET 软复位只回包不重启，
必须真正断电再上电，模组才会回到人脸模式并重新枚举 USB。]]
local function power_cycle_camera()
    log.info(TAG, "GPIO" .. CAM_EN_GPIO .. " 断电重枚举摄像头")
    pcall(gpio.setup, CAM_EN_GPIO, 0)
    pcall(gpio.set, CAM_EN_GPIO, 0)
    sys.wait(400)                                   -- 断电保持 400ms
    pcall(gpio.setup, CAM_EN_GPIO, 1, gpio.PULLUP)
    pcall(gpio.set, CAM_EN_GPIO, 1)
    sys.wait(500)                                   -- 上电后等模组完成重新枚举
end

-- ==================== 人脸模组打开 / 重开 ====================
--[[打开人脸模组

exfacecam.open 末尾有一句 `if param.id == camera.USB then`：
整机若没有编入 camera 库，全局 camera 为 nil，这里会抛异常，
而那时 UART 已经 setup 完成、模组其实已在线。为了让返回值可信，
调用前补一个占位 camera —— param.id 为 nil，永远不等，不会触发摄像头初始化。]]
local function open_face_module()
    local cam_missing = (_G.camera == nil)
    if cam_missing then _G.camera = { USB = -1 } end
    local t0 = now_ms()
    local ok, open_ok = pcall(exfacecam.open, {
        face_uart = FACE_UART,   -- 人脸模组串口（115200/8N1）
        face_rst = nil,          -- Air8601 无复位脚
    })
    if cam_missing then _G.camera = nil end
    log.info(TAG, string.format("exfacecam.open 返回: pcall_ok=%s open_ok=%s 耗时=%dms",
        tostring(ok), tostring(open_ok), now_ms() - t0))
    return ok, open_ok
end

local function ensure_face_open()
    if face_opened then return true end

    -- 另一个协程正在打开：等它结束，避免重复 open 抢同一个 UART 会话
    if face_opening then
        local waited = 0
        while face_opening and waited < 10000 do
            sys.wait(200)
            waited = waited + 200
        end
        if face_opened then return true end
    end

    face_opening = true
    for i = 1, MAX_INIT_RETRY do
        local ok, open_ok = open_face_module()
        if ok and open_ok then
            face_opening = false
            face_opened = true
            return true
        end
        log.warn(TAG, "人脸模组打开失败（第 " .. i .. "/" .. MAX_INIT_RETRY .. " 次）",
            tostring(open_ok))
        if i < MAX_INIT_RETRY then sys.wait(INIT_RETRY_DELAY) end
    end
    face_opening = false
    return false
end

--[[硬复位后重开：先关掉旧会话，等模组重启完，再重新探测 UART]]
local function reopen_face()
    if face_opened then
        pcall(exfacecam.close)
        face_opened = false
    end
    sys.wait(500)
    return ensure_face_open()
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

    log.info(TAG, string.format("开始初始化人脸模组: face_uart=%d face_rst=nil",
        FACE_UART))

    -- 等供电稳定（config.power_on 里 GPIO73 UVC_EN 拉高后 200ms，这里再留足余量）
    sys.wait(1000)
    sys.wait(BOOT_WAIT)

    if ensure_face_open() then
        face_state = ST.READY
        face_ready = true
        init_running = false
        log.info(TAG, "人脸模组初始化成功（UART" .. FACE_UART .. "）")
        publish_status()
        log_module_info()
        return
    end

    face_state = ST.ERROR
    face_ready = false
    init_running = false
    log.error(TAG, "人脸模组初始化失败，已重试 " .. MAX_INIT_RETRY .. " 次")
    publish_status({ message = "人脸模组连接失败，请检查 UART2 接线与模组供电" })
end

-- ==================== 实时预览 ====================
--[[销毁预览组件：必须先 stop 已停流，否则销毁图像时在途帧回调会踩空]]
local function destroy_preview_widgets()
    if pv_widget and type(pv_widget.is_destroyed) == "function"
        and not pv_widget:is_destroyed() then
        pcall(function() pv_widget:stop() end)
        pcall(function() pv_widget:destroy() end)
    end
    pv_widget = nil
    if pv_host and type(pv_host.is_destroyed) == "function"
        and not pv_host:is_destroyed() then
        pcall(function() pv_host:destroy() end)
    end
    pv_host = nil
    pv_box = nil
end

local function close_stream()
    if not stream_open then return end
    stream_open = false
    pcall(excamera.close)
end

--[[把旋转下发给底层 camera（老固件不支持时 pcall 忽略，不影响预览）]]
local function apply_camera_rotation()
    if type(_G.camera) ~= "table" or type(camera.config) ~= "function" then return end
    local rot = camera.ROTATE_90 or CAM_ROTATION
    for _, name in ipairs({ "CONF_PREVIEW_ROTATE", "CONF_SNAPSHOT_ROTATE",
                            "CONF_CAPTURE_ROTATE", "CONF_ROTATE" }) do
        local conf = camera[name]
        if conf then pcall(camera.config, 0, conf, rot) end
    end
end

--[[建宿主容器 + airui.camera 组件（坐标是屏幕绝对坐标）

宿主容器挂在 airui.screen 上，位图直接覆盖页面左侧区域，
因此页面不得在该矩形内绘制任何需要长期可见的内容。
用容器包一层是因为 airui.camera 没有 set_hidden/set_pos，
停流后到组件销毁之间需要立即遮挡最后一帧时只能隐藏宿主容器。]]
local function create_preview_widgets(req)
    local box = {
        x = req.x or 0, y = req.y or 0,
        w = req.w or 320, h = req.h or 240,
    }
    local fit = req.fit or "contain"

    --[[几何没变就复用已有组件（与示例一致）

    停止预览只 stop 显示、不销毁组件，再次开始预览时复用它可以保留最后一帧；
    更重要的是此时数据流可能还没关（停流任务里有 400ms 等待），
    销毁图像会让在途帧回调踩空。]]
    if pv_widget and pv_box and not pv_widget:is_destroyed()
        and pv_box.x == box.x and pv_box.y == box.y
        and pv_box.w == box.w and pv_box.h == box.h then
        if type(pv_widget.set_fit) == "function" then
            pcall(pv_widget.set_fit, pv_widget, fit)
        end
        return true
    end

    destroy_preview_widgets()

    pv_host = airui.container({
        parent = airui.screen,
        x = box.x, y = box.y, w = box.w, h = box.h,
        color = 0x000000,
    })
    if not pv_host then
        return false, "预览容器创建失败"
    end

    pv_widget = airui.camera({
        parent     = pv_host,
        x          = 0,
        y          = 0,
        w          = box.w,
        h          = box.h,
        fit        = fit,
        auto_start = false,
        rotation   = CAM_ROTATION,
    })
    if not pv_widget then
        pcall(function() pv_host:destroy() end)
        pv_host = nil
        return false, "camera 组件创建失败"
    end
    pv_box = box
    log.info(TAG, string.format("预览组件已创建 %dx%d @(%d,%d) rotation=%d",
        box.w, box.h, box.x, box.y, CAM_ROTATION))
    return true
end

-- excamera 预览事件
local function preview_event_cb(event, ...)
    if event == "connected" then
        if pv_state ~= PV.OPENING then return end
        if not pv_widget or pv_widget:is_destroyed() then return end

        if type(pv_widget.set_rotation) == "function" then
            pcall(pv_widget.set_rotation, pv_widget, CAM_ROTATION)
        end
        apply_camera_rotation()
        pcall(function() pv_widget:register() end)
        pcall(function() pv_widget:start() end)

        pv_state = PV.PREVIEWING
        log.info(TAG, "摄像头已连接，预览开始")
        publish_preview("预览中")

    elseif event == "disconnected" then
        log.warn(TAG, "摄像头已断开")
        if pv_widget and not pv_widget:is_destroyed() then
            pcall(function() pv_widget:stop() end)
        end
        if pv_state == PV.PREVIEWING then
            -- 运行中掉线：交给连接监控 / 后续枚举自动重连
            pv_state = PV.OPENING
            publish_preview("摄像头断开，等待重连...")
        end

    elseif event == "error" then
        log.warn(TAG, "摄像头错误", ...)
    end
end

-- 打开数据流并注册回调（必须在协程中执行）
local function open_stream()
    local param = {
        id            = camera.USB,
        sensor_width  = SENSOR_W,
        sensor_height = SENSOR_H,
        usb_port      = 1,
        work_mode     = 2,                  -- 预览模式
        save_path     = "/ram/preview.jpg",
        fps           = CAM_FPS,
    }
    local ok, ret = pcall(excamera.open, param)
    if not (ok and ret) then
        log.warn(TAG, "excamera.open 失败", tostring(ret))
        return false
    end
    stream_open = true
    uvc_used = true     -- 模组已进入 UVC 模式，后续人脸操作前必须硬复位

    local pok, pret = pcall(excamera.preview, preview_event_cb)
    if not (pok and pret) then
        log.warn(TAG, "excamera.preview 失败", tostring(pret))
        close_stream()
        return false
    end
    return true
end

local connect_watch -- 前向声明

--[[停止预览

destroy=false：只停显示，保留最后一帧（airui.camera 组件不销毁）
destroy=true ：停流后销毁组件与宿主容器
顺序：widget:stop() → 400ms → excamera.close() → 100ms → destroy]]
local function stop_preview(destroy, text)
    if pv_state == PV.IDLE and not destroy then return end

    local was_active = (pv_state ~= PV.IDLE) or stream_open
    pv_state = PV.IDLE
    pv_gen = pv_gen + 1                  -- 让进行中的连接监控立即失效

    if pv_widget and not pv_widget:is_destroyed() then
        pcall(function() pv_widget:stop() end)
    end
    if destroy then
        if pv_host and not pv_host:is_destroyed() then
            pcall(function() pv_host:set_hidden(true) end)
        end
    end
    publish_preview(text or (destroy and "预览已关闭" or "预览已停止"))

    local gen = pv_gen
    sys.taskInit(function()
        if was_active then
            sys.wait(400)                -- 等在途帧回调跑完，避免 close 释放缓冲时 use-after-free
            close_stream()
            sys.wait(100)
        end
        if destroy and gen == pv_gen then
            destroy_preview_widgets()
            log.info(TAG, "预览组件已销毁")
        end
    end)
end

--[[连接监控：先等 CONNECT_WAIT，未连接则 GPIO73 断电重枚举一次，再等 RETRY_WAIT

断电动作必须在 excamera.preview() 之后执行，否则模组会被我们自己打断枚举。]]
connect_watch = function(gen)
    local waited = 0
    while waited < CONNECT_WAIT do
        if gen ~= pv_gen or pv_state ~= PV.OPENING then return end
        sys.wait(100)
        waited = waited + 100
    end
    if gen ~= pv_gen or pv_state ~= PV.OPENING then return end

    power_cycle_camera()
    waited = 0
    while waited < RETRY_WAIT do
        if gen ~= pv_gen or pv_state ~= PV.OPENING then return end
        sys.wait(100)
        waited = waited + 100
    end
    if gen ~= pv_gen or pv_state ~= PV.OPENING then return end

    stop_preview(false, "未检测到摄像头，请检查模组接线")
end

--[[开启预览

只做同步段（建组件、进 OPENING），真正的开流与连接监控放在任务里，
这样不会阻塞命令队列。]]
local function start_preview(req)
    if pv_state ~= PV.IDLE then return end
    if face_state == ST.BUSY then
        publish_preview("人脸处理中，请稍后再开启预览")
        return
    end

    local ok, err = create_preview_widgets(req)
    if not ok then
        publish_preview(err)
        return
    end

    pv_state = PV.OPENING
    pv_gen = pv_gen + 1
    local gen = pv_gen
    publish_preview("正在打开摄像头...")

    sys.taskInit(function()
        pcall(excamera.close)            -- 清掉上一轮可能残留的会话
        stream_open = false
        sys.wait(100)
        if gen ~= pv_gen then return end

        if not open_stream() then
            if gen == pv_gen then
                pv_state = PV.IDLE
                publish_preview("摄像头打开失败")
            end
            return
        end
        if gen ~= pv_gen then
            close_stream()
            return
        end
        connect_watch(gen)
    end)
end

--[[为人脸识别让出模组：停显示 → 等 400ms → 关流 → 等 300ms]]
local function stop_stream_for_face()
    local active = (pv_state ~= PV.IDLE) or stream_open
    if pv_state ~= PV.IDLE then
        pv_state = PV.IDLE
        pv_gen = pv_gen + 1
        if pv_widget and not pv_widget:is_destroyed() then
            pcall(function() pv_widget:stop() end)
        end
        publish_preview("停止预览，为人脸识别让出模组...")
    end
    if not active then return end
    sys.wait(400)
    close_stream()
    sys.wait(300)
end

--[[人脸操作前的模组准备
本次开机用过 UVC 预览 → 断电硬复位 + 重开 UART
没用过预览 → 直接确保会话在，等 300ms 让模组稳定

与示例一致：每次操作都现场探测一次 UART（3 次重试），
开机初始化失败过也能靠这一步重新连上，所以入口不再用 face_ready 拦截。]]
local function prepare_face_module()
    stop_stream_for_face()

    if uvc_used then
        power_cycle_camera()
        uvc_used = false
        if not reopen_face() then
            log.error(TAG, "硬复位后人脸模组无响应")
            return false
        end
        face_ready = true       -- 模组已重新在线，leave_busy 才能回到 READY
        return true
    end

    if not ensure_face_open() then
        log.error(TAG, "人脸模组无响应")
        return false
    end
    face_ready = true
    sys.wait(300)
    return true
end

-- ==================== 人脸录入 / 验证 ====================
--[[自动生成姓名：用户N（N = 模组内已有模板数 + 1）

★ exfacecam.list() 返回 (ok, count, ids)，pcall 包住后是 4 个返回值
  (pok, list_ok, count, ids)；取值按位置对齐，count 是第 3 个。]]
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

--[[模组准备失败：标记为 ERROR，让界面提示重新连接]]
local function fail_module()
    face_ready = false
    face_state = ST.ERROR
    publish_status({ message = "人脸模组无响应，请检查 UART2 接线与模组供电" })
end

local function do_register(params)
    params = params or {}

    --[[互斥：exfacecam 内部是单例状态（reply_map / note_cb 共享），
    并发 register/verify 会互相抢回包，表现为莫名超时或结果串台。]]
    if face_state == ST.BUSY then
        sys.publish("FACE_REGISTER_RESULT", { success = false, error = "人脸模块正忙，请稍后重试" })
        return
    end

    face_state = ST.BUSY
    publish_status()

    if not prepare_face_module() then
        fail_module()
        sys.publish("FACE_REGISTER_RESULT", { success = false, error = "人脸模组无响应，请稍后重试" })
        return
    end

    local name = params.name
    if name == nil or name == "" then name = next_user_name() end

    local timeout = params.timeout or ENROLL_TIMEOUT
    log.info(TAG, string.format("开始人脸录入，name=%s admin=%s timeout=%ds",
        tostring(name), tostring(params.admin or false), timeout))

    local t0 = now_ms()
    local ok, reg_ok, reg_data = pcall(function()
        return exfacecam.register({
            name = name,
            admin = params.admin or false,
            timeout = timeout,
            on_state = face_state_cb,
        })
    end)
    log.info(TAG, string.format("exfacecam.register 返回: pcall_ok=%s reg_ok=%s reg_data=%s 耗时=%dms",
        tostring(ok), tostring(reg_ok), tostring(reg_data), now_ms() - t0))

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

    if face_state == ST.BUSY then
        sys.publish("FACE_VERIFY_RESULT", { success = false, error = "人脸模块正忙，请稍后重试" })
        return
    end

    face_state = ST.BUSY
    publish_status()

    if not prepare_face_module() then
        fail_module()
        sys.publish("FACE_VERIFY_RESULT", { success = false, error = "人脸模组无响应，请稍后重试" })
        return
    end

    local timeout = params.timeout or VERIFY_TIMEOUT
    log.info(TAG, string.format("开始人脸验证，timeout=%ds", timeout))

    local t0 = now_ms()
    local ok, ver_ok, ver_data = pcall(function()
        return exfacecam.verify({
            timeout = timeout,
            on_state = face_state_cb,
        })
    end)
    log.info(TAG, string.format("exfacecam.verify 返回: pcall_ok=%s ver_ok=%s ver_data=%s 耗时=%dms",
        tostring(ok), tostring(ver_ok), tostring(ver_data), now_ms() - t0))

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
    if face_state == ST.BUSY then
        sys.publish("FACE_CLEAR_RESULT", { success = false, error = "人脸模块正忙，请稍后重试" })
        return
    end

    face_state = ST.BUSY
    publish_status()

    if not prepare_face_module() then
        fail_module()
        sys.publish("FACE_CLEAR_RESULT", { success = false, error = "人脸模组无响应，请稍后重试" })
        return
    end

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

-- ==================== 命令队列 ====================
--[[单条队列串行执行人脸操作

exfacecam 是单例：register / verify / clear 并发会互相抢回包。
队列同时消除「两条 REQ 在 BUSY 置位前同时进入」的竞态。
异常必须在这里兜住（未捕获异常会触发 Lua VM exit → 整机重启）。]]
local cmd_queue = {}
local cmd_running = false

local function enqueue(fn, result_topic)
    cmd_queue[#cmd_queue + 1] = { fn = fn, topic = result_topic }
    if cmd_running then return end

    cmd_running = true
    sys.taskInit(function()
        while #cmd_queue > 0 do
            local item = table.remove(cmd_queue, 1)
            local ok, err = pcall(item.fn)
            if not ok then
                log.error(TAG, "人脸任务异常", tostring(err))
                face_state = face_ready and ST.READY or ST.ERROR
                publish_status()
                if item.topic then
                    sys.publish(item.topic, { success = false, error = "人脸操作异常：" .. tostring(err) })
                end
            end
        end
        cmd_running = false
    end)
end

-- ==================== 消息订阅 ====================
sys.subscribe("FACE_REGISTER_REQ", function(params)
    enqueue(function() do_register(params) end, "FACE_REGISTER_RESULT")
end)

sys.subscribe("FACE_VERIFY_REQ", function(params)
    enqueue(function() do_verify(params) end, "FACE_VERIFY_RESULT")
end)

sys.subscribe("FACE_CLEAR_REQ", function(params)
    enqueue(function() do_clear(params) end, "FACE_CLEAR_RESULT")
end)

sys.subscribe("FACE_STATUS_REQ", function()
    publish_status()
    -- 未就绪且当前没有初始化在跑 → 重新走一遍初始化（模组热插拔/上电晚的场景）
    if not face_ready and not init_running then
        sys.taskInit(init_task)
    end
end)

sys.subscribe("FACE_PREVIEW_START_REQ", function(req)
    start_preview(req or {})
end)

sys.subscribe("FACE_PREVIEW_STOP_REQ", function(req)
    stop_preview(req and req.destroy == true, req and req.text)
end)

-- 随 app_main 加载即开始初始化，等页面打开时通常已就绪
sys.taskInit(init_task)
