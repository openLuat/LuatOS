# Air1601 编译与下载调试说明（COM10）

## 环境
- 设置环境变量：`CI_REPOS_PATH=D:\github`
- LuatOS 主库：`D:\github\LuatOS`
- SDK 工程：`D:\github\luatos-sdk-ccm42xx-gcc\csdk\project\luatos`
- 刷机工具：`D:\github\luatos-cli\target\release\luatos-cli.exe`
- 设备串口：`COM10`

## 编译 Air1601
在 SDK 工程目录执行：

```powershell
$env:CI_REPOS_PATH='D:\github'
Set-Location D:\github\luatos-sdk-ccm42xx-gcc\csdk\project\luatos
xmake
```

产物：
- `out\LuatOS-SoC_V1021_Air1601.soc`

## 下载与脚本下发

```powershell
$cli='D:\github\luatos-cli\target\release\luatos-cli.exe'
$soc='D:\github\luatos-sdk-ccm42xx-gcc\csdk\project\luatos\out\LuatOS-SoC_V1021_Air1601.soc'

# 整包刷机
& $cli flash run --soc $soc --port COM10

# 下发脚本目录（需包含 main.lua）
& $cli flash script --soc $soc --port COM10 --script <script_dir>
```

## 启动日志判定（建议统一）

```powershell
& $cli flash test --soc $soc --port COM10 --timeout 30 --keyword '### OVERALL_PASS ###' --keyword '### OVERALL_FAIL ###'
```

规则：
- 刷机流程应在 2 分钟内完成。
- 开机后 30 秒内必须出现 PASS/FAIL 关键词，否则按 FAIL 处理。

## 常见问题
- `lf.init` 失败：优先核对 SPI/CS/供电脚组合；当前板级已验证组合为 `spi2 + cs4 + pwr50`。
- 30 秒内无终态：先看是否卡在文件系统慢写（`/lfs2n`），再看脚本是否在失败后及时输出终态标记。
- 串口占用：关闭其他串口监控工具后重试。
