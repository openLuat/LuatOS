# cc 模块 API 文档（VoLTE 通话功能）

> 模块名：`cc`
> 标签：`LUAT_USE_VOLTE`
> 适用：选型手册上支持 VoLTE 通话功能的模组
> 源文件：`components/cc/luat_lib_cc_v2.c`

`cc` 模块用于 VoLTE 通话控制，包含拨号、接听、挂断、通话录音、通话中播放第三方音频等功能。

---

## 目录

- [cc.init](#ccinit)
- [cc.dial](#ccdial)
- [cc.accept](#ccaccept)
- [cc.hangUp](#cchangup)
- [cc.lastNum](#cclastnum)
- [cc.quality](#ccquality)
- [cc.on](#ccon)
- [cc.record](#ccrecord)
- [cc.extern_source](#ccextern_source)
- [cc.input](#ccinput)

---

## cc.init

初始化电话功能（通话音频任务、录音/放音 FIFO 等）。**使用前必须先调用**。

```lua
cc.init(multimedia_id)
```

| 参数 | 类型 | 说明 |
|------|------|------|
| multimedia_id | number | 多媒体 id |

**返回值**

- `boolean`：初始化成功返回 `true`，失败返回 `false`。

---

## cc.dial

拨打电话。

```lua
cc.dial(sim_id, number)
```

| 参数 | 类型 | 说明 |
|------|------|------|
| sim_id | number | 卡槽 id，可选，默认 `0` |
| number | string | 电话号码 |

**返回值**

- `boolean`：拨打电话成功返回 `true`，失败返回 `false`。

**示例**

```lua
cc.dial(0, "10086")
```

---

## cc.accept

接听电话。

```lua
cc.accept(sim_id)
```

| 参数 | 类型 | 说明 |
|------|------|------|
| sim_id | number | 卡槽 id，可选，默认 `0` |

**返回值**

- `boolean`：接听成功返回 `true`，失败返回 `false`。

---

## cc.hangUp

挂断电话。

```lua
cc.hangUp(sim_id)
```

| 参数 | 类型 | 说明 |
|------|------|------|
| sim_id | number | 卡槽 id，可选，默认 `0` |

**返回值**：无。

---

## cc.lastNum

获取最后一次通话的号码。

```lua
cc.lastNum()
```

**返回值**

- `string`：最后一次通话的号码。

---

## cc.quality

获取当前通话质量（采样率信息）。

```lua
cc.quality()
```

**返回值**

- `int`：
  - `0`：没有在通话
  - `1`：低音质（8K）
  - `2`：高音质（16K）
  - 其他值：具体的音频采样率

---

## cc.on

注册通话回调事件。

```lua
cc.on(event, func)
```

| 参数 | 类型 | 说明 |
|------|------|------|
| event | string | 事件名称，音频录音数据为 `"record"` |
| func | function | 回调方法 |

**返回值**：无。

**说明**

当事件为 `"record"` 时，回调函数签名为：

```lua
function(type, buff_point)
    -- type == true 是下行数据，false 是上行数据
    -- buff_point 指示双缓存中返回了哪一个
end
```

**示例**

```lua
cc.on("record", function(type, buff_point)
    log.info(type, buff_point)
end)
```

---

## cc.record

开启/关闭通话录音功能（需配合 `cc.on("record", ...)` 回调使用）。

```lua
cc.record(on_off, upload_zbuff1, upload_zbuff2, download_zbuff1, download_zbuff2)
```

| 参数 | 类型 | 说明 |
|------|------|------|
| on_off | boolean | `true`/`nil` 以外的值开启，`false`/`nil` 关闭 |
| upload_zbuff1 | zbuff | 上行数据保存区 1（容量必须是 640 的倍数） |
| upload_zbuff2 | zbuff | 上行数据保存区 2（与 1 组成双缓冲） |
| download_zbuff1 | zbuff | 下行数据保存区 1（容量必须是 640 的倍数） |
| download_zbuff2 | zbuff | 下行数据保存区 2（与 1 组成双缓冲） |

**返回值**

- `boolean`：成功返回 `true`。若处于通话状态会失败。

**说明**

- 录音仅在通话状态下有效，开启后通过 `cc.on("record", callback)` 接收数据。
- zbuff 创建时的空间容量必须是 640 的倍数。

**示例**

```lua
buff1 = zbuff.create(6400, 0, zbuff.HEAP_AUTO)
buff2 = zbuff.create(6400, 0, zbuff.HEAP_AUTO)
buff3 = zbuff.create(6400, 0, zbuff.HEAP_AUTO)
buff4 = zbuff.create(6400, 0, zbuff.HEAP_AUTO)
cc.on("record", function(type, buff_point)
    log.info(type, buff_point) -- type==true 下行数据，false 上行数据
end)
cc.record(true, buff1, buff2, buff3, buff4)
```

---

## cc.extern_source

通话中附加额外的音频数据（向对端播放第三方音源）。额外音频的数据位数和通道数必须和通话参数一致，否则会失败。

```lua
cc.extern_source(source, is_add_record, codec_id, sample_rate, data_bits, channel_nums, is_signed)
```

| 参数 | 类型 | 说明 |
|------|------|------|
| source | table/string/zbuff/nil | 输入数据：`table` 表示播放文件列表；`string` 表示播放 TTS；`zbuff` 表示播放音频数据；只播放一个文件也要用 `table`；`nil` 表示停止当前第三方数据播放 |
| is_add_record | boolean | 是否添加到上行通道，`true` 添加到上行（往对端播放），`false` 添加到下行，默认 `true`。目前只支持上行通道 |
| codec_id | int | 解码器 id，见 `audio_v2.DATA_CODEC_TYPE_XXX`，留空则通过输入数据自行判断 |
| sample_rate | int | 采样率，若指定解码器为 RAW 不能留空 |
| data_bits | int | 数据位数（8/16/24/32），RAW 时不能留空，默认 `16` |
| channel_nums | int | 通道数（1/2），RAW 时不能留空，默认 `1` |
| is_signed | boolean | 是否有符号数据，默认 `true` |

**返回值**

- `boolean`：成功返回 `true`，否则返回 `false`。

**说明**

- 必须处于通话中（`is_true_start`）且当前没有正在播放的第三方音源时才能调用。
- 连续播放多个文件时，`is_error_stop`（旧名由 `codec_id` 之后参数顺序推断，实际传入位置见上表）控制遇到解码错误是否自动停止。

**示例**

```lua
cc.extern_source({"/test_16k.mp3"})
```

---

## cc.input

通话中以流模式输入未解码的音频数据（配合 `cc.extern_source` 使用）。

```lua
cc.input(is_record, data, is_end)
```

| 参数 | 类型 | 说明 |
|------|------|------|
| is_record | boolean | 是否是上行数据，`true` 上行，`false` 下行，默认 `true`。目前只支持上行通道，此参数实际无效 |
| data | string/zbuff | 输入数据，为空则不输入任何数据。若为 zbuff，写入成功后会自动删除其中数据 |
| is_end | boolean | 是否是最后一帧数据，默认 `false` |

**返回值**

- `boolean`：成功返回 `true`，否则返回 `false`。
- `int`：实际写入的长度（字节）。数据为空或写入失败时返回 `0`。
- `int`：输入缓冲的剩余空间（字节）。

**前提条件**：必须已调用 `cc.extern_source` 启动第三方音源，且处于通话中。

**示例**

```lua
local result, write_len, free_len = cc.input(true, data, is_end)
```

---

## 事件与消息

通话音频状态通过 `sys_pub("CC_IND", ...)` 系统消息广播，常见 `sub_type`：

- `"AUDIO_START"`：通话音频开始。
- `"EXT_SRC_DONE"`：第三方音源解码完成。

来电/拨号振铃由模组内部默认处理（`cc.play_tone`），无需用户干预；若自定义振铃路径，可通过内部字段设置（进阶用法，本文档不展开）。

---

## 典型使用流程

```lua
-- 1. 初始化
cc.init(0)

-- 2. 注册录音回调（可选）
buff1 = zbuff.create(6400, 0, zbuff.HEAP_AUTO)
buff2 = zbuff.create(6400, 0, zbuff.HEAP_AUTO)
buff3 = zbuff.create(6400, 0, zbuff.HEAP_AUTO)
buff4 = zbuff.create(6400, 0, zbuff.HEAP_AUTO)
cc.on("record", function(type, buff_point)
    log.info("record", type, buff_point)
end)

-- 3. 拨号 / 接听
cc.dial(0, "10086")   -- 或 cc.accept(0)

-- 4. 开启录音（通话中才生效）
cc.record(true, buff1, buff2, buff3, buff4)

-- 5. 通话中播放第三方音频
cc.extern_source({"/test_16k.mp3"})

-- 6. 挂断
cc.hangUp(0)
```
