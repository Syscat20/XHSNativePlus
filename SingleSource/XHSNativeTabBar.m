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

#pragma mark - 滚动联动

// 小红书的页面是多层嵌套的分页容器，系统找不到真正在滚的那个列表。
// 手指开始拖的时候把它登记成当前页面的内容滚动视图，系统的「滚动收起底栏」才会生效。

@interface XHSNativeScrollTracker : NSObject
@end

@implementation XHSNativeScrollTracker

+ (instancetype)shared {
    static XHSNativeScrollTracker *tracker;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ tracker = [XHSNativeScrollTracker new]; });
    return tracker;
}

- (void)pan:(UIPanGestureRecognizer *)pan {
    UIScrollView *list = (UIScrollView *)pan.view;
    if (pan.state != UIGestureRecognizerStateBegan || ![list isKindOfClass:UIScrollView.class]) return;
    // 只认竖向列表，横向分页容器不算
    if (list.contentSize.height <= CGRectGetHeight(list.bounds) && !list.alwaysBounceVertical) return;
    if (list.contentSize.width > CGRectGetWidth(list.bounds) + 1 && list.pagingEnabled) return;

    UINavigationController *navigation = (UINavigationController *)XHSNativeConfig.shared.tabBarController.selectedViewController;
    UIViewController *page = [navigation isKindOfClass:UINavigationController.class] ? navigation.topViewController : navigation;
    if (!page.isViewLoaded || ![list isDescendantOfView:page.view]) return;
    [XHSNativeHelper attachHomeBar:list];
    if ([page contentScrollViewForEdge:NSDirectionalRectEdgeBottom] != list) [page setContentScrollView:list forEdge:NSDirectionalRectEdgeBottom];
}

@end

@implementation XHSNativeHelper (TabBar)

#pragma mark - 底栏

// 当前显示着的、对应某个页面的标签
+ (UITab *)tabNamed:(NSString *)name {
    for (UITab *tab in XHSNativeConfig.shared.tabBarController.tabs)
        if ([tab.identifier isEqualToString:name]) return tab;
    return nil;
}

+ (NSArray<NSString *> *)legacyTabNames:(XYTabbarController *)controller {
    return [[controller.customtabBar valueForKey:@"tabs"] valueForKey:@"itemName"];
}

+ (void)refreshBadge:(UITabBarItem *)item {
    if ([item respondsToSelector:@selector(_updateViewBadge)]) [item _updateViewBadge];
}

+ (BOOL)isItemEnabled:(UITabBarItem *)item {
    XHSNativeConfig *config = XHSNativeConfig.shared;
    if (config.searchPage && item == config.searchPage.tabBarItem) return YES;
    for (NSUInteger i = 0; i < config.pages.count; i++) {
        if (item == config.pages[i].tabBarItem) return [self tabNamed:config.pageNames[i]].enabled;
    }
    return NO;
}

+ (BOOL)isOurTabBar:(UITabBar *)bar {
    XYTabbarController *controller = XHSNativeConfig.shared.tabBarController;
    return controller && bar == controller.tabBar;
}

