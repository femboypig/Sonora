//
//  AppDelegate.m
//  Sonora
//
//  Created by loser on 22.02.2026.
//

#import "AppDelegate.h"
#import <AVFoundation/AVFoundation.h>
#import "SonoraWidgetBridge.h"

@interface AppDelegate ()

- (nullable NSError *)loadPersistentStoresForContainer:(NSPersistentContainer *)container;
- (BOOL)configurePersistentContainer:(NSPersistentContainer *)container;
- (BOOL)analyticsStoreFilesExistAtURL:(NSURL *)storeURL;

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Override point for customization after application launch.
    [application beginReceivingRemoteControlEvents];

    NSError *sessionError = nil;
    AVAudioSession *session = AVAudioSession.sharedInstance;
    [session setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:0 error:&sessionError];
    if (sessionError != nil) {
        NSLog(@"Audio session category error: %@", sessionError.localizedDescription);
    }

    sessionError = nil;
    [session setActive:YES error:&sessionError];
    if (sessionError != nil) {
        NSLog(@"Audio session activation error: %@", sessionError.localizedDescription);
    }

    // Sync tracks data with widget early on launch
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [SonoraWidgetBridge refreshSharedLovelyTracks];
    });

    return YES;
}


#pragma mark - UISceneSession lifecycle


- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {
    // Called when a new scene session is being created.
    // Use this method to select a configuration to create the new scene with.
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
}


- (void)application:(UIApplication *)application didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions {
    // Called when the user discards a scene session.
    // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
    // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
}


#pragma mark - Core Data stack

@synthesize persistentContainer = _persistentContainer;

- (NSPersistentContainer *)persistentContainer {
    // The persistent container for the application. This implementation creates and returns a container, having loaded the store for the application to it.
    @synchronized (self) {
        if (_persistentContainer == nil) {
            _persistentContainer = [[NSPersistentContainer alloc] initWithName:@"Sonora"];
            NSPersistentStoreDescription *storeDescription = _persistentContainer.persistentStoreDescriptions.firstObject;
            storeDescription.shouldMigrateStoreAutomatically = YES;
            storeDescription.shouldInferMappingModelAutomatically = YES;
            [self configurePersistentContainer:_persistentContainer];
        }
    }
    
    return _persistentContainer;
}

#pragma mark - Core Data Saving support

- (void)saveContext {
    NSManagedObjectContext *context = self.persistentContainer.viewContext;
    NSError *error = nil;
    if ([context hasChanges] && ![context save:&error]) {
        NSLog(@"Core Data save error %@, %@", error, error.userInfo);
        [context rollback];
    }
}

- (nullable NSError *)loadPersistentStoresForContainer:(NSPersistentContainer *)container {
    __block NSError *loadError = nil;
    [container loadPersistentStoresWithCompletionHandler:^(__unused NSPersistentStoreDescription *storeDescription, NSError *error) {
        if (error != nil) {
            loadError = error;
        }
    }];
    return loadError;
}

- (BOOL)configurePersistentContainer:(NSPersistentContainer *)container {
    NSError *loadError = [self loadPersistentStoresForContainer:container];
    if (loadError == nil) {
        return YES;
    }

    NSLog(@"Core Data load error %@, %@", loadError, loadError.userInfo);

    NSPersistentStoreDescription *storeDescription = container.persistentStoreDescriptions.firstObject;
    NSURL *storeURL = storeDescription.URL;
    if (storeURL.isFileURL && [self analyticsStoreFilesExistAtURL:storeURL]) {
        NSError *destroyError = nil;
        BOOL destroyed = [container.persistentStoreCoordinator destroyPersistentStoreAtURL:storeURL
                                                                                  withType:storeDescription.type
                                                                                   options:storeDescription.options
                                                                                     error:&destroyError];
        if (!destroyed) {
            NSLog(@"Core Data reset error %@, %@", destroyError, destroyError.userInfo);
        } else {
            NSError *recoveryError = [self loadPersistentStoresForContainer:container];
            if (recoveryError == nil) {
                NSLog(@"Core Data store was reset after a load failure.");
                return YES;
            }
            NSLog(@"Core Data recovery load error %@, %@", recoveryError, recoveryError.userInfo);
        }
    }

    NSPersistentStoreDescription *inMemoryDescription = [NSPersistentStoreDescription new];
    inMemoryDescription.type = NSInMemoryStoreType;
    inMemoryDescription.shouldMigrateStoreAutomatically = YES;
    inMemoryDescription.shouldInferMappingModelAutomatically = YES;
    container.persistentStoreDescriptions = @[inMemoryDescription];

    NSError *fallbackError = [self loadPersistentStoresForContainer:container];
    if (fallbackError == nil) {
        NSLog(@"Core Data is using an in-memory fallback store.");
        return YES;
    }

    NSLog(@"Core Data in-memory fallback failed %@, %@", fallbackError, fallbackError.userInfo);
    return NO;
}

- (BOOL)analyticsStoreFilesExistAtURL:(NSURL *)storeURL {
    if (!storeURL.isFileURL || storeURL.path.length == 0) {
        return NO;
    }

    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSString *storePath = storeURL.path;
    NSArray<NSString *> *candidatePaths = @[
        storePath,
        [storePath stringByAppendingString:@"-shm"],
        [storePath stringByAppendingString:@"-wal"]
    ];
    for (NSString *candidatePath in candidatePaths) {
        if ([fileManager fileExistsAtPath:candidatePath]) {
            return YES;
        }
    }

    return NO;
}

@end
