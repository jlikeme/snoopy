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
#import <SpriteKit/SpriteKit.h>
#define scale 720.0 / 1080.0
#define offside 180.0 / 1080.0
//@import Cocoa;

@interface snoopyView()

@property (nonatomic, strong) AVQueuePlayer *queuePlayer;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@property (nonatomic, strong) SKView *skView;
@property (nonatomic, strong) SKScene *scene;
@property (nonatomic, assign) BOOL test;
@property (nonatomic, assign) int index;
@property (nonatomic, copy) NSArray<NSString *> *videoURLs;
@property (nonatomic, copy) NSArray<NSColor *> *colors;
@property (nonatomic, copy) NSArray<NSString *> *backgroundImages;
//@property (nonatomic, strong) NSTextField *testText;

@end

@implementation snoopyView

- (instancetype)initWithFrame:(NSRect)frame isPreview:(BOOL)isPreview
{
    self = [super initWithFrame:frame isPreview:isPreview];
    if (self) {
        [self setAnimationTimeInterval:1/30.0];
        self.colors = @[[NSColor colorWithRed:50.0/255.0 green:60.0/255.0 blue:47.0/255.0 alpha:1],
                       [NSColor colorWithRed:5.0/255.0 green:168.0/255.0 blue:157.0/255.0 alpha:1],
                       [NSColor colorWithRed:65.0/255.0 green:176.0/255.0 blue:246.0/255.0 alpha:1],
                        [NSColor colorWithRed:238.0/255.0 green:95.0/255.0 blue:167.0/255.0 alpha:1],
                        [NSColor blackColor]];
        [self loadBackgroundImages];
//        self.wantsLayer = YES;
        [self setupPlayer];
//        self.testText = [[NSTextField alloc] initWithFrame:CGRectMake(10, 10, 200, 200)];
//        self.testText.backgroundColor = [NSColor blackColor];
//        self.testText.textColor = [NSColor whiteColor];
//        self.testText.stringValue = @"testtest";
//        [self addSubview:self.testText];
    }
    return self;
}

- (void)loadBackgroundImages {
    NSString *resourcePath = [[NSBundle bundleForClass:[self class]] resourcePath];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    
    NSArray<NSString *> *files = [fileManager contentsOfDirectoryAtPath:resourcePath error:&error];
    if (error) {
        NSLog(@"Error reading Resources directory: %@", error.localizedDescription);
        return;
    }
    
    NSPredicate *heicFilter = [NSPredicate predicateWithFormat:@"self ENDSWITH[c] '.heic'"];
    NSArray<NSString *> *heicFiles = [files filteredArrayUsingPredicate:heicFilter];
    self.backgroundImages = heicFiles;
}

- (NSArray<AVPlayerItem *> *)configPlayerItems {
    NSArray<NSString *> *videoURLs = [Clip randomClipURLs:[Clip loadClips]];
    self.videoURLs = videoURLs;
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
    // create spritekit view to play alpha channel videos
    SKView *skView = [[SKView alloc] initWithFrame:self.bounds];
    skView.wantsLayer = YES;
    skView.layer.backgroundColor = [[NSColor blackColor] CGColor];
    skView.ignoresSiblingOrder = YES;
    skView.allowsTransparency = YES;
    self.skView = skView;
    [self addSubview:self.skView];
    
    SKScene *scene = [[SKScene alloc] initWithSize:self.bounds.size];
    scene.scaleMode = SKSceneScaleModeAspectFill;
    self.scene = scene;
    [self.skView presentScene:self.scene];
    
    SKSpriteNode *solidColorBGNode = [SKSpriteNode spriteNodeWithColor:self.colors[arc4random_uniform(self.colors.count)] size:self.scene.size];
    solidColorBGNode.position = CGPointMake(scene.size.width / 2, scene.size.height / 2);
    solidColorBGNode.zPosition = 0;
    solidColorBGNode.name = @"backgroundColor";
    [self.scene addChild:solidColorBGNode];
    
    NSString *bgImagePath = [[NSBundle bundleForClass:[self class]] pathForResource:@"halftone_pattern" ofType:@"png"];
    NSImage *bgImage = [[NSImage alloc] initWithContentsOfFile:bgImagePath];
    SKTexture *bgtexture = [SKTexture textureWithImage:bgImage];
    SKSpriteNode *backgroundBNode = [SKSpriteNode spriteNodeWithTexture:bgtexture];
    backgroundBNode.position = CGPointMake(scene.size.width / 2, scene.size.height / 2);
    backgroundBNode.size = scene.size;
    backgroundBNode.zPosition = 1;
    backgroundBNode.alpha = 0.1;
    backgroundBNode.name = @"backgroundBImage";
    backgroundBNode.blendMode = SKBlendModeAlpha;
    [self.scene addChild:backgroundBNode];
    
    NSURL *imageURL = [[NSBundle bundleForClass:[self class]] URLForResource:self.backgroundImages[arc4random_uniform(self.backgroundImages.count)] withExtension:nil];
    NSImage *image = [[NSImage alloc] initWithContentsOfURL:imageURL];
    double imageAspect = image.size.height / self.scene.size.height;
    SKTexture *texture = [SKTexture textureWithImage:image];
    SKSpriteNode *backgroundNode = [SKSpriteNode spriteNodeWithTexture:texture];
    backgroundNode.position = CGPointMake(scene.size.width / 2, scene.size.height / 2 - scene.size.height * offside);
    backgroundNode.size = CGSizeMake(image.size.width / imageAspect * scale, self.scene.size.height * scale);
    backgroundNode.zPosition = 2;
    backgroundNode.name = @"backgroundImage";
    backgroundNode.blendMode = SKBlendModeAlpha;
    [self.scene addChild:backgroundNode];
    
    self.queuePlayer = [AVQueuePlayer queuePlayerWithItems:[self configPlayerItems]];
//    AVPlayerLayer *playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.queuePlayer];
    
    SKVideoNode *videoNode = [SKVideoNode videoNodeWithAVPlayer:self.queuePlayer];
    videoNode.position = CGPointMake(scene.size.width / 2, scene.size.height / 2);
    videoNode.size = scene.size;
    videoNode.zPosition = 3;
    [self.scene addChild:videoNode];
    
//    NSTextField *test = [[NSTextField alloc] initWithFrame:CGRectMake(100, 100, 1000, 1000)];
//    test.backgroundColor = [NSColor blackColor];
//    test.textColor = [NSColor whiteColor];
//    test.stringValue = [NSString stringWithFormat:@"%@\n%@\n%f", image, bgImage, scene.size.width];
//    [self addSubview:test];
    
//    playerLayer.frame = self.bounds;
//    [playerLayer setAutoresizingMask:kCALayerWidthSizable | kCALayerHeightSizable];
//    playerLayer.needsDisplayOnBoundsChange = YES;
//    playerLayer.contentsGravity = kCAGravityResizeAspect;
//
//    playerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
//    playerLayer.backgroundColor = CGColorCreateSRGB(0, 0, 0, 1);
//    self.playerLayer = playerLayer;
//    [self.layer addSublayer: self.playerLayer];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playerItemDidReachEnd:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:nil];
    
//    [self.queuePlayer play];
}

