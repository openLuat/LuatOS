--[[
@module  picture_character_learning_win
@summary 看图识字应用窗口模块
@version 1.0
@date    2026.04.09
@author  LuatOS
]]

local win_id = nil
local main_container
local current_index = 1

-- 识字数据
local character_data = {
    {id=1, character="猫", pinyin="māo", radical="犭", strokes=11, groups={"小猫","猫咪","猫头鹰"}, imgName="小猫", imgPath="cat.png", desc="可爱的小猫，喵喵叫", strokeHint="撇,弯钩,撇,横,竖,竖,横折,横,竖,横折,横"},
    {id=2, character="狗", pinyin="gǒu", radical="犭", strokes=8, groups={"小狗","狗狗","狗尾巴"}, imgName="小狗", imgPath="dog.png", desc="忠诚的朋友，汪汪叫", strokeHint="撇,弯钩,撇,撇,横折钩,竖,横折,横"},
    {id=3, character="日", pinyin="rì", radical="日", strokes=4, groups={"太阳","日出","日光"}, imgName="太阳", imgPath="sun.png", desc="温暖的太阳公公", strokeHint="竖,横折,横,横"},
    {id=4, character="月", pinyin="yuè", radical="月", strokes=4, groups={"月亮","月光","月饼"}, imgName="月亮", imgPath="moon.png", desc="弯弯的月亮", strokeHint="撇,横折钩,横,横"},
    {id=5, character="云", pinyin="yún", radical="二", strokes=4, groups={"白云","云朵","乌云"}, imgName="云彩", imgPath="cloud.png", desc="软绵绵的白云", strokeHint="横,横,撇折,点"},
    {id=6, character="雨", pinyin="yǔ", radical="雨", strokes=8, groups={"雨水","雨滴","彩虹雨"}, imgName="雨", imgPath="rain.png", desc="下雨啦，滴滴答答", strokeHint="横,竖,横折钩,竖,点,点,点,点"},
    {id=7, character="车", pinyin="chē", radical="车", strokes=4, groups={"汽车","火车","自行车"}, imgName="小汽车", imgPath="car.png", desc="跑得飞快的小汽车", strokeHint="横,撇折,横,竖"},
    {id=8, character="马", pinyin="mǎ", radical="马", strokes=3, groups={"大马","白马","马车"}, imgName="骏马", imgPath="horse.png", desc="马儿奔跑", strokeHint="横折,竖折折钩,横"},
    {id=9, character="鱼", pinyin="yú", radical="鱼", strokes=8, groups={"金鱼","小鱼","鱼缸"}, imgName="小鱼", imgPath="fish.png", desc="游来游去的小鱼", strokeHint="撇,横撇,竖,横折,横,竖,横,横"},
    {id=10, character="鸟", pinyin="niǎo", radical="鸟", strokes=5, groups={"小鸟","鸟儿","飞鸟"}, imgName="小鸟", imgPath="bird.png", desc="叽叽喳喳的小鸟", strokeHint="撇,横折钩,点,竖折折钩,横"},
    {id=11, character="花", pinyin="huā", radical="艹", strokes=7, groups={"花朵","花儿","花园"}, imgName="花朵", imgPath="flower.png", desc="美丽的花朵", strokeHint="横,竖,竖,撇,竖,撇,竖弯钩"},
    {id=12, character="草", pinyin="cǎo", radical="艹", strokes=9, groups={"小草","草地","青草"}, imgName="青草", imgPath="grass.png", desc="绿油油的小草", strokeHint="横,竖,竖,竖,横折,横,横,横,竖"},
    {id=13, character="山", pinyin="shān", radical="山", strokes=3, groups={"大山","高山","山峰"}, imgName="大山", imgPath="mountain.png", desc="高高的山", strokeHint="竖,竖折,竖"},
    {id=14, character="水", pinyin="shuǐ", radical="水", strokes=4, groups={"河水","水滴","喝水"}, imgName="水滴", imgPath="water.png", desc="清澈的水", strokeHint="竖钩,横撇,撇,捺"},
    {id=15, character="火", pinyin="huǒ", radical="火", strokes=4, groups={"火焰","火花","大火"}, imgName="火焰", imgPath="fire.png", desc="温暖的火焰", strokeHint="点,撇,撇,捺"}
}

