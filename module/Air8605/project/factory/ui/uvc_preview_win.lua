--[[
@module  uvc_preview_win
@summary 摄像头测试页（UVC 预览 / 拍照 / 录像 + 人脸识别录入 / 验证 / 删除全部，TabOS 深色玻璃态）
@version 1.8
@date    2026.11.05
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

导航：标题栏「返回」回到功能测试页，这是页面唯一的出口。返回触发 on_destroy →
request_quit，收尾交回命令协程执行。

【人脸识别】摄像头是 AirCAMERA_1034 人脸识别模组时，同一颗模组出两条通路：
USB 走 UVC 出 MJPEG 画面（上面那套 excamera 独占），UART 走协议做人脸。
config.peripherals 的 uvc 条目带 face 子表即在页面多出「人脸识别」页签，
不带的型号页面与原来完全一致，只有「UVC 测试」。见下方「人脸识别边界」。

分辨率与内存（取档做法参考 module/Air8601/project/DEPOSIT_CABINET 的 face_preview）：
1. 开流分辨率取「能盖住预览组件的最小 MJPEG 档」（见 pick_uvc_mode）。预览组件只有
   几百像素，开 1280×720 纯属浪费：相机侧要吃约 4.25×w×h 字节（双帧缓冲 w×h +
   解码输入 w×h/4 + 解码输出 w×h×2），还要每帧把整幅源帧软件缩放到预览区。
   首选 config.peripherals 条目里的 w / h，其次取能盖住预览组件、像素数不超过
   MAX_PIXELS 的最小档。申请档位与实际支持档位不一致时按实际档位重开一次数据流，
   保证 excamera 的双帧缓冲与固件解码缓冲都按真实尺寸分配。
2. airui.camera 的两块显示缓冲按预览区大小分配（视口 w×h×2 字节 × 2 块，与 fit 无关），
   预览区因此按剩余内存收口（见 preview_size），与源分辨率同比、居中于黑底框内。
   这两块走 luat_heap_malloc，恒定落在 sys/SRAM 池，把 psram 一起算进来会高估，
   故预算只认 rtos.meminfo("sys")，余量紧张时再用 zbuff.HEAP_SRAM 真分两块探一次
   （见 probe_fb_ok；余量宽裕就跳过，那两次大 zbuff 各触发一次强制 GC）。
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
7. 离开页面一律发 UVC_CMD("quit") 进命令协程收尾，不在点击 / 销毁回调里同步收：
   excamera.close 含 sys.wait，且桌面 MP4 播放器获得焦点即起播，早于收尾会和
   未关的相机抢内存。收尾命令带界面代数，上一代的 quit 不拆新页面，只补关它的数据流。
8. 起流到出画面要好几秒，大头在固件 USB/UVC 收流侧（C 源码不在本仓库）：实测
   「推流已启动 → _camera_decode_jpg_prepare」空 6.8 秒，且 1280×720 与 640×360
   一样慢，与数据量无关。Lua 侧只把「点击 → 推流已启动」压到最短，并打三条耗时
   （开流就绪 / USB 连接 / 首个原始帧）加一条 5 秒汇总，把延迟切成「USB 枚举」
   与「收流 → 首帧」两段（见「起流耗时打点」）。首个原始帧迟迟不到是收流慢，
   原始帧早到而画面没出是解码侧慢。

人脸识别边界：
1. 供电共用：UVC_EN 一根脚同时供出图与人脸模组，断电两者一起掉。「连不上就断电
   重枚举」不能当常规手段（会把正在跑的人脸模组一起杀掉）。录入 / 验证前确实要让
   传感器从出图模式切回人脸采集模式 —— 停掉 MJPEG 推流后模组仍停在出图模式，此时发
   录入指令它不回包（现场日志 cmd timeout 0x1D），取版本这类纯协议指令却正常。
   但切换手段用 MID_RESET 软复位即可（见 face_reset_sensor，对齐 Air8601），不必断电：
   断电会连人脸模组一起杀掉、再走 USB 重枚举，窗口长且易落进「模组尚未就绪」空窗导致
   录入超时。只有软复位不被响应时才退回 GPIO 断电重枚举兜底（见 face_reenumerate）。
2. 人脸指令是串行的：exfacecam 内部是单例状态（回包表 / 状态回调共享），并发跑
   register 与 verify 会互相抢回包。本页所有人脸动作都进同一个命令协程，天然串行，
   另设 face_busy 挡掉重复点击。
3. 人脸状态回调在 UART 收包上下文里跑，只能发消息不能碰控件（参考工程实测在回调里
   做界面会叠加崩溃）。这里回调只做 500ms 限流 + sys.publish，界面更新交给订阅侧。
4. 录入 / 验证与预览并行（对齐 Air8601 face_preview v3.5）：由 face 子表的 mode 字段决定
   - serial      ：动作前 close_stream 停推流（画面冻结、显示最后一帧），动作后 open_stream 重开
   - auto（默认）：预览不停流，先把 UVC 降到 busy_fps(默认3) 让出 CPU，确认画面有新帧后直接
                   识别；并行识别失败 / 无新帧 / 流未开时，自动降级 serial 重试一次
   - concurrent  ：一律并行，失败不降级
   纯串口动作（清空 / 版本）不停流也不复位传感器，直接发指令。
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

-- 源分辨率初值：开流前按它申请帧缓冲，连上后由 pick_uvc_mode 校正为实际支持档。
-- 相机侧固定开销约 4.25×w×h 字节（双帧缓冲 w×h + 解码输入 w×h/4 + 解码输出 w×h×2），
-- 这一项直接决定还剩多少内存给 airui.camera 的显示缓冲，故初值取预览区够用的小档
local SENSOR_W, SENSOR_H = 640, 360

-- 预览旋转角度：传感器出横画幅，竖屏机型顺时针转 90° 得到竖画面
-- （参考 face_camera_test：airui.camera rotation=90 + camera.config CONF_PREVIEW_ROTATE）
local PREVIEW_ROTATION = 90

-- 源分辨率像素上限：像素数更大的 MJPEG 档位不取（1920×1080 时相机侧要吃掉 8.8MB）
local MAX_PIXELS = 1280 * 720

-- airui.camera 双显示缓冲预算上限（2 块 × 视口 w×h×2 字节）。
-- 只是上限：实际先按开流后剩余内存（动态预算）收，再由 probe_fb_ok 真分两块兜底，
-- 分不下会自动收口，不会崩。竖屏 cover 铺满时组件接近满框，需要更宽松的上限。
local PREVIEW_FB_BUDGET = 900 * 1024

-- 显示缓冲探针的收口次数与每次收口比例（见 probe_fb_ok）
local FB_PROBE_MAX = 3
local FB_SHRINK = 0.75

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
local widget_w, widget_h = 0, 0 -- 预览组件尺寸，取档时挑够盖住它的最小档
local fit_mode = "cover"
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
local face_mode = "auto"    -- 录入/验证与预览的并行模式：serial / auto / concurrent
local face_busy_fps = 3     -- 并行识别时的 UVC 帧率（降帧让出 CPU）
local face_live_timeout = 3000 -- 并行前等待画面新帧的超时(ms)，超时降级串行

-- 页签行与控制栏各摆两份，靠 set_hidden 切换（重建控件只能在界面线程，见 create_widget）
local tab_uvc_row = nil     -- 页签行（UVC 高亮）
local tab_face_row = nil    -- 页签行（人脸高亮）
local uvc_bar = nil         -- UVC 控制栏（拍照 / 录像 / 时长 / 适配）
local face_bar = nil        -- 人脸控制栏（录入 / 验证 / 清空 / 版本）

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

-- ==================== 起流耗时打点 ====================

-- tick 按 mcu.hz() 折算成毫秒：Air1603 约 20ms/tick，PC 模拟器 1ms/tick
local TICKS_PER_MS = 1
do
    local hz = mcu and mcu.hz and mcu.hz()
    if type(hz) == "number" and hz > 1 then TICKS_PER_MS = hz / 1000 end
end

local function now_ms()
    local t = mcu and mcu.ticks and mcu.ticks()
    if type(t) ~= "number" then return 0 end
    return math.floor(t / TICKS_PER_MS)
end

local t_enter   = 0    -- 进页面时刻
local t_frame1  = 0    -- 首个原始帧时刻，0 表示还没到
local frame_cnt = 0    -- 原始帧计数
local probe_timer = nil

-- 首帧后 5 秒打一条汇总：原始帧一直在流而画面没出，就卡在固件解码侧
local function log_stream_summary()
    probe_timer = nil
    local dt = -1
    if t_frame1 > 0 then dt = t_frame1 - t_enter end
    log.info("uvc_preview_win", "起流汇总", "进页面→首个原始帧", dt, "ms",
        "5秒内原始帧", frame_cnt, "帧")
end

-- ==================== UVC 档位自适应 ====================

--[[
枚举摄像头真正支持的 MJPEG 档位，选一档回来：
首选 config 指定的 w/h，其次取能盖住预览组件、像素数不超过 MAX_PIXELS 的最小档，
再退预算内最大档，都没有就取最小档。
拿到的 w/h 用来校正 excamera 的帧缓冲尺寸（它按 open 时的 w×h 建双缓冲）。]]
local function pick_uvc_mode(app_id)
    if not camera.get_usb_config then return nil end
    local res, format_num = camera.get_usb_config(app_id, camera.CONF_UVC_FORMAT)
    if not format_num or format_num <= 0 then
        log.warn("uvc_preview_win", "UVC 格式枚举失败", res, format_num)
        return nil
    end

    local exact, cover, best, smallest = nil, nil, nil, nil
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
                    if m.px <= MAX_PIXELS then
                        if not best or m.px > best.px then best = m end
                        if widget_w > 0 and w >= widget_w and h >= widget_h
                            and (not cover or m.px < cover.px) then
                            cover = m
                        end
                    end
                end
            end
        end
    end
    if exact then return exact end
    if cover then return cover end
    if best then return best end
    if smallest then
        log.warn("uvc_preview_win", "无预算内档位，改用最小档", smallest.w, smallest.h)
    end
    return smallest
end

--[[
单池剩余字节，取不到返回 nil。
airui.camera 的两块显示缓冲走 luat_heap_malloc，恒定落在 sys/SRAM 池，
psram 里的相机帧缓冲让不出来，两个池合起来算是高估（见文件头「分辨率与内存」第 2 条）。]]
local function pool_free(pool)
    local ok, t, u = pcall(rtos.meminfo, pool)
    if ok and type(t) == "number" and type(u) == "number" and t > u then
        return t - u
    end
    return nil
end

-- 相机侧开销：双帧缓冲 w×h + 解码输入 w×h/4 + 解码输出 w×h×2，合计约 4.25×w×h
local function sensor_cost()
    return math.floor(SENSOR_W * SENSOR_H * 4.25) + 16 * 1024
end

--[[
显示缓冲真分探针：按 w×h×2 真分两块再还回去。
内存反复占用释放后，即便余量够也可能没有连续块，估算值不可信；
zbuff.HEAP_SRAM 与 airui.camera 的 luat_heap_malloc 是同一池，探得下组件才建得出来。
老固件没有这个常量时退回估算。]]
local function probe_fb_ok(w, h)
    if not (zbuff and zbuff.HEAP_SRAM) then return true end
    local n = w * h * 2
    local a = zbuff.create(n, 0, zbuff.HEAP_SRAM)
    if not a then return false end
    local b = zbuff.create(n, 0, zbuff.HEAP_SRAM)
    if not b then
        a:free()
        return false
    end
    b:free()
    a:free()
    return true
end

-- 预览区尺寸，再按显示缓冲预算收口。
-- cover：组件按预览框比例铺满（宽度吃满），让组件内部 cover 裁掉细长画面的上下，
--        避免竖画面缩进偏方正的框时左右留大黑边；
-- 其它（contain/center/stretch）：组件仍与旋转后的源画面同比缩进框内。
local function preview_size(avail_w, avail_h)
    local w, h
    if fit_mode == "cover" then
        w, h = math.floor(avail_w), math.floor(avail_h)
    else
        local src_w = SENSOR_W > 0 and SENSOR_W or 16
        local src_h = SENSOR_H > 0 and SENSOR_H or 9
        -- 旋转 90/270 后画面宽高互换，按竖画幅做同比缩进
        if PREVIEW_ROTATION == 90 or PREVIEW_ROTATION == 270 then
            src_w, src_h = src_h, src_w
        end
        w, h = math.floor(avail_w), math.floor(avail_h)
        local scale = math.min(w / src_w, h / src_h)
        w, h = math.floor(src_w * scale), math.floor(src_h * scale)
    end
    -- 双显示缓冲 = 2 块 × w×h×2 字节。预算上限是 PREVIEW_FB_BUDGET，
    -- 这里测到的是开流前的剩余，还要先把相机侧那 4.25×w×h 扣掉，剩下的才是显示缓冲能用的
    local budget = PREVIEW_FB_BUDGET
    collectgarbage()
    local free = pool_free("sys")
    if free then
        local after = math.floor((free - sensor_cost()) * 0.6)
        if after < budget then budget = after end
        log.info("uvc_preview_win", "内存预算", "sys剩余", free,
            "相机侧", sensor_cost(), "显示缓冲", budget)
    end
    if budget < 64 * 1024 then budget = 64 * 1024 end
    local max_px = math.floor(budget / 4)
    if w * h > max_px then
        local k = math.sqrt(max_px / (w * h))
        w, h = math.floor(w * k), math.floor(h * k)
    end
    local min_w, min_h = theme.dp(80), theme.dp(60)
    if w < min_w then w = min_w end
    if h < min_h then h = min_h end
    -- 估算只是上限，真分得下才算数，分不下就继续收口。余量明显宽裕时跳过探针：
    -- 每次要真分两块大 zbuff，各触发一次强制 GC，白等上百毫秒
    if free and (free - sensor_cost()) >= budget * 4 then
        log.info("uvc_preview_win", "内存余量宽裕，跳过显示缓冲探针")
    else
        for _ = 1, FB_PROBE_MAX do
            if probe_fb_ok(w, h) then break end
            log.warn("uvc_preview_win", "显示缓冲分不下，收口", w, "x", h)
            w, h = math.floor(w * FB_SHRINK), math.floor(h * FB_SHRINK)
            if w < min_w or h < min_h then break end
        end
    end
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

    frame_cnt = frame_cnt + 1
    if t_frame1 == 0 then
        t_frame1 = now_ms()
        log.info("uvc_preview_win", "起流打点", "首个原始帧", t_frame1 - t_enter, "ms")
        probe_timer = sys.timerStart(log_stream_summary, 5000)
    end

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
    log.info("uvc_preview_win", "起流打点", "开流就绪", now_ms() - t_enter, "ms")
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
        fit = fit_mode, rotation = PREVIEW_ROTATION, auto_start = false,
    })
    -- 兼容旧组件：创建后再显式下一次旋转，并让相机解码侧按预览旋转
    if okw and wdg then
        if type(wdg.set_rotation) == "function" then
            pcall(wdg.set_rotation, wdg, PREVIEW_ROTATION)
        end
        if camera and camera.CONF_PREVIEW_ROTATE then
            local rot = (PREVIEW_ROTATION == 90 and camera.ROTATE_90)
                or (PREVIEW_ROTATION == 180 and camera.ROTATE_180)
                or (PREVIEW_ROTATION == 270 and camera.ROTATE_270)
                or camera.ROTATE_90
            pcall(camera.config, 0, camera.CONF_PREVIEW_ROTATE, rot)
        end
    end
    cam_widget = okw and wdg or nil
    widget_registered = false
    if not cam_widget then
        log.warn("uvc_preview_win", "airui.camera 创建失败")
        update_status("本固件不含 airui.camera 组件，无法显示画面")
        return false
    end
    log.info("uvc_preview_win", "预览组件", w, "x", h, "源", SENSOR_W, "x", SENSOR_H)
    widget_w, widget_h = w, h
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
    log.info("uvc_preview_win", "起流打点", "USB 连接", now_ms() - t_enter, "ms")
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

