//
//  SonoraMusicModule.m
//  Sonora
//

#import "SonoraMusicModule.h"

#import <limits.h>
#import <math.h>
#import <PhotosUI/PhotosUI.h>
#import <QuartzCore/QuartzCore.h>

#import "SonoraCells.h"
#import "SonoraServices.h"

static UIColor *SonoraLovelyAccentRedColor(void) {
    return [UIColor colorWithRed:0.90 green:0.12 blue:0.15 alpha:1.0];
}

static NSString * const SonoraLovelyPlaylistDefaultsKey = @"sonora_lovely_playlist_id_v1";
static NSString * const SonoraLovelyPlaylistCoverMarkerKey = @"sonora_lovely_playlist_cover_marker_v2";
static NSString * const SonoraSettingsFontKey = @"sonora.settings.font";
static NSString * const SonoraSettingsAccentHexKey = @"sonora.settings.accentHex";
static NSString * const SonoraSettingsLegacyAccentColorKey = @"sonora.settings.accentColor";
static NSString * const SonoraSettingsArtworkStyleKey = @"sonora.settings.artworkStyle";
static NSString * const SonoraSettingsArtworkEqualizerKey = @"sonora.settings.showArtworkEqualizer";
static NSString * const SonoraSettingsMaxStorageMBKey = @"sonora.settings.maxStorageMB";

typedef NS_ENUM(NSInteger, SonoraPlayerFontStyle) {
    SonoraPlayerFontStyleSystem = 0,
    SonoraPlayerFontStyleSerif = 1,
};

typedef NS_ENUM(NSInteger, SonoraPlayerArtworkStyle) {
    SonoraPlayerArtworkStyleSquare = 0,
    SonoraPlayerArtworkStyleRounded = 1,
};

static UIColor *SonoraDefaultAccentColor(void) {
    return [UIColor colorWithRed:1.0 green:0.83 blue:0.08 alpha:1.0];
}

static UIColor *SonoraLegacyAccentColorForIndex(NSInteger raw) {
    switch (raw) {
        case 1:
            return [UIColor colorWithRed:0.31 green:0.64 blue:1.0 alpha:1.0];
        case 2:
            return [UIColor colorWithRed:0.22 green:0.83 blue:0.62 alpha:1.0];
        case 3:
            return [UIColor colorWithRed:1.0 green:0.48 blue:0.40 alpha:1.0];
        case 0:
        default:
            return SonoraDefaultAccentColor();
    }
}

static UIColor *SonoraColorFromHexString(NSString *hexString) {
    if (hexString.length == 0) {
        return nil;
    }
    NSString *normalized = [[hexString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    if ([normalized hasPrefix:@"#"]) {
        normalized = [normalized substringFromIndex:1];
    }
    if (normalized.length != 6) {
        return nil;
    }

    unsigned int rgb = 0;
    if (![[NSScanner scannerWithString:normalized] scanHexInt:&rgb]) {
        return nil;
    }

    CGFloat red = ((rgb >> 16) & 0xFF) / 255.0;
    CGFloat green = ((rgb >> 8) & 0xFF) / 255.0;
    CGFloat blue = (rgb & 0xFF) / 255.0;
    return [UIColor colorWithRed:red green:green blue:blue alpha:1.0];
}

static UIColor *SonoraAccentYellowColor(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    UIColor *fromHex = SonoraColorFromHexString([defaults stringForKey:SonoraSettingsAccentHexKey]);
    if (fromHex != nil) {
        return fromHex;
    }
    return SonoraLegacyAccentColorForIndex([defaults integerForKey:SonoraSettingsLegacyAccentColorKey]);
}

static SonoraPlayerFontStyle SonoraPlayerFontStyleFromDefaults(void) {
    NSInteger raw = [NSUserDefaults.standardUserDefaults integerForKey:SonoraSettingsFontKey];
    if (raw < SonoraPlayerFontStyleSystem || raw > SonoraPlayerFontStyleSerif) {
        return SonoraPlayerFontStyleSystem;
    }
    return (SonoraPlayerFontStyle)raw;
}

static UIColor *SonoraPlayerBackgroundColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
        if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return UIColor.blackColor;
        }
        return UIColor.systemBackgroundColor;
    }];
}

static UIColor *SonoraPlayerPrimaryColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
        if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return UIColor.whiteColor;
        }
        return UIColor.labelColor;
    }];
}

static UIColor *SonoraPlayerSecondaryColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
        if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return [UIColor colorWithWhite:1.0 alpha:0.66];
        }
        return UIColor.secondaryLabelColor;
    }];
}

static UIColor *SonoraPlayerTimelineMaxColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
        if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return [UIColor colorWithWhite:1.0 alpha:0.24];
        }
        return [UIColor colorWithWhite:0.0 alpha:0.22];
    }];
}

static UIFont *SonoraHeadlineFont(CGFloat size) {
    UIFont *font = [UIFont fontWithName:@"YSMusic-HeadlineBold" size:size];
    if (font != nil) {
        return font;
    }
    return [UIFont boldSystemFontOfSize:size];
}

static UIFont *SonoraNewYorkFont(CGFloat size, UIFontWeight weight) {
    NSArray<NSString *> *candidates = @[@"NewYork-Regular"];
    if (weight >= UIFontWeightBold) {
        candidates = @[@"NewYork-Bold", @"NewYork-Semibold", @"NewYork-Medium", @"NewYork-Regular"];
    } else if (weight >= UIFontWeightSemibold) {
        candidates = @[@"NewYork-Semibold", @"NewYork-Medium", @"NewYork-Regular"];
    } else if (weight >= UIFontWeightMedium) {
        candidates = @[@"NewYork-Medium", @"NewYork-Regular"];
    }

    for (NSString *name in candidates) {
        UIFont *font = [UIFont fontWithName:name size:size];
        if (font != nil) {
            return font;
        }
    }

    UIFontDescriptor *baseDescriptor = [UIFont systemFontOfSize:size weight:weight].fontDescriptor;
    UIFontDescriptor *serifDescriptor = [baseDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignSerif];
    if (serifDescriptor != nil) {
        UIFont *font = [UIFont fontWithDescriptor:serifDescriptor size:size];
        if (font != nil) {
            return font;
        }
    }
    return [UIFont systemFontOfSize:size weight:weight];
}

static UIFont *SonoraPlayerFontForStyle(SonoraPlayerFontStyle style, CGFloat size, UIFontWeight weight) {
    switch (style) {
        case SonoraPlayerFontStyleSerif: {
            return SonoraNewYorkFont(size, weight);
        }
        case SonoraPlayerFontStyleSystem:
        default:
            return [UIFont systemFontOfSize:size weight:weight];
    }
}

static SonoraPlayerArtworkStyle SonoraPlayerArtworkStyleFromDefaults(void) {
    NSInteger raw = [NSUserDefaults.standardUserDefaults integerForKey:SonoraSettingsArtworkStyleKey];
    if (raw < SonoraPlayerArtworkStyleSquare || raw > SonoraPlayerArtworkStyleRounded) {
        return SonoraPlayerArtworkStyleRounded;
    }
    return (SonoraPlayerArtworkStyle)raw;
}

static BOOL SonoraArtworkEqualizerEnabledFromDefaults(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:SonoraSettingsArtworkEqualizerKey] == nil) {
        return YES;
    }
    return [defaults boolForKey:SonoraSettingsArtworkEqualizerKey];
}

static CGFloat SonoraArtworkCornerRadiusForStyle(SonoraPlayerArtworkStyle style, CGFloat width) {
    switch (style) {
        case SonoraPlayerArtworkStyleSquare:
            return 0.0;
        case SonoraPlayerArtworkStyleRounded:
        default:
            return MIN(26.0, width * 0.08);
    }
}

static UIImage *SonoraLovelySongsCoverImage(CGSize size) {
    UIImage *sourceImage = [UIImage imageNamed:@"LovelyCover"];
    if (sourceImage == nil) {
        sourceImage = [UIImage imageNamed:@"lovely-cover"];
    }

    CGSize normalizedSize = CGSizeMake(MAX(size.width, 240.0), MAX(size.height, 240.0));
    if (sourceImage == nil || sourceImage.size.width <= 1.0 || sourceImage.size.height <= 1.0) {
        sourceImage = [UIImage systemImageNamed:@"heart.fill"];
        if (sourceImage == nil) {
            return nil;
        }
    }

    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:normalizedSize];
    return [renderer imageWithActions:^(__unused UIGraphicsImageRendererContext * _Nonnull rendererContext) {
        [[UIColor colorWithRed:0.78 green:0.03 blue:0.08 alpha:1.0] setFill];
        UIRectFill(CGRectMake(0.0, 0.0, normalizedSize.width, normalizedSize.height));

        CGFloat scale = MAX(normalizedSize.width / sourceImage.size.width,
                            normalizedSize.height / sourceImage.size.height);
        CGSize drawSize = CGSizeMake(sourceImage.size.width * scale, sourceImage.size.height * scale);
        CGRect drawRect = CGRectMake((normalizedSize.width - drawSize.width) * 0.5,
                                     (normalizedSize.height - drawSize.height) * 0.5,
                                     drawSize.width,
                                     drawSize.height);
        [sourceImage drawInRect:drawRect];
    }];
}

static UILabel *SonoraWhiteSectionTitleLabel(NSString *text) {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.textColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
        if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return UIColor.whiteColor;
        }
        return UIColor.blackColor;
    }];
    label.font = SonoraHeadlineFont(28.0);
    [label sizeToFit];
    return label;
}

static void SonoraPresentAlert(UIViewController *controller, NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [controller presentViewController:alert animated:YES completion:nil];
}

static NSString *SonoraNormalizedSearchText(NSString *text) {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return trimmed.lowercaseString ?: @"";
}

static BOOL SonoraTrackMatchesSearchQuery(SonoraTrack *track, NSString *query) {
    if (query.length == 0) {
        return YES;
    }

    NSString *title = track.title.lowercaseString ?: @"";
    NSString *artist = track.artist.lowercaseString ?: @"";
    NSString *fileName = track.fileName.lowercaseString ?: @"";
    return ([title containsString:query] ||
            [artist containsString:query] ||
            [fileName containsString:query]);
}

static NSArray<SonoraTrack *> *SonoraFilterTracksByQuery(NSArray<SonoraTrack *> *tracks, NSString *query) {
    NSString *normalizedQuery = SonoraNormalizedSearchText(query);
    if (normalizedQuery.length == 0) {
        return tracks ?: @[];
    }

    NSMutableArray<SonoraTrack *> *filtered = [NSMutableArray arrayWithCapacity:tracks.count];
    for (SonoraTrack *track in tracks) {
        if (SonoraTrackMatchesSearchQuery(track, normalizedQuery)) {
            [filtered addObject:track];
        }
    }
    return [filtered copy];
}

static NSInteger SonoraIndexOfTrackByIdentifier(NSArray<SonoraTrack *> *tracks, NSString *trackID) {
    if (trackID.length == 0 || tracks.count == 0) {
        return NSNotFound;
    }

    for (NSUInteger idx = 0; idx < tracks.count; idx += 1) {
        SonoraTrack *track = tracks[idx];
        if ([track.identifier isEqualToString:trackID]) {
            return (NSInteger)idx;
        }
    }
    return NSNotFound;
}

static BOOL SonoraTrackQueuesMatchByIdentifier(NSArray<SonoraTrack *> *first, NSArray<SonoraTrack *> *second) {
    if (first.count != second.count) {
        return NO;
    }

    for (NSUInteger idx = 0; idx < first.count; idx += 1) {
        SonoraTrack *leftTrack = first[idx];
        SonoraTrack *rightTrack = second[idx];
        if (![leftTrack.identifier isEqualToString:rightTrack.identifier]) {
            return NO;
        }
    }
    return YES;
}

static NSArray<SonoraPlaylist *> *SonoraFilterPlaylistsByQuery(NSArray<SonoraPlaylist *> *playlists, NSString *query) {
    NSString *normalizedQuery = SonoraNormalizedSearchText(query);
    if (normalizedQuery.length == 0) {
        return playlists ?: @[];
    }

    NSMutableArray<SonoraPlaylist *> *filtered = [NSMutableArray arrayWithCapacity:playlists.count];
    for (SonoraPlaylist *playlist in playlists) {
        NSString *name = playlist.name.lowercaseString ?: @"";
        if ([name containsString:normalizedQuery]) {
            [filtered addObject:playlist];
        }
    }
    return [filtered copy];
}

static NSArray<NSString *> *SonoraArtistParticipantsFromText(NSString *artistText) {
    NSString *trimmed = [artistText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        return @[];
    }

    NSMutableArray<NSString *> *values = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSArray<NSString *> *chunks = [trimmed componentsSeparatedByString:@","];
    for (NSString *chunk in chunks) {
        NSString *value = [chunk stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *key = SonoraNormalizedSearchText(value);
        if (key.length == 0 || [seen containsObject:key]) {
            continue;
        }
        [seen addObject:key];
        [values addObject:value];
    }
    return values;
}

static NSArray<NSDictionary<NSString *, id> *> *SonoraBuildArtistSearchResults(NSArray<SonoraTrack *> *tracks,
                                                                            NSString *query,
                                                                            NSUInteger limit) {
    NSString *normalizedQuery = SonoraNormalizedSearchText(query);
    if (tracks.count == 0 || limit == 0) {
        return @[];
    }

    NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, id> *> *artistsByKey = [NSMutableDictionary dictionary];
    for (SonoraTrack *track in tracks) {
        NSArray<NSString *> *participants = SonoraArtistParticipantsFromText(track.artist ?: @"");
        for (NSString *participant in participants) {
            NSString *key = SonoraNormalizedSearchText(participant);
            if (normalizedQuery.length > 0 && ![key containsString:normalizedQuery]) {
                continue;
            }

            NSMutableDictionary<NSString *, id> *entry = artistsByKey[key];
            if (entry == nil) {
                entry = [@{
                    @"key": key,
                    @"title": participant,
                    @"tracks": [NSMutableArray array]
                } mutableCopy];
                artistsByKey[key] = entry;
            }
            NSMutableArray<SonoraTrack *> *matchedTracks = entry[@"tracks"];
            if (matchedTracks == nil) {
                matchedTracks = [NSMutableArray array];
                entry[@"tracks"] = matchedTracks;
            }
            BOOL alreadyIncluded = NO;
            for (SonoraTrack *existing in matchedTracks) {
                if ([existing.identifier isEqualToString:track.identifier]) {
                    alreadyIncluded = YES;
                    break;
                }
            }
            if (!alreadyIncluded) {
                [matchedTracks addObject:track];
            }
        }
    }

    NSArray<NSDictionary<NSString *, id> *> *sorted = [artistsByKey.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary<NSString *,id> * _Nonnull left,
                                                                                                                             NSDictionary<NSString *,id> * _Nonnull right) {
        NSArray *leftTracks = left[@"tracks"];
        NSArray *rightTracks = right[@"tracks"];
        if (leftTracks.count > rightTracks.count) {
            return NSOrderedAscending;
        }
        if (leftTracks.count < rightTracks.count) {
            return NSOrderedDescending;
        }
        NSString *leftTitle = left[@"title"] ?: @"";
        NSString *rightTitle = right[@"title"] ?: @"";
        return [leftTitle localizedCaseInsensitiveCompare:rightTitle];
    }];

    if (sorted.count <= limit) {
        return sorted;
    }
    return [sorted subarrayWithRange:NSMakeRange(0, limit)];
}

static UISearchController *SonoraBuildSearchController(id<UISearchResultsUpdating> updater, NSString *placeholder) {
    UISearchController *searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    searchController.obscuresBackgroundDuringPresentation = NO;
    searchController.hidesNavigationBarDuringPresentation = NO;
    searchController.searchResultsUpdater = updater;
    searchController.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    searchController.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    if (placeholder.length > 0) {
        searchController.searchBar.placeholder = placeholder;
    }
    return searchController;
}

static CGFloat SonoraSearchPullDistance(UIScrollView *scrollView) {
    if (scrollView == nil) {
        return 0.0;
    }
    CGFloat topEdge = -scrollView.adjustedContentInset.top;
    return MAX(0.0, topEdge - scrollView.contentOffset.y);
}

static CGFloat const SonoraSearchRevealThreshold = 62.0;
static CGFloat const SonoraSearchDismissThreshold = 40.0;

static BOOL SonoraShouldAttachSearchController(BOOL currentlyAttached,
                                           UISearchController *searchController,
                                           UIScrollView *scrollView,
                                           CGFloat revealThreshold) {
    if (searchController == nil || scrollView == nil) {
        return NO;
    }

    BOOL hasQuery = searchController.searchBar.text.length > 0;
    if (currentlyAttached) {
        if (searchController.isActive || hasQuery) {
            return YES;
        }

        CGFloat topEdge = -scrollView.adjustedContentInset.top;
        BOOL scrolledIntoContent = (scrollView.contentOffset.y > topEdge + SonoraSearchDismissThreshold);
        return !scrolledIntoContent;
    }

    CGFloat pullDistance = SonoraSearchPullDistance(scrollView);
    return (pullDistance >= revealThreshold);
}

static void SonoraApplySearchControllerAttachment(UINavigationItem *navigationItem,
                                              UINavigationBar *navigationBar,
                                              UISearchController *searchController,
                                              BOOL shouldAttach,
                                              BOOL animated) {
    if (navigationItem == nil) {
        return;
    }

    UISearchController *targetController = shouldAttach ? searchController : nil;
    if (navigationItem.searchController == targetController) {
        return;
    }

    if (animated && navigationBar != nil) {
        [UIView transitionWithView:navigationBar
                          duration:0.20
                           options:(UIViewAnimationOptionTransitionCrossDissolve |
                                    UIViewAnimationOptionAllowUserInteraction |
                                    UIViewAnimationOptionBeginFromCurrentState)
                        animations:^{
            navigationItem.searchController = targetController;
            [navigationBar layoutIfNeeded];
        }
                        completion:nil];
        return;
    }

    navigationItem.searchController = targetController;
}

static void SonoraPresentQuickAddTrackToPlaylist(UIViewController *controller,
                                             NSString *trackID,
                                             dispatch_block_t completionHandler) {
    if (controller == nil || trackID.length == 0) {
        return;
    }

    [SonoraPlaylistStore.sharedStore reloadPlaylists];
    NSArray<SonoraPlaylist *> *playlists = SonoraPlaylistStore.sharedStore.playlists;
    if (playlists.count == 0) {
        SonoraPresentAlert(controller, @"No Playlists", @"Create a playlist first.");
        return;
    }

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Add To Playlist"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (SonoraPlaylist *playlist in playlists) {
        BOOL alreadyContains = [playlist.trackIDs containsObject:trackID];
        NSString *title = playlist.name ?: @"Playlist";
        if (alreadyContains) {
            title = [title stringByAppendingString:@"  ✓"];
        }

        UIAlertAction *action = [UIAlertAction actionWithTitle:title
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(__unused UIAlertAction * _Nonnull selectedAction) {
            BOOL added = [SonoraPlaylistStore.sharedStore addTrackIDs:@[trackID] toPlaylistID:playlist.playlistID];
            if (!added) {
                SonoraPresentAlert(controller, @"Already Added", @"Track already exists in that playlist.");
                return;
            }
            if (completionHandler != nil) {
                completionHandler();
            }
        }];
        action.enabled = !alreadyContains;
        [sheet addAction:action];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover != nil) {
        popover.sourceView = controller.view;
        popover.sourceRect = CGRectMake(CGRectGetMidX(controller.view.bounds),
                                        CGRectGetMidY(controller.view.bounds),
                                        1.0,
                                        1.0);
    }

    [controller presentViewController:sheet animated:YES completion:nil];
}

static UIButton *SonoraPlainIconButton(NSString *symbolName, CGFloat symbolSize, CGFloat weightValue) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;

    UIImageSymbolWeight weight = UIImageSymbolWeightRegular;
    if (weightValue >= 700.0) {
        weight = UIImageSymbolWeightBold;
    } else if (weightValue >= 600.0) {
        weight = UIImageSymbolWeightSemibold;
    }

    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:symbolSize
                                                                                           weight:weight];
    [button setImage:[UIImage systemImageNamed:symbolName withConfiguration:config] forState:UIControlStateNormal];
    button.tintColor = SonoraPlayerPrimaryColor();
    button.backgroundColor = UIColor.clearColor;
    return button;
}

static UIImage *SonoraSliderThumbImage(CGFloat diameter, UIColor *color) {
    CGFloat normalizedDiameter = MAX(2.0, diameter);
    CGSize size = CGSizeMake(normalizedDiameter + 2.0, normalizedDiameter + 2.0);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    return [renderer imageWithActions:^(__unused UIGraphicsImageRendererContext * _Nonnull context) {
        CGRect circleRect = CGRectMake(1.0, 1.0, normalizedDiameter, normalizedDiameter);
        [color setFill];
        UIBezierPath *path = [UIBezierPath bezierPathWithOvalInRect:circleRect];
        [path fill];
    }];
}

static NSString *SonoraSleepTimerRemainingString(NSTimeInterval interval) {
    NSInteger totalSeconds = (NSInteger)llround(MAX(0.0, interval));
    NSInteger hours = totalSeconds / 3600;
    NSInteger minutes = (totalSeconds % 3600) / 60;
    NSInteger seconds = totalSeconds % 60;

    if (hours > 0) {
        return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)hours, (long)minutes, (long)seconds];
    }
    return [NSString stringWithFormat:@"%ld:%02ld", (long)minutes, (long)seconds];
}

