--[[
@module  excloud_upload
@summary 文件上传模块（图片/音频/运维日志）
@version 1.0.0
@date    2026.08.29
@author  LuatOS 嵌入式软件设计开发
@usage
本模块负责两类文件上传能力：
1. 【普通文件上传】图片、音频文件的上传，使用 excloud.upload_image / excloud.upload_audio；
2. 【运维日志上传】业务运维日志的记录（excloud.mtn_log）与批量上传（excloud.upload_mtnlogs）。

【上传回调机制说明——两类回调，勿混淆】
A. 单文件上传结果回调：excloud.set_upload_callback(cb)
   cb(file_type, file_name, result_ok, result_msg)
   file_type: 1=图片, 2=音频, 3=运维日志
   该回调在每次”单文件上传“结束时被触发。

B. 批量运维日志上传事件：通过 excloud.on 全局回调触发
   mtn_log_upload_start      —— 开始上传，data.file_count 为待上传文件数
   mtn_log_upload_progress   —— 上传进度，data.current_file/data.total_files/data.file_name 等
   mtn_log_upload_complete   —— 上传完成，data.success_count/data.failed_count/data.total_files
   这些事件已在 excloud_main 模块的全局回调中统一打印，本模块主要负责”触发上传“与”生成日志“。

【运维日志上传触发方式】
1. 云端下行信令：服务器下发 MTN_LOG_UPLOAD_REQ_SIGNAL(25) 时，excloud 库内部会自动
   发送响应(26)并启动 upload_mtn_log_files() 上传，同时产生 mtn_log_upload_* 事件。
   本模块的 handle_mtn_log_upload_signal() 仅为演示业务侧如何处理该信令。
2. 主动触发：业务方随时可调用 M.trigger_upload_mtnlog() 主动上传一次。
3. 定时上传：可开启 config.auto_upload_mtnlog，每隔 mtn_log_upload_cycle 秒主动上传一次。

注：示例中的上传文件均为演示用，通过在 /luadb/ 目录写入模拟内容来构造文件，
真实项目中请替换为实际采集的图片/音频文件路径。
]]

-- 依赖库
local excloud = require("excloud")

-- 配置
local config = require("config")

-- 本模块对外导出的表
local M = {}

-- 日志辅助
local log_tag = config.log_tag
local function log_info(...) log.info(log_tag, ...) end
local function log_warn(...) log.warn(log_tag, ...) end
local function log_error(...) log.error(log_tag, ...) end

-- 演示文件目录（LuatOS 常用可写目录为 /luadb/ 或 /usr/）
local DEMO_DIR = "/luadb"

-- =========================================================================
-- 【单个文件上传结果回调】
-- 注册到 excloud.set_upload_callback，用于观察每次单文件上传的结果
-- @param file_type 文件类型：1=图片, 2=音频, 3=运维日志
-- @param file_name 文件名
-- @param result_ok 是否成功
-- @param result_msg 结果信息
-- =========================================================================
local function on_file_upload_result(file_type, file_name, result_ok, result_msg)
    local type_name = "unknown"
    if file_type == 1 then
        type_name = "图片"
    elseif file_type == 2 then
        type_name = "音频"
    elseif file_type == 3 then
        type_name = "运维日志"
    end
    if result_ok then
        log_info("[文件上传] 成功", "类型:", type_name, "文件:", file_name)
    else
        log_warn("[文件上传] 失败", "类型:", type_name, "文件:", file_name, "原因:", result_msg)
    end
end

-- 注册单个文件上传结果回调
local cb_ok, cb_err = excloud.set_upload_callback(on_file_upload_result)
if cb_ok then
    log_info("已注册单文件上传结果回调")
else
    log_warn("注册单文件上传结果回调失败:", cb_err)
end

-- =========================================================================
-- 生成一个演示文件
-- @param path 目标路径
-- @param data 文件内容（字符串）
-- @return ok, err
-- =========================================================================
local function gen_demo_file(path, data)
    local f = io.open(path, "wb")
    if not f then
        return false, "无法创建文件: " .. path
    end
    f:write(data)
    f:close()
    return true, nil