local face_reenumerate  -- 前向声明：face_reset_sensor 兜底要调它（定义在下方）

-- 关人脸模组串口（相机不在它手上：没传 id 就没做过 camera.init）
local function face_close()
    if not face_on then return end
    face_on = false
    if exfacecam then pcall(exfacecam.close) end
end

--[[
让模组传感器从 UVC 出图模式切回人脸采集模式。

这是录入超时的根因修复（对齐 Air8601 face_manager / ecface 的做法）：停掉 MJPEG 推流后
模组仍停在出图模式，此时直接发录入指令它不回包（cmd timeout 0x1D）。Air8601 的实测
结论是发 MID_RESET 软复位即可切回，**不必 GPIO 断电重枚举** —— 断电会连人脸模组一起
杀掉、再走 USB 重新枚举，窗口长且容易落进「模组还没就绪」的空窗，正是录入超时的来源。

软复位失败（个别模组不响应 MID_RESET）才退回 GPIO 断电重枚举兜底。
@return boolean true = 传感器已回到人脸采集模式
]]
local function face_reset_sensor()
    local ok, res = pcall(exfacecam.reset)
    if ok and res then
        sys.wait(500)   -- 等模组复位完成、传感器切回人脸模式（同 Air8601 reset_module）
        return true
    end
    log.warn("uvc_preview_win", "软复位模组失败，退回断电重枚举兜底", tostring(res))
    face_reenumerate()
    return face_on
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
断电重枚举摄像头，再按复位后的模组重开人脸串口（软复位失败时的兜底手段）。

