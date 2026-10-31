#import <Cocoa/Cocoa.h>

@class QLMSnapshot;

NS_ASSUME_NONNULL_BEGIN

// The debug command channel: a script drives and reads a running Debug build
// with commands. The transport and the client are vibe-libs' dev/DebugChannel.
// The standard verbs and the input verbs are its dev/DebugVerbs. qlm's own
// verbs call what the popover calls. They reach System and Setups, never the
// adapter, so every safety rule still holds.
//
// Every .m here wraps its body in #if DEBUG, so a Release build compiles it
// to nothing. This header has no #if DEBUG, so a call from Release code
// compiles and then fails to link. Every caller stays under #if DEBUG.

// What the verbs drive. The app delegate adopts it.
@protocol QLMDebugApp <NSObject>
// The latest snapshot System handed the app, as the popover shows it.
@property (nonatomic, readonly, nullable) QLMSnapshot *debugSnapshot;
@property (nonatomic, readonly) NSPopover *debugPopover;
// What the status item's click does when the popover is closed.
- (void)debugShowPopover;
// What the popover's Monitors… and Settings… buttons do.
- (void)debugShowMonitors;
- (void)debugShowSettings;
// What the setup banner's Read Again button does.
- (void)debugReadSetup;
@end

// Installs the channel under the bundle identifier. Call it once, at launch.
void QLMDebugInstallChannel(id<QLMDebugApp> app);

// The client: `qlm --debug-cmd <verb> [args...]`. main() calls it before
// NSApplicationMain, so no second app starts. It returns the exit code: 0
// ok, 1 no reply, 2 command error, 64 usage.
int QLMDebugClientMain(int argc, const char *_Nonnull argv[_Nonnull]);

// The spec for a verb in any table the app dispatches with, so the client
// waits as long as the verb says.
NSDictionary *_Nullable QLMDebugSpecForVerb(NSString *verb);

NS_ASSUME_NONNULL_END
