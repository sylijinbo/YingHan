#import "ConversionEngine.h"

NSDictionary *deserializeJSON(NSString *path) {
    NSInputStream *inputStream = [[NSInputStream alloc] initWithFileAtPath:path];
    [inputStream open];
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithStream:inputStream options:0 error:nil];
    [inputStream close];
    return dict;
}

@implementation ConversionEngine {
    FMDatabaseQueue *_dbQueue;
    FMDatabaseQueue *_subDbQueue;
    FMDatabaseQueue *_pyDbQueue;
    FMDatabaseQueue *_learningDbQueue;
    NSInteger _pendingLearningBackupCount;
    NSInteger _pendingLearningCleanupCount;
    BOOL _learningBackupScheduled;
}

+ (instancetype)sharedEngine {
    static dispatch_once_t once;
    static id sharedInstance;

    dispatch_once(&once, ^{
        sharedInstance = [self new];
        [sharedInstance loadPreparedData];
    });
    return sharedInstance;
}

- (void)loadPreparedData {
    [self initDatabase];
    [self initPinyinDatabase];
    [self initSubstitutionDatabase];
    [self initUserLearningDatabase];
    self.substitutions = [self loadSubstitutionsFromDB];
    self.pinyinDict = [self getPinyinData];
    self.phonexEncoded = [self getPhonexEncodedWords];
    self.phonexEncoder = [self getPhonexEncoder];
}

- (NSString *)supportDirectory {
    return [NSString stringWithFormat:@"%@/Library/Application Support/YingHan", NSHomeDirectory()];
}

- (NSString *)userLearningDatabasePath {
    return [[self supportDirectory] stringByAppendingPathComponent:@"user_learning.sqlite3"];
}

- (NSString *)userLearningBackupDirectory {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/YingHan Backups"];
}

- (NSString *)userLearningBackupPath {
    return [[self userLearningBackupDirectory] stringByAppendingPathComponent:@"user_learning.backup.sqlite3"];
}

- (NSInteger)learningRowCountAtPath:(NSString *)path {
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return 0;
    }

    FMDatabase *db = [FMDatabase databaseWithPath:path];
    if (![db open]) {
        return 0;
    }

    NSInteger rowCount = 0;
    FMResultSet *rs = [db executeQuery:@"SELECT count(*) AS count FROM sqlite_master WHERE type = 'table' AND name = 'candidate_learning'"];
    BOOL hasTable = [rs next] && [rs intForColumn:@"count"] > 0;
    [rs close];
    if (hasTable) {
        rs = [db executeQuery:@"SELECT count(*) AS count FROM candidate_learning"];
        if ([rs next]) {
            rowCount = [rs intForColumn:@"count"];
        }
        [rs close];
    }
    [db close];
    return rowCount;
}

- (void)restoreUserLearningDatabaseIfNeededAtPath:(NSString *)dbPath {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *backupPath = [self userLearningBackupPath];
    if (![fileManager fileExistsAtPath:backupPath]) {
        return;
    }

    BOOL shouldRestore = ![fileManager fileExistsAtPath:dbPath] || [self learningRowCountAtPath:dbPath] == 0;
    if (!shouldRestore || [self learningRowCountAtPath:backupPath] == 0) {
        return;
    }

    NSError *error = nil;
    if ([fileManager fileExistsAtPath:dbPath]) {
        [fileManager removeItemAtPath:dbPath error:nil];
    }
    [fileManager copyItemAtPath:backupPath toPath:dbPath error:&error];
    if (error) {
        NSLog(@"[YingHan] ERROR: Failed to restore user learning backup: %@", error.localizedDescription);
    } else {
        NSLog(@"[YingHan] Restored user learning database from backup: %@", backupPath);
    }
}