正常路径不再走这里：见 face_reset_sensor，停流后发 MID_RESET 软复位就能让传感器回到
人脸采集模式，不必断电。只有个别模组不响应软复位时才兜底断电重枚举。断电会连人脸模组
一起杀掉（同一根供电脚），所以重枚举后必须重开串口 —— 旧回包表 / 接收回调随模组作废，
留着会把上一轮残留字节喂给新回包。供电脚不可控时只重开串口，并在日志里点明跳过了这一步。
@param tip 重开失败时的提示语
]]
face_reenumerate = function(tip)
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

--[[人脸动作收尾：复位忙标志 + 按需重开数据流，最后落状态行。
@param msg      动作结果提示
@param need_open boolean true=本次动作停过流（串行路径），收尾要 open_stream 重开画面；
                       false=纯串口动作或并行路径，画面本就没停，不重连
重开失败只在提示尾部带一句，不覆盖动作结果。
注意：必须定义在 face_begin 之前 —— face_begin 的失败分支要调它，
Lua 里后定义的 local 在前面的闭包里是捕获不到的（取到的是全局 nil）。]]
local function face_end(msg, need_open)
    face_busy = false
    if need_open and not quit_requested then
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
人脸动作前置（串行 / 轻路径共用）：忙检查 + 开串口；cycle 时再停推流 + 切传感器 + 确认就绪。

