local report = {}
local ctx_path = "/luadb/ctx.json"
--第一个参数是测试最终结果，第二个参数是测试项目，第三个参数是测试描述
function report.send(result, testcase, msg)
    local data = io.readFile(ctx_path)
    local t_data = json.decode(data)
    local report_url = t_data.report_url
    local rheaders = {}
    rheaders["Content-Type"] = "application/json"
    local result_format = '{"result" : "%s", "test_case" : "%s", "message" : "%s"}'
    local report_data = string.format(result_format, result and "success" or "fail", testcase, msg)
    local code, headers, body = http.request("POST", report_url, rheaders, report_data).wait()
    log.info("上报结果", code)
    return code, headers, body
end

return report