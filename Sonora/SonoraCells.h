//
//  SonoraCells.h
//  Sonora
//

#import <UIKit/UIKit.h>

#import "SonoraModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface SonoraTrackCell : UITableViewCell

- (void)configureWithTrack:(SonoraTrack *)track isCurrent:(BOOL)isCurrent;
- (void)configureWithTrack:(SonoraTrack *)track
                 isCurrent:(BOOL)isCurrent
    showsPlaybackIndicator:(BOOL)showsPlaybackIndicator;

@end

@interface SonoraPlaylistCell : UITableViewCell

- (void)configureWithName:(NSString *)name
                 subtitle:(NSString *)subtitle
                  artwork:(UIImage *)artwork;

@end

@interface SonoraTrackGridCell : UICollectionViewCell

- (void)configureWithTrack:(SonoraTrack *)track isCurrent:(BOOL)isCurrent;

@end

@interface SonoraPlaylistGridCell : UICollectionViewCell

- (void)configureWithName:(NSString *)name
                 subtitle:(NSString *)subtitle
                  artwork:(UIImage *)artwork;

@end

NS_ASSUME_NONNULL_END
