#import <XCTest/XCTest.h>
#import "../Telephone/ActiveCallViewController.h"
#import "../Telephone/AKSIPCall.h"

@interface CallWindowCallStub : NSObject
@property AKSIPCallState state;
@property(getter=isMicrophoneMuted) BOOL microphoneMuted;
@property(getter=isOnRemoteHold) BOOL onRemoteHold;
@property(copy) NSString *sentDigits;
- (void)sendDTMFDigits:(NSString *)digits;
@end
@implementation CallWindowCallStub
- (void)sendDTMFDigits:(NSString *)digits { self.sentDigits = [(self.sentDigits ?: @"") stringByAppendingString:digits]; }
@end

@interface CallWindowControllerStub : NSObject
@property NSTimeInterval callStartTime;
@property(copy) NSString *elapsedTime;
@property(copy) NSString *status;
@property(strong) CallWindowCallStub *call;
@property(copy) NSString *contactName;
@property(copy) NSString *displayedName;
@property(strong) id endedCallViewController;
@end
@implementation CallWindowControllerStub
@end

@interface CallWindowTests : XCTestCase
@end

@implementation CallWindowTests
- (void)testDTMFReplacesContactNameWithAccumulatedDigits {
    CallWindowControllerStub *controller = [CallWindowControllerStub new];
    controller.contactName = @"Maria";
    controller.displayedName = @"Maria";
    controller.call = [CallWindowCallStub new];
    ActiveCallViewController *view = [[ActiveCallViewController alloc] initWithNibName:@"unused" callController:(id)controller];
    view.view = [NSView new];
    NSTextField *name = [NSTextField new];
    [view setValue:name forKey:@"displayedNameField"];
    [name bind:NSValueBinding toObject:controller withKeyPath:@"contactName" options:nil];
    XCTAssertEqualObjects(name.stringValue, @"Maria");
    [view activeCallView:nil didReceiveText:@"!"];
    XCTAssertEqualObjects(name.stringValue, @"Maria");
    XCTAssertNil(controller.call.sentDigits);
    [view activeCallView:nil didReceiveText:@"1"];
    XCTAssertEqualObjects(name.stringValue, @"1");
    [view activeCallView:nil didReceiveText:@"2*#"];
    XCTAssertEqualObjects(name.stringValue, @"12*#");
    XCTAssertEqualObjects(controller.call.sentDigits, @"12*#");
    XCTAssertEqualObjects(controller.contactName, @"Maria");
    [name unbind:NSValueBinding];
}

- (void)testElapsedTimeDoesNotReplaceMutedOrHeldStatus {
    CallWindowControllerStub *controller = [CallWindowControllerStub new];
    controller.call = [CallWindowCallStub new];
    controller.call.state = kAKSIPCallConfirmedState;
    ActiveCallViewController *view = [[ActiveCallViewController alloc] initWithNibName:@"unused"
                                                                     callController:(id)controller];
    for (NSString *status in @[@"mic muted", @"on hold", @"Connected"]) {
        controller.status = status;
        controller.callStartTime = NSDate.timeIntervalSinceReferenceDate - 3661.1;
        [view callTimerTick:nil];
        XCTAssertEqualObjects(controller.elapsedTime, @"01:01:01");
        XCTAssertEqualObjects(controller.status, status);
    }
    controller.callStartTime = NSDate.timeIntervalSinceReferenceDate - 61.1;
    [view callTimerTick:nil];
    XCTAssertEqualObjects(controller.elapsedTime, @"01:01");
}

- (void)testControlsFollowConnectionMuteAndRemoteHold {
    CallWindowControllerStub *controller = [CallWindowControllerStub new];
    controller.call = [CallWindowCallStub new];
    controller.callStartTime = NSDate.timeIntervalSinceReferenceDate;
    ActiveCallViewController *view = [[ActiveCallViewController alloc] initWithNibName:@"unused"
                                                                     callController:(id)controller];
    NSButton *mute = [NSButton new];
    NSButton *transfer = [NSButton new];
    [view setValue:mute forKey:@"muteButton"];
    [view setValue:transfer forKey:@"extensionTransferButton"];
    [view callTimerTick:nil];
    XCTAssertFalse(mute.enabled);
    XCTAssertFalse(transfer.enabled);
    controller.call.state = kAKSIPCallConfirmedState;
    [view callTimerTick:nil];
    XCTAssertTrue(mute.enabled);
    XCTAssertTrue(transfer.enabled);
    XCTAssertEqual(mute.state, NSControlStateValueOff);
    controller.call.microphoneMuted = YES;
    controller.call.onRemoteHold = YES;
    [view callTimerTick:nil];
    XCTAssertEqual(mute.state, NSControlStateValueOn);
    XCTAssertFalse(transfer.enabled);
    controller.call.state = kAKSIPCallDisconnectedState;
    [view callTimerTick:nil];
    XCTAssertFalse(mute.enabled);
    XCTAssertFalse(transfer.enabled);
}
@end
