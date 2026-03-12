//
//  SonoraPlaylistCreationViewControllers.m
//  Sonora
//

#import "SonoraPlaylistViewControllers.h"

#import <PhotosUI/PhotosUI.h>

#import "SonoraCells.h"
#import "SonoraMusicUIHelpers.h"
#import "SonoraServices.h"

#pragma mark - Playlist Name Step

@interface SonoraPlaylistNameViewController () <UITextFieldDelegate>

@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UIButton *nextButton;
@property (nonatomic, strong) UILabel *counterLabel;

@end

@implementation SonoraPlaylistNameViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Create Playlist";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    [self setupUI];
    [self updateNameUI];
}

- (void)setupUI {
    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:scrollView];

    UIView *content = [[UIView alloc] init];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView addSubview:content];

    UIView *heroCard = [[UIView alloc] init];
    heroCard.translatesAutoresizingMaskIntoConstraints = NO;
    heroCard.backgroundColor = UIColor.clearColor;

    UILabel *heroTitle = [[UILabel alloc] init];
    heroTitle.translatesAutoresizingMaskIntoConstraints = NO;
    heroTitle.text = @"Name Your Playlist";
    heroTitle.font = [UIFont systemFontOfSize:30.0 weight:UIFontWeightBold];
    heroTitle.textColor = UIColor.labelColor;
    heroTitle.numberOfLines = 1;

    [heroCard addSubview:heroTitle];

    UIView *inputCard = [[UIView alloc] init];
    inputCard.translatesAutoresizingMaskIntoConstraints = NO;
    inputCard.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
        if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return [UIColor colorWithWhite:1.0 alpha:0.06];
        }
        return [UIColor colorWithWhite:0.0 alpha:0.03];
    }];
    inputCard.layer.cornerRadius = 18.0;
    inputCard.layer.borderWidth = 1.0;
    inputCard.layer.borderColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
        if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return [UIColor colorWithWhite:1.0 alpha:0.14];
        }
        return [UIColor colorWithWhite:0.0 alpha:0.08];
    }].CGColor;

    UILabel *inputTitle = [[UILabel alloc] init];
    inputTitle.translatesAutoresizingMaskIntoConstraints = NO;
    inputTitle.text = @"Playlist Name";
    inputTitle.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    inputTitle.textColor = UIColor.secondaryLabelColor;

    UITextField *nameField = [[UITextField alloc] init];
    nameField.translatesAutoresizingMaskIntoConstraints = NO;
    nameField.borderStyle = UITextBorderStyleNone;
    nameField.placeholder = @"Example: Late Night Drive";
    nameField.returnKeyType = UIReturnKeyNext;
    nameField.clearButtonMode = UITextFieldViewModeWhileEditing;
    nameField.delegate = self;
    nameField.font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightSemibold];
    nameField.textColor = UIColor.labelColor;
    [nameField addTarget:self action:@selector(nameDidChange) forControlEvents:UIControlEventEditingChanged];
    self.nameField = nameField;

    UILabel *counterLabel = [[UILabel alloc] init];
    counterLabel.translatesAutoresizingMaskIntoConstraints = NO;
    counterLabel.font = [UIFont monospacedDigitSystemFontOfSize:12.0 weight:UIFontWeightSemibold];
    counterLabel.textColor = UIColor.secondaryLabelColor;
    counterLabel.textAlignment = NSTextAlignmentRight;
    self.counterLabel = counterLabel;

    [inputCard addSubview:inputTitle];
    [inputCard addSubview:nameField];
    [inputCard addSubview:counterLabel];

    UIButton *nextButton = [UIButton buttonWithType:UIButtonTypeSystem];
    nextButton.translatesAutoresizingMaskIntoConstraints = NO;
    [nextButton setTitle:@"Next: Choose Music" forState:UIControlStateNormal];
    [nextButton setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
    nextButton.titleLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightBold];
    nextButton.layer.cornerRadius = 14.0;
    [nextButton addTarget:self action:@selector(nextTapped) forControlEvents:UIControlEventTouchUpInside];
    self.nextButton = nextButton;

    [content addSubview:heroCard];
    [content addSubview:inputCard];
    [self.view addSubview:nextButton];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray arrayWithArray:@[
        [scrollView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:nextButton.topAnchor constant:-12.0],

        [content.topAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor],
        [content.leadingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.trailingAnchor],
        [content.bottomAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor],
        [content.widthAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.widthAnchor],

        [heroCard.topAnchor constraintEqualToAnchor:content.topAnchor constant:16.0],
        [heroCard.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16.0],
        [heroCard.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16.0],
        [heroCard.heightAnchor constraintEqualToConstant:58.0],

        [heroTitle.topAnchor constraintEqualToAnchor:heroCard.topAnchor constant:8.0],
        [heroTitle.leadingAnchor constraintEqualToAnchor:heroCard.leadingAnchor constant:14.0],
        [heroTitle.trailingAnchor constraintEqualToAnchor:heroCard.trailingAnchor constant:-14.0],

        [inputCard.topAnchor constraintEqualToAnchor:heroCard.bottomAnchor constant:10.0],
        [inputCard.leadingAnchor constraintEqualToAnchor:heroCard.leadingAnchor],
        [inputCard.trailingAnchor constraintEqualToAnchor:heroCard.trailingAnchor],
        [inputCard.heightAnchor constraintEqualToConstant:118.0],

        [inputTitle.topAnchor constraintEqualToAnchor:inputCard.topAnchor constant:14.0],
        [inputTitle.leadingAnchor constraintEqualToAnchor:inputCard.leadingAnchor constant:14.0],
        [inputTitle.trailingAnchor constraintEqualToAnchor:inputCard.trailingAnchor constant:-14.0],

        [nameField.topAnchor constraintEqualToAnchor:inputTitle.bottomAnchor constant:8.0],
        [nameField.leadingAnchor constraintEqualToAnchor:inputTitle.leadingAnchor],
        [nameField.trailingAnchor constraintEqualToAnchor:inputTitle.trailingAnchor],
        [nameField.heightAnchor constraintEqualToConstant:42.0],

        [counterLabel.trailingAnchor constraintEqualToAnchor:nameField.trailingAnchor],
        [counterLabel.bottomAnchor constraintEqualToAnchor:inputCard.bottomAnchor constant:-10.0],
        [counterLabel.widthAnchor constraintEqualToConstant:62.0],

        [content.bottomAnchor constraintEqualToAnchor:inputCard.bottomAnchor constant:24.0],

        [nextButton.leadingAnchor constraintEqualToAnchor:inputCard.leadingAnchor],
        [nextButton.trailingAnchor constraintEqualToAnchor:inputCard.trailingAnchor],
        [nextButton.heightAnchor constraintEqualToConstant:52.0]
    ]];

    if (@available(iOS 15.0, *)) {
        [constraints addObject:[nextButton.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor constant:-12.0]];
    } else {
        [constraints addObject:[nextButton.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-12.0]];
    }

    [NSLayoutConstraint activateConstraints:constraints];
}

