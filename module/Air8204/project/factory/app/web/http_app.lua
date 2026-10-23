imei = mobile.imei()
local http_app = {}

httpplus = require("httpplus")

http_app.last_update_time = "0"
http_app.last_upload_result = false
-- 生成流水号
local counter = 0
function generateTransId()
    counter = counter + 1
    return os.date("%Y%m%d%H%M%S") .. string.format("%06d", counter)
end

--[[ 文件上传 ]] --
function http_app.uploadAudioFile(record)
    -- 生成流水号
    local transId = generateTransId()
    local xtime = os.date("%Y%m%d%H%M%S")
    -- 文件后缀
    local recPath = record.record_start .. "_" .. record.record_end
    -- Aircloud 
    if not excloud.status().is_connected then
        log.info("设备未连接，跳过音频上传")
        return
    end
    -- 上传音频文件
    local result, err_msg = excloud.upload_audio("/sd/" .. record.filename, recPath)
    if result then
        log.info("音频上传成功")
        http_app.last_upload_result = true
        http_app.last_update_time = os.date("%Y-%m-%d %H:%M:%S")
        RecordingManager.setUploadStatus(record.filename, "success")
        RecordingManager.removeRecord(record.filename)
        return true
    else
        log.error("音频上传失败:", err_msg)
        http_app.last_upload_result = false
        RecordingManager.setUploadStatus(record.filename, "failed")
        http_app.last_update_time = os.date("%Y-%m-%d %H:%M:%S")
    end
end

return http_app
