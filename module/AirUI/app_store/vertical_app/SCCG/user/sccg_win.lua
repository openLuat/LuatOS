--[[
@module  sccg_win
@summary 诗词闯关游戏窗口模块
@version 1.0
@date    2026.04.10
@author  LuatOS
]]

local win_id = nil
local main_container,menuContent
local currentPage = "menu"
local currentLevelIndex = 0
local totalScore = 0
local currentSelectedOption = nil
local hasAnsweredCurrent = false
local isLevelCompleted = false

-- 诗词题库
local levelsData = {
    {
        id = 0,
        poemSnippet = "床前____光，疑是地上霜。",
        correctAnswer = "明月",
        options = {"明月", "月光", "灯光", "烛光"},
        explanation = "李白《静夜思》经典名句。"
    },
    {
        id = 1,
        poemSnippet = "欲穷____目，更上一层楼。",
        correctAnswer = "千里",
        options = {"万里", "千里", "百尺", "千山"},
        explanation = "王之涣《登鹳雀楼》气势磅礴。"
    },
    {
        id = 2,
        poemSnippet = "野火烧____，春风吹又生。",
        correctAnswer = "不尽",
        options = {"不尽", "不灭", "未绝", "无痕"},
        explanation = "白居易《赋得古原草送别》坚韧意象。"
    },
    {
        id = 3,
        poemSnippet = "独在异乡为异客，每逢____倍思亲。",
        correctAnswer = "佳节",
        options = {"节日", "重阳", "佳节", "良辰"},
        explanation = "王维《九月九日忆山东兄弟》思乡情深。"
    },
    {
        id = 4,
        poemSnippet = "黄沙百战穿金甲，不破____终不还。",
        correctAnswer = "楼兰",
        options = {"楼兰", "玉门", "阴山", "天山"},
        explanation = "王昌龄《从军行》壮怀激烈。"
    },
    {
        id = 5,
        poemSnippet = "春风又绿____岸，明月何时照我还。",
        correctAnswer = "江南",
        options = {"江南", "江左", "江东", "江畔"},
        explanation = "王安石《泊船瓜洲》千古绝唱。"
    }
}

-- 函数前向声明
local createGamePage, createMenuPage

-- 退出应用
local function exitApp()
    if win_id then
        exwin.close(win_id)
    end
end

-- 获取当前关卡数据
local function getCurrentLevelData()
    if currentLevelIndex < #levelsData then
        return levelsData[currentLevelIndex + 1]
    end
    return nil
end

