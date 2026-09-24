--[[
@module  face_preview
@summary 刷脸界面摄像头预览模块（AirCAMERA_1034 UVC → airui.camera 组件）
@version 3.5
@date    2026.09.21
@author  王城钧
@usage
摄像头数据流随刷脸窗口开关：
- 进刷脸窗口：start() 启动预览（excamera.open+preview，内部 usb.mode 重新枚举）
- 关窗：stop() 停止预览（仅 excamera.close()，不断电 USB，保证 UART2 人脸识别正常）
- 拍照留底：capture() 在预览推流中抓取下一帧 JPEG（须在 stop() 之前调用，任务内使用）

支持预览与识别并行（config.face.preview.mode != "serial"）：
- 画面真正就绪（connected 回调 widget:start 之后）才发布 FACE_PREVIEW_READY，
  业务层收到该事件后才发起人脸识别，替代原有"固定等 3 秒"的定时方式。
- 断电重试：进窗不再无条件对 GPIO73 断电重枚举（会让人脸模组反复掉电重启 → 识别失败/卡死）；
  只有连接监控在 connect_wait(默认2500ms) 内始终未收到 connected 时，才断电重试一次，
  再等 retry_wait(默认3000ms) 仍无连接才判定预览不可用。
- 断开 ≠ 失败：若发生了断电重枚举，该断开属于预期行为，
  故断开后先等 reconnect_wait(默认2500ms) 自动重连，超时仍未连上才判定预览不可用。

注意：
1. 数据流不能常驻：常驻会让 luat_camera 任务事件队列爆满，CPU 被占满导致红外人脸识别处理不过来。
2. 用最小分辨率(320×240)降低解码负载，保证识别期间 CPU 富余。
3. airui.camera 组件必须挂 airui.screen。
4. 并行模式下预览帧率压到 busy_fps(3fps)，把 CPU 让给 UART2 人脸数据，避免识别超时。
5. airui.camera 组件不支持画面旋转（无 rotation 参数、无 set_rotation 方法），
   画面方向只能靠物理安装方向或原厂固件新增能力解决，软件层无法旋转。
]]

local excamera = require "excamera"
local config = require "config"

local M = {}

local widget = nil          -- airui.camera 显示组件
local active = false        -- 预览是否激活
local gen = 0               -- 代数，防旧回调误用
local start_gen = 0         -- 本次 start 时的代数（connected 回调判断用）
local capture_pending = false -- 拍照请求标记（下一帧到达时抓取，供 M.capture 使用）
local closing = false       -- 关闭进行中标记
local ready_published = false -- 本次预览是否已发布就绪事件（防止重复发布/跨窗误发）
local reconnect_timer = nil -- 断开后等待自动重连的宽限定时器（防把断电重枚举误判为预览失败）
local connected_once = false  -- 本次预览是否已收到过 connected（区分"未连接"与"已连接后掉线"）
local power_retry_done = false -- 本次预览是否已执行过"未连接 →  GPIO73 断电重试"（最多一次）
local watch_running = false   -- 连接监控协程是否在跑（防止重复启动）

-- 销毁旧预览组件（pcall 保护）
-- 销毁旧预览组件内部执行（pcall 包装）
local function do_destroy_widget()
    widget:stop()
    widget:destroy()
end

local function destroy_old_widget()
    if widget and not widget:is_destroyed() then
        pcall(do_destroy_widget)
        widget = nil
    end
end

-- 等待上次关闭完成
local function wait_closing_done()
    local t0 = 0
    while closing and t0 < 3000 do
        sys.wait(50)  -- 每50ms检查一次关闭状态
        t0 = t0 + 50
    end
    if closing then
        log.warn("face_preview", "上次关闭仍未完成(3s超时)，继续尝试重建")
    end
end

-- 强制关闭旧数据流内部执行（pcall 包装）
local function do_force_close_camera()
    excamera.close()
end

-- 强制关闭旧数据流（pcall 保护）
local function force_close_camera()
    pcall(do_force_close_camera)
end

