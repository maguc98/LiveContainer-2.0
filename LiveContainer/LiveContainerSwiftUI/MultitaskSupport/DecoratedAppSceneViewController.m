#import "DecoratedAppSceneViewController.h"
#import "ResizeHandleView.h"
#import "LiveContainerSwiftUI-Swift.h"
#import "AppSceneViewController.h"
#import "UIKitPrivate+MultitaskSupport.h"
#import "PiPManager.h"
#import "VirtualWindowsHostView.h"
#import "../../LiveContainer/Localization.h"
#import "utils.h"

@interface DecoratedAppSceneViewController()
@property(nonatomic) NSArray* activatedVerticalConstraints;
@property(nonatomic) NSString* dataUUID;
@property(nonatomic) int pid;
@property(nonatomic) CGRect originalFrame;
@property(nonatomic) UIButton *maximizeButton;
@property(nonatomic) bool isAppTerminationRequested;
@end

static UIButton *LCCreateMultitaskTrafficLightButton(NSString *symbolName, UIColor *backgroundColor) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImageSymbolConfiguration *configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:10.0 weight:UIImageSymbolWeightBold];
    UIImage *image = [[UIImage systemImageNamed:symbolName] imageWithConfiguration:configuration];

    [button setImage:image forState:UIControlStateNormal];
    button.tintColor = UIColor.whiteColor;
    button.backgroundColor = backgroundColor;
    button.layer.cornerRadius = 12.0;
    button.layer.borderWidth = 0.8;
    button.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.62].CGColor;
    button.layer.shadowColor = [UIColor colorWithWhite:0.12 alpha:1.0].CGColor;
    button.layer.shadowOpacity = 0.10;
    button.layer.shadowRadius = 2.0;
    button.layer.shadowOffset = CGSizeMake(0, 1);
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintEqualToConstant:24.0],
        [button.heightAnchor constraintEqualToConstant:24.0]
    ]];
    return button;
}

