--[[
@module exgb28181playback
@summary GB28181 历史回放：把设备本地录像喂进回放会话
@version 0.1.0
@date    2026.09.17

平台点"历史回放"时，INVITE 的 SDP 给的是**时间段**（t= 起止 Unix 秒）而不是
文件名 —— 实测 WVP-Pro 的 `playbackStreamCmd` 里 `u=` 填的是
`<通道编码>:0`，**不是录像 ID**。所以"该播哪一段"只能设备自己按时间对。

本模块就是这一步：时间段 → 录像文件 → 按时间轴喂帧。

分层：
    gb28181(C)         录像文件 → annex-b 访问单元(record_*)，不碰文件系统
    exgb28181client    会话与发送(INVITE/ACK/BYE、push_frame、flush_session)
    exgb28181playback  本文件：选段、开文件、喂帧、暂停/拖动
    exgb28181audio     另一条支路：麦克风/喇叭 ↔ 音频会话

用法：
    local playback = require "exgb28181playback"
    playback.setup()        -- 注册为回放源；client.start() 前后都行
    -- 之后平台点回放，设备自动推录像，应用不需要自己推帧
    -- 平台拖进度条/暂停时，INFO 里的 MANSRTSP 由 client 解析后转到这里

录像库来自 client 的 records 配置（与 RecordInfo 应答**同源**，见
exgb28181client.normalize_records）：
    records = {{
        device_id  = "<通道编码>", name = "rec1",
        file_path  = "/sd/rec/1.mp4",          -- 本机路径
        start_time = "2026-09-17T00:00:00",    -- 字母 T
        end_time   = "2026-09-17T00:05:00",
    }}

**为什么必须由本模块推、而不是发事件让应用推**：回放的数据源是设备上已有的
录像文件，应用手里没有这份数据；而实时点播的帧来自摄像头，只有应用拿得到
（见 ARCHITECTURE.md §6）。两条路的数据源不同，所以入口也不同。
]]

local M = {}

local gb     = nil
local client = nil

-- 每个回放会话一份状态，按 Call-ID 索引（支持多路并发回放）
local g_sess = {}

-- 队列满时的重试间隔与次数。上限 ≈ 2s —— 超过它就不是"一时拥塞"，
-- 而是这一帧根本放不下（见 push_one 的说明）
local RETRY_MS   = 20
local RETRY_MAX  = 100

-- 单帧时间戳间隔的上限(毫秒)。文件里的时间戳跳变(切片接缝、损坏样本)
-- 会让按时间轴播放卡住很久，超过这个值就当"立即发"
local MAX_GAP_MS = 1000

--[[
两帧 90kHz 时间戳之差 → 毫秒（回绕安全）。

**必须用浮点算**：本固件的 Lua 是 32 位整数，`0x100000000` 会被截成 0，
写成 `(ts - prev) % 0x100000000` 会直接抛 `n%0` 把 VM 打崩（实测踩过）。
转成浮点后 2^32 是可精确表示的，减法与补回绕都不再有这个问题。

而**回绕是必然发生的**：C 层给的时间戳是"绝对 Unix 时刻 × 90000 截成32位"
（见 record 头文件），2026 年的时刻装不进 32 位。好在相邻帧只差几十毫秒，
所以"有符号差 + 必要时补一个周期"就够了 —— 补 2^32 得到的是正确的小增量。

差值落在 (0, 2^31) 之外时（时间戳倒流、损坏样本）交给 MAX_GAP_MS 兜底，
不会真的睡一个天文数字。
]]
local function ts_delta_ms(ts, prev)
    local d = (ts + 0.0) - (prev + 0.0)
    if d < 0 then
        d = d + 4294967296.0
    end
    return d / 90.0
end

local function logi(...) log.info("gb28181playback", ...) end
local function logw(...) log.warn("gb28181playback", ...) end
local function loge(...) log.error("gb28181playback", ...) end

local function now_ms()
    if _G.mcu and type(mcu.ticks) == "function" then return mcu.ticks() end
    return os.time() * 1000
