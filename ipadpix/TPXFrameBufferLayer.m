//
//  TPXFrameBufferLayer.m
//  iPadPix
//
//  Created by Oliver Keller on 20.08.14.
//  Copyright (c) 2014 Oliver Keller. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIColor.h>
#import <UIKit/UIScreen.h>
#import "TPXFrameBufferLayer.h"
#import "ColorSpaceUtilities.h"

@implementation TPXFrameBufferLayer

@synthesize context = _context;
@synthesize isFree;
@synthesize index;
@synthesize centerX;
@synthesize centerY;
@synthesize energy;
@synthesize framebuffer;

//TPX/MPX standard:
#define FRAME_WIDTH 255

//MPX JET

//#define SATURATION_VAL     1.0
//#define MAXLIGHTNESS_VAL   0.5
//#define MINLIGHTNESS_VAL   0.6
//#define MAXHUE_VAL         0.64 //(230/360)
//#define MINHUE_VAL         0.0  //(0/360)

//MPX HOT:

//#define SATURATION_VAL     0.9
//#define MAXLIGHTNESS_VAL   0.1
//#define MINLIGHTNESS_VAL   1
//#define MAXHUE_VAL         0      //(0/360)
//#define MINHUE_VAL         0.16667  //(60/360)

#define SATURATION_VAL     1.0

// dark red
#define MAXHUE_VAL         (10.0/256.0)      //(0/360)
#define MAXLIGHTNESS_VAL   (83.0/256.0)
// light yellow
#define MINHUE_VAL         (39.0/256.0)  //(60/360)
#define MINLIGHTNESS_VAL   (233.0/256.0)

#define MAX_COLORS (11810)//256

uint32_t palette[MAX_COLORS];
uint32_t palette_rgba[MAX_COLORS];

bool paletteInitialized = false;

int localFrameWidth;
int localFrameHeight;


+ (TPXFrameBufferLayer *)createLayerWithFrame:(CGRect)frame Index:(uint32_t) index
{
    //init color palette
    //based on HOT palette from mafalda/MPXViewer/MPXViewer.cpp
    
    if(!paletteInitialized){
        NSLog(@"Initializing palette");
        CGFloat lightness, hue, saturation, Maxlightness, Minlightness, MaxHue, MinHue;
        float  alpha, red, green, blue;
        
        saturation = SATURATION_VAL;
        Maxlightness = MAXLIGHTNESS_VAL;
        Minlightness = MINLIGHTNESS_VAL;
        MaxHue = MAXHUE_VAL;
        MinHue = MINHUE_VAL;
        alpha=1.0;

        for(int i = 0; i < MAX_COLORS; i++){
            lightness = Maxlightness-(i+1)*((Maxlightness-Minlightness)/MAX_COLORS);
            hue = MaxHue-(i+1)*((MaxHue-MinHue)/MAX_COLORS);
            HSL2RGB(hue, saturation, lightness, &red, &green, &blue);
            
//            UIColor *color = [UIColor colorWithHue: hue saturation: saturation
//                                        brightness: lightness alpha: alpha];
//            [color getRed: &red green: &green blue: &blue alpha: &alpha];
//            NSLog(@"H %f, S %f, L %f", hue, saturation, lightness);
            
            // pre-multiply alpha to match color space
//            red*=alpha;
//            green*=alpha;
//            blue*=alpha;
            
//            NSLog(@"red %f, green %f, blue %f", red, green, blue);

            //ARGB
//            palette[i] = ((int)floor(alpha*255.0)) << (3*8) |
//            ((int)floor(red  *255.0)) << (2*8) |
//            ((int)floor(green*255.0)) << (1*8) |
//            ((int)floor(blue *255.0));
            
            //BGRA
            palette[i] = ((int)floor(blue  *256.0)) << (3*8) |
                        ((int)floor(green  *256.0)) << (2*8) |
                        ((int)floor(red   *256.0)) << (1*8) |
                        ((int)floor(alpha  *256.0));
            
            //sprite kit texture format, should be RGBA
            palette_rgba[i] = ((int)floor(alpha  *255.0)) << (3*8) |
                            ((int)floor(blue  *255.0)) << (2*8) |
                            ((int)floor(green   *255.0)) << (1*8) |
                            ((int)floor(red  *255.0));
        }
        paletteInitialized = true;
    }
    
    TPXFrameBufferLayer * fBuffer = [[self alloc] initWithFrame:frame];
    fBuffer.isFree = true;
    fBuffer.index = index;
   return fBuffer;
    
}

