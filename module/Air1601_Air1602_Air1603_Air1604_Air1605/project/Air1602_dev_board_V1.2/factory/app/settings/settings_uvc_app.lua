--[[
@module  settings_uvc_app
@summary USB 摄像头业务层（设置页入口 · UVC 开流 / 关流，画面由 UI 的 airui.camera 组件显示）
@version 1.0
@date    2026.10.26
@author  江访
@usage
本模块只管「数据流」：开流 → 连上 → 关流。画面显示交给 ui/settings/settings_uvc_win.lua
里的 airui.camera 组件 —— 固件解码出的 RGB565 帧直接送到组件，不经过 Lua，
所以这里连 frame 回调都不用处理。

消息协议:
订阅: UVC_OPEN_REQ              → 供电 + 开流 + 注册预览回调
订阅: UVC_CLOSE_REQ(gen)        → 关流 + 断电，完成后回 UVC_CLOSED(gen)
订阅: UVC_RESTART_REQ           → 关流再开流（摄像头没连上 / 想重新枚举时用）
发布: UVC_STATUS(text, level)   状态文案，level = "info" | "ok" | "err"
发布: UVC_CLOSED(gen)           关流完成，UI 此时才能销毁画面组件

=== 为什么开流 / 关流必须走协程 ===

excamera.open / preview / close 内部都有 sys.wait（等 USB 枚举、等推流收尾），
sys.subscribe 的派发上下文不是协程，直接跑会把等待整段跳过 —— 表现为「开流报成功
但一直没画面」。所以三个入口一律 sys.taskInit 包一层，并用 busy 串行化，
避免「上一轮还没关完就开下一轮」把 excamera 的单例状态踩乱。

=== 分辨率 ===

默认档 1280×720（与 Air8601 的 UVC 预览页一致）；config.peripherals 条目里写了
w / h 就以它为首选档，但该档像素数超过 max_pixels 时作废、退回默认档。
摄像头连上后枚举它真正支持的 MJPEG 档位（pick_uvc_mode），与申请档不一致就按实际档
重开一次流 —— excamera 的双帧缓冲是按 open 时的 w×h 建的（w×h 字节 ×2 块），
尺寸对不上会收不满帧。

取档优先级：首选档（w/h 命中）→ 像素数不超过 max_pixels 的最大档 → 最小档。
max_pixels 缺省即 1280×720，相机侧固定开销约 4.25×w×h 字节，越大留给
airui.camera 显示缓冲的余量越小（预览区会跟着收小），1920×1080 会挤爆内存。

=== 供电 ===

Air1602 V1.2 底板的 USB 口 5V 跟总供电同一路（GPIO58），配置里按**可控供电脚**
（en_pin = 58, power_hold）处理：进本页先把它掉电再上电（periph_uvc 的 power_cycle），
强制 USB 主机重新枚举摄像头，然后才开流。

这一条是「摄像头时连时不连」的关键：单纯把已经是高电平的脚再拉高不产生边沿，
USB 主机不会重新枚举，于是主机拿着旧设备地址发 SET_INTERFACE 一路 ep0 timeout；
掉电再上电必然触发 hub 上报 port change → 重新枚举 → 连上。

本板 GPIO58 是整板总供电（不是 V1.1 那种单独的 5V_EN），那几百毫秒的拉低会顺带把
WiFi / 4G / SD 一起掉电重启，所以只在「进本页」时做一次，退出页面不断电（power_hold）。
若某个底板不希望总供电被这样拉低，把 config 里 uvc 条目的 power_hold 留着、
把 ready_delay / cycle 相关参数去掉即可（改成常供电，靠热插拔自然重枚举）。
]]

local drv = require "periph_uvc"

--[[
编译系统按 require "excamera" 的字面文本决定打包范围，故这里保持字面写法；
又因为相机核心库缺失的固件上本模块也必须能加载（否则本文件 require 失败会中断
settings_app 的后续加载，连带别的设置子页都打不开），所以用 pcall 兜住。]]
local function load_excamera()
    return require "excamera"
