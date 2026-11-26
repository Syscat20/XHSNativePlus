//
//  XHSNative
//
//  Copyright (c) 2026 huami. All rights reserved.
//  Channel: @huamidev
//  Created on: 2026/11/24
//
#import <UIKit/UIKit.h>
#import "XHSNativeHeaders.h"

@interface XHSNativeHelper : NSObject

#pragma mark - 视图

// 垫在一组现有控件后面的胶囊形玻璃，控件本身不动。frame 传空矩形表示收起
+ (UIVisualEffectView *)plateOn:(UIView *)owner key:(const void *)key below:(UIView *)below frame:(CGRect)frame bar:(NSString *)bar;
+ (void)clearBackground:(UIView *)view;
+ (BOOL)isVisible:(UIView *)view;
+ (UIView *)subviewOf:(UIView *)view named:(NSString *)className;

#pragma mark - 小红书

// 调用是不是来自小红书主程序（而不是系统框架）
+ (BOOL)isAppAddress:(void *)address;
// 小红书图标库里的图标对象：XYThemeManager.defaultManager.icon.<name>
+ (id)themeGlyph:(NSString *)name;
+ (UIImage *)tabIcon:(NSString *)name selected:(BOOL)selected;

#pragma mark - iOS 27.1 以下

+ (void)patchOlderSystems;

@end

@interface XHSNativeHelper (TabBar)

#pragma mark - 底栏

+ (UITab *)tabNamed:(NSString *)name;
+ (NSArray<NSString *> *)legacyTabNames:(XYTabbarController *)controller;
+ (void)refreshBadge:(UITabBarItem *)item;
+ (BOOL)isItemEnabled:(UITabBarItem *)item;
+ (BOOL)isOurTabBar:(UITabBar *)bar;
+ (void)rebuildTabs;
+ (void)openPublish;
+ (void)openSearch;
+ (void)reselectTab:(UITab *)tab;

#pragma mark - 首页顶栏

+ (BOOL)isPinnedEdgeEffect:(UIScrollEdgeEffect *)effect;
+ (BOOL)hasSoftTopEdge:(UIScrollView *)list;
+ (void)useSoftTopEdge:(UIScrollView *)list;
+ (void)attachHomeBar:(UIScrollView *)list;
+ (void)attachVisibleList;
+ (void)stripBarBackground:(XYMHomeNaviBar *)bar;
+ (void)layoutHomeBar:(XYMHomeNaviBar *)bar;
+ (NSArray *)visibleChannels:(NSArray *)children;
+ (NSUInteger)landingChannel:(NSUInteger)page ofHome:(XYMHomeViewController *)home;
+ (NSString *)leftEntranceType:(NSString *)type;
+ (BOOL)keepsMenuIcon;

#pragma mark - 滚动联动 & 标签页扩展

+ (void)trackScrollView:(UIScrollView *)list;
+ (void)extendTabPage:(UIViewController *)page;

@end

@interface XHSNativeHelper (GlassOverlay)

+ (UIView *)hitTestVideoOverlayIn:(UIView *)host point:(CGPoint)point withEvent:(UIEvent *)event;
+ (BOOL)isVideoOverlayTouch:(UITouch *)touch inHost:(UIView *)host;
+ (void)restoreOverlayHost:(UIView *)host;

@end

@interface XHSNativeHelper (NoteGlass)

+ (void)layoutNotePage:(UIViewController *)page;
+ (void)layoutNoteTop:(UIView *)bar;
+ (void)layoutNoteBottom:(UIView *)bar;
+ (void)recenterAuthorRow:(UIView *)row;
+ (void)refreshNoteTopFromDirection:(UIView *)direction;
+ (void)refreshNoteBottomFromInteraction:(UIView *)interaction;
+ (void)refreshNoteBottomLikeFromInteraction:(UIView *)interaction liked:(BOOL)liked animated:(BOOL)animated;
+ (void)resetNoteItem:(UIView *)item;
+ (void)toggleZoomInBrowser:(UIView *)browser;
+ (void)resetZoom;

