--[[
@module  ui_theme
@summary 玻璃拟态双主题（深色 / 浅色，可手动切换 + fskv 记忆）：柔光底 / 半透明玻璃 / 青色高亮 + 微动参数
@version 2.1.0
@usage  改主题只动这一个文件；关闭全部微动把 M.motion.enabled 设为 false。
        颜色 0xRRGGBB，opacity 0-255（越小越透明）。
        与 docs/方案D_玻璃拟态.html（深色 / 浅色两套 CSS 变量）同一套视觉令牌。
        运行中切换：T.set_mode("light"/"dark") 原地更新 M.c / M.glass 的字段并保存 fskv；
        页面收到切换后 destroy + create 原地重建，立即生效，无需重启。
]]
local M = {}

-- ---------- 主题模式：fskv 记忆（固件内置库，直接全局使用，无需 require） ----------
M.mode = "dark"
if fskv then
    pcall(function()
        if fskv.init then fskv.init() end
        local saved = fskv.get("ui_theme_mode")
        log.info("ui_theme", "读取主题偏好", saved)
        if saved == "light" or saved == "dark" then M.mode = saved end
    end)
end

-- ---------- 深色主题（默认）：深空底 / 彩色柔光斑 / 半透明白玻璃 ----------
M.dark = {
    c = {
        -- 文字（深底上保证 ≥4.5:1 对比度）
        text = 0xEDF1F6, text_sub = 0x9AA2B5, text_dim = 0x67708A,
        -- 玻璃叠层：白色低透明度 + 灰蓝描边（LVGL 描边不吃透明度，用偏灰色避免刺眼）
        card = 0xFFFFFF, panel = 0xFFFFFF, edge = 0x59637B, divider = 0x39415A,
        shadow = 0x000000,
        -- 主色：天青 + 深蓝按钮底
        pri = 0x7DD3FC, pri_deep = 0x38BDF8, btn_bg = 0x24344D,
        -- 语义色
        ok = 0x4ADE80, warn = 0xFBBF24, danger = 0xFB7185,
        -- 开关 / 档位 chip
        sw_on = 0x38BDF8, sw_off = 0x3A4356, knob = 0xFFFFFF,
        chip_on = 0x7DD3FC, chip_on_t = 0x0B0D12,           -- 激活 chip：青底深字
        chip_off = 0xFFFFFF, chip_off_t = 0x9AA2B5,
        glow = 0x7DD3FC,                                    -- 数值刷新高亮色
        deep = 0x0F1420,                                    -- 摄像头等深内嵌底
        soft = 0xFFFFFF,                                    -- 极淡装饰（湿度点阵灭点 / 虚线分隔）
    },
    -- 玻璃拟态分层参数：暗色柔光底 + 半透明白玻璃叠层 + 高光描边 + 双层假投影
    -- 说明：LVGL 9 / AirUI 没有背景模糊（backdrop blur），这里用「彩色柔光光斑 +
    -- 低透明度白卡片」近似；以后若有预模糊背景 JPG，直接换掉背景容器即可。
    glass = {
        bg = 0x14161E,                                      -- 深空底
        glow1 = 0x7C3AED, glow2 = 0x0EA5E9,                 -- 紫 / 蓝 光斑
        glow3 = 0xEC4899, glow4 = 0x2DD4BF,                 -- 粉 / 青 光斑
        bg_glow_opa = 34,               -- 大面积光斑透明度（越低越柔）
        card_opa = 38,                  -- 面板白玻璃（≈15%）
        tile_opa = 26,                  -- 行 / 磁贴白玻璃（≈10%）
        panel_opa = 60,
        topbar_opa = 44,
        shadow_opa = 70,                -- 假投影
        shadow_off = 5,                 -- 投影下移像素
        hl_opa = 60,                    -- 顶部反光条
        hl_sweep_opa = 210,             -- 交互时反光条扫光峰值
        card_edge = 2,                  -- 玻璃卡描边宽度：0 = 整屏无框线。描边不参与透明度
                                        -- （LVGL 的 border 不吃 opacity），背景调透明后它照样绘制，
                                        -- 是「幽灵框 / 卡片底边一条横线」的主要来源，嫌线多就设 0
        -- 内嵌层（层级逻辑：浮起 = 更亮，凹陷 = 更暗）
        inset_opa = 150,                -- 面板内嵌控制条（设备调节条）底：深墨色半透，压在玻璃面板上发暗
        track_opa = 14,                 -- 内嵌轨道（− 数值 +）：深底上的一层极淡白，形成凹槽
    },
}

