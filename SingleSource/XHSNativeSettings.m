//
//  XHSNative
//
//  Copyright (c) 2026 huami. All rights reserved.
//  Channel: @huamidev
//  Created on: 2026/11/24
//
#import "XHSNativeGlassShared.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import "XHSNativeConfig.h"

#pragma mark - 设置界面

// 小红书的设置组件，属性都是返回 block 的链式写法，下面几个小函数把调用包一下

static id blockOf(id target, NSString *name) {
    return ((id (*)(id, SEL))objc_msgSend)(target, NSSelectorFromString(name));
}

static id rowTitle(NSString *text) {
    id (^make)(NSString *) = blockOf(objc_getClass("StandardOptionTitle"), @"title");
    return make(text);
}

static id with(id object, NSString *name, id value) {
    id (^apply)(id) = blockOf(object, name);
    return apply(value);
}

static id withFlag(id object, NSString *name, BOOL value) {
    id (^apply)(BOOL) = blockOf(object, name);
    return apply(value);
}

static id row(NSString *kind, id title, NSString *identity) {
    id (^make)(id) = blockOf(objc_getClass("StandardOption"), kind);
    return with(make(title), @"setIdentity", identity);
}

static id gap(CGFloat height) {
    id (^make)(double) = blockOf(objc_getClass("StandardOption"), @"blank");
    return make(height);
}

static id switchRow(NSString *title, BOOL on, NSString *identity) {
    return row(@"switcher", withFlag(rowTitle(title), @"setSwitcherIsOn", on), identity);
}

static NSDictionary<NSString *, NSString *> *tabTitles(void) {
    return @{@"index": @"首页", @"shopping": @"市集", @"message": @"消息", @"me": @"我"};
}

static NSArray<NSArray *> *glassBars(void) {
    return @[@[@"首页顶栏", kXHSNativeBarHome], @[@"笔记顶栏", kXHSNativeBarNoteTop], @[@"笔记底栏", kXHSNativeBarNoteBottom],
             @[@"视频顶栏", kXHSNativeBarVideoTop], @[@"视频底栏", kXHSNativeBarVideoBottom],
             @[@"评论输入栏", kXHSNativeBarComment], @[@"个人页顶栏", kXHSNativeBarProfile]];
}

@implementation XHSNativeHelper (Settings)

+ (NSString *)entryIdentity {
    return @"XHSNative";
}

+ (id)entryOption {
    return row(@"leftIconArrow", with(rowTitle(@"XHSNativePlus"), @"setIconFont", [self themeGlyph:@"filters_b"]), [self entryIdentity]);
}

