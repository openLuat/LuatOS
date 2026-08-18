# VL53L1X 激光红外测距传感器演示

## 一、功能模块介绍

### 1.1 核心主程序模块

1. **main.lua** - 主程序入口，负责项目初始化、版本定义和任务调度
2. **vl53l1x_demo.lua** - VL53L1X 功能演示模块，包含标准测距、模式切换、休眠唤醒、持续测距等所有功能的演示用例

### 1.2 扩展库模块

1. **exs_vl53l1x** - VL53L1X 扩展库，提供初始化、测距数据读取、模式切换、睡眠/唤醒、关闭等 API

## 二、演示流程介绍

本 demo 按顺序演示 exs_vl53l1x 扩展库的 4 项功能：HELLO → [1/4] → [2/4] → [3/4] → [4/4] → End

### 2.1 功能演示项说明

1. **[1/5] 标准测距** - 初始化传感器，连续读取 5 次距离数据（默认 standard 模式）
2. **[2/4] 测距模式切换** - 演示 short（抗强光）和 long（远距离）两种模式切换
3. **[3/4] 休眠与唤醒** - 演示 sleep() 进入软件待机、wakeup() 唤醒恢复测距
4. **[4/4] 持续测距** - 演示 sleep() 进入软件待机、wakeup() 唤醒恢复测距
** - 每隔 1 秒读取一次距离数据，共 5 次

## 三、演示硬件环境

### 3.1 硬件清单

