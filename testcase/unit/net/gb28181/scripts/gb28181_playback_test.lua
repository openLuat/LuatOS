--[[
历史回放的 Lua 层单测（里程碑 M6.2 / M6.3）。

分三块，都由"只测不依赖真实平台与录像文件"的部分组成：

  1. **录像列表归一化** —— RecordInfo 应答回给平台的字符串，与回放定位用的
     Unix 秒，必须**同源**。这是回放链路里最容易静默出错的一处：两边各算各的
     会让平台按它看到的时间点下 t=，设备却定位到别处，现象是"回放起点不对"，
     而两边的代码单看都没问题。
  2. **MANSRTSP 绑定** —— 素材取自真实平台 WVP-Pro 源码发出的报文原文
     （与 C 层 tests/test_mansrtsp.c 同源，这样 Lua 侧也能验证"绑定没把
     C 层用错"）。
  3. **回放模块的状态契约** —— 没有会话时各接口不能抛错（现场用 stats()
     自检是常规动作，它若会崩就等于把设备打重启）。

完整链路（真的读录像文件、真的推 RTP、暂停/拖动真的改变流）属联调，
见 tests/tools/playback_device/main.lua + gb_platform_invite.py --playback。
]]

local client   = require("exgb28181client")
local playback = require("exgb28181playback")

local ok_gb, mod_gb = pcall(require, "gb28181")
local gb = ok_gb and mod_gb or rawget(_G, "gb28181")

local t = {}

local function base_opts(extra)
    local o = {
        server_addr = "127.0.0.1",
        server_port = 1,             -- 无人监听：能起 socket 但注册不上
        domain      = "3502000000",
        device_id   = "35020000001320000001",
        password    = "test_password",
        transport   = "udp",
        local_port  = 5098,
        keepalive   = 0,
        expires     = 300,
    }
    for k, v in pairs(extra or {}) do o[k] = v end
    return o
end

-- 素材的录制起点：2026-09-17 00:00:00（本地时区）
local DAY0 = os.time({ year = 2026, month = 9, day = 17, hour = 0, min = 0, sec = 0 })

local ONE_RECORD = {
    device_id  = "35020000001320000001",
    name       = "rec1",
    file_path  = "/sd/rec/1.mp4",
    address    = "127.0.0.1",
    start_time = "2026-09-17T00:00:00",
    end_time   = "2026-09-17T00:05:00",
}

-- ------------------------------------------------------------------
-- 1. 录像列表归一化
-- ------------------------------------------------------------------

