-- 飞书多维表格 API 调用（只获取30道题）

local thirty_questions = {}

-- ========== 配置区域（请替换为您的实际值）==========
local CONFIG = {
    -- 飞书应用凭证
    APP_ID = "cli_a94350ff1ffadcb3",                      
    APP_SECRET = "4eYgvxouaZqssqRbfQ3HUeZPCejggESH",                      
    
    -- 多维表格参数（从 URL 提取）
    APP_TOKEN = "T8ndbV4bKacm6Ys89Coc5fpcnFc",  
    TABLE_ID = "tblph4t1M4AfLodP",                       
    
    -- 筛选条件
    SUBMITTER_NAME = "刘晶晶",                   -- 提交人姓名（不需要筛选时设为 nil）
    -- CATEGORY = "基础知识",                     -- 题型（不需要筛选时设为 nil）    
    STATUS = "待老陆审核",                         -- 审核状态（不需要筛选时设为 nil）
    
    -- 获取数量
    PAGE_SIZE = 30,                             -- 只需要30道题
}

-- 缓存 token
local cachedToken = nil
local tokenExpireTime = 0

-- 获取 tenant_access_token
local function getAccessToken()
    if cachedToken and os.time() < tokenExpireTime then
        return cachedToken
    end
    
    local url = "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal"
    local body = json.encode({
        app_id = CONFIG.APP_ID,
        app_secret = CONFIG.APP_SECRET
    })
    
    log.info("thirty_questions", "正在获取 access_token...")
    
    local req_headers = {}
    req_headers["Content-Type"] = "application/json; charset=utf-8"
    local code, headers, bodyResp = http.request("POST", url, req_headers, body).wait()
    
    if code == 200 then
        local ok, data = pcall(json.decode, bodyResp)
        if ok and data.code == 0 then
            cachedToken = data.tenant_access_token
            tokenExpireTime = os.time() + data.expire - 300
            log.info("thirty_questions", "Token 获取成功")
            return cachedToken
        else
            log.warn("thirty_questions", "Token 错误: " .. tostring(data and data.msg or "unknown"))
            return nil
        end
    else
        log.warn("thirty_questions", "Token 请求失败, HTTP: " .. tostring(code))
        return nil
    end
end

-- ========== 构建筛选条件 ==========
local function buildFilter()
    local conditions = {}
    
    if CONFIG.SUBMITTER_NAME then
        table.insert(conditions, {
            field_name = "提交人",
            operator = "is",
            value = { CONFIG.SUBMITTER_NAME }
        })
    end
    
    if CONFIG.STATUS then
        table.insert(conditions, {
            field_name = "审核状态",
            operator = "is",
            value = { CONFIG.STATUS }
        })
    end
    -- if CONFIG.CATEGORY then
    --     table.insert(conditions, {
    --         field_name = "题型",
    --         operator = "is",
    --         value = { CONFIG.CATEGORY }
    --     })
    -- end
    
    if #conditions == 0 then
        return nil
    end
    
    return {
        conjunction = "and",
        conditions = conditions
    }
end

