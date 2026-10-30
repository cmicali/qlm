#import "QLMHostCheck.h"

#import <IOKit/IOKitLib.h>
#import <IOKit/hid/IOHIDKeys.h>

#include <libproc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "QLMReport.h"

BOOL QLMHostCheckIsGLMExecutable(NSString *path) {
    return [path rangeOfString:@"/GLMv5.app/Contents/MacOS/"].location != NSNotFound;
}

BOOL QLMHostCheckParseCreator(NSString *creator, pid_t *pid, NSString **name) {
    const char *text = creator.UTF8String;
    int value = 0;
    int consumed = -1;
    if (text == NULL || sscanf(text, "pid %d, %n", &value, &consumed) != 1 || consumed < 0 || value <= 0) {
        return NO;
    }
    if (pid != NULL) {
        *pid = value;
    }
    if (name != NULL) {
        *name = [NSString stringWithUTF8String:text + consumed] ?: @"";
    }
    return YES;
}

NSString *QLMHostCheckGLMProcess(void) {
    int count = proc_listallpids(NULL, 0);
    if (count <= 0) {
        return nil;
    }
    int capacity = count + 64;
    pid_t *pids = calloc((size_t)capacity, sizeof(pid_t));
    if (pids == NULL) {
        return nil;
    }
    count = proc_listallpids(pids, capacity * (int)sizeof(pid_t));
    pid_t me = getpid();
    NSString *found = nil;
    for (int i = 0; i < count && found == nil; i++) {
        if (pids[i] <= 0 || pids[i] == me) {
            continue;
        }
        char path[PROC_PIDPATHINFO_MAXSIZE];
        if (proc_pidpath(pids[i], path, sizeof path) <= 0) {
            continue;
        }
        NSString *executable = [NSString stringWithUTF8String:path];
        if (executable != nil && QLMHostCheckIsGLMExecutable(executable)) {
            found = [NSString stringWithFormat:@"GLM is running (pid %d, %@). Quit GLM first.", pids[i], executable];
        }
    }
    free(pids);
    return found;
}

CFMutableDictionaryRef QLMHostCheckCreateHIDMatching(void) {
    CFMutableDictionaryRef matching = IOServiceMatching(kIOHIDDeviceKey);
    NSDictionary *properties = @{
        @kIOHIDVendorIDKey: @(QLMAdapterVendorID),
        @kIOHIDProductIDKey: @(QLMAdapterProductID),
        @kIOHIDPrimaryUsagePageKey: @(QLMAdapterUsagePage),
    };
    CFDictionarySetValue(matching, CFSTR(kIOPropertyMatchKey), (__bridge CFDictionaryRef)properties);
    return matching;
}

static CFMutableDictionaryRef QLMHostCheckCreateUSBMatching(void) {
    CFMutableDictionaryRef matching = IOServiceMatching("IOUSBHostDevice");
    NSDictionary *properties = @{@"idVendor": @(QLMAdapterVendorID), @"idProduct": @(QLMAdapterProductID)};
    CFDictionarySetValue(matching, CFSTR(kIOPropertyMatchKey), (__bridge CFDictionaryRef)properties);
    return matching;
}

// A creator's process name, cut to 16 characters.
static BOOL QLMHostCheckIsGLMName(NSString *name) {
    return [name hasPrefix:@"GLMv5"];
}

static NSString *QLMHostCheckHolder(NSString *name, pid_t pid) {
    if (QLMHostCheckIsGLMName(name)) {
        return [NSString stringWithFormat:@"GLM is running (pid %d). Quit GLM first.", pid];
    }
    return [NSString stringWithFormat:@"%@ (pid %d) holds the GLM adapter.", name, pid];
}

// Only a boolean No counts, so a missing or odd value counts as a holder.
static BOOL QLMHostCheckIsNo(id _Nullable value) {
    return value == (__bridge id)kCFBooleanFalse;
}

