-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "perfbasic"
VERSION = "1.0.0"

-- 修改者的名称, 方便日后维护
AUTHOR = {"luatos"}

-- 引入测试套件和测试运行器模块
local testrunner = require("testrunner")

-- 载入所有性能测试模块
local perf_hash     = require("perf_hash")
local perf_rsa      = require("perf_rsa")
local perf_ecc      = require("perf_ecc")
local perf_fft      = require("perf_fft")
local perf_codec    = require("perf_codec")
local perf_json     = require("perf_json")
local perf_compress = require("perf_compress")
local perf_gmssl    = require("perf_gmssl")
local perf_lua      = require("perf_lua")

sys.taskInit(function()
    -- 各测试模块按测试类别分组，依次执行
    -- 注意：有库则测，无库则在各模块内部跳过，不影响整体通过
    testrunner.runBatch("perf_basic", {
        { testTable = perf_hash,     testcase = "哈希算法性能（MD5/SHA1/SHA256/SHA512/AES）" },
        { testTable = perf_rsa,      testcase = "RSA-2048 签名验签性能" },
        { testTable = perf_ecc,      testcase = "ECDSA P-256 签名验签性能" },
        { testTable = perf_fft,      testcase = "FFT 计算性能（N=1024/4096）" },
        { testTable = perf_codec,    testcase = "音频编解码性能（AMR-NB/MP3）" },
        { testTable = perf_json,     testcase = "JSON 编解码性能" },
        { testTable = perf_compress, testcase = "miniz 压缩解压性能" },
        { testTable = perf_gmssl,    testcase = "国密算法性能（SM2/SM3/SM4）" },
        { testTable = perf_lua,      testcase = "纯 Lua VM 基准（Fibonacci/表/浮点/字符串/排序）" },
    })
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
