//
//  SonoraMusicModule.m
//  Sonora
//

#import "SonoraMusicModule.h"

#import "SonoraMiniStreamingClient.h"
#import "SonoraMusicSearchViews.h"
#import "SonoraMusicUIHelpers.h"
#import "SonoraPlaylistViewControllers.h"
#import "SonoraPlayerViewController.h"
#import <limits.h>
#import <math.h>
#import <QuartzCore/QuartzCore.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "SonoraCells.h"
#import "SonoraSettings.h"
#import "SonoraSharedPlaylists.h"
#import "SonoraSleepTimerUI.h"
#import "SonoraServices.h"

static NSString * const SonoraLovelyPlaylistCoverMarkerKey = @"sonora_lovely_playlist_cover_marker_v2";
static NSString * const SonoraMiniStreamingPlaceholderPrefix = @"mini-streaming-placeholder-";
static NSString * const SonoraMiniStreamingInstalledTrackMapDefaultsKey = @"sonora.ministreaming.installedTrackPathsByTrackID.v1";
static NSUInteger const SonoraMiniStreamingSearchLimit = 8;
static NSString * const SonoraSharedPlaylistDefaultsKey = @"sonora.sharedPlaylists.v1";
static NSString * const SonoraSharedPlaylistDeepLinkHost = @"playlist";
static NSString * const SonoraSharedPlaylistDeepLinkPath = @"/shared";

static UIViewController * _Nullable SonoraTopMostViewController(void);

BOOL SonoraHandleMusicModuleDeepLinkURL(NSURL *url) {
    if (![url isKindOfClass:NSURL.class]) {
        return NO;
    }
    if (![[url.scheme lowercaseString] isEqualToString:@"sonora"]) {
        return NO;
    }
    if (![[url.host lowercaseString] isEqualToString:SonoraSharedPlaylistDeepLinkHost]) {
        return NO;
    }
    if (![(url.path ?: @"") isEqualToString:SonoraSharedPlaylistDeepLinkPath]) {
        return NO;
    }

    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSString *playlistID = @"";
    NSString *sourceBaseURL = SonoraSharedPlaylistBackendBaseURLString();
    for (NSURLQueryItem *item in components.queryItems) {
        if ([item.name isEqualToString:@"id"] && item.value.length > 0) {
            playlistID = item.value;
        } else if ([item.name isEqualToString:@"source"] && item.value.length > 0) {
            sourceBaseURL = item.value;
        }
    }
    if (playlistID.length == 0) {
        return NO;
    }

    UIViewController *presenter = SonoraTopMostViewController();
    SonoraSharedPlaylistStore *sharedPlaylistStore = SonoraSharedPlaylistStore.sharedStore;
    SonoraSharedPlaylistSnapshot *cachedSnapshot = [sharedPlaylistStore snapshotForPlaylistID:SonoraSharedPlaylistSyntheticID(playlistID)];
    __block UIAlertController *progress = nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        progress = SonoraPresentBlockingProgressAlert(presenter, @"Opening Playlist", @"Loading tracks from server...");
    });
    NSString *requestString = [[sourceBaseURL stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] stringByAppendingFormat:@"/api/shared-playlists/%@", playlistID];
    NSURL *requestURL = [NSURL URLWithString:requestString];
    SonoraSharedPlaylistDataFromURL(requestURL, 120.0, ^(NSData * _Nullable data, __unused NSURLResponse * _Nullable response, __unused NSError * _Nullable error) {
        NSDictionary *payload = data.length > 0 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        SonoraSharedPlaylistSnapshot *snapshot = SonoraSharedPlaylistSnapshotFromPayload(payload, sourceBaseURL);
        if (snapshot == nil && cachedSnapshot != nil) {
            snapshot = cachedSnapshot;
        } else if (snapshot != nil && cachedSnapshot != nil &&
                   snapshot.contentSHA256.length > 0 &&
                   [snapshot.contentSHA256 isEqualToString:(cachedSnapshot.contentSHA256 ?: @"")]) {
            snapshot = cachedSnapshot;
        } else if (snapshot != nil && cachedSnapshot != nil) {
            SonoraSharedPlaylistPerformWithoutDidChangeNotification(^{
                [sharedPlaylistStore saveSnapshot:snapshot];
            });
            SonoraSharedPlaylistWarmPersistentCache(snapshot, nil);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            void (^finishOpening)(void) = ^{
                UIViewController *top = presenter ?: SonoraTopMostViewController();
                if (snapshot == nil || top == nil) {
                    if (top != nil) {
                        SonoraPresentAlert(top, @"Error", @"Could not open shared playlist.");
                    }
                    return;
                }
                UIViewController *detail = [[SonoraPlaylistDetailViewController alloc] initWithSharedPlaylistSnapshot:snapshot];
                detail.hidesBottomBarWhenPushed = YES;
                UINavigationController *nav = top.navigationController;
                if ([top isKindOfClass:UINavigationController.class]) {
                    nav = (UINavigationController *)top;
                }
                if (nav != nil) {
                    [nav pushViewController:detail animated:YES];
                } else {
                    [top presentViewController:[[UINavigationController alloc] initWithRootViewController:detail] animated:YES completion:nil];
                }
            };
            if (progress.presentingViewController != nil) {
                [progress dismissViewControllerAnimated:YES completion:finishOpening];
            } else {
                finishOpening();
            }
        });
    });
    return YES;
}

static UIViewController * _Nullable SonoraTopMostViewController(void) {
    UIViewController *root = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) {
            continue;
        }
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) {
                root = window.rootViewController;
                break;
            }
        }
        if (root != nil) {
            break;
        }
    }
    UIViewController *current = root;
    while (current.presentedViewController != nil) {
        current = current.presentedViewController;
    }
    if ([current isKindOfClass:UITabBarController.class]) {
        UITabBarController *tab = (UITabBarController *)current;
        current = tab.selectedViewController ?: current;
    }
    if ([current isKindOfClass:UINavigationController.class]) {
        UINavigationController *nav = (UINavigationController *)current;
        current = nav.topViewController ?: nav;
    }
    return current;
}

static NSString *SonoraTrimmedStringValue(id value) {
    if (![value isKindOfClass:NSString.class]) {
        return @"";
    }
    NSString *trimmed = [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return trimmed ?: @"";
}

static NSString *SonoraSanitizedFileComponent(NSString *value) {
    NSString *trimmed = SonoraTrimmedStringValue(value);
    if (trimmed.length == 0) {
        return @"";
    }

    NSMutableCharacterSet *invalid = [NSMutableCharacterSet characterSetWithCharactersInString:@"<>:\"/\\|?*"];
    [invalid formUnionWithCharacterSet:NSCharacterSet.controlCharacterSet];
    NSArray<NSString *> *parts = [trimmed componentsSeparatedByCharactersInSet:invalid];
    NSString *joined = [parts componentsJoinedByString:@""];
    NSString *normalizedSpaces = [joined stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    while ([normalizedSpaces containsString:@"  "]) {
        normalizedSpaces = [normalizedSpaces stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    }
    return normalizedSpaces ?: @"";
}

static NSSet<NSString *> *SonoraSupportedAudioExtensions(void) {
    static NSSet<NSString *> *extensions;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        extensions = [NSSet setWithArray:@[@"mp3", @"m4a", @"aac", @"wav", @"aiff", @"flac", @"caf"]];
    });
    return extensions;
}

static UIImage *SonoraMiniStreamingPlaceholderArtwork(NSString *seed, CGSize size) {
    CGSize normalizedSize = CGSizeMake(MAX(size.width, 180.0), MAX(size.height, 180.0));
    NSString *title = SonoraTrimmedStringValue(seed);
    if (title.length == 0) {
        title = @"Track";
    }

    NSUInteger hash = title.hash;
    CGFloat hue = ((CGFloat)(hash % 360u)) / 360.0f;
    UIColor *baseColor = [UIColor colorWithHue:hue saturation:0.52 brightness:0.82 alpha:1.0];
    UIColor *secondaryColor = [UIColor colorWithHue:fmod(hue + 0.12, 1.0) saturation:0.58 brightness:0.64 alpha:1.0];

    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:normalizedSize];
    return [renderer imageWithActions:^(__unused UIGraphicsImageRendererContext * _Nonnull context) {
        CGRect rect = CGRectMake(0, 0, normalizedSize.width, normalizedSize.height);
        CAGradientLayer *gradient = [CAGradientLayer layer];
        gradient.frame = rect;
        gradient.startPoint = CGPointMake(0.0, 0.0);
        gradient.endPoint = CGPointMake(1.0, 1.0);
        gradient.colors = @[
            (__bridge id)baseColor.CGColor,
            (__bridge id)secondaryColor.CGColor
        ];
        [gradient renderInContext:UIGraphicsGetCurrentContext()];

        NSString *symbol = [title substringToIndex:MIN((NSUInteger)1, title.length)].uppercaseString;
        NSDictionary<NSAttributedStringKey, id> *attributes = @{
            NSFontAttributeName: [UIFont systemFontOfSize:normalizedSize.width * 0.34 weight:UIFontWeightBold],
            NSForegroundColorAttributeName: UIColor.whiteColor
        };
        CGSize textSize = [symbol sizeWithAttributes:attributes];
        CGRect textRect = CGRectMake((normalizedSize.width - textSize.width) * 0.5,
                                     (normalizedSize.height - textSize.height) * 0.5,
                                     textSize.width,
                                     textSize.height);
        [symbol drawInRect:textRect withAttributes:attributes];
    }];
}

static NSInteger SonoraIndexOfTrackByIdentifier(NSArray<SonoraTrack *> *tracks, NSString *trackID) {
    if (trackID.length == 0 || tracks.count == 0) {
        return NSNotFound;
    }

    for (NSUInteger idx = 0; idx < tracks.count; idx += 1) {
        SonoraTrack *track = tracks[idx];
        if ([track.identifier isEqualToString:trackID]) {
            return (NSInteger)idx;
        }
    }
    return NSNotFound;
}

static NSArray<SonoraPlaylist *> *SonoraFilterPlaylistsByQuery(NSArray<SonoraPlaylist *> *playlists, NSString *query) {
    NSString *normalizedQuery = SonoraNormalizedSearchText(query);
    if (normalizedQuery.length == 0) {
        return playlists ?: @[];
    }

    NSMutableArray<SonoraPlaylist *> *filtered = [NSMutableArray arrayWithCapacity:playlists.count];
    for (SonoraPlaylist *playlist in playlists) {
        NSString *name = playlist.name.lowercaseString ?: @"";
        if ([name containsString:normalizedQuery]) {
            [filtered addObject:playlist];
        }
    }
    return [filtered copy];
}

static NSArray<NSString *> *SonoraArtistParticipantsFromText(NSString *artistText) {
    NSString *trimmed = [artistText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        return @[];
    }

    NSMutableArray<NSString *> *values = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSArray<NSString *> *chunks = [trimmed componentsSeparatedByString:@","];
    for (NSString *chunk in chunks) {
        NSString *value = [chunk stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *key = SonoraNormalizedSearchText(value);
        if (key.length == 0 || [seen containsObject:key]) {
            continue;
        }
        [seen addObject:key];
        [values addObject:value];
    }
    return values;
}

static __attribute__((unused)) NSArray<NSDictionary<NSString *, id> *> *SonoraBuildArtistSearchResults(NSArray<SonoraTrack *> *tracks,
                                                                                                        NSString *query,
                                                                                                        NSUInteger limit) {
    NSString *normalizedQuery = SonoraNormalizedSearchText(query);
    if (tracks.count == 0 || limit == 0) {
        return @[];
    }

    NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, id> *> *artistsByKey = [NSMutableDictionary dictionary];
    for (SonoraTrack *track in tracks) {
        NSArray<NSString *> *participants = SonoraArtistParticipantsFromText(track.artist ?: @"");
        for (NSString *participant in participants) {
            NSString *key = SonoraNormalizedSearchText(participant);
            if (normalizedQuery.length > 0 && ![key containsString:normalizedQuery]) {
                continue;
            }

            NSMutableDictionary<NSString *, id> *entry = artistsByKey[key];
            if (entry == nil) {
                entry = [@{
                    @"key": key,
                    @"title": participant,
                    @"tracks": [NSMutableArray array]
                } mutableCopy];
                artistsByKey[key] = entry;
            }
            NSMutableArray<SonoraTrack *> *matchedTracks = entry[@"tracks"];
            if (matchedTracks == nil) {
                matchedTracks = [NSMutableArray array];
                entry[@"tracks"] = matchedTracks;
            }
            BOOL alreadyIncluded = NO;
            for (SonoraTrack *existing in matchedTracks) {
                if ([existing.identifier isEqualToString:track.identifier]) {
                    alreadyIncluded = YES;
                    break;
                }
            }
            if (!alreadyIncluded) {
                [matchedTracks addObject:track];
            }
        }
    }

    NSArray<NSDictionary<NSString *, id> *> *sorted = [artistsByKey.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary<NSString *,id> * _Nonnull left,
                                                                                                                             NSDictionary<NSString *,id> * _Nonnull right) {
        NSArray *leftTracks = left[@"tracks"];
        NSArray *rightTracks = right[@"tracks"];
        if (leftTracks.count > rightTracks.count) {
            return NSOrderedAscending;
        }
        if (leftTracks.count < rightTracks.count) {
            return NSOrderedDescending;
        }
        NSString *leftTitle = left[@"title"] ?: @"";
        NSString *rightTitle = right[@"title"] ?: @"";
        return [leftTitle localizedCaseInsensitiveCompare:rightTitle];
    }];

    if (sorted.count <= limit) {
        return sorted;
    }
    return [sorted subarrayWithRange:NSMakeRange(0, limit)];
}

typedef void (^SonoraMiniStreamingInstallHandler)(SonoraMiniStreamingTrack *track,
                                                  NSArray<SonoraMiniStreamingTrack *> *queue,
                                                  NSInteger startIndex,
                                                  UIImage * _Nullable artwork);

@interface SonoraMiniStreamingArtistViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

- (instancetype)initWithArtist:(SonoraMiniStreamingArtist *)artist
                        client:(SonoraMiniStreamingClient *)client
                installHandler:(SonoraMiniStreamingInstallHandler)installHandler;

@end

@interface SonoraMiniStreamingArtistViewController ()

@property (nonatomic, strong) SonoraMiniStreamingArtist *artist;
@property (nonatomic, strong) SonoraMiniStreamingClient *client;
@property (nonatomic, copy) SonoraMiniStreamingInstallHandler installHandler;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray<SonoraMiniStreamingTrack *> *tracks;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *artworkCache;
@property (nonatomic, strong) NSMutableSet<NSString *> *loadingArtworkURLs;
@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UIButton *shuffleButton;
@property (nonatomic, strong) UIButton *sleepButton;
@property (nonatomic, assign) BOOL compactTitleVisible;

@end

@implementation SonoraMiniStreamingArtistViewController

- (instancetype)initWithArtist:(SonoraMiniStreamingArtist *)artist
                        client:(SonoraMiniStreamingClient *)client
                installHandler:(SonoraMiniStreamingInstallHandler)installHandler {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _artist = artist;
        _client = client;
        _installHandler = [installHandler copy];
        _tracks = @[];
        _artworkCache = [[NSCache alloc] init];
        _artworkCache.countLimit = 64;
        _artworkCache.totalCostLimit = 48 * 1024 * 1024;
        _loadingArtworkURLs = [NSMutableSet set];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.title = nil;
    self.navigationItem.rightBarButtonItem = nil;
    self.compactTitleVisible = NO;

    [self setupTableView];
    self.tableView.tableHeaderView = [self headerViewForWidth:self.view.bounds.size.width];
    [self updateHeader];
    [self updatePlayButtonState];
    [self updateSleepButton];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handlePlaybackChanged)
                                               name:SonoraPlaybackStateDidChangeNotification
                                             object:nil];

    __weak typeof(self) weakSelf = self;
    [self.client fetchTopTracksForArtistID:self.artist.artistID
                                     limit:0
                                completion:^(NSArray<SonoraMiniStreamingTrack *> *tracks, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        (void)error;
        strongSelf.tracks = tracks ?: @[];
        NSUInteger prefetchCount = MIN((NSUInteger)strongSelf.tracks.count, (NSUInteger)12);
        for (NSUInteger index = 0; index < prefetchCount; index += 1) {
            [strongSelf loadArtworkIfNeededForTrack:strongSelf.tracks[index]];
        }
        [strongSelf.tableView reloadData];
        [strongSelf updateEmptyState];
        [strongSelf updatePlayButtonState];
        [strongSelf updateSleepButton];
        [strongSelf updateNavigationTitleVisibility];
    }];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.view.bounds.size.width;
    if (fabs(self.tableView.tableHeaderView.bounds.size.width - width) > 1.0) {
        self.tableView.tableHeaderView = [self headerViewForWidth:width];
        [self updateHeader];
        [self updatePlayButtonState];
        [self updateSleepButton];
    }
    [self updateNavigationTitleVisibility];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self handlePlaybackChanged];
}

- (void)setupTableView {
    UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    tableView.translatesAutoresizingMaskIntoConstraints = NO;
    tableView.dataSource = self;
    tableView.delegate = self;
    tableView.rowHeight = 54.0;
    tableView.alwaysBounceVertical = YES;
    tableView.sectionHeaderHeight = 0.0;
    tableView.sectionFooterHeight = 0.0;
    tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    if (@available(iOS 15.0, *)) {
        tableView.sectionHeaderTopPadding = 0.0;
    }
    [tableView registerClass:SonoraTrackCell.class forCellReuseIdentifier:@"MiniStreamingArtistTrackCell"];
    self.tableView = tableView;
    [self.view addSubview:tableView];

    [NSLayoutConstraint activateConstraints:@[
        [tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (UIView *)headerViewForWidth:(CGFloat)width {
    CGFloat totalWidth = MAX(width, 320.0);
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, totalWidth, 374.0)];

    UIImageView *coverView = [[UIImageView alloc] initWithFrame:CGRectMake((totalWidth - 212.0) * 0.5, 16.0, 212.0, 212.0)];
    coverView.layer.cornerRadius = 16.0;
    coverView.layer.masksToBounds = YES;
    coverView.contentMode = UIViewContentModeScaleAspectFill;
    self.coverView = coverView;

    UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(14.0, 236.0, totalWidth - 28.0, 32.0)];
    nameLabel.textAlignment = NSTextAlignmentCenter;
    nameLabel.font = SonoraHeadlineFont(28.0);
    nameLabel.textColor = UIColor.labelColor;
    self.nameLabel = nameLabel;

    CGFloat playSize = 66.0;
    CGFloat sideControlSize = 46.0;
    CGFloat controlsY = 272.0;
    UIButton *playButton = [UIButton buttonWithType:UIButtonTypeSystem];
    playButton.frame = CGRectMake((totalWidth - playSize) * 0.5, controlsY, playSize, playSize);
    playButton.backgroundColor = SonoraAccentYellowColor();
    playButton.tintColor = UIColor.whiteColor;
    playButton.layer.cornerRadius = playSize * 0.5;
    playButton.layer.masksToBounds = YES;
    UIImageSymbolConfiguration *playConfig = [UIImageSymbolConfiguration configurationWithPointSize:29.0
                                                                                               weight:UIImageSymbolWeightSemibold];
    [playButton setImage:[UIImage systemImageNamed:@"play.fill" withConfiguration:playConfig] forState:UIControlStateNormal];
    [playButton addTarget:self action:@selector(playTapped) forControlEvents:UIControlEventTouchUpInside];
    self.playButton = playButton;

    UIButton *sleepButton = [UIButton buttonWithType:UIButtonTypeSystem];
    sleepButton.frame = CGRectMake(CGRectGetMinX(playButton.frame) - 16.0 - sideControlSize,
                                   controlsY + (playSize - sideControlSize) * 0.5,
                                   sideControlSize,
                                   sideControlSize);
    UIImageSymbolConfiguration *sleepConfig = [UIImageSymbolConfiguration configurationWithPointSize:22.0
                                                                                               weight:UIImageSymbolWeightSemibold];
    [sleepButton setImage:[UIImage systemImageNamed:@"moon.zzz" withConfiguration:sleepConfig] forState:UIControlStateNormal];
    sleepButton.tintColor = SonoraPlayerPrimaryColor();
    sleepButton.backgroundColor = UIColor.clearColor;
    [sleepButton addTarget:self action:@selector(sleepTimerTapped) forControlEvents:UIControlEventTouchUpInside];
    self.sleepButton = sleepButton;

    UIButton *shuffleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    shuffleButton.frame = CGRectMake(CGRectGetMaxX(playButton.frame) + 16.0,
                                     controlsY + (playSize - sideControlSize) * 0.5,
                                     sideControlSize,
                                     sideControlSize);
    UIImageSymbolConfiguration *shuffleConfig = [UIImageSymbolConfiguration configurationWithPointSize:22.0
                                                                                                 weight:UIImageSymbolWeightSemibold];
    [shuffleButton setImage:[UIImage systemImageNamed:@"shuffle" withConfiguration:shuffleConfig] forState:UIControlStateNormal];
    shuffleButton.tintColor = SonoraPlayerPrimaryColor();
    shuffleButton.backgroundColor = UIColor.clearColor;
    [shuffleButton addTarget:self action:@selector(shuffleTapped) forControlEvents:UIControlEventTouchUpInside];
    self.shuffleButton = shuffleButton;

    [header addSubview:coverView];
    [header addSubview:nameLabel];
    [header addSubview:sleepButton];
    [header addSubview:playButton];
    [header addSubview:shuffleButton];

    return header;
}

- (void)updateHeader {
    NSString *artistName = self.artist.name.length > 0 ? self.artist.name : @"Artist";
    self.nameLabel.text = artistName;

    UIImage *coverImage = [self cachedArtworkForURL:self.artist.artworkURL];
    if (coverImage != nil) {
        self.coverView.image = coverImage;
        self.coverView.contentMode = UIViewContentModeScaleAspectFill;
        self.coverView.tintColor = nil;
        self.coverView.backgroundColor = UIColor.clearColor;
    } else {
        self.coverView.image = [UIImage systemImageNamed:@"person.fill"];
        self.coverView.contentMode = UIViewContentModeCenter;
        self.coverView.tintColor = UIColor.secondaryLabelColor;
        self.coverView.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
            if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
                return [UIColor colorWithWhite:1.0 alpha:0.08];
            }
            return [UIColor colorWithWhite:0.0 alpha:0.04];
        }];
        [self loadArtworkIfNeededForURL:self.artist.artworkURL];
    }
}

- (void)updatePlayButtonState {
    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    SonoraTrack *currentTrack = playback.currentTrack;
    BOOL hasTracks = (self.tracks.count > 0);
    BOOL playingArtistTrack = NO;
    for (SonoraMiniStreamingTrack *track in self.tracks) {
        if ([self isPlaybackTrack:currentTrack matchingMiniTrack:track]) {
            playingArtistTrack = YES;
            break;
        }
    }

    self.playButton.enabled = hasTracks;
    self.playButton.alpha = hasTracks ? 1.0 : 0.45;
    NSString *symbolName = (playingArtistTrack && playback.isPlaying) ? @"pause.fill" : @"play.fill";
    UIImageSymbolConfiguration *playConfig = [UIImageSymbolConfiguration configurationWithPointSize:29.0
                                                                                              weight:UIImageSymbolWeightSemibold];
    [self.playButton setImage:[UIImage systemImageNamed:symbolName withConfiguration:playConfig] forState:UIControlStateNormal];
}

- (void)updateNavigationTitleVisibility {
    NSString *artistName = self.artist.name.length > 0 ? self.artist.name : @"Artist";
    BOOL shouldShowCompact = (self.tableView.contentOffset.y > 170.0);
    if (shouldShowCompact == self.compactTitleVisible) {
        return;
    }
    self.compactTitleVisible = shouldShowCompact;
    if (shouldShowCompact) {
        self.navigationItem.title = artistName;
    } else {
        self.navigationItem.title = nil;
    }
}

- (void)updateEmptyState {
    if (self.tracks.count > 0) {
        self.tableView.backgroundView = nil;
        return;
    }

    UILabel *label = [[UILabel alloc] init];
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = UIColor.secondaryLabelColor;
    label.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    label.text = @"No tracks found for this artist.";
    self.tableView.backgroundView = label;
}

- (nullable UIImage *)cachedArtworkForURL:(NSString *)urlString {
    if (urlString.length == 0) {
        return nil;
    }
    return [self.artworkCache objectForKey:urlString];
}

- (nullable UIImage *)cachedArtworkForTrack:(SonoraMiniStreamingTrack *)track {
    return [self cachedArtworkForURL:track.artworkURL];
}

- (void)loadArtworkIfNeededForURL:(NSString *)urlString {
    if (urlString.length == 0 ||
        [self.artworkCache objectForKey:urlString] != nil ||
        [self.loadingArtworkURLs containsObject:urlString]) {
        return;
    }

    NSURL *url = [NSURL URLWithString:urlString];
    if (url == nil) {
        return;
    }

    [self.loadingArtworkURLs addObject:urlString];
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:url
                                                            completionHandler:^(NSData * _Nullable data,
                                                                                NSURLResponse * _Nullable response,
                                                                                NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        UIImage *image = nil;
        if (error == nil && data.length > 0) {
            image = [UIImage imageWithData:data];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [strongSelf.loadingArtworkURLs removeObject:urlString];
            if (image != nil) {
                [strongSelf.artworkCache setObject:image forKey:urlString];
                [strongSelf.tableView reloadData];
                [strongSelf updateHeader];
            }
        });
    }];
    [task resume];
}

- (void)loadArtworkIfNeededForTrack:(SonoraMiniStreamingTrack *)track {
    [self loadArtworkIfNeededForURL:track.artworkURL];
}

- (SonoraTrack *)displayTrackForMiniTrack:(SonoraMiniStreamingTrack *)miniTrack artwork:(UIImage * _Nullable)artwork {
    SonoraTrack *track = [[SonoraTrack alloc] init];
    NSString *trackID = SonoraTrimmedStringValue(miniTrack.trackID);
    if (trackID.length == 0) {
        trackID = [NSUUID UUID].UUIDString;
    }
    track.identifier = [NSString stringWithFormat:@"mini-streaming-display-%@", trackID];
    track.title = miniTrack.title.length > 0 ? miniTrack.title : @"Track";
    track.artist = miniTrack.artists.length > 0 ? miniTrack.artists : @"Spotify";
    track.fileName = [NSString stringWithFormat:@"%@.placeholder", trackID];
    track.url = [NSURL fileURLWithPath:@"/dev/null"];
    track.duration = MAX(miniTrack.duration, 0.0);
    track.artwork = artwork ?: SonoraMiniStreamingPlaceholderArtwork(track.title, CGSizeMake(320.0, 320.0));
    return track;
}

- (void)playTapped {
    if (self.tracks.count == 0) {
        SonoraPresentAlert(self, @"No Tracks", @"No tracks found for this artist.");
        return;
    }

    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    BOOL hasCurrentArtistTrack = NO;
    for (SonoraMiniStreamingTrack *artistTrack in self.tracks) {
        if ([self isPlaybackTrack:playback.currentTrack matchingMiniTrack:artistTrack]) {
            hasCurrentArtistTrack = YES;
            break;
        }
    }
    if (hasCurrentArtistTrack) {
        [playback togglePlayPause];
        [self updatePlayButtonState];
        [self.tableView reloadData];
        return;
    }

    SonoraMiniStreamingTrack *track = self.tracks.firstObject;
    if (track != nil && self.installHandler != nil) {
        UIImage *artwork = [self cachedArtworkForTrack:track];
        self.installHandler(track, self.tracks, 0, artwork);
    }
}

