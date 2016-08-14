//
//  OAVAvroSerialization.h
//  Objective-Avro
//
//  Created by Marcelo Fabri on 23/01/14.
//  Copyright (c) 2014 Movile. All rights reserved.
//

#import <Foundation/Foundation.h>

/**
 *  Converts from NSData to JSON objects (and vice-versa). 
 *  A wrapper on Avro-C, (almost) mimicking the interface of NSJSONSerialization.
 */
@interface OAVAvroSerialization : NSObject <NSCopying, NSCoding>

/**
 *  Serializes a JSON object to NSData, containing the Avro-encoded object.
 *
 *  @param jsonObject The object to be encoded
 *  @param schemaName The schema name used to describe the object
 *  @param error      A pointer to the error object that will represent any errors ocurred
 *
 *  @return An NSData object, containing the result of serialization to Avro format
 */
- (NSData *)dataFromJSONObject:(id)jsonObject forSchemaNamed:(NSString *)schemaName
                         error:(NSError * __autoreleasing *)error;

/**
 *  Creates a Foundation object from a NSData Avro object.
 *
 *  @param data       NSData object with the result of a previous Avro serialization
 *  @param schemaName The schema's name of the object being unserialized
 *  @param error      A pointer to the error object that will represent any errors ocurred
 *
 *  @return A Foundation representation of the Avro encoded object
 */
- (id)JSONObjectFromData:(NSData *)data forSchemaNamed:(NSString *)schemaName
                   error:(NSError * __autoreleasing *)error;

/**
 *  Register a schema so the wrapper can serialize objects later.
 *
 *  @param schema A JSON describing the Avro schema
 *  @param error  A pointer to the error object that will represent any errors ocurred
 *
 *  @return Whether the schema was registered or not
 */
- (BOOL)registerSchema:(NSString *)schema error:(NSError * __autoreleasing *)error;

@end
