--[[
@module  main
@summary Air1601 真机 NDK helloworld 验证
@version 0.1.0
@date    2026-06-03

验证 air1601 .soc 已正确链接 NDK runtime,
且 Lua 侧能 ndk.rv32i 加载 hello_world.bin + ndk.exec 执行完成
+ ndk.getData 读出 exchange 中的 HELLO_NDK_DONE 标志位。

依赖: NDK 组件在 air1601 SDK 中已启用 (components/ndk/src + binding)。
      脚本分区需含 hello_world.bin (--script 烧入)。

运行:
  luatos-cli flash test --soc $SOC --port COM10 --baud 6000000 \
    --script testcase/common/scripts \
    --script testcase/air1601_ndk_helloworld/air1601_ndk_helloworld_basic/scripts \
    --timeout 30 \
    --keyword '### OVERALL_PASS ###' \
    --fail-keyword '### OVERALL_FAIL ###' \
    --fail-keyword 'panic' --fail-keyword 'hardfault'
]]

PROJECT = "air1601_ndk_helloworld"
VERSION = "0.1.0"

log.info("main", PROJECT, VERSION)

if wdt then
    wdt.init(9000)
    sys.timerLoopStart(wdt.feed, 3000)
end

local testrunner = require("testrunner")
local tests = require("air1601_ndk_hello_test")

sys.taskInit(function()
    testrunner.runBatch("air1601_ndk_helloworld_basic", {
        { testTable = tests, testcase = "air1601真机NDK helloworld" }
    })
end)

sys.run()
