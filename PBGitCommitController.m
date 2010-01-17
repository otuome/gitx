//
//  PBGitCommitController.m
//  GitX
//
//  Created by Pieter de Bie on 19-09-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//
//	Modified by Hasan Otuome on 12-04-09:
//	- added Unfuddle integration
//
//	Modified by Hasan Otuome on 04-12-09:
//	- added github toolbar item 
//
//	Modified by Hasan Otuome on 16-01-10:
//	- removed Unfuddle and github buttons
//	- added remote selector 

#import "PBGitCommitController.h"
#import "NSFileHandleExt.h"
#import "PBChangedFile.h"
#import "PBWebChangesController.h"
#import "PBGitIndex.h"

#define ASSEMBLA	= "Assembla"
#define GITHUB		= "GitHub"
#define RH			= "RepositoryHosting"
#define UNFUDDLE	= "Unfuddle"

@interface PBGitCommitController ()
- (void)refreshFinished:(NSNotification *)notification;
- (void)commitStatusUpdated:(NSNotification *)notification;
- (void)commitFinished:(NSNotification *)notification;
- (void)commitFailed:(NSNotification *)notification;
- (void)amendCommit:(NSNotification *)notification;
- (void)indexChanged:(NSNotification *)notification;
- (void)indexOperationFailed:(NSNotification *)notification;
@end

@implementation PBGitCommitController

@synthesize status, index, busy, selectedRemote, unfuddleTaskResults, githubTaskResults, repositoryHostingTaskResults;

- (id)initWithRepository:(PBGitRepository *)theRepository superController:(PBGitWindowController *)controller
{
	if (!(self = [super initWithRepository:theRepository superController:controller]))
		return nil;

	index = [[PBGitIndex alloc] initWithRepository:theRepository workingDirectory:[NSURL fileURLWithPath:[theRepository workingDirectory]]];
	[index refresh];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshFinished:) name:PBGitIndexFinishedIndexRefresh object:index];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(commitStatusUpdated:) name:PBGitIndexCommitStatus object:index];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(commitFinished:) name:PBGitIndexFinishedCommit object:index];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(commitFailed:) name:PBGitIndexCommitFailed object:index];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(amendCommit:) name:PBGitIndexAmendMessageAvailable object:index];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(indexChanged:) name:PBGitIndexIndexUpdated object:index];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(indexOperationFailed:) name:PBGitIndexOperationFailed object:index];

	return self;
}

- (void)awakeFromNib
{
	[super awakeFromNib];

	[commitMessageView setTypingAttributes:[NSDictionary dictionaryWithObject:[NSFont fontWithName:@"Monaco" size:12.0] forKey:NSFontAttributeName]];
	
	[unstagedFilesController setFilterPredicate:[NSPredicate predicateWithFormat:@"hasUnstagedChanges == 1"]];
	[cachedFilesController setFilterPredicate:[NSPredicate predicateWithFormat:@"hasStagedChanges == 1"]];
	
	[unstagedFilesController setSortDescriptors:[NSArray arrayWithObjects:
		[[NSSortDescriptor alloc] initWithKey:@"status" ascending:false],
		[[NSSortDescriptor alloc] initWithKey:@"path" ascending:true], nil]];
	[cachedFilesController setSortDescriptors:[NSArray arrayWithObject:
		[[NSSortDescriptor alloc] initWithKey:@"path" ascending:true]]];

	[cachedFilesController setAutomaticallyRearrangesObjects:NO];
	[unstagedFilesController setAutomaticallyRearrangesObjects:NO];
}

- (void) removeView
{
	[webController closeView];
	[super finalize];
}

- (NSResponder *)firstResponder;
{
	return commitMessageView;
}