-- 创建主菜单页面
createMenuPage = function()
    log.info("sccg_win", "createMenuPage called, main_container:", main_container)
    if not main_container then 
        log.info("sccg_win", "main_container is nil, returning")
        return 
    end
    
    -- 头部导航栏
    log.info("sccg_win", "creating header container")
    local header = airui.container({
        parent = main_container,
        x = 0, y = 0, w = 480, h = 80,
        color = 0xfef7e8
    })
    log.info("sccg_win", "header created:", header)
    
    -- 标题容器
    log.info("sccg_win", "creating title container")
    local titleContainer = airui.container({
        parent = header,
        x = 160, y = 18, w = 160, h = 50,
        color = 0xFDF0E0,
        radius = 30
    })
    log.info("sccg_win", "title container created")
    
    -- 标题
    log.info("sccg_win", "creating title label")
    airui.label({
        parent = titleContainer,
        x = 0, y = 10, w = 160, h = 40,
        text = "诗 词 闯 关",
        font_size = 22,
        color = 0x6b4c3b,
        align = airui.TEXT_ALIGN_CENTER,
        font_bold = true
    })
    log.info("sccg_win", "title label created")
    
    -- 标题下划线
    log.info("sccg_win", "creating title underline")
    airui.container({
        parent = header,
        x = 0, y = 68, w = 480, h = 2,
        color = 0x000000
    })
    log.info("sccg_win", "title underline created")
    
    -- 退出按钮
    log.info("sccg_win", "creating exit button")
    airui.button({
        parent = header,
        x = 416, y = 18, w = 44, h = 44,
        text = "X",
        font_size = 24,
        text_color = 0x5e4b3c,
        style = {
            bg_color = 0xe9e0d0,
            radius = 40,
            border_width = 0,
        },
        on_click = function()
            exitApp()
        end
    })
    log.info("sccg_win", "exit button created")
    
    -- 菜单内容
    log.info("sccg_win", "creating menuContent container")
    local menuContent = airui.container({
        parent = main_container,
        x = 0, y = 80, w = 480, h = 720,
        color = 0xfef7e8
    })
    log.info("sccg_win", "menuContent created:", menuContent)
    
    -- Logo 图片
    log.info("sccg_win", "creating logo image")
    airui.image({
        parent = menuContent,
        x = 80, y = 150, w = 200, h = 100,
        src = "/luadb/jiangbei.png"
    })
    log.info("sccg_win", "logo image created")
    
    -- 卷轴图片
    log.info("sccg_win", "creating scroll image")
    airui.image({
        parent = menuContent,
        x = 170, y = 155, w = 200, h = 100,
        src = "/luadb/shujuan.png"
    })
    log.info("sccg_win", "scroll image created")
    
    -- 描述容器
    log.info("sccg_win", "creating description container")
    local descriptionContainer = airui.container({
        parent = menuContent,
        x = 80, y = 270, w = 300, h = 60,
        color = 0xFDF0E0,
        radius = 30
    })
    log.info("sccg_win", "description container created")
    
    -- 描述
    log.info("sccg_win", "creating description label")
    airui.label({
        parent = descriptionContainer,
        x = 0, y = 20, w = 300, h = 40,
        text = "过关斩句  步步生花",
        font_size = 18,
        color = 0x8e735b,
        align = airui.TEXT_ALIGN_CENTER
    })
    log.info("sccg_win", "description label created")
    
    -- 开始按钮
    log.info("sccg_win", "creating start button")
    airui.button({
        parent = menuContent,
        x = 140, y = 400, w = 200, h = 60,
        text = "开始闯关",
        font_size = 22,
        text_color = 0xffffff,
        style = {
            bg_color = 0xb48c5c,
            radius = 60,
            border_width = 0,
        },
        on_click = function()
            currentLevelIndex = 0
            totalScore = 0
            currentSelectedOption = nil
            hasAnsweredCurrent = false
            isLevelCompleted = false
            currentPage = "game"
            createGamePage()
        end
    })
    log.info("sccg_win", "start button created")
    
    -- 底部说明
    log.info("sccg_win", "creating bottom label")
    airui.label({
        parent = menuContent,
        x = 0, y = 500, w = 480, h = 30,
        text = " 每关一题   答对晋级   累计积分 ",
        font_size = 12,
        color = 0xcbbca7,
        align = airui.TEXT_ALIGN_CENTER
    })
    log.info("sccg_win", "bottom label created")
    log.info("sccg_win", "createMenuPage completed")
end

