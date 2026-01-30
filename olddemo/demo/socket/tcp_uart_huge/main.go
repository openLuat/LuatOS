package main

import (
	"fmt"
	"net"
)

// TCP Server端测试
// 处理函数
func process(conn net.Conn) {
	fmt.Printf("新的客户端 %s\n", conn)
	defer conn.Close() // 关闭连接
	var counter = 0
	for {
		var buf = make([]byte, 1024)
		buf[0] = 'L'
		buf[1] = 0xA5
		buf[1023] = 0xAA
		conn.Write(buf) // 发送数据
		counter += 1024
		if (counter >= 8 * 1024 * 1024) {
			break
		}
	}
	
	fmt.Printf("数据发送完成 %s\n", conn)
}

func main() {
	listen, err := net.Listen("tcp", "0.0.0.0:9999")
	if err != nil {
		fmt.Println("Listen() failed, err: ", err)
		return
	}
	for {
		conn, err := listen.Accept() // 监听客户端的连接请求
		if err != nil {
			fmt.Println("Accept() failed, err: ", err)
			continue
		}
		go process(conn) // 启动一个goroutine来处理客户端的连接请求
	}
}