end

-- =========================================================================
-- 演示：上传一张图片
-- 真实项目中 file_path 为实际图片路径（如 /luadb/camera.jpg）
-- 这里先生成一个模拟的 jpg 文件再上传。
-- =========================================================================
function M.upload_demo_image()
    local path = DEMO_DIR .. "/demo_img_" .. os.time() .. ".jpg"
    -- 构造一段假的“图片”内容（真实项目请替换为实际图像字节）
    local ok, err = gen_demo_file(path, "DEMO_IMAGE_CONTENT_1234567890")
    if not ok then
        log_error("生成演示图片失败:", err)
        return false, err
    end

    log_info("开始上传演示图片:", path)
    local up_ok, up_err = excloud.upload_image(path, "demo_img.jpg")
    if not up_ok then
        log_warn("上传演示图片失败:", up_err)
        return false, up_err
    end
    log_info("上传演示图片已触发")
    return true
end

-- =========================================================================
-- 演示：上传一段音频
-- 真实项目中 file_path 为实际录音路径（如 /luadb/rec.mp3）
-- =========================================================================
function M.upload_demo_audio()
    local path = DEMO_DIR .. "/demo_audio_" .. os.time() .. ".mp3"
    local ok, err = gen_demo_file(path, "DEMO_AUDIO_CONTENT_abcdef")
    if not ok then
        log_error("生成演示音频失败:", err)
        return false, err
    end

    log_info("开始上传演示音频:", path)
    local up_ok, up_err = excloud.upload_audio(path, "demo_audio.mp3")
    if not up_ok then
        log_warn("上传演示音频失败:", up_err)
        return false, up_err
    end
    log_info("上传演示音频已触发")
    return true
end

-- =========================================================================
-- 运维日志：写入一条业务日志（供上传）
-- 通过 excloud.mtn_log(tag, ...) 记录，excloud 内部委托给 exmtn.log
-- @param tag 日志标记
-- @param ... 日志内容
-- =========================================================================
function M.write_mtn_log(tag, ...)
    local ok, err = excloud.mtn_log(tag, ...)
    if not ok then
        log_warn("写入运维日志失败:", err)
        return false, err
    end
    return true
end

-- =========================================================================
-- 主动触发一次运维日志上传
-- 直接调用 excloud.upload_mtnlogs()（内部复用 upload_mtn_log_files 逻辑）
-- 上传完成后会给 excloud.on 回调派发 mtn_log_upload_* 事件
-- =========================================================================
function M.trigger_upload_mtnlog()
    log_info("主动触发运维日志上传")
    local ok, err = excloud.upload_mtnlogs()
    if not ok then
        log_warn("触发运维日志上传未执行:", err)
        return false, err
    end
    return true
end

-- =========================================================================
-- 处理云端下发的运维日志上传请求信令
-- 【说明】excloud 库内部已自动处理该信令（发送响应 26 并启动上传），
-- 业务侧此回调仅作演示，可根据需要在信令到达时附加业务动作。
-- @param value 信令携带的值（示例中不解析具体值）
-- =========================================================================
function M.handle_mtn_log_upload_signal(value)
    log_info("收到云端运维日志上传请求信令，值:", tostring(value))
    log_info("excloud 库内部已自动响应并启动上传，业务侧无需重复上传。")
    -- 如需立即刷新业务侧状态，可在此追加逻辑；不需要重复调用 upload_mtnlogs()，
    -- 否则会与库内部自动发起的上传相互叠加（库内部有正在上传的互斥保护，会跳过重复请求）。
end

