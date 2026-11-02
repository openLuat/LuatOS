--[[
@module  app
@summary 页面状态机：锁屏 <-> 首页 <-> 相册目录 <-> 单张查看器
@version 1.1
@date    2026.10.22

页面生命周期：
  - 锁屏/首页/目录页互斥，切换时销毁旧页（都只有一些 label/shape，代价很小）；
  - 查看器离开时**彻底销毁**（含 photo_view 的 2.46MB 帧缓冲），
    首页不会背着大图；查看器内部切图才复用同一个视频控件；
  - 进入查看器时**保留**目录页（不销毁），返回时立刻回到原来的页码和目录。
]]
local conf = require "conf"
local theme = require "theme"
local sd = require "sd_card"
local lock = require "lock"
local ui_lock = require "ui_lock"
local ui_home = require "ui_home"
local ui_browser = require "ui_browser"
local ui_viewer = require "ui_viewer"
local ui_settings = require "ui_settings"

local M = {}

local C = theme.C
local SD_MOUNT = conf.sd.mount

local state = "none"          -- lock | home | browser | viewer | settings
local last_dir = SD_MOUNT
local pwd_return = "home"     -- 从哪个页面进入改密码流程

-- toast（错误/进度提示）
local toastBox, toastLabel, toastTimer = nil, nil, nil
local toastToken = 0

-- ==================== 提示条 ====================
function M.toast(msg)
    toastToken = toastToken + 1
    local tk = toastToken
    -- 每次重建：保证提示条永远在最新页面之上（LVGL 后创建的对象在上层）
    if toastBox then
        pcall(function() toastBox:destroy() end)
        toastBox, toastLabel = nil, nil
    end
    toastBox = airui.container({
        parent = nil, x = 262, y = 524, w = 500, h = 52,
        color = 0x3A2A20, color_opacity = 238,
        radius = 26, border_color = 0x8A6A52, border_width = 1,
    })
    toastLabel = theme.label(toastBox, 0, 14, 500, 24, "", 18,
        C.on_dark, airui.TEXT_ALIGN_CENTER)

    toastLabel:set_text(msg)
    toastBox:set_hidden(false)
    if toastTimer then sys.timerStop(toastTimer) end
    toastTimer = sys.timerStart(function()
        toastTimer = nil
        -- 只隐藏自己这条，避免旧定时器把新提示提前关掉
        if tk == toastToken and toastBox then toastBox:set_hidden(true) end
    end, 2600)
    log.info("app", msg)
end

