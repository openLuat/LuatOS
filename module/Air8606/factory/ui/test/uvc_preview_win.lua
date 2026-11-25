--[[
@module  uvc_preview_win
@summary 摄像头测试页（UVC 预览 / 拍照 / 录像 + 人脸识别录入 / 验证 / 删除全部，TabOS 深色玻璃态）
@version 1.13
@date    2026.11.12
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

布局：标题栏通栏在顶，横竖屏两套。横屏（sw >= sh）走「左预览 + 右操作区」的左右结构：
左列预览画面区占满标题栏以下的高度，右列自上而下排页签 / 状态行 / 供电接线提示 /
控制按钮（4 个按钮排 2 列 2 行），控制按钮贴右列底部，余下留白均摊进上方各块的间隙。
竖屏走上下结构（页签 / 预览 / 状态行 / 底部控制栏一行 4 个）：宽度不够，硬拆左右两列
会把预览挤没。见 build_ui / build_side_ui。

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
   画面旋转在缩放前对帧生效，转 90/270 时帧的宽高互换，取档与预览区都按 UVC 页签的
   旋转后的宽高比来（见 disp_dims）。UVC 页签取 uvc 条目的 rotation、人脸页签取
   face.rotation，都只认顺时针 0/90/180/270（逆时针 90 度写 270）；切页签只改
   airui.camera 的 rotation、不重建组件（见 apply_rotation）。
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
2. 本固件只播 HZV 容器，录像文件仍是 .mjpg（MJPEG 帧序列，可用 ffplay -f mjpeg 或
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
   excamera.close 含 sys.wait，且桌面播放器获得焦点即起播，早于收尾会和
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
   但切换手段走 GPIO 断电重枚举（见 face_reenumerate）：断电上电让模组整体重启、USB 重新
   枚举，传感器回到人脸采集模式，同时新产生的 connected 事件能把显示组件补 start 回来。
   不用 MID_RESET 软复位：软复位不停 USB 电，就不会再有 connected 事件，串行动作做完预览
   会永久冻在最后一帧（见第 6 条）。
2. 人脸指令是串行的：exfacecam 内部是单例状态（回包表 / 状态回调共享），并发跑
   register 与 verify 会互相抢回包。本页所有人脸动作都进同一个命令协程，天然串行，
   另设 face_busy 挡掉重复点击。
3. 人脸状态回调在 UART 收包上下文里跑，只能发消息不能碰控件（参考工程实测在回调里
   做界面会叠加崩溃）。这里回调只做 500ms 限流 + sys.publish，界面更新交给订阅侧。
4. 录入 / 验证与预览并行（对齐 Air8601 face_preview v3.5）：由 face 子表的 mode 字段决定
   - serial      ：动作前 close_stream 停推流（画面冻结、显示最后一帧），动作后 open_stream 重开
   - auto（默认）：预览不停流，先把 UVC 降到 busy_fps(默认3) 让出 CPU，确认画面有新帧后直接
                   识别；并行识别失败 / 无新帧 / 流未开时，自动降级 serial 重试一次。
                   但模组已给出明确结论的失败（人脸不匹配 / 活体未通过 / 用户不存在 / 已满 /
                   已录入）不降级：重试还是同一个结果，只是白停一次流让画面冻十几秒
   - concurrent  ：一律并行，失败不降级
   纯串口动作（清空 / 版本）不停流也不复位传感器，直接发指令。
5. 录入 / 验证的结果除了落底部状态行，还弹一个结果窗（成功绿 / 失败红，大字标题 +
   说明），FACE_TIP_CLOSE_MS(3 秒) 后自动收起。弹窗控件在建界面时最后建好并常驻隐藏，
   结果只做 set_text / set_color / set_hidden —— 命令协程里不新建控件（理由同第 3 条）。
   遮罩带空点击回调，弹窗期间不会误触下面的拍照 / 录入按钮。
6. 停过流的路径（serial / 降级串行）收尾必须把画面开回来，而且要重新 start 组件：
   excamera.close 之后组件处于 stop 状态，而重开流不一定再产生 connected 事件（USB 一直
   处于 Host 时没有新的枚举动沿），只等 on_connected 里那次 start_widget，预览会永久冻在
   最后一帧 —— 失败后「预览卡住」就是这么来的。所以 open_stream 成功即 start_widget
   （幂等，stop 过的组件才会真的再 start）。同理，串行分支里任何一个失败 return 都必须
   走 face_end 把画面重开，不能直接 update_status 了事。
7. 底部状态行是页面上唯一的常驻提示：字号取 h3 档（比原来的 caption 大两档），按语义上色
   （成功绿 / 失败红 / 进行中与「未检测到人脸」琥珀 / 其余亮白）。AirUI 这一版没有字重
   接口、内置字库也只有一种字重，所以「加粗」用加大字号 + 颜色来替代。
8. 人脸状态回调的限流必须按毫秒算（tick_time.now）：原来拿 mcu.ticks() 跟 500ms 比，在
   20ms/tick 的 Air1603 上实际等于 10 秒才刷新一次状态行 —— 用户看到的就是「未检测到
   人脸」一直不变、像卡住。回调本身仍然只 sys.publish，不碰控件（见第 3 条）。
9. 状态不照抄现象，要翻译成动作（FACE_GUIDE）：模组回的状态码 / 错误码先落到「下一步
   该做什么」——识别过程中给当场能照做的动作（抬头、退后、摘口罩），动作失败给重试前
   该做的事（先录入再验证、清空人脸库、拉近距离重试）。只报「识别超时」而不说怎么做，
   用户只能反复点按钮；报错一律带一句可照做的提醒（见 guide_of）。
]]

local usb_mode = require "usb_mode"
if not usb_mode.should_start_uvc(_G.project_config) then return end

local theme = require "ui_theme"
local tick_time = require "tick_time"

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
-- 480×320 是 AirCAMERA_1034 实测最小可用档之一
local SENSOR_W, SENSOR_H = 480, 320

-- 源分辨率像素上限：像素数更大的 MJPEG 档位不取（1920×1080 时相机侧要吃掉 8.8MB）
local MAX_PIXELS = 1280 * 720

-- airui.camera 双显示缓冲预算上限（2 块 × 视口 w×h×2 字节）。
-- 1280×720 实测预览区 894×421 时单块 752KB 分配失败，故上限压到 512KB；
-- 实际预算还要按开流后的剩余内存再收一次（见 preview_size）
local PREVIEW_FB_BUDGET = 512 * 1024

-- 显示缓冲真分探针的收口次数与每次收口比例（见 probe_fb_ok）
local FB_PROBE_MAX = 4
local FB_SHRINK = 0.7

-- 停流前宽限：等一帧时间让在途帧回调跑完，避免读到 excamera.close 已释放的 zbuff
local CLOSE_GRACE = 300

-- config.peripherals 条目里的首选分辨率（不写则用上面的默认档）
local PREF_W, PREF_H = nil, nil

