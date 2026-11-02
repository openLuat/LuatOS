--[[
@module  uvc_preview_win
@summary 摄像头测试页（UVC 预览 / 拍照 / 录像 + 人脸识别录入 / 验证 / 删除全部，TabOS 深色玻璃态）
@version 1.5
@date    2026.10.30
@author  江访
@usage
订阅: OPEN_UVC_PREVIEW_WIN(id)
发布: OTHER_FUNC_SET(id, true)  -- 进页面给摄像头供电
发布: OTHER_FUNC_SET(id, false) -- 退页面断电

按钮一律经 sys.publish("UVC_CMD", cmd) 进协程执行：
excamera.open / preview / close 与 exfacecam 的各条指令内部都有 sys.wait，
只能在协程里调用。

数据流由本页独占：外设开关（periph_uvc）只管供电脚，不再 camera.init，
避免与 excamera.open 里的 camera.init 二次初始化打架。

导航：标题栏「返回」回到功能测试页；底部「退出」经命令协程收尾后回桌面（exwin.return_idle）。

【人脸识别】摄像头是 AirCAMERA_1034 人脸识别模组时，同一颗模组出两条通路：
USB 走 UVC 出 MJPEG 画面（上面那套 excamera 独占），UART 走协议做人脸。
config.peripherals 的 uvc 条目带 face 子表即在页面多出「人脸识别」页签，
不带的型号页面与原来完全一致，只有「UVC 测试」。见下方「人脸识别边界」。

分辨率与内存（取档做法参考 module/Air8601/project/DEPOSIT_CABINET 的 face_preview）：
1. 开流分辨率默认 1280×720（USB 摄像头常用档），先枚举它真正支持的 MJPEG 档位，
   首选 config.peripherals 条目里的 w / h，其次取像素数不超过 MAX_PIXELS 的最大档；
   申请档位与实际支持档位不一致时按实际档位重开一次数据流，保证 excamera 的双帧缓冲
   与固件解码缓冲都按真实尺寸分配。
2. airui.camera 的两块显示缓冲按预览区大小分配（视口 w×h×2 字节 × 2 块，与 fit 无关），
   预览区因此按剩余内存收口（见 preview_size），与源分辨率同比、居中于黑底框内。
   源分辨率越大，相机侧吃掉的越多，预览区就越小——这是源分辨率与预览面积的直接取舍。
3. airui.camera 组件必须在建界面时建好、register + start，且早于 excamera.open 开流。
   组件建晚了（例如等 USB connected 再建）时，固件解码出的预览帧找不到接收方，
   全程不出画面且一条报错日志都没有；ingest 侧组件未 start / 未挂目标时也都是静默丢帧。

已知边界：
1. 拍照 / 录像直接取当前推流里的 MJPEG 帧落盘（帧本身就是完整 JPEG），不关流不重建，
   画面不断。excamera.photo / excamera.video 走的是 camera.start + camera.capture 的
   DVP/SPI 采集通路（luat_camera_capture 在本固件是 LUAT_WEAK 空实现，日志打
   D/camera not support yet），USB 摄像头上必然失败，故本页不用这两个接口。
2. 本固件没有 MP4 封装，录像文件是 .mjpg（MJPEG 帧序列，可用 ffplay -f mjpeg 或
   VLC 播放）。文件按 REC_SAMPLE 抽帧落盘，避免写盘阻塞 USB 收流；
   到 rec_max_bytes 上限自动停帧，状态行会标注。
3. 录像按时长档（5/10/30 秒）录制，倒计时结束自动停止。
4. 落盘目录按实际写探针选（写内容 + 读回比对，只建空文件不算）：SD 卡可写就写
   /sd/photo/，写不了才退回 /ram/photo/（掉电即失、上限更小）。文件名按时间 + 序号
   生成，不覆盖旧文件。SD 卡文件系统由平台挂载，本页不卸载重挂、不重复初始化 SD 卡。
5. excamera.open 里的 fps 会调 camera.config(0, CONF_UVC_FPS, …)，
   本固件未实现该配置项，每次开流会打一条 D/camera not support yet，属正常噪声。
6. 停数据流与销毁组件的顺序不可颠倒：先 excamera.close（前面留 CLOSE_GRACE 让在途帧
   回调跑完）再动 airui.camera 组件；反序会让固件解码线程往已释放的组件里画，
   触发非对齐访问死机。关窗时根控件先 set_hidden 立刻撤画面，销毁交回命令协程收尾。
7. 「退出」不直接 exwin.return_idle：桌面 MP4 播放器获得焦点即起播，早于收尾会和
   未关的相机抢内存。退出发 UVC_CMD("quit")，命令协程跑完 do_teardown（停流、
   销毁组件、断电）后才 exwin.return_idle。收尾命令带界面代数，上一代的 quit
   不拆新页面，只补关它的数据流。

人脸识别边界：
1. 供电共用：UVC_EN 一根脚同时供出图与人脸模组，断电两者一起掉。「连不上就断电
   重枚举」不能当常规手段（会把正在跑的人脸模组一起杀掉）；反过来，录入 / 验证前
   必须断电重枚举一次 —— 停掉 MJPEG 推流后模组仍停在出图模式，此时发录入指令它不
   回包（现场日志 cmd timeout 0x1D），取版本这类纯协议指令却正常。断电重枚举让它
   回人脸采集模式，串口随之重开一遍（见 face_reenumerate）。
2. 人脸指令是串行的：exfacecam 内部是单例状态（回包表 / 状态回调共享），并发跑
   register 与 verify 会互相抢回包。本页所有人脸动作都进同一个命令协程，天然串行，
   另设 face_busy 挡掉重复点击。
3. 人脸状态回调在 UART 收包上下文里跑，只能发消息不能碰控件（参考工程实测在回调里
   做界面会叠加崩溃）。这里回调只做 500ms 限流 + sys.publish，界面更新交给订阅侧。
4. 长动作期间停推流：录入 / 验证会占满 CPU，与 MJPEG 收流叠加时识别会超时
   （参考工程 face_preview 的实测结论）。动作前 close_stream + stop_widget（airui.camera
   停流后继续显示最后一帧，不黑屏），动作结束 open_stream 重开。
]]

local theme = require "ui_theme"

--[[
编译系统按 require "excamera" 的字面文本决定打包范围，故这里保持字面写法；
又因为相机核心库缺失的固件上本页也必须能加载（否则本文件 require 失败会中断
ui_main.optional 的后续加载，连带别的窗口都打不开），所以用 pcall 兜住。]]
local function load_excamera()
    return require "excamera"
end

local ok_cam, cam_lib = pcall(load_excamera)
local excamera = ok_cam and cam_lib or nil
if not excamera then
    log.warn("uvc_preview_win", "excamera 加载失败，预览功能不可用")
end

--[[
人脸识别模组协议库（AirCAMERA_1034，UART 115200/8N1）。
与 excamera 同一套做法：编译系统按 require "exfacecam" 的字面文本决定打包范围，
库里缺它时本页也必须能加载（否则 require 失败会中断 ui_main.optional 的后续加载），
所以用具名函数包一层再 pcall 兜住。]]
local function load_exfacecam()
    return require "exfacecam"
