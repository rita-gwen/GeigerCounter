# GeigerCounter
Firmware and software for a portable Geiger-Mueller counter. Hardware design files are moved to CircuitMaker (https://circuitmaker.com/Projects/Details/Rita-Chupalov/Geiger).

This project represents a portable, battery powered instrument built around Basic Nano (PIC16F87) microcontroller. The device detects 
radiation particles passing through the detector and keeps total count of them since startup and average over the 
last minute (Counts per Minute). 
This repository includes code of the firmware running on the MCU in the device and a Python application that runs on a PC, 
reads data from the device and shows a real-time plot of the counts.



