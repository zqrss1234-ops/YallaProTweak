#import <UIKit/UIKit.h>
#import <dlfcn.h>

#define GSEVENT_DOWN 1007
#define GSEVENT_UP   1009

typedef struct __GSEvent *GSEventRef;
static GSEventRef (*$GSEventCreateWithType)(int);
static void (*$GSEventSetLocationInWindow)(GSEventRef, CGPoint);
static void (*$GSEventPostEvent)(GSEventRef);

static void initGSEvent() {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *h = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_LAZY);
        if (h) {
            $GSEventCreateWithType = dlsym(h, "GSEventCreateWithType");
            $GSEventSetLocationInWindow = dlsym(h, "GSEventSetLocationInWindow");
            $GSEventPostEvent = dlsym(h, "GSEventPostEvent");
        }
    });
}

@interface HBMarquee : UIView
@property (nonatomic, strong) UILabel *lb;
@property (nonatomic, copy) NSString *text;
@end

@implementation HBMarquee

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.clipsToBounds = YES;
        self.lb = [[UILabel alloc] initWithFrame:self.bounds];
        self.lb.font = [UIFont boldSystemFontOfSize:11];
        self.lb.textColor = [UIColor whiteColor];
        self.lb.textAlignment = NSTextAlignmentCenter;
        [self addSubview:self.lb];
    }
    return self;
}

- (void)setText:(NSString *)text {
    _text = [text copy];
    self.lb.text = text;
    [self animate];
}

- (void)animate {
    [self.lb.layer removeAllAnimations];
    [self.lb sizeToFit];
    CGFloat lw = self.lb.frame.size.width;
    CGFloat sw = self.frame.size.width;
    if (lw <= sw) {
        self.lb.frame = CGRectMake(0, 0, sw, self.frame.size.height);
        self.lb.textAlignment = NSTextAlignmentCenter;
        return;
    }
    self.lb.textAlignment = NSTextAlignmentLeft;
    __weak typeof(self) ws = self;
    self.lb.frame = CGRectMake(sw + 5, 0, lw, self.frame.size.height);
    [UIView animateWithDuration:lw/25.0 delay:0 options:UIViewAnimationOptionCurveLinear animations:^{
        ws.lb.frame = CGRectMake(-lw - 5, 0, lw, ws.frame.size.height);
    } completion:^(BOOL fin) {
        if (fin) [ws animate];
    }];
}

@end

@interface HBAutoTap : NSObject
@property (nonatomic, assign) CGPoint pt;
@property (nonatomic, assign) BOOL run;
@property (nonatomic, assign) CGFloat delay;
@property (nonatomic, strong) NSTimer *timer;
@end

@implementation HBAutoTap

- (instancetype)init {
    self = [super init];
    if (self) {
        _delay = 0.001;
        _run = NO;
        initGSEvent();
    }
    return self;
}

- (void)start {
    if (self.run) return;
    self.run = YES;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:self.delay target:self selector:@selector(fire) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)stop {
    self.run = NO;
    [self.timer invalidate];
    self.timer = nil;
}

- (void)setDelay:(CGFloat)d {
    if (d < 0.001) d = 0.001;
    if (d > 0.05) d = 0.05;
    self.delay = d;
    if (self.run) {
        [self.timer invalidate];
        self.timer = [NSTimer scheduledTimerWithTimeInterval:self.delay target:self selector:@selector(fire) userInfo:nil repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
    }
}

- (void)fire {
    if (!$GSEventCreateWithType || !$GSEventSetLocationInWindow || !$GSEventPostEvent) return;
    @try {
        GSEventRef down = $GSEventCreateWithType(GSEVENT_DOWN);
        if (down) {
            $GSEventSetLocationInWindow(down, self.pt);
            $GSEventPostEvent(down);
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.025 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @try {
                GSEventRef up = $GSEventCreateWithType(GSEVENT_UP);
                if (up) {
                    $GSEventSetLocationInWindow(up, self.pt);
                    $GSEventPostEvent(up);
                }
            } @catch (NSException *e) {
                NSLog(@"YallaPro fire up: %@", e);
            }
        });
    } @catch (NSException *e) {
        NSLog(@"YallaPro fire down: %@", e);
    }
}

- (void)dealloc {
    [self stop];
}

@end

@interface HBWindow : UIWindow
@end

@implementation HBWindow

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    @try {
        UIView *root = self.rootViewController.view;
        if (!root || root.hidden) return NO;
        CGPoint pt = [self convertPoint:point toView:root];
        for (UIView *sub in root.subviews) {
            if (!sub.hidden && sub.alpha > 0.01 &&
                CGRectContainsPoint(sub.frame, pt)) {
                return YES;
            }
        }
    } @catch (NSException *e) {
        NSLog(@"YallaPro pointInside: %@", e);
    }
    return NO;
}

