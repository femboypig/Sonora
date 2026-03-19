//
//  SonoraPlayerViewController.m
//  Sonora
//

#import "SonoraPlayerViewController.h"

#import <QuartzCore/QuartzCore.h>

#import "SonoraMusicUIHelpers.h"
#import "SonoraSettings.h"
#import "SonoraSharedPlaylists.h"
#import "SonoraSleepTimerUI.h"
#import "SonoraServices.h"

static NSString * const SonoraMiniStreamingPlaceholderPrefix = @"mini-streaming-placeholder-";
static NSString * const SonoraSharedPlaylistDefaultsKey = @"sonora.sharedPlaylists.v1";
NSArray<UIColor *> *SonoraResolvedWavePalette(UIImage * _Nullable image);

#pragma mark - Player

@interface SonoraArtworkEqualizerBadgeView : UIView

- (void)setBarColor:(UIColor *)color;
- (void)setPlaying:(BOOL)playing;
- (void)setLevel:(CGFloat)level;

@end

@interface SonoraArtworkEqualizerBadgeView ()

@property (nonatomic, copy) NSArray<UIView *> *barViews;
@property (nonatomic, copy) NSArray<NSLayoutConstraint *> *barHeightConstraints;
@property (nonatomic, assign) BOOL playing;

@end

@implementation SonoraArtworkEqualizerBadgeView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.userInteractionEnabled = NO;
        self.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.58];
        self.layer.cornerRadius = 8.0;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.20].CGColor;
        self.layer.masksToBounds = YES;

        NSArray<NSNumber *> *heights = @[@5.0, @8.0, @9.0, @6.0];
        NSMutableArray<UIView *> *bars = [NSMutableArray arrayWithCapacity:heights.count];
        NSMutableArray<NSLayoutConstraint *> *heightConstraints = [NSMutableArray arrayWithCapacity:heights.count];
        UIView *previousBar = nil;
        for (NSNumber *height in heights) {
            UIView *bar = [[UIView alloc] init];
            bar.translatesAutoresizingMaskIntoConstraints = NO;
            bar.backgroundColor = UIColor.whiteColor;
            bar.layer.cornerRadius = 1.3;
            bar.layer.masksToBounds = YES;
            [self addSubview:bar];
            [bars addObject:bar];

            NSLayoutConstraint *heightConstraint = [bar.heightAnchor constraintEqualToConstant:height.doubleValue];
            [NSLayoutConstraint activateConstraints:@[
                [bar.widthAnchor constraintEqualToConstant:2.4],
                heightConstraint,
                [bar.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-4.0]
            ]];
            [heightConstraints addObject:heightConstraint];
            if (previousBar == nil) {
                [bar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:6.0].active = YES;
            } else {
                [bar.leadingAnchor constraintEqualToAnchor:previousBar.trailingAnchor constant:2.5].active = YES;
            }
            previousBar = bar;
        }
        [previousBar.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-6.0].active = YES;
        self.barViews = [bars copy];
        self.barHeightConstraints = [heightConstraints copy];
    }
    return self;
}

- (void)setBarColor:(UIColor *)color {
    UIColor *resolved = color ?: UIColor.whiteColor;
    for (UIView *bar in self.barViews) {
        bar.backgroundColor = resolved;
    }
}

- (void)setPlaying:(BOOL)playing {
    _playing = playing;
    self.alpha = playing ? 1.0 : 0.90;
}

- (void)setLevel:(CGFloat)level {
    CGFloat clamped = MIN(MAX(level, 0.0), 1.0);
    NSArray<NSNumber *> *weights = @[@0.62, @0.92, @1.0, @0.76];

    for (NSUInteger index = 0; index < self.barHeightConstraints.count; index += 1) {
        CGFloat weight = [weights[index] doubleValue];
        CGFloat base = self.playing ? 4.0 : 3.2;
        CGFloat dynamic = clamped * (self.playing ? 14.0 : 5.0) * weight;
        self.barHeightConstraints[index].constant = base + dynamic;
    }

    if (self.window != nil) {
        [UIView animateWithDuration:0.16
                              delay:0.0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            [self layoutIfNeeded];
        } completion:nil];
    }
}

@end

@interface SonoraPlayerViewController ()

@property (nonatomic, strong) UIImageView *artworkView;
@property (nonatomic, strong) UIView *backgroundColorView;
@property (nonatomic, strong) CAGradientLayer *backgroundGradientLayer;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UISlider *progressSlider;
@property (nonatomic, strong) UILabel *elapsedLabel;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) UILabel *nextPreviewLabel;
@property (nonatomic, strong) UIButton *shuffleButton;
@property (nonatomic, strong) UIButton *repeatButton;
@property (nonatomic, strong) UIButton *previousButton;
@property (nonatomic, strong) UIButton *playPauseButton;
@property (nonatomic, strong) UIButton *nextButton;
@property (nonatomic, strong) UIButton *favoriteButton;
@property (nonatomic, strong) UIButton *sleepTimerButton;
@property (nonatomic, strong) SonoraArtworkEqualizerBadgeView *equalizerBadgeView;
@property (nonatomic, strong) UIView *artworkLoadingOverlayView;
@property (nonatomic, strong) UIActivityIndicatorView *artworkLoadingSpinner;
@property (nonatomic, strong) NSLayoutConstraint *artworkLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *artworkTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *controlsBottomConstraint;
@property (nonatomic, strong, nullable) UIColor *currentArtworkBackgroundColor;
@property (nonatomic, assign) BOOL scrubbing;