-- =========================================================================
-- 记录演示日志任务：定期写入几条运维日志，供上传时可见
-- =========================================================================
local function log_demo_task()
    log_info("运维日志记录任务启动")
    -- 等待 excloud.setup 完成事件（timeout=nil 无限等待）：
    -- 第一个返回值 ok 判断是否收到消息，第二/三个返回值是发布方携带的 setup 结果；
    -- 只有 setup 成功返回，config.mtn_log_enabled 才会写入库内部配置，运维日志才可用；
    -- setup 不依赖网络与鉴权，鉴权失败/断网时日志照常记录，便于排查。
    local ok, setup_ok, setup_err = sys.waitUntil("excloud_setup_done")
    if not setup_ok then
        -- setup 失败（设备 ID 获取失败等硬件级故障），运维日志不可用，退出任务
        log_error("excloud.setup 失败，运维日志不可用:", setup_err or "")
        return
    end
    log_info("excloud.setup 已完成，开始周期记录运维日志")
    -- 一直循环，每隔一段时间写入一条业务运维日志
    while true do
        M.write_mtn_log("demo", "周期记录", "sys_uptime=" .. os.time(), "tag=" .. config.log_tag)
        sys.wait(60 * 1000) -- 每 60 秒写一条
    end
end

-- =========================================================================
-- 定时上传运维日志任务（可选）
-- 若 config.auto_upload_mtnlog 为 true，则每隔 mtn_log_upload_cycle 秒主动上传一次
-- 注意：需等待云平台鉴权成功后再上传
-- =========================================================================
local function auto_upload_task()
    if not config.auto_upload_mtnlog then
        log_info("未开启自动上传运维日志")
        return
    end

    log_info("自动上传运维日志任务启动，周期:", config.mtn_log_upload_cycle, "秒")

    -- 等待鉴权成功事件
    local authed = false
    sys.subscribe("excloud_authed", function() authed = true end)
    while not authed do
        sys.wait(1000)
    end

    -- 周期上传
    while true do
        M.trigger_upload_mtnlog()
        sys.wait(config.mtn_log_upload_cycle * 1000)
    end
end

-- =========================================================================
-- 【真实图片上传测试任务】
-- 说明：本示例默认在每次开机鉴权成功后，自动上传一张真实图片，用于验证
--       「图片上传」完整链路（设备上传 → 平台接收 → 单文件上传回调反馈）。
--
-- 【如何放置自己的图片，按以下步骤操作】
--   1. 准备一张真实图片（jpg/png 均可），命名为 test.jpg；
--   2. 将 test.jpg 放入工程编译目录（与 main.lua 同级）；
--   3. 重新编译打包，图片会随脚本一同烧录到设备 /luadb/ 目录下；
--   4. 上传参数在下方两个常量中修改：
--        REAL_IMAGE_PATH —— 图片在设备内的路径（编译后即为 /luadb/ 下的文件）
--        REAL_IMAGE_NAME —— 平台侧显示的文件名（可自定义，如 "photo_001.jpg"）
--      例如要上传 /luadb/photo.png：REAL_IMAGE_PATH = "/luadb/photo.png"，
--      REAL_IMAGE_NAME = "photo.png"；
--   5. 若不想开机自动上传演示图片，删除本任务函数与下方对应的
--      sys.taskInit(upload_real_image_task) 一行即可。
--
-- 上传结果通过文件开头注册的 excloud.set_upload_callback 回调打印
-- （[文件上传] 成功/失败 类型: 图片 文件: xxx），无需在本任务内等待。
-- =========================================================================
local REAL_IMAGE_PATH = "/luadb/test.jpg"   -- 设备内图片路径（随工程编译进 /luadb/）
local REAL_IMAGE_NAME = "test.jpg"          -- 平台侧显示的文件名