- (void)initUserLearningDatabase {
    NSString *supportDir = [self supportDirectory];
    [[NSFileManager defaultManager] createDirectoryAtPath:supportDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *dbPath = [self userLearningDatabasePath];

    [self restoreUserLearningDatabaseIfNeededAtPath:dbPath];

    _learningDbQueue = [FMDatabaseQueue databaseQueueWithPath:dbPath];
    if (!_learningDbQueue) {
        NSLog(@"[YingHan] ERROR: Failed to open user learning database at %@", dbPath);
        return;
    }

    [_learningDbQueue inDatabase:^(FMDatabase *db) {
        [db executeUpdate:@"CREATE TABLE IF NOT EXISTS candidate_learning ("
                          @"mode TEXT NOT NULL, "
                          @"input_key TEXT NOT NULL, "
                          @"candidate TEXT NOT NULL, "
                          @"count INTEGER NOT NULL DEFAULT 0, "
                          @"last_used INTEGER NOT NULL DEFAULT 0, "
                          @"PRIMARY KEY (mode, input_key, candidate))"];
        [db executeUpdate:@"CREATE INDEX IF NOT EXISTS idx_candidate_learning_lookup "
                          @"ON candidate_learning (mode, input_key, count DESC, last_used DESC)"];
    }];
}

- (void)initDatabase {
    NSString *supportDir = [NSString stringWithFormat:@"%@/Library/Application Support/YingHan", NSHomeDirectory()];
    NSString *dbPath = [supportDir stringByAppendingPathComponent:@"words_with_frequency_and_translation_and_ipa.sqlite3"];

    if (![[NSFileManager defaultManager] fileExistsAtPath:dbPath]) {
        NSString *sourcePath = [[NSBundle mainBundle] pathForResource:@"words_with_frequency_and_translation_and_ipa" ofType:@"sqlite3"];
        if (!sourcePath) {
            sourcePath = [[NSBundle bundleForClass:[self class]] pathForResource:@"words_with_frequency_and_translation_and_ipa"
                                                                          ofType:@"sqlite3"];
        }
        if (!sourcePath) {
            NSLog(@"[YingHan] ERROR: words_with_frequency_and_translation_and_ipa.sqlite3 not found");
            return;
        }
        [[NSFileManager defaultManager] createDirectoryAtPath:supportDir withIntermediateDirectories:YES attributes:nil error:nil];
        NSError *error = nil;
        [[NSFileManager defaultManager] copyItemAtPath:sourcePath toPath:dbPath error:&error];
        if (error) {
            NSLog(@"[YingHan] ERROR: Failed to copy database: %@", error.localizedDescription);
            return;
        }
        NSLog(@"[YingHan] Copied database to user directory: %@", dbPath);
    }

    _dbQueue = [FMDatabaseQueue databaseQueueWithPath:dbPath];
    if (!_dbQueue) {
        NSLog(@"[YingHan] ERROR: Failed to open database at %@", dbPath);
    }
}

- (NSDictionary *)getPinyinData {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"cedict" ofType:@"json"];
    return deserializeJSON(path);
}

- (NSDictionary *)getPhonexEncodedWords {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"phonex_encoded_words" ofType:@"json"];
    return deserializeJSON(path);
}

- (JSValue *)getPhonexEncoder {
    NSString *scriptPath = [[NSBundle mainBundle] pathForResource:@"phonex" ofType:@"js"];
    NSString *scriptString = [NSString stringWithContentsOfFile:scriptPath encoding:NSUTF8StringEncoding error:nil];

    JSContext *context = [[JSContext alloc] init];
    [context evaluateScript:scriptString];
    return context[@"phonex"];
}

- (void)initPinyinDatabase {
    NSString *supportDir = [NSString stringWithFormat:@"%@/Library/Application Support/YingHan", NSHomeDirectory()];
    NSString *dbPath = [supportDir stringByAppendingPathComponent:@"pinyin_data.sqlite3"];

    if (![[NSFileManager defaultManager] fileExistsAtPath:dbPath]) {
        NSString *sourcePath = [[NSBundle mainBundle] pathForResource:@"pinyin_data" ofType:@"sqlite3"];
        if (!sourcePath) {
            sourcePath = [[NSBundle bundleForClass:[self class]] pathForResource:@"pinyin_data" ofType:@"sqlite3"];
        }
        if (!sourcePath) {
            NSLog(@"[YingHan] ERROR: pinyin_data.sqlite3 not found");
            return;
        }
        [[NSFileManager defaultManager] createDirectoryAtPath:supportDir withIntermediateDirectories:YES attributes:nil error:nil];
        NSError *error = nil;
        [[NSFileManager defaultManager] copyItemAtPath:sourcePath toPath:dbPath error:&error];
        if (error) {
            NSLog(@"[YingHan] ERROR: Failed to copy pinyin database: %@", error.localizedDescription);
            return;
        }
        NSLog(@"[YingHan] Copied pinyin database to user directory: %@", dbPath);
    }

    _pyDbQueue = [FMDatabaseQueue databaseQueueWithPath:dbPath];
    if (!_pyDbQueue) {
        NSLog(@"[YingHan] ERROR: Failed to open pinyin database at %@", dbPath);
    }
}

