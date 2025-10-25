#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>

typedef void*   (*t_il2cpp_domain_get)(void);
typedef void    (*t_il2cpp_domain_get_assemblies)(void* domain, const void*** assemblies, size_t* size);
typedef void*   (*t_il2cpp_assembly_get_image)(void* assembly);
typedef const char* (*t_il2cpp_image_get_name)(void* image);
typedef void*   (*t_il2cpp_class_from_name)(void* image, const char* namesp, const char* name);
typedef void*   (*t_il2cpp_class_get_method_from_name)(void* klass, const char* name, int argsCount);
typedef void*   (*t_il2cpp_runtime_invoke)(void* method, void* obj, void** params, void** exc);
typedef const uint16_t* (*t_il2cpp_string_chars)(void* il2cppStr);
typedef int32_t (*t_il2cpp_string_length)(void* il2cppStr);
typedef void*   (*t_il2cpp_thread_attach)(void* domain);
typedef void    (*t_il2cpp_thread_detach)(void* thread);

static void* sym(const char* s) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *h = dlopen("@rpath/UnityFramework.framework/UnityFramework", RTLD_NOW | RTLD_GLOBAL);
        if (!h) h = dlopen("/System/Library/Frameworks/UnityFramework.framework/UnityFramework", RTLD_NOW | RTLD_GLOBAL);
        NSLog(@"[SafeIL2CPP] dlopen UnityFramework -> %p (%s)", h, h ? "OK" : dlerror());
    });
    void *p = dlsym(RTLD_DEFAULT, s);
    if (!p) NSLog(@"[SafeIL2CPP] dlsym('%s') = NULL", s);
    return p;
}