static NSTimeInterval SonoraSleepTimerDurationFromInput(NSString *input) {
    NSString *trimmed = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        return 0.0;
    }

    NSArray<NSString *> *colonParts = [trimmed componentsSeparatedByString:@":"];
    if (colonParts.count == 2 || colonParts.count == 3) {
        NSMutableArray<NSNumber *> *values = [NSMutableArray arrayWithCapacity:colonParts.count];
        for (NSString *part in colonParts) {
            NSString *token = [part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (token.length == 0) {
                return 0.0;
            }

            NSScanner *scanner = [NSScanner scannerWithString:token];
            NSInteger value = 0;
            if (![scanner scanInteger:&value] || !scanner.isAtEnd || value < 0) {
                return 0.0;
            }
            [values addObject:@(value)];
        }

        NSTimeInterval duration = 0.0;
        if (values.count == 2) {
            NSInteger hours = values[0].integerValue;
            NSInteger minutes = values[1].integerValue;
            if (minutes >= 60) {
                return 0.0;
            }
            duration = (NSTimeInterval)(hours * 3600 + minutes * 60);
        } else {
            NSInteger hours = values[0].integerValue;
            NSInteger minutes = values[1].integerValue;
            NSInteger seconds = values[2].integerValue;
            if (minutes >= 60 || seconds >= 60) {
                return 0.0;
            }
            duration = (NSTimeInterval)(hours * 3600 + minutes * 60 + seconds);
        }

        if (duration <= 0.0 || duration > 24.0 * 3600.0) {
            return 0.0;
        }
        return duration;
    }

    NSScanner *scanner = [NSScanner scannerWithString:trimmed];
    double minutesValue = 0.0;
    if (![scanner scanDouble:&minutesValue] || !scanner.isAtEnd) {
        return 0.0;
    }

    NSTimeInterval duration = minutesValue * 60.0;
    if (!isfinite(duration) || duration <= 0.0 || duration > 24.0 * 3600.0) {
        return 0.0;
    }
    return duration;
}

static void SonoraPresentCustomSleepTimerAlert(UIViewController *controller, dispatch_block_t updateHandler) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Custom Sleep Timer"
                                                                   message:@"Enter minutes (e.g. 25) or h:mm (e.g. 1:30)."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"25 or 1:30";
        textField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        NSTimeInterval remaining = SonoraSleepTimerManager.sharedManager.remainingTime;
        if (remaining > 0.0) {
            textField.text = [NSString stringWithFormat:@"%.0f", ceil(remaining / 60.0)];
        }
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Set Timer"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction * _Nonnull action) {
        NSString *rawValue = alert.textFields.firstObject.text ?: @"";
        NSTimeInterval duration = SonoraSleepTimerDurationFromInput(rawValue);
        if (duration <= 0.0) {
            SonoraPresentAlert(controller,
                           @"Invalid Time",
                           @"Use minutes (25) or h:mm (1:30). Max is 24 hours.");
            return;
        }

        [SonoraSleepTimerManager.sharedManager startWithDuration:duration];
        if (updateHandler != nil) {
            updateHandler();
        }
    }]];

    [controller presentViewController:alert animated:YES completion:nil];
}

static void SonoraPresentSleepTimerActionSheet(UIViewController *controller,
                                           UIView *sourceView,
                                           dispatch_block_t updateHandler) {
    SonoraSleepTimerManager *sleepTimer = SonoraSleepTimerManager.sharedManager;
    NSString *message = sleepTimer.isActive
    ? [NSString stringWithFormat:@"Will stop playback in %@.", SonoraSleepTimerRemainingString(sleepTimer.remainingTime)]
    : @"Stop playback automatically after selected time.";

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Sleep Timer"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    NSArray<NSNumber *> *durations = @[@(15 * 60), @(30 * 60), @(45 * 60), @(60 * 60)];
    for (NSNumber *durationValue in durations) {
        NSInteger minutes = durationValue.integerValue / 60;
        NSString *title = [NSString stringWithFormat:@"%ld min", (long)minutes];
        [sheet addAction:[UIAlertAction actionWithTitle:title
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction * _Nonnull action) {
            [SonoraSleepTimerManager.sharedManager startWithDuration:durationValue.doubleValue];
            if (updateHandler != nil) {
                updateHandler();
            }
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Custom..."
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction * _Nonnull action) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SonoraPresentCustomSleepTimerAlert(controller, updateHandler);
        });
    }]];

    if (sleepTimer.isActive) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Turn Off Sleep Timer"
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(__unused UIAlertAction * _Nonnull action) {
            [SonoraSleepTimerManager.sharedManager cancel];
            if (updateHandler != nil) {
                updateHandler();
            }
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover != nil) {
        UIView *anchorView = sourceView ?: controller.view;
        popover.sourceView = anchorView;
        popover.sourceRect = anchorView.bounds;
    }

    [controller presentViewController:sheet animated:YES completion:nil];
}

@interface SonoraPlayerViewController : UIViewController
@end

@interface SonoraPlaylistNameViewController : UIViewController
@end

@interface SonoraPlaylistTrackPickerViewController : UIViewController
- (instancetype)initWithPlaylistName:(NSString *)playlistName tracks:(NSArray<SonoraTrack *> *)tracks;
@end

@interface SonoraPlaylistAddTracksViewController : UIViewController
- (instancetype)initWithPlaylistID:(NSString *)playlistID;
@end

@interface SonoraPlaylistCoverPickerViewController : UIViewController <PHPickerViewControllerDelegate>
- (instancetype)initWithPlaylistID:(NSString *)playlistID;
@end

@interface SonoraPlaylistDetailViewController : UIViewController
- (instancetype)initWithPlaylistID:(NSString *)playlistID;
@end

#pragma mark - Music

typedef NS_ENUM(NSInteger, SonoraSearchSectionType) {
    SonoraSearchSectionTypePlaylists = 0,
    SonoraSearchSectionTypeArtists = 1,
    SonoraSearchSectionTypeTracks = 2,
};

static NSString * const SonoraMusicSearchCardCellReuseID = @"SonoraMusicSearchCardCell";
static NSString * const SonoraMusicSearchHeaderReuseID = @"SonoraMusicSearchHeader";

@interface SonoraMusicSearchCardCell : UICollectionViewCell

- (void)configureWithTitle:(NSString *)title subtitle:(NSString *)subtitle image:(UIImage * _Nullable)image;

@end

@interface SonoraMusicSearchCardCell ()

@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;

@end

@implementation SonoraMusicSearchCardCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.contentView.backgroundColor = UIColor.clearColor;

    UIImageView *coverView = [[UIImageView alloc] init];
    coverView.translatesAutoresizingMaskIntoConstraints = NO;
    coverView.contentMode = UIViewContentModeScaleAspectFill;
    coverView.clipsToBounds = YES;
    coverView.layer.cornerRadius = 12.0;
    self.coverView = coverView;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
    titleLabel.textColor = UIColor.labelColor;
    titleLabel.numberOfLines = 1;
    self.titleLabel = titleLabel;

    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular];
    subtitleLabel.textColor = UIColor.secondaryLabelColor;
    subtitleLabel.numberOfLines = 1;
    self.subtitleLabel = subtitleLabel;

    [self.contentView addSubview:coverView];
    [self.contentView addSubview:titleLabel];
    [self.contentView addSubview:subtitleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [coverView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
        [coverView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [coverView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [coverView.heightAnchor constraintEqualToAnchor:coverView.widthAnchor],

        [titleLabel.topAnchor constraintEqualToAnchor:coverView.bottomAnchor constant:8.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],

        [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:2.0],
        [subtitleLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [subtitleLabel.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor]
    ]];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.coverView.image = nil;
    self.coverView.tintColor = nil;
    self.coverView.backgroundColor = UIColor.clearColor;
    self.coverView.contentMode = UIViewContentModeScaleAspectFill;
    self.titleLabel.text = nil;
    self.subtitleLabel.text = nil;
}

- (void)configureWithTitle:(NSString *)title subtitle:(NSString *)subtitle image:(UIImage * _Nullable)image {
    self.titleLabel.text = title ?: @"";
    self.subtitleLabel.text = subtitle ?: @"";
    if (image != nil) {
        self.coverView.contentMode = UIViewContentModeScaleAspectFill;
        self.coverView.image = image;
    } else {
        UIImage *placeholder = [UIImage systemImageNamed:@"music.note"];
        self.coverView.contentMode = UIViewContentModeCenter;
        self.coverView.image = placeholder;
        self.coverView.tintColor = UIColor.secondaryLabelColor;
        self.coverView.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
            if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
                return [UIColor colorWithWhite:1.0 alpha:0.08];
            }
            return [UIColor colorWithWhite:0.0 alpha:0.04];
        }];
    }
}

@end

@interface SonoraMusicSearchHeaderView : UICollectionReusableView

- (void)configureWithTitle:(NSString *)title;

@end

@interface SonoraMusicSearchHeaderView ()

@property (nonatomic, strong) UILabel *titleLabel;

@end

@implementation SonoraMusicSearchHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        UILabel *label = [[UILabel alloc] init];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.font = SonoraHeadlineFont(24.0);
        label.textColor = UIColor.labelColor;
        self.titleLabel = label;
        [self addSubview:label];
        [NSLayoutConstraint activateConstraints:@[
            [label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:0.0],
            [label.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-2.0]
        ]];
    }
    return self;
}

- (void)configureWithTitle:(NSString *)title {
    self.titleLabel.text = title ?: @"";
}

@end

@interface SonoraMusicViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating, UICollectionViewDataSource, UICollectionViewDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UICollectionView *searchCollectionView;
@property (nonatomic, copy) NSArray<SonoraTrack *> *tracks;
@property (nonatomic, copy) NSArray<SonoraTrack *> *filteredTracks;
@property (nonatomic, copy) NSArray<SonoraPlaylist *> *playlists;
@property (nonatomic, copy) NSArray<SonoraPlaylist *> *filteredPlaylists;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *artistResults;
@property (nonatomic, copy) NSArray<NSNumber *> *visibleSections;
@property (nonatomic, copy) NSString *searchQuery;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, assign) BOOL searchControllerAttached;
@property (nonatomic, assign) BOOL musicOnlyMode;
@property (nonatomic, assign) BOOL multiSelectMode;
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *selectedTrackIDs;
@property (nonatomic, strong) UILongPressGestureRecognizer *selectionLongPressRecognizer;

@end

@implementation SonoraMusicViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    NSString *pageTitle = self.musicOnlyMode ? @"Music" : @"Search";
    self.title = pageTitle;
    self.navigationItem.title = nil;
    self.navigationItem.titleView = nil;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:SonoraWhiteSectionTitleLabel(pageTitle)];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    if (self.musicOnlyMode) {
        self.navigationItem.hidesBackButton = YES;
    }

    if (self.musicOnlyMode) {
        UISwipeGestureRecognizer *swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleDismissSwipe)];
        swipeRight.direction = UISwipeGestureRecognizerDirectionRight;
        [self.view addGestureRecognizer:swipeRight];
    }

    [self setupTableView];
    [self setupSearchCollectionView];
    [self setupSearch];
    [self updatePresentationMode];
    self.multiSelectMode = NO;
    self.selectedTrackIDs = [NSMutableOrderedSet orderedSet];

    [self refreshNavigationItemsForMusicSelectionState];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handlePlaybackChanged)
                                               name:SonoraPlaybackStateDidChangeNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(reloadTracks)
                                               name:UIApplicationWillEnterForegroundNotification
                                             object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handlePlaylistsChanged)
                                               name:SonoraPlaylistsDidChangeNotification
                                             object:nil];

    [self reloadTracks];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.musicOnlyMode) {
        self.navigationItem.hidesBackButton = YES;
        self.navigationController.interactivePopGestureRecognizer.enabled = YES;
        self.navigationController.interactivePopGestureRecognizer.delegate = nil;
    }
    [self refreshNavigationItemsForMusicSelectionState];
    [self updatePresentationMode];
    [self updateSearchControllerAttachment];
    [self.tableView reloadData];
    [self.searchCollectionView reloadData];
}

- (void)handleDismissSwipe {
    if (self.navigationController) {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (void)setupTableView {
    UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    tableView.translatesAutoresizingMaskIntoConstraints = NO;
    tableView.dataSource = self;
    tableView.delegate = self;
    tableView.rowHeight = 54.0;
    tableView.alwaysBounceVertical = YES;
    tableView.sectionHeaderHeight = 0.0;
    tableView.sectionFooterHeight = 0.0;
    tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    if (@available(iOS 15.0, *)) {
        tableView.sectionHeaderTopPadding = 0.0;
    }
    [tableView registerClass:SonoraTrackCell.class forCellReuseIdentifier:@"MusicTrackCell"];
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                                                             action:@selector(handleTrackLongPress:)];
    [tableView addGestureRecognizer:longPress];
    self.selectionLongPressRecognizer = longPress;

    self.tableView = tableView;
    [self.view addSubview:tableView];

    [NSLayoutConstraint activateConstraints:@[
        [tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)setupSearchCollectionView {
    UICollectionViewCompositionalLayout *layout = [self buildSearchCollectionLayout];
    UICollectionView *collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    collectionView.backgroundColor = UIColor.systemBackgroundColor;
    collectionView.alwaysBounceVertical = YES;
    collectionView.dataSource = self;
    collectionView.delegate = self;

    [collectionView registerClass:SonoraMusicSearchCardCell.class forCellWithReuseIdentifier:SonoraMusicSearchCardCellReuseID];
    [collectionView registerClass:SonoraMusicSearchHeaderView.class
       forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
              withReuseIdentifier:SonoraMusicSearchHeaderReuseID];

    self.searchCollectionView = collectionView;
    [self.view addSubview:collectionView];

    [NSLayoutConstraint activateConstraints:@[
        [collectionView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)updatePresentationMode {
    self.tableView.hidden = !self.musicOnlyMode;
    self.searchCollectionView.hidden = self.musicOnlyMode;
}

- (UICollectionViewCompositionalLayout *)buildSearchCollectionLayout {
    __weak typeof(self) weakSelf = self;
    return [[UICollectionViewCompositionalLayout alloc] initWithSectionProvider:^NSCollectionLayoutSection * _Nullable(NSInteger sectionIndex,
                                                                                                                        __unused id<NSCollectionLayoutEnvironment> _Nonnull environment) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return nil;
        }
        return [strongSelf searchSectionLayout];
    }];
}

- (NSCollectionLayoutSection *)searchSectionLayout {
    NSCollectionLayoutSize *itemSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:184.0]
                                                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:246.0]];
    NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];

    NSCollectionLayoutSize *groupSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:184.0]
                                                                        heightDimension:[NSCollectionLayoutDimension absoluteDimension:246.0]];
    NSCollectionLayoutGroup *group = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize subitems:@[item]];

    NSCollectionLayoutSection *section = [NSCollectionLayoutSection sectionWithGroup:group];
    section.interGroupSpacing = 12.0;
    section.contentInsets = NSDirectionalEdgeInsetsMake(10.0, 18.0, 12.0, 18.0);
    section.orthogonalScrollingBehavior = UICollectionLayoutSectionOrthogonalScrollingBehaviorContinuousGroupLeadingBoundary;

    NSCollectionLayoutSize *headerSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                                                         heightDimension:[NSCollectionLayoutDimension estimatedDimension:36.0]];
    NSCollectionLayoutBoundarySupplementaryItem *header = [NSCollectionLayoutBoundarySupplementaryItem
                                                           boundarySupplementaryItemWithLayoutSize:headerSize
                                                           elementKind:UICollectionElementKindSectionHeader
                                                           alignment:NSRectAlignmentTop];
    header.contentInsets = NSDirectionalEdgeInsetsMake(0.0, 10.0, 0.0, 18.0);
    section.boundarySupplementaryItems = @[header];
    return section;
}

- (void)setupSearch {
    self.searchController = SonoraBuildSearchController(self, @"Search");
    self.definesPresentationContext = YES;
    if (self.musicOnlyMode) {
        self.navigationItem.searchController = nil;
        self.navigationItem.hidesSearchBarWhenScrolling = YES;
        self.searchControllerAttached = NO;
    } else {
        self.navigationItem.searchController = self.searchController;
        self.navigationItem.hidesSearchBarWhenScrolling = NO;
        self.searchControllerAttached = YES;
    }
}

- (void)updateSearchControllerAttachment {
    if (!self.musicOnlyMode) {
        if (!self.searchControllerAttached || self.navigationItem.searchController != self.searchController) {
            self.searchControllerAttached = YES;
            SonoraApplySearchControllerAttachment(self.navigationItem,
                                              self.navigationController.navigationBar,
                                              self.searchController,
                                              YES,
                                              (self.view.window != nil));
        }
        return;
    }

    UIScrollView *targetScroll = self.musicOnlyMode ? self.tableView : self.searchCollectionView;
    BOOL shouldAttach = SonoraShouldAttachSearchController(self.searchControllerAttached,
                                                       self.searchController,
                                                       targetScroll,
                                                       SonoraSearchRevealThreshold);
    if (shouldAttach == self.searchControllerAttached) {
        return;
    }

    self.searchControllerAttached = shouldAttach;
    SonoraApplySearchControllerAttachment(self.navigationItem,
                                      self.navigationController.navigationBar,
                                      self.searchController,
                                      shouldAttach,
                                      (self.view.window != nil));
}

- (void)applySearchFilterAndReload {
    NSString *normalizedQuery = SonoraNormalizedSearchText(self.searchQuery);
    self.playlists = SonoraPlaylistStore.sharedStore.playlists ?: @[];
    if (self.musicOnlyMode) {
        self.filteredTracks = SonoraFilterTracksByQuery(self.tracks, self.searchQuery);
        self.filteredPlaylists = @[];
        self.artistResults = @[];
    } else {
        NSArray<SonoraTrack *> *queryTracks = SonoraFilterTracksByQuery(self.tracks, self.searchQuery);
        if (normalizedQuery.length == 0) {
            NSArray<SonoraTrack *> *affinityTracks = [SonoraTrackAnalyticsStore.sharedStore tracksSortedByAffinity:self.tracks] ?: @[];
            queryTracks = affinityTracks.count > 0 ? affinityTracks : self.tracks;
        }
        if (queryTracks.count > 24) {
            self.filteredTracks = [queryTracks subarrayWithRange:NSMakeRange(0, 24)];
        } else {
            self.filteredTracks = queryTracks;
        }

        self.filteredPlaylists = SonoraFilterPlaylistsByQuery(self.playlists, self.searchQuery);
        if (self.filteredPlaylists.count > 10) {
            self.filteredPlaylists = [self.filteredPlaylists subarrayWithRange:NSMakeRange(0, 10)];
        }
        self.artistResults = SonoraBuildArtistSearchResults(self.tracks, self.searchQuery, 12);
    }

    NSMutableArray<NSNumber *> *sections = [NSMutableArray array];
    if (self.musicOnlyMode) {
        [sections addObject:@(SonoraSearchSectionTypeTracks)];
    } else {
        if (self.filteredPlaylists.count > 0) {
            [sections addObject:@(SonoraSearchSectionTypePlaylists)];
        }
        if (self.artistResults.count > 0) {
            [sections addObject:@(SonoraSearchSectionTypeArtists)];
        }
        if (self.filteredTracks.count > 0) {
            [sections addObject:@(SonoraSearchSectionTypeTracks)];
        }
    }
    self.visibleSections = [sections copy];

    [self.tableView reloadData];
    [self.searchCollectionView reloadData];
    [self updateEmptyState];
}

- (void)updateEmptyState {
    BOOL hasAnyResult = (self.filteredTracks.count > 0 ||
                         self.filteredPlaylists.count > 0 ||
                         self.artistResults.count > 0);
    if (hasAnyResult) {
        self.tableView.backgroundView = nil;
        self.searchCollectionView.backgroundView = nil;
        return;
    }

    UILabel *label = [[UILabel alloc] init];
    label.textColor = UIColor.secondaryLabelColor;
    label.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;

    if (self.tracks.count == 0) {
        label.text = @"No music files in On My iPhone/Sonora/Sonora";
    } else {
        label.text = @"No search results.";
    }
    if (self.musicOnlyMode) {
        self.tableView.backgroundView = label;
        self.searchCollectionView.backgroundView = nil;
    } else {
        self.searchCollectionView.backgroundView = label;
        self.tableView.backgroundView = nil;
    }
}

- (void)reloadTracks {
    self.tracks = [SonoraLibraryManager.sharedManager reloadTracks];
    [SonoraPlaylistStore.sharedStore reloadPlaylists];
    self.playlists = SonoraPlaylistStore.sharedStore.playlists ?: @[];
    [self applySearchFilterAndReload];
}

- (void)handlePlaylistsChanged {
    [SonoraPlaylistStore.sharedStore reloadPlaylists];
    self.playlists = SonoraPlaylistStore.sharedStore.playlists ?: @[];
    [self applySearchFilterAndReload];
}

- (void)handlePlaybackChanged {
    [self.tableView reloadData];
}

- (void)openPlayer {
    SonoraPlayerViewController *player = [[SonoraPlayerViewController alloc] init];
    player.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:player animated:YES];
}

- (void)searchButtonTapped {
    if (self.searchController == nil) {
        return;
    }

    if (!self.searchControllerAttached) {
        self.searchControllerAttached = YES;
        SonoraApplySearchControllerAttachment(self.navigationItem,
                                          self.navigationController.navigationBar,
                                          self.searchController,
                                          YES,
                                          (self.view.window != nil));
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        self.searchController.active = YES;
        [self.searchController.searchBar becomeFirstResponder];
    });
}

- (void)addMusicTapped {
    if ([self isLibraryAtOrAboveStorageLimit]) {
        [self presentStorageLimitReachedAlert];
        return;
    }
    [self reloadTracks];
}

- (unsigned long long)currentLibraryUsageBytes {
    NSURL *musicDirectoryURL = [SonoraLibraryManager.sharedManager musicDirectoryURL];
    if (musicDirectoryURL == nil) {
        return 0ULL;
    }
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSDirectoryEnumerator<NSURL *> *enumerator =
    [fileManager enumeratorAtURL:musicDirectoryURL
      includingPropertiesForKeys:@[NSURLIsRegularFileKey, NSURLFileSizeKey]
                         options:NSDirectoryEnumerationSkipsHiddenFiles
                    errorHandler:nil];
    unsigned long long totalBytes = 0ULL;
    for (NSURL *fileURL in enumerator) {
        NSNumber *isRegularFile = nil;
        [fileURL getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:nil];
        if (!isRegularFile.boolValue) {
            continue;
        }
        NSNumber *fileSize = nil;
        [fileURL getResourceValue:&fileSize forKey:NSURLFileSizeKey error:nil];
        totalBytes += fileSize.unsignedLongLongValue;
    }
    return totalBytes;
}

