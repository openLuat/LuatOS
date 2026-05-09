--[[
@module  feishu_msg_win
@summary 飞书机器人助手主窗口
@version 1.0.0
@date    2026.04.14
@author  马亚丹
]]

-- 窗口ID，用于管理窗口
local win_id = nil
-- 主容器和内容容器
local main_container, content
-- 输入框组件
local webhook_input, secret_input, message_input
-- 状态标签
local status_label
-- 键盘组件
local keyboard
-- 字符计数标签
local char_count_label
-- 签名开关状态
local sign_enabled_flag = false

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
            char_count_label:set_color(0x7E8B78)
        end
    end
end

-- 创建UI界面函数
local function create_ui()
    log.info("feishu_msg", "开始创建UI")

    -- 创建主容器，全屏显示，浅绿色主题
    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = 480,
        h = 800,
        color = 0xE6F5E8
    })
    log.info("feishu_msg", "主容器创建完成")

    -- 创建键盘
    keyboard = airui.keyboard({
        parent = main_container,    
        x = 0,
        y = 0,
        mode = "text",
        auto_hide = true,
        preview = true,
        preview_height = 50,
        w = 480,
        h = 180
    })
    log.info("feishu_msg", "键盘创建完成")

    -- 创建顶部标题栏（白色）
    local header = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 480,
        h = 90,
        color = 0xFFFFFF
    })
    log.info("feishu_msg", "标题栏创建完成")

    -- 飞书图标（使用钉钉图标替代，实际需准备飞书图标）
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
        color = 0x43A047,
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
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 主标题
    airui.label({
        parent = header,
        x = 100,
        y = 18,
        w = 300,
        h = 35,
        text = "飞书机器人",
        font_size = 24,
        color = 0x2B7A3E
    })

    -- 副标题
    airui.label({
        parent = header,
        x = 100,
        y = 53,
        w = 200,
        h = 22,
        text = "消息推送助手",
        font_size = 12,
        color = 0x5F6C5E
    })

    -- 徽章（支持 Webhook + 签名）
    local badge = airui.container({
        parent = header,
        x = 230,
        y = 51,
        w = 130,
        h = 26,
        color = 0xE1F3E4,
        radius = 13
    })
    airui.label({
        parent = badge,
        x = 0,
        y = 1,
        w = 130,
        h = 24,
        text = "Webhook + 签名",
        font_size = 10,
        color = 0x2B6E3C,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 创建内容区域容器
    content = airui.container({
        parent = main_container,
        x = 0,
        y = 90,
        w = 480,
        h = 710,
        color = 0xE6F5E8
    })
    log.info("feishu_msg", "内容区域创建完成")

    -- ==================== 机器人配置卡片 ====================
    local config_card = airui.container({
        parent = content,
        x = 24,
        y = 0,
        w = 432,
        h = 380,
        color = 0xFAFDF8,
        radius = 28,
        border_color = 0xE2F0E2,
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
        color = 0x1E3A2A
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
        text = "飞书机器人的完整 Webhook 地址",
        font_size = 11,
        color = 0x6C7A68
    })

    -- 先声明后续需要的变量（注意：不重复声明外部已定义的变量）
    local switch_btn, switch_slider

    -- 粘贴示例按钮（Webhook）
    local paste_btn_container = airui.container({
        parent = config_card,
        x = 290,
        y = 53,
        w = 122,
        h = 34,
        on_click = function()
            webhook_input:set_text("https://open.feishu.cn/open-apis/bot/v2/hook/bb089165-4b73-4f80-9ed0-da0c908b44e5")
            secret_input:set_text("dp9w8i5IZrrZQpLW0bTcI")
            sign_enabled_flag = true
            config.setSignEnabled(true)
            if switch_btn then
                switch_btn:set_color(0x4CAF50)
            end
            if switch_slider then
                switch_slider:set_x(20)
            end
            if secret_input then
                secret_input:set_visible(true)
            end
            if status_label then
                status_label:set_text("已填入示例Webhook和Secret，可直接测试")
            end
            log.info("feishu_msg", "已填入Webhook和Secret示例")
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
        color = 0x2E7D32
    })

    -- Webhook输入框
    webhook_input = airui.textarea({
        parent = config_card,
        x = 20,
        y = 85,
        w = 392,
        h = 70,
        text = config.getWebhook(),
        placeholder = "https://open.feishu.cn/open-apis/bot/v2/hook/xxxxxxxxxx",
        font_size = 14,
        max_len = 512,
        keyboard = keyboard,
        radius = 20,
        bg_color = 0xFFFFFF,
        border_color = 0xD4E2D4,
        border_width = 2
    })
    log.info("feishu_msg", "Webhook输入框创建完成")

    -- 签名配置区域容器
    local signature_area = airui.container({
        parent = config_card,
        x = 20,
        y = 160,
        w = 392,
        h = 150,
        color = 0xFFFFFFD9,
        radius = 20,
        border_color = 0xE2F0E2,
        border_width = 1
    })

    -- 签名开关容器
    local toggle_switch_container = airui.container({
        parent = signature_area,
        x = 12,
        y = 12,
        w = 368,
        h = 30
    })

    -- 开关标签
    airui.label({
        parent = toggle_switch_container,
        x = 0,
        y = 4,
        w = 250,
        h = 22,
        text = "开启签名校验 (加签)",
        font_size = 13,
        color = 0x1F3A2A
    })

    -- 签名开关按钮
    switch_btn = airui.container({
        parent = toggle_switch_container,
        x = 328,
        y = 4,
        w = 40,
        h = 22,
        color = config.getSignEnabled() and 0x4CAF50 or 0xC8E0CA,
        radius = 11,
        on_click = function()
            sign_enabled_flag = not sign_enabled_flag
            config.setSignEnabled(sign_enabled_flag)
            if sign_enabled_flag then
                switch_btn:set_color(0x4CAF50)
                secret_input:set_visible(true)
            else
                switch_btn:set_color(0xC8E0CA)
                secret_input:set_visible(false)
            end
            log.info("feishu_msg", "签名开关已切换:", sign_enabled_flag)
        end
    })

    -- 开关滑块
    switch_slider = airui.container({
        parent = switch_btn,
        x = config.getSignEnabled() and 20 or 2,
        y = 2,
        w = 18,
        h = 18,
        color = 0xFFFFFF,
        radius = 9
    })

    -- 签名密钥输入框
    sign_enabled_flag = config.getSignEnabled()
    secret_input = airui.textarea({
        parent = signature_area,
        x = 12,
        y = 50,
        w = 368,
        h = 55,
        text = config.getSecret(),
        placeholder = "请输入签名密钥 (Secret)",
        font_size = 13,
        max_len = 512,
        keyboard = keyboard,
        radius = 12,
        bg_color = 0xFFFFFF,
        border_color = 0xD4E2D4,
        border_width = 2,
        visible = sign_enabled_flag
    })
    log.info("feishu_msg", "签名密钥输入框创建完成")

    -- 签名提示文字
    local sign_hint_label = airui.label({
        parent = signature_area,
        x = 12,
        y = 112,
        w = 368,
        h = 30,
        text = "根据飞书文档: 若机器人开启签名校验，需要填写Secret。",
        font_size = 10,
        color = 0x6C7A68
    })

    -- 保存配置按钮
    local save_btn_container = airui.container({
        parent = config_card,
        x = 290,
        y = 341,
        w = 122,
        h = 30,
        color = 0xFFFFFF,
        radius = 15,
        border_color = 0xC8DEC8,
        border_width = 1,
        on_click = function()
            local webhook = webhook_input:get_text()
            local secret = secret_input:get_text()
            local msg = message_input:get_text()
            config.setWebhook(webhook)
            config.setSecret(secret)
            config.setMessage(msg)
            config.saveConfig()
            status_label:set_text("配置已保存")
            log.info("feishu_msg", "配置已保存")
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
        color = 0x2E5E2E
    })

    -- ==================== 消息内容卡片 ====================
    local message_card = airui.container({
        parent = content,
        x = 24,
        y = 390,
        w = 432,
        h = 180,
        color = 0xFAFDF8,
        radius = 28,
        border_color = 0xE2F0E2,
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
        color = 0x1E3A2A
    })

    -- 消息输入框
    message_input = airui.textarea({
        parent = message_card,
        x = 20,
        y = 50,
        w = 392,
        h = 100,
        text = config.getMessage(),
        placeholder = "输入要发送给飞书机器人的文本消息...\n支持换行，最多2000字符",
        font_size = 15,
        max_len = 2000,
        keyboard = keyboard,
        radius = 24,
        bg_color = 0xFFFFFF,
        border_color = 0xD4E2D4,
        border_width = 2
    })
    log.info("feishu_msg", "消息输入框创建完成")

    -- 设置文本变化回调
    message_input:set_on_text_change(function()
        update_char_count()
    end)

    -- 字符计数器
    char_count_label = airui.label({
        parent = message_card,
        x = 270,
        y = 155,
        w = 142,
        h = 30,
        text = "0 / 2000",
        font_size = 12,
        color = 0x7E8B78,
        align = airui.TEXT_ALIGN_RIGHT
    })

    -- ==================== 发送按钮 ====================
    local send_btn_container = airui.container({
        parent = content,
        x = 24,
        y = 580,
        w = 432,
        h = 50,
        color = 0x43A047,
        radius = 25,
        on_click = function()
            local webhook = webhook_input:get_text()
            local secret = secret_input:get_text()
            local msg = message_input:get_text()
            local enable_sign = sign_enabled_flag

            if not webhook or webhook == "" then
                status_label:set_text("请先配置飞书机器人的Webhook地址")
                log.info("feishu_msg", "请先配置Webhook地址")
                return
            end

            if not msg or msg == "" then
                status_label:set_text("消息内容不能为空")
                log.info("feishu_msg", "消息内容不能为空")
                return
            end

            if #msg > 2000 then
                status_label:set_text("消息内容超过2000字符限制")
                log.info("feishu_msg", "消息内容超过2000字符限制")
                return
            end

            if enable_sign and (not secret or secret == "") then
                status_label:set_text("已开启签名校验，请填写签名密钥 (Secret)")
                log.info("feishu_msg", "已开启签名校验，请填写签名密钥")
                return
            end

            status_label:set_text("发送中...")
            log.info("feishu_msg", "开始发送消息")

            sys.taskInit(function()
                local result, errorMsg = message.sendMessage(webhook, secret, enable_sign, msg)
                if result then
                    status_label:set_text("发送成功！飞书机器人已收到消息")
                    log.info("feishu_msg", "消息发送成功")
                else
                    status_label:set_text("发送失败：" .. (errorMsg or "未知错误"))
                    log.info("feishu_msg", "消息发送失败", errorMsg)
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
        text = "发送到飞书",
        font_size = 16,
        color = 0xFFFFFF
    })

    -- ==================== 状态反馈区域 ====================
    local status_container = airui.container({
        parent = content,
        x = 24,
        y = 640,
        w = 432,
        h = 50,
        color = 0xFFFFFF,
        radius = 24,
        border_left_color = 0x4CAF50,
        border_left_width = 4
    })

    -- 状态标签
    status_label = airui.label({
        parent = status_container,
        x = 16,
        y = 8,
        w = 400,
        h = 34,
        text = "准备就绪，配置好Webhook后即可发送消息 (支持签名自动生成)。",
        font_size = 13,
        color = 0x2C3E2C
    })
    log.info("feishu_msg", "状态标签创建完成")

    -- ==================== 底部提示 ====================
    local footer_container = airui.container({
        parent = content,
        x = 24,
        y = 700,
        w = 432,
        h = 30
    })

    -- 闪电图标
    airui.image({
        parent = footer_container,
        x = 20,
        y = 3,
        w = 14,
        h = 14,
        src = "/luadb/emoji_26a1_32x32.png"
    })

    -- 注意文字
    airui.label({
        parent = footer_container,
        x = 44,
        y = 3,
        w = 190,
        h = 24,
        text = "网络连接可能影响发送效果",
        font_size = 10,
        color = 0x8AA38A
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
        x = 274,
        y = 3,
        w = 130,
        h = 24,
        text = "支持保存配置到本地",
        font_size = 10,
        color = 0x8AA38A
    })

    log.info("feishu_msg", "UI创建完成")
end

-- 窗口创建回调
local function on_create()
    log.info("feishu_msg", "窗口创建回调")
    -- 启用系统物理键盘（PC模拟器专用，方便调试）
    airui.keyboard_enable_system(true)
    create_ui()
    -- 初始化字符计数
    update_char_count()
end

-- 窗口销毁回调
local function on_destroy()
    log.info("feishu_msg", "窗口销毁回调")
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
    log.info("feishu_msg", "窗口销毁完成")
end

-- 窗口获得焦点回调
local function on_get_focus()
    log.info("feishu_msg", "窗口获得焦点")
    -- 更新字符计数
    update_char_count()
end

-- 窗口失去焦点回调
local function on_lose_focus()
    log.info("feishu_msg", "窗口失去焦点")
end

-- 打开窗口的处理函数
local function open_handler()
    log.info("feishu_msg", "接收到打开窗口消息")
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
    log.info("feishu_msg", "窗口已打开，ID:", win_id)
end

-- 订阅打开窗口的消息
sys.subscribe("OPEN_FEISHU_MSG_WIN", open_handler)
log.info("feishu_msg", "已订阅OPEN_FEISHU_MSG_WIN消息")
