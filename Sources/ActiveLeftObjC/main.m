#import <Cocoa/Cocoa.h>
#include <signal.h>

@interface CaffeinateController : NSObject
@property(nonatomic, strong) NSTask *systemTask;
@property(nonatomic, strong) NSTask *displayTask;
@property(nonatomic, copy) void (^onStateChanged)(void);
- (BOOL)isActive;
- (BOOL)startSystemAwakeWithError:(NSError **)error;
- (BOOL)startDisplayAwakeWithError:(NSError **)error;
- (void)stopDisplayAwake;
- (void)stopAll;
@end

@implementation CaffeinateController

- (BOOL)isActive {
    return self.displayTask != nil && self.displayTask.isRunning;
}

- (BOOL)startSystemAwakeWithError:(NSError **)error {
    [self cleanupExitedTask];

    if (self.systemTask != nil && self.systemTask.isRunning) {
        return YES;
    }

    self.systemTask = [self startCaffeinateWithArguments:@[@"-i", @"-s", @"-w", [NSString stringWithFormat:@"%d", getpid()]]
                                                   error:error];

    return self.systemTask != nil;
}

- (BOOL)startDisplayAwakeWithError:(NSError **)error {
    if (![self startSystemAwakeWithError:error]) {
        return NO;
    }

    [self cleanupExitedTask];

    if (self.displayTask != nil && self.displayTask.isRunning) {
        return YES;
    }

    self.displayTask = [self startCaffeinateWithArguments:@[@"-d", @"-w", [NSString stringWithFormat:@"%d", getpid()]]
                                                    error:error];

    if (self.displayTask != nil && self.onStateChanged != nil) {
        self.onStateChanged();
    }

    return self.displayTask != nil;
}

- (NSTask *)startCaffeinateWithArguments:(NSArray<NSString *> *)arguments error:(NSError **)error {
    NSTask *nextTask = [[NSTask alloc] init];
    nextTask.launchPath = @"/usr/bin/caffeinate";
    nextTask.arguments = arguments;
    nextTask.standardInput = [NSFileHandle fileHandleWithNullDevice];
    nextTask.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    nextTask.standardError = [NSFileHandle fileHandleWithNullDevice];

    __weak typeof(self) weakSelf = self;
    nextTask.terminationHandler = ^(NSTask *finishedTask) {
        dispatch_async(dispatch_get_main_queue(), ^{
            CaffeinateController *strongSelf = weakSelf;

            if (strongSelf == nil) {
                return;
            }

            if (strongSelf.displayTask == finishedTask) {
                strongSelf.displayTask = nil;

                if (strongSelf.onStateChanged != nil) {
                    strongSelf.onStateChanged();
                }
            }

            if (strongSelf.systemTask == finishedTask) {
                strongSelf.systemTask = nil;
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

        return nil;
    }

    return nextTask;
}

- (void)stopDisplayAwake {
    [self cleanupExitedTask];

    NSTask *currentTask = self.displayTask;

    if (currentTask == nil) {
        if (self.onStateChanged != nil) {
            self.onStateChanged();
        }

        return;
    }

    [self stopTask:currentTask];

    if (self.displayTask == currentTask) {
        self.displayTask = nil;
    }

    if (self.onStateChanged != nil) {
        self.onStateChanged();
    }
}

- (void)stopAll {
    [self cleanupExitedTask];

    if (self.displayTask != nil) {
        [self stopTask:self.displayTask];
    }

    if (self.systemTask != nil) {
        [self stopTask:self.systemTask];
    }

    self.displayTask = nil;
    self.systemTask = nil;

    if (self.onStateChanged != nil) {
        self.onStateChanged();
    }
}

- (void)stopTask:(NSTask *)task {
    if (task.isRunning) {
        [task terminate];

        if (![self waitForTaskExit:task timeout:2.0]) {
            kill(task.processIdentifier, SIGKILL);
            [self waitForTaskExit:task timeout:1.0];
        }
    }
}

- (void)cleanupExitedTask {
    if (self.systemTask != nil && !self.systemTask.isRunning) {
        self.systemTask = nil;
    }

    if (self.displayTask != nil && !self.displayTask.isRunning) {
        self.displayTask = nil;
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

    NSError *error = nil;

    if (![self.caffeinateController startSystemAwakeWithError:&error]) {
        [self showStartError:error];
    }

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
    [self.caffeinateController stopAll];
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
        [self.caffeinateController stopDisplayAwake];
        return;
    }

    NSError *error = nil;

    if (![self.caffeinateController startDisplayAwakeWithError:&error]) {
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
            [weakSelf.caffeinateController stopAll];
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

        if (![controller startSystemAwakeWithError:&error]) {
            fprintf(stderr, "ActiveLeft self-test failed: %s\n",
                    error.localizedDescription.UTF8String ?: "Unknown error");
            return 1;
        }

        puts("ActiveLeft self-test: started system caffeinate");

        if (![controller startDisplayAwakeWithError:&error]) {
            fprintf(stderr, "ActiveLeft self-test failed: %s\n",
                    error.localizedDescription.UTF8String ?: "Unknown error");
            return 1;
        }

        puts("ActiveLeft self-test: started display caffeinate");
        sleep(3);
        [controller stopDisplayAwake];
        puts("ActiveLeft self-test: stopped display caffeinate");
        sleep(2);
        [controller stopAll];
        puts("ActiveLeft self-test: stopped system caffeinate");
    }

    return 0;
}

static BOOL anotherInstanceIsRunning(void) {
    NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier;

    if (bundleIdentifier.length == 0) {
        return NO;
    }

    pid_t currentPID = getpid();

    for (NSRunningApplication *application in [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleIdentifier]) {
        if (application.processIdentifier == currentPID || application.isTerminated) {
            continue;
        }

        [application activateWithOptions:0];
        return YES;
    }

    return NO;
}

int main(int argc, const char *argv[]) {
    if (argc > 1 && strcmp(argv[1], "--self-test") == 0) {
        return runSelfTest();
    }

    if (anotherInstanceIsRunning()) {
        return 0;
    }

    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }

    return 0;
}
