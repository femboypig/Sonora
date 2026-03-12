//
//  SonoraHomeViewController.m
//  Sonora
//

#import "SonoraHomeViewController.h"

#import <limits.h>
#import <math.h>
#import <QuartzCore/QuartzCore.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "SonoraCells.h"
#import "SonoraHistoryViewController.h"
#import "SonoraSettings.h"
#import "SonoraSettingsBackupArchiveService.h"
#import "SonoraSharedPlaylists.h"
#import "SonoraSleepTimerUI.h"
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

static UIColor *SonoraHomeDefaultAccentColor(void) {
    return [UIColor colorWithRed:1.0 green:0.83 blue:0.08 alpha:1.0];
}

static UIColor *SonoraHomeLegacyAccentColorForIndex(NSInteger raw) {
    switch (raw) {
        case 1:
            return [UIColor colorWithRed:0.31 green:0.64 blue:1.0 alpha:1.0];
        case 2:
            return [UIColor colorWithRed:0.22 green:0.83 blue:0.62 alpha:1.0];
        case 3:
            return [UIColor colorWithRed:1.0 green:0.48 blue:0.40 alpha:1.0];
        case 0:
        default:
            return SonoraHomeDefaultAccentColor();
    }
}

static UIColor *SonoraHomeColorFromHexString(NSString *hexString) {
    if (hexString.length == 0) {
        return nil;
    }
    NSString *normalized = [[hexString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    if ([normalized hasPrefix:@"#"]) {
        normalized = [normalized substringFromIndex:1];
    }
    if (normalized.length != 6) {
        return nil;
    }

    unsigned int rgb = 0;
    if (![[NSScanner scannerWithString:normalized] scanHexInt:&rgb]) {
        return nil;
    }

    CGFloat red = ((rgb >> 16) & 0xFF) / 255.0;
    CGFloat green = ((rgb >> 8) & 0xFF) / 255.0;
    CGFloat blue = (rgb & 0xFF) / 255.0;
    return [UIColor colorWithRed:red green:green blue:blue alpha:1.0];
}

static UIColor *SonoraHomeAccentYellowColor(void) {
    UIColor *fromHex = SonoraHomeColorFromHexString(SonoraSettingsAccentHex());
    if (fromHex != nil) {
        return fromHex;
    }
    return SonoraHomeLegacyAccentColorForIndex(SonoraSettingsLegacyAccentColorIndex());
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

static UIColor *SonoraBlendColor(UIColor *from, UIColor *to, CGFloat ratio) {
    ratio = MIN(MAX(ratio, 0.0), 1.0);
    CGFloat fr = 0.0, fg = 0.0, fb = 0.0, fa = 1.0;
    CGFloat tr = 0.0, tg = 0.0, tb = 0.0, ta = 1.0;
    [from getRed:&fr green:&fg blue:&fb alpha:&fa];
    [to getRed:&tr green:&tg blue:&tb alpha:&ta];
    return [UIColor colorWithRed:(fr + ((tr - fr) * ratio))
                           green:(fg + ((tg - fg) * ratio))
                            blue:(fb + ((tb - fb) * ratio))
                           alpha:(fa + ((ta - fa) * ratio))];
}

static NSArray<UIColor *> *SonoraWavePaletteFromImage(UIImage *image) {
    if (image == nil || image.CGImage == nil) {
        return @[];
    }

    const size_t width = 28;
    const size_t height = 28;
    const size_t bytesPerRow = width * 4;
    uint8_t *pixels = calloc(height, bytesPerRow);
    if (pixels == NULL) {
        return @[];
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    if (colorSpace == nil) {
        free(pixels);
        return @[];
    }

    CGContextRef bitmapContext = CGBitmapContextCreate(pixels,
                                                       width,
                                                       height,
                                                       8,
                                                       bytesPerRow,
                                                       colorSpace,
                                                       (CGBitmapInfo)(kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big));
    CGColorSpaceRelease(colorSpace);
    if (bitmapContext == NULL) {
        free(pixels);
        return @[];
    }
    CGContextDrawImage(bitmapContext, CGRectMake(0.0, 0.0, width, height), image.CGImage);

    typedef struct {
        CGFloat w;
        CGFloat r;
        CGFloat g;
        CGFloat b;
    } SonoraWaveBucket;
    SonoraWaveBucket buckets[10] = {0};

    for (size_t y = 0; y < height; y += 1) {
        for (size_t x = 0; x < width; x += 1) {
            size_t offset = (y * bytesPerRow) + (x * 4);
            CGFloat alpha = ((CGFloat)pixels[offset + 3]) / 255.0;
            if (alpha < 0.18) {
                continue;
            }

            CGFloat red = ((CGFloat)pixels[offset + 0]) / 255.0;
            CGFloat green = ((CGFloat)pixels[offset + 1]) / 255.0;
            CGFloat blue = ((CGFloat)pixels[offset + 2]) / 255.0;
            UIColor *c = [UIColor colorWithRed:red green:green blue:blue alpha:1.0];
            CGFloat hue = 0.0, saturation = 0.0, brightness = 0.0;
            if (![c getHue:&hue saturation:&saturation brightness:&brightness alpha:nil]) {
                continue;
            }
            if (saturation < 0.10 || brightness < 0.12) {
                continue;
            }

            NSUInteger bucketIndex = MIN((NSUInteger)floor(hue * 10.0), (NSUInteger)9);
            CGFloat weight = 0.32 + (saturation * 0.44) + (brightness * 0.24);
            buckets[bucketIndex].w += weight;
            buckets[bucketIndex].r += red * weight;
            buckets[bucketIndex].g += green * weight;
            buckets[bucketIndex].b += blue * weight;
        }
    }

    CGContextRelease(bitmapContext);
    free(pixels);

    NSMutableArray<NSDictionary *> *ranked = [NSMutableArray array];
    for (NSUInteger idx = 0; idx < 10; idx += 1) {
        if (buckets[idx].w <= 0.0) {
            continue;
        }
        [ranked addObject:@{
            @"index": @(idx),
            @"weight": @(buckets[idx].w)
        }];
    }
    [ranked sortUsingComparator:^NSComparisonResult(NSDictionary * _Nonnull left, NSDictionary * _Nonnull right) {
        return [right[@"weight"] compare:left[@"weight"]];
    }];

    NSMutableArray<UIColor *> *colors = [NSMutableArray array];
    NSUInteger maxCount = MIN(ranked.count, (NSUInteger)4);
    for (NSUInteger rank = 0; rank < maxCount; rank += 1) {
        NSUInteger idx = [ranked[rank][@"index"] unsignedIntegerValue];
        CGFloat w = MAX(0.0001, buckets[idx].w);
        UIColor *color = [UIColor colorWithRed:(buckets[idx].r / w)
                                         green:(buckets[idx].g / w)
                                          blue:(buckets[idx].b / w)
                                         alpha:1.0];

        CGFloat hue = 0.0, sat = 0.0, bri = 0.0;
        if ([color getHue:&hue saturation:&sat brightness:&bri alpha:nil]) {
            sat = MAX(sat, 0.22);
            bri = MIN(MAX(bri, 0.30), 0.90);
            color = [UIColor colorWithHue:hue saturation:sat brightness:bri alpha:1.0];
        }
        [colors addObject:color];
    }

    return colors;
}

static NSArray<UIColor *> *SonoraResolvedWavePalette(UIImage * _Nullable image) {
    NSArray<UIColor *> *palette = SonoraWavePaletteFromImage(image);
    if (palette.count >= 4) {
        return palette;
    }

    UIColor *accent = [SonoraArtworkAccentColorService dominantAccentColorForImage:image
                                                                       fallback:[UIColor colorWithRed:0.41 green:0.35 blue:0.29 alpha:1.0]];

    CGFloat hue = 0.0, sat = 0.0, bri = 0.0, alpha = 1.0;
    if ([accent getHue:&hue saturation:&sat brightness:&bri alpha:&alpha]) {
        UIColor *lifted = [UIColor colorWithHue:hue
                                      saturation:MAX(0.20, sat * 0.86)
                                      brightness:MIN(0.96, bri + 0.20)
                                           alpha:1.0];
        UIColor *deep = [UIColor colorWithHue:fmod(hue + 0.06, 1.0)
                                    saturation:MAX(0.22, sat * 0.80)
                                    brightness:MAX(0.34, bri * 0.72)
                                         alpha:1.0];
        UIColor *adjacent = [UIColor colorWithHue:fmod(hue + 0.88, 1.0)
                                        saturation:MAX(0.18, sat * 0.70)
                                        brightness:MAX(0.40, bri * 0.82)
                                             alpha:1.0];
        return @[accent, lifted, deep, adjacent];
    }

    UIColor *warm = [UIColor colorWithRed:0.58 green:0.47 blue:0.35 alpha:1.0];
    UIColor *soft = [UIColor colorWithRed:0.43 green:0.48 blue:0.44 alpha:1.0];
    return @[
        accent,
        SonoraBlendColor(accent, UIColor.whiteColor, 0.24),
        SonoraBlendColor(accent, warm, 0.20),
        SonoraBlendColor(accent, soft, 0.18)
    ];
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

@interface SonoraPlayerViewController : UIViewController
@end

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

typedef NS_ENUM(NSInteger, SonoraMyWaveLook) {
    SonoraMyWaveLookClouds = 0,
    SonoraMyWaveLookContours = 1
};

static SonoraMyWaveLook SonoraCurrentMyWaveLook(void) {
    NSInteger storedValue = SonoraSettingsMyWaveLook();
    if (storedValue != SonoraMyWaveLookClouds && storedValue != SonoraMyWaveLookContours) {
        storedValue = SonoraMyWaveLookContours;
        SonoraSettingsSetMyWaveLook(storedValue);
    }
    return (SonoraMyWaveLook)storedValue;
}

@interface SonoraWaveAnimatedBackgroundView : UIView

- (void)applyPalette:(NSArray<UIColor *> *)palette animated:(BOOL)animated;
- (void)setPlaying:(BOOL)playing;
- (void)setPulseSeedWithTrackIdentifier:(NSString * _Nullable)identifier;
- (void)ensureAnimationsRunning;

@end

@interface SonoraWaveAnimatedBackgroundView ()

@property (nonatomic, strong) CAGradientLayer *baseGradientLayer;
@property (nonatomic, strong) CAGradientLayer *haloLayer;
@property (nonatomic, strong) CAGradientLayer *coreGlowLayer;
@property (nonatomic, strong) CALayer *lineContainerLayer;
@property (nonatomic, strong) CAGradientLayer *lineMaskLayer;
@property (nonatomic, strong) NSArray<CAShapeLayer *> *lineLayers;
@property (nonatomic, strong) CAGradientLayer *vignetteLayer;
@property (nonatomic, strong) CAGradientLayer *edgeFadeMaskLayer;
@property (nonatomic, copy) NSArray<UIColor *> *currentPalette;
@property (nonatomic, assign) BOOL hasStartedAnimations;
@property (nonatomic, assign) BOOL playing;
@property (nonatomic, assign) CGFloat pulseSeed;
@property (nonatomic, assign) CGSize configuredSize;
@property (nonatomic, copy, nullable) NSString *currentTrackIdentifier;
@property (nonatomic, assign) NSUInteger geometryTransitionGeneration;

@end

@implementation SonoraWaveAnimatedBackgroundView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.pulseSeed = 0.43f;
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.clipsToBounds = NO;

    CAGradientLayer *base = [CAGradientLayer layer];
    base.type = kCAGradientLayerRadial;
    base.startPoint = CGPointMake(0.50, 0.50);
    base.endPoint = CGPointMake(1.0, 1.0);
    base.colors = @[
        (__bridge id)UIColor.clearColor.CGColor,
        (__bridge id)UIColor.clearColor.CGColor,
        (__bridge id)UIColor.clearColor.CGColor,
        (__bridge id)UIColor.clearColor.CGColor
    ];
    base.locations = @[@0.0, @0.22, @0.58, @1.0];
    [self.layer addSublayer:base];
    self.baseGradientLayer = base;

    CAGradientLayer *halo = [CAGradientLayer layer];
    halo.type = kCAGradientLayerRadial;
    halo.startPoint = CGPointMake(0.62, 0.42);
    halo.endPoint = CGPointMake(1.0, 1.0);
    halo.colors = @[
        (__bridge id)UIColor.clearColor.CGColor,
        (__bridge id)UIColor.clearColor.CGColor,
        (__bridge id)UIColor.clearColor.CGColor
    ];
    halo.locations = @[@0.0, @0.42, @1.0];
    halo.opacity = 0.90;
    [self.layer addSublayer:halo];
    self.haloLayer = halo;

    CAGradientLayer *coreGlow = [CAGradientLayer layer];
    coreGlow.type = kCAGradientLayerRadial;
    coreGlow.startPoint = CGPointMake(0.50, 0.52);
    coreGlow.endPoint = CGPointMake(1.0, 1.0);
    coreGlow.colors = @[
        (__bridge id)UIColor.clearColor.CGColor,
        (__bridge id)UIColor.clearColor.CGColor,
        (__bridge id)UIColor.clearColor.CGColor,
        (__bridge id)UIColor.clearColor.CGColor
    ];
    coreGlow.locations = @[@0.0, @0.22, @0.52, @1.0];
    coreGlow.opacity = 0.0f;
    [self.layer addSublayer:coreGlow];
    self.coreGlowLayer = coreGlow;

    CALayer *lineContainer = [CALayer layer];
    [self.layer addSublayer:lineContainer];
    self.lineContainerLayer = lineContainer;

    CAGradientLayer *lineMask = [CAGradientLayer layer];
    lineMask.type = kCAGradientLayerRadial;
    lineMask.startPoint = CGPointMake(0.50, 0.52);
    lineMask.endPoint = CGPointMake(1.0, 1.0);
    lineMask.colors = @[
        (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor,
        (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.88].CGColor,
        (__bridge id)[UIColor colorWithWhite:1.0 alpha:1.0].CGColor,
        (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.72].CGColor,
        (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor
    ];
    lineMask.locations = @[@0.0, @0.16, @0.46, @0.82, @1.0];
    lineContainer.mask = lineMask;
    self.lineMaskLayer = lineMask;

    NSMutableArray<CAShapeLayer *> *lines = [NSMutableArray arrayWithCapacity:7];
    for (NSUInteger idx = 0; idx < 7; idx += 1) {
        CAShapeLayer *line = [CAShapeLayer layer];
        line.fillColor = UIColor.clearColor.CGColor;
        line.strokeColor = UIColor.whiteColor.CGColor;
        line.lineCap = kCALineCapRound;
        line.lineJoin = kCALineJoinRound;
        line.opacity = 0.0f;
        line.shadowColor = UIColor.whiteColor.CGColor;
        line.shadowOpacity = 0.22f;
        line.shadowRadius = 10.0f;
        line.shadowOffset = CGSizeZero;
        [lineContainer addSublayer:line];
        [lines addObject:line];
    }
    self.lineLayers = [lines copy];

    CAGradientLayer *vignette = [CAGradientLayer layer];
    vignette.type = kCAGradientLayerRadial;
    vignette.startPoint = CGPointMake(0.50, 0.52);
    vignette.endPoint = CGPointMake(1.0, 1.0);
    vignette.colors = @[
        (__bridge id)UIColor.clearColor.CGColor,
        (__bridge id)UIColor.clearColor.CGColor,
        (__bridge id)UIColor.clearColor.CGColor
    ];
    vignette.locations = @[@0.56, @0.82, @1.0];
    [self.layer addSublayer:vignette];
    self.vignetteLayer = vignette;

    CAGradientLayer *edgeFadeMask = [CAGradientLayer layer];
    edgeFadeMask.startPoint = CGPointMake(0.50, 0.0);
    edgeFadeMask.endPoint = CGPointMake(0.50, 1.0);
    edgeFadeMask.colors = @[
        (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor,
        (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.86].CGColor,
        (__bridge id)[UIColor colorWithWhite:1.0 alpha:1.0].CGColor,
        (__bridge id)[UIColor colorWithWhite:1.0 alpha:1.0].CGColor,
        (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor
    ];
    edgeFadeMask.locations = @[@0.0, @0.14, @0.24, @0.92, @1.0];
    self.layer.mask = edgeFadeMask;
    self.edgeFadeMaskLayer = edgeFadeMask;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.baseGradientLayer.frame = self.bounds;
    self.haloLayer.frame = self.bounds;
    self.coreGlowLayer.frame = self.bounds;
    self.lineContainerLayer.frame = self.bounds;
    self.lineMaskLayer.frame = self.bounds;
    self.vignetteLayer.frame = self.bounds;
    self.edgeFadeMaskLayer.frame = self.bounds;

    if (!CGSizeEqualToSize(self.configuredSize, self.bounds.size)) {
        self.configuredSize = self.bounds.size;
        [self configureLineGeometry];
        [self restartAnimations];
    } else if (!self.hasStartedAnimations) {
        [self startAnimationsIfNeeded];
        [self restartAnimations];
    }
}

- (void)startAnimationsIfNeeded {
    if (self.hasStartedAnimations) {
        return;
    }
    self.hasStartedAnimations = YES;
}

- (void)setPlaying:(BOOL)playing {
    if (_playing == playing) {
        [self updatePlaybackStateAnimated:NO];
        return;
    }
    _playing = playing;
    [self updatePlaybackStateAnimated:YES];
}

- (void)setPulseSeedWithTrackIdentifier:(NSString * _Nullable)identifier {
    NSString *normalizedIdentifier = (identifier.length > 0) ? identifier : nil;
    if ((self.currentTrackIdentifier == nil && normalizedIdentifier == nil) ||
        [self.currentTrackIdentifier isEqualToString:normalizedIdentifier]) {
        return;
    }
    self.currentTrackIdentifier = normalizedIdentifier;

    const char *utf8 = normalizedIdentifier.UTF8String;
    if (utf8 == NULL || utf8[0] == '\0') {
        self.pulseSeed = 0.43f;
        if (!CGSizeEqualToSize(self.bounds.size, CGSizeZero)) {
            [self transitionToUpdatedGeometry];
        }
        return;
    }

    uint64_t hash = 1469598103934665603ULL;
    const uint8_t *bytes = (const uint8_t *)utf8;
    while (*bytes != 0) {
        hash ^= (uint64_t)(*bytes);
        hash *= 1099511628211ULL;
        bytes += 1;
    }
    self.pulseSeed = (CGFloat)((hash % 1000ULL) / 1000.0);
    if (!CGSizeEqualToSize(self.bounds.size, CGSizeZero)) {
        [self transitionToUpdatedGeometry];
    }
}

- (void)applyPalette:(NSArray<UIColor *> *)palette animated:(BOOL)animated {
    NSArray<UIColor *> *resolved = (palette.count >= 4) ? palette : SonoraResolvedWavePalette(nil);
    self.currentPalette = resolved;
    BOOL lightTheme = (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleLight);

    NSArray *baseColors = @[
        (__bridge id)[[(lightTheme
                        ? SonoraBlendColor(resolved[1], UIColor.whiteColor, 0.90)
                        : SonoraBlendColor(resolved[0], UIColor.blackColor, 0.42))
                       colorWithAlphaComponent:(lightTheme ? 0.16 : 0.28)] CGColor],
        (__bridge id)[[(lightTheme
                        ? SonoraBlendColor(resolved[2], UIColor.whiteColor, 0.92)
                        : SonoraBlendColor(resolved[2], UIColor.blackColor, 0.56))
                       colorWithAlphaComponent:(lightTheme ? 0.08 : 0.15)] CGColor],
        (__bridge id)[[(lightTheme
                        ? SonoraBlendColor(resolved[0], UIColor.whiteColor, 0.97)
                        : SonoraBlendColor(resolved[3], UIColor.blackColor, 0.76))
                       colorWithAlphaComponent:(lightTheme ? 0.02 : 0.04)] CGColor],
        (__bridge id)[UIColor clearColor].CGColor
    ];
    if (animated) {
        CABasicAnimation *baseAnim = [CABasicAnimation animationWithKeyPath:@"colors"];
        baseAnim.fromValue = self.baseGradientLayer.colors;
        baseAnim.toValue = baseColors;
        baseAnim.duration = 2.0;
        baseAnim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [self.baseGradientLayer addAnimation:baseAnim forKey:@"sonora_wave_base_colors"];
    }
    self.baseGradientLayer.colors = baseColors;

    UIColor *haloColor = lightTheme
    ? SonoraBlendColor(resolved[3], UIColor.whiteColor, 0.68)
    : SonoraBlendColor(resolved[3], UIColor.whiteColor, 0.18);
    NSArray *haloColors = @[
        (__bridge id)[haloColor colorWithAlphaComponent:(lightTheme ? 0.22 : 0.28)].CGColor,
        (__bridge id)[haloColor colorWithAlphaComponent:(lightTheme ? 0.07 : 0.10)].CGColor,
        (__bridge id)[haloColor colorWithAlphaComponent:0.0].CGColor
    ];
    if (animated) {
        CABasicAnimation *haloAnim = [CABasicAnimation animationWithKeyPath:@"colors"];
        haloAnim.fromValue = self.haloLayer.colors;
        haloAnim.toValue = haloColors;
        haloAnim.duration = 2.0;
        haloAnim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [self.haloLayer addAnimation:haloAnim forKey:@"sonora_wave_halo_colors"];
    }
    self.haloLayer.colors = haloColors;

    UIColor *coreColor = lightTheme
    ? SonoraBlendColor(resolved[2], UIColor.whiteColor, 0.58)
    : SonoraBlendColor(resolved[2], UIColor.whiteColor, 0.08);
    NSArray *coreGlowColors = @[
        (__bridge id)[coreColor colorWithAlphaComponent:(lightTheme ? 0.22 : 0.20)].CGColor,
        (__bridge id)[coreColor colorWithAlphaComponent:(lightTheme ? 0.08 : 0.07)].CGColor,
        (__bridge id)[coreColor colorWithAlphaComponent:0.0].CGColor
    ];
    if (animated) {
        CABasicAnimation *coreAnim = [CABasicAnimation animationWithKeyPath:@"colors"];
        coreAnim.fromValue = self.coreGlowLayer.colors;
        coreAnim.toValue = coreGlowColors;
        coreAnim.duration = 2.2;
        coreAnim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [self.coreGlowLayer addAnimation:coreAnim forKey:@"sonora_wave_core_colors"];
    }
    self.coreGlowLayer.colors = coreGlowColors;

    NSArray<UIColor *> *lineColors = @[
        lightTheme ? SonoraBlendColor(resolved[3], UIColor.whiteColor, 0.14) : SonoraBlendColor(resolved[3], UIColor.whiteColor, 0.06),
        lightTheme ? SonoraBlendColor(resolved[1], UIColor.whiteColor, 0.20) : SonoraBlendColor(resolved[1], UIColor.whiteColor, 0.08),
        lightTheme ? SonoraBlendColor(resolved[2], UIColor.whiteColor, 0.16) : SonoraBlendColor(resolved[2], UIColor.whiteColor, 0.06),
        lightTheme ? SonoraBlendColor(resolved[0], UIColor.whiteColor, 0.10) : SonoraBlendColor(resolved[0], UIColor.whiteColor, 0.02)
    ];
    [self.lineLayers enumerateObjectsUsingBlock:^(CAShapeLayer * _Nonnull line, NSUInteger idx, BOOL * _Nonnull stop) {
        (void)stop;
        UIColor *color = lineColors[idx % lineColors.count];
        CGFloat alpha = lightTheme ? (idx < 3 ? 0.88f : 0.68f) : (idx < 3 ? 1.0f : 0.82f);
        CGColorRef strokeColor = [color colorWithAlphaComponent:alpha].CGColor;
        if (animated) {
            CABasicAnimation *anim = [CABasicAnimation animationWithKeyPath:@"strokeColor"];
            anim.fromValue = (__bridge id)line.strokeColor;
            anim.toValue = (__bridge id)strokeColor;
            anim.duration = 1.8;
            anim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            [line addAnimation:anim forKey:[NSString stringWithFormat:@"sonora_wave_line_color_%lu", (unsigned long)idx]];
        }
        line.strokeColor = strokeColor;
        line.shadowColor = strokeColor;
        line.shadowOpacity = lightTheme ? (idx < 3 ? 0.30f : 0.16f) : (idx < 3 ? 0.50f : 0.30f);
        line.shadowRadius = (idx < 2) ? 18.0f : ((idx < 4) ? 12.0f : 8.0f);
    }];

    NSArray *vignetteColors = @[
        (__bridge id)[UIColor colorWithWhite:0.0 alpha:0.0].CGColor,
        (__bridge id)[[(lightTheme
                        ? SonoraBlendColor(resolved[0], UIColor.whiteColor, 0.98)
                        : SonoraBlendColor(resolved[0], UIColor.blackColor, 0.86))
                       colorWithAlphaComponent:(lightTheme ? 0.015 : 0.028)] CGColor],
        (__bridge id)[[(lightTheme
                        ? SonoraBlendColor(resolved[3], UIColor.whiteColor, 0.995)
                        : SonoraBlendColor(resolved[3], UIColor.blackColor, 0.94))
                       colorWithAlphaComponent:(lightTheme ? 0.040 : 0.12)] CGColor]
    ];
    if (animated) {
        CABasicAnimation *vignetteAnim = [CABasicAnimation animationWithKeyPath:@"colors"];
        vignetteAnim.fromValue = self.vignetteLayer.colors;
        vignetteAnim.toValue = vignetteColors;
        vignetteAnim.duration = 1.8;
        vignetteAnim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [self.vignetteLayer addAnimation:vignetteAnim forKey:@"sonora_wave_vignette_colors"];
    }
    self.vignetteLayer.colors = vignetteColors;
    [self updatePlaybackStateAnimated:NO];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (@available(iOS 13.0, *)) {
        if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
            [self applyPalette:(self.currentPalette ?: SonoraResolvedWavePalette(nil)) animated:NO];
        }
    }
}

- (void)configureLineGeometry {
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    if (width <= 1.0 || height <= 1.0) {
        return;
    }

    CGFloat scale = MAX(0.92f, MIN(1.20f, MIN(width / 360.0f, height / 220.0f)));
    NSArray<NSNumber *> *lineWidths = @[
        @(2.8f * scale),
        @(2.5f * scale),
        @(2.2f * scale),
        @(1.9f * scale),
        @(1.7f * scale),
        @(1.5f * scale),
        @(1.2f * scale)
    ];

    [self.lineLayers enumerateObjectsUsingBlock:^(CAShapeLayer * _Nonnull line, NSUInteger idx, BOOL * _Nonnull stop) {
        (void)stop;
        line.frame = self.bounds;
        line.lineWidth = lineWidths[idx].doubleValue;
        line.path = [self contourPathForIndex:idx variant:0].CGPath;
    }];
}

- (UIBezierPath *)contourPathForIndex:(NSUInteger)index variant:(NSUInteger)variant {
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    CGFloat count = MAX(1.0f, (CGFloat)(self.lineLayers.count - 1));
    CGFloat progress = ((CGFloat)index) / count;
    CGFloat phase = (self.pulseSeed * (CGFloat)(M_PI * 2.0)) + (((CGFloat)variant) * 0.86f) + (progress * 1.15f);

    CGFloat centerX = (width * 0.50f) + (sinf(phase * 0.72f) * width * 0.018f);
    CGFloat centerY = (height * 0.53f) + (cosf((phase * 0.54f) + 0.6f) * height * 0.022f);
    CGFloat radiusX = width * (0.17f + (progress * 0.23f));
    CGFloat radiusY = height * (0.13f + (progress * 0.17f));
    CGFloat amplitude = MIN(width, height) * (0.014f + (progress * 0.010f));
    NSUInteger pointCount = 56;

    UIBezierPath *path = [UIBezierPath bezierPath];
    for (NSUInteger point = 0; point <= pointCount; point += 1) {
        CGFloat angle = (((CGFloat)point) / ((CGFloat)pointCount)) * (CGFloat)(M_PI * 2.0);
        CGFloat wobbleA = sinf((angle * 2.0f) + phase) * amplitude;
        CGFloat wobbleB = cosf((angle * 3.0f) - (phase * 0.74f)) * amplitude * 0.54f;
        CGFloat wobbleC = sinf((angle * 5.0f) + (phase * 1.12f)) * amplitude * 0.20f;
        CGFloat x = centerX + (cosf(angle) * (radiusX + wobbleA + wobbleB));
        CGFloat y = centerY + (sinf(angle) * (radiusY + (wobbleA * 0.72f) - (wobbleB * 0.16f) + wobbleC));
        CGPoint p = CGPointMake(x, y);
        if (point == 0) {
            [path moveToPoint:p];
        } else {
            [path addLineToPoint:p];
        }
    }
    [path closePath];
    return path;
}

- (void)restartLineAnimations {
    if (CGRectIsEmpty(self.bounds)) {
        return;
    }
    self.hasStartedAnimations = YES;

    CGFloat durationMultiplier = self.playing ? 1.0f : 1.28f;
    [self.lineLayers enumerateObjectsUsingBlock:^(CAShapeLayer * _Nonnull line, NSUInteger idx, BOOL * _Nonnull stop) {
        (void)stop;
        [line removeAnimationForKey:@"sonora_wave_line_path"];
        [line removeAnimationForKey:@"sonora_wave_line_scale"];
        [line removeAnimationForKey:@"sonora_wave_line_rotation"];
        [line removeAnimationForKey:@"sonora_wave_line_shadow"];
        [line removeAnimationForKey:@"sonora_wave_line_opacity"];

        UIBezierPath *path0 = [self contourPathForIndex:idx variant:0];
        UIBezierPath *path1 = [self contourPathForIndex:idx variant:1];
        UIBezierPath *path2 = [self contourPathForIndex:idx variant:2];
        line.path = path0.CGPath;

        CGFloat baseOpacity = self.playing
        ? (idx < 2 ? 0.96f : (idx < 4 ? 0.82f : 0.66f))
        : (idx < 2 ? 0.78f : (idx < 4 ? 0.64f : 0.52f));
        CGFloat swing = self.playing ? 0.16f : 0.10f;
        line.opacity = baseOpacity;

        CAKeyframeAnimation *pathAnim = [CAKeyframeAnimation animationWithKeyPath:@"path"];
        pathAnim.values = @[
            (__bridge id)path0.CGPath,
            (__bridge id)path1.CGPath,
            (__bridge id)path2.CGPath,
            (__bridge id)path0.CGPath
        ];
        pathAnim.keyTimes = @[@0.0, @0.34, @0.68, @1.0];
        pathAnim.duration = (8.4 + (((CGFloat)idx) * 0.85f)) * durationMultiplier;
        pathAnim.repeatCount = HUGE_VALF;
        pathAnim.calculationMode = kCAAnimationLinear;
        pathAnim.beginTime = CACurrentMediaTime() + (((CGFloat)idx) * 0.08f);
        pathAnim.timingFunctions = @[
            [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut],
            [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut],
            [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]
        ];
        [line addAnimation:pathAnim forKey:@"sonora_wave_line_path"];

        CAKeyframeAnimation *opacityAnim = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
        opacityAnim.values = @[
            @(baseOpacity - (swing * 0.35f)),
            @(baseOpacity + swing),
            @(baseOpacity - (swing * 0.18f)),
            @(baseOpacity - (swing * 0.35f))
        ];
        opacityAnim.keyTimes = @[@0.0, @0.32, @0.70, @1.0];
        opacityAnim.duration = (4.8 + (((CGFloat)idx) * 0.50)) * durationMultiplier;
        opacityAnim.repeatCount = HUGE_VALF;
        opacityAnim.beginTime = CACurrentMediaTime() + (((CGFloat)idx) * 0.08f);
        opacityAnim.timingFunctions = @[
            [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut],
            [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut],
            [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]
        ];
        [line addAnimation:opacityAnim forKey:@"sonora_wave_line_opacity"];

        if (self.playing) {
            CABasicAnimation *scaleAnim = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
            scaleAnim.fromValue = @(0.998f - (((CGFloat)idx) * 0.0008f));
            scaleAnim.toValue = @(1.010f + (((CGFloat)idx) * 0.0012f));
            scaleAnim.duration = 7.4 + (((CGFloat)idx) * 0.70f);
            scaleAnim.autoreverses = YES;
            scaleAnim.repeatCount = HUGE_VALF;
            scaleAnim.beginTime = CACurrentMediaTime() + (((CGFloat)idx) * 0.06f);
            scaleAnim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            [line addAnimation:scaleAnim forKey:@"sonora_wave_line_scale"];

            CABasicAnimation *rotationAnim = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
            CGFloat rotation = 0.0016f + (((CGFloat)idx) * 0.0006f);
            rotationAnim.fromValue = @(-rotation);
            rotationAnim.toValue = @(rotation);
            rotationAnim.duration = 12.2 + (((CGFloat)idx) * 0.80f);
            rotationAnim.autoreverses = YES;
            rotationAnim.repeatCount = HUGE_VALF;
            rotationAnim.beginTime = CACurrentMediaTime() + (((CGFloat)idx) * 0.05f);
            rotationAnim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            [line addAnimation:rotationAnim forKey:@"sonora_wave_line_rotation"];

            CABasicAnimation *shadowAnim = [CABasicAnimation animationWithKeyPath:@"shadowOpacity"];
            shadowAnim.fromValue = @(MAX(0.0f, line.shadowOpacity * 0.78f));
            shadowAnim.toValue = @(MIN(1.0f, line.shadowOpacity + 0.18f));
            shadowAnim.duration = 5.6 + (((CGFloat)idx) * 0.55f);
            shadowAnim.autoreverses = YES;
            shadowAnim.repeatCount = HUGE_VALF;
            shadowAnim.beginTime = CACurrentMediaTime() + (((CGFloat)idx) * 0.04f);
            shadowAnim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            [line addAnimation:shadowAnim forKey:@"sonora_wave_line_shadow"];
        }
    }];
}

- (void)restartGlowAnimations {
    [self.haloLayer removeAnimationForKey:@"sonora_wave_halo_scale"];
    [self.haloLayer removeAnimationForKey:@"sonora_wave_halo_opacity"];
    [self.coreGlowLayer removeAnimationForKey:@"sonora_wave_core_scale"];
    [self.coreGlowLayer removeAnimationForKey:@"sonora_wave_core_opacity"];

    CABasicAnimation *haloScale = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    haloScale.fromValue = @(self.playing ? 0.96f : 0.985f);
    haloScale.toValue = @(self.playing ? 1.08f : 1.03f);
    haloScale.duration = self.playing ? 4.2 : 6.0;
    haloScale.autoreverses = YES;
    haloScale.repeatCount = HUGE_VALF;
    haloScale.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.haloLayer addAnimation:haloScale forKey:@"sonora_wave_halo_scale"];

    CABasicAnimation *haloOpacity = [CABasicAnimation animationWithKeyPath:@"opacity"];
    haloOpacity.fromValue = @(self.playing ? 0.80f : 0.64f);
    haloOpacity.toValue = @(self.playing ? 1.0f : 0.82f);
    haloOpacity.duration = self.playing ? 3.6 : 5.4;
    haloOpacity.autoreverses = YES;
    haloOpacity.repeatCount = HUGE_VALF;
    haloOpacity.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.haloLayer addAnimation:haloOpacity forKey:@"sonora_wave_halo_opacity"];

    CABasicAnimation *coreScale = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    coreScale.fromValue = @(self.playing ? 0.92f : 0.96f);
    coreScale.toValue = @(self.playing ? 1.04f : 1.01f);
    coreScale.duration = self.playing ? 5.4 : 7.2;
    coreScale.autoreverses = YES;
    coreScale.repeatCount = HUGE_VALF;
    coreScale.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.coreGlowLayer addAnimation:coreScale forKey:@"sonora_wave_core_scale"];

    CABasicAnimation *coreOpacity = [CABasicAnimation animationWithKeyPath:@"opacity"];
    coreOpacity.fromValue = @(self.playing ? 0.52f : 0.38f);
    coreOpacity.toValue = @(self.playing ? 0.82f : 0.58f);
    coreOpacity.duration = self.playing ? 4.8 : 6.6;
    coreOpacity.autoreverses = YES;
    coreOpacity.repeatCount = HUGE_VALF;
    coreOpacity.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.coreGlowLayer addAnimation:coreOpacity forKey:@"sonora_wave_core_opacity"];
}

- (void)restartAnimations {
    [self restartLineAnimations];
    [self restartGlowAnimations];
}

- (void)ensureAnimationsRunning {
    if (CGRectIsEmpty(self.bounds) || self.lineLayers.count == 0) {
        return;
    }

    __block BOOL isMissingLineAnimations = NO;
    [self.lineLayers enumerateObjectsUsingBlock:^(CAShapeLayer * _Nonnull line, NSUInteger idx, BOOL * _Nonnull stop) {
        (void)idx;
        if ([line animationForKey:@"sonora_wave_line_path"] == nil ||
            [line animationForKey:@"sonora_wave_line_opacity"] == nil ||
            (self.playing && [line animationForKey:@"sonora_wave_line_scale"] == nil)) {
            isMissingLineAnimations = YES;
            *stop = YES;
        }
    }];

    BOOL isMissingGlowAnimations =
    ([self.haloLayer animationForKey:@"sonora_wave_halo_scale"] == nil) ||
    ([self.haloLayer animationForKey:@"sonora_wave_halo_opacity"] == nil) ||
    ([self.coreGlowLayer animationForKey:@"sonora_wave_core_scale"] == nil) ||
    ([self.coreGlowLayer animationForKey:@"sonora_wave_core_opacity"] == nil);

    if (isMissingLineAnimations) {
        [self restartLineAnimations];
    }
    if (isMissingGlowAnimations) {
        [self restartGlowAnimations];
    }
    [self updatePlaybackStateAnimated:NO];
}

- (void)transitionToUpdatedGeometry {
    if (CGRectIsEmpty(self.bounds)) {
        return;
    }
    if (!self.hasStartedAnimations) {
        [self configureLineGeometry];
        return;
    }

    self.geometryTransitionGeneration += 1;
    NSUInteger generation = self.geometryTransitionGeneration;
    CGFloat duration = self.playing ? 1.02f : 1.16f;
    CGFloat scale = MAX(0.92f, MIN(1.20f, MIN(CGRectGetWidth(self.bounds) / 360.0f, CGRectGetHeight(self.bounds) / 220.0f)));
    NSArray<NSNumber *> *lineWidths = @[
        @(2.8f * scale),
        @(2.5f * scale),
        @(2.2f * scale),
        @(1.9f * scale),
        @(1.7f * scale),
        @(1.5f * scale),
        @(1.2f * scale)
    ];

    [self.lineLayers enumerateObjectsUsingBlock:^(CAShapeLayer * _Nonnull line, NSUInteger idx, BOOL * _Nonnull stop) {
        (void)stop;
        UIBezierPath *targetPath = [self contourPathForIndex:idx variant:0];
        CGPathRef currentPath = ((CAShapeLayer *)line.presentationLayer).path ?: line.path;
        CGFloat currentWidth = ((CAShapeLayer *)line.presentationLayer).lineWidth > 0.0f
        ? ((CAShapeLayer *)line.presentationLayer).lineWidth
        : line.lineWidth;
        CGFloat currentOpacity = ((CAShapeLayer *)line.presentationLayer).opacity > 0.0f
        ? ((CAShapeLayer *)line.presentationLayer).opacity
        : line.opacity;
        CGFloat currentShadowOpacity = ((CAShapeLayer *)line.presentationLayer).shadowOpacity > 0.0f
        ? ((CAShapeLayer *)line.presentationLayer).shadowOpacity
        : line.shadowOpacity;
        CGFloat targetWidth = lineWidths[idx].doubleValue;

        [line removeAnimationForKey:@"sonora_wave_line_path"];
        [line removeAnimationForKey:@"sonora_wave_line_scale"];
        [line removeAnimationForKey:@"sonora_wave_line_rotation"];
        [line removeAnimationForKey:@"sonora_wave_line_shadow"];
        [line removeAnimationForKey:@"sonora_wave_line_opacity"];
        [line removeAnimationForKey:@"sonora_wave_line_transition"];
        [line removeAnimationForKey:@"sonora_wave_line_width_transition"];

        if (currentPath != NULL) {
            CABasicAnimation *pathTransition = [CABasicAnimation animationWithKeyPath:@"path"];
            pathTransition.fromValue = (__bridge id)currentPath;
            pathTransition.toValue = (__bridge id)targetPath.CGPath;
            pathTransition.duration = duration;
            pathTransition.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            [line addAnimation:pathTransition forKey:@"sonora_wave_line_transition"];
        }

        CABasicAnimation *widthTransition = [CABasicAnimation animationWithKeyPath:@"lineWidth"];
        widthTransition.fromValue = @(currentWidth);
        widthTransition.toValue = @(targetWidth);
        widthTransition.duration = duration;
        widthTransition.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [line addAnimation:widthTransition forKey:@"sonora_wave_line_width_transition"];

        line.opacity = currentOpacity;
        line.shadowOpacity = currentShadowOpacity;
        line.lineWidth = targetWidth;
        line.path = targetPath.CGPath;
    }];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((duration + 0.04f) * (CGFloat)NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.geometryTransitionGeneration != generation) {
            return;
        }
        [self restartLineAnimations];
    });
}

- (void)updatePlaybackStateAnimated:(BOOL)animated {
    CGFloat haloOpacity = self.playing ? 0.94f : 0.78f;
    CGFloat coreOpacity = self.playing ? 0.74f : 0.50f;
    CGFloat lineOpacity = self.playing ? 1.0f : 0.92f;
    if (animated) {
        CABasicAnimation *haloAnim = [CABasicAnimation animationWithKeyPath:@"opacity"];
        haloAnim.fromValue = @(self.haloLayer.opacity);
        haloAnim.toValue = @(haloOpacity);
        haloAnim.duration = 0.28;
        [self.haloLayer addAnimation:haloAnim forKey:@"sonora_wave_state_halo_opacity"];

        CABasicAnimation *containerAnim = [CABasicAnimation animationWithKeyPath:@"opacity"];
        containerAnim.fromValue = @(self.lineContainerLayer.opacity);
        containerAnim.toValue = @(lineOpacity);
        containerAnim.duration = 0.28;
        [self.lineContainerLayer addAnimation:containerAnim forKey:@"sonora_wave_state_line_opacity"];

        CABasicAnimation *coreAnim = [CABasicAnimation animationWithKeyPath:@"opacity"];
        coreAnim.fromValue = @(self.coreGlowLayer.opacity);
        coreAnim.toValue = @(coreOpacity);
        coreAnim.duration = 0.28;
        [self.coreGlowLayer addAnimation:coreAnim forKey:@"sonora_wave_state_core_opacity"];
    }
    self.haloLayer.opacity = haloOpacity;
    self.coreGlowLayer.opacity = coreOpacity;
    self.lineContainerLayer.opacity = lineOpacity;
}

@end



@interface SonoraWaveNebulaBackgroundView : UIView

- (void)applyPalette:(NSArray<UIColor *> *)palette animated:(BOOL)animated;
- (void)setPlaying:(BOOL)playing;
- (void)setPulseSeedWithTrackIdentifier:(NSString * _Nullable)identifier;

@end

@interface SonoraWaveNebulaBackgroundView ()

@property (nonatomic, strong) CAGradientLayer *baseGradientLayer;
@property (nonatomic, strong) CALayer *blobContainerLayer;
@property (nonatomic, strong) NSArray<CAGradientLayer *> *blobLayers;
@property (nonatomic, strong) CAGradientLayer *cloudMaskLayer;
@property (nonatomic, strong) CAGradientLayer *pulseLayer;
@property (nonatomic, strong) CAGradientLayer *vignetteLayer;
@property (nonatomic, strong) UIImageView *grainView;
@property (nonatomic, strong, nullable) CADisplayLink *displayLink;
@property (nonatomic, assign) BOOL hasStartedAnimations;
@property (nonatomic, assign) BOOL playing;
@property (nonatomic, assign) CGFloat pulseSeed;
@property (nonatomic, assign) CFTimeInterval phaseStartTime;

@end

@implementation SonoraWaveNebulaBackgroundView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.pulseSeed = 0.43f;
        self.phaseStartTime = CACurrentMediaTime();
        [self setupUI];
    }
    return self;
}

