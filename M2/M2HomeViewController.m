//
//  M2HomeViewController.m
//  M2
//

#import "M2HomeViewController.h"

#import <math.h>
#import <QuartzCore/QuartzCore.h>

#import "M2Cells.h"
#import "M2HistoryViewController.h"
#import "M2Services.h"

static NSString * const M2HomeRecommendationCellReuseID = @"M2HomeRecommendationCell";
static NSString * const M2HomeHeroRecommendationCellReuseID = @"M2HomeHeroRecommendationCell";
static NSString * const M2HomeLastAddedCellReuseID = @"M2HomeLastAddedCell";
static NSString * const M2HomeAlbumCellReuseID = @"M2HomeAlbumCell";
static NSString * const M2HomeSectionHeaderReuseID = @"M2HomeSectionHeader";
static NSString * const M2HomeSectionHeaderKind = @"M2HomeSectionHeaderKind";

typedef NS_ENUM(NSInteger, M2HomeSectionType) {
    M2HomeSectionTypeForYou = 0,
    M2HomeSectionTypeYouNeedThis = 1,
    M2HomeSectionTypeFreshCuts = 2,
};

static UIFont *M2YSMusicFont(CGFloat size) {
    UIFont *font = [UIFont fontWithName:@"YSMusic-HeadlineBold" size:size];
    if (font != nil) {
        return font;
    }
    return [UIFont boldSystemFontOfSize:size];
}

static UIFont *M2NotoSerifBoldFont(CGFloat size) {
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

static UIColor *M2HomeAccentYellowColor(void) {
    return [UIColor colorWithRed:1.0 green:0.83 blue:0.08 alpha:1.0];
}

static NSDate *M2TrackModifiedDate(M2Track *track) {
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

static NSString *M2DisplayTrackTitle(M2Track *track) {
    if (track.title.length > 0) {
        return track.title;
    }
    if (track.fileName.length > 0) {
        return track.fileName.stringByDeletingPathExtension;
    }
    return @"Unknown track";
}

static NSString *M2DisplayTrackArtist(M2Track *track) {
    if (track.artist.length > 0) {
        return track.artist;
    }
    return @"";
}

static NSString *M2NormalizedArtistText(NSString *artist) {
    NSString *value = [artist stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return value.lowercaseString ?: @"";
}

static UIColor *M2BlendColor(UIColor *from, UIColor *to, CGFloat ratio) {
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

static NSArray<UIColor *> *M2WavePaletteFromImage(UIImage *image) {
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
    } M2WaveBucket;
    M2WaveBucket buckets[10] = {0};

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

static NSArray<UIColor *> *M2ResolvedWavePalette(UIImage * _Nullable image) {
    NSArray<UIColor *> *palette = M2WavePaletteFromImage(image);
    if (palette.count >= 4) {
        return palette;
    }

    UIColor *accent = [M2ArtworkAccentColorService dominantAccentColorForImage:image
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
        M2BlendColor(accent, UIColor.whiteColor, 0.24),
        M2BlendColor(accent, warm, 0.20),
        M2BlendColor(accent, soft, 0.18)
    ];
}

static double M2HomeStabilizedScore(NSInteger playCount, NSInteger skipCount, double rawScore) {
    double plays = MAX((double)playCount, 0.0);
    double skips = MAX((double)skipCount, 0.0);
    double interactions = plays + skips;
    double confidence = 1.0 - exp(-interactions / 4.5);
    double clampedRaw = MIN(MAX(rawScore, 0.0), 1.0);
    double smoothed = (clampedRaw * confidence) + (0.52 * (1.0 - confidence));
    double skipPenalty = (skips / (interactions + 1.0)) * 0.20;
    return MIN(MAX(smoothed - skipPenalty, 0.0), 1.0);
}

static double M2HomeBestTrackWeight(NSDictionary<NSString *, NSNumber *> *metrics, BOOL isFavorite) {
    NSInteger playCount = MAX([metrics[@"playCount"] integerValue], 0);
    NSInteger skipCount = MAX([metrics[@"skipCount"] integerValue], 0);
    double stabilized = M2HomeStabilizedScore(playCount, skipCount, [metrics[@"score"] doubleValue]);
    double playBoost = log1p((double)playCount) * 0.42;
    double skipPenalty = log1p((double)skipCount) * 0.30;
    double momentum = MIN(MAX(((double)playCount - (double)skipCount) / 20.0, -0.25), 0.35);
    double favoriteBoost = isFavorite ? 0.48 : 0.0;
    return MAX(0.05, 0.24 + (stabilized * 3.0) + playBoost - skipPenalty + momentum + favoriteBoost);
}

static NSString *M2HomeSleepTimerRemainingString(NSTimeInterval interval) {
    NSInteger totalSeconds = (NSInteger)llround(MAX(0.0, interval));
    NSInteger hours = totalSeconds / 3600;
    NSInteger minutes = (totalSeconds % 3600) / 60;
    NSInteger seconds = totalSeconds % 60;

    if (hours > 0) {
        return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)hours, (long)minutes, (long)seconds];
    }
    return [NSString stringWithFormat:@"%ld:%02ld", (long)minutes, (long)seconds];
}

static NSTimeInterval M2HomeSleepTimerDurationFromInput(NSString *input) {
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

static void M2ShuffleMutableArray(NSMutableArray *array) {
    if (array.count <= 1) {
        return;
    }

    for (NSInteger idx = array.count - 1; idx > 0; idx -= 1) {
        u_int32_t swapIdx = arc4random_uniform((u_int32_t)(idx + 1));
        [array exchangeObjectAtIndex:idx withObjectAtIndex:(NSUInteger)swapIdx];
    }
}

static UIViewController * _Nullable M2InstantiatePlayerViewController(void) {
    Class playerClass = NSClassFromString(@"M2PlayerViewController");
    if (playerClass == Nil || ![playerClass isSubclassOfClass:UIViewController.class]) {
        return nil;
    }
    return [[playerClass alloc] init];
}

@interface M2HomeAlbumItem : NSObject

@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) UIImage *artwork;
@property (nonatomic, strong) NSDate *latestDate;
@property (nonatomic, assign) NSInteger trackCount;
@property (nonatomic, copy) NSArray<M2Track *> *tracks;

@end

@implementation M2HomeAlbumItem
@end

@interface M2HomeRecommendationCell : UICollectionViewCell

- (void)configureWithTrack:(M2Track *)track;

@end

@interface M2HomeRecommendationCell ()

@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *artistLabel;

@end

@implementation M2HomeRecommendationCell

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

- (void)configureWithTrack:(M2Track *)track {
    self.coverView.image = track.artwork;
    self.titleLabel.text = M2DisplayTrackTitle(track);
    NSString *artist = M2DisplayTrackArtist(track);
    self.artistLabel.text = artist;
    self.artistLabel.hidden = (artist.length == 0);
}

@end

@interface M2WaveAnimatedBackgroundView : UIView

- (void)applyPalette:(NSArray<UIColor *> *)palette animated:(BOOL)animated;
- (void)setPlaying:(BOOL)playing;
- (void)setPulseSeedWithTrackIdentifier:(NSString * _Nullable)identifier;

@end

@interface M2WaveAnimatedBackgroundView ()

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

@implementation M2WaveAnimatedBackgroundView

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
        [layer addAnimation:scale forKey:[NSString stringWithFormat:@"m2_wave_scale_%lu", (unsigned long)idx]];

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
        [layer addAnimation:position forKey:[NSString stringWithFormat:@"m2_wave_position_%lu", (unsigned long)idx]];
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
        M2PlaybackManager *playback = M2PlaybackManager.sharedManager;
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
    NSArray<UIColor *> *resolved = (palette.count >= 4) ? palette : M2ResolvedWavePalette(nil);

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
        [self.baseGradientLayer addAnimation:baseAnim forKey:@"m2_wave_base_colors"];
    }
    self.baseGradientLayer.colors = baseColors;

    UIColor *pulseColor = M2BlendColor(resolved[3], UIColor.whiteColor, 0.26);
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
        [self.pulseLayer addAnimation:pulseAnim forKey:@"m2_wave_pulse_colors"];
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
            [layer addAnimation:anim forKey:[NSString stringWithFormat:@"m2_wave_blob_colors_%lu", (unsigned long)idx]];
        }
        layer.colors = colors;
    }];
}

