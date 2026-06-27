#import <UIKit/UIKit.h>
#import <dlfcn.h>

#pragma mark - GSEvent via dlsym

typedef struct __GSEvent *GSEventRef;
static GSEventRef (*$GSEventCreateWithType)(int) = NULL;
static void (*$GSEventSetLocationInWindow)(GSEventRef, CGPoint) = NULL;
static void (*$GSEventPostEvent)(GSEventRef) = NULL;

static void initGSEvent(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *h = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_NOLOAD);
        if (!h) h = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_LAZY);
        if (h) {
            $GSEventCreateWithType      = dlsym(h, "GSEventCreateWithType");
            $GSEventSetLocationInWindow = dlsym(h, "GSEventSetLocationInWindow");
            $GSEventPostEvent           = dlsym(h, "GSEventPostEvent");
        }
    });
}

#pragma mark - Auto-scrolling Marquee

@interface HBMarqueeView : UIView
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, copy) NSString *text;
- (void)startAnimating;
- (void)stopAnimating;
@end

@implementation HBMarqueeView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.clipsToBounds = YES;
        self.label = [[UILabel alloc] init];
        self.label.font = [UIFont boldSystemFontOfSize:13];
        self.label.textColor = [UIColor colorWithRed:1 green:0.8 blue:0.2 alpha:1];
        [self addSubview:self.label];
    }
    return self;
}

- (void)setText:(NSString *)text {
    _text = [text copy];
    self.label.text = text;
    [self stopAnimating];
    [self startAnimating];
}

- (void)startAnimating {
    [self.label sizeToFit];
    CGFloat labelW = self.label.frame.size.width;
    CGFloat selfW = self.frame.size.width;
    if (labelW <= selfW) {
        self.label.frame = CGRectMake(0, 0, selfW, self.frame.size.height);
        self.label.textAlignment = NSTextAlignmentCenter;
        return;
    }
    self.label.textAlignment = NSTextAlignmentLeft;
    [self animateMarqueeWithWidth:labelW containerWidth:selfW];
}

- (void)animateMarqueeWithWidth:(CGFloat)labelW containerWidth:(CGFloat)selfW {
    __weak typeof(self) ws = self;
    [self.label.layer removeAllAnimations];
    self.label.frame = CGRectMake(selfW + 10, 0, labelW, self.frame.size.height);
    CGFloat duration = labelW / 25.0;
    [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionCurveLinear animations:^{
        ws.label.frame = CGRectMake(-labelW - 10, 0, labelW, ws.frame.size.height);
    } completion:^(BOOL finished) {
        if (finished) {
            [ws animateMarqueeWithWidth:labelW containerWidth:selfW];
        }
    }];
}

- (void)stopAnimating {
    [self.label.layer removeAllAnimations];
}

@end

#pragma mark - HBAutoTapEngine (interval-based)

@interface HBAutoTapEngine : NSObject
@property (nonatomic, assign) CGPoint  tapPoint;
@property (nonatomic, assign, readonly) BOOL    isRunning;
@property (nonatomic, assign) CGFloat   delay; 
@property (nonatomic, strong) NSTimer  *timer;
- (void)start;
- (void)stop;
- (void)setDelay:(CGFloat)delay;
@end

@implementation HBAutoTapEngine

- (instancetype)init {
    self = [super init];
    if (self) {
        _delay     = 0.02;
        _isRunning = NO;
        initGSEvent();
    }
    return self;
}

- (void)start {
    if (self.isRunning) return;
    _isRunning = YES;
    [self scheduleTimer];
}

- (void)stop {
    _isRunning = NO;
    [self.timer invalidate];
    self.timer = nil;
}

- (void)setDelay:(CGFloat)delay {
    if (delay < 0.001) delay = 0.001;
    if (delay > 0.05) delay = 0.05;
    _delay = delay;
    if (self.isRunning) {
        [self.timer invalidate];
        [self scheduleTimer];
    }
}

- (void)scheduleTimer {
    NSTimeInterval interval = self.delay;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:interval
                                                  target:self
                                                selector:@selector(timerFired:)
                                                userInfo:nil
                                                 repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)timerFired:(NSTimer *)timer {
    [self simulateTapAtPoint:self.tapPoint];
}

