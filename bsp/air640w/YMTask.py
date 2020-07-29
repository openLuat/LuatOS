import math

class TaskState:
    ERROR = -99
    ABORTED = -1
    PREPARED = 0
    RUNNING = 1
    FINISHED = 2

class SendTask(object):
    def __init__(self):
        self._state = TaskState.PREPARED
        self._task_name = ""
        self._task_size = 0
        self._task_packets = 0
        self._last_valid_packets_size = 0
        self._sent_packets = 0
        self._missing_sent_packets = 0
        self._valid_sent_packets = 0
        self._valid_sent_bytes = 0
    
    def inc_sent_packets(self):
        self._sent_packets += 1

    def inc_missing_sent_packets(self):
        self._missing_sent_packets += 1

    def inc_valid_sent_packets(self):
        self._valid_sent_packets += 1

    def add_valid_sent_bytes(self, this_valid_sent_bytes):
        self._valid_sent_bytes += this_valid_sent_bytes

    def get_valid_sent_packets(self):
        return self._valid_sent_packets

    def get_valid_sent_bytes(self):
        return self._valid_sent_bytes

    def set_task_name(self, data_name):
        self._task_name = data_name

    def set_task_size(self, data_size):
        self._task_size = data_size
        self._task_packets = math.ceil(data_size / 1024)
        self._last_valid_packets_size = data_size % 1024

class ReceiveTask(object):
    def __init__(self):
        self._state = TaskState.PREPARED
        self._task_name = ""
        self._task_size = 0
        self._task_packets = 0
        self._last_valid_packets_size = 0
        self._received_packets = 0
        self._missing_received_packets = 0
        self._valid_received_packets = 0
        self._valid_received_bytes = 0
    
    def inc_received_packets(self):
        self._received_packets += 1

    def inc_missing_received_packets(self):
        self._missing_received_packets += 1

    def inc_valid_received_packets(self):
        self._valid_received_packets += 1

    def add_valid_received_bytes(self, this_valid_received_bytes):
        self._valid_received_bytes += this_valid_received_bytes

    def get_task_packets(self):
        return self._task_packets

    def get_last_valid_packet_size(self):
        return self._last_valid_packets_size

    def get_valid_received_packets(self):
        return self._valid_received_packets

    def get_valid_received_bytes(self):
        return self._valid_received_bytes

    def set_task_name(self, data_name):
        self._task_name = data_name

    def set_task_size(self, data_size):
        self._task_size = data_size
        self._task_packets = math.ceil(data_size / 1024)
        self._last_valid_packets_size = data_size % 1024
    
    def get_task_name(self):
        return self._task_name
    
    def get_task_size(self):
        return self._task_size