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
        NSLog(@"[Loader] dlsym('%s') miss; trying to dlopen UnityFramework…", s);
        void *hf = dlopen("@rpath/UnityFramework.framework/UnityFramework", RTLD_NOW | RTLD_LOCAL);
        if (!hf) hf = dlopen("/System/Library/Frameworks/UnityFramework.framework/UnityFramework", RTLD_NOW | RTLD_LOCAL);
        p = dlsym(RTLD_DEFAULT, s);
    }
    if (!p) NSLog(@"[Loader] dlsym('%s') still NULL", s);
    return p;
}

#pragma mark - Auth token reader (verbose)

static BOOL logAuthToken_once(void) {
    NSLog(@"[Loader] ===== logAuthToken_once() =====");

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
        NSLog(@"[Loader] il2cpp symbols missing (domain_get or get_assemblies)");
        return NO;
    }

    void* domain = il2cpp_domain_get();
    if (!domain) { NSLog(@"[Loader] il2cpp_domain_get() returned NULL"); return NO; }

    const void** assemblies = NULL; size_t count = 0;
    il2cpp_domain_get_assemblies(domain, &assemblies, &count);
    NSLog(@"[Loader] assemblies count = %zu", count);
    if (!assemblies || count == 0) { NSLog(@"[Loader] no assemblies yet"); return NO; }

    // log a few assembly names so we see what's loaded
    for (size_t i = 0; i < count && i < 8; i++) {
        void* img_i = il2cpp_assembly_get_image((void*)assemblies[i]);
        const char* nm_i = img_i ? il2cpp_image_get_name(img_i) : "(null)";
        NSLog(@"[Loader] asm[%zu] = %s", i, nm_i ?: "(null)");
    }

    // 1) find Nakama image
    void* nakamaImage = NULL;
    for (size_t i = 0; i < count; i++) {
        void* img = il2cpp_assembly_get_image((void*)assemblies[i]);
        const char* name = img ? il2cpp_image_get_name(img) : NULL;
        if (name && (strstr(name, "Nakama.dll") || strstr(name, "Nakama"))) {
            nakamaImage = img;
            NSLog(@"[Loader] found image: %s", name);
            break;
        }
    }
    if (!nakamaImage) { NSLog(@"[Loader] Nakama image not loaded yet"); return NO; }

    // 2) Client.get_Instance()
    void* clientKlass = il2cpp_class_from_name(nakamaImage, "Nakama", "Client");
    if (!clientKlass) { NSLog(@"[Loader] Nakama.Client class not found"); return NO; }
    void* m_getInstance = il2cpp_class_get_method_from_name(clientKlass, "get_Instance", 0);
    if (!m_getInstance){ NSLog(@"[Loader] method get_Instance not found"); return NO; }
    void* exc = NULL;
    void* clientSingleton = il2cpp_runtime_invoke(m_getInstance, NULL, NULL, &exc);
    if (exc) NSLog(@"[Loader] get_Instance threw exception ptr=%p", exc);
    if (!clientSingleton){ NSLog(@"[Loader] Client.Instance is NULL (not set yet?)"); return NO; }
    NSLog(@"[Loader] Client.Instance = %p", clientSingleton);

    // 3) Client.get_Session()
    void* m_getSession = il2cpp_class_get_method_from_name(clientKlass, "get_Session", 0);
    if (!m_getSession){ NSLog(@"[Loader] method get_Session not found on Client"); return NO; }
    void* sessionObj = il2cpp_runtime_invoke(m_getSession, clientSingleton, NULL, &exc);
    if (exc) NSLog(@"[Loader] get_Session threw exception ptr=%p", exc);
    if (!sessionObj){ NSLog(@"[Loader] Session is NULL"); return NO; }
    NSLog(@"[Loader] Session obj = %p", sessionObj);

    // 4) Session.get_AuthToken()
    void* sessionKlass = il2cpp_class_from_name(nakamaImage, "Nakama", "Session");
    if (!sessionKlass){ NSLog(@"[Loader] Nakama.Session class not found"); return NO; }
    void* m_getAuth = il2cpp_class_get_method_from_name(sessionKlass, "get_AuthToken", 0);
    if (!m_getAuth){ NSLog(@"[Loader] method get_AuthToken not found on Session"); return NO; }
    void* tokenStr = il2cpp_runtime_invoke(m_getAuth, sessionObj, NULL, &exc);
    if (exc) NSLog(@"[Loader] get_AuthToken threw exception ptr=%p", exc);
    if (!tokenStr){ NSLog(@"[Loader] AuthToken returned NULL"); return NO; }

    if (!il2cpp_string_chars || !il2cpp_string_length) {
        NSLog(@"[Loader] il2cpp_string_* symbols missing");
        return NO;
    }
    const uint16_t* w = il2cpp_string_chars(tokenStr);
    int32_t len = il2cpp_string_length(tokenStr);
    NSLog(@"[Loader] token Il2CppString len=%d, chars_ptr=%p", len, w);

    if (!w || len <= 0) { NSLog(@"[Loader] token string empty"); return NO; }

    NSString *ns = [NSString stringWithCharacters:(unichar*)w length:(NSUInteger)len];
    NSLog(@"[Loader] Nakama Session AuthToken = %@", ns);
    return YES;
}

