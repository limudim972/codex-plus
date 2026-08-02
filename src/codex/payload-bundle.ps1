function Get-CodexPlusPayloadBundle {
    @(
        Get-CodexRtlSharedPayload
        Get-CodexNewChatButtonPayload
        Get-CodexRtlPayload
        Get-CodexRtlPayloadPlan
        Get-CodexContextBadgePayload
        Get-CodexFullAccessReminderHiderPayload
        Get-CodexActivityOnboardingHiderPayload
        Get-CodexSplitModelEffortSelectorPayload
        Get-CodexProjectSelectorGuardPayload
        Get-CodexSidebarPagingPayload
        Get-CodexNewWindowButtonPayload
        Get-CodexAutoContinuePayload
    ) -join "`n"
}
