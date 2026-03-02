//
//  ViewController.m
//  M2
//
//  Created by loser on 22.02.2026.
//

#import "ViewController.h"

#import <math.h>

#import "M2CollectionsViewController.h"
#import "M2HomeViewController.h"
#import "M2MusicModule.h"
#import "M2Services.h"

static UIColor *M2AccentYellowColor(void) {
    return [UIColor colorWithRed:1.0 green:0.83 blue:0.08 alpha:1.0];
}

static UIColor *M2TabActiveIconColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
        if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return UIColor.whiteColor;
        }
        return [UIColor colorWithWhite:0.08 alpha:1.0];
    }];
}

static UIColor *M2TabInactiveIconColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
        if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return [UIColor colorWithWhite:1.0 alpha:0.36];
        }
        return [UIColor colorWithWhite:0.0 alpha:0.34];
    }];
}

static UIColor *M2TabBarBackgroundColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
        if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return [UIColor colorWithWhite:0.02 alpha:1.0];
        }
        return [UIColor colorWithWhite:0.985 alpha:1.0];
    }];
}

static UIColor *M2MiniPlayerBackgroundColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
        if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return [UIColor colorWithWhite:0.0 alpha:0.30];
        }
        return [UIColor colorWithWhite:1.0 alpha:0.32];
    }];
}

static UIColor *M2MiniPlayerBorderColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
        if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return [UIColor colorWithWhite:1.0 alpha:0.14];
        }
        return [UIColor colorWithWhite:0.0 alpha:0.10];
    }];
}

@interface ViewController () <UITabBarControllerDelegate, UINavigationControllerDelegate>

@property (nonatomic, strong) UIView *miniPlayerContainer;
@property (nonatomic, strong) UIVisualEffectView *miniPlayerBlurView;
@property (nonatomic, strong) UIImageView *miniPlayerArtworkView;
@property (nonatomic, strong) UILabel *miniPlayerTitleLabel;
@property (nonatomic, strong) UILabel *miniPlayerSubtitleLabel;
@property (nonatomic, strong) UIButton *miniPlayerOpenButton;
@property (nonatomic, strong) UIButton *miniPlayerPreviousButton;
@property (nonatomic, strong) UIButton *miniPlayerPlayPauseButton;
@property (nonatomic, strong) UIButton *miniPlayerNextButton;
@property (nonatomic, strong) NSLayoutConstraint *miniPlayerBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *miniPlayerTitleTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *miniPlayerTitleCenterYConstraint;
@property (nonatomic, assign) BOOL miniPlayerTransitionAnimating;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.delegate = self;
    [self setupTabs];
    [self setupAppearance];
    [self setupMiniPlayer];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handlePlaybackStateChanged)
                                               name:M2PlaybackStateDidChangeNotification
                                             object:nil];

    [self updateMiniPlayer];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateMiniPlayerPosition];
    [self updateMiniPlayer];
}

- (void)setupTabs {
    M2MusicViewController *musicVC = [[M2MusicViewController alloc] init];
    UINavigationController *musicNav = [[UINavigationController alloc] initWithRootViewController:musicVC];
    musicNav.delegate = self;
    musicNav.navigationBar.prefersLargeTitles = NO;
    UIImage *musicIcon = [self tabSymbolIconNamed:@"magnifyingglass" pointSize:18.0];
    musicNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:nil image:musicIcon selectedImage:musicIcon];
    musicNav.tabBarItem.imageInsets = UIEdgeInsetsMake(2.0, 0.0, -2.0, 0.0);

    M2HomeViewController *homeVC = [[M2HomeViewController alloc] init];
    UINavigationController *homeNav = [[UINavigationController alloc] initWithRootViewController:homeVC];
    homeNav.delegate = self;
    homeNav.navigationBar.prefersLargeTitles = NO;
    UIImage *homeIcon = [self tabSymbolIconNamed:@"house.fill" pointSize:19.5];
    homeNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:nil image:homeIcon selectedImage:homeIcon];
    homeNav.tabBarItem.imageInsets = UIEdgeInsetsMake(2.0, 0.0, -2.0, 0.0);

    M2CollectionsViewController *collectionsVC = [[M2CollectionsViewController alloc] init];
    UINavigationController *collectionsNav = [[UINavigationController alloc] initWithRootViewController:collectionsVC];
    collectionsNav.delegate = self;
    collectionsNav.navigationBar.prefersLargeTitles = NO;
    UIImage *collectionsIcon = [self tabIconNamed:@"tab_lib"];
    collectionsNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:nil image:collectionsIcon selectedImage:collectionsIcon];
    collectionsNav.tabBarItem.imageInsets = UIEdgeInsetsMake(2.0, 0.0, -2.0, 0.0);

    self.viewControllers = @[musicNav, homeNav, collectionsNav];
    self.selectedIndex = 1;
}

