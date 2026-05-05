local win_id = nil
local main_container = nil
local idiom_label = nil
local score_label = nil
local progress_label = nil
local msg_label = nil
local opt_btns = {}
local opt_texts = {}
local next_timer = nil

-- 加载模块
log.info("main", "开始加载模块")

local function load_module(name)
    local ok, module = pcall(require, name)
    if not ok then
        log.error("main", "加载模块失败:", name, module)
        return nil
    end
    log.info("main", "加载模块成功:", name)
    return module
end

local config = load_module("app_config")
local idiom_data = load_module("idiom_data")
local game_logic = load_module("game_logic")

if not config or not idiom_data or not game_logic then
    log.error("main", "模块加载失败，应用无法启动")
    return
end

log.info("main", "所有模块加载成功")

local function update_stats()
    local state = game_logic.get_state()
    if score_label then
        score_label:set_text("得分:" .. state.total_score)
    end
    if progress_label then
        progress_label:set_text(string.format("%d/%d", state.cur_idx, config.GAME.GROUP_SIZE))
    end
end

local function load_current_question()
    local state = game_logic.get_state()
    
    if state.game_over then
        msg_label:set_text("通关! 点击[新一组]继续")
        for i, btn in ipairs(opt_btns) do
            btn:set_text("--")
            opt_texts[i] = "--"
        end
        return
    end
    
    local idiom = game_logic.get_current_idiom()
    if not idiom then 
        log.error("main", "没有当前成语")
        return 
    end
    
    log.info("main", "当前成语:", idiom.word, "空白位置:", idiom.blank)
    
    local disp_text = game_logic.build_display_text(idiom)
    log.info("main", "显示文本:", disp_text)
    
    if idiom_label then
        idiom_label:set_text(disp_text)
    end
    
    local opts = game_logic.shuffle_options(idiom.opts)
    log.info("main", "选项:", table.concat(opts, ","))
    
    for i = 1, 4 do
        local btn = opt_btns[i]
        if btn then
            btn:set_text(opts[i] or "")
            opt_texts[i] = opts[i] or ""
        end
    end
    
    update_stats()
    msg_label:set_text("请选择正确汉字填空")
end

local function go_to_next_question()
    if next_timer then
        sys.timerStop(next_timer)
        next_timer = nil
    end
    game_logic.next_question()
    load_current_question()
end

local function on_option_click(selected_char)
    local state = game_logic.get_state()
    if state.game_over then return end
    
    local idiom = game_logic.get_current_idiom()
    if not idiom then return end
    
    local correct = game_logic.check_answer(idiom, selected_char)
    
    if correct then
        game_logic.update_score(true, config.GAME.SCORE_PER_CORRECT)
        update_stats()
        msg_label:set_text("正确! +" .. config.GAME.SCORE_PER_CORRECT .. "分")
        
        if next_timer then sys.timerStop(next_timer) end
        next_timer = sys.timerStart(go_to_next_question, config.GAME.DELAY_NEXT)
    else
        msg_label:set_text("错误, 再试试~")
    end
end

local function reset_group()
    if next_timer then
        sys.timerStop(next_timer)
        next_timer = nil
    end
    game_logic.reset_game()
    load_current_question()
    msg_label:set_text("已重置当前组")
end

local function new_group()
    if next_timer then
        sys.timerStop(next_timer)
        next_timer = nil
    end
    game_logic.new_game(idiom_data.get_all(), config.GAME.GROUP_SIZE)
    load_current_question()
    msg_label:set_text("新的一组随机成语!")
end

