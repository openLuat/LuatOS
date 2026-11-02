--[[
@module  ui_settings
@summary 设置页：SD 卡空间占用、亮度调节、修改锁屏密码、清空缓存、关于
@version 1.0
@date    2026.10.23

布局（1024x600）：
  顶栏 0..88：返回 + 标题
  SD 卡卡片：总量/已用/剩余 + 进度条 + 清空缓存按钮
  亮度卡片：- / + 按钮 + 滑动条 + 百分比（实时预览，离开页面时持久化）
  修改锁屏密码按钮（复用 app.change_pwd 的改密流程）
  关于：版本号
]]
local conf = require "conf"
local theme = require "theme"
local settings = require "settings"

local M = {}
local C = theme.C
local SW, SH = conf.W, conf.H

local root = nil
local app_ref = nil
local sdCard = nil
local sdLabel = nil
local sdBar = nil
local brightLabel = nil
local brightSlider = nil
local curBright = 100
local dirty = false            -- 是否改过亮度（避免刚进设置页就写盘）
local saveTimer = nil          -- 亮度落盘延时定时器

local SD_MOUNT = conf.sd.mount
local BAR_W = 620
local BAR_H = 16
local ACCENT = 0xE4763F

-- 缓存文件名前缀（去掉前导斜杠，io.lsdir 返回的 name 不带斜杠）
-- 需与 thumb.lua 的 conf.photo.thumb_prefix、photo_view.lua 的 BIN_PREFIX 保持一致
local CACHE_PREFIXES = { ".at3_", ".af1_" }

-- ==================== SD 卡空间 ====================
--[[重画 SD 占用进度条：airui.container 没有 set_size，只能销毁重建填充条]]
local function refresh_sd_bar(ratio)
    if sdBar then
        pcall(function() sdBar:destroy() end)
        sdBar = nil
    end
    ratio = tonumber(ratio) or 0
    if ratio < 0 then ratio = 0 elseif ratio > 1 then ratio = 1 end
    local w = math.floor(BAR_W * ratio + 0.5)
    if w > 0 and sdCard then
        sdBar = theme.box(sdCard, 28, 96, w, BAR_H, ACCENT, BAR_H / 2)
    end
end

local function load_sd_info()
    if not root or not sdCard or not sdLabel then return end

    local ok, data = pcall(function()
        if not fatfs or not fatfs.getfree then return nil end
        return fatfs.getfree(SD_MOUNT)
    end)

    if not root or not sdCard or not sdLabel then return end

    if ok and type(data) == "table" and data.total_kb and data.total_kb > 0 then
        local total = data.total_kb * 1024
        local free = data.free_kb * 1024
        local used = total - free
        local pct = math.floor(used * 100 / total + 0.5)
        sdLabel:set_text(string.format("总量 %s   已用 %s   剩余 %s（%d%%）",
            theme.size_text(total), theme.size_text(used), theme.size_text(free), pct))
        refresh_sd_bar(used / total)
    else
        sdLabel:set_text("未检测到 SD 卡")
        refresh_sd_bar(0)
    end
end

