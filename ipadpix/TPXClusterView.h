//
//  SKView+TPXClusterView.h
//  iPadPix
//
//  Created by Oliver Keller on 22.09.14.
//  Copyright (c) 2014 Apple Inc. All rights reserved.
//

#import <SpriteKit/SpriteKit.h>

@interface SKView (TPXClusterView)

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event;

@end
