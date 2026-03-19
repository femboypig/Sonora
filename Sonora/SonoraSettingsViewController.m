//
//  SonoraSettingsViewController.m
//  Sonora
//

#import "SonoraSettingsViewController.h"

#import <limits.h>
#import <math.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "SonoraMusicUIHelpers.h"
#import "SonoraSettings.h"
#import "SonoraSettingsBackupArchiveService.h"
#import "SonoraSharedPlaylists.h"
#import "SonoraServices.h"

static UIFont *SonoraYSMusicFont(CGFloat size) {
    UIFont *font = [UIFont fontWithName:@"YSMusic-HeadlineBold" size:size];
    if (font != nil) {
        return font;
    }
    return [UIFont boldSystemFontOfSize:size];
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

static NSString * const SonoraSettingsGitHubURLString = @"https://github.com/femboypig/Sonora";
static NSString * const SonoraSettingsGitHubDisplayString = @"femboypig/Sonora";

typedef NS_ENUM(NSInteger, SonoraSettingsColorPickerContext) {
    SonoraSettingsColorPickerContextAccent = 0,
    SonoraSettingsColorPickerContextAppBackground = 1
};

@interface SonoraSettingsViewController () <UIColorPickerViewControllerDelegate, UIDocumentPickerDelegate>

@property (nonatomic, strong) UISegmentedControl *fontControl;
@property (nonatomic, strong) UISegmentedControl *artworkStyleControl;
@property (nonatomic, strong) UISegmentedControl *myWaveLookControl;
@property (nonatomic, strong) UISwitch *playerArtworkBackgroundSwitch;
@property (nonatomic, strong) UISwitch *autoSaveStreamingSongsSwitch;
@property (nonatomic, strong) UISwitch *artworkEqualizerSwitch;
@property (nonatomic, strong) UISwitch *preservePlayerModesSwitch;
@property (nonatomic, strong) UISwitch *onlinePlaylistCacheTracksSwitch;
@property (nonatomic, strong) UILabel *streamingSearchEngineValueLabel;
@property (nonatomic, strong) UILabel *accentColorValueLabel;
@property (nonatomic, strong) UILabel *appBackgroundValueLabel;
@property (nonatomic, strong) UILabel *trackGapValueLabel;
@property (nonatomic, strong) UILabel *usedStorageValueLabel;
@property (nonatomic, strong) UILabel *maxStorageValueLabel;
@property (nonatomic, strong) UILabel *onlinePlaylistCacheUsedValueLabel;
@property (nonatomic, strong) UILabel *onlinePlaylistCacheValueLabel;
@property (nonatomic, strong, nullable) NSURL *pendingBackupExportURL;
@property (nonatomic, strong) SonoraSettingsBackupArchiveService *backupArchiveService;
@property (nonatomic, assign) BOOL backupPickerImportMode;
@property (nonatomic, assign) BOOL backupOperationInProgress;
@property (nonatomic, assign) SonoraSettingsColorPickerContext colorPickerContext;

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
    self.view.backgroundColor = SonoraAppBackgroundColor();
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
    scrollView.backgroundColor = SonoraAppBackgroundColor();

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

    UISwitch *playerArtworkBackgroundSwitch = [[UISwitch alloc] init];
    [playerArtworkBackgroundSwitch addTarget:self action:@selector(playerArtworkBackgroundChanged:) forControlEvents:UIControlEventValueChanged];
    self.playerArtworkBackgroundSwitch = playerArtworkBackgroundSwitch;
    [customizationStack addArrangedSubview:[self switchRowWithTitle:@"Player background from artwork"
                                                           subtitle:@"Use the dominant cover color behind the player"
                                                            control:playerArtworkBackgroundSwitch]];

    UILabel *appBackgroundValue = [self valueLabel];
    self.appBackgroundValueLabel = appBackgroundValue;
    [customizationStack addArrangedSubview:[self selectableValueRowWithTitle:@"App background"
                                                                     subtitle:@"System, artwork-adaptive or custom color"
                                                                   valueLabel:appBackgroundValue
                                                                       action:@selector(selectAppBackgroundTapped)]];

    UILabel *accentColorValue = [self valueLabel];
    self.accentColorValueLabel = accentColorValue;
    [customizationStack addArrangedSubview:[self selectableValueRowWithTitle:@"Accent color"
                                                                     subtitle:@"Any color for active controls"
                                                                   valueLabel:accentColorValue
                                                                       action:@selector(selectAccentColorTapped)]];

    UILabel *streamingSearchEngineValue = [self valueLabel];
    self.streamingSearchEngineValueLabel = streamingSearchEngineValue;
    [customizationStack addArrangedSubview:[self selectableValueRowWithTitle:@"Streaming search engine"
                                                                    subtitle:@"Choose provider for online tracks"
                                                                  valueLabel:streamingSearchEngineValue
                                                                      action:@selector(selectStreamingSearchEngineTapped)]];

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

    UISwitch *autoSaveStreamingSongsSwitch = [[UISwitch alloc] init];
    [autoSaveStreamingSongsSwitch addTarget:self action:@selector(autoSaveStreamingSongsChanged:) forControlEvents:UIControlEventValueChanged];
    self.autoSaveStreamingSongsSwitch = autoSaveStreamingSongsSwitch;
    [memoryStack addArrangedSubview:[self switchRowWithTitle:@"Auto-save streaming songs"
                                                    subtitle:@"Save online songs to the library while they play"
                                                     control:autoSaveStreamingSongsSwitch]];

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
    SonoraStreamingSearchEngine streamingSearchEngine = SonoraSettingsStreamingSearchEngine();
    BOOL useArtworkBasedPlayerBackground = SonoraSettingsUseArtworkBasedPlayerBackgroundEnabled();
    BOOL autoSaveStreamingSongs = SonoraSettingsAutoSaveStreamingSongsEnabled();
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
    if (streamingSearchEngine != SonoraStreamingSearchEngineSpotify &&
        streamingSearchEngine != SonoraStreamingSearchEngineYouTube) {
        streamingSearchEngine = SonoraStreamingSearchEngineSpotify;
        SonoraSettingsSetStreamingSearchEngine(streamingSearchEngine);
    }
    self.fontControl.selectedSegmentIndex = MAX(0, MIN(1, font));
    self.artworkStyleControl.selectedSegmentIndex = MAX(0, MIN(1, artworkStyle));
    self.myWaveLookControl.selectedSegmentIndex = myWaveLook;
    self.playerArtworkBackgroundSwitch.on = useArtworkBasedPlayerBackground;
    self.autoSaveStreamingSongsSwitch.on = autoSaveStreamingSongs;
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
    [self refreshStreamingSearchEngineLabel];
    [self refreshAccentColorLabel];
    [self refreshAppBackgroundLabel];
    self.view.backgroundColor = SonoraAppBackgroundColor();
    UIView *firstSubview = self.view.subviews.firstObject;
    if ([firstSubview isKindOfClass:UIScrollView.class]) {
        ((UIScrollView *)firstSubview).backgroundColor = SonoraAppBackgroundColor();
    }
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

- (void)playerArtworkBackgroundChanged:(UISwitch *)sender {
    SonoraSettingsSetUseArtworkBasedPlayerBackgroundEnabled(sender.isOn);
    [self notifyPlayerSettingsChanged];
}

- (void)autoSaveStreamingSongsChanged:(UISwitch *)sender {
    SonoraSettingsSetAutoSaveStreamingSongsEnabled(sender.isOn);
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

- (void)refreshAppBackgroundLabel {
    SonoraAppBackgroundMode mode = SonoraSettingsAppBackgroundMode();
    NSString *backgroundHex = SonoraSettingsAppBackgroundHex();
    switch (mode) {
        case SonoraAppBackgroundModeArtwork:
            self.appBackgroundValueLabel.text = @"Artwork";
            break;
        case SonoraAppBackgroundModeCustom:
            self.appBackgroundValueLabel.text = (backgroundHex.length > 0) ? backgroundHex : @"Custom";
            break;
        case SonoraAppBackgroundModeSystem:
        default:
            self.appBackgroundValueLabel.text = @"System";
            break;
    }
}

- (void)refreshStreamingSearchEngineLabel {
    SonoraStreamingSearchEngine engine = SonoraSettingsStreamingSearchEngine();
    self.streamingSearchEngineValueLabel.text = (engine == SonoraStreamingSearchEngineYouTube) ? @"YouTube" : @"Spotify";
}

- (void)selectAccentColorTapped {
    if (@available(iOS 14.0, *)) {
        self.colorPickerContext = SonoraSettingsColorPickerContextAccent;
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

- (void)selectAppBackgroundTapped {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"App background"
                                                                   message:@"Choose system, custom color or artwork-adaptive background."
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Choose color"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction * _Nonnull action) {
        if (@available(iOS 14.0, *)) {
            self.colorPickerContext = SonoraSettingsColorPickerContextAppBackground;
            UIColorPickerViewController *picker = [[UIColorPickerViewController alloc] init];
            NSString *storedHex = SonoraSettingsAppBackgroundHex();
            UIColor *selectedColor = SonoraHomeColorFromHexString(storedHex);
            picker.selectedColor = selectedColor ?: SonoraAppBackgroundColor();
            picker.supportsAlpha = NO;
            picker.delegate = self;
            [self presentViewController:picker animated:YES completion:nil];
        } else {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Unavailable"
                                                                           message:@"Color picker requires iOS 14 or newer."
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"From artwork"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction * _Nonnull action) {
        SonoraSettingsSetAppBackgroundMode(SonoraAppBackgroundModeArtwork);
        [self refreshAppBackgroundLabel];
        self.view.backgroundColor = SonoraAppBackgroundColor();
        UIView *firstSubview = self.view.subviews.firstObject;
        if ([firstSubview isKindOfClass:UIScrollView.class]) {
            ((UIScrollView *)firstSubview).backgroundColor = SonoraAppBackgroundColor();
        }
        [self notifyPlayerSettingsChanged];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Use system"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction * _Nonnull action) {
        SonoraSettingsSetAppBackgroundMode(SonoraAppBackgroundModeSystem);
        SonoraSettingsStoreAppBackgroundHex(nil);
        [self refreshAppBackgroundLabel];
        self.view.backgroundColor = SonoraAppBackgroundColor();
        UIView *firstSubview = self.view.subviews.firstObject;
        if ([firstSubview isKindOfClass:UIScrollView.class]) {
            ((UIScrollView *)firstSubview).backgroundColor = SonoraAppBackgroundColor();
        }
        [self notifyPlayerSettingsChanged];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self configurePopoverForSheet:sheet];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)colorPickerViewController:(UIColorPickerViewController *)viewController
                   didSelectColor:(UIColor *)color
                     continuously:(BOOL)continuously API_AVAILABLE(ios(15.0)) {
    (void)viewController;
    (void)continuously;
    if (self.colorPickerContext == SonoraSettingsColorPickerContextAppBackground) {
        SonoraSettingsSetAppBackgroundMode(SonoraAppBackgroundModeCustom);
        SonoraSettingsStoreAppBackgroundHex([self hexStringForColor:color]);
        [self refreshAppBackgroundLabel];
    } else {
        [self storeAccentColor:color];
        [self refreshAccentColorLabel];
    }
    self.view.backgroundColor = SonoraAppBackgroundColor();
    UIView *firstSubview = self.view.subviews.firstObject;
    if ([firstSubview isKindOfClass:UIScrollView.class]) {
        ((UIScrollView *)firstSubview).backgroundColor = SonoraAppBackgroundColor();
    }
    [self notifyPlayerSettingsChanged];
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController API_AVAILABLE(ios(14.0)) {
    if (self.colorPickerContext == SonoraSettingsColorPickerContextAppBackground) {
        SonoraSettingsSetAppBackgroundMode(SonoraAppBackgroundModeCustom);
        SonoraSettingsStoreAppBackgroundHex([self hexStringForColor:viewController.selectedColor]);
        [self refreshAppBackgroundLabel];
    } else {
        [self storeAccentColor:viewController.selectedColor];
        [self refreshAccentColorLabel];
    }
    self.view.backgroundColor = SonoraAppBackgroundColor();
    UIView *firstSubview = self.view.subviews.firstObject;
    if ([firstSubview isKindOfClass:UIScrollView.class]) {
        ((UIScrollView *)firstSubview).backgroundColor = SonoraAppBackgroundColor();
    }
    [self notifyPlayerSettingsChanged];
}

- (void)artworkEqualizerChanged:(UISwitch *)sender {
    SonoraSettingsSetArtworkEqualizerEnabled(sender.isOn);
    [self notifyPlayerSettingsChanged];
}

- (void)selectStreamingSearchEngineTapped {
    SonoraStreamingSearchEngine current = SonoraSettingsStreamingSearchEngine();
    NSString *currentLabel = (current == SonoraStreamingSearchEngineYouTube) ? @"YouTube" : @"Spotify";
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Streaming search engine"
                                                                   message:[NSString stringWithFormat:@"Current: %@", currentLabel]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Spotify"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction * _Nonnull action) {
        SonoraSettingsSetStreamingSearchEngine(SonoraStreamingSearchEngineSpotify);
        [self refreshStreamingSearchEngineLabel];
        [self notifyPlayerSettingsChanged];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"YouTube"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction * _Nonnull action) {
        SonoraSettingsSetStreamingSearchEngine(SonoraStreamingSearchEngineYouTube);
        [self refreshStreamingSearchEngineLabel];
        [self notifyPlayerSettingsChanged];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self configurePopoverForSheet:sheet];
    [self presentViewController:sheet animated:YES completion:nil];
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
        @"streamingSearchEngine": (SonoraSettingsStreamingSearchEngine() == SonoraStreamingSearchEngineYouTube ? @"youtube" : @"spotify"),
        @"useArtworkBasedPlayerBackground": @(SonoraSettingsUseArtworkBasedPlayerBackgroundEnabled()),
        @"appBackgroundHex": SonoraSettingsAppBackgroundHex() ?: @"",
        @"autoSaveStreamingSongs": @(SonoraSettingsAutoSaveStreamingSongsEnabled()),
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

    id streamingSearchEngineValue = settings[@"streamingSearchEngine"];
    SonoraStreamingSearchEngine engine = SonoraStreamingSearchEngineSpotify;
    if ([streamingSearchEngineValue isKindOfClass:NSString.class]) {
        NSString *normalizedEngine = [((NSString *)streamingSearchEngineValue) lowercaseString];
        engine = [normalizedEngine isEqualToString:@"youtube"] ? SonoraStreamingSearchEngineYouTube : SonoraStreamingSearchEngineSpotify;
    } else if ([streamingSearchEngineValue respondsToSelector:@selector(integerValue)]) {
        engine = ([streamingSearchEngineValue integerValue] == SonoraStreamingSearchEngineYouTube)
            ? SonoraStreamingSearchEngineYouTube
            : SonoraStreamingSearchEngineSpotify;
    }
    SonoraSettingsSetStreamingSearchEngine(engine);

    id artworkBackgroundValue = settings[@"useArtworkBasedPlayerBackground"];
    if ([artworkBackgroundValue respondsToSelector:@selector(boolValue)]) {
        SonoraSettingsSetUseArtworkBasedPlayerBackgroundEnabled([artworkBackgroundValue boolValue]);
    }

    id appBackgroundHexValue = settings[@"appBackgroundHex"];
    if ([appBackgroundHexValue isKindOfClass:NSString.class]) {
        SonoraSettingsStoreAppBackgroundHex((NSString *)appBackgroundHexValue);
    } else {
        id accentAppBackgroundValue = settings[@"useAccentAppBackground"];
        if ([accentAppBackgroundValue respondsToSelector:@selector(boolValue)] &&
            [accentAppBackgroundValue boolValue]) {
            SonoraSettingsStoreAppBackgroundHex([self hexStringForColor:[self currentAccentColor]]);
        }
    }

    id autoSaveStreamingSongsValue = settings[@"autoSaveStreamingSongs"];
    if ([autoSaveStreamingSongsValue respondsToSelector:@selector(boolValue)]) {
        SonoraSettingsSetAutoSaveStreamingSongsEnabled([autoSaveStreamingSongsValue boolValue]);
    }

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
