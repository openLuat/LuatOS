--[[
@module  camera_app
@summary 摄像头业务封装：软件实时预览（连续抓帧 + 解码上屏）/ 拍照 / 存卡
@version 2.0
@date    2026.11.18
@usage
  对外接口（除 available/resolution/frame_path 外都含 sys.wait，必须在协程里调用）：
    camera_app.available()            固件是否带 camera 核心库
    camera_app.start_preview()        打开摄像头（UVC 会验证首帧，不开固件预览通路）
    camera_app.grab()                 抓一帧预览图到 /ram，成功返回 true
    camera_app.frame_path()           预览帧文件路径
    camera_app.capture()              拍一张静帧，成功返回 true, path
    camera_app.save_to_sd()           把最近一张照片存到 /sd
    camera_app.clear_photo()          删掉临时照片
    camera_app.stop()                 关闭摄像头、断开 UVC 供电
    camera_app.resolution()           实际生效的分辨率 w, h

  为什么是"软件预览"，不用固件的 camera.preview（真机实测结论）：
  1. 本固件（V2022_Air8101_104）+ 本板 UVC 上，camera.preview(USB, true) 虽然让 SDK 统计里的
     dec/lcd_fps 涨起来，但屏幕上的画面是**冻结**的：手在镜头前移动，画面不变；
  2. 而 camera.start + camera.capture 这条采集通路可靠：每次 35~50ms 出一帧 36KB 左右的 JPEG；
  3. 所以预览改成"连续抓帧 → lcd.image2raw 解码 → lcd.draw 上屏"，实测 5~6 fps，画面跟随镜头变化。
     注意必须用 image2raw + lcd.draw 上屏：直接 lcd.showImage 在 1024 宽的屏上会出现竖向条纹
     （按 800 宽的行宽写进了 1024 宽的面板）。

  分辨率：UVC 不支持任意分辨率，board.CAM.sensor_list 里逐档试（实测本板 800x480 / 864x480 可用，
  640x480、1280x720、640x360 均报 "not support this resolution"）。
]]

local board = require "board"

local camera_app = {}

local PREVIEW_PATH = "/ram/cam_ui_preview.jpg"
local PHOTO_PATH   = "/ram/cam_ui_shot.jpg"
local PREVIEW_TIMEOUT = 1200
local FIRST_FRAME_TIMEOUT = 750

local state = {
    opened    = false,
    id        = nil,     -- camera.start/stop/capture 用的 id
    w         = 0,       -- 实际生效的分辨率
    h         = 0,
    photo     = nil,     -- 最近一张静帧路径
    photo_len = 0,
    streaming = false,   -- 预览期间保持采集流常开（避免每帧 start/stop）
    uvc_power_held = false,
}

-- 分辨率偏好（fskv 持久化）：用户用 UI 选过之后，下次启动优先用这一档
local PREF_W, PREF_H = "cam_res_w", "cam_res_h"

local function load_pref()
    if not fskv then return end
    if fskv.init then pcall(fskv.init) end
    local ok1, w = pcall(fskv.get, PREF_W)
    local ok2, h = pcall(fskv.get, PREF_H)
    if ok1 and ok2 and type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
        -- 偏好必须仍在当前候选表里：换摄像头 / 删档位后，旧偏好要自动失效
        local valid = false
        for _, r in ipairs(board.CAM.sensor_list or {}) do
            if r[1] == w and r[2] == h then
                valid = true
                break
            end
        end
        if valid then
            state.pref_w, state.pref_h = w, h
            log.info("camera_app", "分辨率偏好", w .. "x" .. h)
        else
            log.warn("camera_app", "分辨率偏好已失效，忽略", w .. "x" .. h)
            state.pref_w, state.pref_h = nil, nil
        end
    end
end

-- 抓帧完成事件：用序号区分"本次"回调，避免上一次的残留事件被当成本次结果
local pending_seq = 0
local done_seq = 0

-- ============================ 工具函数 ============================

local function file_size(path)
    local fp = io.open(path, "rb")
    if not fp then return 0 end
    local sz = fp:seek("end") or 0
    fp:close()
    return sz
end

-- UVC 断电复位，恢复供电后等待模组启动，再交给 camera.init 枚举。
local function uvc_power_cycle(off_ms)
    local en = board.CAM.uvc_en
    if not en then return end
    gpio.setup(en, 0)
    sys.wait(off_ms or board.CAM.uvc_reset_ms or 400)
    gpio.setup(en, 1)
    sys.wait(board.CAM.uvc_startup_ms or 1500)
end

