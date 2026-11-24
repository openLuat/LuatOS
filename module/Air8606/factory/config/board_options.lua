-- Air8606 上电默认装配，设备上保存的接口复用配置（air8606_mux）优先。
-- radio 默认 "wifi"：Engine_Air8606_10inch_1024x600_V010 首启用 WiFi 装配（Air6205），
-- 4G（Air780EX2）在「设置 → 接口复用 → SPI2」切换，重启生效。
return { radio = "wifi", uart2 = "can", rs4851 = "isolated", uart3 = "auto", uart6 = "air1103", usb = "uvc", audio_playback = "air1103" }
