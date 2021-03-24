
PROJECT = "sdcarddemo"
VERSION = "1.0.0"

local sys = require "sys"

pmd.ldoset(3200, pmd.LDO_VLCD)

-- 把灯闪起来, 免得死机了都不知道
sys.taskInit(function()
    local netled = gpio.setup(1, 0)
    while 1 do
        netled(1)
        sys.wait(1000)
        netled(0)
        sys.wait(1000)
    end
end)

sys.taskInit(function()
    sys.wait(15*1000)
    while 1 do
        -- 挂载在/sdcard, 或者你喜欢的路径, 长度不可以超过12字节
        fs.mount("sdmmc", "elm", "/sdcard", "sd")
        -- 挂载完, 读取一下文件系统大小
        log.info("sdcard", "mounted", fs.fsstat("/sdcard/"))
        local f = io.open("/sdcard/luatos", "w")
        if f then
            f:write("luatos\r\n")
            f:write(os.date())
            f:close()
        end

        sys.wait(2000)
        -- 然后又卸载掉, 多开心, 反复N次都可以
        fs.umount("/sdcard")
        log.info("sdcard", "umount", fs.fsstat("/sdcard/"))
        sys.wait(5000)

        -- 或者, 格式化一下?
        --fs.mkfs("sdmmc", "elm")
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
