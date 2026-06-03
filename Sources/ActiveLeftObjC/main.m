#import <Cocoa/Cocoa.h>
#include <signal.h>

@interface CaffeinateController : NSObject
@property(nonatomic, strong) NSTask *task;
@property(nonatomic, copy) void (^onStateChanged)(void);
- (BOOL)isActive;
- (BOOL)startWithError:(NSError **)error;
- (void)stop;
@end

@implementation CaffeinateController

- (BOOL)isActive {
    return self.task != nil && self.task.isRunning;
}

- (BOOL)startWithError:(NSError **)error {
    [self cleanupExitedTask];

    if (self.isActive) {
        return YES;
    }

    NSTask *nextTask = [[NSTask alloc] init];
    nextTask.launchPath = @"/usr/bin/caffeinate";
    nextTask.arguments = @[@"-d", @"-w", [NSString stringWithFormat:@"%d", getpid()]];
    nextTask.standardInput = [NSFileHandle fileHandleWithNullDevice];
    nextTask.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    nextTask.standardError = [NSFileHandle fileHandleWithNullDevice];

    __weak typeof(self) weakSelf = self;
    nextTask.terminationHandler = ^(NSTask *finishedTask) {
        dispatch_async(dispatch_get_main_queue(), ^{
            CaffeinateController *strongSelf = weakSelf;

            if (strongSelf == nil || strongSelf.task != finishedTask) {
                return;
            }

            strongSelf.task = nil;

            if (strongSelf.onStateChanged != nil) {
                strongSelf.onStateChanged();
            }
        });
    };

    @try {
        [nextTask launch];
    } @catch (NSException *exception) {
        if (error != nil) {
            *error = [NSError errorWithDomain:@"ActiveLeft.Caffeinate"
                                         code:1
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: exception.reason ?: @"Unknown launch failure"
                                     }];
        }

        return NO;
    }

    self.task = nextTask;

    if (self.onStateChanged != nil) {
        self.onStateChanged();
    }

    return YES;
}

- (void)stop {
    [self cleanupExitedTask];

    NSTask *currentTask = self.task;

    if (currentTask == nil) {
        if (self.onStateChanged != nil) {
            self.onStateChanged();
        }

        return;
    }

    if (currentTask.isRunning) {
        [currentTask terminate];

        if (![self waitForTaskExit:currentTask timeout:2.0]) {
            kill(currentTask.processIdentifier, SIGKILL);
            [self waitForTaskExit:currentTask timeout:1.0];
        }
    }

    if (self.task == currentTask) {
        self.task = nil;
    }

    if (self.onStateChanged != nil) {
        self.onStateChanged();
    }
}

- (void)cleanupExitedTask {
    if (self.task != nil && !self.task.isRunning) {
        self.task = nil;
    }
}

- (BOOL)waitForTaskExit:(NSTask *)task timeout:(NSTimeInterval)timeout {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];

    while (task.isRunning && [deadline timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }

    return !task.isRunning;
}

@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) CaffeinateController *caffeinateController;
@property(nonatomic, strong) NSMutableArray *signalSources;
@property(nonatomic, strong) NSMenu *statusMenu;
@property(nonatomic, strong) NSStatusItem *statusItem;
@end

@implementation AppDelegate

- (instancetype)init {
    self = [super init];

    if (self != nil) {
        _caffeinateController = [[CaffeinateController alloc] init];
        _signalSources = [[NSMutableArray alloc] init];
    }

    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;

    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [self installSignalHandlers];

    __weak typeof(self) weakSelf = self;
    self.caffeinateController.onStateChanged = ^{
        [weakSelf renderStatus];
    };

    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];

    NSStatusBarButton *button = self.statusItem.button;
    button.target = self;
    button.action = @selector(statusItemClicked:);
    [button sendActionOn:(NSEventMaskLeftMouseUp | NSEventMaskRightMouseUp)];
    button.toolTip = @"ActiveLeft";

    [self renderStatus];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    [self.caffeinateController stop];
}

