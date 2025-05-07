local pcb = {}
-- OTP 存储区
local otpZone = 2
-- 默认版本号
local hversion = "1.0.3"
-- 出厂测试结果
local test = false

-- 读取 OTP 存储区参数，解析硬件版本号
local function loadParam()
    if not otp then
        return
    end
    local len = otp.read(otpZone, 0, 1)
    local otpdata = otp.read(otpZone, 1, string.byte(len))
    -- log.info("OTP数据", otpdata)
    local obj, result, errMsg = json.decode(otpdata)
    if result ~= 1 or not obj or not obj.pcb then
        if hmeta and hmeta.model():find("EPXV") then
            hversion = "1.0.2"
        end
    elseif obj then
        test = obj.test
        hversion = obj.pcb
    end
    log.info("pcb", hversion, obj and obj.pcb, obj and obj.test)
end
loadParam()

-- GNSS 电源控制
function pcb.gnssPower(onoff)
    if hversion == "1.0.2" then
        gpio.setup(2, onoff and 1 or 0)
        gpio.setup(26, onoff and 1 or 0)
        gpio.setup(27, onoff and 1 or 0)
    else
        gpio.setup(25, onoff and 1 or 0)
        gpio.setup(26, onoff and 1 or 0)
    end
end

-- ES8311 电源引脚
function pcb.es8311PowerPin()
    if hversion == "1.0.2" then
        return 25
    else
        return 2
    end
end

-- 充电IC CMD引脚
function pcb.chargeCmdPin()
    if hversion == "1.0.2" then
        return 20
    else
        return 27
    end
end

-- 工厂是否出厂测试
function pcb.test()
    return test
end


function pcb.hver()
    return hversion
end

function pcb.sethver(ver)
    hversion = ver
end
return pcb