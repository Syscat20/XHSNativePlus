//
//  XHSNative
//
//  Copyright (c) 2026 huami. All rights reserved.
//  Channel: @huamidev
//  Created on: 2026/11/24
//
#import "XHSNativeHelper.h"

#define XHS_INTERNAL __attribute__((visibility("hidden")))

typedef NS_ENUM(NSInteger, XHSVideoTopRole) {
    XHSVideoTopRoleBack = 0,
    XHSVideoTopRoleSmallWindow = 1,
    XHSVideoTopRoleSearch = 2,
    XHSVideoTopRoleShare = 3,
    XHSVideoTopRoleNoteFollow = 4,
};

typedef NS_ENUM(NSInteger, XHSGlassItemRole) {
    XHSGlassItemRoleLike = 0,
    XHSGlassItemRoleCollect = 1,
    XHSGlassItemRoleComment = 2,
};

@interface XHSNativeNoteBottomReference : NSObject
@property(nonatomic, weak) UIView *bar;
@end

@interface XHSNativeVideoGlassPill : UIVisualEffectView
@property (nonatomic, copy) NSArray<UIButton *> *buttons;
@property (nonatomic, copy) NSString *barName;
@property (nonatomic, assign) BOOL adaptiveTheme;
@end

@interface XHSNativeVideoOverlayView : UIVisualEffectView
@property (nonatomic, copy) NSArray<UIView *> *interactivePills;
@end

@interface XHSNativeAvatarMirror : NSObject
@property (nonatomic, weak) UIImageView *source;
@property (nonatomic, weak) UIImageView *target;
@property (nonatomic, weak) UIImageView *fallback;
- (void)attachSource:(UIImageView *)source target:(UIImageView *)target fallback:(UIImageView *)fallback;
@end

@interface XHSNativeVideoState : NSObject
@property (nonatomic, weak) UIView *host;
@property (nonatomic, strong) XHSNativeVideoOverlayView *overlayView;
@property (nonatomic, strong) NSMapTable<UIView *, NSArray<NSNumber *> *> *hiddenViews;
// 顶栏状态（视频页 & 笔记页共用）
@property (nonatomic, strong) XHSNativeVideoGlassPill *topLeftPill;
@property (nonatomic, strong) XHSNativeVideoGlassPill *avatarPill;
@property (nonatomic, strong) XHSNativeVideoGlassPill *namePill;
@property (nonatomic, strong) XHSNativeVideoGlassPill *topRightPill;
@property (nonatomic, strong) UIImageView *avatarImageView;
@property (nonatomic, strong) UIImageView *avatarFallbackView;
@property (nonatomic, strong) XHSNativeAvatarMirror *avatarMirror;
@property (nonatomic, weak) UIView *avatarSourceView;
@property (nonatomic, weak) UIView *nameSourceView;
@property (nonatomic, weak) UIView *noteRowView;
@property (nonatomic, copy) NSArray<UIView *> *topLeftSources;
@property (nonatomic, copy) NSArray<UIView *> *topRightSources;
@property (nonatomic, copy) NSArray<NSNumber *> *topLeftRoles;
@property (nonatomic, copy) NSArray<NSNumber *> *topRightRoles;
@property (nonatomic, copy) NSArray<UIButton *> *topLeftButtons;
@property (nonatomic, copy) NSArray<UIButton *> *topRightButtons;
@property (nonatomic, weak) UIView *noteDirectionHost;
// 底栏状态（视频页 & 笔记页共用）
@property (nonatomic, strong) XHSNativeVideoGlassPill *composePill;
@property (nonatomic, strong) XHSNativeVideoGlassPill *engagePill;
@property (nonatomic, strong) UIButton *composeButton;
@property (nonatomic, copy) NSArray<UIButton *> *engageButtons;
@property (nonatomic, copy) NSArray<NSNumber *> *engageRoles;
@property (nonatomic, copy) NSArray<UIView *> *engageRoleViews;
@property (nonatomic, copy) NSArray<UIControl *> *engageControls;
@property (nonatomic, weak) UIView *writeRoleView;
@property (nonatomic, weak) UIControl *writeControl;
@property (nonatomic, weak) UIView *interactionHost;
@property (nonatomic, assign) BOOL compactEngage;
@property (nonatomic, assign) BOOL lastLiked;
@property (nonatomic, assign) BOOL hasLikeOverride;
@property (nonatomic, assign) BOOL likeSelectedOverride;
@property (nonatomic, assign) NSInteger likeCountOverride;
@property (nonatomic, assign) NSInteger retryCount;
@end