- (void)statusItemClicked:(NSStatusBarButton *)sender {
    NSEvent *event = NSApp.currentEvent;
    BOOL isContextClick = event.type == NSEventTypeRightMouseUp
        || (event.modifierFlags & NSEventModifierFlagControl) == NSEventModifierFlagControl;

    if (isContextClick) {
        [self showMenuFromButton:sender];
    } else {
        [self toggleState];
    }
}

- (void)toggleFromMenu {
    [self toggleState];
}

- (void)quit {
    [NSApp terminate:nil];
}

- (void)toggleState {
    if (self.caffeinateController.isActive) {
        [self.caffeinateController stop];
        return;
    }

    NSError *error = nil;

    if (![self.caffeinateController startWithError:&error]) {
        [self renderStatus];
        [self showStartError:error];
    }
}

- (void)renderStatus {
    NSString *state = self.caffeinateController.isActive ? @"Active" : @"Left";
    self.statusItem.button.title = [NSString stringWithFormat:@"ActiveLeft: %@", state];
    self.statusItem.button.toolTip = [NSString stringWithFormat:@"ActiveLeft is %@", state];

    NSMenuItem *toggleItem = self.statusMenu.itemArray.firstObject;

    if (toggleItem != nil) {
        toggleItem.title = self.caffeinateController.isActive ? @"Switch to Left" : @"Switch to Active";
    }
}

- (void)showMenuFromButton:(NSStatusBarButton *)button {
    [self renderStatus];

    self.statusItem.menu = self.statusMenu;
    [button performClick:nil];
    self.statusItem.menu = nil;
}

- (void)showStartError:(NSError *)error {
    [NSApp activateIgnoringOtherApps:YES];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = @"ActiveLeft could not start";
    alert.informativeText = [NSString stringWithFormat:@"Failed to run /usr/bin/caffeinate: %@",
                                                       error.localizedDescription ?: @"Unknown error"];
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (void)installSignalHandlers {
    NSArray<NSNumber *> *signals = @[@(SIGINT), @(SIGTERM), @(SIGHUP)];

    for (NSNumber *signalValue in signals) {
        int signalNumber = signalValue.intValue;
        signal(signalNumber, SIG_IGN);

        dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL,
                                                          (uintptr_t)signalNumber,
                                                          0,
                                                          dispatch_get_main_queue());

        __weak typeof(self) weakSelf = self;
        dispatch_source_set_event_handler(source, ^{
            [weakSelf.caffeinateController stop];
            exit(128 + signalNumber);
        });

        dispatch_resume(source);
        [self.signalSources addObject:source];
    }
}

- (NSMenu *)statusMenu {
    if (_statusMenu != nil) {
        return _statusMenu;
    }

    _statusMenu = [[NSMenu alloc] init];
    _statusMenu.autoenablesItems = NO;

    NSMenuItem *toggleItem = [[NSMenuItem alloc] initWithTitle:@"Switch to Active"
                                                        action:@selector(toggleFromMenu)
                                                 keyEquivalent:@""];
    toggleItem.target = self;
    [_statusMenu addItem:toggleItem];

    [_statusMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit ActiveLeft"
                                                      action:@selector(quit)
                                               keyEquivalent:@"q"];
    quitItem.target = self;
    [_statusMenu addItem:quitItem];

    return _statusMenu;
}

@end

static int runSelfTest(void) {
    @autoreleasepool {
        CaffeinateController *controller = [[CaffeinateController alloc] init];
        NSError *error = nil;

        if (![controller startWithError:&error]) {
            fprintf(stderr, "ActiveLeft self-test failed: %s\n",
                    error.localizedDescription.UTF8String ?: "Unknown error");
            return 1;
        }

        puts("ActiveLeft self-test: started caffeinate");
        sleep(3);
        [controller stop];
        puts("ActiveLeft self-test: stopped caffeinate");
    }

    return 0;
}

int main(int argc, const char *argv[]) {
    if (argc > 1 && strcmp(argv[1], "--self-test") == 0) {
        return runSelfTest();
    }

    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }

    return 0;
}
