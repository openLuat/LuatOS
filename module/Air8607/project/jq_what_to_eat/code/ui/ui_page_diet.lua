--[[
@module  ui_page_diet
@summary 今天吃什么 - 页面一：减脂餐（50 选 1）
@version 1.0
@date    2026.10.26
@usage
ui_main 建好页面容器后调 M.build(box, ctx)；之后页签切换只做容器显隐，
本页结果会一直保留，直到下一次点「再转一次」。

右侧面板（页面内坐标，面板原点 648,10，内边距 22，内容宽 324）：
  y  30..62   类别胶囊「减脂餐」 + 右上角 #编号
  y  72..116  菜名（30px）
  y 126       分隔线
  y 146..412  「菜谱要点」小标题 + 多行菜谱（15px，靠 w 自动换行）
  y 428..500  奶油提示条（50 道菜的说明 + 英文副标）
]]

local T = require "ui_theme"
local D = require "ui_draw"
local F = require "foods"
local Wheel = require "ui_wheel"

local C = T.c
local M = {}

local wheel, lb_idx, lb_name, lb_tip, lb_note, ctx
local busy = false
local tip_box_y0 = 0

--[[把菜谱正文垂直居中在 160..320 这一段里
行高按「字号 * 1.32」估，折行数按 D.text_w 估；估歪最多上下差几像素，不影响阅读。]]
local function set_tip(text)
    lb_tip:set_text(text)
    local CW = T.panel.w - T.panel.pad * 2
    local lines = math.max(1, math.ceil(D.text_w(text, T.f.recipe) / CW))
    local h = lines * math.floor(T.f.recipe * 1.32) + 4
    local y = tip_box_y0 + math.max(0, math.floor((160 - h) / 2))
    D.set_pos(lb_tip, T.panel.x + T.panel.pad, y)
end

function M.build(box, c)
    ctx = c
    local P = T.panel
    local x0 = P.x + P.pad
    local CW = P.w - P.pad * 2

    -- 面板底卡
    D.box(box, P.x, P.y, P.w, P.h, { color = C.card, radius = P.radius, border = C.line, border_w = 1 })

    -- 类别胶囊
    local chip = D.box(box, x0, P.y + 20, 96, 32, { color = C.diet_chip, radius = 16 })
    D.label_mid(chip, 0, 16, 96, "减脂餐", T.f.small, C.diet_chip_t, D.ALIGN_CENTER)

    -- 编号
    lb_idx = D.label_mid(box, x0 + CW - 146, P.y + 36, 146, "#--", T.f.mid, C.accent, D.ALIGN_RIGHT)

    -- 菜名
    lb_name = D.label(box, x0, P.y + 62, CW, 44, "今天吃哪道？", T.f.big, C.ink)

    -- 分隔线 + 小标题
    D.box(box, x0, P.y + 116, CW, 2, { color = C.line })
    D.box(box, x0, P.y + 136, 4, 14, { color = C.accent, radius = 2 })
    D.label_mid(box, x0 + 10, P.y + 143, 220, "菜谱要点", T.f.small, C.mute)

    --[[菜谱正文
    菜谱长度差别很大（19 ~ 57 字），固定 y 会让短菜谱下面空一大块。
    这里按估算的折行数把文本在 160..320 的区间里垂直居中（label 支持 set_pos），
    长短菜谱看起来都是「一块居中的正文」，版面不塌。]]
    tip_box_y0 = P.y + 160
    lb_tip = D.label(box, x0, tip_box_y0, CW, 160,
        "50 道少油少盐的家常减脂菜，转到哪道就吃哪道。", T.f.recipe, C.sub)

    -- 分隔线 + 小贴士（通用做法规矩，按菜序号固定搭配，见 foods.slim_tips）
    D.box(box, x0, P.y + 336, CW, 2, { color = C.line })
    D.box(box, x0, P.y + 354, 4, 12, { color = C.yellow, radius = 2 })
    D.label_mid(box, x0 + 10, P.y + 360, 200, "小贴士", T.f.mini, C.mute)
    lb_note = D.label(box, x0, P.y + 376, CW, 44,
        "少油少盐，能焯水的就先焯后炒。", T.f.small, C.sub)

    -- 底部提示条
    D.box(box, x0, P.y + 428, CW, 62, { color = C.cream, radius = 18 })
    D.label_mid(box, x0, P.y + 448, CW, "共 50 道 · 转到哪道吃哪道", T.f.small, C.sub, D.ALIGN_CENTER)
    D.label_mid(box, x0, P.y + 470, CW, "SHAKE IT AGAIN", T.f.mini, C.faint, D.ALIGN_CENTER)

    -- 转盘
    wheel = Wheel.new({
        parent = box,
        rings = T.rings.diet,
        button_text = "开饭",
        on_button = function() M.start() end,
    })
    M.wheel = wheel -- 供离屏预览 / 现场调试拿到句柄

    log.info("page.diet", "构建完成", D.text_w("香煎鸡胸西蓝花", T.f.big), "px")
end

local function spin_body()
    local t0 = D.now_ms()
    local n = #F.diet
    local idx = math.random(1, n)
    wheel:reset_hits()
    wheel:set_button("转动中", true)
    wheel:spin_to(1, idx, { duration = T.spin.single_ms, turns = T.spin.single_turns })

    local d = F.diet[idx]
    wheel:mark_hit(1, idx)
    lb_idx:set_text(string.format("#%02d", idx))
    lb_name:set_text(d.name)
    set_tip(d.tip)
    -- 小贴士按菜序号取模固定搭配，同一道菜每次都是同一条
    lb_note:set_text(F.slim_tips[(idx - 1) % #F.slim_tips + 1])
    wheel:set_button("再转一次", false)
    log.info("page.diet", "落点", idx, d.name, "耗时", D.now_ms() - t0, "ms")
end

-- 转盘任务：正常结束与异常结束都复位 busy，避免一次异常锁死页签
local function spin_task()
    local ok, err = pcall(spin_body)
    busy = false
    if ctx and ctx.set_busy then ctx.set_busy(false) end
    if not ok then
        log.error("page.diet", "转盘异常", tostring(err))
        if wheel then pcall(wheel.set_button, wheel, "开饭", false) end
    end
end

function M.start()
    if busy or not wheel then return end
    busy = true
    if ctx and ctx.set_busy then ctx.set_busy(true) end
    sys.taskInit(spin_task)
end

return M
