local home = {}

local obj_list = nil--存放新建的对象
local selected = 1--当前选中的按钮

--显示这一页内容
function home.show()
    local theme_btn = lvgl.btn_create(scr)
    lvgl.obj_set_size(theme_btn,70,46)
    lvgl.obj_set_x(theme_btn,5)
    lvgl.obj_set_y(theme_btn,-50)
    local theme_label = lvgl.label_create(theme_btn)
    lvgl.label_set_text(theme_label, "theme")

    local game_btn = lvgl.btn_create(scr)
    lvgl.obj_set_size(game_btn,70,46)
    lvgl.obj_set_x(game_btn,5)
    lvgl.obj_set_y(game_btn,-50)
    local game_label = lvgl.label_create(game_btn)
    lvgl.label_set_text(game_label, "reboot")

    local about_btn = lvgl.btn_create(scr)
    lvgl.obj_set_size(about_btn,70,46)
    lvgl.obj_set_x(about_btn,5)
    lvgl.obj_set_y(about_btn,-50)
    local about_label = lvgl.label_create(about_btn)
    lvgl.label_set_text(about_label, "about")

    if not obj_list then--新建的对象存起来，给以后销毁用
        obj_list = {--按顺序存，偶数下标为按钮对象
            theme_label,
            theme_btn,
            game_label,
            game_btn,
            about_label,
            about_btn,
        }
    end

    home.selectChange()--显示一下现在按下的按键

    --来个动画
    animation.once(theme_btn,lvgl.obj_set_y,-50,5,nil,900)
    animation.once(game_btn,lvgl.obj_set_y,-50,56,nil,700)
    animation.once(about_btn,lvgl.obj_set_y,-50,109,nil,500)
end

--卸载掉该页面
function home.unload()
    if not obj_list then return end
    for i=1,#obj_list do
        lvgl.obj_del(obj_list[i])
    end
    obj_list = nil
end

--更改选中的按钮
function home.selectChange(n)
    if not n then n = 0 end
    --还没显示呢
    if not obj_list then home.show() end
    --现在选了哪个？
    selected = selected + n
    if selected > 3 then selected = 1 end
    if selected < 1 then selected = 3 end
    --设置每个按钮的状态
    for i=2,#obj_list,2 do
        if i/2 == selected then
            lvgl.btn_set_state(obj_list[i],lvgl.BTN_STATE_PRESSED)
        else
            lvgl.btn_set_state(obj_list[i],lvgl.BTN_STATE_RELEASED)
        end
    end
end

--主题控制和切换
local themes = {"material_light","material_dark"}
local themeNow = 1
function home.changeTheme()
    themeNow = themeNow + 1
    if themeNow > #themes then themeNow = 1 end
    lvgl.theme_set_act(themes[themeNow])
end

--事件列表
local keyList = {
    U = function ()
        home.selectChange(-1)
    end,
    D = function ()
        home.selectChange(1)
    end,
    O = function ()
        --todo
        if selected == 1 then
            home.changeTheme()
        elseif selected == 2 then
            rtos.reboot()
        elseif selected == 3 then
            home.unload()
            about.show()
            key.setCb(about.keyCb)
        end
    end,
}
keyList.L = keyList.U
keyList.R = keyList.D

--按键处理事件
function home.keyCb(k)
    if keyList[k] then keyList[k]() end
end


return home
