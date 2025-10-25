#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

__attribute__((constructor))
static void initFieldLogger() {
    Class cls = objc_getClass("YourTargetClass");
    SEL sel = @selector(viewDidLoad);
    Method originalMethod = class_getInstanceMethod(cls, sel);
    void (*originalImp)(id, SEL) = (void *)method_getImplementation(originalMethod);

    void newImp(id self, SEL _cmd) {
        originalImp(self, _cmd);

        Ivar ivar = class_getInstanceVariable(cls, "_authToken");
        if (ivar) {
            id value = object_getIvar(self, ivar);
            NSLog(@"[FieldLogger] authToken = %@", value);
        } else {
            NSLog(@"[FieldLogger] Ivar _authToken not found");
        }
    }

    method_setImplementation(originalMethod, (IMP)newImp);
}