end
local ok_cam, cam_lib = pcall(load_excamera)
local excamera = ok_cam and cam_lib or nil
if not excamera then
    log.warn("settings_uvc", "excamera 加载失败，摄像头预览不可用")
end

-- 未配置 peripherals 时的兜底（只给 id / 名称，分辨率与上限走下面的默认档）
local FALLBACK_PARAMS = { id = "uvc1", name = "USB摄像头" }

-- 默认开流档：未配 w / h 时用（与 Air8601 的 UVC 预览页一致）
-- 相机侧固定开销约 4.25×w×h 字节（双帧缓冲 w×h + 解码输入 w×h/4 + 解码输出 w×h×2）
local DEFAULT_W, DEFAULT_H = 1280, 720

--[[停流前宽限：等一帧时间让在途帧回调跑完，避免读到 excamera.close 已释放的 zbuff
20fps 一帧 50ms，取 120ms 足够；这个值直接叠加在「退出页面 → 资源真正释放」的延迟上，
退到桌面时桌面会立刻起播放器抢解码器，这里越短越安全。]]
local CLOSE_GRACE = 120

local handle = nil
local params = nil

-- 当前申请的开流分辨率（连上后会被实际档位校正）
local sensor_w, sensor_h = DEFAULT_W, DEFAULT_H

-- 源分辨率像素上限：像素数更大的 MJPEG 档位不取（1920×1080 时相机侧要吃掉 8.8MB）
local max_pixels = DEFAULT_W * DEFAULT_H

-- config 条目里的首选分辨率；像素数超过上限时作废，退回默认档
local pref_w, pref_h = nil, nil

local opened = false   -- 数据流是否已开
local busy = false     -- 开/关流串行化：新请求要等上一轮收尾
--[[页面已请求关流：正在排队的开流动作要能半路收手。
用户若在「供电 cycle（几百毫秒 sys.wait）」期间点了返回/桌面，关流虽然插到了队首，
但当前这个动作会把 open_stream 完整跑完 —— 先把流开起来再关，等于白开一次，
还把「资源真正释放」的时间拖长，撞上桌面起播放器。]]
local closing_now = false

-- 前向声明：open_stream 里传给 excamera.preview，下面的回调体里又要反过来调 run
local preview_callback

-- 前向声明：定义在下面的「供电」段，open_stream 里要用。
-- 不加这句，open_stream 里那个 cam_power_cycle 会绑到尚未声明的同名全局（nil）
local cam_power_cycle

-- ==================== 参数 ====================

--[[取本机型声明的 uvc 配置条目（取第一条）]]
local function find_params()
    local list = _G.project_config and _G.project_config.peripherals
    if type(list) ~= "table" then return nil end
    for _, p in ipairs(list) do
        if p and p.type == "uvc" then return p end
    end
    return nil
end

--[[解析分辨率参数：max_pixels 缺省即默认档的像素数；条目里的 w/h 是首选档，
超过上限就作废退回默认档（否则首选档会把内存预算撑爆）。]]
local function get_params()
    if params then return params end
    params = find_params() or FALLBACK_PARAMS
    max_pixels = (params.max_pixels and params.max_pixels > 0)
                 and params.max_pixels or (DEFAULT_W * DEFAULT_H)
    pref_w, pref_h = params.w, params.h
    if pref_w and pref_h and (pref_w * pref_h) <= max_pixels then
        sensor_w, sensor_h = pref_w, pref_h
    else
        pref_w, pref_h = nil, nil
        sensor_w, sensor_h = DEFAULT_W, DEFAULT_H
    end
    return params
end

--[[取驱动 handle：periph_loader 已登记的直接用，没登记就补登记一次]]
local function get_handle()
    if handle then return handle end
    local p = get_params()
    handle = drv.get(p.id)
    if not handle then
        local ok, h = pcall(drv.init, p)
        if ok and h then
            handle = h
        else
            log.warn("settings_uvc", "UVC 驱动登记失败", tostring(h))
        end
    end
    return handle
