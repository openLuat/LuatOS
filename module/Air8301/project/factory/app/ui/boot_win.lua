--[[
@module  boot_win
@summary 开机画面（LOGO 启动页）—— 对齐工厂引擎 boot_ui + welcome_win 的启动范式
@version 1.0
@date    2026.10.09
@version_note v1.6 开机画面背景改为「跟随主题令牌 theme.C.bg」：配合全局浅色主题（纯白背景），
              开机画面由纯黑底改为纯白底，产品名/版本号/启动提示文字自动转为深色（深色主题下仍为
              深色底 + 浅色字，行为不变）；回退绘制版标识的底块改用 theme.C.t1，避免白底下与背景
              融为一体而看不见。
              v1.5 修复「非 PNG 格式的 LOGO 一律不显示」：文件头识别由仅 PNG 扩展为 PNG + JPEG，
              不再「解析不出尺寸就放弃加载」——只要格式可识别即交给 airui 解码显示（等比只缩不放，
              解析失败时用 144×144 正方形兜底），并新增文件头十六进制日志以判定真实格式；
              同时对渐进式 JPEG 增加告警（部分平台不支持，需转基线 JPEG）。
              v1.4 LOGO 改为「按真实尺寸等比自适应」并新增格式诊断日志：开机只读 PNG 文件头 33 字节
              （不解码像素）得到宽高/位深/颜色类型/隔行标志，按 300×144 上限等比缩放后居中绘制，
              解决非 128×128 的 LOGO 被强行塞进固定槽位导致拉伸、裁剪、甚至不显示的问题；
              图片缺失、非 PNG 或文件损坏时自动回退绘制版标识。
              v1.3 修正 v1.2 引入的错误引用 theme.M.BRAND（ui_theme 末尾 return M，外部拿到的就是 M 表本身，
              品牌常量应写 theme.BRAND）；该错误会导致 on_create 抛异常、开机画面文字全部无法创建；
              产品名显示「合宙工业网关Air8301」，产测/业务两种模式共用本页
@author  江访

@usage
界面：全屏底色（浅色主题下为纯白 0xFFFFFF，深色主题下为深色）+ 居中 LOGO（/luadb/logo.png，按图片真实尺寸等比自适应，上限 300×144）
    + 产品名 + 版本号 + 底部启动指示点（循环点亮）。

停留时长：最短 MIN_SHOW_MS=1800ms（保证 LOGO 被看清）、兜底 MAX_WAIT_MS=5000ms。
收尾条件 = 「最短停留满足」且「初始化完成(BOOT_INIT_DONE)」，取两者中较晚者。

=== 启动时序（由 ui_main / prod_ui_main 的初始化协程驱动） ===

  lcd_drv.init()              LCD 硬件初始化（内含 lcd.clear，背光未开 → 用户不可见）
  lcd_drv.airui_init()        AirUI 引擎 + 字体 + 密度
  OPEN_BOOT_WIN(next_msg)     本页创建（全屏底色 + LOGO），next_msg 指定进入的首页
  sys.wait(100)               等 LOGO 首帧刷上屏
  lcd_drv.backlight_on()      开背光 ← 用户第一眼看到的就是开机画面（而非黑屏/白屏）
  tp_drv.init()               触摸初始化
  BOOT_INIT_DONE              本页收尾 → publish(next_msg) 打开首页 → close 自己

=== 关键设计（与「引擎主机」开机画面一致的三条原则） ===

1) 「点亮屏幕」提到初始化链头：黑屏时长只剩固件启动 + display init 的固定开销，
   其余初始化（触摸 / 首页构建）与 LOGO 展示并行，不增加整机启动总时长。

2) 先画 LOGO 后开背光：避免用户看到 lcd.clear 的清屏过程与首帧黑屏。
   背光延迟量 BOOT_BACKLIGHT_DELAY_MS 即为此余量（首帧慢的屏可调大到 150~200）。

3) 收尾用「先开新页、再关自己」：打开首页后本页才 close，exwin 窗口栈全程非空，
   进入首页无白屏闪烁。

=== 可移植性说明（零资源依赖） ===

