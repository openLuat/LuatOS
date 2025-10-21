-- require "test"
-- testdbug = require("testdebug")
-- require "excloud"
checks_function = {}
local M = {}
local A = _G
local core,core_version = rtos.version(_,true)
log.info(core,core_version)
-- 0号版本，所有库都有的table，方便新库的增加时候的检查
local B = {"airui", "lvgl", "cc", "audio.tts", "airtalk", "camera", "codec", "fastlz", "fatfs", "gtfont", "lf",
           "lcd.font_opposansm12_chinese", "codec", "audio", "i2s", "ble", "libgnss", "sfud", "yhm27xx", "ymodem",
           "otp", "adc", "airlink", "bit64", "can", "crypto", "eink", "errDump", "fonts", "fota", "fskv", "ftp",
           "gmssl", "gpio", "hmeta", "ht1621", "http", "httpsrv", "i2c", "iconv", "io", "ioqueue", "iotauth", "iperf",
           "json", "lcd", "log", "lora2", "mcu", "miniz", "mobile", "mqtt", "modbus", "netdrv", "onewire", "os", "pack",
           "pins", "pm", "protobuf", "pwm", "rsa", "rtc", "rtos", "sms", "socket", "spi", "string", "sys", "sysplus",
           "tp", "u8g2", "uart", "wdt", "websocket", "wlan", "xxtea", "zbuff"}


-- 1号固件
local A_1 = {"cc", "camera", "codec", "fastlz", "fatfs", "gtfont", "lf", 
             "codec", "audio", "i2s", "libgnss", "sfud", "yhm27xx", "ymodem", "otp", "adc", "airlink", "bit64",
             "can", "crypto", "eink", "errDump", "fonts", "fota", "fskv", "ftp", "gmssl", "gpio", "hmeta", "ht1621",
             "http", "httpsrv", "i2c", "iconv", "io", "ioqueue", "iotauth", "iperf", "json", "lcd", "log", "lora2",
             "mcu", "miniz", "mobile", "mqtt", "modbus", "netdrv", "onewire", "os", "pack", "pins", "pm", "protobuf",
             "pwm", "rsa", "rtc", "rtos", "sms", "socket", "spi", "string", "sys", "sysplus", "tp", "u8g2", "uart",
             "wdt", "websocket", "wlan", "xxtea", "zbuff"}


-- 2号固件
local A_2 = {"airui", "lvgl", "camera", "codec", "fastlz", "fatfs", "gtfont", "lf", "lcd.font_opposansm12_chinese",
             "codec", "audio", "i2s", "ble", "libgnss", "sfud", "yhm27xx", "ymodem", "otp", "adc", "airlink", "bit64",
             "can", "crypto", "eink", "errDump", "fonts", "fota", "fskv", "ftp", "gmssl", "gpio", "hmeta", "ht1621",
             "http", "httpsrv", "i2c", "iconv", "io", "ioqueue", "iotauth", "iperf", "json", "lcd", "log", "lora2",
             "mcu", "miniz", "mobile", "mqtt", "modbus", "netdrv", "onewire", "os", "pack", "pins", "pm", "protobuf",
             "pwm", "rsa", "rtc", "rtos", "sms", "socket", "spi", "string", "sys", "sysplus", "tp", "u8g2", "uart",
             "wdt", "websocket", "wlan", "xxtea", "zbuff"}


-- 3号固件
local A_3 = {"airui", "lvgl", "audio.tts", "camera", "codec", "fastlz", "fatfs", "gtfont", "lf",
             "lcd.font_opposansm12_chinese", "codec", "audio", "i2s", "ble", "libgnss", "sfud", "yhm27xx", "ymodem",
             "otp", "adc", "airlink", "bit64", "can", "crypto", "eink", "errDump", "fonts", "fota", "fskv", "ftp",
             "gmssl", "gpio", "hmeta", "ht1621", "http", "httpsrv", "i2c", "iconv", "io", "ioqueue", "iotauth", "iperf",
             "json", "lcd", "log", "lora2", "mcu", "miniz", "mobile", "mqtt", "modbus", "netdrv", "onewire", "os",
             "pack", "pins", "pm", "protobuf", "pwm", "rsa", "rtc", "rtos", "sms", "socket", "spi", "string", "sys",
             "sysplus", "tp", "u8g2", "uart", "wdt", "websocket", "wlan", "xxtea", "zbuff"}


