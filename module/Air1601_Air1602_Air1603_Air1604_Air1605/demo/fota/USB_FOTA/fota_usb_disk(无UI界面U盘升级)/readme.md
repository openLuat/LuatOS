## 功能模块介绍

1、main.lua：主程序入口；

2、fota_usb_disk.lua：U盘FOTA升级功能模块（无UI界面通用版），包括完整的升级流程：U盘座供电 → USB切主机 → 等待U盘 → 挂载 → 分块读取升级包 → fota.run写入 → 校验 → 重启；

## 适用模块

本demo为**通用版本**，脚本不需要修改即可适用于以下模块（同为Air1603平台家族，Lua API一致）：

- **Air8607w**
- **Air8603 系列**（8603w/8603m 等各型号）
- **Air8605 系列**（8605w 等各型号）

**唯一需要按硬件确认的地方**是脚本顶部的 `USB_PWR_PIN`（U盘供电使能脚UVC_EN）：

| 模块/硬件 | 供电使能脚 | 依据 |
|---|---|---|
| Air8603 开发板 | GPIO58（PIN58） | 原理图P4：J14 USB-A母座的+5.5V由U0022(JW5357S)产生，EN接UVC_EN |
| Air8605 开发板 | GPIO58 | 原理图第3/9页：J14人脸识别USB Type-A母座的+5.5V由JW5357升压产生，EN接UVC_EN（模块PIN48=SPI5_MOSI/GPIO58） |
| Air8607w / 自研板 | 按各自原理图确认 | 同平台大概率也是GPIO58(UVC_EN)；如USB座是直供5V无使能脚，把 `USB_PWR_PIN` 改成 `nil` 即可跳过供电步骤 |

## 固件要求（重要）

本demo依赖固件编译了 **usb库主机模式（usb.HOST + usb.MSC大容量存储）** 和 **fatfs库的USB挂载（fatfs.USB）**，缺任何一个都无法工作：

- Air1603/Air1602平台当前公开固件 V1028/V1030 的usb库只包含 HID键鼠（V1028）和UVC摄像头（V1030），**不包含U盘MSC支持**；
- U盘MSC/fatfs.USB挂载功能需要 **V1031及以后版本固件**（仓库官方demo module/Air8603/demo/sd_usb_transfer 的readme中明确说明）；
- 101号/102号固件均可使用（两者仅脚本区/文件系统分区大小不同，本demo脚本很小）；
- 如果固件不支持，脚本运行到USB相关调用时会报错，请向合宙获取带MSC支持的固件版本。

## 演示功能概述

本demo演示Air8000系列模块通过U盘进行本地FOTA升级（无UI界面通用版）：

设备USB默认工作在从机模式（虚拟串口），开机5秒后自动切换为主机模式并等待U盘；插入带有升级包的U盘后，设备自动完成U盘座供电、挂载、读取、写入fota分区、校验和重启升级；

升级过程没有屏幕等UI交互，全程通过日志观察；

## 演示硬件环境

1、Air8000 核心板一块

2、TYPE-C USB数据线一根，Air8000 核心板和数据线的硬件接线方式为：

- Air8000 核心板通过TYPE-C USB口供电；（外部供电/USB供电 拨动开关 拨到 USB供电一端）

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口（用于供电和烧录脚本）；

3、FAT32单分区格式的U盘一个（存放升级包）；**不要使用多合一读卡器**（MSC驱动只处理LUN 0，如果LUN 0是空卡槽会导致枚举一直失败），建议普通单分区U盘，USB2.0兼容性更好；

4、如需通过物理串口观察日志，准备USB转串口数据线一根，连接核心板的UART0日志串口；

**注意**：设备进入U盘升级模式后，USB切换为HOST主机模式，USB虚拟串口（CDC）功能不可用，此时luatools无法再通过USB虚拟串口看日志，日志请走UART0物理日志串口；

## 演示软件环境

1、Luatools下载调试工具

2、Air8000内核固件（需确认固件版本包含usb库主机模式和fatfs的USB挂载支持，usb库为2025.12.15之后新增，V2016版本固件可能不支持，如不支持请更新固件）

## 升级包制作

使用Luatools制作升级包，先把新旧版本分别生成量产文件，然后再制作升级包，工具上栏 luatOS->固件工具->差分包/整包升级包制作；

制作好的升级包文件**必须重命名为 update.bin**，放到U盘根目录下；

U盘需要格式化为**FAT32**格式；

## 演示操作步骤

1、搭建好演示硬件环境

2、使用Luatools烧录内核固件和本demo的脚本代码，烧录成功后，自动开机运行；日志中循环打印当前版本号（如 fota version 1.0.0）；

3、开机后等待5秒，设备自动进入U盘升级模式（无需任何按键操作），日志输出：

```
I/user.FOTA_USB_DISK 开机5秒, 自动进入U盘升级模式
I/user.FOTA_USB_DISK === 进入U盘升级模式 ===
I/user.FOTA_USB_DISK U盘供电脚GPIO 58 已拉高
I/user.FOTA_USB_DISK 请插入带有升级包的U盘, 升级包路径应为: /udisk/update.bin
```

4、插入带有update.bin的U盘，设备自动检测到U盘并开始升级，日志输出：

```
I/user.FOTA_USB_DISK 检测到U盘插入 app_id 0
I/user.FOTA_USB_DISK U盘挂载成功: /udisk
I/user.FOTA_USB_DISK 准备写入fota包 4096 累计读取 4096
I/fota write common data
I/user.fota.run true false 1
I/user.FOTA_USB_DISK 准备写入fota包 4096 累计读取 8192
...（重复分块写入）
I/fota common data done, now checking 0
I/fota common data md5 ok
I/fota fota type 0 ok!, wait reboot
I/user.FOTA_USB_DISK 校验通过, 升级成功, 1s后重启
```

5、设备自动重启，重启后新版本运行，日志中版本号变化确认升级成功（如 fota version 1.0.1）；

## 错误场景说明

| 现象 | 日志提示 | 处理方式 |
|---|---|---|
| 超时未插U盘 | 等待U盘插入超时 30000 ms | 重新上电后再插U盘；检查U盘座供电（GPIO58）是否正常 |
| 枚举失败/反复拔插 | U盘已拔出（尚未挂载成功） | 换普通单分区U盘（不要用多合一读卡器）；检查供电与D+/D-接线 |
| U盘挂载失败 | U盘挂载失败, 请确认U盘为FAT32格式（带3次重试日志） | 格式化U盘为FAT32后重试 |
| 找不到升级包 | 找不到升级包文件: /udisk/update.bin | 确认升级包已重命名为update.bin并放在U盘根目录 |
| 升级包损坏/不完整 | 升级包不完整或写入出错, 升级失败 | 重新制作升级包 |

以上错误场景设备均会自动恢复USB为从机模式，重新上电即可再次升级（开机5秒后自动重新进入升级模式）；

## 与其他fota demo的关系

- 本demo的数据来源是U盘文件，写入方式仿照 fota(使用fota核心库) 目录下的 fota_uart.lua（zbuff缓冲 + fota.run分段写入），文件路径固定用法仿照同目录下的 fota_file.lua（固定 /update.bin 路径）；
- 有UI界面版本的U盘升级demo，参考同级的 fota_usb_disk(有UI界面U盘升级) 目录（如有）；
