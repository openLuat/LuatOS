-- 在模块顶部添加 submit_callback 声明
local input_method = {}
local submit_callback = nil  -- 添加模块级变量

-- 输入法状态
local input_state = "LOWERCASE"
local input_text = ""
local display_text = ""  -- 单独存储显示文本
local is_cipher = false
local last_cipher_time = 0
local prev_fun = nil
local is_active = false  -- 输入法激活状态
local text_dirty = true  -- 文本需要刷新的标志
local last_text_length = 0  -- 记录上次文本长度，用于检测变化
--local submit_callback = nil
-- 字体指针（确保使用正确的字体指针）
local font_ptr = nil



-- 文本显示位置
local TEXT_X = 20
local TEXT_Y = 27
local TEXT_X2 = 228  -- 文本区域右下角
local TEXT_Y2 = 52  -- 文本区域右下角


-- 按键映射表
local key_mappings = {
    LOWERCASE = {
        { char = "1", x1 = 4, y1 = 77, x2 = 64, y2 = 124 },
        { char = "2", x1 = 66, y1 = 77, x2 = 126, y2 = 124 },
        { char = "3", x1 = 128, y1 = 77, x2 = 188, y2 = 124 },
        { char = "4", x1 = 190, y1 = 77, x2 = 250, y2 = 124 },
        { char = "5", x1 = 252, y1 = 77, x2 = 312, y2 = 124 },
        { char = "6", x1 = 4, y1 = 127, x2 = 64, y2 = 174 },
        { char = "7", x1 = 66, y1 = 127, x2 = 126, y2 = 174 },
        { char = "8", x1 = 128, y1 = 127, x2 = 188, y2 = 174 },
        { char = "9", x1 = 190, y1 = 127, x2 = 250, y2 = 174 },
        { char = "0", x1 = 252, y1 = 127, x2 = 312, y2 = 174 },
        { char = "a", x1 = 4, y1 = 177, x2 = 64, y2 = 224 },
        { char = "b", x1 = 66, y1 = 177, x2 = 126, y2 = 224 },
        { char = "c", x1 = 128, y1 = 177, x2 = 188, y2 = 224 },
        { char = "d", x1 = 190, y1 = 177, x2 = 250, y2 = 224 },
        { char = "e", x1 = 252, y1 = 177, x2 = 312, y2 = 224 },
        { char = "f", x1 = 4, y1 = 227, x2 = 64, y2 = 274 },
        { char = "g", x1 = 66, y1 = 227, x2 = 126, y2 = 274 },
        { char = "h", x1 = 128, y1 = 227, x2 = 188, y2 = 274 },
        { char = "i", x1 = 190, y1 = 227, x2 = 250, y2 = 274 },
        { char = "j", x1 = 252, y1 = 227, x2 = 312, y2 = 274 },
        { char = "k", x1 = 4, y1 = 277, x2 = 64, y2 = 324 },
        { char = "l", x1 = 66, y1 = 277, x2 = 126, y2 = 324 },
        { char = "m", x1 = 128, y1 = 277, x2 = 188, y2 = 324 },
        { char = "n", x1 = 190, y1 = 277, x2 = 250, y2 = 324 },
        { char = "o", x1 = 252, y1 = 277, x2 = 312, y2 = 324 },
        { char = "p", x1 = 4, y1 = 327, x2 = 64, y2 = 374 },
        { char = "q", x1 = 66, y1 = 327, x2 = 126, y2 = 374 },
        { char = "r", x1 = 128, y1 = 327, x2 = 188, y2 = 374 },
        { char = "s", x1 = 190, y1 = 327, x2 = 250, y2 = 374 },
        { char = "t", x1 = 252, y1 = 327, x2 = 312, y2 = 374 },
        { char = "u", x1 = 4, y1 = 377, x2 = 64, y2 = 424 },
        { char = "v", x1 = 66, y1 = 377, x2 = 126, y2 = 424 },
        { char = "w", x1 = 128, y1 = 377, x2 = 188, y2 = 424 },
        { char = "x", x1 = 190, y1 = 377, x2 = 250, y2 = 424 },
        { char = "y", x1 = 252, y1 = 377, x2 = 312, y2 = 424 },
        { char = "z", x1 = 4, y1 = 427, x2 = 64, y2 = 474 },
    },
    UPPERCASE = {
        { char = "1", x1 = 4, y1 = 77, x2 = 64, y2 = 124 },
        { char = "2", x1 = 66, y1 = 77, x2 = 126, y2 = 124 },
        { char = "3", x1 = 128, y1 = 77, x2 = 188, y2 = 124 },
        { char = "4", x1 = 190, y1 = 77, x2 = 250, y2 = 124 },
        { char = "5", x1 = 252, y1 = 77, x2 = 312, y2 = 124 },
        { char = "6", x1 = 4, y1 = 127, x2 = 64, y2 = 174 },
        { char = "7", x1 = 66, y1 = 127, x2 = 126, y2 = 174 },
        { char = "8", x1 = 128, y1 = 127, x2 = 188, y2 = 174 },
        { char = "9", x1 = 190, y1 = 127, x2 = 250, y2 = 174 },
        { char = "0", x1 = 252, y1 = 127, x2 = 312, y2 = 174 },
        { char = "A", x1 = 4, y1 = 177, x2 = 64, y2 = 224 },
        { char = "B", x1 = 66, y1 = 177, x2 = 126, y2 = 224 },
        { char = "C", x1 = 128, y1 = 177, x2 = 188, y2 = 224 },
        { char = "D", x1 = 190, y1 = 177, x2 = 250, y2 = 224 },
        { char = "E", x1 = 252, y1 = 177, x2 = 312, y2 = 224 },
        { char = "F", x1 = 4, y1 = 227, x2 = 64, y2 = 274 },
        { char = "G", x1 = 66, y1 = 227, x2 = 126, y2 = 274 },
        { char = "H", x1 = 128, y1 = 227, x2 = 188, y2 = 274 },
        { char = "I", x1 = 190, y1 = 227, x2 = 250, y2 = 274 },
        { char = "J", x1 = 252, y1 = 227, x2 = 312, y2 = 274 },
        { char = "K", x1 = 4, y1 = 277, x2 = 64, y2 = 324 },
        { char = "L", x1 = 66, y1 = 277, x2 = 126, y2 = 324 },
        { char = "M", x1 = 128, y1 = 277, x2 = 188, y2 = 324 },
        { char = "N", x1 = 190, y1 = 277, x2 = 250, y2 = 324 },
        { char = "O", x1 = 252, y1 = 277, x2 = 312, y2 = 324 },
        { char = "P", x1 = 4, y1 = 327, x2 = 64, y2 = 374 },
        { char = "Q", x1 = 66, y1 = 327, x2 = 126, y2 = 374 },
        { char = "R", x1 = 128, y1 = 327, x2 = 188, y2 = 374 },
        { char = "S", x1 = 190, y1 = 327, x2 = 250, y2 = 374 },
        { char = "T", x1 = 252, y1 = 327, x2 = 312, y2 = 374 },
        { char = "U", x1 = 4, y1 = 377, x2 = 64, y2 = 424 },
        { char = "V", x1 = 66, y1 = 377, x2 = 126, y2 = 424 },
        { char = "W", x1 = 128, y1 = 377, x2 = 188, y2 = 424 },
        { char = "X", x1 = 190, y1 = 377, x2 = 250, y2 = 424 },
        { char = "Y", x1 = 252, y1 = 377, x2 = 312, y2 = 424 },
        { char = "Z", x1 = 4, y1 = 427, x2 = 64, y2 = 474 },
    },
    SYMBOL = {
        { char = "!", x1 = 4, y1 = 77, x2 = 64, y2 = 124 },
        { char = "@", x1 = 66, y1 = 77, x2 = 126, y2 = 124 },
        { char = "#", x1 = 128, y1 = 77, x2 = 188, y2 = 124 },
        { char = "$", x1 = 190, y1 = 77, x2 = 250, y2 = 124 },
        { char = "%", x1 = 252, y1 = 77, x2 = 312, y2 = 124 },
        { char = "^", x1 = 4, y1 = 127, x2 = 64, y2 = 174 },
        { char = "&", x1 = 66, y1 = 127, x2 = 126, y2 = 174 },
        { char = "*", x1 = 128, y1 = 127, x2 = 188, y2 = 174 },
        { char = "(", x1 = 190, y1 = 127, x2 = 250, y2 = 174 },
        { char = ")", x1 = 252, y1 = 127, x2 = 312, y2 = 174 },
        { char = "-", x1 = 4, y1 = 177, x2 = 64, y2 = 224 },
        { char = "_", x1 = 66, y1 = 177, x2 = 126, y2 = 224 },
        { char = "+", x1 = 128, y1 = 177, x2 = 188, y2 = 224 },
        { char = "=", x1 = 190, y1 = 177, x2 = 250, y2 = 224 },
        { char = "{", x1 = 252, y1 = 177, x2 = 312, y2 = 224 },
        { char = "}", x1 = 4, y1 = 227, x2 = 64, y2 = 274 },
        { char = "[", x1 = 66, y1 = 227, x2 = 126, y2 = 274 },
        { char = "]", x1 = 128, y1 = 227, x2 = 188, y2 = 274 },
        { char = "|", x1 = 190, y1 = 227, x2 = 250, y2 = 274 },
        { char = string.char(92), x1 = 252, y1 = 227, x2 = 312, y2 = 274 }, --\
        { char = ":", x1 = 4, y1 = 277, x2 = 64, y2 = 324 },
        { char = ";", x1 = 66, y1 = 277, x2 = 126, y2 = 324 },
        { char = "\"", x1 = 128, y1 = 277, x2 = 188, y2 = 324 },
        { char = "'", x1 = 190, y1 = 277, x2 = 250, y2 = 324 },
        { char = "<", x1 = 252, y1 = 277, x2 = 312, y2 = 324 },
        { char = ">", x1 = 4, y1 = 327, x2 = 64, y2 = 374 },
        { char = "", x1 = 66, y1 = 327, x2 = 126, y2 = 374 },
        { char = ".", x1 = 128, y1 = 327, x2 = 188, y2 = 374 },
        { char = "?", x1 = 190, y1 = 327, x2 = 250, y2 = 374 },
        { char = "/", x1 = 252, y1 = 327, x2 = 312, y2 = 374 },
        { char = "~", x1 = 4, y1 = 377, x2 = 64, y2 = 424 },
        { char = "`", x1 = 66, y1 = 377, x2 = 126, y2 = 424 },
        { char = "¥", x1 = 128, y1 = 377, x2 = 188, y2 = 424 },
        { char = "€", x1 = 190, y1 = 377, x2 = 250, y2 = 424 },
        { char = "£", x1 = 252, y1 = 377, x2 = 312, y2 = 424 },
        { char = "§", x1 = 4, y1 = 427, x2 = 64, y2 = 474 },
    }
}

