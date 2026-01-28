local check_core = {}
local model_ec718hm = {"Air780EHM", "Air780EHV", "Air780EGH", "Air780EGG", "Air700ECH"}
local model_ec718pm = {"Air780EPM", "Air780EGP", "Air700ECP"}
local A = _G

-- 0号版本，所有库都有的table，方便新库的增加时候的检查
local B = {"lvgl", "cc", "audio.tts", "airtalk", "camera", "codec", "fastlz", "fatfs", "gtfont", "lf", "io",
           "lcd.font_opposansm12_chinese", "audio", "i2s", "ble", "libgnss", "sfud", "yhm27xx", "ymodem", "otp", "adc",
           "airlink", "bit64", "can", "crypto", "eink", "errDump", "fota", "fskv", "ftp", "gmssl", "gpio", "ht1621",
           "http", "httpsrv", "i2c", "iconv", "ioqueue", "iotauth", "iperf", "json", "lcd", "log", "lora2", "mcu",
           "miniz", "mobile", "mqtt", "netdrv", "onewire", "os", "pack", "pins", "pm", "protobuf", "pwm", "rsa", "rtc",
           "rtos", "sms", "socket", "spi", "string", "sys", "sysplus", "tp", "u8g2", "uart", "wdt", "websocket", "wlan",
           "xxtea", "zbuff", "fft", "hzfont"}

-- 1号固件
---718hm
local A_1 = {"audio.tts", "cc", "camera", "codec", "fastlz", "fatfs", "gtfont", "lf", "lcd.font_opposansm12_chinese",
             "audio", "i2s", "ble", "libgnss", "sfud", "yhm27xx", "ymodem", "otp", "adc", "airlink", "bit64", "can",
             "crypto", "eink", "errDump", "fota", "fskv", "ftp", "gmssl", "gpio", "hmeta", "ht1621", "http", "httpsrv",
             "i2c", "iconv", "io", "ioqueue", "iotauth", "iperf", "json", "lcd", "log", "lora2", "mcu", "miniz",
             "mobile", "mqtt", "netdrv", "onewire", "os", "pack", "pins", "pm", "protobuf", "pwm", "rsa", "rtc", "rtos",
             "sms", "socket", "spi", "string", "sys", "sysplus", "tp", "u8g2", "uart", "wdt", "websocket", "wlan",
             "xxtea", "zbuff", "fft"}

-- 2号固件
local A_2 = {"lvgl", "cc", "camera", "codec", "fastlz", "fatfs", "gtfont", "lf", "lcd.font_opposansm12_chinese",
             "audio", "i2s", "ble", "libgnss", "sfud", "yhm27xx", "ymodem", "otp", "adc", "airlink", "bit64", "can",
             "crypto", "eink", "errDump", "fota", "fskv", "ftp", "gmssl", "gpio", "hmeta", "ht1621", "http", "httpsrv",
             "i2c", "iconv", "io", "ioqueue", "iotauth", "iperf", "json", "lcd", "log", "lora2", "mcu", "miniz",
             "mobile", "mqtt", "netdrv", "onewire", "os", "pack", "pins", "pm", "protobuf", "pwm", "rsa", "rtc", "rtos",
             "sms", "socket", "spi", "string", "sys", "sysplus", "tp", "u8g2", "uart", "wdt", "websocket", "wlan",
             "xxtea", "zbuff", "fft"}

-- 3号固件
local A_3 = {"lvgl", "audio.tts", "camera", "codec", "fastlz", "fatfs", "gtfont", "lf", "lcd.font_opposansm12_chinese",
             "audio", "i2s", "ble", "libgnss", "sfud", "yhm27xx", "ymodem", "otp", "adc", "airlink", "bit64", "can",
             "crypto", "eink", "errDump", "fota", "fskv", "ftp", "gmssl", "gpio", "hmeta", "ht1621", "http", "httpsrv",
             "i2c", "iconv", "io", "ioqueue", "iotauth", "iperf", "json", "lcd", "log", "lora2", "mcu", "miniz",
             "mobile", "mqtt", "netdrv", "onewire", "os", "pack", "pins", "pm", "protobuf", "pwm", "rsa", "rtc", "rtos",
             "sms", "socket", "spi", "string", "sys", "sysplus", "tp", "u8g2", "uart", "wdt", "websocket", "wlan",
             "xxtea", "zbuff", "fft"}