- (unsigned long long)maxLibraryStorageBytes {
    NSInteger raw = [NSUserDefaults.standardUserDefaults integerForKey:SonoraSettingsMaxStorageMBKey];
    NSInteger valueMB = raw;
    if (valueMB <= 0) {
        return ULLONG_MAX;
    }
    NSArray<NSNumber *> *allowed = @[@512, @1024, @2048, @3072, @4096, @6144, @8192];
    NSInteger nearest = allowed.firstObject.integerValue;
    NSInteger delta = labs(valueMB - nearest);
    for (NSNumber *candidate in allowed) {
        NSInteger current = candidate.integerValue;
        NSInteger currentDelta = labs(valueMB - current);
        if (currentDelta < delta) {
            delta = currentDelta;
            nearest = current;
        }
    }
    return ((unsigned long long)nearest) * 1024ULL * 1024ULL;
}

- (BOOL)isLibraryAtOrAboveStorageLimit {
    unsigned long long maxBytes = [self maxLibraryStorageBytes];
    if (maxBytes == ULLONG_MAX) {
        return NO;
    }
    return [self currentLibraryUsageBytes] >= maxBytes;
}

- (void)presentStorageLimitReachedAlert {
    unsigned long long usedBytes = [self currentLibraryUsageBytes];
    unsigned long long maxBytes = [self maxLibraryStorageBytes];
    if (maxBytes == ULLONG_MAX) {
        return;
    }
    NSString *usedText = [NSByteCountFormatter stringFromByteCount:(long long)usedBytes
                                                        countStyle:NSByteCountFormatterCountStyleFile];
    NSString *maxText = [NSByteCountFormatter stringFromByteCount:(long long)maxBytes
                                                       countStyle:NSByteCountFormatterCountStyleFile];
    NSString *message = [NSString stringWithFormat:@"Library size %@ reached/over max %@.\nAdding music is blocked until you free space or increase Max player space in Settings.",
                         usedText,
                         maxText];
    SonoraPresentAlert(self, @"Storage limit reached", message);
}

- (void)refreshNavigationItemsForMusicSelectionState {
    NSString *pageTitle = self.musicOnlyMode ? @"Music" : @"Search";
    NSString *displayTitle = self.multiSelectMode
    ? [NSString stringWithFormat:@"%lu Selected", (unsigned long)self.selectedTrackIDs.count]
    : pageTitle;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:SonoraWhiteSectionTitleLabel(displayTitle)];

    if (!self.musicOnlyMode) {
        self.navigationItem.rightBarButtonItems = nil;
        return;
    }

    if (self.multiSelectMode) {
        UIBarButtonItem *cancelItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"]
                                                                        style:UIBarButtonItemStylePlain
                                                                       target:self
                                                                       action:@selector(cancelMusicSelectionTapped)];
        UIBarButtonItem *favoriteItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"heart.fill"]
                                                                          style:UIBarButtonItemStylePlain
                                                                         target:self
                                                                         action:@selector(favoriteSelectedTracksTapped)];
        favoriteItem.tintColor = [UIColor colorWithRed:1.0 green:0.35 blue:0.42 alpha:1.0];
        UIBarButtonItem *deleteItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"trash.fill"]
                                                                        style:UIBarButtonItemStylePlain
                                                                       target:self
                                                                       action:@selector(deleteSelectedTracksTapped)];
        self.navigationItem.rightBarButtonItems = @[cancelItem, deleteItem, favoriteItem];
        return;
    }

    UIBarButtonItem *addItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                               target:self
                                                                               action:@selector(addMusicTapped)];
    UIBarButtonItem *searchItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass"]
                                                                    style:UIBarButtonItemStylePlain
                                                                   target:self
                                                                   action:@selector(searchButtonTapped)];
    self.navigationItem.rightBarButtonItems = @[searchItem, addItem];
}

- (void)cancelMusicSelectionTapped {
    [self setMusicSelectionModeEnabled:NO];
}

- (void)setMusicSelectionModeEnabled:(BOOL)enabled {
    if (!self.musicOnlyMode && enabled) {
        return;
    }
    self.multiSelectMode = enabled;
    if (!enabled) {
        [self.selectedTrackIDs removeAllObjects];
    }
    if (enabled && self.searchController.isActive) {
        self.searchController.active = NO;
    }
    [self refreshNavigationItemsForMusicSelectionState];
    [self.tableView reloadData];
}

- (SonoraTrack * _Nullable)trackForMusicTableIndexPath:(NSIndexPath *)indexPath {
    if (!self.musicOnlyMode) {
        return nil;
    }
    if ([self sectionTypeForIndex:indexPath.section] != SonoraSearchSectionTypeTracks) {
        return nil;
    }
    if (indexPath.row < 0 || indexPath.row >= self.filteredTracks.count) {
        return nil;
    }
    return self.filteredTracks[indexPath.row];
}

- (void)toggleMusicSelectionForTrackID:(NSString *)trackID forceSelected:(BOOL)forceSelected {
    if (trackID.length == 0) {
        return;
    }
    BOOL hasTrack = [self.selectedTrackIDs containsObject:trackID];
    if (forceSelected) {
        if (!hasTrack) {
            [self.selectedTrackIDs addObject:trackID];
        }
    } else if (hasTrack) {
        [self.selectedTrackIDs removeObject:trackID];
    } else {
        [self.selectedTrackIDs addObject:trackID];
    }

    if (self.selectedTrackIDs.count == 0) {
        [self setMusicSelectionModeEnabled:NO];
    } else {
        [self refreshNavigationItemsForMusicSelectionState];
        [self.tableView reloadData];
    }
}

- (void)handleTrackLongPress:(UILongPressGestureRecognizer *)gesture {
    if (!self.musicOnlyMode || gesture.state != UIGestureRecognizerStateBegan) {
        return;
    }
    CGPoint point = [gesture locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:point];
    if (indexPath == nil) {
        return;
    }
    SonoraTrack *track = [self trackForMusicTableIndexPath:indexPath];
    if (track == nil) {
        return;
    }
    [self setMusicSelectionModeEnabled:YES];
    [self toggleMusicSelectionForTrackID:track.identifier forceSelected:YES];
}

- (void)favoriteSelectedTracksTapped {
    if (self.selectedTrackIDs.count == 0) {
        return;
    }
    for (NSString *trackID in self.selectedTrackIDs) {
        [SonoraFavoritesStore.sharedStore setTrackID:trackID favorite:YES];
    }
    [self setMusicSelectionModeEnabled:NO];
    [self reloadTracks];
}

- (void)deleteSelectedTracksTapped {
    if (self.selectedTrackIDs.count == 0) {
        return;
    }

    NSArray<NSString *> *targetIDs = [self.selectedTrackIDs.array copy];
    NSError *firstError = nil;
    for (NSString *trackID in targetIDs) {
        NSError *deleteError = nil;
        BOOL removed = [SonoraLibraryManager.sharedManager deleteTrackWithIdentifier:trackID error:&deleteError];
        if (!removed && firstError == nil) {
            firstError = deleteError;
        }
        if (removed) {
            [SonoraFavoritesStore.sharedStore setTrackID:trackID favorite:NO];
            [SonoraPlaylistStore.sharedStore removeTrackIDFromAllPlaylists:trackID];
        }
    }

    [self setMusicSelectionModeEnabled:NO];
    [self reloadTracks];
    if (firstError != nil) {
        NSString *message = firstError.localizedDescription ?: @"Could not delete one or more tracks.";
        SonoraPresentAlert(self, @"Delete Failed", message);
    }
}

- (SonoraSearchSectionType)sectionTypeForIndex:(NSInteger)section {
    if (section < 0 || section >= self.visibleSections.count) {
        return SonoraSearchSectionTypeTracks;
    }
    return (SonoraSearchSectionType)self.visibleSections[section].integerValue;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    if (!self.musicOnlyMode) {
        return 0;
    }
    return self.visibleSections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if (!self.musicOnlyMode) {
        return 0;
    }
    switch ([self sectionTypeForIndex:section]) {
        case SonoraSearchSectionTypePlaylists:
            return self.filteredPlaylists.count;
        case SonoraSearchSectionTypeArtists:
            return self.artistResults.count;
        case SonoraSearchSectionTypeTracks:
            return self.filteredTracks.count;
    }
    return 0;
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (!self.musicOnlyMode) {
        return nil;
    }
    NSString *normalizedQuery = SonoraNormalizedSearchText(self.searchQuery);
    if (normalizedQuery.length == 0) {
        return nil;
    }
    switch ([self sectionTypeForIndex:section]) {
        case SonoraSearchSectionTypePlaylists:
            return @"Playlists";
        case SonoraSearchSectionTypeArtists:
            return @"Artists";
        case SonoraSearchSectionTypeTracks:
            return @"Tracks";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (!self.musicOnlyMode) {
        return [UITableViewCell new];
    }
    SonoraSearchSectionType sectionType = [self sectionTypeForIndex:indexPath.section];
    if (sectionType == SonoraSearchSectionTypeTracks) {
        SonoraTrackCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MusicTrackCell" forIndexPath:indexPath];

        SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
        SonoraTrack *track = self.filteredTracks[indexPath.row];
        SonoraTrack *currentTrack = playback.currentTrack;
        BOOL isCurrent = (currentTrack != nil && [currentTrack.identifier isEqualToString:track.identifier]);
        BOOL sameQueue = SonoraTrackQueuesMatchByIdentifier(playback.currentQueue, self.tracks);
        BOOL showsPlaybackIndicator = (sameQueue && isCurrent && playback.isPlaying);

        [cell configureWithTrack:track isCurrent:isCurrent showsPlaybackIndicator:showsPlaybackIndicator];
        cell.accessoryType = (self.multiSelectMode && [self.selectedTrackIDs containsObject:track.identifier])
        ? UITableViewCellAccessoryCheckmark
        : UITableViewCellAccessoryNone;
        return cell;
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MusicSearchMetaCell"];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"MusicSearchMetaCell"];
    }
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.textLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular];
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryNone;

    if (sectionType == SonoraSearchSectionTypePlaylists) {
        if (indexPath.row < self.filteredPlaylists.count) {
            SonoraPlaylist *playlist = self.filteredPlaylists[indexPath.row];
            cell.imageView.image = [UIImage systemImageNamed:@"music.note.list"];
            cell.textLabel.text = playlist.name ?: @"Playlist";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld tracks", (long)playlist.trackIDs.count];
        }
    } else if (sectionType == SonoraSearchSectionTypeArtists) {
        if (indexPath.row < self.artistResults.count) {
            NSDictionary<NSString *, id> *artistEntry = self.artistResults[indexPath.row];
            NSArray *matchedTracks = artistEntry[@"tracks"];
            cell.imageView.image = [UIImage systemImageNamed:@"person.fill"];
            cell.textLabel.text = artistEntry[@"title"] ?: @"Artist";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld tracks", (long)matchedTracks.count];
        }
    }

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!self.musicOnlyMode) {
        return;
    }

    if (self.multiSelectMode) {
        SonoraTrack *selectionTrack = [self trackForMusicTableIndexPath:indexPath];
        if (selectionTrack != nil) {
            [self toggleMusicSelectionForTrackID:selectionTrack.identifier forceSelected:NO];
        }
        return;
    }

    SonoraSearchSectionType sectionType = [self sectionTypeForIndex:indexPath.section];
    if (sectionType == SonoraSearchSectionTypePlaylists) {
        if (indexPath.row >= self.filteredPlaylists.count) {
            return;
        }
        SonoraPlaylist *playlist = self.filteredPlaylists[indexPath.row];
        SonoraPlaylistDetailViewController *detail = [[SonoraPlaylistDetailViewController alloc] initWithPlaylistID:playlist.playlistID];
        detail.hidesBottomBarWhenPushed = YES;
        [self.navigationController pushViewController:detail animated:YES];
        return;
    }

    if (sectionType == SonoraSearchSectionTypeArtists) {
        if (indexPath.row >= self.artistResults.count) {
            return;
        }
        NSDictionary<NSString *, id> *artistEntry = self.artistResults[indexPath.row];
        NSString *artistTitle = artistEntry[@"title"] ?: @"";
        self.searchQuery = artistTitle;
        self.searchController.searchBar.text = artistTitle;
        [self applySearchFilterAndReload];
        return;
    }

    if (indexPath.row >= self.filteredTracks.count) {
        return;
    }

    NSArray<SonoraTrack *> *playlistQueue = self.tracks;
    if (playlistQueue.count == 0) {
        return;
    }

    SonoraTrack *selectedTrack = self.filteredTracks[indexPath.row];
    NSInteger playlistIndex = SonoraIndexOfTrackByIdentifier(playlistQueue, selectedTrack.identifier);
    if (playlistIndex == NSNotFound) {
        return;
    }

    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    SonoraTrack *currentTrack = playback.currentTrack;
    BOOL sameTrack = (currentTrack != nil && [currentTrack.identifier isEqualToString:selectedTrack.identifier]);
    BOOL sameQueue = SonoraTrackQueuesMatchByIdentifier(playback.currentQueue, playlistQueue);
    if (sameTrack && sameQueue) {
        [self openPlayer];
        return;
    }

    [self openPlayer];
    dispatch_async(dispatch_get_main_queue(), ^{
        [playback setShuffleEnabled:NO];
        [playback playTracks:playlistQueue startIndex:playlistIndex];
    });
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (!self.musicOnlyMode || self.multiSelectMode) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }
    if ([self sectionTypeForIndex:indexPath.section] != SonoraSearchSectionTypeTracks ||
        indexPath.row >= self.filteredTracks.count) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }

    SonoraTrack *track = self.filteredTracks[indexPath.row];

    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                               title:@"Delete"
                                                                             handler:^(__unused UIContextualAction * _Nonnull action,
                                                                                       __unused UIView * _Nonnull sourceView,
                                                                                       void (^ _Nonnull completionHandler)(BOOL)) {
        NSError *deleteError = nil;
        BOOL removed = [SonoraLibraryManager.sharedManager deleteTrackWithIdentifier:track.identifier error:&deleteError];
        if (!removed) {
            NSString *message = deleteError.localizedDescription ?: @"Could not delete track file.";
            SonoraPresentAlert(self, @"Delete Failed", message);
            completionHandler(NO);
            return;
        }

        [SonoraFavoritesStore.sharedStore setTrackID:track.identifier favorite:NO];
        [SonoraPlaylistStore.sharedStore removeTrackIDFromAllPlaylists:track.identifier];
        [self reloadTracks];
        completionHandler(YES);
    }];
    deleteAction.image = [UIImage systemImageNamed:@"trash.fill"];

    UIContextualAction *addAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                            title:@"Add"
                                                                          handler:^(__unused UIContextualAction * _Nonnull action,
                                                                                    __unused UIView * _Nonnull sourceView,
                                                                                    void (^ _Nonnull completionHandler)(BOOL)) {
        SonoraPresentQuickAddTrackToPlaylist(self, track.identifier, nil);
        completionHandler(YES);
    }];
    addAction.image = [UIImage systemImageNamed:@"text.badge.plus"];
    addAction.backgroundColor = [UIColor colorWithRed:0.16 green:0.47 blue:0.95 alpha:1.0];

    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[deleteAction, addAction]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (!self.musicOnlyMode || self.multiSelectMode) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }
    if ([self sectionTypeForIndex:indexPath.section] != SonoraSearchSectionTypeTracks ||
        indexPath.row >= self.filteredTracks.count) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }

    SonoraTrack *track = self.filteredTracks[indexPath.row];
    BOOL isFavorite = [SonoraFavoritesStore.sharedStore isTrackFavoriteByID:track.identifier];
    NSString *iconName = isFavorite ? @"heart.slash.fill" : @"heart.fill";
    UIColor *backgroundColor = isFavorite
    ? [UIColor colorWithWhite:0.40 alpha:1.0]
    : [UIColor colorWithRed:1.0 green:0.35 blue:0.42 alpha:1.0];

    UIContextualAction *favoriteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                                  title:nil
                                                                                handler:^(__unused UIContextualAction * _Nonnull action,
                                                                                          __unused UIView * _Nonnull sourceView,
                                                                                          void (^ _Nonnull completionHandler)(BOOL)) {
        [SonoraFavoritesStore.sharedStore setTrackID:track.identifier favorite:!isFavorite];
        [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        completionHandler(YES);
    }];
    favoriteAction.image = [UIImage systemImageNamed:iconName];
    favoriteAction.backgroundColor = backgroundColor;

    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[favoriteAction]];
    configuration.performsFirstActionWithFullSwipe = YES;
    return configuration;
}

- (NSString *)titleForSearchSectionType:(SonoraSearchSectionType)sectionType {
    switch (sectionType) {
        case SonoraSearchSectionTypePlaylists:
            return @"Playlists";
        case SonoraSearchSectionTypeArtists:
            return @"Artists";
        case SonoraSearchSectionTypeTracks:
            return @"Music";
    }
    return @"";
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    if (collectionView != self.searchCollectionView || self.musicOnlyMode) {
        return 0;
    }
    return self.visibleSections.count;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    if (collectionView != self.searchCollectionView || self.musicOnlyMode) {
        return 0;
    }

    switch ([self sectionTypeForIndex:section]) {
        case SonoraSearchSectionTypePlaylists:
            return self.filteredPlaylists.count;
        case SonoraSearchSectionTypeArtists:
            return self.artistResults.count;
        case SonoraSearchSectionTypeTracks:
            return self.filteredTracks.count;
    }
    return 0;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                           cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    if (collectionView != self.searchCollectionView || self.musicOnlyMode) {
        return [UICollectionViewCell new];
    }

    SonoraMusicSearchCardCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:SonoraMusicSearchCardCellReuseID
                                                                             forIndexPath:indexPath];
    SonoraSearchSectionType sectionType = [self sectionTypeForIndex:indexPath.section];
    if (sectionType == SonoraSearchSectionTypePlaylists) {
        if (indexPath.item < self.filteredPlaylists.count) {
            SonoraPlaylist *playlist = self.filteredPlaylists[indexPath.item];
            UIImage *cover = [SonoraPlaylistStore.sharedStore coverForPlaylist:playlist
                                                                   library:SonoraLibraryManager.sharedManager
                                                                      size:CGSizeMake(220.0, 220.0)];
            NSString *subtitle = [NSString stringWithFormat:@"%ld tracks", (long)playlist.trackIDs.count];
            [cell configureWithTitle:playlist.name subtitle:subtitle image:cover];
        }
    } else if (sectionType == SonoraSearchSectionTypeArtists) {
        if (indexPath.item < self.artistResults.count) {
            NSDictionary<NSString *, id> *artistEntry = self.artistResults[indexPath.item];
            NSArray<SonoraTrack *> *matchedTracks = artistEntry[@"tracks"] ?: @[];
            SonoraTrack *coverTrack = matchedTracks.firstObject;
            NSString *title = artistEntry[@"title"] ?: @"Artist";
            NSString *subtitle = [NSString stringWithFormat:@"%ld tracks", (long)matchedTracks.count];
            [cell configureWithTitle:title subtitle:subtitle image:coverTrack.artwork];
        }
    } else {
        if (indexPath.item < self.filteredTracks.count) {
            SonoraTrack *track = self.filteredTracks[indexPath.item];
            NSString *trackTitle = track.title.length > 0 ? track.title :
                (track.fileName.length > 0 ? track.fileName.stringByDeletingPathExtension : @"Unknown track");
            NSString *subtitle = track.artist.length > 0 ? track.artist : @"Track";
            [cell configureWithTitle:trackTitle subtitle:subtitle image:track.artwork];
        }
    }
    return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView
              viewForSupplementaryElementOfKind:(NSString *)kind
                                    atIndexPath:(NSIndexPath *)indexPath {
    if (collectionView != self.searchCollectionView ||
        ![kind isEqualToString:UICollectionElementKindSectionHeader] ||
        self.musicOnlyMode) {
        return [UICollectionReusableView new];
    }

    SonoraMusicSearchHeaderView *header = [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                                                          withReuseIdentifier:SonoraMusicSearchHeaderReuseID
                                                                                 forIndexPath:indexPath];
    SonoraSearchSectionType sectionType = [self sectionTypeForIndex:indexPath.section];
    [header configureWithTitle:[self titleForSearchSectionType:sectionType]];
    return header;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    if (collectionView != self.searchCollectionView || self.musicOnlyMode) {
        return;
    }

    SonoraSearchSectionType sectionType = [self sectionTypeForIndex:indexPath.section];
    if (sectionType == SonoraSearchSectionTypePlaylists) {
        if (indexPath.item >= self.filteredPlaylists.count) {
            return;
        }
        SonoraPlaylist *playlist = self.filteredPlaylists[indexPath.item];
        SonoraPlaylistDetailViewController *detail = [[SonoraPlaylistDetailViewController alloc] initWithPlaylistID:playlist.playlistID];
        detail.hidesBottomBarWhenPushed = YES;
        [self.navigationController pushViewController:detail animated:YES];
        return;
    }

    if (sectionType == SonoraSearchSectionTypeArtists) {
        if (indexPath.item >= self.artistResults.count) {
            return;
        }
        NSDictionary<NSString *, id> *artistEntry = self.artistResults[indexPath.item];
        NSString *artistTitle = artistEntry[@"title"] ?: @"";
        self.searchQuery = artistTitle;
        self.searchController.searchBar.text = artistTitle;
        [self applySearchFilterAndReload];
        return;
    }

    if (indexPath.item >= self.filteredTracks.count) {
        return;
    }
    SonoraTrack *selectedTrack = self.filteredTracks[indexPath.item];
    NSInteger startIndex = SonoraIndexOfTrackByIdentifier(self.tracks, selectedTrack.identifier);
    if (startIndex == NSNotFound) {
        return;
    }

    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    SonoraTrack *currentTrack = playback.currentTrack;
    BOOL sameTrack = (currentTrack != nil && [currentTrack.identifier isEqualToString:selectedTrack.identifier]);
    BOOL sameQueue = SonoraTrackQueuesMatchByIdentifier(playback.currentQueue, self.tracks);
    if (sameTrack && sameQueue) {
        [self openPlayer];
        return;
    }

    [self openPlayer];
    dispatch_async(dispatch_get_main_queue(), ^{
        [playback setShuffleEnabled:NO];
        [playback playTracks:self.tracks startIndex:startIndex];
    });
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.searchQuery = searchController.searchBar.text ?: @"";
    [self applySearchFilterAndReload];
    [self updateSearchControllerAttachment];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (self.musicOnlyMode && (scrollView == self.tableView || scrollView == self.searchCollectionView)) {
        [self updateSearchControllerAttachment];
    }
}

