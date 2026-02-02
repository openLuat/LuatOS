local hmeta_test = {}

local device_name = rtos.bsp()
local model_name
local hwver_name
local chip_name

function judge_device()
    if device_name == "Air780EHM" then
        model_name = "Air780EHM"
        chip_name = "EC718HM"
    elseif device_name == "Air780EPM" then
        model_name = "Air780EPM"
        chip_name = "EC718PM"
    elseif device_name == "Air780EHV" then
        model_name = "Air780EHV"
        chip_name = "EC718HM"
    elseif device_name == "Air780EGH" then
        model_name = "Air780EGH"
        chip_name = "EC718HM"
    elseif device_name == "Air8000" then
        model_name = {"Air8000", "Air8000A"}
        chip_name = "EC718HM"
    elseif device_name == "Air780EGG" then
        model_name = "Air780EGG"
        chip_name = "EC718HM"
    elseif device_name == "Air780EGP" then
        model_name = "Air780EGP"
        chip_name = "EC718PM"
    elseif device_name == "Air700ECP" then
        model_name = "Air700ECP"
        chip_name = "EC718PM"
        -- elseif device_name == "Air700ECH" then
        --     model_name = "Air700ECH"
        --     chip_name = "EC718PM"
    elseif device_name == "Air8101" then
        model_name = "Air8101"
        chip_name = "BK7258"
    elseif device_name == "EC618" then
        model_name = "Air780E"
        chip_name = "EC618"
    elseif device_name == "Air780EP" then
        model_name = "Air780EP"
        chip_name = "EC718P"
    elseif device_name == "Air795UG" then
        model_name = "Air795UG"
        chip_name = "UIS8910"
    else
        log.info("未知的设备名称")
    end

end

function hmeta_test.test_model_demo()
    judge_device()

    local hmeta_model = hmeta.model()
    log.info("hmeta_model名称", hmeta_model)

    if device_name == "Air8000" then
        local found = false
        for _, name in ipairs(model_name) do
            if hmeta_model == name then
                found = true
                break
            end
        end
        assert(found == true, string.format("获取模组名称测试失败: 预期 %s, 实际 %s",
            table.concat(model_name, " 或 "), hmeta_model))
        log.info("hmeta_test", "获取模组名称测试通过")
    else
        assert(hmeta_model == model_name,
            string.format("获取模组名称测试失败: 预期 %s, 实际 %s", model_name, hmeta_model))
        log.info("hmeta_test", "获取模组名称测试通过")
    end
end

function hmeta_test.test_hwver_demo()
    local hmeta_hwver = hmeta.hwver()
    log.info("hmeta_hwver版本", hmeta_hwver)

    local has_letter_a = string.find(string.upper(hmeta_hwver), "A") ~= nil
    assert(has_letter_a == true,
        string.format(
            "获取模组的硬件版本号测试失败: 返回值中未包含预期值：'A'，实际值: %s",
            hmeta_hwver))

    -- 提取所有数字（处理可能的小数点情况）
    local version_str = string.match(hmeta_hwver, "[Aa]([%d%.]+)")
    if not version_str then
        -- 尝试其他格式：数字可能在A前面或后面
        version_str = string.match(hmeta_hwver, "([%d%.]+)[Aa]") or string.match(hmeta_hwver, "([%d%.]+)")
    end
    local version_number = version_str and tonumber(version_str)
    -- 检查数字部分是否大于10
    local hwver_result = version_number and version_number >= 1
    assert(hwver_result == true,
        string.format("获取模组的硬件版本号测试失败: 数字部分应大于1，实际值: %s ",
            hmeta_hwver, version_number or "无效"))

    log.info("hmeta_test", "获取模组的硬件版本号测试完全通过")
end

function hmeta_test.test_chip_demo()
    judge_device()
    local hmeta_chip = hmeta.chip()
    log.info("hmeta_chip名称", hmeta_chip)
    assert(hmeta_chip == chip_name,
        string.format("获取芯片名称测试失败: 预期 %s, 实际 %s", chip_name, hmeta_chip))
    log.info("hmeta_test", "获取芯片名称测试通过")
end

return hmeta_test