+ (void)rebuildTabs {
    XHSNativeConfig *config = XHSNativeConfig.shared;
    XYTabbarController *controller = config.tabBarController;
    if (!controller || !config.pages.count) return;
    // 底栏被二级页面盖住时（比如正在设置页里改）先记一笔，等它重新露出来再换
    config.tabsDirty = controller.isTabBarHidden;
    if (config.tabsDirty) return;

    // 每次都建新的标签对象：沿用旧对象重排的话，系统会把留下来的那几个画成灰的
    NSString *selected = controller.selectedTab.identifier;
    NSMutableArray<UITab *> *tabs = [NSMutableArray array];
    NSArray *legacyNames = [self legacyTabNames:controller];
    BOOL showLabels = config.isTabLabelsEnabled;
    NSDictionary<NSString *, NSString *> *titles = @{@"index": @"首页", @"shopping": @"市集", @"message": @"消息", @"me": @"我"};
    for (NSString *name in config.tabOrder) {
        NSUInteger index = [config.pageNames indexOfObject:name];
        if (index == NSNotFound || [config isTabHidden:name]) continue;
        UIViewController *page = config.pages[index];
        NSString *title = showLabels ? (titles[name] ?: @"") : @"";
        UITab *tab = [[UITab alloc] initWithTitle:title image:[self tabIcon:name selected:NO] identifier:name viewControllerProvider:^UIViewController *(UITab *t) { return page; }];
        if ([tab respondsToSelector:@selector(setSelectedImage:)]) [(id)tab setSelectedImage:[self tabIcon:name selected:YES]];
        NSUInteger badgeIndex = [legacyNames indexOfObject:name];
        tab.badgeValue = (legacyNames && badgeIndex != NSNotFound) ? controller.badgeValueDict[@(badgeIndex)] : [self tabNamed:name].badgeValue;
        [tabs addObject:tab];
    }
    BOOL swapped = config.isPublishSwapped;
    if ([config boolForKey:kXHSNativeSearchTab] || swapped) {
        // 系统的搜索标签会自己单独排在右边。它不切页面，点了直接开小红书的搜索，见 shouldSelectTab。
        // 交换搜索与发布时，这一格换成发布
        if (!config.searchPage) config.searchPage = [UIViewController new];
        UIViewController *page = config.searchPage;
        UISearchTab *search = [[UISearchTab alloc] initWithViewControllerProvider:^UIViewController *(UITab *t) { return page; }];
        search.automaticallyActivatesSearch = YES;
        if (swapped) {
            search.title = showLabels ? @"发布" : @"";
            search.image = [UIImage systemImageNamed:@"plus"];
        } else if (showLabels) {
            search.title = @"搜索";
        }
        [tabs addObject:search];
    }
    config.rebuilding = YES;
    [controller setTabs:tabs animated:NO];
    controller.tabBar.tintColor = config.isTabRedTintEnabled
        ? [UIColor colorWithRed:1.0 green:0.141 blue:0.259 alpha:1.0]
        : nil;
    for (UITabBarItem *item in controller.tabBar.items) {
        if (!item.enabled && [self isItemEnabled:item]) item.enabled = YES;
        if (item.badgeValue) [self refreshBadge:item];
    }
    // 旧栏保留给发布和角标使用。其他插件可能在布局时重新显示它。
    if ([self tabNamed:@"index"]) controller.customtabBar.alpha = 0;
    UITab *restored = selected ? [self tabNamed:selected] : nil;
    if (restored) controller.selectedTab = restored;
    controller.tabBarMinimizeBehavior = [config boolForKey:kXHSNativeMinimize] ? UITabBarMinimizeBehaviorOnScrollDown : UITabBarMinimizeBehaviorNever;
    config.rebuilding = NO;
}

// 等同于点原来的加号
+ (void)openPublish {
    XYTabbarController *controller = XHSNativeConfig.shared.tabBarController;
    UIControl *button = [controller respondsToSelector:@selector(centerButton)] ? [controller centerButton] : nil;
    if ([button isKindOfClass:UIControl.class]) [button sendActionsForControlEvents:UIControlEventTouchUpInside];
}

// 等同于点首页顶栏原来的搜索。搜索页是从首页进的，不在首页时先切回去
+ (void)openSearch {
    XHSNativeConfig *config = XHSNativeConfig.shared;
    UITab *home = [self tabNamed:@"index"];
    if (home && config.tabBarController.selectedTab != home) config.tabBarController.selectedTab = home;
    dispatch_async(dispatch_get_main_queue(), ^{
        [config.searchButton sendActionsForControlEvents:UIControlEventTouchUpInside];
    });
}

// 重复点当前标签。小红书的每个标签页都实现了 XYTabbarClicked（首页是回到顶部并刷新），
// 原来由它的自绘底栏调用，换成系统底栏后要自己转过去
+ (void)reselectTab:(UITab *)tab {
    UINavigationController *navigation = (UINavigationController *)tab.viewController;
    UIViewController *page = [navigation isKindOfClass:UINavigationController.class] ? navigation.viewControllers.firstObject : navigation;
    SEL clicked = NSSelectorFromString(@"XYTabbarClicked");
    if ([page respondsToSelector:clicked]) ((void (*)(id, SEL))objc_msgSend)(page, clicked);
}

#pragma mark - 首页顶栏

static char kBarEdgeKey, kSoftEdgeKey, kPublishKey, kSegmentGlassKey;

+ (NSHashTable *)pinnedEdgeEffects {
    static NSHashTable *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ table = [NSHashTable weakObjectsHashTable]; });
    return table;
}

+ (BOOL)isPinnedEdgeEffect:(UIScrollEdgeEffect *)effect {
    return [[self pinnedEdgeEffects] containsObject:effect];
}

+ (BOOL)hasSoftTopEdge:(UIScrollView *)list {
    return objc_getAssociatedObject(list, &kSoftEdgeKey) != nil;
}