@end

@interface M2HomeHeroRecommendationCell : UICollectionViewCell

@property (nonatomic, copy, nullable) dispatch_block_t playHandler;
- (void)configureWithTrack:(M2Track *)track;

@end

@interface M2HomeHeroRecommendationCell ()

@property (nonatomic, strong) M2WaveAnimatedBackgroundView *waveBackgroundView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, assign) BOOL playing;

@end

@implementation M2HomeHeroRecommendationCell

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

    M2WaveAnimatedBackgroundView *waveBackgroundView = [[M2WaveAnimatedBackgroundView alloc] init];
    waveBackgroundView.translatesAutoresizingMaskIntoConstraints = NO;
    self.waveBackgroundView = waveBackgroundView;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = M2NotoSerifBoldFont(30.0);
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

- (void)configureWithTrack:(M2Track *)track {
    NSArray<UIColor *> *palette = M2ResolvedWavePalette(track.artwork);
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

@interface M2HomeLastAddedCell : UICollectionViewCell

- (void)configureWithTrack:(M2Track *)track;

@end

@interface M2HomeLastAddedCell ()

@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *artistLabel;

@end

@implementation M2HomeLastAddedCell

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

- (void)configureWithTrack:(M2Track *)track {
    UIColor *accentColor = [M2ArtworkAccentColorService dominantAccentColorForImage:track.artwork
                                                                            fallback:UIColor.systemGrayColor];
    self.contentView.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
        CGFloat alpha = (trait.userInterfaceStyle == UIUserInterfaceStyleDark) ? 0.19 : 0.11;
        return [accentColor colorWithAlphaComponent:alpha];
    }];

    self.coverView.image = track.artwork;
    self.titleLabel.text = M2DisplayTrackTitle(track);
    NSString *artist = M2DisplayTrackArtist(track);
    self.artistLabel.text = artist;
    self.artistLabel.hidden = (artist.length == 0);
}

