--[[
@module  other_func_win
@summary 功能测试页面（TabOS 深色玻璃态）——UVC / RS485 / 串口 / 录音播放 测试入口、背光与音量调节
@version 1.7
@date    2026.11.09
@author  江访
@usage
订阅: OPEN_OTHER_FUNC_WIN
发布: OTHER_FUNC_GET / OTHER_FUNC_SET(id, enabled)
订阅: OTHER_FUNC_STATUS(list) / OTHER_FUNC_CHANGED(list) / OTHER_FUNC_SET_RESULT(id, ok, err)
发布: DISPLAY_BRIGHTNESS_GET / DISPLAY_BRIGHTNESS_SET(level) /
      AUDIO_VOLUME_GET / AUDIO_VOLUME_SET(level) / AUDIO_PLAY_TEST
订阅: DISPLAY_BRIGHTNESS_VALUE(level) / DISPLAY_BRIGHTNESS_CHANGED(level) /
      AUDIO_VOLUME_VALUE(level) / AUDIO_VOLUME_CHANGED(level)
订阅: TEST_WIN_CLOSED        -- 三个测试页的 on_destroy 各发一次；本页收口断电

页面按 UVC / RS485 / 串口 / 音频 四组展示实例，组内保持 config.peripherals 声明顺序。
RS485 不管配了几路，列表里只出一行「RS485 测试」（见 MERGE_TITLE），几路全进同一个
收发测试页逐路列出；其余 type 一条配置一行，下方显示驱动上报的状态描述。
分组标题默认取 TYPE_TITLE，配置条目写了 title 时用条目自己的（摄像头是人脸识别模组
的板子写 "摄像头"，避免「UVC 摄像头」分组配「人脸识别摄像头」行名打架）。

行可点即测试：点行先给这一路（合并行是全部成员）上电开接口，再进测试页 —— UVC 行进
预览页（预览/拍照/录像），RS485 行进收发测试页（发送 + 收发历史），音频行进录音播放
测试页（录音/停止/播放），开窗事件见 TYPE_PAGE；没有测试页的 type 行不可点。
行上不再有开关，行尾只留状态圆点 + ">" 提示；退出测试页自动断电（TEST_WIN_CLOSED）。
外设列表之后是「背光调节」「音量调节」两张硬件能力卡（滑块 + 试听按钮），按 backlight.pwm_ch
与 hw.audio 自动门控，不进任何测试结果统计。

点行进测试页前先弹该功能的「接线提示」（只写物理接线与注意事项），按钮「跳过 / 确定」：
跳过不落盘，下次点同一个功能还会弹；确定写 fskv 键 other_func_tip_<type>，之后（含重启）不再弹。
只有配了测试页的 type 才有提示（uart 没有测试页，行不可点）。原来底部那行常驻小字已去掉。
两张能力卡的滑条对象高 SLIDER_H = 20dp（圆球直径 = h + 2 × knob padding，见 theme.slider），
比早期的 34dp 大白球小一圈；圆球不再用纯白（浅色主题上和卡片糊在一起），走 theme.slider 的
默认色 M.C.t1。音量卡的「试听」是按钮（ghost_button，青色描边）而不是文字链接。
]]

local theme = require "ui_theme"

local window_id = nil
local main_container = nil

local sw, sh = 480, 800
local pad = 15

-- 外设 type → 分组标题（顺序按 TYPE_ORDER 定）
local TYPE_TITLE = {
    uvc   = "UVC 摄像头",
    rs485 = "RS485",
    uart  = "串口",
    audio = "音频",
}
local TYPE_ORDER = { "uvc", "rs485", "uart", "audio" }

-- 外设 type → 子页开窗事件；nil 表示该 type 暂无测试页，行不可点
local TYPE_PAGE = {
    uvc   = "OPEN_UVC_PREVIEW_WIN",
    rs485 = "OPEN_RS485_TEST_WIN",
    uart  = nil,
    audio = "OPEN_AUDIO_TEST_WIN",
}

-- 合并成单行入口的 type：配置里有几条都只出一行，几路全在子页里逐路列
local MERGE_TITLE = {
    rs485 = "RS485 测试",
}

