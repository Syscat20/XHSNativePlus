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

#pragma mark - 视频页

// 顶上和底下的操作栏使用同一套原生 iOS 26 液态玻璃控件，固定深色模式并跟随「视频顶栏 / 视频底栏」不透明度设置。

static void videoScheduleRetry(XHSNativeVideoState *state, BOOL isTop) {
    if (state.retryCount >= 6 || !state.host.window) return;
    state.retryCount += 1;
    NSTimeInterval delay = state.retryCount <= 2 ? 0.08 * state.retryCount : 0.2 * (state.retryCount - 1);
    UIView *host = state.host;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!host.window) return;
        if (isTop) [XHSNativeHelper layoutVideoHead:host];
        else [XHSNativeHelper layoutVideoEngage:host];
    });
}

static void videoTriggerTopRole(UIView *head, UIView *source, XHSVideoTopRole role) {
    switch (role) {
        case XHSVideoTopRoleBack:
            XHSGlassRelayAction(source, head, NSSelectorFromString(@"didTapBackButtonWithSender:"), YES);
            break;
        case XHSVideoTopRoleSmallWindow:
            XHSGlassRelayAction(source, head, NSSelectorFromString(@"didTapSmallWindowWithSender:"), YES);
            break;
        case XHSVideoTopRoleSearch:
            XHSGlassRelayAction(source, head, NSSelectorFromString(@"didTapRightButtonWithSender:"), YES);
            break;
        case XHSVideoTopRoleShare: {
            UIView *rightBtn = XHSGlassSafeProp(head, @"rightButton");
            if (source == rightBtn) {
                XHSGlassRelayAction(source, head, NSSelectorFromString(@"didTapRightButtonWithSender:"), YES);
            } else {
                XHSGlassRelayAction(source, head, NSSelectorFromString(@"didTapShareButton"), NO);
            }
            break;
        }
        default:
            break;
    }
}

static XHSNativeVideoGlassPill *videoBuildTopPill(XHSNativeVideoState *state,
                                                  NSArray<UIView *> *sources,
                                                  NSArray<NSNumber *> *roles,
                                                  NSArray<NSString *> *counts,
                                                  BOOL isLeft) {
    if (!sources.count) return nil;
    __weak XHSNativeVideoState *weakState = state;
    NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
    for (NSUInteger i = 0; i < sources.count; i++) {
        XHSVideoTopRole role = (XHSVideoTopRole)roles[i].integerValue;
        NSString *count = counts[i].length ? counts[i] : nil;
        UIButton *button = XHSGlassMakeTopButton(XHSGlassSymbolForTopRole(role), XHSGlassLabelForTopRole(role), count, UIColor.whiteColor,
                                              i == 0, i + 1 == sources.count, NO, ^(UIAction *action) {
            (void)action;
            XHSNativeVideoState *s = weakState;
            if (!s || !s.host) return;
            NSArray<UIView *> *srcs = isLeft ? s.topLeftSources : s.topRightSources;
            NSArray<NSNumber *> *rls = isLeft ? s.topLeftRoles : s.topRightRoles;
            if (i < srcs.count && i < rls.count) {
                videoTriggerTopRole(s.host, srcs[i], (XHSVideoTopRole)rls[i].integerValue);
            }
        });
        [buttons addObject:button];
    }
    if (isLeft) state.topLeftButtons = buttons;
    else state.topRightButtons = buttons;
    return XHSGlassMakePill(buttons, kXHSNativeBarVideoTop, 0, NO);
}

