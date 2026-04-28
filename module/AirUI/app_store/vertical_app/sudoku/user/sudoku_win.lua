--[[
@module  sudoku_win
@summary 数独游戏窗口模块
@version 1.0
@date    2026.03.30
@author  杨乔杉
]]

-- 死机不重启接口


local win_id = nil
local main_container
local board = {}        -- 9x9 数字矩阵（0表示空格）
local fixed = {}        -- 是否固定数字（初始题目）
local buttons = {}      -- 9x9 按钮对象
local selected_row, selected_col = nil, nil  -- 当前选中格子
local num_pad_container = nil  -- 自定义数字键盘容器

-- 预生成数独题目的缓存池
local puzzle_cache = {}
local cache_size = 5  -- 缓存5个题目

-- ==================== 数独生成器 ====================

-- 深拷贝9x9矩阵
local function deepcopy_9x9(matrix)
    local copy = {}
    for i = 1, 9 do
        copy[i] = {}
        for j = 1, 9 do
            copy[i][j] = matrix[i][j]
        end
    end
    return copy
end

-- 检查在指定位置放置数字是否合法
local function is_valid(board, row, col, num)
    -- 检查行
    for c = 1, 9 do
        if board[row][c] == num then return false end
    end
    -- 检查列
    for r = 1, 9 do
        if board[r][col] == num then return false end
    end
    -- 检查3x3宫
    local start_row = math.floor((row - 1) / 3) * 3 + 1
    local start_col = math.floor((col - 1) / 3) * 3 + 1
    for r = start_row, start_row + 2 do
        for c = start_col, start_col + 2 do
            if board[r][c] == num then return false end
        end
    end
    return true
end

-- 使用回溯法求解数独，返回解的数量
local function solve_sudoku(board, count_limit)
    count_limit = count_limit or 2  -- 默认最多找2个解
    local solutions = 0

    local function solve()
        if solutions >= count_limit then return true end

        -- 找到第一个空格
        local empty_row, empty_col
        for i = 1, 9 do
            for j = 1, 9 do
                if board[i][j] == 0 then
                    empty_row, empty_col = i, j
                    break
                end
            end
            if empty_row then break end
        end

        -- 如果没有空格，找到解
        if not empty_row then
            solutions = solutions + 1
            return solutions >= count_limit
        end

        -- 尝试1-9的数字
        local nums = {1, 2, 3, 4, 5, 6, 7, 8, 9}
        -- 随机化数字顺序以增加多样性
        for i = #nums, 2, -1 do
            local j = math.random(i)
            nums[i], nums[j] = nums[j], nums[i]
        end

        for _, num in ipairs(nums) do
            if is_valid(board, empty_row, empty_col, num) then
                board[empty_row][empty_col] = num
                if solve() then return true end
                board[empty_row][empty_col] = 0
            end
        end

        return false
    end

    solve()
    return solutions
end

