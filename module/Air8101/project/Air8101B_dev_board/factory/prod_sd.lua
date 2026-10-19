--[[
@module  prod_sd
@summary 产测项 SD_TEST#：SD 卡挂载 + 写文件 + 读回校验
@usage   SD_TEST#（需插卡 + VBAT_SD 拨码打开）
@return  string —— "OK" / "ERROR"
说明
1. 使能 SD_EN(GPIO50) 后按 SDIO 方式挂载到 /sd；
2. 写固定内容再读回比对，比完删临时文件；
3. 测完卸载，避免影响后续测试。
]]

local MOUNT        = "/sd"
local TEST_FILE    = MOUNT .. "/factory_test.txt"
local TEST_CONTENT = "Air8101B_SD_TEST_OK"

return function(arg)
    local c = _G.project_config.hw.sd
    gpio.setup(c.en, 1)     -- SD_EN 供电
    sys.wait(50)

    local mounted = fatfs.mount(fatfs.SDIO, MOUNT, 24000)
    if not mounted then
        log.error("prod_sd", "SD 挂载失败（确认已插卡、VBAT_SD 拨码已打开）")
        return "ERROR"
    end

    local result = "ERROR"
    local f = io.open(TEST_FILE, "wb")
    if f then
        f:write(TEST_CONTENT)
        f:close()

        local content
        f = io.open(TEST_FILE, "rb")
        if f then
            content = f:read("*a")
            f:close()
        end

        if content == TEST_CONTENT then
            result = "OK"
        else
            log.error("prod_sd", "读写校验不一致，读回:", tostring(content))
        end
    else
        log.error("prod_sd", "测试文件创建失败:", TEST_FILE)
    end

    -- 收尾：清文件 + 卸载
    pcall(os.remove, TEST_FILE)
    pcall(fatfs.unmount, MOUNT)
    log.info("prod_sd", "SD 已卸载，结果:", result)

    return result
end
