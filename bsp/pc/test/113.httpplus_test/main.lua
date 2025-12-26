-- httpplus 自测脚本（PC模拟器）
-- 场景覆盖：GET、POST 表单、POST JSON、chunked 响应、multipart 文件上传、bodyfile 上传
-- 运行环境：LuatOS PC 模拟器，用户自测

-- local sys = require "sys"
-- local json = require "json"
local httpplus = require "httpplus"

local TAG = "httpplus_test"
local ok_count, fail_count = 0, 0

local function equals(a, b)
    return a == b
end

local function safe_json_decode(s)
    local ok, obj = pcall(json.decode, s)
    if ok then return obj end
    return nil
end

local function run_case(name, fn)
    log.info(TAG, "CASE", name)
    local ok, err = pcall(fn)
    if ok and err ~= false then
        ok_count = ok_count + 1
        log.info(TAG, "PASS", name)
    else
        fail_count = fail_count + 1
        log.error(TAG, "FAIL", name, err or "")
    end
end

sys.taskInit(function()
    -- 用于上传测试的临时文件
    local upload_file = "/httpplus_test_file.txt"
    do
        local f = io.open(upload_file, "wb")
        if f then
            f:write("hello_world_upload")
            f:close()
        else
            log.warn(TAG, "无法创建测试文件", upload_file)
        end
    end

    -- 1) GET 测试
    run_case("GET", function()
        local code, resp = httpplus.request({
            url = "https://httpbin.air32.cn/get?foo=bar",
            headers = { ["User-Agent"] = "LuatOS-httpplus-test" },
            timeout = 20
        })
        if code ~= 200 or not resp or not resp.body then return false, "GET code/body 异常" end
        local body = resp.body:query()
        local obj = safe_json_decode(body)
        if not obj then return false, "GET JSON 解析失败" end
        if not equals(obj.args and obj.args.foo, "bar") then return false, "GET 参数回显不正确" end
        return true
    end)

    -- 2) POST 表单测试（application/x-www-form-urlencoded）
    run_case("POST forms", function()
        local code, resp = httpplus.request({
            url = "https://httpbin.air32.cn/post",
            forms = { a = "1", b = "空 格", c = "c&=v" },
            headers = { ["User-Agent"] = "LuatOS-httpplus-test" },
            timeout = 20
        })
        if code ~= 200 or not resp or not resp.body then return false, "forms code/body 异常" end
        local obj = safe_json_decode(resp.body:query())
        if not obj then return false, "forms JSON 解析失败" end
        if not (equals(obj.form and obj.form.a, "1") and obj.form.b and obj.form.c) then
            return false, "forms 字段回显缺失"
        end
        return true
    end)

    -- 3) POST JSON 测试
    run_case("POST json", function()
        local code, resp = httpplus.request({
            url = "https://httpbin.air32.cn/post",
            body = { name = "abc", n = 123 },
            headers = { ["User-Agent"] = "LuatOS-httpplus-test" },
            timeout = 20
        })
        if code ~= 200 or not resp or not resp.body then return false, "json code/body 异常" end
        local obj = safe_json_decode(resp.body:query())
        if not obj then return false, "json JSON 解析失败" end
        if not (obj.json and obj.json.name == "abc" and obj.json.n == 123) then
            return false, "json 字段回显不正确"
        end
        return true
    end)

    -- 4) chunked 响应测试（httpbin 流式响应）
    run_case("GET chunked", function()
        local code, resp = httpplus.request({
            url = "http://httpbin.air32.cn/stream/5",
            headers = { ["User-Agent"] = "LuatOS-httpplus-test" },
            timeout = 20,
            debug = true
        })
        if code ~= 200 or not resp or not resp.body then return false, "chunked code/body 异常" end
        local used = resp.body:used()
        if not (used and used > 0) then return false, "chunked body 为空" end
        -- 基础检验：应已去掉 chunked 框架，不包含明显的长度行
        local s = resp.body:query()
        if s:find("\r\n0\r\n") then return false, "chunked 末块残留" end
        return true
    end)

    -- 5) multipart 文件上传
    run_case("POST multipart", function()
        local code, resp = httpplus.request({
            url = "https://httpbin.air32.cn/post",
            files = { file1 = upload_file },
            forms = { note = "uploader" },
            headers = { ["User-Agent"] = "LuatOS-httpplus-test" },
            timeout = 20
        })
        if code ~= 200 or not resp or not resp.body then return false, "multipart code/body 异常" end
        local obj = safe_json_decode(resp.body:query())
        if not obj then return false, "multipart JSON 解析失败" end
        if not (obj.files and obj.files.file1 and obj.form and obj.form.note == "uploader") then
            return false, "multipart 回显缺失"
        end
        if not obj.files.file1:find("hello_world_upload") then
            return false, "multipart 文件内容不匹配"
        end
        return true
    end)

    -- 6) bodyfile 上传（纯文本）
    run_case("POST bodyfile", function()
        local code, resp = httpplus.request({
            url = "https://httpbin.air32.cn/post",
            bodyfile = upload_file,
            headers = {
                ["User-Agent"] = "LuatOS-httpplus-test",
                ["Content-Type"] = "text/plain"
            },
            timeout = 20
        })
        if code ~= 200 or not resp or not resp.body then return false, "bodyfile code/body 异常" end
        local obj = safe_json_decode(resp.body:query())
        if not obj then return false, "bodyfile JSON 解析失败" end
        if not (obj.data and obj.data:find("hello_world_upload")) then
            return false, "bodyfile 数据回显不匹配"
        end
        return true
    end)

    log.info(TAG, "RESULT", string.format("OK=%d FAIL=%d", ok_count, fail_count))
    sys.wait(1000)
    -- 测试结束
end)

sys.run()