录入 / 验证走 cycle=true 的串行降级路径：停流后发 MID_RESET 软复位，让传感器从 UVC
出图模式切回人脸采集模式（见 face_reset_sensor）；取版本 / 清空是纯串口指令，cycle 传
false —— 不停流、不复位、不做就绪自检，直接发指令。

失败时自己给提示并复位 face_busy；成功返回 true，由调用方跑动作再调 face_end 收尾。
@param tip   动作中的提示语
@param cycle boolean true = 停流 + 软复位把传感器切回人脸模式（串行录入/验证）
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
    if not face_open(tip) then
        face_busy = false
        return false
    end
    if not cycle then
        return true   -- 纯串口动作：不停流不复位
    end
    close_stream()
    stop_widget()
    if not face_reset_sensor() then
        face_busy = false
        update_status("人脸模组切回采集模式失败，请重试")
        return false
    end
    if not face_ready() then
        face_end("人脸模组未就绪，请重试", true)
        return false
    end
    return true
end

-- ==================== 录入/验证与预览并行支持 ====================

-- 应用 UVC 帧率配置。固件未实现 CONF_UVC_FPS 时 camera.config 静默失败，无副作用
local function apply_uvc_fps(fps)
    if camera and camera.CONF_UVC_FPS then
        pcall(camera.config, 0, camera.CONF_UVC_FPS, fps)
    end