- (void)dealloc {
    [self.displayLink invalidate];
    self.displayLink = nil;
}

- (void)setupUI {
    self.clipsToBounds = YES;

    CAGradientLayer *base = [CAGradientLayer layer];
    base.startPoint = CGPointMake(0.0, 0.0);
    base.endPoint = CGPointMake(1.0, 1.0);
    base.colors = @[
        (__bridge id)[UIColor clearColor].CGColor,
        (__bridge id)[UIColor clearColor].CGColor,
        (__bridge id)[UIColor clearColor].CGColor
    ];
    [self.layer addSublayer:base];
    self.baseGradientLayer = base;

    CALayer *blobContainer = [CALayer layer];
    [self.layer addSublayer:blobContainer];
    self.blobContainerLayer = blobContainer;

    CAGradientLayer *cloudMask = [CAGradientLayer layer];
    cloudMask.type = kCAGradientLayerRadial;
    cloudMask.startPoint = CGPointMake(0.5, 0.5);
    cloudMask.endPoint = CGPointMake(1.0, 1.0);
    cloudMask.colors = @[
        (__bridge id)[UIColor colorWithWhite:1.0 alpha:1.0].CGColor,
        (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.78].CGColor,
        (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor
    ];
    cloudMask.locations = @[@0.0, @0.72, @1.0];
    blobContainer.mask = cloudMask;
    self.cloudMaskLayer = cloudMask;

    NSMutableArray<CAGradientLayer *> *blobs = [NSMutableArray arrayWithCapacity:7];
    for (NSUInteger idx = 0; idx < 7; idx += 1) {
        CAGradientLayer *blob = [CAGradientLayer layer];
        blob.type = kCAGradientLayerRadial;
        blob.startPoint = CGPointMake(0.5, 0.5);
        blob.endPoint = CGPointMake(1.0, 1.0);
        blob.colors = @[
            (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.38].CGColor,
            (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.13].CGColor,
            (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor
        ];
        blob.locations = @[@0.0, @0.54, @1.0];
        blob.opacity = 1.0;
        [blobContainer addSublayer:blob];
        [blobs addObject:blob];
    }
    self.blobLayers = [blobs copy];

    CAGradientLayer *pulse = [CAGradientLayer layer];
    pulse.type = kCAGradientLayerRadial;
    pulse.startPoint = CGPointMake(0.5, 0.5);
    pulse.endPoint = CGPointMake(1.0, 1.0);
    pulse.colors = @[
        (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.14].CGColor,
        (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor
    ];
    pulse.locations = @[@0.0, @1.0];
    pulse.opacity = 0.16;
    [self.layer addSublayer:pulse];
    self.pulseLayer = pulse;

    CAGradientLayer *vignette = [CAGradientLayer layer];
    vignette.type = kCAGradientLayerRadial;
    vignette.startPoint = CGPointMake(0.5, 0.5);
    vignette.endPoint = CGPointMake(1.0, 1.0);
    vignette.colors = @[
        (__bridge id)[UIColor colorWithWhite:0.0 alpha:0.0].CGColor,
        (__bridge id)[UIColor colorWithWhite:0.0 alpha:0.0].CGColor
    ];
    [self.layer addSublayer:vignette];
    self.vignetteLayer = vignette;

    UIImageView *grainView = [[UIImageView alloc] init];
    grainView.translatesAutoresizingMaskIntoConstraints = NO;
    grainView.userInteractionEnabled = NO;
    grainView.alpha = 0.10;
    grainView.image = [self grainImage];
    grainView.contentMode = UIViewContentModeScaleToFill;
    self.grainView = grainView;
    [self addSubview:grainView];

    [NSLayoutConstraint activateConstraints:@[
        [grainView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [grainView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [grainView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [grainView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
    ]];
}

- (UIImage *)grainImage {
    const size_t width = 96;
    const size_t height = 96;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, height), NO, 1.0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (context == NULL) {
        return [UIImage new];
    }

    for (NSUInteger y = 0; y < height; y += 1) {
        for (NSUInteger x = 0; x < width; x += 1) {
            CGFloat value = ((CGFloat)arc4random_uniform(1000)) / 1000.0;
            CGFloat alpha = 0.01 + (value * 0.04);
            UIColor *color = (value > 0.5)
            ? [UIColor colorWithWhite:1.0 alpha:alpha]
            : [UIColor colorWithWhite:0.0 alpha:alpha * 0.8];
            CGContextSetFillColorWithColor(context, color.CGColor);
            CGContextFillRect(context, CGRectMake(x, y, 1.0, 1.0));
        }
    }
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.baseGradientLayer.frame = self.bounds;
    self.blobContainerLayer.frame = self.bounds;
    self.cloudMaskLayer.frame = self.bounds;
    self.pulseLayer.frame = self.bounds;
    self.vignetteLayer.frame = self.bounds;

    CGFloat w = CGRectGetWidth(self.bounds);
    CGFloat h = CGRectGetHeight(self.bounds);
    CGFloat minSide = MIN(w, h);
    NSArray<NSValue *> *centers = @[
        [NSValue valueWithCGPoint:CGPointMake(w * 0.37, h * 0.43)],
        [NSValue valueWithCGPoint:CGPointMake(w * 0.63, h * 0.42)],
        [NSValue valueWithCGPoint:CGPointMake(w * 0.50, h * 0.56)],
        [NSValue valueWithCGPoint:CGPointMake(w * 0.34, h * 0.58)],
        [NSValue valueWithCGPoint:CGPointMake(w * 0.66, h * 0.57)],
        [NSValue valueWithCGPoint:CGPointMake(w * 0.48, h * 0.32)],
        [NSValue valueWithCGPoint:CGPointMake(w * 0.52, h * 0.70)]
    ];
    NSArray<NSNumber *> *sizes = @[
        @(MAX(minSide * 0.72, 160.0)),
        @(MAX(minSide * 0.68, 152.0)),
        @(MAX(minSide * 0.80, 178.0)),
        @(MAX(minSide * 0.60, 138.0)),
        @(MAX(minSide * 0.58, 132.0)),
        @(MAX(minSide * 0.54, 124.0)),
        @(MAX(minSide * 0.52, 120.0))
    ];

    [self.blobLayers enumerateObjectsUsingBlock:^(CAGradientLayer * _Nonnull layer, NSUInteger idx, BOOL * _Nonnull stop) {
        (void)stop;
        CGFloat size = sizes[idx].doubleValue;
        CGPoint center = centers[idx].CGPointValue;
        layer.bounds = CGRectMake(0.0, 0.0, size, size);
        layer.position = center;
    }];

    [self startAnimationsIfNeeded];
}

- (void)startAnimationsIfNeeded {
    if (self.hasStartedAnimations) {
        return;
    }
    self.hasStartedAnimations = YES;

    NSArray<NSNumber *> *durations = @[@(10.8), @(9.6), @(11.8), @(8.6), @(12.6), @(9.0), @(10.2)];
    [self.blobLayers enumerateObjectsUsingBlock:^(CAGradientLayer * _Nonnull layer, NSUInteger idx, BOOL * _Nonnull stop) {
        (void)stop;
        CABasicAnimation *scale = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        scale.fromValue = @(0.96);
        scale.toValue = @(1.04);
        scale.duration = durations[idx].doubleValue;
        scale.autoreverses = YES;
        scale.repeatCount = HUGE_VALF;
        scale.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [layer addAnimation:scale forKey:[NSString stringWithFormat:@"sonora_wave_scale_%lu", (unsigned long)idx]];

        CABasicAnimation *position = [CABasicAnimation animationWithKeyPath:@"position"];
        CGPoint p = layer.position;
        CGFloat shiftX = 8.0 + ((CGFloat)idx * 2.0);
        CGFloat shiftY = 6.0 + ((CGFloat)(idx % 3) * 2.0);
        position.fromValue = [NSValue valueWithCGPoint:CGPointMake(p.x - shiftX, p.y + shiftY)];
        position.toValue = [NSValue valueWithCGPoint:CGPointMake(p.x + shiftX, p.y - shiftY)];
        position.duration = durations[idx].doubleValue + 1.2;
        position.autoreverses = YES;
        position.repeatCount = HUGE_VALF;
        position.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [layer addAnimation:position forKey:[NSString stringWithFormat:@"sonora_wave_position_%lu", (unsigned long)idx]];
    }];
    [self startDisplayLinkIfNeeded];
}

- (void)startDisplayLinkIfNeeded {
    if (self.displayLink != nil) {
        return;
    }
    CADisplayLink *link = [CADisplayLink displayLinkWithTarget:self selector:@selector(handleDisplayLinkTick:)];
    [link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    self.displayLink = link;
    self.phaseStartTime = CACurrentMediaTime();
}

- (void)handleDisplayLinkTick:(CADisplayLink *)link {
    (void)link;
    CFTimeInterval elapsed = CACurrentMediaTime() - self.phaseStartTime;
    CGFloat t = (CGFloat)elapsed;

    CGFloat ambient = 0.5f + (0.5f * sinf((t * 0.52f) + (self.pulseSeed * 6.28318f)));
    CGFloat drift = 0.5f + (0.5f * cosf((t * 0.38f) + (self.pulseSeed * 4.398f)));

    CGFloat audioImpulse = 0.0f;
    if (self.playing) {
        SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
        CGFloat position = (CGFloat)MAX(0.0, playback.currentTime);
        CGFloat duration = (CGFloat)MAX(1.0, playback.duration);
        CGFloat bpm = 92.0f + fmodf((self.pulseSeed * 71.0f) + duration, 46.0f);
        CGFloat beatPhase = position * (bpm / 60.0f) * 6.28318f;
        CGFloat primary = powf(MAX(0.0f, sinf(beatPhase)), 2.8f);
        CGFloat secondary = powf(MAX(0.0f, sinf((beatPhase * 0.5f) + 0.75f)), 4.0f) * 0.42f;
        audioImpulse = MIN(1.0f, primary + secondary);
    }

    CGFloat pulseOpacity = 0.10f + (ambient * 0.08f) + (audioImpulse * 0.30f);
    self.pulseLayer.opacity = pulseOpacity;
    CGFloat pulseScale = 0.96f + (drift * 0.03f) + (audioImpulse * 0.11f);
    self.pulseLayer.transform = CATransform3DMakeScale(pulseScale, pulseScale, 1.0f);

    [self.blobLayers enumerateObjectsUsingBlock:^(CAGradientLayer * _Nonnull layer, NSUInteger idx, BOOL * _Nonnull stop) {
        (void)stop;
        CGFloat idxBoost = MAX(0.07f, 0.20f - (((CGFloat)idx) * 0.017f));
        layer.opacity = 0.82f + (ambient * 0.08f) + (audioImpulse * idxBoost);
    }];
}

- (void)setPlaying:(BOOL)playing {
    _playing = playing;
}

- (void)setPulseSeedWithTrackIdentifier:(NSString * _Nullable)identifier {
    const char *utf8 = identifier.UTF8String;
    if (utf8 == NULL || utf8[0] == '\0') {
        self.pulseSeed = 0.43f;
        self.phaseStartTime = CACurrentMediaTime();
        return;
    }

    uint64_t hash = 1469598103934665603ULL;
    const uint8_t *bytes = (const uint8_t *)utf8;
    while (*bytes != 0) {
        hash ^= (uint64_t)(*bytes);
        hash *= 1099511628211ULL;
        bytes += 1;
    }
    self.pulseSeed = (CGFloat)((hash % 1000ULL) / 1000.0);
    self.phaseStartTime = CACurrentMediaTime();
}

- (void)applyPalette:(NSArray<UIColor *> *)palette animated:(BOOL)animated {
    NSArray<UIColor *> *resolved = (palette.count >= 4) ? palette : SonoraResolvedWavePalette(nil);

    NSArray *baseColors = @[
        (__bridge id)[UIColor clearColor].CGColor,
        (__bridge id)[UIColor clearColor].CGColor,
        (__bridge id)[UIColor clearColor].CGColor
    ];
    if (animated) {
        CABasicAnimation *baseAnim = [CABasicAnimation animationWithKeyPath:@"colors"];
        baseAnim.fromValue = self.baseGradientLayer.colors;
        baseAnim.toValue = baseColors;
        baseAnim.duration = 2.0;
        baseAnim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [self.baseGradientLayer addAnimation:baseAnim forKey:@"sonora_wave_base_colors"];
    }
    self.baseGradientLayer.colors = baseColors;

    UIColor *pulseColor = SonoraBlendColor(resolved[3], UIColor.whiteColor, 0.26);
    NSArray *pulseColors = @[
        (__bridge id)[pulseColor colorWithAlphaComponent:0.20].CGColor,
        (__bridge id)[pulseColor colorWithAlphaComponent:0.0].CGColor
    ];
    if (animated) {
        CABasicAnimation *pulseAnim = [CABasicAnimation animationWithKeyPath:@"colors"];
        pulseAnim.fromValue = self.pulseLayer.colors;
        pulseAnim.toValue = pulseColors;
        pulseAnim.duration = 2.0;
        pulseAnim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [self.pulseLayer addAnimation:pulseAnim forKey:@"sonora_wave_pulse_colors"];
    }
    self.pulseLayer.colors = pulseColors;

    NSArray<UIColor *> *blobColors = @[
        resolved[1],
        resolved[2],
        resolved[3],
        resolved[0],
        resolved[2],
        resolved[3],
        resolved[1]
    ];
    [self.blobLayers enumerateObjectsUsingBlock:^(CAGradientLayer * _Nonnull layer, NSUInteger idx, BOOL * _Nonnull stop) {
        (void)stop;
        UIColor *color = blobColors[idx];
        NSArray *colors = @[
            (__bridge id)[color colorWithAlphaComponent:0.38].CGColor,
            (__bridge id)[color colorWithAlphaComponent:0.13].CGColor,
            (__bridge id)[color colorWithAlphaComponent:0.0].CGColor
        ];
        if (animated) {
            CABasicAnimation *anim = [CABasicAnimation animationWithKeyPath:@"colors"];
            anim.fromValue = layer.colors;
            anim.toValue = colors;
            anim.duration = 1.8;
            anim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            [layer addAnimation:anim forKey:[NSString stringWithFormat:@"sonora_wave_blob_colors_%lu", (unsigned long)idx]];
        }
        layer.colors = colors;
    }];
}

@end

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
    titleLabel.font = SonoraNotoSerifBoldFont(30.0);
    titleLabel.textColor = UIColor.labelColor;
    titleLabel.numberOfLines = 1;
    titleLabel.text = @"My wave";
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
        [titleLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor constant:-16.0],
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
    self.titleLabel.text = @"My wave";
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

@interface SonoraHomeAlbumDetailViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

- (instancetype)initWithAlbumTitle:(NSString *)albumTitle tracks:(NSArray<SonoraTrack *> *)tracks;

@end

@interface SonoraHomeAlbumDetailViewController ()

@property (nonatomic, copy) NSString *albumTitle;
@property (nonatomic, copy) NSArray<SonoraTrack *> *tracks;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UIButton *shuffleButton;
@property (nonatomic, strong) UIButton *sleepControlButton;

@end

@implementation SonoraHomeAlbumDetailViewController

- (instancetype)initWithAlbumTitle:(NSString *)albumTitle tracks:(NSArray<SonoraTrack *> *)tracks {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _albumTitle = [albumTitle copy] ?: @"Album";
        _tracks = [tracks copy] ?: @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.navigationItem.title = nil;
    self.navigationItem.titleView = nil;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.rightBarButtonItem = nil;

    [self setupTableView];
    [self updateHeader];
    [self updatePlayButtonState];
    [self updateEmptyState];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handlePlaybackChanged)
                                               name:SonoraPlaybackStateDidChangeNotification
                                             object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handleSleepTimerChanged)
                                               name:SonoraSleepTimerDidChangeNotification
                                             object:nil];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updatePlayButtonState];
    [self updateSleepTimerButton];
    [self.tableView reloadData];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat width = self.view.bounds.size.width;
    if (fabs(self.tableView.tableHeaderView.bounds.size.width - width) > 1.0) {
        self.tableView.tableHeaderView = [self headerViewForWidth:width];
        [self updateHeader];
        [self updatePlayButtonState];
    }
}

- (void)setupTableView {
    UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    tableView.translatesAutoresizingMaskIntoConstraints = NO;
    tableView.dataSource = self;
    tableView.delegate = self;
    tableView.rowHeight = 54.0;
    tableView.alwaysBounceVertical = YES;
    tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    if (@available(iOS 15.0, *)) {
        tableView.sectionHeaderTopPadding = 0.0;
    }
    [tableView registerClass:SonoraTrackCell.class forCellReuseIdentifier:@"SonoraHomeAlbumTrackCell"];

    self.tableView = tableView;
    [self.view addSubview:tableView];

    [NSLayoutConstraint activateConstraints:@[
        [tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    self.tableView.tableHeaderView = [self headerViewForWidth:self.view.bounds.size.width];
}

- (UIView *)headerViewForWidth:(CGFloat)width {
    CGFloat totalWidth = MAX(width, 320.0);
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, totalWidth, 368.0)];

    UIImageView *coverView = [[UIImageView alloc] initWithFrame:CGRectMake((totalWidth - 212.0) * 0.5, 16.0, 212.0, 212.0)];
    coverView.layer.cornerRadius = 16.0;
    coverView.layer.masksToBounds = YES;
    coverView.contentMode = UIViewContentModeScaleAspectFill;
    self.coverView = coverView;

    UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(14.0, 236.0, totalWidth - 28.0, 32.0)];
    nameLabel.textAlignment = NSTextAlignmentCenter;
    nameLabel.font = SonoraYSMusicFont(28.0);
    nameLabel.textColor = UIColor.labelColor;
    self.nameLabel = nameLabel;

    CGFloat playSize = 66.0;
    CGFloat shuffleSize = 46.0;
    CGFloat sleepSize = 46.0;
    CGFloat controlsY = 276.0;

    UIButton *playButton = [UIButton buttonWithType:UIButtonTypeSystem];
    playButton.frame = CGRectMake((totalWidth - playSize) * 0.5, controlsY, playSize, playSize);
    playButton.backgroundColor = SonoraHomeAccentYellowColor();
    playButton.tintColor = UIColor.whiteColor;
    playButton.layer.cornerRadius = playSize * 0.5;
    playButton.layer.masksToBounds = YES;
    UIImageSymbolConfiguration *playConfig = [UIImageSymbolConfiguration configurationWithPointSize:29.0
                                                                                               weight:UIImageSymbolWeightSemibold];
    [playButton setImage:[UIImage systemImageNamed:@"play.fill" withConfiguration:playConfig] forState:UIControlStateNormal];
    [playButton addTarget:self action:@selector(playTapped) forControlEvents:UIControlEventTouchUpInside];
    self.playButton = playButton;

    UIButton *shuffleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    shuffleButton.frame = CGRectMake(CGRectGetMaxX(playButton.frame) + 16.0,
                                     controlsY + (playSize - shuffleSize) * 0.5,
                                     shuffleSize,
                                     shuffleSize);
    UIImageSymbolConfiguration *shuffleConfig = [UIImageSymbolConfiguration configurationWithPointSize:22.0
                                                                                                 weight:UIImageSymbolWeightSemibold];
    [shuffleButton setImage:[UIImage systemImageNamed:@"shuffle" withConfiguration:shuffleConfig] forState:UIControlStateNormal];
    shuffleButton.tintColor = UIColor.labelColor;
    shuffleButton.backgroundColor = UIColor.clearColor;
    [shuffleButton addTarget:self action:@selector(shuffleTapped) forControlEvents:UIControlEventTouchUpInside];
    self.shuffleButton = shuffleButton;

    UIButton *sleepButton = [UIButton buttonWithType:UIButtonTypeSystem];
    sleepButton.frame = CGRectMake(CGRectGetMinX(playButton.frame) - 16.0 - sleepSize,
                                   controlsY + (playSize - sleepSize) * 0.5,
                                   sleepSize,
                                   sleepSize);
    UIImageSymbolConfiguration *sleepConfig = [UIImageSymbolConfiguration configurationWithPointSize:21.0
                                                                                                weight:UIImageSymbolWeightSemibold];
    [sleepButton setImage:[UIImage systemImageNamed:@"moon.zzz" withConfiguration:sleepConfig] forState:UIControlStateNormal];
    sleepButton.tintColor = UIColor.labelColor;
    sleepButton.backgroundColor = UIColor.clearColor;
    [sleepButton addTarget:self action:@selector(sleepTimerTapped) forControlEvents:UIControlEventTouchUpInside];
    self.sleepControlButton = sleepButton;

    [header addSubview:coverView];
    [header addSubview:nameLabel];
    [header addSubview:playButton];
    [header addSubview:sleepButton];
    [header addSubview:shuffleButton];

    [self updateSleepTimerButton];
    return header;
}

- (void)updateHeader {
    self.nameLabel.text = self.albumTitle.length > 0 ? self.albumTitle : @"Album";
    UIImage *cover = self.tracks.firstObject.artwork;
    if (cover == nil) {
        cover = [UIImage imageNamed:@"LovelyCover"];
    }
    self.coverView.image = cover;

    UIColor *playColor = [SonoraArtworkAccentColorService dominantAccentColorForImage:cover
                                                                          fallback:SonoraHomeAccentYellowColor()];
    self.playButton.backgroundColor = playColor ?: SonoraHomeAccentYellowColor();
}

- (BOOL)isCurrentQueueMatchingAlbum {
    NSArray<SonoraTrack *> *queue = SonoraPlaybackManager.sharedManager.currentQueue;
    if (queue.count != self.tracks.count || self.tracks.count == 0) {
        return NO;
    }

    for (NSUInteger idx = 0; idx < self.tracks.count; idx += 1) {
        NSString *left = queue[idx].identifier ?: @"";
        NSString *right = self.tracks[idx].identifier ?: @"";
        if (![left isEqualToString:right]) {
            return NO;
        }
    }
    return YES;
}

- (void)updatePlayButtonState {
    if (self.playButton == nil) {
        return;
    }

    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    BOOL isAlbumPlaying = [self isCurrentQueueMatchingAlbum] &&
    playback.isPlaying &&
    (playback.currentTrack != nil);
    NSString *symbol = isAlbumPlaying ? @"pause.fill" : @"play.fill";
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:29.0
                                                                                          weight:UIImageSymbolWeightSemibold];
    [self.playButton setImage:[UIImage systemImageNamed:symbol withConfiguration:config] forState:UIControlStateNormal];
}

- (void)updateEmptyState {
    if (self.tracks.count > 0) {
        self.tableView.backgroundView = nil;
        return;
    }

    UILabel *label = [[UILabel alloc] init];
    label.text = @"No tracks in this album.";
    label.textColor = UIColor.secondaryLabelColor;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
    self.tableView.backgroundView = label;
}

- (void)updateSleepTimerButton {
    if (self.sleepControlButton == nil) {
        return;
    }

    BOOL isActive = SonoraSleepTimerManager.sharedManager.isActive;
    NSString *symbol = isActive ? @"moon.zzz.fill" : @"moon.zzz";
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:21.0
                                                                                          weight:UIImageSymbolWeightSemibold];
    [self.sleepControlButton setImage:[UIImage systemImageNamed:symbol withConfiguration:config] forState:UIControlStateNormal];
    self.sleepControlButton.tintColor = isActive ? SonoraHomeAccentYellowColor() : UIColor.labelColor;
    self.sleepControlButton.accessibilityLabel = isActive
    ? [NSString stringWithFormat:@"Sleep timer active, %@ remaining",
       SonoraSleepTimerRemainingString(SonoraSleepTimerManager.sharedManager.remainingTime)]
    : @"Sleep timer";
}

- (void)presentCustomSleepTimerAlert {
    SonoraPresentCustomSleepTimerAlert(self, ^{
        [self updateSleepTimerButton];
    });
}

- (void)sleepTimerTapped {
    UIView *anchor = self.sleepControlButton ?: self.playButton;
    SonoraPresentSleepTimerActionSheet(self, anchor, ^{
        [self updateSleepTimerButton];
    });
}

- (void)handleSleepTimerChanged {
    [self updateSleepTimerButton];
}

- (void)handlePlaybackChanged {
    [self updatePlayButtonState];
    [self.tableView reloadData];
}

- (void)openPlayer {
    UIViewController *player = SonoraInstantiatePlayerViewController();
    if (player == nil || self.navigationController == nil) {
        return;
    }
    player.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:player animated:YES];
}