end

local ok_face, face_lib = pcall(load_exfacecam)
local exfacecam = ok_face and face_lib or nil
if not exfacecam then
    log.warn("uvc_preview_win", "exfacecam 加载失败，人脸识别不可用")
end

local window_id = nil
local main_container = nil

local sw, sh = 480, 800
local pad = 15

-- 源分辨率：开流前按它申请帧缓冲，连上后由 pick_uvc_mode 校正为实际支持档。
-- 相机侧固定开销约 4.25×w×h 字节（双帧缓冲 w×h + 解码输入 w×h/4 + 解码输出 w×h×2），
-- 1280×720 约 3.8MB，这一项直接决定还剩多少内存给 airui.camera 的显示缓冲
local SENSOR_W, SENSOR_H = 1280, 720

-- 源分辨率像素上限：像素数更大的 MJPEG 档位不取（1920×1080 时相机侧要吃掉 8.8MB）
local MAX_PIXELS = 1280 * 720

-- airui.camera 双显示缓冲预算上限（2 块 × 视口 w×h×2 字节）。
-- 1280×720 实测预览区 894×421 时单块 752KB 分配失败，故上限压到 512KB；
-- 实际预算还要按开流后的剩余内存再收一次（见 preview_size）
local PREVIEW_FB_BUDGET = 512 * 1024

-- 停流前宽限：等一帧时间让在途帧回调跑完，避免读到 excamera.close 已释放的 zbuff
local CLOSE_GRACE = 300

-- config.peripherals 条目里的首选分辨率（不写则用上面的默认档）
local PREF_W, PREF_H = nil, nil

-- 画面适配模式（airui.camera 的 set_fit 取值），按此顺序循环
local FIT_ORDER = { "contain", "cover", "center", "stretch" }
local FIT_TITLE = {
    contain = "适应", cover = "铺满", center = "居中", stretch = "拉伸",
}

-- 录像时长档位（毫秒）
local REC_ORDER = { 5000, 10000, 30000 }

-- 录像抽帧：每 N 帧取 1 帧落盘（15fps 推流下约 5fps），避免写盘阻塞 USB 收流
local REC_SAMPLE = 3

-- ==================== 人脸识别常量 ====================

-- 页签取值；只有 config.peripherals 条目里带 face 子表才出第二个页签
local TAB_UVC, TAB_FACE = "uvc", "face"

-- 人脸状态码 → 引导文案。模组在录入 / 验证过程中按 ~15fps 回调，
-- 取值范围与含义见 exfacecam.register / verify 的 on_state 约定
local FACE_STATE_TEXT = {
    [0] = "请正对摄像头", [1] = "未检测到人脸", [2] = "请抬头", [3] = "请低头",
    [4] = "请向右转", [5] = "请向左转", [6] = "请靠近一些", [7] = "请远离一些",
    [8] = "眉毛被遮挡", [9] = "眼睛被遮挡", [10] = "面部被遮挡", [11] = "角度异常",
}

-- exfacecam 错误码（MR_*）→ 中文说明，比对不上就退回「错误码 N」
local FACE_ERR_TEXT = {
    [1] = "未通过（人脸不匹配）", [2] = "已中止", [4] = "摄像头异常",
    [5] = "未知原因失败", [6] = "参数无效", [7] = "内存不足",
    [8] = "用户不存在", [9] = "用户数已满", [10] = "该人脸已录入",
    [12] = "活体检测未通过", [13] = "操作超时", [14] = "授权校验失败",
}

-- 人脸状态提示最小间隔(ms)：模组回得快，不压一压状态行会刷到看不清
local FACE_STATE_MIN_GAP = 500

-- 运行期状态
local cam_widget = nil          -- airui.camera 控件
local widget_registered = false -- 是否已挂到解码通道
local fit_mode = "contain"
local rec_ms = 10000
local busy = false              -- 拍照/录像互斥
local cmd_running = false       -- 命令协程存活标志
local cmd_started = false       -- 命令协程只启动一次，重复进页不产生第二个协程
local rec_timer = nil           -- 录像倒计时定时器
local closing = false           -- excamera.close 是否在进行（开流前要等它收尾）
local stream_open = false       -- excamera 数据流是否开着（重复进页时先把上代残留流关掉）
local window_open = false       -- 页面是否在前台
local ui_gen = 0                -- 界面代数：关窗的收尾只能动同代界面
local stale_ui = nil            -- 停流期间来不及销毁的上代界面，交回命令协程销毁
local quit_to_idle = false      -- 「退出」请求：收尾跑完后才回桌面

local periph_id = nil           -- config.peripherals 里的 UVC 实例 id
local save_base = "/ram/photo/" -- 落盘目录（见 save_dir）
local photo_path = "/ram/photo/uvc_photo.jpg"
local video_path = "/ram/photo/uvc_video.mjpg"
local file_seq = 0              -- 落盘序号，用来保证文件名不重复

-- 预览区（黑底框）位置，airui.camera 控件按源分辨率同比居中放在框内
local preview_area = nil

-- 拍照：置位后由下一帧回调落盘（帧缓冲会被后续帧覆盖，只能在回调里取）
local snap_pending = false
-- 录像：文件句柄为 nil 表示未在录；帧数/字节数只在回调里累加
local rec_file = nil
local rec_frames = 0            -- 推流进来的总帧数
local rec_saved = 0             -- 实际落盘的帧数
local rec_written = 0           -- 已落盘字节数
local rec_full = false          -- 是否因达到上限停帧
local rec_max_bytes = 4 * 1024 * 1024
local quit_requested = false    -- 页面已销毁，长动作尽快收尾

local status_label = nil
local status_w = 0

-- 人脸识别运行期状态（约束见文件头「人脸识别边界」）
local face_cfg = nil        -- config.peripherals 条目里的 face 子表，nil 表示本板没有人脸模组
local face_pwr = nil        -- 摄像头供电脚（条目的 en_pin），录入前断电重枚举用，nil 表示不可控
local face_on = false       -- exfacecam 串口是否已打开
local face_busy = false     -- 录入 / 验证 / 清空 / 读版本进行中，挡重复点击
local face_seq = 0          -- 录入名序号，保证每次录入的用户名不重复
local face_tab = TAB_UVC    -- 当前页签
local face_last_state = 0   -- 最近一次状态提示时刻(ms)，做人脸引导文案限流

-- 页签行与控制栏各摆两份，靠 set_hidden 切换（重建控件只能在界面线程，见 create_widget）
local tab_uvc_row = nil     -- 页签行（UVC 高亮）
local tab_face_row = nil    -- 页签行（人脸高亮）
local uvc_bar = nil         -- UVC 控制栏（拍照 / 录像 / 时长 / 适配 / 退出）
local face_bar = nil        -- 人脸控制栏（录入 / 验证 / 清空 / 版本 / 退出）

local preview_callback  -- 前向声明：open_stream 里要传给 excamera.preview

-- ==================== 基础工具 ====================

local function update_screen_size()
    sw, sh = screen_w or 480, screen_h or 800
    sw, sh = theme.content_fit(sw, sh)
    pad = theme.page_margin()