- (void)shuffleTapped {
    if (self.tracks.count == 0) {
        SonoraPresentAlert(self, @"No Tracks", @"No tracks found for this artist.");
        return;
    }
    if (self.installHandler == nil) {
        return;
    }

    NSMutableArray<SonoraMiniStreamingTrack *> *shuffledQueue = [self.tracks mutableCopy];
    for (NSInteger index = shuffledQueue.count - 1; index > 0; index -= 1) {
        NSInteger randomIndex = arc4random_uniform((u_int32_t)(index + 1));
        [shuffledQueue exchangeObjectAtIndex:(NSUInteger)index withObjectAtIndex:(NSUInteger)randomIndex];
    }
    SonoraMiniStreamingTrack *startTrack = shuffledQueue.firstObject ?: self.tracks.firstObject;
    if (startTrack == nil) {
        return;
    }
    UIImage *artwork = [self cachedArtworkForTrack:startTrack];
    self.installHandler(startTrack, [shuffledQueue copy], 0, artwork);
}

- (void)sleepTimerTapped {
    __weak typeof(self) weakSelf = self;
    SonoraPresentSleepTimerActionSheet(self, self.sleepButton, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf updateSleepButton];
    });
}

- (void)updateSleepButton {
    if (self.sleepButton == nil) {
        return;
    }

    SonoraSleepTimerManager *sleepTimer = SonoraSleepTimerManager.sharedManager;
    BOOL isActive = sleepTimer.isActive;
    NSString *symbol = isActive ? @"moon.zzz.fill" : @"moon.zzz";
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:22.0
                                                                                          weight:UIImageSymbolWeightSemibold];
    [self.sleepButton setImage:[UIImage systemImageNamed:symbol withConfiguration:config] forState:UIControlStateNormal];
    UIColor *inactiveColor = SonoraPlayerPrimaryColor();
    self.sleepButton.tintColor = isActive ? SonoraAccentYellowColor() : inactiveColor;
    if (self.shuffleButton != nil) {
        self.shuffleButton.tintColor = inactiveColor;
    }
    self.sleepButton.accessibilityLabel = isActive
    ? [NSString stringWithFormat:@"Sleep timer active, %@ remaining", SonoraSleepTimerRemainingString(sleepTimer.remainingTime)]
    : @"Sleep timer";
}

- (BOOL)isPlaybackTrack:(SonoraTrack * _Nullable)playbackTrack matchingMiniTrack:(SonoraMiniStreamingTrack *)miniTrack {
    if (playbackTrack == nil || miniTrack.trackID.length == 0) {
        return NO;
    }

    NSString *identifier = playbackTrack.identifier ?: @"";
    if ([identifier hasPrefix:SonoraMiniStreamingPlaceholderPrefix]) {
        NSString *trackID = [identifier substringFromIndex:SonoraMiniStreamingPlaceholderPrefix.length];
        return [trackID isEqualToString:miniTrack.trackID];
    }

    NSString *playbackTitle = SonoraNormalizedSearchText(playbackTrack.title ?: @"");
    NSString *miniTitle = SonoraNormalizedSearchText(miniTrack.title ?: @"");
    if (playbackTitle.length == 0 || miniTitle.length == 0 || ![playbackTitle isEqualToString:miniTitle]) {
        return NO;
    }

    NSString *playbackArtist = SonoraNormalizedSearchText(playbackTrack.artist ?: @"");
    NSString *miniArtist = SonoraNormalizedSearchText(miniTrack.artists ?: @"");
    if (miniArtist.length == 0 || playbackArtist.length == 0) {
        return YES;
    }
    return ([playbackArtist containsString:miniArtist] ||
            [miniArtist containsString:playbackArtist]);
}

- (void)handlePlaybackChanged {
    [self.tableView reloadData];
    [self updatePlayButtonState];
    [self updateSleepButton];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return self.tracks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SonoraTrackCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MiniStreamingArtistTrackCell" forIndexPath:indexPath];
    if (indexPath.row >= self.tracks.count) {
        return cell;
    }

    SonoraMiniStreamingTrack *track = self.tracks[indexPath.row];
    UIImage *artwork = [self cachedArtworkForTrack:track];
    [self loadArtworkIfNeededForTrack:track];
    SonoraTrack *displayTrack = [self displayTrackForMiniTrack:track artwork:artwork];
    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    BOOL isCurrent = [self isPlaybackTrack:playback.currentTrack matchingMiniTrack:track];
    [cell configureWithTrack:displayTrack
                   isCurrent:isCurrent
      showsPlaybackIndicator:(isCurrent && playback.isPlaying)];
    cell.accessoryType = UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row < 0 || indexPath.row >= self.tracks.count) {
        return;
    }
    SonoraMiniStreamingTrack *track = self.tracks[indexPath.row];
    if (self.installHandler != nil) {
        UIImage *artwork = [self cachedArtworkForTrack:track];
        self.installHandler(track, self.tracks, indexPath.row, artwork);
    }
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView == self.tableView) {
        [self updateNavigationTitleVisibility];
    }
}

@end

#pragma mark - Music

typedef NS_ENUM(NSInteger, SonoraSearchSectionType) {
    SonoraSearchSectionTypeMiniStreaming = 0,
    SonoraSearchSectionTypePlaylists = 1,
    SonoraSearchSectionTypeArtists = 2,
    SonoraSearchSectionTypeTracks = 3,
};


@interface SonoraMusicViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating, UICollectionViewDataSource, UICollectionViewDelegate, UIDocumentPickerDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UICollectionView *searchCollectionView;
@property (nonatomic, strong) SonoraMiniStreamingClient *miniStreamingClient;
@property (nonatomic, copy) NSArray<SonoraTrack *> *tracks;
@property (nonatomic, copy) NSArray<SonoraTrack *> *filteredTracks;
@property (nonatomic, copy) NSArray<SonoraPlaylist *> *playlists;
@property (nonatomic, copy) NSArray<SonoraPlaylist *> *filteredPlaylists;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *artistResults;
@property (nonatomic, copy) NSArray<SonoraMiniStreamingTrack *> *miniStreamingTracks;
@property (nonatomic, copy) NSArray<SonoraMiniStreamingArtist *> *miniStreamingArtists;
@property (nonatomic, assign) BOOL miniStreamingArtistsSectionVisible;
@property (nonatomic, copy) NSArray<NSNumber *> *visibleSections;
@property (nonatomic, copy) NSString *searchQuery;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *miniStreamingArtworkCache;
@property (nonatomic, strong) NSMutableSet<NSString *> *miniStreamingArtworkLoadingURLs;
@property (nonatomic, strong) NSMutableSet<NSString *> *miniStreamingInstallingTrackIDs;
@property (nonatomic, copy) NSArray<SonoraMiniStreamingTrack *> *miniStreamingPlaybackQueue;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary<NSString *, id> *> *miniStreamingResolvedPayloadByTrackID;
@property (nonatomic, strong) NSMutableDictionary<NSString *, SonoraTrack *> *miniStreamingInstalledTracksByTrackID;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *miniStreamingInstalledPathsByTrackID;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSURLSessionDownloadTask *> *miniStreamingDownloadTasksByTrackID;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *miniStreamingResolveRetryAfterByTrackID;
@property (nonatomic, copy, nullable) NSString *miniStreamingActiveTrackID;
@property (nonatomic, copy, nullable) NSString *miniStreamingCurrentPlaybackTrackID;
@property (nonatomic, strong) UITapGestureRecognizer *searchKeyboardDismissTapRecognizer;
@property (nonatomic, assign) BOOL searchControllerAttached;
@property (nonatomic, assign) BOOL multiSelectMode;
@property (nonatomic, assign) NSUInteger miniStreamingQueryToken;
@property (nonatomic, assign) NSUInteger reloadTracksRequestToken;
@property (nonatomic, assign) NSUInteger reloadPlaylistsRequestToken;
@property (nonatomic, assign) BOOL playbackSurfaceRefreshScheduled;
@property (nonatomic, copy, nullable) dispatch_block_t miniStreamingSearchDebounceWorkItem;
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *selectedTrackIDs;
@property (nonatomic, strong) UILongPressGestureRecognizer *selectionLongPressRecognizer;

@end

@implementation SonoraMusicViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    NSString *pageTitle = self.musicOnlyMode ? @"Music" : @"Search";
    self.title = nil;
    self.tabBarItem.title = @"";
    self.tabBarItem.titlePositionAdjustment = UIOffsetMake(0.0, 1000.0);
    self.navigationItem.title = nil;
    self.navigationItem.titleView = nil;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:SonoraWhiteSectionTitleLabel(pageTitle)];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    if (self.musicOnlyMode) {
        self.navigationItem.hidesBackButton = YES;
    }

    if (self.musicOnlyMode) {
        UISwipeGestureRecognizer *swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleDismissSwipe)];
        swipeRight.direction = UISwipeGestureRecognizerDirectionRight;
        [self.view addGestureRecognizer:swipeRight];
    }

    [self setupTableView];
    [self setupSearchCollectionView];
    [self setupSearch];
    [self updatePresentationMode];
    self.multiSelectMode = NO;
    self.selectedTrackIDs = [NSMutableOrderedSet orderedSet];
    self.miniStreamingClient = [[SonoraMiniStreamingClient alloc] init];
    self.miniStreamingTracks = @[];
    self.miniStreamingArtists = @[];
    self.miniStreamingArtistsSectionVisible = self.miniStreamingClient.artistsSectionEnabled;
    self.miniStreamingArtworkCache = [[NSCache alloc] init];
    self.miniStreamingArtworkCache.countLimit = 128;
    self.miniStreamingArtworkCache.totalCostLimit = 96 * 1024 * 1024;
    self.miniStreamingArtworkLoadingURLs = [NSMutableSet set];
    self.miniStreamingInstallingTrackIDs = [NSMutableSet set];
    self.miniStreamingResolvedPayloadByTrackID = [NSMutableDictionary dictionary];
    self.miniStreamingPlaybackQueue = @[];
    self.miniStreamingInstalledTracksByTrackID = [NSMutableDictionary dictionary];
    self.miniStreamingInstalledPathsByTrackID = [NSMutableDictionary dictionary];
    self.miniStreamingDownloadTasksByTrackID = [NSMutableDictionary dictionary];
    self.miniStreamingResolveRetryAfterByTrackID = [NSMutableDictionary dictionary];
    self.miniStreamingActiveTrackID = nil;
    self.miniStreamingCurrentPlaybackTrackID = nil;
    self.miniStreamingQueryToken = 0;
    [self loadMiniStreamingInstalledTrackMappingsFromDefaults];

    [self refreshNavigationItemsForMusicSelectionState];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handlePlaybackChanged)
                                               name:SonoraPlaybackStateDidChangeNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(reloadTracks)
                                               name:UIApplicationWillEnterForegroundNotification
                                             object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handlePlaylistsChanged)
                                               name:SonoraPlaylistsDidChangeNotification
                                             object:nil];

    [self reloadTracks];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.musicOnlyMode) {
        self.navigationItem.hidesBackButton = YES;
        self.navigationController.interactivePopGestureRecognizer.enabled = YES;
        self.navigationController.interactivePopGestureRecognizer.delegate = nil;
    }
    [self refreshNavigationItemsForMusicSelectionState];
    [self updatePresentationMode];
    [self updateSearchControllerAttachment];
    [self reloadVisibleContentViews];
}

- (void)handleDismissSwipe {
    if (self.navigationController) {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (void)setupTableView {
    UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    tableView.translatesAutoresizingMaskIntoConstraints = NO;
    tableView.dataSource = self;
    tableView.delegate = self;
    tableView.rowHeight = 54.0;
    tableView.alwaysBounceVertical = YES;
    tableView.sectionHeaderHeight = 0.0;
    tableView.sectionFooterHeight = 0.0;
    tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    if (@available(iOS 15.0, *)) {
        tableView.sectionHeaderTopPadding = 0.0;
    }
    [tableView registerClass:SonoraTrackCell.class forCellReuseIdentifier:@"MusicTrackCell"];
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                                                             action:@selector(handleTrackLongPress:)];
    [tableView addGestureRecognizer:longPress];
    self.selectionLongPressRecognizer = longPress;

    self.tableView = tableView;
    [self.view addSubview:tableView];

    [NSLayoutConstraint activateConstraints:@[
        [tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)setupSearchCollectionView {
    UICollectionViewCompositionalLayout *layout = [self buildSearchCollectionLayout];
    UICollectionView *collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    collectionView.backgroundColor = UIColor.systemBackgroundColor;
    collectionView.alwaysBounceVertical = YES;
    collectionView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    collectionView.dataSource = self;
    collectionView.delegate = self;

    [collectionView registerClass:SonoraMusicSearchCardCell.class forCellWithReuseIdentifier:SonoraMusicSearchCardCellReuseID];
    [collectionView registerClass:SonoraMiniStreamingListCell.class forCellWithReuseIdentifier:SonoraMiniStreamingListCellReuseID];
    [collectionView registerClass:SonoraMusicSearchHeaderView.class
       forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
              withReuseIdentifier:SonoraMusicSearchHeaderReuseID];
    UITapGestureRecognizer *dismissTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleSearchBackgroundTap)];
    dismissTap.cancelsTouchesInView = NO;
    [collectionView addGestureRecognizer:dismissTap];
    self.searchKeyboardDismissTapRecognizer = dismissTap;

    self.searchCollectionView = collectionView;
    [self.view addSubview:collectionView];

    [NSLayoutConstraint activateConstraints:@[
        [collectionView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)updatePresentationMode {
    self.tableView.hidden = !self.musicOnlyMode;
    self.searchCollectionView.hidden = self.musicOnlyMode;
}

- (UICollectionViewCompositionalLayout *)buildSearchCollectionLayout {
    __weak typeof(self) weakSelf = self;
    return [[UICollectionViewCompositionalLayout alloc] initWithSectionProvider:^NSCollectionLayoutSection * _Nullable(NSInteger sectionIndex,
                                                                                                                        __unused id<NSCollectionLayoutEnvironment> _Nonnull environment) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return nil;
        }
        SonoraSearchSectionType sectionType = [strongSelf sectionTypeForIndex:sectionIndex];
        return [strongSelf searchSectionLayoutForSectionType:sectionType];
    }];
}

- (NSCollectionLayoutSection *)searchSectionLayoutForSectionType:(SonoraSearchSectionType)sectionType {
    BOOL isSpotifyListSection = (sectionType == SonoraSearchSectionTypeMiniStreaming);
    NSCollectionLayoutSize *itemSize = nil;
    NSCollectionLayoutSize *groupSize = nil;
    CGFloat interGroupSpacing = 0.0;
    NSDirectionalEdgeInsets sectionInsets = NSDirectionalEdgeInsetsZero;
    UICollectionLayoutSectionOrthogonalScrollingBehavior scrolling = UICollectionLayoutSectionOrthogonalScrollingBehaviorNone;

    if (isSpotifyListSection) {
        itemSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                                  heightDimension:[NSCollectionLayoutDimension absoluteDimension:54.0]];
        groupSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                                   heightDimension:[NSCollectionLayoutDimension absoluteDimension:54.0]];
        interGroupSpacing = 0.0;
        sectionInsets = NSDirectionalEdgeInsetsMake(8.0, 0.0, 12.0, 0.0);
        scrolling = UICollectionLayoutSectionOrthogonalScrollingBehaviorNone;
    } else {
        itemSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:184.0]
                                                  heightDimension:[NSCollectionLayoutDimension absoluteDimension:246.0]];
        groupSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:184.0]
                                                   heightDimension:[NSCollectionLayoutDimension absoluteDimension:246.0]];
        interGroupSpacing = 12.0;
        sectionInsets = NSDirectionalEdgeInsetsMake(10.0, 18.0, 12.0, 18.0);
        scrolling = UICollectionLayoutSectionOrthogonalScrollingBehaviorContinuousGroupLeadingBoundary;
    }

    NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];

    NSCollectionLayoutGroup *group = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize subitems:@[item]];

    NSCollectionLayoutSection *section = [NSCollectionLayoutSection sectionWithGroup:group];
    section.interGroupSpacing = interGroupSpacing;
    section.contentInsets = sectionInsets;
    section.orthogonalScrollingBehavior = scrolling;

    NSCollectionLayoutSize *headerSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                                                         heightDimension:[NSCollectionLayoutDimension estimatedDimension:36.0]];
    NSCollectionLayoutBoundarySupplementaryItem *header = [NSCollectionLayoutBoundarySupplementaryItem
                                                           boundarySupplementaryItemWithLayoutSize:headerSize
                                                           elementKind:UICollectionElementKindSectionHeader
                                                           alignment:NSRectAlignmentTop];
    header.contentInsets = NSDirectionalEdgeInsetsMake(0.0, 18.0, 0.0, 18.0);
    section.boundarySupplementaryItems = @[header];
    return section;
}

- (void)setupSearch {
    NSString *placeholder = self.musicOnlyMode ? @"Search Music" : @"Search Spotify";
    self.searchController = SonoraBuildSearchController(self, placeholder);
    self.definesPresentationContext = YES;
    if (self.musicOnlyMode) {
        self.navigationItem.searchController = nil;
        self.navigationItem.hidesSearchBarWhenScrolling = YES;
        self.searchControllerAttached = NO;
    } else {
        self.navigationItem.searchController = self.searchController;
        self.navigationItem.hidesSearchBarWhenScrolling = NO;
        self.searchControllerAttached = YES;
    }
}

- (void)updateSearchControllerAttachment {
    if (!self.musicOnlyMode) {
        if (!self.searchControllerAttached || self.navigationItem.searchController != self.searchController) {
            self.searchControllerAttached = YES;
            SonoraApplySearchControllerAttachment(self.navigationItem,
                                              self.navigationController.navigationBar,
                                              self.searchController,
                                              YES,
                                              (self.view.window != nil));
        }
        return;
    }

    UIScrollView *targetScroll = self.musicOnlyMode ? self.tableView : self.searchCollectionView;
    BOOL shouldAttach = SonoraShouldAttachSearchController(self.searchControllerAttached,
                                                       self.searchController,
                                                       targetScroll,
                                                       SonoraSearchRevealThreshold);
    if (shouldAttach == self.searchControllerAttached) {
        return;
    }

    self.searchControllerAttached = shouldAttach;
    SonoraApplySearchControllerAttachment(self.navigationItem,
                                      self.navigationController.navigationBar,
                                      self.searchController,
                                      shouldAttach,
                                      (self.view.window != nil));
}

- (void)applySearchFilterAndReload {
    NSString *normalizedQuery = SonoraNormalizedSearchText(self.searchQuery);
    self.playlists = SonoraPlaylistStore.sharedStore.playlists ?: @[];
    if (self.musicOnlyMode) {
        self.filteredTracks = SonoraFilterTracksByQuery(self.tracks, self.searchQuery);
        self.filteredPlaylists = @[];
        self.artistResults = @[];
        self.miniStreamingTracks = @[];
        self.miniStreamingArtists = @[];
    } else {
        NSArray<SonoraTrack *> *queryTracks = SonoraFilterTracksByQuery(self.tracks, self.searchQuery);
        if (normalizedQuery.length == 0) {
            NSArray<SonoraTrack *> *affinityTracks = [SonoraTrackAnalyticsStore.sharedStore tracksSortedByAffinity:self.tracks] ?: @[];
            queryTracks = affinityTracks.count > 0 ? affinityTracks : self.tracks;
        }
        if (queryTracks.count > 24) {
            self.filteredTracks = [queryTracks subarrayWithRange:NSMakeRange(0, 24)];
        } else {
            self.filteredTracks = queryTracks;
        }

        self.filteredPlaylists = SonoraFilterPlaylistsByQuery(self.playlists, self.searchQuery);
        if (self.filteredPlaylists.count > 10) {
            self.filteredPlaylists = [self.filteredPlaylists subarrayWithRange:NSMakeRange(0, 10)];
        }
        self.artistResults = @[];
    }

    NSMutableArray<NSNumber *> *sections = [NSMutableArray array];
    if (self.musicOnlyMode) {
        [sections addObject:@(SonoraSearchSectionTypeTracks)];
    } else {
        if (self.miniStreamingTracks.count > 0) {
            [sections addObject:@(SonoraSearchSectionTypeMiniStreaming)];
        }
        if (self.miniStreamingArtists.count > 0) {
            [sections addObject:@(SonoraSearchSectionTypeArtists)];
        }
        if (self.filteredPlaylists.count > 0) {
            [sections addObject:@(SonoraSearchSectionTypePlaylists)];
        }
        if (self.filteredTracks.count > 0) {
            [sections addObject:@(SonoraSearchSectionTypeTracks)];
        }
    }
    self.visibleSections = [sections copy];

    [self reloadVisibleContentViews];
    [self updateEmptyState];
}

- (void)reloadVisibleContentViews {
    if (self.tableView != nil && !self.tableView.hidden) {
        [self.tableView reloadData];
    }
    if (self.searchCollectionView != nil && !self.searchCollectionView.hidden) {
        [self.searchCollectionView reloadData];
    }
}

- (void)schedulePlaybackStateSurfaceRefresh {
    if (self.playbackSurfaceRefreshScheduled) {
        return;
    }
    self.playbackSurfaceRefreshScheduled = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        strongSelf.playbackSurfaceRefreshScheduled = NO;
        if (strongSelf.viewIfLoaded.window == nil) {
            return;
        }
        [strongSelf reloadVisibleContentViews];
        [strongSelf ensureCurrentMiniStreamingPlaceholderIsInstalling];
    });
}

- (void)updateEmptyState {
    BOOL hasAnyResult = (self.filteredTracks.count > 0 ||
                         self.filteredPlaylists.count > 0 ||
                         self.miniStreamingTracks.count > 0 ||
                         self.miniStreamingArtists.count > 0);
    if (hasAnyResult) {
        self.tableView.backgroundView = nil;
        self.searchCollectionView.backgroundView = nil;
        return;
    }

    UILabel *label = [[UILabel alloc] init];
    label.textColor = UIColor.secondaryLabelColor;
    label.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    if (self.musicOnlyMode) {
        if (self.tracks.count == 0) {
            label.text = @"No music files in On My iPhone/Sonora/Sonora";
        } else {
            label.text = @"No search results.";
        }
        self.tableView.backgroundView = label;
        self.searchCollectionView.backgroundView = nil;
    } else {
        NSString *normalizedQuery = SonoraNormalizedSearchText(self.searchQuery);
        if (normalizedQuery.length == 0) {
            label.text = @"Use Search above to find Spotify tracks and artists.";
        } else {
            label.text = @"No search results.";
        }
        self.searchCollectionView.backgroundView = label;
        self.tableView.backgroundView = nil;
    }
}

- (void)loadMiniStreamingInstalledTrackMappingsFromDefaults {
    [self.miniStreamingInstalledPathsByTrackID removeAllObjects];
    NSDictionary *stored = [NSUserDefaults.standardUserDefaults dictionaryForKey:SonoraMiniStreamingInstalledTrackMapDefaultsKey];
    if (![stored isKindOfClass:NSDictionary.class]) {
        return;
    }
    [stored enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull rawTrackID, id  _Nonnull rawPath, __unused BOOL * _Nonnull stop) {
        if (![rawTrackID isKindOfClass:NSString.class] || ![rawPath isKindOfClass:NSString.class]) {
            return;
        }
        NSString *trackID = SonoraTrimmedStringValue((NSString *)rawTrackID);
        NSString *path = SonoraTrimmedStringValue((NSString *)rawPath);
        if (trackID.length == 0 || path.length == 0) {
            return;
        }
        self.miniStreamingInstalledPathsByTrackID[trackID] = path;
    }];
}

- (void)persistMiniStreamingInstalledTrackMappings {
    NSDictionary<NSString *, NSString *> *payload = [self.miniStreamingInstalledPathsByTrackID copy] ?: @{};
    [NSUserDefaults.standardUserDefaults setObject:payload forKey:SonoraMiniStreamingInstalledTrackMapDefaultsKey];
}

- (void)rememberMiniStreamingInstalledTrack:(SonoraTrack *)installedTrack trackID:(NSString *)trackID {
    if (installedTrack == nil || trackID.length == 0) {
        return;
    }
    self.miniStreamingInstalledTracksByTrackID[trackID] = installedTrack;
    if (installedTrack.identifier.length > 0) {
        self.miniStreamingInstalledPathsByTrackID[trackID] = installedTrack.identifier;
    } else if (installedTrack.url.path.length > 0) {
        self.miniStreamingInstalledPathsByTrackID[trackID] = installedTrack.url.path;
    } else {
        [self.miniStreamingInstalledPathsByTrackID removeObjectForKey:trackID];
    }
    [self persistMiniStreamingInstalledTrackMappings];
}