- (IBAction)signOff:(id)sender
{
	if (![repository.config valueForKeyPath:@"user.name"] || ![repository.config valueForKeyPath:@"user.email"])
		return [[repository windowController] showMessageSheet:@"User's name not set" infoText:@"Signing off a commit requires setting user.name and user.email in your git config"];
	NSString *SOBline = [NSString stringWithFormat:@"Signed-off-by: %@ <%@>",
				[repository.config valueForKeyPath:@"user.name"],
				[repository.config valueForKeyPath:@"user.email"]];

	if([commitMessageView.string rangeOfString:SOBline].location == NSNotFound) {
		NSArray *selectedRanges = [commitMessageView selectedRanges];
		commitMessageView.string = [NSString stringWithFormat:@"%@\n\n%@",
				commitMessageView.string, SOBline];
		[commitMessageView setSelectedRanges: selectedRanges];
	}
}

- (void) refresh:(id) sender
{
	self.busy = YES;
	self.status = @"Refreshing index…";
	[index refresh];

	// Reload refs (in case HEAD changed)
	[repository reloadRefs];
}

- (void) updateView
{
	[self refresh:nil];
}

- (IBAction) commit:(id) sender
{
	if ([[NSFileManager defaultManager] fileExistsAtPath:[repository.fileURL.path stringByAppendingPathComponent:@"MERGE_HEAD"]]) {
		[[repository windowController] showMessageSheet:@"Cannot commit merges" infoText:@"GitX cannot commit merges yet. Please commit your changes from the command line."];
		return;
	}

	if ([[cachedFilesController arrangedObjects] count] == 0) {
		[[repository windowController] showMessageSheet:@"No changes to commit" infoText:@"You must first stage some changes before committing"];
		return;
	}		
	
	NSString *commitMessage = [commitMessageView string];
	if ([commitMessage length] < 3) {
		[[repository windowController] showMessageSheet:@"Commitmessage missing" infoText:@"Please enter a commit message before committing"];
		return;
	}

	[cachedFilesController setSelectionIndexes:[NSIndexSet indexSet]];
	[unstagedFilesController setSelectionIndexes:[NSIndexSet indexSet]];

	self.busy = YES;
	[commitMessageView setEditable:NO];

	[index commitWithMessage:commitMessage];
}


# pragma mark PBGitIndex Notification handling
- (void)refreshFinished:(NSNotification *)notification
{
	self.busy = NO;
	self.status = @"Index refresh finished";
}

- (void)commitStatusUpdated:(NSNotification *)notification
{
	self.status = [[notification userInfo] objectForKey:@"description"];
}

- (void)commitFinished:(NSNotification *)notification
{
	[commitMessageView setEditable:YES];
	[commitMessageView setString:@""];
	[webController setStateMessage:[NSString stringWithFormat:[[notification userInfo] objectForKey:@"description"]]];
}	

- (void)commitFailed:(NSNotification *)notification
{
	self.busy = NO;
	NSString *reason = [[notification userInfo] objectForKey:@"description"];
	self.status = [@"Commit failed: " stringByAppendingString:reason];
	[commitMessageView setEditable:YES];
	[[repository windowController] showMessageSheet:@"Commit failed" infoText:reason];
}

- (void)amendCommit:(NSNotification *)notification
{
	// Replace commit message with the old one if it's less than 3 characters long.
	// This is just a random number.
	if ([[commitMessageView string] length] > 3)
		return;
	
	NSString *message = [[notification userInfo] objectForKey:@"message"];
	commitMessageView.string = message;
}

- (void)indexChanged:(NSNotification *)notification
{
	[cachedFilesController rearrangeObjects];
	[unstagedFilesController rearrangeObjects];
}

