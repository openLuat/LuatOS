--[[
@module  hzv_player
@summary HZV 视频播放引擎模块（对外提供扫描/打开/播放控制/统计接口）
@version 1.0
@date    2026.10.26
@author  拓毅恒
@usage
本文件为 HZV 播放引擎模块，把"播放一个 HZV 文件"需要的东西收成一个模块，
界面层（hzv_ui.lua）和无界面自动演示（start_auto）都只是它的调用方。

核心业务逻辑：
1、scan       ：扫描 /sd 与 /luadb 下的 *.hzv（可只扫指定目录），返回文件列表给界面层展示；
2、open       ：探测 HZV 真实分辨率 → 在指定矩形区域内居中创建 airui.video 组件 → 开功放 → 播放；
3、play/pause/stop/destroy：播放控制，暂停/停止时同步关闭功放 PA，避免底噪；
4、stats      ：读取 video:get_stats()，供界面显示帧率、音视频偏差、丢帧、音频欠载；
5、start_auto ：无触摸屏时使用，打开第一个素材后一直循环播放（定期打印统计）。

音画同步说明（为什么这里没有定时器）：
HZV 的音画同步由底层引擎完成（Audio V2 用已播采样数做主时钟），Lua 侧不需要设置 interval，
也不需要定时调 step()/skip()，只负责 play/pause/stop 三个控制动作和读统计。

关于 stop() 之后不能直接 play()：
AirUI 的 video 组件 stop() 会把音频时钟清零并把播放头拨回首帧，但视频读包位置在部分固件上
没有同步拨回（2026.10 的 Air1603 固件实测如此），此时直接 play() 会出现"音频从头播、视频停在
文件尾部不再出帧"的假死（日志表现为 fps=0、总帧数不再增长、av_delta_ms 突然变成上万毫秒）。
本模块的处理：stop() 打一个 stopped 标记，之后的 play() 改为重新 open() 组件，等价于从头播。

对外接口：
1、hzv_player.scan()             ：返回 { {path=, name=, size=}, ... }
2、hzv_player.open(path, rect)   ：打开并播放，rect={x=,y=,w=,h=} 为播放区域，nil 表示整屏居中
3、hzv_player.play() / pause() / stop() / destroy()
4、hzv_player.stats()            ：返回统计表，无组件时返回 nil
5、hzv_player.current()          ：返回当前播放的文件路径
6、hzv_player.start_auto()       ：启动无界面自动演示任务
7、hzv_player.set_volume(vol)    ：设置软件音量，vol 为 0~100，nil 表示用板型默认值
8、hzv_player.get_volume()       ：查询当前软件音量
9、hzv_player.volume_step(delta) ：在当前音量上加减（界面"音量+/-"按钮用），做 0~100 限幅
]]

local hzv_hw = require "hzv_hw"
local lcd_app = require "lcd_app"
local sd_app = require "sd_app"

local M = {}

-- 扫描目录：TF 卡优先，内置文件系统兜底；两个目录都会扫，界面层统一展示
local SCAN_DIRS = { "/sd", "/luadb" }

-- 界面左侧目录切换按钮的排列顺序：先内置存储，再 TF 卡
local SOURCE_DIRS = { "/luadb", "/sd" }

-- 默认素材文件名
-- 本文件随 demo 一起放在目录里，用 Luatools 烧录整个工程目录时会打包进 luadb 分区，
-- 运行时路径就是 /luadb/dont_sick.hzv（480x320 / 15FPS / MP3 32kHz 单声道，约 2.9MB）
-- 素材文件放 TF 卡根目录也能识别（/sd/dont_sick.hzv），TF 卡优先
local DEFAULT_FILE = "dont_sick.hzv"

-- 单次扫描返回的最大文件数（1024x600 屏上一屏最多显示 8 个，留点余量）
local SCAN_MAX = 50

