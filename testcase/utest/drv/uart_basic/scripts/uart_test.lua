local t = {}

-- 3 个 api 用例:覆盖 luat_uart_pc.c:20 / :50 护栏 + uart.list 上界
local api_suite = {}

function api_suite.test_api_exist_invalid_id()
    -- 9999 越界 0~127,应返 false (boolean)
    local r = uart.exist(9999)
    assert(r == false, "uart.exist(9999) 应返 false,实际: " .. tostring(r))
end

function api_suite.test_api_setup_invalid_id()
    -- 越界 ID 应失败,返 -1 (luat_uart_pc.c:20 命中 !luat_uart_exist)
    local r = uart.setup(9999, 115200)
    assert(type(r) == "number" and r < 0,
        "uart.setup(9999) 应返负数,实际: " .. tostring(r))
end

function api_suite.test_api_list_probe()
    -- uart_drv_win32.c:75 luat_uart_list 直接解 dll 函数指针;
    -- dll 未加载会段错误,这里主动早返,把失败信号交给 test_dll_loaded
    if uart.dll_utest("dll_loaded") ~= true then
        log.warn("api", "跳过 test_api_list_probe: dll 未加载")
        return
    end
    local list = uart.list(64)
    assert(type(list) == "table", "uart.list(64) 应返 table,实际: " .. type(list))
    assert(#list <= 64, "uart.list(64) 长度不应超过 64,实际: " .. #list)
end

-- 9 个 dll 用例:每条覆盖一个 luat_uart_*_extern 导出符号
local dll_suite = {}

local function assert_dll_export(case_name)
    assert(uart.dll_utest(case_name) == true,
        "uart.dll_utest('" .. case_name .. "') 应返 true")
end

function dll_suite.test_dll_loaded()
    assert_dll_export("dll_loaded")
end
function dll_suite.test_dll_export_exist_extern()  assert_dll_export("export_exist_extern") end
function dll_suite.test_dll_export_open_extern()   assert_dll_export("export_open_extern") end
function dll_suite.test_dll_export_close_extern()  assert_dll_export("export_close_extern") end
function dll_suite.test_dll_export_read_extern()   assert_dll_export("export_read_extern") end
function dll_suite.test_dll_export_send_extern()   assert_dll_export("export_send_extern") end
function dll_suite.test_dll_export_recv_cb_extern() assert_dll_export("export_recv_cb_extern") end
function dll_suite.test_dll_export_sent_cb_extern() assert_dll_export("export_sent_cb_extern") end
function dll_suite.test_dll_export_list_extern()  assert_dll_export("export_get_list_extern") end

t.api_suite = api_suite
t.dll_suite = dll_suite

return t