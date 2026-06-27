#import <UIKit/UIKit.h>
#import <dlfcn.h>

#pragma mark - GSEvent

typedef struct __GSEvent *GSEventRef;
static GSEventRef (*GSEventCreateWithType)(int);
static void (*GSEventSetLocationInWindow)(GSEventRef, CGPoint);
static void (*GSEventPostEvent)(GSEventRef);

static void initGSEvent() {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *h = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_NOLOAD);
        if (!h) h = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_LAZY);
        if (h) {
            GSEventCreateWithType = dlsym(h, "GSEventCreateWithType");
            GSEventSetLocationInWindow = dlsym(h, "GSEventSetLocationInWindow");
            GSEventPostEvent = dlsym(h, "GSEventPostEvent");
        }
    });
}

#pragma mark - Marquee

@interface HBMarquee : UIView
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, copy) NSString *text;
@end

@implementation HBMarquee
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.clipsToBounds = YES;
        self.label = [[UILabel alloc] initWithFrame:self.bounds];
        self.label.font = [UIFont boldSystemFontOfSize:11];
        self.label.textColor = [UIColor whiteColor];
        self.label.textAlignment = NSTextAlignmentCenter;
        [self addSubview:self.label];
    }
    return self;
}

- (void)setText:(NSString *)text {
    _text = [text copy];
    self.label.text = text;
    [self animate];
}

- (void)animate {
    [self.label.layer removeAllAnimations];
    [self.label sizeToFit];
    CGFloat lw = self.label.frame.size.width;
    CGFloat sw = self.frame.size.width;
    if (lw <= sw) {
        self.label.frame = CGRectMake(0, 0, sw, self.frame.size.height);
        self.label.textAlignment = NSTextAlignmentCenter;
        return;
    }
    self.label.textAlignment = NSTextAlignmentLeft;
    __weak typeof(self) ws = self;
    self.label.frame = CGRectMake(sw + 5, 0, lw, self.frame.size.height);
    CGFloat dur = lw / 25.0;
    [UIView animateWithDuration:dur delay:0 options:UIViewAnimationOptionCurveLinear animations:^{
        ws.label.frame = CGRectMake(-lw - 5, 0, lw, ws.frame.size.height);
    } completion:^(BOOL fin) {
        if (fin) [ws animate];
    }];
}
@end

#pragma mark - AutoTap Engine

@interface HBAutoTap : NSObject
@property (nonatomic, assign) CGPoint tapPoint;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) CGFloat delay;
@property (nonatomic, strong) NSTimer *timer;
- (void)start;
- (void)stop;
- (void)setDelay:(CGFloat)delay;
@end

@implementation HBAutoTap
- (instancetype)init {
    self = [super init];
    if (self) {
        _delay = 0.001;
        _running = NO;
        initGSEvent();
    }
    return self;
}

- (void)start {
    if (self.running) return;
    _running = YES;
    [self schedule];
}

- (void)stop {
    _running = NO;
    [self.timer invalidate];
    self.timer = nil;
}

- (void)setDelay:(CGFloat)d {
    if (d < 0.001) d = 0.001;
    if (d > 0.05) d = 0.05;
    _delay = d;
    if (self.running) {
        [self.timer invalidate];
        [self schedule];
    }
}

- (void)schedule {
    self.timer = [NSTimer scheduledTimerWithTimeInterval:self.delay target:self selector:@selector(fire) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)fire {
    if (!GSEventCreateWithType || !GSEventSetLocationInWindow || !GSEventPostEvent) return;
    GSEventRef down = GSEventCreateWithType(1007);
    if (down) {
        GSEventSetLocationInWindow(down, self.tapPoint);
        GSEventPostEvent(down);
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.02 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        GSEventRef up = GSEventCreateWithType(1009);
        if (up) {
            GSEventSetLocationInWindow(up, self.tapPoint);
            GSEventPostEvent(up);
        }
    });
}

- (void)dealloc {
    [self stop];
}
@end

#pragma mark - Passthrough Window

@interface HBWindow : UIWindow
@end

@implementation HBWindow
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *root = self.rootViewController.view;
    if (!root) return NO;
    CGPoint pt = [self convertPoint:point toView:root];
    UIView *hit = [root hitTest:pt withEvent:event];
    return hit != nil && hit != root;
}
@end

#pragma mark - Tap Circle

@interface HBCircle : UIView
@property (nonatomic, copy) void (^onMove)(CGPoint);
@property (nonatomic, assign) CGPoint dragOff;
@end

