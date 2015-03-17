/*
 Copyright (C) 2014 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 
  Control of camera functions.
  
 */

#import "AAPLCameraViewController.h"

#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <SpriteKit/SpriteKit.h>
#import "AAPLPreviewView.h"

#import "GCDAsyncUdpSocket.h"
#import "DDLog.h"
#import "DDTTYLogger.h"
#import "TPXFrameBufferLayer.h"
#import "TPXClusterView.h"
#import "MotionManagerSingleton.h"

#import <ObjectiveAvro/OAVAvroSerialization.h>



static void *CapturingStillImageContext = &CapturingStillImageContext;
static void *RecordingContext = &RecordingContext;
static void *SessionRunningAndDeviceAuthorizedContext = &SessionRunningAndDeviceAuthorizedContext;

static void *FocusModeContext = &FocusModeContext;
static void *LensPositionContext = &LensPositionContext;


@interface AAPLCameraViewController () <AVCaptureFileOutputRecordingDelegate>{
    GCDAsyncUdpSocket *asyncSocket;
}

@property (nonatomic, weak) IBOutlet AAPLPreviewView *previewView;
@property (nonatomic, weak) IBOutlet UIButton *stillButton;

@property (nonatomic, strong) NSArray *focusModes;
@property (nonatomic, weak) IBOutlet UIView *manualHUDFocusView;
@property (nonatomic, weak) IBOutlet UISegmentedControl *focusModeControl;
@property (nonatomic, weak) IBOutlet UISlider *lensPositionSlider;
@property (nonatomic, weak) IBOutlet UILabel *lensPositionNameLabel;
@property (nonatomic, weak) IBOutlet UILabel *lensPositionValueLabel;

@property (nonatomic, strong) NSArray *exposureModes;

@property (nonatomic) dispatch_queue_t sessionQueue; // Communicate with the session and other session objects on this queue.
@property (nonatomic) AVCaptureSession *session;
@property (nonatomic) AVCaptureDeviceInput *videoDeviceInput;
@property (nonatomic) AVCaptureDevice *videoDevice;

@property (nonatomic) UIBackgroundTaskIdentifier backgroundRecordingID;
@property (nonatomic, getter = isDeviceAuthorized) BOOL deviceAuthorized;
@property (nonatomic, readonly, getter = isSessionRunningAndDeviceAuthorized) BOOL sessionRunningAndDeviceAuthorized;
@property (nonatomic) BOOL lockInterfaceRotation;
@property (nonatomic) id runtimeErrorHandlingObserver;

@end

@implementation AAPLCameraViewController

static UIColor* CONTROL_NORMAL_COLOR = nil;
static UIColor* CONTROL_HIGHLIGHT_COLOR = nil;

NSTimer *focusTimer = nil;
NSTimer *demoTimer = nil;
dispatch_queue_t networkQueue;
CGPoint defaultFocusPOI;

//cps display
SKLabelNode *alpha_ctr, *beta_ctr, *gamma_ctr, *unknown_ctr;
NSUInteger alpha_cnt, beta_cnt,gamma_cnt, unknown_cnt;
float alpha_cps, beta_cps, gamma_cps, unknown_cps;


@synthesize focusPointer;
@synthesize fBuffer;
@synthesize overlayImageView;
@synthesize fbArray;