-- 画面旋转角，取 uvc 条目的 rotation：顺时针 0/90/180/270（airui.camera 只吃顺时针，
-- 逆时针 90 度写 270）。不写不转
-- cam_rotation 是 UVC 页签的值（取档与预览框按它算），face_rotation 是人脸页签的值
local cam_rotation = 0
local face_rotation = 0

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
    [12] = "活体检测未通过", [13] = "识别超时（未检测到人脸）", [14] = "授权校验失败",
}

--[[
状态码 / 错误码 → 「下一步该做什么」。

FACE_STATE_TEXT 与 FACE_ERR_TEXT 说的是「现在是什么情况」，这一张说的是「人该怎么做」：
界面不只要报状态，还要把状态翻译成动作，把话说到用户能照做的程度。
key = 数字时按 FACE_STATE_TEXT 的过程态取；key = "err" 时按 FACE_ERR_TEXT 的结论态取；
其余 key 取自建故障（reopen / serial）。
]]
local FACE_GUIDE = {
    -- 过程态：识别过程中模组 ~15fps 回的状态，文案要能立刻照做
    [0]  = "保持不动，等识别完成",
    [1]  = "请走到摄像头正前方，正脸对镜头",
    [2]  = "请把头放平，眼睛看镜头",
    [3]  = "请稍微抬头，眼睛看镜头",
    [4]  = "请把脸转回正前方",
    [5]  = "请把脸转回正前方",
    [6]  = "请退后半步，让整张脸进画面",
    [7]  = "请靠近一些，让脸落在画面中间",
    [8]  = "请把刘海、帽子挪开，露出眉毛",
    [9]  = "请摘下墨镜，露出眼睛",
    [10] = "请摘下口罩、围巾，露出整张脸",
    [11] = "请站正，头不要歪",
    -- 结论态：动作结束时的错误码，给的是重试前该做的事
    err = {
        [1]  = "。请退后一步重新正对摄像头再试",
        [2]  = "。动作已取消，需要就重新点一次",
        [4]  = "。请检查摄像头排线与供电后重进本页",
        [5]  = "。请重试一次；仍失败就重启设备",
        [6]  = "。请退出本页重进后再试",
        [7]  = "。请先退出其它页面释放内存再试",
        [8]  = "。请先录入人脸再做验证",
        [9]  = "。请先清空人脸库再录入",
        [10] = "。该人脸已录入过，直接验证即可",
        [12] = "。请摘掉照片、屏幕翻拍，用真脸正对镜头",
        [13] = "。请正对摄像头、光线充足、距离约 0.5~1.5 米后重试",
        [14] = "。请确认人脸模组型号配套，或联系技术支持",
        timeout = "。模组没应答，请检查串口接线与供电后重试",
    },
    -- 自建故障
    reopen = "。请检查摄像头与人脸模组的供电、排线后重试",
    serial = "。请检查接线与供电后重试",
    other  = "。请重试一次；仍失败就重启设备",
}

-- 人脸状态提示最小间隔(ms)：模组回得快，不压一压状态行会刷到看不清
local FACE_STATE_MIN_GAP = 500
local FACE_STATE_MIN_GAP_TICKS = tick_time.ms(FACE_STATE_MIN_GAP)

-- 录入 / 验证结果弹窗的自动关闭时长(ms)：成功 / 失败各弹一个窗，3 秒后自动收起
local FACE_TIP_CLOSE_MS = 3000

-- 运行期状态
local cam_widget = nil          -- airui.camera 控件
local widget_registered = false -- 是否已挂到解码通道
local widget_started = false    -- 组件是否已在收帧（stop 过就要重新 start，否则画面冻在最后一帧）
local widget_w, widget_h = 0, 0 -- 预览组件尺寸，取档时挑够盖住它的最小档
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
local face_kind = "verify"  -- 当前动作 kind（register / verify），决定结果弹窗用「录入」还是「验证」措辞

-- 结果弹窗运行期状态（控件在建界面时建好并常驻隐藏，结果只改文案与颜色）
local face_tip = nil        -- 遮罩 + 卡片根容器
local face_tip_card = nil   -- 卡片（按成功 / 失败换边框色）
local face_tip_title = nil  -- 大字标题（成功绿 / 失败红）
local face_tip_detail = nil -- 说明文案
local face_tip_text_w = 0   -- 文案可用宽度（fit_text 用）
local face_tip_timer = nil  -- 自动关闭定时器

-- 当前页签的画面旋转角
local function active_rotation()
    if face_tab == TAB_FACE then return face_rotation end
    return cam_rotation
end

--[[
下发电画面旋转角：预览组件不重建（停流重建会打断人脸录入，见文件头「已知边界」第 6 条），
只改 airui.camera 的 rotation，下一帧即生效。]]
local function apply_rotation()
    if not cam_widget or cam_widget:is_destroyed() then return end
    if type(cam_widget.set_rotation) ~= "function" then return end
    pcall(cam_widget.set_rotation, cam_widget, active_rotation())
end

-- 前向声明：弹窗实现在界面段，face_end / do_face_capture 先要能调到
local show_face_tip
local hide_face_tip

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

--[[状态行字号：h3 档（比原来的 caption 大两档），一屏内最显眼的那行提示就靠它。
AirUI 这一版没有字重（bold）接口，字库也只有 MiSans DemiBold 一种字重，
所以「加粗」用「加大字号 + 亮色 / 语义色」来替代。]]
local function status_px()
    return theme.fs("h3")
end

--[[刷新底部状态行（超出宽度自动截断，避免撑出滚动条）
@param text 文案
@param kind 语义色：nil=主文字色（亮白），"ok"=绿，"err"=红，"busy"=琥珀]]
local function update_status(text, kind)
    if not status_label or status_label:is_destroyed() then return end
    status_label:set_text(theme.fit_text(tostring(text or ""), status_w, status_px()))
    local color = theme.C.t1
    if kind == "ok" then
        color = theme.C.green
    elseif kind == "err" then
        color = theme.C.rose
    elseif kind == "busy" then
        color = theme.C.amber
    end
    pcall(status_label.set_color, status_label, color)
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

-- 推流基准帧率：cam_param 下发与人脸并行后的恢复帧率共用这一个数，别再各写各的
local UVC_FPS = 15

-- excamera.open 的 USB 摄像头配置表（只用于开推流，拍照/录像取推流帧落盘）
local function cam_param()
    return {
        id            = camera.USB,
        sensor_width  = SENSOR_W,
        sensor_height = SENSOR_H,
        usb_port      = 1,
        work_mode     = 2,
        fps           = UVC_FPS,
    }
end

-- 相机能力是否齐备
local function cam_ready()
    return excamera ~= nil and camera ~= nil and camera.USB ~= nil
end

-- ==================== 起流耗时打点 ====================

