/*
 * Copyright 2014 Google Inc. All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "PWBeaconsViewController.h"

#import <CoreBluetooth/CoreBluetooth.h>

#import "PWBeaconManager.h"
#import "PWBeacon.h"
#import "PWBeaconCell.h"
#import "PWGradientView.h"
#import "PWMetadataRequest.h"
#import "PWPlaceholderView.h"
#import "PWSettingsViewController.h"

@interface PWBeaconsViewController () <
    UITableViewDataSource, UITableViewDelegate, UITextViewDelegate,
    CBCentralManagerDelegate, PWMetadataRequestDelegate>

@end

@implementation PWBeaconsViewController {
  UITableView *_tableView;
  BOOL _canShowPlaceholder;
  BOOL _shouldShowLogs;
  BOOL _showPlaceholder;
  BOOL _firstUpdate;
  NSMutableArray *_beacons;
  BOOL _scheduledUpdated;
  PWPlaceholderView *_placeholderView;
  PWGradientView *_gradientView;
  CBCentralManager *_centralManager;
  BOOL _showDemoBeacons;
  UIButton *_showDemoBeaconsButton;
  UIActivityIndicatorView *_activityView;
  PWMetadataRequest *_demoBeaconsRequest;
  NSArray *_demoBeacons;
}

- (instancetype)initWithNibName:(NSString *)nibNameOrNil
                         bundle:(NSBundle *)nibBundleOrNil {
  self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
  _firstUpdate = YES;
  [[PWBeaconManager sharedManager]
      registerChangeBlock:^{ [self _updateViewAfterDelay]; }];

  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(_applicationDidResignActive)
             name:UIApplicationWillResignActiveNotification
           object:[UIApplication sharedApplication]];

  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
  [super viewDidLoad];

  CGRect bounds = [[self view] bounds];
  _tableView =
      [[UITableView alloc] initWithFrame:bounds style:UITableViewStylePlain];
  [_tableView setAutoresizingMask:UIViewAutoresizingFlexibleHeight |
                                  UIViewAutoresizingFlexibleWidth];
  [_tableView setDelegate:self];
  [_tableView setDataSource:self];
  [_tableView setRowHeight:100];
  [_tableView setSeparatorStyle:UITableViewCellSeparatorStyleNone];
  [_tableView setScrollsToTop:YES];
  [self viewWillTransitionToSize:bounds.size withTransitionCoordinator:nil];
  [[self view] addSubview:_tableView];

  _placeholderView = [[PWPlaceholderView alloc] initWithFrame:CGRectZero];
  [self performSelector:@selector(_enablePlaceholder)
             withObject:nil
             afterDelay:2];

  _showDemoBeaconsButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
  [_showDemoBeaconsButton setTitle:@"Show Example Beacons"
                          forState:UIControlStateNormal];
  [_showDemoBeaconsButton
      setBackgroundColor:[UIColor colorWithWhite:1.0 alpha:.9]];
  [_showDemoBeaconsButton
      setAutoresizingMask:UIViewAutoresizingFlexibleLeftMargin |
                          UIViewAutoresizingFlexibleRightMargin |
                          UIViewAutoresizingFlexibleTopMargin];
  [_showDemoBeaconsButton addTarget:self
                             action:@selector(_showDemoBeaconsButtonPressed)
                   forControlEvents:UIControlEventTouchUpInside];
  [_showDemoBeaconsButton setAlpha:0.0];
  [_placeholderView addSubview:_showDemoBeaconsButton];
  _activityView = [[UIActivityIndicatorView alloc]
      initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
  [_placeholderView addSubview:_activityView];

  CGRect frame = bounds;
  frame.size.height = 25;
  _gradientView = [[PWGradientView alloc] initWithFrame:frame];
  [_gradientView setAlpha:0.0];
  [[self view] addSubview:_gradientView];

  UIButton *button = [UIButton buttonWithType:UIButtonTypeRoundedRect];
  [[button layer]
      setBorderColor:[[UIColor colorWithWhite:0.95 alpha:1.0] CGColor]];
  [[button layer] setBorderWidth:1.0];
  [[button layer] setCornerRadius:5.0];
  [button setAutoresizingMask:UIViewAutoresizingFlexibleLeftMargin |
                              UIViewAutoresizingFlexibleTopMargin];
  [button setBackgroundColor:[UIColor colorWithWhite:1.0 alpha:.9]];
  [button setImage:[UIImage imageNamed:@"gear"] forState:UIControlStateNormal];
  [button setFrame:CGRectMake(bounds.size.width - 45, bounds.size.height - 45,
                              40, 40)];
  [button addTarget:self
                action:@selector(_settingsPressed)
      forControlEvents:UIControlEventTouchUpInside];
  [[self view] addSubview:button];

  _centralManager =
      [[CBCentralManager alloc] initWithDelegate:self queue:nil options:nil];

  [self _reloadData];
}

- (void)viewWillTransitionToSize:(CGSize)size
       withTransitionCoordinator:
           (id<UIViewControllerTransitionCoordinator>)coordinator {
  [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
  if (size.width > size.height) {
    [_tableView setContentInset:UIEdgeInsetsMake(0, 0, 0, 0)];
  } else {
    [_tableView setContentInset:UIEdgeInsetsMake(20, 0, 0, 0)];
  }
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
  [self _updatedPlaceholderViewState];
}

- (void)_applicationDidResignActive {
  if (!_showDemoBeacons) {
    return;
  }

  // Hide demo beacons
  _showDemoBeacons = NO;
  _demoBeacons = nil;
  [self _updateBeaconsNow];
}

- (void)_showDemoBeaconsButtonPressed {
  if (_showDemoBeacons) {
    return;
  }
  _showDemoBeacons = YES;
  _demoBeacons = nil;
  _demoBeaconsRequest = [[PWMetadataRequest alloc] init];
  [_demoBeaconsRequest setDemo:YES];
  [_demoBeaconsRequest setDelegate:self];
  [_demoBeaconsRequest start];

  [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
  [_activityView startAnimating];

  [self _reloadData];
}

- (void)_updatedPlaceholderViewState {
  BOOL enabled = ([_centralManager state] == CBCentralManagerStatePoweredOn);
  [_placeholderView setBluetoothEnabled:enabled];
  if (enabled) {
    [_placeholderView setLabel:@"No beacons detected"];
  } else {
    [_placeholderView setLabel:@"Please turn on bluetooth in order to start "
                      @"scanning for beacons."];
  }
}

// Settings button handler.
- (void)_settingsPressed {
  PWSettingsViewController *settingsViewController =
      [[PWSettingsViewController alloc] initWithNibName:nil bundle:nil];
  UINavigationController *navigationController = [[UINavigationController alloc]
      initWithRootViewController:settingsViewController];
  [self presentViewController:navigationController animated:YES completion:nil];
}

- (void)_updateViewAfterDelay {
  if (_scheduledUpdated) {
    return;
  }

  _scheduledUpdated = YES;
  // The first update will be scheduled after 1 sec, the subsequent updates will
  // be scheduled after 5 sec. If the list was empty, an update will also be
  // scheduled after 1 sec.
  NSTimeInterval delay = 5;
  if (_firstUpdate || [_beacons count] == 0) {
    delay = 1;
  }
  [self performSelector:@selector(_updateBeaconsNow)
             withObject:nil
             afterDelay:delay];
  _firstUpdate = NO;
}

- (void)_updateBeaconsNow {
  [NSObject cancelPreviousPerformRequestsWithTarget:self
                                           selector:@selector(_updateBeaconsNow)
                                             object:nil];
  _scheduledUpdated = NO;
  _beacons = [[[PWBeaconManager sharedManager] beacons] mutableCopy];
  [_beacons addObjectsFromArray:_demoBeacons];
  [self _sort];
  [self _reloadData];

  [[PWBeaconManager sharedManager] serializeBeacons:_beacons];
}

// Sort results by RSSI value.
- (void)_sort {
  [_beacons sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
      PWBeacon *beacon1 = obj1;
      PWBeacon *beacon2 = obj2;
      NSInteger regionDifference = (NSInteger)[[beacon1 uriBeacon] region] -
                                   (NSInteger)[[beacon2 uriBeacon] region];
      if (regionDifference > 0) {
        return NSOrderedDescending;
      } else if (regionDifference < 0) {
        return NSOrderedAscending;
      } else {
        return [[beacon1 title] caseInsensitiveCompare:[beacon2 title]];
      }
  }];
}

- (void)_reloadData {
  if ([_beacons count] == 0) {
    _showPlaceholder = YES;
    [_placeholderView start];
  } else {
    _showPlaceholder = NO;
    [_placeholderView stop];
  }
  [_tableView reloadData];
}

- (void)_enablePlaceholder {
  _canShowPlaceholder = YES;
  [_placeholderView setShowLabel:YES];
  [UIView animateWithDuration:0.25
                   animations:^{ [_showDemoBeaconsButton setAlpha:1.0]; }];
  [self _reloadData];

  CGRect bounds = [_placeholderView bounds];
  CGRect frame = CGRectMake((bounds.size.width - 200) / 2,
                            bounds.size.height - 100, 200, 40);
  frame = CGRectIntegral(frame);
  [_showDemoBeaconsButton setFrame:frame];
  [_activityView
      setCenter:CGPointMake(bounds.size.width / 2, bounds.size.height - 50)];
}

- (BOOL)canBecomeFirstResponder {
  return YES;
}

#pragma mark UITableView data source

- (CGFloat)tableView:(UITableView *)tableView
    heightForHeaderInSection:(NSInteger)section {
  return _showPlaceholder ? [UIScreen mainScreen].bounds.size.height : 0;
}

- (UIView *)tableView:(UITableView *)tableView
    viewForHeaderInSection:(NSInteger)section {
  return _showPlaceholder ? _placeholderView : nil;
}

- (NSInteger)tableView:(UITableView *)tableView
    numberOfRowsInSection:(NSInteger)section {
  return [_beacons count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  PWBeaconCell *cell = [tableView dequeueReusableCellWithIdentifier:@"device"];
  if (cell == nil) {
    cell = [[PWBeaconCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                               reuseIdentifier:@"device"];
  }
  PWBeacon *beacon = [_beacons objectAtIndex:[indexPath row]];
  [cell setBeacon:beacon];
  return cell;
}

- (CGFloat)tableView:(UITableView *)tableView
    heightForRowAtIndexPath:(NSIndexPath *)indexPath {
  PWBeacon *device = [_beacons objectAtIndex:[indexPath row]];
  return [PWBeaconCell heightForDevice:device tableView:_tableView];
}

- (void)tableView:(UITableView *)tableView
    didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  PWBeacon *beacon = [_beacons objectAtIndex:[indexPath row]];
  NSURL *url = [beacon URL];
  [[UIApplication sharedApplication] openURL:url];

  [_tableView deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma mark scroll view delegate method

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
  [UIView
      animateWithDuration:0.25
               animations:^{
                   [_gradientView
                       setAlpha:[scrollView contentOffset].y > 0 ? 1.0 : 0.0];
               }];
}

#pragma mark metadata request response

- (void)metadataRequest_done:(PWMetadataRequest *)request {
  if ([request error] != nil) {
    UIAlertView *alertView = [[UIAlertView alloc]
            initWithTitle:@"Could not connect to the server"
                  message:@"Please check whether your internet connection is "
                  @"working properly."
                 delegate:nil
        cancelButtonTitle:@"OK"
        otherButtonTitles:nil];
    [alertView show];
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
    [_activityView stopAnimating];
    _showDemoBeacons = NO;
    return;
  }

  [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
  [_activityView stopAnimating];
  _demoBeacons = [_demoBeaconsRequest results];
  _demoBeaconsRequest = nil;
  [self _updateBeaconsNow];
}

@end
