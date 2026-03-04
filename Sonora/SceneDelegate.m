//
//  SceneDelegate.m
//  Sonora
//
//  Created by loser on 22.02.2026.
//

#import "SceneDelegate.h"

#import "AppDelegate.h"
#import "ViewController.h"
#import "SonoraServices.h"
#import "SonoraWidgetBridge.h"

typedef void (^SonoraBootReadyHandler)(void);
static const NSTimeInterval kSonoraBootMinimumDuration = 0.35;

static UIColor *SonoraBootBackgroundColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
        if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return UIColor.blackColor;
        }
        return UIColor.whiteColor;
    }];
}

static UIImage *SonoraAppIconImage(UITraitCollection *traitCollection) {
    UIImage *image = [UIImage imageNamed:@"LaunchIcon"
                                inBundle:NSBundle.mainBundle
           compatibleWithTraitCollection:traitCollection];
    if (image == nil) {
        image = [UIImage imageNamed:@"LaunchIcon"];
    }
    if (image == nil) {
        image = [UIImage imageNamed:@"launch-icon-any"];
    }
    if (image == nil) {
        image = [UIImage systemImageNamed:@"music.note"];
    }
    return image;
}

@interface SonoraBootViewController : UIViewController

@property (nonatomic, copy) SonoraBootReadyHandler readyHandler;
@property (nonatomic, assign) BOOL didStartPreload;
@property (nonatomic, assign) CFTimeInterval bootStartTime;

@end

@implementation SonoraBootViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = SonoraBootBackgroundColor();

    UIImageView *iconView = [[UIImageView alloc] init];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.contentMode = UIViewContentModeScaleAspectFill;
    iconView.image = SonoraAppIconImage(self.traitCollection);
    iconView.layer.cornerRadius = 24.0;
    iconView.layer.masksToBounds = YES;
    [self.view addSubview:iconView];

    [NSLayoutConstraint activateConstraints:@[
        [iconView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [iconView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:124.0],
        [iconView.heightAnchor constraintEqualToConstant:124.0]
    ]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    if (self.didStartPreload) {
        return;
    }
    self.didStartPreload = YES;
    self.bootStartTime = CFAbsoluteTimeGetCurrent();

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            SonoraLibraryManager *library = SonoraLibraryManager.sharedManager;
            NSArray<SonoraTrack *> *tracks = [library reloadTracks];

            SonoraPlaylistStore *playlists = SonoraPlaylistStore.sharedStore;
            [playlists reloadPlaylists];

            SonoraFavoritesStore *favorites = SonoraFavoritesStore.sharedStore;
            [favorites favoriteTrackIDs];
            [favorites favoriteTracksWithLibrary:library];

            if (tracks.count > 0) {
                NSMutableArray<NSString *> *trackIDs = [NSMutableArray arrayWithCapacity:tracks.count];
                for (SonoraTrack *track in tracks) {
                    if (track.identifier.length > 0) {
                        [trackIDs addObject:track.identifier];
                    }
                }
                if (trackIDs.count > 0) {
                    [SonoraTrackAnalyticsStore.sharedStore analyticsByTrackIDForTrackIDs:trackIDs];
                }
            }

            for (SonoraPlaylist *playlist in playlists.playlists) {
                [playlists tracksForPlaylist:playlist library:library];
                [playlists coverForPlaylist:playlist library:library size:CGSizeMake(160.0, 160.0)];
            }

            (void)SonoraPlaybackManager.sharedManager;
            [SonoraWidgetBridge refreshSharedLovelyTracks];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            NSTimeInterval elapsed = CFAbsoluteTimeGetCurrent() - self.bootStartTime;
            NSTimeInterval remaining = MAX(0.0, kSonoraBootMinimumDuration - elapsed);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(remaining * (NSTimeInterval)NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                SonoraBootReadyHandler handler = self.readyHandler;
                self.readyHandler = nil;
                if (handler != nil) {
                    handler();
                }
            });
        });
    });
}

@end

@interface SceneDelegate ()

@property (nonatomic, strong, nullable) NSURL *pendingWidgetURL;
@property (nonatomic, assign) BOOL didFinishBootTransition;

@end

@implementation SceneDelegate

- (void)handleIncomingURL:(NSURL *)url deferIfNeeded:(BOOL)deferIfNeeded {
    if (![url isKindOfClass:NSURL.class]) {
        return;
    }

    if (deferIfNeeded && !self.didFinishBootTransition) {
        self.pendingWidgetURL = url;
        return;
    }

    BOOL handled = [SonoraWidgetBridge handleWidgetDeepLinkURL:url];
    if (handled) {
        self.pendingWidgetURL = nil;
    }
}

- (void)processPendingWidgetURLIfNeeded {
    NSURL *pendingURL = self.pendingWidgetURL;
    self.pendingWidgetURL = nil;
    if (pendingURL == nil) {
        return;
    }

    [self handleIncomingURL:pendingURL deferIfNeeded:NO];
}

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    (void)session;
    UIOpenURLContext *openURLContext = connectionOptions.URLContexts.allObjects.firstObject;
    if ([openURLContext isKindOfClass:UIOpenURLContext.class]) {
        self.pendingWidgetURL = openURLContext.URL;
    }

    if (![scene isKindOfClass:UIWindowScene.class]) {
        return;
    }

    UIWindowScene *windowScene = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    SonoraBootViewController *bootViewController = [[SonoraBootViewController alloc] init];

    __weak typeof(self) weakSelf = self;
    bootViewController.readyHandler = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf.window == nil) {
            return;
        }

        ViewController *mainController = [[ViewController alloc] init];
        [UIView transitionWithView:strongSelf.window
                          duration:0.18
                           options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowAnimatedContent
                        animations:^{
            strongSelf.window.rootViewController = mainController;
        } completion:^(__unused BOOL finished) {
            strongSelf.didFinishBootTransition = YES;
            [strongSelf processPendingWidgetURLIfNeeded];
        }];
    };

    self.window.rootViewController = bootViewController;
    [self.window makeKeyAndVisible];
}

- (void)sceneDidDisconnect:(UIScene *)scene {
    (void)scene;
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
    (void)scene;
}

- (void)sceneWillResignActive:(UIScene *)scene {
    (void)scene;
}

- (void)sceneWillEnterForeground:(UIScene *)scene {
    (void)scene;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * (NSTimeInterval)NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [SonoraWidgetBridge refreshSharedLovelyTracks];
    });
}

- (void)sceneDidEnterBackground:(UIScene *)scene {
    (void)scene;
    [(AppDelegate *)UIApplication.sharedApplication.delegate saveContext];
}

- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts {
    (void)scene;
    UIOpenURLContext *context = URLContexts.allObjects.firstObject;
    if (![context isKindOfClass:UIOpenURLContext.class]) {
        return;
    }

    [self handleIncomingURL:context.URL deferIfNeeded:YES];
}

@end
