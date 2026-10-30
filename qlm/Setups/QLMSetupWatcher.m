#import "QLMSetupWatcher.h"

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

// What tells one version of the file from another.
typedef struct {
    BOOL exists;
    dev_t device;
    ino_t inode;
    off_t size;
    struct timespec modified;
} QLMFileState;

static QLMFileState QLMFileStateOf(const struct stat *info) {
    QLMFileState state = {YES, info->st_dev, info->st_ino, info->st_size, info->st_mtimespec};
    return state;
}

static QLMFileState QLMFileStateAt(NSString *path) {
    struct stat info;
    if (stat(path.fileSystemRepresentation, &info) != 0) {
        QLMFileState missing = {NO, 0, 0, 0, {0, 0}};
        return missing;
    }
    return QLMFileStateOf(&info);
}

static BOOL QLMFileStatesEqual(QLMFileState a, QLMFileState b) {
    return a.exists == b.exists && a.device == b.device && a.inode == b.inode && a.size == b.size &&
           a.modified.tv_sec == b.modified.tv_sec && a.modified.tv_nsec == b.modified.tv_nsec;
}

@implementation QLMSetupWatcher {
    dispatch_queue_t _queue;
    dispatch_block_t _handler;
    dispatch_source_t _folderSource;
    dispatch_source_t _fileSource;
    QLMFileState _watched;  // the file _fileSource watches
    QLMFileState _seen;     // as the handler last saw it, or at start
    NSUInteger _events;     // a settle check from before the latest event does nothing
    BOOL _running;
}

- (instancetype)initWithPath:(NSString *)path queue:(dispatch_queue_t)queue handler:(dispatch_block_t)handler {
    self = [super init];
    if (self) {
        _path = [path copy];
        _queue = queue;
        _handler = [handler copy];
        _settleInterval = 0.5;
    }
    return self;
}

- (void)dealloc {
    [self cancelSources];
}

- (void)start {
    if (_running) {
        return;
    }
    _running = YES;
    _seen = QLMFileStateAt(_path);
    // TRAP: a save that replaces the file gives the old file only a rename
    // or a delete, and the new one no event. So the folder is watched too:
    // its entries change with each replace.
    int folder = open(_path.stringByDeletingLastPathComponent.fileSystemRepresentation, O_EVTONLY);
    if (folder >= 0) {
        _folderSource = [self sourceForDescriptor:folder mask:DISPATCH_VNODE_WRITE];
    }
    [self watchFile];
}

- (void)stop {
    _running = NO;
    _events += 1;
    [self cancelSources];
}

- (void)cancelSources {
    if (_folderSource != NULL) {
        dispatch_source_cancel(_folderSource);
        _folderSource = NULL;
    }
    if (_fileSource != NULL) {
        dispatch_source_cancel(_fileSource);
        _fileSource = NULL;
    }
}

// The source closes the descriptor when it is cancelled.
- (dispatch_source_t)sourceForDescriptor:(int)descriptor mask:(unsigned long)mask {
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, (uintptr_t)descriptor, mask, _queue);
    __weak QLMSetupWatcher *weakSelf = self;
    dispatch_source_set_event_handler(source, ^{
        [weakSelf noteEvent];
    });
    dispatch_source_set_cancel_handler(source, ^{
        close(descriptor);
    });
    dispatch_resume(source);
    return source;
}

// Watches the file now at the path, unless it is the one watched already.
- (void)watchFile {
    QLMFileState now = QLMFileStateAt(_path);
    if (_fileSource != NULL && now.exists && now.device == _watched.device && now.inode == _watched.inode) {
        return;
    }
    if (_fileSource != NULL) {
        dispatch_source_cancel(_fileSource);
        _fileSource = NULL;
    }
    int file = open(_path.fileSystemRepresentation, O_EVTONLY);
    if (file < 0) {
        return;
    }
    struct stat info;
    if (fstat(file, &info) != 0) {
        close(file);
        return;
    }
    _watched = QLMFileStateOf(&info);
    unsigned long mask = DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_ATTRIB | DISPATCH_VNODE_DELETE |
                         DISPATCH_VNODE_RENAME | DISPATCH_VNODE_REVOKE;
    _fileSource = [self sourceForDescriptor:file mask:mask];
}

- (void)noteEvent {
    if (!_running) {
        return;
    }
    [self watchFile];
    NSUInteger event = ++_events;
    __weak QLMSetupWatcher *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_settleInterval * (double)NSEC_PER_SEC)), _queue, ^{
        [weakSelf settleAfterEvent:event];
    });
}

// A missing file is no change, but its return is one.
- (void)settleAfterEvent:(NSUInteger)event {
    if (!_running || event != _events) {
        return;
    }
    [self watchFile];
    QLMFileState now = QLMFileStateAt(_path);
    if (QLMFileStatesEqual(now, _seen)) {
        return;
    }
    _seen = now;
    if (now.exists) {
        _handler();
    }
}

@end
