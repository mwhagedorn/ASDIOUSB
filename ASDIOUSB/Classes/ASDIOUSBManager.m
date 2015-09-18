//
//  LTIOUSBManager.m
//  LTIOUSB
//
//  Created by Yusuke Ito on 12/01/07.
//  Copyright (c) 2012 Yusuke Ito.
//  http://www.opensource.org/licenses/MIT
//

#import "ASDIOUSBManager.h"

#import <CoreFoundation/CoreFoundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/IOMessage.h>
#import <IOKit/IOCFPlugIn.h>
#import <IOKit/usb/IOUSBLib.h>
#import <IOKit/IOBSD.h>

#import "ASDIOUSBDevice.h"

void _ASDIOUSBDeviceAdded(void* context, io_iterator_t iterator);
void _ASDIOUSBDeviceRemoved(void* context, io_iterator_t iterator);


NSString* const ASDIOUSBDeviceConnectedNotification = @"ASDIOUSBDeviceAddedNotification";
NSString* const ASDIOUSBDeviceDisconnectedNotification = @"ASDIOUSBDeviceRemovedNotification";
NSString* const ASDIOUSBManagerObjectBaseClassKey = @"ASDIOUSBManagerObjectBaseClassKey";

#pragma mark - Callbacks

// context: object base class string
void _ASDIOUSBDeviceAdded(void* context, io_iterator_t iterator)
{
    ASDIOUSBManager* manager = [ASDIOUSBManager sharedInstance];
    Class objectClass = NSClassFromString((__bridge NSString*)context);

    io_service_t io_device = IO_OBJECT_NULL;

    NSMutableArray* addedDevices = [[NSMutableArray alloc] initWithCapacity:1];

	while((io_device = IOIteratorNext(iterator))) {
        NSString* identifier = [objectClass deviceIdentifier:io_device];
        ASDIOUSBDevice* device = [manager deviceWithIdentifier:identifier];
        if (! device) {
            device = [[objectClass alloc] initWithIdentifier:identifier];
            [manager addDevice:device];
        }
        [device setDeviceConnectedWithDevice:io_device];
        [addedDevices addObject:device];
    }

    if (addedDevices.count) {
        [[NSNotificationCenter defaultCenter] postNotificationName:ASDIOUSBDeviceConnectedNotification object:addedDevices];
    }
}

void _ASDIOUSBDeviceRemoved(void* context, io_iterator_t iterator)
{
    ASDIOUSBManager* manager = [ASDIOUSBManager sharedInstance];

    io_service_t io_device = IO_OBJECT_NULL;

    NSMutableArray* removed = [[NSMutableArray alloc] initWithCapacity:1];

	while((io_device = IOIteratorNext(iterator))) {
        for (ASDIOUSBDevice* device in manager.devices) {
            if ([device device] == io_device) {
                //NSLog(@"removed: %@", device);
                [device setDeviceDisconnected];
                [removed addObject:device];
            }
        }
    }

    // Remove device from list if allowed
    for (ASDIOUSBDevice* dev in removed) {
        if ([[dev class] removeFromDeviceListOnDisconnect]) {
            [manager removeDevice:dev];
        }
    }

    if (removed.count) {
        [[NSNotificationCenter defaultCenter] postNotificationName:ASDIOUSBDeviceDisconnectedNotification object:removed];
    }
}

@interface ASDIOUSBManager()
{
    NSMutableArray* _devices;
    BOOL _isStarted;
}
@end

@implementation ASDIOUSBManager

@synthesize devices = _devices;

+(id)sharedInstance
{
    static dispatch_once_t pred;
    static id obj = nil;

    dispatch_once(&pred, ^{ obj = [[self alloc] init]; });
    return obj;
}

- (id)init
{
    self = [super init];
    if (self) {
        _isStarted = NO;
        _devices = [[NSMutableArray alloc] init];
    }
    return self;
}

-(void)addDevice:(ASDIOUSBDevice *)device
{
    [_devices addObject:device];
}

-(void)removeDevice:(ASDIOUSBDevice *)device
{
    [_devices removeObjectIdenticalTo:device];
}

