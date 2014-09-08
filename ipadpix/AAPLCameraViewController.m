/*
 Copyright (C) 2014 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 
  Control of camera functions.
  
 */

#import "AAPLCameraViewController.h"

#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>

#import "AAPLPreviewView.h"

#import "GCDAsyncUdpSocket.h"
#import "DDLog.h"
#import "DDTTYLogger.h"
#import "TPXFrameBufferLayer.h"

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
dispatch_queue_t networkQueue;


@synthesize focusPointer;
@synthesize fBuffer;
@synthesize overlayImageView;

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

- (void)viewDidLoad
{
	[super viewDidLoad];
    
    // Setup our logging framework.
    
    [DDLog addLogger:[DDTTYLogger sharedInstance]];
    
	self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	
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
		
        CGRect screenRect = [[UIScreen mainScreen] bounds];
        double screenWidth = screenRect.size.width;
        double screenHeight = screenRect.size.height;
        focusPOI.x = screenWidth/2.0;
        focusPOI.y = screenHeight/2.0;
        
        CGPoint defaultFocusPOI = CGPointMake(.5, .5);
        
        //configure video display size and exposure mode
        
        
        if (!TARGET_IPHONE_SIMULATOR && [self.videoDevice lockForConfiguration:&error]) {
            [self.videoDevice setFocusPointOfInterest:defaultFocusPOI];
            //[self.videoDevice videoZoomFactor:2.0];
            if ([self.videoDevice respondsToSelector:@selector(setVideoZoomFactor:)]) {
                //float zoomFactor = self.videoDevice.activeFormat.videoZoomFactorUpscaleThreshold;
                //[self.videoDevice setVideoZoomFactor:zoomFactor];
                [self.videoDevice setVideoZoomFactor:2.0];
            }
            [(AVCaptureVideoPreviewLayer *)[[self previewView] layer] setVideoGravity:AVLayerVideoGravityResizeAspectFill];
            [self.videoDevice setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
            
            [self.videoDevice unlockForConfiguration];
        }
        else
        {
            NSLog(@"simulator mode or error: %@", error);
        }
        
  
        focusPointer = CGRectMake(0.0, 0.0, 100.0, 100.0);
       
        fPview = [[UIView alloc] initWithFrame:focusPointer];
        CGRect r = focusPointer;
        r.origin = self.view.bounds.origin;
        r.origin.x = focusPOI.x - (r.size.width/2);
        r.origin.y = focusPOI.y - (r.size.height/2);
        fPview.frame = r;
        overlayImageView = [[UIImageView alloc] initWithFrame:focusPointer];
        
        fBuffer = [TPXFrameBufferLayer paletteLayerWithFrame:CGRectMake(0, 0, 255, 255)];
        
        //fPview.backgroundColor = UIColor.redColor; //
        fPview.backgroundColor = UIColor.clearColor; //
        [fPview.layer setBorderWidth:5.0];
        [fPview.layer setCornerRadius:4.0];

        [fPview.layer setBorderColor:[UIColor yellowColor].CGColor];

        
        [[fPview layer] setOpacity:0.5];
		
        dispatch_async(dispatch_get_main_queue(), ^{
			[self configureManualHUD];
            [[self view] addSubview:fPview];
            // translate, then scale, then rotate
//            CGAffineTransform affineTransform = CGAffineTransformMakeTranslation(-(self.previewView.layer.bounds.size.width/4.0), 0.0);
//            affineTransform = CGAffineTransformScale(affineTransform, 1.0, 1.0);
//            affineTransform = CGAffineTransformRotate(affineTransform, 0.0);
//            [CATransaction begin];
//            [CATransaction setAnimationDuration:.025];
//            [(AVCaptureVideoPreviewLayer *)[[self previewView] layer] setAffineTransform:affineTransform];
//            [CATransaction commit];
            
            //            [[overlayImageView layer] setOpacity:1.0];
            //            [fBuffer setOpacity:1.0];
            fBuffer.contentsScale = [[UIScreen mainScreen] scale];
            [self.view addSubview:overlayImageView];
            [overlayImageView.layer addSublayer:fBuffer];
		});

	});
	
	self.manualHUDFocusView.hidden = YES;
    
    // setup and bind UDP server socket to port
  
    // Create High Priotity queue
    networkQueue = dispatch_queue_create("networkQueue", NULL);
    dispatch_queue_t high = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
    
    dispatch_set_target_queue(networkQueue, high);
    
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
}


//- (void)drawRect:(CGRect)rect {
////    CGContextRef context = UIGraphicsGetCurrentContext();
////    //[self.view renderInContext:context];
////    CGContextSetAllowsAntialiasing(context, false);
//}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
    if(!TARGET_IPHONE_SIMULATOR){
        dispatch_async([self sessionQueue], ^{
            [self addObservers];
            [[self session] startRunning];
        });
    }
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
    fPview.frame = r;
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
	//self.manualHUDExposureView.frame = CGRectMake(self.manualHUDFocusView.frame.origin.x, self.manualHUDFocusView.frame.origin.y, self.manualHUDExposureView.frame.size.width, self.manualHUDExposureView.frame.size.height);
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
                    device.autoFocusRangeRestriction = AVCaptureAutoFocusRangeRestrictionNear;
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
	CGPoint focusPOI = CGPointMake(.5, .5);
    
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
    
    
    NSLog(@"timer count: %i", count);
    
    float lensPosition = self.lensPositionSlider.value;
    
    CGRect screenRect = [[UIScreen mainScreen] bounds];
