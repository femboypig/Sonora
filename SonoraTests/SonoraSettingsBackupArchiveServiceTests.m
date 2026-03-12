@import XCTest;

#import "SonoraSettingsBackupArchiveService.h"

static UIImage *SonoraTestSolidImage(void) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(4.0, 4.0)];
    return [renderer imageWithActions:^(__unused UIGraphicsImageRendererContext * _Nonnull rendererContext) {
        [[UIColor colorWithRed:0.23 green:0.51 blue:0.91 alpha:1.0] setFill];
        UIRectFill(CGRectMake(0.0, 0.0, 4.0, 4.0));
    }];
}

static NSString *SonoraTestAudioMarker(NSData *data) {
    NSString *marker = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return marker ?: @"";
}

@interface SonoraBackupTestLibraryManager : NSObject <SonoraBackupLibraryManaging>

@property (nonatomic, strong) NSURL *musicDirectoryURL;
@property (nonatomic, copy) NSArray<SonoraTrack *> *currentTracks;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *trackIDByAudioMarker;

- (instancetype)initWithMusicDirectoryURL:(NSURL *)musicDirectoryURL
                     trackIDByAudioMarker:(NSDictionary<NSString *, NSString *> *)trackIDByAudioMarker;

@end

@implementation SonoraBackupTestLibraryManager

- (instancetype)initWithMusicDirectoryURL:(NSURL *)musicDirectoryURL
                     trackIDByAudioMarker:(NSDictionary<NSString *,NSString *> *)trackIDByAudioMarker {
    self = [super init];
    if (self != nil) {
        _musicDirectoryURL = musicDirectoryURL;
        _currentTracks = @[];
        _trackIDByAudioMarker = trackIDByAudioMarker ?: @{};
    }
    return self;
}

- (NSArray<SonoraTrack *> *)tracks {
    return self.currentTracks ?: @[];
}

- (NSArray<SonoraTrack *> *)reloadTracks {
    NSArray<NSURL *> *fileURLs = [NSFileManager.defaultManager contentsOfDirectoryAtURL:self.musicDirectoryURL
                                                             includingPropertiesForKeys:nil
                                                                                options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                  error:nil] ?: @[];
    NSMutableArray<SonoraTrack *> *tracks = [NSMutableArray arrayWithCapacity:fileURLs.count];
    for (NSURL *fileURL in fileURLs) {
        NSData *data = [NSData dataWithContentsOfURL:fileURL options:0 error:nil];
        NSString *audioMarker = SonoraTestAudioMarker(data);
        SonoraTrack *track = [[SonoraTrack alloc] init];
        track.fileName = fileURL.lastPathComponent ?: @"";
        track.identifier = self.trackIDByAudioMarker[audioMarker] ?: [NSString stringWithFormat:@"track:%@", track.fileName.lowercaseString];
        track.title = audioMarker.length > 0 ? audioMarker : track.fileName;
        track.artist = @"Test Artist";
        track.duration = 1.0;
        track.url = fileURL;
        track.artwork = SonoraTestSolidImage();
        [tracks addObject:track];
    }
    self.currentTracks = tracks.copy;
    return self.currentTracks;
}

@end

@interface SonoraBackupTestPlaylistStore : NSObject <SonoraBackupPlaylistStoring>

@property (nonatomic, strong) NSMutableArray<SonoraPlaylist *> *mutablePlaylists;

- (instancetype)initWithPlaylists:(NSArray<SonoraPlaylist *> *)playlists;

@end

@implementation SonoraBackupTestPlaylistStore

- (instancetype)initWithPlaylists:(NSArray<SonoraPlaylist *> *)playlists {
    self = [super init];
    if (self != nil) {
        _mutablePlaylists = [playlists mutableCopy] ?: [NSMutableArray array];
    }
    return self;
}

- (NSArray<SonoraPlaylist *> *)playlists {
    return self.mutablePlaylists.copy;
}

- (nullable SonoraPlaylist *)addPlaylistWithName:(NSString *)name
                                        trackIDs:(NSArray<NSString *> *)trackIDs
                                      coverImage:(__unused UIImage *)coverImage {
    SonoraPlaylist *playlist = [[SonoraPlaylist alloc] init];
    playlist.playlistID = [NSString stringWithFormat:@"playlist-%lu", (unsigned long)self.mutablePlaylists.count + 1];
    playlist.name = name ?: @"Playlist";
    playlist.trackIDs = trackIDs ?: @[];
    [self.mutablePlaylists addObject:playlist];
    return playlist;
}

- (BOOL)deletePlaylistWithID:(NSString *)playlistID {
    NSIndexSet *indexes = [self.mutablePlaylists indexesOfObjectsPassingTest:^BOOL(SonoraPlaylist * _Nonnull playlist, __unused NSUInteger idx, __unused BOOL * _Nonnull stop) {
        return [playlist.playlistID isEqualToString:playlistID];
    }];
    if (indexes.count == 0) {
        return NO;
    }
    [self.mutablePlaylists removeObjectsAtIndexes:indexes];
    return YES;
}

@end

@interface SonoraBackupTestFavoritesStore : NSObject <SonoraBackupFavoritesStoring>