end

-- 刷新底部状态行（超出宽度自动截断，避免撑出滚动条）
local function update_status(text)
    if status_label and not status_label:is_destroyed() then
        status_label:set_text(theme.fit_text(tostring(text or ""), status_w, theme.fs("caption")))
    end
end

-- 停掉录像倒计时定时器
local function stop_rec_timer()
    if rec_timer then
        pcall(sys.timerStop, rec_timer)
        rec_timer = nil
    end
end

-- ==================== 落盘（SD 卡 / 内存盘） ====================

-- 拼路径：base 下挂子项，base 自带尾斜杠时不重复加
local function join(base, name)
    if base:sub(-1) == "/" then return base .. name end
    return base .. "/" .. name
end

--[[
写探针：建文件、写内容、读回比对，三步都过才算可写。
只建空文件是不够的——部分 TF 卡在高 SPI 时钟下能挂载，一写数据就报
SPI_TF write data timeout / SDHC error，空文件探针会误判为可写。]]
local function dir_writable(base)
    local probe = join(base, ".uvc_probe")
    local fd = io.open(probe, "w")
    if not fd then return false end
    fd:write("uvc_probe")
    fd:close()
    local rd = io.open(probe, "r")
    if not rd then
        pcall(os.remove, probe)
        return false
    end
    local data = rd:read("*a")
    rd:close()
    pcall(os.remove, probe)
    return data == "uvc_probe"
end

-- 落盘目录：base 下的 photo 子目录，目录不存在就建
local function photo_dir_of(base)
    local dir = join(base, "photo")
    if not io.dexist(dir) then
        pcall(io.mkdir, dir)
    end
    local path = join(dir, "")
    log.info("uvc_preview_win", "落盘目录", path)
    return path
end

--[[
落盘目录：SD 卡可写就写卡下的 photo 子目录，写不了才退回内存盘 /ram（掉电即失）。
SD 卡文件系统由平台挂载，本页只做写探针判定落盘位置，不重复初始化 SD 卡。]]
local function save_dir()
    local cfg = _G.project_config or {}
    local f = cfg.features or {}

    if f.sd_card and dir_writable("/sd/") then
        return photo_dir_of("/sd/")
    end
    if f.sd_card then
        log.warn("uvc_preview_win", "SD 卡不可写，照片改存 /ram（掉电即失）")
    end
    if dir_writable("/ram/") then
        return photo_dir_of("/ram/")
    end
    return "/ram/photo/"
end

-- 本轮落盘文件名：优先按 RTC 时间命名，时间无效时用自增序号，末尾补序号保证不覆盖旧文件
local function next_path(ext)
    file_seq = file_seq + 1
    local name
    local ok, ts = pcall(os.time)
    if ok and type(ts) == "number" and ts > 1600000000 then
        name = os.date("uvc_%Y%m%d_%H%M%S", ts)
    else
        name = string.format("uvc_%04d", file_seq)
    end
    return save_base .. name .. "_" .. file_seq .. ext
end

-- 取 config.peripherals 里的 UVC 实例：优先 id 命中（预览页可由某一行点进来），
-- 命不中则退回第一条 uvc，用于补齐 id 与分辨率参数
local function find_uvc()
    local cfg = _G.project_config or {}
    local list = cfg.peripherals
    if type(list) ~= "table" then return nil end
    local first = nil
    for _, p in ipairs(list) do
        if p and p.type == "uvc" then
            if p.id and periph_id and p.id == periph_id then return p end
            if not first then first = p end
        end
    end
    return first
end

-- excamera.open 的 USB 摄像头配置表（只用于开推流，拍照/录像取推流帧落盘）
local function cam_param()
    return {
        id            = camera.USB,
        sensor_width  = SENSOR_W,
        sensor_height = SENSOR_H,
        usb_port      = 1,
        work_mode     = 2,
        fps           = 15,
    }
end

-- 相机能力是否齐备
local function cam_ready()
    return excamera ~= nil and camera ~= nil and camera.USB ~= nil
end

-- ==================== UVC 档位自适应 ====================

--[[
枚举摄像头真正支持的 MJPEG 档位，选一档回来：
首选 config 指定的 w/h，其次像素数不超过 MAX_PIXELS 的最大档，都没有就取最小档。
拿到的 w/h 用来校正 excamera 的帧缓冲尺寸（它按 open 时的 w×h 建双缓冲）。]]
local function pick_uvc_mode(app_id)
    if not camera.get_usb_config then return nil end
    local res, format_num = camera.get_usb_config(app_id, camera.CONF_UVC_FORMAT)
    if not format_num or format_num <= 0 then
        log.warn("uvc_preview_win", "UVC 格式枚举失败", res, format_num)
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
                    log.info("uvc_preview_win", "UVC 支持", w, "x", h, "fps", fps)
                    if not smallest or m.px < smallest.px then smallest = m end
                    if PREF_W == w and PREF_H == h then exact = m end
                    if m.px <= MAX_PIXELS and (not best or m.px > best.px) then best = m end
                end
            end
        end
    end
    if exact then return exact end
    if best then return best end
    if smallest then
        log.warn("uvc_preview_win", "无预算内档位，改用最小档", smallest.w, smallest.h)
    end
    return smallest
end

-- 堆剩余字节（sys + psram 合计，两个池都可能放相机缓冲与显示缓冲），取不到返回 nil
local function heap_free()
    local total = 0
    local got = false
    for _, pool in ipairs({ "sys", "psram" }) do
        local ok, t, u = pcall(rtos.meminfo, pool)
        if ok and type(t) == "number" and type(u) == "number" and t > u then
            total = total + (t - u)
            got = true
        end
    end
    return got and total or nil
end

-- 相机侧开销：双帧缓冲 w×h + 解码输入 w×h/4 + 解码输出 w×h×2，合计约 4.25×w×h
local function sensor_cost()
    return math.floor(SENSOR_W * SENSOR_H * 4.25) + 16 * 1024
end

-- 预览区尺寸：与源分辨率同比缩进黑底框，再按显示缓冲预算收口
local function preview_size(avail_w, avail_h)
    local src_w = SENSOR_W > 0 and SENSOR_W or 16
    local src_h = SENSOR_H > 0 and SENSOR_H or 9
    local w, h = math.floor(avail_w), math.floor(avail_h)
    local scale = math.min(w / src_w, h / src_h)
    w, h = math.floor(src_w * scale), math.floor(src_h * scale)
    -- 双显示缓冲 = 2 块 × w×h×2 字节。预算上限是 PREVIEW_FB_BUDGET，
    -- 这里测到的是开流前的剩余，还要先把相机侧那 4.25×w×h 扣掉，剩下的才是显示缓冲能用的
    local budget = PREVIEW_FB_BUDGET
    collectgarbage()
    local free = heap_free()
    if free then
        local after = math.floor((free - sensor_cost()) * 0.6)
        if after < budget then budget = after end
        log.info("uvc_preview_win", "内存预算", "开流前剩余", free,
            "相机侧", sensor_cost(), "显示缓冲", budget)
    end
    if budget < 64 * 1024 then budget = 64 * 1024 end
    local max_px = math.floor(budget / 4)
    if w * h > max_px then
        local k = math.sqrt(max_px / (w * h))
        w, h = math.floor(w * k), math.floor(h * k)
    end
    if w < theme.dp(80) then w = theme.dp(80) end
    if h < theme.dp(60) then h = theme.dp(60) end
    log.info("uvc_preview_win", "预览区", w, "x", h, "显示缓冲", (w * h * 4), "字节")
    return w, h
