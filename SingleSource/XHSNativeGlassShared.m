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

@implementation XHSNativeNoteBottomReference
@end

@implementation XHSNativeVideoGlassPill

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (!hit) return nil;
    if ([hit isKindOfClass:UIButton.class]) return hit;
    UIButton *nearest = nil;
    CGFloat best = CGFLOAT_MAX;
    for (UIButton *button in self.buttons) {
        if (!button.enabled || button.hidden || button.alpha <= 0.01) continue;
        CGRect frame = [self convertRect:button.bounds fromView:button];
        if (CGRectContainsPoint(frame, point)) return button;
        CGFloat distance = fabs(CGRectGetMidX(frame) - point.x);
        if (distance < best) {
            best = distance;
            nearest = button;
        }
    }
    return nearest ?: hit;
}

@end

@implementation XHSNativeVideoOverlayView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || self.alpha <= 0.01 || !self.userInteractionEnabled) return nil;
    for (UIView *pill in self.interactivePills.reverseObjectEnumerator) {
        if (pill.hidden || pill.alpha <= 0.01 || !pill.userInteractionEnabled) continue;
        CGPoint local = [pill convertPoint:point fromView:self];
        UIView *hit = [pill hitTest:local withEvent:event];
        if (hit) return hit;
    }
    return nil;
}

@end

@implementation XHSNativeAvatarMirror

- (void)sync {
    UIImage *img = self.source.image;
    if (self.target && self.target.image != img) self.target.image = img;
    if (self.fallback) self.fallback.hidden = (img != nil);
}

- (void)attachSource:(UIImageView *)source target:(UIImageView *)target fallback:(UIImageView *)fallback {
    if (self.source != source) {
        if (self.source) {
            @try { [self.source removeObserver:self forKeyPath:@"image"]; } @catch (id e) {}
        }
        self.source = source;
        if (source) [source addObserver:self forKeyPath:@"image" options:NSKeyValueObservingOptionNew context:NULL];
    }
    self.target = target;
    self.fallback = fallback;
    [self sync];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    dispatch_async(dispatch_get_main_queue(), ^{ [self sync]; });
}

- (void)dealloc {
    if (self.source) {
        @try { [self.source removeObserver:self forKeyPath:@"image"]; } @catch (id e) {}
    }
}

@end

@implementation XHSNativeVideoState
@end

static char kVideoStateKey, kVideoOurHiddenKey;

NSHashTable<UIView *> *XHSGlassActiveHosts(void) {
    static NSHashTable<UIView *> *hosts;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ hosts = [NSHashTable weakObjectsHashTable]; });
    return hosts;
}

XHSNativeVideoState *XHSGlassExistingState(UIView *host) {
    return objc_getAssociatedObject(host, &kVideoStateKey);
}