@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *favoriteIDs;

- (instancetype)initWithFavoriteIDs:(NSArray<NSString *> *)favoriteIDs;

@end

@implementation SonoraBackupTestFavoritesStore

- (instancetype)initWithFavoriteIDs:(NSArray<NSString *> *)favoriteIDs {
    self = [super init];
    if (self != nil) {
        _favoriteIDs = [NSMutableOrderedSet orderedSetWithArray:favoriteIDs ?: @[]];
    }
    return self;
}

- (NSArray<NSString *> *)favoriteTrackIDs {
    return self.favoriteIDs.array ?: @[];
}

- (void)setTrackID:(NSString *)trackID favorite:(BOOL)favorite {
    if (trackID.length == 0) {
        return;
    }
    if (favorite) {
        [self.favoriteIDs addObject:trackID];
    } else {
        [self.favoriteIDs removeObject:trackID];
    }
}

@end

@interface SonoraSettingsBackupArchiveServiceTests : XCTestCase

@property (nonatomic, strong) NSURL *temporaryRootURL;

@end

@implementation SonoraSettingsBackupArchiveServiceTests

- (void)setUp {
    [super setUp];
    NSString *directoryName = [NSString stringWithFormat:@"SonoraSettingsBackupArchiveServiceTests-%@", NSUUID.UUID.UUIDString.lowercaseString];
    self.temporaryRootURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:directoryName] isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:self.temporaryRootURL
                          withIntermediateDirectories:YES
                                           attributes:nil
                                                error:nil];
}

- (void)tearDown {
    [NSFileManager.defaultManager removeItemAtURL:self.temporaryRootURL error:nil];
    self.temporaryRootURL = nil;
    [super tearDown];
}

