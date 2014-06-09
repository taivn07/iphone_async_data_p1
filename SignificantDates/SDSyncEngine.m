//
//  SDSyncEngine.m
//  SignificantDates
//
//  Created by タイ マイ・ティー on 6/8/14.
//
//

#import "SDSyncEngine.h"
#import "SDCoreDataController.h"
#import "SDAFParseAPIClient.h"

NSString * const kSDSyncEngineInitialCompleteKey = @"SDSyncEngineInitialSyncComplete";
NSString * const kSDSyncEngineSyncCompletedNotificationName = @"SDSyncEngineSyncCompleted";

@interface SDSyncEngine ()

@property (nonatomic, strong) NSMutableArray *registedClassesToSync;
@property (nonatomic, strong) dispatch_queue_t backgroundSyncQueue;
@property (nonatomic, strong) NSDateFormatter *dateFormater;

@end

@implementation SDSyncEngine

+(SDSyncEngine*)sharedEngine {
    static SDSyncEngine *sharedEngine = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedEngine = [[SDSyncEngine alloc] init];
    });
    
    return sharedEngine;
}

- (void)registerNSManagedObjectClassToSync:(Class)aClass {
    if (!self.registedClassesToSync) {
        self.registedClassesToSync = [NSMutableArray array];
    }
    
    if ([aClass isSubclassOfClass:[NSManagedObject class]]) {
        if (![self.registedClassesToSync containsObject:NSStringFromClass(aClass)]) {
            [self.registedClassesToSync addObject:NSStringFromClass(aClass)];
        } else {
            NSLog(@"Unable to register %@ as it is already registed", NSStringFromClass(aClass));
        }
    } else {
        NSLog(@"Unable to register %@ as it is not a subclass of NSManagedObject", NSStringFromClass(aClass));
    }
}

- (BOOL)initialSyncComplete {
    return [[[NSUserDefaults standardUserDefaults] valueForKey:kSDSyncEngineInitialCompleteKey] boolValue];
}

- (void)setInitialSyncCompleted {
    [[NSUserDefaults standardUserDefaults] setValue:[NSNumber numberWithBool:YES] forKey:kSDSyncEngineInitialCompleteKey];
}

- (void)executeSyncCompletedOperations {
    dispatch_sync(dispatch_get_main_queue(), ^{
        [self setInitialSyncCompleted];
        [[NSNotificationCenter defaultCenter] postNotificationName:kSDSyncEngineSyncCompletedNotificationName object:nil];
        [self willChangeValueForKey:@"syncInProgress"];
        _syncInProgress = NO;
        [self didChangeValueForKey:@"syncInProgress"];
    });
}

-(NSDate*)mostRecentUpdatedAtDateForEntityWithName:(NSString*)entityName {
    __block NSDate *date = nil;
    // create a new fetch request for the specified entity
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:entityName];
    
    // set the sort descriptor on the request to sort by updatedAt in descending order
    [request setSortDescriptors:[NSArray arrayWithObjects:[NSSortDescriptor sortDescriptorWithKey:@"updatedAt" ascending:NO], nil]];
    
    // you are only interested in 1 result so limit the request to 1
    [request setFetchLimit:1];
    [[[SDCoreDataController sharedInstance] backgroundManagedObjectContext] performBlockAndWait:^{
        NSError *error = nil;
        NSArray *results = [[[SDCoreDataController sharedInstance] backgroundManagedObjectContext] executeFetchRequest:request error:&error];
        
        if ([results lastObject]) {
            // set date to the fetched result
            date = [[results lastObject] valueForKey:@"updatedAt"];
        }
    }];
    
    return date;
}

// using record and className to create a new NSManagedObject in the backgroundManagedObjectContext
- (void)newManagedObjectWithClassName: (NSString *)className forRecord: (NSDictionary *)record {
    NSManagedObject *newManagedObject = [NSEntityDescription insertNewObjectForEntityForName:className inManagedObjectContext:[[SDCoreDataController sharedInstance] backgroundManagedObjectContext]];
    [record enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        [self setValue:obj forKey:key forManagedObject:newManagedObject];
    }];
    [record setValue:[NSNumber numberWithInt:SDObjectSynced] forKey:@"syncStatus"];
}

