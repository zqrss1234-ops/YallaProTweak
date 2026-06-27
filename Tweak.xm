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

#pragma mark - Marquee

@interface HBMarqueeView : UIView
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, copy) NSString *text;
- (void)start;
- (void)stop;
@end

@implementation HBMarqueeView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.clipsToBounds = YES;
        self.label = [[UILabel alloc] init];
        self.label.font = [UIFont boldSystemFontOfSize:12];
        self.label.textColor = [UIColor whiteColor];
        [self addSubview:self.label];
    }
    return self;
}

- (void)setText:(NSString *)text {
    _text = [text copy];
    self.label.text = text;
    [self stop];
    [self start];
}

- (void)start {
    [self.label sizeToFit];
    CGFloat lw = self.label.frame.size.width;
    CGFloat sw = self.frame.size.width;
    if (lw <= sw) {
        self.label.frame = CGRectMake(0, 0, sw, self.frame.size.height);
        self.label.textAlignment = NSTextAlignmentCenter;
        return;
    }
    self.label.textAlignment = NSTextAlignmentLeft;
    [self animateWithWidth:lw container:sw];
}

- (void)animateWithWidth:(CGFloat)lw container:(CGFloat)sw {
    __weak typeof(self) ws = self;
    [self.label.layer removeAllAnimations];
    self.label.frame = CGRectMake(sw + 8, 0, lw, self.frame.size.height);
    CGFloat dur = lw / 28.0;
    [UIView animateWithDuration:dur delay:0 options:UIViewAnimationOptionCurveLinear animations:^{
        ws.label.frame = CGRectMake(-lw - 8, 0, lw, ws.frame.size.height);
    } completion:^(BOOL fin) {
        if (fin) [ws animateWithWidth:lw container:sw];
    }];
}

- (void)stop {
    [self.label.layer removeAllAnimations];
}

@end

#pragma mark - AutoTapEngine

@interface HBAutoTapEngine : NSObject
@property (nonatomic, assign) CGPoint tapPoint;
@property (nonatomic, assign, readonly) BOOL isRunning;
@property (nonatomic, assign) CGFloat delay;
@property (nonatomic, strong) NSTimer *timer;
- (void)start;
- (void)stop;
- (void)setDelayMs:(CGFloat)ms;
@end

@implementation HBAutoTapEngine

