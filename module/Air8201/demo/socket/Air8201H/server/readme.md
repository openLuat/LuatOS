## Air8201H socket server demo 说明

> **Air8201H（基于 Air780EHM 模组）未引出 SPI 接口, 无法外挂 SPI 以太网卡。**
>
> 本 socket server demo 演示的是通过 SPI 以太网卡创建 TCP/UDP 服务器端的功能，该功能依赖 SPI 以太网硬件。由于 Air8201H 不支持 SPI 以太网，因此**无法运行 socket server demo**。
>
> 如需使用 socket server 功能，请使用 **Air8201G**（基于 Air780EGH 模组，已引出 SPI 接口，支持外挂 AirETH_1000 以太网配件板）。