end

-- 向上层派事件。走 client 的事件出口，应用只需要注册一处回调
local function emit(action, st, extra)
    if client == nil then return end
    local p = {
        call_id = st.sess and st.sess.call_id,
        record  = st.rec and st.rec.path or nil,
        frames  = st.frames,
    }
    if type(extra) == "table" then
        for k, v in pairs(extra) do p[k] = v end
    end
    client.emit_event("playback", action, p)
end

--[[
加载 C 模块。与其它几个模块同样的两条取用路径（真机 require、
PC 模拟器回退全局表），失败返回 false 而不是抛错 —— 固件没开
LUAT_USE_GB28181 时，require 本模块不该炸。
]]
local function load_deps()
    if gb == nil then
        local ok, mod = pcall(require, "gb28181")
        gb = ok and mod or rawget(_G, "gb28181")
        if gb == nil then
            return false, "C 层 gb28181 不可用(固件未开 LUAT_USE_GB28181?)"
        end
    end
    if type(gb.record_open) ~= "function" then
        return false, "C 层没有 record_open(固件版本太旧?)"
    end
    if client == nil then
        local ok, mod = pcall(require, "exgb28181client")
        if not ok or type(mod) ~= "table" then
            return false, "无法加载 exgb28181client"
        end
        client = mod
    end
    return true
end

-- ------------------------------------------------------------------
-- 选段：时间段 → 录像文件
-- ------------------------------------------------------------------

--[[
从录像库里挑出"该播的这一段"。

**策略（有意选定）：顺延到之后最近的一段** —— 返回第一条满足
`end_unix >= pos` 的可播录像。

为什么不是"回退到之前最近的一段"：平台传下来的 pos 是用户在时间轴上选的
位置。该位置没有录像（被循环覆盖、或用户拖到了空隙）时，用户想看的是
"接下来发生了什么"；回退会先播一段他没要的旧画面，观感是"拖了没反应、
画面还退回去了"。

为什么有 from_idx 而不是每次都从头找：一段播完要接着播时间上相邻的下一段
（录像按分钟切片，用户选的时间段通常跨好几个文件），这时必须**只往后看**，
否则会回到刚播过的那一段，表现为"播完又从头开始"。

@param records  归一化后的录像列表（client.records()）
@param pos      目标时刻（Unix 秒）
@param from_idx 从第几条开始找（首次传 1，续播传上一段 +1）
@return table|nil 录像条目
@return int|nil   它在列表中的序号
]]
local function select_record(records, pos, from_idx)
    for i = (from_idx or 1), #records do
        local r = records[i]
        if r.playable and r.end_unix >= pos then
            return r, i
        end
    end
    return nil, nil
end

-- ------------------------------------------------------------------
-- 文件与时间轴
-- ------------------------------------------------------------------

local function close_file(st)
    if st.ud then
        gb.record_close(st.ud)
        st.ud = nil
    end
    st.rec = nil
end

-- 当前播到的绝对时刻(Unix 秒)。位置由"起点 + 已播时长"导出，
-- 不是逐帧累加时间戳 —— 原因见 pace_delay_ms
local function pos_now(st)
    return st.base_unix + math.floor(st.played_ms / 1000)
end

