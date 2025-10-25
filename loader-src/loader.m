#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>

#pragma mark - IL2CPP typedefs

typedef void*   (*t_il2cpp_domain_get)(void);
typedef void    (*t_il2cpp_domain_get_assemblies)(void* domain, const void*** assemblies, size_t* size);
typedef void*   (*t_il2cpp_assembly_get_image)(void* assembly);
typedef const char* (*t_il2cpp_image_get_name)(void* image);
typedef void*   (*t_il2cpp_class_from_name)(void* image, const char* namesp, const char* name);
typedef void*   (*t_il2cpp_class_get_method_from_name)(void* klass, const char* name, int argsCount);
typedef void*   (*t_il2cpp_runtime_invoke)(void* method, void* obj, void** params, void** exc);
typedef const uint16_t* (*t_il2cpp_string_chars)(void* il2cppStr);
typedef int32_t (*t_il2cpp_string_length)(void* il2cppStr);

// NEW: thread attach/detach + optional assembly open
typedef void*   (*t_il2cpp_thread_attach)(void* domain);
typedef void    (*t_il2cpp_thread_detach)(void* thread);
typedef void*   (*t_il2cpp_domain_assembly_open)(void* domain, const char* name); // may be NULL on some builds

#pragma mark - dlsym helper

static void* sym(const char* s) {
    // ensure UnityFramework is global so symbols resolve from all images
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *h = dlopen("@rpath/UnityFramework.framework/UnityFramework", RTLD_NOW | RTLD_GLOBAL);
        if (!h) h = dlopen("/System/Library/Frameworks/UnityFramework.framework/UnityFramework", RTLD_NOW | RTLD_GLOBAL);
        NSLog(@"[Loader v3] dlopen UnityFramework -> %p (%s)", h, h ? "OK" : dlerror());
    });

    void *p = dlsym(RTLD_DEFAULT, s);
    if (!p) NSLog(@"[Loader v3] dlsym('%s') = NULL", s);
    return p;
}

#pragma mark - UIWindow / root VC helper (scene-safe)

static UIWindow *LF_mainWindow(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive &&
                [scene isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                    if (w.isKeyWindow) return w;
                }
            }
        }
        return UIApplication.sharedApplication.windows.firstObject;
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        return UIApplication.sharedApplication.keyWindow ?: UIApplication.sharedApplication.windows.firstObject;
#pragma clang diagnostic pop
    }
}

#pragma mark - Auth token reader