- (void)indexOperationFailed:(NSNotification *)notification
{
	[[repository windowController] showMessageSheet:@"Index operation failed" infoText:[[notification userInfo] objectForKey:@"description"]];
}
//================================================ REMOTE PUSH INTEGRATION =================================================\\
//
// These methods govern pushing local commits 
// to a remote upstream repository hosted by X host.
- (void) updateSelectedRemote:(id)sender
{
	selectedRemote = [[sender selectedItem] title];
}
- (void) pushToSelectedRemote:(id)sender
{
	if (selectedRemote == nil) 
	{
		selectedRemote = [[remoteSelector selectedItem] title];
	}
	
	if ([selectedRemote isEqualToString: @"GitHub"])[ self doPushToGithub ];
	if ([selectedRemote isEqualToString: @"RepositoryHosting"]) [ self doPushToRepositoryHosting ];
	if ([selectedRemote isEqualToString: @"Unfuddle"]) [ self doPushToUnfuddle ];
}
//================================================ UNFUDDLE INTEGRATION =================================================\\
//
// This method is responsible for pushing local commits 
// to a remote upstream repository hosted by Unfuddle.
// 
// This functionality becomes available once a user 
// adds the "Push to Unfuddle" button to their toolbar.
// 
// This method should only be called if there are local 
// commits ready for remote push.
//
- (void) pushToUnfuddle:(id)sender
{
	NSString *currentWorkingDir = [ [NSString alloc] initWithFormat: @"%@", [repository workingDirectory] ];
	
	NSTask *uf_git = [ [[NSTask alloc] init] autorelease ];
	NSString *pathToGit = [ [NSString alloc] initWithFormat: @"/usr/local/git/bin/git" ];
	NSMutableArray *args = [ NSMutableArray array ];
	NSNotificationCenter *nc = [ NSNotificationCenter defaultCenter ];
	
	[ args addObject: @"push" ];
	[ args addObject: @"unfuddle" ];
	[ args addObject: @"master" ];
//	[ args addObject: @"push unfuddle master" ]; // used this to simulate failure!!
	
	[ nc addObserver: self selector: @selector(pushToUnfuddleComplete:) name: NSTaskDidTerminateNotification object: uf_git ];
	
	[ uf_git setCurrentDirectoryPath: currentWorkingDir ];
	[ uf_git setLaunchPath: pathToGit ];
	[ uf_git setArguments: args ];
	[ uf_git launch ];
	
	self.busy++;
	self.status = @"Pushing commits to Unfuddle";
}

- (void) doPushToUnfuddle
{
	NSString *currentWorkingDir = [ [NSString alloc] initWithFormat: @"%@", [repository workingDirectory] ];
	
	NSTask *uf_git = [ [[NSTask alloc] init] autorelease ];
	NSString *pathToGit = [ [NSString alloc] initWithFormat: @"/usr/local/git/bin/git" ];
	NSMutableArray *args = [ NSMutableArray array ];
	NSNotificationCenter *nc = [ NSNotificationCenter defaultCenter ];
	
	[ args addObject: @"push" ];
	[ args addObject: @"unfuddle" ];
	[ args addObject: @"master" ];
	
	[ nc addObserver: self selector: @selector(pushToUnfuddleComplete:) name: NSTaskDidTerminateNotification object: uf_git ];
	
	[ uf_git setCurrentDirectoryPath: currentWorkingDir ];
	[ uf_git setLaunchPath: pathToGit ];
	[ uf_git setArguments: args ];
	[ uf_git launch ];
	
	self.busy++;
	self.status = @"Pushing commits to Unfuddle";
}

//
// This method is responsible for handling the notification sent 
// by the NSTask created by the pushToUnfuddle() method.
// 
// Ideally, the user should be notified of the status either by 
// a collapsible property sheet/pane or an alert.
//
- (void) pushToUnfuddleComplete:( NSNotification * ) notification
{
	int GIT_SUCCESS_VALUE = 0;
	
	int gitTaskStatus = [ [notification object] terminationStatus ];
	
	if (gitTaskStatus == GIT_SUCCESS_VALUE)
	{
		unfuddleTaskResults = @"Pushed commits to Unfuddle successfully!";
		NSBeginInformationalAlertSheet( @"Unfuddle Status", nil, nil, nil, [ commitMessageView window ], self, nil, nil, NULL, unfuddleTaskResults);
	}
	else
	{
		unfuddleTaskResults = @"Push to Unfuddle failed unexpectedly. Please try again.";
		NSBeginCriticalAlertSheet( @"Unfuddle Status", nil, nil, nil, [ commitMessageView window ], self, nil, nil, NULL, unfuddleTaskResults);
	}
	
	self.busy--;
	self.status = @"Ready";
}

