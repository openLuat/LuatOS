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
]] local openai = {
    conf = {}
}

-- 定义默认参数表
local defaultOpts = {
    apikey = "123456",
    apiurl = "https://api.deepseek.com",
    model = "deepseek-chat"
}

--比较传入的table和默认table，如果传入的值里少了某个值，默认table顶上去
local function mergeWithDefaults(opts, defaults)
    -- 创建一个新的表来存储合并结果
    local mergedOpts = {}
    
    -- 先加载默认值
    for k, v in pairs(defaults) do
        mergedOpts[k] = v
    end
    
    -- 使用传入的 opts 表覆盖默认值
    for k, v in pairs(opts) do
        mergedOpts[k] = v
    end

    return mergedOpts
end


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
        table.insert(self.msgs, {
            role = "user",
            content = msg
        })
    end

    local rbody = {
        model = self.opts.model,
        messages = self.msgs,
        stream = false
    }
    local url = self.opts.apiurl .. "/chat/completions"
    -- log.info("openai", "request", url, json.encode(rheaders), json.encode(rbody))
    local code, headers, body = http.request("POST", url, rheaders, (json.encode(rbody)), {
        timeout = 60 * 1000
    }).wait()
    local tag = ""
    -- log.info("openai", code, json.encode(headers) or "", body or "")
    if code == 200 then
        -- log.info("openai", "执行完成!!!")
        local jdata = json.decode(body)
        if jdata and jdata.choices and #jdata.choices > 0 then
            -- 自动选用第一个回应
            local ch = jdata.choices[1].message
            table.insert(self.msgs, {
                role = ch.role,
                content = ch.content
            })
            return ch
        end
    elseif code == 400 then
        tag = "请求体格式错误,请根据错误信息提示修改请求体"
        log.warn(tag)
    elseif code == 401 then
        tag = "API key错误,认证失败,请检查您的API key是否正确,如没有API key,请先创建API key"
        log.warn(tag)
    elseif code == 402 then
        tag = "账号余额不足,请充值"
        log.warn(tag)
    elseif code == 422 then
        tag = "请求体参数错误,请根据错误信息提示修改请求体"
        log.warn(tag)
    elseif code == 429 then
        tag = "请求速率（TPM 或 RPM）达到上限,请稍后再试"
        log.warn(tag)
    elseif code == 500 then
        tag = "服务器内部故障,请等待后重试,若问题一直存在,请联系deepseek官方解决"
        log.warn(tag)
    elseif code == 503 then
        tag = "服务器负载过高,请稍后重试您的请求"
        log.warn(tag)
    elseif code < 0 then
        tag = "异常，大概率是服务器问题" .. code
        if code == -8 then
            tag = "链接服务超时或读取数据超时" .. code
        end
    end
    log.info("openai", code, json.encode(headers) or "", body or "")
    return tag
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
    opts = mergeWithDefaults(opts, defaultOpts)
    local chat = {
        opts = opts,
        talk = talk,
        msgs = {prompt and {
            role = "system",
            content = prompt
        }}
    }
    return chat

end

return openai
