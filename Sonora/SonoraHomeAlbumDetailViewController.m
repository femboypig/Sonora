//
//  SonoraHomeAlbumDetailViewController.m
//  Sonora
//

#import "SonoraHomeAlbumDetailViewController.h"

#import <math.h>

#import "SonoraCells.h"
#import "SonoraPlayerViewController.h"
#import "SonoraSettings.h"
#import "SonoraSleepTimerUI.h"
#import "SonoraServices.h"

static UIFont *SonoraHomeAlbumDetailHeadlineFont(CGFloat size) {
    UIFont *font = [UIFont fontWithName:@"YSMusic-HeadlineBold" size:size];
    if (font != nil) {
        return font;
    }
    return [UIFont boldSystemFontOfSize:size];
}

static UIColor *SonoraHomeAlbumDetailDefaultAccentColor(void) {
    return [UIColor colorWithRed:1.0 green:0.83 blue:0.08 alpha:1.0];
}

static UIColor *SonoraHomeAlbumDetailLegacyAccentColorForIndex(NSInteger raw) {
    switch (raw) {
        case 1:
            return [UIColor colorWithRed:0.31 green:0.64 blue:1.0 alpha:1.0];
        case 2:
            return [UIColor colorWithRed:0.22 green:0.83 blue:0.62 alpha:1.0];
        case 3:
            return [UIColor colorWithRed:1.0 green:0.48 blue:0.40 alpha:1.0];
        case 0:
        default:
            return SonoraHomeAlbumDetailDefaultAccentColor();
    }
}

static UIColor *SonoraHomeAlbumDetailColorFromHexString(NSString *hexString) {
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

static UIColor *SonoraHomeAlbumDetailAccentColor(void) {
    UIColor *fromHex = SonoraHomeAlbumDetailColorFromHexString(SonoraSettingsAccentHex());
    if (fromHex != nil) {
        return fromHex;
    }
    return SonoraHomeAlbumDetailLegacyAccentColorForIndex(SonoraSettingsLegacyAccentColorIndex());
}

@interface SonoraHomeAlbumDetailViewController () <UITableViewDataSource, UITableViewDelegate>

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
    nameLabel.font = SonoraHomeAlbumDetailHeadlineFont(28.0);
    nameLabel.textColor = UIColor.labelColor;
    self.nameLabel = nameLabel;

    CGFloat playSize = 66.0;
    CGFloat shuffleSize = 46.0;
    CGFloat sleepSize = 46.0;
    CGFloat controlsY = 276.0;

    UIButton *playButton = [UIButton buttonWithType:UIButtonTypeSystem];
    playButton.frame = CGRectMake((totalWidth - playSize) * 0.5, controlsY, playSize, playSize);
    playButton.backgroundColor = SonoraHomeAlbumDetailAccentColor();
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
                                                                          fallback:SonoraHomeAlbumDetailAccentColor()];
    self.playButton.backgroundColor = playColor ?: SonoraHomeAlbumDetailAccentColor();
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
    self.sleepControlButton.tintColor = isActive ? SonoraHomeAlbumDetailAccentColor() : UIColor.labelColor;
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
    UIViewController *player = [[SonoraPlayerViewController alloc] init];
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