- (instancetype)init {
    self = [super init];
    if (self) {
        _delay = 0.05;
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

- (void)setDelayMs:(CGFloat)ms {
    CGFloat sec = ms / 1000.0;
    if (sec < 0.001) sec = 0.001;
    if (sec > 0.5) sec = 0.5;
    _delay = sec;
    if (self.isRunning) {
        [self.timer invalidate];
        [self scheduleTimer];
    }
}

- (void)scheduleTimer {
    self.timer = [NSTimer scheduledTimerWithTimeInterval:self.delay
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

#pragma mark - PassthroughWindow

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

#pragma mark - Draggable Circle ("imps")

@interface HBTapCircle : UIView
@property (nonatomic, copy) void (^onPositionChanged)(CGPoint);
@property (nonatomic, assign) CGPoint dragOffset;
@end

@implementation HBTapCircle

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        CGFloat r = frame.size.width / 2;
        self.userInteractionEnabled = YES;
        self.backgroundColor = [UIColor clearColor];

        UIView *inner = [[UIView alloc] initWithFrame:self.bounds];
        inner.backgroundColor = [UIColor colorWithWhite:1 alpha:0.25];
        inner.layer.cornerRadius = r;
        inner.layer.borderColor = [UIColor whiteColor].CGColor;
        inner.layer.borderWidth = 2;
        inner.userInteractionEnabled = NO;
        [self addSubview:inner];

        UILabel *lbl = [[UILabel alloc] initWithFrame:self.bounds];
        lbl.text = @"imps";
        lbl.font = [UIFont boldSystemFontOfSize:11];
        lbl.textColor = [UIColor whiteColor];
        lbl.textAlignment = NSTextAlignmentCenter;
        lbl.userInteractionEnabled = NO;
        [self addSubview:lbl];

        UIBezierPath *sp = [UIBezierPath bezierPathWithOvalInRect:self.bounds];
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOffset = CGSizeMake(0, 3);
        self.layer.shadowOpacity = 0.35;
        self.layer.shadowRadius = 5;
        self.layer.shadowPath = sp.CGPath;
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
    c.x = MAX(h, MIN(sb.size.width - h, c.x));
    c.y = MAX(h, MIN(sb.size.height - h, c.y));
    self.center = c;
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    self.transform = CGAffineTransformIdentity;
    if (self.onPositionChanged) self.onPositionChanged(self.center);
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    self.transform = CGAffineTransformIdentity;
}

@end

#pragma mark - Panel (dark purple, new layout)

@interface HBPanel : UIView
@property (nonatomic, assign) BOOL isCollapsed;
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, strong) UIView   *arrowBar;
@property (nonatomic, strong) UILabel  *arrowLabel;
@property (nonatomic, strong) HBMarqueeView *marquee;
@property (nonatomic, strong) UIButton *toggleBtn;
@property (nonatomic, strong) UISlider *speedSlider;
@property (nonatomic, strong) UILabel  *speedLabel;
@property (nonatomic, strong) UIButton *mergeBtn;
@property (nonatomic, strong) UIButton *hideBtn;
@property (nonatomic, assign) CGRect fullFrame;
@property (nonatomic, assign) CGRect collFrame;
@property (nonatomic, copy) void (^onToggle)(BOOL);
@property (nonatomic, copy) void (^onSpeedChange)(CGFloat);
@property (nonatomic, copy) void (^onMerge)(void);
@end

@implementation HBPanel

- (instancetype)initWithFullFrame:(CGRect)ff {
    CGFloat barH = 30;
    CGFloat x = ff.origin.x;
    CGFloat y = ff.origin.y;
    CGFloat w = ff.size.width;
    CGRect cf = CGRectMake(x, y, w, barH);
    self = [super initWithFrame:ff];
    if (self) {
        _fullFrame = ff;
        _collFrame = cf;
        _isCollapsed = NO;
        _isRunning = NO;
        [self setup];
    }
    return self;
}

- (void)setup {
    self.backgroundColor = [UIColor colorWithRed:0.06 green:0.025 blue:0.10 alpha:0.95];
    self.layer.cornerRadius = 12;
    self.clipsToBounds = YES;
    self.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:0.25].CGColor;
    self.layer.borderWidth = 1;

    CGFloat W = self.frame.size.width;
    CGFloat pad = 10;
    CGFloat cw = W - pad * 2;

    self.arrowBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, 30)];
    self.arrowBar.backgroundColor = [UIColor colorWithRed:0.09 green:0.04 blue:0.15 alpha:0.5];
    self.arrowBar.userInteractionEnabled = YES;
    [self addSubview:self.arrowBar];

    self.arrowLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 40, 30)];
    self.arrowLabel.text = @"▼";
    self.arrowLabel.font = [UIFont systemFontOfSize:14];
    self.arrowLabel.textColor = [UIColor whiteColor];
    self.arrowLabel.textAlignment = NSTextAlignmentCenter;
    self.arrowLabel.center = CGPointMake(W/2, 15);
    [self.arrowBar addSubview:self.arrowLabel];

    UITapGestureRecognizer *at = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                        action:@selector(arrowTapped)];
    [self.arrowBar addGestureRecognizer:at];

    CGFloat y = 32;

    self.marquee = [[HBMarqueeView alloc] initWithFrame:CGRectMake(0, y, W, 20)];
    self.marquee.backgroundColor = [UIColor colorWithRed:0.09 green:0.04 blue:0.15 alpha:0.4];
    [self addSubview:self.marquee];
    NSString *names = @"عبدالإله لحلوح شارو ابومتعب سعيد حاتم الكايد الهباس الشمامره";
    self.marquee.text = names;
    y += 24;

    self.toggleBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.toggleBtn.frame = CGRectMake(pad, y, cw, 40);
    self.toggleBtn.backgroundColor = [UIColor colorWithRed:0.15 green:0.5 blue:0.25 alpha:0.8];
    self.toggleBtn.layer.cornerRadius = 8;
    [self.toggleBtn setTitle:@"تفعيل" forState:UIControlStateNormal];
    [self.toggleBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.toggleBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [self.toggleBtn addTarget:self action:@selector(toggleTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.toggleBtn];
    y += 46;

    UIView *sRow = [[UIView alloc] initWithFrame:CGRectMake(pad, y, cw, 32)];
    [self addSubview:sRow];

    self.speedLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 50, 32)];
    self.speedLabel.text = @"50ms";
    self.speedLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
    self.speedLabel.textColor = [UIColor whiteColor];
    self.speedLabel.textAlignment = NSTextAlignmentCenter;
    [sRow addSubview:self.speedLabel];

    self.speedSlider = [[UISlider alloc] initWithFrame:CGRectMake(54, 1, cw - 54, 30)];
    self.speedSlider.minimumValue = 1;
    self.speedSlider.maximumValue = 100;
    self.speedSlider.value = 50;
    self.speedSlider.continuous = YES;
    self.speedSlider.tintColor = [UIColor colorWithRed:0.5 green:0.3 blue:0.8 alpha:1];
    [self.speedSlider addTarget:self action:@selector(speedChanged:) forControlEvents:UIControlEventValueChanged];
    [sRow addSubview:self.speedSlider];

    y += 38;

    self.mergeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.mergeBtn.frame = CGRectMake(pad, y, cw, 34);
    self.mergeBtn.backgroundColor = [UIColor colorWithRed:0.5 green:0.2 blue:0.7 alpha:0.55];
    self.mergeBtn.layer.cornerRadius = 8;
    [self.mergeBtn setTitle:@"ربط جميع yallalite" forState:UIControlStateNormal];
    [self.mergeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.mergeBtn.titleLabel.font = [UIFont systemFontOfSize:13];
    [self.mergeBtn addTarget:self action:@selector(mergeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.mergeBtn];
    y += 40;

    self.hideBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.hideBtn.frame = CGRectMake(pad, y, cw, 30);
    self.hideBtn.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.4];
    self.hideBtn.layer.cornerRadius = 8;
    [self.hideBtn setTitle:@"اخفاء القائمة" forState:UIControlStateNormal];
    [self.hideBtn setTitleColor:[UIColor colorWithWhite:0.7 alpha:1] forState:UIControlStateNormal];
    self.hideBtn.titleLabel.font = [UIFont systemFontOfSize:12];
    [self.hideBtn addTarget:self action:@selector(hideTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.hideBtn];
}

- (void)toggleTapped {
    self.isRunning = !self.isRunning;
    if (self.isRunning) {
        [self.toggleBtn setTitle:@"إيقاف" forState:UIControlStateNormal];
        self.toggleBtn.backgroundColor = [UIColor colorWithRed:0.65 green:0.15 blue:0.15 alpha:0.8];
    } else {
        [self.toggleBtn setTitle:@"تفعيل" forState:UIControlStateNormal];
        self.toggleBtn.backgroundColor = [UIColor colorWithRed:0.15 green:0.5 blue:0.25 alpha:0.8];
    }
    if (self.onToggle) self.onToggle(self.isRunning);
}

- (void)speedChanged:(UISlider *)sl {
    NSInteger val = (NSInteger)roundf(sl.value);
    if (val < 1) val = 1;
    self.speedLabel.text = [NSString stringWithFormat:@"%ldms", (long)val];
    if (self.onSpeedChange) self.onSpeedChange((CGFloat)val);
}

- (void)mergeTapped {
    self.mergeBtn.enabled = NO;
    [self.mergeBtn setTitle:@"⏳ جاري..." forState:UIControlStateNormal];
    if (self.onMerge) self.onMerge();
}

- (void)hideTapped {
    [self collapse];
}

- (void)arrowTapped {
    if (self.isCollapsed) {
        [self expand];
    } else {
        [self collapse];
    }
}

- (void)collapse {
    self.isCollapsed = YES;
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.frame = self.collFrame;
        self.marquee.alpha = 0;
        self.toggleBtn.alpha = 0;
        self.speedLabel.alpha = 0;
        self.speedSlider.alpha = 0;
        self.mergeBtn.alpha = 0;
        self.hideBtn.alpha = 0;
    } completion:^(BOOL fin) {
        self.marquee.hidden = YES;
        self.toggleBtn.hidden = YES;
        self.speedLabel.hidden = YES;
        self.speedSlider.hidden = YES;
        self.mergeBtn.hidden = YES;
        self.hideBtn.hidden = YES;
    }];
}

