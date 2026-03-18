//
//  SonoraHomeViewController.m
//  Sonora
//

#import "SonoraHomeViewController.h"

#import <limits.h>
#import <math.h>
#import <QuartzCore/QuartzCore.h>

#import "SonoraCells.h"
#import "SonoraHistoryViewController.h"
#import "SonoraHomeAlbumDetailViewController.h"
#import "SonoraWaveBackgroundViews.h"
#import "SonoraPlayerViewController.h"
#import "SonoraSettingsViewController.h"
#import "SonoraSettings.h"
#import "SonoraServices.h"

static NSString * const SonoraHomeRecommendationCellReuseID = @"SonoraHomeRecommendationCell";
static NSString * const SonoraHomeHeroRecommendationCellReuseID = @"SonoraHomeHeroRecommendationCell";
static NSString * const SonoraHomeLastAddedCellReuseID = @"SonoraHomeLastAddedCell";
static NSString * const SonoraHomeAlbumCellReuseID = @"SonoraHomeAlbumCell";
static NSString * const SonoraHomeSectionHeaderReuseID = @"SonoraHomeSectionHeader";
static NSString * const SonoraHomeSectionHeaderKind = @"SonoraHomeSectionHeaderKind";

typedef NS_ENUM(NSInteger, SonoraHomeSectionType) {
    SonoraHomeSectionTypeForYou = 0,
    SonoraHomeSectionTypeYouNeedThis = 1,
    SonoraHomeSectionTypeFreshCuts = 2,
};

static UIFont *SonoraYSMusicFont(CGFloat size) {
    UIFont *font = [UIFont fontWithName:@"YSMusic-HeadlineBold" size:size];
    if (font != nil) {
        return font;
    }
    return [UIFont boldSystemFontOfSize:size];
}

static UIFont *SonoraNotoSerifBoldFont(CGFloat size) {
    UIFont *font = [UIFont fontWithName:@"FONTSPRINGDEMO-TTCommonsProExpExtraBoldRegular" size:size];
    if (font != nil) {
        return font;
    }
    font = [UIFont fontWithName:@"TTCommonsProExp-ExtraBold" size:size];
    if (font != nil) {
        return font;
    }
    return [UIFont systemFontOfSize:size weight:UIFontWeightBold];
}

static UIView *SonoraHomeNavigationTitleView(NSString *text) {
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = text;
    titleLabel.textColor = UIColor.labelColor;
    titleLabel.font = SonoraYSMusicFont(30.0);
    [titleLabel sizeToFit];

    if (@available(iOS 26.0, *)) {
        CGFloat horizontalPadding = 10.0;
        CGFloat width = ceil(CGRectGetWidth(titleLabel.bounds)) + (horizontalPadding * 2.0);
        CGFloat height = ceil(CGRectGetHeight(titleLabel.bounds));
        UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, width, height)];
        titleLabel.frame = CGRectMake(horizontalPadding, 0.0, ceil(CGRectGetWidth(titleLabel.bounds)), height);
        [container addSubview:titleLabel];
        return container;
    }
    return titleLabel;
}

static NSDate *SonoraTrackModifiedDate(SonoraTrack *track) {
    if (track.url == nil) {
        return [NSDate dateWithTimeIntervalSince1970:0];
    }

    NSDate *modifiedDate = nil;
    [track.url getResourceValue:&modifiedDate forKey:NSURLContentModificationDateKey error:nil];
    if (![modifiedDate isKindOfClass:NSDate.class]) {
        return [NSDate dateWithTimeIntervalSince1970:0];
    }
    return modifiedDate;
}

static NSString *SonoraDisplayTrackTitle(SonoraTrack *track) {
    if (track.title.length > 0) {
        return track.title;
    }
    if (track.fileName.length > 0) {
        return track.fileName.stringByDeletingPathExtension;
    }
    return @"Unknown track";
}

static NSString *SonoraDisplayTrackArtist(SonoraTrack *track) {
    if (track.artist.length > 0) {
        return track.artist;
    }
    return @"";
}

static NSString *SonoraNormalizedArtistText(NSString *artist) {
    NSString *value = [artist stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return value.lowercaseString ?: @"";
}


static double SonoraHomeStabilizedScore(NSInteger playCount, NSInteger skipCount, double rawScore) {
    double plays = MAX((double)playCount, 0.0);
    double skips = MAX((double)skipCount, 0.0);
    double interactions = plays + skips;
    double confidence = 1.0 - exp(-interactions / 4.5);
    double clampedRaw = MIN(MAX(rawScore, 0.0), 1.0);
    double smoothed = (clampedRaw * confidence) + (0.52 * (1.0 - confidence));
    double skipPenalty = (skips / (interactions + 1.0)) * 0.20;
    return MIN(MAX(smoothed - skipPenalty, 0.0), 1.0);
}

static double SonoraHomeBestTrackWeight(NSDictionary<NSString *, NSNumber *> *metrics, BOOL isFavorite) {
    NSInteger playCount = MAX([metrics[@"playCount"] integerValue], 0);
    NSInteger skipCount = MAX([metrics[@"skipCount"] integerValue], 0);
    double stabilized = SonoraHomeStabilizedScore(playCount, skipCount, [metrics[@"score"] doubleValue]);
    double playBoost = log1p((double)playCount) * 0.42;
    double skipPenalty = log1p((double)skipCount) * 0.30;
    double momentum = MIN(MAX(((double)playCount - (double)skipCount) / 20.0, -0.25), 0.35);
    double favoriteBoost = isFavorite ? 0.48 : 0.0;
    return MAX(0.05, 0.24 + (stabilized * 3.0) + playBoost - skipPenalty + momentum + favoriteBoost);
}

static void SonoraShuffleMutableArray(NSMutableArray *array) {
    if (array.count <= 1) {
        return;
    }

    for (NSInteger idx = array.count - 1; idx > 0; idx -= 1) {
        u_int32_t swapIdx = arc4random_uniform((u_int32_t)(idx + 1));
        [array exchangeObjectAtIndex:idx withObjectAtIndex:(NSUInteger)swapIdx];
    }
}

static UIViewController * _Nullable SonoraInstantiatePlayerViewController(void) {
    return [[SonoraPlayerViewController alloc] init];
}

@interface SonoraHomeAlbumItem : NSObject

@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) UIImage *artwork;
@property (nonatomic, strong) NSDate *latestDate;
@property (nonatomic, assign) NSInteger trackCount;
@property (nonatomic, copy) NSArray<SonoraTrack *> *tracks;

@end

@implementation SonoraHomeAlbumItem
@end

@interface SonoraHomeRecommendationCell : UICollectionViewCell

- (void)configureWithTrack:(SonoraTrack *)track;

@end

@interface SonoraHomeRecommendationCell ()

@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *artistLabel;

@end

@implementation SonoraHomeRecommendationCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.contentView.backgroundColor = UIColor.clearColor;

    UIImageView *coverView = [[UIImageView alloc] init];
    coverView.translatesAutoresizingMaskIntoConstraints = NO;
    coverView.contentMode = UIViewContentModeScaleAspectFill;
    coverView.clipsToBounds = YES;
    coverView.layer.cornerRadius = 12.0;
    self.coverView = coverView;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
    titleLabel.textColor = UIColor.labelColor;
    titleLabel.numberOfLines = 1;
    self.titleLabel = titleLabel;

    UILabel *artistLabel = [[UILabel alloc] init];
    artistLabel.translatesAutoresizingMaskIntoConstraints = NO;
    artistLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightRegular];
    artistLabel.textColor = UIColor.secondaryLabelColor;
    artistLabel.numberOfLines = 1;
    self.artistLabel = artistLabel;

    [self.contentView addSubview:coverView];
    [self.contentView addSubview:titleLabel];
    [self.contentView addSubview:artistLabel];

    [NSLayoutConstraint activateConstraints:@[
        [coverView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8.0],
        [coverView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:8.0],
        [coverView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8.0],
        [coverView.heightAnchor constraintEqualToAnchor:coverView.widthAnchor],

        [titleLabel.topAnchor constraintEqualToAnchor:coverView.bottomAnchor constant:10.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:10.0],
        [titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10.0],

        [artistLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:3.0],
        [artistLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [artistLabel.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
        [artistLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-10.0]
    ]];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.contentView.backgroundColor = UIColor.clearColor;
    self.coverView.image = nil;
    self.titleLabel.text = nil;
    self.artistLabel.text = nil;
    self.artistLabel.hidden = NO;
}

- (void)configureWithTrack:(SonoraTrack *)track {
    self.coverView.image = track.artwork;
    self.titleLabel.text = SonoraDisplayTrackTitle(track);
    NSString *artist = SonoraDisplayTrackArtist(track);
    self.artistLabel.text = artist;
    self.artistLabel.hidden = (artist.length == 0);
}

@end

static SonoraMyWaveLook SonoraCurrentMyWaveLook(void) {
    NSInteger storedValue = SonoraSettingsMyWaveLook();
    if (storedValue != SonoraMyWaveLookClouds && storedValue != SonoraMyWaveLookContours) {
        storedValue = SonoraMyWaveLookContours;
        SonoraSettingsSetMyWaveLook(storedValue);
    }
    return (SonoraMyWaveLook)storedValue;
}


@interface SonoraHomeHeroRecommendationCell : UICollectionViewCell

@property (nonatomic, copy, nullable) dispatch_block_t playHandler;
@property (nonatomic, copy, readonly, nullable) NSString *configuredTrackIdentifier;
- (void)configureWithTrack:(SonoraTrack *)track;
- (void)resumeWaveAnimationsIfNeeded;

@end

@interface SonoraHomeHeroRecommendationCell ()

@property (nonatomic, strong) UIView *waveBackgroundContainer;
@property (nonatomic, strong) SonoraWaveAnimatedBackgroundView *contourWaveBackgroundView;
@property (nonatomic, strong) SonoraWaveNebulaBackgroundView *nebulaWaveBackgroundView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, assign) BOOL playing;
@property (nonatomic, copy) NSString *configuredTrackIdentifier;

@end

@implementation SonoraHomeHeroRecommendationCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.contentView.backgroundColor = UIColor.clearColor;
    self.contentView.layer.cornerRadius = 0.0;
    self.contentView.layer.masksToBounds = YES;

    UIView *waveBackgroundContainer = [[UIView alloc] init];
    waveBackgroundContainer.translatesAutoresizingMaskIntoConstraints = NO;
    waveBackgroundContainer.userInteractionEnabled = NO;
    self.waveBackgroundContainer = waveBackgroundContainer;

    SonoraWaveNebulaBackgroundView *nebulaWaveBackgroundView = [[SonoraWaveNebulaBackgroundView alloc] init];
    nebulaWaveBackgroundView.translatesAutoresizingMaskIntoConstraints = NO;
    self.nebulaWaveBackgroundView = nebulaWaveBackgroundView;

    SonoraWaveAnimatedBackgroundView *contourWaveBackgroundView = [[SonoraWaveAnimatedBackgroundView alloc] init];
    contourWaveBackgroundView.translatesAutoresizingMaskIntoConstraints = NO;
    self.contourWaveBackgroundView = contourWaveBackgroundView;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = SonoraNotoSerifBoldFont(28.0);
    titleLabel.textColor = UIColor.labelColor;
    titleLabel.numberOfLines = 2;
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    titleLabel.text = @"";
    self.titleLabel = titleLabel;

    UIButton *playButton = [UIButton buttonWithType:UIButtonTypeSystem];
    playButton.translatesAutoresizingMaskIntoConstraints = NO;
    playButton.backgroundColor = UIColor.clearColor;
    playButton.layer.cornerRadius = 0.0;
    playButton.layer.masksToBounds = NO;
    playButton.tintColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
        return [UIColor.labelColor colorWithAlphaComponent:(trait.userInterfaceStyle == UIUserInterfaceStyleLight ? 0.88 : 0.96)];
    }];
    [playButton setTitleColor:playButton.tintColor forState:UIControlStateNormal];
    playButton.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    playButton.titleLabel.lineBreakMode = NSLineBreakByClipping;
    playButton.titleLabel.adjustsFontSizeToFitWidth = NO;
    playButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    playButton.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    UIButtonConfiguration *playButtonConfiguration = [UIButtonConfiguration plainButtonConfiguration];
    playButtonConfiguration.contentInsets = NSDirectionalEdgeInsetsZero;
    playButtonConfiguration.imagePadding = 10.0;
    playButtonConfiguration.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey,id> * _Nonnull(NSDictionary<NSAttributedStringKey,id> * _Nonnull incoming) {
        NSMutableDictionary<NSAttributedStringKey, id> *attributes = [incoming mutableCopy] ?: [NSMutableDictionary dictionary];
        attributes[NSFontAttributeName] = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
        return attributes.copy;
    };
    playButton.configuration = playButtonConfiguration;
    [playButton addTarget:self action:@selector(playButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    self.playButton = playButton;

    [waveBackgroundContainer addSubview:nebulaWaveBackgroundView];
    [waveBackgroundContainer addSubview:contourWaveBackgroundView];
    [self.contentView addSubview:waveBackgroundContainer];
    [self.contentView addSubview:titleLabel];
    [self.contentView addSubview:playButton];

    [NSLayoutConstraint activateConstraints:@[
        [waveBackgroundContainer.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:24.0],
        [waveBackgroundContainer.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:8.0],
        [waveBackgroundContainer.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8.0],
        [waveBackgroundContainer.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-16.0],

        [nebulaWaveBackgroundView.topAnchor constraintEqualToAnchor:waveBackgroundContainer.topAnchor],
        [nebulaWaveBackgroundView.leadingAnchor constraintEqualToAnchor:waveBackgroundContainer.leadingAnchor],
        [nebulaWaveBackgroundView.trailingAnchor constraintEqualToAnchor:waveBackgroundContainer.trailingAnchor],
        [nebulaWaveBackgroundView.bottomAnchor constraintEqualToAnchor:waveBackgroundContainer.bottomAnchor],

        [contourWaveBackgroundView.topAnchor constraintEqualToAnchor:waveBackgroundContainer.topAnchor],
        [contourWaveBackgroundView.leadingAnchor constraintEqualToAnchor:waveBackgroundContainer.leadingAnchor],
        [contourWaveBackgroundView.trailingAnchor constraintEqualToAnchor:waveBackgroundContainer.trailingAnchor],
        [contourWaveBackgroundView.bottomAnchor constraintEqualToAnchor:waveBackgroundContainer.bottomAnchor],

        [titleLabel.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        [titleLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor constant:-22.0],
        [titleLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.leadingAnchor constant:18.0],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-18.0],

        [playButton.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        [playButton.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:12.0],
        [playButton.heightAnchor constraintEqualToConstant:38.0],
        [playButton.widthAnchor constraintGreaterThanOrEqualToConstant:92.0]
    ]];
    [self updateThemeColors];
    [self updatePlayButton];
    [self updateWaveLookAnimated:NO];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.titleLabel.text = @"";
    self.playHandler = nil;
    self.playing = NO;
    self.configuredTrackIdentifier = nil;
    [self.contourWaveBackgroundView setPlaying:NO];
    [self.nebulaWaveBackgroundView setPlaying:NO];
    [self updatePlayButton];
    [self updateWaveLookAnimated:NO];
}

- (void)playButtonTapped {
    if (self.playHandler != nil) {
        self.playHandler();
    }
}

- (void)configureWithTrack:(SonoraTrack *)track {
    self.configuredTrackIdentifier = track.identifier ?: @"";
    NSArray<UIColor *> *palette = SonoraResolvedWavePalette(track.artwork);
    self.titleLabel.text = SonoraDisplayTrackTitle(track);
    [self updateThemeColors];
    [self updateWaveLookAnimated:NO];
    if (SonoraCurrentMyWaveLook() == SonoraMyWaveLookClouds) {
        [self.contourWaveBackgroundView setPlaying:NO];
        [self.nebulaWaveBackgroundView setPulseSeedWithTrackIdentifier:track.identifier];
        [self.nebulaWaveBackgroundView setPlaying:self.playing];
        [self.nebulaWaveBackgroundView applyPalette:palette animated:YES];
    } else {
        [self.nebulaWaveBackgroundView setPlaying:NO];
        [self.contourWaveBackgroundView setPulseSeedWithTrackIdentifier:track.identifier];
        [self.contourWaveBackgroundView setPlaying:self.playing];
        [self.contourWaveBackgroundView applyPalette:palette animated:YES];
    }
}

- (void)resumeWaveAnimationsIfNeeded {
    if (SonoraCurrentMyWaveLook() == SonoraMyWaveLookContours) {
        [self.contourWaveBackgroundView ensureAnimationsRunning];
    }
}

- (void)setPlaying:(BOOL)playing {
    _playing = playing;
    if (SonoraCurrentMyWaveLook() == SonoraMyWaveLookClouds) {
        [self.contourWaveBackgroundView setPlaying:NO];
        [self.nebulaWaveBackgroundView setPlaying:playing];
    } else {
        [self.nebulaWaveBackgroundView setPlaying:NO];
        [self.contourWaveBackgroundView setPlaying:playing];
    }
    [self updatePlayButton];
}

- (void)updatePlayButton {
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:13.0
                                                                                          weight:UIImageSymbolWeightSemibold];
    NSString *symbol = self.playing ? @"pause.fill" : @"play.fill";
    NSString *title = self.playing ? @"Pause" : @"Play";
    UIImage *image = [UIImage systemImageNamed:symbol withConfiguration:config];
    UIButtonConfiguration *buttonConfiguration = self.playButton.configuration ?: [UIButtonConfiguration plainButtonConfiguration];
    buttonConfiguration.image = image;
    buttonConfiguration.title = title;
    self.playButton.configuration = buttonConfiguration;
}

- (void)updateThemeColors {
    self.titleLabel.textColor = UIColor.labelColor;
    UIColor *buttonColor = [UIColor.labelColor colorWithAlphaComponent:(self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleLight ? 0.88 : 0.96)];
    self.playButton.tintColor = buttonColor;
    UIButtonConfiguration *buttonConfiguration = self.playButton.configuration ?: [UIButtonConfiguration plainButtonConfiguration];
    buttonConfiguration.baseForegroundColor = buttonColor;
    self.playButton.configuration = buttonConfiguration;
}

- (void)updateWaveLookAnimated:(BOOL)animated {
    UIView *showView = (SonoraCurrentMyWaveLook() == SonoraMyWaveLookClouds) ? self.nebulaWaveBackgroundView : self.contourWaveBackgroundView;
    UIView *hideView = (SonoraCurrentMyWaveLook() == SonoraMyWaveLookClouds) ? self.contourWaveBackgroundView : self.nebulaWaveBackgroundView;
    hideView.hidden = NO;
    showView.hidden = NO;

    void (^changes)(void) = ^{
        showView.alpha = 1.0f;
        hideView.alpha = 0.0f;
    };

    if (animated) {
        [UIView animateWithDuration:0.26
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState
                         animations:changes
                         completion:^(__unused BOOL finished) {
            hideView.hidden = YES;
        }];
    } else {
        changes();
        hideView.hidden = YES;
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (@available(iOS 13.0, *)) {
        if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
            [self updateThemeColors];
            [self updateWaveLookAnimated:NO];
        }
    }
}

@end

@interface SonoraHomeLastAddedCell : UICollectionViewCell

- (void)configureWithTrack:(SonoraTrack *)track;

@end

@interface SonoraHomeLastAddedCell ()

@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *artistLabel;

@end

@implementation SonoraHomeLastAddedCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.contentView.backgroundColor = UIColor.clearColor;
    self.contentView.layer.cornerRadius = 18.0;
    self.contentView.layer.masksToBounds = YES;

    UIImageView *coverView = [[UIImageView alloc] init];
    coverView.translatesAutoresizingMaskIntoConstraints = NO;
    coverView.contentMode = UIViewContentModeScaleAspectFill;
    coverView.clipsToBounds = YES;
    coverView.layer.cornerRadius = 12.0;
    self.coverView = coverView;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    titleLabel.textColor = UIColor.labelColor;
    titleLabel.numberOfLines = 1;
    self.titleLabel = titleLabel;

    UILabel *artistLabel = [[UILabel alloc] init];
    artistLabel.translatesAutoresizingMaskIntoConstraints = NO;
    artistLabel.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightRegular];
    artistLabel.textColor = UIColor.secondaryLabelColor;
    artistLabel.numberOfLines = 1;
    self.artistLabel = artistLabel;

    [self.contentView addSubview:coverView];
    [self.contentView addSubview:titleLabel];
    [self.contentView addSubview:artistLabel];

    [NSLayoutConstraint activateConstraints:@[
        [coverView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:8.0],
        [coverView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [coverView.widthAnchor constraintEqualToConstant:48.0],
        [coverView.heightAnchor constraintEqualToConstant:48.0],

        [titleLabel.leadingAnchor constraintEqualToAnchor:coverView.trailingAnchor constant:10.0],
        [titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10.0],
        [titleLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor constant:-7.0],

        [artistLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [artistLabel.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
        [artistLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:1.0]
    ]];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.contentView.backgroundColor = UIColor.clearColor;
    self.coverView.image = nil;
    self.titleLabel.text = nil;
    self.artistLabel.text = nil;
    self.artistLabel.hidden = NO;
}

- (void)configureWithTrack:(SonoraTrack *)track {
    UIColor *accentColor = [SonoraArtworkAccentColorService dominantAccentColorForImage:track.artwork
                                                                            fallback:UIColor.systemGrayColor];
    self.contentView.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
        CGFloat alpha = (trait.userInterfaceStyle == UIUserInterfaceStyleDark) ? 0.19 : 0.11;
        return [accentColor colorWithAlphaComponent:alpha];
    }];

    self.coverView.image = track.artwork;
    self.titleLabel.text = SonoraDisplayTrackTitle(track);
    NSString *artist = SonoraDisplayTrackArtist(track);
    self.artistLabel.text = artist;
    self.artistLabel.hidden = (artist.length == 0);
}

