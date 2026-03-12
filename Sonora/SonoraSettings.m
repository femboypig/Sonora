#import "SonoraSettings.h"

static NSString * const SonoraSettingsFontKey = @"sonora.settings.font";
static NSString * const SonoraSettingsAccentHexKey = @"sonora.settings.accentHex";
static NSString * const SonoraSettingsLegacyAccentColorKey = @"sonora.settings.accentColor";
static NSString * const SonoraSettingsArtworkStyleKey = @"sonora.settings.artworkStyle";
static NSString * const SonoraSettingsArtworkEqualizerKey = @"sonora.settings.showArtworkEqualizer";
static NSString * const SonoraSettingsMaxStorageMBKey = @"sonora.settings.maxStorageMB";
static NSString * const SonoraSettingsCacheOnlinePlaylistTracksKey = @"sonora.settings.cacheOnlinePlaylistTracks";
static NSString * const SonoraSettingsOnlinePlaylistCacheMaxMBKey = @"sonora.settings.onlinePlaylistCacheMaxMB";
static NSString * const SonoraSettingsPreservePlayerModesKey = @"sonora.settings.preservePlayerModes";
static NSString * const SonoraSettingsTrackGapKey = @"sonora.settings.trackGapSeconds";
static NSString * const SonoraSettingsMyWaveLookKey = @"sonora.settings.myWaveLook";

static NSUserDefaults *SonoraSettingsDefaults(void) {
    return NSUserDefaults.standardUserDefaults;
}

NSString *SonoraSettingsAccentHex(void) {
    return [SonoraSettingsDefaults() stringForKey:SonoraSettingsAccentHexKey];
}

NSInteger SonoraSettingsLegacyAccentColorIndex(void) {
    return [SonoraSettingsDefaults() integerForKey:SonoraSettingsLegacyAccentColorKey];
}

void SonoraSettingsStoreAccentHex(NSString *hex) {
    NSUserDefaults *defaults = SonoraSettingsDefaults();
    [defaults setObject:hex forKey:SonoraSettingsAccentHexKey];
    [defaults removeObjectForKey:SonoraSettingsLegacyAccentColorKey];
}

NSInteger SonoraSettingsFontStyleIndex(void) {
    NSUserDefaults *defaults = SonoraSettingsDefaults();
    if ([defaults objectForKey:SonoraSettingsFontKey] == nil) {
        return 0;
    }
    return [defaults integerForKey:SonoraSettingsFontKey];
}

void SonoraSettingsSetFontStyleIndex(NSInteger value) {
    [SonoraSettingsDefaults() setInteger:value forKey:SonoraSettingsFontKey];
}

NSInteger SonoraSettingsArtworkStyleIndex(void) {
    NSUserDefaults *defaults = SonoraSettingsDefaults();
    if ([defaults objectForKey:SonoraSettingsArtworkStyleKey] == nil) {
        return 1;
    }
    return [defaults integerForKey:SonoraSettingsArtworkStyleKey];
}

void SonoraSettingsSetArtworkStyleIndex(NSInteger value) {
    [SonoraSettingsDefaults() setInteger:value forKey:SonoraSettingsArtworkStyleKey];
}

SonoraMyWaveLook SonoraSettingsMyWaveLook(void) {
    NSUserDefaults *defaults = SonoraSettingsDefaults();
    if ([defaults objectForKey:SonoraSettingsMyWaveLookKey] == nil) {
        return SonoraMyWaveLookContours;
    }
    return (SonoraMyWaveLook)[defaults integerForKey:SonoraSettingsMyWaveLookKey];
}

void SonoraSettingsSetMyWaveLook(SonoraMyWaveLook value) {
    [SonoraSettingsDefaults() setInteger:value forKey:SonoraSettingsMyWaveLookKey];
}

BOOL SonoraSettingsArtworkEqualizerEnabled(void) {
    NSUserDefaults *defaults = SonoraSettingsDefaults();
    if ([defaults objectForKey:SonoraSettingsArtworkEqualizerKey] == nil) {
        return YES;
    }
    return [defaults boolForKey:SonoraSettingsArtworkEqualizerKey];
}

void SonoraSettingsSetArtworkEqualizerEnabled(BOOL enabled) {
    [SonoraSettingsDefaults() setBool:enabled forKey:SonoraSettingsArtworkEqualizerKey];
}

BOOL SonoraSettingsPreservePlayerModesEnabled(void) {
    NSUserDefaults *defaults = SonoraSettingsDefaults();
    if ([defaults objectForKey:SonoraSettingsPreservePlayerModesKey] == nil) {
        return YES;
    }
    return [defaults boolForKey:SonoraSettingsPreservePlayerModesKey];
}

void SonoraSettingsSetPreservePlayerModesEnabled(BOOL enabled) {
    [SonoraSettingsDefaults() setBool:enabled forKey:SonoraSettingsPreservePlayerModesKey];
}

BOOL SonoraSettingsCacheOnlinePlaylistTracksEnabled(void) {
    NSUserDefaults *defaults = SonoraSettingsDefaults();
    if ([defaults objectForKey:SonoraSettingsCacheOnlinePlaylistTracksKey] == nil) {
        return NO;
    }
    return [defaults boolForKey:SonoraSettingsCacheOnlinePlaylistTracksKey];
}

void SonoraSettingsSetCacheOnlinePlaylistTracksEnabled(BOOL enabled) {
    [SonoraSettingsDefaults() setBool:enabled forKey:SonoraSettingsCacheOnlinePlaylistTracksKey];
}

NSTimeInterval SonoraSettingsTrackGapSeconds(void) {
    NSUserDefaults *defaults = SonoraSettingsDefaults();
    if ([defaults objectForKey:SonoraSettingsTrackGapKey] == nil) {
        return 0.0;
    }
    return [defaults doubleForKey:SonoraSettingsTrackGapKey];
}

void SonoraSettingsSetTrackGapSeconds(NSTimeInterval seconds) {
    [SonoraSettingsDefaults() setDouble:seconds forKey:SonoraSettingsTrackGapKey];
}

NSInteger SonoraSettingsMaxStorageMB(void) {
    NSUserDefaults *defaults = SonoraSettingsDefaults();
    if ([defaults objectForKey:SonoraSettingsMaxStorageMBKey] == nil) {
        return -1;
    }
    return [defaults integerForKey:SonoraSettingsMaxStorageMBKey];
}

void SonoraSettingsSetMaxStorageMB(NSInteger value) {
    [SonoraSettingsDefaults() setInteger:value forKey:SonoraSettingsMaxStorageMBKey];
}

NSInteger SonoraSettingsOnlinePlaylistCacheMaxMB(void) {
    NSUserDefaults *defaults = SonoraSettingsDefaults();
    if ([defaults objectForKey:SonoraSettingsOnlinePlaylistCacheMaxMBKey] == nil) {
        return 1024;
    }
    return [defaults integerForKey:SonoraSettingsOnlinePlaylistCacheMaxMBKey];
}

void SonoraSettingsSetOnlinePlaylistCacheMaxMB(NSInteger value) {
    [SonoraSettingsDefaults() setInteger:value forKey:SonoraSettingsOnlinePlaylistCacheMaxMBKey];
}
