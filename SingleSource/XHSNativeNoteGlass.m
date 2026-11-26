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

#pragma mark - 图文笔记页

// 系统的 soft 边缘只画在滚动视图自己的范围里，笔记列表从顶栏下沿才开始，画不到顶栏下面。
// 在顶栏的位置放一个空的滚动视图替它画：列表停在顶上时，它的内容在栏的下方，系统不显示边缘；
// 列表一往下滑，就把它的内容挪到栏下面，系统显示边缘
@interface XHSNativeSoftEdge : UIScrollView
- (void)follow:(UIScrollView *)list;
@end

@implementation XHSNativeSoftEdge

- (void)follow:(UIScrollView *)list {
    BOOL scrolled = list.contentOffset.y > 0.5 - list.adjustedContentInset.top;
    CGFloat offset = scrolled ? 0 : -self.contentInset.top;
    if (self.contentOffset.y != offset) self.contentOffset = CGPointMake(0, offset);
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(UIScrollView *)list change:(NSDictionary *)change context:(void *)context {
    [self follow:list];
}

@end

#pragma mark - 双击放大

// 笔记页图片的双指放大由 PinchController 处理：开始时把图片截下来放到全屏的遮罩上，
// 跟着手指缩放和移动，松手弹回。双击时喂给它一个假的双指手势，效果和双指放大一样；
// 放大后盖一层透明的视图接手势：单指拖动、双指继续缩放，点一下松开，用它自己的弹回动画收起

@interface XHSNativeFakePinch : UIPinchGestureRecognizer
@property (nonatomic) UIGestureRecognizerState fakeState;
@property (nonatomic) CGFloat fakeScale;
@property (nonatomic) CGPoint fakePoint;  // 窗口坐标
@property (nonatomic, weak) UIView *hostView;
@end

@implementation XHSNativeFakePinch

- (UIGestureRecognizerState)state {
    return self.fakeState;
}

- (CGFloat)scale {
    return self.fakeScale;
}

- (NSUInteger)numberOfTouches {
    return 2;
}

- (UIView *)view {
    return self.hostView;
}

- (CGPoint)locationInView:(UIView *)view {
    return view ? [view convertPoint:self.fakePoint fromView:nil] : self.fakePoint;
}

@end

@interface XHSNativePinchHold : NSObject
@property (nonatomic, strong) id controller;
@property (nonatomic, strong) XHSNativeFakePinch *pinch;
@property (nonatomic, strong) UIView *catcher;
@property (nonatomic) CGPoint start;
@property (nonatomic) CGFloat baseScale;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic) CFTimeInterval beginTime;
@end

static XHSNativePinchHold *gPinchHold;
static const CGFloat kZoomScale = 2.5;

@implementation XHSNativePinchHold

- (void)send:(UIGestureRecognizerState)state {
    self.pinch.fakeState = state;
    [self.controller didReceivePinchWithRecognizer:self.pinch];
}

- (CGFloat)clampScale:(CGFloat)scale {
    CGFloat limit = [self.controller maxScale] > 1 ? [self.controller maxScale] : kZoomScale;
    return MAX(1, MIN(limit, scale));
}

// 从 1 倍放大到 2.5 倍，和手指张开一样逐帧喂
- (void)grow:(CADisplayLink *)link {
    if (!self.beginTime) self.beginTime = link.timestamp;
    CGFloat progress = MIN(1, (link.timestamp - self.beginTime) / 0.25);
    CGFloat eased = 1 - pow(1 - progress, 3);
    self.pinch.fakeScale = [self clampScale:1 + (kZoomScale - 1) * eased];
    [self send:UIGestureRecognizerStateChanged];
    if (progress < 1) return;
    [link invalidate];
    self.link = nil;
}

- (void)pan:(UIPanGestureRecognizer *)pan {
    if (pan.state == UIGestureRecognizerStateBegan) self.start = self.pinch.fakePoint;
    CGPoint move = [pan translationInView:nil];
    self.pinch.fakePoint = CGPointMake(self.start.x + move.x, self.start.y + move.y);
    [self send:UIGestureRecognizerStateChanged];
}

- (void)zoom:(UIPinchGestureRecognizer *)zoom {
    if (zoom.state == UIGestureRecognizerStateBegan) self.baseScale = self.pinch.fakeScale;
    self.pinch.fakeScale = [self clampScale:self.baseScale * zoom.scale];
    [self send:UIGestureRecognizerStateChanged];
}

- (void)finish {
    [self.link invalidate];
    self.link = nil;
    [self.catcher removeFromSuperview];
    [self send:UIGestureRecognizerStateEnded];
    gPinchHold = nil;
}

@end

#pragma mark - 图文笔记页

// 正文延伸到上下两条栏的后面，栏的底色去掉，顶部与底部操作栏升级为与视频页一致的 iOS 26 原生交互式液态玻璃控件
// （UIGlassContainerEffect + 交互式 UIGlassEffect 胶囊 + 原生 SF Symbols，并自适应浅色/深色模式）。

static char kNoteLeftKey, kNoteRightKey, kNoteBottomKey, kNoteBottomRightKey, kNoteEdgeKey;