-- 4号固件
local A_4 = {"airui", "lvgl", "airtalk", "camera", "codec", "fastlz", "fatfs", "gtfont", "lf",
             "lcd.font_opposansm12_chinese", "codec", "audio", "i2s", "ble", "libgnss", "sfud", "yhm27xx", "ymodem",
             "otp", "adc", "airlink", "bit64", "can", "crypto", "eink", "errDump", "fonts", "fota", "fskv", "ftp",
             "gmssl", "gpio", "hmeta", "ht1621", "http", "httpsrv", "i2c", "iconv", "io", "ioqueue", "iotauth", "iperf",
             "json", "lcd", "log", "lora2", "mcu", "miniz", "mobile", "mqtt", "modbus", "netdrv", "onewire", "os",
             "pack", "pins", "pm", "protobuf", "pwm", "rsa", "rtc", "rtos", "sms", "socket", "spi", "string", "sys",
             "sysplus", "tp", "u8g2", "uart", "wdt", "websocket", "wlan", "xxtea", "zbuff"}

-- 5号固件
local A_5 = {"audio.tts", "airtalk", "camera", "codec", "fastlz", "fatfs", "gtfont", "lf",
             "lcd.font_opposansm12_chinese", "codec", "audio", "i2s", "ble", "libgnss", "sfud", "yhm27xx", "ymodem",
             "otp", "adc", "airlink", "bit64", "can", "crypto", "eink", "errDump", "fonts", "fota", "fskv", "ftp",
             "gmssl", "gpio", "hmeta", "ht1621", "http", "httpsrv", "i2c", "iconv", "io", "ioqueue", "iotauth", "iperf",
             "json", "lcd", "log", "lora2", "mcu", "miniz", "mobile", "mqtt", "modbus", "netdrv", "onewire", "os",
             "pack", "pins", "pm", "protobuf", "pwm", "rsa", "rtc", "rtos", "sms", "socket", "spi", "string", "sys",
             "sysplus", "tp", "u8g2", "uart", "wdt", "websocket", "wlan", "xxtea", "zbuff"}

-- 6号固件
local A_6 = {"airui", "lvgl", "camera", "codec", "fastlz", "fatfs", "gtfont", "lf", "lcd.font_opposansm12_chinese",
             "codec", "audio", "i2s", "ble", "libgnss", "sfud", "yhm27xx", "ymodem", "otp", "adc", "airlink", "bit64",
             "can", "crypto", "eink", "errDump", "fonts", "fota", "fskv", "ftp", "gmssl", "gpio", "hmeta", "ht1621",
             "http", "httpsrv", "i2c", "iconv", "io", "ioqueue", "iotauth", "iperf", "json", "lcd", "log", "lora2",
             "mcu", "miniz", "mobile", "mqtt", "modbus", "netdrv", "onewire", "os", "pack", "pins", "pm", "protobuf",
             "pwm", "rsa", "rtc", "rtos", "sms", "socket", "spi", "string", "sys", "sysplus", "tp", "u8g2", "uart",
             "wdt", "websocket", "wlan", "xxtea", "zbuff"}

-- 7号固件
local A_7 = {"audio.tts", "camera", "codec", "fastlz", "fatfs", "gtfont", "lf", "lcd.font_opposansm12_chinese", "codec",
             "audio", "i2s", "ble", "libgnss", "sfud", "yhm27xx", "ymodem", "otp", "adc", "airlink", "bit64", "can",
             "crypto", "eink", "errDump", "fonts", "fota", "fskv", "ftp", "gmssl", "gpio", "hmeta", "ht1621", "http",
             "httpsrv", "i2c", "iconv", "io", "ioqueue", "iotauth", "iperf", "json", "lcd", "log", "lora2", "mcu",
             "miniz", "mobile", "mqtt", "modbus", "netdrv", "onewire", "os", "pack", "pins", "pm", "protobuf", "pwm",
             "rsa", "rtc", "rtos", "sms", "socket", "spi", "string", "sys", "sysplus", "tp", "u8g2", "uart", "wdt",
             "websocket", "wlan", "xxtea", "zbuff"}


