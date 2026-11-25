-- Air8606 风格的 C1 本机及扩展底板测试。
local theme = require "ui_theme"
local factory = require "air8607c1_factory"
local board = require "air8607c1_board"
local baseboard = require "air8607c1_baseboard"
local cfg = require "air8607c1_config"
local w1ui = require "air8607w1_test_win"

local items = {
    {id = "buzzer", name = "蜂鸣器", icon = "other_func",
        desc = "GPIO73 | 听 BUZ1 短音"},
    {id = "flash", name = "SPI Flash", icon = "storage",
        desc = "SPI6 | 根文件系统写入、读回及删除 " .. (cfg.flash_test.size // 1024) .. " KiB"},
    {id = "lcd", name = "屏幕显示", icon = "img",
        desc = "RGB565 | 依次查看五种纯色"},
    {id = "pwm", name = "PWM", icon = "other_func",
        desc = "PWM1 | J100-25 测量 1 kHz、50% 占空比"},
    {id = "backlight", name = "背光", icon = "brightness",
        desc = "PWM3 | 切换 20% 和 40% 占空比"},
    {id = "touch", name = "触摸", icon = "mouse",
        desc = "GT911 / I2C1 | 四角、四边和中心"},
}
local expansion_items = {
    {id = "wifi", name = "Wi-Fi", icon = "search", interactive = true,
        desc = "Air6205 / SPI5 | 扫描、连接及 HTTP 验证"},
    {id = "dac", name = "DAC喇叭", icon = "other_func",
        desc = "J102 / HT6873 | 播放前隔离 C1 蜂鸣器支路"},
    {id = "sd", name = "SD/TF 卡", icon = "storage",
        desc = "J216 / SPI1 | 8 KiB 写入、读回及删除"},
    {id = "ttl", name = "TTL 串口", icon = "other_func", interactive = true,
        desc = "J3 / UART2 | 9600 8N1，使用 3.3 V USB–TTL 工装"},
    {id = "rs232", name = "RS232", icon = "other_func", interactive = true,
        desc = "J3 / UART2 | 9600 8N1，使用 USB–RS232 工装"},
    {id = "rs485", name = "隔离 RS485", icon = "other_func", interactive = true,
        desc = "J1 / UART1 | 9600 8N1，A、B、隔离地接 USB–RS485 工装"},
    {id = "uvc", name = "UVC 摄像头", icon = "img", interactive = true,
        desc = "J8 / AirCAMERA_1034 | USB 与摄像头 UART 电源侧接同源 5 V"},
    {id = "vrtc", name = "CR2032 备电", icon = "other_func", interactive = true,
        desc = "VRTC | 断主电 " .. cfg.w1.vrtc.off_seconds .. " 秒后 RTC 保持"},
}
local colors = {
    ["通过"] = function() return theme.SEM.success end,
    ["失败"] = function() return theme.SEM.danger end,
    ["待确认"] = function() return theme.SEM.warning end,
    ["测试中"] = function() return theme.SEM.info end,
}
local patterns = {
    {"红", 0xFF0000}, {"绿", 0x00FF00}, {"蓝", 0x0000FF}, {"白", 0xFFFFFF}, {"黑", 0x000000},
}

local function show_result(label, result, with_detail)
    local color = colors[result.state]
    label:set_color(color and color() or theme.C.t2)
    label:set_text(with_detail and result.detail ~= "" and (result.state .. "：" .. result.detail) or result.state)
end

local function run_notice(text)
    airui.msgbox({
        title = "功能测试", text = text, buttons = {"确定"},
        on_action = function(dialog) dialog:destroy() end,
    })
end

local function confirm_hardware(text, apply, confirm_text)
    local caption = confirm_text or "确认"
    airui.msgbox({
        title = "工装确认", text = text, w = theme.dp(500), buttons = {"取消", caption},
        on_action = function(dialog, choice)
            dialog:destroy()
            if choice == caption then apply() end
        end,
    })
end

local function button(parent, x, y, w, label, fn)
    return theme.button(parent, {x = x, y = y, w = w, h = theme.dp(42), text = label, on_click = fn})
end

local function open_lcd()
    local window_id, surface
    local index = 1
    local viewed_all = false
    window_id = exwin.open({
        on_create = function()
            factory.wait_for_check("lcd", "依次查看红、绿、蓝、白、黑")
            local w, h = screen_w, screen_h
            surface = theme.box(airui.screen, {x = 0, y = 0, w = w, h = h, color = patterns[1][2], opa = 255})
            theme.bind_root(surface)
            local bh = theme.dp(78)
            local bar = theme.box(surface, {x = 0, y = h - bh, w = w, h = bh, color = theme.C.bg, opa = 255})
            local pad, gap = theme.dp(12), theme.dp(8)
            local sw = (w - 2 * pad - 3 * gap) // 4
            local hint = theme.label(bar, {x = pad, y = 4, w = w - 2 * pad, h = theme.dp(24)})
            local function update()
                surface:set_color(patterns[index][2], 255)
                hint:set_text(string.format("%s色 %d / %d  |  检查花屏、缺色和亮点", patterns[index][1], index, #patterns))
            end
            button(bar, pad, theme.dp(30), sw, "下一色", function()
                index = index % #patterns + 1
                if index == #patterns then viewed_all = true end
                update()
            end)
            button(bar, pad + sw + gap, theme.dp(30), sw, "通过", function()
                if not viewed_all then
                    hint:set_text("请先查看五种纯色")
                    return
                end
                factory.confirm("lcd", true, "五种纯色已确认")
                exwin.close(window_id)
            end)
            button(bar, pad + 2 * (sw + gap), theme.dp(30), sw, "异常", function()
                factory.confirm("lcd", false, "屏幕显示异常")
                exwin.close(window_id)
            end)
            button(bar, pad + 3 * (sw + gap), theme.dp(30), sw, "返回", function() exwin.close(window_id) end)
            update()
        end,
        on_destroy = function()
            factory.cancel("lcd")
            if surface then surface:destroy() end
        end,
    })
end

local function open_touch()
    local window_id, root
    window_id = exwin.open({
        on_create = function()
            local w, h = screen_w, screen_h
            root = theme.box(airui.screen, {x = 0, y = 0, w = w, h = h, color = theme.C.bg, opa = 255})
            theme.bind_root(root)
            local seen, count = {}, 0
            local bw, bh, gap = theme.dp(68), theme.dp(54), theme.dp(12)
            local progress = theme.label(root, {x = 0, y = h // 4, w = w, h = theme.dp(34),
                align = airui.TEXT_ALIGN_CENTER, text = "依次点击九个触摸点：0 / 9"})
            if _G.c1_touch_ready then
                factory.wait_for_check("touch", "等待九点触摸")
            else
                factory.fail("touch", "GT911 未就绪")
                progress:set_text("GT911 未就绪，请检查触摸排线")
            end
            for row, y in ipairs({gap, (h - bh) // 2, h - bh - gap}) do
                for col, x in ipairs({gap, (w - bw) // 2, w - bw - gap}) do
                    local id = (row - 1) * 3 + col
                    theme.button(root, {x = x, y = y, w = bw, h = bh, text = tostring(id), on_click = function(widget)
                        if not _G.c1_touch_ready or seen[id] then return end
                        seen[id], count = true, count + 1
                        widget:set_text("OK")
                        progress:set_text(string.format("触摸点 %d / 9%s", count, count == 9 and "  |  已完成" or ""))
                        if count == 9 then factory.confirm("touch", true, "九个触摸点均响应") end
                    end})
                end
            end
            button(root, (w - theme.dp(124)) // 2, h - bh - theme.dp(62), theme.dp(124),
                "返回", function() exwin.close(window_id) end)
        end,
        on_destroy = function()
            factory.cancel("touch")
            if root then root:destroy() end
        end,
    })
end

--[[DAC 播放测试页里的媒体音量调节（对齐「亮度和声音」那张卡）
拖动即写回：AUDIO_VOLUME_SET 走全局生效点（试听与播报都用新音量），
同时同步 w1.dac.volume，让「播放测试语音」按滑块音量播。
@return 解绑函数（窗口销毁时调用）]]
local function build_volume_card(base, x, y, w)
    local gap = theme.dp(12)
    local card = theme.card(base, {x = x, y = y, w = w, h = theme.dp(120)})
    theme.label(card, {x = gap, y = theme.dp(12), w = w - 2 * gap - theme.dp(84),
        h = theme.dp(26), text = "媒体音量", size = theme.F.body, color = theme.C.t1})
    local value = theme.label(card, {x = w - gap - theme.dp(84), y = theme.dp(12),
        w = theme.dp(84), h = theme.dp(26), text = "--%", size = theme.F.body,
        color = theme.C.cyan, align = airui.TEXT_ALIGN_RIGHT})
    local bar = theme.slider(card, {x = gap, y = theme.dp(46), w = w - 2 * gap,
        h = theme.dp(30), min = 0, max = 100, value = 0,
        track = theme.C.track, color = theme.C.cyan,
        on_change = function(self)
            local v = self:get_value()
            value:set_text(tostring(v) .. "%")
            sys.publish("AUDIO_VOLUME_SET", v)
            cfg.w1.dac.volume = v
        end})
    -- 试听做成描边小按钮（label 没有点击态，看着像行内文字，也不好点中）
    -- 点击后在按钮右侧回一句提示，没声音时也能看出「确实响应了」
    local tip = theme.label(card, {x = gap + theme.dp(104), y = theme.dp(80),
        w = w - 2 * gap - theme.dp(104), h = theme.dp(30),
        text = "", size = theme.F.tiny, color = theme.C.t3})
    theme.ghost_button(card, {x = gap, y = theme.dp(78), w = theme.dp(96),
        h = theme.dp(32), text = "试听", size = 14,
        on_click = function()
            sys.publish("AUDIO_PLAY_TEST")
            if tip and not tip:is_destroyed() then tip:set_text("播放中…") end
            sys.timerStart(function()
                if tip and not tip:is_destroyed() then tip:set_text("") end
            end, 2000)
        end})
    local function sync(v)
        v = tonumber(v) or 0
        bar:set_value(v)
        value:set_text(tostring(v) .. "%")
    end
    sys.publish("AUDIO_VOLUME_GET")
    sys.subscribe("AUDIO_VOLUME_VALUE", sync)
    sys.subscribe("AUDIO_VOLUME_CHANGED", sync)
    return function()
        sys.unsubscribe("AUDIO_VOLUME_VALUE", sync)
        sys.unsubscribe("AUDIO_VOLUME_CHANGED", sync)
    end
end

local function open_item(item)
    if factory.is_busy() then run_notice("请等待正在执行的测试完成"); return end
    if item.id == "lcd" then open_lcd(); return end
    if item.id == "touch" then open_touch(); return end
    if item.interactive then w1ui.open(item, show_result); return end

    local id = item.id
    local window_id, ctx, status
    local session = {}
    local tested_levels = {}
    local restore_backlight = false
    local unbind_volume
    local function update(key, result)
        if key == id and status then show_result(status, result, true) end
    end

    local function test_backlight(level)
        if _G.is_pc then factory.wait_for_check(id, "PC 预览不操作背光"); return end
        if factory.result(id).state ~= "待确认" then
            tested_levels = {}
            factory.wait_for_check(id, "分别切换两档亮度")
        end
        restore_backlight = true
        local ok, applied = pcall(board.set_backlight, level)
        if not ok or not applied then
            factory.fail(id, "PWM3 无法设置为 " .. level .. "%")
            return
        end
        tested_levels[level] = true
        status:set_text(string.format("当前 %d%%。%s", level,
            (tested_levels[20] and tested_levels[40]) and "确认背光确有变化后点「通过」。" or "请再切换另一档。"))
    end

    window_id = exwin.open({
        on_create = function()
            ctx = theme.page({title = item.name, sub = item.desc, icon = item.icon,
                on_back = function() exwin.close(window_id) end})
            local card = theme.card(ctx.base, {x = ctx.x, y = ctx.y, w = ctx.w, h = theme.dp(150)})
            local gap = theme.dp(12)
            status = theme.label(card, {x = gap, y = gap, w = ctx.w - 2 * gap, h = theme.dp(65)})
            show_result(status, factory.result(id), true)
            sys.subscribe("C1_TEST_RESULT", update)
            local bw = (ctx.w - 5 * gap) // 4
            local x = gap
            local function add(label, fn)
                button(card, x, theme.dp(88), bw, label, fn)
                x = x + bw + gap
            end
            if id == "backlight" then
                add("20% 背光", function() test_backlight(20) end)
                add("40% 背光", function() test_backlight(40) end)
            else
                local label = (id == "flash" or id == "sd") and "读写测试" or "播放短音"
                if id == "pwm" then label = "输出 2 秒" end
                if id == "dac" then label = "播放测试语音" end
                add(label, function()
                    local function start()
                        if session.closed then return end
                        if not factory.run(id, session) then run_notice("请等待正在执行的测试完成") end
                    end
                    if id == "dac" then
                        confirm_hardware("确认底板 J102 已接喇叭，且 C1 的 BUZ1 或 R422 已断电断开。", start)
                    elseif id == "pwm" then
                        confirm_hardware("GPIO65 也控制底板 J8 电源。确认 J8 上的 USB 设备已拔下。", start)
                    else
                        start()
                    end
                end)
            end
            if id ~= "flash" and id ~= "sd" then
                add("通过", function()
                    if factory.result(id).state ~= "待确认" then return end
                    if id == "backlight" and not (tested_levels[20] and tested_levels[40]) then
                        status:set_text("请先切换 20% 和 40% 两档亮度")
                        return
                    end
                    factory.confirm(id, true)
                end)
                add("异常", function() factory.confirm(id, false) end)
            end
            -- DAC 播放测试：下面再挂一张媒体音量卡，边播边调音量和试听
            if id == "dac" then
                unbind_volume = build_volume_card(ctx.base, ctx.x,
                    ctx.y + theme.dp(150) + theme.dp(12), ctx.w)
            end
        end,
        on_destroy = function()
            session.closed = true
            if unbind_volume then unbind_volume(); unbind_volume = nil end
            sys.unsubscribe("C1_TEST_RESULT", update)
            if restore_backlight then
                local ok, restored = pcall(board.set_backlight, cfg.hw.lcd.backlight.level)
                if not ok or not restored then factory.fail(id, "恢复原背光亮度失败") end
            end
            factory.cancel(id)
            if ctx then ctx.base:destroy() end
        end,
    })
end

-- 底板型号选择页：测试页右上角那个「底板型号 Air8607W1」按钮已按需求移除，
-- 两个页签改为均分整行。此实现先保留，后续若要恢复入口（设置页/长按标题）直接接上即可。
local function open_baseboard_models()
    if factory.is_busy() then run_notice("请等待正在执行的测试完成"); return end
    local current = baseboard.current()
    local window_id, ctx
    window_id = exwin.open({
        on_create = function()
            ctx = theme.page({title = "底板型号", sub = "当前 " .. current.name .. " | 选择与实物一致的型号",
                on_back = function() exwin.close(window_id) end})
            local row_h = theme.dp(58)
            local wanted = #cfg.expansion_models * row_h + 2
            local card = theme.card(ctx.base, {x = ctx.x, y = ctx.y, w = ctx.w,
                h = math.min(ctx.h, wanted), scrollable = ctx.h < wanted})
            for i, model in ipairs(cfg.expansion_models) do
                local description = {}
                if model.wifi then description[#description + 1] = "Wi-Fi" end
                description[#description + 1] = model.uart2 == "ttl" and "TTL 串口" or "RS232"
                description[#description + 1] = "隔离 RS485"
                description[#description + 1] = model.audio == "dac" and "DAC 喇叭" or "蜂鸣器"
                theme.row(card, {x = 0, y = 1 + (i - 1) * row_h, w = ctx.w - 2, h = row_h,
                    text = model.name, sub = table.concat(description, " / "),
                    right = model == current and "使用中" or "", right_w = theme.dp(92),
                    on_click = function()
                        if model == current then return end
                        confirm_hardware("将底板型号设为 " .. model.name .. "，重启后生效。", function()
                            if not ctx then return end
                            local ok, reason = factory.select_baseboard(model.name)
                            if not ok then run_notice(reason) end
                        end, "保存并重启")
                    end})
                if i < #cfg.expansion_models then
                    theme.divider(card, {x = theme.dp(12), y = i * row_h, w = ctx.w - theme.dp(24)})
                end
            end
        end,
        on_destroy = function()
            if ctx then ctx.base:destroy(); ctx = nil end
        end,
    })
end

local list_id
local function open()
    if list_id then return end
    local ctx, list, states = nil, nil, {}
    local page = 1
    local function update(id, result)
        local state = states[id]
        if state then show_result(state, result, false) end
    end
    local function draw()
        if list then list:destroy() end
        list = theme.box(ctx.base, {x = ctx.x, y = ctx.y, w = ctx.w, h = ctx.h, opa = 0})
        states = {}
        local gap, tab_h = theme.dp(8), theme.dp(42)
        -- 只有两个页签：整行均分（原来三列还挤着一个「底板型号」按钮，两个页签太窄）
        local tab_w = (ctx.w - gap) // 2
        for i, caption in ipairs({"C1 本机", "扩展底板"}) do
            local tab = i == page and theme.button or theme.ghost_button
            tab(list, {x = (i - 1) * (tab_w + gap), y = 0, w = tab_w, h = tab_h,
                text = caption, on_click = function()
                    if page ~= i then page = i; draw() end
                end})
        end
        local visible = {}
        for _, item in ipairs(page == 1 and items or expansion_items) do
            if baseboard.supports(item.id) then visible[#visible + 1] = item end
        end
        local row_h = theme.dp(58)
        local list_y = tab_h + gap
        local wanted = #visible * row_h + 2
        local card = theme.card(list, {x = 0, y = list_y, w = ctx.w,
            h = math.min(ctx.h - list_y, wanted), scrollable = ctx.h - list_y < wanted})
        for i, item in ipairs(visible) do
            local _, _, label = theme.row(card, {
                x = 0, y = 1 + (i - 1) * row_h, w = ctx.w - 2, h = row_h,
                text = item.name, sub = item.desc, icon = item.icon, right = "未测试",
                right_w = theme.dp(92), on_click = function() open_item(item) end,
            })
            states[item.id] = label
            update(item.id, factory.result(item.id))
            if i < #visible then
                theme.divider(card, {x = theme.dp(12), y = i * row_h, w = ctx.w - theme.dp(24)})
            end
        end
    end
    list_id = exwin.open({
        on_create = function()
            ctx = theme.page({title = "功能测试", sub = "Air8607C1 + " .. baseboard.current().name .. "  |  " .. VERSION,
                on_back = function() exwin.close(list_id) end})
            draw()
            sys.subscribe("C1_TEST_RESULT", update)
        end,
        on_destroy = function()
            sys.unsubscribe("C1_TEST_RESULT", update)
            if ctx then ctx.base:destroy() end
            list_id = nil
        end,
    })
end

sys.subscribe("OPEN_OTHER_FUNC_WIN", open)