@end

@interface SonoraHomeAlbumCell : UICollectionViewCell

- (void)configureWithAlbumItem:(SonoraHomeAlbumItem *)albumItem;

@end

@interface SonoraHomeAlbumCell ()

@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *titleLabel;

@end

@implementation SonoraHomeAlbumCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.contentView.backgroundColor = UIColor.clearColor;

    UIImageView *coverView = [[UIImageView alloc] init];
    coverView.translatesAutoresizingMaskIntoConstraints = NO;
    coverView.contentMode = UIViewContentModeScaleAspectFill;
    coverView.layer.cornerRadius = 12.0;
    coverView.layer.masksToBounds = YES;
    self.coverView = coverView;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightRegular];
    titleLabel.textColor = UIColor.labelColor;
    titleLabel.numberOfLines = 2;
    self.titleLabel = titleLabel;

    [self.contentView addSubview:coverView];
    [self.contentView addSubview:titleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [coverView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
        [coverView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [coverView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [coverView.heightAnchor constraintEqualToAnchor:coverView.widthAnchor],

        [titleLabel.topAnchor constraintEqualToAnchor:coverView.bottomAnchor constant:7.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:2.0],
        [titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-2.0],
        [titleLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor]
    ]];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.coverView.image = nil;
    self.titleLabel.text = nil;
}

- (void)configureWithAlbumItem:(SonoraHomeAlbumItem *)albumItem {
    self.coverView.image = albumItem.artwork;
    self.titleLabel.text = albumItem.title;
}

@end

@interface SonoraHomeSectionHeaderView : UICollectionReusableView

- (void)configureWithTitle:(NSString *)title;

@end

@interface SonoraHomeSectionHeaderView ()

@property (nonatomic, strong) UILabel *titleLabel;

@end

@implementation SonoraHomeSectionHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.textColor = UIColor.labelColor;
    titleLabel.font = SonoraNotoSerifBoldFont(24.0);
    titleLabel.textAlignment = NSTextAlignmentLeft;
    self.titleLabel = titleLabel;

    [self addSubview:titleLabel];
    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [titleLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-2.0]
    ]];
}

- (void)configureWithTitle:(NSString *)title {
    self.titleLabel.text = title;
}

@end


@interface SonoraHomeViewController () <UICollectionViewDataSource, UICollectionViewDelegate>

