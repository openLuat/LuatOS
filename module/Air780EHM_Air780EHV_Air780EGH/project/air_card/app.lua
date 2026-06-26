local imei = mobile.imei()

local function rerecord_upload()
    while true do
        local records = RecordingManager.getPendingRecordings()
        sys.wait(28000)
        -- TODO 根据待上传录音数量决定等待时间
        if #records > 0 then
            log.info("records[1].uploadStatus", records[1].uploadStatus)
            log.info("http,开始上传录音")
            config.upload_status = true
            led_util.set_led2()
            sys.wait(2000)
            http_app.uploadAudioFile(records[1])
            log.info("http,录音上传完成", http_app.last_update_time, http_app.last_upload_result)
            config.upload_status = false
            sys.wait(1000)
            led_util.set_led2()
        else
            log.info("http,没有待上传录音")
            local limitDuration = config.UPLOAD_CONFIG.limitDuration
            sys.wait(limitDuration) -- 录音间隔时间上传
        end
        -- end
        sys.wait(1000)
    end
end

local last
--[[ 设备状态上报 ]] --
local function device_data_upload()
    while true do
        sys.wait(60000) -- 每1分钟上报一次
        log.info("mem.lua", rtos.meminfo())
        log.info("mem.sys", rtos.meminfo("sys"))
        -- 获取SD卡的可用空间信息
        local data, err = fatfs.getfree("/sd")
        if data then
            log.info("fatfs", "getfree", json.encode(data))
        else
            log.info("fatfs", "err", err)
        end
        local r1, r2, r3 = pm.lastReson()
        local reson = "reason" .. r1 .. r2 .. r3
        local tol, use, max_use = rtos.meminfo("sys")
        log.info("mem.lua", "totalMem", tol, "availableMem", use, "max_use", max_use)
        local statusMsg = {
            imei = imei,
            totalDisk = math.floor(data.total_kb / 1024) .. " MB",
            availableDisk = math.floor(data.free_kb / 1024) .. " MB",
            totalMem = math.floor(tol / 1024) .. " KB",
            availableMem = math.floor((tol - use) / 1024) .. " KB",
            appVersion = reson,
            power = tostring(gpio_util.get_battery_voltage()),
            recvType = 2,
            last = last
        }
        local content = json.encode(statusMsg)
        log.info(content)
        local status = excloud.status()
        if not status.is_connected then
            log.warn("设备未连接，跳过数据上报")
        else
            -- 上报基础状态数据
            local ok, err_msg = excloud.send({{
                field_meaning = excloud.FIELD_MEANINGS.BATTERY_LEVEL,
                data_type = excloud.DATA_TYPES.ASCII,
                value = gpio_util.get_battery_voltage()
            }, {
                field_meaning = excloud.FIELD_MEANINGS.BADGE_TOTAL_DISK,
                data_type = excloud.DATA_TYPES.ASCII,
                value = math.floor(data.total_kb / 1024) .. " MB"
            }, {
                field_meaning = excloud.FIELD_MEANINGS.TIMESTAMP,
                data_type = excloud.DATA_TYPES.INTEGER,
                value = os.time()
            }, {
                field_meaning = excloud.FIELD_MEANINGS.BADGE_AVAILABLE_DISK,
                data_type = excloud.DATA_TYPES.ASCII,
                value = math.floor(data.free_kb / 1024) .. " MB"
            }, {
                field_meaning = excloud.FIELD_MEANINGS.BADGE_TOTAL_MEM,
                data_type = excloud.DATA_TYPES.ASCII,
                value = math.floor(tol / 1024) .. " KB"
            }, {
                field_meaning = excloud.FIELD_MEANINGS.BADGE_AVAILABLE_MEM,
                data_type = excloud.DATA_TYPES.ASCII,
                value = math.floor((tol - use) / 1024) .. " KB"
            }}, false)

            if ok then
                log.info("基础数据上报成功")
            else
                log.error("基础数据上报失败:", err_msg)
            end
        end
        -- log.info("MQTT", "设备状态已上报")
        -- end
    end
end

--[[ GPS数据上报 ]] --
local function location_data_upload()
    while true do
        sys.wait(10000)
        sys.wait(20000) -- 默认20秒上报一次
        local fix, rmc = gps.getloc()
        local lbs_fix, lbs_rmc = lbs_util.getloc()
        local gpsData
        -- GPS数据获取
        if fix then
            gpsData = {{
                date = os.time(),
                longitude = rmc.lng,
                latitude = rmc.lat
            }}
        else
            --  获取室内定位结果
            if lbs_rmc.lng and lbs_rmc.lat then
                gpsData = {{
                    date = os.time(),
                    longitude = lbs_rmc.lng,
                    latitude = lbs_rmc.lat
                }}
            else
                gpsData = {{
                    date = os.time(),
                    longitude = "",
                    latitude = ""
                }}
            end
        end
        local content = json.encode(gpsData)
        log.info(content)
        local status = excloud.status()
        if not status.is_connected then
            log.warn("设备未连接，跳过数据上报")

        else
            -- 上报基础状态数据
            local ok, err_msg = excloud.send({{
                field_meaning = excloud.FIELD_MEANINGS.GNSS_LONGITUDE,
                data_type = excloud.DATA_TYPES.ASCII,
                value = gpsData[1].longitude
            }, {
                field_meaning = excloud.FIELD_MEANINGS.GNSS_LATITUDE,
                data_type = excloud.DATA_TYPES.ASCII,
                value = gpsData[1].latitude
            }, {
                field_meaning = excloud.FIELD_MEANINGS.TIMESTAMP,
                data_type = excloud.DATA_TYPES.INTEGER,
                value = os.time()
            }}, false)

            if ok then
                log.info("基础数据上报成功")
            else
                log.error("基础数据上报失败:", err_msg)
            end
        end
    end
end

sys.taskInit(location_data_upload)
sys.taskInit(rerecord_upload)
sys.taskInit(device_data_upload)