end

-- ==================== 推流帧落盘（回调上下文，禁止 sys.wait） ====================

-- 把一帧 MJPEG 写成文件；MJPEG 帧本身就是完整 JPEG，可直接当 .jpg 用
local function write_frame(path, buff, len)
    local f = io.open(path, "w")
    if not f then
        log.error("uvc_preview_win", "无法创建文件", path)
        return false
    end
    local data = buff:toStr(0, len)
    if not data then
        f:close()
        return false
    end
    f:write(data)
    f:close()
    return true
end

-- 收到一帧：拍照按需存单帧，录像抽帧追加进同一个文件
local function on_frame(buff, len)
    if not buff or not len or len <= 0 then return end

    if snap_pending then
        snap_pending = false
        sys.publish("UVC_SNAP_DONE", write_frame(photo_path, buff, len))
    end

    if rec_file then
        rec_frames = rec_frames + 1
        if not rec_full and (rec_frames % REC_SAMPLE) == 1 then
            if rec_written + len > rec_max_bytes then
                rec_full = true
            else
                local data = buff:toStr(0, len)
                if data then
                    rec_file:write(data)
                    rec_written = rec_written + #data
                    rec_saved = rec_saved + 1
                end
            end
        end
    end
end


-- ==================== 摄像头数据流（只在协程里调用） ====================

-- 等上一轮停流收尾，避免新旧数据流抢 excamera 的单例状态
local function wait_closing()
    local t = 0
    while closing and t < 3000 do
        sys.wait(50)
        t = t + 50
    end
end

--[[
关数据流：先 excamera.close 停流并释放帧缓冲，等固件解码/显示任务收尾。
组件的 stop / destroy 必须排在它后面（见 stop_widget），反序会让解码线程往
已释放的组件里画，触发非对齐访问死机。]]
local function close_stream()
    closing = true
    if excamera then
        sys.wait(CLOSE_GRACE)
        pcall(excamera.close)
        sys.wait(100)
    end
    stream_open = false
    widget_registered = false
    closing = false
end

-- 停组件显示（保留最后一帧，不释放缓冲），只允许在数据流已关掉之后调用
local function stop_widget()
    if cam_widget and not cam_widget:is_destroyed() then
        pcall(cam_widget.stop, cam_widget)
    end
end

-- 开数据流；摄像头连接后由 preview_callback 校正分辨率并挂控件
local function open_stream()
    if not cam_ready() then return false, "相机能力不可用" end
    wait_closing()
    if not excamera.open(cam_param()) then
        stream_open = false
        return false, "摄像头打开失败"
    end
    if not excamera.preview(preview_callback) then
        pcall(excamera.close)
        stream_open = false
        return false, "预览启动失败"
    end
    stream_open = true
    return true
end

-- 把显示组件挂到解码通道（register_target 在建组件时已挂过，这里只是兜底重挂）
local function register_widget()
    if not cam_widget or cam_widget:is_destroyed() then return false end
    if not widget_registered then
        pcall(cam_widget.register, cam_widget)
        widget_registered = true
    end
    return true
end

-- 按当前源分辨率建 airui.camera 控件（放在黑底框内居中）
-- 必须在 LVGL 线程建组件并挂到解码通道，且要早于 excamera.open 开流：
-- 晚于开流再挂，固件解码出来的预览帧找不到接收方，画面一片黑（无任何日志）
local function create_widget()
    if cam_widget and not cam_widget:is_destroyed() then return true end
    if not preview_area then
        log.warn("uvc_preview_win", "预览区未就绪，跳过建组件")
        return false
    end

    local w, h = preview_size(preview_area.w, preview_area.h)
    local x = preview_area.x + math.floor((preview_area.w - w) / 2)
    local y = preview_area.y + math.floor((preview_area.h - h) / 2)

    local okw, wdg = pcall(airui.camera, {
        parent = main_container,
        x = x, y = y, w = w, h = h,
        fit = fit_mode, auto_start = false,
    })
    cam_widget = okw and wdg or nil
    widget_registered = false
    if not cam_widget then
        log.warn("uvc_preview_win", "airui.camera 创建失败")
        update_status("本固件不含 airui.camera 组件，无法显示画面")
        return false
    end
    log.info("uvc_preview_win", "预览组件", w, "x", h, "源", SENSOR_W, "x", SENSOR_H)
    return true
end

-- 起显示：挂解码通道 + 开接收（数据流可以还没连上，组件先待命）
local function start_widget()
    if not register_widget() then return end
    pcall(cam_widget.start, cam_widget)
end

-- USB 连接事件（协程内执行）：分辨率不一致就按实际档位重开一次；组件建于建界面时，这里只管数据流
local function on_connected(mode)
    if not window_open then return end
    if mode and (mode.w ~= SENSOR_W or mode.h ~= SENSOR_H) then
        log.info("uvc_preview_win", "改用摄像头实际支持的分辨率", mode.w, "x", mode.h)
        SENSOR_W, SENSOR_H = mode.w, mode.h
        close_stream()
        sys.wait(150)
        local ok, err = open_stream()
        if not ok then
            update_status(tostring(err))
        end
        return
    end
    start_widget()
    -- 预览行只归 UVC 页签：人脸页签的状态行留给录入/验证结果，不被重连事件盖掉
    if face_tab == TAB_UVC then
        update_status("预览中 " .. SENSOR_W .. "x" .. SENSOR_H ..
                      " | 适配 " .. (FIT_TITLE[fit_mode] or fit_mode))
    end
end

-- excamera 预览事件：新帧 / 连接 / 断开 / 异常（在 USB 事件上下文里回调，非协程）
function preview_callback(event, ...)
    if event == "frame" then
        local buff, len = ...
        on_frame(buff, len)
    elseif event == "connected" then
        local app_id = ...
        -- 档位枚举是只读查询，可直接在回调里做；后续动作一律交回命令协程
        local okm, mode = pcall(pick_uvc_mode, app_id)
        sys.publish("UVC_CMD", "connected", okm and mode or nil)
    elseif event == "disconnected" then
        if cam_widget and not cam_widget:is_destroyed() then
            pcall(cam_widget.stop, cam_widget)
        end
        widget_registered = false
        rec_full = true          -- 停止录像写帧，文件交回 do_record 收尾
        if snap_pending then
            snap_pending = false
            sys.publish("UVC_SNAP_DONE", false)
        end
        update_status("摄像头已断开")
    elseif event == "error" then
        update_status("摄像头错误: " .. tostring((...)))
    end
end

-- ==================== 动作（协程内执行） ====================

