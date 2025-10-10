# extp 版本管理

## 版本历史

### v1.0.0 - 初始版本
**发布日期**: 2025年9月17日

**新增功能**
1. 通过 extp.init(args)接口进行初始化触摸芯片
2. 触摸操作会自动转换为对应的手势，然后通过全局消息发布，并携带手势类型和坐标参数。

   1. 消息格式为：`sys.publish("baseTouchEvent", event_type, arg1, arg2)`
   2. `baseTouchEvent` 为：发布的消息标志
   3. `event_type` 为：事件类型
   4. `arg1, arg2` 为：事件类型携带的参数
   5. `event_type` 包含事件和参数 `arg1, arg2` 有：
      1. RAW_DATA：原始触摸数据，`arg1` 为 tp_device, `arg2` 为 tp_data；
      2. TOUCH_DOWN：按下瞬间事件，`arg1` 为按下 x 坐标, `arg2` 为按下 y 坐标；
      3. MOVE_X：水平移动，`arg1` 为为水平移动距离, `arg2` 为 0；
      4. MOVE_Y：垂直移动，`arg1` 为 0, `arg2` 为垂直移动距离；
      5. SWIPE_LEFT：向左滑动，`arg1` 为向左滑动距离, `arg2` 为 0；
      6. SWIPE_RIGHT：向右滑动，`arg1` 为向右滑动距离, `arg2` 为 0；
      7. SWIPE_UP：向上滑动，`arg1` 为 0, `arg2` 为向上滑动距离；
      8. SWIPE_DOWN：向下滑动，`arg1` 为 0, `arg2` 为向下滑动距离；
      9. SINGLE_TAP：单击，`arg1` 为点击 x 坐标, `arg2` 为点击 y 坐标；
      10. LONG_PRESS：长按，`arg1` 为点击 x 坐标, `arg2` 为点击 y 坐标；
3. 提供触摸后消息发布打开/关闭的接口：extp.setPublishEnabled(msg_type, enabled)，支持单个打开/关闭、全部打开/关闭。
4. 提供获取单个/全部消息当前是开启/关闭状态查询接口：extp.getPublishEnabled(msg_type)。
5. 提供滑动多少像素点后判定滑动方向阈值修改接口 extp.setSlideThreshold(threshold)，以适配不同尺寸的屏幕，默认为 45 像素。
6. 提供单击和长按判定阈值修改接口 extp.setSlideThreshold(threshold)，默认按下到抬手时间在 500ms 内为单击，大于等于 500ms 为长按。

**核心特性**
- TOUCH_DOWN、MOVE_X、MOVE_Y 是按下至抬手的中间状态
- 按下至抬手后只能触发事件 SWIPE_LEF、SWIPE_RIGHT、SWIPE_UP、SWIPE_DOWN、SINGLE_TAP、LONG_PRESS 中的一个事件
- 当按下并移动，移动像素超过滑动判定阈值，

  如果触发的是水平移动 MOVE_X，抬手只会返回 SWIPE_LEFT 和 SWIPE_RIGHT 事件，

  如果触发的是垂直移动 MOVE_Y，抬手只会返回 SWIPE_UP 和 SWIPE_DOWN 事件，
- 按下至抬手像素移动超过滑动判定阈值，

  如果按下至抬手时间小于 500ms 判定为单击，按下至抬手时间大于 500ms 判定为长按


### v1.0.1 - 初始版本

**发布日期**: 2025年9月23日

**新增功能**
新增对软件I2C触摸的支持


### v1.0.2 - 初始版本

**发布日期**: 2025年10月9日

**新增功能**
修改单击和长按时间判定依据，修改系统返回的32为时间为64位时间