// accept NSManagedObject and record to updated the passed NSManagedObject with the record information
- (void)updateManagedObject: (NSManagedObject*)managedObject withRecord:(NSDictionary*)record {
    [record enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        [self setValue:obj forKey:key forManagedObject:managedObject];
    }];
}

// save data to NSManagedObject
- (void)setValue:(id)value forKey:(NSString *)key forManagedObject:(NSManagedObject *)managedObject {
    if ([key isEqualToString:@"createdAt"] || [key isEqualToString:@"updatedAt"]) {
        NSDate *date = [self dateUsingStringFromAPI:value];
        [managedObject setValue:date forKey:key];
    } else if([value isKindOfClass:[NSDictionary class]]) {
        if ([value objectForKey:@"__type"]) {
            NSString *dataType = [value objectForKey:@"__type"];
            if ([dataType isEqualToString:@"Date"]) {
                // save date to NSManaged object
                NSString *dateString = [value objectForKey:@"iso"];
                NSDate *date = [self dateUsingStringFromAPI:dateString];
                [managedObject setValue:date forKey:key];
            } else if([dataType isEqualToString:@"File"]) {
                // save file image to NSManagedObject
                NSString *urlString = [value objectForKey:@"url"];
                NSURL *url = [NSURL URLWithString:urlString];
                NSURLRequest *request = [NSURLRequest requestWithURL:url];
                NSURLResponse *response = nil;
                NSError *error = nil;
                NSData *dataResponse = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
                [managedObject setValue:dataResponse forKey:key];
            } else {
                NSLog(@"Unknow Data Type Receiveid");
                [managedObject setValue:nil forKey:key];
            }
        }
    } else {
        [managedObject setValue:value forKey:key];
    }
}

// returns an NSArray of NSManagedObjects for the specified class where their syncSttus is et to the spectified status
- (NSArray*)managedObjectsForClass:(NSString*)className withSyncStatus:(SDObjectSyncStatus)syncStatus {
    __block NSArray *results = nil;
    NSManagedObjectContext *managedObjectContext = [[SDCoreDataController sharedInstance] backgroundManagedObjectContext];
    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:className];
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"syncStatus=%d", syncStatus];
    [fetchRequest setPredicate:predicate];
    [managedObjectContext performBlockAndWait:^{
        NSError *error = nil;
        results = [managedObjectContext executeFetchRequest:fetchRequest error:&error];
    }];
    
    return results;
}

// return NSArray of NSmanagedOjects for the specified classname, sorted by key , using an array of objectIds and you can tell the method to return NSmanagedObjects whose objectIds match those in the passed array or those who do not match those in the array
- (NSArray *)managedObjectForClass: (NSString*)className sortedByKey:(NSString*)key usingArrayOfIds:(NSArray*)idArray inArrayOfIds:(BOOL)inIds {
    __block NSArray *results = nil;
    
    NSManagedObjectContext *managedObjectContext = [[SDCoreDataController sharedInstance] backgroundManagedObjectContext];
    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:className];
    NSPredicate *predicate;
    if (inIds) {
        predicate = [NSPredicate predicateWithFormat:@"objectId IN %@", idArray];
    } else {
        predicate = [NSPredicate predicateWithFormat:@"NOT (objctId IN %@)", idArray];
    }
    
    [fetchRequest setPredicate:predicate];
    [fetchRequest setSortDescriptors:[NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"objectId" ascending:YES]]];
    [managedObjectContext performBlockAndWait:^{
        NSError *error = nil;
        results = [managedObjectContext executeFetchRequest:fetchRequest error:&error];
    }];
    
    return results;
}

- (void)dowloadDataForRegistedObjects: (BOOL)useUpdatedAtDate {
    dispatch_group_t group = dispatch_group_create();
    
    for (NSString *className in self.registedClassesToSync) {
        dispatch_group_enter(group);
        
        NSDate *mostRecentUpdatedDate = nil;
        if (useUpdatedAtDate) {
            mostRecentUpdatedDate = [self mostRecentUpdatedAtDateForEntityWithName:className];
        }
        
        
        AFHTTPRequestOperation *operation = [[SDAFParseAPIClient sharedClient] GETRequestForAllRecordsOfClass:className updatedAfterDate:mostRecentUpdatedDate success:^(AFHTTPRequestOperation *operation, id responseObject) {
            if ([responseObject isKindOfClass:[NSDictionary class]]) {
                // write JSON response to disk
                [self writeJSONResponse:responseObject toDiskForClassWithName:className];
                NSLog(@"Response for %@:%@", className, responseObject);
            }
            dispatch_group_leave(group);
        } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
            NSLog(@"Response for class %@ failed with error %@", className, error);
            dispatch_group_leave(group);
        }];
        
        operation.responseSerializer = [AFJSONResponseSerializer serializer];
        [operation start];
    }
    
    dispatch_group_notify(group, self.backgroundSyncQueue, ^{
        NSLog(@"ALL operations completed");
        [self processJSONDateRecordsIntoCoreData];
    });
}