-- 4号固件
local A_4 = {"lvgl", "airtalk", "camera", "codec", "fastlz", "fatfs", "gtfont", "lf", "lcd.font_opposansm12_chinese",
             "audio", "i2s", "ble", "libgnss", "sfud", "yhm27xx", "ymodem", "otp", "adc", "airlink", "bit64", "can",
             "crypto", "eink", "errDump", "fota", "fskv", "ftp", "gmssl", "gpio", "hmeta", "ht1621", "http", "httpsrv",
             "i2c", "iconv", "io", "ioqueue", "iotauth", "iperf", "json", "lcd", "log", "lora2", "mcu", "miniz",
             "mobile", "mqtt", "netdrv", "onewire", "os", "pack", "pins", "pm", "protobuf", "pwm", "rsa", "rtc", "rtos",
             "sms", "socket", "spi", "string", "sys", "sysplus", "tp", "u8g2", "uart", "wdt", "websocket", "wlan",
             "xxtea", "zbuff", "fft"}

-- 5号固件
local A_5 = {"audio.tts", "airtalk", "camera", "codec", "fastlz", "fatfs", "gtfont", "lf",
             "lcd.font_opposansm12_chinese", "audio", "i2s", "ble", "libgnss", "sfud", "yhm27xx", "ymodem", "otp",
             "adc", "airlink", "bit64", "can", "crypto", "eink", "errDump", "fota", "fskv", "ftp", "gmssl", "gpio",
             "hmeta", "ht1621", "http", "httpsrv", "i2c", "iconv", "io", "ioqueue", "iotauth", "iperf", "json", "lcd",
             "log", "lora2", "mcu", "miniz", "mobile", "mqtt", "netdrv", "onewire", "os", "pack", "pins", "pm",
             "protobuf", "pwm", "rsa", "rtc", "rtos", "sms", "socket", "spi", "string", "sys", "sysplus", "tp", "u8g2",
             "uart", "wdt", "websocket", "wlan", "xxtea", "zbuff", "fft"}

-- 6号固件
local A_6 = {"lvgl", "camera", "codec", "fastlz", "fatfs", "gtfont", "lf", "lcd.font_opposansm12_chinese", "audio",
             "i2s", "ble", "libgnss", "sfud", "yhm27xx", "ymodem", "otp", "adc", "airlink", "bit64", "can", "crypto",
             "eink", "errDump", "fota", "fskv", "ftp", "gmssl", "gpio", "hmeta", "ht1621", "http", "httpsrv", "i2c",
             "iconv", "io", "ioqueue", "iotauth", "iperf", "json", "lcd", "log", "lora2", "mcu", "miniz", "mobile",
             "mqtt", "netdrv", "onewire", "os", "pack", "pins", "pm", "protobuf", "pwm", "rsa", "rtc", "rtos", "sms",
             "socket", "spi", "string", "sys", "sysplus", "tp", "u8g2", "uart", "wdt", "websocket", "wlan", "xxtea",
             "zbuff", "fft"}

