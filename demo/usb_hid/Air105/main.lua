
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "test"
VERSION = "1.0.0"

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
