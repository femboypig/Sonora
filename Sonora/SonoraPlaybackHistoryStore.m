//
//  SonoraPlaybackHistoryStore.m
//  Sonora
//

#import "SonoraServices.h"

static NSString * const kPlaybackHistoryDefaultsKey = @"sonora_playback_history_v1";
static NSUInteger const kPlaybackHistoryMaxEntries = 160;

@interface SonoraPlaybackHistoryStore ()

@property (nonatomic, strong) NSMutableArray<NSString *> *trackIDs;

@end

@implementation SonoraPlaybackHistoryStore

+ (instancetype)sharedStore {
    static SonoraPlaybackHistoryStore *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = [[SonoraPlaybackHistoryStore alloc] init];
    });
    return store;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _trackIDs = [NSMutableArray array];
        [self loadFromDefaults];
    }
    return self;
}

- (void)recordTrackID:(NSString *)trackID {
    if (![trackID isKindOfClass:NSString.class] || trackID.length == 0) {
        return;
    }

    @synchronized (self) {
        NSUInteger existingIndex = [self.trackIDs indexOfObject:trackID];
        if (existingIndex != NSNotFound) {
            [self.trackIDs removeObjectAtIndex:existingIndex];
        }
        [self.trackIDs insertObject:trackID atIndex:0];

        if (self.trackIDs.count > kPlaybackHistoryMaxEntries) {
            NSRange trimRange = NSMakeRange(kPlaybackHistoryMaxEntries, self.trackIDs.count - kPlaybackHistoryMaxEntries);
            [self.trackIDs removeObjectsInRange:trimRange];
        }

        [self persistToDefaults];
    }
}

- (NSArray<NSString *> *)recentTrackIDsWithLimit:(NSUInteger)limit {
    @synchronized (self) {
        if (self.trackIDs.count == 0) {
            return @[];
        }

        NSUInteger resolvedLimit = limit == 0 ? self.trackIDs.count : MIN(limit, self.trackIDs.count);
        return [self.trackIDs subarrayWithRange:NSMakeRange(0, resolvedLimit)];
    }
}

- (NSArray<SonoraTrack *> *)recentTracksWithLibrary:(SonoraLibraryManager *)library
                                              limit:(NSUInteger)limit {
    if (library == nil) {
        return @[];
    }

    NSArray<NSString *> *trackIDs = [self recentTrackIDsWithLimit:limit];
    if (trackIDs.count == 0) {
        return @[];
    }

    NSMutableArray<SonoraTrack *> *tracks = [NSMutableArray arrayWithCapacity:trackIDs.count];
    for (NSString *trackID in trackIDs) {
        SonoraTrack *track = [library trackForIdentifier:trackID];
        if (track != nil) {
            [tracks addObject:track];
        }
    }
    return [tracks copy];
}

- (void)loadFromDefaults {
    NSArray *stored = [NSUserDefaults.standardUserDefaults arrayForKey:kPlaybackHistoryDefaultsKey];
    [self.trackIDs removeAllObjects];

    if (![stored isKindOfClass:NSArray.class]) {
        return;
    }

    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id value in stored) {
        if (![value isKindOfClass:NSString.class]) {
            continue;
        }
        NSString *trackID = (NSString *)value;
        if (trackID.length == 0 || [seen containsObject:trackID]) {
            continue;
        }
        [seen addObject:trackID];
        [self.trackIDs addObject:trackID];
    }

    if (self.trackIDs.count > kPlaybackHistoryMaxEntries) {
        NSRange trimRange = NSMakeRange(kPlaybackHistoryMaxEntries, self.trackIDs.count - kPlaybackHistoryMaxEntries);
        [self.trackIDs removeObjectsInRange:trimRange];
    }
}

- (void)persistToDefaults {
    [NSUserDefaults.standardUserDefaults setObject:self.trackIDs.copy ?: @[] forKey:kPlaybackHistoryDefaultsKey];
}

@end
