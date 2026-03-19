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
static NSString * const SonoraSettingsStreamingSearchEngineKey = @"sonora.settings.streamingSearchEngine";
static NSString * const SonoraSettingsPlayerBackgroundModeKey = @"sonora.settings.playerBackgroundMode";
static NSString * const SonoraSettingsArtworkBasedPlayerBackgroundKey = @"sonora.settings.useArtworkBasedPlayerBackground";
static NSString * const SonoraSettingsAccentAppBackgroundKey = @"sonora.settings.useAccentAppBackground";
static NSString * const SonoraSettingsAppBackgroundHexKey = @"sonora.settings.appBackgroundHex";
static NSString * const SonoraSettingsAutoSaveStreamingSongsKey = @"sonora.settings.autoSaveStreamingSongs";

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

SonoraStreamingSearchEngine SonoraSettingsStreamingSearchEngine(void) {
    NSUserDefaults *defaults = SonoraSettingsDefaults();
    if ([defaults objectForKey:SonoraSettingsStreamingSearchEngineKey] == nil) {
        return SonoraStreamingSearchEngineSpotify;
    }
    NSInteger rawValue = [defaults integerForKey:SonoraSettingsStreamingSearchEngineKey];
    if (rawValue == SonoraStreamingSearchEngineYouTube) {
        return SonoraStreamingSearchEngineYouTube;
    }
    return SonoraStreamingSearchEngineSpotify;
}

void SonoraSettingsSetStreamingSearchEngine(SonoraStreamingSearchEngine value) {
    NSInteger rawValue = (value == SonoraStreamingSearchEngineYouTube)
        ? SonoraStreamingSearchEngineYouTube
        : SonoraStreamingSearchEngineSpotify;
    [SonoraSettingsDefaults() setInteger:rawValue forKey:SonoraSettingsStreamingSearchEngineKey];
}

SonoraPlayerBackgroundMode SonoraSettingsPlayerBackgroundMode(void) {
    NSUserDefaults *defaults = SonoraSettingsDefaults();
    if ([defaults objectForKey:SonoraSettingsPlayerBackgroundModeKey] != nil) {
        NSInteger rawValue = [defaults integerForKey:SonoraSettingsPlayerBackgroundModeKey];
        if (rawValue == SonoraPlayerBackgroundModeApp || rawValue == SonoraPlayerBackgroundModeArtwork) {
            return (SonoraPlayerBackgroundMode)rawValue;
        }
        return SonoraPlayerBackgroundModeSystem;
    }

    if ([defaults objectForKey:SonoraSettingsArtworkBasedPlayerBackgroundKey] != nil &&
        [defaults boolForKey:SonoraSettingsArtworkBasedPlayerBackgroundKey]) {
        return SonoraPlayerBackgroundModeArtwork;
    }
    return SonoraPlayerBackgroundModeSystem;
}

void SonoraSettingsSetPlayerBackgroundMode(SonoraPlayerBackgroundMode mode) {
    SonoraPlayerBackgroundMode normalized = SonoraPlayerBackgroundModeSystem;
    if (mode == SonoraPlayerBackgroundModeApp || mode == SonoraPlayerBackgroundModeArtwork) {
        normalized = mode;
    }
    NSUserDefaults *defaults = SonoraSettingsDefaults();
    [defaults setInteger:normalized forKey:SonoraSettingsPlayerBackgroundModeKey];
    [defaults setBool:(normalized == SonoraPlayerBackgroundModeArtwork)
               forKey:SonoraSettingsArtworkBasedPlayerBackgroundKey];
}

BOOL SonoraSettingsUseArtworkBasedPlayerBackgroundEnabled(void) {
    return SonoraSettingsPlayerBackgroundMode() == SonoraPlayerBackgroundModeArtwork;
}

void SonoraSettingsSetUseArtworkBasedPlayerBackgroundEnabled(BOOL enabled) {
    SonoraSettingsSetPlayerBackgroundMode(enabled ? SonoraPlayerBackgroundModeArtwork : SonoraPlayerBackgroundModeSystem);
}

BOOL SonoraSettingsUseAccentAppBackgroundEnabled(void) {
    NSUserDefaults *defaults = SonoraSettingsDefaults();
    if ([defaults objectForKey:SonoraSettingsAccentAppBackgroundKey] == nil) {
        return NO;
    }
    return [defaults boolForKey:SonoraSettingsAccentAppBackgroundKey];
}

void SonoraSettingsSetUseAccentAppBackgroundEnabled(BOOL enabled) {
    [SonoraSettingsDefaults() setBool:enabled forKey:SonoraSettingsAccentAppBackgroundKey];
}

NSString *SonoraSettingsAppBackgroundHex(void) {
    return [SonoraSettingsDefaults() stringForKey:SonoraSettingsAppBackgroundHexKey];
}

void SonoraSettingsStoreAppBackgroundHex(NSString * _Nullable hex) {
    NSUserDefaults *defaults = SonoraSettingsDefaults();
    NSString *trimmed = [[hex ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] copy];
    if (trimmed.length == 0) {
        [defaults removeObjectForKey:SonoraSettingsAppBackgroundHexKey];
    } else {
        [defaults setObject:trimmed forKey:SonoraSettingsAppBackgroundHexKey];
    }
    [defaults removeObjectForKey:SonoraSettingsAccentAppBackgroundKey];
}

BOOL SonoraSettingsAutoSaveStreamingSongsEnabled(void) {
    NSUserDefaults *defaults = SonoraSettingsDefaults();
    if ([defaults objectForKey:SonoraSettingsAutoSaveStreamingSongsKey] == nil) {
        return YES;
    }
    return [defaults boolForKey:SonoraSettingsAutoSaveStreamingSongsKey];
}

void SonoraSettingsSetAutoSaveStreamingSongsEnabled(BOOL enabled) {
    [SonoraSettingsDefaults() setBool:enabled forKey:SonoraSettingsAutoSaveStreamingSongsKey];
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
