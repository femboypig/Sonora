@import XCTest;

#import "SonoraSharedPlaylists.h"

static UIImage *SonoraSharedPlaylistTestImage(void) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(6.0, 6.0)];
    return [renderer imageWithActions:^(__unused UIGraphicsImageRendererContext * _Nonnull rendererContext) {
        [[UIColor colorWithRed:0.82 green:0.18 blue:0.26 alpha:1.0] setFill];
        UIRectFill(CGRectMake(0.0, 0.0, 6.0, 6.0));
    }];
}

@interface SonoraSharedPlaylistStoreTests : XCTestCase

@property (nonatomic, strong) NSURL *temporaryRootURL;
@property (nonatomic, strong) NSUserDefaults *defaults;
@property (nonatomic, copy) NSString *defaultsSuiteName;
@property (nonatomic, strong) NSURL *storageDirectoryURL;

@end

@implementation SonoraSharedPlaylistStoreTests

- (void)setUp {
    [super setUp];
    NSString *directoryName = [NSString stringWithFormat:@"SonoraSharedPlaylistStoreTests-%@", NSUUID.UUID.UUIDString.lowercaseString];
    self.temporaryRootURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:directoryName] isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:self.temporaryRootURL
                          withIntermediateDirectories:YES
                                           attributes:nil
                                                error:nil];
    self.storageDirectoryURL = [self.temporaryRootURL URLByAppendingPathComponent:@"SharedPlaylistStorage" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:self.storageDirectoryURL withIntermediateDirectories:YES attributes:nil error:nil];
    self.defaultsSuiteName = [NSString stringWithFormat:@"SonoraSharedPlaylistStoreTests.%@", NSUUID.UUID.UUIDString.lowercaseString];
    self.defaults = [[NSUserDefaults alloc] initWithSuiteName:self.defaultsSuiteName];
}

- (void)tearDown {
    [self.defaults removePersistentDomainForName:self.defaultsSuiteName];
    self.defaultsSuiteName = nil;
    self.defaults = nil;
    [NSFileManager.defaultManager removeItemAtURL:self.temporaryRootURL error:nil];
    self.storageDirectoryURL = nil;
    self.temporaryRootURL = nil;
    [super tearDown];
}

- (void)testSnapshotPersistenceRoundTripAndRemoval {
    SonoraSharedPlaylistStore *store = [[SonoraSharedPlaylistStore alloc] initWithUserDefaults:self.defaults
                                                                            storageDirectoryURL:self.storageDirectoryURL];

    NSURL *audioURL = [self.temporaryRootURL URLByAppendingPathComponent:@"shared-track.mp3"];
    [@"shared-audio" writeToURL:audioURL atomically:YES encoding:NSUTF8StringEncoding error:nil];

    SonoraTrack *track = [[SonoraTrack alloc] init];
    track.identifier = @"shared:track-1";
    track.title = @"Shared Track";
    track.artist = @"Shared Artist";
    track.fileName = audioURL.lastPathComponent ?: @"";
    track.url = audioURL;
    track.duration = 42.0;
    track.artwork = SonoraSharedPlaylistTestImage();

    SonoraSharedPlaylistSnapshot *snapshot = [[SonoraSharedPlaylistSnapshot alloc] init];
    snapshot.remoteID = @"remote-1";
    snapshot.playlistID = SonoraSharedPlaylistSyntheticID(snapshot.remoteID);
    snapshot.name = @"Shared Mix";
    snapshot.shareURL = @"https://example.com/shared/remote-1";
    snapshot.sourceBaseURL = @"https://example.com";
    snapshot.contentSHA256 = @"abc123";
    snapshot.coverURL = @"https://example.com/cover.jpg";
    snapshot.coverImage = SonoraSharedPlaylistTestImage();
    snapshot.tracks = @[track];
    snapshot.trackArtworkURLByTrackID = @{ track.identifier : @"https://example.com/artwork.jpg" };
    snapshot.trackRemoteFileURLByTrackID = @{ track.identifier : @"https://cdn.example.com/shared-track.mp3" };

    [store saveSnapshot:snapshot];

    SonoraSharedPlaylistStore *reloadedStore = [[SonoraSharedPlaylistStore alloc] initWithUserDefaults:self.defaults
                                                                                    storageDirectoryURL:self.storageDirectoryURL];
    NSArray<SonoraPlaylist *> *likedPlaylists = [reloadedStore likedPlaylists];
    XCTAssertEqual(likedPlaylists.count, 1);
    XCTAssertEqualObjects(likedPlaylists.firstObject.playlistID, snapshot.playlistID);
    XCTAssertEqualObjects(likedPlaylists.firstObject.name, @"Shared Mix");

    SonoraSharedPlaylistSnapshot *loadedSnapshot = [reloadedStore snapshotForPlaylistID:snapshot.playlistID];
    XCTAssertNotNil(loadedSnapshot);
    XCTAssertEqualObjects(loadedSnapshot.remoteID, @"remote-1");
    XCTAssertEqualObjects(loadedSnapshot.shareURL, @"https://example.com/shared/remote-1");
    XCTAssertEqualObjects(loadedSnapshot.contentSHA256, @"abc123");
    XCTAssertNotNil(loadedSnapshot.coverImage);
    XCTAssertEqual(loadedSnapshot.tracks.count, 1);
    XCTAssertEqualObjects(loadedSnapshot.tracks.firstObject.title, @"Shared Track");
    XCTAssertEqualObjects(loadedSnapshot.trackArtworkURLByTrackID[track.identifier], @"https://example.com/artwork.jpg");
    XCTAssertEqualObjects(loadedSnapshot.trackRemoteFileURLByTrackID[track.identifier], @"https://cdn.example.com/shared-track.mp3");
    XCTAssertNotNil(loadedSnapshot.tracks.firstObject.artwork);

    [reloadedStore removeSnapshotForPlaylistID:snapshot.playlistID];

    XCTAssertNil([reloadedStore snapshotForPlaylistID:snapshot.playlistID]);
    XCTAssertEqual(reloadedStore.likedPlaylists.count, 0);
}

@end