@end

@interface M2HomeAlbumCell : UICollectionViewCell

- (void)configureWithAlbumItem:(M2HomeAlbumItem *)albumItem;

@end

@interface M2HomeAlbumCell ()

@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *titleLabel;

@end

@implementation M2HomeAlbumCell

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

- (void)configureWithAlbumItem:(M2HomeAlbumItem *)albumItem {
    self.coverView.image = albumItem.artwork;
    self.titleLabel.text = albumItem.title;
}

@end

@interface M2HomeSectionHeaderView : UICollectionReusableView

- (void)configureWithTitle:(NSString *)title;

@end

@interface M2HomeSectionHeaderView ()

@property (nonatomic, strong) UILabel *titleLabel;

@end

@implementation M2HomeSectionHeaderView

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
    titleLabel.font = M2NotoSerifBoldFont(24.0);
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

@interface M2HomeAlbumDetailViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

- (instancetype)initWithAlbumTitle:(NSString *)albumTitle tracks:(NSArray<M2Track *> *)tracks;

@end

@interface M2HomeAlbumDetailViewController ()

@property (nonatomic, copy) NSString *albumTitle;
@property (nonatomic, copy) NSArray<M2Track *> *tracks;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UIButton *shuffleButton;
@property (nonatomic, strong) UIButton *sleepControlButton;

@end

@implementation M2HomeAlbumDetailViewController

- (instancetype)initWithAlbumTitle:(NSString *)albumTitle tracks:(NSArray<M2Track *> *)tracks {
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
                                               name:M2PlaybackStateDidChangeNotification
                                             object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handleSleepTimerChanged)
                                               name:M2SleepTimerDidChangeNotification
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
    [tableView registerClass:M2TrackCell.class forCellReuseIdentifier:@"M2HomeAlbumTrackCell"];

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
    nameLabel.font = M2YSMusicFont(28.0);
    nameLabel.textColor = UIColor.labelColor;
    self.nameLabel = nameLabel;

    CGFloat playSize = 66.0;
    CGFloat shuffleSize = 46.0;
    CGFloat sleepSize = 46.0;
    CGFloat controlsY = 276.0;

    UIButton *playButton = [UIButton buttonWithType:UIButtonTypeSystem];
    playButton.frame = CGRectMake((totalWidth - playSize) * 0.5, controlsY, playSize, playSize);
    playButton.backgroundColor = M2HomeAccentYellowColor();
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

    UIColor *playColor = [M2ArtworkAccentColorService dominantAccentColorForImage:cover
                                                                          fallback:M2HomeAccentYellowColor()];
    self.playButton.backgroundColor = playColor ?: M2HomeAccentYellowColor();
}

- (BOOL)isCurrentQueueMatchingAlbum {
    NSArray<M2Track *> *queue = M2PlaybackManager.sharedManager.currentQueue;
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

    M2PlaybackManager *playback = M2PlaybackManager.sharedManager;
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

    BOOL isActive = M2SleepTimerManager.sharedManager.isActive;
    NSString *symbol = isActive ? @"moon.zzz.fill" : @"moon.zzz";
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:21.0
                                                                                          weight:UIImageSymbolWeightSemibold];
    [self.sleepControlButton setImage:[UIImage systemImageNamed:symbol withConfiguration:config] forState:UIControlStateNormal];
    self.sleepControlButton.tintColor = isActive ? M2HomeAccentYellowColor() : UIColor.labelColor;
    self.sleepControlButton.accessibilityLabel = isActive
    ? [NSString stringWithFormat:@"Sleep timer active, %@ remaining",
       M2HomeSleepTimerRemainingString(M2SleepTimerManager.sharedManager.remainingTime)]
    : @"Sleep timer";
}

