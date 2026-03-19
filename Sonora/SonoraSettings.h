#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SonoraMyWaveLook) {
    SonoraMyWaveLookClouds = 0,
    SonoraMyWaveLookContours = 1
};

typedef NS_ENUM(NSInteger, SonoraStreamingSearchEngine) {
    SonoraStreamingSearchEngineSpotify = 0,
    SonoraStreamingSearchEngineYouTube = 1
};

typedef NS_ENUM(NSInteger, SonoraAppBackgroundMode) {
    SonoraAppBackgroundModeSystem = 0,
    SonoraAppBackgroundModeArtwork = 1,
    SonoraAppBackgroundModeCustom = 2
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

FOUNDATION_EXTERN SonoraStreamingSearchEngine SonoraSettingsStreamingSearchEngine(void);
FOUNDATION_EXTERN void SonoraSettingsSetStreamingSearchEngine(SonoraStreamingSearchEngine value);

FOUNDATION_EXTERN BOOL SonoraSettingsUseArtworkBasedPlayerBackgroundEnabled(void);
FOUNDATION_EXTERN void SonoraSettingsSetUseArtworkBasedPlayerBackgroundEnabled(BOOL enabled);
FOUNDATION_EXTERN BOOL SonoraSettingsUseAccentAppBackgroundEnabled(void);
FOUNDATION_EXTERN void SonoraSettingsSetUseAccentAppBackgroundEnabled(BOOL enabled);
FOUNDATION_EXTERN SonoraAppBackgroundMode SonoraSettingsAppBackgroundMode(void);
FOUNDATION_EXTERN void SonoraSettingsSetAppBackgroundMode(SonoraAppBackgroundMode mode);
FOUNDATION_EXTERN NSString * _Nullable SonoraSettingsAppBackgroundHex(void);
FOUNDATION_EXTERN void SonoraSettingsStoreAppBackgroundHex(NSString * _Nullable hex);

FOUNDATION_EXTERN BOOL SonoraSettingsAutoSaveStreamingSongsEnabled(void);
FOUNDATION_EXTERN void SonoraSettingsSetAutoSaveStreamingSongsEnabled(BOOL enabled);

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