+ (NSArray *)settingsRows {
    XHSNativeConfig *config = XHSNativeConfig.shared;
    NSMutableArray *rows = [NSMutableArray arrayWithObject:gap(12)];

    [rows addObject:row(@"label", rowTitle(@"底部标签栏"), @"tabs.heading")];
    [rows addObject:gap(8)];
    for (NSString *name in @[@"me", @"shopping", @"message"])
        [rows addObject:switchRow(tabTitles()[name], ![config isTabHidden:name], [@"tab." stringByAppendingString:name])];
    [rows addObject:switchRow(@"搜索", [config boolForKey:kXHSNativeSearchTab], [@"pref." stringByAppendingString:kXHSNativeSearchTab])];
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    for (NSString *name in config.tabOrder) [order addObject:tabTitles()[name]];
    [rows addObject:row(@"arrow", with(rowTitle(@"标签顺序"), @"setTrailing", [order componentsJoinedByString:@" "]), @"order")];
    [rows addObject:switchRow(@"显示标签文字", config.isTabLabelsEnabled, [@"pref." stringByAppendingString:kXHSNativeTabLabels])];
    [rows addObject:switchRow(@"底栏选中显示主题红", config.isTabRedTintEnabled, [@"pref." stringByAppendingString:kXHSNativeTabRedTint])];
    [rows addObject:switchRow(@"滚动时收起", [config boolForKey:kXHSNativeMinimize], [@"pref." stringByAppendingString:kXHSNativeMinimize])];
    [rows addObject:switchRow(@"交换搜索与发布", config.isPublishSwapped, [@"pref." stringByAppendingString:kXHSNativeSwapPublish])];
    [rows addObject:gap(8)];
    [rows addObject:row(@"label", rowTitle(@"交换后，发布在底栏右侧，搜索回到首页顶栏。"), @"tabs.note")];
    [rows addObject:gap(24)];

    [rows addObject:row(@"label", rowTitle(@"首页"), @"home.heading")];
    [rows addObject:gap(8)];
    NSArray *channels = @[@"关注", @"发现", @"同城"];
    for (NSUInteger page = 0; page < channels.count; page++)
        [rows addObject:switchRow(channels[page], ![config isChannelHidden:page], [NSString stringWithFormat:@"channel.%lu", (unsigned long)page])];
    [rows addObject:switchRow(@"禁用点点 AI", config.isDotsDisabled, [@"pref." stringByAppendingString:kXHSNativeDisableDots])];
    [rows addObject:gap(8)];
    [rows addObject:row(@"label", rowTitle(@"频道及禁用点点 AI 需重启小红书生效。"), @"home.note")];
    [rows addObject:gap(24)];

    [rows addObject:row(@"label", rowTitle(@"浏览与交互"), @"interaction.heading")];
    [rows addObject:gap(8)];
    [rows addObject:switchRow(@"双击放大图片", config.isDoubleTapZoomEnabled, [@"pref." stringByAppendingString:kXHSNativeDoubleTapZoom])];
    [rows addObject:switchRow(@"无水印保存", config.isNoWatermarkEnabled, [@"pref." stringByAppendingString:kXHSNativeNoWatermark])];
    [rows addObject:switchRow(@"解除保存限制", config.isSaveRestrictionIgnored, [@"pref." stringByAppendingString:kXHSNativeIgnoreNoSave])];
    [rows addObject:switchRow(@"禁用视频左下角「说点什么」", [NSUserDefaults.standardUserDefaults boolForKey:kXHSNativeVideoDisableCompose],
                              [@"pref." stringByAppendingString:kXHSNativeVideoDisableCompose])];
    [rows addObject:switchRow(@"禁用图文左下角「说点什么」", [NSUserDefaults.standardUserDefaults boolForKey:kXHSNativeNoteDisableCompose],
                              [@"pref." stringByAppendingString:kXHSNativeNoteDisableCompose])];
    [rows addObject:switchRow(@"私聊 iMessage 风格气泡", [config boolForKey:kXHSNativeChatIMessage],
                              [@"pref." stringByAppendingString:kXHSNativeChatIMessage])];
    [rows addObject:gap(8)];
    [rows addObject:row(@"label", rowTitle(@"双击放大的图片，再双击缩回。"), @"interaction.note")];
    [rows addObject:gap(24)];

    [rows addObject:row(@"label", rowTitle(@"页面液态玻璃"), @"glass.heading")];
    [rows addObject:gap(8)];
    for (NSArray *option in @[@[@"视频页", kXHSNativeGlassVideo], @[@"图文笔记页", kXHSNativeGlassNote], @[@"搜索栏", kXHSNativeGlassSearch],
                              @[@"消息页顶栏与菜单", kXHSNativeGlassMessages], @[@"评论输入栏", kXHSNativeGlassComments],
                              @[@"私聊输入栏", kXHSNativeGlassChat], @[@"个人页顶栏", kXHSNativeGlassProfile]])
        [rows addObject:switchRow(option[0], [config boolForKey:option[1]], [@"pref." stringByAppendingString:option[1]])];
    [rows addObject:gap(8)];
    [rows addObject:row(@"label", rowTitle(@"下次进入对应页面时生效。"), @"glass.note")];
    [rows addObject:gap(24)];

    [rows addObject:row(@"label", rowTitle(@"不透明度"), @"fillHeading")];
    [rows addObject:gap(8)];
    for (NSArray *bar in glassBars()) {
        id title = with(rowTitle(bar[0]), @"setTrailing", [NSString stringWithFormat:@"%.0f%%", [config fillForBar:bar[1]]]);
        [rows addObject:row(@"arrow", title, [@"fill." stringByAppendingString:bar[1]])];
    }
    [rows addObject:gap(24)];
    [rows addObject:row(@"button", rowTitle(@"恢复默认"), @"reset")];
    return rows;
}

+ (NSArray *)orderRows {
    NSMutableArray *rows = [NSMutableArray array];
    for (NSString *name in XHSNativeConfig.shared.tabOrder)
        [rows addObject:withFlag(row(@"text", rowTitle(tabTitles()[name]), name), @"setCornerMaskUsesCellBounds", YES)];
    return rows;
}