- (void)initSubstitutionDatabase {
    NSString *supportDir = [NSString stringWithFormat:@"%@/Library/Application Support/YingHan", NSHomeDirectory()];
    [[NSFileManager defaultManager] createDirectoryAtPath:supportDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *dbPath = [supportDir stringByAppendingPathComponent:@"substitutions.sqlite3"];

    _subDbQueue = [FMDatabaseQueue databaseQueueWithPath:dbPath];
    [_subDbQueue inDatabase:^(FMDatabase *db) {
        [db executeUpdate:@"CREATE TABLE IF NOT EXISTS substitutions (key TEXT PRIMARY KEY, value TEXT)"];
    }];
}

- (NSDictionary *)loadSubstitutionsFromDB {
    if (!_subDbQueue)
        return @{};

    __block NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    [_subDbQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *rs = [db executeQuery:@"SELECT key, value FROM substitutions"];
        while ([rs next]) {
            dict[[rs stringForColumn:@"key"]] = [rs stringForColumn:@"value"];
        }
    }];
    return [dict copy];
}

- (NSDictionary *)allSubstitutions {
    if (!_subDbQueue)
        return @{};
    __block NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    [_subDbQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *rs = [db executeQuery:@"SELECT key, value FROM substitutions"];
        while ([rs next]) {
            dict[[rs stringForColumn:@"key"]] = [rs stringForColumn:@"value"];
        }
    }];
    return [dict copy];
}

- (void)addSubstitution:(NSString *)key value:(NSString *)value {
    if (!_subDbQueue)
        return;
    [_subDbQueue inDatabase:^(FMDatabase *db) {
        [db executeUpdate:@"INSERT OR REPLACE INTO substitutions (key, value) VALUES (?, ?)", key, value];
    }];
    // refresh the cached dictionary
    self.substitutions = [self loadSubstitutionsFromDB];
}

- (void)removeSubstitution:(NSString *)key {
    if (!_subDbQueue)
        return;
    [_subDbQueue inDatabase:^(FMDatabase *db) {
        [db executeUpdate:@"DELETE FROM substitutions WHERE key = ?", key];
    }];
    self.substitutions = [self loadSubstitutionsFromDB];
}

- (NSMutableArray *)wordsStartsWith:(NSString *)prefix {
    if (!_dbQueue)
        return [[NSMutableArray alloc] init];
    __block NSMutableArray *filtered = [[NSMutableArray alloc] init];
    NSString *lowerPrefix = [prefix lowercaseString];
    [_dbQueue inDatabase:^(FMDatabase *db) {
        NSString *sql = @"SELECT word FROM words WHERE word LIKE ? ORDER BY frequency DESC";
        NSString *pattern = [NSString stringWithFormat:@"%@%%", lowerPrefix];
        FMResultSet *resultSet = [db executeQuery:sql, pattern];
        while ([resultSet next]) {
            [filtered addObject:[resultSet stringForColumn:@"word"]];
        }
    }];
    return filtered;
}

- (NSArray *)sortWordsByFrequency:(NSArray *)filtered {
    if (filtered.count == 0)
        return filtered;
    if (!_dbQueue)
        return filtered;

    NSMutableArray *placeholders = [NSMutableArray array];
    for (NSUInteger i = 0; i < filtered.count; i++) {
        [placeholders addObject:@"?"];
    }
    NSString *sql = [NSString stringWithFormat:@"SELECT word FROM words WHERE word IN (%@) ORDER BY frequency DESC",
                                               [placeholders componentsJoinedByString:@","]];

    __block NSArray *sorted;
    [_dbQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *resultSet = [db executeQuery:sql withArgumentsInArray:filtered];
        NSMutableArray *result = [NSMutableArray array];
        while ([resultSet next]) {
            [result addObject:[resultSet stringForColumn:@"word"]];
        }
        sorted = [result copy];
    }];
    return sorted;
}

- (NSString *)phonexEncode:(NSString *)word {
    return [[self.phonexEncoder callWithArguments:@[ word ]] toString];
}