static void videoBuildBottom(XHSNativeVideoState *state, XHSNativeVideoOverlayView *overlay, NSArray<NSNumber *> *roles) {
    __weak XHSNativeVideoState *weakState = state;
    NSArray<NSString *> *allSymbols = @[@"heart", @"star", @"bubble"];
    NSArray<NSString *> *allLabels = @[@"点赞", @"收藏", @"评论"];
    NSArray<NSString *> *allActions = @[@"likeClicked", @"collectAction", @"commentAction"];

    [state.engagePill removeFromSuperview];
    [state.composePill removeFromSuperview];

    NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
    for (NSUInteger i = 0; i < roles.count; i++) {
        XHSGlassItemRole role = (XHSGlassItemRole)roles[i].integerValue;
        SEL directSel = NSSelectorFromString(allActions[(NSUInteger)role]);
        UIButton *button = XHSGlassMakeActionButton(allSymbols[(NSUInteger)role], allLabels[(NSUInteger)role], UIColor.whiteColor, ^(UIAction *action) {
            (void)action;
            XHSNativeVideoState *s = weakState;
            if (!s || i >= s.engageRoleViews.count) return;
            UIView *roleView = s.engageRoleViews[i];
            UIControl *control = i < s.engageControls.count ? s.engageControls[i] : nil;
            BOOL isToggle = (role == XHSGlassItemRoleLike || role == XHSGlassItemRoleCollect);
            BOOL beforeSelected = isToggle && control.selected;
            XHSGlassRelayAction(control ?: roleView, roleView, directSel, NO);
            XHSGlassRefreshBottom(s, NO);
            dispatch_async(dispatch_get_main_queue(), ^{
                XHSGlassRefreshBottom(s, NO);
                if (isToggle && i < s.engageButtons.count && control && control.selected != beforeSelected && control.selected) {
                    XHSGlassBounceSymbol(s.engageButtons[i]);
                }
                [s.host setNeedsLayout];
            });
        });
        [buttons addObject:button];
    }
    state.engageRoles = roles;
    state.engageButtons = buttons;
    state.engagePill = XHSGlassMakePill(buttons, kXHSNativeBarVideoBottom, 0, NO);
    [overlay.contentView addSubview:state.engagePill];

    UIButton *compose = XHSGlassMakeActionButton(@"square.and.pencil", @"写评论", UIColor.whiteColor, ^(UIAction *action) {
        (void)action;
        XHSNativeVideoState *s = weakState;
        if (!s || !s.writeRoleView) return;
        XHSGlassRelayAction(s.writeControl ?: s.writeRoleView, s.writeRoleView, NSSelectorFromString(@"writeCmtAction"), NO);
    });
    UIButtonConfiguration *composeCfg = [compose.configuration copy];
    composeCfg.image = XHSGlassSymbol(@"square.and.pencil", 18, UIImageSymbolWeightMedium);
    composeCfg.contentInsets = NSDirectionalEdgeInsetsZero;
    compose.configuration = composeCfg;
    state.composeButton = compose;
    state.composePill = XHSGlassMakePill(@[compose], kXHSNativeBarVideoBottom, 0, NO);
    [overlay.contentView addSubview:state.composePill];
}

@implementation XHSNativeHelper (VideoGlass)