@implementation DecoratedAppSceneViewController
- (instancetype)initWindowName:(NSString*)windowName bundleId:(NSString*)bundleId dataUUID:(NSString*)dataUUID rootVC:(UIViewController*)rootVC {
    self = [super initWithNibName:nil bundle:nil];
    self.view = [[UIStackView alloc] initWithFrame:self.view.frame];
    [MultitaskDockManager.shared.windowHostingView addSubview:self.view];
    [rootVC addChildViewController:self];
    
    _dataUUID = dataUUID;
    _scaleRatio = 1.0;
    _isMaximized = [NSUserDefaults.lcUserDefaults boolForKey:@"LCLaunchMultitaskMaximized"];
    _appSceneVC = [[AppSceneViewController alloc] initWithBundleId:bundleId dataUUID:dataUUID delegate:self];
    self.title = windowName;
    [self setupDecoratedView];
    
    [MultitaskDockManager.shared addRunningApp:windowName appUUID:dataUUID view:self.view];
    
    NSArray *menuItems = @[
        [UIAction actionWithTitle:@"lc.multitask.copyPid".loc image:[UIImage systemImageNamed:@"doc.on.doc"] identifier:nil handler:^(UIAction * _Nonnull action) {
            UIPasteboard.generalPasteboard.string = @(self.appSceneVC.pid).stringValue;
        }],
        [UIAction actionWithTitle:@"lc.multitask.enablePip".loc image:[UIImage systemImageNamed:@"pip.enter"] identifier:nil handler:^(UIAction * _Nonnull action) {
            if ([PiPManager.shared isPiPWithVC:self.appSceneVC]) {
                [PiPManager.shared stopPiP];
            } else {
                [PiPManager.shared startPiPWithVC:self.appSceneVC];
            }
        }],
        [UICustomViewMenuElement elementWithViewProvider:^UIView *(UICustomViewMenuElement *element) {
            return [self scaleSliderViewWithTitle:@"lc.multitask.scale".loc min:0.5 max:2.0 value:self.scaleRatio stepInterval:0.01];
        }]
    ];

    __weak typeof(self) weakSelf = self;

    UIButton *closeButton = LCCreateMultitaskTrafficLightButton(
        @"xmark",
        [UIColor colorWithRed:0.94 green:0.34 blue:0.33 alpha:1.0]
    );
    [closeButton addTarget:self action:@selector(closeWindow) forControlEvents:UIControlEventTouchUpInside];

    NSString *maximizeImageName = _isMaximized
        ? @"arrow.down.right.and.arrow.up.left"
        : @"arrow.up.left.and.arrow.down.right";
    self.maximizeButton = LCCreateMultitaskTrafficLightButton(
        maximizeImageName,
        [UIColor colorWithRed:0.28 green:0.70 blue:0.46 alpha:1.0]
    );
    [self.maximizeButton addTarget:self action:@selector(maximizeWindow) forControlEvents:UIControlEventTouchUpInside];

    UIButton *minimizeButton = LCCreateMultitaskTrafficLightButton(
        @"minus",
        [UIColor colorWithRed:0.98 green:0.72 blue:0.27 alpha:1.0]
    );
    [minimizeButton addTarget:self action:@selector(minimizeWindow) forControlEvents:UIControlEventTouchUpInside];

    UIButton *appMenuButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [appMenuButton setTitle:windowName forState:UIControlStateNormal];
    [appMenuButton setImage:[UIImage systemImageNamed:@"chevron.down"] forState:UIControlStateNormal];
    appMenuButton.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    appMenuButton.titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    appMenuButton.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    appMenuButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    appMenuButton.titleLabel.minimumScaleFactor = 0.85;
    appMenuButton.tintColor = [UIColor colorWithRed:0.25 green:0.32 blue:0.42 alpha:1.0];
    appMenuButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    appMenuButton.contentEdgeInsets = UIEdgeInsetsMake(0, 2, 0, 2);
    appMenuButton.titleEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 4);
    appMenuButton.imageEdgeInsets = UIEdgeInsetsMake(0, -3, 0, 0);
    appMenuButton.showsMenuAsPrimaryAction = YES;
    appMenuButton.accessibilityLabel = windowName;
    appMenuButton.menu = [UIMenu menuWithTitle:@"" children:@[
        [UIDeferredMenuElement elementWithProvider:^(void (^completion)(NSArray<UIMenuElement *> *elements)) {
            if (!weakSelf) {
                completion(@[]);
                return;
            }
            if (!weakSelf.appSceneVC.isAppRunning) {
                UIAction *terminated = [UIAction actionWithTitle:NSLocalizedString(@"lc.multitaskAppWindow.appTerminated", nil)
                                                            image:nil
                                                       identifier:nil
                                                          handler:^(__kindof UIAction * _Nonnull action) {}];
                terminated.attributes = UIMenuElementAttributesDisabled;
                completion(@[terminated]);
                return;
            }
            UIAction *pidInfo = [UIAction actionWithTitle:[NSString stringWithFormat:@"PID: %d", weakSelf.pid]
                                                     image:nil
                                                identifier:nil
                                                   handler:^(__kindof UIAction * _Nonnull action) {}];
            pidInfo.attributes = UIMenuElementAttributesDisabled;
            completion([@[pidInfo] arrayByAddingObjectsFromArray:menuItems]);
        }]
    ]];

    UIView *pillContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 244, 36)];
    pillContainer.layer.cornerRadius = 18.0;
    pillContainer.layer.shadowColor = [UIColor colorWithRed:0.30 green:0.40 blue:0.55 alpha:1.0].CGColor;
    pillContainer.layer.shadowOpacity = 0.13;
    pillContainer.layer.shadowRadius = 10.0;
    pillContainer.layer.shadowOffset = CGSizeMake(0, 4);
    pillContainer.backgroundColor = UIColor.clearColor;

    UIVisualEffectView *pillGlass = [[UIVisualEffectView alloc] initWithEffect:
        [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialLight]];
    pillGlass.frame = pillContainer.bounds;
    pillGlass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    pillGlass.layer.cornerRadius = 18.0;
    pillGlass.layer.masksToBounds = YES;
    pillGlass.layer.borderWidth = 1.0;
    pillGlass.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.82].CGColor;
    pillGlass.contentView.backgroundColor = [UIColor colorWithRed:0.91 green:0.95 blue:0.99 alpha:0.20];
    [pillContainer addSubview:pillGlass];

    UIView *separator = [[UIView alloc] initWithFrame:CGRectZero];
    separator.backgroundColor = [UIColor colorWithRed:0.61 green:0.68 blue:0.78 alpha:0.35];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [separator.widthAnchor constraintEqualToConstant:1.0],
        [separator.heightAnchor constraintEqualToConstant:18.0]
    ]];

    UIStackView *controlStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        closeButton, minimizeButton, self.maximizeButton, separator, appMenuButton
    ]];
    controlStack.axis = UILayoutConstraintAxisHorizontal;
    controlStack.alignment = UIStackViewAlignmentCenter;
    controlStack.distribution = UIStackViewDistributionFill;
    controlStack.spacing = 5.0;
    controlStack.translatesAutoresizingMaskIntoConstraints = NO;
    [pillGlass.contentView addSubview:controlStack];

    [NSLayoutConstraint activateConstraints:@[
        [controlStack.leadingAnchor constraintEqualToAnchor:pillGlass.contentView.leadingAnchor constant:7.0],
        [controlStack.trailingAnchor constraintEqualToAnchor:pillGlass.contentView.trailingAnchor constant:-7.0],
        [controlStack.centerYAnchor constraintEqualToAnchor:pillGlass.contentView.centerYAnchor],
        [appMenuButton.widthAnchor constraintLessThanOrEqualToConstant:112.0]
    ]];
    [appMenuButton setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [appMenuButton setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    self.navigationItem.titleView = pillContainer;
    self.navigationItem.leftBarButtonItems = nil;
    self.navigationItem.rightBarButtonItems = nil;

    return self;
}

- (void)setupDecoratedView {
    CGFloat navBarHeight = 44;
    BOOL isLandscape = UIInterfaceOrientationIsLandscape(UIApp.statusBarOrientation);
    // The floating toolbar overlays the app and no longer contributes to the window's content height.
    CGRect frame = CGRectMake(0, 0, isLandscape ? 480 : 320, isLandscape ? 320 : 480);
    CGPoint rootViewCenter = self.view.superview.center;
    frame.origin = CGPointMake(rootViewCenter.x - frame.size.width / 2, rootViewCenter.y - frame.size.height / 2);
    
    if(_isMaximized) {
        CGRect maxFrame = UIEdgeInsetsInsetRect(self.view.window.frame, self.view.window.safeAreaInsets);
        // save origin as normalized coordinates
        frame.origin.x /= maxFrame.size.width;
        frame.origin.y /= maxFrame.size.height;
        self.originalFrame = frame;
    } else {
        self.view.frame = frame;
    }
    
    // Navigation bar: keep the bar itself transparent so the centered glass island floats above the app.
    UINavigationBar *navigationBar = [[UINavigationBar alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, navBarHeight)];
    navigationBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    navigationBar.translucent = YES;
    navigationBar.backgroundColor = UIColor.clearColor;
    [navigationBar setBackgroundImage:[UIImage new] forBarMetrics:UIBarMetricsDefault];
    navigationBar.shadowImage = [UIImage new];
    UINavigationItem *navigationItem = [[UINavigationItem alloc] initWithTitle:self.title];
    navigationBar.items = @[navigationItem];
    
    self.view.axis = UILayoutConstraintAxisVertical;
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.view.layer.cornerRadius = 10;
    self.view.layer.masksToBounds = YES;

    self.navigationBar = navigationBar;
    self.navigationItem = navigationBar.items.firstObject;
    if (!self.navigationBar.superview) {
        // Keep the navigation bar out of the vertical stack so it floats above app content.
        [self.view addSubview:self.navigationBar];
    }
    
    CGRect contentFrame = CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height);
    UIView *fixedPositionContentView = [[UIView alloc] initWithFrame:contentFrame];
    self.contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addArrangedSubview:fixedPositionContentView];
    [self.view sendSubviewToBack:fixedPositionContentView];
    
    self.contentView = [[UIView alloc] initWithFrame:contentFrame];
    self.contentView.layer.anchorPoint = self.contentView.layer.position = CGPointMake(0, 0);
    self.contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [fixedPositionContentView addSubview:self.contentView];
    
    UIPanGestureRecognizer *moveGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(moveWindow:)];
    moveGesture.minimumNumberOfTouches = 1;
    moveGesture.maximumNumberOfTouches = 1;
    [self.navigationBar addGestureRecognizer:moveGesture];

    // Resize handle (idea stolen from Notes debugging window)
    UIPanGestureRecognizer *resizeGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(resizeWindow:)];
    resizeGesture.minimumNumberOfTouches = 1;
    resizeGesture.maximumNumberOfTouches = 1;
    self.resizeHandle = [[ResizeHandleView alloc] initWithFrame:CGRectMake(self.view.frame.size.width - navBarHeight, self.view.frame.size.height - navBarHeight, navBarHeight, navBarHeight)];
    self.resizeHandle.alpha = _isMaximized ? 0.0 : 1.0;
    [self.resizeHandle addGestureRecognizer:resizeGesture];
    [self.view addSubview:self.resizeHandle];
    
    self.view.layer.borderWidth = _isMaximized ? 0.0 : 1.0;
    self.view.layer.borderColor = UIColor.secondarySystemBackgroundColor.CGColor;
    
    [self addChildViewController:_appSceneVC];
    [self.view insertSubview:_appSceneVC.view atIndex:0];
    _appSceneVC.view.translatesAutoresizingMaskIntoConstraints = NO;
    
    [self updateVerticalConstraints];
    [NSLayoutConstraint activateConstraints:@[
        [_appSceneVC.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_appSceneVC.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];
    
    
    NSUserDefaults *defaults = NSUserDefaults.lcSharedDefaults;

    [defaults addObserver:self forKeyPath:@"LCMultitaskBottomWindowBar" options:NSKeyValueObservingOptionNew context:NULL];
    [self updateOriginalFrame];
}


// Stolen from UIKitester
- (UIView *)scaleSliderViewWithTitle:(NSString *)title min:(CGFloat)minValue max:(CGFloat)maxValue value:(CGFloat)initialValue stepInterval:(CGFloat)step {
    UIView *containerView = [[UIView alloc] init];
    containerView.translatesAutoresizingMaskIntoConstraints = NO;
    containerView.exclusiveTouch = YES;

    UIStackView *stackView = [[UIStackView alloc] init];
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.spacing = 0.0;
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [containerView addSubview:stackView];
    
    [NSLayoutConstraint activateConstraints:@[
        [stackView.topAnchor constraintEqualToAnchor:containerView.topAnchor constant:10.0],
        [stackView.bottomAnchor constraintEqualToAnchor:containerView.bottomAnchor constant:-8.0],
        [stackView.leadingAnchor constraintEqualToAnchor:containerView.leadingAnchor constant:16.0],
        [stackView.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor constant:-16.0]
    ]];
    
    UILabel *label = [[UILabel alloc] init];
    label.text = title;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [UIFont boldSystemFontOfSize:12.0];
    [stackView addArrangedSubview:label];
    
    _UIPrototypingMenuSlider *slider = [[_UIPrototypingMenuSlider alloc] init];
    slider.minimumValue = minValue;
    slider.maximumValue = maxValue;
    slider.value = initialValue;
    slider.stepSize = step;
    
    NSLayoutConstraint *sliderHeight = [slider.heightAnchor constraintEqualToConstant:40.0];
    sliderHeight.active = YES;
    
    [stackView addArrangedSubview:slider];
    
    [slider addTarget:self action:@selector(scaleSliderChanged:) forControlEvents:UIControlEventValueChanged];
    
    return containerView;
}

- (void)scaleSliderChanged:(_UIPrototypingMenuSlider *)slider {
    self.scaleRatio = slider.value;
    self.appSceneVC.scaleRatio = _scaleRatio;
    if(self.appSceneVC.usesHostingControllerAPI) {
        self.appSceneVC.contentView.transform = CGAffineTransformMakeScale(_scaleRatio, _scaleRatio);
    } else {
        self.appSceneVC.contentView.layer.sublayerTransform = CATransform3DMakeScale(_scaleRatio, _scaleRatio, 1.0);
    }
    __weak typeof(self) weakSelf = self;
    [self.appSceneVC updateFrameWithSettingsBlock:^(UIMutableApplicationSceneSettings *settings) {
        if(weakSelf.isMaximized) {
            [weakSelf updateMaximizedSafeAreaWithSettings:settings];
        } else {
            // it seems some apps don't honor these settings so we don't cover the top of the app
            settings.peripheryInsets = UIEdgeInsetsZero;
            settings.safeAreaInsetsPortrait = UIEdgeInsetsZero;
        }
    }];
}

- (void)closeWindow {
    _isAppTerminationRequested = true;
    if([_appSceneVC isAppRunning]) {
        [_appSceneVC terminate];
    } else {
        [self appSceneVCAppDidExit:self.appSceneVC];
    }
}

- (void)minimizeWindow {
    if (self.view.hidden) return;
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.view.alpha = 0;
        self.view.transform = CGAffineTransformMakeScale(0.1, 0.1);
    } completion:^(BOOL finished) {
        if (!finished) return;
        self.view.hidden = YES;
        self.view.transform = CGAffineTransformIdentity;
        [self.view.superview sendSubviewToBack:self.view];
    }];
}

