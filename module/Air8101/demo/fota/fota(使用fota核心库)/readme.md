## 功能模块介绍

1、main.lua：主程序入口；

2、fota_file.lua：介绍了使用文件系统进行FOTA升级功能的实现模块，包括完整的升级流程，文件系统是挂载的sd卡文件系统；

3、fota_uart.lua：介绍了使用串口分段进行FOTA升级功能的实现模块，包括完整的升级流程；

4、main.py：Python脚本工具，用于通过串口分段发送升级包，演示分段升级的流程；

5、fota_uart.bin：演示串口分段升级的升级包文件,升级内容仅升级版本号以及添加几行打印；

## 演示功能概述

FOTA是固件远程升级的简称，用于设备固件的远程更新和维护；

本demo演示的核心功能为：

Air8101模块的两种FOTA升级方式：文件系统直接升级和串口分段升级；

分两种不同的应用场景来演示固件升级的实现方法:

1、文件系统直接升级：通过模组文件系统中的文件直接升级,代码演示通过luatools的烧录文件系统功能将升级包文件直接烧录到文件系统然后升级；

2、分段升级：通过串口将升级包文件分多个片段发送，每个片段接收并写入,代码演示使用usb虚拟串口分段写入升级包升级；

适用场景：

    非标准数据传输 -> 串口、TCP、MQTT等自定义通道升级

    流程精细控制 -> 需要自定义升级前后处理逻辑

## 演示硬件环境