+ (void)layoutVideoHead:(UIView *)head {
    XHSNativeVideoState *state = XHSGlassStateForHost(head);

    BOOL enabled = [XHSNativeConfig.shared boolForKey:kXHSNativeGlassVideo];
    if (!enabled) {
        XHSGlassRestoreOriginals(state);
        state.retryCount = 0;
        state.overlayView.hidden = YES;
        return;
    }

    UIView *back = XHSGlassSafeProp(head, @"backButton");
    UIView *smallWin = XHSGlassSafeProp(head, @"smallWindowButton");
    UIView *rightBtn = XHSGlassSafeProp(head, @"rightButton");
    UIView *shareBtn = XHSGlassSafeProp(head, @"shareButton");
    UIView *searchView = XHSGlassSafeProp(head, @"searchView");
    UILabel *shareCountLabel = XHSGlassSafeProp(head, @"shareCountLabel");

    // 只要开启视频玻璃，即使离屏/淡入淡出中也不恢复原控件透明度，防止轻微滑动时闪烁
    if (back) XHSGlassHideOriginal(state, back);
    if (smallWin) XHSGlassHideOriginal(state, smallWin);
    if (rightBtn) XHSGlassHideOriginal(state, rightBtn);
    if (shareBtn) XHSGlassHideOriginal(state, shareBtn);
    if (shareCountLabel) XHSGlassHideOriginal(state, shareCountLabel);

    if (!head.window || head.hidden || head.alpha <= 0.01) {
        state.retryCount = 0;
        state.overlayView.hidden = YES;
        return;
    }
    if (CGRectGetWidth(head.bounds) < 120) {
        state.overlayView.hidden = YES;
        videoScheduleRetry(state, YES);
        return;
    }

    NSMutableArray<UIView *> *leftSources = [NSMutableArray array];
    NSMutableArray<NSNumber *> *leftRoles = [NSMutableArray array];
    NSMutableArray<NSString *> *leftCounts = [NSMutableArray array];

    NSMutableArray<UIView *> *rightSources = [NSMutableArray array];
    NSMutableArray<NSNumber *> *rightRoles = [NSMutableArray array];
    NSMutableArray<NSString *> *rightCounts = [NSMutableArray array];

    if (XHSGlassIsItemActive(back)) {
        [leftSources addObject:back];
        [leftRoles addObject:@(XHSVideoTopRoleBack)];
        [leftCounts addObject:@""];
    }
    if (XHSGlassIsItemActive(smallWin)) {
        [leftSources addObject:smallWin];
        [leftRoles addObject:@(XHSVideoTopRoleSmallWindow)];
        [leftCounts addObject:@""];
    }

    BOOL hasTouristSearch = XHSGlassIsItemActive(searchView);
    NSString *shareCount = (XHSGlassIsItemActive(shareCountLabel) ? XHSGlassCountText(shareCountLabel.text) : nil) ?: @"";
    if (!hasTouristSearch && XHSGlassIsItemActive(rightBtn)) {
        BOOL isSearch = [rightBtn respondsToSelector:@selector(isSearchType)]
            ? ((BOOL (*)(id, SEL))objc_msgSend)(rightBtn, @selector(isSearchType))
            : XHSGlassIsItemActive(shareBtn);
        [rightSources addObject:rightBtn];
        [rightRoles addObject:@(isSearch ? XHSVideoTopRoleSearch : XHSVideoTopRoleShare)];
        [rightCounts addObject:isSearch ? @"" : shareCount];
    }
    if (XHSGlassIsItemActive(shareBtn)) {
        [rightSources addObject:shareBtn];
        [rightRoles addObject:@(XHSVideoTopRoleShare)];
        [rightCounts addObject:shareCount];
    }

    // 兜底：若属性未暴露，按几何位置识别左右两侧可见按钮
    if (!leftSources.count && !rightSources.count) {
        CGFloat midX = CGRectGetMidX(head.bounds);
        NSMutableArray<UIControl *> *found = [NSMutableArray array];
        for (UIView *child in head.subviews) {
            if ([child isKindOfClass:XHSNativeVideoOverlayView.class]) continue;
            if ([child isKindOfClass:UIControl.class] && XHSGlassIsItemActive(child) && CGRectGetWidth(child.frame) <= 90) {
                [found addObject:(UIControl *)child];
            }
        }
        [found sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
            return [@(CGRectGetMidX(a.frame)) compare:@(CGRectGetMidX(b.frame))];
        }];
        for (UIControl *ctrl in found) {
            CGRect r = [head convertRect:ctrl.bounds fromView:ctrl];
            if (CGRectGetMidX(r) < midX) {
                [leftSources addObject:ctrl];
                [leftRoles addObject:@(leftSources.count == 1 ? XHSVideoTopRoleBack : XHSVideoTopRoleSmallWindow)];
                [leftCounts addObject:@""];
            } else {
                [rightSources addObject:ctrl];
                [rightRoles addObject:@(XHSVideoTopRoleShare)];
                [rightCounts addObject:@""];
            }
        }
        if (rightRoles.count == 2) rightRoles[0] = @(XHSVideoTopRoleSearch);
    }

    if (!leftSources.count && !rightSources.count) {
        state.overlayView.hidden = YES;
        videoScheduleRetry(state, YES);
        return;
    }

    state.retryCount = 0;
    XHSNativeVideoOverlayView *overlay = XHSGlassEnsureOverlay(state, 8.0, NO);
    overlay.hidden = NO;
    overlay.alpha = 1;

    BOOL leftChanged = ![state.topLeftRoles isEqualToArray:leftRoles] || ![state.topLeftSources isEqualToArray:leftSources];
    BOOL rightChanged = ![state.topRightRoles isEqualToArray:rightRoles] || ![state.topRightSources isEqualToArray:rightSources];
    state.topLeftSources = leftSources;
    state.topLeftRoles = leftRoles;
    state.topRightSources = rightSources;
    state.topRightRoles = rightRoles;

    if (leftChanged) {
        [state.topLeftPill removeFromSuperview];
        state.topLeftPill = videoBuildTopPill(state, leftSources, leftRoles, leftCounts, YES);
        if (state.topLeftPill) [overlay.contentView addSubview:state.topLeftPill];
    }
    if (rightChanged) {
        [state.topRightPill removeFromSuperview];
        state.topRightPill = videoBuildTopPill(state, rightSources, rightRoles, rightCounts, NO);
        if (state.topRightPill) [overlay.contentView addSubview:state.topRightPill];
    }

    CGFloat leftMidYSum = 0, rightMidYSum = 0;
    for (NSUInteger i = 0; i < leftSources.count; i++) {
        UIView *src = leftSources[i];
        CGRect f = [head convertRect:src.bounds fromView:src];
        leftMidYSum += CGRectGetMidY(f);
        if (i < state.topLeftButtons.count && [src isKindOfClass:UIControl.class]) {
            state.topLeftButtons[i].enabled = ((UIControl *)src).enabled;
        }
        XHSGlassHideOriginal(state, src);
    }
    for (NSUInteger i = 0; i < rightSources.count; i++) {
        UIView *src = rightSources[i];
        CGRect f = [head convertRect:src.bounds fromView:src];
        rightMidYSum += CGRectGetMidY(f);
        if (i < state.topRightButtons.count) {
            UIButton *btn = state.topRightButtons[i];
            if ([src isKindOfClass:UIControl.class]) btn.enabled = ((UIControl *)src).enabled;
            NSString *cnt = rightCounts[i].length ? rightCounts[i] : nil;
            XHSVideoTopRole role = (XHSVideoTopRole)rightRoles[i].integerValue;
            XHSGlassUpdateTopButton(btn, XHSGlassSymbolForTopRole(role), cnt, UIColor.whiteColor, i == 0, i + 1 == rightSources.count, NO);
        }
        XHSGlassHideOriginal(state, src);
    }
    if (([rightRoles containsObject:@(XHSVideoTopRoleShare)]) && XHSGlassIsItemActive(shareCountLabel)) {
        XHSGlassHideOriginal(state, shareCountLabel);
    }

    CGFloat height = 44;
    CGFloat edge = 16;
    CGFloat fallbackY = MAX(0, CGRectGetMidY(head.bounds) - height / 2);
    CGFloat leftY = leftSources.count ? (leftMidYSum / leftSources.count - height / 2) : fallbackY;
    CGFloat rightY = rightSources.count ? (rightMidYSum / rightSources.count - height / 2) : leftY;
    leftY = MIN(MAX(leftY, 0), MAX(0, CGRectGetHeight(head.bounds) - height));
    rightY = MIN(MAX(rightY, 0), MAX(0, CGRectGetHeight(head.bounds) - height));

    NSMutableArray<UIView *> *pills = [NSMutableArray array];
    if (state.topLeftPill) {
        XHSGlassApplyPillFill(state.topLeftPill);
        state.topLeftPill.hidden = NO;
        state.topLeftPill.alpha = 1;
        CGFloat fitW = ceil([state.topLeftPill.contentView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].width);
        CGFloat w = leftSources.count == 1 ? MAX(height, fitW) : MAX(88, fitW);
        state.topLeftPill.frame = CGRectMake(edge, leftY, w, height);
        state.topLeftPill.contentView.layer.cornerRadius = height / 2;
        [pills addObject:state.topLeftPill];
    }
    if (state.topRightPill) {
        XHSGlassApplyPillFill(state.topRightPill);
        state.topRightPill.hidden = NO;
        state.topRightPill.alpha = 1;
        CGFloat fitW = ceil([state.topRightPill.contentView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].width);
        CGFloat w = rightSources.count == 1 ? MAX(height, fitW) : MAX(88, fitW);
        state.topRightPill.frame = CGRectMake(CGRectGetWidth(head.bounds) - edge - w, rightY, w, height);
        state.topRightPill.contentView.layer.cornerRadius = height / 2;
        [pills addObject:state.topRightPill];
    }
    overlay.interactivePills = pills;
    if (!CGRectEqualToRect(overlay.frame, head.bounds)) overlay.frame = head.bounds;
    [head bringSubviewToFront:overlay];
}

