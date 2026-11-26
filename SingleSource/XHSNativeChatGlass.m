//
//  XHSNative
//
//  Copyright (c) 2026 huami. All rights reserved.
//  Channel: @huamidev
//  Created on: 2026/11/25
//
#import "XHSNativeGlassShared.h"
#import <UIKit/UIGestureRecognizerSubclass.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "XHSNativeConfig.h"

#pragma mark - 原生液态玻璃按压弹性反馈（原始触摸监听，兼容 UITextView 且零拦截）

@interface XHSNativeTouchObserverGesture : UIGestureRecognizer
@property (nonatomic, copy) void (^onPressChanged)(BOOL pressed);
@end

@implementation XHSNativeTouchObserverGesture

- (instancetype)initWithTarget:(id)target action:(SEL)action {
    self = [super initWithTarget:target action:action];
    if (self) {
        self.cancelsTouchesInView = NO;
        self.delaysTouchesBegan = NO;
        self.delaysTouchesEnded = NO;
    }
    return self;
}

- (BOOL)canPreventGestureRecognizer:(UIGestureRecognizer *)preventedGestureRecognizer {
    (void)preventedGestureRecognizer;
    return NO;
}

- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer *)preventingGestureRecognizer {
    (void)preventingGestureRecognizer;
    return NO;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    if (self.onPressChanged) self.onPressChanged(YES);
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    if (self.onPressChanged) self.onPressChanged(NO);
    self.state = UIGestureRecognizerStateFailed;
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    if (self.onPressChanged) self.onPressChanged(NO);
    self.state = UIGestureRecognizerStateFailed;
}

@end

@interface XHSNativeGlassPressReactor : NSObject
@property (nonatomic, weak) UIVisualEffectView *glassView;
@property (nonatomic, weak) UIView *sheenView;
@property (nonatomic, strong) NSPointerArray *extraTargets;
@property (nonatomic, strong) XHSNativeTouchObserverGesture *gesture;
@end

@implementation XHSNativeGlassPressReactor

- (void)attachToHost:(UIView *)host glassView:(UIVisualEffectView *)glass extraTargets:(NSArray<UIView *> *)targets {
    if (!host || !glass) return;
    if (self.glassView != glass) {
        self.glassView = glass;
        static char kSheenKey;
        UIView *sheen = objc_getAssociatedObject(glass, &kSheenKey);
        if (!sheen) {
            sheen = [[UIView alloc] initWithFrame:glass.contentView.bounds];
            sheen.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            sheen.userInteractionEnabled = NO;
            sheen.alpha = 0;
            sheen.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
                return traits.userInterfaceStyle == UIUserInterfaceStyleDark
                    ? [UIColor colorWithWhite:1.0 alpha:0.16]
                    : [UIColor colorWithWhite:1.0 alpha:0.34];
            }];
            [glass.contentView addSubview:sheen];
            objc_setAssociatedObject(glass, &kSheenKey, sheen, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        self.sheenView = sheen;
    }
    NSPointerArray *arr = [NSPointerArray weakObjectsPointerArray];
    for (UIView *t in targets) {
        if (t && t != glass) [arr addPointer:(__bridge void *)t];
    }
    self.extraTargets = arr;

    if (!self.gesture) {
        __weak XHSNativeGlassPressReactor *weakSelf = self;
        XHSNativeTouchObserverGesture *g = [[XHSNativeTouchObserverGesture alloc] initWithTarget:nil action:nil];
        g.onPressChanged = ^(BOOL pressed) {
            [weakSelf setPressed:pressed];
        };
        self.gesture = g;
    }
    if (self.gesture.view != host) {
        [self.gesture.view removeGestureRecognizer:self.gesture];
        [host addGestureRecognizer:self.gesture];
    }
}

- (void)setPressed:(BOOL)pressed {
    UIVisualEffectView *glass = self.glassView;
    if (!glass) return;
    UIView *sheen = self.sheenView;
    BOOL isCircle = (fabs(CGRectGetWidth(glass.bounds) - CGRectGetHeight(glass.bounds)) < 8.0);
    CGAffineTransform targetTransform = pressed
        ? (isCircle ? CGAffineTransformMakeScale(1.09, 1.09) : CGAffineTransformMakeScale(1.022, 1.055))
        : CGAffineTransformIdentity;
    if (pressed) {
        sheen.frame = glass.contentView.bounds;
        sheen.layer.cornerRadius = CGRectGetHeight(glass.bounds) / 2.0;
    }
    [UIView animateWithDuration:pressed ? 0.14 : 0.38
                          delay:0
         usingSpringWithDamping:pressed ? 0.78 : 0.58
          initialSpringVelocity:pressed ? 0.6 : 0.5
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        glass.transform = targetTransform;
        sheen.alpha = pressed ? 1.0 : 0.0;
    } completion:nil];
    // 用非破坏性 layer 弹性动画联动内部图标，绝不改 model transform，避免与小红书 layoutSubviews/UITextView 冲突闪退
    if (pressed) {
        CGFloat peak = isCircle ? 1.12 : 1.06;
        for (NSUInteger i = 0; i < self.extraTargets.count; i++) {
            UIView *v = (__bridge UIView *)[self.extraTargets pointerAtIndex:i];
            if (!v) continue;
            CAKeyframeAnimation *anim = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
            anim.values = @[@1.0, @(peak), @1.0];
            anim.keyTimes = @[@0.0, @0.35, @1.0];
            anim.duration = 0.28;
            anim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            [v.layer addAnimation:anim forKey:@"xhsNativeGlassPulse"];
        }
    }
}

@end

static void chatAttachGlassPressReactor(UIView *host, UIVisualEffectView *glass, NSArray<UIView *> *extraTargets) {
    if (!host || !glass) return;
    static char kPressReactorKey;
    XHSNativeGlassPressReactor *reactor = objc_getAssociatedObject(host, &kPressReactorKey);
    if (!reactor) {
        reactor = [XHSNativeGlassPressReactor new];
        objc_setAssociatedObject(host, &kPressReactorKey, reactor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [reactor attachToHost:host glassView:glass extraTargets:extraTargets];
}

@class XHSNativeIMessagePlusMenu;

@interface XHSNativeIMessagePlusMenu : UIView
@property (nonatomic, strong) UIView *shadowHost;
@property (nonatomic, strong) UIVisualEffectView *glassCard;
@property (nonatomic, weak) id moreViewModel;
@property (nonatomic, copy) NSArray *items;
+ (instancetype)activeMenu;
+ (void)dismissActiveAnimated:(BOOL)animated;
- (void)showInWindow:(UIWindow *)window anchorRect:(CGRect)anchorRect moreViewModel:(id)moreVM items:(NSArray *)items;
@end

#pragma mark - iMessage 风格通透气泡视图（对方毛玻璃通透适配壁纸 + 己方小红书红质感渐变）

@interface XHSNativeIMessageBubbleView : UIView
@property (nonatomic, assign) BOOL selfSend;
@property (nonatomic, strong) UIColor *bubbleColor;
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UIView *tintOverlay;
@property (nonatomic, strong) CAGradientLayer *redGradientLayer;
@property (nonatomic, strong) CAShapeLayer *blurMaskLayer;
@property (nonatomic, strong) CAShapeLayer *gradMaskLayer;
@property (nonatomic, strong) CAShapeLayer *rimStrokeLayer;
@property (nonatomic, assign) CGSize lastPathSize;
@property (nonatomic, assign) BOOL lastPathSelfSend;
@end

@implementation XHSNativeIMessageBubbleView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.clipsToBounds = NO;
        self.userInteractionEnabled = NO;

        _blurView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
        _blurView.userInteractionEnabled = NO;
        _blurMaskLayer = [CAShapeLayer layer];
        _blurView.layer.mask = _blurMaskLayer;
        [self addSubview:_blurView];

        _tintOverlay = [[UIView alloc] init];
        _tintOverlay.userInteractionEnabled = NO;
        [_blurView.contentView addSubview:_tintOverlay];

        _redGradientLayer = [CAGradientLayer layer];
        _redGradientLayer.startPoint = CGPointMake(0.5, 0.0);
        _redGradientLayer.endPoint = CGPointMake(0.5, 1.0);
        _redGradientLayer.colors = @[
            (id)[UIColor colorWithRed:1.0 green:0.20 blue:0.31 alpha:0.96].CGColor,
            (id)[UIColor colorWithRed:0.94 green:0.11 blue:0.23 alpha:0.96].CGColor,
        ];
        _gradMaskLayer = [CAShapeLayer layer];
        _redGradientLayer.mask = _gradMaskLayer;
        [self.layer addSublayer:_redGradientLayer];

        _rimStrokeLayer = [CAShapeLayer layer];
        _rimStrokeLayer.fillColor = UIColor.clearColor.CGColor;
        _rimStrokeLayer.lineWidth = 0.5;
        [self.layer addSublayer:_rimStrokeLayer];
    }
    return self;
}

- (void)setSelfSend:(BOOL)selfSend {
    if (_selfSend == selfSend) return;
    _selfSend = selfSend;
    [self updateBubblePath];
    [self updateFillColor];
}

- (void)setBubbleColor:(UIColor *)bubbleColor {
    _bubbleColor = bubbleColor;
    [self updateFillColor];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self updateBubblePath];
    [self updateFillColor];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self updateFillColor];
}

