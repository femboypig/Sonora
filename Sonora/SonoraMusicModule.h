//
//  SonoraMusicModule.h
//  Sonora
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXTERN BOOL SonoraHandleMusicModuleDeepLinkURL(NSURL *url);

@interface SonoraMusicViewController : UIViewController
@property (nonatomic, assign) BOOL musicOnlyMode;
@end

@interface SonoraPlaylistsViewController : UIViewController
@end

@interface SonoraFavoritesViewController : UIViewController
@end

NS_ASSUME_NONNULL_END
