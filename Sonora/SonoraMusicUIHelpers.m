//
//  SonoraMusicUIHelpers.m
//  Sonora
//

#import "SonoraMusicUIHelpers.h"

#import "SonoraSettings.h"
#import "SonoraServices.h"

NSString * const SonoraLovelyPlaylistDefaultsKey = @"sonora_lovely_playlist_id_v1";
NSString * const SonoraSharedPlaylistSyntheticPrefix = @"shared:";
CGFloat const SonoraSearchRevealThreshold = 62.0;

static CGFloat const SonoraSearchDismissThreshold = 40.0;

static UIColor *SonoraBlendColors(UIColor *baseColor, UIColor *overlayColor, CGFloat amount) {
    CGFloat mix = MAX(0.0, MIN(1.0, amount));
    CGFloat baseRed = 0.0;
    CGFloat baseGreen = 0.0;
    CGFloat baseBlue = 0.0;
    CGFloat baseAlpha = 0.0;
    CGFloat overlayRed = 0.0;
    CGFloat overlayGreen = 0.0;
    CGFloat overlayBlue = 0.0;
    CGFloat overlayAlpha = 0.0;

    if (![baseColor getRed:&baseRed green:&baseGreen blue:&baseBlue alpha:&baseAlpha]) {
        CGFloat white = 0.0;
        if ([baseColor getWhite:&white alpha:&baseAlpha]) {
            baseRed = white;
            baseGreen = white;
            baseBlue = white;
        }
    }

    if (![overlayColor getRed:&overlayRed green:&overlayGreen blue:&overlayBlue alpha:&overlayAlpha]) {
        CGFloat white = 0.0;
        if ([overlayColor getWhite:&white alpha:&overlayAlpha]) {
            overlayRed = white;
            overlayGreen = white;
            overlayBlue = white;
        }
    }

    return [UIColor colorWithRed:(baseRed + ((overlayRed - baseRed) * mix))
                           green:(baseGreen + ((overlayGreen - baseGreen) * mix))
                            blue:(baseBlue + ((overlayBlue - baseBlue) * mix))
                           alpha:1.0];
}

void SonoraConfigureNavigationIconBarButtonItem(UIBarButtonItem *item, NSString *title) {
    if (![item isKindOfClass:UIBarButtonItem.class]) {
        return;
    }
    if (title.length == 0) {
        return;
    }
    item.title = title;
    item.accessibilityLabel = title;
}

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

static UIColor * _Nullable SonoraCurrentArtworkAppBackgroundSourceColor(UITraitCollection *trait) {
    SonoraTrack *track = SonoraPlaybackManager.sharedManager.currentTrack;
    UIImage *artwork = track.artwork;
    if (artwork == nil) {
        return nil;
    }

    NSArray<UIColor *> *palette = SonoraResolvedWavePalette(artwork);
    UIColor *candidate = nil;
    if (palette.count >= 4) {
        candidate = SonoraBlendColors(
            SonoraBlendColors(palette[0], palette[1], 0.48),
            SonoraBlendColors(palette[2], palette[3], 0.32),
            0.42
        );
    } else if (palette.count > 0) {
        candidate = palette.firstObject;
    }
    if (candidate == nil) {
        candidate = [SonoraArtworkAccentColorService dominantAccentColorForImage:artwork fallback:UIColor.systemBackgroundColor];
    }
    return [candidate resolvedColorWithTraitCollection:trait];
}

UIColor *SonoraAccentYellowColor(void) {
    UIColor *fromHex = SonoraColorFromHexString(SonoraSettingsAccentHex());
    if (fromHex != nil) {
        return fromHex;
    }
    return SonoraLegacyAccentColorForIndex(SonoraSettingsLegacyAccentColorIndex());
}

UIColor *SonoraLovelyAccentRedColor(void) {
    return [UIColor colorWithRed:0.90 green:0.12 blue:0.15 alpha:1.0];
}

SonoraPlayerFontStyle SonoraPlayerFontStyleFromDefaults(void) {
    NSInteger raw = SonoraSettingsFontStyleIndex();
    if (raw < SonoraPlayerFontStyleSystem || raw > SonoraPlayerFontStyleSerif) {
        return SonoraPlayerFontStyleSystem;
    }
    return (SonoraPlayerFontStyle)raw;
}

UIColor *SonoraPlayerBackgroundColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
        if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return UIColor.blackColor;
        }
        return UIColor.systemBackgroundColor;
    }];
}

