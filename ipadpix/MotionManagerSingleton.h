//
//  MotionManagerSingleton.h
//  
//
//  Created by Oliver Keller on 23.09.14.
//  Copyright (c) 2014 Oliver Keller. All rights reserved.
//

#import <CoreMotion/CoreMotion.h>
#import <GLKit/GLKit.h>

@interface MotionManagerSingleton : NSObject

+(GLKVector3)getMotionVectorLPWithReference:(CMAttitude *)referenceAttitude;
+(void)stop;
+(void)calibrate;
+(CMAttitude *)getAttitude;


@end
