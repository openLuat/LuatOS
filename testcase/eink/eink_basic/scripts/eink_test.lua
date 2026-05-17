local eink_tests = {}

local eink = _G.eink
local u8g2 = _G.u8g2

function eink_tests.test_model_2in13_padded_width_smoke()
    log.info("eink_test", "验证 122px 宽的 2.13 寸墨水屏在 PC 模拟器下的基础回归路径")

    assert(eink ~= nil, "_G.eink 不可用")
    assert(u8g2 ~= nil, "_G.u8g2 不可用")
    assert(type(spi) == "table" or type(spi) == "userdata", "spi 模块不可用")
    assert(eink.MODEL_2in13 ~= nil, "eink.MODEL_2in13 不可用")

    local ok_spi, spi_result = pcall(spi.setup, 0, nil, 0, 0, 8, 1000000)
    assert(ok_spi, "spi.setup 抛出异常: " .. tostring(spi_result))
    assert(spi_result == 0, "spi.setup 返回失败: " .. tostring(spi_result))

    local ok_model, model_result = pcall(eink.model, eink.MODEL_2in13)
    assert(ok_model, "eink.model 抛出异常: " .. tostring(model_result))

    local ok_setup, setup_result = pcall(eink.setup, 0, 0, 1, 2, 3, 4)
    assert(ok_setup, "eink.setup 抛出异常: " .. tostring(setup_result))
    assert(setup_result, "eink.setup 返回失败: " .. tostring(setup_result))

    local width, height, rotate = eink.getWin()
    assert(width == 128, "eink.MODEL_2in13 缓冲区宽度应补齐到 128, 实际为 " .. tostring(width))
    assert(width % 8 == 0, "补齐后的缓冲区宽度应为8对齐")
    assert(type(height) == "number" and height > 0, "eink.getWin height 非法: " .. tostring(height))
    assert(type(rotate) == "number", "eink.getWin rotate 非法: " .. tostring(rotate))

    local ok_clear, clear_result = pcall(eink.clear, 1, true)
    assert(ok_clear, "eink.clear 抛出异常: " .. tostring(clear_result))
    assert(clear_result, "eink.clear 返回失败: " .. tostring(clear_result))

    local ok_show, show_result = pcall(eink.show, 0, 0, true)
    assert(ok_show, "eink.show 抛出异常: " .. tostring(show_result))
    assert(show_result, "eink.show 返回失败: " .. tostring(show_result))
end

return eink_tests
