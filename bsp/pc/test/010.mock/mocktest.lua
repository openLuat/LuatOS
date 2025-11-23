
local function mock_handle(key, data)
    log.info("mock.key", key)
    --print("mock", key, data or "nil")
    if key == "rtos.bsp.get" then
        return 0, "EC618"
    end
    return -1
end

-- print("我在这里...")

return mock_handle
