--[[
@module exfacecam
@summary AirCAMERA_1034摄像头人脸识别模组扩展库
@version 1.0
@date    2026.07.30
@author  王城钧
@usage
    exfacecam 扩展库用于 AirCAMERA_1034 摄像头人脸识别模组通信管理，通过 UART 串口（115200/8N1）与模组交互，同时支持 USB 摄像头初始化，实现人脸录入、验证、用户管理等功能。

    注意：exfacecam.lua 适用的产品范围
        Air1601系列、Air1602系列：支持 USB 摄像头 + AirCAMERA_1034 摄像头人脸识别模组

    使用 exfacecam 库的基本流程
    1、初始化：初始化USB摄像头与人脸模组，打开UART并按需初始化摄像头
    2、人脸录入：录入用户人脸（阻塞，需在task中调用）
    3、人脸验证：比对当前人脸与已录入用户（阻塞，需在task中调用）
    4、用户管理：查询/删除/清空已注册用户
    5、关闭：关闭人脸模组UART与摄像头
]]

-- 版本更新说明
-- 版本号：202607301800
-- 1、更新时间：2026-07-30 18:00
-- 2、更新内容
--    初始版本发布，从 excamera 库拆分独立，提供 open/close/register/verify/list/query/delete/clear/status/reset/get_version/version 接口
--    新增：error code 常量导出

local TAG = "exfacecam"

-- 协议常量
local MID_REPLY       = 0x00
local MID_NOTE        = 0x01
local MID_GETSTATUS   = 0x11
local MID_VERIFY      = 0x12
local MID_ENROLL_SINGLE = 0x1D
local MID_DELUSER     = 0x20
local MID_DELALL      = 0x21
local MID_GETUSERINFO = 0x22
local MID_GETALLUSERID = 0x24
local MID_GETVERSION  = 0x30
local MID_RESET       = 0x10

local NID_READY       = 0x00
local NID_FACE_STATE  = 0x01
local NID_OTA_DONE    = 0x03
local FACE_DIR_MIDDLE = 0x01

-- 内部状态 
local uart_id = nil
local rx_buf = ""
local reply_map = {}
local note_cb = nil

local cam_inited = false
local cam_id = nil
local cam_param_backup = nil

--  内部: 构建协议帧 
local function build_frame(mid, data)
    data = data or ""
    local sz = #data
    local f = string.char(0xEF, 0xAA, mid, sz >> 8, sz & 0xFF) .. data
    local cs = 0
    for i = 3, #f do cs = cs ~ f:byte(i) end
    return f .. string.char(cs)
end