- (void)testBackupArchiveRoundTripRestoresTracksPlaylistsFavoritesAndSettings {
    NSURL *sourceMusicURL = [self createDirectoryNamed:@"source-music"];
    NSURL *sourceDocumentsURL = [self createDirectoryNamed:@"source-documents"];
    NSURL *sourceCoversURL = [sourceDocumentsURL URLByAppendingPathComponent:@"PlaylistCovers" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:sourceCoversURL withIntermediateDirectories:YES attributes:nil error:nil];

    NSURL *alphaURL = [self writeAudioMarker:@"alpha-audio" named:@"alpha.mp3" inDirectory:sourceMusicURL];
    NSURL *betaURL = [self writeAudioMarker:@"beta-audio" named:@"beta.m4a" inDirectory:sourceMusicURL];
    NSURL *coverURL = [sourceCoversURL URLByAppendingPathComponent:@"daily.png"];
    [UIImagePNGRepresentation(SonoraTestSolidImage()) writeToURL:coverURL atomically:YES];

    SonoraTrack *alphaTrack = [self trackWithIdentifier:@"local-alpha" title:@"Alpha" artist:@"A" fileURL:alphaURL];
    SonoraTrack *betaTrack = [self trackWithIdentifier:@"local-beta" title:@"Beta" artist:@"B" fileURL:betaURL];
    SonoraPlaylist *playlist = [[SonoraPlaylist alloc] init];
    playlist.playlistID = @"playlist-source";
    playlist.name = @"Daily Mix";
    playlist.trackIDs = @[@"local-alpha", @"local-beta"];
    playlist.customCoverFileName = @"daily.png";

    SonoraBackupTestLibraryManager *sourceLibrary = [[SonoraBackupTestLibraryManager alloc] initWithMusicDirectoryURL:sourceMusicURL
                                                                                                    trackIDByAudioMarker:@{}];
    sourceLibrary.currentTracks = @[alphaTrack, betaTrack];
    SonoraBackupTestPlaylistStore *sourcePlaylistStore = [[SonoraBackupTestPlaylistStore alloc] initWithPlaylists:@[playlist]];
    SonoraBackupTestFavoritesStore *sourceFavoritesStore = [[SonoraBackupTestFavoritesStore alloc] initWithFavoriteIDs:@[@"local-beta"]];
    NSUserDefaults *sourceDefaults = [[NSUserDefaults alloc] initWithSuiteName:[NSString stringWithFormat:@"SonoraSettingsBackupArchiveServiceTests.source.%@", NSUUID.UUID.UUIDString.lowercaseString]];

    SonoraSettingsBackupArchiveService *sourceService = [[SonoraSettingsBackupArchiveService alloc] initWithLibraryManager:sourceLibrary
                                                                                                               playlistStore:sourcePlaylistStore
                                                                                                              favoritesStore:sourceFavoritesStore
                                                                                                                    defaults:sourceDefaults
                                                                                                                documentsURL:sourceDocumentsURL];

    NSDictionary<NSString *, id> *settings = @{
        @"accentHex": @"#ff3300",
        @"cacheOnlinePlaylistTracks": @YES
    };
    NSError *exportError = nil;
    NSData *archiveData = [sourceService backupArchiveDataWithSettings:settings error:&exportError];
    XCTAssertNotNil(archiveData);
    XCTAssertNil(exportError);

    NSURL *archiveURL = [self.temporaryRootURL URLByAppendingPathComponent:@"backup.sonoraarc"];
    XCTAssertTrue([archiveData writeToURL:archiveURL atomically:YES]);

    NSURL *targetMusicURL = [self createDirectoryNamed:@"target-music"];
    NSURL *targetDocumentsURL = [self createDirectoryNamed:@"target-documents"];
    [self writeAudioMarker:@"old-audio" named:@"old.mp3" inDirectory:targetMusicURL];

    SonoraBackupTestLibraryManager *targetLibrary = [[SonoraBackupTestLibraryManager alloc] initWithMusicDirectoryURL:targetMusicURL
                                                                                                    trackIDByAudioMarker:@{
                                                                                                        @"alpha-audio": @"imported-alpha",
                                                                                                        @"beta-audio": @"imported-beta",
                                                                                                        @"old-audio": @"old-track"
                                                                                                    }];
    [targetLibrary reloadTracks];

    SonoraPlaylist *stalePlaylist = [[SonoraPlaylist alloc] init];
    stalePlaylist.playlistID = @"playlist-old";
    stalePlaylist.name = @"Old";
    stalePlaylist.trackIDs = @[@"old-track"];
    SonoraBackupTestPlaylistStore *targetPlaylistStore = [[SonoraBackupTestPlaylistStore alloc] initWithPlaylists:@[stalePlaylist]];
    SonoraBackupTestFavoritesStore *targetFavoritesStore = [[SonoraBackupTestFavoritesStore alloc] initWithFavoriteIDs:@[@"old-track"]];
    NSUserDefaults *targetDefaults = [[NSUserDefaults alloc] initWithSuiteName:[NSString stringWithFormat:@"SonoraSettingsBackupArchiveServiceTests.target.%@", NSUUID.UUID.UUIDString.lowercaseString]];

    SonoraSettingsBackupArchiveService *targetService = [[SonoraSettingsBackupArchiveService alloc] initWithLibraryManager:targetLibrary
                                                                                                               playlistStore:targetPlaylistStore
                                                                                                              favoritesStore:targetFavoritesStore
                                                                                                                    defaults:targetDefaults
                                                                                                                documentsURL:targetDocumentsURL];

    NSDictionary<NSString *, id> *importedSettings = nil;
    NSError *importError = nil;
    BOOL imported = [targetService importBackupArchiveFromURL:archiveURL importedSettings:&importedSettings error:&importError];

    XCTAssertTrue(imported);
    XCTAssertNil(importError);
    XCTAssertEqualObjects(importedSettings[@"accentHex"], @"#ff3300");
    XCTAssertEqualObjects(importedSettings[@"cacheOnlinePlaylistTracks"], @YES);

    NSArray<SonoraTrack *> *importedTracks = [targetLibrary reloadTracks];
    XCTAssertEqual(importedTracks.count, 2);

    NSArray<NSString *> *favoriteIDs = [targetFavoritesStore favoriteTrackIDs];
    XCTAssertEqualObjects(favoriteIDs, (@[@"imported-beta"]));

    NSArray<SonoraPlaylist *> *restoredPlaylists = [targetPlaylistStore playlists];
    XCTAssertEqual(restoredPlaylists.count, 1);
    XCTAssertEqualObjects(restoredPlaylists.firstObject.name, @"Daily Mix");
    XCTAssertEqualObjects(restoredPlaylists.firstObject.trackIDs, (@[@"imported-alpha", @"imported-beta"]));

    NSArray<NSURL *> *targetFiles = [NSFileManager.defaultManager contentsOfDirectoryAtURL:targetMusicURL
                                                                includingPropertiesForKeys:nil
                                                                                   options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                     error:nil];
    XCTAssertEqual(targetFiles.count, 2);
    XCTAssertFalse([NSFileManager.defaultManager fileExistsAtPath:[targetMusicURL URLByAppendingPathComponent:@"old.mp3"].path]);
}

- (SonoraTrack *)trackWithIdentifier:(NSString *)identifier
                               title:(NSString *)title
                              artist:(NSString *)artist
                             fileURL:(NSURL *)fileURL {
    SonoraTrack *track = [[SonoraTrack alloc] init];
    track.identifier = identifier;
    track.title = title;
    track.artist = artist;
    track.fileName = fileURL.lastPathComponent ?: @"";
    track.url = fileURL;
    track.duration = 1.0;
    track.artwork = SonoraTestSolidImage();
    return track;
}

- (NSURL *)createDirectoryNamed:(NSString *)directoryName {
    NSURL *directoryURL = [self.temporaryRootURL URLByAppendingPathComponent:directoryName isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:directoryURL withIntermediateDirectories:YES attributes:nil error:nil];
    return directoryURL;
}

- (NSURL *)writeAudioMarker:(NSString *)audioMarker named:(NSString *)fileName inDirectory:(NSURL *)directoryURL {
    NSURL *fileURL = [directoryURL URLByAppendingPathComponent:fileName];
    NSData *data = [audioMarker dataUsingEncoding:NSUTF8StringEncoding];
    [data writeToURL:fileURL atomically:YES];
    return fileURL;
}

@end
