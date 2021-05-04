---
module: nbiot
summary: NB-IOT操作库
version: V0001
date: 2020.04.30
---

--------------------------------------------------
# nbiot.isReady

```lua
nbiot.isReady()
```

网络是否就绪

## 参数表

> 无参数

## 返回值

> `boolean`: 已联网返回true,否则返回false

## 调用示例

```lua
-- 判断是否已经联网
if nbiot.isReady() then 
    log.info("nbiot", "net is ready")
end
```


--------------------------------------------------
# nbiot.imsi

```lua
nbiot.imsi()
```

读取IMSI

## 参数表

> 无参数

## 返回值

> `string`: 返回IMSI值，如果不存在就返回nil

## 调用示例

```lua
-- 读取imsi
log.info("nbiot", "imsi", nbiot.imsi())
```


--------------------------------------------------
# nbiot.iccid

```lua
nbiot.iccid()
```

读取ICCID

## 参数表

> 无参数

## 返回值

> `string`: 返回ICCID值，如果不存在就返回nil

## 调用示例

```lua
-- 读取iccid
log.info("nbiot", "iccid", nbiot.iccid())
```


--------------------------------------------------
# nbiot.imei

```lua
nbiot.imei(val)
```

读取或设置IMEI

## 参数表

Name | Type | Description
-----|------|--------------
`val`|`string`| 传入需要设置的imei值，不传就是读取

## 返回值

> `string`: 返回imei值，如果不存在就返回nil

## 调用示例

```lua
-- 读取imei
log.info("nbiot", "imei", nbiot.imei())
-------------------------
-- 设置imei
log.info("nbiot", "imei", nbiot.imei("898989898989899898"))
```


--------------------------------------------------
# nbiot.rssi

```lua
nbiot.rssi()
```

读取RSSI

## 参数表

> 无参数

## 返回值

> `int`: 返回rssi值

## 调用示例

```lua
-- 读取rssi
log.info("nbiot", "rssi", nbiot.rssi())
```


--------------------------------------------------
# nbiot.apn

```lua
nbiot.apn()
```

读取APN

## 参数表

> 无参数

## 返回值

> `string`: 返回apn值

## 调用示例

```lua
-- 读取APN
log.info("nbiot", "apn", nbiot.apn())
```


--------------------------------------------------
# nbiot.tac

```lua
nbiot.tac()
```

读取TAC

## 参数表

> 无参数

## 返回值

> `int`: 返回TAC值

## 调用示例

```lua
-- 读取TAC
log.info("nbiot", "tac", nbiot.tac())
```


--------------------------------------------------
# nbiot.tauTime

```lua
nbiot.tauTime()
```

读取Tau Time

## 参数表

> 无参数

## 返回值

> `int`: 返回Tau Time值

## 调用示例

```lua
-- 读取Tau Time
log.info("nbiot", "tau time", nbiot.tauTime())
```


--------------------------------------------------
# nbiot.activeTime

```lua
nbiot.activeTime()
```

读取Active Time

## 参数表

> 无参数

## 返回值

> `int`: 返回Active Time值

## 调用示例

```lua
-- 读取Active Time
log.info("nbiot", "Active Time", nbiot.activeTime())
```


--------------------------------------------------
# nbiot.cellID

```lua
nbiot.cellID()
```

读取CellID

## 参数表

> 无参数

## 返回值

> `int`: 返回CellID值

## 调用示例

```lua
-- 读取CellID
log.info("nbiot", "CellID", nbiot.cellID())
```


--------------------------------------------------
# nbiot.snr

```lua
nbiot.snr()
```

读取SNR

## 参数表

> 无参数

## 返回值

> `int`: 返回SNR值

## 调用示例

```lua
-- 读取SNR
log.info("nbiot", "SNR", nbiot.snr())
```


--------------------------------------------------
# nbiot.csq

```lua
nbiot.csq()
```

读取CSQ, 并不完全等价于GSM的CSQ

## 参数表

> 无参数

## 返回值

> `int`: 返回csq值

## 调用示例

```lua
-- 读取csq
log.info("nbiot", "csq", nbiot.csq())
```


--------------------------------------------------
# nbiot.ceLevel

```lua
nbiot.ceLevel()
```

读取CE Level

## 参数表

> 无参数

## 返回值

> `int`: 返回CE Level值

## 调用示例