+ (id)JSONObjectFromBundleResource:(NSString *)resource {
    NSString *path = [[NSBundle bundleForClass:self] pathForResource:resource ofType:@"json"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return dict;
}

+ (id)stringFromBundleResource:(NSString *)resource {
    NSString *path = [[NSBundle bundleForClass:self] pathForResource:resource ofType:@"json"];
    return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
}

- (void)registerSchemas:(OAVAvroSerialization *)avro {
    NSString *tpxFrame = [[self class] stringFromBundleResource:@"tpx_schema"];
    [avro registerSchema:tpxFrame error:NULL];
}

+ (void)initialize
{
	CONTROL_NORMAL_COLOR = [UIColor yellowColor];
	CONTROL_HIGHLIGHT_COLOR = [UIColor colorWithRed:0.0 green:122.0/255.0 blue:1.0 alpha:1.0]; // A nice blue
}

+ (NSSet *)keyPathsForValuesAffectingSessionRunningAndDeviceAuthorized
{
	return [NSSet setWithObjects:@"session.running", @"deviceAuthorized", nil];
}

- (BOOL)isSessionRunningAndDeviceAuthorized
{
	return [[self session] isRunning] && [self isDeviceAuthorized];
}

- (SKScene *)unarchiveFromFile:(NSString *)file {
    /* Retrieve scene file path from the application bundle */
    NSString *nodePath = [[NSBundle mainBundle] pathForResource:file ofType:@"sks"];
    /* Unarchive the file to an SKScene object */
    NSData *data = [NSData dataWithContentsOfFile:nodePath
                                          options:NSDataReadingMappedIfSafe
                                            error:nil];
    NSKeyedUnarchiver *arch = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
    [arch setClass:[SKScene class] forClassName:@"SKScene"];
    SKScene *scene = [arch decodeObjectForKey:NSKeyedArchiveRootObjectKey];
    [arch finishDecoding];
    
    return scene;
}

- (void)viewDidLoad
{
	[super viewDidLoad];
    
    // Setup our logging framework.
    
    [DDLog addLogger:[DDTTYLogger sharedInstance]];
    
//	self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	
	// Create the AVCaptureSession
	AVCaptureSession *session = [[AVCaptureSession alloc] init];
	[self setSession:session];
	
	// Set up preview
	[[self previewView] setSession:session];
	
	// Check for device authorization
	[self checkDeviceAuthorizationStatus];
	
	// In general it is not safe to mutate an AVCaptureSession or any of its inputs, outputs, or connections from multiple threads at the same time.
	// Why not do all of this on the main queue?
	// -[AVCaptureSession startRunning] is a blocking call which can take a long time. We dispatch session setup to the sessionQueue so that the main queue isn't blocked (which keeps the UI responsive).
	
	dispatch_queue_t sessionQueue = dispatch_queue_create("session queue", DISPATCH_QUEUE_SERIAL);
	[self setSessionQueue:sessionQueue];
	
	dispatch_async(sessionQueue, ^{
		[self setBackgroundRecordingID:UIBackgroundTaskInvalid];
		
		NSError *error = nil;
		
        if(!TARGET_IPHONE_SIMULATOR){
            
            AVCaptureDevice *videoDevice = [AAPLCameraViewController deviceWithMediaType:AVMediaTypeVideo preferringPosition:AVCaptureDevicePositionBack];
            AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
            
            if (error)
            {
                NSLog(@"%@", error);
            }
            
            [[self session] beginConfiguration];
            
            if ([session canAddInput:videoDeviceInput])
            {
                [session addInput:videoDeviceInput];
                [self setVideoDeviceInput:videoDeviceInput];
                [self setVideoDevice:videoDeviceInput.device];
                
                [session setSessionPreset:AVCaptureSessionPresetPhoto];

                dispatch_async(dispatch_get_main_queue(), ^{
                    // Why are we dispatching this to the main queue?
                    // Because AVCaptureVideoPreviewLayer is the backing layer for our preview view and UIView can only be manipulated on main thread.
                    // Note: As an exception to the above rule, it is not necessary to serialize video orientation changes on the AVCaptureVideoPreviewLayer’s connection with other session manipulation.

                    [[(AVCaptureVideoPreviewLayer *)[[self previewView] layer] connection] setVideoOrientation:AVCaptureVideoOrientationLandscapeRight];
                });
            }
            
            [self setLockInterfaceRotation:YES];
            
            if (error)
            {
                NSLog(@"%@", error);
            }
            

            [[self session] commitConfiguration];
            
            NSLog(@"%@", [[self session] sessionPreset]);
            
        }
		
        
        //configure video display size and exposure mode
        
        
        if (!TARGET_IPHONE_SIMULATOR && [self.videoDevice lockForConfiguration:&error]) {
            [self.videoDevice setFocusPointOfInterest:defaultFocusPOI];
            //[self.videoDevice videoZoomFactor:2.0];
            if ([self.videoDevice respondsToSelector:@selector(setVideoZoomFactor:)]) {
                //float zoomFactor = self.videoDevice.activeFormat.videoZoomFactorUpscaleThreshold;
                //[self.videoDevice setVideoZoomFactor:zoomFactor];
                //[self.videoDevice setVideoZoomFactor:2.0];
            }
//            [(AVCaptureVideoPreviewLayer *)[[self previewView] layer] setVideoGravity:AVLayerVideoGravityResizeAspectFill];
            [(AVCaptureVideoPreviewLayer *)[[self previewView] layer] setVideoGravity:AVLayerVideoGravityResizeAspect];
            [self.videoDevice setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
            [self.videoDevice setWhiteBalanceMode:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance];
            
            [self.videoDevice unlockForConfiguration];
        }
        else
        {
            NSLog(@"simulator mode or error: %@", error);
        }
        
  		
//        dispatch_async(dispatch_get_main_queue(), ^{
			[self configureManualHUD];

            // translate, then scale, then rotate
            //CGAffineTransform affineTransform = CGAffineTransformMakeTranslation(-(self.previewView.layer.bounds.size.width/4.0), 0.0);
            //-680 shows righte edge in middle of screen = 8cm
            //-300 = 2 cm shift
        
//            CGAffineTransform affineTransform = CGAffineTransformMakeTranslation(0, 0.0);

        CGAffineTransform affineZoom = CGAffineTransformMakeScale(2.5,2.5);
        CGAffineTransform affineTransform = CGAffineTransformTranslate(affineZoom,-256, 0.0);
        
//            affineTransform = CGAffineTransformScale(affineTransform, 1.0, 1.0);
//            affineTransform = CGAffineTransformRotate(affineTransform, 0.0);
//            [CATransaction begin];
//            [CATransaction setAnimationDuration:.025];
            [(AVCaptureVideoPreviewLayer *)[[self previewView] layer] setAffineTransform:affineTransform];
//            [CATransaction commit];
        
            //            [[overlayImageView layer] setOpacity:1.0];
            //            [fBuffer setOpacity:1.0];

//		});

	});
	
	self.manualHUDFocusView.hidden = YES;
    
    // setup and bind UDP server socket to port
  
    // Create High Priotity queue
    networkQueue = dispatch_queue_create("networkQueue", NULL);
    dispatch_queue_t high = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
    
    dispatch_set_target_queue(networkQueue, high);
    
    demo_mode = false;
    record_mode = false;
   
    // Create UDP Socket
    asyncSocket = [[GCDAsyncUdpSocket alloc] initWithDelegate:self delegateQueue:networkQueue];
//    asyncSocket = [[GCDAsyncUdpSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
    [asyncSocket setPreferIPv4];

    NSError *error = nil;
    if (![asyncSocket bindToPort:8123 error:&error])
    {
        NSLog(@"Error starting server (bind): %@", error);
        exit(1);
    }
    if (![asyncSocket beginReceiving:&error])
    {
        [asyncSocket close];
        NSLog(@"Error starting server (recv): %@", error);
        exit(1);
    }
    NSLog(@"Udp server started on port %hu", [asyncSocket localPort]);
//    demoTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
//                                     target:self
//                                   selector:@selector(handleDemoTimer:)
//                                   userInfo:nil
//                                    repeats:NO];

    //set this to start overriding clusters from nr. 0
//    [[NSUserDefaults standardUserDefaults] setValue:@(0) forKey:@"demo_cluster_count"];

}


- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
    if(!TARGET_IPHONE_SIMULATOR){
        dispatch_async([self sessionQueue], ^{
            [self addObservers];
            [[self session] startRunning];
        });
    }
    
    CGRect screenRect = [[UIScreen mainScreen] bounds];
    double screenWidth = screenRect.size.width;
    double screenHeight = screenRect.size.height;
    focusPOI.x = screenWidth/2.0;
    focusPOI.y = screenHeight/2.0;
    
    defaultFocusPOI = CGPointMake(.5, .5);

    //focuspointer is used for the initial fpView frame size and equals timepix frame size
    focusPointer = CGRectMake(0.0, 0.0, 255, 255);

    //    fPview = [[UIView alloc] initWithFrame:focusPointer];
    CGRect r = focusPointer;
    r.origin = self.view.bounds.origin;
    r.origin.x = focusPOI.x - (r.size.width/2.0);
    r.origin.y = focusPOI.y - (r.size.height/2.0);
//    fPview.frame = CGRectIntegral(r);
    
    fpFrame = [[CALayer alloc] init];
    fpFrame.frame = CGRectIntegral(r);
    

    
    //        overlayImageView = [[UIImageView alloc] initWithFrame:self.view.frame];
//    overlayImageView = [[UIImageView alloc] initWithFrame:focusPointer];
//    overlayImageView.frame = CGRectIntegral(r);

    r.origin = defaultFocusPOI;
    focusPointer = r;
    
    //old full-frame buffer
//    fBuffer = [TPXFrameBufferLayer createLayerWithFrame:focusPointer Index:999];
//    fBuffer.contentsScale = [[UIScreen mainScreen] scale]*2;
    
    //new cluster frame buffer array
    fbArray = [NSMutableArray initTPXFrameBuffersWithParentLayer:overlayImageView.layer];
    
    
    //fPview.backgroundColor = UIColor.redColor; //
    fpFrame.backgroundColor = [UIColor clearColor].CGColor; //
    
    //the layer border wll be above the content, therefore the workaround below
//    [fPview.layer setBorderWidth:2.0];
//    [fPview.layer setCornerRadius:0.0];
    CAShapeLayer * _border = [CAShapeLayer layer];
    _border.strokeColor = [UIColor colorWithRed:255/255.0f green:255/255.0f blue:119/255.0f alpha:0.5f].CGColor;

    _border.fillColor = nil;

    [fpFrame addSublayer:_border];
    _border.path = [UIBezierPath bezierPathWithRoundedRect:fpFrame.bounds cornerRadius:0.f].CGPath;
    
    [fpFrame setBorderColor:[UIColor yellowColor].CGColor];
    
    
    [fpFrame setOpacity:1];
//    [fPview setAutoresizesSubviews:YES];
//    [fPview setAutoresizingMask: UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight];


    
    [[self view].layer addSublayer:fpFrame];
//    [overlayImageView.layer addSublayer:fBuffer];
    
//    [overlayImageView.layer setBackgroundColor:[UIColor redColor].CGColor];
    
    // Configure the sprite kit view
    skView = [[SKView alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    
//    [skView addSubview:overlayImageView];

//    skView = [[SKView alloc] initWithFrame:self.view.bounds];
//      skView = [[SKView alloc] initWithFrame:focusPointer];
    

//    [skView setFrame:({
//        CGRect frame = skView.frame;
//        
//        frame.origin.x = ([[UIScreen mainScreen] bounds].size.width - frame.size.width) / 2.0;
//        frame.origin.y = ([[UIScreen mainScreen] bounds].size.height - frame.size.height) / 2.0;
//        
//        CGRectIntegral(frame);
//    })];
//    
    /* Sprite Kit applies additional optimizations to improve rendering performance */
    skView.ignoresSiblingOrder = YES;
    
    // Create and configure the scene.
//                scene = [self unarchiveFromFile:@"GameScene"];
//    scene = [[SKScene alloc] initWithSize:[[UIScreen mainScreen] bounds].size];
    scene = [[TPXClusterScene alloc] initWithSize:skView.bounds.size];

    scene.anchorPoint = CGPointMake(0.5, 0.5);

//    skView.layer.contentsScale = [[UIScreen mainScreen] scale];

    if (!scene)
        NSLog(@"no scene loaded");
//    scene.scaleMode = SKSceneScaleModeAspectFill;
//    scene.scaleMode = SKSceneScaleModeResizeFill;
    
 
//    SKLabelNode *myLabel = [SKLabelNode labelNodeWithFontNamed:@"Courier"];
//    
//    myLabel.text=@"+";
//    myLabel.fontSize = 50;
////    myLabel.position = CGPointMake(CGRectGetMidX(self.view.bounds),
////                                   CGRectGetMidY(self.view.bounds));
//    myLabel.position = CGPointMake(0,0);
//          [scene addChild:myLabel];
    
    skView.allowsTransparency = YES;
    scene.backgroundColor = [UIColor clearColor];
//    scene.backgroundColor = [UIColor blackColor];
    
    // clusterField is the parent node of all clusters, the "world" node
    ClusterFieldNode * clusterField = [[ClusterFieldNode alloc] initWithSize:[[UIScreen mainScreen] bounds].size];
    clusterField.name = @"clusterField";
    scene.clusters = clusterField;
    [scene addChild:scene.clusters];
    [scene addLabelContainer];
    
    //alpha, beta, gamma counters
    SKLabelNode * cps_label = [SKLabelNode labelNodeWithFontNamed:@"Menlo-Regular"];
    cps_label.verticalAlignmentMode = SKLabelVerticalAlignmentModeBaseline;
    cps_label.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeLeft;
    cps_label.text = [NSString stringWithFormat:@"cps: "];
    cps_label.fontColor = [UIColor yellowColor];
    cps_label.fontSize = 23;
    cps_label.zPosition = 1;
    cps_label.position = CGPointMake(-250, (-[[UIScreen mainScreen] bounds].size.height/2)+6);
    [scene addChild:cps_label];
    
    
    alpha_ctr = [SKLabelNode labelNodeWithFontNamed:@"Menlo-Regular"];
    alpha_ctr.verticalAlignmentMode = SKLabelVerticalAlignmentModeBaseline;
    alpha_ctr.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeLeft;
    alpha_ctr.text = [NSString stringWithFormat:@"\u03B1 %.1f", alpha_cps]; //@"\u03B1 0 cps";
    alpha_ctr.fontColor = [UIColor yellowColor];
    alpha_ctr.fontSize = 23;
    alpha_ctr.zPosition = 1;
    alpha_ctr.position = CGPointMake(80, 0);
    [cps_label addChild:alpha_ctr];
    beta_ctr = [SKLabelNode labelNodeWithFontNamed:@"Menlo-Regular"];
    beta_ctr.verticalAlignmentMode = SKLabelVerticalAlignmentModeBaseline;
    beta_ctr.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeLeft;
    beta_ctr.text = [NSString stringWithFormat:@"\u03B2 %.1f", beta_cps];
    beta_ctr.fontColor = [UIColor yellowColor];
    beta_ctr.fontSize = 23;
    beta_ctr.zPosition = 1;
    beta_ctr.position = CGPointMake(180, 0);
    [cps_label addChild:beta_ctr];
    gamma_ctr = [SKLabelNode labelNodeWithFontNamed:@"Menlo-Regular"];
    gamma_ctr.verticalAlignmentMode = SKLabelVerticalAlignmentModeBaseline;
    gamma_ctr.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeLeft;
    gamma_ctr.text = [NSString stringWithFormat:@"\u03B3 %.1f", gamma_cps];
    gamma_ctr.fontColor = [UIColor yellowColor];
    gamma_ctr.fontSize = 23;
    gamma_ctr.zPosition = 1;
    gamma_ctr.position = CGPointMake(280, 0);
    [cps_label addChild:gamma_ctr];
    unknown_ctr = [SKLabelNode labelNodeWithFontNamed:@"Menlo-Regular"];
    unknown_ctr.verticalAlignmentMode = SKLabelVerticalAlignmentModeBaseline;
    unknown_ctr.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeLeft;
    unknown_ctr.text = [NSString stringWithFormat:@"? %.1f", unknown_cps];
    unknown_ctr.fontColor = [UIColor yellowColor];
    unknown_ctr.fontSize = 23;
    unknown_ctr.zPosition = 1;
    unknown_ctr.position = CGPointMake(380, 0);
    [cps_label addChild:unknown_ctr];

    NSTimer *cpsTimer = [NSTimer scheduledTimerWithTimeInterval:1
                                                 target:self
                                               selector:@selector(handleCpsTimer:)
                                               userInfo:nil
                                                        repeats:YES];
    
    
//    SKNode *camera = [SKNode node];
//    camera.name = @"camera";
//    [clusterField addChild:camera];
    
    [[self view] addSubview:skView];
    [skView presentScene:scene];
//    [self.manualHUDFocusView removeFromSuperview];
//    [skView addSubview:self.manualHUDFocusView];
    
    // Create and initialize a tap gesture
    UIPanGestureRecognizer *panRecognizer = [[UIPanGestureRecognizer alloc]
                                             initWithTarget:self action:@selector(respondToPanGesture:)];
    
    // Specify that the gesture must be a single tap
    panRecognizer.maximumNumberOfTouches = 1;
    
    // Add the tap gesture recognizer to the view
    [skView addGestureRecognizer:panRecognizer];
    
    UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget:    self action:@selector(respondToSingleTap:)];
    singleTap.numberOfTapsRequired = 1;
    [skView addGestureRecognizer:singleTap];
    
    UITapGestureRecognizer *twoTap = [[UITapGestureRecognizer alloc] initWithTarget:   self action:@selector(respondToTwoTap:)];
    twoTap.numberOfTapsRequired = 1;
    twoTap.numberOfTouchesRequired = 2;
    [skView addGestureRecognizer:twoTap];
    
    UITapGestureRecognizer *fiveTap = [[UITapGestureRecognizer alloc] initWithTarget:   self action:@selector(respondToFiveTap:)];
    fiveTap.numberOfTapsRequired = 1;
    fiveTap.numberOfTouchesRequired = 4;
    [skView addGestureRecognizer:fiveTap];
    
    [singleTap requireGestureRecognizerToFail:twoTap];
    [singleTap requireGestureRecognizerToFail:fiveTap];
    
    [twoTap requireGestureRecognizerToFail:fiveTap];

    
}

- (void)respondToSingleTap:(UIPanGestureRecognizer *)recognizer {
     if (recognizer.state == UIGestureRecognizerStateEnded){
        //toggle between stop and play
        if (scene.speed > 0)
            scene.speed=0;
        else if (scene.speed < 1)
            scene.speed=1;
     }
    
}

- (void)respondToTwoTap:(UIPanGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateEnded){
        //toggle between demo on and off
        if (demo_mode){
            [demoTimer invalidate];
            demoTimer = nil;
            demo_mode = false;
            
            skView.showsFPS = NO;
            skView.showsNodeCount = NO;
        }
        else {
            demoTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                         target:self
                                                       selector:@selector(handleDemoTimer:)
                                                       userInfo:nil
                                                        repeats:NO];
            demo_mode = true;
            
            skView.showsFPS = YES;
            skView.showsNodeCount = YES;

        }
    }
}

