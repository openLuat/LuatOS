local config = {}
config.UPLOAD_CONFIG = {
    ip = "",
    port = "",
    limitDuration = 300,  --单个录音文件最大时长 单位 秒
	locateFreq = 40,      -- 定位上传频率
    locateType = 2,       -- 定位模式 
}

-- 更新实时数据
-- 设备配置参数（初始化值）
config.deviceConfig = {
    appVersion = "v1.14",
    power = "100",
    totalDisk = "3792 MB",
    availableDisk = "3784 MB",
    totalMem = "373 KB",
    availableMem = "120 KB",
    recording = false
}
local mqtt_record_status = {
    recording = "recording",
    not_recording = "not_recording",
    no_status = -1
}
config.device_status_mode = {
    ota = 1,
    no_network = 2,
    no_mqtt = 3,
    mqtt_online = 4
}
config.record_status_mode = {
    recording = 1,
    record_error = 2,
    uploading = 3,
    no_record = 4,
    ota = 5
}
config.record_ctrl = mqtt_record_status.no_status
config.device_status = config.device_status_mode.no_network
config.record_status = config.record_status_mode.no_record
config.ota_status = false
config.upload_status = false
config.record_error = false
return config