//add a new NSDateFormatter property that you can re-use
- (void)initializeDateFormater {
    if (!self.dateFormater) {
        self.dateFormater = [NSDateFormatter new];
        [self.dateFormater setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss'Z'"];
        [self.dateFormater setTimeZone:[NSTimeZone timeZoneWithName:@"GMT"]];
    }
}

- (NSDate *)dateUsingStringFromAPI: (NSString *)dateString {
    [self initializeDateFormater];
    // NSDateFormater does not like ISO 8601 so trip the milliseconds and timezon
    dateString = [dateString substringWithRange:NSMakeRange(0, [dateString length]-5)];
    
    return [self.dateFormater dateFromString:dateString];
}

- (NSString *)dateStringForAPIUsingDate: (NSDate *)date {
    [self initializeDateFormater];
    NSString *dateString = [self.dateFormater stringFromDate:date];
    // remove Z
    dateString  = [dateString substringWithRange:NSMakeRange(0, [dateString length]-1)];
    // add milliseconds and putZ backon
    dateString = [dateString stringByAppendingFormat:@".000Z"];
    
    return dateString;
}

#pragma mark - File management

- (NSURL *)applicationCacheDirectory {
    return [[[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask] lastObject];
}

- (NSURL *)JSONDataRecordDirectory {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *url = [NSURL URLWithString:@"JSONRecords/" relativeToURL:[self applicationCacheDirectory]];
    NSError *error = nil;
    
    if (![fileManager fileExistsAtPath:[url path]]) {
        [fileManager createDirectoryAtPath:[url path] withIntermediateDirectories:YES attributes:nil error:&error];
    }
    
    return url;
}

- (void)writeJSONResponse: (id)response toDiskForClassWithName:(NSString *)className {
    NSURL *fileURL = [NSURL URLWithString:className relativeToURL:[self JSONDataRecordDirectory]];
    if (![(NSDictionary *)response writeToFile:[fileURL path] atomically:YES]) {
        NSLog(@"Error saving reponse to disk, will attempt to remove NSNull values and try again");
        // remove NSNulls and try again
        NSArray *records = [response objectForKey:@"results"];
        NSMutableArray *nullFreeRecords = [NSMutableArray array];
        for (NSDictionary *record in records) {
            NSMutableDictionary *nullFreeRecord = [NSMutableDictionary dictionaryWithDictionary:record];
            [record enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                if ([obj isKindOfClass:[NSNull class]]) {
                    [nullFreeRecord setValue:nil forKey:key];
                }
            }];
            [nullFreeRecords addObject:nullFreeRecord];
        }
        
        NSDictionary *nullFreeDictionary = [NSDictionary dictionaryWithObject:nullFreeRecords forKey:@"results"];
        
        if (![nullFreeDictionary writeToFile:[fileURL path] atomically:YES]) {
            NSLog(@"Failed all attempts to save response to disk: %@", response);
        }
    }
}

- (void)startSync {
    if (!self.syncInProgress) {
        [self willChangeValueForKey:@"syncInProgress"];
        _syncInProgress = YES;
        [self didChangeValueForKey:@"syncInProgress"];
        
        self.backgroundSyncQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
        dispatch_async(self.backgroundSyncQueue, ^{
            [self dowloadDataForRegistedObjects:YES];
        });
    }
}

- (NSDictionary *)JSONDictionaryForClassWithName: (NSString *)className {
    // retrieve files from disk
    NSURL *fileURL = [NSURL URLWithString:className relativeToURL:[self JSONDataRecordDirectory]];
    
    return [NSDictionary dictionaryWithContentsOfURL:fileURL];
}

- (NSArray *)JSONDataRecordsForClass: (NSString *)className sortedByKey: (NSString *)key {
    // return information in an NSArray with keys "results" and sort by specified key
    NSDictionary *JSONDictionary = [self JSONDictionaryForClassWithName:className];
    NSArray *records = [JSONDictionary objectForKey:@"results"];
    return [records sortedArrayUsingDescriptors:[NSArray arrayWithObjects:[NSSortDescriptor sortDescriptorWithKey:key ascending:YES], nil]];
}

- (void)deleteJSONDataRecordsForClassWithName: (NSString *)className {
    // delete JSON response file when finished with them
    NSURL *url = [NSURL URLWithString:className relativeToURL:[self JSONDataRecordDirectory]];
    NSError *error = nil;
    BOOL deleted = [[NSFileManager defaultManager] removeItemAtURL:url error:&error];
    if (!deleted) {
        NSLog(@"Unable to delete JSON Records at %@, reason: %@", url, error);
    }
}

- (void)processJSONDateRecordsIntoCoreData {
    NSManagedObjectContext *managedObjectContext = [[SDCoreDataController sharedInstance] backgroundManagedObjectContext];
    
    // iterate over all registed class to syn
    for (NSString *className in self.registedClassesToSync) {
        if (![self initialSyncComplete]) {
            // import all downloaded datat to Core Data for initial sync
            // if this is the initial sync then the logic is pretty simple, you will fetch the JSON data from disk
            // for the class of the current iteration and create new NSmangedObject for each record
            
            NSDictionary *JSONDictionary = [self JSONDictionaryForClassWithName:className];
            NSArray *records = [JSONDictionary objectForKey:@"results"];
            for (NSDictionary *record in records) {
                [self newManagedObjectWithClassName:className forRecord:record];
            }
        } else {
            // otherwise you need to do some more logic to determine if the record is new or has been updated
            // First get the download records from the JSON response, verify there is at leaset one objects
            // in the date, and then fetch all records stored in Core Data whose objectId matchs those from the JSON response
            NSArray *downloadedRecords = [self JSONDataRecordsForClass:className sortedByKey:@"objectId"];
            if ([downloadedRecords lastObject]) {
                // Now you have a set object objects from the remote service and all of the matching objects
                // (based on objectId) from your Core Data store. Iterate over all of the download records
                // from the remote service
                
                NSArray *storedRecords = [self managedObjectForClass:className sortedByKey:@"objectId" usingArrayOfIds:[downloadedRecords valueForKey:@"objectid"] inArrayOfIds:YES];
                int currentIndex = 0;
                
                // if the number of records in your Core Data store is less than the currentIndex, you know that
                // you have a potential match between the downloaded records and stored records because you sorted
                // both list by objectId, this means that an updated has come in from the remote service
                for (NSDictionary *record in downloadedRecords) {
                    NSManagedObject *storedManagedObject = nil;
                    
                    // Make sure we dont access an index that is out of bounds as whe are uterating over
                    // both collections to gether
                    if ([storedRecords count] > currentIndex) {
                        storedManagedObject = [storedRecords objectAtIndex:currentIndex];
                    }
                    
                    if ([[storedManagedObject valueForKey:@"objectId"] isEqualToString:[record valueForKey:@"objectId"]]) {
                        // do a quick spot check to validate the objectIds in fact do match, if they do update the stored
                        // object with the values received from the remote server
                        [self updateManagedObject:[storedRecords objectAtIndex:currentIndex] withRecord:record];
                    } else {
                        // otherwise you have a new object comming in from your remote service so create a new
                        // NSMangedObject to represent this remove object locally
                        [self newManagedObjectWithClassName:className forRecord:record];
                    }
                    
                    currentIndex++;
                }
            }
        }
        
        // Once all NSMangedObjects are created in your context you can save the context to persist the object
        // to your persistent store. In this case though you used an NSmangedObjectContext who has a parent context
        // so all change will be pushed to the parent context
        
        [managedObjectContext performBlockAndWait:^{
            NSError *error = nil;
            if (![managedObjectContext save:&error]) {
                NSLog(@"Unabl to save context for class %@", className);
            }
        }];
        
        // You are now done with the downloaed JSON responses so you can delete them to cclean up after yourself
        // then call your executeSynCompletedOperations to save off your master context and set
        // the syncInPregress flag to NO
        [self deleteJSONDataRecordsForClassWithName:className];
        [self executeSyncCompletedOperations];
    }
}



@end
