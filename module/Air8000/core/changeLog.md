# Air8000模块固件更新 --- 修改记录

## 2025.05.21

1. 修复Air8000/Air8000G在进入休眠后，超过15s没有通过定时器或者外部唤醒，就会关机的问题。

2. 修复wdt.close() api没有正确生效的问题。
3. 修复usb_vuart虚拟串口无法正常触发rx回调。
4. 修复gt911触摸时i2c会读到0字节的问题。
5. 修复st7796旋转方向异常。
6. 支持触屏自动识别屏幕方向。
7. 脚本分区调整为512KB。
8. Air8000G模块会默认拉高gpio22。



## 2025.05.14

1. 修复httpsrv可能会导致死机的问题。

2. 修复pins配置WAKEUP、ADC、PWR_KEY、I2S时会打印报错信息。
3. 修复Air8000G也会启动Airlink导致休眠功耗高的问题。



## 2025.05.09

1. 修复AP、以太网WAN功能因DNS服务器问题，导致的上网通讯异常。



## 2025.05.08

1. 添加实现wlan.setMac，写入修改wifi sta的mac地址。
2. 优化I2C传输输入参数错误的情况和接收到0字节数据的情况。



## 2025.05.07

1. 以太网ch390通讯，取消强制休眠20ms的操作。
2. 优化websocket处理，兼容32k字节或以下的payload。
3. 修复ap+以太网wan功能，上网通讯可能导致死机的问题。
4. 修复读不到GNSS的串口数据。
5. 修复使用lvgl时，tp触摸回调不能正确触发。
6. 添加CAN获取时钟特性API,用于计算实际波特率，can.capacity(id)



## 2025.04.29

1. 修复libgnss设置uart回调没有成功，有"uartXX no received callback"的错误。
2. 修复libgnss，执行bind操作后无法拿到数据。
3. 修复lcd,on/off操作,使用RGB屏时不需要发送指令。
4. 修复air8000s脚本调用wlan.getMAC无法拿到MAC地址。
5. netdrv,ch390,支持中断模式,默认轮询模式。
6. 修复ch390 wan以太网转wifi_ap功能，使用其他设备连接wifi使用网络时，下载/上传 数据过多，会导致处理不过来无法上网的问题。
7. 硬件lcd接口增加软件cs控制，允许使用其他GPIO作为cs控制
8. zbuff的used()加入快速设置有效数据量的方法，可以不用seek
9. 支持wifi订阅的4个事件STA 连上、断开、AP 新STA连上、旧STA断开。
10. 修复lcd预览camera结束后显示异常



## 2025.04.25

1. VOLTE固件 将"开机自动打开Air8000s电源和配置netdrv的功能"关闭。如果是用_VOLTE的固件，并且有需要使用到 **WIFI功能** 或需要 **控制>100序号的GPIO** ，那则需要在主task开头单独执行一次下面的代码。

   ~~~lua
   sys.wait(10)		-- 刚开机稍微缓一下
   airlink.init()		-- 初始化airlink
   airlink.start(1)	-- 启动底层线程, 从机模式
   gpio.setup(23,1, gpio.PULLUP)   --打开Air8000S电源
   sys.wait(300)		-- 等一小段时间让Air8000S启动，然后再配置gpio或wifi
   ~~~

2. 修复VOLTE固件跑es8311初始化会失败，导致出现走cc库通话听不到声音或者说话对方听不到的情况。

   测试发现是Airlink在开机同步启动的原因引起的，如果需要使用es8311的同时 使用Air8000s的wifi功能，需要在es8311初始化之后，再手动添加运行下面代码启动Air8000S和配置netdrv。

   ~~~lua
   airlink.init()			-- 初始化airlink
   log.info("注册STA和AP设备")
   netdrv.setup(socket.LWIP_STA, netdrv.WHALE)
   netdrv.setup(socket.LWIP_AP, netdrv.WHALE)
   airlink.start(1)	 	-- 启动底层线程, 从机模式
   gpio.setup(23, 1) 		-- 打开Air8000S电源
   sys.wait(300)
   ~~~
   
3. 修复i2c有概率发送数据通讯失败的问题。

4. 支持fs库

5. 当前4G转wifi, 4G转以太网, wifi转以太网, 3个网络通道的排列组合的配网都已支持



## 2025.04.24

1. 支持FS功能。
2. 修复VOLTE固件 wifi_sta、wifi_ap、WAN功能，不能正常通网通信的问题。
3. socket链接 不使用tls方式建立的链接，最多可支持64个。
4. 添加wifi事件回调消息,详细用法看看 demo/airlink/air8000_wifi



## 2025.04.23 

1. wifi_sta模式下支持自动开启dhcp，不需要手动打开。
2. 支持默认加载sys和sysplus库，不需要额外在main.lua 中添加require "sys"和require "sysplus"了。
3. 能够支持air8000s wifi模块的fota操作。
4. 修复CAN功能通讯有异常的问题。
5. gpio新增VBUS,USIM_DET常量，可以通过gpio.VBUS和gpio.USIM_DET使用。



## 2025.04.18 

1. 支持CAN功能 
2. 修复使用部分lcd屏幕，显示色彩有偏差 。
3. 增加icmp库，可支持ping操作。
4. 支持最多同时建立32个socket链接。
5. 使用Air8000和Air8000G 带GNSS的模块，默认会将GNSS电源（gpio25）拉低。



## 2025.04.17

1. Air8000和Air8000W 默认打开Air8000S wifi芯片的供电，脚本中可以省略打开Air8000S的电源、airlink.init和airlink.start的操作了。
2. 80/81管脚默认作为i2c0使用，66/67管脚默认作为i2c1使用，不再需要mcu.altfun接口进行复用。
3. 增加 airlink.config接口，可配置AirLink的参数。



## 2025.04.15

1. 支持pins库，代替mcu.altfun复用接口的功能。
2. 支持VOLTE功能，由于VOLTE和LVGL两个功能占用空间很大，分成了两个版本的固件。
3. gpio24默认改为高电平
4. 添加软复位的通用指令，但当前只支持ch390，api：netdrv.ctrl(id, cmd, arg)