NSString *QLMHostCheckClientHolder(NSString *className, NSDictionary *properties, pid_t me) {
    id creator = properties[@"IOUserClientCreator"];
    pid_t pid = 0;
    NSString *name = nil;
    if (![creator isKindOfClass:[NSString class]] || !QLMHostCheckParseCreator(creator, &pid, &name)) {
        return @"A client of unknown origin holds the GLM adapter.";
    }
    if (pid == me) {
        return nil;
    }
    if (!QLMHostCheckIsGLMName(name)) {
        if ([className isEqualToString:@"AppleUSBHostDeviceUserClient"] ||
            [className isEqualToString:@"AppleUSBHostInterfaceUserClient"]) {
            return nil;
        }
        if ([className isEqualToString:@"IOHIDLibUserClient"]) {
            id state = properties[@"DebugState"];
            if ([state isKindOfClass:[NSDictionary class]] && QLMHostCheckIsNo(state[@"ClientOpened"]) &&
                QLMHostCheckIsNo(state[@"ClientSeized"])) {
                return nil;
            }
        }
    }
    return QLMHostCheckHolder(name, pid);
}

NSString *QLMHostCheckEntryOwner(NSDictionary *properties, pid_t me) {
    id owner = properties[@"UsbExclusiveOwner"];
    if (owner == nil || ([owner isKindOfClass:[NSString class]] && ![owner hasPrefix:@"pid "])) {
        return nil;
    }
    pid_t pid = 0;
    NSString *name = nil;
    if (![owner isKindOfClass:[NSString class]] || !QLMHostCheckParseCreator(owner, &pid, &name)) {
        return @"A process of unknown origin has opened the GLM adapter.";
    }
    return pid == me ? nil : QLMHostCheckHolder(name, pid);
}

static NSDictionary *QLMHostCheckProperties(io_registry_entry_t entry, NSArray<NSString *> *keys) {
    NSMutableDictionary *properties = [NSMutableDictionary dictionary];
    for (NSString *key in keys) {
        id value = CFBridgingRelease(IORegistryEntryCreateCFProperty(entry, (__bridge CFStringRef)key, kCFAllocatorDefault, 0));
        if (value != nil) {
            properties[key] = value;
        }
    }
    return properties;
}

// The entry's own holder, or nil.
static NSString *_Nullable QLMHostCheckHolderOf(io_registry_entry_t entry, pid_t me) {
    if (!IOObjectConformsTo(entry, "IOUserClient")) {
        return QLMHostCheckEntryOwner(QLMHostCheckProperties(entry, @[@"UsbExclusiveOwner"]), me);
    }
    io_name_t className;
    NSString *name = IOObjectGetClass(entry, className) == KERN_SUCCESS ? @(className) : @"";
    return QLMHostCheckClientHolder(name, QLMHostCheckProperties(entry, @[@"IOUserClientCreator", @"DebugState"]), me);
}

// The first holder at or below the entry.
static NSString *_Nullable QLMHostCheckHolderBelow(io_registry_entry_t entry, pid_t me) {
    NSString *found = QLMHostCheckHolderOf(entry, me);
    io_iterator_t iterator = IO_OBJECT_NULL;
    if (found != nil ||
        IORegistryEntryCreateIterator(entry, kIOServicePlane, kIORegistryIterateRecursively, &iterator) != KERN_SUCCESS) {
        return found;
    }
    io_registry_entry_t child;
    while ((child = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        if (found == nil) {
            found = QLMHostCheckHolderOf(child, me);
        }
        IOObjectRelease(child);
    }
    IOObjectRelease(iterator);
    return found;
}

// Consumes the matching dictionary.
static NSString *_Nullable QLMHostCheckHolderOfMatches(CFMutableDictionaryRef matching, pid_t me) {
    io_iterator_t services = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, matching, &services) != KERN_SUCCESS) {
        return nil;
    }
    NSString *found = nil;
    io_service_t service;
    while ((service = IOIteratorNext(services)) != IO_OBJECT_NULL) {
        if (found == nil) {
            found = QLMHostCheckHolderBelow(service, me);
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(services);
    return found;
}

NSString *QLMHostCheckAdapterClients(void) {
    pid_t me = getpid();
    return QLMHostCheckHolderOfMatches(QLMHostCheckCreateUSBMatching(), me)
               ?: QLMHostCheckHolderOfMatches(QLMHostCheckCreateHIDMatching(), me);
}

NSString *QLMHostCheckOtherHost(void) {
    return QLMHostCheckGLMProcess() ?: QLMHostCheckAdapterClients();
}