- (void)respondToFiveTap:(UIPanGestureRecognizer *)recognizer {
    
    if (recognizer.state == UIGestureRecognizerStateEnded){
        dispatch_async(dispatch_get_main_queue(), ^{
            record_mode = !record_mode;
            if(record_mode){
                NSLog(@"-------- Clusters are now recorded.");
                [fpFrame setBorderColor:[UIColor redColor].CGColor];

            } else {
                NSLog(@"-------- Stopped recording of clusters.");
                [fpFrame setBorderColor:[UIColor yellowColor].CGColor];
            }
        });
    }
}


- (IBAction)respondToPanGesture:(UIPanGestureRecognizer *)recognizer {
    
//    dispatch_async(dispatch_get_main_queue(), ^{
    
//        CGPoint distance = [recognizer translationInView:scene.view];
//        
//        CGPoint location = [recognizer locationInView:scene.view];
//
//        SKShapeNode *line = [SKShapeNode node];
//        CGMutablePathRef pathToDraw = CGPathCreateMutable();
//        CGPathMoveToPoint(pathToDraw, NULL, location.x, location.y);
//        CGPathAddLineToPoint(pathToDraw, NULL, location.x, distance.y);
//        line.path = pathToDraw;
//
//        [line setStrokeColor:[UIColor redColor]];
//        SKAction * fade = [SKAction fadeOutWithDuration:1];
//        SKAction * remove = [SKAction  runBlock:^{
//            [line removeAllChildren];
//            [line removeFromParent];
//            }];
//        SKAction * sequence = [SKAction sequence:@[fade,remove]];
//
//        [scene addChild:line];
//        [line runAction:sequence];
//        CGPathRelease(pathToDraw);
//
//        float speed = -distance.y/200;
//        
//        if (speed > 1)
//            scene.speed=1;
//        else if (speed < 0)
//            scene.speed=0;
//        else
//            scene.speed = speed;

//    });

}

