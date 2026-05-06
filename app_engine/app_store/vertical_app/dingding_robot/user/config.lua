--[[
@module  config
@summary 钉钉机器人配置管理
@version 1.0.0
@date    2026.04.03
]]

-- 配置文件路径
local CONFIG_FILE = "dingding_config.json"
-- Webhook地址变量
local webhookUrl = ""
-- 加签密钥变量
local secretKey = ""
-- 消息内容变量
local messageText = ""

-- 保存配置到文件
local function saveConfig()
    log.info("config", "开始保存配置")
    
    -- 构建配置数据对象
    local configData = {
        webhook = webhookUrl,
        secret = secretKey,
        message = messageText
    }
    
    -- 将配置数据编码为JSON字符串
    local jsonStr = json.encode(configData)
    if not jsonStr then
        log.error("config", "JSON编码失败")
        return false
    end
    
    -- 打开文件进行写入
    local f = io.open(CONFIG_FILE, "w")
    if f then
        -- 写入JSON字符串
        f:write(jsonStr)
        -- 关闭文件
        f:close()
        log.info("config", "配置已保存到", CONFIG_FILE)
        return true
    else
        log.error("config", "无法打开配置文件进行写入")
        return false
    end
end

-- 从文件加载配置
local function loadConfig()
    log.info("config", "开始加载配置")
    
    -- 打开文件进行读取
    local f = io.open(CONFIG_FILE, "r")
    if f then
        -- 读取文件全部内容
        local content = f:read("*a")
        -- 关闭文件
        f:close()
        
        -- 如果内容不为空
        if content and #content > 0 then
            -- 解析JSON字符串
            local configData = json.decode(content)
            if configData then
                -- 更新变量值
                webhookUrl = configData.webhook or ""
                secretKey = configData.secret or ""
                messageText = configData.message or ""
                log.info("config", "配置已加载成功")
                return true
            end
        end
    end
    
    -- 如果文件不存在或解析失败，使用默认值
    log.info("config", "未找到配置文件，使用默认值")
    return false
end

-- 设置Webhook地址
local function setWebhook(url)
    webhookUrl = url or ""
    log.info("config", "Webhook地址已设置为:", webhookUrl)
end

-- 获取Webhook地址
local function getWebhook()
    return webhookUrl
end

-- 设置加签密钥
local function setSecret(secret)
    secretKey = secret or ""
    log.info("config", "加签密钥已设置")
end

-- 获取加签密钥
local function getSecret()
    return secretKey
end

-- 设置消息内容
local function setMessage(msg)
    messageText = msg or ""
    log.info("config", "消息内容已设置")
end

-- 获取消息内容
local function getMessage()
    return messageText
end

-- 模块加载时自动加载配置
loadConfig()

-- 导出模块接口
return {
    saveConfig = saveConfig,
    loadConfig = loadConfig,
    setWebhook = setWebhook,
    getWebhook = getWebhook,
    setSecret = setSecret,
    getSecret = getSecret,
    setMessage = setMessage,
    getMessage = getMessage,
}