- (NSArray *)getTranslations:(NSString *)word {
    if (!_dbQueue)
        return @[];
    __block NSArray *translation = @[];
    [_dbQueue inDatabase:^(FMDatabase *db) {
        NSString *sql = @"SELECT translation FROM words WHERE word = ?";
        FMResultSet *resultSet = [db executeQuery:sql, word.lowercaseString];
        if ([resultSet next]) {
            NSString *transStr = [resultSet stringForColumn:@"translation"];
            if (transStr && transStr.length > 0) {
                translation = [transStr componentsSeparatedByString:@"|"];
            }
        }
    }];
    return translation;
}

- (NSString *)getPhoneticSymbolOfWord:(NSString *)candidateString {
    if (candidateString && candidateString.length > 3) {
        __block NSString *ipa = nil;
        NSString *word = candidateString.lowercaseString;
        [_dbQueue inDatabase:^(FMDatabase *db) {
            NSString *sql = @"SELECT ipa FROM words WHERE word = ?";
            FMResultSet *resultSet = [db executeQuery:sql, word];
            if ([resultSet next]) {
                ipa = [resultSet stringForColumn:@"ipa"];
            }
        }];
        return ipa;
    }
    return nil;
}

- (NSString *)getAnnotation:(NSString *)word {
    NSString *input = word.lowercaseString;
    NSArray *translation = [self getTranslations:input];
    if (translation && translation.count > 0) {
        NSString *translationText;
        NSString *phoneticSymbol = [self getPhoneticSymbolOfWord:input];
        if (phoneticSymbol.length > 0) {
            NSArray *list = @[ [NSString stringWithFormat:@"[%@]", phoneticSymbol] ];
            translationText = [[list arrayByAddingObjectsFromArray:translation] componentsJoinedByString:@"\n"];
        } else {
            translationText = [translation componentsJoinedByString:@"\n"];
        }
        return translationText;
    } else {
        return @"";
    }
}

- (NSArray *)sortByDamerauLevenshteinDistance:(NSArray *)original inputText:(NSString *)text {
    NSMutableArray *mutableArray = [NSMutableArray new];
    for (NSString *word in original) {
        NSUInteger distance = [text mdc_levenshteinDistanceTo:word];
        if (distance <= 3) {
            [mutableArray addObject:@{@"w" : word, @"d" : @(distance)}];
        }
    }
    NSSortDescriptor *descriptor = [[NSSortDescriptor alloc] initWithKey:@"d" ascending:YES];
    NSArray *sorted = [mutableArray sortedArrayUsingDescriptors:@[ descriptor ]];
    NSMutableArray *result = [NSMutableArray new];
    for (NSDictionary *obj in sorted) {
        [result addObject:obj[@"w"]];
    }
    return [result copy];
}

- (NSArray *)getSuggestionOfSpellChecker:(NSString *)buffer {
    NSSpellChecker *checker = [NSSpellChecker sharedSpellChecker];
    NSRange range = NSMakeRange(0, buffer.length);
    NSArray *result = [checker guessesForWordRange:range inString:buffer language:@"en" inSpellDocumentWithTag:0];

    if (buffer.length > 3) {
        NSArray *words = (self.phonexEncoded)[[self phonexEncode:buffer]];
        NSArray *wordsWithSimilarPhone = [self sortByDamerauLevenshteinDistance:words inputText:buffer];
        if (wordsWithSimilarPhone && wordsWithSimilarPhone.count > 0) {
            NSUInteger range = 4;
            NSMutableArray *finalResult = [NSMutableArray arrayWithArray:[self subarrayWithRang:result range:range]];
            [finalResult addObjectsFromArray:[self subarrayWithRang:wordsWithSimilarPhone range:range]];
            return finalResult;
        }
    }
    return result;
}

- (NSArray *)subarrayWithRang:(NSArray *)array range:(NSUInteger)range {
    NSUInteger count = array.count;
    NSUInteger limit = count >= range ? range : count;
    return [array subarrayWithRange:NSMakeRange(0, limit)];
}

- (NSArray *)predictNextWordsForContext:(NSString *)context maxResults:(NSInteger)max {
    return [self predictNextWordsForContext:context prefixFilter:nil maxResults:max];
}