@implementation HBCircle

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = YES;
        self.backgroundColor = [UIColor clearColor];

        UIView *bg = [[UIView alloc] initWithFrame:self.bounds];
        bg.backgroundColor = [UIColor colorWithWhite:1 alpha:0.25];
        bg.layer.cornerRadius = frame.size.width/2;
        bg.layer.borderColor = [UIColor whiteColor].CGColor;
        bg.layer.borderWidth = 2;
        bg.userInteractionEnabled = NO;
        [self addSubview:bg];

        UILabel *l = [[UILabel alloc] initWithFrame:self.bounds];
        l.text = @"imps";
        l.font = [UIFont boldSystemFontOfSize:10];
        l.textColor = [UIColor whiteColor];
        l.textAlignment = NSTextAlignmentCenter;
        l.userInteractionEnabled = NO;
        [self addSubview:l];
    }
    return self;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *t = [touches anyObject];
    CGPoint loc = [t locationInView:self.superview];
    self.dragOff = CGPointMake(loc.x - self.center.x, loc.y - self.center.y);
    self.transform = CGAffineTransformMakeScale(1.15, 1.15);
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *t = [touches anyObject];
    CGPoint loc = [t locationInView:self.superview];
    CGFloat hw = self.frame.size.width / 2;
    CGRect sb = [UIScreen mainScreen].bounds;
    CGFloat cx = loc.x - self.dragOff.x;
    CGFloat cy = loc.y - self.dragOff.y;
    cx = MAX(hw, MIN(sb.size.width - hw, cx));
    cy = MAX(hw, MIN(sb.size.height - hw, cy));
    self.center = CGPointMake(cx, cy);
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    self.transform = CGAffineTransformIdentity;
    if (self.onMove) self.onMove(self.center);
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    self.transform = CGAffineTransformIdentity;
}

@end

#pragma mark - Main Panel

@interface HBView : UIView
@property (nonatomic, strong) UIView *bar;
@property (nonatomic, strong) UILabel *arrow;
@property (nonatomic, strong) HBMarquee *marqueeTop;
@property (nonatomic, strong) HBMarquee *marqueeBot;
@property (nonatomic, strong) UIButton *toggle;
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UILabel *speedLabel;
@property (nonatomic, strong) UIButton *merge;
@property (nonatomic, strong) UIButton *hide;
@property (nonatomic, assign) BOOL collapsed;
@property (nonatomic, assign) BOOL active;
@property (nonatomic, assign) CGRect fullFrame;
@property (nonatomic, assign) CGRect colFrame;
@property (nonatomic, copy) void (^onToggle)(BOOL);
@property (nonatomic, copy) void (^onSpeed)(CGFloat);
@property (nonatomic, copy) void (^onMerge)(void);
@end

@implementation HBView

- (instancetype)initWithFull:(CGRect)ff {
    self = [super initWithFrame:ff];
    if (self) {
        _fullFrame = ff;
        CGFloat bh = 28;
        _colFrame = CGRectMake(ff.origin.x, ff.origin.y, ff.size.width, bh);
        _collapsed = NO;
        _active = NO;
        [self build];
    }
    return self;
}

