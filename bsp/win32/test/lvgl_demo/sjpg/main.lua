local sys = require ("sys")


sys.taskInit(function()
    sys.wait(500)
    lvgl.init()

    local img1 = lvgl.img_create(lvgl.scr_act())
    local img2 = lvgl.img_create(lvgl.scr_act())

    -- jpg from file
    lvgl.img_set_src(img1, "/wallpaper.jpg")
    lvgl.img_set_src(img2, "/wallpaper.sjpg")

    lvgl.obj_set_x(img2, 100)
    lvgl.obj_set_y(img2, 100)

end)


sys.run()
