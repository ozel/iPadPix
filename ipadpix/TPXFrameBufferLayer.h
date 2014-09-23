//
//  TPXFrameBufferLayer.h
//  iPadPix
//
//  Created by Oliver Keller on 20.08.14.
//  Copyright (c) 2014 Apple Inc. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import <stdint.h>





@interface TPXFrameBufferLayer : CALayer {
}


// Class method to create a new layer with an underlying
// bitmap. Both will have the size set by the frame
+ (TPXFrameBufferLayer *)createLayerWithFrame:(CGRect)frame Index:(uint32_t) index;


+(uint32_t *)getPalette;

// Same as above
- (id)initWithFrame:(CGRect)frame;

// Draw bitmap to screen
- (void)blit;

// Set (x,y) pixel with TOT counts
- (void)setPixelWithX:(unsigned char)x y:(unsigned char)y counts:(unsigned char)counts;
- (void)setPixelRGBAWithX:(unsigned char)x y:(unsigned char)y counts:(unsigned char)counts;

// clear layer bitmap and blit
- (void)clear;

-(void)animateWithLensPosition:(float) lensPosition;

// Get the underlying context to use for higher-level
// drawing operations in Quartz
@property(readonly) CGContextRef context;

// Get the raw "frame buffer"
@property(readonly) uint32_t *framebuffer;

// mark buffers as free or used
@property bool isFree;

@property uint32_t index;
@property unsigned char centerX;
@property unsigned char centerY;
@property float energy;
@property uint32_t *palette_rgba;

@end

@interface NSMutableArray (TPXFrameBuffers)
//initialize color palette and FB array
+ (NSMutableArray *)initTPXFrameBuffersWithParentLayer:(CALayer *) parentLayer;

//initalize and append new frame buffer with parent layer.frame to FB array
//adds sub layer to parent layer
- (TPXFrameBufferLayer *)appendFbArrayWithParentLayer:(CALayer *)parentLayer Index:(uint32_t) index;

//fill layer with pixels
- (TPXFrameBufferLayer *)fillFbLayerWithLength:(int)length
                                           Xi:(unsigned char *) xi
                                           Yi:(unsigned char *)yi
                                           Ei:(unsigned char *)ei
                                       MaxTOT:(unsigned char) maxTOT
                                       CenterX:(float) centerX
                                       CenterY:(float) centerY
                                        Energy:(float) energy;

//find first free fb array index
-(int)findFirstFreeFb;

//@property int firstFreeFb;


@end

@interface NSString (NumberOfChars)

- (int)getNumberOfCharacters;

@end