end

--[[
等待画面出现「进入本函数之后」的新帧：并行识别前确认预览真的活着，不拿旧帧/冻结画面硬跑。
@return boolean true = 超时内收到新帧
]]
local function wait_frame_alive()
    local before = frame_cnt
    local t = 0
    while t < face_live_timeout do
        if frame_cnt > before then return true end
        sys.wait(100)
        t = t + 100
    end
    return false
end

--[[
跑一次人脸动作（协程内），统一封装回包，供并行与串行路径复用。
@return ok(pcall) , success(业务) , extra(user_id|table|错误码) , name(仅录入)
]]
local function face_run_once(kind)
    if kind == "register" then
        face_seq = face_seq + 1
        local name = "user" .. tostring(face_seq)
        local ok, res, extra = pcall(exfacecam.register, {
            name = name,
            -- admin 不传即普通用户：库里写的是 opt.admin and 1 or 0 的真假判断，
            -- 传 0 在 Lua 里为真，反倒会被当成管理员
            timeout = (face_cfg and face_cfg.register_timeout) or 15,
            on_state = on_face_state,
        })
        return ok, ok and res or false, extra, name
    end
    local ok, res, extra = pcall(exfacecam.verify, {
        timeout = (face_cfg and face_cfg.verify_timeout) or 15,
        on_state = on_face_state,
    })
    return ok, ok and res or false, extra, nil
