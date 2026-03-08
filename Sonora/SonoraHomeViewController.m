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

static NSString * const SonoraSettingsAccentHexKey = @"sonora.settings.accentHex";
static NSString * const SonoraSettingsLegacyAccentColorKey = @"sonora.settings.accentColor";

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
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    UIColor *fromHex = SonoraHomeColorFromHexString([defaults stringForKey:SonoraSettingsAccentHexKey]);
    if (fromHex != nil) {
        return fromHex;
    }
    return SonoraHomeLegacyAccentColorForIndex([defaults integerForKey:SonoraSettingsLegacyAccentColorKey]);
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

static NSString *SonoraHomeSleepTimerRemainingString(NSTimeInterval interval) {
    NSInteger totalSeconds = (NSInteger)llround(MAX(0.0, interval));
    NSInteger hours = totalSeconds / 3600;
    NSInteger minutes = (totalSeconds % 3600) / 60;
    NSInteger seconds = totalSeconds % 60;

    if (hours > 0) {
        return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)hours, (long)minutes, (long)seconds];
    }
    return [NSString stringWithFormat:@"%ld:%02ld", (long)minutes, (long)seconds];
}

static NSTimeInterval SonoraHomeSleepTimerDurationFromInput(NSString *input) {
    NSString *trimmed = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        return 0.0;
    }

    NSArray<NSString *> *parts = [trimmed componentsSeparatedByString:@":"];
    if (parts.count == 2 || parts.count == 3) {
        NSMutableArray<NSNumber *> *values = [NSMutableArray arrayWithCapacity:parts.count];
        for (NSString *part in parts) {
            NSString *token = [part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (token.length == 0) {
                return 0.0;
            }
            NSScanner *scanner = [NSScanner scannerWithString:token];
            NSInteger value = 0;
            if (![scanner scanInteger:&value] || !scanner.isAtEnd || value < 0) {
                return 0.0;
            }
            [values addObject:@(value)];
        }

        NSTimeInterval duration = 0.0;
        if (values.count == 2) {
            NSInteger hours = values[0].integerValue;
            NSInteger minutes = values[1].integerValue;
            if (minutes >= 60) {
                return 0.0;
            }
            duration = (NSTimeInterval)(hours * 3600 + minutes * 60);
        } else {
            NSInteger hours = values[0].integerValue;
            NSInteger minutes = values[1].integerValue;
            NSInteger seconds = values[2].integerValue;
            if (minutes >= 60 || seconds >= 60) {
                return 0.0;
            }
            duration = (NSTimeInterval)(hours * 3600 + minutes * 60 + seconds);
        }

        if (duration <= 0.0 || duration > 24.0 * 3600.0) {
            return 0.0;
        }
        return duration;
    }

    NSScanner *scanner = [NSScanner scannerWithString:trimmed];
    double minutesValue = 0.0;
    if (![scanner scanDouble:&minutesValue] || !scanner.isAtEnd) {
        return 0.0;
    }

    NSTimeInterval duration = minutesValue * 60.0;
    if (!isfinite(duration) || duration <= 0.0 || duration > 24.0 * 3600.0) {
        return 0.0;
    }
    return duration;
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
    Class playerClass = NSClassFromString(@"SonoraPlayerViewController");
    if (playerClass == Nil || ![playerClass isSubclassOfClass:UIViewController.class]) {
        return nil;
    }
    return [[playerClass alloc] init];
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

@interface SonoraWaveAnimatedBackgroundView : UIView

- (void)applyPalette:(NSArray<UIColor *> *)palette animated:(BOOL)animated;
- (void)setPlaying:(BOOL)playing;
- (void)setPulseSeedWithTrackIdentifier:(NSString * _Nullable)identifier;

@end

@interface SonoraWaveAnimatedBackgroundView ()

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

@implementation SonoraWaveAnimatedBackgroundView

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
- (void)configureWithTrack:(SonoraTrack *)track;

@end

@interface SonoraHomeHeroRecommendationCell ()

@property (nonatomic, strong) SonoraWaveAnimatedBackgroundView *waveBackgroundView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, assign) BOOL playing;

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

    SonoraWaveAnimatedBackgroundView *waveBackgroundView = [[SonoraWaveAnimatedBackgroundView alloc] init];
    waveBackgroundView.translatesAutoresizingMaskIntoConstraints = NO;
    self.waveBackgroundView = waveBackgroundView;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = SonoraNotoSerifBoldFont(30.0);
    titleLabel.textColor = UIColor.whiteColor;
    titleLabel.numberOfLines = 1;
    titleLabel.text = @"My wave";
    self.titleLabel = titleLabel;

    UIButton *playButton = [UIButton buttonWithType:UIButtonTypeSystem];
    playButton.translatesAutoresizingMaskIntoConstraints = NO;
    playButton.backgroundColor = UIColor.clearColor;
    playButton.layer.cornerRadius = 0.0;
    playButton.layer.masksToBounds = NO;
    playButton.tintColor = [UIColor colorWithWhite:1.0 alpha:0.96];
    [playButton setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.96] forState:UIControlStateNormal];
    playButton.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    playButton.titleLabel.lineBreakMode = NSLineBreakByClipping;
    playButton.titleLabel.adjustsFontSizeToFitWidth = NO;
    playButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    playButton.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    playButton.contentEdgeInsets = UIEdgeInsetsMake(0.0, 0.0, 0.0, 0.0);
    playButton.imageEdgeInsets = UIEdgeInsetsMake(0.0, 0.0, 0.0, 6.0);
    playButton.titleEdgeInsets = UIEdgeInsetsMake(0.0, 4.0, 0.0, 0.0);
    [playButton addTarget:self action:@selector(playButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    self.playButton = playButton;

    [self.contentView addSubview:waveBackgroundView];
    [self.contentView addSubview:titleLabel];
    [self.contentView addSubview:playButton];

    [NSLayoutConstraint activateConstraints:@[
        [waveBackgroundView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
        [waveBackgroundView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [waveBackgroundView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [waveBackgroundView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],

        [titleLabel.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        [titleLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor constant:-16.0],
        [titleLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.leadingAnchor constant:18.0],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-18.0],

        [playButton.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        [playButton.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:12.0],
        [playButton.heightAnchor constraintEqualToConstant:38.0],
        [playButton.widthAnchor constraintGreaterThanOrEqualToConstant:92.0]
    ]];
    [self updatePlayButton];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.titleLabel.text = @"My wave";
    self.playHandler = nil;
    self.playing = NO;
    [self.waveBackgroundView setPlaying:NO];
    [self updatePlayButton];
}

- (void)playButtonTapped {
    if (self.playHandler != nil) {
        self.playHandler();
    }
}

- (void)configureWithTrack:(SonoraTrack *)track {
    NSArray<UIColor *> *palette = SonoraResolvedWavePalette(track.artwork);
    [self.waveBackgroundView setPulseSeedWithTrackIdentifier:track.identifier];
    [self.waveBackgroundView setPlaying:self.playing];
    [self.waveBackgroundView applyPalette:palette animated:YES];
}

- (void)setPlaying:(BOOL)playing {
    _playing = playing;
    [self.waveBackgroundView setPlaying:playing];
    [self updatePlayButton];
}

- (void)updatePlayButton {
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:13.0
                                                                                          weight:UIImageSymbolWeightSemibold];
    NSString *symbol = self.playing ? @"pause.fill" : @"play.fill";
    NSString *title = self.playing ? @"Pause" : @"Play";
    UIImage *image = [UIImage systemImageNamed:symbol withConfiguration:config];
    [self.playButton setImage:image forState:UIControlStateNormal];
    [self.playButton setTitle:title forState:UIControlStateNormal];
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
       SonoraHomeSleepTimerRemainingString(SonoraSleepTimerManager.sharedManager.remainingTime)]
    : @"Sleep timer";
}

- (void)presentCustomSleepTimerAlert {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Custom Sleep Timer"
                                                                   message:@"Enter minutes (e.g. 25) or h:mm (e.g. 1:30)."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"25 or 1:30";
        textField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        NSTimeInterval remaining = SonoraSleepTimerManager.sharedManager.remainingTime;
        if (remaining > 0.0) {
            textField.text = [NSString stringWithFormat:@"%.0f", ceil(remaining / 60.0)];
        }
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Set Timer"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction * _Nonnull action) {
        NSString *rawValue = alert.textFields.firstObject.text ?: @"";
        NSTimeInterval duration = SonoraHomeSleepTimerDurationFromInput(rawValue);
        if (duration <= 0.0) {
            UIAlertController *invalid = [UIAlertController alertControllerWithTitle:@"Invalid Time"
                                                                              message:@"Use minutes (25) or h:mm (1:30). Max is 24 hours."
                                                                       preferredStyle:UIAlertControllerStyleAlert];
            [invalid addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:invalid animated:YES completion:nil];
            return;
        }

        [SonoraSleepTimerManager.sharedManager startWithDuration:duration];
        [self updateSleepTimerButton];
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)sleepTimerTapped {
    SonoraSleepTimerManager *sleepTimer = SonoraSleepTimerManager.sharedManager;
    NSString *message = sleepTimer.isActive
    ? [NSString stringWithFormat:@"Will stop playback in %@.", SonoraHomeSleepTimerRemainingString(sleepTimer.remainingTime)]
    : @"Stop playback automatically after selected time.";

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Sleep Timer"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    NSArray<NSNumber *> *durations = @[@(15 * 60), @(30 * 60), @(45 * 60), @(60 * 60)];
    for (NSNumber *durationValue in durations) {
        NSInteger minutes = durationValue.integerValue / 60;
        NSString *title = [NSString stringWithFormat:@"%ld min", (long)minutes];
        [sheet addAction:[UIAlertAction actionWithTitle:title
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction * _Nonnull action) {
            [SonoraSleepTimerManager.sharedManager startWithDuration:durationValue.doubleValue];
            [self updateSleepTimerButton];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Custom..."
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction * _Nonnull action) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self presentCustomSleepTimerAlert];
        });
    }]];

    if (sleepTimer.isActive) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Turn Off Sleep Timer"
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(__unused UIAlertAction * _Nonnull action) {
            [SonoraSleepTimerManager.sharedManager cancel];
            [self updateSleepTimerButton];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover != nil) {
        UIView *anchor = self.sleepControlButton ?: self.playButton;
        popover.sourceView = anchor;
        popover.sourceRect = anchor.bounds;
    }

    [self presentViewController:sheet animated:YES completion:nil];
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

