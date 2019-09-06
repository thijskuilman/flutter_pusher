#import "FlutterPusherPlugin.h"

@implementation FlutterPusherPlugin

NSString *const PUSHER_CHANNEL_NAME = @"plugins.indoor.solutions/pusher";
NSString *const PUSHER_CONNECTION_CHANNEL_NAME = @"plugins.indoor.solutions/pusher_connection";
NSString *const PUSHER_MESSAGE_CHANNEL_NAME = @"plugins.indoor.solutions/pusher_message";
NSString *const PUSHER_ERROR_CHANNEL_NAME = @"plugins.indoor.solutions/pusher_error";

+ (void)registerWithRegistrar:(NSObject <FlutterPluginRegistrar> *)registrar {
    FlutterMethodChannel *channel = [FlutterMethodChannel
                                     methodChannelWithName:PUSHER_CHANNEL_NAME
                                     binaryMessenger:[registrar messenger]];
    FlutterPusherPlugin *instance = [[FlutterPusherPlugin alloc] init];
    [registrar addMethodCallDelegate:instance channel:channel];
    
    FlutterEventChannel *connectionEventChannel = [FlutterEventChannel eventChannelWithName:PUSHER_CONNECTION_CHANNEL_NAME
                                                                            binaryMessenger:[registrar messenger]];
    instance.connectivityStreamHandler = [[PusherConnectionStateStream alloc] init];
    [connectionEventChannel setStreamHandler:instance.connectivityStreamHandler];
    
    FlutterEventChannel *messageEventChannel = [FlutterEventChannel eventChannelWithName:PUSHER_MESSAGE_CHANNEL_NAME binaryMessenger:[registrar messenger]];
    instance.messageStreamHandler = [[MessageStreamHandler alloc] init];
    [messageEventChannel setStreamHandler:instance.messageStreamHandler];
    
    FlutterEventChannel *errorChannel = [FlutterEventChannel eventChannelWithName:PUSHER_ERROR_CHANNEL_NAME
                                                                  binaryMessenger:[registrar messenger]];
    instance.errorStreamHandler = [[PusherErrorStream alloc] init];
    [errorChannel setStreamHandler:instance.errorStreamHandler];
}

- (BOOL)pusher:(PTPusher *)pusher connectionWillConnect:(PTPusherConnection *)connection {
    [self.connectivityStreamHandler sendState:@"connecting"];
    return YES;
}

- (void)pusher:(PTPusher *)pusher connectionDidConnect:(PTPusherConnection *)connection {
    [self.connectivityStreamHandler sendState:@"connected"];
    
}

- (void)pusher:(PTPusher *)pusher connection:(PTPusherConnection *)connection didDisconnectWithError:(NSError *)error willAttemptReconnect:(BOOL)willAttemptReconnect {
    [self.connectivityStreamHandler sendState:@"disconnected"];
    if (error) {
        [self.errorStreamHandler sendError:error];
    }
}

- (void)pusher:(PTPusher *)pusher connection:(PTPusherConnection *)connection failedWithError:(NSError *)error {
    [self.connectivityStreamHandler sendState:@"disconnected"];
    if (error) {
        [self.errorStreamHandler sendError:error];
    }
}

- (BOOL)pusher:(PTPusher *)pusher connectionWillAutomaticallyReconnect:(PTPusherConnection *)connection afterDelay:(NSTimeInterval)delay {
    [self.connectivityStreamHandler sendState:@"reconnecting"];
    return YES;
}

- (void)pusher:(PTPusher *)pusher willAuthorizeChannel:(PTPusherChannel *)channel withAuthOperation:(PTPusherChannelAuthorizationOperation *)operation {
    
}

- (void)pusher:(PTPusher *)pusher didSubscribeToChannel:(PTPusherChannel *)channel {
    
}

- (void)pusher:(PTPusher *)pusher didUnsubscribeFromChannel:(PTPusherChannel *)channel {
    
}

- (void)pusher:(PTPusher *)pusher didFailToSubscribeToChannel:(PTPusherChannel *)channel withError:(NSError *)error {
    [self.errorStreamHandler sendError:error];
}