+ (void)layoutVideoEngage:(UIView *)bar {
    XHSNativeVideoState *state = XHSGlassStateForHost(bar);

    BOOL enabled = [XHSNativeConfig.shared boolForKey:kXHSNativeGlassVideo];
    if (!enabled) {
        XHSGlassRestoreOriginals(state);
        state.retryCount = 0;
        state.overlayView.hidden = YES;
        return;
    }

    NSArray<NSString *> *roleNames = @[@"VFBottomLikeView", @"VFBottomCollectView", @"VFBottomCommentView"];
    NSMutableArray<UIView *> *allRoleViews = [NSMutableArray array];
    for (NSString *name in roleNames) {
        UIView *v = XHSGlassControlWithSuffix(bar, name);
        if (v) {
            [allRoleViews addObject:v];
            XHSGlassHideOriginal(state, v);
        }
    }
    UIView *writeView = XHSGlassControlWithSuffix(bar, @"VFBottomWriteCmtView");
    BOOL disableCompose = [NSUserDefaults.standardUserDefaults boolForKey:kXHSNativeVideoDisableCompose];
    if (writeView) {
        if (disableCompose) XHSGlassDisableOriginal(state, writeView);
        else XHSGlassHideOriginal(state, writeView);
    }

    if (!bar.window || bar.hidden || bar.alpha <= 0.01) {
        state.retryCount = 0;
        state.overlayView.hidden = YES;
        return;
    }
    if (CGRectGetWidth(bar.bounds) < 160) {
        state.overlayView.hidden = YES;
        videoScheduleRetry(state, NO);
        return;
    }

    NSMutableArray<UIView *> *roleViews = [NSMutableArray array];
    NSMutableArray<UIControl *> *controls = [NSMutableArray array];
    NSMutableArray<NSNumber *> *roles = [NSMutableArray array];
    for (NSUInteger idx = 0; idx < roleNames.count; idx++) {
        UIView *view = XHSGlassControlWithSuffix(bar, roleNames[idx]);
        if (!XHSGlassIsItemActive(view)) continue;
        UIControl *control = XHSGlassSafeProp(view, @"bottomEngageControl") ?: XHSGlassControlIn(view);
        if (!control) continue;
        [roleViews addObject:view];
        [controls addObject:control];
        [roles addObject:@(idx)];
    }

    UIControl *writeControl = nil;
    if (XHSGlassIsItemActive(writeView)) {
        writeControl = XHSGlassSafeProp(writeView, @"bottomEngageControl") ?: XHSGlassControlIn(writeView);
        if (disableCompose) XHSGlassDisableOriginal(state, writeControl);
    }

    if (!roleViews.count) {
        state.overlayView.hidden = YES;
        videoScheduleRetry(state, NO);
        return;
    }
    if (roleViews.count < 3) videoScheduleRetry(state, NO);
    else state.retryCount = 0;

    state.engageRoleViews = roleViews;
    state.engageControls = controls;
    state.writeRoleView = writeView;
    state.writeControl = writeControl;

    XHSNativeVideoOverlayView *overlay = XHSGlassEnsureOverlay(state, 10.0, NO);
    overlay.hidden = NO;
    overlay.alpha = 1;
    if (!state.engagePill || ![state.engageRoles isEqualToArray:roles]) {
        videoBuildBottom(state, overlay, roles);
    }
    if (state.engagePill.superview != overlay.contentView) [overlay.contentView addSubview:state.engagePill];
    if (state.composePill.superview != overlay.contentView) [overlay.contentView addSubview:state.composePill];

    BOOL hasCompose = !disableCompose && XHSGlassIsItemActive(writeView) && writeControl != nil;

    CGFloat edge = 18;
    CGFloat height = 48;
    CGFloat gap = 10;
    CGFloat width = CGRectGetWidth(bar.bounds);
    CGFloat available = width - edge * 2 - (hasCompose ? (height + gap) : 0);

    state.compactEngage = NO;
    XHSGlassRefreshBottom(state, NO);
    CGFloat fit = ceil([state.engagePill.contentView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].width);
    if (fit > available) {
        state.compactEngage = YES;
        XHSGlassRefreshBottom(state, NO);
        fit = ceil([state.engagePill.contentView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].width);
    }
    if (fit <= 0 || available < 80) {
        overlay.hidden = YES;
        videoScheduleRetry(state, NO);
        return;
    }
    CGFloat minW = roleViews.count == 1 ? height : (roleViews.count == 2 ? 100 : 148);
    CGFloat capsuleWidth = MIN(MAX(fit, minW), available);

    CGRect row = CGRectNull;
    for (UIView *view in roleViews) row = CGRectUnion(row, [bar convertRect:view.bounds fromView:view]);
    if (hasCompose) row = CGRectUnion(row, [bar convertRect:writeView.bounds fromView:writeView]);
    CGFloat y = CGRectIsNull(row) ? CGRectGetMaxY(bar.bounds) - height : CGRectGetMaxY(row) + 5 - height;
    y = MIN(MAX(y, 0), MAX(0, CGRectGetHeight(bar.bounds) - height));

    for (UIView *view in roleViews) XHSGlassHideOriginal(state, view);
    if (disableCompose) {
        XHSGlassDisableOriginal(state, writeView);
        XHSGlassDisableOriginal(state, writeControl);
    } else if (XHSGlassIsItemActive(writeView)) {
        XHSGlassHideOriginal(state, writeView);
    }

    XHSGlassApplyPillFill(state.engagePill);
    state.engagePill.hidden = NO;
    state.engagePill.alpha = 1;
    state.engagePill.frame = CGRectMake(width - edge - capsuleWidth, y, capsuleWidth, height);
    state.engagePill.contentView.layer.cornerRadius = height / 2;

    NSMutableArray<UIView *> *pills = [NSMutableArray arrayWithObject:state.engagePill];
    state.composePill.hidden = !hasCompose;
    if (hasCompose) {
        XHSGlassApplyPillFill(state.composePill);
        state.composePill.alpha = 1;
        state.composePill.frame = CGRectMake(edge, y, height, height);
        state.composePill.contentView.layer.cornerRadius = height / 2;
        [pills addObject:state.composePill];
    }
    overlay.interactivePills = pills;
    if (!CGRectEqualToRect(overlay.frame, bar.bounds)) overlay.frame = bar.bounds;
    [bar bringSubviewToFront:overlay];
}

