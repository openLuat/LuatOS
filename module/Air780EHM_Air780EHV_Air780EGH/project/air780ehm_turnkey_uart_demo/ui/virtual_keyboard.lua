--[[
@module  virtual_keyboard
@summary 虚拟键盘组件（简化版）
@version 1.0
@date    2026.03.17
]]

local keyboard = {}

-- 键盘布局（优化为9列，更合理的大小）
local keyboard_layout = {
    -- 第一行
    { "1", "2", "3", "4", "5", "6", "7", "8", "9" },
    -- 第二行
    { "Q", "W", "E", "R", "T", "Y", "U", "I", "O" },
    -- 第三行
    { "A", "S", "D", "F", "G", "H", "J", "K", "L" },
    -- 第四行
    { "Z", "X", "C", "V", "B", "N", "M", ".", "DEL" },
    -- 第五行
    { "0", "P", " " }
}

-- 键盘容器
local keyboard_container = nil
local keyboard_parent = nil
local keyboard_x, keyboard_y, keyboard_w, keyboard_h = 0, 0, 0, 0
local target_textarea = nil
local current_text = ""
local on_complete_callback = nil
local on_change_callback = nil

-- 创建按键
local function create_key(parent, text, x, y, w, h, callback, is_special)
    local btn_color = 0x0f3460
    local text_color = 0x00d4ff
    local font_size = 10  -- 调整字体大小以适应小按键

    -- 特殊按键样式
    if is_special then
        if text == "DEL" then
            btn_color = 0xe94560
        elseif text == " " then
            btn_color = 0x666666
        elseif text == "P" then
            -- P键作为确认键
            btn_color = 0x00ff88
        end
        text_color = 0xffffff
    end

    log.info("virtual_keyboard", "【按键创建】创建按键 - 文本:" .. text .. " 位置:(" .. x .. "," .. y .. ") 大小:" .. w .. "x" .. h)

    -- 将回调函数保存到全局变量，避免闭包问题
    local key_key = "key_" .. text
    _G[key_key] = callback

    local btn = airui.button({
        parent = parent,
        x = x,
        y = y,
        w = w,
        h = h,
        text = text == " " and "␣" or text, -- 空格显示为特殊符号
        font_size = font_size,
        stype = {
            bg_color = btn_color,
            text_color = text_color
        },
        radius = 4,
        on_click = function()
            log.info("virtual_keyboard", "【按键点击】回调被调用 - 文本:" .. text)
            if _G[key_key] then
                _G[key_key]()
            else
                log.error("virtual_keyboard", "【按键点击】错误 - 回调函数不存在")
            end
        end
    })

    if not btn then
        log.error("virtual_keyboard", "【按键创建】错误 - 按钮创建失败")
    end

    return btn
end

-- 处理按键点击
local function handle_key_click(key_text)
    log.info("virtual_keyboard", "【按键点击】按键:" .. key_text .. " 当前文本:" .. current_text)

    if key_text == "DEL" then
        -- 删除最后一个字符
        current_text = current_text:sub(1, -2)
        log.info("virtual_keyboard", "【按键点击】删除字符，当前文本:" .. current_text)
    elseif key_text == "P" then
        -- 确认输入（P键作为确认键）
        log.info("virtual_keyboard", "【按键点击】确认输入，隐藏键盘")
        if on_complete_callback then
            on_complete_callback(current_text)
        end
        keyboard.hide()
    elseif key_text == " " then
        -- 空格
        current_text = current_text .. " "
    else
        -- 普通字符
        current_text = current_text .. key_text
    end

    -- 更新目标输入框
    if target_textarea then
        target_textarea:set_text(current_text)
    end

    -- 触发变更回调
    if on_change_callback then
        on_change_callback(current_text)
    end
end

-- 初始化键盘参数（不创建UI）
function keyboard.init(parent, x, y, w, h)
    log.info("virtual_keyboard", "【键盘初始化】初始化虚拟键盘参数 - 位置:(" .. x .. "," .. y .. ") 大小:" .. w .. "x" .. h)
    keyboard_parent = parent
    keyboard_x, keyboard_y, keyboard_w, keyboard_h = x, y, w, h
end

-- 创建键盘界面
function keyboard.create(parent, x, y, w, h)
    log.info("virtual_keyboard", "【键盘创建】开始创建虚拟键盘 - 位置:(" .. x .. "," .. y .. ") 大小:" .. w .. "x" .. h)
    keyboard_parent = parent
    keyboard_x, keyboard_y, keyboard_w, keyboard_h = x, y, w, h
    local container = keyboard.build_keyboard()
    log.info("virtual_keyboard", "【键盘创建】虚拟键盘创建完成")
    return container
end