--[[清空缩略图/大图缓存，释放 SD 空间]]
local function clear_cache()
    if not app_ref then return end
    app_ref.toast("正在清理缓存...")

    sys.taskInit(function()
        local removed, offset = 0, 0
        while offset < 4000 do
            local ok, list = io.lsdir(SD_MOUNT, 100, offset)
            if not ok or type(list) ~= "table" or #list == 0 then break end
            for _, it in ipairs(list) do
                local name = it.name
                if name and name ~= "" then
                    for _, p in ipairs(CACHE_PREFIXES) do
                        if name:sub(1, #p) == p then
                            if os.remove(SD_MOUNT .. "/" .. name) then removed = removed + 1 end
                            break
                        end
                    end
                end
            end
            offset = offset + #list
        end

        if not root then return end
        if removed > 0 then
            app_ref.toast("已清理 " .. removed .. " 个缓存文件")
        else
            app_ref.toast("没有可清理的缓存")
        end
        load_sd_info()
    end)
end

-- ==================== 亮度 ====================
-- 亮度落盘：改动后延时提交，连续调节合并成一次写盘
local function save_bright()
    if not dirty then return end
    settings.set_brightness(curBright)
    dirty = false
end

local function on_save_timeout()
    saveTimer = nil
    save_bright()
end

local function commit_bright()
    dirty = true
    if saveTimer then sys.timerStop(saveTimer) end
    saveTimer = sys.timerStart(on_save_timeout, 800)
end

local function bright_step(delta)
    local v = curBright + delta
    if v < 10 then v = 10 end
    if v > 100 then v = 100 end
    curBright = v
    commit_bright()
    if brightSlider then brightSlider:set_value(v, true) end
    settings.apply_brightness(v)
    if brightLabel then brightLabel:set_text(v .. "%") end
end

-- ==================== 构建 ====================
function M.build(app)
    M.destroy()
    app_ref = app

    root = airui.container({
        parent = nil, x = 0, y = 0, w = SW, h = SH,
        color = 0xFBF7F2, radius = 0, border_width = 0,
    })
    theme.gradient(root, 0, 0, SW, SH, 0xFBF7F2, 0xF1E8DE, 8)

    -- 顶栏
    theme.box(root, 0, 0, SW, 88, 0xFFF1E4, 0)
    theme.button(root, 16, 16, 104, 56, "返回", 20, 0xEFD9C2, C.ink, function()
        theme.defer(function()
            if app_ref then app_ref.close_settings() end
        end)
    end, 18)
    theme.label(root, 136, 16, 300, 56, "设置", 30, C.ink)

    -- SD 卡存储卡片
    sdCard = theme.card(root, 40, 112, SW - 80, 150, 0xFFFFFF, 16, 0xEADFD2, 1)
    theme.label(sdCard, 28, 20, 240, 30, "SD 卡存储", 22, C.ink)
    sdLabel = theme.label(sdCard, 28, 58, 560, 24, "读取中...", 15, C.ink2)
    theme.box(sdCard, 28, 96, BAR_W, BAR_H, 0xF0DCC6, BAR_H / 2)  -- 进度条背景
    theme.button(sdCard, 700, 52, 200, 48, "清空缓存", 16, 0xF3EAE0, C.ink, function()
        theme.defer(function() clear_cache() end)
    end, 12)

    -- 亮度卡片
    local brightCard = theme.card(root, 40, 282, SW - 80, 150, 0xFFFFFF, 16, 0xEADFD2, 1)
    theme.label(brightCard, 28, 20, 240, 30, "屏幕亮度", 22, C.ink)
    brightLabel = theme.label(brightCard, 720, 24, 160, 30, "", 20, C.ink, airui.TEXT_ALIGN_RIGHT)
    theme.button(brightCard, 28, 92, 72, 44, "-", 22, 0xF3EAE0, C.ink, function()
        theme.defer(function() bright_step(-10) end)
    end, 12)
    theme.button(brightCard, 112, 92, 72, 44, "+", 22, 0xF3EAE0, C.ink, function()
        theme.defer(function() bright_step(10) end)
    end, 12)
    curBright = settings.get_brightness()
    brightLabel:set_text(curBright .. "%")

    -- 老固件可能没有 slider 组件：创建失败就退回只用 - / + 按钮
    local ok, sl = pcall(function()
        return airui.slider({
            parent = brightCard, x = 200, y = 100, w = 500, h = 24,
            min = 10, max = 100, value = curBright,
            style = {
                bg_color = 0xF0DCC6, bg_opa = 255,
                indicator_color = ACCENT, indicator_opa = 255,
                knob_color = 0xFFFFFF, knob_opa = 255,
                knob_border_color = ACCENT, knob_border_width = 2,
                radius = 12,
            },
            on_change = function()
                -- 拖动时实时预览，写盘延时提交
                if not brightSlider then return end
                local v = brightSlider:get_value()
                curBright = v
                commit_bright()
                settings.apply_brightness(v)
                if brightLabel then brightLabel:set_text(v .. "%") end
            end,
        })
    end)
    brightSlider = ok and sl or nil

    -- 修改密码
    theme.button(root, 40, 452, SW - 80, 56, "修改锁屏密码", 20, 0xF3EAE0, C.ink, function()
        theme.defer(function()
            if app_ref then app_ref.change_pwd() end
        end)
    end, 14)

    -- 关于
    local ver = rawget(_G, "VERSION") or "1.0.0"
    theme.label(root, 40, 524, 500, 22, "Air8607 电子相册  v" .. ver, 14, C.ink3)

    -- getfree 首次可能触发全盘 FAT 扫描，放后台，避免页面出来前卡住
    sys.taskInit(function()
        sys.wait(50)
        load_sd_info()
    end)
end

-- ==================== 对外 ====================
function M.destroy()
    if saveTimer then
        sys.timerStop(saveTimer)
        saveTimer = nil
    end
    -- 调节动作已经延时落盘，这里只补交还没提交的改动
    save_bright()
    if root then
        pcall(function() root:destroy() end)
        root = nil
    end
    app_ref = nil
    sdCard, sdLabel, sdBar = nil, nil, nil
    brightLabel, brightSlider = nil, nil
end

return M
