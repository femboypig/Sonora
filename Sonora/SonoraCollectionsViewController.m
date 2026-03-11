//
//  SonoraCollectionsViewController.m
//  Sonora
//

#import "SonoraCollectionsViewController.h"

#import <objc/message.h>

#import "SonoraServices.h"

static NSString * const SonoraCollectionsPlaylistCellReuseID = @"SonoraCollectionsPlaylistCell";
static NSString * const SonoraCollectionsMyMusicCellReuseID = @"SonoraCollectionsMyMusicCell";
static NSString * const SonoraCollectionsFavoritesSummaryCellReuseID = @"SonoraCollectionsFavoritesSummaryCell";
static NSString * const SonoraCollectionsFavoriteTrackCellReuseID = @"SonoraCollectionsFavoriteTrackCell";
static NSString * const SonoraCollectionsHeaderReuseID = @"SonoraCollectionsHeader";
static NSString * const SonoraCollectionsHeaderKind = @"SonoraCollectionsHeaderKind";
static NSString * const SonoraCollectionsCacheOnlinePlaylistTracksKey = @"sonora.settings.cacheOnlinePlaylistTracks";

typedef NS_ENUM(NSInteger, SonoraCollectionsSection) {
    SonoraCollectionsSectionFavoritesSummary = 0,
    SonoraCollectionsSectionFavoritesTracks = 1,
    SonoraCollectionsSectionPlaylists = 2,
    SonoraCollectionsSectionLastAdded = 3,
    SonoraCollectionsSectionAlbums = 4,
    SonoraCollectionsSectionMyMusic = 5,
};

static id SonoraCollectionsSharedPlaylistStore(void) {
    Class storeClass = NSClassFromString(@"SonoraSharedPlaylistStore");
    if (storeClass == Nil) {
        return nil;
    }
    return [storeClass performSelector:@selector(sharedStore)];
}

static NSArray<SonoraPlaylist *> *SonoraCollectionsLikedSharedPlaylists(void) {
    id store = SonoraCollectionsSharedPlaylistStore();
    if (![store respondsToSelector:@selector(likedPlaylists)]) {
        return @[];
    }
    id playlists = [store performSelector:@selector(likedPlaylists)];
    return [playlists isKindOfClass:NSArray.class] ? playlists : @[];
}

static id SonoraCollectionsSharedSnapshotForPlaylistID(NSString *playlistID) {
    id store = SonoraCollectionsSharedPlaylistStore();
    if (playlistID.length == 0 || ![store respondsToSelector:@selector(snapshotForPlaylistID:)]) {
        return nil;
    }
    return [store performSelector:@selector(snapshotForPlaylistID:) withObject:playlistID];
}

static NSString *SonoraCollectionsSharedPlaylistSubtitle(id sharedSnapshot) {
    NSArray<SonoraTrack *> *tracks = [sharedSnapshot valueForKey:@"tracks"];
    NSUInteger totalTracks = [tracks isKindOfClass:NSArray.class] ? tracks.count : 0;
    if (![NSUserDefaults.standardUserDefaults boolForKey:SonoraCollectionsCacheOnlinePlaylistTracksKey]) {
        return @"Online playlist • Streaming";
    }
    NSUInteger cachedTracks = 0;
    for (SonoraTrack *track in tracks) {
        if (track.url.isFileURL && track.url.path.length > 0 &&
            [NSFileManager.defaultManager fileExistsAtPath:track.url.path]) {
            cachedTracks += 1;
        }
    }
    if (totalTracks == 0) {
        return @"Online playlist";
    }
    if (cachedTracks >= totalTracks) {
        return @"Online playlist • Cached";
    }
    return [NSString stringWithFormat:@"Online playlist • Cached %lu/%lu",
            (unsigned long)cachedTracks,
            (unsigned long)totalTracks];
}

static UIFont *SonoraCollectionsYSMusicFont(CGFloat size) {
    UIFont *font = [UIFont fontWithName:@"YSMusic-HeadlineBold" size:size];
    if (font != nil) {
        return font;
    }
    return [UIFont boldSystemFontOfSize:size];
}