- (void)playTapped {
    if (self.tracks.count == 0) {
        return;
    }

    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    if ([self isCurrentQueueMatchingAlbum] && playback.currentTrack != nil) {
        [playback togglePlayPause];
        [self updatePlayButtonState];
        [self.tableView reloadData];
        return;
    }

    [self openPlayer];
    dispatch_async(dispatch_get_main_queue(), ^{
        [playback setShuffleEnabled:NO];
        [playback playTracks:self.tracks startIndex:0];
    });
}

- (void)shuffleTapped {
    if (self.tracks.count == 0) {
        return;
    }

    NSInteger randomStart = (NSInteger)arc4random_uniform((u_int32_t)self.tracks.count);
    [self openPlayer];
    dispatch_async(dispatch_get_main_queue(), ^{
        [SonoraPlaybackManager.sharedManager playTracks:self.tracks startIndex:randomStart];
        [SonoraPlaybackManager.sharedManager setShuffleEnabled:YES];
    });
}

- (void)playTracksStartingAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.tracks.count) {
        return;
    }

    [self openPlayer];
    dispatch_async(dispatch_get_main_queue(), ^{
        [SonoraPlaybackManager.sharedManager setShuffleEnabled:NO];
        [SonoraPlaybackManager.sharedManager playTracks:self.tracks startIndex:index];
    });
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return self.tracks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SonoraTrackCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SonoraHomeAlbumTrackCell" forIndexPath:indexPath];
    if (indexPath.row >= self.tracks.count) {
        return cell;
    }

    SonoraTrack *track = self.tracks[indexPath.row];
    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    SonoraTrack *currentTrack = playback.currentTrack;
    BOOL isCurrent = (currentTrack != nil && [currentTrack.identifier isEqualToString:track.identifier]);
    BOOL sameQueue = [self isCurrentQueueMatchingAlbum];
    BOOL showsPlaybackIndicator = (sameQueue && isCurrent && playback.isPlaying);
    [cell configureWithTrack:track isCurrent:isCurrent showsPlaybackIndicator:showsPlaybackIndicator];
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= self.tracks.count) {
        return;
    }

    SonoraTrack *selectedTrack = self.tracks[indexPath.row];
    SonoraTrack *currentTrack = SonoraPlaybackManager.sharedManager.currentTrack;
    BOOL sameTrack = (currentTrack != nil && [currentTrack.identifier isEqualToString:selectedTrack.identifier]);

    if (sameTrack && [self isCurrentQueueMatchingAlbum]) {
        [self openPlayer];
        return;
    }

    [self playTracksStartingAtIndex:indexPath.row];
}

