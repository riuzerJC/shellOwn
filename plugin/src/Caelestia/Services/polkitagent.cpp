#include "polkitagent.hpp"

#include <qloggingcategory.h>

#include <polkitqt1-identity.h>
#include <polkitqt1-subject.h>
#include <unistd.h>

Q_LOGGING_CATEGORY(lcPolkit, "caelestia.services.polkit", QtInfoMsg)

namespace caelestia::services {

PolkitAgent::PolkitAgent(QObject* parent)
    : PolkitQt1::Agent::Listener(parent) {
    PolkitQt1::UnixProcessSubject subject(static_cast<qint64>(getpid()));
    const bool registered = registerListener(subject, QStringLiteral("/org/caelestia/PolicyKit1/AuthenticationAgent"));
    if (registered) {
        qCInfo(lcPolkit) << "Caelestia Polkit authentication agent registered successfully.";
    } else {
        qCWarning(lcPolkit) << "Failed to register Caelestia Polkit authentication agent.";
    }
}

PolkitAgent::~PolkitAgent() {
    cleanupSession();
}

void PolkitAgent::initiateAuthentication(const QString& actionId, const QString& message, const QString& iconName,
    const PolkitQt1::Details& /*details*/, const QString& cookie, const PolkitQt1::Identity::List& identities,
    PolkitQt1::Agent::AsyncResult* result) {
    cleanupSession();

    m_actionId = actionId;
    m_message = message;
    m_iconName = iconName.isEmpty() ? QStringLiteral("dialog-password") : iconName;
    m_cookie = cookie;
    m_identities = identities;
    m_asyncResult = result;
    m_error.clear();
    m_isBusy = false;

    if (!m_identities.isEmpty()) {
        m_identity = m_identities.first().toString();
    } else {
        m_identity = QStringLiteral("root");
    }

    if (!m_identities.isEmpty()) {
        m_session = new PolkitQt1::Agent::Session(m_identities.first(), m_cookie, m_asyncResult, this);
        connect(m_session, &PolkitQt1::Agent::Session::request, this, &PolkitAgent::onSessionRequest);
        connect(m_session, &PolkitQt1::Agent::Session::completed, this, &PolkitAgent::onSessionCompleted);
        connect(m_session, &PolkitQt1::Agent::Session::showError, this, &PolkitAgent::onSessionShowError);
        connect(m_session, &PolkitQt1::Agent::Session::showInfo, this, &PolkitAgent::onSessionShowInfo);

        m_session->initiate();
    }

    m_active = true;
    emit activeChanged();
    emit requestChanged();
    emit errorChanged();
    emit busyChanged();
}

bool PolkitAgent::initiateAuthenticationFinish() {
    return true;
}

void PolkitAgent::cancelAuthentication() {
    cleanupSession();
}

void PolkitAgent::submitResponse(const QString& response) {
    if (!m_session.isNull()) {
        m_isBusy = true;
        emit busyChanged();
        m_session->setResponse(response);
    }
}

void PolkitAgent::cancel() {
    if (!m_session.isNull()) {
        m_session->cancel();
    }
    cleanupSession();
}

void PolkitAgent::onSessionRequest(const QString& request, bool echo) {
    m_prompt = request.trimmed();
    if (m_prompt.endsWith(QLatin1Char(':'))) {
        m_prompt.chop(1);
        m_prompt = m_prompt.trimmed();
    }
    m_echo = echo;
    m_isBusy = false;
    emit promptChanged();
    emit busyChanged();
}

void PolkitAgent::onSessionCompleted(bool gainedAuthorization) {
    m_isBusy = false;
    emit busyChanged();

    if (gainedAuthorization) {
        emit authSuccess();
        cleanupSession();
    } else {
        if (m_error.isEmpty()) {
            m_error = tr("Authentication failed. Please check your password.");
            emit errorChanged();
        }
        emit authFailed(m_error);
    }
}

void PolkitAgent::onSessionShowError(const QString& text) {
    m_error = text;
    m_isBusy = false;
    emit errorChanged();
    emit busyChanged();
}

void PolkitAgent::onSessionShowInfo(const QString& text) {
    qCInfo(lcPolkit) << "Polkit info:" << text;
}

void PolkitAgent::cleanupSession() {
    if (!m_session.isNull()) {
        m_session->deleteLater();
        m_session.clear();
    }

    m_active = false;
    m_isBusy = false;
    m_prompt.clear();
    m_error.clear();
    m_actionId.clear();
    m_message.clear();
    m_identity.clear();
    m_cookie.clear();
    m_asyncResult = nullptr;

    emit activeChanged();
    emit requestChanged();
    emit promptChanged();
    emit errorChanged();
    emit busyChanged();
}

} // namespace caelestia::services