- (void)viewDidDisappear:(BOOL)animated
{
	dispatch_async([self sessionQueue], ^{
        if(!TARGET_IPHONE_SIMULATOR){
            [[self session] stopRunning];
        }
		[self removeObservers];
	});
	
	[super viewDidDisappear:animated];
}

- (BOOL)prefersStatusBarHidden
{
	return YES;
}

- (BOOL)shouldAutorotate
{
	// Disable autorotation of the interface when recording is in progress.
	return ![self lockInterfaceRotation];
}

- (NSUInteger)supportedInterfaceOrientations
{
	return UIInterfaceOrientationMaskLandscapeRight;
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    /* not needed anymore, since orientation is fixed now.
     left here for reference */
	[[(AVCaptureVideoPreviewLayer *)[[self previewView] layer] connection] setVideoOrientation:(AVCaptureVideoOrientation)toInterfaceOrientation];
    

    dispatch_async(dispatch_get_main_queue(), ^{

    
    CGRect r = focusPointer;
    r.origin = self.view.bounds.origin;
    CGRect screenRect = [[UIScreen mainScreen] bounds];
    double screenWidth = screenRect.size.width;
    double screenHeight = screenRect.size.height;
    focusPOI.x = screenWidth/2.0;
    focusPOI.y = screenHeight/2.0;
    r.origin.x = focusPOI.x - (r.size.width/2);
    r.origin.y = focusPOI.y - (r.size.height/2);
    fpFrame.frame = CGRectIntegral(r);
    });
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
	[self positionManualHUD];
}

#pragma mark Actions


- (IBAction)focusAndExposeTap:(UIGestureRecognizer *)gestureRecognizer
{
	if (self.videoDevice.focusMode != AVCaptureFocusModeLocked && self.videoDevice.exposureMode != AVCaptureExposureModeCustom)
	{
//		CGPoint focusPOI = [(AVCaptureVideoPreviewLayer *)[[self previewView] layer] captureDevicePointOfInterestForPoint:[gestureRecognizer locationInView:[gestureRecognizer view]]];
//        [self focusWithMode:AVCaptureFocusModeContinuousAutoFocus exposeWithMode:AVCaptureExposureModeContinuousAutoExposure atDevicePoint:focusPOI monitorSubjectAreaChange:YES]; //REM
    }
}

- (IBAction)changeManualHUD:(id)sender
{
	UISegmentedControl *control = sender;
	
	[self positionManualHUD];
	
	self.manualHUDFocusView.hidden = (control.selectedSegmentIndex == 1) ? NO : YES;
}

- (IBAction)changeFocusMode:(id)sender
{
	UISegmentedControl *control = sender;
	AVCaptureFocusMode mode = (AVCaptureFocusMode)[self.focusModes[control.selectedSegmentIndex] intValue];
	NSError *error = nil;
	
	if ([self.videoDevice lockForConfiguration:&error])
	{
		if ([self.videoDevice isFocusModeSupported:mode])
		{
			self.videoDevice.focusMode = mode;
		}
		else
		{
			NSLog(@"Focus mode %@ is not supported. Focus mode is %@.", [self stringFromFocusMode:mode], [self stringFromFocusMode:self.videoDevice.focusMode]);
			self.focusModeControl.selectedSegmentIndex = [self.focusModes indexOfObject:@(self.videoDevice.focusMode)];
		}
	}
	else
	{
		NSLog(@"%@", error);
	}
}

- (IBAction)changeLensPosition:(id)sender
{
	UISlider *control = sender;
	NSError *error = nil;
	
	if ([self.videoDevice lockForConfiguration:&error])
	{
		[self.videoDevice setFocusModeLockedWithLensPosition:control.value completionHandler:nil];
	}
	else
	{
		NSLog(@"%@", error);
	}
}


- (IBAction)sliderTouchBegan:(id)sender
{
	UISlider *slider = (UISlider*)sender;
	[self setSlider:slider highlightColor:CONTROL_HIGHLIGHT_COLOR];
}

- (IBAction)sliderTouchEnded:(id)sender
{
	UISlider *slider = (UISlider*)sender;
	[self setSlider:slider highlightColor:CONTROL_NORMAL_COLOR];
}

#pragma mark UI

- (void)configureManualHUD
{
	// Manual focus controls
	self.focusModes = @[@(AVCaptureFocusModeContinuousAutoFocus), @(AVCaptureFocusModeLocked)];
	
	self.focusModeControl.selectedSegmentIndex = [self.focusModes indexOfObject:@(self.videoDevice.focusMode)];
	for (NSNumber *mode in self.focusModes) {
		[self.focusModeControl setEnabled:([self.videoDevice isFocusModeSupported:[mode intValue]]) forSegmentAtIndex:[self.focusModes indexOfObject:mode]];
	}
	
	self.lensPositionSlider.minimumValue = 0.0;
	self.lensPositionSlider.maximumValue = 1.0;
	self.lensPositionSlider.enabled = (self.videoDevice.focusMode == AVCaptureFocusModeLocked);
	
}

- (void)positionManualHUD
{
	// Since we only show one manual view at a time, put them all in the same place (at the top)
//	self.manualHUDExposureView.frame = CGRectMake(self.manualHUDFocusView.frame.origin.x, self.manualHUDFocusView.frame.origin.y, self.manualHUDExposureView.frame.size.width, self.manualHUDExposureView.frame.size.height);
}

- (void)setSlider:(UISlider*)slider highlightColor:(UIColor*)color
{
	slider.tintColor = color;
	
	if (slider == self.lensPositionSlider)
	{
		self.lensPositionNameLabel.textColor = self.lensPositionValueLabel.textColor = slider.tintColor;
	}
}

#pragma mark File Output Delegate

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)error
{
    if (error)
    {
        NSLog(@"%@", error);
    }
    
    /* do nothing */

}

#pragma mark Device Configuration

