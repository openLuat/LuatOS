--[[
@module  game_2048_win
@summary 2048游戏窗口模块
@version 1.0
@date    2026.04.03
@author  杨乔杉
]]

local win_id = nil
local main_container
local board = {}        -- 4x4 游戏棋盘
local tiles = {}        -- 4x4 瓷砖对象
local score = 0         -- 当前分数
local best_score = 0    -- 最高分
local score_label
local best_score_label
local game_over = false
local game_over_msgbox = nil  -- 游戏结束消息框引用

-- 获取瓷砖颜色
local function get_tile_color(value)
    if value == 0 then
        return { bg = 0xCDC1B4, text = 0x776E65 }
    end

    -- 2的幂次方对应的颜色
    local colors = {
        [1] = { bg = 0xEEE4DA, text = 0x776E65 },  -- 2
        [2] = { bg = 0xEDE0C8, text = 0x776E65 },  -- 4
        [3] = { bg = 0xF2B179, text = 0xF9F6F2 },  -- 8
        [4] = { bg = 0xF59563, text = 0xF9F6F2 },  -- 16
        [5] = { bg = 0xF67C5F, text = 0xF9F6F2 },  -- 32
        [6] = { bg = 0xF65E3B, text = 0xF9F6F2 },  -- 64
        [7] = { bg = 0xEDCF72, text = 0xF9F6F2 },  -- 128
        [8] = { bg = 0xEDCC61, text = 0xF9F6F2 },  -- 256
        [9] = { bg = 0xEDC850, text = 0xF9F6F2 },  -- 512
        [10] = { bg = 0xEDC53F, text = 0xF9F6F2 }, -- 1024
        [11] = { bg = 0xEDC22E, text = 0xF9F6F2 }, -- 2048
    }

    local exponent = math.log(value) / math.log(2)
    if exponent <= 11 then
        return colors[exponent]
    else
        return { bg = 0x3C3A32, text = 0xF9F6F2 }  -- 大于2048
    end
end

