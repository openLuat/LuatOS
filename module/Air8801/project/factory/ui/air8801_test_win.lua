--[[
@module  air8801_test_win
@summary 功能测试页（Air8801 出厂检测）
@version 3.2
@date    2026.11.24
@usage
订阅: OPEN_OTHER_FUNC_WIN

v3.4：串口项按 K8801 型号的电平段（TTL/232）只显示一项，结果表键统一为 "serial"；
      裸屏型号（LCD 段）不显示标定入口，校准项显示「无触摸」。
v3.2：串口项改为「电脑回传」（不再用工装短接 TX/RX）：
      设备先发 3 字节 A8K → 电脑把这 3 字节发回 → 10 s 内收到一致即通过。
v3.1：恢复「串口 UART」回环测试（UART2 9600 8N1，工装短接 TX/RX），
      与蜂鸣器、SD/TF、SPI Flash 并列为自动测试项。
v3.0：屏幕五色、九点触摸、背光 20%/40% 双档曾一并移除：
      - 五色与九点改为开机四点标定 + 人工目检，不再单独开页面
      - 背光调节统一走「设置 → 显示亮度」的可拖动滑块
]]
local theme = require "ui_theme"
local factory = require "air8801_factory"
local touch = require "air8801_touch"
local cal = require "air8801_touch_cal"
local cfg = require "air8801_config"

-- 串口项由型号的电平段（TTL/232）决定，只出现一项，不让人在界面上猜硬件
local items = {
    {id = "buzzer", name = "蜂鸣器", icon = "other_func", desc = "D120 · PWM1 2700Hz · 180ms 短音", action = "播放短音"},
    {id = "sd", name = "SD/TF 卡", icon = "storage", desc = "J100 · FAT 卡 8 KiB 读写", action = "读写测试"},
    {id = "flash", name = "SPI Flash", icon = "storage", desc = "SPI6 · 根文件系统 8 KiB 读写", action = "读写测试"},
    factory.serial_info(),
    {id = "cal", name = "触摸校准", icon = "mouse", desc = "四点标定 · 覆盖现有系数", action = "开始标定"},
    {id = "video", name = "视频演示", icon = "img", desc = "HZV 内置素材 · 全屏播放", action = "打开"},
}
local list_id, cal_timer

local function button(parent, x, y, w, text, fn)
    return theme.button(parent, {x = x, y = y, w = w, h = theme.dp(42), text = text, on_click = fn})
end

--[[列表右侧状态。校准项不在 factory 结果表里，按触摸实际状态显示：
裸屏没有触摸芯片，电容屏没有标定概念，NS2009 未绑定则连标定入口都进不去。]]
local function state_of(id)
    -- 视频演示不是 factory 测试项，没有结果表，单独给个固定文案
    if id == "video" then return "播放" end
    if id ~= "cal" then return factory.result(id).state end
    if not touch.enabled() then return "无触摸" end
    if not touch.resistive() then return "不支持" end
    if not touch.ready() then return "未就绪" end
    return touch.calibrated() and "已标定" or "未标定"
end

local function tip(text)
    airui.msgbox({title = "触摸校准", text = text, buttons = {"确定"},
        on_action = function(dialog) dialog:destroy() end})
end

--[[标定完成后刷新列表里的「已标定/未标定」。
标定页画在 airui.screen 上、不是 exwin 窗口，所以不会触发本页 on_get_focus，
只能轮询模块的 status 收尾（SAVED / SAVE_FAILED 都不会再回到 RUNNING）。]]
local function watch_cal(refresh)
    if cal_timer then sys.timerStop(cal_timer) end
    local ticks = 0
    cal_timer = sys.timerLoopStart(function()
        ticks = ticks + 1
        -- 失败后如果还没有有效系数会 1 秒后自动重开，所以只认最终落盘结果；
        -- 再给 3 分钟上限，防止任何意外状态下轮询常驻。
        if cal.status == "SAVED" or cal.status == "SAVE_FAILED" or ticks > 360 then
            sys.timerStop(cal_timer)
            cal_timer = nil
            refresh()
        end
    end, 500)
end