static BOOL logAuthToken_once(void) {
    NSLog(@"[Loader v3] ===== logAuthToken_once() =====");

    t_il2cpp_domain_get  il2cpp_domain_get  = (t_il2cpp_domain_get) sym("il2cpp_domain_get");
    t_il2cpp_domain_get_assemblies il2cpp_domain_get_assemblies = (t_il2cpp_domain_get_assemblies) sym("il2cpp_domain_get_assemblies");
    t_il2cpp_assembly_get_image   il2cpp_assembly_get_image   = (t_il2cpp_assembly_get_image) sym("il2cpp_assembly_get_image");
    t_il2cpp_image_get_name       il2cpp_image_get_name       = (t_il2cpp_image_get_name) sym("il2cpp_image_get_name");
    t_il2cpp_class_from_name      il2cpp_class_from_name      = (t_il2cpp_class_from_name) sym("il2cpp_class_from_name");
    t_il2cpp_class_get_method_from_name mget = (t_il2cpp_class_get_method_from_name) sym("il2cpp_class_get_method_from_name");
    t_il2cpp_runtime_invoke       il2cpp_runtime_invoke       = (t_il2cpp_runtime_invoke) sym("il2cpp_runtime_invoke");
    t_il2cpp_string_chars         il2cpp_string_chars         = (t_il2cpp_string_chars) sym("il2cpp_string_chars");
    t_il2cpp_string_length        il2cpp_string_length        = (t_il2cpp_string_length) sym("il2cpp_string_length");
    t_il2cpp_thread_attach        il2cpp_thread_attach        = (t_il2cpp_thread_attach) sym("il2cpp_thread_attach");
    t_il2cpp_thread_detach        il2cpp_thread_detach        = (t_il2cpp_thread_detach) sym("il2cpp_thread_detach");

    if (!il2cpp_domain_get || !il2cpp_domain_get_assemblies) { NSLog(@"[Loader v3] missing core IL2CPP symbols"); return NO; }

    void* domain = il2cpp_domain_get();
    if (!domain) { NSLog(@"[Loader v3] il2cpp_domain_get() NULL"); return NO; }

    void* tls = NULL;
    if (il2cpp_thread_attach) tls = il2cpp_thread_attach(domain);

    const void** assemblies = NULL; size_t count = 0;
    il2cpp_domain_get_assemblies(domain, &assemblies, &count);
    NSLog(@"[Loader v3] assemblies count = %zu", count);
    if (!assemblies || count == 0) { 
        NSLog(@"[Loader v3] no assemblies yet (will retry)");
        if (il2cpp_thread_detach && tls) il2cpp_thread_detach(tls);
        return NO; 
    }

    for (size_t i = 0; i < count && i < 12; i++) {
        void* img = il2cpp_assembly_get_image((void*)assemblies[i]);
        const char* nm = img ? il2cpp_image_get_name(img) : "(null)";
        NSLog(@"[Loader v3] asm[%zu] %s", i, nm ?: "(null)");
    }

    // Find Nakama image
    void* nakamaImage = NULL;
    for (size_t i = 0; i < count; i++) {
        void* img = il2cpp_assembly_get_image((void*)assemblies[i]);
        const char* name = img ? il2cpp_image_get_name(img) : NULL;
        if (name && (strstr(name, "Nakama.dll") || strstr(name, "Nakama"))) { nakamaImage = img; break; }
    }
    if (!nakamaImage) { 
        NSLog(@"[Loader v3] Nakama image not present yet (will retry)");
        if (il2cpp_thread_detach && tls) il2cpp_thread_detach(tls);
        return NO; 
    }

    void* clientKlass = il2cpp_class_from_name(nakamaImage, "Nakama", "Client");
    if (!clientKlass) { NSLog(@"[Loader v3] Nakama.Client not found"); if (il2cpp_thread_detach && tls) il2cpp_thread_detach(tls); return NO; }

    void* m_getInstance = mget(clientKlass, "get_Instance", 0);
    if (!m_getInstance){ NSLog(@"[Loader v3] get_Instance not found"); if (il2cpp_thread_detach && tls) il2cpp_thread_detach(tls); return NO; }
    void* exc = NULL;
    void* clientSingleton = il2cpp_runtime_invoke(m_getInstance, NULL, NULL, &exc);
    if (!clientSingleton){ NSLog(@"[Loader v3] Client.Instance NULL (exc=%p)", exc); if (il2cpp_thread_detach && tls) il2cpp_thread_detach(tls); return NO; }

    void* m_getSession = mget(clientKlass, "get_Session", 0);
    if (!m_getSession){ NSLog(@"[Loader v3] get_Session not found"); if (il2cpp_thread_detach && tls) il2cpp_thread_detach(tls); return NO; }
    void* sessionObj = il2cpp_runtime_invoke(m_getSession, clientSingleton, NULL, &exc);
    if (!sessionObj){ NSLog(@"[Loader v3] Session NULL (exc=%p)", exc); if (il2cpp_thread_detach && tls) il2cpp_thread_detach(tls); return NO; }

    void* sessionKlass = il2cpp_class_from_name(nakamaImage, "Nakama", "Session");
    if (!sessionKlass){ NSLog(@"[Loader v3] Nakama.Session not found"); if (il2cpp_thread_detach && tls) il2cpp_thread_detach(tls); return NO; }
    void* m_getAuth = mget(sessionKlass, "get_AuthToken", 0);
    if (!m_getAuth){ NSLog(@"[Loader v3] get_AuthToken not found"); if (il2cpp_thread_detach && tls) il2cpp_thread_detach(tls); return NO; }
    void* tokenStr = il2cpp_runtime_invoke(m_getAuth, sessionObj, NULL, &exc);
    if (!tokenStr){ NSLog(@"[Loader v3] AuthToken returned NULL (exc=%p)", exc); if (il2cpp_thread_detach && tls) il2cpp_thread_detach(tls); return NO; }

    const uint16_t* w = il2cpp_string_chars ? il2cpp_string_chars(tokenStr) : NULL;
    int32_t len = il2cpp_string_length ? il2cpp_string_length(tokenStr) : 0;
    if (!w || len <= 0) { NSLog(@"[Loader v3] token empty"); if (il2cpp_thread_detach && tls) il2cpp_thread_detach(tls); return NO; }

    NSString *ns = [NSString stringWithCharacters:(unichar*)w length:(NSUInteger)len];
    NSLog(@"[Loader v3] Nakama Session AuthToken = %@", ns);

    if (il2cpp_thread_detach && tls) il2cpp_thread_detach(tls);
    return YES;
}