- (NSArray<NSString *> *)miniStreamingArtistTokensFromText:(NSString *)artistText {
    NSString *normalized = SonoraNormalizedSearchText(artistText ?: @"");
    if (normalized.length == 0) {
        return @[];
    }
    NSCharacterSet *splitSet = [NSCharacterSet characterSetWithCharactersInString:@",/&;|"];
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    NSArray<NSString *> *parts = [normalized componentsSeparatedByCharactersInSet:splitSet];
    for (NSString *part in parts) {
        NSString *token = [part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (token.length >= 2) {
            [tokens addObject:token];
        }
    }
    return [tokens copy];
}

- (nullable SonoraTrack *)installedLibraryTrackMatchingMiniStreamingTrack:(SonoraMiniStreamingTrack *)track {
    if (track == nil) {
        return nil;
    }
    NSString *targetTitle = SonoraNormalizedSearchText(track.title ?: @"");
    if (targetTitle.length == 0) {
        return nil;
    }
    NSString *targetArtist = SonoraNormalizedSearchText(track.artists ?: @"");
    NSArray<NSString *> *artistTokens = [self miniStreamingArtistTokensFromText:track.artists ?: @""];
    SonoraTrack *titleOnlyFallback = nil;
    for (SonoraTrack *candidate in self.tracks) {
        NSString *candidateTitle = SonoraNormalizedSearchText(candidate.title ?: @"");
        if (candidateTitle.length == 0 || ![candidateTitle isEqualToString:targetTitle]) {
            continue;
        }
        if (targetArtist.length == 0) {
            return candidate;
        }
        NSString *candidateArtist = SonoraNormalizedSearchText(candidate.artist ?: @"");
        if (candidateArtist.length == 0) {
            if (titleOnlyFallback == nil) {
                titleOnlyFallback = candidate;
            }
            continue;
        }
        if ([candidateArtist containsString:targetArtist] || [targetArtist containsString:candidateArtist]) {
            return candidate;
        }
        for (NSString *token in artistTokens) {
            if (token.length > 1 && [candidateArtist containsString:token]) {
                return candidate;
            }
        }
        if (titleOnlyFallback == nil) {
            titleOnlyFallback = candidate;
        }
    }
    return titleOnlyFallback;
}

- (void)rehydrateMiniStreamingInstalledTracksFromLibrary {
    NSMutableDictionary<NSString *, SonoraTrack *> *resolved = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSString *> *validPaths = [NSMutableDictionary dictionary];

    for (NSString *trackID in self.miniStreamingInstalledPathsByTrackID) {
        NSString *path = SonoraTrimmedStringValue(self.miniStreamingInstalledPathsByTrackID[trackID]);
        if (trackID.length == 0 || path.length == 0) {
            continue;
        }
        SonoraTrack *track = [SonoraLibraryManager.sharedManager trackForIdentifier:path];
        if (track == nil && [NSFileManager.defaultManager fileExistsAtPath:path]) {
            track = [self installedTrackForDestinationURL:[NSURL fileURLWithPath:path]];
        }
        if (track == nil) {
            continue;
        }
        resolved[trackID] = track;
        if (track.identifier.length > 0) {
            validPaths[trackID] = track.identifier;
        } else if (track.url.path.length > 0) {
            validPaths[trackID] = track.url.path;
        }
    }

    [self.miniStreamingInstalledTracksByTrackID removeAllObjects];
    [self.miniStreamingInstalledTracksByTrackID addEntriesFromDictionary:resolved];

    NSDictionary<NSString *, NSString *> *currentPaths = [self.miniStreamingInstalledPathsByTrackID copy] ?: @{};
    if (![currentPaths isEqualToDictionary:validPaths]) {
        [self.miniStreamingInstalledPathsByTrackID removeAllObjects];
        [self.miniStreamingInstalledPathsByTrackID addEntriesFromDictionary:validPaths];
        [self persistMiniStreamingInstalledTrackMappings];
    }
}

- (nullable SonoraTrack *)knownInstalledMiniStreamingTrackForTrack:(SonoraMiniStreamingTrack *)track {
    if (track == nil || track.trackID.length == 0) {
        return nil;
    }
    SonoraTrack *installedTrack = self.miniStreamingInstalledTracksByTrackID[track.trackID];
    if (installedTrack != nil && installedTrack.url.path.length > 0 &&
        [NSFileManager.defaultManager fileExistsAtPath:installedTrack.url.path]) {
        return installedTrack;
    }

    NSString *savedPath = SonoraTrimmedStringValue(self.miniStreamingInstalledPathsByTrackID[track.trackID]);
    if (savedPath.length > 0) {
        SonoraTrack *savedTrack = [SonoraLibraryManager.sharedManager trackForIdentifier:savedPath];
        if (savedTrack == nil && [NSFileManager.defaultManager fileExistsAtPath:savedPath]) {
            savedTrack = [self installedTrackForDestinationURL:[NSURL fileURLWithPath:savedPath]];
        }
        if (savedTrack != nil) {
            [self rememberMiniStreamingInstalledTrack:savedTrack trackID:track.trackID];
            return savedTrack;
        }
        [self.miniStreamingInstalledPathsByTrackID removeObjectForKey:track.trackID];
        [self persistMiniStreamingInstalledTrackMappings];
    }

    SonoraTrack *matchedTrack = [self installedLibraryTrackMatchingMiniStreamingTrack:track];
    if (matchedTrack != nil) {
        [self rememberMiniStreamingInstalledTrack:matchedTrack trackID:track.trackID];
        return matchedTrack;
    }
    return nil;
}

- (void)reloadTracks {
    self.reloadTracksRequestToken += 1;
    NSUInteger requestToken = self.reloadTracksRequestToken;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<SonoraTrack *> *reloadedTracks = [SonoraLibraryManager.sharedManager reloadTracks] ?: @[];
        [SonoraPlaylistStore.sharedStore reloadPlaylists];
        NSArray<SonoraPlaylist *> *reloadedPlaylists = SonoraPlaylistStore.sharedStore.playlists ?: @[];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf == nil || requestToken != strongSelf.reloadTracksRequestToken) {
                return;
            }
            strongSelf.tracks = reloadedTracks;
            [strongSelf rehydrateMiniStreamingInstalledTracksFromLibrary];
            strongSelf.playlists = reloadedPlaylists;
            [strongSelf applySearchFilterAndReload];
        });
    });
}

- (void)handlePlaylistsChanged {
    self.reloadPlaylistsRequestToken += 1;
    NSUInteger requestToken = self.reloadPlaylistsRequestToken;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [SonoraPlaylistStore.sharedStore reloadPlaylists];
        NSArray<SonoraPlaylist *> *reloadedPlaylists = SonoraPlaylistStore.sharedStore.playlists ?: @[];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf == nil || requestToken != strongSelf.reloadPlaylistsRequestToken) {
                return;
            }
            strongSelf.playlists = reloadedPlaylists;
            [strongSelf applySearchFilterAndReload];
        });
    });
}

- (void)handlePlaybackChanged {
    NSString *currentMiniTrackID = [self miniStreamingTrackIDFromPlaybackTrack:SonoraPlaybackManager.sharedManager.currentTrack];
    NSString *previousMiniTrackID = self.miniStreamingCurrentPlaybackTrackID ?: @"";
    NSString *nextMiniTrackID = currentMiniTrackID ?: @"";
    if (![previousMiniTrackID isEqualToString:nextMiniTrackID]) {
        if (self.miniStreamingCurrentPlaybackTrackID.length > 0) {
            SonoraDiagnosticsLog(@"mini-streaming", [NSString stringWithFormat:@"cancel_download_on_track_change previous=%@ next=%@",
                                                     self.miniStreamingCurrentPlaybackTrackID,
                                                     nextMiniTrackID]);
            [self cancelMiniStreamingDownloadTaskForTrackID:self.miniStreamingCurrentPlaybackTrackID];
        }
    }
    self.miniStreamingCurrentPlaybackTrackID = nextMiniTrackID.length > 0 ? nextMiniTrackID : nil;

    [self schedulePlaybackStateSurfaceRefresh];
}

- (void)openPlayer {
    SonoraPlayerViewController *player = [[SonoraPlayerViewController alloc] init];
    player.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:player animated:YES];
}

- (void)searchButtonTapped {
    if (self.searchController == nil) {
        return;
    }

    if (!self.searchControllerAttached) {
        self.searchControllerAttached = YES;
        SonoraApplySearchControllerAttachment(self.navigationItem,
                                          self.navigationController.navigationBar,
                                          self.searchController,
                                          YES,
                                          (self.view.window != nil));
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        self.searchController.active = YES;
        [self.searchController.searchBar becomeFirstResponder];
    });
}

- (void)handleSearchBackgroundTap {
    if (self.musicOnlyMode) {
        return;
    }
    [self.searchController.searchBar resignFirstResponder];
}

- (void)refreshMiniStreamingForCurrentQuery {
    if (self.musicOnlyMode) {
        return;
    }

    if (self.miniStreamingSearchDebounceWorkItem != nil) {
        dispatch_block_cancel(self.miniStreamingSearchDebounceWorkItem);
        self.miniStreamingSearchDebounceWorkItem = nil;
    }

    NSString *querySnapshot = self.searchQuery ?: @"";
    __weak typeof(self) weakSelf = self;
    dispatch_block_t workItem = dispatch_block_create(0, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        strongSelf.miniStreamingSearchDebounceWorkItem = nil;
        [strongSelf refreshMiniStreamingForQuery:querySnapshot];
    });

    self.miniStreamingSearchDebounceWorkItem = workItem;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.30 * (NSTimeInterval)NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   workItem);
}

- (void)refreshMiniStreamingForQuery:(NSString *)query {
    if (self.musicOnlyMode) {
        return;
    }

    self.miniStreamingQueryToken += 1;
    NSUInteger currentToken = self.miniStreamingQueryToken;
    NSString *normalizedQuery = SonoraNormalizedSearchText(query);

    if (normalizedQuery.length < 2 || ![self.miniStreamingClient isConfigured]) {
        self.miniStreamingArtistsSectionVisible = self.miniStreamingClient.artistsSectionEnabled;
        if (self.miniStreamingTracks.count > 0 || self.miniStreamingArtists.count > 0) {
            self.miniStreamingTracks = @[];
            self.miniStreamingArtists = @[];
            [self applySearchFilterAndReload];
        }
        return;
    }

    __weak typeof(self) weakSelf = self;
    __block NSArray<SonoraMiniStreamingTrack *> *resolvedTracks = self.miniStreamingTracks ?: @[];
    __block NSArray<SonoraMiniStreamingArtist *> *resolvedArtists = self.miniStreamingArtists ?: @[];
    __block BOOL artistsSectionVisible = self.miniStreamingArtistsSectionVisible;
    __block BOOL tracksResolved = NO;
    __block BOOL artistsResolved = NO;

    void (^commitIfReady)(void) = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf.miniStreamingQueryToken != currentToken) {
            return;
        }
        if (!tracksResolved || !artistsResolved) {
            return;
        }
        strongSelf.miniStreamingTracks = resolvedTracks ?: @[];
        strongSelf.miniStreamingArtistsSectionVisible = artistsSectionVisible;
        strongSelf.miniStreamingArtists = artistsSectionVisible ? (resolvedArtists ?: @[]) : @[];
        [strongSelf applySearchFilterAndReload];
    };

    [self.miniStreamingClient searchTracks:normalizedQuery
                                     limit:SonoraMiniStreamingSearchLimit
                                completion:^(NSArray<SonoraMiniStreamingTrack *> *tracks, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf.miniStreamingQueryToken != currentToken) {
            return;
        }

        (void)error;
        resolvedTracks = tracks ?: @[];
        artistsSectionVisible = strongSelf.miniStreamingClient.artistsSectionEnabled;
        if (!artistsSectionVisible) {
            resolvedArtists = @[];
        }
        tracksResolved = YES;
        commitIfReady();
    }];

    [self.miniStreamingClient searchArtists:normalizedQuery
                                      limit:10
                                 completion:^(NSArray<SonoraMiniStreamingArtist *> *artists, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf.miniStreamingQueryToken != currentToken) {
            return;
        }

        (void)error;
        resolvedArtists = artists ?: @[];
        artistsSectionVisible = strongSelf.miniStreamingClient.artistsSectionEnabled;
        if (!artistsSectionVisible) {
            resolvedArtists = @[];
        }
        artistsResolved = YES;
        commitIfReady();
    }];
}

- (nullable UIImage *)cachedMiniStreamingArtworkForURL:(NSString *)urlString {
    if (urlString.length == 0) {
        return nil;
    }
    return [self.miniStreamingArtworkCache objectForKey:urlString];
}

- (void)loadMiniStreamingArtworkIfNeededForURL:(NSString *)urlString {
    if (urlString.length == 0 ||
        [self.miniStreamingArtworkCache objectForKey:urlString] != nil ||
        [self.miniStreamingArtworkLoadingURLs containsObject:urlString]) {
        return;
    }

    NSURL *url = [NSURL URLWithString:urlString];
    if (url == nil) {
        return;
    }

    [self.miniStreamingArtworkLoadingURLs addObject:urlString];
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:url
                                                            completionHandler:^(NSData * _Nullable data,
                                                                                NSURLResponse * _Nullable response,
                                                                                NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        UIImage *image = nil;
        if (error == nil && data.length > 0) {
            image = [UIImage imageWithData:data];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [strongSelf.miniStreamingArtworkLoadingURLs removeObject:urlString];
            if (image != nil) {
                [strongSelf.miniStreamingArtworkCache setObject:image forKey:urlString];
                [strongSelf reloadMiniStreamingRowsForArtworkURL:urlString];
            }
        });
    }];
    [task resume];
}

- (nullable UIImage *)cachedMiniStreamingArtworkForTrack:(SonoraMiniStreamingTrack *)track {
    return [self cachedMiniStreamingArtworkForURL:track.artworkURL];
}

- (void)loadMiniStreamingArtworkIfNeededForTrack:(SonoraMiniStreamingTrack *)track {
    [self loadMiniStreamingArtworkIfNeededForURL:track.artworkURL];
}

- (nullable NSString *)miniStreamingTrackIDFromPlaybackIdentifier:(NSString *)identifier {
    if (identifier.length == 0) {
        return nil;
    }
    if ([identifier hasPrefix:SonoraMiniStreamingPlaceholderPrefix]) {
        NSString *trackID = [identifier substringFromIndex:SonoraMiniStreamingPlaceholderPrefix.length];
        return trackID.length > 0 ? trackID : nil;
    }
    return nil;
}

- (nullable NSString *)miniStreamingTrackIDFromPlaybackTrack:(SonoraTrack * _Nullable)playbackTrack {
    if (playbackTrack == nil) {
        return nil;
    }

    __block NSString *trackIDFromIdentifier = [self miniStreamingTrackIDFromPlaybackIdentifier:playbackTrack.identifier ?: @""];
    if (trackIDFromIdentifier.length > 0) {
        return trackIDFromIdentifier;
    }

    [self.miniStreamingInstalledTracksByTrackID enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull trackID,
                                                                                     SonoraTrack * _Nonnull installedTrack,
                                                                                     BOOL * _Nonnull stop) {
        BOOL sameIdentifier = (installedTrack.identifier.length > 0 &&
                               [installedTrack.identifier isEqualToString:playbackTrack.identifier ?: @""]);
        BOOL samePath = (installedTrack.url.path.length > 0 &&
                         [installedTrack.url.path isEqualToString:playbackTrack.url.path ?: @""]);
        if (sameIdentifier || samePath) {
            trackIDFromIdentifier = trackID;
            *stop = YES;
        }
    }];

    return trackIDFromIdentifier.length > 0 ? trackIDFromIdentifier : nil;
}

- (BOOL)isMiniStreamingTrackIdentifierMiniPlaceholder:(NSString *)identifier {
    if (identifier.length == 0) {
        return NO;
    }
    if (![identifier hasPrefix:SonoraMiniStreamingPlaceholderPrefix]) {
        return NO;
    }
    return YES;
}

- (BOOL)isMiniStreamingPlaceholderTrack:(SonoraTrack * _Nullable)track {
    if (![self isMiniStreamingTrackIdentifierMiniPlaceholder:track.identifier ?: @""]) {
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

- (nullable NSURL *)miniStreamingDownloadURLFromPayload:(NSDictionary<NSString *, id> *)payload {
    NSString *downloadLink = SonoraTrimmedStringValue(payload[@"downloadLink"]);
    if (downloadLink.length == 0) {
        downloadLink = SonoraTrimmedStringValue(payload[@"mediaUrl"]);
    }
    if (downloadLink.length == 0) {
        downloadLink = SonoraTrimmedStringValue(payload[@"link"]);
    }
    if (downloadLink.length == 0) {
        downloadLink = SonoraTrimmedStringValue(payload[@"url"]);
    }
    if (downloadLink.length == 0) {
        return nil;
    }

    NSURL *url = [NSURL URLWithString:downloadLink];
    if (url == nil) {
        NSString *encoded = [downloadLink stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLFragmentAllowedCharacterSet];
        if (encoded.length > 0) {
            url = [NSURL URLWithString:encoded];
        }
    }
    if (url == nil) {
        return nil;
    }
    NSString *scheme = SonoraTrimmedStringValue(url.scheme).lowercaseString;
    if (scheme.length == 0) {
        return nil;
    }
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        return nil;
    }
    return url;
}

- (BOOL)isUsableMiniStreamingPayload:(NSDictionary<NSString *, id> * _Nullable)payload {
    return [self miniStreamingDownloadURLFromPayload:payload ?: @{}] != nil;
}

- (void)playMiniStreamingPlaybackQueueIfCurrentForTrack:(SonoraMiniStreamingTrack *)track {
    if (track == nil || track.trackID.length == 0) {
        return;
    }

    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    NSString *currentMiniTrackID = [self miniStreamingTrackIDFromPlaybackTrack:playback.currentTrack];
    BOOL targetIsActiveInstall = [self.miniStreamingActiveTrackID isEqualToString:track.trackID];
    if (currentMiniTrackID.length > 0 &&
        ![currentMiniTrackID isEqualToString:track.trackID] &&
        !targetIsActiveInstall) {
        return;
    }

    NSArray<SonoraMiniStreamingTrack *> *normalizedQueue = self.miniStreamingPlaybackQueue;
    if (normalizedQueue.count == 0) {
        normalizedQueue = @[];
    }

    NSMutableArray<SonoraTrack *> *playbackQueue = [NSMutableArray arrayWithCapacity:normalizedQueue.count];
    NSInteger startIndex = 0;
    for (NSUInteger index = 0; index < normalizedQueue.count; index += 1) {
        SonoraMiniStreamingTrack *queueTrack = normalizedQueue[index];
        if ([queueTrack.trackID isEqualToString:track.trackID]) {
            startIndex = (NSInteger)index;
        }
        [playbackQueue addObject:[self miniStreamingPlaybackTrackForMiniTrack:queueTrack]];
    }

    if (playbackQueue.count == 0) {
        [playbackQueue addObject:[self miniStreamingPlaybackTrackForMiniTrack:track]];
    }
    [playback setShuffleEnabled:NO];
    [playback playTracks:playbackQueue startIndex:startIndex];
    SonoraDiagnosticsLog(@"mini-streaming", [NSString stringWithFormat:@"play_queue_switched track=%@ start_index=%ld queue=%lu",
                                             track.trackID,
                                             (long)startIndex,
                                             (unsigned long)playbackQueue.count]);
}

- (void)cancelMiniStreamingDownloadTaskForTrackID:(NSString *)trackID {
    if (trackID.length == 0) {
        return;
    }

    NSURLSessionDownloadTask *downloadTask = self.miniStreamingDownloadTasksByTrackID[trackID];
    if (downloadTask != nil) {
        [downloadTask cancel];
        [self.miniStreamingDownloadTasksByTrackID removeObjectForKey:trackID];
        SonoraDiagnosticsLog(@"mini-streaming", [NSString stringWithFormat:@"download_cancel track=%@", trackID]);
    }
    [self.miniStreamingInstallingTrackIDs removeObject:trackID];
}

- (nullable SonoraMiniStreamingTrack *)miniStreamingTrackFromPlaybackQueueByTrackID:(NSString *)trackID {
    if (trackID.length == 0) {
        return nil;
    }

    for (SonoraMiniStreamingTrack *track in self.miniStreamingPlaybackQueue) {
        if ([track.trackID isEqualToString:trackID]) {
            return track;
        }
    }
    for (SonoraMiniStreamingTrack *track in self.miniStreamingTracks) {
        if ([track.trackID isEqualToString:trackID]) {
            return track;
        }
    }
    return nil;
}

- (SonoraTrack *)miniStreamingPlaceholderPlaybackTrackForTrack:(SonoraMiniStreamingTrack *)track {
    SonoraTrack *placeholderTrack = [[SonoraTrack alloc] init];
    placeholderTrack.identifier = [NSString stringWithFormat:@"%@%@", SonoraMiniStreamingPlaceholderPrefix, track.trackID];
    placeholderTrack.title = track.title.length > 0 ? track.title : @"Loading track...";
    placeholderTrack.artist = track.artists.length > 0 ? track.artists : @"Spotify";
    placeholderTrack.fileName = [NSString stringWithFormat:@"%@.placeholder", track.trackID];
    placeholderTrack.url = [NSURL fileURLWithPath:@"/dev/null"];
    placeholderTrack.duration = MAX(track.duration, 0.0);
    UIImage *artwork = [self cachedMiniStreamingArtworkForTrack:track];
    placeholderTrack.artwork = artwork ?: SonoraMiniStreamingPlaceholderArtwork(placeholderTrack.title, CGSizeMake(640.0, 640.0));
    return placeholderTrack;
}

- (SonoraTrack *)miniStreamingPlaybackTrackForMiniTrack:(SonoraMiniStreamingTrack *)miniTrack {
    SonoraTrack *installedTrack = self.miniStreamingInstalledTracksByTrackID[miniTrack.trackID];
    if (installedTrack == nil) {
        installedTrack = [self knownInstalledMiniStreamingTrackForTrack:miniTrack];
    }
    if (installedTrack != nil) {
        return installedTrack;
    }

    NSDictionary<NSString *, id> *payload = self.miniStreamingResolvedPayloadByTrackID[miniTrack.trackID];
    if ([self isUsableMiniStreamingPayload:payload]) {
        NSURL *downloadURL = [self miniStreamingDownloadURLFromPayload:payload];
        if (downloadURL != nil) {
            SonoraTrack *streamingTrack = [[SonoraTrack alloc] init];
            streamingTrack.identifier = [NSString stringWithFormat:@"%@%@", SonoraMiniStreamingPlaceholderPrefix, miniTrack.trackID];
            streamingTrack.title = miniTrack.title.length > 0 ? miniTrack.title : @"Track";
            streamingTrack.artist = miniTrack.artists.length > 0 ? miniTrack.artists : @"Spotify";
            streamingTrack.fileName = [NSString stringWithFormat:@"%@.mp3", miniTrack.trackID];
            streamingTrack.url = downloadURL;
            streamingTrack.duration = MAX(miniTrack.duration, 0.0);
            UIImage *artwork = [self cachedMiniStreamingArtworkForTrack:miniTrack];
            streamingTrack.artwork = artwork ?: SonoraMiniStreamingPlaceholderArtwork(streamingTrack.title, CGSizeMake(640.0, 640.0));
            return streamingTrack;
        }
    }

    return [self miniStreamingPlaceholderPlaybackTrackForTrack:miniTrack];
}

- (NSArray<SonoraMiniStreamingTrack *> *)miniStreamingQueueFromContext:(NSArray<SonoraMiniStreamingTrack *> *)queue
                                                          selectedTrack:(SonoraMiniStreamingTrack *)selectedTrack {
    NSMutableArray<SonoraMiniStreamingTrack *> *normalized = [NSMutableArray array];
    for (SonoraMiniStreamingTrack *candidate in queue) {
        if (![candidate isKindOfClass:SonoraMiniStreamingTrack.class] || candidate.trackID.length == 0) {
            continue;
        }
        [normalized addObject:candidate];
    }

    if (normalized.count == 0 && selectedTrack != nil && selectedTrack.trackID.length > 0) {
        [normalized addObject:selectedTrack];
    }
    return [normalized copy];
}

- (BOOL)miniStreamingPlaybackQueueMatchesMiniTracks:(NSArray<SonoraMiniStreamingTrack *> *)miniTracks {
    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    NSArray<SonoraTrack *> *queue = playback.currentQueue ?: @[];
    if (miniTracks.count == 0 || queue.count != miniTracks.count) {
        return NO;
    }

    for (NSUInteger index = 0; index < miniTracks.count; index += 1) {
        SonoraMiniStreamingTrack *expectedTrack = miniTracks[index];
        SonoraTrack *queueTrack = queue[index];
        NSString *queueTrackID = [self miniStreamingTrackIDFromPlaybackTrack:queueTrack];
        if (queueTrackID.length == 0 || ![queueTrackID isEqualToString:expectedTrack.trackID]) {
            return NO;
        }
    }
    return YES;
}

- (void)ensureCurrentMiniStreamingPlaceholderIsInstalling {
    if (self.musicOnlyMode) {
        return;
    }

    SonoraTrack *currentTrack = SonoraPlaybackManager.sharedManager.currentTrack;
    if (![self isMiniStreamingPlaceholderTrack:currentTrack]) {
        return;
    }

    NSString *trackID = [self miniStreamingTrackIDFromPlaybackIdentifier:currentTrack.identifier ?: @""];
    if (trackID.length == 0) {
        return;
    }

    SonoraMiniStreamingTrack *miniTrack = [self miniStreamingTrackFromPlaybackQueueByTrackID:trackID];
    if (miniTrack == nil) {
        return;
    }

    [self startMiniStreamingInstallIfNeededForTrack:miniTrack showErrorUI:NO];
}

- (void)reloadMiniStreamingRowsForArtworkURL:(NSString *)artworkURL {
    if (artworkURL.length == 0) {
        return;
    }
    if (self.searchCollectionView == nil || self.searchCollectionView.hidden) {
        return;
    }

    NSMutableArray<NSIndexPath *> *indexPaths = [NSMutableArray array];
    NSInteger miniTracksSectionIndex = NSNotFound;
    NSInteger artistsSectionIndex = NSNotFound;
    for (NSInteger section = 0; section < self.visibleSections.count; section += 1) {
        SonoraSearchSectionType sectionType = [self sectionTypeForIndex:section];
        if (sectionType == SonoraSearchSectionTypeMiniStreaming) {
            miniTracksSectionIndex = section;
        } else if (sectionType == SonoraSearchSectionTypeArtists) {
            artistsSectionIndex = section;
        }
    }

    if (miniTracksSectionIndex != NSNotFound) {
        for (NSInteger index = 0; index < self.miniStreamingTracks.count; index += 1) {
            SonoraMiniStreamingTrack *track = self.miniStreamingTracks[index];
            if ([track.artworkURL isEqualToString:artworkURL]) {
                [indexPaths addObject:[NSIndexPath indexPathForItem:index inSection:miniTracksSectionIndex]];
            }
        }
    }

    if (artistsSectionIndex != NSNotFound) {
        for (NSInteger index = 0; index < self.miniStreamingArtists.count; index += 1) {
            SonoraMiniStreamingArtist *artist = self.miniStreamingArtists[index];
            if ([artist.artworkURL isEqualToString:artworkURL]) {
                [indexPaths addObject:[NSIndexPath indexPathForItem:index inSection:artistsSectionIndex]];
            }
        }
    }

    if (indexPaths.count == 0) {
        return;
    }
    NSInteger sectionCount = [self.searchCollectionView numberOfSections];
    NSMutableArray<NSIndexPath *> *validIndexPaths = [NSMutableArray arrayWithCapacity:indexPaths.count];
    for (NSIndexPath *indexPath in indexPaths) {
        if (indexPath.section < 0 || indexPath.section >= sectionCount) {
            continue;
        }
        NSInteger itemCount = [self.searchCollectionView numberOfItemsInSection:indexPath.section];
        if (indexPath.item < 0 || indexPath.item >= itemCount) {
            continue;
        }
        [validIndexPaths addObject:indexPath];
    }
    if (validIndexPaths.count == 0) {
        return;
    }
    [self.searchCollectionView reloadItemsAtIndexPaths:validIndexPaths];
}

- (void)openPlayerIfNeeded {
    if (self.navigationController == nil) {
        return;
    }
    UIViewController *top = self.navigationController.topViewController;
    if ([top isKindOfClass:SonoraPlayerViewController.class]) {
        return;
    }
    [self openPlayer];
}

- (void)prepareMiniStreamingInstallForTrack:(SonoraMiniStreamingTrack *)track
                                      queue:(NSArray<SonoraMiniStreamingTrack *> *)queue
                                 startIndex:(NSInteger)startIndex {
    if (track == nil || track.trackID.length == 0) {
        return;
    }
    self.miniStreamingActiveTrackID = track.trackID;

    NSArray<SonoraMiniStreamingTrack *> *normalizedQueue = [self miniStreamingQueueFromContext:queue selectedTrack:track];
    self.miniStreamingPlaybackQueue = normalizedQueue;
    for (SonoraMiniStreamingTrack *queueTrack in normalizedQueue) {
        [self loadMiniStreamingArtworkIfNeededForTrack:queueTrack];
    }

    NSMutableArray<SonoraTrack *> *playbackQueue = [NSMutableArray arrayWithCapacity:normalizedQueue.count];
    for (SonoraMiniStreamingTrack *queueTrack in normalizedQueue) {
        [playbackQueue addObject:[self miniStreamingPlaybackTrackForMiniTrack:queueTrack]];
    }
    if (playbackQueue.count == 0) {
        [playbackQueue addObject:[self miniStreamingPlaybackTrackForMiniTrack:track]];
    }

    NSInteger resolvedStartIndex = NSNotFound;
    if (startIndex >= 0 && startIndex < (NSInteger)normalizedQueue.count) {
        SonoraMiniStreamingTrack *fromIndexTrack = normalizedQueue[(NSUInteger)startIndex];
        if ([fromIndexTrack.trackID isEqualToString:track.trackID]) {
            resolvedStartIndex = startIndex;
        }
    }
    if (resolvedStartIndex == NSNotFound) {
        for (NSUInteger idx = 0; idx < normalizedQueue.count; idx += 1) {
            if ([normalizedQueue[idx].trackID isEqualToString:track.trackID]) {
                resolvedStartIndex = (NSInteger)idx;
                break;
            }
        }
    }
    if (resolvedStartIndex == NSNotFound) {
        resolvedStartIndex = 0;
    }

    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    [playback setShuffleEnabled:NO];
    [playback playTracks:playbackQueue startIndex:resolvedStartIndex];
}

- (nullable SonoraTrack *)installedTrackForDestinationURL:(NSURL *)destinationURL {
    if (destinationURL.path.length == 0) {
        return nil;
    }

    SonoraTrack *track = [SonoraLibraryManager.sharedManager trackForIdentifier:destinationURL.path];
    if (track != nil) {
        return track;
    }

    for (SonoraTrack *candidate in self.tracks) {
        if ([candidate.identifier isEqualToString:destinationURL.path]) {
            return candidate;
        }
        if ([candidate.url.path isEqualToString:destinationURL.path]) {
            return candidate;
        }
    }
    return nil;
}

- (void)syncMiniStreamingPlaybackWithInstalledTrackAtURL:(NSURL *)destinationURL
                                                  trackID:(NSString *)trackID {
    if (destinationURL == nil || trackID.length == 0) {
        return;
    }

    SonoraTrack *installedTrack = [self installedTrackForDestinationURL:destinationURL];
    if (installedTrack == nil) {
        return;
    }
    [self rememberMiniStreamingInstalledTrack:installedTrack trackID:trackID];

    if ([self.miniStreamingActiveTrackID isEqualToString:trackID]) {
        self.miniStreamingActiveTrackID = nil;
    }

    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    SonoraTrack *currentPlaybackTrack = playback.currentTrack;
    NSString *currentTrackID = [self miniStreamingTrackIDFromPlaybackTrack:currentPlaybackTrack];
    if (![currentTrackID isEqualToString:trackID]) {
        return;
    }

    BOOL shouldDeferSwap = (currentPlaybackTrack != nil &&
                            currentPlaybackTrack.url != nil &&
                            !currentPlaybackTrack.url.isFileURL &&
                            playback.isPlaying);
    if (shouldDeferSwap) {
        SonoraDiagnosticsLog(@"mini-streaming", [NSString stringWithFormat:@"download_completed_defer_swap track=%@", trackID]);
        return;
    }

    BOOL wasPlaying = playback.isPlaying;
    NSTimeInterval restoreTime = playback.currentTime;

    SonoraMiniStreamingTrack *queueTrack = [self miniStreamingTrackFromPlaybackQueueByTrackID:trackID];
    if (queueTrack == nil || self.miniStreamingPlaybackQueue.count == 0) {
        [playback setShuffleEnabled:NO];
        [playback playTrack:installedTrack];
        if (restoreTime > 0.0) {
            [playback seekToTime:restoreTime];
        }
        if (!wasPlaying && playback.isPlaying) {
            [playback togglePlayPause];
        }
        return;
    }

    NSInteger startIndex = 0;
    NSMutableArray<SonoraTrack *> *playbackQueue = [NSMutableArray arrayWithCapacity:self.miniStreamingPlaybackQueue.count];
    for (NSUInteger idx = 0; idx < self.miniStreamingPlaybackQueue.count; idx += 1) {
        SonoraMiniStreamingTrack *miniTrack = self.miniStreamingPlaybackQueue[idx];
        if ([miniTrack.trackID isEqualToString:trackID]) {
            startIndex = (NSInteger)idx;
        }
        [playbackQueue addObject:[self miniStreamingPlaybackTrackForMiniTrack:miniTrack]];
    }
    [playback setShuffleEnabled:NO];
    [playback playTracks:playbackQueue startIndex:startIndex];
    if (restoreTime > 0.0) {
        [playback seekToTime:restoreTime];
    }
    if (!wasPlaying && playback.isPlaying) {
        [playback togglePlayPause];
    }
}

- (NSURL *)availableDestinationURLInDirectory:(NSURL *)directoryURL
                                     baseName:(NSString *)baseName
                                    extension:(NSString *)fileExtension {
    NSString *normalizedBaseName = SonoraSanitizedFileComponent(baseName);
    if (normalizedBaseName.length == 0) {
        normalizedBaseName = @"track";
    }

    NSString *normalizedExtension = SonoraTrimmedStringValue(fileExtension).lowercaseString;
    if (normalizedExtension.length == 0) {
        normalizedExtension = @"mp3";
    }

    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSURL *candidateURL = [directoryURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", normalizedBaseName, normalizedExtension]];
    if (![fileManager fileExistsAtPath:candidateURL.path]) {
        return candidateURL;
    }

    for (NSUInteger index = 2; index <= 999; index += 1) {
        NSString *candidateName = [NSString stringWithFormat:@"%@ (%lu).%@", normalizedBaseName, (unsigned long)index, normalizedExtension];
        candidateURL = [directoryURL URLByAppendingPathComponent:candidateName];
        if (![fileManager fileExistsAtPath:candidateURL.path]) {
            return candidateURL;
        }
    }

    NSString *uuid = [NSUUID UUID].UUIDString;
    return [directoryURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@.%@", normalizedBaseName, uuid, normalizedExtension]];
}

- (void)startMiniStreamingBackgroundDownloadFromURL:(NSURL *)downloadURL
                                             payload:(NSDictionary<NSString *, id> *)payload
                                             trackID:(NSString *)trackID {
    if (downloadURL == nil || trackID.length == 0) {
        return;
    }
    SonoraDiagnosticsLog(@"mini-streaming", [NSString stringWithFormat:@"download_start track=%@ url=%@",
                                             trackID,
                                             downloadURL.absoluteString ?: @""]);

    __weak typeof(self) weakSelf = self;
    NSURLSessionDownloadTask *existingTask = self.miniStreamingDownloadTasksByTrackID[trackID];
    if (existingTask != nil) {
        [existingTask cancel];
    }

    NSURLSessionDownloadTask *downloadTask = [NSURLSession.sharedSession downloadTaskWithURL:downloadURL
                                                                            completionHandler:^(NSURL * _Nullable location,
                                                                                                NSURLResponse * _Nullable response,
                                                                                                NSError * _Nullable downloadError) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        void (^cleanup)(void) = ^{
            [strongSelf.miniStreamingInstallingTrackIDs removeObject:trackID];
            [strongSelf.miniStreamingDownloadTasksByTrackID removeObjectForKey:trackID];
        };

        if (downloadError != nil || location == nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                cleanup();
                SonoraDiagnosticsLog(@"mini-streaming", [NSString stringWithFormat:@"download_failed track=%@ error=%@",
                                                         trackID,
                                                         downloadError.localizedDescription ?: @"unknown"]);
                if ([strongSelf.miniStreamingActiveTrackID isEqualToString:trackID]) {
                    strongSelf.miniStreamingActiveTrackID = nil;
                }
            });
            return;
        }

        NSURL *musicDirectoryURL = [SonoraLibraryManager.sharedManager musicDirectoryURL];
        NSString *title = SonoraSanitizedFileComponent(payload[@"title"]);
        if (title.length == 0) {
            title = trackID;
        }
        NSString *artist = SonoraSanitizedFileComponent(payload[@"artist"]);
        NSString *baseName = (artist.length > 0) ? [NSString stringWithFormat:@"%@ - %@", artist, title] : title;

        NSString *resolvedExtension = SonoraTrimmedStringValue(response.suggestedFilename.pathExtension);
        if (resolvedExtension.length == 0) {
            resolvedExtension = SonoraTrimmedStringValue(downloadURL.pathExtension);
        }
        if (resolvedExtension.length == 0) {
            resolvedExtension = @"mp3";
        }

        NSURL *destinationURL = [strongSelf availableDestinationURLInDirectory:musicDirectoryURL
                                                                       baseName:baseName
                                                                      extension:resolvedExtension];
        NSError *moveError = nil;
        BOOL moved = [NSFileManager.defaultManager moveItemAtURL:location toURL:destinationURL error:&moveError];
        if (!moved || moveError != nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                cleanup();
                SonoraDiagnosticsLog(@"mini-streaming", [NSString stringWithFormat:@"download_move_failed track=%@ error=%@",
                                                         trackID,
                                                         moveError.localizedDescription ?: @"unknown"]);
                if ([strongSelf.miniStreamingActiveTrackID isEqualToString:trackID]) {
                    strongSelf.miniStreamingActiveTrackID = nil;
                }
            });
            return;
        }

        SonoraMiniStreamingTrack *resolvedMiniTrack = [strongSelf miniStreamingTrackFromPlaybackQueueByTrackID:trackID];
        NSString *preferredTitle = SonoraTrimmedStringValue(resolvedMiniTrack.title);
        if (preferredTitle.length == 0) {
            preferredTitle = SonoraTrimmedStringValue(payload[@"title"]);
        }
        NSString *preferredArtist = SonoraTrimmedStringValue(resolvedMiniTrack.artists);
        if (preferredArtist.length == 0) {
            preferredArtist = SonoraTrimmedStringValue(payload[@"artist"]);
        }
        NSTimeInterval preferredDuration = resolvedMiniTrack.duration > 0.0
            ? resolvedMiniTrack.duration
            : ([payload[@"duration"] respondsToSelector:@selector(doubleValue)] ? [payload[@"duration"] doubleValue] : 0.0);

        NSString *artworkURLString = SonoraTrimmedStringValue(resolvedMiniTrack.artworkURL);
        if (artworkURLString.length == 0) {
            artworkURLString = SonoraTrimmedStringValue(payload[@"artworkURL"]);
        }
        UIImage *preferredArtwork = nil;
        if (artworkURLString.length > 0) {
            NSURL *artworkURL = [NSURL URLWithString:artworkURLString];
            if (artworkURL == nil) {
                NSString *encodedArtworkURLString = [artworkURLString stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLFragmentAllowedCharacterSet];
                artworkURL = [NSURL URLWithString:encodedArtworkURLString];
            }
            if (artworkURL != nil) {
                NSData *artworkData = [NSData dataWithContentsOfURL:artworkURL];
                if (artworkData.length > 0) {
                    preferredArtwork = [UIImage imageWithData:artworkData];
                }
            }
        }

        BOOL shouldRewriteMP3Metadata = (SonoraSettingsStreamingSearchEngine() == SonoraStreamingSearchEngineYouTube &&
                                         [resolvedExtension.lowercaseString isEqualToString:@"mp3"]);
        void (^finalizeInstall)(void) = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                cleanup();
                SonoraDiagnosticsLog(@"mini-streaming", [NSString stringWithFormat:@"download_completed track=%@ path=%@",
                                                         trackID,
                                                         destinationURL.path ?: @""]);
                SonoraTrack *registeredTrack = [SonoraLibraryManager.sharedManager registerDownloadedTrackAtURL:destinationURL
                                                                                                preferredTitle:preferredTitle
                                                                                               preferredArtist:preferredArtist
                                                                                              preferredArtwork:preferredArtwork
                                                                                             preferredDuration:preferredDuration];
                if (registeredTrack == nil) {
                    [strongSelf reloadTracks];
                }
                [strongSelf syncMiniStreamingPlaybackWithInstalledTrackAtURL:destinationURL
                                                                     trackID:trackID];
            });
        };

        if (shouldRewriteMP3Metadata) {
            [SonoraLibraryManager.sharedManager rewriteDownloadedMP3MetadataAtURL:destinationURL
                                                                   preferredTitle:preferredTitle
                                                                  preferredArtist:preferredArtist
                                                                 preferredArtwork:preferredArtwork
                                                                       completion:^(__unused BOOL success) {
                finalizeInstall();
            }];
        } else {
            finalizeInstall();
        }
    }];
    downloadTask.priority = NSURLSessionTaskPriorityLow;
    self.miniStreamingDownloadTasksByTrackID[trackID] = downloadTask;
    [downloadTask resume];
}