@end

static NSString * const SonoraSettingsGitHubURLString = @"https://github.com/femboypig/Sonora";
static NSString * const SonoraSettingsGitHubDisplayString = @"femboypig/Sonora";

@interface SonoraSettingsViewController : UIViewController <UIColorPickerViewControllerDelegate, UIDocumentPickerDelegate>

@property (nonatomic, strong) UISegmentedControl *fontControl;
@property (nonatomic, strong) UISegmentedControl *artworkStyleControl;
@property (nonatomic, strong) UISegmentedControl *myWaveLookControl;
@property (nonatomic, strong) UISwitch *artworkEqualizerSwitch;
@property (nonatomic, strong) UISwitch *preservePlayerModesSwitch;
@property (nonatomic, strong) UISwitch *onlinePlaylistCacheTracksSwitch;
@property (nonatomic, strong) UILabel *accentColorValueLabel;
@property (nonatomic, strong) UILabel *trackGapValueLabel;
@property (nonatomic, strong) UILabel *usedStorageValueLabel;
@property (nonatomic, strong) UILabel *maxStorageValueLabel;
@property (nonatomic, strong) UILabel *onlinePlaylistCacheUsedValueLabel;
@property (nonatomic, strong) UILabel *onlinePlaylistCacheValueLabel;
@property (nonatomic, strong, nullable) NSURL *pendingBackupExportURL;
@property (nonatomic, strong) SonoraSettingsBackupArchiveService *backupArchiveService;
@property (nonatomic, assign) BOOL backupPickerImportMode;
@property (nonatomic, assign) BOOL backupOperationInProgress;