-- 实例行控件：行键 → { info_label, info_w, dot, members, state, info }
-- 合并行的行键是 type 名，其余行的行键是实例 id
local rows = {}
-- 实例 id → 行键（合并行下多个 id 指向同一行）
local row_of = {}
-- 进测试页时打开的实例：{ ids = {id...} }，TEST_WIN_CLOSED 收口时逐个断电
local g = { active = nil }

local function update_screen_size()
    sw, sh = screen_w or 480, screen_h or 800
    sw, sh = theme.content_fit(sw, sh)
    pad = theme.page_margin()
end

-- 提示弹窗（标题 + 一句说明 + 单个确定按钮）
local function show_tip(text)
    airui.msgbox({
        title = "提示", text = text, buttons = { "确定" },
        on_action = function(self) self:hide() end,
    })
end

-- ==================== 进测试页前的接线提示 ====================
-- 点某个功能行时先弹一次该功能的「物理接线提醒」，按钮「跳过 / 确定」：
--   「跳过」不落盘 → 下次点同一个功能还会弹
--   「确定」写 fskv（按 type 记）→ 该功能之后（含重启）不再弹
-- 只有配了测试页的 type 才有提示；uart 没有测试页，行不可点，也就不需要。
local TIP_KV_PREFIX = "other_func_tip_"
-- 只写「要接什么线、要注意什么」，不写软件操作说明（那些在测试页里）
local TIP_TEXT = {
    uvc = "进入预览前请确认：\n"
        .. "1. 摄像头已插到板载 USB Host 口（或模组排线插牢）；\n"
        .. "2. 摄像头由使能脚控电，进页面自动上电、退出自动断电，请勿带电插拔；\n"
        .. "3. 黑屏时先查排线与供电，再退出重进重试。",
    rs485 = "进入收发测试前请确认：\n"
        .. "1. A 接 A、B 接 B，线序接反收不到数据；\n"
        .. "2. 长距离或高波特率时，总线两端按需接 120 欧终端电阻；\n"
        .. "3. 外接设备与板卡共地，供电电压一致。",
    audio = "进入录音播放测试前请确认：\n"
        .. "1. 麦克风接到对应接口，未接时录音会失败；\n"
        .. "2. 喇叭 / 功放供电正常，音量已调到可听见；\n"
        .. "3. 录音时保持环境安静，录完点播放回听。",
}
local tip_box = nil

--[[
@function tip_acked
@summary 该功能是否已确认过接线提示（fskv 无记录 / fskv 未就绪一律按未确认）
@param string type_name 外设 type
@return boolean
]]
local function tip_acked(type_name)
    if not (fskv and fskv.get) then return false end
    local ok, v = pcall(fskv.get, TIP_KV_PREFIX .. tostring(type_name))
    return ok and (v == "1" or v == 1 or v == true)
end

--[[
@function ack_tip
@summary 记住「确定」过的接线提示，之后不再弹
@param string type_name 外设 type
]]
local function ack_tip(type_name)
    if not (fskv and fskv.set) then return end
    pcall(fskv.set, TIP_KV_PREFIX .. tostring(type_name), "1")
end