- (BOOL)startWithMatchingDictionaries:(NSArray*)matching;
{
    if (_isStarted) {
        // TODO: handle error
        return YES;
    }


    mach_port_t masterPort = 0;
	IOMasterPort(MACH_PORT_NULL, &masterPort);

    IONotificationPortRef notifyPort = IONotificationPortCreate(masterPort);
	CFRunLoopSourceRef runLoopSource = IONotificationPortGetRunLoopSource(notifyPort);
	CFRunLoopRef runLoop = CFRunLoopGetCurrent();
	CFRunLoopAddSource(runLoop, runLoopSource, kCFRunLoopDefaultMode);

    NSDictionary* deviceClassMatchingDict = [[NSDictionary alloc] initWithDictionary:(__bridge_transfer NSDictionary*)IOServiceMatching(kIOUSBDeviceClassName)];

    for (NSDictionary* dict in matching) {

        NSMutableDictionary* matchingDict = [dict mutableCopy];
        for (id key in deviceClassMatchingDict) {
            [matchingDict setObject:[deviceClassMatchingDict objectForKey:key] forKey:key];
        }

        CFStringRef objectBaseClassName = (__bridge_retained CFStringRef)[matchingDict objectForKey:ASDIOUSBManagerObjectBaseClassKey];

        // remove Object Base Class object, to use it matching dictionary
        [matchingDict removeObjectForKey:ASDIOUSBManagerObjectBaseClassKey];


        NSLog(@"matching dict: %@", matchingDict);

        io_iterator_t iterator = IO_OBJECT_NULL;
        kern_return_t kr = IOServiceAddMatchingNotification(notifyPort, kIOFirstMatchNotification, (__bridge_retained CFDictionaryRef)matchingDict, _ASDIOUSBDeviceAdded,
                                         (void*)objectBaseClassName, &iterator);
        if (kr != kIOReturnSuccess) {
            CFRelease(objectBaseClassName);
            return NO;
        }

        if (iterator) {
            _ASDIOUSBDeviceAdded((void*)objectBaseClassName, iterator);
            //IOObjectRelease(iterator);
        }

        iterator = IO_OBJECT_NULL;
        kr = IOServiceAddMatchingNotification(notifyPort, kIOTerminatedNotification, (__bridge_retained CFDictionaryRef)matchingDict, _ASDIOUSBDeviceRemoved,
                                         (void*)objectBaseClassName, &iterator);
        if (kr != kIOReturnSuccess) {
            CFRelease(objectBaseClassName);
            return NO;
        }
        if (iterator) {
            _ASDIOUSBDeviceRemoved((void*)objectBaseClassName, iterator);
            //IOObjectRelease(iterator);
        }
    }

    _isStarted = YES;
    return YES; // success
}

-(ASDIOUSBDevice*)deviceWithIdentifier:(NSString *)identifier
{
    for (ASDIOUSBDevice* device in _devices) {
        if ([[device identifier] isEqualToString:identifier]) {
            return device;
        }
    }

    return nil;
}


#pragma mark - Helpers

- (BOOL)startWithMatchingDictionary:(NSDictionary*)dict
{
    return [self startWithMatchingDictionaries:[NSArray arrayWithObject:dict]];
}

+ (NSMutableDictionary*)matchingDictionaryForProductID:(uint16_t)deviceID vendorID:(uint16_t)vendorID objectBaseClass:(Class)cls
{
    NSMutableDictionary* dict = [[NSMutableDictionary alloc] init];
    [dict setObject:NSStringFromClass(cls) forKey:ASDIOUSBManagerObjectBaseClassKey];

    [dict setObject:[NSNumber numberWithUnsignedShort:deviceID] forKey:[NSString stringWithUTF8String:kUSBProductID]];
    [dict setObject:[NSNumber numberWithUnsignedShort:vendorID] forKey:[NSString stringWithUTF8String:kUSBVendorID]];

    return dict;
}

+ (NSMutableDictionary*)matchingDictionaryWithDeviceClass:(uint16_t)deviceClass objectBaseClass:(Class)cls
{
  return [[NSMutableDictionary alloc] init];

}

+ (NSMutableDictionary*)matchingDictionaryForAllUSBDevicesWithObjectBaseClass:(Class)cls
{
    NSMutableDictionary* dict = [[NSMutableDictionary alloc] init];
    [dict setObject:NSStringFromClass(cls) forKey:ASDIOUSBManagerObjectBaseClassKey];

    return dict;
}


@end