static void removeNoteBottomPlate(UIView *bar, const void *key) {
    UIView *glass = objc_getAssociatedObject(bar, key);
    if (!glass) return;
    [glass removeFromSuperview];
    objc_setAssociatedObject(bar, key, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void clearNoteBottomPlates(UIView *bar) {
    if (!bar) return;
    removeNoteBottomPlate(bar, &kNoteBottomKey);
    removeNoteBottomPlate(bar, &kNoteBottomRightKey);
    XHSNativeVideoState *state = XHSGlassExistingState(bar);
    if (state) {
        XHSGlassRestoreOriginals(state);
        state.overlayView.hidden = YES;
    }
}

static BOOL noteBottomIsVisible(UIView *bar) {
    UIWindow *window = bar.window;
    if (!window) return NO;
    for (UIView *view = bar; view; view = view.superview) {
        if (view.hidden || view.alpha <= 0) return NO;
        if (view == window)
            return CGRectIntersectsRect([bar convertRect:bar.bounds toView:window], window.bounds);
    }
    return NO;
}

static char kPageNoteBottomKey, kNavigationNoteBottomKey;

static void updatePageNoteBottom(UIViewController *page, UIView *bottom) {
    XHSNativeNoteBottomReference *reference = objc_getAssociatedObject(page, &kPageNoteBottomKey);
    UIView *previous = reference.bar;
    if (previous != bottom) clearNoteBottomPlates(previous);

    // 每个栏自己持有玻璃。导航栈切页时清理上一页，避免共用玻璃造成重叠。
    UINavigationController *navigation = page.navigationController;
    if (navigation && navigation.topViewController == page) {
        XHSNativeNoteBottomReference *active = objc_getAssociatedObject(navigation, &kNavigationNoteBottomKey);
        if (!active) {
            active = [XHSNativeNoteBottomReference new];
            objc_setAssociatedObject(navigation, &kNavigationNoteBottomKey, active, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (active.bar != bottom) clearNoteBottomPlates(active.bar);
        active.bar = bottom;
    }
    if (previous == bottom) return;
    if (!reference) {
        reference = [XHSNativeNoteBottomReference new];
        objc_setAssociatedObject(page, &kPageNoteBottomKey, reference, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    reference.bar = bottom;
}

static NSString *noteButtonTitle(UIView *view) {
    if ([view isKindOfClass:UIButton.class]) {
        UIButton *btn = (UIButton *)view;
        NSString *t = [btn.currentTitle ?: btn.titleLabel.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (t.length) return t;
    }
    for (UIView *child in view.subviews) {
        if ([child isKindOfClass:UILabel.class]) {
            NSString *t = [((UILabel *)child).text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (t.length) return t;
        }
    }
    return nil;
}

static UIImageView *noteFindAvatarImageView(UIView *avatarView) {
    if (!avatarView) return nil;
    UIImageView *iv = XHSGlassSafeProp(avatarView, @"userAvatarImageView");
    if ([iv isKindOfClass:UIImageView.class]) return iv;
    UIImageView *best = nil;
    CGFloat bestArea = 0;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:avatarView];
    while (queue.count) {
        UIView *cur = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([cur isKindOfClass:UIImageView.class]) {
            UIImageView *cand = (UIImageView *)cur;
            CGFloat area = CGRectGetWidth(cand.bounds) * CGRectGetHeight(cand.bounds);
            if ((cand.image && !best.image) || area >= bestArea) {
                best = cand;
                bestArea = area;
            }
        }
        [queue addObjectsFromArray:cur.subviews];
    }
    return best;
}

static NSString *noteAuthorNameText(UIView *author, UIView *nameView) {
    NSString *text = XHSGlassSafeProp(author, @"title");
    if ([text isKindOfClass:NSString.class] && [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) {
        return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
    id nameLabel = XHSGlassSafeProp(nameView, @"nameLabel");
    if ([nameLabel isKindOfClass:UILabel.class]) {
        NSString *t = [((UILabel *)nameLabel).text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (t.length) return t;
    }
    NSString *viewText = XHSGlassSafeProp(nameView, @"text");
    if ([viewText isKindOfClass:NSString.class] && viewText.length) return viewText;
    NSString *best = nil;
    NSMutableArray<UIView *> *queue = nameView ? [NSMutableArray arrayWithObject:nameView] : [NSMutableArray array];
    while (queue.count) {
        UIView *cur = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([cur isKindOfClass:UILabel.class] && !cur.hidden) {
            NSString *t = [((UILabel *)cur).text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (t.length > best.length) best = t;
        }
        [queue addObjectsFromArray:cur.subviews];
    }
    return best;
}

static BOOL noteFollowIsSelected(UIView *author, UIView *followView) {
    if ([followView isKindOfClass:UIControl.class] && ((UIControl *)followView).selected) return YES;
    SEL isFollowedSel = NSSelectorFromString(@"isFollowed");
    if (author && [author respondsToSelector:isFollowedSel]) {
        if (((BOOL (*)(id, SEL))objc_msgSend)(author, isFollowedSel)) return YES;
    }
    NSString *title = noteButtonTitle(followView);
    if (title.length && ([title containsString:@"已关注"] || [title containsString:@"互相关注"] || [title containsString:@"互关"])) return YES;
    return NO;
}

static void noteTriggerTopRole(XHSNativeVideoState *state, UIView *source, XHSVideoTopRole role) {
    UIView *direction = state.noteDirectionHost;
    switch (role) {
        case XHSVideoTopRoleBack:
            XHSGlassRelayAction(source, direction, NSSelectorFromString(@"handleBackAction"), NO);
            break;
        case XHSVideoTopRoleNoteFollow:
            XHSGlassRelayAction(source, direction, NSSelectorFromString(@"handleFollowIntention"), NO);
            break;
        case XHSVideoTopRoleShare:
            XHSGlassRelayAction(source, direction, NSSelectorFromString(@"handleMoreIntention"), NO);
            break;
        default:
            break;
    }
}

static XHSNativeVideoGlassPill *noteBuildTopPill(XHSNativeVideoState *state,
                                                  NSArray<UIView *> *sources,
                                                  NSArray<NSNumber *> *roles,
                                                  NSArray<NSString *> *titles,
                                                  BOOL isLeft) {
    if (!sources.count) return nil;
    __weak XHSNativeVideoState *weakState = state;
    UIColor *followRed = [UIColor colorWithRed:1.0 green:0.18 blue:0.33 alpha:1.0];
    NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
    for (NSUInteger i = 0; i < sources.count; i++) {
        XHSVideoTopRole role = (XHSVideoTopRole)roles[i].integerValue;
        BOOL isFollow = (role == XHSVideoTopRoleNoteFollow);
        UIView *src = sources[i];
        BOOL followSelected = isFollow && noteFollowIsSelected(state.noteDirectionHost, src);
        NSString *symbol = isFollow ? (followSelected ? @"person.fill.checkmark" : @"person.badge.plus") : XHSGlassSymbolForTopRole(role);
        UIColor *fg = isFollow ? (followSelected ? UIColor.secondaryLabelColor : followRed) : UIColor.labelColor;
        NSString *title = (!isFollow && titles[i].length) ? titles[i] : nil;
        UIButton *button = XHSGlassMakeTopButton(symbol, XHSGlassLabelForTopRole(role), title, fg,
                                              i == 0, i + 1 == sources.count, isFollow, ^(UIAction *action) {
            (void)action;
            XHSNativeVideoState *s = weakState;
            if (!s) return;
            NSArray<UIView *> *srcs = isLeft ? s.topLeftSources : s.topRightSources;
            NSArray<NSNumber *> *rls = isLeft ? s.topLeftRoles : s.topRightRoles;
            if (i < srcs.count && i < rls.count) {
                noteTriggerTopRole(s, srcs[i], (XHSVideoTopRole)rls[i].integerValue);
                if (isFollow && !isLeft && i < s.topRightButtons.count) {
                    XHSGlassBounceSymbol(s.topRightButtons[i]);
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        if (s.host.window) [XHSNativeHelper layoutNoteTop:s.host];
                    });
                }
            }
        });
        [buttons addObject:button];
    }
    if (isLeft) state.topLeftButtons = buttons;
    else state.topRightButtons = buttons;
    return XHSGlassMakePill(buttons, kXHSNativeBarNoteTop, 0, YES);
}

static void noteEnsureProfilePill(XHSNativeVideoState *state, XHSNativeVideoOverlayView *overlay) {
    if (state.namePill) return;
    __weak XHSNativeVideoState *weakState = state;
    UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
    config.baseForegroundColor = UIColor.labelColor;
    config.titleLineBreakMode = NSLineBreakByTruncatingTail;
    config.contentInsets = NSDirectionalEdgeInsetsMake(0, 48, 0, 14);
    config.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *incoming) {
        NSMutableDictionary *attrs = [incoming mutableCopy];
        attrs[NSFontAttributeName] = [UIFont systemFontOfSize:14.5 weight:UIFontWeightSemibold];
        return attrs;
    };
    UIButton *btn = [UIButton buttonWithConfiguration:config primaryAction:[UIAction actionWithHandler:^(UIAction *action) {
        (void)action;
        XHSNativeVideoState *s = weakState;
        if (!s) return;
        UIControl *avatarCtrl = XHSGlassSafeProp(s.avatarSourceView, @"userAvatarButton");
        if (avatarCtrl || s.avatarSourceView) {
            XHSGlassRelayAction(avatarCtrl ?: s.avatarSourceView, s.noteDirectionHost, NSSelectorFromString(@"handleAvatarIntention"), NO);
        } else {
            XHSGlassRelayAction(s.nameSourceView, s.noteDirectionHost, NSSelectorFromString(@"handleTitleIntention"), NO);
        }
    }]];
    btn.accessibilityLabel = @"作者主页";
    btn.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    btn.titleLabel.numberOfLines = 1;
    btn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    [btn setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    UIImageView *fallback = [[UIImageView alloc] initWithImage:XHSGlassSymbol(@"person.crop.circle.fill", 22, UIImageSymbolWeightRegular)];
    fallback.tintColor = UIColor.tertiaryLabelColor;
    fallback.contentMode = UIViewContentModeCenter;
    fallback.userInteractionEnabled = NO;
    fallback.frame = CGRectMake(4, 4, 36, 36);

    UIImageView *avatarImg = [[UIImageView alloc] initWithFrame:CGRectMake(4, 4, 36, 36)];
    avatarImg.contentMode = UIViewContentModeScaleAspectFill;
    avatarImg.layer.cornerRadius = 18;
    avatarImg.clipsToBounds = YES;
    avatarImg.userInteractionEnabled = NO;

    state.avatarImageView = avatarImg;
    state.avatarFallbackView = fallback;
    state.avatarMirror = [XHSNativeAvatarMirror new];
    state.namePill = XHSGlassMakePill(@[btn], kXHSNativeBarNoteTop, 0, YES);
    [state.namePill.contentView addSubview:fallback];
    [state.namePill.contentView addSubview:avatarImg];
    [overlay.contentView addSubview:state.namePill];
}

static UIButton *noteBuildComposeButton(XHSNativeVideoState *state) {
    __weak XHSNativeVideoState *weakState = state;
    UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
    config.baseForegroundColor = UIColor.labelColor;
    config.image = XHSGlassSymbol(@"square.and.pencil", 18, UIImageSymbolWeightMedium);
    config.contentInsets = NSDirectionalEdgeInsetsZero;
    UIButton *button = [UIButton buttonWithConfiguration:config primaryAction:[UIAction actionWithHandler:^(UIAction *action) {
        (void)action;
        XHSNativeVideoState *s = weakState;
        UIView *field = s.writeRoleView;
        UIView *interaction = s.interactionHost;
        if (!field) return;
        UIControl *ctrl = [field isKindOfClass:UIControl.class] && XHSGlassControlActivation((UIControl *)field) ? (UIControl *)field : nil;
        if (ctrl && ctrl.enabled) {
            [ctrl sendActionsForControlEvents:XHSGlassControlActivation(ctrl)];
            return;
        }
        UIView *commentField = XHSGlassSafeProp(interaction, @"commentField");
        if (field == commentField && [interaction respondsToSelector:NSSelectorFromString(@"clickCommentFieldWithSender:")]) {
            ((void (*)(id, SEL, id))objc_msgSend)(interaction, NSSelectorFromString(@"clickCommentFieldWithSender:"), field);
        } else if ([interaction respondsToSelector:NSSelectorFromString(@"clickEditFieldWithSender:")]) {
            ((void (*)(id, SEL, id))objc_msgSend)(interaction, NSSelectorFromString(@"clickEditFieldWithSender:"), field);
        } else if ([interaction respondsToSelector:NSSelectorFromString(@"clickCommentFieldWithSender:")]) {
            ((void (*)(id, SEL, id))objc_msgSend)(interaction, NSSelectorFromString(@"clickCommentFieldWithSender:"), field);
        }
    }]];
    button.accessibilityLabel = @"写评论";
    return button;
}

static void noteBuildBottom(XHSNativeVideoState *state, XHSNativeVideoOverlayView *overlay,
                            NSArray<NSNumber *> *roles) {
    __weak XHSNativeVideoState *weakState = state;
    NSArray<NSString *> *allSymbols = @[@"heart", @"star", @"bubble"];
    NSArray<NSString *> *allLabels = @[@"点赞", @"收藏", @"评论"];

    [state.engagePill removeFromSuperview];
    [state.composePill removeFromSuperview];

    NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
    for (NSUInteger i = 0; i < roles.count; i++) {
        XHSGlassItemRole role = (XHSGlassItemRole)roles[i].integerValue;
        UIButton *button = XHSGlassMakeActionButton(allSymbols[(NSUInteger)role], allLabels[(NSUInteger)role], UIColor.labelColor, ^(UIAction *action) {
            (void)action;
            XHSNativeVideoState *s = weakState;
            if (!s || i >= s.engageRoleViews.count) return;
            UIView *roleView = s.engageRoleViews[i];
            UIControl *control = i < s.engageControls.count ? s.engageControls[i] : nil;
            BOOL isToggle = (role == XHSGlassItemRoleLike || role == XHSGlassItemRoleCollect);
            BOOL beforeSelected = isToggle && control.selected;
            XHSGlassRelayAction(control ?: roleView, s.interactionHost, NSSelectorFromString(@"clickButtonWithSender:"), YES);
            XHSGlassRefreshBottom(s, YES);
            dispatch_async(dispatch_get_main_queue(), ^{
                XHSGlassRefreshBottom(s, YES);
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
    state.engagePill = roles.count ? XHSGlassMakePill(buttons, kXHSNativeBarNoteBottom, 0, YES) : nil;
    if (state.engagePill) [overlay.contentView addSubview:state.engagePill];

    UIButton *compose = noteBuildComposeButton(state);
    state.composeButton = compose;
    state.composePill = XHSGlassMakePill(@[compose], kXHSNativeBarNoteBottom, 0, YES);
    [overlay.contentView addSubview:state.composePill];
}

@implementation XHSNativeHelper (NoteGlass)

+ (void)layoutNoteTop:(UIView *)bar {
    XHSNativeVideoState *state = XHSGlassStateForHost(bar);
    removeNoteBottomPlate(bar, &kNoteLeftKey);
    removeNoteBottomPlate(bar, &kNoteRightKey);

    BOOL enabled = [XHSNativeConfig.shared boolForKey:kXHSNativeGlassNote];
    if (!enabled) {
        XHSGlassRestoreOriginals(state);
        state.overlayView.hidden = YES;
        return;
    }

    [self clearBackground:bar];

    // 控件那一行在安全区下面
    UIView *row = nil;
    for (UIView *view in bar.subviews) {
        if ([view isKindOfClass:UIVisualEffectView.class] || view.hidden || CGRectGetHeight(view.frame) <= 30) continue;
        if (!row || CGRectGetMinY(view.frame) > CGRectGetMinY(row.frame)) row = view;
    }
    if (row) {
        [self clearBackground:row];
        state.noteRowView = row;
    }

    if (!bar.window || bar.hidden || bar.alpha <= 0.01 || CGRectGetWidth(bar.bounds) < 120 || !row) {
        if (row) XHSGlassHideOriginal(state, row);
        state.overlayView.hidden = YES;
        return;
    }

    UIView *back = XHSGlassSafeProp(bar, @"backButton");
    UIView *author = nil;
    for (UIView *view in row.subviews) {
        if (!back && [view isKindOfClass:UIButton.class]) back = view;
        if (!author) author = [self subviewOf:view named:@"XYNoteModule.NoteDirectionView"] ?: [self subviewOf:view named:@"XYNoteModule.NoteDuoDirectionView"];
    }
    if (!author) {
        state.overlayView.hidden = YES;
        return;
    }
    state.noteDirectionHost = author;

    UIView *avatar = XHSGlassSafeProp(author, @"avatarView");
    UIView *follow = XHSGlassSafeProp(author, @"followButton");
    UIView *share = XHSGlassSafeProp(author, @"moreButton") ?: XHSGlassSafeProp(author, @"shareButton");
    UIView *name = XHSGlassSafeProp(author, @"titleLabel") ?: XHSGlassSafeProp(author, @"userInfoStackView");
    UILabel *shareCountLabel = XHSGlassSafeProp(author, @"shareCountLabel");
    UIView *backGlass = XHSGlassSafeProp(author, @"backGlassView");
    UIView *shareGlass = XHSGlassSafeProp(author, @"shareGlassView");
    for (UIView *view in author.subviews) {
        if (!follow && [view isKindOfClass:objc_getClass("XYFollowBtn")]) follow = view;
        else if (!share && [view isKindOfClass:UIButton.class] && view != follow && view != back) share = view;
        else if (!name && [view isKindOfClass:UIStackView.class]) name = view;
        else if (!avatar && [NSStringFromClass(view.class) isEqualToString:@"XYUserAvatar"]) avatar = view;
    }

    NSMutableArray<UIView *> *leftSources = [NSMutableArray array];
    NSMutableArray<NSNumber *> *leftRoles = [NSMutableArray array];
    NSMutableArray<NSString *> *leftTitles = [NSMutableArray array];
    if (XHSGlassIsItemActive(back)) {
        [leftSources addObject:back];
        [leftRoles addObject:@(XHSVideoTopRoleBack)];
        [leftTitles addObject:@""];
    }

    NSMutableArray<UIView *> *rightSources = [NSMutableArray array];
    NSMutableArray<NSNumber *> *rightRoles = [NSMutableArray array];
    NSMutableArray<NSString *> *rightTitles = [NSMutableArray array];
    if (XHSGlassIsItemActive(follow)) {
        [rightSources addObject:follow];
        [rightRoles addObject:@(XHSVideoTopRoleNoteFollow)];
        [rightTitles addObject:@""];
    }
    NSString *shareCount = (XHSGlassIsItemActive(shareCountLabel) ? XHSGlassCountText(shareCountLabel.text) : nil) ?: @"";
    if (XHSGlassIsItemActive(share)) {
        [rightSources addObject:share];
        [rightRoles addObject:@(XHSVideoTopRoleShare)];
        [rightTitles addObject:shareCount];
    }

    BOOL hasAvatar = (avatar != nil && !avatar.hidden);
    NSString *authorName = noteAuthorNameText(author, name);
    BOOL hasName = (authorName.length > 0);
    if (!leftSources.count && !rightSources.count && !hasAvatar && !hasName) {
        state.overlayView.hidden = YES;
        return;
    }

    // 隐藏原顶栏内容，改为 App Store 风格独立圆形头像玻璃 + 用户名胶囊 + 图标化关注与分享
    XHSGlassHideOriginal(state, row);
    if (backGlass) XHSGlassHideOriginal(state, backGlass);
    if (shareGlass) XHSGlassHideOriginal(state, shareGlass);

    XHSNativeVideoOverlayView *overlay = XHSGlassEnsureOverlay(state, 8.0, YES);
    overlay.hidden = NO;
    overlay.alpha = 1;

    BOOL leftChanged = ![state.topLeftRoles isEqualToArray:leftRoles] || ![state.topLeftSources isEqualToArray:leftSources];
    BOOL rightChanged = ![state.topRightRoles isEqualToArray:rightRoles] || ![state.topRightSources isEqualToArray:rightSources];
    state.topLeftSources = leftSources;
    state.topLeftRoles = leftRoles;
    state.topRightSources = rightSources;
    state.topRightRoles = rightRoles;
    state.avatarSourceView = avatar;
    state.nameSourceView = name ?: avatar;

    if (leftChanged) {
        [state.topLeftPill removeFromSuperview];
        state.topLeftPill = noteBuildTopPill(state, leftSources, leftRoles, leftTitles, YES);
        if (state.topLeftPill) [overlay.contentView addSubview:state.topLeftPill];
    }
    noteEnsureProfilePill(state, overlay);
    if (rightChanged) {
        [state.topRightPill removeFromSuperview];
        state.topRightPill = noteBuildTopPill(state, rightSources, rightRoles, rightTitles, NO);
        if (state.topRightPill) [overlay.contentView addSubview:state.topRightPill];
    }

    if (state.topLeftPill.superview != overlay.contentView) [overlay.contentView addSubview:state.topLeftPill];
    if (state.namePill.superview != overlay.contentView) [overlay.contentView addSubview:state.namePill];
    if (state.topRightPill.superview != overlay.contentView) [overlay.contentView addSubview:state.topRightPill];

    UIColor *followRed = [UIColor colorWithRed:1.0 green:0.18 blue:0.33 alpha:1.0];
    for (NSUInteger i = 0; i < leftSources.count; i++) {
        UIView *src = leftSources[i];
        if (i < state.topLeftButtons.count && [src isKindOfClass:UIControl.class]) {
            state.topLeftButtons[i].enabled = ((UIControl *)src).enabled;
        }
    }
    for (NSUInteger i = 0; i < rightSources.count; i++) {
        UIView *src = rightSources[i];
        XHSVideoTopRole role = (XHSVideoTopRole)rightRoles[i].integerValue;
        if (i < state.topRightButtons.count) {
            UIButton *btn = state.topRightButtons[i];
            if ([src isKindOfClass:UIControl.class]) btn.enabled = ((UIControl *)src).enabled;
            BOOL isFollow = (role == XHSVideoTopRoleNoteFollow);
            BOOL followSelected = isFollow && noteFollowIsSelected(author, src);
            NSString *symbol = isFollow ? (followSelected ? @"person.fill.checkmark" : @"person.badge.plus") : XHSGlassSymbolForTopRole(role);
            UIColor *targetColor = isFollow ? (followSelected ? UIColor.secondaryLabelColor : followRed) : UIColor.labelColor;
            NSString *title = (!isFollow && rightTitles[i].length) ? rightTitles[i] : nil;
            XHSGlassUpdateTopButton(btn, symbol, title, targetColor, i == 0, i + 1 == rightSources.count, isFollow);
        }
    }

    if (hasAvatar) {
        UIImageView *srcIV = noteFindAvatarImageView(avatar);
        [state.avatarMirror attachSource:srcIV target:state.avatarImageView fallback:state.avatarFallbackView];
        if (!srcIV.image) {
            UIImage *directImg = XHSGlassSafeProp(avatar, @"userAvatarImage");
            if ([directImg isKindOfClass:UIImage.class]) {
                state.avatarImageView.image = directImg;
                state.avatarFallbackView.hidden = YES;
            }
        }
    }
    state.avatarImageView.hidden = !hasAvatar;
    state.avatarFallbackView.hidden = !hasAvatar || (state.avatarImageView.image != nil);

    if (state.namePill.buttons.count) {
        UIButton *nameBtn = state.namePill.buttons.firstObject;
        NSString *targetTitle = hasName ? authorName : nil;
        CGFloat lead = hasAvatar ? 48.0 : 14.0;
        CGFloat trail = hasName ? 14.0 : 4.0;
        if (![nameBtn.configuration.title ?: @"" isEqualToString:targetTitle ?: @""] ||
            fabs(nameBtn.configuration.contentInsets.leading - lead) > 0.5 ||
            fabs(nameBtn.configuration.contentInsets.trailing - trail) > 0.5) {
            UIButtonConfiguration *cfg = [nameBtn.configuration copy];
            cfg.title = targetTitle;
            cfg.contentInsets = NSDirectionalEdgeInsetsMake(0, lead, 0, trail);
            nameBtn.configuration = cfg;
        }
    }

    CGFloat height = 44;
    CGFloat edge = 16;
    CGFloat spacing = 8;
    CGFloat y = CGRectGetMidY(row.frame) - height / 2;
    y = MIN(MAX(y, 0), MAX(0, CGRectGetHeight(bar.bounds) - height));

    NSMutableArray<UIView *> *pills = [NSMutableArray array];
    CGFloat cursorX = edge;
    if (state.topLeftPill) {
        XHSGlassApplyPillFill(state.topLeftPill);
        state.topLeftPill.hidden = NO;
        state.topLeftPill.alpha = 1;
        state.topLeftPill.frame = CGRectMake(cursorX, y, height, height);
        state.topLeftPill.contentView.layer.cornerRadius = height / 2;
        [pills addObject:state.topLeftPill];
        cursorX += height + spacing;
    }

    CGFloat rightW = 0;
    CGRect rightFrame = CGRectZero;
    if (state.topRightPill) {
        XHSGlassApplyPillFill(state.topRightPill);
        CGFloat fitW = ceil([state.topRightPill.contentView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].width);
        rightW = rightSources.count == 1 ? MAX(height, fitW) : MAX(88, fitW);
        rightFrame = CGRectMake(CGRectGetWidth(bar.bounds) - edge - rightW, y, rightW, height);
        state.topRightPill.hidden = NO;
        state.topRightPill.alpha = 1;
        state.topRightPill.frame = rightFrame;
        state.topRightPill.contentView.layer.cornerRadius = height / 2;
    }

    // Telegram 风格：头像 + 用户名融合在同一个液态玻璃胶囊内
    CGFloat maxNameRight = CGRectIsEmpty(rightFrame) ? (CGRectGetWidth(bar.bounds) - edge) : (CGRectGetMinX(rightFrame) - spacing);
    CGFloat maxNameW = maxNameRight - cursorX;
    BOOL showProfile = (hasAvatar || hasName) && maxNameW >= height;
    state.namePill.hidden = !showProfile;
    if (showProfile) {
        XHSGlassApplyPillFill(state.namePill);
        state.namePill.alpha = 1;
        CGFloat profileW = height;
        if (hasName) {
            CGFloat fitNameW = ceil([state.namePill.contentView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].width);
            profileW = MIN(MAX(hasAvatar ? 88 : 56, fitNameW), maxNameW);
        }
        state.namePill.frame = CGRectMake(cursorX, y, profileW, height);
        state.namePill.contentView.layer.cornerRadius = height / 2;
        state.avatarImageView.frame = CGRectMake(4, 4, 36, 36);
        state.avatarFallbackView.frame = CGRectMake(4, 4, 36, 36);
        [pills addObject:state.namePill];
    }

    if (state.topRightPill) [pills addObject:state.topRightPill];
    overlay.interactivePills = pills;
    if (!CGRectEqualToRect(overlay.frame, bar.bounds)) overlay.frame = bar.bounds;
    [bar bringSubviewToFront:overlay];
}

+ (void)layoutNoteBottom:(UIView *)bar {
    XHSNativeVideoState *state = XHSGlassStateForHost(bar);
    removeNoteBottomPlate(bar, &kNoteBottomKey);
    removeNoteBottomPlate(bar, &kNoteBottomRightKey);

    BOOL enabled = [XHSNativeConfig.shared boolForKey:kXHSNativeGlassNote];
    if (!enabled) {
        XHSGlassRestoreOriginals(state);
        state.overlayView.hidden = YES;
        return;
    }

    UIView *content = [self subviewOf:bar named:@"XYNoteModule.InteractionView"];
    if (!content) {
        state.overlayView.hidden = YES;
        return;
    }

    [self clearBackground:bar];
    [self clearBackground:content];
    if (bar.clipsToBounds) bar.clipsToBounds = NO;

    UIView *stack = nil;
    for (UIView *view in content.subviews) {
        if ([view isKindOfClass:UIVisualEffectView.class]) continue;
        if ([view isKindOfClass:UIStackView.class]) stack = stack ?: view;
        else if (!view.subviews.count && CGRectGetHeight(view.frame) > 0 && CGRectGetHeight(view.frame) <= 1 && !view.hidden) view.hidden = YES;
    }

    UIView *likeBtn = XHSGlassSafeProp(content, @"likeButton");
    UIView *collectBtn = XHSGlassSafeProp(content, @"collectButton");
    UIView *commentBtn = XHSGlassSafeProp(content, @"commentButton");
    UIView *editField = XHSGlassSafeProp(content, @"editField");
    UIView *commentField = XHSGlassSafeProp(content, @"commentField");
    UIView *replyField = XHSGlassSafeProp(content, @"replyField");
    UIView *editGlass = XHSGlassSafeProp(content, @"editGlassView");
    UIView *commentGlass = XHSGlassSafeProp(content, @"commentGlassView");

    // 无论处于滑动还是离屏过渡，始终隐藏原栏，杜绝切换时原组件闪烁
    XHSGlassHideOriginal(state, content);
    if (editGlass) XHSGlassHideOriginal(state, editGlass);
    if (commentGlass) XHSGlassHideOriginal(state, commentGlass);

    if (!content.window || !noteBottomIsVisible(bar) || bar.hidden || bar.alpha <= 0.01 || CGRectGetWidth(bar.bounds) < 160 || (stack && CGRectGetHeight(stack.frame) <= 1)) {
        state.overlayView.hidden = YES;
        return;
    }

    NSMutableArray<UIView *> *roleViews = [NSMutableArray array];
    NSMutableArray<UIControl *> *controls = [NSMutableArray array];
    NSMutableArray<NSNumber *> *roles = [NSMutableArray array];
    NSArray *candidates = @[likeBtn ?: NSNull.null, collectBtn ?: NSNull.null, commentBtn ?: NSNull.null];
    for (NSUInteger idx = 0; idx < candidates.count; idx++) {
        id item = candidates[idx];
        if (item == NSNull.null) continue;
        UIView *view = (UIView *)item;
        if (!XHSGlassIsItemActive(view)) continue;
        UIControl *control = [view isKindOfClass:UIControl.class] ? (UIControl *)view : XHSGlassControlIn(view);
        if (!control) continue;
        [roleViews addObject:view];
        [controls addObject:control];
        [roles addObject:@(idx)];
    }

    UIView *activeField = XHSGlassIsItemActive(editField) ? editField : (XHSGlassIsItemActive(commentField) ? commentField : (XHSGlassIsItemActive(replyField) ? replyField : nil));
    if (!activeField && stack) {
        for (UIView *group in stack.subviews) {
            for (UIView *field in group.subviews) {
                if ([NSStringFromClass(field.class) hasSuffix:@"Field"] && XHSGlassIsItemActive(field)) {
                    activeField = field;
                    break;
                }
            }
            if (activeField) break;
        }
    }

    if (!roleViews.count && !activeField) {
        state.overlayView.hidden = YES;
        return;
    }

    state.interactionHost = content;
    state.engageRoleViews = roleViews;
    state.engageControls = controls;
    state.writeRoleView = activeField;
    state.writeControl = [activeField isKindOfClass:UIControl.class] ? (UIControl *)activeField : nil;

    XHSNativeVideoOverlayView *overlay = XHSGlassEnsureOverlay(state, 10.0, YES);
    overlay.hidden = NO;
    overlay.alpha = 1;
    if (!state.composePill || ![state.engageRoles isEqualToArray:roles]) {
        noteBuildBottom(state, overlay, roles);
    }
    if (state.engagePill && state.engagePill.superview != overlay.contentView) [overlay.contentView addSubview:state.engagePill];
    if (state.composePill && state.composePill.superview != overlay.contentView) [overlay.contentView addSubview:state.composePill];

    CGFloat height = 48;
    CGFloat gap = 10;
    CGFloat width = CGRectGetWidth(bar.bounds);
    CGFloat below = CGRectGetHeight(bar.window.bounds) - CGRectGetMaxY([bar convertRect:bar.bounds toView:nil]);
    CGFloat margin = bar.window.safeAreaInsets.bottom > 0 ? 16 : MAX(0, (CGRectGetHeight(bar.bounds) - height) / 2);
    CGFloat y = CGRectGetHeight(bar.bounds) + below - (bar.window.safeAreaInsets.bottom > 0 ? 20 : margin) - height;

    BOOL disableCompose = [NSUserDefaults.standardUserDefaults boolForKey:kXHSNativeNoteDisableCompose];
    BOOL hasCompose = !disableCompose && activeField != nil;
    CGFloat availableForEngage = width - margin * 2 - (hasCompose ? (height + gap) : 0);

    CGFloat engageWidth = 0;
    if (state.engagePill) {
        state.compactEngage = NO;
        XHSGlassRefreshBottom(state, YES);
        CGFloat fit = ceil([state.engagePill.contentView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].width);
        if (fit > availableForEngage) {
            state.compactEngage = YES;
            XHSGlassRefreshBottom(state, YES);
            fit = ceil([state.engagePill.contentView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].width);
        }
        if (fit <= 0) {
            overlay.hidden = YES;
            return;
        }
        engageWidth = MIN(MAX(fit, roleViews.count == 1 ? height : 132), MAX(height, width - margin * 2));
    }

    if (hasCompose && (width - margin * 2 - (state.engagePill ? (engageWidth + gap) : 0)) < height) hasCompose = NO;
    if (disableCompose) XHSGlassDisableOriginal(state, activeField);

    NSMutableArray<UIView *> *pills = [NSMutableArray array];
    if (state.engagePill) {
        XHSGlassApplyPillFill(state.engagePill);
        state.engagePill.hidden = NO;
        state.engagePill.alpha = 1;
        state.engagePill.frame = CGRectMake(width - margin - engageWidth, y, engageWidth, height);
        state.engagePill.contentView.layer.cornerRadius = height / 2;
        [pills addObject:state.engagePill];
    }
    state.composePill.hidden = !hasCompose;
    if (hasCompose) {
        XHSGlassApplyPillFill(state.composePill);
        state.composePill.alpha = 1;
        state.composePill.frame = CGRectMake(margin, y, height, height);
        state.composePill.contentView.layer.cornerRadius = height / 2;
        [pills addObject:state.composePill];
    }
    overlay.interactivePills = pills;
    if (!CGRectEqualToRect(overlay.frame, bar.bounds)) overlay.frame = bar.bounds;
    [bar bringSubviewToFront:overlay];
}

+ (void)layoutNotePage:(UIViewController *)page {
    UINavigationController *navigation = page.navigationController;
    UIViewController *topPage = navigation.topViewController;
    UIView *root = page.view;
    UIView *top = [self subviewOf:root named:@"XYNoteModule.NavigationBar"], *bottom = [self subviewOf:root named:@"XYNoteModule.NoteDetailBottomView"];
    if (![XHSNativeConfig.shared boolForKey:kXHSNativeGlassNote] ||
        (topPage && topPage != page && topPage.isViewLoaded && ![page.viewIfLoaded isDescendantOfView:topPage.view])) {
        updatePageNoteBottom(page, nil);
        if (top) [self layoutNoteTop:top];
        if (bottom) [self layoutNoteBottom:bottom];
        return;
    }
    UICollectionView *list = nil;
    for (UIView *view in root.subviews)
        if ([view isKindOfClass:UICollectionView.class]) list = list ?: (UICollectionView *)view;
    if (!top || !bottom || !list || top.hidden || bottom.hidden) {
        updatePageNoteBottom(page, nil);
        if (top) [self layoutNoteTop:top];
        if (bottom) [self layoutNoteBottom:bottom];
        return;
    }
    updatePageNoteBottom(page, bottom);

    // 列表的位置不动，它本来就夹在上下两条栏之间。不裁剪，滚出去的内容就能透过栏看到；
    // 可见范围往上下扩到屏幕边，栏后面的单元格才不会被回收（否则栏下面会一块块露出底色）
    if (list.clipsToBounds) list.clipsToBounds = NO;
    UIEdgeInsets reach = UIEdgeInsetsMake(-CGRectGetMinY(list.frame), 0, CGRectGetMaxY(list.frame) - CGRectGetMaxY(root.bounds), 0);
    if ([list respondsToSelector:@selector(_setVisibleRectEdgeInsets:)] && !UIEdgeInsetsEqualToEdgeInsets([list _visibleRectEdgeInsets], reach))
        [list _setVisibleRectEdgeInsets:reach];

    // 顶栏下面的 soft 边缘，见 XHSNativeSoftEdge；底部不要边缘效果，胶囊直接浮在正文上
    XHSNativeSoftEdge *edge = objc_getAssociatedObject(list, &kNoteEdgeKey);
    if (!edge) {
        edge = [XHSNativeSoftEdge new];
        edge.userInteractionEnabled = NO;
        edge.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        edge.topEdgeEffect.style = UIScrollEdgeEffectStyle.softStyle;
        UIScrollEdgeElementContainerInteraction *interaction = [UIScrollEdgeElementContainerInteraction new];
        interaction.edge = UIRectEdgeTop;
        interaction.scrollView = edge;
        [top addInteraction:interaction];
        [list addObserver:edge forKeyPath:@"contentOffset" options:0 context:NULL];
        objc_setAssociatedObject(list, &kNoteEdgeKey, edge, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (edge.superview != root) [root insertSubview:edge belowSubview:top];
    if (!CGRectEqualToRect(edge.frame, top.frame)) {
        edge.frame = top.frame;
        edge.contentSize = top.frame.size;
        edge.contentInset = UIEdgeInsetsMake(CGRectGetHeight(top.frame), 0, 0, 0);
    }
    [edge follow:list];
    if (!list.bottomEdgeEffect.hidden) list.bottomEdgeEffect.hidden = YES;

    [self layoutNoteTop:top];
    [self layoutNoteBottom:bottom];
}

// 「头像 昵称 关注 分享」这一条是贴着安全区摆的，上面把栏高记进安全区之后它会被推到栏外，
// 用位移把它放回容器的垂直正中（位移不参与自动布局，不会和它的约束打架）
+ (void)recenterAuthorRow:(UIView *)row {
    if (!CGAffineTransformIsIdentity(row.transform)) row.transform = CGAffineTransformIdentity;
    for (UIView *view = row.superview; view; view = view.superview) {
        if (![NSStringFromClass(view.class) isEqualToString:@"XYNoteModule.NavigationBar"]) continue;
        [self layoutNoteTop:view];
        break;
    }
}

+ (void)refreshNoteTopFromDirection:(UIView *)direction {
    XHSGlassClearOurHide(direction);
    for (UIView *view = direction.superview; view; view = view.superview) {
        if (![NSStringFromClass(view.class) isEqualToString:@"XYNoteModule.NavigationBar"]) continue;
        [self layoutNoteTop:view];
        break;
    }
}

+ (void)refreshNoteBottomFromInteraction:(UIView *)interaction {
    for (UIView *view = interaction.superview; view; view = view.superview) {
        if (![NSStringFromClass(view.class) isEqualToString:@"XYNoteModule.NoteDetailBottomView"]) continue;
        [self layoutNoteBottom:view];
        break;
    }
}

+ (void)refreshNoteBottomLikeFromInteraction:(UIView *)interaction liked:(BOOL)liked animated:(BOOL)animated {
    for (UIView *view = interaction.superview; view; view = view.superview) {
        if (![NSStringFromClass(view.class) isEqualToString:@"XYNoteModule.NoteDetailBottomView"]) continue;
        XHSNativeVideoState *state = XHSGlassExistingState(view);
        BOOL wasLiked = state ? state.lastLiked : NO;
        if (state) {
            state.hasLikeOverride = YES;
            state.likeSelectedOverride = liked;
        }
        [self layoutNoteBottom:view];
        if (state) state.hasLikeOverride = NO;
        if (liked && (!wasLiked || animated) && state.engageButtons.count && state.engageRoles.count && state.engageRoles[0].integerValue == XHSGlassItemRoleLike) {
            XHSGlassBounceSymbol(state.engageButtons[0]);
        }
        break;
    }
}

+ (void)resetNoteItem:(UIView *)item {
    XHSGlassClearOurHide(item);
    [self refreshNoteBottomFromInteraction:item];
}

// 双击图片：用小红书自己的双指放大，见 XHSNativePinchHold
+ (void)toggleZoomInBrowser:(UIView *)browser {
    if (gPinchHold) return [gPinchHold finish];
    id controller = [browser respondsToSelector:@selector(pinchController)] ? [browser pinchController] : nil;
    if (![controller respondsToSelector:@selector(didReceivePinchWithRecognizer:)] || ![controller installed] || [controller inTransform]) return;
    UIWindow *window = browser.window;
    UIGestureRecognizer *real = [controller recognizer];
    if (!window || !real.view) return;

    XHSNativePinchHold *hold = [XHSNativePinchHold new];
    hold.controller = controller;
    hold.pinch = [[XHSNativeFakePinch alloc] initWithTarget:nil action:nil];
    hold.pinch.hostView = real.view;
    hold.pinch.fakeScale = 1;
    // 以点按的位置为中心放大
    id tap = [browser respondsToSelector:@selector(multiRegesture)] ? [browser multiRegesture] : nil;
    hold.pinch.fakePoint = [tap isKindOfClass:UIGestureRecognizer.class] ? [(UIGestureRecognizer *)tap locationInView:nil]
                                                                        : [browser convertPoint:CGPointMake(CGRectGetMidX(browser.bounds), CGRectGetMidY(browser.bounds)) toView:nil];
    // 开始时它从自己的 recognizer 取位置和手指数，先换成假的
    [controller setRecognizer:hold.pinch];
    [hold send:UIGestureRecognizerStateBegan];
    [controller setRecognizer:real];
    if (![controller inTransform]) return;

    UIView *catcher = [[UIView alloc] initWithFrame:window.bounds];
    catcher.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [catcher addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:hold action:@selector(pan:)]];
    [catcher addGestureRecognizer:[[UIPinchGestureRecognizer alloc] initWithTarget:hold action:@selector(zoom:)]];
    [catcher addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:hold action:@selector(finish)]];
    [window addSubview:catcher];
    hold.catcher = catcher;
    hold.link = [CADisplayLink displayLinkWithTarget:hold selector:@selector(grow:)];
    [hold.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    gPinchHold = hold;
}

+ (void)resetZoom {
    [gPinchHold finish];
}

@end