-- 发布预览就绪事件（只发布一次，防止重复触发识别请求）
-- @param ok true=画面已就绪（可并行识别）/ false=预览不可用（业务层需降级为串行识别）
local function publish_preview_ready(ok)
    if ready_published then return end
    ready_published = true
    log.info("face_preview", "发布 FACE_PREVIEW_READY, ok=" .. tostring(ok) .. ", token=" .. tostring(start_gen))
    sys.publish("FACE_PREVIEW_READY", {token = start_gen, ok = ok})
end

-- 预览就绪延迟发布回调（画面出现后再等一会，确保 UART2 人脸模组稳定）
local function publish_ready_delay_cb()
    if not active then return end  -- 期间已停流/关窗，不再通知
    publish_preview_ready(true)
end

-- 摄像头连接回调
local function camera_connected_cb()
    if gen ~= start_gen then return end  -- 已停/已重开，忽略旧回调
    -- 重连成功：取消"断开重连宽限"定时器（本次断开属于断电重枚举的预期行为，不是故障）
    if reconnect_timer then
        sys.timerStop(reconnect_timer)
        reconnect_timer = nil
    end
    connected_once = true  -- 已连接过，后续断开按"运行中掉线"处理，不再触发断电重试
    log.info("face_preview", "摄像头已连接，开始预览")
    if active and widget and not widget:is_destroyed() then
        widget:register()
        widget:start()
    end
    -- 画面已开始刷新 → 延迟一小段时间等 UART2 人脸模组稳定后，再通知业务层可以发起识别
    if not ready_published then
        sys.timerStart(publish_ready_delay_cb, config.get("face.preview.ready_extra_wait", 500))
    end
end

-- 重连宽限超时：断开后一直没能重新连上，才判定预览不可用（通知业务层降级为串行识别）
local function reconnect_timeout_cb()
    reconnect_timer = nil
    if not active then return end         -- 已停流/关窗，无需通知
    if ready_published then return end    -- 已就绪过，属于运行中掉线，不改变业务节奏
    log.warn("face_preview", "断开后 " .. tostring(config.get("face.preview.reconnect_wait", 2500))
        .. "ms 内未重新连接，判定预览不可用")
    publish_preview_ready(false)
end

-- 摄像头断开回调
--   重要：连接监控（camera_connect_watch）可能在"一直未连接"时对 GPIO73 断电重试一次（仅一次），
--         该动作会产生一次 USB 断开事件（status 0x100 → release child port），随后约 1s 内自动重连。
--         这属于预期行为，不能立刻判定"预览失败"，否则会误关预览、白白降级为串行识别（屏幕全黑）。
--   处理策略：
--     0) 从未连接过的断开 → 直接交给连接监控（它会断电重试一次，超时才降级）；
--     1) 尚未就绪时断开 → 启动宽限定时器等自动重连，超时（reconnect_wait）才判失败；
--     2) 已就绪后断开   → 仅记日志、等待重连，不发布失败事件（避免打断正在进行的识别）。
local function camera_disconnected_cb()
    log.warn("face_preview", "摄像头已断开")
    -- 本次预览从未收到 connected → 视为"摄像头未连接"：交给连接监控处理
    -- （它会做一次断电重试，超时才降级；这里不抢先判失败，否则断电重试还没跑就已降级）
    if active and not connected_once then
        log.info("face_preview", "预览尚未就绪即断开（模组未连接），交由连接监控处理")
        return
    end
    if widget and not widget:is_destroyed() then
        widget:stop()
    end
    -- 已停流（关窗/降级）时不再通知，避免影响下一次开窗
    if not active then return end
    if ready_published then
        log.warn("face_preview", "预览运行中断开，等待自动重连（不降级）")
        return
    end
    if reconnect_timer then
        sys.timerStop(reconnect_timer)
    end
    reconnect_timer = sys.timerStart(reconnect_timeout_cb, config.get("face.preview.reconnect_wait", 2500))
    log.info("face_preview", "预览尚未就绪即断开（可能是断电重枚举），等待自动重连")
end

