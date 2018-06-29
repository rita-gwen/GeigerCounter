import serial
import serial.tools.list_ports
import threading
import wx
import json
from datetime import datetime 

DEVICE_BAUD_RATE = 19200

# ----------------------------------------------------------------------
# Create an own event type, so that GUI updates can be delegated
# this is required as on some platforms only the main thread can
# access the GUI without crashing. wxMutexGuiEnter/wxMutexGuiLeave
# could be used too, but an event is more elegant.

class SerialEvent(wx.CommandEvent):
    def __init__(self, etype, data):
        wx.CommandEvent.__init__(self, commandEventType = etype)
        self.data = data

    def Clone(self):
        # See https://stackoverflow.com/questions/48113110/wxpython-pyserial-and-wx-terminal-thread-fails-to-update-the-gui
        return self.__class__(self.GetEventType(), self.data)

#------------------


SERIAL_RX = wx.NewEventType()
# bind to serial data receive events
EVT_SERIAL_RX = wx.PyEventBinder(SERIAL_RX, 0)

# Serial port opened event
SERIAL_OPEN = wx.NewEventType()
# bind to serial data receive events
EVT_SERIAL_OPEN = wx.PyEventBinder(SERIAL_OPEN, 0)

# Serial port closed event
SERIAL_CLOSE = wx.NewEventType()
# bind to serial data receive events
EVT_SERIAL_CLOSE = wx.PyEventBinder(SERIAL_CLOSE, 0)

#-----------------------------------------------------------------------
# Serial port wrapper
class GeigerSerial():

    #Lists all FTDI devices visible in the system
    @staticmethod
    def listPorts():
        ports = []
        for p in serial.tools.list_ports.comports():
            if p.manufacturer == 'FTDI':
                ports.append(p)
        return ports

    def __init__(self, portName, parent):
        self.port =  None
        self.alive = threading.Event()
        self.parentFrame = parent
        self.portName = portName
        self.thread = None
        self.isOpen = False

    def StartPortThread(self):
        if self.port is not None:
            self.port.close()
        try:
            self.port = serial.Serial(self.portName, DEVICE_BAUD_RATE, timeout=10)
            self.port.dtr = False
        except serial.SerialException as e:
            with wx.MessageDialog(self.parentFrame, str(e), "Serial Port Error", wx.OK | wx.ICON_ERROR) as dlg:
                dlg.ShowModal()
        else:
            self.isOpen = True
            if self.parentFrame is not None:
                event = SerialEvent(SERIAL_OPEN, self.portName)
                wx.PostEvent(self.parentFrame, event)
            else:
                print('Port', self.portName, 'is open')
            self.alive.set()
            self.thread = threading.Thread(target = self.PortThread)
            self.thread.setDaemon(1)
            self.thread.start()

    def EndPortThread(self):
        if self.thread is not None:
            self.alive.clear()
            self.thread.join()
            self.port.close()
            self.thread = None
            self.isOpen = False
            if self.parentFrame is not None:
                event = SerialEvent(SERIAL_CLOSE, self.portName)
                self.parentFrame.GetEventHandler().AddPendingEvent(event)
            else:
                print('Port', self.portName, 'is open')


    def PortThread(self):
        while self.alive.isSet():
            lin = self.port.readline()
            dat = json.loads(lin)
            dat['time'] = datetime.now().strftime('%Y-%m-%d %H:%M:%S.%f')
            if self.parentFrame is not None:
                event = SerialEvent(SERIAL_RX, dat)
                self.parentFrame.GetEventHandler().AddPendingEvent(event)
            #else:
            #    print('Data:', dat)
    
if __name__ == '__main__':  
    ser = GeigerSerial('COM6', None)
    ser.StartPortThread()
    ser.thread.join(60)
    ser.EndPortThread()