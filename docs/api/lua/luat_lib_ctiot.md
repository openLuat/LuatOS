---
module: ctiot
summary: 中国电信CTIOT集成
version: 1.0
date: 2020.08.30
---

--------------------------------------------------
# ctiot.init

```lua
ctiot.init()
```

初始化ctiot，在复位开机后使用一次

## 参数表

> 无参数

## 返回值

> *无返回值*


--------------------------------------------------
# ctiot.param

```lua
ctiot.param(ip, port, lifetime)
```

设置和读取ctiot相关参数，有参数输入则设置，无论是否有参数输入，均输出当前参数

## 参数表

Name | Type | Description
-----|------|--------------
`ip`|`string`| 服务器ip
`port`|`int`| 服务器端口
`lifetime`|`int`| 生命周期,单位秒

## 返回值

No. | Type | Description
----|------|--------------
1 |`string`| 服务器ip
2 |`int`| 服务器端口
3 |`int`| 生命周期,单位秒


--------------------------------------------------
# ctiot.ep

```lua
ctiot.ep(val)
```

设置和读取自定义EP

## 参数表

Name | Type | Description
-----|------|--------------
`val`|`string`| 自定义EP的值,默认是imei,读取的话不要填这个参数

## 返回值

> `string`: 当前EP值


--------------------------------------------------
# ctiot.connect

```lua
ctiot.connect()
```

连接CTIOT，必须在设置完参数和模式后再使用

## 参数表

> 无参数

## 返回值

> `boolean`: 成功返回true,否则返回false


--------------------------------------------------
# ctiot.disconnect

```lua
ctiot.disconnect()
```

断开ctiot

## 参数表

> 无参数

## 返回值

> *无返回值*


--------------------------------------------------
# ctiot.write

```lua
ctiot.write(data, mode, seq)
```

发送数据给ctiot

## 参数表

Name | Type | Description
-----|------|--------------
`data`|`string`| 需要发送的数据
`mode`|`int`| 模式, ctiot.CON/NON/NON_REL/CON_REL
`seq`|`int`| 序号

## 返回值

No. | Type | Description
----|------|--------------
1 |`boolean`| 成功返回true,否则返回false
2 |`string`| 成功为nil,失败返回错误描述


--------------------------------------------------
# ctiot.isReady

```lua
ctiot.isReady()
```

是否已经就绪

## 参数表

> 无参数

## 返回值

> `int`: 已经就绪返回0,否则返回错误代码


--------------------------------------------------
# ctiot.update

```lua
ctiot.update()
```

发送更新注册信息给ctiot

## 参数表

> 无参数

## 返回值

> `boolean`: 发送成功等待结果返回true,否则返回false


