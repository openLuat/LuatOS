use lazy_static::*;
use std::{os::raw::*, sync::Mutex, thread, collections::HashMap};

pub type RecvCB = unsafe extern fn(c_int,c_int);
pub type SentCB = unsafe extern fn(c_int,c_int);

lazy_static! {
    //是不是还开着
    static ref UART_IS_CLOSED: Mutex<HashMap<i32,bool>> = Mutex::new(HashMap::new());
    //接收回调
    static ref UART_RECV_CB: Mutex<HashMap<i32,RecvCB>> = Mutex::new(HashMap::new());
    //发送回调
    static ref UART_SENT_CB: Mutex<HashMap<i32,SentCB>> = Mutex::new(HashMap::new());
    //是否有数据等待发送
    static ref UART_WAIT_SEND: Mutex<HashMap<i32,bool>> = Mutex::new(HashMap::new());
    //等待发送的数据是？
    static ref UART_WAIT_SEND_DATA: Mutex<HashMap<i32,Vec<u8>>> = Mutex::new(HashMap::new());
    //接收到的数据缓冲区
    static ref UART_BUFF: Mutex<HashMap<i32,Vec<u8>>> = Mutex::new(HashMap::new());
}

//检查串口是不是开着（只检查标记）
fn check_port_is_open(port: i32) -> bool {
    let map = UART_IS_CLOSED.lock().unwrap();
    match map.get(&port) {
        Some(b) if *b => false,
        _ => true
    }
}

//切掉开头的数据
fn vec_cut(v: &mut Vec<u8>, start: usize) {
    for i in 0..v.len() - start {
        v[i] = v[i + start];
    }
    v.resize(v.len() - start, 0);
}


// //检测串口存不存在
// int (*luat_uart_exist_extern)(int id)  = NULL;
#[no_mangle]
pub extern fn luat_uart_exist_extern(port: i32) -> i32 {
    let port = format!("COM{}",port);
    match serialport::available_ports() {
        Ok(l) => {
            if l.iter().any(|i|i.port_name == port) {
                return 1;
            }
        },
        _ => ()
    };
    0
}

// //获取可用串口列表
// int (*luat_uart_get_list_extern)(uint8_t* list, size_t buff_len)  = NULL;
#[no_mangle]
pub extern fn luat_uart_get_list_extern(list: *mut u8, buff_len: usize) -> i32 {
    match serialport::available_ports() {
        Ok(l) => {
            let len = if l.len() > buff_len {buff_len} else {l.len()};
            let buff = unsafe{std::slice::from_raw_parts_mut(list, len)};
            for i in 0..len {
                buff[i] = l[i].port_name.replace("COM", "").parse().unwrap();
            }
            len.try_into().unwrap()
        },
        _ => 0
    }
}

// //打开串口
// int (*luat_uart_open_extern)(int id,int br,int db, int sb, int para)  = NULL;
#[no_mangle]
pub extern fn luat_uart_open_extern(port: i32, baud_rate: i32, data_bits: i32, stop_bits: i32, parity: i32) -> i32 {
    let mut uart = match serialport::new(format!("COM{}",port), baud_rate.try_into().unwrap())
        .timeout(std::time::Duration::from_millis(5))
        .data_bits(match data_bits {
            5 => serialport::DataBits::Five,
            6 => serialport::DataBits::Six,
            7 => serialport::DataBits::Seven,
            _ => serialport::DataBits::Eight
        })
        .stop_bits(match stop_bits {
            2 => serialport::StopBits::Two,
            _ => serialport::StopBits::One
        })
        .parity(match parity {
            1 => serialport::Parity::Odd,
            2 => serialport::Parity::Even,
            _ => serialport::Parity::None
        })
        .open() {
            Ok(r) => r,
            Err(_) => return 1,
        };
    uart.write_request_to_send(false).unwrap();//防止之前没退出复位状态

    
    {
        //先开个接收缓冲
        let map = &mut *UART_BUFF.lock().unwrap();
        map.insert(port, vec![]);
        //关闭状态肯定不能为真
        let map = &mut *UART_IS_CLOSED.lock().unwrap();
        map.remove(&port);
    }

    //接收线程
    thread::spawn(move || {
        loop {
            let mut serial_buf: Vec<u8> = vec![0; 1024];
            let len = match uart.read(serial_buf.as_mut_slice()) {
                Err(e) => {
                    if e.kind() == std::io::ErrorKind::TimedOut {//接收超时不算错误
                        0
                    } else {//串口断了
                        let map = &mut *UART_IS_CLOSED.lock().unwrap();
                        map.insert(port, true);
                        return
                    }
                },
                Ok(r) => r,
            };
            //有数据上来
            if len > 0 {
                {
                    let map = &mut *UART_BUFF.lock().unwrap();
                    //数据读出来
                    let uart_data = match map.get_mut(&port) {
                        Some(b) => b,
                        _ => return//不太可能发生
                    };
                    for i in 0..len {
                        uart_data.push(serial_buf[i]);
                    }
                }
                {
                    //触发接收回调
                    let map = &mut *UART_RECV_CB.lock().unwrap();
                    match map.get(&port) {
                        Some(b) => {
                            unsafe{
                                b(port,len.try_into().unwrap());
                            }
                        },
                        _ => ()
                    };
                }
            }
            {//串口是不是被关了？
                let map = &mut *UART_IS_CLOSED.lock().unwrap();
                match map.get(&port) {
                    Some(b) if *b => return,//真被关了
                    _ => ()
                };
            }
            {//是不是有待发送数据？
                let wait_map = &mut *UART_WAIT_SEND.lock().unwrap();
                let wait_send = {
                    match wait_map.get_mut(&port) {
                        Some(b) if *b => true,//有待发送数据
                        _ => false
                    }
                };
                if wait_send {
                    let map = &mut *UART_WAIT_SEND_DATA.lock().unwrap();
                    if let Some(data) = map.get_mut(&port) {
                        let r = match uart.write(data.as_slice()) {
                            Ok(_) => true,
                            Err(_) => false
                        };
                        data.clear();
                        if !r{//发失败了，说明串口关了
                            println!("\r\n[waring] win32 uart send data failed, maybe disconnected?\r\n");
                        }
                    }
                    wait_map.remove(&port);
                }
            }
        }
    });
    0
}