- (void)focusWithMode:(AVCaptureFocusMode)focusMode exposeWithMode:(AVCaptureExposureMode)exposureMode atDevicePoint:(CGPoint)point monitorSubjectAreaChange:(BOOL)monitorSubjectAreaChange
{
	dispatch_async([self sessionQueue], ^{
        if(!TARGET_IPHONE_SIMULATOR){
            AVCaptureDevice *device = [self videoDevice];
            NSError *error = nil;
            if ([device lockForConfiguration:&error])
            {
                if ([device isFocusPointOfInterestSupported] && [device isFocusModeSupported:focusMode])
                {
                    [device setFocusMode:focusMode];
                    [device setFocusPointOfInterest:point];
                }
                if ([device isExposurePointOfInterestSupported] && [device isExposureModeSupported:exposureMode])
                {
                    [device setExposureMode:exposureMode];
                    [device setExposurePointOfInterest:point];
                }
                if ([device respondsToSelector:@selector(isAutoFocusRangeRestrictionSupported)] && device.autoFocusRangeRestrictionSupported) {
                    // If we are on an iOS version that supports AutoFocusRangeRestriction and the device supports it
                    // Set the focus range to "near"
                    [device setAutoFocusRangeRestriction:AVCaptureAutoFocusRangeRestrictionNear];
                }
                [device setSubjectAreaChangeMonitoringEnabled:monitorSubjectAreaChange];
                [device unlockForConfiguration];
            }
            else
            {
                NSLog(@"%@", error);
            }
        }
	});
}


#pragma mark KVO

- (void)addObservers
{
	
	[self addObserver:self forKeyPath:@"videoDeviceInput.device.focusMode" options:(NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:FocusModeContext];
	[self addObserver:self forKeyPath:@"videoDeviceInput.device.lensPosition" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:LensPositionContext];
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(subjectAreaDidChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:[self videoDevice]];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleFPtimer:)
                                                 name:@"UIApplicationDidRefocusEvent" object:nil];
	
	__weak AAPLCameraViewController *weakSelf = self;
    if(!TARGET_IPHONE_SIMULATOR){
        [self setRuntimeErrorHandlingObserver:[[NSNotificationCenter defaultCenter] addObserverForName:AVCaptureSessionRuntimeErrorNotification object:[self session] queue:nil usingBlock:^(NSNotification *note) {
            AAPLCameraViewController *strongSelf = weakSelf;
            dispatch_async([strongSelf sessionQueue], ^{
                // Manually restart the session since it must have been stopped due to an error
                [[strongSelf session] startRunning];
            });
        }]];
    }
}

- (void)removeObservers
{
	[[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:[self videoDevice]];
	[[NSNotificationCenter defaultCenter] removeObserver:[self runtimeErrorHandlingObserver]];

	
	[self removeObserver:self forKeyPath:@"videoDevice.focusMode" context:FocusModeContext];
	[self removeObserver:self forKeyPath:@"videoDevice.lensPosition" context:LensPositionContext];

}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if (context == FocusModeContext)
	{
		AVCaptureFocusMode oldMode = [change[NSKeyValueChangeOldKey] intValue];
		AVCaptureFocusMode newMode = [change[NSKeyValueChangeNewKey] intValue];
		NSLog(@"focus mode: %@ -> %@", [self stringFromFocusMode:oldMode], [self stringFromFocusMode:newMode]);
		
		self.focusModeControl.selectedSegmentIndex = [self.focusModes indexOfObject:@(newMode)];
		self.lensPositionSlider.enabled = (newMode == AVCaptureFocusModeLocked);
	}
	else if (context == LensPositionContext)
	{
		float newLensPosition = [change[NSKeyValueChangeNewKey] floatValue];
		
		if (self.videoDevice.focusMode != AVCaptureFocusModeLocked)
		{
			self.lensPositionSlider.value = newLensPosition;
//            CGPoint onScreen;
//            CGRect screenRect = [[self.previewView layer] bounds];
//            double screenWidth = screenRect.size.width;
//            double screenHeight = screenRect.size.height;
//            onScreen.y = focusPOI.y * screenWidth;
//            onScreen.x = focusPOI.x * screenHeight;
            //if (!self.videoDevice.isAdjustingFocus){
              //  drawFP:;
            //} else {
                if(focusTimer == nil){
                    NSLog(@"start timer");
                    focusTimer = [NSTimer scheduledTimerWithTimeInterval:0.25
                                        target:self
                                        selector:@selector(handleFPtimer:)
                                        userInfo:nil
                                        repeats:NO];
                }
            //}
            //NSLog(@"focusPOI: %@", NSStringFromCGPoint(focusPOI));

		}
		self.lensPositionValueLabel.text = [NSString stringWithFormat:@"%.1f", newLensPosition];
	}
	else if (context == SessionRunningAndDeviceAuthorizedContext)
	{
		BOOL isRunning = [change[NSKeyValueChangeNewKey] boolValue];
		
		dispatch_async(dispatch_get_main_queue(), ^{
			if (isRunning)
			{
				[[self stillButton] setEnabled:YES];
			}
			else
			{
				[[self stillButton] setEnabled:NO];
			}
		});
	}
	else
	{
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

- (void)subjectAreaDidChange:(NSNotification *)notification
{
	//CGPoint focusPOI = CGPointMake(.5, .5);
    
//    float focus_shift = .8*(1-(self.lensPositionSlider.value*1.275));
    //-(256+(102*(1-lensPosition)))
    float focus_shift = (256+(102*(1-self.lensPositionSlider.value)))*0.5/512;
    
    if (focus_shift > 1.0) focus_shift = 1.0;
    
    CGPoint focusPOI = CGPointMake(0.9, .5);
    
	[self focusWithMode:AVCaptureFocusModeContinuousAutoFocus exposeWithMode:AVCaptureExposureModeContinuousAutoExposure atDevicePoint:focusPOI monitorSubjectAreaChange:YES];
    
//    dispatch_async(dispatch_get_main_queue(), ^{
//        [[[self previewView] layer] setOpacity:0.0];
//        [UIView animateWithDuration:.25 animations:^{
//            [[[self previewView] layer] setOpacity:1.0];
//        }];
//    });

    NSLog(@"subjectAreaDidChange");
}


- (void)hideLabel:(UILabel *)label {
    [label setHidden:YES];
}


#pragma mark Utilities

+ (AVCaptureDevice *)deviceWithMediaType:(NSString *)mediaType preferringPosition:(AVCaptureDevicePosition)position
{
	NSArray *devices = [AVCaptureDevice devicesWithMediaType:mediaType];
	AVCaptureDevice *captureDevice = [devices firstObject];
	
	for (AVCaptureDevice *device in devices)
	{
		if ([device position] == position)
		{
			captureDevice = device;
			break;
		}
	}
	
	return captureDevice;
}

- (void)checkDeviceAuthorizationStatus
{
	NSString *mediaType = AVMediaTypeVideo;
	
	[AVCaptureDevice requestAccessForMediaType:mediaType completionHandler:^(BOOL granted) {
		if (granted)
		{
			[self setDeviceAuthorized:YES];
		}
		else
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				[[[UIAlertView alloc] initWithTitle:@"AVCamManual"
											message:@"AVCamManual doesn't have permission to use the Camera"
										   delegate:self
								  cancelButtonTitle:@"OK"
								  otherButtonTitles:nil] show];
				[self setDeviceAuthorized:NO];
			});
		}
	}];
}

- (NSString *)stringFromFocusMode:(AVCaptureFocusMode) focusMode
{
	NSString *string = @"INVALID FOCUS MODE";
	
	if (focusMode == AVCaptureFocusModeLocked)
	{
		string = @"Locked";
	}
	else if (focusMode == AVCaptureFocusModeAutoFocus)
	{
		string = @"Auto";
	}
	else if (focusMode == AVCaptureFocusModeContinuousAutoFocus)
	{
		string = @"ContinuousAuto";
	}
	
	return string;
}