-- ---------- 浅色主题：晨雾底 / 柔和光斑 / 高透明白玻璃 / 深色文字 ----------
M.light = {
    c = {
        text = 0x1F2A3C, text_sub = 0x5B6472, text_dim = 0x8A93A6,
        card = 0xFFFFFF, panel = 0xFFFFFF, edge = 0xC7D0DE, divider = 0xD8DEE9,
        shadow = 0x8892A8,
        pri = 0x0EA5E9, pri_deep = 0x0284C7, btn_bg = 0x334E68,
        ok = 0x16A34A, warn = 0xD97706, danger = 0xE11D48,
        sw_on = 0x0EA5E9, sw_off = 0xD3DAE6, knob = 0xFFFFFF,
        chip_on = 0x0EA5E9, chip_on_t = 0xFFFFFF,
        chip_off = 0xFFFFFF, chip_off_t = 0x5B6472,
        glow = 0x0EA5E9,
        deep = 0xF3F6FA,                                    -- 内嵌底：浅灰白（凹陷）
        soft = 0x94A3B8,                                    -- 湿度点阵灭点 / 虚线分隔
    },
    glass = {
        bg = 0xE2E8F2,                                      -- 晨雾底
        glow1 = 0x93C5FD, glow2 = 0x7DD3FC,                 -- 淡蓝 / 天青 光斑
        glow3 = 0xF9A8D4, glow4 = 0x5EEAD4,                 -- 淡粉 / 薄荷 光斑
        bg_glow_opa = 80,
        card_opa = 165,                 -- 白玻璃要压得住浅底
        tile_opa = 120,
        panel_opa = 210,
        topbar_opa = 190,
        shadow_opa = 36,
        shadow_off = 4,
        hl_opa = 150,
        hl_sweep_opa = 230,
        card_edge = 2,
        inset_opa = 235,                -- 内嵌控制条：浅底上加深一档形成凹槽
        track_opa = 70,
    },
}

-- 生效当前主题：M.c / M.glass 是常驻表，只原地改字段，不换引用。
-- page_glass / ui_widget 在 require 时就把这两张表存进了 local C, G，
-- 若这里改成 M.c = t.c，那些引用会永远停在旧主题；原地改字段才能全局同步。
M.c, M.glass = {}, {}
local function copy_tokens(dst, src)
    for k in pairs(dst) do dst[k] = nil end
    for k, v in pairs(src) do dst[k] = v end
end
function M.apply(mode)
    local t = (mode == "light") and M.light or M.dark
    M.mode = (mode == "light") and "light" or "dark"
    copy_tokens(M.c, t.c)
    copy_tokens(M.glass, t.glass)
end

-- 保存并生效主题偏好：令牌立即更新，页面随后原地重建；fskv 只负责下次开机记忆
function M.set_mode(mode)
    M.apply(mode)
    if fskv then pcall(function()
        fskv.set("ui_theme_mode", M.mode)
        log.info("ui_theme", "保存主题偏好", M.mode)
    end) end
end

M.apply(M.mode)

M.o = { chip = 140, sw_off = 200 }
M.r = { card = 22, panel = 14, chip = 17 }
-- 字号：验收标准「最小字号 16 号」，sub/mini 已并到 16；body 及以上不受影响
M.f = { h1 = 32, title = 28, temp = 46, ac = 32, body = 18, sub = 16, mini = 16 }

-- 微动：全部是「短、局部、状态驱动」的隐性反馈，不做全屏/整卡持续动画
M.motion = {
    enabled     = true,
    instant     = true,  -- 交互反馈全即时（默认）：不建逐帧定时器，状态一帧到位、松手即结束。
                         -- 真机上 Lua 逐帧定时器受其他任务抢占会抖动，动画排队还有拖尾，
                         -- 观感反而廉价；设为 false 可退回补间版本对比。
    frame_ms    = 20,    -- 软补间每帧间隔（sys.timerStart），30→20 更跟手
    press_dy    = 2,     -- 按压下沉像素
    press_fr    = 3,     -- 按压/回弹帧数（约 60ms）
    knob_fr     = 5,     -- 开关滑块缓动（约 100ms）
    glow_fr     = 4,     -- 数值刷新高亮（约 80ms）
    sweep_fr    = 4,     -- 磁贴/按钮高光条扫光（约 80ms）
    enter_dy    = 10,    -- 入场位移
    enter_fr    = 6,     -- 入场约 120ms
    enter_gap   = 60,    -- 各模块依次入场的间隔 ms
    swap_fr     = 4,     -- 房间切换磁贴逐个上浮（约 80ms）
    swap_gap    = 30,    -- 磁贴错开间隔 ms
}

M.screen = { w = 1024, h = 600 }
return M
