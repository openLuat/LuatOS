--[[
@module  app_audio
@summary 音乐播放器 - 音频后端（SD 卡扫描 / 内置示例兜底 / 歌词加载 / 播放控制）
@version 1.0
@date    2026.10.23
@board   Air8607（Air1603 内核 + 内置 DAC + HT6873 功放 + SPI1 SD 卡）

=== 音源优先级 ===
1、SD 卡（/sd/music/、/sd/audio/、/sd/mp3/、/sd/ 根目录，含一级子目录，mp3/wav/amr）
2、SD 卡不可用或没有音频文件时，播放随脚本打包的内置示例 Time_travel_8k.mp3
3、都没有：界面照常进入演示状态，日志报错，不卡死

=== 为什么用 exaudio.setup 之后又直接调 audio_v2 ===
exaudio 把 audio_v2.play() 返回的 request_index 收在模块内部的局部变量里，业务层拿不到，
于是 audio_v2.pause() / get_play_clock() 全都用不上 —— 「暂停/继续」和播放进度就做不了
（factory 工程 ui/video_util.lua 里明确记过这个坑：暂停后再点只能从头重放）。
这里先用 exaudio.setup() 把 DAC/PA 通路配好（DAC 模式只有它配好 pa_ctrl 才不会无声，
它内部会调 audio_v2.config_pa_power_ctrl，播放时自动开关功放），再自己调 audio_v2.play()
拿到 request_index，暂停与进度就都有了。
固件里没有 audio_v2 时才退回 exaudio.play_start()：那种情况下「暂停」等于停止、
「继续」会从头播（UI 上仍表现为暂停/继续，只是进度归零），日志里会提示。

=== 线程模型 ===
换曲要开文件、启动解码器、读 lrc，可能阻塞几十毫秒，不能在 LVGL 点击回调里做。
所以按钮只调 cmd() 入队，真正的动作在 pump 任务里串行执行。
UI 每帧调 update()：读播放进度、判断是否播完（播完按当前模式自动切下一首）。
]]

local lrc = require "lrc"

local M = {}
local TAG = "audio"

M.MODE_ORDER  = 1   -- 顺序播放（到末尾回到第一首）
M.MODE_RANDOM = 2   -- 随机播放（不连播同一首）
M.MODE_SINGLE = 3   -- 单曲循环

local MODE_NAME = {
    [M.MODE_ORDER]  = "顺序播放",
    [M.MODE_RANDOM] = "随机播放",
    [M.MODE_SINGLE] = "单曲循环",
}

--========================================================================
-- 板级参数（与 factory/config/eng_8607_10i_v0.lua 一致）
--========================================================================
local PIN_SD_EN    = 74      -- SD 卡供电使能，高有效
local SD_SPI_ID    = 1       -- SD 卡走 SPI1
local SD_PIN_CS    = 8       -- SPI1_CS
local PIN_AUDIO_PA = 73      -- AUDIOPA_EN（HT6873，高电平使能）

local AUDIO_CFG = {
    model = "dac",
    pa_ctrl = PIN_AUDIO_PA,
    pa_on_level = 1,
    dac_delay = 6,
    pa_delay = 10,
}

-- 随脚本一起打包的内置示例音频。不同上传方式落点不同（res/ 会被拍平到 /luadb/），
-- 这里按可能性从高到低探测，找到哪个用哪个。
local FALLBACK_PATHS = {
    "/luadb/res/Time_travel_8k.mp3",
    "/luadb/Time_travel_8k.mp3",
    "/res/Time_travel_8k.mp3",
    "/Time_travel_8k.mp3",
}

-- SD 卡里按顺序找这几个目录，先命中谁就用谁（/sd/ 根目录兜底）
local SD_DIRS = { "/sd/music/", "/sd/audio/", "/sd/mp3/", "/sd/" }

-- 与 exaudio.play_start 的扩展名→解码器映射保持一致
local AUDIO_EXT = { mp3 = true, wav = true, amr = true }

--========================================================================
-- 对外状态（UI 直接读这张表，字段名改动要同步 ui_main.lua / ui_styles.lua）
--========================================================================
local S = {
    ready     = false,     -- 音频后端是否就绪
    backend   = "none",    -- av2 / exaudio / none
    source    = "",        -- init(空) / sd / flash / none
    scan_dir  = "",        -- 实际扫描到的目录（UI 展示用）
    tracks    = {},        -- { {name=, title=, artist=, path=, size=, dur_ms=}, ... }
    index     = 0,         -- 当前曲目序号（1 起，0 表示未选）
    playing   = false,     -- 正在出声
    paused    = false,     -- 用户按了暂停
    mode      = M.MODE_ORDER,
    volume    = 70,
    pos_ms    = 0,
    dur_ms    = 0,
    title     = "",
    artist    = "",
    lyric     = nil,       -- lrc.parse 的返回值
    lyric_src = "none",    -- sd / none
}
M.S = S

