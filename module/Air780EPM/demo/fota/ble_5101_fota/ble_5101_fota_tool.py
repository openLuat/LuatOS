#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Air5101 BLE FOTA 升级工具

用于通过 Air5101 蓝牙模块向设备发送固件升级包
"""

import asyncio
import argparse
import os
import struct
import time

from bleak import BleakScanner, BleakClient

# Air5101 服务和特征值 UUID
SERVICE_UUID = "0000ff00-f7e3-55b4-6c4c-9fd140100a16"
CHARACTERISTIC_UUID = "0000ff02-f7e3-55b4-6c4c-9fd140100a16"  # write 和 write no response

# 命令定义
CMD_START = 0x01
CMD_END = 0x02

# 数据包大小（字节）
MAX_PACKET_SIZE = 500

# 数据包延迟（秒）
PACKET_DELAY = 0.05

class Air5101FotaTool:
    def __init__(self, device_name, firmware_path):
        """初始化 FOTA 工具"""
        self.device_name = device_name
        self.firmware_path = firmware_path
        self.client = None
        self.firmware_data = None
        self.firmware_size = 0
        self.target_device = None
    
    async def load_firmware(self):
        """加载固件文件到内存"""
        print("\n1. 加载固件文件...")
        try:
            if not os.path.exists(self.firmware_path):
                print(f"   错误: 固件文件不存在: {self.firmware_path}")
                return False
            
            with open(self.firmware_path, 'rb') as f:
                self.firmware_data = f.read()
            
            self.firmware_size = len(self.firmware_data)
            print(f"   固件加载完成，大小: {self.firmware_size} 字节")
            return True
        except Exception as e:
            print(f"   加载固件失败: {e}")
            return False
    
    async def scan_device(self):
        """扫描并返回指定名称的蓝牙设备"""
        print("\n2. 扫描目标设备...")
        print(f"   正在扫描设备: {self.device_name}...")
        
        try:
            devices = await BleakScanner.discover(timeout=10.0)
            
            found_devices = []
            for device in devices:
                if device.name == self.device_name:
                    found_devices.append(device)
                    print(f"   找到设备: {device.name} ({device.address})")
            
            if not found_devices:
                print(f"   未找到设备: {self.device_name}")
                return None
            
            # 选择第一个匹配的设备
            self.target_device = found_devices[0]
            print(f"   选择设备: {self.target_device.name} ({self.target_device.address})")
            return self.target_device
        except Exception as e:
            print(f"   扫描失败: {e}")
            return None
    
    async def connect_device(self, device):
        """连接到目标设备"""
        print("\n3. 建立BLE连接...")
        try:
            self.client = BleakClient(device)
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
                if service.uuid.lower() == SERVICE_UUID.lower():
                    fota_service_found = True
                    print(f"   找到FOTA服务: {service.uuid}")
                    for char in service.characteristics:
                        print(f"     特征值: {char.uuid} - 属性: {char.properties}")
                        if char.uuid.lower() == CHARACTERISTIC_UUID.lower():
                            print(f"       -> 写入特征值 (可写)")
            
            if not fota_service_found:
                print("   警告: 未找到FOTA服务，但继续尝试...")
            
            return True
        except Exception as e:
            print(f"   连接失败: {e}")
            return False
    
    async def write_characteristic(self, data):
        """写入特征值"""
        try:
            # 发送数据
            await self.client.write_gatt_char(CHARACTERISTIC_UUID, data, response=True)
            return True
        except Exception as e:
            print(f"   写入特征值失败: {e}")
            return False
    
    async def send_start_command(self):
        """发送开始升级命令"""
        print("\n5. 发送开始升级命令...")
        
        # 等待连接稳定
        print("   连接成功，等待1秒...")
        await asyncio.sleep(1)
        
        # 发送开始命令
        start_cmd = struct.pack('B', CMD_START) + struct.pack('<I', self.firmware_size)
        
        # 包装命令数据（添加数据类型前缀）
        wrapped_start_cmd = struct.pack('B', 0x01) + start_cmd
        print(f"   发送开始命令: {wrapped_start_cmd.hex()}")
        
        if not await self.write_characteristic(wrapped_start_cmd):
            return False
        
        print("   开始命令发送完成")
        await asyncio.sleep(2)  # 等待设备准备
        return True
    
    async def send_firmware_data(self):
        """分块发送固件数据"""
        print("\n6. 分块传输固件数据...")
        sent_size = 0
        packet_count = 0
        start_time = time.time()

        while sent_size < self.firmware_size:
            # 计算当前包大小
            chunk_size = min(MAX_PACKET_SIZE, self.firmware_size - sent_size)
            chunk = self.firmware_data[sent_size:sent_size + chunk_size]
            
            # 包装数据（添加数据类型前缀）
            wrapped_chunk = struct.pack('B', 0x02) + chunk
            
            # 发送数据
            if not await self.write_characteristic(wrapped_chunk):
                return False
            
            # 更新进度
            sent_size += chunk_size
            packet_count += 1
            
            # 短暂延迟，避免数据包堆积
            await asyncio.sleep(PACKET_DELAY)
            
            # 每20个数据包显示一次进度
            if packet_count % 20 == 0 or sent_size >= self.firmware_size:
                progress = (sent_size / self.firmware_size) * 100
                elapsed = time.time() - start_time
                speed = sent_size / elapsed / 1024 if elapsed > 0 else 0
                remaining_time = (self.firmware_size - sent_size) / (sent_size / elapsed) if sent_size > 0 else 0
                print(f"   进度: {progress:.1f}% - {speed:.1f} KB/s - 已发送 {packet_count} 包 - 预计剩余: {remaining_time:.1f}s")
        
        total_time = time.time() - start_time
        avg_speed = self.firmware_size / total_time / 1024
        print(f"   数据传输完成! 总时间: {total_time:.1f}s, 平均速度: {avg_speed:.1f} KB/s")
        return True
    
    async def send_end_command(self):
        """发送结束升级命令"""
        print("\n7. 发送结束升级命令...")
        end_cmd = struct.pack('B', CMD_END)
        print(f"   发送结束命令: {end_cmd.hex()}")
        
        # 包装命令数据（添加数据类型前缀）
        wrapped_end_cmd = struct.pack('B', 0x01) + end_cmd
        
        if not await self.write_characteristic(wrapped_end_cmd):
            return False
        
        print("   结束命令发送完成")
        return True
    
    async def run(self):
        """主执行流程"""
        # 1. 加载固件文件
        if not await self.load_firmware():
            return False
        
        # 2. 扫描设备
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
            
            # 6. 发送结束命令
            if not await self.send_end_command():
                return False
            
            print("\n8. 等待设备处理升级...")
            print("   固件发送完成，等待设备处理升级...")
            
            # 等待设备处理
            await asyncio.sleep(5)
            
            print("\n" + "="*50)
            print("升级流程完成! 设备应该正在重启...")
            print("请查看设备日志确认升级结果")
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

async def main(args):
    """主函数"""
    tool = Air5101FotaTool(args.device, args.firmware)
    success = await tool.run()
    return success

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Air5101 BLE FOTA 升级工具")
    parser.add_argument("-d", "--device", default="Air5101_FOTA", help="目标设备名称")
    parser.add_argument("-f", "--firmware", required=True, help="固件文件路径")
    
    args = parser.parse_args()
    
    success = asyncio.run(main(args))
    exit(0 if success else 1)