- (void)scheduleMiniStreamingBackgroundDownloadFromURL:(NSURL *)downloadURL
                                                payload:(NSDictionary<NSString *, id> *)payload
                                                trackID:(NSString *)trackID {
    if (downloadURL == nil || trackID.length == 0) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * (NSTimeInterval)NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        NSString *currentTrackID = strongSelf.miniStreamingCurrentPlaybackTrackID ?: @"";
        if (currentTrackID.length > 0 && ![currentTrackID isEqualToString:trackID]) {
            return;
        }
        [strongSelf startMiniStreamingBackgroundDownloadFromURL:downloadURL
                                                        payload:payload
                                                        trackID:trackID];
    });
}

- (void)stopMiniStreamingPlaceholderIfNeededForTrackID:(NSString *)trackID {
    if (trackID.length == 0) {
        return;
    }

    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    SonoraTrack *currentTrack = playback.currentTrack;
    NSString *currentTrackID = [self miniStreamingTrackIDFromPlaybackTrack:currentTrack];
    if (![currentTrackID isEqualToString:trackID]) {
        return;
    }
    if (![self isMiniStreamingPlaceholderTrack:currentTrack]) {
        return;
    }
    if (playback.isPlaying) {
        [playback togglePlayPause];
    }
}

- (BOOL)miniStreamingResolveCooldownActiveForTrackID:(NSString *)trackID {
    if (trackID.length == 0) {
        return NO;
    }

    NSDate *retryAfter = self.miniStreamingResolveRetryAfterByTrackID[trackID];
    if (retryAfter == nil) {
        return NO;
    }

    NSTimeInterval remaining = [retryAfter timeIntervalSinceNow];
    if (remaining <= 0.0) {
        [self.miniStreamingResolveRetryAfterByTrackID removeObjectForKey:trackID];
        return NO;
    }

    SonoraDiagnosticsLog(@"mini-streaming", [NSString stringWithFormat:@"resolve_skip_cooldown track=%@ wait=%.1f",
                                             trackID,
                                             remaining]);
    return YES;
}

- (void)startMiniStreamingInstallIfNeededForTrack:(SonoraMiniStreamingTrack *)track
                                       showErrorUI:(BOOL)showErrorUI {
    if (track == nil || track.trackID.length == 0) {
        return;
    }

    SonoraTrack *knownInstalledTrack = [self knownInstalledMiniStreamingTrackForTrack:track];
    if (knownInstalledTrack != nil && knownInstalledTrack.url.path.length > 0 &&
        [NSFileManager.defaultManager fileExistsAtPath:knownInstalledTrack.url.path]) {
        [self.miniStreamingInstallingTrackIDs removeObject:track.trackID];
        SonoraDiagnosticsLog(@"mini-streaming", [NSString stringWithFormat:@"play_installed track=%@", track.trackID]);
        [self syncMiniStreamingPlaybackWithInstalledTrackAtURL:knownInstalledTrack.url trackID:track.trackID];
        return;
    }

    NSDictionary<NSString *, id> *cachedPayload = self.miniStreamingResolvedPayloadByTrackID[track.trackID];
    if ([self isUsableMiniStreamingPayload:cachedPayload]) {
        [self.miniStreamingInstallingTrackIDs removeObject:track.trackID];
        SonoraDiagnosticsLog(@"mini-streaming", [NSString stringWithFormat:@"play_stream_cached_payload track=%@", track.trackID]);
        SonoraTrack *currentPlaybackTrack = SonoraPlaybackManager.sharedManager.currentTrack;
        NSString *currentTrackID = [self miniStreamingTrackIDFromPlaybackTrack:currentPlaybackTrack];
        BOOL shouldStartPlayback = showErrorUI ||
                                   [self isMiniStreamingPlaceholderTrack:currentPlaybackTrack] ||
                                   [currentTrackID isEqualToString:track.trackID];
        if (shouldStartPlayback) {
            [self playMiniStreamingPlaybackQueueIfCurrentForTrack:track];
        }
        NSURL *cachedDownloadURL = [self miniStreamingDownloadURLFromPayload:cachedPayload];
        if (cachedDownloadURL != nil &&
            (showErrorUI || SonoraSettingsAutoSaveStreamingSongsEnabled())) {
            [self scheduleMiniStreamingBackgroundDownloadFromURL:cachedDownloadURL
                                                         payload:cachedPayload
                                                         trackID:track.trackID];
        }
        return;
    } else if (cachedPayload != nil) {
        [self.miniStreamingResolvedPayloadByTrackID removeObjectForKey:track.trackID];
    }

    if ([self miniStreamingResolveCooldownActiveForTrackID:track.trackID]) {
        [self stopMiniStreamingPlaceholderIfNeededForTrackID:track.trackID];
        return;
    }

    if ([self.miniStreamingInstallingTrackIDs containsObject:track.trackID]) {
        return;
    }

    SonoraDiagnosticsLog(@"mini-streaming", [NSString stringWithFormat:@"resolve_start track=%@", track.trackID]);
    [self.miniStreamingInstallingTrackIDs addObject:track.trackID];
    __weak typeof(self) weakSelf = self;
    [self.miniStreamingClient resolveDownloadForTrackID:track.trackID
                                             completion:^(NSDictionary<NSString *,id> * _Nullable payload, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        if (error != nil || payload == nil) {
            [strongSelf.miniStreamingInstallingTrackIDs removeObject:track.trackID];
            strongSelf.miniStreamingResolveRetryAfterByTrackID[track.trackID] = [NSDate dateWithTimeIntervalSinceNow:20.0];
            SonoraDiagnosticsLog(@"mini-streaming", [NSString stringWithFormat:@"resolve_failed track=%@ error=%@",
                                                     track.trackID,
                                                     error.localizedDescription ?: @"unknown"]);
            if ([strongSelf.miniStreamingActiveTrackID isEqualToString:track.trackID]) {
                strongSelf.miniStreamingActiveTrackID = nil;
            }
            [strongSelf stopMiniStreamingPlaceholderIfNeededForTrackID:track.trackID];
            if (showErrorUI) {
                NSString *message = error.localizedDescription ?: @"Could not resolve download link.";
                SonoraPresentAlert(strongSelf, @"Install Failed", message);
            }
            return;
        }

        if (![strongSelf isUsableMiniStreamingPayload:payload]) {
            [strongSelf.miniStreamingInstallingTrackIDs removeObject:track.trackID];
            strongSelf.miniStreamingResolveRetryAfterByTrackID[track.trackID] = [NSDate dateWithTimeIntervalSinceNow:20.0];
            SonoraDiagnosticsLog(@"mini-streaming", [NSString stringWithFormat:@"resolve_invalid_payload track=%@",
                                                     track.trackID]);
            if ([strongSelf.miniStreamingActiveTrackID isEqualToString:track.trackID]) {
                strongSelf.miniStreamingActiveTrackID = nil;
            }
            [strongSelf stopMiniStreamingPlaceholderIfNeededForTrackID:track.trackID];
            if (showErrorUI) {
                SonoraPresentAlert(strongSelf, @"Install Failed", @"RapidAPI returned invalid download URL.");
            }
            return;
        }

        [strongSelf.miniStreamingInstallingTrackIDs removeObject:track.trackID];
        [strongSelf.miniStreamingResolveRetryAfterByTrackID removeObjectForKey:track.trackID];
        strongSelf.miniStreamingResolvedPayloadByTrackID[track.trackID] = payload;
        NSURL *downloadURL = [strongSelf miniStreamingDownloadURLFromPayload:payload];
        SonoraDiagnosticsLog(@"mini-streaming", [NSString stringWithFormat:@"resolve_succeeded track=%@ url=%@",
                                                 track.trackID,
                                                 downloadURL.absoluteString ?: @""]);
        SonoraTrack *currentPlaybackTrack = SonoraPlaybackManager.sharedManager.currentTrack;
        NSString *currentTrackID = [strongSelf miniStreamingTrackIDFromPlaybackTrack:currentPlaybackTrack];
        BOOL shouldStartPlayback = showErrorUI ||
                                   [strongSelf isMiniStreamingPlaceholderTrack:currentPlaybackTrack] ||
                                   [currentTrackID isEqualToString:track.trackID];
        if (shouldStartPlayback) {
            [strongSelf playMiniStreamingPlaybackQueueIfCurrentForTrack:track];
        }
        if (showErrorUI || SonoraSettingsAutoSaveStreamingSongsEnabled()) {
            [strongSelf scheduleMiniStreamingBackgroundDownloadFromURL:downloadURL
                                                               payload:payload
                                                               trackID:track.trackID];
        }
    }];
}

- (void)installMiniStreamingTrack:(SonoraMiniStreamingTrack *)track
                             queue:(NSArray<SonoraMiniStreamingTrack *> *)queue
                        startIndex:(NSInteger)startIndex
                  preferredArtwork:(UIImage * _Nullable)preferredArtwork {
    if (track == nil || track.trackID.length == 0) {
        return;
    }
    SonoraDiagnosticsLog(@"mini-streaming", [NSString stringWithFormat:@"install_tap track=%@", track.trackID]);
    [self.miniStreamingResolveRetryAfterByTrackID removeObjectForKey:track.trackID];

    if (![self.miniStreamingClient isConfigured]) {
        SonoraPresentAlert(self,
                       @"Mini Streaming Disabled",
                       @"Set BACKEND_BASE_URL in scheme env or Info.plist.");
        return;
    }

    if (preferredArtwork != nil && track.artworkURL.length > 0) {
        [self.miniStreamingArtworkCache setObject:preferredArtwork forKey:track.artworkURL];
    }
    NSArray<SonoraMiniStreamingTrack *> *normalizedQueue = [self miniStreamingQueueFromContext:queue selectedTrack:track];
    if (normalizedQueue.count == 0) {
        return;
    }
    [self prepareMiniStreamingInstallForTrack:track queue:normalizedQueue startIndex:startIndex];
    [self startMiniStreamingInstallIfNeededForTrack:track showErrorUI:YES];
}

- (void)addMusicTapped {
    if ([self isLibraryAtOrAboveStorageLimit]) {
        [self presentStorageLimitReachedAlert];
        return;
    }
    UTType *audioType = [UTType typeWithIdentifier:@"public.audio"];
    if (audioType == nil) {
        audioType = UTTypeAudio;
    }
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[audioType]
                                                                                                          asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = YES;
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    if (urls.count == 0) {
        return;
    }

    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSURL *musicDirectoryURL = [SonoraLibraryManager.sharedManager musicDirectoryURL];
    NSSet<NSString *> *allowedExtensions = SonoraSupportedAudioExtensions();
    NSUInteger importedCount = 0;
    NSUInteger failedCount = 0;
    NSUInteger skippedUnsupportedCount = 0;
    BOOL blockedByStorageLimit = NO;

    for (NSURL *sourceURL in urls) {
        if (sourceURL == nil) {
            failedCount += 1;
            continue;
        }
        if ([self isLibraryAtOrAboveStorageLimit]) {
            blockedByStorageLimit = YES;
            break;
        }

        BOOL grantedAccess = [sourceURL startAccessingSecurityScopedResource];
        @try {
            NSString *extension = SonoraTrimmedStringValue(sourceURL.pathExtension).lowercaseString;
            if (extension.length == 0 || ![allowedExtensions containsObject:extension]) {
                skippedUnsupportedCount += 1;
                continue;
            }

            NSString *baseName = sourceURL.lastPathComponent.stringByDeletingPathExtension;
            if (baseName.length == 0) {
                baseName = @"track";
            }
            NSURL *destinationURL = [self availableDestinationURLInDirectory:musicDirectoryURL
                                                                     baseName:baseName
                                                                    extension:extension];
            NSError *copyError = nil;
            BOOL copied = [fileManager copyItemAtURL:sourceURL toURL:destinationURL error:&copyError];
            if (!copied || copyError != nil) {
                failedCount += 1;
                continue;
            }
            importedCount += 1;
        } @finally {
            if (grantedAccess) {
                [sourceURL stopAccessingSecurityScopedResource];
            }
        }
    }

    [self reloadTracks];

    if (blockedByStorageLimit) {
        [self presentStorageLimitReachedAlert];
    }
    if (failedCount == 0 && skippedUnsupportedCount == 0 && !blockedByStorageLimit) {
        if (importedCount == 0) {
            SonoraPresentAlert(self, @"No Music Added", @"No supported audio files were selected.");
        }
        return;
    }

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (importedCount > 0) {
        [parts addObject:[NSString stringWithFormat:@"Imported: %lu", (unsigned long)importedCount]];
    }
    if (skippedUnsupportedCount > 0) {
        [parts addObject:[NSString stringWithFormat:@"Unsupported files skipped: %lu", (unsigned long)skippedUnsupportedCount]];
    }
    if (failedCount > 0) {
        [parts addObject:[NSString stringWithFormat:@"Failed: %lu", (unsigned long)failedCount]];
    }
    if (blockedByStorageLimit) {
        [parts addObject:@"Stopped: storage limit reached"];
    }
    NSString *message = [parts componentsJoinedByString:@"\n"];
    if (message.length == 0) {
        message = @"Could not import selected files.";
    }
    SonoraPresentAlert(self, @"Import Result", message);
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    (void)controller;
}

