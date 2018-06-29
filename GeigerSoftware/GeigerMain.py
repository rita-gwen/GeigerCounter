
import wx
import json

from GeigerSerial import GeigerSerial
import GeigerSerial as gs
from DataPanel import DataPanel

ID_NEW_FILE = 1
ID_OPEN_FILE = 2
ID_DEVICE_CONNECT = 3   #the range of IDs from 3 to 13 is reserved for multiple devices
ID_DEVICE_DISCONNECT = 14

# TODO:
# Plotting voltages
# Plot scale 
# x axis in date/time units
# add battery level/voltage indicator
# package into a standalone application (with icon)
# replace prints with proper logging
# Add battery charging on/off control
# do not keep the full file in memory, only CMP data for the chart
# Add retry to the serial thread to prevent abnormal termination on single read failure
# add ability to add comments/time marks to the data file
#
# Plot scroll - DONE
# vieport position reset on new file - DONE
# Saving to a file - DONE
# Timestamping - DONE
# Show number of data points in the status bar - DONE

class AppWindow(wx.Frame):

    def __init__(self):
        wx.Frame.__init__(self, parent = None, title="Geiger Monitor", size=[1000, 1000])
        # Set up the menu
        self.menuBar = wx.MenuBar() 
        fileMenu = wx.Menu()
        fileMenu.Append(ID_NEW_FILE, "New File", "Start new recording file")
        fileMenu.Append(ID_OPEN_FILE, "Open File", "Open a file with previous session data")
        self.menuBar.Append(fileMenu, "File")
        deviceListMenu = wx.Menu()
        i = 0
        for p in GeigerSerial.listPorts():
            deviceListMenu.Append(ID_DEVICE_CONNECT + i, p.device, p.description)
            i += 1
        if deviceListMenu.GetMenuItemCount() == 0:
            deviceListMenu.Append(0, "No devices found").Enable(False)
        deviceMenu = wx.Menu()
        self.connectMenu = deviceMenu.AppendSubMenu(deviceListMenu, "Connect Device>")
        self.disconnectMenu = deviceMenu.Append(ID_DEVICE_DISCONNECT, "Disconnect device")
        self.disconnectMenu.Enable(False)
        self.menuBar.Append(deviceMenu, "Device")
        self.SetMenuBar(self.menuBar)
        #
        #data representation UI
        self.panel = DataPanel(self)
        self.statusBar = self.CreateStatusBar()
        self.statusBar.SetFieldsCount(4)
        self.panel.draw()
        #
        # Events binding
        self.Bind(wx.EVT_MENU, self.OnFileOpen, id=ID_OPEN_FILE)
        self.Bind(wx.EVT_MENU, self.OnNewFile, id=ID_NEW_FILE)
        self.Bind(wx.EVT_MENU_RANGE, self.OnMenuConnect, id = ID_DEVICE_CONNECT, id2 = ID_DEVICE_CONNECT + 10)
        self.Bind(wx.EVT_MENU, self.OnMenuDisconnect, id = ID_DEVICE_DISCONNECT)
        self.Bind(wx.EVT_CLOSE, self.OnExit)
        # Set up the COM
        self.serial = None

    #----------------------------
    # Serial port event handlers
    def OnDeviceData(self, event):
        #print(event.data)
        self.panel.addData(event.data)  
        self.statusBar.SetStatusText("Points:%d" % len(self.panel.cpmData), 3)      

    def OnDeviceConnect(self, event):
        print("Connect event received from ", event.data)
        self.connectMenu.Enable(False)
        self.disconnectMenu.Enable(True)
        self.panel.reset()
        self.statusBar.SetStatusText("Connected to " + event.data, 1)
        self.statusBar.SetStatusText("", 2)

    def OnDeviceDisconect(self, event):
        print("Disconnect event received from ", event.data)
        self.connectMenu.Enable(True)
        self.disconnectMenu.Enable(False)
        for i in range(1,3):
            self.statusBar.SetStatusText("", i) 
    # ------
    # Menu event handlers
    def OnMenuConnect(self, event):
        portList = GeigerSerial.listPorts()
        deviceName = portList[event.Id - ID_DEVICE_CONNECT].device
        print('Device Connect menu selected', deviceName)
        self.serial = GeigerSerial(deviceName, self)
        self.Bind(gs.EVT_SERIAL_OPEN, self.OnDeviceConnect)
        self.Bind(gs.EVT_SERIAL_RX, self.OnDeviceData)
        self.Bind(gs.EVT_SERIAL_CLOSE, self.OnDeviceDisconect)
        self.serial.StartPortThread()

    def OnMenuDisconnect(self, event):
        print('Device Disconnect menu selected')
        self.serial.EndPortThread()

    # Use Case: Open existing data file to examine the data
    def OnFileOpen(self, event):
        print('File Open menu selected')

    # Use case: Specify the file name to save the existing data to. 
    # Can be invoked at any point during or after the recording session
    def OnNewFile(self, event):
        print('New File menu selected')
        with wx.FileDialog(
                None,
                "Save Data As...",
                ".",
                "",
                "Text File|*.txt|JSON Files|*.json|All Files|*",
                wx.FD_SAVE | wx.FD_OVERWRITE_PROMPT) as dlg:
            if dlg.ShowModal() == wx.ID_OK:
                filename = dlg.GetPath()
                self.panel.saveData(filename)
                self.statusBar.SetStatusText("File:"+ filename, 2)

    def OnExit(self, event):
        if self.serial is not None:
            self.serial.EndPortThread()
        self.Destroy()
        



if __name__ == "__main__":
    app = wx.App()
    fr = AppWindow()
    fr.Show()
    app.MainLoop()
    