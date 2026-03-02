//
//  M2CollectionsViewController.m
//  M2
//

#import "M2CollectionsViewController.h"

#import <objc/message.h>

#import "M2Services.h"

static NSString * const M2CollectionsPlaylistCellReuseID = @"M2CollectionsPlaylistCell";
static NSString * const M2CollectionsMyMusicCellReuseID = @"M2CollectionsMyMusicCell";
static NSString * const M2CollectionsFavoritesSummaryCellReuseID = @"M2CollectionsFavoritesSummaryCell";
static NSString * const M2CollectionsFavoriteTrackCellReuseID = @"M2CollectionsFavoriteTrackCell";
static NSString * const M2CollectionsHeaderReuseID = @"M2CollectionsHeader";
static NSString * const M2CollectionsHeaderKind = @"M2CollectionsHeaderKind";

typedef NS_ENUM(NSInteger, M2CollectionsSection) {
    M2CollectionsSectionFavoritesSummary = 0,
    M2CollectionsSectionFavoritesTracks = 1,
    M2CollectionsSectionPlaylists = 2,
    M2CollectionsSectionLastAdded = 3,
    M2CollectionsSectionAlbums = 4,
    M2CollectionsSectionMyMusic = 5,
};

static UIFont *M2CollectionsYSMusicFont(CGFloat size) {
    UIFont *font = [UIFont fontWithName:@"YSMusic-HeadlineBold" size:size];
    if (font != nil) {
        return font;
    }
    return [UIFont boldSystemFontOfSize:size];
}