- (void)updateFillColor {
    BOOL dark = (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (self.selfSend) {
        self.blurView.hidden = YES;
        self.redGradientLayer.hidden = NO;
        self.rimStrokeLayer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
    } else {
        self.blurView.hidden = NO;
        self.redGradientLayer.hidden = YES;
        self.tintOverlay.backgroundColor = dark
            ? [UIColor colorWithRed:0.15 green:0.15 blue:0.17 alpha:0.58]
            : [UIColor colorWithWhite:1.0 alpha:0.66];
        self.rimStrokeLayer.strokeColor = dark
            ? [UIColor colorWithWhite:1.0 alpha:0.14].CGColor
            : [UIColor colorWithWhite:0.0 alpha:0.06].CGColor;
    }
    [CATransaction commit];
}

// 绘制带底角小尾巴的 iMessage 气泡矢量路径
- (void)updateBubblePath {
    CGFloat w = CGRectGetWidth(self.bounds);
    CGFloat h = CGRectGetHeight(self.bounds);
    if (w < 8 || h < 8) {
        self.blurMaskLayer.path = nil;
        self.gradMaskLayer.path = nil;
        self.rimStrokeLayer.path = nil;
        self.lastPathSize = CGSizeZero;
        return;
    }
    if (CGSizeEqualToSize(self.lastPathSize, CGSizeMake(w, h)) && self.lastPathSelfSend == self.selfSend && self.rimStrokeLayer.path != NULL) {
        return;
    }
    self.lastPathSize = CGSizeMake(w, h);
    self.lastPathSelfSend = self.selfSend;
    CGFloat pad = 6.0;
    CGRect expanded = CGRectMake(-pad, 0, w + pad * 2.0, h);
    self.blurView.frame = expanded;
    self.tintOverlay.frame = self.blurView.bounds;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.redGradientLayer.frame = expanded;
    self.rimStrokeLayer.frame = expanded;

    CGFloat r = MIN(17.0, MIN(w * 0.45, h * 0.45));
    CGFloat tail = 5.0;
    UIBezierPath *path = [UIBezierPath bezierPath];

    if (self.selfSend) {
        [path moveToPoint:CGPointMake(pad + r, 0)];
        [path addLineToPoint:CGPointMake(pad + w - r, 0)];
        [path addArcWithCenter:CGPointMake(pad + w - r, r) radius:r startAngle:(CGFloat)(-M_PI_2) endAngle:0 clockwise:YES];
        [path addLineToPoint:CGPointMake(pad + w, h - 10)];
        [path addCurveToPoint:CGPointMake(pad + w + tail, h)
                controlPoint1:CGPointMake(pad + w, h - 4)
                controlPoint2:CGPointMake(pad + w + tail * 0.55, h - 0.5)];
        [path addCurveToPoint:CGPointMake(pad + w - 5.5, h - 2.5)
                controlPoint1:CGPointMake(pad + w + tail * 0.25, h + 0.5)
                controlPoint2:CGPointMake(pad + w - 1.5, h - 0.5)];
        [path addCurveToPoint:CGPointMake(pad + w - r, h)
                controlPoint1:CGPointMake(pad + w - 9, h - 0.5)
                controlPoint2:CGPointMake(pad + w - r + 4, h)];
        [path addLineToPoint:CGPointMake(pad + r, h)];
        [path addArcWithCenter:CGPointMake(pad + r, h - r) radius:r startAngle:(CGFloat)M_PI_2 endAngle:(CGFloat)M_PI clockwise:YES];
        [path addLineToPoint:CGPointMake(pad, r)];
        [path addArcWithCenter:CGPointMake(pad + r, r) radius:r startAngle:(CGFloat)M_PI endAngle:(CGFloat)(3 * M_PI_2) clockwise:YES];
    } else {
        [path moveToPoint:CGPointMake(pad + w - r, 0)];
        [path addArcWithCenter:CGPointMake(pad + w - r, r) radius:r startAngle:(CGFloat)(-M_PI_2) endAngle:0 clockwise:YES];
        [path addLineToPoint:CGPointMake(pad + w, h - r)];
        [path addArcWithCenter:CGPointMake(pad + w - r, h - r) radius:r startAngle:0 endAngle:(CGFloat)M_PI_2 clockwise:YES];
        [path addLineToPoint:CGPointMake(pad + r, h)];
        [path addCurveToPoint:CGPointMake(pad + 5.5, h - 2.5)
                controlPoint1:CGPointMake(pad + r - 4, h)
                controlPoint2:CGPointMake(pad + 9, h - 0.5)];
        [path addCurveToPoint:CGPointMake(pad - tail, h)
                controlPoint1:CGPointMake(pad + 1.5, h - 0.5)
                controlPoint2:CGPointMake(pad - tail * 0.25, h + 0.5)];
        [path addCurveToPoint:CGPointMake(pad, h - 10)
                controlPoint1:CGPointMake(pad - tail * 0.55, h - 0.5)
                controlPoint2:CGPointMake(pad, h - 4)];
        [path addLineToPoint:CGPointMake(pad, r)];
        [path addArcWithCenter:CGPointMake(pad + r, r) radius:r startAngle:(CGFloat)M_PI endAngle:(CGFloat)(3 * M_PI_2) clockwise:YES];
    }
    [path closePath];
    self.blurMaskLayer.path = path.CGPath;
    self.gradMaskLayer.path = path.CGPath;
    self.rimStrokeLayer.path = path.CGPath;
    [CATransaction commit];
}

@end

#pragma mark - 消息页与通用助手

static __weak UIViewController *gMsgSearchCaptureVC = nil;
static char kMsgSearchBlockKey, kMsgSearchGestureKey, kMsgNativeSearchKey, kMsgNativePlusKey;
static BOOL gSuppressPopMenu = NO;
static NSMutableArray *gCapturedPopItems = nil;

static NSString *msgSymbolForMenuTitle(NSString *title) {
    if (!title.length) return @"plus.circle";
    if ([title containsString:@"群广场"] || [title containsString:@"发现群"]) return @"person.3";
    if ([title containsString:@"发起群"] || [title containsString:@"创建群"] || [title containsString:@"新建群"]) return @"plus.bubble";
    if ([title containsString:@"聊天"] || [title containsString:@"发起"]) return @"bubble.left.and.bubble.right";
    if ([title containsString:@"好友"] || [title containsString:@"朋友"]) return @"person.badge.plus";
    if ([title containsString:@"扫一扫"] || [title containsString:@"扫码"]) return @"qrcode.viewfinder";
    if ([title containsString:@"已读"]) return @"checkmark.circle";
    return @"plus.circle";
}

static BOOL msgIsPopMenuItem(UIBarButtonItem *item, UIView *entrance) {
    UIView *cv = item.customView;
    if (!cv) return NO;
    if (entrance && cv == entrance) return YES;
    NSString *cls = NSStringFromClass(cv.class);
    return [cls containsString:@"PopMenuEntrance"] || [cls containsString:@"MessageRightPopMenu"];
}

static BOOL msgIsSearchItem(UIBarButtonItem *item) {
    UIView *cv = item.customView;
    if (!cv) return NO;
    if ([item.accessibilityLabel isEqualToString:@"Search"] || [cv.accessibilityLabel isEqualToString:@"Search"]) return YES;
    return [cv isKindOfClass:UIImageView.class];
}

static NSArray<UIMenuElement *> *msgBuildDeferredMenuItems(UIViewController *vc) {
    if (!vc) return @[];
    NSMutableArray *captured = [NSMutableArray array];
    gCapturedPopItems = captured;
    gSuppressPopMenu = YES;

    id entrance = XHSGlassSafeProp(vc, @"popMenuEntrance");
    UIView *anchor = vc.view ?: vc.navigationController.navigationBar;
    SEL showWithAnchor = NSSelectorFromString(@"showPopMenuViewWithAnchorView:");
    if (entrance && anchor && [entrance respondsToSelector:showWithAnchor]) {
        ((void (*)(id, SEL, id))objc_msgSend)(entrance, showWithAnchor, anchor);
    }
    if (!captured.count && entrance) {
        id vm = XHSGlassSafeProp(entrance, @"popMenuViewModel");
        SEL showPop = NSSelectorFromString(@"showPopViewWith:withAlienationModel:sourceView:anchorView:");
        if (vm && anchor && [vm respondsToSelector:showPop]) {
            ((void (*)(id, SEL, id, id, id, id))objc_msgSend)(vm, showPop, anchor, nil, anchor, anchor);
        }
    }
    if (!captured.count && entrance && [entrance respondsToSelector:NSSelectorFromString(@"popMenuClick")]) {
        ((void (*)(id, SEL))objc_msgSend)(entrance, NSSelectorFromString(@"popMenuClick"));
    }
    if (!captured.count && [vc respondsToSelector:NSSelectorFromString(@"showPopMenu")]) {
        ((void (*)(id, SEL))objc_msgSend)(vc, NSSelectorFromString(@"showPopMenu"));
    }

    gSuppressPopMenu = NO;
    gCapturedPopItems = nil;

    // 清理可能被创建的 PopMenuView 实例，避免残留遮罩
    for (NSString *prop in @[@"menuPopView", @"resizablePopMenuView"]) {
        UIView *pop = XHSGlassSafeProp(vc, prop);
        if ([pop respondsToSelector:NSSelectorFromString(@"dismissImmediatelyForSizeChange")]) {
            ((void (*)(id, SEL))objc_msgSend)(pop, NSSelectorFromString(@"dismissImmediatelyForSizeChange"));
        } else {
            [pop removeFromSuperview];
        }
    }
    id vmPop = XHSGlassSafeProp(XHSGlassSafeProp(entrance, @"popMenuViewModel"), @"menuPopView");
    if ([vmPop respondsToSelector:NSSelectorFromString(@"dismissImmediatelyForSizeChange")]) {
        ((void (*)(id, SEL))objc_msgSend)(vmPop, NSSelectorFromString(@"dismissImmediatelyForSizeChange"));
    }

    NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];
    NSMutableSet<NSString *> *seenTitles = [NSMutableSet set];
    for (id item in captured) {
        NSString *title = XHSGlassSafeProp(item, @"title");
        void (^clickBlock)(void) = XHSGlassSafeProp(item, @"didClickBlock");
        if (!title.length || !clickBlock || [seenTitles containsObject:title]) continue;
        [seenTitles addObject:title];
        NSString *symbol = msgSymbolForMenuTitle(title);
        [actions addObject:[UIAction actionWithTitle:title
                                               image:XHSGlassSymbol(symbol, 16, UIImageSymbolWeightMedium)
                                          identifier:nil
                                             handler:^(UIAction *action) {
            (void)action;
            dispatch_async(dispatch_get_main_queue(), ^{
                clickBlock();
            });
        }]];
    }

    // 补充读取 MessageCenterRightPopMenuViewModel / MessageCenterPlusSignEntries 下发的全部动态菜单项
    NSArray *models = XHSGlassSafeProp(XHSGlassSafeProp(entrance, @"popMenuViewModel"), @"modelArray");
    if (![models isKindOfClass:NSArray.class] || !models.count) {
        Class entriesCls = objc_getClass("_TtC12XYMessageKit28MessageCenterPlusSignEntries");
        id sharedEntries = XHSGlassSafeProp(entriesCls, @"shared");
        models = XHSGlassSafeProp(sharedEntries, @"popMenuModels");
    }
    if ([models isKindOfClass:NSArray.class] && models.count > actions.count) {
        for (id model in models) {
            NSString *title = XHSGlassSafeProp(model, @"title");
            NSString *jump = XHSGlassSafeProp(model, @"jumpUrl");
            if (!jump.length) jump = XHSGlassSafeProp(model, @"targetUrl");
            if (!title.length || !jump.length || [seenTitles containsObject:title]) continue;
            [seenTitles addObject:title];
            NSString *symbol = msgSymbolForMenuTitle(title);
            NSString *urlCopy = [jump copy];
            [actions addObject:[UIAction actionWithTitle:title
                                                   image:XHSGlassSymbol(symbol, 16, UIImageSymbolWeightMedium)
                                              identifier:nil
                                                 handler:^(UIAction *action) {
                (void)action;
                NSURL *u = [NSURL URLWithString:urlCopy];
                if (u) [UIApplication.sharedApplication openURL:u options:@{} completionHandler:nil];
            }]];
        }
    }

    if (!actions.count) {
        __weak UIViewController *weakVC = vc;
        if ([vc respondsToSelector:NSSelectorFromString(@"jumpGroupSquare")]) {
            [actions addObject:[UIAction actionWithTitle:@"发现群聊"
                                                   image:XHSGlassSymbol(@"person.3", 16, UIImageSymbolWeightMedium)
                                              identifier:nil
                                                 handler:^(UIAction *action) {
                (void)action;
                UIViewController *sVC = weakVC;
                if ([sVC respondsToSelector:NSSelectorFromString(@"jumpGroupSquare")]) {
                    ((void (*)(id, SEL))objc_msgSend)(sVC, NSSelectorFromString(@"jumpGroupSquare"));
                }
            }]];
        }
        if ([vc respondsToSelector:NSSelectorFromString(@"createNewGroup:")]) {
            [actions addObject:[UIAction actionWithTitle:@"发起群聊"
                                                   image:XHSGlassSymbol(@"plus.bubble", 16, UIImageSymbolWeightMedium)
                                              identifier:nil
                                                 handler:^(UIAction *action) {
                (void)action;
                UIViewController *sVC = weakVC;
                if ([sVC respondsToSelector:NSSelectorFromString(@"createNewGroup:")]) {
                    ((void (*)(id, SEL, id))objc_msgSend)(sVC, NSSelectorFromString(@"createNewGroup:"), nil);
                }
            }]];
        }
    }
    return actions;
}

static char kSearchInputGlassKey, kSearchBtnGlassKey, kSearchBackGlassKey, kChatInputGlassKey;

static BOOL vcIsSearchController(UIResponder *responder) {
    for (UIResponder *r = responder; r; r = r.nextResponder) {
        if (![r isKindOfClass:UIViewController.class]) continue;
        NSString *cls = NSStringFromClass(r.class);
        if ([cls containsString:@"Search"]) return YES;
    }
    return NO;
}

@implementation XHSNativeHelper (ChatGlass)

#pragma mark - 消息页顶栏与原生菜单

+ (void)beginCapturingMessageSearchForVC:(UIViewController *)vc {
    gMsgSearchCaptureVC = vc;
}

+ (BOOL)isCapturingMessageSearch {
    return gMsgSearchCaptureVC != nil;
}

