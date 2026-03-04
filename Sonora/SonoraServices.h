//
//  SonoraServices.h
//  Sonora
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "SonoraModels.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXTERN NSString * const SonoraPlaybackStateDidChangeNotification;
FOUNDATION_EXTERN NSString * const SonoraPlaybackProgressDidChangeNotification;
FOUNDATION_EXTERN NSString * const SonoraPlaylistsDidChangeNotification;
FOUNDATION_EXTERN NSString * const SonoraFavoritesDidChangeNotification;
FOUNDATION_EXTERN NSString * const SonoraSleepTimerDidChangeNotification;

typedef NS_ENUM(NSInteger, SonoraRepeatMode) {
    SonoraRepeatModeNone = 0,
    SonoraRepeatModeQueue = 1,
    SonoraRepeatModeTrack = 2,
};

@interface SonoraLibraryManager : NSObject

+ (instancetype)sharedManager;

- (NSURL *)musicDirectoryURL;
- (NSString *)filesDropHint;
- (NSArray<SonoraTrack *> *)tracks;
- (NSArray<SonoraTrack *> *)reloadTracks;
- (nullable SonoraTrack *)trackForIdentifier:(NSString *)identifier;
- (BOOL)deleteTrackWithIdentifier:(NSString *)identifier error:(NSError * _Nullable * _Nullable)error;

@end

@interface SonoraPlaylistStore : NSObject

+ (instancetype)sharedStore;

- (NSArray<SonoraPlaylist *> *)playlists;
- (void)reloadPlaylists;
- (nullable SonoraPlaylist *)playlistWithID:(NSString *)playlistID;
- (nullable SonoraPlaylist *)addPlaylistWithName:(NSString *)name
                                    trackIDs:(NSArray<NSString *> *)trackIDs
                                  coverImage:(nullable UIImage *)coverImage;
- (BOOL)renamePlaylistWithID:(NSString *)playlistID newName:(NSString *)newName;
- (BOOL)deletePlaylistWithID:(NSString *)playlistID;
- (BOOL)addTrackIDs:(NSArray<NSString *> *)trackIDs toPlaylistID:(NSString *)playlistID;
- (BOOL)replaceTrackIDs:(NSArray<NSString *> *)trackIDs forPlaylistID:(NSString *)playlistID;
- (BOOL)removeTrackID:(NSString *)trackID fromPlaylistID:(NSString *)playlistID;
- (BOOL)removeTrackIDFromAllPlaylists:(NSString *)trackID;
- (BOOL)setCustomCoverImage:(nullable UIImage *)coverImage forPlaylistID:(NSString *)playlistID;
- (NSArray<SonoraTrack *> *)tracksForPlaylist:(SonoraPlaylist *)playlist
                                  library:(SonoraLibraryManager *)library;
- (UIImage *)coverForPlaylist:(SonoraPlaylist *)playlist
                      library:(SonoraLibraryManager *)library
                         size:(CGSize)size;

@end

@interface SonoraPlaybackManager : NSObject

+ (instancetype)sharedManager;

@property (nonatomic, readonly, nullable) SonoraTrack *currentTrack;
@property (nonatomic, readonly, getter=isPlaying) BOOL playing;
@property (nonatomic, readonly) NSTimeInterval currentTime;
@property (nonatomic, readonly) NSTimeInterval duration;
@property (nonatomic, copy, readonly) NSArray<SonoraTrack *> *currentQueue;
@property (nonatomic, readonly) SonoraRepeatMode repeatMode;
@property (nonatomic, readonly, getter=isShuffleEnabled) BOOL shuffleEnabled;

- (void)playTracks:(NSArray<SonoraTrack *> *)tracks startIndex:(NSInteger)index;
- (void)playTrack:(SonoraTrack *)track;
- (void)togglePlayPause;
- (void)playNext;
- (void)playPrevious;
- (void)seekToTime:(NSTimeInterval)time;

- (void)setShuffleEnabled:(BOOL)enabled;
- (void)toggleShuffleEnabled;
- (SonoraRepeatMode)cycleRepeatMode;
- (nullable SonoraTrack *)predictedNextTrackForSkip;

@end

@interface SonoraPlaybackHistoryStore : NSObject

+ (instancetype)sharedStore;

- (void)recordTrackID:(NSString *)trackID;
- (NSArray<NSString *> *)recentTrackIDsWithLimit:(NSUInteger)limit;
- (NSArray<SonoraTrack *> *)recentTracksWithLibrary:(SonoraLibraryManager *)library
                                          limit:(NSUInteger)limit;

@end

@interface SonoraSleepTimerManager : NSObject

+ (instancetype)sharedManager;

@property (nonatomic, readonly, getter=isActive) BOOL active;
@property (nonatomic, readonly) NSTimeInterval remainingTime;
@property (nonatomic, strong, readonly, nullable) NSDate *fireDate;

- (void)startWithDuration:(NSTimeInterval)duration;
- (void)cancel;

@end

@interface SonoraFavoritesStore : NSObject

+ (instancetype)sharedStore;

- (NSArray<NSString *> *)favoriteTrackIDs;
- (BOOL)isTrackFavoriteByID:(NSString *)trackID;
- (void)setTrackID:(NSString *)trackID favorite:(BOOL)favorite;
- (void)toggleFavoriteForTrackID:(NSString *)trackID;
- (NSArray<SonoraTrack *> *)favoriteTracksWithLibrary:(SonoraLibraryManager *)library;

@end

@interface SonoraTrackAnalyticsStore : NSObject

+ (instancetype)sharedStore;

- (void)recordPlayForTrackID:(NSString *)trackID;
- (void)recordSkipForTrackID:(NSString *)trackID;
- (double)scoreForTrackID:(NSString *)trackID;
- (NSDictionary<NSString *, NSDictionary<NSString *, NSNumber *> *> *)analyticsByTrackIDForTrackIDs:(NSArray<NSString *> *)trackIDs;
- (NSArray<SonoraTrack *> *)tracksSortedByAffinity:(NSArray<SonoraTrack *> *)tracks;

@end

@interface SonoraArtworkAccentColorService : NSObject

+ (UIColor *)dominantAccentColorForImage:(nullable UIImage *)image
                                fallback:(UIColor *)fallbackColor;

@end

NS_ASSUME_NONNULL_END
