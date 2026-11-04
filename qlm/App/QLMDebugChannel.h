#import <Cocoa/Cocoa.h>

@class QLMPreferences;
@class QLMSnapshot;
@class QLMSystem;

NS_ASSUME_NONNULL_BEGIN

// The debug command channel: a script drives and reads a running Debug build
// with commands. The transport and the client are vibe-libs' dev/DebugChannel.
// The standard verbs and the input verbs are its dev/DebugVerbs. qlm's own
// verbs call what the popover and Settings call. They reach System and
// Setups, never the adapter, so every safety rule still holds.
//
// Every .m here wraps its body in #if DEBUG, so a Release build compiles it
// to nothing. This header has no #if DEBUG, so a call from Release code
// compiles and then fails to link. Every caller stays under #if DEBUG.

// What the verbs drive. The app delegate adopts it. On the main queue.
@protocol QLMDebugApp <NSObject>
// The latest snapshot System handed the app, as the popover shows it.
@property (nonatomic, readonly, nullable) QLMSnapshot *debugSnapshot;
@property (nonatomic, readonly) NSPopover *debugPopover;
// What the popover's controls and Settings drive.
@property (nonatomic, readonly, nullable) QLMSystem *debugSystem;
@property (nonatomic, readonly) QLMPreferences *debugPreferences;
// The banner's Quit GLM button: its title, or nil while it is hidden.
@property (nonatomic, readonly, copy, nullable) NSString *debugQuitGLMTitle;
// A quit now asks first, since the take-over may raise the real monitors'
// level. So does turning the adapter off, which stops them too.
@property (nonatomic, readonly) BOOL debugQuitAsksFirst;
// What the status item's click does when the popover is closed.
- (void)debugShowPopover;
// What the popover's Monitors… and Settings… buttons do.
- (void)debugShowMonitors;
- (void)debugShowSettings;
// What the setup banner's Read Again button does.
- (void)debugReadSetup;
// What Settings does once it has changed the ceiling, or the adapter
// setting, in the preferences.
- (void)debugVolumeRangeDidChange;
- (void)debugAdapterDidChange;
// The banner's Quit GLM button. NO while it is hidden or disabled.
- (BOOL)debugQuitGLM;
// Opens a look at the named skin, its window or its OSD, and makes it key.
// A disabled look shows every control, or the OSD, disabled. The reply says
// which skin shows, and why it fell back, if it did.
- (NSDictionary *)debugShowSkinPreview:(NSString *)name osd:(BOOL)osd disabled:(BOOL)disabled;
// The OSD: shows the latest snapshot's level, as a turn of the adapter's
// knob would, timer and all, or says why not. The hide is at once.
// dump_screenshot takes it while the app has no key window.
- (nullable NSString *)debugShowOSD;
- (void)debugHideOSD;
@property (nonatomic, readonly) BOOL debugOSDShowing;
// Turns the fake bus's knob, as its window's slider does, or says why not.
- (nullable NSString *)debugTurnFakeKnobTo:(NSInteger)tenths;
// The app's Quit. quitAnyway answers the louder hand-back alert, if it would
// show. Returns only when the quit is cancelled.
- (void)debugQuitAnswering:(BOOL)quitAnyway;

// The main window: what the popover's Window… button opens, and its close.
// The rest are as QLMMainWindowController's.
@property (nonatomic, readonly) BOOL debugWindowShowing;
- (void)debugShowWindow;
- (void)debugCloseWindow;
- (nullable NSString *)debugClickGroupNamed:(NSString *)name;
@property (nonatomic, readonly, copy, nullable) NSString *debugWindowApplyError;
- (double)debugTurnKnobTo:(double)decibels;
@property (nonatomic, readonly, copy) NSString *debugWindowSkinName;
- (nullable NSString *)debugChooseSkin:(NSString *)name;
// Why the saved skin does not load.
@property (nonatomic, readonly, copy, nullable) NSString *debugSkinRefusal;
@end

// Installs the channel under the bundle identifier. Call it once, at launch.
void QLMDebugInstallChannel(id<QLMDebugApp> app);

// Runs one command as the channel does, and returns its JSON reply. Nil when
// a standard verb replies later.
NSString *_Nullable QLMDebugRun(NSArray<NSString *> *args, NSString *commandId, id<QLMDebugApp> _Nullable app);

// qlm's own verbs, then vibe-libs' standard verbs, then its input verbs. A
// verb in two of them would run from the first, silently.
NSArray<NSArray<NSDictionary *> *> *QLMDebugTables(void);

// The client: `qlm --debug-cmd <verb> [args...]`. main() calls it before
// NSApplicationMain, so no second app starts. It returns the exit code: 0
// ok, 1 no reply, 2 command error, 64 usage.
int QLMDebugClientMain(int argc, const char *_Nonnull argv[_Nonnull]);

// The spec for a verb in any table the app dispatches with, so the client
// waits as long as the verb says.
NSDictionary *_Nullable QLMDebugSpecForVerb(NSString *verb);

NS_ASSUME_NONNULL_END