- (void)handleFPtimer:(NSTimer *) timer {
    
    static int count;
    count++;
    
    [focusTimer invalidate];
    
    
//    NSLog(@"timer count: %i", count);
    

    float lensPosition = self.lensPositionSlider.value;

    
    // adjust things only if camera finished focusing on objects
    // else set timer to come back here
    if (!self.videoDevice.isAdjustingFocus){
        // re-calibrate core motion
        //[MotionManagerSingleton calibrate];
        NSLog(@"lensPosition: %f", lensPosition);

//        NSLog(@"focusPOI: %@", NSStringFromCGPoint(focusPOI));
        dispatch_async(dispatch_get_main_queue(), ^{
            
            //rescale focuspointer frame

            fpFrame.affineTransform = CGAffineTransformMakeScale((1-lensPosition)*3, (1-lensPosition)*3);
            
            //display some randomized frames
//            int rand = arc4random() % 10 +1;
//            NSString *imageName = [NSString stringWithFormat:@"%d_.png", rand];
//            overlayImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:imageName]];
//            [overlayImageView setFrame:CGRectMake(0, 0, 255, 255)];
//            rand = arc4random() % 4;
//            overlayImageView.transform = CGAffineTransformMakeRotation(1.57*rand);
            
//            r = overlayImageView.frame;
//            r.origin.x = focusPOI.x  - (256/2);
//            r.origin.y = focusPOI.y  - (256/2);
//            overlayImageView.frame = r;
            
//            NSLog(@"new overlayImageView width: %d, height: %d", (int)overlayImageView.frame.size.width, (int)overlayImageView.frame.size.height);


         
//            fBuffer.transform = CATransform3DMakeScale(3*(1-lensPosition), 3*(1-lensPosition), 1);

           
            dispatch_async(dispatch_get_main_queue(), ^{
//                fBuffer.opacity=0;
                CABasicAnimation* fadeAnimation = [CABasicAnimation animationWithKeyPath:@"opacity"];
                fadeAnimation.fromValue = @1.0;
                fadeAnimation.toValue = @0.5;
                fadeAnimation.fillMode = kCAFillModeForwards;
                fadeAnimation.removedOnCompletion = NO;

                CABasicAnimation* zoomAnimation = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
                zoomAnimation.fromValue = [NSValue valueWithCATransform3D:CATransform3DIdentity];
                zoomAnimation.toValue = [NSValue valueWithCATransform3D:CATransform3DMakeScale(3*(1-lensPosition)*3, 3*(1-lensPosition)*3, 1)];
                zoomAnimation.fillMode = kCAFillModeForwards;
                zoomAnimation.removedOnCompletion =NO;
                
//                zoomAnimation.fromValue = [NSNumber numberWithFloat:1.0f];
//                zoomAnimation.toValue = [NSNumber numberWithFloat:10.0f];
              
                CAAnimationGroup *group = [CAAnimationGroup animation];
                group.duration = 1.8;
                group.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
                group.animations = [NSArray arrayWithObjects:fadeAnimation, zoomAnimation, nil];
                group.delegate = self;
                [group setValue:@"groupFadeZoom" forKey:@"animationName"];
//                [group setValue:fBuffer forKey:@"parentLayer"];
       
                [fBuffer addAnimation:group forKey:@"groupFadeZoom"];
                
                //CGAffineTransform affineTransform = CGAffineTransformMakeTranslation(-(300*(1+(lensPosition*1.275		))), 0.0);

                CGAffineTransform affineZoom = CGAffineTransformMakeScale(2.5,2.5);
                CGAffineTransform affineTransform = CGAffineTransformTranslate(affineZoom,-(256+(102*(1-lensPosition))), 0.0);
//                CGAffineTransform affineTransform = CGAffineTransformTranslate(affineZoom,-(358*(1+(lensPosition*1.275		))), 0.0);
                
                
                
                //            affineTransform = CGAffineTransformScale(affineTransform, 1.0, 1.0);
                //            affineTransform = CGAffineTransformRotate(affineTransform, 0.0);
                            [CATransaction begin];
                            [CATransaction setAnimationDuration:0.5];
//                                [(AVCaptureVideoPreviewLayer *)[[self previewView] layer] setAffineTransform:affineZoom];
                                [(AVCaptureVideoPreviewLayer *)[[self previewView] layer] setAffineTransform:affineTransform];
                            [CATransaction commit];

                
                
                
//                NSLog(@"There are %d sublayers after adding fBuffer",[overlayImageView.layer.sublayers count]);
                

           });
            
//            r.size.height *= lensPosition * 50;
//            r.size.width *= lensPosition * 50;
            
            focusTimer= nil;
        });
    } else {
        NSLog(@"start timer again");
        focusTimer = [NSTimer scheduledTimerWithTimeInterval:0.25
                                                      target:self
                                                    selector:@selector(handleFPtimer:)
                                                    userInfo:nil
                                                     repeats:NO];
    }
}

- (void)animationDidStop:(CAAnimation *)animation finished:(BOOL)finished
{
         NSString *animationName = [animation valueForKey:@"animationName"];
        if ([animationName isEqualToString:@"groupFadeZoom"])
        {
//            [fBuffer clear];
//            NSLog(@"There were %i sublayers",[overlayImageView.layer.sublayers count]);
//            CALayer *layer = [animation valueForKey:@"parentLayer"];
//            [layer removeAllAnimations];
//            [layer removeFromSuperlayer];
//            NSLog(@"There are now %i sublayers",[overlayImageView.layer.sublayers count]);

        }
 }

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didReceiveData:(NSData *)data
      fromAddress:(NSData *)address
withFilterContext:(id)filterContext
{
    BOOL new_frame = false;
    
    OAVAvroSerialization *avro = [[OAVAvroSerialization alloc] init];
    NSError *error;
    [self registerSchemas:avro];

    // the json object returns the opriginal Avro bytes as UTF8 strings, this means numbers > 194 are stored in two bytes
    // and any zero bytes terminate the string early
    // TODO: enable of parsing xi and yi zero values, ei should be never zero
    NSDictionary *fromAvro = [avro JSONObjectFromData:data forSchemaNamed:@"tpxFrame" error:&error] ;
    if (!error) {
        [demoTimer invalidate];
        demoTimer = nil;
        skView.showsFPS = NO;
        skView.showsNodeCount = NO;
        if(record_mode){
            NSURL * prefix = [AAPLCameraViewController applicationDataDirectory];
//            prefix = [prefix URLByAppendingPathComponent:@"demo_clusters"];
            long int count = [[[NSUserDefaults standardUserDefaults] valueForKey:@"demo_cluster_count"] integerValue];
            count++;
            NSLog(@"-------- saving cluster nr. %li", count);
            NSString *path = [[prefix URLByAppendingPathComponent:[NSString stringWithFormat:@"%li", count]] path];
            NSLog(@"%@", path);
            if([NSKeyedArchiver archiveRootObject:fromAvro toFile:path]){
                NSLog(@"-------- Cluster written.");
                [[NSUserDefaults standardUserDefaults] setValue:@(count) forKey:@"demo_cluster_count"];
            } else {
                 NSLog(@"-------- Cluster not written. ");
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
        [self parseClusters:fromAvro];
            //reset timer
//            demoTimer = [NSTimer scheduledTimerWithTimeInterval:5
//                                                     target:self
//                                                   selector:@selector(handleDemoTimer:)
//                                                   userInfo:nil
//                                                    repeats:NO];
        });
    } else {
        NSLog (@"got raw frame");
        //NSLog (@"data.length %lu data: %@",(unsigned long)data.length, data);
        NSString *msg = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (msg)
        {
    //       NSLog (@"Msg: %@",msg);
        }
        else
        {
            NSLog(@"Error converting received data into UTF-8 String");
        }
        
        NSArray *lines = [msg componentsSeparatedByString:@"\n"];
        
    //    NSLog(@"pixels: %@",lines);
        
    //    if([lines count] > 0){
    //        new_hits = true;
    //    }

        for(NSString * line in lines){
            if([line length] != 0){
                if([line isEqualToString:@"new frame:"]){
                    new_frame = true;
                    break;
                    
                }
                
                NSArray *d = [line componentsSeparatedByString:@"\t"];
    //            NSLog(@"pixels: %@",d);
                if ([d count] == 3){
//                    [fBuffer setPixelWithX:[d[0] intValue] y:[d[1] intValue] counts:[d[2] intValue]];
    //                NSLog(@"%08x TOT:%i",fBuffer.framebuffer[ ([d[1] intValue] * 255) + [d[0] intValue]], [d[2] intValue]);
                }
            }
        }

        if(new_frame){
            NSLog (@"Draw new frame");

          
            dispatch_async(dispatch_get_main_queue(), ^{
//                [fBuffer blit];
                focusTimer = [NSTimer scheduledTimerWithTimeInterval:0
                                                      target:self
                                                    selector:@selector(handleFPtimer:)
                                                    userInfo:nil
                                                     repeats:NO];
            });

        }
    }

}