@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, copy) NSArray<SonoraTrack *> *allTracks;
@property (nonatomic, copy) NSArray<SonoraTrack *> *recommendationTracks;
@property (nonatomic, copy) NSArray<SonoraTrack *> *needThisTracks;
@property (nonatomic, copy) NSArray<SonoraTrack *> *freshTracks;
@property (nonatomic, copy) NSString *lastForYouTopTrackID;
@property (nonatomic, copy) NSString *forYouSelectedTrackID;
@property (nonatomic, copy) NSString *homeRecommendationsSessionSignature;
@property (nonatomic, assign) NSUInteger reloadGeneration;
@property (nonatomic, assign) NSInteger forYouSelectionVisit;
@property (nonatomic, assign) NSInteger homeVisitCount;
@property (nonatomic, assign) BOOL hasLoadedInitialHomeContent;

@end

@implementation SonoraHomeViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupNavigationBar];
    [self setupCollectionView];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(reloadHomeContent)
                                               name:UIApplicationWillEnterForegroundNotification
                                             object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(reloadHomeContent)
                                               name:SonoraFavoritesDidChangeNotification
                                             object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handlePlaybackStateChanged)
                                               name:SonoraPlaybackStateDidChangeNotification
                                             object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handlePlayerSettingsChanged)
                                               name:SonoraPlayerSettingsDidChangeNotification
                                             object:nil];
    self.forYouSelectionVisit = NSIntegerMin;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)handlePlaybackStateChanged {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self handlePlaybackStateChanged];
        });
        return;
    }

    UICollectionView *collectionView = self.collectionView;
    if (collectionView == nil || self.viewIfLoaded.window == nil) {
        return;
    }

    if (self.recommendationTracks.count > 0) {
        [self refreshVisibleWaveCellIfNeededPreservingWaveProgress:YES];
    } else {
        [collectionView reloadData];
    }
}

- (void)handlePlayerSettingsChanged {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self handlePlayerSettingsChanged];
        });
        return;
    }

    if (self.collectionView == nil) {
        return;
    }

    if (self.recommendationTracks.count > 0) {
        NSIndexSet *sections = [NSIndexSet indexSetWithIndex:SonoraHomeSectionTypeForYou];
        [self.collectionView reloadSections:sections];
    } else {
        [self.collectionView reloadData];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self applyTransparentNavigationBarAppearance];
    if (!self.hasLoadedInitialHomeContent) {
        self.hasLoadedInitialHomeContent = YES;
        self.homeVisitCount += 1;
        [self reloadHomeContent];
        return;
    }
    [self refreshVisibleWaveCellIfNeededPreservingWaveProgress:YES];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self refreshVisibleWaveCellIfNeededPreservingWaveProgress:YES];
}

- (void)applyTransparentNavigationBarAppearance {
    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithTransparentBackground];
        appearance.backgroundColor = UIColor.clearColor;
        appearance.shadowColor = UIColor.clearColor;
        self.navigationItem.standardAppearance = appearance;
        self.navigationItem.scrollEdgeAppearance = appearance;
        self.navigationItem.compactAppearance = appearance;
        if (@available(iOS 15.0, *)) {
            self.navigationItem.compactScrollEdgeAppearance = appearance;
        }
    }
}

- (void)setupNavigationBar {
    self.title = nil;
    self.navigationItem.title = nil;
    self.navigationItem.titleView = nil;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    [self applyTransparentNavigationBarAppearance];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:SonoraHomeNavigationTitleView(@"Home")];

    UIBarButtonItem *clockItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"clock"]
                                                                   style:UIBarButtonItemStylePlain
                                                                  target:self
                                                                  action:@selector(openHistoryTapped)];
    clockItem.title = @"History";
    clockItem.accessibilityLabel = @"History";
    UIBarButtonItem *settingsItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"gearshape"]
                                                                      style:UIBarButtonItemStylePlain
                                                                     target:self
                                                                     action:@selector(openSettingsTapped)];
    settingsItem.title = @"Settings";
    settingsItem.accessibilityLabel = @"Settings";
    self.navigationItem.rightBarButtonItems = @[settingsItem, clockItem];
}

- (void)setupCollectionView {
    UICollectionViewCompositionalLayout *layout = [self buildLayout];
    UICollectionView *collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero
                                                           collectionViewLayout:layout];
    collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    collectionView.backgroundColor = UIColor.systemBackgroundColor;
    collectionView.alwaysBounceVertical = YES;
    collectionView.dataSource = self;
    collectionView.delegate = self;
    collectionView.contentInset = UIEdgeInsetsMake(10.0, 0.0, 18.0, 0.0);

    [collectionView registerClass:SonoraHomeRecommendationCell.class forCellWithReuseIdentifier:SonoraHomeRecommendationCellReuseID];
    [collectionView registerClass:SonoraHomeHeroRecommendationCell.class forCellWithReuseIdentifier:SonoraHomeHeroRecommendationCellReuseID];
    [collectionView registerClass:SonoraHomeLastAddedCell.class forCellWithReuseIdentifier:SonoraHomeLastAddedCellReuseID];
    [collectionView registerClass:SonoraHomeAlbumCell.class forCellWithReuseIdentifier:SonoraHomeAlbumCellReuseID];
    [collectionView registerClass:SonoraHomeSectionHeaderView.class
       forSupplementaryViewOfKind:SonoraHomeSectionHeaderKind
              withReuseIdentifier:SonoraHomeSectionHeaderReuseID];

    self.collectionView = collectionView;
    [self.view addSubview:collectionView];

    [NSLayoutConstraint activateConstraints:@[
        [collectionView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (UICollectionViewCompositionalLayout *)buildLayout {
    __weak typeof(self) weakSelf = self;
    UICollectionViewCompositionalLayout *layout = [[UICollectionViewCompositionalLayout alloc]
                                                    initWithSectionProvider:^NSCollectionLayoutSection * _Nullable(NSInteger sectionIndex,
                                                                                                                   id<NSCollectionLayoutEnvironment> _Nonnull layoutEnvironment) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return nil;
        }
        return [strongSelf layoutSectionForIndex:sectionIndex environment:layoutEnvironment];
    }];
    return layout;
}

- (NSCollectionLayoutBoundarySupplementaryItem *)sectionHeaderItem {
    NSCollectionLayoutSize *headerSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                                                         heightDimension:[NSCollectionLayoutDimension estimatedDimension:36.0]];
    NSCollectionLayoutBoundarySupplementaryItem *header = [NSCollectionLayoutBoundarySupplementaryItem
                                                           boundarySupplementaryItemWithLayoutSize:headerSize
                                                           elementKind:SonoraHomeSectionHeaderKind
                                                           alignment:NSRectAlignmentTop];
    header.contentInsets = NSDirectionalEdgeInsetsMake(0.0, 8.0, 0.0, 18.0);
    return header;
}

- (NSCollectionLayoutSection *)layoutSectionForIndex:(NSInteger)sectionIndex
                                          environment:(id<NSCollectionLayoutEnvironment>)layoutEnvironment {
    CGFloat containerHeight = layoutEnvironment.container.effectiveContentSize.height;
    CGFloat heroHeight = MAX(300.0, MIN(420.0, containerHeight * 0.56));

    switch ((SonoraHomeSectionType)sectionIndex) {
        case SonoraHomeSectionTypeForYou:
            return [self forYouSectionLayoutWithHeight:heroHeight];
        case SonoraHomeSectionTypeYouNeedThis:
            return [self lastAddedSectionLayout];
        case SonoraHomeSectionTypeFreshCuts:
            return [self recommendationsSectionLayout];
    }
    return [self recommendationsSectionLayout];
}

- (NSCollectionLayoutSection *)forYouSectionLayoutWithHeight:(CGFloat)height {
    NSCollectionLayoutSize *itemSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:height]];
    NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];

    NSCollectionLayoutSize *groupSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                                                        heightDimension:[NSCollectionLayoutDimension absoluteDimension:height]];
    NSCollectionLayoutGroup *group = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize
                                                                                     subitems:@[item]];

    NSCollectionLayoutSection *section = [NSCollectionLayoutSection sectionWithGroup:group];
    section.interGroupSpacing = 0.0;
    section.contentInsets = NSDirectionalEdgeInsetsMake(0.0, 0.0, 12.0, 0.0);
    section.orthogonalScrollingBehavior = UICollectionLayoutSectionOrthogonalScrollingBehaviorNone;
    return section;
}

