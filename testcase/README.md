# LuatOS 测试用例编写指南

本目录包含 LuaTools 项目的所有测试用例。本文档说明如何编写和组织测试用例。

## 目录结构

```
testcase/
├── common/                          # 公共模块
│   └── scripts/
│       ├── testsuite.lua           # 测试套件运行框架
│       ├── testrunner.lua          # 测试运行器（主控制逻辑）
│       ├── testreport.lua          # 测试结果上报模块
│       └── netready.lua            # 网络连接初始化
│
├── gmssl/                           # GMSSL 加密测试用例
│   └── gmssl_basic/
│       ├── metas.json              # 测试用例元数据
│       └── scripts/
│           ├── main.lua            # 测试入口
│           └── gmssl_sm2.lua       # SM2 算法单元测试
```

## 执行方式（PC 模拟器）

运行测试时，需要执行编译产物，并且**必须**传入两个脚本目录：

1. `testcase/common/scripts/`
2. 单个目标测试用例的 `scripts/` 目录

```powershell
build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\unit_testcase_tools\mreport\scripts\
```

注意：该运行方式不支持在同一条命令中传入多个目标测试用例目录。

## 快速开始

### 1. 创建新的测试用例目录

假设要创建一个名为 `myfeature` 的测试用例：

```bash
testcase/
└── myfeature/
    └── myfeature_basic/
        ├── metas.json              # 元数据配置
        └── scripts/
            ├── main.lua            # 测试入口脚本
            └── myfeature_test.lua   # 单元测试模块
```

### 2. 编写 `metas.json` 文件

`metas.json` 定义了测试用例的元数据信息：

```json
{
    "timeout": 60,
    "model": {
        "air780epm": [1, 2, 103, 104, 105, 106],
        "air780ehm": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113],
        "air8000": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113]
    },
    "action_count": 1,
    "priority": 5,
    "description": "XXX单元测试"
}
```

**字段说明：**
- `timeout`: 测试执行的最大超时时间（秒）
- `model`: 支持的设备型号及其对应的 SIM 卡 ID
- `action_count`: 执行动作次数
- `priority`: 优先级（数字越小优先级越高）
- `description`: 测试的描述

### 3. 编写 `main.lua` 入口脚本

`main.lua` 是测试的入口点，负责初始化和运行所有测试：

```lua
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "myfeaturetest"
VERSION = "1.0.0"

-- 修改者的名称, 方便日后维护
AUTHOR = "your_name"

-- 引入测试运行器模块
testrunner = require("testrunner")

-- 载入需要测试的模块
myfeature_test = require("myfeature_test")

-- 开启一个task,运行测试
sys.taskInit(function()
    -- testrunner.run() - 运行单个测试
    -- testrunner.runBatch() - 运行多个测试
    testrunner.runBatch("myfeature", {
        {testTable = myfeature_test, testcase = "MyFeature 基础测试"}
    })
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
```

**关键点：**
- 必须定义 `PROJECT` 和 `VERSION`
- 使用 `require()` 导入测试模块
- 在 `sys.taskInit()` 中调用 `testrunner.run()` 或 `testrunner.runBatch()`

### 4. 编写单元测试模块

单元测试模块包含具体的测试逻辑，所有以 `test_` 开头的函数都会被自动执行：

```lua
-- myfeature_test.lua
local myfeature = {}

-- 测试用例 1: 基础功能测试
function myfeature.test_basic_functionality()
    log.info("myfeature", "开始基础功能测试")
    
    -- 执行被测试的代码
    local result = someFunction()
    
    -- 使用 assert 验证结果
    assert(result == expected_value, "基础功能测试失败")
    
    log.info("myfeature", "基础功能测试通过")
end

-- 测试用例 2: 边界条件测试
function myfeature.test_boundary_conditions()
    log.info("myfeature", "开始边界条件测试")
    
    -- 测试边界值
    assert(someFunction(0) == 0, "边界值 0 处理失败")
    assert(someFunction(-1) == -1, "负数处理失败")
    assert(someFunction(999999) == 999999, "大数处理失败")
    
    log.info("myfeature", "边界条件测试通过")
end

-- 测试用例 3: 错误处理测试
function myfeature.test_error_handling()
    log.info("myfeature", "开始错误处理测试")
    
    -- 测试异常情况
    local success, err = pcall(function()
        -- 会抛出异常的代码
        invalidFunction()
    end)
    
    assert(not success, "应该捕获异常")
    
    log.info("myfeature", "错误处理测试通过")
end

return myfeature
```

