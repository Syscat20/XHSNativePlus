//
//  XHSNative
//
//  Copyright (c) 2026 huami. All rights reserved.
//  Channel: @huamidev
//  Created on: 2026/11/24
//
#import "XHSNativeHelper.h"
#import <dlfcn.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <mach/mach.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "XHSNativeConfig.h"

#pragma mark - 小红书主程序

// 小红书主程序的镜像。不按 MH_EXECUTE 找：用 LiveContainer 这类容器加载时，进程的主程序是容器自己，
// 小红书是被当成动态库加载进来的。按它里面的类落在哪个镜像来找，两种情况都对
struct XHSAppImage {
    const struct mach_header_64 *header;
    intptr_t slide;
    uintptr_t textSize;
};

static const struct XHSAppImage *appImage(void) {
    static struct XHSAppImage app;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Dl_info info;
        if (!dladdr((__bridge void *)objc_getClass("XYTabbarController"), &info) || !info.dli_fbase) return;
        const struct mach_header_64 *header = (const struct mach_header_64 *)info.dli_fbase;
        if (header->magic != MH_MAGIC_64) return;
        const struct load_command *command = (const struct load_command *)(header + 1);
        for (uint32_t i = 0; i < header->ncmds; i++, command = (const struct load_command *)((const char *)command + command->cmdsize)) {
            const struct segment_command_64 *segment = (const struct segment_command_64 *)command;
            if (command->cmd != LC_SEGMENT_64 || strcmp(segment->segname, SEG_TEXT)) continue;
            app.header = header;
            app.slide = (intptr_t)header - (intptr_t)segment->vmaddr;
            app.textSize = segment->vmsize;
            break;
        }
    });
    return &app;
}

#pragma mark - iOS 27.1 以下

// 首页的下沉布局是按 iOS 27.1 写的，用到三个更早的系统上没有的东西：
// 特征 verticalBarEdge，Swift 的 UITraitCollection.systemTraitsAffectingVerticalBarEdge
// 和 UIView.LayoutRegion.bar(onEdge:extent:)。
// 第一个补一个返回「未指定」的方法。后两个在导入表里是空的，一调就崩：
// 一个填上返回空数组的函数（没有竖排栏，也就没有要监听的特征），
// 一个填上转给 safeArea 的跳板（没有竖排栏时这个区域的上边界就是安全区，结果一样）。

static NSInteger verticalBarEdgeUnspecified(id self, SEL _cmd) {
    return 0;
}

// 跳板的目标和参数。参数是 AdaptivityAxis?，这个枚举跨模块按地址传，nil 是字节 2
__attribute__((used, visibility("hidden"))) void *gSafeAreaRegion;
__attribute__((used, visibility("hidden"))) uint64_t gNoAxis = 2;

__attribute__((naked)) static void layoutRegionBar(void) {
    __asm__ volatile("adrp x16, _gSafeAreaRegion@PAGE\n"
                     "ldr x16, [x16, _gSafeAreaRegion@PAGEOFF]\n"
                     "adrp x0, _gNoAxis@PAGE\n"
                     "add x0, x0, _gNoAxis@PAGEOFF\n"
                     "br x16\n");
}