-(void)parseClusters:(NSDictionary *)fromAvro {
    //    NSLog (@"%@",fromAvro);
    //        NSLog (@"data.length %lu data: %@",(unsigned long)data.length, data);
    
    //save current device orientation as reference
    CMAttitude * attitude = [MotionManagerSingleton getAttitude];
    //                if(attitude==nil){
    //                    //during init phase we don't have a proper attitude, yet
    //                    attitude = [[CMAttitude alloc] init];
    //                }
    
    NSArray * clusters = [fromAvro valueForKey:@"clusterArray"];
    int counts = (int)[clusters count];
    NSLog (@"got %i avro clusters", counts);
    
    NSDictionary * cluster;
    
    
    for (cluster in clusters) {
        // UTF8 string length is in bytes and thus missleading if there are composed characters,
        // therefore we have to extract the number of composed characters with this custom category function
        int xdata = (int) [[cluster valueForKey:@"xi"] getNumberOfCharacters];
        int ydata = (int) [[cluster valueForKey:@"yi"] getNumberOfCharacters];
        int edata = (int) [[cluster valueForKey:@"ei"] getNumberOfCharacters];
        int clusterSize = xdata;
        if(xdata != ydata && xdata != edata && ydata != edata){
            NSLog(@"WARNING: non equal byte length ------------------------");
        }
        
        float centerX = [[cluster valueForKey:@"center_x"] floatValue];
        float centerY = [[cluster valueForKey:@"center_y"] floatValue];
        float energy = [[cluster valueForKey:@"energy"] floatValue];
        NSLog (@"clusterTOT: %@ size: %i centerx: %.1f centery: %.1f",[cluster valueForKey:@"energy"], clusterSize, centerX, centerY);
        //            NSLog(@"size xi: %i size yi: %i, size ei: %i ",xdata,ydata,edata);
        
        //            NSData * test = [cluster valueForKey:@"yi"];
        //            NSData * test = [NSKeyedArchiver archivedDataWithRootObject:[cluster valueForKey:@"yi"]];
        //            uint8_t * bytePtr = (uint8_t  * )[test bytes];
        //              unichar bytePtr[clusterSize];
        //              [[cluster valueForKey:@"yi"] getCharacters:bytePtr range:NSMakeRange(0, [[cluster valueForKey:@"yi"] length])];
        //              NSInteger totalData = clusterSize;
        //            NSInteger totalData = [test length] / sizeof(uint8_t);
        //              for (int i = 0 ; i < totalData; i ++)
        //              {
        //                  NSLog(@"data byte chunk : %x", bytePtr[i]);
        //              }
        //            NSLog(@"test length: %i", totalData);
        
        //            NSData* test = [[[cluster valueForKey:@"xi"] dataUsingEncoding:NSASCIIStringEncoding];
        //            NSData* test = [[[cluster valueForKey:@"xi"] cStringUsingEncoding:NSASCIIStringEncoding]];
        
        
        //            NSLog(@"%@", test);
        
        //TODO: is dispatching here better for fast packet processing?
//        dispatch_async(dispatch_get_main_queue(), ^{
        
            uint32_t framebuffer[256*256]={0};
            
            unsigned char xi[clusterSize];
            unsigned char yi[clusterSize];
            unsigned char ei[clusterSize];
            
            unsigned char maxTOT = 0;
            unsigned char maxX = 0;
            unsigned char maxY = 0;
            unsigned char minX = 255;
            unsigned char minY = 255;
            
            // get _character_ values (UTF8 numbers can be multiple bytes)
            for(int i = 0; i < clusterSize; i++){
                xi[i] = (unsigned char)[[cluster valueForKey:@"xi"] characterAtIndex:i ];
                yi[i] = (unsigned char)[[cluster valueForKey:@"yi"] characterAtIndex:i ];
                ei[i] = (unsigned char)[[cluster valueForKey:@"ei"] characterAtIndex:i ];
                if(ei[i] > maxTOT){
                    maxTOT = ei[i];
                }
                if(xi[i] > maxX)
                    maxX = xi[i];
                if(xi[i]< minX)
                    minX = xi[i];
                if(yi[i] > maxY)
                    maxY = yi[i];
                if(yi[i]< minY)
                    minY = yi[i];
            }
            
            //cluster box size:
            unsigned char width = (maxX - minX)+1;
            unsigned char heigth = (maxY - minY)+1;
            
            
            //            for (int i=0; i < clusterSize; i++) {
            //                NSLog (@"%d %d %d",xi[i],yi[i],ei[i] );
            //
            //            }
            
#if 0
            TPXFrameBufferLayer * localFBuffer = [fbArray fillFbLayerWithLength:clusterSize Xi:xi Yi:yi Ei:ei MaxTOT:maxTOT CenterX:centerX CenterY:centerY Energy:energy];
            [localFBuffer blit];
            [localFBuffer animateWithLensPosition:self.lensPositionSlider.value];
            
#else
            
            uint32_t * palette_rgba = [TPXFrameBufferLayer getPalette];
            for (int i = 0; i < clusterSize; i++) {
                framebuffer[(yi[i] * 256) + xi[i]] = palette_rgba[(unsigned char)floor(ei[i] * (256)/(maxTOT+28))];
                
            }
            
            //                    SKSpriteNode *sprite = [SKSpriteNode spriteNodeWithColor:[SKColor redColor] size:CGSizeMake(256, 256)];
            //                SKSpriteNode *node = [[SKSpriteNode alloc] init];
            SKSpriteNode *sprite = [[SKSpriteNode alloc] init];
            NSData * data = [NSData dataWithBytes:framebuffer length:256*256*4];
            SKTexture *tex = [SKTexture textureWithData:data size:CGSizeMake(256, 256)];
            tex.filteringMode = SKTextureFilteringNearest;
            sprite.texture = tex;
            sprite.size = tex.size;
            sprite.alpha = 1;
            sprite.anchorPoint = CGPointMake((centerX/256), (centerY/256));
            
            sprite.userData = [NSMutableDictionary dictionary];
            if(attitude){
                [sprite.userData setObject:attitude forKey:@"attitude"];
            }
            [sprite.userData setValue:@(energy) forKey:@"energy"];
            
            
            // sprite scale must be in sync with fpFrame size
            float geoFactor = (768.0/256.0) * (1-self.lensPositionSlider.value);
            sprite.scale = (geoFactor);
            
            //                [sprite setScale:10.0f];
            //                [sprite setPosition:CGPointMake((focusPointer.size.width/2),(focusPointer.size.height/2))];
            [sprite setPosition:CGPointMake((centerX-128) * geoFactor,
                                            (centerY-128) * geoFactor)];
            
            //display cluster only if scene speed is forward
            if(scene.speed >= 1){
                
                // set energy dependant scale and time factors
                float scaleFactor = energy/40;
                if (scaleFactor > 8.0)
                    scaleFactor = 8.0;
                else if (scaleFactor < 1.0)
                    scaleFactor = 1.0;
                
                float timeScale = 2.0f*energy/2000;
                
                if(timeScale > 3.5)
                    timeScale= 3.5f;
                else if (timeScale < 2.0)
                    timeScale = 2.0;
                
                [sprite.userData setValue:@(timeScale) forKey:@"duration"];
                
                
                float alpaFactor = 0.2*energy/1000;
                if (alpaFactor > 1)
                    alpaFactor = 1;
                else if (clusterSize < 5)
                    alpaFactor = 0.9; //preserve visibility of small clusters
                else if (alpaFactor < 0.3)
                    alpaFactor = 0.3;
                
                SKAction * zoom = [SKAction scaleBy:scaleFactor*(1+self.lensPositionSlider.value) duration:timeScale];
                zoom.timingMode = SKActionTimingEaseOut;
                SKAction * fade = [SKAction fadeAlphaTo:alpaFactor duration:timeScale];
                SKAction *remove = [SKAction removeFromParent];
                //                    SKAction * remove = [SKAction  runBlock:^{
                //                        [sprite removeAllChildren];
                //                        [sprite removeFromParent];
                //                    }];
                SKAction * zoomFade = [SKAction group:@[zoom, fade]];
                
                unsigned char max_length = 0;
                float ratio = .0;
                
                if(width > heigth){
                    max_length = width;
                    ratio = width/heigth;
                } else {
                    max_length = heigth;
                    ratio = heigth/width;
                }
                
                float occupancy = (clusterSize/(width*heigth*1.0));
                
                int beta_threshold = 200;
            
                //simple cluster identfification
                // 1 and 2 pixel clusters
                if (clusterSize <= 2){
                    if (energy<10){
                        //assmuming electrons would be stopped in the metal layer
                        sprite.name=@"gamma";
                        gamma_cnt++;
                    } else {
                        sprite.name=@"beta/gamma";
                        unknown_cnt++;
                    }
                }else if (clusterSize > 4) {
//                    if ( ratio < 1.5 ) {
                        // squarish clusters
                        //if (clusterSize > (2*max_length) ){
                        if ( occupancy > 0.5 ){
                            //round heavy blob
                            if (energy > 1000) {
                                sprite.name=@"alpha";
                                alpha_cnt++;
                            } else {
                                //overlapping cluters?
                                //sprite.name=[NSString stringWithFormat:@"%.1f", occupancy];;
                                unknown_cnt++;
                                NSLog(@"unclassified cluster");
                            }
                        } else {
                            //curly track
                            if (energy>beta_threshold){
                                //assumption on increased probability
                                sprite.name=@"beta";
                                beta_cnt++;
                            } else {
                                sprite.name=@"beta/gamma";
                                unknown_cnt++;
                            }
                        }
//                    } else {
//                        // longish clusters
//                        if (energy>beta_threshold){
//                            //assumption on increased probability
//                            sprite.name=@"beta";
//                            beta_cnt++;
//                        } else {
//                            sprite.name=@"beta/gamma";
//                            unknown_cnt++;
//                        }
//                    }
                } else if (clusterSize == 4 && (width==1 || heigth==1)){
                    //most likely a short muon track
                    sprite.name=@"muon";
                    unknown_cnt++;
                }else {
                    unknown_cnt++;
                    NSLog(@"unclassified cluster");
                }
                
                if (([scene getLabelCount]/4) < 10){
                    [scene addLabelForNode:sprite];
                } else {
                    NSLog(@"label count: %lu",[scene getLabelCount]);
                }
                
                [scene.clusters addChild:sprite];
                [sprite runAction: [SKAction sequence:@[zoomFade,remove]]];
            }
#endif
//        });
    }
}

