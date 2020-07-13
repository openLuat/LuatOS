---
module: luat_uart_rtt
---

--------------------------------------------------
# uart_input_cb

```c
static rt_err_t uart_input_cb(rt_device_t dev, rt_size_t size)
```

接收数据回调

## 参数表

Name | Type | Description
-----|------|--------------
`dev`|`rt_device_t`| *无*
`size`|`rt_size_t`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`rt_err_t`| *无*


--------------------------------------------------
# uart_sent_cb

```c
static rt_err_t uart_sent_cb(rt_device_t dev, void *buffer)
```

串口发送完成事件回调

## 参数表

Name | Type | Description
-----|------|--------------
`dev`|`rt_device_t`| *无*
`buffer`|`void*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`rt_err_t`| *无*