XHSNativeVideoState *XHSGlassStateForHost(UIView *host) {
    XHSNativeVideoState *state = XHSGlassExistingState(host);
    if (!state) {
        state = [XHSNativeVideoState new];
        state.host = host;
        state.hiddenViews = [NSMapTable weakToStrongObjectsMapTable];
        objc_setAssociatedObject(host, &kVideoStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [XHSGlassActiveHosts() addObject:host];
    return state;
}

// 复用池回收组件时，防止上一页残留 opacity=0 导致新页面误判为不可见
void XHSGlassClearOurHide(UIView *view) {
    if (!view || !objc_getAssociatedObject(view, &kVideoOurHiddenKey)) return;
    objc_setAssociatedObject(view, &kVideoOurHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (view.layer.opacity == 0) view.layer.opacity = 1;
    [CATransaction commit];
    if (view.accessibilityElementsHidden) view.accessibilityElementsHidden = NO;
    if (!view.userInteractionEnabled) view.userInteractionEnabled = YES;
}

BOOL XHSGlassIsItemActive(UIView *view) {
    if (!view || view.hidden || CGRectGetWidth(view.bounds) <= 0 || CGRectGetHeight(view.bounds) <= 0) return NO;
    if (objc_getAssociatedObject(view, &kVideoOurHiddenKey)) return YES;
    return view.alpha > 0.01;
}

void XHSGlassRestoreOriginals(XHSNativeVideoState *state) {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (UIView *view in state.hiddenViews) {
        NSArray<NSNumber *> *saved = [state.hiddenViews objectForKey:view];
        objc_setAssociatedObject(view, &kVideoOurHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (view.layer.opacity == 0) view.layer.opacity = saved[0].floatValue;
        view.accessibilityElementsHidden = saved[1].boolValue;
        view.userInteractionEnabled = saved[2].boolValue;
    }
    [CATransaction commit];
    [state.hiddenViews removeAllObjects];
}

void XHSGlassHideOriginal(XHSNativeVideoState *state, UIView *view) {
    if (!view) return;
    if (![state.hiddenViews objectForKey:view]) {
        float initialOpacity = (objc_getAssociatedObject(view, &kVideoOurHiddenKey) && view.layer.opacity == 0) ? 1.0f : view.layer.opacity;
        [state.hiddenViews setObject:@[@(initialOpacity), @(view.accessibilityElementsHidden), @(view.userInteractionEnabled)] forKey:view];
    }
    objc_setAssociatedObject(view, &kVideoOurHiddenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (view.layer.opacity != 0) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        view.layer.opacity = 0;
        [CATransaction commit];
    }
    if (!view.accessibilityElementsHidden) view.accessibilityElementsHidden = YES;
}

void XHSGlassDisableOriginal(XHSNativeVideoState *state, UIView *view) {
    if (!view) return;
    XHSGlassHideOriginal(state, view);
    if (view.userInteractionEnabled) view.userInteractionEnabled = NO;
}

id XHSGlassSafeProp(id object, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    if (![object respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

UIControlEvents XHSGlassControlActivation(UIControl *control) {
    if (![control isKindOfClass:UIControl.class]) return 0;
    UIControlEvents handlers = control.allControlEvents;
    if (handlers & UIControlEventTouchUpInside) return UIControlEventTouchUpInside;
    if (handlers & UIControlEventPrimaryActionTriggered) return UIControlEventPrimaryActionTriggered;
    if (handlers & UIControlEventTouchDown) return UIControlEventTouchDown;
    return 0;
}

UIControl *XHSGlassControlIn(UIView *root) {
    if (!XHSGlassIsItemActive(root)) return nil;
    if ([root isKindOfClass:UIControl.class] && XHSGlassControlActivation((UIControl *)root)) return (UIControl *)root;
    for (UIView *child in root.subviews) {
        UIControl *found = XHSGlassControlIn(child);
        if (found) return found;
    }
    return nil;
}

UIView *XHSGlassControlWithSuffix(UIView *parent, NSString *suffix) {
    for (UIView *child in parent.subviews) {
        if ([child isKindOfClass:XHSNativeVideoOverlayView.class]) continue;
        if ([NSStringFromClass(child.class) hasSuffix:suffix]) return child;
        if (child.hidden || [child isKindOfClass:UIVisualEffectView.class]) continue;
        UIView *match = XHSGlassControlWithSuffix(child, suffix);
        if (match) return match;
    }
    return nil;
}

void XHSGlassRelayAction(UIView *sourceView, id fallbackTarget, SEL fallbackSelector, BOOL sendsArg) {
    UIControl *control = [sourceView isKindOfClass:UIControl.class] ? (UIControl *)sourceView : XHSGlassControlIn(sourceView);
    UIControlEvents event = XHSGlassControlActivation(control);
    if (control && control.enabled && event) {
        [control sendActionsForControlEvents:event];
        return;
    }
    if (fallbackTarget && fallbackSelector && [fallbackTarget respondsToSelector:fallbackSelector]) {
        if (sendsArg) ((void (*)(id, SEL, id))objc_msgSend)(fallbackTarget, fallbackSelector, sourceView);
        else ((void (*)(id, SEL))objc_msgSend)(fallbackTarget, fallbackSelector);
    }
}

UIImage *XHSGlassSymbol(NSString *name, CGFloat pointSize, UIImageSymbolWeight weight) {
    if (!name.length) return nil;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:weight];
    return [UIImage systemImageNamed:name withConfiguration:cfg];
}

static UIColor *XHSGlassFillColor(NSString *barName, BOOL adaptiveTheme, double fill) {
    if (!fill) return nil;
    if (!adaptiveTheme) return [UIColor colorWithRed:0.13 green:0.13 blue:0.15 alpha:fill / 100.0];
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:0.13 green:0.13 blue:0.15 alpha:fill / 100.0]
            : [UIColor colorWithWhite:1.0 alpha:fill / 100.0];
    }];
}

void XHSGlassApplyPillFill(XHSNativeVideoGlassPill *pill) {
    NSInteger fill = (NSInteger)[XHSNativeConfig.shared fillForBar:pill.barName];
    UIView *content = pill.contentView;
    if (content.tag != fill + 1) {
        content.tag = fill + 1;
        content.backgroundColor = XHSGlassFillColor(pill.barName, pill.adaptiveTheme, (double)fill);
    }
}

XHSNativeVideoGlassPill *XHSGlassMakePill(NSArray<UIButton *> *buttons, NSString *barName, CGFloat spacing, BOOL adaptiveTheme) {
    UIGlassEffect *glass = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
    glass.interactive = YES;
    XHSNativeVideoGlassPill *pill = [[XHSNativeVideoGlassPill alloc] initWithEffect:glass];
    pill.adaptiveTheme = adaptiveTheme;
    pill.overrideUserInterfaceStyle = adaptiveTheme ? UIUserInterfaceStyleUnspecified : UIUserInterfaceStyleDark;
    pill.cornerConfiguration = [UICornerConfiguration capsuleConfiguration];
    pill.contentView.layer.masksToBounds = YES;
    pill.barName = barName;
    pill.buttons = buttons;
    XHSGlassApplyPillFill(pill);

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:buttons];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.alignment = UIStackViewAlignmentFill;
    stack.distribution = UIStackViewDistributionFill;
    stack.spacing = spacing;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [pill.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:pill.contentView.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:pill.contentView.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:pill.contentView.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:pill.contentView.bottomAnchor],
    ]];
    return pill;
}

