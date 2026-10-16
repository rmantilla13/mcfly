#include "SettingsBridge.h"

#include "hardware/DisplayController.h"
#include "models/Assistant.h"
#include "models/FeedStore.h"
#include "voice/VoiceClient.h"

SettingsBridge::SettingsBridge(FeedStore *store, DisplayController *display, Assistant *assistant, VoiceClient *voice, QObject *parent)
    : QObject(parent), m_store(store), m_display(display), m_assistant(assistant), m_voice(voice)
{
    m_debounce.setSingleShot(true);
    m_debounce.setInterval(1500);
    connect(&m_debounce, &QTimer::timeout, this, [this]() {
        const QVariantMap patch = changed(collect(), m_server);
        if (patch.isEmpty())
            return;
        for (auto it = patch.cbegin(); it != patch.cend(); ++it)
            m_server.insert(it.key(), it.value());
        emit push(patch);
    });

    if (m_store) {
        connect(m_store, &FeedStore::deviceSettingsReceived, this, &SettingsBridge::receive);
        connect(this, &SettingsBridge::push, m_store, &FeedStore::pushDeviceSettings);
    }
    if (m_display) {
        for (auto signal : {&DisplayController::screensaverChanged, &DisplayController::backdropChanged, &DisplayController::darkModeChanged,
                            &DisplayController::animatedTilesChanged, &DisplayController::idleTimeoutChanged,
                            &DisplayController::sleepSettingsChanged})
            connect(m_display, signal, this, &SettingsBridge::onLocalChange);
    }
    if (m_assistant)
        connect(m_assistant, &Assistant::providerChanged, this, &SettingsBridge::onLocalChange);
    if (m_voice) {
        // A hello after the display (or the web) changed the voice.
        connect(m_voice, &VoiceClient::infoChanged, this, &SettingsBridge::onLocalChange);
        connect(m_voice, &VoiceClient::speakRepliesChanged, this, &SettingsBridge::onLocalChange);
        connect(m_voice, &VoiceClient::wakewordEnabledChanged, this, &SettingsBridge::onLocalChange);
    }
}

QVariantMap SettingsBridge::collect() const
{
    QVariantMap s;
    if (m_display) {
        s.insert("screensaver", m_display->screensaver());
        s.insert("backdrop", m_display->backdrop());
        s.insert("darkMode", m_display->darkMode());
        s.insert("animatedTiles", m_display->animatedTiles());
        s.insert("idleSeconds", qBound(30, m_display->idleTimeoutSec(), 3600));
        s.insert("offAfterSeconds", qBound(0, m_display->offAfterSec(), 86400));
        s.insert("offAtNight", m_display->offAtNight());
        s.insert("bedtime", qBound(0, m_display->bedtime(), 1439));
        s.insert("wakeTime", qBound(0, m_display->wakeTime(), 1439));
    }
    if (m_assistant)
        s.insert("assistantProvider", m_assistant->provider());
    if (m_voice) {
        s.insert("speakReplies", m_voice->speakReplies());
        // The wake word's on/off lives in the voice service; only say it
        // while the service is there to know.
        if (m_voice->available()) {
            s.insert("wakeword", m_voice->wakewordEnabled());
            // What the voice service runs now (it says in its hello).
            if (!m_voice->voiceId().isEmpty())
                s.insert("voice", m_voice->voiceId());
            s.insert("voiceSpeed", qRound(m_voice->speechSpeed() * 100) / 100.0);
            if (!m_voice->wakewordModel().isEmpty())
                s.insert("wakewordModel", m_voice->wakewordModel());
        }
    }
    return s;
}

void SettingsBridge::apply(const QVariantMap &settings)
{
    m_applying = true;
    if (m_display) {
        if (settings.contains("screensaver"))
            m_display->setScreensaver(settings.value("screensaver").toString());
        if (settings.contains("backdrop"))
            m_display->setBackdrop(settings.value("backdrop").toString());
        if (settings.contains("darkMode"))
            m_display->setDarkMode(settings.value("darkMode").toBool());
        if (settings.contains("animatedTiles"))
            m_display->setAnimatedTiles(settings.value("animatedTiles").toBool());
        if (settings.contains("idleSeconds"))
            m_display->setIdleTimeoutSec(settings.value("idleSeconds").toInt());
        if (settings.contains("offAfterSeconds"))
            m_display->setOffAfterSec(settings.value("offAfterSeconds").toInt());
        if (settings.contains("offAtNight"))
            m_display->setOffAtNight(settings.value("offAtNight").toBool());
        if (settings.contains("bedtime"))
            m_display->setBedtime(settings.value("bedtime").toInt());
        if (settings.contains("wakeTime"))
            m_display->setWakeTime(settings.value("wakeTime").toInt());
    }
    if (m_assistant && settings.contains("assistantProvider"))
        m_assistant->setProvider(settings.value("assistantProvider").toString());
    if (m_voice) {
        if (settings.contains("speakReplies"))
            m_voice->setSpeakReplies(settings.value("speakReplies").toBool());
        if (settings.contains("wakeword") && m_voice->available() && settings.value("wakeword").toBool() != m_voice->wakewordEnabled())
            m_voice->setWakewordEnabled(settings.value("wakeword").toBool());
        if (m_voice->available() && (settings.contains("voice") || settings.contains("voiceSpeed") || settings.contains("wakewordModel")))
            m_voice->setVoiceOptions(settings.value("voice").toString(), settings.value("voiceSpeed", 0.0).toDouble(),
                                     settings.value("wakewordModel").toString());
    }
    m_applying = false;
}

QVariantMap SettingsBridge::changed(const QVariantMap &local, const QVariantMap &server)
{
    QVariantMap out;
    for (auto it = local.cbegin(); it != local.cend(); ++it) {
        const QVariant theirs = server.value(it.key());
        // Numbers arrive from JSON as doubles; compare by value, not type.
        const bool same = theirs.isValid()
            && (theirs == it.value() || (theirs.canConvert<double>() && it.value().canConvert<double>()
                                         && it.value().typeId() != QMetaType::QString
                                         && theirs.toDouble() == it.value().toDouble()));
        if (!same)
            out.insert(it.key(), it.value());
    }
    return out;
}

void SettingsBridge::receive(const QVariantMap &settings)
{
    const bool first = !m_seenServer;
    m_seenServer = true;
    m_server = settings;
    if (settings.isEmpty()) {
        // Nothing on the server yet: this display's settings become the copy.
        if (first) {
            const QVariantMap mine = collect();
            m_server = mine;
            emit push(mine);
        }
        return;
    }
    apply(settings);
    // Keys the server doesn't have yet (an older copy): send ours.
    const QVariantMap missing = changed(collect(), m_server);
    QVariantMap add;
    for (auto it = missing.cbegin(); it != missing.cend(); ++it)
        if (!m_server.contains(it.key()))
            add.insert(it.key(), it.value());
    if (!add.isEmpty()) {
        for (auto it = add.cbegin(); it != add.cend(); ++it)
            m_server.insert(it.key(), it.value());
        emit push(add);
    }
}

void SettingsBridge::onLocalChange()
{
    if (m_applying || !m_seenServer)
        return;
    m_debounce.start();
}
