//
//  main.m
//  Test
//
//  Created by Uri Baghin on 08/01/2013.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <ReactiveCocoa/ReactiveCocoa.h>

int main(int argc, const char * argv[]) {
	@autoreleasepool {
	    
		NSUInteger length = 1000000;
		NSMutableArray *values = [NSMutableArray arrayWithCapacity:length];
		for (NSUInteger i = 0; i < length; ++i) {
			[values addObject:@(i)];
		}
		
		__block NSUInteger sum = 0;
		[values.objectEnumerator.rac_signal subscribeNext:^(NSNumber *x) {
			sum += x.unsignedIntegerValue;
		} completed:^{
			NSLog(@"%@", @(sum));
		}];
		
		sleep(UINT32_MAX);
	}
	return 0;
}

