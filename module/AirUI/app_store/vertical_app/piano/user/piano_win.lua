--[[
@module  piano_win
@summary 简单钢琴模拟窗口
@version 1.0
]]

-- exapp 沙箱里包装后的 exwin 在 _ENV 上；rawget(_G,"exwin") 易误用裸 exwin，退出后无法 exapp.close
local exwin = exwin
if not exwin then
    exwin = require "exwin"
end

local win_id = nil
local main_container = nil
local status_label = nil
local key_buttons = {}

local SCREEN_W = 480
local SCREEN_H = 800
local BLACK_KEY_IDLE = 0x000000
local BLACK_KEY_ACTIVE = 0x334155
local BLACK_KEY_FLASH_MS = 90

local function ensure_airui()
    if not airui or not airui.init then
        return false
    end
    if type(exapp) == "table" then
        return true
    end
    local bsp = (rtos and rtos.bsp and rtos.bsp()) or ""
    bsp = tostring(bsp)
    if bsp:upper():find("PC", 1, true) then
        return airui.init(480, 800, airui.COLOR_FORMAT_ARGB8888)
    end
    local w, h = 480, 800
    if lcd and lcd.getSize then
        w, h = lcd.getSize()
    end
    return airui.init(w, h)
end

-- 音符表（频率 Hz）；每次打开窗口时在内存中生成对应 PCM，不读文件
local NOTES = {
    { name = "C4", freq_hz = 261.63, is_black = false },
    { name = "C#4", freq_hz = 277.18, is_black = true },
    { name = "D4", freq_hz = 293.66, is_black = false },
    { name = "D#4", freq_hz = 311.13, is_black = true },
    { name = "E4", freq_hz = 329.63, is_black = false },
    { name = "F4", freq_hz = 349.23, is_black = false },
    { name = "F#4", freq_hz = 369.99, is_black = true },
    { name = "G4", freq_hz = 392.00, is_black = false },
    { name = "G#4", freq_hz = 415.30, is_black = true },
    { name = "A4", freq_hz = 440.00, is_black = false },
    { name = "A#4", freq_hz = 466.16, is_black = true },
    { name = "B4", freq_hz = 493.88, is_black = false },
    { name = "C5", freq_hz = 523.25, is_black = false },
}

local function set_status(msg, color)
    if status_label then
        status_label:set_text(msg or "")
        if color then
            status_label:set_color(color)
        end
    end
end

-- PC 上 audio.play(文件) 未实现，统一用 audio.start + audio.write 播内存 PCM
local AUDIO_CH = 0
local PCM_SR = 22050
local PCM_DUR_SEC = 0.45
local PCM_AMP = 12000
local PCM_FADE_SAMPLES = math.floor(PCM_SR * 0.04)