local function open_cal(refresh)
    if not touch.enabled() then
        tip("当前为裸屏型号（LCD 段），板上没有触摸芯片，无标定。")
        return
    end
    if not touch.resistive() then
        tip("当前为电容屏，芯片自带绝对坐标，不需要标定。")
        return
    end
    if not touch.ready() then
        tip("NS2009 未就绪，无法标定。请检查触摸排线与 3.3V 供电。")
        return
    end
    airui.msgbox({
        title = "触摸校准",
        text = "将用四点重新标定并覆盖现有系数。\n开始后必须依次按住四个十字并松手，中途无法退出。",
        buttons = {"取消", "开始"},
        on_action = function(dialog, chosen)
            dialog:destroy()
            if chosen ~= "开始" then return end
            local ok, reason = cal.open()
            if ok then
                watch_cal(refresh)
            else
                tip("标定启动失败：" .. tostring(reason))
            end
        end,
    })
end

local function open_item(item, refresh_cal)
    if item.id == "cal" then open_cal(refresh_cal); return end
    -- 视频演示走独立的 exwin 页面，不参与 factory 的分步测试流程
    if item.id == "video" then sys.publish("OPEN_VIDEO_WIN"); return end
    local id, ctx, label
    local function update(key, result)
        if key == item.id and label then label:set_text(result.state .. "  " .. result.detail) end
    end
    id = exwin.open({
        on_create = function()
            ctx = theme.page({title = item.name, sub = item.desc, icon = item.icon,
                on_back = function() exwin.close(id) end})
            local box = theme.card(ctx.base, {x = ctx.x, y = ctx.y, w = ctx.w, h = ctx.h, scrollable = true})
            local gap, bw = theme.dp(8), (ctx.w - 5 * theme.dp(8)) // 4
            label = theme.label(box, {x = gap, y = gap, w = ctx.w - 2 * gap, h = theme.dp(65)})
            update(item.id, factory.result(item.id))
            sys.subscribe("AIR8801_TEST_RESULT", update)
            local x, y = gap, theme.dp(78)
            button(box, x, y, bw, item.action, function()
                if not factory.run(item.id) then label:set_text("等待当前测试完成") end
            end)
            if item.id == "buzzer" then
                x = x + bw + gap
                button(box, x, y, bw, "通过", function()
                    if factory.result(item.id).state ~= "待确认" then return end
                    factory.report(item.id, "通过", "现场确认")
                end)
                x = x + bw + gap
                button(box, x, y, bw, "异常", function()
                    if factory.result(item.id).state == "待确认" then factory.report(item.id, "失败", "现场确认异常") end
                end)
            end
        end,
        on_destroy = function()
            sys.unsubscribe("AIR8801_TEST_RESULT", update)
            if ctx then ctx.base:destroy() end
        end,
    })
end

local function open()
    if list_id then return end
    local ctx, labels = nil, {}
    local function update(id, result) if labels[id] then labels[id]:set_text(result.state) end end
    local function refresh_cal() if labels.cal then labels.cal:set_text(state_of("cal")) end end
    list_id = exwin.open({
        on_create = function()
            -- 副标题直接读型号解析结果：1024x600 电阻触摸 / 1024x600 电容触摸 / 1024x600 裸屏
            ctx = theme.page({title = "功能测试", sub = "K8801  |  " .. cfg.screen_desc,
                on_back = function() exwin.close(list_id) end})
            local row_h = theme.dp(58)
            local height = #items * row_h + 2
            local box = theme.card(ctx.base, {x = ctx.x, y = ctx.y, w = ctx.w, h = math.min(height, ctx.h),
                scrollable = height > ctx.h})
            for i, item in ipairs(items) do
                local _, _, label = theme.row(box, {x = 0, y = 1 + (i - 1) * row_h, w = ctx.w - 2, h = row_h,
                    text = item.name, sub = item.desc, icon = item.icon, right = state_of(item.id),
                    right_w = theme.dp(90), on_click = function() open_item(item, refresh_cal) end})
                labels[item.id] = label
            end
            sys.subscribe("AIR8801_TEST_RESULT", update)
        end,
        on_destroy = function()
            sys.unsubscribe("AIR8801_TEST_RESULT", update)
            if cal_timer then sys.timerStop(cal_timer); cal_timer = nil end
            if ctx then ctx.base:destroy() end
            list_id = nil
        end,
    })
end

sys.subscribe("OPEN_OTHER_FUNC_WIN", open)
