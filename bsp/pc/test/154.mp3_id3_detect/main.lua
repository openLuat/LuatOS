-- 验证 mp3 ID3v2 跳过偏移修复 (luat_audio_codec_port_mp3.c)
-- 复刻 luat_audio_get_play_info_from_file 的探测循环, 检查:
-- 1. 所有样本都能识别出采样率
-- 2. 跳转位置 == 10 + ID3 tag size (即第一帧帧头处, 字节为 0xFF)
-- 修复前 bug: 偏移写成 tag_size + 12, 丢第一帧导致位流水库解码失败
PROJECT = "mp3_id3_detect"
VERSION = "1.0.0"

local sys = require("sys")

local MP3 = audio_v2.DATA_CODEC_TYPE_MP3

-- 与 C 侧 luat_audio_get_play_info_from_file 相同的探测流程
local function detect(data)
    local pos = 0
    local d = data:sub(1, 44)
    local ok, next_pos, need_len, hz = audio_v2.get_play_info(d, MP3, pos)
    if not ok then return nil, "first call error" end
    pos = next_pos
    local retry = 0
    while hz == 0 and retry < 5 do
        d = data:sub(pos + 1, pos + need_len)
        if #d < need_len then return nil, "not enough data" end
        ok, next_pos, need_len, hz = audio_v2.get_play_info(d, MP3, pos)
        if not ok then return nil, "detect error" end
        pos = next_pos
        retry = retry + 1
    end
    if hz == 0 then return nil, "no sample rate after retries" end
    return hz, pos
end

-- 期望值: name -> {期望采样率}
-- 跳转位置期望值由文件自身的 ID3 头计算: 10 + synchsafe(size)
local cases = {
    {"ok_709328036721332224.mp3",  44100},
    {"bad_707422536488456192.mp3", 44100},
    {"bad_707422573452857344.mp3", 22050},
    {"bad_707422606994706432.mp3", 8000},
    {"bad_707422667254272000.mp3", 44100},
    {"bad_707422689563774976.mp3", 48000},
    {"bad_707422953351942144.mp3", 44100},
    {"bad_709301807028899840.mp3", 44100},
    {"bad_727439223266742272.mp3", 22050},
}

sys.taskInit(function()
    local pass, fail = 0, 0
    for _, case in ipairs(cases) do
        local name, expect_hz = case[1], case[2]
        local f = io.open("../../test/154.mp3_id3_detect/" .. name, "rb")
        if not f then
            log.error("test", name, "file not found")
            fail = fail + 1
        else
            local data = f:read("*a")
            f:close()
            local hz, pos = detect(data)
            -- 计算期望跳转位置
            local expect_pos = 0
            if data:sub(1, 3) == "ID3" then
                local b = {data:byte(7, 10)}
                expect_pos = 10 + ((b[1] & 0x7f) << 21) + ((b[2] & 0x7f) << 14) + ((b[3] & 0x7f) << 7) + (b[4] & 0x7f)
            end
            local at_pos = data:byte(pos + 1)
            if hz == expect_hz and pos == expect_pos and at_pos == 0xff then
                log.info("PASS", name, string.format("hz=%d pos=%d (expect %d), byte@pos=0x%02X", hz, pos, expect_pos, at_pos))
                pass = pass + 1
            else
                log.error("FAIL", name, string.format("hz=%d(expect %d) pos=%d(expect %d) byte@pos=0x%02X", hz or -1, expect_hz, pos or -1, expect_pos, at_pos or 0))
                fail = fail + 1
            end
        end
    end
    log.info("RESULT", string.format("pass=%d fail=%d", pass, fail))
    os.exit(fail == 0 and 0 or 1)
end)

sys.run()