- (void)simulateTapAtPoint:(CGPoint)point {
    if (!$GSEventCreateWithType || !$GSEventSetLocationInWindow || !$GSEventPostEvent) return;

    GSEventRef down = $GSEventCreateWithType(1007);
    if (down) {
        $GSEventSetLocationInWindow(down, point);
        $GSEventPostEvent(down);
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.03 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        GSEventRef up = $GSEventCreateWithType(1009);
        if (up) {
            $GSEventSetLocationInWindow(up, point);
            $GSEventPostEvent(up);
        }
    });
}

- (void)dealloc {
    [self stop];
}

@end

#pragma mark - HBPassthroughWindow

@interface HBPassthroughWindow : UIWindow
@end

@implementation HBPassthroughWindow
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    for (UIView *v in self.subviews) {
        if (!v.hidden && v.alpha > 0 &&
            CGRectContainsPoint(v.frame, [self convertPoint:point toView:v])) {
            return YES;
        }
    }
    return NO;
}
@end

#pragma mark - Draggable Circle (tap position indicator)

@interface HBTapCircle : UIView
@property (nonatomic, copy) void (^onPositionChanged)(CGPoint point);
@property (nonatomic, assign) CGPoint dragOffset;
@end

@implementation HBTapCircle

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        CGFloat r = frame.size.width / 2;
        self.layer.cornerRadius  = r;
        self.layer.masksToBounds = NO;
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;

        UIView *inner = [[UIView alloc] initWithFrame:self.bounds];
        inner.backgroundColor = [UIColor colorWithRed:1 green:0.2 blue:0.2 alpha:0.55];
        inner.layer.cornerRadius = r;
        inner.layer.borderColor = [UIColor whiteColor].CGColor;
        inner.layer.borderWidth = 2.5;
        inner.userInteractionEnabled = NO;
        [self addSubview:inner];

        UILabel *cross = [[UILabel alloc] initWithFrame:CGRectInset(self.bounds, 4, 4)];
        cross.text = @"✚";
        cross.font = [UIFont boldSystemFontOfSize:22];
        cross.textColor = [UIColor whiteColor];
        cross.textAlignment = NSTextAlignmentCenter;
        cross.userInteractionEnabled = NO;
        [self addSubview:cross];

        UIBezierPath *sp = [UIBezierPath bezierPathWithOvalInRect:self.bounds];
        self.layer.shadowColor   = [UIColor blackColor].CGColor;
        self.layer.shadowOffset  = CGSizeMake(0, 3);
        self.layer.shadowOpacity = 0.4;
        self.layer.shadowRadius  = 5;
        self.layer.shadowPath    = sp.CGPath;
    }
    return self;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *t = [touches anyObject];
    CGPoint loc = [t locationInView:self.superview];
    self.dragOffset = CGPointMake(loc.x - self.center.x, loc.y - self.center.y);
    self.transform = CGAffineTransformMakeScale(1.2, 1.2);
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *t = [touches anyObject];
    CGPoint loc = [t locationInView:self.superview];
    CGPoint c = CGPointMake(loc.x - self.dragOffset.x, loc.y - self.dragOffset.y);
    CGFloat h = self.frame.size.width / 2;
    CGRect sb = [UIScreen mainScreen].bounds;
    c.x = MAX(h, MIN(sb.size.width  - h, c.x));
    c.y = MAX(h, MIN(sb.size.height - h, c.y));
    self.center = c;
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    self.transform = CGAffineTransformIdentity;
    if (self.onPositionChanged) {
        self.onPositionChanged(self.center);
    }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    self.transform = CGAffineTransformIdentity;
}

@end

#pragma mark - HBCollapsiblePanel

@interface HBCollapsiblePanel : UIView
@property (nonatomic, assign) BOOL  isCollapsed;
@property (nonatomic, assign) BOOL  isRunning;
@property (nonatomic, strong) UIButton *toggleBtn;
@property (nonatomic, strong) UISlider *speedSlider;
@property (nonatomic, strong) UILabel  *speedLabel;
@property (nonatomic, strong) UIButton *mergeBtn;
@property (nonatomic, strong) UIButton *hideBtn;
@property (nonatomic, strong) UILabel  *arrowLabel;
@property (nonatomic, strong) HBMarqueeView *topMarquee;
@property (nonatomic, strong) HBMarqueeView *bottomMarquee;
@property (nonatomic, assign) CGRect fullFrame;
@property (nonatomic, assign) CGRect collapsedFrame;

@property (nonatomic, copy) void (^onToggle)(BOOL running);
@property (nonatomic, copy) void (^onSpeedChange)(CGFloat delay);
@property (nonatomic, copy) void (^onMerge)(void);
@end

@implementation HBCollapsiblePanel

