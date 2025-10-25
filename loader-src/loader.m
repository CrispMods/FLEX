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

#pragma mark - dlsym helper

static void* sym(const char* s) {
    void *p = dlsym(RTLD_DEFAULT, s);
    if (!p) {
        NSLog(@"[Loader v2] dlsym('%s') miss -> dlopen UnityFramework", s);
        void *hf = dlopen("@rpath/UnityFramework.framework/UnityFramework", RTLD_NOW | RTLD_LOCAL);
        if (!hf) hf = dlopen("/System/Library/Frameworks/UnityFramework.framework/UnityFramework", RTLD_NOW | RTLD_LOCAL);
        p = dlsym(RTLD_DEFAULT, s);
    }
    if (!p) NSLog(@"[Loader v2] dlsym('%s') still NULL", s);
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

#pragma mark - Auth token reader (very verbose)

static BOOL logAuthToken_once(void) {
    NSLog(@"[Loader v2] ===== logAuthToken_once() =====");

    t_il2cpp_domain_get                 il2cpp_domain_get                 = (t_il2cpp_domain_get)                sym("il2cpp_domain_get");
    t_il2cpp_domain_get_assemblies      il2cpp_domain_get_assemblies      = (t_il2cpp_domain_get_assemblies)     sym("il2cpp_domain_get_assemblies");
    t_il2cpp_assembly_get_image         il2cpp_assembly_get_image         = (t_il2cpp_assembly_get_image)        sym("il2cpp_assembly_get_image");
    t_il2cpp_image_get_name             il2cpp_image_get_name             = (t_il2cpp_image_get_name)            sym("il2cpp_image_get_name");
    t_il2cpp_class_from_name            il2cpp_class_from_name            = (t_il2cpp_class_from_name)           sym("il2cpp_class_from_name");
    t_il2cpp_class_get_method_from_name il2cpp_class_get_method_from_name = (t_il2cpp_class_get_method_from_name)sym("il2cpp_class_get_method_from_name");
    t_il2cpp_runtime_invoke             il2cpp_runtime_invoke             = (t_il2cpp_runtime_invoke)            sym("il2cpp_runtime_invoke");
    t_il2cpp_string_chars               il2cpp_string_chars               = (t_il2cpp_string_chars)              sym("il2cpp_string_chars");
    t_il2cpp_string_length              il2cpp_string_length              = (t_il2cpp_string_length)             sym("il2cpp_string_length");

    if (!il2cpp_domain_get || !il2cpp_domain_get_assemblies) {
        NSLog(@"[Loader v2] il2cpp symbols missing (domain_get / get_assemblies)");
        return NO;
    }

    void* domain = il2cpp_domain_get();
    if (!domain) { NSLog(@"[Loader v2] il2cpp_domain_get() NULL"); return NO; }

    const void** assemblies = NULL; size_t count = 0;
    il2cpp_domain_get_assemblies(domain, &assemblies, &count);
    NSLog(@"[Loader v2] assemblies count = %zu", count);
    if (!assemblies || count == 0) { NSLog(@"[Loader v2] no assemblies yet"); return NO; }

    for (size_t i = 0; i < count && i < 8; i++) {
        void* img_i = il2cpp_assembly_get_image((void*)assemblies[i]);
        const char* nm_i = img_i ? il2cpp_image_get_name(img_i) : "(null)";
        NSLog(@"[Loader v2] asm[%zu] = %s", i, nm_i ?: "(null)");
    }

    // Find Nakama image
    void* nakamaImage = NULL;
    for (size_t i = 0; i < count; i++) {
        void* img = il2cpp_assembly_get_image((void*)assemblies[i]);
        const char* name = img ? il2cpp_image_get_name(img) : NULL;
        if (name && (strstr(name, "Nakama.dll") || strstr(name, "Nakama"))) {
            nakamaImage = img; NSLog(@"[Loader v2] found image: %s", name); break;
        }
    }
    if (!nakamaImage) { NSLog(@"[Loader v2] Nakama image not loaded yet"); return NO; }

    // Client.get_Instance()
    void* clientKlass = il2cpp_class_from_name(nakamaImage, "Nakama", "Client");
    if (!clientKlass) { NSLog(@"[Loader v2] Nakama.Client class not found"); return NO; }
    void* m_getInstance = il2cpp_class_get_method_from_name(clientKlass, "get_Instance", 0);
    if (!m_getInstance){ NSLog(@"[Loader v2] get_Instance not found"); return NO; }
    void* exc = NULL;
    void* clientSingleton = il2cpp_runtime_invoke(m_getInstance, NULL, NULL, &exc);
    if (exc) NSLog(@"[Loader v2] get_Instance exception=%p", exc);
    if (!clientSingleton){ NSLog(@"[Loader v2] Client.Instance NULL"); return NO; }
    NSLog(@"[Loader v2] Client.Instance = %p", clientSingleton);

    // Client.get_Session()
    void* m_getSession = il2cpp_class_get_method_from_name(clientKlass, "get_Session", 0);
    if (!m_getSession){ NSLog(@"[Loader v2] get_Session not found"); return NO; }
    void* sessionObj = il2cpp_runtime_invoke(m_getSession, clientSingleton, NULL, &exc);
    if (exc) NSLog(@"[Loader v2] get_Session exception=%p", exc);
    if (!sessionObj){ NSLog(@"[Loader v2] Session NULL"); return NO; }
    NSLog(@"[Loader v2] Session obj = %p", sessionObj);

    // Session.get_AuthToken()
    void* sessionKlass = il2cpp_class_from_name(nakamaImage, "Nakama", "Session");
    if (!sessionKlass){ NSLog(@"[Loader v2] Nakama.Session class not found"); return NO; }
    void* m_getAuth = il2cpp_class_get_method_from_name(sessionKlass, "get_AuthToken", 0);
    if (!m_getAuth){ NSLog(@"[Loader v2] get_AuthToken not found"); return NO; }
    void* tokenStr = il2cpp_runtime_invoke(m_getAuth, sessionObj, NULL, &exc);
    if (exc) NSLog(@"[Loader v2] get_AuthToken exception=%p", exc);
    if (!tokenStr){ NSLog(@"[Loader v2] AuthToken returned NULL"); return NO; }

    if (!il2cpp_string_chars || !il2cpp_string_length) {
        NSLog(@"[Loader v2] il2cpp_string_* missing"); return NO;
    }
    const uint16_t* w = il2cpp_string_chars(tokenStr);
    int32_t len = il2cpp_string_length(tokenStr);
    NSLog(@"[Loader v2] token Il2CppString len=%d chars_ptr=%p", len, w);
    if (!w || len <= 0) { NSLog(@"[Loader v2] token empty"); return NO; }

    NSString *ns = [NSString stringWithCharacters:(unichar*)w length:(NSUInteger)len];
    NSLog(@"[Loader v2] Nakama Session AuthToken = %@", ns);
    return YES;
}

static void try_logAuthToken_with_retries(void) {
    __block int attempts = 0;
    __block void (^tick)(void);
    tick = ^{
        attempts++;
        NSLog(@"[Loader v2] AuthToken attempt %d", attempts);
        if (logAuthToken_once()) {
            NSLog(@"[Loader v2] AuthToken read OK");
            return;
        }
        if (attempts < 60) { // ~60s
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), tick);
        } else {
            NSLog(@"[Loader v2] gave up after %d attempts", attempts);
        }
    };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        tick();
    });
}

