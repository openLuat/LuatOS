--[[
@module openai
@summary 对接OpenAI兼容的平台,例如deepseek
@version 1.0
@date    2025.1.27
@author  wendal
@tag LUAT_USE_NETWORK
@demo openai
@usage
-- 对接deepseek演示 请阅demo/openai

-- 本API正在积极设计中
]]

local openai = {
    conf = {}
}

local function talk(self, msg)
    local rheaders = {
        ['Content-Type'] = "application/json",
        ['Accept'] = "application/json",
        ['Authorization'] = "Bearer " .. self.opts.apikey
    }
    if not msg then
        return
    end
    if type(msg) == "table" then
        table.insert(self.msgs, msg)
    else
        table.insert(self.msgs, {role="user", content=msg})
    end

    local rbody = {
        model = self.opts.model,
        messages = self.msgs,
        stream = false
    }
    local url = self.opts.apiurl .. "/chat/completions"
    -- log.info("openai", "request", url, json.encode(rheaders), json.encode(rbody))
    local code,headers,body = http.request("POST", url, rheaders, (json.encode(rbody)), {timeout=60*1000}).wait()
    -- log.info("openai", code, json.encode(headers) or "", body or "")
    if code == 200 then
        -- log.info("openai", "执行完成!!!")
        local jdata = json.decode(body)
        if jdata and jdata.choices and #jdata.choices > 0 then
            -- 自动选用第一个回应
            local ch = jdata.choices[1].message
            table.insert(self.msgs, {role=ch.role, content=ch.content})
            return ch
        end
    end
end

--[[
创建一个对话
@api openai.completions(opts, prompt)
@table 调用选项,有必填参数,请看实例
@string 起始提示语,可选
@return 对话实例
@usage
-- 以deepseek为例, 请填充真实的apikey
sys = require "sys"
require "sysplus"
openai = require "openai"

local opts = {
    apikey = "sk-123456",
    apiurl = "https://api.deepseek.com",
    model = "deepseek-chat"
}
local chat = openai.completions(opts)
sys.taskInit(function()
    sys.waitUntil("IP_READY")
    sys.wait(100)
    -- 固定问答演示
    local resp = chat:talk("你好,请问LuatOS是什么软件?应该如何学习呢?")
    if resp then
        log.info("deepseek回复", resp.content)
    else
        log.info("deepseek执行失败")
    end
end)
]]
function openai.completions(opts, prompt)
    local chat = {
        opts = opts,
        talk = talk,
        msgs = {
            prompt and {role="system", content=prompt}
        }
    }
    return chat
end


return openai