// 在主程序的导入表里按符号名找到对应的指针槽：间接符号表 → 符号表 → 名字
static void **importSlot(const char *symbol) {
    const struct mach_header_64 *header = appImage()->header;
    intptr_t slide = appImage()->slide;
    if (!header) return NULL;

    const struct symtab_command *symtab = NULL;
    const struct dysymtab_command *dysymtab = NULL;
    const struct segment_command_64 *linkedit = NULL;
    const struct load_command *command = (const struct load_command *)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++, command = (const struct load_command *)((const char *)command + command->cmdsize)) {
        if (command->cmd == LC_SYMTAB) symtab = (const struct symtab_command *)command;
        else if (command->cmd == LC_DYSYMTAB) dysymtab = (const struct dysymtab_command *)command;
        else if (command->cmd == LC_SEGMENT_64 && !strcmp(((const struct segment_command_64 *)command)->segname, SEG_LINKEDIT)) linkedit = (const struct segment_command_64 *)command;
    }
    if (!symtab || !dysymtab || !linkedit) return NULL;
    uintptr_t base = slide + linkedit->vmaddr - linkedit->fileoff;
    const struct nlist_64 *symbols = (const struct nlist_64 *)(base + symtab->symoff);
    const char *strings = (const char *)(base + symtab->stroff);
    const uint32_t *indirect = (const uint32_t *)(base + dysymtab->indirectsymoff);

    command = (const struct load_command *)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++, command = (const struct load_command *)((const char *)command + command->cmdsize)) {
        if (command->cmd != LC_SEGMENT_64) continue;
        const struct segment_command_64 *segment = (const struct segment_command_64 *)command;
        const struct section_64 *section = (const struct section_64 *)(segment + 1);
        for (uint32_t j = 0; j < segment->nsects; j++, section++) {
            uint32_t type = section->flags & SECTION_TYPE;
            if (type != S_NON_LAZY_SYMBOL_POINTERS && type != S_LAZY_SYMBOL_POINTERS) continue;
            void **slots = (void **)(section->addr + slide);
            for (size_t k = 0; k < section->size / sizeof(void *); k++) {
                uint32_t index = indirect[section->reserved1 + k];
                if ((index & (INDIRECT_SYMBOL_ABS | INDIRECT_SYMBOL_LOCAL)) || index >= symtab->nsyms) continue;
                if (!strcmp(strings + symbols[index].n_un.n_strx, symbol)) return &slots[k];
            }
        }
    }
    return NULL;
}

static void *noTraits(void) {
    static void *empty;
    if (!empty) empty = dlsym(RTLD_DEFAULT, "_swiftEmptyArrayStorage");
    return empty;
}

static void fillImport(const char *symbol, void *replacement) {
    void **slot = importSlot(symbol);
    if (!slot || *slot) return;  // 槽里有东西说明系统自带，不用补
    vm_address_t page = (vm_address_t)slot & ~(vm_page_size - 1);
    if (vm_protect(mach_task_self(), page, vm_page_size, false, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY) != KERN_SUCCESS) return;
    *slot = replacement;
    vm_protect(mach_task_self(), page, vm_page_size, false, VM_PROT_READ);
}

@implementation XHSNativeHelper

#pragma mark - 视图

+ (UIVisualEffectView *)plateOn:(UIView *)owner key:(const void *)key below:(UIView *)below frame:(CGRect)frame bar:(NSString *)bar {
    UIVisualEffectView *glass = objc_getAssociatedObject(owner, key);
    if (!glass) {
        UIGlassEffect *effect = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
        effect.interactive = YES;
        glass = [[UIVisualEffectView alloc] initWithEffect:effect];
        glass.cornerConfiguration = [UICornerConfiguration capsuleConfiguration];
        glass.userInteractionEnabled = NO;
        glass.contentView.layer.masksToBounds = YES;
        objc_setAssociatedObject(owner, key, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    BOOL empty = CGRectIsEmpty(frame) || !below.superview;
    if (glass.hidden != empty) glass.hidden = empty;
    if (empty) return glass;

    NSArray<UIView *> *siblings = below.superview.subviews;
    NSUInteger index = [siblings indexOfObjectIdenticalTo:below];
    if (glass.superview != below.superview || index == 0 || siblings[index - 1] != glass) [below.superview insertSubview:glass belowSubview:below];
    if (!CGRectEqualToRect(glass.frame, frame)) glass.frame = frame;

    // 不透明度：在玻璃上垫一层半透明的底色
    UIView *content = glass.contentView;
    NSInteger fill = (NSInteger)[XHSNativeConfig.shared fillForBar:bar];
    if (content.tag != fill + 1) {
        content.tag = fill + 1;
        content.backgroundColor = fill ? [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor colorWithRed:0.13 green:0.13 blue:0.15 alpha:fill / 100.0]
                                                                         : [UIColor colorWithWhite:1 alpha:fill / 100.0];
        }] : nil;
    }
    content.layer.cornerRadius = CGRectGetHeight(frame) / 2;
    return glass;
}