-- 打点记 tick，出日志才按 mcu.hz() 折算毫秒
local function elapsed_ms(t1, t0)
    return tick_time.to_ms(tick_time.elapsed(t1, t0))
end

local t_enter   = 0    -- 进页面时刻(tick)
local t_frame1  = 0    -- 首个原始帧时刻(tick)，0 表示还没到
local frame_cnt = 0    -- 原始帧计数
local probe_timer = nil

-- 首帧后 5 秒打一条汇总：原始帧一直在流而画面没出，就卡在固件解码侧
local function log_stream_summary()
    probe_timer = nil
    local dt = -1
    if t_frame1 > 0 then dt = elapsed_ms(t_frame1, t_enter) end
    log.info("uvc_preview_win", "起流汇总", "进页面→首个原始帧", dt, "ms",
        "5秒内原始帧", frame_cnt, "帧")
end

-- ==================== UVC 档位自适应 ====================

--[[
旋转在缩放前对帧生效（airui.camera 的 rotation），转 90/270 时帧的宽高互换。
取档与预览区都按 UVC 页签的旋转算（组件建于进页面那一刻，切页签只换旋转不换框），
否则视口和画面对不上（适应留黑边、铺满裁画面）。]]
local function disp_dims(w, h)
    if cam_rotation == 90 or cam_rotation == 270 then return h, w end
    return w, h
end

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
                        -- 能不能盖住预览区，按旋转后的宽高比算（见 disp_dims）
                        local cw, ch = disp_dims(w, h)
                        if widget_w > 0 and cw >= widget_w and ch >= widget_h
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
显示缓冲真分探针：先占住相机侧开流要吃的几块，再按 w×h×2 真分两块显示缓冲，最后全还回去。
探针要复现「相机侧已占满自己的份额、显示缓冲才来分」这个时刻：airui.camera 的两块缓冲是在
首帧回调里分的，那时相机侧的帧缓冲与解码缓冲早已落位。只探显示缓冲探到的是开流前的空闲，
真到首帧就分不下。
内存反复占用释放后，即便余量够也可能没有连续块，估算值不可信；
zbuff.HEAP_SRAM 与 airui.camera 的 luat_heap_malloc 是同一池，探得下组件才建得出来。
老固件没有这个常量时退回估算。]]
local function probe_fb_ok(w, h)
    if not (zbuff and zbuff.HEAP_SRAM) then return true end
    local sw, sh = SENSOR_W, SENSOR_H
    -- 相机侧：双帧缓冲 w×h + 解码输入 w×h/4 + 解码输出 w×h×2
    local take = { sw * sh, sw * sh, math.floor(sw * sh / 4), sw * sh * 2 }
    -- 显示缓冲两块殿后，这两块分得下才算数
    local n = w * h * 2
    take[#take + 1] = n
    take[#take + 1] = n
    local held = {}
    for i = 1, #take do
        local b = zbuff.create(take[i], 0, zbuff.HEAP_SRAM)
        if not b then
            for j = #held, 1, -1 do held[j]:free() end
            return false
        end
        held[i] = b
    end
    for j = #held, 1, -1 do held[j]:free() end
    return true
end

-- 预览区尺寸：与旋转后的源分辨率同比缩进黑底框，再按显示缓冲预算收口
local function preview_size(avail_w, avail_h)
    -- 视口按旋转后的源宽高比算（见 disp_dims）
    local src_w, src_h = disp_dims(SENSOR_W > 0 and SENSOR_W or 16,
                                   SENSOR_H > 0 and SENSOR_H or 9)
    local w, h = math.floor(avail_w), math.floor(avail_h)
    local scale = math.min(w / src_w, h / src_h)
    w, h = math.floor(src_w * scale), math.floor(src_h * scale)
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
    -- 探针要连相机侧一起真分几兆，各触发一次强制 GC，白等上百毫秒
    if free and (free - sensor_cost()) >= budget * 6 then
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
        t_frame1 = tick_time.now()
        log.info("uvc_preview_win", "起流打点", "首个原始帧", elapsed_ms(t_frame1, t_enter), "ms")
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
    widget_started = false
    if cam_widget and not cam_widget:is_destroyed() then
        pcall(cam_widget.stop, cam_widget)
    end
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

--[[起显示：挂解码通道 + 开接收（数据流可以还没连上，组件先待命）。

stop 过的组件必须重新 start 才会再收帧，所以这里是幂等的：已经 start 就不再调，
重复 start 会重置组件的显示缓冲，画面会闪一下。]]
local function start_widget()
    if not register_widget() then return end
    if widget_started then return end
    if pcall(cam_widget.start, cam_widget) then
        widget_started = true
    end
end

--[[开数据流；成功后立刻起显示，不等 USB 的 connected 事件。

关流时组件会被 stop（见 stop_widget），而重开流不一定会再产生 connected 事件
（USB 一直处于 Host 状态时没有新的枚举动沿），只靠 on_connected 里那次 start_widget
会让预览永远冻在最后一帧 —— 人脸验证失败降级串行后「画面卡住」就是这么来的。
start_widget 是幂等的（见它上面的说明），connected 事件再补一次也不会重置显示缓冲。]]
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
    start_widget()
    log.info("uvc_preview_win", "起流打点", "开流就绪", elapsed_ms(tick_time.now(), t_enter), "ms")
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
        fit = fit_mode, rotation = active_rotation(), auto_start = false,
    })
    cam_widget = okw and wdg or nil
    widget_registered = false
    widget_started = false     -- 新组件还没 start，交给 start_widget
    if not cam_widget then
        log.warn("uvc_preview_win", "airui.camera 创建失败")
        update_status("本固件不含 airui.camera 组件，无法显示画面", "err")
        return false
    end
    -- 旋转两个入口都试：建参数 rotation 是文档写法，set_rotation 兜老固件不认建参数的情况
    apply_rotation()
    log.info("uvc_preview_win", "预览组件", w, "x", h, "源", SENSOR_W, "x", SENSOR_H,
        "旋转", active_rotation())
    widget_w, widget_h = w, h
    return true
end

-- USB 连接事件（协程内执行）：分辨率不一致就按实际档位重开一次；组件建于建界面时，这里只管数据流
local function on_connected(mode)
    if not window_open then return end
    log.info("uvc_preview_win", "起流打点", "USB 连接", elapsed_ms(tick_time.now(), t_enter), "ms")
    if mode and (mode.w ~= SENSOR_W or mode.h ~= SENSOR_H) then
        log.info("uvc_preview_win", "改用摄像头实际支持的分辨率", mode.w, "x", mode.h)
        SENSOR_W, SENSOR_H = mode.w, mode.h
        close_stream()
        sys.wait(150)
        local ok, err = open_stream()
        if not ok then
            update_status(tostring(err), "err")
        end
        return
    end
    start_widget()
    -- 预览行只归 UVC 页签：人脸页签的状态行留给录入/验证结果，不被重连事件盖掉
    if face_tab == TAB_UVC then
        local rot = active_rotation()
        update_status("预览中 " .. SENSOR_W .. "x" .. SENSOR_H ..
                      " | 适配 " .. (FIT_TITLE[fit_mode] or fit_mode) ..
                      (rot > 0 and (" | 旋转" .. rot) or ""))
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
        -- 走 stop_widget：它会把 widget_started 一起复位，重开流后 start_widget 才会真的再挂上
        stop_widget()
        widget_registered = false
        rec_full = true          -- 停止录像写帧，文件交回 do_record 收尾
        if snap_pending then
            snap_pending = false
            sys.publish("UVC_SNAP_DONE", false)
        end
        update_status("摄像头已断开", "err")
    elseif event == "error" then
        update_status("摄像头错误: " .. tostring((...)), "err")
    end