-- 整条 USB 主机复位：VBUS 掉电 → 重新设为主机模式 → 上电。
-- 热插拔后 USB 栈可能停在"设备存在但连不上"的状态（实测日志里表现为
-- Manufacturer/Product 已打印却 connect timeout），只断电摄像头救不回来，
-- 需要把主机也复位一次重新枚举。
local function usb_host_reset()
    if pm and pm.power then pcall(pm.power, pm.USB, false) end
    sys.wait(300)
    if usb and usb.mode then pcall(usb.mode, 0, usb.HOST) end
    if pm and pm.power then pcall(pm.power, pm.USB, true) end
    sys.wait(600)
end

-- 抓帧回调：参数是 JPEG 字节数（扫码结果是字符串，本 demo 不用）
local function on_scanned(_, r)
    if type(r) == "number" or r == true then
        done_seq = pending_seq
        sys.publish("CAM_FRAME_DONE")
    end
end

-- camera.init 成功时返回 0/1（老固件可能返回 true）；失败会返回错误码，不能当成功
local function init_ok(id)
    return id == 0 or id == 1 or id == true
end

-- 抓一帧到指定文件；timeout_ms 内没等到回调就算失败
local function grab_to(id, path, timeout_ms)
    pending_seq = pending_seq + 1
    local seq = pending_seq
    done_seq = 0

    camera.start(id)
    local called = camera.capture(id, path, 1)
    local got = false

    if called then
        local loops = math.floor(timeout_ms / 20)
        for _ = 1, loops do
            if done_seq == seq then
                got = true
                break
            end
            sys.wait(20)
        end
    end
    pcall(camera.stop, id)

    if not got then
        return false, 0
    end
    local size = file_size(path)
    return size > 0, size
end

-- ============================ 打开 / 关闭 ============================

local function open_dvp()
    local c = board.CAM
    local id = camera.init({
        id            = camera.DVP,
        sensor_width  = c.dvp_w,
        sensor_height = c.dvp_h,
        i2c_id        = c.dvp_i2c_id,
    })
    log.info("camera_app", "camera.init(DVP)", c.dvp_w .. "x" .. c.dvp_h, id)
    if not init_ok(id) then
        return false
    end

    state.id = camera.DVP
    state.w, state.h = c.dvp_w, c.dvp_h
    camera.on(camera.DVP, "scanned", on_scanned)
    return true
end

