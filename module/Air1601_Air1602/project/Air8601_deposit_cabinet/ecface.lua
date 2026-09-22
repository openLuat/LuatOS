--[[
@module  ecface
@summary 刷脸存件/取件界面模块
@version 1.1 (同步参考版深蓝风格 UI，逻辑不变)
@date    2026.09.18
@author  王城钧
@usage
刷脸存件（人脸注册）：订阅 OPEN_FACE_DEPOSIT_WIN
刷脸取件（人脸验证）：订阅 OPEN_FACE_RECEIVE_WIN
人脸状态提示：订阅 FACE_STATE_UPDATE
预览就绪事件：订阅 FACE_PREVIEW_READY（face_preview 在画面真正就绪后发布）

人脸识别与预览并行（config.face.preview.mode）：
- serial      ：停流 → 复位模组 → 识别（原逻辑，可回退）
- auto        ：预览不停流直接识别；失败自动降级为 serial 重试一次（推荐）
- concurrent  ：一律并行，失败不降级
说明：本文件的界面风格、拍照留底（face_photo）、业务逻辑与原来完全一致，
     只把"固定等 3 秒后停流再识别"改为"等画面就绪事件 → 预览不停流直接识别"。
]]

local config = require "config"

-- 预览时长（ms）：显示摄像头画面多久后自动停止预览并发起人脸注册/验证
-- 可在 config.face.preview.capture_delay 调整（默认 3000，与原固定 3 秒一致）
local preview_delay = config.get("face.preview.capture_delay", 3000)
local preview_sec = math.floor(preview_delay / 1000)

local win_id = nil
local main_container = nil
local screen_w, screen_h = 1024, 600
local current_mode = nil      -- "deposit" / "receive"
local status_label = nil      -- 人脸状态提示标签
local tip_label = nil         -- 操作提示标签
local current_result_modal = nil
local busy = false            -- 业务处理中标记（防止重复触发）
local done_flag = false       -- 业务结果是否已处理（防重复弹窗）
local pending_mode = nil      -- 等待人脸模块初始化完成后继续的窗口模式（deposit/receive）
local pending_timer = nil     -- 初始化等待超时定时器
local face_task_timer = nil   -- 业务任务超时兜底定时器
local task_seq = 0            -- 业务任务序号（防旧任务结果误用）
local preview_x, preview_y = 0, 0   -- 摄像头预览区域位置
local preview_w, preview_h = 0, 0   -- 摄像头预览区域尺寸
local preview_started_flag = false  -- 本次窗口预览是否成功启动（供初始化完成后判断走并行还是串行）
-- 人脸识别与预览并行相关状态
local preview_token = 0        -- 本次预览的就绪令牌（校验 FACE_PREVIEW_READY 是否属于本次预览）
local preview_ready_flag = false -- 本次预览是否已收到就绪事件（可能早于人脸模块初始化完成）
local preview_ready_ok = true  -- 就绪事件结果：true=画面可用 / false=预览不可用需降级
local preview_ready_timer = nil -- 等待预览就绪 / 延迟发起识别的定时器
local face_started = false     -- 本次窗口是否已发起识别（防重复发起）
local parallel_inflight = false -- 当前识别是否运行在并行模式（预览未停流）
local serial_retry_used = false -- 是否已降级重试过（降级只做一次）
local start_face_operation    -- 前向声明：on_create 的定时器回调先于函数体声明，需先声明避免解析成全局 nil
local try_serial_retry        -- 前向声明：并行识别失败后的降级重试（函数体定义在文件后部，供结果回调调用）
local stop_preview_after_face -- 前向声明：识别出结果后立即停流（函数体定义在文件后部，供结果回调调用）

local function update_screen_size()
    local rotation = airui.get_rotation()
    local phys_w, phys_h = lcd.getSize()
    if rotation == 0 or rotation == 180 then
        screen_w, screen_h = phys_w, phys_h
    else
        screen_w, screen_h = phys_h, phys_w
    end
end

-- 统一更新界面状态文字（只在主消息上下文调用，避免任务里操作 UI 卡死）
local function update_ui(status_text, tip_text)
    if status_label then
        status_label:set_text(status_text or "请正对摄像头")
    end
    if tip_label then
        tip_label:set_text(tip_text or "")
    end
end