- (NSArray *)predictNextWordsForContext:(NSString *)context prefixFilter:(NSString *)prefix maxResults:(NSInteger)max {
    if (!_dbQueue || !context || context.length == 0)
        return @[];

    NSString *lowerContext = context.lowercaseString;
    NSArray *contextWords = [lowerContext componentsSeparatedByString:@" "];

    // Remove empty strings from context
    NSMutableArray *cleanWords = [NSMutableArray array];
    for (NSString *w in contextWords) {
        if (w.length > 0)
            [cleanWords addObject:w];
    }
    if (cleanWords.count == 0)
        return @[];

    // Use at most the last 4 words as context (for 5-gram lookup)
    NSUInteger maxContextWords = 4;
    NSUInteger startIdx = cleanWords.count > maxContextWords ? cleanWords.count - maxContextWords : 0;
    NSArray *recentWords = [cleanWords subarrayWithRange:NSMakeRange(startIdx, cleanWords.count - startIdx)];

    __block NSMutableArray *results = [NSMutableArray array];

    [_dbQueue inDatabase:^(FMDatabase *db) {
        // Try from longest to shortest n-gram match
        // n = contextWords.count + 1, down to 2
        for (NSInteger n = recentWords.count + 1; n >= 2 && results.count < max; n--) {
            // Build the context for this n-gram level
            // For n=5 with 4 context words: use all 4 words
            // For n=4 with 4 context words: use last 3 words
            // For n=3 with 4 context words: use last 2 words
            // For n=2 with 4 context words: use last 1 word
            NSUInteger ctxLen = n - 1;
            if (ctxLen > recentWords.count)
                continue;

            NSArray *ctxWords = [recentWords subarrayWithRange:NSMakeRange(recentWords.count - ctxLen, ctxLen)];
            NSString *ctx = [ctxWords componentsJoinedByString:@" "];

            NSString *sql;
            FMResultSet *rs;

            if (prefix && prefix.length > 0) {
                NSString *lowerPrefix = prefix.lowercaseString;
                sql = @"SELECT next_word, frequency FROM ngrams WHERE n = ? AND context = ? AND next_word LIKE ? ORDER BY frequency DESC "
                      @"LIMIT ?";
                NSString *pattern = [NSString stringWithFormat:@"%@%%", lowerPrefix];
                rs = [db executeQuery:sql, @(n), ctx, pattern, @(max - results.count)];
            } else {
                sql = @"SELECT next_word, frequency FROM ngrams WHERE n = ? AND context = ? ORDER BY frequency DESC LIMIT ?";
                rs = [db executeQuery:sql, @(n), ctx, @(max - results.count)];
            }

            while ([rs next]) {
                NSString *word = [rs stringForColumn:@"next_word"];
                if (![results containsObject:word]) {
                    [results addObject:word];
                }
            }
            [rs close];
        }
    }];

    return [results copy];
}

- (NSArray *)fetchHanZiByPinyinWithPrefix:(NSString *)prefix {
    if (!_pyDbQueue || !prefix || prefix.length == 0)
        return @[];

    NSString *lowerPrefix = prefix.lowercaseString;
    __block NSMutableArray *results = [NSMutableArray array];

    [_pyDbQueue inDatabase:^(FMDatabase *db) {
        NSString *sql = @"SELECT hz FROM pinyin_data WHERE py LIKE ? OR abbr LIKE ? "
                        @"ORDER BY CASE WHEN py = ? OR abbr = ? THEN 0 ELSE 1 END, freq DESC LIMIT 20";
        NSString *pattern = [NSString stringWithFormat:@"%@%%", lowerPrefix];
        FMResultSet *rs = [db executeQuery:sql, pattern, pattern, lowerPrefix, lowerPrefix];
        while ([rs next]) {
            NSString *hz = [rs stringForColumn:@"hz"];
            if (hz && hz.length > 0 && ![results containsObject:hz]) {
                [results addObject:hz];
            }
        }
        [rs close];
    }];

    return [results copy];
}

- (BOOL)isValidLearningInputKey:(NSString *)inputKey {
    if (!inputKey || inputKey.length == 0 || inputKey.length > 32) {
        return NO;
    }

    NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
    for (NSInteger i = 0; i < (NSInteger)inputKey.length; i++) {
        if (![letters characterIsMember:[inputKey characterAtIndex:i]]) {
            return NO;
        }
    }
    return YES;
}