-- 7号固件
local A_7 = {"audio.tts", "camera", "codec", "fastlz", "fatfs", "gtfont", "lf", "lcd.font_opposansm12_chinese", "audio",
             "i2s", "ble", "libgnss", "sfud", "yhm27xx", "ymodem", "otp", "adc", "airlink", "bit64", "can", "crypto",
             "eink", "errDump", "fota", "fskv", "ftp", "gmssl", "gpio", "hmeta", "ht1621", "http", "httpsrv", "i2c",
             "iconv", "io", "ioqueue", "iotauth", "iperf", "json", "lcd", "log", "lora2", "mcu", "miniz", "mobile",
             "mqtt", "netdrv", "onewire", "os", "pack", "pins", "pm", "protobuf", "pwm", "rsa", "rtc", "rtos", "sms",
             "socket", "spi", "string", "sys", "sysplus", "tp", "u8g2", "uart", "wdt", "websocket", "wlan", "xxtea",
             "zbuff", "fft"}

-- 8号固件
local A_8 = {"cc", "camera", "codec", "fastlz", "fatfs", "gtfont", "lf", "lcd.font_opposansm12_chinese", "audio", "i2s",
             "ble", "libgnss", "sfud", "yhm27xx", "ymodem", "otp", "adc", "airlink", "bit64", "can", "crypto", "eink",
             "errDump", "fota", "fskv", "ftp", "gmssl", "gpio", "hmeta", "ht1621", "http", "httpsrv", "i2c", "iconv",
             "io", "ioqueue", "iotauth", "iperf", "json", "lcd", "log", "lora2", "mcu", "miniz", "mobile", "mqtt",
             "netdrv", "onewire", "os", "pack", "pins", "pm", "protobuf", "pwm", "rsa", "rtc", "rtos", "sms", "socket",
             "spi", "string", "sys", "sysplus", "tp", "u8g2", "uart", "wdt", "websocket", "wlan", "xxtea", "zbuff",
             "fft"}

-- 9号固件
local A_9 = {"airtalk", "camera", "codec", "fastlz", "fatfs", "gtfont", "lf", "lcd.font_opposansm12_chinese", "audio",
             "i2s", "ble", "libgnss", "sfud", "yhm27xx", "ymodem", "otp", "adc", "airlink", "bit64", "can", "crypto",
             "eink", "errDump", "fota", "fskv", "ftp", "gmssl", "gpio", "hmeta", "ht1621", "http", "httpsrv", "i2c",
             "iconv", "io", "ioqueue", "iotauth", "iperf", "json", "lcd", "log", "lora2", "mcu", "miniz", "mobile",
             "mqtt", "netdrv", "onewire", "os", "pack", "pins", "pm", "protobuf", "pwm", "rsa", "rtc", "rtos", "sms",
             "socket", "spi", "string", "sys", "sysplus", "tp", "u8g2", "uart", "wdt", "websocket", "wlan", "xxtea",
             "zbuff", "fft"}

-- 10号固件
local A_10 = {"camera", "codec", "fastlz", "fatfs", "gtfont", "lf", "lcd.font_opposansm12_chinese", "audio", "i2s",
              "ble", "libgnss", "sfud", "yhm27xx", "ymodem", "otp", "adc", "airlink", "bit64", "can", "crypto", "eink",
              "errDump", "fota", "fskv", "ftp", "gmssl", "gpio", "hmeta", "ht1621", "http", "httpsrv", "i2c", "iconv",
              "io", "ioqueue", "iotauth", "iperf", "json", "lcd", "log", "lora2", "mcu", "miniz", "mobile", "mqtt",
              "netdrv", "onewire", "os", "pack", "pins", "pm", "protobuf", "pwm", "rsa", "rtc", "rtos", "sms", "socket",
              "spi", "string", "sys", "sysplus", "tp", "u8g2", "uart", "wdt", "websocket", "wlan", "xxtea", "zbuff",
              "fft"}

-- 11号固件
local A_11 = {"ble", "libgnss", "yhm27xx", "ymodem", "otp", "adc", "airlink", "bit64", "can", "crypto", "eink",
              "errDump", "fota", "fskv", "ftp", "gmssl", "gpio", "hmeta", "ht1621", "http", "httpsrv", "i2c", "iconv",
              "io", "ioqueue", "iotauth", "iperf", "json", "lcd", "log", "lora2", "mcu", "miniz", "mobile", "mqtt",
              "netdrv", "onewire", "os", "pack", "pins", "pm", "protobuf", "pwm", "rsa", "rtc", "rtos", "sms", "socket",
              "spi", "string", "sys", "sysplus", "tp", "u8g2", "uart", "wdt", "websocket", "wlan", "xxtea", "zbuff",
              "fft"}

