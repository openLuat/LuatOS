

local function testTask()
    local code, header, body = http2.request(nil,"http://site0.cn/api/httptest/simple/time", 
                        {
                            method = "GET",
                            headers = {
                                ["Content-Type"] = "application/x-www-form-urlencoded",
                            },
                        }).wait()
    print(code)
    print(header)
    print(body)

    local code, header, body = http2.request(nil,"http://site0.cn/api/httptest/simple/date", 
    {
        method = "POST",
        body = string.rep("1234567890", 100),
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
        },
    }).wait()
    print(code)
    print(header)
    print(body)

    
end

function httpDemo()
	sys.taskInit(testTask)
end