@end

@implementation SonoraPlayerViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = SonoraPlayerBackgroundColor();

    [self setupUI];
    [self applyPlayerTheme];

    if (@available(iOS 17.0, *)) {
        __weak typeof(self) weakSelf = self;
        [self registerForTraitChanges:@[UITraitUserInterfaceStyle.class]
                          withHandler:^(__kindof id<UITraitEnvironment>  _Nonnull traitEnvironment,
                                        UITraitCollection * _Nullable previousTraitCollection) {
            (void)traitEnvironment;
            (void)previousTraitCollection;
            __strong typeof(weakSelf) strongSelf = weakSelf;
            [strongSelf applyPlayerTheme];
            [strongSelf updateModeIcons];
        }];
    }

    UISwipeGestureRecognizer *swipeDown = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleDismissSwipe)];
    swipeDown.direction = UISwipeGestureRecognizerDirectionDown;
    [self.view addGestureRecognizer:swipeDown];

    UISwipeGestureRecognizer *swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleDismissSwipe)];
    swipeRight.direction = UISwipeGestureRecognizerDirectionRight;
    [self.view addGestureRecognizer:swipeRight];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(refreshUI)
                                               name:SonoraPlaybackStateDidChangeNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handleProgressChanged)
                                               name:SonoraPlaybackProgressDidChangeNotification
                                             object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handlePlaybackMeterChanged:)
                                               name:SonoraPlaybackMeterDidChangeNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(updateFavoriteButton)
                                               name:SonoraFavoritesDidChangeNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(updateSleepTimerButton)
                                               name:SonoraSleepTimerDidChangeNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handlePlayerSettingsChanged:)
                                               name:SonoraPlayerSettingsDidChangeNotification
                                             object:nil];

    [self refreshUI];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    self.navigationController.interactivePopGestureRecognizer.enabled = YES;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateArtworkCornerRadius];
    [self updateControlsBottomInset];
    self.backgroundGradientLayer.frame = self.backgroundColorView.bounds;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:animated];
}

