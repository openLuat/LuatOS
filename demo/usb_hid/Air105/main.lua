
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "test"
VERSION = "1.0.0"

--[[
驱动下载, 与Air724驱动一致:
https://doc.openluat.com/wiki/21?wiki_page_id=2070
]]

-- sys库是标配
_G.sys = require("sys")

sys.subscribe("USB_HID_INC", function(event)
    log.info("HID EVENT", event)
    if event == usbapp.NEW_DATA then
        sys.publish("HID_RX")
    end
end)
sys.taskInit(function()
    local rx_buff = zbuff.create(64)
    local tx_buff = zbuff.create(64)
    -- 下面演示键盘模式下发送原始包来实现键盘功能
    -- 底层键盘描述符中，1个包8个字节，byte0是控制按键值，其中
    -- bit0 LeftControl
    -- bit1 LeftShift
    -- bit2 LeftAlt
    -- bit3 LeftGUI
    -- bit4 RightControl
    -- bit5 RightShift
    -- bit6 RightAlt
    -- bit7 RightGUI win键
    -- byte1 固定0
    -- byte2~8 其他按键值，最多允许同时按下6个键
    -- 没有按键按下时，8个byte都为0
    -- 为了兼容扫码枪处理，允许一次发送多次按键处理
    usbapp.start(0)
    while 1 do
        -- 模拟按下数字0，然后抬起
        tx_buff:copy(0, "\x00\x00\x27\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00")
        usbapp.hid_tx(0, tx_buff)
        tx_buff:del()
        sys.wait(5000)
         -- 模拟按下Ctrl+Alt+A，然后抬起，QQ截屏
        tx_buff:copy(0, "\x05\x00\x04\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00")
        usbapp.hid_tx(0, tx_buff)
        tx_buff:del()
        sys.wait(5000)
    end
    --下面演示自定义HID，使用前注释掉上面的键盘模式演示代码
    usbapp.set_id(0, 0xaabb, 0xccdd)    --改了默认VID和PID识别不了串口，但是HID和MSD还能用
    usbapp.hid_mode(0, 1, 8)       --自定义HID模式，ep_size=8，每次发送需要8的倍数，适合数据量较小的应用
    --usbapp.hid_mode(0, 1, 64)       --自定义HID模式，ep_size=64，每次发送需要64的倍数，适合数据量较大的应用
    usbapp.start(0)
    while 1 do  --收到数据返回hellworld+PC数据
        local msg, data = sys.waitUntilExt("HID_RX")
        usbapp.hid_rx(0, rx_buff)
        tx_buff:copy(0, "helloworld" .. rx_buff:query())
        rx_buff:del()
        usbapp.hid_tx(0, tx_buff)
        tx_buff:del()
    end
    
end)
-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
