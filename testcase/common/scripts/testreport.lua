local report = {}

-- 上报测试用例的状态
-- 参数:
--   ctx - 上下文对象，必须包含 status_url 字段（为空或不存在时不进行上报）
--   testcase - 字符串，测试用例名称
--   status - 字符串，测试状态（"running"、"passed"、"failed" 等）
--   msg - 字符串，状态描述或错误信息
-- 返回: 
--   如果 status_url 不存在，返回 nil
--   如果进行了上报，返回 (code, headers, body) - HTTP 状态码、响应头、响应体
function report.reportStatus(ctx, testcase, status, msg)
    -- 检查上下文对象和状态 URL 是否存在
    if not ctx or not ctx.status_url or ctx.status_url == "" then
        --log.warn("report", "状态 URL 未配置，跳过状态上报")
        return nil
    end
    
    local status_url = ctx.status_url
    
    -- 设置 HTTP 请求头
    local rheaders = {}
    rheaders["Content-Type"] = "application/json"
    
    -- 生成 JSON 格式的状态数据
    local status_data = {
        id = ctx.id or "",
        test_case = testcase,
        status = status,
        message = msg
    }
    local status_json = json.encode(status_data)
    
    -- 发送 POST 请求到状态服务器
    local code, headers, body = http.request("POST", status_url, rheaders, status_json).wait()
    
    log.info("report", string.format("上报状态: %s - %s (状态码: %d)", testcase, status, code))
    
    return code, headers, body
end

-- 发送最终测试结果到报告服务器
-- 参数:
--   ctx - 上下文对象，必须包含 report_url 字段（为空或不存在时不进行上报）
--   result - 布尔值，测试结果（true 表示成功，false 表示失败）
--   testcase - 字符串，测试用例名称
--   msg - 字符串，测试描述或错误信息
-- 返回: 
--   如果 report_url 不存在，返回 nil
--   如果进行了上报，返回 (code, headers, body) - HTTP 状态码、响应头、响应体
function report.send(ctx, result, testcase, msg)
    -- 检查上下文对象和报告 URL 是否存在
    if not ctx or not ctx.report_url or ctx.report_url == "" then
        log.warn("report", "报告 URL 未配置，跳过最终结果上报")
        return nil
    end
    
    local report_url = ctx.report_url
    
    -- 设置 HTTP 请求头
    local rheaders = {}
    rheaders["Content-Type"] = "application/json"
    
    -- 构建结果数据：将布尔值转换为字符串 "success" 或 "fail"
    local result_status = result and "success" or "fail"
    
    -- 生成 JSON 格式的报告数据
    local report_data = {
        id = ctx.id or "",
        result = result_status,
        test_case = testcase,
        message = msg
    }
    local report_json = json.encode(report_data)
    
    -- 发送 POST 请求到报告服务器
    local code, headers, body = http.request("POST", report_url, rheaders, report_json).wait()
    
    log.info("report", string.format("上报最终结果: %s - %s (状态码: %d)", testcase, result_status, code))
    
    return code, headers, body
end

return report