static UIView *SonoraCollectionsNavigationTitleView(NSString *text) {
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = text;
    titleLabel.textColor = UIColor.labelColor;
    titleLabel.font = SonoraCollectionsYSMusicFont(30.0);
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

static UIViewController * _Nullable SonoraInstantiatePlaylistDetailViewController(NSString *playlistID) {
    Class detailClass = NSClassFromString(@"SonoraPlaylistDetailViewController");
    if (detailClass == Nil || ![detailClass isSubclassOfClass:UIViewController.class]) {
        return nil;
    }

    SEL initializer = NSSelectorFromString(@"initWithPlaylistID:");
    id instance = [detailClass alloc];
    if (instance == nil || ![instance respondsToSelector:initializer]) {
        return nil;
    }

    id (*messageSend)(id, SEL, id) = (void *)objc_msgSend;
    id controller = messageSend(instance, initializer, playlistID);
    if (![controller isKindOfClass:UIViewController.class]) {
        return nil;
    }
    return (UIViewController *)controller;
}

static UIViewController * _Nullable SonoraInstantiateFavoritesViewController(void) {
    Class favoritesClass = NSClassFromString(@"SonoraFavoritesViewController");
    if (favoritesClass == Nil || ![favoritesClass isSubclassOfClass:UIViewController.class]) {
        return nil;
    }
    return [[favoritesClass alloc] init];
}

static UIViewController * _Nullable SonoraInstantiatePlayerFromCollections(void) {
    Class playerClass = NSClassFromString(@"SonoraPlayerViewController");
    if (playerClass == Nil || ![playerClass isSubclassOfClass:UIViewController.class]) {
        return nil;
    }
    return [[playerClass alloc] init];
}

static UIViewController * _Nullable SonoraInstantiatePlaylistNameViewController(void) {
    Class nameClass = NSClassFromString(@"SonoraPlaylistNameViewController");
    if (nameClass == Nil || ![nameClass isSubclassOfClass:UIViewController.class]) {
        return nil;
    }
    return [[nameClass alloc] init];
}

static UIViewController * _Nullable SonoraInstantiatePlaylistsViewController(void) {
    Class playlistsClass = NSClassFromString(@"SonoraPlaylistsViewController");
    if (playlistsClass == Nil || ![playlistsClass isSubclassOfClass:UIViewController.class]) {
        return nil;
    }
    return [[playlistsClass alloc] init];
}

static NSString *SonoraCollectionsTrackTitle(SonoraTrack *track) {
    if (track.title.length > 0) {
        return track.title;
    }
    if (track.fileName.length > 0) {
        return track.fileName.stringByDeletingPathExtension;
    }
    return @"Unknown track";
}

static NSString *SonoraCollectionsTrackArtist(SonoraTrack *track) {
    if (track.artist.length > 0) {
        return track.artist;
    }
    return @"";
}

static NSDate *SonoraCollectionsTrackModifiedDate(SonoraTrack *track) {
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

static NSString *SonoraCollectionsNormalizedArtistText(NSString *artist) {
    NSString *value = [artist stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return value.lowercaseString ?: @"";
}

static NSArray<NSString *> *SonoraCollectionsArtistParticipants(NSString *artistText) {
    NSString *trimmed = [artistText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        return @[];
    }

    NSMutableArray<NSString *> *result = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSArray<NSString *> *chunks = [trimmed componentsSeparatedByString:@","];
    for (NSString *chunk in chunks) {
        NSString *value = [chunk stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *key = SonoraCollectionsNormalizedArtistText(value);
        if (key.length == 0 || [seen containsObject:key]) {
            continue;
        }
        [seen addObject:key];
        [result addObject:value];
    }
    return result;
}

@interface SonoraCollectionsAlbumItem : NSObject

@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) UIImage *artwork;
@property (nonatomic, strong) NSDate *latestDate;
@property (nonatomic, assign) NSInteger trackCount;
@property (nonatomic, copy) NSArray<SonoraTrack *> *tracks;

@end

@implementation SonoraCollectionsAlbumItem
@end

@interface SonoraCollectionsPlaylistCardCell : UICollectionViewCell

- (void)configureWithPlaylist:(SonoraPlaylist *)playlist cover:(UIImage *)cover;
- (void)configureWithTitle:(NSString *)title subtitle:(NSString *)subtitle cover:(UIImage *)cover;
- (void)configureAsCreatePlaylistCard;

@end

@interface SonoraCollectionsPlaylistCardCell ()

@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;

@end

@implementation SonoraCollectionsPlaylistCardCell

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
    titleLabel.textColor = UIColor.labelColor;
    titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
    titleLabel.numberOfLines = 1;
    self.titleLabel = titleLabel;

    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLabel.textColor = UIColor.secondaryLabelColor;
    subtitleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular];
    subtitleLabel.numberOfLines = 1;
    self.subtitleLabel = subtitleLabel;

    [self.contentView addSubview:coverView];
    [self.contentView addSubview:titleLabel];
    [self.contentView addSubview:subtitleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [coverView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8.0],
        [coverView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:8.0],
        [coverView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8.0],
        [coverView.heightAnchor constraintEqualToAnchor:coverView.widthAnchor],

        [titleLabel.topAnchor constraintEqualToAnchor:coverView.bottomAnchor constant:10.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:10.0],
        [titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10.0],

        [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:3.0],
        [subtitleLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [subtitleLabel.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
        [subtitleLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-10.0]
    ]];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.coverView.image = nil;
    self.coverView.tintColor = nil;
    self.coverView.backgroundColor = UIColor.clearColor;
    self.coverView.contentMode = UIViewContentModeScaleAspectFill;
    self.titleLabel.text = nil;
    self.subtitleLabel.text = nil;
    self.subtitleLabel.hidden = NO;
}

- (void)configureWithPlaylist:(SonoraPlaylist *)playlist cover:(UIImage *)cover {
    self.coverView.contentMode = UIViewContentModeScaleAspectFill;
    self.coverView.tintColor = nil;
    self.coverView.backgroundColor = UIColor.clearColor;
    self.coverView.image = cover;
    self.titleLabel.text = playlist.name;
    self.subtitleLabel.text = [NSString stringWithFormat:@"%ld tracks", (long)playlist.trackIDs.count];
    self.subtitleLabel.hidden = NO;
}

- (void)configureWithTitle:(NSString *)title subtitle:(NSString *)subtitle cover:(UIImage *)cover {
    self.coverView.contentMode = UIViewContentModeScaleAspectFill;
    self.coverView.tintColor = nil;
    self.coverView.backgroundColor = UIColor.clearColor;
    self.coverView.image = cover;
    self.titleLabel.text = title ?: @"";
    self.subtitleLabel.text = subtitle ?: @"";
    self.subtitleLabel.hidden = (subtitle.length == 0);
}

- (void)configureAsCreatePlaylistCard {
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:56.0
                                                                                          weight:UIImageSymbolWeightRegular];
    UIImage *plus = [[UIImage systemImageNamed:@"plus" withConfiguration:config] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    self.coverView.image = plus;
    self.coverView.contentMode = UIViewContentModeCenter;
    self.coverView.tintColor = UIColor.secondaryLabelColor;
    self.coverView.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
        if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return [UIColor colorWithWhite:1.0 alpha:0.06];
        }
        return [UIColor colorWithWhite:0.0 alpha:0.04];
    }];
    self.titleLabel.text = @"New playlist";
    self.subtitleLabel.text = nil;
    self.subtitleLabel.hidden = YES;
}

