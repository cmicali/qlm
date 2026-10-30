#import <Foundation/Foundation.h>

#include <unistd.h>

NS_ASSUME_NONNULL_BEGIN

// Finds another host on the GLM adapter, so qlm never drives the bus while
// one does. Each check reads the process table or the IORegistry and opens
// nothing. Each returns a description that names the host, or nil.

// A process other than this one whose executable is inside a GLMv5.app bundle.
NSString *_Nullable QLMHostCheckGLMProcess(void);

// A process other than this one that holds the adapter: a user client on its
// USB device, its HID device, or anything below them that
// QLMHostCheckClientHolder counts, or an entry that QLMHostCheckEntryOwner
// counts. GLM holds an opened IOHIDLibUserClient on the HID device while it
// runs. A process that only enumerates USB devices, as Spotify does, holds an
// AppleUSBHostDeviceUserClient and is ignored.
NSString *_Nullable QLMHostCheckAdapterClients(void);

// Whether a user client below the adapter holds it, from its class and its
// IOUserClientCreator and DebugState properties. Returns a description that
// names the holder, or nil. A client this process created never holds it.
// Holders: a client of unknown origin, any client GLM created, an
// IOHIDLibUserClient unless its DebugState says it neither opened nor seized
// the HID device, and any client of a class not listed here. A USB device or
// interface client holds nothing itself. Its open shows as UsbExclusiveOwner.
// TRAP: this guards "Never drive the bus while GLM runs". When unsure, it
// counts the client as a holder.
NSString *_Nullable QLMHostCheckClientHolder(NSString *className, NSDictionary *properties, pid_t me);

// A process other than this one that has opened the adapter's USB device or
// interface, from the entry's UsbExclusiveOwner, "pid 906, MIDIServer".
// Returns a description that names it, or nil. A driver that owns the entry is
// named by its class, as AppleUserUSBHostHIDDevice owns the adapter's
// interface, and is not a process.
NSString *_Nullable QLMHostCheckEntryOwner(NSDictionary *properties, pid_t me);

// Both checks, GLM first.
NSString *_Nullable QLMHostCheckOtherHost(void);

// GLM 5's executable is /Applications/GLMv5.app/Contents/MacOS/GLMv5. A copy
// elsewhere counts too.
BOOL QLMHostCheckIsGLMExecutable(NSString *path);

// Reads IOKit's "IOUserClientCreator", "pid 20129, GLMv5": the pid, then the
// process name, cut to 16 characters.
BOOL QLMHostCheckParseCreator(NSString *creator, pid_t *pid, NSString *_Nullable *_Nullable name);

// Matching for the adapter's HID device: its vendor, product, and usage page.
// The caller owns the dictionary, or hands it to a call that consumes it.
CFMutableDictionaryRef QLMHostCheckCreateHIDMatching(void);

NS_ASSUME_NONNULL_END
