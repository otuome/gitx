//
//  PBGitCommitController.h
//  GitX
//
//  Created by Pieter de Bie on 19-09-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//
//	Modified by Hasan Otuome on 12-04-09:
//	- added Unfuddle toolbar item
//
//	Modified by Hasan Otuome on 04-12-09:
//	- added github toolbar item 

#import <Cocoa/Cocoa.h>
#import "PBViewController.h"

@class PBGitIndexController, PBIconAndTextCell, PBWebChangesController, PBGitIndex;

@interface PBGitCommitController : PBViewController {
	// This might have to transfer over to the PBGitRepository
	// object sometime
	PBGitIndex *index;
	
	IBOutlet NSTextView *commitMessageView;
	IBOutlet NSArrayController *unstagedFilesController;
	IBOutlet NSArrayController *cachedFilesController;

	IBOutlet PBGitIndexController *indexController;
	IBOutlet PBWebChangesController *webController;

	NSString *status;
	BOOL busy;
	
	NSString *unfuddleTaskResults;
	NSString *githubTaskResults;
}

@property(copy) NSString *status;
@property(readonly) PBGitIndex *index;
@property(assign) BOOL busy;
@property (nonatomic, retain) NSString *unfuddleTaskResults;
@property (nonatomic, retain) NSString *githubTaskResults;

- (IBAction) refresh:(id) sender;
- (IBAction) commit:(id) sender;
- (IBAction)signOff:(id)sender;
- (IBAction) pushToUnfuddle:(id)sender;
- (IBAction) pushToGithub:(id)sender;
@end