- (unsigned long long)currentLibraryUsageBytes {
    NSURL *musicDirectoryURL = [SonoraLibraryManager.sharedManager musicDirectoryURL];
    if (musicDirectoryURL == nil) {
        return 0ULL;
    }
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSDirectoryEnumerator<NSURL *> *enumerator =
    [fileManager enumeratorAtURL:musicDirectoryURL
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

- (unsigned long long)maxLibraryStorageBytes {
    NSInteger valueMB = SonoraSettingsMaxStorageMB();
    if (valueMB <= 0) {
        return ULLONG_MAX;
    }
    NSArray<NSNumber *> *allowed = @[@512, @1024, @2048, @3072, @4096, @6144, @8192];
    NSInteger nearest = allowed.firstObject.integerValue;
    NSInteger delta = labs(valueMB - nearest);
    for (NSNumber *candidate in allowed) {
        NSInteger current = candidate.integerValue;
        NSInteger currentDelta = labs(valueMB - current);
        if (currentDelta < delta) {
            delta = currentDelta;
            nearest = current;
        }
    }
    return ((unsigned long long)nearest) * 1024ULL * 1024ULL;
}

- (BOOL)isLibraryAtOrAboveStorageLimit {
    unsigned long long maxBytes = [self maxLibraryStorageBytes];
    if (maxBytes == ULLONG_MAX) {
        return NO;
    }
    return [self currentLibraryUsageBytes] >= maxBytes;
}

- (void)presentStorageLimitReachedAlert {
    unsigned long long usedBytes = [self currentLibraryUsageBytes];
    unsigned long long maxBytes = [self maxLibraryStorageBytes];
    if (maxBytes == ULLONG_MAX) {
        return;
    }
    NSString *usedText = [NSByteCountFormatter stringFromByteCount:(long long)usedBytes
                                                        countStyle:NSByteCountFormatterCountStyleFile];
    NSString *maxText = [NSByteCountFormatter stringFromByteCount:(long long)maxBytes
                                                       countStyle:NSByteCountFormatterCountStyleFile];
    NSString *message = [NSString stringWithFormat:@"Library size %@ reached/over max %@.\nAdding music is blocked until you free space or increase Max player space in Settings.",
                         usedText,
                         maxText];
    SonoraPresentAlert(self, @"Storage limit reached", message);
}

- (void)refreshNavigationItemsForMusicSelectionState {
    NSString *pageTitle = self.musicOnlyMode ? @"Music" : @"Search";
    NSString *displayTitle = self.multiSelectMode
    ? [NSString stringWithFormat:@"%lu Selected", (unsigned long)self.selectedTrackIDs.count]
    : pageTitle;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:SonoraWhiteSectionTitleLabel(displayTitle)];

    if (!self.musicOnlyMode) {
        UIBarButtonItem *searchItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass"]
                                                                        style:UIBarButtonItemStylePlain
                                                                       target:self
                                                                       action:@selector(searchButtonTapped)];
        SonoraConfigureNavigationIconBarButtonItem(searchItem, @"Search");
        self.navigationItem.rightBarButtonItems = @[searchItem];
        return;
    }

    if (self.multiSelectMode) {
        UIBarButtonItem *cancelItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"]
                                                                        style:UIBarButtonItemStylePlain
                                                                       target:self
                                                                       action:@selector(cancelMusicSelectionTapped)];
        SonoraConfigureNavigationIconBarButtonItem(cancelItem, @"Cancel Selection");
        UIBarButtonItem *favoriteItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"heart.fill"]
                                                                          style:UIBarButtonItemStylePlain
                                                                         target:self
                                                                         action:@selector(favoriteSelectedTracksTapped)];
        SonoraConfigureNavigationIconBarButtonItem(favoriteItem, @"Favorite Selected");
        favoriteItem.tintColor = [UIColor colorWithRed:1.0 green:0.35 blue:0.42 alpha:1.0];
        UIBarButtonItem *deleteItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"trash.fill"]
                                                                        style:UIBarButtonItemStylePlain
                                                                       target:self
                                                                       action:@selector(deleteSelectedTracksTapped)];
        SonoraConfigureNavigationIconBarButtonItem(deleteItem, @"Delete Selected");
        self.navigationItem.rightBarButtonItems = @[cancelItem, deleteItem, favoriteItem];
        return;
    }

    UIBarButtonItem *addItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                               target:self
                                                                               action:@selector(addMusicTapped)];
    SonoraConfigureNavigationIconBarButtonItem(addItem, @"Add Music");
    UIBarButtonItem *searchItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass"]
                                                                    style:UIBarButtonItemStylePlain
                                                                   target:self
                                                                   action:@selector(searchButtonTapped)];
    SonoraConfigureNavigationIconBarButtonItem(searchItem, @"Search");
    self.navigationItem.rightBarButtonItems = @[searchItem, addItem];
}

- (void)cancelMusicSelectionTapped {
    [self setMusicSelectionModeEnabled:NO];
}

- (void)setMusicSelectionModeEnabled:(BOOL)enabled {
    if (!self.musicOnlyMode && enabled) {
        return;
    }
    self.multiSelectMode = enabled;
    if (!enabled) {
        [self.selectedTrackIDs removeAllObjects];
    }
    if (enabled && self.searchController.isActive) {
        self.searchController.active = NO;
    }
    [self refreshNavigationItemsForMusicSelectionState];
    [self.tableView reloadData];
}

- (SonoraTrack * _Nullable)trackForMusicTableIndexPath:(NSIndexPath *)indexPath {
    if (!self.musicOnlyMode) {
        return nil;
    }
    if ([self sectionTypeForIndex:indexPath.section] != SonoraSearchSectionTypeTracks) {
        return nil;
    }
    if (indexPath.row < 0 || indexPath.row >= self.filteredTracks.count) {
        return nil;
    }
    return self.filteredTracks[indexPath.row];
}

- (void)toggleMusicSelectionForTrackID:(NSString *)trackID forceSelected:(BOOL)forceSelected {
    if (trackID.length == 0) {
        return;
    }
    BOOL hasTrack = [self.selectedTrackIDs containsObject:trackID];
    if (forceSelected) {
        if (!hasTrack) {
            [self.selectedTrackIDs addObject:trackID];
        }
    } else if (hasTrack) {
        [self.selectedTrackIDs removeObject:trackID];
    } else {
        [self.selectedTrackIDs addObject:trackID];
    }

    if (self.selectedTrackIDs.count == 0) {
        [self setMusicSelectionModeEnabled:NO];
    } else {
        [self refreshNavigationItemsForMusicSelectionState];
        [self.tableView reloadData];
    }
}

- (void)handleTrackLongPress:(UILongPressGestureRecognizer *)gesture {
    if (!self.musicOnlyMode || gesture.state != UIGestureRecognizerStateBegan) {
        return;
    }
    CGPoint point = [gesture locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:point];
    if (indexPath == nil) {
        return;
    }
    SonoraTrack *track = [self trackForMusicTableIndexPath:indexPath];
    if (track == nil) {
        return;
    }
    [self setMusicSelectionModeEnabled:YES];
    [self toggleMusicSelectionForTrackID:track.identifier forceSelected:YES];
}

- (void)favoriteSelectedTracksTapped {
    if (self.selectedTrackIDs.count == 0) {
        return;
    }
    for (NSString *trackID in self.selectedTrackIDs) {
        [SonoraFavoritesStore.sharedStore setTrackID:trackID favorite:YES];
    }
    [self setMusicSelectionModeEnabled:NO];
    [self reloadTracks];
}

- (void)deleteSelectedTracksTapped {
    if (self.selectedTrackIDs.count == 0) {
        return;
    }

    NSArray<NSString *> *targetIDs = [self.selectedTrackIDs.array copy];
    NSError *firstError = nil;
    for (NSString *trackID in targetIDs) {
        NSError *deleteError = nil;
        BOOL removed = [SonoraLibraryManager.sharedManager deleteTrackWithIdentifier:trackID error:&deleteError];
        if (!removed && firstError == nil) {
            firstError = deleteError;
        }
        if (removed) {
            [SonoraFavoritesStore.sharedStore setTrackID:trackID favorite:NO];
            [SonoraPlaylistStore.sharedStore removeTrackIDFromAllPlaylists:trackID];
        }
    }

    [self setMusicSelectionModeEnabled:NO];
    [self reloadTracks];
    if (firstError != nil) {
        NSString *message = firstError.localizedDescription ?: @"Could not delete one or more tracks.";
        SonoraPresentAlert(self, @"Delete Failed", message);
    }
}

- (SonoraSearchSectionType)sectionTypeForIndex:(NSInteger)section {
    if (section < 0 || section >= self.visibleSections.count) {
        return SonoraSearchSectionTypeTracks;
    }
    return (SonoraSearchSectionType)self.visibleSections[section].integerValue;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    if (!self.musicOnlyMode) {
        return 0;
    }
    return self.visibleSections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if (!self.musicOnlyMode) {
        return 0;
    }
    switch ([self sectionTypeForIndex:section]) {
        case SonoraSearchSectionTypeMiniStreaming:
            return 0;
        case SonoraSearchSectionTypePlaylists:
            return self.filteredPlaylists.count;
        case SonoraSearchSectionTypeArtists:
            return self.artistResults.count;
        case SonoraSearchSectionTypeTracks:
            return self.filteredTracks.count;
    }
    return 0;
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (!self.musicOnlyMode) {
        return nil;
    }
    NSString *normalizedQuery = SonoraNormalizedSearchText(self.searchQuery);
    if (normalizedQuery.length == 0) {
        return nil;
    }
    switch ([self sectionTypeForIndex:section]) {
        case SonoraSearchSectionTypeMiniStreaming:
            return nil;
        case SonoraSearchSectionTypePlaylists:
            return @"Playlists";
        case SonoraSearchSectionTypeArtists:
            return @"Artists";
        case SonoraSearchSectionTypeTracks:
            return @"Tracks";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (!self.musicOnlyMode) {
        return [UITableViewCell new];
    }
    SonoraSearchSectionType sectionType = [self sectionTypeForIndex:indexPath.section];
    if (sectionType == SonoraSearchSectionTypeTracks) {
        SonoraTrackCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MusicTrackCell" forIndexPath:indexPath];

        SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
        SonoraTrack *track = self.filteredTracks[indexPath.row];
        SonoraTrack *currentTrack = playback.currentTrack;
        BOOL isCurrent = (currentTrack != nil && [currentTrack.identifier isEqualToString:track.identifier]);
        BOOL sameQueue = SonoraTrackQueuesMatchByIdentifier(playback.currentQueue, self.tracks);
        BOOL showsPlaybackIndicator = (sameQueue && isCurrent && playback.isPlaying);

        [cell configureWithTrack:track isCurrent:isCurrent showsPlaybackIndicator:showsPlaybackIndicator];
        cell.accessoryType = (self.multiSelectMode && [self.selectedTrackIDs containsObject:track.identifier])
        ? UITableViewCellAccessoryCheckmark
        : UITableViewCellAccessoryNone;
        return cell;
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MusicSearchMetaCell"];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"MusicSearchMetaCell"];
    }
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.textLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular];
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryNone;

    if (sectionType == SonoraSearchSectionTypePlaylists) {
        if (indexPath.row < self.filteredPlaylists.count) {
            SonoraPlaylist *playlist = self.filteredPlaylists[indexPath.row];
            cell.imageView.image = [UIImage systemImageNamed:@"music.note.list"];
            cell.textLabel.text = playlist.name ?: @"Playlist";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld tracks", (long)playlist.trackIDs.count];
        }
    } else if (sectionType == SonoraSearchSectionTypeArtists) {
        if (indexPath.row < self.artistResults.count) {
            NSDictionary<NSString *, id> *artistEntry = self.artistResults[indexPath.row];
            NSArray *matchedTracks = artistEntry[@"tracks"];
            cell.imageView.image = [UIImage systemImageNamed:@"person.fill"];
            cell.textLabel.text = artistEntry[@"title"] ?: @"Artist";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld tracks", (long)matchedTracks.count];
        }
    }

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!self.musicOnlyMode) {
        return;
    }

    if (self.multiSelectMode) {
        SonoraTrack *selectionTrack = [self trackForMusicTableIndexPath:indexPath];
        if (selectionTrack != nil) {
            [self toggleMusicSelectionForTrackID:selectionTrack.identifier forceSelected:NO];
        }
        return;
    }

    SonoraSearchSectionType sectionType = [self sectionTypeForIndex:indexPath.section];
    if (sectionType == SonoraSearchSectionTypePlaylists) {
        if (indexPath.row >= self.filteredPlaylists.count) {
            return;
        }
        SonoraPlaylist *playlist = self.filteredPlaylists[indexPath.row];
        SonoraPlaylistDetailViewController *detail = [[SonoraPlaylistDetailViewController alloc] initWithPlaylistID:playlist.playlistID];
        detail.hidesBottomBarWhenPushed = YES;
        [self.navigationController pushViewController:detail animated:YES];
        return;
    }

    if (sectionType == SonoraSearchSectionTypeArtists) {
        if (indexPath.row >= self.artistResults.count) {
            return;
        }
        NSDictionary<NSString *, id> *artistEntry = self.artistResults[indexPath.row];
        NSString *artistTitle = artistEntry[@"title"] ?: @"";
        self.searchQuery = artistTitle;
        self.searchController.searchBar.text = artistTitle;
        [self applySearchFilterAndReload];
        [self refreshMiniStreamingForCurrentQuery];
        return;
    }

    if (indexPath.row >= self.filteredTracks.count) {
        return;
    }

    NSArray<SonoraTrack *> *playlistQueue = self.tracks;
    if (playlistQueue.count == 0) {
        return;
    }

    SonoraTrack *selectedTrack = self.filteredTracks[indexPath.row];
    NSInteger playlistIndex = SonoraIndexOfTrackByIdentifier(playlistQueue, selectedTrack.identifier);
    if (playlistIndex == NSNotFound) {
        return;
    }

    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    SonoraTrack *currentTrack = playback.currentTrack;
    BOOL sameTrack = (currentTrack != nil && [currentTrack.identifier isEqualToString:selectedTrack.identifier]);
    BOOL sameQueue = SonoraTrackQueuesMatchByIdentifier(playback.currentQueue, playlistQueue);
    if (sameTrack && sameQueue) {
        [self openPlayer];
        return;
    }

    [self openPlayer];
    dispatch_async(dispatch_get_main_queue(), ^{
        [playback setShuffleEnabled:NO];
        [playback playTracks:playlistQueue startIndex:playlistIndex];
    });
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (!self.musicOnlyMode || self.multiSelectMode) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }
    if ([self sectionTypeForIndex:indexPath.section] != SonoraSearchSectionTypeTracks ||
        indexPath.row >= self.filteredTracks.count) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }

    SonoraTrack *track = self.filteredTracks[indexPath.row];

    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                               title:@"Delete"
                                                                             handler:^(__unused UIContextualAction * _Nonnull action,
                                                                                       __unused UIView * _Nonnull sourceView,
                                                                                       void (^ _Nonnull completionHandler)(BOOL)) {
        NSError *deleteError = nil;
        BOOL removed = [SonoraLibraryManager.sharedManager deleteTrackWithIdentifier:track.identifier error:&deleteError];
        if (!removed) {
            NSString *message = deleteError.localizedDescription ?: @"Could not delete track file.";
            SonoraPresentAlert(self, @"Delete Failed", message);
            completionHandler(NO);
            return;
        }

        [SonoraFavoritesStore.sharedStore setTrackID:track.identifier favorite:NO];
        [SonoraPlaylistStore.sharedStore removeTrackIDFromAllPlaylists:track.identifier];
        [self reloadTracks];
        completionHandler(YES);
    }];
    deleteAction.image = [UIImage systemImageNamed:@"trash.fill"];

    UIContextualAction *addAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                            title:@"Add"
                                                                          handler:^(__unused UIContextualAction * _Nonnull action,
                                                                                    __unused UIView * _Nonnull sourceView,
                                                                                    void (^ _Nonnull completionHandler)(BOOL)) {
        SonoraPresentQuickAddTrackToPlaylist(self, track.identifier, nil);
        completionHandler(YES);
    }];
    addAction.image = [UIImage systemImageNamed:@"text.badge.plus"];
    addAction.backgroundColor = [UIColor colorWithRed:0.16 green:0.47 blue:0.95 alpha:1.0];

    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[deleteAction, addAction]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (!self.musicOnlyMode || self.multiSelectMode) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }
    if ([self sectionTypeForIndex:indexPath.section] != SonoraSearchSectionTypeTracks ||
        indexPath.row >= self.filteredTracks.count) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }

    SonoraTrack *track = self.filteredTracks[indexPath.row];
    BOOL isFavorite = [SonoraFavoritesStore.sharedStore isTrackFavoriteByID:track.identifier];
    NSString *iconName = isFavorite ? @"heart.slash.fill" : @"heart.fill";
    UIColor *backgroundColor = isFavorite
    ? [UIColor colorWithWhite:0.40 alpha:1.0]
    : [UIColor colorWithRed:1.0 green:0.35 blue:0.42 alpha:1.0];

    UIContextualAction *favoriteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                                  title:nil
                                                                                handler:^(__unused UIContextualAction * _Nonnull action,
                                                                                          __unused UIView * _Nonnull sourceView,
                                                                                          void (^ _Nonnull completionHandler)(BOOL)) {
        [SonoraFavoritesStore.sharedStore setTrackID:track.identifier favorite:!isFavorite];
        [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        completionHandler(YES);
    }];
    favoriteAction.image = [UIImage systemImageNamed:iconName];
    favoriteAction.backgroundColor = backgroundColor;

    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[favoriteAction]];
    configuration.performsFirstActionWithFullSwipe = YES;
    return configuration;
}

- (NSString *)titleForSearchSectionType:(SonoraSearchSectionType)sectionType {
    switch (sectionType) {
        case SonoraSearchSectionTypeMiniStreaming:
            return @"Tracks";
        case SonoraSearchSectionTypePlaylists:
            return @"Playlists";
        case SonoraSearchSectionTypeArtists:
            return @"Artists";
        case SonoraSearchSectionTypeTracks:
            return @"Music";
    }
    return @"";
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    if (collectionView != self.searchCollectionView || self.musicOnlyMode) {
        return 0;
    }
    return self.visibleSections.count;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    if (collectionView != self.searchCollectionView || self.musicOnlyMode) {
        return 0;
    }

    switch ([self sectionTypeForIndex:section]) {
        case SonoraSearchSectionTypeMiniStreaming:
            return self.miniStreamingTracks.count;
        case SonoraSearchSectionTypePlaylists:
            return self.filteredPlaylists.count;
        case SonoraSearchSectionTypeArtists:
            return self.miniStreamingArtists.count;
        case SonoraSearchSectionTypeTracks:
            return self.filteredTracks.count;
    }
    return 0;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                           cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    if (collectionView != self.searchCollectionView || self.musicOnlyMode) {
        return [UICollectionViewCell new];
    }

    SonoraSearchSectionType sectionType = [self sectionTypeForIndex:indexPath.section];
    if (sectionType == SonoraSearchSectionTypeMiniStreaming) {
        SonoraMiniStreamingListCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:SonoraMiniStreamingListCellReuseID
                                                                                       forIndexPath:indexPath];
        if (indexPath.item < self.miniStreamingTracks.count) {
            SonoraMiniStreamingTrack *track = self.miniStreamingTracks[indexPath.item];
            UIImage *artwork = [self cachedMiniStreamingArtworkForTrack:track];
            [self loadMiniStreamingArtworkIfNeededForTrack:track];
            SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
            NSString *currentTrackID = [self miniStreamingTrackIDFromPlaybackTrack:playback.currentTrack];
            BOOL isCurrent = [currentTrackID isEqualToString:track.trackID];
            BOOL sameQueue = [self miniStreamingPlaybackQueueMatchesMiniTracks:self.miniStreamingTracks];
            BOOL showsPlaybackIndicator = (sameQueue && isCurrent && playback.isPlaying);
            NSString *subtitle = track.artists.length > 0 ? track.artists : @"Spotify";
            [cell configureWithTitle:track.title
                            subtitle:subtitle
                         durationText:SonoraFormatDuration(track.duration)
                               image:artwork
                            isCurrent:isCurrent
               showsPlaybackIndicator:showsPlaybackIndicator
                       showsSeparator:(indexPath.item + 1 < self.miniStreamingTracks.count)];
        }
        return cell;
    }

    if (sectionType == SonoraSearchSectionTypeArtists) {
        SonoraMusicSearchCardCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:SonoraMusicSearchCardCellReuseID
                                                                                     forIndexPath:indexPath];
        if (indexPath.item < self.miniStreamingArtists.count) {
            SonoraMiniStreamingArtist *artist = self.miniStreamingArtists[indexPath.item];
            UIImage *artwork = [self cachedMiniStreamingArtworkForURL:artist.artworkURL];
            [self loadMiniStreamingArtworkIfNeededForURL:artist.artworkURL];
            [cell configureWithTitle:artist.name subtitle:@"Artist" image:artwork];
        }
        return cell;
    }

    SonoraMusicSearchCardCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:SonoraMusicSearchCardCellReuseID
                                                                                 forIndexPath:indexPath];
    if (sectionType == SonoraSearchSectionTypePlaylists) {
        if (indexPath.item < self.filteredPlaylists.count) {
            SonoraPlaylist *playlist = self.filteredPlaylists[indexPath.item];
            UIImage *cover = [SonoraPlaylistStore.sharedStore coverForPlaylist:playlist
                                                                   library:SonoraLibraryManager.sharedManager
                                                                      size:CGSizeMake(220.0, 220.0)];
            NSString *subtitle = [NSString stringWithFormat:@"%ld tracks", (long)playlist.trackIDs.count];
            [cell configureWithTitle:playlist.name subtitle:subtitle image:cover];
        }
    } else {
        if (indexPath.item < self.filteredTracks.count) {
            SonoraTrack *track = self.filteredTracks[indexPath.item];
            NSString *trackTitle = track.title.length > 0 ? track.title :
                (track.fileName.length > 0 ? track.fileName.stringByDeletingPathExtension : @"Unknown track");
            NSString *subtitle = track.artist.length > 0 ? track.artist : @"Track";
            [cell configureWithTitle:trackTitle subtitle:subtitle image:track.artwork];
        }
    }
    return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView
              viewForSupplementaryElementOfKind:(NSString *)kind
                                    atIndexPath:(NSIndexPath *)indexPath {
    if (collectionView != self.searchCollectionView ||
        ![kind isEqualToString:UICollectionElementKindSectionHeader] ||
        self.musicOnlyMode) {
        return [UICollectionReusableView new];
    }

    SonoraMusicSearchHeaderView *header = [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                                                          withReuseIdentifier:SonoraMusicSearchHeaderReuseID
                                                                                 forIndexPath:indexPath];
    SonoraSearchSectionType sectionType = [self sectionTypeForIndex:indexPath.section];
    [header configureWithTitle:[self titleForSearchSectionType:sectionType]];
    return header;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    if (collectionView != self.searchCollectionView || self.musicOnlyMode) {
        return;
    }
    [self.searchController.searchBar resignFirstResponder];

    SonoraSearchSectionType sectionType = [self sectionTypeForIndex:indexPath.section];
    if (sectionType == SonoraSearchSectionTypeMiniStreaming) {
        if (indexPath.item >= self.miniStreamingTracks.count) {
            return;
        }
        SonoraMiniStreamingTrack *track = self.miniStreamingTracks[indexPath.item];
        UIImage *artwork = [self cachedMiniStreamingArtworkForTrack:track];
        NSArray<SonoraMiniStreamingTrack *> *queueSnapshot = [self.miniStreamingTracks copy] ?: @[];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self installMiniStreamingTrack:track
                                      queue:queueSnapshot
                                 startIndex:indexPath.item
                           preferredArtwork:artwork];
        });
        return;
    }

    if (sectionType == SonoraSearchSectionTypePlaylists) {
        if (indexPath.item >= self.filteredPlaylists.count) {
            return;
        }
        SonoraPlaylist *playlist = self.filteredPlaylists[indexPath.item];
        SonoraPlaylistDetailViewController *detail = [[SonoraPlaylistDetailViewController alloc] initWithPlaylistID:playlist.playlistID];
        detail.hidesBottomBarWhenPushed = YES;
        [self.navigationController pushViewController:detail animated:YES];
        return;
    }

    if (sectionType == SonoraSearchSectionTypeArtists) {
        if (indexPath.item >= self.miniStreamingArtists.count) {
            return;
        }
        SonoraMiniStreamingArtist *artist = self.miniStreamingArtists[indexPath.item];
        if (artist == nil || artist.artistID.length == 0) {
            return;
        }

        __weak typeof(self) weakSelf = self;
        SonoraMiniStreamingArtistViewController *artistView = [[SonoraMiniStreamingArtistViewController alloc] initWithArtist:artist
                                                                                                                        client:self.miniStreamingClient
                                                                                                                installHandler:^(SonoraMiniStreamingTrack * _Nonnull track,
                                                                                                                                NSArray<SonoraMiniStreamingTrack *> * _Nonnull queue,
                                                                                                                                NSInteger startIndex,
                                                                                                                                UIImage * _Nullable artwork) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            [strongSelf installMiniStreamingTrack:track
                                            queue:queue
                                       startIndex:startIndex
                                 preferredArtwork:artwork];
        }];
        artistView.hidesBottomBarWhenPushed = YES;
        [self.navigationController pushViewController:artistView animated:YES];
        return;
    }

    if (indexPath.item >= self.filteredTracks.count) {
        return;
    }
    SonoraTrack *selectedTrack = self.filteredTracks[indexPath.item];
    NSInteger startIndex = SonoraIndexOfTrackByIdentifier(self.tracks, selectedTrack.identifier);
    if (startIndex == NSNotFound) {
        return;
    }

    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    SonoraTrack *currentTrack = playback.currentTrack;
    BOOL sameTrack = (currentTrack != nil && [currentTrack.identifier isEqualToString:selectedTrack.identifier]);
    BOOL sameQueue = SonoraTrackQueuesMatchByIdentifier(playback.currentQueue, self.tracks);
    if (sameTrack && sameQueue) {
        [self openPlayer];
        return;
    }

    [self openPlayer];
    dispatch_async(dispatch_get_main_queue(), ^{
        [playback setShuffleEnabled:NO];
        [playback playTracks:self.tracks startIndex:startIndex];
    });
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.searchQuery = searchController.searchBar.text ?: @"";
    [self applySearchFilterAndReload];
    [self refreshMiniStreamingForCurrentQuery];
    [self updateSearchControllerAttachment];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (self.musicOnlyMode && (scrollView == self.tableView || scrollView == self.searchCollectionView)) {
        [self updateSearchControllerAttachment];
    }
}

@end

#pragma mark - Playlists

@interface SonoraPlaylistsViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray<SonoraPlaylist *> *playlists;
@property (nonatomic, copy) NSArray<SonoraPlaylist *> *filteredPlaylists;
@property (nonatomic, copy) NSString *searchQuery;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, assign) BOOL searchControllerAttached;
@property (nonatomic, assign) BOOL syncingLovelyPlaylist;
@property (nonatomic, assign) BOOL needsLovelyRefresh;

@end

@implementation SonoraPlaylistsViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = nil;
    self.navigationItem.title = nil;
    self.navigationItem.titleView = nil;
    self.navigationItem.hidesBackButton = YES;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:SonoraWhiteSectionTitleLabel(@"Playlists")];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    [self setupTableView];
    [self setupSearch];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                                             target:self
                                                                                             action:@selector(addPlaylistTapped)];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(reloadPlaylists)
                                               name:SonoraPlaylistsDidChangeNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(reloadPlaylists)
                                               name:UIApplicationWillEnterForegroundNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(reloadPlaylists)
                                               name:SonoraFavoritesDidChangeNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(markNeedsLovelyRefresh)
                                               name:SonoraPlaybackStateDidChangeNotification
                                             object:nil];

    self.needsLovelyRefresh = YES;
    [self reloadPlaylists];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationItem.title = nil;
    self.navigationItem.titleView = nil;
    self.navigationItem.hidesBackButton = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                                             target:self
                                                                                             action:@selector(addPlaylistTapped)];
    self.navigationController.interactivePopGestureRecognizer.enabled = YES;
    self.navigationController.interactivePopGestureRecognizer.delegate = nil;
    if (self.needsLovelyRefresh) {
        [self reloadPlaylists];
    }
    [self updateSearchControllerAttachment];
    [self.tableView reloadData];
}

- (void)markNeedsLovelyRefresh {
    self.needsLovelyRefresh = YES;
}

