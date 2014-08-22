/*
 Copyright (C) 2014 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 
  Control of camera functions.
  
*/

@import UIKit;
#import "RSFrameBufferLayer.h"



CGPoint focusPOI;
UIView *fPview;


@interface AAPLCameraViewController : UIViewController
@property (nonatomic) CGRect focusPointer;
@property (nonatomic) RSFrameBufferLayer * fBuffer;
@property (nonatomic) UIImageView * overlayImageView;



@end
