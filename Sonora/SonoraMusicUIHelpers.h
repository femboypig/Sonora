//
//  SonoraMusicUIHelpers.h
//  Sonora
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

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
FOUNDATION_EXTERN SonoraPlayerFontStyle SonoraPlayerFontStyleFromDefaults(void);
FOUNDATION_EXTERN UIColor *SonoraPlayerBackgroundColor(void);
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
FOUNDATION_EXTERN NSString *SonoraNormalizedSearchText(NSString *text);
FOUNDATION_EXTERN UIButton *SonoraPlainIconButton(NSString *symbolName, CGFloat symbolSize, CGFloat weightValue);
FOUNDATION_EXTERN UIImage *SonoraSliderThumbImage(CGFloat diameter, UIColor *color);

NS_ASSUME_NONNULL_END