+(uint32_t *)getPalette{
    return palette_rgba;
}

- (id)initWithFrame:(CGRect)frame
{
    if (self=[super init]){
        self.opaque = NO; //YES
        self.frame=frame;
//        NSLog(@"super init %f", self.frame.size.width);
    }
    return self;
}

- (void)dealloc
{
    CGContextRelease(_context);
}

- (void)blit
{
    CGImageRef img = CGBitmapContextCreateImage(_context);
    self.contents = (__bridge id)img;
    CGImageRelease(img);
}

- (void)setPixelWithX:(unsigned char)x y:(unsigned char)y counts:(unsigned char)counts
{
    framebuffer[(y * localFrameWidth) + x] = palette[counts];
}

- (void)setPixelRGBAWithX:(unsigned char)x y:(unsigned char)y counts:(unsigned char)counts
{
    framebuffer[(y * localFrameWidth) + x] = palette_rgba[counts];
}

-(void)clear
{
    for(int i = 0; i < (localFrameWidth * localFrameHeight); i++){
        framebuffer[i]=0x00000000;
    }
    self.isFree = true;
    [self blit];
//    NSLog(@"tpx frame buffer %i cleared", self.index);
}

-(void)setFrame:(CGRect)frame
{
    CGRect oldframe = self.frame;
    [super setFrame:frame];
    if (frame.size.width != oldframe.size.width ||
        frame.size.height != oldframe.size.height){
        NSLog(@"new frame buffer, width: %d, height: %d", (int)frame.size.width, (int)frame.size.height);
        if (_context){
            CGContextRelease(_context);
        }
        CGColorSpaceRef csp = CGColorSpaceCreateDeviceRGB();
        _context = CGBitmapContextCreate(NULL,
                                         (size_t)frame.size.width,
                                         (size_t)frame.size.height, 8,
                                         4*(size_t)frame.size.width, csp,
                                         (CGBitmapInfo)(kCGImageAlphaPremultipliedFirst));
//                                         (CGBitmapInfo)(kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little));
//                                         (CGBitmapInfo)kCGBitmapByteOrder32Little |kCGImageAlphaNoneSkipFirst);
        //switch off anti-aliasing
        CGContextSetShouldAntialias(_context, NO);
        CGContextSetAllowsAntialiasing(_context, NO);
        CGContextSetInterpolationQuality(_context, kCGInterpolationNone);

        //support scale factor of retina devices
        float scaleFactor = [[UIScreen mainScreen] scale];
        CGContextScaleCTM(_context, scaleFactor*2, scaleFactor*2);

        
        CGColorSpaceRelease(csp);
        framebuffer = CGBitmapContextGetData(_context);
        //self.frame is not in sync with actual frame width so we save it here
        localFrameWidth=(int)frame.size.width;
        localFrameHeight=(int)frame.size.height;
//        CGContextSaveGState(_context);
//        CGContextTranslateCTM(_context, 0.0, localFrameHeight);
//        CGContextScaleCTM(_context, 1.0, -1.0);
//        CGContextDrawImage(_context, image, CGRectMake(0, 0, imageWidth, imageHeight));
//        CGContextRestoreGState(_context);

    }
}

-(uint32_t *)framebuffer
{
    return CGBitmapContextGetData(_context);
}

