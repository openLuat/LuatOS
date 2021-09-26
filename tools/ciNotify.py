import sys
import paho.mqtt.client as mqtt
import paho.mqtt.publish as publish

client = mqtt.Client()
try:
    #服务器请自行修改，需要传入参数
    client.connect(sys.argv[1], int(sys.argv[2]), 60)
    #topic请根据需要自行修改，需要传入参数
    pub = client.publish(sys.argv[3],sys.argv[4])
    pub.wait_for_publish()
    client.disconnect()
    print("sent")
except Exception as e:
    print(e)