- (NSCollectionLayoutSection *)recommendationsSectionLayout {
    NSCollectionLayoutSize *itemSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:184.0]
                                                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:246.0]];
    NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];

    NSCollectionLayoutSize *groupSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:184.0]
                                                                        heightDimension:[NSCollectionLayoutDimension absoluteDimension:246.0]];
    NSCollectionLayoutGroup *group = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize
                                                                                     subitems:@[item]];

    NSCollectionLayoutSection *section = [NSCollectionLayoutSection sectionWithGroup:group];
    section.interGroupSpacing = 12.0;
    section.contentInsets = NSDirectionalEdgeInsetsMake(6.0, 18.0, 12.0, 18.0);
    section.orthogonalScrollingBehavior = UICollectionLayoutSectionOrthogonalScrollingBehaviorContinuousGroupLeadingBoundary;
    section.boundarySupplementaryItems = @[[self sectionHeaderItem]];
    return section;
}

- (NSCollectionLayoutSection *)lastAddedSectionLayout {
    NSCollectionLayoutSize *itemSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:66.0]];
    NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];

    NSCollectionLayoutSize *groupSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:304.0]
                                                                        heightDimension:[NSCollectionLayoutDimension absoluteDimension:140.0]];
    NSCollectionLayoutGroup *group = [NSCollectionLayoutGroup verticalGroupWithLayoutSize:groupSize
                                                                         repeatingSubitem:item
                                                                                      count:2];
    group.interItemSpacing = [NSCollectionLayoutSpacing fixedSpacing:8.0];

    NSCollectionLayoutSection *section = [NSCollectionLayoutSection sectionWithGroup:group];
    section.interGroupSpacing = 12.0;
    section.contentInsets = NSDirectionalEdgeInsetsMake(6.0, 18.0, 12.0, 18.0);
    section.orthogonalScrollingBehavior = UICollectionLayoutSectionOrthogonalScrollingBehaviorContinuousGroupLeadingBoundary;
    section.boundarySupplementaryItems = @[[self sectionHeaderItem]];
    return section;
}

- (NSCollectionLayoutSection *)albumsSectionLayout {
    NSCollectionLayoutSize *itemSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:126.0]
                                                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:166.0]];
    NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];

    NSCollectionLayoutSize *groupSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:126.0]
                                                                        heightDimension:[NSCollectionLayoutDimension absoluteDimension:166.0]];
    NSCollectionLayoutGroup *group = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize
                                                                                     subitems:@[item]];

    NSCollectionLayoutSection *section = [NSCollectionLayoutSection sectionWithGroup:group];
    section.interGroupSpacing = 12.0;
    section.contentInsets = NSDirectionalEdgeInsetsMake(6.0, 18.0, 12.0, 18.0);
    section.orthogonalScrollingBehavior = UICollectionLayoutSectionOrthogonalScrollingBehaviorContinuousGroupLeadingBoundary;
    section.boundarySupplementaryItems = @[[self sectionHeaderItem]];
    return section;
}

- (void)reloadHomeContent {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self reloadHomeContent];
        });
        return;
    }

    NSUInteger reloadGeneration = ++self.reloadGeneration;
    NSArray<SonoraTrack *> *existingRecommendationTracks = self.recommendationTracks ?: @[];
    NSArray<SonoraTrack *> *existingNeedThisTracks = self.needThisTracks ?: @[];
    NSArray<SonoraTrack *> *existingFreshTracks = self.freshTracks ?: @[];
    NSString *existingSessionSignature = self.homeRecommendationsSessionSignature ?: @"";
    NSString *existingRecommendationSignature = [self recommendationsSessionSignatureForTracks:existingRecommendationTracks];
    NSString *existingNeedThisSignature = [self recommendationsSessionSignatureForTracks:existingNeedThisTracks];
    NSString *existingFreshSignature = [self recommendationsSessionSignatureForTracks:existingFreshTracks];
    BOOL hadTracks = self.allTracks.count > 0;

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        NSArray<SonoraTrack *> *tracks = SonoraLibraryManager.sharedManager.tracks;
        if (tracks.count == 0) {
            tracks = [SonoraLibraryManager.sharedManager reloadTracks];
        }

        NSArray<SonoraTrack *> *allTracks = tracks ?: @[];
        NSArray<SonoraTrack *> *recommendationTracks = [strongSelf buildForYouTracksFromTracks:allTracks limit:120];
        NSString *sessionSignature = [strongSelf recommendationsSessionSignatureForTracks:allTracks];
        BOOL shouldRefreshRecommendations =
        (existingNeedThisTracks.count == 0 ||
         existingFreshTracks.count == 0 ||
         ![existingSessionSignature isEqualToString:sessionSignature]);

        NSArray<SonoraTrack *> *needThisTracks = existingNeedThisTracks;
        NSArray<SonoraTrack *> *freshTracks = existingFreshTracks;
        if (shouldRefreshRecommendations) {
            needThisTracks = [strongSelf buildRecommendationsFromTracks:allTracks limit:12];
            freshTracks = [strongSelf buildFreshChoiceTracksFromTracks:allTracks limit:12];
        }
        NSString *recommendationSignature = [strongSelf recommendationsSessionSignatureForTracks:recommendationTracks];
        NSString *needThisSignature = [strongSelf recommendationsSessionSignatureForTracks:needThisTracks];
        NSString *freshSignature = [strongSelf recommendationsSessionSignatureForTracks:freshTracks];
        BOOL contentUnchanged =
        (hadTracks == (allTracks.count > 0)) &&
        [existingRecommendationSignature isEqualToString:recommendationSignature] &&
        [existingNeedThisSignature isEqualToString:needThisSignature] &&
        [existingFreshSignature isEqualToString:freshSignature];

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) innerSelf = weakSelf;
            if (innerSelf == nil || reloadGeneration != innerSelf.reloadGeneration) {
                return;
            }

            innerSelf.allTracks = allTracks;
            innerSelf.recommendationTracks = recommendationTracks;
            innerSelf.needThisTracks = needThisTracks;
            innerSelf.freshTracks = freshTracks;
            innerSelf.homeRecommendationsSessionSignature = sessionSignature;

            if (contentUnchanged) {
                [innerSelf refreshVisibleWaveCellIfNeededPreservingWaveProgress:YES];
                [innerSelf updateEmptyStateIfNeeded];
                return;
            }

            [innerSelf.collectionView reloadData];
            [innerSelf updateEmptyStateIfNeeded];
        });
    });
}

- (NSString *)recommendationsSessionSignatureForTracks:(NSArray<SonoraTrack *> *)tracks {
    if (tracks.count == 0) {
        return @"0";
    }

    NSMutableString *seed = [NSMutableString stringWithCapacity:(tracks.count * 18)];
    [seed appendFormat:@"%lu|", (unsigned long)tracks.count];
    for (SonoraTrack *track in tracks) {
        NSString *identifier = track.identifier;
        if (identifier.length > 0) {
            [seed appendString:identifier];
        } else if (track.url.lastPathComponent.length > 0) {
            [seed appendString:track.url.lastPathComponent];
        } else {
            [seed appendString:SonoraDisplayTrackTitle(track)];
        }
        [seed appendString:@"|"];
    }
    return SonoraStableHashString(seed) ?: @"0";
}

