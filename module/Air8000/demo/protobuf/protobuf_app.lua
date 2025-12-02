--[[
@module  protobuf_app
@summary protobuf 编解码功能模块
@version 1.0
@date    2025.10.31
@author  马梦阳
@usage
本功能模块演示的内容为：
1.加载 protobuf 定义文件；
2.将符合 protobuf 定义的 Lua table 数据编码为二进制数据；
3.使用 json 编码同样的 Lua table 数据后，对比 protobuf 和 json 编码后数据的大小；
4.将二进制数据解码为 Lua table 数据；
5.清除所有已加载的定义数据；


本文件没有对外接口,直接在 main.lua 中 require "protobuf_app" 就可以加载运行；
]]


local function main_task()
    -- 加载 pb 文件, 这个是 proto 经过 protoc.exe 编译后生成的二进制文件
    -- 下载资源到模块时不需要下载 proto 文件
    -- 转换命令: protoc -o person.pb person.proto
    -- protoc.exe 下载地址: https://github.com/protocolbuffers/protobuf/releases
    local pb_file = "/luadb/person.pb"

    local tbdata = {
        name = "wendal",
        id = 123,
        email = "abc@qq.com"
    }

    if io.exists(pb_file) then
        local success, bytesRead = protobuf.load(io.readFile(pb_file))
        if not success then
            log.info("protobuf", "加载 protobuf 定义失败，已读取 " .. bytesRead .. " 字节")
            return
        else
            log.info("protobuf", "加载 protobuf 定义成功，共解析 " .. bytesRead .. " 字节")
        end
    else
        log.info("protobuf", "pb 文件不存在")
        return
    end

    -- 编码数据；
    local pbdata = protobuf.encode("Person", tbdata)
    if pbdata then
        -- 编码成功，编码后的数据通常包含不可见字符；
        -- 打印长度和十六进制内容（便于调试）；
        log.info("protobuf", "编码成功，数据长度：" .. #pbdata)
        log.info("protobuf", "十六进制内容：" .. pbdata:toHex())
    else
        log.info("protobuf", "编码失败：数据格式或类型不匹配")
    end

    -- 对比 protobuf 编码和 json 编码的大小；
    local jdata = json.encode(tbdata)
    if jdata then
        log.info("json", "编码成功，数据长度：" .. #jdata)
        log.info("json", "数据内容：" .. jdata)
    else
        log.info("json", "编码失败：数据格式或类型不匹配")
    end
    -- 可见 protobuffs 比 json 节省很多空间；

    -- 数据解码；
    local tbdata = protobuf.decode("Person", pbdata)
    if tbdata then
        -- 解码后的数据为 Lua table 格式，需要转化为 json 进行显示；
        log.info("protobuf", "解码成功，数据内容：", json.encode(tbdata))
    else
        log.info("protobuf", "解码失败")
    end

    -- 清除所有已加载的定义数据；
    protobuf.clear()
    log.info("protobuf", "所有 protobuf 定义已清除")
end

-- 创建并启动一个 task
-- 用于运行 main_task 函数
sys.taskInit(main_task)