- (void)minimizeWindowPiP {
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.view.alpha = 0;
    } completion:^(BOOL finished) {
        self.view.hidden = YES;
    }];
}

- (void)unminimizeWindowPiP {
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.view.hidden = NO;
        self.view.alpha = 1;
    } completion:nil];
}

- (void)maximizeWindow {
    void (^updateSettingsBlock)(UIMutableApplicationSceneSettings *settings);
    
    [self.view layoutIfNeeded];
    if (self.isMaximized) {
        updateSettingsBlock = ^(UIMutableApplicationSceneSettings *settings) {
            [self updateWindowedFrameWithSettings:settings];
        };
        CGRect maxFrame = UIEdgeInsetsInsetRect(self.view.window.frame, self.view.window.safeAreaInsets);
        CGRect newFrame = CGRectMake(self.originalFrame.origin.x * maxFrame.size.width, self.originalFrame.origin.y * maxFrame.size.height, self.originalFrame.size.width, self.originalFrame.size.height);
        [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            self.view.frame = newFrame;
            self.view.layer.borderWidth = 1;
            self.resizeHandle.alpha = 1;
            
            [self.appSceneVC updateSettingsWithBlock:updateSettingsBlock];
            
            [self.view layoutIfNeeded];
        } completion:^(BOOL finished) {
            self.isMaximized = NO;
            UIImage *maximizeImage = [UIImage systemImageNamed:@"arrow.up.left.and.arrow.down.right"];
            UIImageSymbolConfiguration *maximizeConfig = [UIImageSymbolConfiguration configurationWithPointSize:10.0 weight:UIImageSymbolWeightBold];
            [self.maximizeButton setImage:[maximizeImage imageWithConfiguration:maximizeConfig] forState:UIControlStateNormal];
        }];
    } else {
        updateSettingsBlock = ^(UIMutableApplicationSceneSettings *settings) {
            [self updateMaximizedFrameWithSettings:settings];
        };
        [self updateOriginalFrame];
        [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            self.isMaximized = YES;
            [self updateVerticalConstraints];
            
            self.view.layer.borderWidth = 0;
            self.resizeHandle.alpha = 0;
            
            [self.appSceneVC updateSettingsWithBlock:updateSettingsBlock];
            
            [self.view layoutIfNeeded];
        } completion:^(BOOL finished) {
            UIImage *restoreImage = [UIImage systemImageNamed:@"arrow.down.right.and.arrow.up.left"];
            UIImageSymbolConfiguration *restoreConfig = [UIImageSymbolConfiguration configurationWithPointSize:10.0 weight:UIImageSymbolWeightBold];
            [self.maximizeButton setImage:[restoreImage imageWithConfiguration:restoreConfig] forState:UIControlStateNormal];
        }];
    }
}

