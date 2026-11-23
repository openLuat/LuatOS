# plcui 泵站网页示例

这是一个固定 **800×480** 的泵站监控网页，用于预览工控界面、测试交互，并为 plcui 导出背景、按钮和状态图片。页面使用模拟数据，不连接真实 PLC。

## 文件说明

| 文件 | 作用 |
| --- | --- |
| `index.html` | 监控首页，包含水箱、水泵、实时数值和目标液位输入框。 |
| `details.html` | 设备详情与事件记录页面。 |
| `panel.css` | 两个页面共用的布局、颜色和按钮状态样式。 |
| `panel.js` | 启停演示、目标液位修改和页面跳转逻辑。 |
| `fonts/` | 网页使用的本地字体及许可证。 |

## 使用 Python 启动

安装 Python 3 后，在 PowerShell 中执行：

```powershell
cd C:\code\cursor\luatos-plcui\bsp\pc\test\157.plcui\web
python -m http.server 8000 --bind 127.0.0.1
```

如果系统使用 Python 启动器，也可以将第二行换成：

```powershell
py -3 -m http.server 8000 --bind 127.0.0.1
```

保持终端运行，在浏览器打开 [监控首页](http://127.0.0.1:8000/index.html)。服务只监听本机；在终端按 `Ctrl+C` 停止。

如果 8000 端口被占用，将命令中的端口改为 8001，并访问 `http://127.0.0.1:8001/index.html`。

## 测试方法

浏览器缩放设为 100%，窗口内容区至少为 800×480：

1. 点击 **STOP PUMP**，确认水泵显示 STOPPED，转速和流量归零。
2. 点击 **START PUMP**，确认恢复 RUNNING、1,450 rpm 和 12.4 m3/h。
3. 修改 **Target level**，再点击其他位置或按 Tab，确认底部出现目标值更新提示。
4. 点击 **STATION DETAILS** 进入详情页，再点击 **PROCESS OVERVIEW** 返回首页。

## 与 plcui 示例的关系

HTML 中的 `data-plcui` 标记用于描述组件、状态和事件，`data-font="hzfont"` 与 `data-font-size` 指定导出后的原生文字配置。网页本身使用浏览器字体渲染。

网页修改后需要重新导出 XML 和图片，再运行模拟器查看效果。相邻的 `pump_station/` 使用 JPG，`pump_station_png/` 使用 PNG，可用于比较两种图片格式的显示效果。
