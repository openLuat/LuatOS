--[[
@module  face_preview
@summary 刷脸界面摄像头预览模块（AirCAMERA_1034 UVC → airui.camera 组件）
@version 3.1
@date    2026.08.21
@author  王城钧
@usage
摄像头数据流随刷脸窗口开关：
- 进刷脸窗口：start() 启动预览（excamera.open+preview，内部 usb.mode 重新枚举）
- 关窗：stop() 停止预览（仅 excamera.close()，不断电 USB，保证 UART2 人脸识别正常）

注意：
1. 数据流不能常驻：常驻会让 luat_camera 任务事件队列爆满，CPU 被占满导致红外人脸识别处理不过来。
2. 用最小分辨率(320×240)降低解码负载，保证识别期间 CPU 富余。
3. airui.camera 组件必须挂 airui.screen。
]]

local excamera = require "excamera"
local config = require "config"

local M = {}

local widget = nil          -- airui.camera 显示组件
local active = false        -- 预览是否激活
local gen = 0               -- 代数，防旧回调误用
local closing = false       -- 关闭进行中标记

-- 启动预览（进刷脸窗口时调用）
-- @param mode 窗口模式："deposit"/"receive"，取件时强制重启模组触发 USB 重枚举
function M.start(parent, x, y, w, h, mode)
    --    不能因 active=true 短路 return，否则第二次进窗口永远黑屏。
    --    这里直接重建：active 会被下方重置；taskInit 内 stop_wait 会等待旧 close 完成。
    --    旧 widget 若仍存活先销毁，避免 airui.camera 全局单实例冲突。
    if widget and not widget:is_destroyed() then
        pcall(function()
            widget:stop()
            widget:destroy()
        end)
        widget = nil
    end
    local cfg = config.get("face.preview", {})
    if not cfg.enabled then return false end

    widget = airui.camera({
        parent = airui.screen,
        x = x, y = y, w = w, h = h,
        fit = cfg.fit or "cover",
        rotation = cfg.rotation or 90,
        auto_start = false,
    })
    if not widget then
        log.error("face_preview", "airui.camera 组件创建失败")
        return false
    end
    if widget.set_rotation then
        widget:set_rotation(cfg.rotation or 90)
    end

    gen = gen + 1
    local my_gen = gen
    active = true

    local cam_w = cfg.width or 320
    local cam_h = cfg.height or 240
    local fps = cfg.fps or 10

    sys.taskInit(function()
        -- 这里只等待 closing（上次 close 任务）结束，不主动触发新的 close，
        -- 因为当前预览已在 start 主上下文设置 active=true，误 close 会毁掉本次预览。
        local t0 = 0
        while closing and t0 < 3000 do
            sys.wait(50)
            t0 = t0 + 50
        end
        if closing then
            log.warn("face_preview", "上次关闭仍未完成(3s超时)，继续尝试重建")
        end
        sys.wait(100) -- 等关闭标记处理完再进入重建流程

        -- 无条件强制 close 一次，兜底旧状态：此时 excamera 内部 preview_active 若为 true 会清理；
        -- 若为 false 则仅清理残留 camera_id（pcall 保护），随后 open 会完整重建。
        pcall(function()
            excamera.close()
        end)
        sys.wait(100) -- 等旧数据流彻底释放后再重新 open

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
            return
        end
        ok = excamera.preview(function(event, ...)
            if my_gen ~= gen then return end  -- 已停/已重开，忽略旧回调
            if event == "connected" then
                log.info("face_preview", "摄像头已连接，开始预览")
                if active and widget and not widget:is_destroyed() then
                    widget:register()
                    widget:start()
                end
            elseif event == "disconnected" then
                log.warn("face_preview", "摄像头已断开")
                if widget and not widget:is_destroyed() then
                    widget:stop()
                end
            end
        end)
        if not ok then
            log.error("face_preview", "excamera.preview 失败")
            excamera.close()
            return
        end

        -- 背景：pm.power(pm.USB,false/true) 只控制 USB VBUS，无法重启已上电模组；
        --       仅开机后第一次进刷脸窗口时模组从无电到有电会触发枚举；
        --       之后（第二次存件/取件）模组已上电并枚举过 → preview 注册回调后不会再有新枚举 → 黑屏。
        -- 时序（关键）：必须在 excamera.preview【之后】执行！preview 内部已注册 usb_raw 回调，
        --       GPIO73 断电重启模组 → 模组重新枚举产生的 EV_CONNECT 事件发生在回调注册之后 → 不丢失。
        --       若在 preview 之前重启，枚举在回调注册前完成 → EV_CONNECT 丢失 → 依然黑屏。
        -- 注：GPIO73 同时供 UART2 人脸模组，重启后预览结束的 exfacecam.reset()(MID_RESET) 会重建 UART2。
        log.info("face_preview", "预览启动，mode=" .. tostring(mode) .. ", closing=" .. tostring(closing))
        log.info("face_preview", "preview后强制重启 AirCAMERA 模组触发 USB 重枚举")
        pcall(function()
            gpio.setup(73, 0)
            gpio.set(73, 0)
            sys.wait(400)  -- 断电保持400ms，确保模组完全下电
            gpio.setup(73, 1, gpio.PULLUP)
            gpio.set(73, 1)
            sys.wait(500)  -- 上电后等500ms，让模组完成重新枚举
        end)
    end)
    return true
end

-- 停止预览（关窗时调用；只停流，不断电USB —— 模组是USB供电，断电会杀掉UART2人脸识别）
function M.stop()
    if not active then return end
    active = false
    gen = gen + 1  -- 使进行中的旧回调失效
    if widget and not widget:is_destroyed() then
        widget:stop()
        widget:destroy()
    end
    widget = nil
    closing = true
    sys.taskInit(function()
        pcall(excamera.close)
        closing = false
        log.info("face_preview", "预览已停止，数据流已释放")
    end)
end

-- 强制停止并等待预览数据流完全关闭（避免上次预览未释放 → 下次 start 状态残留 → 黑屏）
-- 与 stop() 不同：即使 active 已 false 也等待进行中的 close 完成；返回后 USB 状态干净。
function M.stop_wait()
    if not active and not closing then return end
    if active then
        active = false
        gen = gen + 1
        if widget and not widget:is_destroyed() then
            widget:stop()
            widget:destroy()
        end
        widget = nil
        closing = true
        sys.taskInit(function()
            pcall(excamera.close)
            closing = false
            log.info("face_preview", "预览已停止，数据流已释放")
        end)
    end
    -- 等待 close 完成
    local t = 0
    while closing and t < 3000 do
        sys.wait(50)
        t = t + 50
    end
    sys.wait(100)
    log.info("face_preview", "stop_wait 完成，closing=" .. tostring(closing))
end

-- 同步等待预览数据流完全关闭（复位人脸模组前调用，避免与残留 USB 回调竞争）
-- 说明：stop() 释放数据流是异步的（sys.taskInit），若立即复位模组（MID_RESET→USB重枚举），
--       残留回调/未释放缓冲会与复位竞争 → use-after-free → 非对齐访问崩溃。
-- 最多等待 1500ms，超时不再阻塞，交由 excamera.close 的 pcall 兜底。
function M.wait_closed(timeout)
    local t = 0
    while closing and t < (timeout or 1500) do
        sys.wait(50)
        t = t + 50
    end
    -- 再留 100ms 让 USB 栈稳定（注销回调/释放 zbuff 生效）
    sys.wait(100)
end

-- 当前是否有关闭正在进行（供调用方判断）
function M.is_closing()
    return closing
end

return M