- (void)appSceneVCAppDidExit:(AppSceneViewController*)vc {
    BOOL skipTerminationScreen = [NSUserDefaults.lcSharedDefaults boolForKey:@"LCSkipTerminatedScreen"];
    BOOL isManual = _isAppTerminationRequested;
    if(isManual || skipTerminationScreen) {
        
        MultitaskDockManager *dock = [MultitaskDockManager shared];
        [dock removeRunningApp:self.dataUUID];
        
        self.view.layer.masksToBounds = NO;
        [UIView transitionWithView:self.view duration:0.4 options:UIViewAnimationOptionTransitionCurlUp animations:^{
            self.view.hidden = YES;
        } completion:^(BOOL b){
            [self.view removeFromSuperview];
        }];
        
        if(skipTerminationScreen) {
            [MultitaskRelaunchManager scheduleRelaunchIfNeededWithBundleId:self.appSceneVC.bundleId dataUUID:self.dataUUID isManualTermination:isManual];
        }
    } else {
        UILabel *label = [[UILabel alloc] initWithFrame:self.view.bounds];
        label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        label.lineBreakMode = NSLineBreakByWordWrapping;
        label.numberOfLines = 0;
        label.text = NSLocalizedString(@"lc.multitaskAppWindow.appTerminated", @"");
        label.textAlignment = NSTextAlignmentCenter;
        [self.view insertSubview:label atIndex:0];
    }
}