-- 全局UI元素引用
local ui_elements = {}

local function refresh_ui()
    local data = character_data[current_index]
    
    -- 更新图片
    if ui_elements.main_image then
        local img_path = "/luadb/" .. data.imgPath
        ui_elements.main_image:set_src(img_path)
    end
    
    -- 更新大字
    if ui_elements.char_label then
        ui_elements.char_label:set_text(data.character)
    end
    
    -- 更新拼音
    if ui_elements.pinyin_label then
        ui_elements.pinyin_label:set_text(data.pinyin)
    end
    

    
    -- 更新组词
    if ui_elements.phrase_section then
        -- 清除旧的组词按钮
        if ui_elements.phrase_buttons then
            for _, btn in ipairs(ui_elements.phrase_buttons) do
                btn:destroy()
            end
        end
        ui_elements.phrase_buttons = {}
        
        -- 确保groups存在且至少有3个元素
        if not data.groups then
            data.groups = {"组1", "组2", "组3"}
        elseif #data.groups < 3 then
            -- 如果不够3个，补充到3个
            while #data.groups < 3 do
                table.insert(data.groups, "组" .. (#data.groups + 1))
            end
        end
        
        -- 创建新的组词按钮
        local start_x = 30
        local start_y = 40
        local gap = 10
        local btn_width = 120
        local btn_height = 40
        
        -- 只显示前3个组词
        for i = 1, 3 do
            local group = data.groups[i]
            if group then
                local x = start_x + ((i-1) % 3) * (btn_width + gap)
                local y = start_y + math.floor((i-1) / 3) * (btn_height + gap)
                
                local btn = airui.button({
                    parent = ui_elements.phrase_section,
                    x = x, y = y,
                    w = btn_width, h = btn_height,
                    text = group,
                    font_size = 18,
                    color = 0xC45A1C,
                    bg_color = 0xFFF0E0,
                    radius = 20,
                    border_color = 0xFFDBB5,
                    border_width = 1
                })
                table.insert(ui_elements.phrase_buttons, btn)
            end
        end
    end
    
    -- 更新进度
    if ui_elements.progress_label then
        ui_elements.progress_label:set_text(string.format("%d/%d 快乐识字", current_index, #character_data))
    end
end

local function create_ui()
    -- 主容器
    main_container = airui.container({ 
        parent = airui.screen, 
        x = 0, y = 0, 
        w = 480, h = 800, 
        color = 0xF5E7D3 
    })

    -- 标题栏
    local header = airui.container({ 
        parent = main_container, 
        x = 0, y = 0, 
        w = 480, h = 60, 
        color = 0xFFF3E5 
    })
    
    -- 标题文字
    airui.label({ 
        parent = header, 
        x = 120, y = 15, 
        w = 240, h = 30, 
        align = airui.TEXT_ALIGN_CENTER, 
        text = "看图识字", 
        font_size = 20, 
        color = 0xC26828 
    })
    

    
    -- 内容区域背景
    local content_bg = airui.container({ 
        parent = main_container, 
        x = 0, y = 60, 
        w = 480, h = 740, 
        color = 0xFFFAF2 
    })
    
    local data = character_data[current_index]
    
    -- 主卡片区域（大字 + 拼音）
    local card = airui.container({ 
        parent = content_bg, 
        x = 20, y = 20, 
        w = 440, h = 420, 
        color = 0xFFF9EF,
        radius = 20,
        border_color = 0xFFFFFF,
        border_width = 4,
        shadow_radius = 8,
        shadow_color = 0x000000,
        shadow_offset_x = 0,
        shadow_offset_y = 2
    })
    
    -- 圆形背景
    airui.container({
        parent = card,
        x = 120, y = 40,
        w = 200, h = 200,
        color = 0xFFE8C7,
        radius = 100
    })
    
    -- 图片路径 - 使用luadb路径
    local img_path = "/luadb/" .. data.imgPath
    
    -- 上方大图片
    ui_elements.main_image = airui.image({
        parent = card,
        x = 140, y = 60,
        w = 160, h = 160,
        src = img_path,
        opacity = 255
    })
    
    -- 下方文字显示（图片正下方）
    ui_elements.char_label = airui.label({
        parent = card,
        x = 160, y = 270,
        w = 120, h = 60,
        text = data.character,
        align = airui.TEXT_ALIGN_CENTER,
        font_size = 48,
        color = 0x6B4423
    })
    
    -- 拼音显示（汉字正下方）
    ui_elements.pinyin_label = airui.label({
        parent = card,
        x = 160, y = 320,
        w = 120, h = 40,
        text = data.pinyin,
        align = airui.TEXT_ALIGN_CENTER,
        font_size = 24,
        color = 0xE67E22
    })
    
    -- 组词区域
    ui_elements.phrase_section = airui.container({
        parent = content_bg,
        x = 20, y = 440,
        w = 440, h = 120,
        color = 0xFFFFFF,
        radius = 36,
        border_color = 0xFFEFCF,
        border_width = 1
    })
    
    airui.label({
        parent = ui_elements.phrase_section,
        x = 30, y = 10,
        w = 200, h = 30,
        text = "常用组词",
        align = airui.TEXT_ALIGN_LEFT,
        font_size = 18,
        color = 0xC57128
    })
    
    -- 初始化组词按钮数组
    ui_elements.phrase_buttons = {}
    
    -- 进度指示器
    ui_elements.progress_label = airui.label({
        parent = content_bg,
        x = 240, y = 540,
        w = 200, h = 20,
        text = string.format("%d/%d 快乐识字", current_index, #character_data),
        align = airui.TEXT_ALIGN_CENTER,
        font_size = 15,
        color = 0xC9884A
    })
    
    -- 导航按钮区域
    local nav_area = airui.container({
        parent = content_bg,
        x = 20, y = 570,
        w = 440, h = 50,
        color = 0xFFFAF2
    })
    
    -- 上一个按钮
    airui.button({
        parent = nav_area,
        x = 20, y = 5,
        w = 200, h = 40,
        text = " 上一个",
        font_size = 14,
        color = 0x000000,
        bg_color = 0xFFFFFF,
        radius = 0,
        border_color = 0x0000FF,
        border_width = 2,
        on_click = function()
            if current_index > 1 then
                current_index = current_index - 1
                refresh_ui()
            end
        end
    })
    
    -- 下一个按钮
    airui.button({
        parent = nav_area,
        x = 240, y = 5,
        w = 200, h = 40,
        text = "下一个 ",
        font_size = 14,
        color = 0x000000,
        bg_color = 0xFFFFFF,
        radius = 0,
        border_color = 0x0000FF,
        border_width = 2,
        on_click = function()
            if current_index < #character_data then
                current_index = current_index + 1
                refresh_ui()
            end
        end
    })
    
    -- 退出按钮区域
    local exit_area = airui.container({
        parent = content_bg,
        x = 20, y = 630,
        w = 440, h = 50,
        color = 0xFFFAF2
    })
    
    -- 退出按钮
    airui.button({
        parent = exit_area,
        x = 140, y = 5,
        w = 200, h = 40,
        text = " 退出应用",
        font_size = 14,
        color = 0x000000,
        bg_color = 0xFFFFFF,
        radius = 0,
        border_color = 0x0000FF,
        border_width = 2,
        on_click = function()
            if win_id then
                exwin.close(win_id)
            end
        end
    })
    
    -- 初始化组词按钮
    refresh_ui()
end

local function on_create()
    create_ui()
end

local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    ui_elements = {}
    win_id = nil
    current_index = 1
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    -- 直接打开窗口，不做复杂的状态检查
    -- 窗口的on_create和on_destroy会处理状态管理
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end
sys.subscribe("OPEN_PICTURE_CHARACTER_LEARNING_WIN", open_handler)