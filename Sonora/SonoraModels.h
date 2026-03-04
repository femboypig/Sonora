//
//  SonoraModels.h
//  Sonora
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SonoraTrack : NSObject

@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *artist;
@property (nonatomic, copy) NSString *fileName;
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, strong) UIImage *artwork;

@end

@interface SonoraPlaylist : NSObject

@property (nonatomic, copy) NSString *playlistID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSArray<NSString *> *trackIDs;
@property (nonatomic, copy, nullable) NSString *customCoverFileName;

+ (nullable instancetype)playlistFromDictionary:(NSDictionary<NSString *, id> *)dictionary;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;

@end

FOUNDATION_EXTERN NSString *SonoraFormatDuration(NSTimeInterval duration);

NS_ASSUME_NONNULL_END