--========================================================================
-- 运行时
--========================================================================
local exaudio = nil
local av2 = nil
local req = nil            -- audio_v2 请求索引
local idle_n = 0           -- 连续读到"请求空闲"的次数，用于确认播放结束
local started_at = 0       -- 起播时刻（毫秒），exaudio / 演示模式靠它估算进度
local queue = {}           -- 命令队列

--========================================================================
-- 时间
--========================================================================
--[[毫秒时钟
mcu.ticks() 是"多少 tick"而不是毫秒：Air1603（Air8607 的主控）约 20ms/tick，
必须用 mcu.hz() 折算，否则所有时间量都缩放 20 倍。
PC 模拟器 hz<=1，且 ticks 本身已是毫秒，直接返回即可。
]]
function M.now_ms()
    if mcu and mcu.ticks then
        local hz = (mcu.hz and mcu.hz()) or 1000
        local v = mcu.ticks()
        if v < 0 then v = v + 4294967296 end     -- ticks 是 uint32，回绕后可能变负
        if hz and hz > 1 then return v * 1000 / hz end
        return v
    end
    if sys and sys.mtime then return sys.mtime() end
    return os.time() * 1000
end

--========================================================================
-- 小工具
--========================================================================
local function ext_of(name)
    local e = name:match("%.([%w]+)$")
    return e and e:lower() or nil
end

local function le32(s, i)
    local a, b, c, d = s:byte(i, i + 3)
    if not d then return 0 end
    return a + b * 256 + c * 65536 + d * 16777216
end

local function tidy_name(name)
    return (name:gsub("%.[%w]+$", ""))
end

--[[从文件名里拆歌手与曲名："歌手 - 曲名" → artist, title]]
local function split_name(name)
    local a, b = name:match("^(.-)%s+%-%s+(.+)$")
    if a and #a > 0 and #b > 0 then return a, b end
    return "", name
end

--[[分页列目录（io.lsdir 单次上限 100，超过要翻页）]]
local function ls_all(dir)
    local out = {}
    local offset = 0
    while true do
        local ok, list = io.lsdir(dir, 100, offset)
        if not ok or type(list) ~= "table" or #list == 0 then break end
        for i = 1, #list do out[#out + 1] = list[i] end
        if #list < 100 then break end
        offset = offset + #list
        if offset > 2000 then break end
    end
    return out
end

local function file_size(path)
    local f = io.open(path, "rb")
    if not f then return 0 end
    local size = f:seek("end") or 0
    f:close()
    return size
end

--========================================================================
-- 时长探测
--========================================================================
-- MPEG1 Layer2/3 码率表（kbps）
local MP3_BR_V1 = {
    [1] = 32, [2] = 40, [3] = 48, [4] = 56, [5] = 64, [6] = 80, [7] = 96,
    [8] = 112, [9] = 128, [10] = 160, [11] = 192, [12] = 224, [13] = 256, [14] = 320,
}
-- MPEG2 / MPEG2.5 Layer3 码率表（kbps）
local MP3_BR_V2 = {
    [1] = 8, [2] = 16, [3] = 24, [4] = 32, [5] = 40, [6] = 48, [7] = 56,
    [8] = 64, [9] = 80, [10] = 96, [11] = 112, [12] = 128, [13] = 144, [14] = 160,
}
local MP3_SR = {
    [3] = { 44100, 48000, 32000 },   -- MPEG1
    [2] = { 22050, 24000, 16000 },   -- MPEG2
    [0] = { 11025, 12000, 8000 },    -- MPEG2.5
}