- (void)setupUI {
    UIView *backgroundColorView = [[UIView alloc] init];
    backgroundColorView.translatesAutoresizingMaskIntoConstraints = NO;
    self.backgroundColorView = backgroundColorView;
    CAGradientLayer *backgroundGradientLayer = [CAGradientLayer layer];
    backgroundGradientLayer.startPoint = CGPointMake(0.15, 0.0);
    backgroundGradientLayer.endPoint = CGPointMake(0.85, 1.0);
    backgroundGradientLayer.locations = @[@0.0, @0.36, @0.72, @1.0];
    [backgroundColorView.layer addSublayer:backgroundGradientLayer];
    self.backgroundGradientLayer = backgroundGradientLayer;

    UIView *content = [[UIView alloc] init];
    content.translatesAutoresizingMaskIntoConstraints = NO;

    UIImageView *artworkView = [[UIImageView alloc] init];
    artworkView.translatesAutoresizingMaskIntoConstraints = NO;
    artworkView.contentMode = UIViewContentModeScaleAspectFill;
    artworkView.layer.cornerRadius = 0.0;
    artworkView.layer.masksToBounds = YES;
    self.artworkView = artworkView;

    SonoraArtworkEqualizerBadgeView *equalizerBadge = [[SonoraArtworkEqualizerBadgeView alloc] init];
    equalizerBadge.hidden = YES;
    self.equalizerBadgeView = equalizerBadge;
    [artworkView addSubview:equalizerBadge];

    UIView *artworkLoadingOverlayView = [[UIView alloc] init];
    artworkLoadingOverlayView.translatesAutoresizingMaskIntoConstraints = NO;
    artworkLoadingOverlayView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.36];
    artworkLoadingOverlayView.userInteractionEnabled = NO;
    artworkLoadingOverlayView.hidden = YES;
    self.artworkLoadingOverlayView = artworkLoadingOverlayView;

    UIActivityIndicatorView *artworkLoadingSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    artworkLoadingSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    artworkLoadingSpinner.color = UIColor.whiteColor;
    artworkLoadingSpinner.hidesWhenStopped = NO;
    self.artworkLoadingSpinner = artworkLoadingSpinner;

    [artworkLoadingOverlayView addSubview:artworkLoadingSpinner];
    [artworkView addSubview:artworkLoadingOverlayView];

    UILabel *artistLabel = [[UILabel alloc] init];
    artistLabel.translatesAutoresizingMaskIntoConstraints = NO;
    artistLabel.textAlignment = NSTextAlignmentCenter;
    artistLabel.font = [UIFont systemFontOfSize:24.0 weight:UIFontWeightSemibold];
    artistLabel.numberOfLines = 1;
    self.subtitleLabel = artistLabel;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont systemFontOfSize:24.0 weight:UIFontWeightSemibold];
    titleLabel.numberOfLines = 1;
    self.titleLabel = titleLabel;

    UISlider *slider = [[UISlider alloc] init];
    slider.translatesAutoresizingMaskIntoConstraints = NO;
    slider.minimumValue = 0.0;
    slider.maximumValue = 1.0;
    slider.transform = CGAffineTransformMakeScale(1.0, 0.92);
    [slider addTarget:self action:@selector(sliderTouchDown) forControlEvents:UIControlEventTouchDown];
    [slider addTarget:self action:@selector(sliderChanged) forControlEvents:UIControlEventValueChanged];
    [slider addTarget:self action:@selector(sliderTouchUp) forControlEvents:UIControlEventTouchUpInside];
    [slider addTarget:self action:@selector(sliderTouchUp) forControlEvents:UIControlEventTouchUpOutside];
    [slider addTarget:self action:@selector(sliderTouchUp) forControlEvents:UIControlEventTouchCancel];
    self.progressSlider = slider;

    UILabel *elapsedLabel = [[UILabel alloc] init];
    elapsedLabel.translatesAutoresizingMaskIntoConstraints = NO;
    elapsedLabel.font = [UIFont monospacedDigitSystemFontOfSize:12.0 weight:UIFontWeightMedium];
    self.elapsedLabel = elapsedLabel;

    UILabel *durationLabel = [[UILabel alloc] init];
    durationLabel.translatesAutoresizingMaskIntoConstraints = NO;
    durationLabel.textAlignment = NSTextAlignmentRight;
    durationLabel.font = [UIFont monospacedDigitSystemFontOfSize:12.0 weight:UIFontWeightMedium];
    self.durationLabel = durationLabel;

    UILabel *nextPreviewLabel = [[UILabel alloc] init];
    nextPreviewLabel.translatesAutoresizingMaskIntoConstraints = NO;
    nextPreviewLabel.textAlignment = NSTextAlignmentLeft;
    nextPreviewLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightSemibold];
    nextPreviewLabel.numberOfLines = 2;
    self.nextPreviewLabel = nextPreviewLabel;

    self.repeatButton = SonoraPlainIconButton(@"repeat", 24.0, 600.0);
    [self.repeatButton addTarget:self action:@selector(toggleRepeatTapped) forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[
        [self.repeatButton.widthAnchor constraintEqualToConstant:42.0],
        [self.repeatButton.heightAnchor constraintEqualToConstant:42.0]
    ]];

    self.shuffleButton = SonoraPlainIconButton(@"shuffle", 24.0, 600.0);
    [self.shuffleButton addTarget:self action:@selector(toggleShuffleTapped) forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[
        [self.shuffleButton.widthAnchor constraintEqualToConstant:42.0],
        [self.shuffleButton.heightAnchor constraintEqualToConstant:42.0]
    ]];

    self.previousButton = SonoraPlainIconButton(@"backward.fill", 44.0, 700.0);
    [self.previousButton addTarget:self action:@selector(previousTapped) forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[
        [self.previousButton.widthAnchor constraintEqualToConstant:64.0],
        [self.previousButton.heightAnchor constraintEqualToConstant:64.0]
    ]];

    self.playPauseButton = SonoraPlainIconButton(@"play.fill", 56.0, 700.0);
    [self.playPauseButton addTarget:self action:@selector(playPauseTapped) forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[
        [self.playPauseButton.widthAnchor constraintEqualToConstant:76.0],
        [self.playPauseButton.heightAnchor constraintEqualToConstant:76.0]
    ]];

    self.nextButton = SonoraPlainIconButton(@"forward.fill", 44.0, 700.0);
    [self.nextButton addTarget:self action:@selector(nextTapped) forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[
        [self.nextButton.widthAnchor constraintEqualToConstant:64.0],
        [self.nextButton.heightAnchor constraintEqualToConstant:64.0]
    ]];

    self.favoriteButton = SonoraPlainIconButton(@"heart", 24.0, 600.0);
    [self.favoriteButton addTarget:self action:@selector(toggleFavoriteTapped) forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[
        [self.favoriteButton.widthAnchor constraintEqualToConstant:40.0],
        [self.favoriteButton.heightAnchor constraintEqualToConstant:40.0]
    ]];

    self.sleepTimerButton = SonoraPlainIconButton(@"moon.zzz", 23.0, 600.0);
    [self.sleepTimerButton addTarget:self action:@selector(sleepTimerTapped) forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[
        [self.sleepTimerButton.widthAnchor constraintEqualToConstant:40.0],
        [self.sleepTimerButton.heightAnchor constraintEqualToConstant:40.0]
    ]];

    UIStackView *modeStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.repeatButton, self.shuffleButton]];
    modeStack.translatesAutoresizingMaskIntoConstraints = NO;
    modeStack.axis = UILayoutConstraintAxisVertical;
    modeStack.alignment = UIStackViewAlignmentCenter;
    modeStack.distribution = UIStackViewDistributionEqualSpacing;
    modeStack.spacing = 10.0;

    UIStackView *rightStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.sleepTimerButton, self.favoriteButton]];
    rightStack.translatesAutoresizingMaskIntoConstraints = NO;
    rightStack.axis = UILayoutConstraintAxisVertical;
    rightStack.alignment = UIStackViewAlignmentCenter;
    rightStack.distribution = UIStackViewDistributionEqualSpacing;
    rightStack.spacing = 10.0;

    UIStackView *transportStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.previousButton, self.playPauseButton, self.nextButton
    ]];
    transportStack.translatesAutoresizingMaskIntoConstraints = NO;
    transportStack.axis = UILayoutConstraintAxisHorizontal;
    transportStack.alignment = UIStackViewAlignmentCenter;
    transportStack.distribution = UIStackViewDistributionEqualCentering;
    transportStack.spacing = 16.0;

    UIView *controlsRow = [[UIView alloc] init];
    controlsRow.translatesAutoresizingMaskIntoConstraints = NO;

    [content addSubview:artworkView];
    [content addSubview:slider];
    [content addSubview:elapsedLabel];
    [content addSubview:durationLabel];
    [content addSubview:artistLabel];
    [content addSubview:titleLabel];
    [content addSubview:nextPreviewLabel];
    [content addSubview:controlsRow];

    [controlsRow addSubview:modeStack];
    [controlsRow addSubview:transportStack];
    [controlsRow addSubview:rightStack];

    [self.view addSubview:backgroundColorView];
    [self.view addSubview:content];

    NSLayoutConstraint *artworkSquare = [artworkView.heightAnchor constraintEqualToAnchor:artworkView.widthAnchor];
    artworkSquare.priority = UILayoutPriorityDefaultHigh;
    self.artworkLeadingConstraint = [artworkView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor];
    self.artworkTrailingConstraint = [artworkView.trailingAnchor constraintEqualToAnchor:content.trailingAnchor];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    self.controlsBottomConstraint = [controlsRow.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-6.0];
    [NSLayoutConstraint activateConstraints:@[
        [backgroundColorView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [backgroundColorView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [backgroundColorView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [backgroundColorView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [content.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [content.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [content.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [artworkView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        self.artworkLeadingConstraint,
        self.artworkTrailingConstraint,
        artworkSquare,
        [artworkView.heightAnchor constraintLessThanOrEqualToAnchor:content.heightAnchor multiplier:0.56],
        [equalizerBadge.bottomAnchor constraintEqualToAnchor:artworkView.bottomAnchor constant:-10.0],
        [equalizerBadge.trailingAnchor constraintEqualToAnchor:artworkView.trailingAnchor constant:-10.0],
        [equalizerBadge.widthAnchor constraintEqualToConstant:30.0],
        [equalizerBadge.heightAnchor constraintEqualToConstant:24.0],
        [artworkLoadingOverlayView.topAnchor constraintEqualToAnchor:artworkView.topAnchor],
        [artworkLoadingOverlayView.leadingAnchor constraintEqualToAnchor:artworkView.leadingAnchor],
        [artworkLoadingOverlayView.trailingAnchor constraintEqualToAnchor:artworkView.trailingAnchor],
        [artworkLoadingOverlayView.bottomAnchor constraintEqualToAnchor:artworkView.bottomAnchor],
        [artworkLoadingSpinner.centerXAnchor constraintEqualToAnchor:artworkLoadingOverlayView.centerXAnchor],
        [artworkLoadingSpinner.centerYAnchor constraintEqualToAnchor:artworkLoadingOverlayView.centerYAnchor],

        [slider.topAnchor constraintEqualToAnchor:artworkView.bottomAnchor constant:16.0],
        [slider.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16.0],
        [slider.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16.0],

        [elapsedLabel.topAnchor constraintEqualToAnchor:slider.bottomAnchor constant:3.0],
        [elapsedLabel.leadingAnchor constraintEqualToAnchor:slider.leadingAnchor],

        [durationLabel.topAnchor constraintEqualToAnchor:elapsedLabel.topAnchor],
        [durationLabel.trailingAnchor constraintEqualToAnchor:slider.trailingAnchor],

        [artistLabel.topAnchor constraintEqualToAnchor:elapsedLabel.bottomAnchor constant:18.0],
        [artistLabel.leadingAnchor constraintEqualToAnchor:slider.leadingAnchor],
        [artistLabel.trailingAnchor constraintEqualToAnchor:slider.trailingAnchor],

        [titleLabel.topAnchor constraintEqualToAnchor:artistLabel.bottomAnchor constant:6.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:slider.leadingAnchor],
        [titleLabel.trailingAnchor constraintEqualToAnchor:slider.trailingAnchor],

        [controlsRow.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14.0],
        [controlsRow.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-14.0],
        self.controlsBottomConstraint,
        [controlsRow.heightAnchor constraintEqualToConstant:88.0],

        [modeStack.leadingAnchor constraintEqualToAnchor:controlsRow.leadingAnchor],
        [modeStack.centerYAnchor constraintEqualToAnchor:controlsRow.centerYAnchor],

        [transportStack.centerXAnchor constraintEqualToAnchor:controlsRow.centerXAnchor],
        [transportStack.centerYAnchor constraintEqualToAnchor:controlsRow.centerYAnchor],

        [rightStack.trailingAnchor constraintEqualToAnchor:controlsRow.trailingAnchor],
        [rightStack.centerYAnchor constraintEqualToAnchor:controlsRow.centerYAnchor],

        [nextPreviewLabel.leadingAnchor constraintEqualToAnchor:slider.leadingAnchor],
        [nextPreviewLabel.trailingAnchor constraintEqualToAnchor:slider.trailingAnchor],
        [nextPreviewLabel.topAnchor constraintGreaterThanOrEqualToAnchor:titleLabel.bottomAnchor constant:16.0],
        [nextPreviewLabel.bottomAnchor constraintEqualToAnchor:controlsRow.topAnchor constant:-14.0]
    ]];
}

- (void)handleDismissSwipe {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)applyPlayerTheme {
    UIColor *primary = SonoraPlayerPrimaryColor();
    UIColor *secondary = SonoraPlayerSecondaryColor();
    SonoraPlayerFontStyle fontStyle = SonoraPlayerFontStyleFromDefaults();
    UIColor *resolvedBackground = SonoraPlayerBackgroundColor();
    if (SonoraSettingsUseArtworkBasedPlayerBackgroundEnabled() && self.currentArtworkBackgroundColor != nil) {
        resolvedBackground = self.currentArtworkBackgroundColor;
        CGFloat red = 0.0;
        CGFloat green = 0.0;
        CGFloat blue = 0.0;
        CGFloat alpha = 1.0;
        if ([resolvedBackground getRed:&red green:&green blue:&blue alpha:&alpha]) {
            CGFloat luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue);
            if (luminance > 0.58) {
                primary = [UIColor colorWithWhite:0.10 alpha:1.0];
                secondary = [UIColor colorWithWhite:0.10 alpha:0.68];
            } else {
                primary = [UIColor colorWithWhite:1.0 alpha:0.96];
                secondary = [UIColor colorWithWhite:1.0 alpha:0.70];
            }
        }
    }

    self.view.backgroundColor = resolvedBackground;
    self.backgroundColorView.backgroundColor = resolvedBackground;
    self.backgroundGradientLayer.hidden = !(SonoraSettingsUseArtworkBasedPlayerBackgroundEnabled() && self.backgroundGradientLayer.colors.count > 0);
    [self updateArtworkCornerRadius];
    self.titleLabel.textColor = primary;
    self.subtitleLabel.textColor = secondary;
    self.elapsedLabel.textColor = secondary;
    self.durationLabel.textColor = secondary;
    self.nextPreviewLabel.textColor = secondary;
    self.titleLabel.font = SonoraPlayerFontForStyle(fontStyle, 24.0, UIFontWeightSemibold);
    self.subtitleLabel.font = SonoraPlayerFontForStyle(fontStyle, 24.0, UIFontWeightSemibold);
    self.nextPreviewLabel.font = SonoraPlayerFontForStyle(fontStyle, 18.0, UIFontWeightSemibold);

    self.progressSlider.minimumTrackTintColor = primary;
    self.progressSlider.maximumTrackTintColor = SonoraPlayerTimelineMaxColor();
    UIImage *thumbImage = SonoraSliderThumbImage(14.5, primary);
    [self.progressSlider setThumbImage:thumbImage forState:UIControlStateNormal];
    [self.progressSlider setThumbImage:thumbImage forState:UIControlStateHighlighted];
    self.artworkLoadingOverlayView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.38];

    BOOL controlsEnabled = self.playPauseButton.enabled;
    UIColor *controlColor = controlsEnabled ? primary : [secondary colorWithAlphaComponent:0.65];
    NSArray<UIButton *> *buttons = @[
        self.repeatButton,
        self.shuffleButton,
        self.previousButton,
        self.playPauseButton,
        self.nextButton,
        self.favoriteButton,
        self.sleepTimerButton
    ];
    for (UIButton *button in buttons) {
        CGFloat height = CGRectGetHeight(button.bounds);
        if (height < 1.0) {
            [button layoutIfNeeded];
            height = CGRectGetHeight(button.bounds);
        }
        if (height < 1.0) {
            height = 42.0;
        }
        button.backgroundColor = UIColor.clearColor;
        button.layer.cornerRadius = 0.0;
        button.layer.borderWidth = 0.0;
        button.layer.borderColor = nil;
        button.layer.masksToBounds = YES;
    }

    [self.equalizerBadgeView setBarColor:[UIColor colorWithWhite:1.0 alpha:0.96]];
    self.equalizerBadgeView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.58];

    self.repeatButton.tintColor = [primary colorWithAlphaComponent:0.92];
    self.shuffleButton.tintColor = [primary colorWithAlphaComponent:0.92];
    self.previousButton.tintColor = controlColor;
    self.playPauseButton.tintColor = controlColor;
    self.nextButton.tintColor = controlColor;
    [self updateFavoriteButton];
    [self updateSleepTimerButton];
    [self updateEqualizerBadge];
}

- (void)updateControlsBottomInset {
    CGFloat maxDimension = MAX(CGRectGetWidth(self.view.bounds), CGRectGetHeight(self.view.bounds));
    CGFloat bottomInset = 6.0;
    if (maxDimension >= 926.0) {
        bottomInset = 18.0;
    } else if (maxDimension >= 852.0) {
        bottomInset = 14.0;
    } else if (maxDimension >= 812.0) {
        bottomInset = 10.0;
    }
    self.controlsBottomConstraint.constant = -bottomInset;
}

- (void)updateArtworkBasedBackgroundForTrack:(SonoraTrack * _Nullable)track {
    if (!SonoraSettingsUseArtworkBasedPlayerBackgroundEnabled() || track.artwork == nil) {
        self.currentArtworkBackgroundColor = nil;
        self.backgroundGradientLayer.colors = nil;
        return;
    }

    UIColor *base = SonoraPlayerBackgroundColor();
    CGFloat baseRed = 0.0;
    CGFloat baseGreen = 0.0;
    CGFloat baseBlue = 0.0;
    CGFloat baseAlpha = 1.0;
    [base getRed:&baseRed green:&baseGreen blue:&baseBlue alpha:&baseAlpha];

    BOOL isDark = (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark);
    NSArray<UIColor *> *palette = SonoraResolvedWavePalette(track.artwork);
    if (palette.count == 0) {
        palette = @[[SonoraArtworkAccentColorService dominantAccentColorForImage:track.artwork fallback:base]];
    }

    NSMutableArray *gradientColors = [NSMutableArray arrayWithCapacity:4];
    NSArray<NSNumber *> *mixes = isDark ? @[@0.24, @0.16, @0.10, @0.05] : @[@0.24, @0.14, @0.08, @0.04];
    for (NSUInteger idx = 0; idx < 4; idx += 1) {
        UIColor *paletteColor = palette[idx % palette.count];
        CGFloat red = 0.0;
        CGFloat green = 0.0;
        CGFloat blue = 0.0;
        CGFloat alpha = 1.0;
        if (![paletteColor getRed:&red green:&green blue:&blue alpha:&alpha]) {
            continue;
        }
        CGFloat mix = [mixes[idx] doubleValue];
        UIColor *blended = [UIColor colorWithRed:(baseRed + ((red - baseRed) * mix))
                                           green:(baseGreen + ((green - baseGreen) * mix))
                                            blue:(baseBlue + ((blue - baseBlue) * mix))
                                           alpha:1.0];
        [gradientColors addObject:(id)blended.CGColor];
        if (idx == 0) {
            self.currentArtworkBackgroundColor = blended;
        }
    }

    self.backgroundGradientLayer.colors = gradientColors;
}

- (void)updateArtworkCornerRadius {
    SonoraPlayerArtworkStyle artworkStyle = SonoraPlayerArtworkStyleFromDefaults();
    CGFloat horizontalInset = (artworkStyle == SonoraPlayerArtworkStyleRounded) ? 12.0 : 0.0;
    self.artworkLeadingConstraint.constant = horizontalInset;
    self.artworkTrailingConstraint.constant = -horizontalInset;
    CGFloat artworkWidth = CGRectGetWidth(self.artworkView.bounds);
    if (artworkWidth < 1.0) {
        CGFloat fallbackWidth = CGRectGetWidth(self.view.bounds);
        if (fallbackWidth < 1.0) {
            fallbackWidth = CGRectGetWidth(UIScreen.mainScreen.bounds);
        }
        artworkWidth = MAX(0.0, fallbackWidth - (horizontalInset * 2.0));
    }
    self.artworkView.layer.cornerRadius = SonoraArtworkCornerRadiusForStyle(artworkStyle, artworkWidth);
    self.artworkView.layer.masksToBounds = YES;
    if (@available(iOS 13.0, *)) {
        self.artworkView.layer.cornerCurve = kCACornerCurveContinuous;
    }
}

- (void)handlePlayerSettingsChanged:(NSNotification *)notification {
    (void)notification;
    [self updateArtworkBasedBackgroundForTrack:SonoraPlaybackManager.sharedManager.currentTrack];
    [self applyPlayerTheme];
    [self updateEqualizerBadge];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSArray<NSDictionary<NSString *, id> *> *storedSharedPlaylists = [NSUserDefaults.standardUserDefaults arrayForKey:SonoraSharedPlaylistDefaultsKey];
        if (![storedSharedPlaylists isKindOfClass:NSArray.class] || storedSharedPlaylists.count == 0) {
            return;
        }
        if (!SonoraSettingsCacheOnlinePlaylistTracksEnabled()) {
            NSArray<NSURL *> *files = [NSFileManager.defaultManager contentsOfDirectoryAtURL:[NSURL fileURLWithPath:SonoraSharedPlaylistAudioCacheDirectoryPath()]
                                                                  includingPropertiesForKeys:nil
                                                                                     options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                       error:nil];
            for (NSURL *fileURL in files) {
                [NSFileManager.defaultManager removeItemAtURL:fileURL error:nil];
            }
            return;
        }
        for (NSDictionary<NSString *, id> *item in storedSharedPlaylists) {
            NSString *playlistID = [item[@"playlistID"] isKindOfClass:NSString.class] ? item[@"playlistID"] : @"";
            if (playlistID.length == 0) {
                continue;
            }
            SonoraSharedPlaylistSnapshot *snapshot = [SonoraSharedPlaylistStore.sharedStore snapshotForPlaylistID:playlistID];
            if (snapshot != nil) {
                SonoraSharedPlaylistWarmPersistentCache(snapshot, nil);
            }
        }
    });
}

- (void)previousTapped {
    [SonoraPlaybackManager.sharedManager playPrevious];
}

- (void)playPauseTapped {
    [SonoraPlaybackManager.sharedManager togglePlayPause];
}

- (void)nextTapped {
    [SonoraPlaybackManager.sharedManager playNext];
}

- (void)toggleShuffleTapped {
    [SonoraPlaybackManager.sharedManager toggleShuffleEnabled];
}

- (void)toggleRepeatTapped {
    [SonoraPlaybackManager.sharedManager cycleRepeatMode];
}

- (void)toggleFavoriteTapped {
    SonoraTrack *track = SonoraPlaybackManager.sharedManager.currentTrack;
    if (track.identifier.length == 0) {
        return;
    }
    [SonoraFavoritesStore.sharedStore toggleFavoriteForTrackID:track.identifier];
    [self updateFavoriteButton];
}

- (void)sleepTimerTapped {
    __weak typeof(self) weakSelf = self;
    SonoraPresentSleepTimerActionSheet(self, self.sleepTimerButton, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf updateSleepTimerButton];
    });
}