- (void)setupAppearance {
    UITabBarAppearance *tabAppearance = [[UITabBarAppearance alloc] init];
    [tabAppearance configureWithOpaqueBackground];
    tabAppearance.backgroundEffect = nil;
    tabAppearance.backgroundColor = M2TabBarBackgroundColor();
    tabAppearance.shadowColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
        if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return [UIColor colorWithWhite:1.0 alpha:0.07];
        }
        return [UIColor colorWithWhite:0.0 alpha:0.08];
    }];

    UIColor *inactiveColor = M2TabInactiveIconColor();
    UIColor *activeColor = M2TabActiveIconColor();

    UITabBarItemAppearance *stacked = tabAppearance.stackedLayoutAppearance;
    stacked.normal.iconColor = inactiveColor;
    stacked.selected.iconColor = activeColor;
    stacked.normal.titleTextAttributes = @{NSForegroundColorAttributeName: UIColor.clearColor};
    stacked.selected.titleTextAttributes = @{NSForegroundColorAttributeName: UIColor.clearColor};
    stacked.normal.titlePositionAdjustment = UIOffsetMake(0.0, 14.0);
    stacked.selected.titlePositionAdjustment = UIOffsetMake(0.0, 14.0);

    self.tabBar.standardAppearance = tabAppearance;
    if (@available(iOS 15.0, *)) {
        self.tabBar.scrollEdgeAppearance = tabAppearance;
    }
    self.tabBar.itemPositioning = UITabBarItemPositioningCentered;
    self.tabBar.tintColor = activeColor;
    self.tabBar.unselectedItemTintColor = inactiveColor;

    UINavigationBarAppearance *navAppearance = [[UINavigationBarAppearance alloc] init];
    [navAppearance configureWithDefaultBackground];
    navAppearance.backgroundColor = UIColor.systemBackgroundColor;
    navAppearance.titleTextAttributes = @{
        NSForegroundColorAttributeName: UIColor.labelColor,
        NSFontAttributeName: [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold]
    };
    navAppearance.largeTitleTextAttributes = @{
        NSForegroundColorAttributeName: UIColor.labelColor,
        NSFontAttributeName: [UIFont systemFontOfSize:30.0 weight:UIFontWeightBold]
    };

    UIBarButtonItemAppearance *barButtonAppearance = [[UIBarButtonItemAppearance alloc] init];
    barButtonAppearance.normal.titleTextAttributes = @{
        NSForegroundColorAttributeName: UIColor.labelColor
    };
    barButtonAppearance.highlighted.titleTextAttributes = @{
        NSForegroundColorAttributeName: UIColor.secondaryLabelColor
    };
    navAppearance.buttonAppearance = barButtonAppearance;
    navAppearance.doneButtonAppearance = barButtonAppearance;
    UIBarButtonItemAppearance *backButtonAppearance = [[UIBarButtonItemAppearance alloc] init];
    backButtonAppearance.normal.titleTextAttributes = @{
        NSForegroundColorAttributeName: UIColor.clearColor
    };
    backButtonAppearance.highlighted.titleTextAttributes = @{
        NSForegroundColorAttributeName: UIColor.clearColor
    };
    backButtonAppearance.normal.titlePositionAdjustment = UIOffsetMake(-1000.0, 0.0);
    backButtonAppearance.highlighted.titlePositionAdjustment = UIOffsetMake(-1000.0, 0.0);
    navAppearance.backButtonAppearance = backButtonAppearance;

    UIImageSymbolConfiguration *backConfig = [UIImageSymbolConfiguration configurationWithPointSize:20.0
                                                                                             weight:UIImageSymbolWeightSemibold];
    UIImage *backImage = [UIImage systemImageNamed:@"chevron.backward" withConfiguration:backConfig];
    if (backImage != nil) {
        [navAppearance setBackIndicatorImage:backImage transitionMaskImage:backImage];
    }

    UINavigationBar.appearance.standardAppearance = navAppearance;
    UINavigationBar.appearance.compactAppearance = navAppearance;
    if (@available(iOS 15.0, *)) {
        UINavigationBar.appearance.scrollEdgeAppearance = navAppearance;
    }
    UINavigationBar.appearance.tintColor = UIColor.labelColor;

    self.view.tintColor = M2AccentYellowColor();
}