![](https://docs.openluat.com/air8101/luatos/app/socket/http/image/RsjSbrZAookedIxzxJAcfYuFnfe.png)

1、Air8101核心板一块；

2、闪迪C10高速TF卡一张（即micro SD卡，即微型SD卡）

3、AirMICROSD_1000配件板一块；

4、TYPE-C USB数据线一根 + USB转串口数据线一根，Air8101核心板和数据线的硬件接线方式为：

- Air8101核心板通过TYPE-C USB口供电；（外部供电/USB供电 拨动开关 拨到 USB供电一端）

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

5、Air8101核心板与AirMICROSD_1000配件板直插，对应管脚为
| Air8101/Air6101核心板 | AirMICROSD_1000配件板 |
| ------------- | ----------------- |
| 59/3V3        | 3V3               |
| gnd           | gnd               |
| 9/GPIO6       | CD                |
| 67/GPIO4      | D0                |
| 66/GPIO3      | CMD               |
| 65/GPIO2      | CLK               |

![](https://docs.openluat.com/air8101/luatos/app/driver/sdcard/image/1c02c13d0001814bcaaf2f14d0b1ab20.png)

## 演示软件环境

1、Luatools下载调试工具，需要注意的是luatools工具版本必须为3.1.10及以上版本，否则制作的升级包没办法升级。

2、[Air8101 V2001版本固件以上，25/12/17日后的固件）](https://docs.openluat.com/air8101/luatos/firmware/)

3、Python 3 环境（用于运行main.py发送升级包）

## 演示操作步骤

### 方式1：文件系统直接升级

1、搭建好演示硬件环境

2、修改demo脚本代码，取消`main.lua`中`require("fota_file")`的注释，注释掉`require("fota_uart")`

3、使用Luatools制作升级包，然后将升级包文件放到sd卡中，然后插入AirMICROSD_1000配件板中，然后将配件版链接Air8101核心板。

4、Luatools烧录内核固件和修改前的demo脚本代码。烧录成功后，开机运行。

5、可以看到如下日志：
日志分析如下：

1. 开始升级，读取文件系统目录下的升级包文件/sd/update.bin

2. FOTA初始化 → 底层就绪 → 文件写入 → MD5校验通过

3. 升级完成，版本验证成功

4. 设备自动重启

5. 新版本 1.0.1 正常运行，新增日志确认升级成功

结果：文件系统FOTA升级完全成功，版本从1.0.0升级到1.0.1

```lua
[2025-12-19 15:12:02.893] luat:I(581):pm:reset native reason: 0
[2025-12-19 15:12:02.893] luat:D(581):pm:boot up by power on
[2025-12-19 15:12:02.893] luat:D(581):pm:poweron reason 0
[2025-12-19 15:12:02.893] luat:D(582):main:STA MAC: C8C2C68CD602
[2025-12-19 15:12:02.893] luat:D(583):main:AP  MAC: C8C2C68CD603
[2025-12-19 15:12:02.893] ap1:mac:W(474):sync_base_mac_record, saved records is more than 1, free index(3).
[2025-12-19 15:12:02.893] luat:D(587):main:BLE MAC: C8C2C68CD604
[2025-12-19 15:12:02.893] luat:D(587):main:io voltage set to 3.3V
[2025-12-19 15:12:02.900] luat:D(587):main:UID: 54540D5E2E
[2025-12-19 15:12:02.900] luat:I(595):main:LuatOS@Air8101 base 25.11 bsp V2001 64bit
[2025-12-19 15:12:02.900] luat:I(595):main:ROM Build: Dec 17 2025 13:49:18
[2025-12-19 15:12:03.063] luat:W(753):pins:/luadb/pins_air8101.json not exist!!
[2025-12-19 15:12:03.063] luat:D(755):main:loadlibs luavm 2097144 20560 20560
[2025-12-19 15:12:03.063] luat:D(755):main:loadlibs sys   233872 33384 33384
[2025-12-19 15:12:03.063] luat:D(755):main:loadlibs psram 6291456 51472 69264
[2025-12-19 15:12:03.123] luat:U(807):I/user.main fota_test 001.000.000
[2025-12-19 15:12:04.100] luat:U(1808):I/user.fota version 001.000.000
[2025-12-19 15:12:05.113] luat:U(2808):I/user.fota version 001.000.000
[2025-12-19 15:12:06.124] luat:U(3808):I/user.fota version 001.000.000
[2025-12-19 15:12:07.102] luat:U(4808):I/user.fota version 001.000.000
[2025-12-19 15:12:08.116] luat:U(5808):I/user.fota version 001.000.000
[2025-12-19 15:12:09.128] luat:U(6808):I/user.fota version 001.000.000
[2025-12-19 15:12:10.107] luat:U(7808):I/user.fota version 001.000.000
[2025-12-19 15:12:11.125] luat:U(8808):I/user.fota version 001.000.000
[2025-12-19 15:12:12.102] luat:U(9808):I/user.fota version 001.000.000
[2025-12-19 15:12:13.122] luat:U(10808):I/user.fota version 001.000.000
[2025-12-19 15:12:13.124] luat:D(10826):fatfs:init FatFS at sdio
[2025-12-19 15:12:13.124] luat:D(10827):sdio:sdio gpio init : clk 2 cmd 3 data0 4 data1 5 data2 10 data3 11
[2025-12-19 15:12:13.401] luat:I(11085):fatfs:mount success at fat32
[2025-12-19 15:12:13.401] luat:U(11085):I/user.fatfs.mount 挂载成功 0
[2025-12-19 15:12:13.401] luat:U(11086):I/user.fatfs mount true
[2025-12-19 15:12:13.401] luat:U(11086):I/user.fatfs getfree {"free_sectors":31084608,"total_kb":15549952,"free_kb":15542304,"total_sectors":31099904}
[2025-12-19 15:12:13.401] luat:U(11087):I/user.FOTA_FILE === 开始文件系统升级 ===
[2025-12-19 15:12:13.401] luat:U(11087):I/user.FOTA_FILE 初始化FOTA...
[2025-12-19 15:12:13.401] luat:U(11087):I/user.FOTA_FILE 等待底层准备...
[2025-12-19 15:12:13.401] luat:U(11087):I/user.FOTA_FILE 底层准备就绪
[2025-12-19 15:12:13.401] luat:U(11088):I/user.FOTA_FILE 开始读取升级文件： /sd/update.bin
[2025-12-19 15:12:13.416] luat:I(11107):fota:升级包类型: type=1, expected_len=26056
[2025-12-19 15:12:13.789] luat:I(11475):fota:erase time used 307ms
[2025-12-19 15:12:13.883] luat:I(11573):fota:write time used 98ms
[2025-12-19 15:12:13.883] luat:I(11573):fota:FOTA progress: 26056 bytes written , total 486ms
[2025-12-19 15:12:13.883] luat:I(11573):fota:fota file write done, call fota.done()
[2025-12-19 15:12:13.883] luat:I(11573):fota:fota done, write 26056 bytes
[2025-12-19 15:12:13.883] luat:I(11573):fota:fota done success, call fota.end()
[2025-12-19 15:12:13.883] luat:U(11574):I/user.FOTA_FILE 升级文件写入flash中的fota分区结果 true true 0
[2025-12-19 15:12:13.883] luat:U(11574):I/user.FOTA_FILE 结束写入fota分区...
[2025-12-19 15:12:13.883] luat:U(11574):I/user.FOTA_FILE 写入fota分区状态 结果: true 完成: true
[2025-12-19 15:12:13.883] luat:U(11574):I/user.FOTA_FILE 升级成功，准备重启设备
[2025-12-19 15:12:14.115] luat:U(11808):I/user.fota version 001.000.000
[2025-12-19 15:12:15.125] luat:U(12808):I/user.fota version 001.000.000
[2025-12-19 15:12:15.935] ef:I(3):ENV start address is 0x007FA000, size is 8192 bytes.
[2025-12-19 15:12:15.935] ef:I(5):EasyFlash V4.1.0 is initialize success.
[2025-12-19 15:12:15.935] sensor:W(6):uncali sdmadc value:[0 0]
[2025-12-19 15:12:15.940] cal:W(19):temp in otp is:567
[2025-12-19 15:12:16.043] xtal_cali:76
[2025-12-19 15:12:16.043] cal:I(109):idx:40=40+(0),r:54,xtal:76,pwr_gain:a0ab7128
[2025-12-19 15:12:16.043] cal:I(118):idx:38=40+(-2),r:54,xtal:79,pwr_gain:a0ab7118
[2025-12-19 15:12:16.383] ap1:ef:I(0):ENV start address is 0x007FC000, size is 8192 bytes.
[2025-12-19 15:12:16.477] ap0:ef:I(433):EasyFlash V4.1.0 is initialize success.
[2025-12-19 15:12:16.477] ap1:WDRV:W(436):wdrv_tx_cmd_buffer_init, addr[0]=0x28012b4c, pattern_addr=0x28012b48
[2025-12-19 15:12:16.481] ap1:WDRV:W(437):wdrv_tx_cmd_buffer_init, addr[1]=0x28012e6c, pattern_addr=0x28012e68
[2025-12-19 15:12:16.481] ap1:WDRV:W(437):wdrv_tx_cmd_buffer_init, addr[2]=0x2801318c, pattern_addr=0x28013188
[2025-12-19 15:12:16.481] mac:W(556):sync_base_mac_record, saved records is more than 1, free index(3).
[2025-12-19 15:12:16.481] CIF:I(558):cif_handle_bk_cmd_lwipmem_addr_req,634,addr:0x2806b300
[2025-12-19 15:12:16.912] luat:I(14600):pm:reset native reason: 1
[2025-12-19 15:12:16.912] luat:D(14600):pm:boot up by reboot
[2025-12-19 15:12:16.912] luat:I(14600):pm:reset reason: SWRESET
[2025-12-19 15:12:16.912] luat:D(14600):pm:poweron reason 3
[2025-12-19 15:12:16.912] luat:D(14600):main:STA MAC: C8C2C68CD602
[2025-12-19 15:12:16.912] luat:D(14601):main:AP  MAC: C8C2C68CD603
[2025-12-19 15:12:16.921] ap1:mac:W(870):sync_base_mac_record, saved records is more than 1, free index(3).
[2025-12-19 15:12:16.921] luat:D(14606):main:BLE MAC: C8C2C68CD604
[2025-12-19 15:12:16.921] luat:D(14606):main:io voltage set to 3.3V
[2025-12-19 15:12:16.921] luat:D(14606):main:UID: 54540D5E2E
[2025-12-19 15:12:16.921] luat:I(14613):main:LuatOS@Air8101 base 25.11 bsp V2001 64bit
[2025-12-19 15:12:16.921] luat:I(14613):main:ROM Build: Dec 17 2025 13:49:18
[2025-12-19 15:12:17.083] luat:W(14775):pins:/luadb/pins_air8101.json not exist!!
[2025-12-19 15:12:17.088] luat:D(14777):main:loadlibs luavm 2097144 20560 20560
[2025-12-19 15:12:17.088] luat:D(14777):main:loadlibs sys   233872 33384 33384
[2025-12-19 15:12:17.088] luat:D(14777):main:loadlibs psram 6291456 51472 69264
[2025-12-19 15:12:17.145] luat:U(14829):I/user.main fota_test 001.000.001
[2025-12-19 15:12:18.154] luat:U(15830):I/user.fota version 001.000.001
[2025-12-19 15:12:18.154] luat:U(15831):I/user.8101fota test
[2025-12-19 15:12:18.157] luat:U(15849):I/user.FOTA_UART 开机自动启动串口升级模式
[2025-12-19 15:12:18.157] luat:D(15851):uart:uart(1) tx pin: 0, rx pin: 1
[2025-12-19 15:12:18.157] luat:U(15853):I/user.FOTA_UART 升级任务已启动，等待数据...
[2025-12-19 15:12:19.145] luat:U(16831):I/user.fota version 001.000.001
[2025-12-19 15:12:19.145] luat:U(16832):I/user.8101fota test
[2025-12-19 15:12:20.126] luat:U(17831):I/user.fota version 001.000.001
[2025-12-19 15:12:20.126] luat:U(17832):I/user.8101fota test
[2025-12-19 15:12:21.150] luat:U(18831):I/user.fota version 001.000.001
[2025-12-19 15:12:21.150] luat:U(18832):I/user.8101fota test
```

### 方式2：串口分段升级

1、搭建好演示硬件环境

2、修改demo脚本代码，确保`main.lua`中已注释`require("fota_file")`，取消`require("fota_uart")`的注释

3、使用Luatools制作升级包，先把新旧版本分别生成量产文件，然后再制作升级包，工具上栏 luatOS->固件工具->差分包/整包升级包制作，将制作好的升级包放在main.py同级目录下

4、Luatools烧录内核固件和修改前的demo脚本代码，烧录成功后，自动开机运行。

5、确认设备连接到电脑的串口（虚拟USB串口）

6、运行Python脚本发送升级包：
    注意修改核心板uart1接的串口线在电脑上的端口号

```lua
   python main.py -p COM13
```

7、脚本会自动寻找设备虚拟串口，发送升级命令并传输`fota_uart.bin`文件

8、设备接收并验证升级包，升级成功后会自动重启

9、可以看到如下日志：

串口分段升级日志解读：

1. uart1 串口连接，收到#FOTA起始指令

2. 开始分段接收升级包，每次256字节，累计5751字节

3. 所有数据包写入成功，MD5校验通过

4. 升级完成，重启

5. 重启后新版本1.0.2运行，新增日志确认升级成功

结果：串口FOTA升级完全成功，版本从1.0.0升级到1.0.2。
```lua
[2025-12-18 17:10:48.338] luat:U(951):I/user.main fota_test 001.000.000
[2025-12-18 17:10:49.369] luat:U(1952):I/user.fota version 001.000.000
[2025-12-18 17:10:49.416] luat:U(2007):I/user.FOTA_UART 开机自动启动串口升级模式
[2025-12-18 17:10:49.416] luat:D(2008):uart:uart(1) tx pin: 0, rx pin: 1
[2025-12-18 17:10:49.416] luat:U(2010):I/user.FOTA_UART 升级任务已启动，等待数据...
[2025-12-18 17:10:50.364] luat:U(2952):I/user.fota version 001.000.000
[2025-12-18 17:10:51.348] luat:U(3952):I/user.fota version 001.000.000
[2025-12-18 17:10:52.359] luat:U(4952):I/user.fota version 001.000.000
[2025-12-18 17:10:53.340] luat:U(5952):I/user.fota version 001.000.000
[2025-12-18 17:10:54.028] luat:U(6616):I/user.uart 收到数据 6 累计 6
[2025-12-18 17:10:54.028] luat:U(6616):I/user.UART_FOTA 首次收到数据，发布升级信号
[2025-12-18 17:10:54.028] luat:U(6617):I/user.UART_FOTA 等待数据...
[2025-12-18 17:10:54.028] luat:U(6617):I/user.fota 检测到fota起始标记,进入FOTA状态 #FOTA
[2025-12-18 17:10:54.028]
[2025-12-18 17:10:54.358] luat:U(6952):I/user.fota version 001.000.000
[2025-12-18 17:10:55.090] luat:U(7675):I/user.uart 收到数据 544 累计 550
[2025-12-18 17:10:55.090] luat:U(7675):I/user.UART_FOTA 首次收到数据，发布升级信号
[2025-12-18 17:10:55.090] luat:U(7675):I/user.UART_FOTA 等待数据...
[2025-12-18 17:10:55.090] luat:U(7676):I/user.准备写入fota包 544 累计写入 544
[2025-12-18 17:10:55.090] luat:U(7676):D/user.fota.run true false 1
[2025-12-18 17:10:55.090] luat:U(7676):I/user.fota 单包写入完成 544 等待下一个包
[2025-12-18 17:10:55.114] luat:U(7717):I/user.uart 收到数据 480 累计 1030
[2025-12-18 17:10:55.114] luat:U(7717):I/user.UART_FOTA 首次收到数据，发布升级信号
[2025-12-18 17:10:55.114] luat:U(7717):I/user.UART_FOTA 等待数据...
[2025-12-18 17:10:55.114] luat:U(7718):I/user.准备写入fota包 480 累计写入 1024
[2025-12-18 17:10:55.114] luat:U(7718):D/user.fota.run true false 1
[2025-12-18 17:10:55.114] luat:U(7718):I/user.fota 单包写入完成 480 等待下一个包
[2025-12-18 17:10:55.356] luat:U(7952):I/user.fota version 001.000.000
[2025-12-18 17:10:56.123] luat:U(8733):I/user.uart 收到数据 1024 累计 2054
[2025-12-18 17:10:56.123] luat:U(8733):I/user.UART_FOTA 首次收到数据，发布升级信号
[2025-12-18 17:10:56.123] luat:U(8734):I/user.UART_FOTA 等待数据...
[2025-12-18 17:10:56.123] luat:U(8734):I/user.准备写入fota包 1024 累计写入 2048
[2025-12-18 17:10:56.123] luat:I(8734):fota:升级包类型: type=1, expected_len=26056
[2025-12-18 17:10:56.123] luat:U(8734):D/user.fota.run true false 1
[2025-12-18 17:10:56.123] luat:U(8735):I/user.fota 单包写入完成 1024 等待下一个包
[2025-12-18 17:10:56.355] luat:U(8952):I/user.fota version 001.000.000
[2025-12-18 17:10:57.153] luat:U(9747):I/user.uart 收到数据 1024 累计 3078
[2025-12-18 17:10:57.153] luat:U(9747):I/user.UART_FOTA 首次收到数据，发布升级信号
[2025-12-18 17:10:57.153] luat:U(9747):I/user.UART_FOTA 等待数据...
[2025-12-18 17:10:57.153] luat:U(9748):I/user.准备写入fota包 1024 累计写入 3072
[2025-12-18 17:10:57.153] luat:U(9748):D/user.fota.run true false 1
[2025-12-18 17:10:57.153] luat:U(9748):I/user.fota 单包写入完成 1024 等待下一个包
[2025-12-18 17:10:57.355] luat:U(9952):I/user.fota version 001.000.000
[2025-12-18 17:10:58.165] luat:U(10758):I/user.uart 收到数据 1024 累计 4102
[2025-12-18 17:10:58.165] luat:U(10758):I/user.UART_FOTA 首次收到数据，发布升级信号
[2025-12-18 17:10:58.165] luat:U(10758):I/user.UART_FOTA 等待数据...
[2025-12-18 17:10:58.165] luat:U(10759):I/user.准备写入fota包 1024 累计写入 4096
[2025-12-18 17:10:58.165] luat:U(10759):D/user.fota.run true false 1
[2025-12-18 17:10:58.165] luat:U(10759):I/user.fota 单包写入完成 1024 等待下一个包
[2025-12-18 17:10:58.367] luat:U(10952):I/user.fota version 001.000.000
[2025-12-18 17:10:59.176] luat:U(11771):I/user.uart 收到数据 1024 累计 5126
[2025-12-18 17:10:59.176] luat:U(11771):I/user.UART_FOTA 首次收到数据，发布升级信号
[2025-12-18 17:10:59.176] luat:U(11772):I/user.UART_FOTA 等待数据...
[2025-12-18 17:10:59.176] luat:U(11772):I/user.准备写入fota包 1024 累计写入 5120
[2025-12-18 17:10:59.176] luat:U(11772):D/user.fota.run true false 1
[2025-12-18 17:10:59.176] luat:U(11772):I/user.fota 单包写入完成 1024 等待下一个包
[2025-12-18 17:10:59.361] luat:U(11952):I/user.fota version 001.000.000
[2025-12-18 17:11:00.190] luat:U(12784):I/user.uart 收到数据 1024 累计 6150
[2025-12-18 17:11:00.190] luat:U(12784):I/user.UART_FOTA 首次收到数据，发布升级信号
[2025-12-18 17:11:00.190] luat:U(12784):I/user.UART_FOTA 等待数据...
[2025-12-18 17:11:00.190] luat:U(12785):I/user.准备写入fota包 1024 累计写入 6144
[2025-12-18 17:11:00.190] luat:U(12785):D/user.fota.run true false 1
[2025-12-18 17:11:00.190] luat:U(12785):I/user.fota 单包写入完成 1024 等待下一个包
[2025-12-18 17:11:00.362] luat:U(12952):I/user.fota version 001.000.000
[2025-12-18 17:11:01.187] luat:U(13785):I/user.uart 收到数据 1024 累计 7174
[2025-12-18 17:11:01.187] luat:U(13785):I/user.UART_FOTA 首次收到数据，发布升级信号
[2025-12-18 17:11:01.187] luat:U(13785):I/user.UART_FOTA 等待数据...
[2025-12-18 17:11:01.211] luat:U(13786):I/user.准备写入fota包 1024 累计写入 7168
[2025-12-18 17:11:01.211] luat:U(13786):D/user.fota.run true false 1
[2025-12-18 17:11:01.211] luat:U(13786):I/user.fota 单包写入完成 1024 等待下一个包
[2025-12-18 17:11:01.345] luat:U(13952):I/user.fota version 001.000.000
[2025-12-18 17:11:02.194] luat:U(14788):I/user.uart 收到数据 1024 累计 8198
[2025-12-18 17:11:02.194] luat:U(14788):I/user.UART_FOTA 首次收到数据，发布升级信号
[2025-12-18 17:11:02.194] luat:U(14788):I/user.UART_FOTA 等待数据...
[2025-12-18 17:11:02.194] luat:U(14789):I/user.准备写入fota包 1024 累计写入 8192
[2025-12-18 17:11:02.194] luat:U(14789):D/user.fota.run true false 1
[2025-12-18 17:11:02.194] luat:U(14789):I/user.fota 单包写入完成 1024 等待下一个包
[2025-12-18 17:11:02.366] luat:U(14952):I/user.fota version 001.000.000
[2025-12-18 17:11:03.195] luat:U(15789):I/user.uart 收到数据 1024 累计 9222
[2025-12-18 17:11:03.195] luat:U(15789):I/user.UART_FOTA 首次收到数据，发布升级信号
[2025-12-18 17:11:03.195] luat:U(15789):I/user.UART_FOTA 等待数据...
[2025-12-18 17:11:03.195] luat:U(15790):I/user.准备写入fota包 1024 累计写入 9216
[2025-12-18 17:11:03.195] luat:U(15790):D/user.fota.run true false 1
[2025-12-18 17:11:03.195] luat:U(15790):I/user.fota 单包写入完成 1024 等待下一个包
[2025-12-18 17:11:03.367] luat:U(15952):I/user.fota version 001.000.000
[2025-12-18 17:11:04.203] luat:U(16797):I/user.uart 收到数据 1024 累计 10246
[2025-12-18 17:11:04.203] luat:U(16797):I/user.UART_FOTA 首次收到数据，发布升级信号
[2025-12-18 17:11:04.203] luat:U(16797):I/user.UART_FOTA 等待数据...
[2025-12-18 17:11:04.203] luat:U(16798):I/user.准备写入fota包 1024 累计写入 10240
[2025-12-18 17:11:04.203] luat:U(16798):D/user.fota.run true false 1
[2025-12-18 17:11:04.203] luat:U(16798):I/user.fota 单包写入完成 1024 等待下一个包
[2025-12-18 17:11:04.358] luat:U(16952):I/user.fota version 001.000.000
[2025-12-18 17:11:05.201] luat:U(17798):I/user.uart 收到数据 1024 累计 11270
[2025-12-18 17:11:05.201] luat:U(17798):I/user.UART_FOTA 首次收到数据，发布升级信号
[2025-12-18 17:11:05.201] luat:U(17798):I/user.UART_FOTA 等待数据...
[2025-12-18 17:11:05.201] luat:U(17799):I/user.准备写入fota包 1024 累计写入 11264
[2025-12-18 17:11:05.201] luat:U(17799):D/user.fota.run true false 1
[2025-12-18 17:11:05.201] luat:U(17799):I/user.fota 单包写入完成 1024 等待下一个包
[2025-12-18 17:11:05.358] luat:U(17952):I/user.fota version 001.000.000
[2025-12-18 17:11:06.219] luat:U(18813):I/user.uart 收到数据 1024 累计 12294
[2025-12-18 17:11:06.219] luat:U(18813):I/user.UART_FOTA 首次收到数据，发布升级信号
[2025-12-18 17:11:06.219] luat:U(18813):I/user.UART_FOTA 等待数据...
[2025-12-18 17:11:06.219] luat:U(18814):I/user.准备写入fota包 1024 累计写入 12288
[2025-12-18 17:11:06.219] luat:U(18814):D/user.fota.run true false 1
[2025-12-18 17:11:06.219] luat:U(18814):I/user.fota 单包写入完成 1024 等待下一个包
[2025-12-18 17:11:06.358] luat:U(18952):I/user.fota version 001.000.000
[2025-12-18 17:11:07.232] luat:U(19827):I/user.uart 收到数据 1024 累计 13318
[2025-12-18 17:11:07.232] luat:U(19827):I/user.UART_FOTA 首次收到数据，发布升级信号
[2025-12-18 17:11:07.232] luat:U(19827):I/user.UART_FOTA 等待数据...
[2025-12-18 17:11:07.232] luat:U(19828):I/user.准备写入fota包 1024 累计写入 13312
[2025-12-18 17:11:07.232] luat:U(19828):D/user.fota.run true false 1
[2025-12-18 17:11:07.232] luat:U(19828):I/user.fota 单包写入完成 1024 等待下一个包
[2025-12-18 17:11:07.356] luat:U(19952):I/user.fota version 001.000.000
[2025-12-18 17:11:08.229] luat:U(20839):I/user.uart 收到数据 1024 累计 14342
[2025-12-18 17:11:08.229] luat:U(20839):I/user.UART_FOTA 首次收到数据，发布升级信号
[2025-12-18 17:11:08.229] luat:U(20839):I/user.UART_FOTA 等待数据...
[2025-12-18 17:11:08.229] luat:U(20840):I/user.准备写入fota包 1024 累计写入 14336
[2025-12-18 17:11:08.229] luat:U(20840):D/user.fota.run true false 1
[2025-12-18 17:11:08.229] luat:U(20840):I/user.fota 单包写入完成 1024 等待下一个包
[2025-12-18 17:11:08.353] luat:U(20952):I/user.fota version 001.000.000
[2025-12-18 17:11:09.257] luat:U(21850):I/user.uart 收到数据 1024 累计 15366
[2025-12-18 17:11:09.257] luat:U(21850):I/user.UART_FOTA 首次收到数据，发布升级信号
[2025-12-18 17:11:09.257] luat:U(21850):I/user.UART_FOTA 等待数据...
[2025-12-18 17:11:09.257] luat:U(21851):I/user.准备写入fota包 1024 累计写入 15360
[2025-12-18 17:11:09.257] luat:U(21851):D/user.fota.run true false 1
[2025-12-18 17:11:09.257] luat:U(21851):I/user.fota 单包写入完成 1024 等待下一个包
[2025-12-18 17:11:09.366] luat:U(21952):I/user.fota version 001.000.000
[2025-12-18 17:11:10.272] luat:U(22866):I/user.uart 收到数据 1024 累计 16390
[2025-12-18 17:11:10.272] luat:U(22866):I/user.UART_FOTA 首次收到数据，发布升级信号
[2025-12-18 17:11:10.272] luat:U(22866):I/user.UART_FOTA 等待数据...
[2025-12-18 17:11:10.272] luat:U(22867):I/user.准备写入fota包 1024 累计写入 16384
[2025-12-18 17:11:10.272] luat:U(22867):D/user.fota.run true false 1
[2025-12-18 17:11:10.272] luat:U(22867):I/user.fota 单包写入完成 1024 等待下一个包
[2025-12-18 17:11:10.362] luat:U(22952):I/user.fota version 001.000.000
[2025-12-18 17:11:11.284] luat:U(23880):I/user.uart 收到数据 1024 累计 17414
[2025-12-18 17:11:11.284] luat:U(23880):I/user.UART_FOTA 首次收到数据，发布升级信号
[2025-12-18 17:11:11.284] luat:U(23880):I/user.UART_FOTA 等待数据...
[2025-12-18 17:11:11.284] luat:U(23881):I/user.准备写入fota包 1024 累计写入 17408
[2025-12-18 17:11:11.284] luat:U(23881):D/user.fota.run true false 1
[2025-12-18 17:11:11.284] luat:U(23881):I/user.fota 单包写入完成 1024 等待下一个包
[2025-12-18 17:11:11.362] luat:U(23952):I/user.fota version 001.000.000
[2025-12-18 17:11:12.284] luat:U(24881):I/user.uart 收到数据 1024 累计 18438
[2025-12-18 17:11:12.284] luat:U(24881):I/user.UART_FOTA 首次收到数据，发布升级信号
[2025-12-18 17:11:12.284] luat:U(24881):I/user.UART_FOTA 等待数据...
[2025-12-18 17:11:12.284] luat:U(24882):I/user.准备写入fota包 1024 累计写入 18432
[2025-12-18 17:11:12.284] luat:U(24882):D/user.fota.run true false 1
[2025-12-18 17:11:12.284] luat:U(24882):I/user.fota 单包写入完成 1024 等待下一个包
[2025-12-18 17:11:12.363] luat:U(24952):I/user.fota version 001.000.000
[2025-12-18 17:11:13.299] luat:U(25894):I/user.uart 收到数据 1024 累计 19462
[2025-12-18 17:11:13.299] luat:U(25894):I/user.UART_FOTA 首次收到数据，发布升级信号
[2025-12-18 17:11:13.299] luat:U(25894):I/user.UART_FOTA 等待数据...
[2025-12-18 17:11:13.299] luat:U(25895):I/user.准备写入fota包 1024 累计写入 19456
[2025-12-18 17:11:13.299] luat:U(25895):D/user.fota.run true false 1
[2025-12-18 17:11:13.299] luat:U(25895):I/user.fota 单包写入完成 1024 等待下一个包
[2025-12-18 17:11:13.361] luat:U(25952):I/user.fota version 001.000.000
[2025-12-18 17:11:14.300] luat:U(26896):I/user.uart 收到数据 1024 累计 20486
[2025-12-18 17:11:14.300] luat:U(26896):I/user.UART_FOTA 首次收到数据，发布升级信号
[2025-12-18 17:11:14.300] luat:U(26896):I/user.UART_FOTA 等待数据...
[2025-12-18 17:11:14.300] luat:U(26897):I/user.准备写入fota包 1024 累计写入 20480
[2025-12-18 17:11:14.300] luat:U(26897):D/user.fota.run true false 1
[2025-12-18 17:11:14.300] luat:U(26897):I/user.fota 单包写入完成 1024 等待下一个包
[2025-12-18 17:11:14.361] luat:U(26952):I/user.fota version 001.000.000
[2025-12-18 17:11:15.301] luat:U(27897):I/user.uart 收到数据 1024 累计 21510
[2025-12-18 17:11:15.301] luat:U(27897):I/user.UART_FOTA 首次收到数据，发布升级信号
[2025-12-18 17:11:15.301] luat:U(27897):I/user.UART_FOTA 等待数据...
[2025-12-18 17:11:15.301] luat:U(27898):I/user.准备写入fota包 1024 累计写入 21504
[2025-12-18 17:11:15.301] luat:U(27898):D/user.fota.run true false 1
[2025-12-18 17:11:15.301] luat:U(27898):I/user.fota 单包写入完成 1024 等待下一个包
[2025-12-18 17:11:15.362] luat:U(27952):I/user.fota version 001.000.000
[2025-12-18 17:11:16.306] luat:U(28901):I/user.uart 收到数据 1024 累计 22534
[2025-12-18 17:11:16.306] luat:U(28901):I/user.UART_FOTA 首次收到数据，发布升级信号
[2025-12-18 17:11:16.306] luat:U(28901):I/user.UART_FOTA 等待数据...
[2025-12-18 17:11:16.306] luat:U(28902):I/user.准备写入fota包 1024 累计写入 22528
[2025-12-18 17:11:16.306] luat:U(28902):D/user.fota.run true false 1
[2025-12-18 17:11:16.306] luat:U(28902):I/user.fota 单包写入完成 1024 等待下一个包
[2025-12-18 17:11:16.367] luat:U(28952):I/user.fota version 001.000.000
[2025-12-18 17:11:17.309] luat:U(29904):I/user.uart 收到数据 1024 累计 23558
[2025-12-18 17:11:17.309] luat:U(29904):I/user.UART_FOTA 首次收到数据，发布升级信号
[2025-12-18 17:11:17.309] luat:U(29904):I/user.UART_FOTA 等待数据...
[2025-12-18 17:11:17.309] luat:U(29905):I/user.准备写入fota包 1024 累计写入 23552
[2025-12-18 17:11:17.309] luat:U(29905):D/user.fota.run true false 1
[2025-12-18 17:11:17.309] luat:U(29905):I/user.fota 单包写入完成 1024 等待下一个包
[2025-12-18 17:11:17.355] luat:U(29952):I/user.fota version 001.000.000
[2025-12-18 17:11:18.312] luat:U(30906):I/user.uart 收到数据 1024 累计 24582
[2025-12-18 17:11:18.312] luat:U(30906):I/user.UART_FOTA 首次收到数据，发布升级信号
[2025-12-18 17:11:18.312] luat:U(30906):I/user.UART_FOTA 等待数据...
[2025-12-18 17:11:18.312] luat:U(30907):I/user.准备写入fota包 1024 累计写入 24576
[2025-12-18 17:11:18.312] luat:U(30907):D/user.fota.run true false 1
[2025-12-18 17:11:18.312] luat:U(30907):I/user.fota 单包写入完成 1024 等待下一个包
[2025-12-18 17:11:18.338] luat:U(30952):I/user.fota version 001.000.000
[2025-12-18 17:11:19.326] luat:U(31921):I/user.uart 收到数据 1024 累计 25606
[2025-12-18 17:11:19.326] luat:U(31921):I/user.UART_FOTA 首次收到数据，发布升级信号
[2025-12-18 17:11:19.326] luat:U(31921):I/user.UART_FOTA 等待数据...
[2025-12-18 17:11:19.326] luat:U(31922):I/user.准备写入fota包 1024 累计写入 25600
[2025-12-18 17:11:19.326] luat:U(31922):D/user.fota.run true false 1
[2025-12-18 17:11:19.326] luat:U(31922):I/user.fota 单包写入完成 1024 等待下一个包
[2025-12-18 17:11:19.351] luat:U(31952):I/user.fota version 001.000.000
[2025-12-18 17:11:20.293] luat:U(32886):I/user.uart 收到数据 456 累计 26062
[2025-12-18 17:11:20.293] luat:U(32886):I/user.UART_FOTA 首次收到数据，发布升级信号
[2025-12-18 17:11:20.293] luat:U(32886):I/user.UART_FOTA 等待数据...
[2025-12-18 17:11:20.293] luat:U(32887):I/user.准备写入fota包 456 累计写入 26056
[2025-12-18 17:11:20.619] luat:I(33218):fota:erase time used 331ms
[2025-12-18 17:11:20.729] luat:I(33317):fota:write time used 99ms
[2025-12-18 17:11:20.729] luat:I(33317):fota:FOTA progress: 26056 bytes written , total 26700ms
[2025-12-18 17:11:20.729] luat:U(33318):D/user.fota.run true true 0
[2025-12-18 17:11:20.729] luat:U(33319):I/user.fota version 001.000.000
[2025-12-18 17:11:20.822] luat:I(33418):fota:fota done, write 26056 bytes
[2025-12-18 17:11:20.822] luat:U(33418):I/user.fota 已完成,1s后重启
[2025-12-18 17:11:21.709] luat:U(34318):I/user.fota version 001.000.000
[2025-12-18 17:11:21.866] ef:I(3):ENV start address is 0x007FA000, size is 8192 bytes.
[2025-12-18 17:11:21.876] ef:I(5):EasyFlash V4.1.0 is initialize success.
[2025-12-18 17:11:21.876] sensor:W(6):uncali sdmadc value:[0 0]
[2025-12-18 17:11:21.876] cal:W(19):temp in otp is:565
[2025-12-18 17:11:21.975] xtal_cali:76
[2025-12-18 17:11:21.975] cal:I(105):idx:40=40+(0),r:54,xtal:76,pwr_gain:acab7128
[2025-12-18 17:11:21.983] cal:I(115):idx:38=40+(-2),r:54,xtal:79,pwr_gain:acab7118
[2025-12-18 17:11:22.319] ap1:ef:I(0):ENV start address is 0x007FC000, size is 8192 bytes.
[2025-12-18 17:11:22.411] ap0:ef:I(433):EasyFlash V4.1.0 is initialize success.
[2025-12-18 17:11:22.416] ap1:WDRV:W(436):wdrv_tx_cmd_buffer_init, addr[0]=0x28012b4c, pattern_addr=0x28012b48
[2025-12-18 17:11:22.416] ap1:WDRV:W(437):wdrv_tx_cmd_buffer_init, addr[1]=0x28012e6c, pattern_addr=0x28012e68
[2025-12-18 17:11:22.416] ap1:WDRV:W(437):wdrv_tx_cmd_buffer_init, addr[2]=0x2801318c, pattern_addr=0x28013188
[2025-12-18 17:11:22.416] mac:W(554):sync_base_mac_record, saved records is more than 1, free index(2).
[2025-12-18 17:11:22.416] CIF:I(555):cif_handle_bk_cmd_lwipmem_addr_req,634,addr:0x2806b300
[2025-12-18 17:11:22.880] luat:I(35462):pm:reset native reason: 1
[2025-12-18 17:11:22.880] luat:D(35462):pm:boot up by reboot
[2025-12-18 17:11:22.880] luat:I(35462):pm:reset reason: SWRESET
[2025-12-18 17:11:22.880] luat:D(35462):pm:poweron reason 3
[2025-12-18 17:11:22.880] luat:D(35463):main:STA MAC: C8C2C68C5D3E
[2025-12-18 17:11:22.902] luat:D(35464):main:AP  MAC: C8C2C68C5D3F
[2025-12-18 17:11:22.902] ap1:mac:W(891):sync_base_mac_record, saved records is more than 1, free index(2).
[2025-12-18 17:11:22.902] luat:D(35468):main:BLE MAC: C8C2C68C5D40
[2025-12-18 17:11:22.902] luat:D(35468):main:io voltage set to 3.3V
[2025-12-18 17:11:22.902] luat:D(35468):main:UID: 54540D4935
[2025-12-18 17:11:22.902] luat:I(35476):main:LuatOS@Air8101 base 25.11 bsp V2001 64bit
[2025-12-18 17:11:22.902] luat:I(35476):main:ROM Build: Dec 17 2025 13:49:18
[2025-12-18 17:11:23.134] luat:W(35694):pins:/luadb/pins_air8101.json not exist!!
[2025-12-18 17:11:23.134] luat:D(35697):main:loadlibs luavm 2097144 20560 20560
[2025-12-18 17:11:23.134] luat:D(35697):main:loadlibs sys   233872 33384 33384
[2025-12-18 17:11:23.134] luat:D(35697):main:loadlibs psram 6291456 51472 69264
[2025-12-18 17:11:23.291] luat:U(35846):I/user.main fota_test 001.000.001
[2025-12-18 17:11:24.283] luat:U(36847):I/user.fota version 001.000.001
[2025-12-18 17:11:24.283] luat:U(36847):I/user.8101fota test
[2025-12-18 17:11:24.342] luat:U(36902):I/user.FOTA_UART 开机自动启动串口升级模式
[2025-12-18 17:11:24.342] luat:D(36904):uart:uart(1) tx pin: 0, rx pin: 1
[2025-12-18 17:11:24.342] luat:U(36905):I/user.FOTA_UART 升级任务已启动，等待数据...
[2025-12-18 17:11:25.296] luat:U(37848):I/user.fota version 001.000.001
[2025-12-18 17:11:25.296] luat:U(37848):I/user.8101fota test
[2025-12-18 17:11:26.282] luat:U(38848):I/user.fota version 001.000.001
[2025-12-18 17:11:26.282] luat:U(38848):I/user.8101fota test

```

main.py 日志：
```lua
D:\gitee_hz\LuatOS_demo_v2_temp\module\Air8101\demo\fota\fota(使用fota核心库)>python main.py -p COM13
使用串口: COM13
设备响应 b'#FOTA RDY\n'
发送升级包数据 1024
设备响应 b'#FOTA NEXT\n#FOTA NEXT\n'
发送升级包数据 1024
设备响应 b'#FOTA NEXT\n'
发送升级包数据 1024
设备响应 b'#FOTA NEXT\n'
发送升级包数据 1024
设备响应 b'#FOTA NEXT\n'
发送升级包数据 1024
设备响应 b'#FOTA NEXT\n'
发送升级包数据 1024
设备响应 b'#FOTA NEXT\n'
发送升级包数据 1024
设备响应 b'#FOTA NEXT\n'
发送升级包数据 1024
设备响应 b'#FOTA NEXT\n'
发送升级包数据 1024
设备响应 b'#FOTA NEXT\n'
发送升级包数据 1024
设备响应 b'#FOTA NEXT\n'
发送升级包数据 1024
设备响应 b'#FOTA NEXT\n'
发送升级包数据 1024
设备响应 b'#FOTA NEXT\n'
发送升级包数据 1024
设备响应 b'#FOTA NEXT\n'
发送升级包数据 1024
设备响应 b'#FOTA NEXT\n'
发送升级包数据 1024
设备响应 b'#FOTA NEXT\n'
发送升级包数据 1024
设备响应 b'#FOTA NEXT\n'
发送升级包数据 1024
设备响应 b'#FOTA NEXT\n'
发送升级包数据 1024
设备响应 b'#FOTA NEXT\n'
发送升级包数据 1024
设备响应 b'#FOTA NEXT\n'
发送升级包数据 1024
设备响应 b'#FOTA NEXT\n'
发送升级包数据 1024
设备响应 b'#FOTA NEXT\n'
发送升级包数据 1024
设备响应 b'#FOTA NEXT\n'
发送升级包数据 1024
设备响应 b'#FOTA NEXT\n'
发送升级包数据 1024
设备响应 b'#FOTA NEXT\n'
发送升级包数据 1024
设备响应 b'#FOTA NEXT\n'
发送升级包数据 456
设备响应 b'#FOTA OK\n'
发送完毕,退出
```