-- ========== 获取题目（只获取30道）==========
local function fetchRecords()
    local token = getAccessToken()
    if not token then
        return nil
    end
    
    local url = string.format(
        "https://open.feishu.cn/open-apis/bitable/v1/apps/%s/tables/%s/records/search",
        CONFIG.APP_TOKEN,
        CONFIG.TABLE_ID
    )
    
    local requestBody = {
        page_size = CONFIG.PAGE_SIZE,   -- 直接限制为30条
        automatic_fields = false
    }
    
    local filter = buildFilter()
    if filter then
        requestBody.filter = filter
    end
    
    local headers = {
        ["Authorization"] = "Bearer " .. token,
        ["Content-Type"] = "application/json"
    }
    
    log.info("thirty_questions", string.format("正在获取 %d 道题目...", CONFIG.PAGE_SIZE))
    
    local code, headers, bodyResp = http.request(
        "POST",
        url,
        headers,
        json.encode(requestBody)
    ).wait()
    
    if code == 200 then
        local ok, data = pcall(json.decode, bodyResp)
        if ok and data.code == 0 then
            local records = data.data.items or {}
            log.info("thirty_questions", string.format("成功获取 %d 条记录", #records))
            return records
        else
            log.warn("thirty_questions", "查询失败: " .. tostring(data and data.msg or "unknown"))
            return nil
        end
    else
        log.warn("thirty_questions", "HTTP请求失败: " .. tostring(code))
        return nil
    end
end

local function getFieldText(value)
    if type(value) == "table" and #value > 0 and value[1].text then
        return value[1].text
    elseif type(value) == "string" then
        return value
    else
        return ""
    end
end

local function getAnswerText(value)
    local answer = ""
    if type(value) == "table" and #value > 0 then
        answer = value[1]
    elseif type(value) == "string" then
        answer = value
    end
    
    answer = string.upper(answer:match("^%s*(.-)%s*$") or "")
    if answer:match("^[ABCD]$") then
        return answer
    elseif answer:match("^[1-4]$") then
        return string.char(64 + tonumber(answer))
    elseif answer:find("选项A") or answer:find("答案A") then
        return "A"
    elseif answer:find("选项B") or answer:find("答案B") then
        return "B"
    elseif answer:find("选项C") or answer:find("答案C") then
        return "C"
    elseif answer:find("选项D") or answer:find("答案D") then
        return "D"
    end
    
    return answer
end

-- ========== 转换为答题格式 ==========
local function formatQuestions(records)
    if not records then return {} end
    
    log.info("thirty_questions", "开始格式化题目，原始记录数:", #records)
    if #records > 0 then
        log.info("thirty_questions", "第一条记录原始数据:", json.encode(records[1]))
    end
    
    local questions = {}
    for _, record in ipairs(records) do
        local fields = record.fields
        local questionText = getFieldText(fields["题目"])
        if questionText and questionText ~= "" then
            table.insert(questions, {
                id = record.record_id,
                question = questionText,
                options = {
                    getFieldText(fields["选项A"]),
                    getFieldText(fields["选项B"]),
                    getFieldText(fields["选项C"]),
                    getFieldText(fields["选项D"])
                },
                answer = getAnswerText(fields["答案"])
            })
        end
    end
    
    if #questions > 0 then
        log.info("thirty_questions", "格式化后第一道题:", json.encode(questions[1]))
    end
    
    return questions
end

-- ========== 从30道题中随机抽取N道 ==========
local function selectRandomQuestions(questions, count)
    if not questions or #questions == 0 then
        return {}
    end
    
    count = count or 10
    if count > #questions then
        count = #questions
    end
    
    local selected = {}
    local indices = {}
    
    for i = 1, #questions do
        indices[i] = i
    end
    
    for i = 1, count do
        local randomPos = math.random(i, #indices)
        indices[i], indices[randomPos] = indices[randomPos], indices[i]
        table.insert(selected, questions[indices[i]])
    end
    
    return selected
end

-- ========== 公开接口 ==========
function thirty_questions.fetchQuestions(callback)
    local records = fetchRecords()
    local questions = formatQuestions(records)
    
    if #questions > 0 then
        log.info("thirty_questions", string.format("成功获取 %d 道题目", #questions))
        if callback then callback(questions) end
        return questions
    else
        log.warn("thirty_questions", "获取失败或没有题目")
        if callback then callback(nil) end
        return nil
    end
end

function thirty_questions.fetchRandomQuestions(count, callback)
    count = count or 10
    
    local questions = thirty_questions.fetchQuestions()
    
    if questions and #questions > 0 then
        local selected = selectRandomQuestions(questions, count)
        log.info("thirty_questions", string.format("从 %d 道题中随机抽取了 %d 道", #questions, #selected))
        if callback then callback(selected) end
        return selected
    else
        if callback then callback(nil) end
        return nil
    end
end

function thirty_questions.setConfig(config)
    if config.APP_ID then CONFIG.APP_ID = config.APP_ID end
    if config.APP_SECRET then CONFIG.APP_SECRET = config.APP_SECRET end
    if config.APP_TOKEN then CONFIG.APP_TOKEN = config.APP_TOKEN end
    if config.TABLE_ID then CONFIG.TABLE_ID = config.TABLE_ID end
    if config.SUBMITTER_NAME ~= nil then CONFIG.SUBMITTER_NAME = config.SUBMITTER_NAME end
    if config.CATEGORY ~= nil then CONFIG.CATEGORY = config.CATEGORY end
    if config.PAGE_SIZE then CONFIG.PAGE_SIZE = config.PAGE_SIZE end
end

return thirty_questions

