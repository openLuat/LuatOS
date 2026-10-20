--[[
@module  prod_i2c
@summary 产测项 I2C_SCAN#：探测 I2C1 上的 GT911 触摸 IC（与排针共用同一条总线）
@usage
  I2C_SCAN#        只精确探测 GT911 的两个可能地址（默认，快且不刷屏）
  I2C_SCAN,all#    全总线扫描 0x08~0x77（排查总线异常时用，会打印较多失败日志）
@return  string —— "OK" / "ERROR"
判据
- PASS：探到 GT911（0x5D 或 0x14，由 INT 上电电平决定）→ 总线通、触摸 IC 在位；
- FAIL：没探到 → 总线被拉死 / 触摸 IC 未焊 / 供电异常 / 排线未接。
说明
总线句柄统一走 drv_i2c（默认软件 I2C：GPIO38/39）。
Air8101 硬件 I2C1 默认在 GPIO0/1（那是 UART1 的脚），实测 pinmux 切不过来。
]]

local GT911 = { [0x5D] = true, [0x14] = true }

return function(arg)
    local c   = _G.project_config.hw.tp
    local dev = require("drv_i2c").get()

    -- 单地址探测：i2c.send 返回 true 表示从机 ACK
    local function probe(addr)
        local r = i2c.send(dev, addr, "")
        return r and true or false
    end

    local full_scan = (type(arg) == "string" and arg:lower() == "all")
    local list, has_gt911 = {}, false

    if full_scan then
        for addr = 0x08, 0x77 do
            if pcall(probe, addr) and probe(addr) then
                list[#list + 1] = addr
            end
        end
        for _, addr in ipairs(list) do
            if GT911[addr] then has_gt911 = true end
        end
    else
        for _, addr in ipairs(c.addr_list or { 0x5D, 0x14 }) do
            if pcall(probe, addr) and probe(addr) then
                has_gt911 = true
                list[#list + 1] = addr
            end
        end
    end

    local names = {}
    for _, addr in ipairs(list) do
        names[#names + 1] = string.format("0x%02X", addr)
    end
    local found_str = (#names > 0) and table.concat(names, ",") or "无"
    log.info("prod_i2c", "扫描方式:", full_scan and "全总线" or "精确", "结果:", found_str)

    if not has_gt911 then
        log.error("prod_i2c", "未探到 GT911(0x5D/0x14)")
        return "ERROR"
    end
    return "OK"
end
