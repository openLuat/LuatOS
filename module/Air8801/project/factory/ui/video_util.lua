--[[
@module  video_util
@summary 视频素材工具（HZV 容器嗅探 / 帧尺寸读取 / 双落点查找 / 播放器创建）—— 桌面与全屏播放页共用
@version 1.0
@date    2026.11.23

=== 本平台约束 ===
Air1101 / CCM4211 上视频不保证有编码器支持，且素材可能放在脚本区或 SD 卡，因此：

1. 无功放（PA）。air8801_config.lua 只有 buzzer 段、没有 audio 段，本模块不控 PA 引脚。
2. 素材分散查找：按「/luadb/ → /sd/video/ → /sd/ → /」顺序找第一个存在的，
   插卡和不插卡都能用。
3. 先问 available()：airui.video 由固件按需编入，调用方不要直接建播放器
   （未编入时只会在日志里刷一堆失败）。

=== 只播 HZV ===
素材是 MJPEG 逐帧 + 内嵌 MP3 音轨，走 airui.video 的 videoplayer 后端。
**不支持缩放**：控件 w/h 必须等于素材帧尺寸，否则组件会强制改回素材尺寸，
表现为控件溢出容器、画面被切掉一块。所以帧尺寸口径必须只有这一处实现。

@api video_util.available()                    固件是否编入 airui.video（boolean）
@api video_util.find_asset(name)               按落点顺序找素材，返回第一个存在的路径或 nil
@api video_util.guess_format(path)             是否 HZV："hzv" | nil
@api video_util.read_dimensions(path)          w, h；读不到返回 nil
@api video_util.frame_size(path, def_w, def_h) w, h；读不到时用兜底值
@api video_util.check_frame(path)              ok, w, h, fmt, reason
@api video_util.create_player(path, o)         创建嵌入式播放器，失败返回 nil
@api video_util.after_release(fn)              释放窗口内延后执行
@api video_util.cancel_pending()               丢掉待建动作
]]

local M = {}

-- ==================== 能力探测 ====================

--[[固件是否编入 airui.video

Air1101 底包按需裁剪，airui 的 label/container 在，不等于 video 也在。
未编入时 airui.video 是 nil，直接调用会抛 "attempt to call a nil value"，
所以入口统一先问这里。]]
function M.available()
    -- 只看 airui.video 本身：某些底包把 airui 导出成 userdata，再要求 airui 是 table 会误判
    return airui and airui.video
end

-- ==================== 素材落点 ====================

--[[素材搜索顺序

/luadb/       脚本区（随 Luatools 一起烧进去，不插卡也能播）
/sd/video/    卡上的分类目录（推荐给客户自己拷片用）
/sd/          卡根目录
/             内置根文件系统（8801 只有 256KiB，实际放不下视频，留作兜底）

注意挂载点必须带尾斜杠：VFS 按前缀匹配挂载点，"/sd" 匹配不到 "/sd/" 这个挂载。
]]
M.SEARCH_DIRS = { "/luadb/", "/sd/video/", "/sd/", "/" }

--[[按落点顺序找素材
@param name string 不带目录的文件名，如 "fruit.hzv"
@return string|nil 第一个存在的完整路径]]
function M.find_asset(name)
    if type(name) ~= "string" or name == "" then return nil end
    for _, dir in ipairs(M.SEARCH_DIRS) do
        local p = dir .. name
        if io.exists(p) then return p end
    end
    return nil
end

--[[列出所有落点里实际存在的素材（供诊断：到底哪个目录有东西）
@return table 每项 { path=, size= }]]
function M.scan_assets()
    local out, seen = {}, {}
    for _, dir in ipairs(M.SEARCH_DIRS) do
        local ok, list = pcall(io.lsdir, dir, 100, 0)
        if ok and type(list) == "table" then
            for _, f in ipairs(list) do
                -- 底包返回 {name=,size=,type=}；个别固件直接给字符串，两种都认
                local name = type(f) == "table" and f.name or tostring(f)
                local is_dir = type(f) == "table" and f.type == 1
                if type(name) == "string" and not is_dir
                    and name:lower():sub(-4) == ".hzv" then
                    local p = dir .. name
                    if not seen[p] then
                        seen[p] = true
                        out[#out + 1] = {
                            path = p,
                            size = type(f) == "table" and f.size or nil,
                        }
                    end
                end
            end
        end
    end
    return out
end

-- ==================== HZV 容器 ====================

--[[判断素材是不是 HZV：先看魔数，再看扩展名

魔数优先：素材被改名后仍能正确解码。返回 nil 的素材由调用方按
「无法播放该文件」处理，不拿去解码器白试一轮。]]
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

HZV v1: 前 4 字节 "HZV1"，文件偏移 68 / 70 处各一个 uint16 宽、高
        （Lua 下标从 1 起，所以是 byte(69)/byte(70) 与 byte(71)/byte(72)）
        固定头 128 字节，宽高在 72 字节以内

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

兜底值必须与该页面的布局基准一致：给错了不会「拉伸画面」，
只会让控件溢出容器、把画面切掉一块。]]
function M.frame_size(path, def_w, def_h)
    local w, h = M.read_dimensions(path)
    if w and h then return w, h end
    return def_w, def_h
end

-- ==================== 分辨率上限 ====================

