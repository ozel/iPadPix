//
//  SKView+TPXClusterView.m
//  iPadPix
//
//  Created by Oliver Keller on 22.09.14.
//  Copyright (c) 2014 Apple Inc. All rights reserved.
//

#import "TPXClusterView.h"

@implementation SKView (TPXClusterView)

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    UIView *hitView = [super hitTest:point withEvent:event];
    
    // If the hi\tView is THIS view, return nil and allow hitTest:withEvent: to
    // continue traversing the hierarchy to find the underlying view.
    if (hitView == self) {
        return nil;
    }
    // Else return the hitView (as it could be one of this view's buttons):
    return hitView;
}

@end

@implementation SKScene (TPXClusterScene)

- (void)didFinishUpdate
{
    int rand = arc4random() % 10 +1;
    [self childNodeWithName: @"//clusterField"].position = CGPointMake(rand, rand);
    [self centerOnNode: [self childNodeWithName: @"//camera"]];
}

- (void) centerOnNode: (SKNode *) node
{
    CGPoint cameraPositionInScene = [node.scene convertPoint:node.position fromNode:node.parent];
    node.parent.position = CGPointMake(node.parent.position.x - cameraPositionInScene.x,                                       node.parent.position.y - cameraPositionInScene.y);
}

@end