- (void)pusher:(PTPusher *)pusher didReceiveErrorEvent:(PTPusherErrorEvent *)errorEvent {
    [self.errorStreamHandler sendCode:errorEvent.code message:errorEvent.message];
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    if ([call.method isEqualToString:@"create"]) {
        NSString *apiKey = call.arguments[@"apiKey"];
        NSString *cluster = call.arguments[@"cluster"];
        NSString *authUrl = call.arguments[@"authUrl"];
        
        if ([cluster length] == 0) {
            self.pusher = [PTPusher pusherWithKey:apiKey delegate:self encrypted:YES];
        } else {
            self.pusher = [PTPusher pusherWithKey:apiKey delegate:self encrypted:YES cluster:cluster];
        }
        
        if ([authUrl length] > 0) {
            self.pusher.authorizationURL = [NSURL URLWithString:authUrl];
        }
        
        result(@(YES));
    } else if ([call.method isEqualToString:@"connect"]) {
        [self.pusher connect];
        result(@(YES));
    } else if ([call.method isEqualToString:@"disconnect"]) {
        [self.pusher disconnect];
        result(@(YES));
    } else if ([call.method isEqualToString:@"subscribe"]) {
        NSString *channelName = call.arguments[@"channel"];
        NSString *event = call.arguments[@"event"];
        PTPusherChannel *channel = [self.pusher channelNamed:channelName];
        
        if (!channel) {
            channel = [self.pusher subscribeToChannelNamed:channelName];
        }
        
        [channel bindToEventNamed:event target:self action:@selector(forwardEvent:)];
        result(@(YES));
    } else if ([call.method isEqualToString:@"subscribePrivate"]) {
        NSString *channelName = call.arguments[@"channel"];
        NSString *event = call.arguments[@"event"];
        PTPusherChannel *channel = [self.pusher channelNamed:channelName];
        
        if (!channel) {
            channel = [self.pusher subscribeToPrivateChannelNamed:channelName];
        }
        
        [channel bindToEventNamed:event target:self action:@selector(forwardEvent:)];
        result(@(YES));
    } else if ([call.method isEqualToString:@"unsubscribe"]) {
        PTPusherChannel *channel = [self.pusher channelNamed:call.arguments];
        [channel removeAllBindings];
        if (channel) {
            [channel unsubscribe];
        }
        result(@(YES));
    }
    result(FlutterMethodNotImplemented);
}

- (void)forwardEvent:(PTPusherEvent *)event {
    [_messageStreamHandler send:event];
}

@end

@implementation MessageStreamHandler {
    FlutterEventSink _eventSink;
}

- (FlutterError *_Nullable)onListenWithArguments:(id _Nullable)arguments eventSink:(FlutterEventSink)events {
    _eventSink = events;
    return nil;
}

- (void)send:(PTPusherEvent *)event {
    if (_eventSink) {
        NSDictionary *dictionary = @{@"channel": event.channel, @"event": event.name, @"body": event.data};
        _eventSink(dictionary);
    }
}

- (FlutterError *_Nullable)onCancelWithArguments:(id _Nullable)arguments {
    _eventSink = nil;
    return nil;
}

@end


@implementation PusherConnectionStateStream {
    FlutterEventSink _eventSink;
}

- (FlutterError *_Nullable)onListenWithArguments:(id _Nullable)arguments eventSink:(FlutterEventSink)events {
    _eventSink = events;
    return nil;
}

- (void)sendState:(NSString *)state {
    if (_eventSink) {
        _eventSink(state);
    }
}

- (FlutterError *_Nullable)onCancelWithArguments:(id _Nullable)arguments {
    _eventSink = nil;
    return nil;
}

@end

@implementation PusherErrorStream {
    FlutterEventSink _eventSink;
}

- (void)sendError:(NSError *)error {
    if (_eventSink) {
        _eventSink(@{@"code" : @(error.code), @"message" : error.localizedDescription});
    }
}

- (void)sendCode:(NSInteger)code message:(NSString *)message {
    if (_eventSink) {
        _eventSink(@{@"code" : @(code), @"message" : message});
    }
}

- (FlutterError *_Nullable)onListenWithArguments:(id _Nullable)arguments eventSink:(FlutterEventSink)events {
    _eventSink = events;
    return nil;
}

- (FlutterError *_Nullable)onCancelWithArguments:(id _Nullable)arguments {
    _eventSink = nil;
    return nil;
}


@end