+ (void)captureMessageSearchTapBlock:(id)block gesture:(id)gesture {
    UIViewController *vc = gMsgSearchCaptureVC;
    if (!vc) return;
    if (block) objc_setAssociatedObject(vc, &kMsgSearchBlockKey, block, OBJC_ASSOCIATION_COPY_NONATOMIC);
    if (gesture) objc_setAssociatedObject(vc, &kMsgSearchGestureKey, gesture, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

+ (void)endCapturingMessageSearch {
    gMsgSearchCaptureVC = nil;
}

+ (BOOL)isSuppressingPopMenu {
    return gSuppressPopMenu;
}

+ (void)capturePopMenuItem:(id)item {
    if (gSuppressPopMenu && item) [gCapturedPopItems addObject:item];
}

static UIImage *msgCircularSwipeIcon(NSString *symbolName, UIColor *bgColor) {
    CGSize size = CGSizeMake(44, 44);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    UIImage *img = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        (void)ctx;
        UIBezierPath *circle = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, size.width, size.height)];
        [bgColor setFill];
        [circle fill];
        UIImage *sym = [XHSGlassSymbol(symbolName, 17.5, UIImageSymbolWeightSemibold) imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
        if (sym) {
            CGSize s = sym.size;
            [sym drawInRect:CGRectMake((size.width - s.width) / 2, (size.height - s.height) / 2, s.width, s.height)];
        }
    }];
    return [img imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

+ (UISwipeActionsConfiguration *)iconSwipeActionsFromConfiguration:(UISwipeActionsConfiguration *)config {
    if (!config || !config.actions.count || ![XHSNativeConfig.shared boolForKey:kXHSNativeGlassMessages]) return config;
    for (UIContextualAction *action in config.actions) {
        NSString *t = action.title ?: @"";
        NSString *symbol = nil;
        UIColor *bg = action.backgroundColor ?: UIColor.systemGrayColor;
        if ([t containsString:@"删除"]) {
            symbol = @"trash.fill";
            bg = UIColor.systemRedColor;
        } else if ([t containsString:@"取消置顶"]) {
            symbol = @"pin.slash.fill";
            bg = UIColor.systemGrayColor;
        } else if ([t containsString:@"置顶"]) {
            symbol = @"pin.fill";
            bg = UIColor.systemOrangeColor;
        } else if ([t containsString:@"未读"]) {
            symbol = @"envelope.badge.fill";
            bg = UIColor.systemBlueColor;
        } else if ([t containsString:@"已读"]) {
            symbol = @"envelope.open.fill";
            bg = UIColor.systemBlueColor;
        } else if ([t containsString:@"免打扰"] || [t containsString:@"静音"]) {
            symbol = @"bell.slash.fill";
            bg = UIColor.systemIndigoColor;
        } else if ([t containsString:@"隐藏"] || [t containsString:@"不显示"]) {
            symbol = @"eye.slash.fill";
            bg = UIColor.systemGray2Color;
        }
        if (symbol) {
            action.title = nil;
            action.image = msgCircularSwipeIcon(symbol, bg);
            action.backgroundColor = UIColor.clearColor;
        }
    }
    return config;
}

+ (void)upgradeMessageCenterBar:(UIViewController *)vc {
    if (!vc || ![XHSNativeConfig.shared boolForKey:kXHSNativeGlassMessages]) return;

    // 收起小红书自建导航玻璃包装，由系统 UINavigationBar 原生渲染胶囊
    UIView *glassView = XHSGlassSafeProp(vc, @"navigationGlassView");
    if (glassView) {
        glassView.hidden = YES;
        [glassView removeFromSuperview];
    }

    UIBarButtonItem *nativeSearch = objc_getAssociatedObject(vc, &kMsgNativeSearchKey);
    if (!nativeSearch) {
        __weak UIViewController *weakVC = vc;
        UIAction *searchAction = [UIAction actionWithTitle:@""
                                                   image:XHSGlassSymbol(@"magnifyingglass", 17, UIImageSymbolWeightMedium)
                                              identifier:nil
                                                 handler:^(UIAction *action) {
            (void)action;
            UIViewController *sVC = weakVC;
            if (!sVC) return;
            void (^tapBlock)(id) = objc_getAssociatedObject(sVC, &kMsgSearchBlockKey);
            id tapGesture = objc_getAssociatedObject(sVC, &kMsgSearchGestureKey);
            if (tapBlock) {
                tapBlock(tapGesture);
            }
        }];
        nativeSearch = [[UIBarButtonItem alloc] initWithPrimaryAction:searchAction];
        nativeSearch.accessibilityLabel = @"搜索";
        objc_setAssociatedObject(vc, &kMsgNativeSearchKey, nativeSearch, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    UIBarButtonItem *nativePlus = objc_getAssociatedObject(vc, &kMsgNativePlusKey);
    if (!nativePlus) {
        __weak UIViewController *weakVC = vc;
        UIDeferredMenuElement *deferred = [UIDeferredMenuElement elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> *)) {
            UIViewController *sVC = weakVC;
            completion(msgBuildDeferredMenuItems(sVC));
        }];
        UIMenu *menu = [UIMenu menuWithTitle:@"" children:@[deferred]];
        nativePlus = [[UIBarButtonItem alloc] initWithImage:XHSGlassSymbol(@"plus", 17.5, UIImageSymbolWeightMedium) menu:menu];
        nativePlus.accessibilityLabel = @"更多";
        objc_setAssociatedObject(vc, &kMsgNativePlusKey, nativePlus, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    id entrance = XHSGlassSafeProp(vc, @"popMenuEntrance");
    UIBarButtonItem *left = vc.navigationItem.leftBarButtonItem;
    if (left && msgIsPopMenuItem(left, entrance)) {
        if (left != nativePlus) vc.navigationItem.leftBarButtonItem = nativePlus;
    }

    NSArray<UIBarButtonItem *> *rightItems = vc.navigationItem.rightBarButtonItems;
    if (rightItems.count) {
        NSMutableArray<UIBarButtonItem *> *updated = [NSMutableArray array];
        BOOL changed = NO;
        for (UIBarButtonItem *item in rightItems) {
            if (item == nativePlus || item == nativeSearch) {
                [updated addObject:item];
            } else if (msgIsPopMenuItem(item, entrance)) {
                [updated addObject:nativePlus];
                changed = YES;
            } else if (msgIsSearchItem(item)) {
                [updated addObject:nativeSearch];
                changed = YES;
            } else if (!item.customView && item.width > 0) {
                changed = YES; // 移除为旧自定义视图预留的固定空白 spacer
            } else {
                [updated addObject:item];
            }
        }
        if (changed) vc.navigationItem.rightBarButtonItems = updated;
    }

    // 消息主页顶栏改为 iOS 26 原生透明导航栏 + 列表顶部 softStyle 渐进模糊
    static char kMsgNavAppAppliedKey;
    if (!objc_getAssociatedObject(vc, &kMsgNavAppAppliedKey)) {
        UINavigationBarAppearance *app = [UINavigationBarAppearance new];
        [app configureWithTransparentBackground];
        vc.navigationItem.standardAppearance = app;
        vc.navigationItem.scrollEdgeAppearance = app;
        vc.navigationItem.compactAppearance = app;
        vc.edgesForExtendedLayout = UIRectEdgeAll;
        vc.extendedLayoutIncludesOpaqueBars = YES;
        objc_setAssociatedObject(vc, &kMsgNavAppAppliedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (vc.isViewLoaded) {
        UIScrollView *list = XHSGlassSafeProp(vc, @"messageTableView") ?: XHSGlassSafeProp(vc, @"tableView");
        if (![list isKindOfClass:UIScrollView.class]) {
            for (UIView *sub in vc.view.subviews) {
                if ([sub isKindOfClass:UIScrollView.class] && CGRectGetHeight(sub.bounds) > 200) {
                    list = (UIScrollView *)sub;
                    break;
                }
            }
        }
        if ([list isKindOfClass:UIScrollView.class]) {
            list.topEdgeEffect.style = UIScrollEdgeEffectStyle.softStyle;
            list.topEdgeEffect.hidden = NO;

            // 隐藏小红书自定义下拉刷新头（防止在透明渐进模糊顶栏下露出来），换上 iOS 原生 UIRefreshControl
            UIView *oldRefresh = XHSGlassSafeProp(vc, @"softEdgeObservedRefreshView");
            if ([oldRefresh isKindOfClass:UIView.class]) {
                oldRefresh.hidden = YES;
                oldRefresh.alpha = 0;
            }
            for (UIView *sub in list.subviews) {
                if ([sub isKindOfClass:UIRefreshControl.class]) continue;
                NSString *cn = NSStringFromClass(sub.class);
                if (([cn containsString:@"Refresh"] || [cn containsString:@"MJRefresh"]) && CGRectGetMinY(sub.frame) < 20) {
                    sub.hidden = YES;
                    sub.alpha = 0;
                }
            }
            static char kMsgNativeRefreshKey;
            UIRefreshControl *rc = objc_getAssociatedObject(list, &kMsgNativeRefreshKey);
            if (!rc) {
                __weak UIViewController *weakVC = vc;
                rc = [UIRefreshControl new];
                __weak UIRefreshControl *weakRC = rc;
                [rc addAction:[UIAction actionWithHandler:^(UIAction *action) {
                    (void)action;
                    UIViewController *sVC = weakVC;
                    if (sVC && [sVC respondsToSelector:NSSelectorFromString(@"pullToRefresh")]) {
                        ((void (*)(id, SEL))objc_msgSend)(sVC, NSSelectorFromString(@"pullToRefresh"));
                    } else if (sVC && [sVC respondsToSelector:NSSelectorFromString(@"refreshData")]) {
                        ((void (*)(id, SEL))objc_msgSend)(sVC, NSSelectorFromString(@"refreshData"));
                    }
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.85 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [weakRC endRefreshing];
                    });
                }] forControlEvents:UIControlEventValueChanged];
                list.refreshControl = rc;
                objc_setAssociatedObject(list, &kMsgNativeRefreshKey, rc, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            } else if (list.refreshControl != rc) {
                list.refreshControl = rc;
            }
        }
    }
}

#pragma mark - 搜索框原生化

+ (void)styleSearchBarV2:(UIView *)bar {
    if (!bar || !bar.window || ![XHSNativeConfig.shared boolForKey:kXHSNativeGlassSearch]) return;
    if (!vcIsSearchController(bar)) return;

    SEL usesGlassSel = NSSelectorFromString(@"usesLiquidGlass");
    SEL setUsesGlassSel = NSSelectorFromString(@"setUsesLiquidGlass:");
    if ([bar respondsToSelector:usesGlassSel] && [bar respondsToSelector:setUsesGlassSel]) {
        BOOL on = ((BOOL (*)(id, SEL))objc_msgSend)(bar, usesGlassSel);
        if (!on) ((void (*)(id, SEL, BOOL))objc_msgSend)(bar, setUsesGlassSel, YES);
    }

    UIView *shadowBox = XHSGlassSafeProp(bar, @"textViewShadowContainer");
    if (shadowBox) {
        if (shadowBox.layer.shadowOpacity != 0) shadowBox.layer.shadowOpacity = 0;
        [self clearBackground:shadowBox];
    }

    UIView *bgBox = XHSGlassSafeProp(bar, @"textViewBackgroundView");
    UIView *inputGlass = XHSGlassSafeProp(bar, @"inputGlassView");
    if (bgBox && bgBox.superview) {
        [self clearBackground:bgBox];
        if (bgBox.layer.borderWidth != 0) bgBox.layer.borderWidth = 0;
        if (!inputGlass && [self isVisible:bgBox]) {
            UIVisualEffectView *sg = [self plateOn:bar key:&kSearchInputGlassKey below:bgBox frame:bgBox.frame bar:kXHSNativeBarHome];
            chatAttachGlassPressReactor(bgBox, sg, @[bgBox]);
        } else {
            ((UIView *)objc_getAssociatedObject(bar, &kSearchInputGlassKey)).hidden = YES;
            if ([inputGlass isKindOfClass:UIVisualEffectView.class]) {
                chatAttachGlassPressReactor(bgBox, (UIVisualEffectView *)inputGlass, @[bgBox]);
            }
        }
    }

    UIImageView *leftIcon = XHSGlassSafeProp(bar, @"leftIconImageView");
    if ([leftIcon isKindOfClass:UIImageView.class]) {
        UIImage *mag = XHSGlassSymbol(@"magnifyingglass", 15.5, UIImageSymbolWeightMedium);
        if (![leftIcon.image isEqual:mag]) {
            leftIcon.image = mag;
            leftIcon.contentMode = UIViewContentModeScaleAspectFit;
        }
        leftIcon.tintColor = UIColor.secondaryLabelColor;
    }

    UIButton *backBtn = XHSGlassSafeProp(bar, @"backButton");
    if ([self isVisible:backBtn] && backBtn.superview) {
        SEL hasGlassBack = NSSelectorFromString(@"hasAppliedGlassBackButton");
        BOOL alreadyGlass = [bar respondsToSelector:hasGlassBack] && ((BOOL (*)(id, SEL))objc_msgSend)(bar, hasGlassBack);
        if (!alreadyGlass) {
            UIImage *chev = XHSGlassSymbol(@"chevron.backward", 17, UIImageSymbolWeightMedium);
            if (backBtn.configuration) {
                if (![backBtn.configuration.image isEqual:chev]) {
                    UIButtonConfiguration *c = [backBtn.configuration copy];
                    c.image = chev;
                    c.baseForegroundColor = UIColor.labelColor;
                    backBtn.configuration = c;
                }
            } else if (![backBtn.currentImage isEqual:chev]) {
                [backBtn setImage:chev forState:UIControlStateNormal];
                backBtn.tintColor = UIColor.labelColor;
            }
            CGRect bf = backBtn.frame;
            CGFloat side = MAX(36, MIN(42, MAX(CGRectGetWidth(bf), CGRectGetHeight(bf))));
            CGRect circle = CGRectMake(CGRectGetMidX(bf) - side / 2, CGRectGetMidY(bf) - side / 2, side, side);
            [self plateOn:bar key:&kSearchBackGlassKey below:backBtn frame:circle bar:kXHSNativeBarHome];
        } else {
            ((UIView *)objc_getAssociatedObject(bar, &kSearchBackGlassKey)).hidden = YES;
        }
    } else {
        ((UIView *)objc_getAssociatedObject(bar, &kSearchBackGlassKey)).hidden = YES;
    }

    UIButton *searchBtn = XHSGlassSafeProp(bar, @"searchButton");
    if ([self isVisible:searchBtn] && searchBtn.superview && CGRectGetWidth(searchBtn.bounds) > 20) {
        UIImage *magBtn = XHSGlassSymbol(@"magnifyingglass", 17, UIImageSymbolWeightMedium);
        if (searchBtn.configuration) {
            if (searchBtn.configuration.title.length || ![searchBtn.configuration.image isEqual:magBtn]) {
                UIButtonConfiguration *c = [searchBtn.configuration copy];
                c.title = nil;
                c.attributedTitle = nil;
                c.image = magBtn;
                c.baseForegroundColor = UIColor.labelColor;
                searchBtn.configuration = c;
            }
        } else {
            if (searchBtn.currentTitle.length) [searchBtn setTitle:@"" forState:UIControlStateNormal];
            if (searchBtn.currentAttributedTitle.length) [searchBtn setAttributedTitle:nil forState:UIControlStateNormal];
            if (![searchBtn.currentImage isEqual:magBtn]) {
                [searchBtn setImage:magBtn forState:UIControlStateNormal];
                searchBtn.tintColor = UIColor.labelColor;
            }
        }
        CGRect sf = searchBtn.frame;
        CGFloat side = MAX(36, MIN(42, MAX(CGRectGetHeight(sf), 38)));
        CGRect circle = CGRectMake(CGRectGetMidX(sf) - side / 2, CGRectGetMidY(sf) - side / 2, side, side);
        [self plateOn:bar key:&kSearchBtnGlassKey below:searchBtn frame:circle bar:kXHSNativeBarHome];
    } else {
        ((UIView *)objc_getAssociatedObject(bar, &kSearchBtnGlassKey)).hidden = YES;
    }
}

#pragma mark - 私聊界面与 iMessage 气泡

static void chatStripNavBarVeils(UIView *view, UIView *skipOverlay, int depth) {
    if (!view || view == skipOverlay || depth > 5) return;
    if ([view isKindOfClass:UIVisualEffectView.class] || [view.layer isKindOfClass:CAGradientLayer.class]) {
        view.hidden = YES;
        view.alpha = 0;
        return;
    }
    if (view.backgroundColor && ![view.backgroundColor isEqual:UIColor.clearColor]) {
        view.backgroundColor = UIColor.clearColor;
    }
    view.opaque = NO;
    view.layer.backgroundColor = nil;
    for (CALayer *l in view.layer.sublayers) {
        if ([l isKindOfClass:CAGradientLayer.class]) l.hidden = YES;
    }
    for (UIView *sub in view.subviews) {
        chatStripNavBarVeils(sub, skipOverlay, depth + 1);
    }
}

+ (void)styleChatEmojiBackground:(UIView *)bgView {
    if (!bgView || ![XHSNativeConfig.shared boolForKey:kXHSNativeGlassChat]) return;
    // 去掉 EmojiBackgroundPreviewView 自带的 innerMaskView 及渐变遮罩层，并确保壁纸铺满至 y=0
    UIView *maskV = XHSGlassSafeProp(bgView, @"innerMaskView");
    if ([maskV isKindOfClass:UIView.class]) {
        maskV.hidden = YES;
        maskV.alpha = 0;
    }
    for (UIView *sub in bgView.subviews) {
        if ([sub.layer isKindOfClass:CAGradientLayer.class] || [sub isKindOfClass:UIVisualEffectView.class]) {
            sub.hidden = YES;
            sub.alpha = 0;
        }
        for (CALayer *l in sub.layer.sublayers) {
            if ([l isKindOfClass:CAGradientLayer.class]) l.hidden = YES;
        }
    }
    if (bgView.superview && CGRectGetHeight(bgView.superview.bounds) > 400 &&
        CGRectGetWidth(bgView.bounds) >= CGRectGetWidth(bgView.superview.bounds) - 10 &&
        CGRectGetMinY(bgView.frame) > 1.0) {
        bgView.frame = bgView.superview.bounds;
    }
}

static UIImageView *chatFindAvatarImageView(UIView *root) {
    if (!root) return nil;
    UIImageView *iv = XHSGlassSafeProp(root, @"iconView");
    if ([iv isKindOfClass:UIImageView.class]) return iv;
    for (UIView *sub in root.subviews) {
        if ([sub isKindOfClass:UIImageView.class] && CGRectGetWidth(sub.bounds) >= 20) return (UIImageView *)sub;
        UIImageView *found = chatFindAvatarImageView(sub);
        if (found) return found;
    }
    return nil;
}

static NSString *chatLabelText(UIView *view) {
    if (!view) return nil;
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *l = (UILabel *)view;
        NSString *t = l.text.length ? l.text : l.attributedText.string;
        return [t stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
    if ([view respondsToSelector:@selector(text)]) {
        id t = ((id (*)(id, SEL))objc_msgSend)(view, @selector(text));
        if ([t isKindOfClass:NSString.class] && [t length]) {
            return [t stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        }
    }
    if ([view respondsToSelector:@selector(attributedText)]) {
        id at = ((id (*)(id, SEL))objc_msgSend)(view, @selector(attributedText));
        if ([at isKindOfClass:NSAttributedString.class] && [at length]) {
            return [[at string] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        }
    }
    return nil;
}

static NSString *chatFirstTextInView(UIView *root) {
    if (!root || root.hidden) return nil;
    NSString *own = chatLabelText(root);
    if (own.length) return own;
    for (UIView *sub in root.subviews) {
        NSString *t = chatFirstTextInView(sub);
        if (t.length) return t;
    }
    return nil;
}

static void chatExtractTitleAndSubtitle(UIView *titleView, NSString **outTitle, NSString **outSub) {
    if (!titleView) return;
    // 优先直接读取 ConversationNavigationTitleView 的具名子视图（titleView / onlineView / chatStatusView）
    UIView *namedTitle = XHSGlassSafeProp(titleView, @"titleView");
    UIView *namedOnline = XHSGlassSafeProp(titleView, @"onlineView");
    UIView *namedStatus = XHSGlassSafeProp(titleView, @"chatStatusView");
    NSString *directTitle = chatFirstTextInView(namedTitle);
    NSString *directSub = chatFirstTextInView(namedOnline);
    if (!directSub.length) directSub = chatFirstTextInView(namedStatus);
    if (directTitle.length) *outTitle = directTitle;
    if (directSub.length && ![directSub isEqualToString:directTitle ?: @""]) *outSub = directSub;
    if ((*outTitle).length && (*outSub).length) return;

    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:titleView];
    while (queue.count) {
        UIView *cur = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (cur.hidden) continue;
        // 注意：titleView 本身可能已被 XHSGlassHideOriginal 设了 layer.opacity = 0，
        // 所以不能对根节点判 alpha <= 0.01，只过滤真正被小红书隐藏的子控件
        if (cur != titleView && cur.alpha <= 0.01) continue;
        NSString *t = chatLabelText(cur);
        if (t.length) {
            CGRect r = [titleView convertRect:cur.bounds fromView:cur];
            CGFloat pt = 14.0;
            if ([cur isKindOfClass:UILabel.class]) pt = ((UILabel *)cur).font.pointSize;
            [items addObject:@{@"text": t, @"y": @(CGRectGetMidY(r)), @"pt": @(pt)}];
        }
        [queue addObjectsFromArray:cur.subviews];
    }
    [items sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        double ya = [a[@"y"] doubleValue], yb = [b[@"y"] doubleValue];
        if (fabs(ya - yb) > 4) return [@(ya) compare:@(yb)];
        return [b[@"pt"] compare:a[@"pt"]];
    }];
    if (!(*outTitle).length && items.count >= 1) *outTitle = items[0][@"text"];
    if (!(*outSub).length) {
        for (NSDictionary *it in items) {
            NSString *t = it[@"text"];
            if (t.length && ![t isEqualToString:*outTitle ?: @""]) {
                *outSub = t;
                break;
            }
        }
    }
}

static void chatCollectButtons(UIView *root, NSMutableArray<UIButton *> *out) {
    if (!root || root.hidden) return;
    UIButton *inner = XHSGlassSafeProp(root, @"innerButton");
    if ([inner isKindOfClass:UIButton.class] && !inner.hidden) {
        [out addObject:inner];
        return;
    }
    if ([root isKindOfClass:UIButton.class]) {
        [out addObject:(UIButton *)root];
        return;
    }
    for (UIView *sub in root.subviews) chatCollectButtons(sub, out);
}

static NSString *chatSymbolForRightButton(UIButton *btn, NSUInteger idx, NSUInteger total) {
    NSString *lbl = btn.accessibilityLabel ?: @"";
    if ([lbl containsString:@"电话"] || [lbl containsString:@"通话"] || [lbl containsString:@"语音"]) return @"phone";
    if ([lbl containsString:@"视频"]) return @"video";
    if ([lbl containsString:@"搜索"]) return @"magnifyingglass";
    if ([lbl containsString:@"邀请"] || [lbl containsString:@"加"]) return @"person.badge.plus";
    if ([lbl containsString:@"分享"]) return @"square.and.arrow.up";
    if ([lbl containsString:@"店铺"] || [lbl containsString:@"商店"]) return @"bag";
    if (idx + 1 == total) return @"ellipsis";
    return @"circle.grid.2x2";
}

+ (void)layoutChatNavBar:(UIView *)bar {
    if (!bar) return;
    XHSNativeVideoState *state = XHSGlassStateForHost(bar);
    BOOL enabled = [XHSNativeConfig.shared boolForKey:kXHSNativeGlassChat];
    if (!enabled) {
        XHSGlassRestoreOriginals(state);
        state.overlayView.hidden = YES;
        return;
    }

    chatStripNavBarVeils(bar, state.overlayView, 0);
    UIView *line = XHSGlassSafeProp(bar, @"bottomLineView");
    if (line && !line.hidden) line.hidden = YES;

    UIView *leftView = XHSGlassSafeProp(bar, @"leftBarItemsView");
    UIView *titleView = XHSGlassSafeProp(bar, @"titleView");
    UIView *rightView = XHSGlassSafeProp(bar, @"rightBarItemsView");
    if (leftView.superview && leftView.superview != bar) {
        chatStripNavBarVeils(leftView.superview, state.overlayView, 0);
    }
    if (!bar.window || CGRectGetWidth(bar.bounds) < 120) {
        state.overlayView.hidden = YES;
        return;
    }

    // 先从原始内容读取头像、标题与在线状态，再隐藏原视图，避免 alpha=0 干扰读取
    NSMutableArray<UIButton *> *leftBtns = [NSMutableArray array];
    NSMutableArray<UIButton *> *rightBtns = [NSMutableArray array];
    chatCollectButtons(leftView, leftBtns);
    chatCollectButtons(rightView, rightBtns);
    [rightBtns sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        CGRect ra = [bar convertRect:a.bounds fromView:a];
        CGRect rb = [bar convertRect:b.bounds fromView:b];
        return [@(CGRectGetMidX(ra)) compare:@(CGRectGetMidX(rb))];
    }];

    UIImageView *srcAvatar = chatFindAvatarImageView(titleView);
    NSString *titleText = nil, *subtitleText = nil;
    chatExtractTitleAndSubtitle(titleView, &titleText, &subtitleText);
    BOOL hasAvatar = (srcAvatar != nil);
    BOOL hasName = (titleText.length > 0);

    if (leftView) XHSGlassHideOriginal(state, leftView);
    if (titleView) XHSGlassHideOriginal(state, titleView);
    if (rightView) XHSGlassHideOriginal(state, rightView);

    XHSNativeVideoOverlayView *overlay = XHSGlassEnsureOverlay(state, 8.0, YES);
    overlay.hidden = NO;
    overlay.alpha = 1;

    state.topLeftSources = leftBtns;
    state.topRightSources = rightBtns;
    state.noteDirectionHost = titleView;

    __weak XHSNativeVideoState *weakState = state;
    if (!state.topLeftPill && leftBtns.count) {
        UIButton *back = XHSGlassMakeTopButton(@"chevron.backward", @"返回", nil, UIColor.labelColor, YES, YES, NO, ^(UIAction *action) {
            (void)action;
            XHSNativeVideoState *s = weakState;
            UIView *src = s.topLeftSources.firstObject;
            if (src) XHSGlassRelayAction(src, nil, nil, NO);
        });
        state.topLeftButtons = @[back];
        state.topLeftPill = XHSGlassMakePill(@[back], kXHSNativeBarHome, 0, YES);
        [overlay.contentView addSubview:state.topLeftPill];
    }

    if (!state.namePill) {
        UIButtonConfiguration *nc = [UIButtonConfiguration plainButtonConfiguration];
        nc.baseForegroundColor = UIColor.labelColor;
        nc.titleLineBreakMode = NSLineBreakByTruncatingTail;
        nc.subtitleLineBreakMode = NSLineBreakByTruncatingTail;
        nc.titlePadding = 1.0;
        nc.contentInsets = NSDirectionalEdgeInsetsMake(0, 48, 0, 14);
        nc.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *incoming) {
            NSMutableDictionary *attrs = [incoming mutableCopy];
            attrs[NSFontAttributeName] = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
            return attrs;
        };
        UIButton *nameBtn = [UIButton buttonWithConfiguration:nc primaryAction:[UIAction actionWithHandler:^(UIAction *action) {
            (void)action;
            XHSNativeVideoState *s = weakState;
            UIView *tv = s.noteDirectionHost;
            if ([tv respondsToSelector:NSSelectorFromString(@"onAvatatClick")]) {
                ((void (*)(id, SEL))objc_msgSend)(tv, NSSelectorFromString(@"onAvatatClick"));
            }
        }]];
        nameBtn.accessibilityLabel = @"主页";
        nameBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
        [nameBtn setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

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
        state.namePill = XHSGlassMakePill(@[nameBtn], kXHSNativeBarHome, 0, YES);
        [state.namePill.contentView addSubview:fallback];
        [state.namePill.contentView addSubview:avatarImg];
        [overlay.contentView addSubview:state.namePill];
    }

    if (rightBtns.count != state.topRightButtons.count) {
        [state.topRightPill removeFromSuperview];
        state.topRightPill = nil;
        state.topRightButtons = @[];
        if (rightBtns.count) {
            NSMutableArray<UIButton *> *rGlassBtns = [NSMutableArray array];
            for (NSUInteger i = 0; i < rightBtns.count; i++) {
                NSString *sym = chatSymbolForRightButton(rightBtns[i], i, rightBtns.count);
                UIButton *b = XHSGlassMakeTopButton(sym, rightBtns[i].accessibilityLabel ?: @"更多", nil, UIColor.labelColor,
                                                    i == 0, i + 1 == rightBtns.count, NO, ^(UIAction *action) {
                    (void)action;
                    XHSNativeVideoState *s = weakState;
                    if (i < s.topRightSources.count) XHSGlassRelayAction(s.topRightSources[i], nil, nil, NO);
                });
                [rGlassBtns addObject:b];
            }
            state.topRightButtons = rGlassBtns;
            state.topRightPill = XHSGlassMakePill(rGlassBtns, kXHSNativeBarHome, 0, YES);
            [overlay.contentView addSubview:state.topRightPill];
        }
    }

    if (hasAvatar) {
        [state.avatarMirror attachSource:srcAvatar target:state.avatarImageView fallback:state.avatarFallbackView];
    }
    state.avatarImageView.hidden = !hasAvatar;
    state.avatarFallbackView.hidden = !hasAvatar || (state.avatarImageView.image != nil);

    if (state.namePill.buttons.count) {
        UIButton *nb = state.namePill.buttons.firstObject;
        NSString *targetTitle = hasName ? titleText : nil;
        NSString *sub = (hasName && subtitleText.length) ? subtitleText : nil;
        BOOL isOnlineNow = sub.length && ([sub containsString:@"当前在线"] || [sub isEqualToString:@"在线"] || [sub containsString:@"正在输入"]);
        CGFloat lead = hasAvatar ? 48.0 : 14.0;
        CGFloat trail = hasName ? 14.0 : 4.0;
        NSInteger onlineTag = isOnlineNow ? 2 : 1;
        if (![nb.configuration.title ?: @"" isEqualToString:targetTitle ?: @""] ||
            ![nb.configuration.subtitle ?: @"" isEqualToString:sub ?: @""] ||
            fabs(nb.configuration.contentInsets.leading - lead) > 0.5 ||
            fabs(nb.configuration.contentInsets.trailing - trail) > 0.5 ||
            nb.tag != onlineTag) {
            UIButtonConfiguration *cfg = [nb.configuration copy];
            cfg.title = targetTitle;
            cfg.subtitle = sub;
            cfg.contentInsets = NSDirectionalEdgeInsetsMake(0, lead, 0, trail);
            UIColor *subColor = isOnlineNow
                ? [UIColor colorWithRed:1.0 green:0.141 blue:0.259 alpha:1.0]
                : UIColor.secondaryLabelColor;
            cfg.subtitleTextAttributesTransformer = ^NSDictionary *(NSDictionary *incoming) {
                NSMutableDictionary *attrs = [incoming mutableCopy];
                attrs[NSFontAttributeName] = [UIFont systemFontOfSize:11.0 weight:isOnlineNow ? UIFontWeightSemibold : UIFontWeightMedium];
                attrs[NSForegroundColorAttributeName] = subColor;
                return attrs;
            };
            nb.configuration = cfg;
            nb.tag = onlineTag;
        }
    }

    CGFloat height = 44;
    CGFloat edge = 16;
    CGFloat spacing = 8;
    UIView *refRow = leftView ?: titleView ?: rightView;
    CGFloat y = CGRectGetHeight(bar.bounds) - height - 6;
    if (refRow && !CGRectIsEmpty(refRow.bounds)) {
        CGRect refInBar = [bar convertRect:refRow.bounds fromView:refRow];
        y = CGRectGetMidY(refInBar) - height / 2;
    }
    y = MIN(MAX(y, 0), MAX(0, CGRectGetHeight(bar.bounds) - height));

    NSMutableArray<UIView *> *pills = [NSMutableArray array];
    CGFloat cursorX = edge;
    if (state.topLeftPill) {
        XHSGlassApplyPillFill(state.topLeftPill);
        state.topLeftPill.hidden = !leftBtns.count;
        if (!state.topLeftPill.hidden) {
            state.topLeftPill.frame = CGRectMake(cursorX, y, height, height);
            state.topLeftPill.contentView.layer.cornerRadius = height / 2;
            [pills addObject:state.topLeftPill];
            cursorX += height + spacing;
        }
    }

    CGRect rightFrame = CGRectZero;
    if (state.topRightPill) {
        XHSGlassApplyPillFill(state.topRightPill);
        CGFloat fitW = ceil([state.topRightPill.contentView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].width);
        CGFloat rw = rightBtns.count == 1 ? MAX(height, fitW) : MAX(80, fitW);
        rightFrame = CGRectMake(CGRectGetWidth(bar.bounds) - edge - rw, y, rw, height);
        state.topRightPill.hidden = NO;
        state.topRightPill.frame = rightFrame;
        state.topRightPill.contentView.layer.cornerRadius = height / 2;
    }

    // Telegram 风格：头像 + 昵称 + 在线状态融合在同一个液态玻璃胶囊内
    CGFloat maxNameRight = CGRectIsEmpty(rightFrame) ? (CGRectGetWidth(bar.bounds) - edge) : (CGRectGetMinX(rightFrame) - spacing);
    CGFloat maxNameW = maxNameRight - cursorX;
    BOOL showProfile = (hasAvatar || hasName) && maxNameW >= height;
    state.namePill.hidden = !showProfile;
    if (showProfile) {
        XHSGlassApplyPillFill(state.namePill);
        CGFloat profileW = height;
        if (hasName) {
            CGFloat fitNameW = ceil([state.namePill.contentView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].width);
            profileW = MIN(MAX(hasAvatar ? 96 : 56, fitNameW), maxNameW);
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

+ (void)styleChatSystemNavItem:(UIViewController *)vc {
    if (!vc || !vc.navigationItem) return;
    static char kChatSysTitleGlassKey;
    BOOL enabled = [XHSNativeConfig.shared boolForKey:kXHSNativeGlassChat];
    UINavigationItem *item = vc.navigationItem;
    if (!enabled) {
        UIView *tv = item.titleView;
        if (tv) ((UIView *)objc_getAssociatedObject(tv, &kChatSysTitleGlassKey)).hidden = YES;
        return;
    }
    UINavigationBarAppearance *app = [UINavigationBarAppearance new];
    [app configureWithTransparentBackground];
    item.standardAppearance = app;
    item.scrollEdgeAppearance = app;
    item.compactAppearance = app;

    SEL setHidesSel = NSSelectorFromString(@"setHidesSharedBackground:");
    NSMutableArray<UIBarButtonItem *> *allItems = [NSMutableArray array];
    if (item.leftBarButtonItems.count) [allItems addObjectsFromArray:item.leftBarButtonItems];
    else if (item.leftBarButtonItem) [allItems addObject:item.leftBarButtonItem];
    if (item.rightBarButtonItems.count) [allItems addObjectsFromArray:item.rightBarButtonItems];
    else if (item.rightBarButtonItem) [allItems addObject:item.rightBarButtonItem];
    for (UIBarButtonItem *bi in allItems) {
        if ([bi respondsToSelector:setHidesSel]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(bi, setHidesSel, NO);
        }
        if (bi.customView) [self clearBackground:bi.customView];
    }

    UIView *tv = item.titleView;
    if ([tv isKindOfClass:UIView.class] && CGRectGetWidth(tv.bounds) >= 60 && CGRectGetHeight(tv.bounds) >= 28) {
        [self clearBackground:tv];
        UIView *first = nil;
        UIVisualEffectView *existing = objc_getAssociatedObject(tv, &kChatSysTitleGlassKey);
        for (UIView *sub in tv.subviews) {
            if (sub == existing) continue;
            first = sub;
            break;
        }
        if (first) {
            CGRect f = CGRectInset(tv.bounds, -10, -2);
            f.size.height = MAX(40, CGRectGetHeight(f));
            f.origin.y = (CGRectGetHeight(tv.bounds) - f.size.height) / 2;
            [self plateOn:tv key:&kChatSysTitleGlassKey below:first frame:f bar:kXHSNativeBarHome];
        }
    }
}

+ (void)styleChatBaseVC:(UIViewController *)vc {
    if (!vc) return;
    BOOL styledCustomBar = NO;
    UIView *activeNavBar = nil;
    id navCtrl = XHSGlassSafeProp(vc, @"naviBarController");
    UIView *navBar = XHSGlassSafeProp(navCtrl, @"navigationBar");
    if ([navBar isKindOfClass:UIView.class] && navBar.window && !navBar.hidden && CGRectGetWidth(navBar.bounds) >= 120) {
        [self layoutChatNavBar:navBar];
        styledCustomBar = YES;
        activeNavBar = navBar;
    }
    if (!styledCustomBar && vc.isViewLoaded) {
        CGFloat vw = CGRectGetWidth(vc.view.bounds);
        for (UIView *sub in vc.view.subviews) {
            if (sub.hidden || sub.alpha <= 0.01 || [sub isKindOfClass:UIScrollView.class]) continue;
            CGRect f = sub.frame;
            if (CGRectGetMinY(f) > 12 || CGRectGetHeight(f) < 40 || CGRectGetHeight(f) > 150 || CGRectGetWidth(f) < vw - 24) continue;
            NSString *clsName = NSStringFromClass(sub.class);
            if ([sub respondsToSelector:NSSelectorFromString(@"leftBarItemsView")] ||
                [clsName containsString:@"NavigationBar"] || [clsName containsString:@"NaviBar"]) {
                [self layoutChatNavBar:sub];
                styledCustomBar = YES;
                activeNavBar = sub;
                break;
            }
        }
    }
    if (!styledCustomBar && vc.navigationController && !vc.navigationController.navigationBarHidden) {
        [self styleChatSystemNavItem:vc];
    }

    UIViewController *shortcutVC = XHSGlassSafeProp(vc, @"shortcutBarViewController");
    if ([shortcutVC isKindOfClass:UIViewController.class]) {
        [self styleChatShortcutBarVC:shortcutVC];
    }

    if (![XHSNativeConfig.shared boolForKey:kXHSNativeGlassChat]) return;
    // 精准隐藏 XYPMChatViewController 在 emoji 壁纸模式下添加的顶部渐变遮罩视图与渐变图层
    UIView *emojiGradView = XHSGlassSafeProp(vc, @"emojiGradientMaskView");
    if (!emojiGradView) {
        @try { emojiGradView = [vc valueForKey:@"_emojiGradientMaskView"]; } @catch (id e) {}
    }
    if ([emojiGradView isKindOfClass:UIView.class]) {
        emojiGradView.hidden = YES;
        emojiGradView.alpha = 0;
    }
    CALayer *emojiGradLayer = XHSGlassSafeProp(vc, @"emojiGradientLayer");
    if (!emojiGradLayer) {
        @try { emojiGradLayer = [vc valueForKey:@"_emojiGradientLayer"]; } @catch (id e) {}
    }
    if ([emojiGradLayer isKindOfClass:CALayer.class]) {
        emojiGradLayer.hidden = YES;
        emojiGradLayer.opacity = 0;
    }

    UIScrollView *table = XHSGlassSafeProp(vc, @"messageTableView");
    if ([table isKindOfClass:UIScrollView.class]) {
        // 让消息列表延伸到透明导航栏下方，配合系统 iOS 26/27 soft 渐进模糊边缘效果，不再被顶部纯色硬切
        static char kChatTableTopPadKey;
        CGFloat navBottom = activeNavBar ? CGRectGetMaxY(activeNavBar.frame) : 0;
        if (navBottom > 40 && table.superview == vc.view) {
            CGRect tf = table.frame;
            if (CGRectGetMinY(tf) > 1.0) {
                CGFloat delta = CGRectGetMinY(tf);
                tf.origin.y = 0;
                tf.size.height += delta;
                table.frame = tf;
                CGFloat prevAdded = [objc_getAssociatedObject(table, &kChatTableTopPadKey) doubleValue];
                if (fabs(prevAdded - delta) > 0.5) {
                    UIEdgeInsets ci = table.contentInset;
                    ci.top += (delta - prevAdded);
                    table.contentInset = ci;
                    UIEdgeInsets si = table.verticalScrollIndicatorInsets;
                    si.top += (delta - prevAdded);
                    table.verticalScrollIndicatorInsets = si;
                    objc_setAssociatedObject(table, &kChatTableTopPadKey, @(delta), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
            }
            [self clearBackground:activeNavBar];
            activeNavBar.opaque = NO;
            for (CALayer *sublayer in activeNavBar.layer.sublayers) {
                if ([sublayer isKindOfClass:CAGradientLayer.class]) sublayer.hidden = YES;
            }
            // 移除之前的顶部毛玻璃条，避免把自定义/emoji 壁纸本身糊成一条突兀的雾带
            static char kChatTopProgBlurKey;
            UIView *oldBarBlur = objc_getAssociatedObject(activeNavBar, &kChatTopProgBlurKey);
            if (oldBarBlur) {
                [oldBarBlur removeFromSuperview];
                objc_setAssociatedObject(activeNavBar, &kChatTopProgBlurKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            UIView *oldVcBlur = objc_getAssociatedObject(vc.view, &kChatTopProgBlurKey);
            if (oldVcBlur) {
                [oldVcBlur removeFromSuperview];
                objc_setAssociatedObject(vc.view, &kChatTopProgBlurKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            // 同时清理 vc.view 顶部可能由 emoji 壁纸或渐变视图（含 layerClass == CAGradientLayer）添加的渐变/模糊遮罩条
            CGFloat vw = CGRectGetWidth(vc.view.bounds);
            for (UIView *sub in vc.view.subviews) {
                if (sub == activeNavBar || sub == table) continue;
                if ([NSStringFromClass(sub.class) containsString:@"EmojiBackground"]) {
                    [self styleChatEmojiBackground:sub];
                    continue;
                }
                CGRect sf = sub.frame;
                if (CGRectGetMinY(sf) <= 100 && CGRectGetMaxY(sf) <= 200 && CGRectGetWidth(sf) >= vw - 24 && CGRectGetHeight(sf) <= 180) {
                    if ([sub isKindOfClass:UIVisualEffectView.class] || [sub.layer isKindOfClass:CAGradientLayer.class]) {
                        sub.hidden = YES;
                        sub.alpha = 0;
                    } else {
                        for (CALayer *l in sub.layer.sublayers) {
                            if ([l isKindOfClass:CAGradientLayer.class]) l.hidden = YES;
                        }
                        for (UIView *child in sub.subviews) {
                            if ([child.layer isKindOfClass:CAGradientLayer.class] || [child isKindOfClass:UIVisualEffectView.class]) {
                                child.hidden = YES;
                                child.alpha = 0;
                            }
                        }
                    }
                }
            }
            // 绑定系统原生 iOS 26 UIScrollEdgeElementContainerInteraction，让顶部渐进模糊严格贴合导航栏高度
            static char kChatTopEdgeInteractionKey;
            if (!objc_getAssociatedObject(activeNavBar, &kChatTopEdgeInteractionKey)) {
                UIScrollEdgeElementContainerInteraction *edgeInteraction = [UIScrollEdgeElementContainerInteraction new];
                edgeInteraction.edge = UIRectEdgeTop;
                edgeInteraction.scrollView = table;
                [activeNavBar addInteraction:edgeInteraction];
                objc_setAssociatedObject(activeNavBar, &kChatTopEdgeInteractionKey, edgeInteraction, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            [vc.view bringSubviewToFront:activeNavBar];
        }
        // 已干掉小红书自己的 _emojiGradientMaskView 后，重新开启系统原生 iOS 26/27 softStyle 顶部渐进模糊
        table.topEdgeEffect.style = UIScrollEdgeEffectStyle.softStyle;
        table.topEdgeEffect.hidden = NO;
    }
    UIView *bottomSafe = XHSGlassSafeProp(vc, @"bottomSafeView");
    if (bottomSafe) [self clearBackground:bottomSafe];
}

static void chatClearOpaqueSubtree(UIView *view, UIView *skipGlass, int depth) {
    if (!view || view == skipGlass || depth > 5) return;
    if ([view isKindOfClass:UIVisualEffectView.class]) return;
    if ([view isKindOfClass:UIImageView.class] || [view isKindOfClass:UILabel.class]) return;
    // 清掉压在玻璃上面的原版实心灰/黑底色与边框，但保留子按钮和输入文字本身
    if (view.backgroundColor && ![view.backgroundColor isEqual:UIColor.clearColor]) {
        view.backgroundColor = UIColor.clearColor;
    }
    if (view.opaque) view.opaque = NO;
    if (view.layer.backgroundColor) view.layer.backgroundColor = nil;
    if (view.layer.borderWidth > 0) view.layer.borderWidth = 0;
    for (UIView *sub in view.subviews) {
        chatClearOpaqueSubtree(sub, skipGlass, depth + 1);
    }
}

static UIVisualEffectView *chatFindExistingGlassView(UIView *root, UIView *skipGlass, int depth) {
    if (!root || root == skipGlass || depth > 4) return nil;
    if ([root isKindOfClass:UIVisualEffectView.class] && !root.hidden && root.alpha > 0.01 &&
        CGRectGetWidth(root.bounds) > 100 && CGRectGetHeight(root.bounds) >= 34) {
        return (UIVisualEffectView *)root;
    }
    for (UIView *sub in root.subviews) {
        UIVisualEffectView *found = chatFindExistingGlassView(sub, skipGlass, depth + 1);
        if (found) return found;
    }
    return nil;
}

static UIView *chatFindShortcutItemView(UIViewController *vc, NSString *clsFragment) {
    for (UIViewController *child in vc.childViewControllers) {
        if ([NSStringFromClass(child.class) containsString:clsFragment] && child.isViewLoaded && !child.view.hidden) {
            return child.view;
        }
    }
    return nil;
}

static void chatHideForeignGlassViews(UIView *root, UIView *keepA, UIView *keepB) {
    if (!root) return;
    // 只清理 vc.view 直接子视图里的外部原生玻璃，绝不深入污染 contentView 子树
    for (UIView *sub in root.subviews) {
        if (sub == keepA || sub == keepB) continue;
        if ([sub isKindOfClass:UIVisualEffectView.class]) {
            sub.hidden = YES;
            sub.alpha = 0;
        }
    }
}

static void chatStripSwapAnimations(UIView *v) {
    if (!v) return;
    [v.layer removeAnimationForKey:@"position"];
    [v.layer removeAnimationForKey:@"bounds"];
    [v.layer removeAnimationForKey:@"bounds.origin"];
    [v.layer removeAnimationForKey:@"bounds.size"];
    [v.layer removeAnimationForKey:@"frame"];
}

static void chatCenterIconInsideItemView(UIView *itemView) {
    if (!itemView) return;
    for (UIView *sub in itemView.subviews) {
        if ([NSStringFromClass(sub.class) containsString:@"ShortcutBarIconView"]) {
            if (!CGRectEqualToRect(sub.frame, itemView.bounds)) sub.frame = itemView.bounds;
            UIImageView *iv = XHSGlassSafeProp(sub, @"iconImageView");
            if ([iv isKindOfClass:UIImageView.class]) {
                if (!CGRectEqualToRect(iv.frame, sub.bounds)) iv.frame = sub.bounds;
                iv.contentMode = UIViewContentModeCenter;
            }
        }
    }
}

static BOOL chatComputeIMessageFramesForVC(UIViewController *vc,
                                           UIView **outRow,
                                           UIView **outMoreV, UIView **outInputV, UIView **outEmotionV, UIView **outAudioV,
                                           CGRect *outPlusRect, CGRect *outCapsuleRect,
                                           CGRect *outInputRect, CGRect *outEmotionRect, CGRect *outAudioRect) {
    if (!vc || !vc.isViewLoaded) return NO;
    UIView *moreV = nil, *inputV = nil, *emotionV = nil, *audioV = nil;
    for (UIViewController *child in vc.childViewControllers) {
        if (!child.isViewLoaded || child.view.hidden) continue;
        NSString *cn = NSStringFromClass(child.class);
        if ([cn containsString:@"ItemMoreViewController"]) moreV = child.view;
        else if ([cn containsString:@"ItemInputViewController"]) inputV = child.view;
        else if ([cn containsString:@"ItemEmotionViewController"]) emotionV = child.view;
        else if ([cn containsString:@"ItemAudioViewController"]) audioV = child.view;
    }
    if (!moreV || !inputV || moreV.superview != inputV.superview || !moreV.superview || !moreV.superview.superview) return NO;
    UIView *row = moreV.superview;
    CGFloat rw = CGRectGetWidth(row.bounds), rh = CGRectGetHeight(row.bounds);
    if (rw < 220 || rh < 36) return NO;

    CGFloat side = 42.0;
    CGFloat edge = 12.0;
    CGFloat gap = 8.0;
    CGFloat midY = rh / 2.0;
    CGFloat pillH = MAX(42.0, MIN(rh - 4.0, MAX(CGRectGetHeight(inputV.frame), 42.0)));
    CGFloat pillY = midY - pillH / 2.0;

    CGRect plusRect = CGRectMake(edge, midY - side / 2.0, side, side);
    CGFloat capsuleX = edge + side + gap;
    CGFloat capsuleW = rw - edge - capsuleX;
    CGRect capsuleRect = CGRectMake(capsuleX, pillY, capsuleW, pillH);

    CGFloat rightCursor = CGRectGetMaxX(capsuleRect) - 8.0;
    CGRect audioRect = CGRectZero, emotionRect = CGRectZero;
    if (audioV && audioV.superview == row && !audioV.hidden) {
        CGFloat aw = 34.0, ah = 36.0;
        audioRect = CGRectMake(rightCursor - aw, midY - ah / 2.0, aw, ah);
        rightCursor -= (aw + 4.0);
    }
    if (emotionV && emotionV.superview == row && !emotionV.hidden) {
        CGFloat ew = 34.0, eh = 36.0;
        emotionRect = CGRectMake(rightCursor - ew, midY - eh / 2.0, ew, eh);
        rightCursor -= (ew + 4.0);
    }
    CGFloat inputX = capsuleX + 12.0;
    CGFloat inputW = MAX(80.0, rightCursor - inputX);
    CGFloat inputH = MAX(36.0, MIN(pillH, CGRectGetHeight(inputV.frame) > 10 ? CGRectGetHeight(inputV.frame) : 38.0));
    CGRect inputRect = CGRectMake(inputX, midY - inputH / 2.0, inputW, inputH);

    if (outRow) *outRow = row;
    if (outMoreV) *outMoreV = moreV;
    if (outInputV) *outInputV = inputV;
    if (outEmotionV) *outEmotionV = emotionV;
    if (outAudioV) *outAudioV = audioV;
    if (outPlusRect) *outPlusRect = plusRect;
    if (outCapsuleRect) *outCapsuleRect = capsuleRect;
    if (outInputRect) *outInputRect = inputRect;
    if (outEmotionRect) *outEmotionRect = emotionRect;
    if (outAudioRect) *outAudioRect = audioRect;
    return YES;
}

+ (void)adjustChatShortcutFlowLayoutAfterPrepare:(id)layout {
    if (!layout || ![XHSNativeConfig.shared boolForKey:kXHSNativeGlassChat]) return;
    UIView *barView = XHSGlassSafeProp(layout, @"shortcutBar") ?: XHSGlassSafeProp(layout, @"internalShortcutBar");
    if (![barView isKindOfClass:UIView.class]) return;
    id cached = XHSGlassSafeProp(layout, @"cachedAttributes");
    if ([cached isKindOfClass:NSDictionary.class]) {
        [(NSDictionary *)cached enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            (void)stop;
            NSIndexPath *ip = [key isKindOfClass:NSIndexPath.class] ? key : XHSGlassSafeProp(obj, @"targetIndex");
            if (ip) [self adjustChatShortcutAttributes:obj forShortcutBarView:barView indexPath:ip];
        }];
    } else if ([cached isKindOfClass:NSArray.class]) {
        for (id obj in (NSArray *)cached) {
            NSIndexPath *ip = XHSGlassSafeProp(obj, @"targetIndex");
            if ([ip isKindOfClass:NSIndexPath.class]) {
                [self adjustChatShortcutAttributes:obj forShortcutBarView:barView indexPath:ip];
            }
        }
    }
}

+ (void)adjustChatShortcutAttributes:(id)attrs forFlowLayout:(id)layout indexPath:(NSIndexPath *)indexPath {
    if (!attrs || !layout || !indexPath || ![XHSNativeConfig.shared boolForKey:kXHSNativeGlassChat]) return;
    UIView *barView = XHSGlassSafeProp(layout, @"shortcutBar") ?: XHSGlassSafeProp(layout, @"internalShortcutBar");
    if ([barView isKindOfClass:UIView.class]) {
        [self adjustChatShortcutAttributes:attrs forShortcutBarView:barView indexPath:indexPath];
    }
}

+ (void)adjustChatShortcutAttributes:(id)attrs forShortcutBarView:(UIView *)barView indexPath:(NSIndexPath *)indexPath {
    if (!attrs || !barView || !indexPath || ![XHSNativeConfig.shared boolForKey:kXHSNativeGlassChat]) return;
    if (![attrs respondsToSelector:@selector(setFrame:)]) return;

    UIViewController *vc = nil;
    for (UIResponder *r = barView.nextResponder; r; r = r.nextResponder) {
        if ([NSStringFromClass(r.class) containsString:@"ShortcutBarLayoutViewController"]) {
            vc = (UIViewController *)r;
            break;
        }
    }
    if (!vc) return;

    // 通过 indexPathItemViewControllerDict 精准识别该 indexPath 对应的 ItemVC，从源头直接返回 iMessage 坐标，
    // 彻底消除小红书原版 FlowLayout 先把按钮算回旧坐标再被重排导致的闪换动画！
    NSDictionary *dict = XHSGlassSafeProp(vc, @"indexPathItemViewControllerDict");
    UIViewController *itemVC = [dict isKindOfClass:NSDictionary.class] ? dict[indexPath] : nil;
    if (![itemVC isKindOfClass:UIViewController.class]) return;

    CGRect plusRect, capsuleRect, inputRect, emotionRect, audioRect;
    if (!chatComputeIMessageFramesForVC(vc, NULL, NULL, NULL, NULL, NULL,
                                        &plusRect, &capsuleRect, &inputRect, &emotionRect, &audioRect)) return;

    NSString *cn = NSStringFromClass(itemVC.class);
    CGRect target = CGRectZero;
    if ([cn containsString:@"ItemMoreViewController"]) target = plusRect;
    else if ([cn containsString:@"ItemInputViewController"]) target = inputRect;
    else if ([cn containsString:@"ItemEmotionViewController"] && !CGRectIsEmpty(emotionRect)) target = emotionRect;
    else if ([cn containsString:@"ItemAudioViewController"] && !CGRectIsEmpty(audioRect)) target = audioRect;
    else return;

    ((void (*)(id, SEL, CGRect))objc_msgSend)(attrs, @selector(setFrame:), target);
}

+ (void)styleChatShortcutBarVC:(UIViewController *)vc {
    static BOOL sInShortcutLayout = NO;
    if (sInShortcutLayout || !vc || !vc.isViewLoaded) return;
    sInShortcutLayout = YES;
    @try {
        static char kChatBarGlassKey, kChatPlusGlassKey;
        UIView *host = XHSGlassSafeProp(vc, @"shortcutBarView") ?: vc.view;
        if (![host isKindOfClass:UIView.class]) return;
        UIVisualEffectView *plate = objc_getAssociatedObject(host, &kChatBarGlassKey);
        UIVisualEffectView *plusPlate = objc_getAssociatedObject(host, &kChatPlusGlassKey);
        if (![XHSNativeConfig.shared boolForKey:kXHSNativeGlassChat]) {
            plate.hidden = YES;
            plusPlate.hidden = YES;
            return;
        }

        // 同步刷新语音/表情/加号的原生 SF Symbols，防止切换语音↔键盘或表情↔键盘后被小红书刷回原版图标
        UIView *moreV = nil, *inputV = nil, *emotionV = nil, *audioV = nil;
        for (UIViewController *child in vc.childViewControllers) {
            if (!child.isViewLoaded || child.view.hidden) continue;
            NSString *cn = NSStringFromClass(child.class);
            if ([cn containsString:@"ItemMoreViewController"]) {
                moreV = child.view;
                [self styleChatShortcutItemVC:child kind:2];
            } else if ([cn containsString:@"ItemInputViewController"]) {
                inputV = child.view;
            } else if ([cn containsString:@"ItemEmotionViewController"]) {
                emotionV = child.view;
                [self styleChatShortcutItemVC:child kind:1];
            } else if ([cn containsString:@"ItemAudioViewController"]) {
                audioV = child.view;
                [self styleChatShortcutItemVC:child kind:0];
            }
        }

        // 按 iOS 26 iMessage 布局重排：左侧独立圆形「+」液态玻璃 + 右侧「发消息… ☺ 🎤」独立液态玻璃胶囊
        if (moreV && inputV && moreV.superview == inputV.superview && moreV.superview != nil && moreV.superview.superview != nil) {
            UIView *row = moreV.superview;
            CGFloat rw = CGRectGetWidth(row.bounds), rh = CGRectGetHeight(row.bounds);
            if (rw >= 220 && rh >= 36) {
                host.clipsToBounds = NO;
                vc.view.clipsToBounds = NO;
                row.clipsToBounds = NO;

                CGFloat side = 42.0;
                CGFloat edge = 12.0;
                CGFloat gap = 8.0;
                CGFloat midY = rh / 2.0;
                CGFloat pillH = MAX(42.0, MIN(rh - 4.0, MAX(CGRectGetHeight(inputV.frame), 42.0)));
                CGFloat pillY = midY - pillH / 2.0;

                [UIView performWithoutAnimation:^{
                    // 1. 左侧独立「+」圆球，并强制把内部 iconView 严格居中
                    CGRect plusRect = CGRectMake(edge, midY - side / 2.0, side, side);
                    if (!CGRectEqualToRect(moreV.frame, plusRect)) moreV.frame = plusRect;
                    chatCenterIconInsideItemView(moreV);

                    // 2. 右侧输入胶囊范围 [capsuleX .. rw - edge]
                    CGFloat capsuleX = edge + side + gap;
                    CGFloat capsuleW = rw - edge - capsuleX;
                    CGRect capsuleRect = CGRectMake(capsuleX, pillY, capsuleW, pillH);

                    // 3. 胶囊内从右往左排：语音(🎤) -> 表情(☺) -> 文本框(发消息…)
                    CGFloat rightCursor = CGRectGetMaxX(capsuleRect) - 8.0;
                    NSMutableArray<UIView *> *capsuleChildren = [NSMutableArray array];
                    if (audioV && audioV.superview == row && !audioV.hidden) {
                        CGFloat aw = 34.0, ah = 36.0;
                        CGRect af = CGRectMake(rightCursor - aw, midY - ah / 2.0, aw, ah);
                        if (!CGRectEqualToRect(audioV.frame, af)) audioV.frame = af;
                        chatCenterIconInsideItemView(audioV);
                        rightCursor -= (aw + 4.0);
                        [capsuleChildren addObject:audioV];
                    }
                    if (emotionV && emotionV.superview == row && !emotionV.hidden) {
                        CGFloat ew = 34.0, eh = 36.0;
                        CGRect ef = CGRectMake(rightCursor - ew, midY - eh / 2.0, ew, eh);
                        if (!CGRectEqualToRect(emotionV.frame, ef)) emotionV.frame = ef;
                        chatCenterIconInsideItemView(emotionV);
                        rightCursor -= (ew + 4.0);
                        [capsuleChildren addObject:emotionV];
                    }
                    CGFloat inputX = capsuleX + 12.0;
                    CGFloat inputW = MAX(80.0, rightCursor - inputX);
                    CGFloat inputH = MAX(36.0, MIN(pillH, CGRectGetHeight(inputV.frame) > 10 ? CGRectGetHeight(inputV.frame) : 38.0));
                    CGRect inf = CGRectMake(inputX, midY - inputH / 2.0, inputW, inputH);
                    if (!CGRectEqualToRect(inputV.frame, inf)) inputV.frame = inf;
                    [capsuleChildren addObject:inputV];

                    // 关键：pGlass 放在 below:row，cGlass 放在 below:pGlass（绝不同时传 below:row，彻底杜绝 insertSubview 乒乓死循环！）
                    UIView *glassContainer = row.superview;
                    CGRect plusInContainer = [glassContainer convertRect:plusRect fromView:row];
                    CGRect capsuleInContainer = [glassContainer convertRect:capsuleRect fromView:row];
                    UIVisualEffectView *pGlass = [self plateOn:host key:&kChatPlusGlassKey below:row frame:plusInContainer bar:kXHSNativeBarComment];
                    UIVisualEffectView *cGlass = [self plateOn:host key:&kChatBarGlassKey below:(pGlass ?: row) frame:capsuleInContainer bar:kXHSNativeBarComment];

                    chatHideForeignGlassViews(vc.view, pGlass, cGlass);
                    chatClearOpaqueSubtree(vc.view, nil, 0);

                    // 清除小红书动画块在旧布局上挂的 position/bounds 交换动画（保留外层栏随键盘上下滑出的动画与我们的点击脉冲）
                    chatStripSwapAnimations(moreV);
                    chatStripSwapAnimations(inputV);
                    chatStripSwapAnimations(emotionV);
                    chatStripSwapAnimations(audioV);
                    chatStripSwapAnimations(pGlass);
                    chatStripSwapAnimations(cGlass);

                    // 独立联动：点「+」缩放「+」圆球与图标；点输入区/表情/语音一起缩放右侧整个胶囊与图标
                    chatAttachGlassPressReactor(moreV, pGlass, @[moreV]);
                    chatAttachGlassPressReactor(inputV, cGlass, capsuleChildren);
                    if (emotionV) chatAttachGlassPressReactor(emotionV, cGlass, capsuleChildren);
                    if (audioV) chatAttachGlassPressReactor(audioV, cGlass, capsuleChildren);
                }];
                return;
            }
        }

        // 兜底：非标准输入栏时复用单一原生玻璃并联动整行缩放
        plusPlate.hidden = YES;
        UIVisualEffectView *nativeGlass = chatFindExistingGlassView(vc.view, plate, 0);
        if (nativeGlass) {
            if (plate) {
                [plate removeFromSuperview];
                objc_setAssociatedObject(host, &kChatBarGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            if (![nativeGlass.effect isKindOfClass:UIGlassEffect.class] || !((UIGlassEffect *)nativeGlass.effect).interactive) {
                UIGlassEffect *interactiveGlass = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
                interactiveGlass.interactive = YES;
                nativeGlass.effect = interactiveGlass;
            }
            host.clipsToBounds = NO;
            vc.view.clipsToBounds = NO;
            chatClearOpaqueSubtree(vc.view, nativeGlass, 0);
            chatAttachGlassPressReactor(host, nativeGlass, @[host]);
            return;
        }
        CGFloat w = CGRectGetWidth(host.bounds), h = CGRectGetHeight(host.bounds);
        if (w < 120 || h < 34) {
            plate.hidden = YES;
            return;
        }
        host.clipsToBounds = NO;
        vc.view.clipsToBounds = NO;
        UIView *firstChild = nil;
        for (UIView *sub in host.subviews) {
            if (sub == plate || sub.hidden || sub.alpha <= 0.01) continue;
            firstChild = sub;
            break;
        }
        if (!firstChild) return;
        CGRect capsule = CGRectMake(12, 4, w - 24, MAX(42, MIN(48, h - 8)));
        UIVisualEffectView *placed = [self plateOn:host key:&kChatBarGlassKey below:firstChild frame:capsule bar:kXHSNativeBarComment];
        if (placed) {
            chatAttachGlassPressReactor(host, placed, @[host]);
        }
        chatClearOpaqueSubtree(vc.view, placed, 0);
    } @finally {
        sInShortcutLayout = NO;
    }
}

+ (void)styleChatInputContainer:(UIView *)container {
    if (!container) return;
    // 清理旧版内层玻璃，避免出现双层边框
    UIView *oldPlate = objc_getAssociatedObject(container, &kChatInputGlassKey);
    if (oldPlate) {
        [oldPlate removeFromSuperview];
        objc_setAssociatedObject(container, &kChatInputGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (![XHSNativeConfig.shared boolForKey:kXHSNativeGlassChat]) return;
    SEL setGlassSel = NSSelectorFromString(@"setGlassAppearance:");
    if ([container respondsToSelector:setGlassSel]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(container, setGlassSel, YES);
    }
    [self clearBackground:container];
    UIView *textView = XHSGlassSafeProp(container, @"inputTextView");
    if (textView) {
        [self clearBackground:textView];
        if (textView.layer.borderWidth != 0) textView.layer.borderWidth = 0;
    }
}

#pragma mark - 原生 SF Symbols 输入栏图标 & iMessage 风格「+」液态玻璃弹出菜单

static char kChatIconVCKey, kChatIconKindKey, kChatOurSymbolImgKey;

static UIImage *chatSymbolImageForItemVC(UIViewController *vc, NSInteger kind) {
    SEL selSelected = NSSelectorFromString(@"iconViewSelected");
    BOOL isSelected = [vc respondsToSelector:selSelected] && ((BOOL (*)(id, SEL))objc_msgSend)(vc, selSelected);
    NSString *sym = nil;
    CGFloat pt = 19.0;
    if (kind == 0) { // 语音
        sym = isSelected ? @"keyboard" : @"waveform";
    } else if (kind == 1) { // 表情
        sym = isSelected ? @"keyboard" : @"face.smiling";
    } else if (kind == 2) { // 加号
        sym = isSelected ? @"xmark" : @"plus";
        pt = isSelected ? 17.5 : 20.0;
    }
    if (!sym.length) return nil;
    UIImage *img = [XHSGlassSymbol(sym, pt, UIImageSymbolWeightMedium) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    if (img) objc_setAssociatedObject(img, &kChatOurSymbolImgKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return img;
}

+ (void)styleChatShortcutItemVC:(UIViewController *)vc kind:(NSInteger)kind {
    if (!vc || ![XHSNativeConfig.shared boolForKey:kXHSNativeGlassChat]) return;
    UIView *iconView = XHSGlassSafeProp(vc, @"iconView");
    UIImageView *iv = XHSGlassSafeProp(iconView, @"iconImageView");
    if (![iv isKindOfClass:UIImageView.class]) return;
    // 用弱引用包装器绑定 iconImageView -> 所属 ItemVC，拦截任意 Swift 内部 reset 路径写回原图
    NSPointerArray *weakBox = objc_getAssociatedObject(iv, &kChatIconVCKey);
    if (!weakBox) {
        weakBox = [NSPointerArray weakObjectsPointerArray];
        [weakBox addPointer:(__bridge void *)vc];
        objc_setAssociatedObject(iv, &kChatIconVCKey, weakBox, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (weakBox.count == 0 || [weakBox pointerAtIndex:0] != (__bridge void *)vc) {
        weakBox.count = 0;
        [weakBox addPointer:(__bridge void *)vc];
    }
    objc_setAssociatedObject(iv, &kChatIconKindKey, @(kind), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIImage *img = chatSymbolImageForItemVC(vc, kind);
    if (img && ![iv.image isEqual:img]) {
        iv.image = img;
    }
    iv.tintColor = UIColor.labelColor;
    iv.contentMode = UIViewContentModeCenter;
}

+ (UIImage *)resolvedChatShortcutImage:(UIImage *)image forImageView:(UIImageView *)imageView {
    if (!imageView) return image;
    // 无锁快速过滤：99.999% 的普通 UIImageView（如首页瀑布流图片）直接 O(1) 跳过，不碰 objc_getAssociatedObject 全局锁
    static Class sIconViewCls = Nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ sIconViewCls = objc_getClass("_TtC14XYMessageUIKit30XYPMMessageShortcutBarIconView"); });
    if (!sIconViewCls || ![imageView.superview isKindOfClass:sIconViewCls]) return image;

    NSPointerArray *weakBox = objc_getAssociatedObject(imageView, &kChatIconVCKey);
    if (!weakBox || weakBox.count == 0) return image;
    if (![XHSNativeConfig.shared boolForKey:kXHSNativeGlassChat]) return image;
    if (image && objc_getAssociatedObject(image, &kChatOurSymbolImgKey)) return image;
    UIViewController *vc = (__bridge UIViewController *)[weakBox pointerAtIndex:0];
    if (!vc) return image;
    NSNumber *kindNum = objc_getAssociatedObject(imageView, &kChatIconKindKey);
    if (!kindNum) return image;
    UIImage *symImg = chatSymbolImageForItemVC(vc, kindNum.integerValue);
    if (symImg) {
        imageView.tintColor = UIColor.labelColor;
        imageView.contentMode = UIViewContentModeCenter;
        return symImg;
    }
    return image;
}

static void chatPlusMenuStyleForTitle(NSString *title, NSString **outSymbol, UIColor **outColor) {
    NSString *t = title ?: @"";
    if ([t containsString:@"相册"] || [t containsString:@"图片"] || [t containsString:@"照片"]) {
        *outSymbol = @"photo.on.rectangle.angled";
        *outColor = [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0];
    } else if ([t containsString:@"拍"] || [t containsString:@"相机"]) {
        *outSymbol = @"camera.fill";
        *outColor = [UIColor colorWithRed:0.35 green:0.34 blue:0.84 alpha:1.0];
    } else if ([t containsString:@"视频"]) {
        *outSymbol = @"video.fill";
        *outColor = [UIColor colorWithRed:0.19 green:0.82 blue:0.35 alpha:1.0];
    } else if ([t containsString:@"通话"] || [t containsString:@"电话"] || [t containsString:@"语音"]) {
        *outSymbol = @"phone.fill";
        *outColor = [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0];
    } else if ([t containsString:@"笔记"]) {
        *outSymbol = @"doc.richtext.fill";
        *outColor = [UIColor colorWithRed:1.0 green:0.141 blue:0.259 alpha:1.0];
    } else if ([t containsString:@"文件"]) {
        *outSymbol = @"folder.fill";
        *outColor = [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0];
    } else if ([t containsString:@"便利贴"] || [t containsString:@"便签"]) {
        *outSymbol = @"note.text";
        *outColor = [UIColor colorWithRed:1.0 green:0.76 blue:0.03 alpha:1.0];
    } else if ([t containsString:@"地图"] || [t containsString:@"位置"] || [t containsString:@"定位"]) {
        *outSymbol = @"map.fill";
        *outColor = [UIColor colorWithRed:0.20 green:0.68 blue:0.90 alpha:1.0];
    } else if ([t containsString:@"打卡"]) {
        *outSymbol = @"checkmark.seal.fill";
        *outColor = [UIColor colorWithRed:1.0 green:0.58 blue:0.0 alpha:1.0];
    } else if ([t containsString:@"投票"]) {
        *outSymbol = @"chart.bar.doc.horizontal.fill";
        *outColor = [UIColor colorWithRed:1.0 green:0.62 blue:0.04 alpha:1.0];
    } else if ([t containsString:@"红包"] || [t containsString:@"礼物"]) {
        *outSymbol = @"gift.fill";
        *outColor = [UIColor colorWithRed:1.0 green:0.23 blue:0.19 alpha:1.0];
    } else if ([t containsString:@"商品"] || [t containsString:@"好物"] || [t containsString:@"店"]) {
        *outSymbol = @"bag.fill";
        *outColor = [UIColor colorWithRed:1.0 green:0.18 blue:0.33 alpha:1.0];
    } else if ([t containsString:@"接龙"] || [t containsString:@"清单"]) {
        *outSymbol = @"list.bullet.clipboard.fill";
        *outColor = [UIColor colorWithRed:0.69 green:0.32 blue:0.87 alpha:1.0];
    } else if ([t containsString:@"名片"] || [t containsString:@"推荐"]) {
        *outSymbol = @"person.crop.rectangle.fill";
        *outColor = [UIColor colorWithRed:0.35 green:0.78 blue:0.98 alpha:1.0];
    } else {
        *outSymbol = @"sparkles";
        *outColor = [UIColor colorWithRed:0.04 green:0.52 blue:1.0 alpha:1.0];
    }
}

+ (BOOL)presentChatIMessagePlusMenuFromVC:(UIViewController *)moreItemVC {
    if (!moreItemVC || ![XHSNativeConfig.shared boolForKey:kXHSNativeGlassChat]) return NO;
    if ([XHSNativeIMessagePlusMenu activeMenu]) {
        [XHSNativeIMessagePlusMenu dismissActiveAnimated:YES];
        return YES;
    }
    id paramInfo = XHSGlassSafeProp(moreItemVC, @"paramInfo");
    id barVM = XHSGlassSafeProp(paramInfo, @"shortcutBarBaseViewModel");
    id moreVM = XHSGlassSafeProp(barVM, @"moreViewModel");
    NSArray *items = XHSGlassSafeProp(moreVM, @"moreItemsData");
    if (![items isKindOfClass:NSArray.class] || !items.count) return NO;

    UIView *anchorView = XHSGlassSafeProp(moreItemVC, @"iconView") ?: moreItemVC.view;
    UIWindow *window = anchorView.window;
    if (!window) return NO;
    CGRect anchorRect = [anchorView convertRect:anchorView.bounds toView:window];

    XHSNativeIMessagePlusMenu *menu = [[XHSNativeIMessagePlusMenu alloc] initWithFrame:window.bounds];
    [menu showInWindow:window anchorRect:anchorRect moreViewModel:moreVM items:items];
    return YES;
}

static BOOL chatIsSelfSendVM(id vm) {
    SEL sel = NSSelectorFromString(@"isSelfSendMessage");
    return vm && [vm respondsToSelector:sel] && ((BOOL (*)(id, SEL))objc_msgSend)(vm, sel);
}

static BOOL chatCellHasCustomSkin(UITableViewCell *cell) {
    SEL sel = NSSelectorFromString(@"isDisplayingMessageBubble");
    return cell && [cell respondsToSelector:sel] && ((BOOL (*)(id, SEL))objc_msgSend)(cell, sel);
}

static NSAttributedString *chatRecolorAttributedText(NSAttributedString *attr, UIColor *fg) {
    if (!attr.length || !fg) return attr;
    NSMutableAttributedString *mutable = [attr mutableCopy];
    [mutable enumerateAttributesInRange:NSMakeRange(0, mutable.length)
                                options:0
                             usingBlock:^(NSDictionary<NSAttributedStringKey, id> *attrs, NSRange range, BOOL *stop) {
        (void)stop;
        if (attrs[NSAttachmentAttributeName]) return;
        [mutable addAttribute:NSForegroundColorAttributeName value:fg range:range];
    }];
    return mutable;
}

+ (NSAttributedString *)attributedText:(NSAttributedString *)text forChatTextCell:(UITableViewCell *)cell viewModel:(id)vm {
    if (![XHSNativeConfig.shared boolForKey:kXHSNativeChatIMessage] || chatCellHasCustomSkin(cell)) return text;
    if (!chatIsSelfSendVM(vm)) return text;
    return chatRecolorAttributedText(text, UIColor.whiteColor);
}

+ (void)applyChatTextCellBubble:(UITableViewCell *)cell viewModel:(id)vm {
    UIView *textView = XHSGlassSafeProp(cell, @"messageTextView");
    if (!textView) return;
    static char kBubbleKey;
    XHSNativeIMessageBubbleView *bubble = objc_getAssociatedObject(textView, &kBubbleKey);

    if (![XHSNativeConfig.shared boolForKey:kXHSNativeChatIMessage] || chatCellHasCustomSkin(cell)) {
        bubble.hidden = YES;
        return;
    }

    if (!bubble) {
        bubble = [[XHSNativeIMessageBubbleView alloc] initWithFrame:textView.bounds];
        bubble.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        bubble.userInteractionEnabled = NO;
        [textView insertSubview:bubble atIndex:0];
        objc_setAssociatedObject(textView, &kBubbleKey, bubble, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (bubble.superview != textView) [textView insertSubview:bubble atIndex:0];
    [textView sendSubviewToBack:bubble];
    bubble.hidden = NO;

    BOOL isSelf = chatIsSelfSendVM(vm);
    bubble.selfSend = isSelf;
    bubble.bubbleColor = isSelf
        ? [UIColor colorWithRed:1.0 green:0.141 blue:0.259 alpha:1.0]
        : [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            return traits.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithRed:0.149 green:0.149 blue:0.161 alpha:1.0]
                : [UIColor colorWithRed:0.914 green:0.914 blue:0.922 alpha:1.0];
        }];
    bubble.frame = textView.bounds;

    textView.backgroundColor = UIColor.clearColor;
    textView.layer.cornerRadius = 0;
    textView.layer.borderWidth = 0;
    textView.clipsToBounds = NO;
    textView.layer.masksToBounds = NO;

    UITextView *innerTV = XHSGlassSafeProp(textView, @"innerTextView");
    if ([innerTV isKindOfClass:UITextView.class]) {
        innerTV.backgroundColor = UIColor.clearColor;
        UIColor *fg = isSelf ? UIColor.whiteColor : UIColor.labelColor;
        innerTV.tintColor = fg;
        if (isSelf && innerTV.attributedText.length) {
            innerTV.attributedText = chatRecolorAttributedText(innerTV.attributedText, UIColor.whiteColor);
        }
    }
}

+ (void)layoutChatTextCellBubble:(UITableViewCell *)cell {
    UIView *textView = XHSGlassSafeProp(cell, @"messageTextView");
    if (!textView) return;
    for (UIView *sub in textView.subviews) {
        if ([sub isKindOfClass:XHSNativeIMessageBubbleView.class]) {
            if (!CGRectEqualToRect(sub.frame, textView.bounds)) sub.frame = textView.bounds;
            [textView sendSubviewToBack:sub];
            break;
        }
    }
}

+ (void)applyChatVoiceCellBubble:(UITableViewCell *)cell viewModel:(id)vm {
    UIView *voiceView = XHSGlassSafeProp(cell, @"contentVoiceView");
    if (!voiceView) return;
    static char kVoiceBubbleKey;
    XHSNativeIMessageBubbleView *bubble = objc_getAssociatedObject(voiceView, &kVoiceBubbleKey);

    if (![XHSNativeConfig.shared boolForKey:kXHSNativeChatIMessage] || chatCellHasCustomSkin(cell)) {
        bubble.hidden = YES;
        return;
    }

    if (!bubble) {
        bubble = [[XHSNativeIMessageBubbleView alloc] initWithFrame:voiceView.bounds];
        bubble.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        bubble.userInteractionEnabled = NO;
        [voiceView insertSubview:bubble atIndex:0];
        objc_setAssociatedObject(voiceView, &kVoiceBubbleKey, bubble, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (bubble.superview != voiceView) [voiceView insertSubview:bubble atIndex:0];
    [voiceView sendSubviewToBack:bubble];
    bubble.hidden = NO;

    BOOL isSelf = chatIsSelfSendVM(vm);
    bubble.selfSend = isSelf;
    bubble.bubbleColor = isSelf
        ? [UIColor colorWithRed:1.0 green:0.141 blue:0.259 alpha:1.0]
        : [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            return traits.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithRed:0.149 green:0.149 blue:0.161 alpha:1.0]
                : [UIColor colorWithRed:0.914 green:0.914 blue:0.922 alpha:1.0];
        }];
    bubble.frame = voiceView.bounds;

    voiceView.backgroundColor = UIColor.clearColor;
    voiceView.layer.cornerRadius = 0;
    voiceView.layer.borderWidth = 0;
    voiceView.clipsToBounds = NO;
    voiceView.layer.masksToBounds = NO;

    UILabel *secLbl = XHSGlassSafeProp(cell, @"secondsLabel");
    if ([secLbl isKindOfClass:UILabel.class]) {
        secLbl.textColor = isSelf ? UIColor.whiteColor : UIColor.labelColor;
    }
}

+ (void)layoutChatVoiceCellBubble:(UITableViewCell *)cell {
    UIView *voiceView = XHSGlassSafeProp(cell, @"contentVoiceView");
    if (!voiceView) return;
    for (UIView *sub in voiceView.subviews) {
        if ([sub isKindOfClass:XHSNativeIMessageBubbleView.class]) {
            if (!CGRectEqualToRect(sub.frame, voiceView.bounds)) sub.frame = voiceView.bounds;
            [voiceView sendSubviewToBack:sub];
            break;
        }
    }
}

#pragma mark - iMessage 风格长按消息液态玻璃上下文菜单

static void chatContextMenuStyleForTitle(NSString *title, NSString **outSym, BOOL *outDestructive) {
    NSString *t = title ?: @"";
    *outDestructive = NO;
    if ([t containsString:@"回复"] || [t containsString:@"引用"]) {
        *outSym = @"arrowshape.turn.up.left";
    } else if ([t containsString:@"复制"]) {
        *outSym = @"doc.on.doc";
    } else if ([t containsString:@"转发"] || [t containsString:@"分享"]) {
        *outSym = @"arrowshape.turn.up.right";
    } else if ([t containsString:@"翻译"]) {
        *outSym = @"character.book.closed";
    } else if ([t containsString:@"便利贴"] || [t containsString:@"便签"]) {
        *outSym = @"note.text";
    } else if ([t containsString:@"顶"] || [t containsString:@"赞"] || [t containsString:@"表态"]) {
        *outSym = @"hand.thumbsup";
    } else if ([t containsString:@"收藏"]) {
        *outSym = @"star";
    } else if ([t containsString:@"多选"] || [t containsString:@"选择"]) {
        *outSym = @"checkmark.circle";
    } else if ([t containsString:@"置顶"]) {
        *outSym = @"pin";
    } else if ([t containsString:@"转文字"] || [t containsString:@"语音"]) {
        *outSym = @"text.bubble";
    } else if ([t containsString:@"听筒"] || [t containsString:@"扬声器"]) {
        *outSym = @"speaker.wave.2";
    } else if ([t containsString:@"撤回"]) {
        *outSym = @"arrow.uturn.backward";
        *outDestructive = YES;
    } else if ([t containsString:@"删除"]) {
        *outSym = @"trash";
        *outDestructive = YES;
    } else if ([t containsString:@"举报"]) {
        *outSym = @"exclamationmark.bubble";
        *outDestructive = YES;
    } else {
        *outSym = @"ellipsis.circle";
    }
}

static char kChatLongPressGlassHostKey;

+ (void)styleChatLongPressMenu:(UIView *)menuView {
    if (!menuView || !menuView.window || ![XHSNativeConfig.shared boolForKey:kXHSNativeGlassChat]) return;
    NSArray *items = XHSGlassSafeProp(menuView, @"items");
    if (![items isKindOfClass:NSArray.class] || !items.count) return;

    // 隐藏小红书原版深黑网格菜单与小三角
    UIView *origContainer = XHSGlassSafeProp(menuView, @"containerView");
    UIView *origCol = XHSGlassSafeProp(menuView, @"collectionView");
    UIView *origOpCol = XHSGlassSafeProp(menuView, @"opinionCollectionView");
    if (origContainer) { origContainer.hidden = YES; origContainer.alpha = 0; }
    if (origCol) { origCol.hidden = YES; origCol.alpha = 0; }
    if (origOpCol) { origOpCol.hidden = YES; origOpCol.alpha = 0; }
    for (UIView *sub in menuView.subviews) {
        if (sub == objc_getAssociatedObject(menuView, &kChatLongPressGlassHostKey)) continue;
        sub.hidden = YES;
        sub.alpha = 0;
    }

    UIView *glassHost = objc_getAssociatedObject(menuView, &kChatLongPressGlassHostKey);
    if (glassHost && glassHost.superview == menuView && (NSUInteger)glassHost.tag == items.count) {
        [menuView bringSubviewToFront:glassHost];
        return;
    }
    [glassHost removeFromSuperview];

    CGFloat menuW = MIN(224.0, CGRectGetWidth(menuView.bounds) - 32.0);
    CGFloat rowH = 44.0;
    CGFloat padV = 6.0;

    // 把破坏性操作（删除/撤回/举报）排在底部，中间加细分隔线（对齐 iOS 26 iMessage）
    NSMutableArray<NSNumber *> *normalIdx = [NSMutableArray array];
    NSMutableArray<NSNumber *> *destructiveIdx = [NSMutableArray array];
    for (NSUInteger i = 0; i < items.count; i++) {
        NSString *t = XHSGlassSafeProp(items[i], @"title");
        NSString *sym = nil;
        BOOL isDest = NO;
        chatContextMenuStyleForTitle(t, &sym, &isDest);
        if (isDest) [destructiveIdx addObject:@(i)];
        else [normalIdx addObject:@(i)];
    }
    BOOL hasSep = (normalIdx.count > 0 && destructiveIdx.count > 0);
    CGFloat sepH = hasSep ? 9.0 : 0.0;
    CGFloat totalH = padV * 2 + (normalIdx.count + destructiveIdx.count) * rowH + sepH;
    CGFloat maxH = MAX(180.0, CGRectGetHeight(menuView.bounds) - menuView.safeAreaInsets.top - menuView.safeAreaInsets.bottom - 120.0);
    CGFloat cardH = MIN(totalH, maxH);

    // 根据被长按的气泡位置智能定位在气泡下方或上方
    UIView *target = XHSGlassSafeProp(menuView, @"targetView");
    CGRect targetRect = (target && target.window)
        ? [target convertRect:target.bounds toView:menuView]
        : CGRectMake(CGRectGetMidX(menuView.bounds) - 40, CGRectGetMidY(menuView.bounds) - 20, 80, 40);

    CGFloat safeTop = menuView.safeAreaInsets.top + 16.0;
    CGFloat safeBottom = CGRectGetHeight(menuView.bounds) - menuView.safeAreaInsets.bottom - 16.0;
    CGFloat cardX;
    if (CGRectGetMidX(targetRect) > CGRectGetWidth(menuView.bounds) * 0.5) {
        cardX = CGRectGetMaxX(targetRect) - menuW;
    } else {
        cardX = CGRectGetMinX(targetRect);
    }
    cardX = MAX(16.0, MIN(CGRectGetWidth(menuView.bounds) - 16.0 - menuW, cardX));

    BOOL placeBelow = (CGRectGetMaxY(targetRect) + 10.0 + cardH <= safeBottom);
    CGFloat cardY = placeBelow
        ? (CGRectGetMaxY(targetRect) + 10.0)
        : MAX(safeTop, CGRectGetMinY(targetRect) - 10.0 - cardH);

    UIView *shadowHost = [[UIView alloc] initWithFrame:CGRectMake(cardX, cardY, menuW, cardH)];
    shadowHost.tag = (NSInteger)items.count;
    shadowHost.backgroundColor = UIColor.clearColor;
    shadowHost.layer.shadowColor = UIColor.blackColor.CGColor;
    shadowHost.layer.shadowOpacity = 0.24;
    shadowHost.layer.shadowRadius = 24.0;
    shadowHost.layer.shadowOffset = CGSizeMake(0, 10);

    UIGlassEffect *glass = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
    glass.interactive = YES;
    UIVisualEffectView *card = [[UIVisualEffectView alloc] initWithEffect:glass];
    card.frame = shadowHost.bounds;
    card.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    card.layer.cornerRadius = 22.0;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.clipsToBounds = YES;
    card.layer.borderWidth = 0.5;
    card.layer.borderColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:1.0 alpha:0.20]
            : [UIColor colorWithWhite:1.0 alpha:0.55];
    }].CGColor;
    [shadowHost addSubview:card];

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:card.contentView.bounds];
    scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    scroll.showsVerticalScrollIndicator = (totalH > cardH + 2);
    scroll.alwaysBounceVertical = (totalH > cardH + 2);
    scroll.contentSize = CGSizeMake(menuW, totalH);
    [card.contentView addSubview:scroll];

    __weak UIView *weakMenu = menuView;
    __weak UICollectionView *weakCol = [origCol isKindOfClass:UICollectionView.class] ? (UICollectionView *)origCol : nil;
    CGFloat cursorY = padV;

    void (^addRow)(NSUInteger, CGFloat) = ^(NSUInteger idx, CGFloat rowY) {
        id item = items[idx];
        NSString *title = XHSGlassSafeProp(item, @"title");
        if (![title isKindOfClass:NSString.class] || !title.length) title = @"操作";
        NSString *sym = nil;
        BOOL isDest = NO;
        chatContextMenuStyleForTitle(title, &sym, &isDest);
        UIColor *fg = isDest ? UIColor.systemRedColor : UIColor.labelColor;

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(6, rowY, menuW - 12, rowH);
        btn.layer.cornerRadius = 13.0;
        btn.layer.cornerCurve = kCACornerCurveContinuous;
        btn.clipsToBounds = YES;

        UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(14, (rowH - 22) / 2.0, 22, 22)];
        iv.image = [XHSGlassSymbol(sym, 16.5, UIImageSymbolWeightMedium) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        iv.tintColor = fg;
        iv.contentMode = UIViewContentModeCenter;
        iv.userInteractionEnabled = NO;
        [btn addSubview:iv];

        UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(46, 0, menuW - 64, rowH)];
        lbl.text = title;
        lbl.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightRegular];
        lbl.textColor = fg;
        lbl.userInteractionEnabled = NO;
        [btn addSubview:lbl];

        [btn addAction:[UIAction actionWithHandler:^(UIAction *action) {
            (void)action;
            btn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.14];
        }] forControlEvents:UIControlEventTouchDown];
        [btn addAction:[UIAction actionWithHandler:^(UIAction *action) {
            (void)action;
            btn.backgroundColor = UIColor.clearColor;
        }] forControlEvents:UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
        [btn addAction:[UIAction actionWithHandler:^(UIAction *action) {
            (void)action;
            btn.backgroundColor = UIColor.clearColor;
            UIView *m = weakMenu;
            UICollectionView *col = weakCol;
            if (m && col && [m respondsToSelector:@selector(collectionView:didSelectItemAtIndexPath:)]) {
                NSIndexPath *ip = [NSIndexPath indexPathForItem:(NSInteger)idx inSection:0];
                ((void (*)(id, SEL, id, id))objc_msgSend)(m, @selector(collectionView:didSelectItemAtIndexPath:), col, ip);
            } else {
                void (^act)(void) = XHSGlassSafeProp(item, @"action");
                if (act) act();
                if (m && [m respondsToSelector:NSSelectorFromString(@"tapAction")]) {
                    ((void (*)(id, SEL))objc_msgSend)(m, NSSelectorFromString(@"tapAction"));
                }
            }
        }] forControlEvents:UIControlEventTouchUpInside];

        [scroll addSubview:btn];
    };

    for (NSNumber *n in normalIdx) {
        addRow(n.unsignedIntegerValue, cursorY);
        cursorY += rowH;
    }
    if (hasSep) {
        UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(14, cursorY + 4.0, menuW - 28, 0.5)];
        sep.backgroundColor = UIColor.separatorColor;
        [scroll addSubview:sep];
        cursorY += sepH;
    }
    for (NSNumber *n in destructiveIdx) {
        addRow(n.unsignedIntegerValue, cursorY);
        cursorY += rowH;
    }

    [menuView addSubview:shadowHost];
    objc_setAssociatedObject(menuView, &kChatLongPressGlassHostKey, shadowHost, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    shadowHost.alpha = 0.0;
    shadowHost.transform = CGAffineTransformMakeScale(0.84, 0.84);
    [UIView animateWithDuration:0.32
                          delay:0
         usingSpringWithDamping:0.78
          initialSpringVelocity:0.6
                        options:UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        shadowHost.alpha = 1.0;
        shadowHost.transform = CGAffineTransformIdentity;
    } completion:nil];
}

+ (UIView *)hitTestChatLongPressMenu:(UIView *)menuView point:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *glassHost = objc_getAssociatedObject(menuView, &kChatLongPressGlassHostKey);
    if (!glassHost || glassHost.hidden || glassHost.alpha <= 0.01) return nil;
    CGPoint local = [glassHost convertPoint:point fromView:menuView];
    if (CGRectContainsPoint(glassHost.bounds, local)) {
        return [glassHost hitTest:local withEvent:event];
    }
    return nil;
}

@end

static __weak XHSNativeIMessagePlusMenu *sActiveChatPlusMenu = nil;

@implementation XHSNativeIMessagePlusMenu

+ (instancetype)activeMenu {
    return sActiveChatPlusMenu;
}

+ (void)dismissActiveAnimated:(BOOL)animated {
    XHSNativeIMessagePlusMenu *menu = sActiveChatPlusMenu;
    if (menu) [menu dismissAnimated:animated completion:nil];
}

- (void)showInWindow:(UIWindow *)window anchorRect:(CGRect)anchorRect moreViewModel:(id)moreVM items:(NSArray *)items {
    if (!window || !items.count) return;
    [XHSNativeIMessagePlusMenu dismissActiveAnimated:NO];
    self.moreViewModel = moreVM;
    self.items = items;
    self.frame = window.bounds;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.backgroundColor = UIColor.clearColor;
    sActiveChatPlusMenu = self;

    UITapGestureRecognizer *bgTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleBackdropTap:)];
    bgTap.cancelsTouchesInView = NO;
    [self addGestureRecognizer:bgTap];

    CGFloat rowH = 52.0;
    CGFloat padV = 10.0;
    CGFloat cardW = MIN(244.0, CGRectGetWidth(window.bounds) - 28.0);
    CGFloat totalContentH = items.count * rowH + padV * 2;
    CGFloat topLimit = window.safeAreaInsets.top + 16.0;
    CGFloat availH = MAX(180.0, CGRectGetMinY(anchorRect) - 12.0 - topLimit);
    CGFloat cardH = MIN(totalContentH, MIN(392.0, availH));

    CGFloat cardX = CGRectGetMidX(anchorRect) - cardW / 2.0;
    cardX = MAX(14.0, MIN(CGRectGetWidth(window.bounds) - 14.0 - cardW, cardX));
    CGFloat cardY = MAX(topLimit, CGRectGetMinY(anchorRect) - 12.0 - cardH);

    UIView *shadowHost = [[UIView alloc] initWithFrame:CGRectMake(cardX, cardY, cardW, cardH)];
    shadowHost.backgroundColor = UIColor.clearColor;
    shadowHost.layer.shadowColor = UIColor.blackColor.CGColor;
    shadowHost.layer.shadowOpacity = 0.24;
    shadowHost.layer.shadowRadius = 26.0;
    shadowHost.layer.shadowOffset = CGSizeMake(0, 10);
    self.shadowHost = shadowHost;
    [self addSubview:shadowHost];

    UIGlassEffect *glass = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
    glass.interactive = YES;
    UIVisualEffectView *card = [[UIVisualEffectView alloc] initWithEffect:glass];
    card.frame = shadowHost.bounds;
    card.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    card.layer.cornerRadius = 26.0;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.clipsToBounds = YES;
    card.layer.borderWidth = 0.5;
    card.layer.borderColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:1.0 alpha:0.20]
            : [UIColor colorWithWhite:1.0 alpha:0.55];
    }].CGColor;
    self.glassCard = card;
    [shadowHost addSubview:card];

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:card.contentView.bounds];
    scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    scroll.showsVerticalScrollIndicator = (totalContentH > cardH + 2);
    scroll.alwaysBounceVertical = (totalContentH > cardH + 2);
    scroll.contentSize = CGSizeMake(cardW, totalContentH);
    [card.contentView addSubview:scroll];

    __weak XHSNativeIMessagePlusMenu *weakSelf = self;
    for (NSUInteger i = 0; i < items.count; i++) {
        id item = items[i];
        NSString *title = XHSGlassSafeProp(item, @"title");
        if (![title isKindOfClass:NSString.class] || !title.length) title = @"更多";
        NSString *sym = nil;
        UIColor *badgeColor = nil;
        chatPlusMenuStyleForTitle(title, &sym, &badgeColor);

        UIButton *rowBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        rowBtn.frame = CGRectMake(6, padV + i * rowH, cardW - 12, rowH);
        rowBtn.layer.cornerRadius = 16.0;
        rowBtn.layer.cornerCurve = kCACornerCurveContinuous;
        rowBtn.clipsToBounds = YES;

        UIView *badge = [[UIView alloc] initWithFrame:CGRectMake(12, (rowH - 34) / 2.0, 34, 34)];
        badge.backgroundColor = badgeColor;
        badge.layer.cornerRadius = 17.0;
        badge.userInteractionEnabled = NO;
        [rowBtn addSubview:badge];

        UIImageView *iv = [[UIImageView alloc] initWithFrame:badge.bounds];
        iv.image = [XHSGlassSymbol(sym, 16.0, UIImageSymbolWeightSemibold) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        iv.tintColor = UIColor.whiteColor;
        iv.contentMode = UIViewContentModeCenter;
        iv.userInteractionEnabled = NO;
        [badge addSubview:iv];

        UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(58, 0, cardW - 80, rowH)];
        lbl.text = title;
        lbl.font = [UIFont systemFontOfSize:16.5 weight:UIFontWeightMedium];
        lbl.textColor = UIColor.labelColor;
        lbl.userInteractionEnabled = NO;
        [rowBtn addSubview:lbl];

        [rowBtn addAction:[UIAction actionWithHandler:^(UIAction *action) {
            (void)action;
            rowBtn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.14];
        }] forControlEvents:UIControlEventTouchDown];
        [rowBtn addAction:[UIAction actionWithHandler:^(UIAction *action) {
            (void)action;
            rowBtn.backgroundColor = UIColor.clearColor;
        }] forControlEvents:UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
        [rowBtn addAction:[UIAction actionWithHandler:^(UIAction *action) {
            (void)action;
            rowBtn.backgroundColor = UIColor.clearColor;
            XHSNativeIMessagePlusMenu *s = weakSelf;
            id vm = s.moreViewModel;
            [s dismissAnimated:YES completion:^{
                if (vm && [vm respondsToSelector:NSSelectorFromString(@"didSelectItem:")]) {
                    ((void (*)(id, SEL, id))objc_msgSend)(vm, NSSelectorFromString(@"didSelectItem:"), item);
                }
            }];
        }] forControlEvents:UIControlEventTouchUpInside];

        [scroll addSubview:rowBtn];
    }

    [window addSubview:self];
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [haptic impactOccurred];

    // 从「+」按钮处弹簧弹出（对齐 iOS 26 iMessage 交互）
    CGFloat anchorX = (CGRectGetMidX(anchorRect) - cardX) / MAX(cardW, 1.0);
    anchorX = MAX(0.12, MIN(0.88, anchorX));
    shadowHost.layer.anchorPoint = CGPointMake(anchorX, 1.0);
    shadowHost.frame = CGRectMake(cardX, cardY, cardW, cardH);
    shadowHost.alpha = 0.0;
    shadowHost.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(0.70, 0.70), CGAffineTransformMakeTranslation(0, 16));

    [UIView animateWithDuration:0.38
                          delay:0
         usingSpringWithDamping:0.74
          initialSpringVelocity:0.65
                        options:UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        shadowHost.alpha = 1.0;
        shadowHost.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)handleBackdropTap:(UITapGestureRecognizer *)tap {
    CGPoint pt = [tap locationInView:self];
    if (!CGRectContainsPoint(self.shadowHost.frame, pt)) {
        [self dismissAnimated:YES completion:nil];
    }
}

- (void)dismissAnimated:(BOOL)animated completion:(void (^)(void))completion {
    if (sActiveChatPlusMenu == self) sActiveChatPlusMenu = nil;
    if (!animated) {
        [self removeFromSuperview];
        if (completion) completion();
        return;
    }
    [UIView animateWithDuration:0.20
                          delay:0
                        options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.shadowHost.alpha = 0.0;
        self.shadowHost.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(0.76, 0.76), CGAffineTransformMakeTranslation(0, 12));
    } completion:^(BOOL finished) {
        (void)finished;
        [self removeFromSuperview];
        if (completion) completion();
    }];
}

@end