XHSNativeVideoOverlayView *XHSGlassEnsureOverlay(XHSNativeVideoState *state, CGFloat spacing, BOOL adaptiveTheme) {
    if (!state.overlayView) {
        UIGlassContainerEffect *container = [UIGlassContainerEffect new];
        container.spacing = spacing;
        XHSNativeVideoOverlayView *overlay = [[XHSNativeVideoOverlayView alloc] initWithEffect:container];
        overlay.overrideUserInterfaceStyle = adaptiveTheme ? UIUserInterfaceStyleUnspecified : UIUserInterfaceStyleDark;
        overlay.frame = state.host.bounds;
        overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        state.overlayView = overlay;
    }
    if (state.overlayView.superview != state.host) [state.host addSubview:state.overlayView];
    return state.overlayView;
}

NSString *XHSGlassCountText(NSString *text) {
    NSString *value = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!value.length || [value rangeOfString:@"^[0-9][0-9,. ]*(?:[kKmMwW万亿+])?$"
                                      options:NSRegularExpressionSearch].location == NSNotFound) return nil;
    NSString *digits = [[value stringByReplacingOccurrencesOfString:@"," withString:@""] stringByReplacingOccurrencesOfString:@" " withString:@""];
    if ([digits rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location != NSNotFound)
        return value;
    long long count = digits.longLongValue;
    if (count <= 0) return nil;
    if (count < 1000) return digits;
    return [NSString stringWithFormat:@"%.1fk", floor(count / 100.0) / 10.0];
}

static NSString *XHSGlassOwnCount(UIView *view) {
    NSString *text = XHSGlassCountText(view.accessibilityValue) ?: XHSGlassCountText(view.accessibilityLabel);
    if (!text && [view isKindOfClass:UIButton.class]) {
        UIButton *button = (UIButton *)view;
        text = XHSGlassCountText(button.titleLabel.text) ?: XHSGlassCountText(button.currentTitle);
    }
    if (!text && [view isKindOfClass:UILabel.class]) text = XHSGlassCountText(((UILabel *)view).text);
    return text;
}

NSString *XHSGlassCountIn(UIView *view) {
    if (!view || view.hidden) return nil;
    NSString *text = XHSGlassOwnCount(view);
    if (text) return text;
    for (UIView *child in view.subviews) {
        text = XHSGlassCountIn(child);
        if (text) return text;
    }
    return nil;
}