- (void)updateFavoriteButton {
    SonoraTrack *track = SonoraPlaybackManager.sharedManager.currentTrack;
    BOOL isPlaceholder = [self isMiniStreamingPlaceholderTrack:track];
    if (track == nil || track.identifier.length == 0 || isPlaceholder) {
        self.favoriteButton.hidden = YES;
        self.favoriteButton.enabled = NO;
        return;
    }

    self.favoriteButton.hidden = NO;
    self.favoriteButton.enabled = YES;

    BOOL isFavorite = [SonoraFavoritesStore.sharedStore isTrackFavoriteByID:track.identifier];
    NSString *symbolName = isFavorite ? @"heart.fill" : @"heart";
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:24.0
                                                                                          weight:UIImageSymbolWeightSemibold];
    UIImage *image = [UIImage systemImageNamed:symbolName withConfiguration:config];
    [self.favoriteButton setImage:image forState:UIControlStateNormal];
    self.favoriteButton.tintColor = isFavorite ? [UIColor colorWithRed:1.0 green:0.35 blue:0.40 alpha:1.0]
                                               : [SonoraPlayerPrimaryColor() colorWithAlphaComponent:0.92];
}

- (void)updateSleepTimerButton {
    BOOL isActive = SonoraSleepTimerManager.sharedManager.isActive;
    NSString *symbol = isActive ? @"moon.zzz.fill" : @"moon.zzz";
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:23.0
                                                                                          weight:UIImageSymbolWeightSemibold];
    [self.sleepTimerButton setImage:[UIImage systemImageNamed:symbol withConfiguration:config] forState:UIControlStateNormal];
    self.sleepTimerButton.tintColor = isActive ? SonoraAccentYellowColor()
                                               : [SonoraPlayerPrimaryColor() colorWithAlphaComponent:0.92];
    self.sleepTimerButton.accessibilityLabel = isActive
    ? [NSString stringWithFormat:@"Sleep timer active, %@ remaining", SonoraSleepTimerRemainingString(SonoraSleepTimerManager.sharedManager.remainingTime)]
    : @"Sleep timer";
}

