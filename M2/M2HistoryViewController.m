//
//  M2HistoryViewController.m
//  M2
//

#import "M2HistoryViewController.h"

#import "M2Cells.h"
#import "M2Services.h"

static UIViewController * _Nullable M2InstantiatePlayerFromHistory(void) {
    Class playerClass = NSClassFromString(@"M2PlayerViewController");
    if (playerClass == Nil || ![playerClass isSubclassOfClass:UIViewController.class]) {
        return nil;
    }
    return [[playerClass alloc] init];
}

@interface M2HistoryViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray<M2Track *> *tracks;

@end

@implementation M2HistoryViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"History";
    self.navigationItem.hidesBackButton = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    UISwipeGestureRecognizer *swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self
                                                                                      action:@selector(handleDismissSwipe)];
    swipeRight.direction = UISwipeGestureRecognizerDirectionRight;
    [self.view addGestureRecognizer:swipeRight];

    [self setupTableView];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(reloadHistory)
                                               name:UIApplicationWillEnterForegroundNotification
                                             object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handlePlaybackChanged)
                                               name:M2PlaybackStateDidChangeNotification
                                             object:nil];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationItem.hidesBackButton = YES;
    self.navigationController.interactivePopGestureRecognizer.enabled = YES;
    self.navigationController.interactivePopGestureRecognizer.delegate = nil;
    [self reloadHistory];
}

- (void)handleDismissSwipe {
    if (self.navigationController != nil) {
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
    if (@available(iOS 15.0, *)) {
        tableView.sectionHeaderTopPadding = 0.0;
    }
    [tableView registerClass:M2TrackCell.class forCellReuseIdentifier:@"M2HistoryTrackCell"];

    self.tableView = tableView;
    [self.view addSubview:tableView];

    [NSLayoutConstraint activateConstraints:@[
        [tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)reloadHistory {
    M2LibraryManager *library = M2LibraryManager.sharedManager;
    if (library.tracks.count == 0) {
        [library reloadTracks];
    }

    self.tracks = [M2PlaybackHistoryStore.sharedStore recentTracksWithLibrary:library limit:120];
    [self.tableView reloadData];
    [self updateEmptyState];
}

- (void)updateEmptyState {
    if (self.tracks.count > 0) {
        self.tableView.backgroundView = nil;
        return;
    }

    UILabel *label = [[UILabel alloc] init];
    label.text = @"No listening history yet.";
    label.textColor = UIColor.secondaryLabelColor;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
    self.tableView.backgroundView = label;
}

- (void)handlePlaybackChanged {
    [self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return self.tracks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    M2TrackCell *cell = [tableView dequeueReusableCellWithIdentifier:@"M2HistoryTrackCell" forIndexPath:indexPath];
    if (indexPath.row >= self.tracks.count) {
        return cell;
    }

    M2Track *track = self.tracks[indexPath.row];
    M2PlaybackManager *playback = M2PlaybackManager.sharedManager;
    M2Track *currentTrack = playback.currentTrack;
    BOOL isCurrent = (currentTrack != nil && [currentTrack.identifier isEqualToString:track.identifier]);
    BOOL showsPlaybackIndicator = (isCurrent && playback.isPlaying);
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
    BOOL isCurrent = (currentTrack != nil && [currentTrack.identifier isEqualToString:selectedTrack.identifier]);

    UIViewController *player = M2InstantiatePlayerFromHistory();
    if (player != nil && self.navigationController != nil) {
        player.hidesBottomBarWhenPushed = YES;
        [self.navigationController pushViewController:player animated:YES];
    }

    if (isCurrent) {
        return;
    }

    NSArray<M2Track *> *queue = self.tracks;
    NSInteger startIndex = indexPath.row;
    dispatch_async(dispatch_get_main_queue(), ^{
        [M2PlaybackManager.sharedManager setShuffleEnabled:NO];
        [M2PlaybackManager.sharedManager playTracks:queue startIndex:startIndex];
    });
}

@end