-- 生成完整的数独解（优化版本）
local function generate_complete_solution()
    -- 使用基础模板快速生成
    local base_template = {
        {1,2,3,4,5,6,7,8,9},
        {4,5,6,7,8,9,1,2,3},
        {7,8,9,1,2,3,4,5,6},
        {2,3,1,5,6,4,8,9,7},
        {5,6,4,8,9,7,2,3,1},
        {8,9,7,2,3,1,5,6,4},
        {3,1,2,6,4,5,9,7,8},
        {6,4,5,9,7,8,3,1,2},
        {9,7,8,3,1,2,6,4,5}
    }

    local board = deepcopy_9x9(base_template)

    -- 随机变换整个棋盘
    -- 1. 随机交换行（在每个3x3宫格内）
    for block_row = 0, 2 do
        local rows = {1, 2, 3}
        for i = #rows, 2, -1 do
            local j = math.random(i)
            rows[i], rows[j] = rows[j], rows[i]
        end
        if rows[1] ~= rows[2] then
            local r1 = block_row * 3 + rows[1]
            local r2 = block_row * 3 + rows[2]
            board[r1], board[r2] = board[r2], board[r1]
        end
    end

    -- 2. 随机交换列（在每个3x3宫格内）
    for block_col = 0, 2 do
        local cols = {1, 2, 3}
        for i = #cols, 2, -1 do
            local j = math.random(i)
            cols[i], cols[j] = cols[j], cols[i]
        end
        if cols[1] ~= cols[2] then
            local c1 = block_col * 3 + cols[1]
            local c2 = block_col * 3 + cols[2]
            for r = 1, 9 do
                board[r][c1], board[r][c2] = board[r][c2], board[r][c1]
            end
        end
    end

    -- 3. 随机交换3x3宫格行
    local block_rows = {0, 1, 2}
    for i = #block_rows, 2, -1 do
        local j = math.random(i)
        block_rows[i], block_rows[j] = block_rows[j], block_rows[i]
    end
    if block_rows[1] ~= block_rows[2] then
        local br1 = block_rows[1]
        local br2 = block_rows[2]
        for r_offset = 0, 2 do
            local r1 = br1 * 3 + r_offset + 1
            local r2 = br2 * 3 + r_offset + 1
            board[r1], board[r2] = board[r2], board[r1]
        end
    end

    -- 4. 随机交换3x3宫格列
    local block_cols = {0, 1, 2}
    for i = #block_cols, 2, -1 do
        local j = math.random(i)
        block_cols[i], block_cols[j] = block_cols[j], block_cols[i]
    end
    if block_cols[1] ~= block_cols[2] then
        local bc1 = block_cols[1]
        local bc2 = block_cols[2]
        for c_offset = 0, 2 do
            local c1 = bc1 * 3 + c_offset + 1
            local c2 = bc2 * 3 + c_offset + 1
            for r = 1, 9 do
                board[r][c1], board[r][c2] = board[r][c2], board[r][c1]
            end
        end
    end

    -- 5. 随机数字映射（增加多样性）
    local mapping = {1,2,3,4,5,6,7,8,9}
    for i = #mapping, 2, -1 do
        local j = math.random(i)
        mapping[i], mapping[j] = mapping[j], mapping[i]
    end

    for r = 1, 9 do
        for c = 1, 9 do
            board[r][c] = mapping[board[r][c]]
        end
    end

    return board
end

