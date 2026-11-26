//
//  XHSNative
//
//  Copyright (c) 2026 huami. All rights reserved.
//  Channel: @huamidev
//  Created on: 2026/11/26
//
#import "XHSNativeSave.h"
#import <Photos/Photos.h>
#import <objc/message.h>
#import <objc/runtime.h>

static id field(id object, NSString *key) {
    if (!object) return nil;
    @try { return [object valueForKey:key]; } @catch (NSException *exception) { return nil; }
}

static NSString *string(id value) {
    if ([value isKindOfClass:NSURL.class]) return [value absoluteString];
    return [value isKindOfClass:NSString.class] && [value length] ? value : nil;
}

#pragma mark - 评论

static NSHashTable *comments(void) {
    static NSHashTable *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ table = [NSHashTable weakObjectsHashTable]; });
    return table;
}

static id findComment(NSString *commentId) {
    if (!commentId.length) return nil;
    for (id comment in comments().allObjects)
        if ([string(field(comment, @"commentId")) isEqualToString:commentId]) return comment;
    return nil;
}

#pragma mark - 视频地址

// video_info 是原始视频信息的 JSON，里面按编码分了几路流。挑分辨率最高的，一样高再挑码率高的
static void collectStreams(id node, NSMutableArray<NSDictionary *> *found) {
    if ([node isKindOfClass:NSArray.class]) {
        for (id child in node) collectStreams(child, found);
        return;
    }
    if (![node isKindOfClass:NSDictionary.class]) return;
    NSDictionary *dict = node;
    NSString *url = string(dict[@"master_url"]) ?: string(dict[@"url"]);
    if (!url) {
        NSArray *backups = dict[@"backup_urls"];
        if ([backups isKindOfClass:NSArray.class]) url = string(backups.firstObject);
    }
    if ([url hasPrefix:@"http"]) {
        double pixels = [dict[@"width"] doubleValue] * [dict[@"height"] doubleValue];
        double bitrate = MAX([dict[@"avg_bitrate"] doubleValue], [dict[@"video_bitrate"] doubleValue]);
        [found addObject:@{@"url": url, @"score": @(pixels * 1e4 + bitrate)}];
    }
    for (id child in dict.allValues) collectStreams(child, found);
}

static NSString *bestVideoURL(id info) {
    id json = info;
    if ([info isKindOfClass:NSString.class])
        json = [NSJSONSerialization JSONObjectWithData:[info dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    NSMutableArray<NSDictionary *> *found = [NSMutableArray array];
    collectStreams(json, found);
    NSDictionary *best = nil;
    for (NSDictionary *stream in found)
        if (!best || [stream[@"score"] doubleValue] > [best[@"score"] doubleValue]) best = stream;
    return best[@"url"];
}

#pragma mark - 保存

// 小红书私信模块的媒体保存，自带下载进度和结果提示。它是异步的，保存期间留着
static id mediaHandler(void) {
    static NSMutableArray *alive;
    if (!alive) alive = [NSMutableArray array];
    Class handlerClass = objc_getClass("XYMessageUIKit.MediaMessageHandler");
    id handler = [handlerClass new];
    if (!handler) return nil;
    [alive addObject:handler];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(180 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [alive removeObject:handler]; });
    return handler;
}

static void saveImageData(NSData *data, void (^completion)(BOOL)) {
    void (^finish)(BOOL) = ^(BOOL success) { dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(success); }); };
    [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus status) {
        if (status != PHAuthorizationStatusAuthorized && status != PHAuthorizationStatusLimited) return finish(NO);
        [PHPhotoLibrary.sharedPhotoLibrary performChanges:^{
            [[PHAssetCreationRequest creationRequestForAsset] addResourceWithType:PHAssetResourceTypePhoto data:data options:nil];
        } completionHandler:^(BOOL success, NSError *error) { finish(success); }];
    }];
}

@implementation XHSNativeSave

+ (void)rememberComment:(id)comment {
    if (comment) [comments() addObject:comment];
}

+ (BOOL)saveCommentVideoWithCommentId:(NSString *)commentId index:(NSInteger)index {
    NSArray *videos = field(findComment(commentId), @"commentVideos");
    if (![videos isKindOfClass:NSArray.class] || index < 0 || index >= (NSInteger)videos.count) return NO;
    NSString *url = bestVideoURL(field(videos[index], @"videoInfo"));
    id handler = url ? mediaHandler() : nil;
    SEL save = NSSelectorFromString(@"saveVidioWithUrl:");
    if (![handler respondsToSelector:save]) return NO;
    ((void (*)(id, SEL, id))objc_msgSend)(handler, save, url);
    return YES;
}

+ (BOOL)saveCommentLivePhotoWithCommentId:(NSString *)commentId videoId:(NSString *)videoId imageURL:(NSString *)imageURL {
    NSArray *images = field(findComment(commentId), @"commentImages");
    if (![images isKindOfClass:NSArray.class]) return NO;
    id item = nil;
    for (id image in images)
        if ([string(field(image, @"livePhotoVideoId")) isEqualToString:videoId]) item = image;
    NSString *video = bestVideoURL(field(item, @"livePhotoMediaInfo"));
    NSString *cover = string(field(item, @"originUrl")) ?: string(field(item, @"url")) ?: imageURL;
    id handler = video && cover ? mediaHandler() : nil;
    SEL save = NSSelectorFromString(@"saveLivePhotoWithImageUrl:videoUrl:");
    if (![handler respondsToSelector:save]) return NO;
    ((void (*)(id, SEL, id, id))objc_msgSend)(handler, save, cover, video);
    return YES;
}

// 评论图片原本是下载后画上水印再存成静态图。直接存原图数据；评论里这张有动图地址就存动图
+ (BOOL)saveCommentImageWithURL:(NSString *)url completion:(void (^)(BOOL success))completion {
    NSString *source = url;
    for (id comment in comments().allObjects) {
        NSArray *images = field(comment, @"commentImages");
        if (![images isKindOfClass:NSArray.class]) continue;
        for (id image in images) {
            NSString *plain = string(field(image, @"url")), *origin = string(field(image, @"originUrl"));
            if (![url isEqualToString:plain] && ![url isEqualToString:origin]) continue;
            source = string(field(image, @"animationUrl")) ?: origin ?: url;
        }
    }
    NSURL *link = [NSURL URLWithString:source];
    if (!link) return NO;
    [[NSURLSession.sharedSession dataTaskWithURL:link completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger code = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 200;
        if (!data.length || error || code >= 400) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(NO); });
            return;
        }
        saveImageData(data, completion);
    }] resume];
    return YES;
}

@end