+ (void)clearBackground:(UIView *)view {
    if (view.backgroundColor && ![view.backgroundColor isEqual:UIColor.clearColor]) view.backgroundColor = UIColor.clearColor;
}

+ (BOOL)isVisible:(UIView *)view {
    return view && !view.hidden && view.alpha > 0.01 && CGRectGetWidth(view.bounds) > 0 && CGRectGetHeight(view.bounds) > 0;
}

+ (UIView *)subviewOf:(UIView *)view named:(NSString *)className {
    for (UIView *subview in view.subviews)
        if ([NSStringFromClass(subview.class) isEqualToString:className]) return subview;
    return nil;
}

#pragma mark - 小红书

// 这几个方法调用得很频繁，不用 dladdr，先算好主程序代码段的地址范围直接比
+ (BOOL)isAppAddress:(void *)address {
    uintptr_t start = (uintptr_t)appImage()->header;
    return start && (uintptr_t)address >= start && (uintptr_t)address < start + appImage()->textSize;
}

+ (id)themeGlyph:(NSString *)name {
    Class managerClass = objc_getClass("XYThemeManager");
    if (![managerClass respondsToSelector:NSSelectorFromString(@"defaultManager")]) return nil;
    id manager = ((id (*)(id, SEL))objc_msgSend)(managerClass, NSSelectorFromString(@"defaultManager"));
    if (![manager respondsToSelector:NSSelectorFromString(@"icon")]) return nil;
    id set = ((id (*)(id, SEL))objc_msgSend)(manager, NSSelectorFromString(@"icon"));
    return [set respondsToSelector:NSSelectorFromString(name)] ? ((id (*)(id, SEL))objc_msgSend)(set, NSSelectorFromString(name)) : nil;
}

// 取成图片的写法是 .size(28).image
+ (UIImage *)themeIcon:(NSString *)name {
    id glyph = [self themeGlyph:name];
    if (![glyph respondsToSelector:NSSelectorFromString(@"size")]) return nil;
    id (^sized)(CGFloat) = ((id (*)(id, SEL))objc_msgSend)(glyph, NSSelectorFromString(@"size"));
    id result = sized ? sized(28) : nil;
    if (![result respondsToSelector:NSSelectorFromString(@"image")]) return nil;
    UIImage *image = ((id (*)(id, SEL))objc_msgSend)(result, NSSelectorFromString(@"image"));
    return [image isKindOfClass:UIImage.class] ? [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] : nil;
}

+ (UIImage *)tabIcon:(NSString *)name selected:(BOOL)selected {
    NSDictionary *theme = @{@"index": @"home", @"shopping": @"store", @"message": @"chat", @"me": @"me"};
    NSDictionary *symbols = @{@"index": @"house", @"shopping": @"bag", @"message": @"message", @"me": @"person"};
    UIImage *image = [self themeIcon:[theme[name] stringByAppendingString:selected ? @"_f" : @"_b"]];
    return image ?: [UIImage systemImageNamed:selected ? [symbols[name] stringByAppendingString:@".fill"] : symbols[name]];
}

#pragma mark - iOS 27.1 以下

+ (void)patchOlderSystems {
    class_addMethod(UITraitCollection.class, NSSelectorFromString(@"verticalBarEdge"), (IMP)verticalBarEdgeUnspecified, "q@:");
    if (noTraits()) fillImport("_$sSo17UITraitCollectionC5UIKitE36systemTraitsAffectingVerticalBarEdgeSayAC0A10Definition_pXpGvgZ", (void *)noTraits);
    gSafeAreaRegion = dlsym(RTLD_DEFAULT, "$sSo6UIViewC5UIKitE12LayoutRegionV8safeArea16cornerAdaptationA2E14AdaptivityAxisOSg_tFZ");
    if (gSafeAreaRegion) fillImport("_$sSo6UIViewC5UIKitE12LayoutRegionV3bar6onEdge6extentAESo06UIRectG0V_12CoreGraphics7CGFloatVtFZ", (void *)layoutRegionBar);
}

@end
