local sys = require ("sys")


sys.taskInit(function()
    sys.wait(500)

    fatfs.debug(1)
    fatfs.mount("ram", 128*1024)
    fatfs.mkfs("ram")
    sys.wait(100)
    zbuff2 = zbuff.create(128*1024)
    local drv = sfd.init("zbuff", zbuff2)
    lfs2.mount("/mem", drv, true)

    
    local src = io.open("/wallpaper.jpg", "rb")
    local data = src:read("*a")
    src:close()
    local dst = io.open("/sdcard/wallpaper.jpg", "wb")
    dst:write(data)
    dst:close()

    local src = io.open("/wallpaper.sjpg", "rb")
    local data = src:read("*a")
    src:close()
    local dst = io.open("/mem/wallpaper.sjpg", "wb")
    dst:write(data)
    dst:close()

    lvgl.init()

    local img1 = lvgl.img_create(lvgl.scr_act())
    local img2 = lvgl.img_create(lvgl.scr_act())


    -- jpg from file
    lvgl.img_set_src(img1, "/sdcard/wallpaper.jpg")
    lvgl.img_set_src(img2, "/mem/wallpaper.sjpg")

    lvgl.obj_set_x(img2, 100)
    lvgl.obj_set_y(img2, 100)

end)


sys.run()