- (instancetype)initWithFullFrame:(CGRect)fullFrame {
    CGFloat collW = 56;
    CGFloat collH = 48;
    CGFloat collX = fullFrame.origin.x + (fullFrame.size.width - collW) / 2;
    CGFloat collY = fullFrame.origin.y + fullFrame.size.height + 10;
    CGRect cf = CGRectMake(collX, collY, collW, collH);

    self = [super initWithFrame:fullFrame];
    if (self) {
        _fullFrame = fullFrame;
        _collapsedFrame = cf;
        _isCollapsed = NO;
        _isRunning = NO;
        [self setupPanel];
    }
    return self;
}

- (void)setupPanel {
    self.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.94];
    self.layer.cornerRadius = 14;
    self.clipsToBounds = YES;
    self.layer.borderColor = [UIColor colorWithWhite:0.4 alpha:0.3].CGColor;
    self.layer.borderWidth = 1;

    CGFloat W = self.frame.size.width;
    CGFloat padX = 12;
    CGFloat cW = W - padX * 2;

    self.topMarquee = [[HBMarqueeView alloc] initWithFrame:CGRectMake(0, 0, W, 22)];
    self.topMarquee.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.5];
    [self addSubview:self.topMarquee];

    CGFloat y = 30;

    self.toggleBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.toggleBtn.frame = CGRectMake(padX, y, cW, 46);
    self.toggleBtn.backgroundColor = [UIColor colorWithRed:0.15 green:0.55 blue:0.2 alpha:0.8];
    self.toggleBtn.layer.cornerRadius = 10;
    [self.toggleBtn setTitle:@"تشغيل" forState:UIControlStateNormal];
    [self.toggleBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.toggleBtn.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [self.toggleBtn addTarget:self action:@selector(toggleTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.toggleBtn];
    y += 54;

    UIView *spdRow = [[UIView alloc] initWithFrame:CGRectMake(padX, y, cW, 36)];
    [self addSubview:spdRow];

    self.speedLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 55, 36)];
    self.speedLabel.text = @"0.020s";
    self.speedLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightMedium];
    self.speedLabel.textColor = [UIColor whiteColor];
    self.speedLabel.textAlignment = NSTextAlignmentCenter;
    [spdRow addSubview:self.speedLabel];

    self.speedSlider = [[UISlider alloc] initWithFrame:CGRectMake(60, 3, cW - 60, 30)];
    self.speedSlider.minimumValue = 0.0;
    self.speedSlider.maximumValue = 0.05;
    self.speedSlider.value = 0.02;
    self.speedSlider.continuous = YES;
    self.speedSlider.tintColor = [UIColor colorWithRed:0.2 green:0.5 blue:1.0 alpha:1];
    [self.speedSlider addTarget:self action:@selector(speedChanged:) forControlEvents:UIControlEventValueChanged];
    [spdRow addSubview:self.speedSlider];

    y += 44;

    self.mergeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.mergeBtn.frame = CGRectMake(padX, y, cW, 38);
    self.mergeBtn.backgroundColor = [UIColor colorWithRed:0.55 green:0.2 blue:0.75 alpha:0.6];
    self.mergeBtn.layer.cornerRadius = 10;
    [self.mergeBtn setTitle:@"🔗 دمج الحسابات" forState:UIControlStateNormal];
    [self.mergeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.mergeBtn.titleLabel.font = [UIFont systemFontOfSize:14];
    [self.mergeBtn addTarget:self action:@selector(mergeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.mergeBtn];
    y += 44;

    self.hideBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.hideBtn.frame = CGRectMake(padX, y, cW, 36);
    self.hideBtn.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.5];
    self.hideBtn.layer.cornerRadius = 10;
    [self.hideBtn setTitle:@"◀ اخفاء" forState:UIControlStateNormal];
    [self.hideBtn setTitleColor:[UIColor lightGrayColor] forState:UIControlStateNormal];
    self.hideBtn.titleLabel.font = [UIFont systemFontOfSize:13];
    [self.hideBtn addTarget:self action:@selector(hideTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.hideBtn];

    CGFloat bmY = self.frame.size.height - 22;
    self.bottomMarquee = [[HBMarqueeView alloc] initWithFrame:CGRectMake(0, bmY, W, 22)];
    self.bottomMarquee.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.5];
    [self addSubview:self.bottomMarquee];

    NSString *names = @"عبدالإله لحلوح شارو ابومتعب سعيد حاتم الكايد الهباس الشمامره";
    self.topMarquee.text = names;
    self.bottomMarquee.text = names;

    self.arrowLabel = [[UILabel alloc] initWithFrame:self.bounds];
    self.arrowLabel.text = @"▶";
    self.arrowLabel.font = [UIFont boldSystemFontOfSize:22];
    self.arrowLabel.textColor = [UIColor whiteColor];
    self.arrowLabel.textAlignment = NSTextAlignmentCenter;
    self.arrowLabel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.94];
    self.arrowLabel.hidden = YES;
    self.arrowLabel.userInteractionEnabled = YES;
    self.arrowLabel.layer.cornerRadius = 12;
    self.arrowLabel.clipsToBounds = YES;
    [self addSubview:self.arrowLabel];

    UITapGestureRecognizer *arrowTap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                               action:@selector(expandTapped)];
    [self.arrowLabel addGestureRecognizer:arrowTap];
}

