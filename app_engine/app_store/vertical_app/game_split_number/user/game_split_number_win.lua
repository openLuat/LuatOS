--[[
@module  game_split_number_win
@summary 拆数游戏窗口模块
@version 1.0
@date    2026.04.07
@author  杨乔杉
]]

local main_container
local target_number = 0   -- 目标数字
local current_split = {}   -- 当前拆分结果
local score = 0            -- 当前分数
local level = 1            -- 当前关卡
local game_mode = "sum"   -- 游戏模式：sum（求和）或 product（求积）
local target_label
local split_label
local score_label
local level_label
local game_mode_label

-- 检查数字是否可以通过1-9的数字组合相乘得到（递归版本，最多3个数字）
local function can_be_product(num, depth)
    depth = depth or 1
    if depth > 3 then return false end

    -- 数字1-9可以直接使用
    if num >= 1 and num <= 9 then return true end

    -- 尝试用2-9分解
    for i = 2, 9 do
        if num % i == 0 then
            local quotient = num / i
            if can_be_product(quotient, depth + 1) then
                return true
            end
        end
    end

    return false
end

-- 生成目标数字（根据关卡难度和游戏模式）
local function generate_target_number()
    if game_mode == "sum" then
        -- 求和模式目标数字范围
        if level <= 5 then
            return math.random(10, 50)
        elseif level <= 10 then
            return math.random(50, 100)
        else
            return math.random(100, 200)
        end
    else
        -- 求积模式目标数字范围（更小，因为乘积增长快）
        local max_attempts = 100  -- 最大尝试次数
        local attempts = 0
        
        while attempts < max_attempts do
            local target
            if level <= 5 then
                target = math.random(6, 36)  -- 1-9的乘积范围
            elseif level <= 10 then
                target = math.random(24, 120)
            else
                target = math.random(60, 360)
            end
            
            -- 检查是否可以通过1-9的数字组合相乘得到
            if can_be_product(target) then
                return target
            end
            
            attempts = attempts + 1
        end
        
        -- 如果无法生成合适的数字，返回一个默认值
        return 24
    end
end

-- 检查拆分是否正确
local function check_split()
    if game_mode == "sum" then
        -- 求和模式
        local sum = 0
        for _, num in ipairs(current_split) do
            sum = sum + num
        end
        return sum == target_number
    else
        -- 求积模式
        local product = 1
        for _, num in ipairs(current_split) do
            product = product * num
        end
        return product == target_number
    end
end

-- 更新UI
local function update_ui()
    -- 更新目标数字
    target_label:set_text("目标数字: " .. target_number)
    
    -- 更新当前拆分
    local split_text = "拆分结果: "
    local operator = game_mode == "sum" and " + " or " × "
    for i, num in ipairs(current_split) do
        split_text = split_text .. num
        if i < #current_split then
            split_text = split_text .. operator
        end
    end
    split_label:set_text(split_text)
    
    -- 更新分数和关卡
    score_label:set_text("分数: " .. score)
    level_label:set_text("关卡: " .. level)
    
    -- 更新游戏模式
    local mode_text = game_mode == "sum" and "求和模式" or "求积模式"
    game_mode_label:set_text("模式: " .. mode_text)
end

-- 开始新游戏
local function start_new_game()
    -- 重置游戏状态
    level = 1
    score = 0
    current_split = {}
    
    -- 生成新的目标数字
    target_number = generate_target_number()
    
    -- 更新UI
    update_ui()
end

-- 处理数字按钮点击
local function handle_number_click(num)
    -- 添加数字到拆分结果
    table.insert(current_split, num)
    
    -- 检查拆分是否完成
    if check_split() then
        -- 拆分正确，加分并进入下一关
        local base_points = 100 * level
        -- 数字越少，积分越高
        local num_count = #current_split
        local bonus = 4 - num_count  -- 使用1个数字得3倍，2个得2倍，3个得1倍
        if bonus < 1 then bonus = 1 end  -- 最低1倍
        local points = base_points * bonus

        score = score + points
        level = level + 1
        current_split = {}
        target_number = generate_target_number()

        -- 先更新UI显示新关卡
        update_ui()

        -- 显示成功消息
        show_message("拆分成功！", "得分: " .. points .. " (使用" .. num_count .. "个数字)\n进入下一关")
        return
    end

    update_ui()
end

-- 处理清除按钮点击
local function handle_clear_click()
    -- 清空当前拆分
    current_split = {}
    
    -- 更新UI
    update_ui()
end

-- 切换游戏模式
local function toggle_game_mode()
    -- 切换游戏模式
    game_mode = game_mode == "sum" and "product" or "sum"
    
    -- 重新开始游戏
    start_new_game()
end

-- 显示消息框的函数
local function show_message(title, text, buttons, on_action)
    airui.msgbox({
        title = title,
        text = text,
        buttons = buttons or { "确定" },
        on_action = function(self, label)
            self:hide()
            self:destroy()
            if on_action then
                on_action(label)
            end
        end
    }):show()
end

