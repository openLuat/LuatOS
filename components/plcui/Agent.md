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
- 切页先离屏创建并初始化目标页，只准备首帧可见图片的当前状态；检查与解码结果留在缓存，页面持有像素引用，绘制时直接复用。隐藏/备用状态在显示时准备，失败返回资源错误，首帧准备失败保留旧页。
- 需要业务初始状态时使用 `plcui.load(path, {handlers=..., prepare=function(xml, page_id) ... end})`。回调同步设置目标页的显隐、选中态、文本和图表，不依赖尚未切换的 `plcui.status().page`；失败使用 `error/assert` 中止。准备期间禁止yield、load/show/close/deinit和启动输入会话，只访问传入的目标XML/页面；临时组件句柄在提交后失效，后续重新find。
- 图片运行中视为固定，替换文件后重新 `plcui.load()`。缓存按XML实例隔离，重新加载不会复用旧版本像素；资源仍按原LuatOS VFS路径读取，内部缓存键不对应磁盘目录。
- 文件读取遵循 LuatOS VFS：脚本区用 `/luadb/main.xml`，SD 卡使用实际挂载路径（如 `/sd/ui/main.xml`）。资源相对于 XML 所在目录解析；文件名长度和目录结构遵循所用文件系统及烧录工具。PLCUI 不自动改名或改写 XML。
- 组件填写 `id/x/y/w/h`，同一页面内 ID 唯一；container 子组件使用相对于容器内容区的坐标。
- HZFont 字号范围为 1～255，省略字号时默认 16；为文字预留足够的显示空间。
- table 在 XML 中指定 `rows/columns`，用 `<cell row="1" column="1" text="名称"/>` 初始化；Lua 使用 `set_cell/get_cell/set_column_width/set_font_size`，行列从 1 开始。最多 128 行、16 列，总计不超过 1024 格；`grid` 开启完整网格，`row-height` 设置最小行高，`col-aligns/header-align` 控制列与表头对齐。
- chart 指定 `type="line|bar"`、`point-count`、`y-min/y-max`，用 `<series id="supply" color="#44dcf6" values="..."/>` 初始化；Lua 使用 `set_values/get_values/add_point/set_range/set_series_hidden`。点数 2～1024，系列 1～8，数值范围 -1000～1000、精度两位小数，未填写 values 时初始化为下限；超轴值按边界绘制并保留原始数据，刻度和图例用外围文字或图片表达。
- `xml:find()` 获取组件，`set_text()` 更新文字，`set_src("资源ID")` 切换图片，`set_checked()` 切换选中状态；`xml:show()` 切页后重新查找组件。
- 按钮操作交给业务处理，界面状态按实际设备反馈更新；事件回调保持简短。
- 初始化后自动以 60Hz 为目标调度刷新，无需添加刷新定时器；退出时调用 `xml:close()`、`plcui.deinit()`。
- PC 与真机使用同一套 PLCUI Lua 接口：`plcui.device_bind_touch(tp_cfg)` 在 PC 兼容成功，输入由 SDL 鼠标提供；板级上电、屏幕与 TP 初始化封装在各自驱动中，参考 AIRUI 示例的 PC 处理方式。


### 3.1 使用耗时调试优化界面响应

1. **固定操作，再开启采样。** 在已有初始化/加载逻辑前调用 `plcui.debug(true)`，执行固定次数的切页、输入或数据更新，最后调用 `plcui.debug(false)` 输出剩余统计。默认关闭；完整接口说明见第五章。

   ```lua
   plcui.debug(true)
   -- 执行原有的初始化、XML加载及业务操作
   -- 按相同顺序切换两轮页面，再更新相同次数的数据
   plcui.debug(false)
   ```

2. **区分创建、初始化与日常更新。** `phase=create` 看组件构造，`phase=prepare` 看显示前的业务初始化，`phase=update` 看已有对象的更新。重新切页创建的对象仍属于 create，不表示组件被缓存复用。
3. **先看总量，再定位最大单次。** 用 `type/op/count/total_us/avg_us/max_us` 判断是调用次数多还是单次慢，通过 `slow_page/slow_id` 定位最慢的一次。日志按类型、阶段和方法汇总；跨页面操作可能合并，分析单个页面时可单独开启/关闭一轮采样。先排查 `failed` 或 `dropped`，避免根据失败调用或不完整数据做判断。
4. **根据结果选择优化点。** create 占用高时检查组件数量、反复重建及静态内容能否合并到背景图片；prepare/update 中 `set_text`、`set_cell` 等总量高时检查重复赋值和更新频率，集中更新有变化的数据。同值调用也计数，低耗时可能来自已有跳过路径；textarea 的同值更新仍可能承担取消编辑语义，不能只为减少次数随意跳过。图片状态更新慢时检查资源尺寸、编码、缓存和资源所在存储，但简版不会进一步拆出读取/解码耗时。
5. **每次只改一个因素，做同条件对照。** 保持设备、分辨率、资源位置、缓存配置、操作顺序和调用次数一致，首次访问与复访分开记录；比较相同操作的总/平均/最大耗时，再验证实际切页、输入和动态刷新体验。PC 与真机的绝对时间不能直接比较。

注意：这些统计是同步调用的经过时间，包含调用触发的布局或图片准备，不是 CPU 占用，也不包含后续异步绘制、flush 或实际显示延迟。组件局部指标下降，不代表整页响应一定同步改善。日志本身也会影响运行，完成对比后关闭调试，再检查正常使用体验。