- (UIView *)selectableValueRowWithTitle:(NSString *)title
                               subtitle:(NSString *)subtitle
                             valueLabel:(UILabel *)valueLabel
                                 action:(SEL)action;
- (UIView *)infoRowWithTitle:(NSString *)title
                       value:(NSString *)value
                  valueLabel:(UILabel * _Nullable)valueLabel;

@end

@implementation SonoraSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.title = @"Settings";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    [self setupInterface];
    [self loadSettingsValues];
    [self refreshStorageUsage];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self loadSettingsValues];
    [self refreshStorageUsage];
}

- (void)setupInterface {
    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.alwaysBounceVertical = YES;
    scrollView.backgroundColor = UIColor.systemBackgroundColor;

    UIStackView *contentStack = [[UIStackView alloc] init];
    contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    contentStack.axis = UILayoutConstraintAxisVertical;
    contentStack.spacing = 10.0;

    [self.view addSubview:scrollView];
    [scrollView addSubview:contentStack];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],

        [contentStack.topAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor constant:8.0],
        [contentStack.leadingAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.leadingAnchor constant:16.0],
        [contentStack.trailingAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.trailingAnchor constant:-16.0],
        [contentStack.bottomAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor constant:-20.0]
    ]];

    [contentStack addArrangedSubview:[self sectionHeadingWithText:@"Customization"]];
    UIStackView *customizationStack = [self addSectionCardToStack:contentStack];

    UISegmentedControl *fontControl = [[UISegmentedControl alloc] initWithItems:@[@"System", @"Serif"]];
    [fontControl addTarget:self action:@selector(fontChanged:) forControlEvents:UIControlEventValueChanged];
    self.fontControl = fontControl;
    [customizationStack addArrangedSubview:[self segmentedRowWithTitle:@"Font"
                                                              subtitle:@"Player title and artist font"
                                                               control:fontControl]];

    UISegmentedControl *artworkStyleControl = [[UISegmentedControl alloc] initWithItems:@[@"Square", @"Rounded"]];
    [artworkStyleControl addTarget:self action:@selector(artworkStyleChanged:) forControlEvents:UIControlEventValueChanged];
    self.artworkStyleControl = artworkStyleControl;
    [customizationStack addArrangedSubview:[self segmentedRowWithTitle:@"Artwork style"
                                                              subtitle:@"Cover corners in player"
                                                               control:artworkStyleControl]];

    UISegmentedControl *myWaveLookControl = [[UISegmentedControl alloc] initWithItems:@[@"Clouds", @"Contours"]];
    [myWaveLookControl addTarget:self action:@selector(myWaveLookChanged:) forControlEvents:UIControlEventValueChanged];
    self.myWaveLookControl = myWaveLookControl;
    [customizationStack addArrangedSubview:[self segmentedRowWithTitle:@"My Wave look"
                                                              subtitle:@"Previous clouds or contour rings on Home"
                                                               control:myWaveLookControl]];

    UILabel *accentColorValue = [self valueLabel];
    self.accentColorValueLabel = accentColorValue;
    [customizationStack addArrangedSubview:[self selectableValueRowWithTitle:@"Accent color"
                                                                     subtitle:@"Any color for active controls"
                                                                   valueLabel:accentColorValue
                                                                       action:@selector(selectAccentColorTapped)]];

    [contentStack addArrangedSubview:[self sectionHeadingWithText:@"Sound"]];
    UIStackView *soundStack = [self addSectionCardToStack:contentStack];

    UISwitch *artworkEqualizerSwitch = [[UISwitch alloc] init];
    [artworkEqualizerSwitch addTarget:self action:@selector(artworkEqualizerChanged:) forControlEvents:UIControlEventValueChanged];
    self.artworkEqualizerSwitch = artworkEqualizerSwitch;
    [soundStack addArrangedSubview:[self switchRowWithTitle:@"Cover equalizer"
                                                   subtitle:@"Show animated badge on artwork while playing"
                                                    control:artworkEqualizerSwitch]];

    UILabel *gapValue = [self valueLabel];
    self.trackGapValueLabel = gapValue;
    [soundStack addArrangedSubview:[self selectableValueRowWithTitle:@"Delay between tracks"
                                                            subtitle:@""
                                                          valueLabel:gapValue
                                                              action:@selector(selectTrackGapTapped)]];

    [contentStack addArrangedSubview:[self sectionHeadingWithText:@"Memory"]];
    UIStackView *memoryStack = [self addSectionCardToStack:contentStack];

    UILabel *usedStorageValue = [self valueLabel];
    self.usedStorageValueLabel = usedStorageValue;
    [memoryStack addArrangedSubview:[self infoRowWithTitle:@"Used by app + songs"
                                                     value:@"0 MB"
                                                valueLabel:usedStorageValue]];

    UILabel *maxStorageValue = [self valueLabel];
    self.maxStorageValueLabel = maxStorageValue;
    [memoryStack addArrangedSubview:[self selectableValueRowWithTitle:@"Max player space"
                                                             subtitle:@""
                                                           valueLabel:maxStorageValue
                                                               action:@selector(selectMaxStorageTapped)]];

    UISwitch *preservePlayerModesSwitch = [[UISwitch alloc] init];
    [preservePlayerModesSwitch addTarget:self action:@selector(preservePlayerModesChanged:) forControlEvents:UIControlEventValueChanged];
    self.preservePlayerModesSwitch = preservePlayerModesSwitch;
    [memoryStack addArrangedSubview:[self switchRowWithTitle:@"Preserve player settings"
                                                    subtitle:@"Keep shuffle/repeat after app restart"
                                                     control:preservePlayerModesSwitch]];

    [contentStack addArrangedSubview:[self sectionHeadingWithText:@"Cache"]];
    UIStackView *cacheStack = [self addSectionCardToStack:contentStack];

    UISwitch *onlinePlaylistCacheTracksSwitch = [[UISwitch alloc] init];
    [onlinePlaylistCacheTracksSwitch addTarget:self action:@selector(cacheOnlinePlaylistTracksChanged:) forControlEvents:UIControlEventValueChanged];
    self.onlinePlaylistCacheTracksSwitch = onlinePlaylistCacheTracksSwitch;
    [cacheStack addArrangedSubview:[self switchRowWithTitle:@"Cache tracks from online playlists"
                                                   subtitle:@"Keep liked shared playlists available offline"
                                                    control:onlinePlaylistCacheTracksSwitch]];

    UILabel *onlinePlaylistCacheUsedValue = [self valueLabel];
    self.onlinePlaylistCacheUsedValueLabel = onlinePlaylistCacheUsedValue;
    [cacheStack addArrangedSubview:[self infoRowWithTitle:@"Used by online playlists"
                                                    value:@"0 MB"
                                               valueLabel:onlinePlaylistCacheUsedValue]];

    UILabel *onlinePlaylistCacheValue = [self valueLabel];
    self.onlinePlaylistCacheValueLabel = onlinePlaylistCacheValue;
    [cacheStack addArrangedSubview:[self selectableValueRowWithTitle:@"Max online cache space"
                                                            subtitle:@""
                                                          valueLabel:onlinePlaylistCacheValue
                                                              action:@selector(selectOnlinePlaylistCacheTapped)]];

    UILabel *clearOnlinePlaylistCacheValue = [self valueLabel];
    clearOnlinePlaylistCacheValue.text = @"Delete";
    [cacheStack addArrangedSubview:[self selectableValueRowWithTitle:@"Clear online cache"
                                                            subtitle:@"Remove downloaded tracks from shared playlists"
                                                          valueLabel:clearOnlinePlaylistCacheValue
                                                              action:@selector(clearOnlinePlaylistCacheTapped)]];

    [contentStack addArrangedSubview:[self sectionHeadingWithText:@"Backup"]];
    UIStackView *backupStack = [self addSectionCardToStack:contentStack];

    UILabel *exportValueLabel = [self valueLabel];
    exportValueLabel.text = @"Create archive";
    [backupStack addArrangedSubview:[self selectableValueRowWithTitle:@"Export backup"
                                                              subtitle:@"Songs, playlists, favorites, settings"
                                                            valueLabel:exportValueLabel
                                                                action:@selector(exportBackupTapped)]];

    UILabel *importValueLabel = [self valueLabel];
    importValueLabel.text = @"Restore archive";
    [backupStack addArrangedSubview:[self selectableValueRowWithTitle:@"Import backup"
                                                              subtitle:@"Replace local data from archive"
                                                            valueLabel:importValueLabel
                                                                action:@selector(importBackupTapped)]];

    [contentStack addArrangedSubview:[self sectionHeadingWithText:@"About"]];
    UIStackView *aboutStack = [self addSectionCardToStack:contentStack];

    UIView *githubRow = [self infoRowWithTitle:@"GitHub project"
                                         value:SonoraSettingsGitHubDisplayString
                                    valueLabel:nil];
    githubRow.userInteractionEnabled = YES;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openGitHubTapped)];
    [githubRow addGestureRecognizer:tap];
    [aboutStack addArrangedSubview:githubRow];

    [aboutStack addArrangedSubview:[self infoRowWithTitle:@"Developers"
                                                    value:@"hippopotamus"
                                               valueLabel:nil]];
    [aboutStack addArrangedSubview:[self infoRowWithTitle:@"Version"
                                                    value:[self appVersionLabel]
                                               valueLabel:nil]];
    [aboutStack addArrangedSubview:[self infoRowWithTitle:@"Storage path"
                                                    value:[self abbreviatedStoragePathDisplayValue]
                                               valueLabel:nil]];
}

