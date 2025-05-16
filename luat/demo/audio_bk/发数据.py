import socket
import time,fpstimer
import numpy as np
from scipy.io.wavfile import write
# 配置 UDP 端口和绑定地址
UDP_IP = "0.0.0.0"  # 监听所有可用的网络接口
UDP_PORT = 8899     # 监听的端口
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM,socket.IPPROTO_UDP)
sock.bind((UDP_IP, UDP_PORT))
# _,target = sock.recvfrom(1500)
target = ('192.168.32.102', 8899)
print("已经连接",target)

with open("1.bin","rb") as f:
    d=f.read()
    data2=np.frombuffer(d,dtype=np.int16)
    
data2 = data2.astype(np.float32) * 32000.0 / np.max(np.abs(data2))
data2 = data2.astype(np.int16)[::2]

with open("2.bin","wb") as f:
    f.write(data2.tobytes())
with open("2.bin","rb") as f:
    while True:
        d=f.read(1024)
        
        if len(d) == 0:break
        n=sock.sendto(d,target)
        while sock.recvfrom(1500)[0] != b'OK':pass
sock.close()