```lua
-- 读取CE Level
log.info("nbiot", "CE Level", nbiot.ceLevel())
```


--------------------------------------------------
# nbiot.sn

```lua
nbiot.sn(val)
```

读取或设置SN,普通刷机(刷底层/刷脚本)不会清除

## 参数表

Name | Type | Description
-----|------|--------------
`val`|`string`| 需要设置的SN值(只能是可见字符),不传值则为读取

## 返回值

> `string`: 返回SN值

## 调用示例

```lua
-- 读取SN
log.info("nbiot", "SN", nbiot.sn())
-------------------------
-- 设置SN
log.info("nbiot", "SN", nbiot.sn("My Custom SN"))
```


--------------------------------------------------
# nbiot.updateCellInfo

```lua
nbiot.updateCellInfo()
```

刷新网络信息,可通过定时任务刷新,最小间隔5秒

## 参数表

> 无参数

## 返回值

> `boolean`: 成功启动刷新线程返回true，否则返回false.

## 调用示例

```lua
-- 刷新网络信息
nbiot.updateCellInfo()
sys.waitUntil("CELL_INFO_IND", 3000)
log.info("nbiot", "cell", json.encode(nbiot.getCellInfo()))
```


--------------------------------------------------
# nbiot.mcc

```lua
nbiot.mcc()
```

读取MCC值,注册网络后可用,通过nbiot.updateCellInfo()刷新

## 参数表

> 无参数

## 返回值

> `int`: 运营商MCC值

## 调用示例

```lua
-- 读取MCC
log.info("nbiot", "mcc", nbiot.mcc())
```


--------------------------------------------------
# nbiot.mnc

```lua
nbiot.mnc()
```

读取MNC值,注册网络后可用,通过nbiot.updateCellInfo()刷新

## 参数表

> 无参数

## 返回值

> `int`: 运营商MNC值

## 调用示例

```lua
-- 读取MNC
log.info("nbiot", "mnc", nbiot.mnc())
```


--------------------------------------------------
# nbiot.earfcn

```lua
nbiot.earfcn()
```

读取earfcn值,注册网络后可用,通过nbiot.updateCellInfo()刷新

## 参数表

> 无参数

## 返回值

> `int`: 运营商earfcn值

## 调用示例

```lua
-- 读取earfcn
log.info("nbiot", "earfcn", nbiot.earfcn())
```


--------------------------------------------------
# nbiot.phyCellId

```lua
nbiot.phyCellId()
```

读取phyCellId值,注册网络后可用,通过nbiot.updateCellInfo()刷新

## 参数表

> 无参数

## 返回值

> `int`: 运营商phyCellId值

## 调用示例

```lua
-- 读取phyCellId
log.info("nbiot", "phyCellId", nbiot.phyCellId())
```


--------------------------------------------------
# nbiot.rsrq

```lua
nbiot.rsrq()
```

读取rsrq值,注册网络后可用,通过nbiot.updateCellInfo()刷新

## 参数表

> 无参数

## 返回值

> `int`: 运营商ersrq值

## 调用示例

```lua
-- 读取rsrq
log.info("nbiot", "rsrq", nbiot.rsrq())
```


--------------------------------------------------
# nbiot.rsrp

```lua
nbiot.rsrp()
```

读取rsrp值,注册网络后可用,通过nbiot.updateCellInfo()刷新

## 参数表

> 无参数

## 返回值

> `int`: 运营商rsrp值

## 调用示例

```lua
-- 读取rsrp
log.info("nbiot", "rsrp", nbiot.rsrp())
```


--------------------------------------------------
# nbiot.powerLevel

```lua
nbiot.powerLevel()
```

读取PowerLevel值,注册网络后可用,通过nbiot.updateCellInfo()刷新

## 参数表

> 无参数

## 返回值

> `int`: 运营商PowerLevel值

## 调用示例

```lua
-- 读取PowerLevel
log.info("nbiot", "PowerLevel", nbiot.powerLevel())
```


--------------------------------------------------
# nbiot.getCellInfo

```lua
nbiot.getCellInfo()
```

获取网络基站详情,注册网络后可用,通过nbiot.updateCellInfo()刷新

## 参数表

> 无参数

## 返回值

> `table`: 网络基站详情

## 调用示例

```lua
-- 读取基站信息
log.info("nbiot", "cell info", json.encode(nbiot.getCellInfo()))
```


--------------------------------------------------
# nbiot.setCFUN

