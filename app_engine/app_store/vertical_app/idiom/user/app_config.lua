-- 应用配置
local config = {
    SCREEN = {
        WIDTH = 480,
        HEIGHT = 800
    },
    LAYOUT = {
        TITLE_HEIGHT = 60,
        CARD_WIDTH = 400,
        CARD_HEIGHT = 200,  -- 改为200px
        CARD_Y = 160,
        CARD_RADIUS = 10,
        OPTIONS_WIDTH = 400,
        OPTIONS_HEIGHT = 200,
        OPTIONS_Y = 380,  -- 调整选项区域位置
        PANEL_RADIUS = 10,
        MESSAGE_Y = 600,  -- 调整消息区域位置
        MESSAGE_HEIGHT = 50,
        BUTTON_WIDTH = 120,
        BUTTON_HEIGHT = 50,
        BUTTON_Y = 670,  -- 调整底部按钮位置
        BUTTON_RADIUS = 10
    },
    COLORS = {
        BG = 0x1A1F2F,
        TITLE_BAR = 0x2C3E50,
        CARD_BG = 0x34495E,
        BUTTON = 0x4CAF50,  -- 浅绿色
        TEXT_PRIMARY = 0xFFFFFF,
        TEXT_TITLE = 0xF9D371,
        TEXT_ACCENT = 0x3498DB
    },
    FONT = {
        TITLE_SIZE = 24,
        IDIOM_SIZE = 60,
        BUTTON_SIZE = 20,
        MESSAGE_SIZE = 18
    },
    GAME = {
        GROUP_SIZE = 10,
        SCORE_PER_CORRECT = 10,
        DELAY_NEXT = 1000
    }
}

return config