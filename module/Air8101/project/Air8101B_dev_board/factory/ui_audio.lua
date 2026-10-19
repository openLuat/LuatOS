--[[
@module  ui_audio
@summary 音频播放：扫描 luadb / flash 里的音频文件，点一下播放（DAC + PA）
@version 1.0
@date    2026.10.16
@usage
    sys.publish("OPEN_AUDIO_WIN")

说明
1. 播放走扩展库 exaudio（与产测 AUDIO_TEST# 同一套：model=dac、pa_ctrl=config.hw.audio.pa_en）；
2. 支持 mp3 / wav / flac / amr / aac；文件要随脚本烧进 luadb 或在内置 flash 里；
3. 播放是异步的，完成事件 PLAY_DONE 回来才把状态改回"就绪"；本页只做单曲播放，不做播放列表；
4. 布局用设计坐标（基准 800×480）。
]]

local exwin = require "exwin"
local ui    = require "ui_kit"
local T     = require "ui_theme"

local C, F, S, G = T.COLOR, T.FONT, T.SCREEN, T.GAP
local DW = S.DW

local EXTS      = { mp3 = true, wav = true, flac = true, amr = true, aac = true, mp4 = false }
local SCAN_DIRS = { "/sd", "/little_flash", "/nand", "/luadb", "/" }
-- 列表排序用：先卡、再外挂 Flash、最后脚本区
local DIR_ORDER = { ["/builtin"] = 0, ["/sd"] = 1, ["/little_flash"] = 2, ["/nand"] = 3, ["/luadb"] = 4, ["/"] = 5 }

local BUILTIN_SOUNDS = {
    { name = "小星星", path = "/luadb/test_sound.wav", dir = "/builtin" },
}
local PER_PAGE  = 4
local ROW_H     = 50
local ROW_GAP   = 6
local LIST_Y    = 106

local win_id
local page
local state_label, list_box, pager_box
local vol_label

local files    = {}
local page_idx = 1
local playing  = nil      -- 正在播放的文件 path
local scanning = false    -- 是否正在扫卡（首帧先出界面，扫卡放后台）

local volume   = (((_G.project_config or {}).hw or {}).audio or {}).vol or 40
local ready    = false    -- exaudio 是否已 setup

local function fmt_name(n)
    return n or "?"
end

local function wav_peak_pct(path)
    if not path or not path:lower():match("%.wav$") then return nil end

    local fp = io.open(path, "rb")
    if not fp then return nil end

    local head = fp:read(4096) or ""
    local pos = head:find("data", 1, true)
    if not pos then
        fp:close()
        return nil
    end

    fp:seek("set", pos + 3)          -- 跳过 "data" + 4 字节长度，落在 PCM 数据起点
    local data = fp:read(65536)
    fp:close()
    if not data or #data < 2 then return nil end

    local max = 0
    for i = 1, #data - 1, 2 do
        local lo, hi = data:byte(i, i + 1)
        local v = lo + hi * 256
        if v >= 32768 then v = v - 65536 end
        if v < 0 then v = -v end
        if v > max then max = v end
    end
    return math.floor(max * 100 / 32768 + 0.5)
end

