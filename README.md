# Introduction

ztachip is an opensource framework to build both AI hardware and software. 

ztachip has the full hardware implementation available in VHDL source code.

ztachip hardware can be deployed to FPGA hardware or custom ASIC.

ztachip is fully software programmable by using a special tensor programming paradigm. 

The hardware does not have to be rewire for different applications, making ztachip ideal for porting to ASIC due to its low logic gate counts.

Unlike many other AI acceleration architectures, ztachip is flexible enough to run not just neural-network functions, but also a wide range of image processing such as image resizing, edge detection, image blurring, optical flow, harris corner feature extraction,...  

# Demonstration 


Run objectDetection,edgeDetection,motionDetection and featureOfInterest extraction together at same time.

![ObjectDetect+EdgeDetection+OpticalFlow+Harris](Documentation/images/all.gif)

Run object detection using SSD-MobiNetv1.0

![Object Detection](Documentation/images/obj_detect.gif)

Run image classfication using MobiNetv2.0

![Classifier](Documentation/images/classifier.gif)

Run Edge detection

![Edge detection](Documentation/images/edge_detect.gif)

Run HarrisCorner feature of interest extraction

![HarrisCorner](Documentation/images/harris_corner.gif)


# Getting started 

[Build Procedure](https://github.com/ztachip/ztachip/blob/master/Documentation/BuildProcedure.md)

[FPGA Build Procedure](https://github.com/ztachip/ztachip/blob/master/Documentation/HardwareBuildProcedure.md)

[ztachip Hardware Architecture](https://github.com/ztachip/ztachip/blob/master/Documentation/HardwareArchitecture.md)

[ztachip Software Architecture](https://github.com/ztachip/ztachip/blob/master/Documentation/SoftwareArchitecture.md)

[Programmer Guide (pcore)](https://github.com/ztachip/ztachip/blob/master/Documentation/pcore_programmer_guide.md)

[Programmer Guide (mcore)](https://github.com/ztachip/ztachip/blob/master/Documentation/mcore_programmer_guide.md)

[Programmer Guide (app)](https://github.com/ztachip/ztachip/blob/master/Documentation/app_programmer_guide.md)

# Copyright and license 

Copyright: Vuong Nguyen For licensing details please visit [LICENSE.md](https://github.com/ztachip/ztachip/blob/master/LICENSE.md)







