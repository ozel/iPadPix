//
//  SKView+TPXClusterView.m
//  iPadPix
//
//  Created by Oliver Keller on 22.09.14.
//  Copyright (c) 2014 Apple Inc. All rights reserved.
//

#import "TPXClusterView.h"
#import "MotionManagerSingleton.h"


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

@implementation TPXClusterScene

#define START_SPEED 50
#define MAX_SPEED  100

// private properties

NSTimeInterval _lastUpdateTime;
NSTimeInterval _dt;
int _speed=START_SPEED;


- (void)didFinishUpdate
{
//    int rand = arc4random() % 10 +1;
//    [self childNodeWithName: @"//clusterField"].position = CGPointMake(rand, rand);
//    [self centerOnNode: [self childNodeWithName: @"//camera"]];
}

- (void) centerOnNode: (SKNode *) node
{
    CGPoint cameraPositionInScene = [node.scene convertPoint:node.position fromNode:node.parent];
    node.parent.position = CGPointMake(node.parent.position.x - cameraPositionInScene.x,                                       node.parent.position.y - cameraPositionInScene.y);
}

// Increase speed after touch event up to 5 times.
-(void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    if (_speed<MAX_SPEED && _speed>-MAX_SPEED) {
        _speed+=20;
    } else {
        _speed=START_SPEED;
    }
}

-(void)update:(NSTimeInterval)currentTime {
    
    // Needed for smooth scrolling. It's not guaranteed, that the update method is not called in fixed intervalls
    if (_lastUpdateTime) {
        _dt = currentTime - _lastUpdateTime;
    } else {
        _dt = 0;
    }
    _lastUpdateTime = currentTime;
    
    // Scroll
    if (self.clusters)
        [self.clusters scrollWith:_speed*_dt Dt:_dt];
    
}

@end

@implementation ClusterFieldNode

#define SPEED_FACTOR 2
#define ROTATION_FACTOR 1

CGSize _containerSize;
NSMutableArray* _directions;
NSMutableArray* _stepsizes;

-(id)initWithSize:(CGSize)size {
    _containerSize=size;
    // Initialize the Arrays to store the direction and stepsize information
    _directions = [[NSMutableArray alloc] init];
    _stepsizes = [[NSMutableArray alloc] init];
    
    return [self init];
}

// Infinite scrolling:
// - Scroll the backgrounds and switch back if the end or the start screen is reached
// - Speed depends on layer to simulate deepth
-(void)scrollWith:(float)speed Dt:(float)dt {
    
  
//    NSLog(@"Counts %i dMotionFactorX %f dMotionFactorY ",self.children.count,dMotionFactorX,dMotionFactorY);
    for (int i=0; i<self.children.count;i++) {
        
//        NSLog(@"%@",[self.children objectAtIndex:i]);
        SKSpriteNode *spriteNode = [self.children objectAtIndex:i];
//        NSMutableDictionary * userData = spriteNode.userData;
        
        CMAttitude * attitude = [spriteNode.userData objectForKey:@"attitude"];
        unsigned int count = [[spriteNode.userData valueForKey:@"count"] integerValue];
        float timeSinceRotation = [[spriteNode.userData valueForKey:@"timeSinceRotation"] floatValue];
        float energy = [[spriteNode.userData valueForKey:@"energy"] floatValue];
        
//        NSLog(@"attitude: %@",attitude);
        GLKVector3 vMotionVector = [MotionManagerSingleton getMotionVectorLPWithReference:attitude];
        //z=yaw= what we want to control x drift
        float dMotionFactorX=vMotionVector.z*SPEED_FACTOR;
        float dMotionFactorY=vMotionVector.y*SPEED_FACTOR;
        float dRotationRadians=vMotionVector.x*ROTATION_FACTOR;
        
        CGPoint parallaxPos;
        
        parallaxPos=spriteNode.position;
        
        //calc drift with fake 2.5D
        //higher engery cluster drift further because they are floating higher in the z plane
        parallaxPos.x+=speed * (spriteNode.size.width/256) * dMotionFactorX * energy/1000;
        
        parallaxPos.y+=speed * (spriteNode.size.height/256) * dMotionFactorY * energy/1000;
        
        //calc rotation with little delay to smooth animation
        if(count == 10){
            [spriteNode runAction: [SKAction rotateToAngle:-dRotationRadians duration:timeSinceRotation]];
            count = 0;
            timeSinceRotation = 0.0;
        } else {
            count++;
            timeSinceRotation+=dt;
        }
        [spriteNode.userData setValue:@(timeSinceRotation) forKey:@"timeSinceRotation"];
        [spriteNode.userData setValue:@(count) forKey:@"count"];

        //increment zPosition proportinal to cluster energy
        spriteNode.zPosition+=energy/1000;
        
        // Set the new position
        spriteNode.position = parallaxPos;
    }
}


@end

