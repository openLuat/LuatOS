# 154.mp3_id3_detect

验证 mp3 ID3v2 跳过偏移修复（`luat_audio_codec_port_mp3.c` 的 `tag_size + 12` → `+10`）。

## 运行前准备

测试样本（9 个 mp3，约 1.4MB）不入库，请自行下载到本目录：

```
https://minio.asinfo.tech/hazy-iot-user-files/official-materials/709328036721332224.mp3  (正常样本)
https://minio.asinfo.tech/hazy-iot-user-files/official-materials/707422536488456192.mp3
https://minio.asinfo.tech/hazy-iot-user-files/official-materials/707422573452857344.mp3
https://minio.asinfo.tech/hazy-iot-user-files/official-materials/707422606994706432.mp3
https://minio.asinfo.tech/hazy-iot-user-files/official-materials/707422667254272000.mp3
https://minio.asinfo.tech/hazy-iot-user-files/official-materials/707422689563774976.mp3
https://minio.asinfo.tech/hazy-iot-user-files/official-materials/707422953351942144.mp3
https://minio.asinfo.tech/hazy-iot-user-files/official-materials/709301807028899840.mp3
https://minio.asinfo.tech/hazy-iot-user-files/official-materials/727439223266742272.mp3
```

文件命名：把 URL 中的 id 按 main.lua 里的 cases 表加 `ok_`/`bad_` 前缀即可。

## 运行

```powershell
cd bsp\pc\build\out
.\luatos-lua.exe ..\..\test\154.mp3_id3_detect\
```

预期输出 9 行 PASS 且 `RESULT pass=9 fail=0`。
