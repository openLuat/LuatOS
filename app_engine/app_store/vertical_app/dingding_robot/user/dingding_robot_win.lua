--[[
@module  dingding_robot_win
@summary 钉钉机器人助手主窗口
@version 2.0.0
@date    2026.04.07
@author  马亚丹
]]

-- 窗口ID，用于管理窗口
local win_id = nil
-- 主容器和内容容器
local main_container, content
-- 输入框组件
local webhook_input, message_input
-- 状态标签
local status_label
-- 键盘组件
local keyboard
-- 字符计数标签
local char_count_label

-- 引入配置模块
local config = require("config")
-- 引入消息发送模块
local message = require("message")

-- 更新字符计数
local function update_char_count()
        if message_input and char_count_label then
            local text = message_input:get_text()
            local len = text and #text or 0
            char_count_label:set_text(len .. " / 2000")
            if len > 2000 then
                char_count_label:set_color(0xDC2626)
            else
                char_count_label:set_color(0x7E8B9C)
            end
        end
    end
-- 创建UI界面函数
local function create_ui()
    log.info("dingding_robot", "开始创建UI")

    -- 创建键盘
    keyboard = airui.keyboard({
        mode = "text",
        auto_hide = true,
        preview = true,
        preview_height = 50,
        w = 480,
        h = 150
    })
    log.info("dingding_robot", "键盘创建完成")

    -- 创建主容器，全屏显示
    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = 480,
        h = 800,
        color = 0xF0F4F8
    })
    log.info("dingding_robot", "主容器创建完成")

    -- 创建顶部标题栏（白色）
    local header = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 480,
        h = 90,
        color = 0xFFFFFF
    })
    log.info("dingding_robot", "标题栏创建完成")

    -- 钉钉图标
    airui.image({
        parent = header,
        x = 24,
        y = 18,
        w = 55,
        h = 55,
        src = "/luadb/dingding.png"
    })
    -- 返回按钮
    local back_btn = airui.container({
        parent = header,
        x = 390,
        y = 10,
        w = 80,
        h = 40,
        color = 0x2195F6,
        radius = 5,
        on_click = function() 
            if win_id then 
                exwin.close(win_id) 

            end
        end
    })

    airui.label({
        parent = back_btn,
        x = 10,
        y = 10,
        w = 60,
        h = 24,
        text = "返回",
        font_size = 20,
        color = 0xfefefe,
        align =
            airui.TEXT_ALIGN_CENTER
    })

    -- 主标题
    airui.label({
        parent = header,
        x = 100,
        y = 18,
        w = 300,
        h = 35,
        text = "钉钉机器人",
        font_size = 24,
        color = 0x1A73E8
    })

    -- 副标题
    airui.label({
        parent = header,
        x = 100,
        y = 53,
        w = 200,
        h = 22,
        text = "消息推送工具",
        font_size = 12,
        color = 0x5F6C7A
    })

    -- 徽章（支持 Webhook）
    local badge = airui.container({
        parent = header,
        x = 230,
        y = 51,
        w = 95,
        h = 26,
        color = 0xEEF2FF,
        radius = 13
    })
    airui.label({
        parent = badge,
        x = 0,
        y = 1,
        w = 95,
        h = 24,
        text = "支持 Webhook",
        font_size = 10,
        color = 0x1A73E8,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 创建内容区域容器
    content = airui.container({
        parent = main_container,
        x = 0,
        y = 90,
        w = 480,
        h = 710,
        color = 0xF0F4F8
    })
    log.info("dingding_robot", "内容区域创建完成")

    -- ==================== 机器人配置卡片 ====================
    local config_card = airui.container({
        parent = content,
        x = 24,
        y = 0,
        w = 432,
        h = 330,
        color = 0xF9FAFC,
        radius = 28,
        border_color = 0xEDF2F7,
        border_width = 1
    })

    -- 配置卡片标题区域
    local section_title_container = airui.container({
        parent = config_card,
        x = 0,
        y = 0,
        w = 432,
        h = 50
    })

    -- 扳手图标
    airui.image({
        parent = section_title_container,
        x = 20,
        y = 12,
        w = 32,
        h = 32,
        src = "/luadb/set.png"
    })

    -- 配置标题
    airui.label({
        parent = section_title_container,
        x = 60,
        y = 12,
        w = 200,
        h = 32,
        text = "机器人配置",
        font_size = 16,
        color = 0x1E2A3A
    })
     airui.label({
        parent = section_title_container,
        x = 160,
        y = 12,
        w = 200,
        h = 32,
        text = "获取webhook:钉钉群聊->群设置->群管理->机器人",
        font_size = 10,
        color = 0x1E2A3A
    })

    -- Webhook帮助文字区域
    local helper_container = airui.container({
        parent = config_card,
        x = 20,
        y = 55,
        w = 392,
        h = 30
    })

    -- 图钉图标
    airui.image({
        parent = helper_container,
        x = 0,
        y = 0,
        w = 24,
        h = 24,
        src = "/luadb/zhen.png"
    })

    -- 帮助文字
    airui.label({
        parent = helper_container,
        x = 28,
        y = 7,
        w = 250,
        h = 28,
        text = "钉钉机器人的完整 Webhook 地址",
        font_size = 11,
        color = 0x6C7A8E
    })

    -- 粘贴示例按钮（Webhook）
    local paste_btn_container = airui.container({
        parent = config_card,
        x = 290,
        y = 53,
        w = 122,
        h = 34,
        on_click = function()
            webhook_input:set_text(
                "https://oapi.dingtalk.com/robot/send?access_token=03f4753ec6aa6f0524fb85907c94b17f3fa0fed3107d4e8f4eee1d4a97855f4d")
            status_label:set_text("已填入示例地址，请将access_token替换为真实token")
            log.info("dingding_robot", "已填入Webhook示例地址")
        end
    })
    -- 复制图标
    airui.image({
        parent = paste_btn_container,
        x = 8,
        y = 5,
        w = 24,
        h = 24,
        src = "/luadb/copy.png"
    })
    -- 粘贴示例文字
    airui.label({
        parent = paste_btn_container,
        x = 36,
        y = 11,
        w = 80,
        h = 24,
        text = "粘贴示例格式",
        font_size = 11,
        color = 0x1A73E8
    })

    -- Webhook输入框
    webhook_input = airui.textarea({
        parent = config_card,
        x = 20,
        y = 85,
        w = 392,
        h = 80,
        text = config.getWebhook(),
        placeholder = "https://oapi.dingtalk.com/robot/send?access_token=your_token_here",
        font_size = 14,
        max_len = 512,
        keyboard = keyboard,
        radius = 20,
        bg_color = 0xFFFFFF,
        border_color = 0xE2E8F0,
        border_width = 2
    })
    log.info("dingding_robot", "Webhook输入框创建完成")

    -- 加签输入框
    local secret_input = airui.textarea({
        parent = config_card,
        x = 20,
        y = 216,
        w = 392,
        h = 70,
        text = config.getSecret(),
        placeholder = "SECxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
        font_size = 14,
        max_len = 512,
        keyboard = keyboard,
        radius = 20,
        bg_color = 0xFFFFFF,
        border_color = 0xE2E8F0,
        border_width = 2
    })
    log.info("dingding_robot", "加签输入框创建完成")

    -- 加签帮助文字区域
    local secret_helper_container = airui.container({
        parent = config_card,
        x = 20,
        y = 185,
        w = 392,
        h = 30
    })

    -- 图钉图标
    airui.image({
        parent = secret_helper_container,
        x = 0,
        y = 0,
        w = 24,
        h = 24,
        src = "/luadb/zhen.png"
    })

    -- 加签帮助文字
    airui.label({
        parent = secret_helper_container,
        x = 28,
        y = 7,
        w = 250,
        h = 28,
        text = "钉钉机器人的加签密钥",
        font_size = 11,
        color = 0x6C7A8E
    })

    -- 粘贴示例按钮（加签）
    local paste_secret_btn_container = airui.container({
        parent = config_card,
        x = 290,
        y = 183,
        w = 122,
        h = 34,
        on_click = function()
            secret_input:set_text("SECac5b455d6b567f64073a456e91feec6ad26c0f8f7dcca85dd2ce6c23ea466c52")
            status_label:set_text("已填入示例密钥，请替换为真实密钥")
            log.info("dingding_robot", "已填入加签示例密钥")
        end
    })
    -- 复制图标
    airui.image({
        parent = paste_secret_btn_container,
        x = 8,
        y = 5,
        w = 24,
        h = 24,
        src = "/luadb/copy.png"
    })
    -- 粘贴示例文字
    airui.label({
        parent = paste_secret_btn_container,
        x = 36,
        y = 11,
        w = 80,
        h = 24,
        text = "粘贴示例格式",
        font_size = 11,
        color = 0x1A73E8
    })

    -- 保存配置按钮
    local save_btn_container = airui.container({
        parent = config_card,
        x = 290,
        y = 291,
        w = 122,
        h = 30,
        color = 0xFFFFFF,
        radius = 15,
        border_color = 0xCBD5E1,
        border_width = 1,
        on_click = function()
            -- 获取输入框内容
            local webhook = webhook_input:get_text()
            local secret = secret_input:get_text()
            -- 保存到配置
            config.setWebhook(webhook)
            config.setSecret(secret)
            config.saveConfig()
            -- 更新状态提示
            status_label:set_text("配置已保存")
            log.info("dingding_robot", "配置已保存")
        end
    })
    -- 保存图标
    airui.image({
        parent = save_btn_container,
        x = 12,
        y = 3,
        w = 24,
        h = 24,
        src = "/luadb/save.png"
    })
    -- 保存配置文字
    airui.label({
        parent = save_btn_container,
        x = 40,
        y = 3,
        w = 78,
        h = 24,
        text = "保存配置",
        font_size = 13,
        color = 0x2C3E4E
    })

    -- ==================== 消息内容卡片 ====================
    local message_card = airui.container({
        parent = content,
        x = 24,
        y = 340,
        w = 432,
        h = 220,
        color = 0xF9FAFC,
        radius = 28,
        border_color = 0xEDF2F7,
        border_width = 1
    })

    -- 消息卡片标题区域
    local msg_title_container = airui.container({
        parent = message_card,
        x = 0,
        y = 0,
        w = 432,
        h = 50
    })

    -- 对话框图标
    airui.image({
        parent = msg_title_container,
        x = 20,
        y = 12,
        w = 32,
        h = 32,
        src = "/luadb/emoji_1f4dd_32x32.png"
    })

    -- 消息标题
    airui.label({
        parent = msg_title_container,
        x = 60,
        y = 12,
        w = 200,
        h = 32,
        text = "消息内容",
        font_size = 16,
        color = 0x1E2A3A
    })

    -- 消息输入框
    message_input = airui.textarea({
        parent = message_card,
        x = 20,
        y = 50,
        w = 392,
        h = 130,
        text = config.getMessage(),
        placeholder = "输入要发送给钉钉机器人的消息...\n支持换行，最多2000字符",
        font_size = 15,
        max_len = 2000,
        keyboard = keyboard,
        radius = 24,
        bg_color = 0xFFFFFF,
        border_color = 0xE2E8F0,
        border_width = 2
    })
    log.info("dingding_robot", "消息输入框创建完成")
    
    
    -- 设置文本变化回调
    message_input:set_on_text_change(function()
        update_char_count()
    end)

    -- 字符计数器
    char_count_label = airui.label({
        parent = message_card,
        x = 270,
        y = 190,
        w = 142,
        h = 30,
        text = "0 / 2000",
        font_size = 12,
        color = 0x7E8B9C,
        align = airui.TEXT_ALIGN_RIGHT
    })

    -- ==================== 发送按钮 ====================
    local send_btn_container = airui.container({
        parent = content,
        x = 24,
        y = 575,
        w = 432,
        h = 50,
        color = 0x1A73E8,
        radius = 25,
        on_click = function()
            -- 获取输入框内容
            local webhook = webhook_input:get_text()
            local secret = secret_input:get_text()
            local msg = message_input:get_text()

            -- 验证Webhook地址
            if not webhook or webhook == "" then
                status_label:set_text("请先配置钉钉机器人的Webhook地址")
                log.info("dingding_robot", "请先配置Webhook地址")
                return
            end

            -- 验证消息内容
            if not msg or msg == "" then
                status_label:set_text("消息内容不能为空")
                log.info("dingding_robot", "消息内容不能为空")
                return
            end

            -- 验证消息长度
            if #msg > 2000 then
                status_label:set_text("消息内容超过2000字符限制")
                log.info("dingding_robot", "消息内容超过2000字符限制")
                return
            end

            -- 更新状态提示
            status_label:set_text("发送中...")
            log.info("dingding_robot", "开始发送消息")

            -- 异步发送消息，避免阻塞UI
            sys.taskInit(function()
                local result, errorMsg = message.sendMessage(webhook, secret, msg)
                if result then
                    status_label:set_text("发送成功！钉钉机器人已收到消息")
                    log.info("dingding_robot", "消息发送成功")
                else
                    status_label:set_text("发送失败：" .. (errorMsg or "未知错误"))
                    log.info("dingding_robot", "消息发送失败", errorMsg)
                end
            end)
        end
    })
    -- 发送图标
    airui.image({
        parent = send_btn_container,
        x = 160,
        y = 9,
        w = 32,
        h = 32,
        src = "/luadb/send.png"
    })
    -- 发送按钮文字
    airui.label({
        parent = send_btn_container,
        x = 200,
        y = 12,
        w = 200,
        h = 26,
        text = "发送到钉钉",
        font_size = 16,
        color = 0xFFFFFF
    })

    -- ==================== 状态反馈区域 ====================
    local status_container = airui.container({
        parent = content,
        x = 24,
        y = 635,
        w = 432,
        h = 50,
        color = 0xFFFFFF,
        radius = 24,
        border_left_color = 0x1A73E8,
        border_left_width = 4
    })

    -- 状态标签
    status_label = airui.label({
        parent = status_container,
        x = 16,
        y = 8,
        w = 400,
        h = 34,
        text = "准备就绪，配置好Webhook后即可发送消息。",
        font_size = 13,
        color = 0x2C3E4E
    })
    log.info("dingding_robot", "状态标签创建完成")

    -- ==================== 底部提示 ====================
    local footer_container = airui.container({
        parent = content,
        x = 24,
        y = 705,
        w = 432,
        h = 30
    })

    -- 闪电图标
    airui.image({
        parent = footer_container,
        x = 30,
        y = 3,
        w = 14,
        h = 14,
        src = "/luadb/emoji_26a1_32x32.png"
    })

    -- 注意文字
    airui.label({
        parent = footer_container,
        x = 58,
        y = 3,
        w = 180,
        h = 24,
        text = "注意：网络连接可能影响发送效果",
        font_size = 10,
        color = 0x8A99AA
    })

    -- 灯泡图标
    airui.image({
        parent = footer_container,
        x = 250,
        y = 3,
        w = 14,
        h = 14,
        src = "/luadb/emoji_1f4a1_32x32.png"
    })

    -- 提示文字
    airui.label({
        parent = footer_container,
        x = 278,
        y = 3,
        w = 130,
        h = 24,
        text = "提示：支持保存配置",
        font_size = 10,
        color = 0x8A99AA
    })

    log.info("dingding_robot", "UI创建完成")
end



-- 窗口创建回调
local function on_create()
    log.info("dingding_robot", "窗口创建回调")
    create_ui()
    -- 初始化字符计数
    update_char_count()
end

-- 窗口销毁回调
local function on_destroy()
    log.info("dingding_robot", "窗口销毁回调")
    -- 销毁键盘
    if keyboard then
        keyboard:destroy()
        keyboard = nil
    end
    -- 销毁主容器
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    -- 清空窗口ID
    win_id = nil
    log.info("dingding_robot", "窗口销毁完成")
end

-- 窗口获得焦点回调
local function on_get_focus()
    log.info("dingding_robot", "窗口获得焦点")
    -- 更新字符计数
    update_char_count()
end

-- 窗口失去焦点回调
local function on_lose_focus()
    log.info("dingding_robot", "窗口失去焦点")
end

-- 打开窗口的处理函数
local function open_handler()
    log.info("dingding_robot", "接收到打开窗口消息")
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
    log.info("dingding_robot", "窗口已打开，ID:", win_id)
end

-- 订阅打开窗口的消息
sys.subscribe("OPEN_DINGDING_ROBOT_WIN", open_handler)
log.info("dingding_robot", "已订阅OPEN_DINGDING_ROBOT_WIN消息")