//================================================ GITHUB INTEGRATION =================================================\\
//
// This method is responsible for pushing local commits 
// to a remote upstream repository hosted by github.
// 
// This functionality becomes available once a user 
// adds the "Push to github" button to their toolbar.
// 
// This method should only be called if there are local 
// commits ready for remote push. Furthermore, users should 
// be warned that their commits will be pushed to the master. 
// Will change once ability is added to set push "destination".
//
- (void) pushToGithub:(id)sender
{
	NSString *currentWorkingDir = [ [NSString alloc] initWithFormat: @"%@", [repository workingDirectory] ];
	
	NSTask *github_git = [ [[NSTask alloc] init] autorelease ];
	NSString *pathToGit = [ [NSString alloc] initWithFormat: @"/usr/local/git/bin/git" ];
	NSMutableArray *args = [ NSMutableArray array ];
	NSNotificationCenter *nc = [ NSNotificationCenter defaultCenter ];
	
	[ args addObject: @"push" ];
	[ args addObject: @"origin" ];
	[ args addObject: @"master" ];
	//	[ args addObject: @"push origin master" ]; // used this to simulate failure!!
	
	[ nc addObserver: self selector: @selector(pushToGithubComplete:) name: NSTaskDidTerminateNotification object: github_git ];
	
	[ github_git setCurrentDirectoryPath: currentWorkingDir ];
	[ github_git setLaunchPath: pathToGit ];
	[ github_git setArguments: args ];
	[ github_git launch ];
	
	self.busy++;
	self.status = @"Pushing commits to GitHub";
}

- (void) doPushToGithub
{
	NSString *currentWorkingDir = [ [NSString alloc] initWithFormat: @"%@", [repository workingDirectory] ];
	
	NSTask *github_git = [ [[NSTask alloc] init] autorelease ];
	NSString *pathToGit = [ [NSString alloc] initWithFormat: @"/usr/local/git/bin/git" ];
	NSMutableArray *args = [ NSMutableArray array ];
	NSNotificationCenter *nc = [ NSNotificationCenter defaultCenter ];
	
	[ args addObject: @"push" ];
	[ args addObject: @"origin" ];
	[ args addObject: @"master" ];
	//	[ args addObject: @"push origin master" ]; // used this to simulate failure!!
	
	[ nc addObserver: self selector: @selector(pushToGithubComplete:) name: NSTaskDidTerminateNotification object: github_git ];
	
	[ github_git setCurrentDirectoryPath: currentWorkingDir ];
	[ github_git setLaunchPath: pathToGit ];
	[ github_git setArguments: args ];
	[ github_git launch ];
	
	self.busy++;
	self.status = @"Pushing commits to GitHub";
}

//
// This method is responsible for handling the notification sent 
// by the NSTask created by the pushToGithub() method.
// 
// Ideally, the user should be notified of the status either by 
// a collapsible property sheet/pane or an alert.
//
- (void) pushToGithubComplete:( NSNotification * ) notification
{
	int GIT_SUCCESS_VALUE = 0;
	
	int gitTaskStatus = [ [notification object] terminationStatus ];
	
	if (gitTaskStatus == GIT_SUCCESS_VALUE)
	{
		githubTaskResults = @"Pushed commits to GitHub successfully!";
		NSBeginInformationalAlertSheet( @"GitHub Status", nil, nil, nil, [ commitMessageView window ], self, nil, nil, NULL, githubTaskResults);
	}
	else
	{
		githubTaskResults = @"Push to GitHub failed unexpectedly. Please try again.";
		NSBeginCriticalAlertSheet( @"GitHub Status", nil, nil, nil, [ commitMessageView window ], self, nil, nil, NULL, githubTaskResults);
	}
	
	self.busy--;
	self.status = @"Ready";
}