#pragma mark - FLEX helpers (verbose)

static void presentExplorerWithManager(id mgr) {
    if (!mgr) { NSLog(@"[Loader v2] FLEXManager nil"); return; }
    NSArray<NSString *> *noArg = @[@"showExplorer", @"toggleExplorer", @"presentExplorer", @"show"];
    NSArray<NSString *> *oneArg = @[@"showExplorerFromRootViewController:", @"presentExplorerAnimated:"];

    for (NSString *name in noArg) {
        SEL sel = NSSelectorFromString(name);
        if ([mgr respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [mgr performSelector:sel];
#pragma clang diagnostic pop
            NSLog(@"[Loader v2] invoked %@", name);
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
            NSLog(@"[Loader v2] invoked %@ with root", name);
            return;
        }
    }
    NSLog(@"[Loader v2] FLEX presenter not found");
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
            if (![[NSFileManager defaultManager] fileExistsAtPath:p]) { NSLog(@"[Loader v2] FLEX not at %@", p); continue; }
            void *h = dlopen(p.UTF8String, RTLD_NOW | RTLD_LOCAL);
            if (!h) { NSLog(@"[Loader v2] dlopen FLEX failed at %@: %s", p, dlerror()); continue; }
            NSLog(@"[Loader v2] dlopen OK: %@", p);

            Class FlexMgr = NSClassFromString(@"FLEXManager");
            if (FlexMgr && [FlexMgr respondsToSelector:@selector(sharedManager)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                id mgr = [FlexMgr performSelector:@selector(sharedManager)];
#pragma clang diagnostic pop
                presentExplorerWithManager(mgr);

                // Use a block here (this was the build error).
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(500 * NSEC_PER_MSEC)),
                               dispatch_get_main_queue(), ^{
                    try_logAuthToken_with_retries();
                });
                return;
            }
            NSLog(@"[Loader v2] FLEXManager not found after dlopen");
        }
        NSLog(@"[Loader v2] FLEX framework not found anywhere");
    });
}

#pragma mark - Entry points (two of them)

__attribute__((constructor))
static void loader_constructor() {
    NSLog(@"[Loader v2] C constructor hit");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        sleep(1);
        tryLoadAndPresentFLEX();
        try_logAuthToken_with_retries();
    });
}

// Obj-C +load sometimes fires in cases where the constructor is skipped
@interface _LoaderBootstrap : NSObject @end
@implementation _LoaderBootstrap
+ (void)load {
    NSLog(@"[Loader v2] +load fired");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        tryLoadAndPresentFLEX();
        try_logAuthToken_with_retries();
    });
}
@end
