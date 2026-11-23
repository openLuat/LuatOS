# 换热站参考界面 · 1024×600

按 reference 中的五张实屏照片重绘界面，恢复蓝色背景、顶部装饰标题、双换热器与多泵管路、密集表格及查询曲线布局。屏幕照片中的反光、划痕和外框不作为界面素材；布局适配为 1024×600。

| 网页 | 对应参考画面 |
| --- | --- |
| `web/index.html` | 监控页面：双换热器、分布泵/循环泵/补水泵、实时读数、底部补偿与能耗区。 |
| `web/parameters.html` | 参数设置：保护参数、上下限输入、红黄绿报警状态、三组 PID 参数。 |
| `web/records.html` | 能耗数据：日期查询、显示列选项、可滚动的密集表格。 |
| `web/trends.html` | 温度曲线：日期查询、曲线选择、温度突变和掉线走势。 |
| `web/pressure.html` | 压力曲线：压力查询、曲线选择与压差走势。 |

左上角 ☰ 打开页面菜单。所有数据均为模拟数据；曲线按参考照片走势重建，不代表原系统的逐点原始数据。“共267条”为参考演示标记，能耗表包含21条可滚动样本，保留4个可替换的数据列。

## 查看网页

```powershell
cd C:\code\cursor\luatos-plcui\bsp\pc\test\157.plcui\Heat_exchange_station\web
python -m http.server 8000 --bind 127.0.0.1
```

浏览器打开 http://127.0.0.1:8000/index.html，缩放设为100%，内容区至少1024×600。Ctrl+C 停止服务。

可测试菜单切页、循环泵状态、保护参数编辑与报警更新、能耗查询及显示列切换、曲线复选框和图例显隐。

## 运行 plcui

使用已有 GUI 编译脚本构建模拟器后，在 `bsp/pc/build/out` 执行：

```powershell
.\luatos-lua.exe .\plcui\Heat_exchange_station\app\
```

也可直接运行测试源码包：

```powershell
.\luatos-lua.exe ..\..\test\157.plcui\Heat_exchange_station\app\
```

`app/main.lua` 通过 `/luadb/main.xml` 加载 PNG 素材、HZFont 文字、原生 table/chart 组件。点击输入框弹出键盘，确认后保存；关闭或取消键盘恢复编辑前内容。监控读数每秒模拟更新，历史曲线保持参考走势。

只传入 app 目录；网页与原参考照片留在资源包之外，避免一同打包进 luadb。

## 重新导出

在任务目录的 `example/plcui-web-export` 执行：

```powershell
node export.mjs --input C:/code/cursor/luatos-plcui/bsp/pc/test/157.plcui/Heat_exchange_station/web/index.html --output C:/code/cursor/luatos-plcui/bsp/pc/test/157.plcui/Heat_exchange_station/app --format png --width 1024 --height 600
node verify-heat.mjs
```

导出保留 XML 中的 cell/series 数据与隐藏菜单，不覆盖 main.lua。表格使用原生网格、最小行高和对齐配置；参数输入框使用白色容器覆盖在表格上。
