--[[
@module  message
@summary 飞书机器人消息发送
@version 1.0.0
@date    2026.04.14
]]

-- 发送消息到飞书机器人
-- @param webhookUrl 飞书机器人Webhook地址
-- @param secret 飞书机器人签名密钥（可选）
-- @param enableSign 是否启用签名校验
-- @param text 要发送的消息内容
-- @return result 发送是否成功
-- @return errorMsg 错误信息（如果失败）
local function sendMessage(webhookUrl, secret, enableSign, text)
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
    
    -- 构建飞书机器人消息格式
    local msgData = {
        msg_type = "text",
        content = {
            text = text
        }
    }
    
    -- 如果启用签名，添加timestamp和sign字段
    if enableSign and secret and secret ~= "" then
        local timestamp = tostring(os.time())
        msgData.timestamp = timestamp
        
        -- 生成签名（关键：第一个参数为空，第二个参数是 timestamp + "\n" + secret）
        local stringToSign = timestamp .. "\n" .. secret
        local sign = crypto.hmac_sha256("", stringToSign):fromHex():toBase64()
        msgData.sign = sign
        log.info("message", "已添加签名")
    else
        log.info("message", "未启用签名或未配置密钥，使用普通模式")
    end
    
    -- 将消息数据编码为JSON字符串
    local jsonStr = json.encode(msgData)
    if not jsonStr then
        log.error("message", "JSON编码失败")
        return false, "JSON编码失败"
    end
    
    local rheaders = {}
    rheaders["Content-Type"] = "application/json"
    
    log.info("message", "正在发送HTTP请求到:", webhookUrl)
    
    -- 发送HTTP POST请求
    local code, headers, body = http.request("POST", webhookUrl, rheaders, jsonStr).wait()
    
    if code == 200 and body then
        local result = json.decode(body)
        
        -- 飞书真正成功：code = 0
        if result and result.code == 0 then
            log.info("message", "✅ 飞书消息发送成功")
            return true, "发送成功"
        else
            -- 飞书返回错误
            local err = "飞书返回错误：" .. (result and result.msg or body)
            if result and result.code == 10000 then
                err = err .. " (签名校验失败，请检查Secret或时间戳)"
            elseif result and result.code == 99999999 then
                err = err .. " (机器人不存在或Webhook无效)"
            end
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