end

-- 把一次动作回包翻译成结果文案
local function face_result_text(kind, ok, success, extra, name)
    if not ok then
        return (kind == "register" and "录入异常：" or "验证异常：") .. tostring(extra)
    end
    if kind == "register" then
        if success then
            return "录入成功 用户ID " .. tostring(extra or "?") .. " " .. tostring(name)
        end
        return "录入失败：" .. face_err_text(extra)
    end
    if success then
        local info = type(extra) == "table" and extra or {}
        local who = tostring(info.name or "")
        if who ~= "" then who = " " .. who end
        return "验证通过 用户ID " .. tostring(info.user_id or "?") .. who
    end
    return "验证失败：" .. face_err_text(extra)
end

--[[
录入/验证统一入口：按 face_mode 决定并行或串行。
- serial     ：face_begin(cycle=true) 停流串行
- auto       ：预览不停流直接识别；并行失败（异常/业务失败/无新帧/流未开）降级串行重试一次
- concurrent ：只走并行，失败不降级
]]
local function do_face_capture(kind)
    if face_busy then return end
    local doing = (kind == "register") and "录入" or "验证"

    if face_mode == "serial" then
        if not face_begin(doing .. "中，请正对摄像头...", true) then return end
        local ok, success, extra, name = face_run_once(kind)
        log.warn("uvc_preview_win", "人脸" .. doing, "serial", tostring(ok), tostring(success), tostring(extra))
        face_end(face_result_text(kind, ok, success, extra, name), true)
        return
    end

    -- 并行：先开串口（不停流），再降帧 + 确认画面活着
    face_busy = true
    update_status(doing .. "中，请正对摄像头...")
    if not face_open(doing .. "中，请正对摄像头...") then
        face_busy = false
        return
    end

    local can_parallel = stream_open
    if can_parallel then
        apply_uvc_fps(face_busy_fps)
        can_parallel = wait_frame_alive()
    end

    if not can_parallel then
        if face_mode ~= "auto" then
            face_busy = false
            update_status(doing .. "失败：预览无画面")
            return
        end
        log.warn("uvc_preview_win", "并行" .. doing .. "前置不满足，降级串行")
        face_busy = false
        if not face_begin(doing .. "中，请正对摄像头...", true) then return end
        local ok, success, extra, name = face_run_once(kind)
        face_end(face_result_text(kind, ok, success, extra, name), true)
        return
    end

    log.info("uvc_preview_win", "并行" .. doing .. "，预览不停流 fps=" .. tostring(face_busy_fps))
    local ok, success, extra, name = face_run_once(kind)
    log.warn("uvc_preview_win", "人脸" .. doing, "parallel", tostring(ok), tostring(success), tostring(extra))

    if ok and success then
        apply_uvc_fps(15)
        face_end(face_result_text(kind, ok, success, extra, name), false)
        return
    end

    if face_mode ~= "auto" then
        apply_uvc_fps(15)
        face_end(face_result_text(kind, ok, success, extra, name), false)
        return
    end
    log.warn("uvc_preview_win", "并行" .. doing .. "失败，降级串行重试一次")
    face_busy = false
    if not face_begin("正在重新" .. doing .. "，请稍候...", true) then return end
    local ok2, success2, extra2, name2 = face_run_once(kind)
    face_end(face_result_text(kind, ok2, success2, extra2, name2), true)
