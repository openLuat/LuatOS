import socket
import time
import numpy as np
from scipy.io.wavfile import write
# 配置 UDP 端口和绑定地址
UDP_IP = "0.0.0.0"  # 监听所有可用的网络接口
UDP_PORT = 8899     # 监听的端口
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind((UDP_IP, UDP_PORT))
print("已经连接")
data2 = []
lastroll = None
try:
    with open("1.bin","wb") as f:
        while True:
            data,_ = sock.recvfrom(1500)  # 每次接收最大 1024 字节
            f.write(data[4:])
            roll = int.from_bytes(data[:4],'little')
            if lastroll is not None and roll != lastroll +1:
                print(roll,lastroll,len(data))
            else:
                print(len(data))
            lastroll=roll
            
except KeyboardInterrupt:
    pass
sock.close()
with open("1.bin","rb") as f:
    d=f.read()
    data2=np.frombuffer(d,dtype=np.int16).reshape([-1,2])

data2 = data2.astype(np.float32) * 32000.0 / np.max(np.abs(data2))
data2 = data2.astype(np.int16)
write("output.wav", 8000, data2)

