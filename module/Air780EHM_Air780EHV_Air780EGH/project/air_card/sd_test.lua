-- TODO 空间占用大时，清理记录中的文件
local function main_task()
    sys.wait(100)
    -- fatfs.debug(1) -- 若挂载失败,可以尝试打开调试信息,查找原因

    -- 此为spi方式挂载SD卡
    local spi_id, pin_cs = 0,8 
    spi.setup(spi_id, nil, 0, 0, pin_cs, 400 * 1000)
    gpio.setup(pin_cs, 1)
    fatfs.mount(fatfs.SPI, "/sd", spi_id, pin_cs, 24 * 1000 * 1000)

    --获取SD卡的可用空间信息
    local data, err = fatfs.getfree("/sd")
    if data then
        log.info("fatfs", "getfree", json.encode(data))
    else
        log.info("fatfs", "err", err)
    end
    sys.wait(100)
    RecordingManager.init()
    -- RecordingManager.check_recording_status()
end

sys.taskInit(main_task)

-- 录音记录管理模块,TODO:限制最大数量
local RecordingManager = {
    dbPath = "/sd/recording_db.json",  -- 数据库文件路径
    records = {}                       -- 内存中的记录缓存
}

-- 单个录音记录结构
function RecordingManager.createRecord(filename)
    local now = os.time()
    local start_time = os.date("%Y%m%d%H%M%S")
    return {
        filename = filename,             -- 录音文件名
        uploadStatus = "recording",      -- 上传状态: recording,pending, uploading, success, failed, done
        startTime = now,                 -- 录音开始时间 (Unix时间戳)
        endTime = nil,                   -- 录音结束时间 (在录音完成时设置)
        uploadAttempts = 0,              -- 上传尝试次数
        lastUploadTime = 0,              -- 最后上传尝试时间
        fileSize = 0,                    -- 文件大小(字节)
        uploadError = "",                -- 上传错误信息
        record_start = start_time,       -- 录音开始时间 os.date("%Y%m%d%H%M%S")
        record_end = 0,                  -- 录音结束时间 os.date("%Y%m%d%H%M%S")
        open_record_time = 0             -- 打开录音时间
    }
end