LOGO 资源：优先使用 /luadb/logo.png（工程内源文件为 web/logo.png，打包后即设备内的 /luadb/logo.png；
      若打包工具保留子目录，则退到 /luadb/web/logo.png）；
      开机时解析 PNG 文件头得到真实宽高，按 300×144 上限等比缩放并居中，可适配任意尺寸的 LOGO，
      无需再手工调整代码常量。图片缺失、非 PNG 或文件损坏时自动回退为绘制版标识（圆角方块 + "8301"），
      因此本页缺图不会报错、不会影响开机流程。
      设备日志会打印 LOGO 的实际尺寸与格式（位深 / 颜色类型 / 隔行标志），便于排查「图片不显示」；
      其中颜色类型 3（调色板）与隔行标志 1（Adam7 隔行）在部分平台不受支持，建议导出为 24 位
      非隔行的直通式 PNG。
      颜色来源：底色用 theme.C.bg（浅色主题 = 纯白 0xFFFFFF，深色主题 = 深色），文字与指示点复用
      ui_theme 令牌，因此两种主题下都能保证对比度。

入口消息 DOCK 与首页消息名解耦：业务模式传 "OPEN_IDLE_WIN"，
产测模式传 "OPEN_PROD_IDLE_WIN"，本页不自带模式判断。
]]

local theme = require "ui_theme"

-- 开机画面最短停留：保证 LOGO 被用户看清，避免一闪而过
-- 参考引擎主机（factory_new welcome_win + hzv 视频）的品牌露出时长，此处取 1800ms。
-- 注意：调整本值时必须同步调整 ui_main / prod_ui_main 步骤7 的兜底等待（须 > 本值）
local MIN_SHOW_MS = 1800
-- 初始化兜底超时：初始化异常卡死时也能进入首页（不把用户留在启动页）
local MAX_WAIT_MS = 5000
-- 底部启动指示点的循环点亮周期
local DOT_PERIOD_MS = 320

local win_id = nil
local root                     -- 全屏根容器
local dots = {}                -- 启动指示点（3 个）
local dot_idx = 0              -- 当前点亮的点序号（1..3）
local dot_timer, min_timer, max_timer
local next_msg = "OPEN_IDLE_WIN"

local min_ok = false           -- 最短停留是否已满足
local boot_ok = false          -- 初始化是否已完成
local finished = false         -- 收尾闸门（只生效一次）

--[[
停掉本页全部定时器（收尾与销毁时调用，幂等）

@local
@function stop_timers
]]
local function stop_timers()
    if dot_timer then sys.timerStop(dot_timer) dot_timer = nil end
    if min_timer then sys.timerStop(min_timer) min_timer = nil end
    if max_timer then sys.timerStop(max_timer) max_timer = nil end
end

--[[
收尾：打开首页 → 关闭自己

顺序至关重要：先 publish 打开首页（首页创建并入栈），再关闭本页，
exwin 窗口栈全程非空，用户不会看到白屏。

@local
@function finish
@param string reason 收尾原因（仅日志用）
]]
local function finish(reason)
    if finished or not win_id then return end
    finished = true
    _G.__boot_finished = true
    stop_timers()
    log.info("boot_win", "开机画面结束(", reason, ")，进入", next_msg)
    sys.publish(next_msg)
    exwin.close(win_id)
end

--[[
入场闸门：最短停留与初始化完成同时满足才收尾

@local
@function try_finish
]]
local function try_finish()
    if min_ok and boot_ok then finish("就绪") end
end

--[[
初始化完成通知（ui_main / prod_ui_main 发布 BOOT_INIT_DONE）

@local
@function on_boot_init_done
]]
local function on_boot_init_done()
    boot_ok = true
    if max_timer then
        sys.timerStop(max_timer)
        max_timer = nil
    end
    try_finish()
end

--[[
启动指示点循环点亮（跑马灯效果，给出「正在启动」的动态反馈）

@local
@function tick_dots
]]
local function tick_dots()
    if #dots == 0 then return end
    dot_idx = dot_idx % #dots + 1
    for i = 1, #dots do
        dots[i]:set_color(i <= dot_idx and theme.C.amber or theme.C.stroke, 255)
    end
end