@end

@interface SonoraCollectionsMyMusicCell : UICollectionViewCell
@end

@interface SonoraCollectionsMyMusicCell ()

@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIImageView *arrowView;

@end

@implementation SonoraCollectionsMyMusicCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.contentView.backgroundColor = UIColor.clearColor;

    UIView *containerView = [[UIView alloc] init];
    containerView.translatesAutoresizingMaskIntoConstraints = NO;
    containerView.layer.cornerRadius = 14.0;
    containerView.layer.masksToBounds = YES;
    containerView.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
        if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return [UIColor colorWithWhite:1.0 alpha:0.08];
        }
        return [UIColor colorWithWhite:0.0 alpha:0.05];
    }];

    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass"]];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.tintColor = UIColor.labelColor;
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconView = iconView;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = SonoraCollectionsYSMusicFont(24.0);
    titleLabel.textColor = UIColor.labelColor;
    titleLabel.text = @"My music";
    self.titleLabel = titleLabel;

    UIImageView *arrowView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
    arrowView.translatesAutoresizingMaskIntoConstraints = NO;
    arrowView.tintColor = UIColor.secondaryLabelColor;
    arrowView.contentMode = UIViewContentModeScaleAspectFit;
    self.arrowView = arrowView;

    [self.contentView addSubview:containerView];
    [containerView addSubview:iconView];
    [containerView addSubview:titleLabel];
    [containerView addSubview:arrowView];

    [NSLayoutConstraint activateConstraints:@[
        [containerView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
        [containerView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [containerView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [containerView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],

        [iconView.leadingAnchor constraintEqualToAnchor:containerView.leadingAnchor constant:12.0],
        [iconView.centerYAnchor constraintEqualToAnchor:containerView.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:15.0],
        [iconView.heightAnchor constraintEqualToConstant:15.0],

        [titleLabel.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:9.0],
        [titleLabel.centerYAnchor constraintEqualToAnchor:containerView.centerYAnchor],

        [arrowView.leadingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor constant:8.0],
        [arrowView.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],
        [arrowView.widthAnchor constraintEqualToConstant:14.0],
        [arrowView.heightAnchor constraintEqualToConstant:14.0],
        [arrowView.trailingAnchor constraintLessThanOrEqualToAnchor:containerView.trailingAnchor constant:-10.0]
    ]];
}

@end

@interface SonoraCollectionsFavoritesSummaryCell : UICollectionViewCell

- (void)configureWithTracksCount:(NSInteger)tracksCount;

@end

@interface SonoraCollectionsFavoritesSummaryCell ()

@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIImageView *arrowView;
@property (nonatomic, strong) UILabel *subtitleLabel;

@end

@implementation SonoraCollectionsFavoritesSummaryCell

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
    titleLabel.font = SonoraCollectionsYSMusicFont(20.0);
    titleLabel.textColor = UIColor.labelColor;
    titleLabel.numberOfLines = 1;
    titleLabel.text = @"My Favorites";
    self.titleLabel = titleLabel;

    UIImageView *arrowView = [[UIImageView alloc] init];
    arrowView.translatesAutoresizingMaskIntoConstraints = NO;
    arrowView.image = [UIImage systemImageNamed:@"chevron.right"];
    arrowView.tintColor = UIColor.secondaryLabelColor;
    arrowView.contentMode = UIViewContentModeScaleAspectFit;
    self.arrowView = arrowView;

    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
    subtitleLabel.textColor = UIColor.secondaryLabelColor;
    subtitleLabel.numberOfLines = 1;
    self.subtitleLabel = subtitleLabel;

    [self.contentView addSubview:coverView];
    [self.contentView addSubview:titleLabel];
    [self.contentView addSubview:arrowView];
    [self.contentView addSubview:subtitleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [coverView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:8.0],
        [coverView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [coverView.widthAnchor constraintEqualToConstant:66.0],
        [coverView.heightAnchor constraintEqualToConstant:66.0],

        [titleLabel.leadingAnchor constraintEqualToAnchor:coverView.trailingAnchor constant:13.0],
        [titleLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor constant:-8.0],

        [arrowView.leadingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor constant:7.0],
        [arrowView.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],
        [arrowView.widthAnchor constraintEqualToConstant:14.0],
        [arrowView.heightAnchor constraintEqualToConstant:14.0],
        [arrowView.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-10.0],

        [subtitleLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:2.0],
        [subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-10.0]
    ]];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.coverView.image = nil;
    self.subtitleLabel.text = nil;
}

- (void)configureWithTracksCount:(NSInteger)tracksCount {
    UIImage *cover = [UIImage imageNamed:@"LovelyCover"];
    if (cover == nil) {
        cover = [UIImage systemImageNamed:@"heart.fill"];
    }
    self.coverView.image = cover;
    self.coverView.layer.cornerRadius = 14.0;
    NSString *trackWord = (tracksCount == 1) ? @"track" : @"tracks";
    self.subtitleLabel.text = [NSString stringWithFormat:@"%ld %@", (long)tracksCount, trackWord];
}

@end

@interface SonoraCollectionsFavoriteTrackCell : UICollectionViewCell

- (void)configureWithTrack:(SonoraTrack *)track;
- (void)configureWithTrack:(SonoraTrack *)track accented:(BOOL)accented;

@end

@interface SonoraCollectionsFavoriteTrackCell ()

@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *artistLabel;

@end

@implementation SonoraCollectionsFavoriteTrackCell

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
    [self configureWithTrack:track accented:NO];
}