+ (void)refreshVideoEngageFromItem:(UIView *)item {
    for (UIView *view = item.superview; view; view = view.superview) {
        if (![NSStringFromClass(view.class) hasSuffix:@"VFBottomEngageView"]) continue;
        XHSNativeVideoState *state = XHSGlassExistingState(view);
        if (state) state.retryCount = 0;
        [self layoutVideoEngage:view];
        [view setNeedsLayout];
        break;
    }
}

+ (void)refreshVideoLikeFromItem:(UIView *)item selected:(BOOL)selected animated:(BOOL)animated {
    for (UIView *view = item.superview; view; view = view.superview) {
        if (![NSStringFromClass(view.class) hasSuffix:@"VFBottomEngageView"]) continue;
        XHSNativeVideoState *state = XHSGlassExistingState(view);
        BOOL wasLiked = state ? state.lastLiked : NO;
        if (state) {
            state.retryCount = 0;
            state.hasLikeOverride = YES;
            state.likeSelectedOverride = selected;
        }
        [self layoutVideoEngage:view];
        if (state) state.hasLikeOverride = NO;
        if (selected && (!wasLiked || animated) && state.engageButtons.count && state.engageRoles.count && state.engageRoles[0].integerValue == XHSGlassItemRoleLike) {
            XHSGlassBounceSymbol(state.engageButtons[0]);
        }
        break;
    }
}