end

-- 录入一张人脸：用户名按录入次数递增，现场连录多人时名字不重复
local function do_face_register()
    do_face_capture("register")
end

-- 验证一张人脸：通过则报出命中的用户
local function do_face_verify()
    do_face_capture("verify")
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
    face_end(msg, false)
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
    face_end(msg, false)
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

-- 请求收尾：收尾动作在 cmd_loop 的 quit 分支，跑完才算离开
local function request_quit()
    if quit_requested then return end
    quit_requested = true
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
右侧竖排控制栏：UVC 与人脸各摆一份，同一右栏位置靠 set_hidden 切换（与页签行同一套做法）。
两栏都是 4 个等高按钮纵向均分，按钮文案压到两字。
左栏预览一直延伸到底，右栏只占固定窄列，预览因此更高更贴合竖画幅。
不带 face 子表的机型只建 UVC 栏，人脸栏不占控件。
@param x, y, w, h 右栏整体几何
@param gap 按钮间距
@param has_face 是否建人脸栏
]]
local function build_ctrl_bars(x, y, w, h, gap, has_face)
    local n = 4
    local bh = math.floor((h - (n - 1) * gap) / n)

    uvc_bar = theme.box(main_container, {
        x = x, y = y, w = w, h = h, color = theme.C.black, opa = 0,
    })
    theme.button(uvc_bar, {
        x = 0, y = 0, w = w, h = bh,
        text = "拍照", on_click = function() sys.publish("UVC_CMD", "photo") end,
    })
    theme.button(uvc_bar, {
        x = 0, y = bh + gap, w = w, h = bh,
        text = "录像", on_click = function() sys.publish("UVC_CMD", "record") end,
    })
    theme.ghost_button(uvc_bar, {
        x = 0, y = 2 * (bh + gap), w = w, h = bh,
        text = "时长", on_click = function() sys.publish("UVC_CMD", "duration") end,
    })
    theme.ghost_button(uvc_bar, {
        x = 0, y = 3 * (bh + gap), w = w, h = bh,
        text = "适配", on_click = function() sys.publish("UVC_CMD", "fit") end,
    })

    if has_face then
        face_bar = theme.box(main_container, {
            x = x, y = y, w = w, h = h, color = theme.C.black, opa = 0,
        })
        theme.button(face_bar, {
            x = 0, y = 0, w = w, h = bh,
            text = "录入", on_click = function() sys.publish("UVC_CMD", "face_register") end,
        })
        theme.button(face_bar, {
            x = 0, y = bh + gap, w = w, h = bh,
            text = "验证", on_click = function() sys.publish("UVC_CMD", "face_verify") end,
        })
        theme.ghost_button(face_bar, {
            x = 0, y = 2 * (bh + gap), w = w, h = bh,
            text = "清空", on_click = function() sys.publish("UVC_CMD", "face_clear") end,
        })
        theme.ghost_button(face_bar, {
            x = 0, y = 3 * (bh + gap), w = w, h = bh,
            text = "版本", on_click = function() sys.publish("UVC_CMD", "face_version") end,
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
    local status_h = theme.fs("caption") + theme.dp(10)

    -- 页签行：预览区之上，只有配了 face 子表才出
    local tab_h = 0
    if has_face then
        tab_h = theme.dp(36)
        build_tabs(card_w, y, tab_h, gap)
        y = y + tab_h + gap
    end

    -- 右侧控制列固定窄宽（与原横排按钮等宽），左栏占其余宽度
    local col_w = theme.dp(100)
    local left_w = card_w - col_w - gap

    -- 底部只留一条状态行：左预览与右控制列都延伸到状态行上方
    local content_h = sh - y - pad - status_h - gap
    if content_h < theme.dp(120) then content_h = theme.dp(120) end

    local col_x = pad + left_w + gap

    -- 预览区：左栏满高，纯黑底 + 描边，airui.camera 覆盖在上面出画面
    theme.box(main_container, {
        x = pad, y = y, w = left_w, h = content_h,
        color = theme.C.black, opa = 255,
        radius = theme.R.lg, border = theme.C.stroke, border_w = 1,
    })
    preview_area = { x = pad, y = y, w = left_w, h = content_h }
    -- 组件必须在建界面时就建好并挂上解码通道，早于 excamera.open 开流（见 create_widget）
    if create_widget() then
        start_widget()
    end

    -- 右侧竖排控制列与左预览同高
    build_ctrl_bars(col_x, y, col_w, content_h, gap, has_face)

    -- 底部状态行横跨整宽
    local sy = y + content_h + gap
    status_w = card_w
    status_label = theme.label(main_container, {
        x = pad, y = sy, w = card_w, h = status_h,
        text = "准备中...", px_size = theme.fs("caption"),
        color = theme.C.t2, align = airui.TEXT_ALIGN_LEFT,
    })
end

-- ==================== 窗口生命周期 ====================

local function on_create()
    ui_gen = ui_gen + 1
    window_open = true
    quit_requested = false
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
    -- 并行模式参数（见文件头「人脸识别边界」第 4 条）；不配时默认 auto + 3fps
    if face_cfg then
        face_mode = (face_cfg.mode == "serial" or face_cfg.mode == "concurrent")
            and face_cfg.mode or "auto"
        if type(face_cfg.busy_fps) == "number" and face_cfg.busy_fps > 0 then
            face_busy_fps = math.floor(face_cfg.busy_fps)
        end
        if type(face_cfg.live_timeout) == "number" and face_cfg.live_timeout >= 500 then
            face_live_timeout = math.floor(face_cfg.live_timeout)
        end
    else
        face_mode = "auto"
    end
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
    -- 这里不再提前 pm.power(pm.USB, true)。
    -- 枚举依赖的是"上电沿"：示例能出画面是因为 VBUS 在 excamera.preview 内部
    -- usb.mode(0, usb.HOST) 之后才第一次打开，模组上电时主机侧已就绪。
    -- 提前供电会让模组在 USB 还是非 Host 状态时就完成上电，之后 excamera 里
    -- 再调一次 pm.power(pm.USB, true) 是幂等的（无新上电沿）=> 永不枚举
    -- （实测：两次进页面 190s+ 0 条 USB 事件，GPIO73 断电重上电也救不回）。
    -- 上电统一交给 excamera.preview 内的 usb.mode -> pm.power(pm.USB, true)。
    sys.publish("UVC_CMD", "start")
    update_status("等待摄像头连接...")
end

local function on_destroy()
    -- excamera.close 含 sys.wait，不能在销毁回调里直接调，交回命令协程收尾；
    -- 根控件先隐藏，画面立刻撤掉，控件销毁留在停流之后（顺序见 close_stream）
    stop_rec_timer()
    if probe_timer then
        sys.timerStop(probe_timer)
        probe_timer = nil
    end
    sys.unsubscribe("FACE_STATE_TEXT", on_face_state_text)
    if main_container and not main_container:is_destroyed() then
        pcall(main_container.set_hidden, main_container, true)
    end
    request_quit()
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler(id)
    if id then periph_id = id end
    -- 起流耗时从点击这一刻起算
    t_enter = now_ms()
    t_frame1, frame_cnt = 0, 0
    if probe_timer then
        sys.timerStop(probe_timer)
        probe_timer = nil
    end
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_UVC_PREVIEW_WIN", open_handler)
