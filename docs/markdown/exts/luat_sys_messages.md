# NBIOT

## SIM_IND

SIM卡状态

#### 返回值

RDY：SIM已插入

IMSI_READY: IMSI已获取

NIST: SIM卡已移走

#### 调用示例

```Lua
sys.subscribe("SIM_IND", function(msg)
	if msg == "RDY" then
    	log.info("RDY","已插入SIM卡")
    else if msg == "IMSI_READY" then
        log.info("IMSI_READY","已获取IMSI")
   	else if msg == "NIST" then
        log.info("NIST","SIM卡已移走")
    end
end)
```

## NET_STATUS

网络状态

#### 返回值

NRDY：网络准备好

调用示例

```lua
sys.subscribe("NET_STATUS", function(msg)
 	if msg == "NRDY" then
    	log.info("NRDY","网络已就绪")
    end
end)
```

## CELL_INFO_IND

网络信息

#### 调用示例

```lua
sys.subscribe("CELL_INFO_IND", function()
	log.info("CELL_INFO_IND")
end)
```

# WLAN

## WLAN_READY

网络就绪

#### 调用示例

```lua
sys.subscribe("WLAN_READY", function()
	log.info("网络就绪")
end)
```

## NET_READY

网络准备好（通用事件）

#### 调用示例

```lua
sys.subscribe("NET_READY", function()
	log.info("网络准备好")
end)
```

## WLAN_SCAN_DONE

wlan扫描完成

#### 调用示例

```lua
sys.subscribe("WLAN_SCAN_DONE", function()
	log.info("wlan扫描完成")
end)
```

## WLAN_STA_CONNECTED

#### 返回值

1：连上wifi路由器/热点,但还没拿到ip

0：没有连上wifi路由器/热点,通常是密码错误

#### 调用示例

```lua
sys.subscribe("WLAN_STA_CONNECTED", function(msg)
	if msg == 1 then
		log.info("连上wifi路由器/热点,但还没拿到ip")
	elseif msg == 0 then
		log.info("没有连上wifi路由器/热点,通常是密码错误")
	end
end)
```

## WLAN_STA_DISCONNECTED

从wifi路由器/热点断开了

#### 调用示例

```lua
sys.subscribe("WLAN_STA_DISCONNECTED", function()
	log.info("从wifi路由器/热点断开了")
end)
```

## WLAN_AP_START

wlan ap 开启

#### 调用示例

```lua
sys.subscribe("WLAN_AP_START", function()
	log.info("ap开启")
end)
```

## WLAN_AP_STOP

wlan ap 关闭

#### 调用示例

```lua
sys.subscribe("WLAN_AP_STOP", function()
	log.info("ap关闭")
end)
```

## WLAN_AP_ASSOCIATED

ap设备接入

#### 调用示例

```lua
sys.subscribe("WLAN_AP_ASSOCIATED", function()
	log.info("设备接入")
end)
```

## WLAN_AP_DISASSOCIATED

ap设备断开

#### 调用示例

```lua
sys.subscribe("WLAN_AP_DISASSOCIATED", function()
	log.info("设备断开")
end)
```

## WLAN_PW_RE

配网结果

#### 调用示例

```lua
sys.subscribe("WLAN_PW_RE", function(ssid,passwd)
	if (ssid == nil and passwd == nil) then
		log,info("配网失败")
	else
		log.info("ssid",ssid)
		log.info("passwd",passwd)
	end
end)
```

# NTP

## NTP_UPDATE

ntp更新

#### 调用示例

```lua
sys.subscribe("NTP_UPDATE", function()
	log.info("ntp更新")
end)
```

