//
//  SonoraSleepTimerManager.m
//  Sonora
//

#import "SonoraServices.h"

#import <math.h>
#import <objc/message.h>

static void SonoraSyncSleepLiveActivity(NSTimeInterval remainingSeconds) {
    if (!isfinite(remainingSeconds) || remainingSeconds <= 0.0) {
        return;
    }

    Class bridgeClass = NSClassFromString(@"SonoraSleepLiveActivityBridge");
    if (bridgeClass == Nil) {
        return;
    }

    SEL selector = NSSelectorFromString(@"syncSleepTimerWithRemaining:title:subtitle:");
    if (![bridgeClass respondsToSelector:selector]) {
        return;
    }

    SonoraTrack *track = SonoraPlaybackManager.sharedManager.currentTrack;
    NSString *title = track.title.length > 0 ? track.title : @"Sleep Timer";
    NSString *subtitle = track.artist.length > 0 ? track.artist : @"";

    void (*function)(id, SEL, NSTimeInterval, NSString *, NSString *) = (void *)[bridgeClass methodForSelector:selector];
    if (function != NULL) {
        function(bridgeClass, selector, remainingSeconds, title, subtitle);
    }
}

static void SonoraEndSleepLiveActivity(void) {
    Class bridgeClass = NSClassFromString(@"SonoraSleepLiveActivityBridge");
    if (bridgeClass == Nil) {
        return;
    }

    SEL selector = NSSelectorFromString(@"endSleepTimerActivity");
    if (![bridgeClass respondsToSelector:selector]) {
        return;
    }

    void (*function)(id, SEL) = (void *)[bridgeClass methodForSelector:selector];
    if (function != NULL) {
        function(bridgeClass, selector);
    }
}

@interface SonoraSleepTimerManager ()

@property (nonatomic, strong, nullable) NSDate *fireDate;
@property (nonatomic, strong, nullable) dispatch_source_t timer;

@end

@implementation SonoraSleepTimerManager

+ (instancetype)sharedManager {
    static SonoraSleepTimerManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[SonoraSleepTimerManager alloc] init];
    });
    return manager;
}

- (BOOL)isActive {
    return self.remainingTime > 0.0;
}

- (NSTimeInterval)remainingTime {
    if (self.fireDate == nil) {
        return 0.0;
    }

    NSTimeInterval remaining = [self.fireDate timeIntervalSinceNow];
    if (!isfinite(remaining) || remaining <= 0.0) {
        return 0.0;
    }
    return remaining;
}

- (void)startWithDuration:(NSTimeInterval)duration {
    NSTimeInterval normalizedDuration = MAX(duration, 0.0);
    if (normalizedDuration <= 0.0) {
        [self cancel];
        return;
    }

    [self invalidateTimer];
    self.fireDate = [NSDate dateWithTimeIntervalSinceNow:normalizedDuration];

    __weak typeof(self) weakSelf = self;
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_event_handler(timer, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        [strongSelf handleTimerFired];
    });
    dispatch_source_set_timer(timer,
                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)(normalizedDuration * (NSTimeInterval)NSEC_PER_SEC)),
                              DISPATCH_TIME_FOREVER,
                              (uint64_t)(0.1 * (NSTimeInterval)NSEC_PER_SEC));
    self.timer = timer;
    dispatch_resume(timer);

    SonoraSyncSleepLiveActivity(normalizedDuration);
    [self postDidChange];
}

- (void)cancel {
    if (self.fireDate == nil && self.timer == nil) {
        return;
    }

    [self invalidateTimer];
    self.fireDate = nil;
    SonoraEndSleepLiveActivity();
    [self postDidChange];
}

- (void)handleTimerFired {
    [self invalidateTimer];
    self.fireDate = nil;

    SonoraPlaybackManager *playback = SonoraPlaybackManager.sharedManager;
    if (playback.isPlaying) {
        [playback togglePlayPause];
    }

    SonoraEndSleepLiveActivity();
    [self postDidChange];
}

- (void)invalidateTimer {
    if (self.timer == nil) {
        return;
    }

    dispatch_source_cancel(self.timer);
    self.timer = nil;
}

- (void)postDidChange {
    [NSNotificationCenter.defaultCenter postNotificationName:SonoraSleepTimerDidChangeNotification object:self];
}

@end