- (void)toggleTapped {
    self.isRunning = !self.isRunning;
    if (self.isRunning) {
        [self.toggleBtn setTitle:@"إيقاف" forState:UIControlStateNormal];
        self.toggleBtn.backgroundColor = [UIColor colorWithRed:0.7 green:0.15 blue:0.15 alpha:0.8];
    } else {
        [self.toggleBtn setTitle:@"تشغيل" forState:UIControlStateNormal];
        self.toggleBtn.backgroundColor = [UIColor colorWithRed:0.15 green:0.55 blue:0.2 alpha:0.8];
    }
    if (self.onToggle) self.onToggle(self.isRunning);
}

- (void)speedChanged:(UISlider *)slider {
    CGFloat val = roundf(slider.value * 1000.0) / 1000.0;
    if (val < 0.001) val = 0.001;
    self.speedLabel.text = [NSString stringWithFormat:@"%.3fs", val];
    if (self.onSpeedChange) self.onSpeedChange(val);
}

- (void)mergeTapped {
    self.mergeBtn.enabled = NO;
    [self.mergeBtn setTitle:@"⏳ جاري..." forState:UIControlStateNormal];
    if (self.onMerge) self.onMerge();
}

- (void)hideTapped {
    [self collapsePanel];
}

- (void)expandTapped {
    [self expandPanel];
}

- (void)collapsePanel {
    self.isCollapsed = YES;
    self.arrowLabel.hidden = NO;
    self.arrowLabel.alpha = 0;
    self.arrowLabel.frame = self.bounds;
    self.arrowLabel.layer.cornerRadius = self.layer.cornerRadius;
    self.arrowLabel.clipsToBounds = YES;

    [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.frame = self.collapsedFrame;
        self.arrowLabel.frame = self.bounds;
        self.arrowLabel.alpha = 1;
        self.topMarquee.alpha = 0;
        self.toggleBtn.alpha = 0;
        self.speedLabel.alpha = 0;
        self.speedSlider.alpha = 0;
        self.mergeBtn.alpha = 0;
        self.hideBtn.alpha = 0;
        self.bottomMarquee.alpha = 0;
    } completion:^(BOOL fin) {
        self.topMarquee.hidden = YES;
        self.toggleBtn.hidden = YES;
        self.speedLabel.hidden = YES;
        self.speedSlider.hidden = YES;
        self.mergeBtn.hidden = YES;
        self.hideBtn.hidden = YES;
        self.bottomMarquee.hidden = YES;
    }];
}

- (void)expandPanel {
    self.isCollapsed = NO;
    self.topMarquee.hidden = NO;
    self.toggleBtn.hidden = NO;
    self.speedLabel.hidden = NO;
    self.speedSlider.hidden = NO;
    self.mergeBtn.hidden = NO;
    self.hideBtn.hidden = NO;
    self.bottomMarquee.hidden = NO;
    self.topMarquee.alpha = 0;
    self.toggleBtn.alpha = 0;
    self.speedLabel.alpha = 0;
    self.speedSlider.alpha = 0;
    self.mergeBtn.alpha = 0;
    self.hideBtn.alpha = 0;
    self.bottomMarquee.alpha = 0;

    [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.frame = self.fullFrame;
        self.arrowLabel.alpha = 0;
        self.topMarquee.alpha = 1;
        self.toggleBtn.alpha = 1;
        self.speedLabel.alpha = 1;
        self.speedSlider.alpha = 1;
        self.mergeBtn.alpha = 1;
        self.hideBtn.alpha = 1;
        self.bottomMarquee.alpha = 1;
    } completion:^(BOOL fin) {
        self.arrowLabel.hidden = YES;
    }];
}

