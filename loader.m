#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>

static void presentExplorerWithManager(id mgr) {
    if (!mgr) return;
    SEL cands[] = {
        NSSelectorFromString(@"showExplorer"),
        NSSelectorFromString(@"show"),
        NSSelectorFromString(@"open"),
        NSSelectorFromString(@"presentExplorer"),
    };
    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            for (int i = 0; i < sizeof(cands)/sizeof(cands[0]); ++i) {
                SEL sel = cands[i];
                if ([mgr respondsToSelector:sel]) {
                    @try { [mgr performSelector:sel]; NSLog(@"[Loader] invoked %@", NSStringFromSelector(sel)); }
                    @catch (NSException *e) { NSLog(@"[Loader] exception: %@", e); }
                    return;
                }
            }
            NSLog(@"[Loader] no known present selector worked");
        });
    });
}

static void tryDlopenPath(NSString *path) {
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) { NSLog(@"[Loader] not found: %@", path); return; }
    void *h = dlopen(path.UTF8String, RTLD_NOW | RTLD_LOCAL);
    if (!h) { NSLog(@"[Loader] dlopen failed for %@: %s", path, dlerror()); return; }
    NSLog(@"[Loader] dlopen OK: %@", path);

    Class FlexMgr = NSClassFromString(@"FLEXManager");
    if (FlexMgr) {
        id mgr = [FlexMgr performSelector:@selector(sharedManager)];
        if (mgr) { presentExplorerWithManager(mgr); return; }
    }
    NSLog(@"[Loader] explorer manager not found");
}

static void loadAndPresent() {
    @autoreleasepool {
        NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
        NSArray<NSString *> *paths = @[
            [bundlePath stringByAppendingPathComponent:@"Frameworks/FLEX.framework/FLEX"],
            [bundlePath stringByAppendingPathComponent:@"Frameworks/FLEX.dylib"]
        ];
        for (NSString *p in paths) tryDlopenPath(p);
    }
}

__attribute__((constructor))
static void loader_constructor() {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        sleep(1);
        loadAndPresent();
    });
}