- (void)setupTableView {
    UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    tableView.translatesAutoresizingMaskIntoConstraints = NO;
    tableView.dataSource = self;
    tableView.delegate = self;
    tableView.rowHeight = 56.0;
    tableView.alwaysBounceVertical = YES;
    tableView.sectionHeaderHeight = 0.0;
    tableView.sectionFooterHeight = 0.0;
    tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    if (@available(iOS 15.0, *)) {
        tableView.sectionHeaderTopPadding = 0.0;
    }
    [tableView registerClass:SonoraPlaylistCell.class forCellReuseIdentifier:@"PlaylistCell"];

    self.tableView = tableView;
    [self.view addSubview:tableView];

    [NSLayoutConstraint activateConstraints:@[
        [tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)setupSearch {
    self.searchController = SonoraBuildSearchController(self, @"Search Playlists");
    self.navigationItem.searchController = nil;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
    self.definesPresentationContext = YES;
    self.searchControllerAttached = NO;
}

- (void)updateSearchControllerAttachment {
    BOOL shouldAttach = SonoraShouldAttachSearchController(self.searchControllerAttached,
                                                       self.searchController,
                                                       self.tableView,
                                                       SonoraSearchRevealThreshold);
    if (shouldAttach == self.searchControllerAttached) {
        return;
    }

    self.searchControllerAttached = shouldAttach;
    SonoraApplySearchControllerAttachment(self.navigationItem,
                                      self.navigationController.navigationBar,
                                      self.searchController,
                                      shouldAttach,
                                      (self.view.window != nil));
}

- (void)applySearchFilterAndReload {
    self.filteredPlaylists = SonoraFilterPlaylistsByQuery(self.playlists, self.searchQuery);
    [self.tableView reloadData];
    [self updateEmptyState];
}

- (void)updateEmptyState {
    if (self.filteredPlaylists.count > 0) {
        self.tableView.backgroundView = nil;
        return;
    }

    UILabel *label = [[UILabel alloc] init];
    label.textColor = UIColor.secondaryLabelColor;
    label.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    if (self.playlists.count == 0) {
        label.text = @"Tap + to create a playlist";
    } else {
        label.text = @"No matching playlists.";
    }
    self.tableView.backgroundView = label;
}

- (void)addPlaylistTapped {
    SonoraPlaylistNameViewController *nameVC = [[SonoraPlaylistNameViewController alloc] init];
    nameVC.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:nameVC animated:YES];
}

- (NSArray<NSString *> *)lovelyTrackIDsFromLibraryTracks:(NSArray<SonoraTrack *> *)libraryTracks {
    if (libraryTracks.count == 0) {
        return @[];
    }

    NSMutableArray<NSString *> *trackIDs = [NSMutableArray arrayWithCapacity:libraryTracks.count];
    for (SonoraTrack *track in libraryTracks) {
        if (track.identifier.length > 0) {
            [trackIDs addObject:track.identifier];
        }
    }
    if (trackIDs.count == 0) {
        return @[];
    }

    NSDictionary<NSString *, NSDictionary<NSString *, NSNumber *> *> *analyticsByTrackID =
    [SonoraTrackAnalyticsStore.sharedStore analyticsByTrackIDForTrackIDs:trackIDs];
    SonoraFavoritesStore *favoritesStore = SonoraFavoritesStore.sharedStore;

    NSMutableArray<SonoraTrack *> *eligibleTracks = [NSMutableArray array];
    for (SonoraTrack *track in libraryTracks) {
        NSDictionary<NSString *, NSNumber *> *metrics = analyticsByTrackID[track.identifier] ?: @{};
        NSInteger playCount = [metrics[@"playCount"] integerValue];
        NSInteger skipCount = [metrics[@"skipCount"] integerValue];
        double score = [metrics[@"score"] doubleValue];
        NSInteger activity = playCount + skipCount;
        BOOL isFavorite = [favoritesStore isTrackFavoriteByID:track.identifier];

        // Rule:
        // (playCount + skipCount) >= 3
        // AND ((isFavorite && score >= 0.60 && playCount >= 2) || (score >= 0.80 && playCount >= 4))
        // AND skipCount <= 3
        BOOL matchesFavoriteRule = (isFavorite && score >= 0.60 && playCount >= 2);
        BOOL matchesHighScoreRule = (score >= 0.80 && playCount >= 4);
        if (activity < 3 || skipCount > 3 || !(matchesFavoriteRule || matchesHighScoreRule)) {
            continue;
        }

        [eligibleTracks addObject:track];
    }

    if (eligibleTracks.count == 0) {
        return @[];
    }

    [eligibleTracks sortUsingComparator:^NSComparisonResult(SonoraTrack * _Nonnull left, SonoraTrack * _Nonnull right) {
        NSDictionary<NSString *, NSNumber *> *leftMetrics = analyticsByTrackID[left.identifier] ?: @{};
        NSDictionary<NSString *, NSNumber *> *rightMetrics = analyticsByTrackID[right.identifier] ?: @{};

        NSInteger leftPlay = [leftMetrics[@"playCount"] integerValue];
        NSInteger rightPlay = [rightMetrics[@"playCount"] integerValue];
        NSInteger leftSkip = [leftMetrics[@"skipCount"] integerValue];
        NSInteger rightSkip = [rightMetrics[@"skipCount"] integerValue];

        double leftScore = [leftMetrics[@"score"] doubleValue];
        double rightScore = [rightMetrics[@"score"] doubleValue];
        BOOL leftFavorite = [favoritesStore isTrackFavoriteByID:left.identifier];
        BOOL rightFavorite = [favoritesStore isTrackFavoriteByID:right.identifier];

        if (leftScore > rightScore) {
            return NSOrderedAscending;
        }
        if (leftScore < rightScore) {
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
        if (leftFavorite != rightFavorite) {
            return leftFavorite ? NSOrderedAscending : NSOrderedDescending;
        }

        NSString *leftTitle = left.title.length > 0 ? left.title : left.fileName;
        NSString *rightTitle = right.title.length > 0 ? right.title : right.fileName;
        return [leftTitle localizedCaseInsensitiveCompare:rightTitle];
    }];

    NSMutableArray<NSString *> *orderedIDs = [NSMutableArray arrayWithCapacity:eligibleTracks.count];
    for (SonoraTrack *track in eligibleTracks) {
        if (track.identifier.length > 0) {
            [orderedIDs addObject:track.identifier];
        }
    }
    return [orderedIDs copy];
}

- (void)syncLovelyPlaylistIfNeeded {
    NSArray<SonoraTrack *> *libraryTracks = SonoraLibraryManager.sharedManager.tracks;
    if (libraryTracks.count == 0) {
        libraryTracks = [SonoraLibraryManager.sharedManager reloadTracks];
    }
    NSArray<NSString *> *lovelyTrackIDs = [self lovelyTrackIDsFromLibraryTracks:libraryTracks];

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *storedPlaylistID = [defaults stringForKey:SonoraLovelyPlaylistDefaultsKey];

    SonoraPlaylistStore *store = SonoraPlaylistStore.sharedStore;
    SonoraPlaylist *lovelyPlaylist = (storedPlaylistID.length > 0)
    ? [store playlistWithID:storedPlaylistID]
    : nil;
    if (lovelyPlaylist == nil) {
        for (SonoraPlaylist *playlist in store.playlists) {
            if ([playlist.name localizedCaseInsensitiveCompare:@"Lovely songs"] == NSOrderedSame) {
                lovelyPlaylist = playlist;
                [defaults setObject:playlist.playlistID forKey:SonoraLovelyPlaylistDefaultsKey];
                break;
            }
        }
    }

    if (lovelyPlaylist == nil) {
        [defaults removeObjectForKey:SonoraLovelyPlaylistDefaultsKey];
        [defaults removeObjectForKey:SonoraLovelyPlaylistCoverMarkerKey];
        if (lovelyTrackIDs.count == 0) {
            return;
        }

        UIImage *coverImage = SonoraLovelySongsCoverImage(CGSizeMake(768.0, 768.0));
        SonoraPlaylist *created = [store addPlaylistWithName:@"Lovely songs"
                                                trackIDs:lovelyTrackIDs
                                              coverImage:coverImage];
        if (created != nil) {
            [defaults setObject:created.playlistID forKey:SonoraLovelyPlaylistDefaultsKey];
            [defaults setObject:created.playlistID forKey:SonoraLovelyPlaylistCoverMarkerKey];
        }
        return;
    }

    if (![lovelyPlaylist.name isEqualToString:@"Lovely songs"]) {
        [store renamePlaylistWithID:lovelyPlaylist.playlistID newName:@"Lovely songs"];
    }

    if (![lovelyPlaylist.trackIDs isEqualToArray:lovelyTrackIDs]) {
        [store replaceTrackIDs:lovelyTrackIDs forPlaylistID:lovelyPlaylist.playlistID];
    }

    NSString *coverMarker = [defaults stringForKey:SonoraLovelyPlaylistCoverMarkerKey];
    BOOL shouldRefreshCover = (lovelyPlaylist.customCoverFileName.length == 0 ||
                               ![coverMarker isEqualToString:lovelyPlaylist.playlistID]);
    if (shouldRefreshCover) {
        UIImage *coverImage = SonoraLovelySongsCoverImage(CGSizeMake(768.0, 768.0));
        BOOL coverSet = [store setCustomCoverImage:coverImage forPlaylistID:lovelyPlaylist.playlistID];
        if (coverSet) {
            [defaults setObject:lovelyPlaylist.playlistID forKey:SonoraLovelyPlaylistCoverMarkerKey];
        }
    }
}

- (void)reloadPlaylists {
    if (self.syncingLovelyPlaylist) {
        return;
    }

    self.syncingLovelyPlaylist = YES;
    @try {
        SonoraPlaylistStore *store = SonoraPlaylistStore.sharedStore;
        [store reloadPlaylists];
        [self syncLovelyPlaylistIfNeeded];
        [store reloadPlaylists];

        NSMutableArray<SonoraPlaylist *> *orderedPlaylists = [store.playlists mutableCopy];
        NSString *lovelyID = [NSUserDefaults.standardUserDefaults stringForKey:SonoraLovelyPlaylistDefaultsKey];
        if (lovelyID.length > 0) {
            NSUInteger index = [orderedPlaylists indexOfObjectPassingTest:^BOOL(SonoraPlaylist * _Nonnull playlist, __unused NSUInteger idx, __unused BOOL * _Nonnull stop) {
                return [playlist.playlistID isEqualToString:lovelyID];
            }];
            if (index != NSNotFound) {
                SonoraPlaylist *lovely = orderedPlaylists[index];
                if (lovely.trackIDs.count == 0) {
                    [orderedPlaylists removeObjectAtIndex:index];
                } else if (index != 0) {
                    [orderedPlaylists removeObjectAtIndex:index];
                    [orderedPlaylists insertObject:lovely atIndex:0];
                }
            }
        }

        NSArray<SonoraPlaylist *> *likedSharedPlaylists = [SonoraSharedPlaylistStore.sharedStore likedPlaylists];
        if (likedSharedPlaylists.count > 0) {
            [orderedPlaylists addObjectsFromArray:likedSharedPlaylists];
        }

        self.playlists = [orderedPlaylists copy];
        [self applySearchFilterAndReload];
    } @finally {
        self.needsLovelyRefresh = NO;
        self.syncingLovelyPlaylist = NO;
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return self.filteredPlaylists.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SonoraPlaylistCell *cell = [tableView dequeueReusableCellWithIdentifier:@"PlaylistCell" forIndexPath:indexPath];

    SonoraPlaylist *playlist = self.filteredPlaylists[indexPath.row];
    UIImage *cover = nil;
    NSString *subtitle = [NSString stringWithFormat:@"%ld tracks", (long)playlist.trackIDs.count];
    SonoraSharedPlaylistSnapshot *sharedSnapshot = [SonoraSharedPlaylistStore.sharedStore snapshotForPlaylistID:playlist.playlistID];
    if (sharedSnapshot != nil) {
        cover = sharedSnapshot.coverImage ?: sharedSnapshot.tracks.firstObject.artwork;
        BOOL cacheAudioEnabled = SonoraSettingsCacheOnlinePlaylistTracksEnabled();
        NSUInteger totalTracks = sharedSnapshot.tracks.count;
        NSUInteger cachedTracks = 0;
        for (SonoraTrack *track in sharedSnapshot.tracks) {
            if (track.url.isFileURL && track.url.path.length > 0 &&
                [NSFileManager.defaultManager fileExistsAtPath:track.url.path]) {
                cachedTracks += 1;
            }
        }
        if (!cacheAudioEnabled) {
            subtitle = @"Online playlist • Streaming";
        } else if (totalTracks == 0) {
            subtitle = @"Online playlist";
        } else if (cachedTracks >= totalTracks) {
            subtitle = @"Online playlist • Cached";
        } else {
            subtitle = [NSString stringWithFormat:@"Online playlist • Cached %lu/%lu",
                        (unsigned long)cachedTracks,
                        (unsigned long)totalTracks];
        }
    } else {
        cover = [SonoraPlaylistStore.sharedStore coverForPlaylist:playlist
                                                         library:SonoraLibraryManager.sharedManager
                                                            size:CGSizeMake(160.0, 160.0)];
    }

    [cell configureWithName:playlist.name subtitle:subtitle artwork:cover];
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.row >= self.filteredPlaylists.count) {
        return;
    }
    SonoraPlaylist *playlist = self.filteredPlaylists[indexPath.row];
    SonoraPlaylistDetailViewController *detail = [[SonoraPlaylistDetailViewController alloc] initWithPlaylistID:playlist.playlistID];
    detail.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:detail animated:YES];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.searchQuery = searchController.searchBar.text ?: @"";
    [self applySearchFilterAndReload];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView == self.tableView) {
        [self updateSearchControllerAttachment];
    }
}

@end

#pragma mark - Favorites

@interface SonoraFavoritesViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray<SonoraTrack *> *tracks;
@property (nonatomic, copy) NSArray<SonoraTrack *> *filteredTracks;
@property (nonatomic, copy) NSString *searchQuery;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, assign) BOOL searchControllerAttached;
@property (nonatomic, assign) BOOL multiSelectMode;
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *selectedTrackIDs;
@property (nonatomic, strong) UILongPressGestureRecognizer *selectionLongPressRecognizer;

@end

@implementation SonoraFavoritesViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Favorites";
    self.navigationItem.title = nil;
    self.navigationItem.titleView = nil;
    self.navigationItem.hidesBackButton = YES;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:SonoraWhiteSectionTitleLabel(@"Favorites")];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    UIBarButtonItem *searchItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass"]
                                                                               style:UIBarButtonItemStylePlain
                                                                              target:self
                                                                              action:@selector(searchButtonTapped)];
    SonoraConfigureNavigationIconBarButtonItem(searchItem, @"Search");
    self.navigationItem.rightBarButtonItem = searchItem;

    [self setupTableView];
    [self setupSearch];
    self.multiSelectMode = NO;
    self.selectedTrackIDs = [NSMutableOrderedSet orderedSet];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(reloadFavorites)
                                               name:SonoraFavoritesDidChangeNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handlePlaybackChanged)
                                               name:SonoraPlaybackStateDidChangeNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handleAppForeground)
                                               name:UIApplicationWillEnterForegroundNotification
                                             object:nil];

    [self refreshNavigationItemsForFavoritesSelectionState];
    [self reloadFavorites];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationItem.hidesBackButton = YES;
    [self refreshNavigationItemsForFavoritesSelectionState];
    self.navigationController.interactivePopGestureRecognizer.enabled = YES;
    self.navigationController.interactivePopGestureRecognizer.delegate = nil;
    [self updateSearchControllerAttachment];
    [self.tableView reloadData];
}

- (void)setupTableView {
    UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    tableView.translatesAutoresizingMaskIntoConstraints = NO;
    tableView.dataSource = self;
    tableView.delegate = self;
    tableView.rowHeight = 54.0;
    tableView.alwaysBounceVertical = YES;
    tableView.sectionHeaderHeight = 0.0;
    tableView.sectionFooterHeight = 0.0;
    tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    if (@available(iOS 15.0, *)) {
        tableView.sectionHeaderTopPadding = 0.0;
    }
    [tableView registerClass:SonoraTrackCell.class forCellReuseIdentifier:@"FavoriteTrackCell"];
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                                                             action:@selector(handleTrackLongPress:)];
    [tableView addGestureRecognizer:longPress];
    self.selectionLongPressRecognizer = longPress;

    self.tableView = tableView;
    [self.view addSubview:tableView];

    [NSLayoutConstraint activateConstraints:@[
        [tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)setupSearch {
    self.searchController = SonoraBuildSearchController(self, @"Search Favorites");
    self.navigationItem.searchController = nil;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
    self.definesPresentationContext = YES;
    self.searchControllerAttached = NO;
}

- (void)updateSearchControllerAttachment {
    BOOL shouldAttach = SonoraShouldAttachSearchController(self.searchControllerAttached,
                                                       self.searchController,
                                                       self.tableView,
                                                       SonoraSearchRevealThreshold);
    if (shouldAttach == self.searchControllerAttached) {
        return;
    }

    self.searchControllerAttached = shouldAttach;
    SonoraApplySearchControllerAttachment(self.navigationItem,
                                      self.navigationController.navigationBar,
                                      self.searchController,
                                      shouldAttach,
                                      (self.view.window != nil));
}

- (void)applySearchFilterAndReload {
    self.filteredTracks = SonoraFilterTracksByQuery(self.tracks, self.searchQuery);
    [self.tableView reloadData];
    [self updateEmptyState];
}

- (void)updateEmptyState {
    if (self.filteredTracks.count > 0) {
        self.tableView.backgroundView = nil;
        return;
    }

    UILabel *label = [[UILabel alloc] init];
    label.textColor = UIColor.secondaryLabelColor;
    label.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    if (self.tracks.count == 0) {
        label.text = @"No favorites yet.\nTap heart in player to add tracks.";
    } else {
        label.text = @"No search results.";
    }
    self.tableView.backgroundView = label;
}

- (void)reloadFavorites {
    if (SonoraLibraryManager.sharedManager.tracks.count == 0 &&
        SonoraFavoritesStore.sharedStore.favoriteTrackIDs.count > 0) {
        [SonoraLibraryManager.sharedManager reloadTracks];
    }

    self.tracks = [SonoraFavoritesStore.sharedStore favoriteTracksWithLibrary:SonoraLibraryManager.sharedManager];
    [self applySearchFilterAndReload];
}

- (void)handleAppForeground {
    [SonoraLibraryManager.sharedManager reloadTracks];
    [self reloadFavorites];
}

- (void)handlePlaybackChanged {
    [self.tableView reloadData];
}

- (void)openPlayer {
    SonoraPlayerViewController *player = [[SonoraPlayerViewController alloc] init];
    player.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:player animated:YES];
}

- (void)searchButtonTapped {
    if (self.searchController == nil) {
        return;
    }

    if (!self.searchControllerAttached) {
        self.searchControllerAttached = YES;
        SonoraApplySearchControllerAttachment(self.navigationItem,
                                          self.navigationController.navigationBar,
                                          self.searchController,
                                          YES,
                                          (self.view.window != nil));
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        self.searchController.active = YES;
        [self.searchController.searchBar becomeFirstResponder];
    });
}

- (void)refreshNavigationItemsForFavoritesSelectionState {
    NSString *displayTitle = self.multiSelectMode
    ? [NSString stringWithFormat:@"%lu Selected", (unsigned long)self.selectedTrackIDs.count]
    : @"Favorites";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:SonoraWhiteSectionTitleLabel(displayTitle)];

    if (self.multiSelectMode) {
        UIBarButtonItem *cancelItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"]
                                                                        style:UIBarButtonItemStylePlain
                                                                       target:self
                                                                       action:@selector(cancelFavoritesSelectionTapped)];
        SonoraConfigureNavigationIconBarButtonItem(cancelItem, @"Cancel Selection");
        UIBarButtonItem *favoriteItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"heart.fill"]
                                                                          style:UIBarButtonItemStylePlain
                                                                         target:self
                                                                         action:@selector(favoriteSelectedFavoritesTapped)];
        SonoraConfigureNavigationIconBarButtonItem(favoriteItem, @"Favorite Selected");
        favoriteItem.tintColor = [UIColor colorWithRed:1.0 green:0.35 blue:0.42 alpha:1.0];
        UIBarButtonItem *deleteItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"trash.fill"]
                                                                        style:UIBarButtonItemStylePlain
                                                                       target:self
                                                                       action:@selector(removeSelectedFavoritesTapped)];
        SonoraConfigureNavigationIconBarButtonItem(deleteItem, @"Delete Selected");
        self.navigationItem.rightBarButtonItems = @[cancelItem, deleteItem, favoriteItem];
        return;
    }

    UIBarButtonItem *searchItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass"]
                                                                    style:UIBarButtonItemStylePlain
                                                                   target:self
                                                                   action:@selector(searchButtonTapped)];
    SonoraConfigureNavigationIconBarButtonItem(searchItem, @"Search");
    self.navigationItem.rightBarButtonItems = @[searchItem];
}

- (void)cancelFavoritesSelectionTapped {
    [self setFavoritesSelectionModeEnabled:NO];
}

- (void)setFavoritesSelectionModeEnabled:(BOOL)enabled {
    self.multiSelectMode = enabled;
    if (!enabled) {
        [self.selectedTrackIDs removeAllObjects];
    }
    if (enabled && self.searchController.isActive) {
        self.searchController.active = NO;
    }
    [self refreshNavigationItemsForFavoritesSelectionState];
    [self.tableView reloadData];
}

- (SonoraTrack * _Nullable)favoriteTrackAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row < 0 || indexPath.row >= self.filteredTracks.count) {
        return nil;
    }
    return self.filteredTracks[indexPath.row];
}

- (void)toggleFavoritesSelectionForTrackID:(NSString *)trackID forceSelected:(BOOL)forceSelected {
    if (trackID.length == 0) {
        return;
    }
    BOOL hasTrack = [self.selectedTrackIDs containsObject:trackID];
    if (forceSelected) {
        if (!hasTrack) {
            [self.selectedTrackIDs addObject:trackID];
        }
    } else if (hasTrack) {
        [self.selectedTrackIDs removeObject:trackID];
    } else {
        [self.selectedTrackIDs addObject:trackID];
    }

    if (self.selectedTrackIDs.count == 0) {
        [self setFavoritesSelectionModeEnabled:NO];
    } else {
        [self refreshNavigationItemsForFavoritesSelectionState];
        [self.tableView reloadData];
    }
}

- (void)handleTrackLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) {
        return;
    }
    CGPoint point = [gesture locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:point];
    if (indexPath == nil) {
        return;
    }
    SonoraTrack *track = [self favoriteTrackAtIndexPath:indexPath];
    if (track == nil) {
        return;
    }
    [self setFavoritesSelectionModeEnabled:YES];
    [self toggleFavoritesSelectionForTrackID:track.identifier forceSelected:YES];
}

- (void)favoriteSelectedFavoritesTapped {
    if (self.selectedTrackIDs.count == 0) {
        return;
    }
    for (NSString *trackID in self.selectedTrackIDs) {
        [SonoraFavoritesStore.sharedStore setTrackID:trackID favorite:YES];
    }
    [self setFavoritesSelectionModeEnabled:NO];
    [self reloadFavorites];
}

- (void)removeSelectedFavoritesTapped {
    if (self.selectedTrackIDs.count == 0) {
        return;
    }
    for (NSString *trackID in self.selectedTrackIDs) {
        [SonoraFavoritesStore.sharedStore setTrackID:trackID favorite:NO];
    }
    [self setFavoritesSelectionModeEnabled:NO];
    [self reloadFavorites];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return self.filteredTracks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SonoraTrackCell *cell = [tableView dequeueReusableCellWithIdentifier:@"FavoriteTrackCell" forIndexPath:indexPath];

    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    SonoraTrack *track = self.filteredTracks[indexPath.row];
    SonoraTrack *currentTrack = playback.currentTrack;
    BOOL isCurrent = (currentTrack != nil && [currentTrack.identifier isEqualToString:track.identifier]);
    BOOL showsPlaybackIndicator = (isCurrent && playback.isPlaying);
    [cell configureWithTrack:track isCurrent:isCurrent showsPlaybackIndicator:showsPlaybackIndicator];
    cell.accessoryType = (self.multiSelectMode && [self.selectedTrackIDs containsObject:track.identifier])
    ? UITableViewCellAccessoryCheckmark
    : UITableViewCellAccessoryNone;

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= self.filteredTracks.count) {
        return;
    }

    if (self.multiSelectMode) {
        SonoraTrack *selectionTrack = [self favoriteTrackAtIndexPath:indexPath];
        if (selectionTrack != nil) {
            [self toggleFavoritesSelectionForTrackID:selectionTrack.identifier forceSelected:NO];
        }
        return;
    }

    SonoraTrack *selectedTrack = self.filteredTracks[indexPath.row];
    SonoraTrack *currentTrack = SonoraPlaybackManager.sharedManager.currentTrack;
    if (currentTrack != nil && [currentTrack.identifier isEqualToString:selectedTrack.identifier]) {
        [self openPlayer];
        return;
    }

    NSArray<SonoraTrack *> *queue = self.filteredTracks;
    NSInteger startIndex = indexPath.row;
    [self openPlayer];
    dispatch_async(dispatch_get_main_queue(), ^{
        [SonoraPlaybackManager.sharedManager setShuffleEnabled:NO];
        [SonoraPlaybackManager.sharedManager playTracks:queue startIndex:startIndex];
    });
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (self.multiSelectMode) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }
    if (indexPath.row >= self.filteredTracks.count) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }

    SonoraTrack *track = self.filteredTracks[indexPath.row];

    UIContextualAction *removeAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                                title:@"Unfollow"
                                                                              handler:^(__unused UIContextualAction * _Nonnull action,
                                                                                        __unused UIView * _Nonnull sourceView,
                                                                                        void (^ _Nonnull completionHandler)(BOOL)) {
        [SonoraFavoritesStore.sharedStore setTrackID:track.identifier favorite:NO];
        [self reloadFavorites];
        completionHandler(YES);
    }];
    removeAction.image = [UIImage systemImageNamed:@"heart.slash.fill"];
    removeAction.backgroundColor = [UIColor colorWithWhite:0.40 alpha:1.0];

    UIContextualAction *addAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                            title:@"Add"
                                                                          handler:^(__unused UIContextualAction * _Nonnull action,
                                                                                    __unused UIView * _Nonnull sourceView,
                                                                                    void (^ _Nonnull completionHandler)(BOOL)) {
        SonoraPresentQuickAddTrackToPlaylist(self, track.identifier, nil);
        completionHandler(YES);
    }];
    addAction.image = [UIImage systemImageNamed:@"text.badge.plus"];
    addAction.backgroundColor = [UIColor colorWithRed:0.16 green:0.47 blue:0.95 alpha:1.0];

    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[removeAction, addAction]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (self.multiSelectMode) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }
    (void)indexPath;
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.searchQuery = searchController.searchBar.text ?: @"";
    [self applySearchFilterAndReload];
    [self updateSearchControllerAttachment];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView == self.tableView) {
        [self updateSearchControllerAttachment];
    }
}

@end

#pragma mark - Playlist Detail

@interface SonoraPlaylistDetailViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>

@property (nonatomic, copy) NSString *playlistID;
@property (nonatomic, strong, nullable) SonoraPlaylist *playlist;
@property (nonatomic, strong, nullable) SonoraSharedPlaylistSnapshot *sharedSnapshot;
@property (nonatomic, copy) NSArray<SonoraTrack *> *tracks;
@property (nonatomic, copy) NSArray<SonoraTrack *> *filteredTracks;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UIButton *sleepButton;
@property (nonatomic, strong) UIButton *shuffleButton;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, copy) NSString *searchQuery;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, assign) BOOL compactTitleVisible;
@property (nonatomic, assign) BOOL sharedCoverLoading;
@property (nonatomic, assign) BOOL searchControllerAttached;
@property (nonatomic, assign) BOOL multiSelectMode;
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *selectedTrackIDs;
@property (nonatomic, strong) UILongPressGestureRecognizer *selectionLongPressRecognizer;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *sharedArtworkCache;
@property (nonatomic, strong) NSMutableSet<NSString *> *sharedArtworkLoadingTrackIDs;

