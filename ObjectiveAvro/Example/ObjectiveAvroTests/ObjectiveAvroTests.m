//
//  ObjectiveAvroTests.m
//  ObjectiveAvroTests
//
//  Created by Marcelo Fabri on 14/03/14.
//  Copyright (c) 2014 Movile. All rights reserved.
//

#define EXP_SHORTHAND YES

#import <XCTest/XCTest.h>
#import <Expecta.h>
#import <ObjectiveAvro/OAVAvroSerialization.h>

@interface ObjectiveAvroTests : XCTestCase

@end

@implementation ObjectiveAvroTests

#pragma mark - Private methods

+ (id)JSONObjectFromBundleResource:(NSString *)resource {
    NSString *path = [[NSBundle bundleForClass:self] pathForResource:resource ofType:@"json"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return dict;
}

+ (id)stringFromBundleResource:(NSString *)resource {
    NSString *path = [[NSBundle bundleForClass:self] pathForResource:resource ofType:@"json"];
    return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
}

- (void)registerSchemas:(OAVAvroSerialization *)avro {
    NSString *personSchema = [[self class] stringFromBundleResource:@"person_schema"];
    NSString *peopleSchema = [[self class] stringFromBundleResource:@"people_schema"];
    
    [avro registerSchema:personSchema error:NULL];
    [avro registerSchema:peopleSchema error:NULL];
}

#pragma mark - XCTestCase

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

#pragma mark - Tests

- (void)testValidSchemaRegistration {
    OAVAvroSerialization *avro = [[OAVAvroSerialization alloc] init];
    
    NSString *personSchema = [[self class] stringFromBundleResource:@"person_schema"];
    NSString *peopleSchema = [[self class] stringFromBundleResource:@"people_schema"];
    
    NSError *error;
    BOOL result = [avro registerSchema:personSchema error:&error];
    expect(result).to.beTruthy();
    expect(error).to.beNil();
    
    result = [avro registerSchema:peopleSchema error:&error];
    expect(result).to.beTruthy();
    expect(error).to.beNil();
}

- (void)testInvalidJSONSchemaRegistration {
    OAVAvroSerialization *avro = [[OAVAvroSerialization alloc] init];
    NSError *error;
    BOOL result = [avro registerSchema:@"{invalid json}" error:&error];
    expect(result).to.beFalsy();
    expect(error).notTo.beNil();
}

- (void)testInvalidSchemaWithNoNameRegistration {
    NSString *schema = @"{\"type\":\"record\",\"namespace\":\"com.movile.objectiveavro.unittest.v1\",\"fields\":[{\"name\":\"name\",\"type\":\"string\"},{\"name\":\"country\",\"type\":\"string\"},{\"name\":\"age\",\"type\":\"int\"}]}";
    
    OAVAvroSerialization *avro = [[OAVAvroSerialization alloc] init];
    NSError *error;
    BOOL result = [avro registerSchema:schema error:&error];
    expect(result).to.beFalsy();
    expect(error).notTo.beNil();
    expect(error.domain).to.equal(NSCocoaErrorDomain);
    expect(error.code).to.equal(NSPropertyListReadCorruptError);
}

- (void)testAvroSerialization {
    NSDictionary *dict = [[self class] JSONObjectFromBundleResource:@"people"];
    
    OAVAvroSerialization *avro = [[OAVAvroSerialization alloc] init];
    [self registerSchemas:avro];
    
    NSError *error;
    NSData *data = [avro dataFromJSONObject:dict forSchemaNamed:@"People" error:&error];
    
    expect(error).to.beNil();
    expect(data).notTo.beNil();
    
    NSDictionary *fromAvro = [avro JSONObjectFromData:data forSchemaNamed:@"People" error:&error];
    
    expect(error).to.beNil();
    expect(fromAvro).notTo.beNil();
    
    expect(fromAvro).to.equal(dict);
}

- (void)testAvroCopy {
    NSDictionary *dict = [[self class] JSONObjectFromBundleResource:@"people"];
    
    OAVAvroSerialization *avro = [[OAVAvroSerialization alloc] init];
    [self registerSchemas:avro];
    
    NSError *error;
    NSData *data = [avro dataFromJSONObject:dict forSchemaNamed:@"People" error:&error];
    
    expect(error).to.beNil();
    expect(data).notTo.beNil();
    
    OAVAvroSerialization *copy = [avro copy];
    expect(copy).notTo.beNil();
    expect(copy).toNot.equal(avro);
    
    NSData *dataFromCopy = [copy dataFromJSONObject:dict forSchemaNamed:@"People" error:&error];
    expect(error).to.beNil();
    expect(dataFromCopy).notTo.beNil();
    expect(dataFromCopy).to.equal(data);
}

- (void)testAvroCoding {
    NSDictionary *dict = [[self class] JSONObjectFromBundleResource:@"people"];
    
    OAVAvroSerialization *avro = [[OAVAvroSerialization alloc] init];
    [self registerSchemas:avro];
    
    NSError *error;
    NSData *data = [avro dataFromJSONObject:dict forSchemaNamed:@"People" error:&error];
    
    expect(error).to.beNil();
    expect(data).notTo.beNil();
    
    NSData *archivedAvroData = [NSKeyedArchiver archivedDataWithRootObject:avro];
    expect(archivedAvroData).notTo.beNil();
    
    OAVAvroSerialization *archivedAvro = [NSKeyedUnarchiver unarchiveObjectWithData:archivedAvroData];
    
    expect(archivedAvro).notTo.beNil();
    expect(archivedAvro).toNot.equal(avro);
    
    NSData *dataFromCopy = [archivedAvro dataFromJSONObject:dict
                                             forSchemaNamed:@"People" error:&error];
    expect(error).to.beNil();
    expect(dataFromCopy).notTo.beNil();
    expect(dataFromCopy).to.equal(data);
}

- (void)testMissingFieldAvroSerialization {
    NSString *json = @"{\"people\":[{\"name\":\"Marcelo Fabri\",\"age\":20},{\"name\":\"Tim Cook\",\"country\":\"USA\",\"age\":53},{\"name\":\"Steve Wozniak\",\"country\":\"USA\",\"age\":63},{\"name\":\"Bill Gates\",\"country\":\"USA\",\"age\":58}],\"generated_timestamp\":1389376800000}";
    
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    
    OAVAvroSerialization *avro = [[OAVAvroSerialization alloc] init];
    [self registerSchemas:avro];
    
    NSError *error;
    NSData *data = [avro dataFromJSONObject:dict forSchemaNamed:@"People" error:&error];
    
    expect(error).toNot.beNil();
    expect(error.domain).to.equal(NSCocoaErrorDomain);
    expect(error.code).to.equal(NSPropertyListReadCorruptError);
    expect(data).to.beNil();
}

- (void)testNoSchemaRegistred {
    NSDictionary *dict = [[self class] JSONObjectFromBundleResource:@"people"];
    
    OAVAvroSerialization *avro = [[OAVAvroSerialization alloc] init];
    
    NSError *error;
    NSData *data = [avro dataFromJSONObject:dict forSchemaNamed:@"People" error:&error];
    
    expect(error).toNot.beNil();
    expect(error.domain).to.equal(NSCocoaErrorDomain);
    expect(error.code).to.equal(NSFileReadNoSuchFileError);
    expect(data).to.beNil();
}

#pragma mark - Type tests 

- (void)testStringType {
    NSString *schema = @"{\"type\":\"record\",\"name\":\"StringTest\",\"namespace\":\"com.movile.objectiveavro.unittest.v1\",\"fields\":[{\"name\":\"string_value\",\"type\":\"string\"}]}";
    
    OAVAvroSerialization *avro = [[OAVAvroSerialization alloc] init];
    [avro registerSchema:schema error:NULL];

    NSArray *strings = @[@"bla", @"test", @"foo", @"bar"];
    
    for (NSString *str in strings) {
        NSError *error;
        NSData *data = [avro dataFromJSONObject:@{@"string_value": str} forSchemaNamed:@"StringTest" error:&error];
        expect(error).to.beNil();
        expect(data).toNot.beNil();
        
        NSString *strFromAvro = [avro JSONObjectFromData:data forSchemaNamed:@"StringTest" error:&error][@"string_value"];
        
        expect(error).to.beNil();
        expect(strFromAvro).to.equal(str);
    }
}

- (void)testIntType {
    NSString *schema = @"{\"type\":\"record\",\"name\":\"IntTest\",\"namespace\":\"com.movile.objectiveavro.unittest.v1\",\"fields\":[{\"name\":\"int_value\",\"type\":\"int\"}]}";
    
    OAVAvroSerialization *avro = [[OAVAvroSerialization alloc] init];
    [avro registerSchema:schema error:NULL];
    
    NSArray *numbers = @[@2, @303, @1098, @500000, @-200, @-100001, @0];
    
    for (NSNumber *number in numbers) {
        NSError *error;
        NSData *data = [avro dataFromJSONObject:@{@"int_value": number} forSchemaNamed:@"IntTest" error:&error];
        expect(error).to.beNil();
        expect(data).toNot.beNil();
        
        NSString *numberFromAvro = [avro JSONObjectFromData:data forSchemaNamed:@"IntTest" error:&error][@"int_value"];
        
        expect(error).to.beNil();
        expect(numberFromAvro).to.equal(number);
    }
}

- (void)testLongType {
    NSString *schema = @"{\"type\":\"record\",\"name\":\"LongTest\",\"namespace\":\"com.movile.objectiveavro.unittest.v1\",\"fields\":[{\"name\":\"long_value\",\"type\":\"long\"}]}";
    
    OAVAvroSerialization *avro = [[OAVAvroSerialization alloc] init];
    [avro registerSchema:schema error:NULL];
    
    NSArray *numbers = @[@2, @303, @1098, @500000,  @-200, @-100001, @0, @((long) pow(2, 30)), @((long) pow(-2, 30))];
    
    for (NSNumber *number in numbers) {
        NSError *error;
        NSData *data = [avro dataFromJSONObject:@{@"long_value": number} forSchemaNamed:@"LongTest" error:&error];
        expect(error).to.beNil();
        expect(data).toNot.beNil();
        
        NSString *numberFromAvro = [avro JSONObjectFromData:data forSchemaNamed:@"LongTest" error:&error][@"long_value"];
        
        expect(error).to.beNil();
        expect(numberFromAvro).to.equal(number);
    }
}

- (void)testFloatType {
    NSString *schema = @"{\"type\":\"record\",\"name\":\"FloatTest\",\"namespace\":\"com.movile.objectiveavro.unittest.v1\",\"fields\":[{\"name\":\"float_value\",\"type\":\"float\"}]}";
    
    OAVAvroSerialization *avro = [[OAVAvroSerialization alloc] init];
    [avro registerSchema:schema error:NULL];
    
    NSArray *numbers = @[@2, @303, @1098, @500000, @-200, @-100001, @0, @1.43f, @100.98420f, @0.001f, @-9.7431f];
    
    for (NSNumber *number in numbers) {
        NSError *error;
        NSData *data = [avro dataFromJSONObject:@{@"float_value": number} forSchemaNamed:@"FloatTest" error:&error];
        expect(error).to.beNil();
        expect(data).toNot.beNil();
        
        NSString *numberFromAvro = [avro JSONObjectFromData:data forSchemaNamed:@"FloatTest" error:&error][@"float_value"];
        
        expect(error).to.beNil();
        expect(numberFromAvro).to.equal(number);
    }
}

- (void)testDoubleType {
    NSString *schema = @"{\"type\":\"record\",\"name\":\"DoubleTest\",\"namespace\":\"com.movile.objectiveavro.unittest.v1\",\"fields\":[{\"name\":\"double_value\",\"type\":\"double\"}]}";
    
    OAVAvroSerialization *avro = [[OAVAvroSerialization alloc] init];
    [avro registerSchema:schema error:NULL];
    
    NSArray *numbers = @[@2, @303, @1098, @500000, @-200, @-100001, @0, @1.43, @100.98420, @0.001, @-9.7431, @(DBL_MAX), @((double) pow(2.4, 20)), @(M_PI)];
    
    for (NSNumber *number in numbers) {
        NSError *error;
        NSData *data = [avro dataFromJSONObject:@{@"double_value": number} forSchemaNamed:@"DoubleTest" error:&error];
        expect(error).to.beNil();
        expect(data).toNot.beNil();
        
        NSString *numberFromAvro = [avro JSONObjectFromData:data forSchemaNamed:@"DoubleTest" error:&error][@"double_value"];
        
        expect(error).to.beNil();
        expect(numberFromAvro).to.equal(number);
    }
}

- (void)testBooleanType {
    NSString *schema = @"{\"type\":\"record\",\"name\":\"BooleanTest\",\"namespace\":\"com.movile.objectiveavro.unittest.v1\",\"fields\":[{\"name\":\"boolean_value\",\"type\":\"boolean\"}]}";
    
    OAVAvroSerialization *avro = [[OAVAvroSerialization alloc] init];
    [avro registerSchema:schema error:NULL];
    
    NSArray *numbers = @[@NO, @YES];
    
    for (NSNumber *number in numbers) {
        NSError *error;
        NSData *data = [avro dataFromJSONObject:@{@"boolean_value": number} forSchemaNamed:@"BooleanTest" error:&error];
        expect(error).to.beNil();
        expect(data).toNot.beNil();
        
        NSString *numberFromAvro = [avro JSONObjectFromData:data forSchemaNamed:@"BooleanTest" error:&error][@"boolean_value"];
        
        expect(error).to.beNil();
        expect(numberFromAvro).to.equal(number);
    }
}

- (void)testNullType {
    NSString *schema = @"{\"type\":\"record\",\"name\":\"NullTest\",\"namespace\":\"com.movile.objectiveavro.unittest.v1\",\"fields\":[{\"name\":\"null_value\",\"type\":\"null\"}]}";
    
    OAVAvroSerialization *avro = [[OAVAvroSerialization alloc] init];
    [avro registerSchema:schema error:NULL];
    
    
    NSError *error;
    NSData *data = [avro dataFromJSONObject:@{@"null_value": [NSNull null]} forSchemaNamed:@"NullTest" error:&error];
    expect(error).to.beNil();
    expect(data).toNot.beNil();
    
    id nullFromAvro = [avro JSONObjectFromData:data forSchemaNamed:@"NullTest" error:&error][@"null_value"];
    
    expect(error).to.beNil();
    expect(nullFromAvro).to.equal([NSNull null]);
}

- (void)testArrayType {
    NSString *schema = @"{\"type\":\"array\",\"name\":\"ArrayTest\",\"namespace\":\"com.movile.objectiveavro.unittest.v1\",\"items\": {\"type\": \"int\"}}";

    OAVAvroSerialization *avro = [[OAVAvroSerialization alloc] init];
    [avro registerSchema:schema error:NULL];
    
    
    NSError *error;
    NSArray *array = @[@1, @5, @-2, @0, @10021, @500000];
    NSData *data = [avro dataFromJSONObject:array forSchemaNamed:@"ArrayTest" error:&error];
    expect(error).to.beNil();
    expect(data).toNot.beNil();
    
    NSArray *arrayFromAvro = [avro JSONObjectFromData:data forSchemaNamed:@"ArrayTest" error:&error];
    
    expect(error).to.beNil();
    expect(arrayFromAvro).to.equal(array);
}

- (void)testMapType {
    NSString *schema = @"{\"type\":\"map\",\"name\":\"MapTest\",\"namespace\":\"com.movile.objectiveavro.unittest.v1\",\"values\": \"int\"}";
    
    OAVAvroSerialization *avro = [[OAVAvroSerialization alloc] init];
    [avro registerSchema:schema error:NULL];
    
    
    NSError *error;
    NSDictionary *map = @{@"one": @1, @"zero": @0, @"two": @2, @"-one": @-1};
    NSData *data = [avro dataFromJSONObject:map forSchemaNamed:@"MapTest" error:&error];
    expect(error).to.beNil();
    expect(data).toNot.beNil();
    
    NSDictionary *mapFromAvro = [avro JSONObjectFromData:data forSchemaNamed:@"MapTest" error:&error];
    
    expect(error).to.beNil();
    expect(mapFromAvro).to.equal(map);
}

- (void)testBytesType {
    NSString *schema = @"{\"type\":\"record\",\"name\":\"BytesTest\",\"namespace\":\"com.movile.objectiveavro.unittest.v1\",\"fields\":[{\"name\":\"bytes_value\",\"type\":\"bytes\"}]}";
    
    OAVAvroSerialization *avro = [[OAVAvroSerialization alloc] init];
    [avro registerSchema:schema error:NULL];
    
    
    NSError *error;
    NSString *bytes = @"\"\\u00de\\u00ad\\u00be\\u00ef\"";
    
    NSData *data = [avro dataFromJSONObject:@{@"bytes_value": bytes} forSchemaNamed:@"BytesTest" error:&error];
    expect(error).to.beNil();
    expect(data).toNot.beNil();
    
    id bytesFromAvro = [avro JSONObjectFromData:data forSchemaNamed:@"BytesTest" error:&error][@"bytes_value"];
    
    expect(error).to.beNil();
    expect(bytesFromAvro).to.equal(bytes);
}

@end
