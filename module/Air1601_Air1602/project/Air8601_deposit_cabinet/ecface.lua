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
local preview_started = false       -- 本次窗口是否已启动过摄像头预览（人脸就绪才启动，未就绪时等初始化结果再补启动）
local start_face_operation    -- 前向声明：on_create 的定时器回调先于函数体声明，需先声明避免解析成全局 nil

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

    -- 操作提示
    local tip_text = "请正对摄像头，" .. preview_sec .. "秒后自动开始人脸录入\n录入成功后自动分配柜子"
    if current_mode ~= "deposit" then
        tip_text = "请正对摄像头，" .. preview_sec .. "秒后自动开始人脸验证\n验证成功后自动开柜"
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
        show_result_dialog(false, "录入失败", data.error or "请重试")
    end
end

-- 处理验证结果（取件模式：验证人脸 → 查绑定柜 → 开柜 → 解绑）
local function on_verify_result(data)
    if current_mode ~= "receive" then return end
    if busy then return end

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
        show_result_dialog(false, "验证失败", data.error or "请重试")
    end
end

-- 人脸状态更新（来自 face_manager 的 on_state 回调）
local function on_face_state(data)
    if not status_label then return end
    if current_mode == nil then return end
    status_label:set_text(data.message or "请正对摄像头")
end

-- 窗口创建回调
-- 停止摄像头预览并发起人脸操作
--   UVC 摄像头流会占满 luat_camera 任务 CPU（"preview wait too much / no free event"），
--   导致红外 UART2 处理不过来 → 注册/验证超时失败。必须先停摄像头释放CPU再发起识别。
start_face_operation = function()
    --    exfacecam.reset() 内部含 sys.waitUntil，在定时器回调(非协程)里调用会报
    --    "attempt to yield from outside a coroutine"。
    --    拍照留底的 face_preview.capture() 同样是阻塞等待，必须在任务里调用；
    --    因此停预览也从定时器回调移入任务：先抓帧（预览仍在推流），再停流释放CPU。
    sys.taskInit(function()
        local face_preview = require "face_preview"
        -- 【拍照留底】预览仍在推流时抓取一帧 JPEG（下一帧到达即返回，一般≤200ms；
        --   停止预览后帧事件即消失，所以必须放在 stop() 之前）
        local photo_data = nil
        local cfg_ok, photo_cfg = pcall(function()
            local config = require "config"
            return config.get("face.photo", {})
        end)
        if cfg_ok and type(photo_cfg) == "table" and photo_cfg.enabled ~= false then
            -- 注意：face_preview.capture 是普通函数(非方法)，不能用 pcall(fn, self, ...) 形式
            -- 传 self 会让 timeout 收到 table → sys.waitUntil 内 timer_start 抛错 →
            -- FACE_PREVIEW_FRAME 订阅泄漏到已死亡协程 → 下次 publish 时 "cannot resume dead coroutine" 崩溃
            local cap_ok, cap_ret, cap_data = pcall(function()
                return face_preview.capture(photo_cfg.timeout or 2000)
            end)
            if cap_ok and cap_ret then
                photo_data = cap_data
            else
                log.warn("ecface", "拍照留底抓帧失败:", tostring(cap_ok and cap_data or cap_ret))
            end
        end
        -- 停止摄像头预览（原逻辑：UVC 流占满 luat_camera 任务 CPU，必须先停流释放CPU）
        pcall(function()
            face_preview.stop()
        end)
        -- stop() 释放数据流是异步的，若立即 MID_RESET → AirCAMERA 重启 → USB 重枚举，
        -- 残留回调/未释放 zbuff 会与之竞争 → use-after-free → 非对齐访问崩溃（死机）。
        pcall(function()
            face_preview.wait_closed()
        end)
        -- 【拍照留底】预览已停止、CPU 已释放，此时把照片写入SD卡，不与识别抢CPU
        if photo_data then
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
        -- 复位人脸模组：预览(UVC)会把模组传感器留在UVC模式，register(录入新脸)会因
        -- 传感器切不回人脸采集模式而超时（verify不受影响）。复位后传感器回到人脸模式。
        pcall(function()
            local face_manager = require "face_manager"
            face_manager.reset_module()
        end)
        log.info("ecface", "摄像头已停止，发起人脸", current_mode)
        if current_mode == "deposit" then
            local name = "user_" .. tostring(os.time())
            sys.publish("FACE_REGISTER_REQ", {name = name, admin = false})
        elseif current_mode == "receive" then
            sys.publish("FACE_VERIFY_REQ", {})
        end
    end)
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
    if face_ready_now and preview_w > 0 and preview_h > 0 then
        local ok_preview, err_preview = pcall(function()
            local face_preview = require "face_preview"
            return face_preview.start(main_container, preview_x, preview_y, preview_w, preview_h, current_mode)
        end)
        if not ok_preview then
            log.warn("ecface", "启动摄像头预览异常:", err_preview)
        else
            preview_started = true
        end
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
    -- 先显示预览 preview_sec 秒（用户看到自己、对准摄像头，期间自动抓拍留底），
    --    再停止摄像头释放CPU，然后发起人脸注册/验证；故预览 preview_delay 后自动触发
    sys.timerStart(start_face_operation, preview_delay)
end

-- 窗口销毁回调
local function on_destroy()
    -- 停止摄像头预览，释放 USB/内存资源（airui.camera 全局只允许一个）
    pcall(function()
        local face_preview = require "face_preview"
        face_preview.stop()
    end)
    preview_started = false
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
        local mode = pending_mode
        pending_mode = nil
        -- 【死机修复·配套】进窗口时人脸还没就绪 → 当时没启动预览，这里补启动，
        --   保证人脸正常时后续流程（preview_delay 后识别）与原来完全一致。
        if not preview_started and main_container and preview_w > 0 and preview_h > 0 then
            pcall(function()
                local face_preview = require "face_preview"
                preview_started = face_preview.start(main_container, preview_x, preview_y, preview_w, preview_h, mode) and true or false
            end)
        end
        -- 初始化完成：预览已常驻，preview_sec 秒后自动停止预览并发起人脸注册/验证
        update_ui("请正对摄像头", (mode == "deposit")
            and ("请正对摄像头，" .. preview_sec .. "秒后自动开始人脸录入\n录入成功后自动分配柜子")
            or ("请正对摄像头，" .. preview_sec .. "秒后自动开始人脸验证\n验证成功后自动开柜"))
        sys.timerStart(start_face_operation, preview_delay)
    end
end)

log.info("ecface", "刷脸界面模块加载完成")