- (NSArray<SonoraTrack *> *)buildForYouTracksFromTracks:(NSArray<SonoraTrack *> *)tracks limit:(NSUInteger)limit {
    if (tracks.count == 0 || limit == 0) {
        return @[];
    }

    NSMutableArray<NSString *> *trackIDs = [NSMutableArray arrayWithCapacity:tracks.count];
    for (SonoraTrack *track in tracks) {
        if (track.identifier.length > 0) {
            [trackIDs addObject:track.identifier];
        }
    }
    NSDictionary<NSString *, NSDictionary<NSString *, NSNumber *> *> *analyticsByTrackID =
    [SonoraTrackAnalyticsStore.sharedStore analyticsByTrackIDForTrackIDs:trackIDs];
    NSSet<NSString *> *favoriteTrackIDs = [NSSet setWithArray:SonoraFavoritesStore.sharedStore.favoriteTrackIDs];

    NSArray<SonoraTrack *> *ranked = [tracks sortedArrayUsingComparator:^NSComparisonResult(SonoraTrack * _Nonnull left,
                                                                                         SonoraTrack * _Nonnull right) {
        NSDictionary<NSString *, NSNumber *> *leftMetrics = analyticsByTrackID[left.identifier] ?: @{};
        NSDictionary<NSString *, NSNumber *> *rightMetrics = analyticsByTrackID[right.identifier] ?: @{};
        double leftWeight = SonoraHomeBestTrackWeight(leftMetrics, [favoriteTrackIDs containsObject:left.identifier]);
        double rightWeight = SonoraHomeBestTrackWeight(rightMetrics, [favoriteTrackIDs containsObject:right.identifier]);
        NSInteger leftPlay = [leftMetrics[@"playCount"] integerValue];
        NSInteger rightPlay = [rightMetrics[@"playCount"] integerValue];
        NSInteger leftSkip = [leftMetrics[@"skipCount"] integerValue];
        NSInteger rightSkip = [rightMetrics[@"skipCount"] integerValue];

        if (leftWeight > rightWeight) {
            return NSOrderedAscending;
        }
        if (leftWeight < rightWeight) {
            return NSOrderedDescending;
        }
        if (leftPlay > rightPlay) {
            return NSOrderedAscending;
        }
        if (leftPlay < rightPlay) {
            return NSOrderedDescending;
        }
        if (leftSkip < rightSkip) {
            return NSOrderedAscending;
        }
        if (leftSkip > rightSkip) {
            return NSOrderedDescending;
        }
        return [SonoraDisplayTrackTitle(left) localizedCaseInsensitiveCompare:SonoraDisplayTrackTitle(right)];
    }];

    NSMutableArray<SonoraTrack *> *result = [ranked mutableCopy];
    if (result.count == 0) {
        return @[];
    }

    if (self.forYouSelectionVisit != self.homeVisitCount) {
        NSUInteger candidateLimit = MIN((NSUInteger)6, result.count);
        SonoraTrack *selectedTrack = result.firstObject;
        if (candidateLimit > 0) {
            NSInteger visit = self.homeVisitCount;
            if (visit < 0) {
                visit = -visit;
            }
            NSUInteger baseIndex = (NSUInteger)visit % candidateLimit;
            for (NSUInteger step = 0; step < candidateLimit; step += 1) {
                NSUInteger candidateIndex = (baseIndex + step) % candidateLimit;
                SonoraTrack *candidate = result[candidateIndex];
                if (candidate.identifier.length == 0) {
                    continue;
                }
                if (candidateLimit > 1 &&
                    self.forYouSelectedTrackID.length > 0 &&
                    [candidate.identifier isEqualToString:self.forYouSelectedTrackID]) {
                    continue;
                }
                selectedTrack = candidate;
                break;
            }
        }

        self.forYouSelectedTrackID = selectedTrack.identifier ?: @"";
        self.lastForYouTopTrackID = result.firstObject.identifier ?: self.lastForYouTopTrackID;
        self.forYouSelectionVisit = self.homeVisitCount;
    }

    if (self.forYouSelectedTrackID.length > 0) {
        NSUInteger selectedIndex = [result indexOfObjectPassingTest:^BOOL(SonoraTrack * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            (void)idx;
            (void)stop;
            return [obj.identifier isEqualToString:self.forYouSelectedTrackID];
        }];
        if (selectedIndex != NSNotFound && selectedIndex > 0) {
            [result exchangeObjectAtIndex:0 withObjectAtIndex:selectedIndex];
        }
    }

    if (result.count > limit) {
        [result removeObjectsInRange:NSMakeRange(limit, result.count - limit)];
    }
    return [result copy];
}

- (NSArray<SonoraTrack *> *)buildRecommendationsFromTracks:(NSArray<SonoraTrack *> *)tracks limit:(NSUInteger)limit {
    if (tracks.count == 0 || limit == 0) {
        return @[];
    }

    NSSet<NSString *> *favoriteTrackIDs = [NSSet setWithArray:SonoraFavoritesStore.sharedStore.favoriteTrackIDs];
    NSMutableArray<NSString *> *trackIDs = [NSMutableArray arrayWithCapacity:tracks.count];
    for (SonoraTrack *track in tracks) {
        if (track.identifier.length > 0) {
            [trackIDs addObject:track.identifier];
        }
    }

    NSDictionary<NSString *, NSDictionary<NSString *, NSNumber *> *> *analyticsByTrackID =
    [SonoraTrackAnalyticsStore.sharedStore analyticsByTrackIDForTrackIDs:trackIDs];
    if (analyticsByTrackID.count == 0 && favoriteTrackIDs.count == 0) {
        NSMutableArray<SonoraTrack *> *shuffled = [tracks mutableCopy];
        SonoraShuffleMutableArray(shuffled);
        if (shuffled.count > limit) {
            [shuffled removeObjectsInRange:NSMakeRange(limit, shuffled.count - limit)];
        }
        return [shuffled copy];
    }

    NSMutableDictionary<NSString *, NSNumber *> *weightByTrackID = [NSMutableDictionary dictionaryWithCapacity:tracks.count];
    for (SonoraTrack *track in tracks) {
        NSDictionary<NSString *, NSNumber *> *metrics = analyticsByTrackID[track.identifier] ?: @{};
        BOOL isFavorite = [favoriteTrackIDs containsObject:track.identifier];
        double weight = SonoraHomeBestTrackWeight(metrics, isFavorite);

        if (track.identifier.length > 0) {
            weightByTrackID[track.identifier] = @(weight);
        }
    }

    NSArray<SonoraTrack *> *rankedTracks = [tracks sortedArrayUsingComparator:^NSComparisonResult(SonoraTrack * _Nonnull left,
                                                                                                SonoraTrack * _Nonnull right) {
        double leftWeight = [weightByTrackID[left.identifier] doubleValue];
        double rightWeight = [weightByTrackID[right.identifier] doubleValue];
        if (leftWeight > rightWeight) {
            return NSOrderedAscending;
        }
        if (leftWeight < rightWeight) {
            return NSOrderedDescending;
        }
        return [SonoraDisplayTrackTitle(left) localizedCaseInsensitiveCompare:SonoraDisplayTrackTitle(right)];
    }];

    NSUInteger poolLimit = MIN(rankedTracks.count, MAX((NSInteger)limit * 3, 12));
    NSMutableArray<SonoraTrack *> *pool = [[rankedTracks subarrayWithRange:NSMakeRange(0, poolLimit)] mutableCopy];
    SonoraShuffleMutableArray(pool);
    if (pool.count > limit) {
        [pool removeObjectsInRange:NSMakeRange(limit, pool.count - limit)];
    }
    return [pool copy];
}

- (NSArray<SonoraTrack *> *)buildLastAddedTracksFromTracks:(NSArray<SonoraTrack *> *)tracks limit:(NSUInteger)limit {
    if (tracks.count == 0 || limit == 0) {
        return @[];
    }

    NSMutableDictionary<NSString *, NSDate *> *dateByTrackID = [NSMutableDictionary dictionaryWithCapacity:tracks.count];
    for (SonoraTrack *track in tracks) {
        if (track.identifier.length > 0) {
            dateByTrackID[track.identifier] = SonoraTrackModifiedDate(track);
        }
    }

    NSArray<SonoraTrack *> *sorted = [tracks sortedArrayUsingComparator:^NSComparisonResult(SonoraTrack * _Nonnull left,
                                                                                         SonoraTrack * _Nonnull right) {
        NSDate *leftDate = dateByTrackID[left.identifier] ?: [NSDate dateWithTimeIntervalSince1970:0];
        NSDate *rightDate = dateByTrackID[right.identifier] ?: [NSDate dateWithTimeIntervalSince1970:0];

        NSTimeInterval leftTime = leftDate.timeIntervalSince1970;
        NSTimeInterval rightTime = rightDate.timeIntervalSince1970;
        if (leftTime > rightTime) {
            return NSOrderedAscending;
        }
        if (leftTime < rightTime) {
            return NSOrderedDescending;
        }
        return [SonoraDisplayTrackTitle(left) localizedCaseInsensitiveCompare:SonoraDisplayTrackTitle(right)];
    }];

    if (sorted.count <= limit) {
        return sorted;
    }
    return [sorted subarrayWithRange:NSMakeRange(0, limit)];
}