--[[
@function collect_instances
@summary 按 usb_mode 过滤后的 config.peripherals 收集可管理实例，按 type 分组并保持声明顺序
合并类型的全部实例并成一行，成员 id 全挂在这一行上
@return table  { { type=, title=, items={ {key=, name=, type=, page=, members={id...}}, ... } }, ... }
]]
local function collect_instances()
    local cfg = _G.project_config or {}
    local usb_mode = require "usb_mode"
    local list = usb_mode.filter(cfg.peripherals)
    local groups = {}
    local by_type = {}
    local seen = {}
    if type(list) == "table" then
        for i, p in ipairs(list) do
            local t = p and p.type
            if TYPE_TITLE[t] then
                -- id 是 UI 与业务层的匹配键，必填且全表唯一；缺/重直接跳过，与业务层同规则
                if not p.id then
                    log.warn("other_func_win", "外设缺 id，跳过", t, "#" .. i)
                elseif seen[p.id] then
                    log.warn("other_func_win", "外设 id 重复，跳过", p.id)
                else
                    seen[p.id] = true
                    local g = by_type[t]
                    if not g then
                        g = { type = t, title = p.title or TYPE_TITLE[t], items = {} }
                        by_type[t] = g
                        groups[#groups + 1] = g
                    end
                    if MERGE_TITLE[t] then
                        -- 同 type 全并一行，行里挂全部成员 id
                        local it = g.items[1]
                        if not it then
                            it = {
                                key = t,
                                name = MERGE_TITLE[t],
                                type = t,
                                page = TYPE_PAGE[t],
                                members = {},
                            }
                            g.items[1] = it
                        end
                        it.members[#it.members + 1] = p.id
                    else
                        g.items[#g.items + 1] = {
                            key = p.id,
                            name = p.name or p.id or t,
                            type = t,
                            page = TYPE_PAGE[t],
                            members = { p.id },
                        }
                    end
                end
            end
        end
    end

    -- 分组按 TYPE_ORDER 排定，未出现的 type 不建组
    local out = {}
    for _, t in ipairs(TYPE_ORDER) do
        if by_type[t] then out[#out + 1] = by_type[t] end
    end
    return out
end

--[[
@function enter_test
@summary 进测试页：先给这一路（合并行是全部成员）上电开接口，再开窗
退出测试页由 TEST_WIN_CLOSED 统一断电
@param table it 实例行
]]
local function enter_test(it)
    for i = 1, #it.members do
        sys.publish("OTHER_FUNC_SET", it.members[i], true)
    end
    -- 记下本次打开的是哪几路，测试页销毁时逐个断电
    g.active = { ids = it.members }
    sys.publish(it.page, it.members[1])
end

--[[
@function open_row
@summary 行点击：该功能有接线提示且没确认过就先弹窗，「跳过 / 确定」都继续进测试页
只有「确定」会记住（按 type 落 fskv），「跳过」下次点同一个功能还会弹
@param table it 实例行
]]
local function open_row(it)
    local tip = TIP_TEXT[it.type]
    if not tip or tip_acked(it.type) then
        enter_test(it)
        return
    end
    if tip_box then return end   -- 已有提示窗时不叠第二个
    tip_box = airui.msgbox({
        parent = main_container,
        w = math.floor((sw or 480) * 0.86),   -- 只给宽度，高度按内容自适应
        title = it.name or "接线提示",
        text = tip,
        style = { text_font_size = theme.fs("body") },
        buttons = { "跳过", "确定" },
        on_action = function(dlg, btn)
            tip_box = nil
            if btn == "确定" then ack_tip(it.type) end
            if dlg then dlg:destroy() end
            enter_test(it)
        end,
    })
end

--[[
@function build_item_row
@summary 单行入口：名称 + 状态描述 + 状态圆点 + （可点进子页）
@param parent 父容器
@param x, y, w, h 行几何
@param it 实例行 { key, name, type, page, members }
]]
local function build_item_row(parent, x, y, w, h, it)
    -- 有子页的行整行可点：先弹该功能的接线提示，再上电进测试页
    local row = theme.box(parent, {
        x = x, y = y, w = w, h = h, color = theme.C.black, opa = 0,
        on_click = it.page and function() open_row(it) end or nil,
    })

    local pad2 = theme.dp(12)
    local gap2 = theme.dp(10)
    local dot_d = theme.dp(10)
    -- 可点行在行尾补一个 ">" 提示，宽度从文本区让出
    local chev_w = it.page and (theme.dp(10) + gap2) or 0
    local dot_w = dot_d + gap2

    local fs = theme.fs("body")
    local fs_sub = theme.fs("micro")
    local lh = fs + 3
    local lh_sub = fs_sub + 3
    local total = lh + theme.dp(2) + lh_sub
    local ty = math.floor((h - total) / 2)
    if ty < 0 then ty = 0 end

    local txw = w - pad2 * 2 - dot_w - chev_w
    if txw < theme.dp(40) then txw = theme.dp(40) end

    theme.label(row, {
        x = pad2, y = ty, w = txw, h = lh,
        text = theme.fit_text(tostring(it.name or ""), txw, fs), px_size = fs,
        color = theme.C.t1, align = airui.TEXT_ALIGN_LEFT,
    })

    local info_label = theme.label(row, {
        x = pad2, y = ty + lh + theme.dp(2), w = txw, h = lh_sub,
        text = "读取中...", px_size = fs_sub,
        color = theme.C.t3, align = airui.TEXT_ALIGN_LEFT,
    })

    if it.page then
        theme.label(row, {
            x = w - pad2 - theme.dp(10),
            y = math.floor((h - lh) / 2), w = theme.dp(10), h = lh,
            text = ">", px_size = fs,
            color = theme.C.t3, align = airui.TEXT_ALIGN_CENTER,
        })
    end

    -- 行尾状态圆点：开 = 绿、关 = 轨道灰、驱动未就绪 = 弱描边灰
    -- 圆点半径给直径值即可（radius 会被 theme 再过一次 dp，LVGL 夹到 min(w,h)/2）
    local dot = theme.box(row, {
        x = w - pad2 - chev_w - dot_d,
        y = math.floor((h - dot_d) / 2), w = dot_d, h = dot_d,
        radius = dot_d, color = theme.C.stroke_soft,
    })

    local rec = {
        info_label = info_label, info_w = txw, dot = dot,
        members = it.members, state = {}, info = {},
    }
    rows[it.key] = rec
    for i = 1, #it.members do
        row_of[it.members[i]] = it.key
    end
end

-- ==================== 背光 / 音量：硬件能力调节卡 ====================
-- 这两项不是 config.peripherals 外设，不进 collect_instances()，排在外设列表之后。
-- 事件链现成可用（业务层 settings_display_app.lua），本页零业务改动。
-- 背光 / 音量调节卡的控件引用，VALUE / CHANGED 回灌时就地刷新
local brightness_label, brightness_slider
local volume_label, volume_slider

-- 滑条对象高度（= 轨道高度，圆球直径 = h + 2 × knob padding，见 theme.slider 注释）：
-- 取 20 时轨道约 14px、圆球约 30px，比早期 34 + 10 的大白球小一圈，也不至于难拖
local SLIDER_H = 20
-- 底部动作行高度：动作文字改成按钮后，行高要装得下按钮
local ACTION_H = 30

--[[
@function hw_caps
@summary 硬件能力门控：背光可调光 / 有音频硬件
只看 hw 配置（与「亮度和声音」设置页同口径），不新增 features/ui 开关。
纯亮灭的板子（gpio_bl / params.pin_bl）没有 pwm_ch，背光不可调。
@return boolean 背光支持 PWM 调光, boolean 配置了 hw.audio
]]
local function hw_caps()
    local hw = (_G.project_config and _G.project_config.hw) or {}
    local bl = hw.lcd and hw.lcd.backlight
    return (bl and bl.pwm_ch ~= nil) and true or false, hw.audio ~= nil
end

--[[
@function slider_card_height
@summary 调节卡高度：上下留白 + 标题行 + 间距 + 滑条 + （动作行）
与 build_slider_card 的排布逐项对应，调用方据此接排下一张卡
@param has_action 是否有底部动作行（音量卡的「试听」）
@return number 像素高度
]]
local function slider_card_height(has_action)
    local h = theme.dp(12) + (theme.fs("body") + 3) + theme.dp(10) + theme.dp(SLIDER_H) + theme.dp(12)
    if has_action then h = h + theme.dp(10) + theme.dp(ACTION_H) end
    return h
end

--[[
@function build_slider_card
@summary 调节卡：标题 + 数值 + 可拖滑块 + （可选）底部动作
样式照抄 ui/settings/settings_sound_win.lua 的同名卡片：一条 set_event 字符串做回调，
拖动直接发 sys.publish(set_event, value)，min/max 与业务层夹取区间一致
（亮度 10~100，媒体音量 0~100）。滑条对象高 SLIDER_H = 20dp，圆球直径 = 高度 + knob
padding（约 30px），比早期的大白球小一圈；底部动作是按钮而不是文字链接。
@param parent 父容器
@param x, y, w 卡片几何（高度自算，随返回值带回）
@param title 卡片标题
@param value_text 初值文案
@param min, max, value 滑块区间与初值
@param color 数值文字与滑块进度色
@param set_event 滑块回调事件名
@param action 底部动作 { text=, event= }，nil 表示不要动作行
@return 数值 label, 滑块, 卡片高度
]]
local function build_slider_card(parent, x, y, w, title, value_text, min, max, value,
                                 color, set_event, action)
    local h = slider_card_height(action ~= nil)
    local card = theme.card(parent, { x = x, y = y, w = w, h = h })
    local pad2 = theme.dp(12)
    local gap2 = theme.dp(10)
    local fs = theme.fs("body")
    local lh = fs + 3
    local inner_w = w - 2 * pad2
    -- 标题与数值同一行左右分占：按数值栏实宽倒推标题栏，别用比例（高倍密度下会压到数值）
    local val_w = theme.dp(90)
    local tw = inner_w - val_w - gap2

    theme.label(card, {
        x = pad2, y = pad2, w = tw, h = lh,
        text = theme.fit_text(title, tw, fs), px_size = fs,
        color = theme.C.t1, align = airui.TEXT_ALIGN_LEFT,
    })
    local val = theme.label(card, {
        x = w - pad2 - val_w, y = pad2, w = val_w, h = lh,
        text = value_text, px_size = fs,
        color = color, align = airui.TEXT_ALIGN_RIGHT,
    })

    local sl_h = theme.dp(SLIDER_H)
    local sl_y = pad2 + lh + gap2
    local bar = theme.slider(card, {
        x = pad2, y = sl_y, w = inner_w, h = sl_h,
        min = min, max = max, value = value,
        -- 圆球不传 knob_color：走 theme.slider 的缺省色 t1（浅色主题深球、深色主题浅球），
        -- 原来的纯白球在浅色主题上和卡片糊在一起
        track = theme.C.track, color = color,
        on_change = function(self)
            sys.publish(set_event, self:get_value())
        end,
    })

    if action then
        theme.ghost_button(card, {
            x = pad2, y = sl_y + sl_h + gap2,
            w = theme.dp(88), h = theme.dp(ACTION_H),
            text = action.text, size = theme.F.small,
            fg = theme.C.cyan, border = theme.C.cyan,
            on_click = function() sys.publish(action.event) end,
        })
    end

    return val, bar, h
end

--[[
@function build_note_card
@summary 只读说明卡：硬件不支持调节时占一行说明，文字风格同行内状态描述
@param parent 父容器
@param x, y, w 卡片几何
@param text 说明文字
@return number 卡片高度
]]
local function build_note_card(parent, x, y, w, text)
    local h = theme.dp(40)
    local card = theme.card(parent, { x = x, y = y, w = w, h = h })
    theme.label(card, {
        x = theme.dp(12), y = 0, w = w - 2 * theme.dp(12), h = h,
        text = text, px_size = theme.fs("body"),
        color = theme.C.t3, align = airui.TEXT_ALIGN_LEFT,
    })
    return h
end

local function build_ui()
    update_screen_size()
    main_container = theme.page_bg(airui.screen, sw, sh)
    local _, th = theme.header(main_container, {
        x = pad, y = pad, w = sw - 2 * pad,
        title = "功能测试",
        sub = "外设测试入口与亮度音量调节",
        on_back = function() exwin.close(window_id) end,
    })

    local y = pad + th + pad
    local card_w = sw - 2 * pad
    local avail = sh - y - pad

    -- 内容区可滚动：实例数随机型变化（1~4 条），放不下时向下滚
    local body = theme.box(main_container, {
        x = pad, y = y, w = card_w, h = avail,
        color = theme.C.black, opa = 0, scrollable = true,
    })

    local groups = collect_instances()
    local gap = theme.dp(12)
    local row_h = theme.dp(56)
    local sec_h = theme.fs("micro") + 3 + theme.dp(6)
    local bw = 1
    local cy = 0

    if #groups == 0 then
        -- 没有外设也照排下面的背光 / 音量卡，这里只占一行提示
        theme.label(body, {
            x = 0, y = cy + theme.dp(20), w = card_w, h = theme.fs("body") + 3,
            text = "当前机型未配置外设", px_size = theme.fs("body"),
            color = theme.C.t3, align = airui.TEXT_ALIGN_CENTER,
        })
        cy = cy + theme.dp(20) + theme.fs("body") + 3 + gap
    end

    for _, grp in ipairs(groups) do
        theme.section(body, {
            x = theme.dp(4), y = cy, w = card_w - theme.dp(8), h = sec_h,
            text = grp.title, px_size = theme.fs("micro"), color = theme.C.t3,
        })
        cy = cy + sec_h

        local n = #grp.items
        local card = theme.card(body, {
            x = 0, y = cy, w = card_w, h = n * row_h + 2 * bw, border_w = bw,
        })
        local inner_w = card_w - 2 * bw
        for i, it in ipairs(grp.items) do
            local ry = (i - 1) * row_h
            build_item_row(card, 0, ry, inner_w, row_h, it)
            if i < n then
                theme.divider(card, {
                    x = theme.dp(12), y = ry + row_h, w = inner_w - 2 * theme.dp(12),
                })
            end
        end
        cy = cy + n * row_h + 2 * bw + gap
    end

    -- ===== 背光 / 音量调节：硬件能力卡，排在外设列表之后 =====
    local can_dim, has_audio = hw_caps()

    theme.section(body, {
        x = theme.dp(4), y = cy, w = card_w - theme.dp(8), h = sec_h,
        text = "背光调节", px_size = theme.fs("micro"), color = theme.C.t3,
    })
    cy = cy + sec_h
    if can_dim then
        local bh
        brightness_label, brightness_slider, bh = build_slider_card(body, 0, cy, card_w,
            "屏幕亮度", "100%", 10, 100, 100, theme.C.amber, "DISPLAY_BRIGHTNESS_SET", nil)
        cy = cy + bh + gap
    else
        cy = cy + build_note_card(body, 0, cy, card_w, "本机型背光不支持调光") + gap
    end

    theme.section(body, {
        x = theme.dp(4), y = cy, w = card_w - theme.dp(8), h = sec_h,
        text = "音量调节", px_size = theme.fs("micro"), color = theme.C.t3,
    })
    cy = cy + sec_h
    if has_audio then
        local vh
        volume_label, volume_slider, vh = build_slider_card(body, 0, cy, card_w,
            "媒体音量", "70%", 0, 100, 70, theme.C.cyan, "AUDIO_VOLUME_SET",
            { text = "试听", event = "AUDIO_PLAY_TEST" })
        cy = cy + vh + gap
    else
        cy = cy + build_note_card(body, 0, cy, card_w, "本机型未配置音频") + gap
    end
end

--[[
@function row_text
@summary 行的第二行文字：单实例给驱动描述，合并行给「几路 / 打开几路」
@param r 行记录
@return string
]]
local function row_text(r)
    local n = #r.members
    local on, known = 0, 0
    for i = 1, n do
        local v = r.state[r.members[i]]
        if v ~= nil then
            known = known + 1
            if v then on = on + 1 end
        end
    end
    if known == 0 then return "驱动未就绪" end
    if n == 1 then return tostring(r.info[r.members[1]] or "") end
    return string.format("%d 路 | 已打开 %d/%d", n, on, n)
end

--[[
@function update_row
@summary 按行内各实例的状态刷新文字与状态圆点
@param r 行记录
]]
local function update_row(r)
    if not r then return end
    local n = #r.members
    local on, known = 0, 0
    for i = 1, n do
        local v = r.state[r.members[i]]
        if v ~= nil then
            known = known + 1
            if v then on = on + 1 end
        end
    end
    if r.info_label and not r.info_label:is_destroyed() then
        r.info_label:set_text(theme.fit_text(row_text(r), r.info_w or 0, theme.fs("micro")))
    end
    -- 圆点只表示开 / 关：合并行要全开才算开，未就绪压到弱灰
    if r.dot and not r.dot:is_destroyed() then
        local c = theme.C.stroke_soft
        if known > 0 then c = (on == n) and theme.C.green or theme.C.track end
        r.dot:set_color(c, 255)
    end
end

--[[
@function apply_list
@summary 用驱动状态列表刷新各行状态描述与状态圆点
@param list { { id=, enabled=, info= }, ... }
]]
local function apply_list(list)
    if type(list) ~= "table" then return end
    -- 每次整份重填，列表始终是全量快照，避免上一轮的残留状态
    for _, r in pairs(rows) do
        r.state = {}
        r.info = {}
    end
    for _, s in ipairs(list) do
        if s then
            local r = rows[row_of[s.id] or s.id]
            if r then
                r.state[s.id] = s.enabled and true or false
                r.info[s.id] = tostring(s.info or "")
            end
        end
    end
    for _, r in pairs(rows) do
        update_row(r)
    end
end

--[[
@function on_set_result
@summary 通断电操作回执，失败时给出原因
@param id 实例 id
@param ok 是否成功
@param err 失败原因

最终状态不在这里回滚：OTHER_FUNC_CHANGED 带着驱动的权威状态紧随其后，
会把状态描述与圆点对齐到真实值，这里只负责报错。
]]
local function on_set_result(id, ok, err)
    if not ok then
        show_tip(tostring(err or "操作失败"))
    end
end

--[[
@function on_test_win_closed
@summary 测试页销毁收口：把进测试页时打开的那几路逐个断电
三个测试页（uvc_preview_win / rs485_test_win / audio_test_win）的 on_destroy
各发一次 TEST_WIN_CLOSED；exwin.close 与系统返回最终都落到 on_destroy。
]]
local function on_test_win_closed()
    local a = g.active
    g.active = nil
    if type(a) ~= "table" or type(a.ids) ~= "table" then return end
    for i = 1, #a.ids do
        sys.publish("OTHER_FUNC_SET", a.ids[i], false)
    end
end

--[[
@function on_brightness
@summary 背光亮度回灌：查询返回值与变更通知同口径，滑块与数值就地刷新
@param level 亮度 10~100
]]
local function on_brightness(level)
    level = tonumber(level)
    if not level then return end
    if brightness_label then brightness_label:set_text(tostring(level) .. "%") end
    if brightness_slider then brightness_slider:set_value(level) end
end

--[[
@function on_volume
@summary 媒体音量回灌：查询返回值与变更通知同口径，滑块与数值就地刷新
@param level 音量 0~100
]]
local function on_volume(level)
    level = tonumber(level)
    if not level then return end
    if volume_label then volume_label:set_text(tostring(level) .. "%") end
    if volume_slider then volume_slider:set_value(level) end
end

local function on_create()
    rows = {}
    row_of = {}
    g.active = nil
    build_ui()
    sys.subscribe("OTHER_FUNC_STATUS", apply_list)
    sys.subscribe("OTHER_FUNC_CHANGED", apply_list)
    sys.subscribe("OTHER_FUNC_SET_RESULT", on_set_result)
    sys.subscribe("TEST_WIN_CLOSED", on_test_win_closed)
    sys.publish("OTHER_FUNC_GET")
    -- 背光 / 音量进页面各查一次初值，回灌走 VALUE / CHANGED
    sys.subscribe("DISPLAY_BRIGHTNESS_VALUE", on_brightness)
    sys.subscribe("DISPLAY_BRIGHTNESS_CHANGED", on_brightness)
    sys.publish("DISPLAY_BRIGHTNESS_GET")
    local _, has_audio = hw_caps()
    if has_audio then
        sys.subscribe("AUDIO_VOLUME_VALUE", on_volume)
        sys.subscribe("AUDIO_VOLUME_CHANGED", on_volume)
        sys.publish("AUDIO_VOLUME_GET")
    end
end

local function on_destroy()
    sys.unsubscribe("OTHER_FUNC_STATUS", apply_list)
    sys.unsubscribe("OTHER_FUNC_CHANGED", apply_list)
    sys.unsubscribe("OTHER_FUNC_SET_RESULT", on_set_result)
    sys.unsubscribe("TEST_WIN_CLOSED", on_test_win_closed)
    sys.unsubscribe("DISPLAY_BRIGHTNESS_VALUE", on_brightness)
    sys.unsubscribe("DISPLAY_BRIGHTNESS_CHANGED", on_brightness)
    local _, has_audio = hw_caps()
    if has_audio then
        sys.unsubscribe("AUDIO_VOLUME_VALUE", on_volume)
        sys.unsubscribe("AUDIO_VOLUME_CHANGED", on_volume)
    end
    -- 本页先于测试页销毁时 TEST_WIN_CLOSED 已无人收，这里补一次断电兜底
    on_test_win_closed()
    -- 提示弹窗挂在页面容器上，随容器一起销毁，这里只清掉 Lua 侧引用
    tip_box = nil
    if main_container then main_container:destroy(); main_container = nil end
    rows = {}
    row_of = {}
    brightness_label, brightness_slider = nil, nil
    volume_label, volume_slider = nil, nil
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_OTHER_FUNC_WIN", open_handler)
