-- WebP解码器基础测试
-- 测试 LUAT_USE_WEBP 宏开启后的解码功能
-- 注意: lcd.showImage 需要 GUI 模式初始化 lcd, 非 GUI 模式下测试 API 可达性和稳定性

local webp_tests = {}

-- 1x1 白色像素的最小有效 WebP 文件 (44字节, 有损格式)
local WEBP_1x1 = "\x52\x49\x46\x46\x24\x00\x00\x00\x57\x45\x42\x50\x56\x50\x38\x20"
              .. "\x17\x00\x00\x00\x30\x01\x00\x9d\x01\x2a\x01\x00\x01\x00\x02\x00"
              .. "\x34\x25\x9f\x03\x70\x00\xfe\xfb\x94\x00\x00\x00"

local WEBP_TEST_PATH = "/tmp/test_webp_basic.webp"

-- 写测试 WebP 文件到 VFS
local function write_test_webp()
    local f = io.open(WEBP_TEST_PATH, "wb")
    if not f then
        return false, "无法创建测试文件: " .. WEBP_TEST_PATH
    end
    f:write(WEBP_1x1)
    f:close()
    return true
end

-- 测试1: lcd 模块可达性 (非 GUI 模式下跳过)
function webp_tests.test_lcd_module_reachable()
    log.info("webp_test", "检查 lcd 模块可达性")
    if type(lcd) ~= "userdata" and type(lcd) ~= "table" then
        log.info("webp_test", "lcd 模块未加载 (非 GUI 模式), 跳过")
        -- 非 GUI 模式下此测试以无报错通过
        return
    end
    assert(type(lcd.showImage) == "function", "lcd.showImage 不是函数")
    log.info("webp_test", "lcd.showImage 可达: OK")
end

-- 测试2: lcd.showImage 传入 .webp 文件不崩溃 (LCD 未初始化时应返回 nil/false)
function webp_tests.test_showimage_webp_no_crash()
    log.info("webp_test", "测试 lcd.showImage 对 .webp 文件不崩溃")
    if type(lcd) ~= "userdata" and type(lcd) ~= "table" then
        log.info("webp_test", "lcd 模块未加载, 跳过")
        return
    end

    local ok, err = write_test_webp()
    assert(ok, "写测试文件失败: " .. tostring(err))

    -- LCD 未初始化时 showImage 应返回 nil 或 false, 不能 crash
    local ok2, result = pcall(lcd.showImage, 0, 0, WEBP_TEST_PATH)
    assert(ok2, "lcd.showImage 抛出异常: " .. tostring(result))
    log.info("webp_test", "lcd.showImage 未崩溃, 返回: " .. tostring(result))
end

-- 测试3: lcd.showImage 对不支持的格式返回 false (不崩溃)
function webp_tests.test_showimage_unsupported_ext_no_crash()
    log.info("webp_test", "测试 lcd.showImage 对不支持格式不崩溃")
    if type(lcd) ~= "userdata" and type(lcd) ~= "table" then
        log.info("webp_test", "lcd 模块未加载, 跳过")
        return
    end
    local ok, result = pcall(lcd.showImage, 0, 0, "/tmp/not_exist.bmp")
    assert(ok, "lcd.showImage 对不支持格式抛出异常: " .. tostring(result))
    log.info("webp_test", "lcd.showImage 对不支持格式未崩溃: OK")
end

-- 测试4: 写入测试 WebP 文件并验证内容长度
function webp_tests.test_write_webp_file()
    log.info("webp_test", "测试写入 WebP 测试文件")
    local ok, err = write_test_webp()
    assert(ok, tostring(err))

    local f = io.open(WEBP_TEST_PATH, "rb")
    assert(f, "无法打开写入的测试文件")
    local data = f:read("*a")
    f:close()

    assert(#data == #WEBP_1x1, string.format("文件大小不匹配: 期望 %d, 实际 %d", #WEBP_1x1, #data))
    -- 验证 RIFF 魔术字节
    assert(data:sub(1, 4) == "RIFF", "RIFF 头部校验失败")
    assert(data:sub(9, 12) == "WEBP", "WEBP 头部校验失败")
    log.info("webp_test", "WebP 文件写入验证: OK, 大小=" .. #data)
end

return webp_tests