-- 12号固件
local A_12 = A_11

-- 13号固件
local A_13 = {"audio.tts", "cc", "camera", "codec", "fastlz", "fatfs", "gtfont", "lf", "audio", "i2s", "ble", "libgnss",
              "sfud", "yhm27xx", "ymodem", "otp", "adc", "airlink", "bit64", "can", "crypto", "eink", "errDump", "fota",
              "fskv", "ftp", "gmssl", "gpio", "hmeta", "ht1621", "http", "httpsrv", "i2c", "iconv", "io", "ioqueue",
              "iotauth", "iperf", "json", "lcd", "log", "lora2", "mcu", "miniz", "mobile", "mqtt", "netdrv", "onewire",
              "os", "pack", "pins", "pm", "protobuf", "pwm", "rsa", "rtc", "rtos", "sms", "socket", "spi", "string",
              "sys", "sysplus", "tp", "u8g2", "uart", "wdt", "websocket", "wlan", "xxtea", "zbuff", "fft"}

local A_14 = {"ble", "libgnss", "yhm27xx", "ymodem", "otp", "adc", "airlink", "bit64", "can", "crypto", "eink",
              "errDump", "fota", "fskv", "ftp", "gmssl", "gpio", "hmeta", "ht1621", "http", "httpsrv", "i2c", "iconv",
              "io", "ioqueue", "iotauth", "iperf", "json", "lcd", "log", "lora2", "mcu", "miniz", "mobile", "mqtt",
              "netdrv", "onewire", "os", "pack", "pins", "pm", "protobuf", "pwm", "rsa", "rtc", "rtos", "sms", "socket",
              "spi", "string", "sys", "sysplus", "tp", "u8g2", "uart", "wdt", "websocket", "wlan", "xxtea", "zbuff",
              "fft", "hzfont", "lf"}

local A_size = {
    [1] = {
        fs_size = 768,
        script_size = 512
    },
    [2] = {
        fs_size = 640,
        script_size = 512
    },
    [3] = {
        fs_size = 512,
        script_size = 512
    },
    [4] = {
        fs_size = 1280,
        script_size = 512
    },
    [5] = {
        fs_size = 1408,
        script_size = 512
    },

    [6] = {
        fs_size = 1408,
        script_size = 512
    },

    [7] = {
        fs_size = 1536,
        script_size = 512
    },
    [8] = {
        fs_size = 1536,
        script_size = 512
    },
    [9] = {
        fs_size = 2304,
        script_size = 512
    },
    [10] = {
        fs_size = 2432,
        script_size = 512
    },
    [11] = {
        fs_size = 3584,
        script_size = 256
    },
    [12] = {
        fs_size = 2304,
        script_size = 1024
    },
    [13] = {
        fs_size = 512,
        script_size = 512
    },
    [14] = {
        fs_size = 1024,
        script_size = 512
    }

}

---718pm

local B_1 = {"camera", "eink", "tp", "lcd", "u8g2", "protobuf", "adc", "airlink", "bit64", "can", "crypto", "errDump",
             "i2c", "iconv", "io", "fota", "fskv", "ftp", "gmssl", "gpio","hmeta", "ht1621", "http", "httpsrv", "ioqueue",
             "iotauth", "iperf", "json", "log", "lora2", "mcu", "miniz", "mobile", "mqtt", "netdrv", "onewire", "os",
             "pack", "pins", "pm", "pwm", "rsa", "rtc", "rtos", "sms", "socket", "spi", "string", "sys", "sysplus",
             "uart", "wdt", "websocket", "wlan", "xxtea", "zbuff"}