- (void)updateEqualizerBadge {
    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    BOOL enabled = SonoraArtworkEqualizerEnabledFromDefaults();
    BOOL hasTrack = (playback.currentTrack != nil);
    BOOL isPlaceholder = [self isMiniStreamingPlaceholderTrack:playback.currentTrack];
    BOOL visible = enabled && hasTrack && !isPlaceholder;
    self.equalizerBadgeView.hidden = !visible;
    if (!visible) {
        [self.equalizerBadgeView setPlaying:NO];
        [self.equalizerBadgeView setLevel:0.0];
        return;
    }

    BOOL isPlaying = playback.isPlaying;
    [self.equalizerBadgeView setPlaying:isPlaying];
    [self.equalizerBadgeView setLevel:isPlaying ? 0.18 : 0.06];
}

- (void)updateArtworkLoadingOverlayForTrack:(SonoraTrack * _Nullable)track {
    BOOL isMiniStreamingPlaceholder = [self isMiniStreamingPlaceholderTrack:track];
    self.artworkLoadingOverlayView.hidden = !isMiniStreamingPlaceholder;
    if (isMiniStreamingPlaceholder) {
        [self.artworkLoadingSpinner startAnimating];
    } else {
        [self.artworkLoadingSpinner stopAnimating];
    }
}

