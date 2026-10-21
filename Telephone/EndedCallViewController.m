//
//  EndedCallViewController.m
//  Telephone
//
//  Copyright © 2008-2016 Alexey Kuznetsov
//  Copyright © 2016-2022 64 Characters
//
//  Telephone is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Telephone is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//

#import "EndedCallViewController.h"

#import "CallController.h"


@interface EndedCallViewController ()
@property(nonatomic, weak) IBOutlet NSTextField *numberField;
@property(nonatomic, weak) IBOutlet NSTextField *durationField;
@end

@implementation EndedCallViewController

- (instancetype)initWithNibName:(NSString *)nibName callController:(CallController *)callController {
    self = [super initWithNibName:nibName bundle:nil];
    
    if (self != nil) {
        [self setCallController:callController];
    }
    return self;
}

- (instancetype)init {
    NSString *reason = @"Initialize EndedCallViewController with initWithCallController:";
    @throw [NSException exceptionWithName:@"AKBadInitCall" reason:reason userInfo:nil];
    return nil;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if (self.numberField != nil) {
        self.redialButton.title = NSLocalizedString(@"Call Again", @"Redial ended call.");
    }
}

- (void)removeObservations {
    [[self displayedNameField] unbind:NSValueBinding];
    [[self statusField] unbind:NSValueBinding];
    [self.numberField unbind:NSValueBinding];
    [self.durationField unbind:NSValueBinding];
}

- (IBAction)redial:(id)sender {
    [[self callController] redial];
}

- (void)enableRedialButtonTick:(NSTimer *)theTimer {
    [[self redialButton] setEnabled:YES];
}

@end
