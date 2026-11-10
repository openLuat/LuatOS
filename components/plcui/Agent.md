# plcui 使用指南

## 一、plcui介绍

plcui 是以 **image 图片为设计核心**的工控界面库：先设计界面并切图，或准备组态组件图片，再由 XML 组织布局，Lua 更新数据和处理业务。

支持七种组件：`image` 显示背景、设备和图片按钮；`label` 显示动态文字；`textarea` 输入参数；`keyboard` 提供数字或英文键盘；`container` 分组和嵌套布局；`table` 显示数据表格；`chart` 显示折线图或柱状图。

## 二、plcui使用举例

### 2.1 使用ai设计网页辅助完成界面设计

以 800×480 的泵站监控界面为例，向 AI 提供设计要求：

> 设计一个 800×480 固定画布的泵站监控网页，采用深色工控风格。包含水箱、管道、水泵、启动和停止按钮，显示液位、温度、流量，并提供目标液位输入框。按钮需有正常、按下、选中和禁用状态。将动态数据与背景分离，为需要切图的元素标注 ID、位置和尺寸。

完成网页预览并确认效果后，按以下步骤制作 plcui 界面：

1. **准备图片。** 隐藏动态数值和输入内容，将静态外观导出为背景图，再分别导出按钮及其状态图，记录各元素的坐标和尺寸。
2. **组织 XML。** 使用 `ui → resources + pages → page` 结构；resources 声明图片资源，page 中用 image 引用资源 ID。用 label 覆盖温度、液位等动态区域，用 textarea 和 keyboard 实现目标液位输入，相关节点可放入 container 分组。
3. **设置文字和交互。** 文字节点使用 `font="hzfont" font_size="24"`；输入框通过 `keyboard="键盘ID"` 关联键盘。启动按钮使用 `clickable="true" on-click="start_pump"`，通过状态图片表现按下和设备运行状态。
4. **连接 Lua 业务。** 初始化并加载 XML，在 handlers 中提供事件函数，通过组件 ID 更新界面：

```lua
-- 在 sys.taskInit 的任务中执行；真机先完成显示、触摸及存储初始化。
plcui.init({width = 800, height = 480})
local xml = plcui.load("/luadb/main.xml", {handlers = {
    start_pump = function() sys.publish("PUMP_START") end
}})
xml:find("main", "temperature"):set_text("24.6℃")
```

XML 中声明的所有事件都须在 handlers 中提供对应函数。将 XML 和图片部署到 luadb 或 SD 卡后，检查画面、按钮状态、数据更新与输入交互。

完整 XML 和 Lua 示例参考仓库中的 `bsp/pc/test/157.plcui/pump_station/main.xml` 与 `main.lua`。

## 三、plcui使用注意事项

- **image 推荐使用非渐进式 JPG（Baseline JPEG）**，以便使用目标平台支持的 JPEG 硬件解码。导出时关闭“渐进式 / Progressive”选项；需要透明背景的素材可使用 PNG。如果 JPG 显示效果与原设计差异较大，例如出现明显色差、渐变条带或边缘失真，也推荐改用 PNG。PNG 能保留原始像素和抗锯齿细节，但相较于目标平台的 JPEG 硬解，解码通常会慢一些，应结合实际画质与加载时间选择。
- 图片按目标显示尺寸导出；背景中不要保留需要实时变化的数值和输入内容。
- XML 与图片作为同一个资源包放入 luadb 或已挂载的 SD 卡；图片 src 使用相对于 XML 目录的路径，不使用绝对路径或 `..`。
- PC 命令行打包会平铺文件名；luadb 文件名不超过 31 字节。示例图片放在 assets 子目录，XML 引用打包后的文件名，通过 `/luadb/main.xml` 加载，不依赖启动目录。
- 组件填写 `id/x/y/w/h`，同一页面内 ID 唯一；container 子组件使用相对于容器内容区的坐标。
- HZFont 字号范围为 1～255，省略字号时默认 16；为文字预留足够的显示空间。
- table 在 XML 中指定 `rows/columns`，用 `<cell row="1" column="1" text="名称"/>` 初始化；Lua 使用 `set_cell/get_cell/set_column_width/set_font_size`，行列从 1 开始。最多 128 行、16 列，总计不超过 1024 格；`grid` 开启完整网格，`row-height` 设置最小行高，`col-aligns/header-align` 控制列与表头对齐。
- chart 指定 `type="line|bar"`、`point-count`、`y-min/y-max`，用 `<series id="supply" color="#44dcf6" values="..."/>` 初始化；Lua 使用 `set_values/get_values/add_point/set_range/set_series_hidden`。点数 2～1024，系列 1～8，数值范围 -1000～1000、精度两位小数，未填写 values 时初始化为下限；超轴值按边界绘制并保留原始数据，刻度和图例用外围文字或图片表达。
- `xml:find()` 获取组件，`set_text()` 更新文字，`set_src("资源ID")` 切换图片，`set_checked()` 切换选中状态；`xml:show()` 切页后重新查找组件。
- 按钮操作交给业务处理，界面状态按实际设备反馈更新；事件回调保持简短。
- 初始化后自动以 60Hz 为目标调度刷新，无需添加刷新定时器；退出时调用 `xml:close()`、`plcui.deinit()`。