-- 预览事件回调（excamera.preview 回调，按事件分发）
-- 说明：excamera.preview 回调签名为 function(event, ...)，代数判断直接使用模块级 gen
local function preview_event_cb(event, ...)
    if event == "connected" then
        camera_connected_cb()
    elseif event == "frame" then
        -- 拍照留底：按需抓取当前帧（UVC 推流为 MJPEG，单帧即完整 JPEG，可直接存文件）
        --   仅在 capture_pending 置位时才做 toStr 拷贝，平时零开销，
        --   不增加 luat_camera 任务负载，不影响 UART2 人脸识别。
        if gen ~= start_gen then return end  -- 已停/已重开，忽略旧回调
        local buff, len = ...
        if capture_pending and buff and len and len > 0 then
            capture_pending = false
            local ok, data = pcall(buff.toStr, buff, 0, len)
            if ok and data and #data > 0 then
                sys.publish("FACE_PREVIEW_FRAME", data)
            end
        end
    elseif event == "disconnected" then
        camera_disconnected_cb()
    end
end

-- 断电重启模组内部执行（pcall 包装）
local function do_power_cycle_camera()
    gpio.setup(73, 0)
    gpio.set(73, 0)
    sys.wait(400)  -- 断电保持400ms，确保模组完全下电
    gpio.setup(73, 1, gpio.PULLUP)
    gpio.set(73, 1)
    sys.wait(500)  -- 上电后等500ms，让模组完成重新枚举
end

-- 断电重启模组触发 USB 重枚举
local function power_cycle_camera()
    pcall(do_power_cycle_camera)
end

-- 连接监控：等摄像头连接，只有一直未连接才断电重试一次，再超时才判定预览不可用
--   背景：GPIO73 断电会同时切断 UART2 人脸模组电源，进窗就无条件断电重枚举，
--         会让人脸模组每次开窗都掉电重启 → 反复重枚举风暴 → 识别失败 / 系统卡死。
--   策略：进窗后先正常等 connected 事件；只有在 connect_wait 内始终没等到连接，
--         才执行一次 GPIO73 断电重试，再等 retry_wait；仍未连接才通知业务层降级串行。
local function camera_connect_watch(token)
    -- connect_wait 默认 400ms（不是 2500）：模组已上电且枚举过时，preview 注册回调后不会再有
    --   EV_CONNECT，只能靠 GPIO73 断电重枚举触发；等太久就是纯黑屏（实测每次开窗白黑 2.5s）。
    local wait_first = config.get("face.preview.connect_wait", 400)
    local wait_retry = config.get("face.preview.retry_wait", 3000)

    -- 第一次等待：正常情况下 USB 枚举会在这个窗口内给出 connected
    local waited = 0
    while active and token == start_gen and not ready_published and not connected_once do
        if waited >= wait_first then break end
        sys.wait(200)  -- 每200ms检查一次连接状态
        waited = waited + 200
    end
    if not active or token ~= start_gen or ready_published or connected_once then
        if token == start_gen then watch_running = false end
        return
    end

    -- 始终没连上 → 断电重试一次（仅此一次）
    power_retry_done = true
    log.warn("face_preview", "等待 " .. tostring(wait_first) .. "ms 未检测到摄像头连接，执行一次断电重试")
    power_cycle_camera()

    -- 第二次等待：断电重枚举需要时间
    waited = 0
    while active and token == start_gen and not ready_published and not connected_once do
        if waited >= wait_retry then break end
        sys.wait(200)  -- 每200ms检查一次连接状态
        waited = waited + 200
    end
    if token == start_gen then watch_running = false end
    if not active or token ~= start_gen or ready_published or connected_once then return end

    log.warn("face_preview", "断电重试后仍未检测到摄像头连接，判定预览不可用")
    publish_preview_ready(false)  -- 通知业务层降级为串行识别
end

-- 启动连接监控（每轮预览只启动一次）
local function start_connect_watch(token)
    if watch_running then return end
    watch_running = true
    sys.taskInit(camera_connect_watch, token)
end