- (NSArray<SonoraTrack *> *)buildFreshChoiceTracksFromTracks:(NSArray<SonoraTrack *> *)tracks limit:(NSUInteger)limit {
    if (tracks.count == 0 || limit == 0) {
        return @[];
    }

    NSMutableArray<NSString *> *trackIDs = [NSMutableArray arrayWithCapacity:tracks.count];
    for (SonoraTrack *track in tracks) {
        if (track.identifier.length > 0) {
            [trackIDs addObject:track.identifier];
        }
    }

    NSDictionary<NSString *, NSDictionary<NSString *, NSNumber *> *> *analyticsByTrackID =
    [SonoraTrackAnalyticsStore.sharedStore analyticsByTrackIDForTrackIDs:trackIDs];
    NSSet<NSString *> *favoriteTrackIDs = [NSSet setWithArray:SonoraFavoritesStore.sharedStore.favoriteTrackIDs];
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;

    NSArray<SonoraTrack *> *ranked = [tracks sortedArrayUsingComparator:^NSComparisonResult(SonoraTrack * _Nonnull left,
                                                                                         SonoraTrack * _Nonnull right) {
        NSDictionary<NSString *, NSNumber *> *leftMetrics = analyticsByTrackID[left.identifier] ?: @{};
        NSDictionary<NSString *, NSNumber *> *rightMetrics = analyticsByTrackID[right.identifier] ?: @{};

        NSInteger leftPlay = [leftMetrics[@"playCount"] integerValue];
        NSInteger rightPlay = [rightMetrics[@"playCount"] integerValue];
        NSInteger leftSkip = [leftMetrics[@"skipCount"] integerValue];
        NSInteger rightSkip = [rightMetrics[@"skipCount"] integerValue];
        double leftScore = SonoraHomeStabilizedScore(leftPlay, leftSkip, [leftMetrics[@"score"] doubleValue]);
        double rightScore = SonoraHomeStabilizedScore(rightPlay, rightSkip, [rightMetrics[@"score"] doubleValue]);

        NSTimeInterval leftAgeDays = MAX(0.0, (now - SonoraTrackModifiedDate(left).timeIntervalSince1970) / 86400.0);
        NSTimeInterval rightAgeDays = MAX(0.0, (now - SonoraTrackModifiedDate(right).timeIntervalSince1970) / 86400.0);

        double leftFreshness = exp(-leftAgeDays / 24.0);
        double rightFreshness = exp(-rightAgeDays / 24.0);
        double leftUnderplayed = 1.0 - (MIN((double)leftPlay, 40.0) / 40.0);
        double rightUnderplayed = 1.0 - (MIN((double)rightPlay, 40.0) / 40.0);

        double leftWeight = (leftFreshness * 0.50) +
        (leftScore * 0.32) +
        (leftUnderplayed * 0.16) -
        (MIN((double)leftSkip, 20.0) * 0.01) +
        ([favoriteTrackIDs containsObject:left.identifier] ? 0.08 : 0.0);

        double rightWeight = (rightFreshness * 0.50) +
        (rightScore * 0.32) +
        (rightUnderplayed * 0.16) -
        (MIN((double)rightSkip, 20.0) * 0.01) +
        ([favoriteTrackIDs containsObject:right.identifier] ? 0.08 : 0.0);

        if (leftWeight > rightWeight) {
            return NSOrderedAscending;
        }
        if (leftWeight < rightWeight) {
            return NSOrderedDescending;
        }
        return [SonoraDisplayTrackTitle(left) localizedCaseInsensitiveCompare:SonoraDisplayTrackTitle(right)];
    }];

    NSUInteger poolLimit = MIN(ranked.count, MAX((NSInteger)limit * 3, 14));
    NSMutableArray<SonoraTrack *> *pool = [[ranked subarrayWithRange:NSMakeRange(0, poolLimit)] mutableCopy];
    SonoraShuffleMutableArray(pool);
    if (pool.count > limit) {
        [pool removeObjectsInRange:NSMakeRange(limit, pool.count - limit)];
    }
    return [pool copy];
}

- (NSArray<SonoraHomeAlbumItem *> *)buildAlbumItemsFromTracks:(NSArray<SonoraTrack *> *)tracks limit:(NSUInteger)limit {
    if (tracks.count == 0 || limit == 0) {
        return @[];
    }

    NSMutableDictionary<NSString *, SonoraHomeAlbumItem *> *albumsByKey = [NSMutableDictionary dictionary];

    for (SonoraTrack *track in tracks) {
        NSString *rawArtist = [track.artist stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *key = SonoraNormalizedArtistText(rawArtist ?: @"");
        if (key.length == 0) {
            continue;
        }

        SonoraHomeAlbumItem *item = albumsByKey[key];
        NSDate *trackDate = SonoraTrackModifiedDate(track);
        if (item == nil) {
            item = [[SonoraHomeAlbumItem alloc] init];
            item.title = rawArtist;
            item.artwork = track.artwork;
            item.latestDate = trackDate;
            item.trackCount = 1;
            item.tracks = @[track];
            albumsByKey[key] = item;
        } else {
            item.trackCount += 1;
            item.tracks = [item.tracks arrayByAddingObject:track];
            if ([trackDate compare:item.latestDate] == NSOrderedDescending) {
                item.latestDate = trackDate;
                item.artwork = track.artwork;
            }
        }
    }

    NSArray<SonoraHomeAlbumItem *> *sorted = [albumsByKey.allValues sortedArrayUsingComparator:^NSComparisonResult(SonoraHomeAlbumItem * _Nonnull left,
                                                                                                                SonoraHomeAlbumItem * _Nonnull right) {
        NSTimeInterval leftTime = left.latestDate.timeIntervalSince1970;
        NSTimeInterval rightTime = right.latestDate.timeIntervalSince1970;
        if (leftTime > rightTime) {
            return NSOrderedAscending;
        }
        if (leftTime < rightTime) {
            return NSOrderedDescending;
        }
        if (left.trackCount > right.trackCount) {
            return NSOrderedAscending;
        }
        if (left.trackCount < right.trackCount) {
            return NSOrderedDescending;
        }
        return [left.title localizedCaseInsensitiveCompare:right.title];
    }];

    if (sorted.count <= limit) {
        return sorted;
    }
    return [sorted subarrayWithRange:NSMakeRange(0, limit)];
}

- (void)updateEmptyStateIfNeeded {
    if (self.allTracks.count > 0) {
        self.collectionView.backgroundView = nil;
        return;
    }

    UILabel *emptyLabel = [[UILabel alloc] init];
    emptyLabel.text = @"No tracks yet.\nAdd music to On My iPhone/Sonora/Sonora.";
    emptyLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
    emptyLabel.textColor = UIColor.secondaryLabelColor;
    emptyLabel.textAlignment = NSTextAlignmentCenter;
    emptyLabel.numberOfLines = 0;
    self.collectionView.backgroundView = emptyLabel;
}

- (void)noopBarButtonTapped {
    // UI only.
}

- (void)openHistoryTapped {
    SonoraHistoryViewController *history = [[SonoraHistoryViewController alloc] init];
    history.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:history animated:YES];
}

- (void)openSettingsTapped {
    SonoraSettingsViewController *settings = [[SonoraSettingsViewController alloc] init];
    settings.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:settings animated:YES];
}

- (NSString *)titleForSection:(SonoraHomeSectionType)sectionType {
    switch (sectionType) {
        case SonoraHomeSectionTypeForYou:
            return @"My wave";
        case SonoraHomeSectionTypeYouNeedThis:
            return @"Fresh choice";
        case SonoraHomeSectionTypeFreshCuts:
            return @"Based on your taste";
    }
    return @"";
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    (void)collectionView;
    return 3;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    (void)collectionView;
    switch ((SonoraHomeSectionType)section) {
        case SonoraHomeSectionTypeForYou:
            return (self.recommendationTracks.count > 0) ? 1 : 0;
        case SonoraHomeSectionTypeYouNeedThis:
            return self.freshTracks.count;
        case SonoraHomeSectionTypeFreshCuts:
            return self.needThisTracks.count;
    }
    return 0;
}

