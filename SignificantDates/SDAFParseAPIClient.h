//
//  SDAFParseAPIClient.h
//  SignificantDates
//
//  Created by タイ マイ・ティー on 6/8/14.
//
//

#import "AFHTTPRequestOperationManager.h"

typedef void (^SuccessBlockType)(AFHTTPRequestOperation *operation, id responseObject);
typedef void (^FailureBlockType)(AFHTTPRequestOperation *operation, NSError *error);

@interface SDAFParseAPIClient : AFHTTPRequestOperationManager

+(SDAFParseAPIClient*)sharedClient;

-(AFHTTPRequestOperation*)GETRequestForClass: (NSString*)className
                               parameters: (NSDictionary*)parameters
                                  success:(SuccessBlockType)success
                                  failure:(FailureBlockType)failure;

-(AFHTTPRequestOperation*)GETRequestForAllRecordsOfClass:(NSString*)className
                                     updatedAfterDate: (NSDate*)updatedDate
                                              success: (SuccessBlockType)success
                                              failure:(FailureBlockType)failure;

@end