//    double screenWidth = screenRect.size.width;
    double screenHeight = screenRect.size.height;
    
    if (!self.videoDevice.isAdjustingFocus){
        NSLog(@"focusPOI: %@", NSStringFromCGPoint(focusPOI));
        dispatch_async(dispatch_get_main_queue(), ^{
            CGRect r = focusPointer;
            r.origin = self.view.bounds.origin;
//            r.size.height = 50 + ((int)floor(r.size.height / (lensPosition+0.1)));
//            r.size.width  = 50 + ((int)floor(r.size.width  / (lensPosition+0.1)));
            r.size.height = (screenHeight/ ((lensPosition+1.0)*(lensPosition+1.0)) );
            r.size.width  = r.size.height;
            r.origin.x = focusPOI.x - (r.size.width/2);
            r.origin.y = focusPOI.y - (r.size.height/2);
            fPview.frame = r;
            
            //display some randomized frames
//            int rand = arc4random() % 10 +1;
//            NSString *imageName = [NSString stringWithFormat:@"%d_.png", rand];
//            overlayImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:imageName]];
//            [overlayImageView setFrame:CGRectMake(0, 0, 255, 255)];
//            rand = arc4random() % 4;
//            overlayImageView.transform = CGAffineTransformMakeRotation(1.57*rand);
            
            r = overlayImageView.frame;
            r.origin.x = focusPOI.x  - (256/2);
            r.origin.y = focusPOI.y  - (256/2);
            overlayImageView.frame = r;
                        
//            NSLog(@"new overlayImageView width: %d, height: %d", (int)overlayImageView.frame.size.width, (int)overlayImageView.frame.size.height);


         
            fBuffer.transform = CATransform3DMakeScale(3*(1-lensPosition), 3*(1-lensPosition), 1);

            
            dispatch_async(dispatch_get_main_queue(), ^{
             
//                [[fPview layer] setOpacity:1.0];
//                [UIView animateWithDuration:.10 animations:^{
//                    [fPview.layer setBorderColor:[UIColor redColor].CGColor];
//                    [[fPview layer] setOpacity:0.0];
//                }];
                
//                [fPview.layer setBorderColor:[UIColor yellowColor].CGColor];
//                [[fPview layer] setOpacity:1.0];
                fBuffer.opacity=0;
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
                group.duration = 1.8f;
                group.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
                group.animations = [NSArray arrayWithObjects:fadeAnimation, zoomAnimation, nil];
                group.delegate = self;
                [group setValue:@"groupFadeZoom" forKey:@"animationName"];
                [group setValue:fBuffer forKey:@"parentLayer"];
       
                [fBuffer addAnimation:group forKey:@"groupFadeZoom"];
                
                
                
//                NSLog(@"There are %d sublayers after adding fBuffer",[overlayImageView.layer.sublayers count]);
                

           });
            
//            r.size.height *= lensPosition * 50;
//            r.size.width *= lensPosition * 50;
            
            focusTimer= nil;
        });
    } else {
        NSLog(@"start timer2");
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
            [fBuffer clear];
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
    NSDictionary *fromAvro = [avro JSONObjectFromData:data forSchemaNamed:@"tpxFrame" error:&error];
    if (!error) {
//    NSLog (@"%@",fromAvro);
        NSLog (@"got avro clusters");
        NSLog (@"data.length %lu data: %@",(unsigned long)data.length, data);

        
        NSArray * clusters = [fromAvro valueForKey:@"clusterArray"];
        const unsigned char * xi = (const unsigned char*) [[[clusters objectAtIndex:0] valueForKey:@"xi"] UTF8String];
        const unsigned char * yi = (const unsigned char*) [[[clusters objectAtIndex:0] valueForKey:@"yi"] UTF8String];
        const unsigned char * ei = (const unsigned char*) [[[clusters objectAtIndex:0] valueForKey:@"ei"] UTF8String];
        int cluster_size = (int) [[[clusters objectAtIndex:0] valueForKey:@"ei"] length];
        
        //number of clusters
        NSLog (@"%i",(int)[clusters count]);
        
        for (int i=0; i < cluster_size; i++) {
            NSLog (@"%d %d %d",xi[i],yi[i],ei[i] );

        }
        NSLog (@"%@",[[clusters objectAtIndex:0] valueForKey:@"energy"]);
    } else {

        NSLog (@"got raw frame");

        //NSLog (@"data.length %lu data: %@",(unsigned long)data.length, data);

        NSString *msg = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (msg)
        {
            /* If you want to get a display friendly version of the IPv4 or IPv6 address, you could do this:
           
             NSString *host = nil;
             uint16_t port = 0;
             [GCDAsyncUdpSocket getHost:&host port:&port fromAddress:address];
             
             */
            
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
                    [fBuffer setPixelWithX:[d[0] intValue] y:[d[1] intValue] counts:[d[2] intValue]];
    //                NSLog(@"%08x TOT:%i",fBuffer.framebuffer[ ([d[1] intValue] * 255) + [d[0] intValue]], [d[2] intValue]);
                }
            }
        }

        if(new_frame){
            NSLog (@"Draw new frame");

          
            dispatch_async(dispatch_get_main_queue(), ^{
                [fBuffer blit];
                focusTimer = [NSTimer scheduledTimerWithTimeInterval:0
                                                      target:self
                                                    selector:@selector(handleFPtimer:)
                                                    userInfo:nil
                                                     repeats:NO];
            });

        }
    }

}

@end
