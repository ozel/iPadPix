//
//  CameraViewController.h
//  iPadPix
//
//  Copyright (c) 2016 Oliver Keller. All rights reserved.
//

@import UIKit;
@import SpriteKit;
#import "TPXClusterView.h"
#import "TPXFrameBufferLayer.h"


@interface CameraViewController : UIViewController

- (SKScene *)unarchiveFromFile:(NSString *)file;

+ (NSURL*)applicationDataDirectory;


@property (nonatomic) CGRect focusPointer;
@property (nonatomic) TPXFrameBufferLayer * fBuffer;
@property (nonatomic) NSMutableArray * fbArray;
@property (nonatomic) UIImageView * overlayImageView;
@property (nonatomic, strong) NSMutableArray *counter_fifos;


@end
