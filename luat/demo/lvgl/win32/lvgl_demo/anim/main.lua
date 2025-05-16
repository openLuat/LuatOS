sys = require("sys")

log.info("sys", "from win32")

sys.taskInit(function()
    log.info("lvgl", lvgl.init(480, 320))
    -- gui.setup_ui()

    -- local scr = lvgl.obj_create()
    local btn = lvgl.btn_create(lvgl.scr_act())
    lvgl.obj_set_x(btn, 10)
    lvgl.obj_set_y(btn, 100)
    -- lvgl.btn_set_title("Hi, LuatOS-Soc")

    local anim = lvgl.anim_create()
    lvgl.anim_set_var(anim, btn)
    -- 注意, 这个方法需要3个参数, 第3个参数可以是自定义function(obj, val)
    lvgl.anim_set_exec_cb(anim, lvgl.obj_set_x)
    -- lvgl.anim_set_exec_cb(anim, function(obj, val)
    --    lvgl.obj_set_x(obj, val)
    -- end)

    lvgl.anim_set_values(anim, 10, 240);

    while true do -- 为了演示,这里把对象还原到默认位置,然后重新开始动画
        sys.wait(5000)
        lvgl.obj_set_x(btn, 10)
        lvgl.anim_start(anim)
    end

    lvgl.anim_free(anim) -- 与C不同, 这里的anim需要主动释放
end)

sys.run()
