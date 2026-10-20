--[[
@module  scan_code
@summary Air1601/Air1602/Air8601 + AirCAMERA_1034 USB摄像头 扫码（二维码/条形码识别）应用模块
@version 1.0
@date    2026.09.24
@usage
本demo主要使用 Air1601/Air1602/Air8601 + AirCAMERA_1034 USB摄像头（标准UVC接口）完成以下功能：
1、给USB摄像头供电（引脚由 board_config 根据 main.lua 中的 BOARD 型号自动解析）；
2、初始化USB摄像头，采集分辨率使用 640x480（扫码分辨率越低，解码越快、内存占用越小）；
3、注册 camera 的 "scanned" 事件回调，进入扫码模式；
4、camera.start 后摄像头持续采集并解码，每识别成功一次就在回调中拿到解码字符串；
5、解码结果打印到日志（可自行改成UART输出、网络上传、控制外设等）；
6、支持摄像头热插拔：拔出后停止扫码，重新插入后自动恢复扫码。

需要的硬件：开发板 + AirCAMERA_1034（USB摄像头）；
不需要网络、不需要LCD、不需要 AirCAMERA_1034 的人脸识别模组（本demo只用到USB摄像头部分）。

板型适配（摄像头供电引脚）：
- Air1601_V1.1                = GPIO12（5V_EN）
- Air1601_V1.2 / Air1602_V1.2 = GPIO58（VC_EN）
- Air8601 / Air8602           = GPIO73（UVC_EN）
引脚由 board_config 根据 main.lua 中的 BOARD 型号常量自动解析，本文件无需修改。

互斥关系：
- 本模块与 face_demo / photo_to_aircloud / audio_record 互斥，
  USB摄像头同一时刻只能被一个业务占用，main.lua 中一次只打开一个 require；
- 本模块不需要网络，因此不要打开 require "netdrv_device"。

本文件没有对外接口，直接在main.lua中 require "scan_code" 即可加载运行。
]]

-- 加载板型配置（必须在所有 GPIO 操作之前 require）
local board_config = require "board_config"

local TAG = "scan_code"

-- ==================== 用户可调参数 ====================
local SCAN_WIDTH    = 640    -- 扫码采集宽度（建议640；可选 640x480 / 800x480 / 864x480 / 1280x720）
local SCAN_HEIGHT   = 480    -- 扫码采集高度
local USB_PORT      = 1      -- USB摄像头端口号，没有USB HUB时固定为1
local CAM_READY_MS  = 3000   -- 摄像头供电后等待上电稳定 + USB枚举的时间（毫秒）
local RETRY_MS      = 5000   -- 摄像头未就绪或扫码异常时的重试间隔（毫秒）
local DUP_FILTER_MS = 2000   -- 同一个码连续重复上报的去重时间（毫秒）
local REPORT_UART   = false  -- true：把扫码结果通过串口输出，便于对接MCU/上位机
local UART_ID       = 1      -- REPORT_UART = true 时使用的串口
local UART_BAUD     = 115200 -- 串口波特率

-- ==================== 运行状态 ====================
local cam_id                  -- camera.init 返回的摄像头ID（USB摄像头即其应用ID）
local cam_ready = false       -- 摄像头是否已初始化成功
local scanning  = false       -- 是否处于扫码中
local last_code, last_code_ms -- 上一次扫码结果与时间（用于去重）

-- USB事件回调函数
-- 作用：监听USB摄像头的接入和拔出
local function usb_cb(usb_id, class, app_id, event, param1, param2, param3)
    if class ~= usb.CAMERA then
        return
    end
    if event == usb.EV_CONNECT then
        log.info(TAG, "usb摄像头已接入，app id", app_id, "hub端口", param2)
    elseif event == usb.EV_DISCONNECT then
        log.warn(TAG, "usb摄像头已拔出，app id", app_id)
        scanning = false
        -- 通知扫码任务结束当前会话，等待重新接入后重新初始化
        sys.publish("SCAN_CAM_DISCONNECTED")
    end
end

