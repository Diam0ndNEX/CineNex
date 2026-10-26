#import "Session_Internal.h"
static NSErrorDomain ErrorDomain = @"fixture.Session.error";
@implementation Session
- (instancetype)initWith:(NSURL *)downloadPath torrentsPath:(NSURL *)torrentsPath fastResumePath:(NSURL *)fastResumePath settings:(SessionSettings *)settings storages:(NSDictionary<NSUUID*, StorageModel*>*)storages {
    self = [super init];
    if (self) {
        _downloadPath = downloadPath.path;
        _torrentsPath = torrentsPath.path;
        _fastResumePath = fastResumePath.path;
        _settings = settings;
        _storages = storages;

        NSError * error;
        [[NSFileManager defaultManager] createDirectoryAtURL:downloadPath withIntermediateDirectories:YES attributes:nil error:&error];
        [[NSFileManager defaultManager] createDirectoryAtURL:torrentsPath withIntermediateDirectories:YES attributes:nil error:&error];
        [[NSFileManager defaultManager] createDirectoryAtURL:fastResumePath withIntermediateDirectories:YES attributes:nil error:&error];

        auto params = lt::session_params(_settings.settingsPack);
        params.disk_io_constructor = &lt::pread_disk_io_constructor;
        _session = new lt::session(std::move(params));

        // Init session properties
        _filesQueue = dispatch_queue_create([FileEntriesQueueIdentifier UTF8String], DISPATCH_QUEUE_SERIAL);
        _torrentsMap = [[NSMutableDictionary alloc] init];
        _automaticErrorRecoveryAttempts = [[NSMutableSet alloc] init];
        _delegates = [NSHashTable weakObjectsHashTable];

        // restore session
        [self restoreSession];

        // start alerts loop
        _eventsThread = [[NSThread alloc] initWithTarget:self selector:@selector(alertsLoop) object:nil];
        [_eventsThread setName: EventsQueueIdentifier];
        [_eventsThread setQualityOfService:NSQualityOfServiceDefault];
        [_eventsThread start];

    }
    return self;
}

- (void)setSettings:(SessionSettings *)settings {
    _settings = settings;
    _session->pause(); // Pause to break current connections in case networking settings will be changed
    _session->apply_settings(settings.settingsPack);
    _session->resume();
}

@end
