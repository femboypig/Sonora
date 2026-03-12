//
//  SonoraTrackAnalyticsStore.m
//  Sonora
//

#import "SonoraServices.h"

#import <CoreData/CoreData.h>

#import "AppDelegate.h"

static NSString * const kTrackAnalyticsEntityName = @"TrackAnalytics";
static NSString * const kTrackAnalyticsTrackIDKey = @"trackID";
static NSString * const kTrackAnalyticsPlayCountKey = @"playCount";
static NSString * const kTrackAnalyticsSkipCountKey = @"skipCount";
static NSString * const kTrackAnalyticsUpdatedAtKey = @"updatedAt";

@interface SonoraTrackAnalyticsStore ()

@property (nonatomic, strong, nullable) NSPersistentContainer *cachedPersistentContainer;

@end

@implementation SonoraTrackAnalyticsStore

+ (instancetype)sharedStore {
    static SonoraTrackAnalyticsStore *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = [[SonoraTrackAnalyticsStore alloc] init];
    });
    return store;
}

- (nullable NSManagedObjectContext *)analyticsContext {
    NSPersistentContainer *container = [self analyticsPersistentContainer];
    if (container == nil) {
        return nil;
    }

    NSManagedObjectContext *context = [container newBackgroundContext];
    context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy;
    context.undoManager = nil;
    return context;
}

- (nullable NSPersistentContainer *)analyticsPersistentContainer {
    @synchronized (self) {
        if (self.cachedPersistentContainer != nil) {
            return self.cachedPersistentContainer;
        }
    }

    __block id<UIApplicationDelegate> appDelegate = nil;
    void (^resolveDelegate)(void) = ^{
        appDelegate = UIApplication.sharedApplication.delegate;
    };
    if (NSThread.isMainThread) {
        resolveDelegate();
    } else {
        dispatch_sync(dispatch_get_main_queue(), resolveDelegate);
    }

    if (![appDelegate isKindOfClass:AppDelegate.class]) {
        return nil;
    }

    NSPersistentContainer *container = ((AppDelegate *)appDelegate).persistentContainer;
    if (container == nil) {
        return nil;
    }

    @synchronized (self) {
        if (self.cachedPersistentContainer == nil) {
            self.cachedPersistentContainer = container;
        }
        return self.cachedPersistentContainer;
    }
}

