## Air8201H httpsrv demo 说明

> **Air8201H（基于 Air780EHM 模组）未引出 SPI 接口, 无法外挂 SPI 以太网卡。**
>
> 本 httpsrv demo 演示的是通过 SPI 以太网卡（AirETH_1000 配件板）创建 HTTP 服务器并提供 Web 控制界面的功能，该功能依赖 SPI 以太网硬件。由于 Air8201H 不支持 SPI 以太网，因此**无法运行本 demo**。
>
> 如需使用 HTTP 服务器功能，请使用 **Air8201G**（基于 Air780EGH 模组，已引出 SPI 接口，支持外挂 AirETH_1000 以太网配件板）。