- (void)configureWithTrack:(SonoraTrack *)track accented:(BOOL)accented {
    if (accented) {
        UIColor *base = [SonoraArtworkAccentColorService dominantAccentColorForImage:track.artwork
                                                                         fallback:UIColor.clearColor];
        CGFloat alpha = (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) ? 0.20 : 0.12;
        self.contentView.backgroundColor = [base colorWithAlphaComponent:alpha];
    } else {
        self.contentView.backgroundColor = UIColor.clearColor;
    }
    self.coverView.image = track.artwork;
    self.titleLabel.text = SonoraCollectionsTrackTitle(track);
    NSString *artist = SonoraCollectionsTrackArtist(track);
    self.artistLabel.text = artist;
    self.artistLabel.hidden = (artist.length == 0);
}

@end

@interface SonoraCollectionsSectionHeaderView : UICollectionReusableView

- (void)configureWithTitle:(NSString *)title showsArrow:(BOOL)showsArrow;
@property (nonatomic, copy, nullable) dispatch_block_t tapHandler;

@end

@interface SonoraCollectionsSectionHeaderView ()

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIImageView *arrowView;

@end

@implementation SonoraCollectionsSectionHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.userInteractionEnabled = YES;

    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.textColor = UIColor.labelColor;
    label.font = SonoraCollectionsYSMusicFont(24.0);
    self.titleLabel = label;

    UIImageView *arrowView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
    arrowView.translatesAutoresizingMaskIntoConstraints = NO;
    arrowView.tintColor = UIColor.secondaryLabelColor;
    arrowView.contentMode = UIViewContentModeScaleAspectFit;
    self.arrowView = arrowView;

    [self addSubview:label];
    [self addSubview:arrowView];

    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:0.0],
        [label.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-2.0],

        [arrowView.leadingAnchor constraintEqualToAnchor:label.trailingAnchor constant:8.0],
        [arrowView.centerYAnchor constraintEqualToAnchor:label.centerYAnchor],
        [arrowView.widthAnchor constraintEqualToConstant:14.0],
        [arrowView.heightAnchor constraintEqualToConstant:14.0]
    ]];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
    [self addGestureRecognizer:tap];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.tapHandler = nil;
}

- (void)handleTap {
    if (self.tapHandler != nil) {
        self.tapHandler();
    }
}

- (void)configureWithTitle:(NSString *)title showsArrow:(BOOL)showsArrow {
    self.titleLabel.text = title;
    self.arrowView.hidden = !showsArrow;
    self.userInteractionEnabled = showsArrow;
}

@end

@interface SonoraCollectionsViewController () <UICollectionViewDataSource, UICollectionViewDelegate>

@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, copy) NSArray<SonoraPlaylist *> *playlists;
@property (nonatomic, copy) NSArray<SonoraTrack *> *favoriteTracks;
@property (nonatomic, copy) NSArray<SonoraTrack *> *allTracks;
@property (nonatomic, copy) NSArray<SonoraTrack *> *lastAddedTracks;
@property (nonatomic, copy) NSArray<SonoraCollectionsAlbumItem *> *albumItems;
@property (nonatomic, copy) NSArray<SonoraTrack *> *myMusicTracks;

@end

@implementation SonoraCollectionsViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupNavigationBar];
    [self setupCollectionView];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(reloadCollections)
                                               name:SonoraPlaylistsDidChangeNotification
                                             object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                            selector:@selector(reloadCollections)
                                                name:SonoraFavoritesDidChangeNotification
                                              object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                            selector:@selector(reloadCollections)
                                                name:UIApplicationWillEnterForegroundNotification
                                              object:nil];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadCollections];
}

- (void)setupNavigationBar {
    self.title = nil;
    self.navigationItem.title = nil;
    self.navigationItem.titleView = nil;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:SonoraCollectionsNavigationTitleView(@"Collections")];
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

    [collectionView registerClass:SonoraCollectionsPlaylistCardCell.class
       forCellWithReuseIdentifier:SonoraCollectionsPlaylistCellReuseID];
    [collectionView registerClass:SonoraCollectionsFavoritesSummaryCell.class
       forCellWithReuseIdentifier:SonoraCollectionsFavoritesSummaryCellReuseID];
    [collectionView registerClass:SonoraCollectionsFavoriteTrackCell.class
       forCellWithReuseIdentifier:SonoraCollectionsFavoriteTrackCellReuseID];
    [collectionView registerClass:SonoraCollectionsSectionHeaderView.class
       forSupplementaryViewOfKind:SonoraCollectionsHeaderKind
              withReuseIdentifier:SonoraCollectionsHeaderReuseID];

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
    return [[UICollectionViewCompositionalLayout alloc] initWithSectionProvider:^NSCollectionLayoutSection * _Nullable(NSInteger sectionIndex,
                                                                                                                        __unused id<NSCollectionLayoutEnvironment> _Nonnull environment) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return nil;
        }
        switch ((SonoraCollectionsSection)sectionIndex) {
            case SonoraCollectionsSectionMyMusic:
                return [strongSelf myMusicSectionLayout];
            case SonoraCollectionsSectionFavoritesSummary:
                return [strongSelf favoritesSummarySectionLayout];
            case SonoraCollectionsSectionFavoritesTracks:
                return [strongSelf favoritesTracksSectionLayout];
            case SonoraCollectionsSectionPlaylists:
                return [strongSelf playlistsSectionLayout];
            case SonoraCollectionsSectionLastAdded:
                return [strongSelf lastAddedSectionLayout];
            case SonoraCollectionsSectionAlbums:
                return [strongSelf albumsSectionLayout];
        }
        return nil;
    }];
}