- (UILabel *)sectionHeadingWithText:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.font = SonoraYSMusicFont(24.0);
    label.textColor = UIColor.labelColor;
    label.text = text;
    return label;
}

- (UIStackView *)addSectionCardToStack:(UIStackView *)parent {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    container.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
        if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return [UIColor colorWithWhite:1.0 alpha:0.06];
        }
        return [UIColor colorWithWhite:0.0 alpha:0.03];
    }];
    container.layer.cornerRadius = 16.0;
    container.layer.borderWidth = 1.0;
    container.layer.borderColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
        if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return [UIColor colorWithWhite:1.0 alpha:0.12];
        }
        return [UIColor colorWithWhite:0.0 alpha:0.09];
    }].CGColor;
    [parent addArrangedSubview:container];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12.0;
    [container addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:container.topAnchor constant:12.0],
        [stack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:14.0],
        [stack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-14.0],
        [stack.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-12.0]
    ]];
    return stack;
}

- (UILabel *)valueLabel {
    UILabel *label = [[UILabel alloc] init];
    label.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    label.textColor = UIColor.labelColor;
    label.textAlignment = NSTextAlignmentRight;
    label.numberOfLines = 1;
    return label;
}

- (UIView *)switchRowWithTitle:(NSString *)title
                      subtitle:(NSString *)subtitle
                       control:(UISwitch *)control {
    UIView *row = [[UIView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    titleLabel.textColor = UIColor.labelColor;
    titleLabel.text = title;
    titleLabel.numberOfLines = 1;

    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular];
    subtitleLabel.textColor = UIColor.secondaryLabelColor;
    subtitleLabel.text = subtitle;
    subtitleLabel.numberOfLines = 2;

    UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, subtitleLabel]];
    textStack.translatesAutoresizingMaskIntoConstraints = NO;
    textStack.axis = UILayoutConstraintAxisVertical;
    textStack.spacing = 2.0;

    control.translatesAutoresizingMaskIntoConstraints = NO;

    [row addSubview:textStack];
    [row addSubview:control];

    [NSLayoutConstraint activateConstraints:@[
        [textStack.topAnchor constraintEqualToAnchor:row.topAnchor],
        [textStack.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [textStack.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
        [textStack.trailingAnchor constraintLessThanOrEqualToAnchor:control.leadingAnchor constant:-10.0],

        [control.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [control.centerYAnchor constraintEqualToAnchor:row.centerYAnchor]
    ]];
    return row;
}

- (UIView *)segmentedRowWithTitle:(NSString *)title
                         subtitle:(NSString *)subtitle
                          control:(UISegmentedControl *)control {
    UIView *row = [[UIView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    titleLabel.textColor = UIColor.labelColor;
    titleLabel.text = title;

    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular];
    subtitleLabel.textColor = UIColor.secondaryLabelColor;
    subtitleLabel.text = subtitle;
    subtitleLabel.numberOfLines = 2;

    control.translatesAutoresizingMaskIntoConstraints = NO;

    [row addSubview:titleLabel];
    [row addSubview:subtitleLabel];
    [row addSubview:control];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:row.topAnchor],
        [titleLabel.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [titleLabel.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],

        [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:2.0],
        [subtitleLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [subtitleLabel.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],

        [control.topAnchor constraintEqualToAnchor:subtitleLabel.bottomAnchor constant:8.0],
        [control.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [control.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [control.bottomAnchor constraintEqualToAnchor:row.bottomAnchor]
    ]];
    return row;
}

- (UIView *)selectableValueRowWithTitle:(NSString *)title
                               subtitle:(NSString *)subtitle
                             valueLabel:(UILabel *)valueLabel
                                 action:(SEL)action {
    UIControl *row = [[UIControl alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    [row addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    titleLabel.textColor = UIColor.labelColor;
    titleLabel.text = title;
    titleLabel.numberOfLines = 1;

    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular];
    subtitleLabel.textColor = UIColor.secondaryLabelColor;
    subtitleLabel.text = subtitle;
    subtitleLabel.numberOfLines = 2;
    subtitleLabel.hidden = (subtitle.length == 0);

    UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:(subtitleLabel.hidden ? @[titleLabel] : @[titleLabel, subtitleLabel])];
    textStack.translatesAutoresizingMaskIntoConstraints = NO;
    textStack.axis = UILayoutConstraintAxisVertical;
    textStack.spacing = 2.0;
    textStack.alignment = UIStackViewAlignmentFill;

    valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    valueLabel.textAlignment = NSTextAlignmentRight;
    [valueLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [valueLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
    chevron.translatesAutoresizingMaskIntoConstraints = NO;
    chevron.contentMode = UIViewContentModeScaleAspectFit;
    chevron.tintColor = UIColor.tertiaryLabelColor;

    [row addSubview:textStack];
    [row addSubview:valueLabel];
    [row addSubview:chevron];

    [NSLayoutConstraint activateConstraints:@[
        [textStack.topAnchor constraintEqualToAnchor:row.topAnchor],
        [textStack.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [textStack.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],

        [chevron.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [chevron.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [chevron.widthAnchor constraintEqualToConstant:11.0],
        [chevron.heightAnchor constraintEqualToConstant:15.0],

        [valueLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:textStack.trailingAnchor constant:10.0],
        [valueLabel.trailingAnchor constraintEqualToAnchor:chevron.leadingAnchor constant:-8.0],
        [valueLabel.centerYAnchor constraintEqualToAnchor:row.centerYAnchor]
    ]];
    return row;
}

- (UIView *)infoRowWithTitle:(NSString *)title
                       value:(NSString *)value
                  valueLabel:(UILabel * _Nullable)valueLabel {
    UIView *row = [[UIView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    titleLabel.textColor = UIColor.labelColor;
    titleLabel.text = title;
    titleLabel.numberOfLines = 1;

    UILabel *resolvedValueLabel = valueLabel ?: [self valueLabel];
    resolvedValueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    resolvedValueLabel.text = value;
    resolvedValueLabel.textAlignment = NSTextAlignmentRight;
    resolvedValueLabel.numberOfLines = 1;
    [resolvedValueLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [resolvedValueLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    [row addSubview:titleLabel];
    [row addSubview:resolvedValueLabel];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:row.topAnchor],
        [titleLabel.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [titleLabel.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],

        [resolvedValueLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:titleLabel.trailingAnchor constant:12.0],
        [resolvedValueLabel.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [resolvedValueLabel.centerYAnchor constraintEqualToAnchor:row.centerYAnchor]
    ]];
    return row;
}

- (void)loadSettingsValues {
    NSInteger font = SonoraSettingsFontStyleIndex();
    NSInteger artworkStyle = SonoraSettingsArtworkStyleIndex();
    NSInteger myWaveLook = SonoraSettingsMyWaveLook();
    BOOL artworkEqualizerEnabled = SonoraSettingsArtworkEqualizerEnabled();
    BOOL preserveModes = SonoraSettingsPreservePlayerModesEnabled();
    double trackGap = SonoraSettingsTrackGapSeconds();
    NSInteger maxStorageMB = SonoraSettingsMaxStorageMB();
    BOOL cacheOnlinePlaylistTracks = SonoraSettingsCacheOnlinePlaylistTracksEnabled();
    NSInteger onlinePlaylistCacheMaxMB = SonoraSettingsOnlinePlaylistCacheMaxMB();

    if (font > 1) {
        font = 0;
        SonoraSettingsSetFontStyleIndex(font);
    }
    if (myWaveLook != SonoraMyWaveLookClouds && myWaveLook != SonoraMyWaveLookContours) {
        myWaveLook = SonoraMyWaveLookContours;
        SonoraSettingsSetMyWaveLook(myWaveLook);
    }
    self.fontControl.selectedSegmentIndex = MAX(0, MIN(1, font));
    self.artworkStyleControl.selectedSegmentIndex = MAX(0, MIN(1, artworkStyle));
    self.myWaveLookControl.selectedSegmentIndex = myWaveLook;
    self.artworkEqualizerSwitch.on = artworkEqualizerEnabled;
    self.preservePlayerModesSwitch.on = preserveModes;
    self.onlinePlaylistCacheTracksSwitch.on = cacheOnlinePlaylistTracks;

    double snappedGap = [self nearestTrackGapValueForValue:trackGap];
    NSInteger snappedMaxStorage = [self nearestMaxStorageValueForValue:maxStorageMB];
    NSInteger snappedOnlinePlaylistCache = [self nearestMaxStorageValueForValue:onlinePlaylistCacheMaxMB];
    SonoraSettingsSetTrackGapSeconds(snappedGap);
    SonoraSettingsSetMaxStorageMB(snappedMaxStorage);
    SonoraSettingsSetOnlinePlaylistCacheMaxMB(snappedOnlinePlaylistCache);
    [self refreshTrackGapLabel];
    [self refreshMaxStorageLabel];
    [self refreshOnlinePlaylistCacheUsageLabel];
    [self refreshOnlinePlaylistCacheLabel];
    [self refreshAccentColorLabel];
}

- (void)fontChanged:(UISegmentedControl *)sender {
    SonoraSettingsSetFontStyleIndex(sender.selectedSegmentIndex);
    [self notifyPlayerSettingsChanged];
}

- (void)artworkStyleChanged:(UISegmentedControl *)sender {
    SonoraSettingsSetArtworkStyleIndex(sender.selectedSegmentIndex);
    [self notifyPlayerSettingsChanged];
}

- (void)myWaveLookChanged:(UISegmentedControl *)sender {
    NSInteger look = MAX((NSInteger)SonoraMyWaveLookClouds, MIN((NSInteger)SonoraMyWaveLookContours, sender.selectedSegmentIndex));
    SonoraSettingsSetMyWaveLook(look);
    [self notifyPlayerSettingsChanged];
}

- (void)preservePlayerModesChanged:(UISwitch *)sender {
    SonoraSettingsSetPreservePlayerModesEnabled(sender.isOn);
}

- (void)cacheOnlinePlaylistTracksChanged:(UISwitch *)sender {
    SonoraSettingsSetCacheOnlinePlaylistTracksEnabled(sender.isOn);
    [self trimSharedPlaylistAudioCacheToLimitBytes:(sender.isOn ? [self onlinePlaylistCacheLimitBytes] : 0)];
    [self refreshOnlinePlaylistCacheUsageLabel];
    if (sender.isOn) {
        [self refreshSharedPlaylistAudioCacheIfNeeded];
    }
    [self notifyPlayerSettingsChanged];
    [NSNotificationCenter.defaultCenter postNotificationName:SonoraPlaylistsDidChangeNotification object:nil];
}

- (UIColor *)currentAccentColor {
    return SonoraHomeAccentYellowColor();
}

- (NSString *)hexStringForColor:(UIColor *)color {
    if (color == nil) {
        return @"#FFD414";
    }

    CGFloat red = 0.0;
    CGFloat green = 0.0;
    CGFloat blue = 0.0;
    CGFloat alpha = 0.0;
    if (![color getRed:&red green:&green blue:&blue alpha:&alpha]) {
        CGFloat white = 0.0;
        if ([color getWhite:&white alpha:&alpha]) {
            red = white;
            green = white;
            blue = white;
        } else {
            return @"#FFD414";
        }
    }

    NSInteger r = (NSInteger)lround(MAX(0.0, MIN(1.0, red)) * 255.0);
    NSInteger g = (NSInteger)lround(MAX(0.0, MIN(1.0, green)) * 255.0);
    NSInteger b = (NSInteger)lround(MAX(0.0, MIN(1.0, blue)) * 255.0);
    return [NSString stringWithFormat:@"#%02lX%02lX%02lX", (long)r, (long)g, (long)b];
}

- (void)storeAccentColor:(UIColor *)color {
    NSString *hex = [self hexStringForColor:color];
    SonoraSettingsStoreAccentHex(hex);
}

- (void)refreshAccentColorLabel {
    self.accentColorValueLabel.text = [self hexStringForColor:[self currentAccentColor]];
}

- (void)selectAccentColorTapped {
    if (@available(iOS 14.0, *)) {
        UIColorPickerViewController *picker = [[UIColorPickerViewController alloc] init];
        picker.selectedColor = [self currentAccentColor];
        picker.supportsAlpha = NO;
        picker.delegate = self;
        [self presentViewController:picker animated:YES completion:nil];
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Unavailable"
                                                                   message:@"Color picker requires iOS 14 or newer."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)colorPickerViewController:(UIColorPickerViewController *)viewController
                   didSelectColor:(UIColor *)color
                     continuously:(BOOL)continuously API_AVAILABLE(ios(15.0)) {
    (void)viewController;
    (void)continuously;
    [self storeAccentColor:color];
    [self refreshAccentColorLabel];
    [self notifyPlayerSettingsChanged];
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController API_AVAILABLE(ios(14.0)) {
    [self storeAccentColor:viewController.selectedColor];
    [self refreshAccentColorLabel];
    [self notifyPlayerSettingsChanged];
}

- (void)artworkEqualizerChanged:(UISwitch *)sender {
    SonoraSettingsSetArtworkEqualizerEnabled(sender.isOn);
    [self notifyPlayerSettingsChanged];
}

- (void)selectTrackGapTapped {
    double current = [self nearestTrackGapValueForValue:SonoraSettingsTrackGapSeconds()];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Delay between tracks"
                                                                   message:[NSString stringWithFormat:@"Current: %@", [self trackGapLabelForSeconds:current]]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSNumber *value in [self trackGapOptionValues]) {
        double seconds = value.doubleValue;
        NSString *title = [self trackGapLabelForSeconds:seconds];
        [sheet addAction:[UIAlertAction actionWithTitle:title
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction * _Nonnull action) {
            SonoraSettingsSetTrackGapSeconds(seconds);
            [self refreshTrackGapLabel];
            [self notifyPlayerSettingsChanged];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self configurePopoverForSheet:sheet];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)selectMaxStorageTapped {
    NSInteger current = [self nearestMaxStorageValueForValue:SonoraSettingsMaxStorageMB()];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Max player space"
                                                                   message:[NSString stringWithFormat:@"Current: %@", [self storageLabelForMB:current]]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSNumber *value in [self maxStorageOptionValues]) {
        NSInteger sizeMB = value.integerValue;
        NSString *title = [self storageLabelForMB:sizeMB];
        [sheet addAction:[UIAlertAction actionWithTitle:title
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction * _Nonnull action) {
            SonoraSettingsSetMaxStorageMB(sizeMB);
            [self refreshMaxStorageLabel];
            [self refreshStorageUsage];
            [self presentStorageLimitExceededAlertIfNeeded];
            [self notifyPlayerSettingsChanged];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self configurePopoverForSheet:sheet];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)selectOnlinePlaylistCacheTapped {
    NSInteger current = [self nearestMaxStorageValueForValue:SonoraSettingsOnlinePlaylistCacheMaxMB()];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Max online cache space"
                                                                   message:[NSString stringWithFormat:@"Current: %@", [self storageLabelForMB:current]]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSNumber *value in [self maxStorageOptionValues]) {
        NSInteger sizeMB = value.integerValue;
        NSString *title = [self storageLabelForMB:sizeMB];
        [sheet addAction:[UIAlertAction actionWithTitle:title
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction * _Nonnull action) {
            SonoraSettingsSetOnlinePlaylistCacheMaxMB(sizeMB);
            [self refreshOnlinePlaylistCacheLabel];
            if (self.onlinePlaylistCacheTracksSwitch.isOn) {
                [self trimSharedPlaylistAudioCacheToLimitBytes:[self onlinePlaylistCacheLimitBytes]];
                [self refreshOnlinePlaylistCacheUsageLabel];
                [self refreshSharedPlaylistAudioCacheIfNeeded];
                [NSNotificationCenter.defaultCenter postNotificationName:SonoraPlaylistsDidChangeNotification object:nil];
            }
            [self notifyPlayerSettingsChanged];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self configurePopoverForSheet:sheet];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)clearOnlinePlaylistCacheTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Clear online cache"
                                                                   message:@"Delete downloaded tracks from shared playlists on this device?"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(__unused UIAlertAction * _Nonnull action) {
        [self trimSharedPlaylistAudioCacheToLimitBytes:0];
        [self refreshOnlinePlaylistCacheUsageLabel];
        [self notifyPlayerSettingsChanged];
        [NSNotificationCenter.defaultCenter postNotificationName:SonoraPlaylistsDidChangeNotification object:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self configurePopoverForSheet:alert];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)configurePopoverForSheet:(UIAlertController *)sheet {
    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover == nil) {
        return;
    }
    popover.sourceView = self.view;
    popover.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1.0, 1.0);
    popover.permittedArrowDirections = UIPopoverArrowDirectionUnknown;
}

- (NSArray<NSNumber *> *)trackGapOptionValues {
    return @[@0.0, @0.5, @1.0, @1.5, @2.0, @3.0, @5.0, @8.0];
}

- (NSArray<NSNumber *> *)maxStorageOptionValues {
    return @[@0, @512, @1024, @2048, @3072, @4096, @6144, @8192];
}

- (double)nearestTrackGapValueForValue:(double)value {
    double nearest = 0.0;
    double nearestDelta = DBL_MAX;
    for (NSNumber *candidate in [self trackGapOptionValues]) {
        double current = candidate.doubleValue;
        double delta = fabs(current - value);
        if (delta < nearestDelta) {
            nearestDelta = delta;
            nearest = current;
        }
    }
    return nearest;
}

- (NSInteger)nearestMaxStorageValueForValue:(NSInteger)value {
    if (value <= 0) {
        return 0;
    }
    NSInteger nearest = 2048;
    NSInteger nearestDelta = NSIntegerMax;
    for (NSNumber *candidate in [self maxStorageOptionValues]) {
        NSInteger current = candidate.integerValue;
        if (current <= 0) {
            continue;
        }
        NSInteger delta = labs(current - value);
        if (delta < nearestDelta) {
            nearestDelta = delta;
            nearest = current;
        }
    }
    return nearest;
}

- (NSString *)trackGapLabelForSeconds:(double)seconds {
    if (seconds <= 0.01) {
        return @"Off";
    }
    double rounded = round(seconds * 10.0) / 10.0;
    if (fabs(rounded - round(rounded)) < 0.05) {
        return [NSString stringWithFormat:@"%ld s", (long)lround(rounded)];
    }
    return [NSString stringWithFormat:@"%.1f s", rounded];
}

- (NSString *)storageLabelForMB:(NSInteger)sizeMB {
    if (sizeMB <= 0) {
        return @"Unlimited";
    }
    double gigabytes = ((double)sizeMB) / 1024.0;
    double rounded = round(gigabytes * 10.0) / 10.0;
    if (rounded >= 1.0) {
        if (fabs(rounded - round(rounded)) < 0.05) {
            return [NSString stringWithFormat:@"%ld GB", (long)lround(rounded)];
        }
        return [NSString stringWithFormat:@"%.1f GB", rounded];
    }
    return [NSString stringWithFormat:@"%ld MB", (long)sizeMB];
}

- (void)refreshTrackGapLabel {
    double value = SonoraSettingsTrackGapSeconds();
    self.trackGapValueLabel.text = [self trackGapLabelForSeconds:[self nearestTrackGapValueForValue:value]];
}

- (void)refreshMaxStorageLabel {
    NSInteger value = SonoraSettingsMaxStorageMB();
    self.maxStorageValueLabel.text = [self storageLabelForMB:[self nearestMaxStorageValueForValue:value]];
}

- (void)refreshOnlinePlaylistCacheLabel {
    NSInteger value = SonoraSettingsOnlinePlaylistCacheMaxMB();
    self.onlinePlaylistCacheValueLabel.text = [self storageLabelForMB:[self nearestMaxStorageValueForValue:value]];
}

- (void)refreshSharedPlaylistAudioCacheIfNeeded {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [SonoraSharedPlaylistStore.sharedStore refreshAllPersistentCachesIfNeeded];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self refreshOnlinePlaylistCacheUsageLabel];
        });
    });
}

- (unsigned long long)currentOnlinePlaylistCacheUsageBytes {
    NSString *directory = [self sharedPlaylistAudioCacheDirectoryPath];
    NSDirectoryEnumerator<NSURL *> *enumerator =
        [NSFileManager.defaultManager enumeratorAtURL:[NSURL fileURLWithPath:directory]
                           includingPropertiesForKeys:@[NSURLIsRegularFileKey, NSURLFileSizeKey]
                                              options:NSDirectoryEnumerationSkipsHiddenFiles
                                         errorHandler:nil];
    unsigned long long totalBytes = 0;
    for (NSURL *fileURL in enumerator) {
        NSNumber *isRegularFile = nil;
        [fileURL getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:nil];
        if (![isRegularFile boolValue]) {
            continue;
        }
        NSNumber *fileSize = nil;
        [fileURL getResourceValue:&fileSize forKey:NSURLFileSizeKey error:nil];
        totalBytes += MAX(fileSize.unsignedLongLongValue, 0);
    }
    return totalBytes;
}

- (void)refreshOnlinePlaylistCacheUsageLabel {
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        unsigned long long usedBytes = [strongSelf currentOnlinePlaylistCacheUsageBytes];
        unsigned long long maxBytes = [strongSelf onlinePlaylistCacheLimitBytes];
        BOOL cacheEnabled = strongSelf.onlinePlaylistCacheTracksSwitch.isOn;
        NSString *usedText = [NSByteCountFormatter stringFromByteCount:(long long)usedBytes
                                                            countStyle:NSByteCountFormatterCountStyleFile];
        BOOL overLimit = (cacheEnabled && maxBytes != ULLONG_MAX && usedBytes > maxBytes);
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) innerSelf = weakSelf;
            if (innerSelf == nil) {
                return;
            }
            innerSelf.onlinePlaylistCacheUsedValueLabel.text = usedText;
            innerSelf.onlinePlaylistCacheUsedValueLabel.textColor = overLimit ? UIColor.systemRedColor : UIColor.labelColor;
        });
    });
}

- (void)refreshStorageUsage {
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        unsigned long long usedBytes = [strongSelf currentLibraryUsageBytes];
        unsigned long long maxBytes = [strongSelf maxStorageLimitBytes];
        NSString *usedText = [NSByteCountFormatter stringFromByteCount:(long long)usedBytes
                                                            countStyle:NSByteCountFormatterCountStyleFile];
        BOOL overLimit = (maxBytes != ULLONG_MAX && usedBytes > maxBytes);
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) innerSelf = weakSelf;
            if (innerSelf == nil) {
                return;
            }
            innerSelf.usedStorageValueLabel.text = usedText;
            innerSelf.usedStorageValueLabel.textColor = overLimit ? UIColor.systemRedColor : UIColor.labelColor;
        });
    });
}

- (unsigned long long)maxStorageLimitBytes {
    NSInteger maxMB = [self nearestMaxStorageValueForValue:SonoraSettingsMaxStorageMB()];
    if (maxMB <= 0) {
        return ULLONG_MAX;
    }
    return ((unsigned long long)maxMB) * 1024ULL * 1024ULL;
}

- (NSString *)sharedPlaylistAudioCacheDirectoryPath {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *base = paths.firstObject ?: NSTemporaryDirectory();
    NSString *directory = [[base stringByAppendingPathComponent:@"SonoraSharedPlaylists"] stringByAppendingPathComponent:@"audio"];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    return directory;
}

- (unsigned long long)onlinePlaylistCacheLimitBytes {
    NSInteger maxMB = [self nearestMaxStorageValueForValue:SonoraSettingsOnlinePlaylistCacheMaxMB()];
    if (maxMB <= 0) {
        return ULLONG_MAX;
    }
    return ((unsigned long long)maxMB) * 1024ULL * 1024ULL;
}

- (void)trimSharedPlaylistAudioCacheToLimitBytes:(unsigned long long)limitBytes {
    NSString *directory = [self sharedPlaylistAudioCacheDirectoryPath];
    NSArray<NSURL *> *files = [NSFileManager.defaultManager contentsOfDirectoryAtURL:[NSURL fileURLWithPath:directory]
                                                          includingPropertiesForKeys:@[NSURLIsRegularFileKey, NSURLContentModificationDateKey, NSURLFileSizeKey]
                                                                             options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                               error:nil];
    NSMutableArray<NSDictionary<NSString *, id> *> *entries = [NSMutableArray array];
    unsigned long long totalBytes = 0;
    for (NSURL *fileURL in files) {
        NSNumber *isRegularFile = nil;
        [fileURL getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:nil];
        if (![isRegularFile boolValue]) {
            continue;
        }
        NSNumber *fileSize = nil;
        NSDate *modifiedAt = nil;
        [fileURL getResourceValue:&fileSize forKey:NSURLFileSizeKey error:nil];
        [fileURL getResourceValue:&modifiedAt forKey:NSURLContentModificationDateKey error:nil];
        unsigned long long currentSize = MAX(fileSize.unsignedLongLongValue, 0);
        totalBytes += currentSize;
        [entries addObject:@{
            @"url": fileURL,
            @"modifiedAt": modifiedAt ?: NSDate.distantPast,
            @"size": @(currentSize)
        }];
    }
    [entries sortUsingComparator:^NSComparisonResult(NSDictionary<NSString *,id> * _Nonnull lhs, NSDictionary<NSString *,id> * _Nonnull rhs) {
        return [lhs[@"modifiedAt"] compare:rhs[@"modifiedAt"]];
    }];
    for (NSDictionary<NSString *, id> *entry in entries) {
        if (limitBytes == ULLONG_MAX || totalBytes <= limitBytes) {
            break;
        }
        NSURL *fileURL = entry[@"url"];
        unsigned long long fileSize = [entry[@"size"] unsignedLongLongValue];
        [NSFileManager.defaultManager removeItemAtURL:fileURL error:nil];
        totalBytes = (totalBytes > fileSize) ? (totalBytes - fileSize) : 0;
    }
}

- (void)presentStorageLimitExceededAlertIfNeeded {
    unsigned long long usedBytes = [self currentLibraryUsageBytes];
    unsigned long long maxBytes = [self maxStorageLimitBytes];
    if (maxBytes == ULLONG_MAX) {
        return;
    }
    if (usedBytes <= maxBytes) {
        return;
    }

    NSString *usedText = [NSByteCountFormatter stringFromByteCount:(long long)usedBytes
                                                        countStyle:NSByteCountFormatterCountStyleFile];
    NSString *maxText = [NSByteCountFormatter stringFromByteCount:(long long)maxBytes
                                                       countStyle:NSByteCountFormatterCountStyleFile];
    NSString *message = [NSString stringWithFormat:@"Library size %@ is over max %@.\nNew music additions are blocked until you free space or increase Max player space.",
                         usedText,
                         maxText];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Storage limit exceeded"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.presentedViewController == nil) {
            [self presentViewController:alert animated:YES completion:nil];
        }
    });
}