@end

#pragma mark - Playlists

@interface SonoraPlaylistsViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray<SonoraPlaylist *> *playlists;
@property (nonatomic, copy) NSArray<SonoraPlaylist *> *filteredPlaylists;
@property (nonatomic, copy) NSString *searchQuery;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, assign) BOOL searchControllerAttached;
@property (nonatomic, assign) BOOL syncingLovelyPlaylist;
@property (nonatomic, assign) BOOL needsLovelyRefresh;

@end

@implementation SonoraPlaylistsViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = nil;
    self.navigationItem.title = nil;
    self.navigationItem.titleView = nil;
    self.navigationItem.hidesBackButton = YES;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:SonoraWhiteSectionTitleLabel(@"Playlists")];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    [self setupTableView];
    [self setupSearch];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                                             target:self
                                                                                             action:@selector(addPlaylistTapped)];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(reloadPlaylists)
                                               name:SonoraPlaylistsDidChangeNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(reloadPlaylists)
                                               name:UIApplicationWillEnterForegroundNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(reloadPlaylists)
                                               name:SonoraFavoritesDidChangeNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(markNeedsLovelyRefresh)
                                               name:SonoraPlaybackStateDidChangeNotification
                                             object:nil];

    self.needsLovelyRefresh = YES;
    [self reloadPlaylists];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationItem.title = nil;
    self.navigationItem.titleView = nil;
    self.navigationItem.hidesBackButton = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                                             target:self
                                                                                             action:@selector(addPlaylistTapped)];
    self.navigationController.interactivePopGestureRecognizer.enabled = YES;
    self.navigationController.interactivePopGestureRecognizer.delegate = nil;
    if (self.needsLovelyRefresh) {
        [self reloadPlaylists];
    }
    [self updateSearchControllerAttachment];
    [self.tableView reloadData];
}

- (void)markNeedsLovelyRefresh {
    self.needsLovelyRefresh = YES;
}

- (void)setupTableView {
    UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    tableView.translatesAutoresizingMaskIntoConstraints = NO;
    tableView.dataSource = self;
    tableView.delegate = self;
    tableView.rowHeight = 56.0;
    tableView.alwaysBounceVertical = YES;
    tableView.sectionHeaderHeight = 0.0;
    tableView.sectionFooterHeight = 0.0;
    tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    if (@available(iOS 15.0, *)) {
        tableView.sectionHeaderTopPadding = 0.0;
    }
    [tableView registerClass:SonoraPlaylistCell.class forCellReuseIdentifier:@"PlaylistCell"];

    self.tableView = tableView;
    [self.view addSubview:tableView];

    [NSLayoutConstraint activateConstraints:@[
        [tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)setupSearch {
    self.searchController = SonoraBuildSearchController(self, @"Search Playlists");
    self.navigationItem.searchController = nil;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
    self.definesPresentationContext = YES;
    self.searchControllerAttached = NO;
}

- (void)updateSearchControllerAttachment {
    BOOL shouldAttach = SonoraShouldAttachSearchController(self.searchControllerAttached,
                                                       self.searchController,
                                                       self.tableView,
                                                       SonoraSearchRevealThreshold);
    if (shouldAttach == self.searchControllerAttached) {
        return;
    }

    self.searchControllerAttached = shouldAttach;
    SonoraApplySearchControllerAttachment(self.navigationItem,
                                      self.navigationController.navigationBar,
                                      self.searchController,
                                      shouldAttach,
                                      (self.view.window != nil));
}

- (void)applySearchFilterAndReload {
    self.filteredPlaylists = SonoraFilterPlaylistsByQuery(self.playlists, self.searchQuery);
    [self.tableView reloadData];
    [self updateEmptyState];
}

- (void)updateEmptyState {
    if (self.filteredPlaylists.count > 0) {
        self.tableView.backgroundView = nil;
        return;
    }

    UILabel *label = [[UILabel alloc] init];
    label.textColor = UIColor.secondaryLabelColor;
    label.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    if (self.playlists.count == 0) {
        label.text = @"Tap + to create a playlist";
    } else {
        label.text = @"No matching playlists.";
    }
    self.tableView.backgroundView = label;
}

- (void)addPlaylistTapped {
    SonoraPlaylistNameViewController *nameVC = [[SonoraPlaylistNameViewController alloc] init];
    nameVC.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:nameVC animated:YES];
}

- (NSArray<NSString *> *)lovelyTrackIDsFromLibraryTracks:(NSArray<SonoraTrack *> *)libraryTracks {
    if (libraryTracks.count == 0) {
        return @[];
    }

    NSMutableArray<NSString *> *trackIDs = [NSMutableArray arrayWithCapacity:libraryTracks.count];
    for (SonoraTrack *track in libraryTracks) {
        if (track.identifier.length > 0) {
            [trackIDs addObject:track.identifier];
        }
    }
    if (trackIDs.count == 0) {
        return @[];
    }

    NSDictionary<NSString *, NSDictionary<NSString *, NSNumber *> *> *analyticsByTrackID =
    [SonoraTrackAnalyticsStore.sharedStore analyticsByTrackIDForTrackIDs:trackIDs];
    SonoraFavoritesStore *favoritesStore = SonoraFavoritesStore.sharedStore;

    NSMutableArray<SonoraTrack *> *eligibleTracks = [NSMutableArray array];
    for (SonoraTrack *track in libraryTracks) {
        NSDictionary<NSString *, NSNumber *> *metrics = analyticsByTrackID[track.identifier] ?: @{};
        NSInteger playCount = [metrics[@"playCount"] integerValue];
        NSInteger skipCount = [metrics[@"skipCount"] integerValue];
        double score = [metrics[@"score"] doubleValue];
        NSInteger activity = playCount + skipCount;
        BOOL isFavorite = [favoritesStore isTrackFavoriteByID:track.identifier];

        // Rule:
        // (playCount + skipCount) >= 3
        // AND ((isFavorite && score >= 0.60 && playCount >= 2) || (score >= 0.80 && playCount >= 4))
        // AND skipCount <= 3
        BOOL matchesFavoriteRule = (isFavorite && score >= 0.60 && playCount >= 2);
        BOOL matchesHighScoreRule = (score >= 0.80 && playCount >= 4);
        if (activity < 3 || skipCount > 3 || !(matchesFavoriteRule || matchesHighScoreRule)) {
            continue;
        }

        [eligibleTracks addObject:track];
    }

    if (eligibleTracks.count == 0) {
        return @[];
    }

    [eligibleTracks sortUsingComparator:^NSComparisonResult(SonoraTrack * _Nonnull left, SonoraTrack * _Nonnull right) {
        NSDictionary<NSString *, NSNumber *> *leftMetrics = analyticsByTrackID[left.identifier] ?: @{};
        NSDictionary<NSString *, NSNumber *> *rightMetrics = analyticsByTrackID[right.identifier] ?: @{};

        NSInteger leftPlay = [leftMetrics[@"playCount"] integerValue];
        NSInteger rightPlay = [rightMetrics[@"playCount"] integerValue];
        NSInteger leftSkip = [leftMetrics[@"skipCount"] integerValue];
        NSInteger rightSkip = [rightMetrics[@"skipCount"] integerValue];

        double leftScore = [leftMetrics[@"score"] doubleValue];
        double rightScore = [rightMetrics[@"score"] doubleValue];
        BOOL leftFavorite = [favoritesStore isTrackFavoriteByID:left.identifier];
        BOOL rightFavorite = [favoritesStore isTrackFavoriteByID:right.identifier];

        if (leftScore > rightScore) {
            return NSOrderedAscending;
        }
        if (leftScore < rightScore) {
            return NSOrderedDescending;
        }
        if (leftPlay > rightPlay) {
            return NSOrderedAscending;
        }
        if (leftPlay < rightPlay) {
            return NSOrderedDescending;
        }
        if (leftSkip < rightSkip) {
            return NSOrderedAscending;
        }
        if (leftSkip > rightSkip) {
            return NSOrderedDescending;
        }
        if (leftFavorite != rightFavorite) {
            return leftFavorite ? NSOrderedAscending : NSOrderedDescending;
        }

        NSString *leftTitle = left.title.length > 0 ? left.title : left.fileName;
        NSString *rightTitle = right.title.length > 0 ? right.title : right.fileName;
        return [leftTitle localizedCaseInsensitiveCompare:rightTitle];
    }];

    NSMutableArray<NSString *> *orderedIDs = [NSMutableArray arrayWithCapacity:eligibleTracks.count];
    for (SonoraTrack *track in eligibleTracks) {
        if (track.identifier.length > 0) {
            [orderedIDs addObject:track.identifier];
        }
    }
    return [orderedIDs copy];
}

- (void)syncLovelyPlaylistIfNeeded {
    NSArray<SonoraTrack *> *libraryTracks = SonoraLibraryManager.sharedManager.tracks;
    if (libraryTracks.count == 0) {
        libraryTracks = [SonoraLibraryManager.sharedManager reloadTracks];
    }
    NSArray<NSString *> *lovelyTrackIDs = [self lovelyTrackIDsFromLibraryTracks:libraryTracks];

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *storedPlaylistID = [defaults stringForKey:SonoraLovelyPlaylistDefaultsKey];

    SonoraPlaylistStore *store = SonoraPlaylistStore.sharedStore;
    SonoraPlaylist *lovelyPlaylist = (storedPlaylistID.length > 0)
    ? [store playlistWithID:storedPlaylistID]
    : nil;
    if (lovelyPlaylist == nil) {
        for (SonoraPlaylist *playlist in store.playlists) {
            if ([playlist.name localizedCaseInsensitiveCompare:@"Lovely songs"] == NSOrderedSame) {
                lovelyPlaylist = playlist;
                [defaults setObject:playlist.playlistID forKey:SonoraLovelyPlaylistDefaultsKey];
                break;
            }
        }
    }

    if (lovelyPlaylist == nil) {
        [defaults removeObjectForKey:SonoraLovelyPlaylistDefaultsKey];
        [defaults removeObjectForKey:SonoraLovelyPlaylistCoverMarkerKey];
        if (lovelyTrackIDs.count == 0) {
            return;
        }

        UIImage *coverImage = SonoraLovelySongsCoverImage(CGSizeMake(768.0, 768.0));
        SonoraPlaylist *created = [store addPlaylistWithName:@"Lovely songs"
                                                trackIDs:lovelyTrackIDs
                                              coverImage:coverImage];
        if (created != nil) {
            [defaults setObject:created.playlistID forKey:SonoraLovelyPlaylistDefaultsKey];
            [defaults setObject:created.playlistID forKey:SonoraLovelyPlaylistCoverMarkerKey];
        }
        return;
    }

    if (![lovelyPlaylist.name isEqualToString:@"Lovely songs"]) {
        [store renamePlaylistWithID:lovelyPlaylist.playlistID newName:@"Lovely songs"];
    }

    if (![lovelyPlaylist.trackIDs isEqualToArray:lovelyTrackIDs]) {
        [store replaceTrackIDs:lovelyTrackIDs forPlaylistID:lovelyPlaylist.playlistID];
    }

    NSString *coverMarker = [defaults stringForKey:SonoraLovelyPlaylistCoverMarkerKey];
    BOOL shouldRefreshCover = (lovelyPlaylist.customCoverFileName.length == 0 ||
                               ![coverMarker isEqualToString:lovelyPlaylist.playlistID]);
    if (shouldRefreshCover) {
        UIImage *coverImage = SonoraLovelySongsCoverImage(CGSizeMake(768.0, 768.0));
        BOOL coverSet = [store setCustomCoverImage:coverImage forPlaylistID:lovelyPlaylist.playlistID];
        if (coverSet) {
            [defaults setObject:lovelyPlaylist.playlistID forKey:SonoraLovelyPlaylistCoverMarkerKey];
        }
    }
}

- (void)reloadPlaylists {
    if (self.syncingLovelyPlaylist) {
        return;
    }

    self.syncingLovelyPlaylist = YES;
    @try {
        SonoraPlaylistStore *store = SonoraPlaylistStore.sharedStore;
        [store reloadPlaylists];
        [self syncLovelyPlaylistIfNeeded];
        [store reloadPlaylists];

        NSMutableArray<SonoraPlaylist *> *orderedPlaylists = [store.playlists mutableCopy];
        NSString *lovelyID = [NSUserDefaults.standardUserDefaults stringForKey:SonoraLovelyPlaylistDefaultsKey];
        if (lovelyID.length > 0) {
            NSUInteger index = [orderedPlaylists indexOfObjectPassingTest:^BOOL(SonoraPlaylist * _Nonnull playlist, __unused NSUInteger idx, __unused BOOL * _Nonnull stop) {
                return [playlist.playlistID isEqualToString:lovelyID];
            }];
            if (index != NSNotFound) {
                SonoraPlaylist *lovely = orderedPlaylists[index];
                if (lovely.trackIDs.count == 0) {
                    [orderedPlaylists removeObjectAtIndex:index];
                } else if (index != 0) {
                    [orderedPlaylists removeObjectAtIndex:index];
                    [orderedPlaylists insertObject:lovely atIndex:0];
                }
            }
        }

        self.playlists = [orderedPlaylists copy];
        [self applySearchFilterAndReload];
    } @finally {
        self.needsLovelyRefresh = NO;
        self.syncingLovelyPlaylist = NO;
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return self.filteredPlaylists.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SonoraPlaylistCell *cell = [tableView dequeueReusableCellWithIdentifier:@"PlaylistCell" forIndexPath:indexPath];

    SonoraPlaylist *playlist = self.filteredPlaylists[indexPath.row];
    UIImage *cover = [SonoraPlaylistStore.sharedStore coverForPlaylist:playlist
                                                           library:SonoraLibraryManager.sharedManager
                                                              size:CGSizeMake(160.0, 160.0)];
    NSString *subtitle = [NSString stringWithFormat:@"%ld tracks", (long)playlist.trackIDs.count];

    [cell configureWithName:playlist.name subtitle:subtitle artwork:cover];
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.row >= self.filteredPlaylists.count) {
        return;
    }
    SonoraPlaylist *playlist = self.filteredPlaylists[indexPath.row];
    SonoraPlaylistDetailViewController *detail = [[SonoraPlaylistDetailViewController alloc] initWithPlaylistID:playlist.playlistID];
    detail.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:detail animated:YES];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.searchQuery = searchController.searchBar.text ?: @"";
    [self applySearchFilterAndReload];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView == self.tableView) {
        [self updateSearchControllerAttachment];
    }
}

@end

#pragma mark - Favorites

@interface SonoraFavoritesViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray<SonoraTrack *> *tracks;
@property (nonatomic, copy) NSArray<SonoraTrack *> *filteredTracks;
@property (nonatomic, copy) NSString *searchQuery;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, assign) BOOL searchControllerAttached;
@property (nonatomic, assign) BOOL multiSelectMode;
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *selectedTrackIDs;
@property (nonatomic, strong) UILongPressGestureRecognizer *selectionLongPressRecognizer;

@end

@implementation SonoraFavoritesViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Favorites";
    self.navigationItem.title = nil;
    self.navigationItem.titleView = nil;
    self.navigationItem.hidesBackButton = YES;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:SonoraWhiteSectionTitleLabel(@"Favorites")];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass"]
                                                                               style:UIBarButtonItemStylePlain
                                                                              target:self
                                                                              action:@selector(searchButtonTapped)];

    [self setupTableView];
    [self setupSearch];
    self.multiSelectMode = NO;
    self.selectedTrackIDs = [NSMutableOrderedSet orderedSet];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(reloadFavorites)
                                               name:SonoraFavoritesDidChangeNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handlePlaybackChanged)
                                               name:SonoraPlaybackStateDidChangeNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handleAppForeground)
                                               name:UIApplicationWillEnterForegroundNotification
                                             object:nil];

    [self refreshNavigationItemsForFavoritesSelectionState];
    [self reloadFavorites];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationItem.hidesBackButton = YES;
    [self refreshNavigationItemsForFavoritesSelectionState];
    self.navigationController.interactivePopGestureRecognizer.enabled = YES;
    self.navigationController.interactivePopGestureRecognizer.delegate = nil;
    [self updateSearchControllerAttachment];
    [self.tableView reloadData];
}

- (void)setupTableView {
    UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    tableView.translatesAutoresizingMaskIntoConstraints = NO;
    tableView.dataSource = self;
    tableView.delegate = self;
    tableView.rowHeight = 54.0;
    tableView.alwaysBounceVertical = YES;
    tableView.sectionHeaderHeight = 0.0;
    tableView.sectionFooterHeight = 0.0;
    tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    if (@available(iOS 15.0, *)) {
        tableView.sectionHeaderTopPadding = 0.0;
    }
    [tableView registerClass:SonoraTrackCell.class forCellReuseIdentifier:@"FavoriteTrackCell"];
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                                                             action:@selector(handleTrackLongPress:)];
    [tableView addGestureRecognizer:longPress];
    self.selectionLongPressRecognizer = longPress;

    self.tableView = tableView;
    [self.view addSubview:tableView];

    [NSLayoutConstraint activateConstraints:@[
        [tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)setupSearch {
    self.searchController = SonoraBuildSearchController(self, @"Search Favorites");
    self.navigationItem.searchController = nil;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
    self.definesPresentationContext = YES;
    self.searchControllerAttached = NO;
}

- (void)updateSearchControllerAttachment {
    BOOL shouldAttach = SonoraShouldAttachSearchController(self.searchControllerAttached,
                                                       self.searchController,
                                                       self.tableView,
                                                       SonoraSearchRevealThreshold);
    if (shouldAttach == self.searchControllerAttached) {
        return;
    }

    self.searchControllerAttached = shouldAttach;
    SonoraApplySearchControllerAttachment(self.navigationItem,
                                      self.navigationController.navigationBar,
                                      self.searchController,
                                      shouldAttach,
                                      (self.view.window != nil));
}

- (void)applySearchFilterAndReload {
    self.filteredTracks = SonoraFilterTracksByQuery(self.tracks, self.searchQuery);
    [self.tableView reloadData];
    [self updateEmptyState];
}

- (void)updateEmptyState {
    if (self.filteredTracks.count > 0) {
        self.tableView.backgroundView = nil;
        return;
    }

    UILabel *label = [[UILabel alloc] init];
    label.textColor = UIColor.secondaryLabelColor;
    label.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    if (self.tracks.count == 0) {
        label.text = @"No favorites yet.\nTap heart in player to add tracks.";
    } else {
        label.text = @"No search results.";
    }
    self.tableView.backgroundView = label;
}

- (void)reloadFavorites {
    if (SonoraLibraryManager.sharedManager.tracks.count == 0 &&
        SonoraFavoritesStore.sharedStore.favoriteTrackIDs.count > 0) {
        [SonoraLibraryManager.sharedManager reloadTracks];
    }

    self.tracks = [SonoraFavoritesStore.sharedStore favoriteTracksWithLibrary:SonoraLibraryManager.sharedManager];
    [self applySearchFilterAndReload];
}

- (void)handleAppForeground {
    [SonoraLibraryManager.sharedManager reloadTracks];
    [self reloadFavorites];
}

- (void)handlePlaybackChanged {
    [self.tableView reloadData];
}

- (void)openPlayer {
    SonoraPlayerViewController *player = [[SonoraPlayerViewController alloc] init];
    player.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:player animated:YES];
}

- (void)searchButtonTapped {
    if (self.searchController == nil) {
        return;
    }

    if (!self.searchControllerAttached) {
        self.searchControllerAttached = YES;
        SonoraApplySearchControllerAttachment(self.navigationItem,
                                          self.navigationController.navigationBar,
                                          self.searchController,
                                          YES,
                                          (self.view.window != nil));
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        self.searchController.active = YES;
        [self.searchController.searchBar becomeFirstResponder];
    });
}

- (void)refreshNavigationItemsForFavoritesSelectionState {
    NSString *displayTitle = self.multiSelectMode
    ? [NSString stringWithFormat:@"%lu Selected", (unsigned long)self.selectedTrackIDs.count]
    : @"Favorites";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:SonoraWhiteSectionTitleLabel(displayTitle)];

    if (self.multiSelectMode) {
        UIBarButtonItem *cancelItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"]
                                                                        style:UIBarButtonItemStylePlain
                                                                       target:self
                                                                       action:@selector(cancelFavoritesSelectionTapped)];
        UIBarButtonItem *favoriteItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"heart.fill"]
                                                                          style:UIBarButtonItemStylePlain
                                                                         target:self
                                                                         action:@selector(favoriteSelectedFavoritesTapped)];
        favoriteItem.tintColor = [UIColor colorWithRed:1.0 green:0.35 blue:0.42 alpha:1.0];
        UIBarButtonItem *deleteItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"trash.fill"]
                                                                        style:UIBarButtonItemStylePlain
                                                                       target:self
                                                                       action:@selector(removeSelectedFavoritesTapped)];
        self.navigationItem.rightBarButtonItems = @[cancelItem, deleteItem, favoriteItem];
        return;
    }

    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass"]
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(searchButtonTapped)]
    ];
}

- (void)cancelFavoritesSelectionTapped {
    [self setFavoritesSelectionModeEnabled:NO];
}

- (void)setFavoritesSelectionModeEnabled:(BOOL)enabled {
    self.multiSelectMode = enabled;
    if (!enabled) {
        [self.selectedTrackIDs removeAllObjects];
    }
    if (enabled && self.searchController.isActive) {
        self.searchController.active = NO;
    }
    [self refreshNavigationItemsForFavoritesSelectionState];
    [self.tableView reloadData];
}

- (SonoraTrack * _Nullable)favoriteTrackAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row < 0 || indexPath.row >= self.filteredTracks.count) {
        return nil;
    }
    return self.filteredTracks[indexPath.row];
}