+ (void)useSoftTopEdge:(UIScrollView *)list {
    if ([self hasSoftTopEdge:list]) return;
    objc_setAssociatedObject(list, &kSoftEdgeKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [[self pinnedEdgeEffects] addObject:list.topEdgeEffect];
    list.topEdgeEffect.style = UIScrollEdgeEffectStyle.softStyle;
    list.topEdgeEffect.hidden = NO;
}

// 这个列表是不是当前屏幕上、压在顶栏下面的那个竖向列表
+ (BOOL)isList:(UIScrollView *)list underBar:(UIView *)bar {
    if (list.hidden || !list.window || list.window != bar.window) return NO;
    if (list.contentSize.width > CGRectGetWidth(list.bounds) + 1 && list.pagingEnabled) return NO;
    if (list.contentSize.height <= CGRectGetHeight(list.bounds) && !list.alwaysBounceVertical) return NO;
    CGRect frame = [list convertRect:list.bounds toView:nil], barFrame = [bar convertRect:bar.bounds toView:nil];
    if (CGRectGetWidth(CGRectIntersection(frame, list.window.bounds)) < CGRectGetWidth(list.window.bounds) / 2) return NO;  // 在左右相邻的页里
    return CGRectGetMinY(frame) < CGRectGetMaxY(barFrame) - 1 && CGRectGetHeight(frame) > CGRectGetHeight(barFrame) * 2;
}

// 告诉系统顶栏压在这个列表上，边缘效果才会按顶栏的高度铺开。同一时刻只跟当前在看的那个列表
+ (void)attachHomeBar:(UIScrollView *)list {
    UIView *bar = XHSNativeConfig.shared.homeBar;
    if (!bar || ![self isList:list underBar:bar]) return;
    [self useSoftTopEdge:list];
    UIScrollEdgeElementContainerInteraction *interaction = objc_getAssociatedObject(bar, &kBarEdgeKey);
    if (!interaction) {
        interaction = [UIScrollEdgeElementContainerInteraction new];
        interaction.edge = UIRectEdgeTop;
        [bar addInteraction:interaction];
        objc_setAssociatedObject(bar, &kBarEdgeKey, interaction, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (interaction.scrollView != list) interaction.scrollView = list;
}

+ (void)findListIn:(UIView *)root underBar:(UIView *)bar best:(UIScrollView **)best {
    if ([root isKindOfClass:UIScrollView.class] && [self isList:(UIScrollView *)root underBar:bar] &&
        (!*best || CGRectGetHeight(root.bounds) > CGRectGetHeight((*best).bounds)))
        *best = (UIScrollView *)root;
    for (UIView *view in root.subviews) [self findListIn:view underBar:bar best:best];
}

// 左右切到别的页（关注 / 发现 / 同城）之后，把边缘效果接到新出现的那个列表上
+ (void)attachVisibleList {
    UIView *bar = XHSNativeConfig.shared.homeBar;
    if (!bar.window) return;
    UIScrollView *list = nil;
    [self findListIn:bar.superview underBar:bar best:&list];
    if (list) [self attachHomeBar:list];
}

// 主题图、分隔线和通栏磨砂各是一层，主题图的高度会按图片比例变化。
+ (void)stripBarBackground:(XYMHomeNaviBar *)bar {
    [self clearBackground:bar];
    UIView *theme = [bar respondsToSelector:@selector(background)] ? bar.background : nil;
    Class separator = objc_getClass("_XYSeparatorView");
    for (UIView *view in bar.subviews) {
        if (view.alpha == 0) continue;
        BOOL fullWidth = CGRectGetWidth(bar.bounds) > 0 &&
                         fabs(CGRectGetMinX(view.frame) - CGRectGetMinX(bar.bounds)) < 1 &&
                         fabs(CGRectGetWidth(view.frame) - CGRectGetWidth(bar.bounds)) < 1;
        BOOL backdrop = fullWidth && view.subviews.count <= 2 &&
            ([view isMemberOfClass:UIVisualEffectView.class] ||
             ([view isMemberOfClass:UIView.class] && (!view.userInteractionEnabled || CGRectEqualToRect(view.frame, bar.bounds))));
        if (view == theme || backdrop || (fullWidth && [view isKindOfClass:separator])) view.alpha = 0;
    }
}

+ (void)layoutHomeBar:(XYMHomeNaviBar *)bar {
    XHSNativeConfig.shared.homeBar = bar;
    [self stripBarBackground:bar];

    UIButton *publish = objc_getAssociatedObject(bar, &kPublishKey);
    UIView *menu = nil, *segment = nil, *search = nil;
    for (UIView *view in bar.subviews) {
        NSString *name = NSStringFromClass(view.class);
        if ([name isEqualToString:@"XYMenuButton"]) menu = view;
        else if ([name isEqualToString:@"XYSegmentControl"]) segment = view;
        else if (view != publish && [view isKindOfClass:UIButton.class] && (!search || CGRectGetMinX(view.frame) > CGRectGetMinX(search.frame))) search = view;
    }
    if (!menu || !search) return;
    XHSNativeConfig.shared.searchButton = (UIControl *)search;

    if (XHSNativeConfig.shared.isPublishSwapped) {
        // 发布去了底栏，原来的搜索留在顶栏。之前收起过的话放出来
        if (publish) {
            [publish removeFromSuperview];
            objc_setAssociatedObject(bar, &kPublishKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            for (UIView *view in bar.subviews) {
                BOOL backing = [view isKindOfClass:UIVisualEffectView.class] && CGRectEqualToRect(view.frame, search.frame);
                if (view == search || backing) view.hidden = NO;
            }
        }
    } else {
        if (!publish) {
            UIButtonConfiguration *config = [UIButtonConfiguration glassButtonConfiguration];
            config.image = [UIImage systemImageNamed:@"plus"];
            config.preferredSymbolConfigurationForImage = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium];
            config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
            config.baseForegroundColor = UIColor.labelColor;
            publish = [UIButton buttonWithConfiguration:config primaryAction:[UIAction actionWithHandler:^(UIAction *action) { [XHSNativeHelper openPublish]; }]];
            publish.accessibilityLabel = @"发布";
            objc_setAssociatedObject(bar, &kPublishKey, publish, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (publish.superview != bar) [bar addSubview:publish];
        if (!CGRectEqualToRect(publish.frame, search.frame)) publish.frame = search.frame;
        // 原搜索按钮和它背后那块玻璃都收起来（玻璃是和按钮同一位置的另一个视图）
        for (UIView *view in bar.subviews) {
            BOOL backing = [view isKindOfClass:UIVisualEffectView.class] && CGRectEqualToRect(view.frame, search.frame);
            if ((view == search || backing) && !view.hidden) view.hidden = YES;
        }
    }

    if (!segment) return;
    // 「关注 发现 同城」垫一块玻璃，文字压在图片上才看得清；高度和两侧按钮对齐，在两个按钮之间居中
    CGFloat left = CGRectGetMaxX(menu.frame) + 8, right = CGRectGetMinX(search.frame) - 8;
    CGFloat width = MIN(right - left, CGRectGetWidth(segment.frame) + 16);
    CGFloat x = left + (right - left - width) / 2;
    CGRect frame = segment.frame;
    frame.origin.x = x + (width - CGRectGetWidth(frame)) / 2;
    if (!CGRectEqualToRect(segment.frame, frame)) segment.frame = frame;
    CGRect plate = segment.hidden ? CGRectZero : CGRectMake(x, CGRectGetMinY(menu.frame), width, CGRectGetHeight(menu.frame));
    [self plateOn:bar key:&kSegmentGlassKey below:segment frame:plate bar:kXHSNativeBarHome];
}

// 首页的频道页（关注 发现 同城）都由 childViewModels 提供，标题、分页、按频道找下标都从这里取，
// 在这一处过滤就能整个藏掉。全藏了就不过滤
+ (NSArray *)visibleChannels:(NSArray *)children {
    XHSNativeConfig *config = XHSNativeConfig.shared;
    NSMutableArray *visible = [NSMutableArray array];
    for (id child in children)
        if (![child respondsToSelector:@selector(childVCPageName)] || ![config isChannelHidden:[child childVCPageName]]) [visible addObject:child];
    return visible.count ? visible : children;
}

// 默认打开的频道被藏了，就打开剩下的第一个
+ (NSUInteger)landingChannel:(NSUInteger)page ofHome:(XYMHomeViewController *)home {
    if (![XHSNativeConfig.shared isChannelHidden:page]) return page;
    id first = [[home dataSource] childViewModels].firstObject;
    return [first respondsToSelector:@selector(childVCPageName)] ? [first childVCPageName] : page;
}

// 首页左上角的入口由服务器按账号下发：SETTING 侧边栏菜单，DOT 点点，RED_BOX 红包。
// 禁用点点时把 DOT 当成 SETTING，图标和点击都回到侧边栏菜单
+ (NSString *)leftEntranceType:(NSString *)type {
    if (!XHSNativeConfig.shared.isDotsDisabled || ![type isEqualToString:@"DOT"]) return type;
    return @"SETTING";
}

// 入口按侧边栏菜单处理时，服务器配的图标还是点点的那张，不让顶栏再去套它
+ (BOOL)keepsMenuIcon {
    if (!XHSNativeConfig.shared.isDotsDisabled) return NO;
    return [[[objc_getClass("XYHomeModule.MainFrameEntranceConfigManager") shared] leftSideBarType] isEqualToString:@"SETTING"];
}

#pragma mark - 滚动联动

+ (void)trackScrollView:(UIScrollView *)list {
    static char key;
    if (!list.window || objc_getAssociatedObject(list, &key)) return;
    objc_setAssociatedObject(list, &key, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [list.panGestureRecognizer addTarget:[XHSNativeScrollTracker shared] action:@selector(pan:)];
}

#pragma mark - 市集 / 消息 / 我

// 换成悬浮的系统底栏后，这几页底下会空出一条。原因有两种：
// 页面按旧底栏的高度（44 + 底部安全区）把内容区截短了（市集），或者页面不肯延伸到栏下面（消息）。

static BOOL nearlyEqual(CGFloat a, CGFloat b) {
    return fabs(a - b) < 1.5;
}

// 把一个「底边正好停在旧底栏上沿」的视图往下加长 gap
static BOOL growView(UIView *view, CGFloat gap) {
    for (NSLayoutConstraint *constraint in view.constraints) {
        if (constraint.firstItem == view && !constraint.secondItem && constraint.firstAttribute == NSLayoutAttributeHeight &&
            constraint.relation == NSLayoutRelationEqual && constraint.isActive && nearlyEqual(constraint.constant, CGRectGetHeight(view.bounds))) {
            constraint.constant += gap;
            return YES;
        }
    }
    for (NSLayoutConstraint *constraint in view.superview.constraints) {
        if (!constraint.isActive || constraint.relation != NSLayoutRelationEqual || constraint.multiplier != 1) continue;
        BOOL pinned = (constraint.firstItem == view && constraint.secondItem == view.superview) || (constraint.firstItem == view.superview && constraint.secondItem == view);
        if (!pinned || constraint.firstAttribute != NSLayoutAttributeBottom || constraint.secondAttribute != NSLayoutAttributeBottom) continue;
        if (nearlyEqual(fabs(constraint.constant), gap)) {
            constraint.constant = 0;
            return YES;
        }
    }
    if (!view.translatesAutoresizingMaskIntoConstraints) return NO;
    CGRect frame = view.frame;
    frame.size.height += gap;
    view.frame = frame;
    return YES;
}

static void extendDown(UIView *parent, UIView *root, CGFloat gap, int depth) {
    CGFloat height = CGRectGetHeight(root.bounds), width = CGRectGetWidth(root.bounds);
    for (UIView *view in [parent.subviews copy]) {
        if (view.hidden || view.alpha < 0.01) continue;
        CGRect frame = [root convertRect:view.bounds fromView:view];
        if (CGRectGetWidth(frame) < width * 0.9 || CGRectGetHeight(frame) <= gap) continue;
        if (nearlyEqual(CGRectGetMaxY(frame), height - gap) && growView(view, gap)) {
            [view.superview layoutIfNeeded];
            frame = [root convertRect:view.bounds fromView:view];
        }
        if (CGRectGetMaxY(frame) < height - gap - 1.5) continue;  // 够不到底部那一段，里面不用看
        if ([view isKindOfClass:UIScrollView.class]) {
            UIScrollView *list = (UIScrollView *)view;
            if (list.contentSize.width <= CGRectGetWidth(list.bounds) + 1) {
                // 延伸到底的竖向列表，末尾留出底栏的位置；里面是单元格，不往里找
                if (nearlyEqual(CGRectGetMaxY(frame), height) && list.adjustedContentInset.bottom < gap) {
                    UIEdgeInsets inset = list.contentInset;
                    inset.bottom += gap - list.adjustedContentInset.bottom;
                    list.contentInset = inset;
                }
                continue;
            }
        }
        if (depth < 9) extendDown(view, root, gap, depth + 1);
    }
}

+ (void)extendTabPage:(UIViewController *)page {
    UINavigationController *navigation = page.navigationController;
    if (!page.view.window || navigation.viewControllers.firstObject != page || navigation.parentViewController != XHSNativeConfig.shared.tabBarController) return;
    if (!(page.edgesForExtendedLayout & UIRectEdgeBottom)) {
        page.edgesForExtendedLayout |= UIRectEdgeBottom;
        [navigation.view setNeedsLayout];
    }
    static BOOL busy;
    if (busy) return;
    busy = YES;
    extendDown(page.view, page.view, 44 + page.view.window.safeAreaInsets.bottom, 0);
    busy = NO;
}

@end