static NSString * const SonoraSettingsFontKey = @"sonora.settings.font";
static NSString * const SonoraSettingsArtworkStyleKey = @"sonora.settings.artworkStyle";
static NSString * const SonoraSettingsArtworkEqualizerKey = @"sonora.settings.showArtworkEqualizer";
static NSString * const SonoraSettingsTrackGapKey = @"sonora.settings.trackGapSeconds";
static NSString * const SonoraSettingsMaxStorageMBKey = @"sonora.settings.maxStorageMB";
static NSString * const SonoraSettingsPreservePlayerModesKey = @"sonora.settings.preservePlayerModes";
static NSString * const SonoraSettingsGitHubURLString = @"https://github.com/femboypig/Sonora";
static NSString * const SonoraSettingsGitHubDisplayString = @"femboypig/Sonora";

@interface SonoraSettingsViewController : UIViewController <UIColorPickerViewControllerDelegate>

@property (nonatomic, strong) UISegmentedControl *fontControl;
@property (nonatomic, strong) UISegmentedControl *artworkStyleControl;
@property (nonatomic, strong) UISwitch *artworkEqualizerSwitch;
@property (nonatomic, strong) UISwitch *preservePlayerModesSwitch;
@property (nonatomic, strong) UILabel *accentColorValueLabel;
@property (nonatomic, strong) UILabel *trackGapValueLabel;
@property (nonatomic, strong) UILabel *usedStorageValueLabel;
@property (nonatomic, strong) UILabel *maxStorageValueLabel;

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