local function make_pcm_sine(freq_hz)
    local n = math.floor(PCM_SR * PCM_DUR_SEC)
    if n < 2 then
        return ""
    end
    local fade = PCM_FADE_SAMPLES
    if fade * 2 > n then
        fade = math.floor(n / 4)
    end
    local two_pi_f = 2 * math.pi * freq_hz / PCM_SR
    local parts = {}
    for i = 0, n - 1 do
        local env = 1.0
        if i < fade then
            env = i / math.max(1, fade)
        end
        if i > n - 1 - fade then
            local t = (n - 1 - i) / math.max(1, fade)
            if t < env then
                env = t
            end
        end
        local s = math.floor(PCM_AMP * env * math.sin(two_pi_f * i))
        if s > 32767 then
            s = 32767
        elseif s < -32768 then
            s = -32768
        end
        parts[#parts + 1] = string.pack("<i2", s)
    end
    return table.concat(parts)
end

local function rebuild_note_pcm()
    for i = 1, #NOTES do
        NOTES[i].pcm = make_pcm_sine(NOTES[i].freq_hz)
    end
end

local function clear_note_pcm()
    for i = 1, #NOTES do
        NOTES[i].pcm = nil
    end
end

local function play_pcm_buffer(pcm)
    if not audio or not audio.start or not audio.write then
        return false
    end
    if not pcm or #pcm < 2 then
        return false
    end
    pcall(function()
        audio.stop(AUDIO_CH)
    end)
    local ok = pcall(function()
        if not audio.start(AUDIO_CH, audio.PCM, 1, PCM_SR, 16, true) then
            error("audio.start failed")
        end
        if not audio.write(AUDIO_CH, pcm) then
            error("audio.write failed")
        end
        if audio.finish then
            audio.finish(AUDIO_CH)
        end
    end)
    return ok
end

local function play_note(note)
    if not audio then
        set_status("无 audio 模块", 0xFCA5A5)
        return
    end
    local pcm = note and note.pcm
    if not pcm or #pcm < 2 then
        set_status("无音色数据: " .. tostring(note and note.name), 0xFCA5A5)
        return
    end
    if play_pcm_buffer(pcm) then
        set_status("播放: " .. note.name, 0xD1FADF)
    else
        set_status("音频失败: " .. note.name, 0xFCA5A5)
    end
end

local function flash_black_key(key)
    if not key then
        return
    end
    key:set_color(BLACK_KEY_ACTIVE)
    sys.timerStart(function()
        if key then
            key:set_color(BLACK_KEY_IDLE)
        end
    end, BLACK_KEY_FLASH_MS)
end

local function create_ui()
    rebuild_note_pcm()

    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = 0x101827,
    })

    airui.label({
        parent = main_container,
        x = 0,
        y = 10,
        w = SCREEN_W,
        h = 36,
        text = "Piano",
        font_size = 30,
        color = 0xE5E7EB,
        align = airui.TEXT_ALIGN_CENTER,
    })

    status_label = airui.label({
        parent = main_container,
        x = 12,
        y = 52,
        w = SCREEN_W - 24,
        h = 28,
        text = "点击琴键播放音符",
        font_size = 16,
        color = 0xA7F3D0,
        align = airui.TEXT_ALIGN_CENTER,
    })

    local keyboard = airui.container({
        parent = main_container,
        x = 20,
        y = 110,
        w = SCREEN_W - 40,
        h = 640,
        color = 0xD1D5DB,
    })

    local white_count = 8
    local white_w = math.floor((SCREEN_W - 40) / white_count)
    local white_h = 640

    local white_notes = {
        NOTES[1], NOTES[3], NOTES[5], NOTES[6],
        NOTES[8], NOTES[10], NOTES[12], NOTES[13]
    }

    for i = 1, #white_notes do
        local note = white_notes[i]
        local btn = airui.button({
            parent = keyboard,
            x = (i - 1) * white_w,
            y = 0,
            w = white_w - 2,
            h = white_h,
            text = note.name,
            font_size = 18,
            text_color = 0x0F172A,
            color = 0xFFFFFF,
            bg_color = 0xFFFFFF,
            on_click = function()
                play_note(note)
            end,
        })
        key_buttons[#key_buttons + 1] = btn
    end

    local black_w = math.floor(white_w * 0.62)
    local black_h = 360
    local black_offsets = {
        { idx = 1, note = NOTES[2] },
        { idx = 2, note = NOTES[4] },
        { idx = 4, note = NOTES[7] },
        { idx = 5, note = NOTES[9] },
        { idx = 6, note = NOTES[11] },
    }

    for _, b in ipairs(black_offsets) do
        local x = b.idx * white_w - math.floor(black_w / 2)
        local note = b.note
        local key
        key = airui.container({
            parent = keyboard,
            x = x,
            y = 0,
            w = black_w,
            h = black_h,
            color = BLACK_KEY_IDLE,
            on_click = function()
                flash_black_key(key)
                play_note(note)
            end,
        })

        airui.label({
            parent = key,
            x = 0,
            y = black_h - 36,
            w = black_w,
            h = 30,
            text = note.name,
            font_size = 14,
            color = 0xF8FAFC,
            align = airui.TEXT_ALIGN_CENTER,
        })

        key_buttons[#key_buttons + 1] = key
    end

    airui.button({
        parent = main_container,
        x = 16,
        y = 754,
        w = SCREEN_W - 32,
        h = 38,
        text = "退出",
        font_size = 20,
        text_color = 0xF1F5F9,
        bg_color = 0x374151,
        on_click = function()
            if win_id then
                exwin.close(win_id)
            end
        end,
    })
end

local function on_create()
    create_ui()
end

local function on_destroy()
    pcall(function()
        if audio and audio.stop then
            audio.stop(AUDIO_CH)
        end
    end)
    clear_note_pcm()
    for i = #key_buttons, 1, -1 do
        key_buttons[i] = nil
    end
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    status_label = nil
    win_id = nil
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    if win_id then
        return
    end
    if not ensure_airui() then
        log.error("piano_win", "airui init failed")
        return
    end
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

sys.subscribe("OPEN_PIANO_WIN", open_handler)

function piano_open()
    open_handler()
end