- (NSCollectionLayoutBoundarySupplementaryItem *)sectionHeaderItem {
    NSCollectionLayoutSize *headerSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                                                         heightDimension:[NSCollectionLayoutDimension estimatedDimension:36.0]];
    NSCollectionLayoutBoundarySupplementaryItem *header = [NSCollectionLayoutBoundarySupplementaryItem
                                                           boundarySupplementaryItemWithLayoutSize:headerSize
                                                           elementKind:SonoraCollectionsHeaderKind
                                                           alignment:NSRectAlignmentTop];
    header.contentInsets = NSDirectionalEdgeInsetsMake(0.0, 10.0, 0.0, 18.0);
    return header;
}

- (NSCollectionLayoutSection *)myMusicSectionLayout {
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
    section.contentInsets = NSDirectionalEdgeInsetsMake(10.0, 18.0, 12.0, 18.0);
    section.orthogonalScrollingBehavior = UICollectionLayoutSectionOrthogonalScrollingBehaviorContinuousGroupLeadingBoundary;
    section.boundarySupplementaryItems = @[[self sectionHeaderItem]];
    return section;
}

- (NSCollectionLayoutSection *)playlistsSectionLayout {
    NSCollectionLayoutSize *itemSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:196.0]
                                                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:262.0]];
    NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];

    NSCollectionLayoutSize *groupSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:196.0]
                                                                        heightDimension:[NSCollectionLayoutDimension absoluteDimension:262.0]];
    NSCollectionLayoutGroup *group = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize subitems:@[item]];

    NSCollectionLayoutSection *section = [NSCollectionLayoutSection sectionWithGroup:group];
    section.interGroupSpacing = 12.0;
    section.contentInsets = NSDirectionalEdgeInsetsMake(10.0, 18.0, 12.0, 18.0);
    section.orthogonalScrollingBehavior = UICollectionLayoutSectionOrthogonalScrollingBehaviorContinuousGroupLeadingBoundary;
    section.boundarySupplementaryItems = @[[self sectionHeaderItem]];
    return section;
}

- (NSCollectionLayoutSection *)favoritesSummarySectionLayout {
    NSCollectionLayoutSize *itemSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:76.0]];
    NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];

    NSCollectionLayoutSize *groupSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                                                        heightDimension:[NSCollectionLayoutDimension absoluteDimension:76.0]];
    NSCollectionLayoutGroup *group = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize
                                                                                     subitems:@[item]];

    NSCollectionLayoutSection *section = [NSCollectionLayoutSection sectionWithGroup:group];
    section.contentInsets = NSDirectionalEdgeInsetsMake(8.0, 18.0, 6.0, 18.0);
    return section;
}

- (NSCollectionLayoutSection *)favoritesTracksSectionLayout {
    NSCollectionLayoutSize *itemSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:66.0]];
    NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];

    NSCollectionLayoutSize *groupSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:304.0]
                                                                        heightDimension:[NSCollectionLayoutDimension absoluteDimension:66.0]];
    NSCollectionLayoutGroup *group = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize
                                                                                     subitems:@[item]];

    NSCollectionLayoutSection *section = [NSCollectionLayoutSection sectionWithGroup:group];
    section.interGroupSpacing = 12.0;
    section.contentInsets = NSDirectionalEdgeInsetsMake(0.0, 18.0, 10.0, 18.0);
    section.orthogonalScrollingBehavior = UICollectionLayoutSectionOrthogonalScrollingBehaviorContinuousGroupLeadingBoundary;
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
    section.contentInsets = NSDirectionalEdgeInsetsMake(10.0, 18.0, 10.0, 18.0);
    section.orthogonalScrollingBehavior = UICollectionLayoutSectionOrthogonalScrollingBehaviorContinuousGroupLeadingBoundary;
    section.boundarySupplementaryItems = @[[self sectionHeaderItem]];
    return section;
}

- (NSCollectionLayoutSection *)albumsSectionLayout {
    NSCollectionLayoutSize *itemSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:138.0]
                                                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:182.0]];
    NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];

    NSCollectionLayoutSize *groupSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:138.0]
                                                                        heightDimension:[NSCollectionLayoutDimension absoluteDimension:182.0]];
    NSCollectionLayoutGroup *group = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize
                                                                                     subitems:@[item]];

    NSCollectionLayoutSection *section = [NSCollectionLayoutSection sectionWithGroup:group];
    section.interGroupSpacing = 12.0;
    section.contentInsets = NSDirectionalEdgeInsetsMake(10.0, 18.0, 12.0, 18.0);
    section.orthogonalScrollingBehavior = UICollectionLayoutSectionOrthogonalScrollingBehaviorContinuousGroupLeadingBoundary;
    section.boundarySupplementaryItems = @[[self sectionHeaderItem]];
    return section;
}

- (void)reloadCollections {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self reloadCollections];
        });
        return;
    }

    SonoraPlaylistStore *playlistStore = SonoraPlaylistStore.sharedStore;
    [playlistStore reloadPlaylists];
    NSMutableArray<SonoraPlaylist *> *playlists = [(playlistStore.playlists ?: @[]) mutableCopy];
    NSArray<SonoraPlaylist *> *likedSharedPlaylists = SonoraCollectionsLikedSharedPlaylists();
    if (likedSharedPlaylists.count > 0) {
        [playlists addObjectsFromArray:likedSharedPlaylists];
    }
    self.playlists = [playlists copy];

    SonoraLibraryManager *library = SonoraLibraryManager.sharedManager;
    if (library.tracks.count == 0 && SonoraFavoritesStore.sharedStore.favoriteTrackIDs.count > 0) {
        [library reloadTracks];
    }
    self.allTracks = library.tracks ?: @[];
    self.favoriteTracks = [SonoraFavoritesStore.sharedStore favoriteTracksWithLibrary:library] ?: @[];
    self.lastAddedTracks = [self buildLastAddedTracksFromTracks:self.allTracks limit:14];
    self.albumItems = [self buildAlbumItemsFromTracks:self.allTracks limit:14];
    NSArray<SonoraTrack *> *affinityTracks = [SonoraTrackAnalyticsStore.sharedStore tracksSortedByAffinity:self.allTracks] ?: @[];
    if (affinityTracks.count > 14) {
        self.myMusicTracks = [affinityTracks subarrayWithRange:NSMakeRange(0, 14)];
    } else {
        self.myMusicTracks = affinityTracks;
    }

    [self.collectionView reloadData];
    [self updateEmptyState];
}