static void try_logAuthToken_with_retries(void) {
    __block int attempts = 0;
    __block void (^tick)(void);
    tick = ^{
        attempts++;
        NSLog(@"[Loader v3] AuthToken attempt %d", attempts);
        if (logAuthToken_once()) {
            NSLog(@"[Loader v3] AuthToken read OK");
            return;
        }
        if (attempts < 180) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), tick);
        } else {
            NSLog(@"[Loader v3] gave up after %d attempts", attempts);
        }
    };
    tick(); // start immediately; caller controls initial warm-up via dispatch_after
}

#pragma mark - FLEX helpers

static void presentExplorerWithManager(id mgr) {
    if (!mgr) { NSLog(@"[Loader v3] FLEXManager nil"); return; }
    NSArray<NSString *> *noArg = @[@"showExplorer", @"toggleExplorer", @"presentExplorer", @"show"];
    NSArray<NSString *> *oneArg = @[@"showExplorerFromRootViewController:", @"presentExplorerAnimated:"];

    for (NSString *name in noArg) {
        SEL sel = NSSelectorFromString(name);
        if ([mgr respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [mgr performSelector:sel];
#pragma clang diagnostic pop
            NSLog(@"[Loader v3] invoked %@", name);
            return;
        }
    }
    UIWindow *win = LF_mainWindow();
    UIViewController *root = win.rootViewController ?: [UIViewController new];
    for (NSString *name in oneArg) {
        SEL sel = NSSelectorFromString(name);
        if ([mgr respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [mgr performSelector:sel withObject:root];
#pragma clang diagnostic pop
            NSLog(@"[Loader v3] invoked %@ with root", name);
            return;
        }
    }
    NSLog(@"[Loader v3] FLEX presenter not found");
}

static void tryLoadAndPresentFLEX(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray<NSString *> *paths = @[
            [[NSBundle mainBundle] pathForResource:@"FLEX" ofType:@"framework" inDirectory:@"Frameworks"],
            [NSString stringWithFormat:@"%@/Frameworks/FLEX.framework/FLEX", [[NSBundle mainBundle] bundlePath]],
            @"/Library/Frameworks/FLEX.framework/FLEX"
        ];
        for (NSString *p in paths) {
            if (!p) continue;
            if (![[NSFileManager defaultManager] fileExistsAtPath:p]) { NSLog(@"[Loader v3] FLEX not at %@", p); continue; }
            void *h = dlopen(p.UTF8String, RTLD_NOW | RTLD_LOCAL);
            if (!h) { NSLog(@"[Loader v3] dlopen FLEX failed at %@: %s", p, dlerror()); continue; }
            NSLog(@"[Loader v3] dlopen OK: %@", p);

            Class FlexMgr = NSClassFromString(@"FLEXManager");
            if (FlexMgr && [FlexMgr respondsToSelector:@selector(sharedManager)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                id mgr = [FlexMgr performSelector:@selector(sharedManager)];
#pragma clang diagnostic pop
                presentExplorerWithManager(mgr);

                // kick off token loop after a warm-up
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10.0 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    try_logAuthToken_with_retries();
                });
                return;
            }
            NSLog(@"[Loader v3] FLEXManager not found after dlopen");
        }
        NSLog(@"[Loader v3] FLEX framework not found anywhere");
    });
}

#pragma mark - Entry points

__attribute__((constructor))
static void loader_constructor() {
    NSLog(@"[Loader v3] C constructor hit");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        sleep(1);
        tryLoadAndPresentFLEX();

        // also retry when app becomes active (Unity scene ready)
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(__unused NSNotification *n) {
            NSLog(@"[Loader v3] UIApplicationDidBecomeActive -> start token attempts");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                try_logAuthToken_with_retries();
            });
        }];

        // fallback warm-up start
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            try_logAuthToken_with_retries();
        });
    });
}

// backup entrypoint in case constructor is skipped
@interface _LoaderBootstrap : NSObject @end
@implementation _LoaderBootstrap
+ (void)load {
    NSLog(@"[Loader v3] +load fired");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        tryLoadAndPresentFLEX();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            try_logAuthToken_with_retries();
        });
    });
}
@end
