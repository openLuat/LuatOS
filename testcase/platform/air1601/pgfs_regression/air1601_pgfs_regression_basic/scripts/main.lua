--[[
@module  main
@summary Air1601 真机 pgfs 回归 (FTL 迁移验证)
@version 1.0.0
@date    2026-06-02
@author  Mavis (mavis)
@usage
回归目标: 验证 master 6 个 commit 后的 FTL 改造在 air1601 真机上
  · 链接通过 (C 代码编进 .soc)
  · pgfs mount 正常
  · 基础文件操作正常
  · 重新 mount 状态恢复 (验证 CP 恢复)
  · 运行时控制 (lock_mode / powercut / bad_block_once) 正常
  · 损坏块处理 (bad_block_once 注入) 不崩

依赖: 需要外部 SPI NOR flash, 默认 spi2 + cs4 + pwr50
       (与 bsp/air1601/README.md 验证过的组合一致)

运行:
  luatos-cli flash test --soc $SOC --port COM10 --baud 6000000 \
    --script testcase/common/scripts \
    --script testcase/platform/air1601/pgfs_regression/air1601_pgfs_regression_basic/scripts \
    --timeout 60 --keyword '### OVERALL_PASS ###' --keyword '### OVERALL_FAIL ###' \
    --fail-keyword 'panic' --fail-keyword 'hardfault'
]]

PROJECT = "air1601_pgfs_regression"
VERSION = "001.999.000"

log.info("main", PROJECT, VERSION)

if wdt then
    wdt.init(9000)
    sys.timerLoopStart(wdt.feed, 3000)
end

local testrunner = require("testrunner")
local tests = require("air1601_pgfs_test")

sys.taskInit(function()
    testrunner.runBatch("air1601_pgfs_regression", {
        {testTable = tests, testcase = "air1601真机pgfs回归"}
    })
end)

sys.run()
