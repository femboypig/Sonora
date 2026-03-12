//
//  SonoraPlaylistViewControllers.h
//  Sonora
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class SonoraSharedPlaylistSnapshot;
@class SonoraTrack;

@interface SonoraPlaylistNameViewController : UIViewController
@end

@interface SonoraPlaylistTrackPickerViewController : UIViewController
- (instancetype)initWithPlaylistName:(NSString *)playlistName
                              tracks:(NSArray<SonoraTrack *> *)tracks;
@end

@interface SonoraPlaylistAddTracksViewController : UIViewController
- (instancetype)initWithPlaylistID:(NSString *)playlistID;
@end

@interface SonoraPlaylistCoverPickerViewController : UIViewController
- (instancetype)initWithPlaylistID:(NSString *)playlistID;
@end

@interface SonoraPlaylistDetailViewController : UIViewController
- (instancetype)initWithPlaylistID:(NSString *)playlistID;
- (instancetype)initWithSharedPlaylistSnapshot:(SonoraSharedPlaylistSnapshot *)snapshot;
@end

NS_ASSUME_NONNULL_END