--[[
打开覆盖 pos 的那段录像并定位到 pos。

**epoch 的口径**：取自归一化后的 start_unix，与报给平台的 StartTime 是
同一个数（record 层头文件把这条写成契约）。各算各的迟早会漂，而漂了的
表现是"平台按它看到的时间点回放，设备却定位到别处"，极难倒查。

@return boolean, string|nil
]]
local function open_at(st, pos)
    close_file(st)

    local rec, idx = select_record(st.records, pos, st.from_idx)
    if rec == nil then
        return false, "没有覆盖该时刻的录像"
    end

    local ud, err = gb.record_open(rec.path, rec.epoch)
    if ud == nil then
        return false, "打开录像失败: " .. tostring(err) ..
                       " (" .. tostring(rec.path) .. ")"
    end
    if not gb.record_seek(ud, pos) then
        gb.record_close(ud)
        return false, "定位失败: " .. tostring(rec.path)
    end

    st.ud        = ud
    st.rec       = rec
    st.rec_idx   = idx
    st.from_idx  = idx + 1
    -- 实际播到哪：pos 早于录像起点时只能从头开始（seek 层也是这么做的）
    st.base_unix = (pos > rec.start_unix) and pos or rec.start_unix
    st.played_ms = 0        -- 自 base_unix 起的**文件内**已播时长
    st.last_ts   = nil      -- 换了文件，时间戳基准要重来
    st.t0_ms     = now_ms()

    logi("回放定位", tostring(rec.name or idx), tostring(rec.path),
         os.date("%Y-%m-%d %H:%M:%S", st.base_unix))
    return true
end

--[[
算出"这一帧还要等多久才发"（毫秒），即实时(1x)回放。

为什么按文件自己的时间戳走，而不是按帧率睡固定值：录像可能是变帧率的
（编码器按需出帧），按固定帧率睡会让整段录像的**时长与内容都对不上**，
平台侧录下来的回放会比你选的时间段短或长。

为什么用"累计已播时长"而不是"这一帧时间戳 − 起始时间戳"：C 层给的 90kHz
时间戳是**绝对 Unix 时刻 × 90000 截成 32 位**的（见 record 头文件），2026 年
的时刻装不进 32 位、已经在回绕。所以只能在**相邻两帧之间**做差（差值只有
几十毫秒，回绕安全），再累加到 played_ms 上。

返回 0 表示"已经落后了，立刻发"。落后时不该补睡 —— 补睡会把落后量一直
累加下去，表现为"越播越慢"；立即发才能自然追上。
]]
local function pace_delay_ms(st, ts)
    if ts == nil then
        return 0
    end

    if st.last_ts ~= nil then
        local d = ts_delta_ms(ts, st.last_ts)
        if d > MAX_GAP_MS then
            -- 文件里的时间戳跳变：按它等会让回放停住，按上限等即可
            logw("帧间隔异常，按上限处理", tostring(math.floor(d)), "ms")
            d = MAX_GAP_MS
        end
        st.played_ms = st.played_ms + d
    end
    st.last_ts = ts

    -- t0 = 这一段开播时的墙钟。暂停/拖动后由 resume()/seek() 重设，
    -- 否则暂停的那段时间会被算成"落后"，一恢复就狂发
    local delay = (st.t0_ms + st.played_ms) - now_ms()
    return delay > 0 and math.floor(delay) or 0
end

-- ------------------------------------------------------------------
-- 喂帧
-- ------------------------------------------------------------------

--[[
把一帧交给会话。队列满时**等**而不是丢 —— 这是回放与实时的关键差别。

实时点播的帧来自摄像头，丢一帧是唯一选择（下一帧马上来，等就是积压）。
回放的帧来自文件，**等得起**：丢一帧意味着画面缺一块，要到下一个 IDR 才
恢复，在平台侧看起来就是花屏。所以这里 flush 之后重试。

重试的前提是"这帧放得下"。队列容量是固定的(默认 32KB)，而一个 1080p 的
IDR 可能上百 KB —— 那种帧等到天荒地老也进不去，只能丢掉并计数，否则回放
会**永久卡死在这一帧**（而不是"少一块画面"）。

@return boolean 是否发出去了
@return string|nil 失败原因
]]
local function push_one(st, au)
    local why
    for _ = 1, RETRY_MAX do
        local ok, err = client.push_frame(st.sess, au)
        if ok then
            st.frames = st.frames + 1
            return true
        end
        why = err
        if err ~= "queue_full" then
            return false, err     -- 会话没了 / 链路断了，等也没用
        end
        client.flush_session(st.sess)
        sys.wait(RETRY_MS)
    end

    st.dropped = st.dropped + 1
    return false, why
end

-- ------------------------------------------------------------------
-- 回放泵
-- ------------------------------------------------------------------