@end

@implementation SonoraPlaylistDetailViewController

- (instancetype)initWithPlaylistID:(NSString *)playlistID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _playlistID = [playlistID copy];
        _tracks = @[];
        _filteredTracks = @[];
        _selectedTrackIDs = [NSMutableOrderedSet orderedSet];
        _multiSelectMode = NO;
        _sharedArtworkCache = [[NSCache alloc] init];
        _sharedArtworkLoadingTrackIDs = [NSMutableSet set];
    }
    return self;
}

- (instancetype)initWithSharedPlaylistSnapshot:(SonoraSharedPlaylistSnapshot *)snapshot {
    self = [self initWithPlaylistID:snapshot.playlistID ?: SonoraSharedPlaylistSyntheticID(snapshot.remoteID)];
    if (self) {
        _sharedSnapshot = snapshot;
    }
    return self;
}

- (BOOL)isSharedPlaylistMode {
    return (self.sharedSnapshot != nil ||
            [self.playlistID hasPrefix:SonoraSharedPlaylistSyntheticPrefix] ||
            [SonoraSharedPlaylistStore.sharedStore snapshotForPlaylistID:self.playlistID] != nil);
}

- (SonoraSharedPlaylistSnapshot * _Nullable)resolvedSharedSnapshot {
    SonoraSharedPlaylistSnapshot *storedSnapshot = [SonoraSharedPlaylistStore.sharedStore snapshotForPlaylistID:self.playlistID];
    if (storedSnapshot != nil) {
        self.sharedSnapshot = storedSnapshot;
        return storedSnapshot;
    }
    return self.sharedSnapshot;
}

- (NSString * _Nullable)sharedArtworkURLForTrack:(SonoraTrack *)track {
    if (track.identifier.length == 0 || ![self isSharedPlaylistMode]) {
        return nil;
    }
    SonoraSharedPlaylistSnapshot *snapshot = [self resolvedSharedSnapshot];
    NSString *urlString = snapshot.trackArtworkURLByTrackID[track.identifier];
    return urlString.length > 0 ? urlString : nil;
}

- (void)loadSharedCoverIfNeeded {
    if (![self isSharedPlaylistMode] || self.sharedCoverLoading) {
        return;
    }
    SonoraSharedPlaylistSnapshot *snapshot = [self resolvedSharedSnapshot];
    NSString *urlString = snapshot.coverURL ?: @"";
    if (snapshot == nil || snapshot.coverImage != nil || urlString.length == 0) {
        return;
    }
    NSURL *url = [NSURL URLWithString:urlString];
    if (url == nil) {
        return;
    }

    self.sharedCoverLoading = YES;
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:url
                                                            completionHandler:^(NSData * _Nullable data,
                                                                                NSURLResponse * _Nullable response,
                                                                                NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        UIImage *image = nil;
        if (error == nil && data.length > 0) {
            image = [UIImage imageWithData:data];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            strongSelf.sharedCoverLoading = NO;
            if (image == nil) {
                return;
            }
            snapshot.coverImage = image;
            strongSelf.coverView.image = image;
            if ([SonoraSharedPlaylistStore.sharedStore isSnapshotLikedForPlaylistID:snapshot.playlistID]) {
                SonoraSharedPlaylistSnapshot *snapshotToPersist = snapshot;
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                    SonoraSharedPlaylistPerformWithoutDidChangeNotification(^{
                        [SonoraSharedPlaylistStore.sharedStore saveSnapshot:snapshotToPersist];
                    });
                });
            }
        });
    }];
    [task resume];
}

- (void)loadSharedArtworkIfNeededForTrack:(SonoraTrack *)track {
    if (track == nil || track.artwork != nil || ![self isSharedPlaylistMode]) {
        return;
    }
    NSString *trackID = track.identifier ?: @"";
    if (trackID.length == 0) {
        return;
    }
    UIImage *cachedImage = [self.sharedArtworkCache objectForKey:trackID];
    if (cachedImage != nil) {
        track.artwork = cachedImage;
        return;
    }
    if ([self.sharedArtworkLoadingTrackIDs containsObject:trackID]) {
        return;
    }
    NSString *urlString = [self sharedArtworkURLForTrack:track];
    NSURL *url = [NSURL URLWithString:urlString ?: @""];
    if (url == nil) {
        return;
    }

    [self.sharedArtworkLoadingTrackIDs addObject:trackID];
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:url
                                                            completionHandler:^(NSData * _Nullable data,
                                                                                NSURLResponse * _Nullable response,
                                                                                NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        UIImage *image = nil;
        if (error == nil && data.length > 0) {
            image = [UIImage imageWithData:data];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [strongSelf.sharedArtworkLoadingTrackIDs removeObject:trackID];
            if (image == nil) {
                return;
            }
            [strongSelf.sharedArtworkCache setObject:image forKey:trackID];
            track.artwork = image;
            SonoraSharedPlaylistSnapshot *snapshot = [strongSelf resolvedSharedSnapshot];
            if (snapshot != nil && [SonoraSharedPlaylistStore.sharedStore isSnapshotLikedForPlaylistID:snapshot.playlistID]) {
                SonoraSharedPlaylistSnapshot *snapshotToPersist = snapshot;
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                    SonoraSharedPlaylistPerformWithoutDidChangeNotification(^{
                        [SonoraSharedPlaylistStore.sharedStore saveSnapshot:snapshotToPersist];
                    });
                });
            }
            NSUInteger row = [strongSelf.filteredTracks indexOfObjectPassingTest:^BOOL(SonoraTrack * _Nonnull candidate, NSUInteger idx, BOOL * _Nonnull stop) {
                return [candidate.identifier isEqualToString:trackID];
            }];
            if (row != NSNotFound) {
                NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
                if ([[strongSelf.tableView indexPathsForVisibleRows] containsObject:indexPath]) {
                    [strongSelf.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
                }
            }
        });
    }];
    [task resume];
}

- (NSArray<NSString *> *)matchingLocalTrackIDsForSharedSnapshot:(SonoraSharedPlaylistSnapshot *)snapshot {
    NSArray<SonoraTrack *> *libraryTracks = SonoraLibraryManager.sharedManager.tracks;
    if (libraryTracks.count == 0) {
        libraryTracks = [SonoraLibraryManager.sharedManager reloadTracks];
    }
    NSMutableArray<NSString *> *matched = [NSMutableArray array];
    for (SonoraTrack *remoteTrack in snapshot.tracks) {
        NSString *remoteTitle = SonoraSharedPlaylistNormalizeText(remoteTrack.title);
        NSString *remoteArtist = SonoraSharedPlaylistNormalizeText(remoteTrack.artist);
        if (remoteTitle.length == 0) {
            continue;
        }
        for (SonoraTrack *localTrack in libraryTracks) {
            if (localTrack.identifier.length == 0) {
                continue;
            }
            NSString *localTitle = SonoraSharedPlaylistNormalizeText(localTrack.title);
            NSString *localArtist = SonoraSharedPlaylistNormalizeText(localTrack.artist);
            if (![localTitle isEqualToString:remoteTitle]) {
                continue;
            }
            if (remoteArtist.length > 0 && localArtist.length > 0 &&
                ![localArtist containsString:remoteArtist] &&
                ![remoteArtist containsString:localArtist]) {
                continue;
            }
            [matched addObject:localTrack.identifier];
            break;
        }
    }
    return [[NSOrderedSet orderedSetWithArray:matched] array];
}

- (void)downloadSharedPlaylistTracks:(NSArray<SonoraTrack *> *)tracks
                               index:(NSUInteger)index
                            progress:(UIAlertController *)progress
                    importedTrackIDs:(NSMutableArray<NSString *> *)importedTrackIDs
                          completion:(dispatch_block_t)completion {
    if (index >= tracks.count) {
        if (completion != nil) {
            completion();
        }
        return;
    }

    SonoraTrack *track = tracks[index];
    dispatch_async(dispatch_get_main_queue(), ^{
        progress.message = [NSString stringWithFormat:@"Downloading track %lu/%lu...",
                            (unsigned long)(index + 1),
                            (unsigned long)tracks.count];
    });
    NSString *suggestedName = track.artist.length > 0
    ? [NSString stringWithFormat:@"%@ - %@", track.artist, track.title ?: @"Track"]
    : (track.title ?: @"Track");
    __weak typeof(self) weakSelf = self;
    SonoraSharedPlaylistDownloadedFileURL(track.url.absoluteString ?: @"", suggestedName, ^(NSURL * _Nullable fileURL, __unused NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (fileURL != nil) {
            [importedTrackIDs addObject:fileURL.path ?: @""];
        }
        [strongSelf downloadSharedPlaylistTracks:tracks
                                           index:(index + 1)
                                        progress:progress
                                importedTrackIDs:importedTrackIDs
                                      completion:completion];
    });
}

- (NSString *)sharedPlaylistEncodedFilename:(NSString *)value {
    NSString *safeValue = value.length > 0 ? value : @"file.bin";
    return [safeValue stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet] ?: safeValue;
}

- (NSString *)sharedPlaylistAudioMimeTypeForExtension:(NSString *)extension {
    NSString *normalized = extension.lowercaseString ?: @"";
    if ([normalized isEqualToString:@"m4a"]) {
        return @"audio/mp4";
    }
    if ([normalized isEqualToString:@"aac"]) {
        return @"audio/aac";
    }
    if ([normalized isEqualToString:@"wav"]) {
        return @"audio/wav";
    }
    if ([normalized isEqualToString:@"ogg"]) {
        return @"audio/ogg";
    }
    if ([normalized isEqualToString:@"flac"]) {
        return @"audio/flac";
    }
    return @"audio/mpeg";
}

- (void)uploadSharedPlaylistBinaryAtEndpointPath:(NSString *)endpointPath
                                   baseURLString:(NSString *)baseURLString
                                        filename:(NSString *)filename
                                        mimeType:(NSString *)mimeType
                                            data:(NSData * _Nullable)data
                                         fileURL:(NSURL * _Nullable)fileURL
                                      completion:(void (^)(BOOL success))completion {
    if ((data.length == 0) && !fileURL.isFileURL) {
        if (completion != nil) {
            completion(YES);
        }
        return;
    }

    NSString *urlString = [NSString stringWithFormat:@"%@%@?filename=%@",
                           baseURLString,
                           endpointPath,
                           [self sharedPlaylistEncodedFilename:filename]];
    NSURL *uploadURL = [NSURL URLWithString:urlString];
    if (uploadURL == nil) {
        if (completion != nil) {
            completion(NO);
        }
        return;
    }

    NSMutableURLRequest *uploadRequest = [NSMutableURLRequest requestWithURL:uploadURL];
    uploadRequest.HTTPMethod = @"POST";
    uploadRequest.timeoutInterval = 600.0;
    [uploadRequest setValue:(mimeType.length > 0 ? mimeType : @"application/octet-stream") forHTTPHeaderField:@"Content-Type"];
    if (fileURL.isFileURL) {
        SonoraSharedPlaylistUploadFileRequest(uploadRequest, fileURL, 600.0, ^(__unused NSData * _Nullable responseData, __unused NSHTTPURLResponse * _Nullable response, NSError * _Nullable error) {
            if (completion != nil) {
                completion(error == nil);
            }
        });
        return;
    }

    uploadRequest.HTTPBody = data;
    SonoraSharedPlaylistPerformRequest(uploadRequest, 600.0, ^(__unused NSData * _Nullable responseData, __unused NSHTTPURLResponse * _Nullable response, NSError * _Nullable error) {
        if (completion != nil) {
            completion(error == nil);
        }
    });
}

- (void)uploadSharedPlaylistTracks:(NSArray<SonoraTrack *> *)tracks
                             index:(NSUInteger)index
                          remoteID:(NSString *)remoteID
                     baseURLString:(NSString *)baseURLString
                          progress:(UIAlertController *)progress
                        completion:(void (^)(BOOL success))completion {
    if (index >= tracks.count) {
        if (completion != nil) {
            completion(YES);
        }
        return;
    }

    SonoraTrack *track = tracks[index];
    dispatch_async(dispatch_get_main_queue(), ^{
        progress.message = [NSString stringWithFormat:@"Uploading track %lu/%lu...",
                            (unsigned long)(index + 1),
                            (unsigned long)tracks.count];
    });

    NSData *artworkData = track.artwork != nil ? UIImageJPEGRepresentation(track.artwork, 0.86) : nil;
    NSString *artworkName = [NSString stringWithFormat:@"%@.jpg",
                             track.identifier.length > 0
                             ? track.identifier
                             : [NSString stringWithFormat:@"track_%lu", (unsigned long)index]];
    NSString *artworkEndpoint = [NSString stringWithFormat:@"/api/shared-playlists/%@/tracks/%lu/artwork",
                                 remoteID,
                                 (unsigned long)index];

    __weak typeof(self) weakSelf = self;
    [self uploadSharedPlaylistBinaryAtEndpointPath:artworkEndpoint
                                     baseURLString:baseURLString
                                          filename:artworkName
                                          mimeType:@"image/jpeg"
                                              data:artworkData
                                           fileURL:nil
                                        completion:^(BOOL artworkSuccess) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!artworkSuccess || strongSelf == nil) {
            if (completion != nil) {
                completion(NO);
            }
            return;
        }

        if (!track.url.isFileURL) {
            [strongSelf uploadSharedPlaylistTracks:tracks
                                             index:(index + 1)
                                          remoteID:remoteID
                                     baseURLString:baseURLString
                                          progress:progress
                                        completion:completion];
            return;
        }

        NSString *extension = track.url.pathExtension.length > 0 ? track.url.pathExtension.lowercaseString : @"mp3";
        NSString *fileName = track.url.lastPathComponent.length > 0
        ? track.url.lastPathComponent
        : [NSString stringWithFormat:@"track_%lu.%@", (unsigned long)index, extension];
        NSString *audioEndpoint = [NSString stringWithFormat:@"/api/shared-playlists/%@/tracks/%lu/file",
                                   remoteID,
                                   (unsigned long)index];
        [strongSelf uploadSharedPlaylistBinaryAtEndpointPath:audioEndpoint
                                               baseURLString:baseURLString
                                                    filename:fileName
                                                    mimeType:[strongSelf sharedPlaylistAudioMimeTypeForExtension:extension]
                                                        data:nil
                                                     fileURL:track.url
                                                  completion:^(BOOL audioSuccess) {
            if (!audioSuccess) {
                if (completion != nil) {
                    completion(NO);
                }
                return;
            }
            [strongSelf uploadSharedPlaylistTracks:tracks
                                             index:(index + 1)
                                          remoteID:remoteID
                                     baseURLString:baseURLString
                                          progress:progress
                                        completion:completion];
        }];
    }];
}

- (void)addSharedPlaylistLocallyTapped {
    SonoraSharedPlaylistSnapshot *snapshot = [self resolvedSharedSnapshot];
    if (snapshot == nil) {
        return;
    }
    UIAlertController *progress = SonoraPresentBlockingProgressAlert(self, @"Adding Playlist", @"Downloading tracks...");
    __weak typeof(self) weakSelf = self;
    NSMutableArray<NSString *> *importedTrackIDs = [NSMutableArray array];
    [self downloadSharedPlaylistTracks:snapshot.tracks
                                 index:0
                              progress:progress
                      importedTrackIDs:importedTrackIDs
                            completion:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            [progress dismissViewControllerAnimated:YES completion:nil];
            if (strongSelf == nil) {
                return;
            }
            [SonoraLibraryManager.sharedManager reloadTracks];
            NSMutableArray<NSString *> *resolvedTrackIDs = [NSMutableArray array];
            for (NSString *path in importedTrackIDs) {
                SonoraTrack *importedTrack = [SonoraLibraryManager.sharedManager trackForIdentifier:path];
                if (importedTrack.identifier.length > 0) {
                    [resolvedTrackIDs addObject:importedTrack.identifier];
                } else if (path.length > 0) {
                    [resolvedTrackIDs addObject:path];
                }
            }
            SonoraPlaylist *created = [SonoraPlaylistStore.sharedStore addPlaylistWithName:snapshot.name
                                                                                  trackIDs:[resolvedTrackIDs copy]
                                                                                coverImage:snapshot.coverImage];
            if (created == nil) {
                SonoraPresentAlert(strongSelf, @"Error", @"Could not create local playlist.");
                return;
            }
            strongSelf.sharedSnapshot = nil;
            SonoraPlaylistDetailViewController *detail = [[SonoraPlaylistDetailViewController alloc] initWithPlaylistID:created.playlistID];
            NSMutableArray<UIViewController *> *stack = [strongSelf.navigationController.viewControllers mutableCopy];
            [stack removeLastObject];
            [stack addObject:detail];
            [strongSelf.navigationController setViewControllers:[stack copy] animated:YES];
        });
    }];
}

- (void)toggleSharedPlaylistLikeTapped {
    SonoraSharedPlaylistSnapshot *snapshot = [self resolvedSharedSnapshot];
    if (snapshot == nil) {
        return;
    }
    self.sharedSnapshot = snapshot;
    if ([SonoraSharedPlaylistStore.sharedStore isSnapshotLikedForPlaylistID:snapshot.playlistID]) {
        [SonoraSharedPlaylistStore.sharedStore removeSnapshotForPlaylistID:snapshot.playlistID];
    } else {
        [SonoraSharedPlaylistStore.sharedStore saveSnapshot:snapshot];
        SonoraSharedPlaylistWarmPersistentCache(snapshot, nil);
    }
}

- (void)shareCurrentPlaylistLinkTapped {
    SonoraSharedPlaylistSnapshot *snapshot = [self resolvedSharedSnapshot];
    NSString *shareURL = snapshot.shareURL ?: @"";
    if (shareURL.length == 0) {
        SonoraPresentAlert(self, @"Error", @"Share link is unavailable.");
        return;
    }
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[shareURL] applicationActivities:nil];
    UIPopoverPresentationController *popover = share.popoverPresentationController;
    if (popover != nil) {
        popover.barButtonItem = self.navigationItem.rightBarButtonItem;
    }
    [self presentViewController:share animated:YES completion:nil];
}

- (void)sharePlaylistTapped {
    if (self.playlist == nil || [self isSharedPlaylistMode]) {
        return;
    }
    UIAlertController *progress = SonoraPresentBlockingProgressAlert(self, @"Sharing Playlist", @"Uploading tracks to server...");
    NSString *playlistName = self.playlist.name ?: @"Playlist";
    NSArray<SonoraTrack *> *tracksSnapshot = [self.tracks copy];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        UIImage *cover = [SonoraPlaylistStore.sharedStore coverForPlaylist:self.playlist
                                                               library:SonoraLibraryManager.sharedManager
                                                                  size:CGSizeMake(768.0, 768.0)];
        NSMutableDictionary<NSString *, id> *manifest = [NSMutableDictionary dictionary];
        manifest[@"name"] = playlistName;
        NSMutableArray<NSDictionary<NSString *, id> *> *trackItems = [NSMutableArray arrayWithCapacity:tracksSnapshot.count];
        [tracksSnapshot enumerateObjectsUsingBlock:^(SonoraTrack * _Nonnull track, NSUInteger idx, __unused BOOL * _Nonnull stop) {
            NSMutableDictionary<NSString *, id> *trackPayload = [NSMutableDictionary dictionary];
            trackPayload[@"id"] = track.identifier ?: @"";
            trackPayload[@"title"] = track.title ?: @"";
            trackPayload[@"artist"] = track.artist ?: @"";
            trackPayload[@"durationMs"] = @((NSInteger)llround(MAX(track.duration, 0.0) * 1000.0));
            [trackItems addObject:[trackPayload copy]];
        }];
        manifest[@"tracks"] = [trackItems copy];
        NSString *baseURLString = [SonoraSharedPlaylistBackendBaseURLString() stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSURL *requestURL = [NSURL URLWithString:[baseURLString stringByAppendingString:@"/api/shared-playlists"]];
        if (requestURL == nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [progress dismissViewControllerAnimated:YES completion:nil];
                SonoraPresentAlert(self, @"Error", @"Backend URL is invalid.");
            });
            return;
        }
        NSData *manifestData = [NSJSONSerialization dataWithJSONObject:manifest options:0 error:nil];
        NSMutableURLRequest *createRequest = [NSMutableURLRequest requestWithURL:requestURL];
        createRequest.HTTPMethod = @"POST";
        createRequest.timeoutInterval = 120.0;
        [createRequest setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        [createRequest setValue:@"application/json" forHTTPHeaderField:@"Accept"];
        createRequest.HTTPBody = manifestData;
        NSData *coverData = cover != nil ? UIImageJPEGRepresentation(cover, 0.88) : nil;
        __weak typeof(self) weakSelf = self;
        SonoraSharedPlaylistPerformRequest(createRequest, 120.0, ^(NSData * _Nullable createData, __unused NSHTTPURLResponse * _Nullable createResponse, NSError * _Nullable error) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            NSDictionary *createPayload = createData.length > 0 ? [NSJSONSerialization JSONObjectWithData:createData options:0 error:nil] : nil;
            NSString *remoteID = [createPayload[@"id"] isKindOfClass:NSString.class] ? createPayload[@"id"] : @"";
            NSString *shareURL = [createPayload[@"shareUrl"] isKindOfClass:NSString.class] ? createPayload[@"shareUrl"] : createPayload[@"url"];
            if (strongSelf == nil || error != nil || remoteID.length == 0 || shareURL.length == 0) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [progress dismissViewControllerAnimated:YES completion:nil];
                    SonoraPresentAlert(weakSelf, @"Error", @"Could not share playlist.");
                });
                return;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                progress.message = @"Uploading cover...";
            });
            [strongSelf uploadSharedPlaylistBinaryAtEndpointPath:[NSString stringWithFormat:@"/api/shared-playlists/%@/cover", remoteID]
                                                   baseURLString:baseURLString
                                                        filename:@"cover.jpg"
                                                        mimeType:@"image/jpeg"
                                                            data:coverData
                                                         fileURL:nil
                                                      completion:^(BOOL coverSuccess) {
                if (!coverSuccess) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [progress dismissViewControllerAnimated:YES completion:nil];
                        SonoraPresentAlert(strongSelf, @"Error", @"Could not upload playlist cover.");
                    });
                    return;
                }

                [strongSelf uploadSharedPlaylistTracks:tracksSnapshot
                                                 index:0
                                              remoteID:remoteID
                                         baseURLString:baseURLString
                                              progress:progress
                                            completion:^(BOOL success) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [progress dismissViewControllerAnimated:YES completion:nil];
                        if (!success) {
                            SonoraPresentAlert(strongSelf, @"Error", @"Could not share playlist.");
                            return;
                        }
                        UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[shareURL] applicationActivities:nil];
                        UIPopoverPresentationController *popover = share.popoverPresentationController;
                        if (popover != nil) {
                            popover.barButtonItem = strongSelf.navigationItem.rightBarButtonItem;
                        }
                        [strongSelf presentViewController:share animated:YES completion:nil];
                    });
                }];
            }];
        });
    });
}
- (void)refreshNavigationItemsForPlaylistSelectionState {
    if (self.multiSelectMode) {
        NSString *displayTitle = [NSString stringWithFormat:@"%lu Selected", (unsigned long)self.selectedTrackIDs.count];
        self.navigationItem.title = nil;
        self.navigationItem.titleView = nil;
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:SonoraWhiteSectionTitleLabel(displayTitle)];

        UIBarButtonItem *cancelItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"]
                                                                        style:UIBarButtonItemStylePlain
                                                                       target:self
                                                                       action:@selector(cancelPlaylistSelectionTapped)];
        SonoraConfigureNavigationIconBarButtonItem(cancelItem, @"Cancel Selection");
        UIBarButtonItem *favoriteItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"heart.fill"]
                                                                          style:UIBarButtonItemStylePlain
                                                                         target:self
                                                                         action:@selector(favoriteSelectedPlaylistTracksTapped)];
        SonoraConfigureNavigationIconBarButtonItem(favoriteItem, @"Favorite Selected");
        favoriteItem.tintColor = [UIColor colorWithRed:1.0 green:0.35 blue:0.42 alpha:1.0];
        UIBarButtonItem *deleteItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"trash.fill"]
                                                                        style:UIBarButtonItemStylePlain
                                                                       target:self
                                                                       action:@selector(removeSelectedPlaylistTracksTapped)];
        SonoraConfigureNavigationIconBarButtonItem(deleteItem, @"Delete Selected");
        UIBarButtonItem *tightSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace
                                                                                      target:nil
                                                                                      action:nil];
        tightSpace.width = -8.0;
        self.navigationItem.rightBarButtonItems = @[cancelItem, deleteItem, tightSpace, favoriteItem];
        return;
    }
    self.navigationItem.leftBarButtonItem = nil;
    [self updateOptionsButtonVisibility];
}

- (void)setPlaylistSelectionModeEnabled:(BOOL)enabled {
    if (enabled && [self isSharedPlaylistMode]) {
        return;
    }
    self.multiSelectMode = enabled;
    if (!enabled) {
        [self.selectedTrackIDs removeAllObjects];
    }
    if (enabled && self.searchController.isActive) {
        self.searchController.active = NO;
    }
    [self refreshNavigationItemsForPlaylistSelectionState];
    [self updateNavigationTitleVisibility];
    [self.tableView reloadData];
}

- (SonoraTrack * _Nullable)playlistTrackAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row < 0 || indexPath.row >= self.filteredTracks.count) {
        return nil;
    }
    return self.filteredTracks[indexPath.row];
}

- (void)togglePlaylistSelectionForTrackID:(NSString *)trackID forceSelected:(BOOL)forceSelected {
    if (trackID.length == 0) {
        return;
    }
    BOOL hasTrack = [self.selectedTrackIDs containsObject:trackID];
    if (forceSelected) {
        if (!hasTrack) {
            [self.selectedTrackIDs addObject:trackID];
        }
    } else if (hasTrack) {
        [self.selectedTrackIDs removeObject:trackID];
    } else {
        [self.selectedTrackIDs addObject:trackID];
    }

    if (self.selectedTrackIDs.count == 0) {
        [self setPlaylistSelectionModeEnabled:NO];
    } else {
        [self refreshNavigationItemsForPlaylistSelectionState];
        [self updateNavigationTitleVisibility];
        [self.tableView reloadData];
    }
}

- (void)handleTrackLongPress:(UILongPressGestureRecognizer *)gesture {
    if ([self isSharedPlaylistMode]) {
        return;
    }
    if (gesture.state != UIGestureRecognizerStateBegan) {
        return;
    }
    CGPoint point = [gesture locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:point];
    if (indexPath == nil) {
        return;
    }
    SonoraTrack *track = [self playlistTrackAtIndexPath:indexPath];
    if (track == nil) {
        return;
    }
    [self setPlaylistSelectionModeEnabled:YES];
    [self togglePlaylistSelectionForTrackID:track.identifier forceSelected:YES];
}

- (void)favoriteSelectedPlaylistTracksTapped {
    if (self.selectedTrackIDs.count == 0) {
        return;
    }
    for (NSString *trackID in self.selectedTrackIDs) {
        [SonoraFavoritesStore.sharedStore setTrackID:trackID favorite:YES];
    }
    [self setPlaylistSelectionModeEnabled:NO];
    [self reloadData];
}

