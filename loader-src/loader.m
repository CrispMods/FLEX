// --- IL2CPP minimal API typedefs ---
typedef void* (*t_il2cpp_domain_get)();
typedef void  (*t_il2cpp_domain_get_assemblies)(void* domain, const void*** assemblies, size_t* size);
typedef const char* (*t_il2cpp_image_get_name)(void* image);
typedef void* (*t_il2cpp_assembly_get_image)(void* assembly);
typedef void* (*t_il2cpp_class_from_name)(void* image, const char* namesp, const char* name);
typedef void* (*t_il2cpp_class_get_method_from_name)(void* klass, const char* name, int argsCount);
typedef void* (*t_il2cpp_runtime_invoke)(void* method, void* obj, void** params, void** exc);
typedef const uint16_t* (*t_il2cpp_string_chars)(void* il2cppStr);

// Resolve IL2CPP exports from UnityFramework
static void* sym(const char* s){ return dlsym(RTLD_DEFAULT, s); }

static void logAuthToken() {
    t_il2cpp_domain_get               il2cpp_domain_get               = (t_il2cpp_domain_get)sym("il2cpp_domain_get");
    t_il2cpp_domain_get_assemblies    il2cpp_domain_get_assemblies    = (t_il2cpp_domain_get_assemblies)sym("il2cpp_domain_get_assemblies");
    t_il2cpp_assembly_get_image       il2cpp_assembly_get_image       = (t_il2cpp_assembly_get_image)sym("il2cpp_assembly_get_image");
    t_il2cpp_image_get_name           il2cpp_image_get_name           = (t_il2cpp_image_get_name)sym("il2cpp_image_get_name");
    t_il2cpp_class_from_name          il2cpp_class_from_name          = (t_il2cpp_class_from_name)sym("il2cpp_class_from_name");
    t_il2cpp_class_get_method_from_name il2cpp_class_get_method_from_name = (t_il2cpp_class_get_method_from_name)sym("il2cpp_class_get_method_from_name");
    t_il2cpp_runtime_invoke           il2cpp_runtime_invoke           = (t_il2cpp_runtime_invoke)sym("il2cpp_runtime_invoke");
    t_il2cpp_string_chars             il2cpp_string_chars             = (t_il2cpp_string_chars)sym("il2cpp_string_chars");

    if (!il2cpp_domain_get) { NSLog(@"[Loader] il2cpp symbols missing"); return; }

    // 1) find Nakama image
    void* domain = il2cpp_domain_get();
    const void** assemblies = NULL; size_t count = 0;
    il2cpp_domain_get_assemblies(domain, &assemblies, &count);

    void* nakamaImage = NULL;
    for (size_t i=0;i<count;i++){
        void* asmbl = (void*)assemblies[i];
        void* img = il2cpp_assembly_get_image(asmbl);
        const char* name = il2cpp_image_get_name(img);
        if (name && strstr(name, "Nakama.dll")) { nakamaImage = img; break; }
    }
    if (!nakamaImage) { NSLog(@"[Loader] Nakama.dll not found"); return; }

    // 2) Client.get_Instance()
    void* clientKlass = il2cpp_class_from_name(nakamaImage, "Nakama", "Client");
    if (!clientKlass) { NSLog(@"[Loader] Nakama.Client class not found"); return; }
    void* m_getInstance = il2cpp_class_get_method_from_name(clientKlass, "get_Instance", 0);
    if (!m_getInstance){ NSLog(@"[Loader] get_Instance not found"); return; }
    void* exc = NULL;
    void* clientSingleton = il2cpp_runtime_invoke(m_getInstance, NULL, NULL, &exc);
    if (!clientSingleton){ NSLog(@"[Loader] Client.Instance is null"); return; }

    // 3) Client.get_Session()
    void* m_getSession = il2cpp_class_get_method_from_name(clientKlass, "get_Session", 0);
    if (!m_getSession){ NSLog(@"[Loader] get_Session not found"); return; }
    void* sessionObj = il2cpp_runtime_invoke(m_getSession, clientSingleton, NULL, &exc);
    if (!sessionObj){ NSLog(@"[Loader] Session is null"); return; }

    // 4) Session.get_AuthToken()
    void* sessionKlass = il2cpp_class_from_name(nakamaImage, "Nakama", "Session");
    if (!sessionKlass){ NSLog(@"[Loader] Nakama.Session class not found"); return; }
    void* m_getAuth = il2cpp_class_get_method_from_name(sessionKlass, "get_AuthToken", 0);
    if (!m_getAuth){ NSLog(@"[Loader] get_AuthToken not found"); return; }
    void* tokenStr = il2cpp_runtime_invoke(m_getAuth, sessionObj, NULL, &exc);
    if (!tokenStr){ NSLog(@"[Loader] AuthToken returned null"); return; }

    // Convert Il2CppString (UTF-16) to NSString for logging
    const uint16_t* w = il2cpp_string_chars(tokenStr);
    NSString* ns = [NSString stringWithCharacters:(unichar*)w length:w ? wcslen((wchar_t*)w) : 0];
    NSLog(@"[Loader] Nakama Session AuthToken = %@", ns);
}