## 完整示例：GMSSL SM2 测试

### 目录结构
```
testcase/gmssl/gmssl_basic/
├── metas.json
└── scripts/
    ├── main.lua
    └── gmssl_sm2.lua
```

### main.lua
```lua
PROJECT = "gmssltest"
VERSION = "1.0.0"
AUTHOR = "wendal"

testrunner = require("testrunner")
gmssl_sm2 = require("gmssl_sm2")

sys.taskInit(function()
    testrunner.runBatch("gmssl", {
        {testTable = gmssl_sm2, testcase = "GMSSL SM2 测试"}
    })
end)

sys.run()
```

### gmssl_sm2.lua
```lua
local sm2 = {}

function sm2.test_sm2_sign_verify()
    log.info("sm2", "开始 SM2 签名和验证测试")
    
    -- 生成 SM2 密钥对
    local pubkey, privkey = gmssl.sm2_genkey()
    assert(pubkey and privkey, "SM2 密钥生成失败")
    
    -- 准备待签名数据
    local data = "test message"
    
    -- 进行签名
    local signature = gmssl.sm2_sign(privkey, data)
    assert(signature, "SM2 签名失败")
    
    -- 验证签名
    local verify_result = gmssl.sm2_verify(pubkey, data, signature)
    assert(verify_result, "SM2 验证签名失败")
    
    log.info("sm2", "SM2 签名和验证测试通过")
end

function sm2.test_sm2_encrypt_decrypt()
    log.info("sm2", "开始 SM2 加密和解密测试")
    
    local pubkey, privkey = gmssl.sm2_genkey()
    
    -- 准备明文
    local plaintext = "secret data"
    
    -- 加密
    local ciphertext = gmssl.sm2_encrypt(pubkey, plaintext)
    assert(ciphertext, "SM2 加密失败")
    
    -- 解密
    local decrypted = gmssl.sm2_decrypt(privkey, ciphertext)
    assert(decrypted == plaintext, "SM2 解密失败或数据不匹配")
    
    log.info("sm2", "SM2 加密和解密测试通过")
end

return sm2
```

## 测试框架的工作流程

```
main.lua
  ├─> testrunner.run() / testrunner.runBatch()
  │   ├─> loadConfig()      # 加载配置文件
  │   ├─> initNetwork()     # 初始化网络连接
  │   ├─> runTests()        # 执行测试用例
  │   │   ├─> reportStatus() # 上报测试状态（running）
  │   │   ├─> testsuite.runTestSuite()  # 运行所有 test_ 函数
  │   │   └─> reportStatus() # 上报测试状态（passed/failed）
  │   └─> reportResult()    # 上报最终测试结果
```

## 关键模块说明

### testsuite.lua - 测试套件执行

负责发现和执行测试函数：
```lua
local suite = require("testsuite")
suite.runTestSuite(testTable)  -- 执行单个测试套件
suite.runMultipleTestSuites(test1, test2, ...) -- 执行多个测试套件
```

### testrunner.lua - 测试运行器

负责整个测试的流程控制：
```lua
local runner = require("testrunner")
-- 运行单个测试
runner.run(testTable, testcase, msg)

-- 运行多个测试
runner.runBatch({
    {testTable = t1, testcase = "test1"},
    {testTable = t2, testcase = "test2"}
})
```

### testreport.lua - 测试结果上报

上报测试状态和结果：
```lua
local report = require("testreport")
-- 上报测试状态（"running", "passed", "failed"）
report.reportStatus(ctx, testcase, status, msg)

-- 上报最终结果
report.send(ctx, result, testcase, msg)
```

## 编写测试用例的最佳实践

### 1. 命名规范

