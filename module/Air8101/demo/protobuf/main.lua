-- main.lua文件
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "protobuf_demo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)



sys.taskInit(function()

        -- 如果没有这个库, 就云编译一份吧: https://wiki.luatos.com/develop/compile/Cloud_compilation.html
        if not protobuf then
                log.info("protobuf", "this demo need protobuf lib")
                return
        end

        -- 加载 pb 文件, 这个是从pbtxt 转换得到的
        -- 下载资源到模块时不需要下载pbtxt,需要下载person.pb文件
        -- 转换命令: protoc.exe -o person.pb person.pbtxt
        -- protoc.exe 下载地址: https://github.com/protocolbuffers/protobuf/releases
        local pb_file = "/luadb/person.pb"

        if io.exists(pb_file) then
                protobuf.load(io.readFile(pb_file))
                --如果该文件存在，会发布一个事件 pb_file_exists
                sys.publish("pb_file_exists")
        else
                log.info("protobuf","Failed to load file")

        end

        local tb = {
                name = "wendal",
                id = 123,
                email = "abc@qq.com"
        }

        sys.waitUntil("pb_file_exists")

        sys.wait(1000)
        -- 用 protobuf 编码数据
        local pbdata = protobuf.encode("Person", tb)
        if pbdata then
                -- 打印数据长度. 编码后的数据含不可见字符, toHex是方便显示
                log.info("protobuf", "encode",  #pbdata, (pbdata:toHex()))
        end
        -- 用 json 编码数据, 用于对比大小
        local jdata = json.encode(tb)
        if jdata then
                log.info("json", #jdata, jdata)
        end
        -- 可见 protobuffs 比 json 节省很多空间

        -- 后续是演示解码
        local re = protobuf.decode("Person", pbdata)
        if re then
-- 打印数据, 因为table不能直接显示, 这里转成json来显示
log.info("protobuf", "decode", json.encode(re))
        end


end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!