- (void)removeSelectedPlaylistTracksTapped {
    if (self.selectedTrackIDs.count == 0) {
        return;
    }
    for (NSString *trackID in self.selectedTrackIDs) {
        [SonoraPlaylistStore.sharedStore removeTrackID:trackID fromPlaylistID:self.playlistID];
    }
    [self setPlaylistSelectionModeEnabled:NO];
    [self reloadData];
}

- (void)cancelPlaylistSelectionTapped {
    [self setPlaylistSelectionModeEnabled:NO];
}


- (void)viewDidLoad {
    [super viewDidLoad];

    self.navigationItem.titleView = nil;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.navigationItem.rightBarButtonItem = nil;
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    [self setupTableView];
    [self setupSearch];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(reloadData)
                                               name:SonoraPlaylistsDidChangeNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handleAppForeground)
                                               name:UIApplicationWillEnterForegroundNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handlePlaybackChanged)
                                               name:SonoraPlaybackStateDidChangeNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(updateSleepButton)
                                               name:SonoraSleepTimerDidChangeNotification
                                             object:nil];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshNavigationItemsForPlaylistSelectionState];
    [self updateSearchControllerAttachment];
    [self reloadData];
}

- (void)handleAppForeground {
    [SonoraLibraryManager.sharedManager reloadTracks];
    [self reloadData];
}

- (void)handlePlaybackChanged {
    [self updatePlayButtonState];
    [self.tableView reloadData];
}

- (void)setupTableView {
    UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    tableView.translatesAutoresizingMaskIntoConstraints = NO;
    tableView.dataSource = self;
    tableView.delegate = self;
    tableView.rowHeight = 54.0;
    tableView.alwaysBounceVertical = YES;
    tableView.sectionHeaderHeight = 0.0;
    tableView.sectionFooterHeight = 0.0;
    tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    if (@available(iOS 15.0, *)) {
        tableView.sectionHeaderTopPadding = 0.0;
    }
    [tableView registerClass:SonoraTrackCell.class forCellReuseIdentifier:@"PlaylistTrackCell"];
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                                                             action:@selector(handleTrackLongPress:)];
    [tableView addGestureRecognizer:longPress];
    self.selectionLongPressRecognizer = longPress;

    self.tableView = tableView;
    [self.view addSubview:tableView];

    [NSLayoutConstraint activateConstraints:@[
        [tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    self.tableView.tableHeaderView = [self headerViewForWidth:self.view.bounds.size.width];
    [self updatePlayButtonState];
    [self updateSleepButton];
}

- (void)setupSearch {
    self.searchController = SonoraBuildSearchController(self, @"Search In Playlist");
    self.navigationItem.searchController = nil;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
    self.definesPresentationContext = YES;
    self.searchControllerAttached = NO;
}

- (void)updateSearchControllerAttachment {
    BOOL shouldAttach = SonoraShouldAttachSearchController(self.searchControllerAttached,
                                                       self.searchController,
                                                       self.tableView,
                                                       SonoraSearchRevealThreshold);
    if (shouldAttach == self.searchControllerAttached) {
        return;
    }

    self.searchControllerAttached = shouldAttach;
    SonoraApplySearchControllerAttachment(self.navigationItem,
                                      self.navigationController.navigationBar,
                                      self.searchController,
                                      shouldAttach,
                                      (self.view.window != nil));
}

- (void)applySearchFilterAndReload {
    self.filteredTracks = SonoraFilterTracksByQuery(self.tracks, self.searchQuery);
    [self.tableView reloadData];
    [self updateEmptyState];
}

- (void)updateEmptyState {
    if (self.filteredTracks.count > 0) {
        self.tableView.backgroundView = nil;
        return;
    }

    UILabel *label = [[UILabel alloc] init];
    label.textColor = UIColor.secondaryLabelColor;
    label.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    if (self.tracks.count == 0) {
        label.text = @"Tracks missing. Re-add files to On My iPhone/Sonora/Sonora";
    } else {
        label.text = @"No matching tracks.";
    }
    self.tableView.backgroundView = label;
}

- (UIView *)headerViewForWidth:(CGFloat)width {
    CGFloat totalWidth = MAX(width, 320.0);
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, totalWidth, 374.0)];

    UIImageView *coverView = [[UIImageView alloc] initWithFrame:CGRectMake((totalWidth - 212.0) * 0.5, 16.0, 212.0, 212.0)];
    coverView.layer.cornerRadius = 16.0;
    coverView.layer.masksToBounds = YES;
    coverView.contentMode = UIViewContentModeScaleAspectFill;
    self.coverView = coverView;

    UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(14.0, 236.0, totalWidth - 28.0, 32.0)];
    nameLabel.textAlignment = NSTextAlignmentCenter;
    nameLabel.font = SonoraHeadlineFont(28.0);
    nameLabel.textColor = UIColor.labelColor;
    self.nameLabel = nameLabel;

    CGFloat playSize = 66.0;
    CGFloat sideControlSize = 46.0;
    CGFloat shuffleSize = 46.0;
    CGFloat controlsY = 272.0;

    UIButton *playButton = [UIButton buttonWithType:UIButtonTypeSystem];
    playButton.frame = CGRectMake((totalWidth - playSize) * 0.5, controlsY, playSize, playSize);
    playButton.backgroundColor = SonoraAccentYellowColor();
    playButton.tintColor = UIColor.whiteColor;
    playButton.layer.cornerRadius = playSize * 0.5;
    playButton.layer.masksToBounds = YES;
    UIImageSymbolConfiguration *playConfig = [UIImageSymbolConfiguration configurationWithPointSize:29.0
                                                                                               weight:UIImageSymbolWeightSemibold];
    [playButton setImage:[UIImage systemImageNamed:@"play.fill" withConfiguration:playConfig] forState:UIControlStateNormal];
    [playButton addTarget:self action:@selector(playTapped) forControlEvents:UIControlEventTouchUpInside];
    self.playButton = playButton;

    UIButton *sleepButton = [UIButton buttonWithType:UIButtonTypeSystem];
    sleepButton.frame = CGRectMake(CGRectGetMinX(playButton.frame) - 16.0 - sideControlSize,
                                   controlsY + (playSize - sideControlSize) * 0.5,
                                   sideControlSize,
                                   sideControlSize);
    UIImageSymbolConfiguration *sleepConfig = [UIImageSymbolConfiguration configurationWithPointSize:22.0
                                                                                               weight:UIImageSymbolWeightSemibold];
    [sleepButton setImage:[UIImage systemImageNamed:@"moon.zzz" withConfiguration:sleepConfig] forState:UIControlStateNormal];
    sleepButton.tintColor = SonoraPlayerPrimaryColor();
    sleepButton.backgroundColor = UIColor.clearColor;
    [sleepButton addTarget:self action:@selector(sleepTimerTapped) forControlEvents:UIControlEventTouchUpInside];
    self.sleepButton = sleepButton;

    UIButton *shuffleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    shuffleButton.frame = CGRectMake(CGRectGetMaxX(playButton.frame) + 16.0,
                                     controlsY + (playSize - shuffleSize) * 0.5,
                                     shuffleSize,
                                     shuffleSize);
    UIImageSymbolConfiguration *shuffleConfig = [UIImageSymbolConfiguration configurationWithPointSize:22.0
                                                                                                 weight:UIImageSymbolWeightSemibold];
    [shuffleButton setImage:[UIImage systemImageNamed:@"shuffle" withConfiguration:shuffleConfig] forState:UIControlStateNormal];
    shuffleButton.tintColor = SonoraPlayerPrimaryColor();
    shuffleButton.backgroundColor = UIColor.clearColor;
    [shuffleButton addTarget:self action:@selector(shuffleTapped) forControlEvents:UIControlEventTouchUpInside];
    self.shuffleButton = shuffleButton;

    [header addSubview:coverView];
    [header addSubview:nameLabel];
    [header addSubview:sleepButton];
    [header addSubview:playButton];
    [header addSubview:shuffleButton];

    return header;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat width = self.view.bounds.size.width;
    if (fabs(self.tableView.tableHeaderView.bounds.size.width - width) > 1.0) {
        self.tableView.tableHeaderView = [self headerViewForWidth:width];
        [self updateHeader];
        [self updatePlayButtonState];
        [self updateSleepButton];
    }
    [self updateNavigationTitleVisibility];
}

- (BOOL)isLovelyPlaylist {
    if (self.playlist == nil) {
        return NO;
    }

    NSString *lovelyID = [NSUserDefaults.standardUserDefaults stringForKey:SonoraLovelyPlaylistDefaultsKey];
    if (lovelyID.length > 0 && [self.playlist.playlistID isEqualToString:lovelyID]) {
        return YES;
    }
    return ([self.playlist.name localizedCaseInsensitiveCompare:@"Lovely songs"] == NSOrderedSame);
}

- (void)updateOptionsButtonVisibility {
    if (self.multiSelectMode) {
        return;
    }
    if (self.playlist == nil || ([self isLovelyPlaylist] && ![self isSharedPlaylistMode])) {
        self.navigationItem.rightBarButtonItem = nil;
        return;
    }
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:18.0
                                                                                          weight:UIImageSymbolWeightBold];
    UIImage *optionsImage = [UIImage systemImageNamed:@"ellipsis" withConfiguration:config];
    if (optionsImage == nil) {
        optionsImage = [UIImage imageNamed:@"tab_ellipsis"];
    }
    if (optionsImage != nil) {
        UIBarButtonItem *optionsItem = [[UIBarButtonItem alloc] initWithImage:optionsImage
                                                                         style:UIBarButtonItemStylePlain
                                                                        target:self
                                                                        action:@selector(optionsTapped)];
        SonoraConfigureNavigationIconBarButtonItem(optionsItem, @"Playlist Options");
        self.navigationItem.rightBarButtonItem = optionsItem;
    } else {
        UIBarButtonItem *optionsItem = [[UIBarButtonItem alloc] initWithTitle:@"..."
                                                                         style:UIBarButtonItemStylePlain
                                                                        target:self
                                                                        action:@selector(optionsTapped)];
        SonoraConfigureNavigationIconBarButtonItem(optionsItem, @"Playlist Options");
        self.navigationItem.rightBarButtonItem = optionsItem;
    }
}

- (void)reloadData {
    if ([self isSharedPlaylistMode]) {
        SonoraSharedPlaylistSnapshot *snapshot = [self resolvedSharedSnapshot];
        if (snapshot == nil) {
            [self.navigationController popViewControllerAnimated:YES];
            return;
        }
        self.sharedSnapshot = snapshot;
        SonoraPlaylist *pseudo = [[SonoraPlaylist alloc] init];
        pseudo.playlistID = snapshot.playlistID;
        pseudo.name = snapshot.name;
        NSMutableArray<NSString *> *trackIDs = [NSMutableArray arrayWithCapacity:snapshot.tracks.count];
        [snapshot.tracks enumerateObjectsUsingBlock:^(SonoraTrack * _Nonnull track, NSUInteger idx, __unused BOOL * _Nonnull stop) {
            [trackIDs addObject:(track.identifier.length > 0 ? track.identifier : [NSString stringWithFormat:@"%@:%lu", snapshot.playlistID, (unsigned long)idx])];
        }];
        pseudo.trackIDs = [trackIDs copy];
        self.playlist = pseudo;
        self.tracks = snapshot.tracks ?: @[];
    } else {
        [SonoraPlaylistStore.sharedStore reloadPlaylists];

        self.playlist = [SonoraPlaylistStore.sharedStore playlistWithID:self.playlistID];
        if (self.playlist == nil) {
            [self.navigationController popViewControllerAnimated:YES];
            return;
        }

        if (SonoraLibraryManager.sharedManager.tracks.count == 0 && self.playlist.trackIDs.count > 0) {
            [SonoraLibraryManager.sharedManager reloadTracks];
        }
        self.tracks = [SonoraPlaylistStore.sharedStore tracksForPlaylist:self.playlist library:SonoraLibraryManager.sharedManager];
    }

    [self updateOptionsButtonVisibility];
    [self updateHeader];
    [self updatePlayButtonState];
    [self updateSleepButton];
    [self updateNavigationTitleVisibility];
    [self refreshNavigationItemsForPlaylistSelectionState];
    [self applySearchFilterAndReload];
}

- (void)updateHeader {
    if (self.playlist == nil) {
        return;
    }

    self.nameLabel.text = self.playlist.name;
    UIImage *cover = nil;
    if ([self isSharedPlaylistMode]) {
        SonoraSharedPlaylistSnapshot *snapshot = [self resolvedSharedSnapshot];
        [self loadSharedCoverIfNeeded];
        cover = snapshot.coverImage ?: snapshot.tracks.firstObject.artwork;
    } else {
        cover = [SonoraPlaylistStore.sharedStore coverForPlaylist:self.playlist
                                                         library:SonoraLibraryManager.sharedManager
                                                            size:CGSizeMake(240.0, 240.0)];
    }
    self.coverView.image = cover;

    if (self.playButton != nil) {
        NSString *lovelyID = [NSUserDefaults.standardUserDefaults stringForKey:SonoraLovelyPlaylistDefaultsKey];
        BOOL isLovely = ((lovelyID.length > 0 && [self.playlist.playlistID isEqualToString:lovelyID]) ||
                         [self.playlist.name localizedCaseInsensitiveCompare:@"Lovely songs"] == NSOrderedSame);
        UIColor *targetColor = nil;
        if (isLovely) {
            targetColor = SonoraLovelyAccentRedColor();
        } else {
            UIImage *accentSource = cover;
            if (accentSource == nil || accentSource.CGImage == nil) {
                for (SonoraTrack *track in self.tracks) {
                    if (track.artwork != nil) {
                        accentSource = track.artwork;
                        break;
                    }
                }
            }

            targetColor = [SonoraArtworkAccentColorService dominantAccentColorForImage:accentSource
                                                                           fallback:SonoraAccentYellowColor()];
        }
        if (targetColor == nil) {
            targetColor = SonoraAccentYellowColor();
        }

        UIColor *currentColor = self.playButton.backgroundColor;
        if (currentColor == nil || !CGColorEqualToColor(currentColor.CGColor, targetColor.CGColor)) {
            [UIView animateWithDuration:0.22
                                  delay:0.0
                                options:(UIViewAnimationOptionAllowUserInteraction |
                                         UIViewAnimationOptionBeginFromCurrentState)
                             animations:^{
                self.playButton.backgroundColor = targetColor;
            }
                             completion:nil];
        }
    }

    [self updatePlayButtonState];
}

- (BOOL)isCurrentQueueMatchingPlaylist {
    if (self.tracks.count == 0) {
        return NO;
    }

    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    return SonoraTrackQueuesMatchByIdentifier(playback.currentQueue, self.tracks);
}

- (void)updatePlayButtonState {
    if (self.playButton == nil) {
        return;
    }

    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    BOOL isPlaylistPlaying = [self isCurrentQueueMatchingPlaylist] &&
    playback.isPlaying &&
    (playback.currentTrack != nil);
    NSString *symbol = isPlaylistPlaying ? @"pause.fill" : @"play.fill";
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:29.0
                                                                                          weight:UIImageSymbolWeightSemibold];
    [self.playButton setImage:[UIImage systemImageNamed:symbol withConfiguration:config] forState:UIControlStateNormal];
    self.playButton.accessibilityLabel = isPlaylistPlaying ? @"Pause playlist" : @"Play playlist";
}

- (void)updateNavigationTitleVisibility {
    if (self.multiSelectMode) {
        self.navigationItem.titleView = nil;
        self.navigationItem.title = nil;
        self.compactTitleVisible = YES;
        return;
    }
    if (self.playlist == nil) {
        self.navigationItem.title = nil;
        self.navigationItem.titleView = nil;
        self.compactTitleVisible = NO;
        return;
    }

    BOOL shouldShowCompact = self.tableView.contentOffset.y > 175.0;
    if (shouldShowCompact == self.compactTitleVisible) {
        return;
    }

    self.compactTitleVisible = shouldShowCompact;
    if (shouldShowCompact) {
        self.navigationItem.titleView = nil;
        self.navigationItem.title = self.playlist.name;
    } else {
        self.navigationItem.title = nil;
        self.navigationItem.titleView = nil;
    }
}

- (void)openPlayer {
    SonoraPlayerViewController *player = [[SonoraPlayerViewController alloc] init];
    player.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:player animated:YES];
}

- (void)playTapped {
    if (self.tracks.count == 0) {
        SonoraPresentAlert(self, @"No Tracks", @"This playlist has no available tracks.");
        return;
    }

    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    if ([self isCurrentQueueMatchingPlaylist] && playback.currentTrack != nil) {
        [playback togglePlayPause];
        [self updatePlayButtonState];
        [self.tableView reloadData];
        return;
    }

    NSArray<SonoraTrack *> *queue = self.tracks;
    [self openPlayer];
    dispatch_async(dispatch_get_main_queue(), ^{
        [playback setShuffleEnabled:NO];
        [playback playTracks:queue startIndex:0];
        [self updatePlayButtonState];
        [self.tableView reloadData];
    });
}

- (void)shuffleTapped {
    if (self.tracks.count == 0) {
        SonoraPresentAlert(self, @"No Tracks", @"This playlist has no available tracks.");
        return;
    }

    NSInteger randomStart = (NSInteger)arc4random_uniform((u_int32_t)self.tracks.count);
    NSArray<SonoraTrack *> *queue = self.tracks;
    [self openPlayer];
    dispatch_async(dispatch_get_main_queue(), ^{
        [SonoraPlaybackManager.sharedManager playTracks:queue startIndex:randomStart];
        [SonoraPlaybackManager.sharedManager setShuffleEnabled:YES];
        [self updatePlayButtonState];
        [self.tableView reloadData];
    });
}

- (void)sleepTimerTapped {
    __weak typeof(self) weakSelf = self;
    SonoraPresentSleepTimerActionSheet(self, self.sleepButton, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf updateSleepButton];
    });
}

- (void)updateSleepButton {
    if (self.sleepButton == nil) {
        return;
    }

    SonoraSleepTimerManager *sleepTimer = SonoraSleepTimerManager.sharedManager;
    BOOL isActive = sleepTimer.isActive;
    NSString *symbol = isActive ? @"moon.zzz.fill" : @"moon.zzz";
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:22.0
                                                                                          weight:UIImageSymbolWeightSemibold];
    [self.sleepButton setImage:[UIImage systemImageNamed:symbol withConfiguration:config] forState:UIControlStateNormal];
    UIColor *inactiveColor = [UIColor labelColor];
    self.sleepButton.tintColor = isActive ? SonoraAccentYellowColor() : inactiveColor;
    if (self.shuffleButton != nil) {
        self.shuffleButton.tintColor = inactiveColor;
    }
    self.sleepButton.accessibilityLabel = isActive
    ? [NSString stringWithFormat:@"Sleep timer active, %@ remaining", SonoraSleepTimerRemainingString(sleepTimer.remainingTime)]
    : @"Sleep timer";
}

- (void)optionsTapped {
    if (self.playlist == nil) {
        return;
    }
    if ([self isLovelyPlaylist] && ![self isSharedPlaylistMode]) {
        return;
    }

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:self.playlist.name
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    if ([self isSharedPlaylistMode]) {
        SonoraSharedPlaylistSnapshot *snapshot = [self resolvedSharedSnapshot];
        BOOL liked = [SonoraSharedPlaylistStore.sharedStore isSnapshotLikedForPlaylistID:snapshot.playlistID];
        [sheet addAction:[UIAlertAction actionWithTitle:(liked ? @"Remove from Collections" : @"Add to Collections")
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction * _Nonnull action) {
            [self toggleSharedPlaylistLikeTapped];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Import to Library"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction * _Nonnull action) {
            [self addSharedPlaylistLocallyTapped];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Share Link"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction * _Nonnull action) {
            [self shareCurrentPlaylistLinkTapped];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                  style:UIAlertActionStyleCancel
                                                handler:nil]];

        UIPopoverPresentationController *popover = sheet.popoverPresentationController;
        if (popover != nil) {
            popover.barButtonItem = self.navigationItem.rightBarButtonItem;
        }

        [self presentViewController:sheet animated:YES completion:nil];
        return;
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Rename Playlist"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction * _Nonnull action) {
        [self renamePlaylistTapped];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Change Cover"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction * _Nonnull action) {
        [self changeCoverTapped];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Add Music"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction * _Nonnull action) {
        [self addMusicTapped];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Share Playlist"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction * _Nonnull action) {
        [self sharePlaylistTapped];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Delete Playlist"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(__unused UIAlertAction * _Nonnull action) {
        [self deletePlaylistTapped];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover != nil) {
        popover.barButtonItem = self.navigationItem.rightBarButtonItem;
    }

    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)renamePlaylistTapped {
    if (self.playlist == nil) {
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Rename Playlist"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"Playlist Name";
        textField.text = self.playlist.name;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction * _Nonnull action) {
        NSString *name = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (name.length == 0) {
            SonoraPresentAlert(self, @"Name Required", @"Enter playlist name.");
            return;
        }

        BOOL renamed = [SonoraPlaylistStore.sharedStore renamePlaylistWithID:self.playlistID newName:name];
        if (!renamed) {
            SonoraPresentAlert(self, @"Error", @"Could not rename playlist.");
            return;
        }

        [self reloadData];
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)changeCoverTapped {
    SonoraPlaylistCoverPickerViewController *coverPicker = [[SonoraPlaylistCoverPickerViewController alloc] initWithPlaylistID:self.playlistID];
    coverPicker.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:coverPicker animated:YES];
}

- (void)addMusicTapped {
    SonoraPlaylistAddTracksViewController *addTracks = [[SonoraPlaylistAddTracksViewController alloc] initWithPlaylistID:self.playlistID];
    addTracks.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:addTracks animated:YES];
}

- (void)deletePlaylistTapped {
    if (self.playlist == nil) {
        return;
    }

    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"Delete Playlist?"
                                                                      message:self.playlist.name
                                                               preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                style:UIAlertActionStyleCancel
                                              handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Delete"
                                                style:UIAlertActionStyleDestructive
                                              handler:^(__unused UIAlertAction * _Nonnull action) {
        BOOL deleted = [SonoraPlaylistStore.sharedStore deletePlaylistWithID:self.playlistID];
        if (!deleted) {
            SonoraPresentAlert(self, @"Error", @"Could not delete playlist.");
            return;
        }
        [self.navigationController popViewControllerAnimated:YES];
    }]];

    [self presentViewController:confirm animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return self.filteredTracks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SonoraTrackCell *cell = [tableView dequeueReusableCellWithIdentifier:@"PlaylistTrackCell" forIndexPath:indexPath];

    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    SonoraTrack *track = self.filteredTracks[indexPath.row];
    [self loadSharedArtworkIfNeededForTrack:track];
    SonoraTrack *currentTrack = playback.currentTrack;
    BOOL isCurrent = (currentTrack != nil && [currentTrack.identifier isEqualToString:track.identifier]);
    BOOL sameQueue = [self isCurrentQueueMatchingPlaylist];
    BOOL showsPlaybackIndicator = (sameQueue && isCurrent && playback.isPlaying);

    [cell configureWithTrack:track isCurrent:isCurrent showsPlaybackIndicator:showsPlaybackIndicator];
    cell.accessoryType = (self.multiSelectMode && [self.selectedTrackIDs containsObject:track.identifier])
    ? UITableViewCellAccessoryCheckmark
    : UITableViewCellAccessoryNone;
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.row >= self.filteredTracks.count) {
        return;
    }

    if (self.multiSelectMode) {
        SonoraTrack *selectionTrack = [self playlistTrackAtIndexPath:indexPath];
        if (selectionTrack != nil) {
            [self togglePlaylistSelectionForTrackID:selectionTrack.identifier forceSelected:NO];
        }
        return;
    }

    SonoraTrack *selectedTrack = self.filteredTracks[indexPath.row];
    SonoraTrack *currentTrack = SonoraPlaybackManager.sharedManager.currentTrack;
    if (currentTrack != nil && [currentTrack.identifier isEqualToString:selectedTrack.identifier]) {
        [self openPlayer];
        return;
    }

    NSArray<SonoraTrack *> *queue = self.filteredTracks;
    NSInteger startIndex = indexPath.row;
    [self openPlayer];
    dispatch_async(dispatch_get_main_queue(), ^{
        [SonoraPlaybackManager.sharedManager setShuffleEnabled:NO];
        [SonoraPlaybackManager.sharedManager playTracks:queue startIndex:startIndex];
    });
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView == self.tableView) {
        [self updateNavigationTitleVisibility];
        [self updateSearchControllerAttachment];
    }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (self.multiSelectMode || [self isSharedPlaylistMode]) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }
    if (indexPath.row >= self.filteredTracks.count) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }

    SonoraTrack *track = self.filteredTracks[indexPath.row];

    UIContextualAction *removeAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                                title:@"Remove"
                                                                              handler:^(__unused UIContextualAction * _Nonnull action,
                                                                                        __unused UIView * _Nonnull sourceView,
                                                                                        void (^ _Nonnull completionHandler)(BOOL)) {
        BOOL removed = [SonoraPlaylistStore.sharedStore removeTrackID:track.identifier fromPlaylistID:self.playlistID];
        if (!removed) {
            SonoraPresentAlert(self, @"Could Not Remove", @"Track could not be removed from playlist.");
            completionHandler(NO);
            return;
        }
        [self reloadData];
        completionHandler(YES);
    }];
    removeAction.image = [UIImage systemImageNamed:@"trash.fill"];

    UIContextualAction *addAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                            title:@"Add"
                                                                          handler:^(__unused UIContextualAction * _Nonnull action,
                                                                                    __unused UIView * _Nonnull sourceView,
                                                                                    void (^ _Nonnull completionHandler)(BOOL)) {
        SonoraPresentQuickAddTrackToPlaylist(self, track.identifier, nil);
        completionHandler(YES);
    }];
    addAction.image = [UIImage systemImageNamed:@"text.badge.plus"];
    addAction.backgroundColor = [UIColor colorWithRed:0.16 green:0.47 blue:0.95 alpha:1.0];

    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[removeAction, addAction]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (self.multiSelectMode || [self isSharedPlaylistMode]) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }
    if (indexPath.row >= self.filteredTracks.count) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }

    SonoraTrack *track = self.filteredTracks[indexPath.row];
    BOOL isFavorite = [SonoraFavoritesStore.sharedStore isTrackFavoriteByID:track.identifier];
    NSString *iconName = isFavorite ? @"heart.slash.fill" : @"heart.fill";

    UIContextualAction *favoriteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                                  title:nil
                                                                                handler:^(__unused UIContextualAction * _Nonnull action,
                                                                                          __unused UIView * _Nonnull sourceView,
                                                                                          void (^ _Nonnull completionHandler)(BOOL)) {
        [SonoraFavoritesStore.sharedStore setTrackID:track.identifier favorite:!isFavorite];
        completionHandler(YES);
    }];
    favoriteAction.image = [UIImage systemImageNamed:iconName];
    favoriteAction.backgroundColor = isFavorite
    ? [UIColor colorWithWhite:0.40 alpha:1.0]
    : [UIColor colorWithRed:1.0 green:0.35 blue:0.42 alpha:1.0];

    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[favoriteAction]];
    configuration.performsFirstActionWithFullSwipe = YES;
    return configuration;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.searchQuery = searchController.searchBar.text ?: @"";
    [self applySearchFilterAndReload];
}

@end
