#import <Foundation/Foundation.h>

#include <unistd.h>

NS_ASSUME_NONNULL_BEGIN

// Finds another host on the GLM adapter, so qlm never drives the bus while
// one does. Each check reads the process table or the IORegistry and opens
// nothing. Each returns a description that names the host, or nil.

// A process other than this one whose executable is inside a GLMv5.app bundle.
NSString *_Nullable QLMHostCheckGLMProcess(void);

// A process other than this one with a user client on the adapter: on its
// USB device, its HID device, or anything below them. GLM holds an
// IOHIDLibUserClient on the HID device while it runs.
NSString *_Nullable QLMHostCheckAdapterClients(void);

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
