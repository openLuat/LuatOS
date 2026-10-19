# Air780EHM 出厂固件已迁移

Air780EHM 不再单独维护出厂工程。其硬件配置（无 GNSS、LBS 定位、I2C 传感器接口、仅内核软狗）与 **Air780EPM** 出厂固件一致，统一使用 Air780EPM 工程：

➡️ **[e:\csdk\lua\LuatOS\module\Air780EPM\project\factory](file:///e:/csdk/lua/LuatOS/module/Air780EPM/project/factory)**

烧录时按 Air780EPM 工程说明操作（选择其 `user/` + `lib/`，并勾选「添加默认 lib」），硬件直接运行在 Air780EHM 上即可。

## 官方支持渠道

- https://docs.openluat.com/ 查找文档
- https://gitee.com/openLuat/LuatOS/tree/master/module 查找代码
- 合宙官方企业微信群（https://docs.openluat.com/ 网站底部二维码，扫码加入）
- https://luat.taobao.com/ 选购核心板和开发板产品，对比验证