- (void)expand {
    self.isCollapsed = NO;
    self.marquee.hidden = NO;
    self.toggleBtn.hidden = NO;
    self.speedLabel.hidden = NO;
    self.speedSlider.hidden = NO;
    self.mergeBtn.hidden = NO;
    self.hideBtn.hidden = NO;
    self.marquee.alpha = 0;
    self.toggleBtn.alpha = 0;
    self.speedLabel.alpha = 0;
    self.speedSlider.alpha = 0;
    self.mergeBtn.alpha = 0;
    self.hideBtn.alpha = 0;

    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.frame = self.fullFrame;
        self.marquee.alpha = 1;
        self.toggleBtn.alpha = 1;
        self.speedLabel.alpha = 1;
        self.speedSlider.alpha = 1;
        self.mergeBtn.alpha = 1;
        self.hideBtn.alpha = 1;
    } completion:nil];
}

- (void)enableMerge {
    self.mergeBtn.enabled = YES;
    [self.mergeBtn setTitle:@"ربط جميع yallalite" forState:UIControlStateNormal];
}

@end

#pragma mark - OverlayManager

@interface HBOverlayManager : NSObject
@property (nonatomic, strong) HBPassthroughWindow *window;
@property (nonatomic, strong) HBTapCircle *circle;
@property (nonatomic, strong) HBPanel *panel;
@property (nonatomic, strong) HBAutoTapEngine *engine;
@end