-(void)animateWithLensPosition:(float) lensPosition
{

//    [self setBorderWidth:1.0];
//    [self setBorderColor:[UIColor blackColor].CGColor];
    
    [CATransaction begin];
    [CATransaction setDisableActions: YES];

    //if fBuffer parent layer is the whole screen
//    CGRect screenRect = [[UIScreen mainScreen] bounds];
//    double screenWidth = screenRect.size.width;
//    double screenHeight = screenRect.size.height;
//    CGRect r = self.frame;
//    r.origin.x = floorf((screenWidth/2.0)-(128));
//    r.origin.y = floorf((screenHeight/2.0)-(128));
//    self.frame = r;
    //fBuffer is a subview of another view
    //set the origin
    [self setFrame:({
        CGRect frame = self.frame;
        
        frame.origin.x = (self.frame.size.width/2.0) - localFrameWidth/2;
        frame.origin.y = (self.frame.size.height/2.0) - localFrameHeight/2;
        
        CGRectIntegral(frame);
    })];
    
    [CATransaction commit];

    NSLog(@"origin %f %f size %f %f scale %f ", self.frame.origin.x,self.frame.origin.y, self.frame.size.width, self.frame.size.height, self.contentsScale );
    CABasicAnimation* fadeAnimation = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fadeAnimation.fromValue = @1.0;
    fadeAnimation.toValue = @0.8;
//    fadeAnimation.fillMode = kCAFillModeForwards;
//    fadeAnimation.removedOnCompletion = NO;
    
    CABasicAnimation* zoomAnimation = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    zoomAnimation.fromValue = [NSValue valueWithCATransform3D:CATransform3DIdentity];
    float scaleFactor = self.energy/40;
    if (scaleFactor > 12.0)
        scaleFactor = 12.0;
    zoomAnimation.toValue = [NSValue valueWithCATransform3D:CATransform3DMakeScale((1-lensPosition)*3*scaleFactor, (1-lensPosition)*3*scaleFactor, 1)];
//    zoomAnimation.fillMode = kCAFillModeForwards;
//    zoomAnimation.removedOnCompletion =NO;
    
    //                zoomAnimation.fromValue = [NSNumber numberWithFloat:1.0f];
    //                zoomAnimation.toValue = [NSNumber numberWithFloat:10.0f];
    
    CAAnimationGroup *group = [CAAnimationGroup animation];
    float timeScale = 2.0f*self.energy/1000;
    if(timeScale > 3.0)
        group.duration = 3.0f;
    else if (timeScale < 1.5)
        group.duration = 1.5;
    else
        group.duration = 2.0f*self.energy/1000;
    
    group.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
//    group.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    group.animations = [NSArray arrayWithObjects:fadeAnimation, zoomAnimation, nil];
//    group.animations = [NSArray arrayWithObjects:zoomAnimation, nil];
    group.delegate = self;
    [group setValue:@"groupFadeZoomCluster" forKey:@"animationName"];
    [group setValue:self forKey:@"parentLayer"];
    
    [self addAnimation:group forKey:@"groupFadeZoomCluster"];

}
- (void)animationDidStop:(CAAnimation *)animation finished:(BOOL)finished
{
    NSString *animationName = [animation valueForKey:@"animationName"];
    if ([animationName isEqualToString:@"groupFadeZoomCluster"])
    {
        [self clear];
//        self.center = CGPointMake(0.5, 0.5);
        //            NSLog(@"There were %i sublayers",[overlayImageView.layer.sublayers count]);
        //            CALayer *layer = [animation valueForKey:@"parentLayer"];
        //            [layer removeAllAnimations];
        //            [layer removeFromSuperlayer];
        //            NSLog(@"There are now %i sublayers",[overlayImageView.layer.sublayers count]);
        
    }
}

@end

@implementation NSMutableArray (TPXFrameBuffers)

#define MAX_FRAME_BUFFERS 128
//TPXFrameBuffers * fbArray[MAX_FRAME_BUFFERS];

+ (NSMutableArray *)initTPXFrameBuffersWithParentLayer:(CALayer *) parentLayer
{
    
    NSMutableArray * fbArray = [[self alloc] init]; //[NSMutableArray array];
    for(int i=0; i < MAX_FRAME_BUFFERS; i++ ){
        [fbArray appendFbArrayWithParentLayer:parentLayer Index:i];
    }
    NSLog(@"created %i TPX frame buffers",(unsigned int) [fbArray count]);
    return fbArray;
}