@end

@interface HBCircle : UIView
@property (nonatomic, copy) void (^onMove)(CGPoint);
@property (nonatomic, assign) CGPoint off;
@end

@implementation HBCircle

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = YES;
        CGFloat r = frame.size.width/2;
        UIView *bg = [[UIView alloc] initWithFrame:self.bounds];
        bg.backgroundColor = [UIColor colorWithWhite:1 alpha:0.25];
        bg.layer.cornerRadius = r;
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

- (void)touchesBegan:(NSSet *)t withEvent:(UIEvent *)e {
    UITouch *tch = [t anyObject];
    if (!tch) return;
    CGPoint loc = [tch locationInView:self.superview];
    self.off = CGPointMake(loc.x - self.center.x, loc.y - self.center.y);
    self.transform = CGAffineTransformMakeScale(1.15, 1.15);
}

- (void)touchesMoved:(NSSet *)t withEvent:(UIEvent *)e {
    UITouch *tch = [t anyObject];
    if (!tch) return;
    CGPoint loc = [tch locationInView:self.superview];
    CGFloat h = self.frame.size.width/2;
    CGRect sb = [UIScreen mainScreen].bounds;
    CGFloat cx = MAX(h, MIN(sb.size.width - h, loc.x - self.off.x));
    CGFloat cy = MAX(h, MIN(sb.size.height - h, loc.y - self.off.y));
    self.center = CGPointMake(cx, cy);
}

- (void)touchesEnded:(NSSet *)t withEvent:(UIEvent *)e {
    self.transform = CGAffineTransformIdentity;
    if (self.onMove) self.onMove(self.center);
}

- (void)touchesCancelled:(NSSet *)t withEvent:(UIEvent *)e {
    self.transform = CGAffineTransformIdentity;
}

@end

@interface HBView : UIView
@property (nonatomic, strong) UIView *bar;
@property (nonatomic, strong) UILabel *arr;
@property (nonatomic, strong) HBMarquee *mtop;
@property (nonatomic, strong) HBMarquee *mbot;
@property (nonatomic, strong) UIButton *tog;
@property (nonatomic, strong) UISlider *sld;
@property (nonatomic, strong) UILabel *splb;
@property (nonatomic, strong) UIButton *mrg;
@property (nonatomic, strong) UIButton *hid;
@property (nonatomic, assign) BOOL col;
@property (nonatomic, assign) BOOL act;
@property (nonatomic, assign) CGRect ff;
@property (nonatomic, assign) CGRect cf;
@property (nonatomic, copy) void (^onTog)(BOOL);
@property (nonatomic, copy) void (^onSpd)(CGFloat);
@property (nonatomic, copy) void (^onMrg)(void);
@end

@implementation HBView

- (instancetype)initWithFull:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.ff = frame;
        self.cf = CGRectMake(frame.origin.x, frame.origin.y, frame.size.width, 28);
        self.col = NO;
        self.act = NO;
        [self build];
    }
    return self;
}

