#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "SonoraServices.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXTERN NSString *SonoraSharedPlaylistSyntheticID(NSString *remoteID);
FOUNDATION_EXTERN NSString *SonoraSharedPlaylistBackendBaseURLString(void);
FOUNDATION_EXTERN NSString *SonoraSharedPlaylistStorageDirectoryPath(void);
FOUNDATION_EXTERN NSString *SonoraSharedPlaylistAudioCacheDirectoryPath(void);
FOUNDATION_EXTERN NSString *SonoraSharedPlaylistNormalizeText(NSString *value);

typedef void (^SonoraSharedPlaylistDataCompletion)(NSData * _Nullable data,
                                                   NSURLResponse * _Nullable response,
                                                   NSError * _Nullable error);
typedef void (^SonoraSharedPlaylistRequestCompletion)(NSData * _Nullable data,
                                                      NSHTTPURLResponse * _Nullable response,
                                                      NSError * _Nullable error);
typedef void (^SonoraSharedPlaylistDownloadedFileCompletion)(NSURL * _Nullable fileURL,
                                                             NSError * _Nullable error);
typedef void (^SonoraSharedPlaylistWarmCompletion)(BOOL didPersistUpdates);

FOUNDATION_EXTERN void SonoraSharedPlaylistDataFromURL(NSURL *url,
                                                       NSTimeInterval timeout,
                                                       SonoraSharedPlaylistDataCompletion completion);
FOUNDATION_EXTERN void SonoraSharedPlaylistPerformRequest(NSURLRequest *request,
                                                          NSTimeInterval timeout,
                                                          SonoraSharedPlaylistRequestCompletion completion);
FOUNDATION_EXTERN void SonoraSharedPlaylistUploadFileRequest(NSURLRequest *request,
                                                             NSURL *fileURL,
                                                             NSTimeInterval timeout,
                                                             SonoraSharedPlaylistRequestCompletion completion);
FOUNDATION_EXTERN void SonoraSharedPlaylistDownloadedFileURL(NSString *urlString,
                                                             NSString *suggestedBaseName,
                                                             SonoraSharedPlaylistDownloadedFileCompletion completion);

@interface SonoraSharedPlaylistSnapshot : NSObject

@property (nonatomic, copy) NSString *playlistID;
@property (nonatomic, copy) NSString *remoteID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *shareURL;
@property (nonatomic, copy) NSString *sourceBaseURL;
@property (nonatomic, copy) NSString *contentSHA256;
@property (nonatomic, copy) NSString *coverURL;
@property (nonatomic, strong, nullable) UIImage *coverImage;
@property (nonatomic, copy) NSArray<SonoraTrack *> *tracks;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *trackArtworkURLByTrackID;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *trackRemoteFileURLByTrackID;

@end

FOUNDATION_EXTERN SonoraSharedPlaylistSnapshot * _Nullable SonoraSharedPlaylistSnapshotFromPayload(NSDictionary<NSString *, id> *payload,
                                                                                                   NSString *fallbackBaseURL);
FOUNDATION_EXTERN void SonoraSharedPlaylistPerformWithoutDidChangeNotification(dispatch_block_t block);
FOUNDATION_EXTERN void SonoraSharedPlaylistWarmPersistentCache(SonoraSharedPlaylistSnapshot *snapshot,
                                                               SonoraSharedPlaylistWarmCompletion _Nullable completion);

@interface SonoraSharedPlaylistStore : NSObject

+ (instancetype)sharedStore;
- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults
                 storageDirectoryURL:(NSURL *)storageDirectoryURL NS_DESIGNATED_INITIALIZER;
- (NSArray<SonoraPlaylist *> *)likedPlaylists;
- (nullable SonoraSharedPlaylistSnapshot *)snapshotForPlaylistID:(NSString *)playlistID;
- (BOOL)isSnapshotLikedForPlaylistID:(NSString *)playlistID;
- (void)saveSnapshot:(SonoraSharedPlaylistSnapshot *)snapshot;
- (void)removeSnapshotForPlaylistID:(NSString *)playlistID;
- (void)refreshAllPersistentCachesIfNeeded;

@end

NS_ASSUME_NONNULL_END
