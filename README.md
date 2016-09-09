# iPadPix: Visualisation of Radioactivity in Real-Time on a Tablet

- Using means of Augmented Reality 
- Designed for educational settings 
- Based on a hybrid pixel detector technology developed at CERN: 300 μm silicon sensor on Timepix chip

Inspired by cloud chambers, this novel tool allows an intuitive exploration of natural and other sources of low radioactivity. Different particle types are distinguished by evaluating their interaction with a pixel detector. Recorded traces of radiation are displayed on top of the live video feed from a tablet’s camera. The mobility of iPadPix enables new experimental activities to observe radioactivity from every-day objects and the environment over time and space.

## Data Flow

Real-time processing of Timepix pixel data is achieved via a modified version of MAFalda (https://github.com/ozel/mafalda) on the 'MinnowdBoard Max, an embedded Linux board. Pixel clusters are sent in an open and efficient format over WiFi to the iPad, using the AVRO data serialisation library and an UDP connection. The iPad application classifies the clusters according to shape and energy into different particle categories. The results are animated and displayed as overlay on the live camera feed. 

Further details in this CERN thesis: https://cds.cern.ch/record/2062012

## Requirements for this iOS App

_Libraries_:

GCDAsyncSocket: https://github.com/robbiehanson/CocoaAsyncSocket

ObjectiveAvro: http://cocoadocs.org/docsets/ObjectiveAvro

_Hardware_:

Timepix: https://medipix.web.cern.ch/medipix/pages/medipix2/timepix.php

MinnowBoard Max: http://wiki.minnowboard.org/MinnowBoard_MAX

Wide angle lens from iPro lens systems: http://www.iprolens.com/lenses 

### Build

iOS 8 SDK

### Runtime

iOS 8 or later

App based on AVCamManual example from Apple: https://developer.apple.com/library/ios/samplecode/AVCamManual/Introduction/Intro.html