static void try_logAuthToken_with_retries(void) {
    __block int attempts = 0;
    __block void (^tick)(void);
    tick = ^{
        attempts++;
        NSLog(@"[Loader] AuthToken attempt %d", attempts);
        if (logAuthToken_once()) {
            NSLog(@"[Loader] AuthToken read OK");
            return;
        }
        if (attempts < 60) { // try for ~60 seconds
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), tick);
        } else {
            NSLog(@"[Loader] gave up after %d attempts", attempts);
        }
    };
    // small initial delay so Unity boots a bit
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), tick);
}

#pragma mark - FLEX helpers (unchanged but verbose)

static void presentExplorerWithManager(id mgr) {
    if (!mgr) { NSLog(@"[Loader] FLEXManager nil"); return; }
    NSArray<NSString *> *noArg = @[@"showExplorer", @"toggleExplorer", @"presentExplorer", @"show"];
    NSArray<NSString *> *oneArg = @[@"showExplorerFromRootViewController:", @"presentExplorerAnimated:"];

    for (NSString *name in noArg) {
        SEL sel = NSSelectorFromString(name);
        if ([mgr respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [mgr performSelector:sel];
#pragma clang diagnostic pop
            NSLog(@"[Loader] invoked %@", name);
            return;
        }
    }

    UIWindow *win = UIApplication.sharedApplication.keyWindow ?: UIApplication.sharedApplication.windows.firstObject;
    UIViewController *root = win.rootViewController ?: [UIViewController new];

    for (NSString *name in oneArg) {
        SEL sel = NSSelectorFromString(name);
        if ([mgr respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [mgr performSelector:sel withObject:root];
#pragma clang diagnostic pop
            NSLog(@"[Loader] invoked %@ with root", name);
            return;
        }
    }
    NSLog(@"[Loader] could not find FLEX presenter method");
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
            if (![[NSFileManager defaultManager] fileExistsAtPath:p]) { NSLog(@"[Loader] FLEX not at %@", p); continue; }
            void *h = dlopen(p.UTF8String, RTLD_NOW | RTLD_LOCAL);
            if (!h) { NSLog(@"[Loader] dlopen FLEX failed at %@: %s", p, dlerror()); continue; }

            NSLog(@"[Loader] dlopen OK: %@", p);
            Class FlexMgr = NSClassFromString(@"FLEXManager");
            if (FlexMgr && [FlexMgr respondsToSelector:@selector(sharedManager)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                id mgr = [FlexMgr performSelector:@selector(sharedManager)];
#pragma clang diagnostic pop
                presentExplorerWithManager(mgr);

                // Also kick the token reader shortly after showing FLEX
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(500 * NSEC_PER_MSEC)),
                               dispatch_get_main_queue(), try_logAuthToken_with_retries);
                return;
            }
            NSLog(@"[Loader] FLEXManager not found after dlopen");
        }
        NSLog(@"[Loader] FLEX framework not found anywhere");
    });
}

#pragma mark - Entry point

__attribute__((constructor))
static void loader_constructor() {
    NSLog(@"[Loader] constructor hit");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        sleep(1);
        // Always try both in parallel: show FLEX and start token retries.
        tryLoadAndPresentFLEX();
        try_logAuthToken_with_retries();
    });
}
