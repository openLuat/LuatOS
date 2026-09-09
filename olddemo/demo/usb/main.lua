PROJECT = "usb_demo"
VERSION = "1.3.3"

sys = require("sys")

log.style(1)

local function air1601_evb_init()
    gpio.setup(12, 1, gpio.PULLUP) -- 输出高，内部上拉可选
end

local u_disk_test_ready = false
local u_disk_app_id = nil

local function usb_cb(usb_id, class, app_id, event, param1, param2, param3)
    if event == usb.EV_CONNECT then
        if class == usb.CAMERA then
            log.info("usb摄像头已连接，使用app id", app_id, "位于hub地址", param1, "端口",param2, "地址", param3)
        end
        if class == usb.MSC then
            log.info("USB大容量存储设备已连接，使用app id", app_id, "位于hub地址", param1, "端口",param2, "地址", param3)
            u_disk_app_id = app_id
            u_disk_test_ready = true
        end
    end
    if event == usb.EV_DISCONNECT then
        if class == usb.CAMERA then
            log.info("usb摄像头已断开，使用app id", app_id, "位于hub地址", param1, "端口",param2, "地址", param3)
        end
        if class == usb.MSC then
            log.info("USB大容量存储设备已断开，使用app id", app_id, "位于hub地址", param1, "端口",param2, "地址", param3)
            u_disk_test_ready = false
            u_disk_app_id = nil
        end
    end
end

usb.on(0, usb_cb)
sys.taskInit(function()
    require("lcd_drv")
    require("hid_lvgl")
    require("input_demo")
    require("tp_drv")
    pm.power(pm.USB, false)
    sys.wait(100) -- USB电源操作由C任务异步执行，等待关闭后再切换模式
    air1601_evb_init()
    sys.wait(100) -- 等待开发板VBUS供电稳定
    usb.debug(0, false) -- 保留 C HID/input 日志，关闭底层控制传输刷屏
    assert(usb.mode(0, usb.HOST), "USB Host mode failed")
    pm.power(pm.USB, true)
    log.info("usb_hid", "HID_C_HOST_READY", VERSION)
    while true do
        sys.wait(10000)
        log.info("usb_hid", "HID_C_HOST_STABLE", VERSION)
    end
end)

local function u_disk_test_task()
    while true do
        while not u_disk_test_ready do  --正式用不要这么傻等
            sys.wait(100)
        end
        local u_disk_path = "/udisk"
        -- fatfs.debug(1) -- 若挂载失败,可以尝试打开调试信息,查找原因
        fatfs.mount(fatfs.USB, u_disk_path, u_disk_app_id)

        local data, err = fatfs.getfree(u_disk_path)
        if data then
            log.info("fatfs", "getfree", json.encode(data))
        else
            log.info("fatfs", "err", err)
        end

        -- #################################################
        -- 文件操作测试
        -- #################################################
        local f = io.open(u_disk_path .. "/boottime", "rb")
        local c = 0
        if f then
            local data = f:read("*a")
            log.info("fs", "data", data, data:toHex())
            c = tonumber(data)
            f:close()
        end
        log.info("fs", "boot count", c)
        if c == nil then
            c = 0
        end
        c = c + 1
        f = io.open(u_disk_path .. "/boottime", "wb")
        if f ~= nil then
            log.info("fs", "write c to file", c, tostring(c))
            f:write(tostring(c))
            f:close()
        else
            log.warn("sdio", "mount not good?!")
        end
        if fs then
            log.info("fsstat", fs.fsstat(u_disk_path))
        end

        -- 测试一下追加, fix in 2021.12.21
        os.remove(u_disk_path .. "/test_a.txt")
        sys.wait(50)
        f = io.open(u_disk_path .. "/test_a.txt", "w")
        if f then
            f:write("ABC")
            f:close()
        end
        f = io.open(u_disk_path .. "/test_a.txt", "a+")
        if f then
            f:write("def")
            f:close()
        end
        f = io.open(u_disk_path .. "/test_a.txt", "r")
        if  f then
            local data = f:read("*a")
            log.info("data", data, data == "ABCdef")
            f:close()
        end

        -- 测试一下按行读取, fix in 2022-01-16
        f = io.open(u_disk_path .. "/testline.txt", "w")
        if f then
            f:write("abc\n")
            f:write("123\n")
            f:write("wendal\n")
            f:close()
        end
        sys.wait(100)
        f = io.open(u_disk_path .. "/testline.txt", "r")
        if f then
            log.info("sdio", "line1", f:read("*l"))
            log.info("sdio", "line2", f:read("*l"))
            log.info("sdio", "line3", f:read("*l"))
            f:close()
        end
        -- -- #################################################
        log.info("测试完成可以拔出USB大容量存储设备")
        fatfs.unmount(u_disk_path)
        while u_disk_test_ready do  --正式用不要这么傻等
            sys.wait(100)
        end
    end
end
-- HID/LVGL验证期间不启用U盘读写任务。
-- sys.taskInit(u_disk_test_task)
-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
