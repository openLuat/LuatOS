local mreport_tests = {}

function mreport_tests.test_mreport_api_exists()
    log.info("mreport_tests", "检查 netdrv.mreport 接口存在")
    assert(type(netdrv) == "userdata", "netdrv 模块不存在")
    assert(type(netdrv.mreport) == "function", "netdrv.mreport 接口不存在")
end

function mreport_tests.test_mreport_send_no_panic()
    log.info("mreport_tests", "检查 netdrv.mreport() 调用稳定性")
    local ok, err = pcall(function()
        netdrv.mreport()
    end)
    assert(ok == true, "netdrv.mreport() 调用异常: " .. tostring(err))
end

function mreport_tests.test_mreport_enable_disable_no_panic()
    log.info("mreport_tests", "检查 netdrv.mreport(enable) 开关稳定性")
    local ok_enable, err_enable = pcall(function()
        netdrv.mreport("enable", true)
    end)
    assert(ok_enable == true, "enable=true 调用异常: " .. tostring(err_enable))

    local ok_disable, err_disable = pcall(function()
        netdrv.mreport("enable", false)
    end)
    assert(ok_disable == true, "enable=false 调用异常: " .. tostring(err_disable))
end

function mreport_tests.test_mreport_adapter_id_no_panic()
    log.info("mreport_tests", "检查 netdrv.mreport(adapter_id) 调用稳定性")
    local adapter_id = 0
    if socket and socket.LWIP_GP then
        adapter_id = socket.LWIP_GP
    end

    local ok, err = pcall(function()
        netdrv.mreport("adapter_id", adapter_id)
    end)
    assert(ok == true, "adapter_id 调用异常: " .. tostring(err))
end

return mreport_tests
