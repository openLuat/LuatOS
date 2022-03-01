import sys
import paho.mqtt.client as mqtt
import paho.mqtt.publish as publish
from git import Repo

client = mqtt.Client()
repo = Repo("../")
try:
    #服务器请自行修改，需要传入参数
    client.connect(sys.argv[1], int(sys.argv[2]), 60)
    #topic请根据需要自行修改，需要传入参数
    info = sys.argv[4]+"\r\n"+str(repo.head.commit.author)+"-"+str(repo.head.commit.message)
    if len(sys.argv) >= 6:
        repo = Repo("../../"+sys.argv[5])
        info = info+"\r\n子仓库"+sys.argv[5]+"最后提交：\r\n"+str(repo.head.commit.author)+"-"+str(repo.head.commit.message)
    pub = client.publish(sys.argv[3],info)
    pub.wait_for_publish()
    client.disconnect()
    print("sent")
except Exception as e:
    print(e)