- (void)nameDidChange {
    [self updateNameUI];
}

- (void)updateNameUI {
    NSString *trimmed = [self.nameField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSUInteger length = self.nameField.text.length;
    if (length > 32) {
        self.nameField.text = [self.nameField.text substringToIndex:32];
        length = 32;
    }

    self.counterLabel.text = [NSString stringWithFormat:@"%lu/32", (unsigned long)length];

    BOOL enabled = (trimmed.length > 0);
    self.nextButton.enabled = enabled;
    self.nextButton.alpha = enabled ? 1.0 : 0.45;
    self.nextButton.backgroundColor = enabled ? SonoraAccentYellowColor() : [UIColor colorWithWhite:0.65 alpha:0.4];
}

- (void)nextTapped {
    NSString *name = [self.nameField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (name.length == 0) {
        SonoraPresentAlert(self, @"Name Required", @"Enter playlist name.");
        return;
    }

    NSArray<SonoraTrack *> *tracks = [SonoraLibraryManager.sharedManager reloadTracks];
    if (tracks.count == 0) {
        SonoraPresentAlert(self, @"No Music", @"Add music files in Files app first.");
        return;
    }

    SonoraPlaylistTrackPickerViewController *picker = [[SonoraPlaylistTrackPickerViewController alloc] initWithPlaylistName:name tracks:tracks];
    picker.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:picker animated:YES];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    (void)textField;
    [self nextTapped];
    return YES;
}

- (BOOL)textField:(UITextField *)textField
shouldChangeCharactersInRange:(NSRange)range
replacementString:(NSString *)string {
    NSString *current = textField.text ?: @"";
    NSString *updated = [current stringByReplacingCharactersInRange:range withString:string ?: @""];
    return (updated.length <= 32);
}

@end

#pragma mark - Playlist Track Step

@interface SonoraPlaylistTrackPickerViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>

@property (nonatomic, copy) NSString *playlistName;
@property (nonatomic, copy) NSArray<SonoraTrack *> *tracks;
@property (nonatomic, copy) NSArray<SonoraTrack *> *filteredTracks;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedTrackIDs;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSString *searchQuery;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, assign) BOOL searchControllerAttached;