--[[
一个回放会话的主循环。每个会话一个任务，各自独立（并发回放互不影响）。

循环里几件事的顺序是有讲究的：
  1. 先看暂停/拖动 —— 拖动要换文件，得在取帧之前处理，否则会先白取一帧
  2. 没有打开的文件就打开（首次进入、或上一段播完要续下一段）
  3. 取一帧 → 按时间轴等 → 推出去
  4. 播到 t_end 就收工。**不主动发 BYE**（会话何时结束由平台决定），
     只停推流并报事件
]]
local function pump_task(st)
    while st.running do
        if st.paused then
            sys.wait(RETRY_MS)

        elseif st.ud == nil then
            local want = st.seek_to or st.start_pos
            st.seek_to = nil
            local ok, err = open_at(st, want)
            if not ok then
                M.finish(st, "no_record", err)
                break
            end

        elseif st.stop_at and pos_now(st) >= st.stop_at then
            -- **逐帧判**，不能只在换文件时判：用户选的时间段通常落在
            -- 某一段录像的中间，那一段本身比时间段长
            M.finish(st, "reached_end")
            break

        else
            local au, ts = gb.record_next(st.ud)
            if au == nil and ts ~= nil then
                M.finish(st, "error", tostring(ts))   -- 出错时第二返回值是错误串
                break
            end

            if au == nil then
                -- 这一段播完了：接着播时间上相邻的下一段，直到 t_end
                local next_rec = select_record(st.records, st.rec.end_unix, st.from_idx)
                if next_rec == nil then
                    M.finish(st, "reached_end")
                    break
                end
                if not open_at(st, next_rec.start_unix) then
                    M.finish(st, "no_record")
                    break
                end
            else
                local delay = pace_delay_ms(st, ts)
                if delay > 0 then
                    sys.wait(delay)
                end
                local ok, err = push_one(st, au)
                if not ok and err ~= "queue_full" then
                    M.finish(st, "session", tostring(err))
                    break
                end
            end
        end
    end

    close_file(st)
    st.running = false
end

--[[
把泵跑起来。已经在跑就什么都不做（重复 ACK、拖动、播完重来都走这里）。

**播完之后不能再拖动**是个很容易漏的坑：若在收工时把会话状态删掉，
平台在后面发的 seek 就找不到会话，表现为"首次回放能拖，播完再拖没反应"。
所以收工只置状态、不删条目（条目由 M.stop 在会话销毁时删）。
]]
local function launch(st)
    if st.running then
        return
    end
    st.running  = true
    st.finished = false
    sys.taskInit(pump_task, st)
end

--[[
启动一个回放会话的泵。由 on_session 调用。
@return boolean, string|nil
]]
local function start_pump(sess)
    local ok, err = load_deps()
    if not ok then
        return false, err
    end

    local records = client.records()
    if #records == 0 then
        return false, "没有配置录像(见 client 的 records 配置)"
    end

    -- 平台没给 t_start 时(is_playback 靠 s= 兜底判出来的)从最早的录像开始
    local start_pos = sess.t_start
    if start_pos == nil then
        local first = select_record(records, 0, 1)
        if first == nil then
            return false, "录像列表里没有可播的条目"
        end
        start_pos = first.start_unix
        logw("回放 INVITE 没有 t= 行，从最早的录像开始", tostring(first.name))
    end

    --[[
    状态表**必须在这里就填成完整可用的**，不能等到 open_at 再补：
    stats() 与平台的控制命令都可能在泵跑到 open_at 之前进来，缺字段就是
    一次 nil 算术(实测踩过：暂停命令恰好在泵读第一帧前到达，stats 把它
    打崩，整个 VM 重启)。
    ]]
    local st = {
        sess       = sess,
        records    = records,
        from_idx   = 1,
        start_pos  = start_pos,
        stop_at    = sess.t_end,
        base_unix  = start_pos,     -- 当前播到的基准时刻(open_at 会按实际定位改写)
        played_ms  = 0,             -- 自 base_unix 起的文件内已播时长
        last_ts    = nil,           -- 上一帧的时间戳(首帧为 nil)
        t0_ms      = now_ms(),
        paused     = false,
        finished   = false,
        running    = false,         -- 由 launch() 置位并启动任务
        frames     = 0,
        dropped    = 0,
    }
    g_sess[sess.call_id] = st

    logi("回放开始", tostring(sess.call_id),
         os.date("%H:%M:%S", start_pos),
         st.stop_at and os.date("%H:%M:%S", st.stop_at) or "(到文件末尾)")

    emit("started", st)
    launch(st)
    return true
