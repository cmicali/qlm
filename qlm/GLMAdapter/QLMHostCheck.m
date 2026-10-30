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

// The first user client below the entry that another process created.
// TRAP: a user client with no readable creator counts, so an unknown holder
// is refused rather than ignored.
static NSString *_Nullable QLMHostCheckClientBelow(io_registry_entry_t entry, pid_t me) {
    io_iterator_t iterator = IO_OBJECT_NULL;
    if (IORegistryEntryCreateIterator(entry, kIOServicePlane, kIORegistryIterateRecursively, &iterator) != KERN_SUCCESS) {
        return nil;
    }
    NSString *found = nil;
    io_registry_entry_t child;
    while ((child = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        if (found == nil && IOObjectConformsTo(child, "IOUserClient")) {
            id creator = CFBridgingRelease(IORegistryEntryCreateCFProperty(child, CFSTR("IOUserClientCreator"), kCFAllocatorDefault, 0));
            pid_t pid = 0;
            NSString *name = nil;
            if (![creator isKindOfClass:[NSString class]] || !QLMHostCheckParseCreator(creator, &pid, &name)) {
                found = @"A client of unknown origin holds the GLM adapter.";
            } else if (pid != me) {
                found = [NSString stringWithFormat:@"%@ (pid %d) holds the GLM adapter.", name, pid];
            }
        }
        IOObjectRelease(child);
    }
    IOObjectRelease(iterator);
    return found;
}

// Consumes the matching dictionary.
static NSString *_Nullable QLMHostCheckClientOfMatches(CFMutableDictionaryRef matching, pid_t me) {
    io_iterator_t services = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, matching, &services) != KERN_SUCCESS) {
        return nil;
    }
    NSString *found = nil;
    io_service_t service;
    while ((service = IOIteratorNext(services)) != IO_OBJECT_NULL) {
        if (found == nil) {
            found = QLMHostCheckClientBelow(service, me);
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(services);
    return found;
}

NSString *QLMHostCheckAdapterClients(void) {
    pid_t me = getpid();
    return QLMHostCheckClientOfMatches(QLMHostCheckCreateUSBMatching(), me)
               ?: QLMHostCheckClientOfMatches(QLMHostCheckCreateHIDMatching(), me);
}

NSString *QLMHostCheckOtherHost(void) {
    return QLMHostCheckGLMProcess() ?: QLMHostCheckAdapterClients();
}
