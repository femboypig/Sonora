//
//  SonoraWidgetBridge.h
//  Sonora
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SonoraWidgetBridge : NSObject

+ (void)refreshSharedLovelyTracks;
+ (BOOL)handleWidgetDeepLinkURL:(NSURL *)url;

@end

NS_ASSUME_NONNULL_END