- (void)handleDemoTimer:(NSTimer *) timer {
    
    [demoTimer invalidate];
    demoTimer = nil;

//    NSLog(@"demo timer fired");
    
    //load previously saved clusters
    NSURL * prefix = [AAPLCameraViewController applicationDataDirectory];
//    prefix = [prefix URLByAppendingPathComponent:@"demo_clusters"];
    
    unsigned int clusters = arc4random_uniform(2); //randomly display 0 to 4 clusters in one frame
    unsigned int count = (unsigned int)[[[NSUserDefaults standardUserDefaults] valueForKey:@"demo_cluster_count"] integerValue];
    
    while(clusters--){
        unsigned int rand = arc4random_uniform(count)+1;
        NSString *path = [[prefix URLByAppendingPathComponent:[NSString stringWithFormat:@"%i", rand]] path];
        NSLog(@"randomly selected cluster for display %i", rand);
        dispatch_async(dispatch_get_main_queue(), ^{
            NSDictionary * data = [NSKeyedUnarchiver unarchiveObjectWithFile:path];
            //    NSLog(@"%@",data);
            [self parseClusters:data];
        });
    }
    
    if(demo_mode){
    //reset timer
    demoTimer = [NSTimer scheduledTimerWithTimeInterval:0.6
                                                 target:self
                                               selector:@selector(handleDemoTimer:)
                                               userInfo:nil
                                                repeats:NO];
    }
}

- (void)handleCpsTimer:(NSTimer *) timer {
    static int count;
    
    alpha_cps+=alpha_cnt;
    alpha_cnt=0; //simulate low pass behaviour on this counter

    beta_cps+=beta_cnt;
    beta_cnt=0; //simulate low pass behaviour on this counter

    
    gamma_cps+=gamma_cnt;
    gamma_cnt=0; //simulate low pass behaviour on this counter
    
    unknown_cps+=unknown_cnt;
    unknown_cnt=0; //simulate low pass behaviour on this counter
    
    
    //update display every second
    if(!(count%1)){
        alpha_ctr.text = [NSString stringWithFormat:@"\u03B1 %.1f", alpha_cps];
        beta_ctr.text = [NSString stringWithFormat:@"\u03B2 %.1f", beta_cps];
        gamma_ctr.text = [NSString stringWithFormat:@"\u03B3 %.1f", gamma_cps];
        unknown_ctr.text = [NSString stringWithFormat:@"? %.1f", unknown_cps];
    }
    
    //average every 3 seconds
    if(!(count%3)){
        alpha_cps /= 3;
        beta_cps /= 3;
        gamma_cps /= 3;
        unknown_cps /= 3;
    }
    count++;

    
//    NSLog(@"cps timer finished");
}

+ (NSURL*)applicationDataDirectory {
//    NSFileManager* sharedFM = [NSFileManager defaultManager];
//    NSArray* possibleURLs = [sharedFM URLsForDirectory:NSApplicationSupportDirectory
//                                             inDomains:NSUserDomainMask];
//    NSURL* appSupportDir = nil;
//    NSURL* appDirectory = nil;
//    
//    if ([possibleURLs count] >= 1) {
//        // Use the first directory (if multiple are returned)
//        appSupportDir = [possibleURLs objectAtIndex:0];
//    }
//    
//    // If a valid app support directory exists, add the
//    // app's bundle ID to it to specify the final directory.
//    if (appSupportDir) {
//        NSString* appBundleID = [[NSBundle mainBundle] bundleIdentifier];
//        appDirectory = [appSupportDir URLByAppendingPathComponent:appBundleID];
//    }
//    
//    return appDirectory;
    
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
}


@end
