//
//  M2Services.h
//  M2
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "M2Models.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXTERN NSString * const M2PlaybackStateDidChangeNotification;
FOUNDATION_EXTERN NSString * const M2PlaybackProgressDidChangeNotification;
FOUNDATION_EXTERN NSString * const M2PlaylistsDidChangeNotification;
FOUNDATION_EXTERN NSString * const M2FavoritesDidChangeNotification;
FOUNDATION_EXTERN NSString * const M2SleepTimerDidChangeNotification;

typedef NS_ENUM(NSInteger, M2RepeatMode) {
    M2RepeatModeNone = 0,
    M2RepeatModeQueue = 1,
    M2RepeatModeTrack = 2,
};

@interface M2LibraryManager : NSObject

+ (instancetype)sharedManager;

- (NSURL *)musicDirectoryURL;
- (NSString *)filesDropHint;
- (NSArray<M2Track *> *)tracks;
- (NSArray<M2Track *> *)reloadTracks;
- (nullable M2Track *)trackForIdentifier:(NSString *)identifier;
- (BOOL)deleteTrackWithIdentifier:(NSString *)identifier error:(NSError * _Nullable * _Nullable)error;

@end

@interface M2PlaylistStore : NSObject

+ (instancetype)sharedStore;

- (NSArray<M2Playlist *> *)playlists;
- (void)reloadPlaylists;
- (nullable M2Playlist *)playlistWithID:(NSString *)playlistID;
- (nullable M2Playlist *)addPlaylistWithName:(NSString *)name
                                    trackIDs:(NSArray<NSString *> *)trackIDs
                                  coverImage:(nullable UIImage *)coverImage;
- (BOOL)renamePlaylistWithID:(NSString *)playlistID newName:(NSString *)newName;
- (BOOL)deletePlaylistWithID:(NSString *)playlistID;
- (BOOL)addTrackIDs:(NSArray<NSString *> *)trackIDs toPlaylistID:(NSString *)playlistID;
- (BOOL)replaceTrackIDs:(NSArray<NSString *> *)trackIDs forPlaylistID:(NSString *)playlistID;
- (BOOL)removeTrackID:(NSString *)trackID fromPlaylistID:(NSString *)playlistID;
- (BOOL)removeTrackIDFromAllPlaylists:(NSString *)trackID;
- (BOOL)setCustomCoverImage:(nullable UIImage *)coverImage forPlaylistID:(NSString *)playlistID;
- (NSArray<M2Track *> *)tracksForPlaylist:(M2Playlist *)playlist
                                  library:(M2LibraryManager *)library;
- (UIImage *)coverForPlaylist:(M2Playlist *)playlist
                      library:(M2LibraryManager *)library
                         size:(CGSize)size;

@end

@interface M2PlaybackManager : NSObject

+ (instancetype)sharedManager;

@property (nonatomic, readonly, nullable) M2Track *currentTrack;
@property (nonatomic, readonly, getter=isPlaying) BOOL playing;
@property (nonatomic, readonly) NSTimeInterval currentTime;
@property (nonatomic, readonly) NSTimeInterval duration;
@property (nonatomic, copy, readonly) NSArray<M2Track *> *currentQueue;
@property (nonatomic, readonly) M2RepeatMode repeatMode;
@property (nonatomic, readonly, getter=isShuffleEnabled) BOOL shuffleEnabled;

- (void)playTracks:(NSArray<M2Track *> *)tracks startIndex:(NSInteger)index;
- (void)playTrack:(M2Track *)track;
- (void)togglePlayPause;
- (void)playNext;
- (void)playPrevious;
- (void)seekToTime:(NSTimeInterval)time;

- (void)setShuffleEnabled:(BOOL)enabled;
- (void)toggleShuffleEnabled;
- (M2RepeatMode)cycleRepeatMode;
- (nullable M2Track *)predictedNextTrackForSkip;

@end

@interface M2PlaybackHistoryStore : NSObject

+ (instancetype)sharedStore;

- (void)recordTrackID:(NSString *)trackID;
- (NSArray<NSString *> *)recentTrackIDsWithLimit:(NSUInteger)limit;
- (NSArray<M2Track *> *)recentTracksWithLibrary:(M2LibraryManager *)library
                                          limit:(NSUInteger)limit;

@end

@interface M2SleepTimerManager : NSObject

+ (instancetype)sharedManager;

@property (nonatomic, readonly, getter=isActive) BOOL active;
@property (nonatomic, readonly) NSTimeInterval remainingTime;
@property (nonatomic, strong, readonly, nullable) NSDate *fireDate;

- (void)startWithDuration:(NSTimeInterval)duration;
- (void)cancel;

@end

@interface M2FavoritesStore : NSObject

+ (instancetype)sharedStore;

- (NSArray<NSString *> *)favoriteTrackIDs;
- (BOOL)isTrackFavoriteByID:(NSString *)trackID;
- (void)setTrackID:(NSString *)trackID favorite:(BOOL)favorite;
- (void)toggleFavoriteForTrackID:(NSString *)trackID;
- (NSArray<M2Track *> *)favoriteTracksWithLibrary:(M2LibraryManager *)library;

@end

@interface M2TrackAnalyticsStore : NSObject

+ (instancetype)sharedStore;

- (void)recordPlayForTrackID:(NSString *)trackID;
- (void)recordSkipForTrackID:(NSString *)trackID;
- (double)scoreForTrackID:(NSString *)trackID;
- (NSDictionary<NSString *, NSDictionary<NSString *, NSNumber *> *> *)analyticsByTrackIDForTrackIDs:(NSArray<NSString *> *)trackIDs;
- (NSArray<M2Track *> *)tracksSortedByAffinity:(NSArray<M2Track *> *)tracks;

@end

@interface M2ArtworkAccentColorService : NSObject

+ (UIColor *)dominantAccentColorForImage:(nullable UIImage *)image
                                fallback:(UIColor *)fallbackColor;

@end

NS_ASSUME_NONNULL_END