-- 初始化字体指针
local function init_font()
    -- 尝试获取可用的中文字体
    if lcd.font_opposansm16_chinese then
        font_ptr = lcd.font_opposansm16_chinese
    elseif lcd.font_opposansm16 then
        font_ptr = lcd.font_opposansm16
    elseif lcd.font_opposanss16 then
        font_ptr = lcd.font_opposanss16
    else
        -- 如果没有中文字体，使用默认字体
        font_ptr = lcd.font_default
    end
end

-- 刷新输入框文本 - 直接显示文字
local function refresh_input_text()
    
    if not text_dirty then return end
  
    
    -- 只显示最后20位内容
    display_text = string.sub(input_text, -25)

    -- 处理密文显示
    if is_cipher and input_text ~= "" then
        if mcu.ticks() - last_cipher_time < 1000 then
            -- 显示明文1秒
        else
            display_text = string.rep("*", #display_text)
        end
    end

    -- 添加省略号如果文本过长
    if #display_text > 20 then
        display_text = "..." .. string.sub(display_text, -12)
    end
    
    -- 设置文本框文本颜色
    lcd.setColor(0xFFFF,0x0000)  --白底黑字
    
    -- 绘制文本（使用字体指针）

    lcd.setFont(font_ptr)
    lcd.fill(19,14,228,52,0xFFFFF)
    lcd.drawStr(TEXT_X, TEXT_Y, display_text)

    -- 更新上次文本长度
    last_text_length = #input_text
    
    text_dirty = false
    
    -- 刷新屏幕
    
    lcd.flush()

end

-- 检查文本长度是否变化
local function check_text_length()
    if #input_text ~= last_text_length then
        text_dirty = true
    end
    return text_dirty
end

-- 初始化输入法
function input_method.init(is_cipher_input, previous_fun, callback)
    submit_callback = callback  -- 保存到模块级变量
    -- 初始化字体
    -- init_font()
    
    input_state = "LOWERCASE"
    input_text = ""
    display_text = ""
    --_cipher = is_cipher_input
    last_cipher_time = 0
    prev_fun = previous_fun
    is_active = true
    text_dirty = true
    last_text_length = 0
    
    
    -- 清除整个屏幕
    lcd.clear()
    lcd.flush()
    
    -- 显示键盘图片（覆盖整个屏幕）
    if input_state == "LOWERCASE" then
        lcd.showImage(0, 0, "/luadb/Lkeyboard.jpg")
    elseif input_state == "UPPERCASE" then
        lcd.showImage(0, 0, "/luadb/Ukeyboard.jpg")
    else
        lcd.showImage(0, 0, "/luadb/Skeyboard.jpg")
    end
    lcd.flush()
    
    -- 刷新输入文本
    refresh_input_text()
    return true
end

-- 切换键盘布局
local function switch_keyboard_layout()
    -- 清除整个屏幕
    lcd.clear()
    lcd.flush()
    
    -- 显示对应键盘图片
    if input_state == "LOWERCASE" then
        lcd.showImage(0, 0, "/luadb/Lkeyboard.jpg")
    elseif input_state == "UPPERCASE" then
        lcd.showImage(0, 0, "/luadb/Ukeyboard.jpg")
    else
        lcd.showImage(0, 0, "/luadb/Skeyboard.jpg")
    end
    lcd.flush()
    
    -- 刷新输入文本
    text_dirty = true
    refresh_input_text()
end

-- 处理触摸事件
function input_method.process_touch(x, y)
    if not is_active then return end
    
    -- 提交按钮
    if x >= 244 and x <= 304 and y >= 8 and y <= 58 then
        is_active = false
        if type(submit_callback) == "function" then  -- 安全检查
            submit_callback(input_text)  -- 调用回调
        else
            log.warn("submit_callback is not a function")
        end
        return
    end
        

    -- 删除按钮
    if x >= 252 and x <= 312 and y >= 427 and y <= 474 then
        if #input_text > 0 then
            input_text = string.sub(input_text, 1, -2)
            last_cipher_time = mcu.ticks()
            text_dirty = true
            refresh_input_text()  -- 立即刷新文本
            
        end
    -- 切换大小写
    elseif x >= 66 and x <= 126 and y >= 427 and y <= 474 then
        if input_state == "LOWERCASE" then
            input_state = "UPPERCASE"
        elseif input_state == "UPPERCASE" then
            input_state = "LOWERCASE"
        elseif input_state == "SYMBOL" then
            input_state = "UPPERCASE"
        end
        switch_keyboard_layout()  -- 切换键盘布局并刷新文本
    -- 切换符号
    elseif x >= 128 and x <= 188 and y >= 427 and y <= 474 then
        if input_state == "LOWERCASE" or input_state == "UPPERCASE" then
            input_state = "SYMBOL"
        elseif input_state == "SYMBOL" then
            input_state = "UPPERCASE"
        end
        switch_keyboard_layout()  -- 切换键盘布局并刷新文本
    -- 空格键
    elseif x >= 190 and x <= 250 and y >= 427 and y <= 474 then
        input_text = input_text .. " "
        last_cipher_time = mcu.ticks()
        check_text_length()  -- 检查文本长度是否变化
        refresh_input_text()  -- 立即刷新文本
    else
        -- 查找按键映射
        for _, key in ipairs(key_mappings[input_state]) do
            if x >= key.x1 and x <= key.x2 and y >= key.y1 and y <= key.y2 then
                input_text = input_text .. key.char
                last_cipher_time = mcu.ticks()
                check_text_length()  -- 检查文本长度是否变化
                refresh_input_text()  -- 立即刷新文本
                break
            end
        end
    end
end

-- 添加定期刷新函数，确保文本显示正常
function input_method.periodic_refresh()
    if is_active then
        -- 检查文本长度是否变化
        if #input_text ~= last_text_length then
            text_dirty = true
        end
        
        -- 检查密文状态
        if is_cipher and input_text ~= "" then
            if mcu.ticks() - last_cipher_time >= 1000 then
                text_dirty = true
            end
        end
        
        -- 刷新文本
        if text_dirty then
            refresh_input_text()
        end
    end
end

-- 检查输入法是否激活
function input_method.is_active()
    return is_active
end

return input_method