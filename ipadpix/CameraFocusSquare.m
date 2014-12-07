//
//  CameraFocusSquare.m
//  AVCamManual
//
//  Created by Oliver Keller on 02.07.14.
//  Copyright (c) 2014 Apple Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CameraFocusSquare.h"

const float squareLength = 80.0f;
@implementation CameraFocusSquare

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code
        
        [self setBackgroundColor:[UIColor clearColor]];
        [self.layer setBorderWidth:2.0];
        [self.layer setCornerRadius:4.0];
        [self.layer setBorderColor:[UIColor whiteColor].CGColor];
        
        CABasicAnimation* selectionAnimation = [CABasicAnimation
                                                animationWithKeyPath:@"borderColor"];
        selectionAnimation.toValue = (id)[UIColor yellowColor].CGColor;
        selectionAnimation.repeatCount = 8;
        [self.layer addAnimation:selectionAnimation
                          forKey:@"selectionAnimation"];
        
    }
    return self;
}


@end