static UIViewController * _Nullable M2InstantiatePlaylistDetailViewController(NSString *playlistID) {
    Class detailClass = NSClassFromString(@"M2PlaylistDetailViewController");
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

static UIViewController * _Nullable M2InstantiateFavoritesViewController(void) {
    Class favoritesClass = NSClassFromString(@"M2FavoritesViewController");
    if (favoritesClass == Nil || ![favoritesClass isSubclassOfClass:UIViewController.class]) {
        return nil;
    }
    return [[favoritesClass alloc] init];
}

static UIViewController * _Nullable M2InstantiatePlayerFromCollections(void) {
    Class playerClass = NSClassFromString(@"M2PlayerViewController");
    if (playerClass == Nil || ![playerClass isSubclassOfClass:UIViewController.class]) {
        return nil;
    }
    return [[playerClass alloc] init];
}

static UIViewController * _Nullable M2InstantiatePlaylistNameViewController(void) {
    Class nameClass = NSClassFromString(@"M2PlaylistNameViewController");
    if (nameClass == Nil || ![nameClass isSubclassOfClass:UIViewController.class]) {
        return nil;
    }
    return [[nameClass alloc] init];
}

static UIViewController * _Nullable M2InstantiatePlaylistsViewController(void) {
    Class playlistsClass = NSClassFromString(@"M2PlaylistsViewController");
    if (playlistsClass == Nil || ![playlistsClass isSubclassOfClass:UIViewController.class]) {
        return nil;
    }
    return [[playlistsClass alloc] init];
}

static NSString *M2CollectionsTrackTitle(M2Track *track) {
    if (track.title.length > 0) {
        return track.title;
    }
    if (track.fileName.length > 0) {
        return track.fileName.stringByDeletingPathExtension;
    }
    return @"Unknown track";
}

static NSString *M2CollectionsTrackArtist(M2Track *track) {
    if (track.artist.length > 0) {
        return track.artist;
    }
    return @"";
}

static NSDate *M2CollectionsTrackModifiedDate(M2Track *track) {
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

static NSString *M2CollectionsNormalizedArtistText(NSString *artist) {
    NSString *value = [artist stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return value.lowercaseString ?: @"";
}

static NSArray<NSString *> *M2CollectionsArtistParticipants(NSString *artistText) {
    NSString *trimmed = [artistText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        return @[];
    }

    NSMutableArray<NSString *> *result = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSArray<NSString *> *chunks = [trimmed componentsSeparatedByString:@","];
    for (NSString *chunk in chunks) {
        NSString *value = [chunk stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *key = M2CollectionsNormalizedArtistText(value);
        if (key.length == 0 || [seen containsObject:key]) {
            continue;
        }
        [seen addObject:key];
        [result addObject:value];
    }
    return result;
}

@interface M2CollectionsAlbumItem : NSObject

@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) UIImage *artwork;
@property (nonatomic, strong) NSDate *latestDate;
@property (nonatomic, assign) NSInteger trackCount;
@property (nonatomic, copy) NSArray<M2Track *> *tracks;

@end

@implementation M2CollectionsAlbumItem
@end

@interface M2CollectionsPlaylistCardCell : UICollectionViewCell

- (void)configureWithPlaylist:(M2Playlist *)playlist cover:(UIImage *)cover;
- (void)configureWithTitle:(NSString *)title subtitle:(NSString *)subtitle cover:(UIImage *)cover;
- (void)configureAsCreatePlaylistCard;

@end

@interface M2CollectionsPlaylistCardCell ()

@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;

@end

@implementation M2CollectionsPlaylistCardCell

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

- (void)configureWithPlaylist:(M2Playlist *)playlist cover:(UIImage *)cover {
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

@interface M2CollectionsMyMusicCell : UICollectionViewCell
@end

@interface M2CollectionsMyMusicCell ()

@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIImageView *arrowView;

@end

@implementation M2CollectionsMyMusicCell

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
    titleLabel.font = M2CollectionsYSMusicFont(24.0);
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

@interface M2CollectionsFavoritesSummaryCell : UICollectionViewCell

- (void)configureWithTracksCount:(NSInteger)tracksCount;

@end

@interface M2CollectionsFavoritesSummaryCell ()

@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIImageView *arrowView;
@property (nonatomic, strong) UILabel *subtitleLabel;

@end

@implementation M2CollectionsFavoritesSummaryCell

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
    titleLabel.font = M2CollectionsYSMusicFont(20.0);
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

@interface M2CollectionsFavoriteTrackCell : UICollectionViewCell

- (void)configureWithTrack:(M2Track *)track;
- (void)configureWithTrack:(M2Track *)track accented:(BOOL)accented;

@end

@interface M2CollectionsFavoriteTrackCell ()

@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *artistLabel;

@end

@implementation M2CollectionsFavoriteTrackCell

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
    [self configureWithTrack:track accented:NO];
}

- (void)configureWithTrack:(M2Track *)track accented:(BOOL)accented {
    if (accented) {
        UIColor *base = [M2ArtworkAccentColorService dominantAccentColorForImage:track.artwork
                                                                         fallback:UIColor.clearColor];
        CGFloat alpha = (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) ? 0.20 : 0.12;
        self.contentView.backgroundColor = [base colorWithAlphaComponent:alpha];
    } else {
        self.contentView.backgroundColor = UIColor.clearColor;
    }
    self.coverView.image = track.artwork;
    self.titleLabel.text = M2CollectionsTrackTitle(track);
    NSString *artist = M2CollectionsTrackArtist(track);
    self.artistLabel.text = artist;
    self.artistLabel.hidden = (artist.length == 0);
}

@end

@interface M2CollectionsSectionHeaderView : UICollectionReusableView

- (void)configureWithTitle:(NSString *)title showsArrow:(BOOL)showsArrow;
@property (nonatomic, copy, nullable) dispatch_block_t tapHandler;

@end

@interface M2CollectionsSectionHeaderView ()

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIImageView *arrowView;

@end

@implementation M2CollectionsSectionHeaderView

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
    label.font = M2CollectionsYSMusicFont(24.0);
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

@interface M2CollectionsViewController () <UICollectionViewDataSource, UICollectionViewDelegate>

@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, copy) NSArray<M2Playlist *> *playlists;
@property (nonatomic, copy) NSArray<M2Track *> *favoriteTracks;
@property (nonatomic, copy) NSArray<M2Track *> *allTracks;
@property (nonatomic, copy) NSArray<M2Track *> *lastAddedTracks;
@property (nonatomic, copy) NSArray<M2CollectionsAlbumItem *> *albumItems;
@property (nonatomic, copy) NSArray<M2Track *> *myMusicTracks;

@end

@implementation M2CollectionsViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupNavigationBar];
    [self setupCollectionView];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(reloadCollections)
                                               name:M2PlaylistsDidChangeNotification
                                             object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                            selector:@selector(reloadCollections)
                                                name:M2FavoritesDidChangeNotification
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

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"Collections";
    titleLabel.textColor = UIColor.labelColor;
    titleLabel.font = M2CollectionsYSMusicFont(30.0);
    [titleLabel sizeToFit];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:titleLabel];
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

    [collectionView registerClass:M2CollectionsPlaylistCardCell.class
       forCellWithReuseIdentifier:M2CollectionsPlaylistCellReuseID];
    [collectionView registerClass:M2CollectionsFavoritesSummaryCell.class
       forCellWithReuseIdentifier:M2CollectionsFavoritesSummaryCellReuseID];
    [collectionView registerClass:M2CollectionsFavoriteTrackCell.class
       forCellWithReuseIdentifier:M2CollectionsFavoriteTrackCellReuseID];
    [collectionView registerClass:M2CollectionsSectionHeaderView.class
       forSupplementaryViewOfKind:M2CollectionsHeaderKind
              withReuseIdentifier:M2CollectionsHeaderReuseID];

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
        switch ((M2CollectionsSection)sectionIndex) {
            case M2CollectionsSectionMyMusic:
                return [strongSelf myMusicSectionLayout];
            case M2CollectionsSectionFavoritesSummary:
                return [strongSelf favoritesSummarySectionLayout];
            case M2CollectionsSectionFavoritesTracks:
                return [strongSelf favoritesTracksSectionLayout];
            case M2CollectionsSectionPlaylists:
                return [strongSelf playlistsSectionLayout];
            case M2CollectionsSectionLastAdded:
                return [strongSelf lastAddedSectionLayout];
            case M2CollectionsSectionAlbums:
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
                                                           elementKind:M2CollectionsHeaderKind
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
    M2PlaylistStore *playlistStore = M2PlaylistStore.sharedStore;
    [playlistStore reloadPlaylists];
    self.playlists = playlistStore.playlists ?: @[];

    M2LibraryManager *library = M2LibraryManager.sharedManager;
    if (library.tracks.count == 0 && M2FavoritesStore.sharedStore.favoriteTrackIDs.count > 0) {
        [library reloadTracks];
    }
    self.allTracks = library.tracks ?: @[];
    self.favoriteTracks = [M2FavoritesStore.sharedStore favoriteTracksWithLibrary:library] ?: @[];
    self.lastAddedTracks = [self buildLastAddedTracksFromTracks:self.allTracks limit:14];
    self.albumItems = [self buildAlbumItemsFromTracks:self.allTracks limit:14];
    NSArray<M2Track *> *affinityTracks = [M2TrackAnalyticsStore.sharedStore tracksSortedByAffinity:self.allTracks] ?: @[];
    if (affinityTracks.count > 14) {
        self.myMusicTracks = [affinityTracks subarrayWithRange:NSMakeRange(0, 14)];
    } else {
        self.myMusicTracks = affinityTracks;
    }

    [self.collectionView reloadData];
    [self updateEmptyState];
}

