--[[
@module  1a2b_win
@summary 1A2B 猜数字游戏窗口
@version 1.0.0
@date    2026.05.12
]]

local win_id = nil
local main_container = nil

-- ============ 设计稿基准 ============
local base_width = 480
local base_height = 800

-- ============ 运行时显示参数 ============
local runtime_display = {
    rotation = 0,
    raw_width = base_width,
    raw_height = base_height,
    logical_width = base_width,
    logical_height = base_height,
    is_landscape = false
}

-- ============ 布局缓存 ============
local layout = {
    width = base_width,
    height = base_height,
    is_landscape = false,
    scale_x = 1,
    scale_y = 1,
    font_scale = 1,
}

-- ============ 游戏状态 ============
local game = {
    secret = "",
    digit_length = 4,
    attempts = 0,
    history = {},
    active = false,
    current_input = "",
    answer_revealed = false,
}

-- ============ UI 引用缓存 ============
local ui = {}

-- ============ 排行榜状态 ============
local leaderboard = {
    win_id = nil,
    main_container = nil,
    items = {},
    data = {},
    page = 1,
    total_pages = 1,
    loading_label = nil,
    pending_upload = nil,  -- {account, nickname, digit_length, attempts}
}

local function get_leaderboard_cls(digit_length)
    return 10 + (digit_length or game.digit_length or 4)
end

-- ============ 资源路径 ============
local function detect_resource_root()
    local nested = "/luadb/res/"
    -- if io and io.exists and io.exists(nested .. "icon_game.png") then
    --     return nested
    -- end
    local flat = "/luadb/"
    if io and io.exists and io.exists(flat .. "icon_game.png") then
        return flat
    end
    return nested
end

local RES_ROOT = detect_resource_root()

