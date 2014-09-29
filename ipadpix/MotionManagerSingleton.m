//
//  MotionManagerSingleton.m
//
//
//  Created by  Oliver Keller on 23.09.14.
//  Copyright (c) 2014 Oliver Keller. All rights reserved.
//


#import "MotionManagerSingleton.h"

// Damping factor
#define LP_FACTOR 0.99

#define radiansToDegrees(x) (180/M_PI)*x

@implementation MotionManagerSingleton

static CMMotionManager* _motionManager;
static CMAttitude* _referenceAttitude;
static bool bActive;

// only one instance of CMMotionManager can be used in your project.
// => Implement as Singleton which can be used in the whole application
+(CMMotionManager*)getMotionManager {
    if (_motionManager==nil) {
        _motionManager=[[CMMotionManager alloc]init];
        _motionManager.deviceMotionUpdateInterval=0.1; //0.25;
        [_motionManager startDeviceMotionUpdates];
        bActive=true;
    } else if (bActive==false) {
        [_motionManager startDeviceMotionUpdates];
        bActive=true;
    }
    return _motionManager;
}

// Returns a vector with the orientation values
// At the first time a reference orientation is saved to ensure the motion detection works for multiple device positions
+(GLKVector3)getMotionVectorLPWithReference:(CMAttitude *)referenceAttitude{
    // Motion
    CMAttitude *attitude = self.getMotionManager.deviceMotion.attitude;
    if(referenceAttitude){
        [attitude multiplyByInverseOfAttitude:referenceAttitude];
    }
    CMQuaternion quat = attitude.quaternion;
    float myRoll = atan2(2*(quat.y*quat.w - quat.x*quat.z), 1 - 2*quat.y*quat.y - 2*quat.z*quat.z) ;
    float myPitch = atan2(2*(quat.x*quat.w + quat.y*quat.z), 1 - 2*quat.x*quat.x - 2*quat.z*quat.z);
    float myYaw = asin(2*quat.x*quat.y + 2*quat.w*quat.z);
    
//    if (_referenceAttitude==nil) {
//        // Cache Start Orientation to calibrate the device. Wait for a short time to give MotionManager enough time to initialize
//        [self performSelector:@selector(calibrate) withObject:nil afterDelay:0.25];
//        
//    } else {
//        // Use start orientation to calibrate
//        [attitude multiplyByInverseOfAttitude:_referenceAttitude];
////        NSLog(@"roll: %f", attitude.roll);
//    }

    return [self lowPassWithVector: GLKVector3Make(myYaw,myRoll,myPitch)];
}

+(void)calibrate {
    if (_motionManager){
        _referenceAttitude = [self.getMotionManager.deviceMotion.attitude copy];
        NSLog(@"Calibrated CoreMotion");
    }
}

+(CMAttitude *)getAttitude {
    if (_motionManager){
        return self.getMotionManager.deviceMotion.attitude;
    }
    else {
        return nil;
    }
}

// Stop collecting motion data to save energy
+(void)stop {
    if (_motionManager!=nil) {
        [_motionManager stopDeviceMotionUpdates];
        _referenceAttitude=nil;
        bActive=false;
    }
}

// Damp the jitter caused by hand movement
+(GLKVector3)lowPassWithVector:(GLKVector3)vector
{
    static GLKVector3 lastVector;
    
    if(fabsf(vector.x) < 0.01)
        vector.x= 0.0;
    if(fabsf(vector.y) < 0.01)
        vector.y= 0.0;
    if(fabsf(vector.z) < 0.01)
        vector.z= 0.0;
    
    vector.x = vector.x * LP_FACTOR + lastVector.x * (1.0 - LP_FACTOR);
    vector.y = vector.y * LP_FACTOR + lastVector.y * (1.0 - LP_FACTOR);
    vector.z = vector.z * LP_FACTOR + lastVector.z * (1.0 - LP_FACTOR);
    
//    NSLog(@"filtered x %.2f y %.2f z %.2f", vector.x,vector.y,vector.z);

    
    lastVector = vector;
    return vector;
}

@end
