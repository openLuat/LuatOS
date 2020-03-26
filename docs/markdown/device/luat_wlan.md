# WLAN

## 基本信息

* 起草日期：2020-01-14
* 设计人员：[freestrong @ Snail]

## 为什么需要WLAN中间件管理WIFI
随着物联网快速发展，越来越多的嵌入式设备上搭载了 WIFI 无线网络设备。为了能够管理 WIFI 网络设备，RT-Thread 引入了 WLAN 设备管理框架。这套框架具备控制和管理 WIFI 的众多功能，为开发者使用 WIFI 设备提供许多便利。

## 设计思路和边界
 * 管理并抽象Wlan的C API, 提供一套Lua API供用户代码调用
## 相关知识点

* [RT-Thread WLAN设备管理](https://www.rt-thread.org/document/site/programming-manual/device/wlan/wlan/)


## C API(平台层)

```c
#define Luat_WLAN_SECURITY_OPEN             0x00
#define Luat_WLAN_SECURITY_WEP_PSK          0x01
#define Luat_WLAN_SECURITY_WEP_SHARED       0x02
#define Luat_WLAN_SECURITY_WPA_TKIP_PSK     0x03
#define Luat_WLAN_SECURITY_WPA_AES_PSK      0x04
#define Luat_WLAN_SECURITY_WPA2_AES_PSK     0x05
#define Luat_WLAN_SECURITY_WPA2_TKIP_PSK    0x06
#define Luat_WLAN_SECURITY_WPA2_MIXED_PSK   0x07
#define Luat_WLAN_SECURITY_WPS_OPEN         0x08
#define Luat_WLAN_SECURITY_WPS_SECURE       0x09

#define Luat_WLAN_EVT_READY                 0x01
#define Luat_WLAN_EVT_SCAN_DONE             0x02
#define Luat_WLAN_EVT_SCAN_REPORT           0x03
#define Luat_WLAN_EVT_STA_CONNECTED         0x04
#define Luat_WLAN_EVT_STA_CONNECTED_FAIL    0x05
#define Luat_WLAN_EVT_STA_DISCONNECTED      0x06
#define Luat_WLAN_EVT_AP_START		        0x07
#define Luat_WLAN_EVT_AP_STOP               0x08
#define Luat_WLAN_EVT_AP_ASSOCIATED         0x09
#define Luat_WLAN_EVT_AP_DISASSOCIATED      0x0A


/* 网络 */
int luat_wlan_set_stanet(luat_wlan_net_t * net)    //设置STA的网络信息
luat_wlan_net_t luat_wlan_get_stanet(void)         //获取STA的网络信息

int luat_wlan_set_apnet(luat_wlan_net_t * net)     //设置AP的网络信息
luat_wlan_net_t luat_wlan_get_apnet(void)          //获取AP的网络信息


/* WLAN 连接 */
int luat_wlan_connect(luat_wlan_info_t *info);	    //连接热点
int luat_wlan_is_ready(void);	                    //获取就绪标志
luat_wlan_info_t luat_wlan_get_info(void);          //获取连接信息
int luat_wlan_get_rssi(void);	                    //获取信号强度

/* WLAN 扫描 */
luat_wlan_info_t luat_wlan_scan_with_info(void);    //扫描

/* WLAN 热点 */
int luat_wlan_start_ap(luat_wlan_info_t);           //启动热点
int luat_wlan_ap_is_active(void);                   //获取启动标志
int luat_wlan_ap_stop(void);                        //停止热点
luat_wlan_info_t luat_wlan_ap_get_info(void);       //获取热点信息
luat_wlan_info_t luat_wlan_ap_get_stainfo(void);    //获取连接热点的Station信息

/* WLAN 事件回调 */
int luat_wlan_register_event_handler(int evt);      //事件注册
int luat_wlan_unregister_event_handler(int evt));   //解除注册

/* WLAN 功耗管理 */
int luat_wlan_set_powersave(int level);             //设置功耗等级，用于 station 模式。
int luat_wlan_get_powersave(void);                  //获取功耗等级
```


## 常量
```lua
--安全模式
wlan.OPEN                        --Open security
wlan.WEP_PSK                     --WEP Security with open authentication
wlan.WEP_SHARED                  --WEP Security with shared authentication
wlan.WPA_TKIP_PSK                --WPA Security with TKIP
wlan.WPA_AES_PSK                 --WPA Security with AES
wlan.WPA2_AES_PSK                --WPA2 Security with AES
wlan.WPA2_TKIP_PSK               --WPA2 Security with TKIP
wlan.WPA2_MIXED_PSK              --WPA2 Security with AES & TKIP
wlan.WPS_OPEN                    --WPS with open securit
wlan.WPS_SECURE                  --WPS with AES security

--注册串口事件的处理函数事件
wlan.EVT_READY                   --IP 地址
wlan.EVT_SCAN_DONE	 	         --扫描的结果
wlan.EVT_SCAN_REPORT             --扫描到的热点信息
wlan.EVT_STA_CONNECTED           --连接成功的 Station 信息
wlan.EVT_STA_CONNECTED_FAIL		 --连接失败的 Station 信息
wlan.EVT_STA_DISCONNECTED	     --断开连接的 Station 信息
wlan.EVT_AP_START		         --启动成功的 AP 信息
wlan.EVT_AP_STOP		         --启动失败的 AP 信息
wlan.EVT_AP_ASSOCIATED		     --连入的 Station 信息
wlan.EVT_AP_DISASSOCIATED        --断开的 Station 信息
```



## Lua API


```lua
--设置wifi Station 模式下的网络信息
wlan.setStaNet(ip,netmask,gateway)
--[[
用例:
    wlan.setStaNet()                    --启动DHCP，自动获取ip地址，子网掩码，网关等信息
    wlan.setStaNet(ip)                  --静态设置ip地址，ip：xxx.xxx.xxx.xxx，子网掩码：255.255.255.0,  网关：xxx.xxx.xxx.1
    wlan.setStaNet(ip,net)              --静态设置ip地址，ip：xxx.xxx.xxx.xxx，子网掩码：xxx.xxx.xxx.xxx,网关：xxx.xxx.xxx.1
    wlan.setStaNet(ip,netmask,gateway)  --静态设置ip地址，ip：xxx.xxx.xxx.xxx，子网掩码：xxx.xxx.xxx.xxx,网关：xxx.xxx.xxx.xxx
]]

--获取 wifi Station 模式下的网络信息
wlan.getStaNet()
--[[
用例:
    local ip,netmask,gateway = wlan.getStaNet()
]]


--设置wifi AP 模式下的网络信息
wlan.setApNet()
--[[
用例:
    wlan.setStaNet(ip)                  --静态设置ip地址，ip：xxx.xxx.xxx.xxx，子网掩码：255.255.255.0,  网关：xxx.xxx.xxx.1
    wlan.setStaNet(ip,net)              --静态设置ip地址，ip：xxx.xxx.xxx.xxx，子网掩码：xxx.xxx.xxx.xxx,网关：xxx.xxx.xxx.1
    wlan.setStaNet(ip,netmask,gateway)  --静态设置ip地址，ip：xxx.xxx.xxx.xxx，子网掩码：xxx.xxx.xxx.xxx,网关：xxx.xxx.xxx.xxx
]]

--获取 wifi AP 模式下的网络信息
wlan.getApNet()
--[[
用例:
    local ip,netmask,gateway = wlan.getApNet()
]]

--扫描热点
wlan.scan(ssid)
--[[
用例:
    local num,info = wlan.scan()      --扫描热点
    local num,info = wlan.scan(ssid)  --扫描指定的ssid热点
]]

--连接热点
wlan.connect(ssid,password,bssid)
--[[
用例:
    wlan.connect(ssid)                  --连接开放的热点
    wlan.connect(ssid,password)         --连接加密的热点
    wlan.connect(ssid,password,bssid)   --连接指定MAC地址的加密的热点
    wlan.connect(ssid,nil,bssid)        --连接指定MAC地址的开放热点
]]

--获取连接热点的信息
wlan.getinfo()
--[[
用例:
    local info = wlan.getinfo()
    info.ssid      --连接热点的信息ssid
    info.channel   --连接热点的信道
    info.rssi      --连接热点的信号强度
    info.bssid     --连接热点的MAC地址
    info.security  --连接热点的安全模式
]]

--断开热点
wlan.disconnect()

--连接状态
wlan.ready()

--获取信号强度
wlan.getrssi()

--创建热点
wlan.ap_start(ssid,password,security,channel,hidden)
--[[
用例:
    wlan.connect(ssid)                                        --创建开放的热点
    wlan.connect(ssid,password)                               --创建加密的热点
    wlan.connect(ssid,password,security)                      --创建指定安全级别加密的热点
    wlan.connect(ssid,password,security,channel)              --创建指定信道，指定安全级别加密的热点
    wlan.connect(ssid,password,nil,channel)                   --创建指定信道，加密的热点
    wlan.connect(ssid,nil,nil,channel)                        --创建指定信道，开发的热点
    wlan.connect(ssid,password,security,channel,hidden)       --创建指定安全级别，指定信道，是否广播ssid的加密热点
    wlan.connect(ssid,password,nil,channel,hidden)            --指定信道，是否广播ssid的加密热点
    wlan.connect(ssid,password,nil,nil,hidden)                --指定信道，是否广播ssid的加密热点
    wlan.connect(ssid,nil,nil,nil,hidden)                     --指定信道，是否广播ssid的开发热点
]]

--获取创建热点的信息
wlan.getapinfo()
--[[
用例:
    local info = wlan.getapinfo()
    info.ssid      --连接热点的信息ssid
    info.channel   --连接热点的信道
    info.rssi      --连接热点的信号强度
    info.bssid     --连接热点的MAC地址
    info.security  --连接热点的安全模式
    info.hidden    --是否广播ssid
]]

--获取加入热点的STA信息
wlan.getJionApInfo()
--[[
用例:
    local num,info = wlan.getJionApInfo()
    num             --已经连接的 station 数目
    info[num].ip    --station 的 ip 地址
    info[num].mac   --station 的 mac 地址
]]

--热点的状态
wlan.ap_ready()

--关闭热点
wlan.ap_stop()

--注册中断函数
wlan.on(EVT,fun)
--[[
用例:
    wlan.on(wlan.EVT_READY ,function() ... end)
    ...
]]

--设置功耗等级，用于station模式。
wlan.pw(level)

--获取功耗等级
wlan.getpw()

```