- (void)playerItemDidReachEnd:(NSNotification *)notification {
    AVPlayerItem *finishedItem = notification.object;
    
    NSURL *videoURL = [[NSBundle bundleForClass:[self class]] URLForResource:self.videoURLs[self.index] withExtension:nil];
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:videoURL];
    if (finishedItem) {
        [self.queuePlayer insertItem:item afterItem:nil];
    }
    self.index++;
    if (self.index % self.videoURLs.count == 0) {
        self.index = 0;
        // change background color and image
        SKSpriteNode *imageNode = (SKSpriteNode *)[self.scene childNodeWithName:@"backgroundImage"];
        NSURL *imageURL = [[NSBundle bundleForClass:[self class]] URLForResource:self.backgroundImages[arc4random_uniform(self.backgroundImages.count)] withExtension:nil];
        NSImage *image = [[NSImage alloc] initWithContentsOfURL:imageURL];
        double imageAspect = image.size.height / self.scene.size.height;
        imageNode.texture = [SKTexture textureWithImage:image];
        imageNode.position = CGPointMake(self.scene.size.width / 2, self.scene.size.height / 2 - self.scene.size.height * offside);
        imageNode.size = CGSizeMake(image.size.width / imageAspect * scale, self.scene.size.height * scale);
        
        SKSpriteNode *colorNode = (SKSpriteNode *)[self.scene childNodeWithName:@"backgroundColor"];
        colorNode.color = self.colors[arc4random_uniform(self.colors.count)];
        
    }
//    self.testText.stringValue = [NSString stringWithFormat:@"%d, %d", self.index, self.queuePlayer.items.count];
}

//- (void)setFrame:(NSRect)frame {
//    [super setFrame:frame];
//    [self setupPlayer];
//    self.skView.frame = self.bounds;
//    self.scene.size = self.bounds.size;
//    SKVideoNode *videoNode = (SKVideoNode *)[self.scene childNodeWithName:@"video"];
//    videoNode.size = self.scene.size;
//    videoNode.position = CGPointMake(self.scene.size.width / 2, self.scene.size.height / 2);
//    SKSpriteNode *imageNode = (SKSpriteNode *)[self.scene childNodeWithName:@"backgroundImage"];
//    imageNode.position = CGPointMake(self.scene.size.width / 2, self.scene.size.height / 2 - self.scene.size.height * offside);
//    imageNode.size = CGSizeMake(1440.0 / 1080.0 / self.scene.size.height * scale, self.scene.size.height * scale);
//    SKSpriteNode *backgroundBNode = (SKSpriteNode *)[self.scene childNodeWithName:@"backgroundBImage"];
//    backgroundBNode.position = CGPointMake(self.scene.size.width / 2, self.scene.size.height / 2);
//    backgroundBNode.size = self.scene.size;
//}

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