local function scan_files()
    local out, seen = {}, {}

    -- 内置测试音排最前面：按路径判断存在性，不依赖 lsdir
    for _, b in ipairs(BUILTIN_SOUNDS) do
        if io.exists(b.path) then
            seen[b.path] = true
            out[#out + 1] = { name = b.name, path = b.path, dir = b.dir }
        end
    end

    for _, dir in ipairs(SCAN_DIRS) do
        local ok, list = io.lsdir(dir, 100, 0)
        if ok and type(list) == "table" then
            for _, e in ipairs(list) do
                if e.type ~= 1 and e.name then
                    local ext = e.name:match("%.([%w]+)$")
                    ext = ext and ext:lower() or ""
                    local path = (dir == "/") and ("/" .. e.name) or (dir .. "/" .. e.name)
                    if EXTS[ext] and not seen[path] then
                        seen[path] = true
                        out[#out + 1] = { name = e.name, path = path, size = e.size, dir = dir }
                    end
                end
            end
        end
    end
    -- 排序：TF 卡 → NAND → 脚本区 → 内置 flash，同目录内按文件名
    table.sort(out, function(a, b)
        local oa, ob = DIR_ORDER[a.dir] or 9, DIR_ORDER[b.dir] or 9
        if oa ~= ob then return oa < ob end
        return a.name < b.name
    end)
    return out
end

local function set_state(text, color)
    if not state_label then return end
    state_label:set_text(text)
    pcall(function() state_label:set_color(color or C.TEXT) end)
end

-- ===== 播放 =====

local function ensure_ready()
    if ready then return true end

    local ok, exaudio = pcall(require, "exaudio")
    if not ok then
        set_state("扩展库 exaudio 不可用（固件未带）", C.DANGER)
        return false
    end

    local c = ((_G.project_config or {}).hw or {}).audio or {}

    local a = {
        model       = "dac",
        pa_ctrl     = c.pa_en,
        pa_on_level = c.pa_on_level or 1,
    }
    if c.dac_chl then a.dac_chl = c.dac_chl end     -- 0=AUD_LN(默认) / 1=AUD_LP / 2=双通道

    local ok2 = exaudio.setup(a)
    if not ok2 then
        set_state("音频初始化失败（查 PA_EN / 喇叭）", C.DANGER)
        log.error("ui_audio", "exaudio.setup 失败, pa_ctrl=", tostring(c.pa_en))
        return false
    end
    log.info("ui_audio", "exaudio.setup ok, pa_ctrl", tostring(c.pa_en),
        "pa_on_level", tostring(a.pa_on_level),
        "dac_chl", tostring(a.dac_chl or "默认0(AUD_LN)"))

    exaudio.vol(volume)
    log.info("ui_audio", "音量", volume)
    ready = true
    return true
end

local function play_file(f)
    if playing then
        page.toast("正在播放，先点「停止」")
        return
    end

    sys.taskInit(function()
        if not ensure_ready() then return end

        local exaudio = require "exaudio"
        playing = f.path
        set_state("播放中：" .. fmt_name(f.name), C.PRIMARY)
        log.info("ui_audio", "开始播放", f.path)

        -- 静音文件识别：能播完却没声音时，多半是文件本身没内容（录音时 MIC 没接/没开）
        local pct = wav_peak_pct(f.path)
        if pct then
            log.info("ui_audio", "文件峰值", pct .. "%", pct < 3 and "→ 疑似静音文件" or "")
            if pct < 3 then
                page.toast("这个文件几乎是静音（峰值 " .. pct .. "%），换一个文件试")
            end
        end

        local ac = (((_G.project_config or {}).hw or {}).audio) or {}
        if ac.pa_en then
            local lv = (ac.pa_on_level == 0) and 0 or 1
            pcall(gpio.setup, ac.pa_en, lv)
            sys.wait(20)
            local ok_get, v = pcall(gpio.get, ac.pa_en)
            log.info("ui_audio", "PA 使能脚", ac.pa_en, "写入", lv,
                "读回", ok_get and tostring(v) or "读不到")
        end

        local ok_start = exaudio.play_start({
            type    = 0,
            content = f.path,
            cbfnc   = function(event)
                if event == exaudio.PLAY_DONE then
                    playing = nil
                    log.info("ui_audio", "播放完成", f.path)
                    set_state("播放完成：" .. fmt_name(f.name), C.OK)
                end
            end,
        })
        -- 排查用：false 一般是文件不存在 / 文件头坏（日志里会跟一句 "播放文件损坏"）
        log.info("ui_audio", "play_start 返回:", tostring(ok_start))
    end)
end

local function stop_play()
    if not playing then
        page.toast("当前没有播放")
        return
    end
    local exaudio = require "exaudio"
    for _, fn in ipairs({ "play_stop", "stop", "play_cancel" }) do
        if exaudio[fn] then
            pcall(exaudio[fn])
            break
        end
    end
    playing = nil
    set_state("已停止", C.TEXT_WEAK)
end

local function set_volume(delta)
    volume = volume + delta
    if volume < 0 then volume = 0 end
    if volume > 100 then volume = 100 end

    if ready then
        pcall(function() require("exaudio").vol(volume) end)
    end
    if vol_label then vol_label:set_text("音量 " .. volume) end
end

-- ===== 列表 =====

local function render_list()
    if list_box then
        pcall(function() list_box:destroy() end)
        list_box = nil
    end
    if pager_box then
        pcall(function() pager_box:destroy() end)
        pager_box = nil
    end

    list_box = ui.box({ parent = page.body, x = 0, y = LIST_Y, w = DW, h = PER_PAGE * (ROW_H + ROW_GAP) })

    if #files == 0 then
        local no_sd = not io.exists("/sd")
        ui.label({
            parent = list_box, x = G.M, y = 10, w = DW - G.M * 2, h = 26,
            text = scanning and "正在扫描音频文件…"
                or (no_sd and "TF 卡没挂上（/sd 不存在）：检查卡座、卡格式（FAT32）"
                    or "没找到音频文件：把 mp3 / wav 拷到 TF 卡根目录（开机自动挂到 /sd）"),
            size = F.SMALL, color = C.TEXT_WEAK,
        })
        ui.label({
            parent = list_box, x = G.M, y = 40, w = DW - G.M * 2, h = 24,
            text = "脚本区只有 512 KB，音乐别随脚本烧进 luadb；插卡后重开本页就能看到",
            size = F.TINY, color = C.TEXT_WEAK,
        })
        return
    end

    local start = (page_idx - 1) * PER_PAGE
    for i = 1, PER_PAGE do
        local f = files[start + i]
        if f then
            local y = (i - 1) * (ROW_H + ROW_GAP)
            local row = ui.card({
                parent = list_box, x = G.M, y = y, w = DW - G.M * 2, h = ROW_H,
                radius = T.RADIUS.S,
                on_click = function() play_file(f) end,
            })
            ui.label({
                parent = row, x = 12, y = math.floor((ROW_H - F.NORMAL) / 2), w = 30, h = F.NORMAL + 4,
                symbol = airui.SYMBOL_PLAY, size = F.NORMAL,
                color = (playing == f.path) and C.OK or C.PRIMARY,
            })
            ui.label({
                parent = row, x = 52, y = math.floor((ROW_H - F.SMALL) / 2),
                w = DW - G.M * 2 - 200, h = F.SMALL + 4,
                text = f.name, size = F.SMALL, color = C.TEXT,
            })
            local meta
            if playing == f.path then
                meta = "播放中"
            else
                -- 内置项（/builtin）没有 size 字段，别显示成 "0.0 KB"
                local dir_text = (f.dir == "/builtin") and "内置" or (f.dir or "")
                local kb = (f.size or 0) / 1024
                meta = (kb > 0) and string.format("%s · %.1f KB", dir_text, kb) or dir_text
            end
            ui.label({
                parent = row, x = DW - G.M * 2 - 210, y = math.floor((ROW_H - F.TINY) / 2),
                w = 198, h = F.TINY + 4,
                text = meta,
                size = F.TINY, color = (playing == f.path) and C.OK or C.TEXT_WEAK,
                align = airui.TEXT_ALIGN_RIGHT,
            })
        end
    end

    -- 分页条紧贴列表下方（原来放在 y=S.DH-56=424，超出 page.body 高度 ~422，
    -- 内容溢出会让右侧冒出 LVGL 滚动条，看着像"没用的竖条"）
    pager_box = ui.box({
        parent = page.body, x = 0,
        y = LIST_Y + PER_PAGE * (ROW_H + ROW_GAP), w = DW, h = 44,
    })
    ui.pager({
        parent = pager_box, y = 0, page = page_idx,
        page_count = math.max(1, math.ceil(#files / PER_PAGE)),
        on_change = function(p)
            page_idx = p
            render_list()
        end,
    })
end

-- 回到本页时重扫：可能刚插卡 / 刚挂载完，或者从文件页拷了音乐过来
local function rescan()
    scanning = true
    files = scan_files()
    scanning = false
    local pages = math.max(1, math.ceil(#files / PER_PAGE))
    if page_idx > pages then page_idx = 1 end
    if page then render_list() end
    -- 排障用：每个目录能列到多少个文件（板子上没有 /sd 就是 TF 卡没挂上）
    local stats = {}
    for _, dir in ipairs(SCAN_DIRS) do
        local ok, list = io.lsdir(dir, 100, 0)
        stats[#stats + 1] = string.format("%s=%s", dir, (ok and type(list) == "table") and #list or "-")
    end
    log.info("ui_audio", "扫描到音频文件", #files, "个", table.concat(stats, " "))
end

-- ===== 界面 =====

local function create_ui()
    page = ui.page({
        title = "音频播放",
        on_back = function() if win_id then exwin.close(win_id) end end,
    })

    -- 状态卡
    local st = ui.card({ parent = page.body, x = G.M, y = 10, w = DW - G.M * 2, h = 82 })
    ui.label({
        parent = st, x = 12, y = 10, w = DW - G.M * 2 - 24, h = 22,
        text = "播放状态", size = F.SMALL, color = C.TEXT_SUB,
    })
    state_label = ui.label({
        parent = st, x = 12, y = 36, w = DW - G.M * 2 - 24, h = 30,
        text = "就绪：点下面任意一首开始播放", size = F.SMALL, color = C.TEXT,
    })

    -- 音量行
    ui.ghost_button({
        parent = page.body, x = G.M, y = S.DH - 106, w = 66, h = 40,
        text = "－", on_click = function() set_volume(-10) end,
    })
    vol_label = ui.label({
        parent = page.body, x = G.M + 76, y = S.DH - 96, w = 140, h = 24,
        text = "音量 " .. volume, size = F.SMALL, color = C.TEXT_SUB,
    })
    ui.ghost_button({
        parent = page.body, x = G.M + 226, y = S.DH - 106, w = 66, h = 40,
        text = "＋", on_click = function() set_volume(10) end,
    })
    ui.button({
        parent = page.body, x = DW - G.M - 160, y = S.DH - 106, w = 160, h = 40,
        text = "停止", color = C.WARN, on_click = stop_play,
    })

    files = {}
    render_list()
end

local function on_create()
    page_idx, playing = 1, nil
    -- 先出界面，再扫卡：scan_files 要读 TF 卡目录，放在这里同步做会把首帧一起拖住
    scanning = true
    create_ui()
    sys.taskInit(function()
        sys.wait(30)
        if page then rescan() end
    end)
end

local function on_destroy()
    -- 离开页面就停播，避免回桌面后还在响
    if playing then
        local ok, exaudio = pcall(require, "exaudio")
        if ok then
            for _, fn in ipairs({ "play_stop", "stop", "play_cancel" }) do
                if exaudio[fn] then pcall(exaudio[fn]) break end
            end
        end
        playing = nil
    end

    if page then
        page.destroy()
        page = nil
    end
    state_label, list_box, pager_box, vol_label = nil, nil, nil, nil
    files = {}
    win_id = nil
end

sys.subscribe("OPEN_AUDIO_WIN", function()
    win_id = exwin.open({
        on_create     = on_create,
        on_destroy    = on_destroy,
        on_get_focus  = rescan,
        on_lose_focus = function() end,
    })
end)
