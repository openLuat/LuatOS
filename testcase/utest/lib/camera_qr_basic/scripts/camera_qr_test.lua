local camera_qr_test = {}

local decode_suite = {}

local QR_PAYLOAD = "https://luatos.com/test"
local QR_FIXTURE = "/luadb/qr_test.jpg"

local function qr_decode_available()
    if camera and type(camera.utest_qr_decode) == "function" then
        return true
    end
    log.warn("camera_qr", "camera.utest_qr_decode 不可用(未启用 camera scan/Zxing)，跳过本用例")
    return false
end

local function read_qr_frame()
    local player = videoplayer.open(QR_FIXTURE)
    assert(player, "videoplayer.open(" .. QR_FIXTURE .. ") 失败")
    local frame, err = videoplayer.read_frame(player)
    videoplayer.close(player)
    assert(frame, "videoplayer.read_frame 失败: " .. tostring(err))
    assert(frame.width > 0 and frame.height > 0, "帧尺寸非法")
    return frame
end

function decode_suite.test_decode_qr_from_jpeg()
    if not qr_decode_available() then return end
    local frame = read_qr_frame()
    local str = camera.utest_qr_decode(frame.data, frame.width, frame.height)
    assert(str == QR_PAYLOAD, "解码结果不匹配, 期望[" .. QR_PAYLOAD .. "] 实际[" .. tostring(str) .. "]")
end

function decode_suite.test_decode_qr_with_format_mask()
    if not qr_decode_available() then return end
    local frame = read_qr_frame()
    -- 只允许 1D 码制时, QR 不应被解出
    local str = camera.utest_qr_decode(frame.data, frame.width, frame.height, 0, camera.SCAN_FMT_1D)
    assert(str == nil, "仅 1D 码制不应解出 QR, 实际[" .. tostring(str) .. "]")
    -- 明确允许 QR 码制时应正常解出
    str = camera.utest_qr_decode(frame.data, frame.width, frame.height, 0, camera.SCAN_FMT_QR)
    assert(str == QR_PAYLOAD, "QR 码制解码失败, 实际[" .. tostring(str) .. "]")
end

function decode_suite.test_decode_invalid_args()
    if not qr_decode_available() then return end
    assert(camera.utest_qr_decode("short", 64, 64) == nil, "数据长度不足应返回 nil")
    assert(camera.utest_qr_decode(string.rep("\0", 64 * 64 * 2), 0, 64) == nil, "宽度非法应返回 nil")
end

camera_qr_test.decode_suite = decode_suite

return camera_qr_test