- (BOOL)isKnownEnglishWord:(NSString *)word {
    if (!_dbQueue || !word || word.length == 0) {
        return NO;
    }

    __block BOOL exists = NO;
    [_dbQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *rs = [db executeQuery:@"SELECT 1 FROM words WHERE word = ? LIMIT 1", word.lowercaseString];
        exists = [rs next];
        [rs close];
    }];
    return exists;
}

- (BOOL)isValidLearningCandidate:(NSString *)candidate inputKey:(NSString *)inputKey mode:(NSString *)mode candidateList:(NSArray *)candidateList {
    if (!candidate || candidate.length == 0 || candidate.length > 64) {
        return NO;
    }

    NSString *trimmed = [candidate stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0 || ![trimmed isEqualToString:candidate]) {
        return NO;
    }

    BOOL candidateMatchesInput = [candidate.lowercaseString isEqualToString:inputKey.lowercaseString];
    if (candidateMatchesInput && !([mode isEqualToString:@"english"] && [self isKnownEnglishWord:candidate])) {
        return NO;
    }

    if (![candidateList containsObject:candidate]) {
        return NO;
    }

    return YES;
}

- (NSArray *)learningRowsForInputKey:(NSString *)inputKey mode:(NSString *)mode {
    if (!_learningDbQueue || ![self isValidLearningInputKey:inputKey] || !mode || mode.length == 0) {
        return @[];
    }

    NSString *normalizedInputKey = inputKey.lowercaseString;
    __block NSMutableArray *rows = [NSMutableArray array];
    [_learningDbQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *rs = [db executeQuery:@"SELECT candidate, count, last_used FROM candidate_learning "
                                            @"WHERE mode = ? AND input_key = ? "
                                            @"ORDER BY count DESC, last_used DESC",
                                       mode, normalizedInputKey];
        while ([rs next]) {
            NSString *candidate = [rs stringForColumn:@"candidate"];
            if (candidate && candidate.length > 0) {
                [rows addObject:@{
                    @"candidate" : candidate,
                    @"count" : @([rs intForColumn:@"count"]),
                    @"last_used" : @([rs longLongIntForColumn:@"last_used"]),
                }];
            }
        }
        [rs close];
    }];
    return [rows copy];
}

- (NSArray *)applyUserLearningToCandidates:(NSArray *)candidates inputKey:(NSString *)inputKey mode:(NSString *)mode {
    if (!candidates || candidates.count == 0 || ![self isValidLearningInputKey:inputKey]) {
        return candidates;
    }

    NSArray *learningRows = [self learningRowsForInputKey:inputKey mode:mode];
    if (learningRows.count == 0) {
        return candidates;
    }

    NSMutableDictionary *candidateRanks = [NSMutableDictionary dictionary];
    NSMutableDictionary *baseIndexes = [NSMutableDictionary dictionary];
    for (NSInteger i = 0; i < (NSInteger)candidates.count; i++) {
        NSString *candidate = candidates[i];
        if (!baseIndexes[candidate]) {
            baseIndexes[candidate] = @(i);
        }
    }

    for (NSDictionary *row in learningRows) {
        NSString *candidate = row[@"candidate"];
        if (baseIndexes[candidate]) {
            candidateRanks[candidate] = row;
        }
    }
    if (candidateRanks.count == 0) {
        return candidates;
    }

    NSMutableArray *promoted = [NSMutableArray array];
    NSMutableArray *unpromoted = [NSMutableArray array];
    NSMutableArray *remaining = [NSMutableArray arrayWithArray:candidates];
    static const NSInteger learningPromotionThreshold = 3;

    for (NSString *candidate in candidates) {
        NSDictionary *rank = candidateRanks[candidate];
        if (!rank) {
            continue;
        }
        NSInteger count = [rank[@"count"] integerValue];
        if (count >= learningPromotionThreshold) {
            [promoted addObject:candidate];
        } else {
            [unpromoted addObject:candidate];
        }
        [remaining removeObject:candidate];
    }

    NSComparator compareLearnedCandidates = ^NSComparisonResult(id a, id b) {
        NSDictionary *rankA = candidateRanks[a];
        NSDictionary *rankB = candidateRanks[b];
        long long lastUsedA = [rankA[@"last_used"] longLongValue];
        long long lastUsedB = [rankB[@"last_used"] longLongValue];
        if (lastUsedA != lastUsedB) {
            return lastUsedA > lastUsedB ? NSOrderedAscending : NSOrderedDescending;
        }

        NSInteger countA = [rankA[@"count"] integerValue];
        NSInteger countB = [rankB[@"count"] integerValue];
        if (countA != countB) {
            return countA > countB ? NSOrderedAscending : NSOrderedDescending;
        }

        NSInteger indexA = [baseIndexes[a] integerValue];
        NSInteger indexB = [baseIndexes[b] integerValue];
        if (indexA == indexB) {
            return NSOrderedSame;
        }
        return indexA < indexB ? NSOrderedAscending : NSOrderedDescending;
    };

    [promoted sortUsingComparator:compareLearnedCandidates];
    [unpromoted sortUsingComparator:compareLearnedCandidates];

    NSMutableArray *ranked = [NSMutableArray array];
    [ranked addObjectsFromArray:promoted];

    NSString *originalCandidate = nil;
    for (NSString *candidate in remaining) {
        if ([candidate.lowercaseString isEqualToString:inputKey.lowercaseString]) {
            originalCandidate = candidate;
            break;
        }
    }
    if (originalCandidate) {
        [ranked addObject:originalCandidate];
        [remaining removeObject:originalCandidate];
    }

    [ranked addObjectsFromArray:unpromoted];
    [ranked addObjectsFromArray:remaining];
    return [ranked copy];
}

