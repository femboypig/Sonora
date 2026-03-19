//
//  SonoraCells.m
//  Sonora
//

#import "SonoraCells.h"
#import "SonoraMusicUIHelpers.h"

static UIColor *SonoraCellsDefaultAccentColor(void) {
    return [UIColor colorWithRed:1.0 green:0.83 blue:0.08 alpha:1.0];
}

static UIColor *SonoraCellsLegacyAccentColorForIndex(NSInteger raw) {
    switch (raw) {
        case 1:
            return [UIColor colorWithRed:0.31 green:0.64 blue:1.0 alpha:1.0];
        case 2:
            return [UIColor colorWithRed:0.22 green:0.83 blue:0.62 alpha:1.0];
        case 3:
            return [UIColor colorWithRed:1.0 green:0.48 blue:0.40 alpha:1.0];
        case 0:
        default:
            return SonoraCellsDefaultAccentColor();
    }
}

static UIColor *SonoraCellsColorFromHexString(NSString *hexString) {
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

static UIColor *SonoraCellsAccentColor(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    UIColor *fromHex = SonoraCellsColorFromHexString([defaults stringForKey:@"sonora.settings.accentHex"]);
    if (fromHex != nil) {
        return fromHex;
    }
    return SonoraCellsLegacyAccentColorForIndex([defaults integerForKey:@"sonora.settings.accentColor"]);
}

@interface SonoraTrackCell ()

@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *durationLabel;

@end

@implementation SonoraTrackCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.selectionStyle = UITableViewCellSelectionStyleDefault;
    self.preservesSuperviewLayoutMargins = NO;
    self.separatorInset = UIEdgeInsetsMake(0.0, 60.0, 0.0, 12.0);
    self.layoutMargins = UIEdgeInsetsZero;
    self.backgroundColor = SonoraAppBackgroundColor();
    self.contentView.backgroundColor = SonoraAppBackgroundColor();

    UIImageView *coverView = [[UIImageView alloc] init];
    coverView.translatesAutoresizingMaskIntoConstraints = NO;
    coverView.layer.cornerRadius = 0.0;
    coverView.layer.masksToBounds = YES;
    coverView.contentMode = UIViewContentModeScaleAspectFill;
    self.coverView = coverView;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
    titleLabel.numberOfLines = 1;
    self.titleLabel = titleLabel;

    UILabel *durationLabel = [[UILabel alloc] init];
    durationLabel.translatesAutoresizingMaskIntoConstraints = NO;
    durationLabel.font = [UIFont monospacedDigitSystemFontOfSize:12.0 weight:UIFontWeightSemibold];
    durationLabel.textColor = UIColor.secondaryLabelColor;
    durationLabel.textAlignment = NSTextAlignmentRight;
    self.durationLabel = durationLabel;

    [self.contentView addSubview:coverView];
    [self.contentView addSubview:titleLabel];
    [self.contentView addSubview:durationLabel];

    [NSLayoutConstraint activateConstraints:@[
        [coverView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12.0],
        [coverView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [coverView.widthAnchor constraintEqualToConstant:40.0],
        [coverView.heightAnchor constraintEqualToConstant:40.0],

        [durationLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12.0],
        [durationLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [durationLabel.widthAnchor constraintGreaterThanOrEqualToConstant:44.0],

        [titleLabel.leadingAnchor constraintEqualToAnchor:coverView.trailingAnchor constant:10.0],
        [titleLabel.trailingAnchor constraintEqualToAnchor:durationLabel.leadingAnchor constant:-8.0],
        [titleLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor]
    ]];
}

- (void)configureWithTrack:(SonoraTrack *)track isCurrent:(BOOL)isCurrent {
    [self configureWithTrack:track isCurrent:isCurrent showsPlaybackIndicator:NO];
}

- (void)configureWithTrack:(SonoraTrack *)track
                 isCurrent:(BOOL)isCurrent
    showsPlaybackIndicator:(BOOL)showsPlaybackIndicator {
    self.titleLabel.text = track.title;
    self.durationLabel.text = SonoraFormatDuration(track.duration);

    if (showsPlaybackIndicator && isCurrent) {
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:17.0
                                                                                               weight:UIImageSymbolWeightSemibold];
        self.coverView.image = [UIImage systemImageNamed:@"pause.fill" withConfiguration:config];
        self.coverView.tintColor = UIColor.labelColor;
        self.coverView.backgroundColor = UIColor.clearColor;
        self.coverView.contentMode = UIViewContentModeCenter;
        self.titleLabel.textColor = UIColor.labelColor;
        return;
    }

    self.coverView.image = track.artwork;
    self.coverView.tintColor = nil;
    self.coverView.backgroundColor = UIColor.clearColor;
    self.coverView.contentMode = UIViewContentModeScaleAspectFill;
    self.titleLabel.textColor = isCurrent ? SonoraCellsAccentColor() : UIColor.labelColor;
}

@end

@interface SonoraPlaylistCell ()

@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) NSLayoutConstraint *nameTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *nameCenterYConstraint;

