//
//  SDAFParseAPIClient.m
//  SignificantDates
//
//  Created by タイ マイ・ティー on 6/8/14.
//
//

#import "SDAFParseAPIClient.h"

static NSString * const kSDFParseAPIBaseURLString = @"https://api.parse.com/1/";

static NSString * const kSDFParseAPIApplicationId = @"VNea8PdBvwGLxpkmBLlmMD4ulGG19W6pyXroRzev";
static NSString * const kSDFParseAPIKey = @"3PGkrm74XprIMht97SnoaG3y7u6EirXh1sev9KEz";

@implementation SDAFParseAPIClient

+ (SDAFParseAPIClient*)sharedClient {
    static SDAFParseAPIClient *sharedClient = nil;
    static dispatch_once_t oneToken;
    dispatch_once(&oneToken, ^{
        sharedClient = [[SDAFParseAPIClient alloc] initWithBaseURL:[NSURL URLWithString:kSDFParseAPIBaseURLString]];
    });
    
    return sharedClient;
}

-(instancetype)initWithBaseURL:(NSURL *)url {
    self = [super initWithBaseURL:url];
    if (self) {
        AFJSONRequestSerializer *requesstSerializer = [[AFJSONRequestSerializer alloc] init];
        [requesstSerializer setValue:kSDFParseAPIApplicationId forHTTPHeaderField:@"X-Parse-Application-Id"];
        [requesstSerializer setValue:kSDFParseAPIKey forHTTPHeaderField:@"X-Parse-REST-API-Key"];
        [self setRequestSerializer:requesstSerializer];
        [self setResponseSerializer:[AFJSONResponseSerializer serializer]];
    }
    
    return self;
}

-(AFHTTPRequestOperation*)GETRequestForClass: (NSString*)className
                                  parameters: (NSDictionary*)parameters
                                     success:(SuccessBlockType)success
                                     failure:(FailureBlockType)failure {
    AFHTTPRequestOperation *operation = [self GET:[NSString stringWithFormat:@"classes/%@", className] parameters:parameters success:success failure:failure];
    
    return operation;
}

-(AFHTTPRequestOperation*)GETRequestForAllRecordsOfClass:(NSString*)className
                                     updatedAfterDate: (NSDate*)updatedDate
                                              success: (SuccessBlockType)success
                                              failure:(FailureBlockType)failure {
    AFHTTPRequestOperation *operation = nil;
    NSDictionary *parameters = nil;
    if (updatedDate) {
        NSDateFormatter *dateFormater = [[NSDateFormatter alloc] init];
        [dateFormater setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.'999Z'"];
        [dateFormater setTimeZone:[NSTimeZone timeZoneWithName:@"GMT"]];
        
        NSString *jsonString = [NSString stringWithFormat:@"{\"updatedAt\":{\"$gte\":{\"__type\":\"Date\",\"iso\":\"%@\"}}}",[dateFormater stringFromDate:updatedDate]];
        parameters = [NSDictionary dictionaryWithObject:jsonString forKey:@"where"];
    }
    
    operation = [self GETRequestForClass:className parameters:parameters success:success failure:failure];
    
    return operation;
}



@end