local function create_ui()
    log.info("main", "开始创建UI")
    
    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = config.SCREEN.WIDTH,
        h = config.SCREEN.HEIGHT,
        color = config.COLORS.BG
    })
    
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = config.SCREEN.WIDTH,
        h = config.LAYOUT.TITLE_HEIGHT,
        color = config.COLORS.TITLE_BAR
    })
    
    airui.label({
        parent = title_bar,
        text = "成语填空",
        x = 20,  -- 向右移动20px
        y = 20,
        w = config.SCREEN.WIDTH - 20,  -- 调整宽度以适应移动
        h = 30,
        color = config.COLORS.TEXT_TITLE,
        font_size = config.FONT.TITLE_SIZE,
        halign = "left"  -- 改为左对齐
    })
    
    score_label = airui.label({
        parent = main_container,
        text = "得分:0",
        x = 20,  -- 与标题左对齐
        y = 80,
        w = 150,
        h = 30,
        color = config.COLORS.TEXT_PRIMARY,
        font_size = config.FONT.MESSAGE_SIZE
    })
    
    progress_label = airui.label({
        parent = main_container,
        text = "1/10",
        x = config.SCREEN.WIDTH - 100,
        y = 80,
        w = 80,
        h = 30,
        color = config.COLORS.TEXT_ACCENT,
        font_size = config.FONT.MESSAGE_SIZE
    })
    
    -- 成语卡片
    local card_width = 440  -- 父级容器宽度440
    local idiom_x = (config.SCREEN.WIDTH - card_width) // 2  -- 水平居中
    local idiom_y = config.LAYOUT.CARD_Y
    
    local card_bg = airui.container({
        parent = main_container,
        x = idiom_x,
        y = idiom_y,
        w = card_width,  -- 宽度440
        h = config.LAYOUT.CARD_HEIGHT,
        color = config.COLORS.CARD_BG,
        radius = config.LAYOUT.CARD_RADIUS
    })
    
    local label_w = card_width - 40  -- 留20px边距
    local label_h = 80
    local label_x = 20  -- 20px左边距
    local label_y = 70  -- 离顶边距离70px
    
    idiom_label = airui.label({
        parent = card_bg,  -- 改为card_bg作为父容器
        text = "测试",
        x = label_x,
        y = label_y,
        w = label_w,
        h = label_h,
        color = 0xffffff,
        font_size = config.FONT.IDIOM_SIZE,
        align = airui.TEXT_ALIGN_CENTER,  -- 水平居中
        valign = airui.TEXT_VALIGN_CENTER  -- 垂直居中
    })
    
    -- 选项按钮
    local btn_panel = airui.container({
        parent = main_container,
        x = (config.SCREEN.WIDTH - config.LAYOUT.OPTIONS_WIDTH) // 2,
        y = config.LAYOUT.OPTIONS_Y,
        w = config.LAYOUT.OPTIONS_WIDTH,
        h = config.LAYOUT.OPTIONS_HEIGHT,
        color = config.COLORS.BG,
        radius = config.LAYOUT.PANEL_RADIUS
    })
    
    local btn_w = (config.LAYOUT.OPTIONS_WIDTH - 30) // 2
    local btn_h = 55
    local padding = 10
    
    for i = 1, 4 do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        
        local x = padding + col * (btn_w + padding)
        local y = padding + row * (btn_h + padding)
        
        local btn_idx = i
        
        local btn = airui.button({
            parent = btn_panel,
            text = "",
            x = x,
            y = y,
            w = btn_w,
            h = btn_h,
            color = config.COLORS.BUTTON,
            radius = config.LAYOUT.BUTTON_RADIUS,
            font_size = config.FONT.BUTTON_SIZE,
            on_click = function()
                local state = game_logic.get_state()
                if not state.game_over then
                    local char = opt_texts[btn_idx]
                    if char and char ~= "" then
                        on_option_click(char)
                    end
                end
            end
        })
        
        table.insert(opt_btns, btn)
    end
    
    -- 消息标签
    msg_label = airui.label({
        parent = main_container,
        text = "请选择正确汉字填空",
        x = 20,
        y = config.LAYOUT.MESSAGE_Y,
        w = config.SCREEN.WIDTH - 40,
        h = config.LAYOUT.MESSAGE_HEIGHT,
        color = config.COLORS.TEXT_PRIMARY,
        font_size = config.FONT.MESSAGE_SIZE,
        halign = "center"
    })
    
    -- 底部按钮
    local reset_btn = airui.button({
        parent = main_container,
        text = "重置",
        x = 30,
        y = config.LAYOUT.BUTTON_Y,
        w = config.LAYOUT.BUTTON_WIDTH,
        h = config.LAYOUT.BUTTON_HEIGHT,
        color = config.COLORS.BUTTON,
        radius = config.LAYOUT.BUTTON_RADIUS,
        font_size = config.FONT.BUTTON_SIZE,
        on_click = reset_group
    })
    
    local new_btn = airui.button({
        parent = main_container,
        text = "新一组",
        x = 180,
        y = config.LAYOUT.BUTTON_Y,
        w = config.LAYOUT.BUTTON_WIDTH,
        h = config.LAYOUT.BUTTON_HEIGHT,
        color = config.COLORS.BUTTON,
        radius = config.LAYOUT.BUTTON_RADIUS,
        font_size = config.FONT.BUTTON_SIZE,
        on_click = new_group
    })
    
    local exit_btn = airui.button({
        parent = main_container,
        text = "退出",
        x = config.SCREEN.WIDTH - config.LAYOUT.BUTTON_WIDTH - 30,
        y = config.LAYOUT.BUTTON_Y,
        w = config.LAYOUT.BUTTON_WIDTH,
        h = config.LAYOUT.BUTTON_HEIGHT,
        color = config.COLORS.BUTTON,
        radius = config.LAYOUT.BUTTON_RADIUS,
        font_size = config.FONT.BUTTON_SIZE,
        on_click = function()
            log.info("main", "退出应用")
            if win_id then
                exwin.close(win_id)
                win_id = nil
            end
        end
    })
    
    log.info("main", "UI创建完成")
end

local function on_create()
    log.info("main", "创建窗口")
    math.randomseed(os.time())
    game_logic.new_game(idiom_data.get_all(), config.GAME.GROUP_SIZE)
    create_ui()
    load_current_question()
    log.info("main", "窗口创建完成")
end

local function on_destroy()
    log.info("main", "销毁窗口")
    if next_timer then
        sys.timerStop(next_timer)
        next_timer = nil
    end
    
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    
    idiom_label = nil
    score_label = nil
    progress_label = nil
    msg_label = nil
    opt_btns = {}
    opt_texts = {}
    win_id = nil
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    log.info("main", "打开窗口")
    local exwin = require("exwin")
    if exwin then
        win_id = exwin.open({
            on_create = on_create,
            on_destroy = on_destroy,
            on_get_focus = on_get_focus,
            on_lose_focus = on_lose_focus,
        })
        log.info("main", "窗口打开，ID:", win_id)
    else
        log.error("main", "exwin模块加载失败")
    end
end

sys.subscribe("OPEN_IDIOM_APP", open_handler)