- (nullable NSManagedObject *)entryForTrackID:(NSString *)trackID
                                    inContext:(NSManagedObjectContext *)context
                                 createIfMiss:(BOOL)createIfMiss {
    if (trackID.length == 0 || context == nil) {
        return nil;
    }

    NSFetchRequest<NSManagedObject *> *request = [NSFetchRequest fetchRequestWithEntityName:kTrackAnalyticsEntityName];
    request.predicate = [NSPredicate predicateWithFormat:@"%K == %@", kTrackAnalyticsTrackIDKey, trackID];
    request.fetchLimit = 1;

    NSError *fetchError = nil;
    NSArray<NSManagedObject *> *results = [context executeFetchRequest:request error:&fetchError];
    if (results.count > 0) {
        return results.firstObject;
    }

    if (!createIfMiss) {
        return nil;
    }

    NSEntityDescription *entity = [NSEntityDescription entityForName:kTrackAnalyticsEntityName inManagedObjectContext:context];
    if (entity == nil) {
        return nil;
    }

    NSManagedObject *entry = [[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:context];
    [entry setValue:trackID forKey:kTrackAnalyticsTrackIDKey];
    [entry setValue:@(0) forKey:kTrackAnalyticsPlayCountKey];
    [entry setValue:@(0) forKey:kTrackAnalyticsSkipCountKey];
    [entry setValue:NSDate.date forKey:kTrackAnalyticsUpdatedAtKey];
    return entry;
}

- (void)saveContextIfNeeded:(NSManagedObjectContext *)context {
    if (context == nil || !context.hasChanges) {
        return;
    }

    NSError *saveError = nil;
    [context save:&saveError];
    if (saveError != nil) {
        NSLog(@"Track analytics save error: %@", saveError.localizedDescription);
    }
}

- (void)recordPlayForTrackID:(NSString *)trackID {
    NSManagedObjectContext *context = [self analyticsContext];
    if (context == nil || trackID.length == 0) {
        return;
    }

    [context performBlock:^{
        NSManagedObject *entry = [self entryForTrackID:trackID inContext:context createIfMiss:YES];
        if (entry == nil) {
            return;
        }

        NSInteger playCount = [[entry valueForKey:kTrackAnalyticsPlayCountKey] integerValue];
        [entry setValue:@(playCount + 1) forKey:kTrackAnalyticsPlayCountKey];
        [entry setValue:NSDate.date forKey:kTrackAnalyticsUpdatedAtKey];
        [self saveContextIfNeeded:context];
    }];
}

- (void)recordSkipForTrackID:(NSString *)trackID {
    NSManagedObjectContext *context = [self analyticsContext];
    if (context == nil || trackID.length == 0) {
        return;
    }

    [context performBlock:^{
        NSManagedObject *entry = [self entryForTrackID:trackID inContext:context createIfMiss:YES];
        if (entry == nil) {
            return;
        }

        NSInteger skipCount = [[entry valueForKey:kTrackAnalyticsSkipCountKey] integerValue];
        [entry setValue:@(skipCount + 1) forKey:kTrackAnalyticsSkipCountKey];
        [entry setValue:NSDate.date forKey:kTrackAnalyticsUpdatedAtKey];
        [self saveContextIfNeeded:context];
    }];
}

- (double)scoreForTrackID:(NSString *)trackID {
    if (trackID.length == 0) {
        return 0.0;
    }

    NSManagedObjectContext *context = [self analyticsContext];
    if (context == nil) {
        return 0.0;
    }

    __block double score = 0.0;
    [context performBlockAndWait:^{
        NSManagedObject *entry = [self entryForTrackID:trackID inContext:context createIfMiss:NO];
        if (entry == nil) {
            score = 0.0;
            return;
        }

        double plays = [[entry valueForKey:kTrackAnalyticsPlayCountKey] doubleValue];
        double skips = [[entry valueForKey:kTrackAnalyticsSkipCountKey] doubleValue];
        score = plays / (plays + skips + 1.0);
    }];
    return score;
}

- (NSDictionary<NSString *, NSDictionary<NSString *, NSNumber *> *> *)analyticsByTrackIDForTrackIDs:(NSArray<NSString *> *)trackIDs {
    if (trackIDs.count == 0) {
        return @{};
    }

    NSManagedObjectContext *context = [self analyticsContext];
    if (context == nil) {
        return @{};
    }

    NSMutableArray<NSString *> *normalized = [NSMutableArray arrayWithCapacity:trackIDs.count];
    for (NSString *trackID in trackIDs) {
        if ([trackID isKindOfClass:NSString.class] && trackID.length > 0) {
            [normalized addObject:trackID];
        }
    }
    if (normalized.count == 0) {
        return @{};
    }

    __block NSDictionary<NSString *, NSDictionary<NSString *, NSNumber *> *> *result = @{};
    [context performBlockAndWait:^{
        NSFetchRequest<NSManagedObject *> *request = [NSFetchRequest fetchRequestWithEntityName:kTrackAnalyticsEntityName];
        request.predicate = [NSPredicate predicateWithFormat:@"%K IN %@", kTrackAnalyticsTrackIDKey, normalized];

        NSError *fetchError = nil;
        NSArray<NSManagedObject *> *entries = [context executeFetchRequest:request error:&fetchError];
        if (fetchError != nil || entries.count == 0) {
            result = @{};
            return;
        }

        NSMutableDictionary<NSString *, NSDictionary<NSString *, NSNumber *> *> *map = [NSMutableDictionary dictionaryWithCapacity:entries.count];
        for (NSManagedObject *entry in entries) {
            NSString *trackID = [entry valueForKey:kTrackAnalyticsTrackIDKey];
            if (![trackID isKindOfClass:NSString.class] || trackID.length == 0) {
                continue;
            }

            NSInteger playCount = [[entry valueForKey:kTrackAnalyticsPlayCountKey] integerValue];
            NSInteger skipCount = [[entry valueForKey:kTrackAnalyticsSkipCountKey] integerValue];
            double score = ((double)playCount) / ((double)playCount + (double)skipCount + 1.0);

            map[trackID] = @{
                @"playCount": @(playCount),
                @"skipCount": @(skipCount),
                @"score": @(score)
            };
        }

        result = [map copy];
    }];
    return result;
}

- (NSDictionary<NSString *, NSNumber *> *)scoreMapForTrackIDs:(NSArray<NSString *> *)trackIDs {
    if (trackIDs.count == 0) {
        return @{};
    }

    NSManagedObjectContext *context = [self analyticsContext];
    if (context == nil) {
        return @{};
    }

    NSMutableArray<NSString *> *normalized = [NSMutableArray arrayWithCapacity:trackIDs.count];
    for (NSString *trackID in trackIDs) {
        if ([trackID isKindOfClass:NSString.class] && trackID.length > 0) {
            [normalized addObject:trackID];
        }
    }
    if (normalized.count == 0) {
        return @{};
    }

    __block NSDictionary<NSString *, NSNumber *> *result = @{};
    [context performBlockAndWait:^{
        NSFetchRequest<NSManagedObject *> *request = [NSFetchRequest fetchRequestWithEntityName:kTrackAnalyticsEntityName];
        request.predicate = [NSPredicate predicateWithFormat:@"%K IN %@", kTrackAnalyticsTrackIDKey, normalized];

        NSError *error = nil;
        NSArray<NSManagedObject *> *entries = [context executeFetchRequest:request error:&error];
        if (entries.count == 0 || error != nil) {
            result = @{};
            return;
        }

        NSMutableDictionary<NSString *, NSNumber *> *map = [NSMutableDictionary dictionaryWithCapacity:entries.count];
        for (NSManagedObject *entry in entries) {
            NSString *trackID = [entry valueForKey:kTrackAnalyticsTrackIDKey];
            if (![trackID isKindOfClass:NSString.class] || trackID.length == 0) {
                continue;
            }

            double plays = [[entry valueForKey:kTrackAnalyticsPlayCountKey] doubleValue];
            double skips = [[entry valueForKey:kTrackAnalyticsSkipCountKey] doubleValue];
            double score = plays / (plays + skips + 1.0);
            map[trackID] = @(score);
        }
        result = [map copy];
    }];
    return result;
}

- (NSArray<SonoraTrack *> *)tracksSortedByAffinity:(NSArray<SonoraTrack *> *)tracks {
    if (tracks.count <= 1) {
        return tracks ?: @[];
    }

    NSMutableArray<NSString *> *trackIDs = [NSMutableArray arrayWithCapacity:tracks.count];
    for (SonoraTrack *track in tracks) {
        if (track.identifier.length > 0) {
            [trackIDs addObject:track.identifier];
        }
    }

    NSDictionary<NSString *, NSNumber *> *scoreByID = [self scoreMapForTrackIDs:trackIDs];
    return [tracks sortedArrayUsingComparator:^NSComparisonResult(SonoraTrack * _Nonnull left, SonoraTrack * _Nonnull right) {
        double leftScore = [scoreByID[left.identifier] doubleValue];
        double rightScore = [scoreByID[right.identifier] doubleValue];
        if (leftScore > rightScore) {
            return NSOrderedAscending;
        }
        if (leftScore < rightScore) {
            return NSOrderedDescending;
        }
        return [left.title localizedCaseInsensitiveCompare:right.title];
    }];
}

@end