-- ============ 工具函数 ============
local function clamp(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function round(value)
    return math.floor(value + 0.5)
end

local function scale_w(value)
    return round(value * (layout.width or base_width) / base_width)
end

local function scale_h(value)
    return round(value * (layout.height or base_height) / base_height)
end

local function scale_font(value)
    return clamp(round(value * layout.font_scale), 12, 48)
end

local function display_value(value, fallback)
    if value and value > 0 then return value end
    return fallback
end

-- ============ 刷新显示参数 ============
local function refresh_runtime_display()
    local raw_width, raw_height = base_width, base_height
    local rotation = 0

    if lcd and lcd.getSize then
        local w, h = lcd.getSize()
        if w and h and w > 0 and h > 0 then
            raw_width, raw_height = w, h
        end
    end

    if airui and airui.get_rotation then
        local r = airui.get_rotation()
        if type(r) == "number" then
            rotation = r % 360
            if rotation < 0 then rotation = rotation + 360 end
        end
    end

    local logical_width, logical_height = raw_width, raw_height
    if rotation == 90 or rotation == 270 then
        logical_width, logical_height = raw_height, raw_width
    end

    runtime_display.rotation = rotation
    runtime_display.raw_width = raw_width
    runtime_display.raw_height = raw_height
    runtime_display.logical_width = logical_width
    runtime_display.logical_height = logical_height
    runtime_display.is_landscape = logical_width > logical_height
end

-- ============ 重建布局 ============
local function rebuild_layout()
    local width = runtime_display.logical_width
    local height = runtime_display.logical_height

    layout.width = display_value(width, base_width)
    layout.height = display_value(height, base_height)
    layout.is_landscape = runtime_display.is_landscape == true
    layout.scale_x = layout.width / base_width
    layout.scale_y = layout.height / base_height
    layout.font_scale = math.min(layout.scale_x, layout.scale_y)

    layout.page_padding = clamp(round(math.min(layout.width, layout.height) * 0.04), 12, 32)
    layout.gap = clamp(round(math.min(layout.width, layout.height) * 0.015), 6, 16)
    layout.corner_radius = clamp(round(math.min(layout.width, layout.height) * 0.02), 4, 12)

    if layout.is_landscape then
        layout.left_panel_w = math.floor(layout.width * 0.58)
        layout.right_panel_x = layout.left_panel_w
        layout.right_panel_w = layout.width - layout.left_panel_w
        -- 矮屏横屏优化：压缩各区域高度，确保左侧面板内容不超出可视区域
        local content_h = layout.height - layout.page_padding * 2
        layout.title_h = clamp(round(content_h * 0.11), 40, 56)
        layout.setting_h = clamp(round(content_h * 0.13), 48, 68)
        layout.info_h = clamp(round(content_h * 0.08), 32, 44)
        layout.input_display_h = clamp(round(content_h * 0.09), 36, 48)
        layout.keyboard_h = content_h - layout.title_h - layout.setting_h - layout.info_h - layout.input_display_h - scale_h(40)
        if layout.keyboard_h < scale_h(120) then layout.keyboard_h = scale_h(120) end
        layout.history_title_h = clamp(round(layout.height * 0.08), 28, 44)
    else
        layout.left_panel_w = layout.width
        layout.title_h = clamp(round(layout.height * 0.08), 48, 72)
        layout.setting_h = clamp(round(layout.height * 0.12), 64, 100)
        layout.info_h = clamp(round(layout.height * 0.06), 32, 52)
        layout.input_display_h = clamp(round(layout.height * 0.07), 36, 56)
        layout.keyboard_h = clamp(round(layout.height * 0.24), 140, 200)
        if layout.keyboard_h < scale_h(120) then layout.keyboard_h = scale_h(120) end
        layout.history_title_h = clamp(round(layout.height * 0.05), 28, 44)
    end
end

-- ============ 游戏逻辑 ============
local function generate_secret(digits)
    digits = clamp(digits, 3, 10)
    local pool = {0,1,2,3,4,5,6,7,8,9}
    local first_idx = math.random(1, 10)
    local first = pool[first_idx]
    table.remove(pool, first_idx)
    local result = {first}
    for i = 2, digits do
        local idx = math.random(1, #pool)
        table.insert(result, pool[idx])
        table.remove(pool, idx)
    end
    return table.concat(result)
end

local function validate_guess(guess, expected_len)
    if not guess or guess == "" then return "请输入数字" end
    if not guess:match("^%d+$") then return "只能包含数字" end
    if #guess ~= expected_len then return "请输入 " .. expected_len .. " 位数字" end
    -- 1A2B 标准规则允许首位为 0
    local seen = {}
    for i = 1, #guess do
        local d = guess:sub(i,i)
        if seen[d] then return "数字不能重复" end
        seen[d] = true
    end
    return nil
end

local function calculate_ab(secret, guess)
    local a, b = 0, 0
    for i = 1, #secret do
        if guess:sub(i,i) == secret:sub(i,i) then
            a = a + 1
        elseif secret:find(guess:sub(i,i), 1, true) then
            b = b + 1
        end
    end
    return a, b
end

local function calculate_score(attempts)
    if attempts >= 1 and attempts <= 5 then
        return 4
    elseif attempts >= 6 and attempts <= 10 then
        return 3
    elseif attempts >= 11 and attempts <= 20 then
        return 2
    else
        return 1
    end
end

local function reset_game()
    game.secret = generate_secret(game.digit_length)
    game.attempts = 0
    game.history = {}
    game.active = true
    game.current_input = ""
    game.answer_revealed = false
    log.info("1a2b", "new game", game.digit_length, "digits")
end

-- ============ UI 更新辅助 ============
local function set_text(comp, text)
    if comp and comp.set_text then comp:set_text(text or "") end
end

local function set_hidden(comp, hidden)
    if comp and comp.set_hidden then comp:set_hidden(hidden) end
end

local function set_color(comp, color)
    if comp and comp.set_color then comp:set_color(color) end
end

-- 计算label在父容器中垂直居中的y坐标
local function vcenter_y(parent_h, font_size)
    return math.floor((parent_h - font_size) / 2)
end

local function update_input_display()
    local display = game.current_input
    while #display < game.digit_length do
        display = display .. "_"
    end
    set_text(ui.input_display_label, display)
end

local function update_info_display()
    set_text(ui.attempt_label, "尝试: " .. game.attempts)
    if ui.answer_label then
        if game.active then
            local mask = ""
            for i = 1, game.digit_length do mask = mask .. "?" end
            set_text(ui.answer_label, "答案: " .. mask)
            set_color(ui.answer_label, 0xEF4B4B)  -- 未猜出：红色
        else
            set_text(ui.answer_label, "答案: " .. (game.secret or ""))
            set_color(ui.answer_label, 0x1A7F3A)  -- 猜对：绿色
        end
    end
end

local function update_history_ui()
    if ui.history_items then
        for _, item in ipairs(ui.history_items) do
            if item.container then item.container:destroy() end
        end
    end
    ui.history_items = {}

    if #game.history == 0 then
        set_text(ui.empty_history_label, "暂无记录，开始游戏吧")
        set_hidden(ui.empty_history_label, false)
        return
    end

    set_hidden(ui.empty_history_label, true)

    local item_h = scale_h(36)
    local gap = scale_h(6)
    local parent = ui.history_container
    local item_w
    if layout.is_landscape then
        item_w = layout.right_panel_w - layout.page_padding * 2
    else
        item_w = layout.width - layout.page_padding * 2
    end

    -- 限制最多显示最近20条，防止过长；最新记录在最上方，从上往下排
    local display_count = math.min(#game.history, 20)

    local history_start_y = layout.history_title_h + scale_h(8)
    for i = 1, display_count do
        -- 从 history 末尾倒序取：i=1 为最新记录
        local record = game.history[#game.history - i + 1]
        local y = history_start_y + (i - 1) * (item_h + gap)
        -- 行容器尺寸略留边距，避免子元素贴边触发滚动条
        local row_w = item_w - scale_w(20)
        local row_h = item_h
        local container = airui.container({
            parent = parent,
            x = scale_w(10), y = y,
            w = row_w, h = row_h,
            color = 0xFFFFFF,
            radius = layout.corner_radius,
        })
        container:set_border_color(0xE2E8F0, 1)

        local text_y = vcenter_y(row_h, scale_font(14))
        local col_w = math.floor(row_w * 0.5) - scale_w(6)
        airui.label({
            parent = container,
            x = scale_w(6), y = text_y,
            w = col_w,
            h = scale_font(20) + 4,
            text = record.guess,
            font_size = scale_font(14),
            color = 0x1E293B,
            align = airui.TEXT_ALIGN_LEFT,
        })

        airui.label({
            parent = container,
            x = math.floor(row_w * 0.5), y = text_y,
            w = col_w,
            h = scale_font(14) + 4,
            text = record.result,
            font_size = scale_font(14),
            color = 0x2E5BFF,
            align = airui.TEXT_ALIGN_RIGHT,
        })

        ui.history_items[i] = { container = container }
    end
end

local function show_message(msg, is_error)
    if ui.msg_label then
        set_text(ui.msg_label, msg)
        ui.msg_label:set_color(is_error and 0xEF4B4B or 0x2E5BFF)
    end
    if ui.msg_timer then
        sys.timerStop(ui.msg_timer)
        ui.msg_timer = nil
    end
    ui.msg_timer = sys.timerStart(function()
        if ui.msg_label then set_text(ui.msg_label, "") end
        ui.msg_timer = nil
    end, 2500)
end

-- ============ 输入处理 ============
local function append_digit(digit)
    if not game.active then
        show_message("请先点击开始游戏", true)
        return
    end
    if #game.current_input >= game.digit_length then
        show_message("已达到 " .. game.digit_length .. " 位", true)
        return
    end
    game.current_input = game.current_input .. digit
    update_input_display()
end

local function backspace()
    if #game.current_input > 0 then
        game.current_input = game.current_input:sub(1, -2)
        update_input_display()
    end
end

local function clear_input()
    game.current_input = ""
    update_input_display()
end

local upload_score

local function submit_guess()
    if not game.active then
        show_message("请先点击开始游戏", true)
        return
    end
    local err = validate_guess(game.current_input, game.digit_length)
    if err then
        show_message(err, true)
        return
    end

    local a, b = calculate_ab(game.secret, game.current_input)
    game.attempts = game.attempts + 1
    local result_str = a .. "A" .. b .. "B"
    table.insert(game.history, { guess = game.current_input, result = result_str })

    update_info_display()
    update_history_ui()
    game.current_input = ""
    update_input_display()

    if a == game.digit_length then
        local score = calculate_score(game.attempts)
        show_message("恭喜猜中！答案正是 " .. game.secret .. "，共尝试 " .. game.attempts .. " 次，获得 " .. score .. " 积分", false)
        game.active = false
        update_info_display()
        if game.answer_revealed then
            show_message("本局已查看过答案，分数不会上传排行榜", true)
        else
            sys.timerStart(function()
                upload_score(game.digit_length, score)
            end, 800)
        end
    else
        show_message(result_str, false)
    end
end

local function reveal_answer()
    if not game.secret or game.secret == "" then
        show_message("请先开始游戏", true)
        return
    end
    game.answer_revealed = true
    show_message("答案是 " .. game.secret, false)
    update_info_display()
end

local function change_digit_length(delta)
    local new_len = clamp(game.digit_length + delta, 3, 10)
    game.digit_length = new_len
    set_text(ui.digit_label, tostring(new_len) .. " 位")
    if game.active and game.secret ~= "" then
        game.active = false
        game.secret = ""
        update_info_display()
        show_message("位数已变更，请重新开始", true)
    end
end

-- ============ 游戏规则弹窗 ============
local function hide_rule_dialog()
    set_hidden(ui.rule_dialog, true)
    set_hidden(ui.rule_mask, true)
end

local function show_rule_dialog()
    if ui.rule_dialog then
        set_hidden(ui.rule_dialog, false)
        set_hidden(ui.rule_mask, false)
        return
    end

    local W2, H2 = layout.width, layout.height
    local P2 = layout.page_padding

    local dialog_w = math.min(scale_w(420), W2 - P2 * 4)
    local dialog_h = scale_h(380)
    local dialog_x = math.floor((W2 - dialog_w) / 2)
    local dialog_y = math.floor((H2 - dialog_h) / 2)

    -- 半透明遮罩（点击关闭）
    local mask = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = W2, h = H2,
        color = 0x000000,
        color_opacity = 100,
        on_click = hide_rule_dialog,
    })

    -- 白色卡片
    local card = airui.container({
        parent = main_container,
        x = dialog_x, y = dialog_y,
        w = dialog_w, h = dialog_h,
        color = 0xFFFFFF,
        radius = layout.corner_radius,
    })

    -- 标题栏背景
    local card_title_h = scale_h(44)
    airui.container({
        parent = card,
        x = 0, y = 0,
        w = dialog_w, h = card_title_h,
        color = 0xF8FAFC,
        radius = layout.corner_radius,
    })

    -- 标题文字
    airui.label({
        parent = card,
        x = scale_w(16),
        y = vcenter_y(card_title_h, scale_font(16)),
        w = dialog_w - scale_w(80),
        h = scale_font(16) + 4,
        text = "游戏规则",
        font_size = scale_font(18),
        color = 0x1E293B,
        align = airui.TEXT_ALIGN_LEFT,
    })

    -- 关闭按钮
    airui.button({
        parent = card,
        x = dialog_w - scale_w(52) - scale_w(8),
        y = math.floor((card_title_h - scale_h(32)) / 2),
        w = scale_w(52), h = scale_h(32),
        text = "X",
        font_size = scale_font(16),
        color = 0x64748B,
        bg_color = 0xE2E8F0,
        radius = math.floor(scale_h(14)),
        on_click = hide_rule_dialog,
    })

    -- 分隔线
    local sep = airui.container({
        parent = card,
        x = scale_w(16), y = card_title_h,
        w = dialog_w - scale_w(32), h = 1,
        color = 0xE2E8F0,
    })

    -- 规则文本（逐行创建，精确控制行间距）
    local rule_lines = {
        "1A2B 猜数字规则：",
        "",
        "1. 系统随机生成 N 位不重复数字（N = 3~10）",
        "2. 每次输入 N 位不重复数字进行猜测",
        "3. 系统反馈 xAyB：",
        "   * A = 数字和位置都正确",
        "   * B = 数字正确但位置不对",
        "4. 示例：答案 1234，猜 1356 → 1A1B",
        "   （1 位置对得 1A，3 存在但位置错得 1B）",
        "5. 猜中全部数字及位置即为胜利",
        "  ",
        "积分规则：",
        "  1~5次猜中  +4分",
        "  6~10次猜中 +3分",
        "  11~20次猜中+2分",
        "  20次以上    +1分",
        "  查看答案后猜中不计分",
    }

    local line_font = scale_font(15)
    local line_h = line_font + 4
    local line_gap = scale_h(8)
    local text_x = scale_w(16)
    local text_w = dialog_w - scale_w(32)
    local start_y = card_title_h + scale_h(12)

    for i, line in ipairs(rule_lines) do
        airui.label({
            parent = card,
            x = text_x,
            y = start_y + (i - 1) * (line_h + line_gap),
            w = text_w,
            h = line_h,
            text = line,
            font_size = line_font,
            color = 0x334155,
            align = airui.TEXT_ALIGN_LEFT,
        })
    end

    ui.rule_dialog = card
    ui.rule_mask = mask
end

-- ============ 排行榜服务器通信 ============
function upload_score(digit_length, score)
    if not exapp or not exapp.iot_get_account_info then
        log.warn("1a2b", "exapp 不可用，跳过上传")
        return
    end
    local ok, info = pcall(exapp.iot_get_account_info)
    if not ok or not info or info.is_guest then
        log.warn("1a2b", "未登录或访客模式，不上传")
        return
    end
    if score <= 0 then
        log.info("1a2b", "本次积分为0，无需上传")
        return
    end
    leaderboard.pending_upload = {
        account = info.account or "unknown",
        nickname = info.nickname or "unknown",
        digit_length = digit_length,
        score = score,
    }
    log.info("1a2b", "查询历史积分", "account:", leaderboard.pending_upload.account,
             "位数:", digit_length, "本次积分:", score)
    exapp.list_record({
        cls = get_leaderboard_cls(digit_length),
        size = 1,
        filter = {
            aks = {"uni_key"},
            acs = {"eq"},
            avs = {leaderboard.pending_upload.account},
        },
    })
end

local function delete_my_score()
    if not exapp or not exapp.iot_get_account_info then
        log.warn("1a2b", "exapp 不可用，无法删除")
        return
    end
    local ok, info = pcall(exapp.iot_get_account_info)
    if not ok or not info or info.is_guest then
        log.warn("1a2b", "未登录或访客模式，无法删除")
        return
    end
    local account = info.account
    local cls = get_leaderboard_cls(leaderboard.digit_length or game.digit_length)
    log.info("1a2b", "查询并删除积分记录", "account:", account, "cls:", cls)
    exapp.list_record({
        cls = cls,
        size = 1,
        filter = {
            aks = {"uni_key"},
            acs = {"eq"},
            avs = {account},
        },
    }, function(success, data)
        if success and data and data.records and #data.records > 0 then
            local rec = data.records[1]
            if rec.uni_key == account and rec.id then
                exapp.delete_record({cls = cls, id = rec.id}, function(del_success, del_result)
                    if del_success then
                        log.info("1a2b", "删除积分记录成功")
                        exapp.list_record({
                            cls = cls,
                            sort = "i1", desc = true, size = 30,
                        }, on_leaderboard_query_callback)
                    else
                        log.warn("1a2b", "删除积分记录失败", del_result)
                    end
                end)
            else
                log.warn("1a2b", "未找到匹配的积分记录")
            end
        else
            log.warn("1a2b", "无积分记录可删除")
        end
    end)
end

-- ============ 排行榜 UI ============
local rebuild_leaderboard_ui

local function switch_leaderboard_digit(delta)
    local new_len = clamp((leaderboard.digit_length or game.digit_length) + delta, 3, 10)
    if new_len == leaderboard.digit_length then return end
    leaderboard.digit_length = new_len
    leaderboard.page = 1
    leaderboard.data = {}
    if leaderboard.loading_label then
        leaderboard.loading_label:destroy()
        leaderboard.loading_label = nil
    end
    rebuild_leaderboard_ui()
    leaderboard.loading_label = airui.label({
        parent = leaderboard.main_container,
        x = 0, y = math.floor(layout.height / 2) - scale_h(20),
        w = layout.width, h = scale_h(30),
        text = "数据同步中，请稍等...",
        font_size = scale_font(14),
        color = 0x1E293B,
        align = airui.TEXT_ALIGN_CENTER,
    })
    exapp.list_record({
        cls = get_leaderboard_cls(new_len),
        sort = "i1", desc = true, size = 30,
    }, on_leaderboard_query_callback)
end

function rebuild_leaderboard_ui()
    if not leaderboard.main_container then return end
    for _, item in ipairs(leaderboard.items) do
        if item then item:destroy() end
    end
    leaderboard.items = {}
    if leaderboard.loading_label then
        leaderboard.loading_label:destroy()
        leaderboard.loading_label = nil
    end

    local W2, H2 = layout.width, layout.height
    local P2 = layout.page_padding
    local title_h = scale_h(48)
    local bottom_h = scale_h(56)
    local content_w = W2 - P2 * 2
    local content_x = P2

    -- 顶部标题栏
    local header_bar = airui.container({
        parent = leaderboard.main_container,
        x = 0, y = 0,
        w = W2, h = title_h,
        color = 0xFFFFFF,
    })
    table.insert(leaderboard.items, header_bar)
    -- 标题栏底部分割线
    airui.container({
        parent = header_bar,
        x = 0, y = title_h - 1,
        w = W2, h = 1,
        color = 0xE2E8F0,
    })
    -- 返回按钮
    airui.button({
        parent = header_bar,
        x = P2,
        y = math.floor((title_h - scale_h(32)) / 2),
        w = scale_w(60), h = scale_h(32),
        text = "返回",
        font_size = scale_font(14),
        color = 0x1E293B,
        bg_color = 0xF1F5F9,
        radius = layout.corner_radius,
        on_click = function()
            if leaderboard.win_id then exwin.close(leaderboard.win_id) end
        end,
    })
    -- 标题
    airui.label({
        parent = header_bar,
        x = 0,
        y = vcenter_y(title_h, scale_font(18)),
        w = W2, h = scale_font(18) + 4,
        text = (leaderboard.digit_length or game.digit_length) .. "位数字排行榜",
        font_size = scale_font(18),
        color = 0x1E293B,
        align = airui.TEXT_ALIGN_CENTER,
    })
    -- 切换位数按钮（左）
    local btn_y = math.floor((title_h - scale_h(32)) / 2)
    local center_x = math.floor(W2 / 2)
    airui.button({
        parent = header_bar,
        x = center_x - scale_w(130),
        y = btn_y,
        w = scale_w(36), h = scale_h(32),
        text = "<",
        font_size = scale_font(16),
        color = 0x1E293B,
        bg_color = 0xEEF3FF,
        radius = layout.corner_radius,
        on_click = function() switch_leaderboard_digit(-1) end,
    })
    -- 切换位数按钮（右）
    airui.button({
        parent = header_bar,
        x = center_x + scale_w(94),
        y = btn_y,
        w = scale_w(36), h = scale_h(32),
        text = ">",
        font_size = scale_font(16),
        color = 0x1E293B,
        bg_color = 0xEEF3FF,
        radius = layout.corner_radius,
        on_click = function() switch_leaderboard_digit(1) end,
    })

    local card_h = scale_h(36)
    local gap = scale_h(6)
    local yPos = title_h + scale_h(16)

    -- 表头
    local header = airui.container({
        parent = leaderboard.main_container,
        x = content_x, y = yPos, w = content_w, h = card_h,
        color = 0xEEF3FF,
        radius = layout.corner_radius,
    })
    table.insert(leaderboard.items, header)

    airui.label({
        parent = header, x = scale_w(8), y = vcenter_y(card_h, scale_font(12)),
        w = scale_w(40), h = scale_font(12) + 4,
        text = "排名", font_size = scale_font(12), color = 0x2E5BFF,
    })
    airui.label({
        parent = header, x = scale_w(55), y = vcenter_y(card_h, scale_font(12)),
        w = scale_w(140), h = scale_font(12) + 4,
        text = "昵称", font_size = scale_font(12), color = 0x2E5BFF,
    })
    airui.label({
        parent = header, x = content_w - scale_w(80), y = vcenter_y(card_h, scale_font(12)),
        w = scale_w(70), h = scale_font(12) + 4,
        text = "积分", font_size = scale_font(12), color = 0x2E5BFF,
        align = airui.TEXT_ALIGN_RIGHT,
    })

    yPos = yPos + card_h + gap

    if #leaderboard.data == 0 then
        local empty = airui.container({
            parent = leaderboard.main_container,
            x = content_x, y = yPos, w = content_w, h = scale_h(80),
            color = 0xFFFFFF,
            radius = layout.corner_radius,
        })
        table.insert(leaderboard.items, empty)
        airui.label({
            parent = empty, x = 0, y = scale_h(20), w = content_w, h = scale_font(14) + 4,
            text = "暂无记录，快来挑战吧！",
            font_size = scale_font(14), color = 0x8AA9CC,
            align = airui.TEXT_ALIGN_CENTER,
        })
    else
        local startIdx = (leaderboard.page - 1) * 11 + 1
        local endIdx = math.min(startIdx + 10, #leaderboard.data)
        local medal_bg = { [1] = 0xFFD700, [2] = 0xC0C0C0, [3] = 0xCD7F32 }

        for i = startIdx, endIdx do
            local record = leaderboard.data[i]
            local nickname = (record.s1 and #record.s1 > 0) and record.s1 or "匿名"
            local score = record.i1 or 0
            local displayName = #nickname > 12 and nickname:sub(1, 12) .. ".." or nickname
            local isTop3 = (i <= 3)
            local bgColor = isTop3 and medal_bg[i] or 0xFFFFFF
            local textColor = 0x1E293B

            local card = airui.container({
                parent = leaderboard.main_container,
                x = content_x, y = yPos, w = content_w, h = card_h,
                color = bgColor,
                radius = layout.corner_radius,
            })
            card:set_border_color(0xE2E8F0, 1)
            table.insert(leaderboard.items, card)

            airui.label({
                parent = card, x = scale_w(8), y = vcenter_y(card_h, scale_font(12)),
                w = scale_w(40), h = scale_font(12) + 4,
                text = tostring(i), font_size = scale_font(12), color = textColor,
            })
            airui.label({
                parent = card, x = scale_w(55), y = vcenter_y(card_h, scale_font(12)),
                w = scale_w(170), h = scale_font(12) + 4,
                text = displayName, font_size = scale_font(12), color = textColor,
            })
            airui.label({
                parent = card, x = content_w - scale_w(80), y = vcenter_y(card_h, scale_font(12)),
                w = scale_w(70), h = scale_font(12) + 4,
                text = tostring(score) .. "分", font_size = scale_font(12), color = 0x2E5BFF,
                align = airui.TEXT_ALIGN_RIGHT,
            })

            yPos = yPos + card_h + gap
        end

        -- 分页
        local pageY = H2 - bottom_h - scale_h(52)
        local prevBtn = airui.button({
            parent = leaderboard.main_container,
            x = content_x, y = pageY, w = scale_w(60), h = scale_h(28),
            text = "上一页", font_size = scale_font(12),
            color = 0xFFFFFF,
            bg_color = leaderboard.page > 1 and 0x2E5BFF or 0x888888,
            radius = layout.corner_radius,
            on_click = function()
                if leaderboard.page > 1 then
                    leaderboard.page = leaderboard.page - 1
                    rebuild_leaderboard_ui()
                end
            end,
        })
        table.insert(leaderboard.items, prevBtn)

        local pageLabel = airui.label({
            parent = leaderboard.main_container,
            x = content_x + scale_w(100), y = pageY + scale_h(4),
            w = scale_w(120), h = scale_font(14) + 4,
            text = string.format("<%d/%d>", leaderboard.page, leaderboard.total_pages),
            font_size = scale_font(14), color = 0x1E293B,
            align = airui.TEXT_ALIGN_CENTER,
        })
        table.insert(leaderboard.items, pageLabel)

        local nextBtn = airui.button({
            parent = leaderboard.main_container,
            x = content_x + content_w - scale_w(60) - scale_w(20), y = pageY,
            w = scale_w(60), h = scale_h(28),
            text = "下一页", font_size = scale_font(12),
            color = 0xFFFFFF,
            bg_color = leaderboard.page < leaderboard.total_pages and 0x2E5BFF or 0x888888,
            radius = layout.corner_radius,
            on_click = function()
                if leaderboard.page < leaderboard.total_pages then
                    leaderboard.page = leaderboard.page + 1
                    rebuild_leaderboard_ui()
                end
            end,
        })
        table.insert(leaderboard.items, nextBtn)
    end

    -- 底部操作栏
    local bottom_bar = airui.container({
        parent = leaderboard.main_container,
        x = 0, y = H2 - bottom_h,
        w = W2, h = bottom_h,
        color = 0xFFFFFF,
    })
    table.insert(leaderboard.items, bottom_bar)
    -- 底部分割线
    airui.container({
        parent = bottom_bar,
        x = 0, y = 0,
        w = W2, h = 1,
        color = 0xE2E8F0,
    })

    -- 刷新按钮
    airui.button({
        parent = bottom_bar,
        x = P2,
        y = math.floor((bottom_h - scale_h(36)) / 2),
        w = scale_w(70), h = scale_h(36),
        text = "刷新",
        font_size = scale_font(13),
        color = 0xFFFFFF,
        bg_color = 0x1A7F3A,
        radius = layout.corner_radius,
        on_click = function()
            exapp.list_record({
                cls = get_leaderboard_cls(leaderboard.digit_length or game.digit_length),
                sort = "i1", desc = true, size = 30,
            }, on_leaderboard_query_callback)
        end,
    })

    -- 删除记录按钮
    airui.button({
        parent = bottom_bar,
        x = math.floor((W2 - scale_w(100)) / 2),
        y = math.floor((bottom_h - scale_h(36)) / 2),
        w = scale_w(100), h = scale_h(36),
        text = "删除记录",
        font_size = scale_font(13),
        color = 0xFFFFFF,
        bg_color = 0xEF4B4B,
        radius = layout.corner_radius,
        on_click = delete_my_score,
    })

    -- 关闭按钮
    airui.button({
        parent = bottom_bar,
        x = W2 - scale_w(70) - P2,
        y = math.floor((bottom_h - scale_h(36)) / 2),
        w = scale_w(70), h = scale_h(36),
        text = "关闭",
        font_size = scale_font(13),
        color = 0xFFFFFF,
        bg_color = 0x64748B,
        radius = layout.corner_radius,
        on_click = function()
            if leaderboard.win_id then exwin.close(leaderboard.win_id) end
        end,
    })
end

local function on_leaderboard_query_callback(success, data)
    if success and data and data.records then
        if leaderboard.loading_label then
            leaderboard.loading_label:destroy()
            leaderboard.loading_label = nil
        end
        leaderboard.data = data.records
        table.sort(leaderboard.data, function(a, b)
            return (tonumber(a.i1) or 0) > (tonumber(b.i1) or 0)
        end)
        local total = data.total or #data.records
        leaderboard.total_pages = math.max(1, math.ceil(total / 11))
        rebuild_leaderboard_ui()
    end
end

local function on_db_result(endpoint, success, data)
    if endpoint ~= "list" then return end
    if leaderboard.pending_upload then
        local up = leaderboard.pending_upload
        leaderboard.pending_upload = nil
        log.info("1a2b", "【积分回调】account:", up.account, "位数:", up.digit_length, "本次积分:", up.score)
        if not exapp or not exapp.add_record then
            log.warn("1a2b", "exapp.add_record 不可用")
            return
        end
        local upload_val = up.score
        if success and data and data.records and #data.records > 0 then
            local rec = data.records[1]
            if rec.uni_key == up.account then
                local total = (tonumber(rec.i1) or 0) + up.score
                upload_val = total
                log.info("1a2b", "累加积分，历史总积分:", rec.i1, "本次:", up.score, "新总积分:", total)
            else
                log.info("1a2b", "uni_key 不匹配，视为首次上传")
            end
        else
            log.info("1a2b", "无历史记录，首次上传")
        end
        pcall(exapp.add_record, {
            cls = get_leaderboard_cls(up.digit_length),
            uni_key = up.account,
            i1 = upload_val,
            s1 = up.nickname,
        })
        return
    end
    if not success or not data or not data.records then return end
    if leaderboard.loading_label then
        leaderboard.loading_label:destroy()
        leaderboard.loading_label = nil
    end
    leaderboard.data = data.records
    table.sort(leaderboard.data, function(a, b)
        return (tonumber(a.i1) or 0) > (tonumber(b.i1) or 0)
    end)
    local total = data.total or #data.records
    leaderboard.total_pages = math.max(1, math.ceil(total / 11))
    rebuild_leaderboard_ui()
end

local function open_leaderboard_win(digit_length)
    digit_length = digit_length or game.digit_length or 4
    if leaderboard.win_id then
        exwin.close(leaderboard.win_id)
        return
    end
    leaderboard.data = {}
    leaderboard.page = 1
    leaderboard.total_pages = 1
    leaderboard.digit_length = digit_length

    leaderboard.win_id = exwin.open({
        on_create = function()
            leaderboard.main_container = airui.container({
                parent = airui.screen,
                x = 0, y = 0, w = layout.width, h = layout.height,
                color = 0xFFFFFF,
            })

            leaderboard.loading_label = airui.label({
                parent = leaderboard.main_container,
                x = 0, y = math.floor(layout.height / 2) - scale_h(20),
                w = layout.width, h = scale_h(30),
                text = "数据同步中，请稍等...",
                font_size = scale_font(14),
                color = 0x1E293B,
                align = airui.TEXT_ALIGN_CENTER,
            })

            exapp.list_record({
                cls = get_leaderboard_cls(digit_length),
                sort = "i1", desc = true, size = 30,
            }, on_leaderboard_query_callback)
        end,
        on_destroy = function()
            for _, item in ipairs(leaderboard.items) do
                if item then item:destroy() end
            end
            leaderboard.items = {}
            if leaderboard.loading_label then
                leaderboard.loading_label:destroy()
                leaderboard.loading_label = nil
            end
            if leaderboard.main_container then
                leaderboard.main_container:destroy()
                leaderboard.main_container = nil
            end
            leaderboard.win_id = nil
            leaderboard.data = {}
        end,
    })
end

-- ============ 构建 UI ============
local function build_ui()
    local W, H = layout.width, layout.height
    local P = layout.page_padding
    local G = layout.gap
    local R = layout.corner_radius
    local left_w = layout.is_landscape and (layout.left_panel_w - P * 2) or (W - P * 2)

    -- 主容器
    main_container = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = W, h = H,
        color = 0xF5F7FA,
    })

    -- ===== 标题栏 =====
    local title_y = 0
    local title_h = layout.title_h
    local title_bg = airui.container({
        parent = main_container,
        x = 0, y = title_y,
        w = layout.is_landscape and layout.left_panel_w or W,
        h = title_h,
        color = 0xFFFFFF,
    })

    airui.label({
        parent = title_bg,
        x = P, y = vcenter_y(title_h, scale_font(24)),
        w = left_w, h = scale_font(24) + 4,
        text = "1A2B 猜数字",
        font_size = scale_font(24),
        color = 0x2E5BFF,
        align = airui.TEXT_ALIGN_LEFT,
    })

    -- 右侧按钮与图标布局参数（从右往左：icon → 退出 → 规则 → 排行）
    local icon_size = math.min(scale_w(36), title_h)
    local btn_gap = scale_w(4)
    local rule_btn_w = scale_w(56)
    local rule_btn_h = scale_h(28)
    local exit_btn_w = scale_w(52)
    local rank_btn_w = scale_w(56)

    local right_edge = left_w + P
    local icon_x = right_edge - icon_size
    local exit_btn_x = icon_x - btn_gap - exit_btn_w
    local rule_btn_x = exit_btn_x - btn_gap - rule_btn_w
    local rank_btn_x = rule_btn_x - btn_gap - rank_btn_w

    -- 排行按钮
    ui.rank_btn = airui.button({
        parent = title_bg,
        x = rank_btn_x,
        y = math.floor((title_h - rule_btn_h) / 2),
        w = rank_btn_w, h = rule_btn_h,
        text = "排行",
        font_size = scale_font(13),
        color = 0xFFFFFF,
        bg_color = 0xF59E0B,
        radius = math.floor(scale_h(14)),
        on_click = function() open_leaderboard_win(game.digit_length) end,
    })

    -- 规则按钮
    ui.rule_btn = airui.button({
        parent = title_bg,
        x = rule_btn_x,
        y = math.floor((title_h - rule_btn_h) / 2),
        w = rule_btn_w, h = rule_btn_h,
        text = "规则",
        font_size = scale_font(13),
        color = 0x2E5BFF,
        bg_color = 0xEEF3FF,
        radius = math.floor(scale_h(14)),
        on_click = function() show_rule_dialog() end,
    })

    -- 退出按钮
    ui.exit_btn = airui.button({
        parent = title_bg,
        x = exit_btn_x,
        y = math.floor((title_h - rule_btn_h) / 2),
        w = exit_btn_w, h = rule_btn_h,
        text = "退出",
        font_size = scale_font(13),
        color = 0xFFFFFF,
        bg_color = 0xEF4B4B,
        radius = math.floor(scale_h(14)),
        on_click = function() exwin.close(win_id) end,
    })

    -- 图标尺寸限制在标题栏高度内，防止超出容器触发滚动条
    airui.image({
        parent = title_bg,
        src = RES_ROOT .. "icon_game.png",
        x = icon_x,
        y = math.floor((title_h - icon_size) / 2),
        w = icon_size, h = icon_size,
    })

    -- ===== 设置区 =====
    local setting_y = title_y + title_h + G
    local setting_h = layout.setting_h
    local setting_bg = airui.container({
        parent = main_container,
        x = P, y = setting_y,
        w = left_w, h = setting_h,
        color = 0xFFFFFF,
        radius = R,
    })

    -- 位数控制参数（横屏更紧凑，防止与右侧按钮重叠）
    local ctrl_btn_w, ctrl_btn_h, ctrl_label_w, ctrl_digit_w
    local ctrl_label_x, ctrl_btn_x, ctrl_digit_x, ctrl_plus_x
    if layout.is_landscape then
        ctrl_btn_w = math.min(scale_w(32), scale_h(32))
        ctrl_btn_h = ctrl_btn_w
        ctrl_label_x = scale_w(8)
        ctrl_label_w = scale_w(36)
        ctrl_btn_x = scale_w(40)
        ctrl_digit_w = scale_w(48)
        ctrl_digit_x = ctrl_btn_x + ctrl_btn_w + scale_w(4)
        ctrl_plus_x = ctrl_digit_x + ctrl_digit_w + scale_w(8)
    else
        ctrl_btn_w = scale_w(40)
        ctrl_btn_h = scale_h(40)
        ctrl_label_x = scale_w(12)
        ctrl_label_w = scale_w(60)
        ctrl_btn_x = scale_w(72)
        ctrl_digit_w = scale_w(60)
        ctrl_digit_x = scale_w(118)
        ctrl_plus_x = scale_w(182)
    end

    local ctrl_y = math.floor((setting_h - ctrl_btn_h) / 2)
    local text_y = vcenter_y(ctrl_btn_h, scale_font(layout.is_landscape and 14 or 16))

    airui.label({
        parent = setting_bg,
        x = ctrl_label_x, y = ctrl_y + text_y,
        w = ctrl_label_w, h = scale_font(layout.is_landscape and 14 or 16) + 4,
        text = "位数",
        font_size = scale_font(layout.is_landscape and 14 or 16),
        color = 0x4A627A,
        align = airui.TEXT_ALIGN_LEFT,
    })

    ui.digit_minus_btn = airui.button({
        parent = setting_bg,
        x = ctrl_btn_x, y = ctrl_y,
        w = ctrl_btn_w, h = ctrl_btn_h,
        text = "-",
        font_size = scale_font(layout.is_landscape and 16 or 18),
        color = 0x2E5BFF,
        bg_color = 0xEEF3FF,
        radius = math.floor(ctrl_btn_w / 2),
        on_click = function() change_digit_length(-1) end,
    })

    ui.digit_label = airui.label({
        parent = setting_bg,
        x = ctrl_digit_x, y = ctrl_y + text_y,
        w = ctrl_digit_w, h = scale_font(layout.is_landscape and 14 or 16) + 4,
        text = tostring(game.digit_length) .. " 位",
        font_size = scale_font(layout.is_landscape and 14 or 16),
        color = 0x1E293B,
        align = airui.TEXT_ALIGN_CENTER,
    })

    ui.digit_plus_btn = airui.button({
        parent = setting_bg,
        x = ctrl_plus_x, y = ctrl_y,
        w = ctrl_btn_w, h = ctrl_btn_h,
        text = "+",
        font_size = scale_font(layout.is_landscape and 16 or 18),
        color = 0x2E5BFF,
        bg_color = 0xEEF3FF,
        radius = math.floor(ctrl_btn_w / 2),
        on_click = function() change_digit_length(1) end,
    })

    -- 动态计算按钮位置，防止小屏幕超出边界
    local btn_start_w = math.min(scale_w(90), math.floor(left_w * 0.26))
    local btn_reveal_w = math.min(scale_w(70), math.floor(left_w * 0.22))
    local btn_gap = scale_w(6)
    local ctrl_end = ctrl_plus_x + ctrl_btn_w + scale_w(12)
    local available = left_w - ctrl_end - scale_w(10)
    local start_x, reveal_x
    if btn_start_w + btn_reveal_w + btn_gap <= available then
        start_x = left_w - btn_start_w - btn_reveal_w - btn_gap - scale_w(8)
        reveal_x = left_w - btn_reveal_w - scale_w(8)
    else
        -- 空间紧张时按比例缩小按钮，确保不与左侧控件重叠
        local max_pair_w = left_w - ctrl_end - scale_w(16)
        if btn_start_w + btn_reveal_w + btn_gap > max_pair_w then
            local ratio = max_pair_w / (btn_start_w + btn_reveal_w + btn_gap)
            btn_start_w = math.floor(btn_start_w * ratio)
            btn_reveal_w = math.floor(btn_reveal_w * ratio)
        end
        reveal_x = left_w - btn_reveal_w - scale_w(8)
        start_x = reveal_x - btn_start_w - btn_gap
    end
    -- 最终兜底，确保不超出左侧面板
    reveal_x = math.min(reveal_x, left_w - btn_reveal_w - scale_w(4))
    start_x = math.min(start_x, reveal_x - btn_start_w - btn_gap)

    -- 开始按钮（横屏高度与位数控制按钮一致）
    local action_btn_h = layout.is_landscape and ctrl_btn_h or scale_h(40)
    ui.start_btn = airui.button({
        parent = setting_bg,
        x = start_x, y = ctrl_y,
        w = btn_start_w, h = action_btn_h,
        text = "开始",
        font_size = scale_font(14),
        color = 0xFFFFFF,
        bg_color = 0x2E5BFF,
        radius = math.floor((layout.is_landscape and ctrl_btn_w or scale_w(20))),
        on_click = function()
            reset_game()
            update_info_display()
            update_history_ui()
            update_input_display()
            show_message("新游戏开始！猜 " .. game.digit_length .. " 位数字", false)
        end,
    })

    -- 显示答案按钮
    ui.reveal_btn = airui.button({
        parent = setting_bg,
        x = reveal_x, y = ctrl_y,
        w = btn_reveal_w, h = action_btn_h,
        text = "答案",
        font_size = scale_font(14),
        color = 0x2E5BFF,
        bg_color = 0xF0F4FA,
        radius = math.floor((layout.is_landscape and ctrl_btn_w or scale_w(20))),
        on_click = reveal_answer,
    })

    -- ===== 信息区 =====
    local info_y = setting_y + setting_h + G
    local info_h = layout.info_h
    local info_bg = airui.container({
        parent = main_container,
        x = P, y = info_y,
        w = left_w, h = info_h,
        color = 0xFFFFFF,
        radius = R,
    })

    local info_text_y = vcenter_y(info_h, scale_font(14))
    ui.attempt_label = airui.label({
        parent = info_bg,
        x = scale_w(12), y = info_text_y,
        w = math.floor(left_w / 2) - scale_w(12),
        h = scale_font(14) + 4,
        text = "尝试: 0",
        font_size = scale_font(14),
        color = 0x1F3A6B,
        align = airui.TEXT_ALIGN_LEFT,
    })

    ui.answer_label = airui.label({
        parent = info_bg,
        x = math.floor(left_w / 2), y = info_text_y,
        w = math.floor(left_w / 2) - scale_w(12),
        h = scale_font(14) + 4,
        text = "答案: ????",
        font_size = scale_font(14),
        color = 0xEF4B4B,
        align = airui.TEXT_ALIGN_RIGHT,
    })

    -- ===== 输入显示区 =====
    local input_y = info_y + info_h + G
    local input_h = layout.input_display_h
    local input_bg = airui.container({
        parent = main_container,
        x = P, y = input_y,
        w = left_w, h = input_h,
        color = 0xFFFFFF,
        radius = R,
    })
    input_bg:set_border_color(0xDCE5F0, 1)

    -- 标签宽度缩进避免贴边，高度按字体居中避免触发滚动条
    local input_font_h = scale_font(22)
    ui.input_display_label = airui.label({
        parent = input_bg,
        x = scale_w(4),
        y = vcenter_y(input_h, input_font_h),
        w = left_w - scale_w(8),
        h = input_font_h + 4,
        text = string.rep("_", game.digit_length),
        font_size = input_font_h,
        color = 0x1E293B,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- ===== 消息提示 =====
    local msg_y = input_y + input_h + math.floor(G / 2)
    ui.msg_label = airui.label({
        parent = main_container,
        x = P, y = msg_y,
        w = left_w, h = scale_h(24),
        text = "",
        font_size = scale_font(12),
        color = 0x2E5BFF,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- ===== 数字键盘 =====
    local kb_y = msg_y + scale_h(24) + G
    local kb_h = layout.keyboard_h
    local kb_bg = airui.container({
        parent = main_container,
        x = P, y = kb_y,
        w = left_w, h = kb_h,
        color = 0xFFFFFF,
        radius = R,
    })

    -- 按钮宽度留出余量，避免最右列贴边触发水平滚动条
    local btn_w = math.floor((left_w - G * 2 - scale_w(8)) / 3)
    local btn_h = math.floor((kb_h - G * 3) / 4)
    local btn_font = scale_font(20)

    -- 竖屏与横屏均将"提交"集成到键盘第4行，节省独立按钮空间
    local keys = {
        {"1", "2", "3"},
        {"4", "5", "6"},
        {"7", "8", "9"},
        {"←", "0", "提交"},
    }

    for row = 1, 4 do
        for col = 1, 3 do
            local key = keys[row][col]
            local x = (col - 1) * (btn_w + G)
            local y = (row - 1) * (btn_h + G)
            local on_click_fn
            if key == "←" then
                on_click_fn = backspace
            elseif key == "C" then
                on_click_fn = clear_input
            elseif key == "提交" then
                on_click_fn = submit_guess
            else
                on_click_fn = function() append_digit(key) end
            end

            airui.button({
                parent = kb_bg,
                x = x, y = y,
                w = btn_w, h = btn_h,
                text = key,
                font_size = btn_font,
                color = key == "提交" and 0xFFFFFF or 0x1E293B,
                bg_color = key == "提交" and 0x2E5BFF or 0xF0F4F9,
                radius = math.floor(math.min(btn_w, btn_h) * 0.2),
                on_click = on_click_fn,
            })
        end
    end

    -- ===== 历史记录区 =====
    local hist_y, hist_h, hist_x, hist_w
    if layout.is_landscape then
        hist_x = layout.right_panel_x + P
        hist_y = P
        hist_w = layout.right_panel_w - P * 2
        hist_h = H - P * 2
    else
        hist_x = P
        hist_y = kb_y + kb_h + G
        hist_w = W - P * 2
        hist_h = H - hist_y - P
        if hist_h < scale_h(80) then hist_h = scale_h(80) end
    end

    ui.history_container = airui.container({
        parent = main_container,
        x = hist_x, y = hist_y,
        w = hist_w, h = hist_h,
        color = 0xFFFFFF,
        radius = R,
    })
    ui.history_container_h = hist_h

    ui.history_title = airui.label({
        parent = ui.history_container,
        x = scale_w(12), y = 0,
        w = hist_w - scale_w(24),
        h = layout.history_title_h,
        text = "猜测历史",
        font_size = scale_font(14),
        color = 0x4A627A,
        align = airui.TEXT_ALIGN_LEFT,
    })

    ui.empty_history_label = airui.label({
        parent = ui.history_container,
        x = scale_w(4), y = layout.history_title_h + scale_h(20),
        w = hist_w - scale_w(8),
        h = scale_h(40),
        text = "暂无记录，开始游戏吧",
        font_size = scale_font(13),
        color = 0x8AA9CC,
        align = airui.TEXT_ALIGN_CENTER,
    })
end

-- ============ 窗口生命周期 ============
local function on_create()
    refresh_runtime_display()
    rebuild_layout()
    build_ui()
    update_input_display()
    update_info_display()
end

local function on_destroy()
    if ui.msg_timer then
        sys.timerStop(ui.msg_timer)
        ui.msg_timer = nil
    end
    if ui.history_items then
        for _, item in ipairs(ui.history_items) do
            if item.container then item.container:destroy() end
        end
        ui.history_items = nil
    end
    if leaderboard.win_id then
        exwin.close(leaderboard.win_id)
        leaderboard.win_id = nil
    end
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    ui = {}
    game = {
        secret = "",
        digit_length = 4,
        attempts = 0,
        history = {},
        active = false,
        current_input = "",
    }
end

local function on_get_focus()
end

local function on_lose_focus()
end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_1A2B_WIN", open_handler)
sys.subscribe("DB_RESULT", on_db_result)