- (void)appSceneVC:(AppSceneViewController*)vc didInitializeWithError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        if(error) {
            [vc appTerminationCleanUp];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"lc.common.error".loc message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"lc.common.ok".loc style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"lc.common.copy".loc style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                UIPasteboard.generalPasteboard.string = error.localizedDescription;
            }]];
            [self presentViewController:alert animated:YES completion:nil];
        } else {
            self.pid = vc.pid;
            [self updateOriginalFrame];
            if (self.pidAvailableHandler) {
                self.pidAvailableHandler(@(self.pid), nil);
            }
        }
    });
}

- (void)appSceneVCWillActivateScene:(AppSceneViewController *)vc {
    // Set up initial settings such as frame, safe area, etc
    [self appSceneVC:vc didUpdateFromSettings:vc.presenter.scene.settings.mutableCopy transitionContext:nil lifecycleActionType:0];
}

- (void)appSceneVC:(AppSceneViewController*)vc didUpdateFromSettings:(UIMutableApplicationSceneSettings *)baseSettings transitionContext:(id)newContext lifecycleActionType:(uint32_t)actionType {
    [self.appSceneVC updateSettingsWithBlock:^(UIMutableApplicationSceneSettings *settings) {
        settings.userInterfaceStyle = baseSettings.userInterfaceStyle;
        settings.interfaceOrientation = baseSettings.interfaceOrientation;
        settings.deviceOrientation = baseSettings.deviceOrientation;
        settings.foreground = YES;
        
        if(self.isMaximized) {
            [self updateMaximizedFrameWithSettings:settings];
        } else {
            [self updateWindowedFrameWithSettings:settings];
        }
        CGRect newFrame = CGRectMake(0, 0, self.view.bounds.size.width, self.view.bounds.size.height);
        
        if(UIInterfaceOrientationIsLandscape(baseSettings.interfaceOrientation)) {
            settings.frame = CGRectMake(0, 0, newFrame.size.height, newFrame.size.width);
        } else {
            settings.frame = CGRectMake(0, 0, newFrame.size.width, newFrame.size.height);
        }
    }];
}