-- 构建键盘（内部使用）
function keyboard.build_keyboard()
    log.info("virtual_keyboard", "【键盘构建】开始构建键盘")

    if keyboard_container then
        log.info("virtual_keyboard", "【键盘构建】销毁旧键盘容器")
        keyboard_container:destroy()
    end

    log.info("virtual_keyboard", "【键盘构建】创建新键盘容器")
    log.info("virtual_keyboard", "【键盘构建】容器参数 - parent:" .. tostring(keyboard_parent) ..
              " x:" .. keyboard_x .. " y:" .. keyboard_y .. " w:" .. keyboard_w .. " h:" .. keyboard_h)

    keyboard_container = airui.container({
        parent = keyboard_parent,
        x = keyboard_x,
        y = keyboard_y,
        w = keyboard_w,
        h = keyboard_h,
        color = 0x2a3a4e,  -- 稍微亮一点的颜色，便于调试
        radius = 8
    })

    if not keyboard_container then
        log.error("virtual_keyboard", "【键盘构建】错误 - 容器创建失败")
        return nil
    else
        log.info("virtual_keyboard", "【键盘构建】容器创建成功")
    end

    local margin = 4
    local key_w = 48  -- 固定按键宽度
    local key_h = 14  -- 固定按键高度

    log.info("virtual_keyboard", "【键盘构建】按键大小 - 宽:" .. key_w .. " 高:" .. key_h)
    log.info("virtual_keyboard", "【键盘构建】容器大小 - 宽:" .. keyboard_w .. " 高:" .. keyboard_h)
    log.info("virtual_keyboard", "【键盘构建】间距 - margin:" .. margin)

    -- 创建按键
    log.info("virtual_keyboard", "【键盘构建】开始创建按键...")
    local key_count = 0
    local start_x = (keyboard_w - (9 * key_w + 8 * margin)) / 2  -- 居中对齐
    for row_idx, row in ipairs(keyboard_layout) do
        -- 计算每行的起始x坐标（居中对齐）
        local row_width = #row * key_w + (#row - 1) * margin
        local row_start_x = (keyboard_w - row_width) / 2

        for col_idx, key_text in ipairs(row) do
            local key_x = row_start_x + (col_idx - 1) * (key_w + margin)
            local key_y = margin + (row_idx - 1) * (key_h + margin)

            log.info("virtual_keyboard", "【键盘构建】按键[" .. key_count .. "] - 文本:" .. key_text ..
                     " 位置:(" .. key_x .. "," .. key_y .. ") 大小:" .. key_w .. "x" .. key_h)

            local is_special = (key_text == "DEL" or key_text == " " or key_text == "P")
            create_key(keyboard_container, key_text, key_x, key_y, key_w, key_h,
                function() handle_key_click(key_text) end, is_special)

            key_count = key_count + 1
        end
    end
    log.info("virtual_keyboard", "【键盘构建】按键创建完成，共创建:" .. key_count .. "个按键")

    return keyboard_container
end

-- 显示键盘
function keyboard.show(textarea, initial_text, on_complete, on_change)
    log.info("virtual_keyboard", "【键盘显示】显示虚拟键盘")
    log.info("virtual_keyboard", "【键盘显示】初始文本:" .. (initial_text or ""))

    target_textarea = textarea
    current_text = initial_text or ""
    on_complete_callback = on_complete
    on_change_callback = on_change

    if target_textarea then
        target_textarea:set_text(current_text)
    end

    -- 重新构建键盘
    log.info("virtual_keyboard", "【键盘显示】开始构建键盘UI...")
    local result = keyboard.build_keyboard()

    if result then
        log.info("virtual_keyboard", "【键盘显示】键盘构建成功")
    else
        log.error("virtual_keyboard", "【键盘显示】键盘构建失败")
    end

    log.info("virtual_keyboard", "键盘已显示")
end

-- 隐藏键盘
function keyboard.hide()
    if keyboard_container then
        keyboard_container:destroy()
        keyboard_container = nil
    end
    log.info("virtual_keyboard", "键盘已隐藏")
end

-- 获取当前文本
function keyboard.get_text()
    return current_text
end

-- 设置当前文本
function keyboard.set_text(text)
    current_text = text or ""
    if target_textarea then
        target_textarea:set_text(current_text)
    end
end

-- 销毁键盘
function keyboard.destroy()
    if keyboard_container then
        keyboard_container:destroy()
        keyboard_container = nil
    end
    keyboard_parent = nil
    target_textarea = nil
    current_text = ""
    on_complete_callback = nil
    on_change_callback = nil
    log.info("virtual_keyboard", "键盘已销毁")
end

log.info("virtual_keyboard", "【模块加载】虚拟键盘模块加载完成")

return keyboard