-- 内置文件系统（luadb）容量上限，用于排查"素材烧不进去/放不下"：
--   Air1601/Air1602 的 101 号固件：文件系统 3008KB + 脚本区 1024KB
--   Air1601/Air1602 的 102 号固件：文件系统 1536KB + 脚本区 4096KB
-- 默认素材 dont_sick.hzv 约 2969KB，几乎占满 101 号固件的 fs 分区，所以只能配 101 号固件；
-- 素材超过 LUADB_WARN_KB 就在日志里提示改用 TF 卡
local LUADB_FS_KB   = 3008
local LUADB_WARN_KB = 2600

-- 自动演示模式下打印统计信息的间隔，单位毫秒
-- 无触摸屏时不做任何暂停/停止动作，素材按 loop=true 连续循环播放，这里只负责定期打日志
local T_STATS  = 2000

-- 创建视频组件失败时的重试次数与间隔（例如素材还没放进 TF 卡）
local CREATE_RETRY      = 5
local CREATE_RETRY_WAIT = 5000

-- 当前视频组件与状态
local video    = nil   -- airui.video 组件对象
local cur_path = nil   -- 当前播放的文件路径
local cur_rect = nil   -- 当前播放区域
local stopped  = false -- 是否刚执行过 stop()（此时 play() 必须重新 open，见文件头说明）
local cur_volume = nil -- 最近一次设置成功的软件音量，界面音量按钮用它做起点

--[[
按板型设置喇叭软件音量；

@api hzv_player.set_volume(vol)
@summary 调用 Audio V2 的通道软件音量接口；固件不支持时只打印告警，不影响播放
@param number vol 0~100，100 为原始音量（不衰减），0 为静音；nil 表示用板型默认值
@return boolean 设置成功返回 true
]]
function M.set_volume(vol)
    vol = vol or hzv_hw.volume()
    -- 音量统一用 0~100 的刻度（界面显示、按钮步进都是这个范围）。
    -- audio_v2.soft_volume 支持 0~100
    if vol < 0 then
        vol = 0
    elseif vol > 100 then
        vol = 100
    end
    if not rawget(_G, "audio_v2") or not audio_v2.soft_volume then
        log.warn("hzv_player", "固件不支持 audio_v2.soft_volume，音量维持固件默认值")
        return false
    end
    local ok = audio_v2.soft_volume(vol)
    if ok then
        -- 记录当前音量，界面的"音量+/-"按钮和状态栏要用它做起点
        cur_volume = vol
        log.info("hzv_player", "软件音量设置", vol, "/100")
    else
        log.warn("hzv_player", "软件音量设置失败", vol)
    end
    return ok
end

--[[
查询当前软件音量；

@api hzv_player.get_volume()
@summary 返回最近一次设置成功的软件音量；还没设置过时返回板型默认值
@return number 0~100 的软件音量
]]
function M.get_volume()
    return cur_volume or hzv_hw.volume()
end

--[[
在当前音量基础上加减；

@api hzv_player.volume_step(delta)
@summary 界面上的"音量+/-"按钮调用它，逐级加减并做 0~100 限幅
@param number delta 正数加音量，负数减音量，界面上每次 5
@return number 本次生效后的音量值

@usage
hzv_player.volume_step(5)    -- 音量 +5
hzv_player.volume_step(-5)   -- 音量 -5
]]
function M.volume_step(delta)
    local vol = M.get_volume() + (delta or 0)
    -- 音量刻度 0~100，越界直接夹住
    if vol < 0 then
        vol = 0
    elseif vol > 100 then
        vol = 100
    end
    M.set_volume(vol)
    return vol
end

