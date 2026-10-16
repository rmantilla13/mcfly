#pragma once

#include <QObject>
#include <QTimer>
#include <QVariantMap>

class FeedStore;
class DisplayController;
class Assistant;
class VoiceClient;

// Keeps this display's settings and the server's copy (devices.settings) the
// same, so the web console and the screen edit one thing.
//
//   server -> screen: each sync's settings are applied to the controllers.
//   screen -> server: a change made here is sent (debounced) as a patch of
//                     the keys that differ.
//   first sync with an empty server copy: this display's current settings
//                     are uploaded, so nothing set on the Pi is lost.
//   the voice service (re)connects: its first hello is what it ran before, not
//                     a pick, so the server's voice is applied to it instead.
//                     The voice is the account's: the web and the app follow
//                     this display's (docs/VOICE.md).
//
// Keys and ranges match clean_device_settings (migration 20261015000004).
// The assistant and voice pointers may be null (tests).
class SettingsBridge : public QObject
{
    Q_OBJECT
public:
    SettingsBridge(FeedStore *store, DisplayController *display, Assistant *assistant, VoiceClient *voice, QObject *parent = nullptr);

    // This display's settings, as the server stores them.
    QVariantMap collect() const;
    // Applies the keys it knows; others are ignored. Doesn't echo back.
    void apply(const QVariantMap &settings);
    // The keys of `local` that differ from `server`.
    static QVariantMap changed(const QVariantMap &local, const QVariantMap &server);
    // The server's copy after a sync (FeedStore::deviceSettingsReceived).
    void receive(const QVariantMap &settings);

signals:
    // A patch for the server (FeedStore::pushDeviceSettings).
    void push(const QVariantMap &patch);

private:
    void onLocalChange();
    void onVoiceInfo();

    FeedStore *m_store;
    DisplayController *m_display;
    Assistant *m_assistant;
    VoiceClient *m_voice;
    QVariantMap m_server;
    bool m_seenServer = false;
    bool m_applying = false;
    bool m_voiceFresh = false; // the next hello is the voice service's first since it connected
    QTimer m_debounce;
};