-- 扫码结果处理函数
-- 作用：去重后打印结果，并支持UART输出/消息发布，业务层可自行改为其他处理方式
local function report_code(str)
    local now = mcu.ticks()
    -- 同一个码可能会被连续识别多次，这里做一次去重，避免日志刷屏
    if str == last_code and last_code_ms and (now - last_code_ms) < DUP_FILTER_MS then
        return
    end
    last_code, last_code_ms = str, now

    log.info(TAG, "==============================")
    log.info(TAG, "扫码成功:", str, "长度:", #str)
    log.info(TAG, "==============================")

    -- 需要对接上位机/MCU时，把文件顶部的 REPORT_UART 置为 true 即可
    if REPORT_UART then
        uart.write(UART_ID, str .. "\r\n")
    end

    -- 其他业务模块可以订阅这个主题做二次处理：sys.subscribe("SCAN_RESULT", function(code) end)
    sys.publish("SCAN_RESULT", str)
end

-- 摄像头事件回调函数
-- 参数str的三种类型（camera核心库定义）：
--   string ：扫码模式下识别成功一次的解码结果
--   false  ：摄像头没有正常工作
--   number ：拍照结果的字节长度（本demo是扫码模式，用不到）
local function camera_cb(id, str)
    local tp = type(str)
    if tp == "string" then
        report_code(str)
    elseif str == false then
        log.error(TAG, "摄像头没有数据，请检查摄像头接线和供电")
    else
        log.info(TAG, "摄像头数据长度", str)
    end
end

-- 摄像头初始化函数
-- 流程：USB供电 → 等待上电稳定和USB枚举 → camera.init → 注册 "scanned" 回调
local function camera_init()
    -- USB摄像头供电（供电引脚随 main.lua 中的 BOARD 型号自动变化）
    board_config.power_on_camera()

    -- 等待供电稳定 + USB枚举完成；供电后立即 camera.init 可能因摄像头未就绪而失败
    sys.wait(CAM_READY_MS)

    -- 640x480：常规二维码/条形码都够用，分辨率越低解码越快、内存占用越小
    local param = {
        id = camera.USB,             -- USB摄像头（标准UVC）
        sensor_width = SCAN_WIDTH,   -- 采集宽度
        sensor_height = SCAN_HEIGHT, -- 采集高度
        usb_port = USB_PORT          -- USB端口号
    }
    cam_id = camera.init(param)
    if not cam_id then
        log.error(TAG, "摄像头初始化失败，请检查摄像头接线、供电以及分辨率是否被摄像头支持")
        return false
    end
    log.info(TAG, "摄像头初始化成功，分辨率", SCAN_WIDTH .. "x" .. SCAN_HEIGHT, "camera id", cam_id)

    -- 注册摄像头事件回调：扫码结果通过 "scanned" 事件上报
    -- 注意：与 "usb_raw"（原始图像流）回调是互斥的，扫码场景只注册 scanned
    camera.on(cam_id, "scanned", camera_cb)

    cam_ready = true
    return true
end

-- 单次扫码会话
-- 摄像头就绪后调用 camera.start 启动扫码，之后摄像头持续采集并解码，
-- 每识别成功一次都会进入 camera_cb；本函数只负责等待"摄像头被拔出"等结束条件
local function scan_session()
    if not camera.start(cam_id) then
        log.error(TAG, "启动扫码失败")
        return
    end
    scanning = true
    log.info(TAG, "扫码已启动，请将二维码/条形码对准摄像头...")

    while true do
        -- 正常情况下会一直扫码，直到摄像头被拔出
        if sys.waitUntil("SCAN_CAM_DISCONNECTED", 60000) then
            return
        end
        -- 每分钟打印一次内存信息，便于长时间运行观察
        log.info(TAG, "扫码运行中", scanning and "扫码中" or "已停止",
            "sys ram", rtos.meminfo("sys"), "lua ram", rtos.meminfo("lua"))
        collectgarbage()
    end
end

-- 扫码主任务
-- 作用：摄像头未就绪时循环重试初始化；就绪后进入扫码会话；摄像头拔出后自动重新初始化
local function scan_task()
    -- 注册USB事件回调（摄像头接入/拔出），只注册一次，用于把控插拔状态
    usb.on(0, usb_cb)

    -- 需要把扫码结果输出到串口时，初始化串口
    if REPORT_UART then
        uart.setup(UART_ID, UART_BAUD, 8, 1)
        log.info(TAG, "扫码结果将通过UART" .. UART_ID .. "输出，波特率", UART_BAUD)
    end

    while true do
        -- 1、等待摄像头上电并初始化成功，失败则间隔重试
        while not cam_ready do
            if not camera_init() then
                log.warn(TAG, RETRY_MS, "ms 后重新初始化摄像头")
                sys.wait(RETRY_MS)
            end
        end

        -- 2、进入扫码会话（异常返回/摄像头拔出后回到这里重新初始化）
        scan_session()

        -- 3、释放资源，等待摄像头重新接入
        if cam_id then
            pcall(camera.stop, cam_id)
            pcall(camera.close, cam_id)
        end
        cam_id, cam_ready, scanning = nil, false, false
        last_code, last_code_ms = nil, nil
        log.info(TAG, "本次扫码会话结束，", RETRY_MS, "ms 后重新初始化摄像头")
        sys.wait(RETRY_MS)
    end
end

--[[
补充说明（一般用不到，出现异常时可参考）：

1、扫码回调的注册对象统一使用 camera.init 的返回值 cam_id（官方推荐用法）。
   个别固件上USB摄像头的id语义有差异，如果日志里已经有"摄像头已接入"但一直不出扫码结果，
   可尝试把 camera.on(cam_id, ...) / camera.start(cam_id) 换成 camera.on(camera.USB, ...) / camera.start(camera.USB) 再验证。

2、如果需要手工初始化USB主机模式（参考 olddemo/demo/camera/usb_cam_mcu），
   可以把上面 camera_init() 里的 "sys.wait(CAM_READY_MS)" 之前替换为：

       usb.on(0, usb_cb)             -- 注册USB事件回调
       pm.power(pm.USB, false)       -- 确保USB外设掉电
       usb.mode(0, usb.HOST)         -- USB设置成主机模式
       pm.power(pm.USB, true)        -- USB上电，开始枚举摄像头
       sys.wait(CAM_READY_MS)        -- 等待枚举完成

   注意：该方式与 camera.init 内部的USB初始化是两套流程，二选一即可，不要重复执行。

3、扫码失败常见原因：
   - 摄像头供电未打开（board_config.power_on_camera() 未执行或 BOARD 型号选错）；
   - 采集分辨率不被摄像头支持（可改成 1280x720 再试）；
   - 环境太暗、码太小或离摄像头太近，640x480 下建议距离 10~20cm。
]]

-- 创建扫码任务
sys.taskInit(scan_task)