@end

@implementation SonoraPlaylistTrackPickerViewController

- (instancetype)initWithPlaylistName:(NSString *)playlistName tracks:(NSArray<SonoraTrack *> *)tracks {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _playlistName = [playlistName copy];
        _tracks = [[SonoraTrackAnalyticsStore.sharedStore tracksSortedByAffinity:tracks] copy];
        _filteredTracks = _tracks;
        _selectedTrackIDs = [NSMutableSet set];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Select Music";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Create"
                                                                               style:UIBarButtonItemStyleDone
                                                                              target:self
                                                                              action:@selector(createTapped)];

    [self setupTableView];
    [self setupSearch];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateSearchControllerAttachment];
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
    [tableView registerClass:SonoraTrackCell.class forCellReuseIdentifier:@"TrackPickCell"];

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
    self.searchController = SonoraBuildSearchController(self, @"Search Tracks");
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
}

- (void)createTapped {
    if (self.selectedTrackIDs.count == 0) {
        SonoraPresentAlert(self, @"No Music Selected", @"Select at least one track.");
        return;
    }

    NSMutableArray<NSString *> *orderedIDs = [NSMutableArray arrayWithCapacity:self.selectedTrackIDs.count];
    for (SonoraTrack *track in self.tracks) {
        if ([self.selectedTrackIDs containsObject:track.identifier]) {
            [orderedIDs addObject:track.identifier];
        }
    }

    SonoraPlaylist *playlist = [SonoraPlaylistStore.sharedStore addPlaylistWithName:self.playlistName
                                                                            trackIDs:orderedIDs
                                                                          coverImage:nil];
    if (playlist == nil) {
        SonoraPresentAlert(self, @"Error", @"Could not create playlist.");
        return;
    }

    SonoraPlaylistDetailViewController *detail = [[SonoraPlaylistDetailViewController alloc] initWithPlaylistID:playlist.playlistID];
    detail.hidesBottomBarWhenPushed = YES;
    UIViewController *root = self.navigationController.viewControllers.firstObject;
    if (root != nil) {
        [self.navigationController setViewControllers:@[root, detail] animated:YES];
    } else {
        [self.navigationController pushViewController:detail animated:YES];
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return self.filteredTracks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SonoraTrackCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TrackPickCell" forIndexPath:indexPath];

    SonoraTrack *track = self.filteredTracks[indexPath.row];
    BOOL selected = [self.selectedTrackIDs containsObject:track.identifier];
    [cell configureWithTrack:track isCurrent:selected];
    cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.row >= self.filteredTracks.count) {
        return;
    }
    SonoraTrack *track = self.filteredTracks[indexPath.row];
    if ([self.selectedTrackIDs containsObject:track.identifier]) {
        [self.selectedTrackIDs removeObject:track.identifier];
    } else {
        [self.selectedTrackIDs addObject:track.identifier];
    }

    [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
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

#pragma mark - Playlist Add Tracks

@interface SonoraPlaylistAddTracksViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, copy) NSString *playlistID;
@property (nonatomic, copy) NSArray<SonoraTrack *> *availableTracks;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedTrackIDs;
@property (nonatomic, strong) UITableView *tableView;

@end

@implementation SonoraPlaylistAddTracksViewController

- (instancetype)initWithPlaylistID:(NSString *)playlistID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _playlistID = [playlistID copy];
        _availableTracks = @[];
        _selectedTrackIDs = [NSMutableSet set];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Add Music";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Add"
                                                                               style:UIBarButtonItemStyleDone
                                                                              target:self
                                                                              action:@selector(addTapped)];
    self.navigationItem.rightBarButtonItem.enabled = NO;

    [self setupTableView];
    [self reloadAvailableTracks];
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
    [tableView registerClass:SonoraTrackCell.class forCellReuseIdentifier:@"PlaylistAddTrackCell"];

    self.tableView = tableView;
    [self.view addSubview:tableView];

    [NSLayoutConstraint activateConstraints:@[
        [tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)reloadAvailableTracks {
    [SonoraPlaylistStore.sharedStore reloadPlaylists];
    SonoraPlaylist *playlist = [SonoraPlaylistStore.sharedStore playlistWithID:self.playlistID];
    if (playlist == nil) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }

    NSArray<SonoraTrack *> *libraryTracks = SonoraLibraryManager.sharedManager.tracks;
    if (libraryTracks.count == 0) {
        libraryTracks = [SonoraLibraryManager.sharedManager reloadTracks];
    }

    NSSet<NSString *> *existingIDs = [NSSet setWithArray:playlist.trackIDs ?: @[]];
    NSMutableArray<SonoraTrack *> *filteredTracks = [NSMutableArray arrayWithCapacity:libraryTracks.count];
    for (SonoraTrack *track in libraryTracks) {
        if (![existingIDs containsObject:track.identifier]) {
            [filteredTracks addObject:track];
        }
    }

    self.availableTracks = [filteredTracks copy];
    [self.selectedTrackIDs removeAllObjects];
    [self.tableView reloadData];
    [self updateAddButtonState];
    [self updateEmptyState];
}

- (void)updateAddButtonState {
    self.navigationItem.rightBarButtonItem.enabled = (self.selectedTrackIDs.count > 0);
}

- (void)updateEmptyState {
    if (self.availableTracks.count > 0) {
        self.tableView.backgroundView = nil;
        return;
    }

    UILabel *label = [[UILabel alloc] init];
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = UIColor.secondaryLabelColor;
    label.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    label.numberOfLines = 2;

    if (SonoraLibraryManager.sharedManager.tracks.count == 0) {
        label.text = @"No tracks in library.";
    } else {
        label.text = @"All tracks are already in this playlist.";
    }

    self.tableView.backgroundView = label;
}

- (void)addTapped {
    if (self.selectedTrackIDs.count == 0) {
        return;
    }

    NSMutableArray<NSString *> *orderedIDs = [NSMutableArray arrayWithCapacity:self.selectedTrackIDs.count];
    for (SonoraTrack *track in self.availableTracks) {
        if ([self.selectedTrackIDs containsObject:track.identifier]) {
            [orderedIDs addObject:track.identifier];
        }
    }

    BOOL added = [SonoraPlaylistStore.sharedStore addTrackIDs:orderedIDs toPlaylistID:self.playlistID];
    if (!added) {
        SonoraPresentAlert(self, @"Nothing Added", @"Selected tracks are already in this playlist.");
        return;
    }

    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return self.availableTracks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SonoraTrackCell *cell = [tableView dequeueReusableCellWithIdentifier:@"PlaylistAddTrackCell" forIndexPath:indexPath];

    SonoraTrack *track = self.availableTracks[indexPath.row];
    BOOL selected = [self.selectedTrackIDs containsObject:track.identifier];
    [cell configureWithTrack:track isCurrent:selected];
    cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    SonoraTrack *track = self.availableTracks[indexPath.row];
    if ([self.selectedTrackIDs containsObject:track.identifier]) {
        [self.selectedTrackIDs removeObject:track.identifier];
    } else {
        [self.selectedTrackIDs addObject:track.identifier];
    }

    [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    [self updateAddButtonState];
}

@end

#pragma mark - Playlist Cover Picker

@interface SonoraPlaylistCoverPickerViewController () <PHPickerViewControllerDelegate>

@property (nonatomic, copy) NSString *playlistID;
@property (nonatomic, strong) UIImageView *previewView;

@end

@implementation SonoraPlaylistCoverPickerViewController

- (instancetype)initWithPlaylistID:(NSString *)playlistID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _playlistID = [playlistID copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Change Playlist Cover";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    [self setupUI];
    [self reloadPreview];
}

- (void)setupUI {
    UIImageView *previewView = [[UIImageView alloc] init];
    previewView.translatesAutoresizingMaskIntoConstraints = NO;
    previewView.contentMode = UIViewContentModeScaleAspectFill;
    previewView.layer.cornerRadius = 14.0;
    previewView.layer.masksToBounds = YES;
    self.previewView = previewView;

    UIButton *chooseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    chooseButton.translatesAutoresizingMaskIntoConstraints = NO;
    [chooseButton setTitle:@"Choose Image" forState:UIControlStateNormal];
    chooseButton.titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    [chooseButton addTarget:self action:@selector(chooseImageTapped) forControlEvents:UIControlEventTouchUpInside];

    UIButton *autoButton = [UIButton buttonWithType:UIButtonTypeSystem];
    autoButton.translatesAutoresizingMaskIntoConstraints = NO;
    [autoButton setTitle:@"Use Auto Cover" forState:UIControlStateNormal];
    autoButton.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    [autoButton addTarget:self action:@selector(resetAutoCoverTapped) forControlEvents:UIControlEventTouchUpInside];

    UILabel *hintLabel = [[UILabel alloc] init];
    hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    hintLabel.text = @"Select an image from Gallery.\nThis changes playlist cover only.";
    hintLabel.textColor = UIColor.secondaryLabelColor;
    hintLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
    hintLabel.textAlignment = NSTextAlignmentCenter;
    hintLabel.numberOfLines = 2;

    [self.view addSubview:previewView];
    [self.view addSubview:chooseButton];
    [self.view addSubview:autoButton];
    [self.view addSubview:hintLabel];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [previewView.topAnchor constraintEqualToAnchor:safe.topAnchor constant:20.0],
        [previewView.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [previewView.widthAnchor constraintEqualToConstant:220.0],
        [previewView.heightAnchor constraintEqualToConstant:220.0],

        [chooseButton.topAnchor constraintEqualToAnchor:previewView.bottomAnchor constant:20.0],
        [chooseButton.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],

        [autoButton.topAnchor constraintEqualToAnchor:chooseButton.bottomAnchor constant:10.0],
        [autoButton.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],

        [hintLabel.topAnchor constraintEqualToAnchor:autoButton.bottomAnchor constant:16.0],
        [hintLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16.0],
        [hintLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16.0]
    ]];
}

- (void)reloadPreview {
    [SonoraPlaylistStore.sharedStore reloadPlaylists];
    SonoraPlaylist *playlist = [SonoraPlaylistStore.sharedStore playlistWithID:self.playlistID];
    if (playlist == nil) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }

    self.previewView.image = [SonoraPlaylistStore.sharedStore coverForPlaylist:playlist
                                                                       library:SonoraLibraryManager.sharedManager
                                                                          size:CGSizeMake(320.0, 320.0)];
}