-- 页面构建失败时不能留下半成品页面，记录错误并交回调用方退回可用页面
local function build_page(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        log.error("app", "页面构建失败", tostring(err))
    end
    return ok
end

-- ==================== 锁屏 ====================
--[[显示锁屏/改密码页
mode: "unlock" 解锁 | "old"/"new"/"confirm" 改密码流程
]]
function M.show_lock(mode)
    ui_viewer.destroy()
    ui_browser.destroy()
    ui_home.destroy()
    ui_lock.destroy()
    ui_settings.destroy()

    state = "lock"
    if not build_page(ui_lock.build, M, mode or "unlock") then
        M.toast("界面构建失败")
    end
end

--[[解锁成功]]
function M.on_unlock()
    if state ~= "lock" then return end
    log.info("app", "解锁成功")
    M.show_home()
end

--[[主动锁屏]]
function M.lock_now()
    log.info("app", "手动锁屏")
    M.show_lock("unlock")
end

--[[改密码：先验证原密码。允许从首页或设置页进入，返回时回到原页面]]
function M.change_pwd()
    if state ~= "home" and state ~= "settings" then return end
    pwd_return = state
    M.show_lock("old")
end

--[[改密码流程里点“返回首页”]]
function M.cancel_pwd()
    if state ~= "lock" then return end
    if pwd_return == "settings" then
        M.open_settings()
    else
        M.show_home()
    end
end

--[[改密码成功]]
function M.on_pwd_changed()
    log.info("app", "密码已修改")
    M.toast("密码已修改")
    if pwd_return == "settings" then
        M.open_settings()
    else
        M.show_home()
    end
end

-- ==================== 首页 ====================
local function refresh_home_sd()
    local ok = sd.is_mounted()
    local f, p = 0, 0
    if ok then
        f, p = sd.overview()
    end
    if state == "home" then
        ui_home.set_sd(ok, f, p, sd.last_error())
    end
end

function M.show_home()
    ui_viewer.destroy()
    ui_browser.destroy()
    ui_lock.destroy()
    ui_home.destroy()
    ui_settings.destroy()

    state = "home"
    if not build_page(ui_home.build, M) then
        M.toast("界面构建失败")
    end
    refresh_home_sd()

    -- 异步挂载，避免首页出现前卡住
    if not sd.is_mounted() then
        sys.taskInit(function()
            sys.wait(60)
            sd.mount()
            if state == "home" then refresh_home_sd() end
        end)
    end
end

-- ==================== 设置页 ====================
function M.open_settings()
    ui_viewer.destroy()
    ui_browser.destroy()
    ui_lock.destroy()
    ui_home.destroy()
    ui_settings.destroy()

    state = "settings"
    if not build_page(ui_settings.build, M) then
        M.show_home()
    end
end

function M.close_settings()
    if state ~= "settings" then return end
    M.show_home()
end

-- ==================== 相册目录 ====================
function M.open_dir(path)
    last_dir = path or SD_MOUNT
    ui_viewer.hide()          -- 还在相册里，保留已分配的帧缓冲
    ui_lock.destroy()
    ui_home.destroy()
    ui_browser.destroy()
    ui_settings.destroy()

    state = "browser"
    if not build_page(ui_browser.build, M, last_dir) then
        M.show_home()
    end
end

function M.open_album()
    if state ~= "home" then return end

    if sd.is_mounted() then
        M.open_dir(SD_MOUNT)
        return
    end

    M.toast("正在读取 SD 卡...")
    sys.taskInit(function()
        sys.wait(40)
        local ok, err = sd.mount()
        if state ~= "home" then return end
        if not ok then
            M.toast("未检测到 SD 卡：" .. tostring(err))
            ui_home.set_sd(false, 0, 0, err)
            return
        end
        M.open_dir(SD_MOUNT)
    end)
end

function M.browser_up()
    if state ~= "browser" then return end
    if last_dir == SD_MOUNT then
        M.show_home()
        return
    end
    local parent = last_dir:match("^(.*)/[^/]+$")
    if not parent or parent == "" then parent = SD_MOUNT end
    M.open_dir(parent)
end

function M.browser_back()
    if state ~= "browser" then return end
    if last_dir == SD_MOUNT then
        M.show_home()
    else
        M.browser_up()
    end
end

-- ==================== 单张查看 ====================
function M.open_photo(photos, index)
    if state ~= "browser" then return end
    if type(photos) ~= "table" or #photos == 0 then
        M.toast("这个文件夹里没有照片")
        return
    end

    local dir_before = last_dir
    state = "viewer"
    build_page(ui_viewer.build, M, photos, index or 1)

    -- build 失败（列表为空或抛错）时回退到目录页
    if not ui_viewer.active() then
        state = "browser"
        last_dir = dir_before
        if not build_page(ui_browser.build, M, last_dir) then
            M.show_home()
        end
    end
end

function M.close_viewer()
    if state ~= "viewer" then return end
    ui_viewer.hide()          -- 只隐藏，保留帧缓冲，再进来是瞬开
    state = "browser"
    -- 目录页一直保留着，直接显示即可（不重建，页码不丢）
    if not ui_browser.dir() then
        if not build_page(ui_browser.build, M, last_dir) then
            M.show_home()
        end
    end
end

function M.go_home()
    if state == "viewer" then
        ui_viewer.destroy()
    end
    M.show_home()
end

-- ==================== 重新读卡 ====================
function M.refresh_sd()
    if state ~= "home" then return end
    M.toast("正在重新读取 SD 卡...")
    sys.taskInit(function()
        sys.wait(40)
        sd.remount()
        if state ~= "home" then return end
        refresh_home_sd()
        if sd.is_mounted() then
            M.toast("SD 卡已就绪")
        else
            M.toast("未检测到 SD 卡")
        end
    end)
end

-- ==================== 触摸分发 ====================
function M.on_touch(tp_state, x, y, track_id, ts)
    if state == "viewer" then
        ui_viewer.on_touch(tp_state, x, y, track_id, ts)
    end
end

-- ==================== 旧缓存清理 ====================
--[[早期版本在 SD 根目录留过 .athumb_ / .afull_ / .album_view.jpg。
-- 现在缓存前缀带版本号（缩略图 .at3_，大图 .af1_），启动时把旧前缀的残留删掉，
-- 避免卡根目录里堆一堆没人再用的旧文件。]]
local LEGACY_DEL = { ".athumb_", ".album_view.jpg" }

local function clean_legacy_cache()
    local mount = conf.sd.mount
    local removed, kept, offset = 0, 0, 0
    while offset < 3000 do
        local ok, list = io.lsdir(mount, 100, offset)
        if not ok or type(list) ~= "table" or #list == 0 then break end
        for _, it in ipairs(list) do
            local name = it.name
            if name and name ~= "" then
                if name:sub(1, 7) == ".afull_" then
                    -- 大图缓存的格式没变，改名成新前缀，省掉一次重新生成
                    local dst = mount .. "/.af1_" .. name:sub(8)
                    if not os.rename(mount .. "/" .. name, dst) then
                        os.remove(mount .. "/" .. name)
                        removed = removed + 1
                    else
                        kept = kept + 1
                    end
                else
                    for _, p in ipairs(LEGACY_DEL) do
                        if name:sub(1, #p) == p then
                            if os.remove(mount .. "/" .. name) then removed = removed + 1 end
                            break
                        end
                    end
                end
            end
        end
        offset = offset + #list
    end
    if removed > 0 or kept > 0 then
        log.info("app", "旧缓存清理", "删除", removed, "保留改名", kept)
    end
end

-- ==================== 启动 ====================
function M.start()
    -- 先挂 SD 再出锁屏：密码可能存在卡上的 /.album_pwd，首页也要立刻显示照片数量
    local sd_ok, sd_err = sd.mount()
    log.info("app", "SD", sd_ok and "已挂载" or ("未挂载 " .. tostring(sd_err)))
    log.info("app", "缩略图", conf.photo.preview ~= false and "开" or "关",
        "videoplayer", type(videoplayer))
    if sd_ok then clean_legacy_cache() end

    if lock.enabled() then
        M.show_lock("unlock")
        log.info("app", "电子相册已启动（锁屏）")
    else
        M.show_home()
        log.info("app", "电子相册已启动（未设锁屏）")
    end
end

function M.state_name()
    return state
end

return M