- (NSArray<M2Track *> *)buildLastAddedTracksFromTracks:(NSArray<M2Track *> *)tracks limit:(NSUInteger)limit {
    if (tracks.count == 0 || limit == 0) {
        return @[];
    }

    NSArray<M2Track *> *sorted = [tracks sortedArrayUsingComparator:^NSComparisonResult(M2Track * _Nonnull left,
                                                                                         M2Track * _Nonnull right) {
        NSTimeInterval leftTime = M2CollectionsTrackModifiedDate(left).timeIntervalSince1970;
        NSTimeInterval rightTime = M2CollectionsTrackModifiedDate(right).timeIntervalSince1970;
        if (leftTime > rightTime) {
            return NSOrderedAscending;
        }
        if (leftTime < rightTime) {
            return NSOrderedDescending;
        }
        return [M2CollectionsTrackTitle(left) localizedCaseInsensitiveCompare:M2CollectionsTrackTitle(right)];
    }];

    if (sorted.count <= limit) {
        return sorted;
    }
    return [sorted subarrayWithRange:NSMakeRange(0, limit)];
}

- (NSArray<M2CollectionsAlbumItem *> *)buildAlbumItemsFromTracks:(NSArray<M2Track *> *)tracks limit:(NSUInteger)limit {
    if (tracks.count == 0 || limit == 0) {
        return @[];
    }

    NSMutableDictionary<NSString *, M2CollectionsAlbumItem *> *albumsByKey = [NSMutableDictionary dictionary];
    for (M2Track *track in tracks) {
        NSArray<NSString *> *participants = M2CollectionsArtistParticipants(track.artist ?: @"");
        if (participants.count == 0) {
            continue;
        }

        NSDate *trackDate = M2CollectionsTrackModifiedDate(track);
        NSMutableSet<NSString *> *handledKeys = [NSMutableSet set];
        for (NSString *participant in participants) {
            NSString *key = M2CollectionsNormalizedArtistText(participant);
            if (key.length == 0 || [handledKeys containsObject:key]) {
                continue;
            }
            [handledKeys addObject:key];

            M2CollectionsAlbumItem *item = albumsByKey[key];
            if (item == nil) {
                item = [[M2CollectionsAlbumItem alloc] init];
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

    NSArray<M2CollectionsAlbumItem *> *sorted = [albumsByKey.allValues sortedArrayUsingComparator:^NSComparisonResult(M2CollectionsAlbumItem * _Nonnull left,
                                                                                                                       M2CollectionsAlbumItem * _Nonnull right) {
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

- (NSArray<M2Track *> *)albumDetailTracksForAlbumItem:(M2CollectionsAlbumItem *)albumItem {
    if (albumItem == nil) {
        return @[];
    }

    NSString *targetArtist = M2CollectionsNormalizedArtistText(albumItem.title ?: @"");
    if (targetArtist.length == 0) {
        return @[];
    }

    NSMutableArray<M2Track *> *matched = [NSMutableArray array];
    for (M2Track *track in self.allTracks) {
        NSArray<NSString *> *participants = M2CollectionsArtistParticipants(track.artist ?: @"");
        for (NSString *participant in participants) {
            NSString *key = M2CollectionsNormalizedArtistText(participant);
            if ([key isEqualToString:targetArtist]) {
                [matched addObject:track];
                break;
            }
        }
    }
    [matched sortUsingComparator:^NSComparisonResult(M2Track * _Nonnull left, M2Track * _Nonnull right) {
        return [M2CollectionsTrackTitle(left) localizedCaseInsensitiveCompare:M2CollectionsTrackTitle(right)];
    }];
    return matched;
}

- (void)updateEmptyState {
    self.collectionView.backgroundView = nil;
}

- (void)openPlaylistsPage {
    UIViewController *playlistsController = M2InstantiatePlaylistsViewController();
    if (playlistsController == nil || self.navigationController == nil) {
        return;
    }
    playlistsController.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:playlistsController animated:YES];
}

- (void)openMyMusicPage {
    Class musicClass = NSClassFromString(@"M2MusicViewController");
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

- (NSString *)titleForSection:(M2CollectionsSection)section {
    switch (section) {
        case M2CollectionsSectionMyMusic:
            return @"My music";
        case M2CollectionsSectionFavoritesSummary:
            return @"";
        case M2CollectionsSectionFavoritesTracks:
            return @"";
        case M2CollectionsSectionPlaylists:
            return @"My playlists";
        case M2CollectionsSectionLastAdded:
            return @"Last added";
        case M2CollectionsSectionAlbums:
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
    switch ((M2CollectionsSection)section) {
        case M2CollectionsSectionMyMusic:
            return self.myMusicTracks.count;
        case M2CollectionsSectionFavoritesSummary:
            return 1;
        case M2CollectionsSectionFavoritesTracks:
            return self.favoriteTracks.count;
        case M2CollectionsSectionPlaylists:
            return self.playlists.count + 1;
        case M2CollectionsSectionLastAdded:
            return self.lastAddedTracks.count;
        case M2CollectionsSectionAlbums:
            return self.albumItems.count;
    }
    return 0;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                            cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    switch ((M2CollectionsSection)indexPath.section) {
        case M2CollectionsSectionMyMusic: {
            M2CollectionsFavoriteTrackCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:M2CollectionsFavoriteTrackCellReuseID
                                                                                               forIndexPath:indexPath];
            if (indexPath.item < self.myMusicTracks.count) {
                [cell configureWithTrack:self.myMusicTracks[indexPath.item] accented:YES];
            }
            return cell;
        }
        case M2CollectionsSectionFavoritesSummary: {
            M2CollectionsFavoritesSummaryCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:M2CollectionsFavoritesSummaryCellReuseID
                                                                                                forIndexPath:indexPath];
            [cell configureWithTracksCount:self.favoriteTracks.count];
            return cell;
        }
        case M2CollectionsSectionFavoritesTracks: {
            M2CollectionsFavoriteTrackCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:M2CollectionsFavoriteTrackCellReuseID
                                                                                               forIndexPath:indexPath];
            if (indexPath.item < self.favoriteTracks.count) {
                [cell configureWithTrack:self.favoriteTracks[indexPath.item] accented:NO];
            }
            return cell;
        }
        case M2CollectionsSectionPlaylists: {
            M2CollectionsPlaylistCardCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:M2CollectionsPlaylistCellReuseID
                                                                                             forIndexPath:indexPath];
            if (indexPath.item < self.playlists.count) {
                M2Playlist *playlist = self.playlists[indexPath.item];
                UIImage *cover = [M2PlaylistStore.sharedStore coverForPlaylist:playlist
                                                                       library:M2LibraryManager.sharedManager
                                                                          size:CGSizeMake(220.0, 220.0)];
                [cell configureWithPlaylist:playlist cover:cover];
            } else {
                [cell configureAsCreatePlaylistCard];
            }
            return cell;
        }
        case M2CollectionsSectionLastAdded: {
            M2CollectionsFavoriteTrackCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:M2CollectionsFavoriteTrackCellReuseID
                                                                                               forIndexPath:indexPath];
            if (indexPath.item < self.lastAddedTracks.count) {
                [cell configureWithTrack:self.lastAddedTracks[indexPath.item] accented:YES];
            }
            return cell;
        }
        case M2CollectionsSectionAlbums: {
            M2CollectionsPlaylistCardCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:M2CollectionsPlaylistCellReuseID
                                                                                             forIndexPath:indexPath];
            if (indexPath.item < self.albumItems.count) {
                M2CollectionsAlbumItem *item = self.albumItems[indexPath.item];
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
    if (![kind isEqualToString:M2CollectionsHeaderKind]) {
        return [UICollectionReusableView new];
    }

    M2CollectionsSectionHeaderView *header = [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                                                                 withReuseIdentifier:M2CollectionsHeaderReuseID
                                                                                        forIndexPath:indexPath];
    M2CollectionsSection section = (M2CollectionsSection)indexPath.section;
    BOOL showsArrow = (section == M2CollectionsSectionPlaylists || section == M2CollectionsSectionMyMusic);
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
            if (section == M2CollectionsSectionMyMusic) {
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

    switch ((M2CollectionsSection)indexPath.section) {
        case M2CollectionsSectionMyMusic: {
            if (indexPath.item >= self.myMusicTracks.count) {
                return;
            }
            M2Track *selectedTrack = self.myMusicTracks[indexPath.item];
            M2Track *currentTrack = M2PlaybackManager.sharedManager.currentTrack;
            BOOL isCurrent = (currentTrack != nil && [currentTrack.identifier isEqualToString:selectedTrack.identifier]);

            UIViewController *player = M2InstantiatePlayerFromCollections();
            if (player != nil && self.navigationController != nil) {
                player.hidesBottomBarWhenPushed = YES;
                [self.navigationController pushViewController:player animated:YES];
            }

            if (isCurrent) {
                return;
            }

            NSArray<M2Track *> *queue = self.myMusicTracks;
            NSInteger startIndex = indexPath.item;
            dispatch_async(dispatch_get_main_queue(), ^{
                [M2PlaybackManager.sharedManager setShuffleEnabled:NO];
                [M2PlaybackManager.sharedManager playTracks:queue startIndex:startIndex];
            });
            return;
        }
        case M2CollectionsSectionFavoritesSummary: {
            UIViewController *favoritesController = M2InstantiateFavoritesViewController();
            if (favoritesController == nil || self.navigationController == nil) {
                return;
            }
            favoritesController.hidesBottomBarWhenPushed = YES;
            [self.navigationController pushViewController:favoritesController animated:YES];
            return;
        }
        case M2CollectionsSectionFavoritesTracks: {
            if (indexPath.item >= self.favoriteTracks.count) {
                return;
            }
            M2Track *selectedTrack = self.favoriteTracks[indexPath.item];
            M2Track *currentTrack = M2PlaybackManager.sharedManager.currentTrack;
            BOOL isCurrent = (currentTrack != nil && [currentTrack.identifier isEqualToString:selectedTrack.identifier]);

            UIViewController *player = M2InstantiatePlayerFromCollections();
            if (player != nil && self.navigationController != nil) {
                player.hidesBottomBarWhenPushed = YES;
                [self.navigationController pushViewController:player animated:YES];
            }

            if (isCurrent) {
                return;
            }

            NSArray<M2Track *> *queue = self.favoriteTracks;
            NSInteger startIndex = indexPath.item;
            dispatch_async(dispatch_get_main_queue(), ^{
                [M2PlaybackManager.sharedManager setShuffleEnabled:NO];
                [M2PlaybackManager.sharedManager playTracks:queue startIndex:startIndex];
            });
            return;
        }
        case M2CollectionsSectionPlaylists: {
            if (indexPath.item == self.playlists.count) {
                UIViewController *nameVC = M2InstantiatePlaylistNameViewController();
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
            M2Playlist *playlist = self.playlists[indexPath.item];
            UIViewController *detail = M2InstantiatePlaylistDetailViewController(playlist.playlistID);
            if (detail == nil) {
                return;
            }
            detail.hidesBottomBarWhenPushed = YES;
            [self.navigationController pushViewController:detail animated:YES];
            return;
        }
        case M2CollectionsSectionLastAdded: {
            if (indexPath.item >= self.lastAddedTracks.count) {
                return;
            }
            M2Track *selectedTrack = self.lastAddedTracks[indexPath.item];
            M2Track *currentTrack = M2PlaybackManager.sharedManager.currentTrack;
            BOOL isCurrent = (currentTrack != nil && [currentTrack.identifier isEqualToString:selectedTrack.identifier]);

            UIViewController *player = M2InstantiatePlayerFromCollections();
            if (player != nil && self.navigationController != nil) {
                player.hidesBottomBarWhenPushed = YES;
                [self.navigationController pushViewController:player animated:YES];
            }

            if (isCurrent) {
                return;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                [M2PlaybackManager.sharedManager setShuffleEnabled:NO];
                [M2PlaybackManager.sharedManager playTracks:self.lastAddedTracks startIndex:indexPath.item];
            });
            return;
        }
        case M2CollectionsSectionAlbums: {
            if (indexPath.item >= self.albumItems.count) {
                return;
            }
            M2CollectionsAlbumItem *item = self.albumItems[indexPath.item];
            NSArray<M2Track *> *tracks = [self albumDetailTracksForAlbumItem:item];
            UIViewController *player = M2InstantiatePlayerFromCollections();
            if (player != nil && self.navigationController != nil) {
                player.hidesBottomBarWhenPushed = YES;
            }
            Class albumClass = NSClassFromString(@"M2HomeAlbumDetailViewController");
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