- (void)presentCustomSleepTimerAlert {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Custom Sleep Timer"
                                                                   message:@"Enter minutes (e.g. 25) or h:mm (e.g. 1:30)."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"25 or 1:30";
        textField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        NSTimeInterval remaining = M2SleepTimerManager.sharedManager.remainingTime;
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
        NSTimeInterval duration = M2HomeSleepTimerDurationFromInput(rawValue);
        if (duration <= 0.0) {
            UIAlertController *invalid = [UIAlertController alertControllerWithTitle:@"Invalid Time"
                                                                              message:@"Use minutes (25) or h:mm (1:30). Max is 24 hours."
                                                                       preferredStyle:UIAlertControllerStyleAlert];
            [invalid addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:invalid animated:YES completion:nil];
            return;
        }

        [M2SleepTimerManager.sharedManager startWithDuration:duration];
        [self updateSleepTimerButton];
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)sleepTimerTapped {
    M2SleepTimerManager *sleepTimer = M2SleepTimerManager.sharedManager;
    NSString *message = sleepTimer.isActive
    ? [NSString stringWithFormat:@"Will stop playback in %@.", M2HomeSleepTimerRemainingString(sleepTimer.remainingTime)]
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
            [M2SleepTimerManager.sharedManager startWithDuration:durationValue.doubleValue];
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
            [M2SleepTimerManager.sharedManager cancel];
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
    UIViewController *player = M2InstantiatePlayerViewController();
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

    M2PlaybackManager *playback = M2PlaybackManager.sharedManager;
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
        [M2PlaybackManager.sharedManager playTracks:self.tracks startIndex:randomStart];
        [M2PlaybackManager.sharedManager setShuffleEnabled:YES];
    });
}

- (void)playTracksStartingAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.tracks.count) {
        return;
    }

    [self openPlayer];
    dispatch_async(dispatch_get_main_queue(), ^{
        [M2PlaybackManager.sharedManager setShuffleEnabled:NO];
        [M2PlaybackManager.sharedManager playTracks:self.tracks startIndex:index];
    });
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return self.tracks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    M2TrackCell *cell = [tableView dequeueReusableCellWithIdentifier:@"M2HomeAlbumTrackCell" forIndexPath:indexPath];
    if (indexPath.row >= self.tracks.count) {
        return cell;
    }

    M2Track *track = self.tracks[indexPath.row];
    M2PlaybackManager *playback = M2PlaybackManager.sharedManager;
    M2Track *currentTrack = playback.currentTrack;
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

    M2Track *selectedTrack = self.tracks[indexPath.row];
    M2Track *currentTrack = M2PlaybackManager.sharedManager.currentTrack;
    BOOL sameTrack = (currentTrack != nil && [currentTrack.identifier isEqualToString:selectedTrack.identifier]);

    if (sameTrack && [self isCurrentQueueMatchingAlbum]) {
        [self openPlayer];
        return;
    }

    [self playTracksStartingAtIndex:indexPath.row];
}

@end

@interface M2HomeViewController () <UICollectionViewDataSource, UICollectionViewDelegate>

@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, copy) NSArray<M2Track *> *allTracks;
@property (nonatomic, copy) NSArray<M2Track *> *recommendationTracks;
@property (nonatomic, copy) NSArray<M2Track *> *needThisTracks;
@property (nonatomic, copy) NSArray<M2Track *> *freshTracks;
@property (nonatomic, copy) NSString *lastForYouTopTrackID;
@property (nonatomic, copy) NSString *forYouSelectedTrackID;
@property (nonatomic, assign) NSInteger forYouSelectionVisit;
@property (nonatomic, assign) NSInteger homeVisitCount;

@end

@implementation M2HomeViewController

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
                                               name:M2FavoritesDidChangeNotification
                                             object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handlePlaybackStateChanged)
                                               name:M2PlaybackStateDidChangeNotification
                                             object:nil];
    self.forYouSelectionVisit = NSIntegerMin;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)handlePlaybackStateChanged {
    if (self.collectionView == nil) {
        return;
    }
    NSIndexSet *heroSection = [NSIndexSet indexSetWithIndex:(NSUInteger)M2HomeSectionTypeForYou];
    [self.collectionView reloadSections:heroSection];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.homeVisitCount += 1;
    [self reloadHomeContent];
}

- (void)setupNavigationBar {
    self.title = nil;
    self.navigationItem.title = nil;
    self.navigationItem.titleView = nil;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"Home";
    titleLabel.textColor = UIColor.labelColor;
    titleLabel.font = M2YSMusicFont(30.0);
    [titleLabel sizeToFit];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:titleLabel];

    UIBarButtonItem *clockItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"clock"]
                                                                   style:UIBarButtonItemStylePlain
                                                                  target:self
                                                                  action:@selector(openHistoryTapped)];
    self.navigationItem.rightBarButtonItems = @[clockItem];
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

    [collectionView registerClass:M2HomeRecommendationCell.class forCellWithReuseIdentifier:M2HomeRecommendationCellReuseID];
    [collectionView registerClass:M2HomeHeroRecommendationCell.class forCellWithReuseIdentifier:M2HomeHeroRecommendationCellReuseID];
    [collectionView registerClass:M2HomeLastAddedCell.class forCellWithReuseIdentifier:M2HomeLastAddedCellReuseID];
    [collectionView registerClass:M2HomeAlbumCell.class forCellWithReuseIdentifier:M2HomeAlbumCellReuseID];
    [collectionView registerClass:M2HomeSectionHeaderView.class
       forSupplementaryViewOfKind:M2HomeSectionHeaderKind
              withReuseIdentifier:M2HomeSectionHeaderReuseID];

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
                                                           elementKind:M2HomeSectionHeaderKind
                                                           alignment:NSRectAlignmentTop];
    header.contentInsets = NSDirectionalEdgeInsetsMake(0.0, 8.0, 0.0, 18.0);
    return header;
}