- (TPXFrameBufferLayer *)appendFbArrayWithParentLayer:(CALayer *)parentLayer Index:(uint32_t) index
{
    TPXFrameBufferLayer * fBuffer = [TPXFrameBufferLayer createLayerWithFrame:parentLayer.frame Index:index];
    [CATransaction begin];
    [CATransaction setDisableActions: YES];
    
    //FIXME: somehow setting origin has no influence here, why?
//    CGRect screenRect = [[UIScreen mainScreen] bounds];
//    double screenWidth = screenRect.size.width;
//    double screenHeight = screenRect.size.height;
//    CGRect r = fBuffer.frame;
//    r.origin.x = floorf((screenWidth/2.0)-(128));
//    r.origin.y = floorf((screenHeight/2.0)-(128));
//    fBuffer.frame = r;
    
    fBuffer.opacity=0;
    fBuffer.shouldRasterize = YES;
    //fBuffer.edgeAntialiasingMask = kCALayerLeftEdge | kCALayerRightEdge | kCALayerTopEdge | kCALayerBottomEdge ;
    fBuffer.geometryFlipped = YES;
    [fBuffer setRasterizationScale:[UIScreen mainScreen].scale*2];
    //fBuffer.contentsScale=[[UIScreen mainScreen] scale]*2;
    
    [CATransaction commit];

    [parentLayer addSublayer:fBuffer];
    [self addObject:fBuffer];
    return fBuffer;
}

- (TPXFrameBufferLayer *)fillFbLayerWithLength:(int)length  Xi:(unsigned char *) xi Yi:(unsigned char *)yi Ei:(unsigned char *)ei MaxTOT:(unsigned char)maxTOT CenterX:(float) centerX CenterY:(float) centerY Energy:(float)energy
{
    int firstFreeFb = [self findFirstFreeFb];
    NSLog(@"filling layer %i", firstFreeFb);
    TPXFrameBufferLayer * fBuffer = [self objectAtIndex:firstFreeFb];
    [CATransaction begin];
    [CATransaction setDisableActions: YES];
    fBuffer.anchorPoint = CGPointMake(centerX/256, centerY/256);
    [CATransaction commit];
    NSLog(@"anchor point %f %f", centerX/256,centerY/256 );
    for (int i = 0; i < length; i++) {
        [fBuffer setPixelWithX:xi[i] y:yi[i] counts:(unsigned char)floor(ei[i] * (MAX_COLORS)/(maxTOT+5)) ]; //scale tot to max color
    }
    fBuffer.isFree = false;
    
    //TODO: not used so far, remove properties?
    fBuffer.centerX = centerX;
    fBuffer.centerY = centerY;
    
    fBuffer.energy = energy;
    
//    CGRect r = fBuffer.frame;
//    r.origin.x = r.origin.x - (256/2) + centerX;
//    r.origin.y = r.origin.y - (256/2) + centerY;
//    fBuffer.frame = r;
//    CGPoint r = fBuffer.anchorPoint;
//    r.x = fBuffer.centerX;
//    r.y = fBuffer.centerY;
//    fBuffer.anchorPoint = r;


    return fBuffer;
}

- (int)findFirstFreeFb

{
    TPXFrameBufferLayer * fBuffer;
    int index;
    int i = 0;
    for(fBuffer in self){
        if (fBuffer.isFree){
            NSLog(@"layer %i is free", i);
            index=i;
            break;
        }
        else if (self.count == (i+1)){
            NSLog(@"Warning: No free frame buffer in array, overwriting first entry");
            index=0;
            break;
        }
        i++;
    }
    return index;
}

@end

@implementation NSString (NumberOfChars)

- (int)getNumberOfCharacters
{
    __block NSUInteger count =0;
    [self enumerateSubstringsInRange:NSMakeRange(0, [self length])
                             options:NSStringEnumerationByComposedCharacterSequences
                          usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
                                       count++;
                          }];
    return (int)count;
}

@end