end

-- ------------------------------------------------------------------
-- 会话钩子（由 exgb28181client 调用）
-- ------------------------------------------------------------------

--[[
回放控制入口。由 client 在以下时机调用，一般不需要自己调：

    ACK 到达         → ("start")
    会话销毁         → ("stop")
    INFO + MANSRTSP  → ("pause") / ("resume") / ("seek", 偏移秒数)

@param sess   回放会话（带 is_playback / t_start / t_end）
@param action "start" | "stop" | "pause" | "resume" | "seek"
@param arg    seek 时的偏移秒数（相对 t_start，见 M.seek）
]]
function M.on_session(sess, action, arg)
    if type(sess) ~= "table" or sess.call_id == nil then
        return
    end

    if action == "start" then
        if g_sess[sess.call_id] then
            return                      -- 重复的 ACK，别起两个泵
        end
        local ok, err = start_pump(sess)
        if not ok then
            loge("回放启动失败:", err)
            if client then
                client.emit_event("playback", "error",
                                  { call_id = sess.call_id, reason = err })
            end
        end
    elseif action == "stop" then
        M.stop(sess)
    elseif action == "pause" then
        M.pause(sess)
    elseif action == "resume" then
        M.resume(sess)
    elseif action == "seek" then
        M.seek(sess, arg)
    end
end

-- ------------------------------------------------------------------
-- 对外接口
-- ------------------------------------------------------------------

--[[
注册为回放源。**必须在平台发起回放之前调用**（client.start() 前后都行）。

重复调用无副作用。不调用的话，平台的回放会话能建立但一个字节都不会发，
client 侧会打一条明确的告警。

@api exgb28181playback.setup()
@return boolean, string|nil
]]
function M.setup()
    local ok, err = load_deps()
    if not ok then
        return false, err
    end
    client.on_playback(M.on_session)
    logi("回放源已注册")
    return true
end

--[[
暂停回放（平台点暂停时由 MANSRTSP 触发，也可自己调）。

**不是把泵停掉**：泵继续跑，只是不再取帧。这样"恢复"是即时的，
也不必处理任务重启的竞态。
]]
function M.pause(sess)
    local st = g_sess[sess and sess.call_id]
    if not st or st.paused or st.finished then
        return false                  -- 已播完就没什么可暂停的
    end
    st.paused = true
    logi("回放暂停", tostring(sess.call_id))
    emit("paused", st)
    return true
end

--[[
从暂停中恢复。

恢复时要**同时重置两个基准**，它们对应两套不同的时钟：
  · st.t0_ms / played_ms —— 播放位置的时间轴（否则暂停时长被算成落后）
  · sess.last_ms        —— RTP 时间戳的推进基准（push_frame 用的是"距上次
                            推帧的墙钟差"，不清掉的话平台上会看到时间戳
                            整整跳一个暂停时长）
]]
function M.resume(sess)
    local st = g_sess[sess and sess.call_id]
    if not st then
        return false
    end
    if st.finished then
        -- 播完之后平台若发 `PLAY Range: npt=now-`（"继续"），**没有东西可继续**：
        -- 当前位置就是末尾。真要再看只能拖动(seek，会重新放起来)或重新点播。
        -- 明确记一笔，免得与"平台根本没发命令"混淆
        logw("回放已播完，忽略'继续'；要重看请拖动或重新点播", tostring(sess.call_id))
        return false
    end
    if not st.paused then
        return false
    end
    st.paused    = false
    st.t0_ms     = now_ms() - st.played_ms
    sess.last_ms = nil
    logi("回放恢复", tostring(sess.call_id))
    emit("resumed", st)
    return true