-- 创建游戏页面
createGamePage = function()
    log.info("sccg_win", "createGamePage called, main_container:", main_container)
    if not main_container then 
        log.info("sccg_win", "main_container is nil, returning")
        return 
    end
    
    -- 清空主容器
    -- main_container:removeAllChildren()
    
    -- 头部导航栏
    log.info("sccg_win", "creating header container")
    local header = airui.container({
        parent = main_container,
        x = 0, y = 0, w = 480, h = 80,
        color = 0xfef7e8
    })
    log.info("sccg_win", "header created:", header)
    
    -- 返回按钮
    log.info("sccg_win", "creating back button")
    airui.button({
        parent = header,
        x = 20, y = 18, w = 44, h = 44,
        text = "←",
        font_size = 24,
        text_color = 0x5e4b3c,
        style = {
            bg_color = 0xe9e0d0,
            radius = 40,
            border_width = 0,
        },
        on_click = function()
            currentLevelIndex = 0
            totalScore = 0
            currentSelectedOption = nil
            hasAnsweredCurrent = false
            isLevelCompleted = false
            currentPage = "menu"
            createMenuPage()
        end
    })
    log.info("sccg_win", "back button created")
    
    -- 标题容器
    log.info("sccg_win", "creating title container")
    local titleContainer = airui.container({
        parent = header,
        x = 160, y = 18, w = 160, h = 50,
        color = 0xFDF0E0,
        radius = 30
    })
    log.info("sccg_win", "title container created")
    
    -- 标题
    log.info("sccg_win", "creating title label")
    airui.label({
        parent = titleContainer,
        x = 0, y = 10, w = 160, h = 40,
        text = "过 关 模 式",
        font_size = 22,
        color = 0x6b4c3b,
        align = airui.TEXT_ALIGN_CENTER,
        font_bold = true
    })
    log.info("sccg_win", "title label created")
    
    -- 标题下划线
    log.info("sccg_win", "creating title underline")
    airui.container({
        parent = header,
        x = 0, y = 68, w = 480, h = 2,
        color = 0xCCCCCC
    })
    log.info("sccg_win", "title underline created")
    
    -- 退出按钮
    log.info("sccg_win", "creating exit button")
    airui.button({
        parent = header,
        x = 416, y = 18, w = 40, h = 40,
        text = "X",
        font_size = 24,
        text_color = 0x5e4b3c,
        style = {
            bg_color = 0xe9e0d0,
            radius = 40,
            border_width = 0,
        },
        on_click = function()
            exitApp()
        end
    })
    log.info("sccg_win", "exit button created")
    
    -- 游戏容器
    log.info("sccg_win", "creating game container")
    local gameContainer = airui.container({
        parent = main_container,
        x = 0, y = 80, w = 480, h = 640,
        color = 0xfef7e8
    })
    log.info("sccg_win", "game container created:", gameContainer)
    
    local levelData = getCurrentLevelData()
    if not levelData then
        -- 通关完成界面
        log.info("sccg_win", "creating complete panel")
        local completePanel = airui.container({
            parent = gameContainer,
            x = 20, y = 40, w = 440, h = 300,
            color = 0xfffff0,
            radius = 60
        })
        
        -- 通关标题
        airui.label({
            parent = completePanel,
            x = 0, y = 30, w = 440, h = 40,
            text = "通关成功",
            font_size = 28,
            color = 0xb48c5c,
            align = airui.TEXT_ALIGN_CENTER
        })
        
        -- 通关描述
        airui.label({
            parent = completePanel,
            x = 0, y = 80, w = 440, h = 60,
            text = "恭喜你成功闯过所有关卡！\n你的总积分为：" .. totalScore .. " 分",
            font_size = 18,
            color = 0x6b4c3b,
            align = airui.TEXT_ALIGN_CENTER
        })
        
        -- 退出应用按钮
        airui.button({
            parent = completePanel,
            x = 45, y = 150, w = 350, h = 50,
            text = "退出应用",
            font_size = 18,
            text_color = 0xffffff,
            style = {
                bg_color = 0xb48c5c,
                radius = 60,
                border_width = 0,
            },
            on_click = function()
                exitApp()
            end
        })
        
        -- 返回主菜单按钮
        airui.button({
            parent = completePanel,
            x = 45, y = 210, w = 350, h = 50,
            text = "返回主菜单",
            font_size = 18,
            text_color = 0xffffff,
            style = {
                bg_color = 0xaa8f70,
                radius = 60,
                border_width = 0,
            },
            on_click = function()
                currentLevelIndex = 0
                totalScore = 0
                currentSelectedOption = nil
                hasAnsweredCurrent = false
                isLevelCompleted = false
                currentPage = "menu"
                createMenuPage()
            end
        })
        
        log.info("sccg_win", "complete panel created")
        return
    end
    
    -- 进度区域
    log.info("sccg_win", "creating progress area")
    local progressArea = airui.container({
        parent = gameContainer,
        x = 0, y = 10, w = 480, h = 50,
        color = 0xfef7e8
    })
    
    -- 关卡信息容器
    local levelInfoContainer = airui.container({
        parent = progressArea,
        x = 50, y = 10, w = 120, h = 30,
        color = 0xC9B38C,
        radius = 30
    })
    
    -- 关卡信息
    airui.label({
        parent = levelInfoContainer,
        x = 0, y = 5, w = 110, h = 20,
        text = "关卡 " .. (currentLevelIndex + 1) .. "/" .. #levelsData,
        font_size = 16,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER,
        font_bold = true
    })
    
    -- 分数显示容器
    local scoreContainer = airui.container({
        parent = progressArea,
        x = 300, y = 10, w = 120, h = 30,
        color = 0xF7EEDD,
        radius = 30
    })
    
    -- 积分图标
    airui.image({
        parent = scoreContainer,
        x = 20, y = 3, w = 20, h = 20,
        src = "/luadb/jf.png"
    })
    
    -- 分数显示
    airui.label({
        parent = scoreContainer,
        x = 40, y = 5, w = 75, h = 20,
        text = "积分:" .. totalScore,
        font_size = 16,
        color = 0x5a3f2e,
        align = airui.TEXT_ALIGN_CENTER,
        font_bold = true
    })
    
    -- 题目和选项容器
    log.info("sccg_win", "creating question and options container")
    local questionOptionsContainer = airui.container({
        parent = gameContainer,
        x = 30, y = 70, w = 420, h = 400,
        color = 0xFFFAF0,
        radius = 30
    })
    
    -- 题目内容
    local displaySnippet = levelData.poemSnippet
    if hasAnsweredCurrent then
        displaySnippet = string.gsub(displaySnippet, "____", levelData.correctAnswer)
    end
    
    airui.label({
        parent = questionOptionsContainer,
        x = 20, y = 30, w = 380, h = 80,
        text = displaySnippet,
        font_size = 25,
        color = 0x5a3f2e,
        align = airui.TEXT_ALIGN_CENTER,
        font_bold = true
    })
    
    -- 选项区域
    log.info("sccg_win", "creating options area")
    local optionY = 140
    for i, option in ipairs(levelData.options) do
        local isSelected = (currentSelectedOption == option)
        local optionColor = isSelected and 0xb48c5c or 0xf2e8d0
        local textColor = isSelected and 0xffffff or 0x6b4c3b
        
        airui.button({
            parent = questionOptionsContainer,
            x = 30, y = optionY, w = 360, h = 45,
            text = option,
            font_size = 20,
            text_color = textColor,
            style = {
                bg_color = optionColor,
                radius = 20,
                border_width = 0,
            },
            on_click = function()
                if not hasAnsweredCurrent then
                    currentSelectedOption = option
                    hasAnsweredCurrent = true
                    isLevelCompleted = (option == levelData.correctAnswer)
                    
                    if isLevelCompleted then
                        totalScore = totalScore + 10
                        -- 重新创建游戏页面以更新显示，显示反馈内容
                        createGamePage()
                        -- 延迟进入下一关
                        sys.timerStart(function()
                            currentLevelIndex = currentLevelIndex + 1
                            -- 重置状态，准备进入下一关
                            hasAnsweredCurrent = false
                            currentSelectedOption = nil
                            -- 进入下一关
                            createGamePage()
                        end, 1500)
                        return
                    end
                    
                    -- 重新创建游戏页面以更新显示
                    createGamePage()
                end
            end
        })
        
        optionY = optionY + 50
    end
    
    -- 反馈区域
    log.info("sccg_win", "creating feedback area")
    local feedbackText = "选择正确的词语填空"
    local feedbackColor = 0x6b5a4a
    local feedbackBgColor = 0xf1ebdf
    
    if hasAnsweredCurrent then
        if isLevelCompleted then
            feedbackText = "漂亮！答对了！"
            feedbackColor = 0x2f6b3c
            feedbackBgColor = 0xe0f0e3
        else
            feedbackText = "很遗憾，\"" .. (currentSelectedOption or "你的答案") .. "\"不正确。正确答案是\"" .. levelData.correctAnswer .. "\"。"
            feedbackColor = 0xbc5a4c
            feedbackBgColor = 0xffe6e5
        end
    end
    
    -- 反馈区域圆角容器
    local feedbackContainer = airui.container({
        parent = gameContainer,
        x = 20, y = 490, w = 440, h = 50,
        color =0xE6E2D3,
        radius = 30
    })
    
    -- 左侧图片
    if not hasAnsweredCurrent then
        airui.image({
            parent = feedbackContainer,
            x = 55, y = 15, w = 20, h = 20,
            src = "/luadb/xx.png"
        })
    end
    
    airui.label({
        parent = feedbackContainer,
        x = 70, y = 20, w = 300, h = 30,
        text = feedbackText,
        font_size = 15,
        color = feedbackColor,
        align = airui.TEXT_ALIGN_CENTER,
        style = {
            bg_color = feedbackBgColor,
            radius = 20,
        }
    })
    
    -- 右侧图片
    if not hasAnsweredCurrent then
        airui.image({
            parent = feedbackContainer,
            x = 355, y = 15, w = 20, h = 20,
            src = "/luadb/xx.png"
        })
    end
    log.info("sccg_win", "feedback area created, feedbackText:", feedbackText)
    
    -- 提示按钮
    log.info("sccg_win", "creating hint button")
    airui.button({
        parent = gameContainer,
        x = 180, y = 550, w = 105, h = 40,
        text = "提示",
        font_size = 16,
        text_color = 0xffffff,
        style = {
            bg_color = 0xaa8f70,
            radius = 20,
            border_width = 0,
        },
        on_click = function()
            local hintText = "提示：" .. levelData.explanation
            
            airui.label({
                parent = gameContainer,
                x = 20, y = 595, w = 440, h = 40,
                text = hintText,
                font_size = 14,
                color = 0x5a3f2e,
                align = airui.TEXT_ALIGN_CENTER,
                style = {
                    bg_color = 0xf1ebdf,
                    radius = 30,
                }
            })
            log.info("sccg_win", "hint button clicked, hint text:", hintText)
        end
    })
    
    log.info("sccg_win", "createGamePage completed")
