--[[
@module  lrc
@summary 歌词文件（.lrc）解析与查找
@version 1.0
@date    2026.10.23

=== 支持的格式 ===
  [00:12.34]歌词            两位小数 = 百分秒
  [00:12.345]歌词           三位小数 = 毫秒
  [00:12:34]歌词            冒号分隔的变体（部分老播放器）
  [00:12.34][01:20.00]歌词  一行挂多个时间戳（副歌复用同一句）
  [ti:标题] [ar:歌手] [al:专辑] [by:制作] [offset:+500]  元信息

=== 编码 ===
固件里没有可用的 iconv（gb2utf8 已从注册表移除），只能按 UTF-8 读。
读到非法 UTF-8 序列时 lyric.gbk = true，UI 提示用户转码，
而不是把乱码刷满整屏。

=== 为什么时间要减 offset ===
LRC 约定 [offset:+500] 表示"歌词整体提前 500ms"，
即展示时刻 = 时间戳 - offset。反过来加会让整首歌词偏 1 秒。
]]

local fx = require "fx_core"

local M = {}

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--[[mm / ss / frac → 毫秒
1 位小数 = 十分之一秒，2 位 = 百分秒，3 位以上按小数秒算
]]
local function to_ms(mm, ss, frac)
    local ms = (tonumber(mm) or 0) * 60000 + (tonumber(ss) or 0) * 1000
    if frac and frac ~= "" then
        local n = #frac
        local v = tonumber(frac) or 0
        if n == 1 then
            ms = ms + v * 100
        elseif n == 2 then
            ms = ms + v * 10
        else
            ms = ms + v * (1000 / (10 ^ n))
        end
    end
    return math.floor(ms + 0.5)
end

--[[解析歌词文本
@param string text 歌词文件全文
@return table lyric { lines = { {t=起, e=止, s=文本}, ... }, meta = {...}, gbk = bool }
        lines 按时间升序；没有任何有效歌词行时返回 nil, 原因
]]
function M.parse(text)
    if type(text) ~= "string" or #text == 0 then return nil, "空文件" end

    -- 去掉 UTF-8 BOM，否则第一行 [ti:...] 会解析失败
    if text:sub(1, 3) == "\239\187\191" then text = text:sub(4) end

    local raw = {}
    local meta = {}
    local order = 0

    for line in text:gmatch("[^\r\n]+") do
        local rest = line
        local stamps = nil        -- 本行所有时间戳

        -- 逐个吃掉行首的 [mm:ss.xx]，剩下的才是正文
        while true do
            local mm, ss, frac, tail = rest:match("^%s*%[(%d+)%:(%d+)[%.:]?(%d*)%]%s*(.*)$")
            if not mm then break end
            stamps = stamps or {}
            stamps[#stamps + 1] = to_ms(mm, ss, frac)
            rest = tail
        end

        if stamps then
            local body = trim(rest)
            if body ~= "" then
                for k = 1, #stamps do
                    order = order + 1
                    raw[#raw + 1] = { t = stamps[k], s = body, n = order }
                end
            end
        else
            -- 没有任何时间戳：可能是 [ti:xxx] 这类元信息
            local k, v = line:match("^%s*%[(%a+)%:(.-)%]%s*$")
            if k then meta[k:lower()] = trim(v) end
        end
    end

    if #raw == 0 then return nil, "没有时间戳行" end

    -- offset 带正负号
    -- 注意 gsub 返回两个值，必须用括号包起来再交给 tonumber，
    -- 否则第二个返回值（替换次数）会被当成进制传入：tonumber(s, 3) → base out of range
    local off = tonumber(((tostring(meta.offset or "0")):gsub("%s+", ""))) or 0

    table.sort(raw, function(a, b)
        if a.t == b.t then return a.n < b.n end
        return a.t < b.t
    end)

    -- 去重：同一时刻同一句被重复标记的歌词文件很常见
    local lines = {}
    local prev_t, prev_s = -1, nil
    for i = 1, #raw do
        local it = raw[i]
        local t = it.t - off
        if t < 0 then t = 0 end
        if not (t == prev_t and it.s == prev_s) then
            lines[#lines + 1] = { t = t, s = it.s }
            prev_t, prev_s = t, it.s
        end
    end

    -- 结束时刻 = 下一行开始；最后一行给 6 秒，否则高亮条会瞬间跑完
    for i = 1, #lines do
        local nxt = lines[i + 1]
        local e = nxt and nxt.t or (lines[i].t + 6000)
        if e <= lines[i].t then e = lines[i].t + 1200 end
        lines[i].e = e
    end

    return {
        lines = lines,
        meta = meta,
        gbk = not fx.is_utf8(text),
    }
end

--[[从文件加载歌词（阻塞几十毫秒，请在音频任务里调用）
@param string path
@return table lyric 或 nil, 原因
]]
function M.load(path)
    if not path then return nil, "无路径" end
    local f = io.open(path, "rb")
    if not f then return nil, "打不开" end
    -- 歌词文件正常几 KB；上限 96KB，防止误读到别的大文件把内存吃光
    local text = f:read(96 * 1024)
    f:close()
    if not text or #text == 0 then return nil, "内容为空" end
    local ly, err = M.parse(text)
    if not ly then return nil, err end
    ly.path = path
    return ly
end

--[[为某首歌找同名歌词
查找顺序：歌曲同目录 → /sd/lyric/ → /sd/lrc/ → /sd/lyrics/
@param string audio_path 例如 "/sd/music/某歌.mp3"
@return string 歌词路径 或 nil
]]
function M.find(audio_path)
    if type(audio_path) ~= "string" then return nil end
    local dir, name = audio_path:match("^(.*/)([^/]+)$")
    if not name then dir, name = "/", audio_path end
    local base = name:gsub("%.[%w]+$", "")

    local cand = {
        dir .. base .. ".lrc",
        dir .. base .. ".LRC",
        dir .. base .. ".Lrc",
        "/sd/lyric/" .. base .. ".lrc",
        "/sd/lrc/" .. base .. ".lrc",
        "/sd/lyrics/" .. base .. ".lrc",
    }
    for _, p in ipairs(cand) do
        if io.exists(p) then return p end
    end
    return nil
end

--[[按播放位置找当前行号（线性推进 + 双向回退，点歌/跳播都能跟上）
@param table lyric
@param number ms 位置毫秒
@param number hint 上次行号（可省）
@return number 行号（1 起），无歌词返回 0
]]
function M.index_at(lyric, ms, hint)
    if not lyric or not lyric.lines then return 0 end
    local lines = lyric.lines
    local n = #lines
    if n == 0 then return 0 end

    local i = hint or 1
    if i < 1 then i = 1 elseif i > n then i = n end
    ms = ms or 0

    -- 绝大多数情况是往后走
    while i < n and lines[i + 1].t <= ms do i = i + 1 end
    -- 切歌/重新起播时往回退
    while i > 1 and lines[i].t > ms do i = i - 1 end

    -- 还没到第一句：返回 0，UI 显示"前奏"
    if ms < lines[1].t then return 0 end
    return i
end

return M
