--[[
@module  video_util
@summary 媒体素材工具（HZV 容器嗅探 / 帧尺寸读取 / 分辨率上限 / 播放器创建）—— 播放类页面共用
@version 3.0
@date    2026.11.11
@author  江访

=== 为什么单独成模块 ===
idle_win（桌面播放器）与 video_win（全屏播放页）都要读素材帧尺寸，而 airui 播放器
**不支持缩放**：控件尺寸与素材帧尺寸不一致时会被强制改回素材尺寸
（components/airui/src/components/widgets/luat_airui_video.c 的
 "scaling is not supported yet ... force reset widget size"）。
也就是说，帧尺寸读错**不会**把画面拉伸，只会让控件溢出容器、把画面切掉一块 ——
同一份口径必须只有一处实现，否则两个页面的裁切行为会不一致。

（welcome_win 里的历史副本已随 welcome 页面删除，全工程只剩这一处实现。）

=== 只播 HZV 一种容器（2026-11-11 起）===
素材是 MJPEG 逐帧 + 内嵌 MP3 音轨，走 airui.video 的 videoplayer 后端（tjpgd 软解或
平台硬解，逐帧拉 RGB565 塞进 lv_image），音轨由组件自己调 luat_audio_request_play_stream。
历史上还支持 MJPG（配同名 .mp3）与 MP4（mplayer 后端、闭源 mp4_decode、同名 .pcm 补声），
那条兼容线连同它的妥协已全部移除。桌面播放器（idle_win）与全屏播放页（video_win）
的播放收口到 create_player 一个入口。

**HZV 不碰 exaudio**：它的音轨由 videoplayer 自己走 luat_audio_request_play_stream，
而 exaudio.setup 的 DAC 收尾会 audio_v2.shutdown 关掉 codec 和功放，紧接着起播会让
下一路 play_stream 没声音。所以本模块只管功放引脚，音频框架一律不初始化。

@api video_util.guess_format(path)              是否 HZV："hzv" | nil（不认识的容器）
@api video_util.read_dimensions(path)           w, h；读不到返回 nil
@api video_util.frame_size(path, def_w, def_h)  w, h；读不到时用调用方给的兜底值
@api video_util.max_frame_size(fmt)             源分辨率上限 w, h
@api video_util.check_frame(path)               ok, w, h, fmt, reason；超上限时 ok=false 且 reason 说明原因
@api video_util.create_player(path, o)          创建**嵌入式**播放器（airui.video，
                                                o.on_complete=单次播完回调）
                                                创建失败按「硬解→软解→建好再起播」降级重试，
                                                全部失败返回 nil 并逐档打日志（含堆剩余）
@api video_util.after_release(fn)               释放窗口内延后执行 fn，窗口已关则立即执行
@api video_util.cancel_pending()                丢掉待执行的建播放器动作（页面失焦/销毁时）
]]

local M = {}

--[[判断素材是不是 HZV：先看魔数，再看扩展名，都不是返回 nil

魔数优先的原因：素材被改名（或从 SD 卡拷进来时后缀被改）后仍能正确解码。
返回 nil 的素材由调用方按「无法播放该文件」处理，不会拿去解码器白试一轮。]]
function M.guess_format(path)
    local f = io.open(path, "rb")
    if f then
        local magic = f:read(4)
        f:close()
        if magic == "HZV1" then return "hzv" end
    end
    local ext = path and path:match("%.([^%.]+)$")
    if ext and ext:lower() == "hzv" then return "hzv" end
    return nil
end