--[[
窗口创建回调：构建全屏开机画面

@local
@function on_create
]]
local function on_create()
    log.info("boot_win", "[UI-MARK] 开机画面 v1.6 已加载（LOGO 启动页，支持 PNG/JPEG，白底跟随主题，停留 1800ms）")
    finished = false
    min_ok = false
    boot_ok = false
    dot_idx = 0
    dots = {}

    local SW, SH = theme.SCREEN_W, theme.SCREEN_H

    -- ---- 全屏底色（跟随主题） ----
    -- 底色使用主题令牌 theme.C.bg：浅色主题下为纯白（0xFFFFFF），深色主题下为深色。
    -- 显式挂到 airui.screen；个别 airui 版本无该常量时回退为 nil（airui 默认挂屏幕）
    root = theme.box(airui.screen, {
        x = 0, y = 0, w = SW, h = SH,
        color = theme.C.bg,
    })

    -- ---- LOGO：优先图片（按真实尺寸等比自适应），缺失/损坏则绘制版标识 ----
    -- 图片区：宽上限 300（两侧留边）、高上限 144（保证产品名/版本号/底部提示都有位置）
    local IMG_MAX_W, IMG_MAX_H = 300, 144
    local SLOT_Y = 20

    --[[读取文件头前 n 字节并转成十六进制串（仅用于日志诊断真实格式）]]
    local function head_hex(path, n)
        local f = io.open(path, "rb") or io.open(path, "r")
        if not f then return nil end
        local s = f:read(n or 8)
        f:close()
        if not s then return nil end
        local t = {}
        for i = 1, #s do t[i] = string.format("%02X", s:byte(i)) end
        return table.concat(t, " ")
    end

    --[[读取图片文件头，识别 PNG / JPEG 并取真实像素宽高（不解码像素，开销可忽略）。
    返回 w, h, fmt, extra；无法取得宽高时 w/h 为 nil，但 fmt/extra 仍会返回，便于日志判定真实格式。
    PNG 颜色类型：0 灰度、2 真彩、3 调色板、4 灰度+Alpha、6 真彩+Alpha；隔行：0 非隔行、1 Adam7。
    JPEG 仅支持基线（baseline），渐进式（progressive）在部分平台不支持。]]
    local function img_info(path)
        local f = io.open(path, "rb") or io.open(path, "r")
        if not f then return nil end
        local sig = f:read(8) or ""
        f:close()

        -- ---- PNG：89 50 4E 47 0D 0A 1A 0A ----
        if #sig >= 8 and sig:byte(1) == 0x89 and sig:byte(2) == 0x50
            and sig:byte(3) == 0x4E and sig:byte(4) == 0x47 then
            local g = io.open(path, "rb") or io.open(path, "r")
            if not g then return nil, nil, "PNG" end
            local hdr = g:read(33)
            g:close()
            -- 首个数据块必须是 IHDR（标识位于第 13~16 字节），否则文件已损坏
            if not hdr or #hdr < 33 or hdr:sub(13, 16) ~= "IHDR" then
                return nil, nil, "PNG", "文件头不完整或损坏"
            end
            local function be32(s, i)
                return s:byte(i) * 0x1000000 + s:byte(i + 1) * 0x10000 + s:byte(i + 2) * 0x100 + s:byte(i + 3)
            end
            local w, h = be32(hdr, 17), be32(hdr, 21)
            if w <= 0 or h <= 0 then return nil, nil, "PNG", "宽高非法" end
            return w, h, "PNG",
                ("颜色类型%d 隔行%d 位深%d"):format(hdr:byte(26) or -1, hdr:byte(29) or -1, hdr:byte(25) or -1)
        end

        -- ---- JPEG：FF D8 FF … ----
        if #sig >= 3 and sig:byte(1) == 0xFF and sig:byte(2) == 0xD8 and sig:byte(3) == 0xFF then
            local g = io.open(path, "rb") or io.open(path, "r")
            if not g then return nil, nil, "JPEG" end
            g:read(2)   -- 跳过 SOI
            while true do
                local mk = g:read(2)
                if not mk or #mk < 2 or mk:byte(1) ~= 0xFF then break end
                local marker = mk:byte(2)
                if marker == 0x01 or (marker >= 0xD0 and marker <= 0xD7) then
                    -- 无长度字段的标记，直接继续
                elseif marker == 0xD9 then
                    break
                else
                    local lb = g:read(2)
                    if not lb or #lb < 2 then break end
                    local seglen = lb:byte(1) * 256 + lb:byte(2)
                    if seglen < 2 then break end
                    -- SOF0~SOF15（排除 DHT=C4 / JPG=C8 / DAC=CC）内含图像宽高
                    local is_sof = (marker >= 0xC0 and marker <= 0xCF)
                        and marker ~= 0xC4 and marker ~= 0xC8 and marker ~= 0xCC
                    if is_sof then
                        local d = g:read(seglen - 2)
                        if d and #d >= 5 then
                            local h = d:byte(2) * 256 + d:byte(3)
                            local w = d:byte(4) * 256 + d:byte(5)
                            local ptype = (marker == 0xC2 or marker == 0xC6
                                or marker == 0xCA or marker == 0xCE) and "渐进式" or "基线"
                            g:close()
                            if w > 0 and h > 0 then
                                return w, h, "JPEG", ("%s 0x%02X"):format(ptype, marker)
                            end
                            return nil, nil, "JPEG", ptype
                        end
                        break
                    else
                        g:read(seglen - 2)   -- 丢弃该段（不用 seek，兼容性更好）
                    end
                end
            end
            g:close()
            return nil, nil, "JPEG", "未找到 SOF 段"
        end

        return nil, nil, nil, "非 PNG / JPEG"
    end

    local logo_path
    -- 依次尝试：web/ 目录被打包平铺后的标准路径、保留子目录的打包方式、根文件系统
    for _, p in ipairs({ "/luadb/logo.png", "/luadb/web/logo.png", "/logo.png" }) do
        if io.exists(p) then logo_path = p break end
    end

    -- 读取图片头：识别格式并取真实尺寸（用于日志诊断与等比缩放，不作为「能否显示」的前提）
    local logo_fmt, logo_w, logo_h, logo_bottom
    if logo_path then
        local pw, ph, fmt, extra = img_info(logo_path)
        logo_fmt = fmt
        log.info("boot_win", "LOGO 资源:", logo_path, "字节:", io.fileSize(logo_path) or "未知",
            "格式:", fmt or "无法识别", "宽高:", (pw and ph) and (pw .. "x" .. ph) or "解析失败", extra or "")
        log.info("boot_win", "LOGO 文件头:", head_hex(logo_path, 8) or "读取失败")
        if extra and string.find(extra, "渐进式") then
            log.warn("boot_win", "LOGO 是渐进式 JPEG，部分平台不支持，请另存为基线 JPEG 或标准 PNG")
        end
        if logo_fmt == "JPEG" then
            -- airui 的 JPEG 解码依赖硬件，仅部分平台支持（Air8301 不在支持之列），
            -- 且要求图片宽高均为 16 的倍数；若照片区为空白，请用「画图」另存为 24 位 PNG。
            log.warn("boot_win", "LOGO 为 JPEG：airui 的 JPEG 解码仅部分平台支持(Air8301 不支持)，"
                .. "若照片区空白请用「画图」另存为 24 位 PNG（宽高需为 16 的倍数）")
        end
        if extra and string.find(extra, "颜色类型3") then
            log.warn("boot_win", "LOGO 是调色板(Palette)PNG，部分平台不支持，建议导出为 24 位真彩 PNG")
        end
        if extra and string.find(extra, "隔行1") then
            log.warn("boot_win", "LOGO 是 Adam7 隔行 PNG，部分平台不支持，建议导出为非隔行 PNG")
        end
        if pw and ph then
            -- 只缩不放（放大会发糊），等比缩放到图片区上限内
            local scale = math.min(IMG_MAX_W / pw, IMG_MAX_H / ph, 1)
            logo_w = math.max(1, math.floor(pw * scale))
            logo_h = math.max(1, math.floor(ph * scale))
        end
    end

    -- 只要格式可识别（PNG / JPEG）就交给 airui 解码显示：
    -- 尺寸解析成功 → 按真实比例「只缩不放」；解析失败 → 退化为 144×144 图片区兜底，不再直接放弃显示
    if logo_path and (logo_fmt == "PNG" or logo_fmt == "JPEG") then
        local bw, bh, lx, ly
        if logo_w and logo_h then
            bw, bh = logo_w, logo_h
            lx = math.floor((SW - bw) / 2)
            ly = SLOT_Y + math.floor((IMG_MAX_H - bh) / 2)   -- 在图片区内垂直居中
        else
            bw, bh = IMG_MAX_H, IMG_MAX_H                     -- 144×144 正方形兜底
            lx = math.floor((SW - bw) / 2)
            ly = SLOT_Y
        end
        theme.image(root, { x = lx, y = ly, w = bw, h = bh, src = logo_path, fit = "contain" })
        logo_bottom = ly + bh
    else
        if logo_path then
            log.warn("boot_win", "LOGO 图片无法识别或不可用，回退为绘制版标识:", logo_path)
        end
        local lsz = 128
        local lx = math.floor((SW - lsz) / 2)
        local ly = SLOT_Y + math.floor((IMG_MAX_H - lsz) / 2)
        local logo_box = theme.box(root, {
            x = lx, y = ly, w = lsz, h = lsz,
            color = theme.C.t1,      -- 深色底块：白底下也能看清（浅色主题的 panel 为白色，会与白底融为一体）
            radius = theme.r("lg") + 6,
            border = theme.C.amber,
        })
        theme.label(logo_box, {
            x = 0, y = math.floor((lsz - (34 + 3)) / 2), w = lsz, h = 34 + 3,
            text = "8301", px_size = 34, color = theme.C.amber,
            align = airui.TEXT_ALIGN_CENTER,
        })
        logo_bottom = ly + lsz
    end

    -- ---- 产品名 ----
    local title_y = logo_bottom + 10
    theme.label(root, {
        x = 0, y = title_y, w = SW, h = 18 + 3,
        text = theme.BRAND, px_size = 18, color = theme.C.t1,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- ---- 版本号（PROJECT / VERSION 由 main.lua 定义） ----
    theme.label(root, {
        x = 0, y = title_y + 23, w = SW, h = 16 + 3,
        text = "版本 " .. tostring(VERSION or ""), px_size = 16, color = theme.C.t3,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- ---- 底部启动指示：文字 + 3 个指示点 ----
    local hint_y = 214
    local txt_w, gap, dw, dgap = 80, 8, 8, 8
    local total = txt_w + gap + dw * 3 + dgap * 2
    local x0 = math.floor((SW - total) / 2)

    theme.label(root, {
        x = x0, y = hint_y, w = txt_w, h = 16 + 3,
        text = "正在启动", px_size = 16, color = theme.C.t2,
        align = airui.TEXT_ALIGN_CENTER,
    })

    local dx = x0 + txt_w + gap
    local dy = hint_y + math.floor((19 - dw) / 2)
    for i = 1, 3 do
        dots[i] = theme.dot(root, {
            x = dx + (i - 1) * (dw + dgap), y = dy, d = dw,
            color = theme.C.stroke,
        })
    end
    tick_dots()   -- 首帧立即点亮第 1 个点

    -- ---- 定时器 ----
    min_timer = sys.timerStart(function()
        min_timer = nil
        min_ok = true
        try_finish()
    end, MIN_SHOW_MS)

    max_timer = sys.timerStart(function()
        max_timer = nil
        log.warn("boot_win", "初始化未在", MAX_WAIT_MS, "ms 内完成，兜底进入首页")
        boot_ok = true
        try_finish()
    end, MAX_WAIT_MS)

    dot_timer = sys.timerLoopStart(tick_dots, DOT_PERIOD_MS)

    -- 粘性标记补查：初始化早于本页创建时（极小概率）不丢事件
    if _G.__boot_init_done then boot_ok = true end
    -- 延后一次尝试：此刻 exwin.open 尚未返回，win_id 还不可用
    sys.timerStart(try_finish, 10)
end

--[[
窗口销毁回调：释放组件与定时器

@local
@function on_destroy
]]
local function on_destroy()
    finished = true
    stop_timers()
    dots = {}
    if root then
        root:destroy()
        root = nil
    end
    win_id = nil
end

--[[
OPEN_BOOT_WIN 消息处理器

@local
@function open_handler
@param string msg 收尾后要打开的首页消息名（缺省 OPEN_IDLE_WIN）
]]
local function open_handler(msg)
    if msg then next_msg = msg end
    if win_id then return end
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = function() end,
        on_lose_focus = function() end,
    })
end

sys.subscribe("OPEN_BOOT_WIN", open_handler)
sys.subscribe("BOOT_INIT_DONE", on_boot_init_done)