- (BOOL)isMiniStreamingPlaceholderTrack:(SonoraTrack * _Nullable)track {
    if (track == nil || track.identifier.length == 0) {
        return NO;
    }
    if (![track.identifier hasPrefix:SonoraMiniStreamingPlaceholderPrefix]) {
        return NO;
    }

    NSURL *url = track.url;
    if (url == nil) {
        return YES;
    }
    if (!url.isFileURL) {
        return NO;
    }

    NSString *path = url.path ?: @"";
    return path.length == 0 || [path isEqualToString:@"/dev/null"];
}

- (void)handlePlaybackMeterChanged:(NSNotification *)notification {
    if (self.equalizerBadgeView.hidden) {
        return;
    }

    NSNumber *levelNumber = notification.userInfo[@"level"];
    CGFloat level = [levelNumber isKindOfClass:NSNumber.class] ? (CGFloat)levelNumber.doubleValue : 0.0;
    BOOL isPlaying = SonoraPlaybackManager.sharedManager.isPlaying;
    [self.equalizerBadgeView setPlaying:isPlaying];
    [self.equalizerBadgeView setLevel:isPlaying ? level : 0.06];
}

- (void)sliderTouchDown {
    self.scrubbing = YES;
}

- (void)sliderChanged {
    self.elapsedLabel.text = SonoraFormatDuration(self.progressSlider.value);
}

