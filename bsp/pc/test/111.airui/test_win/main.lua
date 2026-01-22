-- Win 组件测试脚本
PROJECT = "airui"
VERSION = "1.0.0"

sys.taskInit(function()
    -- 1. 初始化 AIRUI
    -- airui.init(w, h, buff_size, buff_mode)
    -- w: 屏幕宽,可选,默认480
    -- h: 屏幕高,可选,默认320
    -- color_format: 颜色格式,可选,默认ARGB8888
    --                   可用值：airui.COLOR_FORMAT_RGB565（默认,嵌入式，节省内存）
    --                          airui.COLOR_FORMAT_ARGB8888（pc，高质量）
    local ret = airui.init(800, 600, airui.COLOR_FORMAT_ARGB8888)
    if not ret then
        log.error("airui", "init failed")
        return
    end

    -- 窗口组件
    local win = airui.win({
        parent = airui.screen,
        title = "Settings", -- 标题文本，可选
        x = 40, y = 40, w = 600, h = 400, -- x, y, w, h
        close_btn = false, -- 是否显示关闭按钮，默认 false
        auto_center = false, -- 是否自动居中，默认 true
        on_close = function(self) -- 关闭回调
            log.info("airui.win", "win:on_close called")
        end
    })

    --label
    local label = airui.label({
        text = "win test",
        x = 0, y = 0, w = 120, h = 40,
    })

    -- 下拉框组件
    local dropdown = airui.dropdown({
        options = {"Option A", "Option B", "Option C"}, -- 选项列表（字符串数组）
        default_index = 2, -- 默认选中项索引，默认 -1
        x = 0, y = 40, w = 180, h = 50,
        on_change = function(self, index) -- 选中项变化回调
            log.info("dropdown", "selected index", index)
        end
    })

    -- 不可点击图片
    local img = airui.image({
        src = "/luadb/logo.png",
        x = 0, y = 240, w = 80, h = 80,
        zoom = 256, -- 缩放比例，默认 256（100%）
        opacity = 255, -- 透明度，默认 255（不透明），范围 0-255
    })

    --先创建按钮（不指定 parent，默认添加到屏幕）
    local inner_btn = airui.button({
        text = "Close",
        x = 0, y = 340, w = 120, h = 40,
        on_click = function(self)
            log.info("airui.win", "inner button closing window")
            win:close()
        end
    })

    -- 将按钮添加到窗口内容区域
    win:add_content(inner_btn)
    win:add_content(label)
    win:add_content(dropdown)
    win:add_content(img)
    -- 设置窗口标题
    win:set_title("Settings Window")

    while true do
        airui.refresh()
        sys.wait(10)
    end

end)

sys.run()