- (void)chooseImageTapped {
    PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
    configuration.filter = [PHPickerFilter imagesFilter];
    configuration.selectionLimit = 1;

    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)resetAutoCoverTapped {
    [SonoraPlaylistStore.sharedStore reloadPlaylists];
    SonoraPlaylist *playlist = [SonoraPlaylistStore.sharedStore playlistWithID:self.playlistID];
    if (playlist == nil) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }

    UIImage *autoCover = [self randomAutoCoverImageForPlaylist:playlist];
    BOOL success = [SonoraPlaylistStore.sharedStore setCustomCoverImage:autoCover forPlaylistID:self.playlistID];
    if (!success) {
        SonoraPresentAlert(self, @"Error", @"Could not reset cover.");
        return;
    }
    [self reloadPreview];
}

#pragma mark - PHPickerViewControllerDelegate

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];

    PHPickerResult *result = results.firstObject;
    if (result == nil) {
        return;
    }

    NSItemProvider *provider = result.itemProvider;
    if (![provider canLoadObjectOfClass:UIImage.class]) {
        SonoraPresentAlert(self, @"Error", @"Cannot read this image.");
        return;
    }

    __weak typeof(self) weakSelf = self;
    [provider loadObjectOfClass:UIImage.class
              completionHandler:^(id<NSItemProviderReading>  _Nullable object, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }

            if (error != nil || ![object isKindOfClass:UIImage.class]) {
                SonoraPresentAlert(strongSelf, @"Error", @"Cannot read this image.");
                return;
            }

            UIImage *image = (UIImage *)object;
            BOOL success = [SonoraPlaylistStore.sharedStore setCustomCoverImage:image forPlaylistID:strongSelf.playlistID];
            if (!success) {
                SonoraPresentAlert(strongSelf, @"Error", @"Could not set cover.");
                return;
            }

            [strongSelf reloadPreview];
        });
    }];
}