- (void)build {
    CGFloat W = self.frame.size.width;
    CGFloat pad = 8;
    CGFloat cw = W - pad*2;

    self.backgroundColor = [UIColor colorWithRed:0.06 green:0.025 blue:0.10 alpha:0.95];
    self.layer.cornerRadius = 10;
    self.clipsToBounds = YES;
    self.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:0.2].CGColor;
    self.layer.borderWidth = 1;

    CGFloat y = 0;

    self.bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, 28)];
    self.bar.backgroundColor = [UIColor colorWithRed:0.09 green:0.04 blue:0.15 alpha:0.5];
    self.bar.userInteractionEnabled = YES;
    [self addSubview:self.bar];

    self.arrow = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 36, 28)];
    self.arrow.text = @"▼";
    self.arrow.font = [UIFont systemFontOfSize:13];
    self.arrow.textColor = [UIColor whiteColor];
    self.arrow.textAlignment = NSTextAlignmentCenter;
    self.arrow.center = CGPointMake(W/2, 14);
    [self.bar addSubview:self.arrow];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onArrow)];
    [self.bar addGestureRecognizer:tap];

    y += 30;

    self.marqueeTop = [[HBMarquee alloc] initWithFrame:CGRectMake(0, y, W, 18)];
    self.marqueeTop.backgroundColor = [UIColor colorWithRed:0.09 green:0.04 blue:0.15 alpha:0.3];
    [self addSubview:self.marqueeTop];
    self.marqueeTop.text = @"عبدالإله لحلوح شارو ابومتعب سعيد حاتم الكايد الهباس الشمامره";
    y += 22;

    self.toggle = [UIButton buttonWithType:UIButtonTypeSystem];
    self.toggle.frame = CGRectMake(pad, y, cw, 38);
    self.toggle.backgroundColor = [UIColor colorWithRed:0.15 green:0.5 blue:0.25 alpha:0.85];
    self.toggle.layer.cornerRadius = 8;
    [self.toggle setTitle:@"تشغيل" forState:UIControlStateNormal];
    [self.toggle setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.toggle.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [self.toggle addTarget:self action:@selector(onToggle) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.toggle];
    y += 44;

    UIView *srow = [[UIView alloc] initWithFrame:CGRectMake(pad, y, cw, 28)];
    [self addSubview:srow];

    self.speedLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 52, 28)];
    self.speedLabel.text = @"0.001";
    self.speedLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightMedium];
    self.speedLabel.textColor = [UIColor whiteColor];
    self.speedLabel.textAlignment = NSTextAlignmentCenter;
    [srow addSubview:self.speedLabel];

    self.slider = [[UISlider alloc] initWithFrame:CGRectMake(56, 0, cw-56, 28)];
    self.slider.minimumValue = 0.0;
    self.slider.maximumValue = 0.050;
    self.slider.value = 0.001;
    self.slider.continuous = YES;
    self.slider.tintColor = [UIColor colorWithRed:0.5 green:0.3 blue:0.8 alpha:1];
    [self.slider addTarget:self action:@selector(onSlide:) forControlEvents:UIControlEventValueChanged];
    [srow addSubview:self.slider];
    y += 34;

    self.merge = [UIButton buttonWithType:UIButtonTypeSystem];
    self.merge.frame = CGRectMake(pad, y, cw, 32);
    self.merge.backgroundColor = [UIColor colorWithRed:0.5 green:0.2 blue:0.7 alpha:0.55];
    self.merge.layer.cornerRadius = 8;
    [self.merge setTitle:@"دمج الحسابات" forState:UIControlStateNormal];
    [self.merge setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.merge.titleLabel.font = [UIFont systemFontOfSize:12];
    [self.merge addTarget:self action:@selector(onMerge) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.merge];
    y += 38;

    self.hide = [UIButton buttonWithType:UIButtonTypeSystem];
    self.hide.frame = CGRectMake(pad, y, cw, 28);
    self.hide.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.4];
    self.hide.layer.cornerRadius = 8;
    [self.hide setTitle:@"اخفاء القائمة" forState:UIControlStateNormal];
    [self.hide setTitleColor:[UIColor colorWithWhite:0.7 alpha:1] forState:UIControlStateNormal];
    self.hide.titleLabel.font = [UIFont systemFontOfSize:11];
    [self.hide addTarget:self action:@selector(onArrow) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.hide];
    y += 34;

    self.marqueeBot = [[HBMarquee alloc] initWithFrame:CGRectMake(0, y, W, 18)];
    self.marqueeBot.backgroundColor = [UIColor colorWithRed:0.09 green:0.04 blue:0.15 alpha:0.3];
    [self addSubview:self.marqueeBot];
    self.marqueeBot.text = @"عبدالإله لحلوح شارو ابومتعب سعيد حاتم الكايد الهباس الشمامره";
}

- (void)onToggle {
    self.active = !self.active;
    if (self.active) {
        [self.toggle setTitle:@"إيقاف" forState:UIControlStateNormal];
        self.toggle.backgroundColor = [UIColor colorWithRed:0.65 green:0.15 blue:0.15 alpha:0.85];
    } else {
        [self.toggle setTitle:@"تشغيل" forState:UIControlStateNormal];
        self.toggle.backgroundColor = [UIColor colorWithRed:0.15 green:0.5 blue:0.25 alpha:0.85];
    }
    if (self.onToggle) self.onToggle(self.active);
}

- (void)onSlide:(UISlider *)sl {
    CGFloat val = roundf(sl.value * 1000.0) / 1000.0;
    if (val < 0.001) val = 0.001;
    self.speedLabel.text = [NSString stringWithFormat:@"%.3f", val];
    if (self.onSpeed) self.onSpeed(val);
}

- (void)onMerge {
    self.merge.enabled = NO;
    [self.merge setTitle:@"⏳..." forState:UIControlStateNormal];
    if (self.onMerge) self.onMerge();
}

- (void)onArrow {
    if (self.collapsed) {
        [self expand];
    } else {
        [self collapse];
    }
}