end

-- ==================== 动作（协程内执行） ====================

-- 拍照：下一帧 MJPEG 直接落盘成 .jpg（不断流）
local function do_photo()
    if busy then return end
    if not cam_ready() then
        update_status("相机能力不可用", "err")
        return
    end
    busy = true
    update_status("拍照中...", "busy")
    photo_path = next_path(".jpg")
    snap_pending = true
    local got, ok = sys.waitUntil("UVC_SNAP_DONE", 4000)
    if not got or not ok then
        snap_pending = false
        update_status("拍照失败：未收到图像帧，请确认摄像头已连接", "err")
    else
        local kb = math.floor((io.fileSize(photo_path) or 0) / 1024)
        update_status("已保存 " .. photo_path .. " | " .. kb .. "KB", "ok")
    end
    busy = false
end

-- 录像：推流帧抽样追加进 .mjpg（MJPEG 帧序列），到时长自动停止
local function do_record()
    if busy then return end
    if not cam_ready() then
        update_status("相机能力不可用", "err")
        return
    end
    busy = true
    local secs = math.floor(rec_ms / 1000)
    update_status("录像中 " .. secs .. " 秒，请保持画面稳定...", "busy")

    -- 倒计时走定时器：下面 sys.wait(rec_ms) 会阻塞本协程，不能自己刷
    local left = secs
    rec_timer = sys.timerLoopStart(function()
        left = left - 1
        if left >= 0 then
            update_status("录像中，剩余 " .. left .. " 秒...", "busy")
        end
    end, 1000)

    rec_frames, rec_saved, rec_written, rec_full = 0, 0, 0, false
    video_path = next_path(".mjpg")
    rec_file = io.open(video_path, "w")
    if not rec_file then
        stop_rec_timer()
        update_status("无法创建文件 " .. video_path, "err")
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

    local msg, pass
    if rec_saved > 0 then
        local kb = math.floor((io.fileSize(video_path) or 0) / 1024)
        msg = "已保存 " .. video_path .. " | " .. rec_saved .. " 帧 | " .. kb .. "KB"
        if rec_full then msg = msg .. " | 达到大小上限" end
        pass = true
    else
        msg, pass = "录像失败：未收到图像帧，请确认摄像头已连接", false
    end
    update_status(msg, pass and "ok" or "err")
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

-- 取「下一步该做什么」的引导文案，见 FACE_GUIDE
local function guide_of(key, code)
    local t = FACE_GUIDE[key]
    if type(t) == "table" then
        return t[code] or FACE_GUIDE.other
    end
    return t or FACE_GUIDE.other
end

-- 错误码转中文说明，对不上就退回「错误码 N」
-- exfacecam.send_cmd 超时返回的第二值是字符串 "timeout" 而不是 MR_* 数字，
-- register/verify 会把它原样当错误码抛回来，这里要单列一条
local function face_err_text(code)
    if code == nil then return "模组未就绪" end
    if type(code) == "number" then
        return (FACE_ERR_TEXT[code] or ("错误码 " .. tostring(code))) .. guide_of("err", code)
    end
    if code == "timeout" then return "模组无应答（超时）" .. guide_of("err", "timeout") end
    return "错误 " .. tostring(code) .. guide_of("other")
end

--[[
人脸模组状态回调，跑在串口收包上下文里（见文件头「人脸识别边界」第 3 条）：
只做限流 + 发消息，不碰控件。包围盒与角度参数本页不消费。
状态不是照抄现象，而是翻译成「下一步该做什么」，见 FACE_GUIDE。
@param state 见 FACE_STATE_TEXT]]
local function on_face_state(state, left, top, right, bottom, yaw, pitch, roll)
    local now = tick_time.now()
    if tick_time.elapsed(now, face_last_state) < FACE_STATE_MIN_GAP_TICKS then return end
    face_last_state = now
    sys.publish("FACE_STATE_TEXT",
        FACE_GUIDE[state] or FACE_STATE_TEXT[state] or ("人脸状态 " .. tostring(state)))
end

-- 界面侧收人脸引导文案。回调只在录入/验证期间来，跟着 face_busy 走，不看页签：
-- 用户中途切到 UVC 页签也要能看到引导。引导文案用琥珀色，跟结果的成功绿 / 失败红区分开
local function on_face_state_text(text)
    if not window_open or not face_busy then return end
    update_status(text, "busy")
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
        update_status(tip, "err")
        return false
    end
    local ok, res = pcall(exfacecam.open, {
        face_uart = face_cfg.uart_id,
        face_rst = face_cfg.rst_pin,
    })
    if not ok or not res then
        log.warn("uvc_preview_win", "exfacecam.open 失败", res)
        update_status(tip, "err")
        return false
    end
    face_on = true
    return true
end

local face_reenumerate  -- 前向声明：face_begin 的复位路径要调它（定义在下方）

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

切换采集模式的唯一手段，走主代码那条路：停流后给摄像头供电脚断电再上电，让模组从 UVC
出图模式整体重启、USB 重新枚举，回到人脸采集模式。断电会连人脸模组一起杀掉（同一根供电
脚），所以重枚举后必须重开串口 —— 旧回包表 / 接收回调随模组作废，留着会把上一轮残留字节
喂给新回包。供电脚不可控时只重开串口，并在日志里点明跳过了这一步。

不用 MID_RESET 软复位：软复位不触发 USB 重新枚举，也就不会再有 connected 事件去 start_widget，
串行动作做完预览会永久冻在最后一帧。断电重枚举靠 connected 自愈，链路更短。
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