end

--[[
拖动到某个位置。

@param sess    会话
@param seconds 偏移秒数（**相对回放起点**，>=0）

为什么是相对而不是绝对：实测 WVP 的 `playSeekCmd` 发的是
`Range: npt=<秒>-`，而 npt(normal play time) 在 RTSP 里对一段"存储的节目"
就是相对节目开头的偏移；同一平台恢复播放时发的 `Range: npt=now-` 是同一套
语义（now = 当前位置，不可能是绝对时刻）。所以这里的秒数相对 t_start。

只改"意图"，换文件交给泵做 —— 在泵里换的目的是让取帧与换文件在同一个
上下文里，不至于出现"泵正拿着旧文件句柄取帧，控制路径把它关掉了"。
]]
function M.seek(sess, seconds)
    local st = g_sess[sess and sess.call_id]
    if not st then
        return false, "该会话没有在回放"
    end
    if type(seconds) ~= "number" or seconds < 0 then
        return false, "偏移秒数无效"
    end

    local target = st.start_pos + math.floor(seconds)
    if st.stop_at and target > st.stop_at then
        target = st.stop_at       -- 拖到时间段之外就落到末尾，播完自然收工
    end

    st.seek_to   = target
    st.from_idx  = 1              -- 从头找：可能往前拖
    st.paused    = false
    st.played_ms = 0              -- 新位置的时间轴从零重算
    st.last_ts   = nil
    st.t0_ms     = now_ms()
    sess.last_ms = nil

    -- 播完之后再拖要能重新放起来（见 launch 的说明）
    launch(st)

    logi("回放拖动", tostring(sess.call_id), seconds .. "s",
         os.date("%H:%M:%S", target))
    emit("seek", st, { seconds = seconds, target = target })
    return true
end

--[[
停止回放并释放文件。会话本身还在（是否结束由平台决定），只是不再推流。

由 client 在会话销毁时自动调用（BYE / 失活回收 / 受理失败），也可自己调。
]]
function M.stop(sess)
    local st = g_sess[sess and sess.call_id]
    if not st then
        return true
    end
    st.running = false
    st.paused  = false
    g_sess[sess.call_id] = nil
    logi("回放停止", tostring(sess.call_id), "共", st.frames, "帧",
         st.dropped > 0 and ("丢弃 " .. st.dropped .. " 帧") or "")
    emit("stopped", st)
    return true
end

--[[
收工。**不主动发 BYE** —— 会话的终结由平台决定，设备主动 BYE 有些平台会
当成回放异常。（有意选定：停推流、保留会话，等平台 BYE。代价是平台若一直
不发 BYE，端口会占着 —— TCP 会话由 client 的失活回收兜底，UDP 的本来就
判不出来，见 session_death_reason。）
]]
function M.finish(st, reason, detail)
    logi("回放结束", tostring(st.sess and st.sess.call_id), reason, detail or "")

    st.paused   = false
    st.running  = false
    st.finished = true     -- 条目**保留**：播完之后平台还可能拖动(见 launch)
    close_file(st)
    emit("finished", st, { reason = reason, detail = detail })
end

--[[
查询回放状态。用以判断"在播/暂停/播到哪了"。

@api exgb28181playback.stats([session])
@table session 可选，不传则返回全部会话
@return table|nil
]]
function M.stats(sess)
    if sess and sess.call_id then
        local st = g_sess[sess.call_id]
        if not st then return nil end
        return {
            frames   = st.frames,
            dropped  = st.dropped,
            paused   = st.paused,
            running  = st.running,
            finished = st.finished,
            record   = st.rec and st.rec.path or nil,
            pos      = pos_now(st),
            stop_at  = st.stop_at,
        }
    end
    local out = {}
    for _, st in pairs(g_sess) do
        out[st.sess.call_id] = M.stats(st.sess)
    end
    return out
end

return M