-- 启动预览的内部协程体
local function start_preview_task(cfg, cam_w, cam_h, fps, mode)
    -- 这里只等待 closing（上次 close 任务）结束，不主动触发新的 close，
    -- 因为当前预览已在 start 主上下文设置 active=true，误 close 会毁掉本次预览。
    wait_closing_done()
    sys.wait(100)  -- 等关闭标记处理完再进入重建流程

    -- 无条件强制 close 一次，兜底旧状态：此时 excamera 内部 preview_active 若为 true 会清理；
    -- 若为 false 则仅清理残留 camera_id（pcall 保护），随后 open 会完整重建。
    force_close_camera()
    sys.wait(100)  -- 等旧数据流彻底释放后再重新 open

    local param = {
        id = camera.USB,
        sensor_width = cam_w,
        sensor_height = cam_h,
        usb_port = 1,
        work_mode = 2,
        save_path = "/ram/preview.jpg",
        fps = fps,
    }
    local ok = excamera.open(param)
    if not ok then
        log.error("face_preview", "excamera.open 失败，预览不可用")
        publish_preview_ready(false)  -- 通知业务层降级为串行识别
        return
    end
    ok = excamera.preview(preview_event_cb)
    if not ok then
        log.error("face_preview", "excamera.preview 失败")
        excamera.close()
        publish_preview_ready(false)  -- 通知业务层降级为串行识别
        return
    end

    -- 背景：pm.power(pm.USB,false/true) 只控制 USB VBUS，无法重启已上电模组；
    --       仅开机后第一次进刷脸窗口时模组从无电到有电会触发枚举；
    --       之后（第二次存件/取件）模组已上电并枚举过 → preview 注册回调后不会再有新枚举 → 黑屏。
    -- 因此启动连接监控（camera_connect_watch）：先等 connected 事件，一直等不到才断电重试一次；
    --       GPIO73 同时供 UART2 人脸模组，若进窗就无条件断电，会让人脸模组每次开窗都掉电重启
    --       → 反复重枚举风暴 → 识别失败 / 系统卡死，故改为"仅在未连接时重试一次"。
    -- 时序（关键）：断电重试必须在 excamera.preview【之后】执行！preview 内部已注册 usb_raw 回调，
    --       GPIO73 断电重启模组 → 模组重新枚举产生的 EV_CONNECT 事件发生在回调注册之后 → 不丢失。
    --       若在 preview 之前重启，枚举在回调注册前完成 → EV_CONNECT 丢失 → 依然黑屏。
    log.info("face_preview", "预览启动，mode=" .. tostring(mode) .. ", closing=" .. tostring(closing))
    -- 不再无条件断电重枚举：进窗先正常等 connected 事件，
    -- 只有连接监控发现"一直未连接"时才执行一次 GPIO73 断电重试（见 camera_connect_watch）
    start_connect_watch(start_gen)
end