-- 8号固件
local A_8 = {"cc", "camera", "codec", "fastlz", "fatfs", "gtfont", "lf", "lcd.font_opposansm12_chinese", "codec",
             "audio", "i2s", "ble", "libgnss", "sfud", "yhm27xx", "ymodem", "otp", "adc", "airlink", "bit64", "can",
             "crypto", "eink", "errDump", "fonts", "fota", "fskv", "ftp", "gmssl", "gpio", "hmeta", "ht1621", "http",
             "httpsrv", "i2c", "iconv", "io", "ioqueue", "iotauth", "iperf", "json", "lcd", "log", "lora2", "mcu",
             "miniz", "mobile", "mqtt", "modbus", "netdrv", "onewire", "os", "pack", "pins", "pm", "protobuf", "pwm",
             "rsa", "rtc", "rtos", "sms", "socket", "spi", "string", "sys", "sysplus", "tp", "u8g2", "uart", "wdt",
             "websocket", "wlan", "xxtea", "zbuff"}

-- 9号固件
local A_9 = {"airtalk", "camera", "codec", "fastlz", "fatfs", "gtfont", "lf", "lcd.font_opposansm12_chinese", "codec",
             "audio", "i2s", "ble", "libgnss", "sfud", "yhm27xx", "ymodem", "otp", "adc", "airlink", "bit64", "can",
             "crypto", "eink", "errDump", "fonts", "fota", "fskv", "ftp", "gmssl", "gpio", "hmeta", "ht1621", "http",
             "httpsrv", "i2c", "iconv", "io", "ioqueue", "iotauth", "iperf", "json", "lcd", "log", "lora2", "mcu",
             "miniz", "mobile", "mqtt", "modbus", "netdrv", "onewire", "os", "pack", "pins", "pm", "protobuf", "pwm",
             "rsa", "rtc", "rtos", "sms", "socket", "spi", "string", "sys", "sysplus", "tp", "u8g2", "uart", "wdt",
             "websocket", "wlan", "xxtea", "zbuff"}

-- 10号固件
local A_10 = {"camera", "codec", "fastlz", "fatfs", "gtfont", "lf", "lcd.font_opposansm12_chinese", "codec", "audio",
              "i2s", "ble", "libgnss", "sfud", "yhm27xx", "ymodem", "otp", "adc", "airlink", "bit64", "can", "crypto",
              "eink", "errDump", "fonts", "fota", "fskv", "ftp", "gmssl", "gpio", "hmeta", "ht1621", "http", "httpsrv",
              "i2c", "iconv", "io", "ioqueue", "iotauth", "iperf", "json", "lcd", "log", "lora2", "mcu", "miniz",
              "mobile", "mqtt", "modbus", "netdrv", "onewire", "os", "pack", "pins", "pm", "protobuf", "pwm", "rsa",
              "rtc", "rtos", "sms", "socket", "spi", "string", "sys", "sysplus", "tp", "u8g2", "uart", "wdt",
              "websocket", "wlan", "xxtea", "zbuff"}

-- 11号固件
local A_11 = {"codec", "audio", "i2s", "ble", "libgnss", "sfud", "yhm27xx", "ymodem", "otp", "adc", "airlink", "bit64",
              "can", "crypto", "eink", "errDump", "fonts", "fota", "fskv", "ftp", "gmssl", "gpio", "hmeta", "ht1621",
              "http", "httpsrv", "i2c", "iconv", "io", "ioqueue", "iotauth", "iperf", "json", "lcd", "log", "lora2",
              "mcu", "miniz", "mobile", "mqtt", "modbus", "netdrv", "onewire", "os", "pack", "pins", "pm", "protobuf",
              "pwm", "rsa", "rtc", "rtos", "sms", "socket", "spi", "string", "sys", "sysplus", "tp", "u8g2", "uart",
              "wdt", "websocket", "wlan", "xxtea", "zbuff"}