-- 2号固件
local B_2 = {"camera", "lcd", "u8g2", "protobuf", "adc", "airlink", "bit64", "can", "crypto", "errDump", "fota", "fskv",
             "ftp", "gmssl", "gpio", "hmeta", "ht1621", "http", "httpsrv", "i2c", "iconv", "io", "ioqueue", "iotauth",
             "iperf", "json", "log", "lora2", "mcu", "miniz", "mobile", "mqtt", "netdrv", "onewire", "os", "pack",
             "pins", "pm", "pwm", "rsa", "rtc", "rtos", "sms", "socket", "spi", "string", "sys", "sysplus", "uart",
             "wdt", "websocket", "wlan", "xxtea", "zbuff"}

-- 3号固件
local B_3 = {"libgnss", "protobuf", "adc", "airlink", "bit64", "can", "crypto", "errDump", "fota", "fskv", "ftp",
             "gmssl", "gpio", "hmeta", "ht1621", "http", "httpsrv", "i2c", "iconv", "io", "ioqueue", "iotauth", "iperf",
             "json", "log", "lora2", "mcu", "miniz", "mobile", "mqtt", "netdrv", "onewire", "os", "pack", "pins", "pm",
             "pwm", "rsa", "rtc", "rtos", "sms", "socket", "spi", "string", "sys", "sysplus", "uart", "wdt",
             "websocket", "wlan", "xxtea", "zbuff"}

-- 4号固件
local B_4 = {"lf", "libgnss", "otp", "fft", "protobuf", "adc", "airlink", "bit64", "can", "crypto", "errDump", "fota",
             "fskv", "ftp", "gmssl", "gpio", "hmeta", "ht1621", "http", "httpsrv", "i2c", "iconv", "io", "ioqueue",
             "iotauth", "iperf", "json", "log", "lora2", "mcu", "miniz", "mobile", "mqtt", "netdrv", "onewire", "os",
             "pack", "pins", "pm", "pwm", "rsa", "rtc", "rtos", "sms", "socket", "spi", "string", "sys", "sysplus",
             "uart", "wdt", "websocket", "wlan", "xxtea", "zbuff"}

-- 5号固件
local B_5 = {"camera", "lf", "libgnss", "otp", "fft", "protobuf", "adc", "airlink", "bit64", "can", "crypto", "errDump",
             "fota", "fskv", "ftp", "gmssl", "gpio", "hmeta", "ht1621", "http", "httpsrv", "i2c", "iconv", "io",
             "ioqueue", "iotauth", "iperf", "json", "log", "lora2", "mcu", "miniz", "mobile", "mqtt", "netdrv",
             "onewire", "os", "pack", "pins", "pm", "pwm", "rsa", "rtc", "rtos", "sms", "socket", "spi", "string",
             "sys", "sysplus", "uart", "wdt", "websocket", "wlan", "xxtea", "zbuff"}

-- 6号固件
local B_6 = {"adc", "airlink", "bit64", "can", "crypto", "errDump", "fota", "fskv", "ftp", "gmssl", "gpio", "hmeta",
             "ht1621", "http", "httpsrv", "i2c", "iconv", "io", "ioqueue", "iotauth", "iperf", "json", "log", "lora2",
             "mcu", "miniz", "mobile", "mqtt", "netdrv", "onewire", "os", "pack", "pins", "pm", "pwm", "rsa", "rtc",
             "rtos", "sms", "socket", "spi", "string", "sys", "sysplus", "uart", "wdt", "websocket", "wlan", "xxtea",
             "zbuff"}

local B_7 = {"lcd", "u8g2", "adc", "crypto", "errDump", "fota", "fskv", "gpio", "i2c", "iconv", "io", "json", "log",
             "bit64", "http", "netdrv", "mcu", "mobile", "mqtt", "os", "pack", "pins", "pm", "pwm", "rtc", "rtos",
             "socket", "spi", "string", "sys", "sysplus", "uart", "wdt", "wlan", "zbuff"}