- (void)toggleFavoritesSelectionForTrackID:(NSString *)trackID forceSelected:(BOOL)forceSelected {
    if (trackID.length == 0) {
        return;
    }
    BOOL hasTrack = [self.selectedTrackIDs containsObject:trackID];
    if (forceSelected) {
        if (!hasTrack) {
            [self.selectedTrackIDs addObject:trackID];
        }
    } else if (hasTrack) {
        [self.selectedTrackIDs removeObject:trackID];
    } else {
        [self.selectedTrackIDs addObject:trackID];
    }

    if (self.selectedTrackIDs.count == 0) {
        [self setFavoritesSelectionModeEnabled:NO];
    } else {
        [self refreshNavigationItemsForFavoritesSelectionState];
        [self.tableView reloadData];
    }
}

- (void)handleTrackLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) {
        return;
    }
    CGPoint point = [gesture locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:point];
    if (indexPath == nil) {
        return;
    }
    SonoraTrack *track = [self favoriteTrackAtIndexPath:indexPath];
    if (track == nil) {
        return;
    }
    [self setFavoritesSelectionModeEnabled:YES];
    [self toggleFavoritesSelectionForTrackID:track.identifier forceSelected:YES];
}

- (void)favoriteSelectedFavoritesTapped {
    if (self.selectedTrackIDs.count == 0) {
        return;
    }
    for (NSString *trackID in self.selectedTrackIDs) {
        [SonoraFavoritesStore.sharedStore setTrackID:trackID favorite:YES];
    }
    [self setFavoritesSelectionModeEnabled:NO];
    [self reloadFavorites];
}

- (void)removeSelectedFavoritesTapped {
    if (self.selectedTrackIDs.count == 0) {
        return;
    }
    for (NSString *trackID in self.selectedTrackIDs) {
        [SonoraFavoritesStore.sharedStore setTrackID:trackID favorite:NO];
    }
    [self setFavoritesSelectionModeEnabled:NO];
    [self reloadFavorites];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return self.filteredTracks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SonoraTrackCell *cell = [tableView dequeueReusableCellWithIdentifier:@"FavoriteTrackCell" forIndexPath:indexPath];

    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    SonoraTrack *track = self.filteredTracks[indexPath.row];
    SonoraTrack *currentTrack = playback.currentTrack;
    BOOL isCurrent = (currentTrack != nil && [currentTrack.identifier isEqualToString:track.identifier]);
    BOOL showsPlaybackIndicator = (isCurrent && playback.isPlaying);
    [cell configureWithTrack:track isCurrent:isCurrent showsPlaybackIndicator:showsPlaybackIndicator];
    cell.accessoryType = (self.multiSelectMode && [self.selectedTrackIDs containsObject:track.identifier])
    ? UITableViewCellAccessoryCheckmark
    : UITableViewCellAccessoryNone;

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= self.filteredTracks.count) {
        return;
    }

    if (self.multiSelectMode) {
        SonoraTrack *selectionTrack = [self favoriteTrackAtIndexPath:indexPath];
        if (selectionTrack != nil) {
            [self toggleFavoritesSelectionForTrackID:selectionTrack.identifier forceSelected:NO];
        }
        return;
    }

    SonoraTrack *selectedTrack = self.filteredTracks[indexPath.row];
    SonoraTrack *currentTrack = SonoraPlaybackManager.sharedManager.currentTrack;
    if (currentTrack != nil && [currentTrack.identifier isEqualToString:selectedTrack.identifier]) {
        [self openPlayer];
        return;
    }

    NSArray<SonoraTrack *> *queue = self.filteredTracks;
    NSInteger startIndex = indexPath.row;
    [self openPlayer];
    dispatch_async(dispatch_get_main_queue(), ^{
        [SonoraPlaybackManager.sharedManager setShuffleEnabled:NO];
        [SonoraPlaybackManager.sharedManager playTracks:queue startIndex:startIndex];
    });
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (self.multiSelectMode) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }
    if (indexPath.row >= self.filteredTracks.count) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }

    SonoraTrack *track = self.filteredTracks[indexPath.row];

    UIContextualAction *removeAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                                title:@"Unfollow"
                                                                              handler:^(__unused UIContextualAction * _Nonnull action,
                                                                                        __unused UIView * _Nonnull sourceView,
                                                                                        void (^ _Nonnull completionHandler)(BOOL)) {
        [SonoraFavoritesStore.sharedStore setTrackID:track.identifier favorite:NO];
        [self reloadFavorites];
        completionHandler(YES);
    }];
    removeAction.image = [UIImage systemImageNamed:@"heart.slash.fill"];
    removeAction.backgroundColor = [UIColor colorWithWhite:0.40 alpha:1.0];

    UIContextualAction *addAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                            title:@"Add"
                                                                          handler:^(__unused UIContextualAction * _Nonnull action,
                                                                                    __unused UIView * _Nonnull sourceView,
                                                                                    void (^ _Nonnull completionHandler)(BOOL)) {
        SonoraPresentQuickAddTrackToPlaylist(self, track.identifier, nil);
        completionHandler(YES);
    }];
    addAction.image = [UIImage systemImageNamed:@"text.badge.plus"];
    addAction.backgroundColor = [UIColor colorWithRed:0.16 green:0.47 blue:0.95 alpha:1.0];

    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[removeAction, addAction]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (self.multiSelectMode) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }
    (void)indexPath;
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.searchQuery = searchController.searchBar.text ?: @"";
    [self applySearchFilterAndReload];
    [self updateSearchControllerAttachment];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView == self.tableView) {
        [self updateSearchControllerAttachment];
    }
}

@end

#pragma mark - Playlist Name Step

@interface SonoraPlaylistNameViewController () <UITextFieldDelegate>

@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UIButton *nextButton;
@property (nonatomic, strong) UILabel *counterLabel;

@end

@implementation SonoraPlaylistNameViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Create Playlist";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    [self setupUI];
    [self updateNameUI];
}

- (void)setupUI {
    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:scrollView];

    UIView *content = [[UIView alloc] init];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView addSubview:content];

    UIView *heroCard = [[UIView alloc] init];
    heroCard.translatesAutoresizingMaskIntoConstraints = NO;
    heroCard.backgroundColor = UIColor.clearColor;

    UILabel *heroTitle = [[UILabel alloc] init];
    heroTitle.translatesAutoresizingMaskIntoConstraints = NO;
    heroTitle.text = @"Name Your Playlist";
    heroTitle.font = [UIFont systemFontOfSize:30.0 weight:UIFontWeightBold];
    heroTitle.textColor = UIColor.labelColor;
    heroTitle.numberOfLines = 1;

    [heroCard addSubview:heroTitle];

    UIView *inputCard = [[UIView alloc] init];
    inputCard.translatesAutoresizingMaskIntoConstraints = NO;
    inputCard.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
        if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return [UIColor colorWithWhite:1.0 alpha:0.06];
        }
        return [UIColor colorWithWhite:0.0 alpha:0.03];
    }];
    inputCard.layer.cornerRadius = 18.0;
    inputCard.layer.borderWidth = 1.0;
    inputCard.layer.borderColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
        if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return [UIColor colorWithWhite:1.0 alpha:0.14];
        }
        return [UIColor colorWithWhite:0.0 alpha:0.08];
    }].CGColor;

    UILabel *inputTitle = [[UILabel alloc] init];
    inputTitle.translatesAutoresizingMaskIntoConstraints = NO;
    inputTitle.text = @"Playlist Name";
    inputTitle.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    inputTitle.textColor = UIColor.secondaryLabelColor;

    UITextField *nameField = [[UITextField alloc] init];
    nameField.translatesAutoresizingMaskIntoConstraints = NO;
    nameField.borderStyle = UITextBorderStyleNone;
    nameField.placeholder = @"Example: Late Night Drive";
    nameField.returnKeyType = UIReturnKeyNext;
    nameField.clearButtonMode = UITextFieldViewModeWhileEditing;
    nameField.delegate = self;
    nameField.font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightSemibold];
    nameField.textColor = UIColor.labelColor;
    [nameField addTarget:self action:@selector(nameDidChange) forControlEvents:UIControlEventEditingChanged];
    self.nameField = nameField;

    UILabel *counterLabel = [[UILabel alloc] init];
    counterLabel.translatesAutoresizingMaskIntoConstraints = NO;
    counterLabel.font = [UIFont monospacedDigitSystemFontOfSize:12.0 weight:UIFontWeightSemibold];
    counterLabel.textColor = UIColor.secondaryLabelColor;
    counterLabel.textAlignment = NSTextAlignmentRight;
    self.counterLabel = counterLabel;

    [inputCard addSubview:inputTitle];
    [inputCard addSubview:nameField];
    [inputCard addSubview:counterLabel];

    UIButton *nextButton = [UIButton buttonWithType:UIButtonTypeSystem];
    nextButton.translatesAutoresizingMaskIntoConstraints = NO;
    [nextButton setTitle:@"Next: Choose Music" forState:UIControlStateNormal];
    [nextButton setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
    nextButton.titleLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightBold];
    nextButton.layer.cornerRadius = 14.0;
    [nextButton addTarget:self action:@selector(nextTapped) forControlEvents:UIControlEventTouchUpInside];
    self.nextButton = nextButton;

    [content addSubview:heroCard];
    [content addSubview:inputCard];
    [self.view addSubview:nextButton];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray arrayWithArray:@[
        [scrollView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:nextButton.topAnchor constant:-12.0],

        [content.topAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor],
        [content.leadingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.trailingAnchor],
        [content.bottomAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor],
        [content.widthAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.widthAnchor],

        [heroCard.topAnchor constraintEqualToAnchor:content.topAnchor constant:16.0],
        [heroCard.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16.0],
        [heroCard.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16.0],
        [heroCard.heightAnchor constraintEqualToConstant:58.0],

        [heroTitle.topAnchor constraintEqualToAnchor:heroCard.topAnchor constant:8.0],
        [heroTitle.leadingAnchor constraintEqualToAnchor:heroCard.leadingAnchor constant:14.0],
        [heroTitle.trailingAnchor constraintEqualToAnchor:heroCard.trailingAnchor constant:-14.0],

        [inputCard.topAnchor constraintEqualToAnchor:heroCard.bottomAnchor constant:10.0],
        [inputCard.leadingAnchor constraintEqualToAnchor:heroCard.leadingAnchor],
        [inputCard.trailingAnchor constraintEqualToAnchor:heroCard.trailingAnchor],
        [inputCard.heightAnchor constraintEqualToConstant:118.0],

        [inputTitle.topAnchor constraintEqualToAnchor:inputCard.topAnchor constant:14.0],
        [inputTitle.leadingAnchor constraintEqualToAnchor:inputCard.leadingAnchor constant:14.0],
        [inputTitle.trailingAnchor constraintEqualToAnchor:inputCard.trailingAnchor constant:-14.0],

        [nameField.topAnchor constraintEqualToAnchor:inputTitle.bottomAnchor constant:8.0],
        [nameField.leadingAnchor constraintEqualToAnchor:inputTitle.leadingAnchor],
        [nameField.trailingAnchor constraintEqualToAnchor:inputTitle.trailingAnchor],
        [nameField.heightAnchor constraintEqualToConstant:42.0],

        [counterLabel.trailingAnchor constraintEqualToAnchor:nameField.trailingAnchor],
        [counterLabel.bottomAnchor constraintEqualToAnchor:inputCard.bottomAnchor constant:-10.0],
        [counterLabel.widthAnchor constraintEqualToConstant:62.0],

        [content.bottomAnchor constraintEqualToAnchor:inputCard.bottomAnchor constant:24.0],

        [nextButton.leadingAnchor constraintEqualToAnchor:inputCard.leadingAnchor],
        [nextButton.trailingAnchor constraintEqualToAnchor:inputCard.trailingAnchor],
        [nextButton.heightAnchor constraintEqualToConstant:52.0]
    ]];

    if (@available(iOS 15.0, *)) {
        [constraints addObject:[nextButton.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor constant:-12.0]];
    } else {
        [constraints addObject:[nextButton.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-12.0]];
    }

    [NSLayoutConstraint activateConstraints:constraints];
}

- (void)nameDidChange {
    [self updateNameUI];
}

- (void)updateNameUI {
    NSString *trimmed = [self.nameField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSUInteger length = self.nameField.text.length;
    if (length > 32) {
        self.nameField.text = [self.nameField.text substringToIndex:32];
        length = 32;
    }

    self.counterLabel.text = [NSString stringWithFormat:@"%lu/32", (unsigned long)length];

    BOOL enabled = (trimmed.length > 0);
    self.nextButton.enabled = enabled;
    self.nextButton.alpha = enabled ? 1.0 : 0.45;
    self.nextButton.backgroundColor = enabled ? SonoraAccentYellowColor() : [UIColor colorWithWhite:0.65 alpha:0.4];
}

- (void)nextTapped {
    NSString *name = [self.nameField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (name.length == 0) {
        SonoraPresentAlert(self, @"Name Required", @"Enter playlist name.");
        return;
    }

    NSArray<SonoraTrack *> *tracks = [SonoraLibraryManager.sharedManager reloadTracks];
    if (tracks.count == 0) {
        SonoraPresentAlert(self, @"No Music", @"Add music files in Files app first.");
        return;
    }

    SonoraPlaylistTrackPickerViewController *picker = [[SonoraPlaylistTrackPickerViewController alloc] initWithPlaylistName:name tracks:tracks];
    picker.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:picker animated:YES];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    (void)textField;
    [self nextTapped];
    return YES;
}

- (BOOL)textField:(UITextField *)textField
shouldChangeCharactersInRange:(NSRange)range
replacementString:(NSString *)string {
    NSString *current = textField.text ?: @"";
    NSString *updated = [current stringByReplacingCharactersInRange:range withString:string ?: @""];
    return (updated.length <= 32);
}

@end

#pragma mark - Playlist Track Step

@interface SonoraPlaylistTrackPickerViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>

@property (nonatomic, copy) NSString *playlistName;
@property (nonatomic, copy) NSArray<SonoraTrack *> *tracks;
@property (nonatomic, copy) NSArray<SonoraTrack *> *filteredTracks;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedTrackIDs;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSString *searchQuery;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, assign) BOOL searchControllerAttached;

@end

@implementation SonoraPlaylistTrackPickerViewController

- (instancetype)initWithPlaylistName:(NSString *)playlistName tracks:(NSArray<SonoraTrack *> *)tracks {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _playlistName = [playlistName copy];
        _tracks = [[SonoraTrackAnalyticsStore.sharedStore tracksSortedByAffinity:tracks] copy];
        _filteredTracks = _tracks;
        _selectedTrackIDs = [NSMutableSet set];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Select Music";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Create"
                                                                               style:UIBarButtonItemStyleDone
                                                                              target:self
                                                                              action:@selector(createTapped)];

    [self setupTableView];
    [self setupSearch];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateSearchControllerAttachment];
}

- (void)setupTableView {
    UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    tableView.translatesAutoresizingMaskIntoConstraints = NO;
    tableView.dataSource = self;
    tableView.delegate = self;
    tableView.rowHeight = 54.0;
    tableView.alwaysBounceVertical = YES;
    tableView.sectionHeaderHeight = 0.0;
    tableView.sectionFooterHeight = 0.0;
    tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    if (@available(iOS 15.0, *)) {
        tableView.sectionHeaderTopPadding = 0.0;
    }
    [tableView registerClass:SonoraTrackCell.class forCellReuseIdentifier:@"TrackPickCell"];

    self.tableView = tableView;
    [self.view addSubview:tableView];

    [NSLayoutConstraint activateConstraints:@[
        [tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)setupSearch {
    self.searchController = SonoraBuildSearchController(self, @"Search Tracks");
    self.navigationItem.searchController = nil;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
    self.definesPresentationContext = YES;
    self.searchControllerAttached = NO;
}

- (void)updateSearchControllerAttachment {
    BOOL shouldAttach = SonoraShouldAttachSearchController(self.searchControllerAttached,
                                                       self.searchController,
                                                       self.tableView,
                                                       SonoraSearchRevealThreshold);
    if (shouldAttach == self.searchControllerAttached) {
        return;
    }

    self.searchControllerAttached = shouldAttach;
    SonoraApplySearchControllerAttachment(self.navigationItem,
                                      self.navigationController.navigationBar,
                                      self.searchController,
                                      shouldAttach,
                                      (self.view.window != nil));
}

- (void)applySearchFilterAndReload {
    self.filteredTracks = SonoraFilterTracksByQuery(self.tracks, self.searchQuery);
    [self.tableView reloadData];
}

- (void)createTapped {
    if (self.selectedTrackIDs.count == 0) {
        SonoraPresentAlert(self, @"No Music Selected", @"Select at least one track.");
        return;
    }

    NSMutableArray<NSString *> *orderedIDs = [NSMutableArray arrayWithCapacity:self.selectedTrackIDs.count];
    for (SonoraTrack *track in self.tracks) {
        if ([self.selectedTrackIDs containsObject:track.identifier]) {
            [orderedIDs addObject:track.identifier];
        }
    }

    SonoraPlaylist *playlist = [SonoraPlaylistStore.sharedStore addPlaylistWithName:self.playlistName
                                                                    trackIDs:orderedIDs
                                                                  coverImage:nil];
    if (playlist == nil) {
        SonoraPresentAlert(self, @"Error", @"Could not create playlist.");
        return;
    }

    SonoraPlaylistDetailViewController *detail = [[SonoraPlaylistDetailViewController alloc] initWithPlaylistID:playlist.playlistID];
    detail.hidesBottomBarWhenPushed = YES;
    UIViewController *root = self.navigationController.viewControllers.firstObject;
    if (root != nil) {
        [self.navigationController setViewControllers:@[root, detail] animated:YES];
    } else {
        [self.navigationController pushViewController:detail animated:YES];
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return self.filteredTracks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SonoraTrackCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TrackPickCell" forIndexPath:indexPath];

    SonoraTrack *track = self.filteredTracks[indexPath.row];
    BOOL selected = [self.selectedTrackIDs containsObject:track.identifier];
    [cell configureWithTrack:track isCurrent:selected];
    cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.row >= self.filteredTracks.count) {
        return;
    }
    SonoraTrack *track = self.filteredTracks[indexPath.row];
    if ([self.selectedTrackIDs containsObject:track.identifier]) {
        [self.selectedTrackIDs removeObject:track.identifier];
    } else {
        [self.selectedTrackIDs addObject:track.identifier];
    }

    [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.searchQuery = searchController.searchBar.text ?: @"";
    [self applySearchFilterAndReload];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView == self.tableView) {
        [self updateSearchControllerAttachment];
    }
}

@end

#pragma mark - Playlist Add Tracks

@interface SonoraPlaylistAddTracksViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, copy) NSString *playlistID;
@property (nonatomic, copy) NSArray<SonoraTrack *> *availableTracks;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedTrackIDs;
@property (nonatomic, strong) UITableView *tableView;

@end

@implementation SonoraPlaylistAddTracksViewController

- (instancetype)initWithPlaylistID:(NSString *)playlistID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _playlistID = [playlistID copy];
        _availableTracks = @[];
        _selectedTrackIDs = [NSMutableSet set];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Add Music";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Add"
                                                                               style:UIBarButtonItemStyleDone
                                                                              target:self
                                                                              action:@selector(addTapped)];
    self.navigationItem.rightBarButtonItem.enabled = NO;

    [self setupTableView];
    [self reloadAvailableTracks];
}