static void XHSGlassCollectCounts(UIView *view, UIView *host, UIView *skip,
                               NSMutableArray<NSValue *> *centers, NSMutableArray<NSString *> *texts) {
    if (!view || view.hidden || view == skip) return;
    NSString *text = XHSGlassOwnCount(view);
    if (text) {
        CGRect rect = [host convertRect:view.bounds fromView:view];
        [centers addObject:[NSValue valueWithCGPoint:CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect))]];
        [texts addObject:text];
    }
    for (UIView *child in view.subviews) XHSGlassCollectCounts(child, host, skip, centers, texts);
}

NSString *XHSGlassCountNear(UIView *host, UIView *target, UIView *skip) {
    if (!host || !target) return nil;
    NSMutableArray<NSValue *> *centers = [NSMutableArray array];
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    XHSGlassCollectCounts(host, host, skip, centers, texts);
    CGRect targetRect = [host convertRect:target.bounds fromView:target];
    CGPoint center = CGPointMake(CGRectGetMidX(targetRect), CGRectGetMidY(targetRect));
    NSString *best = nil;
    CGFloat bestDistance = CGFLOAT_MAX;
    for (NSUInteger i = 0; i < texts.count; i++) {
        CGPoint point = centers[i].CGPointValue;
        CGFloat dx = fabs(point.x - center.x), dy = fabs(point.y - center.y);
        if (dx > 44 || dy > 30) continue;
        if (dx + dy < bestDistance) {
            bestDistance = dx + dy;
            best = texts[i];
        }
    }
    return best;
}

void XHSGlassBounceSymbol(UIButton *button) {
    Class bounceClass = NSClassFromString(@"NSSymbolBounceEffect");
    SEL bounceSel = NSSelectorFromString(@"bounceUpEffect");
    SEL addSel = NSSelectorFromString(@"addSymbolEffect:");
    if (!bounceClass || ![bounceClass respondsToSelector:bounceSel] || ![button.imageView respondsToSelector:addSel]) return;
    id effect = ((id (*)(id, SEL))objc_msgSend)(bounceClass, bounceSel);
    if (effect) ((void (*)(id, SEL, id))objc_msgSend)(button.imageView, addSel, effect);
}