## 四、模组 PLCUI 配置

当前真机适配范围为 Air1603。102、103 号固件同时包含 AIRUI 和 PLCUI，每次运行只能选择其中一个库，不支持在同一运行过程中切换。104 号固件已移除。其他模组待适配后补充。

| 配置项 | Air1603（102 / 103 号固件） | 说明 |
|---|---|---|
| PLCUI 开关 | `LUAT_USE_PLCUI=1` | 102 / 103 同时启用 `LUAT_USE_AIRUI` 和 `LUAT_USE_PLCUI`。 |
| 显示接口 | `display` / RGB | 业务先初始化显示设备；PLCUI 适配使用 display 库。 |
| 屏幕分辨率上限 | 1024×600 | `plcui.init()` 的宽高须与已初始化的显示设备一致。 |
| 像素格式与方向 | RGB565，16 位；固定方向 0 | 当前适配不支持运行时旋转。 |
| 触摸 | 单触点 | 业务初始化 TP 后调用 `plcui.device_bind_touch(tp_cfg)`。 |
| 刷新目标 | 60Hz | 自动调度的目标频率，实际帧率取决于界面、资源读取和绘制耗时。 |
| 图片像素缓存 | 6MiB（6,291,456 字节） | `LUAT_USE_PLCUI_IMAGE_CACHE_SIZE`；JPG/PNG 共用解码像素缓存，属于运行时内存，不是压缩图片文件大小或 Flash 空间；实际占用随缓存回收变化。 |
| 图片头缓存 | 256 条 | `LUAT_USE_PLCUI_IMAGE_HEADER_CACHE_COUNT`；PLCUI 初始化时应用，缓存尺寸、格式等头信息，与像素缓存分开。 |
| AIRUI 独立缓存配置 | 像素缓存 4MiB，图片头 64 条 | 共用一份 LVGL 引擎，启动时选择哪一库就应用哪套缓存上限，不同时占用两套缓存；`plcui.status()` 的缓存字段反映当前 LVGL 实际容量。 |
| 显示缓冲 | 1 块绘制缓冲 + 2 块扫描缓冲 | 按实际分辨率分配；1024×600 RGB565 合计约 3.52MiB，另计图片像素缓存。 |
| 图片硬解 | JPG、PNG 硬解启用 | JPG 允许非 16 像素对齐尺寸；具体能否硬解仍取决于图片编码格式。 |
| 中文字体 | HZFont，启用内置 TTF | 默认字号 16，XML 可设置 1～255；布局需预留相应文字空间。 |
| 执行方式 | 102：XIP/PSRAM 混合；103：全量 PSRAM | 103 将更多代码放入 PSRAM，运行时可用内存需结合资源规模验证。 |
| Lua 脚本区 | 102：4MiB；103：4.5MiB | `LUAT_SCRIPT_SIZE`；脚本区 XML/资源按 `/luadb/` 路径访问。 |
| 内部文件系统区 | 1.5MiB（1536KiB） | `__FS_TOTAL_LEN__`；SD 卡为独立挂载存储，不计入该分区容量。 |
| 组件耗时调试 | 默认关闭 | `plcui.debug(true)` 开启，使用方式见第五章。 |
| 配置来源 | SDK 配置 + PLCUI 配置 | 模组开关、像素缓存见 SDK `csdk/project/luatos/include/luat_conf_bsp.h`；分区见同目录 `flash_map.h`；图片头缓存和刷新目标见 `components/plcui/inc/luat_plcui_conf.h`。 |

## 五、简版组件耗时调试

默认关闭；PC 和真机使用同一个接口，可在 `plcui.init()` 前开启：

```lua
plcui.debug(true)
-- 初始化、加载 XML、切页、操作控件
-- ...
plcui.debug(false) -- 输出尚未汇总的数据并关闭
```

`plcui.debug()` 不传参数返回当前开关状态；`plcui.deinit()` 自动汇总并关闭。

开启后，`plcui.debug` 日志每秒最多汇总一次，按组件类型、阶段和方法输出 `count`、`failed`、`total_us`、`avg_us`、`max_us`，以及本批最慢调用的 `slow_page`、`slow_id`。阶段为 `create`（原生组件创建）、`prepare`（XML prepare 回调中的设置）、`update`（已有对象的更新方法）。统计涵盖七种组件，更新方法包括 `set_*`、`add_point` 和 `focus`；getter 不计入。

这些数字是同步调用经过时间，包含同值调用、校验及同步触发的布局/图片准备，不能当作 CPU 占用或后续绘制时间。`xml:show()` 重建的组件仍记为 create，不表示页面缓存复用。失败候选页已完成的创建也会计入。普通 `nil,error` 计入 failed；参数错误抛出的 Lua 异常和失效句柄调用不计入。相同类型/方法跨页面合并，slow_page/id 仅代表其中最大单次调用。

汇总最多保留64种类型/阶段/方法组合，满时输出 dropped 数；关闭开关也会输出不足一秒的剩余数据。日志输出发生在计时之外，但调试本身仍会影响运行；PC 数据只适合 PC 内的改前改后比较，真机性能需在真机测量。

编译宏 `PLCUI_PERF_ENABLE=0` 可裁掉统计支持，此时开启返回 E_NOT_SUPPORTED。旧的文件/字体/逐帧详细 profiler 默认由 `PLCUI_PERF_VERBOSE=0` 关闭；本简版不提供详细报告接口。
