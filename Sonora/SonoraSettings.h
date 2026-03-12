#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SonoraMyWaveLook) {
    SonoraMyWaveLookClouds = 0,
    SonoraMyWaveLookContours = 1
};

FOUNDATION_EXTERN NSString * _Nullable SonoraSettingsAccentHex(void);
FOUNDATION_EXTERN NSInteger SonoraSettingsLegacyAccentColorIndex(void);
FOUNDATION_EXTERN void SonoraSettingsStoreAccentHex(NSString *hex);

FOUNDATION_EXTERN NSInteger SonoraSettingsFontStyleIndex(void);
FOUNDATION_EXTERN void SonoraSettingsSetFontStyleIndex(NSInteger value);

FOUNDATION_EXTERN NSInteger SonoraSettingsArtworkStyleIndex(void);
FOUNDATION_EXTERN void SonoraSettingsSetArtworkStyleIndex(NSInteger value);

FOUNDATION_EXTERN SonoraMyWaveLook SonoraSettingsMyWaveLook(void);
FOUNDATION_EXTERN void SonoraSettingsSetMyWaveLook(SonoraMyWaveLook value);

FOUNDATION_EXTERN BOOL SonoraSettingsArtworkEqualizerEnabled(void);
FOUNDATION_EXTERN void SonoraSettingsSetArtworkEqualizerEnabled(BOOL enabled);

FOUNDATION_EXTERN BOOL SonoraSettingsPreservePlayerModesEnabled(void);
FOUNDATION_EXTERN void SonoraSettingsSetPreservePlayerModesEnabled(BOOL enabled);

FOUNDATION_EXTERN BOOL SonoraSettingsCacheOnlinePlaylistTracksEnabled(void);
FOUNDATION_EXTERN void SonoraSettingsSetCacheOnlinePlaylistTracksEnabled(BOOL enabled);

FOUNDATION_EXTERN NSTimeInterval SonoraSettingsTrackGapSeconds(void);
FOUNDATION_EXTERN void SonoraSettingsSetTrackGapSeconds(NSTimeInterval seconds);

FOUNDATION_EXTERN NSInteger SonoraSettingsMaxStorageMB(void);
FOUNDATION_EXTERN void SonoraSettingsSetMaxStorageMB(NSInteger value);

FOUNDATION_EXTERN NSInteger SonoraSettingsOnlinePlaylistCacheMaxMB(void);
FOUNDATION_EXTERN void SonoraSettingsSetOnlinePlaylistCacheMaxMB(NSInteger value);

NS_ASSUME_NONNULL_END