-- 拍照：下一帧 MJPEG 直接落盘成 .jpg（不断流）
local function do_photo()
    if busy then return end
    if not cam_ready() then
        update_status("相机能力不可用")
        return
    end
    busy = true
    update_status("拍照中...")
    photo_path = next_path(".jpg")
    snap_pending = true
    local got, ok = sys.waitUntil("UVC_SNAP_DONE", 4000)
    if not got or not ok then
        snap_pending = false
        update_status("拍照失败：未收到图像帧，请确认摄像头已连接")
    else
        local kb = math.floor((io.fileSize(photo_path) or 0) / 1024)
        update_status("已保存 " .. photo_path .. " | " .. kb .. "KB")
    end
    busy = false
end

-- 录像：推流帧抽样追加进 .mjpg（MJPEG 帧序列），到时长自动停止
local function do_record()
    if busy then return end
    if not cam_ready() then
        update_status("相机能力不可用")
        return
    end
    busy = true
    local secs = math.floor(rec_ms / 1000)
    update_status("录像中 " .. secs .. " 秒，请保持画面稳定...")

    -- 倒计时走定时器：下面 sys.wait(rec_ms) 会阻塞本协程，不能自己刷
    local left = secs
    rec_timer = sys.timerLoopStart(function()
        left = left - 1
        if left >= 0 then
            update_status("录像中，剩余 " .. left .. " 秒...")
        end
    end, 1000)

    rec_frames, rec_saved, rec_written, rec_full = 0, 0, 0, false
    video_path = next_path(".mjpg")
    rec_file = io.open(video_path, "w")
    if not rec_file then
        stop_rec_timer()
        update_status("无法创建文件 " .. video_path)
        busy = false
        return
    end

    -- 分片等待：中途退出页面要能立刻收尾，不能闷满整个时长
    local waited = 0
    while waited < rec_ms and not quit_requested do
        local step = math.min(500, rec_ms - waited)
        sys.wait(step)
        waited = waited + step
    end

    local f = rec_file
    rec_file = nil              -- 先摘掉句柄，回调侧不再写
    if f then pcall(f.close, f) end
    stop_rec_timer()

    local msg
    if rec_saved > 0 then
        local kb = math.floor((io.fileSize(video_path) or 0) / 1024)
        msg = "已保存 " .. video_path .. " | " .. rec_saved .. " 帧 | " .. kb .. "KB"
        if rec_full then msg = msg .. " | 达到大小上限" end
    else
        msg = "录像失败：未收到图像帧，请确认摄像头已连接"
    end
    update_status(msg)
    busy = false
end

