

rtos.setPaths("/ram/%s.lua")

sys.taskInit(function()
    local fd = io.open("/ram/a.lua", "w+")
    fd:write("print(123) return { value = 42 }")
    fd:close()

    -- 第一次加载"a.lua"，会执行文件内容，打印123，并返回一个table
    local a = require "a"
    print("a", a, a.value)
    -- 这里故意设置成43，来验证卸载后重新加载是否生效
    a.value = 43
    print("a", a, a.value)
    unload "a"
    a = nil -- 卸载模块后，a变量仍然存在，但它的内容应该被垃圾回收掉了
    collectgarbage()
    collectgarbage() -- 这里调用两次垃圾回收，确保之前的a模块被完全清理掉了

    -- 重新加载后, 应该还是42，而不是43
    local a2 = require "a"
    print("a2", a2, a2.value)
end)

sys.run()