//
//  SonoraMusicUIHelpers.h
//  Sonora
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class SonoraTrack;

typedef NS_ENUM(NSInteger, SonoraPlayerFontStyle) {
    SonoraPlayerFontStyleSystem = 0,
    SonoraPlayerFontStyleSerif = 1,
};

typedef NS_ENUM(NSInteger, SonoraPlayerArtworkStyle) {
    SonoraPlayerArtworkStyleSquare = 0,
    SonoraPlayerArtworkStyleRounded = 1,
};

FOUNDATION_EXTERN void SonoraConfigureNavigationIconBarButtonItem(UIBarButtonItem *item, NSString *title);
FOUNDATION_EXTERN UIColor *SonoraAccentYellowColor(void);
FOUNDATION_EXTERN UIColor *SonoraLovelyAccentRedColor(void);
FOUNDATION_EXTERN SonoraPlayerFontStyle SonoraPlayerFontStyleFromDefaults(void);
FOUNDATION_EXTERN UIColor *SonoraPlayerBackgroundColor(void);
FOUNDATION_EXTERN UIColor *SonoraAppBackgroundColor(void);
FOUNDATION_EXTERN UIColor *SonoraPlayerPrimaryColor(void);
FOUNDATION_EXTERN UIColor *SonoraPlayerSecondaryColor(void);
FOUNDATION_EXTERN UIColor *SonoraPlayerTimelineMaxColor(void);
FOUNDATION_EXTERN UIFont *SonoraHeadlineFont(CGFloat size);
FOUNDATION_EXTERN UIFont *SonoraPlayerFontForStyle(SonoraPlayerFontStyle style, CGFloat size, UIFontWeight weight);
FOUNDATION_EXTERN SonoraPlayerArtworkStyle SonoraPlayerArtworkStyleFromDefaults(void);
FOUNDATION_EXTERN BOOL SonoraArtworkEqualizerEnabledFromDefaults(void);
FOUNDATION_EXTERN CGFloat SonoraArtworkCornerRadiusForStyle(SonoraPlayerArtworkStyle style, CGFloat width);
FOUNDATION_EXTERN UIImage * _Nullable SonoraLovelySongsCoverImage(CGSize size);
FOUNDATION_EXTERN UIView *SonoraWhiteSectionTitleLabel(NSString *text);
FOUNDATION_EXTERN void SonoraPresentAlert(UIViewController *controller, NSString *title, NSString *message);
FOUNDATION_EXTERN UIAlertController * _Nullable SonoraPresentBlockingProgressAlert(UIViewController * _Nullable controller,
                                                                                   NSString *title,
                                                                                   NSString *message);
FOUNDATION_EXTERN NSString *SonoraNormalizedSearchText(NSString *text);
FOUNDATION_EXTERN NSString * const SonoraLovelyPlaylistDefaultsKey;
FOUNDATION_EXTERN NSString * const SonoraSharedPlaylistSyntheticPrefix;
FOUNDATION_EXTERN CGFloat const SonoraSearchRevealThreshold;
FOUNDATION_EXTERN NSArray<SonoraTrack *> *SonoraFilterTracksByQuery(NSArray<SonoraTrack *> *tracks, NSString *query);
FOUNDATION_EXTERN BOOL SonoraTrackQueuesMatchByIdentifier(NSArray<SonoraTrack *> *first, NSArray<SonoraTrack *> *second);
FOUNDATION_EXTERN UISearchController *SonoraBuildSearchController(id<UISearchResultsUpdating> updater, NSString *placeholder);
FOUNDATION_EXTERN BOOL SonoraShouldAttachSearchController(BOOL currentlyAttached,
                                                          UISearchController * _Nullable searchController,
                                                          UIScrollView * _Nullable scrollView,
                                                          CGFloat revealThreshold);
FOUNDATION_EXTERN void SonoraApplySearchControllerAttachment(UINavigationItem *navigationItem,
                                                             UINavigationBar * _Nullable navigationBar,
                                                             UISearchController * _Nullable searchController,
                                                             BOOL shouldAttach,
                                                             BOOL animated);
FOUNDATION_EXTERN void SonoraPresentQuickAddTrackToPlaylist(UIViewController *controller,
                                                            NSString *trackID,
                                                            dispatch_block_t _Nullable completionHandler);
FOUNDATION_EXTERN UIButton *SonoraPlainIconButton(NSString *symbolName, CGFloat symbolSize, CGFloat weightValue);
FOUNDATION_EXTERN UIImage *SonoraSliderThumbImage(CGFloat diameter, UIColor *color);

NS_ASSUME_NONNULL_END