local B_size = {
    [1] = {
        fs_size = 168,
        script_size = 256
    },
    [2] = {
        fs_size = 168,
        script_size = 288
    },
    [3] = {
        fs_size = 168,
        script_size = 384
    },
    [4] = {
        fs_size = 168,
        script_size = 368
    },
    [5] = {
        fs_size = 192,
        script_size = 256
    },

    [6] = {
        fs_size = 168,
        script_size = 176
    },
    [7] = {
        fs_size = 168,
        script_size = 288
    }
}

-- 8101
local C_1 = {"airlink", "fft", "protobuf", "iconv", "rsa", "xxtea", "camera", "fatfs", "can", "pins", "ble", "fastlz",
             "lcd", "lf", "otp", "tp", "crypto", "errDump", "fota", "fskv", "ftp", "gmssl", "gpio", "hmeta", "http",
             "httpsrv", "i2c", "io", "iotauth", "iperf", "json", "log", "lora2", "mcu", "miniz", "mqtt", "netdrv", "os",
             "pack", "pwm", "pm", "rtc", "rtos", "socket", "spi", "string", "sys", "sysplus", "uart", "wdt",
             "websocket", "wlan", "zbuff"}

local C_2 = {"airlink", "camera", "fatfs", "can", "pins", "ble", "fastlz", "lcd", "lf", "otp", "tp", "crypto",
             "errDump", "fota", "fskv", "ftp", "gmssl", "gpio", "hmeta", "http", "httpsrv", "i2c", "io", "iotauth",
             "iperf", "json", "log", "lora2", "mcu", "miniz", "mqtt", "netdrv", "os", "pack", "pwm", "pm", "rtc",
             "rtos", "socket", "spi", "string", "sys", "sysplus", "uart", "wdt", "websocket", "wlan", "zbuff"}

local C_size = {
    [1] = {
        fs_size = 256,
        script_size = 512
    },
    [2] = {
        fs_size = 2124,
        script_size = 512
    }
}

local function findMissingElements(aTable, bTable)
    local missingElements = {}

    for _, bKey in ipairs(bTable) do
        log.info("当前检查的库为：", bKey)
        sys.wait(200)
        local exists = false
        exists = aTable[bKey] ~= nil
        if not exists then
            log.info(bKey .. " 不存在")
            table.insert(missingElements, bKey)
        else
            log.info(bKey .. " 存在")
        end
    end
    return missingElements
end

-- 过滤缺失列表：只保留在当前固件配置表中存在的库
local function filterMissingByFirmware(missingList, firmwareConfig)
    local filteredMissing = {}
    for _, libName in ipairs(missingList) do
        local shouldExist = false
        -- 检查该库是否在固件配置表中
        for _, firmwareLib in ipairs(firmwareConfig) do
            if firmwareLib == libName then
                shouldExist = true
                break
            end
        end
        if shouldExist then
            table.insert(filteredMissing, libName)
        else
            log.info("库 " .. libName .. " 在固件定义中不存在，忽略")
        end
    end

    return filteredMissing
end

