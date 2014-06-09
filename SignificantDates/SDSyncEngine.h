//
//  SDSyncEngine.h
//  SignificantDates
//
//  Created by タイ マイ・ティー on 6/8/14.
//
//

#import <Foundation/Foundation.h>

typedef enum {
    SDObjectSynced = 0,
    SDObjectCreated,
    SDObjectDeleted,
} SDObjectSyncStatus;

@interface SDSyncEngine : NSObject

@property (atomic, readonly) BOOL syncInProgress;

+ (SDSyncEngine*)sharedEngine;

-(void)registerNSManagedObjectClassToSync:(Class)aClass;
- (void)startSync;

@end
