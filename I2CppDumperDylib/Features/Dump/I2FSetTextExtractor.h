#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 负责从 dump 目录中提取 set_Text/set_htmlText 信息，并可写回过滤后的 set_text_rvas.json。
@interface I2FSetTextExtractor : NSObject

/// 从 dump 目录提取过滤后的 set_Text/set_htmlText 列表（去重、过滤 System.*、非 virtual 单参 String）。
/// 同时可选地写出 set_text_rvas.json（覆盖）。
/// 返回的条目包含 name/rva（可选）/signature（可选）。
+ (NSArray<NSDictionary *> *)extractEntriesAtDumpPath:(NSString *)dumpPath
                                        writeJSONFile:(BOOL)writeJSON;

@end

NS_ASSUME_NONNULL_END
