--[[
@module  tc_iot_config
@summary 腾讯云 IoT 微信通话凭证（与 demo/airlcd-camera-status-024 同一设备）
@version 1.1.0
@date    2026.10.21
@usage
  该文件必须与 main.lua 一起下载到设备，缺失或字段为空时 call_service 会降级为
  “本地模式”（只演示界面，不会真的呼叫微信）。
  wifi_ssid 仅作备用：net_mgr 连不上时，call_service 会用它再连一次。
]]

return {
    product_id    = "YOUR PRODUCT_ID", -- 腾讯云 IoT 控制台创建的产品 ID
    device_name   = "YOUR DEVICE_NAME", -- 腾讯云 IoT 控制台创建的设备名称
    device_secret = "YOUR DEVICE_SECRET", -- 腾讯云 IoT 控制台创建的设备密钥
    region        = "china",
    model_id      = "YOUR MODEL_ID", -- 腾讯云 IoT 控制台创建的模型 ID
    wxa_appid     = "YOUR WXA_APPID", -- 微信小程序 AppID

    voip_type     = 1,                          -- 0 正式 / 1 开发 / 2 体验版小程序
    data_path     = "YOUR DATA_PATH", -- 微信小程序后台创建的 data_path，必须与小程序端一致

    -- 备用热点（net_mgr 连不上时由 call_service 再连一次）
    wifi_ssid     = "YOUR WIFI SSID",
    wifi_password = "YOUR WIFI PASSWORD",

    auto_answer   = false,                      -- 台架测试可改 true
    caller_camera = 1,                          -- Air8101 H.264 视频上行
    callee_camera = 0,

    -- 外呼必须登记到业务后端，小程序才会收到来电；demo 里就是这个地址
    call_status_url   = "YOUR CALL_STATUS_URL",
    call_status_token = "YOUR CALL_STATUS_TOKEN",
    call_open_id      = "",                     -- 留空则取第一个授权用户
}
