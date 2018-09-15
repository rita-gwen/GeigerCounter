# GeigerCounter
Firmware and software for a portable Geiger-Mueller counter. 

This project represents a portable, battery powered instrument built around Basic Nano (PIC16F87) microcontroller. The device detects 
radiation particles passing through the detector and keeps total count of them since startup and average over the 
last minute (Counts per Minute). 

This repository includes code of the firmware running on the MCU in the device and a Python application that runs on a PC, 
reads data from the device and shows a real-time plot of the counts. Basic Nano runs an embedded version of MBasic which is used to implement the main loop, power management and display functionality. There are also a couple of assembly procedures for timer ISR that actually gets the counts from the hardware and for low-level display bus handling.

The device successfully passed field testing: I took it on multiple hikes and trips around Cascades and Eastern Washington and it is reliable and performs well - I was able to detect some mildly radioactime granites and verify radiation background change with altitude. 
Features to be implemented in the next version:
 * reduced weight: use LiPO batteries instead of NiMH
 * reduce power consumption (related to the previous item)
 * Improve display visibility in full day light: LCD display is almost invisible in full sun.
 * Add multiple modes of operation: background monitoring, sample measurement
 * add data logging abilities
 * use more advanced CPU, one of ST32 CORTEX-M0 family most probably.

Please ignore the DipTrace schematic and PCB files here, they are outdated. Hardware design files are moved to CircuitMaker (https://circuitmaker.com/Projects/Details/Rita-Chupalov/Geiger). The version of DipTrace I have has too many limitations for this 
project.

Assembly.FCStd is a FreeCAD sketch of the device components fitting into the enclosure.