@end

@implementation SonoraPlaylistCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.selectionStyle = UITableViewCellSelectionStyleDefault;
    self.preservesSuperviewLayoutMargins = NO;
    self.separatorInset = UIEdgeInsetsMake(0.0, 62.0, 0.0, 12.0);
    self.layoutMargins = UIEdgeInsetsZero;
    self.backgroundColor = SonoraAppBackgroundColor();
    self.contentView.backgroundColor = SonoraAppBackgroundColor();

    UIImageView *coverView = [[UIImageView alloc] init];
    coverView.translatesAutoresizingMaskIntoConstraints = NO;
    coverView.layer.cornerRadius = 0.0;
    coverView.layer.masksToBounds = YES;
    coverView.contentMode = UIViewContentModeScaleAspectFill;
    self.coverView = coverView;

    UILabel *nameLabel = [[UILabel alloc] init];
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    nameLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    nameLabel.textColor = UIColor.labelColor;
    nameLabel.numberOfLines = 1;
    self.nameLabel = nameLabel;

    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold];
    subtitleLabel.textColor = UIColor.secondaryLabelColor;
    subtitleLabel.numberOfLines = 1;
    self.subtitleLabel = subtitleLabel;

    [self.contentView addSubview:coverView];
    [self.contentView addSubview:nameLabel];
    [self.contentView addSubview:subtitleLabel];

    NSLayoutConstraint *nameTopConstraint = [nameLabel.topAnchor constraintEqualToAnchor:coverView.topAnchor constant:3.0];
    NSLayoutConstraint *nameCenterYConstraint = [nameLabel.centerYAnchor constraintEqualToAnchor:coverView.centerYAnchor];
    nameCenterYConstraint.active = NO;
    self.nameTopConstraint = nameTopConstraint;
    self.nameCenterYConstraint = nameCenterYConstraint;

    [NSLayoutConstraint activateConstraints:@[
        [coverView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12.0],
        [coverView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [coverView.widthAnchor constraintEqualToConstant:42.0],
        [coverView.heightAnchor constraintEqualToConstant:42.0],

        [nameLabel.leadingAnchor constraintEqualToAnchor:coverView.trailingAnchor constant:10.0],
        [nameLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12.0],
        nameTopConstraint,
        nameCenterYConstraint,

        [subtitleLabel.leadingAnchor constraintEqualToAnchor:nameLabel.leadingAnchor],
        [subtitleLabel.trailingAnchor constraintEqualToAnchor:nameLabel.trailingAnchor],
        [subtitleLabel.bottomAnchor constraintEqualToAnchor:coverView.bottomAnchor constant:-3.0]
    ]];
}

- (void)configureWithName:(NSString *)name subtitle:(NSString *)subtitle artwork:(UIImage *)artwork {
    self.nameLabel.text = name;
    BOOL hasSubtitle = (subtitle.length > 0);
    self.subtitleLabel.text = hasSubtitle ? subtitle : @"";
    self.subtitleLabel.hidden = !hasSubtitle;
    self.nameTopConstraint.active = hasSubtitle;
    self.nameCenterYConstraint.active = !hasSubtitle;
    self.coverView.image = artwork;
}

@end

@interface SonoraTrackGridCell ()

@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) CAGradientLayer *overlayGradient;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *durationLabel;

@end

