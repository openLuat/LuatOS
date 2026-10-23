--[[
GB28181 音频库的纯函数测试。

exgb28181audio 的 start/mic_start 依赖 voip/audio_v2 硬件路径，PC 模拟器上
无法覆盖；这里只测与硬件无关、但对外公开的部分：

  · G.711A 编解码（alaw_encode / pcm_to_alaw / alaw_to_pcm）
  · PCM 增益/钳位（pcm_gain）
  · 稳定 API 的存在与参数校验（不启动真实音频）
  · 裸流后端 exgb28181audio_raw 的可用性与参数拒绝（不建链）

裸流后端已不随 script/libs 发布（放在组件仓库 gb28181/tests/tools/）。
要跑那组用例，把该目录也加入脚本搜索路径；没带时整组自动跳过。

testrunner 用 pairs() 遍历，执行顺序不确定，每个用例自备状态。
]]

local ok, mod = pcall(require, "exgb28181audio")
local gba = ok and mod or rawget(_G, "exgb28181audio")

-- 裸 C stream 后端（PC/探针）：不依赖 voip，PC 上也能加载
local okr, modr = pcall(require, "exgb28181audio_raw")
local raw = okr and modr or rawget(_G, "exgb28181audio_raw")

local t = {}

local function pcm16(samples)
    local out = {}
    for _, v in ipairs(samples) do
        if v < 0 then v = v + 0x10000 end
        out[#out + 1] = string.char(v & 0xFF, (v >> 8) & 0xFF)
    end
    return table.concat(out)
end

local function samples_of(pcm)
    local out = {}
    for i = 1, #pcm - 1, 2 do
        local v = pcm:byte(i) | (pcm:byte(i + 1) << 8)
        if v >= 0x8000 then v = v - 0x10000 end
        out[#out + 1] = v
    end
    return out
end

function t.test_module_available()
    assert(gba ~= nil, "require exgb28181audio 失败")
    assert(type(gba.available) == "function")
    assert(type(gba.start) == "function")
    assert(type(gba.mic_start) == "function")
    assert(type(gba.stats) == "function")
end

function t.test_alaw_encode_zero_and_saturation()
    assert(gba.alaw_encode(0) == 0xD5, "A-law(0) 应为 0xD5")
    -- 超过 32635 的样本必须饱和，不能回绕
    assert(gba.alaw_encode(40000) == gba.alaw_encode(32635),
           "正饱和值应一致")
    assert(gba.alaw_encode(-40000) == gba.alaw_encode(-32635),
           "负饱和值应一致")
    -- 正负样本的符号位必须不同
    assert(gba.alaw_encode(1000) ~= gba.alaw_encode(-1000),
           "正负样本不能编码成同一字节")
end

function t.test_pcm_alaw_round_trip()
    local src = { 0, 1, -1, 100, -100, 1000, -1000, 8000, -8000, 30000, -30000 }
    local alaw = gba.pcm_to_alaw(pcm16(src))
    assert(#alaw == #src, "每个 16bit 样本应产生 1 字节 A-law")
    local dec = samples_of(gba.alaw_to_pcm(alaw))
    assert(#dec == #src, "解码样本数应一致")
    for i = 1, #src do
        local want, got = src[i], dec[i]
        -- A-law 有量化误差；符号必须一致，幅度允许 1/16 + 16 的偏差
        if want == 0 then
            assert(math.abs(got) <= 8, "0 附近解码偏差过大: " .. got)
        else
            assert((want > 0) == (got > 0),
                   "符号变化: " .. want .. " -> " .. got)
            local tol = math.max(16, math.abs(want) // 16)
            assert(math.abs(got - want) <= tol,
                   "量化偏差过大: " .. want .. " -> " .. got)
        end
    end
end

function t.test_pcm_to_alaw_swap_and_gain()
    local pcm = pcm16({ 1000, -1000 })
    assert(#gba.pcm_to_alaw(pcm) == 2)
    assert(#gba.pcm_to_alaw(pcm, 2) == 2)
    assert(#gba.pcm_to_alaw(pcm, 2, true) == 2)
    -- 空输入必须原样返回空串
    assert(gba.pcm_to_alaw("") == "")
    assert(gba.alaw_to_pcm("") == "")
end

function t.test_pcm_gain_clamp()
    local doubled = samples_of(gba.pcm_gain(pcm16({ 1000, -1000 }), 2))
    assert(doubled[1] == 2000 and doubled[2] == -2000,
           "2 倍增益结果不对")
    local clipped = samples_of(gba.pcm_gain(pcm16({ 30000, -30000 }), 100))
    assert(clipped[1] == 32767, "正方向应钳位到 32767")
    assert(clipped[2] == -32768, "负方向应钳位到 -32768")
    assert(gba.pcm_gain("", 2) == "", "空输入应返回空串")
end

function t.test_start_rejects_chip_and_bad_mode()
    local ok1, why1 = gba.start({}, { chip = "air1103" })
    assert(ok1 == false and type(why1) == "string", "chip 必须被拒绝")
    assert(why1:find("audio_air1103", 1, true) ~= nil,
           "错误信息应指向 demo/audio_air1103.lua")

    local ok2, why2 = gba.start({}, { mode = "bogus" })
    assert(ok2 == false and why2:find("音频模式", 1, true) ~= nil,
           "未知 mode 应被拒绝")
end

function t.test_idle_api_safe()
    assert(gba.mic_active() == false, "初始不应有 mic 采集")
    local ok = gba.stop()
    assert(ok == true, "空闲时 stop 应返回 true")
    local s = gba.stats()
    assert(type(s) == "table" and type(s.mic) == "table",
           "stats 应返回表并带 mic 子表")
end

-- 裸流后端的用例只在找得到模块时注册：它已不随 script/libs 发布，
-- 跑法见文件头的说明（不带上对应目录时整组跳过，而不是判失败）。
if raw then
    function t.test_raw_backend_available_and_idle()
        assert(raw.available() == true, "PC 上应有 gb28181.stream_*")
        assert(raw.is_running() == false, "初始不应在运行")
        assert(raw.stop() == true, "空闲时 stop 应返回 true")
        local s = raw.stats()
        assert(type(s) == "table", "stats 应返回表")
        assert(s.mode == nil and s.mic_active == false,
               "未运行时 mode 应为 nil、mic_active 为 false")
    end

    function t.test_raw_backend_rejects_bad_session()
        -- 没有 local_port：必须在建链前拒绝，不能碰 socket
        local ok1, why1 = raw.start({ call_id = "no-port" })
        assert(ok1 == false and type(why1) == "string")

        -- 未知承载：同样在 stream_new 之前拒绝
        local ok2, why2 = raw.start({
            call_id = "bad-transport", local_port = 31000, transport = "sctp",
        })
        assert(ok2 == false and type(why2) == "string")
        assert(why2:find("承载", 1, true) ~= nil, "错误应指明承载不合法")
        assert(raw.is_running() == false, "失败后不能留下运行状态")
    end
else
    log.warn("gb28181_audio_test",
             "没有 exgb28181audio_raw：跳过裸流后端用例" ..
             "（把组件仓库 gb28181/tests/tools/ 加入脚本路径可跑）")
end

return t
