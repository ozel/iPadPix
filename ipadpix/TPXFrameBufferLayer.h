//
//  TPXFrameBufferLayer.h
//  iPadPix
//
//  Created by Oliver Keller on 20.08.14.
//  Copyright (c) 2014 Apple Inc. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import <stdint.h>

@interface TPXFrameBufferLayer : CALayer

// Class method to create a new layer with an underlying
// bitmap. Both will have the size set by the frame
+ (TPXFrameBufferLayer *)paletteLayerWithFrame:(CGRect)frame;
// Same as above
- (id)initWithFrame:(CGRect)frame;

// Draw bitmap to screen
- (void)blit;

// Set (x,y) pixel with TOT counts
- (void)setPixelWithX:(int)x y:(int)y counts:(int)counts;

// clear layer bitmap and blit
- (void)clear;

// Get the underlying context to use for higher-level
// drawing operations in Quartz
@property(readonly) CGContextRef context;

// Get the raw "frame buffer"
@property(readonly) uint32_t *framebuffer;

@end