#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>

// --- IL2CPP minimal API typedefs ---
typedef void*   (*t_il2cpp_domain_get)(void);
typedef void    (*t_il2cpp_domain_get_assemblies)(void* domain, const void*** assemblies, size_t* size);
typedef void*   (*t_il2cpp_assembly_get_image)(void* assembly);
typedef const char* (*t_il2cpp_image_get_name)(void* image);
typedef void*   (*t_il2cpp_class_from_name)(void* image, const char* namesp, const char* name);
typedef void*   (*t_il2cpp_class_get_method_from_name)(void* klass, const char* name, int argsCount);
typedef void*   (*t_il2cpp_runtime_invoke)(void* method, void* obj, void** params, void** exc);
typedef const uint16_t* (*t_il2cpp_string_chars)(void* il2cppStr);
typedef int32_t (*t_il2cpp_string_length)(void* il2cppStr); // safer than wcslen

static void* sym(const char* s) {
    void *p = dlsym(RTLD_DEFAULT, s);
    if (!p) {
        // In some builds you must dlopen UnityFramework first
        void *hf = dlopen("@rpath/UnityFramework.framework/UnityFramework", RTLD_NOW);
        if (!hf) hf = dlopen("/System/Library/Frameworks/UnityFramework.framework/UnityFramework", RTLD_NOW);
        p = dlsym(RTLD_DEFAULT, s);
    }
    return p;
}

static BOOL logAuthToken_once(void) {
    t_il2cpp_domain_get                il2cpp_domain_get                = (t_il2cpp_domain_get)               sym("il2cpp_domain_get");
    t_il2cpp_domain_get_assemblies     il2cpp_domain_get_assemblies     = (t_il2cpp_domain_get_assemblies)    sym("il2cpp_domain_get_assemblies");
    t_il2cpp_assembly_get_image        il2cpp_assembly_get_image        = (t_il2cpp_assembly_get_image)       sym("il2cpp_assembly_get_image");
    t_il2cpp_image_get_name            il2cpp_image_get_name            = (t_il2cpp_image_get_name)           sym("il2cpp_image_get_name");
    t_il2cpp_class_from_name           il2cpp_class_from_name           = (t_il2cpp_class_from_name)          sym("il2cpp_class_from_name");
    t_il2cpp_class_get_method_from_name il2cpp_class_get_method_from_name = (t_il2cpp_class_get_method_from_name)sym("il2cpp_class_get_method_from_name");
    t_il2cpp_runtime_invoke            il2cpp_runtime_invoke            = (t_il2cpp_runtime_invoke)           sym("il2cpp_runtime_invoke");
    t_il2cpp_string_chars              il2cpp_string_chars              = (t_il2cpp_string_chars)             sym("il2cpp_string_chars");
    t_il2cpp_string_length             il2cpp_string_length             = (t_il2cpp_string_length)            sym("il2cpp_string_length");

    if (!il2cpp_domain_get || !il2cpp_domain_get_assemblies) { NSLog(@"[Loader] il2cpp symbols missing"); return NO; }

    // 1) find Nakama image
    void* domain = il2cpp_domain_get();
    const void** assemblies = NULL; size_t count = 0;
    il2cpp_domain_get_assemblies(domain, &assemblies, &count);

    void* nakamaImage = NULL;
    for (size_t i = 0; i < count; i++) {
        void* img = il2cpp_assembly_get_image((void*)assemblies[i]);
        const char* name = il2cpp_image_get_name(img);
        // Names vary: "Nakama.dll" or "Nakama"
        if (name && (strstr(name, "Nakama.dll") || strstr(name, "Nakama"))) { nakamaImage = img; break; }
    }
    if (!nakamaImage) { NSLog(@"[Loader] Nakama image not loaded yet"); return NO; }

    // 2) Client.get_Instance()
    void* clientKlass = il2cpp_class_from_name(nakamaImage, "Nakama", "Client");
    if (!clientKlass) { NSLog(@"[Loader] Nakama.Client not found"); return NO; }
    void* m_getInstance = il2cpp_class_get_method_from_name(clientKlass, "get_Instance", 0);
    if (!m_getInstance){ NSLog(@"[Loader] get_Instance not found"); return NO; }
    void* exc = NULL;
    void* clientSingleton = il2cpp_runtime_invoke(m_getInstance, NULL, NULL, &exc);
    if (!clientSingleton){ NSLog(@"[Loader] Client.Instance is null (login not done?)"); return NO; }

    // 3) Client.get_Session()
    void* m_getSession = il2cpp_class_get_method_from_name(clientKlass, "get_Session", 0);
    if (!m_getSession){ NSLog(@"[Loader] get_Session not found"); return NO; }
    void* sessionObj = il2cpp_runtime_invoke(m_getSession, clientSingleton, NULL, &exc);
    if (!sessionObj){ NSLog(@"[Loader] Session is null"); return NO; }

    // 4) Session.get_AuthToken()
    void* sessionKlass = il2cpp_class_from_name(nakamaImage, "Nakama", "Session");
    if (!sessionKlass){ NSLog(@"[Loader] Nakama.Session not found"); return NO; }
    void* m_getAuth = il2cpp_class_get_method_from_name(sessionKlass, "get_AuthToken", 0);
    if (!m_getAuth){ NSLog(@"[Loader] get_AuthToken not found"); return NO; }
    void* tokenStr = il2cpp_runtime_invoke(m_getAuth, sessionObj, NULL, &exc);
    if (!tokenStr){ NSLog(@"[Loader] AuthToken returned NULL"); return NO; }

    const uint16_t* w = il2cpp_string_chars ? il2cpp_string_chars(tokenStr) : NULL;
    int32_t len = il2cpp_string_length ? il2cpp_string_length(tokenStr) : 0;
    if (!w || len <= 0) { NSLog(@"[Loader] token string empty"); return NO; }

    NSString *ns = [NSString stringWithCharacters:(unichar*)w length:(NSUInteger)len];
    NSLog(@"[Loader] Nakama Session AuthToken = %@", ns);
    return YES;
}

// Call this after FLEX/explorer shows; retry because login/session may appear later
static void try_logAuthToken_with_retries(void) {
    __block int attempts = 0;
    void (^tick)(void) = ^{
        if (logAuthToken_once()) return;
        attempts++;
        if (attempts < 10) { // ~10 tries x 1s
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), tick);
        } else {
            NSLog(@"[Loader] gave up reading AuthToken");
        }
    };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), tick);
}