-- 显示结果弹窗（确定后关闭当前窗口）
local function show_result_dialog(success, title_text, content_text)
    -- 销毁之前的弹窗
    if current_result_modal then
        current_result_modal:destroy()
        current_result_modal = nil
    end

    local density = _G.density_scale or 1

    local result_modal = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0x000000,
        opacity = 0.35   -- 原 0.6 太黑，观感像"屏幕变黑"，改为 0.35 只轻微变暗
    })

    local result_content = airui.container({
        parent = result_modal,
        x = math.floor((screen_w - math.floor(340 * density)) / 2),
        y = math.floor((screen_h - math.floor(240 * density)) / 2),
        w = math.floor(340 * density),
        h = math.floor(240 * density),
        color = 0x0F2547,
        radius = math.floor(10 * density)
    })

    airui.label({
        parent = result_content,
        x = 0, y = math.floor(30 * density),
        w = math.floor(340 * density),
        h = math.floor(30 * density),
        text = title_text or "",
        font_size = math.floor(20 * density),
        color = success and 0x28A745 or 0xD32F2F,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 600
    })

    airui.label({
        parent = result_content,
        x = math.floor(20 * density),
        y = math.floor(70 * density),
        w = math.floor(300 * density),
        h = math.floor(100 * density),
        text = content_text or "",
        font_size = math.floor(14 * density),
        color = 0xB8C6D9,
        align = airui.TEXT_ALIGN_CENTER,
    })

    airui.button({
        parent = result_content,
        x = math.floor(95 * density),
        y = math.floor(180 * density),
        w = math.floor(150 * density),
        h = math.floor(45 * density),
        text = "确定",
        style = {
            bg_color = 0x4A90E2,
            text_color = 0xFFFFFF,
            radius = math.floor(5 * density),
            font_size = math.floor(16 * density),
            font_weight = 600
        },
        on_click = function()
            result_modal:destroy()
            current_result_modal = nil
            busy = false
            exwin.close(win_id)
        end
    })

    current_result_modal = result_modal
end