UIColor *SonoraAppBackgroundColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
        UIColor *baseColor = [UIColor.systemBackgroundColor resolvedColorWithTraitCollection:trait];
        UIColor *customColor = nil;
        switch (SonoraSettingsAppBackgroundMode()) {
            case SonoraAppBackgroundModeArtwork:
                customColor = SonoraCurrentArtworkAppBackgroundSourceColor(trait);
                break;
            case SonoraAppBackgroundModeCustom:
                customColor = SonoraColorFromHexString(SonoraSettingsAppBackgroundHex());
                if (customColor == nil && SonoraSettingsUseAccentAppBackgroundEnabled()) {
                    customColor = SonoraAccentYellowColor();
                }
                break;
            case SonoraAppBackgroundModeSystem:
            default:
                break;
        }
        if (customColor == nil) {
            return baseColor;
        }
        UIColor *resolvedCustomColor = [customColor resolvedColorWithTraitCollection:trait];
        BOOL artworkMode = (SonoraSettingsAppBackgroundMode() == SonoraAppBackgroundModeArtwork);
        CGFloat amount = (trait.userInterfaceStyle == UIUserInterfaceStyleDark)
            ? (artworkMode ? 0.16 : 0.18)
            : (artworkMode ? 0.11 : 0.12);
        return SonoraBlendColors(baseColor, resolvedCustomColor, amount);
    }];
}

UIColor *SonoraPlayerPrimaryColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
        if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return UIColor.whiteColor;
        }
        return UIColor.labelColor;
    }];
}

UIColor *SonoraPlayerSecondaryColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
        if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return [UIColor colorWithWhite:1.0 alpha:0.66];
        }
        return UIColor.secondaryLabelColor;
    }];
}

UIColor *SonoraPlayerTimelineMaxColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
        if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return [UIColor colorWithWhite:1.0 alpha:0.24];
        }
        return [UIColor colorWithWhite:0.0 alpha:0.22];
    }];
}

UIFont *SonoraHeadlineFont(CGFloat size) {
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

UIFont *SonoraPlayerFontForStyle(SonoraPlayerFontStyle style, CGFloat size, UIFontWeight weight) {
    switch (style) {
        case SonoraPlayerFontStyleSerif:
            return SonoraNewYorkFont(size, weight);
        case SonoraPlayerFontStyleSystem:
        default:
            return [UIFont systemFontOfSize:size weight:weight];
    }
}

SonoraPlayerArtworkStyle SonoraPlayerArtworkStyleFromDefaults(void) {
    NSInteger raw = SonoraSettingsArtworkStyleIndex();
    if (raw < SonoraPlayerArtworkStyleSquare || raw > SonoraPlayerArtworkStyleRounded) {
        return SonoraPlayerArtworkStyleRounded;
    }
    return (SonoraPlayerArtworkStyle)raw;
}

BOOL SonoraArtworkEqualizerEnabledFromDefaults(void) {
    return SonoraSettingsArtworkEqualizerEnabled();
}

CGFloat SonoraArtworkCornerRadiusForStyle(SonoraPlayerArtworkStyle style, CGFloat width) {
    switch (style) {
        case SonoraPlayerArtworkStyleSquare:
            return 0.0;
        case SonoraPlayerArtworkStyleRounded:
        default:
            return MIN(26.0, width * 0.08);
    }
}

UIImage *SonoraLovelySongsCoverImage(CGSize size) {
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

UIView *SonoraWhiteSectionTitleLabel(NSString *text) {
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

    if (@available(iOS 26.0, *)) {
        CGFloat horizontalPadding = 10.0;
        CGFloat width = ceil(CGRectGetWidth(label.bounds)) + (horizontalPadding * 2.0);
        CGFloat height = ceil(CGRectGetHeight(label.bounds));
        UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, width, height)];
        label.frame = CGRectMake(horizontalPadding, 0.0, ceil(CGRectGetWidth(label.bounds)), height);
        [container addSubview:label];
        return container;
    }
    return label;
}

void SonoraPresentAlert(UIViewController *controller, NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [controller presentViewController:alert animated:YES completion:nil];
}

UIAlertController * _Nullable SonoraPresentBlockingProgressAlert(UIViewController * _Nullable controller,
                                                                 NSString *title,
                                                                 NSString *message) {
    if (controller == nil) {
        return nil;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [controller presentViewController:alert animated:YES completion:nil];
    return alert;
}

NSString *SonoraNormalizedSearchText(NSString *text) {
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

NSArray<SonoraTrack *> *SonoraFilterTracksByQuery(NSArray<SonoraTrack *> *tracks, NSString *query) {
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

BOOL SonoraTrackQueuesMatchByIdentifier(NSArray<SonoraTrack *> *first, NSArray<SonoraTrack *> *second) {
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

UISearchController *SonoraBuildSearchController(id<UISearchResultsUpdating> updater, NSString *placeholder) {
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

BOOL SonoraShouldAttachSearchController(BOOL currentlyAttached,
                                        UISearchController * _Nullable searchController,
                                        UIScrollView * _Nullable scrollView,
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

void SonoraApplySearchControllerAttachment(UINavigationItem *navigationItem,
                                           UINavigationBar * _Nullable navigationBar,
                                           UISearchController * _Nullable searchController,
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

void SonoraPresentQuickAddTrackToPlaylist(UIViewController *controller,
                                          NSString *trackID,
                                          dispatch_block_t _Nullable completionHandler) {
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

UIButton *SonoraPlainIconButton(NSString *symbolName, CGFloat symbolSize, CGFloat weightValue) {
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

UIImage *SonoraSliderThumbImage(CGFloat diameter, UIColor *color) {
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