--[[源分辨率上限（含）：超出拒绝起播

hzv：videoplayer 后端（tjpgd 软解或平台硬解），支持到 1024×600。
只拦「读到了尺寸且超限」的确定情况；尺寸读不出来时交回解码器去试。]]
local FRAME_MAX = {
    hzv = { w = 1024, h = 600 },
}

function M.max_frame_size(fmt)
    local lim = FRAME_MAX[fmt]
    if not lim then return 0, 0 end
    return lim.w, lim.h
end

--[[按格式上限校验素材
@return ok, w, h, fmt, reason（reason 可直接给用户看）]]
function M.check_frame(path)
    local fmt = M.guess_format(path)
    local w, h = M.read_dimensions(path)
    local max_w, max_h = M.max_frame_size(fmt)
    if w and h and max_w > 0 and (w > max_w or h > max_h) then
        return false, w, h, fmt, string.format(
            "%s 素材 %d×%d 超过该格式上限 %d×%d，无法播放",
            string.upper(fmt or "?"), w, h, max_w, max_h)
    end
    return true, w, h, fmt, nil
end

-- ==================== 播放器会话释放窗口 ====================

--[[stop/destroy 到下一次 create 必须留出释放时间

播放器的音频会话从 stop() 到 C 侧打出 `dac_sound audio v2 request end` 实测要
400~530ms。这段窗口里再起一路新会话去 luat_audio_request_play_stream，会跟还没
释放完的旧会话抢：轻则新会话的 DAC 驱动起不来，重则新会话阻塞在音频请求上、
解码线程一帧不出。

页面的「停旧 → 建新」都在同一次回调里做，中间让不出时间，所以收口到这里：
stop/destroy 打开释放窗口，窗口没关就把建播放器的动作延后到窗口结束再做。
延后用定时器而不是 sys.wait —— 起播发生在点击回调里，不在协程上下文。]]
local RELEASE_MS = 700          -- 释放窗口长度（实测 400~530ms，留余量）
local release_timer = nil       -- 非 nil = 释放窗口未关
local pending_create = nil      -- 窗口结束后要执行的建播放器动作

local function mark_release()
    if release_timer then sys.timerStop(release_timer) end
    release_timer = sys.timerStart(function()
        release_timer = nil
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
function M.cancel_pending()
    pending_create = nil
end

--[[给播放器补一层会话收尾：stop/destroy 顺带打开释放窗口
接口面与裸对象一致（:play/:pause/:stop/:destroy）。]]
local function wrap_release(v)
    local closed = false
    local function bye()
        if closed then return end      -- stop + destroy 连着调也只记一次
        closed = true
        mark_release()
    end
    return {
        play = function(_, ...) return v:play(...) end,
        pause = function(_, ...) return v:pause(...) end,
        stop = function(_, ...)
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

--[[堆剩余快照（只在创建失败时调用）]]
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

--[[创建嵌入式播放器（唯一入口）

@table o
  @userdata o.parent    airui 父容器
  @number   o.x,o.y     画面摆放位置（相对 parent）
  @number   o.w,o.h     画面尺寸（必须等于素材帧尺寸，不支持缩放）
  @boolean  o.loop      是否循环
  @function o.on_complete 单次播完回调
@return table|nil 播放器对象，失败 nil
]]
function M.create_player(path, o)
    o = o or {}

    if not M.available() then
        log.warn("video_util", "本固件未编入 airui.video",
                 "airui=", type(airui), "video=", type(airui and airui.video))
        return nil
    end

    local size_ok, _w, _h, fmt, reason = M.check_frame(path)
    if not size_ok then
        log.warn("video_util", reason or "素材超过格式上限，拒绝起播", path)
        return nil
    end
    if fmt ~= "hzv" then
        log.warn("video_util", "只支持 HZV 素材", path)
        return nil
    end

    local vcfg = {
        parent = o.parent,
        x = o.x, y = o.y, w = o.w, h = o.h,
        src = path, format = fmt,
        decode_mode = "hw",
        loop = o.loop and true or false,
        auto_play = true,
        backend = "videoplayer",
    }
    if o.on_complete then vcfg.on_complete = o.on_complete end

    --[[创建失败逐档降级重试

    C 端这条路全程静默：建不出来只返回 nil（不抛错），硬解回退、起播被拒
    也都不打日志。分档试，每档失败都记一行原因：
      1) 硬解 → 2) 软解 → 3) 建好再单独起播（区分「建不出来」与「起播被拒」）
    ]]
    local attempts = {
        { decode_mode = "hw", auto_play = true },
        { decode_mode = "sw", auto_play = true },
        { decode_mode = "hw", auto_play = false },
        { decode_mode = "sw", auto_play = false },
    }
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
            mark_release()
        else
            log.warn("video_util", "airui.video 返回 nil", path, "fmt=", fmt,
                     "decode=", a.decode_mode, mem_snapshot())
        end
    end
    if not v then
        local need_kb = 0
        if type(_w) == "number" and type(_h) == "number" then
            need_kb = math.floor(_w * _h * 2 / 1024)
        end
        log.warn("video_util", "播放器创建放弃", path, "mem=", mem_snapshot(),
                 "单块需", need_kb .. "KB")
        mark_release()
        return nil
    end
    return wrap_release(v)
end

return M
