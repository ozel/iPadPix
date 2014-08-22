//
//  RSFrameBufferLayer.m
//  iPadPix
//
//  Created by Oliver Keller on 20.08.14.
//  Copyright (c) 2014 Apple Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIColor.h>
#import "RSFrameBufferLayer.h"

@implementation RSFrameBufferLayer
@synthesize context = _context;

#define MAX_COLORS 256

#define HOT_SATURATION_VAL     1
#define HOT_MAXLIGHTNESS_VAL   0.47
#define HOT_MINLIGHTNESS_VAL   1
#define HOT_MAXHUE_VAL         330
#define HOT_MINHUE_VAL         360

uint32_t palette[MAX_COLORS];
uint32_t * framebuffer;
int localFrameWidth;
int localFrameHeight;

+ (RSFrameBufferLayer *)paletteLayerWithFrame:(CGRect)frame
{
    //init color palette
    //based on HOT palette from mafalda/MPXViewer/MPXViewer.cpp
    CGFloat brightness, hue, saturation, Maxlightness, Minlightness, MaxHue, MinHue, alpha, red, green, blue;

    saturation = HOT_SATURATION_VAL;
    Maxlightness = HOT_MAXLIGHTNESS_VAL;
    Minlightness = HOT_MINLIGHTNESS_VAL;
    MaxHue = HOT_MAXHUE_VAL;
    MinHue = HOT_MINHUE_VAL;
    alpha=1.0;
    
    for(int i = 0; i < MAX_COLORS; i++){
        brightness = Maxlightness-(i+1)*((Maxlightness-Minlightness)/MAX_COLORS);
        hue = MaxHue-(i+1)*((MaxHue-MinHue)/MAX_COLORS);
        UIColor *color = [UIColor colorWithHue: hue saturation: saturation
                                    brightness: brightness alpha: alpha];
        [color getRed: &red green: &green blue: &blue alpha: &alpha];
        //NSLog(@"red %f, green %f, blue %f", red, green, blue);

        palette[i] = ((int)floor(alpha*255.0)) << (3*8) |
        ((int)floor(red  *255.0)) << (2*8) |
        ((int)floor(green*255.0)) << (1*8) |
        ((int)floor(blue *255.0));
    }
    return [[RSFrameBufferLayer alloc] initWithFrame:frame];
    
}

- (id)initWithFrame:(CGRect)frame
{
    if (self=[super init]){
        self.opaque = NO; //YES
        self.frame=frame;
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

- (void)setPixelWithX:(int)x y:(int)y counts:(int)counts
{
    framebuffer[(y * localFrameWidth) + x] = palette[counts];
}

-(void)clear
{
    for(int i = 0; i < (localFrameWidth * localFrameHeight); i++){
        framebuffer[i]=0x00000000;
    }
    [self blit];
}

-(void)setFrame:(CGRect)frame
{
    CGRect oldframe = self.frame;
    [super setFrame:frame];
    if (frame.size.width != oldframe.size.width ||
        frame.size.height != oldframe.size.height){
        NSLog(@"new frame width: %d, height: %d", (int)frame.size.width, (int)frame.size.height);
        if (_context){
            CGContextRelease(_context);
        }
        CGColorSpaceRef csp = CGColorSpaceCreateDeviceRGB();
        _context = CGBitmapContextCreate(NULL,
                                         (size_t)frame.size.width,
                                         (size_t)frame.size.height, 8,
                                         4*(size_t)frame.size.width, csp,
                                         (CGBitmapInfo)kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
//                                         (CGBitmapInfo)kCGBitmapByteOrder32Little |kCGImageAlphaNoneSkipFirst);
        CGContextSetShouldAntialias(_context, NO);
        CGContextSetAllowsAntialiasing(_context, NO);
        CGContextSetInterpolationQuality(_context, kCGInterpolationHigh);
        CGColorSpaceRelease(csp);
        framebuffer = CGBitmapContextGetData(_context);
        //self.frame is not in sync with actual frame width so we save it here
        localFrameWidth=(int)frame.size.width;
        localFrameHeight=(int)frame.size.height;
    }
}

-(uint32_t *)framebuffer
{
    return CGBitmapContextGetData(_context);
}


@end