-- 根据rtos.version()返回的core值获取对应的配置表
local function getConfigByCore()
    -- 生成对应的表名
    local table_name
    local config_table
    local mouble, core_value, _ = rtos.version(true)
    local rtos_bsp = rtos.bsp()
    local core_number = tonumber(core_value) or 1
    local core_num
    local is_ec718hm = false
    local is_ec718pm = false
    for _, model in ipairs(model_ec718hm) do
        if rtos_bsp == model then
            is_ec718hm = true
            log.info("是718hm")
            break
        end
    end

    -- 检查是否在 model_ec718pm 列表中)
    if not is_ec718hm then
        for _, model in ipairs(model_ec718pm) do
            if rtos_bsp == model then
                is_ec718pm = true
                log.info("是718pm")
                break
            end
        end
    end

    if core_number > 100 then
        core_num = core_number - 100
    else
        core_num = core_number
    end

    log.info("获取到的固件核心版本:", core_number, "(原始值:", core_value, ")")
    if is_ec718hm or string.find(rtos_bsp, "Air8000") then
        -- 生成对应的表名
        table_name = "A_" .. tostring(core_num)
        -- 根据表名返回对应的本地表
        if table_name == "A_1" then
            config_table = A_1
        elseif table_name == "A_2" then
            config_table = A_2
        elseif table_name == "A_3" then
            config_table = A_3
        elseif table_name == "A_4" then
            config_table = A_4
        elseif table_name == "A_5" then
            config_table = A_5
        elseif table_name == "A_6" then
            config_table = A_6
        elseif table_name == "A_7" then
            config_table = A_7
        elseif table_name == "A_8" then
            config_table = A_8
        elseif table_name == "A_9" then
            config_table = A_9
        elseif table_name == "A_10" then
            config_table = A_10
        elseif table_name == "A_11" then
            config_table = A_11
        elseif table_name == "A_12" then
            config_table = A_12
        elseif table_name == "A_13" then
            config_table = A_13
        elseif table_name == "A_14" then
            config_table = A_14
        else
            log.error("未知的配置表名:", table_name)
        end
    elseif is_ec718pm then
        table_name = "B_" .. tostring(core_num)
        if table_name == "B_1" then
            config_table = B_1
        elseif table_name == "B_2" then
            config_table = B_2
        elseif table_name == "B_3" then
            config_table = B_3
        elseif table_name == "B_4" then
            config_table = B_4
        elseif table_name == "B_5" then
            config_table = B_5
        elseif table_name == "B_6" then
            config_table = B_6
        elseif table_name == "B_7" then
            config_table = B_7
        else
            log.error("未知的配置表名:", table_name)
        end

    else
        table_name = "C_" .. tostring(core_num)
        if table_name == "C_1" then
            config_table = C_1
        elseif table_name == "C_2" then
            config_table = C_2
        else
            log.error("未知的配置表名:", table_name)
        end
    end
    log.info("固件版本检测结果:")
    log.info("  核心版本号:", core_number)
    log.info("  配置表名:", table_name)

    return config_table, core_num, table_name, is_ec718hm, is_ec718pm
end

local function module_size(core_number, is_ec718hm, is_ec718pm)
    log.info("第一步：脚本区/fs区大小是否符合预期")
    local rtos_bsp = rtos.bsp()
    local expected_fs_size = nil
    local expected_script_size = nil
    local _, total_blocks1, used_blocks1, block_size1 = io.fsstat("/luadb/")
    local _, total_blocks, used_blocks, block_size = io.fsstat("/")
    local fs_size = (total_blocks * block_size) / 1024
    local script_size = (total_blocks1 * block_size1) / 1024
    if is_ec718hm or string.find(rtos_bsp, "Air8000") then
        -- EC718HM 系列使用 A_size 表
        if A_size[core_number] then
            expected_fs_size = A_size[core_number].fs_size
            expected_script_size = A_size[core_number].script_size
            log.info("使用A_size配置表，版本:", core_number)
        else
            log.warn("A_size表中未找到版本", core_number, "的配置")
        end
    elseif is_ec718pm then
        -- EC718PM 系列使用 B_size 表
        if B_size[core_number] then
            expected_fs_size = B_size[core_number].fs_size
            expected_script_size = B_size[core_number].script_size
            log.info("使用B_size配置表，版本:", core_number)
        else
            log.warn("B_size表中未找到版本", core_number, "的配置")
        end
    else
        if C_size[core_number] then
            expected_fs_size = C_size[core_number].fs_size
            expected_script_size = C_size[core_number].script_size
            log.info("使用C_size配置表，版本:", core_number)
        else
            log.warn("C_size表中未找到版本", core_number, "的配置")
        end
    end

    assert(fs_size == expected_fs_size,
        string.format("%s_%s固件文件系统区大小不符合预期：理论是 %dKB，实际是 %dKB", rtos_bsp,
            core_value, expected_fs_size, fs_size))

    assert(script_size == expected_script_size,
        string.format("%s_%s固件脚本区大小不符合预期：理论是 %dKB，实际是 %dKB", rtos_bsp,
            core_value, expected_script_size, script_size))
    log.info("脚本区/fs区大小符合预期")
    -- return expected_fs_size, expected_script_size