- 测试模块文件：`<feature>_test.lua` 或 `<feature>.lua`
- 测试函数：`test_<function_name>` 开头
- 测试用例目录：`<feature>_<variant>/`

```lua
-- 推荐的命名方式
function mymodule.test_create_user()
function mymodule.test_delete_user()
function mymodule.test_invalid_input()
function mymodule.test_boundary_case()
```

### 2. 测试隔离

每个测试函数应该是独立的，不依赖其他测试的结果：

```lua
-- 推荐：每个测试独立初始化
function mymodule.test_feature_a()
    local resource = initResource()
    -- ... 测试代码 ...
    cleanupResource(resource)
end

function mymodule.test_feature_b()
    local resource = initResource()  -- 重新初始化
    -- ... 测试代码 ...
    cleanupResource(resource)
end

-- 不推荐：依赖全局状态
local resource
function mymodule.test_feature_a()
    resource = initResource()
end

function mymodule.test_feature_b()
    -- 依赖 test_feature_a 的结果
    use(resource)
end
```

### 3. 错误消息

提供有意义的错误消息：

```lua
-- 推荐
assert(result == expected, 
    string.format("期望 %d，但得到 %d", expected, result))

-- 不推荐
assert(result == expected, "测试失败")
```

### 4. 日志记录

使用日志记录测试的关键步骤：

```lua
function mymodule.test_complex_operation()
    log.info("mymodule", "步骤 1: 初始化资源")
    local resource = initResource()
    
    log.info("mymodule", "步骤 2: 执行操作")
    local result = performOperation(resource)
    
    log.info("mymodule", "步骤 3: 验证结果")
    assert(result, "操作失败")
    
    log.info("mymodule", "步骤 4: 清理资源")
    cleanupResource(resource)
end
```

### 5. 处理异步操作

对于涉及异步操作的测试，使用适当的等待机制：

```lua
function mymodule.test_async_operation()
    log.info("mymodule", "开始异步操作测试")
    
    local result = nil
    -- 启动异步操作
    startAsyncOperation(function(response)
        result = response
    end)
    
    -- 等待结果（最多 5 秒）
    local wait_time = 0
    while not result and wait_time < 5000 do
        sys.wait(100)
        wait_time = wait_time + 100
    end
    
    assert(result, "异步操作超时")
    assert(result.success, "异步操作失败")
end
```

## 配置文件说明

测试框架使用 `/luadb/ctx.json` 配置文件，包含以下信息：

```json
{
    "timeout": 30000,
    "retry_count": 3,
    "wifi_ssid": "network_name",
    "wifi_password": "network_password",
    "report_url": "http://example.com/report",
    "status_url": "http://example.com/status",
    "runner_config": {
        "timeout": 30000
    }
}
```

- `timeout`: 网络连接超时时间（毫秒）
- `report_url`: 最终结果上报的服务器地址（可选）
- `status_url`: 测试状态实时上报的地址（可选）

## 常见问题

### Q: 如何跳过某个测试？
A: 临时修改函数名，去掉 `test_` 前缀：

```lua
-- 跳过这个测试
function mymodule.skip_test_feature()
    -- ...
end
```

### Q: 如何在测试中添加调试输出？
A: 使用 `log` 模块：

```lua
function mymodule.test_debug_example()
    log.debug("mymodule", "调试信息")
    log.info("mymodule", "普通信息")
    log.warn("mymodule", "警告信息")
    log.error("mymodule", "错误信息")
end
```

### Q: 如何处理测试中的网络依赖？
A: 在 `main.lua` 中调用 `network` 模块进行网络初始化，或依赖 `testrunner` 中的 `initNetwork()` 函数。

### Q: 测试的执行顺序是否有保证？
A: 测试的执行顺序依赖于 Lua 表的遍历顺序，不保证固定顺序。如果需要特定顺序，应该在同一个测试函数中依次执行。

## 相关文件

- `common/scripts/testsuite.lua` - 测试套件框架
- `common/scripts/testrunner.lua` - 测试运行器
- `common/scripts/testreport.lua` - 结果上报
- `common/scripts/network.lua` - 网络初始化