-- 启动预览（进刷脸窗口时调用）
-- @param mode 窗口模式："deposit"/"receive"（仅记录日志用；不再进窗就强制断电重枚举）
function M.start(parent, x, y, w, h, mode)
    --    不能因 active=true 短路 return，否则第二次进窗口永远黑屏。
    --    这里直接重建：active 会被下方重置；taskInit 内 stop_wait 会等待旧 close 完成。
    --    旧 widget 若仍存活先销毁，避免 airui.camera 全局单实例冲突；
    --    但上一次 close 还在进行（数据流没停）时不要在这里销毁 —— 交给 close_camera_flow 按引用销毁。
    if not closing then
        destroy_old_widget()
    end
    -- 清理上一轮的"断开重连宽限"定时器，避免旧定时器影响本次预览
    if reconnect_timer then
        sys.timerStop(reconnect_timer)
        reconnect_timer = nil
    end
    local cfg = config.get("face.preview", {})
    if not cfg.enabled then return false end

    -- 注意：airui.camera 组件（AirUI V1.2.4 起提供）目前只支持 x/y/w/h/fit/auto_start/parent，
    --       既不支持 rotation 参数，组件对象也没有 set_rotation 方法（只有 register/start/stop/
    --       destroy/is_destroyed），因此画面方向无法在软件层旋转：只能通过物理旋转摄像头安装方向，
    --       或由原厂固件给 airui.camera 新增旋转能力来解决。
    --    旋转说明：airui.camera 组件的公开文档只列出 x/y/w/h/auto_start/parent，
    --    但实测日志显示未文档化的 fit 参数实际生效（fit=2 software），说明文档不全，
    --    因此此处把 rotation 直通传入做验证：若固件已支持则画面立即旋转，不支持则被忽略（无害）。
    local rotate = cfg.rotation or 0
    widget = airui.camera({
        parent = airui.screen,
        x = x, y = y, w = w, h = h,
        fit = cfg.fit or "cover",
        auto_start = false,
        rotation = rotate,
    })
    log.info("face_preview", "预览旋转参数直通=" .. tostring(rotate) .. "（0=不旋转，90=顺时针90度），组件是否支持以实机画面为准")
    if not widget then
        log.error("face_preview", "airui.camera 组件创建失败")
        return false
    end

    gen = gen + 1
    start_gen = gen
    active = true
    ready_published = false  -- 新一轮预览，重置就绪标记
    connected_once = false   -- 新一轮预览，重置"是否连接过"
    power_retry_done = false -- 新一轮预览，允许一次断电重试
    watch_running = false    -- 允许启动本轮新的连接监控

    local cam_w = cfg.width or 320
    local cam_h = cfg.height or 240
    local fps = cfg.fps or 10
    -- 并行识别模式下压低预览帧率：把 CPU 让给 UART2 人脸数据，避免识别超时
    local face_mode = config.get("face.preview.mode", "auto")
    if face_mode ~= "serial" then
        fps = cfg.busy_fps or fps
    end
    log.info("face_preview", "预览帧率=" .. tostring(fps) .. "，识别模式=" .. tostring(face_mode))

    sys.taskInit(start_preview_task, cfg, cam_w, cam_h, fps, mode)
    return true
end

-- 获取当前预览就绪令牌（业务层校验 FACE_PREVIEW_READY 是否属于本次预览，防跨窗误触发）
function M.get_ready_token()
    return start_gen
end

-- 关闭预览数据流 + 销毁显示组件（pcall 保护）
-- 【顺序很关键·死机修复】必须"先停数据流、再销毁显示组件"：
--   1) 先等一帧时间（close_grace）：让在途帧回调跑完 —— excamera.close() 内部会
--      frame_buff0/1:free()，若此刻帧回调正在读这两块 zbuff → use-after-free。
--   2) excamera.close()：preview_active=false（usb_raw 回调立即 return）+
--      camera.preview(USB,false) + camera.close(app_id) 停掉推流与解码管线。
--   3) 再等 100ms 让固件解码/显示任务把在途帧处理完。
--   4) 最后才 widget:stop()/destroy()。
--   反过来（先 widget:stop/destroy 再 close）会造成"组件已销毁、固件还在往组件里画"，
--   日志特征：pc 14137db0（固件 app 段）/ pc 20006572（IRAM）"企图执行非对齐访问" → 死机重启。
-- @param w 本次要销毁的 airui.camera 组件（按引用销毁，避免误删新窗口刚建的组件）
local function close_camera_flow(w)
    local grace = config.get("face.preview.close_grace", 400)
    if type(grace) == "number" and grace > 0 then
        sys.wait(grace)
    end
    pcall(excamera.close)   -- ① 停推流：preview_active=false → usb_raw 回调直接 return，并释放双缓冲
    sys.wait(100)           -- ② 等固件解码/显示任务把在途帧收尾
    if w and not w:is_destroyed() then
        pcall(function()    -- ③ 流已停，销毁组件才安全
            w:stop()
            w:destroy()
        end)
    end
    if widget == w then widget = nil end
    closing = false
    log.info("face_preview", "预览已停止，数据流已释放")
end

