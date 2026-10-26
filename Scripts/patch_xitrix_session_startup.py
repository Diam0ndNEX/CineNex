"""Harden and instrument the pinned XITRIX native session initializer."""
from pathlib import Path
import argparse
import re

MARKER = '// CineNex native startup diagnostics v1'
TRACE = r'''
// CineNex native startup diagnostics v1
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <mach/mach.h>
#include <exception>
#include <errno.h>

static void CineNexNativeStage(NSString *stage, NSString *detail = @"") {
    @try {
        NSURL *cache = [[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
        if (cache == nil) { return; }
        NSURL *directory = [cache URLByAppendingPathComponent:@"CineNex/Diagnostics" isDirectory:YES];
        [[NSFileManager defaultManager] createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil];
        NSURL *file = [directory URLByAppendingPathComponent:@"native-startup.jsonl"];
        mach_task_basic_info_data_t info = {};
        mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
        const bool memoryAvailable = task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t)&info, &count) == KERN_SUCCESS;
        NSString *attempt = [[NSUserDefaults standardUserDefaults] stringForKey:@"cinenex.playbackAttemptID"] ?: @"none";
        NSRegularExpression *urls = [NSRegularExpression regularExpressionWithPattern:@"[a-zA-Z][a-zA-Z0-9+.-]*://[^\\s]+" options:0 error:nil];
        NSString *safeDetail = [urls stringByReplacingMatchesInString:detail options:0 range:NSMakeRange(0, detail.length) withTemplate:@"[redacted-url]"];
        if (safeDetail.length > 1000) { safeDetail = [safeDetail substringToIndex:1000]; }
        NSDictionary *event = @{
            @"timestamp": @([[NSDate date] timeIntervalSince1970]),
            @"attempt": attempt, @"stage": stage, @"detail": safeDetail,
            @"resident_bytes": @(memoryAvailable ? info.resident_size : 0),
            @"main_thread": @([NSThread isMainThread]),
            @"uptime_seconds": @([NSProcessInfo processInfo].systemUptime)
        };
        NSData *json = [NSJSONSerialization dataWithJSONObject:event options:NSJSONWritingSortedKeys error:nil];
        if (json == nil) { return; }
        NSMutableData *line = [json mutableCopy];
        [line appendBytes:"\n" length:1];
        int descriptor = open(file.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND, 0600);
        if (descriptor < 0) { return; }
        struct stat attributes;
        if (fstat(descriptor, &attributes) == 0 && attributes.st_size > 262144) { ftruncate(descriptor, 0); }
        const uint8_t *bytes = (const uint8_t *)line.bytes;
        size_t remaining = line.length;
        while (remaining > 0) {
            ssize_t written = write(descriptor, bytes, remaining);
            if (written < 0 && errno == EINTR) { continue; }
            if (written <= 0) { break; }
            bytes += written;
            remaining -= (size_t)written;
        }
        fsync(descriptor);
        close(descriptor);
    } @catch (NSException *ignored) {
        // Diagnostics must never prevent session startup.
    }
}

'''


class PatchError(RuntimeError):
    pass


