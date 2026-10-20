--[[
@module  prod_retest
@summary 正常模式下的返工入口（V3）
@version 1.0.0
@date    2026.10.19
@usage
本模块只在正常模式加载，占用 USB 虚拟串口 uart.VUART_0（115200 8N1），
仅响应两条返工相关指令，其余指令一律忽略（不影响正常业务）：

  MODEL_RETEST,CONFIRM#   写入返工标记 retest_flag，回 OK# 后重启进入产测模式
  MODEL_RETEST?#          查询返工标记，回 true# / false#

魔法字 CONFIRM 去首尾空格后全匹配、区分大小写。
]]

local usbTrans = uart.VUART_0
local rxCache = ""

local function trim(s)
    return (tostring(s or ""):gsub("^%s*", ""):gsub("%s*$", ""))
end

local function handle(text)
    -- text 不含结尾的 #
    local h2 = text:find(",")
    local cmd, data
    if h2 then
        cmd = text:sub(1, h2 - 1)
        data = text:sub(h2 + 1)
    else
        cmd = text
    end
    cmd = trim(cmd):upper()

    if cmd == "MODEL_RETEST" then
        local magic = trim(data)
        if magic ~= "CONFIRM" then
            log.error("prod_retest", "MODEL_RETEST 魔法字错误:", magic)
            uart.write(usbTrans, "ERROR#")
            return
        end
        fskv.set("retest_flag", true)
        log.info("prod_retest", "收到返工指令，写入返工标记，重启进入产测模式")
        uart.write(usbTrans, "OK#")
        sys.timerStart(pm.reboot, 500)  -- 延时确保 OK# 发出
    elseif cmd == "MODEL_RETEST?" then
        uart.write(usbTrans, (fskv.get("retest_flag") and "true" or "false") .. "#")
    end
    -- 其余指令忽略，保持正常模式业务不受影响
end

uart.setup(usbTrans, 115200)

uart.on(usbTrans, "receive", function(id, len)
    while true do
        local data = uart.read(usbTrans, 512)
        if not data or #data == 0 then break end
        rxCache = rxCache .. data
    end
    while true do
        local h1 = rxCache:find("#")
        if not h1 then break end
        local text = rxCache:sub(1, h1 - 1)
        rxCache = rxCache:sub(h1 + 1)
        handle(text)
    end
end)

log.info("prod_retest", "返工入口已就绪", usbTrans)