- (void)sliderTouchUp {
    self.scrubbing = NO;
    [SonoraPlaybackManager.sharedManager seekToTime:self.progressSlider.value];
}

- (void)handleProgressChanged {
    if (!self.scrubbing) {
        [self refreshTimelineOnly];
    }
}

- (void)refreshTimelineOnly {
    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    NSTimeInterval duration = playback.duration;
    NSTimeInterval current = playback.currentTime;

    self.progressSlider.maximumValue = MAX(duration, 1.0);
    self.progressSlider.value = MIN(current, self.progressSlider.maximumValue);

    self.elapsedLabel.text = SonoraFormatDuration(current);
    self.durationLabel.text = SonoraFormatDuration(duration);
}

- (void)refreshUI {
    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    SonoraTrack *track = playback.currentTrack;

    if (track == nil) {
        self.artworkView.image = [UIImage systemImageNamed:@"music.note.list"];
        self.artworkView.contentMode = UIViewContentModeCenter;
        self.artworkView.tintColor = SonoraPlayerPrimaryColor();
        self.currentArtworkBackgroundColor = nil;
        [self updateArtworkLoadingOverlayForTrack:nil];

        self.subtitleLabel.text = @"";
        self.titleLabel.text = @"No track selected";
        self.nextPreviewLabel.text = @"Next: -";

        self.playPauseButton.enabled = NO;
        self.previousButton.enabled = NO;
        self.nextButton.enabled = NO;

        self.progressSlider.maximumValue = 1.0;
        self.progressSlider.value = 0.0;
        self.elapsedLabel.text = @"0:00";
        self.durationLabel.text = @"0:00";

        [self applyPlayerTheme];
        [self updatePlayPauseIcon];
        [self updateModeIcons];
        [self updateFavoriteButton];
        [self updateSleepTimerButton];
        return;
    }

    self.artworkView.contentMode = UIViewContentModeScaleAspectFill;
    self.artworkView.image = track.artwork;
    [self updateArtworkBasedBackgroundForTrack:track];
    [self updateArtworkLoadingOverlayForTrack:track];

    self.subtitleLabel.text = (track.artist.length > 0 ? track.artist : @"");
    self.titleLabel.text = (track.title.length > 0 ? track.title : track.fileName);
    self.nextPreviewLabel.text = [self nextPreviewText];

    self.playPauseButton.enabled = YES;
    self.previousButton.enabled = YES;
    self.nextButton.enabled = YES;

    [self refreshTimelineOnly];
    [self applyPlayerTheme];
    [self updatePlayPauseIcon];
    [self updateModeIcons];
    [self updateFavoriteButton];
    [self updateSleepTimerButton];
}

