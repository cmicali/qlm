#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

#import "QLMPreferences.h"
#import "QLMSnapshot.h"

NS_ASSUME_NONNULL_BEGIN

// Whether a snapshot shows the OSD, by docs/ui.md's "The OSD". Foundation
// only. On the main queue.
@interface QLMOSDRule : NSObject

// Settings' checkbox. YES until set.
@property (nonatomic) BOOL enabled;

// Takes each snapshot, in order, and remembers it for the next.
- (BOOL)showsSnapshot:(QLMSnapshot *)snapshot whileShowing:(BOOL)showing;

@end

// The OSD's frame on a screen whose visible frame is `visible`, 24 points
// in from its edges. Screen coordinates, so y grows upward.
CGRect QLMOSDFrame(CGRect visible, CGSize size, QLMOSDPlacement placement);

NS_ASSUME_NONNULL_END