- (void)scheduleUserLearningBackup {
    if (!_learningDbQueue || _learningBackupScheduled) {
        return;
    }

    _learningBackupScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [self backupUserLearningDatabase];
    });
}

- (void)backupUserLearningDatabase {
    if (!_learningDbQueue) {
        return;
    }

    NSString *backupDir = [self userLearningBackupDirectory];
    NSString *backupPath = [self userLearningBackupPath];
    NSString *tempPath = [backupPath stringByAppendingString:@".tmp"];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager createDirectoryAtPath:backupDir withIntermediateDirectories:YES attributes:nil error:nil];
    [fileManager removeItemAtPath:tempPath error:nil];

    __block BOOL backedUp = NO;
    [_learningDbQueue inDatabase:^(FMDatabase *db) {
        backedUp = [db executeUpdate:@"VACUUM main INTO ?", tempPath];
        if (!backedUp) {
            NSLog(@"[YingHan] ERROR: Failed to create user learning backup: %@", [db lastErrorMessage]);
        }
    }];

    if (backedUp) {
        NSError *error = nil;
        if ([fileManager fileExistsAtPath:backupPath]) {
            [fileManager removeItemAtPath:backupPath error:nil];
        }
        [fileManager moveItemAtPath:tempPath toPath:backupPath error:&error];
        if (error) {
            NSLog(@"[YingHan] ERROR: Failed to publish user learning backup: %@", error.localizedDescription);
        }
    }

    _pendingLearningBackupCount = 0;
    _learningBackupScheduled = NO;
}

- (void)cleanupUserLearningGroupInDatabase:(FMDatabase *)db mode:(NSString *)mode inputKey:(NSString *)inputKey {
    static const NSInteger learningMaxRowsPerInputGroup = 8;

    FMResultSet *rs = [db executeQuery:@"SELECT candidate FROM candidate_learning "
                                        @"WHERE mode = ? AND input_key = ? "
                                        @"ORDER BY CASE WHEN count >= 3 THEN 0 ELSE 1 END, "
                                        @"last_used DESC, count DESC, candidate ASC "
                                        @"LIMIT ?",
                                   mode, inputKey, @(learningMaxRowsPerInputGroup)];
    NSMutableArray *keepCandidates = [NSMutableArray array];
    while ([rs next]) {
        NSString *candidate = [rs stringForColumn:@"candidate"];
        if (candidate && candidate.length > 0) {
            [keepCandidates addObject:candidate];
        }
    }
    [rs close];

    if (keepCandidates.count == 0) {
        return;
    }

    NSMutableArray *placeholders = [NSMutableArray array];
    NSMutableArray *arguments = [NSMutableArray arrayWithObjects:mode, inputKey, nil];
    for (NSString *candidate in keepCandidates) {
        [placeholders addObject:@"?"];
        [arguments addObject:candidate];
    }

    NSString *sql = [NSString stringWithFormat:@"DELETE FROM candidate_learning WHERE mode = ? AND input_key = ? AND candidate NOT IN (%@)",
                                               [placeholders componentsJoinedByString:@","]];
    [db executeUpdate:sql withArgumentsInArray:arguments];
}