XHS_INTERNAL NSHashTable<UIView *> *XHSGlassActiveHosts(void);
XHS_INTERNAL XHSNativeVideoState *XHSGlassExistingState(UIView *host);
XHS_INTERNAL XHSNativeVideoState *XHSGlassStateForHost(UIView *host);
XHS_INTERNAL void XHSGlassClearOurHide(UIView *view);
XHS_INTERNAL BOOL XHSGlassIsItemActive(UIView *view);
XHS_INTERNAL void XHSGlassRestoreOriginals(XHSNativeVideoState *state);
XHS_INTERNAL void XHSGlassHideOriginal(XHSNativeVideoState *state, UIView *view);
XHS_INTERNAL void XHSGlassDisableOriginal(XHSNativeVideoState *state, UIView *view);

XHS_INTERNAL id XHSGlassSafeProp(id object, NSString *selectorName);
XHS_INTERNAL UIControlEvents XHSGlassControlActivation(UIControl *control);
XHS_INTERNAL UIControl *XHSGlassControlIn(UIView *root);
XHS_INTERNAL UIView *XHSGlassControlWithSuffix(UIView *parent, NSString *suffix);
XHS_INTERNAL void XHSGlassRelayAction(UIView *sourceView, id fallbackTarget, SEL fallbackSelector, BOOL sendsArg);

XHS_INTERNAL UIImage *XHSGlassSymbol(NSString *name, CGFloat pointSize, UIImageSymbolWeight weight);
XHS_INTERNAL void XHSGlassApplyPillFill(XHSNativeVideoGlassPill *pill);
XHS_INTERNAL XHSNativeVideoGlassPill *XHSGlassMakePill(NSArray<UIButton *> *buttons, NSString *barName, CGFloat spacing, BOOL adaptiveTheme);
XHS_INTERNAL XHSNativeVideoOverlayView *XHSGlassEnsureOverlay(XHSNativeVideoState *state, CGFloat spacing, BOOL adaptiveTheme);

XHS_INTERNAL NSString *XHSGlassCountText(NSString *text);
XHS_INTERNAL NSString *XHSGlassCountIn(UIView *view);
XHS_INTERNAL NSString *XHSGlassCountNear(UIView *host, UIView *target, UIView *skip);

XHS_INTERNAL void XHSGlassBounceSymbol(UIButton *button);
XHS_INTERNAL UIButton *XHSGlassMakeActionButton(NSString *symbol, NSString *a11yLabel, UIColor *defaultColor, void (^handler)(UIAction *));
XHS_INTERNAL void XHSGlassRefreshBottom(XHSNativeVideoState *state, BOOL adaptiveTheme);
XHS_INTERNAL NSString *XHSGlassSymbolForTopRole(XHSVideoTopRole role);
XHS_INTERNAL NSString *XHSGlassLabelForTopRole(XHSVideoTopRole role);
XHS_INTERNAL UIButton *XHSGlassMakeTopButton(NSString *symbol, NSString *label, NSString *title, UIColor *foreground,
                                             BOOL isFirst, BOOL isLast, BOOL isFollow, void (^handler)(UIAction *));
XHS_INTERNAL void XHSGlassUpdateTopButton(UIButton *button, NSString *symbol, NSString *title, UIColor *foreground,
                                          BOOL isFirst, BOOL isLast, BOOL isFollow);
