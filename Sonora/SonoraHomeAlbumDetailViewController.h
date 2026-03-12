//
//  SonoraHomeAlbumDetailViewController.h
//  Sonora
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class SonoraTrack;

@interface SonoraHomeAlbumDetailViewController : UIViewController

- (instancetype)initWithAlbumTitle:(NSString *)albumTitle tracks:(NSArray<SonoraTrack *> *)tracks;

@end

NS_ASSUME_NONNULL_END