- (NSArray<SonoraTrack *> *)buildLastAddedTracksFromTracks:(NSArray<SonoraTrack *> *)tracks limit:(NSUInteger)limit {
    if (tracks.count == 0 || limit == 0) {
        return @[];
    }

    NSArray<SonoraTrack *> *sorted = [tracks sortedArrayUsingComparator:^NSComparisonResult(SonoraTrack * _Nonnull left,
                                                                                         SonoraTrack * _Nonnull right) {
        NSTimeInterval leftTime = SonoraCollectionsTrackModifiedDate(left).timeIntervalSince1970;
        NSTimeInterval rightTime = SonoraCollectionsTrackModifiedDate(right).timeIntervalSince1970;
        if (leftTime > rightTime) {
            return NSOrderedAscending;
        }
        if (leftTime < rightTime) {
            return NSOrderedDescending;
        }
        return [SonoraCollectionsTrackTitle(left) localizedCaseInsensitiveCompare:SonoraCollectionsTrackTitle(right)];
    }];

    if (sorted.count <= limit) {
        return sorted;
    }
    return [sorted subarrayWithRange:NSMakeRange(0, limit)];
}

- (NSArray<SonoraCollectionsAlbumItem *> *)buildAlbumItemsFromTracks:(NSArray<SonoraTrack *> *)tracks limit:(NSUInteger)limit {
    if (tracks.count == 0 || limit == 0) {
        return @[];
    }

    NSMutableDictionary<NSString *, SonoraCollectionsAlbumItem *> *albumsByKey = [NSMutableDictionary dictionary];
    for (SonoraTrack *track in tracks) {
        NSArray<NSString *> *participants = SonoraCollectionsArtistParticipants(track.artist ?: @"");
        if (participants.count == 0) {
            continue;
        }

        NSDate *trackDate = SonoraCollectionsTrackModifiedDate(track);
        NSMutableSet<NSString *> *handledKeys = [NSMutableSet set];
        for (NSString *participant in participants) {
            NSString *key = SonoraCollectionsNormalizedArtistText(participant);
            if (key.length == 0 || [handledKeys containsObject:key]) {
                continue;
            }
            [handledKeys addObject:key];

            SonoraCollectionsAlbumItem *item = albumsByKey[key];
            if (item == nil) {
                item = [[SonoraCollectionsAlbumItem alloc] init];
                item.title = participant;
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
    }

    NSArray<SonoraCollectionsAlbumItem *> *sorted = [albumsByKey.allValues sortedArrayUsingComparator:^NSComparisonResult(SonoraCollectionsAlbumItem * _Nonnull left,
                                                                                                                       SonoraCollectionsAlbumItem * _Nonnull right) {
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

- (NSArray<SonoraTrack *> *)albumDetailTracksForAlbumItem:(SonoraCollectionsAlbumItem *)albumItem {
    if (albumItem == nil) {
        return @[];
    }

    NSString *targetArtist = SonoraCollectionsNormalizedArtistText(albumItem.title ?: @"");
    if (targetArtist.length == 0) {
        return @[];
    }

    NSMutableArray<SonoraTrack *> *matched = [NSMutableArray array];
    for (SonoraTrack *track in self.allTracks) {
        NSArray<NSString *> *participants = SonoraCollectionsArtistParticipants(track.artist ?: @"");
        for (NSString *participant in participants) {
            NSString *key = SonoraCollectionsNormalizedArtistText(participant);
            if ([key isEqualToString:targetArtist]) {
                [matched addObject:track];
                break;
            }
        }
    }
    [matched sortUsingComparator:^NSComparisonResult(SonoraTrack * _Nonnull left, SonoraTrack * _Nonnull right) {
        return [SonoraCollectionsTrackTitle(left) localizedCaseInsensitiveCompare:SonoraCollectionsTrackTitle(right)];
    }];
    return matched;
}

- (void)updateEmptyState {
    self.collectionView.backgroundView = nil;
}

- (void)openPlaylistsPage {
    UIViewController *playlistsController = SonoraInstantiatePlaylistsViewController();
    if (playlistsController == nil || self.navigationController == nil) {
        return;
    }
    playlistsController.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:playlistsController animated:YES];
}

- (void)openMyMusicPage {
    Class musicClass = NSClassFromString(@"SonoraMusicViewController");
    if (musicClass == Nil || ![musicClass isSubclassOfClass:UIViewController.class] || self.navigationController == nil) {
        return;
    }

    UIViewController *musicController = [[musicClass alloc] init];
    SEL setModeSelector = NSSelectorFromString(@"setMusicOnlyMode:");
    if ([musicController respondsToSelector:setModeSelector]) {
        void (*messageSend)(id, SEL, BOOL) = (void *)objc_msgSend;
        messageSend(musicController, setModeSelector, YES);
    }
    musicController.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:musicController animated:YES];
}

- (NSString *)titleForSection:(SonoraCollectionsSection)section {
    switch (section) {
        case SonoraCollectionsSectionMyMusic:
            return @"My music";
        case SonoraCollectionsSectionFavoritesSummary:
            return @"";
        case SonoraCollectionsSectionFavoritesTracks:
            return @"";
        case SonoraCollectionsSectionPlaylists:
            return @"My playlists";
        case SonoraCollectionsSectionLastAdded:
            return @"Last added";
        case SonoraCollectionsSectionAlbums:
            return @"Your albums";
    }
    return @"";
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    (void)collectionView;
    return 6;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    (void)collectionView;
    switch ((SonoraCollectionsSection)section) {
        case SonoraCollectionsSectionMyMusic:
            return self.myMusicTracks.count;
        case SonoraCollectionsSectionFavoritesSummary:
            return 1;
        case SonoraCollectionsSectionFavoritesTracks:
            return self.favoriteTracks.count;
        case SonoraCollectionsSectionPlaylists:
            return self.playlists.count + 1;
        case SonoraCollectionsSectionLastAdded:
            return self.lastAddedTracks.count;
        case SonoraCollectionsSectionAlbums:
            return self.albumItems.count;
    }
    return 0;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                            cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    switch ((SonoraCollectionsSection)indexPath.section) {
        case SonoraCollectionsSectionMyMusic: {
            SonoraCollectionsFavoriteTrackCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:SonoraCollectionsFavoriteTrackCellReuseID
                                                                                               forIndexPath:indexPath];
            if (indexPath.item < self.myMusicTracks.count) {
                [cell configureWithTrack:self.myMusicTracks[indexPath.item] accented:YES];
            }
            return cell;
        }
        case SonoraCollectionsSectionFavoritesSummary: {
            SonoraCollectionsFavoritesSummaryCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:SonoraCollectionsFavoritesSummaryCellReuseID
                                                                                                forIndexPath:indexPath];
            [cell configureWithTracksCount:self.favoriteTracks.count];
            return cell;
        }
        case SonoraCollectionsSectionFavoritesTracks: {
            SonoraCollectionsFavoriteTrackCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:SonoraCollectionsFavoriteTrackCellReuseID
                                                                                               forIndexPath:indexPath];
            if (indexPath.item < self.favoriteTracks.count) {
                [cell configureWithTrack:self.favoriteTracks[indexPath.item] accented:NO];
            }
            return cell;
        }
        case SonoraCollectionsSectionPlaylists: {
            SonoraCollectionsPlaylistCardCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:SonoraCollectionsPlaylistCellReuseID
                                                                                             forIndexPath:indexPath];
            if (indexPath.item < self.playlists.count) {
                SonoraPlaylist *playlist = self.playlists[indexPath.item];
                id sharedSnapshot = SonoraCollectionsSharedSnapshotForPlaylistID(playlist.playlistID);
                if (sharedSnapshot != nil) {
                    NSArray<SonoraTrack *> *sharedTracks = [sharedSnapshot valueForKey:@"tracks"];
                    UIImage *cover = [sharedSnapshot valueForKey:@"coverImage"];
                    if (cover == nil && [sharedTracks isKindOfClass:NSArray.class]) {
                        cover = sharedTracks.firstObject.artwork;
                    }
                    [cell configureWithTitle:playlist.name
                                    subtitle:SonoraCollectionsSharedPlaylistSubtitle(sharedSnapshot)
                                       cover:cover];
                } else {
                    UIImage *cover = [SonoraPlaylistStore.sharedStore coverForPlaylist:playlist
                                                                           library:SonoraLibraryManager.sharedManager
                                                                              size:CGSizeMake(220.0, 220.0)];
                    [cell configureWithPlaylist:playlist cover:cover];
                }
            } else {
                [cell configureAsCreatePlaylistCard];
            }
            return cell;
        }
        case SonoraCollectionsSectionLastAdded: {
            SonoraCollectionsFavoriteTrackCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:SonoraCollectionsFavoriteTrackCellReuseID
                                                                                               forIndexPath:indexPath];
            if (indexPath.item < self.lastAddedTracks.count) {
                [cell configureWithTrack:self.lastAddedTracks[indexPath.item] accented:YES];
            }
            return cell;
        }
        case SonoraCollectionsSectionAlbums: {
            SonoraCollectionsPlaylistCardCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:SonoraCollectionsPlaylistCellReuseID
                                                                                             forIndexPath:indexPath];
            if (indexPath.item < self.albumItems.count) {
                SonoraCollectionsAlbumItem *item = self.albumItems[indexPath.item];
                NSString *subtitle = [NSString stringWithFormat:@"%ld tracks", (long)item.trackCount];
                [cell configureWithTitle:item.title subtitle:subtitle cover:item.artwork];
            }
            return cell;
        }
    }
    return [UICollectionViewCell new];
}