- (void)setupTableView {
    UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    tableView.translatesAutoresizingMaskIntoConstraints = NO;
    tableView.dataSource = self;
    tableView.delegate = self;
    tableView.rowHeight = 54.0;
    tableView.alwaysBounceVertical = YES;
    tableView.sectionHeaderHeight = 0.0;
    tableView.sectionFooterHeight = 0.0;
    tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    if (@available(iOS 15.0, *)) {
        tableView.sectionHeaderTopPadding = 0.0;
    }
    [tableView registerClass:SonoraTrackCell.class forCellReuseIdentifier:@"PlaylistAddTrackCell"];

    self.tableView = tableView;
    [self.view addSubview:tableView];

    [NSLayoutConstraint activateConstraints:@[
        [tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)reloadAvailableTracks {
    [SonoraPlaylistStore.sharedStore reloadPlaylists];
    SonoraPlaylist *playlist = [SonoraPlaylistStore.sharedStore playlistWithID:self.playlistID];
    if (playlist == nil) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }

    NSArray<SonoraTrack *> *libraryTracks = SonoraLibraryManager.sharedManager.tracks;
    if (libraryTracks.count == 0) {
        libraryTracks = [SonoraLibraryManager.sharedManager reloadTracks];
    }

    NSSet<NSString *> *existingIDs = [NSSet setWithArray:playlist.trackIDs ?: @[]];
    NSMutableArray<SonoraTrack *> *filteredTracks = [NSMutableArray arrayWithCapacity:libraryTracks.count];
    for (SonoraTrack *track in libraryTracks) {
        if (![existingIDs containsObject:track.identifier]) {
            [filteredTracks addObject:track];
        }
    }

    self.availableTracks = [filteredTracks copy];
    [self.selectedTrackIDs removeAllObjects];
    [self.tableView reloadData];
    [self updateAddButtonState];
    [self updateEmptyState];
}

- (void)updateAddButtonState {
    self.navigationItem.rightBarButtonItem.enabled = (self.selectedTrackIDs.count > 0);
}

- (void)updateEmptyState {
    if (self.availableTracks.count > 0) {
        self.tableView.backgroundView = nil;
        return;
    }

    UILabel *label = [[UILabel alloc] init];
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = UIColor.secondaryLabelColor;
    label.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    label.numberOfLines = 2;

    if (SonoraLibraryManager.sharedManager.tracks.count == 0) {
        label.text = @"No tracks in library.";
    } else {
        label.text = @"All tracks are already in this playlist.";
    }

    self.tableView.backgroundView = label;
}

- (void)addTapped {
    if (self.selectedTrackIDs.count == 0) {
        return;
    }

    NSMutableArray<NSString *> *orderedIDs = [NSMutableArray arrayWithCapacity:self.selectedTrackIDs.count];
    for (SonoraTrack *track in self.availableTracks) {
        if ([self.selectedTrackIDs containsObject:track.identifier]) {
            [orderedIDs addObject:track.identifier];
        }
    }

    BOOL added = [SonoraPlaylistStore.sharedStore addTrackIDs:orderedIDs toPlaylistID:self.playlistID];
    if (!added) {
        SonoraPresentAlert(self, @"Nothing Added", @"Selected tracks are already in this playlist.");
        return;
    }

    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return self.availableTracks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SonoraTrackCell *cell = [tableView dequeueReusableCellWithIdentifier:@"PlaylistAddTrackCell" forIndexPath:indexPath];

    SonoraTrack *track = self.availableTracks[indexPath.row];
    BOOL selected = [self.selectedTrackIDs containsObject:track.identifier];
    [cell configureWithTrack:track isCurrent:selected];
    cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    SonoraTrack *track = self.availableTracks[indexPath.row];
    if ([self.selectedTrackIDs containsObject:track.identifier]) {
        [self.selectedTrackIDs removeObject:track.identifier];
    } else {
        [self.selectedTrackIDs addObject:track.identifier];
    }

    [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    [self updateAddButtonState];
}

@end

#pragma mark - Playlist Cover Picker

@interface SonoraPlaylistCoverPickerViewController ()

@property (nonatomic, copy) NSString *playlistID;
@property (nonatomic, strong) UIImageView *previewView;

@end

@implementation SonoraPlaylistCoverPickerViewController

- (instancetype)initWithPlaylistID:(NSString *)playlistID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _playlistID = [playlistID copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Change Playlist Cover";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    [self setupUI];
    [self reloadPreview];
}

- (void)setupUI {
    UIImageView *previewView = [[UIImageView alloc] init];
    previewView.translatesAutoresizingMaskIntoConstraints = NO;
    previewView.contentMode = UIViewContentModeScaleAspectFill;
    previewView.layer.cornerRadius = 14.0;
    previewView.layer.masksToBounds = YES;
    self.previewView = previewView;

    UIButton *chooseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    chooseButton.translatesAutoresizingMaskIntoConstraints = NO;
    [chooseButton setTitle:@"Choose Image" forState:UIControlStateNormal];
    chooseButton.titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    [chooseButton addTarget:self action:@selector(chooseImageTapped) forControlEvents:UIControlEventTouchUpInside];

    UIButton *autoButton = [UIButton buttonWithType:UIButtonTypeSystem];
    autoButton.translatesAutoresizingMaskIntoConstraints = NO;
    [autoButton setTitle:@"Use Auto Cover" forState:UIControlStateNormal];
    autoButton.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    [autoButton addTarget:self action:@selector(resetAutoCoverTapped) forControlEvents:UIControlEventTouchUpInside];

    UILabel *hintLabel = [[UILabel alloc] init];
    hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    hintLabel.text = @"Select an image from Gallery.\nThis changes playlist cover only.";
    hintLabel.textColor = UIColor.secondaryLabelColor;
    hintLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
    hintLabel.textAlignment = NSTextAlignmentCenter;
    hintLabel.numberOfLines = 2;

    [self.view addSubview:previewView];
    [self.view addSubview:chooseButton];
    [self.view addSubview:autoButton];
    [self.view addSubview:hintLabel];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [previewView.topAnchor constraintEqualToAnchor:safe.topAnchor constant:20.0],
        [previewView.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [previewView.widthAnchor constraintEqualToConstant:220.0],
        [previewView.heightAnchor constraintEqualToConstant:220.0],

        [chooseButton.topAnchor constraintEqualToAnchor:previewView.bottomAnchor constant:20.0],
        [chooseButton.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],

        [autoButton.topAnchor constraintEqualToAnchor:chooseButton.bottomAnchor constant:10.0],
        [autoButton.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],

        [hintLabel.topAnchor constraintEqualToAnchor:autoButton.bottomAnchor constant:16.0],
        [hintLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16.0],
        [hintLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16.0]
    ]];
}

- (void)reloadPreview {
    [SonoraPlaylistStore.sharedStore reloadPlaylists];
    SonoraPlaylist *playlist = [SonoraPlaylistStore.sharedStore playlistWithID:self.playlistID];
    if (playlist == nil) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }

    self.previewView.image = [SonoraPlaylistStore.sharedStore coverForPlaylist:playlist
                                                                    library:SonoraLibraryManager.sharedManager
                                                                       size:CGSizeMake(320.0, 320.0)];
}

- (void)chooseImageTapped {
    PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
    configuration.filter = [PHPickerFilter imagesFilter];
    configuration.selectionLimit = 1;

    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)resetAutoCoverTapped {
    [SonoraPlaylistStore.sharedStore reloadPlaylists];
    SonoraPlaylist *playlist = [SonoraPlaylistStore.sharedStore playlistWithID:self.playlistID];
    if (playlist == nil) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }

    UIImage *autoCover = [self randomAutoCoverImageForPlaylist:playlist];
    BOOL success = [SonoraPlaylistStore.sharedStore setCustomCoverImage:autoCover forPlaylistID:self.playlistID];
    if (!success) {
        SonoraPresentAlert(self, @"Error", @"Could not reset cover.");
        return;
    }
    [self reloadPreview];
}

#pragma mark - PHPickerViewControllerDelegate

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];

    PHPickerResult *result = results.firstObject;
    if (result == nil) {
        return;
    }

    NSItemProvider *provider = result.itemProvider;
    if (![provider canLoadObjectOfClass:UIImage.class]) {
        SonoraPresentAlert(self, @"Error", @"Cannot read this image.");
        return;
    }

    __weak typeof(self) weakSelf = self;
    [provider loadObjectOfClass:UIImage.class
              completionHandler:^(id<NSItemProviderReading>  _Nullable object, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }

            if (error != nil || ![object isKindOfClass:UIImage.class]) {
                SonoraPresentAlert(strongSelf, @"Error", @"Cannot read this image.");
                return;
            }

            UIImage *image = (UIImage *)object;
            BOOL success = [SonoraPlaylistStore.sharedStore setCustomCoverImage:image forPlaylistID:strongSelf.playlistID];
            if (!success) {
                SonoraPresentAlert(strongSelf, @"Error", @"Could not set cover.");
                return;
            }

            [strongSelf reloadPreview];
        });
    }];
}

- (nullable UIImage *)randomAutoCoverImageForPlaylist:(SonoraPlaylist *)playlist {
    if (playlist == nil) {
        return nil;
    }

    if (SonoraLibraryManager.sharedManager.tracks.count == 0) {
        [SonoraLibraryManager.sharedManager reloadTracks];
    }

    NSArray<SonoraTrack *> *playlistTracks = [SonoraPlaylistStore.sharedStore tracksForPlaylist:playlist library:SonoraLibraryManager.sharedManager];
    if (playlistTracks.count == 0) {
        return nil;
    }

    NSMutableArray<SonoraTrack *> *shuffledTracks = [playlistTracks mutableCopy];
    for (NSInteger i = shuffledTracks.count - 1; i > 0; i -= 1) {
        u_int32_t j = arc4random_uniform((u_int32_t)(i + 1));
        [shuffledTracks exchangeObjectAtIndex:i withObjectAtIndex:j];
    }

    NSUInteger limit = MIN((NSUInteger)4, shuffledTracks.count);
    NSMutableArray<NSString *> *randomTrackIDs = [NSMutableArray arrayWithCapacity:limit];
    for (NSUInteger index = 0; index < limit; index += 1) {
        SonoraTrack *track = shuffledTracks[index];
        if (track.identifier.length > 0) {
            [randomTrackIDs addObject:track.identifier];
        }
    }

    if (randomTrackIDs.count == 0) {
        return nil;
    }

    SonoraPlaylist *tempPlaylist = [[SonoraPlaylist alloc] init];
    tempPlaylist.playlistID = @"sonora-auto-cover-temp";
    tempPlaylist.name = playlist.name ?: @"Playlist";
    tempPlaylist.trackIDs = [randomTrackIDs copy];
    tempPlaylist.customCoverFileName = nil;

    return [SonoraPlaylistStore.sharedStore coverForPlaylist:tempPlaylist
                                                 library:SonoraLibraryManager.sharedManager
                                                    size:CGSizeMake(320.0, 320.0)];
}

@end

#pragma mark - Playlist Detail

@interface SonoraPlaylistDetailViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>

@property (nonatomic, copy) NSString *playlistID;
@property (nonatomic, strong, nullable) SonoraPlaylist *playlist;
@property (nonatomic, copy) NSArray<SonoraTrack *> *tracks;
@property (nonatomic, copy) NSArray<SonoraTrack *> *filteredTracks;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UIButton *sleepButton;
@property (nonatomic, strong) UIButton *shuffleButton;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, copy) NSString *searchQuery;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, assign) BOOL compactTitleVisible;
@property (nonatomic, assign) BOOL searchControllerAttached;
@property (nonatomic, assign) BOOL multiSelectMode;
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *selectedTrackIDs;
@property (nonatomic, strong) UILongPressGestureRecognizer *selectionLongPressRecognizer;

@end

@implementation SonoraPlaylistDetailViewController

- (instancetype)initWithPlaylistID:(NSString *)playlistID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _playlistID = [playlistID copy];
        _tracks = @[];
        _filteredTracks = @[];
        _selectedTrackIDs = [NSMutableOrderedSet orderedSet];
        _multiSelectMode = NO;
    }
    return self;
}
- (void)refreshNavigationItemsForPlaylistSelectionState {
    if (self.multiSelectMode) {
        UIBarButtonItem *cancelItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"]
                                                                        style:UIBarButtonItemStylePlain
                                                                       target:self
                                                                       action:@selector(cancelPlaylistSelectionTapped)];
        UIBarButtonItem *favoriteItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"heart.fill"]
                                                                          style:UIBarButtonItemStylePlain
                                                                         target:self
                                                                         action:@selector(favoriteSelectedPlaylistTracksTapped)];
        favoriteItem.tintColor = [UIColor colorWithRed:1.0 green:0.35 blue:0.42 alpha:1.0];
        UIBarButtonItem *deleteItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"trash.fill"]
                                                                        style:UIBarButtonItemStylePlain
                                                                       target:self
                                                                       action:@selector(removeSelectedPlaylistTracksTapped)];
        self.navigationItem.rightBarButtonItems = @[cancelItem, deleteItem, favoriteItem];
        return;
    }
    [self updateOptionsButtonVisibility];
}

- (void)setPlaylistSelectionModeEnabled:(BOOL)enabled {
    self.multiSelectMode = enabled;
    if (!enabled) {
        [self.selectedTrackIDs removeAllObjects];
    }
    if (enabled && self.searchController.isActive) {
        self.searchController.active = NO;
    }
    [self refreshNavigationItemsForPlaylistSelectionState];
    [self updateNavigationTitleVisibility];
    [self.tableView reloadData];
}

- (SonoraTrack * _Nullable)playlistTrackAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row < 0 || indexPath.row >= self.filteredTracks.count) {
        return nil;
    }
    return self.filteredTracks[indexPath.row];
}

- (void)togglePlaylistSelectionForTrackID:(NSString *)trackID forceSelected:(BOOL)forceSelected {
    if (trackID.length == 0) {
        return;
    }
    BOOL hasTrack = [self.selectedTrackIDs containsObject:trackID];
    if (forceSelected) {
        if (!hasTrack) {
            [self.selectedTrackIDs addObject:trackID];
        }
    } else if (hasTrack) {
        [self.selectedTrackIDs removeObject:trackID];
    } else {
        [self.selectedTrackIDs addObject:trackID];
    }

    if (self.selectedTrackIDs.count == 0) {
        [self setPlaylistSelectionModeEnabled:NO];
    } else {
        [self refreshNavigationItemsForPlaylistSelectionState];
        [self updateNavigationTitleVisibility];
        [self.tableView reloadData];
    }
}

- (void)handleTrackLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) {
        return;
    }
    CGPoint point = [gesture locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:point];
    if (indexPath == nil) {
        return;
    }
    SonoraTrack *track = [self playlistTrackAtIndexPath:indexPath];
    if (track == nil) {
        return;
    }
    [self setPlaylistSelectionModeEnabled:YES];
    [self togglePlaylistSelectionForTrackID:track.identifier forceSelected:YES];
}

- (void)favoriteSelectedPlaylistTracksTapped {
    if (self.selectedTrackIDs.count == 0) {
        return;
    }
    for (NSString *trackID in self.selectedTrackIDs) {
        [SonoraFavoritesStore.sharedStore setTrackID:trackID favorite:YES];
    }
    [self setPlaylistSelectionModeEnabled:NO];
    [self reloadData];
}

- (void)removeSelectedPlaylistTracksTapped {
    if (self.selectedTrackIDs.count == 0) {
        return;
    }
    for (NSString *trackID in self.selectedTrackIDs) {
        [SonoraPlaylistStore.sharedStore removeTrackID:trackID fromPlaylistID:self.playlistID];
    }
    [self setPlaylistSelectionModeEnabled:NO];
    [self reloadData];
}

- (void)cancelPlaylistSelectionTapped {
    [self setPlaylistSelectionModeEnabled:NO];
}


- (void)viewDidLoad {
    [super viewDidLoad];

    self.navigationItem.titleView = nil;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.navigationItem.rightBarButtonItem = nil;
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    [self setupTableView];
    [self setupSearch];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(reloadData)
                                               name:SonoraPlaylistsDidChangeNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handleAppForeground)
                                               name:UIApplicationWillEnterForegroundNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handlePlaybackChanged)
                                               name:SonoraPlaybackStateDidChangeNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(updateSleepButton)
                                               name:SonoraSleepTimerDidChangeNotification
                                             object:nil];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshNavigationItemsForPlaylistSelectionState];
    [self updateSearchControllerAttachment];
    [self reloadData];
}

- (void)handleAppForeground {
    [SonoraLibraryManager.sharedManager reloadTracks];
    [self reloadData];
}

- (void)handlePlaybackChanged {
    [self updatePlayButtonState];
    [self.tableView reloadData];
}

- (void)setupTableView {
    UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    tableView.translatesAutoresizingMaskIntoConstraints = NO;
    tableView.dataSource = self;
    tableView.delegate = self;
    tableView.rowHeight = 54.0;
    tableView.alwaysBounceVertical = YES;
    tableView.sectionHeaderHeight = 0.0;
    tableView.sectionFooterHeight = 0.0;
    tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    if (@available(iOS 15.0, *)) {
        tableView.sectionHeaderTopPadding = 0.0;
    }
    [tableView registerClass:SonoraTrackCell.class forCellReuseIdentifier:@"PlaylistTrackCell"];
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                                                             action:@selector(handleTrackLongPress:)];
    [tableView addGestureRecognizer:longPress];
    self.selectionLongPressRecognizer = longPress;

    self.tableView = tableView;
    [self.view addSubview:tableView];

    [NSLayoutConstraint activateConstraints:@[
        [tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    self.tableView.tableHeaderView = [self headerViewForWidth:self.view.bounds.size.width];
    [self updatePlayButtonState];
    [self updateSleepButton];
}

- (void)setupSearch {
    self.searchController = SonoraBuildSearchController(self, @"Search In Playlist");
    self.navigationItem.searchController = nil;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
    self.definesPresentationContext = YES;
    self.searchControllerAttached = NO;
}

- (void)updateSearchControllerAttachment {
    BOOL shouldAttach = SonoraShouldAttachSearchController(self.searchControllerAttached,
                                                       self.searchController,
                                                       self.tableView,
                                                       SonoraSearchRevealThreshold);
    if (shouldAttach == self.searchControllerAttached) {
        return;
    }

    self.searchControllerAttached = shouldAttach;
    SonoraApplySearchControllerAttachment(self.navigationItem,
                                      self.navigationController.navigationBar,
                                      self.searchController,
                                      shouldAttach,
                                      (self.view.window != nil));
}

- (void)applySearchFilterAndReload {
    self.filteredTracks = SonoraFilterTracksByQuery(self.tracks, self.searchQuery);
    [self.tableView reloadData];
    [self updateEmptyState];
}

- (void)updateEmptyState {
    if (self.filteredTracks.count > 0) {
        self.tableView.backgroundView = nil;
        return;
    }

    UILabel *label = [[UILabel alloc] init];
    label.textColor = UIColor.secondaryLabelColor;
    label.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    if (self.tracks.count == 0) {
        label.text = @"Tracks missing. Re-add files to On My iPhone/Sonora/Sonora";
    } else {
        label.text = @"No matching tracks.";
    }
    self.tableView.backgroundView = label;
}

- (UIView *)headerViewForWidth:(CGFloat)width {
    CGFloat totalWidth = MAX(width, 320.0);
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, totalWidth, 374.0)];

    UIImageView *coverView = [[UIImageView alloc] initWithFrame:CGRectMake((totalWidth - 212.0) * 0.5, 16.0, 212.0, 212.0)];
    coverView.layer.cornerRadius = 16.0;
    coverView.layer.masksToBounds = YES;
    coverView.contentMode = UIViewContentModeScaleAspectFill;
    self.coverView = coverView;

    UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(14.0, 236.0, totalWidth - 28.0, 32.0)];
    nameLabel.textAlignment = NSTextAlignmentCenter;
    nameLabel.font = SonoraHeadlineFont(28.0);
    nameLabel.textColor = UIColor.labelColor;
    self.nameLabel = nameLabel;

    CGFloat playSize = 66.0;
    CGFloat sideControlSize = 46.0;
    CGFloat shuffleSize = 46.0;
    CGFloat controlsY = 272.0;

    UIButton *playButton = [UIButton buttonWithType:UIButtonTypeSystem];
    playButton.frame = CGRectMake((totalWidth - playSize) * 0.5, controlsY, playSize, playSize);
    playButton.backgroundColor = SonoraAccentYellowColor();
    playButton.tintColor = UIColor.whiteColor;
    playButton.layer.cornerRadius = playSize * 0.5;
    playButton.layer.masksToBounds = YES;
    UIImageSymbolConfiguration *playConfig = [UIImageSymbolConfiguration configurationWithPointSize:29.0
                                                                                               weight:UIImageSymbolWeightSemibold];
    [playButton setImage:[UIImage systemImageNamed:@"play.fill" withConfiguration:playConfig] forState:UIControlStateNormal];
    [playButton addTarget:self action:@selector(playTapped) forControlEvents:UIControlEventTouchUpInside];
    self.playButton = playButton;

    UIButton *sleepButton = [UIButton buttonWithType:UIButtonTypeSystem];
    sleepButton.frame = CGRectMake(CGRectGetMinX(playButton.frame) - 16.0 - sideControlSize,
                                   controlsY + (playSize - sideControlSize) * 0.5,
                                   sideControlSize,
                                   sideControlSize);
    UIImageSymbolConfiguration *sleepConfig = [UIImageSymbolConfiguration configurationWithPointSize:22.0
                                                                                               weight:UIImageSymbolWeightSemibold];
    [sleepButton setImage:[UIImage systemImageNamed:@"moon.zzz" withConfiguration:sleepConfig] forState:UIControlStateNormal];
    sleepButton.tintColor = SonoraPlayerPrimaryColor();
    sleepButton.backgroundColor = UIColor.clearColor;
    [sleepButton addTarget:self action:@selector(sleepTimerTapped) forControlEvents:UIControlEventTouchUpInside];
    self.sleepButton = sleepButton;

    UIButton *shuffleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    shuffleButton.frame = CGRectMake(CGRectGetMaxX(playButton.frame) + 16.0,
                                     controlsY + (playSize - shuffleSize) * 0.5,
                                     shuffleSize,
                                     shuffleSize);
    UIImageSymbolConfiguration *shuffleConfig = [UIImageSymbolConfiguration configurationWithPointSize:22.0
                                                                                                 weight:UIImageSymbolWeightSemibold];
    [shuffleButton setImage:[UIImage systemImageNamed:@"shuffle" withConfiguration:shuffleConfig] forState:UIControlStateNormal];
    shuffleButton.tintColor = SonoraPlayerPrimaryColor();
    shuffleButton.backgroundColor = UIColor.clearColor;
    [shuffleButton addTarget:self action:@selector(shuffleTapped) forControlEvents:UIControlEventTouchUpInside];
    self.shuffleButton = shuffleButton;

    [header addSubview:coverView];
    [header addSubview:nameLabel];
    [header addSubview:sleepButton];
    [header addSubview:playButton];
    [header addSubview:shuffleButton];

    return header;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat width = self.view.bounds.size.width;
    if (fabs(self.tableView.tableHeaderView.bounds.size.width - width) > 1.0) {
        self.tableView.tableHeaderView = [self headerViewForWidth:width];
        [self updateHeader];
        [self updatePlayButtonState];
        [self updateSleepButton];
    }
    [self updateNavigationTitleVisibility];
}

- (BOOL)isLovelyPlaylist {
    if (self.playlist == nil) {
        return NO;
    }

    NSString *lovelyID = [NSUserDefaults.standardUserDefaults stringForKey:SonoraLovelyPlaylistDefaultsKey];
    if (lovelyID.length > 0 && [self.playlist.playlistID isEqualToString:lovelyID]) {
        return YES;
    }
    return ([self.playlist.name localizedCaseInsensitiveCompare:@"Lovely songs"] == NSOrderedSame);
}

- (void)updateOptionsButtonVisibility {
    if (self.multiSelectMode) {
        return;
    }
    if (self.playlist == nil || [self isLovelyPlaylist]) {
        self.navigationItem.rightBarButtonItem = nil;
        return;
    }
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:18.0
                                                                                          weight:UIImageSymbolWeightBold];
    UIImage *optionsImage = [UIImage systemImageNamed:@"ellipsis" withConfiguration:config];
    if (optionsImage == nil) {
        optionsImage = [UIImage imageNamed:@"tab_ellipsis"];
    }
    if (optionsImage != nil) {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:optionsImage
                                                                                   style:UIBarButtonItemStylePlain
                                                                                  target:self
                                                                                  action:@selector(optionsTapped)];
    } else {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"..."
                                                                                   style:UIBarButtonItemStylePlain
                                                                                  target:self
                                                                                  action:@selector(optionsTapped)];
    }
}

