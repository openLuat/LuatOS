# AirCAMERA_1040 DEMO

## 演示功能概述

本示例主要是展示 AirCAMERA_1040 的使用，本地拍摄照片后通过 httpplus 扩展库将图片上传至 air32.com

1、main.lua：主程序入口

2、take_photo_http_post.lua：执行拍照后上传照片至 air32.com

3、scan_code.lua：扫描二维码应用DEMO

4、netdrv_4g.lua：联网状态检测模块

注意事项：

- 拍照或者扫描模式需要在摄像头初始化时确定
- 如使用拍照模式就无法使用扫描模式，扫描模式同理
- 需要拍照后执行扫描的话需要重新初始化
- 所以拍照和扫描不可同时使用，如需切换模式需重新初始化

## 演示功能概述

### 1、主程序入口模块（main.lua）

- 初始化项目信息和版本号
- 初始化看门狗，并定时喂狗
- 启动一个循环定时器，每隔 3 秒钟打印一次总内存，实时的已使用内存，历史最高的已使用内存情况方便分析内存使用是否有异常
- 加载 netdrv_4g 4G联网状态检测模块
- 加载 take_photo_http_post 模块（通过 require "take_photo_http_post"）

### 2、4G联网状态检测模块（netdrv_4g.lua）

- 订阅"IP_READY"消息，收到消息后打印联网成功日志
- 订阅"IP_LOSE"消息，收到消息后打印联网失败日志

### 3、拍照上传核心业务模块（take_photo_http_post.lua）

- 每 30 秒触发一次拍照：AirCAMERA_1040_func()
- 每 3 秒打印一次系统和 LUA 的内存信息：memory_check()
- 配置摄像头信息表：spi_camera_param
- 初始化摄像头：excamera.open()
- 执行拍照：excamera.photo()
- 上传照片：httpplus.request()
- 关闭摄像头：excamera.close()

### 4、扫描二维码应用DEMO（scan_code.lua）

- 每 30 秒触发一次拍照：AirCAMERA_1040_func()
- 每 3 秒打印一次系统和 LUA 的内存信息：memory_check()
- 配置摄像头信息表：spi_camera_param
- 初始化摄像头：excamera.open()
- 执行扫描：excamera.scan()
- 关闭摄像头：excamera.close()

## 演示硬件环境

1、Air8000系列 开发板一块

2、TYPE-C USB 数据线一根

3、合宙标准配件 AirCAMERA_1040 一个

4、Air8000系列 开发板和合宙标准配件 AirCAMERA_1040 的硬件接线方式为

Air8000系列 开发板通过 TYPE-C USB 口供电；（侧面拨码拨至USB供电）

TYPE-C USB 数据线直接插到开发板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

AirCAMERA_1040 配件板插入Air8000系列 开发板的SPI摄像头座子中

## 演示软件环境

1、Luatools 下载调试工具：[https://docs.openluat.com/air780epm/common/Luatools/](https://docs.openluat.com/air780epm/common/Luatools/)

2、固件版本：LuatOS-SoC_V2018_Air8000_1，固件地址，如有最新固件请用最新 https://docs.openluat.com/air8000/luatos/firmware/


## 演示核心步骤

1、搭建硬件环境;

2、烧录 DEMO 代码;

3、等待自动拍照完成后上传平台，LUATOOLS会有如下打印;
```lua
[2025-11-19 16:01:52.898][000000000.277] I2C_MasterSetup 426:I2C1, Total 65 HCNT 22 LCNT 40
[2025-11-19 16:01:52.905][000000000.367] I/user.初始化状态 true
[2025-11-19 16:01:52.910][000000000.367] CSPI_Rx 2000:block len 7680, total block 80
[2025-11-19 16:01:52.916][000000000.371] I/user.照片存储路径 ZBUFF*: 0C1AE288
[2025-11-19 16:01:52.923][000000000.372] luat_camera_capture_config 682:0,0,0,0
[2025-11-19 16:01:53.180][000000000.941] I/user.摄像头数据 68576
[2025-11-19 16:01:53.186][000000000.942] I/user.拍照完成
[2025-11-19 16:01:53.192][000000000.942] W/user.tcp_client_main_task_func wait IP_READY
[2025-11-19 16:01:54.492][000000002.228] D/mobile cid1, state0
[2025-11-19 16:01:54.498][000000002.228] D/mobile bearer act 0, result 0
[2025-11-19 16:01:54.504][000000002.230] D/mobile NETIF_LINK_ON -> IP_READY
[2025-11-19 16:01:54.510][000000002.234] D/socket connect to upload.air32.cn,80
[2025-11-19 16:01:54.513][000000002.235] dns_run 676:upload.air32.cn state 0 id 1 ipv6 0 use dns server2, try 0
[2025-11-19 16:01:54.521][000000002.250] D/mobile TIME_SYNC 0
[2025-11-19 16:01:54.525][000000002.288] dns_run 693:dns all done ,now stop
[2025-11-19 16:01:54.609][000000002.373] I/user.httpplus 等待服务器完成响应
[2025-11-19 16:01:55.453][000000003.207] I/user.httpplus 等待服务器完成响应
[2025-11-19 16:01:55.458][000000003.209] I/user.httpplus 服务器已完成响应,开始解析响应
[2025-11-19 16:01:55.464][000000003.228] I/user.http_upload_photo_task_func httpplus.request 200
[2025-11-19 16:01:55.470][000000003.229] I/user.剩余内存 2375432 71960 1603164
[2025-11-19 16:01:55.513][000000003.273] I/user.sys ram 2375432 71796 1603164
[2025-11-19 16:01:55.519][000000003.274] I/user.lua ram 1048568 157744 157744
```

4、等待自动扫描任务完成后，LUATOOLS会有如下打印;
```lua
[2025-11-21 15:19:17.310][000000000.269] I2C_MasterSetup 426:I2C1, Total 65 HCNT 22 LCNT 40
[2025-11-21 15:19:17.313][000000000.332] I/user.初始化状态 true
[2025-11-21 15:19:17.316][000000000.332] CSPI_Rx 2000:block len 7680, total block 40
[2025-11-21 15:19:17.319][000000000.541] I/user.扫码结果 Air780EPM
[2025-11-21 15:19:17.323][000000000.542] I/user.扫描完成，扫描结果为： Air780EPM
[2025-11-21 15:19:17.327][000000000.542] I/user.Scan result : Air780EPM
```

5、登录 https://www.air32.cn/upload/data/jpg/ 查看拍摄的照片;

![](https://docs.openluat.com/air8101/luatos/app/accessory/AirCAMERA_1020/image/httpupload.png)