-- 创建UI
local function create_ui()
    -- 提取常量
    local BACKGROUND_COLOR = 0xF5F5F5
    local TITLE_BAR_COLOR = 0x2195F6
    local WHITE_COLOR = 0xffffff
    local PRIMARY_COLOR = 0x2195F6
    local SECONDARY_COLOR = 0x2196F3
    local SUCCESS_COLOR = 0x4CAF50
    local WARNING_COLOR = 0xFF5722
    local GRAY_COLOR = 0x9E9E9E
    local TEXT_PRIMARY = 0x333333
    local TEXT_SECONDARY = 0x666666
    local TEXT_WHITE = 0xfefefe
    local NUMBER_BUTTON_BG = 0xE3F2FD
    local NUMBER_BUTTON_TEXT = 0x2195F6
    
    local BUTTON_SIZE = 120
    local GAP = 10
    local CONTAINER_WIDTH = 440
    local BOTTOM_BUTTON_WIDTH = 130
    local BOTTOM_BUTTON_HEIGHT = 45
    local RETURN_BUTTON_WIDTH = 440
    
    -- 创建按钮的函数
    local function create_button(parent, x, y, width, height, text, bg_color, text_color, on_click)
        return airui.button({
            parent = parent,
            x = x, y = y,
            w = width, h = height,
            text = text,
            style = {
                bg_color = bg_color,
                text_color = text_color,
                border_width = 0,
                radius = 5,
            },
            on_click = on_click
        })
    end

    main_container = airui.container({ x = 0, y = 0, w = 480, h = 800, color = BACKGROUND_COLOR, parent = airui.screen })

    -- 顶部标题栏
    local title_bar = airui.container({ parent = main_container, x = 0, y = 0, w = 480, h = 70, color = TITLE_BAR_COLOR })
    airui.label({ parent = title_bar, x = 20, y = 15, w = 150, h = 40, text = "拆数游戏", font_size = 32, color = TEXT_WHITE, align = airui.TEXT_ALIGN_LEFT })
    
    -- 游戏信息区域
    local info_container = airui.container({ parent = main_container, x = 20, y = 80, w = CONTAINER_WIDTH, h = 130, color = WHITE_COLOR, radius = 5 })
    
    target_label = airui.label({ parent = info_container, x = 20, y = 15, w = 400, h = 25, text = "目标数字: 0", font_size = 20, color = TEXT_PRIMARY, align = airui.TEXT_ALIGN_LEFT })
    split_label = airui.label({ parent = info_container, x = 20, y = 50, w = 400, h = 25, text = "拆分结果: ", font_size = 16, color = TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })
    
    local stats_container = airui.container({ parent = info_container, x = 20, y = 90, w = 400, h = 25, color = WHITE_COLOR })
    score_label = airui.label({ parent = stats_container, x = 0, y = 0, w = 133, h = 25, text = "分数: 0", font_size = 14, color = TEXT_PRIMARY, align = airui.TEXT_ALIGN_LEFT })
    level_label = airui.label({ parent = stats_container, x = 133, y = 0, w = 133, h = 25, text = "关卡: 1", font_size = 14, color = TEXT_PRIMARY, align = airui.TEXT_ALIGN_LEFT })
    game_mode_label = airui.label({ parent = stats_container, x = 266, y = 0, w = 134, h = 25, text = "模式: 求和模式", font_size = 14, color = TEXT_PRIMARY, align = airui.TEXT_ALIGN_LEFT })

    -- 数字按钮区域
    local number_container = airui.container({ parent = main_container, x = 20, y = 210, w = CONTAINER_WIDTH, h = 400, color = WHITE_COLOR, radius = 5 })
    
    -- 数字按钮（3x3网格）
    local numbers = {1, 2, 3, 4, 5, 6, 7, 8, 9}
    
    local total_width = 3 * BUTTON_SIZE + 2 * GAP
    local left_margin = (CONTAINER_WIDTH - total_width) / 2
    
    for i, num in ipairs(numbers) do
        local row = math.floor((i-1) / 3)
        local col = (i-1) % 3
        local x = col * (BUTTON_SIZE + GAP) + left_margin
        local y = row * (BUTTON_SIZE + GAP) + GAP
        
        create_button(number_container, x, y, BUTTON_SIZE, BUTTON_SIZE, tostring(num), NUMBER_BUTTON_BG, NUMBER_BUTTON_TEXT, function() handle_number_click(num) end)
    end

    -- 底部按钮栏
    local bottom_bar = airui.container({ parent = main_container, x = 0, y = 630, w = 480, h = 150, color = WHITE_COLOR })
    
    -- 清除按钮
    create_button(bottom_bar, 20, 15, BOTTOM_BUTTON_WIDTH, BOTTOM_BUTTON_HEIGHT, "清除", WARNING_COLOR, TEXT_WHITE, handle_clear_click)
    
    -- 新游戏按钮
    create_button(bottom_bar, 170, 15, BOTTOM_BUTTON_WIDTH, BOTTOM_BUTTON_HEIGHT, "新游戏", SUCCESS_COLOR, TEXT_WHITE, start_new_game)
    
    -- 切换模式按钮
    create_button(bottom_bar, 320, 15, 140, BOTTOM_BUTTON_HEIGHT, "切换模式", SECONDARY_COLOR, TEXT_WHITE, toggle_game_mode)
    
    -- 返回按钮
    create_button(bottom_bar, 20, 70, RETURN_BUTTON_WIDTH, BOTTOM_BUTTON_HEIGHT, "返回首页", GRAY_COLOR, TEXT_WHITE, function() sys.publish("OPEN_IDLE_WIN") end)

    -- 开始新游戏
    start_new_game()
end

local function on_create()
    create_ui()
end

local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    -- 清理所有状态变量
    current_split = {}
    target_number = 0
    score = 0
    level = 1
    game_mode = "sum"
    target_label = nil
    split_label = nil
    score_label = nil
    level_label = nil
    game_mode_label = nil
end

local function on_get_focus()
    -- 获得焦点时的处理
end

local function on_lose_focus()
    -- 失去焦点时的处理
end

local function open_handler()
    exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_GAME_SPLIT_NUMBER_WIN", open_handler)