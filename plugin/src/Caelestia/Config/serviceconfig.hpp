#pragma once

#include "configobject.hpp"

#include <qstring.h>
#include <qstringlist.h>
#include <qvariant.h>

namespace caelestia::config {

using Qt::StringLiterals::operator""_s;

class ServiceConfig : public ConfigObject {
    Q_OBJECT
    QML_ANONYMOUS

    CONFIG_GLOBAL_PROPERTY(QString, weatherLocation)
    // Guess based on locale
    CONFIG_GLOBAL_PROPERTY(bool, useFahrenheit,
        QLocale().measurementSystem() == QLocale::ImperialUSSystem ||
            QLocale().measurementSystem() == QLocale::ImperialUKSystem)
    // This is always false by default cause apparently even imperial system users don't use it for perf temps?
    CONFIG_GLOBAL_PROPERTY(bool, useFahrenheitPerformance, false)
    // Attempt to guess based on locale
    CONFIG_GLOBAL_PROPERTY(
        bool, useTwelveHourClock, QLocale().timeFormat(QLocale::ShortFormat).toLower().contains(u"a"_s))
    CONFIG_GLOBAL_PROPERTY(QString, gpuType)
    CONFIG_GLOBAL_PROPERTY(int, visualiserBars, 45)
    CONFIG_GLOBAL_PROPERTY(qreal, audioIncrement, 0.1)
    CONFIG_GLOBAL_PROPERTY(qreal, brightnessIncrement, 0.1)
    CONFIG_GLOBAL_PROPERTY(qreal, maxVolume, 1.0)
    CONFIG_GLOBAL_PROPERTY(bool, smartScheme, true)
    CONFIG_GLOBAL_PROPERTY(QString, defaultPlayer, u"Spotify"_s)
    CONFIG_GLOBAL_PROPERTY(QVariantList, playerAliases,
        { vmap({ { u"from"_s, u"com.github.th_ch.youtube_music"_s }, { u"to"_s, u"YT Music"_s } }) })
    CONFIG_GLOBAL_PROPERTY(bool, showLyrics, false)
    CONFIG_GLOBAL_PROPERTY(QString, lyricsBackend, u"Auto"_s)
    CONFIG_GLOBAL_PROPERTY(QVariantList, panelMappings,
        {
            vmap({
                { u"id"_s, u"docker"_s },
                { u"name"_s, u"Docker"_s },
                { u"description"_s, u"Container runtime daemon"_s },
                { u"icon"_s, u"deployed_code"_s },
                { u"adapter"_s, u"docker"_s },
                { u"enabled"_s, true },
                { u"capabilities"_s, vmap({
                                         { u"start"_s, true },
                                         { u"stop"_s, true },
                                     }) },
                { u"params"_s, vmap({
                                    { u"probeMode"_s, u"cli-only"_s },
                                    { u"startCommandPreference"_s, QStringList{ u"systemctl"_s } },
                                    { u"stopCommandPreference"_s, QStringList{ u"systemctl"_s } },
                                }) },
            }),
            vmap({
                { u"id"_s, u"network-manager"_s },
                { u"name"_s, u"NetworkManager"_s },
                { u"description"_s, u"Network service manager"_s },
                { u"icon"_s, u"network_check"_s },
                { u"adapter"_s, u"systemd"_s },
                { u"enabled"_s, true },
                { u"capabilities"_s, vmap({
                                         { u"start"_s, true },
                                         { u"stop"_s, true },
                                     }) },
                { u"params"_s, vmap({
                                    { u"unit"_s, u"NetworkManager.service"_s },
                                }) },
            }),
            vmap({
                { u"id"_s, u"bluetooth"_s },
                { u"name"_s, u"Bluetooth"_s },
                { u"description"_s, u"Bluetooth stack daemon"_s },
                { u"icon"_s, u"bluetooth"_s },
                { u"adapter"_s, u"systemd"_s },
                { u"enabled"_s, true },
                { u"capabilities"_s, vmap({
                                         { u"start"_s, true },
                                         { u"stop"_s, true },
                                     }) },
                { u"params"_s, vmap({
                                    { u"unit"_s, u"bluetooth.service"_s },
                                }) },
            }),
        })

public:
    explicit ServiceConfig(QObject* parent = nullptr)
        : ConfigObject(parent) {}
};

} // namespace caelestia::config