- (unsigned long long)currentLibraryUsageBytes {
    NSURL *musicDirectoryURL = [SonoraLibraryManager.sharedManager musicDirectoryURL];
    if (musicDirectoryURL == nil) {
        return 0ULL;
    }
    return [self directorySizeAtURL:musicDirectoryURL];
}

- (unsigned long long)directorySizeAtURL:(NSURL *)url {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSDirectoryEnumerator<NSURL *> *enumerator =
    [fileManager enumeratorAtURL:url
      includingPropertiesForKeys:@[NSURLIsRegularFileKey, NSURLFileSizeKey]
                         options:NSDirectoryEnumerationSkipsHiddenFiles
                    errorHandler:nil];
    unsigned long long totalBytes = 0ULL;
    for (NSURL *fileURL in enumerator) {
        NSNumber *isRegularFile = nil;
        [fileURL getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:nil];
        if (!isRegularFile.boolValue) {
            continue;
        }

        NSNumber *fileSize = nil;
        [fileURL getResourceValue:&fileSize forKey:NSURLFileSizeKey error:nil];
        totalBytes += fileSize.unsignedLongLongValue;
    }
    return totalBytes;
}

- (NSString *)appVersionLabel {
    NSDictionary *info = NSBundle.mainBundle.infoDictionary ?: @{};
    NSString *shortVersion = info[@"CFBundleShortVersionString"];
    NSString *buildVersion = info[(NSString *)kCFBundleVersionKey];
    if (shortVersion.length > 0 && buildVersion.length > 0 && ![shortVersion isEqualToString:buildVersion]) {
        return [NSString stringWithFormat:@"%@ (%@)", shortVersion, buildVersion];
    }
    if (shortVersion.length > 0) {
        return shortVersion;
    }
    if (buildVersion.length > 0) {
        return buildVersion;
    }
    return @"1.0";
}