- (void)adjustNavigationBarButtonSpacingWithNegativeSpacing:(CGFloat)spacing rightMargin:(CGFloat)margin {
    if (!self.navigationBar) return;
    [self findAndAdjustButtonBarStackView:self.navigationBar withSpacing:spacing rightMargin:margin];
}

- (void)findAndAdjustButtonBarStackView:(UIView *)view withSpacing:(CGFloat)spacing rightMargin:(CGFloat)margin {
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:NSClassFromString(@"_UIButtonBarStackView")]) {
            if ([subview respondsToSelector:@selector(setSpacing:)]) {
                [(_UIButtonBarStackView *)subview setSpacing:spacing];
            }
            
            if (subview.superview) {
                for (NSLayoutConstraint *constraint in subview.superview.constraints) {
                    if ((constraint.firstItem == subview && constraint.firstAttribute == NSLayoutAttributeTrailing) ||
                        (constraint.secondItem == subview && constraint.secondAttribute == NSLayoutAttributeTrailing)) {
                        constraint.constant = (constraint.firstItem == subview) ? -margin : margin;
                        break;
                    }
                }
                
                [subview setNeedsLayout];
                [subview.superview setNeedsLayout];
            }
            
            return;
        }
        
        [self findAndAdjustButtonBarStackView:subview withSpacing:spacing rightMargin:margin];
    }
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    [self updateVerticalConstraints];
    [self adjustNavigationBarButtonSpacingWithNegativeSpacing:-8.0 rightMargin:-4.0];

    if(_isMaximized) {
        [self.appSceneVC updateSettingsWithBlock:^(UIMutableApplicationSceneSettings *settings) {
            [self updateMaximizedFrameWithSettings:settings];
        }];
    }
}

