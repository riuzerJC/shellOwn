pragma Singleton

import QtQuick
import qs.modules.servicespanel.core as ServicesPanelCore

QtObject {
    readonly property var serviceEntries: ServicesPanelCore.ServiceOrchestrator.serviceEntries

    function transformSearch(search: string): string {
        return ServicesPanelCore.ServiceOrchestrator.transformSearch(search);
    }

    function query(search: string): list<QtObject> {
        return ServicesPanelCore.ServiceOrchestrator.query(search);
    }

    function setModeActive(active: bool): void {
        ServicesPanelCore.ServiceOrchestrator.setPanelVisible(active);
    }

    function setSimulationHooks(hooks: var): void {
        ServicesPanelCore.ServiceOrchestrator.setSimulationHooks(hooks);
    }

    function clearSimulationHooks(): void {
        ServicesPanelCore.ServiceOrchestrator.clearSimulationHooks();
    }

    function refreshVisible(): void {
        ServicesPanelCore.ServiceOrchestrator.refreshVisible();
    }

    function startServiceById(serviceId: string): void {
        ServicesPanelCore.ServiceOrchestrator.startServiceById(serviceId);
    }

    function stopServiceById(serviceId: string): void {
        ServicesPanelCore.ServiceOrchestrator.stopServiceById(serviceId);
    }

    function probeServiceById(serviceId: string): void {
        ServicesPanelCore.ServiceOrchestrator.probeServiceById(serviceId);
    }

    function reload(): void {
        ServicesPanelCore.ServiceOrchestrator.reload();
    }
}