+ (void)triggerVideoLikeBounceFromItem:(UIView *)item {
    for (UIView *view = item.superview; view; view = view.superview) {
        if (![NSStringFromClass(view.class) hasSuffix:@"VFBottomEngageView"]) continue;
        XHSNativeVideoState *state = XHSGlassExistingState(view);
        if (state) {
            state.hasLikeOverride = YES;
            state.likeSelectedOverride = YES;
            [self layoutVideoEngage:view];
            state.hasLikeOverride = NO;
            if (state.engageButtons.count && state.engageRoles.count && state.engageRoles[0].integerValue == XHSGlassItemRoleLike) {
                XHSGlassBounceSymbol(state.engageButtons[0]);
            }
        }
        break;
    }
}

+ (void)refreshVideoEngageFromItemIfNeeded:(UIView *)item {
    for (UIView *view = item.superview; view; view = view.superview) {
        if (![NSStringFromClass(view.class) hasSuffix:@"VFBottomEngageView"]) continue;
        XHSNativeVideoState *state = XHSGlassExistingState(view);
        if (!state || !state.overlayView || state.overlayView.hidden) {
            if (state) state.retryCount = 0;
            [self layoutVideoEngage:view];
        }
        break;
    }
}

+ (void)resetVideoItem:(UIView *)item {
    XHSGlassClearOurHide(item);
    [self refreshVideoEngageFromItem:item];
}

@end