- (void)setupMiniPlayer {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    container.backgroundColor = M2MiniPlayerBackgroundColor();
    container.layer.borderWidth = 1.0;
    container.layer.borderColor = M2MiniPlayerBorderColor().CGColor;
    container.layer.cornerRadius = 16.0;
    container.layer.masksToBounds = YES;
    container.hidden = YES;
    self.miniPlayerContainer = container;

    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    blurView.translatesAutoresizingMaskIntoConstraints = NO;
    blurView.userInteractionEnabled = NO;
    blurView.alpha = 0.90;
    self.miniPlayerBlurView = blurView;

    UIImageView *artworkView = [[UIImageView alloc] init];
    artworkView.translatesAutoresizingMaskIntoConstraints = NO;
    artworkView.contentMode = UIViewContentModeScaleAspectFill;
    artworkView.layer.cornerRadius = 8.0;
    artworkView.layer.masksToBounds = YES;
    artworkView.userInteractionEnabled = NO;
    self.miniPlayerArtworkView = artworkView;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightSemibold];
    titleLabel.textColor = UIColor.labelColor;
    titleLabel.numberOfLines = 1;
    titleLabel.userInteractionEnabled = NO;
    self.miniPlayerTitleLabel = titleLabel;

    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    subtitleLabel.textColor = UIColor.secondaryLabelColor;
    subtitleLabel.numberOfLines = 1;
    subtitleLabel.userInteractionEnabled = NO;
    self.miniPlayerSubtitleLabel = subtitleLabel;

    UIButton *previousButton = [UIButton buttonWithType:UIButtonTypeSystem];
    previousButton.translatesAutoresizingMaskIntoConstraints = NO;
    previousButton.tintColor = UIColor.labelColor;
    UIImageSymbolConfiguration *previousConfig = [UIImageSymbolConfiguration configurationWithPointSize:15.0
                                                                                                 weight:UIImageSymbolWeightSemibold];
    [previousButton setImage:[UIImage systemImageNamed:@"backward.fill" withConfiguration:previousConfig]
                    forState:UIControlStateNormal];
    [previousButton addTarget:self action:@selector(miniPlayerPreviousTapped) forControlEvents:UIControlEventTouchUpInside];
    self.miniPlayerPreviousButton = previousButton;

    UIButton *playPauseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    playPauseButton.translatesAutoresizingMaskIntoConstraints = NO;
    playPauseButton.tintColor = UIColor.labelColor;
    [playPauseButton addTarget:self action:@selector(miniPlayerPlayPauseTapped) forControlEvents:UIControlEventTouchUpInside];
    self.miniPlayerPlayPauseButton = playPauseButton;

    UIButton *nextButton = [UIButton buttonWithType:UIButtonTypeSystem];
    nextButton.translatesAutoresizingMaskIntoConstraints = NO;
    nextButton.tintColor = UIColor.labelColor;
    UIImageSymbolConfiguration *nextConfig = [UIImageSymbolConfiguration configurationWithPointSize:15.0
                                                                                             weight:UIImageSymbolWeightSemibold];
    [nextButton setImage:[UIImage systemImageNamed:@"forward.fill" withConfiguration:nextConfig]
                forState:UIControlStateNormal];
    [nextButton addTarget:self action:@selector(miniPlayerNextTapped) forControlEvents:UIControlEventTouchUpInside];
    self.miniPlayerNextButton = nextButton;

    UIButton *openButton = [UIButton buttonWithType:UIButtonTypeCustom];
    openButton.translatesAutoresizingMaskIntoConstraints = NO;
    [openButton addTarget:self action:@selector(miniPlayerOpenTapped) forControlEvents:UIControlEventTouchUpInside];
    self.miniPlayerOpenButton = openButton;

    UIPanGestureRecognizer *horizontalPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleMiniPlayerHorizontalPan:)];
    horizontalPan.cancelsTouchesInView = NO;
    [container addGestureRecognizer:horizontalPan];

    [self.view addSubview:container];
    [container addSubview:blurView];
    [container addSubview:openButton];
    [container addSubview:artworkView];
    [container addSubview:titleLabel];
    [container addSubview:subtitleLabel];
    [container addSubview:previousButton];
    [container addSubview:playPauseButton];
    [container addSubview:nextButton];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    NSLayoutConstraint *bottomConstraint = [container.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:0.0];
    self.miniPlayerBottomConstraint = bottomConstraint;
    NSLayoutConstraint *titleTopConstraint = [titleLabel.topAnchor constraintEqualToAnchor:container.topAnchor constant:14.0];
    NSLayoutConstraint *titleCenterYConstraint = [titleLabel.centerYAnchor constraintEqualToAnchor:container.centerYAnchor];
    titleCenterYConstraint.active = NO;
    self.miniPlayerTitleTopConstraint = titleTopConstraint;
    self.miniPlayerTitleCenterYConstraint = titleCenterYConstraint;
    [NSLayoutConstraint activateConstraints:@[
        [container.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:8.0],
        [container.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-8.0],
        bottomConstraint,
        [container.heightAnchor constraintEqualToConstant:62.0],

        [blurView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [blurView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [blurView.topAnchor constraintEqualToAnchor:container.topAnchor],
        [blurView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],

        [artworkView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:8.0],
        [artworkView.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [artworkView.widthAnchor constraintEqualToConstant:40.0],
        [artworkView.heightAnchor constraintEqualToConstant:40.0],

        [nextButton.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-7.0],
        [nextButton.centerYAnchor constraintEqualToAnchor:artworkView.centerYAnchor],
        [nextButton.widthAnchor constraintEqualToConstant:28.0],
        [nextButton.heightAnchor constraintEqualToConstant:28.0],

        [playPauseButton.trailingAnchor constraintEqualToAnchor:nextButton.leadingAnchor constant:-1.0],
        [playPauseButton.centerYAnchor constraintEqualToAnchor:artworkView.centerYAnchor],
        [playPauseButton.widthAnchor constraintEqualToConstant:34.0],
        [playPauseButton.heightAnchor constraintEqualToConstant:34.0],

        [previousButton.trailingAnchor constraintEqualToAnchor:playPauseButton.leadingAnchor constant:-1.0],
        [previousButton.centerYAnchor constraintEqualToAnchor:artworkView.centerYAnchor],
        [previousButton.widthAnchor constraintEqualToConstant:28.0],
        [previousButton.heightAnchor constraintEqualToConstant:28.0],

        [titleLabel.leadingAnchor constraintEqualToAnchor:artworkView.trailingAnchor constant:10.0],
        [titleLabel.trailingAnchor constraintEqualToAnchor:previousButton.leadingAnchor constant:-8.0],
        titleTopConstraint,
        titleCenterYConstraint,

        [subtitleLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [subtitleLabel.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
        [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:1.5],

        [openButton.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [openButton.topAnchor constraintEqualToAnchor:container.topAnchor],
        [openButton.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        [openButton.trailingAnchor constraintEqualToAnchor:previousButton.leadingAnchor constant:-4.0],
    ]];

    [self.view bringSubviewToFront:container];
    [self updateMiniPlayerPosition];
}

- (void)handlePlaybackStateChanged {
    [self updateMiniPlayer];
}

- (nullable UINavigationController *)selectedNavigationController {
    if ([self.selectedViewController isKindOfClass:UINavigationController.class]) {
        return (UINavigationController *)self.selectedViewController;
    }
    return nil;
}

- (BOOL)isMiniPlayerAllowedForCurrentController {
    UINavigationController *navigation = [self selectedNavigationController];
    if (navigation == nil) {
        return YES;
    }

    id<UIViewControllerTransitionCoordinator> coordinator = navigation.transitionCoordinator;
    if (coordinator != nil) {
        UIViewController *toViewController = [coordinator viewControllerForKey:UITransitionContextToViewControllerKey];
        if (toViewController != nil) {
            return !toViewController.hidesBottomBarWhenPushed;
        }
    }

    UIViewController *active = navigation.visibleViewController ?: navigation.topViewController;
    if (active == nil) {
        return YES;
    }
    return !active.hidesBottomBarWhenPushed;
}

- (BOOL)isMiniPlayerAllowedForViewController:(UIViewController *)viewController {
    if (viewController == nil) {
        return YES;
    }
    return !viewController.hidesBottomBarWhenPushed;
}

- (BOOL)shouldShowMiniPlayer {
    if (M2PlaybackManager.sharedManager.currentTrack == nil) {
        return NO;
    }

    if (self.tabBar.superview == nil) {
        return NO;
    }

    CGRect tabBarFrameInView = [self.view convertRect:self.tabBar.frame fromView:self.tabBar.superview];
    CGFloat tabBarTop = CGRectGetMinY(tabBarFrameInView);
    if (!isfinite(tabBarTop) || tabBarTop >= CGRectGetHeight(self.view.bounds)) {
        return NO;
    }

    return [self isMiniPlayerAllowedForCurrentController];
}

- (void)animateMiniPlayerAlongNavigationTransition:(UINavigationController *)navigationController {
    id<UIViewControllerTransitionCoordinator> coordinator = navigationController.transitionCoordinator;
    if (coordinator == nil) {
        return;
    }

    UIViewController *fromViewController = [coordinator viewControllerForKey:UITransitionContextFromViewControllerKey];
    UIViewController *toViewController = [coordinator viewControllerForKey:UITransitionContextToViewControllerKey];
    BOOL fromAllows = [self isMiniPlayerAllowedForViewController:fromViewController];
    BOOL toAllows = [self isMiniPlayerAllowedForViewController:toViewController];
    BOOL hasTrack = (M2PlaybackManager.sharedManager.currentTrack != nil);

    if (!hasTrack || (fromAllows == toAllows)) {
        return;
    }

    CGFloat width = MAX(CGRectGetWidth(self.view.bounds), 1.0);
    CGFloat startX = 0.0;
    CGFloat endX = 0.0;

    if (fromAllows && !toAllows) {
        startX = 0.0;
        endX = -width;
    } else if (!fromAllows && toAllows) {
        startX = -width;
        endX = 0.0;
    }

    self.miniPlayerTransitionAnimating = YES;
    self.miniPlayerContainer.hidden = NO;
    self.miniPlayerContainer.transform = CGAffineTransformMakeTranslation(startX, 0.0);

    [coordinator animateAlongsideTransition:^(__unused id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
        self.miniPlayerContainer.transform = CGAffineTransformMakeTranslation(endX, 0.0);
    } completion:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
        self.miniPlayerContainer.transform = CGAffineTransformIdentity;
        self.miniPlayerTransitionAnimating = NO;

        if (context.isCancelled) {
            [self updateMiniPlayer];
            return;
        }

        [self updateMiniPlayer];
    }];
}

- (void)updateMiniPlayerPosition {
    if (self.miniPlayerBottomConstraint == nil || self.tabBar.superview == nil) {
        return;
    }

    CGRect tabBarFrameInView = [self.view convertRect:self.tabBar.frame fromView:self.tabBar.superview];
    CGFloat tabBarTop = CGRectGetMinY(tabBarFrameInView);
    if (!isfinite(tabBarTop) || tabBarTop <= 0.0) {
        tabBarTop = CGRectGetHeight(self.view.bounds) - CGRectGetHeight(self.tabBar.bounds);
    }

    CGFloat distanceFromBottom = MAX(0.0, CGRectGetHeight(self.view.bounds) - tabBarTop);
    self.miniPlayerBottomConstraint.constant = -(distanceFromBottom + 6.0);
}

- (void)updateMiniPlayer {
    [self updateMiniPlayerPosition];

    M2PlaybackManager *playback = M2PlaybackManager.sharedManager;
    M2Track *track = playback.currentTrack;
    BOOL shouldShow = [self shouldShowMiniPlayer];

    self.miniPlayerContainer.backgroundColor = M2MiniPlayerBackgroundColor();
    self.miniPlayerContainer.layer.borderColor = M2MiniPlayerBorderColor().CGColor;
    self.miniPlayerBlurView.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
    if (!self.miniPlayerTransitionAnimating) {
        self.miniPlayerContainer.hidden = !shouldShow;
    }
    [self applyMiniPlayerInset:(shouldShow ? 70.0 : 0.0)];

    if (!shouldShow || track == nil) {
        return;
    }

    if (track.artwork != nil) {
        self.miniPlayerArtworkView.image = track.artwork;
        self.miniPlayerArtworkView.contentMode = UIViewContentModeScaleAspectFill;
        self.miniPlayerArtworkView.tintColor = nil;
    } else {
        self.miniPlayerArtworkView.image = [UIImage systemImageNamed:@"music.note"];
        self.miniPlayerArtworkView.contentMode = UIViewContentModeCenter;
        self.miniPlayerArtworkView.tintColor = UIColor.secondaryLabelColor;
    }

    NSString *title = track.title.length > 0 ? track.title : track.fileName;
    self.miniPlayerTitleLabel.text = title;
    BOOL hasArtist = (track.artist.length > 0);
    self.miniPlayerSubtitleLabel.text = hasArtist ? track.artist : @"";
    self.miniPlayerSubtitleLabel.hidden = !hasArtist;
    self.miniPlayerTitleTopConstraint.active = hasArtist;
    self.miniPlayerTitleCenterYConstraint.active = !hasArtist;

    NSString *symbolName = playback.isPlaying ? @"pause.fill" : @"play.fill";
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:18.0
                                                                                           weight:UIImageSymbolWeightSemibold];
    UIImage *playPauseImage = [UIImage systemImageNamed:symbolName withConfiguration:config];
    [self.miniPlayerPlayPauseButton setImage:playPauseImage forState:UIControlStateNormal];

    BOOL hasQueue = (playback.currentQueue.count > 0);
    BOOL canStep = (playback.currentQueue.count > 1) || playback.isShuffleEnabled || (playback.repeatMode != M2RepeatModeNone);
    self.miniPlayerOpenButton.enabled = hasQueue;
    self.miniPlayerPlayPauseButton.enabled = hasQueue;
    self.miniPlayerPreviousButton.enabled = hasQueue && canStep;
    self.miniPlayerNextButton.enabled = hasQueue && canStep;
    self.miniPlayerPreviousButton.alpha = self.miniPlayerPreviousButton.enabled ? 1.0 : 0.45;
    self.miniPlayerNextButton.alpha = self.miniPlayerNextButton.enabled ? 1.0 : 0.45;
}

- (void)applyMiniPlayerInset:(CGFloat)bottomInset {
    for (UIViewController *controller in self.viewControllers ?: @[]) {
        UIViewController *target = controller;
        if ([controller isKindOfClass:UINavigationController.class]) {
            UINavigationController *navigation = (UINavigationController *)controller;
            target = navigation.topViewController ?: navigation;
        }

        UIEdgeInsets insets = target.additionalSafeAreaInsets;
        if (fabs(insets.bottom - bottomInset) <= 0.5) {
            continue;
        }
        insets.bottom = bottomInset;
        target.additionalSafeAreaInsets = insets;
    }
}

- (void)miniPlayerOpenTapped {
    [self openPlayerFromMiniPlayer];
}

- (void)miniPlayerPlayPauseTapped {
    [M2PlaybackManager.sharedManager togglePlayPause];
    [self updateMiniPlayer];
}

- (void)miniPlayerPreviousTapped {
    [M2PlaybackManager.sharedManager playPrevious];
    [self updateMiniPlayer];
}

- (void)miniPlayerNextTapped {
    [M2PlaybackManager.sharedManager playNext];
    [self updateMiniPlayer];
}

- (void)handleMiniPlayerHorizontalPan:(UIPanGestureRecognizer *)gesture {
    if (self.miniPlayerContainer.hidden) {
        return;
    }

    if (gesture.state != UIGestureRecognizerStateEnded) {
        return;
    }

    CGPoint translation = [gesture translationInView:self.miniPlayerContainer];
    CGPoint velocity = [gesture velocityInView:self.miniPlayerContainer];
    CGFloat absX = fabs(translation.x);
    CGFloat absY = fabs(translation.y);
    BOOL horizontalIntent = (absX > absY * 1.1);
    if (!horizontalIntent) {
        return;
    }

    if (translation.x <= -20.0 || velocity.x <= -300.0) {
        [self miniPlayerNextTapped];
    } else if (translation.x >= 20.0 || velocity.x >= 300.0) {
        [self miniPlayerPreviousTapped];
    }
}

- (void)openPlayerFromMiniPlayer {
    if (M2PlaybackManager.sharedManager.currentTrack == nil) {
        return;
    }

    UINavigationController *navigation = [self selectedNavigationController];
    if (navigation == nil) {
        return;
    }

    UIViewController *top = navigation.topViewController;
    if ([NSStringFromClass(top.class) isEqualToString:@"M2PlayerViewController"]) {
        return;
    }

    Class playerClass = NSClassFromString(@"M2PlayerViewController");
    if (playerClass == Nil || ![playerClass isSubclassOfClass:UIViewController.class]) {
        return;
    }

    UIViewController *player = [[playerClass alloc] init];
    player.hidesBottomBarWhenPushed = YES;
    [navigation pushViewController:player animated:YES];
}

- (void)tabBarController:(UITabBarController *)tabBarController didSelectViewController:(UIViewController *)viewController {
    (void)tabBarController;
    (void)viewController;
    [self updateMiniPlayerPosition];
    [self updateMiniPlayer];
}

- (void)navigationController:(UINavigationController *)navigationController
      willShowViewController:(UIViewController *)viewController
                    animated:(BOOL)animated {
    BOOL isRoot = (navigationController.viewControllers.firstObject == viewController);
    viewController.navigationItem.hidesBackButton = !isRoot;
    navigationController.interactivePopGestureRecognizer.enabled = YES;
    navigationController.interactivePopGestureRecognizer.delegate = nil;
    [self updateMiniPlayerPosition];
    if (animated) {
        [self animateMiniPlayerAlongNavigationTransition:navigationController];
    }
    [self updateMiniPlayer];
}

- (UIImage *)tabIconNamed:(NSString *)name {
    UIImage *image = [UIImage imageNamed:name];
    if (image == nil) {
        NSString *path = [NSBundle.mainBundle pathForResource:name ofType:@"png"];
        if (path != nil) {
            image = [UIImage imageWithContentsOfFile:path];
        }
    }

    if (image == nil) {
        image = [UIImage systemImageNamed:@"circle.fill"];
    }

    UIImage *normalized = [self normalizedIconImage:image targetSize:24.0];
    return [normalized imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

- (UIImage *)normalizedIconImage:(UIImage *)image targetSize:(CGFloat)targetSize {
    CGSize canvasSize = CGSizeMake(targetSize, targetSize);
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.opaque = NO;
    format.scale = UIScreen.mainScreen.scale;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:canvasSize format:format];

    return [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull context) {
        CGSize source = image.size;
        if (source.width <= 0.0 || source.height <= 0.0) {
            [image drawInRect:CGRectMake(0.0, 0.0, canvasSize.width, canvasSize.height)];
            return;
        }

        CGFloat scale = MIN(canvasSize.width / source.width, canvasSize.height / source.height);
        CGSize drawSize = CGSizeMake(source.width * scale, source.height * scale);
        CGRect drawRect = CGRectMake((canvasSize.width - drawSize.width) * 0.5,
                                     (canvasSize.height - drawSize.height) * 0.5,
                                     drawSize.width,
                                     drawSize.height);
        [image drawInRect:drawRect];
    }];
}

- (UIImage *)tabSymbolIconNamed:(NSString *)symbolName pointSize:(CGFloat)pointSize {
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:pointSize
                                                                                           weight:UIImageSymbolWeightSemibold];
    UIImage *image = [UIImage systemImageNamed:symbolName withConfiguration:config];
    if (image == nil) {
        image = [UIImage systemImageNamed:@"circle.fill"];
    }
    UIImage *normalized = [self normalizedIconImage:image targetSize:24.0];
    return [normalized imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

@end
