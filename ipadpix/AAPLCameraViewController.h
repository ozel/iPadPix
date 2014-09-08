/*
 Copyright (C) 2014 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 
  Control of camera functions.
  
*/

@import UIKit;
#import "TPXFrameBufferLayer.h"



CGPoint focusPOI;
UIView *fPview;


@interface AAPLCameraViewController : UIViewController
@property (nonatomic) CGRect focusPointer;
@property (nonatomic) TPXFrameBufferLayer * fBuffer;
@property (nonatomic) UIImageView * overlayImageView;



@end
