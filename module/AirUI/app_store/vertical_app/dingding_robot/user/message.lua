--[[
@module  message
@summary 钉钉机器人消息发送
@version 1.0.0
@date    2026.04.03
]]

-- 发送消息到钉钉机器人
-- @param webhookUrl 钉钉机器人Webhook地址
-- @param secret 钉钉机器人加签密钥（可选）
-- @param text 要发送的消息内容
-- @return result 发送是否成功
-- @return errorMsg 错误信息（如果失败）
local function sendMessage(webhookUrl, secret, text)
    log.info("message", "开始发送消息")
    
    -- 验证Webhook地址
    if not webhookUrl or webhookUrl == "" then
        log.error("message", "Webhook地址为空")
        return false, "Webhook地址为空"
    end
    
    -- 验证消息内容
    if not text or text == "" then
        log.error("message", "消息内容为空")
        return false, "消息内容为空"
    end
    
    -- 构建钉钉机器人消息格式
    local msgData = {
        msgtype = "text",  -- 消息类型为文本
        text = {
            content = text  -- 消息内容
        }
    }
    
    -- 将消息数据编码为JSON字符串
    local jsonStr = json.encode(msgData)
    if not jsonStr then
        log.error("message", "JSON编码失败")
        return false, "JSON编码失败"
    end
    
    local rheaders = {}
    rheaders["Content-Type"] = "application/json"

    -- 最终使用的URL
    local url = webhookUrl
    
    -- 如果有加签密钥，则添加签名
    if secret and secret ~= "" then
        local timestamp = tostring(os.time()) .. "000"
        local sign = crypto.hmac_sha256(timestamp .. "\n" .. secret, secret):fromHex():toBase64():urlEncode()
        url = webhookUrl .. "&timestamp=" .. timestamp .. "&sign=" .. sign
        log.info("message", "已添加加签")
    else
        log.info("message", "未配置加签，使用普通模式")
    end
    
    log.info("message", "正在发送HTTP请求到:", url)
    
    -- 发送HTTP POST请求
    local code, headers, body = http.request("POST", url, rheaders, jsonStr).wait()
    
    
    if code == 200 and body then
        local result = json.decode(body)
        
        -- 钉钉真正成功：errcode = 0
        if result and result.errcode == 0 then
            log.info("message", "✅ 钉钉消息发送成功")
            return true, "发送成功"
        else
            -- 钉钉返回错误（关键词/签名/权限问题）
            local err = "钉钉返回错误：" .. (result and result.errmsg or body)
            log.error("message", err)
            return false, err
        end
    else
        local err = "HTTP请求失败 code=" .. tostring(code)
        log.error("message", err)
        return false, err
    end
end

-- 导出模块接口
return {
    sendMessage = sendMessage
}
