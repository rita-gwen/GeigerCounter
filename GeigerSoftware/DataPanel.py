
from numpy import arange, sin, pi, array
import matplotlib
matplotlib.use('WXAgg')
import matplotlib.pyplot as plt

from matplotlib.backends.backend_wxagg import FigureCanvasWxAgg as FigureCanvas
from matplotlib.backends.backend_wx import NavigationToolbar2Wx
from matplotlib.figure import Figure
from matplotlib.widgets import Slider

import wx
import json
import numpy as np

VIEWPORT_EXTENSION_INCREMENT = 30
def min(a, b):
    if a<=b: 
        return a
    else:
        return b

def max(a, b):
    if a>=b: 
        return a
    else:
        return b

class DataPanel(wx.Panel):
    def __init__(self, parent):
        wx.Panel.__init__(self, parent)
        # Set up UI
        self.figure = Figure()
        self.axes = self.figure.add_subplot(111)
        self.canvas = FigureCanvas(self, -1, self.figure)
        self.outputText = wx.TextCtrl(self, style=wx.TE_MULTILINE | wx.TE_READONLY)
        self.sizer = wx.BoxSizer(wx.VERTICAL)
        self.sizer.Add(self.canvas, 1, wx.LEFT | wx.TOP | wx.GROW)
        self.sizer.Add(self.outputText, 1, wx.GROW)
        self.SetSizer(self.sizer)
        self.Fit()
        #
        self.reset()
        #
        self.canvas.Bind(wx.EVT_SCROLLWIN, self.OnScrollEvt)

    def reset(self):
        self.clearData()
        self.filePath = None
        self.viewport_size = 50
        self.viewport_pos = 1
        self.canvas.SetScrollbar(wx.HORIZONTAL, 0, self.viewport_size, self.viewport_size)
        self.lines = None
        self.draw()


    def draw(self):
        #initial window setup
        newPointIndex = len(self.rawData)
        if newPointIndex == self.viewport_pos + self.viewport_size - 1:
            self.viewport_pos += VIEWPORT_EXTENSION_INCREMENT
            self.canvas.SetScrollbar(wx.HORIZONTAL, self.viewport_pos, self.viewport_size, self.viewport_pos + self.viewport_size)
        self.drawVieport()
 
    def drawVieport(self):
        self.axes.set_xlim(self.viewport_pos, self.viewport_pos + self.viewport_size - 1)
        if len(self.cpmData) > 0:
            self.axes.set_ylim(1, np.max(self.cpmData) + 15)
        else:
            self.axes.set_ylim(1, 15)
            self.axes.clear()
        x = arange(self.viewport_pos,min(self.viewport_pos + self.viewport_size - 1, len(self.cpmData)))
        y = array(self.cpmData[self.viewport_pos:min(self.viewport_pos + self.viewport_size - 1, len(self.cpmData))])
        if self.lines is not None:
            self.lines[0].set_data(x, y)
        else:
            if len(self.cpmData) > 2:
                self.lines = self.axes.plot(x, y)
        self.canvas.draw()

    def isTailVisible(self):
        newPointIndex = len(self.rawData)
        #if the new data point is within visible range
        return (newPointIndex >= self.viewport_pos and newPointIndex <= self.viewport_pos + self.viewport_size - 1)

    def addData(self, data):
        self.cpmData.append(data['cpm']) 
        self.outputText.AppendText(json.dumps(data) + '\n')
        #trim the text field content to prevent memory wasting
        if self.outputText.GetNumberOfLines() > 10:
            lineLen = self.outputText.GetRange(0, 500).index('}')
            self.outputText.Remove(0, lineLen + 3)
        #
        # DONE: store the record in the file if the file name is specified. 
        if self.filePath is not None:
            file = open(self.filePath, 'a')
            json.dump(data, file)
            file.write('\n')
            file.close()
        else:
            # otherwise store it in the memory array
            self.rawData.append(data)
        self.draw()

    def clearData(self):
        self.rawData = []
        self.cpmData = []
        self.outputText.SetValue('')
        self.filePath = None

    # saves the data accumulated so far and stores the 
    # file name and file object
    def saveData(self, filePath):
        self.filePath = filePath
        #save the data in the memory into the file
        file = open(self.filePath, 'w')
        for p in self.rawData:
            json.dump(p, file)
            file.write('\n')
        file.close()
        #and clear the array
        self.rawData.clear()

    def OnScrollEvt(self, event):
        self.viewport_pos = event.GetPosition()
        self.canvas.SetScrollbar(wx.HORIZONTAL, self.viewport_pos, self.viewport_size, len(self.cpmData) + VIEWPORT_EXTENSION_INCREMENT)
        self.drawVieport()