- (void)reloadData {
    [SonoraPlaylistStore.sharedStore reloadPlaylists];

    self.playlist = [SonoraPlaylistStore.sharedStore playlistWithID:self.playlistID];
    if (self.playlist == nil) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    [self updateOptionsButtonVisibility];

    if (SonoraLibraryManager.sharedManager.tracks.count == 0 && self.playlist.trackIDs.count > 0) {
        [SonoraLibraryManager.sharedManager reloadTracks];
    }
    self.tracks = [SonoraPlaylistStore.sharedStore tracksForPlaylist:self.playlist library:SonoraLibraryManager.sharedManager];
    [self updateHeader];
    [self updatePlayButtonState];
    [self updateSleepButton];
    [self updateNavigationTitleVisibility];
    [self refreshNavigationItemsForPlaylistSelectionState];
    [self applySearchFilterAndReload];
}

- (void)updateHeader {
    if (self.playlist == nil) {
        return;
    }

    self.nameLabel.text = self.playlist.name;
    UIImage *cover = [SonoraPlaylistStore.sharedStore coverForPlaylist:self.playlist
                                                           library:SonoraLibraryManager.sharedManager
                                                              size:CGSizeMake(240.0, 240.0)];
    self.coverView.image = cover;

    if (self.playButton != nil) {
        NSString *lovelyID = [NSUserDefaults.standardUserDefaults stringForKey:SonoraLovelyPlaylistDefaultsKey];
        BOOL isLovely = ((lovelyID.length > 0 && [self.playlist.playlistID isEqualToString:lovelyID]) ||
                         [self.playlist.name localizedCaseInsensitiveCompare:@"Lovely songs"] == NSOrderedSame);
        UIColor *targetColor = nil;
        if (isLovely) {
            targetColor = SonoraLovelyAccentRedColor();
        } else {
            UIImage *accentSource = cover;
            if (accentSource == nil || accentSource.CGImage == nil) {
                for (SonoraTrack *track in self.tracks) {
                    if (track.artwork != nil) {
                        accentSource = track.artwork;
                        break;
                    }
                }
            }

            targetColor = [SonoraArtworkAccentColorService dominantAccentColorForImage:accentSource
                                                                           fallback:SonoraAccentYellowColor()];
        }
        if (targetColor == nil) {
            targetColor = SonoraAccentYellowColor();
        }

        UIColor *currentColor = self.playButton.backgroundColor;
        if (currentColor == nil || !CGColorEqualToColor(currentColor.CGColor, targetColor.CGColor)) {
            [UIView animateWithDuration:0.22
                                  delay:0.0
                                options:(UIViewAnimationOptionAllowUserInteraction |
                                         UIViewAnimationOptionBeginFromCurrentState)
                             animations:^{
                self.playButton.backgroundColor = targetColor;
            }
                             completion:nil];
        }
    }

    [self updatePlayButtonState];
}

- (BOOL)isCurrentQueueMatchingPlaylist {
    if (self.tracks.count == 0) {
        return NO;
    }

    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    return SonoraTrackQueuesMatchByIdentifier(playback.currentQueue, self.tracks);
}

- (void)updatePlayButtonState {
    if (self.playButton == nil) {
        return;
    }

    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    BOOL isPlaylistPlaying = [self isCurrentQueueMatchingPlaylist] &&
    playback.isPlaying &&
    (playback.currentTrack != nil);
    NSString *symbol = isPlaylistPlaying ? @"pause.fill" : @"play.fill";
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:29.0
                                                                                          weight:UIImageSymbolWeightSemibold];
    [self.playButton setImage:[UIImage systemImageNamed:symbol withConfiguration:config] forState:UIControlStateNormal];
    self.playButton.accessibilityLabel = isPlaylistPlaying ? @"Pause playlist" : @"Play playlist";
}

- (void)updateNavigationTitleVisibility {
    if (self.multiSelectMode) {
        self.navigationItem.titleView = nil;
        self.navigationItem.title = [NSString stringWithFormat:@"%lu Selected", (unsigned long)self.selectedTrackIDs.count];
        self.compactTitleVisible = YES;
        return;
    }
    if (self.playlist == nil) {
        self.navigationItem.title = nil;
        self.navigationItem.titleView = nil;
        self.compactTitleVisible = NO;
        return;
    }

    BOOL shouldShowCompact = self.tableView.contentOffset.y > 175.0;
    if (shouldShowCompact == self.compactTitleVisible) {
        return;
    }

    self.compactTitleVisible = shouldShowCompact;
    if (shouldShowCompact) {
        self.navigationItem.titleView = nil;
        self.navigationItem.title = self.playlist.name;
    } else {
        self.navigationItem.title = nil;
        self.navigationItem.titleView = nil;
    }
}

- (void)openPlayer {
    SonoraPlayerViewController *player = [[SonoraPlayerViewController alloc] init];
    player.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:player animated:YES];
}

- (void)playTapped {
    if (self.tracks.count == 0) {
        SonoraPresentAlert(self, @"No Tracks", @"This playlist has no available tracks.");
        return;
    }

    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    if ([self isCurrentQueueMatchingPlaylist] && playback.currentTrack != nil) {
        [playback togglePlayPause];
        [self updatePlayButtonState];
        [self.tableView reloadData];
        return;
    }

    NSArray<SonoraTrack *> *queue = self.tracks;
    [self openPlayer];
    dispatch_async(dispatch_get_main_queue(), ^{
        [playback setShuffleEnabled:NO];
        [playback playTracks:queue startIndex:0];
        [self updatePlayButtonState];
        [self.tableView reloadData];
    });
}

- (void)shuffleTapped {
    if (self.tracks.count == 0) {
        SonoraPresentAlert(self, @"No Tracks", @"This playlist has no available tracks.");
        return;
    }

    NSInteger randomStart = (NSInteger)arc4random_uniform((u_int32_t)self.tracks.count);
    NSArray<SonoraTrack *> *queue = self.tracks;
    [self openPlayer];
    dispatch_async(dispatch_get_main_queue(), ^{
        [SonoraPlaybackManager.sharedManager playTracks:queue startIndex:randomStart];
        [SonoraPlaybackManager.sharedManager setShuffleEnabled:YES];
        [self updatePlayButtonState];
        [self.tableView reloadData];
    });
}

- (void)sleepTimerTapped {
    __weak typeof(self) weakSelf = self;
    SonoraPresentSleepTimerActionSheet(self, self.sleepButton, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf updateSleepButton];
    });
}

- (void)updateSleepButton {
    if (self.sleepButton == nil) {
        return;
    }

    SonoraSleepTimerManager *sleepTimer = SonoraSleepTimerManager.sharedManager;
    BOOL isActive = sleepTimer.isActive;
    NSString *symbol = isActive ? @"moon.zzz.fill" : @"moon.zzz";
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:22.0
                                                                                          weight:UIImageSymbolWeightSemibold];
    [self.sleepButton setImage:[UIImage systemImageNamed:symbol withConfiguration:config] forState:UIControlStateNormal];
    UIColor *inactiveColor = [UIColor labelColor];
    self.sleepButton.tintColor = isActive ? SonoraAccentYellowColor() : inactiveColor;
    if (self.shuffleButton != nil) {
        self.shuffleButton.tintColor = inactiveColor;
    }
    self.sleepButton.accessibilityLabel = isActive
    ? [NSString stringWithFormat:@"Sleep timer active, %@ remaining", SonoraSleepTimerRemainingString(sleepTimer.remainingTime)]
    : @"Sleep timer";
}

- (void)optionsTapped {
    if (self.playlist == nil) {
        return;
    }
    if ([self isLovelyPlaylist]) {
        return;
    }

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:self.playlist.name
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Rename Playlist"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction * _Nonnull action) {
        [self renamePlaylistTapped];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Change Cover"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction * _Nonnull action) {
        [self changeCoverTapped];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Add Music"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction * _Nonnull action) {
        [self addMusicTapped];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Delete Playlist"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(__unused UIAlertAction * _Nonnull action) {
        [self deletePlaylistTapped];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover != nil) {
        popover.barButtonItem = self.navigationItem.rightBarButtonItem;
    }

    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)renamePlaylistTapped {
    if (self.playlist == nil) {
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Rename Playlist"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"Playlist Name";
        textField.text = self.playlist.name;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction * _Nonnull action) {
        NSString *name = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (name.length == 0) {
            SonoraPresentAlert(self, @"Name Required", @"Enter playlist name.");
            return;
        }

        BOOL renamed = [SonoraPlaylistStore.sharedStore renamePlaylistWithID:self.playlistID newName:name];
        if (!renamed) {
            SonoraPresentAlert(self, @"Error", @"Could not rename playlist.");
            return;
        }

        [self reloadData];
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)changeCoverTapped {
    SonoraPlaylistCoverPickerViewController *coverPicker = [[SonoraPlaylistCoverPickerViewController alloc] initWithPlaylistID:self.playlistID];
    coverPicker.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:coverPicker animated:YES];
}

- (void)addMusicTapped {
    SonoraPlaylistAddTracksViewController *addTracks = [[SonoraPlaylistAddTracksViewController alloc] initWithPlaylistID:self.playlistID];
    addTracks.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:addTracks animated:YES];
}

- (void)deletePlaylistTapped {
    if (self.playlist == nil) {
        return;
    }

    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"Delete Playlist?"
                                                                      message:self.playlist.name
                                                               preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                style:UIAlertActionStyleCancel
                                              handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Delete"
                                                style:UIAlertActionStyleDestructive
                                              handler:^(__unused UIAlertAction * _Nonnull action) {
        BOOL deleted = [SonoraPlaylistStore.sharedStore deletePlaylistWithID:self.playlistID];
        if (!deleted) {
            SonoraPresentAlert(self, @"Error", @"Could not delete playlist.");
            return;
        }
        [self.navigationController popViewControllerAnimated:YES];
    }]];

    [self presentViewController:confirm animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return self.filteredTracks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SonoraTrackCell *cell = [tableView dequeueReusableCellWithIdentifier:@"PlaylistTrackCell" forIndexPath:indexPath];

    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    SonoraTrack *track = self.filteredTracks[indexPath.row];
    SonoraTrack *currentTrack = playback.currentTrack;
    BOOL isCurrent = (currentTrack != nil && [currentTrack.identifier isEqualToString:track.identifier]);
    BOOL sameQueue = [self isCurrentQueueMatchingPlaylist];
    BOOL showsPlaybackIndicator = (sameQueue && isCurrent && playback.isPlaying);

    [cell configureWithTrack:track isCurrent:isCurrent showsPlaybackIndicator:showsPlaybackIndicator];
    cell.accessoryType = (self.multiSelectMode && [self.selectedTrackIDs containsObject:track.identifier])
    ? UITableViewCellAccessoryCheckmark
    : UITableViewCellAccessoryNone;
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.row >= self.filteredTracks.count) {
        return;
    }

    if (self.multiSelectMode) {
        SonoraTrack *selectionTrack = [self playlistTrackAtIndexPath:indexPath];
        if (selectionTrack != nil) {
            [self togglePlaylistSelectionForTrackID:selectionTrack.identifier forceSelected:NO];
        }
        return;
    }

    SonoraTrack *selectedTrack = self.filteredTracks[indexPath.row];
    SonoraTrack *currentTrack = SonoraPlaybackManager.sharedManager.currentTrack;
    if (currentTrack != nil && [currentTrack.identifier isEqualToString:selectedTrack.identifier]) {
        [self openPlayer];
        return;
    }

    NSArray<SonoraTrack *> *queue = self.filteredTracks;
    NSInteger startIndex = indexPath.row;
    [self openPlayer];
    dispatch_async(dispatch_get_main_queue(), ^{
        [SonoraPlaybackManager.sharedManager setShuffleEnabled:NO];
        [SonoraPlaybackManager.sharedManager playTracks:queue startIndex:startIndex];
    });
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView == self.tableView) {
        [self updateNavigationTitleVisibility];
        [self updateSearchControllerAttachment];
    }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (self.multiSelectMode) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }
    if (indexPath.row >= self.filteredTracks.count) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }

    SonoraTrack *track = self.filteredTracks[indexPath.row];

    UIContextualAction *removeAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                                title:@"Remove"
                                                                              handler:^(__unused UIContextualAction * _Nonnull action,
                                                                                        __unused UIView * _Nonnull sourceView,
                                                                                        void (^ _Nonnull completionHandler)(BOOL)) {
        BOOL removed = [SonoraPlaylistStore.sharedStore removeTrackID:track.identifier fromPlaylistID:self.playlistID];
        if (!removed) {
            SonoraPresentAlert(self, @"Could Not Remove", @"Track could not be removed from playlist.");
            completionHandler(NO);
            return;
        }
        [self reloadData];
        completionHandler(YES);
    }];
    removeAction.image = [UIImage systemImageNamed:@"trash.fill"];

    UIContextualAction *addAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                            title:@"Add"
                                                                          handler:^(__unused UIContextualAction * _Nonnull action,
                                                                                    __unused UIView * _Nonnull sourceView,
                                                                                    void (^ _Nonnull completionHandler)(BOOL)) {
        SonoraPresentQuickAddTrackToPlaylist(self, track.identifier, nil);
        completionHandler(YES);
    }];
    addAction.image = [UIImage systemImageNamed:@"text.badge.plus"];
    addAction.backgroundColor = [UIColor colorWithRed:0.16 green:0.47 blue:0.95 alpha:1.0];

    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[removeAction, addAction]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (self.multiSelectMode) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }
    if (indexPath.row >= self.filteredTracks.count) {
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }

    SonoraTrack *track = self.filteredTracks[indexPath.row];
    BOOL isFavorite = [SonoraFavoritesStore.sharedStore isTrackFavoriteByID:track.identifier];
    NSString *iconName = isFavorite ? @"heart.slash.fill" : @"heart.fill";

    UIContextualAction *favoriteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                                  title:nil
                                                                                handler:^(__unused UIContextualAction * _Nonnull action,
                                                                                          __unused UIView * _Nonnull sourceView,
                                                                                          void (^ _Nonnull completionHandler)(BOOL)) {
        [SonoraFavoritesStore.sharedStore setTrackID:track.identifier favorite:!isFavorite];
        completionHandler(YES);
    }];
    favoriteAction.image = [UIImage systemImageNamed:iconName];
    favoriteAction.backgroundColor = isFavorite
    ? [UIColor colorWithWhite:0.40 alpha:1.0]
    : [UIColor colorWithRed:1.0 green:0.35 blue:0.42 alpha:1.0];

    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[favoriteAction]];
    configuration.performsFirstActionWithFullSwipe = YES;
    return configuration;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.searchQuery = searchController.searchBar.text ?: @"";
    [self applySearchFilterAndReload];
}

@end

#pragma mark - Player

@interface SonoraArtworkEqualizerBadgeView : UIView

- (void)setBarColor:(UIColor *)color;
- (void)setPlaying:(BOOL)playing;
- (void)setLevel:(CGFloat)level;

@end

@interface SonoraArtworkEqualizerBadgeView ()

@property (nonatomic, copy) NSArray<UIView *> *barViews;
@property (nonatomic, copy) NSArray<NSLayoutConstraint *> *barHeightConstraints;
@property (nonatomic, assign) BOOL playing;

@end

@implementation SonoraArtworkEqualizerBadgeView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.userInteractionEnabled = NO;
        self.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.58];
        self.layer.cornerRadius = 8.0;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.20].CGColor;
        self.layer.masksToBounds = YES;

        NSArray<NSNumber *> *heights = @[@5.0, @8.0, @9.0, @6.0];
        NSMutableArray<UIView *> *bars = [NSMutableArray arrayWithCapacity:heights.count];
        NSMutableArray<NSLayoutConstraint *> *heightConstraints = [NSMutableArray arrayWithCapacity:heights.count];
        UIView *previousBar = nil;
        for (NSNumber *height in heights) {
            UIView *bar = [[UIView alloc] init];
            bar.translatesAutoresizingMaskIntoConstraints = NO;
            bar.backgroundColor = UIColor.whiteColor;
            bar.layer.cornerRadius = 1.3;
            bar.layer.masksToBounds = YES;
            [self addSubview:bar];
            [bars addObject:bar];

            NSLayoutConstraint *heightConstraint = [bar.heightAnchor constraintEqualToConstant:height.doubleValue];
            [NSLayoutConstraint activateConstraints:@[
                [bar.widthAnchor constraintEqualToConstant:2.4],
                heightConstraint,
                [bar.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-4.0]
            ]];
            [heightConstraints addObject:heightConstraint];
            if (previousBar == nil) {
                [bar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:6.0].active = YES;
            } else {
                [bar.leadingAnchor constraintEqualToAnchor:previousBar.trailingAnchor constant:2.5].active = YES;
            }
            previousBar = bar;
        }
        [previousBar.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-6.0].active = YES;
        self.barViews = [bars copy];
        self.barHeightConstraints = [heightConstraints copy];
    }
    return self;
}

- (void)setBarColor:(UIColor *)color {
    UIColor *resolved = color ?: UIColor.whiteColor;
    for (UIView *bar in self.barViews) {
        bar.backgroundColor = resolved;
    }
}

- (void)setPlaying:(BOOL)playing {
    _playing = playing;
    self.alpha = playing ? 1.0 : 0.90;
}

- (void)setLevel:(CGFloat)level {
    CGFloat clamped = MIN(MAX(level, 0.0), 1.0);
    NSArray<NSNumber *> *weights = @[@0.62, @0.92, @1.0, @0.76];

    for (NSUInteger index = 0; index < self.barHeightConstraints.count; index += 1) {
        CGFloat weight = [weights[index] doubleValue];
        CGFloat base = self.playing ? 4.0 : 3.2;
        CGFloat dynamic = clamped * (self.playing ? 14.0 : 5.0) * weight;
        self.barHeightConstraints[index].constant = base + dynamic;
    }

    if (self.window != nil) {
        [UIView animateWithDuration:0.16
                              delay:0.0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            [self layoutIfNeeded];
        } completion:nil];
    }
}

@end

@interface SonoraPlayerViewController ()

@property (nonatomic, strong) UIImageView *artworkView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UISlider *progressSlider;
@property (nonatomic, strong) UILabel *elapsedLabel;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) UILabel *nextPreviewLabel;
@property (nonatomic, strong) UIButton *shuffleButton;
@property (nonatomic, strong) UIButton *repeatButton;
@property (nonatomic, strong) UIButton *previousButton;
@property (nonatomic, strong) UIButton *playPauseButton;
@property (nonatomic, strong) UIButton *nextButton;
@property (nonatomic, strong) UIButton *favoriteButton;
@property (nonatomic, strong) UIButton *sleepTimerButton;
@property (nonatomic, strong) SonoraArtworkEqualizerBadgeView *equalizerBadgeView;
@property (nonatomic, strong) NSLayoutConstraint *artworkLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *artworkTrailingConstraint;
@property (nonatomic, assign) BOOL scrubbing;

@end

@implementation SonoraPlayerViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = SonoraPlayerBackgroundColor();

    [self setupUI];
    [self applyPlayerTheme];

    if (@available(iOS 17.0, *)) {
        __weak typeof(self) weakSelf = self;
        [self registerForTraitChanges:@[UITraitUserInterfaceStyle.class]
                          withHandler:^(__kindof id<UITraitEnvironment>  _Nonnull traitEnvironment,
                                        UITraitCollection * _Nullable previousTraitCollection) {
            (void)traitEnvironment;
            (void)previousTraitCollection;
            __strong typeof(weakSelf) strongSelf = weakSelf;
            [strongSelf applyPlayerTheme];
            [strongSelf updateModeIcons];
        }];
    }

    UISwipeGestureRecognizer *swipeDown = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleDismissSwipe)];
    swipeDown.direction = UISwipeGestureRecognizerDirectionDown;
    [self.view addGestureRecognizer:swipeDown];

    UISwipeGestureRecognizer *swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleDismissSwipe)];
    swipeRight.direction = UISwipeGestureRecognizerDirectionRight;
    [self.view addGestureRecognizer:swipeRight];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(refreshUI)
                                               name:SonoraPlaybackStateDidChangeNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handleProgressChanged)
                                               name:SonoraPlaybackProgressDidChangeNotification
                                             object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handlePlaybackMeterChanged:)
                                               name:SonoraPlaybackMeterDidChangeNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(updateFavoriteButton)
                                               name:SonoraFavoritesDidChangeNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(updateSleepTimerButton)
                                               name:SonoraSleepTimerDidChangeNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(handlePlayerSettingsChanged:)
                                               name:SonoraPlayerSettingsDidChangeNotification
                                             object:nil];

    [self refreshUI];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    self.navigationController.interactivePopGestureRecognizer.enabled = YES;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateArtworkCornerRadius];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:animated];
}