-- 初始化记录管理器
function RecordingManager.init()
    -- 检查数据库文件是否存在
    if io.exists(RecordingManager.dbPath) then
        -- 读取并解析现有数据库
        local file = io.open(RecordingManager.dbPath, "r")
        if file then
            local content = file:read("*a")
            file:close()
            
            if content and content ~= "" then
                local ok, data = pcall(json.decode, content)
                if ok and data then
                    RecordingManager.records = data
                    log.info("RECDB", "成功加载录音数据库，记录数:", #RecordingManager.records)
                    return
                end
            end
        end
    end
    
    -- 创建新数据库文件
    local file = io.open(RecordingManager.dbPath, "w")
    if file then
        file:write("[]")  -- 空数组
        file:close()
        log.info("RECDB", "创建新的录音数据库")
    else
        log.error("RECDB", "无法创建录音数据库文件")
    end
end

-- 添加新录音记录
function RecordingManager.addRecording(filename)
    -- 检查是否已存在同名记录
    for _, record in ipairs(RecordingManager.records) do
        if record.filename == filename then
            log.warn("RECDB", "记录已存在:", filename)
            return record
        end
    end
    
    -- 创建新记录
    local newRecord = RecordingManager.createRecord(filename)
    table.insert(RecordingManager.records, newRecord)
    RecordingManager.saveToDisk()
    log.info("RECDB", "添加新录音记录:", filename)
    return newRecord
end

-- 更新录音结束时间
function RecordingManager.setEndTime(filename, endTime)
    for _, record in ipairs(RecordingManager.records) do
        if record.filename == filename then
            record.endTime = endTime or os.time()
            record.record_end = os.date("%Y%m%d%H%M%S")
            record.uploadStatus = "pending"  -- 标记为等待上传
            -- 更新文件大小
            local filePath = "/sd/" .. filename
            if io.exists(filePath) then
                record.fileSize = io.fileSize(filePath)
            end
            
            RecordingManager.saveToDisk()
            log.info("RECDB", "更新录音结束时间:", filename, "时长:", record.endTime - record.startTime, "秒")
            return true
        end
    end
    return false
end

-- 设置打开录音开关的时间
function RecordingManager.setopen_record_time(filename, time)
    for _, record in ipairs(RecordingManager.records) do
        if record.filename == filename then
            record.open_record_time  = time or os.date("%Y%m%d%H%M%S")
            RecordingManager.saveToDisk()
            log.info("RECDB", "设置录音打开的时间:", filename, "时间:", time)
            return true
        end
    end
    return false
end


-- 设置录音开启的时间
function RecordingManager.set_firstopen_record_time(filename, time,ts)
    for _, record in ipairs(RecordingManager.records) do
        if record.filename == filename then
            record.record_start  = time or os.date("%Y%m%d%H%M%S")
            record.startTime = ts or os.time()
            record.open_record_time  = time or os.date("%Y%m%d%H%M%S")
            RecordingManager.saveToDisk()
            log.info("RECDB", "设置录音开启的时间:", filename, "时间:", time)
            return true
        end
    end
    return false
end



-- 更新上传状态
function RecordingManager.setUploadStatus(filename, status, errorMsg)
    for _, record in ipairs(RecordingManager.records) do
        if record.filename == filename then
            record.uploadStatus = status
            record.lastUploadTime = os.time()
            record.uploadAttempts = record.uploadAttempts + 1
            
            if errorMsg then
                record.uploadError = errorMsg
            end
            
            RecordingManager.saveToDisk()
            log.info("RECDB", "更新上传状态:", filename, "=>", status)
            return true
        end
    end
    return false
end

-- 获取待上传的记录
function RecordingManager.getPendingRecordings()
    local pending = {}
    for _, record in ipairs(RecordingManager.records) do
        if record.uploadStatus == "pending" or record.uploadStatus == "done" or 
           (record.uploadStatus == "failed" and record.uploadAttempts < 5) then
            table.insert(pending, record)
        end
    end
    return pending
end

-- 删除记录 (上传成功后调用)
function RecordingManager.removeRecord(filename)
    for i = #RecordingManager.records, 1, -1 do
        if RecordingManager.records[i].filename == filename then
            table.remove(RecordingManager.records, i)
            RecordingManager.saveToDisk()
            log.info("RECDB", "删除记录:", filename)
            
            -- 同时删除物理文件
            local filePath = "/sd/" .. filename
            if io.exists(filePath) then
                os.remove(filePath)
            end
            
            return true
        end
    end
    return false
end

-- 将内存中的数据保存到磁盘
function RecordingManager.saveToDisk()
    -- TODO 排查文件不断增大的问题
    local file = io.open(RecordingManager.dbPath, "w")
    if file then
        local jsonData = json.encode(RecordingManager.records)
        file:write(jsonData)
        file:close()
        return true
    end
    log.error("RECDB", "保存数据库失败")
    return false
end

-- 将记录转换为易读字符串 (用于日志显示)
function RecordingManager.recordToString(record)
    local duration = record.endTime and (record.endTime - record.startTime) or "N/A"
    local sizeMB = record.fileSize and string.format("%.2f MB", record.fileSize / (1024 * 1024)) or "N/A"
    
    return string.format("文件: %s | 状态: %s | 时长: %s秒 | 大小: %s | 开始时间: %s",
        record.filename,
        record.uploadStatus,
        duration,
        sizeMB,
        os.date("%Y-%m-%d %H:%M:%S", record.startTime)
    )
end

-- 清理旧记录 (防止数据库无限增长)
function RecordingManager.cleanOldRecords(maxAgeDays)
    local now = os.time()
    local removedCount = 0
    
    for i = #RecordingManager.records, 1, -1 do
        local record = RecordingManager.records[i]
        local recordAge = now - record.startTime
        if record.uploadStatus == "success" and recordAge > (maxAgeDays * 24 * 3600) then
            RecordingManager.removeRecord(record.filename)
            removedCount = removedCount + 1
        end
    end
    
    if removedCount > 0 then
        RecordingManager.saveToDisk()
        log.info("RECDB", "清理旧记录:", removedCount, "条")
    end
    
    return removedCount
end

-- 导出当前所有记录 (用于调试)
function RecordingManager.getAllRecords()
    return RecordingManager.records
end

-- 格式化tf卡
function RecordingManager.format_tf()
    local ret, errio = io.mkfs("/sd")
    log.info("fs", "mkfs", ret, errio)
    RecordingManager.records = {}
    RecordingManager.init()
end

-- -- 开机检查所有记录，录音状态为recording的并且没有录音结束时间，根据文件大小算出录音结束时间，修改状态并添加。done文件
function RecordingManager.check_recording_status()
    for i = #RecordingManager.records, 1, -1 do
        local record = RecordingManager.records[i]
        if record.uploadStatus == "recording" and record.endTime == 0 or record.endTime == nil then
            local filePath = "/sd/" .. record.filename
            if io.exists(filePath) then
                local fileSize = io.fileSize(filePath)
                log.info("fileSize",fileSize)
                if fileSize > 651 then
                    local seconds = math.floor(fileSize/641)
                    record.endTime = record.startTime + seconds
                    record.record_end = os.date("%Y%m%d%H%M%S", record.endTime)
                    record.uploadStatus = "pending"
                    record.fileSize = fileSize
                    log.info("RECDB", "更新录音结束时间:", record.filename, "时长:", seconds, "秒","结束时间",record.record_end)
                    local file_path = "/sd/" .. file_name
                    local f = io.open(file_path, "w")
                    if f then
                        log.info("添加.done文件", file_path)
                        f:write("\n")
                        f:close()
                    end
                    -- RecordingManager.saveToDisk()
                end
            end
        end
    end
end

local function getRecords()
    sys.wait(25000)
    while true do
        sys.wait(5000)
        -- 先执行意外关机需要补传的记录
        RecordingManager.cleanOldRecords(1)
        log.info("RECDB", "所有记录:", json.encode(RecordingManager.getAllRecords()))
        log.info("RECDB", "待上传记录:", json.encode(RecordingManager.getPendingRecordings()))
    end
end
-- 初始化数据库
sys.taskInit(getRecords)


return RecordingManager