static BOOL read_auth_from_instance_once(void) {
    t_il2cpp_domain_get  il2cpp_domain_get  = (t_il2cpp_domain_get)  sym("il2cpp_domain_get");
    t_il2cpp_domain_get_assemblies dom_get_assemblies = (t_il2cpp_domain_get_assemblies) sym("il2cpp_domain_get_assemblies");
    t_il2cpp_assembly_get_image   assembly_get_image  = (t_il2cpp_assembly_get_image)  sym("il2cpp_assembly_get_image");
    t_il2cpp_image_get_name       image_get_name      = (t_il2cpp_image_get_name)      sym("il2cpp_image_get_name");
    t_il2cpp_class_from_name      class_from_name     = (t_il2cpp_class_from_name)     sym("il2cpp_class_from_name");
    t_il2cpp_class_get_method_from_name mget          = (t_il2cpp_class_get_method_from_name) sym("il2cpp_class_get_method_from_name");
    t_il2cpp_runtime_invoke       runtime_invoke      = (t_il2cpp_runtime_invoke)      sym("il2cpp_runtime_invoke");
    t_il2cpp_string_chars         string_chars        = (t_il2cpp_string_chars)        sym("il2cpp_string_chars");
    t_il2cpp_string_length        string_length       = (t_il2cpp_string_length)       sym("il2cpp_string_length");
    t_il2cpp_thread_attach        thread_attach       = (t_il2cpp_thread_attach)       sym("il2cpp_thread_attach");
    t_il2cpp_thread_detach        thread_detach       = (t_il2cpp_thread_detach)       sym("il2cpp_thread_detach");
    t_il2cpp_domain_assembly_open domain_assembly_open = (t_il2cpp_domain_assembly_open) sym("il2cpp_domain_assembly_open");

    if (!il2cpp_domain_get || !dom_get_assemblies || !assembly_get_image || !image_get_name ||
        !class_from_name || !mget || !runtime_invoke) {
        NSLog(@"[Loader v3] missing core il2cpp symbols");
        return NO;
    }

    void* domain = il2cpp_domain_get();
    if (!domain) { NSLog(@"[Loader v3] il2cpp_domain_get() NULL"); return NO; }

    void* attached = NULL;
    if (thread_attach) attached = thread_attach(domain);

    const void** assemblies = NULL; size_t count = 0;
    dom_get_assemblies(domain, &assemblies, &count);
    NSLog(@"[Loader v3] assembly count = %zu ptr=%p", count, assemblies);

    if ((count == 0 || !assemblies) && domain_assembly_open) {
        void* a = domain_assembly_open(domain, "AnimalCompany.dll");
        NSLog(@"[Loader v3] domain_assembly_open(\"AnimalCompany.dll\") -> %p", a);
        dom_get_assemblies(domain, &assemblies, &count);
        NSLog(@"[Loader v3] assemblies after open = %zu", count);
    }

    if (!assemblies || count == 0) {
        NSLog(@"[Loader v3] no assemblies available yet");
        if (thread_detach && attached) thread_detach(attached);
        return NO;
    }

    void* animalImage = NULL;
    for (size_t i = 0; i < count; i++) {
        void* img = assembly_get_image((void*)assemblies[i]);
        const char* name = img ? image_get_name(img) : NULL;
        if (name && (strstr(name, "AnimalCompany.dll") || strstr(name, "AnimalCompany"))) { animalImage = img; break; }
    }
    if (!animalImage) {
        NSLog(@"[Loader v3] AnimalCompany image not loaded yet");
        if (thread_detach && attached) thread_detach(attached);
        return NO;
    }

    // find AnimalCompanyAPI class
    void* apiKlass = class_from_name(animalImage, "AnimalCompany.API", "AnimalCompanyAPI");
    if (!apiKlass) {
        NSLog(@"[Loader v3] AnimalCompany.API.AnimalCompanyAPI not found");
        if (thread_detach && attached) thread_detach(attached);
        return NO;
    }

    // try both common getter name variants
    void* m_getInstance = mget(apiKlass, "get_instance", 0);
    if (!m_getInstance) m_getInstance = mget(apiKlass, "get_Instance", 0);
    if (!m_getInstance) {
        NSLog(@"[Loader v3] AnimalCompanyAPI.get_instance/get_Instance not found");
        if (thread_detach && attached) thread_detach(attached);
        return NO;
    }

    void* exc = NULL;
    void* instanceObj = runtime_invoke(m_getInstance, NULL, NULL, &exc);
    if (!instanceObj) {
        NSLog(@"[Loader v3] AnimalCompanyAPI instance getter returned NULL (exc=%p)", exc);
        if (thread_detach && attached) thread_detach(attached);
        return NO;
    }
    NSLog(@"[Loader v3] got AnimalCompanyAPI instance %p", instanceObj);

    // Try to get Session from the instance: instance.get_Session()
    void* m_getSession = mget(apiKlass, "get_Session", 0);
    void* sessionObj = NULL;
    if (m_getSession) {
        exc = NULL;
        sessionObj = runtime_invoke(m_getSession, instanceObj, NULL, &exc);
        if (!sessionObj) {
            NSLog(@"[Loader v3] instance.get_Session returned NULL (exc=%p)", exc);
            // continue to try other fallbacks if needed
        } else {
            NSLog(@"[Loader v3] got session object %p from instance.get_Session", sessionObj);
        }
    } else {
        NSLog(@"[Loader v3] instance.get_Session not found on AnimalCompanyAPI");
    }

    // If we didn't get session from instance, look for Nakama image and try to locate Session via other means
    void* nakamaImage = NULL;
    if (!sessionObj) {
        for (size_t i = 0; i < count; i++) {
            void* img = assembly_get_image((void*)assemblies[i]);
            const char* name = img ? image_get_name(img) : NULL;
            if (name && (strstr(name, "Nakama.dll") || strstr(name, "Nakama"))) { nakamaImage = img; break; }
        }
        if (!nakamaImage) {
            NSLog(@"[Loader v3] Nakama image not present yet (can't resolve session type)");
            if (thread_detach && attached) thread_detach(attached);
            return NO;
        }
        // If AnimalCompanyAPI exposes a Nakama.Client or similar static, user asked session is on instance so we stop here if none
        NSLog(@"[Loader v3] session not found on instance and no fallback implemented");
        if (thread_detach && attached) thread_detach(attached);
        return NO;
    }

    // Now resolve Nakama.Session class and get_AuthToken
    // find Nakama image (may already be found)
    if (!nakamaImage) {
        for (size_t i = 0; i < count; i++) {
            void* img = assembly_get_image((void*)assemblies[i]);
            const char* name = img ? image_get_name(img) : NULL;
            if (name && (strstr(name, "Nakama.dll") || strstr(name, "Nakama"))) { nakamaImage = img; break; }
        }
    }
    if (!nakamaImage) {
        NSLog(@"[Loader v3] Nakama image not loaded (cannot call get_AuthToken)");
        if (thread_detach && attached) thread_detach(attached);
        return NO;
    }

    void* sessionKlass = class_from_name(nakamaImage, "Nakama", "Session");
    if (!sessionKlass) {
        // Some builds may put Session in different namespace/class name; log and fail
        NSLog(@"[Loader v3] Nakama.Session class not found in image");
        if (thread_detach && attached) thread_detach(attached);
        return NO;
    }

    void* m_getAuth = mget(sessionKlass, "get_AuthToken", 0);
    if (!m_getAuth) {
        NSLog(@"[Loader v3] Nakama.Session.get_AuthToken not found");
        if (thread_detach && attached) thread_detach(attached);
        return NO;
    }

    exc = NULL;
    void* tokenIl2cppStr = runtime_invoke(m_getAuth, sessionObj, NULL, &exc);
    if (!tokenIl2cppStr) {
        NSLog(@"[Loader v3] get_AuthToken returned NULL (exc=%p)", exc);
        if (thread_detach && attached) thread_detach(attached);
        return NO;
    }

    if (!string_chars || !string_length) {
        NSLog(@"[Loader v3] il2cpp_string_chars/length missing");
        if (thread_detach && attached) thread_detach(attached);
        return NO;
    }

    const uint16_t* w = string_chars(tokenIl2cppStr);
    int32_t len = string_length(tokenIl2cppStr);
    NSLog(@"[Loader v3] token Il2CppString len=%d ptr=%p", len, w);
    if (!w || len <= 0) {
        NSLog(@"[Loader v3] token empty");
        if (thread_detach && attached) thread_detach(attached);
        return NO;
    }

    NSString *token = [NSString stringWithCharacters:(unichar*)w length:(NSUInteger)len];
    NSLog(@"[Loader v3] Nakama Session AuthToken = %@", token);

    if (thread_detach && attached) thread_detach(attached);
    return YES;
}

static void retry_read_loop(void) {
    __block int attempts = 0;
    __block void (^tick)(void);
    tick = ^{
        attempts++;
        NSLog(@"[Loader v3] auth attempt %d", attempts);
        if (read_auth_from_instance_once()) {
            NSLog(@"[Loader v3] read_auth_from_instance_once success");
            return;
        }
        if (attempts < 240) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), tick);
        } else {
            NSLog(@"[Loader v3] gave up after %d attempts", attempts);
        }
    };
    tick();
}


__attribute__((constructor))
static void ctor(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        // Start a bit later so Unity gets at least one frame.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            retry_read_loop();
        });
    });
}