- (NSCollectionLayoutSection *)layoutSectionForIndex:(NSInteger)sectionIndex
                                          environment:(id<NSCollectionLayoutEnvironment>)layoutEnvironment {
    CGFloat containerHeight = layoutEnvironment.container.effectiveContentSize.height;
    CGFloat heroHeight = MAX(300.0, MIN(420.0, containerHeight * 0.56));

    switch ((M2HomeSectionType)sectionIndex) {
        case M2HomeSectionTypeForYou:
            return [self forYouSectionLayoutWithHeight:heroHeight];
        case M2HomeSectionTypeYouNeedThis:
            return [self recommendationsSectionLayout];
        case M2HomeSectionTypeFreshCuts:
            return [self lastAddedSectionLayout];
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
    NSArray<M2Track *> *tracks = M2LibraryManager.sharedManager.tracks;
    if (tracks.count == 0) {
        tracks = [M2LibraryManager.sharedManager reloadTracks];
    }

    self.allTracks = tracks ?: @[];
    self.recommendationTracks = [self buildForYouTracksFromTracks:self.allTracks limit:120];
    self.needThisTracks = [self buildRecommendationsFromTracks:self.allTracks limit:12];
    self.freshTracks = [self buildFreshChoiceTracksFromTracks:self.allTracks limit:12];

    [self.collectionView reloadData];
    [self updateEmptyStateIfNeeded];
}

- (NSArray<M2Track *> *)buildForYouTracksFromTracks:(NSArray<M2Track *> *)tracks limit:(NSUInteger)limit {
    if (tracks.count == 0 || limit == 0) {
        return @[];
    }

    NSMutableArray<NSString *> *trackIDs = [NSMutableArray arrayWithCapacity:tracks.count];
    for (M2Track *track in tracks) {
        if (track.identifier.length > 0) {
            [trackIDs addObject:track.identifier];
        }
    }
    NSDictionary<NSString *, NSDictionary<NSString *, NSNumber *> *> *analyticsByTrackID =
    [M2TrackAnalyticsStore.sharedStore analyticsByTrackIDForTrackIDs:trackIDs];
    NSSet<NSString *> *favoriteTrackIDs = [NSSet setWithArray:M2FavoritesStore.sharedStore.favoriteTrackIDs];

    NSArray<M2Track *> *ranked = [tracks sortedArrayUsingComparator:^NSComparisonResult(M2Track * _Nonnull left,
                                                                                         M2Track * _Nonnull right) {
        NSDictionary<NSString *, NSNumber *> *leftMetrics = analyticsByTrackID[left.identifier] ?: @{};
        NSDictionary<NSString *, NSNumber *> *rightMetrics = analyticsByTrackID[right.identifier] ?: @{};
        double leftWeight = M2HomeBestTrackWeight(leftMetrics, [favoriteTrackIDs containsObject:left.identifier]);
        double rightWeight = M2HomeBestTrackWeight(rightMetrics, [favoriteTrackIDs containsObject:right.identifier]);
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
        return [M2DisplayTrackTitle(left) localizedCaseInsensitiveCompare:M2DisplayTrackTitle(right)];
    }];

    NSMutableArray<M2Track *> *result = [ranked mutableCopy];
    if (result.count == 0) {
        return @[];
    }

    if (self.forYouSelectionVisit != self.homeVisitCount) {
        NSUInteger candidateLimit = MIN((NSUInteger)6, result.count);
        M2Track *selectedTrack = result.firstObject;
        if (candidateLimit > 0) {
            NSInteger visit = self.homeVisitCount;
            if (visit < 0) {
                visit = -visit;
            }
            NSUInteger baseIndex = (NSUInteger)visit % candidateLimit;
            for (NSUInteger step = 0; step < candidateLimit; step += 1) {
                NSUInteger candidateIndex = (baseIndex + step) % candidateLimit;
                M2Track *candidate = result[candidateIndex];
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
        NSUInteger selectedIndex = [result indexOfObjectPassingTest:^BOOL(M2Track * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
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

- (NSArray<M2Track *> *)buildRecommendationsFromTracks:(NSArray<M2Track *> *)tracks limit:(NSUInteger)limit {
    if (tracks.count == 0 || limit == 0) {
        return @[];
    }

    NSSet<NSString *> *favoriteTrackIDs = [NSSet setWithArray:M2FavoritesStore.sharedStore.favoriteTrackIDs];
    NSMutableArray<NSString *> *trackIDs = [NSMutableArray arrayWithCapacity:tracks.count];
    for (M2Track *track in tracks) {
        if (track.identifier.length > 0) {
            [trackIDs addObject:track.identifier];
        }
    }

    NSDictionary<NSString *, NSDictionary<NSString *, NSNumber *> *> *analyticsByTrackID =
    [M2TrackAnalyticsStore.sharedStore analyticsByTrackIDForTrackIDs:trackIDs];
    if (analyticsByTrackID.count == 0 && favoriteTrackIDs.count == 0) {
        NSMutableArray<M2Track *> *shuffled = [tracks mutableCopy];
        M2ShuffleMutableArray(shuffled);
        if (shuffled.count > limit) {
            [shuffled removeObjectsInRange:NSMakeRange(limit, shuffled.count - limit)];
        }
        return [shuffled copy];
    }

    NSMutableDictionary<NSString *, NSNumber *> *weightByTrackID = [NSMutableDictionary dictionaryWithCapacity:tracks.count];
    for (M2Track *track in tracks) {
        NSDictionary<NSString *, NSNumber *> *metrics = analyticsByTrackID[track.identifier] ?: @{};
        BOOL isFavorite = [favoriteTrackIDs containsObject:track.identifier];
        double weight = M2HomeBestTrackWeight(metrics, isFavorite);

        if (track.identifier.length > 0) {
            weightByTrackID[track.identifier] = @(weight);
        }
    }

    NSArray<M2Track *> *rankedTracks = [tracks sortedArrayUsingComparator:^NSComparisonResult(M2Track * _Nonnull left,
                                                                                                M2Track * _Nonnull right) {
        double leftWeight = [weightByTrackID[left.identifier] doubleValue];
        double rightWeight = [weightByTrackID[right.identifier] doubleValue];
        if (leftWeight > rightWeight) {
            return NSOrderedAscending;
        }
        if (leftWeight < rightWeight) {
            return NSOrderedDescending;
        }
        return [M2DisplayTrackTitle(left) localizedCaseInsensitiveCompare:M2DisplayTrackTitle(right)];
    }];

    NSUInteger poolLimit = MIN(rankedTracks.count, MAX((NSInteger)limit * 3, 12));
    NSMutableArray<M2Track *> *pool = [[rankedTracks subarrayWithRange:NSMakeRange(0, poolLimit)] mutableCopy];
    M2ShuffleMutableArray(pool);
    if (pool.count > limit) {
        [pool removeObjectsInRange:NSMakeRange(limit, pool.count - limit)];
    }
    return [pool copy];
}

- (NSArray<M2Track *> *)buildLastAddedTracksFromTracks:(NSArray<M2Track *> *)tracks limit:(NSUInteger)limit {
    if (tracks.count == 0 || limit == 0) {
        return @[];
    }

    NSMutableDictionary<NSString *, NSDate *> *dateByTrackID = [NSMutableDictionary dictionaryWithCapacity:tracks.count];
    for (M2Track *track in tracks) {
        if (track.identifier.length > 0) {
            dateByTrackID[track.identifier] = M2TrackModifiedDate(track);
        }
    }

    NSArray<M2Track *> *sorted = [tracks sortedArrayUsingComparator:^NSComparisonResult(M2Track * _Nonnull left,
                                                                                         M2Track * _Nonnull right) {
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
        return [M2DisplayTrackTitle(left) localizedCaseInsensitiveCompare:M2DisplayTrackTitle(right)];
    }];

    if (sorted.count <= limit) {
        return sorted;
    }
    return [sorted subarrayWithRange:NSMakeRange(0, limit)];
}

- (NSArray<M2Track *> *)buildFreshChoiceTracksFromTracks:(NSArray<M2Track *> *)tracks limit:(NSUInteger)limit {
    if (tracks.count == 0 || limit == 0) {
        return @[];
    }

    NSMutableArray<NSString *> *trackIDs = [NSMutableArray arrayWithCapacity:tracks.count];
    for (M2Track *track in tracks) {
        if (track.identifier.length > 0) {
            [trackIDs addObject:track.identifier];
        }
    }

    NSDictionary<NSString *, NSDictionary<NSString *, NSNumber *> *> *analyticsByTrackID =
    [M2TrackAnalyticsStore.sharedStore analyticsByTrackIDForTrackIDs:trackIDs];
    NSSet<NSString *> *favoriteTrackIDs = [NSSet setWithArray:M2FavoritesStore.sharedStore.favoriteTrackIDs];
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;

    NSArray<M2Track *> *ranked = [tracks sortedArrayUsingComparator:^NSComparisonResult(M2Track * _Nonnull left,
                                                                                         M2Track * _Nonnull right) {
        NSDictionary<NSString *, NSNumber *> *leftMetrics = analyticsByTrackID[left.identifier] ?: @{};
        NSDictionary<NSString *, NSNumber *> *rightMetrics = analyticsByTrackID[right.identifier] ?: @{};

        NSInteger leftPlay = [leftMetrics[@"playCount"] integerValue];
        NSInteger rightPlay = [rightMetrics[@"playCount"] integerValue];
        NSInteger leftSkip = [leftMetrics[@"skipCount"] integerValue];
        NSInteger rightSkip = [rightMetrics[@"skipCount"] integerValue];
        double leftScore = M2HomeStabilizedScore(leftPlay, leftSkip, [leftMetrics[@"score"] doubleValue]);
        double rightScore = M2HomeStabilizedScore(rightPlay, rightSkip, [rightMetrics[@"score"] doubleValue]);

        NSTimeInterval leftAgeDays = MAX(0.0, (now - M2TrackModifiedDate(left).timeIntervalSince1970) / 86400.0);
        NSTimeInterval rightAgeDays = MAX(0.0, (now - M2TrackModifiedDate(right).timeIntervalSince1970) / 86400.0);

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
        return [M2DisplayTrackTitle(left) localizedCaseInsensitiveCompare:M2DisplayTrackTitle(right)];
    }];

    NSUInteger poolLimit = MIN(ranked.count, MAX((NSInteger)limit * 3, 14));
    NSMutableArray<M2Track *> *pool = [[ranked subarrayWithRange:NSMakeRange(0, poolLimit)] mutableCopy];
    M2ShuffleMutableArray(pool);
    if (pool.count > limit) {
        [pool removeObjectsInRange:NSMakeRange(limit, pool.count - limit)];
    }
    return [pool copy];
}

- (NSArray<M2HomeAlbumItem *> *)buildAlbumItemsFromTracks:(NSArray<M2Track *> *)tracks limit:(NSUInteger)limit {
    if (tracks.count == 0 || limit == 0) {
        return @[];
    }

    NSMutableDictionary<NSString *, M2HomeAlbumItem *> *albumsByKey = [NSMutableDictionary dictionary];

    for (M2Track *track in tracks) {
        NSString *rawArtist = [track.artist stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *key = M2NormalizedArtistText(rawArtist ?: @"");
        if (key.length == 0) {
            continue;
        }

        M2HomeAlbumItem *item = albumsByKey[key];
        NSDate *trackDate = M2TrackModifiedDate(track);
        if (item == nil) {
            item = [[M2HomeAlbumItem alloc] init];
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

    NSArray<M2HomeAlbumItem *> *sorted = [albumsByKey.allValues sortedArrayUsingComparator:^NSComparisonResult(M2HomeAlbumItem * _Nonnull left,
                                                                                                                M2HomeAlbumItem * _Nonnull right) {
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
    emptyLabel.text = @"No tracks yet.\nAdd music to On My iPhone/M2/M2.";
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
    M2HistoryViewController *history = [[M2HistoryViewController alloc] init];
    history.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:history animated:YES];
}

- (NSString *)titleForSection:(M2HomeSectionType)sectionType {
    switch (sectionType) {
        case M2HomeSectionTypeForYou:
            return @"My wave";
        case M2HomeSectionTypeYouNeedThis:
            return @"Based on your taste";
        case M2HomeSectionTypeFreshCuts:
            return @"Fresh choice";
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
    switch ((M2HomeSectionType)section) {
        case M2HomeSectionTypeForYou:
            return (self.recommendationTracks.count > 0) ? 1 : 0;
        case M2HomeSectionTypeYouNeedThis:
            return self.needThisTracks.count;
        case M2HomeSectionTypeFreshCuts:
            return self.freshTracks.count;
    }
    return 0;
}

- (BOOL)isWaveQueueActiveForQueue:(NSArray<M2Track *> *)queue
                      currentTrack:(M2Track * _Nullable)currentTrack {
    if (self.recommendationTracks.count == 0 || queue.count == 0 || currentTrack.identifier.length == 0) {
        return NO;
    }

    NSMutableSet<NSString *> *waveIDs = [NSMutableSet setWithCapacity:self.recommendationTracks.count];
    for (M2Track *track in self.recommendationTracks) {
        if (track.identifier.length > 0) {
            [waveIDs addObject:track.identifier];
        }
    }
    if (waveIDs.count == 0 || ![waveIDs containsObject:currentTrack.identifier]) {
        return NO;
    }

    NSUInteger matched = 0;
    for (M2Track *track in queue) {
        if (track.identifier.length > 0 && [waveIDs containsObject:track.identifier]) {
            matched += 1;
        }
    }

    double ratio = (double)matched / (double)MAX((NSUInteger)1, queue.count);
    return ratio >= 0.68;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                            cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    switch ((M2HomeSectionType)indexPath.section) {
        case M2HomeSectionTypeForYou: {
            M2HomeHeroRecommendationCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:M2HomeHeroRecommendationCellReuseID
                                                                                             forIndexPath:indexPath];
            if (self.recommendationTracks.count > 0) {
                NSArray<M2Track *> *queue = M2PlaybackManager.sharedManager.currentQueue;
                M2Track *currentTrack = M2PlaybackManager.sharedManager.currentTrack;
                BOOL isWaveQueue = [self isWaveQueueActiveForQueue:queue currentTrack:currentTrack];
                M2Track *displayTrack = (isWaveQueue && currentTrack != nil) ? currentTrack : self.recommendationTracks.firstObject;
                [cell configureWithTrack:displayTrack];
                cell.playing = isWaveQueue && M2PlaybackManager.sharedManager.isPlaying;
                __weak typeof(self) weakSelf = self;
                cell.playHandler = ^{
                    __strong typeof(weakSelf) strongSelf = weakSelf;
                    if (strongSelf == nil || strongSelf.recommendationTracks.count == 0) {
                        return;
                    }
                    NSArray<M2Track *> *liveQueue = M2PlaybackManager.sharedManager.currentQueue;
                    M2Track *liveTrack = M2PlaybackManager.sharedManager.currentTrack;
                    BOOL liveWaveQueue = [strongSelf isWaveQueueActiveForQueue:liveQueue currentTrack:liveTrack];
                    if (liveWaveQueue && M2PlaybackManager.sharedManager.currentTrack != nil) {
                        [M2PlaybackManager.sharedManager togglePlayPause];
                    } else {
                        [strongSelf playTracks:strongSelf.recommendationTracks startIndex:0];
                    }
                };
            }
            return cell;
        }
        case M2HomeSectionTypeYouNeedThis: {
            M2HomeRecommendationCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:M2HomeRecommendationCellReuseID
                                                                                        forIndexPath:indexPath];
            if (indexPath.item < self.needThisTracks.count) {
                [cell configureWithTrack:self.needThisTracks[indexPath.item]];
            }
            return cell;
        }
        case M2HomeSectionTypeFreshCuts: {
            M2HomeLastAddedCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:M2HomeLastAddedCellReuseID
                                                                                   forIndexPath:indexPath];
            if (indexPath.item < self.freshTracks.count) {
                [cell configureWithTrack:self.freshTracks[indexPath.item]];
            }
            return cell;
        }
    }
    return [UICollectionViewCell new];
}

- (__kindof UICollectionReusableView *)collectionView:(UICollectionView *)collectionView
                            viewForSupplementaryElementOfKind:(NSString *)kind
                                                  atIndexPath:(NSIndexPath *)indexPath {
    if (![kind isEqualToString:M2HomeSectionHeaderKind]) {
        return [UICollectionReusableView new];
    }

    M2HomeSectionHeaderView *header = [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                                                           withReuseIdentifier:M2HomeSectionHeaderReuseID
                                                                                  forIndexPath:indexPath];
    [header configureWithTitle:[self titleForSection:(M2HomeSectionType)indexPath.section]];
    return header;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];

    switch ((M2HomeSectionType)indexPath.section) {
        case M2HomeSectionTypeForYou:
            [self playTracks:self.recommendationTracks startIndex:indexPath.item];
            return;
        case M2HomeSectionTypeYouNeedThis:
            [self playTracks:self.needThisTracks startIndex:indexPath.item];
            return;
        case M2HomeSectionTypeFreshCuts:
            [self playTracks:self.freshTracks startIndex:indexPath.item];
            return;
    }
}

- (NSArray<M2Track *> *)albumDetailTracksForAlbumItem:(M2HomeAlbumItem *)albumItem {
    if (albumItem == nil) {
        return @[];
    }

    NSArray<M2Track *> *seedTracks = albumItem.tracks ?: @[];
    if (seedTracks.count == 0) {
        return @[];
    }

    NSString *targetArtist = M2NormalizedArtistText(albumItem.title ?: @"");
    if (targetArtist.length == 0) {
        for (M2Track *track in seedTracks) {
            NSString *artist = M2NormalizedArtistText(track.artist ?: @"");
            if (artist.length > 0) {
                targetArtist = artist;
                break;
            }
        }
    }

    if (targetArtist.length == 0) {
        return @[];
    }

    NSMutableArray<M2Track *> *matchedTracks = [NSMutableArray array];
    for (M2Track *track in self.allTracks) {
        NSString *artist = M2NormalizedArtistText(track.artist ?: @"");
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

    [matchedTracks sortUsingComparator:^NSComparisonResult(M2Track * _Nonnull left, M2Track * _Nonnull right) {
        NSString *leftTitle = M2DisplayTrackTitle(left);
        NSString *rightTitle = M2DisplayTrackTitle(right);
        return [leftTitle localizedCaseInsensitiveCompare:rightTitle];
    }];
    return matchedTracks;
}

- (void)playTracks:(NSArray<M2Track *> *)tracks startIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)tracks.count) {
        return;
    }

    UIViewController *player = M2InstantiatePlayerViewController();
    if (player != nil && self.navigationController != nil) {
        player.hidesBottomBarWhenPushed = YES;
        [self.navigationController pushViewController:player animated:YES];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [M2PlaybackManager.sharedManager setShuffleEnabled:NO];
        [M2PlaybackManager.sharedManager playTracks:tracks startIndex:index];
    });
}

@end