-- 创建界面
local function create_ui()
    update_screen_size()
    local density = _G.density_scale or 1

    main_container = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0x0A1E3A
    })

    -- 顶部导航栏
    local header_h = math.floor(60 * density)
    local header = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = header_h,
        color = 0x4A90E2,
    })

    -- 标题
    airui.label({
        parent = header,
        text = (current_mode == "deposit") and "刷脸存件" or "刷脸取件",
        x = 0,
        y = math.floor((header_h - 28 * density) / 2),
        w = screen_w,
        h = math.floor(28 * density),
        font_size = math.floor(24 * density),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 600,
    })

    -- 摄像头预览区域（airui.camera 组件，face_preview 在其上创建）
    -- 视口用较小尺寸，降低 airui.camera 软件缩放 + LVGL 渲染负载，避免 "preview wait too much" 冻结
    preview_w = math.floor(480 * density)
    preview_h = math.floor(270 * density)
    preview_x = math.floor((screen_w - preview_w) / 2)
    preview_y = header_h + math.floor(15 * density)

    airui.container({
        parent = main_container,
        x = preview_x, y = preview_y,
        w = preview_w, h = preview_h,
        color = 0x000000,
        radius = math.floor(10 * density),
    })

    -- 人脸状态提示（状态文字）
    status_label = airui.label({
        parent = main_container,
        text = "请正对摄像头",
        x = 0,
        y = preview_y + preview_h + math.floor(12 * density),
        w = screen_w,
        h = math.floor(32 * density),
        font_size = math.floor(20 * density),
        color = 0x3FA9F5,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 600,
    })

    -- 操作提示（并行模式下不再"等固定秒数"，画面就绪后自动发起识别，故提示不说秒数）
    local tip_text = "请正对摄像头，保持不动\n即将自动开始人脸录入"
    if current_mode ~= "deposit" then
        tip_text = "请正对摄像头，保持不动\n即将自动开始人脸验证"
    end
    tip_label = airui.label({
        parent = main_container,
        text = tip_text,
        x = math.floor(60 * density),
        y = preview_y + preview_h + math.floor(50 * density),
        w = screen_w - math.floor(120 * density),
        h = math.floor(50 * density),
        font_size = math.floor(14 * density),
        color = 0x999999,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 底部取消按钮
    airui.button({
        parent = main_container,
        x = math.floor((screen_w - math.floor(200 * density)) / 2),
        y = screen_h - math.floor(70 * density),
        w = math.floor(200 * density),
        h = math.floor(50 * density),
        text = "取消",
        style = {
            bg_color = 0x0F2547,
            pressed_bg_color = 0x1F3A60,
            text_color = 0xFFFFFF,
            radius = math.floor(7 * density),
            font_size = math.floor(15 * density),
            font_weight = 600,
        },
        on_click = function()
            exwin.close(win_id)
        end
    })
end

-- 处理注册结果（存件模式：录入人脸 → 分配柜子 → 开柜 → 绑定）
local function on_register_result(data)
    if current_mode ~= "deposit" then return end
    if busy then return end
    stop_preview_after_face()  -- 识别已有结果，立刻停流（降低关窗时释放 UVC 的崩溃概率）

    if data.success then
        busy = true
        done_flag = false
        task_seq = task_seq + 1
        local my_seq = task_seq
        update_ui("识别成功", "正在分配柜子，请稍候...\n可点返回/取消退出")
        -- 超时兜底：业务任务 12 秒内未完成则判定失败，避免界面卡死无法返回
        if face_task_timer then
            sys.timerStop(face_task_timer)
            face_task_timer = nil
        end
        face_task_timer = sys.timerStart(function()
            face_task_timer = nil
            sys.publish("FACE_DEPOSIT_DONE", {success = false, error = "操作超时，请重试", seq = my_seq})
        end, 12000)
        -- 业务逻辑跑在独立任务，只通过消息回传结果，不在此处操作 UI
        sys.taskInit(function()
            local ok, dep_ok, dep_result = pcall(function()
                local ecbusiness = require "ecbusiness"
                return ecbusiness.face_deposit(data.user_id, data.name)
            end)
            if not ok then
                sys.publish("FACE_DEPOSIT_DONE", {success = false, error = tostring(dep_ok), seq = my_seq})
            elseif dep_ok then
                sys.publish("FACE_DEPOSIT_DONE", {success = true, result = dep_result, seq = my_seq})
            else
                sys.publish("FACE_DEPOSIT_DONE", {success = false, error = tostring(dep_result), seq = my_seq})
            end
        end)
    else
        -- 并行模式识别失败：自动降级为串行（停流+复位）重试一次，保证功能不失效
        if try_serial_retry() then
            return
        end
        show_result_dialog(false, "录入失败", data.error or "请重试")
    end
end

-- 处理验证结果（取件模式：验证人脸 → 查绑定柜 → 开柜 → 解绑）
local function on_verify_result(data)
    if current_mode ~= "receive" then return end
    if busy then return end
    stop_preview_after_face()  -- 识别已有结果，立刻停流（降低关窗时释放 UVC 的崩溃概率）

    if data.success then
        if data.box_num then
            busy = true
            done_flag = false
            task_seq = task_seq + 1
            local my_seq = task_seq
            update_ui("验证成功", "正在打开柜门，请稍候...\n可点返回/取消退出")
            -- 超时兜底
            if face_task_timer then
                sys.timerStop(face_task_timer)
                face_task_timer = nil
            end
            face_task_timer = sys.timerStart(function()
                face_task_timer = nil
                sys.publish("FACE_VERIFY_DONE", {success = false, error = "操作超时，请重试", seq = my_seq})
            end, 12000)
            -- 业务逻辑跑在独立任务，通过消息回传结果
            sys.taskInit(function()
                local ok, pk_ok, pk_result = pcall(function()
                    local ecbusiness = require "ecbusiness"
                    return ecbusiness.face_pickup(data.user_id)
                end)
                if not ok then
                    sys.publish("FACE_VERIFY_DONE", {success = false, error = tostring(pk_ok), seq = my_seq})
                elseif pk_ok then
                    sys.publish("FACE_VERIFY_DONE", {success = true, result = pk_result, seq = my_seq})
                else
                    sys.publish("FACE_VERIFY_DONE", {success = false, error = tostring(pk_result), seq = my_seq})
                end
            end)
        else
            show_result_dialog(false, "取件失败", "该用户未绑定柜子")
        end
    else
        -- 并行模式验证失败：同样自动降级为串行重试一次（避免并行负载导致取件主路径不可用）
        if try_serial_retry() then
            return
        end
        show_result_dialog(false, "验证失败", data.error or "请重试")
    end
end

-- 人脸状态更新（来自 face_manager 的 on_state 回调）
local function on_face_state(data)
    if not status_label then return end
    if current_mode == nil then return end
    status_label:set_text(data.message or "请正对摄像头")
end

-- 【拍照留底】预览推流中抓取一帧 JPEG（任务/协程内调用；stop() 之后帧事件即消失）
-- @return string|nil JPEG 数据
local function capture_photo()
    -- 注意：face_preview.capture 是普通函数(非方法)，不能用 pcall(fn, self, ...) 形式
    -- 传 self 会让 timeout 收到 table → sys.waitUntil 内 timer_start 抛错 →
    -- FACE_PREVIEW_FRAME 订阅泄漏到已死亡协程 → 下次 publish 时 "cannot resume dead coroutine" 崩溃
    local cfg_ok, photo_cfg = pcall(function()
        return config.get("face.photo", {})
    end)
    if not cfg_ok or type(photo_cfg) ~= "table" or photo_cfg.enabled == false then
        return nil
    end
    local cap_ok, cap_ret, cap_data = pcall(function()
        local face_preview = require "face_preview"
        return face_preview.capture(photo_cfg.timeout or 2000)
    end)
    if cap_ok and cap_ret then
        return cap_data
    end
    log.warn("ecface", "拍照留底抓帧失败:", tostring(cap_ok and cap_data or cap_ret))
    return nil
end

-- 【拍照留底】把抓到的 JPEG 写入存储卡（pcall 保护，失败不影响识别主流程）
local function save_photo(photo_data)
    if not photo_data then return end
    pcall(function()
        local face_photo = require "face_photo"
        local ok, path_or_err = face_photo.save(photo_data, current_mode)
        if ok then
            log.info("ecface", "拍照留底完成", path_or_err)
        else
            log.warn("ecface", "拍照留底保存失败:", tostring(path_or_err))
        end
    end)
end

-- 停止摄像头预览（pcall 保护）
local function stop_preview_safe()
    pcall(function()
        local face_preview = require "face_preview"
        face_preview.stop()
    end)
end

-- 等待预览数据流完全关闭（pcall 保护）：
--   stop() 释放数据流是异步的，若立即 MID_RESET → AirCAMERA 重启 → USB 重枚举，
--   残留回调/未释放 zbuff 会与之竞争 → use-after-free → 非对齐访问崩溃（死机）。
local function wait_preview_closed()
    pcall(function()
        local face_preview = require "face_preview"
        face_preview.wait_closed()
    end)
end

-- 复位人脸模组（pcall 保护）：
--   预览(UVC)会把模组传感器留在 UVC 模式，register(录入新脸)会因传感器切不回人脸模式而超时
--   （verify 不受影响）。复位后传感器回到人脸模式。
local function reset_face_module()
    pcall(function()
        local face_manager = require "face_manager"
        face_manager.reset_module()
    end)
end

-- 发起人脸注册/验证请求（并行模式下预览不停流；串行/降级路径下预览已停止）
local function publish_face_request()
    log.info("ecface", "发起人脸", current_mode)
    if current_mode == "deposit" then
        local name = "user_" .. tostring(os.time())
        sys.publish("FACE_REGISTER_REQ", {name = name, admin = false})
    elseif current_mode == "receive" then
        sys.publish("FACE_VERIFY_REQ", {})
    end
end

-- 识别已有结果（成功/失败）后立刻停流
--   为什么不等关窗再停：实测 3 次“企图执行非对齐访问 pc 20006572”都发生在
--   “识别成功 → 结果弹窗 → 点确定关窗 → on_destroy 里 face_preview.stop()”那一刻，
--   此时 UI 销毁 + LVGL 重绘 + exwin 窗口切换同时进行，容易撞上 excamera 释放数据流的残留回调。
--   把停流提前到“识别出结果”这个 CPU 空闲、界面稳定的时刻，关窗时 stop() 自然变成 no-op。
stop_preview_after_face = function()
    if not preview_started_flag then return end
    preview_started_flag = false
    sys.taskInit(function()
        stop_preview_safe()
        wait_preview_closed()
        log.info("ecface", "识别结束，预览已停止（释放CPU、避开关窗时释放UVC）")
    end)
end

-- 窗口创建回调
-- 串行路径：停止摄像头预览 → 复位模组 → 发起人脸操作
--   UVC 摄像头流会占满 luat_camera 任务 CPU（"preview wait too much / no free event"），
--   导致红外 UART2 处理不过来 → 注册/验证超时失败，故必须先停摄像头释放CPU再发起识别。
--   并行模式（config.face.preview.mode ~= "serial"）下本函数只用于"预览不可用 / 并行识别失败"的降级。
--   注意：capture() 与 reset() 内含 sys.waitUntil，必须在任务里调用，
--         故停预览与复位也从定时器回调移入任务：先抓帧（预览仍在推流），再停流释放CPU。
start_face_operation = function()
    face_started = true       -- 标记已发起识别，防止就绪事件重复触发
    parallel_inflight = false -- 本路径为串行模式（识别期间预览已停流）
    sys.taskInit(function()
        -- 【拍照留底】预览仍在推流时抓取一帧 JPEG（下一帧到达即返回，一般≤200ms；
        --   停止预览后帧事件即消失，所以必须放在 stop() 之前）
        local photo_data = capture_photo()
        -- 停止摄像头预览（原逻辑：UVC 流占满 luat_camera 任务 CPU，必须先停流释放CPU）
        stop_preview_safe()
        wait_preview_closed()
        -- 【拍照留底】预览已停止、CPU 已释放，此时把照片写入SD卡，不与识别抢CPU
        save_photo(photo_data)
        reset_face_module()
        log.info("ecface", "摄像头已停止，发起人脸", current_mode)
        publish_face_request()
    end)
end

-- ==================== 人脸识别与预览并行支持 ====================
-- 说明：并行模式下预览不停流、不复位人脸模组，直接发起 register/verify；
--       发起前必须先等到 FACE_PREVIEW_READY（画面真正刷新的信号），避免预览未连上就抢跑；
--       识别失败时自动降级为"停流 → 复位模组 → 重发"的串行路径重试一次，保证功能不失效。

-- 读取并行识别模式配置（serial/auto/concurrent）
local function get_preview_mode()
    return config.get("face.preview.mode", "auto") or "auto"
end

-- 并行发起识别协程：抓帧留底 → 不停流不复位模组，直接发起识别（画面持续刷新）
local function parallel_face_task()
    if current_mode == nil then return end  -- 窗口已关闭
    -- 【拍照留底】预览仍在推流时抓一帧；并行模式下预览不停流，所以立刻写卡（不再等停流）
    save_photo(capture_photo())
    if current_mode == nil then return end
    publish_face_request()
end

-- 并行模式发起识别：不停流、不复位模组
local function start_face_operation_parallel()
    if face_started then return end
    if get_preview_mode() == "serial" then
        -- 串行模式：完全走原逻辑（停流 → 复位 → 识别）
        log.info("ecface", "识别模式=serial，停流后发起识别")
        start_face_operation()
        return
    end
    face_started = true
    parallel_inflight = true
    serial_retry_used = false
    update_ui("正在识别", "请正对摄像头，保持不动")
    log.info("ecface", "并行模式发起人脸识别，mode=" .. tostring(get_preview_mode()) .. "，预览不停流")
    sys.taskInit(parallel_face_task)
end

-- 就绪延迟到点：发起识别（定时器回调，禁止 yield）
local function preview_ready_start_cb()
    preview_ready_timer = nil
    if current_mode == nil then return end
    if face_started then return end
    start_face_operation_parallel()
end

-- 按预览就绪结果安排发起识别（ok=false 表示预览不可用，直接降级串行）
local function schedule_face_start(ok)
    if current_mode == nil then return end
    if face_started then return end
    if preview_ready_timer then
        sys.timerStop(preview_ready_timer)
        preview_ready_timer = nil
    end
    if ok == false then
        log.warn("ecface", "预览不可用，降级为串行识别")
        start_face_operation()
        return
    end
    -- 画面已就绪：再留一点时间让用户对准摄像头，随后自动发起识别
    preview_ready_timer = sys.timerStart(preview_ready_start_cb, config.get("face.preview.start_delay", 1500))
end

-- 等待预览就绪超时兜底：超时按串行识别处理，避免界面卡死
local function preview_ready_timeout_cb()
    preview_ready_timer = nil
    if current_mode == nil then return end
    if face_started then return end
    log.warn("ecface", "等待预览就绪超时，降级为串行识别")
    start_face_operation()
end

-- 串行降级重试任务：停流 → 等关闭 → 复位模组 → 重新发起识别
local function serial_retry_task()
    if current_mode == nil then return end  -- 窗口已关闭，无需重试
    stop_preview_safe()
    wait_preview_closed()
    reset_face_module()
    if current_mode == nil then return end
    log.info("ecface", "串行降级重试，重新发起人脸", current_mode)
    publish_face_request()
end

-- 并行识别失败后的降级重试（只重试一次，避免死循环）
-- @return boolean true=已触发降级重试（本次结果由重试流程接管，调用方不再弹窗）
function try_serial_retry()
    if not parallel_inflight then return false end          -- 串行结果不做降级
    if serial_retry_used then return false end              -- 已重试过
    if not config.get("face.preview.retry_serial", true) then return false end
    serial_retry_used = true
    parallel_inflight = false
    log.warn("ecface", "并行识别失败，降级为串行识别并重试一次")
    update_ui("正在重新识别", "请保持正对摄像头，请稍候...")
    sys.taskInit(serial_retry_task)
    return true
end

-- 启动预览并记录本次就绪令牌（pcall 保护）
-- @return boolean 预览是否成功启动
local function start_preview_only()
    preview_ready_flag = false  -- 新一轮预览，重置就绪标记
    preview_ready_ok = true
    local started = false
    if main_container and preview_w > 0 and preview_h > 0 then
        local ok_preview, res = pcall(function()
            local face_preview = require "face_preview"
            return face_preview.start(main_container, preview_x, preview_y, preview_w, preview_h, current_mode)
        end)
        if not ok_preview then
            log.warn("ecface", "启动摄像头预览异常:", res)
        else
            started = res and true or false
        end
    end
    if started then
        local ok_token, token = pcall(function()
            local face_preview = require "face_preview"
            return face_preview.get_ready_token()
        end)
        if ok_token and token then
            preview_token = token
        end
        log.info("ecface", "预览已启动，token=" .. tostring(preview_token) .. "，等待就绪事件")
    end
    preview_started_flag = started
    return started
end

-- 开始等待预览就绪（人脸模块就绪后调用；就绪事件可能已提前到达）
local function wait_preview_ready()
    if current_mode == nil then return end
    if face_started then return end
    if not preview_started_flag then
        -- 预览未成功启动（未开启/组件创建失败）：直接走串行识别
        log.info("ecface", "预览未启动，直接走串行识别")
        start_face_operation()
        return
    end
    if preview_ready_flag then
        -- 就绪事件早于"人脸模块就绪/窗口创建完成"到达，直接安排发起识别
        schedule_face_start(preview_ready_ok)
        return
    end
    if preview_ready_timer then
        sys.timerStop(preview_ready_timer)
        preview_ready_timer = nil
    end
    preview_ready_timer = sys.timerStart(preview_ready_timeout_cb, config.get("face.preview.ready_timeout", 6000))
end

-- 预览就绪事件回调（face_preview 在画面真正刷新后发布）
local function on_preview_ready(data)
    if current_mode == nil then return end   -- 窗口已关闭
    if face_started then return end          -- 已发起过识别
    -- 令牌校验：只接受本次预览发布的就绪事件，防旧预览误触发新窗口识别
    if data and data.token and data.token ~= preview_token then
        log.warn("ecface", "忽略过期预览就绪事件 token=" .. tostring(data.token)
            .. "，当前 token=" .. tostring(preview_token))
        return
    end
    preview_ready_flag = true
    preview_ready_ok = (data == nil) or (data.ok ~= false)
    log.info("ecface", "收到预览就绪事件，ok=" .. tostring(preview_ready_ok))
    -- 人脸模块未就绪时先记录就绪状态，等 FACE_INIT_RESULT 后再安排识别
    local face_manager = require "face_manager"
    local status_ok, status = pcall(function()
        return face_manager.get_status()
    end)
    if not status_ok or not status or not status.ready then
        log.info("ecface", "人脸模块尚未就绪，暂不发起识别（已记录预览就绪）")
        return
    end
    schedule_face_start(preview_ready_ok)
end

local function on_create()
    -- pcall 保护：create_ui 异常时避免窗口异常关闭退回主界面
    local ok, err = pcall(create_ui)
    if not ok then
        log.error("ecface", "创建刷脸界面失败:", err)
        show_result_dialog(false, "界面初始化失败", tostring(err))
        return
    end
    -- 【死机修复】人脸模组未就绪时不要启动 UVC 预览：
    --   预览启动后再关闭会走 excamera.close() 的残留回调竞争 → use-after-free →
    --   非对齐访问崩溃（日志：紧跟"预览已停止，数据流已释放"之后出现 pc 20006572）。
    --   这里只做"人脸没就绪时不创建 UVC 数据流"，人脸失败提示/重试/超时逻辑一律不变。
    local face_mgr_check = require "face_manager"
    local ready_ok, ready_status = pcall(function()
        return face_mgr_check.get_status()
    end)
    local face_ready_now = (ready_ok and ready_status and ready_status.ready) and true or false

    -- 启动摄像头预览（独立协程初始化，失败不影响人脸识别）
    -- 并行模式下预览在识别期间持续刷新，故启动后不再定时停流（改为等 FACE_PREVIEW_READY）
    if face_ready_now then
        start_preview_only()
    end
    -- GPIO38 同时是 I2C1 的 SDA（触摸屏 GT911 所在总线），重新 gpio.setup(38) 会把
    -- SDA 从 I2C 复用功能切回普通 GPIO 输出，导致触摸屏 i2c_failed 无应答/传输超时、无法触摸。
    -- 背光真身是 PIN43/GPIO13，由 lcd_hx8282_10in.lua 的 pins.setup(43,"GPIO13") +
    -- hardware.power_on 的 { pin = 43, level = 1 } 负责，无需在这里重复设置。
    -- 打开窗口后发布人脸请求（先检查初始化状态，避免时序竞态：初始化未完成时点击会报"未初始化"）
    local face_manager = require "face_manager"
    -- 防御性保护：get_status 异常时不至于让窗口创建回调崩溃导致黑屏退回主界面
    local status_ok, status = pcall(function()
        return face_manager.get_status()
    end)
    if not status_ok or not status or not status.ready then
        -- 人脸模块尚未初始化完成：显示等待提示，等 FACE_INIT_RESULT 后自动继续
        if status_label then
            status_label:set_text("正在初始化人脸模块...")
        end
        if tip_label then
            tip_label:set_text("人脸识别摄像头初始化中，请稍候（约" .. preview_sec .. "秒）")
        end
        pending_mode = current_mode
        -- 超时保护：10 秒内未收到初始化结果则提示失败，避免窗口卡死
        if pending_timer then
            sys.timerStop(pending_timer)
            pending_timer = nil
        end
        pending_timer = sys.timerStart(function()
            pending_timer = nil
            if pending_mode then
                local mode = pending_mode
                pending_mode = nil
                show_result_dialog(false, "人脸模块初始化超时", "请检查摄像头连接后重试")
            end
        end, 10000)
        return
    end
    -- 人脸已就绪：预览已启动 → 等画面就绪（FACE_PREVIEW_READY）后自动发起识别（预览不停流）；
    --   预览未启动（未开启/组件创建失败）→ 直接走串行识别，保证功能不失效
    if not preview_started_flag then
        log.info("ecface", "预览未启动，直接走串行识别")
        start_face_operation()
        return
    end
    wait_preview_ready()
end

-- 窗口销毁回调
local function on_destroy()
    -- 停止摄像头预览，释放 USB/内存资源（airui.camera 全局只允许一个）
    pcall(function()
        local face_preview = require "face_preview"
        face_preview.stop()
    end)
    preview_started_flag = false
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    if current_result_modal then
        current_result_modal:destroy()
        current_result_modal = nil
    end
    status_label = nil
    tip_label = nil
    current_mode = nil
    if pending_timer then
        sys.timerStop(pending_timer)
        pending_timer = nil
    end
    pending_mode = nil
    if face_task_timer then
        sys.timerStop(face_task_timer)
        face_task_timer = nil
    end
    -- 清理并行识别相关状态与定时器，避免影响下次开窗
    if preview_ready_timer then
        sys.timerStop(preview_ready_timer)
        preview_ready_timer = nil
    end
    preview_ready_flag = false
    preview_ready_ok = true
    preview_started_flag = false
    face_started = false
    parallel_inflight = false
    serial_retry_used = false
    busy = false
    done_flag = false
    win_id = nil
    -- 业务任务可能仍在后台执行，强制复位业务状态，避免下次操作报"业务状态繁忙"
    local ok, err = pcall(function()
        local ecbusiness = require "ecbusiness"
        ecbusiness.reset_business_state()
    end)
    if not ok then
        log.warn("ecface", "重置业务状态失败:", err)
    end
end

-- 打开窗口
local function open(mode)
    log.info("ecface", "打开刷脸窗口，模式:", mode)
    -- 防止重复打开（与其他窗口模块保持一致）
    if exwin.is_active(win_id) then
        log.warn("ecface", "刷脸窗口已打开，忽略重复请求")
        return
    end
    current_mode = mode
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
    })
