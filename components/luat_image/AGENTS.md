# luat_image 图片解码库

## 作用

`components/luat_image/` 是 LuatOS 的统一图片处理库，负责把不同来源、不同格式、不同解码模式的图片，统一成可供上层使用的像素缓冲。

它的核心职责不是“某一种图片格式的完整业务实现”，而是提供一层通用适配：

- 统一输入：支持内存缓冲区 `in_buf/in_len`，也支持文件路径 `source_path`
- 统一格式：通过 `luat_img_format_t` 区分 JPG / PNG / WebP
- 统一模式：通过 `luat_img_decode_mode_t` 区分软件解码和硬件解码
- 统一出口：把图片信息写入 `luat_img_info_t`

## 主要接口

- `luat_image_get_decoder_opts()`：根据格式和解码模式查找对应 decoder
- `luat_image_probe()`：只做探测，不输出像素数据
- `luat_image_decode()`：执行真正的解码，输出像素数据
- `luat_image_set_debug()` / `luat_image_get_debug()`：控制解码耗时日志

## 一般图片解码流程

1. 先填写 `luat_img_conf_t`
   - `format`：图片格式
   - `decode_mode`：软件或硬件解码
   - `source_path`：当没有直接传内存时，用文件路径作为输入来源

2. 决定输入方式
   - 如果上层已经有完整图片数据，就直接传 `in_buf/in_len`
   - 如果没有，就由 decoder 内部根据 `source_path` 读取文件

3. 先调用 `luat_image_probe()`
   - 检查当前格式/模式是否有可用 decoder
   - 解析图片头部信息
   - 填充 `luat_img_info_t` 中的宽高和预估尺寸
   - 这个阶段不申请最终像素缓冲，也不做完整解码

4. 再调用 `luat_image_decode()`
   - 查找对应 decoder 的 `decode` 函数
   - 完整解码图片数据
   - 把像素缓冲放到 `img_info->data`
   - 同时填充 `width`、`height`、`size`

5. 上层使用完后释放资源
   - 如果 decoder 分配了 `img_info->data`，通常由上层按对应内存管理方式释放
   - 如果 decoder 在内部申请了临时输入缓冲，也会在内部回收

## 解码器组织方式

`luat_image.c` 里维护了一张 decoder 表，把：

- 图片格式
- 解码模式

映射到具体实现的 `probe` / `decode` 函数。

这意味着新增或替换某种图片能力时，通常需要：

1. 实现对应的 `probe`
2. 实现对应的 `decode`
3. 把实现挂到 `decoder_opts_table` 中

## 常见行为约定

- `probe` 只负责“能不能解、图片多大”
- `decode` 负责“真正把图像像素解出来”
- 返回值统一使用 `LUAT_IMG_OK` / `LUAT_IMG_ERR`
- 图片输出一般会按 `luat_color_t` 对齐到目标色彩格式

## 调试提示

- 需要统计耗时或排查性能时，可以打开 `luat_image_set_debug(1)`
- 若某个格式或模式没有注册 decoder，`luat_image_probe()` / `luat_image_decode()` 会直接失败并给出告警