-- 添加随机瓷砖（2或4）
local function add_random_tile()
    local empty_cells = {}
    for i = 1, 4 do
        for j = 1, 4 do
            if board[i][j] == 0 then
                table.insert(empty_cells, {i, j})
            end
        end
    end
    
    if #empty_cells > 0 then
        local cell = empty_cells[math.random(#empty_cells)]
        board[cell[1]][cell[2]] = math.random() < 0.9 and 2 or 4
    end
end

-- 初始化游戏板
local function init_board()
    for i = 1, 4 do
        board[i] = {0, 0, 0, 0}
    end
    -- 添加两个初始数字
    add_random_tile()
    add_random_tile()
end

-- 更新瓷砖UI
local function update_tiles()
    for i = 1, 4 do
        for j = 1, 4 do
            local value = board[i][j]
            local tile = tiles[i][j]
            if tile then
                local color = get_tile_color(value)
                tile:set_style({ bg_color = color.bg, text_color = color.text })
                tile:set_text(value == 0 and "" or tostring(value))
            end
        end
    end
    -- 更新分数
    score_label:set_text("分数: " .. score)
    best_score_label:set_text("最高分: " .. best_score)
end

-- 检查游戏是否结束
local function check_game_over()
    -- 检查是否有空格
    for i = 1, 4 do
        for j = 1, 4 do
            if board[i][j] == 0 then
                return false
            end
        end
    end

    -- 统一检查相邻相同数字
    for i = 1, 4 do
        for j = 1, 4 do
            -- 检查右边和下边即可
            if j < 4 and board[i][j] == board[i][j+1] then
                return false
            end
            if i < 4 and board[i][j] == board[i+1][j] then
                return false
            end
        end
    end

    return true
end

-- 处理一行/列的移动和合并
local function process_line(line, reverse)
    local new_line = {}
    local pos = reverse and 4 or 1
    local step = reverse and -1 or 1
    local moved = false

    -- 移动非零元素
    for i = reverse and 4 or 1, reverse and 1 or 4, step do
        if line[i] ~= 0 then
            new_line[pos] = line[i]
            pos = pos + step
        end
    end

    -- 合并相邻相同数字
    for i = reverse and 4 or 1, reverse and 2 or 3, step do
        local next_i = i + step
        if new_line[i] and new_line[i] ~= 0 and new_line[i] == new_line[next_i] then
            new_line[i] = new_line[i] * 2
            score = score + new_line[i]
            new_line[next_i] = nil
            moved = true
        end
    end

    -- 再次移动（填补合并后的空隙）
    local final_line = {}
    pos = reverse and 4 or 1
    for i = reverse and 4 or 1, reverse and 1 or 4, step do
        if new_line[i] and new_line[i] ~= 0 then
            final_line[pos] = new_line[i]
            pos = pos + step
        end
    end

    -- 检查是否有变化
    for i = 1, 4 do
        if (line[i] or 0) ~= (final_line[i] or 0) then
            moved = true
            break
        end
    end

    return final_line, moved
end

-- 统一移动函数
local function move(direction)
    local moved = false
    local is_row = (direction == "left" or direction == "right")
    local reverse = (direction == "down" or direction == "right")

    for i = 1, 4 do
        -- 获取一行或一列的数据
        local line = {}
        for j = 1, 4 do
            line[j] = is_row and board[i][j] or board[j][i]
        end

        -- 处理这一行/列
        local final_line, line_moved = process_line(line, reverse)
        if line_moved then
            moved = true
        end

        -- 更新棋盘
        for j = 1, 4 do
            local value = final_line[j] or 0
            if is_row then
                board[i][j] = value
            else
                board[j][i] = value
            end
        end
    end

    return moved
end

-- 处理移动
local function handle_move(direction)
    if game_over then return end

    local moved = move(direction)

    if moved then
        add_random_tile()
        update_tiles()

        if score > best_score then
            best_score = score
        end

        if check_game_over() then
            game_over = true
            if game_over_msgbox then
                game_over_msgbox:destroy()
                game_over_msgbox = nil
            end
            game_over_msgbox = airui.msgbox({
                title = "游戏结束",
                text = "你的分数: " .. score .. "\n点击重新开始",
                buttons = { "重新开始" },
                on_action = function(self, label)
                    if label == "重新开始" then
                        self:hide()
                        reset_game()
                    end
                    self:destroy()
                    game_over_msgbox = nil
                end
            }):show()
        end
    end
end

-- 重置游戏
local function reset_game()
    score = 0
    game_over = false
    init_board()
    update_tiles()
end

-- 创建UI
local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = 480, h = 800, color = 0xFAF8EF, parent = airui.screen })

    -- 顶部标题栏
    local title_bar = airui.container({ parent = main_container, x = 0, y = 0, w = 480, h = 80, color = 0xBBADA0 })
    airui.label({ parent = title_bar, x = 20, y = 20, w = 150, h = 40, text = "2048", font_size = 36, color = 0xfefefe, align = airui.TEXT_ALIGN_LEFT })
    
    -- 分数显示
    local score_container = airui.container({ parent = title_bar, x = 280, y = 20, w = 180, h = 60, color = 0xBBADA0 })
    score_label = airui.label({ parent = score_container, x = 0, y = 0, w = 180, h = 30, text = "分数: 0", font_size = 18, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })
    best_score_label = airui.label({ parent = score_container, x = 0, y = 30, w = 180, h = 30, text = "最高分: 0", font_size = 18, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })

    -- 游戏棋盘
    local board_container = airui.container({ parent = main_container, x = 40, y = 100, w = 400, h = 400, color = 0xBBADA0, radius = 5 })
    
    -- 创建4x4瓷砖网格
    local tile_size = 90
    local gap = 10
    for i = 1, 4 do
        tiles[i] = {}
        for j = 1, 4 do
            local x = (j-1) * (tile_size + gap) + gap
            local y = (i-1) * (tile_size + gap) + gap
            local tile = airui.button({
                parent = board_container,
                x = x, y = y,
                w = tile_size, h = tile_size,
                text = "",
                style = {
                    bg_color = 0xCDC1B4,
                    text_color = 0x776E65,
                    border_width = 0,
                    radius = 3,
                },
                on_click = function() end
            })
            tiles[i][j] = tile
        end
    end

    -- 方向按钮
    local dpad_container = airui.container({ parent = main_container, x = 115, y = 520, w = 250, h = 170, color = 0xFAF8EF })
    
    -- 上按钮
    airui.button({
        parent = dpad_container,
        x = 97, y = 5,
        w = 55, h = 55,
        text = "↑",
        font_size = 32,
        text_color = 0x776E65,
        bg_color = 0xBBADA0,
        on_click = function() handle_move("up") end
    })
    
    -- 左按钮
    airui.button({
        parent = dpad_container,
        x = 10, y = 60,
        w = 55, h = 55,
        text = "←",
        font_size = 32,
        text_color = 0x776E65,
        bg_color = 0xBBADA0,
        on_click = function() handle_move("left") end
    })
    
    -- 右按钮
    airui.button({
        parent = dpad_container,
        x = 185, y = 60,
        w = 55, h = 55,
        text = "→",
        font_size = 32,
        text_color = 0x776E65,
        bg_color = 0xBBADA0,
        on_click = function() handle_move("right") end
    })
    
    -- 下按钮
    airui.button({
        parent = dpad_container,
        x = 97, y = 115,
        w = 55, h = 55,
        text = "↓",
        font_size = 32,
        text_color = 0x776E65,
        bg_color = 0xBBADA0,
        on_click = function() handle_move("down") end
    })

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
            bg_color = 0x8F7A66,
            text_color = 0xfefefe,
            border_color = 0x8F7A66,
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
        text = "返回首页",
        style = {
            bg_color = 0x2195F6,
            text_color = 0xfefefe,
            border_color = 0x2195F6,
            border_width = 0,
            radius = 0,
        },
        on_click = function() exwin.close(win_id) end
    })

    -- 初始化游戏
    reset_game()
end

local function on_create()
    create_ui()
end

local function on_destroy()
    -- 销毁游戏结束消息框
    if game_over_msgbox then
        game_over_msgbox:destroy()
        game_over_msgbox = nil
    end

    -- 销毁主容器
    if main_container then
        main_container:destroy()
        main_container = nil
    end

    -- 清理所有状态变量
    tiles = {}
    board = {}
    score = 0
    best_score = 0
    game_over = false
    score_label = nil
    best_score_label = nil
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

sys.subscribe("OPEN_GAME_2048_WIN", open_handler)