--[[人脸动作收尾：复位忙标志 + 弹结果窗 + 按需重开数据流，最后落状态行。
@param msg      动作结果提示
@param need_open boolean true=本次动作停过流（串行路径），收尾要 open_stream 重开画面；
                       false=纯串口动作或并行路径，画面本就没停，不重连
@param tip      table/nil 结果弹窗 { ok=成功与否, title=标题, detail=说明 }；
                nil 表示不弹窗（清空 / 读版本这类纯串口动作只落状态行）
@param kind     状态行语义色（tip 为 nil 时生效）："ok" 绿 / "err" 红 / nil 亮白
弹窗必须早于 open_stream：重开画面要几百毫秒，结果不能等它。
重开失败只在提示尾部带一句，不覆盖动作结果。
注意：必须定义在 face_begin 之前 —— face_begin 的失败分支要调它，
Lua 里后定义的 local 在前面的闭包里是捕获不到的（取到的是全局 nil）。]]
local function face_end(msg, need_open, tip, kind)
    face_busy = false
    -- 有结果窗就按成功 / 失败上色，没有（清空 / 版本这类）用调用方给的 kind
    local color_kind = tip and (tip.ok and "ok" or "err") or kind
    if tip then
        show_face_tip(tip.ok, tip.title, tip.detail)
    end
    if need_open and not quit_requested then
        -- 停过流的路径：画面要重开才有，给一句「预览恢复中」，免得用户以为卡死了
        update_status(tostring(msg) .. " | 预览恢复中...", color_kind)
        local ok, err = open_stream()
        if not ok then
            log.warn("uvc_preview_win", "人脸动作后重开数据流失败", err)
            update_status(tostring(msg) .. " | 画面恢复失败，请退出重进页面", "err")
            return
        end
    end
    update_status(tostring(msg), color_kind)
end

-- 当前动作的中文名：结果弹窗标题统一用「录入 / 验证 + 失败」
local function face_kind_word()
    return (face_kind == "register") and "录入" or "验证"
end

--[[
人脸动作前置（串行 / 轻路径共用）：忙检查 + 开串口；cycle 时再停推流 + 断电重枚举 + 确认就绪。

录入 / 验证走 cycle=true 的串行降级路径：停流后给摄像头供电脚断电再上电，让传感器从 UVC
出图模式整体重启回人脸采集模式（见 face_reenumerate）；取版本 / 清空是纯串口指令，cycle 传
false —— 不停流、不复位、不做就绪自检，直接发指令。

轻路径失败自己给提示并复位 face_busy；cycle 路径的失败必须走 face_end 把画面重开回来
（流已经停了，直接 return 会冻在最后一帧）。成功返回 true，由调用方跑动作再调 face_end 收尾。
@param tip   动作中的提示语
@param cycle boolean true = 停流 + 断电重枚举把传感器切回人脸模式（串行录入/验证）
@return boolean
]]
local function face_begin(tip, cycle)
    if face_busy then return false end
    if not exfacecam then
        update_status("本固件不含 exfacecam 库，人脸识别不可用", "err")
        if cycle then
            show_face_tip(false, face_kind_word() .. "失败", "本固件不含 exfacecam 库")
        end
        return false
    end
    face_busy = true
    update_status(tip, "busy")
    if not face_open("人脸模组串口打不开，请检查接线") then
        face_busy = false
        if cycle then
            show_face_tip(false, face_kind_word() .. "失败", "人脸模组串口打不开，请检查接线")
        end
        return false
    end
    if not cycle then
        return true   -- 纯串口动作：不停流不复位
    end
    close_stream()
    stop_widget()
    -- 断电重枚举让模组从出图模式整体重启、USB 重新枚举回人脸采集模式（见 face_reenumerate）
    face_reenumerate("人脸模组串口重开失败，请检查接线")
    if not face_on then
        -- 此时数据流已经被 close_stream 停掉了，必须走 face_end 把画面重开回来，
        -- 否则预览就永久冻在最后一帧（失败时「画面卡住」的另一条来源）
        local msg = "人脸模组切回采集模式失败，请重试"
        face_end(msg, true, { ok = false, title = face_kind_word() .. "失败", detail = msg .. guide_of("reopen") })
        return false
    end
    if not face_ready() then
        local msg = "人脸模组未就绪，请重试"
        face_end(msg, true, { ok = false, title = face_kind_word() .. "失败", detail = msg .. guide_of("reopen") })
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

--[[把一次动作回包翻译成「标题 / 说明 / 成功与否」三件套：
标题进结果弹窗的大字（录入成功 / 验证失败 ...），说明进弹窗正文与状态行。]]
local function face_result_parts(kind, ok, success, extra, name)
    if not ok then
        return (kind == "register" and "录入失败" or "验证失败"),
            "动作异常：" .. tostring(extra) .. guide_of("other"), false
    end
    if kind == "register" then
        if success then
            return "录入成功", "用户ID " .. tostring(extra or "?") .. " " .. tostring(name), true
        end
        return "录入失败", face_err_text(extra), false
    end
    if success then
        local info = type(extra) == "table" and extra or {}
        local who = tostring(info.name or "")
        if who ~= "" then who = " " .. who end
        return "验证通过", "用户ID " .. tostring(info.user_id or "?") .. who, true
    end
    return "验证失败", face_err_text(extra), false
end

--[[录入/验证收尾：状态行与结果弹窗共用同一份文案，再交 face_end 恢复画面。
成功用空格连接、失败用冒号，保持原来状态行的读法。]]
local function face_finish(kind, ok, success, extra, name, need_open)
    local title, detail, pass = face_result_parts(kind, ok, success, extra, name)
    local msg = pass and (title .. " " .. detail) or (title .. "：" .. detail)
    face_end(msg, need_open, { ok = pass, title = title, detail = detail })
end

--[[模组已经给出明确结论的错误码：重试一百次也是同一个结果。

1 人脸不匹配 / 2 已中止 / 5 未知原因（画面里没人脸时模组多半回这个）/ 8 用户不存在 /
9 用户数已满 / 10 该人脸已录入 / 12 活体未通过 / 13 操作超时。
这些属于「这一次就是识别不出来」，不是「并行把识别拖慢了」。]]
local FACE_DECISIVE_ERR = {
    [1] = true, [2] = true, [5] = true, [8] = true,
    [9] = true, [10] = true, [12] = true, [13] = true,
}

--[[并行失败后值不值得降级串行重试。

只有「模组 / 时序原因」的失败才值得重试（pcall 异常、摄像头异常、参数 / 内存 / 授权问题）。
判定类失败一律不重试：降级串行要停流 + 复位传感器 + 重新就绪自检，前后十几秒画面冻在
最后一帧 —— 尤其是「一直没检测到人脸」这种，等 15 秒超时后再冻十几秒，用户看到的就是卡死。]]
local function face_retry_worth(ok, success, extra)
    if not ok then return true end              -- 动作异常：值得换串行再试一次
    if success then return false end
    if extra == nil then return false end       -- 串口没开之类：重试也不会变
    if extra == "timeout" then return false end -- 模组应答超时（常见于画面里没人脸）
    return not FACE_DECISIVE_ERR[extra]
end