def patched_sources(settings, session, header):
    present = [MARKER in settings, MARKER in session, 'nullable instancetype)initWith:' in header]
    if all(present):
        return None
    if any(present):
        raise PatchError('Partially applied session-startup patch; refusing an inconsistent wrapper.')
    settings_anchor = '        _peerFingerprint = @"-IT0000-";'
    if settings.count(settings_anchor) != 1:
        raise PatchError('Unexpected SessionSettings initializer.')
    fields = ['agentName', 'peerFingerprint', 'outgoingInterfaces', 'listenInterfaces', 'proxyHostname', 'proxyUsername', 'proxyPassword']
    for field in fields:
        if settings.count(f'[_{field} UTF8String]') != 1:
            raise PatchError(f'Unexpected native string conversion: {field}')
    signature = '- (instancetype)initWith:'
    if header.count(signature) != 1 or session.count(signature) != 1:
        raise PatchError('Unexpected Session initializer signature.')
    start = session.index(signature)
    end = session.index('\n- (void)setSettings:', start)
    constructor = session[start:end]
    replacements = [
        ('        auto params = lt::session_params(_settings.settingsPack);', '        CineNexNativeStage(@"settings.convert.begin");\n        auto params = lt::session_params(_settings.settingsPack);\n        CineNexNativeStage(@"settings.convert.end");'),
        ('        _session = new lt::session(std::move(params));', '        CineNexNativeStage(@"session.construct.begin");\n        _session = new lt::session(std::move(params));\n        CineNexNativeStage(@"session.construct.end");'),
        ('        [self restoreSession];', '        CineNexNativeStage(@"persistence.restore.begin");\n        [self restoreSession];\n        CineNexNativeStage(@"persistence.restore.end");'),
        ('        [_eventsThread start];', '        CineNexNativeStage(@"alerts.thread.start");\n        [_eventsThread start];\n        CineNexNativeStage(@"session.ready");')
    ]
    for anchor, replacement in replacements:
        if constructor.count(anchor) != 1:
            raise PatchError('Unexpected native initializer body: ' + anchor.strip())
        constructor = constructor.replace(anchor, replacement, 1)
    body_start = constructor.index('    self = [super init];')
    body_end = constructor.rindex('    return self;') + len('    return self;')
    body = constructor[body_start:body_end]
    constructor = constructor[:body_start] + '''    CineNexNativeStage(@"session.init.enter");
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"cinenex.nativeSessionInitializationError"];
    @try {
        try {
''' + '\n'.join('        ' + line for line in body.splitlines()) + '''
        } catch (std::exception const &exception) {
            NSString *reason = [NSString stringWithUTF8String:exception.what()] ?: @"C++ initialization error";
            CineNexNativeStage(@"session.exception.cpp", reason);
            [[NSUserDefaults standardUserDefaults] setObject:@"Native C++ session initialization failed. See native diagnostics." forKey:@"cinenex.nativeSessionInitializationError"];
        } catch (...) {
            CineNexNativeStage(@"session.exception.unknown");
            [[NSUserDefaults standardUserDefaults] setObject:@"Unknown native initialization failure." forKey:@"cinenex.nativeSessionInitializationError"];
        }
    } @catch (NSException *exception) {
        CineNexNativeStage(@"session.exception.objc", [NSString stringWithFormat:@"%@: %@", exception.name, exception.reason ?: @""]);
        [[NSUserDefaults standardUserDefaults] setObject:@"Objective-C session initialization failed. See native diagnostics." forKey:@"cinenex.nativeSessionInitializationError"];
    }
    return nil;''' + constructor[body_end:]
    settings = MARKER + '\n' + settings
    settings = settings.replace('@implementation SessionSettings', 'static const char *CineNexSafeUTF8(NSString *value) {\n    const char *text = [value UTF8String];\n    return text != nullptr ? text : \"\";\n}\n\n@implementation SessionSettings', 1)
    defaults = '''        _agentName = @"CineNex";
        _outgoingInterfaces = @"";
        _listenInterfaces = @"0.0.0.0:0,[::]:0";
        _proxyHostname = @"";
        _proxyUsername = @"";
        _proxyPassword = @"";
'''
    settings = settings.replace(settings_anchor, defaults + settings_anchor, 1)
    for field in fields:
        settings = settings.replace(f'[_{field} UTF8String]', f'CineNexSafeUTF8(_{field})')
    session = session[:start] + constructor + session[end:]
    anchor = 'static NSErrorDomain ErrorDomain'
    if session.count(anchor) != 1:
        raise PatchError('Unexpected Session error-domain declaration.')
    session = session.replace(anchor, TRACE + anchor, 1)
    header = header.replace(signature, '- (nullable instancetype)initWith:', 1)
    return settings, session, header


def patch_wrapper(root):
    paths = [root / path for path in ['LibTorrent/Core/SessionSettings/SessionSettings.mm', 'LibTorrent/Core/Session/Session.mm', 'LibTorrent/Core/Session/Session.h']]
    if not all(p.is_file() for p in paths):
        raise PatchError('Expected pinned XITRIX session sources are missing.')
    changes = patched_sources(*(p.read_text() for p in paths))
    if changes is None:
        return False
    for path, content in zip(paths, changes):
        path.write_text(content)
    return True


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('wrapper_root', type=Path)
    args = parser.parse_args()
    try:
        print('Native startup patch applied.' if patch_wrapper(args.wrapper_root) else 'Native startup patch already applied.')
    except (OSError, PatchError) as error:
        parser.exit(1, str(error) + '\n')