end

-- 订阅消息
sys.subscribe("OPEN_FACE_DEPOSIT_WIN", function() open("deposit") end)
sys.subscribe("OPEN_FACE_RECEIVE_WIN", function() open("receive") end)
sys.subscribe("FACE_REGISTER_RESULT", on_register_result)
sys.subscribe("FACE_VERIFY_RESULT", on_verify_result)
sys.subscribe("FACE_STATE_UPDATE", on_face_state)
sys.subscribe("FACE_PREVIEW_READY", on_preview_ready)

-- 存件业务完成（业务任务回传结果，在主上下文弹窗，避免任务里操作 UI 卡死）
sys.subscribe("FACE_DEPOSIT_DONE", function(data)
    if current_mode ~= "deposit" then return end
    if not busy then return end
    if done_flag then return end
    if data.seq ~= task_seq then return end  -- 旧任务的结果，丢弃
    done_flag = true
    busy = false
    if face_task_timer then
        sys.timerStop(face_task_timer)
        face_task_timer = nil
    end
    if data.success then
        local content = "第" .. data.result.box_num .. "号箱门已打开\n请放入物品后关闭柜门"
        if data.result.save_code then
            -- 服务器返回存件码：用于小程序绑定"我的存件"
            content = content .. "\n存件码: " .. data.result.save_code .. "（小程序绑定用）"
        end
        if data.result.pickup_code then
            content = content .. "\n取件码: " .. data.result.pickup_code
        end
        show_result_dialog(true, "存件成功", content)
    else
        show_result_dialog(false, "存件失败", data.error or "请重试")
    end
end)