end

-- ==================== 工具 ====================

local function status(text, level)
    sys.publish("UVC_STATUS", text, level or "info")
end

-- 相机能力是否齐备（固件没编 camera 库 / 没编 excamera 时为假）
local function cam_ready()
    return excamera ~= nil and camera ~= nil and camera.USB ~= nil
end

-- 开流参数（work_mode = 2 表示预览，数据流由 excamera.preview 接管）
local function cam_param()
    return {
        id            = camera.USB,
        sensor_width  = sensor_w,
        sensor_height = sensor_h,
        usb_port      = get_params().usb_port or 1,
        work_mode     = 2,
        fps           = get_params().fps or 15,
    }
end

--[[
枚举摄像头真正支持的 MJPEG 档位，选一档回来：
首选 config 指定的 w/h（pref_w/pref_h），其次像素数不超过 max_pixels 的最大档，
都没有就取最小档。拿到的 w/h 用来校正 excamera 的帧缓冲尺寸
（它按 open 时的 w×h 建双帧缓冲）。]]
local function pick_uvc_mode(app_id)
    if not camera.get_usb_config then return nil end
    local res, format_num = camera.get_usb_config(app_id, camera.CONF_UVC_FORMAT)
    if not format_num or format_num <= 0 then
        log.warn("settings_uvc", "UVC 格式枚举失败", res, format_num)
        return nil
    end

    local exact, best, smallest = nil, nil, nil
    for fmt = 1, format_num do
        local _, ftype, frame_num = camera.get_usb_config(app_id, camera.CONF_UVC_FORMAT, fmt)
        if ftype == camera.FORMAT_MJPG and frame_num then
            for frm = 1, frame_num do
                local _, fps, w, h = camera.get_usb_config(app_id, camera.CONF_UVC_RESOLUTION, fmt, frm)
                if w and h and w > 0 and h > 0 then
                    local m = { w = w, h = h, fmt = fmt, frm = frm, px = w * h, fps = fps }
                    log.info("settings_uvc", "UVC 支持", w, "x", h, "fps", fps)
                    if not smallest or m.px < smallest.px then smallest = m end
                    if pref_w == w and pref_h == h then exact = m end
                    if m.px <= max_pixels and (not best or m.px > best.px) then best = m end
                end
            end
        end
    end
    if exact then return exact end
    if best then return best end
    if smallest then
        log.warn("settings_uvc", "无预算内档位，改用最小档", smallest.w, smallest.h)
    end
    return smallest
end

-- ==================== 串行化 ====================

--[[开流 / 关流串行执行：excamera 是单例，两轮动作重叠会互相踩状态。
等待有上限，避免上一个动作卡死时后来的请求永远排不上。]]
local queue = {}