- (NSString *)nextPreviewText {
    SonoraTrack *nextTrack = [SonoraPlaybackManager.sharedManager predictedNextTrackForSkip];

    if (nextTrack == nil) {
        return @"Next: -";
    }

    NSString *title = (nextTrack.title.length > 0 ? nextTrack.title : @"Unknown");
    if (nextTrack.artist.length > 0) {
        return [NSString stringWithFormat:@"Next: %@ - %@", nextTrack.artist, title];
    }
    return [NSString stringWithFormat:@"Next: %@", title];
}

- (void)updatePlayPauseIcon {
    NSString *symbol = SonoraPlaybackManager.sharedManager.isPlaying ? @"pause.fill" : @"play.fill";
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:56.0
                                                                                           weight:UIImageSymbolWeightBold];
    [self.playPauseButton setImage:[UIImage systemImageNamed:symbol withConfiguration:config] forState:UIControlStateNormal];
}

- (void)updateModeIcons {
    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    UIColor *inactiveColor = SonoraPlayerPrimaryColor();

    self.shuffleButton.tintColor = playback.isShuffleEnabled ? SonoraAccentYellowColor() : inactiveColor;

    NSString *repeatSymbol = @"repeat";
    switch (playback.repeatMode) {
        case SonoraRepeatModeNone:
            repeatSymbol = @"repeat";
            self.repeatButton.tintColor = inactiveColor;
            break;
        case SonoraRepeatModeQueue:
            repeatSymbol = @"repeat";
            self.repeatButton.tintColor = SonoraAccentYellowColor();
            break;
        case SonoraRepeatModeTrack:
            repeatSymbol = @"repeat.1";
            self.repeatButton.tintColor = SonoraAccentYellowColor();
            break;
    }

    UIImageSymbolConfiguration *repeatConfig = [UIImageSymbolConfiguration configurationWithPointSize:24.0
                                                                                                 weight:UIImageSymbolWeightSemibold];
    [self.repeatButton setImage:[UIImage systemImageNamed:repeatSymbol withConfiguration:repeatConfig] forState:UIControlStateNormal];
}

@end