end

-- 窗口创建回调
local function on_create()
    log.info("sccg_win", "on_create called")
    log.info("sccg_win", "airui:", airui)
    log.info("sccg_win", "airui.screen:", airui.screen)
    
    main_container = airui.container({
        parent = airui.screen,
        x = 0, y = 0, w = 480, h = 800,
        color = 0xfef7e8,
        scrollable = false
    })
    
    log.info("sccg_win", "main_container created:", main_container)
    
    -- 显示主菜单
    log.info("sccg_win", "calling createMenuPage")
    createMenuPage()
    log.info("sccg_win", "createMenuPage completed")
end

-- 窗口销毁回调
local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    
    win_id = nil
    currentPage = "menu"
    currentLevelIndex = 0
    totalScore = 0
    currentSelectedOption = nil
    hasAnsweredCurrent = false
    isLevelCompleted = false
end

-- 窗口获得焦点回调
local function on_get_focus()
end

-- 窗口失去焦点回调
local function on_lose_focus()
end

-- 打开窗口
local function open_handler()
    log.info("sccg_win", "open_handler called")
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
    log.info("sccg_win", "window created, win_id:", win_id)
end

log.info("sccg_win", "module loaded, subscribing to OPEN_SCCG_WIN")
sys.subscribe("OPEN_SCCG_WIN", open_handler)