-- 12号固件
local A_12 = A_11

-- 13号固件
local A_13 = {"airui", "audio.tts", "camera", "codec", "fastlz", "fatfs", "gtfont", "lf", "codec", "audio", "i2s",
              "ble", "libgnss", "sfud", "yhm27xx", "ymodem", "otp", "adc", "airlink", "bit64", "can", "crypto", "eink",
              "errDump", "fonts", "fota", "fskv", "ftp", "gmssl", "gpio", "hmeta", "ht1621", "http", "httpsrv", "i2c",
              "iconv", "io", "ioqueue", "iotauth", "iperf", "json", "lcd", "log", "lora2", "mcu", "miniz", "mobile",
              "mqtt", "modbus", "netdrv", "onewire", "os", "pack", "pins", "pm", "protobuf", "pwm", "rsa", "rtc",
              "rtos", "sms", "socket", "spi", "string", "sys", "sysplus", "tp", "u8g2", "uart", "wdt", "websocket",
              "wlan", "xxtea", "zbuff"}

local BIG64 = 9223372036854775807
local last_element = {}
local version_error_message = nil
local skipp_mlement = {}

-- 101号固件
local A_101 = A_1
A_101.BIG64 = BIG64

-- 102号固件
local A_102 = A_2
A_102.BIG64 = BIG64

-- 103号固件
local A_103 = A_3
A_103.BIG64 = BIG64

-- 104号固件
local A_104 = A_4
A_104.BIG64 = BIG64

-- 105号固件
local A_105 = A_5
A_105.BIG64 = BIG64

-- 106号固件
local A_106 = A_6
A_106.BIG64 = BIG64

-- 107号固件
local A_107 = A_7
A_107.BIG64 = BIG64

-- 108号固件
local A_108 = A_8
A_108.BIG64 = BIG64

-- 109号固件
local A_109 = A_9
A_109.BIG64 = BIG64

-- 110号固件
local A_110 = A_10
A_110.BIG64 = BIG64

-- 111号固件
local A_111 = A_11
A_111.BIG64 = BIG64

-- 112号固件
local A_112 = A_12
A_112.BIG64 = BIG64

-- 113号固件
local A_113 = A_13
A_113.BIG64 = BIG64

local function checkSubmodule(mainModule, submodule)
    if type(mainModule) ~= "table" then
        return false, "Main module is not a table"
    end

    return mainModule[submodule] ~= nil
end

local function findMissingElements(aTable, bTable)
    local missingElements = {}

    for _, bKey in ipairs(bTable) do
        log.info("当前检查的库为：", bKey)
        sys.wait(200)
        -- 检查 B 表中的键是否存在于 A 表中
        if aTable[bKey] == nil then
            log.info(bKey .. "库不存在")
            table.insert(missingElements, bKey)
            sys.wait(200)
        else
            log.info("库" .. bKey .. "存在")
        end
    end
    return missingElements
end


sys.taskInit(function()
    sys.wait(3000)
    local user_table = A_1
    local missingInA = findMissingElements(A, user_table)
    
    -- 打印结果

    log.info("_G中缺失的核心库名称:")
    if #missingInA == 0 then
        print("当前固件符合预期")
        local missingInB = findMissingElements(A, B) -- 用于判断哪些库不用测
        
        if #missingInB == 0 then 
            log.info("没有需要跳过的测试")
        else
            for j, elem in ipairs(missingInB) do
                -- log.info(j .. ". ", elem)
                table.insert(skipp_elem, elem)
                log.info("skipp_element",json.encode(skipp_elem))
            end  
        end
        -- table.insert(skipp_elem, skipp_element)
        -- 发布消息应该在所有处理完成后
        sys.publish("counte_test")
       
    else
        log.info("固件不符合预期")
        for i, element in ipairs(missingInA) do
            -- log.info(i .. ". ", element)
            table.insert(last_element, element)
            version_error_message = "核心库检测失败,终止后续测试"
        end
        excloud_message.device_status.error_message.send_message = version_error_message
        table.insert(excloud_message.device_status.error_message.last_element, last_element)
    end
end)
