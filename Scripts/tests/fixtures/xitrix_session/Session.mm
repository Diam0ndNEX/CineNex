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

- (void)dealloc {
    delete _session;
}
- (void)alertsLoop {
    auto max_wait = lt::milliseconds(ALERTS_LOOP_WAIT_MILLIS);
    while (YES) {
        @autoreleasepool {
            try {
                auto const hasAlerts = _session->wait_for_alert(max_wait);
                std::vector<lt::alert *> alerts_queue;
                if (hasAlerts) {
                    _session->pop_alerts(&alerts_queue);
                } else {
                    continue;
                }

                for (auto it = alerts_queue.begin(); it != alerts_queue.end(); ++it) {
                    auto alert = (*it);
                    //            NSLog(@"type:%d msg:%s", alert->type(), alert->message().c_str());
                    switch (alert->type()) {
                        case lt::metadata_received_alert::alert_type: {
                            [self metadataReceivedAlert:(lt::torrent_alert *)alert];
                        } break;

                        case lt::metadata_failed_alert::alert_type: {
                            NSLog(@"TorrentKit metadata_failed - %s", alert->message().c_str());
                        } break;

                        case lt::block_finished_alert::alert_type: {
                        } break;

                        case lt::piece_finished_alert::alert_type: {
                            [self torrentMadeProgress:(lt::torrent_alert *)alert];
                        } break;

                        case lt::add_torrent_alert::alert_type: {
                            [self torrentAddedAlert:(lt::torrent_alert *)alert];
                        } break;

                        case lt::torrent_removed_alert::alert_type: {
                            //                        [self torrentRemovedAlert:(lt::torrent_alert *)alert];
                            continue; // Do not notify about update cause it was already removed
                        } break;

                        case lt::torrent_deleted_alert::alert_type: {
                            continue;
                        } break;

                        case lt::torrent_finished_alert::alert_type: {
                            [self torrentStateChanged:(lt::torrent_alert *)alert];
                        } break;

                        case lt::torrent_paused_alert::alert_type: {
                            [self torrentStateChanged:(lt::torrent_alert *)alert];
                        } break;

                        case lt::torrent_resumed_alert::alert_type: {
                            [self torrentStateChanged:(lt::torrent_alert *)alert];
                        } break;

                        case lt::torrent_error_alert::alert_type: {
                            NSLog(@"TorrentKit torrent_error - %s", alert->message().c_str());
                            [self handleTorrentError:(lt::torrent_error_alert *)alert];
                        } break;

                        case lt::file_error_alert::alert_type: {
                            NSLog(@"TorrentKit file_error - %s", alert->message().c_str());
                        } break;

                        case lt::session_error_alert::alert_type: {
                            NSLog(@"TorrentKit session_error - %s", alert->message().c_str());
                        } break;

                        case lt::peer_error_alert::alert_type: {
                            NSLog(@"TorrentKit peer_error - %s", alert->message().c_str());
                        } break;

                        case lt::tracker_announce_alert::alert_type:
                        case lt::tracker_error_alert::alert_type:
                        case lt::tracker_reply_alert::alert_type:
                        case lt::tracker_warning_alert::alert_type: {
                            NSLog(@"TorrentKit - %s", alert->message().c_str());
                            [self handleTrackerAlert: (lt::tracker_alert *)alert];
                        } break;

                        case lt::external_ip_alert::alert_type: {
                            [self handleExternalIPAlert: (lt::external_ip_alert *)alert];
                        } break;

                        case lt::state_update_alert::alert_type: {
                            auto stateUpdateAlert = static_cast<lt::state_update_alert *>(alert);
                            for (auto const &status : stateUpdateAlert->status) {
                                [self notifyDelegatesWithUpdate:status.handle];
                            }
                            continue;
                        } break;

                        case lt::save_resume_data_alert::alert_type: {
                            [self torrentSaveFastResume:(lt::save_resume_data_alert *)alert];
                            continue; // Not sure if need notify update
                        } break;

                        case lt::save_resume_data_failed_alert::alert_type: {
                            NSLog(@"TorrentKit save_resume_data_failed - %s", alert->message().c_str());
                            continue;
                        } break;

                        case lt::fastresume_rejected_alert::alert_type: {

                        } break;

                            // Skip log alerts
                        case lt::log_alert::alert_type: {
                            continue;
                        } break;

                        case lt::torrent_log_alert::alert_type: {
                            continue;
                        } break;

                        case lt::peer_log_alert::alert_type: {
                            continue;
                        } break;

                        default: break;
                    }

                    //                if (alert->message().size() > 0) {
                    //                    NSLog(@"TorrentKit - %s", alert->message().c_str());
                    //                }

                    if (dynamic_cast<lt::torrent_alert *>(alert) != nullptr) {
                        auto th = ((lt::torrent_alert *)alert)->handle;
                        if (!th.is_valid()) { continue; }

                        if (th.need_save_resume_data())
                            th.save_resume_data();

                        [self notifyDelegatesWithUpdate:th];
                    }
                }

                alerts_queue.clear();
            } catch (std::exception const &exception) {
                NSString *message = [NSString stringWithUTF8String:exception.what()] ?: @"Unknown C++ exception";
                [self reportErrorWithCode:ErrorCodeAlertFail operation:@"alertsLoop" message:message];
            } catch (...) {
                [self reportErrorWithCode:ErrorCodeAlertFail
                                operation:@"alertsLoop"
                                  message:@"Unknown C++ exception"];
            }
            [NSThread sleepForTimeInterval:0.1];
        }
    }
}

@end