-- 内部: 解析收到的协议帧 
local function parse_frames(s)
    rx_buf = rx_buf .. (s or "")
    while #rx_buf >= 6 do
        local pos = rx_buf:find("\xEF\xAA", 1, true)
        if not pos then rx_buf = ""; return end
        if pos > 1 then rx_buf = rx_buf:sub(pos) end
        local size = (rx_buf:byte(4) << 8) | rx_buf:byte(5)
        local total = 6 + size
        if #rx_buf < total then return end
        local frame = rx_buf:sub(3, total)
        rx_buf = rx_buf:sub(total + 1)

        -- XOR 校验
        local cs = 0
        for i = 1, #frame - 1 do cs = cs ~ frame:byte(i) end
        if cs ~= frame:byte(#frame) then
            log.warn(TAG, "cs err")
        else
            local mid = frame:byte(1)
            local d = size > 0 and frame:sub(4, 3 + size) or ""
            if mid == MID_REPLY and #d >= 2 then
                reply_map[d:byte(1)] = {r = d:byte(2), d = #d > 2 and d:sub(3) or ""}
                sys.publish("FF_" .. d:byte(1))
            elseif mid == MID_NOTE and #d >= 1 then
                local nid = d:byte(1)
                if nid == NID_READY then
                    sys.publish("FF_READY")
                    log.info(TAG, "ready")
                elseif nid == NID_FACE_STATE and note_cb and #d >= 17 then
                    -- Data 区 int16_t 为 Little-Endian
                    local function s16(v) return v > 32767 and v - 65536 or v end
                    local function i16(i) return s16(d:byte(i) | (d:byte(i + 1) << 8)) end
                    pcall(note_cb, i16(2), i16(4), i16(6), i16(8), i16(10), i16(12), i16(14), i16(16))
                elseif nid == NID_OTA_DONE then
                    log.info(TAG, "ota done")
                end
            end
        end
    end
end

-- 内部: 发送指令并等待回复
local function send_cmd(mid, data, timeout)
    timeout = timeout or 5000
    reply_map[mid] = nil
    uart.write(uart_id, build_frame(mid, data))
    if sys.waitUntil("FF_" .. mid, timeout) then
        local r = reply_map[mid]
        if r then return true, r.r, r.d end
    end
    log.warn(TAG, "cmd timeout 0x" .. string.format("%02X", mid))
    return false, "timeout"
end

-- 错误码常量
local EXFACECAM_VERSION = "202607291800"

local exfacecam = {}

exfacecam.MR_SUCCESS            = 0
exfacecam.MR_REJECTED           = 1
exfacecam.MR_ABORTED            = 2
exfacecam.MR_FAILED4_CAMERA     = 4
exfacecam.MR_FAILED4_UNKNOWNREASON = 5
exfacecam.MR_FAILED4_INVALIDPARAM   = 6
exfacecam.MR_FAILED4_NOMEMORY       = 7
exfacecam.MR_FAILED4_UNKNOWNUSER    = 8
exfacecam.MR_FAILED4_MAXUSER        = 9
exfacecam.MR_FAILED4_FACEENROLLED   = 10
exfacecam.MR_FAILED4_LIVENESSCHECK  = 12
exfacecam.MR_FAILED4_TIMEOUT        = 13
exfacecam.MR_FAILED4_AUTHORIZATION  = 14

--[[
打开人脸模组和摄像头
@param param table 配置表
  face_uart (number, 必选) 人脸模组 UART 编号
  face_rst  (number, 可选) 人脸模组复位 GPIO
  id        (number, 可选) camera.USB / camera.DVP
  sensor_width  (number) 摄像头像素宽度
  sensor_height (number) 摄像头像素高度
  usb_port  (number) USB 端口号
@return boolean 初始化结果
]]
function exfacecam.open(param)
    if not param or not param.face_uart then
        log.error(TAG, "face_uart required")
        return false
    end

    -- 复位人脸模组
    if param.face_rst then
        gpio.setup(param.face_rst, 0)
        sys.wait(100)
        gpio.setup(param.face_rst, 1)
        sys.wait(500)
    end

    -- 打开 UART
    uart_id = param.face_uart
    rx_buf = ""
    reply_map = {}

    uart.setup(uart_id, 115200, 8, uart.PAR_NONE, uart.STOP_1)
    sys.wait(300)
    log.info(TAG, "uart" .. uart_id .. " @115200 8N1")

    -- 事件驱动接收
    local function uart_recv_cb(_, len)
        if not uart_id then return end
        local data = nil
        if type(len) == "number" and len > 0 then
            data = uart.read(uart_id, len)
        elseif type(len) == "string" then
            data = len
        end
        if data and #data > 0 then
            parse_frames(data)
        end
    end
    uart.on(uart_id, "recv", uart_recv_cb)

    -- 探测模组
    log.info(TAG, "probing...")
    uart.write(uart_id, build_frame(MID_GETSTATUS, nil))
    if sys.waitUntil("FF_" .. MID_GETSTATUS, 2000) then
        log.info(TAG, "probe ok")
    else
        log.info(TAG, "waiting NID_READY...")
        if not sys.waitUntil("FF_READY", 5000) then
            uart.write(uart_id, build_frame(MID_GETSTATUS, nil))
            if not sys.waitUntil("FF_" .. MID_GETSTATUS, 2000) then
                log.error(TAG, "no response")
                uart.on(uart_id, "recv", nil)
                uart.close(uart_id)
                uart_id = nil
                return false
            end
        end
    end
    log.info(TAG, "face module online")

    -- 初始化 USB 摄像头（可选）
    if param.id == camera.USB then
        if camera.init(param) then
            cam_inited = true
            cam_id = param.id
            cam_param_backup = param
            log.info(TAG, "camera init ok")
        else
            log.warn(TAG, "camera init fail, face only")
        end
    end

    return true
end

--[[
关闭人脸模组和摄像头
]]
function exfacecam.close()
    if uart_id then
        uart.on(uart_id, "recv", nil)
        uart.close(uart_id)
        uart_id = nil
        rx_buf = ""
        reply_map = {}
        note_cb = nil
    end
    if cam_inited and cam_id then
        pcall(camera.close, cam_id)
        cam_inited = false
        cam_id = nil
        cam_param_backup = nil
    end
    log.info(TAG, "closed")
end

--[[
录入人脸（单帧）
@param opt table {name, admin, timeout, on_state}
  name    (string, 必选) 用户姓名，最长 32 字节
  admin   (number, 可选) 1=管理员，0=普通用户，默认 0
  timeout (number, 可选) 录入超时(秒)，默认 15
  on_state (function, 可选) 回调 function(state, left, top, right, bottom, yaw, pitch, roll)
           state: 0=正常, 1=无人脸, 2=偏上, 3=偏下, 4=偏左, 5=偏右, 6=太远, 7=太近,
                  8=眉毛遮挡, 9=眼睛遮挡, 10=面部遮挡, 11=角度异常
@return boolean 录入结果
@return number 成功返回 user_id，失败返回错误码(exfacecam.MR_*)
]]
function exfacecam.register(opt)
    if not uart_id then log.error(TAG, "not open"); return false end
    opt = opt or {}
    local nm = opt.name or ""
    if #nm > 32 then nm = nm:sub(1, 32) end
    local d = string.char(opt.admin and 1 or 0) ..
        nm .. string.rep('\x00', 32 - #nm) ..
        string.char(FACE_DIR_MIDDLE, opt.timeout or 15)
    note_cb = opt.on_state
    local ok, r = send_cmd(MID_ENROLL_SINGLE, d, (opt.timeout or 15) * 1000 + 8000)
    note_cb = nil
    if ok and r == exfacecam.MR_SUCCESS then
        local rp = reply_map[MID_ENROLL_SINGLE]
        if rp and #rp.d >= 2 then return true, (rp.d:byte(1) << 8) | rp.d:byte(2) end
        return true
    end
    return false, r
end

--[[
人脸验证
@param opt table {timeout, on_state}
  timeout (number, 可选) 验证超时(秒)，默认 30
  on_state (function, 可选) 回调，同 register
@return boolean 验证结果
@return table/number 成功返回 {user_id, name, admin, unlock_status}，失败返回 error_code
]]
function exfacecam.verify(opt)
    if not uart_id then log.error(TAG, "not open"); return false end
    opt = opt or {}
    local d = string.char(0, opt.timeout or 30, 0)
    note_cb = opt.on_state
    local ok, r = send_cmd(MID_VERIFY, d, (opt.timeout or 30) * 1000 + 8000)
    note_cb = nil
    if ok and r == exfacecam.MR_SUCCESS then
        local rp = reply_map[MID_VERIFY]
        if rp and #rp.d >= 36 then
            return true, {
                user_id = (rp.d:byte(1) << 8) | rp.d:byte(2),
                name = rp.d:sub(3, 34):match("^[^\0]*") or "",
                admin = rp.d:byte(35),
                unlock_status = rp.d:byte(36),
            }
        end
        return true, {}
    end
    return false, r
end

--[[
查询所有已注册用户
@return boolean 查询结果
@return number 用户数量
@return table 用户 ID 数组
]]
function exfacecam.list()
    if not uart_id then return false end
    local ok, r = send_cmd(MID_GETALLUSERID, "\x00", 2000)
    if ok and r == exfacecam.MR_SUCCESS then
        local rp = reply_map[MID_GETALLUSERID]
        if rp and #rp.d >= 1 then
            local c = rp.d:byte(1)
            local ids = {}
            for i = 1, c do
                ids[i] = (rp.d:byte(2 + (i - 1) * 2) << 8) | rp.d:byte(3 + (i - 1) * 2)
            end
            return true, c, ids
        end
        return true, 0, {}
    end
    return false, r
end

--[[
查询指定用户信息
@param uid number 用户 ID
@return boolean 查询结果
@return table {name, admin}
]]
function exfacecam.query(uid)
    if not uart_id then return false end
    local ok, r = send_cmd(MID_GETUSERINFO, string.char((uid >> 8) & 0xFF, uid & 0xFF), 2000)
    if ok and r == exfacecam.MR_SUCCESS then
        local rp = reply_map[MID_GETUSERINFO]
        if rp and #rp.d >= 35 then
            return true, {
                name = rp.d:sub(3, 34):match("^[^\0]*") or "",
                admin = rp.d:byte(35),
            }
        end
    end
    return false, r
end

--[[
删除指定用户
@param uid number 用户 ID
@return boolean 删除结果
]]
function exfacecam.delete(uid)
    if not uart_id then return false end
    local ok, r = send_cmd(MID_DELUSER, string.char((uid >> 8) & 0xFF, uid & 0xFF, 0), 3000)
    return ok and r == exfacecam.MR_SUCCESS
end

--[[
删除所有已注册用户
@return boolean 删除结果
]]
function exfacecam.clear()
    if not uart_id then return false end
    local ok, r = send_cmd(MID_DELALL, "\x00", 5000)
    return ok and r == exfacecam.MR_SUCCESS
end

--[[
复位人脸模组
@return boolean 复位结果
]]
function exfacecam.reset()
    if not uart_id then return false end
    local ok, r = send_cmd(MID_RESET, nil, 1000)
    return ok and r == exfacecam.MR_SUCCESS
end

--[[
获取模组固件版本
@return boolean 查询结果
@return string 固件版本
]]
function exfacecam.get_version()
    if not uart_id then return false end
    local ok, r = send_cmd(MID_GETVERSION, nil, 2000)
    if ok and r == exfacecam.MR_SUCCESS then
        local rp = reply_map[MID_GETVERSION]
        if rp then return true, rp.d end
    end
    return false
end

--[[
获取库版本号
@return string 年月日时分，例如： "202606300102"
]]
function exfacecam.version()
    return "202607311200"
end

return exfacecam
