--[[
@module  scan
@summary Air8603(W1) + USB(UVC) 摄像头扫码 → 解析二维码 → 输出账户键
@note    对外接口：M.init() / M.start() / M.stop()；
         结果通过 sys.publish("SCAN_RESULT", 账户键, 备用工牌ID) 上报。

本模块演示一套已在真机验证过的 UVC 扫码链路，核心要点：

  1) 顶层一次性分配双缓冲 960*480 ×2，永不释放；EV_DISCONNECT 只清状态、复用缓冲。
     （每次重连都重新分配大缓冲会触发强制 GC，是反复掉线的加剧因素）
  2) camera.on(USB,"scanned",nil) 先清残留：C 层分发里 scanned 与 usb_raw 互斥，
     不清则收不到解码结果。
  3) usb.on(0,usb_cb) 只做诊断打印、不改写状态；class 过滤 usb.CAMERA 排除 UAC。
  4) EV_CONNECT 里固定四步：get_usb_config 枚举 → set_usb_config(格式类型,宽,高)
     → camera.cache(USB,真实app_id,双缓冲) → camera.stream(USB,app_id,nil,nil,false,true)。
     ★ 第 2 参必须是真实 app_id(0/1)，绝不能传 camera.USB(32)。
     ★ 第 4 参传 nil、不传第 7 参。
  5) 档位固定 RES_INDEX=5 (320x240)；改回 0 = 自动选档。
  6) EV_ERR_STOP / EV_DISCONNECT 都【不】调用 usb.reset_device，靠下一次 EV_CONNECT 自愈。
  7) 无后台轮询重开流任务：只在 EV_CONNECT 开一次，M.start() 最多补开一次。

与独立扫码 demo 相比，为保留业务功能所做的调整：
  a) 模块顶层只做「无副作用准备」：双缓冲 + 清 scanned + 注册回调。
     供电与 USB HOST 三件套放在 M.init() 里、唯一一次 sys.wait(3000) 之前，
     避免在 IP_READY 一次性事件之前插入长等待（否则 WIFI.wait_ready() 会超时）。
  b) 本文件由 app.lua require，不调用 sys.run()。
  c) 解码后增加业务层：scanning 门控（点确认后的 30s 窗口）、
     CFG.limit.scan_dup_ms 去重、CFG.card 归一化与 min_len 校验、发布 SCAN_RESULT。
     非窗口期只打印原文、不触发扣费。
  d) 心跳日志默认关闭（HEARTBEAT_ENABLE），需要观察 USB 重连时改成 true。
  e) M.init()/M.start()/M.stop() 恒返回 true，保证业务层一定进入扫码窗口。

★ 示例工程已移除原工程中的本地绝对路径、调试时间与现场实测记录；业务逻辑未改动。
]]

local CFG = require "config"
local M = {}

-- ==================== 可调参数（集中在此，不动 config.lua） ====================
-- ▲【按需 O08】分辨率档位：5 = 320x240（已验证稳定档），0 = 自动选档
local RES_INDEX        = 5           -- ▲【按需 O08】← 就是这一行
local BUFF_SIZE        = 960 * 480   -- 本模块枚举到的最大档，留足余量
local CAM_READY_MS     = 3000        -- 唯一一次开机等待，勿加长（见文件头时序约定）
local HEARTBEAT_MS     = 3000
local HEARTBEAT_ENABLE = false       -- 排查 USB 反复重连时改成 true
local DUP_TIP_EVERY    = 20          -- 同一个码每连续解出 N 帧提示一次

-- 供电引脚：与 hw_init.lua / config.lua 一致，取值 12(5V_EN) / 58(UVC_EN)
local PIN_5V_EN  = CFG.hw.pwr_5v_en
local PIN_UVC_EN = CFG.hw.uvc_en

local usb_app_id, usb_online, stream_id
local last_str, dup_cnt = nil, 0   -- 日志抑制（同一码连续帧）
local last_code, last_ms           -- 业务去重
local scanning = false             -- 是否处于「点确认后」的扫码窗口

-- ==================== 双缓冲：顶层一次性分配，永不释放 ====================
local frame_buff0 = zbuff.create(BUFF_SIZE)
local frame_buff1 = zbuff.create(BUFF_SIZE)
if not (frame_buff0 and frame_buff1) then
    -- 正式工程还有 1024x600 RGB 帧缓冲，内存比独立工程紧；异常时降档兜底
    log.warn("scan", "顶层缓冲分配失败，降为 640x480 重试")
    frame_buff0 = zbuff.create(640 * 480)
    frame_buff1 = zbuff.create(640 * 480)
