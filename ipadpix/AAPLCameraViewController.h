/*
 Copyright (C) 2014 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 
  Control of camera functions.
  
*/

@import UIKit;
#import "TPXFrameBufferLayer.h"
#import <SpriteKit/SpriteKit.h>
#import "TPXClusterView.h"



CGPoint focusPOI;
UIView * fPview;
SKView * skView;
TPXClusterScene * scene;
CALayer * fpFrame;
BOOL demo_mode;
BOOL record_mode;

@interface AAPLCameraViewController : UIViewController

- (SKScene *)unarchiveFromFile:(NSString *)file;

+ (NSURL*)applicationDataDirectory;


@property (nonatomic) CGRect focusPointer;
@property (nonatomic) TPXFrameBufferLayer * fBuffer;
@property (nonatomic) NSMutableArray * fbArray;
@property (nonatomic) UIImageView * overlayImageView;



@end
