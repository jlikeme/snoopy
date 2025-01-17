//
//  snoopyView.m
//  snoopy
//
//  Created by dillon on 2025/1/16.
//

#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>
#import "snoopyView.h"
#import "Clip.h"
//@import Cocoa;

@interface snoopyView()

@property (nonatomic, strong) AVQueuePlayer *queuePlayer;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@property (nonatomic, assign) BOOL test;

@end

@implementation snoopyView

- (instancetype)initWithFrame:(NSRect)frame isPreview:(BOOL)isPreview
{
    self = [super initWithFrame:frame isPreview:isPreview];
    if (self) {
        [self setAnimationTimeInterval:1/30.0];
        self.wantsLayer = YES;
        [self setupPlayer];
    }
    return self;
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
//    [self setupPlayer];
}

- (NSArray<AVPlayerItem *> *)configPlayerItems {
    NSArray<NSString *> *videoURLs = [Clip randomClipURLs:[Clip loadClips]];
    NSMutableArray<AVPlayerItem *> *playerItems = [NSMutableArray array];
    
    for (NSString *videoStr in videoURLs) {
        if (videoStr) {
            NSURL *videoURL = [[NSBundle bundleForClass:[self class]] URLForResource:videoStr withExtension:nil];
            AVPlayerItem *item = [AVPlayerItem playerItemWithURL:videoURL];
            [playerItems addObject:item];
        } else {
            NSLog(@"Error: Video file %@ not found!", videoStr);
        }
    }
    return [playerItems copy];
}

- (void)setupPlayer {
    self.queuePlayer = [AVQueuePlayer queuePlayerWithItems:[self configPlayerItems]];
    AVPlayerLayer *playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.queuePlayer];
    
    playerLayer.frame = self.bounds;
    [playerLayer setAutoresizingMask:kCALayerWidthSizable | kCALayerHeightSizable];
    playerLayer.needsDisplayOnBoundsChange = YES;
    playerLayer.contentsGravity = kCAGravityResizeAspect;
    
    playerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    playerLayer.backgroundColor = CGColorCreateSRGB(0, 0, 0, 1);
    self.playerLayer = playerLayer;
    [self.layer addSublayer: self.playerLayer];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playerItemDidReachEnd:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:nil];
}

- (void)playerItemDidReachEnd:(NSNotification *)notification {
    AVPlayerItem *finishedItem = notification.object;
        
    [finishedItem seekToTime:kCMTimeZero completionHandler:nil];
    
//    if ([self.playerItems containsObject:finishedItem]) {
//        [self.queuePlayer insertItem:finishedItem afterItem:nil];
//    }
}

- (void)startAnimation
{
    [super startAnimation];
    [self.queuePlayer play];
}

- (void)stopAnimation
{
    [super stopAnimation];
    [self.queuePlayer pause];
}

- (void)drawRect:(NSRect)rect
{
    [super drawRect:rect];
}

- (void)animateOneFrame
{
    return;
}

- (BOOL)hasConfigureSheet
{
    return NO;
}

- (NSWindow*)configureSheet
{
    return nil;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.queuePlayer pause];
    self.queuePlayer = nil;
}

@end
