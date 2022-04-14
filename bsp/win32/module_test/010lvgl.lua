

local sys = require "sys"

log.info("sys", "from win32")

sys.taskInit(function ()
    sys.wait(1000)

    if lfs2 ~= nil then
        local buff = zbuff.create(64*1024)
        local drv = sfd.init("zbuff", buff)
        if drv then
            lfs2.mount("/mem", drv, true)
            --lfs2.mkfs("/mem")
            local f = io.open("/mem/abc.txt", "w")
            if f then
                f:write("Hi, from LuatOS")
                f:close()
            end
            f = io.open("/mem/abc.txt", "r")
            if f then
                log.info("from lfs2-vfs", f:read("a"))
            end
        end
    end

    log.info("lvgl", lvgl.init())
    
    local scr = lvgl.obj_create(nil, nil)
    local btn = lvgl.btn_create(scr)
    local btn2 = lvgl.btn_create(scr)
    lvgl.obj_align(btn, lvgl.scr_act(), lvgl.ALIGN_CENTER, 0, 0)
    lvgl.obj_align(btn2, lvgl.scr_act(), lvgl.ALIGN_CENTER, 0, 50)
    local label = lvgl.label_create(btn)
    local label2 = lvgl.label_create(btn2)
    lvgl.label_set_text(label, "LuatOS!")
    lvgl.label_set_text(label2, "Hi")

    lvgl.scr_load(scr)

    log.info("abc", "=====================")

    sys.wait(3000)

    os.exit()
end)

sys.run()