- (__kindof UICollectionReusableView *)collectionView:(UICollectionView *)collectionView
                            viewForSupplementaryElementOfKind:(NSString *)kind
                                                  atIndexPath:(NSIndexPath *)indexPath {
    if (![kind isEqualToString:SonoraCollectionsHeaderKind]) {
        return [UICollectionReusableView new];
    }

    SonoraCollectionsSectionHeaderView *header = [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                                                                 withReuseIdentifier:SonoraCollectionsHeaderReuseID
                                                                                        forIndexPath:indexPath];
    SonoraCollectionsSection section = (SonoraCollectionsSection)indexPath.section;
    BOOL showsArrow = (section == SonoraCollectionsSectionPlaylists || section == SonoraCollectionsSectionMyMusic);
    if (!showsArrow) {
        [header configureWithTitle:@"" showsArrow:NO];
        header.tapHandler = nil;
    } else {
        __weak typeof(self) weakSelf = self;
        header.tapHandler = ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            if (section == SonoraCollectionsSectionMyMusic) {
                [strongSelf openMyMusicPage];
            } else {
                [strongSelf openPlaylistsPage];
            }
        };
    }
    NSString *title = [self titleForSection:section];
    [header configureWithTitle:title showsArrow:showsArrow];
    return header;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];

    switch ((SonoraCollectionsSection)indexPath.section) {
        case SonoraCollectionsSectionMyMusic: {
            if (indexPath.item >= self.myMusicTracks.count) {
                return;
            }
            SonoraTrack *selectedTrack = self.myMusicTracks[indexPath.item];
            SonoraTrack *currentTrack = SonoraPlaybackManager.sharedManager.currentTrack;
            BOOL isCurrent = (currentTrack != nil && [currentTrack.identifier isEqualToString:selectedTrack.identifier]);

            UIViewController *player = SonoraInstantiatePlayerFromCollections();
            if (player != nil && self.navigationController != nil) {
                player.hidesBottomBarWhenPushed = YES;
                [self.navigationController pushViewController:player animated:YES];
            }

            if (isCurrent) {
                return;
            }

            NSArray<SonoraTrack *> *queue = self.myMusicTracks;
            NSInteger startIndex = indexPath.item;
            dispatch_async(dispatch_get_main_queue(), ^{
                [SonoraPlaybackManager.sharedManager setShuffleEnabled:NO];
                [SonoraPlaybackManager.sharedManager playTracks:queue startIndex:startIndex];
            });
            return;
        }
        case SonoraCollectionsSectionFavoritesSummary: {
            UIViewController *favoritesController = SonoraInstantiateFavoritesViewController();
            if (favoritesController == nil || self.navigationController == nil) {
                return;
            }
            favoritesController.hidesBottomBarWhenPushed = YES;
            [self.navigationController pushViewController:favoritesController animated:YES];
            return;
        }
        case SonoraCollectionsSectionFavoritesTracks: {
            if (indexPath.item >= self.favoriteTracks.count) {
                return;
            }
            SonoraTrack *selectedTrack = self.favoriteTracks[indexPath.item];
            SonoraTrack *currentTrack = SonoraPlaybackManager.sharedManager.currentTrack;
            BOOL isCurrent = (currentTrack != nil && [currentTrack.identifier isEqualToString:selectedTrack.identifier]);

            UIViewController *player = SonoraInstantiatePlayerFromCollections();
            if (player != nil && self.navigationController != nil) {
                player.hidesBottomBarWhenPushed = YES;
                [self.navigationController pushViewController:player animated:YES];
            }

            if (isCurrent) {
                return;
            }

            NSArray<SonoraTrack *> *queue = self.favoriteTracks;
            NSInteger startIndex = indexPath.item;
            dispatch_async(dispatch_get_main_queue(), ^{
                [SonoraPlaybackManager.sharedManager setShuffleEnabled:NO];
                [SonoraPlaybackManager.sharedManager playTracks:queue startIndex:startIndex];
            });
            return;
        }
        case SonoraCollectionsSectionPlaylists: {
            if (indexPath.item == self.playlists.count) {
                UIViewController *nameVC = SonoraInstantiatePlaylistNameViewController();
                if (nameVC == nil || self.navigationController == nil) {
                    return;
                }
                nameVC.hidesBottomBarWhenPushed = YES;
                [self.navigationController pushViewController:nameVC animated:YES];
                return;
            }
            if (indexPath.item > self.playlists.count) {
                return;
            }
            SonoraPlaylist *playlist = self.playlists[indexPath.item];
            UIViewController *detail = SonoraInstantiatePlaylistDetailViewController(playlist.playlistID);
            if (detail == nil) {
                return;
            }
            detail.hidesBottomBarWhenPushed = YES;
            [self.navigationController pushViewController:detail animated:YES];
            return;
        }
        case SonoraCollectionsSectionLastAdded: {
            if (indexPath.item >= self.lastAddedTracks.count) {
                return;
            }
            SonoraTrack *selectedTrack = self.lastAddedTracks[indexPath.item];
            SonoraTrack *currentTrack = SonoraPlaybackManager.sharedManager.currentTrack;
            BOOL isCurrent = (currentTrack != nil && [currentTrack.identifier isEqualToString:selectedTrack.identifier]);

            UIViewController *player = SonoraInstantiatePlayerFromCollections();
            if (player != nil && self.navigationController != nil) {
                player.hidesBottomBarWhenPushed = YES;
                [self.navigationController pushViewController:player animated:YES];
            }

            if (isCurrent) {
                return;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                [SonoraPlaybackManager.sharedManager setShuffleEnabled:NO];
                [SonoraPlaybackManager.sharedManager playTracks:self.lastAddedTracks startIndex:indexPath.item];
            });
            return;
        }
        case SonoraCollectionsSectionAlbums: {
            if (indexPath.item >= self.albumItems.count) {
                return;
            }
            SonoraCollectionsAlbumItem *item = self.albumItems[indexPath.item];
            NSArray<SonoraTrack *> *tracks = [self albumDetailTracksForAlbumItem:item];
            UIViewController *player = SonoraInstantiatePlayerFromCollections();
            if (player != nil && self.navigationController != nil) {
                player.hidesBottomBarWhenPushed = YES;
            }
            Class albumClass = NSClassFromString(@"SonoraHomeAlbumDetailViewController");
            if (albumClass == Nil || ![albumClass isSubclassOfClass:UIViewController.class]) {
                return;
            }
            SEL initializer = NSSelectorFromString(@"initWithAlbumTitle:tracks:");
            id instance = [albumClass alloc];
            if (instance == nil || ![instance respondsToSelector:initializer]) {
                return;
            }
            id (*messageSend)(id, SEL, id, id) = (void *)objc_msgSend;
            UIViewController *detail = messageSend(instance, initializer, item.title, tracks);
            if (![detail isKindOfClass:UIViewController.class]) {
                return;
            }
            detail.hidesBottomBarWhenPushed = YES;
            [self.navigationController pushViewController:detail animated:YES];
            return;
        }
    }
}

@end
