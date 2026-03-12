//
//  SonoraFavoritesStore.m
//  Sonora
//

#import "SonoraServices.h"

static NSString * const kFavoritesDefaultsKey = @"sonora_favorites_v1";

@interface SonoraFavoritesStore ()

@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *favoriteIDs;

@end

@implementation SonoraFavoritesStore

+ (instancetype)sharedStore {
    static SonoraFavoritesStore *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = [[SonoraFavoritesStore alloc] init];
    });
    return store;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _favoriteIDs = [NSMutableOrderedSet orderedSet];
        [self reloadFavoritesFromDefaults];
    }
    return self;
}

- (NSArray<NSString *> *)favoriteTrackIDs {
    return self.favoriteIDs.array ?: @[];
}

- (NSString *)canonicalFavoriteIDForTrackID:(NSString *)trackID {
    if (trackID.length == 0) {
        return @"";
    }

    SonoraTrack *resolvedTrack = [SonoraLibraryManager.sharedManager trackForIdentifier:trackID];
    if (resolvedTrack.identifier.length > 0) {
        return resolvedTrack.identifier;
    }

    return trackID;
}

- (NSIndexSet *)indexesForFavoritesMatchingTrackID:(NSString *)trackID {
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
    if (trackID.length == 0 || self.favoriteIDs.count == 0) {
        return indexes;
    }

    NSString *targetCanonicalID = [self canonicalFavoriteIDForTrackID:trackID];
    if (targetCanonicalID.length == 0) {
        return indexes;
    }

    [self.favoriteIDs enumerateObjectsUsingBlock:^(NSString * _Nonnull storedTrackID, NSUInteger idx, __unused BOOL * _Nonnull stop) {
        NSString *storedCanonicalID = [self canonicalFavoriteIDForTrackID:storedTrackID];
        if ([storedCanonicalID isEqualToString:targetCanonicalID]) {
            [indexes addIndex:idx];
        }
    }];
    return indexes;
}

- (void)normalizeFavoriteTrackIDsIfNeeded {
    if (self.favoriteIDs.count == 0) {
        return;
    }

    NSMutableOrderedSet<NSString *> *normalized = [NSMutableOrderedSet orderedSetWithCapacity:self.favoriteIDs.count];
    BOOL changed = NO;

    for (NSString *storedTrackID in self.favoriteIDs) {
        NSString *canonicalID = [self canonicalFavoriteIDForTrackID:storedTrackID];
        if (canonicalID.length == 0) {
            changed = YES;
            continue;
        }

        if (![canonicalID isEqualToString:storedTrackID]) {
            changed = YES;
        }
        if ([normalized containsObject:canonicalID]) {
            changed = YES;
            continue;
        }
        [normalized addObject:canonicalID];
    }

    if (!changed) {
        return;
    }

    self.favoriteIDs = normalized;
    [self persistFavorites];
}

- (BOOL)isTrackFavoriteByID:(NSString *)trackID {
    if (trackID.length == 0) {
        return NO;
    }
    return [self indexesForFavoritesMatchingTrackID:trackID].count > 0;
}

- (void)setTrackID:(NSString *)trackID favorite:(BOOL)favorite {
    if (trackID.length == 0) {
        return;
    }

    NSIndexSet *matchingIndexes = [self indexesForFavoritesMatchingTrackID:trackID];
    BOOL alreadyFavorite = matchingIndexes.count > 0;
    NSString *canonicalID = [self canonicalFavoriteIDForTrackID:trackID];
    if (canonicalID.length == 0) {
        return;
    }

    if (!favorite && !alreadyFavorite) {
        return;
    }

    if (favorite) {
        BOOL alreadyCanonicalOnly = (matchingIndexes.count == 1 &&
                                     [[self.favoriteIDs objectAtIndex:matchingIndexes.firstIndex] isEqualToString:canonicalID]);
        if (alreadyCanonicalOnly) {
            return;
        }

        if (matchingIndexes.count > 0) {
            [self.favoriteIDs removeObjectsAtIndexes:matchingIndexes];
        }
        [self.favoriteIDs addObject:canonicalID];
    } else {
        [self.favoriteIDs removeObjectsAtIndexes:matchingIndexes];
    }

    [self persistFavorites];
    [NSNotificationCenter.defaultCenter postNotificationName:SonoraFavoritesDidChangeNotification object:nil];
}

- (void)toggleFavoriteForTrackID:(NSString *)trackID {
    [self setTrackID:trackID favorite:![self isTrackFavoriteByID:trackID]];
}

- (NSArray<SonoraTrack *> *)favoriteTracksWithLibrary:(SonoraLibraryManager *)library {
    NSMutableArray<SonoraTrack *> *tracks = [NSMutableArray arrayWithCapacity:self.favoriteIDs.count];
    NSMutableSet<NSString *> *seenTrackIDs = [NSMutableSet setWithCapacity:self.favoriteIDs.count];
    for (NSString *trackID in self.favoriteIDs) {
        SonoraTrack *track = [library trackForIdentifier:trackID];
        if (track != nil && track.identifier.length > 0 && ![seenTrackIDs containsObject:track.identifier]) {
            [seenTrackIDs addObject:track.identifier];
            [tracks addObject:track];
        }
    }
    return tracks.copy;
}

- (void)reloadFavoritesFromDefaults {
    NSArray *stored = [NSUserDefaults.standardUserDefaults arrayForKey:kFavoritesDefaultsKey];
    [self.favoriteIDs removeAllObjects];

    if (![stored isKindOfClass:NSArray.class]) {
        return;
    }

    for (id value in stored) {
        if ([value isKindOfClass:NSString.class] && ((NSString *)value).length > 0) {
            [self.favoriteIDs addObject:value];
        }
    }

    [self normalizeFavoriteTrackIDsIfNeeded];
}

- (void)persistFavorites {
    [NSUserDefaults.standardUserDefaults setObject:self.favoriteIDs.array ?: @[] forKey:kFavoritesDefaultsKey];
}

@end
