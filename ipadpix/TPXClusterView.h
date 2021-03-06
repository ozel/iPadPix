//
//  SKView+TPXClusterView.h
//  iPadPix
//
//  Created by Oliver Keller on 22.09.14.
//  Copyright (c) 2014 Oliver Keller. All rights reserved.
//

#import <SpriteKit/SpriteKit.h>

@interface SKView (TPXClusterView)

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event;

@end

@interface ClusterFieldNode : SKSpriteNode

-(id)initWithSize:(CGSize)size;
-(void)scrollWith:(float)speed Dt:(float)dt;


@end

@interface  TPXClusterScene : SKScene

- (void)addLabelContainer;
- (NSUInteger)getLabelCount;
- (void)addLabelForNode:(SKNode*)node;

@property ClusterFieldNode * clusters;


@end

@interface SKNode (SKmyNodes)

- (void)cleanUpChildrenAndRemove:(SKNode*)node;

@end