- (void)moveWindow:(UIPanGestureRecognizer*)sender {
    if(_isMaximized) return;
    
    CGPoint point = [sender translationInView:self.view];
    [sender setTranslation:CGPointZero inView:self.view];

    self.view.center = CGPointMake(self.view.center.x + point.x, self.view.center.y + point.y);
    [self updateOriginalFrame];
}

- (void)resizeWindow:(UIPanGestureRecognizer*)sender {
    if(_isMaximized) return;
    
    CGPoint point = [sender translationInView:self.view];
    [sender setTranslation:CGPointZero inView:self.view];

    CGRect frame = self.view.frame;
    frame.size.width = MAX(50, frame.size.width + point.x);
    frame.size.height = MAX(50, frame.size.height + point.y);
    self.view.frame = frame;
    [self updateOriginalFrame];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    // FIXME: how to bring view to front when touching the passthrough view?
    [self.view.superview bringSubviewToFront:self.view];
}

- (void)updateVerticalConstraints {
    [self.view layoutIfNeeded];

    BOOL bottomWindowBar = [NSUserDefaults.lcSharedDefaults boolForKey:@"LCMultitaskBottomWindowBar"];
    BOOL hideWindowBar = MultitaskDockManager.shared.isCollapsed && self.isMaximized;
    CGFloat navBarHeight = 44.0;

    self.navigationBar.alpha = hideWindowBar ? 0.0 : 1.0;
    self.navigationBar.hidden = hideWindowBar;

    // The toolbar is a floating overlay: keep app content constrained to the full window.
    CGRect navigationBarFrame = CGRectMake(
        0.0,
        bottomWindowBar ? MAX(0.0, CGRectGetHeight(self.view.bounds) - navBarHeight) : 0.0,
        CGRectGetWidth(self.view.bounds),
        navBarHeight
    );
    self.navigationBar.autoresizingMask = UIViewAutoresizingFlexibleWidth |
        (bottomWindowBar ? UIViewAutoresizingFlexibleTopMargin : UIViewAutoresizingFlexibleBottomMargin);

    [NSLayoutConstraint deactivateConstraints:self.activatedVerticalConstraints ?: @[]];
    self.activatedVerticalConstraints = @[
        [self.appSceneVC.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.appSceneVC.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ];
    [NSLayoutConstraint activateConstraints:self.activatedVerticalConstraints];

    [UIView animateWithDuration:0.3 animations:^{
        self.navigationBar.frame = navigationBarFrame;
        [self.view layoutIfNeeded];
    }];

    // Preserve the existing maximized-window safe-area behavior.
    if(self.isMaximized) {
        self.appSceneVC.shouldSkipDebounceOnce = YES;
        __weak typeof(self) weakSelf = self;
        [self.appSceneVC updateSettingsWithBlock:^(UIMutableApplicationSceneSettings *settings) {
            [weakSelf updateMaximizedFrameWithSettings:settings];
        }];
    }
}

- (UIEdgeInsets)updateMaximizedSafeAreaWithSettings:(UIMutableApplicationSceneSettings *)settings {
    BOOL bottomWindowBar = [NSUserDefaults.lcSharedDefaults boolForKey:@"LCMultitaskBottomWindowBar"];
    UIEdgeInsets safeAreaInsets = self.view.window.safeAreaInsets;
    if(self.navigationBar.hidden) {
        settings.peripheryInsets = safeAreaInsets;
        safeAreaInsets = UIEdgeInsetsZero;
    } else if(bottomWindowBar) {
        // allow the control bar to overlap the bottom safe area
        safeAreaInsets.bottom = 0;
        settings.peripheryInsets = safeAreaInsets;
        safeAreaInsets.top = safeAreaInsets.left = safeAreaInsets.right = 0;
    } else {
        settings.peripheryInsets = UIEdgeInsetsMake(0, safeAreaInsets.left, safeAreaInsets.bottom, safeAreaInsets.right);
        safeAreaInsets.bottom = safeAreaInsets.left = safeAreaInsets.right = 0;
    }
    
    // scale peripheryInsets to match the scale ratio
    settings.peripheryInsets = UIEdgeInsetsMake(settings.peripheryInsets.top/_scaleRatio, settings.peripheryInsets.left/_scaleRatio, settings.peripheryInsets.bottom/_scaleRatio, settings.peripheryInsets.right/_scaleRatio);
    if(UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad) {
        UIInterfaceOrientation currentOrientation = UIApp.statusBarOrientation;
        if(UIInterfaceOrientationIsLandscape(currentOrientation)) {
            safeAreaInsets.top = 0;
        }
        settings.safeAreaInsetsPortrait = LCUIEdgeInsetsRotateToOrientation(settings.peripheryInsets, currentOrientation);

    } else {
        settings.safeAreaInsetsPortrait = UIEdgeInsetsMake(settings.peripheryInsets.top, settings.peripheryInsets.left, settings.peripheryInsets.bottom, settings.peripheryInsets.right);
    }
    
    safeAreaInsets.bottom = 0;
    return safeAreaInsets;
}

- (void)updateMaximizedFrameWithSettings:(UIMutableApplicationSceneSettings *)settings {
    CGRect maxFrame = UIEdgeInsetsInsetRect(self.view.window.frame, [self updateMaximizedSafeAreaWithSettings:settings]);
    self.view.frame = maxFrame;
}

- (void)updateWindowedFrameWithSettings:(UIMutableApplicationSceneSettings *)settings {
    UIEdgeInsets safeAreaInsets = self.view.window.safeAreaInsets;
    CGRect maxFrame = UIEdgeInsetsInsetRect(self.view.window.frame, safeAreaInsets);
    settings.peripheryInsets = UIEdgeInsetsZero;
    settings.safeAreaInsetsPortrait = UIEdgeInsetsZero;
    
    CGRect newFrame = CGRectMake(self.originalFrame.origin.x * maxFrame.size.width, self.originalFrame.origin.y * maxFrame.size.height, self.originalFrame.size.width, self.originalFrame.size.height);
    CGPoint center = self.view.center;
    CGRect frame = CGRectZero;
    frame.size.width = MIN(newFrame.size.width, maxFrame.size.width);
    frame.size.height = MIN(newFrame.size.height, maxFrame.size.height);
    CGFloat oobOffset = MAX(30, frame.size.width - 30);
    frame.origin.x = MAX(maxFrame.origin.x - oobOffset, MIN(CGRectGetMaxX(maxFrame) - frame.size.width + oobOffset, center.x - frame.size.width / 2));
    frame.origin.y = MAX(maxFrame.origin.y, MIN(center.y - frame.size.height / 2, CGRectGetMaxY(maxFrame) - frame.size.height));
    [UIView animateWithDuration:0.3 animations:^{
        self.view.frame = frame;
    }];
}

- (void)updateOriginalFrame {
    if(_isMaximized) return;
    CGRect maxFrame = UIEdgeInsetsInsetRect(self.view.window.frame, self.view.window.safeAreaInsets);
    // save origin as normalized coordinates
    self.originalFrame = CGRectMake(self.view.frame.origin.x / maxFrame.size.width, self.view.frame.origin.y / maxFrame.size.height, self.view.frame.size.width, self.view.frame.size.height);
}

@end