--[[
扫描指定目录下的 .hzv 文件；

@api hzv_player.scan_dir(dir)
@summary 列出目录下一层的 *.hzv 文件，目录不存在或读取失败时静默跳过
@param string dir 目录路径
@param table list 结果收集表（会被追加）
@return nil
]]
local function scan_dir(dir, list)
    -- /sd 没挂载时不要再费力去 ls
    if dir == "/sd" and not sd_app.is_mounted() then
        return
    end

    --[[
    不同文件系统的挂载前缀写法不一样：
      luadb 注册的前缀是 "/luadb/"（带尾斜杠，见 io.lsmount() 的打印）
      fatfs 注册的前缀是 "/sd"   （不带尾斜杠）
    VFS 用 strncmp(前缀, 路径, strlen(前缀)) 匹配挂载点，所以对 luadb 直接传 "/luadb"
    会少一个字符匹配失败（getmount 返回 NULL → lsdir 拿不到任何条目），必须两种写法都试。
    ]]
    local candidates = { dir .. "/", dir }
    local data = nil
    for _, probe in ipairs(candidates) do
        local ret, list_data = io.lsdir(probe, SCAN_MAX, 0)
        if ret and type(list_data) == "table" and #list_data > 0 then
            data = list_data
            break
        end
    end
    if not data then
        -- 两种写法都拿不到条目：通常是空目录；如果是"明明有文件却列不出来"，
        -- 这行 debug 日志配合 io.lsmount() 的打印就能看出挂载前缀对不对
        log.debug("hzv_player", "目录没有可列出的 HZV 条目", dir)
        return
    end

    for _, item in ipairs(data) do
        -- type == 0 表示普通文件
        if item.type == 0 and item.name then
            -- luadb 的条目名就是纯文件名；个别文件系统可能返回带路径的项，统一取最后一段
            local raw = tostring(item.name)
            local name = raw:match("([^/\\]+)$") or raw
            if name:lower():sub(-4) == ".hzv" then
                local path = dir .. "/" .. name
                -- 再确认一次真的能打开（避免列表里有、点开却报文件不存在）
                if not io.exists(path) then
                    -- 兜底：有的文件系统条目名本身就带完整路径
                    if io.exists(raw) then
                        path = raw
                    else
                        log.warn("hzv_player", "跳过打不开的条目", raw)
                        path = nil
                    end
                end
                if path then
                    list[#list + 1] = {
                        path = path,
                        name = name,
                        size = io.fileSize(path) or item.size or 0,
                    }
                end
            end
        end
    end
end

-- 列表排序用的比较函数（用具名函数，避免匿名函数字面量）
local function sort_by_path(a, b)
    return a.path < b.path
end

--[[
把默认素材排到列表第一位；

@api hzv_player.move_default_first(list)
@summary 列表里如果有 dont_sick.hzv，就把它挪到第一位，其余按路径名排序，
          这样界面默认选中项和自动演示的起始素材都固定是它
@param table list 扫描结果
@return nil
]]
local function move_default_first(list)
    -- 其余素材先按路径排序，保证每次上电顺序一致
    table.sort(list, sort_by_path)

    for i = 1, #list do
        if list[i].name == DEFAULT_FILE then
            if i ~= 1 then
                local f = table.remove(list, i)
                table.insert(list, 1, f)
            end
            return
        end
    end
end