@end

@interface XHSNativeHelper (VideoGlass)

+ (void)layoutVideoHead:(UIView *)head;
+ (void)layoutVideoEngage:(UIView *)bar;
+ (void)refreshVideoEngageFromItem:(UIView *)item;
+ (void)refreshVideoLikeFromItem:(UIView *)item selected:(BOOL)selected animated:(BOOL)animated;
+ (void)triggerVideoLikeBounceFromItem:(UIView *)item;
+ (void)refreshVideoEngageFromItemIfNeeded:(UIView *)item;
+ (void)resetVideoItem:(UIView *)item;

@end

@interface XHSNativeHelper (Settings)

#pragma mark - 设置界面

+ (NSString *)entryIdentity;
+ (id)entryOption;
+ (NSArray *)settingsRows;
+ (NSArray *)orderRows;
+ (NSArray *)percentRowsForBar:(NSString *)bar;
+ (NSString *)titleForMode:(NSString *)mode;
+ (UIView *)settingsFooterWithWidth:(CGFloat)width;
+ (void)handleTap:(NSString *)identity onPage:(XHSNativeSettingsPage *)page;
+ (void)handleSwitch:(NSString *)identity on:(BOOL)on;
+ (void)applySettings;

@end

@interface XHSNativeHelper (ChatGlass)

#pragma mark - 消息 / 搜索 / 私聊

+ (void)beginCapturingMessageSearchForVC:(UIViewController *)vc;
+ (BOOL)isCapturingMessageSearch;
+ (void)captureMessageSearchTapBlock:(id)block gesture:(id)gesture;
+ (void)endCapturingMessageSearch;
+ (void)upgradeMessageCenterBar:(UIViewController *)vc;

+ (BOOL)isSuppressingPopMenu;
+ (void)capturePopMenuItem:(id)item;
+ (UISwipeActionsConfiguration *)iconSwipeActionsFromConfiguration:(UISwipeActionsConfiguration *)config;

+ (void)styleSearchBarV2:(UIView *)bar;

+ (void)layoutChatNavBar:(UIView *)bar;
+ (void)styleChatEmojiBackground:(UIView *)bgView;
+ (void)styleChatBaseVC:(UIViewController *)vc;
+ (void)styleChatShortcutBarVC:(UIViewController *)vc;
+ (void)adjustChatShortcutFlowLayoutAfterPrepare:(id)layout;
+ (void)adjustChatShortcutAttributes:(id)attrs forFlowLayout:(id)layout indexPath:(NSIndexPath *)indexPath;
+ (void)adjustChatShortcutAttributes:(id)attrs forShortcutBarView:(UIView *)barView indexPath:(NSIndexPath *)indexPath;
+ (void)styleChatInputContainer:(UIView *)container;
+ (void)styleChatShortcutItemVC:(UIViewController *)vc kind:(NSInteger)kind;
+ (UIImage *)resolvedChatShortcutImage:(UIImage *)image forImageView:(UIImageView *)imageView;
+ (BOOL)presentChatIMessagePlusMenuFromVC:(UIViewController *)moreItemVC;
+ (void)styleChatLongPressMenu:(UIView *)menuView;
+ (UIView *)hitTestChatLongPressMenu:(UIView *)menuView point:(CGPoint)point withEvent:(UIEvent *)event;
+ (NSAttributedString *)attributedText:(NSAttributedString *)text forChatTextCell:(UITableViewCell *)cell viewModel:(id)vm;
+ (void)applyChatTextCellBubble:(UITableViewCell *)cell viewModel:(id)vm;
+ (void)layoutChatTextCellBubble:(UITableViewCell *)cell;
+ (void)applyChatVoiceCellBubble:(UITableViewCell *)cell viewModel:(id)vm;
+ (void)layoutChatVoiceCellBubble:(UITableViewCell *)cell;

@end
