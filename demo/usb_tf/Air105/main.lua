
-- LuaTools需要PROJECT和VERSION这两个信息
-- 必须先挂载TF卡，然后再启动USB
-- 受制于USB速度和SPI速度，U盘在电脑上初始化过程非常慢，16G卡需要20~30秒，电脑文件浏览器会卡住，这是正常现象
-- 拿读卡器插在全速接口的USB-HUB能看到同样的问题
-- 出现prvUSB_MSCTimeout 96:bot timeout!, reboot usb是正常现象不用管
-- 读取速度大概在600KB~700KB，写入速度在350KB。注意105自己读写TF卡比这个快
PROJECT = "usb_tf"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

sys.taskInit(function()
    sys.wait(500) -- 启动延时
    local spiId = 0
    local result = spi.setup(
        spiId,--串口id
        255, -- 不使用默认CS脚
        0,--CPHA
        0,--CPOL
        8,--数据宽度
        400*1000  -- 初始化时使用较低的频率
    )
    local TF_CS = pin.PB13
    gpio.setup(TF_CS, 1)
    -- fatfs.debug(1) -- 若挂载失败,可以尝试打开调试信息,查找原因
    fatfs.mount("SD", 0, TF_CS, 24000000)
    local data, err = fatfs.getfree("SD")
    usbapp.udisk_attach_sdhc(0) -- udisk映射到TF卡上
    usbapp.start(0)
    sys.wait(600000)
end)
-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
