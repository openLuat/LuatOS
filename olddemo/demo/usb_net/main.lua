PROJECT = "USB_NET"
VERSION = "1.0.0"

local function usb_cb(usb_id, class, app_id, event, param1, param2, param3)
    if event == usb.EV_CONNECT then
        if class == usb.RNDIS then
            log.info("rndis设备已连接")
        elseif class == usb.CDC_ECM then
            log.info("ecm设备已连接")
        end
    end
    if event == usb.EV_DISCONNECT then
        if class == usb.RNDIS then
            log.info("rndis设备已断开连接")
        elseif class == usb.CDC_ECM then
            log.info("ecm设备已断开连接")
        end
    end
end


gpio.setup(12, 1, gpio.PULLUP)
usb.on(0, usb_cb)
pm.power(pm.USB, false)
usb.mode(0, usb.HOST)
pm.power(pm.USB, true)

sys.run()
