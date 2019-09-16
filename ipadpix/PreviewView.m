//
//  PreviewView.h
//  iPadPix
//
//  Copyright (c) 2014 Oliver Keller. All rights reserved.
//


#import "PreviewView.h"
#import "CameraFocusSquare.h"
#import <AVFoundation/AVFoundation.h>

CameraFocusSquare *camFocus;


@implementation PreviewView



+ (Class)layerClass
{
	return [AVCaptureVideoPreviewLayer class];
}

- (AVCaptureSession *)session
{
	return [(AVCaptureVideoPreviewLayer *)[self layer] session];
}

- (void)setSession:(AVCaptureSession *)session
{
	[(AVCaptureVideoPreviewLayer *)[self layer] setSession:session];
}

- (void) touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    UITouch *touch = [[event allTouches] anyObject];
    CGPoint touchPoint = [touch locationInView:touch.view];
    //[self focus:touchPoint];

    if ([[touch view] isKindOfClass:[PreviewView class]])
    {
        //focusPOI = touchPoint;
        [[NSNotificationCenter defaultCenter]
            postNotificationName:@"UIApplicationDidRefocusEvent"
         object:self];
        camFocus = [[CameraFocusSquare alloc]initWithFrame:CGRectMake(touchPoint.x-40, touchPoint.y-40, 80, 80)];
        [camFocus.layer setCornerRadius:20.0];

        [camFocus setBackgroundColor:[UIColor clearColor]];
        [self addSubview:camFocus];
        [camFocus setNeedsDisplay];
        
        [UIView beginAnimations:nil context:NULL];
        [UIView setAnimationDuration:1.5];
        [camFocus setAlpha:0.0];
        [UIView commitAnimations];
    }
}

//- (void) focus:(CGPoint) aPoint;
//{
//    Class captureDeviceClass = NSClassFromString(@"AVCaptureDevice");
//    if (captureDeviceClass != nil) {
//        AVCaptureDevice *device = [captureDeviceClass defaultDeviceWithMediaType:AVMediaTypeVideo];
//        if([device isFocusPointOfInterestSupported] &&
//           [device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
//            CGRect screenRect = [[UIScreen mainScreen] bounds];
//            double screenWidth = screenRect.size.width;
//            double screenHeight = screenRect.size.height;
//            double focus_x = aPoint.x/screenWidth;
//            double focus_y = aPoint.y/screenHeight;
//            if([device lockForConfiguration:nil]) {
//                [device setFocusPointOfInterest:CGPointMake(focus_x,focus_y)];
//                [device setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
//                if ([device isExposureModeSupported:AVCaptureExposureModeAutoExpose]){
//                    [device setExposureMode:AVCaptureExposureModeAutoExpose];
//                }
//                [device unlockForConfiguration];
//            }
//        }
//    }
//}

@end
