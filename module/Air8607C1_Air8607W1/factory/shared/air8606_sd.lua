-- Air8606 的 TF 卡长期挂在 /sd/，供文件管理和应用工厂共用。
local M = {}
local mount_point = "/sd/"

function M.is_mounted()
    local ok, _, _, _, fs = io.fsstat(mount_point)
    return ok and fs == "fatfs"
end

function M.mount(cfg)
    if M.is_mounted() then return true end
    local id, cs, hz = cfg.spi_id or 1, cfg.pin_cs or 8, cfg.speed or 10000000
    log.info("air8606_sd", "mount SPI", id, "CS", cs, "Hz", hz)
    if not gpio.setup(cs, 1) then return false, "TF 片选脚初始化失败" end
    local code = spi.setup(id, 255, 0, 0, 8, 400000)
    if code ~= 0 then return false, "SPI 初始化失败 " .. tostring(code) end
    -- SD_EN 已由上电序列拉高；探测卡失败也必须保留卡上的原数据。
    local ok, err = fatfs.mount(fatfs.SPI, mount_point, id, cs, hz, nil, 1, false)
    if not ok then
        spi.close(id)
        return false, "TF 挂载失败 " .. tostring(err) .. "，请插入 FAT 格式卡后重试"
    end
    if not M.is_mounted() then
        fatfs.unmount(mount_point)
        spi.close(id)
        return false, "TF 挂载点未注册"
    end
    return true
end

function M.verify(cfg)
    local ok, err = M.mount(cfg)
    if not ok then return false, err end
    -- f_mkdir 对已存在的名称返回失败。只有成功创建私有目录才打开写文件。
    local dir
    for offset = 0, 7 do
        local candidate = string.format("%sT%07X", mount_point, (mcu.ticks() + offset) & 0x0fffffff)
        if io.mkdir(candidate) then dir = candidate; break end
        if not io.exists(candidate) then break end
    end
    if not dir then return false, "无法创建临时目录，请检查卡和可用空间" end
    local path = dir .. "/CHECK.BIN"
    local file, created
    local function pattern(i)
        return string.rep(string.char(i, 0x5a, 0, 0xa5), 128)
    end
    local verified, detail = pcall(function()
        file = assert(io.open(path, "wb"), "无法创建测试文件")
        created = true
        for i = 1, 16 do assert(file:write(pattern(i)), "TF 写入失败") end
        assert(file:close(), "TF 写入关闭失败")
        file = assert(io.open(path, "rb"), "无法重新打开测试文件")
        for i = 1, 16 do assert(file:read(512) == pattern(i), "TF 读回内容不一致") end
        assert(file:read(1) == nil, "TF 读回长度不一致")
        assert(file:close(), "TF 读取关闭失败")
        file = nil
    end)
    if file then pcall(file.close, file) end
    if created and not os.remove(path) then return false, "测试文件清理失败 " .. path end
    if not io.rmdir(dir) then return false, "临时目录清理失败 " .. dir end
    if not verified then return false, tostring(detail) end
    return true, "已写入并逐字节读回 8192 字节，测试文件已删除"
end

return M
