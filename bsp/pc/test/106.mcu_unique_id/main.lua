_G.sys = require("sys")

sys.taskInit(function()
    -- 打印mcu.unique_id()多次，验证每次结果一致
    for i = 1, 3 do
        local id = mcu.unique_id()
        print("MCU Unique ID:", id:toHex())
        print("MCU Unique ID:", mobile.imei(), #mobile.imei())
        sys.wait(1000)
    end
    os.exit(0)
end)

sys.run()