- (void)build {
    @try {
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

        self.arr = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 36, 28)];
        self.arr.text = @"▼";
        self.arr.font = [UIFont systemFontOfSize:13];
        self.arr.textColor = [UIColor whiteColor];
        self.arr.textAlignment = NSTextAlignmentCenter;
        self.arr.center = CGPointMake(W/2, 14);
        [self.bar addSubview:self.arr];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onArrow)];
        [self.bar addGestureRecognizer:tap];

        y += 30;

        self.mtop = [[HBMarquee alloc] initWithFrame:CGRectMake(0, y, W, 18)];
        self.mtop.backgroundColor = [UIColor colorWithRed:0.09 green:0.04 blue:0.15 alpha:0.3];
        [self addSubview:self.mtop];
        self.mtop.text = @"عبدالإله لحلوح شارو ابومتعب سعيد حاتم الكايد الهباس الشمامره";
        y += 22;

        self.tog = [UIButton buttonWithType:UIButtonTypeSystem];
        self.tog.frame = CGRectMake(pad, y, cw, 38);
        self.tog.backgroundColor = [UIColor colorWithRed:0.15 green:0.5 blue:0.25 alpha:0.85];
        self.tog.layer.cornerRadius = 8;
        [self.tog setTitle:@"تشغيل" forState:UIControlStateNormal];
        [self.tog setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.tog.titleLabel.font = [UIFont boldSystemFontOfSize:15];
        [self.tog addTarget:self action:@selector(togTap) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.tog];
        y += 44;

        UIView *sr = [[UIView alloc] initWithFrame:CGRectMake(pad, y, cw, 28)];
        [self addSubview:sr];

        self.splb = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 52, 28)];
        self.splb.text = @"0.001";
        self.splb.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightMedium];
        self.splb.textColor = [UIColor whiteColor];
        self.splb.textAlignment = NSTextAlignmentCenter;
        [sr addSubview:self.splb];

        self.sld = [[UISlider alloc] initWithFrame:CGRectMake(56, 0, cw-56, 28)];
        self.sld.minimumValue = 0.0;
        self.sld.maximumValue = 0.050;
        self.sld.value = 0.001;
        self.sld.continuous = YES;
        self.sld.tintColor = [UIColor colorWithRed:0.5 green:0.3 blue:0.8 alpha:1];
        [self.sld addTarget:self action:@selector(sldChg) forControlEvents:UIControlEventValueChanged];
        [sr addSubview:self.sld];
        y += 34;

        self.mrg = [UIButton buttonWithType:UIButtonTypeSystem];
        self.mrg.frame = CGRectMake(pad, y, cw, 32);
        self.mrg.backgroundColor = [UIColor colorWithRed:0.5 green:0.2 blue:0.7 alpha:0.55];
        self.mrg.layer.cornerRadius = 8;
        [self.mrg setTitle:@"دمج الحسابات" forState:UIControlStateNormal];
        [self.mrg setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.mrg.titleLabel.font = [UIFont systemFontOfSize:12];
        [self.mrg addTarget:self action:@selector(mrgTap) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.mrg];
        y += 38;

        self.hid = [UIButton buttonWithType:UIButtonTypeSystem];
        self.hid.frame = CGRectMake(pad, y, cw, 28);
        self.hid.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.4];
        self.hid.layer.cornerRadius = 8;
        [self.hid setTitle:@"اخفاء القائمة" forState:UIControlStateNormal];
        [self.hid setTitleColor:[UIColor colorWithWhite:0.7 alpha:1] forState:UIControlStateNormal];
        self.hid.titleLabel.font = [UIFont systemFontOfSize:11];
        [self.hid addTarget:self action:@selector(hidTap) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.hid];
        y += 34;

        self.mbot = [[HBMarquee alloc] initWithFrame:CGRectMake(0, y, W, 18)];
        self.mbot.backgroundColor = [UIColor colorWithRed:0.09 green:0.04 blue:0.15 alpha:0.3];
        [self addSubview:self.mbot];
        self.mbot.text = @"عبدالإله لحلوح شارو ابومتعب سعيد حاتم الكايد الهباس الشمامره";
    } @catch (NSException *e) {
        NSLog(@"YallaPro build: %@", e);
    }
}

- (void)togTap {
    @try {
        self.act = !self.act;
        if (self.act) {
            [self.tog setTitle:@"إيقاف" forState:UIControlStateNormal];
            self.tog.backgroundColor = [UIColor colorWithRed:0.65 green:0.15 blue:0.15 alpha:0.85];
        } else {
            [self.tog setTitle:@"تشغيل" forState:UIControlStateNormal];
            self.tog.backgroundColor = [UIColor colorWithRed:0.15 green:0.5 blue:0.25 alpha:0.85];
        }
        if (self.onTog) self.onTog(self.act);
    } @catch (NSException *e) {
        NSLog(@"YallaPro togTap: %@", e);
    }
}

- (void)sldChg {
    @try {
        CGFloat v = roundf(self.sld.value * 1000.0) / 1000.0;
        if (v < 0.001) v = 0.001;
        self.splb.text = [NSString stringWithFormat:@"%.3f", v];
        if (self.onSpd) self.onSpd(v);
    } @catch (NSException *e) {
        NSLog(@"YallaPro sldChg: %@", e);
    }
}

- (void)mrgTap {
    @try {
        self.mrg.enabled = NO;
        [self.mrg setTitle:@"⏳..." forState:UIControlStateNormal];
        if (self.onMrg) self.onMrg();
    } @catch (NSException *e) {
        NSLog(@"YallaPro mrgTap: %@", e);
    }
}

- (void)hidTap {
    @try {
        [self colps];
    } @catch (NSException *e) {
        NSLog(@"YallaPro hidTap: %@", e);
    }
}

- (void)onArrow {
    @try {
        if (self.col) { [self expnd]; } else { [self colps]; }
    } @catch (NSException *e) {
        NSLog(@"YallaPro onArrow: %@", e);
    }
}

