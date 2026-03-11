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

static NSString *SonoraHomeStableHashString(NSString *value) {
    if (value.length == 0) {
        return @"0";
    }

    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    if (data.length == 0) {
        return @"0";
    }

    const uint8_t *bytes = data.bytes;
    uint64_t hash = 1469598103934665603ULL;
    for (NSUInteger index = 0; index < data.length; index += 1) {
        hash ^= bytes[index];
        hash *= 1099511628211ULL;
    }

    return [NSString stringWithFormat:@"%016llx", hash];
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
static NSString * const SonoraSettingsCacheOnlinePlaylistTracksKey = @"sonora.settings.cacheOnlinePlaylistTracks";
static NSString * const SonoraSettingsOnlinePlaylistCacheMaxMBKey = @"sonora.settings.onlinePlaylistCacheMaxMB";
static NSString * const SonoraSettingsPreservePlayerModesKey = @"sonora.settings.preservePlayerModes";
static NSString * const SonoraBackupArchiveMagicString = @"SONORAAR";
static NSString * const SonoraBackupManifestEntryName = @"meta/manifest.v1";
static NSString * const SonoraBackupArchiveErrorDomain = @"SonoraBackupArchive";
static NSInteger const SonoraBackupArchiveVersion = 1;
static NSString * const SonoraSettingsGitHubURLString = @"https://github.com/femboypig/Sonora";
static NSString * const SonoraSettingsGitHubDisplayString = @"femboypig/Sonora";

@interface SonoraSettingsViewController : UIViewController <UIColorPickerViewControllerDelegate, UIDocumentPickerDelegate>

@property (nonatomic, strong) UISegmentedControl *fontControl;
@property (nonatomic, strong) UISegmentedControl *artworkStyleControl;
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
@property (nonatomic, assign) BOOL backupPickerImportMode;

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
    BOOL cacheOnlinePlaylistTracks = [defaults objectForKey:SonoraSettingsCacheOnlinePlaylistTracksKey] ? [defaults boolForKey:SonoraSettingsCacheOnlinePlaylistTracksKey] : NO;
    NSInteger onlinePlaylistCacheMaxMB = [defaults objectForKey:SonoraSettingsOnlinePlaylistCacheMaxMBKey] ? [defaults integerForKey:SonoraSettingsOnlinePlaylistCacheMaxMBKey] : 1024;

    if (font > 1) {
        font = 0;
        [defaults setInteger:font forKey:SonoraSettingsFontKey];
    }

    self.fontControl.selectedSegmentIndex = MAX(0, MIN(1, font));
    self.artworkStyleControl.selectedSegmentIndex = MAX(0, MIN(1, artworkStyle));
    self.artworkEqualizerSwitch.on = artworkEqualizerEnabled;
    self.preservePlayerModesSwitch.on = preserveModes;
    self.onlinePlaylistCacheTracksSwitch.on = cacheOnlinePlaylistTracks;

    double snappedGap = [self nearestTrackGapValueForValue:trackGap];
    NSInteger snappedMaxStorage = [self nearestMaxStorageValueForValue:maxStorageMB];
    NSInteger snappedOnlinePlaylistCache = [self nearestMaxStorageValueForValue:onlinePlaylistCacheMaxMB];
    [defaults setDouble:snappedGap forKey:SonoraSettingsTrackGapKey];
    [defaults setInteger:snappedMaxStorage forKey:SonoraSettingsMaxStorageMBKey];
    [defaults setInteger:snappedOnlinePlaylistCache forKey:SonoraSettingsOnlinePlaylistCacheMaxMBKey];
    [self refreshTrackGapLabel];
    [self refreshMaxStorageLabel];
    [self refreshOnlinePlaylistCacheUsageLabel];
    [self refreshOnlinePlaylistCacheLabel];
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

- (void)cacheOnlinePlaylistTracksChanged:(UISwitch *)sender {
    [NSUserDefaults.standardUserDefaults setBool:sender.isOn forKey:SonoraSettingsCacheOnlinePlaylistTracksKey];
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

- (void)selectOnlinePlaylistCacheTapped {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSInteger current = [self nearestMaxStorageValueForValue:[defaults integerForKey:SonoraSettingsOnlinePlaylistCacheMaxMBKey]];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Max online cache space"
                                                                   message:[NSString stringWithFormat:@"Current: %@", [self storageLabelForMB:current]]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSNumber *value in [self maxStorageOptionValues]) {
        NSInteger sizeMB = value.integerValue;
        NSString *title = [self storageLabelForMB:sizeMB];
        [sheet addAction:[UIAlertAction actionWithTitle:title
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction * _Nonnull action) {
            [NSUserDefaults.standardUserDefaults setInteger:sizeMB forKey:SonoraSettingsOnlinePlaylistCacheMaxMBKey];
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
    double value = [NSUserDefaults.standardUserDefaults doubleForKey:SonoraSettingsTrackGapKey];
    self.trackGapValueLabel.text = [self trackGapLabelForSeconds:[self nearestTrackGapValueForValue:value]];
}

- (void)refreshMaxStorageLabel {
    NSInteger value = [NSUserDefaults.standardUserDefaults integerForKey:SonoraSettingsMaxStorageMBKey];
    self.maxStorageValueLabel.text = [self storageLabelForMB:[self nearestMaxStorageValueForValue:value]];
}

- (void)refreshOnlinePlaylistCacheLabel {
    NSInteger value = [NSUserDefaults.standardUserDefaults integerForKey:SonoraSettingsOnlinePlaylistCacheMaxMBKey];
    self.onlinePlaylistCacheValueLabel.text = [self storageLabelForMB:[self nearestMaxStorageValueForValue:value]];
}

- (void)refreshSharedPlaylistAudioCacheIfNeeded {
    Class sharedPlaylistStoreClass = NSClassFromString(@"SonoraSharedPlaylistStore");
    if (sharedPlaylistStoreClass == Nil) {
        return;
    }
    id sharedPlaylistStore = [sharedPlaylistStoreClass performSelector:@selector(sharedStore)];
    if (![sharedPlaylistStore respondsToSelector:@selector(refreshAllPersistentCachesIfNeeded)]) {
        return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [sharedPlaylistStore performSelector:@selector(refreshAllPersistentCachesIfNeeded)];
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
    NSInteger maxMB = [self nearestMaxStorageValueForValue:[NSUserDefaults.standardUserDefaults integerForKey:SonoraSettingsMaxStorageMBKey]];
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
    NSInteger maxMB = [self nearestMaxStorageValueForValue:[NSUserDefaults.standardUserDefaults integerForKey:SonoraSettingsOnlinePlaylistCacheMaxMBKey]];
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

- (void)exportBackupTapped {
    NSError *archiveError = nil;
    NSData *archiveData = [self backupArchiveDataWithError:&archiveError];
    if (archiveData.length == 0) {
        [self presentBackupErrorMessage:(archiveError.localizedDescription ?: @"Could not create backup archive.")];
        return;
    }

    NSString *fileName = [self backupArchiveFileName];
    NSString *temporaryPath = [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];
    NSURL *temporaryURL = [NSURL fileURLWithPath:temporaryPath];
    NSError *writeError = nil;
    [archiveData writeToURL:temporaryURL options:NSDataWritingAtomic error:&writeError];
    if (writeError != nil) {
        [self presentBackupErrorMessage:(writeError.localizedDescription ?: @"Could not prepare backup file.")];
        return;
    }

    UIDocumentPickerViewController *picker = nil;
    if (@available(iOS 14.0, *)) {
        picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[temporaryURL] asCopy:YES];
    } else {
        picker = [[UIDocumentPickerViewController alloc] initWithURL:temporaryURL inMode:UIDocumentPickerModeExportToService];
    }
    picker.delegate = self;
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    self.pendingBackupExportURL = temporaryURL;
    self.backupPickerImportMode = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)importBackupTapped {
    UIDocumentPickerViewController *picker =
    [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.data"]
                                                           inMode:UIDocumentPickerModeImport];
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
        NSError *importError = nil;
        BOOL imported = [self importBackupArchiveFromURL:selectedURL error:&importError];
        if (hasScope) {
            [selectedURL stopAccessingSecurityScopedResource];
        }

        if (imported) {
            [self presentBackupInfoMessage:@"Backup archive imported successfully."];
        } else {
            [self presentBackupErrorMessage:(importError.localizedDescription ?: @"Could not import backup archive.")];
        }
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

- (NSString *)backupArchiveFileName {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyyMMdd_HHmmss";
    NSString *suffix = [formatter stringFromDate:[NSDate date]] ?: @"backup";
    return [NSString stringWithFormat:@"sonora_backup_%@.sonoraarc", suffix];
}

- (NSError *)backupErrorWithCode:(NSInteger)code description:(NSString *)description {
    NSString *resolved = description.length > 0 ? description : @"Backup error.";
    return [NSError errorWithDomain:SonoraBackupArchiveErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: resolved}];
}

- (NSString *)safeTokenFromString:(NSString *)raw fallback:(NSString *)fallback {
    NSString *source = [raw isKindOfClass:NSString.class] ? raw : @"";
    if (source.length == 0) {
        source = fallback.length > 0 ? fallback : @"item";
    }
    NSMutableString *result = [NSMutableString stringWithCapacity:source.length];
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"];
    for (NSUInteger idx = 0; idx < source.length; idx += 1) {
        unichar ch = [source characterAtIndex:idx];
        if ([allowed characterIsMember:ch]) {
            [result appendFormat:@"%C", ch];
        } else {
            [result appendString:@"_"];
        }
    }
    NSString *normalized = [[result copy] lowercaseString];
    if (normalized.length == 0) {
        return [NSString stringWithFormat:@"%@_%@", fallback ?: @"item", NSUUID.UUID.UUIDString.lowercaseString];
    }
    return normalized;
}

- (NSString *)safeExtensionFromString:(NSString *)raw fallback:(NSString *)fallback {
    NSString *source = [raw isKindOfClass:NSString.class] ? raw.lowercaseString : @"";
    NSMutableString *result = [NSMutableString stringWithCapacity:source.length];
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789"];
    for (NSUInteger idx = 0; idx < source.length; idx += 1) {
        unichar ch = [source characterAtIndex:idx];
        if ([allowed characterIsMember:ch]) {
            [result appendFormat:@"%C", ch];
        }
    }
    if (result.length == 0) {
        [result appendString:(fallback.length > 0 ? fallback : @"bin")];
    }
    return [result copy];
}

- (NSString *)uniqueFileNameInDirectoryURL:(NSURL *)directoryURL preferredName:(NSString *)preferredName {
    NSString *baseName = [preferredName.stringByDeletingPathExtension stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *extension = [self safeExtensionFromString:preferredName.pathExtension fallback:@"bin"];
    if (baseName.length == 0) {
        baseName = @"track";
    }
    baseName = [self safeTokenFromString:baseName fallback:@"track"];

    NSString *candidate = [NSString stringWithFormat:@"%@.%@", baseName, extension];
    NSUInteger index = 1;
    while ([NSFileManager.defaultManager fileExistsAtPath:[directoryURL URLByAppendingPathComponent:candidate].path]) {
        candidate = [NSString stringWithFormat:@"%@_%lu.%@", baseName, (unsigned long)index, extension];
        index += 1;
    }
    return candidate;
}

- (void)appendUInt32:(uint32_t)value toData:(NSMutableData *)data {
    uint32_t bigEndian = CFSwapInt32HostToBig(value);
    [data appendBytes:&bigEndian length:sizeof(uint32_t)];
}

- (void)appendUInt64:(uint64_t)value toData:(NSMutableData *)data {
    uint64_t bigEndian = CFSwapInt64HostToBig(value);
    [data appendBytes:&bigEndian length:sizeof(uint64_t)];
}

- (BOOL)readUInt32:(uint32_t *)value fromData:(NSData *)data offset:(NSUInteger *)offset {
    if (value == NULL || data == nil || offset == NULL) {
        return NO;
    }
    if ((*offset + sizeof(uint32_t)) > data.length) {
        return NO;
    }
    uint32_t rawValue = 0;
    [data getBytes:&rawValue range:NSMakeRange(*offset, sizeof(uint32_t))];
    *offset += sizeof(uint32_t);
    *value = CFSwapInt32BigToHost(rawValue);
    return YES;
}

- (BOOL)readUInt64:(uint64_t *)value fromData:(NSData *)data offset:(NSUInteger *)offset {
    if (value == NULL || data == nil || offset == NULL) {
        return NO;
    }
    if ((*offset + sizeof(uint64_t)) > data.length) {
        return NO;
    }
    uint64_t rawValue = 0;
    [data getBytes:&rawValue range:NSMakeRange(*offset, sizeof(uint64_t))];
    *offset += sizeof(uint64_t);
    *value = CFSwapInt64BigToHost(rawValue);
    return YES;
}

- (nullable NSDictionary<NSString *, NSData *> *)parseArchiveEntriesFromData:(NSData *)data error:(NSError **)error {
    NSData *magicData = [SonoraBackupArchiveMagicString dataUsingEncoding:NSASCIIStringEncoding];
    if (magicData.length == 0 || data.length < (magicData.length + sizeof(uint32_t) + sizeof(uint32_t))) {
        if (error != NULL) {
            *error = [self backupErrorWithCode:100 description:@"Invalid backup archive file."];
        }
        return nil;
    }

    NSData *receivedMagic = [data subdataWithRange:NSMakeRange(0, magicData.length)];
    if (![receivedMagic isEqualToData:magicData]) {
        if (error != NULL) {
            *error = [self backupErrorWithCode:101 description:@"Backup archive header mismatch."];
        }
        return nil;
    }

    NSUInteger offset = magicData.length;
    uint32_t version = 0;
    uint32_t entryCount = 0;
    if (![self readUInt32:&version fromData:data offset:&offset] ||
        ![self readUInt32:&entryCount fromData:data offset:&offset]) {
        if (error != NULL) {
            *error = [self backupErrorWithCode:102 description:@"Backup archive is corrupted."];
        }
        return nil;
    }
    if ((NSInteger)version != SonoraBackupArchiveVersion) {
        if (error != NULL) {
            *error = [self backupErrorWithCode:103 description:@"Unsupported backup archive version."];
        }
        return nil;
    }
    if (entryCount == 0) {
        if (error != NULL) {
            *error = [self backupErrorWithCode:104 description:@"Backup archive has no entries."];
        }
        return nil;
    }

    NSMutableDictionary<NSString *, NSData *> *entries = [NSMutableDictionary dictionaryWithCapacity:entryCount];
    for (uint32_t idx = 0; idx < entryCount; idx += 1) {
        uint32_t nameLength = 0;
        if (![self readUInt32:&nameLength fromData:data offset:&offset] || nameLength == 0 || nameLength > 2048) {
            if (error != NULL) {
                *error = [self backupErrorWithCode:105 description:@"Backup entry name is invalid."];
            }
            return nil;
        }
        if ((offset + nameLength) > data.length) {
            if (error != NULL) {
                *error = [self backupErrorWithCode:106 description:@"Backup entry exceeds archive bounds."];
            }
            return nil;
        }
        NSData *nameData = [data subdataWithRange:NSMakeRange(offset, nameLength)];
        offset += nameLength;
        NSString *name = [[NSString alloc] initWithData:nameData encoding:NSUTF8StringEncoding];
        if (name.length == 0) {
            if (error != NULL) {
                *error = [self backupErrorWithCode:107 description:@"Backup entry name cannot be decoded."];
            }
            return nil;
        }

        uint64_t payloadLength = 0;
        if (![self readUInt64:&payloadLength fromData:data offset:&offset]) {
            if (error != NULL) {
                *error = [self backupErrorWithCode:108 description:@"Backup entry payload is corrupted."];
            }
            return nil;
        }
        if (payloadLength > (uint64_t)(data.length - offset)) {
            if (error != NULL) {
                *error = [self backupErrorWithCode:109 description:@"Backup entry payload exceeds archive bounds."];
            }
            return nil;
        }
        NSData *payload = [data subdataWithRange:NSMakeRange(offset, (NSUInteger)payloadLength)];
        offset += (NSUInteger)payloadLength;
        entries[name] = payload;
    }

    return [entries copy];
}

- (nullable NSData *)backupArchiveDataWithError:(NSError **)error {
    SonoraLibraryManager *library = SonoraLibraryManager.sharedManager;
    NSArray<SonoraTrack *> *tracks = library.tracks;
    if (tracks.count == 0) {
        tracks = [library reloadTracks];
    }
    SonoraPlaylistStore *playlistStore = SonoraPlaylistStore.sharedStore;
    NSArray<SonoraPlaylist *> *playlists = playlistStore.playlists ?: @[];
    NSSet<NSString *> *favoriteSourceIDs = [NSSet setWithArray:SonoraFavoritesStore.sharedStore.favoriteTrackIDs ?: @[]];

    NSMutableDictionary<NSString *, NSData *> *entryDataByName = [NSMutableDictionary dictionary];
    NSMutableArray<NSDictionary<NSString *, id> *> *manifestTracks = [NSMutableArray array];
    NSMutableArray<NSDictionary<NSString *, id> *> *manifestPlaylists = [NSMutableArray array];
    NSMutableOrderedSet<NSString *> *favoriteBackupIDs = [NSMutableOrderedSet orderedSet];
    NSMutableDictionary<NSString *, NSString *> *backupIDByTrackID = [NSMutableDictionary dictionary];
    NSMutableSet<NSString *> *usedTrackBackupIDs = [NSMutableSet set];

    NSUInteger trackIndex = 0;
    for (SonoraTrack *track in tracks) {
        NSURL *sourceURL = track.url;
        if (sourceURL == nil) {
            continue;
        }
        NSData *audioData = [NSData dataWithContentsOfURL:sourceURL options:NSDataReadingMappedIfSafe error:nil];
        if (audioData.length == 0) {
            continue;
        }

        NSString *seed = track.identifier.length > 0 ? track.identifier : NSUUID.UUID.UUIDString;
        NSString *hash = SonoraHomeStableHashString(seed);
        if (hash.length > 8) {
            hash = [hash substringToIndex:8];
        }
        NSString *baseBackupID = [self safeTokenFromString:[NSString stringWithFormat:@"t%04lu_%@", (unsigned long)trackIndex, hash]
                                                   fallback:@"track"];
        NSString *backupID = baseBackupID;
        NSUInteger suffix = 1;
        while ([usedTrackBackupIDs containsObject:backupID]) {
            backupID = [NSString stringWithFormat:@"%@_%lu", baseBackupID, (unsigned long)suffix];
            suffix += 1;
        }
        [usedTrackBackupIDs addObject:backupID];

        NSString *extension = [self safeExtensionFromString:sourceURL.pathExtension fallback:@"bin"];
        NSString *songEntry = [NSString stringWithFormat:@"songs/%@.%@", backupID, extension];
        entryDataByName[songEntry] = audioData;

        if (track.identifier.length > 0) {
            backupIDByTrackID[track.identifier] = backupID;
        }

        BOOL isFavorite = (track.identifier.length > 0 && [favoriteSourceIDs containsObject:track.identifier]);
        if (isFavorite) {
            [favoriteBackupIDs addObject:backupID];
        }

        [manifestTracks addObject:@{
            @"id": backupID,
            @"title": (track.title ?: @""),
            @"artist": (track.artist ?: @""),
            @"durationMs": @((long long)llround(MAX(0.0, track.duration) * 1000.0)),
            @"addedAt": @0,
            @"songEntry": songEntry,
            @"isFavorite": @(isFavorite)
        }];
        trackIndex += 1;
    }

    NSMutableSet<NSString *> *usedPlaylistBackupIDs = [NSMutableSet set];
    NSURL *documentsURL = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *coversDirectoryURL = [documentsURL URLByAppendingPathComponent:@"PlaylistCovers" isDirectory:YES];
    for (SonoraPlaylist *playlist in playlists) {
        NSString *basePlaylistID = [self safeTokenFromString:playlist.playlistID fallback:@"playlist"];
        NSString *backupPlaylistID = basePlaylistID;
        NSUInteger suffix = 1;
        while ([usedPlaylistBackupIDs containsObject:backupPlaylistID]) {
            backupPlaylistID = [NSString stringWithFormat:@"%@_%lu", basePlaylistID, (unsigned long)suffix];
            suffix += 1;
        }
        [usedPlaylistBackupIDs addObject:backupPlaylistID];

        NSMutableOrderedSet<NSString *> *mappedTrackIDs = [NSMutableOrderedSet orderedSet];
        for (NSString *sourceTrackID in playlist.trackIDs ?: @[]) {
            NSString *mapped = backupIDByTrackID[sourceTrackID];
            if (mapped.length > 0) {
                [mappedTrackIDs addObject:mapped];
            }
        }

        NSString *coverEntry = nil;
        if (playlist.customCoverFileName.length > 0) {
            NSURL *coverURL = [coversDirectoryURL URLByAppendingPathComponent:playlist.customCoverFileName];
            NSData *coverData = [NSData dataWithContentsOfURL:coverURL options:NSDataReadingMappedIfSafe error:nil];
            if (coverData.length > 0) {
                NSString *coverExtension = [self safeExtensionFromString:coverURL.pathExtension fallback:@"png"];
                coverEntry = [NSString stringWithFormat:@"playlist_covers/%@.%@", backupPlaylistID, coverExtension];
                entryDataByName[coverEntry] = coverData;
            }
        }

        NSMutableDictionary<NSString *, id> *manifestPlaylist = [@{
            @"id": backupPlaylistID,
            @"name": (playlist.name ?: @"Playlist"),
            @"trackIds": mappedTrackIDs.array ?: @[],
            @"createdAt": @0
        } mutableCopy];
        if (coverEntry.length > 0) {
            manifestPlaylist[@"coverEntry"] = coverEntry;
        }
        [manifestPlaylists addObject:[manifestPlaylist copy]];
    }

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSInteger fontValue = [defaults objectForKey:SonoraSettingsFontKey] ? [defaults integerForKey:SonoraSettingsFontKey] : 0;
    NSInteger artworkStyleValue = [defaults objectForKey:SonoraSettingsArtworkStyleKey] ? [defaults integerForKey:SonoraSettingsArtworkStyleKey] : 1;
    BOOL artworkEqualizer = [defaults objectForKey:SonoraSettingsArtworkEqualizerKey] ? [defaults boolForKey:SonoraSettingsArtworkEqualizerKey] : YES;
    BOOL preserveModes = [defaults objectForKey:SonoraSettingsPreservePlayerModesKey] ? [defaults boolForKey:SonoraSettingsPreservePlayerModesKey] : YES;
    double trackGap = [defaults objectForKey:SonoraSettingsTrackGapKey] ? [defaults doubleForKey:SonoraSettingsTrackGapKey] : 0.0;
    NSInteger maxStorageMb = [defaults objectForKey:SonoraSettingsMaxStorageMBKey] ? [defaults integerForKey:SonoraSettingsMaxStorageMBKey] : -1;
    BOOL cacheOnlinePlaylistTracks = [defaults objectForKey:SonoraSettingsCacheOnlinePlaylistTracksKey] ? [defaults boolForKey:SonoraSettingsCacheOnlinePlaylistTracksKey] : NO;
    NSInteger onlinePlaylistCacheMaxMb = [defaults objectForKey:SonoraSettingsOnlinePlaylistCacheMaxMBKey] ? [defaults integerForKey:SonoraSettingsOnlinePlaylistCacheMaxMBKey] : 1024;

    NSDictionary<NSString *, id> *settings = @{
        @"fontStyle": (fontValue == 1 ? @"serif" : @"system"),
        @"artworkStyle": (artworkStyleValue == 0 ? @"square" : @"rounded"),
        @"accentHex": [self hexStringForColor:[self currentAccentColor]],
        @"preservePlayerModes": @(preserveModes),
        @"trackGapSeconds": @(trackGap),
        @"maxStorageMb": @(maxStorageMb),
        @"cacheOnlinePlaylistTracks": @(cacheOnlinePlaylistTracks),
        @"onlinePlaylistCacheMaxMb": @(onlinePlaylistCacheMaxMb),
        @"artworkEqualizer": @(artworkEqualizer)
    };

    NSDictionary<NSString *, id> *manifest = @{
        @"format": @"sonora-archive",
        @"version": @(SonoraBackupArchiveVersion),
        @"exportedAt": @((long long)llround([NSDate date].timeIntervalSince1970 * 1000.0)),
        @"tracks": manifestTracks,
        @"playlists": manifestPlaylists,
        @"favorites": favoriteBackupIDs.array ?: @[],
        @"settings": settings
    };
    NSError *jsonError = nil;
    NSData *manifestData = [NSJSONSerialization dataWithJSONObject:manifest options:0 error:&jsonError];
    if (jsonError != nil || manifestData.length == 0) {
        if (error != NULL) {
            *error = [self backupErrorWithCode:200 description:(jsonError.localizedDescription ?: @"Could not encode backup manifest.")];
        }
        return nil;
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *orderedEntries = [NSMutableArray array];
    [orderedEntries addObject:@{
        @"name": SonoraBackupManifestEntryName,
        @"data": manifestData
    }];

    NSArray<NSString *> *sortedNames = [[entryDataByName allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *entryName in sortedNames) {
        NSData *entryData = entryDataByName[entryName];
        if (entryData.length == 0) {
            continue;
        }
        [orderedEntries addObject:@{
            @"name": entryName,
            @"data": entryData
        }];
    }

    NSData *magicData = [SonoraBackupArchiveMagicString dataUsingEncoding:NSASCIIStringEncoding];
    if (magicData.length != 8) {
        if (error != NULL) {
            *error = [self backupErrorWithCode:201 description:@"Backup archive magic is invalid."];
        }
        return nil;
    }

    NSMutableData *archiveData = [NSMutableData data];
    [archiveData appendData:magicData];
    [self appendUInt32:(uint32_t)SonoraBackupArchiveVersion toData:archiveData];
    [self appendUInt32:(uint32_t)orderedEntries.count toData:archiveData];

    for (NSDictionary<NSString *, id> *entry in orderedEntries) {
        NSString *entryName = [entry[@"name"] isKindOfClass:NSString.class] ? entry[@"name"] : @"";
        NSData *entryPayload = [entry[@"data"] isKindOfClass:NSData.class] ? entry[@"data"] : nil;
        if (entryName.length == 0 || entryPayload.length == 0) {
            continue;
        }
        NSData *entryNameData = [entryName dataUsingEncoding:NSUTF8StringEncoding];
        [self appendUInt32:(uint32_t)entryNameData.length toData:archiveData];
        [archiveData appendData:entryNameData];
        [self appendUInt64:(uint64_t)entryPayload.length toData:archiveData];
        [archiveData appendData:entryPayload];
    }

    return [archiveData copy];
}

- (BOOL)importBackupArchiveFromURL:(NSURL *)url error:(NSError **)error {
    NSError *readError = nil;
    NSData *archiveData = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:&readError];
    if (archiveData.length == 0 || readError != nil) {
        if (error != NULL) {
            *error = [self backupErrorWithCode:300 description:(readError.localizedDescription ?: @"Could not read backup archive.")];
        }
        return NO;
    }

    NSDictionary<NSString *, NSData *> *entries = [self parseArchiveEntriesFromData:archiveData error:error];
    if (entries == nil) {
        return NO;
    }

    NSData *manifestData = entries[SonoraBackupManifestEntryName];
    if (manifestData.length == 0) {
        if (error != NULL) {
            *error = [self backupErrorWithCode:301 description:@"Backup archive has no manifest."];
        }
        return NO;
    }

    NSError *jsonError = nil;
    id manifestObject = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:&jsonError];
    if (![manifestObject isKindOfClass:NSDictionary.class] || jsonError != nil) {
        if (error != NULL) {
            *error = [self backupErrorWithCode:302 description:(jsonError.localizedDescription ?: @"Backup manifest is invalid.")];
        }
        return NO;
    }
    NSDictionary<NSString *, id> *manifest = (NSDictionary<NSString *, id> *)manifestObject;
    NSArray<NSDictionary<NSString *, id> *> *manifestTracks =
    [manifest[@"tracks"] isKindOfClass:NSArray.class] ? manifest[@"tracks"] : @[];
    NSArray<NSDictionary<NSString *, id> *> *manifestPlaylists =
    [manifest[@"playlists"] isKindOfClass:NSArray.class] ? manifest[@"playlists"] : @[];
    NSArray *manifestFavoritesRaw = [manifest[@"favorites"] isKindOfClass:NSArray.class] ? manifest[@"favorites"] : @[];

    SonoraLibraryManager *library = SonoraLibraryManager.sharedManager;
    SonoraPlaylistStore *playlistStore = SonoraPlaylistStore.sharedStore;
    SonoraFavoritesStore *favoritesStore = SonoraFavoritesStore.sharedStore;

    NSArray<SonoraTrack *> *currentTracks = [library reloadTracks];
    for (SonoraTrack *track in [currentTracks copy]) {
        [library deleteTrackWithIdentifier:track.identifier error:nil];
    }
    for (SonoraPlaylist *playlist in [playlistStore.playlists copy]) {
        [playlistStore deletePlaylistWithID:playlist.playlistID];
    }
    for (NSString *favoriteID in [favoritesStore.favoriteTrackIDs copy]) {
        [favoritesStore setTrackID:favoriteID favorite:NO];
    }

    NSURL *musicDirectoryURL = [library musicDirectoryURL];
    [NSFileManager.defaultManager createDirectoryAtURL:musicDirectoryURL
                           withIntermediateDirectories:YES
                                            attributes:nil
                                                 error:nil];

    NSMutableDictionary<NSString *, NSString *> *backupFileNameByTrackID = [NSMutableDictionary dictionary];
    NSMutableOrderedSet<NSString *> *favoriteBackupIDs = [NSMutableOrderedSet orderedSet];

    for (NSDictionary<NSString *, id> *trackDictionary in manifestTracks) {
        if (![trackDictionary isKindOfClass:NSDictionary.class]) {
            continue;
        }
        NSString *backupID = [trackDictionary[@"id"] isKindOfClass:NSString.class] ? trackDictionary[@"id"] : @"";
        NSString *songEntry = [trackDictionary[@"songEntry"] isKindOfClass:NSString.class] ? trackDictionary[@"songEntry"] : @"";
        if (backupID.length == 0 || songEntry.length == 0) {
            continue;
        }
        NSData *songData = entries[songEntry];
        if (songData.length == 0) {
            continue;
        }
        NSString *preferredFileName = songEntry.lastPathComponent;
        if (preferredFileName.length == 0) {
            preferredFileName = [NSString stringWithFormat:@"%@.bin", [self safeTokenFromString:backupID fallback:@"track"]];
        }
        NSString *uniqueFileName = [self uniqueFileNameInDirectoryURL:musicDirectoryURL preferredName:preferredFileName];
        NSURL *targetURL = [musicDirectoryURL URLByAppendingPathComponent:uniqueFileName];
        NSError *writeError = nil;
        [songData writeToURL:targetURL options:NSDataWritingAtomic error:&writeError];
        if (writeError != nil) {
            if (error != NULL) {
                *error = [self backupErrorWithCode:303 description:(writeError.localizedDescription ?: @"Could not restore audio file from archive.")];
            }
            return NO;
        }
        backupFileNameByTrackID[backupID] = uniqueFileName;

        id favoriteFlag = trackDictionary[@"isFavorite"];
        if ([favoriteFlag respondsToSelector:@selector(boolValue)] && [favoriteFlag boolValue]) {
            [favoriteBackupIDs addObject:backupID];
        }
    }

    for (id value in manifestFavoritesRaw) {
        if ([value isKindOfClass:NSString.class] && ((NSString *)value).length > 0) {
            [favoriteBackupIDs addObject:(NSString *)value];
        }
    }

    NSArray<SonoraTrack *> *restoredTracks = [library reloadTracks];
    NSMutableDictionary<NSString *, NSString *> *trackIDByFileName = [NSMutableDictionary dictionary];
    for (SonoraTrack *track in restoredTracks) {
        if (track.fileName.length > 0 && track.identifier.length > 0) {
            trackIDByFileName[track.fileName.lowercaseString] = track.identifier;
        }
    }

    NSMutableDictionary<NSString *, NSString *> *localTrackIDByBackupID = [NSMutableDictionary dictionary];
    [backupFileNameByTrackID enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull backupID, NSString * _Nonnull fileName, BOOL * _Nonnull stop) {
        (void)stop;
        NSString *localTrackID = trackIDByFileName[fileName.lowercaseString];
        if (localTrackID.length > 0) {
            localTrackIDByBackupID[backupID] = localTrackID;
        }
    }];

    for (NSString *backupFavoriteID in favoriteBackupIDs) {
        NSString *localTrackID = localTrackIDByBackupID[backupFavoriteID];
        if (localTrackID.length > 0) {
            [favoritesStore setTrackID:localTrackID favorite:YES];
        }
    }

    for (NSDictionary<NSString *, id> *playlistDictionary in manifestPlaylists) {
        if (![playlistDictionary isKindOfClass:NSDictionary.class]) {
            continue;
        }
        NSString *playlistName = [playlistDictionary[@"name"] isKindOfClass:NSString.class] ? playlistDictionary[@"name"] : @"";
        playlistName = [playlistName stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (playlistName.length == 0) {
            continue;
        }

        NSArray *backupTrackIDs = [playlistDictionary[@"trackIds"] isKindOfClass:NSArray.class] ? playlistDictionary[@"trackIds"] : @[];
        NSMutableOrderedSet<NSString *> *localTrackIDs = [NSMutableOrderedSet orderedSet];
        for (id value in backupTrackIDs) {
            if (![value isKindOfClass:NSString.class]) {
                continue;
            }
            NSString *localTrackID = localTrackIDByBackupID[(NSString *)value];
            if (localTrackID.length > 0) {
                [localTrackIDs addObject:localTrackID];
            }
        }
        if (localTrackIDs.count == 0) {
            continue;
        }

        UIImage *coverImage = nil;
        NSString *coverEntry = [playlistDictionary[@"coverEntry"] isKindOfClass:NSString.class] ? playlistDictionary[@"coverEntry"] : @"";
        if (coverEntry.length > 0) {
            NSData *coverData = entries[coverEntry];
            if (coverData.length > 0) {
                coverImage = [UIImage imageWithData:coverData];
            }
        }

        [playlistStore addPlaylistWithName:playlistName
                                   trackIDs:localTrackIDs.array
                                 coverImage:coverImage];
    }

    NSDictionary<NSString *, id> *settings = [manifest[@"settings"] isKindOfClass:NSDictionary.class] ? manifest[@"settings"] : nil;
    if (settings != nil) {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;

        id fontValue = settings[@"fontStyle"];
        NSInteger fontIndex = 0;
        if ([fontValue isKindOfClass:NSString.class]) {
            fontIndex = [((NSString *)fontValue).lowercaseString isEqualToString:@"serif"] ? 1 : 0;
        } else if ([fontValue respondsToSelector:@selector(integerValue)]) {
            fontIndex = [fontValue integerValue];
        }
        [defaults setInteger:MAX(0, MIN(1, fontIndex)) forKey:SonoraSettingsFontKey];

        id artworkStyleValue = settings[@"artworkStyle"];
        NSInteger artworkIndex = 1;
        if ([artworkStyleValue isKindOfClass:NSString.class]) {
            artworkIndex = [((NSString *)artworkStyleValue).lowercaseString isEqualToString:@"square"] ? 0 : 1;
        } else if ([artworkStyleValue respondsToSelector:@selector(integerValue)]) {
            artworkIndex = [artworkStyleValue integerValue];
        }
        [defaults setInteger:MAX(0, MIN(1, artworkIndex)) forKey:SonoraSettingsArtworkStyleKey];

        id accentValue = settings[@"accentHex"];
        if ([accentValue isKindOfClass:NSString.class] && ((NSString *)accentValue).length > 0) {
            [defaults setObject:accentValue forKey:SonoraSettingsAccentHexKey];
            [defaults removeObjectForKey:SonoraSettingsLegacyAccentColorKey];
        }

        id preserveValue = settings[@"preservePlayerModes"];
        if ([preserveValue respondsToSelector:@selector(boolValue)]) {
            [defaults setBool:[preserveValue boolValue] forKey:SonoraSettingsPreservePlayerModesKey];
        }

        id gapValue = settings[@"trackGapSeconds"];
        if ([gapValue respondsToSelector:@selector(doubleValue)]) {
            [defaults setDouble:[self nearestTrackGapValueForValue:[gapValue doubleValue]] forKey:SonoraSettingsTrackGapKey];
        }

        id maxStorageValue = settings[@"maxStorageMb"];
        if (maxStorageValue == nil) {
            maxStorageValue = settings[@"maxStorageMB"];
        }
        if ([maxStorageValue respondsToSelector:@selector(integerValue)]) {
            [defaults setInteger:[self nearestMaxStorageValueForValue:[maxStorageValue integerValue]] forKey:SonoraSettingsMaxStorageMBKey];
        }

        id cacheOnlinePlaylistTracksValue = settings[@"cacheOnlinePlaylistTracks"];
        if ([cacheOnlinePlaylistTracksValue respondsToSelector:@selector(boolValue)]) {
            [defaults setBool:[cacheOnlinePlaylistTracksValue boolValue] forKey:SonoraSettingsCacheOnlinePlaylistTracksKey];
        }

        id onlinePlaylistCacheMaxValue = settings[@"onlinePlaylistCacheMaxMb"];
        if (onlinePlaylistCacheMaxValue == nil) {
            onlinePlaylistCacheMaxValue = settings[@"onlinePlaylistCacheMaxMB"];
        }
        if ([onlinePlaylistCacheMaxValue respondsToSelector:@selector(integerValue)]) {
            [defaults setInteger:[self nearestMaxStorageValueForValue:[onlinePlaylistCacheMaxValue integerValue]]
                         forKey:SonoraSettingsOnlinePlaylistCacheMaxMBKey];
        }

        id artworkEqualizerValue = settings[@"artworkEqualizer"];
        if ([artworkEqualizerValue respondsToSelector:@selector(boolValue)]) {
            [defaults setBool:[artworkEqualizerValue boolValue] forKey:SonoraSettingsArtworkEqualizerKey];
        }
    }

    [self loadSettingsValues];
    [self refreshStorageUsage];
    [self notifyPlayerSettingsChanged];
    [NSNotificationCenter.defaultCenter postNotificationName:SonoraPlaylistsDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter postNotificationName:SonoraFavoritesDidChangeNotification object:nil];
    return YES;
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
