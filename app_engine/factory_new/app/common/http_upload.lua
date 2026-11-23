--[[
@module  http_upload
@summary 上传本地文件为 multipart/form-data（有 httpplus 就分块流式，没有才整读）
@version 1.1
@date    2026.11.12
@author  江访

录音上传是大文件 POST：Air1103 只能录 PCM_16000，30 秒 ≈ 960KB。
io.readFile 整读再拼 multipart，瞬时占用接近 2MB，在 1.4MB 的 Lua 堆上会把 VM 打挂；
httpplus 的 files= 路径内部按块读、按块发，峰值是一个上传缓冲，与文件大小无关。

httpplus 是固件扩展库，不是每个型号都编进去了，故这里只做软依赖：有就走流式，
没有就退回整读路径（小文件没事，大文件仍可能 OOM，那要靠型号自己带 httpplus）。

=== 对外接口 ===

  http_upload.post_file(o) -> code, body
    o.url          [必填] 上传地址
    o.headers      [必填] 请求头表，本函数会往里写 Content-Type
    o.file_path    [必填] 本地文件绝对路径
    o.field        [可选] 文件表单字段名，默认 "file"
    o.filename     [可选] 表单里的文件名，默认取 file_path 的最后一段
    o.content_type [可选] 文件 MIME，默认 "application/octet-stream"
    o.forms        [可选] 普通表单字段表 name -> value，不带 filename 发送
    o.timeout      [可选] 超时秒数，默认 30
    @return number HTTP 状态码（请求没发出去时为 0）
    @return string 响应体

forms 里的字段一律【不带 filename】：带 filename 的 part 会被 Spring 识别成 MultipartFile，
request.getParameter 拿不到值（make_app 的 device_info 踩过，服务端报 device_info 异常）。
]]

local M = {}

-- httpplus 是固件扩展库：顶层 require 会让没编它的型号直接加载失败，
-- 故放到函数里调用；同时保持 require "httpplus" 字面写法，打包系统按这个文本决定是否打包。
local httpplus_loaded = false
local httpplus_mod = nil
local function load_httpplus()
    return require "httpplus"
end
local function get_httpplus()
    if not httpplus_loaded then
        httpplus_loaded = true
        local ok, m = pcall(load_httpplus)
        httpplus_mod = ok and type(m) == "table" and m or nil
    end
    return httpplus_mod
end

--[[
@function post_file
@summary 用 multipart/form-data 上传一个本地文件
@param table o 见模块头的参数表
@return number HTTP 状态码
@return string 响应体
]]
function M.post_file(o)
    local url = o and o.url
    local headers = o and o.headers
    local file_path = o and o.file_path
    if not url or type(headers) ~= "table" or not file_path then return 0, "" end

    local field = o.field or "file"
    local filename = o.filename or (file_path:match("([^/\\]+)$") or file_path)
    local ctype = o.content_type or "application/octet-stream"
    local timeout = tonumber(o.timeout) or 30
    local forms = (type(o.forms) == "table") and o.forms or nil

    -- 流式：httpplus 自己拼 multipart 并分块读写，不占大块内存
    local hp = get_httpplus()
    if hp and hp.request then
        headers["Content-Type"] = nil
        local req = {
            url = url,
            method = "POST",
            headers = headers,
            files = { [field] = file_path },
            timeout = timeout,
        }
        if forms and next(forms) then req.forms = forms end
        local code, resp = hp.request(req)
        local body = (resp and resp.body and resp.body:query()) or ""
        return tonumber(code) or 0, body
    end

    -- 退回整读：没有 httpplus 的型号只能这样，大文件有 OOM 风险
    local fdata = io.readFile(file_path)
    if not fdata then return 0, "" end
    local bd = "----WebKitFormBoundary" .. tostring(os.time())
    headers["Content-Type"] = "multipart/form-data; boundary=" .. bd
    local body = {
        "--" .. bd .. "\r\n",
        "Content-Disposition: form-data; name=\"" .. field .. "\"; filename=\"" .. filename .. "\"\r\n",
        "Content-Type: " .. ctype .. "\r\n\r\n",
        fdata,
        "\r\n",
    }
    if forms then
        for name, value in pairs(forms) do
            body[#body + 1] = "--" .. bd .. "\r\n"
            body[#body + 1] = "Content-Disposition: form-data; name=\"" .. name .. "\"\r\n\r\n"
            body[#body + 1] = tostring(value)
            body[#body + 1] = "\r\n"
        end
    end
    body[#body + 1] = "--" .. bd .. "--\r\n"
    local code, _, rb = http.request("POST", url, headers, table.concat(body),
        { timeout = timeout * 1000 }).wait()
    return tonumber(code) or 0, rb or ""
end

return M