--[[估算音频时长（毫秒）
MP3 按第一帧的码率当恒定码率算（CBR 准确，VBR 只是近似）；
WAV 直接按 data 块大小 / 字节率算，准确。
拿不到就返回 0，UI 用 --:-- 显示且进度条不动。
]]
local function probe_duration(path, size)
    local f = io.open(path, "rb")
    if not f then return 0 end
    --[[fatfs 的 lsdir 不一定给出 d_size（可能恒为 0），
    所以传进来的 size 不可信时，用同一个句柄自己量一遍，不额外开文件。]]
    if not size or size <= 0 then
        size = f:seek("end") or 0
        f:seek("set", 0)
    end
    local head = f:read(4096) or ""
    f:close()
    if #head < 32 then return 0 end

    -- ---- WAV ----
    if head:sub(1, 4) == "RIFF" and head:sub(9, 12) == "WAVE" then
        local byte_rate, data_size
        local i = 13
        while i + 7 <= #head do
            local id = head:sub(i, i + 3)
            local sz = le32(head, i + 4)
            if id == "fmt " then
                byte_rate = le32(head, i + 16)
            elseif id == "data" then
                data_size = sz
                break
            end
            i = i + 8 + sz + (sz % 2)
        end
        if byte_rate and byte_rate > 0 then
            if data_size and data_size > 0 and data_size < 0x7FFFFFFF then
                return math.floor(data_size * 1000 / byte_rate)
            end
            return math.floor((size - 44) * 1000 / byte_rate)
        end
        return 0
    end

    -- ---- MP3 ----
    local base = 0
    if head:sub(1, 3) == "ID3" then
        local a, b, c, d = head:byte(7, 10)
        base = 10 + ((a or 0) * 2097152 + (b or 0) * 16384 + (c or 0) * 128 + (d or 0))
    end
    --[[找帧头：0xFF 后一个字节高 3 位全 1（即 >= 0xE0）
    注意不能写成 b2 % 32，那是取低 5 位，会把 0x1C~0x1F 这类垃圾数据误判成帧头。]]
    local pos
    for i = base + 1, math.min(#head - 3, base + 3000) do
        local b1, b2 = head:byte(i, i + 1)
        if b1 == 0xFF and b2 and b2 >= 224 then
            local ver = math.floor(b2 / 8) % 4          -- 3=MPEG1 2=MPEG2 0=MPEG2.5 1=保留
            local layer = math.floor(b2 / 2) % 4        -- 1=Layer3 2=Layer2 3=Layer1 0=保留
            if ver ~= 1 and (layer == 1 or layer == 2) then
                pos = i
                break
            end
        end
    end
    if not pos then return 0 end

    local b2, b3 = head:byte(pos + 1, pos + 2)
    local ver = math.floor(b2 / 8) % 4
    local bri = math.floor(b3 / 16) % 16
    local sri = math.floor(b3 / 4) % 4
    local br = (ver == 3) and MP3_BR_V1[bri] or MP3_BR_V2[bri]
    local srtab = MP3_SR[ver]
    if not br or not srtab or sri > 2 or not srtab[sri + 1] then return 0 end

    local audio_bytes = size - (pos - 1)
    if audio_bytes <= 0 then return 0 end
    local ms = math.floor(audio_bytes * 8 * 1000 / (br * 1000))
    if ms > 4 * 3600 * 1000 then ms = 0 end     -- 解析结果离谱就当未知
    return ms
end

-- 暴露给自检脚本用（正常业务只经由 start_track 间接使用）
M.probe_duration = probe_duration

--========================================================================
-- SD 卡
--========================================================================
--[[挂载 SD 卡
注意第 8 个参数 auto_format 必须传 false：fatfs 默认挂载失败就去格式化卡，
那会把用户卡里的东西全清掉，这里只报告失败，交给内置示例兜底。
]]
local function mount_sd()
    if not (fatfs and fatfs.mount and spi) then
        log.warn(TAG, "固件无 fatfs/spi，跳过 SD 卡")
        return false
    end
    pcall(gpio.setup, PIN_SD_EN, 1, gpio.PULLUP)   -- SD_EN 先供电
    sys.wait(50)
    pcall(spi.setup, SD_SPI_ID, nil, 0, 0, 8, 400000)
    pcall(gpio.setup, SD_PIN_CS, 1)                -- 挂载前先拉高 CS
    sys.wait(10)

    local ok, err = fatfs.mount(fatfs.SPI, "/sd", SD_SPI_ID, SD_PIN_CS,
        20 * 1000 * 1000, nil, 1, false)
    if not ok then
        log.warn(TAG, "SD 卡 20MHz 挂载失败，降到 8MHz 重试", err)
        ok, err = fatfs.mount(fatfs.SPI, "/sd", SD_SPI_ID, SD_PIN_CS,
            8 * 1000 * 1000, nil, 1, false)
    end
    if not ok then
        log.warn(TAG, "未检测到 SD 卡", err)
        return false
    end
    log.info(TAG, "SD 卡挂载成功", err)
    return true
end

--[[把一个目录（含一级子目录）里的音频文件收进 list]]
local function collect_dir(dir, list, seen, depth)
    local d = dir:gsub("/+$", "")
    if not (io.dexist and io.dexist(d)) then return end

    local subdirs = {}
    for _, it in ipairs(ls_all(dir)) do
        local name = it.name or ""
        if name ~= "" and name ~= "." and name ~= ".." then
            if it.type == 1 then
                if depth < 1 then subdirs[#subdirs + 1] = dir .. name end
            else
                local ext = ext_of(name)
                if ext and AUDIO_EXT[ext] then
                    local path = dir .. name
                    if not seen[path] then
                        seen[path] = true
                        local title = tidy_name(name)
                        local artist, t2 = split_name(title)
                        list[#list + 1] = {
                            name = title,
                            title = t2,
                            artist = artist,
                            path = path,
                            size = it.size or 0,
                        }
                    end
                end
            end
        end
    end

    for _, sub in ipairs(subdirs) do
        collect_dir(sub, list, seen, depth + 1)
    end
end

--[[扫描 SD 卡里的音频文件（按目录优先级 + 文件名排序，保证播放顺序稳定）]]
local function scan_sd()
    local list, seen = {}, {}
    local hit_dir = ""
    for _, dir in ipairs(SD_DIRS) do
        local n0 = #list
        collect_dir(dir, list, seen, 0)
        if #list > n0 and hit_dir == "" then hit_dir = dir end
        -- 已经在上层目录找到歌就不再看根目录，避免重复
        if #list > 0 and dir ~= "/sd/" then break end
    end
    table.sort(list, function(a, b)
        if a.path == b.path then return false end
        return a.path < b.path
    end)
    return list, hit_dir
end

--[[找内置示例音频；都没有就返回 nil]]
local function find_fallback()
    for _, p in ipairs(FALLBACK_PATHS) do
        if io.exists(p) then return p end
    end
    return nil
end

--========================================================================
-- 音频后端
--========================================================================
local function audio_init()
    -- exaudio 可能已被别的脚本 require 过，也可能挂在全局
    local lib = rawget(_G, "exaudio")
    if not lib then
        local ok, r = pcall(require, "exaudio")
        if ok then lib = r end
    end
    if not lib then
        log.warn(TAG, "exaudio 扩展库不可用，界面照常运行但不出声")
        return false
    end
    local ok2, ret = pcall(lib.setup, AUDIO_CFG)
    if not ok2 or not ret then
        log.warn(TAG, "exaudio.setup 失败，界面照常运行但不出声", ok2, ret)
        return false
    end
    exaudio = lib
    pcall(lib.vol, S.volume)
    sys.wait(100)            -- DAC / PA 上电需要一点时间

    -- 优先 audio_v2：只有它能拿到 request_index（暂停、进度都靠它）
    local av = rawget(_G, "audio_v2")
    if av and av.play and av.pause and av.is_busy then
        av2 = av
        S.backend = "av2"
        log.info(TAG, "音频后端 audio_v2（支持暂停与进度）")
        return true
    end
    if lib.play_start and lib.play_stop then
        S.backend = "exaudio"
        log.warn(TAG, "音频后端 exaudio（无暂停接口，继续播放会从头开始）")
        return true
    end
    return false
end

local function stop_req()
    if req and av2 then pcall(av2.stop, req) end
    req = nil
    idle_n = 0
end

--[[真正起播（在 pump 任务里调用，允许阻塞）]]
local function start_track(i)
    local tk = S.tracks[i]
    if not tk then return false end
    stop_req()

    S.index = i
    S.pos_ms = 0
    S.paused = false
    S.playing = false
    if not tk.dur_ms or tk.dur_ms <= 0 then
        tk.dur_ms = probe_duration(tk.path, tk.size or 0)
    end
    S.dur_ms = tk.dur_ms or 0

    -- ---- 显示信息 ----
    S.title = tk.title or tk.name
    S.artist = tk.artist or ""

    -- ---- 歌词 ----
    S.lyric = nil
    S.lyric_src = "none"
    local lp = lrc.find(tk.path)
    if lp then
        local ly, err = lrc.load(lp)
        if ly then
            S.lyric = ly
            S.lyric_src = "sd"
            -- 歌词文件里的 ti/ar 比文件名可靠
            if ly.meta.ti and ly.meta.ti ~= "" then S.title = ly.meta.ti end
            if ly.meta.ar and ly.meta.ar ~= "" then S.artist = ly.meta.ar end
            if ly.gbk then
                log.warn(TAG, "歌词不是 UTF-8 编码，中文会显示异常", lp)
            end
            log.info(TAG, "歌词已加载", lp, #ly.lines .. " 行")
        else
            log.warn(TAG, "歌词解析失败", lp, err)
        end
    end

    -- ---- 起播 ----
    local ok = false
    if S.backend == "av2" then
        -- exaudio.setup 默认 SHUTDOWN，直接调 audio_v2.play 前要手动唤醒一次
        if exaudio and exaudio.pm and exaudio.RESUME then
            pcall(exaudio.pm, exaudio.RESUME)
        end
        local r, idx = av2.play(tk.path)
        if r then
            req = idx
            ok = true
        else
            log.error(TAG, "播放失败", tk.path)
        end
    elseif S.backend == "exaudio" then
        ok = exaudio.play_start({ type = 0, content = tk.path }) and true or false
        if not ok then log.error(TAG, "播放失败", tk.path) end
    else
        -- 无音频硬件：走演示时钟，让画面与歌词照常走起来
        ok = true
    end

    S.playing = ok
    started_at = M.now_ms()
    idle_n = 0
    log.info(TAG, ok and "起播" or "起播失败", string.format("%d/%d", i, #S.tracks), tk.name)
    return ok
end

--[[下一首序号（按当前模式）]]
local function next_index()
    local n = #S.tracks
    if n == 0 then return 0 end
    if S.mode == M.MODE_RANDOM then
        if n == 1 then return 1 end
        local i, guard = S.index, 0
        while i == S.index and guard < 8 do
            i = math.random(n)
            guard = guard + 1
        end
        return i
    end
    local i = S.index + 1
    if i > n then i = 1 end
    return i
end

local function prev_index()
    local n = #S.tracks
    if n == 0 then return 0 end
    local i = S.index - 1
    if i < 1 then i = n end
    return i
end

-- 播放结束按模式决定下一首（单曲循环重播本首，其余按 next_index 走）
local function on_finished()
    if S.mode == M.MODE_SINGLE then
        M.cmd("play", S.index)
    else
        M.cmd("play", next_index())
    end
end

--========================================================================
-- 对外接口
--========================================================================
function M.mode_name()
    return MODE_NAME[S.mode] or "顺序播放"
end

function M.song_count()
    return #S.tracks
end

--[[入队一个命令（任意上下文可调，不阻塞）
@param string c play / next / prev
@param number a play 时的曲目序号
]]
function M.cmd(c, a)
    queue[#queue + 1] = { c = c, a = a }
end

function M.cycle_mode()
    local m = S.mode + 1
    if m > M.MODE_SINGLE then m = M.MODE_ORDER end
    S.mode = m
    log.info(TAG, "播放模式", M.mode_name())
    return m
end

function M.set_volume(v)
    v = math.floor(v or 70)
    if v < 0 then v = 0 elseif v > 100 then v = 100 end
    S.volume = v
    if exaudio and exaudio.vol then
        pcall(exaudio.vol, v)
    elseif av2 and av2.soft_volume then
        pcall(av2.soft_volume, v)
    end
    return v
end

function M.volume_step(d)
    return M.set_volume(S.volume + (d or 5))
end

--[[暂停 / 继续
av2 后端：真正的暂停（audio_v2.pause），继续时从原位置接着放。
exaudio / 演示后端：没有断点续播，暂停时记账、继续时按剩余位置重播（进度会归零）。
]]
function M.toggle()
    if S.index == 0 then
        if #S.tracks > 0 then M.cmd("play", 1) end
        return
    end

    if S.paused then
        if S.backend == "av2" and req then
            pcall(av2.pause, req, false)
            S.paused = false
            S.playing = true
        elseif S.backend == "exaudio" then
            M.cmd("play", S.index)      -- 无断点续播，只能重来
        else
            -- 演示时钟：把起点倒推到当前位置，接着往下走
            started_at = M.now_ms() - (S.pos_ms or 0)
            S.paused = false
            S.playing = true
        end
        log.info(TAG, "继续播放", S.index)
    else
        if S.backend == "av2" and req then
            pcall(av2.pause, req, true)
        elseif S.backend == "exaudio" and exaudio then
            pcall(exaudio.play_stop, { type = 0 })
        end
        S.paused = true
        S.playing = false
        log.info(TAG, "暂停", S.index)
    end
end

--[[每帧调用：刷新播放进度、判断是否播完]]
function M.update()
    if S.index == 0 then return end

    if S.backend == "av2" then
        if not req then return end
        if av2.get_play_clock then
            -- 请求不在跑（暂停/结束）时返回 nil，此时不要动 pos_ms
            local clock = av2.get_play_clock(req)
            if clock and clock.pts_ms then S.pos_ms = clock.pts_ms end
        end
        if S.paused then return end
        local busy = av2.is_busy(req)
        if busy then
            idle_n = 0
        else
            idle_n = idle_n + 1
            -- 连续 3 次空闲才认定播完：避免起播瞬间的窗口期被误判
            if idle_n >= 3 and S.playing then
                S.playing = false
                S.pos_ms = S.dur_ms
                log.info(TAG, "播放结束", S.index)
                on_finished()
            end
        end
    elseif S.backend == "exaudio" then
        if S.paused then return end
        S.pos_ms = M.now_ms() - started_at
        -- 起播后 800ms 内不判结束：旧框架 is_end 在请求刚入队时也是 true
        if S.playing and M.now_ms() - started_at > 800
            and exaudio.is_end and exaudio.is_end() then
            S.playing = false
            log.info(TAG, "播放结束", S.index)
            on_finished()
        end
    else
        --[[演示时钟（无音频硬件）：按真实时间推进，让画面与歌词照常走。
        播完之后必须靠 S.playing 挡住重复触发 —— 命令是异步入队的，
        在 pump 把下一首真正起播之前，本函数还会被调用好几次。]]
        if S.paused then return end
        local el = M.now_ms() - started_at
        if S.dur_ms and S.dur_ms > 0 and el >= S.dur_ms then
            if S.playing then
                S.playing = false
                S.pos_ms = S.dur_ms
                log.info(TAG, "演示播放结束", S.index)
                on_finished()
            end
        else
            S.pos_ms = (S.dur_ms and S.dur_ms > 0) and math.min(el, S.dur_ms) or el
            S.playing = true
        end
    end
end

--========================================================================
-- 命令泵
--========================================================================
local function handle(c, a)
    if c == "play" then
        if a and a >= 1 and a <= #S.tracks then start_track(a) end
    elseif c == "next" then
        if #S.tracks > 0 then start_track(next_index()) end
    elseif c == "prev" then
        if #S.tracks > 0 then start_track(prev_index()) end
    end
end

local function pump()
    while true do
        if #queue > 0 then
            local it = table.remove(queue, 1)
            local ok, err = pcall(handle, it.c, it.a)
            if not ok then log.error(TAG, "命令执行失败", it.c, err) end
        else
            sys.wait(80)
        end
    end
end

--========================================================================
-- 初始化
--========================================================================
--[[初始化音频后端与播放列表（阻塞，需在独立 task 里调用）
顺序：SD 卡 → 扫歌 → 没有就用内置示例 → 配音频通路 → 起播第一首
]]
function M.init()
    -- 命令泵先起：即使后面的初始化中途出错，按钮也不会完全失效
    sys.taskInit(pump)

    math.randomseed((os.time() or 1) * 1000 + (M.now_ms() % 1000))

    -- 1、SD 卡
    if mount_sd() then
        local list, dir = scan_sd()
        if #list > 0 then
            S.tracks = list
            S.source = "sd"
            S.scan_dir = dir
            log.info(TAG, "SD 卡曲目数", #list, "目录", dir)
        else
            log.warn(TAG, "SD 卡已挂载，但没有 mp3/wav/amr 文件")
        end
    end

    -- 2、内置示例兜底
    if #S.tracks == 0 then
        local p = find_fallback()
        if p then
            local size = file_size(p)
            S.tracks = { {
                name = "内置示例 - Time travel",
                title = "Time travel (内置示例)",
                artist = "SD 卡未就绪",
                path = p,
                size = size,
            } }
            S.source = "flash"
            log.info(TAG, "使用内置示例音频", p, size)
        else
            S.source = "none"
            log.error(TAG, "没有可播放的音频，界面进入演示状态")
        end
    end

    -- 3、音频通路
    S.ready = audio_init()
    if S.ready then M.set_volume(S.volume) end

    -- 4、起播第一首
    if #S.tracks > 0 then
        S.index = 1
        start_track(1)
    end

    log.info(TAG, "初始化完成", "音源=" .. S.source, "曲目=" .. #S.tracks, "后端=" .. S.backend)
    return S.ready
end

return M