```lua
nbiot.setCFUN(val)
```

进入或退出飞行模式

## 参数表

Name | Type | Description
-----|------|--------------
`val`|`int`| 0飞行模式,1普通联网模式

## 返回值

> `boolean`: 设置成功返回true,否则返回false

## 调用示例

```lua
-- 进入飞行模式
nbiot.setCFUN(0)
```


--------------------------------------------------
# nbiot.setBootCFUN

```lua
nbiot.setBootCFUN(val)
```

设置设备上电启动时，是否进入飞行模式

## 参数表

Name | Type | Description
-----|------|--------------
`val`|`int`| 0飞行模式,1普通联网模式

## 返回值

> `boolean`: 设置成功返回true,否则返回false

## 调用示例

```lua
-- 设置为上电进入飞行模式
nbiot.setBootCFUN(0)
```


--------------------------------------------------
# nbiot.getBootCFUN

```lua
nbiot.getBootCFUN(val)
```

获取设备上电启动时，是否进入飞行模式

## 参数表

Name | Type | Description
-----|------|--------------
`val`|`null`| *无*

## 返回值

> `int`: 开机就进入飞行模式返回0,进入普通模式返回1

## 调用示例

```lua
-- 获取上电模式
nbiot.getBootCFUN()
```


--------------------------------------------------
# nbiot.setPSM

```lua
nbiot.setPSM(psmMode, tauTimeS, activeTimeS)
```

设置PSM参数

## 参数表

Name | Type | Description
-----|------|--------------
`psmMode`|`int`| psm模式, CMI_MM_DISABLE_PSM(0)/CMI_MM_ENABLE_PSM(1)/CMI_MM_DISCARD_PSM(2)
`tauTimeS`|`int`| TAU time(unit: S)---related to T3412
`activeTimeS`|`int`| active time(unit: S)---related to T3324

## 返回值

> `boolean`: 设置成功返回true,否则返回false

## 调用示例

```lua
-- 设置PSM
nbiot.setPSM(1, 60, 120)
```


--------------------------------------------------
# nbiot.setEDRX

```lua
nbiot.setEDRX(modeVal, actType, reqEdrxValueMs)
```

设置EDRX参数

## 参数表

Name | Type | Description
-----|------|--------------
`modeVal`|`int`| 模式,CMI_MM_DISABLE_EDRX = 0/CMI_MM_ENABLE_EDRX_AND_DISABLE_IND = 1/CMI_MM_ENABLE_EDRX_AND_ENABLE_IND = 2/CMI_MM_DISCARD_EDRX = 3
`actType`|`int`| 可选值, 0或者5. CMI_MM_EDRX_NO_ACT_OR_NOT_USE_EDRX = 0/CMI_MM_EDRX_NB_IOT = 5
`reqEdrxValueMs`|`int`| edrx值,4个字节长度二进制字符串

## 返回值

> `boolean`: 设置成功返回true,否则返回false

## 调用示例

```lua
-- 设置EDRX
nbiot.setPSM(1, 5, "0101")
```


--------------------------------------------------
# nbiot.getPSM

```lua
nbiot.getPSM()
```

获取PSM参数

## 参数表

> 无参数

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| psm模式, CMI_MM_DISABLE_PSM(0)/CMI_MM_ENABLE_PSM(1)/CMI_MM_DISCARD_PSM(2)
2 |`int`| TAU time(unit: S)---related to T3412
3 |`int`| active time(unit: S)---related to T3324

## 调用示例

```lua
-- 获取PSM
log.info("psm", nbiot.getPSM())
```


--------------------------------------------------
# nbiot.getEDRX

```lua
nbiot.getEDRX()
```

获取EDRX参数

## 参数表

> 无参数

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| 模式,CMI_MM_DISABLE_EDRX = 0/CMI_MM_ENABLE_EDRX_AND_DISABLE_IND = 1/CMI_MM_ENABLE_EDRX_AND_ENABLE_IND = 2/CMI_MM_DISCARD_EDRX = 3
2 |`int`| 可选值, 0或者5. CMI_MM_EDRX_NO_ACT_OR_NOT_USE_EDRX = 0/CMI_MM_EDRX_NB_IOT = 5
3 |`int`| edrx值,单位毫秒

## 调用示例

```lua
-- 获取EDRX
log.info("edrx", nbiot.getEDRX())
```


--------------------------------------------------
# nbiot.setTZ