UIButton *XHSGlassMakeActionButton(NSString *symbol, NSString *a11yLabel, UIColor *defaultColor, void (^handler)(UIAction *)) {
    UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
    config.baseForegroundColor = defaultColor;
    config.image = XHSGlassSymbol(symbol, 18, UIImageSymbolWeightMedium);
    config.imagePadding = 5;
    config.titleLineBreakMode = NSLineBreakByClipping;
    config.contentInsets = NSDirectionalEdgeInsetsMake(0, 12, 0, 12);
    config.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *incoming) {
        NSMutableDictionary *attrs = [incoming mutableCopy];
        attrs[NSFontAttributeName] = [UIFont monospacedDigitSystemFontOfSize:13.5 weight:UIFontWeightSemibold];
        return attrs;
    };
    UIButton *button = [UIButton buttonWithConfiguration:config primaryAction:[UIAction actionWithHandler:handler]];
    button.accessibilityLabel = a11yLabel;
    button.titleLabel.lineBreakMode = NSLineBreakByClipping;
    button.titleLabel.numberOfLines = 1;
    [button setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [button setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    return button;
}

static void XHSGlassSetBottomButtonContent(UIButton *button, NSString *symbol, NSString *count,
                                        UIColor *foreground, BOOL selected, BOOL compact, BOOL isFirst, BOOL isLast) {
    UIButtonConfiguration *config = [button.configuration copy];
    config.image = XHSGlassSymbol(symbol, 18, UIImageSymbolWeightMedium);
    config.baseForegroundColor = foreground;
    config.title = count;
    CGFloat innerPad = compact ? (count.length ? 6 : 8) : (count.length ? 8 : 10);
    CGFloat outerExtra = compact ? 6 : 8;
    CGFloat leading = innerPad + (isFirst ? outerExtra : 0);
    CGFloat trailing = innerPad + (isLast ? outerExtra : 0);
    config.imagePadding = compact ? 3.5 : 4.5;
    config.contentInsets = NSDirectionalEdgeInsetsMake(0, leading, 0, trailing);
    button.configuration = config;
    button.accessibilityValue = count;
    if (selected) button.accessibilityTraits |= UIAccessibilityTraitSelected;
    else button.accessibilityTraits &= ~UIAccessibilityTraitSelected;
}

void XHSGlassRefreshBottom(XHSNativeVideoState *state, BOOL adaptiveTheme) {
    if (!state.engagePill || state.overlayView.hidden) return;
    NSArray<NSString *> *allSymbols = @[@"heart", @"star", @"bubble"];
    UIColor *defaultColor = adaptiveTheme ? UIColor.labelColor : UIColor.whiteColor;
    UIColor *likeRed = [UIColor colorWithRed:1.0 green:0.18 blue:0.33 alpha:1.0];
    UIColor *collectGold = adaptiveTheme ? [UIColor colorWithRed:0.96 green:0.65 blue:0.0 alpha:1.0] : UIColor.systemYellowColor;
    NSUInteger total = state.engageButtons.count;
    for (NSUInteger i = 0; i < total && i < state.engageRoleViews.count && i < state.engageRoles.count; i++) {
        XHSGlassItemRole role = (XHSGlassItemRole)state.engageRoles[i].integerValue;
        UIView *roleView = state.engageRoleViews[i];
        UIControl *control = i < state.engageControls.count ? state.engageControls[i] : nil;
        UIButton *button = state.engageButtons[i];
        NSString *count = XHSGlassCountIn(roleView) ?: (adaptiveTheme ? nil : XHSGlassCountNear(state.host, roleView, state.overlayView));
        BOOL selected = NO;
        if (role == XHSGlassItemRoleLike) {
            selected = state.hasLikeOverride ? state.likeSelectedOverride : control.selected;
            if (!count && state.hasLikeOverride && state.likeCountOverride > 0) {
                count = XHSGlassCountText([NSString stringWithFormat:@"%ld", (long)state.likeCountOverride]);
            }
            state.lastLiked = selected;
        } else if (role == XHSGlassItemRoleCollect) {
            selected = control.selected;
        }
        NSString *baseSymbol = allSymbols[(NSUInteger)role];
        NSString *symbol = selected ? [baseSymbol stringByAppendingString:@".fill"] : baseSymbol;
        UIColor *fg = defaultColor;
        if (selected) fg = (role == XHSGlassItemRoleLike) ? likeRed : collectGold;
        XHSGlassSetBottomButtonContent(button, symbol, count, fg, selected, state.compactEngage, i == 0, i + 1 == total);
        button.enabled = control ? control.enabled : YES;
        XHSGlassHideOriginal(state, roleView);
    }
    if (state.composeButton && state.writeRoleView && !adaptiveTheme) {
        state.composeButton.enabled = state.writeControl ? state.writeControl.enabled : YES;
    }
}

NSString *XHSGlassSymbolForTopRole(XHSVideoTopRole role) {
    switch (role) {
        case XHSVideoTopRoleBack: return @"chevron.backward";
        case XHSVideoTopRoleSmallWindow: return @"pip.enter";
        case XHSVideoTopRoleSearch: return @"magnifyingglass";
        case XHSVideoTopRoleShare: return @"square.and.arrow.up";
        case XHSVideoTopRoleNoteFollow: return nil;
    }
}

NSString *XHSGlassLabelForTopRole(XHSVideoTopRole role) {
    switch (role) {
        case XHSVideoTopRoleBack: return @"返回";
        case XHSVideoTopRoleSmallWindow: return @"小窗";
        case XHSVideoTopRoleSearch: return @"搜索";
        case XHSVideoTopRoleShare: return @"分享";
        case XHSVideoTopRoleNoteFollow: return @"关注";
    }
}

UIButton *XHSGlassMakeTopButton(NSString *symbol, NSString *label, NSString *title, UIColor *foreground,
                                    BOOL isFirst, BOOL isLast, BOOL isFollow, void (^handler)(UIAction *)) {
    UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
    config.baseForegroundColor = foreground;
    CGFloat pointSize = [symbol isEqualToString:@"pip.enter"] ? 15.5 : 17.0;
    config.image = XHSGlassSymbol(symbol, pointSize, UIImageSymbolWeightMedium);
    config.title = title;
    config.titleLineBreakMode = NSLineBreakByClipping;
    config.imagePadding = symbol.length && title.length ? 5 : 0;
    if (isFollow) {
        config.contentInsets = NSDirectionalEdgeInsetsMake(0, (isFirst && !isLast) ? 6 : 0, 0, (isLast && !isFirst) ? 6 : 0);
    } else if (isFirst && isLast && !title.length) {
        config.contentInsets = NSDirectionalEdgeInsetsZero;
    } else {
        CGFloat innerPad = 6;
        CGFloat outerPad = 14;
        config.contentInsets = NSDirectionalEdgeInsetsMake(0, isFirst ? outerPad : innerPad, 0, isLast ? outerPad : innerPad);
    }
    config.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *incoming) {
        NSMutableDictionary *attrs = [incoming mutableCopy];
        attrs[NSFontAttributeName] = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightSemibold];
        return attrs;
    };
    UIButton *button = [UIButton buttonWithConfiguration:config primaryAction:[UIAction actionWithHandler:handler]];
    button.accessibilityLabel = label;
    button.titleLabel.lineBreakMode = NSLineBreakByClipping;
    button.titleLabel.numberOfLines = 1;
    if (isFollow) {
        CGFloat followW = (isFirst && isLast) ? 44 : 42;
        [button.widthAnchor constraintEqualToConstant:followW].active = YES;
    }
    [button setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [button setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    return button;
}


void XHSGlassUpdateTopButton(UIButton *button, NSString *symbol, NSString *title, UIColor *foreground,
                             BOOL isFirst, BOOL isLast, BOOL isFollow) {
    UIImage *targetImg = XHSGlassSymbol(symbol, [symbol isEqualToString:@"pip.enter"] ? 15.5 : 17.0, UIImageSymbolWeightMedium);
    if (![button.configuration.title ?: @"" isEqualToString:title ?: @""] ||
        ![button.configuration.baseForegroundColor isEqual:foreground] ||
        ![button.configuration.image isEqual:targetImg]) {
        UIButtonConfiguration *cfg = [button.configuration copy];
        cfg.image = targetImg;
        cfg.title = title;
        cfg.imagePadding = title.length ? 5 : 0;
        cfg.baseForegroundColor = foreground;
        if (isFollow) {
            cfg.contentInsets = NSDirectionalEdgeInsetsMake(0, (isFirst && !isLast) ? 6 : 0, 0, (isLast && !isFirst) ? 6 : 0);
        } else if (isFirst && isLast && !title.length) {
            cfg.contentInsets = NSDirectionalEdgeInsetsZero;
        } else {
            cfg.contentInsets = NSDirectionalEdgeInsetsMake(0, isFirst ? 14 : 6, 0, isLast ? 14 : 6);
        }
        button.configuration = cfg;
    }
}

@implementation XHSNativeHelper (GlassOverlay)

+ (UIView *)hitTestVideoOverlayIn:(UIView *)host point:(CGPoint)point withEvent:(UIEvent *)event {
    XHSNativeVideoState *state = XHSGlassExistingState(host);
    XHSNativeVideoOverlayView *overlay = state.overlayView;
    if (!overlay || overlay.hidden || overlay.alpha <= 0.01 || overlay.superview != host) return nil;
    CGPoint local = [overlay convertPoint:point fromView:host];
    return [overlay hitTest:local withEvent:event];
}

+ (BOOL)isVideoOverlayTouch:(UITouch *)touch inHost:(UIView *)host {
    XHSNativeVideoState *state = XHSGlassExistingState(host);
    XHSNativeVideoOverlayView *overlay = state.overlayView;
    if (!overlay || overlay.hidden || overlay.superview != host) return NO;
    return [touch.view isDescendantOfView:overlay];
}

+ (void)restoreOverlayHost:(UIView *)host {
    XHSNativeVideoState *state = XHSGlassExistingState(host);
    if (!state) return;
    state.retryCount = 0;
    state.overlayView.hidden = YES;
    NSString *clsName = NSStringFromClass(host.class);
    BOOL isNoteHost = [clsName hasPrefix:@"XYNoteModule."];
    BOOL enabled = [XHSNativeConfig.shared boolForKey:isNoteHost ? kXHSNativeGlassNote : kXHSNativeGlassVideo];
    if (!enabled) XHSGlassRestoreOriginals(state);
}

@end