--[[读 HZV 容器头拿回 (width, height)

HZV v1: 前 4 字节为 "HZV1"，0x44 / 0x46 处各一个 uint16 宽、高
        （Lua 下标从 1 起，所以是 byte(69)/byte(70) 与 byte(71)/byte(72)）
        固定头 128 字节，宽高就在 72 字节以内，读到那里就够

@return width, height 或 nil（调用方必须给兜底值）]]
function M.read_dimensions(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read(72)
    f:close()
    if not data or #data < 72 then return nil end
    if data:sub(1, 4) ~= "HZV1" then return nil end
    local hw = data:byte(69) + data:byte(70) * 256
    local hh = data:byte(71) + data:byte(72) * 256
    if hw > 0 and hh > 0 then return hw, hh end
    return nil
end

--[[读素材帧尺寸，读不到时回退到调用方给的兜底值

兜底值必须与该页面的**布局基准**一致：给定错了不会「拉伸画面」，
只会让控件溢出容器、把画面切掉一块。]]
function M.frame_size(path, def_w, def_h)
    local w, h = M.read_dimensions(path)
    if w and h then return w, h end
    return def_w, def_h
end

-- ==================== 素材分辨率上限 ====================
--[[源分辨率上限（含）：超出拒绝起播，调用方按「无法播放」走提示 / 空态

hzv : videoplayer 后端（tjpgd 软解或平台硬解，控件内双帧缓冲），支持到 1024×600。
      1024×600 的 HZV 是合法素材，在 1024×600 屏上能整屏播；桌面素材 fruit.hzv 是 480×320。

只拦「读到了尺寸且超限」的确定情况：尺寸读不出来时交回解码器去试，
不要因为容器头解析失败就误杀一个好素材。]]
local FRAME_MAX = {
    hzv = { w = 1024, h = 600 },
}

--[[取某格式的源分辨率上限
@param fmt string 容器格式（guess_format 的返回值）
@return number max_w, number max_h（未知格式返回 0,0 表示不设限）]]
function M.max_frame_size(fmt)
    local lim = FRAME_MAX[fmt]
    if not lim then return 0, 0 end
    return lim.w, lim.h
end

--[[按格式上限校验素材（两个播放页面都只调这一个）

@param path string 素材路径
@return boolean  ok     是否可播
@return number   w       帧宽（读不到时 nil）
@return number   h       帧高（读不到时 nil）
@return string   fmt     容器格式
@return string   reason  不可播原因（可播时 nil），可直接给用户看
]]
function M.check_frame(path)
    local fmt = M.guess_format(path)
    local w, h = M.read_dimensions(path)
    local max_w, max_h = M.max_frame_size(fmt)
    if w and h and max_w > 0 and (w > max_w or h > max_h) then
        return false, w, h, fmt, string.format(
            "%s 素材 %d×%d 超过该格式上限 %d×%d，无法播放",
            string.upper(fmt), w, h, max_w, max_h)
    end
    return true, w, h, fmt, nil
end

-- ==================== 功放（PA） ====================
--[[功放引脚要手动使能，videoplayer 不拉它

起播前打开、停播后关闭，收口在这里。跨路径丢功放由 pa_reassert 补
（exaudio.setup 的 DAC 收尾会 audio_v2.shutdown 关掉 codec 和功放，
TTS / 录音回放那些路径跑完之后回到播放器，功放可能已经是关的）。
停播必须关：PA 常开时 DAC 空闲噪声被放大成电流声（2026.11.11 实测切界面时出现）。]]

-- PA 功放使能/关闭：驱动收口到 audio_hw.pa_set（pa_power_hold 闸在那边统一挡）。
-- 本模块仍只管功放引脚、不初始化音频框架 —— require audio_hw 不碰 exaudio（它内部懒加载）
local audio_hw = require "audio_hw"
local function pa_set(on)
    return audio_hw.pa_set(on)
end

-- 跨路径功放补枪的世代号（关功放时也 +1，作废还没落地的补枪）
local pa_gen = 0

-- 起播时把功放打开，并在音频任务异步收尾之后再补一次
local function pa_reassert()
    pa_gen = pa_gen + 1
    local gen = pa_gen
    pa_set(true)
    sys.timerStart(function()
        if gen == pa_gen then pa_set(true) end
    end, 200)
end

-- 停播后关功放，顺带作废 200ms 那一脚补枪（否则它会把刚关的功放又拉起来）。
-- 真关与否由 audio_hw.pa_off 统一判：别的音频任务 / PA 使用者还在用就放弃
local function pa_off()
    pa_gen = pa_gen + 1
    audio_hw.pa_off()
end

-- 暂停后延后关功放：暂停瞬间 DAC 还在收尾，立刻关会有 pop；
-- 期间恢复播放由 pa_reassert 顶掉世代号，这一脚不再落地
local PA_OFF_MS = 150
local function pa_off_later()
    local gen = pa_gen
    sys.timerStart(function()
        if gen == pa_gen then pa_off() end
    end, PA_OFF_MS)
end

-- ==================== 播放器会话释放窗口 ====================
--[[stop/destroy 到下一次 create 必须留出释放时间

播放器的音频会话从 stop() 到 C 侧打出 `dac_sound audio v2 request end` 实测要
400~530ms（HZV 的 videoplayer 与当年的 mplayer 同一条 luat_audio_request_play_stream
通路，节奏一样）。这段窗口里再起一路新会话去 luat_audio_request_play_stream，会跟还没
释放完的旧会话抢：轻则新会话的 DAC 驱动起不来（`Movie audio` 打印了却没有
`dac_sound audio v2 driver started`），重则新会话阻塞在音频请求上、解码线程一帧
不出，连带触摸 I2C 事务被拖死。真机 100% 复现（2026.11.03：桌面↔文件管理来回、
中间切两次循环，第 5 路音频断在半路、第 6 路卡死）。

页面的「停旧 → 建新」都在同一次回调里做，中间让不出时间，所以收口到这里：
stop/destroy 打开释放窗口，窗口没关就把建播放器的动作延后到窗口结束再做。
延后用定时器而不是 sys.wait —— 起播发生在点击 / 焦点回调里，不在协程上下文。]]
local RELEASE_MS = 700          -- 释放窗口长度（实测 400~530ms，留余量）
local release_timer = nil       -- 非 nil = 释放窗口未关
local pending_create = nil      -- 窗口结束后要执行的建播放器动作
local live_players = 0          -- 还活着的播放器数（wrap_release 记账，0 时才允许关功放）
local playing_players = 0       -- 正在播的播放器数（暂停/停止即退出计数，PA 仲裁看它）
-- PA 使用者探针：桌面视频正在播时 audio_hw.pa_off 会放弃关功放
-- （音量测试收尾等路径要关 PA，不能掐掉视频正在用的功放）
pcall(function()
    require("audio_hw").register_pa_blocker("video", function() return playing_players > 0 end)
end)

-- 打开（或顺延）释放窗口：每停一路就从头计时
local function mark_release()
    if release_timer then sys.timerStop(release_timer) end
    release_timer = sys.timerStart(function()
        release_timer = nil
        -- 窗口结束 = 旧会话音频已收尾，这时才关功放（关早了截尾音有 pop，
        -- 不关则 PA 常开、DAC 空闲噪声被放大成电流声）。
        -- 还有活着的播放器就别关：页面可能没走 after_release 直接建了新播放器
        if live_players == 0 then pa_off() end
        local fn = pending_create
        pending_create = nil
        if fn then fn() end
    end, RELEASE_MS)
end

---释放窗口内延后执行 fn，窗口已关则立即执行
---连点 / 连切只保留最后一次动作，不会排队建出多个播放器
function M.after_release(fn)
    if not release_timer then
        fn()
        return
    end
    log.info("video_util", "释放窗口未关，起播延后", RELEASE_MS .. "ms")
    pending_create = fn
end

---丢掉待执行的建播放器动作（页面失焦 / 销毁时调用）
---只丢动作、不关窗口：这一次销毁照样需要完整的释放时间
function M.cancel_pending()
    pending_create = nil
end

--[[给播放器补一层会话收尾：stop/destroy 顺带打开释放窗口

HZV 的 videoplayer 音轨从 luat_audio_request_play_stream 走，「停旧 → 建新」
同样要留释放窗口（见上方释放窗口说明）。接口面与裸对象一致（:play/:pause/:stop/:destroy）。]]
local function wrap_release(v)
    live_players = live_players + 1
    playing_players = playing_players + 1   -- 创建即起播（auto_play / start_player 两条路都是）
    local closed = false
    local playing = true
    local function bye()
        if closed then return end      -- stop + destroy 连着调也只记一次账
        closed = true
        if playing then playing = false; playing_players = playing_players - 1 end
        live_players = live_players - 1
        mark_release()
    end
    return {
        play = function(self, ...)
            if not playing then playing = true; playing_players = playing_players + 1 end
            pa_reassert()   -- 暂停期间功放可能已被关，恢复播放重新拉高
            return v:play(...)
        end,
        pause = function(self, ...)
            local r = v:pause(...)
            if playing then playing = false; playing_players = playing_players - 1 end
            pa_off_later()  -- 暂停也要关功放，否则挂着 PA 一样有电流声
            return r
        end,
        stop = function(self, ...)
            local r = v:stop(...)
            bye()
            return r
        end,
        destroy = function(_)
            pcall(function() v:destroy() end)
            bye()
        end,
    }
end

-- ==================== 播放器创建 ====================
--[[堆剩余快照（只在创建失败时调用）

1024×600 的 HZV 要两块 RGB565 帧缓冲（约 2.4MB），起播时还要一块解码输出（约 1.2MB），
建不出来多半是内存不够，把剩余量一起打出来才好判断。]]
local function mem_snapshot()
    if not rtos or not rtos.meminfo then return "" end
    local out = {}
    for _, pool in ipairs({ "sys", "psram" }) do
        local ok, total, used = pcall(rtos.meminfo, pool)
        if ok and type(total) == "number" and type(used) == "number" and total > used then
            out[#out + 1] = string.format("%s余%dKB", pool, math.floor((total - used) / 1024))
        end
    end
    return table.concat(out, " ")
end

--[[最大连续块实测（只在创建失败时调用）

rtos.meminfo 报的是池子「总量-已用」，报不出「最大连续块」：碎片化时总量还很富余，
1MB 级的整块照样要不出来。帧缓冲走 luat_heap_memalign / luat_heap_malloc，跟
zbuff 取的是同一批堆（都落到 luat_heap_opt_malloc），所以用 zbuff 二分实测，
直接跟素材需要的「单块 = 宽×高×2」对账。]]
local function alloc_probe()
    if not zbuff or type(zbuff.create) ~= "function" then return "无zbuff" end

    -- 每测一档就地释放：zbuff 是 userdata，要两遍 GC 才回收，不收干净会把下一档搅小
    local function try(n)
        local ok, buf = pcall(zbuff.create, n)
        local got = ok and (buf ~= nil)
        buf = nil
        collectgarbage()
        collectgarbage()
        return got
    end

    collectgarbage()
    collectgarbage()
    local step = 64 * 1024
    local lo, hi, best = step, 4 * 1024 * 1024, 0
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2 / step) * step
        if mid < step then break end
        if try(mid) then
            best = mid
            lo = mid + step
        else
            hi = mid - step
        end
    end
    return string.format("最大连续块%dKB", math.floor(best / 1024))
end

--[[起播并确认真的起来了

airui.video:play() 既不报错也不返回值（C 端把错误吞了），是否起来只能问
get_stats().playing —— 组件只在底层起播成功时才置 true。
老固件没有 get_stats，无从校验，按起来了算。]]
local function start_player(v)
    pcall(function() v:play() end)
    if type(v.get_stats) ~= "function" then return true end
    local ok, st = pcall(function() return v:get_stats() end)
    return ok and type(st) == "table" and st.playing == true
end

--[[创建**嵌入式**播放器（唯一入口）

素材走 airui.video 的 videoplayer 后端（父容器内的控件，随 UI 层级显示/隐藏），
自带帧时序（HZV 容器帧时长）；单次播完（on_complete）由组件回调，循环也由组件
统一处理，控制栏代码无感。两个播放页面（桌面播放器 / 全屏播放页）都走这里。

@table o
  @userdata o.parent   airui 父容器
  @number   o.x,o.y    画面摆放位置（相对 parent）
  @number   o.w,o.h    画面尺寸（必须等于素材帧尺寸，不支持缩放）
  @boolean  o.loop     是否循环
  @function o.on_complete 单次播完（loop=false 读到 EOF）回调
@return userdata|nil 播放器对象（:play/:pause/:stop/:destroy），失败 nil
                      （素材不是 HZV、超过分辨率上限、或播放器创建失败时）
]]
function M.create_player(path, o)
    o = o or {}

    --[[分辨率超限拒绝起播：调用方按「无法播放」走提示 / 空态。
    上限见 FRAME_MAX，校验收口在 check_frame ——
    页面要提前知道「能不能播 / 为什么不能播」，也调它，不要各写一套判断。]]
    local size_ok, _w, _h, fmt, reason = M.check_frame(path)
    if not size_ok then
        log.warn("video_util", reason or "素材超过格式上限，拒绝起播", path)
        return nil
    end
    if fmt ~= "hzv" then
        log.warn("video_util", "只支持 HZV 素材", path)
        return nil
    end

    --[[HZV 音轨由 videoplayer 自己调用 luat_audio_request_play_stream，不经 exaudio。
    这里只保持功放开：exaudio.setup 的 DAC 收尾会 audio_v2.shutdown 关掉 codec 和功放，
    起播前调它反而会让这一路没有声音。]]
    pa_reassert()

    local vcfg = {
        parent = o.parent,
        x = o.x, y = o.y, w = o.w, h = o.h,
        src = path, format = fmt,
        decode_mode = "hw",
        loop = o.loop and true or false,
        auto_play = true,
        -- HZV 自带逐帧时长，不填 interval，显式走 videoplayer 后端
        backend = "videoplayer",
    }
    if o.on_complete then
        vcfg.on_complete = o.on_complete
    end

    --[[创建失败逐档降级重试

    C 端这条路全程静默：airui.video 建不出来只返回 nil（不抛错），videoplayer 的
    硬解回退、HZV 起播时音轨请求被拒也都不打日志。分档试，每档失败都记一行原因：
      1) 硬解 → 2) 软解（tjpgd 对大分辨率更宽容）
      3) 创建时不起播、建好后单独起播 —— auto_play 路径上「起播被拒」会把整个控件
         拖没（组件建不出来），跟「建不出来」混在一起分不清；分开后靠
         get_stats().playing 就能确认起播到底成没成。
    任一档成功即返回，全部失败才返回 nil。]]
    local attempts = {
        { decode_mode = "hw", auto_play = true },
        { decode_mode = "sw", auto_play = true },
        { decode_mode = "hw", auto_play = false },
        { decode_mode = "sw", auto_play = false },
    }
    -- 起播前先收干净垃圾：大分辨率要整块分配帧缓冲，Lua 侧能挤出来的都挤出来。
    -- 收两遍，userdata（上一个播放器的 zbuff / 临时对象）第二遍才回收
    collectgarbage()
    collectgarbage()

    local v = nil
    for i = 1, #attempts do
        local a = attempts[i]
        vcfg.decode_mode = a.decode_mode
        vcfg.auto_play = a.auto_play
        local ok, obj = pcall(airui.video, vcfg)
        if not ok then
            log.warn("video_util", "airui.video 报错", path, "decode=", a.decode_mode,
                     tostring(obj), mem_snapshot())
        elseif obj then
            if a.auto_play or start_player(obj) then
                v = obj
                break
            end
            log.warn("video_util", "起播被拒", path, "decode=", a.decode_mode, mem_snapshot())
            pcall(function() obj:stop() end)
            pcall(function() obj:destroy() end)
            mark_release()   -- 半路起播也可能占住音频请求，一并留释放窗口
        else
            log.warn("video_util", "airui.video 返回 nil", path, "fmt=", fmt,
                     "decode=", a.decode_mode, mem_snapshot())
        end
    end
    if not v then
        --[[放弃时把账算全：堆剩余 / 最大连续块 / 该素材单块需要多少。
        1024×600 单块是 1.23MB，起播峰值要 3 块（两块持久帧缓冲 + 一块解码输出），
        最大连续块够不上就是内存不够，够得上就往别处找原因。]]
        local need_kb = 0
        if type(_w) == "number" and type(_h) == "number" then
            need_kb = math.floor(_w * _h * 2 / 1024)
        end
        log.warn("video_util", "播放器创建放弃", path, "mem=", mem_snapshot(),
                 "单块需", need_kb .. "KB", alloc_probe())
        mark_release()   -- 各档都试过，残留的音频请求同样要留出释放时间
        return nil
    end
    -- 播放器打开时音频任务可能再次把功放拉高，创建成功后再拉一次
    pa_set(true)
    return wrap_release(v)
end

return M