- (NSString *)abbreviatedStoragePathDisplayValue {
    NSString *fullPath = SonoraLibraryManager.sharedManager.filesDropHint ?: @"";
    if (fullPath.length == 0) {
        return @"-";
    }

    NSString *trimmed = [fullPath stringByReplacingOccurrencesOfString:@"Files -> " withString:@""];
    trimmed = [trimmed stringByReplacingOccurrencesOfString:@" -> " withString:@"/"];
    trimmed = [trimmed stringByReplacingOccurrencesOfString:@"/files" withString:@""];
    NSString *abbreviated = [trimmed stringByAbbreviatingWithTildeInPath];
    if (abbreviated.length <= 38) {
        return abbreviated;
    }

    NSArray<NSString *> *parts = [abbreviated componentsSeparatedByString:@"/"];
    NSMutableArray<NSString *> *nonEmptyParts = [NSMutableArray array];
    for (NSString *part in parts) {
        if (part.length > 0) {
            [nonEmptyParts addObject:part];
        }
    }
    if (nonEmptyParts.count >= 2) {
        NSString *tail = [NSString stringWithFormat:@"%@/%@",
                          nonEmptyParts[nonEmptyParts.count - 2],
                          nonEmptyParts.lastObject];
        return [NSString stringWithFormat:@".../%@", tail];
    }

    NSUInteger keep = MIN((NSUInteger)38, abbreviated.length);
    return [abbreviated substringFromIndex:abbreviated.length - keep];
}

- (void)openGitHubTapped {
    NSURL *url = [NSURL URLWithString:SonoraSettingsGitHubURLString];
    if (url == nil) {
        return;
    }
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}

- (SonoraSettingsBackupArchiveService *)backupArchiveService {
    if (_backupArchiveService == nil) {
        _backupArchiveService = [[SonoraSettingsBackupArchiveService alloc] init];
    }
    return _backupArchiveService;
}

- (NSDictionary<NSString *, id> *)backupManifestSettingsSnapshot {
    return @{
        @"fontStyle": (SonoraSettingsFontStyleIndex() == 1 ? @"serif" : @"system"),
        @"artworkStyle": (SonoraSettingsArtworkStyleIndex() == 0 ? @"square" : @"rounded"),
        @"accentHex": [self hexStringForColor:[self currentAccentColor]],
        @"preservePlayerModes": @(SonoraSettingsPreservePlayerModesEnabled()),
        @"trackGapSeconds": @(SonoraSettingsTrackGapSeconds()),
        @"maxStorageMb": @(SonoraSettingsMaxStorageMB()),
        @"cacheOnlinePlaylistTracks": @(SonoraSettingsCacheOnlinePlaylistTracksEnabled()),
        @"onlinePlaylistCacheMaxMb": @(SonoraSettingsOnlinePlaylistCacheMaxMB()),
        @"artworkEqualizer": @(SonoraSettingsArtworkEqualizerEnabled())
    };
}

- (void)applyImportedBackupSettings:(NSDictionary<NSString *, id> *)settings {
    if (![settings isKindOfClass:NSDictionary.class] || settings.count == 0) {
        return;
    }

    id fontValue = settings[@"fontStyle"];
    NSInteger fontIndex = 0;
    if ([fontValue isKindOfClass:NSString.class]) {
        fontIndex = [((NSString *)fontValue).lowercaseString isEqualToString:@"serif"] ? 1 : 0;
    } else if ([fontValue respondsToSelector:@selector(integerValue)]) {
        fontIndex = [fontValue integerValue];
    }
    SonoraSettingsSetFontStyleIndex(MAX(0, MIN(1, fontIndex)));

    id artworkStyleValue = settings[@"artworkStyle"];
    NSInteger artworkIndex = 1;
    if ([artworkStyleValue isKindOfClass:NSString.class]) {
        artworkIndex = [((NSString *)artworkStyleValue).lowercaseString isEqualToString:@"square"] ? 0 : 1;
    } else if ([artworkStyleValue respondsToSelector:@selector(integerValue)]) {
        artworkIndex = [artworkStyleValue integerValue];
    }
    SonoraSettingsSetArtworkStyleIndex(MAX(0, MIN(1, artworkIndex)));

    id accentValue = settings[@"accentHex"];
    if ([accentValue isKindOfClass:NSString.class] && ((NSString *)accentValue).length > 0) {
        SonoraSettingsStoreAccentHex((NSString *)accentValue);
    }

    id preserveValue = settings[@"preservePlayerModes"];
    if ([preserveValue respondsToSelector:@selector(boolValue)]) {
        SonoraSettingsSetPreservePlayerModesEnabled([preserveValue boolValue]);
    }

    id gapValue = settings[@"trackGapSeconds"];
    if ([gapValue respondsToSelector:@selector(doubleValue)]) {
        SonoraSettingsSetTrackGapSeconds([self nearestTrackGapValueForValue:[gapValue doubleValue]]);
    }

    id maxStorageValue = settings[@"maxStorageMb"];
    if (maxStorageValue == nil) {
        maxStorageValue = settings[@"maxStorageMB"];
    }
    if ([maxStorageValue respondsToSelector:@selector(integerValue)]) {
        SonoraSettingsSetMaxStorageMB([self nearestMaxStorageValueForValue:[maxStorageValue integerValue]]);
    }

    id cacheOnlinePlaylistTracksValue = settings[@"cacheOnlinePlaylistTracks"];
    if ([cacheOnlinePlaylistTracksValue respondsToSelector:@selector(boolValue)]) {
        SonoraSettingsSetCacheOnlinePlaylistTracksEnabled([cacheOnlinePlaylistTracksValue boolValue]);
    }

    id onlinePlaylistCacheMaxValue = settings[@"onlinePlaylistCacheMaxMb"];
    if (onlinePlaylistCacheMaxValue == nil) {
        onlinePlaylistCacheMaxValue = settings[@"onlinePlaylistCacheMaxMB"];
    }
    if ([onlinePlaylistCacheMaxValue respondsToSelector:@selector(integerValue)]) {
        SonoraSettingsSetOnlinePlaylistCacheMaxMB([self nearestMaxStorageValueForValue:[onlinePlaylistCacheMaxValue integerValue]]);
    }

    id artworkEqualizerValue = settings[@"artworkEqualizer"];
    if ([artworkEqualizerValue respondsToSelector:@selector(boolValue)]) {
        SonoraSettingsSetArtworkEqualizerEnabled([artworkEqualizerValue boolValue]);
    }
}

- (void)exportBackupTapped {
    if (self.backupOperationInProgress) {
        return;
    }
    self.backupOperationInProgress = YES;
    UIAlertController *progress = [UIAlertController alertControllerWithTitle:@"Backup"
                                                                      message:@"Preparing archive..."
                                                               preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:progress animated:YES completion:nil];

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        NSError *archiveError = nil;
        NSDictionary<NSString *, id> *settingsSnapshot = [strongSelf backupManifestSettingsSnapshot];
        NSData *archiveData = [strongSelf.backupArchiveService backupArchiveDataWithSettings:settingsSnapshot error:&archiveError];
        NSURL *temporaryURL = nil;
        if (archiveData.length > 0) {
            NSString *fileName = [strongSelf.backupArchiveService backupArchiveFileName];
            NSString *temporaryPath = [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];
            temporaryURL = [NSURL fileURLWithPath:temporaryPath];
            NSError *writeError = nil;
            [archiveData writeToURL:temporaryURL options:NSDataWritingAtomic error:&writeError];
            if (writeError != nil) {
                archiveError = writeError;
                temporaryURL = nil;
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) innerSelf = weakSelf;
            if (innerSelf == nil) {
                return;
            }

            innerSelf.backupOperationInProgress = NO;
            [progress dismissViewControllerAnimated:YES completion:^{
                if (temporaryURL == nil) {
                    [innerSelf presentBackupErrorMessage:(archiveError.localizedDescription ?: @"Could not create backup archive.")];
                    return;
                }

                UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[temporaryURL] asCopy:YES];
                picker.delegate = innerSelf;
                picker.modalPresentationStyle = UIModalPresentationFormSheet;
                innerSelf.pendingBackupExportURL = temporaryURL;
                innerSelf.backupPickerImportMode = NO;
                [innerSelf presentViewController:picker animated:YES completion:nil];
            }];
        });
    });
}

- (void)importBackupTapped {
    if (self.backupOperationInProgress) {
        return;
    }
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData]
                                                                                                          asCopy:YES];
    picker.delegate = self;
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    self.backupPickerImportMode = YES;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    NSURL *selectedURL = urls.firstObject;
    if (selectedURL == nil) {
        [self cleanupPendingBackupExportFile];
        self.backupPickerImportMode = NO;
        return;
    }

    if (self.backupPickerImportMode) {
        BOOL hasScope = [selectedURL startAccessingSecurityScopedResource];
        self.backupOperationInProgress = YES;
        UIAlertController *progress = [UIAlertController alertControllerWithTitle:@"Backup"
                                                                          message:@"Importing archive..."
                                                                   preferredStyle:UIAlertControllerStyleAlert];
        [self presentViewController:progress animated:YES completion:nil];

        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf == nil) {
                if (hasScope) {
                    [selectedURL stopAccessingSecurityScopedResource];
                }
                return;
            }

            NSError *importError = nil;
            NSDictionary<NSString *, id> *importedSettings = nil;
            BOOL imported = [strongSelf.backupArchiveService importBackupArchiveFromURL:selectedURL
                                                                      importedSettings:&importedSettings
                                                                                 error:&importError];
            if (hasScope) {
                [selectedURL stopAccessingSecurityScopedResource];
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) innerSelf = weakSelf;
                if (innerSelf == nil) {
                    return;
                }

                innerSelf.backupOperationInProgress = NO;
                [progress dismissViewControllerAnimated:YES completion:^{
                    if (imported) {
                        [innerSelf applyImportedBackupSettings:importedSettings];
                        [innerSelf loadSettingsValues];
                        [innerSelf refreshStorageUsage];
                        [innerSelf notifyPlayerSettingsChanged];
                        [NSNotificationCenter.defaultCenter postNotificationName:SonoraPlaylistsDidChangeNotification object:nil];
                        [NSNotificationCenter.defaultCenter postNotificationName:SonoraFavoritesDidChangeNotification object:nil];
                        [innerSelf presentBackupInfoMessage:@"Backup archive imported successfully."];
                    } else {
                        [innerSelf presentBackupErrorMessage:(importError.localizedDescription ?: @"Could not import backup archive.")];
                    }
                }];
            });
        });
    } else {
        [self presentBackupInfoMessage:@"Backup archive exported."];
    }

    [self cleanupPendingBackupExportFile];
    self.backupPickerImportMode = NO;
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    (void)controller;
    [self cleanupPendingBackupExportFile];
    self.backupPickerImportMode = NO;
}

- (void)cleanupPendingBackupExportFile {
    if (self.pendingBackupExportURL != nil) {
        [NSFileManager.defaultManager removeItemAtURL:self.pendingBackupExportURL error:nil];
        self.pendingBackupExportURL = nil;
    }
}

- (void)presentBackupInfoMessage:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Backup"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)presentBackupErrorMessage:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Backup Error"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)notifyPlayerSettingsChanged {
    [NSNotificationCenter.defaultCenter postNotificationName:SonoraPlayerSettingsDidChangeNotification object:nil];
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

    NSUInteger matched = 0;
    for (SonoraTrack *track in queue) {
        if (track.identifier.length > 0 && [waveIDs containsObject:track.identifier]) {
            matched += 1;
        }
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
    if (shouldPreserveConfiguredWave) {
        [cell resumeWaveAnimationsIfNeeded];
    } else {
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