- Air8101 核心板 × 1
- VL53L1X 激光红外测距传感器模块（如 GY-VL53L1X 等） × 1
  demo所演示的VL53L1X 激光红外测距传感器模块[购买链接](https://item.taobao.com/item.htm?app=chrome&bxsign=scd0Y1aCFssu5WNBf4zgfL9PHTC771hSBaYQhJANVSUUTh2awzexyQyuQSg4mN6Pbloj55y5X5F66iW6hytMgKrQauVMZK_2eg_EVTNPrAckp1M2aoTVhEBdqhZFkPdhK0r&cpp=1&h5_spm=a-tb-item.b-tb-item&id=597981154375&share_crt_v=1&shareurl=true&short_name=h.8XEIWwnTbGSsdlI&sp_tk=MGdwOGd0NWtvME0%3D&spm=a2159r.13376460.0.0&tbSocialPopKey=shareItem&tk=0gp8gt5ko0M&un=33e3e4902f14a2acade3a8129ff9a52d&un_site=0&ut_sk=1.aHcpu1x%2F2XQDACU%2ByKbrGPzO_21646297_1784598506860.TaoPassword-WeiXin.1&wxsign=tbwRNA5Uhd58zJzNm2egOHG_-dy1Cgfx7h_MWqBNsxfXGOARu2O3Fc6t-RivRx0dfSe2M0HcrjjRwaVMelu4sxeZQ-Sg6ckAT9CCpBMe0GKHQ-1vgswN6QAK7KQCMvOfph_&x-ssr=true)

- 母对母杜邦线 × 4
- TYPE-C 数据线 × 1

### 3.2 接线配置

#### 3.2.1 I2C 模式接线

<table>
<tr>
<td>Air8101 核心板<br/></td><td>VL53L1X 模块<br/></td></tr>
<tr>
<td>67/GPIO4<br/></td><td>SCL<br/></td></tr>
<tr>
<td>8/GPIO5<br/></td><td>SDA<br/></td></tr>
<tr>
<td>vbat<br/></td><td>VCC（3.3V）<br/></td></tr>
<tr>
<td>gnd<br/></td><td>GND<br/></td></tr>
</table>

> 说明：接线时注意杜邦线不宜过长，以免通信不稳定。VL53L1X 模块上的 SCL/SDA 通常已集成上拉电阻，无需额外配置。XSHUT 引脚不接时传感器会自动启动。

![](https://docs.openluat.com/cdn/image/Air8101_exs_vl53l1x.png)

## 四、演示软件环境

### 4.1 开发工具

- [Luatools下载调试工具](https://docs.openluat.com/air8101/luatos/common/download/) - 固件烧录和代码调试

### 4.2 内核固件

- [点击下载Air8101系列最新版本内核固件](https://docs.openluat.com/air8101/luatos/firmware/)，demo所使用的是 LuatOS-SoC_V2018_Air8101_101.soc

### 4.3 脚本文件

1. **main.lua** - 程序入口
2. **vl53l1x_demo.lua** - VL53L1X 功能演示模块
3. **exs_vl53l1x** - VL53L1X 扩展库

## 五、演示核心步骤

### 5.1 硬件准备

1. 按照接线表将 VL53L1X 模块连接到核心板
2. 确保电源连接正确，通过 TYPE-C USB 口供电
3. 检查所有接线无误，避免短路

### 5.2 软件配置

在 `main.lua` 中加载对应的演示模块：

```lua
-- 加载 vl53l1x_demo.lua 演示模块
require "vl53l1x_demo"
```

### 5.3 软件烧录

1. 使用 Luatools 选择最新内核固件
2. 下载本项目所有脚本文件
3. 将固件和脚本一起烧录到设备
4. 烧录成功后设备自动重启后开始运行

### 5.4 功能测试

#### 5.4.1 标准测距演示

1. 设备启动后打印 "HELLO"，随后自动进入 [1/5] 标准测距
2. 观察日志输出，确认初始化成功（应看到 `MID=0xEA MT=0xCC`）
3. 观察距离数据（单位 mm）的连续读取，共 5 次

#### 5.4.2 测距模式切换演示

1. 自动进入 [2/4] 测距模式切换
2. short 模式：抗环境光干扰最强，适合窗口附近等强光环境
3. long 模式：最远可测约 3.6m，适合室内暗光远距离场景

#### 5.4.3 休眠与唤醒演示

1. 自动进入 [3/4] 休眠与唤醒演示
2. 读一次当前距离作为参考
3. sleep() 进入软件待机（约 6μA），3 秒后 wakeup() 唤醒恢复测距
4. 观察唤醒后测距是否正常恢复

#### 5.4.4 持续测距演示

1. 自动进入 [4/4] 持续测距演示
2. 每隔 1 秒读取一次距离数据，共 5 次
3. 观察数据稳定性与状态码

### 5.5 预期效果

- **标准测距**：初始化成功，距离数据正常输出
- **模式切换**：short/long 模式均能正常读取距离
- **休眠唤醒**：sleep 后停止测距，wakeup 后测距恢复正常
- **持续测距**：每秒一帧数据，状态码 0（测距成功）
- **日志如下：**
```lua
[2026-07-21 20:27:23.860][CPU2][LTOS/N][000000000.599]:LuatOS@Air8101 base 26.04 bsp V2018 64bit
[2026-07-21 20:27:23.863][CPU2][LTOS/N][000000000.599]:ROM Build: Jul  7 2026 14:14:30
[2026-07-21 20:27:23.871][CPU1][LTOS/N][000000000.647]:/luadb/pins_air8101.json not exist!!
[2026-07-21 20:27:23.875][CPU1][LTOS/N][000000000.650]:loadlibs luavm 2097144 19136 19216
[2026-07-21 20:27:23.884][CPU1][LTOS/N][000000000.650]:loadlibs sys   224464 29736 29736
[2026-07-21 20:27:23.888][CPU1][LTOS/N][000000000.650]:loadlibs psram 6291456 51344 69432
[2026-07-21 20:27:23.897][CPU1][LTOS/N][000000000.667]:I/user.main VL53L1X_Demo 001.999.000
[2026-07-21 20:27:23.901][CPU1][LTOS/N][000000000.682]:I/user.vl53l1x_demo HELLO
[2026-07-21 20:27:24.850][CPU1][LTOS/N][000000001.682]:I/user.vl53l1x_demo ===== [1/5] 标准测距 =====
[2026-07-21 20:27:24.856][CPU2][LTOS/N][000000001.692]:I/user.exs_vl53l1x 固件就绪 0x00E5=0x03
[2026-07-21 20:27:24.880][CPU2][LTOS/N][000000001.705]:I/user.exs_vl53l1x 预设模式配置写入完成 (mode=standard)
[2026-07-21 20:27:24.883][CPU2][LTOS/N][000000001.706]:I/user.exs_vl53l1x 芯片 MID=0xEA MT=0xCC
[2026-07-21 20:27:25.083][CPU1][LTOS/N][000000001.906]:I/user.exs_vl53l1x 初始化完成，Standard Ranging 测距已启动
[2026-07-21 20:27:25.311][CPU1][LTOS/N][000000002.146]:I/user.vl53l1x_demo 第1次: 距离=273mm 状态=测距成功 stream=1
[2026-07-21 20:27:25.827][CPU1][LTOS/N][000000002.648]:I/user.vl53l1x_demo 第2次: 距离=264mm 状态=测距成功 stream=2
[2026-07-21 20:27:26.328][CPU1][LTOS/N][000000003.150]:I/user.vl53l1x_demo 第3次: 距离=266mm 状态=测距成功 stream=3
[2026-07-21 20:27:26.824][CPU1][LTOS/N][000000003.652]:I/user.vl53l1x_demo 第4次: 距离=260mm 状态=测距成功 stream=4
[2026-07-21 20:27:27.323][CPU1][LTOS/N][000000004.154]:I/user.vl53l1x_demo 第5次: 距离=265mm 状态=测距成功 stream=5
[2026-07-21 20:27:27.832][CPU2][LTOS/N][000000004.656]:I/user.exs_vl53l1x 传感器已关闭
[2026-07-21 20:27:28.335][CPU1][LTOS/N][000000005.156]:I/user.vl53l1x_demo ===== [2/5] 测距模式切换 =====
[2026-07-21 20:27:28.340][CPU1][LTOS/N][000000005.156]:I/user.vl53l1x_demo 切换 short 模式（抗强光）
[2026-07-21 20:27:28.345][CPU2][LTOS/N][000000005.166]:I/user.exs_vl53l1x 固件就绪 0x00E5=0x03
[2026-07-21 20:27:28.369][CPU2][LTOS/N][000000005.179]:I/user.exs_vl53l1x 芯片 MID=0xEA MT=0xCC
[2026-07-21 20:27:28.553][CPU1][LTOS/N][000000005.380]:I/user.exs_vl53l1x 初始化完成，Standard Ranging 测距已启动
[2026-07-21 20:27:28.770][CPU2][LTOS/N][000000005.609]:I/user.vl53l1x_demo short 模式: 距离=0mm 状态=串扰信号
[2026-07-21 20:27:28.778][CPU1][LTOS/N][000000005.611]:I/user.exs_vl53l1x 传感器已关闭
[2026-07-21 20:27:28.782][CPU1][LTOS/N][000000005.611]:I/user.vl53l1x_demo 切换 long 模式（远距离）
[2026-07-21 20:27:28.828][CPU2][LTOS/N][000000005.634]:I/user.exs_vl53l1x 芯片 MID=0xEA MT=0xCC
[2026-07-21 20:27:29.018][CPU1][LTOS/N][000000005.835]:I/user.exs_vl53l1x 初始化完成，Standard Ranging 测距已启动
[2026-07-21 20:27:29.267][CPU1][LTOS/N][000000006.089]:I/user.vl53l1x_demo long 模式: 距离=271mm 状态=测距成功
[2026-07-21 20:27:29.273][CPU2][LTOS/N][000000006.091]:I/user.exs_vl53l1x 传感器已关闭
[2026-07-21 20:27:29.278][CPU2][LTOS/N][000000006.091]:I/user.vl53l1x_demo ---- [2/5] 完成 ----
[2026-07-21 20:27:29.765][CPU1][LTOS/N][000000006.591]:I/user.vl53l1x_demo ===== [4/5] 休眠与唤醒演示 =====
[2026-07-21 20:27:29.831][CPU1][LTOS/N][000000006.616]:I/user.exs_vl53l1x 预设模式配置写入完成 (mode=standard)
[2026-07-21 20:27:29.839][CPU1][LTOS/N][000000006.617]:I/user.exs_vl53l1x 芯片 MID=0xEA MT=0xCC
[2026-07-21 20:27:30.000][CPU1][LTOS/N][000000006.818]:I/user.exs_vl53l1x 初始化完成，Standard Ranging 测距已启动
[2026-07-21 20:27:30.220][CPU2][LTOS/N][000000007.057]:I/user.vl53l1x_demo 休眠前: 距离=266mm 状态=测距成功
[2026-07-21 20:27:30.230][CPU2][LTOS/N][000000007.057]:I/user.vl53l1x_demo 进入软件待机模式
[2026-07-21 20:27:30.238][CPU1][LTOS/N][000000007.059]:I/user.exs_vl53l1x 已进入软件待机
[2026-07-21 20:27:33.259][CPU1][LTOS/N][000000010.059]:I/user.vl53l1x_demo 从软件待机模式唤醒
[2026-07-21 20:27:33.268][CPU1][LTOS/N][000000010.070]:I/user.exs_vl53l1x 已从软件待机唤醒，测距已恢复
[2026-07-21 20:27:33.482][CPU2][LTOS/N][000000010.308]:I/user.vl53l1x_demo 唤醒后: 距离=268mm 状态=测距成功
[2026-07-21 20:27:33.486][CPU1][LTOS/N][000000010.310]:I/user.exs_vl53l1x 传感器已关闭
[2026-07-21 20:27:33.495][CPU1][LTOS/N][000000010.310]:I/user.vl53l1x_demo ---- [4/5] 完成 ----
[2026-07-21 20:27:33.981][CPU1][LTOS/N][000000010.810]:I/user.vl53l1x_demo ===== [5/5] 持续测距演示 =====
[2026-07-21 20:27:33.991][CPU1][LTOS/N][000000010.819]:I/user.exs_vl53l1x 固件就绪 0x00E5=0x03
[2026-07-21 20:27:34.042][CPU1][LTOS/N][000000010.833]:I/user.exs_vl53l1x 预设模式配置写入完成 (mode=standard)
[2026-07-21 20:27:34.064][CPU1][LTOS/N][000000010.834]:I/user.exs_vl53l1x 芯片 MID=0xEA MT=0xCC
[2026-07-21 20:27:34.214][CPU1][LTOS/N][000000011.034]:I/user.exs_vl53l1x 初始化完成，Standard Ranging 测距已启动
[2026-07-21 20:27:35.255][CPU2][LTOS/N][000000012.073]:I/user.vl53l1x_demo 持续测距[1]: 距离=272mm 状态=测距成功
[2026-07-21 20:27:36.233][CPU1][LTOS/N][000000013.075]:I/user.vl53l1x_demo 持续测距[2]: 距离=266mm 状态=测距成功
[2026-07-21 20:27:37.255][CPU1][LTOS/N][000000014.077]:I/user.vl53l1x_demo 持续测距[3]: 距离=263mm 状态=测距成功
[2026-07-21 20:27:38.238][CPU1][LTOS/N][000000015.079]:I/user.vl53l1x_demo 持续测距[4]: 距离=261mm 状态=测距成功
[2026-07-21 20:27:39.261][CPU1][LTOS/N][000000016.081]:I/user.vl53l1x_demo 持续测距[5]: 距离=263mm 状态=测距成功
[2026-07-21 20:27:39.270][CPU2][LTOS/N][000000016.083]:I/user.exs_vl53l1x 传感器已关闭
[2026-07-21 20:27:39.275][CPU2][LTOS/N][000000016.083]:I/user.vl53l1x_demo ---- [5/5] 完成 ----
[2026-07-21 20:27:39.761][CPU1][LTOS/N][000000016.583]:I/user.vl53l1x_demo ===== [演示完毕] =====
```

### 5.6 故障排除

1. **传感器初始化失败**：

   - 检查 VL53L1X 接线是否正确（SCL、SDA、VCC、GND）
   - 确认 GPIO 引脚配置与接线一致
   - 检查电源电压是否稳定（3.3V）
   - 确认 exs_vl53l1x 扩展库已正常加载

2. **读取数据始终为 0 或异常**：

   - 检查传感器供电是否正常
   - 确认 I2C 地址是否正确（默认 0x29）
   - 确认接线无松动

3. **测距状态码异常**：

   - 状态码 1（Sigma 失效）：测量波动太大，目标反射率过低
   - 状态码 2（信号失效）：信号太弱，目标距离过远或反射率低
   - 状态码 9（串扰信号）：有保护玻璃串扰，可运行串扰校准
   - 状态码 14（范围无效）：通常对应第一帧无效数据，会自动跳过

### 5.7 扩展功能建议

exs_vl53l1x 更多接口的使用可以查看 [exs_vl53l1x 扩展库说明](https://docs.openluat.com/osapi/ext/sensor/exs_vl53l1x/)