- (nullable UIImage *)randomAutoCoverImageForPlaylist:(SonoraPlaylist *)playlist {
    if (playlist == nil) {
        return nil;
    }

    if (SonoraLibraryManager.sharedManager.tracks.count == 0) {
        [SonoraLibraryManager.sharedManager reloadTracks];
    }

    NSArray<SonoraTrack *> *playlistTracks = [SonoraPlaylistStore.sharedStore tracksForPlaylist:playlist library:SonoraLibraryManager.sharedManager];
    if (playlistTracks.count == 0) {
        return nil;
    }

    NSMutableArray<SonoraTrack *> *shuffledTracks = [playlistTracks mutableCopy];
    for (NSInteger i = shuffledTracks.count - 1; i > 0; i -= 1) {
        u_int32_t j = arc4random_uniform((u_int32_t)(i + 1));
        [shuffledTracks exchangeObjectAtIndex:i withObjectAtIndex:j];
    }

    NSUInteger limit = MIN((NSUInteger)4, shuffledTracks.count);
    NSMutableArray<NSString *> *randomTrackIDs = [NSMutableArray arrayWithCapacity:limit];
    for (NSUInteger index = 0; index < limit; index += 1) {
        SonoraTrack *track = shuffledTracks[index];
        if (track.identifier.length > 0) {
            [randomTrackIDs addObject:track.identifier];
        }
    }

    if (randomTrackIDs.count == 0) {
        return nil;
    }

    SonoraPlaylist *tempPlaylist = [[SonoraPlaylist alloc] init];
    tempPlaylist.playlistID = @"sonora-auto-cover-temp";
    tempPlaylist.name = playlist.name ?: @"Playlist";
    tempPlaylist.trackIDs = [randomTrackIDs copy];
    tempPlaylist.customCoverFileName = nil;

    return [SonoraPlaylistStore.sharedStore coverForPlaylist:tempPlaylist
                                                     library:SonoraLibraryManager.sharedManager
                                                        size:CGSizeMake(320.0, 320.0)];
}

@end
