
## 演示功能概述
1、创建四路socket连接，详情如下

- 创建一个tcp client，连接tcp server；

- 创建一个udp client，连接udp server；（后续补充）

- 创建一个tcp ssl client，连接tcp ssl server，不做证书校验；（后续补充）

- 创建一个tcp ssl client，连接tcp ssl server，client仅单向校验server的证书，server不校验client的证书和密钥文件；（后续补充）

2、每一路socket连接出现异常后，自动重连；

3、每一路socket连接，client按照以下几种逻辑发送数据给server

- 串口应用功能模块uart_app.lua，通过uart1接收到串口数据，将串口数据增加send from uart: 前缀后发送给server；

- 定时器应用功能模块timer_app.lua，定时产生数据，将数据增加send from timer：前缀后发送给server；

4、每一路socket连接，client收到server数据后，将数据增加recv from tcp/udp/tcp ssl/tcp ssl ca（四选一）server: 前缀后，通过uart1发送出去；

5、每一路socket连接，启动一个网络业务逻辑看门狗task，用来监控socket工作状态，如果连续长时间工作不正常，重启整个软件系统（后续补充）；


## 演示硬件环境

1、Air8101核心板一块

2、TYPE-C USB数据线一根

3、USB转串口数据线一根

4、Air8101核心板和数据线的硬件接线方式为

- Air8101核心板通过TYPE-C USB口供电；（核心板背面的功耗测试开关拨到OFF一端）

- 如果测试发现软件频繁重启，重启原因值为：poweron reason 0，可能是供电不足，此时再通过直流稳压电源对核心板的VIN管脚进行5V供电；

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

- USB转串口数据线，一般来说，白线连接核心板的12/U1TX，绿线连接核心板的11/U1RX，黑线连接核心板的gnd，另外一段连接电脑USB口；


## 演示软件环境

1、Luatools下载调试工具

2、[Air8101 V1004版本固件](https://docs.openluat.com/air8101/luatos/firmware/)（理论上最新版本固件也可以，如果使用最新版本的固件不可以，可以烧录V1004固件对比验证）

3、PC端的串口工具，例如SSCOM、LLCOM等都可以；

4、PC端浏览器访问[合宙TCP/UDP web测试工具](https://netlab.luatos.com/)；


## 演示核心步骤

1、搭建好硬件环境

2、PC端浏览器访问[合宙TCP/UDP web测试工具](https://netlab.luatos.com/)，点击 打开TCP 按钮，会创建一个TCP server，将server的地址和端口赋值给tcp_client_main.lua中的SERVER_ADDR和SERVER_PORT两个变量

3、demo脚本代码wifi_app.lua中的wlan.connect("茶室-降功耗,找合宙!", "Air123456", 1)，前两个参数，修改为自己测试时wifi热点的名称和密码；注意：仅支持2.4G的wifi，不支持5G的wifi

4、Luatools烧录内核固件和修改后的demo脚本代码

5、烧录成功后，自动开机运行

6、[合宙TCP/UDP web测试工具](https://netlab.luatos.com/)上创建的TCP server，可以看到有设备连接上来，每隔5秒钟，会接收到一段类似于 send from timer: 1 的数据，最后面的数字每次加1

7、打开PC端的串口工具，选择对应的端口，配置波特率115200，数据位8，停止位1，无奇偶校验位；

8、PC端的串口工具上输入一段数据，点击发送，在[合宙TCP/UDP web测试工具](https://netlab.luatos.com/)可以接收到数据；

9、在[合宙TCP/UDP web测试工具](https://netlab.luatos.com/)的发送编辑框内，输入一段数据，点击发送，在PC端的串口工具上可以接受到这段数据；
   