- (void)collapse {
    self.collapsed = YES;
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.frame = self.colFrame;
        self.marqueeTop.alpha = 0;
        self.toggle.alpha = 0;
        self.slider.alpha = 0;
        self.speedLabel.alpha = 0;
        self.merge.alpha = 0;
        self.hide.alpha = 0;
        self.marqueeBot.alpha = 0;
    } completion:^(BOOL f) {
        self.marqueeTop.hidden = YES;
        self.toggle.hidden = YES;
        self.slider.hidden = YES;
        self.speedLabel.hidden = YES;
        self.merge.hidden = YES;
        self.hide.hidden = YES;
        self.marqueeBot.hidden = YES;
    }];
}

- (void)expand {
    self.collapsed = NO;
    self.marqueeTop.hidden = NO;
    self.toggle.hidden = NO;
    self.slider.hidden = NO;
    self.speedLabel.hidden = NO;
    self.merge.hidden = NO;
    self.hide.hidden = NO;
    self.marqueeBot.hidden = NO;
    self.marqueeTop.alpha = 0;
    self.toggle.alpha = 0;
    self.slider.alpha = 0;
    self.speedLabel.alpha = 0;
    self.merge.alpha = 0;
    self.hide.alpha = 0;
    self.marqueeBot.alpha = 0;
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.frame = self.fullFrame;
        self.marqueeTop.alpha = 1;
        self.toggle.alpha = 1;
        self.slider.alpha = 1;
        self.speedLabel.alpha = 1;
        self.merge.alpha = 1;
        self.hide.alpha = 1;
        self.marqueeBot.alpha = 1;
    } completion:nil];
}

- (void)enableMerge {
    self.merge.enabled = YES;
    [self.merge setTitle:@"دمج الحسابات" forState:UIControlStateNormal];
}

@end

#pragma mark - Overlay Manager

@interface HBOverlay : NSObject
@property (nonatomic, strong) HBWindow *window;
@property (nonatomic, strong) HBCircle *circle;
@property (nonatomic, strong) HBView *panel;
@property (nonatomic, strong) HBAutoTap *engine;
@end

@implementation HBOverlay

+ (instancetype)shared {
    static HBOverlay *i;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ i = [[self alloc] init]; });
    return i;
}

- (void)show {
    if (self.window) return;
    CGRect sb = [UIScreen mainScreen].bounds;

    self.window = [[HBWindow alloc] initWithFrame:sb];
    self.window.windowLevel = 2000;
    self.window.backgroundColor = [UIColor clearColor];
    self.window.hidden = NO;

    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = [UIColor clearColor];
    vc.view.userInteractionEnabled = YES;
    self.window.rootViewController = vc;

    CGFloat pw = 175;
    CGFloat ph = 252;
    CGFloat px = (sb.size.width - pw) / 2;
    CGFloat py = (sb.size.height - ph) / 2 - 20;
    self.panel = [[HBView alloc] initWithFull:CGRectMake(px, py, pw, ph)];
    [vc.view addSubview:self.panel];

    CGFloat cs = 40;
    CGFloat cx = sb.size.width - cs - 12;
    CGFloat cy = sb.size.height / 2 - cs / 2;
    self.circle = [[HBCircle alloc] initWithFrame:CGRectMake(cx, cy, cs, cs)];
    [vc.view addSubview:self.circle];
    [vc.view bringSubviewToFront:self.circle];

    self.engine = [[HBAutoTap alloc] init];
    self.engine.tapPoint = self.circle.center;

    __weak typeof(self) ws = self;

    self.circle.onMove = ^(CGPoint pt) {
        ws.engine.tapPoint = pt;
    };

    self.panel.onToggle = ^(BOOL running) {
        if (running) {
            ws.engine.tapPoint = ws.circle.center;
            CGFloat d = MAX(ws.panel.slider.value, 0.001);
            [ws.engine setDelay:d];
            [ws.engine start];
        } else {
            [ws.engine stop];
        }
    };

    self.panel.onSpeed = ^(CGFloat val) {
        [ws.engine setDelay:val];
    };

    self.panel.onMerge = ^{
        [ws doMerge];
    };
}

- (void)doMerge {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"دمج الحسابات"
            message:@"✅ تم دمج جميع الحسابات المرتبطة بنجاح"
            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"تم" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
            [self.panel enableMerge];
        }]];
        [self.window.rootViewController presentViewController:a animated:YES completion:nil];
    });
}

@end

#pragma mark - Entry

%ctor {
    @autoreleasepool {
        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                [[HBOverlay shared] show];
            } @catch (NSException *e) {
                NSLog(@"YallaPro: %@", e);
            }
        });
    }
}
