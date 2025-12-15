#!/usr/bin/env python3
import asyncio
import struct
import time
from bleak import BleakScanner, BleakClient

# 完整UUID定义
FOTA_SERVICE_UUID = "0000f000-0000-1000-8000-00805f9b34fb"  # 完整服务UUID
FOTA_CMD_CHAR_UUID = "0000f001-0000-1000-8000-00805f9b34fb"  # 完整命令特征UUID
FOTA_DATA_CHAR_UUID = "0000f002-0000-1000-8000-00805f9b34fb"  # 完整数据特征UUID

# Command definitions
CMD_START_UPGRADE = 0x01
CMD_END_UPGRADE = 0x02

# 每包数据大小
MAX_PACKET_SIZE = 200

class SimpleFotaTool:
    def __init__(self, device_name, firmware_path):
        self.device_name = device_name
        self.firmware_path = firmware_path
        self.client = None
        self.firmware_data = None
        self.total_size = 0
        self.target_device = None

    async def load_firmware(self):
        """Load firmware file into memory"""
        try:
            with open(self.firmware_path, 'rb') as f:
                self.firmware_data = f.read()
            self.total_size = len(self.firmware_data)
            print(f"   固件加载完成，大小: {self.total_size} 字节")
            return True
        except Exception as e:
            print(f"   加载固件失败: {e}")
            return False

    async def scan_device(self):
        """Scan for the target device"""
        print("\n2. 扫描目标设备...")
        print("   正在扫描，请等待...")

        try:
            devices = await BleakScanner.discover(timeout=10.0)

            found_devices = []
            for device in devices:
                if device.name and self.device_name in device.name:
                    found_devices.append(device)
                    print(f"   找到匹配设备: {device.name} (地址: {device.address})")

            if not found_devices:
                print(f"   未找到设备: {self.device_name}")
                return None

            # 选择第一个匹配的设备
            self.target_device = found_devices[0]
            print(f"   选择设备: {self.target_device.name} (地址: {self.target_device.address})")
            return self.target_device

        except Exception as e:
            print(f"   扫描失败: {e}")
            return None

    async def connect_device(self, device):
        """Connect to the target device"""
        print("\n3. 建立BLE连接...")
        try:
            self.client = BleakClient(device.address)
            await self.client.connect(timeout=30.0)
            print(f"   连接成功，状态: {self.client.is_connected}")

            # 调试：打印所有服务和特征值
            print("\n4. 发现服务和特征值...")

            # 兼容不同版本的Bleak库
            try:
                # 新版本Bleak
                services = self.client.services
            except AttributeError:
                # 旧版本Bleak
                services = await self.client.get_services()

            fota_service_found = False
            for service in services:
                if service.uuid.lower() == FOTA_SERVICE_UUID.lower():
                    fota_service_found = True
                    print(f"   找到FOTA服务: {service.uuid}")
                    for char in service.characteristics:
                        print(f"     特征值: {char.uuid} - 属性: {char.properties}")
                        if char.uuid.lower() == FOTA_CMD_CHAR_UUID.lower():
                            print(f"       -> 命令特征值 (可写)")
                        elif char.uuid.lower() == FOTA_DATA_CHAR_UUID.lower():
                            print(f"       -> 数据特征值 (可写)")

            if not fota_service_found:
                print("   警告: 未找到FOTA服务，但继续尝试...")

            return True
        except Exception as e:
            print(f"   连接失败: {e}")
            return False

    async def write_characteristic(self, uuid, data):
        """写入特征值"""
        try:
            await self.client.write_gatt_char(uuid, data, response=True)

            # 正确提取短UUID（从完整UUID中提取f001/f002部分）
            # 完整UUID格式: "0000f001-0000-1000-8000-00805f9b34fb"
            # 我们想要提取 "f001" 部分
            short_uuid = uuid.split('-')[0][-4:]
            print(f"   写入特征值 {short_uuid}，数据长度: {len(data)} 字节")
            return True
        except Exception as e:
            print(f"   写入特征值失败: {e}")
            return False

    async def send_start_command(self):
        """发送开始升级命令"""
        print("\n5. 发送开始升级命令...")

        # 连接成功后短暂延时
        print("   连接成功，等待1秒...")
        await asyncio.sleep(1)

        # 发送开始升级命令
        start_cmd = struct.pack("<BI", CMD_START_UPGRADE, self.total_size)
        if not await self.write_characteristic(FOTA_CMD_CHAR_UUID, start_cmd):
            return False

        print("   开始命令发送完成")
        await asyncio.sleep(1)  # 等待设备准备
        return True

    async def send_firmware_data(self):
        """Send firmware data in chunks with optimized delay"""
        print("\n6. 分块传输固件数据...")
        sent_bytes = 0
        start_time = time.time()
        packet_count = 0

        # 优化延时：减少到100ms以提高速度
        PACKET_DELAY = 0.1

        while sent_bytes < self.total_size:
            chunk_size = min(MAX_PACKET_SIZE, self.total_size - sent_bytes)
            chunk = self.firmware_data[sent_bytes:sent_bytes + chunk_size]

            if not await self.write_characteristic(FOTA_DATA_CHAR_UUID, chunk):
                return False

            sent_bytes += chunk_size
            packet_count += 1

            # 短暂延时，避免数据丢失
            await asyncio.sleep(PACKET_DELAY)

            # 每20个数据包显示一次进度
            if packet_count % 20 == 0 or sent_bytes >= self.total_size:
                progress = (sent_bytes / self.total_size) * 100
                elapsed = time.time() - start_time
                speed = sent_bytes / elapsed / 1024 if elapsed > 0 else 0
                remaining_time = (self.total_size - sent_bytes) / (sent_bytes / elapsed) if sent_bytes > 0 else 0
                print(f"   进度: {progress:.1f}% - {speed:.1f} KB/s - 已发送 {packet_count} 包 - 预计剩余: {remaining_time:.1f}s")

        total_time = time.time() - start_time
        avg_speed = self.total_size / total_time / 1024
        print(f"   数据传输完成! 总时间: {total_time:.1f}s, 平均速度: {avg_speed:.1f} KB/s")
        return True

    async def end_upgrade(self):
        """Send end upgrade command"""
        print("\n7. 发送结束升级命令...")
        end_cmd = struct.pack("B", CMD_END_UPGRADE)
        if not await self.write_characteristic(FOTA_CMD_CHAR_UUID, end_cmd):
            return False

        print("   结束命令发送完成")

        # 等待设备处理
        print("\n8. 等待设备处理升级...")
        await asyncio.sleep(5)  # 给设备足够时间处理
        return True

    async def run(self):
        """Main execution flow"""

        # 1. 加载固件文件
        print("\n1. 加载固件文件...")
        if not await self.load_firmware():
            return False

        # 2. 扫描目标设备
        device = await self.scan_device()
        if not device:
            return False

        # 3. 连接设备
        if not await self.connect_device(device):
            return False

        try:
            # 4. 发送开始命令
            if not await self.send_start_command():
                return False

            # 5. 发送固件数据
            if not await self.send_firmware_data():
                return False

            # 6. 结束升级
            if not await self.end_upgrade():
                return False

            print("\n" + "="*50)
            print("升级流程完成! 设备应该正在重启...")
            print("="*50)
            return True

        except Exception as e:
            print(f"   升级过程中出现错误: {e}")
            return False
        finally:
            # 断开连接
            if self.client and self.client.is_connected:
                await self.client.disconnect()
                print("   已断开连接")

async def main():
    import argparse
    parser = argparse.ArgumentParser(description="蓝牙FOTA升级工具")
    parser.add_argument("-f", "--firmware", required=True, help="固件文件路径")
    parser.add_argument("-d", "--device", default="Air8000_FOTA", help="设备名称")

    args = parser.parse_args()

    tool = SimpleFotaTool(args.device, args.firmware)
    success = await tool.run()
    return success

if __name__ == "__main__":
    success = asyncio.run(main())
    exit(0 if success else 1)