- (UIControl *)selectableValueRowWithTitle:(NSString *)title
                                  subtitle:(NSString *)subtitle
                                valueLabel:(UILabel *)valueLabel
                                    action:(SEL)action {
    UIControl *row = [[UIControl alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
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

    UILabel *chevronLabel = [[UILabel alloc] init];
    chevronLabel.translatesAutoresizingMaskIntoConstraints = NO;
    chevronLabel.text = @"›";
    chevronLabel.font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightRegular];
    chevronLabel.textColor = UIColor.tertiaryLabelColor;

    valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    valueLabel.textAlignment = NSTextAlignmentRight;

    [row addSubview:titleLabel];
    [row addSubview:subtitleLabel];
    [row addSubview:valueLabel];
    [row addSubview:chevronLabel];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:row.topAnchor],
        [titleLabel.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:valueLabel.leadingAnchor constant:-8.0],

        [valueLabel.trailingAnchor constraintEqualToAnchor:chevronLabel.leadingAnchor constant:-4.0],
        [valueLabel.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],

        [chevronLabel.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [chevronLabel.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],

        [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:2.0],
        [subtitleLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [subtitleLabel.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [subtitleLabel.bottomAnchor constraintEqualToAnchor:row.bottomAnchor]
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
    titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
    titleLabel.textColor = UIColor.secondaryLabelColor;
    titleLabel.text = title;
    titleLabel.numberOfLines = 1;

    UILabel *valueTextLabel = valueLabel ?: [[UILabel alloc] init];
    valueTextLabel.translatesAutoresizingMaskIntoConstraints = NO;
    valueTextLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
    valueTextLabel.textColor = UIColor.labelColor;
    valueTextLabel.text = value;
    valueTextLabel.numberOfLines = 1;
    valueTextLabel.textAlignment = NSTextAlignmentRight;

    [row addSubview:titleLabel];
    [row addSubview:valueTextLabel];
    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:row.topAnchor],
        [titleLabel.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [titleLabel.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:valueTextLabel.leadingAnchor constant:-8.0],

        [valueTextLabel.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [valueTextLabel.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor]
    ]];
    if (valueLabel != nil) {
        valueLabel.text = value;
    }
    return row;
}

- (void)loadSettingsValues {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSInteger font = [defaults objectForKey:SonoraSettingsFontKey] ? [defaults integerForKey:SonoraSettingsFontKey] : 0;
    NSInteger artworkStyle = [defaults objectForKey:SonoraSettingsArtworkStyleKey] ? [defaults integerForKey:SonoraSettingsArtworkStyleKey] : 1;
    BOOL artworkEqualizerEnabled = [defaults objectForKey:SonoraSettingsArtworkEqualizerKey] ? [defaults boolForKey:SonoraSettingsArtworkEqualizerKey] : YES;
    BOOL preserveModes = [defaults objectForKey:SonoraSettingsPreservePlayerModesKey] ? [defaults boolForKey:SonoraSettingsPreservePlayerModesKey] : YES;
    double trackGap = [defaults objectForKey:SonoraSettingsTrackGapKey] ? [defaults doubleForKey:SonoraSettingsTrackGapKey] : 0.0;
    NSInteger maxStorageMB = [defaults objectForKey:SonoraSettingsMaxStorageMBKey] ? [defaults integerForKey:SonoraSettingsMaxStorageMBKey] : -1;

    if (font > 1) {
        font = 0;
        [defaults setInteger:font forKey:SonoraSettingsFontKey];
    }

    self.fontControl.selectedSegmentIndex = MAX(0, MIN(1, font));
    self.artworkStyleControl.selectedSegmentIndex = MAX(0, MIN(1, artworkStyle));
    self.artworkEqualizerSwitch.on = artworkEqualizerEnabled;
    self.preservePlayerModesSwitch.on = preserveModes;

    double snappedGap = [self nearestTrackGapValueForValue:trackGap];
    NSInteger snappedMaxStorage = [self nearestMaxStorageValueForValue:maxStorageMB];
    [defaults setDouble:snappedGap forKey:SonoraSettingsTrackGapKey];
    [defaults setInteger:snappedMaxStorage forKey:SonoraSettingsMaxStorageMBKey];
    [self refreshTrackGapLabel];
    [self refreshMaxStorageLabel];
    [self refreshAccentColorLabel];
}

- (void)fontChanged:(UISegmentedControl *)sender {
    [NSUserDefaults.standardUserDefaults setInteger:sender.selectedSegmentIndex forKey:SonoraSettingsFontKey];
    [self notifyPlayerSettingsChanged];
}

- (void)artworkStyleChanged:(UISegmentedControl *)sender {
    [NSUserDefaults.standardUserDefaults setInteger:sender.selectedSegmentIndex forKey:SonoraSettingsArtworkStyleKey];
    [self notifyPlayerSettingsChanged];
}

- (void)preservePlayerModesChanged:(UISwitch *)sender {
    [NSUserDefaults.standardUserDefaults setBool:sender.isOn forKey:SonoraSettingsPreservePlayerModesKey];
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
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:hex forKey:SonoraSettingsAccentHexKey];
    [defaults removeObjectForKey:SonoraSettingsLegacyAccentColorKey];
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

- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)viewController API_AVAILABLE(ios(14.0)) {
    [self storeAccentColor:viewController.selectedColor];
    [self refreshAccentColorLabel];
    [self notifyPlayerSettingsChanged];
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController API_AVAILABLE(ios(14.0)) {
    [self storeAccentColor:viewController.selectedColor];
    [self refreshAccentColorLabel];
    [self notifyPlayerSettingsChanged];
}

- (void)artworkEqualizerChanged:(UISwitch *)sender {
    [NSUserDefaults.standardUserDefaults setBool:sender.isOn forKey:SonoraSettingsArtworkEqualizerKey];
    [self notifyPlayerSettingsChanged];
}

- (void)selectTrackGapTapped {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    double current = [self nearestTrackGapValueForValue:[defaults doubleForKey:SonoraSettingsTrackGapKey]];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Delay between tracks"
                                                                   message:[NSString stringWithFormat:@"Current: %@", [self trackGapLabelForSeconds:current]]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSNumber *value in [self trackGapOptionValues]) {
        double seconds = value.doubleValue;
        NSString *title = [self trackGapLabelForSeconds:seconds];
        [sheet addAction:[UIAlertAction actionWithTitle:title
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction * _Nonnull action) {
            [NSUserDefaults.standardUserDefaults setDouble:seconds forKey:SonoraSettingsTrackGapKey];
            [self refreshTrackGapLabel];
            [self notifyPlayerSettingsChanged];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self configurePopoverForSheet:sheet];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)selectMaxStorageTapped {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSInteger current = [self nearestMaxStorageValueForValue:[defaults integerForKey:SonoraSettingsMaxStorageMBKey]];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Max player space"
                                                                   message:[NSString stringWithFormat:@"Current: %@", [self storageLabelForMB:current]]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSNumber *value in [self maxStorageOptionValues]) {
        NSInteger sizeMB = value.integerValue;
        NSString *title = [self storageLabelForMB:sizeMB];
        [sheet addAction:[UIAlertAction actionWithTitle:title
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction * _Nonnull action) {
            [NSUserDefaults.standardUserDefaults setInteger:sizeMB forKey:SonoraSettingsMaxStorageMBKey];
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
    double value = [NSUserDefaults.standardUserDefaults doubleForKey:SonoraSettingsTrackGapKey];
    self.trackGapValueLabel.text = [self trackGapLabelForSeconds:[self nearestTrackGapValueForValue:value]];
}

- (void)refreshMaxStorageLabel {
    NSInteger value = [NSUserDefaults.standardUserDefaults integerForKey:SonoraSettingsMaxStorageMBKey];
    self.maxStorageValueLabel.text = [self storageLabelForMB:[self nearestMaxStorageValueForValue:value]];
}

- (void)refreshStorageUsage {
    unsigned long long usedBytes = [self currentLibraryUsageBytes];
    self.usedStorageValueLabel.text = [NSByteCountFormatter stringFromByteCount:(long long)usedBytes
                                                                      countStyle:NSByteCountFormatterCountStyleFile];
    unsigned long long maxBytes = [self maxStorageLimitBytes];
    BOOL overLimit = (maxBytes != ULLONG_MAX && usedBytes > maxBytes);
    self.usedStorageValueLabel.textColor = overLimit ? UIColor.systemRedColor : UIColor.labelColor;
}

- (unsigned long long)maxStorageLimitBytes {
    NSInteger maxMB = [self nearestMaxStorageValueForValue:[NSUserDefaults.standardUserDefaults integerForKey:SonoraSettingsMaxStorageMBKey]];
    if (maxMB <= 0) {
        return ULLONG_MAX;
    }
    return ((unsigned long long)maxMB) * 1024ULL * 1024ULL;
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
@property (nonatomic, assign) NSInteger forYouSelectionVisit;
@property (nonatomic, assign) NSInteger homeVisitCount;

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

    [collectionView reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self applyTransparentNavigationBarAppearance];
    self.homeVisitCount += 1;
    [self reloadHomeContent];
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

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"Home";
    titleLabel.textColor = UIColor.labelColor;
    titleLabel.font = SonoraYSMusicFont(30.0);
    [titleLabel sizeToFit];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:titleLabel];

    UIBarButtonItem *clockItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"clock"]
                                                                   style:UIBarButtonItemStylePlain
                                                                  target:self
                                                                  action:@selector(openHistoryTapped)];
    UIBarButtonItem *settingsItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"gearshape"]
                                                                      style:UIBarButtonItemStylePlain
                                                                     target:self
                                                                     action:@selector(openSettingsTapped)];
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
                                                                                    subitem:item
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
    NSArray<SonoraTrack *> *tracks = SonoraLibraryManager.sharedManager.tracks;
    if (tracks.count == 0) {
        tracks = [SonoraLibraryManager.sharedManager reloadTracks];
    }

    self.allTracks = tracks ?: @[];
    self.recommendationTracks = [self buildForYouTracksFromTracks:self.allTracks limit:120];
    self.needThisTracks = [self buildRecommendationsFromTracks:self.allTracks limit:12];
    self.freshTracks = [self buildFreshChoiceTracksFromTracks:self.allTracks limit:12];

    [self.collectionView reloadData];
    [self updateEmptyStateIfNeeded];
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

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                            cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    switch ((SonoraHomeSectionType)indexPath.section) {
        case SonoraHomeSectionTypeForYou: {
            SonoraHomeHeroRecommendationCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:SonoraHomeHeroRecommendationCellReuseID
                                                                                             forIndexPath:indexPath];
            if (self.recommendationTracks.count > 0) {
                NSArray<SonoraTrack *> *queue = SonoraPlaybackManager.sharedManager.currentQueue;
                SonoraTrack *currentTrack = SonoraPlaybackManager.sharedManager.currentTrack;
                BOOL isWaveQueue = [self isWaveQueueActiveForQueue:queue currentTrack:currentTrack];
                SonoraTrack *displayTrack = (isWaveQueue && currentTrack != nil) ? currentTrack : self.recommendationTracks.firstObject;
                [cell configureWithTrack:displayTrack];
                cell.playing = isWaveQueue && SonoraPlaybackManager.sharedManager.isPlaying;
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