end
log.info("scan", "帧缓冲就绪", BUFF_SIZE, "字节 x2",
         frame_buff0 ~= nil and frame_buff1 ~= nil)

-- ==================== 二维码内容 → 账户键 ====================
-- 示例二维码格式：badge<工牌ID>-<识别有效位数>
-- 按最后一个横杠拆两段。约定：★ 横杠后是稳定的「识别有效位数」，
-- 对应后端员工表 number 字段；横杠前的工牌 ID 可能变化，只能作备用参考。
local function split_dash(s)
    local a, b = s:match("^(.*)%-([^%-]*)$")
    if a then return a, b end
    return s, ""
end

-- 规则见 config/config.lua 的 C.card.parse_rule / take_n
local function normalize(s)
    local c    = CFG.card
    local rule = c.parse_rule or ""
    local out
    if rule == "after_dash" then
        local _, b = split_dash(s)
        out = b
    elseif rule == "before_dash" then
        local a = split_dash(s)
        out = a
    elseif rule == "before_dash_digits" then
        local a = split_dash(s)
        out = (a:gsub("%D", ""))
    elseif rule == "digits" then
        out = (s:gsub("%D", ""))
    else
        -- 旧版兜底：mode 规则（"" / "digits" / Lua 匹配模式）
        local mode = c.mode
        if mode == "digits" then
            out = (s:gsub("%D", ""))
        elseif mode ~= "" then
            local v = s:match(mode)
            out = v or s
        else
            out = s
        end
    end
    -- 有效位数：正数取前 N 位，负数取后 N 位，0 表示整段
    local n = c.take_n or 0
    if n > 0 and #out > n then
        out = out:sub(1, n)
    elseif n < 0 and #out > -n then
        out = out:sub(n)
    end
    return out
end

