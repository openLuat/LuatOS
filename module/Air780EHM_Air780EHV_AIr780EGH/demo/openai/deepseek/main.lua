-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "deepseek"
VERSION = "1.0.0"

sys = require "sys"
require "sysplus"
openai = require "openai"

local uartid = 2

local opts = {
    apikey = "sk-e3d44d7c15a",--此处填用户自己去https://platform.deepseek.com/api_keys这里获取的key
    apiurl = "https://api.deepseek.com",
    model = "deepseek-chat",
}
uart.setup(uartid, 115200)

-- 收取数据会触发回调, 这里的"receive" 是固定值
uart.on(uartid, "receive", function(id, len)
    local s = ""
    repeat
        s = uart.read(id, 1024)
        if #s > 0 then -- #s 是取字符串的长度
            log.info("uart", "receive", id, #s, s)
            uart.write(uartid,
                "消息发送成功,请等待回复,若串口60S没有回复,请检查luatools打印的日志\r\n")
            sys.publish("uart_rx", s)
        end
    until s == ""
end)

sys.taskInit(function()
    sys.waitUntil("IP_READY")
    sys.wait(2000)

    local chat = openai.completions(opts)
    if chat then
        uart.write(uartid, "大语言模型初始化完成,可以开始对话了\r\n")
    else
        uart.write(uartid, "大语言模型初始化失败，请检查代码\r\n")
    end
    -- -- uart交互演示
    while 1 do
        local re, data = sys.waitUntil("uart_rx")
        if data then
            local resp = chat:talk(data)
            if resp and type(resp) == "table" then
                log.info("deepseek回复", resp.content)
                uart.write(uartid, resp.content)
            else
                local re_data = "大语言模型返回失败,错误原因:\r\n"
                log.info(re_data,resp)
                uart.write(uartid,re_data)
                uart.write(uartid,resp)
            end
        end
    end
end)

sys.run()

