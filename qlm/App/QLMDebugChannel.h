#import <Foundation/Foundation.h>

#import "QLMPreferences.h"
#import "QLMSystem.h"

NS_ASSUME_NONNULL_BEGIN

// The debug channel: a script drives a running Debug build of the app, over
// vibe-libs's dev/DebugChannel. `qlm debug <verb> …` is its client, and the
// app's own binary runs it.
//
// Compiled in every configuration. The .m wraps its body in #if DEBUG, so a
// Release build has none of it, and a call from Release code fails to link.
// Keep every caller under #if DEBUG.

// What the verbs drive. Each is the app's own action, so the ceiling, the
// allowlist, and the GLM check hold for a script as they do for the user.
// No verb sends a frame itself. On the main queue.
@protocol QLMDebugApp <NSObject>

@property (nonatomic, readonly) QLMPreferences *preferences;
@property (nonatomic, readonly, nullable) QLMSystem *system;
// The snapshot the app last drew.
@property (nonatomic, readonly, nullable) QLMSnapshot *shownSnapshot;
// The banner's Quit GLM button: its title, or nil while it is hidden.
@property (nonatomic, readonly, copy, nullable) NSString *quitGLMTitle;
// A quit now asks first, since the take-over would raise the real monitors'
// level.
@property (nonatomic, readonly) BOOL quitAsksFirst;

// Settings' ceiling: kept in the preferences, which bound it, then sent to
// System.
- (void)changeCeilingDecibels:(double)decibels;
// Settings' adapter checkbox: kept in the preferences, then a new System.
- (void)changeUsesAdapter:(BOOL)usesAdapter;
// The banner's Quit GLM. NO when the banner offers none.
- (BOOL)quitGLM;
// The app's Quit. When the app asks first, quitAnyway answers in place of
// the alert. It returns only when the quit is cancelled.
- (void)quitAnswering:(BOOL)quitAnyway;

@end

// The verbs, as vibe-libs's VibeDebugCmd builds them.
NSArray<NSDictionary *> *QLMDebugCommands(void);

// The main bundle's identifier. Only the app's own binary names the app's
// channel, so a test process never reaches a running app.
NSString *QLMDebugChannelName(void);

// Runs one command against the app on the main queue, and returns the JSON
// reply. Every reply carries "at", the local time the verb ran.
NSString *QLMDebugRun(NSArray<NSString *> *args, NSString *commandId, id<QLMDebugApp> _Nullable app);

// Installs the channel under QLMDebugChannelName() once. A later call only
// replaces the app. The app is held weakly.
void QLMInstallDebugChannel(id<QLMDebugApp> app);

// Sends one command over the channel and waits for its reply, as long as the
// verb's table says. Nil when none came. Turns the run loop while it waits,
// so a channel in this process can answer.
NSString *_Nullable QLMDebugSend(NSArray<NSString *> *args);

// `qlm debug <verb> …`: prints the reply. Exits 0 for a reply, 1 for an
// error reply, and 2 when no reply came.
int QLMDebugClientMain(NSArray<NSString *> *args);

NS_ASSUME_NONNULL_END