-- deep=false：只跑第一轮（开机自动预览用，别把启动拖太久）
-- deep=true ：第一轮失败后复位 USB 主机再跑一轮（手动点按钮 / 自动重试用）
local function open_uvc(deep, first_only)
    local c = board.CAM
    local list = camera_app.candidate_list()
    local passes = deep and 2 or 1
    local mode_count = first_only and math.min(1, #list) or #list

    for pass = 1, passes do
        if pass == 2 then
            log.warn("camera_app", "第一轮失败，复位 USB 主机后重试")
            pcall(camera.close, camera.USB)
            usb_host_reset()
            -- 断电时间拉长到 2s：热插拔后摄像头电容可能还撑着，400ms 掉不干净，
            -- 主机就看不到"拔出"，重新枚举拿到的还是旧实例
            uvc_power_cycle(2000)
        else
            uvc_power_cycle()
        end

        -- 同一轮里只上电一次，换分辨率不再断电（省时间，也避免反复重启摄像头）
        local deadline = mcu.ticks() + 12000
        for i = 1, mode_count do
            if mcu.ticks() > deadline then
                log.warn("camera_app", "本轮超时，提前结束")
                break
            end

            local w, h, first_frame_timeout = table.unpack(list[i])
            local id = camera.init({
                id            = camera.USB,
                sensor_width  = w,
                sensor_height = h,
                usb_port      = c.usb_port,
            })
            log.info("camera_app", "camera.init(UVC) pass" .. pass, w .. "x" .. h, id)

            if init_ok(id) then
                camera.on(camera.USB, "scanned", on_scanned)
                -- 专用长等待档位发一次抓帧请求，其余档位保留两次短等待。
                local attempts = first_frame_timeout and 1 or 2
                local timeout = first_frame_timeout or FIRST_FRAME_TIMEOUT
                for attempt = 1, attempts do
                    os.remove(PREVIEW_PATH)
                    if grab_to(camera.USB, PREVIEW_PATH, timeout) then
                        state.id = camera.USB
                        state.w, state.h = w, h
                        return true
                    end
                    if attempt < attempts then sys.wait(100) end
                end
                log.warn("camera_app", "未取得 UVC 首帧，尝试下一档", w .. "x" .. h)
            end

            pcall(camera.close, camera.USB)
            sys.wait(200)
        end
    end
    return false
end

local function close_camera()
    if not state.opened then return end

    camera_app.end_stream()
    if camera then
        pcall(camera.stop, state.id)
        pcall(camera.close, state.id)
    end
    -- UVC 断电，避免长时间通电发热；下次 start_preview 会重新上电复位
    if board.CAM.type == "UVC" and board.CAM.uvc_en then
        pcall(gpio.setup, board.CAM.uvc_en, 0)
    end

    state.opened, state.id, state.w, state.h = false, nil, 0, 0
    sys.wait(200)
end

-- 连续抓帧失败计数：UVC 采集跑久了会停，连续失败就重启摄像头
local fail_count = 0

-- ============================ 采集流 ============================

--[[
预览期间把采集流打开一次，之后只重复 capture。
实测：每帧 start/capture/stop 要 145ms，start 一次后每帧 capture 只要 51ms。
]]
function camera_app.begin_stream()
    if not state.opened or state.streaming then return end
    camera.start(state.id)
    state.streaming = true
    sys.wait(100)
end

function camera_app.end_stream()
    if not state.streaming then return end
    pcall(camera.stop, state.id)
    state.streaming = false
end

-- ============================ 对外接口 ============================

function camera_app.available()
    return camera ~= nil
end

--[[
按"用户偏好优先"排好的候选分辨率表。
@api camera_app.candidate_list()
@return table {{w,h,first_frame_timeout_ms}, ...}
]]
function camera_app.candidate_list()
    local list = {}
    if state.pref_w and state.pref_h then
        list[#list + 1] = { state.pref_w, state.pref_h }
    end
    for _, r in ipairs(board.CAM.sensor_list or {}) do
        if state.pref_w == r[1] and state.pref_h == r[2] then
            list[1] = r
        else
            list[#list + 1] = r
        end
    end
    return list
end

--[[
设置分辨率偏好（写 fskv，下次启动继续生效）。
@api camera_app.set_preferred(w, h)
]]
function camera_app.set_preferred(w, h)
    state.pref_w, state.pref_h = w, h
    if fskv then
        pcall(fskv.set, PREF_W, w)
        pcall(fskv.set, PREF_H, h)
    end
    log.info("camera_app", "分辨率偏好已保存", w .. "x" .. h)
end

function camera_app.preferred()
    return state.pref_w, state.pref_h
end

--[[
按 board.CAM.sensor_list 的顺序取下一档（当前档的下一项，末项回到第一项）。
@api camera_app.next_mode()
@return number, number 下一档宽高
]]
function camera_app.next_mode()
    local list = board.CAM.sensor_list or {}
    if #list == 0 then return 960, 480 end
    for i, r in ipairs(list) do
        if r[1] == state.w and r[2] == state.h then
            local n = list[i % #list + 1]
            return n[1], n[2]
        end
    end
    return list[1][1], list[1][2]
end

-- 一次性重启标记（fskv）：成功后清零，失败时最多重启一次
local FSKV_KEY = "cam_rb"

local function flag_get()
    if not fskv then return nil end
    local ok, v = pcall(fskv.get, FSKV_KEY)
    if ok then return v end
    return nil
end

local function flag_clear()
    if not fskv then return end
    pcall(fskv.set, FSKV_KEY, 0)
end

--[[
热插拔兜底：自动重试全失败后调用。返回 true 表示已经触发重启（调用方不要再改界面）。
@api camera_app.try_reboot_once()
@return boolean
]]
function camera_app.try_reboot_once()
    if not (rtos and rtos.reboot) then
        return false
    end
    if flag_get() == 1 then
        log.warn("camera_app", "本次上电已重启过一次，不再重启")
        return false
    end
    if fskv then
        pcall(fskv.set, FSKV_KEY, 1)
    end
    log.warn("camera_app", "UVC 热插拔后连接不上，重启一次走开机路径")
    sys.wait(200)
    rtos.reboot()
    return true
end

function camera_app.resolution()
    return state.w, state.h
end

load_pref()

function camera_app.frame_path()
    return PREVIEW_PATH
end

--[[
打开摄像头（UVC 验证首帧；预览靠 grab + ui.draw_frame 软件上屏）。
@api camera_app.start_preview(deep, first_only)
@boolean deep true 时失败后会复位 USB 主机再试一轮（手动点按钮/自动重试用）
@boolean first_only true 时仅尝试首选分辨率，用于 LCD 初始化之前的快速探测
@return boolean, string 成功返回 true；失败返回 false, 文案键
]]
function camera_app.start_preview(deep, first_only)
    if not camera_app.available() then
        return false, "err_no_lib"
    end
    if state.opened then
        return true
    end

    local ok
    if board.CAM.type == "DVP" then
        ok = open_dvp()
    else
        ok = open_uvc(deep, first_only)
    end
    if not ok then
        return false, "err_cam_init"
    end

    state.opened = true
    flag_clear()
    log.info("camera_app", "摄像头就绪", state.w .. "x" .. state.h)
    return true
end

-- UART 人脸操作期间推迟 UVC 断电恢复，两路共用同一个电源。
function camera_app.hold_uvc_power(hold)
    if hold and (board.CAM.type ~= "UVC" or not state.opened) then
        return false
    end
    state.uvc_power_held = hold
    return true
end

--[[
抓一帧预览图（写 /ram/cam_ui_preview.jpg）。
@api camera_app.grab()
@return boolean, number 成功返回 true, 字节数
]]
function camera_app.grab()
    if not state.opened then
        return false, 0
    end

    -- 注意：不能用"采集流常开 + 每帧只 capture"。
    -- 实测那样虽然快（每帧 51ms vs 145ms），但屏幕上不再更新（拿到的 JPEG 解码失败）；
    -- 所以这里仍然每帧 start → capture → stop。
    local ok, size = grab_to(state.id, PREVIEW_PATH, PREVIEW_TIMEOUT)
    if ok then
        if fail_count > 0 then
            log.info("camera_app", "抓帧恢复")
        end
        fail_count = 0
        return true, size
    end

    fail_count = fail_count + 1
    log.info("camera_app", "抓帧失败", fail_count)
    if fail_count >= 3 and not state.uvc_power_held then
        log.warn("camera_app", "连续抓帧失败，重启摄像头")
        close_camera()
        sys.wait(300)
        camera_app.start_preview()
        fail_count = 0
    end
    return false, 0
end

--[[
拍一张静帧（写 /ram/cam_ui_shot.jpg），摄像头保持打开，方便回到预览。
@api camera_app.capture()
@return boolean, string 成功返回 true, 照片路径；失败返回 false, 文案键
]]
function camera_app.capture()
    if not camera_app.available() then
        return false, "err_no_lib"
    end
    if not state.opened then
        local ok, err = camera_app.start_preview()
        if not ok then
            return false, err
        end
    end

    camera_app.end_stream()          -- 静帧走独立的一次采集，先停掉预览流
    local ok, size = grab_to(state.id, PHOTO_PATH, 3000)
    if not ok then
        log.info("camera_app", "抓帧失败")
        return false, "err_capture"
    end

    state.photo = PHOTO_PATH
    state.photo_len = size
    log.info("camera_app", "拍照完成", size, "字节")
    return true, PHOTO_PATH
end

--[[
停止预览并释放摄像头（UVC 同时断电）。
@api camera_app.stop()
]]
function camera_app.stop()
    close_camera()
end

-- 挂载 TF 卡到 /sd（没插卡 / 没格式化不算错误，返回 false 即可）
local function mount_sd()
    if not fatfs then
        log.warn("camera_app", "固件未包含 fatfs")
        return false, "err_no_fatfs"
    end
    if board.SD.en then
        gpio.setup(board.SD.en, 1)
        sys.wait(50)
    end

    local ok = fatfs.mount(fatfs.SDIO, "/sd", 24000)
    if not ok then
        sys.wait(100)
        ok = fatfs.mount(fatfs.SDIO, "/sd", 24000)
    end
    log.info("camera_app", "fatfs.mount /sd", ok)
    if not ok then
        return false, "err_sd_mount"
    end
    return true
end

--[[
把最近一张照片存到 TF 卡。
@api camera_app.save_to_sd()
@return boolean, string, number 成功返回 true, 目标路径, 字节数；失败返回 false, 文案键
]]
function camera_app.save_to_sd()
    if not state.photo then
        return false, "err_no_photo"
    end

    local mounted, mount_err = mount_sd()
    if not mounted then
        return false, mount_err or "err_sd_mount"
    end

    local data = io.readFile(state.photo)
    if not data then
        return false, "err_read"
    end

    local path = "/sd/cam_" .. os.date("%Y%m%d_%H%M%S") .. ".jpg"
    if not io.writeFile(path, data) then
        return false, "err_write"
    end

    log.info("camera_app", "已保存", path, #data, "字节")
    return true, path, #data
end

--[[
删除临时照片（复位界面时用）。
@api camera_app.clear_photo()
]]
function camera_app.clear_photo()
    if state.photo then
        os.remove(state.photo)
    end
    state.photo = nil
    state.photo_len = 0
end

function camera_app.last_photo()
    return state.photo
end

function camera_app.last_size()
    return state.photo_len
end

return camera_app