-- 生成数独题目（根据难度，带缓存）
-- difficulty: 1=简单, 2=中等, 3=困难
local function generate_sudoku_puzzle(difficulty)
    difficulty = difficulty or 2

    -- 先检查缓存中是否有相同难度的题目
    if puzzle_cache[difficulty] and #puzzle_cache[difficulty] > 0 then
        local cached_puzzle = table.remove(puzzle_cache[difficulty], 1)
        return cached_puzzle
    end

    -- 生成完整解
    local solution = generate_complete_solution()

    -- 根据难度决定要保留的数字数量
    local keep_count
    if difficulty == 1 then
        keep_count = math.random(45, 50)  -- 简单：保留45-50个数字
    elseif difficulty == 2 then
        keep_count = math.random(32, 38)  -- 中等：保留32-38个数字
    else
        keep_count = math.random(25, 30)  -- 困难：保留25-30个数字
    end

    -- 创建要移除的位置列表并随机化
    local positions = {}
    for i = 1, 9 do
        for j = 1, 9 do
            table.insert(positions, {i, j})
        end
    end

    -- 随机化位置顺序
    for i = #positions, 2, -1 do
        local j = math.random(i)
        positions[i], positions[j] = positions[j], positions[i]
    end

    -- 优化的挖空算法：批量移除而非逐个验证
    local puzzle = deepcopy_9x9(solution)
    local removed = 0
    local target_removed = 81 - keep_count

    -- 第一步：批量移除数字（不验证唯一解）
    for _, pos in ipairs(positions) do
        if removed >= target_removed then break end
        local row, col = pos[1], pos[2]
        puzzle[row][col] = 0
        removed = removed + 1
    end

    -- 第二步：只验证少量关键位置确保基本可解性
    -- 从对称位置中选择几个进行验证，而不是全部验证
    local check_positions = {}
    for i = 1, 5 do  -- 只检查5个随机位置
        local idx = math.random(#positions)
        table.insert(check_positions, positions[idx])
    end

    for _, pos in ipairs(check_positions) do
        local row, col = pos[1], pos[2]
        if puzzle[row][col] ~= 0 then  -- 如果这个位置还有数字
            local backup = puzzle[row][col]
            puzzle[row][col] = 0

            -- 快速检查是否仍可解
            local test_board = deepcopy_9x9(puzzle)
            local solution_count = solve_sudoku(test_board, 2)

            if solution_count ~= 1 then
                puzzle[row][col] = backup  -- 恢复数字
            end
        end
    end

    return puzzle
end

-- 预生成数独题目填充缓存
local function pre_generate_puzzles()
    for difficulty = 1, 3 do
        puzzle_cache[difficulty] = {}
        for i = 1, cache_size do
            local puzzle = generate_sudoku_puzzle(difficulty)
            table.insert(puzzle_cache[difficulty], puzzle)
        end
    end
end

-- 冲突检测
local function has_conflict(row, col)
    local num = board[row][col]
    if num == 0 then return false end
    -- 检查行
    for c = 1, 9 do
        if c ~= col and board[row][c] == num then return true end
    end
    -- 检查列
    for r = 1, 9 do
        if r ~= row and board[r][col] == num then return true end
    end
    -- 检查3x3宫
    local start_r = math.floor((row - 1) / 3) * 3 + 1
    local start_c = math.floor((col - 1) / 3) * 3 + 1
    for r = start_r, start_r + 2 do
        for c = start_c, start_c + 2 do
            if (r ~= row or c ~= col) and board[r][c] == num then
                return true
            end
        end
    end
    return false
end

-- 更新所有按钮的高亮样式
local function update_conflict_highlight() 
    -- 只更新有变化的按钮，减少不必要的UI更新
    for i = 1, 9 do
        for j = 1, 9 do
            local btn = buttons[i][j]
            if btn then
                if fixed[i][j] then
                    -- 固定数字：灰色背景
                    btn:set_style({ bg_color = 0xE0E0E0, text_color = 0x000000 })
                else
                    if board[i][j] ~= 0 and has_conflict(i, j) then
                        -- 冲突：红色背景
                        btn:set_style({ bg_color = 0xFFCCCC, text_color = 0x000000 })
                    else
                        -- 正常：白色背景
                        btn:set_style({ bg_color = 0xFFFFFF, text_color = 0x000000 })
                    end
                end
            end
        end
    end
end

-- 检查胜利
local function check_win()
    for i = 1, 9 do
        for j = 1, 9 do
            if board[i][j] == 0 or has_conflict(i, j) then
                return false
            end
        end
    end
    return true
end

-- 重置游戏到初始状态
local function reset_game()
    -- 随机选择难度并生成新的数独题目
    math.randomseed(os.time())
    local difficulty = math.random(3)  -- 1=简单, 2=中等, 3=困难
    local random_board = generate_sudoku_puzzle(difficulty)

    for i = 1, 9 do
        for j = 1, 9 do
            board[i][j] = random_board[i][j]
            fixed[i][j] = (random_board[i][j] ~= 0)
            if board[i][j] == 0 then
                buttons[i][j]:set_text("")
            else
                buttons[i][j]:set_text(tostring(board[i][j]))
            end
        end
    end
    update_conflict_highlight()
    selected_row, selected_col = nil, nil
    if num_pad_container and num_pad_container.set_visible then
        num_pad_container:set_visible(false)
    end

    -- 异步预生成下一个题目（不阻塞UI）
    sys.taskInit(function()
        local next_difficulty = math.random(3)
        local puzzle = generate_sudoku_puzzle(next_difficulty)
        if not puzzle_cache[next_difficulty] then
            puzzle_cache[next_difficulty] = {}
        end
        if #puzzle_cache[next_difficulty] < cache_size then
            table.insert(puzzle_cache[next_difficulty], puzzle)
        end
    end)
end

-- 初始化游戏数据
local function init_game_data()
    -- 随机选择难度并生成新的数独题目
    math.randomseed(os.time())
    local difficulty = math.random(3)  -- 1=简单, 2=中等, 3=困难
    local random_board = generate_sudoku_puzzle(difficulty)
    
    -- 初始化board和fixed表
    for i = 1, 9 do
        board[i] = {}
        fixed[i] = {}
        for j = 1, 9 do
            board[i][j] = random_board[i][j]
            fixed[i][j] = (random_board[i][j] ~= 0)
        end
    end
end

-- 创建UI
local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = 480, h = 800, color = 0xF8F9FA, parent = airui.screen })

    -- 顶部标题栏
    local title_bar = airui.container({ parent = main_container, x = 0, y = 0, w = 480, h = 60, color = 0x3F51B5 })
    airui.label({ parent = title_bar, x = 0, y = 10, w = 480, h = 40, text = "数独游戏", font_size = 24, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })

    -- 计算网格布局（9x9，每个格子48x48，总宽432，居中）
    local cell_size = 48
    local grid_size = 9 * cell_size
    local offset_x = (480 - grid_size) / 2
    local offset_y = 100  -- 顶部留空给标题

    -- 先初始化游戏数据
    init_game_data()

    -- 创建9x9按钮网格
    for i = 1, 9 do
        buttons[i] = {}
        for j = 1, 9 do
            local x = offset_x + (j - 1) * cell_size
            local y = offset_y + (i - 1) * cell_size
            local btn = airui.button({
                parent = main_container,
                x = x, y = y,
                w = cell_size, h = cell_size,
                text = "",
                style = {
                    bg_color = 0xFFFFFF,
                    border_color = 0xCCCCCC,
                    border_width = 1,
                    radius = 0,
                },
                on_click = function(self)
                    -- 固定数字不可编辑
                    if fixed and fixed[i] and fixed[i][j] then return end
                    selected_row, selected_col = i, j
                    if num_pad_container and num_pad_container.set_visible then
                        num_pad_container:set_visible(true)   -- 显示数字键盘
                    end
                end
            })
            buttons[i][j] = btn
        end
    end

    -- 创建自定义数字键盘（使用按钮替代）
    num_pad_container = airui.container({
        parent = main_container,
        x = 0, y = 532,  -- 位于棋盘下方
        w = 480, h = 208,
        color = 0xEEEEEE,
        visible = false,  -- 初始隐藏
    })
    
    -- 重新设计数字键盘布局，铺满整个宽度
    local total_width = 480  -- 不留边距，完全铺满
    local num_cols = 4  -- 4列布局
    local num_rows = 3  -- 3行布局
    local btn_spacing = 4
    local btn_width = math.floor((total_width - (num_cols - 1) * btn_spacing) / num_cols)
    local btn_height = math.floor((208 - 20 - (num_rows - 1) * btn_spacing) / num_rows)  -- 208是容器高度
    local start_x = 0
    local start_y = 20
    
    -- 创建数字按钮 1-9 和功能按钮
    local buttons_layout = {
        {1, 2, 3, "清除"},
        {4, 5, 6, "X"},
        {7, 8, 9, "确认"}
    }
    
    for row = 1, num_rows do
        for col = 1, num_cols do
            local value = buttons_layout[row][col]
            if value ~= "" then
                local x = start_x + (col - 1) * (btn_width + btn_spacing)
                local y = start_y + (row - 1) * (btn_height + btn_spacing)
                
                airui.button({
                    parent = num_pad_container,
                    x = x, y = y,
                    w = btn_width, h = btn_height,
                    text = tostring(value),
                    style = {
                        bg_color = value == "清除" and 0xFFCCCC or (value == "X" and 0xCCCCCC or 0xFFFFFF),
                        text_color = 0x000000,
                        border_color = 0xCCCCCC,
                        border_width = 1,
                        radius = 5,
                    },
                    on_click = function(self)
                        if type(value) == "number" then
                            -- 数字按钮
                            if selected_row and selected_col and buttons and buttons[selected_row] and buttons[selected_row][selected_col] then
                                -- 更新游戏数据
                                board[selected_row][selected_col] = value
                                buttons[selected_row][selected_col]:set_text(tostring(value))
                                update_conflict_highlight()
                                -- 检查胜利
                                if check_win() then
                                    airui.msgbox({
                                        title = "恭喜！",
                                        text = "你成功完成了数独！\n点击新游戏继续挑战。",
                                        buttons = { "新游戏" },
                                        on_action = function(self, label)
                                            if label == "新游戏" then
                                                self:hide()
                                                reset_game()
                                            end
                                            -- 正确关闭提示框的方法
                                            self:destroy()
                                        end
                                    }):show()
                                end
                                -- 隐藏数字键盘
                                if num_pad_container and num_pad_container.set_visible then
                                    num_pad_container:set_visible(false)
                                end
                                selected_row, selected_col = nil, nil
                            end
                        elseif value == "清除" then
                            -- 清除按钮
                            if selected_row and selected_col and buttons and buttons[selected_row] and buttons[selected_row][selected_col] then
                                board[selected_row][selected_col] = 0
                                buttons[selected_row][selected_col]:set_text("")
                                update_conflict_highlight()
                                if num_pad_container and num_pad_container.set_visible then
                                    num_pad_container:set_visible(false)
                                end
                                selected_row, selected_col = nil, nil
                            end
                        elseif value == "X" then
                            -- 关闭按钮
                            if num_pad_container and num_pad_container.set_visible then
                                num_pad_container:set_visible(false)
                            end
                            selected_row, selected_col = nil, nil
                        elseif value == "确认" then
                            -- 确认按钮：隐藏键盘
                            if num_pad_container and num_pad_container.set_visible then
                                num_pad_container:set_visible(false)
                            end
                            selected_row, selected_col = nil, nil
                        end
                    end
                })
            end
        end
    end

    -- 底部按钮栏
    local bottom_bar = airui.container({ parent = main_container, x = 0, y = 740, w = 480, h = 60, color = 0xffffff })
    
    -- 新游戏按钮
    local new_btn = airui.button({
        parent = bottom_bar,
        x = 0,
        y = 0,
        w = 240,
        h = 60,
        text = "新游戏",
        style = {
            bg_color = 0xFF9A27,
            text_color = 0xfefefe,
            border_color = 0xFF9A27,
            border_width = 0,
            radius = 0,
        },
        on_click = reset_game
    })

    -- 返回按钮
    local back_btn = airui.button({
        parent = bottom_bar,
        x = 240,
        y = 0,
        w = 240,
        h = 60,
        text = "退出",
        style = {
            bg_color = 0x2195F6,
            text_color = 0xfefefe,
            border_color = 0x2195F6,
            border_width = 0,
            radius = 0,
        },
        on_click = function() if win_id then exwin.close(win_id) end end
    })

    -- 初始化游戏
    reset_game()
end

local function on_create()
    create_ui()
    -- 窗口创建后异步预生成题目
    sys.taskInit(function()
        pre_generate_puzzles()
    end)
end

local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    buttons = {}
    num_pad_container = nil
    selected_row, selected_col = nil, nil
end

local function on_get_focus()
    -- 获得焦点时的处理
end

local function on_lose_focus()
    -- 失去焦点时的处理
end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_SUDOKU_WIN", open_handler)