--[[ 归一化后：路径、起止 Unix、epoch 都要齐备，且 epoch 必须等于报给平台的起点 ]]
function t.test_records_normalized_for_playback()
    client.stop()
    assert(client.start(base_opts({ records = { ONE_RECORD } })))
    local recs = client.records()
    assert(#recs == 1, "应有一条录像")
    local r = recs[1]
    assert(r.playable == true, "时间可解析的录像应标为可播")
    assert(r.path == "/sd/rec/1.mp4", "本机路径取自 file_path，实际 " .. tostring(r.path))
    assert(r.start_unix == DAY0, "起点应换算成 Unix 秒，实际 " .. tostring(r.start_unix))
    assert(r.end_unix == DAY0 + 300, "终点应换算成 Unix 秒")
    -- 这条是关键：epoch 与报给平台的 StartTime 同源，否则平台下 t= 时对不上
    assert(r.epoch == r.start_unix, "epoch 必须与 start_unix 同源")
    -- 回给平台的字符串仍是字母 T 的形态（不能退化成空格）
    assert(r.start_time == "2026-09-17T00:00:00", "实际 " .. tostring(r.start_time))
    assert(r.end_time == "2026-09-17T00:05:00", "实际 " .. tostring(r.end_time))
    client.stop()
end

--[[ 时间解析不出来时：原样保留字符串上报，但标成不可播（不编造时刻） ]]
function t.test_records_unparsable_time_is_reported_but_not_playable()
    client.stop()
    local bad = {}
    for k, v in pairs(ONE_RECORD) do bad[k] = v end
    bad.start_time = "2026/09/17 00:00:00"      -- 分隔符不对
    bad.end_time   = "2026-09-17 00:05:00"      -- 空格分隔（这个倒是被容忍）
    assert(client.start(base_opts({ records = { bad } })))
    local r = client.records()[1]
    assert(r ~= nil, "条目仍要出现在列表里（设备确实有这段录像）")
    assert(r.playable == false, "解析不出来的段必须标为不可播")
    assert(r.start_time == "2026/09/17 00:00:00", "原字符串要原样保留给平台")
    client.stop()
end

--[[ 起点晚于终点的时间段不是有效录像 ]]
function t.test_records_reversed_range_is_not_playable()
    client.stop()
    local bad = {}
    for k, v in pairs(ONE_RECORD) do bad[k] = v end
    bad.start_time = "2026-09-17T01:00:00"
    bad.end_time   = "2026-09-17T00:00:00"
    assert(client.start(base_opts({ records = { bad } })))
    assert(client.records()[1].playable == false, "起止颠倒的段不可播")
    client.stop()
end

--[[ 没配录像时返回空表而不是 nil：调用方可以无条件写 #client.records() ]]
function t.test_records_empty_without_config()
    client.stop()
    assert(client.start(base_opts()))
    local recs = client.records()
    assert(type(recs) == "table", "应返回表")
    assert(#recs == 0, "未配置时应为空")
    client.stop()
end

-- ------------------------------------------------------------------
-- 2. MANSRTSP 绑定（素材 = 真实平台发出的原文）
-- ------------------------------------------------------------------

function t.test_mansrtsp_binding_parses_real_platform_commands()
    assert(gb ~= nil, "需要 C 层 gb28181")
    assert(type(gb.mansrtsp_parse) == "function", "固件的绑定太旧，没有 mansrtsp_parse")

    -- 暂停
    local m = gb.mansrtsp_parse("PAUSE RTSP/1.0\r\nCSeq: 123456789\r\nPauseTime: now\r\n\r\n")
    assert(m ~= nil, "应能解析 PAUSE")
    assert(m.method == gb.MANSRTSP_PAUSE, "方法应为 PAUSE")
    assert(m.cseq == 123456789, "应取 body 里的 CSeq")

    -- 继续：npt=now- **不能**被当成 0 秒
    m = gb.mansrtsp_parse("PLAY RTSP/1.0\r\nCSeq: 234567891\r\nRange: npt=now-\r\n\r\n")
    assert(m.method == gb.MANSRTSP_PLAY)
    assert(m.npt_kind == gb.NPT_NOW, "npt=now- 应解析为 NPT_NOW 而不是 NPT_POS")
    assert(m.npt_sec == nil, "now 形态不该给出秒数")

    -- 拖动
    m = gb.mansrtsp_parse("PLAY RTSP/1.0\r\nCSeq: 3\r\nRange: npt=125-\r\n\r\n")
    assert(m.npt_kind == gb.NPT_POS, "npt=125- 应解析为定位")
    assert(m.npt_sec == 125, "偏移应为 125 秒，实际 " .. tostring(m.npt_sec))

    -- 倍速
    m = gb.mansrtsp_parse("PLAY RTSP/1.0\r\nCSeq: 4\r\nScale: 2.000000\r\n\r\n")
    assert(m.has_scale == true and m.scale > 1.99 and m.scale < 2.01, "应解析出倍速")

    -- 不是 MANSRTSP 的内容
    assert(gb.mansrtsp_parse("hello") == nil, "非 MANSRTSP 应返回 nil")
end

function t.test_mansrtsp_response_binding()
    assert(gb ~= nil)
    local body = gb.mansrtsp_response(200, "OK", 123456789)
    assert(body == "RTSP/1.0 200 OK\r\nCSeq: 123456789\r\n\r\n",
           "应答原文不对: " .. tostring(body))
    -- 请求没给 CSeq 时不该编一个
    assert(gb.mansrtsp_response(200, "OK", -1) == "RTSP/1.0 200 OK\r\n\r\n")
    -- 不支持的命令
    local un = gb.mansrtsp_response(501, "Not Implemented", 7)
    assert(string.find(un, "501", 1, true) ~= nil)
end

-- ------------------------------------------------------------------
-- 3. 回放模块的状态契约
-- ------------------------------------------------------------------

--[[ 没有会话时各接口都不能抛错（stats() 是现场自检的常规动作） ]]
function t.test_playback_api_is_safe_without_session()
    local fake = { call_id = "nobody@test", is_playback = true }
    assert(playback.pause(fake) == false)
    assert(playback.resume(fake) == false)
    local ok, err = playback.seek(fake, 1)
    assert(ok == false and type(err) == "string")
    assert(playback.stats(fake) == nil)
    assert(type(playback.stats()) == "table", "无参应返回空表而不是 nil")
    assert(playback.stop(fake) == true, "停止不存在的会话应当是幂等的成功")

    -- 参数非法
    assert(playback.seek(fake, -1) == false, "负偏移应被拒")
    assert(playback.seek(fake, "abc") == false, "非数字偏移应被拒")
end

--[[ setup 幂等：重复注册不该报错，也不该把回调叠起来 ]]
function t.test_playback_setup_is_idempotent()
    assert(playback.setup() == true)
    assert(playback.setup() == true)
    assert(client.on_playback(function() end) == true, "应能注册回放钩子")
    assert(client.on_playback("not a function") == false, "非函数应被拒")
    -- 还回去，免得影响其它用例
    assert(client.on_playback(playback.on_session) == true)
end

return t
