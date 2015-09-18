//
//  LTIOUSBManager.h
//  LTIOUSB
//
//  Created by Yusuke Ito on 12/01/07.
//  Copyright (c) 2012 Yusuke Ito.
//  http://www.opensource.org/licenses/MIT
//

#import <Foundation/Foundation.h>
#import "ASDIOUSBDevice.h"

extern NSString* const ASDIOUSBDeviceConnectedNotification;
extern NSString* const ASDIOUSBDeviceDisconnectedNotification;
extern NSString* const ASDIOUSBManagerObjectBaseClassKey; // the value must be NSString



//@class LTIOUSBDevice;
@interface ASDIOUSBManager : NSObject

// Primitive
+ (ASDIOUSBManager*)sharedInstance;
- (BOOL)startWithMatchingDictionaries:(NSArray*)array; // return: not 0 is success
@property (nonatomic, strong, readonly) NSArray* devices; // LTIOUSBDevice or its subclass



// Helper
- (BOOL)startWithMatchingDictionary:(NSDictionary*)dict;

+ (NSMutableDictionary*)matchingDictionaryForProductID:(uint16_t)deviceID vendorID:(uint16_t)vendorID objectBaseClass:(Class)cls;
//+ (NSMutableDictionary*)matchingDictionaryWithDeviceClass:(uint16_t)deviceClass objectBaseClass:(Class)cls;
+ (NSMutableDictionary*)matchingDictionaryForAllUSBDevicesWithObjectBaseClass:(Class)cls;

@end





@interface ASDIOUSBManager(Private)

- (ASDIOUSBDevice*)deviceWithIdentifier:(NSString*)identifier;
- (void)addDevice:(ASDIOUSBDevice*)device;
- (void)removeDevice:(ASDIOUSBDevice*)device;

@end