- (BOOL)isWaveQueueActiveForQueue:(NSArray<SonoraTrack *> *)queue
                      currentTrack:(SonoraTrack * _Nullable)currentTrack {
    if (self.recommendationTracks.count == 0 || queue.count == 0 || currentTrack.identifier.length == 0) {
        return NO;
    }

    NSMutableSet<NSString *> *waveIDs = [NSMutableSet setWithCapacity:self.recommendationTracks.count];
    for (SonoraTrack *track in self.recommendationTracks) {
        if (track.identifier.length > 0) {
            [waveIDs addObject:track.identifier];
        }
    }
    if (waveIDs.count == 0 || ![waveIDs containsObject:currentTrack.identifier]) {
        return NO;
    }

    NSUInteger minimumWaveMatches = MIN((NSUInteger)3, self.recommendationTracks.count);
    if (queue.count < minimumWaveMatches) {
        return NO;
    }

    NSUInteger matched = 0;
    for (SonoraTrack *track in queue) {
        if (track.identifier.length > 0 && [waveIDs containsObject:track.identifier]) {
            matched += 1;
        }
    }

    if (matched < minimumWaveMatches) {
        return NO;
    }

    double ratio = (double)matched / (double)MAX((NSUInteger)1, queue.count);
    return ratio >= 0.68;
}

- (void)configureHeroRecommendationCell:(SonoraHomeHeroRecommendationCell *)cell
                  preserveWaveProgress:(BOOL)preserveWaveProgress {
    if (cell == nil || self.recommendationTracks.count == 0) {
        return;
    }

    NSArray<SonoraTrack *> *queue = SonoraPlaybackManager.sharedManager.currentQueue;
    SonoraTrack *currentTrack = SonoraPlaybackManager.sharedManager.currentTrack;
    BOOL isWaveQueue = [self isWaveQueueActiveForQueue:queue currentTrack:currentTrack];
    SonoraTrack *displayTrack = (isWaveQueue && currentTrack != nil) ? currentTrack : self.recommendationTracks.firstObject;
    BOOL shouldPreserveConfiguredWave =
    preserveWaveProgress &&
    displayTrack.identifier.length > 0 &&
    [cell.configuredTrackIdentifier isEqualToString:displayTrack.identifier];
    if (!shouldPreserveConfiguredWave) {
        [cell configureWithTrack:displayTrack];
    }
    cell.playing = isWaveQueue && SonoraPlaybackManager.sharedManager.isPlaying;
    [cell resumeWaveAnimationsIfNeeded];

    __weak typeof(self) weakSelf = self;
    cell.playHandler = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf.recommendationTracks.count == 0) {
            return;
        }
        NSArray<SonoraTrack *> *liveQueue = SonoraPlaybackManager.sharedManager.currentQueue;
        SonoraTrack *liveTrack = SonoraPlaybackManager.sharedManager.currentTrack;
        BOOL liveWaveQueue = [strongSelf isWaveQueueActiveForQueue:liveQueue currentTrack:liveTrack];
        if (liveWaveQueue && SonoraPlaybackManager.sharedManager.currentTrack != nil) {
            [SonoraPlaybackManager.sharedManager togglePlayPause];
        } else {
            [strongSelf playTracks:strongSelf.recommendationTracks startIndex:0];
        }
    };
}

- (void)refreshVisibleWaveCellIfNeededPreservingWaveProgress:(BOOL)preserveWaveProgress {
    if (self.collectionView == nil || self.recommendationTracks.count == 0) {
        return;
    }

    NSIndexPath *indexPath = [NSIndexPath indexPathForItem:0 inSection:SonoraHomeSectionTypeForYou];
    SonoraHomeHeroRecommendationCell *cell = (SonoraHomeHeroRecommendationCell *)[self.collectionView cellForItemAtIndexPath:indexPath];
    if (![cell isKindOfClass:SonoraHomeHeroRecommendationCell.class]) {
        return;
    }

    [self configureHeroRecommendationCell:cell preserveWaveProgress:preserveWaveProgress];
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                            cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    switch ((SonoraHomeSectionType)indexPath.section) {
        case SonoraHomeSectionTypeForYou: {
            SonoraHomeHeroRecommendationCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:SonoraHomeHeroRecommendationCellReuseID
                                                                                             forIndexPath:indexPath];
            if (self.recommendationTracks.count > 0) {
                [self configureHeroRecommendationCell:cell preserveWaveProgress:NO];
            }
            return cell;
        }
        case SonoraHomeSectionTypeYouNeedThis: {
            SonoraHomeLastAddedCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:SonoraHomeLastAddedCellReuseID
                                                                                   forIndexPath:indexPath];
            if (indexPath.item < self.freshTracks.count) {
                [cell configureWithTrack:self.freshTracks[indexPath.item]];
            }
            return cell;
        }
        case SonoraHomeSectionTypeFreshCuts: {
            SonoraHomeRecommendationCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:SonoraHomeRecommendationCellReuseID
                                                                                        forIndexPath:indexPath];
            if (indexPath.item < self.needThisTracks.count) {
                [cell configureWithTrack:self.needThisTracks[indexPath.item]];
            }
            return cell;
        }
    }
    return [UICollectionViewCell new];
}

- (__kindof UICollectionReusableView *)collectionView:(UICollectionView *)collectionView
                            viewForSupplementaryElementOfKind:(NSString *)kind
                                                  atIndexPath:(NSIndexPath *)indexPath {
    if (![kind isEqualToString:SonoraHomeSectionHeaderKind]) {
        return [UICollectionReusableView new];
    }

    SonoraHomeSectionHeaderView *header = [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                                                           withReuseIdentifier:SonoraHomeSectionHeaderReuseID
                                                                                  forIndexPath:indexPath];
    [header configureWithTitle:[self titleForSection:(SonoraHomeSectionType)indexPath.section]];
    return header;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];

    switch ((SonoraHomeSectionType)indexPath.section) {
        case SonoraHomeSectionTypeForYou:
            [self playTracks:self.recommendationTracks startIndex:indexPath.item];
            return;
        case SonoraHomeSectionTypeYouNeedThis:
            [self playTracks:self.freshTracks startIndex:indexPath.item];
            return;
        case SonoraHomeSectionTypeFreshCuts:
            [self playTracks:self.needThisTracks startIndex:indexPath.item];
            return;
    }
}

- (NSArray<SonoraTrack *> *)albumDetailTracksForAlbumItem:(SonoraHomeAlbumItem *)albumItem {
    if (albumItem == nil) {
        return @[];
    }

    NSArray<SonoraTrack *> *seedTracks = albumItem.tracks ?: @[];
    if (seedTracks.count == 0) {
        return @[];
    }

    NSString *targetArtist = SonoraNormalizedArtistText(albumItem.title ?: @"");
    if (targetArtist.length == 0) {
        for (SonoraTrack *track in seedTracks) {
            NSString *artist = SonoraNormalizedArtistText(track.artist ?: @"");
            if (artist.length > 0) {
                targetArtist = artist;
                break;
            }
        }
    }

    if (targetArtist.length == 0) {
        return @[];
    }

    NSMutableArray<SonoraTrack *> *matchedTracks = [NSMutableArray array];
    for (SonoraTrack *track in self.allTracks) {
        NSString *artist = SonoraNormalizedArtistText(track.artist ?: @"");
        if (artist.length == 0) {
            continue;
        }

        if ([artist isEqualToString:targetArtist]) {
            [matchedTracks addObject:track];
        }
    }

    if (matchedTracks.count == 0) {
        return @[];
    }

    [matchedTracks sortUsingComparator:^NSComparisonResult(SonoraTrack * _Nonnull left, SonoraTrack * _Nonnull right) {
        NSString *leftTitle = SonoraDisplayTrackTitle(left);
        NSString *rightTitle = SonoraDisplayTrackTitle(right);
        return [leftTitle localizedCaseInsensitiveCompare:rightTitle];
    }];
    return matchedTracks;
}

- (void)playTracks:(NSArray<SonoraTrack *> *)tracks startIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)tracks.count) {
        return;
    }

    UIViewController *player = SonoraInstantiatePlayerViewController();
    if (player != nil && self.navigationController != nil) {
        player.hidesBottomBarWhenPushed = YES;
        [self.navigationController pushViewController:player animated:YES];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [SonoraPlaybackManager.sharedManager setShuffleEnabled:NO];
        [SonoraPlaybackManager.sharedManager playTracks:tracks startIndex:index];
    });
}

@end