// 选不透明度：0% 是纯玻璃，越大越不透
+ (NSArray *)percentRowsForBar:(NSString *)bar {
    NSInteger current = (NSInteger)[XHSNativeConfig.shared fillForBar:bar];
    NSMutableArray *rows = [NSMutableArray arrayWithObject:gap(12)];
    for (NSInteger percent = 0; percent <= 100; percent += 10) {
        id title = withFlag(rowTitle([NSString stringWithFormat:@"%ld%%", (long)percent]), @"setSelected", percent == current);
        [rows addObject:row(@"selector", title, [NSString stringWithFormat:@"percent.%ld", (long)percent])];
    }
    [rows addObject:gap(8)];
    [rows addObject:row(@"label", rowTitle(@"0% 是纯玻璃，数值越大越不透。"), @"note")];
    return rows;
}

+ (NSString *)titleForMode:(NSString *)mode {
    if (!mode) return @"XHSNativePlus";
    if ([mode isEqualToString:@"order"]) return @"标签顺序";
    for (NSArray *bar in glassBars())
        if ([bar[1] isEqualToString:mode]) return [bar[0] stringByAppendingString:@"不透明度"];
    return @"XHSNativePlus";
}

+ (UIView *)settingsFooterWithWidth:(CGFloat)width {
    UIStackView *footer = [UIStackView new];
    footer.axis = UILayoutConstraintAxisVertical;
    footer.alignment = UIStackViewAlignmentCenter;
    footer.spacing = 8;
    footer.layoutMarginsRelativeArrangement = YES;
    footer.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(14, 0, 14, 0);

    UIFont *font = [UIFont systemFontOfSize:12];
    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    NSInteger year = [calendar component:NSCalendarUnitYear fromDate:NSDate.date];
    NSString *copyright = [NSString stringWithFormat:@"© %ld Syscat20 & huamidev", (long)year];
    NSArray *lines = @[@"XHSNativePlus", @"Version: " XHSNativeVersion, @"Modified by Syscat20 · Based on huami1314", copyright];
    CGFloat opacity[] = {0.8, 0.56, 0.56 * 0.7, 0.56 * 0.5};
    for (NSUInteger i = 0; i < lines.count; i++) {
        UILabel *label = [UILabel new];
        label.text = lines[i];
        label.font = font;
        label.textAlignment = NSTextAlignmentCenter;
        label.textColor = [UIColor.labelColor colorWithAlphaComponent:opacity[i]];
        [footer addArrangedSubview:label];
    }
    CGFloat height = [footer systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].height;
    footer.frame = CGRectMake(0, 0, width, ceil(height));
    return footer;
}

+ (void)handleTap:(NSString *)identity onPage:(XHSNativeSettingsPage *)page {
    XHSNativeConfig *config = XHSNativeConfig.shared;
    if ([identity isEqualToString:@"order"] || [identity hasPrefix:@"fill."]) {
        XHSNativeSettingsPage *next = [[objc_getClass("XHSNativeSettingsPage") alloc] init];
        next.mode = [identity hasPrefix:@"fill."] ? [identity substringFromIndex:5] : identity;
        [page.navigationController pushViewController:next animated:YES];
    } else if ([identity hasPrefix:@"percent."]) {
        [config setFill:[identity substringFromIndex:8].doubleValue forBar:page.mode];
        [self applySettings];
        [page.navigationController popViewControllerAnimated:YES];
    } else if ([identity isEqualToString:@"reset"]) {
        [config reset];
        [self applySettings];
        [page reloadRows];
    }
}

+ (void)handleSwitch:(NSString *)identity on:(BOOL)on {
    XHSNativeConfig *config = XHSNativeConfig.shared;
    if ([identity hasPrefix:@"pref."]) [config setBool:on forKey:[identity substringFromIndex:5]];
    else if ([identity hasPrefix:@"tab."]) [config setTab:[identity substringFromIndex:4] hidden:!on];
    else if ([identity hasPrefix:@"channel."]) [config setChannel:[identity substringFromIndex:8].integerValue hidden:!on];
    [self applySettings];
}

+ (void)applySettings {
    XYTabbarController *tb = XHSNativeConfig.shared.tabBarController;
    if (tb) {
        tb.tabBar.tintColor = XHSNativeConfig.shared.isTabRedTintEnabled
            ? [UIColor colorWithRed:1.0 green:0.141 blue:0.259 alpha:1.0]
            : nil;
    }
    [self rebuildTabs];
    [XHSNativeConfig.shared.homeBar setNeedsLayout];
    for (UIView *host in XHSGlassActiveHosts()) [host setNeedsLayout];
}

@end
