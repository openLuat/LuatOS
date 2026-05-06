-- 游戏逻辑
local game_state = {
    idioms = {},
    cur_idx = 1,
    total_score = 0,
    game_over = false
}

local function new_game(idioms, group_size)
    -- 随机选择成语
    local shuffled = {}
    for i, idiom in ipairs(idioms) do
        shuffled[i] = idiom
    end
    
    -- 打乱顺序
    for i = #shuffled, 2, -1 do
        local j = math.random(i)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end
    
    -- 取前group_size个
    local selected = {}
    for i = 1, math.min(group_size, #shuffled) do
        selected[i] = shuffled[i]
    end
    
    game_state = {
        idioms = selected,
        cur_idx = 1,
        total_score = 0,
        game_over = false
    }
end

local function get_state()
    return game_state
end

local function get_current_idiom()
    if game_state.cur_idx > #game_state.idioms then
        game_state.game_over = true
        return nil
    end
    return game_state.idioms[game_state.cur_idx]
end

local function next_question()
    game_state.cur_idx = game_state.cur_idx + 1
    if game_state.cur_idx > #game_state.idioms then
        game_state.game_over = true
    end
end

local function check_answer(idiom, selected_char)
    local word = idiom.word
    local i = 1
    local char_index = 1
    
    while i <= #word do
        local char = string.sub(word, i, i)
        local byte = string.byte(char)
        if byte >= 0x80 then
            char = string.sub(word, i, i + 2)
            i = i + 3
        else
            i = i + 1
        end
        
        if char_index == idiom.blank then
            return char == selected_char
        end
        char_index = char_index + 1
    end
    
    return false
end

local function update_score(correct, points)
    if correct then
        game_state.total_score = game_state.total_score + points
    end
end

local function reset_game()
    game_state.cur_idx = 1
    game_state.total_score = 0
    game_state.game_over = false
end

local function build_display_text(idiom)
    local chars = {}
    local word = idiom.word
    local i = 1
    local char_index = 1
    
    while i <= #word do
        local char = string.sub(word, i, i)
        local byte = string.byte(char)
        if byte >= 0x80 then
            char = string.sub(word, i, i + 2)
            i = i + 3
        else
            i = i + 1
        end
        
        if char_index == idiom.blank then
            table.insert(chars, "?")
        else
            table.insert(chars, char)
        end
        char_index = char_index + 1
    end
    
    return table.concat(chars, " ")
end

local function shuffle_options(opts)
    local shuffled = {}
    for i, opt in ipairs(opts) do
        shuffled[i] = opt
    end
    
    for i = #shuffled, 2, -1 do
        local j = math.random(i)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end
    
    return shuffled
end

return {
    new_game = new_game,
    get_state = get_state,
    get_current_idiom = get_current_idiom,
    next_question = next_question,
    check_answer = check_answer,
    update_score = update_score,
    reset_game = reset_game,
    build_display_text = build_display_text,
    shuffle_options = shuffle_options
}