-- lua - 开机画面

local win_id = nil
local main_container

-- 创建 UI：全屏显示一张图片或纯色背景+文字
local function create_ui()
    -- 使用全屏容器，背景色可自定义（例如 0x3F51B5 与状态栏颜色一致）
    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = 480,
        h = 320,
        color = 0x3F51B5 -- 深蓝色背景
    })

    -- 尝试加载开机图片，若不存在则显示文字
    -- local welcome_img_path = "/luadb/idle.png"  -- 请将开机图片放在此路径
    -- local img = airui.image({
    --     parent = main_container,
    --     x = 0, y = 0, w = 480, h = 320,
    --     src = welcome_img_path
    -- })
    -- 如果图片加载失败（例如文件不存在），airui.image 可能不会报错，但会显示空白。
    -- 为了更健壮，可以添加一个后备文字标签（叠加在图片上方或单独显示）
    -- 这里简单起见，再添加一个居中文字标签，即使图片存在也会被覆盖，但无妨
    airui.label({
        parent = main_container,
        x = 0,
        y = 140,
        w = 480,
        h = 40,
        text = "欢迎使用合宙turnkey开发板",
        font_size = 24,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })
end

-- 定时器回调：打开首页并关闭自己
local function on_welcome_timeout()
    -- 然后关闭开机画面窗口
    if win_id then
        exwin.close(win_id)
    end
    -- 先发布打开首页的消息（home_win 订阅了 OPEN_HOME_win）
    sys.publish("OPEN_IDLE_WIN")
end

local function on_create()
    create_ui()
    -- 启动一个定时器，1秒后切换到首页（可根据实际需要调整时间）
    sys.timerStart(on_welcome_timeout, 1000)
end

local function on_destroy()
    sys.timerStop(on_welcome_timeout)
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    win_id = nil
end

-- 可选：获得焦点/失去焦点时不做特殊处理
local function on_get_focus() end

local function on_lose_focus() end

-- 订阅打开开机画面的消息
local function open_welcome_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end
sys.subscribe("OPEN_WELCOME_WIN", open_welcome_handler)