//================================================ REPOSITORY HOSTING INTEGRATION =================================================\\
//
// This method is responsible for pushing local commits 
// to a remote upstream repository hosted by repositoryhosting.com.
// 
// This functionality becomes available once a user 
// adds the "Push to RH" button to their toolbar.
// 
// This method should only be called if there are local 
// commits ready for remote push. Furthermore, users should 
// be warned that their commits will be pushed to the master. 
// Will change once ability is added to set push "destination".
//
- (void) pushToRepositoryHosting:(id)sender
{
	NSString *currentWorkingDir = [ [NSString alloc] initWithFormat: @"%@", [repository workingDirectory] ];
	
	NSTask *rh_git = [ [[NSTask alloc] init] autorelease ];
	NSString *pathToGit = [ [NSString alloc] initWithFormat: @"/usr/local/git/bin/git" ];
	NSMutableArray *args = [ NSMutableArray array ];
	NSNotificationCenter *nc = [ NSNotificationCenter defaultCenter ];
	
	[ args addObject: @"push" ];
	[ args addObject: @"origin" ];
	[ args addObject: @"master" ];
	//	[ args addObject: @"push origin master" ]; // used this to simulate failure!!
	
	[ nc addObserver: self selector: @selector(pushToRepositoryHostingComplete:) name: NSTaskDidTerminateNotification object: rh_git ];
	
	[ rh_git setCurrentDirectoryPath: currentWorkingDir ];
	[ rh_git setLaunchPath: pathToGit ];
	[ rh_git setArguments: args ];
	[ rh_git launch ];
	
	self.busy++;
	self.status = @"Pushing commits to RepositoryHosting";
}

- (void) doPushToRepositoryHosting
{
	NSString *currentWorkingDir = [ [NSString alloc] initWithFormat: @"%@", [repository workingDirectory] ];
	
	NSTask *rh_git = [ [[NSTask alloc] init] autorelease ];
	NSString *pathToGit = [ [NSString alloc] initWithFormat: @"/usr/local/git/bin/git" ];
	NSMutableArray *args = [ NSMutableArray array ];
	NSNotificationCenter *nc = [ NSNotificationCenter defaultCenter ];
	
	[ args addObject: @"push" ];
	[ args addObject: @"origin" ];
	[ args addObject: @"master" ];
	//	[ args addObject: @"push origin master" ]; // used this to simulate failure!!
	
	[ nc addObserver: self selector: @selector(pushToRepositoryHostingComplete:) name: NSTaskDidTerminateNotification object: rh_git ];
	
	[ rh_git setCurrentDirectoryPath: currentWorkingDir ];
	[ rh_git setLaunchPath: pathToGit ];
	[ rh_git setArguments: args ];
	[ rh_git launch ];
	
	self.busy++;
	self.status = @"Pushing commits to RepositoryHosting";
}

//
// This method is responsible for handling the notification sent 
// by the NSTask created by the pushToRepositoryHosting() method.
// 
// Ideally, the user should be notified of the status either by 
// a collapsible property sheet/pane or an alert.
//
- (void) pushToRepositoryHostingComplete:( NSNotification * ) notification
{
	int GIT_SUCCESS_VALUE = 0;
	
	int gitTaskStatus = [ [notification object] terminationStatus ];
	
	if (gitTaskStatus == GIT_SUCCESS_VALUE)
	{
		repositoryHostingTaskResults = @"Pushed commits to RepositoryHosting successfully!";
		NSBeginInformationalAlertSheet( @"RepositoryHosting Status", nil, nil, nil, [ commitMessageView window ], self, nil, nil, NULL, repositoryHostingTaskResults);
	}
	else
	{
		repositoryHostingTaskResults = @"Push to RepositoryHosting failed unexpectedly. Please try again.";
		NSBeginCriticalAlertSheet( @"RepositoryHosting Status", nil, nil, nil, [ commitMessageView window ], self, nil, nil, NULL, repositoryHostingTaskResults);
	}
	
	self.busy--;
	self.status = @"Ready";
}

@end