end
function check_core.test_mouble_check()
    local mouble, core_value, _ = rtos.version(true)
    local rtos_bsp = rtos.bsp()
    -- 获取当前固件的配置表
    local current_config, core_number, config_table_name, is_ec718hm, is_ec718pm = getConfigByCore()
    module_size(core_number, is_ec718hm, is_ec718pm)
    log.info("开始固件核心库检查")
    -- 第一步：A与B对比，找出所有缺失的库
    log.info("第一步：检查所有可能库（B表）...")
    local allMissing = findMissingElements(A, B)

    -- 在过滤缺失列表后进行处理：
    -- 第二步：过滤缺失列表，只保留在当前固件中应该存在的库
    log.info("第二步：根据固件配置过滤缺失库...")
    local actualMissing = filterMissingByFirmware(allMissing, current_config)

    -- 第三步：特殊处理，检查audio.tts和lcd.font_opposansm12_chinese是否实际存在
    log.info("第三步：特殊库二次验证...")
    local finalMissing = {}
    for i, libName in ipairs(actualMissing) do
        local shouldRemove = false

        -- 只在库确实在固件定义列表中时才进行特殊检查
        local isInFirmware = false
        for _, firmwareLib in ipairs(current_config) do
            if firmwareLib == libName then
                isInFirmware = true
                break
            end
        end

        if isInFirmware then
            -- 特殊处理audio.tts
            if libName == "audio.tts" then
                -- 先检查audio是否存在
                if audio then
                    if audio.tts then
                        log.info("audio.tts 实际存在，从缺失列表中移除")
                        shouldRemove = true
                    else
                        log.info("audio存在但audio.tts不存在")
                    end
                else
                    log.info("audio不存在，跳过audio.tts检查")
                end
                -- 特殊处理lcd.font_opposansm12_chinese
            elseif libName == "lcd.font_opposansm12_chinese" then
                if lcd and lcd.font_opposansm12_chinese then
                    log.info("lcd.font_opposansm12_chinese 实际存在，从缺失列表中移除")
                    shouldRemove = true
                end
            end
        end

        if not shouldRemove then
            table.insert(finalMissing, libName)
        end
    end

    -- 第四步：根据固件定义只有air8000有ble,其余固件没有

    if is_ec718hm then
        log.info("当前检查的模块为", rtos_bsp)
        if #finalMissing == 1 and finalMissing[1] == "ble" then
            log.info("检测到" .. rtos_bsp .. "的设备，仅缺失ble库，忽略并视为通过检查")
            log.info(rtos_bsp .. "_" .. core_value .. "固件" .. "要求的所有库都存在")
        else
            assert(false, string.format(rtos_bsp .. "设备异常缺失库: %s", table.concat(finalMissing, ", ")))
        end
    else
        log.info("当前检查的模块为", rtos_bsp)
        if #finalMissing == 0 then
            log.info(rtos_bsp .. "_" .. core_value .. "固件" .. "要求的所有库都存在")
        else
            -- 构建详细的错误信息
            local error_msg = rtos_bsp .. "_" .. core_value .. "固件" .. "缺失以下" .. #finalMissing ..
                                  "个库:\n"
            for i, element in ipairs(finalMissing) do
                error_msg = error_msg .. "  " .. i .. ". " .. element .. "\n"
            end
            assert(false, error_msg)
        end

    end
    log.info("✓ 库检查完成")
end
return check_core

