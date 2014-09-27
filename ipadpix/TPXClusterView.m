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
   CGRect frame = CGRectMake(0, 40,
                              self.frame.size.width,
                              self.frame.size.height - 40);
    
    if (CGRectContainsPoint(frame, point)) {
        return self;
    }

    // Else return the hitView (as it could be one of this view's buttons):
    return nil;
}

@end

@implementation TPXClusterScene

#define START_SPEED 50
#define MAX_SPEED  100

// private properties

NSTimeInterval _lastUpdateTime;
NSTimeInterval _dt;
int _speed=START_SPEED;

// Add a container as a scene instance variable.
SKNode *labels;

- (void)addLabelContainer
{
    labels = [SKNode node];
    [self addChild:labels];
}

- (void)addLabelForNode:(SKNode*)node labelKey:(id)key
{
    //without dispatching this, the removing of labels terminates the app from time to time
    dispatch_async(dispatch_get_main_queue(), ^{

        SKLabelNode *label = [SKLabelNode labelNodeWithFontNamed:@"Menlo-Regular"];
        label.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
        //NOTE userData must be pre-initialized before
        [node.userData setObject:label forKey:key];

        if(key == (id)@"energyLabel"){
            float energy = [[node.userData valueForKey:@"energy"] floatValue];
            label.text = [NSString stringWithFormat:@"%.1f eV", energy];
            label.fontSize = 20;
            
            SKSpriteNode* line = [SKSpriteNode spriteNodeWithColor:[SKColor whiteColor] size:CGSizeMake(128, 2.0)];
            //        [line setPosition:CGPointMake(136.0, 50.0)];
            line.alpha = 0.5;
            line.zPosition = 0;
            [label addChild:line];
            [node.userData setObject:line forKey:@("line")];

            
        } else {
            //cluster type
            label.text = node.name;
            label.fontSize = 40;

        }
        label.zPosition = 100000;

        [labels addChild:label];
        float duration = [[node.userData valueForKey:@"duration"] floatValue];

    //    zoom.timingMode = SKActionTimingEaseOut;
        SKAction * fade = [SKAction fadeAlphaTo:0.3 duration:duration+0.1];
        fade.timingMode = SKActionTimingEaseIn;
//        SKAction *remove = [SKAction removeFromParent];
        SKAction * remove = [SKAction  runBlock:^{
          [label removeAllChildren];
          [label removeFromParent];
        }];
        [label runAction: [SKAction sequence:@[fade, remove]]];
        

    });
}

- (void)removeLabelForNode:(SKNode*)node
{
    [[node.userData objectForKey:@"label"] removeFromParent];
    [node.userData removeObjectForKey:@"label"];
}

- (void)didFinishUpdate
{
//    int rand = arc4random() % 10 +1;
//    [self childNodeWithName: @"//clusterField"].position = CGPointMake(rand, rand);
//    [self centerOnNode: [self childNodeWithName: @"//camera"]];
}

- (void) centerOnNode: (SKNode *) node
{
//    CGPoint cameraPositionInScene = [node.scene convertPoint:node.position fromNode:node.parent];
//    node.parent.position = CGPointMake(node.parent.position.x - cameraPositionInScene.x,                                       node.parent.position.y - cameraPositionInScene.y);
}

-(void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    //    if (_speed<MAX_SPEED && _speed>-MAX_SPEED) {
//        _speed+=20;
//    } else {
//        _speed=START_SPEED;
//    }

//    if(self.scene.view.paused==YES)
//        self.scene.view.paused = NO;
//    else
//        self.scene.view.paused = YES;

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
    
    //update labels
    for (SKNode *node in self.clusters.children) {
        SKLabelNode *infoLabel = (SKLabelNode*)[node.userData objectForKey:@"energyLabel"];
        if (infoLabel) {
            if (node.position.x < (0)){
                SKSpriteNode *line = (SKSpriteNode*)[node.userData objectForKey:@"line"];
                line.anchorPoint = (CGPointMake(0,0));
                line.size = CGSizeMake((self.size.width/2)+node.position.x, 2);
                
                infoLabel.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeLeft;
                infoLabel.position = CGPointMake(-self.size.width/2, node.position.y);
            } else {
                SKSpriteNode *line = (SKSpriteNode*)[node.userData objectForKey:@"line"];
                line.anchorPoint = CGPointMake(1, 0);
                line.size = CGSizeMake((self.size.width/2)-node.position.x, 2);
                
                infoLabel.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeRight;
                infoLabel.position = CGPointMake(self.size.width/2, node.position.y);
            }
        }
        infoLabel = (SKLabelNode*)[node.userData objectForKey:@"typeLabel"];
        if (infoLabel) {
            if (node.position.x < (0)){
                infoLabel.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeLeft;
                infoLabel.position = CGPointMake(-self.size.width/2, node.position.y-40);
            } else {
                infoLabel.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeRight;
                infoLabel.position = CGPointMake(self.size.width/2, node.position.y-40);
            }
        }
    }
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

@implementation SKNode (SKmyNodes)

- (void)cleanUpChildrenAndRemove:(SKNode*)node {
    for (SKNode *child in node.children) {
        [self cleanUpChildrenAndRemove:child];
    }
    [node removeFromParent];
}
@end