- (void)setupUI {
    UIView *content = [[UIView alloc] init];
    content.translatesAutoresizingMaskIntoConstraints = NO;

    UIImageView *artworkView = [[UIImageView alloc] init];
    artworkView.translatesAutoresizingMaskIntoConstraints = NO;
    artworkView.contentMode = UIViewContentModeScaleAspectFill;
    artworkView.layer.cornerRadius = 0.0;
    artworkView.layer.masksToBounds = YES;
    self.artworkView = artworkView;

    SonoraArtworkEqualizerBadgeView *equalizerBadge = [[SonoraArtworkEqualizerBadgeView alloc] init];
    equalizerBadge.hidden = YES;
    self.equalizerBadgeView = equalizerBadge;
    [artworkView addSubview:equalizerBadge];

    UILabel *artistLabel = [[UILabel alloc] init];
    artistLabel.translatesAutoresizingMaskIntoConstraints = NO;
    artistLabel.textAlignment = NSTextAlignmentCenter;
    artistLabel.font = [UIFont systemFontOfSize:24.0 weight:UIFontWeightSemibold];
    artistLabel.numberOfLines = 1;
    self.subtitleLabel = artistLabel;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont systemFontOfSize:24.0 weight:UIFontWeightSemibold];
    titleLabel.numberOfLines = 1;
    self.titleLabel = titleLabel;

    UISlider *slider = [[UISlider alloc] init];
    slider.translatesAutoresizingMaskIntoConstraints = NO;
    slider.minimumValue = 0.0;
    slider.maximumValue = 1.0;
    slider.transform = CGAffineTransformMakeScale(1.0, 0.92);
    [slider addTarget:self action:@selector(sliderTouchDown) forControlEvents:UIControlEventTouchDown];
    [slider addTarget:self action:@selector(sliderChanged) forControlEvents:UIControlEventValueChanged];
    [slider addTarget:self action:@selector(sliderTouchUp) forControlEvents:UIControlEventTouchUpInside];
    [slider addTarget:self action:@selector(sliderTouchUp) forControlEvents:UIControlEventTouchUpOutside];
    [slider addTarget:self action:@selector(sliderTouchUp) forControlEvents:UIControlEventTouchCancel];
    self.progressSlider = slider;

    UILabel *elapsedLabel = [[UILabel alloc] init];
    elapsedLabel.translatesAutoresizingMaskIntoConstraints = NO;
    elapsedLabel.font = [UIFont monospacedDigitSystemFontOfSize:12.0 weight:UIFontWeightMedium];
    self.elapsedLabel = elapsedLabel;

    UILabel *durationLabel = [[UILabel alloc] init];
    durationLabel.translatesAutoresizingMaskIntoConstraints = NO;
    durationLabel.textAlignment = NSTextAlignmentRight;
    durationLabel.font = [UIFont monospacedDigitSystemFontOfSize:12.0 weight:UIFontWeightMedium];
    self.durationLabel = durationLabel;

    UILabel *nextPreviewLabel = [[UILabel alloc] init];
    nextPreviewLabel.translatesAutoresizingMaskIntoConstraints = NO;
    nextPreviewLabel.textAlignment = NSTextAlignmentLeft;
    nextPreviewLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightSemibold];
    nextPreviewLabel.numberOfLines = 2;
    self.nextPreviewLabel = nextPreviewLabel;

    self.repeatButton = SonoraPlainIconButton(@"repeat", 24.0, 600.0);
    [self.repeatButton addTarget:self action:@selector(toggleRepeatTapped) forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[
        [self.repeatButton.widthAnchor constraintEqualToConstant:42.0],
        [self.repeatButton.heightAnchor constraintEqualToConstant:42.0]
    ]];

    self.shuffleButton = SonoraPlainIconButton(@"shuffle", 24.0, 600.0);
    [self.shuffleButton addTarget:self action:@selector(toggleShuffleTapped) forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[
        [self.shuffleButton.widthAnchor constraintEqualToConstant:42.0],
        [self.shuffleButton.heightAnchor constraintEqualToConstant:42.0]
    ]];

    self.previousButton = SonoraPlainIconButton(@"backward.fill", 44.0, 700.0);
    [self.previousButton addTarget:self action:@selector(previousTapped) forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[
        [self.previousButton.widthAnchor constraintEqualToConstant:64.0],
        [self.previousButton.heightAnchor constraintEqualToConstant:64.0]
    ]];

    self.playPauseButton = SonoraPlainIconButton(@"play.fill", 56.0, 700.0);
    [self.playPauseButton addTarget:self action:@selector(playPauseTapped) forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[
        [self.playPauseButton.widthAnchor constraintEqualToConstant:76.0],
        [self.playPauseButton.heightAnchor constraintEqualToConstant:76.0]
    ]];

    self.nextButton = SonoraPlainIconButton(@"forward.fill", 44.0, 700.0);
    [self.nextButton addTarget:self action:@selector(nextTapped) forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[
        [self.nextButton.widthAnchor constraintEqualToConstant:64.0],
        [self.nextButton.heightAnchor constraintEqualToConstant:64.0]
    ]];

    self.favoriteButton = SonoraPlainIconButton(@"heart", 24.0, 600.0);
    [self.favoriteButton addTarget:self action:@selector(toggleFavoriteTapped) forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[
        [self.favoriteButton.widthAnchor constraintEqualToConstant:40.0],
        [self.favoriteButton.heightAnchor constraintEqualToConstant:40.0]
    ]];

    self.sleepTimerButton = SonoraPlainIconButton(@"moon.zzz", 23.0, 600.0);
    [self.sleepTimerButton addTarget:self action:@selector(sleepTimerTapped) forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[
        [self.sleepTimerButton.widthAnchor constraintEqualToConstant:40.0],
        [self.sleepTimerButton.heightAnchor constraintEqualToConstant:40.0]
    ]];

    UIStackView *modeStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.repeatButton, self.shuffleButton]];
    modeStack.translatesAutoresizingMaskIntoConstraints = NO;
    modeStack.axis = UILayoutConstraintAxisVertical;
    modeStack.alignment = UIStackViewAlignmentCenter;
    modeStack.distribution = UIStackViewDistributionEqualSpacing;
    modeStack.spacing = 10.0;

    UIStackView *rightStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.sleepTimerButton, self.favoriteButton]];
    rightStack.translatesAutoresizingMaskIntoConstraints = NO;
    rightStack.axis = UILayoutConstraintAxisVertical;
    rightStack.alignment = UIStackViewAlignmentCenter;
    rightStack.distribution = UIStackViewDistributionEqualSpacing;
    rightStack.spacing = 10.0;

    UIStackView *transportStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.previousButton, self.playPauseButton, self.nextButton
    ]];
    transportStack.translatesAutoresizingMaskIntoConstraints = NO;
    transportStack.axis = UILayoutConstraintAxisHorizontal;
    transportStack.alignment = UIStackViewAlignmentCenter;
    transportStack.distribution = UIStackViewDistributionEqualCentering;
    transportStack.spacing = 16.0;

    UIView *controlsRow = [[UIView alloc] init];
    controlsRow.translatesAutoresizingMaskIntoConstraints = NO;

    [content addSubview:artworkView];
    [content addSubview:slider];
    [content addSubview:elapsedLabel];
    [content addSubview:durationLabel];
    [content addSubview:artistLabel];
    [content addSubview:titleLabel];
    [content addSubview:nextPreviewLabel];
    [content addSubview:controlsRow];

    [controlsRow addSubview:modeStack];
    [controlsRow addSubview:transportStack];
    [controlsRow addSubview:rightStack];

    [self.view addSubview:content];

    NSLayoutConstraint *artworkSquare = [artworkView.heightAnchor constraintEqualToAnchor:artworkView.widthAnchor];
    artworkSquare.priority = UILayoutPriorityDefaultHigh;
    self.artworkLeadingConstraint = [artworkView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor];
    self.artworkTrailingConstraint = [artworkView.trailingAnchor constraintEqualToAnchor:content.trailingAnchor];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [content.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [content.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [content.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [artworkView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        self.artworkLeadingConstraint,
        self.artworkTrailingConstraint,
        artworkSquare,
        [artworkView.heightAnchor constraintLessThanOrEqualToAnchor:content.heightAnchor multiplier:0.56],
        [equalizerBadge.bottomAnchor constraintEqualToAnchor:artworkView.bottomAnchor constant:-10.0],
        [equalizerBadge.trailingAnchor constraintEqualToAnchor:artworkView.trailingAnchor constant:-10.0],
        [equalizerBadge.widthAnchor constraintEqualToConstant:30.0],
        [equalizerBadge.heightAnchor constraintEqualToConstant:24.0],

        [slider.topAnchor constraintEqualToAnchor:artworkView.bottomAnchor constant:16.0],
        [slider.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16.0],
        [slider.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16.0],

        [elapsedLabel.topAnchor constraintEqualToAnchor:slider.bottomAnchor constant:3.0],
        [elapsedLabel.leadingAnchor constraintEqualToAnchor:slider.leadingAnchor],

        [durationLabel.topAnchor constraintEqualToAnchor:elapsedLabel.topAnchor],
        [durationLabel.trailingAnchor constraintEqualToAnchor:slider.trailingAnchor],

        [artistLabel.topAnchor constraintEqualToAnchor:elapsedLabel.bottomAnchor constant:18.0],
        [artistLabel.leadingAnchor constraintEqualToAnchor:slider.leadingAnchor],
        [artistLabel.trailingAnchor constraintEqualToAnchor:slider.trailingAnchor],

        [titleLabel.topAnchor constraintEqualToAnchor:artistLabel.bottomAnchor constant:6.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:slider.leadingAnchor],
        [titleLabel.trailingAnchor constraintEqualToAnchor:slider.trailingAnchor],

        [controlsRow.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14.0],
        [controlsRow.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-14.0],
        [controlsRow.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-6.0],
        [controlsRow.heightAnchor constraintEqualToConstant:88.0],

        [modeStack.leadingAnchor constraintEqualToAnchor:controlsRow.leadingAnchor],
        [modeStack.centerYAnchor constraintEqualToAnchor:controlsRow.centerYAnchor],

        [transportStack.centerXAnchor constraintEqualToAnchor:controlsRow.centerXAnchor],
        [transportStack.centerYAnchor constraintEqualToAnchor:controlsRow.centerYAnchor],

        [rightStack.trailingAnchor constraintEqualToAnchor:controlsRow.trailingAnchor],
        [rightStack.centerYAnchor constraintEqualToAnchor:controlsRow.centerYAnchor],

        [nextPreviewLabel.leadingAnchor constraintEqualToAnchor:slider.leadingAnchor],
        [nextPreviewLabel.trailingAnchor constraintEqualToAnchor:slider.trailingAnchor],
        [nextPreviewLabel.topAnchor constraintGreaterThanOrEqualToAnchor:titleLabel.bottomAnchor constant:16.0],
        [nextPreviewLabel.bottomAnchor constraintEqualToAnchor:controlsRow.topAnchor constant:-14.0]
    ]];
}

- (void)handleDismissSwipe {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)applyPlayerTheme {
    UIColor *primary = SonoraPlayerPrimaryColor();
    UIColor *secondary = SonoraPlayerSecondaryColor();
    SonoraPlayerFontStyle fontStyle = SonoraPlayerFontStyleFromDefaults();

    self.view.backgroundColor = SonoraPlayerBackgroundColor();
    [self updateArtworkCornerRadius];
    self.titleLabel.textColor = primary;
    self.subtitleLabel.textColor = secondary;
    self.elapsedLabel.textColor = secondary;
    self.durationLabel.textColor = secondary;
    self.nextPreviewLabel.textColor = secondary;
    self.titleLabel.font = SonoraPlayerFontForStyle(fontStyle, 24.0, UIFontWeightSemibold);
    self.subtitleLabel.font = SonoraPlayerFontForStyle(fontStyle, 24.0, UIFontWeightSemibold);
    self.nextPreviewLabel.font = SonoraPlayerFontForStyle(fontStyle, 18.0, UIFontWeightSemibold);

    self.progressSlider.minimumTrackTintColor = primary;
    self.progressSlider.maximumTrackTintColor = SonoraPlayerTimelineMaxColor();
    UIImage *thumbImage = SonoraSliderThumbImage(14.5, primary);
    [self.progressSlider setThumbImage:thumbImage forState:UIControlStateNormal];
    [self.progressSlider setThumbImage:thumbImage forState:UIControlStateHighlighted];

    BOOL controlsEnabled = self.playPauseButton.enabled;
    UIColor *controlColor = controlsEnabled ? primary : [secondary colorWithAlphaComponent:0.65];
    NSArray<UIButton *> *buttons = @[
        self.repeatButton,
        self.shuffleButton,
        self.previousButton,
        self.playPauseButton,
        self.nextButton,
        self.favoriteButton,
        self.sleepTimerButton
    ];
    for (UIButton *button in buttons) {
        CGFloat height = CGRectGetHeight(button.bounds);
        if (height < 1.0) {
            [button layoutIfNeeded];
            height = CGRectGetHeight(button.bounds);
        }
        if (height < 1.0) {
            height = 42.0;
        }
        button.backgroundColor = UIColor.clearColor;
        button.layer.cornerRadius = 0.0;
        button.layer.masksToBounds = YES;
    }

    [self.equalizerBadgeView setBarColor:[UIColor colorWithWhite:1.0 alpha:0.96]];
    self.equalizerBadgeView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.58];

    self.repeatButton.tintColor = [primary colorWithAlphaComponent:0.92];
    self.shuffleButton.tintColor = [primary colorWithAlphaComponent:0.92];
    self.previousButton.tintColor = controlColor;
    self.playPauseButton.tintColor = controlColor;
    self.nextButton.tintColor = controlColor;
    [self updateFavoriteButton];
    [self updateSleepTimerButton];
    [self updateEqualizerBadge];
}

- (void)updateArtworkCornerRadius {
    SonoraPlayerArtworkStyle artworkStyle = SonoraPlayerArtworkStyleFromDefaults();
    CGFloat horizontalInset = (artworkStyle == SonoraPlayerArtworkStyleRounded) ? 12.0 : 0.0;
    self.artworkLeadingConstraint.constant = horizontalInset;
    self.artworkTrailingConstraint.constant = -horizontalInset;
    self.artworkView.layer.cornerRadius = SonoraArtworkCornerRadiusForStyle(artworkStyle, CGRectGetWidth(self.artworkView.bounds));
    self.artworkView.layer.masksToBounds = YES;
    if (@available(iOS 13.0, *)) {
        self.artworkView.layer.cornerCurve = kCACornerCurveContinuous;
    }
}

- (void)handlePlayerSettingsChanged:(NSNotification *)notification {
    (void)notification;
    [self applyPlayerTheme];
    [self updateEqualizerBadge];
}

- (void)previousTapped {
    [SonoraPlaybackManager.sharedManager playPrevious];
}

- (void)playPauseTapped {
    [SonoraPlaybackManager.sharedManager togglePlayPause];
}

- (void)nextTapped {
    [SonoraPlaybackManager.sharedManager playNext];
}

- (void)toggleShuffleTapped {
    [SonoraPlaybackManager.sharedManager toggleShuffleEnabled];
}

- (void)toggleRepeatTapped {
    [SonoraPlaybackManager.sharedManager cycleRepeatMode];
}

- (void)toggleFavoriteTapped {
    SonoraTrack *track = SonoraPlaybackManager.sharedManager.currentTrack;
    if (track.identifier.length == 0) {
        return;
    }
    [SonoraFavoritesStore.sharedStore toggleFavoriteForTrackID:track.identifier];
    [self updateFavoriteButton];
}

- (void)sleepTimerTapped {
    __weak typeof(self) weakSelf = self;
    SonoraPresentSleepTimerActionSheet(self, self.sleepTimerButton, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf updateSleepTimerButton];
    });
}

- (void)updateFavoriteButton {
    SonoraTrack *track = SonoraPlaybackManager.sharedManager.currentTrack;
    if (track == nil || track.identifier.length == 0) {
        self.favoriteButton.hidden = YES;
        self.favoriteButton.enabled = NO;
        return;
    }

    self.favoriteButton.hidden = NO;
    self.favoriteButton.enabled = YES;

    BOOL isFavorite = [SonoraFavoritesStore.sharedStore isTrackFavoriteByID:track.identifier];
    NSString *symbolName = isFavorite ? @"heart.fill" : @"heart";
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:24.0
                                                                                          weight:UIImageSymbolWeightSemibold];
    UIImage *image = [UIImage systemImageNamed:symbolName withConfiguration:config];
    [self.favoriteButton setImage:image forState:UIControlStateNormal];
    self.favoriteButton.tintColor = isFavorite ? [UIColor colorWithRed:1.0 green:0.35 blue:0.40 alpha:1.0]
                                               : [SonoraPlayerPrimaryColor() colorWithAlphaComponent:0.92];
}

- (void)updateSleepTimerButton {
    BOOL isActive = SonoraSleepTimerManager.sharedManager.isActive;
    NSString *symbol = isActive ? @"moon.zzz.fill" : @"moon.zzz";
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:23.0
                                                                                          weight:UIImageSymbolWeightSemibold];
    [self.sleepTimerButton setImage:[UIImage systemImageNamed:symbol withConfiguration:config] forState:UIControlStateNormal];
    self.sleepTimerButton.tintColor = isActive ? SonoraAccentYellowColor()
                                               : [SonoraPlayerPrimaryColor() colorWithAlphaComponent:0.92];
    self.sleepTimerButton.accessibilityLabel = isActive
    ? [NSString stringWithFormat:@"Sleep timer active, %@ remaining", SonoraSleepTimerRemainingString(SonoraSleepTimerManager.sharedManager.remainingTime)]
    : @"Sleep timer";
}

- (void)updateEqualizerBadge {
    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    BOOL enabled = SonoraArtworkEqualizerEnabledFromDefaults();
    BOOL hasTrack = (playback.currentTrack != nil);
    BOOL visible = enabled && hasTrack;
    self.equalizerBadgeView.hidden = !visible;
    if (!visible) {
        [self.equalizerBadgeView setPlaying:NO];
        [self.equalizerBadgeView setLevel:0.0];
        return;
    }

    BOOL isPlaying = playback.isPlaying;
    [self.equalizerBadgeView setPlaying:isPlaying];
    [self.equalizerBadgeView setLevel:isPlaying ? 0.18 : 0.06];
}

- (void)handlePlaybackMeterChanged:(NSNotification *)notification {
    if (self.equalizerBadgeView.hidden) {
        return;
    }

    NSNumber *levelNumber = notification.userInfo[@"level"];
    CGFloat level = [levelNumber isKindOfClass:NSNumber.class] ? (CGFloat)levelNumber.doubleValue : 0.0;
    BOOL isPlaying = SonoraPlaybackManager.sharedManager.isPlaying;
    [self.equalizerBadgeView setPlaying:isPlaying];
    [self.equalizerBadgeView setLevel:isPlaying ? level : 0.06];
}

- (void)sliderTouchDown {
    self.scrubbing = YES;
}

- (void)sliderChanged {
    self.elapsedLabel.text = SonoraFormatDuration(self.progressSlider.value);
}

- (void)sliderTouchUp {
    self.scrubbing = NO;
    [SonoraPlaybackManager.sharedManager seekToTime:self.progressSlider.value];
}

- (void)handleProgressChanged {
    if (!self.scrubbing) {
        [self refreshTimelineOnly];
    }
}

- (void)refreshTimelineOnly {
    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    NSTimeInterval duration = playback.duration;
    NSTimeInterval current = playback.currentTime;

    self.progressSlider.maximumValue = MAX(duration, 1.0);
    self.progressSlider.value = MIN(current, self.progressSlider.maximumValue);

    self.elapsedLabel.text = SonoraFormatDuration(current);
    self.durationLabel.text = SonoraFormatDuration(duration);
}

- (void)refreshUI {
    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    SonoraTrack *track = playback.currentTrack;

    if (track == nil) {
        self.artworkView.image = [UIImage systemImageNamed:@"music.note.list"];
        self.artworkView.contentMode = UIViewContentModeCenter;
        self.artworkView.tintColor = SonoraPlayerPrimaryColor();

        self.subtitleLabel.text = @"";
        self.titleLabel.text = @"No track selected";
        self.nextPreviewLabel.text = @"Next: -";

        self.playPauseButton.enabled = NO;
        self.previousButton.enabled = NO;
        self.nextButton.enabled = NO;

        self.progressSlider.maximumValue = 1.0;
        self.progressSlider.value = 0.0;
        self.elapsedLabel.text = @"0:00";
        self.durationLabel.text = @"0:00";

        [self applyPlayerTheme];
        [self updatePlayPauseIcon];
        [self updateModeIcons];
        [self updateFavoriteButton];
        [self updateSleepTimerButton];
        return;
    }

    self.artworkView.contentMode = UIViewContentModeScaleAspectFill;
    self.artworkView.image = track.artwork;

    self.subtitleLabel.text = (track.artist.length > 0 ? track.artist : @"");
    self.titleLabel.text = (track.title.length > 0 ? track.title : track.fileName);
    self.nextPreviewLabel.text = [self nextPreviewText];

    self.playPauseButton.enabled = YES;
    self.previousButton.enabled = YES;
    self.nextButton.enabled = YES;

    [self refreshTimelineOnly];
    [self applyPlayerTheme];
    [self updatePlayPauseIcon];
    [self updateModeIcons];
    [self updateFavoriteButton];
    [self updateSleepTimerButton];
}

- (NSString *)nextPreviewText {
    SonoraTrack *nextTrack = [SonoraPlaybackManager.sharedManager predictedNextTrackForSkip];

    if (nextTrack == nil) {
        return @"Next: -";
    }

    NSString *title = (nextTrack.title.length > 0 ? nextTrack.title : @"Unknown");
    if (nextTrack.artist.length > 0) {
        return [NSString stringWithFormat:@"Next: %@ - %@", nextTrack.artist, title];
    }
    return [NSString stringWithFormat:@"Next: %@", title];
}

- (void)updatePlayPauseIcon {
    NSString *symbol = SonoraPlaybackManager.sharedManager.isPlaying ? @"pause.fill" : @"play.fill";
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:56.0
                                                                                           weight:UIImageSymbolWeightBold];
    [self.playPauseButton setImage:[UIImage systemImageNamed:symbol withConfiguration:config] forState:UIControlStateNormal];
}

- (void)updateModeIcons {
    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    UIColor *inactiveColor = SonoraPlayerPrimaryColor();

    self.shuffleButton.tintColor = playback.isShuffleEnabled ? SonoraAccentYellowColor() : inactiveColor;

    NSString *repeatSymbol = @"repeat";
    switch (playback.repeatMode) {
        case SonoraRepeatModeNone:
            repeatSymbol = @"repeat";
            self.repeatButton.tintColor = inactiveColor;
            break;
        case SonoraRepeatModeQueue:
            repeatSymbol = @"repeat";
            self.repeatButton.tintColor = SonoraAccentYellowColor();
            break;
        case SonoraRepeatModeTrack:
            repeatSymbol = @"repeat.1";
            self.repeatButton.tintColor = SonoraAccentYellowColor();
            break;
    }

    UIImageSymbolConfiguration *repeatConfig = [UIImageSymbolConfiguration configurationWithPointSize:24.0
                                                                                                 weight:UIImageSymbolWeightSemibold];
    [self.repeatButton setImage:[UIImage systemImageNamed:repeatSymbol withConfiguration:repeatConfig] forState:UIControlStateNormal];
}

@end