```lua
nbiot.setTZ(tz, auto)
```

设置时区参数

## 参数表

Name | Type | Description
-----|------|--------------
`tz`|`int`| 时区参数,可选, 单位是1/4时区, 默认为 东8区, 对应的值为32
`auto`|`boolean`| 是否自动设置时区,可选, 默认为true

## 返回值

> *无返回值*

## 调用示例

```lua
-- 设置为东8区,禁用自动更新时区功能
nbiot.setTZ(32, false)
-------------------------
-- 启用自动更新时区功能
nbiot.setTZ(nil, true)
```


--------------------------------------------------
# nbiot.getTZ

```lua
nbiot.getTZ()
```

获取时区参数

## 参数表

> 无参数

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| 时区参数,单位1/4时区, 默认东8区, 值为32
2 |`boolean`| 自动设置时区,默认为true

## 调用示例

```lua
-- 获取时区参数
log.info("timezone", nbiot.getTZ())
```


--------------------------------------------------
# nbiot.setBands

```lua
nbiot.setBands(modes)
```

设置Band模式(暂不可用)

## 参数表

Name | Type | Description
-----|------|--------------
`modes`|`any`| 模式,需要是一个table形式的数组,必须传入

## 返回值

> `boolean`: 设置结果

## 调用示例

```lua
-- 仅搜索band 8
log.info("band", nbiot.setBands({8}))
```


--------------------------------------------------
# nbiot.getBands

```lua
nbiot.getBands()
```

获取当前使用的Band模式(暂不可用)

## 参数表

> 无参数

## 返回值

> `table`: 所设置的band的数组

## 调用示例

```lua
-- 仅搜索band 8
log.info("band", json.encode(nbiot.getBands()))
```


--------------------------------------------------
# nbiot.setEDRXPtw

```lua
nbiot.setEDRXPtw(val)
```

设置EDRX PTW参数

## 参数表

Name | Type | Description
-----|------|--------------
`val`|`int`| 需要设置的值

## 返回值

> `boolean`: 成功返回true,否则返回false

## 调用示例

```lua
-- 设置PTW值为X
-- 可选值
nbiot.setEDRXPtw(val)
reqPtwValue:
NB-S1 mode
The field contains the PTW value in seconds for NB-S1 mode.The PTW value is used
as specified in 3GPP TS 23.682 [133a].The PTW value is derived as follows:
bit
         Paging Time Window length
0 0 0 0  2,56 seconds
0 0 0 1  5,12 seconds
0 0 1 0  7,68 seconds
0 0 1 1  10,24 seconds
0 1 0 0  12,8 seconds
0 1 0 1  15,36 seconds
0 1 1 0  17,92 seconds
0 1 1 1  20,48 seconds
1 0 0 0  23,04 seconds
1 0 0 1  25,6 seconds
1 0 1 0  28,16 seconds
1 0 1 1  30,72 seconds
1 1 0 0  33,28 seconds
1 1 0 1  35,84 seconds
1 1 1 0  38,4 seconds
1 1 1 1  40,96 seconds
 
-------------------------
-- 设置PTW值为X
-- 可选值
nbiot.setEDRXPtw(val)
reqPtwValue:
NB-S1 mode
The field contains the PTW value in seconds for NB-S1 mode.The PTW value is used
as specified in 3GPP TS 23.682 [133a].The PTW value is derived as follows:
bit
         Paging Time Window length
0 0 0 0  2,56 seconds
0 0 0 1  5,12 seconds
0 0 1 0  7,68 seconds
0 0 1 1  10,24 seconds
0 1 0 0  12,8 seconds
0 1 0 1  15,36 seconds
0 1 1 0  17,92 seconds
0 1 1 1  20,48 seconds
1 0 0 0  23,04 seconds
1 0 0 1  25,6 seconds
1 0 1 0  28,16 seconds
1 0 1 1  30,72 seconds
1 1 0 0  33,28 seconds
1 1 0 1  35,84 seconds
1 1 1 0  38,4 seconds
1 1 1 1  40,96 seconds
 
```


--------------------------------------------------
# nbiot.getEDRXPtw

```lua
nbiot.getEDRXPtw()
```

获取EDRX PTW参数

## 参数表

> 无参数

## 返回值

> `int`: ptw值

## 调用示例

```lua
-- 打印PTW值
log.info("ptw", nbiot.getEDRXPtw())
```