@implementation SonoraTrackGridCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.contentView.clipsToBounds = YES;
    self.contentView.layer.cornerRadius = 6.0;

    UIImageView *coverView = [[UIImageView alloc] initWithFrame:self.contentView.bounds];
    coverView.translatesAutoresizingMaskIntoConstraints = NO;
    coverView.contentMode = UIViewContentModeScaleAspectFill;
    coverView.clipsToBounds = YES;
    self.coverView = coverView;

    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.colors = @[
        (__bridge id)[UIColor clearColor].CGColor,
        (__bridge id)[UIColor colorWithWhite:0.0 alpha:0.72].CGColor
    ];
    gradient.locations = @[@0.45, @1.0];
    gradient.startPoint = CGPointMake(0.5, 0.0);
    gradient.endPoint = CGPointMake(0.5, 1.0);
    [coverView.layer addSublayer:gradient];
    self.overlayGradient = gradient;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold];
    titleLabel.textColor = UIColor.whiteColor;
    titleLabel.numberOfLines = 1;
    self.titleLabel = titleLabel;

    UILabel *durationLabel = [[UILabel alloc] init];
    durationLabel.translatesAutoresizingMaskIntoConstraints = NO;
    durationLabel.font = [UIFont monospacedDigitSystemFontOfSize:10.0 weight:UIFontWeightSemibold];
    durationLabel.textColor = UIColor.whiteColor;
    durationLabel.textAlignment = NSTextAlignmentRight;
    self.durationLabel = durationLabel;

    [self.contentView addSubview:coverView];
    [self.contentView addSubview:titleLabel];
    [self.contentView addSubview:durationLabel];

    [NSLayoutConstraint activateConstraints:@[
        [coverView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
        [coverView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [coverView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [coverView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],

        [titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:6.0],
        [titleLabel.trailingAnchor constraintEqualToAnchor:durationLabel.leadingAnchor constant:-4.0],
        [titleLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-5.0],

        [durationLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-6.0],
        [durationLabel.bottomAnchor constraintEqualToAnchor:titleLabel.bottomAnchor],
        [durationLabel.widthAnchor constraintGreaterThanOrEqualToConstant:32.0]
    ]];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.overlayGradient.frame = self.contentView.bounds;
}

- (void)configureWithTrack:(SonoraTrack *)track isCurrent:(BOOL)isCurrent {
    self.coverView.image = track.artwork;
    self.titleLabel.text = track.title;
    self.durationLabel.text = SonoraFormatDuration(track.duration);

    self.contentView.layer.borderWidth = isCurrent ? 2.0 : 0.0;
    self.contentView.layer.borderColor = isCurrent ? SonoraCellsAccentColor().CGColor : UIColor.clearColor.CGColor;
}

@end

@interface SonoraPlaylistGridCell ()

@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) CAGradientLayer *overlayGradient;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;

@end

@implementation SonoraPlaylistGridCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.contentView.clipsToBounds = YES;
    self.contentView.layer.cornerRadius = 6.0;

    UIImageView *coverView = [[UIImageView alloc] initWithFrame:self.contentView.bounds];
    coverView.translatesAutoresizingMaskIntoConstraints = NO;
    coverView.contentMode = UIViewContentModeScaleAspectFill;
    coverView.clipsToBounds = YES;
    self.coverView = coverView;

    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.colors = @[
        (__bridge id)[UIColor clearColor].CGColor,
        (__bridge id)[UIColor colorWithWhite:0.0 alpha:0.74].CGColor
    ];
    gradient.locations = @[@0.42, @1.0];
    gradient.startPoint = CGPointMake(0.5, 0.0);
    gradient.endPoint = CGPointMake(0.5, 1.0);
    [coverView.layer addSublayer:gradient];
    self.overlayGradient = gradient;

    UILabel *nameLabel = [[UILabel alloc] init];
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    nameLabel.textColor = UIColor.whiteColor;
    nameLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightBold];
    nameLabel.numberOfLines = 1;
    self.nameLabel = nameLabel;

    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.92];
    subtitleLabel.font = [UIFont systemFontOfSize:9.5 weight:UIFontWeightSemibold];
    subtitleLabel.numberOfLines = 1;
    self.subtitleLabel = subtitleLabel;

    [self.contentView addSubview:coverView];
    [self.contentView addSubview:nameLabel];
    [self.contentView addSubview:subtitleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [coverView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
        [coverView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [coverView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [coverView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],

        [subtitleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:6.0],
        [subtitleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-6.0],
        [subtitleLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-5.0],

        [nameLabel.leadingAnchor constraintEqualToAnchor:subtitleLabel.leadingAnchor],
        [nameLabel.trailingAnchor constraintEqualToAnchor:subtitleLabel.trailingAnchor],
        [nameLabel.bottomAnchor constraintEqualToAnchor:subtitleLabel.topAnchor constant:-1.0]
    ]];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.overlayGradient.frame = self.contentView.bounds;
}

- (void)configureWithName:(NSString *)name subtitle:(NSString *)subtitle artwork:(UIImage *)artwork {
    self.coverView.image = artwork;
    self.nameLabel.text = name;
    self.subtitleLabel.text = subtitle;
}

@end
