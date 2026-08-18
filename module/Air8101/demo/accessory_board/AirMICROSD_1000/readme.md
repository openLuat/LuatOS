## **功能模块介绍**

本demo演示了在嵌入式环境中对TF卡（SD卡）的完整操作流程，使用 AirMICROSD_1000 直插式配件板，通过 SDIO 接口挂载。覆盖了从文件系统挂载到高级文件操作的完整功能链。项目分为两个核心模块：

1、main.lua：主程序入口 <br> 
2、AirMICROSD_1000.lua：TF卡基础应用模块，实现文件系统管理、文件操作和目录管理功能。<br> 
3、http_download_file.lua：HTTP下载模块，实现网络检测与文件下载到TF卡的功能

**注意事项：**
- Air8101 使用 SDIO 挂载时，必须使用 AirMICROSD_1000 直插式配件板
- SDIO 挂载支持 1-bit 模式，最高速率可达 24MHz
- 挂载前需要确保 GPIO13 供电控制引脚已拉高
- 如挂载失败，可调用 `fatfs.debug(1)` 开启调试模式查看详细错误信息

## **演示功能概述**

### 1、主程序入口模块（main.lua）

- 初始化项目信息和版本号
- 初始化看门狗，并定时喂狗
- 启动一个循环定时器，每隔3秒钟打印一次总内存，实时的已使用内存，历史最高的已使用内存情况方便分析内存使用是否有异常
- 加载AirMICROSD_1000模块（通过require "AirMICROSD_1000"）
- 加载http_download_file模块（通过require "http_download_file"）
- 最后运行sys.run()

### 2、TF卡核心演示模块（AirMICROSD_1000.lua）

#### 文件系统管理

- 挂载：
  - 使用 SDIO 接口挂载FAT32文件系统到`/sd`路径
  - 自动格式化检测与处理
- 空间信息获取：
  - 实时查询TF卡可用空间
  - 输出详细存储信息（总空间/剩余空间）
#### 文件操作
- 创建目录：io.mkdir("/sd/io_test")
- 创建/写入文件： io.open("/sd/io_test/boottime", "wb")
- 检查文件存在： io.exists(file_path)
- 获取文件大小：io.fileSize(file_path)
- 读取文件内容: io.open(file_path, "rb"):read("*a")
- 启动计数文件： 记录设备启动次数
- 文件追加： io.open(append_file, "a+")
- 按行读取： file:read("*l")
- 文件关闭： file:close()
- 文件重命名： os.rename(old_path, new_path)
- 列举目录： io.lsdir(dir_path)
- 删除文件： os.remove(file_path)
- 删除目录： io.rmdir(dir_path)

#### 结果处理

- 资源清理（卸载）

### 3、HTTP下载功能 (http_download_file.lua)

#### 文件系统管理

- 挂载sd卡（SDIO方式）

#### 网络就绪检测

- wifi链接
- 1秒循环等待IP就绪
- 网络故障处理机制

#### 安全下载

- HTTP下载

#### 结果处理

- 下载状态码解析
- 自动文件大小验证
- 资源清理（卸载）

## **演示硬件环境**

### **Air8101核心板**

1、Air8101核心板一块

2、TYPE-C USB数据线一根

3、闪迪C10高速TF卡一张（即micro SD卡，即微型SD卡）

4、AirMICROSD_1000配件板一块

5、Air8101核心板和数据线的硬件接线方式为

- Air8101核心板通过板上的TYPE-C USB口供电。（正面的开关拨到3.3V，背面的开关拨到off）
- TYPE-C USB数据线直接插到Air8101核心板的TYPE-C USB座子，另外一端连接电脑USB口；

6、Air8101核心板与AirMICROSD_1000配件板直插，对应管脚为
| Air8101 | AirMICROSD_1000配件板 |
| ------------- | ----------------- |
| 59/3V3        | 3V3               |
| gnd           | gnd               |
| 9/GPIO6       | CD                |
| 67/GPIO4      | D0                |
| 66/GPIO3      | CMD               |
| 65/GPIO2      | CLK               |

## **演示软件环境**

1、Luatools下载调试工具： https://docs.openluat.com/air780epm/common/Luatools/

2、内核固件版本：https://docs.openluat.com/air8101/luatos/firmware/

## **演示核心步骤**

1、搭建好硬件环境

2、通过Luatools将demo与固件烧录到开发板中

3、烧录好后，板子开机将会在Luatools上看到如下打印

```lua
（1）TF卡初始化与挂载
[2025-09-14 12:59:05.009] I/user.fatfs.mount	挂载成功	0
[2025-09-14 12:59:05.133] I/user.fatfs	getfree	{"free_sectors":244262144,"total_kb":122132480,"free_kb":122131072,"total_sectors":244264960}
[2025-09-14 12:59:05.133] I/user.fs	lsmount	[{"fs":"lfs2","path":"\/"},{"fs":"inline","path":"\/lua\/"},{"fs":"ram","path":"\/ram\/"},{"fs":"luadb","path":"\/luadb\/"},{"fs":"fatfs","path":"\/sd"}]

（2）文件操作演示
[2025-08-24 19:51:24.685][000000002.619] I/user.文件操作 ===== 开始文件操作 =====
[2025-08-24 19:51:25.145][000000003.032] I/user.io.mkdir 目录创建成功 路径:/sd/io_test
[2025-08-24 19:51:25.231][000000003.043] I/user.文件创建 文件写入成功 路径:/sd/io_test/boottime
[2025-08-24 19:51:25.297][000000003.046] I/user.io.exists 文件存在 路径:/sd/io_test/boottime
[2025-08-24 19:51:25.376][000000003.049] I/user.io.fileSize 文件大小:41字节 路径:/sd/io_test/boottime
[2025-08-24 19:51:25.467][000000003.052] I/user.io.readfile 路径:/sd/io_test/boottime 内容:这是io库API文档示例的测试内容
...（省略中间日志）
[2025-08-24 19:51:27.772][000000003.160] I/user.文件系统 卸载成功

（3）网络连接与HTTP下载
[2025-08-24 20:31:49.405][000000006.268] I/user.HTTP下载 开始下载任务
[2025-08-24 20:31:54.800][000000012.080] I/user.HTTP下载 下载完成 success 200 
[2025-08-24 20:31:54.936][000000012.082] I/user.HTTP下载 文件大小验证 预期: 411922 实际: 411922
[2025-08-24 20:31:54.979][000000012.083] I/user.HTTP下载 资源清理完成

```

## **AirMICROSD_1000 产品信息**

- 淘宝购买链接：https://item.taobao.com/item.htm?id=976139183501
- 产品特点：免杜邦线连接，避免数据异常/挂载失败
- 接口类型：SDIO（仅支持 Air8101 系列模组）

## **官方支持渠道**

- 合宙文档中心：https://docs.openluat.com/air8101/luatos/app/driver/sdcard/
- 技术支持：support@openluat.com
- SDIO 硬件设计参考：https://docs.openluat.com/air8101/luatos/hardware/design/sdcard/