-- 取件业务完成
sys.subscribe("FACE_VERIFY_DONE", function(data)
    if current_mode ~= "receive" then return end
    if not busy then return end
    if done_flag then return end
    if data.seq ~= task_seq then return end  -- 旧任务的结果，丢弃
    done_flag = true
    busy = false
    if face_task_timer then
        sys.timerStop(face_task_timer)
        face_task_timer = nil
    end
    if data.success then
        show_result_dialog(true, "柜门已打开", "第" .. data.result.box_num .. "号箱门已打开\n请取走您的物品")
    else
        show_result_dialog(false, "取件失败", data.error or "请重试")
    end
end)

-- 人脸模块初始化结果：初始化完成后自动继续之前等待的操作（修复时序竞态）
sys.subscribe("FACE_INIT_RESULT", function(data)
    -- 清除初始化等待超时定时器
    if pending_timer then
        sys.timerStop(pending_timer)
        pending_timer = nil
    end
    if not data.success then
        if pending_mode then
            show_result_dialog(false, "人脸模块初始化失败", data.error or "请检查摄像头连接")
            pending_mode = nil
        end
        return
    end
    if pending_mode then
        pending_mode = nil
        if current_mode == nil then return end  -- 窗口已关闭
        -- 【死机修复·配套】进窗口时人脸还没就绪 → 当时没启动预览，这里补启动
        if not preview_started_flag then
            start_preview_only()
        end
        -- 初始化完成：预览已启动，等画面就绪（FACE_PREVIEW_READY）后自动发起人脸注册/验证
        update_ui("请正对摄像头", (current_mode == "deposit")
            and "请正对摄像头，保持不动\n即将自动开始人脸录入"
            or "请正对摄像头，保持不动\n即将自动开始人脸验证")
        if not preview_started_flag then
            log.info("ecface", "预览未启动，直接走串行识别")
            start_face_operation()
            return
        end
        wait_preview_ready()
    end
end)

log.info("ecface", "刷脸界面模块加载完成")
