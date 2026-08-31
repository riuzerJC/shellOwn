#pragma once

#include <qobject.h>
#include <qqmlintegration.h>
#include <qpointer.h>
#include <polkitqt1-agent-listener.h>
#include <polkitqt1-agent-session.h>
#include <polkitqt1-subject.h>
#include <polkitqt1-identity.h>
#include <polkitqt1-details.h>

namespace caelestia::services {

class PolkitAgent : public PolkitQt1::Agent::Listener {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool active READ active NOTIFY activeChanged)
    Q_PROPERTY(QString actionId READ actionId NOTIFY requestChanged)
    Q_PROPERTY(QString message READ message NOTIFY requestChanged)
    Q_PROPERTY(QString iconName READ iconName NOTIFY requestChanged)
    Q_PROPERTY(QString identity READ identity NOTIFY requestChanged)
    Q_PROPERTY(QString prompt READ prompt NOTIFY promptChanged)
    Q_PROPERTY(bool echo READ echo NOTIFY promptChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)
    Q_PROPERTY(bool isBusy READ isBusy NOTIFY busyChanged)

public:
    explicit PolkitAgent(QObject* parent = nullptr);
    ~PolkitAgent() override;

    [[nodiscard]] bool active() const { return m_active; }
    [[nodiscard]] QString actionId() const { return m_actionId; }
    [[nodiscard]] QString message() const { return m_message; }
    [[nodiscard]] QString iconName() const { return m_iconName; }
    [[nodiscard]] QString identity() const { return m_identity; }
    [[nodiscard]] QString prompt() const { return m_prompt; }
    [[nodiscard]] bool echo() const { return m_echo; }
    [[nodiscard]] QString error() const { return m_error; }
    [[nodiscard]] bool isBusy() const { return m_isBusy; }

    Q_INVOKABLE void submitResponse(const QString& response);
    Q_INVOKABLE void cancel();

    void initiateAuthentication(
        const QString& actionId,
        const QString& message,
        const QString& iconName,
        const PolkitQt1::Details& details,
        const QString& cookie,
        const PolkitQt1::Identity::List& identities,
        PolkitQt1::Agent::AsyncResult* result) override;

    bool initiateAuthenticationFinish() override;
    void cancelAuthentication() override;

signals:
    void activeChanged();
    void requestChanged();
    void promptChanged();
    void errorChanged();
    void busyChanged();
    void authSuccess();
    void authFailed(const QString& reason);

private slots:
    void onSessionRequest(const QString& request, bool echo);
    void onSessionCompleted(bool gainedAuthorization);
    void onSessionShowError(const QString& text);
    void onSessionShowInfo(const QString& text);

private:
    void cleanupSession();

    bool m_active = false;
    bool m_isBusy = false;
    bool m_echo = false;
    QString m_actionId;
    QString m_message;
    QString m_iconName;
    QString m_identity;
    QString m_prompt;
    QString m_error;
    QString m_cookie;

    QPointer<PolkitQt1::Agent::Session> m_session;
    PolkitQt1::Agent::AsyncResult* m_asyncResult = nullptr;
    PolkitQt1::Identity::List m_identities;
};

}