-- 切换画面适配方式
local function do_fit()
    local idx = 1
    for i, m in ipairs(FIT_ORDER) do
        if m == fit_mode then idx = i end
    end
    fit_mode = FIT_ORDER[(idx % #FIT_ORDER) + 1]
    if cam_widget and not cam_widget:is_destroyed() then
        pcall(cam_widget.set_fit, cam_widget, fit_mode)
    end
    update_status("适配方式 " .. (FIT_TITLE[fit_mode] or fit_mode))
end

-- 切换录像时长档
local function do_duration()
    local idx = 1
    for i, v in ipairs(REC_ORDER) do
        if v == rec_ms then idx = i end
    end
    rec_ms = REC_ORDER[(idx % #REC_ORDER) + 1]
    update_status("录像时长 " .. math.floor(rec_ms / 1000) .. " 秒")
end

-- ==================== 人脸识别 ====================

-- 错误码转中文说明，对不上就退回「错误码 N」
-- exfacecam.send_cmd 超时返回的第二值是字符串 "timeout" 而不是 MR_* 数字，
-- register/verify 会把它原样当错误码抛回来，这里要单列一条
local function face_err_text(code)
    if type(code) == "number" then
        return FACE_ERR_TEXT[code] or ("错误码 " .. tostring(code))
    end
    if code == "timeout" then return "模组无应答（超时）" end
    return "错误 " .. tostring(code)
end

--[[
人脸模组状态回调，跑在串口收包上下文里（见文件头「人脸识别边界」第 3 条）：
只做限流 + 发消息，不碰控件。包围盒与角度参数本页不消费。
@param state 见 FACE_STATE_TEXT]]
local function on_face_state(state, left, top, right, bottom, yaw, pitch, roll)
    local now = mcu.ticks() or 0
    if now - face_last_state < FACE_STATE_MIN_GAP then return end
    face_last_state = now
    sys.publish("FACE_STATE_TEXT", FACE_STATE_TEXT[state] or ("人脸状态 " .. tostring(state)))
end

-- 界面侧收人脸引导文案。回调只在录入/验证期间来，跟着 face_busy 走，不看页签：
-- 用户中途切到 UVC 页签也要能看到引导
local function on_face_state_text(text)
    if not window_open or not face_busy then return end
    update_status(text)
end

--[[
开人脸模组串口。只开 UART，不传 id = camera.USB：
画面通路由 excamera 独占，再让 exfacecam 走 camera.init 会抢走 USB 摄像头数据流。
@param tip 打不开时的提示语
@return boolean
]]
local function face_open(tip)
    if face_on then return true end
    if not exfacecam or not face_cfg or not face_cfg.uart_id then
        update_status(tip)
        return false
    end
    local ok, res = pcall(exfacecam.open, {
        face_uart = face_cfg.uart_id,
        face_rst = face_cfg.rst_pin,
    })
    if not ok or not res then
        log.warn("uvc_preview_win", "exfacecam.open 失败", res)
        update_status(tip)
        return false
    end
    face_on = true
    return true
end

-- 关人脸模组串口（相机不在它手上：没传 id 就没做过 camera.init）
local function face_close()
    if not face_on then return end
    face_on = false
    if exfacecam then pcall(exfacecam.close) end
end

--[[
模组就绪自检：问一次固件版本当作真实往返。

两个理由，缺一不可：
1. exfacecam.open 的探测有空子 —— 第一条 GETSTATUS 收不到回包时，它会转去等
   NID_READY，等到就直接返回 true，**不再复探**。模组掉电重启时刚好落进这个窗口：
   open 说成功，紧接着的录入却失败。
2. AirCAMERA_1034 是 USB 供电（参考工程 face_preview「停止预览」一节：断电会杀掉
   UART2 人脸识别），excamera.close 动过 USB 通路之后模组需要时间重新就绪。
   参考工程 face_manager 在 register 前连做几条查询并重试，理由写的是「模组刚复位时
   可能未就绪」。

所以这里做成「问到版本号才算就绪」，问不到就重试，把重启窗口吃掉。
@return boolean
]]
local function face_ready()
    for i = 1, 5 do
        local ok, res, ver = pcall(exfacecam.get_version)
        if ok and res then
            log.info("uvc_preview_win", "人脸模组就绪", tostring(ver))
            return true
        end
        log.warn("uvc_preview_win", "人脸模组未就绪 第 " .. i .. " 次", tostring(res))
        sys.wait(1000)
    end
    return false
end

--[[
断电重枚举摄像头，再按复位后的模组重开人脸串口。

理由见文件头「人脸识别边界」第 1 条：模组出完 MJPEG 停流后停在出图模式，录入指令
不回包；断电重新枚举才回到人脸采集模式。断电连人脸模组一起杀掉（同一根供电脚），
所以重枚举后必须重开串口 —— 旧回包表 / 接收回调随模组作废，留着会把上一轮残留字节
喂给新回包。供电脚不可控时只重开串口，并在日志里点明跳过了这一步。
@param tip 重开失败时的提示语
]]
local function face_reenumerate(tip)
    if face_pwr then
        log.info("uvc_preview_win", "断电重枚举摄像头", "GPIO" .. tostring(face_pwr))
        pcall(gpio.setup, face_pwr, 0)
        pcall(gpio.set, face_pwr, 0)
        sys.wait(400)               -- 断电保持
        pcall(gpio.setup, face_pwr, 1, gpio.PULLUP)
        pcall(gpio.set, face_pwr, 1)
        sys.wait(500)               -- 上电后等模组重新枚举
    else
        log.warn("uvc_preview_win", "本板未配摄像头供电脚，跳过断电重枚举，录入可能失败")
    end
    face_close()
    face_open(tip)
end

--[[人脸动作收尾：复位忙标志 + 重开数据流，最后落状态行。
重开失败只在提示尾部带一句，不覆盖动作结果。
@param msg 动作结果提示
注意：必须定义在 face_begin 之前 —— face_begin 的失败分支要调它，
Lua 里后定义的 local 在前面的闭包里是捕获不到的（取到的是全局 nil）。]]
local function face_end(msg)
    face_busy = false
    if not quit_requested then
        local ok, err = open_stream()
        if not ok then
            log.warn("uvc_preview_win", "人脸动作后重开数据流失败", err)
            update_status(tostring(msg) .. " | 画面恢复失败")
            return
        end
    end
    update_status(tostring(msg))
end

--[[
人脸动作前置：忙检查 + 开串口 + 停推流 + 确认模组就绪。

录入 / 验证要动模组的采集传感器，先断电重枚举（cycle 传 true）；取版本 / 清空是纯
串口指令，走轻路径，不折腾摄像头。轻路径先开串口再停流，「模组压根没接上」与
「停流把模组弄掉了」各给一条提示；重枚举路径反正要重开串口，不必先开这一次。

录入/验证会占满 CPU，与 MJPEG 收流叠加时识别超时，所以动作前停流（见文件头
「人脸识别边界」第 4 条），airui.camera 停流后继续显示最后一帧，不黑屏。
失败时自己给提示并复位 face_busy；成功返回 true，由调用方跑动作再调 face_end 收尾。
@param tip 动作中的提示语
@param cycle boolean true = 先断电重枚举摄像头
@return boolean
]]
local function face_begin(tip, cycle)
    if face_busy then return false end
    if not exfacecam then
        update_status("本固件不含 exfacecam 库，人脸识别不可用")
        return false
    end
    face_busy = true
    update_status(tip)
    if not cycle and not face_open(tip) then
        face_busy = false
        return false
    end
    close_stream()
    stop_widget()
    if cycle then
        face_reenumerate(tip)
        if not face_on then
            face_busy = false
            return false
        end
    end
    if not face_ready() then
        face_end("人脸模组未就绪，请重试")
        return false
    end
    return true
end

-- 录入一张人脸：用户名按录入次数递增，现场连录多人时名字不重复
local function do_face_register()
    if not face_begin("录入中，请正对摄像头...", true) then return end
    face_seq = face_seq + 1
    local name = "user" .. tostring(face_seq)
    local ok, res, extra = pcall(exfacecam.register, {
        name = name,
        -- admin 不传即普通用户：库里写的是 opt.admin and 1 or 0 的真假判断，
        -- 传 0 在 Lua 里为真，反倒会被当成管理员
        timeout = (face_cfg and face_cfg.register_timeout) or 15,
        on_state = on_face_state,
    })
    local msg
    if not ok then
        msg = "录入异常：" .. tostring(res)
    elseif res then
        msg = "录入成功 用户ID " .. tostring(extra or "?") .. " " .. name
    else
        msg = "录入失败：" .. face_err_text(extra)
    end
    -- 原始返回值落日志：界面文案做了翻译，现场排障要按原始码比对 exfacecam.MR_*
    log.warn("uvc_preview_win", "人脸录入 返回", tostring(ok), tostring(res), tostring(extra))
    face_end(msg)
end

-- 验证一张人脸：通过则报出命中的用户
local function do_face_verify()
    if not face_begin("验证中，请正对摄像头...", true) then return end
    local ok, res, extra = pcall(exfacecam.verify, {
        timeout = (face_cfg and face_cfg.verify_timeout) or 15,
        on_state = on_face_state,
    })
    local msg
    if not ok then
        msg = "验证异常：" .. tostring(res)
    elseif res then
        local info = type(extra) == "table" and extra or {}
        local who = tostring(info.name or "")
        if who ~= "" then who = " " .. who end
        msg = "验证通过 用户ID " .. tostring(info.user_id or "?") .. who
    else
        msg = "验证失败：" .. face_err_text(extra)
    end
    log.warn("uvc_preview_win", "人脸验证 返回", tostring(ok), tostring(res), tostring(extra))
    face_end(msg)
end

-- 删除全部已注册用户：先数一遍现有用户，删完把个数一起报出来
local function do_face_clear()
    if not face_begin("删除全部用户中...") then return end
    local okl, resl, cnt = pcall(exfacecam.list)
    local before = (okl and resl and type(cnt) == "number") and cnt or nil
    local ok, res = pcall(exfacecam.clear)
    local msg
    if ok and res then
        msg = "已删除全部用户"
        if before then msg = msg .. "（原有 " .. tostring(before) .. " 个）" end
    else
        msg = "删除失败"
    end
    face_end(msg)
end

-- 读模组固件版本：串口通没通，这一条最直观
local function do_face_version()
    if not face_begin("读取模组版本中...") then return end
    local ok, res, ver = pcall(exfacecam.get_version)
    local msg
    if ok and res then
        msg = "模组版本 " .. tostring(ver or "?")
    else
        msg = "版本读取失败"
    end
    face_end(msg)
end

-- 拆掉一组界面控件（控件销毁必须晚于停流，见 close_stream 的说明）
local function dispose_ui(it)
    if it.widget and not it.widget:is_destroyed() then
        pcall(it.widget.destroy, it.widget)
    end
    if it.container and not it.container:is_destroyed() then
        pcall(it.container.destroy, it.container)
    end
end

-- 断开界面控件引用（控件本体随 container 一起销毁，这里只清句柄）
local function drop_ui_refs()
    cam_widget = nil
    widget_registered = false
    main_container = nil
    preview_area = nil
    status_label = nil
    window_id = nil
    tab_uvc_row, tab_face_row = nil, nil
    uvc_bar, face_bar = nil, nil
end

-- 销毁本页界面
local function destroy_ui()
    dispose_ui({ widget = cam_widget, container = main_container })
    drop_ui_refs()
end

-- 进新页前收走上代界面：正在停流时组件不能销毁，先挂到 stale_ui 等数据流停掉
local function stash_ui()
    local it = { widget = cam_widget, container = main_container }
    drop_ui_refs()
    if not it.widget and not it.container then return end
    if not closing then
        dispose_ui(it)
        return
    end
    stale_ui = stale_ui or {}
    table.insert(stale_ui, it)
end

-- 数据流已停，销毁攒下的上代界面
local function flush_stale_ui()
    if not stale_ui then return end
    for _, it in ipairs(stale_ui) do
        dispose_ui(it)
    end
    stale_ui = nil
end

-- 退出页面：释放数据流与供电（必须在协程里，close 含 sys.wait）
local function do_teardown(gen)
    stop_rec_timer()
    snap_pending = false
    rec_full = true
    local f = rec_file
    rec_file = nil
    if f then pcall(f.close, f) end
    face_close()
    close_stream()
    stop_widget()
    flush_stale_ui()
    if periph_id then
        sys.publish("OTHER_FUNC_SET", periph_id, false)
    end
    -- 只有界面代数没变（期间没有重新进本页）才动控件，避免误删新页面的界面
    if gen == ui_gen then destroy_ui() end
end

-- 请求收尾：go_idle 为真时，收尾跑完后再回桌面（回桌面的动作在 cmd_loop 的 quit 分支）
local function request_quit(go_idle)
    if quit_requested then return end
    quit_requested = true
    if go_idle then quit_to_idle = true end
    sys.publish("UVC_CMD", "quit", ui_gen)
end

-- ==================== 命令协程 ====================

local function cmd_loop()
    cmd_running = true
    while cmd_running do
        -- 带超时等待：页面销毁后最多 1 秒内自行退出，避免残留协程被下次进页唤醒
        local _, cmd, arg = sys.waitUntil("UVC_CMD", 1000)
        if cmd_running and cmd then
            if cmd == "start" then
                wait_closing()          -- 上一轮停流收尾完，才动它的界面与数据流
                if stream_open then     -- 上代收尾没跑到（quit 期间已重新进页），这里补关
                    close_stream()
                end
                flush_stale_ui()
                local ok, err = open_stream()
                if not ok then update_status(tostring(err)) end
            elseif cmd == "connected" then
                on_connected(arg)
            elseif cmd == "photo" then
                do_photo()
            elseif cmd == "record" then
                do_record()
            elseif cmd == "fit" then
                do_fit()
            elseif cmd == "duration" then
                do_duration()
            elseif cmd == "face_register" then
                do_face_register()
            elseif cmd == "face_verify" then
                do_face_verify()
            elseif cmd == "face_clear" then
                do_face_clear()
            elseif cmd == "face_version" then
                do_face_version()
            elseif cmd == "quit" then
                -- 期间若已重新进本页，界面代数变了，这条 quit 属于上一代，只补关它的数据流
                if arg ~= ui_gen then
                    if stream_open then close_stream() end
                else
                    do_teardown(arg)
                    window_open = false
                    cmd_running = false
                    -- 收尾跑完（流已停、组件已销毁、供电已断）才回桌面：
                    -- 桌面 MP4 播放器在获得焦点时立刻起播，早于收尾会和相机抢内存
                    if quit_to_idle then
                        quit_to_idle = false
                        pcall(exwin.return_idle)
                    end
                end
            end
        end
    end
    cmd_started = false
end

-- ==================== 界面 ====================

--[[
页签切换：纯显隐，控件不重建 —— 建/销控件只能在界面线程（见 create_widget），
页签点击回调本身就跑在界面线程，显隐即可。
@param which TAB_UVC / TAB_FACE
]]
local function switch_tab(which)
    if face_tab == which then return end
    face_tab = which
    if tab_uvc_row and not tab_uvc_row:is_destroyed() then
        tab_uvc_row:set_hidden(which ~= TAB_UVC)
    end
    if tab_face_row and not tab_face_row:is_destroyed() then
        tab_face_row:set_hidden(which ~= TAB_FACE)
    end
    if uvc_bar and not uvc_bar:is_destroyed() then
        uvc_bar:set_hidden(which ~= TAB_UVC)
    end
    if face_bar and not face_bar:is_destroyed() then
        face_bar:set_hidden(which ~= TAB_FACE)
    end
    if which == TAB_FACE then
        update_status("人脸识别：录入 / 验证 / 删除全部 / 版本")
    else
        update_status("预览中 " .. SENSOR_W .. "x" .. SENSOR_H)
    end
end

--[[
页签行：两套胶囊各摆一份，用容器 set_hidden 切换高亮。
theme.pills 的选中态是建的时候定死的，没有改色接口，只能整行换。
@param w, y, h 行几何
@param gap 胶囊间距
]]
local function build_tabs(w, y, h, gap)
    local items = {
        { text = "UVC 测试", on_click = function() switch_tab(TAB_UVC) end },
        { text = "人脸识别", on_click = function() switch_tab(TAB_FACE) end },
    }
    tab_uvc_row = theme.box(main_container, {
        x = pad, y = y, w = w, h = h, color = theme.C.black, opa = 0,
    })
    theme.pills(tab_uvc_row, { x = 0, y = 0, w = w, h = h, gap = gap, active = 1, items = items })
    tab_face_row = theme.box(main_container, {
        x = pad, y = y, w = w, h = h, color = theme.C.black, opa = 0,
    })
    theme.pills(tab_face_row, { x = 0, y = 0, w = w, h = h, gap = gap, active = 2, items = items })
    tab_uvc_row:set_hidden(face_tab ~= TAB_UVC)
    tab_face_row:set_hidden(face_tab ~= TAB_FACE)
end

--[[
底部控制栏：UVC 与人脸各摆一份，同一位置靠 set_hidden 切换（与页签行同一套做法）。
两栏都是 5 个等宽按钮，480 宽下每个约 82，按钮文案压到两字。
不带 face 子表的机型只建 UVC 栏，人脸栏不占控件。
@param w, y, h 栏几何
@param gap 按钮间距
@param has_face 是否建人脸栏
]]
local function build_ctrl_bars(w, y, h, gap, has_face)
    local n = 5
    local bw = math.floor((w - (n - 1) * gap) / n)

    uvc_bar = theme.box(main_container, {
        x = pad, y = y, w = w, h = h, color = theme.C.black, opa = 0,
    })
    theme.button(uvc_bar, {
        x = 0, y = 0, w = bw, h = h,
        text = "拍照", on_click = function() sys.publish("UVC_CMD", "photo") end,
    })
    theme.button(uvc_bar, {
        x = bw + gap, y = 0, w = bw, h = h,
        text = "录像", on_click = function() sys.publish("UVC_CMD", "record") end,
    })
    theme.ghost_button(uvc_bar, {
        x = 2 * (bw + gap), y = 0, w = bw, h = h,
        text = "时长", on_click = function() sys.publish("UVC_CMD", "duration") end,
    })
    theme.ghost_button(uvc_bar, {
        x = 3 * (bw + gap), y = 0, w = bw, h = h,
        text = "适配", on_click = function() sys.publish("UVC_CMD", "fit") end,
    })
    theme.ghost_button(uvc_bar, {
        x = 4 * (bw + gap), y = 0, w = bw, h = h,
        text = "退出", bg = theme.C.rose, bg_opa = theme.OPA.fill,
        border = theme.C.rose, fg = theme.C.rose_light,
        on_click = function() request_quit(true) end,
    })

    if has_face then
        face_bar = theme.box(main_container, {
            x = pad, y = y, w = w, h = h, color = theme.C.black, opa = 0,
        })
        theme.button(face_bar, {
            x = 0, y = 0, w = bw, h = h,
            text = "录入", on_click = function() sys.publish("UVC_CMD", "face_register") end,
        })
        theme.button(face_bar, {
            x = bw + gap, y = 0, w = bw, h = h,
            text = "验证", on_click = function() sys.publish("UVC_CMD", "face_verify") end,
        })
        theme.ghost_button(face_bar, {
            x = 2 * (bw + gap), y = 0, w = bw, h = h,
            text = "清空", on_click = function() sys.publish("UVC_CMD", "face_clear") end,
        })
        theme.ghost_button(face_bar, {
            x = 3 * (bw + gap), y = 0, w = bw, h = h,
            text = "版本", on_click = function() sys.publish("UVC_CMD", "face_version") end,
        })
        theme.ghost_button(face_bar, {
            x = 4 * (bw + gap), y = 0, w = bw, h = h,
            text = "退出", bg = theme.C.rose, bg_opa = theme.OPA.fill,
            border = theme.C.rose, fg = theme.C.rose_light,
            on_click = function() request_quit(true) end,
        })
    end

    uvc_bar:set_hidden(face_tab ~= TAB_UVC)
    if face_bar then face_bar:set_hidden(face_tab ~= TAB_FACE) end
end

local function build_ui()
    update_screen_size()
    main_container = theme.page_bg(airui.screen, sw, sh)

    local card_w = sw - 2 * pad
    -- 有 face 子表就多一个页签，标题跟着改（见文件头【人脸识别】）
    -- 分隔符用 ASCII 的 "|"：内置字库不含 "·"(U+00B7)，见 ui_theme「字体能力约束」
    local has_face = (face_cfg ~= nil)
    local _, th = theme.header(main_container, {
        x = pad, y = pad, w = card_w,
        title = has_face and "人脸识别摄像头" or "UVC 摄像头",
        sub = has_face and "预览 / 拍照 / 录像 | 人脸录入 / 验证" or "预览 / 拍照 / 录像",
        on_back = function() exwin.close(window_id) end,
    })

    local y = pad + th + pad
    local gap = theme.dp(10)
    local ctrl_h = theme.dp(50)
    local status_h = theme.fs("caption") + theme.dp(10)

    -- 页签行：预览区之上，只有配了 face 子表才出
    local tab_h = 0
    if has_face then
        tab_h = theme.dp(36)
        build_tabs(card_w, y, tab_h, gap)
        y = y + tab_h + gap
    end

    -- 底部：状态行 + 控制栏，剩余高度全给预览区
    local bottom_h = status_h + gap + ctrl_h
    local preview_h = sh - y - pad - bottom_h
    if preview_h < theme.dp(80) then preview_h = theme.dp(80) end

    -- 预览区：纯黑底 + 描边，airui.camera 覆盖在上面出画面
    theme.box(main_container, {
        x = pad, y = y, w = card_w, h = preview_h,
        color = theme.C.black, opa = 255,
        radius = theme.R.lg, border = theme.C.stroke, border_w = 1,
    })
    preview_area = { x = pad, y = y, w = card_w, h = preview_h }
    -- 组件必须在建界面时就建好并挂上解码通道，早于 excamera.open 开流（见 create_widget）
    if create_widget() then
        start_widget()
    end

    local sy = y + preview_h + gap
    status_w = card_w
    status_label = theme.label(main_container, {
        x = pad, y = sy, w = card_w, h = status_h,
        text = "准备中...", px_size = theme.fs("caption"),
        color = theme.C.t2, align = airui.TEXT_ALIGN_LEFT,
    })

    local cy = sy + status_h + gap
    build_ctrl_bars(card_w, cy, ctrl_h, gap, has_face)
end

-- ==================== 窗口生命周期 ====================

local function on_create()
    ui_gen = ui_gen + 1
    window_open = true
    quit_requested = false
    quit_to_idle = false
    busy = false
    snap_pending = false
    rec_file = nil
    face_busy = false
    face_tab = TAB_UVC
    face_last_state = 0

    -- 上一轮界面若还挂着（停流期间来不及销毁），先收走，销毁动作延后到数据流停掉
    stash_ui()

    local entry = find_uvc()
    -- 条目带 face 子表才有人脸页签（见文件头【人脸识别】）；串口按需开，见 face_open
    local face = entry and entry.face
    face_cfg = (type(face) == "table") and face or nil
    -- 供电脚取条目的 en_pin。GPIO12 在多数机型是 VBUS 与 5V_EN 共轨，未声明
    -- pin12_free 就不碰（同 periph_uvc 的 check_en_pin），此时跳过断电重枚举
    face_pwr = nil
    if entry and entry.en_pin and not (entry.en_pin == 12 and not entry.pin12_free) then
        face_pwr = entry.en_pin
    end
    if entry then
        if not periph_id then periph_id = entry.id end
        if entry.max_pixels and entry.max_pixels > 0 then
            MAX_PIXELS = entry.max_pixels
        end
        -- 条目里的 w/h 是首选分辨率，超过内存预算时按预算收口
        PREF_W, PREF_H = entry.w, entry.h
        if PREF_W and PREF_H and (PREF_W * PREF_H) <= MAX_PIXELS then
            SENSOR_W, SENSOR_H = PREF_W, PREF_H
        else
            PREF_W, PREF_H = nil, nil
        end
    end
    save_base = save_dir()
    file_seq = 0
    photo_path = save_base .. "uvc_photo.jpg"
    video_path = save_base .. "uvc_video.mjpg"
    -- /ram 是内存，上限压到 4MB；SD 卡放宽到 24MB（见文件头第 2、4 条）
    rec_max_bytes = (save_base:sub(1, 5) == "/ram/") and (4 * 1024 * 1024) or (24 * 1024 * 1024)

    sys.subscribe("FACE_STATE_TEXT", on_face_state_text)
    build_ui()
    -- 协程只启动一次：重复进页再起一个会把 UVC_CMD 广播给两个协程，动作被执行两遍
    if not cmd_started then
        cmd_started = true
        sys.taskInit(cmd_loop)
    else
        cmd_running = true
    end

    -- 先给摄像头供电，再开数据流；供电与数据流解耦在 periph_uvc
    if periph_id then
        sys.publish("OTHER_FUNC_SET", periph_id, true)
    end
    sys.publish("UVC_CMD", "start")
    update_status("等待摄像头连接...")
end

local function on_destroy()
    -- excamera.close 含 sys.wait，不能在销毁回调里直接调，交回命令协程收尾；
    -- 根控件先隐藏，画面立刻撤掉，控件销毁留在停流之后（顺序见 close_stream）
    stop_rec_timer()
    sys.unsubscribe("FACE_STATE_TEXT", on_face_state_text)
    if main_container and not main_container:is_destroyed() then
        pcall(main_container.set_hidden, main_container, true)
    end
    request_quit(false)
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler(id)
    if id then periph_id = id end
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_UVC_PREVIEW_WIN", open_handler)