-- 拍照留底：抓取下一帧 JPEG 画面（预览推流中调用，stop() 之前有效；必须在任务/协程内使用）
--   内部含 sys.waitUntil，不能在定时器回调等非协程上下文调用。
-- @param timeout 等待画面超时(ms)，默认2000
-- @return ok, data  成功返回 true 和 JPEG 字符串；失败返回 false 和原因
function M.capture(timeout)
    if not active then
        return false, "预览未启动"
    end
    if capture_pending then
        return false, "上次拍照尚未完成"
    end
    -- 防御：timeout 必须是正数，否则 sys.waitUntil 内 timer_start 会抛错，
    -- 并把 FACE_PREVIEW_FRAME 订阅泄漏到本协程（协程结束后 publish 会崩溃）
    if type(timeout) ~= "number" or timeout <= 0 then timeout = 2000 end
    capture_pending = true
    local ok, data
    local pok, perr = pcall(function()
        ok, data = sys.waitUntil("FACE_PREVIEW_FRAME", timeout)
    end)
    if not pok then
        capture_pending = false  -- 关键：异常时必须复位，否则下次帧到达会误 publish 到死协程
        return false, tostring(perr)
    end
    if not ok then
        capture_pending = false
        return false, "等待摄像头画面超时"
    end
    if type(data) ~= "string" or #data == 0 then
        return false, "画面数据为空"
    end
    return true, data
end

-- 停止预览（关窗时调用；只停流，不断电USB —— 模组是USB供电，断电会杀掉UART2人脸识别）
--   注意：这里【不销毁】airui.camera 组件，交给 close_camera_flow 在数据流停掉之后销毁：
--   组件先销毁 = 固件解码/显示管线还在往已释放的组件里画 → 非对齐访问死机。
function M.stop()
    if not active then return end
    active = false
    ready_published = false  -- 停流后禁止再发布就绪事件
    gen = gen + 1  -- 使进行中的旧回调失效
    if reconnect_timer then
        sys.timerStop(reconnect_timer)
        reconnect_timer = nil
    end
    local w = widget          -- 记住本次要销毁的组件（期间若被新 start 替换，不会误删新组件）
    closing = true
    sys.taskInit(close_camera_flow, w)
end

-- 强制停止并等待预览数据流完全关闭（避免上次预览未释放 → 下次 start 状态残留 → 黑屏）
-- 与 stop() 不同：即使 active 已 false 也等待进行中的 close 完成；返回后 USB 状态干净。
function M.stop_wait()
    if not active and not closing then return end
    if active then
        active = false
        ready_published = false  -- 停流后禁止再发布就绪事件
        gen = gen + 1
        if reconnect_timer then
            sys.timerStop(reconnect_timer)
            reconnect_timer = nil
        end
        local w = widget         -- 同上：组件由 close_camera_flow 在停流后销毁
        closing = true
        sys.taskInit(close_camera_flow, w)
    end
    -- 等待 close 完成
    local t = 0
    while closing and t < 3000 do
        sys.wait(50)  -- 每50ms检查一次关闭状态
        t = t + 50
    end
    sys.wait(100)  -- 等USB栈稳定后再返回
    log.info("face_preview", "stop_wait 完成，closing=" .. tostring(closing))
end

-- 同步等待预览数据流完全关闭（复位人脸模组前调用，避免与残留 USB 回调竞争）
-- 说明：stop() 释放数据流是异步的（sys.taskInit），若立即复位模组（MID_RESET→USB重枚举），
--       残留回调/未释放缓冲会与复位竞争 → use-after-free → 非对齐访问崩溃。
-- 最多等待 1500ms，超时不再阻塞，交由 excamera.close 的 pcall 兜底。
function M.wait_closed(timeout)
    local t = 0
    while closing and t < (timeout or 1500) do
        sys.wait(50)  -- 每50ms检查一次关闭状态
        t = t + 50
    end
    -- 再留 100ms 让 USB 栈稳定（注销回调/释放 zbuff 生效）
    sys.wait(100)
end

-- 当前是否有关闭正在进行（供调用方判断）
function M.is_closing()
    return closing
end

-- 当前预览是否处于激活状态（供业务层判断能否并行识别）
function M.is_active()
    return active
end

return M
