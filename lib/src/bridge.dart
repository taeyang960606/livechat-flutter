// Ported from the LiveChat Android SDK's queue-based bridge.
const bootstrapScript = r'''
(function () {
    if (window.__livechatFlutterBridge) {
        return;
    }

    window.__livechatFlutterBridge = true;

    window.__livechatCall = function (method, args) {
        var sdk = window.LiveChat = window.LiveChat || { q: [] };

        if (typeof sdk[method] === 'function') {
            sdk[method].apply(sdk, args || []);
            return;
        }

        sdk.q = sdk.q || [];
        sdk.q.push([method, args || []]);
    };

    // The widget replays 'ready' for a late subscriber, so this
    // cannot miss a widget that mounted before the bridge landed.
    window.__livechatCall('on', ['ready', function () {
        LiveChatFlutter.postMessage(JSON.stringify({ type: 'ready' }));
    }]);

    window.__livechatCall('on', ['message', function (payload) {
        LiveChatFlutter.postMessage(JSON.stringify({
            type: 'message',
            message: payload.message
        }));
    }]);

    window.__livechatCall('on', ['error', function (payload) {
        LiveChatFlutter.postMessage(JSON.stringify({
            type: 'error',
            description: (payload && payload.message) ? String(payload.message) : 'widget error'
        }));
    }]);
})();
''';