--[[
录入/验证统一入口：按 face_mode 决定并行或串行。
- serial     ：face_begin(cycle=true) 停流串行
- auto       ：预览不停流直接识别；并行失败（异常/业务失败/无新帧/流未开）降级串行重试一次
- concurrent ：只走并行，失败不降级
]]
local function do_face_capture(kind)
    if face_busy then return end
    face_kind = kind
    hide_face_tip()   -- 上一轮结果窗先收掉，别让两条结果叠在一起
    local doing = (kind == "register") and "录入" or "验证"

    if face_mode == "serial" then
        if not face_begin(doing .. "中，请正对摄像头...", true) then return end
        local ok, success, extra, name = face_run_once(kind)
        log.warn("uvc_preview_win", "人脸" .. doing, "serial", tostring(ok), tostring(success), tostring(extra))
        face_finish(kind, ok, success, extra, name, true)
        return
    end

    -- 并行：先开串口（不停流），再降帧 + 确认画面活着
    face_busy = true
    update_status(doing .. "中，请正对摄像头...", "busy")
    if not face_open("人脸模组串口打不开，请检查接线") then
        face_busy = false
        show_face_tip(false, doing .. "失败", "人脸模组串口打不开" .. guide_of("serial"))
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
            -- 前面已经降过帧，这里要还原，否则预览一直卡在 3fps
            apply_uvc_fps(UVC_FPS)
            update_status(doing .. "失败：预览无画面", "err")
            show_face_tip(false, doing .. "失败", "预览无画面，识别不了" .. guide_of("reopen"))
            return
        end
        log.warn("uvc_preview_win", "并行" .. doing .. "前置不满足，降级串行")
        face_busy = false
        if not face_begin(doing .. "中，请正对摄像头...", true) then return end
        local ok, success, extra, name = face_run_once(kind)
        face_finish(kind, ok, success, extra, name, true)
        return
    end

    log.info("uvc_preview_win", "并行" .. doing .. "，预览不停流 fps=" .. tostring(face_busy_fps))
    local ok, success, extra, name = face_run_once(kind)
    log.warn("uvc_preview_win", "人脸" .. doing, "parallel", tostring(ok), tostring(success), tostring(extra))

    if ok and success then
        apply_uvc_fps(UVC_FPS)
        face_finish(kind, ok, success, extra, name, false)
        return
    end

    if face_mode ~= "auto" then
        apply_uvc_fps(UVC_FPS)
        face_finish(kind, ok, success, extra, name, false)
        return
    end

    if not face_retry_worth(ok, success, extra) then
        -- 模组已经给出明确结论（人脸不匹配等）：重试没有意义，而且降级串行要停流，
        -- 画面会冻在最后一帧十几秒 —— 看起来就是「预览卡住」。直接出结果。
        log.warn("uvc_preview_win", "并行" .. doing .. "失败为判定性失败，不降级重试", tostring(extra))
        apply_uvc_fps(UVC_FPS)
        face_finish(kind, ok, success, extra, name, false)
        return
    end

    log.warn("uvc_preview_win", "并行" .. doing .. "失败，降级串行重试一次")
    face_busy = false
    if not face_begin("正在重新" .. doing .. "，请稍候...", true) then return end
    local ok2, success2, extra2, name2 = face_run_once(kind)
    face_finish(kind, ok2, success2, extra2, name2, true)
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
    local msg, pass
    if ok and res then
        msg, pass = "已删除全部用户", true
        if before then msg = msg .. "（原有 " .. tostring(before) .. " 个）" end
    else
        msg, pass = "删除失败", false
    end
    face_end(msg, false, nil, pass and "ok" or "err")
end

-- 读模组固件版本：串口通没通，这一条最直观
local function do_face_version()
    if not face_begin("读取模组版本中...") then return end
    local ok, res, ver = pcall(exfacecam.get_version)
    local msg, pass
    if ok and res then
        msg, pass = "模组版本 " .. tostring(ver or "?"), true
    else
        msg, pass = "版本读取失败", false
    end
    face_end(msg, false, nil, pass and "ok" or "err")
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
    widget_started = false
    main_container = nil
    preview_area = nil
    status_label = nil
    window_id = nil
    tab_uvc_row, tab_face_row = nil, nil
    uvc_bar, face_bar = nil, nil
    -- 结果弹窗是 main_container 的子控件，随它一起销毁，这里只清句柄并停掉定时器
    if face_tip_timer then
        pcall(sys.timerStop, face_tip_timer)
        face_tip_timer = nil
    end
    face_tip, face_tip_card = nil, nil
    face_tip_title, face_tip_detail = nil, nil
    face_tip_text_w = 0
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
                if not ok then update_status(tostring(err), "err") end
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

-- ==================== 人脸结果弹窗 ====================

-- 收掉自动关闭定时器
local function stop_face_tip_timer()
    if face_tip_timer then
        pcall(sys.timerStop, face_tip_timer)
        face_tip_timer = nil
    end
end

-- 收起结果弹窗：只切显隐，控件本体随页面一起销毁
hide_face_tip = function()
    stop_face_tip_timer()
    if face_tip and not face_tip:is_destroyed() then
        face_tip:set_hidden(true)
    end
end

--[[显示人脸结果弹窗：成功绿、失败红，FACE_TIP_CLOSE_MS 后自动收起。

跑在命令协程里，只改文案 / 颜色 / 显隐，不新建控件 —— 建销控件只能在界面线程
（见文件头「人脸识别边界」第 3 条），弹窗控件在建界面时就已经建好并常驻隐藏。
@param ok     boolean 成功与否，决定标题与边框的语义色
@param title  string 大字标题（录入成功 / 验证失败 ...）
@param detail string 说明文案，超长按两行截断
]]
show_face_tip = function(ok, title, detail)
    if not window_open or not face_tip or face_tip:is_destroyed() then return end
    local accent = ok and theme.C.green or theme.C.rose
    if face_tip_card and not face_tip_card:is_destroyed() then
        pcall(face_tip_card.set_border_color, face_tip_card, accent, theme.dp(3))
    end
    if face_tip_title and not face_tip_title:is_destroyed() then
        face_tip_title:set_color(accent)
        face_tip_title:set_text(
            theme.fit_text(tostring(title or ""), face_tip_text_w, theme.fs("h1"), 1))
    end
    if face_tip_detail and not face_tip_detail:is_destroyed() then
        face_tip_detail:set_text(
            theme.fit_text(tostring(detail or ""), face_tip_text_w, theme.fs("body"), 2))
    end
    face_tip:set_hidden(false)
    -- 重新计时：两条结果不叠加，后一条从头算满 3 秒
    stop_face_tip_timer()
    face_tip_timer = sys.timerStart(hide_face_tip, FACE_TIP_CLOSE_MS)
end