- (void)recordUserLearningWithInputKey:(NSString *)inputKey
                              candidate:(NSString *)candidate
                                  mode:(NSString *)mode
                         candidateList:(NSArray *)candidateList {
    if (!_learningDbQueue || !mode || mode.length == 0) {
        return;
    }

    NSString *normalizedInputKey = inputKey.lowercaseString;
    if (![self isValidLearningInputKey:normalizedInputKey] ||
        ![self isValidLearningCandidate:candidate inputKey:normalizedInputKey mode:mode candidateList:candidateList]) {
        return;
    }

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    _pendingLearningCleanupCount++;
    static const NSInteger learningCleanupWriteInterval = 50;
    BOOL shouldCleanup = _pendingLearningCleanupCount >= learningCleanupWriteInterval;
    if (shouldCleanup) {
        _pendingLearningCleanupCount = 0;
    }

    [_learningDbQueue inDatabase:^(FMDatabase *db) {
        [db executeUpdate:@"INSERT OR IGNORE INTO candidate_learning (mode, input_key, candidate, count, last_used) "
                          @"VALUES (?, ?, ?, 0, 0)",
                          mode, normalizedInputKey, candidate];
        [db executeUpdate:@"UPDATE candidate_learning SET count = count + 1, last_used = ? "
                          @"WHERE mode = ? AND input_key = ? AND candidate = ?",
                          @((long long)now), mode, normalizedInputKey, candidate];

        static const NSInteger learningCountCompressionThreshold = 100;
        FMResultSet *rs = [db executeQuery:@"SELECT MAX(count) AS max_count FROM candidate_learning WHERE mode = ? AND input_key = ?",
                                      mode, normalizedInputKey];
        NSInteger maxCount = 0;
        if ([rs next]) {
            maxCount = [rs intForColumn:@"max_count"];
        }
        [rs close];

        if (maxCount > learningCountCompressionThreshold) {
            [db executeUpdate:@"UPDATE candidate_learning SET count = MAX(1, (count + 1) / 2) WHERE mode = ? AND input_key = ?",
                              mode, normalizedInputKey];
        }

        if (shouldCleanup) {
            [self cleanupUserLearningGroupInDatabase:db mode:mode inputKey:normalizedInputKey];
        }
    }];

    _pendingLearningBackupCount++;
    if (_pendingLearningBackupCount >= 10) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            [self backupUserLearningDatabase];
        });
    } else {
        [self scheduleUserLearningBackup];
    }
}

- (NSArray *)getCandidates:(NSString *)originalInput {
    NSString *buffer = originalInput.lowercaseString;
    NSMutableArray *result = [[NSMutableArray alloc] init];

    if (buffer && buffer.length > 0) {
        if (self.substitutions && self.substitutions[buffer]) {
            [result addObject:self.substitutions[buffer]];
        }

        NSMutableArray *filtered = [self wordsStartsWith:buffer];
        if (filtered && filtered.count > 0) {
            [result addObjectsFromArray:filtered];
        } else {
            [result addObjectsFromArray:[self getSuggestionOfSpellChecker:buffer]];
        }

        if (self.pinyinDict && self.pinyinDict[buffer]) {
            [result addObjectsFromArray:self.pinyinDict[buffer]];
        }

        if (result.count > 50) {
            result = [NSMutableArray arrayWithArray:[result subarrayWithRange:NSMakeRange(0, 49)]];
        }
        [result removeObject:buffer];
        [result insertObject:buffer atIndex:0];
    }

    NSMutableArray *result2 = [[NSMutableArray alloc] init];
    for (NSString *word in result) {
        if ([word hasPrefix:buffer]) {
            [result2 addObject:[NSString stringWithFormat:@"%@%@", originalInput, [word substringFromIndex:originalInput.length]]];
        } else {
            [result2 addObject:word];
        }
    }
    NSOrderedSet *orderedSet = [NSOrderedSet orderedSetWithArray:result2];
    NSArray *arrayWithoutDuplicates = orderedSet.array;
    return [NSArray arrayWithArray:arrayWithoutDuplicates];
}

@end
