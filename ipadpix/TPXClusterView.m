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

- (NSUInteger)getLabelCount
{
    return [labels.children count];
}

- (void)addLabelForNode:(SKNode*)node
{
    //without dispatching this, the removing of labels terminates the app from time to time
    dispatch_async(dispatch_get_main_queue(), ^{

        SKLabelNode *energyLabel = [SKLabelNode labelNodeWithFontNamed:@"Menlo-Regular"];
        energyLabel.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
        //NOTE userData must be pre-initialized before
        [node.userData setObject:energyLabel forKey:@"energyLabel"];

        float energy = [[node.userData valueForKey:@"energy"] floatValue];
        energyLabel.text = [NSString stringWithFormat:@"%.1f keV", energy];
        energyLabel.fontSize = 20;
        energyLabel.position = node.position; //just as intial position
        energyLabel.userData = [NSMutableDictionary new];
        
        SKSpriteNode* underline = [SKSpriteNode spriteNodeWithColor:[SKColor whiteColor] size:CGSizeMake(125, 2.0)];
        //        [line setPosition:CGPointMake(136.0, 50.0)];
        underline.alpha = 0.5;
        underline.zPosition = 0;
        energyLabel.zPosition = 1;
        [energyLabel addChild:underline];
        [node.userData setObject:underline forKey:@("underline")];

        SKSpriteNode* pointerline = [SKSpriteNode spriteNodeWithColor:[SKColor whiteColor] size:CGSizeMake(100, 2.0)];
        pointerline.alpha = 0.4;
    
        pointerline.zPosition = 0;
        [energyLabel addChild:pointerline];
        [node.userData setObject:pointerline forKey:@("pointerline")];
        NSMutableArray *lineConstraints = [NSMutableArray new];
    
        [lineConstraints addObject:[SKConstraint orientToPoint:CGPointMake(0,0) inNode:node offset:[SKRange rangeWithConstantValue:0]]];
        pointerline.constraints = lineConstraints;
    
        //cluster type
        SKLabelNode *typeLabel = [SKLabelNode labelNodeWithFontNamed:@"Menlo-Italic"];
        typeLabel.verticalAlignmentMode = SKLabelVerticalAlignmentModeCenter;
        typeLabel.text = node.name;
        typeLabel.fontSize = 40;
        typeLabel.zPosition = 1;
        typeLabel.position = CGPointMake(0, -22);

        if([node.name isEqualToString:@"alpha"]){
            typeLabel.fontColor=[SKColor redColor];
            typeLabel.text= @"\u03B1";
        }else if ([node.name isEqualToString:@"beta"]){
            typeLabel.fontColor=[SKColor orangeColor];
            typeLabel.text= @"\u03B2";
        }else if ([node.name isEqualToString:@"gamma"]){
            typeLabel.fontColor=[SKColor yellowColor];
            typeLabel.text= @"\u03B3";
        }else if ([node.name isEqualToString:@"beta/gamma"]){
            typeLabel.text= @"\u03B2/\u03B3";
        }

        
        [energyLabel addChild:typeLabel];

        float duration = [[node.userData valueForKey:@"duration"] floatValue];

    //    zoom.timingMode = SKActionTimingEaseOut;
        SKAction * fade = [SKAction fadeAlphaTo:0.3 duration:duration+0.1];
        fade.timingMode = SKActionTimingEaseIn;
        NSMutableArray *constraints = [NSMutableArray new];

//        SKRange* range = [SKRange rangeWithConstantValue:0.0f];
        
 
        
        SKConstraint *leftPosition = [SKConstraint positionX:[SKRange rangeWithConstantValue:-508] Y:[SKRange rangeWithLowerLimit:-(768/2)+20 upperLimit:(768/2)-20] ];
        
        SKConstraint *rightPosition = [SKConstraint positionX:[SKRange rangeWithConstantValue:+508] Y:[SKRange rangeWithLowerLimit:-(768/2)+20 upperLimit:(768/2)-20] ];

        if(node.position.x < 0) {
            [rightPosition setEnabled:NO];
            [energyLabel.userData setValue:@"left" forKey:@("position")];
        } else {
            [leftPosition setEnabled:NO];
            [energyLabel.userData setValue:@"right" forKey:@("position")];

        }
        [constraints addObject:leftPosition];
        [constraints addObject:rightPosition];
    
        SKConstraint* clusterDistance = [SKConstraint distance:[SKRange rangeWithLowerLimit:40 upperLimit:250] toPoint:CGPointMake(0,0) inNode:node];
        [constraints addObject:clusterDistance];
    
    
        //keep distance from other labels
        for (SKNode *labelNode in labels.children ){
            id position = [energyLabel.userData valueForKey:@"position"];
            if (position == [labelNode.userData valueForKey:@"position"]){
                SKConstraint* minLabelDistance = [SKConstraint distance:[SKRange rangeWithLowerLimit:100] toPoint:CGPointMake(0,0) inNode:labelNode];
                [constraints addObject:minLabelDistance];
            }
        }

        //keep distance from other clusters
        for (SKNode *clusterNode in node.parent.children ){
            if (clusterNode != node){
                SKConstraint* minClusterDistance = [SKConstraint distance:[SKRange rangeWithLowerLimit:150] toPoint:CGPointMake(0,0) inNode:clusterNode];
                [constraints addObject:minClusterDistance];
            }
        }
//

    
        energyLabel.constraints = constraints;

        [energyLabel runAction: [SKAction sequence:@[fade]]];
//        [CATransaction begin];
//        [CATransaction setDisableActions: YES];
        [labels addChild:energyLabel];
//        [CATransaction commit];
        //label will be removed in SKview update loop
        

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

long int distanceBetweenPoints(CGPoint first, CGPoint second) {
    return lroundf(hypotf(second.x - first.x, second.y - first.y));
}

-(void)update:(NSTimeInterval)currentTime {
    
    // Needed for smooth scrolling. It's not guaranteed, that the update method is not called in fixed intervalls
    if (_lastUpdateTime) {
        _dt = currentTime - _lastUpdateTime;
    } else {
        _dt = 0;
    }
    _lastUpdateTime = currentTime;
    
//    [CATransaction begin];
//    [CATransaction setDisableActions: YES];
    
    // Scroll
    if (self.clusters)
        [self.clusters scrollWith:_speed*_dt Dt:_dt];
    
    for (SKLabelNode *label in labels.children){
        if (label.alpha < 0.4){
            [label removeAllActions];
            [label removeAllChildren];
            [label removeFromParent];
        }
    }
    
//    for (SKSpriteNode *sprite in self.clusters.children){
//        if (sprite.alpha <= 0.1){
//            [sprite removeAllActions];
//            [sprite removeAllChildren];
//            [sprite removeFromParent];
//        }
//    }
    
   
    
    //update labels
    for (SKNode *node in self.clusters.children) {
        SKLabelNode *infoLabel = (SKLabelNode*)[node.userData objectForKey:@"energyLabel"];
        if (infoLabel) {
            if (node.position.x < (0)){
                SKSpriteNode *line = (SKSpriteNode*)[node.userData objectForKey:@"underline"];
                line.anchorPoint = (CGPointMake(0,0));

                line = (SKSpriteNode*)[node.userData objectForKey:@"pointerline"];
                line.size = CGSizeMake(distanceBetweenPoints(node.position, CGPointMake(infoLabel.position.x+125, infoLabel.position.y)), 2);
                line.anchorPoint = (CGPointMake(0,0));
                [line setPosition:CGPointMake(+125, 0)];

                
                infoLabel.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeLeft;
                if ([infoLabel.children count] > 1) {
                    SKLabelNode *typeLabel = [infoLabel.children objectAtIndex:3];
                    typeLabel.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeLeft;
                }
//                infoLabel.position = CGPointMake(-self.size.width/2, node.position.y);
                //enable left position constraint
                [[infoLabel.constraints objectAtIndex:0] setEnabled:YES];
                [[infoLabel.constraints objectAtIndex:1] setEnabled:NO];
            } else {
                SKSpriteNode *line = (SKSpriteNode*)[node.userData objectForKey:@"underline"];
                line.anchorPoint = CGPointMake(1, 0);

                line = (SKSpriteNode*)[node.userData objectForKey:@"pointerline"];
                line.size = CGSizeMake(distanceBetweenPoints(node.position, CGPointMake(infoLabel.position.x-125, infoLabel.position.y)), 2);
                line.anchorPoint = (CGPointMake(0,1));
                [line setPosition:CGPointMake(-125, 0)];

                
                if ([infoLabel.children count] > 1) {
                    SKLabelNode *typeLabel = [infoLabel.children objectAtIndex:3];
                    typeLabel.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeRight;
                }
                infoLabel.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeRight;
                //enable right position constraint
                [[infoLabel.constraints objectAtIndex:0] setEnabled:NO];
                [[infoLabel.constraints objectAtIndex:1] setEnabled:YES];

                
//                infoLabel.position = CGPointMake(self.size.width/2, node.position.y);
            }
        }
//        [CATransaction commit];
//        infoLabel = (SKLabelNode*)[node.userData objectForKey:@"typeLabel"];
//        if (infoLabel) {
//            if (node.position.x < (0)){
//                infoLabel.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeLeft;
//                infoLabel.position = CGPointMake(-self.size.width/2, node.position.y-40);
//            } else {
//                infoLabel.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeRight;
//                infoLabel.position = CGPointMake(self.size.width/2, node.position.y-40);
//            }
//        }
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