--[[
扫描所有素材目录；

@api hzv_player.scan()
@summary 依次扫描 /sd 与 /luadb，返回 HZV 文件列表；默认素材 dont_sick.hzv 排在第一位
@return table 文件列表，每个元素为 {path=, name=, size=}

@usage
for _, f in ipairs(hzv_player.scan()) do
    log.info("hzv", f.name, f.size)
end
]]
function M.scan(only_dir)
    local list = {}
    if only_dir then
        -- 只扫指定目录（界面上"内置存储 / TF 卡"切换时用）
        scan_dir(only_dir, list)
    else
        for _, dir in ipairs(SCAN_DIRS) do
            scan_dir(dir, list)
        end
    end
    move_default_first(list)
    log.info("hzv_player", "扫描到 HZV 文件数量", #list,
        (#list > 0) and ("默认播放 " .. list[1].path) or "",
        only_dir and ("目录 " .. only_dir) or "全部目录")
    return list
end

--[[
查询可切换的素材目录；
@api hzv_player.sources()
@summary 给界面的目录切换按钮用，返回目录路径、显示名、当前是否可用（TF 卡是否挂载）
@return table { {dir=, label=, ready=}, ... }
]]
function M.sources()
    local ret = {}
    for _, dir in ipairs(SOURCE_DIRS) do
        local item = {
            dir   = dir,
            label = (dir == "/sd") and "TF 卡" or "内置存储",
            ready = true,
        }
        if dir == "/sd" then
            item.ready = sd_app.is_mounted()
        end
        ret[#ret + 1] = item
    end
    return ret
end

--[[
探测 HZV 真实分辨率；

@api hzv_player.probe_size(path)
@summary 用 videoplayer 打开文件读一次视频信息，失败返回 nil（不影响后面按区域创建）
@param string path HZV 文件路径
@return number 视频宽度，探测失败返回 nil
@return number 视频高度，探测失败返回 nil
]]
-- 真正做一次"打开-读信息-关闭"的函数（具名，供 pcall 调用）
local function probe_once(path)
    local player = videoplayer.open(path)
    if not player then
        return nil
    end
    local info = videoplayer.info(player)
    videoplayer.close(player)
    if info and info.width and info.height then
        return info.width, info.height
    end
    return nil
end

local function probe_size(path)
    -- 固件没编 videoplayer 时全局变量不存在，直接跳过探测
    if not rawget(_G, "videoplayer") or not videoplayer.open then
        return nil
    end

    -- 探测失败只是拿不到尺寸，不影响播放，所以用 pcall 兜住异常
    local ok, vw, vh = pcall(probe_once, path)
    if ok and vw and vh then
        log.info("hzv_player", "探测到视频分辨率", vw .. "x" .. vh)
        return vw, vh
    end
    log.warn("hzv_player", "视频分辨率探测失败，按播放区域尺寸创建组件")
    return nil
end

--[[
销毁当前视频组件；

@api hzv_player.destroy()
@summary 销毁组件并关闭功放，切换素材或退出界面时调用
@return nil
]]
-- 销毁组件本体（具名，供 pcall 调用，组件已失效时不至于把任务带崩）
local function destroy_video(v)
    v:destroy()
end

function M.destroy()
    local had_video = (video ~= nil)
    if video then
        pcall(destroy_video, video)
        video = nil
    end
    -- 只有确实在播过才需要关功放，避免还没播就打印"功放关闭"
    if had_video then
        hzv_hw.pa_set(false)
    end
    cur_path = nil
    stopped = false
end

--[[
打开并播放一个 HZV 文件；

@api hzv_player.open(path, rect)
@summary 在指定矩形区域内居中创建视频组件并开始播放，重复调用会自动重建组件
@param string path HZV 文件路径
@param table rect 播放区域 {x=,y=,w=,h=}，nil 表示按整屏居中
@return boolean 打开成功返回 true

@usage
hzv_player.open("/luadb/dont_sick.hzv", { x = 300, y = 64, w = 700, h = 470 })
]]
function M.open(path, rect)
    if not path then
        log.error("hzv_player", "open 参数为空")
        return false
    end
    if not io.exists(path) then
        log.error("hzv_player", "文件不存在", path)
        return false
    end

    -- 打印素材大小：内置文件系统（luadb）只有 3008KB（101 号固件），
    -- 默认素材已经用到 2969KB，素材再大就只能放 TF 卡，所以把大小直接打进日志方便排查
    if io.fileSize then
        local fsize = io.fileSize(path)
        if fsize then
            local kb = math.floor(fsize / 1024)
            log.info("hzv_player", "素材大小", path, kb .. "KB")
            if path:sub(1, 6) == "/luadb" and kb > LUADB_WARN_KB then
                log.warn("hzv_player", "素材接近内置文件系统上限",
                    "luadb 分区约 " .. LUADB_FS_KB .. "KB（101 号固件），建议压小素材或改放 TF 卡")
            end
        end
    end

    -- 换片时先销毁旧组件，避免多个解码通道同时占用内存
    M.destroy()

    local screen_w, screen_h = lcd_app.get_size()
    -- 播放区域：默认整屏
    cur_rect = rect or { x = 0, y = 0, w = screen_w, h = screen_h }

    -- 视频尺寸：优先用探测到的真实值，探测不到就铺满播放区域
    local vw, vh = probe_size(path)
    vw = vw or cur_rect.w
    vh = vh or cur_rect.h
    -- 视频不能超出播放区域，超了就按区域裁剪上限（组件本身不支持缩放）
    vw = math.min(vw, cur_rect.w)
    vh = math.min(vh, cur_rect.h)

    -- 在播放区域内居中
    local vx = cur_rect.x + math.max(0, math.floor((cur_rect.w - vw) / 2))
    local vy = cur_rect.y + math.max(0, math.floor((cur_rect.h - vh) / 2))

    -- 父对象：界面模式把 ui.bg 传进来（rect.parent），保证视频和界面同层；
    -- 早期 AirUI 没有导出 airui.screen，此时传 nil，由 AirUI/LVGL 自己用当前屏
    local parent = cur_rect.parent or airui.screen

    video = airui.video({
        parent      = parent,
        x           = vx,
        y           = vy,
        w           = vw,
        h           = vh,
        src         = path,
        format      = "hzv",        -- HZV 容器，支持音视频同步播放
        backend     = "videoplayer",-- 走 videoplayer 后端（HZV reader + JPEG 硬解 + Audio V2）
        decode_mode = "hw",         -- 硬解优先，拿不到硬解时底层会回退软解
        loop        = true,         -- 循环播放
        auto_play   = false,        -- 由本模块控制播放时机，先开 PA 再 play
        -- 注意：HZV 会优先使用容器里的帧时长，Lua 侧不需要设置 interval，也不需要 step()/skip()
    })

    if not video then
        log.error("hzv_player", "创建视频组件失败", path,
            "请确认素材存在、固件已开启 LUAT_USE_AIRUI / VIDEOPLAYER / HZV / JPEG_DECODE_HW / AUDIO_V2")
        return false
    end

    cur_path = path
    stopped = false
    log.info("hzv_player", "视频组件创建成功", path, "位置", vx, vy, "尺寸", vw .. "x" .. vh)

    -- HZV 音轨走 Audio V2，音量由通道软件音量控制；不设置就是固件默认的 100（不衰减），
    -- 10 寸整机板载喇叭在这个值下普遍偏大，这里按板型默认值（hzv_hw.volume()）设一次
    M.set_volume()

    -- 先打开功放再播放，避免第一帧音频被 PA 建立时间吞掉
    hzv_hw.pa_set(true)
    video:play()

    -- 注意：这里不点背光。背光统一由 main.lua 在"界面画好 + wait(200)"之后点亮，
    -- 保持只有一个点灯入口，开机才不会出现"背光先亮、画面还没出来"的花屏/黑屏。
    -- （换片时背光早已点亮，无需再操作；lcd_app.backlight_on() 本身也是幂等的）
    return true
end

--[[
继续/开始播放；

@api hzv_player.play()
@summary 打开功放并播放当前组件
@return nil
]]
function M.play()
    if not video then
        return
    end
    -- stop() 之后引擎只把音频时钟拨回 0，视频读包位置不回 0，直接 play() 会假死，
    -- 所以这里改成重新打开组件（等价于从头播一遍）
    if stopped then
        log.info("hzv_player", "stop 之后播放，重新打开组件")
        M.open(cur_path, cur_rect)
        return
    end
    hzv_hw.pa_set(true)
    video:play()
    log.info("hzv_player", "video:play")
end

--[[
暂停播放；

@api hzv_player.pause()
@summary 暂停视频调度和音频播放，同时关闭功放避免底噪
@return nil
]]
function M.pause()
    if not video then
        return
    end
    video:pause()
    hzv_hw.pa_set(false)
    log.info("hzv_player", "video:pause")
end

--[[
停止播放并回到初始状态；

@api hzv_player.stop()
@summary 停止播放，组件保留，下次 play 从头开始
@return nil
]]
function M.stop()
    if not video then
        return
    end
    video:stop()
    hzv_hw.pa_set(false)
    stopped = true
    log.info("hzv_player", "video:stop")
end

--[[
读取播放统计信息；

@api hzv_player.stats()
@summary 读取 video:get_stats()，供界面显示；老固件没有该接口时返回 nil
@return table 统计表或 nil
]]
-- 读一次组件统计（具名，供 pcall 调用）
local function read_stats(v)
    return v:get_stats()
end

function M.stats()
    if not video then
        return nil
    end
    -- get_stats 是 AirUI V1.2.6 之后新增的接口，老固件没有，用 pcall 兼容
    local ok, stats = pcall(read_stats, video)
    if ok then
        return stats
    end
    return nil
end

--[[
查询当前播放的文件路径；

@api hzv_player.current()
@summary 返回当前正在播放的 HZV 路径，没有播放时返回 nil
@return string 文件路径或 nil
]]
function M.current()
    return cur_path
end

--[[
打印一次播放统计到日志；

@api hzv_player.log_stats()
@summary 自动演示模式下定时打印帧率/音视频偏差/丢帧/音频欠载
@return nil
]]
local function log_stats()
    local stats = M.stats()
    if not stats then
        return
    end
    log.info("hzv_player", "播放统计",
        "fps=" .. tostring(stats.fps),
        "总帧数=" .. tostring(stats.total_frames),
        "音视频偏差(ms)=" .. tostring(stats.av_delta_ms),
        "丢帧=" .. tostring(stats.dropped_frames),
        "音频欠载=" .. tostring(stats.audio_underruns),
        "时钟模式=" .. tostring(stats.clock_mode),
        "解码模式=" .. tostring(stats.decode_mode))
end

--[[
无界面自动演示任务；
@summary 找素材 → 打开 → 一直循环播放（组件 loop=true），期间只定期打印统计，不做暂停/停止
@return nil
]]
local function auto_task()
    log.info("hzv_player", "自动演示模式启动，当前板型", hzv_hw.name())

    -- 取第一个素材：scan() 已经把默认素材 dont_sick.hzv 排到第一位
    local files = M.scan()
    if #files == 0 then
        log.error("hzv_player", "没有可播放的 HZV 素材，任务退出",
            "请把 dont_sick.hzv 放进 TF 卡根目录，或随脚本烧进 /luadb")
        return
    end
    local path = files[1].path
    log.info("hzv_player", "自动演示素材", path)

    -- 打开（失败重试）
    local retry = 0
    while not M.open(path) and retry < CREATE_RETRY do
        retry = retry + 1
        log.warn("hzv_player", "打开失败，" .. CREATE_RETRY_WAIT .. "ms 后重试", retry .. "/" .. CREATE_RETRY)
        sys.wait(CREATE_RETRY_WAIT)
    end
    if not M.current() then
        log.error("hzv_player", "多次重试仍然无法创建视频组件，任务退出")
        return
    end

    -- 正常连续播放：open() 里已经 play()，组件 loop=true 会在片尾自动从头循环，
    -- 定期把帧率/丢帧/音画差打到日志里
    log.info("hzv_player", "开始循环播放", path, "内存信息", rtos.meminfo("sys"))
    while true do
        sys.wait(T_STATS)
        log_stats()
    end
end

--[[
启动无界面自动演示任务；

@api hzv_player.start_auto()
@summary 触摸不可用时由 main.lua 调用，创建自动演示任务后立即返回
@return nil
]]
function M.start_auto()
    sys.taskInit(auto_task)
end

return M