// //关闭串口
// int (*luat_uart_close_extern)(int id)  = NULL;
#[no_mangle]
pub extern fn luat_uart_close_extern(id: i32) -> i32 {
    {
        let map = &mut *UART_IS_CLOSED.lock().unwrap();
        map.insert(id, true);
    }
    {
        let map = &mut *UART_RECV_CB.lock().unwrap();
        map.remove(&id);
    }
    {
        let map = &mut *UART_SENT_CB.lock().unwrap();
        map.remove(&id);
    }
    {
        let map = &mut *UART_WAIT_SEND.lock().unwrap();
        map.remove(&id);
    }
    {
        let map = &mut *UART_WAIT_SEND_DATA.lock().unwrap();
        map.remove(&id);
    }
    {
        let map = &mut *UART_BUFF.lock().unwrap();
        map.remove(&id);
    }
    0
}


// //读取数据
// int (*luat_uart_read_extern)(int id,void* buff, size_t len)  = NULL;
#[no_mangle]
pub extern fn luat_uart_read_extern(port: i32, buff: *mut u8, len: usize) -> i32 {
    //看看串口开没开
    if !check_port_is_open(port) {
        return 0;
    }
    let map = &mut *UART_BUFF.lock().unwrap();
    //数据读出来
    let read_buff = match map.get_mut(&port) {
        Some(b) => b,
        _ => return 0
    };

    //判断下缓冲区有没有那么大，别超了
    let len = if read_buff.len() >= len {
        len
    } else {
        read_buff.len()
    };
    let buff = unsafe{std::slice::from_raw_parts_mut(buff, len)};
    //把数据扔到buff
    buff.clone_from_slice(&read_buff[0..len]);
    //切掉已经读到的数据
    vec_cut(read_buff, len);

    len.try_into().unwrap()
}


// //发送数据
// int (*luat_uart_send_extern)(int id,void* buff, size_t len)  = NULL;
#[no_mangle]
pub extern fn luat_uart_send_extern(port: i32, buff: *const u8, len: usize) -> i32 {
    //看看串口开没开
    if !check_port_is_open(port) {
        return 0;
    }
    let map = &mut *UART_WAIT_SEND_DATA.lock().unwrap();
    //数据读出来
    let send_buff = match map.get_mut(&port) {
        Some(b) => b,
        _ => {
            map.insert(port, vec![]);
            map.get_mut(&port).unwrap()
        }
    };

    //数据塞进去
    let buff = unsafe{std::slice::from_raw_parts(buff, len)};
    for i in 0..len {
        send_buff.push(buff[i]);
    }

    let map = &mut *UART_WAIT_SEND.lock().unwrap();
    //待发送标记
    map.insert(port, true);

    len.try_into().unwrap()
}

// //配置接收回调
// int (*luat_uart_recv_cb_extern)(int id,void (*)(int id, int len))  = NULL;
#[no_mangle]
pub extern fn luat_uart_recv_cb_extern(port: i32, cb: RecvCB) -> i32 {
    let map = &mut *UART_RECV_CB.lock().unwrap();
    map.insert(port, cb);
    0
}


// //配置发送回调
// int (*luat_uart_sent_cb_extern)(int id,void (*)(int id, int len))  = NULL;
#[no_mangle]
pub extern fn luat_uart_sent_cb_extern(_port: i32, _cb: SentCB) -> i32 {
    // let map = &mut *UART_SENT_CB.lock().unwrap();
    // map.insert(port, cb);
    // 1
    println!("\r\n[waring] win32 uart lib do not support uart sent cb function\r\n");
    1
}
