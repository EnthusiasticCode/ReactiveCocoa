//
//  main.m
//  Test
//
//  Created by Uri Baghin on 08/01/2013.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <ReactiveCocoa/ReactiveCocoa.h>

@interface CountUpToXEnumerator : NSEnumerator

+ (instancetype)countUpTo:(NSUInteger)x;

@end

@implementation CountUpToXEnumerator {
	NSUInteger _x;
	NSUInteger _current;
}

+ (instancetype)countUpTo:(NSUInteger)x {
	CountUpToXEnumerator *enumerator = [[self alloc] init];
	enumerator->_x = x;
	return enumerator;
}

- (id)nextObject {
	if (_current == _x) return nil;
	return @(_current++);
}

@end

int main(int argc, const char * argv[]) {
	
	@autoreleasepool {
		
		__block NSUInteger sum = 0;
		[[CountUpToXEnumerator countUpTo:1000000].rac_signal subscribeNext:^(NSNumber *x) {
			sum += x.unsignedIntegerValue;
		} completed:^{
			NSLog(@"%@", @(sum));
			exit(0);
		}];
		
	}
	
	sleep(UINT32_MAX);
	return 0;
}