-- ==================== 解码结果：日志 + 业务上报 ====================
local function on_decode(str)
    if type(str) ~= "string" or #str == 0 then return end

    -- 摄像头会对同一码连续解码很多帧：新码完整打印，连续帧每 20 帧提示一次
    if str ~= last_str then
        last_str, dup_cnt = str, 0
        log.info("scan", "==============================")
        log.info("scan", "★ 扫码成功 原始内容:", str)
        log.info("scan", "扫码内容长度:", #str)
        local a, b = split_dash(str)
        log.info("scan", "横杠前 工牌ID段:", a)
        log.info("scan", "横杠后 识别有效位数:", b)
        log.info("scan", "==============================")
    else
        dup_cnt = dup_cnt + 1
        if scanning and dup_cnt % DUP_TIP_EVERY == 0 then
            log.info("scan", "同一码连续解码", dup_cnt, "帧（流正常）", str)
        end
    end

    if not scanning then return end   -- 非扫码窗口：只打印，不触发扣费

    -- 2 秒内同一个码只认一次，防止连续帧重复扣费
    local now = mcu.ticks()
    if str == last_code and last_ms and (now - last_ms) < CFG.limit.scan_dup_ms then
        return
    end
    last_code, last_ms = str, now

    local card = normalize(str)
    log.info("scan", "账户键(", tostring(CFG.card.parse_rule), "):", card, "长度:", #card)
    if #card < CFG.card.min_len then
        log.warn("scan", "二维码内容不像卡号，已忽略", str,
                 "（min_len =", CFG.card.min_len, "）")
        return
    end
    -- 备用键：横杠前的纯数字工牌 ID，仅供 fallback_to_name 兜底路径使用。
    local a = split_dash(str)
    local stable = (a:gsub("%D", ""))
    log.info("scan", "备用键(横杠前工牌ID):", stable)
    log.info("scan", "★ 卡号有效，触发扣费流程 识别有效位数:", card)
    sys.publish("SCAN_RESULT", card, stable)
end

-- ==================== 枚举 → 设格式 → 双缓冲 → 只扫码开流 ====================
-- get_usb_config 返回值（luat_lib_camera.c）：
--   (id, CONF_UVC_FORMAT)               → result, 格式总数
--   (id, CONF_UVC_FORMAT, fmt)          → result, 格式类型, 图像档数
--   (id, CONF_UVC_RESOLUTION, fmt, frm) → result, 帧率, 宽, 高
local function open_stream(id)
    log.info("scan", "---- 配置 UVC app_id", id, "----")

    if not (frame_buff0 and frame_buff1) then
        log.error("scan", "帧缓冲不可用，跳过开流")
        return false
    end

    local res, format_num = camera.get_usb_config(id, camera.CONF_UVC_FORMAT)
    log.info("scan", "数据流格式总数", format_num, "枚举结果", res)
    if not res or not format_num or format_num <= 0 then return false end

    local list = {}
    for fmt = 1, format_num do
        local r2, ftype, frame_num =
            camera.get_usb_config(id, camera.CONF_UVC_FORMAT, fmt)
        for frm = 1, (frame_num or 0) do
            local r3, fps, w, h =
                camera.get_usb_config(id, camera.CONF_UVC_RESOLUTION, fmt, frm)
            if r3 and w and h then
                list[#list + 1] = { fmt = fmt, frm = frm, type = ftype, w = w, h = h }
                log.info("scan", "  档位", #list, "格式", ftype,
                         "分辨率", w .. "x" .. h, "帧率", fps)
            end
        end
    end
    if #list == 0 then
        log.error("scan", "未枚举到任何分辨率")
        return false
    end

    local pick = list[RES_INDEX]
    if not pick then
        -- 优先 MJPEG；其次面积最接近 640x480（解码快、内存省）
        local best
        for _, v in ipairs(list) do
            local score = math.abs(v.w * v.h - 640 * 480)
                          + ((v.type == (camera.FORMAT_MJPG or 1)) and 0 or 1000000)
            if not best or score < best then best, pick = score, v end
        end
    end
    log.info("scan", "★ 选用", pick.w .. "x" .. pick.h, "格式", pick.type)

    -- 官方 main.lua 第 101 行【实际执行】的写法：格式类型 + 宽 + 高
    local ok = camera.set_usb_config(id, camera.CONF_UVC_RESOLUTION,
                                     pick.type or camera.FORMAT_MJPG or 1,
                                     pick.w, pick.h)
    log.info("scan", "set_usb_config", ok)
    if not ok then   -- 回退：官方第 102 行注释里的「序号」写法
        ok = camera.set_usb_config(id, camera.CONF_UVC_RESOLUTION, pick.fmt, pick.frm)
        log.info("scan", "set_usb_config(序号回退)", pick.fmt, pick.frm, ok)
    end

    log.info("scan", "camera.cache",
             camera.cache(camera.USB, id, frame_buff0, frame_buff1))

    -- ★ 只扫码、不输出视频流；第 2 参必须是 EV_CONNECT 给的真实 app_id
    local ok_stream = camera.stream(camera.USB, id, nil, nil, false, true)
    log.info("scan", "★ camera.stream(只扫码)", ok_stream, "app_id", id)
    return ok_stream == true
end

-- ==================== USB 事件（仅诊断，class 过滤；不改写状态） ====================
-- 回调签名 (usb_id, class, app_id, event, p1, p2, p3)
local function usb_cb(usb_id, class, app_id, event, p1, p2, p3)
    if usb.CAMERA and class ~= usb.CAMERA then return end  -- UVC+UAC 复合设备
    if event == usb.EV_CONNECT then
        log.info("scan", "USB摄像头已接入 app_id", app_id, "hub端口", p2)
    elseif event == usb.EV_DISCONNECT then
        log.info("scan", "USB摄像头已拔出 app_id", app_id)
    end
end

-- ==================== camera 的 usb_raw 回调 ====================
-- luat_lib_camera.c：LUAT_CAMERA_SCAN_DECODE 分支推的是
--   event = usb.EV_NEW_RX，param = 二维码解码字符串
local function camera_cb(app_id, event, param)
    if event == usb.EV_NEW_RX then
        if type(param) == "string" and #param > 0 then
            on_decode(param)
        end
        -- param == 0/1 是帧缓冲序号；帧回调已关闭，不打印避免刷屏
        return
    end

    if event == usb.EV_CONNECT then
        usb_app_id, usb_online = app_id, true
        log.info("scan", "★ 摄像头已连接 app_id", app_id, "hub端口", param)
        stream_id = open_stream(app_id) and app_id or nil
        if stream_id then
            log.info("scan", "★ 扫码已启动，请把二维码对准摄像头")
        else
            log.warn("scan", "开流失败，等下一次接入重试")
        end
        return
    end

    if event == usb.EV_DISCONNECT then
        log.info("scan", "摄像头 app_id", app_id, "已断开")
        usb_app_id, usb_online, stream_id = nil, false, nil
        last_str, dup_cnt = nil, 0
        return   -- 帧缓冲不释放，重新接入直接复用
    end

    -- 固件注册的是 usb.EV_RX_ERROR（官方 demo 写的 EV_RX_ERR 并不存在）
    if event == usb.EV_RX_ERROR then
        log.warn("scan", "摄像头接收数据异常 app_id", app_id)
        return
    end
    if event == usb.EV_ERR_STOP then
        -- ★ 不主动 usb.reset_device：避免人为加剧 USB 重连，靠下一次 EV_CONNECT 自愈
        log.warn("scan", "摄像头异常停止 app_id", app_id, "等待重新接入")
        usb_app_id, usb_online, stream_id = nil, false, nil
        last_str, dup_cnt = nil, 0
        return
    end
end

-- ==================== 顶层注册（顺序与已验证工程一致） ====================
usb.on(0, usb_cb)
camera.preview(camera.USB, false)
camera.on(camera.USB, "scanned", nil)   -- 清残留：scanned 与 usb_raw 二选一
camera.on(camera.USB, "usb_raw", camera_cb)
log.info("scan", "回调已注册（等待 M.init() 上电枚举）")

-- ==================== 可选心跳：观察是否仍在反复重连 ====================
if HEARTBEAT_ENABLE then
    sys.taskInit(function()
        while true do
            log.info("scan", "心跳 在线", usb_online, "app_id", usb_app_id,
                     "已开流", stream_id)
            sys.wait(HEARTBEAT_MS)
        end
    end)
end

-- ==================== 初始化（内含 sys.wait，需在协程中调用） ====================
function M.init()
    -- 1) 供电：GPIO12 = 5V_EN，GPIO58 = UVC_EN（hw_init 已拉过一次，这里按官方补 PULLUP）
    pcall(gpio.setup, PIN_5V_EN, 1, gpio.PULLUP)
    pcall(gpio.set,   PIN_5V_EN, 1)
    pcall(gpio.setup, PIN_UVC_EN, 1, gpio.PULLUP)
    pcall(gpio.set,   PIN_UVC_EN, 1)
    log.info("scan", "供电已打开 5V_EN GPIO", PIN_5V_EN, "UVC_EN GPIO", PIN_UVC_EN)

    -- 2) USB 主机模式三件套（官方 main.lua 第 133~135 行）
    --    放在唯一一次 sys.wait 之前，不增加开机耗时，不影响 IP_READY
    if pm and pm.power and pm.USB and usb and usb.mode and usb.HOST then
        pcall(pm.power, pm.USB, false)
        local okm, rm = pcall(usb.mode, 0, usb.HOST)
        pcall(pm.power, pm.USB, true)
        log.info("scan", "usb.mode(0, HOST)", okm, rm, "USB 已上电，等待枚举")
    else
        log.warn("scan", "固件缺 pm.USB / usb.mode")
    end

    -- 3) 唯一一次开机等待（严格保持 3000ms）
    sys.wait(CAM_READY_MS)
    log.info("scan", "开机 USB 状态 在线", usb_online,
             "app_id", usb_app_id, "已开流", stream_id)
    if not usb_online then
        log.warn("scan", "尚未收到 EV_CONNECT；等待摄像头接入")
    end

    -- ★ 恒返回 true：app.lua 的 cam_ok 为 false 会直接播「摄像头不可用」秒退出
    return true
end

-- ==================== 开始一轮扫码（点「确认」后调用） ====================
function M.start()
    last_code, last_ms = nil, nil
    last_str, dup_cnt = nil, 0      -- 保证进入窗口后第一帧就能出结果
    scanning = true

    -- 若开机那次 EV_CONNECT 没开成流，这里补开一次（只补一次，不循环重试）
    if usb_online and usb_app_id and not stream_id then
        stream_id = open_stream(usb_app_id) and usb_app_id or nil
        log.info("scan", "扫码窗口补开流", stream_id ~= nil)
    end

    -- ★ 恒返回 true，保证 app.lua 一定进入 30 秒扫码窗口
    log.info("scan", "★ 进入扫码窗口，请把二维码对准摄像头")
    return true
end

function M.stop()
    -- 只关接收门控：摄像头保持常开流，下一笔点确认后立刻能扫，
    -- 避免反复 start/stop 让 USB 栈重枚举
    scanning = false
    log.info("scan", "扫码窗口关闭（摄像头保持就绪）")
    return true
end

return M
