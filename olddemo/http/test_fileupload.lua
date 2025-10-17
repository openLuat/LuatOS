
function demo_http_post_file()
        -- -- POST multipart/form-data模式 上传文件---手动拼接
        local boundary = "----WebKitFormBoundary"..os.time()
        local req_headers = {
            ["Content-Type"] = "multipart/form-data; boundary="..boundary,
        }
        local body = "--"..boundary.."\r\n"..
                     "Content-Disposition: form-data; name=\"uploadFile\"; filename=\"luatos_uploadFile_TEST01.txt\""..
                     "\r\nContent-Type: text/plain\r\n\r\n"..
                     "1111http_测试一二三四654zacc\r\n"..
                     "--"..boundary

        log.info("headers: ", "\r\n"..json.encode(req_headers))
        log.info("body: ", "\r\n"..body)
        local code, headers, body = http.request("POST","http://airtest.openluat.com:2900/uploadFileToStatic",
                req_headers,
                body -- POST请求所需要的body, string, zbuff, file均可
        ).wait()
        log.info("http.post", code, headers, body)

        -- 也可用postMultipartFormData(url, params) 上传文件
        postMultipartFormData(
            "http://airtest.openluat.com:2900/uploadFileToStatic",
            {
                -- texts = 
                -- {
                --     ["imei"] = "862991234567890",
                --     ["time"] = "20180802180345"
                -- },
                
                files =
                {
                    ["uploadFile"] = "/luadb/luatos_uploadFile.txt",
                }
            }
        )
end



---- MultipartForm上传文件
-- url string 请求URL地址
-- req_headers table 请求头
-- params table 需要传输的数据参数
function postMultipartFormData(url, params)
    local boundary = "----WebKitFormBoundary"..os.time()
    local req_headers = {
        ["Content-Type"] = "multipart/form-data; boundary="..boundary,
    }
    local body = {}

    -- 解析拼接 body
    for k,v in pairs(params) do
        if k=="texts" then
            local bodyText = ""
            for kk,vv in pairs(v) do
                print(kk,vv)
                bodyText = bodyText.."--"..boundary.."\r\nContent-Disposition: form-data; name=\""..kk.."\"\r\n\r\n"..vv.."\r\n"
            end
            table.insert(body, bodyText)
        elseif k=="files" then
            local contentType =
            {
                txt = "text/plain",             -- 文本
                jpg = "image/jpeg",             -- JPG 格式图片
                jpeg = "image/jpeg",            -- JPEG 格式图片
                png = "image/png",              -- PNG 格式图片   
                gif = "image/gif",              -- GIF 格式图片
                html = "image/html",            -- HTML
                json = "application/json"       -- JSON
            }
            
            for kk,vv in pairs(v) do
                if type(vv) == "table" then
                    for i=1, #vv do
                        print(kk,vv[i])
                        table.insert(body, "--"..boundary.."\r\nContent-Disposition: form-data; name=\""..kk.."\"; filename=\""..vv[i]:match("[^%/]+%w$").."\"\r\nContent-Type: "..contentType[vv[i]:match("%.(%w+)$")].."\r\n\r\n")
                        table.insert(body, io.readFile(vv[i]))
                        table.insert(body, "\r\n")
                    end
                else
                    print(kk,vv)
                    table.insert(body, "--"..boundary.."\r\nContent-Disposition: form-data; name=\""..kk.."\"; filename=\""..vv:match("[^%/]+%w$").."\"\r\nContent-Type: "..contentType[vv:match("%.(%w+)$")].."\r\n\r\n")
                    table.insert(body, io.readFile(vv))
                    table.insert(body, "\r\n")
                end
            end
        end
    end 
    table.insert(body, "--"..boundary.."--\r\n")
    body = table.concat(body)
    log.info("headers: ", "\r\n" .. json.encode(req_headers), type(body))
    log.info("body: " .. body:len() .. "\r\n" .. body)
    local code, headers, body = http.request("POST",url,
            req_headers,
            body
    ).wait()   
    log.info("http.post", code, headers, body)
end
