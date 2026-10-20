--[[
@module  ui_main
@summary 用户模式 UI 主模块：初始化显示/触摸/AirUI，加载字库，打开欢迎页
@version 1.0
@date    2026.10.16
@usage
    由 user_main 在开机流程里 require，本模块自己起 task 完成初始化。

说明
1. 显示参数全部来自 config（drv_lcd 封装），本文件不写死分辨率与引脚；
2. AirUI 是内核能力：固件不带 airui/exwin 核心库时这里会报错，界面起不来（此时不影响产测）；
3. 字库文件由 font_subset 工具生成后放到本目录、随脚本一起烧入；
   缺字库时中文会显示异常，所以这里明确告警，不静默失败。
]]

local exwin = require "exwin"

-- 公共层：主题 + 组件（页面都依赖它们，这里显式引用确保被打包）
require "ui_theme"
require "ui_kit"

-- 页面模块：必须静态 require，烧录合并器才会打包这些文件
require "ui_welcome"
require "ui_idle"
require "ui_net"
require "ui_wifi"
-- 设备信息页已下线（2026-10-19）：页面文件 ui_sysinfo.lua 在 .airmaster/unused_pages/ 备查，
-- 不在这里 require，烧录合并器就不会打包它。
-- 温湿度页已下线（改用 485 温湿度）：页面文件 ui_sensor.lua 保留备查，不随固件打包
-- （注释里也不写 require 字面量：合并器按文本扫描，注释里的 require 也可能被打包）
require "ui_air"
require "ui_audio"
require "temp_hum"
require "ui_485"
require "ui_cam"

-- 已下线：桌面不再提供「I2C 扫描」「显示设置」入口（2026-10-18）。
-- 页面文件 ui_i2c.lua / ui_setting.lua 仍留在工程目录里备查，但这里不引用，
-- 烧录合并器就不会把它们打进固件；需要重新启用时，在这里加回 require 并在
-- ui_idle.lua 的 APPS 表里加回对应入口。
-- （同样不在注释里写 require 字面量，避免被合并器当成依赖打包。）


-- 字库候选路径：
--   /luadb/xxx.ttf  随脚本区一起烧入（本工程默认方式）
--   /xxx.ttf        烧到文件系统根目录（官方 demo 的用法）
local FONT_PATH = "/luadb/ui_font.ttf"
local FONT_CANDIDATES = { FONT_PATH, "/ui_font.ttf" }

-- ===== 显示与触摸 =====

local function load_font()
    local file
    for _, path in ipairs(FONT_CANDIDATES) do
        if io.exists(path) then
            file = path
            break
        end
    end

    if not file then
        log.warn("ui_main", "未找到字库（", FONT_CANDIDATES[1], "或", FONT_CANDIDATES[2],
            "）→ 中文可能显示异常，用 font_subset 生成后随脚本烧入")
        return false
    end

    local ok = airui.font_load({
        type       = "hzfont",
        path       = file,
        size       = 20,        -- 基础字号，页面里 font_size 可单独指定
        cache_size = 1024,      -- 字形缓存条数（hzfont 允许 128/256/512/1024/2048；条数越大查找越慢、且位图占内部 RAM，保持默认 1024）
        antialias  = 1,
        global     = true,
    })
    log.info("ui_main", "字库加载", ok and "成功" or "失败", file)
    return ok and true or false
end

local function init_display()
    -- 显示屏（RGB）：drv_lcd 内部已完成 lcd.init + 帧缓冲 + 禁自动刷新 + 背光
    local lcd_drv = require "drv_lcd"
    if not lcd_drv.init() then
        log.error("ui_main", "LCD 初始化失败，用户界面无法启动")
        return false
    end

    local W, H = lcd_drv.size()
    if not airui.init(W, H) then
        log.error("ui_main", "airui.init 失败（确认内核固件带 airui / exwin 核心库）")
        return false
    end
    log.info("ui_main", "AirUI 版本", airui.version(), "屏幕", W, H)

    -- 把内核真实分辨率同步给主题层：ui_theme 按 800×480 设计基准等比缩放，
    -- 内容区在整屏居中（大屏四周/两侧的留白由页面根容器背景色铺满）。
    -- 必须在创建任何页面之前调用。
    require("ui_theme").setup(W, H)

    local cfg_lcd  = ((_G.project_config or {}).hw or {}).lcd or {}
    -- fskv 里没写过 ui_rotation 时 get() 返回 nil，直接 tonumber(nil) 会抛
    -- "bad argument #1 to 'tonumber' (value expected)"，把整个 Lua VM 干掉。
    -- 先把 nil 兜成 ""（tonumber("") 只返回 nil，不报错），config 缺省值同理。
    local rotation = tonumber(fskv.get("ui_rotation") or "") or tonumber(cfg_lcd.rotation or 0) or 0
    if rotation ~= 0 and airui.set_rotation then
        local ok, err = pcall(airui.set_rotation, rotation)
        log.info("ui_main", "界面旋转", rotation .. "°", ok and "OK" or tostring(err))
    end

    load_font()

    -- 触摸：绑给 AirUI 当输入设备（注意不是产测那种 TP_RAW 回调模式）。
    -- 必须在 airui.init 之后调用，否则 AirUI 收不到触点。
    local tp_drv = require "drv_tp"
    if not tp_drv.init({ airui = true }) then
        log.warn("ui_main", "触摸初始化失败，界面只能看不能点")
    end

    return true
end

-- ===== 启动 =====

sys.taskInit(function()
    -- 兜底：UI 初始化里的任何异常都不能把 Lua VM 干掉（VM 退出 => 15 秒后重启，
    -- 现场表现为"反复重启/黑屏"，且脚本层逻辑全跑不完，极难定位）。
    -- 异常时只记日志、保持空转，设备至少还能被人发现/远程排查。
    local ok, ret = pcall(init_display)
    if not ok then
        log.error("ui_main", "UI 初始化异常，用户模式保持空转（可发 RST# 回产测排查）", ret)
        return
    end
    if not ret then
        log.error("ui_main", "UI 初始化失败，用户模式保持空转（可发 RST# 回产测排查）")
        return
    end

    -- 欢迎页 → 主界面：欢迎页自己关闭后再开主界面
    sys.publish("OPEN_WELCOME_WIN")
    log.info("ui_main", "UI 已启动")
end)

-- 调试入口：任何时候发这个事件都能回到主界面（供后期加"返回首页"逻辑用）
sys.subscribe("UI_BACK_HOME", function()
    sys.publish("OPEN_IDLE_WIN")
end)
