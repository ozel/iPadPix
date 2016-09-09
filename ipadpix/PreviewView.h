//
//  PreviewView.h
//  iPadPix
//
//  Copyright (c) 2014 Oliver Keller. All rights reserved.
//

#import "CameraFocusSquare.h"
#import "CameraViewController.h"

@import UIKit;

CameraFocusSquare *camFocus;


@class AVCaptureSession;

@interface PreviewView : UIView

@property (nonatomic) AVCaptureSession *session;


@end