local function upload_real_image_task()
    log_info("真实图片上传任务启动，等待鉴权成功...")

    -- 等待鉴权成功事件（与 auto_upload_task 相同的等待方式）
    local authed = false
    sys.subscribe("excloud_authed", function() authed = true end)
    while not authed do
        sys.wait(1000)
    end
    log_info("鉴权成功，开始检查待上传图片")

    -- 检查图片是否已随工程编译进 /luadb/（未找到时提示放置方法）
    if not io.exists(REAL_IMAGE_PATH) then
        log_warn("未找到待上传图片:", REAL_IMAGE_PATH)
        log_warn("请将图片命名为 test.jpg 放入工程编译目录（与 main.lua 同级）后重新编译烧录")
        return
    end

    log_info("开始上传真实图片，设备路径:", REAL_IMAGE_PATH, "平台文件名:", REAL_IMAGE_NAME)
    local up_ok, up_err = excloud.upload_image(REAL_IMAGE_PATH, REAL_IMAGE_NAME)
    if not up_ok then
        log_warn("上传真实图片未执行:", up_err)
        return
    end
    log_info("真实图片上传已触发，结果将通过单文件上传回调反馈")
end

-- =========================================================================
-- 【真实音频上传测试任务】
-- 说明：本示例默认在每次开机鉴权成功后，自动上传一段真实音频，用于验证
--       「音频上传」完整链路（设备上传 → 平台接收 → 单文件上传回调反馈）。
--       与真实图片上传任务并行：两者均在鉴权成功后各自触发上传，互不等待，
--       便于同时验证两类上传链路（若实测并发上传异常，可再改为串行）。
--
-- 【如何放置自己的音频，按以下步骤操作】
--   1. 准备一段真实音频（mp3/wav 均可），命名为 test.mp3；
--   2. 将 test.mp3 放入工程编译目录（与 main.lua 同级）；
--   3. 重新编译打包，音频会随脚本一同烧录到设备 /luadb/ 目录下；
--   4. 上传参数在下方两个常量中修改：
--        REAL_AUDIO_PATH —— 音频在设备内的路径（编译后即为 /luadb/ 下的文件）
--        REAL_AUDIO_NAME —— 平台侧显示的文件名（可自定义，如 "record_001.mp3"）
--      例如要上传 /luadb/rec.wav：REAL_AUDIO_PATH = "/luadb/rec.wav"，
--      REAL_AUDIO_NAME = "rec.wav"；
--   5. 若不想开机自动上传演示音频，删除本任务函数与下方对应的
--      sys.taskInit(upload_real_audio_task) 一行即可。
--
-- 上传结果通过文件开头注册的 excloud.set_upload_callback 回调打印
-- （[文件上传] 成功/失败 类型: 音频 文件: xxx），无需在本任务内等待。
-- =========================================================================
local REAL_AUDIO_PATH = "/luadb/test.mp3"   -- 设备内音频路径（随工程编译进 /luadb/）
local REAL_AUDIO_NAME = "test.mp3"          -- 平台侧显示的文件名

local function upload_real_audio_task()
    log_info("真实音频上传任务启动，等待鉴权成功...")

    -- 等待鉴权成功事件（与真实图片上传任务相同的等待方式）
    local authed = false
    sys.subscribe("excloud_authed", function() authed = true end)
    while not authed do
        sys.wait(1000)
    end
    log_info("鉴权成功，开始检查待上传音频")

    -- 检查音频是否已随工程编译进 /luadb/（未找到时提示放置方法）
    if not io.exists(REAL_AUDIO_PATH) then
        log_warn("未找到待上传音频:", REAL_AUDIO_PATH)
        log_warn("请将音频命名为 test.mp3 放入工程编译目录（与 main.lua 同级）后重新编译烧录")
        return
    end

    log_info("开始上传真实音频，设备路径:", REAL_AUDIO_PATH, "平台文件名:", REAL_AUDIO_NAME)
    local up_ok, up_err = excloud.upload_audio(REAL_AUDIO_PATH, REAL_AUDIO_NAME)
    if not up_ok then
        log_warn("上传真实音频未执行:", up_err)
        return
    end
    log_info("真实音频上传已触发，结果将通过单文件上传回调反馈")
end

-- 启动日志记录任务、（可选的）自动上传任务、真实图片上传任务与真实音频上传任务
sys.taskInit(log_demo_task)
sys.taskInit(auto_upload_task)
sys.taskInit(upload_real_image_task)
sys.taskInit(upload_real_audio_task)

-- 导出本模块
return M