--[[建结果弹窗：半透明遮罩 + 居中卡片 + 大字标题 + 两行说明，平时隐藏。
必须建在 build_ui 最后（创建顺序 = z-order），才盖得住预览画面与右侧按钮。
遮罩自己吃掉触摸，弹窗期间的点击不会落到下面的拍照 / 录入按钮上；
点一下弹窗可以提前收掉（失败的验证不必等满 3 秒才能重试）。]]
local function build_face_tip()
    face_tip = theme.box(main_container, {
        x = 0, y = 0, w = sw, h = sh,
        color = theme.C.scrim, opa = theme.OPA.scrim,
        on_click = function() hide_face_tip() end,
    })
    if not face_tip then return end

    local inset = theme.dp(20)
    local card_w = math.min(math.floor(sw * 0.8), sw - 2 * pad)
    local text_w = card_w - 2 * inset
    local title_px, detail_px = theme.fs("h1"), theme.fs("body")
    local title_h = title_px + theme.dp(12)
    local detail_h = (detail_px + 3) * 2 + theme.dp(6)
    local card_h = inset * 2 + title_h + theme.dp(10) + detail_h
    local card_x = math.floor((sw - card_w) / 2)
    local card_y = math.floor((sh - card_h) / 2)

    face_tip_card = theme.box(face_tip, {
        x = card_x, y = card_y, w = card_w, h = card_h,
        color = theme.C.dialog, opa = 255, radius = theme.R.xl,
        border = theme.C.stroke, border_w = theme.dp(3),
        on_click = function() hide_face_tip() end,
    })
    if not face_tip_card then
        face_tip:set_hidden(true)
        return
    end
    face_tip_title = theme.label(face_tip_card, {
        x = inset, y = inset, w = text_w, h = title_h,
        text = "", px_size = title_px, color = theme.C.green,
        align = airui.TEXT_ALIGN_CENTER,
    })
    face_tip_detail = theme.label(face_tip_card, {
        x = inset, y = inset + title_h + theme.dp(10), w = text_w, h = detail_h,
        text = "", px_size = detail_px, color = theme.C.t1,
        align = airui.TEXT_ALIGN_CENTER,
    })
    face_tip_text_w = text_w
    face_tip:set_hidden(true)
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
    apply_rotation()
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
@param x 行起点，不传取左页边距（横屏要挪到右列，见 build_side_ui）
]]
local function build_tabs(w, y, h, gap, x)
    x = x or pad
    local items = {
        { text = "UVC 测试", on_click = function() switch_tab(TAB_UVC) end },
        { text = "人脸识别", on_click = function() switch_tab(TAB_FACE) end },
    }
    tab_uvc_row = theme.box(main_container, {
        x = x, y = y, w = w, h = h, color = theme.C.black, opa = 0,
    })
    theme.pills(tab_uvc_row, { x = 0, y = 0, w = w, h = h, gap = gap, active = 1, items = items })
    tab_face_row = theme.box(main_container, {
        x = x, y = y, w = w, h = h, color = theme.C.black, opa = 0,
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
@param w, y, h 栏几何（h 是单个按钮高，栏高按行数铺）
@param gap 按钮间距
@param has_face 是否建人脸栏
@param x 栏起点，不传取左页边距（横屏要挪到右列，见 build_side_ui）
@param cols 按钮列数，不传 4（一行 4 个）；横屏右列窄传 2，排成 2 列 2 行
]]
local function build_ctrl_bars(w, y, h, gap, has_face, x, cols)
    x = x or pad
    cols = cols or 4
    local rows = math.ceil(4 / cols)
    local bw = math.floor((w - (cols - 1) * gap) / cols)
    -- 栏高按行数铺：cols = 4 时只有一行，与改造前完全一致
    local bar_h = rows * h + (rows - 1) * gap

    -- 按钮表：前两个是实底主按钮，后两个是描边幽灵按钮
    local uvc_items = {
        { text = "拍照", cmd = "photo" },
        { text = "录像", cmd = "record" },
        { text = "时长", cmd = "duration", ghost = true },
        { text = "适配", cmd = "fit", ghost = true },
    }
    local face_items = {
        { text = "录入", cmd = "face_register" },
        { text = "验证", cmd = "face_verify" },
        { text = "清空", cmd = "face_clear", ghost = true },
        { text = "版本", cmd = "face_version", ghost = true },
    }

    -- 按列数铺按钮：k 从 1 起，一行 cols 个，先往右再往下
    local function fill(bar, items)
        for k, it in ipairs(items) do
            local bx = ((k - 1) % cols) * (bw + gap)
            local by = math.floor((k - 1) / cols) * (h + gap)
            local cmd = it.cmd
            local click = function() sys.publish("UVC_CMD", cmd) end
            if it.ghost then
                theme.ghost_button(bar, {
                    x = bx, y = by, w = bw, h = h,
                    text = it.text, on_click = click,
                })
            else
                theme.button(bar, {
                    x = bx, y = by, w = bw, h = h,
                    text = it.text, on_click = click,
                })
            end
        end
    end

    uvc_bar = theme.box(main_container, {
        x = x, y = y, w = w, h = bar_h, color = theme.C.black, opa = 0,
    })
    fill(uvc_bar, uvc_items)

    if has_face then
        face_bar = theme.box(main_container, {
            x = x, y = y, w = w, h = bar_h, color = theme.C.black, opa = 0,
        })
        fill(face_bar, face_items)
    end

    uvc_bar:set_hidden(face_tab ~= TAB_UVC)
    if face_bar then face_bar:set_hidden(face_tab ~= TAB_FACE) end
end

-- ==================== 横屏左右结构 ====================

--[[
供电与接线提示（人脸识别摄像头）：AirCAMERA_1034 用 12VDC 电源头供电，出图走 USB、
人脸走串口，两根线都要接。摆在右列操作区，只在带 face 子表的机型显示（见文件头【人脸识别】）。
分隔符只用 ASCII 的 "|"：内置字库不含 "·"(U+00B7)，见 ui_theme「字体能力约束」。]]
local PWR_TIP = "供电 | 设备使用 12VDC 电源头供电\n接线 | 需接入 USB 接口与串口 共 2 个接口"

-- 提示块内边距（上下左右各留这么多，块本身再带 1px 描边）
local PWR_TIP_PAD = 8

--[[
提示块盒高：按 theme.text_lines 估出实际占几行再定盒高（行高 = 字号 + 3），
估少了文字被裁、估多了只是块高多几像素。先算后摆：右列的间隙要按块高摊余量。]]
local function power_tip_h(w)
    local fs = theme.fs("micro") -- 灰字小号；15px 是全工程字号下限
    local inner_w = w - 2 * PWR_TIP_PAD - 2
    local lines = 0
    for seg in string.gmatch(PWR_TIP, "([^\n]+)") do
        lines = lines + theme.text_lines(seg, inner_w, fs)
    end
    return lines * (fs + 3) + 2 * PWR_TIP_PAD
end

