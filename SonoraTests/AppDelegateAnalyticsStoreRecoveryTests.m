@import XCTest;
@import CoreData;

#import "AppDelegate.h"

@interface AppDelegate (Testing)

- (BOOL)configurePersistentContainer:(NSPersistentContainer *)container;

@end

@interface AppDelegateAnalyticsStoreRecoveryTests : XCTestCase

@property (nonatomic, strong) NSURL *temporaryRootURL;

@end

@implementation AppDelegateAnalyticsStoreRecoveryTests

- (void)setUp {
    [super setUp];
    NSString *directoryName = [NSString stringWithFormat:@"AppDelegateAnalyticsStoreRecoveryTests-%@", NSUUID.UUID.UUIDString.lowercaseString];
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

- (void)testConfigurePersistentContainerRecoversFromCorruptedSQLiteStore {
    NSURL *modelURL = [[NSBundle bundleForClass:AppDelegate.class] URLForResource:@"Sonora" withExtension:@"momd"];
    XCTAssertNotNil(modelURL);

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    XCTAssertNotNil(model);

    NSPersistentContainer *container = [[NSPersistentContainer alloc] initWithName:@"Sonora" managedObjectModel:model];
    NSPersistentStoreDescription *description = container.persistentStoreDescriptions.firstObject;
    NSURL *storeURL = [self.temporaryRootURL URLByAppendingPathComponent:@"analytics.sqlite"];
    description.type = NSSQLiteStoreType;
    description.URL = storeURL;
    description.shouldMigrateStoreAutomatically = YES;
    description.shouldInferMappingModelAutomatically = YES;

    NSData *garbageData = [@"not-a-real-sqlite-store" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([garbageData writeToURL:storeURL atomically:YES]);

    AppDelegate *delegate = [[AppDelegate alloc] init];
    BOOL configured = [delegate configurePersistentContainer:container];

    XCTAssertTrue(configured);
    XCTAssertEqual(container.persistentStoreCoordinator.persistentStores.count, 1);

    NSPersistentStore *store = container.persistentStoreCoordinator.persistentStores.firstObject;
    XCTAssertEqualObjects(store.type, NSSQLiteStoreType);
    XCTAssertEqualObjects(store.URL, storeURL);
}

@end
