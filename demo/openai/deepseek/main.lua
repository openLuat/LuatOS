-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "deepseek"
VERSION = "1.0.0"

sys = require "sys"
require "sysplus"
openai = require "openai"

local opts = {
    apikey = "sk-123456",
    apiurl = "https://api.deepseek.com",
    model = "deepseek-chat"
}
local chat = openai.completions(opts)

uart.setup(1, 115200)
uart.on(1, "receive", function(id, len)
    local data = uart.read(id, len)
    log.info("uart", id, len, data)
    if data and #data > 0 then
        sys.publish("uart_rx", data)
    end
end)

sys.taskInit(function()
    sys.waitUntil("IP_READY")
    sys.wait(100)
    -- -- 固定问答演示
    -- local resp = chat:talk("你好,请问LuatOS是什么软件?应该如何学习呢?")
    -- if resp then
    --     log.info("deepseek回复", resp.content)
    -- else
    --     log.info("deepseek执行失败")
    -- end

    -- -- uart交互演示
    while 1 do
        local re, data = sys.waitUntil("uart_rx")
        if data then
            local resp = chat:talk(data)
            if resp then
                log.info("deepseek回复", resp.content)
                uart.write(1, resp.content)
            end
        end
    end
end)


sys.run()

