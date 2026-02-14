package e2e

const (
	actionRegisterDevice         = "register_device"
	actionFetchDashboard         = "fetch_dashboard"
	actionCreateRecord           = "create_record"
	actionUpdateRecord           = "update_record"
	actionLogout                 = "logout"
	actionRuntimeRegisterDevice  = "runtime_register_device"
	actionRuntimeCheckDomain     = "runtime_check_domain"
	actionRuntimeApproveDevice   = "runtime_approve_device"
	actionRuntimeCreateAlertRule = "runtime_create_alert_rule"
	actionRuntimeQueuePayloadRef = "runtime_queue_payload_ref_command"
	actionRuntimeMissingPayload  = "runtime_expect_missing_payload_ref"
	actionRuntimeRejectCmdResult = "runtime_reject_invalid_command_results"
	actionRuntimePollWithScripts = "runtime_poll_with_scripts"
	actionRuntimeVerifyTelemetry = "runtime_verify_telemetry"
	actionRuntimeCreateReport    = "runtime_create_report"
	actionRuntimeVerifyReport    = "runtime_verify_report"
	actionRuntimeVerifyAlert     = "runtime_verify_alert"
	actionRuntimeCleanup         = "runtime_cleanup"

	journeyLogout = actionLogout
)
