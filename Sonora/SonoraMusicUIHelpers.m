//
//  SonoraMusicUIHelpers.m
//  Sonora
//

#import "SonoraMusicUIHelpers.h"

#import "SonoraSettings.h"

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

UIColor *SonoraAccentYellowColor(void) {
    UIColor *fromHex = SonoraColorFromHexString(SonoraSettingsAccentHex());
    if (fromHex != nil) {
        return fromHex;
    }
    return SonoraLegacyAccentColorForIndex(SonoraSettingsLegacyAccentColorIndex());
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

NSString *SonoraNormalizedSearchText(NSString *text) {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return trimmed.lowercaseString ?: @"";
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