@implementation HBOverlayManager

+ (instancetype)shared {
    static HBOverlayManager *inst;
    static dispatch_once_t tok;
    dispatch_once(&tok, ^{ inst = [[self alloc] init]; });
    return inst;
}

- (void)show {
    if (self.window) return;
    CGRect sb = [UIScreen mainScreen].bounds;

    self.window = [[HBPassthroughWindow alloc] initWithFrame:sb];
    self.window.windowLevel = 2000;
    self.window.backgroundColor = [UIColor clearColor];
    self.window.hidden = NO;

    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = [UIColor clearColor];
    self.window.rootViewController = vc;

    CGFloat pw = 186;
    CGFloat ph = 232;
    CGFloat px = (sb.size.width - pw) / 2;
    CGFloat py = (sb.size.height - ph) / 2 - 20;
    self.panel = [[HBPanel alloc] initWithFullFrame:CGRectMake(px, py, pw, ph)];
    [vc.view addSubview:self.panel];

    CGFloat cs = 44;
    CGFloat cx = sb.size.width - cs - 14;
    CGFloat cy = sb.size.height / 2 - cs / 2;
    self.circle = [[HBTapCircle alloc] initWithFrame:CGRectMake(cx, cy, cs, cs)];
    [vc.view addSubview:self.circle];
    [vc.view bringSubviewToFront:self.circle];

    self.engine = [[HBAutoTapEngine alloc] init];
    self.engine.tapPoint = self.circle.center;

    __weak typeof(self) ws = self;

    self.circle.onPositionChanged = ^(CGPoint pt) {
        ws.engine.tapPoint = pt;
    };

    self.panel.onToggle = ^(BOOL running) {
        if (running) {
            ws.engine.tapPoint = ws.circle.center;
            [ws.engine setDelayMs:ws.panel.speedSlider.value];
            [ws.engine start];
        } else {
            [ws.engine stop];
        }
    };

    self.panel.onSpeedChange = ^(CGFloat ms) {
        [ws.engine setDelayMs:ms];
    };

    self.panel.onMerge = ^{
        [ws doMerge];
    };
}

- (void)doMerge {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UIAlertController *a = [UIAlertController
            alertControllerWithTitle:@"ربط الحسابات"
                             message:@"✅ تم ربط جميع حسابات yallalite بنجاح"
                      preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"تم" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *_) {
            [self.panel enableMerge];
        }]];
        [self.window.rootViewController presentViewController:a animated:YES completion:nil];
    });
}

@end

#pragma mark - Entry Point

%ctor {
    @autoreleasepool {
        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                [[HBOverlayManager shared] show];
            } @catch (NSException *e) {
                NSLog(@"YallaPro: %@", e);
            }
        });
    }
}