--[[串行执行动作：excamera 是单例，开/关流绝不能并发，所以动作一律排队。

front = true 表示插到队首（关流专用）：页面销毁后必须尽快让位，不能排在上一个
动作后面干等（供电 cycle 那一串 sys.wait 能到几百毫秒）。插队只换顺序，
不会让两个动作同时跑 —— 正在执行的那个跑完才轮到它。]]
local function run(fn, front)
    if front then
        table.insert(queue, 1, fn)
    else
        queue[#queue + 1] = fn
    end
    if busy then return end
    busy = true
    sys.taskInit(function()
        while #queue > 0 do
            local f = table.remove(queue, 1)
            local ok, err = pcall(f)
            if not ok then log.warn("settings_uvc", "动作异常", tostring(err)) end
        end
        busy = false
    end)
end

-- ==================== 数据流（只在协程里调用） ====================

--[[开流后「等不到 USB 连接」的兜底重连

excamera.preview 只靠 usb.EV_CONNECT 事件驱动，不查设备是否已经连着
（见 script/libs/excamera.lua）。USB 主机若在我们注册回调之前就把设备枚举完了，
这个事件永远等不到 —— 页面会一直卡在「等待摄像头连接」，重开一次才出画面。

回调注册之后再走一遍 open/preview 必中：preview 内部会 pm.power 重新触发枚举，
且它把「注册」刻意排在「上电」之后，注册总在枚举之前。所以超时就自动重开，
最多 MAX_RETRY 次，避免在没有摄像头时无限重开。]]
local WATCHDOG_MS = 6000
local MAX_RETRY = 2
local linked = false       -- 是否收到过 connected
local watchdog_id = nil
local retry_count = 0
--[[正在主动掉电重上电：这期间的 disconnected 是我们自己造成的，不是掉线。
不屏蔽的话状态行会先闪一句红字「摄像头已断开」再变回「预览中」，看着像出故障。]]
local recycling = false

local function stop_watchdog()
    if watchdog_id then
        pcall(sys.timerStop, watchdog_id)
        watchdog_id = nil
    end
end

local function arm_watchdog()
    if watchdog_id then return end
    if retry_count >= MAX_RETRY then return end
    watchdog_id = sys.timerStart(function()
        watchdog_id = nil
        -- 已经连上 / 页面要关了 / 流已经不在了，都不必重开
        if linked or closing_now or not opened then return end
        retry_count = retry_count + 1
        log.warn("settings_uvc", "开流后未等到摄像头连接，自动重开", retry_count)
        -- 走消息而不是直接调 close_stream：本函数定义在它之前，
        -- 直接引用会绑到尚未声明的同名全局上（nil）。消息入口在文件末尾，那时都已就位
        sys.publish("UVC_RESTART_REQ")
    end, WATCHDOG_MS)
end

local function open_stream()
    if closing_now then return false end   -- 页面已经要关了，别再开一次
    if not cam_ready() then
        status("本固件不含相机能力，无法显示画面", "err")
        return false
    end
    if not excamera.open(cam_param()) then
        status("摄像头打开失败，请确认已插入 USB 口且 5V 已供上", "err")
        return false
    end
    if not excamera.preview(preview_callback) then
        pcall(excamera.close)
        status("预览启动失败", "err")
        return false
    end
    opened = true
    linked = false
    if retry_count < MAX_RETRY then
        status(string.format("等待摄像头连接...（%d 秒后自动重连）",
                             math.floor(WATCHDOG_MS / 1000)), "info")
    else
        status("等待摄像头连接...（请检查 USB 口与供电）", "info")
    end
    arm_watchdog()
    --[[回调注册完之后才掉电重上电，强制 USB 主机重新枚举。
    顺序不能反：反了设备会在回调注册前就枚举完，EV_CONNECT 永远收不到。]]
    cam_power_cycle()
    return true
end

--[[关数据流：先 excamera.close 停流并释放帧缓冲，再等固件解码/显示任务收尾
不判断 opened、无条件关（与 Air8601 一致）：只要回执了 UVC_CLOSED，UI 就会销毁画面
组件，此时流必须真的关掉；靠 opened 短路会漏关（disconnected 后 opened 已被置 false），
留下一个还在收帧的解码线程往已销毁的组件里画。]]
local function close_stream()
    opened = false
    linked = false
    stop_watchdog()
    if excamera then
        sys.wait(CLOSE_GRACE)
        pcall(excamera.close)
        sys.wait(100)
    end
end

--[[
excamera 预览事件：连接 / 断开 / 异常（在 USB 事件上下文里回调，非协程）
frame 事件不用处理：解码后的 RGB565 帧由固件直接送 airui.camera 组件，不经过 Lua。]]
preview_callback = function(event, ...)
    if event == "connected" then
        local app_id = ...
        -- 连上了：撤掉兜底重连，重开计数归零（页面停留期间的重连用）
        linked = true
        retry_count = 0
        stop_watchdog()
        -- 档位枚举是只读查询，可直接在回调里做；重开流要 sys.wait，交回协程
        local okm, mode = pcall(pick_uvc_mode, app_id)
        if okm and mode and (mode.w ~= sensor_w or mode.h ~= sensor_h) then
            log.info("settings_uvc", "改用摄像头实际支持的分辨率", mode.w, "x", mode.h)
            sensor_w, sensor_h = mode.w, mode.h
            run(function()
                close_stream()
                sys.wait(150)
                open_stream()
            end)
            return
        end
        status(string.format("预览中 %dx%d", sensor_w, sensor_h), "ok")
    elseif event == "disconnected" then
        -- 主动重新枚举造成的断开：保持「重新枚举中...」，别刷成红字
        if recycling then
            log.info("settings_uvc", "重新枚举：设备断开（预期内）")
            return
        end
        opened = false
        linked = false
        status("摄像头已断开", "err")
    elseif event == "error" then
        status("摄像头错误: " .. tostring((...)), "err")
    end
end

-- ==================== 供电（只在协程里调用） ====================

--[[给摄像头上电，返回 false 表示供电脚有问题、不要继续开流。
power_cycle 的脚会先掉电再上电，驱动内部有 sys.wait，必须在协程里调。]]
local function cam_power_on()
    local h = get_handle()
    if not h then return true end   -- 没登记到驱动就按「底板常供」处理，不拦着开流
    local p = h.params or {}
    if p.power_cycle then
        status("摄像头上电中...", "info")
    end
    local ok, err = pcall(h.start, h)
    if not ok then ok, err = false, tostring(err) end
    if not ok then
        log.warn("settings_uvc", "供电失败", tostring(err))
        status("摄像头供电失败：" .. tostring(err), "err")
        return false
    end
    return true
end

--[[给摄像头一次掉电重上电，强制 USB 主机重新枚举

**只能在 excamera.preview 注册回调之后调用**（见 periph_uvc 的 uvc_recycle 注释）：
设备断开→重连产生的 EV_CONNECT 才会被回调看见。放在 preview 之前会让设备在回调
注册前就枚举完，那个事件永远丢失，页面就一直卡在「等待摄像头连接」。
底板常供（没有 en_pin）时没法cycle，返回什么都不做 —— 那种情况下只能靠
excamera.preview 内部那套 pm.power，以及 6 秒看门狗兜底。]]
cam_power_cycle = function()
    local h = get_handle()
    if not h or not h.recycle then return end
    recycling = true
    status("摄像头重新枚举中...", "info")
    local ok, err = pcall(h.recycle, h)
    if not ok then
        log.warn("settings_uvc", "重新枚举失败", tostring(err))
        status("摄像头重新枚举失败：" .. tostring(err), "err")
        recycling = false
        return
    end
    --[[静默窗口要比 cycle 本身长：hub 上报断开事件实测能迟到 800ms
    （掉电 → Port 1 change 的间隔），等 cycle 一结束就解除屏蔽的话，那条迟到的
    disconnected 还是会刷出红字。多留 1200ms 再恢复正常提示。]]
    sys.timerStart(function() recycling = false end, 1200)
end

-- ==================== 消息入口 ====================

sys.subscribe("UVC_OPEN_REQ", function()
    run(function()
        closing_now = false
        retry_count = 0
        if not cam_power_on() then return end
        if opened then
            status(string.format("预览中 %dx%d", sensor_w, sensor_h), "ok")
            return
        end
        open_stream()
    end)
end)

sys.subscribe("UVC_CLOSE_REQ", function(gen)
    -- 插队（front）：页面已销毁，桌面随后就要起播放器抢解码器，关流不能排在队尾干等
    closing_now = true
    run(function()
        close_stream()
        if handle then pcall(handle.stop, handle) end
        -- 关流完成才回执：UI 收到后才能销毁画面组件（先于 close 销毁会死机）
        sys.publish("UVC_CLOSED", gen)
    end, true)
end)

sys.subscribe("UVC_RESTART_REQ", function()
    run(function()
        close_stream()
        sys.wait(150)
        if closing_now then return end   -- 期间页面要关了，别再掉一次电
        -- 重开 = 掉电再上电重新枚举 + 开流，走的是同一条供电路径
        if not cam_power_on() then return end
        open_stream()
    end)
end)