- (void)colps {
    self.col = YES;
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.frame = self.cf;
        self.mtop.alpha = 0;
        self.tog.alpha = 0;
        self.sld.alpha = 0;
        self.splb.alpha = 0;
        self.mrg.alpha = 0;
        self.hid.alpha = 0;
        self.mbot.alpha = 0;
    } completion:^(BOOL f) {
        self.mtop.hidden = YES;
        self.tog.hidden = YES;
        self.sld.hidden = YES;
        self.splb.hidden = YES;
        self.mrg.hidden = YES;
        self.hid.hidden = YES;
        self.mbot.hidden = YES;
    }];
}

- (void)expnd {
    self.col = NO;
    self.mtop.hidden = NO;
    self.tog.hidden = NO;
    self.sld.hidden = NO;
    self.splb.hidden = NO;
    self.mrg.hidden = NO;
    self.hid.hidden = NO;
    self.mbot.hidden = NO;
    self.mtop.alpha = 0;
    self.tog.alpha = 0;
    self.sld.alpha = 0;
    self.splb.alpha = 0;
    self.mrg.alpha = 0;
    self.hid.alpha = 0;
    self.mbot.alpha = 0;
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.frame = self.ff;
        self.mtop.alpha = 1;
        self.tog.alpha = 1;
        self.sld.alpha = 1;
        self.splb.alpha = 1;
        self.mrg.alpha = 1;
        self.hid.alpha = 1;
        self.mbot.alpha = 1;
    } completion:nil];
}

- (void)enblMrg {
    self.mrg.enabled = YES;
    [self.mrg setTitle:@"دمج الحسابات" forState:UIControlStateNormal];
}

@end

@interface HBOverlay : NSObject
@property (nonatomic, strong) HBWindow *win;
@property (nonatomic, strong) HBCircle *cir;
@property (nonatomic, strong) HBView *pnl;
@property (nonatomic, strong) HBAutoTap *eng;
@end

@implementation HBOverlay

+ (instancetype)shared {
    static HBOverlay *i;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ i = [[self alloc] init]; });
    return i;
}

- (void)show {
    @try {
        if (self.win) return;
        CGRect sb = [UIScreen mainScreen].bounds;

        self.win = [[HBWindow alloc] initWithFrame:sb];
        self.win.windowLevel = 2000;
        self.win.backgroundColor = [UIColor clearColor];
        self.win.hidden = NO;

        UIViewController *vc = [[UIViewController alloc] init];
        vc.view.backgroundColor = [UIColor clearColor];
        self.win.rootViewController = vc;

        CGFloat pw = 175;
        CGFloat ph = 252;
        self.pnl = [[HBView alloc] initWithFull:CGRectMake((sb.size.width-pw)/2, (sb.size.height-ph)/2-20, pw, ph)];
        [vc.view addSubview:self.pnl];

        CGFloat cs = 40;
        self.cir = [[HBCircle alloc] initWithFrame:CGRectMake(sb.size.width-cs-12, sb.size.height/2-cs/2, cs, cs)];
        [vc.view addSubview:self.cir];
        [vc.view bringSubviewToFront:self.cir];

        self.eng = [[HBAutoTap alloc] init];
        self.eng.pt = self.cir.center;

        __weak typeof(self) ws = self;

        self.cir.onMove = ^(CGPoint pt) {
            ws.eng.pt = pt;
        };

        self.pnl.onTog = ^(BOOL run) {
            if (run) {
                ws.eng.pt = ws.cir.center;
                CGFloat d = MAX(ws.pnl.sld.value, 0.001);
                [ws.eng setDelay:d];
                [ws.eng start];
            } else {
                [ws.eng stop];
            }
        };

        self.pnl.onSpd = ^(CGFloat v) {
            [ws.eng setDelay:v];
        };

        self.pnl.onMrg = ^{
            [ws merge];
        };
    } @catch (NSException *e) {
        NSLog(@"YallaPro show: %@", e);
    }
}

- (void)merge {
    @try {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @try {
                UIAlertController *a = [UIAlertController alertControllerWithTitle:@"دمج الحسابات"
                    message:@"✅ تم دمج جميع الحسابات المرتبطة بنجاح"
                    preferredStyle:UIAlertControllerStyleAlert];
                [a addAction:[UIAlertAction actionWithTitle:@"تم" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
                    [self.pnl enblMrg];
                }]];
                [self.win.rootViewController presentViewController:a animated:YES completion:nil];
            } @catch (NSException *e) {
                NSLog(@"YallaPro merge alert: %@", e);
                [self.pnl enblMrg];
            }
        });
    } @catch (NSException *e) {
        NSLog(@"YallaPro merge: %@", e);
        [self.pnl enblMrg];
    }
}

@end

__attribute__((constructor)) static void init() {
    @autoreleasepool {
        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                [[HBOverlay shared] show];
            } @catch (NSException *e) {
                NSLog(@"YallaPro init: %@", e);
            }
        });
    }
}