- (void)enableMergeButton {
    self.mergeBtn.enabled = YES;
    [self.mergeBtn setTitle:@"🔗 دمج الحسابات" forState:UIControlStateNormal];
}

- (void)setRunning:(BOOL)running {
    _isRunning = running;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (running) {
            [self.toggleBtn setTitle:@"إيقاف" forState:UIControlStateNormal];
            self.toggleBtn.backgroundColor = [UIColor colorWithRed:0.7 green:0.15 blue:0.15 alpha:0.8];
        } else {
            [self.toggleBtn setTitle:@"تشغيل" forState:UIControlStateNormal];
            self.toggleBtn.backgroundColor = [UIColor colorWithRed:0.15 green:0.55 blue:0.2 alpha:0.8];
        }
    });
}

@end

#pragma mark - HBOverlayManager

@interface HBOverlayManager : NSObject
@property (nonatomic, strong) HBPassthroughWindow *overlayWindow;
@property (nonatomic, strong) HBTapCircle        *tapCircle;
@property (nonatomic, strong) HBCollapsiblePanel *panel;
@property (nonatomic, strong) HBAutoTapEngine    *tapEngine;
@property (nonatomic, assign) CGPoint tapPosition;
- (void)show;
@end

@implementation HBOverlayManager

+ (instancetype)shared {
    static HBOverlayManager *instance = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        CGSize sz = [UIScreen mainScreen].bounds.size;
        _tapPosition = CGPointMake(sz.width / 2, sz.height / 2);
    }
    return self;
}

- (void)show {
    if (self.overlayWindow) return;
    CGRect sb = [UIScreen mainScreen].bounds;

    self.overlayWindow = [[HBPassthroughWindow alloc] initWithFrame:sb];
    self.overlayWindow.windowLevel = 2000;
    self.overlayWindow.backgroundColor = [UIColor clearColor];
    self.overlayWindow.userInteractionEnabled = YES;
    self.overlayWindow.hidden = NO;

    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = [UIColor clearColor];
    vc.view.userInteractionEnabled = YES;
    self.overlayWindow.rootViewController = vc;

    CGFloat pw = 210;
    CGFloat ph = 270;
    CGFloat px = (sb.size.width - pw) / 2;
    CGFloat py = (sb.size.height - ph) / 2;
    self.panel = [[HBCollapsiblePanel alloc] initWithFullFrame:CGRectMake(px, py, pw, ph)];
    [vc.view addSubview:self.panel];

    CGFloat circleSize = 42;
    CGFloat cx = sb.size.width - circleSize - 16;
    CGFloat cy = sb.size.height / 2 - circleSize / 2;
    self.tapCircle = [[HBTapCircle alloc] initWithFrame:CGRectMake(cx, cy, circleSize, circleSize)];
    [vc.view addSubview:self.tapCircle];
    [vc.view bringSubviewToFront:self.tapCircle];

    self.tapEngine = [[HBAutoTapEngine alloc] init];
    self.tapEngine.tapPoint = self.tapCircle.center;

    __weak typeof(self) ws = self;

    self.tapCircle.onPositionChanged = ^(CGPoint pt) {
        ws.tapPosition = pt;
        ws.tapEngine.tapPoint = pt;
    };

    self.panel.onToggle = ^(BOOL running) {
        if (running) {
            ws.tapEngine.tapPoint = ws.tapCircle.center;
            [ws.tapEngine setDelay:ws.panel.speedSlider.value > 0.001 ? ws.panel.speedSlider.value : 0.001];
            [ws.tapEngine start];
        } else {
            [ws.tapEngine stop];
        }
    };

    self.panel.onSpeedChange = ^(CGFloat delay) {
        [ws.tapEngine setDelay:delay];
    };

    self.panel.onMerge = ^{
        [ws performMerge];
    };
}

- (void)performMerge {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"دمج الحسابات"
                             message:@"✅ تم دمج جميع الحسابات بنجاح"
                      preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"تم" style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *a) {
            [self.panel enableMergeButton];
        }]];
        [self.overlayWindow.rootViewController presentViewController:alert animated:YES completion:nil];
    });
}

@end

#pragma mark - Entry Point (%ctor + dispatch_async)

%ctor {
    @autoreleasepool {
        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                [[HBOverlayManager shared] show];
            } @catch (NSException *e) {
                NSLog(@"YallaPro: init error - %@", e);
            }
        });
    }
}
