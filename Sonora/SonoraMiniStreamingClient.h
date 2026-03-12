#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SonoraMiniStreamingTrack : NSObject

@property (nonatomic, copy) NSString *trackID;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *artists;
@property (nonatomic, copy) NSString *spotifyURL;
@property (nonatomic, copy) NSString *artworkURL;
@property (nonatomic, assign) NSTimeInterval duration;

@end

@interface SonoraMiniStreamingArtist : NSObject

@property (nonatomic, copy) NSString *artistID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *artworkURL;

@end

typedef void (^SonoraMiniStreamingSearchCompletion)(NSArray<SonoraMiniStreamingTrack *> *tracks, NSError * _Nullable error);
typedef void (^SonoraMiniStreamingArtistSearchCompletion)(NSArray<SonoraMiniStreamingArtist *> *artists, NSError * _Nullable error);
typedef void (^SonoraMiniStreamingResolveCompletion)(NSDictionary<NSString *, id> * _Nullable payload, NSError * _Nullable error);

@interface SonoraMiniStreamingClient : NSObject

@property (nonatomic, copy) NSString *backendBaseURL;
@property (nonatomic, copy) NSString *spotifyClientID;
@property (nonatomic, copy) NSString *spotifyClientSecret;
@property (nonatomic, copy) NSString *rapidAPIHost;
@property (nonatomic, copy) NSString *rapidAPIKey;
@property (nonatomic, copy) NSString *brokerRapidAPIHost;
@property (nonatomic, copy) NSString *brokerRapidAPIKey;
@property (nonatomic, assign) NSTimeInterval brokerCredentialFetchedAt;
@property (nonatomic, assign) BOOL artistsSectionEnabled;
@property (nonatomic, copy) NSString *spotifyAccessToken;
@property (nonatomic, strong, nullable) NSDate *spotifyTokenExpiresAt;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong, nullable) NSURLSessionDataTask *currentSearchTask;
@property (nonatomic, strong, nullable) NSURLSessionDataTask *currentArtistSearchTask;
@property (nonatomic, strong, nullable) NSURLSessionDataTask *currentArtistTopTracksTask;

- (BOOL)isConfigured;
- (void)searchTracks:(NSString *)query
               limit:(NSUInteger)limit
          completion:(SonoraMiniStreamingSearchCompletion)completion;
- (void)searchArtists:(NSString *)query
                limit:(NSUInteger)limit
           completion:(SonoraMiniStreamingArtistSearchCompletion)completion;
- (void)fetchTopTracksForArtistID:(NSString *)artistID
                            limit:(NSUInteger)limit
                       completion:(SonoraMiniStreamingSearchCompletion)completion;
- (void)resolveDownloadForTrackID:(NSString *)trackID
                       completion:(SonoraMiniStreamingResolveCompletion)completion;

@end

NS_ASSUME_NONNULL_END