-- 供电与接线提示块：灰字小号多行（文案见 PWR_TIP），返回块高
local function build_power_tip(x, w, y)
    local h = power_tip_h(w)
    local tip = theme.box(main_container, {
        x = x, y = y, w = w, h = h,
        color = theme.C.surface, opa = theme.OPA.fill,
        radius = theme.R.md, border = theme.C.stroke, border_w = 1,
    })
    -- 子控件原点是父容器内容区（外框 - 描边），盒宽扣掉描边才不会探出内容区画滚动条
    theme.label(tip, {
        x = PWR_TIP_PAD, y = PWR_TIP_PAD,
        w = w - 2 * PWR_TIP_PAD - 2, h = h - 2 * PWR_TIP_PAD,
        text = PWR_TIP, px_size = theme.fs("micro"),
        color = theme.C.t2, align = airui.TEXT_ALIGN_LEFT,
    })
    return h
end

--[[
横屏左右结构：左列是预览画面区，占满标题栏以下的整段高度；右列自上而下排
页签 / 状态行 / 供电接线提示 / 控制按钮。控制按钮贴右列底部（与左列预览框下沿齐平），
余下留白均摊进上方各块之间的间隙，块高本身不变。
竖屏走 build_ui 下面原有的上下结构（宽度不够，硬拆会把预览挤没）。
@param card_w 内容区宽（= sw - 2*pad）
@param y 标题栏下方的起始 y
@param gap, ctrl_h, status_h 与上下结构同一套控件尺寸
@param has_face 是否带人脸识别（带则多一页签与供电接线提示）
]]
local function build_side_ui(card_w, y, gap, ctrl_h, status_h, has_face)
    --[[
    左列 62% 给预览，右列取余下 38%。右列放得下是按实际文字宽度复核过的：
    两列按钮 bw 约 140px（"拍照" 两字约 32px）、两个页签胶囊各约 140px（"UVC 测试" 约 80px）。]]
    local left_w = math.floor((card_w - gap) * 0.62)
    local right_w = card_w - left_w - gap
    local right_x = pad + left_w + gap

    -- 左列：纯黑底 + 描边，airui.camera 覆盖在上面出画面（同上下结构）
    local preview_h = sh - y - pad
    theme.box(main_container, {
        x = pad, y = y, w = left_w, h = preview_h,
        color = theme.C.black, opa = 255,
        radius = theme.R.lg, border = theme.C.stroke, border_w = 1,
    })
    preview_area = { x = pad, y = y, w = left_w, h = preview_h }

    -- 右列块高先算好；4 个按钮在窄右列里排 2 列 2 行，栏高按行数铺
    local tab_h = has_face and theme.dp(36) or 0
    local tip_h = has_face and power_tip_h(right_w) or 0
    local bar_h = 2 * ctrl_h + gap
    local top_h = tab_h + status_h + tip_h
    local bar_y = sh - pad - bar_h
    if bar_y < y + top_h + gap then bar_y = y + top_h + gap end
    local n_gap = has_face and 3 or 1 -- 页签→状态行→提示块→控制栏之间的间隙数
    local vgap = math.floor((bar_y - y - top_h) / n_gap)
    if vgap < gap then vgap = gap end

    -- 右列自上而下：页签（有人脸才出）
    local ry = y
    if has_face then
        build_tabs(right_w, ry, tab_h, gap, right_x)
        ry = ry + tab_h + vgap
    end

    -- 状态行：宽度跟右列走，update_status 按它截断（见 update_status）
    status_w = right_w
    status_label = theme.label(main_container, {
        x = right_x, y = ry, w = right_w, h = status_h,
        text = "准备中...", px_size = status_px(),
        color = theme.C.t1, align = airui.TEXT_ALIGN_LEFT,
    })
    ry = ry + status_h + vgap

    -- 供电与接线提示（有人脸才出）
    if has_face then
        local h = build_power_tip(right_x, right_w, ry)
        ry = ry + h + vgap
    end

    -- 控制按钮：贴右列底部
    build_ctrl_bars(right_w, bar_y, ctrl_h, gap, has_face, right_x, 2)

    --[[组件必须在建界面时就建好并挂上解码通道，早于 excamera.open 开流（见 create_widget）。
    排到状态行之后再建，建不出组件时的提示才写得进状态行。]]
    if create_widget() then
        start_widget()
    end

    -- 结果弹窗最后建：创建顺序即 z-order，晚了才盖得住预览画面与按钮。
    -- 没有人脸模组的机型不建它，白占几个控件
    if has_face then build_face_tip() end
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
    local status_h = status_px() + theme.dp(10)

    -- 横屏宽度够，走「左预览 + 右操作区」的左右结构；竖屏走下面的上下结构
    if sw >= sh then
        build_side_ui(card_w, y, gap, ctrl_h, status_h, has_face)
        return
    end

    -- 页签行：预览区之上，只有配了 face 子表才出
    local tab_h = 0
    if has_face then
        tab_h = theme.dp(36)
        build_tabs(card_w, y, tab_h, gap)
        y = y + tab_h + gap
    end

    -- 底部：状态行 + 控制栏，剩余高度全给预览区
    -- 预览框以下依次是 gap / 状态行 / gap / 控制栏，余量照 pad 留在最下
    local bottom_h = gap + status_h + gap + ctrl_h
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
        text = "准备中...", px_size = status_px(),
        color = theme.C.t1, align = airui.TEXT_ALIGN_LEFT,
    })

    local cy = sy + status_h + gap
    build_ctrl_bars(card_w, cy, ctrl_h, gap, has_face)

    -- 结果弹窗最后建：创建顺序即 z-order，晚了才盖得住预览画面与按钮。
    -- 没有人脸模组的机型不建它，白占几个控件
    if has_face then build_face_tip() end
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
        -- 画面旋转角只认 0/90/180/270，其余按不转处理（同 airui.camera 的约定）
        local r = entry.rotation
        cam_rotation = (r == 90 or r == 180 or r == 270) and r or 0
        -- 人脸页签可另给一个旋转角（face.rotation），不写沿用 UVC 页签的值
        local fr = face_cfg and face_cfg.rotation
        face_rotation = (fr == 90 or fr == 180 or fr == 270) and fr or cam_rotation
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
    update_status("等待摄像头连接...", "busy")
end

local function on_destroy()
    -- excamera.close 含 sys.wait，不能在销毁回调里直接调，交回命令协程收尾；
    -- 根控件先隐藏，画面立刻撤掉，控件销毁留在停流之后（顺序见 close_stream）
    stop_rec_timer()
    if probe_timer then
        sys.timerStop(probe_timer)
        probe_timer = nil
    end
    hide_face_tip()   -- 收掉结果弹窗并停自动关闭定时器，免得回调打到已销毁的控件
    sys.unsubscribe("FACE_STATE_TEXT", on_face_state_text)
    if main_container and not main_container:is_destroyed() then
        pcall(main_container.set_hidden, main_container, true)
    end
    request_quit()
    sys.publish("TEST_WIN_CLOSED")   -- 收口：功能测试页据此断开本页用的接口
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler(id)
    if id then periph_id = id end
    -- 起流耗时从点击这一刻起算
    t_enter = tick_time.now()
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
